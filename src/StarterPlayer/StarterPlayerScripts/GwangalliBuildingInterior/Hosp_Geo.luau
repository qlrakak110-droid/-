--!strict
-- GwangalliBuildingInterior/Hosp_Geo: 광안 메디컬 의원 시설 레이어(HospitalPlus)의 순수 데이터.
--   require 없음 (HospitalPlus 최상단이 yield 없이 keep 을 등록할 수 있게).
--   좌표는 전부 병원 프레임 HF 기준 (설계 문서 §1):
--     원점 = 1F 바닥 윗면 (월드 -515, 6.9, 300), +X = 동쪽(구급차 베이), +Z = 북쪽(뒷마당), +Y = 위.
--     1F 바닥 0, 2F 바닥 14.15, 옥상 25.20. 1 스터드 ≈ 0.28 m.

local Geo = {}

local V3 = Vector3.new

Geo.HF = CFrame.new(-515, 6.9, 300) * CFrame.Angles(0, math.rad(-1.8747), 0)
Geo.CENTER = V3(-515, 7, 300)

function Geo.W(x: number, y: number, z: number): Vector3
	return Geo.HF * V3(x, y, z)
end
function Geo.L(p: Vector3): Vector3
	return Geo.HF:PointToObjectSpace(p)
end

-- 층 높이 (바닥 윗면, 로컬 y)
Geo.LEVELS = { 0, 14.15, 25.20 }
Geo.LEVEL_LABEL = { "1", "2", "R" }
Geo.CEIL1 = 11.0 -- 1F 천장판 아래면
Geo.CEIL2 = 22.6 -- 2F 천장판 아래면
Geo.ROOF = 25.2

-- 거리 (월드, 평면)
Geo.BUILD_R = 140 -- 이 안에 들어오면 짓기
Geo.TEAR_R = 170 -- 이보다 멀어지면 치우기
Geo.ROOF_R = 90 -- 옥상 정원은 더 가까울 때만 (또는 2F 이상)

-- 맵 부품 기대 위치 검증 (GroundBack 중심). 0.5 이상 어긋나면 HF 를 실제 파트 기준으로 다시 잡음
Geo.GB_LOCAL = V3(-0.09, 6.30, 39.18)

-- 다른 매장 · 방 빌더가 비워 둘 월드 공간 (설계 §6). 월드 AABB.
Geo.KEEPS = {
	{ id = "K01", kind = "facility_room", min = V3(-575.53, 6.90, 324.65), max = V3(-551.75, 17.95, 337.58) },
	{ id = "K02", kind = "facility", min = V3(-568.24, 6.90, 322.27), max = V3(-559.16, 14.90, 325.17) },
	{ id = "K03", kind = "facility_room", min = V3(-552.65, 6.90, 329.79), max = V3(-543.80, 17.95, 337.85) },
	{ id = "K04", kind = "facility", min = V3(-551.99, 6.90, 326.41), max = V3(-550.48, 14.90, 329.85) },
	{ id = "K05", kind = "opening", min = V3(-531.26, 6.90, 334.49), max = V3(-525.34, 16.90, 338.46) },
	{ id = "K06", kind = "opening", min = V3(-541.26, 6.90, 334.16), max = V3(-535.33, 16.90, 338.13) },
	{ id = "K07", kind = "opening", min = V3(-461.63, 6.90, 327.97), max = V3(-456.78, 16.90, 335.52) },
	{ id = "K08", kind = "facility", min = V3(-456.22, 6.50, 327.55), max = V3(-450.37, 16.90, 335.72) },
	{ id = "K09", kind = "opening", min = V3(-461.48, 6.90, 311.17), max = V3(-456.23, 17.95, 321.72) },
	{ id = "K10", kind = "facility", min = V3(-455.79, 6.50, 310.46), max = V3(-446.81, 19.50, 322.73) },
	{ id = "K12", kind = "opening", min = V3(-541.41, 6.90, 292.13), max = V3(-532.46, 15.50, 294.02) },
	{ id = "K13", kind = "opening", min = V3(-489.26, 6.90, 297.94), max = V3(-480.42, 15.50, 299.53) },
	{ id = "K14", kind = "facility", min = V3(-537.82, 11.40, 293.43), max = V3(-529.50, 16.90, 294.32) },
	{ id = "K15", kind = "opening", min = V3(-501.29, 21.05, 289.54), max = V3(-492.46, 29.50, 291.13) },
	{ id = "K16", kind = "opening", min = V3(-541.27, 21.05, 288.24), max = V3(-532.33, 29.50, 289.83) },
	{ id = "K17", kind = "opening", min = V3(-551.46, 21.05, 293.91), max = V3(-534.53, 29.50, 295.76) },
	{ id = "K18", kind = "facility_room", min = V3(-552.65, 21.05, 329.79), max = V3(-543.80, 29.50, 338.01) },
	{ id = "K19", kind = "facility", min = V3(-544.26, 23.50, 337.46), max = V3(-535.65, 28.90, 338.28) },
	{ id = "K20", kind = "opening", min = V3(-523.10, 21.05, 293.74), max = V3(-516.80, 29.50, 300.13) },
	{ id = "K21", kind = "opening", min = V3(-524.36, 21.05, 334.22), max = V3(-519.43, 29.50, 338.81) },
	{ id = "K22", kind = "facility_room", min = V3(-552.85, 32.10, 329.29), max = V3(-543.58, 42.10, 337.95) },
	{ id = "K23", kind = "facility", min = V3(-491.45, 14.50, 322.96), max = V3(-489.64, 16.30, 323.29) },
}

-- Law/Hospital NPC 지점 (로컬 x, z) — 서버 SPOTS 를 HF 로 옮긴 값 (설계 §2.12)
Geo.LIFT_SPOT = V3(-31.9, 0, 33.1) -- lift1 (1F) = lift2 (2F) 같은 xz
Geo.PROMPT_DESK = V3(-0.12, 2.5, -18.81) -- HospitalPrompt_desk
Geo.PROMPT_DOCTOR = V3(-40.07, 2.5, -19.80) -- HospitalPrompt_doctor
Geo.TRANSIT = V3(49.82, 2.70, 2.87) -- Ems Patients.TRANSIT

-- T_clinic LANES1 / LANES2 (월드 xz). 엘리베이터 지점(-548, 332) 앞 4 스터드는 우리 문이라 잘라 냄
Geo.LANES1 = {
	{ { -496, 252 }, { -496, 270 }, { -505, 276 }, { -515, 281 } },
	{ { -505, 276 }, { -503, 284 } },
	{ { -505, 276 }, { -466, 275 } },
	{ { -505, 276 }, { -466, 281 } },
	{ { -505, 276 }, { -480, 284 }, { -466, 287 } },
	{ { -505, 276 }, { -497, 291 }, { -505, 300 } },
	{ { -505, 300 }, { -525, 294 }, { -540, 294 } },
	{ { -525, 294 }, { -537, 297 }, { -534.9, 292.5 }, { -545, 285 } },
	{ { -505, 300 }, { -485, 296 }, { -487, 298.8 }, { -478, 308 }, { -468, 309 } },
	{ { -505, 300 }, { -510, 323 }, { -520, 328 }, { -548, 332 } },
}
Geo.LANES2 = {
	{ { -548, 332 }, { -552, 312 }, { -543, 298 }, { -538.9, 295 }, { -540, 294 }, { -520, 290 } },
	{ { -548, 332 }, { -543, 298 } },
	{ { -540, 294 }, { -537, 292 }, { -534.75, 289.2 }, { -550, 281 }, { -540, 281 } },
	{ { -520, 290 }, { -497, 293 }, { -494.8, 290.5 }, { -480, 283 }, { -466, 282 } },
	{ { -520, 290 }, { -525.5, 290 }, { -525.5, 284 }, { -515, 284 } },
	{ { -520, 290 }, { -503.5, 290 }, { -503.5, 284 }, { -515, 284 } },
	{ { -497, 293 }, { -478.6, 296 }, { -478, 311 } },
}

-- 우리 Kit 의 안전 keep (로컬 상자): NPC 통로 · 서버 프롬프트 · 침대 · 계단 · 자동문 · TRANSIT
local function laneKeeps(out: { any }, lanes: { any }, floorY: number)
	local liftW = Geo.W(Geo.LIFT_SPOT.X, 0, Geo.LIFT_SPOT.Z)
	local hw = 1.25
	for _, line in lanes do
		for i = 1, #line - 1 do
			local a = Geo.L(V3(line[i][1], 6.9, line[i][2]))
			local b = Geo.L(V3(line[i + 1][1], 6.9, line[i + 1][2]))
			a = V3(a.X, 0, a.Z)
			b = V3(b.X, 0, b.Z)
			local len = (b - a).Magnitude
			local n = math.max(1, math.ceil(len / 1.0))
			for k = 0, n do
				local p = a:Lerp(b, k / n)
				local pw = Geo.W(p.X, 0, p.Z)
				if V3(pw.X - liftW.X, 0, pw.Z - liftW.Z).Magnitude > 4.0 then
					table.insert(out, { min = V3(p.X - hw, floorY + 0.1, p.Z - hw), max = V3(p.X + hw, floorY + 6.5, p.Z + hw), kind = "lane" })
				end
			end
		end
	end
end

local function sphereKeep(out: { any }, c: Vector3, r: number, h: number, kind: string)
	table.insert(out, { min = V3(c.X - r, c.Y - 1, c.Z - r), max = V3(c.X + r, c.Y + h, c.Z + r), kind = kind })
end

Geo.SAFE_KEEPS = {} :: { any }
laneKeeps(Geo.SAFE_KEEPS, Geo.LANES1, 0)
laneKeeps(Geo.SAFE_KEEPS, Geo.LANES2, 14.15)
sphereKeep(Geo.SAFE_KEEPS, Geo.PROMPT_DESK, 1.4, 4, "point")
sphereKeep(Geo.SAFE_KEEPS, Geo.PROMPT_DOCTOR, 1.4, 4, "point")
sphereKeep(Geo.SAFE_KEEPS, Geo.TRANSIT, 2.0, 5, "point")
-- 계단 (17 단, 1F → 2F) 부피
table.insert(Geo.SAFE_KEEPS, { min = V3(-3.33, 0, 24.6), max = V3(19.31, 21, 35.5), kind = "stair" })
-- 정문 자동문 (AutoDoor_Hospital)
table.insert(Geo.SAFE_KEEPS, { min = V3(13.4, 0, -37), max = V3(22.4, 9, -31), kind = "door" })
-- 서버 침대 BedSeat (태그 HospitalBed 8 개, 월드 좌석 위치 → 로컬). 침대 주변은 우리 장식이 비켜 감.
-- 실제 좌석이 스트리밍되어 있으면 HospitalPlus 가 시작할 때 그 상자도 더함 (Geo.addBedKeep)
Geo.BED_SPOTS = {} :: { Vector3 }
for _, w in {
	V3(-569.6, 8.8, 283.2), -- ExamBed (진료실 1)
	V3(-465.3, 8.8, 308.6), -- TreatBed1 (= Ems TRANSIT)
	V3(-479.3, 8.8, 308.1), -- TreatBed2
	V3(-566.1, 22.9, 329.3), -- CheckupBed (2F)
	V3(-466.5, 22.9, 279.1), -- 201 A
	V3(-488.5, 22.9, 278.3), -- 201 B
	V3(-540.2, 22.9, 276.6), -- 202 A
	V3(-562.2, 22.9, 275.9), -- 202 B
} do
	local l = Geo.L(w)
	table.insert(Geo.BED_SPOTS, l)
	sphereKeep(Geo.SAFE_KEEPS, l, 2.2, 4.5, "bed")
end
-- 실제 BedSeat 파트 상자 (로컬 AABB) + 둘레 0.6, 위 4
function Geo.addBedKeep(mn: Vector3, mx: Vector3)
	table.insert(Geo.SAFE_KEEPS, { min = mn - V3(0.6, 0.2, 0.6), max = mx + V3(0.6, 4, 0.6), kind = "bed" })
end

-- 맵 부품 찾기 사양. root = "main" (광안 메디컬 의원) | "bld" (광안 메디컬 의원 (건물))
Geo.PARTS = {
	groundBack = { root = "main", path = {}, name = "GroundBack", c = V3(-0.09, 6.30, 39.18) },
	groundEast = { root = "main", path = {}, name = "GroundSide", c = V3(59.51, 6.30, 2.18) },
	backWall2 = { root = "main", path = { "2F" }, name = "BackWall2", c = V3(12.91, 18.375, -4.12) },
	fireExitDoor = { root = "main", path = { "1F", "BackZone" }, name = "FireExitDoor", c = V3(59.21, 4.0, 29.58) },
	pushBar = { root = "main", path = { "1F", "BackZone" }, name = "PushBar", c = V3(58.91, 4.0, 28.58) },
	roofDoor = { root = "bld", path = {}, name = "RoofDoor", c = V3(38.13, 28.70, -2.17) },
	checkupGuide = { root = "main", path = { "2F", "CheckupCenter" }, name = "Sign_건강검진 안내", c = V3(-30.09, 21.95, 38.74) },
}
-- 1F 가짜 엘리베이터 (전부 숨김)
Geo.FAKE_LIFT = { "ElevatorJamb", "ElevatorHead", "ElevatorDoor", "FloorIndicator", "CallButton", "Sign_엘리베이터" }
-- 1F 뒷벽 가짜 문 모델 (전부 숨김)
Geo.FAKE_DOORS = { "Door_남자 화장실", "Door_여자 화장실", "Door_STAFF ONLY", "Door_창고" }

-- 유리 미닫이 방문 (설계 §2.9). x0..x1 = 개구부(문틀 안쪽면), z = 문짝 면(맵 문짝과 같은 면), slide = 열리는 방향(x 부호),
-- y = 바닥 높이, cz = 복도 쪽 벽면 z, cn = 복도 쪽 법선 z 부호, wide = 2 짝 연동 (건강검진센터 8 폭)
Geo.GLASS_DOORS = {
	{ id = "consult", model = "Door_진료실 1 · 내과", floorName = "1F", x0 = -22.09, x1 = -18.09, z = -6.59, slide = -1, y = 0, room = "진료실 1 · 내과", sub = "Internal Medicine", cz = -5.82, cn = 1 },
	{ id = "treat", model = "Door_주사실 · 처치실", floorName = "1F", x0 = 25.91, x1 = 29.91, z = -2.59, slide = 1, y = 0, room = "주사실 · 처치실", sub = "Injection · Treatment", cz = -2.42, cn = -1 },
	{ id = "w201", model = "Door_입원실 201", floorName = "2F", x0 = 17.91, x1 = 21.91, z = -10.59, slide = -1, y = 14.15, room = "201호 입원실", sub = "Ward 201", cz = -9.82, cn = 1 },
	{ id = "w202", model = "Door_입원실 202", floorName = "2F", x0 = -22.09, x1 = -18.09, z = -10.59, slide = -1, y = 14.15, room = "202호 입원실", sub = "Ward 202", cz = -9.82, cn = 1 },
	{ id = "check", model = "Door_건강검진센터", floorName = "2F", x0 = -28.09, x1 = -20.09, z = -4.59, slide = -1, y = 14.15, room = "건강검진센터", sub = "Health Check-up", cz = -4.42, cn = -1, wide = true },
}

-- 엘리베이터 (설계 §7.3)
Geo.LIFT = {
	x0 = -35.90, x1 = -28.30, -- 승강로 외곽
	front = 33.30, -- 홀 쪽 마감면 z
	openX0 = -33.69, openX1 = -30.49, -- 출입구
	doorH = 7.20,
	pivot = V3(-32.09, 0, 36.10), -- 카 바닥 가운데 (y = 층 높이)
	cabin = { x0 = -34.95, x1 = -29.25, z0 = 33.30, z1 = 38.45 }, -- 카 안 판정 상자
	doorway = { x0 = -33.8, x1 = -30.4, z0 = 33.0, z1 = 34.2 },
	backZ = { 38.78, 38.94, 38.46 }, -- 층별 뒷벽 안쪽면 (옥상 탑 뒷벽은 파라펫 38.87 앞)
	height = { 10.85, 8.30, 9.30 }, -- 층별 승강로 마감 높이
}

-- 숨은 방 (설계 §2.16): 병원 바로 아래 y -50
Geo.PORTAL_Y = -50
Geo.ROOMS = {
	staff = {
		label = "직원 휴게실",
		box = { min = V3(-24.4, -50.6, 21.6), max = V3(-1.6, -40.9, 36.4) },
		inside = CFrame.lookAt(V3(-12.1, -50, 24.6), V3(-12.1, -50, 30)), -- 방 안 도착점 (+z 를 봄)
		hall = CFrame.lookAt(V3(-12.09, 0, 35.6), V3(-12.09, 0, 30)), -- 1F 후면 홀 돌아오는 점 (-z 를 봄)
		hallDoor = V3(-12.09, 3.8, 38.78),
		roomDoor = V3(-12.1, -46.2, 22.0),
	},
	store = {
		label = "창고",
		box = { min = V3(-30.4, -50.6, 1.6), max = V3(-14.6, -40.9, 14.4) },
		inside = CFrame.lookAt(V3(-22.1, -50, 4.6), V3(-22.1, -50, 10)),
		hall = CFrame.lookAt(V3(-22.09, 0, 35.6), V3(-22.09, 0, 30)),
		hallDoor = V3(-22.09, 3.8, 38.78),
		roomDoor = V3(-22.1, -46.2, 2.0),
	},
	stair = {
		label = "비상계단",
		box = { min = V3(-10.4, -50.6, -24.4), max = V3(-1.0, -30.0, -6.6) },
		inside = CFrame.lookAt(V3(-8.0, -50, -21.6), V3(-8.0, -50, -15)), -- 아래(2F) 문 안쪽
		insideTop = CFrame.lookAt(V3(-3.4, -38.95, -21.6), V3(-3.4, -38.95, -15)), -- 위(RF) 문 안쪽
		hall = CFrame.lookAt(V3(-5.95, 14.15, 36.0), V3(-5.95, 14.15, 30)), -- 2F 계단홀 문 앞
		roof = CFrame.lookAt(V3(38.13, 25.2, -4.8), V3(38.13, 25.2, -10)), -- 옥상 RoofDoor 앞
		hallDoor = V3(-5.95, 17.8, 38.94),
		roofDoor = V3(38.13, 28.7, -2.3),
		roomDoor = V3(-8.0, -46.4, -24.0),
		roomDoorTop = V3(-3.4, -35.3, -24.0),
	},
}

-- 팔레트 (T_clinic 과 같은 값)
local C3 = Color3.fromRGB
Geo.C = {
	TEAL = C3(0, 128, 118),
	TEAL_D = C3(0, 92, 86),
	MINT = C3(196, 232, 226),
	MINT_L = C3(228, 245, 241),
	WHITE = C3(250, 250, 248),
	INK = C3(30, 34, 38),
	GREY_T = C3(96, 102, 108),
	RED = C3(206, 36, 40),
	NAVY = C3(28, 50, 92),
	GREEN_EXIT = C3(0, 150, 80),
	PLASTER = C3(222, 218, 208),
	PORCELAIN = C3(246, 246, 243),
	AMBER = C3(255, 176, 60),
}

-- 소리 (이 게임에서 이미 쓰는 기본 내장 소리)
Geo.SND = {
	chime = "rbxasset://sounds/electronicpingshort.wav",
	click = "rbxasset://sounds/clickfast.wav",
	swoosh = "rbxasset://sounds/swoosh.wav",
	water = "rbxasset://sounds/action_swim.mp3",
	flush = "rbxasset://sounds/impact_water.mp3",
	wind = "rbxasset://sounds/action_falling.mp3",
	thunk = "rbxasset://sounds/action_jump_land.mp3",
	switch = "rbxasset://sounds/switch.wav",
}
Geo.TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

-- 영역 예산 (high / mid / low): parts, lights
-- (오프라인 측정: high 129 / 166 / 404 / 195 / 35 / 478 / 방 최대 396 개 + 여유)
Geo.BUDGET = {
	exits = { high = 160, mid = 150, low = 130, lights = 2 },
	lift = { high = 200, mid = 200, low = 150, lights = 1 },
	hall1 = { high = 440, mid = 420, low = 300, lights = 2 },
	doors = { high = 230, mid = 230, low = 200, lights = 0 },
	level2 = { high = 60, mid = 60, low = 40, lights = 0 },
	roof = { high = 520, mid = 400, low = 180, lights = 2 },
	portal = { high = 430, mid = 390, low = 260, lights = 2 },
}

return Geo
