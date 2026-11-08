--!strict
-- SeoulSkyline / ShowHome
-- 한강뷰 101동 — 강변북로 바로 뒤(가까운 쪽 도시 지면)에 선 28층 판상형 아파트 1동 + 걸어 들어가 볼 수 있는 실내.
-- 실제 스케일 1 stud = 0.3 m: 이 파일의 모든 치수는 m 로 적고 Config.m(미터) 로 변환합니다.
--
--   * 동: 4호 라인(세대 폭 12.6 m) × 깊이 9.85 m + 뒤로 돌출된 계단실 코어 2개(4.8 m). 1층 4.5 m(필로티 + 로비),
--     2~28층 층고 2.9 m(Config.Real.HomeFloor), 옥상 파라펫까지 84 m. 앞면(-Z, 강 쪽) = 발코니.
--     외관은 Facade "apartment" 언어(층 슬래브 띠 · 세대 벽 핀 · 층 묶음 Neon 조명 코어 · 측벽 동 번호/슈퍼그래픽)에
--     한강변 신축 단지의 유리 난간을 더함. 20층 1호 라인(2001호)만 조명 코어/난간/뒤 띠를 비우고 진짜 실내로 지음.
--   * 1층 로비(1·2호 라인 코어): 자동 유리문(열린 상태) + 공동현관 키패드, 대리석 바닥, 우편함 54칸(201~2802호),
--     엘리베이터 2대(태그 SeoulElevator → 20층 엘리베이터 홀), 관리사무소 공지 게시판, 무인택배함, 비상구 계단 문.
--   * 20층 엘리베이터 홀: 2001호(밖여닫이 현관문 열림) / 2002호, 엘리베이터 2대(SeoulElevator → 1층 로비), 소화전, 비상구.
--   * 2001호(34평형, 전용 84 m²): 현관(0.15 m 단차, 신발장) · 거실(아트월, 65" TV, 소파 좌면 0.43 m) · 식당(4인 식탁
--     0.75 m, 펜던트) · 주방(ㄱ자 0.9 m 상판, 개수대, 인덕션, 후드, 냉장고 1.8 m, 아일랜드) · 안방(퀸 침대 0.45 m, 협탁,
--     붙박이장, 책상) · 욕실(타일, 세면대, 거울, 샤워 유리, 양변기) · 서재(1.8 m 책장) · 유리 난간 발코니(라운지 체어).
--     거실/발코니에서 정면(-Z, 약간 왼쪽)으로 한강 너머 잠실 타워가 보이는 것이 히어로 뷰.
--   * 바닥 슬래브는 외피(Persistent) 모델에 있어 실내(Atomic 스트리밍)가 늦게 로드돼도 엘리베이터 도착 지점에 발판이 있음.
--   * 발자국 Kit.reserveRect(조경 포함) → Apartments 가 이 자리를 비움. 파트 ≤ 3500, 광원 ≤ 40.

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local ShowHome = {}

local rgb = Color3.fromRGB
local P = Config.Palette
local R = Config.Real
local M = Config.m
local MAT = Enum.Material
local NID = Enum.NormalId
local MPS = Config.METERS_PER_STUD

local function toM(studs: number): number
	return studs * MPS
end

------------------------------------------------------------------------------------------------------
-- 상수 (m)
------------------------------------------------------------------------------------------------------
local PART_BUDGET = 3500
local MAX_LIGHTS = 40

local FH = toM(R.HomeFloor) -- 층고 2.9
local DOOR_H = toM(R.Door) -- 문 높이 2.1
local CEIL_H = toM(R.HomeCeiling) -- 천장고 2.3
local COUNTER = toM(R.Counter) -- 주방 상판 0.9
local TABLE_H = toM(R.Table) -- 식탁/책상 0.75
local SEAT = toM(R.Seat) -- 좌면 0.43
local DOOR_W = 0.9
local EYE = 1.56 -- 눈높이 5.2 stud

local LINE_W = 12.6 -- 세대(호 라인) 폭
local NLINES = 4
local BL = LINE_W * NLINES -- 50.4
local END_T = 0.35 -- 측벽 두께
local DEPTH = 9.85 -- 앞 난간선(z=0) → 뒤 외벽면
local FIN_T = 0.4 -- 세대 벽(핀) 두께
local FLOORS = 28
local LOBBY_H = 4.5 -- 1층(필로티/로비) 층고
local UNIT_FL = 20 -- 실내를 만든 층
local SLAB_DN, SLAB_UP = 0.1, 0.25 -- 층 기준선 아래/위 슬래브 두께
local CORE_A0, CORE_A1 = 6.0, 19.2 -- 1·2호 라인 코어(로비/엘리베이터 홀) X
local CORE_B0, CORE_B1 = 31.2, 44.4 -- 3·4호 라인 코어
local CORE_SPLIT, CORE_Z1 = 12.25, 14.65 -- 홀 | 승강로·계단 경계, 코어 뒷면
local FRONT_SET = 27 -- 도시 지면 시작(CityFrom) → 건물 앞면 (조경 + 진입로)
local RES_X0, RES_X1, RES_Z0, RES_Z1 = -20, 62, -27, 17 -- 예약(로컬 m): 앞쪽은 넓게(전망 확보)

local function yb(k: number): number -- k 층 기준선(구조 슬래브 중심 위쪽 기준)
	return LOBBY_H + (k - 2) * FH
end
local YB = yb(UNIT_FL) -- 56.7
local SLAB_TOP = YB + SLAB_UP -- 56.95 구조 슬래브 윗면
local HF = SLAB_TOP + 0.05 -- 57.00 엘리베이터 홀·현관 바닥
local UF = HF + 0.15 -- 57.15 세대 마감 바닥(현관 단차 0.15 m)
local CEIL = UF + CEIL_H -- 59.45 세대 천장
local TOPY = yb(UNIT_FL + 1) - SLAB_DN -- 59.50 위층 슬래브 아랫면
local ROOF = yb(FLOORS + 1) + SLAB_UP -- 83.05 옥상 슬래브 윗면
local PARAPET = ROOF + 1.05
local CORE_TOP = ROOF + 3.0 -- 승강기 기계실
local LOBBY_FL = 0.15
local LOBBY_CEIL = 3.9
local LOBBY_TOP = LOBBY_H - SLAB_DN -- 4.4 (2층 슬래브 아랫면)
local PAVE = 0.06
local HALL_CEIL = HF + 2.35

-- 색 / 재질
local WALL_EXT = rgb(226, 220, 208) -- 외벽 크림
local WALL_CORE = rgb(206, 200, 190)
local ACCENT = rgb(58, 104, 158) -- 측벽 슈퍼그래픽
local RAIL_GLASS = rgb(150, 178, 196)
local STEEL = rgb(184, 186, 190)
local STEEL_D = rgb(66, 68, 74)
local BRONZE = rgb(96, 84, 70)
local PLASTER = rgb(238, 234, 226)
local CEIL_C = rgb(244, 242, 238)
local OAK = rgb(172, 134, 96)
local OAK_L = rgb(196, 162, 122)
local WALNUT = rgb(96, 70, 52)
local WHITE_LAC = rgb(236, 234, 230)
local MARBLE_W = rgb(228, 224, 216)
local MARBLE_G = rgb(158, 154, 148)
local MARBLE_D = rgb(66, 64, 62)
local LIMESTONE = rgb(214, 206, 192)
local STONE_L = rgb(222, 214, 200) -- 실내 석재 패널(밝은 웜 대리석)
local TILE_W = rgb(228, 226, 220)
local TILE_D = rgb(104, 102, 100)
local SOFA_C = rgb(176, 170, 160)
local BENCH_WOOD = rgb(118, 88, 62)
local LINEN = rgb(238, 234, 224)
local GLASS_C = rgb(178, 202, 218)
local OFF_C = rgb(44, 46, 54)
local PANEL_WARM = rgb(214, 188, 146) -- 매입등(Neon, 은은한 3000K)
local PANEL_COOL = rgb(206, 214, 226)
local LAMP = rgb(255, 206, 150)
local SCREEN = rgb(64, 112, 160)
local INK = rgb(40, 40, 44)
local LEAVES = { rgb(60, 102, 56), rgb(74, 118, 62), rgb(54, 92, 54), rgb(84, 126, 66), rgb(50, 86, 54) }
local BOOK_COLORS = {
	rgb(150, 52, 44),
	rgb(42, 70, 110),
	rgb(212, 196, 160),
	rgb(60, 92, 70),
	rgb(30, 30, 34),
	rgb(196, 140, 60),
	rgb(110, 84, 120),
	rgb(232, 228, 216),
	rgb(176, 92, 64),
	rgb(84, 110, 130),
}

------------------------------------------------------------------------------------------------------
-- 좌표 / 파트 보조
--   로컬 좌표(m): x = 서쪽 측벽 안쪽면에서 +X, y = 도시 지면에서 위, z = 앞 난간선에서 +Z(뒤, 도시 쪽).
--   건물은 회전 없이 놓이므로 로컬 → 월드 = 평행 이동 + m→stud.
------------------------------------------------------------------------------------------------------
local X0, Z0, GY = 0, 0, 0
local partsAtStart = 0
local lightsUsed = 0

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(X0 + M(x), GY + M(y), Z0 + M(z))
end
local function LCF(x: number, y: number, z: number): CFrame
	return CFrame.new(V(x, y, z))
end
local function SZ(x: number, y: number, z: number): Vector3
	return Vector3.new(M(x), M(y), M(z))
end
local function mcf(x: number, y: number, z: number): CFrame
	return CFrame.new(M(x), M(y), M(z))
end
-- 로컬 프레임(가구): yaw 0 = 앞(-Z)을 봄, -90 = +X 를 봄, 90 = -X 를 봄, 180 = +Z 를 봄
local function frameAt(x: number, y: number, z: number, yawDeg: number?): CFrame
	return LCF(x, y, z) * CFrame.Angles(0, math.rad(yawDeg or 0), 0)
end

local function used(): number
	return Kit.stats.parts - partsAtStart
end
local function room(n: number): boolean
	return used() + n <= PART_BUDGET
end

-- 축 정렬 박스: 로컬 m 범위
local function bx(parent: Instance, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, color: Color3, mat: Enum.Material, o: any?): BasePart
	local ax, ax1 = math.min(x0, x1), math.max(x0, x1)
	local ay, ay1 = math.min(y0, y1), math.max(y0, y1)
	local az, az1 = math.min(z0, z1), math.max(z0, z1)
	return Kit.box(parent, LCF((ax + ax1) / 2, (ay + ay1) / 2, (az + az1) / 2), SZ(ax1 - ax, ay1 - ay, az1 - az), color, mat, o or {})
end
-- 프레임 기준 박스: 중심 오프셋/크기 m
local function fb(parent: Instance, F: CFrame, cx: number, cy: number, cz: number, sx: number, sy: number, sz: number, color: Color3, mat: Enum.Material, o: any?): BasePart
	return Kit.box(parent, F * mcf(cx, cy, cz), SZ(sx, sy, sz), color, mat, o or {})
end
-- 세로 원기둥(로컬 m): 바닥 y0 부터 높이 h
local function cyl(parent: Instance, x: number, y0: number, z: number, h: number, d: number, color: Color3, mat: Enum.Material, o: any?): BasePart
	return Kit.vcyl(parent, V(x, y0 + h / 2, z), M(h), M(d), color, mat, o or {})
end

local function solid(name: string): any
	return { name = name }
end
local function deco(name: string): any
	return { name = name, collide = false, query = false, shadow = false }
end
local function glassO(name: string, tr: number?, collide: boolean?): any
	local c = collide ~= false
	return { name = name, transparency = tr or 0.6, collide = c, query = c, shadow = false, reflectance = 0.08 }
end
local function neon(name: string, dayColor: Color3?): any
	return { name = name, collide = false, query = false, shadow = false, glow = true, dayMaterial = MAT.SmoothPlastic, dayColor = dayColor or rgb(232, 232, 228) }
end

local function light(p: BasePart, kind: string, props: any): Light?
	if lightsUsed >= MAX_LIGHTS then
		return nil
	end
	local L = Kit.light(p, kind, props)
	if L then
		lightsUsed += 1
	end
	return L
end

-- 글자 판(얇은 파트 + SurfaceGui)
local function sign(parent: Instance, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, face: Enum.NormalId, text: string, o: any?): BasePart
	local oo = o or {}
	local p = bx(parent, x0, y0, z0, x1, y1, z1, oo.bg or rgb(250, 250, 248), oo.mat or MAT.SmoothPlastic, {
		name = oo.name or "Sign",
		collide = false,
		query = false,
		shadow = false,
		transparency = if oo.transparent then 1 else nil,
	})
	Kit.label(p, face, text, { color = oo.color or INK, glow = oo.glow, pixelsPerStud = oo.pps or 40, maxDistance = oo.maxd or 140, font = oo.font })
	return p
end

-- 한 면에 여러 칸 글자(우편함·택배함·키패드): rects = { {u0, v0, u1, v1, text, textColor?, bgColor?} } (면 기준 0..1, 왼→오/위→아래)
local function guiRects(part: BasePart, face: Enum.NormalId, rects: { any }, pps: number, maxDist: number, glowing: boolean)
	local g = Instance.new("SurfaceGui")
	g.Name = "Grid"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pps
	g.LightInfluence = if glowing then 0 else 1
	g.MaxDistance = maxDist
	for _, r in rects do
		local t = Instance.new("TextLabel")
		t.BorderSizePixel = 0
		if r[7] then
			t.BackgroundColor3 = r[7]
			t.BackgroundTransparency = 0
		else
			t.BackgroundTransparency = 1
		end
		t.Position = UDim2.fromScale(r[1], r[2])
		t.Size = UDim2.fromScale(r[3] - r[1], r[4] - r[2])
		t.Text = r[5] or ""
		t.TextScaled = true
		t.Font = Enum.Font.GothamMedium
		t.TextColor3 = r[6] or INK
		t.Parent = g
	end
	g.Parent = part
	Kit.stats.labels += 1
end

local function jitter(rng: Random, c: Color3, amt: number): Color3
	local k = 1 + (rng:NextNumber() * 2 - 1) * amt
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

------------------------------------------------------------------------------------------------------
-- 공용 소품
------------------------------------------------------------------------------------------------------
-- 문짝: 경첩(hx, hz)에서 theta(도, +X → +Z 방향 각) 쪽으로 폭 w. 레버 손잡이 양면.
local function doorLeaf(parent: Instance, hx: number, hz: number, y0: number, w: number, h: number, t: number, theta: number, color: Color3, mat: Enum.Material, handle: Color3): CFrame
	local th = math.rad(theta)
	local F = LCF(hx + math.cos(th) * w / 2, y0 + h / 2, hz + math.sin(th) * w / 2) * CFrame.Angles(0, -th, 0)
	Kit.box(parent, F, SZ(w, h, t), color, mat, solid("DoorLeaf"))
	for _, s in { -1, 1 } do
		Kit.box(parent, F * mcf(w / 2 - 0.12, 1.0 - h / 2, s * (t / 2 + 0.035)), SZ(0.14, 0.022, 0.022), handle, MAT.Metal, deco("Lever"))
		Kit.box(parent, F * mcf(w / 2 - 0.06, 1.0 - h / 2, s * (t / 2 + 0.015)), SZ(0.05, 0.05, 0.03), handle, MAT.Metal, deco("Rose"))
	end
	return F
end

-- X 에 수직인 벽(두께 x0..x1)의 문틀: 개구부 z a..b, 바닥 y0 부터 DOOR_H
local function casingX(parent: Instance, x0: number, x1: number, a: number, b: number, y0: number, color: Color3)
	bx(parent, x0 - 0.02, y0, a - 0.06, x1 + 0.02, y0 + DOOR_H + 0.06, a + 0.02, color, MAT.SmoothPlastic, deco("Casing"))
	bx(parent, x0 - 0.02, y0, b - 0.02, x1 + 0.02, y0 + DOOR_H + 0.06, b + 0.06, color, MAT.SmoothPlastic, deco("Casing"))
	bx(parent, x0 - 0.02, y0 + DOOR_H - 0.02, a - 0.06, x1 + 0.02, y0 + DOOR_H + 0.06, b + 0.06, color, MAT.SmoothPlastic, deco("CasingHead"))
end
-- Z 에 수직인 벽(z0..z1)의 문틀: 개구부 x a..b
local function casingZ(parent: Instance, z0: number, z1: number, a: number, b: number, y0: number, color: Color3)
	bx(parent, a - 0.06, y0, z0 - 0.02, a + 0.02, y0 + DOOR_H + 0.06, z1 + 0.02, color, MAT.Metal, deco("Casing"))
	bx(parent, b - 0.02, y0, z0 - 0.02, b + 0.06, y0 + DOOR_H + 0.06, z1 + 0.02, color, MAT.Metal, deco("Casing"))
	bx(parent, a - 0.06, y0 + DOOR_H - 0.02, z0 - 0.02, b + 0.06, y0 + DOOR_H + 0.06, z1 + 0.02, color, MAT.Metal, deco("CasingHead"))
end

-- 스위치 판 (벽면 법선 축 axis "x"/"z", 벽면 좌표 w, 바깥 방향 s = ±1)
local function switchPlate(parent: Instance, axis: string, w: number, s: number, along: number, y: number)
	if axis == "x" then
		bx(parent, w, y, along - 0.04, w + s * 0.012, y + 0.12, along + 0.04, rgb(246, 246, 244), MAT.SmoothPlastic, deco("Switch"))
	else
		bx(parent, along - 0.04, y, w, along + 0.04, y + 0.12, w + s * 0.012, rgb(246, 246, 244), MAT.SmoothPlastic, deco("Switch"))
	end
end

-- 액자 (벽면 법선 축, 벽면 좌표 w, 방향 s): 테두리 + 매트 + 그림
local function picture(parent: Instance, axis: string, w: number, s: number, a0: number, a1: number, y0: number, y1: number, art: Color3, art2: Color3?)
	local function slab(off0: number, off1: number, b0: number, b1: number, c0: number, c1: number, col: Color3, mat: Enum.Material, name: string)
		if axis == "x" then
			bx(parent, w + s * off0, c0, b0, w + s * off1, c1, b1, col, mat, deco(name))
		else
			bx(parent, b0, c0, w + s * off0, b1, c1, w + s * off1, col, mat, deco(name))
		end
	end
	slab(0, 0.03, a0, a1, y0, y1, rgb(34, 32, 30), MAT.Wood, "Frame")
	slab(0.03, 0.036, a0 + 0.03, a1 - 0.03, y0 + 0.03, y1 - 0.03, rgb(244, 242, 236), MAT.SmoothPlastic, "Mat")
	local ma, mb = a0 + (a1 - a0) * 0.2, a1 - (a1 - a0) * 0.2
	local mc, md = y0 + (y1 - y0) * 0.2, y1 - (y1 - y0) * 0.2
	slab(0.036, 0.042, ma, mb, mc, md, art, MAT.SmoothPlastic, "Art")
	if art2 then
		slab(0.042, 0.048, ma, (ma + mb) / 2, mc, (mc + md) / 2, art2, MAT.SmoothPlastic, "Art")
	end
end

-- 화분 식물: 화분 + 흙 + (작은 것) 둥근 잎 덩어리 / (큰 것) 줄기 + 납작한 잎이 나선으로 펼쳐진 관엽식물
local HOUSE_LEAVES = { rgb(38, 82, 46), rgb(52, 98, 54), rgb(30, 70, 40), rgb(62, 110, 58) }
local function plant(parent: Instance, x: number, y0: number, z: number, potD: number, potH: number, leafD: number, leafH: number, rng: Random, potColor: Color3?)
	cyl(parent, x, y0, z, potH, potD, potColor or rgb(232, 228, 220), MAT.SmoothPlastic, { name = "Pot", collide = potD > 0.3, query = potD > 0.3, shadow = false })
	cyl(parent, x, y0 + potH - 0.02, z, 0.03, potD * 0.86, rgb(70, 54, 42), MAT.Ground, deco("Soil"))
	local top = y0 + potH
	if leafD < 0.4 then
		for _ = 1, 3 do
			local s = leafD * rng:NextNumber(0.45, 0.7)
			Kit.ellipsoid(parent, LCF(x + rng:NextNumber(-0.25, 0.25) * leafD, top + leafH * rng:NextNumber(0.3, 0.8), z + rng:NextNumber(-0.25, 0.25) * leafD), SZ(s, s * 0.8, s), HOUSE_LEAVES[rng:NextInteger(1, #HOUSE_LEAVES)], MAT.SmoothPlastic, deco("Leaves"))
		end
		return
	end
	for i = 1, 3 do
		local a = i * 2.1
		cyl(parent, x + math.cos(a) * 0.04, top, z + math.sin(a) * 0.04, leafH * (0.55 + 0.15 * i), 0.025, rgb(70, 92, 52), MAT.SmoothPlastic, deco("Stem"))
	end
	local n = if leafD > 0.9 then 11 else 8
	for i = 1, n do
		local a = i * 2.4 + rng:NextNumber(-0.3, 0.3) -- 황금각 나선
		local t = i / n
		local hh = top + leafH * (0.3 + 0.7 * t)
		local r = leafD * (0.12 + 0.28 * (1 - t) + rng:NextNumber(0, 0.08))
		local len = leafD * rng:NextNumber(0.38, 0.55)
		local droop = rng:NextNumber(10, 38) + 20 * (1 - t)
		local cf = LCF(x + math.cos(a) * r, hh, z + math.sin(a) * r) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-droop))
		Kit.ellipsoid(parent, cf, SZ(len, 0.03, len * rng:NextNumber(0.55, 0.75)), HOUSE_LEAVES[rng:NextInteger(1, #HOUSE_LEAVES)], MAT.SmoothPlastic, deco("Leaf"))
	end
end

-- 나무(조경): 줄기 + 수관 2~3
local function tree(parent: Instance, x: number, z: number, h: number, cd: number, rng: Random)
	local th = h * 0.5
	cyl(parent, x, 0, z, th, 0.32, P.Bark, MAT.Wood, { name = "Trunk", shadow = false })
	local n = rng:NextInteger(2, 3)
	for _ = 1, n do
		local s = cd * rng:NextNumber(0.7, 1.0)
		Kit.ellipsoid(parent, LCF(x + rng:NextNumber(-0.7, 0.7), h - s * 0.4 + rng:NextNumber(-0.4, 0.3), z + rng:NextNumber(-0.7, 0.7)), SZ(s, s * 0.8, s), LEAVES[rng:NextInteger(1, #LEAVES)], MAT.Grass, { name = "Crown" })
	end
end

------------------------------------------------------------------------------------------------------
-- 엘리베이터 (뒷벽 z = CORE_SPLIT 앞면에 붙음): 문틀 + 중앙 개폐 문 2짝 + 층 표시기 + 호출 버튼(SeoulElevator)
------------------------------------------------------------------------------------------------------
local ELEV_X = { 10.55, 14.65 }

local function elevatorBank(parent: Instance, fl: number, floorLabel: string, target: Vector3, action: string)
	local zf = CORE_SPLIT
	for i, xc in ELEV_X do
		-- 포털(스테인리스)
		bx(parent, xc - 0.68, fl, zf - 0.12, xc - 0.56, fl + 2.32, zf, STEEL, MAT.Metal, solid("ElevJamb"))
		bx(parent, xc + 0.56, fl, zf - 0.12, xc + 0.68, fl + 2.32, zf, STEEL, MAT.Metal, solid("ElevJamb"))
		bx(parent, xc - 0.68, fl + 2.2, zf - 0.12, xc + 0.68, fl + 2.32, zf, STEEL, MAT.Metal, solid("ElevHead"))
		-- 문 2짝(가운데 1 cm 틈 → 뒤 석재가 어둡게 비침)
		bx(parent, xc - 0.56, fl, zf - 0.07, xc - 0.006, fl + 2.2, zf - 0.02, rgb(196, 198, 202), MAT.Metal, solid("ElevDoor"))
		bx(parent, xc + 0.006, fl, zf - 0.07, xc + 0.56, fl + 2.2, zf - 0.02, rgb(196, 198, 202), MAT.Metal, solid("ElevDoor"))
		-- 층 표시기
		sign(parent, xc - 0.22, fl + 2.42, zf - 0.08, xc + 0.22, fl + 2.6, zf - 0.05, NID.Front, floorLabel .. (if i == 1 then " ▲" else " ▼"), {
			bg = rgb(18, 18, 20),
			color = rgb(255, 128, 64),
			glow = true,
			pps = 60,
			maxd = 90,
			name = "ElevIndicator",
		})
		-- 호출 버튼 판 (태그: SeoulSkylineBoot 이 ElevatorTarget 으로 순간이동)
		local plate = bx(parent, xc + 0.82, fl + 1.0, zf - 0.075, xc + 0.94, fl + 1.32, zf - 0.05, STEEL, MAT.Metal, { name = "ElevatorCall", collide = false, query = true, shadow = false })
		for j, dy in { 1.22, 1.1 } do
			Kit.hcyl(parent, LCF(xc + 0.88, fl + dy, zf - 0.08) * CFrame.Angles(0, math.rad(90), 0), M(0.015), M(0.045), if j == 1 then rgb(255, 214, 150) else rgb(120, 120, 124), if j == 1 then MAT.Neon else MAT.Metal, deco("CallButton"))
		end
		plate:SetAttribute("ElevatorTarget", target)
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "ElevatorPrompt"
		pp.ActionText = action
		pp.ObjectText = "엘리베이터"
		pp.HoldDuration = 0.25
		pp.MaxActivationDistance = M(2.6)
		pp.RequiresLineOfSight = false
		pp.Parent = plate
		CollectionService:AddTag(plate, "SeoulElevator")
	end
	-- 석재 피처월(엘리베이터 뒤) + 좌우 라임스톤
	bx(parent, 8.6, fl, zf - 0.05, 16.6, fl + (if fl < 1 then LOBBY_CEIL - LOBBY_FL else 2.35), zf, MARBLE_D, MAT.Marble, solid("ElevWall"))
	-- 안내판
	sign(parent, 12.3, fl + 1.45, zf - 0.07, 12.9, fl + 1.75, zf - 0.05, NID.Front, "101동\n1·2호 라인", { bg = rgb(36, 36, 38), color = rgb(232, 226, 210), pps = 80, maxd = 60 })
end

-- 비상구 계단 문 (뒷벽): 철문 + 문틀 + 푸시바 + 초록 Neon 표시등
local function stairDoor(parent: Instance, fl: number, x0: number)
	local zf = CORE_SPLIT
	local x1 = x0 + DOOR_W
	bx(parent, x0, fl, zf - 0.06, x1, fl + DOOR_H, zf - 0.02, rgb(118, 128, 120), MAT.Metal, solid("StairDoor"))
	bx(parent, x0 - 0.06, fl, zf - 0.08, x0, fl + DOOR_H + 0.06, zf, STEEL_D, MAT.Metal, deco("StairFrame"))
	bx(parent, x1, fl, zf - 0.08, x1 + 0.06, fl + DOOR_H + 0.06, zf, STEEL_D, MAT.Metal, deco("StairFrame"))
	bx(parent, x0 - 0.06, fl + DOOR_H, zf - 0.08, x1 + 0.06, fl + DOOR_H + 0.06, zf, STEEL_D, MAT.Metal, deco("StairFrame"))
	bx(parent, x0 + 0.1, fl + 0.98, zf - 0.11, x1 - 0.08, fl + 1.03, zf - 0.07, STEEL, MAT.Metal, deco("PushBar"))
	local ex = bx(parent, x0 + 0.2, fl + DOOR_H + 0.14, zf - 0.08, x1 - 0.2, fl + DOOR_H + 0.3, zf, rgb(40, 200, 90), MAT.Neon, { name = "ExitSign", collide = false, query = false, shadow = false })
	Kit.label(ex, NID.Front, "비상구", { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 80, maxDistance = 120 })
	-- 소화기
	cyl(parent, x1 + 0.3, fl, zf - 0.15, 0.48, 0.16, rgb(196, 30, 30), MAT.SmoothPlastic, deco("Extinguisher"))
	cyl(parent, x1 + 0.3, fl + 0.48, zf - 0.15, 0.08, 0.06, rgb(40, 40, 40), MAT.Metal, deco("ExtinguisherValve"))
end

------------------------------------------------------------------------------------------------------
-- 1) 외피: 슬래브 띠 · 유리 난간 · 조명 코어 · 핀 · 측벽 · 코어 · 옥상 · 1층 필로티/로비 외피
------------------------------------------------------------------------------------------------------
local function shell(ext: Model, rng: Random, lit: { Color3 })
	-- 층 슬래브(2층~지붕): 앞뒤로 튀어나온 가로 띠 + 실제 바닥
	for k = 2, FLOORS + 1 do
		local y = yb(k)
		bx(ext, -END_T, y - SLAB_DN, -0.25, BL + END_T, y + SLAB_UP, DEPTH + 0.15, WALL_EXT, MAT.Concrete, { name = "Slab" .. k, shadow = k == FLOORS + 1 })
	end
	-- 앞면 유리 난간 + 손스침 / 뒷면 창 아래 띠 (20층 2001호 구간 제외)
	for k = 2, FLOORS do
		local y = yb(k) + SLAB_UP
		local fx0 = if k == UNIT_FL then LINE_W - FIN_T / 2 else 0
		bx(ext, fx0, y, -0.07, BL, y + 1.0, -0.03, RAIL_GLASS, MAT.Glass, glassO("RailGlass", 0.55))
		bx(ext, fx0, y + 1.0, -0.1, BL, y + 1.06, 0.0, STEEL_D, MAT.Metal, { name = "Handrail", shadow = false })
		local bx0 = if k == UNIT_FL then CORE_A1 else -END_T
		bx(ext, bx0, y, DEPTH - 0.25, BL + END_T, y + 0.85, DEPTH + 0.15, WALL_EXT, MAT.Concrete, { name = "BackSpandrel", shadow = false })
	end
	-- 조명 코어: 호 라인별, 1~4개 층 묶음 (켜진 집 / 꺼진 집). 2001호 층은 비움.
	for line = 1, NLINES do
		local cx0 = (line - 1) * LINE_W + (if line == 1 then 0.12 else FIN_T / 2 + 0.05)
		local cx1 = line * LINE_W - (if line == NLINES then 0.12 else FIN_T / 2 + 0.05)
		local k = 2
		while k <= FLOORS do
			if line == 1 and k == UNIT_FL then
				k += 1
				continue
			end
			local k1 = math.min(FLOORS, k + rng:NextInteger(0, 3))
			if line == 1 and k < UNIT_FL and k1 >= UNIT_FL then
				k1 = UNIT_FL - 1
			end
			local on = rng:NextNumber() < 0.64
			local c = if on then jitter(rng, lit[rng:NextInteger(1, #lit)], 0.08) else OFF_C
			bx(ext, cx0, yb(k) + SLAB_UP, 0.6, cx1, yb(k1 + 1) - SLAB_DN, DEPTH - 0.6, c, if on then MAT.Neon else MAT.SmoothPlastic, {
				name = "Core",
				glow = on,
				dayMaterial = MAT.Glass,
				dayColor = P.GlassDeep,
				shadow = false,
			})
			k = k1 + 1
		end
	end
	-- 세대 벽 핀 (관통: 앞뒤로 0.35 m 돌출)
	for i = 1, NLINES - 1 do
		local x = i * LINE_W
		bx(ext, x - FIN_T / 2, yb(2) - SLAB_DN, -0.35, x + FIN_T / 2, ROOF, DEPTH + 0.25, WALL_EXT, MAT.Concrete, solid("Fin"))
	end
	-- 전면 창 멀리언(안방 | 거실 경계, 짝수 라인은 대칭) — 2001호에서는 안방 벽과 같은 자리
	for line = 1, NLINES do
		local base = (line - 1) * LINE_W
		local mx = if line % 2 == 1 then base + 8.075 else base + LINE_W - 8.075
		bx(ext, mx - 0.075, yb(2) + SLAB_UP, -0.14, mx + 0.075, ROOF - SLAB_UP, 0.0, STEEL_D, MAT.Metal, { name = "Mullion", collide = false, query = false, shadow = false })
	end
	-- 측벽(서쪽: 2001호 식당 창 개구부) / 동쪽
	local wy0, wy1, wz0, wz1 = UF + 0.9, UF + 2.1, 2.0, 4.6
	bx(ext, -END_T, 0, -0.35, 0, wy0, DEPTH + 0.25, WALL_EXT, MAT.Concrete, solid("EndWallW"))
	bx(ext, -END_T, wy0, -0.35, 0, wy1, wz0, WALL_EXT, MAT.Concrete, solid("EndWallW"))
	bx(ext, -END_T, wy0, wz1, 0, wy1, DEPTH + 0.25, WALL_EXT, MAT.Concrete, solid("EndWallW"))
	bx(ext, -END_T, wy1, -0.35, 0, PARAPET, DEPTH + 0.25, WALL_EXT, MAT.Concrete, solid("EndWallW"))
	bx(ext, BL, 0, -0.35, BL + END_T, PARAPET, DEPTH + 0.25, WALL_EXT, MAT.Concrete, solid("EndWallE"))
	-- 서쪽 창(식당): 흰 PVC 샷시 + 유리
	bx(ext, -0.24, wy0, wz0, -0.12, wy0 + 0.06, wz1, rgb(240, 240, 238), MAT.SmoothPlastic, deco("WinFrame"))
	bx(ext, -0.24, wy1 - 0.06, wz0, -0.12, wy1, wz1, rgb(240, 240, 238), MAT.SmoothPlastic, deco("WinFrame"))
	bx(ext, -0.24, wy0, wz0, -0.12, wy1, wz0 + 0.06, rgb(240, 240, 238), MAT.SmoothPlastic, deco("WinFrame"))
	bx(ext, -0.24, wy0, wz1 - 0.06, -0.12, wy1, wz1, rgb(240, 240, 238), MAT.SmoothPlastic, deco("WinFrame"))
	bx(ext, -0.24, wy0, (wz0 + wz1) / 2 - 0.03, -0.12, wy1, (wz0 + wz1) / 2 + 0.03, rgb(240, 240, 238), MAT.SmoothPlastic, deco("WinMullion"))
	bx(ext, -0.2, wy0 + 0.06, wz0 + 0.06, -0.16, wy1 - 0.06, wz1 - 0.06, GLASS_C, MAT.Glass, glassO("WinGlass", 0.65))
	-- 측벽 슈퍼그래픽 + 동 번호
	for _, sd in { -1, 1 } do
		local face = if sd < 0 then NID.Left else NID.Right
		local xo = if sd < 0 then -END_T else BL + END_T
		bx(ext, xo + sd * 0.02, 10, 6.3, xo + sd * 0.12, 70, 8.3, ACCENT, MAT.SmoothPlastic, { name = "Accent", collide = false, query = false, shadow = false })
		sign(ext, xo + sd * 0.12, 73, 0.6, xo + sd * 0.16, 80, 8.6, face, "101", { bg = WALL_EXT, mat = MAT.Concrete, color = rgb(250, 244, 230), glow = true, pps = 6, maxd = 3000, name = "DongNumber" })
	end
	-- 옥상: 파라펫 + LED 띠 + 단지명 사인
	bx(ext, -END_T, ROOF, -0.25, BL + END_T, PARAPET, -0.05, WALL_EXT, MAT.Concrete, solid("Parapet"))
	bx(ext, -END_T, ROOF, DEPTH - 0.05, BL + END_T, PARAPET, DEPTH + 0.15, WALL_EXT, MAT.Concrete, solid("Parapet"))
	bx(ext, -END_T, PARAPET, -0.3, BL + END_T, PARAPET + 0.1, 0.0, rgb(150, 112, 60), MAT.Neon, neon("RoofLed", WALL_EXT))
	for _, px in { 18.2, 32.2 } do
		bx(ext, px - 0.1, ROOF, 0.6, px + 0.1, ROOF + 4.0, 0.8, STEEL_D, MAT.Metal, { name = "SignPost", shadow = false })
	end
	sign(ext, 17.6, ROOF + 1.4, 0.45, 32.8, ROOF + 4.0, 0.55, NID.Front, "한강뷰", { bg = rgb(36, 38, 42), mat = MAT.Metal, color = rgb(250, 238, 214), glow = true, pps = 8, maxd = 3500, name = "RoofSign", font = Enum.Font.GothamBlack })
	-- 계단실·승강로 코어 (뒤로 돌출, 기계실까지)
	bx(ext, CORE_A0, 0, CORE_SPLIT, CORE_A1, CORE_TOP, CORE_Z1, WALL_CORE, MAT.Concrete, solid("CoreA"))
	bx(ext, CORE_A0, LOBBY_TOP - 0.05, DEPTH, CORE_A1, SLAB_TOP, CORE_SPLIT, WALL_CORE, MAT.Concrete, solid("CoreAFront"))
	bx(ext, CORE_A0, TOPY, DEPTH, CORE_A1, CORE_TOP, CORE_SPLIT, WALL_CORE, MAT.Concrete, solid("CoreAFront"))
	bx(ext, CORE_B0, 0, CORE_SPLIT, CORE_B1, CORE_TOP, CORE_Z1, WALL_CORE, MAT.Concrete, solid("CoreB"))
	bx(ext, CORE_B0, LOBBY_TOP - 0.05, DEPTH, CORE_B1, CORE_TOP, CORE_SPLIT, WALL_CORE, MAT.Concrete, solid("CoreBFront"))
	for _, cx in { CORE_A1 - 2.0, CORE_B1 - 2.0 } do
		bx(ext, cx - 0.5, LOBBY_H, CORE_Z1 + 0.02, cx + 0.5, ROOF, CORE_Z1 + 0.12, rgb(120, 104, 80), MAT.Neon, neon("StairWindow", GLASS_C))
	end
	-- 1층 필로티 기둥 + 천장(2층 슬래브 밑면) 매입등
	for _, z in { 0.3, 9.0 } do
		bx(ext, 24.95, PAVE, z, 25.45, LOBBY_TOP, z + 0.6, WALL_EXT, MAT.Concrete, solid("Pilotis"))
	end
	for _, x in { 3.0, 22.2, 28.2, 47.4 } do
		for _, z in { 2.5, 7.5 } do
			cyl(ext, x, LOBBY_TOP - 0.03, z, 0.03, 0.22, PANEL_WARM, MAT.Neon, neon("SoffitLight"))
		end
	end
	-- 3·4호 라인 로비(외관만: 불 켜진 유리 상자)
	bx(ext, CORE_B0, PAVE, 1.0, CORE_B0 + 0.25, LOBBY_TOP, CORE_SPLIT, LIMESTONE, MAT.Limestone, solid("LobbyBWall"))
	bx(ext, CORE_B1 - 0.25, PAVE, 1.0, CORE_B1, LOBBY_TOP, CORE_SPLIT, LIMESTONE, MAT.Limestone, solid("LobbyBWall"))
	bx(ext, CORE_B0 + 0.45, PAVE + 0.1, 1.6, CORE_B1 - 0.45, LOBBY_CEIL, CORE_SPLIT - 0.2, rgb(150, 122, 86), MAT.Neon, neon("LobbyBGlow", LIMESTONE))
	bx(ext, CORE_B0 + 0.25, PAVE, 1.0, CORE_B1 - 0.25, LOBBY_CEIL, 1.05, GLASS_C, MAT.Glass, glassO("LobbyBGlass", 0.55))
	bx(ext, CORE_B0, LOBBY_CEIL, 0.95, CORE_B1, LOBBY_TOP, 1.1, STEEL_D, MAT.Metal, solid("LobbyBFascia"))
	for i = 1, 5 do
		local x = CORE_B0 + 0.25 + i * (CORE_B1 - CORE_B0 - 0.5) / 6
		bx(ext, x - 0.03, PAVE, 0.97, x + 0.03, LOBBY_CEIL, 1.08, STEEL_D, MAT.Metal, deco("Mullion"))
	end
	bx(ext, 35.4, 3.2, -2.2, 40.2, 3.45, 0.9, STEEL_D, MAT.Metal, solid("CanopyB"))
	sign(ext, 36.6, 3.22, -2.27, 39.0, 3.43, -2.22, NID.Front, "101동 3·4호", { bg = STEEL_D, mat = MAT.Metal, color = rgb(250, 236, 210), glow = true, pps = 30, maxd = 400 })
	-- 바닥 포장(필로티·앞마당·뒤)
	bx(ext, -6, 0, -9.5, BL + 6, PAVE, CORE_Z1 + 1.5, rgb(150, 144, 136), MAT.Pavement, { name = "Plaza", shadow = false })
end

------------------------------------------------------------------------------------------------------
-- 2) 조경 / 진입로 / 캐노피
------------------------------------------------------------------------------------------------------
local function grounds(gm: Model, rng: Random)
	-- 진입로(강변북로 쪽 → 캐노피), 잔디, 경계석, 생울타리
	bx(gm, 10.6, 0, RES_Z0, 14.6, PAVE + 0.01, -9.5, rgb(176, 168, 156), MAT.Pavement, { name = "Walkway", shadow = false })
	bx(gm, -6, 0, RES_Z0, 10.4, 0.12, -9.5, P.Grass, MAT.Grass, { name = "Lawn", shadow = false })
	bx(gm, 14.8, 0, RES_Z0, BL + 6, 0.12, -9.5, P.Grass, MAT.Grass, { name = "Lawn", shadow = false })
	bx(gm, 10.4, 0, RES_Z0, 10.6, 0.18, -9.5, rgb(132, 130, 126), MAT.Granite, solid("Curb"))
	bx(gm, 14.6, 0, RES_Z0, 14.8, 0.18, -9.5, rgb(132, 130, 126), MAT.Granite, solid("Curb"))
	bx(gm, -6, 0.12, -10.4, 10.2, 0.95, -9.6, rgb(46, 78, 44), MAT.Grass, solid("Hedge"))
	bx(gm, 15.0, 0.12, -10.4, BL + 6, 0.95, -9.6, rgb(46, 78, 44), MAT.Grass, solid("Hedge"))
	-- 나무 (앞 잔디: 저층만 가리고 20층 전망은 막지 않음)
	for _, t in { { -2.5, -14.5 }, { 3.5, -22.5 }, { 7.6, -13.4 }, { 18.2, -13.6 }, { 23.5, -21.5 }, { 30.5, -14.2 }, { 37.5, -22.0 }, { 44.0, -14.0 }, { 51.0, -21.0 }, { -3.5, -24.5 }, { 55.0, -13.5 } } do
		tree(gm, t[1], t[2], rng:NextNumber(8.5, 11.5), rng:NextNumber(4.8, 6.4), rng)
	end
	-- 관목 + 꽃 화단 (캐노피 양옆)
	for _, s in { { 8.0, -1.6 }, { 8.8, -2.6 }, { 16.6, -1.6 }, { 17.4, -2.7 }, { 5.6, -2.2 }, { 19.6, -2.2 } } do
		Kit.ellipsoid(gm, LCF(s[1], 0.45, s[2]), SZ(1.3, 0.9, 1.1), LEAVES[rng:NextInteger(1, #LEAVES)], MAT.Grass, deco("Shrub"))
	end
	for _, f in { { 7.2, -3.6 }, { 18.0, -3.6 } } do
		bx(gm, f[1] - 1.0, PAVE, f[2] - 0.5, f[1] + 1.0, 0.45, f[2] + 0.5, rgb(120, 116, 110), MAT.Granite, solid("Planter"))
		for i = 0, 5 do
			Kit.ball(gm, V(f[1] - 0.75 + i * 0.3, 0.52, f[2] + (if i % 2 == 0 then -0.15 else 0.15)), M(0.26), if i % 2 == 0 then rgb(214, 96, 110) else rgb(236, 206, 120), MAT.SmoothPlastic, deco("Flowers"))
		end
	end
	-- 볼라드 조명 (진입로 양옆)
	for _, z in { -25.0, -21.0, -17.0, -13.0 } do
		for _, x in { 10.1, 15.1 } do
			cyl(gm, x, 0.12, z, 0.75, 0.16, STEEL_D, MAT.Metal, solid("Bollard"))
			cyl(gm, x, 0.87, z, 0.08, 0.17, LAMP, MAT.Neon, neon("BollardLamp"))
		end
	end
	-- 단지 보안등 4.5 m (2개, 실제 광원)
	for _, lp in { { 9.6, -18.5 }, { 15.6, -24.5 } } do
		cyl(gm, lp[1], 0.12, lp[2], toM(R.ParkLamp) - 0.2, 0.12, STEEL_D, MAT.Metal, solid("LampPole"))
		local head = Kit.ball(gm, V(lp[1], toM(R.ParkLamp), lp[2]), M(0.42), LAMP, MAT.Neon, neon("LampGlobe"))
		light(head, "PointLight", { color = P.LampWarm, brightness = 1.1, range = M(7) })
	end
	-- 동 표지석 (진입로 입구, 도로 쪽을 봄)
	bx(gm, 15.4, 0.12, -26.4, 19.6, 0.3, -25.2, rgb(110, 106, 100), MAT.Granite, solid("MonumentBase"))
	bx(gm, 15.6, 0.3, -26.1, 19.4, 1.25, -25.5, rgb(64, 62, 60), MAT.Granite, solid("Monument"))
	sign(gm, 15.8, 0.42, -26.14, 19.2, 1.14, -26.1, NID.Front, "한강뷰 101동", { bg = rgb(64, 62, 60), mat = MAT.Granite, color = rgb(250, 230, 190), glow = true, pps = 30, maxd = 600, name = "MonumentText" })
	-- 벤치 (강 쪽을 봄)
	for _, b in { { 2.5, -6.5 }, { 46.0, -6.5 } } do
		local F = frameAt(b[1], PAVE, b[2], 0)
		fb(gm, F, 0, 0.43, 0, 1.8, 0.05, 0.45, BENCH_WOOD, MAT.Wood, solid("Bench"))
		fb(gm, F, 0, 0.7, 0.22, 1.8, 0.3, 0.04, BENCH_WOOD, MAT.Wood, deco("BenchBack"))
		for _, lx in { -0.75, 0.75 } do
			fb(gm, F, lx, 0.2, 0, 0.06, 0.4, 0.42, STEEL_D, MAT.Metal, deco("BenchLeg"))
		end
	end
	-- 자전거 거치대 + 자전거 2대
	bx(gm, 0.6, PAVE, -3.2, 3.8, PAVE + 0.08, -3.0, STEEL_D, MAT.Metal, deco("BikeRackRail"))
	for i, bxp in { 1.3, 2.6 } do
		local F = frameAt(bxp, PAVE, -3.1, 0)
		for _, wz in { -0.5, 0.5 } do
			Kit.hcyl(gm, F * mcf(0, 0.33, wz) * CFrame.Angles(0, math.rad(90), 0), M(0.04), M(0.66), rgb(30, 30, 32), MAT.Rubber, deco("BikeWheel"))
		end
		fb(gm, F, 0, 0.55, 0, 0.04, 0.04, 0.95, if i == 1 then rgb(40, 96, 150) else rgb(170, 50, 46), MAT.Metal, deco("BikeFrame"))
		fb(gm, F, 0, 0.62, 0.3, 0.12, 0.05, 0.22, rgb(30, 30, 30), MAT.Leather, deco("BikeSaddle"))
		fb(gm, F, 0, 0.8, -0.42, 0.5, 0.03, 0.03, rgb(40, 40, 40), MAT.Metal, deco("BikeBar"))
	end
end

------------------------------------------------------------------------------------------------------
-- 3) 1층 로비
------------------------------------------------------------------------------------------------------
local LX0, LX1 = CORE_A0 + 0.25, CORE_A1 - 0.25 -- 6.25 .. 18.95
local LZ0, LZ1 = 1.05, CORE_SPLIT
local DOOR_X0, DOOR_X1 = 11.7, 13.5 -- 자동문 개구부 1.8 m

local function lobbyEnvelope(ext: Model)
	-- 좌우 벽(외부 쪽은 콘크리트)
	bx(ext, CORE_A0, 0, 1.0, LX0, LOBBY_TOP, LZ1, WALL_CORE, MAT.Concrete, solid("LobbyWallW"))
	bx(ext, LX1, 0, 1.0, CORE_A1, LOBBY_TOP, LZ1, WALL_CORE, MAT.Concrete, solid("LobbyWallE"))
	-- 정면 유리벽 + 멀리언 + 자동문 상부
	bx(ext, LX0, LOBBY_FL, 1.0, DOOR_X0, LOBBY_CEIL, 1.04, GLASS_C, MAT.Glass, glassO("LobbyGlass", 0.62))
	bx(ext, DOOR_X1, LOBBY_FL, 1.0, LX1, LOBBY_CEIL, 1.04, GLASS_C, MAT.Glass, glassO("LobbyGlass", 0.62))
	bx(ext, DOOR_X0, 2.42, 1.0, DOOR_X1, LOBBY_CEIL, 1.04, GLASS_C, MAT.Glass, glassO("LobbyTransom", 0.62))
	for _, x in { 8.1, 9.95, DOOR_X0, DOOR_X1, 15.25, 17.1 } do
		bx(ext, x - 0.04, LOBBY_FL, 0.96, x + 0.04, LOBBY_CEIL, 1.1, STEEL_D, MAT.Metal, solid("LobbyMullion"))
	end
	bx(ext, CORE_A0, LOBBY_CEIL, 0.94, CORE_A1, LOBBY_TOP, 1.12, STEEL_D, MAT.Metal, solid("LobbyFascia"))
	-- 자동문: 문 상부 구동부 + 열린 상태의 두 짝(고정 유리 안쪽으로 겹쳐 밀림)
	bx(ext, DOOR_X0 - 1.05, 2.22, 1.1, DOOR_X1 + 1.05, 2.42, 1.26, rgb(150, 152, 156), MAT.Metal, solid("DoorOperator"))
	cyl(ext, (DOOR_X0 + DOOR_X1) / 2, 2.17, 1.18, 0.05, 0.08, rgb(30, 30, 30), MAT.SmoothPlastic, deco("DoorSensor"))
	for _, s in { -1, 1 } do
		local x0 = if s < 0 then DOOR_X0 - 0.98 else DOOR_X1 - 0.02
		bx(ext, x0, LOBBY_FL, 1.12, x0 + 1.0, 2.2, 1.16, GLASS_C, MAT.Glass, glassO("AutoDoor", 0.6))
		local edge = if s < 0 then x0 + 1.0 - 0.05 else x0
		bx(ext, edge, LOBBY_FL, 1.11, edge + 0.05, 2.2, 1.17, STEEL, MAT.Metal, deco("AutoDoorStile"))
		local back = if s < 0 then x0 else x0 + 1.0 - 0.04
		bx(ext, back, LOBBY_FL, 1.11, back + 0.04, 2.2, 1.17, STEEL, MAT.Metal, deco("AutoDoorStile"))
	end
	bx(ext, DOOR_X0, PAVE, 0.96, DOOR_X1, LOBBY_FL + 0.005, 1.2, STEEL, MAT.Metal, solid("Threshold"))
	-- 캐노피 + 기둥 + 동 번호 사인 + 하부 조명
	local canopy = bx(ext, 9.4, 3.25, -3.2, 15.8, 3.5, 0.9, rgb(58, 60, 66), MAT.Metal, solid("Canopy"))
	for _, x in { 9.65, 15.55 } do
		cyl(ext, x, PAVE, -2.95, 3.25 - PAVE, 0.16, rgb(58, 60, 66), MAT.Metal, solid("CanopyColumn"))
	end
	for _, x in { 10.8, 12.6, 14.4 } do
		for _, z in { -2.2, -0.6 } do
			cyl(ext, x, 3.22, z, 0.03, 0.18, PANEL_WARM, MAT.Neon, neon("CanopyLight"))
		end
	end
	light(canopy, "SurfaceLight", { face = NID.Bottom, color = P.LampWarm, brightness = 1.6, range = M(5), angle = 110 })
	bx(ext, 11.0, 3.5, -3.05, 14.2, 4.15, -2.97, rgb(58, 60, 66), MAT.Metal, deco("CanopySignBack"))
	sign(ext, 11.1, 3.55, -3.12, 14.1, 4.1, -3.07, NID.Front, "101동", { bg = rgb(58, 60, 66), mat = MAT.Metal, color = rgb(255, 236, 200), glow = true, pps = 40, maxd = 800, name = "CanopySign", font = Enum.Font.GothamBold })
end

local function lobbyInterior(g: Model, rng: Random, unitTarget: Vector3)
	-- 대리석 바닥: 어두운 테두리 + 밝은 필드 + 중앙 런너(입구 → 엘리베이터)
	local fy0, fy1 = PAVE, LOBBY_FL
	bx(g, LX0, fy0, LZ0, LX1, fy1, 1.65, MARBLE_D, MAT.Marble, solid("FloorBorder"))
	bx(g, LX0, fy0, 11.65, LX1, fy1, LZ1, MARBLE_D, MAT.Marble, solid("FloorBorder"))
	bx(g, LX0, fy0, 1.65, 6.85, fy1, 11.65, MARBLE_D, MAT.Marble, solid("FloorBorder"))
	bx(g, 18.35, fy0, 1.65, LX1, fy1, 11.65, MARBLE_D, MAT.Marble, solid("FloorBorder"))
	bx(g, 6.85, fy0, 1.65, 11.4, fy1, 11.65, MARBLE_W, MAT.Marble, solid("FloorField"))
	bx(g, 11.4, fy0, 1.65, 13.8, fy1, 11.65, MARBLE_G, MAT.Marble, solid("FloorRunner"))
	bx(g, 13.8, fy0, 1.65, 18.35, fy1, 11.65, MARBLE_W, MAT.Marble, solid("FloorField"))
	bx(g, 11.6, fy1, 1.25, 13.6, fy1 + 0.018, 2.7, rgb(58, 56, 54), MAT.Carpet, deco("EntryMat"))
	-- 벽 마감: 서쪽 월넛 패널, 동쪽 라임스톤, 뒤 라임스톤(엘리베이터 석재 피처월은 elevatorBank)
	bx(g, LX0, LOBBY_FL, LZ0 + 0.05, LX0 + 0.04, LOBBY_CEIL, LZ1 - 0.05, WALNUT, MAT.Wood, solid("WallPanelW"))
	bx(g, LX1 - 0.04, LOBBY_FL, LZ0 + 0.05, LX1, LOBBY_CEIL, LZ1 - 0.05, STONE_L, MAT.Marble, solid("WallPanelE"))
	bx(g, LX0 + 0.04, LOBBY_FL, LZ1 - 0.04, 8.6, LOBBY_CEIL, LZ1, STONE_L, MAT.Marble, solid("WallPanelN"))
	bx(g, 16.6, LOBBY_FL, LZ1 - 0.04, LX1 - 0.04, LOBBY_CEIL, LZ1, STONE_L, MAT.Marble, solid("WallPanelN"))
	bx(g, LX0 + 0.04, LOBBY_FL, LZ0 + 0.1, LX0 + 0.06, LOBBY_FL + 0.1, LZ1 - 0.1, rgb(40, 40, 42), MAT.Metal, deco("Skirting"))
	bx(g, LX1 - 0.06, LOBBY_FL, LZ0 + 0.1, LX1 - 0.04, LOBBY_FL + 0.1, LZ1 - 0.1, rgb(40, 40, 42), MAT.Metal, deco("Skirting"))
	-- 천장 + 런너 위 라인 조명 + 매입등 6
	bx(g, LX0, LOBBY_CEIL, LZ0, LX1, LOBBY_CEIL + 0.05, LZ1, CEIL_C, MAT.SmoothPlastic, solid("Ceiling"))
	bx(g, 12.48, LOBBY_CEIL - 0.03, 2.0, 12.72, LOBBY_CEIL + 0.01, 11.2, PANEL_WARM, MAT.Neon, neon("LineLight"))
	local panels = {}
	for _, x in { 8.7, 16.5 } do
		for _, z in { 3.4, 6.6, 9.8 } do
			table.insert(panels, bx(g, x - 0.3, LOBBY_CEIL - 0.025, z - 0.3, x + 0.3, LOBBY_CEIL + 0.01, z + 0.3, PANEL_WARM, MAT.Neon, neon("CeilPanel")))
		end
	end
	light(panels[2], "PointLight", { color = rgb(255, 222, 180), brightness = 1.1, range = M(8) })
	light(panels[5], "PointLight", { color = rgb(255, 222, 180), brightness = 1.1, range = M(8) })
	Kit.ball(g, V(17.6, LOBBY_CEIL - 0.06, 10.8), M(0.14), rgb(20, 20, 24), MAT.Glass, deco("CCTV"))

	-- 우편함 54칸 (서쪽 벽, 9열 × 6행: 201~2802호)
	local mz0, mz1, my0, my1 = 3.2, 7.0, 0.8, 2.0
	local mx0, mx1 = LX0 + 0.04, LX0 + 0.3
	local housing = bx(g, mx0, my0, mz0, mx1, my1, mz1, rgb(178, 166, 142), MAT.Metal, solid("Mailboxes"))
	for i = 0, 9 do
		local z = mz0 + i * (mz1 - mz0) / 9
		bx(g, mx1, my0, z - 0.012, mx1 + 0.03, my1, z + 0.012, rgb(120, 110, 92), MAT.Metal, deco("MailRib"))
	end
	for j = 0, 6 do
		local y = my0 + j * (my1 - my0) / 6
		bx(g, mx1, y - 0.012, mz0, mx1 + 0.03, y + 0.012, mz1, rgb(120, 110, 92), MAT.Metal, deco("MailRib"))
	end
	local cells = {}
	for r = 0, 5 do
		for c = 0, 8 do
			local idx = r * 9 + c
			local fl, ln = 2 + idx // 2, idx % 2 + 1
			local u0, v0 = c / 9, r / 6
			table.insert(cells, { u0 + 0.008, v0 + 0.02, u0 + 0.075, v0 + 0.085, string.format("%d%02d", fl, ln), rgb(52, 46, 36) })
			table.insert(cells, { u0 + 0.02, v0 + 0.11, u0 + 1 / 9 - 0.02, v0 + 0.125, "", nil, rgb(60, 54, 44) })
		end
	end
	guiRects(housing, NID.Right, cells, 60, 70, false)
	sign(g, mx0, 2.08, 4.3, mx0 + 0.03, 2.3, 5.9, NID.Right, "우 편 함", { bg = rgb(52, 46, 36), color = rgb(236, 226, 200), pps = 60, maxd = 80 })
	sign(g, LX0 + 0.04, 2.7, 3.4, LX0 + 0.07, 3.3, 6.8, NID.Right, "HANGANG VIEW  101", { bg = WALNUT, mat = MAT.Wood, color = rgb(214, 190, 140), pps = 40, maxd = 120, name = "WallLogo", font = Enum.Font.Gotham })

	-- 관리사무소 공지 게시판 (동쪽 벽, -X 를 봄)
	local nx = LX1 - 0.04
	bx(g, nx - 0.04, 1.2, 2.6, nx, 2.1, 4.4, WALNUT, MAT.Wood, solid("NoticeFrame"))
	bx(g, nx - 0.055, 1.25, 2.65, nx - 0.04, 2.05, 4.35, rgb(176, 136, 94), MAT.Fabric, deco("NoticeCork"))
	sign(g, nx - 0.03, 2.13, 2.6, nx, 2.33, 4.4, NID.Left, "관리사무소 공지사항", { bg = rgb(36, 52, 84), color = rgb(255, 255, 255), pps = 70, maxd = 80 })
	local notices = {
		{ 2.72, 3.08, 1.62, 2.0, "[공지]\n엘리베이터 정기점검\n11월 12일(목) 10~12시", rgb(255, 255, 255) },
		{ 3.16, 3.5, 1.68, 2.0, "재활용 분리배출\n매주 화요일\n18:00~24:00", rgb(255, 246, 196) },
		{ 3.58, 3.92, 1.6, 1.98, "지하주차장\n물청소 안내\n11/15(일) 09:00~", rgb(255, 255, 255) },
		{ 4.0, 4.3, 1.66, 2.0, "층간소음\n줄이기\n캠페인", rgb(255, 222, 226) },
		{ 2.8, 3.3, 1.3, 1.56, "택배 수령은\n무인택배함 이용", rgb(214, 236, 255) },
		{ 3.5, 4.2, 1.3, 1.54, "동대표 선거 공고\n입주자대표회의", rgb(255, 255, 255) },
	}
	for _, n in notices do
		sign(g, nx - 0.075, n[3], n[1], nx - 0.06, n[4], n[2], NID.Left, n[5], { bg = n[6], color = rgb(30, 30, 34), pps = 120, maxd = 50, name = "Notice" })
		Kit.ball(g, V(nx - 0.08, n[4] - 0.025, (n[1] + n[2]) / 2), M(0.022), rgb(210, 40, 40), MAT.SmoothPlastic, deco("Pin"))
	end

	-- 무인택배함 (동쪽 벽): 본체 + 문(열별 높이 다양) + 터치스크린 열
	local pz0, pz1, py0, py1 = 5.2, 9.6, LOBBY_FL, 2.15
	local px1 = LX1 - 0.04
	local px0 = px1 - 0.5
	bx(g, px0, py0, pz0, px1, py1, pz1, rgb(70, 74, 80), MAT.Metal, solid("ParcelLocker"))
	local cols = { 4, 3, 0, 5, 4, 3 }
	local cw = (pz1 - pz0 - 0.1) / 6
	local doorLabels = {}
	local num = 1
	for ci, nrows in cols do
		local z0 = pz0 + 0.05 + (ci - 1) * cw
		if nrows == 0 then
			-- 조작부: 화면 + 키패드 + 사인
			local scr = bx(g, px0 - 0.012, 1.25, z0 + 0.1, px0, 1.62, z0 + cw - 0.1, SCREEN, MAT.Neon, { name = "LockerScreen", collide = false, query = false, shadow = false })
			Kit.label(scr, NID.Left, "택배 찾기\n동·호수 입력", { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 80, maxDistance = 60 })
			bx(g, px0 - 0.012, 0.95, z0 + 0.15, px0, 1.18, z0 + cw - 0.15, rgb(40, 42, 46), MAT.Metal, deco("LockerKeypad"))
			bx(g, px0 - 0.006, 0.3, z0 + 0.04, px0, 0.85, z0 + cw - 0.04, rgb(200, 204, 208), MAT.Metal, deco("LockerDoor"))
		else
			local hgt = (py1 - py0 - 0.1) / nrows
			for ri = 0, nrows - 1 do
				local y0 = py0 + 0.05 + ri * hgt
				bx(g, px0 - 0.02, y0 + 0.01, z0 + 0.01, px0, y0 + hgt - 0.01, z0 + cw - 0.01, rgb(204, 208, 212), MAT.Metal, deco("LockerDoor"))
				local u0 = (z0 - pz0) / (pz1 - pz0)
				local v1 = 1 - (y0 + hgt - 0.03 - py0) / (py1 - py0)
				table.insert(doorLabels, { u0 + 0.01, v1, u0 + 0.045, v1 + 0.035, tostring(num), rgb(60, 64, 70) })
				if rng:NextNumber() < 0.35 then
					bx(g, px0 - 0.03, y0 + hgt - 0.08, z0 + cw - 0.07, px0 - 0.02, y0 + hgt - 0.05, z0 + cw - 0.04, rgb(255, 60, 40), MAT.Neon, deco("LockerLed"))
				end
				num += 1
			end
		end
	end
	local overlay = bx(g, px0 - 0.03, py0, pz0, px0 - 0.025, py1, pz1, rgb(0, 0, 0), MAT.SmoothPlastic, { name = "LockerNumbers", transparency = 1, collide = false, query = false, shadow = false })
	guiRects(overlay, NID.Left, doorLabels, 60, 60, false)
	sign(g, px1 - 0.03, 2.2, 6.4, px1, 2.42, 8.4, NID.Left, "무인택배함", { bg = rgb(40, 120, 90), color = rgb(255, 255, 255), pps = 60, maxd = 90 })

	-- 대기 벤치 + 사이드 테이블 + 대형 화분
	local BF = frameAt(8.5, LOBBY_FL, 2.15, 180)
	fb(g, BF, 0, 0.21, 0, 2.2, 0.32, 0.55, rgb(40, 38, 36), MAT.Metal, solid("LobbyBenchBase"))
	fb(g, BF, 0, SEAT - 0.05, 0, 2.16, 0.1, 0.53, rgb(150, 98, 64), MAT.Leather, solid("LobbyBenchSeat"))
	cyl(g, 10.05, LOBBY_FL, 2.2, 0.45, 0.42, MARBLE_W, MAT.Marble, solid("SideTable"))
	plant(g, 10.4, LOBBY_FL, 1.55, 0.5, 0.55, 0.95, 1.2, rng, rgb(60, 58, 56))
	plant(g, 14.8, LOBBY_FL, 1.55, 0.5, 0.55, 0.95, 1.2, rng, rgb(60, 58, 56))
	plant(g, 7.3, LOBBY_FL, 11.5, 0.45, 0.5, 0.8, 1.0, rng, rgb(60, 58, 56))
	-- 엘리베이터 2대 + 비상구
	elevatorBank(g, LOBBY_FL, "1", unitTarget, "20층으로 올라가기")
	stairDoor(g, LOBBY_FL, 17.25)
	-- 공동현관 키패드(문 밖 왼쪽 기둥)
	local kx0, kx1 = 10.55, 10.9
	bx(g, kx0, PAVE, 0.3, kx1, 1.45, 0.5, STEEL, MAT.Metal, solid("KeypadPost"))
	local kscr = bx(g, kx0 + 0.04, 1.15, 0.28, kx1 - 0.04, 1.38, 0.3, SCREEN, MAT.Neon, { name = "KeypadScreen", collide = false, query = false, shadow = false })
	Kit.label(kscr, NID.Front, "101동\n호수 + 호출", { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 100, maxDistance = 50 })
	local pad = bx(g, kx0 + 0.05, 0.82, 0.28, kx1 - 0.05, 1.1, 0.3, rgb(40, 42, 46), MAT.Metal, deco("Keypad"))
	local keys = {}
	local kt = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }
	for i, t in kt do
		local c, r = (i - 1) % 3, (i - 1) // 3
		table.insert(keys, { c / 3 + 0.04, r / 4 + 0.03, (c + 1) / 3 - 0.04, (r + 1) / 4 - 0.03, t, rgb(230, 236, 240), rgb(70, 74, 80) })
	end
	guiRects(pad, NID.Front, keys, 120, 40, true)
	Kit.ball(g, V((kx0 + kx1) / 2, 1.41, 0.29), M(0.03), rgb(20, 20, 24), MAT.Glass, deco("KeypadCam"))
end

------------------------------------------------------------------------------------------------------
-- 4) 20층 엘리베이터 홀 (x 6.25..18.95, z 9.85..12.25)
------------------------------------------------------------------------------------------------------
local HX0, HX1 = CORE_A0 + 0.25, CORE_A1 - 0.25
local HZ0, HZ1 = DEPTH, CORE_SPLIT
local FD_X0, FD_X1 = 6.95, 6.95 + DOOR_W -- 2001호 현관문 개구부
local ND_X0 = 17.45 -- 2002호 문

local function hallEnvelope(ext: Model)
	-- 홀 좌우 벽(서쪽 창), 2002호 쪽 앞벽
	local wy0, wy1, wz0, wz1 = HF + 0.9, HF + 2.05, 10.4, 11.75
	bx(ext, CORE_A0, SLAB_TOP, HZ0, HX0, wy0, HZ1, WALL_CORE, MAT.Concrete, solid("HallWallW"))
	bx(ext, CORE_A0, wy1, HZ0, HX0, TOPY, HZ1, WALL_CORE, MAT.Concrete, solid("HallWallW"))
	bx(ext, CORE_A0, wy0, HZ0, HX0, wy1, wz0, WALL_CORE, MAT.Concrete, solid("HallWallW"))
	bx(ext, CORE_A0, wy0, wz1, HX0, wy1, HZ1, WALL_CORE, MAT.Concrete, solid("HallWallW"))
	bx(ext, CORE_A0 + 0.1, wy0, wz0, CORE_A0 + 0.14, wy1, wz1, GLASS_C, MAT.Glass, glassO("HallWindow", 0.6))
	bx(ext, CORE_A0 + 0.06, wy0, wz0, CORE_A0 + 0.18, wy0 + 0.05, wz1, rgb(240, 240, 238), MAT.SmoothPlastic, deco("HallWinFrame"))
	bx(ext, CORE_A0 + 0.06, wy1 - 0.05, wz0, CORE_A0 + 0.18, wy1, wz1, rgb(240, 240, 238), MAT.SmoothPlastic, deco("HallWinFrame"))
	bx(ext, HX1, SLAB_TOP, HZ0, CORE_A1, TOPY, HZ1, WALL_CORE, MAT.Concrete, solid("HallWallE"))
	bx(ext, LINE_W + FIN_T / 2, SLAB_TOP, DEPTH - 0.25, CORE_A1, TOPY, DEPTH, WALL_EXT, MAT.Concrete, solid("HallWall2002"))
end

local function hallInterior(g: Model, rng: Random, lobbyTarget: Vector3)
	bx(g, HX0, SLAB_TOP, HZ0, HX1, HF, HZ1, rgb(196, 192, 186), MAT.CeramicTiles, solid("HallFloor"))
	bx(g, HX0, HALL_CEIL, HZ0, HX1, HALL_CEIL + 0.05, HZ1, CEIL_C, MAT.SmoothPlastic, solid("HallCeiling"))
	-- 앞벽(세대 현관 쪽) 라임스톤 패널, 문 주위로 나눔
	local fz = HZ0
	bx(g, HX0, HF, fz, FD_X0 - 0.07, HALL_CEIL, fz + 0.03, STONE_L, MAT.Marble, deco("HallPanel"))
	bx(g, FD_X1 + 0.07, HF, fz, LINE_W - FIN_T / 2, HALL_CEIL, fz + 0.03, STONE_L, MAT.Marble, deco("HallPanel"))
	bx(g, FD_X0 - 0.07, HF + DOOR_H + 0.07, fz, FD_X1 + 0.07, HALL_CEIL, fz + 0.03, STONE_L, MAT.Marble, deco("HallPanel"))
	bx(g, LINE_W + FIN_T / 2, HF, fz, HX1, HALL_CEIL, fz + 0.03, STONE_L, MAT.Marble, deco("HallPanel"))
	-- 핀(세대 경계벽) 돌출부 마감
	bx(g, LINE_W - FIN_T / 2 - 0.02, HF, DEPTH + 0.25, LINE_W + FIN_T / 2 + 0.02, HALL_CEIL, DEPTH + 0.28, STONE_L, MAT.Marble, deco("PilasterCap"))
	bx(g, HX0, HF, fz + 0.03, FD_X0 - 0.07, HF + 0.1, fz + 0.045, rgb(60, 58, 56), MAT.Marble, deco("Skirting"))
	bx(g, FD_X1 + 0.07, HF, fz + 0.03, HX1, HF + 0.1, fz + 0.045, rgb(60, 58, 56), MAT.Marble, deco("Skirting"))
	casingZ(g, fz, fz + 0.05, FD_X0, FD_X1, HF, BRONZE)
	-- 뒷벽 라임스톤 + 엘리베이터 + 비상구
	bx(g, HX0, HF, HZ1 - 0.04, 8.6, HALL_CEIL, HZ1, STONE_L, MAT.Marble, deco("HallPanel"))
	bx(g, 16.6, HF, HZ1 - 0.04, HX1, HALL_CEIL, HZ1, STONE_L, MAT.Marble, deco("HallPanel"))
	elevatorBank(g, HF, "20", lobbyTarget, "1층으로 내려가기")
	stairDoor(g, HF, 17.3)
	sign(g, 6.6, HF + 1.3, HZ1 - 0.065, 7.9, HF + 1.85, HZ1 - 0.045, NID.Front, "20F", { bg = STONE_L, mat = MAT.Marble, color = rgb(120, 112, 100), pps = 50, maxd = 80, font = Enum.Font.GothamBlack })
	-- 2002호 (닫힌 문, 벽 앞에 붙은 철문 + 도어록 + 문패) + 택배 상자
	local n0, n1 = ND_X0, ND_X0 + DOOR_W
	bx(g, n0, HF, fz + 0.03, n1, HF + DOOR_H, fz + 0.08, rgb(86, 80, 74), MAT.Metal, solid("Door2002"))
	casingZ(g, fz + 0.03, fz + 0.09, n0, n1, HF, rgb(70, 66, 62))
	bx(g, n0 + 0.08, HF + 0.95, fz + 0.08, n0 + 0.16, HF + 1.3, fz + 0.115, rgb(20, 20, 22), MAT.SmoothPlastic, deco("DoorLock"))
	bx(g, n0 + 0.095, HF + 1.18, fz + 0.115, n0 + 0.145, HF + 1.26, fz + 0.125, rgb(80, 150, 220), MAT.Neon, deco("DoorLockPad"))
	bx(g, n0 + 0.06, HF + 1.0, fz + 0.08, n0 + 0.2, HF + 1.02, fz + 0.12, STEEL, MAT.Metal, deco("DoorPull"))
	sign(g, n1 + 0.15, HF + 1.55, fz + 0.03, n1 + 0.4, HF + 1.67, fz + 0.045, NID.Back, "2002", { bg = rgb(40, 40, 42), color = rgb(230, 220, 200), pps = 100, maxd = 40 })
	bx(g, n0 + 0.1, HF, fz + 0.35, n0 + 0.5, HF + 0.28, fz + 0.65, rgb(176, 136, 92), MAT.Cardboard, solid("Parcel"))
	bx(g, n0 + 0.14, HF + 0.28, fz + 0.4, n0 + 0.4, HF + 0.42, fz + 0.6, rgb(190, 152, 104), MAT.Cardboard, deco("Parcel"))
	-- 2001호 문패 + 초인종(카메라)
	sign(g, FD_X1 + 0.15, HF + 1.55, fz + 0.03, FD_X1 + 0.4, HF + 1.67, fz + 0.045, NID.Back, "2001", { bg = rgb(40, 40, 42), color = rgb(230, 220, 200), pps = 100, maxd = 40 })
	bx(g, FD_X1 + 0.2, HF + 1.25, fz + 0.03, FD_X1 + 0.32, HF + 1.42, fz + 0.06, rgb(30, 30, 32), MAT.SmoothPlastic, deco("DoorBell"))
	-- 소화전함 (동쪽 벽)
	local hb = bx(g, HX1 - 0.16, HF + 0.55, 10.45, HX1, HF + 1.45, 11.25, rgb(196, 34, 30), MAT.Metal, solid("Hydrant"))
	Kit.label(hb, NID.Left, "소화전", { color = rgb(255, 255, 255), pixelsPerStud = 60, maxDistance = 60 })
	Kit.ball(g, V(HX1 - 0.06, HF + 1.6, 10.85), M(0.09), rgb(255, 40, 30), MAT.Neon, deco("HydrantLamp"))
	-- 천장 감지등 2 + 광원
	local l1 = cyl(g, 9.6, HALL_CEIL - 0.02, 11.05, 0.03, 0.3, PANEL_WARM, MAT.Neon, neon("SensorLight"))
	cyl(g, 15.6, HALL_CEIL - 0.02, 11.05, 0.03, 0.3, PANEL_WARM, MAT.Neon, neon("SensorLight"))
	light(l1, "PointLight", { color = rgb(255, 224, 186), brightness = 1.0, range = M(6) })
	plant(g, 6.75, HF, 11.75, 0.34, 0.4, 0.6, 0.8, rng, rgb(70, 68, 64))
end

------------------------------------------------------------------------------------------------------
-- 5) 2001호
--    평면(로컬 m): 세대 x 0..12.4, z 0..9.6 (앞=발코니)
--      발코니 x 0..8.0, z 0..1.5 | 거실 x 3.0..8.0, z 1.62..6.2 | 식당 x 0..3.0 | 주방 x 0..6.25, z 6.2..9.6
--      복도 x 6.4..8.0, z 5.0..8.3 | 현관 x 6.4..8.0, z 8.42..9.6 (현관문 z 9.6 벽, 홀 쪽으로 밖여닫이)
--      안방 x 8.15..12.4, z 0.2..5.0 | 욕실 z 5.12..7.2 | 서재 z 7.32..9.6
------------------------------------------------------------------------------------------------------
local W4X0, W4X1 = 8.0, 8.15 -- 거실/복도 ↔ 안방·욕실·서재 벽

local function unitEnvelope(ext: Model)
	-- 뒷벽(z 9.6..9.85): 주방 창 + 현관문 개구부
	local z0, z1 = 9.6, DEPTH
	local ky0, ky1 = UF + 1.05, UF + 2.1
	bx(ext, 0, SLAB_TOP, z0, 0.8, TOPY, z1, WALL_EXT, MAT.Concrete, solid("BackWall"))
	bx(ext, 0.8, SLAB_TOP, z0, 2.6, ky0, z1, WALL_EXT, MAT.Concrete, solid("BackWall"))
	bx(ext, 0.8, ky1, z0, 2.6, TOPY, z1, WALL_EXT, MAT.Concrete, solid("BackWall"))
	bx(ext, 2.6, SLAB_TOP, z0, FD_X0, TOPY, z1, WALL_EXT, MAT.Concrete, solid("BackWall"))
	bx(ext, FD_X0, HF + DOOR_H, z0, FD_X1, TOPY, z1, WALL_EXT, MAT.Concrete, solid("BackWall"))
	bx(ext, FD_X1, SLAB_TOP, z0, LINE_W - FIN_T / 2, TOPY, z1, WALL_EXT, MAT.Concrete, solid("BackWall"))
	-- 주방 창
	local wf = rgb(240, 240, 238)
	bx(ext, 0.8, ky0, 9.66, 2.6, ky0 + 0.05, 9.8, wf, MAT.SmoothPlastic, deco("WinFrame"))
	bx(ext, 0.8, ky1 - 0.05, 9.66, 2.6, ky1, 9.8, wf, MAT.SmoothPlastic, deco("WinFrame"))
	bx(ext, 0.8, ky0, 9.66, 0.85, ky1, 9.8, wf, MAT.SmoothPlastic, deco("WinFrame"))
	bx(ext, 2.55, ky0, 9.66, 2.6, ky1, 9.8, wf, MAT.SmoothPlastic, deco("WinFrame"))
	bx(ext, 1.67, ky0, 9.66, 1.73, ky1, 9.8, wf, MAT.SmoothPlastic, deco("WinMullion"))
	bx(ext, 0.85, ky0 + 0.05, 9.71, 2.55, ky1 - 0.05, 9.75, GLASS_C, MAT.Glass, glassO("KitchenGlass", 0.62))
	-- 현관문 틀(철제, 개구부 안쪽)
	bx(ext, FD_X0, HF, z0, FD_X0 + 0.05, HF + DOOR_H, z1, BRONZE, MAT.Metal, solid("DoorFrame"))
	bx(ext, FD_X1 - 0.05, HF, z0, FD_X1, HF + DOOR_H, z1, BRONZE, MAT.Metal, solid("DoorFrame"))
	bx(ext, FD_X0, HF + DOOR_H - 0.05, z0, FD_X1, HF + DOOR_H, z1, BRONZE, MAT.Metal, solid("DoorFrame"))
	bx(ext, FD_X0, SLAB_TOP, z0, FD_X1, HF + 0.008, z1, MARBLE_D, MAT.Marble, solid("DoorThreshold"))
	-- 안방 전면 창(확장형: 바닥~천장 유리, 가운데 멀리언, 안전 바)
	local bx0, bx1 = W4X1, LINE_W - FIN_T / 2
	bx(ext, bx0, SLAB_TOP, 0.0, bx1, UF + 0.05, 0.2, rgb(70, 72, 76), MAT.Metal, solid("WinSill"))
	bx(ext, bx0, CEIL, 0.0, bx1, TOPY, 0.2, rgb(70, 72, 76), MAT.Metal, solid("WinHead"))
	bx(ext, (bx0 + bx1) / 2 - 0.03, UF + 0.05, 0.02, (bx0 + bx1) / 2 + 0.03, CEIL, 0.18, rgb(70, 72, 76), MAT.Metal, solid("WinMullion"))
	bx(ext, bx0, UF + 0.05, 0.08, bx1, CEIL, 0.12, GLASS_C, MAT.Glass, glassO("BedroomGlass", 0.68))
	bx(ext, bx0, UF + 0.92, 0.0, bx1, UF + 0.96, 0.05, rgb(70, 72, 76), MAT.Metal, deco("SafetyBar"))
	-- 발코니 유리 난간(바닥 채널 + 강화유리 + 손스침)
	local dk = UF - 0.07
	bx(ext, 0, SLAB_TOP, 0.0, W4X0, dk + 0.1, 0.1, rgb(70, 72, 76), MAT.Metal, solid("RailShoe"))
	bx(ext, 0, dk + 0.1, 0.03, W4X0, dk + 1.12, 0.07, RAIL_GLASS, MAT.Glass, glassO("BalconyGlass", 0.7))
	bx(ext, 0, dk + 1.12, -0.01, W4X0, dk + 1.18, 0.11, OAK, MAT.Wood, solid("BalconyHandrail"))
end

local function unitInterior(g: Model, rng: Random)
	--------------------------------------------------------------------------------------------------
	-- 바닥 / 천장 / 벽
	--------------------------------------------------------------------------------------------------
	bx(g, 0, SLAB_TOP, 1.62, 6.4, UF, 9.6, OAK, MAT.WoodPlanks, solid("FloorWood"))
	bx(g, 6.4, SLAB_TOP, 1.62, W4X0, UF, 8.3, OAK, MAT.WoodPlanks, solid("FloorWood"))
	bx(g, W4X0, SLAB_TOP, 0.2, LINE_W - FIN_T / 2, UF, 5.0, OAK, MAT.WoodPlanks, solid("FloorWood"))
	bx(g, W4X0, SLAB_TOP, 7.2, LINE_W - FIN_T / 2, UF, 9.6, OAK, MAT.WoodPlanks, solid("FloorWood"))
	bx(g, W4X0, SLAB_TOP, 5.0, LINE_W - FIN_T / 2, UF - 0.03, 7.2, TILE_D, MAT.CeramicTiles, solid("FloorBath"))
	bx(g, 6.4, SLAB_TOP, 8.42, W4X0, HF, 9.6, rgb(92, 90, 88), MAT.CeramicTiles, solid("FloorEntry"))
	bx(g, 6.4, SLAB_TOP, 8.3, W4X0, UF + 0.012, 8.42, MARBLE_W, MAT.Marble, solid("EntryStep"))
	bx(g, 0, SLAB_TOP, 0.0, W4X0, UF - 0.07, 1.5, rgb(118, 90, 68), MAT.WoodPlanks, solid("BalconyDeck"))
	bx(g, 0, SLAB_TOP, 1.5, W4X0, UF + 0.025, 1.62, rgb(150, 152, 156), MAT.Metal, solid("SlideTrack"))
	bx(g, 0, CEIL, 0, LINE_W - FIN_T / 2, CEIL + 0.04, 9.6, CEIL_C, MAT.SmoothPlastic, solid("Ceiling"))
	-- 벽 (도배 화이트)
	local WC = PLASTER
	local w0, w1 = W4X0, W4X1
	local dh = UF + DOOR_H
	bx(g, w0, SLAB_TOP, 0.0, w1, TOPY, 3.9, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, dh, 3.9, w1, TOPY, 4.8, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, SLAB_TOP, 4.8, w1, TOPY, 5.5, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, dh, 5.5, w1, TOPY, 6.4, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, SLAB_TOP, 6.4, w1, TOPY, 7.45, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, dh, 7.45, w1, TOPY, 8.35, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, SLAB_TOP, 8.35, w1, TOPY, 9.6, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w1, SLAB_TOP, 5.0, LINE_W - FIN_T / 2, TOPY, 5.12, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w1, SLAB_TOP, 7.2, LINE_W - FIN_T / 2, TOPY, 7.32, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, 6.25, SLAB_TOP, 7.0, 6.4, TOPY, 9.6, WC, MAT.SmoothPlastic, solid("Wall"))
	-- 콘크리트 외벽/경계벽 실내면 도배
	local exw = LINE_W - FIN_T / 2
	bx(g, exw - 0.02, UF, 0.2, exw, CEIL, 5.0, WC, MAT.SmoothPlastic, deco("WallSkin"))
	bx(g, exw - 0.02, UF, 7.32, exw, CEIL, 9.6, WC, MAT.SmoothPlastic, deco("WallSkin"))
	bx(g, w1, UF, 9.58, exw - 0.02, CEIL, 9.6, WC, MAT.SmoothPlastic, deco("WallSkin"))
	bx(g, 0, UF, 1.62, 0.02, CEIL, 2.0, WC, MAT.SmoothPlastic, deco("WallSkin"))
	bx(g, 0, UF, 4.6, 0.02, CEIL, 9.6, WC, MAT.SmoothPlastic, deco("WallSkin"))
	bx(g, 0, UF, 2.0, 0.02, UF + 0.86, 4.6, WC, MAT.SmoothPlastic, deco("WallSkin"))
	bx(g, 0, UF + 2.1, 2.0, 0.02, CEIL, 4.6, WC, MAT.SmoothPlastic, deco("WallSkin"))
	bx(g, 6.8, HF, 9.58, FD_X0, CEIL, 9.6, WC, MAT.SmoothPlastic, deco("WallSkin"))
	bx(g, FD_X1, HF, 9.58, w0, CEIL, 9.6, WC, MAT.SmoothPlastic, deco("WallSkin"))
	bx(g, FD_X0, HF + DOOR_H, 9.58, FD_X1, CEIL, 9.6, WC, MAT.SmoothPlastic, deco("WallSkin"))
	casingZ(g, 9.56, 9.6, FD_X0, FD_X1, HF, BRONZE)
	-- 문틀
	casingX(g, w0, w1, 3.9, 4.8, UF, rgb(246, 244, 240))
	casingX(g, w0, w1, 5.5, 6.4, UF, rgb(246, 244, 240))
	casingX(g, w0, w1, 7.45, 8.35, UF, rgb(246, 244, 240))
	-- 걸레받이 (0.08 m)
	local SK = rgb(246, 244, 240)
	local function skirtX(x: number, s: number, za: number, zb: number, y0: number?)
		local yy = y0 or UF
		bx(g, x, yy, za, x + s * 0.018, yy + 0.08, zb, SK, MAT.SmoothPlastic, deco("Skirting"))
	end
	local function skirtZ(z: number, s: number, xa: number, xb: number)
		bx(g, xa, UF, z, xb, UF + 0.08, z + s * 0.018, SK, MAT.SmoothPlastic, deco("Skirting"))
	end
	skirtX(0.02, 1, 1.64, 6.38)
	skirtX(w0, -1, 4.86, 5.44)
	skirtX(w0, -1, 6.46, 7.39)
	skirtX(w1, 1, 0.22, 3.84)
	skirtX(LINE_W - FIN_T / 2 - 0.02, -1, 0.22, 1.1)
	skirtX(LINE_W - FIN_T / 2 - 0.02, -1, 4.1, 4.38)
	skirtX(6.4, 1, 7.02, 8.28)
	skirtZ(5.0, -1, w1, 9.18)

	--------------------------------------------------------------------------------------------------
	-- 문 (안방·욕실 열림, 서재 반쯤 열림) + 현관문(홀 쪽으로 열림)
	--------------------------------------------------------------------------------------------------
	local DL = rgb(240, 238, 234)
	local DH = rgb(150, 136, 110)
	doorLeaf(g, w1, 4.8 - 0.03, UF + 0.005, DOOR_W - 0.08, DOOR_H - 0.02, 0.04, -12, DL, MAT.SmoothPlastic, DH)
	doorLeaf(g, w1, 5.5 + 0.03, UF, DOOR_W - 0.08, DOOR_H - 0.02, 0.04, 14, DL, MAT.SmoothPlastic, DH)
	doorLeaf(g, w1, 8.35 - 0.03, UF + 0.005, DOOR_W - 0.08, DOOR_H - 0.02, 0.04, -45, DL, MAT.SmoothPlastic, DH)
	local FF = doorLeaf(g, FD_X0 + 0.06, DEPTH + 0.04, HF + 0.005, DOOR_W - 0.12, DOOR_H - 0.06, 0.06, 84, rgb(86, 80, 74), MAT.Metal, STEEL)
	local fw, fh = DOOR_W - 0.12, DOOR_H - 0.06
	fb(g, FF, fw / 2 - 0.13, 1.15 - fh / 2, 0.065, 0.075, 0.3, 0.035, rgb(18, 18, 20), MAT.SmoothPlastic, deco("DoorLock"))
	fb(g, FF, fw / 2 - 0.13, 1.22 - fh / 2, 0.088, 0.05, 0.08, 0.012, rgb(80, 150, 220), MAT.Neon, deco("DoorLockPad"))
	fb(g, FF, fw / 2 - 0.13, 1.1 - fh / 2, -0.06, 0.085, 0.32, 0.05, rgb(18, 18, 20), MAT.SmoothPlastic, deco("DoorLockIn"))
	fb(g, FF, 0.25, fh / 2 - 0.08, -0.065, 0.32, 0.06, 0.06, rgb(60, 60, 62), MAT.Metal, deco("DoorCloser"))

	--------------------------------------------------------------------------------------------------
	-- 발코니 / 미닫이 창 / 커튼
	--------------------------------------------------------------------------------------------------
	local frameC = rgb(70, 72, 76)
	local gy0, gy1 = UF + 0.025, CEIL - 0.05
	bx(g, 0, gy1, 1.5, W4X0, CEIL, 1.62, frameC, MAT.Metal, solid("SlideHead"))
	local slides = {
		{ 0.0, 2.05, 1.52, 1.55 }, -- 고정
		{ 1.95, 4.05, 1.57, 1.6 }, -- 닫힌 미닫이
		{ 5.95, W4X0, 1.57, 1.6 }, -- 열린 미닫이(오른쪽 고정창 위로 겹침)
		{ 5.95, W4X0, 1.52, 1.55 }, -- 고정
	}
	for _, s in slides do
		bx(g, s[1] + 0.05, gy0, s[3], s[2] - 0.05, gy1, s[4], GLASS_C, MAT.Glass, glassO("SlideGlass", 0.72))
		bx(g, s[1], gy0, s[3] - 0.005, s[1] + 0.05, gy1, s[4] + 0.005, frameC, MAT.Metal, deco("SlideStile"))
		bx(g, s[2] - 0.05, gy0, s[3] - 0.005, s[2], gy1, s[4] + 0.005, frameC, MAT.Metal, deco("SlideStile"))
	end
	-- 커튼 박스 + 쉬어 커튼(양옆으로 모음)
	bx(g, 0, CEIL - 0.05, 1.64, W4X0, CEIL, 1.8, rgb(220, 220, 218), MAT.Metal, deco("CurtainRail"))
	for _, c in { { 0.05, 0.6 }, { 7.4, 7.95 } } do
		for i = 0, 3 do
			local x0 = c[1] + i * (c[2] - c[1]) / 4
			local zz = 1.68 + (if i % 2 == 0 then 0 else 0.05)
			bx(g, x0, UF + 0.03, zz, x0 + (c[2] - c[1]) / 4 + 0.02, CEIL - 0.05, zz + 0.04, LINEN, MAT.Fabric, { name = "Curtain", collide = false, query = false, shadow = false, transparency = 0.18 })
		end
	end
	-- 발코니 라운지 체어(강을 봄) + 사이드 테이블 + 화분 + 랜턴
	local dk = UF - 0.07
	local CF = frameAt(4.7, dk, 0.78, 0)
	for _, lx in { -0.28, 0.28 } do
		for _, lz in { -0.28, 0.3 } do
			fb(g, CF, lx, 0.16, lz, 0.04, 0.32, 0.04, rgb(110, 80, 58), MAT.Wood, deco("ChairLeg"))
		end
		fb(g, CF, lx + (if lx < 0 then -0.02 else 0.02), 0.56, 0.0, 0.05, 0.04, 0.66, rgb(110, 80, 58), MAT.Wood, deco("ChairArm"))
	end
	fb(g, CF, 0, 0.34, 0.0, 0.62, 0.05, 0.64, rgb(110, 80, 58), MAT.Wood, solid("ChairSeat"))
	fb(g, CF, 0, SEAT - 0.02, -0.02, 0.56, 0.07, 0.56, rgb(236, 230, 216), MAT.Fabric, deco("ChairCushion"))
	Kit.box(g, CF * mcf(0, 0.72, 0.36) * CFrame.Angles(math.rad(22), 0, 0), SZ(0.6, 0.7, 0.05), rgb(110, 80, 58), MAT.Wood, solid("ChairBack"))
	Kit.box(g, CF * mcf(0, 0.74, 0.3) * CFrame.Angles(math.rad(22), 0, 0), SZ(0.52, 0.55, 0.07), rgb(236, 230, 216), MAT.Fabric, deco("ChairBackCushion"))
	Kit.box(g, CF * mcf(0.1, SEAT + 0.03, 0.05) * CFrame.Angles(0, math.rad(12), 0), SZ(0.45, 0.03, 0.35), rgb(150, 92, 70), MAT.Fabric, deco("Throw"))
	cyl(g, 5.4, dk, 0.7, 0.5, 0.06, rgb(40, 40, 42), MAT.Metal, deco("SideTableStem"))
	cyl(g, 5.4, dk, 0.7, 0.02, 0.32, rgb(40, 40, 42), MAT.Metal, deco("SideTableBase"))
	cyl(g, 5.4, dk + 0.5, 0.7, 0.025, 0.45, MARBLE_W, MAT.Marble, solid("SideTableTop"))
	cyl(g, 5.33, dk + 0.525, 0.66, 0.012, 0.13, rgb(250, 250, 248), MAT.SmoothPlastic, deco("Saucer"))
	cyl(g, 5.33, dk + 0.537, 0.66, 0.08, 0.075, rgb(250, 250, 248), MAT.SmoothPlastic, deco("Cup"))
	bx(g, 5.48, dk + 0.525, 0.72, 5.62, dk + 0.555, 0.92, rgb(36, 70, 110), MAT.SmoothPlastic, deco("Book"))
	plant(g, 0.5, dk, 0.55, 0.55, 0.55, 1.1, 1.5, rng, rgb(176, 104, 72))
	plant(g, 7.55, dk, 0.4, 0.32, 0.3, 0.45, 0.4, rng, rgb(176, 104, 72))
	plant(g, 7.15, dk, 0.32, 0.26, 0.24, 0.35, 0.3, rng, rgb(232, 228, 220))
	bx(g, 3.25, dk, 0.25, 3.45, dk + 0.32, 0.45, rgb(30, 30, 32), MAT.Metal, deco("Lantern"))
	local candle = cyl(g, 3.35, dk + 0.04, 0.35, 0.12, 0.07, LAMP, MAT.Neon, neon("LanternCandle"))
	light(candle, "PointLight", { color = rgb(255, 180, 110), brightness = 0.8, range = M(3) })
	cyl(g, 4.0, CEIL - 0.02, 0.75, 0.025, 0.22, PANEL_WARM, MAT.Neon, neon("BalconyLight"))

	--------------------------------------------------------------------------------------------------
	-- 거실: 아트월 + TV 콘솔 + 65" TV + 소파 + 러그 + 커피 테이블 + 스탠드 + 에어컨 + 식물
	--------------------------------------------------------------------------------------------------
	bx(g, w0 - 0.03, UF, 1.64, w0, CEIL, 3.86, MARBLE_W, MAT.Marble, solid("ArtWall"))
	for _, z in { 2.38, 3.12 } do
		bx(g, w0 - 0.045, UF, z - 0.008, w0 - 0.03, CEIL, z + 0.008, rgb(176, 160, 128), MAT.Metal, deco("ArtWallTrim"))
	end
	local tvz = 2.9
	bx(g, 7.5, UF + 0.14, tvz - 0.9, w0 - 0.045, UF + 0.45, tvz + 0.9, WALNUT, MAT.Wood, solid("TVConsole"))
	bx(g, 7.62, UF, tvz - 0.8, 7.9, UF + 0.14, tvz + 0.8, rgb(30, 30, 30), MAT.SmoothPlastic, deco("ConsolePlinth"))
	for _, z in { tvz - 0.3, tvz + 0.3 } do
		bx(g, 7.485, UF + 0.16, z - 0.008, 7.5, UF + 0.43, z + 0.008, rgb(60, 44, 32), MAT.Wood, deco("DrawerSeam"))
	end
	-- 65" (1.44 x 0.81 m) + 스탠드 + 사운드바
	local tvY = UF + 0.45 + 0.09 + 0.405
	bx(g, 7.72, tvY - 0.405, tvz - 0.72, 7.75, tvY + 0.405, tvz + 0.72, rgb(10, 10, 12), MAT.Glass, { name = "TV65", reflectance = 0.15, shadow = false })
	bx(g, 7.75, tvY - 0.3, tvz - 0.45, 7.8, tvY + 0.3, tvz + 0.45, rgb(24, 24, 26), MAT.SmoothPlastic, deco("TVBack"))
	bx(g, 7.75, UF + 0.45, tvz - 0.05, 7.79, tvY - 0.3, tvz + 0.05, rgb(40, 40, 42), MAT.Metal, deco("TVNeck"))
	bx(g, 7.62, UF + 0.45, tvz - 0.22, 7.9, UF + 0.465, tvz + 0.22, rgb(40, 40, 42), MAT.Metal, deco("TVFoot"))
	bx(g, 7.56, UF + 0.45, tvz - 0.55, 7.66, UF + 0.51, tvz + 0.55, rgb(46, 46, 50), MAT.Fabric, deco("Soundbar"))
	bx(g, 7.715, tvY - 0.4, tvz + 0.62, 7.72, tvY - 0.39, tvz + 0.63, rgb(255, 40, 30), MAT.Neon, deco("StandbyLed"))
	plant(g, 7.72, UF + 0.45, tvz + 0.82, 0.12, 0.12, 0.22, 0.2, rng, rgb(232, 228, 220))
	Kit.box(g, LCF(7.7, UF + 0.53, tvz - 0.8) * CFrame.Angles(0, 0, math.rad(-10)), SZ(0.02, 0.16, 0.13), rgb(34, 32, 30), MAT.Wood, deco("PhotoFrame"))
	Kit.box(g, LCF(7.688, UF + 0.531, tvz - 0.8) * CFrame.Angles(0, 0, math.rad(-10)), SZ(0.008, 0.12, 0.09), rgb(200, 176, 150), MAT.SmoothPlastic, deco("Photo"))
	-- 소파 (3인, 좌면 0.43 m, +X 를 봄)
	local SF = frameAt(3.68, UF, tvz, -90)
	for _, lx in { -1.0, 1.0 } do
		for _, lz in { -0.4, 0.4 } do
			fb(g, SF, lx, 0.05, lz, 0.04, 0.1, 0.04, rgb(40, 32, 26), MAT.Wood, deco("SofaLeg"))
		end
	end
	fb(g, SF, 0, 0.215, 0, 2.2, 0.23, 0.95, SOFA_C, MAT.Fabric, solid("SofaBase"))
	for _, ax in { -1.015, 1.015 } do
		fb(g, SF, ax, 0.36, 0, 0.17, 0.52, 0.95, SOFA_C, MAT.Fabric, solid("SofaArm"))
	end
	fb(g, SF, 0, 0.565, 0.3875, 1.86, 0.47, 0.175, SOFA_C, MAT.Fabric, solid("SofaBack"))
	for _, cx in { -0.62, 0, 0.62 } do
		fb(g, SF, cx, SEAT - 0.05, -0.15, 0.6, 0.1, 0.64, rgb(184, 178, 168), MAT.Fabric, deco("SeatCushion"))
		Kit.box(g, SF * mcf(cx, 0.6, 0.215) * CFrame.Angles(math.rad(8), 0, 0), SZ(0.6, 0.42, 0.16), rgb(184, 178, 168), MAT.Fabric, deco("BackCushion"))
	end
	Kit.box(g, SF * mcf(-0.8, 0.62, 0.05) * CFrame.Angles(math.rad(18), math.rad(12), math.rad(8)), SZ(0.45, 0.45, 0.13), rgb(198, 150, 64), MAT.Fabric, deco("Pillow"))
	Kit.box(g, SF * mcf(-0.42, 0.6, 0.08) * CFrame.Angles(math.rad(16), math.rad(-6), math.rad(-5)), SZ(0.42, 0.42, 0.12), rgb(232, 226, 210), MAT.Fabric, deco("Pillow"))
	Kit.box(g, SF * mcf(0.78, 0.62, 0.05) * CFrame.Angles(math.rad(18), math.rad(-10), math.rad(-9)), SZ(0.45, 0.45, 0.13), rgb(170, 96, 70), MAT.Fabric, deco("Pillow"))
	fb(g, SF, 1.015, 0.63, 0.05, 0.22, 0.02, 0.5, rgb(132, 140, 150), MAT.Fabric, deco("Throw"))
	fb(g, SF, 1.11, 0.42, 0.05, 0.02, 0.42, 0.5, rgb(132, 140, 150), MAT.Fabric, deco("ThrowHang"))
	-- 러그 + 커피 테이블 + 소품
	bx(g, 4.3, UF, 1.95, 7.2, UF + 0.015, 3.85, rgb(210, 200, 182), MAT.Carpet, deco("Rug"))
	bx(g, 4.42, UF + 0.015, 2.07, 7.08, UF + 0.022, 3.73, rgb(188, 176, 156), MAT.Carpet, deco("RugInner"))
	bx(g, 4.8, UF + 0.36, 2.3, 5.4, UF + 0.4, 3.5, OAK_L, MAT.Wood, solid("CoffeeTable"))
	for _, z in { 2.36, 3.44 } do
		bx(g, 4.85, UF + 0.022, z - 0.025, 5.35, UF + 0.36, z + 0.025, OAK_L, MAT.Wood, solid("CoffeeLeg"))
	end
	bx(g, 4.85, UF + 0.1, 2.39, 5.35, UF + 0.12, 3.41, OAK_L, MAT.Wood, deco("CoffeeShelf"))
	local by = UF + 0.4
	for i, b in { { 0.3, 0.22, rgb(42, 70, 110) }, { 0.27, 0.2, rgb(232, 228, 216) }, { 0.24, 0.17, rgb(150, 52, 44) } } do
		Kit.box(g, LCF(4.98, by + 0.015, 2.62) * CFrame.Angles(0, math.rad(i * 7), 0), SZ(b[2], 0.03, b[1]), b[3], MAT.SmoothPlastic, deco("Book"))
		by += 0.03
	end
	cyl(g, 5.2, UF + 0.4, 3.12, 0.09, 0.08, rgb(240, 238, 232), MAT.SmoothPlastic, deco("Mug"))
	bx(g, 5.235, UF + 0.42, 3.115, 5.26, UF + 0.47, 3.125, rgb(240, 238, 232), MAT.SmoothPlastic, deco("MugHandle"))
	cyl(g, 5.05, UF + 0.4, 3.3, 0.18, 0.1, GLASS_C, MAT.Glass, { name = "Vase", collide = false, query = false, shadow = false, transparency = 0.4 })
	for i = 0, 2 do
		Kit.ball(g, V(5.05 + (i - 1) * 0.05, UF + 0.64 + (i % 2) * 0.04, 3.3 + (i - 1) * 0.03), M(0.07), if i == 1 then rgb(236, 220, 200) else rgb(214, 110, 120), MAT.SmoothPlastic, deco("Flower"))
	end
	bx(g, 5.2, UF + 0.4, 2.45, 5.24, UF + 0.42, 2.62, rgb(30, 30, 32), MAT.SmoothPlastic, deco("Remote"))
	-- 플로어 스탠드
	cyl(g, 3.45, UF, 4.3, 0.025, 0.3, rgb(40, 40, 42), MAT.Metal, deco("LampBase"))
	cyl(g, 3.45, UF + 0.025, 4.3, 1.4, 0.03, rgb(40, 40, 42), MAT.Metal, deco("LampPole"))
	cyl(g, 3.45, UF + 1.36, 4.3, 0.32, 0.42, rgb(240, 230, 210), MAT.Fabric, { name = "LampShade", collide = false, query = false, shadow = false, transparency = 0.1 })
	local bulb = Kit.ball(g, V(3.45, UF + 1.42, 4.3), M(0.1), LAMP, MAT.Neon, neon("LampBulb"))
	light(bulb, "PointLight", { color = rgb(255, 196, 130), brightness = 1.2, range = M(3.6) })
	-- 스탠드형 에어컨 (복도 입구)
	bx(g, 7.6, UF, 4.95, 7.96, UF + 1.8, 5.32, rgb(246, 246, 244), MAT.SmoothPlastic, solid("AirCon"))
	bx(g, 7.585, UF + 1.25, 5.0, 7.6, UF + 1.7, 5.27, rgb(214, 216, 220), MAT.SmoothPlastic, deco("AirConGrille"))
	bx(g, 7.58, UF + 1.1, 5.1, 7.6, UF + 1.15, 5.17, rgb(80, 170, 255), MAT.Neon, deco("AirConDisplay"))
	-- 대형 화분(몬스테라)
	plant(g, 2.85, UF, 1.95, 0.42, 0.45, 0.85, 1.1, rng, rgb(240, 238, 232))
	-- 거실 천장: 매입 다운라이트 4 + 간접 조명 띠
	local dls = {}
	for _, p in { { 4.6, 2.3 }, { 4.6, 3.5 }, { 6.8, 2.3 }, { 6.8, 3.5 } } do
		table.insert(dls, cyl(g, p[1], CEIL - 0.015, p[2], 0.03, 0.12, PANEL_WARM, MAT.Neon, neon("DownLight")))
	end
	light(dls[3], "PointLight", { color = rgb(255, 214, 168), brightness = 0.9, range = M(5) })
	switchPlate(g, "x", w0, -1, 4.95, UF + 1.15)

	--------------------------------------------------------------------------------------------------
	-- 식당: 4인 식탁(0.75 m) + 의자 4 + 펜던트 2 + 서쪽 창 블라인드 + 액자 + 시계
	--------------------------------------------------------------------------------------------------
	local tx, tz = 1.5, 3.4
	bx(g, tx - 0.45, UF + TABLE_H - 0.04, tz - 0.8, tx + 0.45, UF + TABLE_H, tz + 0.8, OAK_L, MAT.Wood, solid("DiningTable"))
	for _, lx in { -0.38, 0.38 } do
		for _, lz in { -0.72, 0.72 } do
			bx(g, tx + lx - 0.025, UF, tz + lz - 0.025, tx + lx + 0.025, UF + TABLE_H - 0.04, tz + lz + 0.025, OAK_L, MAT.Wood, solid("TableLeg"))
		end
	end
	for _, c in { { 0.72, 3.0, -90 }, { 0.72, 3.8, -90 }, { 2.28, 3.0, 90 }, { 2.28, 3.8, 90 } } do
		local F = frameAt(c[1], UF, c[2], c[3])
		for _, lx in { -0.19, 0.19 } do
			for _, lz in { -0.17, 0.17 } do
				fb(g, F, lx, (SEAT - 0.05) / 2, lz, 0.03, SEAT - 0.05, 0.03, WALNUT, MAT.Wood, deco("ChairLeg"))
			end
		end
		fb(g, F, 0, SEAT - 0.035, 0, 0.44, 0.03, 0.42, WALNUT, MAT.Wood, solid("ChairSeat"))
		fb(g, F, 0, SEAT - 0.005, -0.01, 0.4, 0.03, 0.38, rgb(214, 204, 186), MAT.Fabric, deco("ChairPad"))
		fb(g, F, 0, SEAT + 0.24, 0.19, 0.42, 0.34, 0.03, WALNUT, MAT.Wood, deco("ChairBack"))
		-- 식기 (매트 + 접시 + 컵)
		local pl = frameAt(c[1] + (if c[3] < 0 then 0.55 else -0.55), UF + TABLE_H, c[2], 0)
		fb(g, pl, 0, 0.004, 0, 0.32, 0.008, 0.42, rgb(196, 186, 168), MAT.Fabric, deco("Placemat"))
		Kit.vcyl(g, (pl * mcf(0, 0.016, 0)).Position, M(0.015), M(0.24), rgb(250, 250, 248), MAT.SmoothPlastic, deco("Plate"))
		Kit.vcyl(g, (pl * mcf(0.1, 0.06, -0.15)).Position, M(0.1), M(0.07), GLASS_C, MAT.Glass, { name = "Glass", collide = false, query = false, shadow = false, transparency = 0.45 })
	end
	cyl(g, tx, UF + TABLE_H, tz, 0.07, 0.28, rgb(244, 242, 236), MAT.SmoothPlastic, deco("FruitBowl"))
	for i = 0, 3 do
		Kit.ball(g, V(tx + (i % 2 - 0.5) * 0.09, UF + TABLE_H + 0.1, tz + (i // 2 - 0.5) * 0.09), M(0.08), if i % 2 == 0 then rgb(236, 140, 40) else rgb(190, 40, 40), MAT.SmoothPlastic, deco("Fruit"))
	end
	for i, z in { 3.0, 3.8 } do
		cyl(g, tx, CEIL - 0.02, z, 0.02, 0.1, rgb(30, 30, 32), MAT.Metal, deco("PendantCanopy"))
		cyl(g, tx, UF + 1.65, z, CEIL - UF - 1.67, 0.015, rgb(30, 30, 32), MAT.SmoothPlastic, deco("PendantCord"))
		cyl(g, tx, UF + 1.45, z, 0.2, 0.3, rgb(36, 38, 40), MAT.Metal, deco("PendantShade"))
		local pb = cyl(g, tx, UF + 1.44, z, 0.012, 0.24, LAMP, MAT.Neon, neon("PendantBulb"))
		if i == 1 then
			light(pb, "PointLight", { color = rgb(255, 200, 140), brightness = 1.0, range = M(3.2) })
		end
	end
	-- 서쪽 창: 대리석 창대 + 롤 블라인드(절반)
	bx(g, -0.15, UF + 0.86, 1.95, 0.05, UF + 0.9, 4.65, MARBLE_W, MAT.Marble, deco("WinSill"))
	bx(g, 0.03, UF + 1.5, 2.0, 0.06, UF + 2.08, 4.6, LINEN, MAT.Fabric, deco("RollerBlind"))
	bx(g, 0.03, UF + 1.48, 2.0, 0.07, UF + 1.51, 4.6, rgb(200, 200, 198), MAT.Metal, deco("BlindBar"))
	picture(g, "x", 0.02, 1, 4.85, 5.65, UF + 1.3, UF + 1.95, rgb(64, 110, 150), rgb(214, 170, 90))
	-- 벽시계 (주방/복도 칸막이, 18:05)
	local ck = V(6.25 - 0.03, UF + 1.95, 7.65)
	Kit.hcyl(g, CFrame.new(ck), M(0.03), M(0.36), rgb(30, 30, 32), MAT.Metal, deco("ClockRim"))
	Kit.hcyl(g, CFrame.new(ck - Vector3.new(M(0.01), 0, 0)), M(0.02), M(0.32), rgb(248, 246, 240), MAT.SmoothPlastic, deco("ClockFace"))
	for _, hnd in { { 182, 0.08, 0.016 }, { 30, 0.13, 0.012 } } do
		local phi = math.rad(hnd[1])
		local L = hnd[2]
		Kit.box(g, CFrame.new(ck - Vector3.new(M(0.025), 0, 0)) * CFrame.Angles(phi, 0, 0) * mcf(0, L / 2, 0), SZ(0.012, L, hnd[3]), rgb(20, 20, 22), MAT.SmoothPlastic, deco("ClockHand"))
	end

	--------------------------------------------------------------------------------------------------
	-- 주방: ㄱ자 하부장(0.9 m) + 상부장 + 개수대 + 인덕션 + 후드 + 냉장고(1.8 m) + 아일랜드 + 소품
	--------------------------------------------------------------------------------------------------
	local ct = UF + COUNTER
	bx(g, 0.6, UF + 0.1, 9.0, 5.3, ct - 0.03, 9.6, WHITE_LAC, MAT.SmoothPlastic, solid("BaseCabinet"))
	bx(g, 0.6, UF, 9.05, 5.3, UF + 0.1, 9.6, rgb(50, 50, 52), MAT.SmoothPlastic, deco("Plinth"))
	bx(g, 0, UF + 0.1, 6.4, 0.6, ct - 0.03, 9.6, WHITE_LAC, MAT.SmoothPlastic, solid("BaseCabinet"))
	bx(g, 0, UF, 6.45, 0.55, UF + 0.1, 9.6, rgb(50, 50, 52), MAT.SmoothPlastic, deco("Plinth"))
	for _, x in { 1.15, 1.95, 2.55, 3.05, 3.75, 4.5 } do
		bx(g, x - 0.007, UF + 0.12, 8.985, x + 0.007, ct - 0.08, 9.0, rgb(150, 150, 150), MAT.SmoothPlastic, deco("DoorSeam"))
	end
	for _, y in { UF + 0.42, UF + 0.64 } do
		bx(g, 3.05, y - 0.007, 8.985, 3.75, y + 0.007, 9.0, rgb(150, 150, 150), MAT.SmoothPlastic, deco("DrawerSeam"))
	end
	bx(g, 0.6, ct - 0.08, 8.985, 5.3, ct - 0.05, 9.0, rgb(60, 60, 62), MAT.SmoothPlastic, deco("HandleChannel"))
	for _, z in { 7.0, 7.6, 8.2 } do
		bx(g, 0.6, UF + 0.12, z - 0.007, 0.615, ct - 0.08, z + 0.007, rgb(150, 150, 150), MAT.SmoothPlastic, deco("DoorSeam"))
	end
	bx(g, 0.6, ct - 0.08, 6.4, 0.615, ct - 0.05, 8.98, rgb(60, 60, 62), MAT.SmoothPlastic, deco("HandleChannel"))
	-- 상판(개수대 자리 비움)
	local sx0, sx1, sz0, sz1 = 1.15, 1.95, 9.07, 9.52
	bx(g, 0, ct - 0.03, 6.38, 0.62, ct, 9.6, MARBLE_W, MAT.Marble, solid("Countertop"))
	bx(g, 0.62, ct - 0.03, 8.98, sx0, ct, 9.6, MARBLE_W, MAT.Marble, solid("Countertop"))
	bx(g, sx1, ct - 0.03, 8.98, 5.32, ct, 9.6, MARBLE_W, MAT.Marble, solid("Countertop"))
	bx(g, sx0, ct - 0.03, 8.98, sx1, ct, sz0, MARBLE_W, MAT.Marble, solid("Countertop"))
	bx(g, sx0, ct - 0.03, sz1, sx1, ct, 9.6, MARBLE_W, MAT.Marble, solid("Countertop"))
	bx(g, sx0, ct - 0.05, sz0, sx1, ct - 0.035, sz1, rgb(160, 162, 166), MAT.Metal, deco("SinkBasin"))
	cyl(g, (sx0 + sx1) / 2, ct - 0.035, (sz0 + sz1) / 2, 0.006, 0.06, rgb(60, 60, 62), MAT.Metal, deco("Drain"))
	cyl(g, 1.55, ct, 9.5, 0.3, 0.04, rgb(200, 202, 206), MAT.Metal, deco("Faucet"))
	bx(g, 1.54, ct + 0.27, 9.3, 1.56, ct + 0.3, 9.5, rgb(200, 202, 206), MAT.Metal, deco("FaucetSpout"))
	cyl(g, 2.1, ct, 9.45, 0.18, 0.07, rgb(240, 240, 238), MAT.SmoothPlastic, deco("SoapPump"))
	-- 인덕션 + 후드
	bx(g, 3.1, ct, 9.04, 3.7, ct + 0.012, 9.56, rgb(14, 14, 16), MAT.Glass, { name = "Induction", collide = false, query = false, shadow = false, reflectance = 0.12 })
	for _, p in { { 3.25, 9.2, 0.2 }, { 3.55, 9.2, 0.16 }, { 3.4, 9.42, 0.18 } } do
		cyl(g, p[1], ct + 0.012, p[2], 0.004, p[3], rgb(70, 70, 74), MAT.SmoothPlastic, deco("HobRing"))
	end
	bx(g, 3.3, ct + 0.012, 9.045, 3.5, ct + 0.016, 9.06, rgb(255, 120, 60), MAT.Neon, deco("HobControls"))
	bx(g, 3.0, UF + 1.55, 9.1, 3.8, UF + 1.65, 9.6, STEEL, MAT.Metal, solid("Hood"))
	bx(g, 3.25, UF + 1.65, 9.3, 3.55, CEIL, 9.6, STEEL, MAT.Metal, solid("HoodChimney"))
	bx(g, 3.15, UF + 1.545, 9.2, 3.65, UF + 1.55, 9.3, rgb(255, 230, 190), MAT.Neon, deco("HoodLight"))
	-- 상부장 + 하부 LED
	bx(g, 3.85, UF + 1.45, 9.25, 5.3, CEIL, 9.6, WHITE_LAC, MAT.SmoothPlastic, solid("UpperCabinet"))
	bx(g, 4.57, UF + 1.47, 9.235, 4.585, CEIL - 0.02, 9.25, rgb(150, 150, 150), MAT.SmoothPlastic, deco("DoorSeam"))
	bx(g, 3.9, UF + 1.43, 9.28, 5.25, UF + 1.45, 9.34, rgb(255, 224, 180), MAT.Neon, neon("UnderCabinetLed"))
	bx(g, 0, UF + 1.45, 6.4, 0.35, CEIL, 8.95, WHITE_LAC, MAT.SmoothPlastic, solid("UpperCabinet"))
	for _, z in { 7.05, 7.7, 8.35 } do
		bx(g, 0.35, UF + 1.47, z - 0.007, 0.365, CEIL - 0.02, z + 0.007, rgb(150, 150, 150), MAT.SmoothPlastic, deco("DoorSeam"))
	end
	bx(g, 0.04, UF + 1.43, 6.45, 0.12, UF + 1.45, 8.9, rgb(255, 224, 180), MAT.Neon, neon("UnderCabinetLed"))
	-- 백스플래시 타일
	local BS = rgb(234, 232, 228)
	bx(g, 0.62, ct, 9.575, 5.32, UF + 1.05, 9.6, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, 0.62, UF + 1.05, 9.575, 0.8, UF + 1.45, 9.6, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, 2.6, UF + 1.05, 9.575, 5.32, UF + 1.45, 9.6, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, 0, ct, 6.4, 0.025, UF + 1.45, 8.98, BS, MAT.CeramicTiles, deco("Backsplash"))
	-- 냉장고(양문형 1.8 m) + 상부 수납
	local fx0, fx1, fz0 = 5.35, 6.22, 8.85
	bx(g, fx0, UF, fz0, fx1, UF + 1.8, 9.58, rgb(206, 200, 190), MAT.SmoothPlastic, solid("Fridge"))
	bx(g, (fx0 + fx1) / 2 - 0.006, UF + 0.76, fz0 - 0.012, (fx0 + fx1) / 2 + 0.006, UF + 1.8, fz0, rgb(120, 116, 110), MAT.SmoothPlastic, deco("FridgeSeam"))
	for _, y in { UF + 0.75, UF + 0.38 } do
		bx(g, fx0, y - 0.006, fz0 - 0.012, fx1, y + 0.006, fz0, rgb(120, 116, 110), MAT.SmoothPlastic, deco("FridgeSeam"))
	end
	for _, hx in { (fx0 + fx1) / 2 - 0.05, (fx0 + fx1) / 2 + 0.05 } do
		bx(g, hx - 0.012, UF + 0.95, fz0 - 0.05, hx + 0.012, UF + 1.5, fz0 - 0.012, STEEL, MAT.Metal, deco("FridgeHandle"))
	end
	bx(g, fx0 + 0.12, UF + 0.6, fz0 - 0.05, fx1 - 0.12, UF + 0.63, fz0 - 0.012, STEEL, MAT.Metal, deco("FridgeHandle"))
	bx(g, fx0 + 0.1, UF + 1.3, fz0 - 0.016, fx0 + 0.18, UF + 1.36, fz0 - 0.012, rgb(150, 200, 255), MAT.Neon, deco("FridgeDisplay"))
	bx(g, fx1 - 0.3, UF + 1.15, fz0 - 0.016, fx1 - 0.12, UF + 1.4, fz0 - 0.012, rgb(250, 240, 200), MAT.SmoothPlastic, deco("KidDrawing"))
	bx(g, fx1 - 0.24, UF + 1.24, fz0 - 0.02, fx1 - 0.18, UF + 1.32, fz0 - 0.016, rgb(220, 80, 80), MAT.SmoothPlastic, deco("DrawingSun"))
	bx(g, 5.33, UF + 1.85, 8.9, 6.24, CEIL, 9.6, WHITE_LAC, MAT.SmoothPlastic, solid("FridgeTopCabinet"))
	-- 아일랜드 + 바 스툴 2
	bx(g, 1.5, UF, 6.75, 4.3, ct - 0.03, 7.55, WALNUT, MAT.Wood, solid("Island"))
	bx(g, 1.45, ct - 0.03, 6.5, 4.35, ct, 7.6, MARBLE_W, MAT.Marble, solid("IslandTop"))
	for _, sx in { 2.3, 3.5 } do
		cyl(g, sx, UF, 6.2, 0.02, 0.4, rgb(40, 40, 42), MAT.Metal, deco("StoolBase"))
		cyl(g, sx, UF + 0.02, 6.2, 0.61, 0.05, rgb(40, 40, 42), MAT.Metal, deco("StoolPole"))
		cyl(g, sx, UF + 0.63, 6.2, 0.06, 0.38, rgb(150, 98, 64), MAT.Leather, solid("StoolSeat"))
	end
	cyl(g, 2.1, ct, 7.05, 0.08, 0.3, rgb(244, 242, 236), MAT.SmoothPlastic, deco("Bowl"))
	for i = 0, 4 do
		Kit.ball(g, V(2.1 + math.cos(i * 1.25) * 0.08, ct + 0.1, 7.05 + math.sin(i * 1.25) * 0.08), M(0.08), if i % 2 == 0 then rgb(120, 170, 60) else rgb(200, 50, 40), MAT.SmoothPlastic, deco("Fruit"))
	end
	plant(g, 3.9, ct, 7.2, 0.14, 0.13, 0.22, 0.2, rng, rgb(196, 120, 80))
	Kit.box(g, LCF(3.0, ct + 0.01, 7.1) * CFrame.Angles(0, math.rad(-15), 0), SZ(0.3, 0.02, 0.22), rgb(232, 226, 210), MAT.SmoothPlastic, deco("Cookbook"))
	-- 조리대 소품: 밥솥, 전기포트, 도마, 양념병, 커피머신, 식기 건조대
	cyl(g, 4.75, ct, 9.32, 0.24, 0.28, rgb(244, 244, 242), MAT.SmoothPlastic, deco("RiceCooker"))
	cyl(g, 4.75, ct + 0.24, 9.32, 0.03, 0.22, rgb(150, 40, 44), MAT.SmoothPlastic, deco("RiceCookerLid"))
	cyl(g, 4.3, ct, 9.38, 0.22, 0.16, rgb(40, 40, 42), MAT.Metal, deco("Kettle"))
	Kit.box(g, LCF(2.5, ct + 0.01, 9.22) * CFrame.Angles(0, math.rad(6), 0), SZ(0.42, 0.02, 0.28), OAK_L, MAT.Wood, deco("CuttingBoard"))
	Kit.ball(g, V(2.45, ct + 0.06, 9.2), M(0.08), rgb(230, 120, 40), MAT.SmoothPlastic, deco("Veg"))
	Kit.ball(g, V(2.58, ct + 0.06, 9.25), M(0.09), rgb(90, 140, 60), MAT.SmoothPlastic, deco("Veg"))
	cyl(g, 2.85, ct, 9.48, 0.2, 0.06, rgb(40, 22, 14), MAT.Glass, deco("SoySauce"))
	cyl(g, 2.95, ct, 9.5, 0.24, 0.06, rgb(150, 140, 40), MAT.Glass, deco("OliveOil"))
	bx(g, 0.1, ct, 7.1, 0.5, ct + 0.36, 7.45, rgb(36, 36, 38), MAT.Metal, deco("CoffeeMachine"))
	bx(g, 0.62, ct, 9.1, 1.08, ct + 0.18, 9.5, STEEL, MAT.Metal, deco("DishRack"))
	for i = 0, 2 do
		bx(g, 0.7 + i * 0.12, ct + 0.04, 9.15, 0.71 + i * 0.12, ct + 0.26, 9.45, rgb(248, 248, 246), MAT.SmoothPlastic, deco("Dish"))
	end
	plant(g, 0.3, ct, 8.7, 0.14, 0.13, 0.22, 0.18, rng, rgb(232, 228, 220))
	-- 주방 조명: 아일랜드 위 라인 조명 + 광원
	local kl = bx(g, 1.7, CEIL - 0.02, 7.0, 4.1, CEIL + 0.01, 7.12, PANEL_WARM, MAT.Neon, neon("KitchenLine"))
	light(kl, "PointLight", { color = rgb(255, 226, 190), brightness = 0.85, range = M(4) })
	cyl(g, 2.6, CEIL - 0.015, 8.9, 0.03, 0.12, PANEL_WARM, MAT.Neon, neon("DownLight"))
	switchPlate(g, "x", 6.25, -1, 7.15, UF + 1.15)

	--------------------------------------------------------------------------------------------------
	-- 복도 · 현관: 신발장(간접 조명) + 디딤판 + 월패드 + 신발 + 우산 + 액자
	--------------------------------------------------------------------------------------------------
	local sc0, sc1 = 6.4, 6.8
	bx(g, sc0, HF + 0.22, 8.45, sc1, UF + 0.95, 9.58, WHITE_LAC, MAT.SmoothPlastic, solid("ShoeCabinet"))
	bx(g, sc0, UF + 1.3, 8.45, sc1, CEIL, 9.58, WHITE_LAC, MAT.SmoothPlastic, solid("ShoeCabinet"))
	bx(g, sc0, UF + 0.95, 8.45, sc0 + 0.03, UF + 1.3, 9.58, WALNUT, MAT.Wood, deco("NicheBack"))
	bx(g, sc0 + 0.03, UF + 1.28, 8.47, sc1 - 0.02, UF + 1.3, 9.56, rgb(255, 220, 170), MAT.Neon, neon("NicheLed"))
	bx(g, sc0 + 0.02, HF + 0.2, 8.5, sc1 - 0.04, HF + 0.22, 9.55, rgb(255, 214, 160), MAT.Neon, neon("ShoeCabinetLed"))
	bx(g, sc1, HF + 0.24, 9.0 - 0.007, sc1 + 0.012, UF + 0.93, 9.0 + 0.007, rgb(150, 150, 150), MAT.SmoothPlastic, deco("DoorSeam"))
	bx(g, sc1, UF + 1.35, 9.02, sc1 + 0.012, CEIL - 0.05, 9.55, rgb(196, 206, 214), MAT.Glass, { name = "Mirror", collide = false, query = false, shadow = false, reflectance = 0.35 })
	cyl(g, 6.62, UF + 0.95, 8.75, 0.12, 0.07, rgb(190, 170, 140), MAT.Glass, deco("Diffuser"))
	bx(g, 6.5, UF + 0.95, 9.1, 6.7, UF + 0.97, 9.3, WALNUT, MAT.Wood, deco("KeyTray"))
	for i, s in { { 7.15, 9.2, rgb(245, 245, 245) }, { 7.45, 9.25, rgb(40, 40, 44) } } do
		for _, dx in { -0.06, 0.06 } do
			bx(g, s[1] + dx - 0.045, HF, s[2] - 0.13, s[1] + dx + 0.045, HF + 0.08, s[2] + 0.13, s[3], if i == 1 then MAT.Fabric else MAT.Leather, deco("Shoe"))
		end
	end
	for _, dx in { -0.06, 0.06 } do
		bx(g, 7.2 + dx - 0.05, UF + 0.012, 8.0, 7.2 + dx + 0.05, UF + 0.04, 8.27, rgb(170, 160, 150), MAT.Fabric, deco("Slipper"))
	end
	Kit.cylAlongY(g, LCF(7.88, HF + 0.45, 9.48) * CFrame.Angles(0, 0, math.rad(6)), M(0.9), M(0.05), rgb(30, 44, 70), MAT.Fabric, deco("Umbrella"))
	-- 월패드(비디오폰) + 스위치
	bx(g, w0 - 0.025, UF + 1.3, 8.55, w0, UF + 1.55, 8.88, rgb(246, 246, 244), MAT.SmoothPlastic, deco("WallPad"))
	local wp = bx(g, w0 - 0.04, UF + 1.33, 8.58, w0 - 0.025, UF + 1.52, 8.8, rgb(40, 60, 90), MAT.Neon, deco("WallPadScreen"))
	Kit.label(wp, NID.Left, "18:05\n11.07 (토)", { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 120, maxDistance = 40 })
	switchPlate(g, "x", w0, -1, 8.98, UF + 1.15)
	picture(g, "x", 6.4, 1, 7.35, 8.15, UF + 1.25, UF + 1.85, rgb(196, 120, 80), rgb(60, 80, 110))
	local el = cyl(g, 7.2, CEIL - 0.015, 9.0, 0.03, 0.2, PANEL_WARM, MAT.Neon, neon("EntryLight"))
	light(el, "PointLight", { color = rgb(255, 220, 180), brightness = 0.7, range = M(2.6) })
	cyl(g, 7.2, CEIL - 0.015, 6.6, 0.03, 0.12, PANEL_WARM, MAT.Neon, neon("DownLight"))

	--------------------------------------------------------------------------------------------------
	-- 안방: 퀸 침대(0.45 m) + 협탁 2 + 스탠드 + 붙박이장 + 책상 + 의자 + 벽걸이 에어컨 + 블라인드 + 액자
	--------------------------------------------------------------------------------------------------
	local ex = LINE_W - FIN_T / 2 -- 12.4 (세대 경계벽 안쪽면)
	bx(g, 10.5, UF, 1.95, 12.1, UF + 0.08, 3.25, rgb(30, 28, 26), MAT.SmoothPlastic, deco("BedPlinth"))
	bx(g, 10.3, UF + 0.08, 1.78, 12.25, UF + 0.28, 3.42, WALNUT, MAT.Wood, solid("BedFrame"))
	bx(g, 10.35, UF + 0.28, 1.83, 12.22, UF + 0.45, 3.37, rgb(246, 246, 244), MAT.Fabric, solid("Mattress"))
	local DUV = rgb(176, 188, 200)
	bx(g, 10.3, UF + 0.45, 1.8, 11.72, UF + 0.51, 3.4, DUV, MAT.Fabric, deco("Duvet"))
	bx(g, 10.3, UF + 0.3, 1.785, 11.72, UF + 0.5, 1.8, DUV, MAT.Fabric, deco("DuvetSide"))
	bx(g, 10.3, UF + 0.3, 3.4, 11.72, UF + 0.5, 3.415, DUV, MAT.Fabric, deco("DuvetSide"))
	bx(g, 10.285, UF + 0.3, 1.785, 10.3, UF + 0.5, 3.415, DUV, MAT.Fabric, deco("DuvetFoot"))
	bx(g, 11.72, UF + 0.45, 1.82, 11.86, UF + 0.55, 3.38, rgb(190, 200, 210), MAT.Fabric, deco("DuvetFold"))
	bx(g, 10.55, UF + 0.51, 1.79, 10.95, UF + 0.525, 3.41, rgb(198, 150, 64), MAT.Fabric, deco("BedRunner"))
	for _, z in { 2.24, 2.96 } do
		Kit.box(g, LCF(12.05, UF + 0.53, z) * CFrame.Angles(0, 0, math.rad(-14)), SZ(0.16, 0.16, 0.62), rgb(250, 250, 248), MAT.Fabric, deco("Pillow"))
	end
	Kit.box(g, LCF(11.88, UF + 0.6, 2.6) * CFrame.Angles(0, 0, math.rad(-10)), SZ(0.12, 0.3, 0.45), rgb(132, 140, 150), MAT.Fabric, deco("Cushion"))
	bx(g, 12.25, UF + 0.1, 1.65, ex - 0.025, UF + 1.15, 3.55, rgb(150, 138, 124), MAT.Fabric, solid("Headboard"))
	-- 협탁 + 스탠드 / 시계·휴대폰·물컵
	for i, nz in { { 1.12, 1.58 }, { 3.62, 4.08 } } do
		bx(g, 11.9, UF, nz[1], ex - 0.03, UF + 0.52, nz[2], OAK, MAT.Wood, solid("Nightstand"))
		bx(g, 11.885, UF + 0.3, nz[1] + 0.03, 11.9, UF + 0.31, nz[2] - 0.03, rgb(90, 66, 46), MAT.Wood, deco("DrawerSeam"))
		Kit.ball(g, V(11.88, UF + 0.42, (nz[1] + nz[2]) / 2), M(0.03), rgb(176, 160, 128), MAT.Metal, deco("Knob"))
		if i == 1 then
			cyl(g, 12.12, UF + 0.52, 1.35, 0.24, 0.12, rgb(214, 204, 186), MAT.SmoothPlastic, deco("LampBase"))
			cyl(g, 12.12, UF + 0.74, 1.35, 0.22, 0.3, rgb(244, 236, 220), MAT.Fabric, { name = "LampShade", collide = false, query = false, shadow = false, transparency = 0.1 })
			local nb = Kit.ball(g, V(12.12, UF + 0.84, 1.35), M(0.08), LAMP, MAT.Neon, neon("LampBulb"))
			light(nb, "PointLight", { color = rgb(255, 196, 130), brightness = 1.0, range = M(3) })
			bx(g, 11.95, UF + 0.52, 1.18, 12.1, UF + 0.55, 1.4, rgb(150, 52, 44), MAT.SmoothPlastic, deco("Book"))
		else
			local clk = bx(g, 12.05, UF + 0.52, 3.7, 12.15, UF + 0.6, 3.86, rgb(30, 30, 32), MAT.SmoothPlastic, deco("AlarmClock"))
			Kit.label(clk, NID.Left, "18:05", { color = rgb(255, 120, 60), glow = true, pixelsPerStud = 120, maxDistance = 30 })
			bx(g, 12.0, UF + 0.52, 3.9, 12.18, UF + 0.53, 3.98, rgb(20, 20, 22), MAT.Glass, deco("Phone"))
			cyl(g, 12.25, UF + 0.52, 3.95, 0.11, 0.07, GLASS_C, MAT.Glass, { name = "WaterGlass", collide = false, query = false, shadow = false, transparency = 0.4 })
		end
	end
	-- 붙박이장 (바닥~천장, 4짝)
	bx(g, 9.2, UF, 4.4, ex, CEIL, 4.98, rgb(232, 228, 220), MAT.SmoothPlastic, solid("Wardrobe"))
	for _, x in { 10.0, 10.8, 11.6 } do
		bx(g, x - 0.006, UF + 0.02, 4.385, x + 0.006, CEIL - 0.02, 4.4, rgb(170, 166, 160), MAT.SmoothPlastic, deco("WardrobeSeam"))
	end
	for _, x in { 9.93, 10.07, 11.53, 11.67 } do
		bx(g, x - 0.01, UF + 0.8, 4.36, x + 0.01, UF + 1.4, 4.385, rgb(176, 160, 128), MAT.Metal, deco("WardrobeHandle"))
	end
	-- 책상 + 의자 + 노트북 + 스탠드
	local dt = UF + TABLE_H
	bx(g, w1, dt - 0.03, 0.55, w1 + 0.6, dt, 1.75, OAK_L, MAT.Wood, solid("Desk"))
	bx(g, w1 + 0.03, UF, 0.57, w1 + 0.57, dt - 0.03, 0.6, OAK_L, MAT.Wood, solid("DeskLeg"))
	bx(g, w1 + 0.03, UF, 1.7, w1 + 0.57, dt - 0.03, 1.73, OAK_L, MAT.Wood, solid("DeskLeg"))
	bx(g, w1 + 0.03, dt - 0.15, 0.95, w1 + 0.55, dt - 0.03, 1.45, OAK_L, MAT.Wood, deco("DeskDrawer"))
	local LF = frameAt(w1 + 0.32, dt, 1.2, -90)
	fb(g, LF, 0, 0.008, 0, 0.32, 0.015, 0.22, rgb(176, 178, 182), MAT.Metal, deco("LaptopBase"))
	Kit.box(g, LF * mcf(0, 0.11, 0.11) * CFrame.Angles(math.rad(15), 0, 0), SZ(0.32, 0.21, 0.01), rgb(176, 178, 182), MAT.Metal, deco("LaptopLid"))
	Kit.box(g, LF * mcf(0, 0.11, 0.104) * CFrame.Angles(math.rad(15), 0, 0), SZ(0.29, 0.18, 0.005), rgb(70, 100, 140), MAT.Neon, deco("LaptopScreen"))
	cyl(g, w1 + 0.2, dt, 0.72, 0.02, 0.14, rgb(30, 30, 32), MAT.Metal, deco("DeskLampBase"))
	Kit.box(g, LCF(w1 + 0.2, dt + 0.22, 0.75) * CFrame.Angles(math.rad(12), 0, 0), SZ(0.015, 0.42, 0.015), rgb(30, 30, 32), MAT.Metal, deco("DeskLampArm"))
	cyl(g, w1 + 0.24, dt + 0.36, 0.82, 0.08, 0.13, rgb(30, 30, 32), MAT.Metal, deco("DeskLampHead"))
	cyl(g, w1 + 0.42, dt, 1.62, 0.09, 0.08, rgb(214, 96, 70), MAT.SmoothPlastic, deco("Mug"))
	for i = 0, 2 do
		bx(g, w1 + 0.05, dt + i * 0.03, 1.48, w1 + 0.27, dt + i * 0.03 + 0.03, 1.66, BOOK_COLORS[i + 3], MAT.SmoothPlastic, deco("Book"))
	end
	plant(g, w1 + 0.45, dt, 0.68, 0.09, 0.08, 0.13, 0.08, rng, rgb(232, 228, 220))
	local OC = frameAt(w1 + 0.85, UF, 1.15, 90)
	fb(g, OC, 0, 0.02, 0, 0.6, 0.03, 0.06, rgb(40, 40, 42), MAT.Metal, deco("ChairStar"))
	fb(g, OC, 0, 0.02, 0, 0.06, 0.03, 0.6, rgb(40, 40, 42), MAT.Metal, deco("ChairStar"))
	Kit.vcyl(g, (OC * mcf(0, 0.22, 0)).Position, M(0.36), M(0.05), rgb(40, 40, 42), MAT.Metal, deco("ChairGas"))
	fb(g, OC, 0, 0.44, 0, 0.48, 0.07, 0.46, rgb(60, 62, 66), MAT.Fabric, solid("OfficeSeat"))
	fb(g, OC, 0, 0.78, 0.22, 0.44, 0.52, 0.05, rgb(60, 62, 66), MAT.Fabric, deco("OfficeBack"))
	-- 벽걸이 에어컨 + 러그 + 액자 + 블라인드 + 조명
	bx(g, w1, UF + 1.95, 2.3, w1 + 0.22, UF + 2.25, 3.25, rgb(246, 246, 244), MAT.SmoothPlastic, deco("WallAC"))
	bx(g, w1 + 0.22, UF + 1.97, 2.32, w1 + 0.23, UF + 2.0, 3.23, rgb(200, 200, 198), MAT.SmoothPlastic, deco("WallACVane"))
	bx(g, 9.5, UF, 1.4, 11.5, UF + 0.015, 3.8, rgb(200, 196, 190), MAT.Carpet, deco("BedRug"))
	picture(g, "x", ex - 0.02, -1, 2.15, 3.05, UF + 1.35, UF + 1.95, rgb(120, 150, 170), rgb(230, 214, 186))
	bx(g, w1 + 0.03, CEIL - 0.09, 0.2, ex, CEIL, 0.32, rgb(240, 240, 238), MAT.SmoothPlastic, deco("BlindBox"))
	bx(g, w1 + 0.05, UF + 1.55, 0.24, ex - 0.02, CEIL - 0.09, 0.27, rgb(226, 220, 208), MAT.Fabric, { name = "RollerBlind", collide = false, query = false, shadow = false, transparency = 0.15 })
	bx(g, w1 + 0.05, UF + 1.53, 0.23, ex - 0.02, UF + 1.56, 0.28, rgb(200, 200, 198), MAT.Metal, deco("BlindBar"))
	local bl = cyl(g, 10.3, CEIL - 0.02, 2.6, 0.035, 0.5, rgb(170, 150, 120), MAT.Neon, neon("BedroomLight"))
	light(bl, "PointLight", { color = rgb(255, 214, 168), brightness = 0.55, range = M(4) })
	switchPlate(g, "x", w1, 1, 3.75, UF + 1.15)
	plant(g, 8.55, UF, 3.5, 0.32, 0.38, 0.55, 0.8, rng, rgb(196, 190, 180))

	--------------------------------------------------------------------------------------------------
	-- 욕실: 벽·바닥 타일, 세면대 + 거울, 양변기, 샤워 유리 + 레인 샤워, 수건, 조명
	--------------------------------------------------------------------------------------------------
	local bf = UF - 0.03
	local bz0, bz1 = 5.12, 7.2
	local TW = TILE_W
	bx(g, w1, bf, bz0, w1 + 0.025, CEIL, 5.5, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, w1, bf, 6.4, w1 + 0.025, CEIL, bz1, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, w1, UF + DOOR_H + 0.06, 5.5, w1 + 0.025, CEIL, 6.4, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, ex - 0.025, bf, bz0, ex, CEIL, bz1, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, w1 + 0.025, bf, bz0, ex - 0.025, CEIL, bz0 + 0.025, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, w1 + 0.025, bf, bz1 - 0.025, ex - 0.025, CEIL, bz1, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, 11.3, bf, bz0 + 0.025, ex - 0.025, CEIL, bz0 + 0.04, rgb(120, 124, 128), MAT.CeramicTiles, deco("ShowerAccentTile"))
	bx(g, w0, SLAB_TOP, 5.5, w1, UF + 0.012, 6.4, MARBLE_W, MAT.Marble, solid("BathThreshold"))
	-- 세면대(벽걸이) + 볼 + 수전 + 거울 + 조명
	local vz1 = bz1 - 0.025
	bx(g, 8.7, UF + 0.4, 6.7, 9.9, UF + 0.82, vz1, WALNUT, MAT.Wood, solid("Vanity"))
	bx(g, 8.68, UF + 0.82, 6.68, 9.92, UF + 0.85, vz1, rgb(244, 244, 242), MAT.Marble, solid("VanityTop"))
	cyl(g, 9.3, UF + 0.85, 6.92, 0.12, 0.42, rgb(250, 250, 248), MAT.SmoothPlastic, deco("Basin"))
	cyl(g, 9.3, UF + 0.95, 6.92, 0.012, 0.32, rgb(214, 220, 224), MAT.SmoothPlastic, deco("BasinWater"))
	cyl(g, 9.3, UF + 0.85, 7.12, 0.28, 0.035, rgb(200, 202, 206), MAT.Metal, deco("BasinFaucet"))
	bx(g, 9.29, UF + 1.1, 6.98, 9.31, UF + 1.13, 7.12, rgb(200, 202, 206), MAT.Metal, deco("BasinSpout"))
	cyl(g, 8.85, UF + 0.85, 6.95, 0.12, 0.07, rgb(214, 224, 232), MAT.Glass, { name = "ToothCup", collide = false, query = false, shadow = false, transparency = 0.3 })
	cyl(g, 9.75, UF + 0.85, 6.98, 0.16, 0.06, rgb(236, 230, 220), MAT.SmoothPlastic, deco("SoapPump"))
	bx(g, 8.75, UF + 1.0, vz1 - 0.012, 9.85, UF + 1.85, vz1, rgb(204, 214, 220), MAT.Glass, { name = "Mirror", collide = false, query = false, shadow = false, reflectance = 0.4 })
	bx(g, 8.8, UF + 1.88, vz1 - 0.05, 9.8, UF + 1.92, vz1, rgb(240, 236, 226), MAT.Neon, neon("MirrorLight"))
	-- 양변기(벽걸이형) + 휴지걸이
	bx(g, 10.28, UF, 6.98, 10.72, UF + 0.95, vz1, rgb(240, 240, 238), MAT.SmoothPlastic, solid("ToiletWall"))
	bx(g, 10.45, UF + 0.75, 6.97, 10.55, UF + 0.85, 6.98, rgb(200, 202, 206), MAT.Metal, deco("FlushPlate"))
	bx(g, 10.31, UF + 0.15, 6.48, 10.69, UF + 0.4, 6.98, rgb(250, 250, 248), MAT.SmoothPlastic, solid("ToiletBowl"))
	bx(g, 10.3, UF + 0.4, 6.46, 10.7, UF + 0.425, 6.98, rgb(250, 250, 248), MAT.SmoothPlastic, deco("ToiletSeat"))
	bx(g, 10.31, UF + 0.425, 6.48, 10.69, UF + 0.445, 6.97, rgb(246, 246, 244), MAT.SmoothPlastic, deco("ToiletLid"))
	bx(g, 10.95, UF + 0.72, vz1 - 0.06, 11.1, UF + 0.74, vz1, rgb(200, 202, 206), MAT.Metal, deco("PaperHolder"))
	Kit.hcyl(g, LCF(11.02, UF + 0.68, vz1 - 0.07), M(0.11), M(0.11), rgb(250, 250, 248), MAT.Fabric, deco("PaperRoll"))
	-- 샤워: 유리 칸막이 + 상부 프로파일 + 레인 샤워 + 수전 + 선반 + 배수구
	bx(g, 11.25, bf, bz0 + 0.025, 11.27, UF + 2.0, 6.55, rgb(214, 228, 236), MAT.Glass, glassO("ShowerGlass", 0.75))
	bx(g, 11.24, UF + 2.0, bz0 + 0.025, 11.28, UF + 2.03, 6.55, rgb(200, 202, 206), MAT.Metal, deco("ShowerProfile"))
	bx(g, 11.24, bf, bz0 + 0.025, 11.28, UF + 2.03, bz0 + 0.06, rgb(200, 202, 206), MAT.Metal, deco("ShowerProfile"))
	bx(g, 11.85, UF + 2.15, 5.8, ex - 0.025, UF + 2.17, 5.83, rgb(200, 202, 206), MAT.Metal, deco("ShowerArm"))
	bx(g, 11.73, UF + 2.12, 5.69, 11.98, UF + 2.15, 5.94, rgb(200, 202, 206), MAT.Metal, deco("RainShower"))
	bx(g, ex - 0.04, UF + 1.05, 5.75, ex - 0.025, UF + 1.2, 5.9, rgb(200, 202, 206), MAT.Metal, deco("Mixer"))
	bx(g, ex - 0.08, UF + 1.11, 5.81, ex - 0.04, UF + 1.14, 5.84, rgb(200, 202, 206), MAT.Metal, deco("MixerLever"))
	bx(g, ex - 0.03, UF + 0.9, 6.5, ex - 0.025, UF + 1.9, 6.53, rgb(200, 202, 206), MAT.Metal, deco("SlideBar"))
	bx(g, ex - 0.16, UF + 1.1, 6.65, ex - 0.025, UF + 1.12, 7.0, rgb(200, 202, 206), MAT.Metal, deco("ShowerShelf"))
	cyl(g, ex - 0.09, UF + 1.12, 6.72, 0.2, 0.06, rgb(60, 100, 140), MAT.SmoothPlastic, deco("Shampoo"))
	cyl(g, ex - 0.09, UF + 1.12, 6.85, 0.17, 0.055, rgb(236, 230, 220), MAT.SmoothPlastic, deco("BodyWash"))
	bx(g, 11.4, bf, 7.06, 12.3, bf + 0.012, 7.12, rgb(150, 152, 156), MAT.Metal, deco("LinearDrain"))
	-- 수건걸이 + 수건, 발매트
	bx(g, w1 + 0.025, UF + 1.1, 6.55, w1 + 0.06, UF + 1.12, 7.05, rgb(200, 202, 206), MAT.Metal, deco("TowelBar"))
	bx(g, w1 + 0.06, UF + 0.75, 6.6, w1 + 0.1, UF + 1.13, 7.0, rgb(214, 210, 202), MAT.Fabric, deco("Towel"))
	bx(g, 8.8, bf, 6.15, 9.8, bf + 0.015, 6.6, rgb(150, 160, 170), MAT.Carpet, deco("BathMat"))
	local bp = bx(g, 9.9, CEIL - 0.02, 5.85, 10.6, CEIL + 0.01, 6.45, PANEL_COOL, MAT.Neon, neon("BathPanel"))
	light(bp, "PointLight", { color = rgb(236, 240, 255), brightness = 0.8, range = M(2.8) })
	bx(g, 11.0, CEIL - 0.012, 5.45, 11.2, CEIL, 5.65, rgb(200, 200, 198), MAT.SmoothPlastic, deco("ExhaustFan"))
	switchPlate(g, "x", w0, -1, 6.5, UF + 1.15)

	--------------------------------------------------------------------------------------------------
	-- 서재(작은방): 1.8 m 책장 + 책상 + 모니터 + 의자 + 조명
	--------------------------------------------------------------------------------------------------
	local sz0, sz1 = 7.32, 9.6
	local kz0, kz1, kx0 = sz0 + 0.15, sz1 - 0.15, ex - 0.36
	bx(g, ex - 0.03, UF, kz0, ex, UF + 1.8, kz1, WALNUT, MAT.Wood, solid("BookcaseBack"))
	bx(g, kx0, UF, kz0, ex - 0.03, UF + 1.8, kz0 + 0.025, WALNUT, MAT.Wood, solid("BookcaseSide"))
	bx(g, kx0, UF, kz1 - 0.025, ex - 0.03, UF + 1.8, kz1, WALNUT, MAT.Wood, solid("BookcaseSide"))
	for i = 0, 5 do
		local yy = UF + 0.06 + i * 0.345
		bx(g, kx0, yy - 0.025, kz0 + 0.025, ex - 0.03, yy, kz1 - 0.025, WALNUT, MAT.Wood, solid("Shelf"))
		if i < 5 and room(40) then
			local z = kz0 + 0.05
			while z < kz1 - 0.08 do
				local t = rng:NextNumber(0.03, 0.06)
				if z + t > kz1 - 0.03 then
					break
				end
				local h = rng:NextNumber(0.17, 0.29)
				bx(g, ex - 0.04 - rng:NextNumber(0.2, 0.28), yy, z, ex - 0.04, yy + h, z + t, BOOK_COLORS[rng:NextInteger(1, #BOOK_COLORS)], MAT.SmoothPlastic, deco("Book"))
				z += t + 0.004
				if rng:NextNumber() < 0.1 then
					z += rng:NextNumber(0.08, 0.2)
				end
			end
		end
	end
	bx(g, 9.3, UF + TABLE_H - 0.03, sz1 - 0.6, 11.4, UF + TABLE_H, sz1 - 0.02, OAK_L, MAT.Wood, solid("StudyDesk"))
	for _, x in { 9.33, 11.37 } do
		bx(g, x - 0.03, UF, sz1 - 0.58, x + 0.03, UF + TABLE_H - 0.03, sz1 - 0.04, OAK_L, MAT.Wood, solid("StudyDeskLeg"))
	end
	bx(g, 10.0, UF + TABLE_H + 0.12, sz1 - 0.2, 10.7, UF + TABLE_H + 0.52, sz1 - 0.17, rgb(18, 18, 20), MAT.SmoothPlastic, deco("Monitor"))
	bx(g, 10.02, UF + TABLE_H + 0.14, sz1 - 0.205, 10.68, UF + TABLE_H + 0.5, sz1 - 0.2, rgb(56, 80, 110), MAT.Neon, deco("MonitorScreen"))
	bx(g, 10.32, UF + TABLE_H, sz1 - 0.18, 10.38, UF + TABLE_H + 0.13, sz1 - 0.12, rgb(40, 40, 42), MAT.Metal, deco("MonitorStand"))
	bx(g, 10.1, UF + TABLE_H, sz1 - 0.48, 10.55, UF + TABLE_H + 0.02, sz1 - 0.33, rgb(40, 40, 42), MAT.SmoothPlastic, deco("Keyboard"))
	local SC = frameAt(10.35, UF, 8.55, 180)
	fb(g, SC, 0, 0.02, 0, 0.6, 0.03, 0.06, rgb(40, 40, 42), MAT.Metal, deco("ChairStar"))
	fb(g, SC, 0, 0.02, 0, 0.06, 0.03, 0.6, rgb(40, 40, 42), MAT.Metal, deco("ChairStar"))
	Kit.vcyl(g, (SC * mcf(0, 0.22, 0)).Position, M(0.36), M(0.05), rgb(40, 40, 42), MAT.Metal, deco("ChairGas"))
	fb(g, SC, 0, 0.44, 0, 0.48, 0.07, 0.46, rgb(30, 30, 32), MAT.Fabric, solid("OfficeSeat"))
	fb(g, SC, 0, 0.8, 0.22, 0.44, 0.56, 0.05, rgb(30, 30, 32), MAT.Fabric, deco("OfficeBack"))
	picture(g, "z", sz0, 1, 9.3, 10.3, UF + 1.3, UF + 1.9, rgb(214, 170, 90), nil)
	bx(g, 8.6, UF, 7.6, 9.6, UF + 0.015, 9.2, rgb(120, 110, 104), MAT.Carpet, deco("StudyRug"))
	local stl = cyl(g, 10.3, CEIL - 0.02, 8.4, 0.035, 0.4, rgb(170, 152, 120), MAT.Neon, neon("StudyLight"))
	light(stl, "PointLight", { color = rgb(255, 218, 176), brightness = 0.7, range = M(3.5) })
end

------------------------------------------------------------------------------------------------------
-- 부지 선정: 강변북로 뒤 CityFrom + 27 m, X -600..+200 사이에서 다리 축(±120)을 피하고 비어 있는 곳
------------------------------------------------------------------------------------------------------
local function findSite(): (number, number)
	local zf = Config.NearBank.CityFrom + M(FRONT_SET)
	local bxr = Config.Bridge.X
	local candidates = { -260, -320, -200, -380, -140, -440, -80, -500, -560, -20 }
	for _, x0 in candidates do
		local wx0, wx1 = x0 + M(RES_X0), x0 + M(RES_X1)
		local clearBridge = wx1 < bxr - 120 or wx0 > bxr + 120
		if clearBridge and Kit.isFree(wx0, zf + M(RES_Z0), wx1, zf + M(RES_Z1), 0) then
			return x0, zf
		end
	end
	return candidates[1], zf
end

------------------------------------------------------------------------------------------------------
function ShowHome.build(ctx: any)
	local model: Model = ctx.model
	local rng: Random = ctx.rng
	partsAtStart = Kit.stats.parts
	lightsUsed = 0
	X0, Z0 = findSite()
	GY = Config.Level.City
	Kit.reserve(X0 + M(RES_X0), Z0 + M(RES_Z0), X0 + M(RES_X1), Z0 + M(RES_Z1), "ShowHome")

	-- 창 불빛: Facade 의 집 불빛을 블룸 대비 한 톤 낮춤(Apartments 와 같은 톤)
	local lit = {}
	for i, c in (ctx.Facade and ctx.Facade.LIT_HOME or { P.WindowWarm, P.WindowWarmDim, P.WindowGold }) :: { Color3 } do
		lit[i] = c:Lerp(Color3.new(0, 0, 0), 0.34)
	end

	-- 엘리베이터 도착 지점(HumanoidRootPart 높이 ≈ 바닥 + 3 stud, 캐릭터는 -Z 를 봄)
	local unitTarget = V(9.6, HF, 11.1) + Vector3.new(0, 3.2, 0)
	local lobbyTarget = V(12.6, LOBBY_FL, 10.2) + Vector3.new(0, 3.2, 0)

	local ext = Kit.group(model, "Shell") -- 외피: Persistent(원경에서도 보임) — 바닥 슬래브 포함
	shell(ext, rng, lit)
	lobbyEnvelope(ext)
	hallEnvelope(ext)
	unitEnvelope(ext)
	grounds(Kit.group(model, "Grounds"), rng)
	lobbyInterior(Kit.group(model, "Lobby", Config.InteriorStreaming), rng, unitTarget)
	hallInterior(Kit.group(model, "Hall20F", Config.InteriorStreaming), rng, lobbyTarget)
	unitInterior(Kit.group(model, "Unit2001", Config.InteriorStreaming), rng)

	-- 다른 모듈/클라이언트용 정보
	model:SetAttribute("Parts", used())
	model:SetAttribute("Lights", lightsUsed)
	model:SetAttribute("Entrance", V(12.6, LOBBY_FL, -1.0))
	model:SetAttribute("UnitTarget", unitTarget)
	model:SetAttribute("LobbyTarget", lobbyTarget)
	model:SetAttribute("ViewCamPos", V(5.0, UF + EYE, 2.3))
	model:SetAttribute("ViewCamLook", Config.Landmark.Tower.Center + Vector3.new(0, 520, 0))
	if used() > PART_BUDGET then
		warn(string.format("[ShowHome] 파트 예산 초과: %d / %d", used(), PART_BUDGET))
	end
end

return ShowHome
