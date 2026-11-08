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
--     엘리베이터 2대(태그 SeoulElevator → 20층 엘리베이터 홀), 관리사무소 공지 게시판, 무인택배함, 비상구 계단 문,
--     피난구유도등 · 옥내소화전 · 소화기 · 하향식 스프링클러 · 감지기 · CCTV.
--   * 20층 엘리베이터 홀: 2001호(밖여닫이 현관문 열림) / 2002호, 엘리베이터 2대(SeoulElevator → 1층 로비), 옥내소화전,
--     비상구(유도등 · 소화기), 센서등, 스프링클러, CCTV, 문패.
--   * 2001호(34평형, 전용 84 m², 신축 기본 사양): 현관(0.15 m 단차, 키큰 신발장 + 전신거울 + 니치, 3연동 중문, 월패드,
--     일괄소등, 센서등) · 거실(포세린 아트월, 벽걸이 65" TV + 콘솔, 우물천장 + 간접 LED, 4-way 시스템에어컨, 다운라이트,
--     커튼, 소파 좌면 0.43 m, 러그, 보일러 온도조절기) · 식당(4인 식탁 0.75 m, 펜던트) · 주방(ㄱ자 0.9 m 쿼츠 상판, 언더싱크,
--     정수기 수전, 인덕션, 슬림 후드, 천장까지 상부장, 4도어 냉장고 + 스탠드 김치냉장고, 아일랜드, 식기건조대) · 안방(퀸 침대,
--     붙박이장, 화장대, 1-way 에어컨) · 욕실(젠다이, 벽걸이 변기 + 비데, 해바라기 샤워, 수납 거울장, 수건장, SMC 천장) ·
--     서재(2칸 책장, 27" 모니터 책상, 프린터) · 발코니(세탁기 + 건조기, 천장형 빨래건조대, 라운지 체어).
--     세대 천장마다 감지기 + 컨실드 스프링클러(11층 이상). 콘센트 0.3 m, 스위치 1.2 m.
--     거실/발코니에서 정면(-Z, 약간 왼쪽)으로 한강 너머 잠실 타워가 보이는 것이 히어로 뷰.
--   * 바닥 슬래브는 외피(Persistent) 모델에 있어 실내(Atomic 스트리밍)가 늦게 로드돼도 엘리베이터 도착 지점에 발판이 있음.
--   * 발자국 Kit.reserveRect(조경 포함) → Apartments 가 이 자리를 비움. 파트 ≤ 3500, 광원 ≤ 40.

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)

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
-- 2001호 거실 우물천장(천장 개구 + 위층 슬래브를 그만큼 얇게): 깊이 12 cm, 간접 LED 코브
local REC = 0.12
local RX0, RX1, RZ0, RZ1 = 3.7, 7.4, 2.05, 5.55
-- 주방 창(뒷벽) 개구: x, UF 기준 높이
local KW_X0, KW_X1, KW_Y0, KW_Y1 = 0.8, 2.6, 1.3, 2.1

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

-- X 에 수직인 벽(두께 x0..x1)의 문틀: 개구부 z a..b, 바닥 y0 부터 DOOR_H. e0/e1 = 벽면에서 -X/+X 쪽으로 튀어나온 두께(m)
local function casingX(parent: Instance, x0: number, x1: number, a: number, b: number, y0: number, color: Color3, e0: number?, e1: number?)
	local xa, xb = x0 - (e0 or 0.02), x1 + (e1 or 0.02)
	bx(parent, xa, y0, a - 0.06, xb, y0 + DOOR_H + 0.06, a + 0.02, color, MAT.SmoothPlastic, deco("Casing"))
	bx(parent, xa, y0, b - 0.02, xb, y0 + DOOR_H + 0.06, b + 0.06, color, MAT.SmoothPlastic, deco("Casing"))
	bx(parent, xa, y0 + DOOR_H - 0.02, a + 0.02, xb, y0 + DOOR_H + 0.06, b - 0.02, color, MAT.SmoothPlastic, deco("CasingHead"))
end
-- Z 에 수직인 벽(z0..z1)의 문틀: 개구부 x a..b
local function casingZ(parent: Instance, z0: number, z1: number, a: number, b: number, y0: number, color: Color3)
	bx(parent, a - 0.06, y0, z0 - 0.02, a + 0.02, y0 + DOOR_H + 0.06, z1 + 0.02, color, MAT.Metal, deco("Casing"))
	bx(parent, b - 0.02, y0, z0 - 0.02, b + 0.06, y0 + DOOR_H + 0.06, z1 + 0.02, color, MAT.Metal, deco("Casing"))
	bx(parent, a + 0.02, y0 + DOOR_H - 0.02, z0 - 0.02, b - 0.02, y0 + DOOR_H + 0.06, z1 + 0.02, color, MAT.Metal, deco("CasingHead"))
end

-- 벽에 붙는 판: axis "x" → 벽면 x = w, 방 쪽 방향 s(±1). off0..off1 = 벽면에서 방 쪽으로 거리(m), a = 벽을 따라, y = 높이
local function wb(parent: Instance, axis: string, w: number, s: number, off0: number, off1: number, a0: number, a1: number, y0: number, y1: number, color: Color3, mat: Enum.Material, o: any?): BasePart
	if axis == "x" then
		return bx(parent, w + s * off0, y0, a0, w + s * off1, y1, a1, color, mat, o)
	end
	return bx(parent, a0, y0, w + s * off0, a1, y1, w + s * off1, color, mat, o)
end
-- 벽면 위 한 점의 CFrame(로컬 -Z = 방 쪽): Props.outlet / exitSign / hydrant 규약
local function wallCF(axis: string, w: number, s: number, along: number, y: number, off: number?): CFrame
	local o = off or 0
	local p = if axis == "x" then V(w + s * o, y, along) else V(along, y, w + s * o)
	local d = if axis == "x" then Vector3.new(s, 0, 0) else Vector3.new(0, 0, s)
	return CFrame.lookAt(p, p + d)
end
local function outlet(parent: Instance, axis: string, w: number, s: number, along: number, y: number, kind: string?)
	Props.outlet(parent, wallCF(axis, w, s, along, y), kind)
end

-- 천장 설비: 감지기(Props.ceilingKit 의 감지기 1개), 스프링클러(공용부 = 하향식 크롬 / 세대 = 컨실드 백색 커버)
local function detector(parent: Instance, x: number, z: number, ceilY: number)
	Props.ceilingKit(parent, CFrame.new(V(x - 0.4, ceilY, z)), 0.5, 0.02, { sprinkler = 0, smoke = 1 })
end
local function pendantSprinkler(parent: Instance, x: number, z: number, ceilY: number)
	Props.ceilingKit(parent, CFrame.new(V(x, ceilY, z)), 1, 1, { sprinkler = 1, smoke = 0 })
end
local function concealedSprinkler(parent: Instance, x: number, z: number, ceilY: number)
	-- 컨실드형 헤드: 지름 75 mm 백색 커버 플레이트(천장 1.6 cm 아래로) + 링
	cyl(parent, x, ceilY - 0.015, z, 0.05, 0.09, rgb(228, 228, 224), MAT.SmoothPlastic, deco("SprinklerRing"))
	cyl(parent, x, ceilY - 0.03, z, 0.03, 0.07, rgb(248, 248, 246), MAT.SmoothPlastic, deco("SprinklerCover"))
end
-- 매입 다운라이트(Neon 퍽, 천장 1.5 cm 아래로)
local function downlight(parent: Instance, x: number, z: number, ceilY: number, d: number?): BasePart
	return cyl(parent, x, ceilY - 0.015, z, 0.05, d or 0.09, PANEL_WARM, MAT.Neon, neon("DownLight"))
end

-- 스위치 판 (벽면 법선 축 axis "x"/"z", 벽면 좌표 w, 바깥 방향 s = ±1)
local function switchPlate(parent: Instance, axis: string, w: number, s: number, along: number, y: number)
	wb(parent, axis, w, s, 0, 0.015, along - 0.035, along + 0.035, y, y + 0.12, rgb(246, 246, 244), MAT.SmoothPlastic, deco("SwitchPlate"))
	wb(parent, axis, w, s, 0.015, 0.03, along - 0.022, along + 0.022, y + 0.02, y + 0.1, rgb(238, 238, 234), MAT.SmoothPlastic, deco("SwitchRocker"))
end

-- 액자 (벽면 법선 축, 벽면 좌표 w, 방향 s): 테두리 4변(3.5 cm) + 매트(1.5 cm) + 그림(3 cm, 2색이면 위아래로 나눔)
local function picture(parent: Instance, axis: string, w: number, s: number, a0: number, a1: number, y0: number, y1: number, art: Color3, art2: Color3?)
	local fw = 0.03
	local FR = rgb(34, 32, 30)
	local function sl(off0: number, off1: number, b0: number, b1: number, c0: number, c1: number, col: Color3, mat: Enum.Material, name: string)
		wb(parent, axis, w, s, off0, off1, b0, b1, c0, c1, col, mat, deco(name))
	end
	sl(0, 0.035, a0, a1, y1 - fw, y1, FR, MAT.Wood, "Frame")
	sl(0, 0.035, a0, a1, y0, y0 + fw, FR, MAT.Wood, "Frame")
	sl(0, 0.035, a0, a0 + fw, y0 + fw, y1 - fw, FR, MAT.Wood, "Frame")
	sl(0, 0.035, a1 - fw, a1, y0 + fw, y1 - fw, FR, MAT.Wood, "Frame")
	sl(0, 0.015, a0 + fw, a1 - fw, y0 + fw, y1 - fw, rgb(244, 242, 236), MAT.SmoothPlastic, "Mat")
	local ma, mb = a0 + (a1 - a0) * 0.18, a1 - (a1 - a0) * 0.18
	local mc, md = y0 + (y1 - y0) * 0.18, y1 - (y1 - y0) * 0.18
	if art2 then
		local split = mc + (md - mc) * 0.42
		sl(0.005, 0.03, ma, mb, mc, split, art2, MAT.SmoothPlastic, "Art")
		sl(0.005, 0.03, ma, mb, split, md, art, MAT.SmoothPlastic, "Art")
	else
		sl(0.005, 0.03, ma, mb, mc, md, art, MAT.SmoothPlastic, "Art")
	end
end

-- 작은 화분(다육/허브): 흙 윗면은 화분 테두리보다 1.5 cm 낮음
local HOUSE_LEAVES = { rgb(38, 82, 46), rgb(52, 98, 54), rgb(30, 70, 40), rgb(62, 110, 58) }
local function smallPlant(parent: Instance, x: number, y0: number, z: number, potD: number, potH: number, leafD: number, rng: Random, potColor: Color3?)
	cyl(parent, x, y0, z, potH, potD, potColor or rgb(232, 228, 220), MAT.SmoothPlastic, deco("Pot"))
	cyl(parent, x, y0 + potH - 0.035, z, 0.02, potD * 0.84, rgb(70, 54, 42), MAT.Ground, deco("Soil"))
	local top = y0 + potH - 0.015
	for i = 1, 4 do
		local a = i * 1.7 + rng:NextNumber(-0.3, 0.3)
		local s = leafD * rng:NextNumber(0.45, 0.65)
		local r = leafD * 0.22
		Kit.ellipsoid(parent, LCF(x + math.cos(a) * r, top + s * 0.35 + (i % 2) * leafD * 0.15, z + math.sin(a) * r), SZ(s, s * 0.75, s), HOUSE_LEAVES[rng:NextInteger(1, #HOUSE_LEAVES)], MAT.SmoothPlastic, deco("Leaves"))
	end
end
-- 큰 관엽식물(Props): kind "monstera" | "fiddle" | "areca" | "sansevieria", h = 전체 높이(m)
local function bigPlant(parent: Instance, kind: string, x: number, y0: number, z: number, h: number, rng: Random, potColor: Color3?)
	local f = (Props :: any)[kind]
	f(parent, LCF(x, y0, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), h, rng, potColor)
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
	-- 패닉바(문 안쪽 면에서 1.5 cm 이상 떨어진 손잡이 막대 + 브래킷)
	bx(parent, x0 + 0.12, fl + 0.98, zf - 0.115, x1 - 0.1, fl + 1.03, zf - 0.085, STEEL, MAT.Metal, deco("PushBar"))
	for _, px in { x0 + 0.14, x1 - 0.12 } do
		bx(parent, px - 0.02, fl + 0.96, zf - 0.085, px + 0.02, fl + 1.05, zf - 0.06, STEEL_D, MAT.Metal, deco("PushBarBracket"))
	end
	bx(parent, x0 + 0.06, fl + 1.02, zf - 0.08, x0 + 0.1, fl + 1.12, zf - 0.06, STEEL_D, MAT.Metal, deco("DoorHinge"))
	bx(parent, x0 + 0.08, fl + DOOR_H - 0.12, zf - 0.11, x0 + 0.45, fl + DOOR_H - 0.06, zf - 0.06, rgb(60, 60, 62), MAT.Metal, deco("DoorCloser"))
	-- 피난구유도등(문 위) + 소화기(받침대 + 표지)
	Props.exitSign(parent, CFrame.lookAt(V((x0 + x1) / 2, fl + DOOR_H + 0.155, zf - 0.04), V((x0 + x1) / 2, fl + DOOR_H + 0.155, zf - 1)))
	local ezf = zf - 0.04 - 0.125
	Props.extinguisher(parent, CFrame.lookAt(V(x1 + 0.35, fl, ezf), V(x1 + 0.35, fl, ezf - 1)), true)
end

------------------------------------------------------------------------------------------------------
-- 1) 외피: 슬래브 띠 · 유리 난간 · 조명 코어 · 핀 · 측벽 · 코어 · 옥상 · 1층 필로티/로비 외피
------------------------------------------------------------------------------------------------------
local function shell(ext: Model, rng: Random, lit: { Color3 })
	-- 층 슬래브(2층~지붕): 앞뒤로 튀어나온 가로 띠 + 실제 바닥
	for k = 2, FLOORS + 1 do
		local y = yb(k)
		local so = { name = "Slab" .. k, shadow = k == FLOORS + 1 }
		if k == UNIT_FL + 1 then
			-- 2001호 거실 우물천장 자리: 슬래브 아랫면을 REC + 5 cm 만큼 얇게(개구 둘레 4장 + 얇은 판)
			local y0, y1 = y - SLAB_DN, y + SLAB_UP
			bx(ext, -END_T, y0, -0.25, BL + END_T, y1, RZ0, WALL_EXT, MAT.Concrete, so)
			bx(ext, -END_T, y0, RZ1, BL + END_T, y1, DEPTH + 0.15, WALL_EXT, MAT.Concrete, { name = "Slab" .. k, shadow = false })
			bx(ext, -END_T, y0, RZ0, RX0, y1, RZ1, WALL_EXT, MAT.Concrete, { name = "Slab" .. k, shadow = false })
			bx(ext, RX1, y0, RZ0, BL + END_T, y1, RZ1, WALL_EXT, MAT.Concrete, { name = "Slab" .. k, shadow = false })
			bx(ext, RX0, CEIL + REC + 0.05, RZ0, RX1, y1, RZ1, WALL_EXT, MAT.Concrete, { name = "Slab" .. k, shadow = false })
		else
			bx(ext, -END_T, y - SLAB_DN, -0.25, BL + END_T, y + SLAB_UP, DEPTH + 0.15, WALL_EXT, MAT.Concrete, so)
		end
	end
	-- 앞면 유리 난간 + 손스침 / 뒷면 창 아래 띠 (20층 2001호 구간 제외)
	for k = 2, FLOORS do
		local y = yb(k) + SLAB_UP
		local fx0 = if k == UNIT_FL then LINE_W - FIN_T / 2 + 0.05 else 0
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
	bx(ext, -END_T, 0.02, -0.35, 0, wy0, DEPTH + 0.25, WALL_EXT, MAT.Concrete, solid("EndWallW"))
	bx(ext, -END_T, wy0, -0.35, 0, wy1, wz0, WALL_EXT, MAT.Concrete, solid("EndWallW"))
	bx(ext, -END_T, wy0, wz1, 0, wy1, DEPTH + 0.25, WALL_EXT, MAT.Concrete, solid("EndWallW"))
	bx(ext, -END_T, wy1, -0.35, 0, PARAPET, DEPTH + 0.25, WALL_EXT, MAT.Concrete, solid("EndWallW"))
	bx(ext, BL, 0.02, -0.35, BL + END_T, PARAPET, DEPTH + 0.25, WALL_EXT, MAT.Concrete, solid("EndWallE"))
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
	bx(ext, CORE_A0, 0.02, CORE_SPLIT, CORE_A1, CORE_TOP, CORE_Z1, WALL_CORE, MAT.Concrete, solid("CoreA"))
	bx(ext, CORE_A0, LOBBY_TOP - 0.05, DEPTH, CORE_A1, SLAB_TOP - 0.05, CORE_SPLIT, WALL_CORE, MAT.Concrete, solid("CoreAFront"))
	bx(ext, CORE_A0, TOPY + 0.05, DEPTH, CORE_A1, CORE_TOP, CORE_SPLIT, WALL_CORE, MAT.Concrete, solid("CoreAFront"))
	bx(ext, CORE_B0, 0.02, CORE_SPLIT, CORE_B1, CORE_TOP, CORE_Z1, WALL_CORE, MAT.Concrete, solid("CoreB"))
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
	bx(ext, CORE_B0, PAVE, 1.0, CORE_B0 + 0.25, LOBBY_TOP - 0.05, CORE_SPLIT, LIMESTONE, MAT.Limestone, solid("LobbyBWall"))
	bx(ext, CORE_B1 - 0.25, PAVE, 1.0, CORE_B1, LOBBY_TOP - 0.05, CORE_SPLIT, LIMESTONE, MAT.Limestone, solid("LobbyBWall"))
	bx(ext, CORE_B0 + 0.45, PAVE + 0.1, 1.6, CORE_B1 - 0.45, LOBBY_CEIL, CORE_SPLIT - 0.2, rgb(150, 122, 86), MAT.Neon, neon("LobbyBGlow", LIMESTONE))
	bx(ext, CORE_B0 + 0.25, PAVE, 1.0, CORE_B1 - 0.25, LOBBY_CEIL, 1.05, GLASS_C, MAT.Glass, glassO("LobbyBGlass", 0.55))
	bx(ext, CORE_B0 - 0.03, LOBBY_CEIL - 0.03, 0.95, CORE_B1 + 0.03, LOBBY_TOP - 0.02, 1.1, STEEL_D, MAT.Metal, solid("LobbyBFascia"))
	for i = 1, 5 do
		local x = CORE_B0 + 0.25 + i * (CORE_B1 - CORE_B0 - 0.5) / 6
		bx(ext, x - 0.03, PAVE + 0.02, 0.97, x + 0.03, LOBBY_CEIL + 0.05, 1.08, STEEL_D, MAT.Metal, deco("Mullion"))
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
	bx(ext, CORE_A0, 0.02, 1.0, LX0, LOBBY_TOP, LZ1, WALL_CORE, MAT.Concrete, solid("LobbyWallW"))
	bx(ext, LX1, 0.02, 1.0, CORE_A1, LOBBY_TOP, LZ1, WALL_CORE, MAT.Concrete, solid("LobbyWallE"))
	-- 정면 유리벽: 하부 걸레받이 채널(유리 아래 끝을 물고 있음) + 멀리언(위는 파사드 띠 속) + 자동문 상부 고정창
	local BASE_C = rgb(52, 54, 58)
	bx(ext, LX0, PAVE + 0.01, 0.99, DOOR_X0 - 0.04, LOBBY_FL + 0.08, 1.05, BASE_C, MAT.Metal, solid("GlassBase"))
	bx(ext, DOOR_X1 + 0.04, PAVE + 0.01, 0.99, LX1, LOBBY_FL + 0.08, 1.05, BASE_C, MAT.Metal, solid("GlassBase"))
	bx(ext, LX0, LOBBY_FL + 0.05, 1.005, DOOR_X0, LOBBY_CEIL, 1.035, GLASS_C, MAT.Glass, glassO("LobbyGlass", 0.62))
	bx(ext, DOOR_X1, LOBBY_FL + 0.05, 1.005, LX1, LOBBY_CEIL, 1.035, GLASS_C, MAT.Glass, glassO("LobbyGlass", 0.62))
	bx(ext, DOOR_X0, 2.42, 1.005, DOOR_X1, LOBBY_CEIL, 1.035, GLASS_C, MAT.Glass, glassO("LobbyTransom", 0.62))
	for _, x in { 8.1, 9.95, DOOR_X0, DOOR_X1, 15.25, 17.1 } do
		bx(ext, x - 0.04, PAVE + 0.025, 0.96, x + 0.04, LOBBY_CEIL + 0.1, 1.1, STEEL_D, MAT.Metal, solid("LobbyMullion"))
	end
	bx(ext, CORE_A0 - 0.03, LOBBY_CEIL - 0.03, 0.94, CORE_A1 + 0.03, LOBBY_TOP - 0.02, 1.12, STEEL_D, MAT.Metal, solid("LobbyFascia"))
	-- 자동문: 문 상부 구동부 + 열린 상태의 두 짝(고정 유리 안쪽으로 겹쳐 밀림). 짝 = 스테인리스 프레임 4변 + 유리(프레임 속에 물림)
	bx(ext, DOOR_X0 - 1.05, 2.22, 1.1, DOOR_X1 + 1.05, 2.42, 1.26, rgb(150, 152, 156), MAT.Metal, solid("DoorOperator"))
	cyl(ext, (DOOR_X0 + DOOR_X1) / 2, 2.16, 1.18, 0.06, 0.08, rgb(30, 30, 30), MAT.SmoothPlastic, deco("DoorSensor"))
	for _, s in { -1, 1 } do
		local x0 = if s < 0 then DOOR_X0 - 0.98 else DOOR_X1 - 0.02
		local y0, y1 = LOBBY_FL + 0.01, 2.2
		bx(ext, x0 + 0.03, y0 + 0.05, 1.125, x0 + 0.97, y1 - 0.04, 1.155, GLASS_C, MAT.Glass, glassO("AutoDoor", 0.6))
		bx(ext, x0, y0, 1.11, x0 + 0.05, y1, 1.17, STEEL, MAT.Metal, deco("AutoDoorStile"))
		bx(ext, x0 + 0.95, y0, 1.11, x0 + 1.0, y1, 1.17, STEEL, MAT.Metal, deco("AutoDoorStile"))
		bx(ext, x0 + 0.05, y0, 1.11, x0 + 0.95, y0 + 0.09, 1.17, STEEL, MAT.Metal, deco("AutoDoorRail"))
		bx(ext, x0 + 0.05, y1 - 0.07, 1.11, x0 + 0.95, y1, 1.17, STEEL, MAT.Metal, deco("AutoDoorRail"))
	end
	bx(ext, DOOR_X0, PAVE + 0.01, 0.98, DOOR_X1, LOBBY_FL + 0.005, 1.05, STEEL, MAT.Metal, solid("Threshold"))
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
	-- 천장 설비: 하향식 스프링클러(격자 ≈3 m, 조명 피함) + 연기감지기 + 디퓨저/스피커 + CCTV 2
	for _, x in { 7.9, 10.9, 14.3, 17.3 } do
		for _, z in { 2.5, 5.0, 8.2, 10.9 } do
			pendantSprinkler(g, x, z, LOBBY_CEIL)
		end
	end
	detector(g, 10.2, 6.6, LOBBY_CEIL)
	detector(g, 15.0, 3.3, LOBBY_CEIL)
	for _, d in { { 9.6, 8.95 }, { 15.6, 5.25 } } do
		-- 600각 디퓨저(계단식 3단, 단마다 1.5 cm)
		bx(g, d[1] - 0.3, LOBBY_CEIL - 0.015, d[2] - 0.3, d[1] + 0.3, LOBBY_CEIL + 0.035, d[2] + 0.3, rgb(240, 240, 236), MAT.SmoothPlastic, deco("Diffuser"))
		bx(g, d[1] - 0.21, LOBBY_CEIL - 0.03, d[2] - 0.21, d[1] + 0.21, LOBBY_CEIL - 0.015, d[2] + 0.21, rgb(222, 222, 218), MAT.SmoothPlastic, deco("DiffuserRing"))
		bx(g, d[1] - 0.12, LOBBY_CEIL - 0.045, d[2] - 0.12, d[1] + 0.12, LOBBY_CEIL - 0.03, d[2] + 0.12, rgb(204, 204, 200), MAT.SmoothPlastic, deco("DiffuserCore"))
	end
	cyl(g, 9.6, LOBBY_CEIL - 0.015, 7.6, 0.05, 0.2, rgb(240, 240, 236), MAT.SmoothPlastic, deco("CeilingSpeaker"))
	cyl(g, 9.6, LOBBY_CEIL - 0.03, 7.6, 0.015, 0.15, rgb(180, 180, 177), MAT.DiamondPlate, deco("SpeakerGrille"))
	Props.cctv(g, CFrame.new(V(17.6, LOBBY_CEIL, 10.9)))
	Props.cctv(g, CFrame.new(V(7.0, LOBBY_CEIL, 1.7)))
	-- 옥내소화전(서쪽 월넛 벽, 엘리베이터 쪽) + 소화기
	Props.hydrant(g, wallCF("x", LX0 + 0.04, 1, 9.2, LOBBY_FL))
	Props.extinguisher(g, CFrame.lookAt(V(LX0 + 0.04 + 0.125, LOBBY_FL, 10.2), V(LX0 + 1, LOBBY_FL, 10.2)), true)

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
			bx(g, px0 - 0.02, 0.3, z0 + 0.04, px0, 0.85, z0 + cw - 0.04, rgb(200, 204, 208), MAT.Metal, deco("LockerDoor"))
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
	fb(g, BF, 0, 0.2, 0, 2.0, 0.3, 0.42, rgb(40, 38, 36), MAT.Metal, solid("LobbyBenchBase"))
	fb(g, BF, 0, SEAT - 0.05, 0, 2.2, 0.1, 0.52, rgb(150, 98, 64), MAT.Leather, solid("LobbyBenchSeat"))
	for i = 0, 3 do
		fb(g, BF, -0.825 + i * 0.55, SEAT + 0.012, 0.02, 0.53, 0.024, 0.46, rgb(140, 90, 58), MAT.Leather, deco("BenchCushion"))
	end
	cyl(g, 10.05, LOBBY_FL, 2.2, 0.45, 0.42, MARBLE_W, MAT.Marble, solid("SideTable"))
	cyl(g, 10.0, LOBBY_FL + 0.45, 2.15, 0.12, 0.12, rgb(30, 30, 32), MAT.SmoothPlastic, deco("Vase"))
	bigPlant(g, "fiddle", 10.55, LOBBY_FL, 1.6, 1.9, rng, rgb(60, 58, 56))
	bigPlant(g, "fiddle", 14.7, LOBBY_FL, 1.6, 1.9, rng, rgb(60, 58, 56))
	bigPlant(g, "areca", 7.1, LOBBY_FL, 11.4, 1.5, rng, rgb(60, 58, 56))
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
	for _, r in { { HX0, FD_X0 - 0.07 }, { FD_X1 + 0.07, LINE_W - FIN_T / 2 - 0.03 }, { LINE_W + FIN_T / 2 + 0.03, ND_X0 - 0.07 }, { ND_X0 + DOOR_W + 0.07, HX1 - 0.03 } } do
		bx(g, r[1], HF, fz + 0.03, r[2], HF + 0.1, fz + 0.045, rgb(60, 58, 56), MAT.Marble, deco("Skirting"))
	end
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
	bx(g, n0 - 0.55, HF, fz + 0.1, n0 - 0.1, HF + 0.3, fz + 0.42, rgb(176, 136, 92), MAT.Cardboard, solid("Parcel"))
	bx(g, n0 - 0.5, HF + 0.3, fz + 0.14, n0 - 0.22, HF + 0.45, fz + 0.36, rgb(190, 152, 104), MAT.Cardboard, deco("Parcel"))
	bx(g, n0 - 0.42, HF + 0.08, fz + 0.085, n0 - 0.2, HF + 0.2, fz + 0.105, rgb(240, 240, 236), MAT.SmoothPlastic, deco("ParcelLabel"))
	-- 2001호 문패 + 초인종(카메라)
	sign(g, FD_X1 + 0.15, HF + 1.55, fz + 0.03, FD_X1 + 0.4, HF + 1.67, fz + 0.045, NID.Back, "2001", { bg = rgb(40, 40, 42), color = rgb(230, 220, 200), pps = 100, maxd = 40 })
	bx(g, FD_X1 + 0.2, HF + 1.25, fz + 0.03, FD_X1 + 0.32, HF + 1.42, fz + 0.06, rgb(30, 30, 32), MAT.SmoothPlastic, deco("DoorBell"))
	-- 핀(세대 경계벽) 옆면도 석재로 감쌈
	for _, sx in { -1, 1 } do
		local x0 = if sx < 0 then LINE_W - FIN_T / 2 - 0.03 else LINE_W + FIN_T / 2
		bx(g, x0, HF, fz + 0.03, x0 + 0.03, HALL_CEIL, DEPTH + 0.25, STONE_L, MAT.Marble, deco("PilasterSide"))
	end
	-- 동쪽 벽 석재 + 옥내소화전함(바닥 위 0.3 m) + 표시등
	bx(g, HX1 - 0.03, HF, fz + 0.03, HX1, HALL_CEIL, HZ1 - 0.04, STONE_L, MAT.Marble, deco("HallPanel"))
	Props.hydrant(g, wallCF("x", HX1 - 0.03, -1, 10.75, HF))
	-- 천장: 센서 감지등 2(광원 2) + 하향식 스프링클러 4 + 연기감지기 + CCTV + 점검구
	local CY = HALL_CEIL
	for i, x in { 9.6, 15.6 } do
		local l = cyl(g, x, CY - 0.02, 11.05, 0.04, 0.32, PANEL_WARM, MAT.Neon, neon("SensorLight"))
		cyl(g, x + 0.3, CY - 0.025, 11.05, 0.04, 0.07, rgb(244, 244, 240), MAT.SmoothPlastic, deco("MotionSensor"))
		light(l, "PointLight", { color = rgb(255, 224, 186), brightness = if i == 1 then 1.0 else 0.8, range = M(6) })
	end
	for _, x in { 7.6, 11.0, 14.0, 17.4 } do
		pendantSprinkler(g, x, 11.05, CY)
	end
	detector(g, 12.6, 10.6, CY)
	Props.cctv(g, CFrame.new(V(18.5, CY, 11.9)))
	bx(g, 12.3, CY - 0.015, 11.35, 12.75, CY + 0.025, 11.8, rgb(236, 236, 232), MAT.SmoothPlastic, deco("AccessPanel"))
	bigPlant(g, "sansevieria", 6.7, HF, 11.8, 0.85, rng, rgb(70, 68, 64))
	-- 세대 현관 앞 매트(2002호)
	bx(g, ND_X0 + 0.05, HF, fz + 0.12, ND_X0 + DOOR_W - 0.05, HF + 0.015, fz + 0.62, rgb(70, 66, 62), MAT.Carpet, deco("DoorMat"))
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
	local ky0, ky1 = UF + KW_Y0, UF + KW_Y1
	bx(ext, 0, SLAB_TOP, z0, KW_X0, TOPY, z1, WALL_EXT, MAT.Concrete, solid("BackWall"))
	bx(ext, KW_X0, SLAB_TOP, z0, KW_X1, ky0, z1, WALL_EXT, MAT.Concrete, solid("BackWall"))
	bx(ext, KW_X0, ky1, z0, KW_X1, TOPY, z1, WALL_EXT, MAT.Concrete, solid("BackWall"))
	bx(ext, KW_X1, SLAB_TOP, z0, FD_X0, TOPY, z1, WALL_EXT, MAT.Concrete, solid("BackWall"))
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
	bx(ext, FD_X0, SLAB_TOP, z0, FD_X1, HF + 0.015, z1, MARBLE_D, MAT.Marble, solid("DoorThreshold"))
	-- 안방 전면 창(확장형: 바닥~천장 유리, 가운데 멀리언, 안전 바)
	local bx0, bx1 = W4X1, LINE_W - FIN_T / 2
	bx(ext, bx0, SLAB_TOP, 0.0, bx1, UF + 0.05, 0.2, rgb(70, 72, 76), MAT.Metal, solid("WinSill"))
	bx(ext, bx0, CEIL - 0.03, 0.0, bx1, TOPY, 0.2, rgb(70, 72, 76), MAT.Metal, solid("WinHead"))
	bx(ext, (bx0 + bx1) / 2 - 0.03, UF + 0.05, 0.02, (bx0 + bx1) / 2 + 0.03, CEIL, 0.18, rgb(70, 72, 76), MAT.Metal, solid("WinMullion"))
	bx(ext, bx0, UF + 0.05, 0.08, bx1, CEIL, 0.12, GLASS_C, MAT.Glass, glassO("BedroomGlass", 0.68))
	bx(ext, bx0, UF + 0.92, 0.0, bx1, UF + 0.96, 0.05, rgb(70, 72, 76), MAT.Metal, deco("SafetyBar"))
	-- 발코니 유리 난간(바닥 채널 + 강화유리 + 손스침)
	local dk = UF - 0.07
	bx(ext, 0, SLAB_TOP, 0.0, W4X0, dk + 0.1, 0.1, rgb(70, 72, 76), MAT.Metal, solid("RailShoe"))
	bx(ext, 0, dk + 0.1, 0.03, W4X0, dk + 1.12, 0.07, RAIL_GLASS, MAT.Glass, glassO("BalconyGlass", 0.7))
	bx(ext, 0, dk + 1.12, -0.01, W4X0, dk + 1.18, 0.11, OAK, MAT.Wood, solid("BalconyHandrail"))
end

local EXW = LINE_W - FIN_T / 2 -- 12.4 세대 경계벽(핀) 안쪽면
local FB = SLAB_TOP + 0.015 -- 바닥재 밑면: 슬래브 위 1.5 cm(벽 밑면과 같은 평면 금지)
local WOOD = rgb(180, 148, 114) -- 강마루(라이트 오크)
local TRIM = rgb(246, 244, 240) -- 문틀 · 걸레받이
local CHROME = rgb(204, 206, 210)
local BLACK_AL = rgb(34, 34, 36) -- 중문 · 커튼 레일 블랙 알루미늄
local DOOR_C = rgb(240, 238, 234)
local DOOR_HW = rgb(150, 136, 110)
local CAB = rgb(238, 236, 232) -- 무광 화이트 도어
local CAB_IN = rgb(92, 90, 88) -- 장 몸통(문짝 틈으로 보이는 어두운 선)
local QUARTZ = rgb(240, 238, 234)
local GAP = 0.006 -- 문짝 사이 틈

--------------------------------------------------------------------------------------------------
-- 5-1) 구조: 바닥재 · 천장(우물천장) · 벽 · 도배 · 문틀 · 걸레받이 · 문
--------------------------------------------------------------------------------------------------
local function unitStructure(g: Model)
	local w0, w1 = W4X0, W4X1
	-- 바닥재: 끝은 벽 속(8.075)이나 이웃 바닥재/레일과 맞닿음
	bx(g, 0, FB, 1.62, 8.075, UF, 8.3, WOOD, MAT.WoodPlanks, solid("FloorWood"))
	bx(g, 0, FB, 8.3, 6.32, UF, 9.6, WOOD, MAT.WoodPlanks, solid("FloorWood"))
	bx(g, 8.075, FB, 0.15, EXW, UF, 5.05, WOOD, MAT.WoodPlanks, solid("FloorWood"))
	bx(g, 8.075, FB, 7.27, EXW, UF, 9.6, WOOD, MAT.WoodPlanks, solid("FloorWood"))
	bx(g, 8.075, FB, 5.07, EXW, UF - 0.03, 7.25, TILE_D, MAT.CeramicTiles, solid("FloorBath"))
	bx(g, 6.4, FB, 8.42, 8.075, HF, 9.6, rgb(84, 82, 80), MAT.CeramicTiles, solid("FloorEntry"))
	bx(g, 6.4, FB, 8.3, 8.075, UF + 0.015, 8.42, MARBLE_W, MAT.Marble, solid("EntryStep"))
	bx(g, 0, FB, 0.05, w0, UF - 0.07, 1.5, rgb(122, 94, 72), MAT.WoodPlanks, solid("BalconyDeck"))
	bx(g, 0, FB, 1.5, w0, UF + 0.025, 1.62, rgb(150, 152, 156), MAT.Metal, solid("SlideTrack"))
	bx(g, w0, UF - 0.05, 5.5, w1, UF + 0.02, 6.4, MARBLE_W, MAT.Marble, solid("BathThreshold"))

	-- 천장(2 cm 판, 벽 윗면 TOPY 와 3 cm 차). 거실 우물천장 개구(RX0..RX1 × RZ0..RZ1)는 비움
	local CC = CEIL_C
	bx(g, 0, CEIL, 0.05, EXW, CEIL + 0.02, RZ0, CC, MAT.SmoothPlastic, solid("Ceiling"))
	bx(g, 0, CEIL, RZ1, EXW, CEIL + 0.02, 9.6, CC, MAT.SmoothPlastic, solid("Ceiling"))
	bx(g, 0, CEIL, RZ0, RX0, CEIL + 0.02, RZ1, CC, MAT.SmoothPlastic, solid("Ceiling"))
	bx(g, RX1, CEIL, RZ0, EXW, CEIL + 0.02, RZ1, CC, MAT.SmoothPlastic, solid("Ceiling"))
	-- 우물천장: 12 cm 올라간 천장판 + 둘레 단(1.5 cm 판) + 간접 LED 코브(단 안쪽 위, 천장판 4 cm 아래)
	local coffer = bx(g, RX0, CEIL + REC, RZ0, RX1, CEIL + REC + 0.02, RZ1, CC, MAT.SmoothPlastic, solid("CofferCeiling"))
	bx(g, RX0, CEIL, RZ0, RX0 + 0.015, CEIL + REC, RZ1, CC, MAT.SmoothPlastic, deco("CofferSide"))
	bx(g, RX1 - 0.015, CEIL, RZ0, RX1, CEIL + REC, RZ1, CC, MAT.SmoothPlastic, deco("CofferSide"))
	bx(g, RX0 + 0.015, CEIL, RZ0, RX1 - 0.015, CEIL + REC, RZ0 + 0.015, CC, MAT.SmoothPlastic, deco("CofferSide"))
	bx(g, RX0 + 0.015, CEIL, RZ1 - 0.015, RX1 - 0.015, CEIL + REC, RZ1, CC, MAT.SmoothPlastic, deco("CofferSide"))
	local cy0, cy1 = CEIL + REC - 0.045, CEIL + REC - 0.025
	bx(g, RX0 + 0.015, cy0, RZ0 + 0.015, RX0 + 0.035, cy1, RZ1 - 0.015, PANEL_WARM, MAT.Neon, neon("CoveLed"))
	bx(g, RX1 - 0.035, cy0, RZ0 + 0.015, RX1 - 0.015, cy1, RZ1 - 0.015, PANEL_WARM, MAT.Neon, neon("CoveLed"))
	bx(g, RX0 + 0.035, cy0, RZ0 + 0.015, RX1 - 0.035, cy1, RZ0 + 0.035, PANEL_WARM, MAT.Neon, neon("CoveLed"))
	bx(g, RX0 + 0.035, cy0, RZ1 - 0.035, RX1 - 0.035, cy1, RZ1 - 0.015, PANEL_WARM, MAT.Neon, neon("CoveLed"))
	light(coffer, "SurfaceLight", { face = NID.Bottom, color = rgb(255, 214, 170), brightness = 0.7, range = M(3.2), angle = 150 })

	-- 벽 (도배 화이트): W4 = 거실/복도 ↔ 안방·욕실·서재, 욕실 앞뒤 벽, 주방 | 현관 가벽
	local WC = PLASTER
	local dh = UF + DOOR_H
	bx(g, w0, SLAB_TOP, 0.0, w1, TOPY, 3.9, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, dh, 3.9, w1, TOPY, 4.8, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, SLAB_TOP, 4.8, w1, TOPY, 5.5, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, dh, 5.5, w1, TOPY, 6.4, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, SLAB_TOP, 6.4, w1, TOPY, 7.45, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, dh, 7.45, w1, TOPY, 8.35, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w0, SLAB_TOP, 8.35, w1, TOPY, 9.6, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w1, SLAB_TOP, 5.0, EXW, TOPY, 5.12, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, w1, SLAB_TOP, 7.2, EXW, TOPY, 7.32, WC, MAT.SmoothPlastic, solid("Wall"))
	bx(g, 6.25, SLAB_TOP, 7.0, 6.4, TOPY, 9.6, WC, MAT.SmoothPlastic, solid("Wall"))
	-- 콘크리트 외벽/경계벽 실내면 도배(2 cm): 가구는 이 면에서 시작
	local function skin(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
		bx(g, x0, y0, z0, x1, y1, z1, WC, MAT.SmoothPlastic, deco("WallSkin"))
	end
	skin(EXW - 0.02, UF, 0.2, EXW, CEIL, 5.0)
	skin(EXW - 0.02, UF, 7.32, EXW, CEIL, 9.6)
	skin(w1, UF, 9.58, EXW - 0.02, CEIL, 9.6)
	skin(0, UF, 1.62, 0.02, CEIL, 2.0)
	skin(0, UF, 4.6, 0.02, CEIL, 9.6)
	skin(0, UF, 2.0, 0.02, UF + 0.9, 4.6)
	skin(0, UF + 2.1, 2.0, 0.02, CEIL, 4.6)
	skin(0.02, UF, 9.58, KW_X0, CEIL, 9.6)
	skin(KW_X1, UF, 9.58, 6.25, CEIL, 9.6)
	skin(KW_X0, UF, 9.58, KW_X1, UF + KW_Y0, 9.6)
	skin(KW_X0, UF + KW_Y1, 9.58, KW_X1, CEIL, 9.6)
	skin(6.4, HF, 9.58, FD_X0, CEIL, 9.6)
	skin(FD_X1, HF, 9.58, w0, CEIL, 9.6)
	skin(FD_X0, HF + DOOR_H, 9.58, FD_X1, CEIL, 9.6)
	casingZ(g, 9.56, 9.6, FD_X0, FD_X1, HF, BRONZE)
	-- 문틀(안방 쪽은 아트월 슬랩 두께만큼 4 cm, 욕실 쪽은 타일 위로 4.5 cm)
	casingX(g, w0, w1, 3.9, 4.8, UF, TRIM, 0.04, 0.02)
	casingX(g, w0, w1, 5.5, 6.4, UF, TRIM, 0.02, 0.045)
	casingX(g, w0, w1, 7.45, 8.35, UF, TRIM, 0.02, 0.02)
	-- 걸레받이(높이 7 cm, 1.5 cm)
	local function skX(x: number, s: number, za: number, zb: number, y0: number?)
		local yy = y0 or UF
		bx(g, x, yy, za, x + s * 0.015, yy + 0.07, zb, TRIM, MAT.SmoothPlastic, deco("Skirting"))
	end
	local function skZ(z: number, s: number, xa: number, xb: number)
		bx(g, xa, UF, z, xb, UF + 0.07, z + s * 0.015, TRIM, MAT.SmoothPlastic, deco("Skirting"))
	end
	skX(0.02, 1, 1.64, 6.38)
	skX(w0, -1, 4.86, 5.44)
	skX(w0, -1, 6.46, 7.39)
	skX(w0, -1, 8.42, 9.58, HF)
	skX(6.4, 1, 7.02, 8.17)
	skX(6.25, -1, 7.02, 8.83)
	skX(w1, 1, 0.22, 3.84)
	skZ(5.0, -1, w1, 9.18)
	skX(EXW - 0.02, -1, 0.22, 1.06)
	skX(EXW - 0.02, -1, 4.14, 4.4)
	skX(w1, 1, 8.41, 9.02)
	skZ(7.32, 1, w1, 11.98)
	-- 문: 안방·욕실 열림, 서재 반쯤 열림 + 현관문(홀 쪽으로 열림, 디지털 도어록)
	doorLeaf(g, w1, 4.8 - 0.03, UF + 0.005, DOOR_W - 0.08, DOOR_H - 0.02, 0.04, -12, DOOR_C, MAT.SmoothPlastic, DOOR_HW)
	doorLeaf(g, w1, 5.5 + 0.03, UF + 0.025, DOOR_W - 0.08, DOOR_H - 0.04, 0.04, 14, DOOR_C, MAT.SmoothPlastic, DOOR_HW)
	doorLeaf(g, w1, 8.35 - 0.03, UF + 0.005, DOOR_W - 0.08, DOOR_H - 0.02, 0.04, -45, DOOR_C, MAT.SmoothPlastic, DOOR_HW)
	local FF = doorLeaf(g, FD_X0 + 0.06, DEPTH + 0.04, HF + 0.005, DOOR_W - 0.12, DOOR_H - 0.06, 0.06, 84, rgb(86, 80, 74), MAT.Metal, STEEL)
	local fw, fh = DOOR_W - 0.12, DOOR_H - 0.06
	fb(g, FF, fw / 2 - 0.13, 1.15 - fh / 2, 0.065, 0.075, 0.3, 0.035, rgb(18, 18, 20), MAT.SmoothPlastic, deco("DoorLock"))
	fb(g, FF, fw / 2 - 0.13, 1.22 - fh / 2, 0.09, 0.05, 0.08, 0.015, rgb(80, 150, 220), MAT.Neon, deco("DoorLockPad"))
	fb(g, FF, fw / 2 - 0.13, 1.1 - fh / 2, -0.0675, 0.1, 0.32, 0.065, rgb(18, 18, 20), MAT.SmoothPlastic, deco("DoorLockIn"))
	fb(g, FF, 0.25, fh / 2 - 0.08, -0.065, 0.32, 0.06, 0.06, rgb(60, 60, 62), MAT.Metal, deco("DoorCloser"))
	fb(g, FF, -0.2, 0.0, -0.045, 0.06, 0.06, 0.03, rgb(190, 192, 196), MAT.Metal, deco("DoorViewer"))
end

--------------------------------------------------------------------------------------------------
-- 5-2) 발코니: 미닫이 창(4짝) · 커튼 · 세탁기+건조기 · 천장형 빨래건조대 · 라운지 체어 · 식물
--------------------------------------------------------------------------------------------------
local function unitBalcony(g: Model, rng: Random)
	local dk = UF - 0.07
	local frameC = rgb(70, 72, 76)
	local gy0, gy1 = UF + 0.025, CEIL - 0.05
	bx(g, 0, gy1, 1.5, W4X0, CEIL, 1.62, frameC, MAT.Metal, solid("SlideHead"))
	-- 짝: {x0, x1, 레일 z 중심} — 고정 / 닫힌 미닫이 / 열린 미닫이(오른쪽 고정창 앞으로 겹침) / 고정
	local slides = { { 0.0, 2.05, 1.535 }, { 1.95, 4.05, 1.585 }, { 5.95, W4X0, 1.585 }, { 5.95, W4X0, 1.535 } }
	for i, s in slides do
		local x0, x1, zc = s[1], s[2], s[3]
		local z0, z1 = zc - 0.022, zc + 0.022
		bx(g, x0, gy0, z0, x0 + 0.05, gy1, z1, frameC, MAT.Metal, deco("SlideStile"))
		bx(g, x1 - 0.05, gy0, z0, x1, gy1, z1, frameC, MAT.Metal, deco("SlideStile"))
		bx(g, x0 + 0.05, gy0, z0, x1 - 0.05, gy0 + 0.07, z1, frameC, MAT.Metal, deco("SlideRail"))
		bx(g, x0 + 0.05, gy1 - 0.05, z0, x1 - 0.05, gy1, z1, frameC, MAT.Metal, deco("SlideRail"))
		bx(g, x0 + 0.05, gy0 + 0.05, zc - 0.0075, x1 - 0.05, gy1 - 0.03, zc + 0.0075, GLASS_C, MAT.Glass, glassO("SlideGlass", 0.74))
		if i == 2 or i == 3 then
			-- 미닫이 손잡이(실내 쪽 세로 손잡이)
			local hx = if i == 2 then x1 - 0.09 else x0 + 0.06
			bx(g, hx, UF + 0.9, z1, hx + 0.03, UF + 1.25, z1 + 0.025, rgb(50, 50, 54), MAT.Metal, deco("SashHandle"))
		end
	end
	-- 커튼 레일 박스 + 쉬어(얇은 망사) + 암막(주름 6) — 양쪽으로 모음
	bx(g, 0.02, CEIL - 0.04, 1.64, W4X0 - 0.02, CEIL, 1.86, rgb(236, 236, 234), MAT.SmoothPlastic, deco("CurtainBox"))
	local function drape(x0: number, x1: number, zf: number, n: number, col: Color3, tr: number, name: string)
		local w = (x1 - x0) / n
		for i = 0, n - 1 do
			local z = zf + (i % 2) * 0.035
			bx(g, x0 + i * w, UF + 0.01, z, x0 + (i + 1) * w, CEIL - 0.04, z + 0.035, col, MAT.Fabric, { name = name, collide = false, query = false, shadow = false, transparency = tr })
		end
	end
	drape(0.05, 0.95, 1.665, 5, rgb(244, 242, 236), 0.4, "Sheer")
	drape(0.05, 0.7, 1.75, 6, rgb(186, 176, 160), 0, "Drape")
	drape(7.05, 7.95, 1.665, 5, rgb(244, 242, 236), 0.4, "Sheer")
	drape(7.3, 7.95, 1.75, 6, rgb(186, 176, 160), 0, "Drape")

	-- 세탁기(아래) + 건조기(위) 직렬 설치, 문은 +X(발코니 길이 방향)를 봄
	local WM = rgb(236, 236, 234)
	local lx0, lx1, lz0, lz1 = 0.05, 0.77, 0.45, 1.15
	for k = 0, 1 do
		local y0 = dk + k * 1.0
		local hgt = if k == 0 then 0.98 else 0.92
		bx(g, lx0, y0, lz0, lx1, y0 + hgt, lz1, WM, MAT.SmoothPlastic, solid(if k == 0 then "Washer" else "Dryer"))
		local cyY = y0 + hgt * 0.47
		local zc = (lz0 + lz1) / 2
		Kit.hcyl(g, CFrame.new(V(lx1 + 0.015, cyY, zc)), M(0.03), M(0.5), rgb(186, 188, 192), MAT.Metal, deco("DoorRing"))
		Kit.hcyl(g, CFrame.new(V(lx1 + 0.03, cyY, zc)), M(0.03), M(0.38), rgb(40, 46, 54), MAT.Glass, { name = "DoorGlass", collide = false, query = false, shadow = false, reflectance = 0.2 })
		bx(g, lx1, y0 + hgt - 0.12, lz0 + 0.06, lx1 + 0.015, y0 + hgt - 0.03, lz1 - 0.06, rgb(46, 48, 52), MAT.SmoothPlastic, deco("ControlPanel"))
		bx(g, lx1 + 0.015, y0 + hgt - 0.1, lz0 + 0.3, lx1 + 0.03, y0 + hgt - 0.05, lz0 + 0.42, rgb(90, 200, 255), MAT.Neon, deco("Display"))
		bx(g, lx1, y0 + 0.02, lz0 + 0.12, lx1 + 0.015, y0 + 0.08, lz1 - 0.12, rgb(200, 200, 198), MAT.SmoothPlastic, deco("FilterCover"))
	end
	bx(g, lx0 + 0.02, dk + 0.98, lz0 + 0.02, lx1 - 0.02, dk + 1.0, lz1 - 0.02, rgb(60, 60, 62), MAT.Metal, deco("StackKit"))
	-- 세탁 수전 + 배수 호스, 콘센트, 세제 선반
	cyl(g, 0.06, UF + 0.55, 1.3, 0.06, 0.04, CHROME, MAT.Metal, deco("UtilityTap"))
	bx(g, 0.0, UF + 0.57, 1.28, 0.08, UF + 0.6, 1.32, CHROME, MAT.Metal, deco("UtilityTapArm"))
	outlet(g, "x", 0, 1, 1.32, UF + 1.15)
	bx(g, 0.0, UF + 1.45, 1.2, 0.25, UF + 1.47, 1.45, rgb(220, 220, 218), MAT.SmoothPlastic, deco("DetergentShelf"))
	Props.fillShelf(g, frameAt(0.25, UF + 1.47, 1.325, 90), 0.22, 0.22, 0.3, "drink", rng, { maxItems = 3, front = true })
	-- 빨래 바구니
	cyl(g, 1.15, dk, 1.2, 0.42, 0.4, rgb(190, 164, 120), MAT.Fabric, solid("LaundryBasket"))
	for i = 0, 2 do
		Kit.ellipsoid(g, LCF(1.12 + (i - 1) * 0.08, dk + 0.43 + (i % 2) * 0.03, 1.2 + (i - 1) * 0.05), SZ(0.24, 0.1, 0.2), ({ rgb(240, 240, 236), rgb(120, 150, 190), rgb(214, 200, 180) })[i + 1], MAT.Fabric, deco("Laundry"))
	end
	-- 천장형 빨래건조대(봉 2 + 도르래 브래킷) + 수건 3장
	for _, bxp in { 1.05, 2.35 } do
		for _, bz in { 0.55, 0.95 } do
			bx(g, bxp - 0.03, CEIL - 0.06, bz - 0.03, bxp + 0.03, CEIL, bz + 0.03, rgb(220, 220, 222), MAT.Metal, deco("PulleyBracket"))
			cyl(g, bxp, UF + 1.98, bz, CEIL - 0.06 - UF - 1.98, 0.006, rgb(230, 230, 230), MAT.SmoothPlastic, deco("PulleyCord"))
		end
	end
	for _, bz in { 0.55, 0.95 } do
		Kit.hcyl(g, CFrame.new(V(1.7, UF + 1.97, bz)), M(1.7), M(0.03), rgb(214, 216, 220), MAT.Metal, deco("DryingBar"))
	end
	for i, t in { { 1.25, 0.55, rgb(236, 232, 222) }, { 1.75, 0.55, rgb(150, 176, 196) }, { 2.1, 0.95, rgb(236, 232, 222) } } do
		local tx = t[1] + (i - 2) * 0.02
		bx(g, tx - 0.22, UF + 1.45, t[2] + 0.017, tx + 0.22, UF + 1.97, t[2] + 0.037, t[3], MAT.Fabric, deco("Towel"))
		bx(g, tx - 0.22, UF + 1.45, t[2] - 0.037, tx + 0.22, UF + 1.97, t[2] - 0.017, t[3], MAT.Fabric, deco("Towel"))
	end
	-- 라운지 체어(강을 봄) + 사이드 테이블 + 랜턴 + 식물
	local CF = frameAt(4.75, dk, 0.78, 0)
	for _, lx in { -0.28, 0.28 } do
		for _, lz in { -0.28, 0.3 } do
			fb(g, CF, lx, 0.16, lz, 0.04, 0.32, 0.04, rgb(110, 80, 58), MAT.Wood, deco("ChairLeg"))
		end
		fb(g, CF, lx + (if lx < 0 then -0.025 else 0.025), 0.56, 0.0, 0.05, 0.04, 0.66, rgb(110, 80, 58), MAT.Wood, deco("ChairArm"))
	end
	fb(g, CF, 0, 0.34, 0.0, 0.62, 0.05, 0.64, rgb(110, 80, 58), MAT.Wood, solid("ChairSeat"))
	fb(g, CF, 0, SEAT - 0.02, -0.02, 0.56, 0.07, 0.56, rgb(236, 230, 216), MAT.Fabric, deco("ChairCushion"))
	Kit.box(g, CF * mcf(0, 0.72, 0.36) * CFrame.Angles(math.rad(22), 0, 0), SZ(0.6, 0.7, 0.05), rgb(110, 80, 58), MAT.Wood, solid("ChairBack"))
	Kit.box(g, CF * mcf(0, 0.74, 0.3) * CFrame.Angles(math.rad(22), 0, 0), SZ(0.52, 0.55, 0.07), rgb(236, 230, 216), MAT.Fabric, deco("ChairBackCushion"))
	Kit.box(g, CF * mcf(0.1, SEAT + 0.035, 0.05) * CFrame.Angles(0, math.rad(12), 0), SZ(0.45, 0.03, 0.35), rgb(150, 92, 70), MAT.Fabric, deco("Throw"))
	cyl(g, 5.45, dk, 0.7, 0.5, 0.06, rgb(40, 40, 42), MAT.Metal, deco("SideTableStem"))
	cyl(g, 5.45, dk, 0.7, 0.02, 0.32, rgb(40, 40, 42), MAT.Metal, deco("SideTableBase"))
	cyl(g, 5.45, dk + 0.5, 0.7, 0.025, 0.45, MARBLE_W, MAT.Marble, solid("SideTableTop"))
	cyl(g, 5.38, dk + 0.525, 0.66, 0.015, 0.13, rgb(250, 250, 248), MAT.SmoothPlastic, deco("Saucer"))
	cyl(g, 5.38, dk + 0.54, 0.66, 0.08, 0.075, rgb(250, 250, 248), MAT.SmoothPlastic, deco("Cup"))
	bx(g, 5.5, dk + 0.525, 0.74, 5.64, dk + 0.555, 0.94, rgb(36, 70, 110), MAT.SmoothPlastic, deco("Book"))
	bx(g, 3.85, dk, 0.25, 4.05, dk + 0.32, 0.45, rgb(30, 30, 32), MAT.Metal, deco("Lantern"))
	local candle = cyl(g, 3.95, dk + 0.04, 0.35, 0.12, 0.07, LAMP, MAT.Neon, neon("LanternCandle"))
	light(candle, "PointLight", { color = rgb(255, 180, 110), brightness = 0.8, range = M(3) })
	bigPlant(g, "areca", 7.5, dk, 0.55, 1.45, rng, rgb(176, 104, 72))
	smallPlant(g, 7.05, dk, 0.32, 0.26, 0.24, 0.35, rng, rgb(232, 228, 220))
	local tTop = Props.planter(g, LCF(3.2, dk, 0.42), "round", 0.42, 0.4, rgb(196, 186, 170), MAT.Concrete)
	Props.tree(g, LCF(3.2, dk, 0.42) * CFrame.new(0, tTop, 0), 1.25, rng, { crown = 0.36 })
end

--------------------------------------------------------------------------------------------------
-- 5-3) 거실 + 식당: 포세린 아트월 · 벽걸이 65" TV · 콘솔 · 소파 · 러그 · 커피 테이블 · 식탁 · 블라인드 · 식물
--------------------------------------------------------------------------------------------------
local function unitLiving(g: Model, rng: Random)
	local w0 = W4X0
	-- 아트월: 줄눈 색 바탕판(1.5 cm) + 포세린 슬랩 3장(2 cm, 6 mm 줄눈)
	local az0, az1 = 1.62, 3.84
	wb(g, "x", w0, -1, 0, 0.015, az0, az1, UF, CEIL, rgb(84, 80, 76), MAT.SmoothPlastic, solid("ArtWallBack"))
	local sw = (az1 - az0 - 2 * 0.006) / 3
	for i = 0, 2 do
		local z0 = az0 + i * (sw + 0.006)
		wb(g, "x", w0, -1, 0.015, 0.035, z0, z0 + sw, UF, CEIL, rgb(230, 226, 220), MAT.Marble, solid("PorcelainSlab"))
	end
	local sx = w0 - 0.035 -- 슬랩 앞면
	local tvz = (az0 + az1) / 2
	outlet(g, "x", sx, -1, az0 + 0.2, UF + 0.3)
	-- 65" 벽걸이 TV(1.45 × 0.83, 두께 2.5 cm) + 숨은 브래킷
	local ty0 = UF + 0.8
	bx(g, sx - 0.035, ty0 + 0.2, tvz - 0.25, sx, ty0 + 0.63, tvz + 0.25, rgb(30, 30, 32), MAT.Metal, deco("TVBracket"))
	bx(g, sx - 0.06, ty0, tvz - 0.725, sx - 0.035, ty0 + 0.83, tvz + 0.725, rgb(14, 14, 16), MAT.SmoothPlastic, { name = "TV65", reflectance = 0.12, shadow = false })
	-- 낮은 TV 콘솔(월넛, 1.7 m): 몸통 + 들어간 받침 + 앞판 4짝
	local cx0 = sx - 0.42
	local cz0, cz1 = tvz - 0.85, tvz + 0.85
	bx(g, cx0, UF + 0.07, cz0, sx, UF + 0.43, cz1, WALNUT, MAT.Wood, solid("TVConsole"))
	bx(g, cx0 + 0.08, UF, cz0 + 0.08, sx - 0.02, UF + 0.07, cz1 - 0.08, rgb(26, 26, 28), MAT.SmoothPlastic, deco("ConsolePlinth"))
	local dwid = (cz1 - cz0 - 3 * GAP) / 4
	for i = 0, 3 do
		local z0 = cz0 + i * (dwid + GAP)
		bx(g, cx0 - 0.018, UF + 0.085, z0, cx0, UF + 0.415, z0 + dwid, rgb(116, 88, 64), MAT.Wood, deco("ConsoleFront"))
	end
	local ctop = UF + 0.43
	bx(g, cx0 + 0.08, ctop, tvz - 0.5, cx0 + 0.2, ctop + 0.065, tvz + 0.5, rgb(44, 44, 48), MAT.Fabric, deco("Soundbar"))
	bx(g, cx0 + 0.24, ctop, tvz - 0.22, cx0 + 0.4, ctop + 0.04, tvz - 0.06, rgb(24, 24, 26), MAT.SmoothPlastic, deco("SetTopBox"))
	bx(g, cx0 + 0.07, ctop, cz0 + 0.05, cx0 + 0.31, ctop + 0.035, cz0 + 0.31, rgb(212, 202, 184), MAT.SmoothPlastic, deco("ArtBook"))
	bx(g, cx0 + 0.09, ctop + 0.035, cz0 + 0.07, cx0 + 0.29, ctop + 0.06, cz0 + 0.29, rgb(58, 66, 80), MAT.SmoothPlastic, deco("ArtBook"))
	Kit.ball(g, V(cx0 + 0.19, ctop + 0.06 + 0.055, cz0 + 0.18), M(0.11), rgb(196, 168, 116), MAT.Metal, deco("Sculpture"))
	cyl(g, cx0 + 0.3, ctop, tvz + 0.76, 0.2, 0.12, rgb(226, 220, 208), MAT.SmoothPlastic, deco("Vase"))
	cyl(g, cx0 + 0.3, ctop + 0.2, tvz + 0.76, 0.04, 0.05, rgb(226, 220, 208), MAT.SmoothPlastic, deco("VaseNeck"))
	smallPlant(g, cx0 + 0.13, ctop, tvz + 0.66, 0.1, 0.1, 0.16, rng, rgb(60, 58, 56))
	Kit.box(g, LCF(cx0 + 0.32, ctop + 0.085, tvz + 0.56) * CFrame.Angles(0, 0, math.rad(-10)), SZ(0.02, 0.17, 0.13), rgb(34, 32, 30), MAT.Wood, deco("PhotoFrame"))

	-- 소파(3인, 좌면 0.43 m, +X 를 봄)
	local SF = frameAt(3.68, UF, 2.85, -90)
	local SC = rgb(184, 178, 168)
	for _, lx in { -1.0, 1.0 } do
		for _, lz in { -0.4, 0.4 } do
			fb(g, SF, lx, 0.05, lz, 0.04, 0.1, 0.04, rgb(40, 32, 26), MAT.Wood, deco("SofaLeg"))
		end
	end
	fb(g, SF, 0, 0.215, 0, 2.2, 0.23, 0.95, SOFA_C, MAT.Fabric, solid("SofaBase"))
	for _, ax in { -1.015, 1.015 } do
		fb(g, SF, ax, 0.385, 0, 0.17, 0.57, 0.95, SOFA_C, MAT.Fabric, solid("SofaArm"))
	end
	fb(g, SF, 0, 0.565, 0.3875, 1.86, 0.47, 0.175, SOFA_C, MAT.Fabric, solid("SofaBack"))
	for _, cx in { -0.62, 0, 0.62 } do
		fb(g, SF, cx, SEAT - 0.05, -0.13, 0.6, 0.1, 0.64, SC, MAT.Fabric, deco("SeatCushion"))
		Kit.box(g, SF * mcf(cx, 0.62, 0.215) * CFrame.Angles(math.rad(8), 0, 0), SZ(0.6, 0.44, 0.16), SC, MAT.Fabric, deco("BackCushion"))
	end
	Kit.box(g, SF * mcf(-0.8, 0.64, 0.06) * CFrame.Angles(math.rad(18), math.rad(12), math.rad(8)), SZ(0.45, 0.45, 0.13), rgb(198, 150, 64), MAT.Fabric, deco("Pillow"))
	Kit.box(g, SF * mcf(-0.42, 0.62, 0.09) * CFrame.Angles(math.rad(16), math.rad(-6), math.rad(-5)), SZ(0.42, 0.42, 0.12), rgb(232, 226, 210), MAT.Fabric, deco("Pillow"))
	Kit.box(g, SF * mcf(0.78, 0.64, 0.06) * CFrame.Angles(math.rad(18), math.rad(-10), math.rad(-9)), SZ(0.45, 0.45, 0.13), rgb(170, 96, 70), MAT.Fabric, deco("Pillow"))
	-- 스로우 블랭킷(팔걸이 위로 걸쳐 앞으로 늘어짐)
	fb(g, SF, 1.015, 0.69, 0.05, 0.24, 0.02, 0.55, rgb(132, 140, 150), MAT.Fabric, deco("Throw"))
	fb(g, SF, 1.12, 0.47, 0.05, 0.02, 0.44, 0.55, rgb(132, 140, 150), MAT.Fabric, deco("ThrowHang"))
	Kit.box(g, SF * mcf(0.55, SEAT + 0.03, -0.2) * CFrame.Angles(0, math.rad(20), 0), SZ(0.5, 0.04, 0.32), rgb(132, 140, 150), MAT.Fabric, deco("ThrowFold"))

	-- 러그(테두리 4 + 가운데, 두께 1.5 cm) — 소파 앞에서 시작(다리와 겹치지 않음)
	local rx0, rx1, rz0, rz1 = 4.2, 7.15, 1.95, 3.8
	local RB, RF = rgb(140, 126, 108), rgb(214, 206, 190)
	bx(g, rx0 + 0.09, UF, rz0 + 0.09, rx1 - 0.09, UF + 0.015, rz1 - 0.09, RF, MAT.Carpet, deco("Rug"))
	bx(g, rx0, UF, rz0, rx1, UF + 0.015, rz0 + 0.09, RB, MAT.Carpet, deco("RugBorder"))
	bx(g, rx0, UF, rz1 - 0.09, rx1, UF + 0.015, rz1, RB, MAT.Carpet, deco("RugBorder"))
	bx(g, rx0, UF, rz0 + 0.09, rx0 + 0.09, UF + 0.015, rz1 - 0.09, RB, MAT.Carpet, deco("RugBorder"))
	bx(g, rx1 - 0.09, UF, rz0 + 0.09, rx1, UF + 0.015, rz1 - 0.09, RB, MAT.Carpet, deco("RugBorder"))
	-- 커피 테이블(오크, 다리는 러그 위) + 선반 + 소품
	local ry = UF + 0.015
	local tx0, tx1, tz0, tz1 = 4.75, 5.45, 2.25, 3.45
	bx(g, tx0, UF + 0.36, tz0, tx1, UF + 0.4, tz1, OAK_L, MAT.Wood, solid("CoffeeTable"))
	for _, z in { tz0 + 0.06, tz1 - 0.06 } do
		bx(g, tx0 + 0.05, ry, z - 0.025, tx1 - 0.05, UF + 0.36, z + 0.025, OAK_L, MAT.Wood, solid("CoffeeLeg"))
	end
	bx(g, tx0 + 0.05, UF + 0.1, tz0 + 0.085, tx1 - 0.05, UF + 0.12, tz1 - 0.085, OAK_L, MAT.Wood, deco("CoffeeShelf"))
	bx(g, tx0 + 0.12, UF + 0.12, tz0 + 0.2, tx0 + 0.42, UF + 0.14, tz0 + 0.42, rgb(220, 60, 50), MAT.SmoothPlastic, deco("Magazine"))
	local by = UF + 0.4
	for i, b in { { 0.3, 0.22, rgb(42, 70, 110) }, { 0.27, 0.2, rgb(232, 228, 216) }, { 0.24, 0.17, rgb(150, 52, 44) } } do
		Kit.box(g, LCF(4.95, by + 0.015, 2.5) * CFrame.Angles(0, math.rad(i * 7), 0), SZ(b[2], 0.03, b[1]), b[3], MAT.SmoothPlastic, deco("Book"))
		by += 0.03
	end
	-- 과일 그릇(사과 · 귤) + 머그 + 리모컨 + 트레이 위 캔들
	cyl(g, 5.15, UF + 0.4, 3.12, 0.07, 0.26, rgb(236, 232, 224), MAT.SmoothPlastic, deco("FruitBowl"))
	for i = 0, 4 do
		local a = i * 1.26
		Kit.ball(g, V(5.15 + math.cos(a) * 0.065, UF + 0.47 + (i % 2) * 0.02, 3.12 + math.sin(a) * 0.065), M(0.075), if i % 2 == 0 then rgb(236, 140, 40) else rgb(186, 36, 36), MAT.SmoothPlastic, deco("Fruit"))
	end
	cyl(g, 5.3, UF + 0.4, 2.62, 0.09, 0.08, rgb(240, 238, 232), MAT.SmoothPlastic, deco("Mug"))
	bx(g, 5.335, UF + 0.42, 2.615, 5.36, UF + 0.47, 2.63, rgb(240, 238, 232), MAT.SmoothPlastic, deco("MugHandle"))
	Kit.box(g, LCF(5.0, UF + 0.41, 2.88) * CFrame.Angles(0, math.rad(-18), 0), SZ(0.045, 0.02, 0.17), rgb(30, 30, 32), MAT.SmoothPlastic, deco("Remote"))
	bx(g, 5.0, UF + 0.4, 3.25, 5.3, UF + 0.415, 3.4, rgb(70, 66, 62), MAT.Wood, deco("Tray"))
	cyl(g, 5.08, UF + 0.415, 3.32, 0.09, 0.07, rgb(240, 234, 222), MAT.SmoothPlastic, deco("Candle"))

	-- 플로어 스탠드(소파 끝)
	cyl(g, 3.4, UF, 4.3, 0.025, 0.3, rgb(40, 40, 42), MAT.Metal, deco("LampBase"))
	cyl(g, 3.4, UF + 0.025, 4.3, 1.36, 0.03, rgb(40, 40, 42), MAT.Metal, deco("LampPole"))
	cyl(g, 3.4, UF + 1.36, 4.3, 0.32, 0.42, rgb(240, 230, 210), MAT.Fabric, { name = "LampShade", collide = false, query = false, shadow = false, transparency = 0.1 })
	local bulb = Kit.ball(g, V(3.4, UF + 1.45, 4.3), M(0.1), LAMP, MAT.Neon, neon("LampBulb"))
	light(bulb, "PointLight", { color = rgb(255, 196, 130), brightness = 1.2, range = M(3.6) })
	-- 관엽식물: 몬스테라(창가, 식당 쪽) · 떡갈고무나무(창가, TV 쪽)
	bigPlant(g, "monstera", 2.75, UF, 2.1, 1.25, rng, rgb(240, 238, 232))
	bigPlant(g, "fiddle", 6.95, UF, 2.12, 1.75, rng, rgb(214, 208, 198))
	-- 스위치 · 보일러 온도조절기 · 콘센트(안방문 ↔ 욕실문 사이 벽)
	switchPlate(g, "x", w0, -1, 5.0, UF + 1.15)
	wb(g, "x", w0, -1, 0, 0.018, 5.22, 5.36, UF + 1.36, UF + 1.5, rgb(246, 246, 244), MAT.SmoothPlastic, deco("Thermostat"))
	local th = wb(g, "x", w0, -1, 0.018, 0.033, 5.24, 5.34, UF + 1.41, UF + 1.48, rgb(40, 130, 200), MAT.Neon, deco("ThermostatLcd"))
	Kit.label(th, NID.Left, "23.5℃", { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 160, maxDistance = 20 })
	outlet(g, "x", w0, -1, 5.3, UF + 0.3)

	-- 식당: 4인 식탁(1600 × 900, 0.75 m) + 의자 4 + 식기
	local tx, tz = 1.5, 3.4
	bx(g, tx - 0.45, UF + TABLE_H - 0.04, tz - 0.8, tx + 0.45, UF + TABLE_H, tz + 0.8, OAK_L, MAT.Wood, solid("DiningTable"))
	for _, lx in { -0.38, 0.38 } do
		for _, lz in { -0.72, 0.72 } do
			bx(g, tx + lx - 0.025, UF, tz + lz - 0.025, tx + lx + 0.025, UF + TABLE_H - 0.04, tz + lz + 0.025, OAK_L, MAT.Wood, solid("TableLeg"))
		end
	end
	local tt = UF + TABLE_H
	for _, c in { { 0.72, 3.0, -90 }, { 0.72, 3.8, -90 }, { 2.28, 3.0, 90 }, { 2.28, 3.8, 90 } } do
		local F = frameAt(c[1], UF, c[2], c[3])
		for _, lx in { -0.19, 0.19 } do
			for _, lz in { -0.17, 0.17 } do
				fb(g, F, lx, (SEAT - 0.05) / 2, lz, 0.03, SEAT - 0.05, 0.03, WALNUT, MAT.Wood, deco("ChairLeg"))
			end
		end
		fb(g, F, 0, SEAT - 0.035, 0, 0.44, 0.03, 0.42, WALNUT, MAT.Wood, solid("ChairSeat"))
		fb(g, F, 0, SEAT + 0.0, -0.01, 0.4, 0.04, 0.38, rgb(214, 204, 186), MAT.Fabric, deco("ChairPad"))
		fb(g, F, 0, SEAT + 0.24, 0.19, 0.42, 0.34, 0.03, WALNUT, MAT.Wood, deco("ChairBack"))
		-- 매트(1.5 cm) + 접시(매트 위 1.7 cm) + 물컵
		local pl = frameAt(c[1] + (if c[3] < 0 then 0.55 else -0.55), tt, c[2], 0)
		fb(g, pl, 0, 0.0025, 0, 0.32, 0.025, 0.42, rgb(196, 186, 168), MAT.Fabric, deco("Placemat"))
		Kit.vcyl(g, (pl * mcf(0, 0.026, 0)).Position, M(0.022), M(0.24), rgb(250, 250, 248), MAT.SmoothPlastic, deco("Plate"))
		Kit.vcyl(g, (pl * mcf(0.1, 0.065, -0.15)).Position, M(0.1), M(0.07), GLASS_C, MAT.Glass, { name = "Glass", collide = false, query = false, shadow = false, transparency = 0.45 })
	end
	cyl(g, tx, tt, tz, 0.16, 0.12, rgb(214, 206, 190), MAT.SmoothPlastic, deco("Vase"))
	for i = 0, 2 do
		Kit.ball(g, V(tx + (i - 1) * 0.05, tt + 0.22 + (i % 2) * 0.04, tz + (i - 1) * 0.03), M(0.07), if i == 1 then rgb(236, 220, 200) else rgb(214, 110, 120), MAT.SmoothPlastic, deco("Flower"))
	end
	for i, z in { 3.0, 3.8 } do
		cyl(g, tx, CEIL - 0.025, z, 0.06, 0.1, rgb(30, 30, 32), MAT.Metal, deco("PendantCanopy"))
		cyl(g, tx, UF + 1.65, z, CEIL - UF - 1.67, 0.015, rgb(30, 30, 32), MAT.SmoothPlastic, deco("PendantCord"))
		cyl(g, tx, UF + 1.45, z, 0.2, 0.3, rgb(36, 38, 40), MAT.Metal, deco("PendantShade"))
		local pb = cyl(g, tx, UF + 1.43, z, 0.02, 0.24, LAMP, MAT.Neon, neon("PendantBulb"))
		if i == 1 then
			light(pb, "PointLight", { color = rgb(255, 200, 140), brightness = 1.0, range = M(3.2) })
		end
	end
	-- 서쪽 창: 대리석 창대(벽 절단면보다 1.5 cm 위) + 롤 블라인드(벽 위 카세트, 절반 내림)
	bx(g, -0.15, UF + 0.88, 1.95, 0.06, UF + 0.915, 4.65, MARBLE_W, MAT.Marble, deco("WinSill"))
	bx(g, 0.02, UF + 2.1, 1.95, 0.1, UF + 2.18, 4.65, rgb(240, 240, 238), MAT.SmoothPlastic, deco("BlindCassette"))
	bx(g, 0.045, UF + 1.5, 2.0, 0.06, UF + 2.1, 4.6, LINEN, MAT.Fabric, deco("RollerBlind"))
	bx(g, 0.025, UF + 1.48, 2.0, 0.08, UF + 1.51, 4.6, rgb(200, 200, 198), MAT.Metal, deco("BlindBar"))
	picture(g, "x", 0.02, 1, 4.85, 5.65, UF + 1.3, UF + 1.95, rgb(64, 110, 150), rgb(214, 170, 90))
	outlet(g, "x", 0.02, 1, 4.95, UF + 0.3)
	outlet(g, "x", 0.02, 1, 2.3, UF + 0.3)
	bigPlant(g, "sansevieria", 0.32, UF, 5.95, 0.75, rng, rgb(46, 46, 48))
	-- 벽시계(주방 쪽 가벽, 18:05): 테두리 → 문자판(1.5 cm 앞) → 바늘(1.5 cm 앞)
	local ck = V(6.25 - 0.015, UF + 1.95, 7.65)
	Kit.hcyl(g, CFrame.new(ck), M(0.03), M(0.36), rgb(30, 30, 32), MAT.Metal, deco("ClockRim"))
	Kit.hcyl(g, CFrame.new(ck - Vector3.new(M(0.015), 0, 0)), M(0.03), M(0.32), rgb(248, 246, 240), MAT.SmoothPlastic, deco("ClockFace"))
	for _, hnd in { { 182, 0.08, 0.016 }, { 30, 0.13, 0.012 } } do
		local phi = math.rad(hnd[1])
		local L = hnd[2]
		Kit.box(g, CFrame.new(ck - Vector3.new(M(0.04), 0, 0)) * CFrame.Angles(phi, 0, 0) * mcf(0, L / 2, 0), SZ(0.015, L, hnd[3]), rgb(20, 20, 22), MAT.SmoothPlastic, deco("ClockHand"))
	end
end

--------------------------------------------------------------------------------------------------
-- 5-4) 주방: ㄱ자 하부장(문짝 + 게일라 홈) · 쿼츠 상판 · 언더싱크 · 정수기 수전 · 인덕션 · 슬림 후드 장 ·
--      천장까지 상부장 · 냉장고장(4도어 냉장고 + 스탠드 김치냉장고) · 아일랜드 · 식기건조대 · 조리 소품
--------------------------------------------------------------------------------------------------
local function unitKitchen(g: Model, rng: Random)
	local ct = UF + COUNTER
	local cb = ct - 0.04 -- 상판 밑면
	local BODY = CAB_IN
	-- 하부장 몸통(서쪽 런 + 뒤쪽 런, 개수대 칸은 볼 자리만큼 낮음) + 5 cm 들어간 걸레받이
	bx(g, 0.02, UF + 0.1, 6.4, 0.62, cb, 9.0, BODY, MAT.SmoothPlastic, solid("BaseCabinet"))
	bx(g, 0.02, UF + 0.1, 9.0, 1.12, cb, 9.58, BODY, MAT.SmoothPlastic, solid("BaseCabinet"))
	bx(g, 1.12, UF + 0.1, 9.0, 1.97, ct - 0.26, 9.58, BODY, MAT.SmoothPlastic, solid("BaseCabinet"))
	bx(g, 1.97, UF + 0.1, 9.0, 4.55, cb, 9.58, BODY, MAT.SmoothPlastic, solid("BaseCabinet"))
	bx(g, 4.55, UF, 8.96, 4.57, cb, 9.58, CAB, MAT.SmoothPlastic, solid("EndPanel"))
	bx(g, 0.02, UF, 6.45, 0.57, UF + 0.1, 9.05, rgb(40, 40, 42), MAT.SmoothPlastic, deco("Plinth"))
	bx(g, 0.02, UF, 9.05, 4.55, UF + 0.1, 9.58, rgb(40, 40, 42), MAT.SmoothPlastic, deco("Plinth"))
	-- 문짝(2 cm, 6 mm 틈) — 위 3.5 cm 는 손잡이 홈(어두운 몸통이 보임)
	local dy0, dy1 = UF + 0.105, ct - 0.075
	local function doorZ(x0: number, x1: number, y0: number, y1: number)
		bx(g, x0 + GAP / 2, y0, 8.98, x1 - GAP / 2, y1, 9.0, CAB, MAT.SmoothPlastic, deco("CabDoor"))
	end
	local function doorX(z0: number, z1: number, y0: number, y1: number)
		bx(g, 0.62, y0, z0 + GAP / 2, 0.64, y1, z1 - GAP / 2, CAB, MAT.SmoothPlastic, deco("CabDoor"))
	end
	local function drawers(n: number, f: (number, number) -> ())
		local h = (dy1 - dy0) / n
		for k = 0, n - 1 do
			f(dy0 + k * h + GAP / 2, dy0 + (k + 1) * h - GAP / 2)
		end
	end
	doorZ(0.62, 1.12, dy0, dy1)
	doorZ(1.12, 1.545, dy0, dy1)
	doorZ(1.545, 1.97, dy0, dy1)
	drawers(3, function(a, b)
		doorZ(1.97, 2.57, a, b)
	end)
	doorZ(2.57, 3.07, dy0, dy1)
	drawers(2, function(a, b)
		doorZ(3.07, 3.77, a, b)
	end)
	doorZ(3.77, 4.16, dy0, dy1)
	doorZ(4.16, 4.55, dy0, dy1)
	doorX(6.4, 7.0, dy0, dy1)
	doorX(7.0, 7.6, dy0, dy1)
	drawers(3, function(a, b)
		doorX(7.6, 8.4, a, b)
	end)
	doorX(8.4, 8.98, dy0, dy1) -- 빌트인 식기세척기(문짝 일체)
	bx(g, 0.64, ct - 0.115, 8.52, 0.655, ct - 0.09, 8.64, rgb(80, 180, 255), MAT.Neon, deco("DishwasherLed"))
	-- 쿼츠 상판(4 cm, 문짝보다 2 cm 앞) — 개수대 자리 개구
	local sx0, sx1, sz0, sz1 = 1.15, 1.95, 9.06, 9.5
	bx(g, 0.02, cb, 6.38, 0.66, ct, 8.96, QUARTZ, MAT.Marble, solid("Countertop"))
	bx(g, 0.02, cb, 8.96, sx0, ct, 9.58, QUARTZ, MAT.Marble, solid("Countertop"))
	bx(g, sx1, cb, 8.96, 4.57, ct, 9.58, QUARTZ, MAT.Marble, solid("Countertop"))
	bx(g, sx0, cb, 8.96, sx1, ct, sz0, QUARTZ, MAT.Marble, solid("Countertop"))
	bx(g, sx0, cb, sz1, sx1, ct, 9.58, QUARTZ, MAT.Marble, solid("Countertop"))
	-- 언더싱크 볼(깊이 20 cm): 바닥 + 4면 + 배수구
	local SS = rgb(172, 174, 178)
	local by0 = ct - 0.24
	bx(g, sx0, by0, sz0, sx1, by0 + 0.02, sz1, SS, MAT.Metal, deco("SinkBottom"))
	bx(g, sx0, by0 + 0.02, sz0, sx0 + 0.015, cb, sz1, SS, MAT.Metal, deco("SinkWall"))
	bx(g, sx1 - 0.015, by0 + 0.02, sz0, sx1, cb, sz1, SS, MAT.Metal, deco("SinkWall"))
	bx(g, sx0 + 0.015, by0 + 0.02, sz0, sx1 - 0.015, cb, sz0 + 0.015, SS, MAT.Metal, deco("SinkWall"))
	bx(g, sx0 + 0.015, by0 + 0.02, sz1 - 0.015, sx1 - 0.015, cb, sz1, SS, MAT.Metal, deco("SinkWall"))
	cyl(g, (sx0 + sx1) / 2, by0 - 0.02, (sz0 + sz1) / 2, 0.055, 0.08, rgb(60, 60, 62), MAT.Metal, deco("Drain"))
	cyl(g, 1.35, by0 + 0.02, 9.3, 0.07, 0.16, rgb(244, 244, 240), MAT.SmoothPlastic, deco("BowlInSink"))
	-- 풀다운 수전(크롬) + 직수 정수기 수전(백색, LED)
	local fx, fz = 1.55, 9.54
	cyl(g, fx, ct, fz, 0.05, 0.06, CHROME, MAT.Metal, deco("FaucetBase"))
	cyl(g, fx, ct + 0.05, fz, 0.27, 0.032, CHROME, MAT.Metal, deco("Faucet"))
	bx(g, fx - 0.016, ct + 0.31, fz - 0.21, fx + 0.016, ct + 0.342, fz + 0.016, CHROME, MAT.Metal, deco("FaucetNeck"))
	cyl(g, fx, ct + 0.21, fz - 0.19, 0.12, 0.042, CHROME, MAT.Metal, deco("FaucetHead"))
	bx(g, fx + 0.03, ct + 0.12, fz - 0.01, fx + 0.11, ct + 0.135, fz + 0.01, CHROME, MAT.Metal, deco("FaucetLever"))
	local px, pz = 1.86, 9.54
	cyl(g, px, ct, pz, 0.04, 0.05, rgb(240, 240, 238), MAT.SmoothPlastic, deco("PurifierBase"))
	cyl(g, px, ct + 0.04, pz, 0.24, 0.028, rgb(240, 240, 238), MAT.SmoothPlastic, deco("PurifierTap"))
	bx(g, px - 0.015, ct + 0.27, pz - 0.14, px + 0.015, ct + 0.305, pz + 0.015, rgb(240, 240, 238), MAT.SmoothPlastic, deco("PurifierSpout"))
	bx(g, px - 0.012, ct + 0.275, pz - 0.155, px + 0.012, ct + 0.3, pz - 0.14, rgb(80, 170, 255), MAT.Neon, deco("PurifierLed"))
	cyl(g, 1.03, ct, 9.47, 0.17, 0.065, rgb(236, 232, 224), MAT.SmoothPlastic, deco("SoapPump"))
	cyl(g, 1.03, ct + 0.17, 9.47, 0.04, 0.02, CHROME, MAT.Metal, deco("PumpHead"))
	-- 창: 대리석 창대 + 창가 허브 화분 2
	bx(g, KW_X0, UF + KW_Y0 - 0.03, 9.54, KW_X1, UF + KW_Y0 + 0.015, 9.72, MARBLE_W, MAT.Marble, deco("WinSill"))
	smallPlant(g, 1.25, UF + KW_Y0 + 0.015, 9.63, 0.1, 0.09, 0.14, rng, rgb(196, 120, 80))
	smallPlant(g, 2.3, UF + KW_Y0 + 0.015, 9.63, 0.1, 0.09, 0.14, rng, rgb(232, 228, 220))
	-- 인덕션(상판 위 1.5 cm) + 냄비 + 프라이팬 + 조작부
	bx(g, 3.12, ct - 0.01, 9.03, 3.72, ct + 0.015, 9.55, rgb(16, 16, 18), MAT.Glass, { name = "Induction", collide = false, query = false, shadow = false, reflectance = 0.12 })
	bx(g, 3.3, ct + 0.015, 9.05, 3.54, ct + 0.03, 9.08, rgb(255, 110, 60), MAT.Neon, deco("HobControls"))
	cyl(g, 3.27, ct + 0.015, 9.38, 0.14, 0.22, rgb(190, 192, 196), MAT.Metal, deco("Pot"))
	cyl(g, 3.27, ct + 0.155, 9.38, 0.02, 0.23, rgb(200, 206, 210), MAT.Glass, { name = "PotLid", collide = false, query = false, shadow = false, transparency = 0.2 })
	Kit.ball(g, V(3.27, ct + 0.19, 9.38), M(0.04), rgb(30, 30, 32), MAT.SmoothPlastic, deco("LidKnob"))
	cyl(g, 3.57, ct + 0.015, 9.22, 0.045, 0.26, rgb(40, 40, 42), MAT.Metal, deco("Pan"))
	bx(g, 3.555, ct + 0.035, 8.87, 3.585, ct + 0.055, 9.09, rgb(30, 30, 32), MAT.Metal, deco("PanHandle"))
	-- 상부장(천장까지, 깊이 35 cm, 하부 55 cm 띄움) + 슬림 후드(쿡탑 위 장 아래 비저) + 하부 LED
	local uy0 = UF + 1.45
	local hy0 = UF + 1.62
	local function upperZ(x0: number, x1: number, y0: number, n: number)
		bx(g, x0, y0, 9.23, x1, CEIL, 9.58, BODY, MAT.SmoothPlastic, solid("UpperCabinet"))
		local w = (x1 - x0) / n
		for i = 0, n - 1 do
			bx(g, x0 + i * w + GAP / 2, y0, 9.21, x0 + (i + 1) * w - GAP / 2, CEIL - 0.005, 9.23, CAB, MAT.SmoothPlastic, deco("CabDoor"))
		end
	end
	upperZ(2.62, 3.02, uy0, 1)
	upperZ(3.02, 3.78, hy0, 2)
	upperZ(3.78, 4.57, uy0, 2)
	bx(g, 3.04, hy0 - 0.05, 9.15, 3.76, hy0, 9.58, STEEL, MAT.Metal, solid("HoodVisor"))
	for _, hx in { 3.2, 3.6 } do
		bx(g, hx - 0.08, hy0 - 0.065, 9.32, hx + 0.08, hy0 - 0.05, 9.4, rgb(255, 236, 200), MAT.Neon, neon("HoodLight"))
	end
	bx(g, 2.64, uy0 - 0.015, 9.25, 3.0, uy0, 9.28, rgb(255, 224, 180), MAT.Neon, neon("UnderCabinetLed"))
	bx(g, 3.8, uy0 - 0.015, 9.25, 4.55, uy0, 9.28, rgb(255, 224, 180), MAT.Neon, neon("UnderCabinetLed"))
	-- 서쪽 상부장(z 6.4..9.58, 깊이 35 cm, 4짝)
	bx(g, 0.02, uy0, 6.4, 0.37, CEIL, 9.58, BODY, MAT.SmoothPlastic, solid("UpperCabinet"))
	local uw = (9.58 - 6.4) / 4
	for i = 0, 3 do
		bx(g, 0.37, uy0, 6.4 + i * uw + GAP / 2, 0.39, CEIL - 0.005, 6.4 + (i + 1) * uw - GAP / 2, CAB, MAT.SmoothPlastic, deco("CabDoor"))
	end
	bx(g, 0.3, uy0 - 0.015, 6.45, 0.34, uy0, 9.5, rgb(255, 224, 180), MAT.Neon, neon("UnderCabinetLed"))
	-- 백스플래시(대형 타일, 1.5 cm): 창 둘레 · 후드 뒤 · 서쪽 벽
	local BS = rgb(236, 234, 230)
	local bz = 9.565
	bx(g, 0.02, ct, bz, 0.39, uy0, 9.58, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, 0.39, uy0, bz, KW_X0, CEIL, 9.58, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, 0.39, ct, bz, KW_X0, uy0, 9.58, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, KW_X0, ct, bz, KW_X1, UF + KW_Y0, 9.58, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, KW_X0, UF + KW_Y1, bz, KW_X1, CEIL, 9.58, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, KW_X1, ct, bz, 3.02, uy0, 9.58, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, 3.02, ct, bz, 3.78, hy0 - 0.05, 9.58, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, 3.78, ct, bz, 4.57, uy0, 9.58, BS, MAT.CeramicTiles, deco("Backsplash"))
	bx(g, 0.02, ct, 6.38, 0.035, uy0, bz, BS, MAT.CeramicTiles, deco("Backsplash"))
	outlet(g, "z", bz, -1, 2.4, UF + 1.15)
	outlet(g, "z", bz, -1, 4.35, UF + 1.15)
	outlet(g, "x", 0.035, 1, 7.6, UF + 1.15)

	-- 냉장고장: 스탠드형 김치냉장고(위 2도어 + 서랍 2) | 4도어 냉장고(위 양문 + 아래 서랍 2) + 위 수납장
	local function panelZ(x0: number, x1: number, y0: number, y1: number, zf: number, col: Color3)
		bx(g, x0, y0, zf - 0.02, x1, y1, zf, col, MAT.SmoothPlastic, deco("ApplianceDoor"))
	end
	local kx0, kx1, kz0 = 4.62, 5.3, 8.88
	local KC = rgb(206, 198, 184)
	bx(g, kx0, UF, kz0, kx1, UF + 1.84, 9.58, rgb(188, 184, 176), MAT.SmoothPlastic, solid("KimchiFridge"))
	local km = (kx0 + kx1) / 2
	panelZ(kx0 + 0.003, km - GAP / 2, UF + 0.97, UF + 1.83, kz0, KC)
	panelZ(km + GAP / 2, kx1 - 0.003, UF + 0.97, UF + 1.83, kz0, KC)
	panelZ(kx0 + 0.003, kx1 - 0.003, UF + 0.52, UF + 0.97 - GAP, kz0, KC)
	panelZ(kx0 + 0.003, kx1 - 0.003, UF + 0.05, UF + 0.52 - GAP, kz0, KC)
	bx(g, km + 0.05, UF + 1.6, kz0 - 0.035, km + 0.13, UF + 1.64, kz0 - 0.02, rgb(120, 200, 255), MAT.Neon, deco("KimchiDisplay"))
	local fx0, fx1, fz0 = 5.33, 6.23, 8.85
	local FT, FBm = rgb(236, 234, 230), rgb(150, 156, 164)
	bx(g, fx0, UF, fz0, fx1, UF + 1.84, 9.58, rgb(196, 194, 190), MAT.SmoothPlastic, solid("Fridge"))
	local fm = (fx0 + fx1) / 2
	panelZ(fx0 + 0.003, fm - GAP / 2, UF + 0.83, UF + 1.83, fz0, FT)
	panelZ(fm + GAP / 2, fx1 - 0.003, UF + 0.83, UF + 1.83, fz0, FT)
	panelZ(fx0 + 0.003, fx1 - 0.003, UF + 0.44, UF + 0.83 - GAP, fz0, FBm)
	panelZ(fx0 + 0.003, fx1 - 0.003, UF + 0.05, UF + 0.44 - GAP, fz0, FBm)
	for _, hx in { fm - 0.045, fm + 0.025 } do
		bx(g, hx, UF + 1.05, fz0 - 0.05, hx + 0.02, UF + 1.6, fz0 - 0.02, STEEL, MAT.Metal, deco("FridgeHandle"))
	end
	bx(g, fx0 + 0.15, UF + 0.76, fz0 - 0.05, fx1 - 0.15, UF + 0.78, fz0 - 0.02, STEEL, MAT.Metal, deco("FridgeHandle"))
	bx(g, fx0 + 0.15, UF + 0.37, fz0 - 0.05, fx1 - 0.15, UF + 0.39, fz0 - 0.02, STEEL, MAT.Metal, deco("FridgeHandle"))
	bx(g, fx1 - 0.3, UF + 1.2, fz0 - 0.035, fx1 - 0.12, UF + 1.44, fz0 - 0.02, rgb(250, 240, 200), MAT.SmoothPlastic, deco("KidDrawing"))
	bx(g, fx1 - 0.24, UF + 1.3, fz0 - 0.05, fx1 - 0.18, UF + 1.38, fz0 - 0.035, rgb(220, 80, 80), MAT.SmoothPlastic, deco("Magnet"))
	bx(g, kx0, UF + 1.86, 8.85, fx1, CEIL, 9.58, BODY, MAT.SmoothPlastic, solid("TallTopCabinet"))
	for _, d in { { kx0, km }, { km, kx1 + 0.015 }, { kx1 + 0.015, fm }, { fm, fx1 } } do
		bx(g, d[1] + GAP / 2, UF + 1.86, 8.83, d[2] - GAP / 2, CEIL - 0.005, 8.85, CAB, MAT.SmoothPlastic, deco("CabDoor"))
	end

	-- 아일랜드(월넛 몸통 + 쿼츠 상판, 거실 쪽 30 cm 오버행) + 주방 쪽 서랍 4×2 + 바 스툴 2
	local ix0, ix1 = 1.5, 4.3
	bx(g, ix0, UF + 0.08, 6.78, ix1, cb, 7.52, WALNUT, MAT.Wood, solid("Island"))
	bx(g, ix0 + 0.05, UF, 6.83, ix1 - 0.05, UF + 0.08, 7.47, rgb(30, 30, 32), MAT.SmoothPlastic, deco("IslandPlinth"))
	bx(g, 1.42, cb, 6.5, 4.38, ct, 7.6, QUARTZ, MAT.Marble, solid("IslandTop"))
	local iw = (ix1 - ix0) / 4
	for i = 0, 3 do
		for k = 0, 1 do
			local y0 = UF + 0.1 + k * 0.33
			bx(g, ix0 + i * iw + GAP / 2, y0 + GAP / 2, 7.52, ix0 + (i + 1) * iw - GAP / 2, y0 + 0.33 - GAP / 2, 7.54, rgb(112, 84, 62), MAT.Wood, deco("IslandDrawer"))
		end
	end
	for _, sxp in { 2.3, 3.5 } do
		cyl(g, sxp, UF, 6.2, 0.02, 0.4, rgb(40, 40, 42), MAT.Metal, deco("StoolBase"))
		cyl(g, sxp, UF + 0.02, 6.2, 0.61, 0.05, rgb(40, 40, 42), MAT.Metal, deco("StoolPole"))
		cyl(g, sxp, UF + 0.25, 6.2, 0.02, 0.3, rgb(40, 40, 42), MAT.Metal, deco("StoolFootRing"))
		cyl(g, sxp, UF + 0.63, 6.2, 0.06, 0.38, rgb(150, 98, 64), MAT.Leather, solid("StoolSeat"))
	end
	cyl(g, 2.05, ct, 7.05, 0.08, 0.3, rgb(244, 242, 236), MAT.SmoothPlastic, deco("Bowl"))
	for i = 0, 4 do
		Kit.ball(g, V(2.05 + math.cos(i * 1.25) * 0.08, ct + 0.1, 7.05 + math.sin(i * 1.25) * 0.08), M(0.08), if i % 2 == 0 then rgb(120, 170, 60) else rgb(200, 50, 40), MAT.SmoothPlastic, deco("Fruit"))
	end
	smallPlant(g, 3.95, ct, 7.2, 0.14, 0.13, 0.22, rng, rgb(196, 120, 80))
	Kit.box(g, LCF(3.0, ct + 0.015, 7.1) * CFrame.Angles(0, math.rad(-15), 0), SZ(0.3, 0.03, 0.22), rgb(232, 226, 210), MAT.SmoothPlastic, deco("Cookbook"))

	-- 조리대 소품: 식기건조대(접시·컵) · 도마+칼+채소 · 전기포트 · 양념병 · 밥솥 · 커피머신 · 수저통
	local rk = { 0.68, 1.1, 9.1, 9.5 }
	bx(g, rk[1], ct, rk[3], rk[2], ct + 0.02, rk[4], rgb(214, 216, 220), MAT.Metal, deco("DishRackTray"))
	for _, p in { { rk[1], rk[3] }, { rk[2] - 0.015, rk[3] }, { rk[1], rk[4] - 0.015 }, { rk[2] - 0.015, rk[4] - 0.015 } } do
		bx(g, p[1], ct + 0.02, p[2], p[1] + 0.015, ct + 0.3, p[2] + 0.015, CHROME, MAT.Metal, deco("DishRackPost"))
	end
	bx(g, rk[1], ct + 0.3, rk[3], rk[2], ct + 0.315, rk[3] + 0.015, CHROME, MAT.Metal, deco("DishRackRail"))
	bx(g, rk[1], ct + 0.3, rk[4] - 0.015, rk[2], ct + 0.315, rk[4], CHROME, MAT.Metal, deco("DishRackRail"))
	for i = 0, 3 do
		Kit.hcyl(g, CFrame.new(V(0.75 + i * 0.05, ct + 0.135, 9.24)), M(0.015), M(0.22), rgb(250, 250, 248), MAT.SmoothPlastic, deco("Plate"))
	end
	for i = 0, 1 do
		cyl(g, 0.8 + i * 0.13, ct + 0.02, 9.42, 0.09, 0.075, if i == 0 then rgb(240, 238, 232) else rgb(120, 150, 180), MAT.SmoothPlastic, deco("CupUpsideDown"))
	end
	Kit.box(g, LCF(2.3, ct + 0.01, 9.25) * CFrame.Angles(0, math.rad(6), 0), SZ(0.42, 0.02, 0.28), OAK_L, MAT.Wood, deco("CuttingBoard"))
	Kit.box(g, LCF(2.32, ct + 0.03, 9.16) * CFrame.Angles(0, math.rad(-8), 0), SZ(0.26, 0.015, 0.04), CHROME, MAT.Metal, deco("Knife"))
	Kit.ball(g, V(2.22, ct + 0.06, 9.3), M(0.08), rgb(230, 120, 40), MAT.SmoothPlastic, deco("Veg"))
	Kit.ball(g, V(2.36, ct + 0.065, 9.32), M(0.09), rgb(90, 140, 60), MAT.SmoothPlastic, deco("Veg"))
	cyl(g, 2.85, ct, 9.42, 0.02, 0.17, rgb(30, 30, 32), MAT.SmoothPlastic, deco("KettleBase"))
	cyl(g, 2.85, ct + 0.02, 9.42, 0.2, 0.15, rgb(232, 230, 226), MAT.SmoothPlastic, deco("Kettle"))
	bx(g, 2.835, ct + 0.06, 9.49, 2.865, ct + 0.2, 9.52, rgb(40, 40, 42), MAT.SmoothPlastic, deco("KettleHandle"))
	bx(g, 2.84, ct + 0.17, 9.31, 2.86, ct + 0.19, 9.35, rgb(232, 230, 226), MAT.SmoothPlastic, deco("KettleSpout"))
	cyl(g, 2.98, ct, 9.52, 0.2, 0.055, rgb(40, 22, 14), MAT.Glass, deco("SoySauce"))
	cyl(g, 3.05, ct, 9.48, 0.24, 0.055, rgb(150, 140, 40), MAT.Glass, deco("OliveOil"))
	cyl(g, 4.2, ct, 9.35, 0.24, 0.3, rgb(236, 236, 234), MAT.SmoothPlastic, deco("RiceCooker"))
	cyl(g, 4.2, ct + 0.24, 9.35, 0.03, 0.27, rgb(150, 36, 40), MAT.SmoothPlastic, deco("RiceCookerLid"))
	bx(g, 4.12, ct + 0.12, 9.185, 4.28, ct + 0.2, 9.2, rgb(30, 30, 32), MAT.SmoothPlastic, deco("RiceCookerPanel"))
	bx(g, 4.15, ct + 0.15, 9.17, 4.21, ct + 0.18, 9.185, rgb(90, 200, 255), MAT.Neon, deco("RiceCookerLcd"))
	bx(g, 0.08, ct, 7.0, 0.42, ct + 0.36, 7.32, rgb(36, 36, 38), MAT.Metal, deco("CoffeeMachine"))
	bx(g, 0.42, ct + 0.02, 7.06, 0.48, ct + 0.04, 7.26, rgb(60, 60, 62), MAT.Metal, deco("DripTray"))
	cyl(g, 0.45, ct + 0.04, 7.16, 0.08, 0.07, rgb(240, 238, 232), MAT.SmoothPlastic, deco("EspressoCup"))
	cyl(g, 0.3, ct, 7.9, 0.15, 0.12, rgb(214, 206, 192), MAT.SmoothPlastic, deco("UtensilCrock"))
	for i = 0, 3 do
		Kit.cylAlongY(g, LCF(0.3 + (i % 2 - 0.5) * 0.04, ct + 0.2, 7.9 + (i // 2 - 0.5) * 0.04) * CFrame.Angles(math.rad((i - 1.5) * 6), 0, math.rad((i % 2 - 0.5) * 10)), M(0.28), M(0.02), if i % 2 == 0 then rgb(60, 50, 40) else rgb(30, 30, 32), MAT.Wood, deco("Utensil"))
	end
	smallPlant(g, 0.3, ct, 8.65, 0.14, 0.13, 0.22, rng, rgb(232, 228, 220))
end

--------------------------------------------------------------------------------------------------
-- 5-5) 현관 · 복도: 키큰 신발장(띄움 + 간접등, 전신거울 도어, 오픈 니치) · 3연동 중문(블랙 슬림, 열림) ·
--      월패드 · 일괄소등 스위치 · 신발/슬리퍼/우산 · 액자
--------------------------------------------------------------------------------------------------
local function unitEntry(g: Model, rng: Random)
	local w0 = W4X0
	-- 신발장: 몸통 A(z 8.44..9.2 키큰) + B(9.2..9.58, 가운데 니치로 나뉨)
	local sx0, sx1 = 6.4, 6.78
	local sz0, sm, sz1 = 8.44, 9.2, 9.58
	local SB = rgb(200, 198, 194)
	local ny0, ny1 = UF + 0.85, UF + 1.15
	bx(g, sx0, HF + 0.15, sz0, sx1, CEIL, sm, SB, MAT.SmoothPlastic, solid("ShoeCabinet"))
	bx(g, sx0, HF + 0.15, sm, sx1, ny0, sz1, SB, MAT.SmoothPlastic, solid("ShoeCabinet"))
	bx(g, sx0, ny1, sm, sx1, CEIL, sz1, SB, MAT.SmoothPlastic, solid("ShoeCabinet"))
	bx(g, sx0, ny0, sm, sx0 + 0.03, ny1, sz1, WALNUT, MAT.Wood, deco("NicheBack"))
	bx(g, sx0 + 0.03, ny1 - 0.015, sm + 0.01, sx1 - 0.03, ny1, sz1 - 0.01, rgb(255, 220, 170), MAT.Neon, neon("NicheLed"))
	bx(g, sx0 + 0.02, HF + 0.135, sz0 + 0.03, sx1 - 0.04, HF + 0.15, sz1 - 0.03, rgb(255, 214, 160), MAT.Neon, neon("ShoeCabinetLed"))
	-- 문짝(2 cm, 6 mm 틈): 1 = 화이트, 2 = 전신거울, 3 = 니치 위/아래
	local DC = rgb(240, 238, 234)
	local dw = (sz1 - sz0 - 2 * GAP) / 3
	local zA = sz0
	local zB = sz0 + dw + GAP
	local zC = sz0 + 2 * (dw + GAP)
	bx(g, sx1, HF + 0.16, zA, sx1 + 0.02, CEIL - 0.01, zA + dw, DC, MAT.SmoothPlastic, deco("ShoeDoor"))
	bx(g, sx1, HF + 0.16, zB, sx1 + 0.02, CEIL - 0.01, zB + dw, DC, MAT.SmoothPlastic, deco("ShoeDoor"))
	bx(g, sx1 + 0.02, HF + 0.24, zB + 0.03, sx1 + 0.035, CEIL - 0.09, zB + dw - 0.03, rgb(196, 206, 212), MAT.Glass, { name = "Mirror", collide = false, query = false, shadow = false, reflectance = 0.4 })
	bx(g, sx1, HF + 0.16, zC, sx1 + 0.02, ny0 - 0.005, sz1, DC, MAT.SmoothPlastic, deco("ShoeDoor"))
	bx(g, sx1, ny1 + 0.005, zC, sx1 + 0.02, CEIL - 0.01, sz1, DC, MAT.SmoothPlastic, deco("ShoeDoor"))
	-- 니치 소품: 키 트레이 · 디퓨저(병 + 리드 스틱) · 작은 액자
	bx(g, sx0 + 0.12, ny0, 9.3, sx0 + 0.3, ny0 + 0.015, 9.48, WALNUT, MAT.Wood, deco("KeyTray"))
	cyl(g, sx0 + 0.2, ny0, sm + 0.05, 0.1, 0.07, rgb(190, 170, 140), MAT.Glass, deco("Diffuser"))
	for i = 0, 3 do
		Kit.cylAlongY(g, LCF(sx0 + 0.2 + (i % 2 - 0.5) * 0.02, ny0 + 0.17, sm + 0.05 + (i // 2 - 0.5) * 0.02) * CFrame.Angles(math.rad((i // 2 - 0.5) * 16), 0, math.rad((i % 2 - 0.5) * 16)), M(0.16), M(0.006), rgb(60, 44, 32), MAT.Wood, deco("ReedStick"))
	end

	-- 3연동 중문(z 8.25 중심, 블랙 알루미늄 2.5 cm 프레임 + 투명 유리 + 가운데 가로대) — 세 짝이 서쪽으로 겹쳐 열림
	local mz = 8.25
	bx(g, 6.4, CEIL - 0.05, mz - 0.07, w0, CEIL, mz + 0.07, BLACK_AL, MAT.Metal, solid("MidDoorHead"))
	bx(g, 6.4, UF, mz - 0.07, 6.44, CEIL - 0.05, mz + 0.07, BLACK_AL, MAT.Metal, solid("MidDoorJamb"))
	bx(g, w0 - 0.04, UF, mz - 0.07, w0, CEIL - 0.05, mz + 0.07, BLACK_AL, MAT.Metal, solid("MidDoorJamb"))
	local pw = 0.6
	local py0, py1 = UF + 0.01, CEIL - 0.055
	for i = 0, 2 do
		local x0 = 6.44 + i * 0.03
		local zc = mz - 0.045 + i * 0.045
		local z0, z1 = zc - 0.02, zc + 0.02
		local function fr(a0: number, b0: number, a1: number, b1: number)
			bx(g, a0, b0, z0, a1, b1, z1, BLACK_AL, MAT.Metal, deco("MidDoorFrame"))
		end
		fr(x0, py0, x0 + 0.025, py1)
		fr(x0 + pw - 0.025, py0, x0 + pw, py1)
		fr(x0 + 0.025, py0, x0 + pw - 0.025, py0 + 0.04)
		fr(x0 + 0.025, py1 - 0.03, x0 + pw - 0.025, py1)
		fr(x0 + 0.025, UF + 0.95, x0 + pw - 0.025, UF + 0.975)
		bx(g, x0 + 0.02, py0 + 0.035, zc - 0.0075, x0 + pw - 0.02, py1 - 0.025, zc + 0.0075, rgb(176, 184, 186), MAT.Glass, glassO("MidDoorGlass", 0.72, false))
		if i == 2 then
			bx(g, x0 + pw - 0.075, UF + 0.6, z1, x0 + pw - 0.055, UF + 1.45, z1 + 0.025, BLACK_AL, MAT.Metal, deco("MidDoorHandle"))
		end
	end

	-- 신발 2켤레(밑창 + 갑피) · 슬리퍼 2켤레 · 우산
	for i, s in { { 7.25, 9.1, rgb(245, 245, 245) }, { 7.6, 9.2, rgb(40, 40, 44) } } do
		for _, dx in { -0.06, 0.06 } do
			bx(g, s[1] + dx - 0.045, HF, s[2] - 0.135, s[1] + dx + 0.045, HF + 0.025, s[2] + 0.135, rgb(236, 234, 228), MAT.Rubber, deco("Sole"))
			bx(g, s[1] + dx - 0.04, HF + 0.025, s[2] - 0.08, s[1] + dx + 0.04, HF + 0.09, s[2] + 0.13, s[3], if i == 1 then MAT.Fabric else MAT.Leather, deco("ShoeUpper"))
			Kit.ellipsoid(g, LCF(s[1] + dx, HF + 0.045, s[2] - 0.08), SZ(0.08, 0.06, 0.1), s[3], if i == 1 then MAT.Fabric else MAT.Leather, deco("ShoeToe"))
		end
	end
	for _, sp in { { 7.1, rgb(170, 160, 150) }, { 7.45, rgb(120, 136, 150) } } do
		for _, dx in { -0.06, 0.06 } do
			bx(g, sp[1] + dx - 0.05, UF, 7.92, sp[1] + dx + 0.05, UF + 0.02, 8.17, rgb(236, 232, 224), MAT.Rubber, deco("SlipperSole"))
			bx(g, sp[1] + dx - 0.05, UF + 0.02, 7.92, sp[1] + dx + 0.05, UF + 0.05, 8.04, sp[2], MAT.Fabric, deco("SlipperStrap"))
		end
	end
	Kit.cylAlongY(g, LCF(7.88, HF + 0.45, 9.48) * CFrame.Angles(0, 0, math.rad(6)), M(0.9), M(0.05), rgb(30, 44, 70), MAT.Fabric, deco("Umbrella"))
	Kit.ball(g, V(7.83, HF + 0.92, 9.48), M(0.05), rgb(40, 30, 24), MAT.Wood, deco("UmbrellaHandle"))
	-- 월패드(비디오폰) + 일괄소등 스위치(복도 쪽 W4 벽, 현관 바닥 기준 1.45 m)
	local wpz0, wpz1 = 8.55, 8.88
	wb(g, "x", w0, -1, 0, 0.02, wpz0, wpz1, UF + 1.28, UF + 1.53, rgb(246, 246, 244), MAT.SmoothPlastic, deco("WallPad"))
	local wp = wb(g, "x", w0, -1, 0.02, 0.035, wpz0 + 0.025, wpz1 - 0.07, UF + 1.31, UF + 1.5, rgb(32, 52, 80), MAT.Neon, deco("WallPadScreen"))
	Kit.label(wp, NID.Left, "2001호  18:05\n실내 23.5℃ · 외기 12℃", { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 140, maxDistance = 40 })
	for i = 0, 3 do
		wb(g, "x", w0, -1, 0.02, 0.035, wpz1 - 0.055, wpz1 - 0.025, UF + 1.33 + i * 0.045, UF + 1.36 + i * 0.045, rgb(206, 206, 204), MAT.SmoothPlastic, deco("WallPadKey"))
	end
	local ms = wb(g, "x", w0, -1, 0, 0.018, 9.08, 9.22, UF + 1.0, UF + 1.13, rgb(246, 246, 244), MAT.SmoothPlastic, deco("MasterSwitch"))
	Kit.label(ms, NID.Left, "일괄소등", { color = rgb(90, 90, 94), pixelsPerStud = 160, maxDistance = 25 })
	wb(g, "x", w0, -1, 0.018, 0.033, 9.13, 9.17, UF + 1.02, UF + 1.04, rgb(255, 60, 40), MAT.Neon, deco("MasterSwitchLed"))
	-- 복도 액자 + 욕실/서재 스위치
	picture(g, "x", 6.4, 1, 7.25, 8.0, UF + 1.25, UF + 1.85, rgb(196, 120, 80), rgb(60, 80, 110))
	switchPlate(g, "x", w0, -1, 6.56, UF + 1.15)
end

--------------------------------------------------------------------------------------------------
-- 5-6) 안방: 퀸 침대(헤드보드 · 이불 · 베개 5 · 러너) · 협탁 2 · 붙박이장 · 화장대(LED 거울 + 화장품) ·
--      침대 벤치 · 암막+쉬어 커튼 · 1-way 시스템에어컨 · 러그 · 액자 · 식물
--------------------------------------------------------------------------------------------------
local function unitMaster(g: Model, rng: Random)
	local w1, ex = W4X1, EXW - 0.02 -- ex = 도배면
	-- 러그(침대 아래) — 침대 받침은 러그 위
	local ru = UF + 0.015
	bx(g, 9.55, UF, 1.3, 11.9, ru, 3.9, rgb(204, 198, 190), MAT.Carpet, deco("BedRug"))
	-- 침대: 받침 + 월넛 프레임 + 매트리스 + 헤드보드
	bx(g, 10.35, ru, 1.85, 12.15, UF + 0.08, 3.35, rgb(30, 28, 26), MAT.SmoothPlastic, deco("BedPlinth"))
	bx(g, 10.25, UF + 0.08, 1.75, 12.25, UF + 0.3, 3.45, WALNUT, MAT.Wood, solid("BedFrame"))
	bx(g, 10.3, UF + 0.3, 1.8, 12.22, UF + 0.5, 3.4, rgb(246, 246, 244), MAT.Fabric, solid("Mattress"))
	bx(g, 12.25, UF + 0.1, 1.6, ex, UF + 1.2, 3.6, rgb(150, 138, 124), MAT.Fabric, solid("Headboard"))
	for i = 1, 4 do
		bx(g, 12.235, UF + 0.14, 1.6 + i * 0.4 - 0.008, 12.25, UF + 1.16, 1.6 + i * 0.4 + 0.008, rgb(128, 118, 106), MAT.Fabric, deco("HeadboardChannel"))
	end
	-- 이불(매트리스를 덮고 옆으로 늘어짐) + 접힌 윗단 + 발치 러너
	local DUV = rgb(232, 230, 224)
	bx(g, 10.27, UF + 0.33, 1.77, 11.75, UF + 0.56, 3.43, DUV, MAT.Fabric, deco("Duvet"))
	bx(g, 11.75, UF + 0.5, 1.785, 11.92, UF + 0.6, 3.415, rgb(214, 210, 200), MAT.Fabric, deco("DuvetFold"))
	bx(g, 10.4, UF + 0.56, 1.755, 10.85, UF + 0.575, 3.445, rgb(122, 112, 98), MAT.Fabric, deco("BedRunner"))
	bx(g, 10.4, UF + 0.4, 1.74, 10.85, UF + 0.575, 1.755, rgb(122, 112, 98), MAT.Fabric, deco("BedRunnerSide"))
	bx(g, 10.4, UF + 0.4, 3.445, 10.85, UF + 0.575, 3.46, rgb(122, 112, 98), MAT.Fabric, deco("BedRunnerSide"))
	-- 베개: 유로 쿠션 2(세움) + 베개 2(기댐) + 허리 쿠션
	for k, z in { 2.17, 3.03 } do
		local yaw = math.rad(if k == 1 then 3 else -3)
		Kit.box(g, LCF(12.1, UF + 0.84, z) * CFrame.Angles(0, yaw, math.rad(-8)), SZ(0.17, 0.6, 0.6), rgb(196, 188, 176), MAT.Fabric, deco("EuroSham"))
		Kit.box(g, LCF(11.93, UF + 0.68, z) * CFrame.Angles(0, -yaw, math.rad(-22)), SZ(0.15, 0.48, 0.66), rgb(250, 250, 248), MAT.Fabric, deco("Pillow"))
	end
	Kit.box(g, LCF(11.78, UF + 0.65, 2.6) * CFrame.Angles(0, 0, math.rad(-12)), SZ(0.13, 0.3, 0.5), rgb(160, 120, 84), MAT.Fabric, deco("LumbarCushion"))
	-- 협탁 2(월넛, 서랍 + 손잡이) + 스탠드 / 시계·휴대폰·물컵·책
	for i, nz in { { 1.08, 1.56 }, { 3.64, 4.12 } } do
		bx(g, 11.9, UF, nz[1], ex, UF + 0.52, nz[2], OAK, MAT.Wood, solid("Nightstand"))
		bx(g, 11.88, UF + 0.3, nz[1] + 0.02, 11.9, UF + 0.48, nz[2] - 0.02, rgb(150, 112, 78), MAT.Wood, deco("DrawerFront"))
		Kit.ball(g, V(11.87, UF + 0.39, (nz[1] + nz[2]) / 2), M(0.03), rgb(176, 160, 128), MAT.Metal, deco("Knob"))
		local mid = (nz[1] + nz[2]) / 2
		if i == 1 then
			cyl(g, 12.12, UF + 0.52, mid, 0.24, 0.12, rgb(214, 204, 186), MAT.SmoothPlastic, deco("LampBase"))
			cyl(g, 12.12, UF + 0.74, mid, 0.22, 0.3, rgb(244, 236, 220), MAT.Fabric, { name = "LampShade", collide = false, query = false, shadow = false, transparency = 0.1 })
			local nb = Kit.ball(g, V(12.12, UF + 0.84, mid), M(0.08), LAMP, MAT.Neon, neon("LampBulb"))
			light(nb, "PointLight", { color = rgb(255, 196, 130), brightness = 1.0, range = M(3) })
			bx(g, 11.92, UF + 0.52, nz[1] + 0.02, 12.04, UF + 0.55, nz[1] + 0.2, rgb(150, 52, 44), MAT.SmoothPlastic, deco("Book"))
		else
			local clk = bx(g, 12.05, UF + 0.52, 3.7, 12.15, UF + 0.6, 3.86, rgb(30, 30, 32), MAT.SmoothPlastic, deco("AlarmClock"))
			Kit.label(clk, NID.Left, "18:05", { color = rgb(255, 120, 60), glow = true, pixelsPerStud = 120, maxDistance = 30 })
			bx(g, 11.96, UF + 0.52, 3.92, 12.14, UF + 0.535, 4.0, rgb(20, 20, 22), MAT.Glass, deco("Phone"))
			cyl(g, 12.25, UF + 0.52, 3.95, 0.11, 0.07, GLASS_C, MAT.Glass, { name = "WaterGlass", collide = false, query = false, shadow = false, transparency = 0.4 })
		end
	end
	outlet(g, "x", ex, -1, 0.95, UF + 0.3)
	outlet(g, "x", ex, -1, 4.28, UF + 0.3)
	-- 침대 벤치(발치, 러그 위)
	bx(g, 9.7, UF + 0.33, 1.95, 10.12, UF + 0.45, 3.25, rgb(176, 160, 140), MAT.Fabric, solid("BedBench"))
	for _, p in { { 9.74, 1.99 }, { 10.04, 1.99 }, { 9.74, 3.17 }, { 10.04, 3.17 } } do
		bx(g, p[1], ru, p[2], p[1] + 0.04, UF + 0.33, p[2] + 0.04, WALNUT, MAT.Wood, deco("BenchLeg"))
	end
	-- 붙박이장(바닥~천장): 몸통 + 문짝 4(6 mm 틈) + 긴 바 손잡이(받침 포함)
	bx(g, 9.2, UF, 4.42, ex, CEIL, 4.98, rgb(180, 176, 170), MAT.SmoothPlastic, solid("Wardrobe"))
	local ww = (ex - 9.2) / 4
	for i = 0, 3 do
		local x0 = 9.2 + i * ww
		bx(g, x0 + GAP / 2, UF + 0.012, 4.4, x0 + ww - GAP / 2, CEIL - 0.008, 4.42, rgb(232, 228, 220), MAT.SmoothPlastic, deco("WardrobeDoor"))
		local hx = if i % 2 == 0 then x0 + ww - 0.06 else x0 + 0.04
		bx(g, hx, UF + 0.75, 4.37, hx + 0.02, UF + 1.45, 4.385, rgb(176, 156, 120), MAT.Metal, deco("WardrobeHandle"))
		for _, hy in { UF + 0.78, UF + 1.42 } do
			bx(g, hx + 0.003, hy - 0.01, 4.385, hx + 0.017, hy + 0.01, 4.4, rgb(176, 156, 120), MAT.Metal, deco("HandlePost"))
		end
	end
	-- 화장대(벽걸이, 오크) + LED 백라이트 거울 + 화장품 + 스툴
	bx(g, w1, UF + 0.6, 0.6, w1 + 0.45, UF + 0.76, 1.7, OAK, MAT.Wood, solid("Dresser"))
	bx(g, w1 + 0.45, UF + 0.62, 0.65, w1 + 0.47, UF + 0.74, 1.65, rgb(196, 160, 118), MAT.Wood, deco("DresserDrawer"))
	bx(g, w1 + 0.47, UF + 0.67, 1.1, w1 + 0.485, UF + 0.69, 1.2, rgb(176, 156, 120), MAT.Metal, deco("DresserPull"))
	bx(g, w1, UF + 0.98, 0.83, w1 + 0.015, UF + 1.87, 1.47, rgb(255, 232, 200), MAT.Neon, neon("MirrorHalo"))
	bx(g, w1 + 0.015, UF + 1.0, 0.85, w1 + 0.04, UF + 1.85, 1.45, rgb(40, 40, 42), MAT.Metal, deco("MirrorFrame"))
	bx(g, w1 + 0.04, UF + 1.02, 0.87, w1 + 0.055, UF + 1.83, 1.43, rgb(200, 210, 216), MAT.Glass, { name = "Mirror", collide = false, query = false, shadow = false, reflectance = 0.4 })
	Props.fillShelf(g, frameAt(w1 + 0.43, UF + 0.76, 1.15, -90), 0.85, 0.3, 0.3, "cosmetic", rng, { maxItems = 8, front = true })
	bx(g, w1 + 0.05, UF + 0.76, 0.66, w1 + 0.25, UF + 0.775, 0.8, rgb(196, 170, 120), MAT.Metal, deco("JewelryTray"))
	cyl(g, w1 + 0.8, UF, 1.15, 0.42, 0.4, rgb(222, 212, 198), MAT.Fabric, solid("Pouf"))
	outlet(g, "x", w1, 1, 1.85, UF + 0.95)
	-- 커튼(레일 박스 + 쉬어 + 암막, 양쪽으로 모음)
	bx(g, w1 + 0.02, CEIL - 0.04, 0.22, ex, CEIL, 0.42, rgb(236, 236, 234), MAT.SmoothPlastic, deco("CurtainBox"))
	local function drape(x0: number, x1: number, zf: number, n: number, col: Color3, tr: number, name: string)
		local w = (x1 - x0) / n
		for i = 0, n - 1 do
			local z = zf + (i % 2) * 0.035
			bx(g, x0 + i * w, UF + 0.01, z, x0 + (i + 1) * w, CEIL - 0.04, z + 0.035, col, MAT.Fabric, { name = name, collide = false, query = false, shadow = false, transparency = tr })
		end
	end
	drape(8.2, 9.0, 0.24, 5, rgb(244, 242, 236), 0.4, "Sheer")
	drape(8.2, 8.8, 0.32, 5, rgb(150, 140, 128), 0, "Drape")
	drape(11.56, ex - 0.02, 0.24, 5, rgb(244, 242, 236), 0.4, "Sheer")
	drape(11.76, ex - 0.02, 0.32, 5, rgb(150, 140, 128), 0, "Drape")
	-- 벽 액자(침대 위) · 스위치 · 식물
	picture(g, "x", ex, -1, 2.15, 3.05, UF + 1.35, UF + 1.95, rgb(120, 150, 170), rgb(230, 214, 186))
	switchPlate(g, "x", w1, 1, 3.75, UF + 1.15)
	bigPlant(g, "sansevieria", 8.48, UF, 3.4, 0.8, rng, rgb(196, 190, 180))
end

--------------------------------------------------------------------------------------------------
-- 5-7) 욕실: 대형 타일 · 젠다이(변기·세면대 뒤 선반, 매립 수조) · 벽걸이 세면대 + 언더볼 · 수납 거울장 ·
--      벽걸이 변기 + 비데 · 수건장(오픈 선반에 말아 둔 수건) · 해바라기 샤워(온도조절 수전 + 레인 헤드 +
--      핸드 샤워) · 유리 칸막이 · 선반 · 트렌치/바닥 배수구 · SMC 천장(리브 · 환풍구 · 점검구) · 조명
--------------------------------------------------------------------------------------------------
local function unitBath(g: Model, rng: Random)
	local w1, ex = W4X1, EXW
	local bf = UF - 0.03
	local bz0, bz1 = 5.12, 7.2
	local t = 0.025
	local TW = TILE_W
	local BCY = CEIL - 0.06 -- 욕실 천장(SMC) 아랫면 2.24 m
	-- 벽 타일
	bx(g, w1, bf, bz0, w1 + t, CEIL, 5.5, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, w1, bf, 6.4, w1 + t, CEIL, bz1, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, w1, UF + DOOR_H + 0.06, 5.5, w1 + t, CEIL, 6.4, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, ex - t, bf, bz0, ex, CEIL, bz1, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, w1 + t, bf, bz0, ex - t, CEIL, bz0 + t, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, w1 + t, bf, bz1 - t, ex - t, CEIL, bz1, TW, MAT.CeramicTiles, deco("WallTile"))
	bx(g, ex - t - 0.015, bf, bz0 + t, ex - t, BCY, bz1 - t, rgb(132, 134, 136), MAT.CeramicTiles, deco("ShowerAccentTile"))
	local sw = ex - t - 0.015 -- 샤워 벽면 12.36
	local nz = bz1 - t -- 북쪽 타일면 7.175
	-- SMC 천장 + 리브 2 + 조명 패널 + 환풍구 + 점검구
	bx(g, w1 + t, BCY, bz0 + t, ex - t, BCY + 0.015, nz, rgb(246, 246, 244), MAT.SmoothPlastic, solid("BathCeiling"))
	for _, rz in { 5.65, 6.67 } do
		bx(g, w1 + t, BCY - 0.015, rz - 0.01, ex - t, BCY, rz + 0.01, rgb(236, 236, 234), MAT.SmoothPlastic, deco("SmcRib"))
	end
	local bp = bx(g, 9.0, BCY - 0.015, 5.86, 9.6, BCY, 6.46, PANEL_COOL, MAT.Neon, neon("BathPanel"))
	light(bp, "PointLight", { color = rgb(236, 240, 255), brightness = 0.85, range = M(3.0) })
	bx(g, 10.68, BCY - 0.015, 5.28, 10.96, BCY, 5.56, rgb(240, 240, 238), MAT.SmoothPlastic, deco("ExhaustGrille"))
	for i = 0, 3 do
		bx(g, 10.71, BCY - 0.03, 5.31 + i * 0.065, 10.93, BCY - 0.015, 5.33 + i * 0.065, rgb(150, 152, 156), MAT.SmoothPlastic, deco("ExhaustSlat"))
	end
	bx(g, 10.0, BCY - 0.015, 5.9, 10.45, BCY, 6.35, rgb(238, 238, 236), MAT.SmoothPlastic, deco("AccessHatch"))
	-- 젠다이(타일 박스 + 인조대리석 상판, 2 cm 앞으로)
	local jz0 = 7.0
	local jy = UF + 1.0
	bx(g, w1 + t, bf, jz0, 11.25, jy, nz, TW, MAT.CeramicTiles, solid("Jendai"))
	bx(g, w1 + t, jy, jz0 - 0.02, 11.25, jy + 0.025, nz, rgb(244, 242, 238), MAT.Marble, solid("JendaiTop"))
	-- 세면대: 벽걸이 월넛 장(서랍 앞판 + 옆판) + 인조대리석 상판 + 언더볼 + 수전
	local vx0, vx1, vz0 = 8.5, 9.7, 6.5
	bx(g, vx0, UF + 0.45, vz0 + 0.02, vx1, UF + 0.66, jz0, WALNUT, MAT.Wood, solid("Vanity"))
	bx(g, vx0 + 0.003, UF + 0.46, vz0, vx1 - 0.003, UF + 0.79, vz0 + 0.02, rgb(110, 82, 60), MAT.Wood, deco("VanityFront"))
	bx(g, vx0, UF + 0.66, vz0 + 0.02, vx0 + 0.02, UF + 0.8, jz0, WALNUT, MAT.Wood, deco("VanitySide"))
	bx(g, vx1 - 0.02, UF + 0.66, vz0 + 0.02, vx1, UF + 0.8, jz0, WALNUT, MAT.Wood, deco("VanitySide"))
	bx(g, (vx0 + vx1) / 2 - 0.15, UF + 0.72, vz0 - 0.015, (vx0 + vx1) / 2 + 0.15, UF + 0.735, vz0, rgb(176, 156, 120), MAT.Metal, deco("VanityPull"))
	local cx0, cx1, cz0, cz1 = 8.85, 9.35, 6.6, 6.92
	local VT = rgb(248, 248, 246)
	bx(g, 8.48, UF + 0.8, 6.48, cx0, UF + 0.85, jz0, VT, MAT.Marble, solid("VanityTop"))
	bx(g, cx1, UF + 0.8, 6.48, 9.72, UF + 0.85, jz0, VT, MAT.Marble, solid("VanityTop"))
	bx(g, cx0, UF + 0.8, 6.48, cx1, UF + 0.85, cz0, VT, MAT.Marble, solid("VanityTop"))
	bx(g, cx0, UF + 0.8, cz1, cx1, UF + 0.85, jz0, VT, MAT.Marble, solid("VanityTop"))
	local BW = rgb(252, 252, 250)
	bx(g, cx0, UF + 0.68, cz0, cx1, UF + 0.7, cz1, BW, MAT.SmoothPlastic, deco("BasinBottom"))
	bx(g, cx0, UF + 0.7, cz0, cx0 + 0.015, UF + 0.8, cz1, BW, MAT.SmoothPlastic, deco("BasinWall"))
	bx(g, cx1 - 0.015, UF + 0.7, cz0, cx1, UF + 0.8, cz1, BW, MAT.SmoothPlastic, deco("BasinWall"))
	bx(g, cx0 + 0.015, UF + 0.7, cz0, cx1 - 0.015, UF + 0.8, cz0 + 0.015, BW, MAT.SmoothPlastic, deco("BasinWall"))
	bx(g, cx0 + 0.015, UF + 0.7, cz1 - 0.015, cx1 - 0.015, UF + 0.8, cz1, BW, MAT.SmoothPlastic, deco("BasinWall"))
	cyl(g, (cx0 + cx1) / 2, UF + 0.66, (cz0 + cz1) / 2, 0.055, 0.05, CHROME, MAT.Metal, deco("BasinDrain"))
	local fxp = (cx0 + cx1) / 2
	cyl(g, fxp, UF + 0.85, 6.96, 0.03, 0.055, CHROME, MAT.Metal, deco("BasinFaucetBase"))
	cyl(g, fxp, UF + 0.88, 6.96, 0.17, 0.035, CHROME, MAT.Metal, deco("BasinFaucet"))
	bx(g, fxp - 0.0175, UF + 1.02, 6.82, fxp + 0.0175, UF + 1.045, 6.96, CHROME, MAT.Metal, deco("BasinSpout"))
	bx(g, fxp - 0.01, UF + 1.045, 6.93, fxp + 0.01, UF + 1.06, 7.02, CHROME, MAT.Metal, deco("BasinLever"))
	-- 수납 거울장(젠다이 위, 거울 문 2 + 하부 LED)
	bx(g, vx0, UF + 1.15, 7.03, vx1, UF + 1.95, nz, rgb(236, 236, 234), MAT.SmoothPlastic, solid("MirrorCabinet"))
	local mw = (vx1 - vx0) / 2
	for i = 0, 1 do
		bx(g, vx0 + i * mw + GAP / 2, UF + 1.15, 7.01, vx0 + (i + 1) * mw - GAP / 2, UF + 1.95, 7.03, rgb(204, 214, 220), MAT.Glass, { name = "Mirror", collide = false, query = false, shadow = false, reflectance = 0.45 })
	end
	bx(g, vx0 + 0.05, UF + 1.135, 7.05, vx1 - 0.05, UF + 1.15, 7.1, rgb(240, 236, 226), MAT.Neon, neon("MirrorLed"))
	-- 젠다이 위 소품: 칫솔컵 · 핸드워시 · 디퓨저 · 화장품
	cyl(g, 8.33, jy + 0.025, 7.08, 0.1, 0.07, rgb(214, 224, 232), MAT.Glass, { name = "ToothCup", collide = false, query = false, shadow = false, transparency = 0.3 })
	for i = 0, 1 do
		Kit.cylAlongY(g, LCF(8.325 + i * 0.012, jy + 0.025 + 0.13, 7.08) * CFrame.Angles(0, 0, math.rad(-8 + i * 16)), M(0.17), M(0.012), if i == 0 then rgb(80, 160, 220) else rgb(240, 120, 140), MAT.SmoothPlastic, deco("Toothbrush"))
	end
	cyl(g, 9.85, jy + 0.025, 7.08, 0.16, 0.065, rgb(236, 230, 220), MAT.SmoothPlastic, deco("SoapPump"))
	cyl(g, 9.85, jy + 0.185, 7.08, 0.035, 0.022, CHROME, MAT.Metal, deco("PumpHead"))
	Props.fillShelf(g, frameAt(10.55, jy + 0.025, 6.99, 0), 0.5, 0.16, 0.3, "cosmetic", rng, { maxItems = 5, front = true })
	-- 벽걸이 변기 + 비데(본체 · 시트 · 뚜껑 · 측면 조작부) + 젠다이 전면 플러시 버튼 + 휴지걸이
	local tcx = 10.45
	local TC = rgb(250, 250, 248)
	bx(g, tcx - 0.18, UF + 0.12, 6.72, tcx + 0.18, UF + 0.38, jz0, TC, MAT.SmoothPlastic, solid("ToiletBowl"))
	Kit.ellipsoid(g, LCF(tcx, UF + 0.25, 6.72), SZ(0.36, 0.26, 0.52), TC, MAT.SmoothPlastic, deco("ToiletBowlFront"))
	bx(g, tcx - 0.2, UF + 0.38, 6.82, tcx + 0.2, UF + 0.5, jz0 - 0.005, rgb(244, 244, 242), MAT.SmoothPlastic, deco("BidetBody"))
	Kit.ellipsoid(g, LCF(tcx, UF + 0.4, 6.66), SZ(0.4, 0.04, 0.5), rgb(246, 246, 244), MAT.SmoothPlastic, deco("BidetSeat"))
	Kit.ellipsoid(g, LCF(tcx, UF + 0.435, 6.67), SZ(0.38, 0.03, 0.47), rgb(240, 240, 238), MAT.SmoothPlastic, deco("BidetLid"))
	bx(g, tcx + 0.2, UF + 0.4, 6.62, tcx + 0.25, UF + 0.48, 6.82, rgb(236, 236, 234), MAT.SmoothPlastic, deco("BidetPanel"))
	bx(g, tcx + 0.25, UF + 0.445, 6.66, tcx + 0.265, UF + 0.465, 6.7, rgb(60, 140, 230), MAT.Neon, deco("BidetButton"))
	bx(g, tcx + 0.25, UF + 0.445, 6.74, tcx + 0.265, UF + 0.465, 6.78, rgb(230, 90, 80), MAT.Neon, deco("BidetButton"))
	bx(g, tcx - 0.12, UF + 0.74, jz0 - 0.015, tcx + 0.12, UF + 0.9, jz0, CHROME, MAT.Metal, deco("FlushPlate"))
	bx(g, tcx - 0.05, UF + 0.79, jz0 - 0.03, tcx - 0.005, UF + 0.85, jz0 - 0.015, rgb(220, 222, 226), MAT.Metal, deco("FlushButton"))
	bx(g, tcx + 0.005, UF + 0.79, jz0 - 0.03, tcx + 0.05, UF + 0.85, jz0 - 0.015, rgb(220, 222, 226), MAT.Metal, deco("FlushButton"))
	bx(g, 10.86, UF + 0.66, jz0 - 0.03, 11.0, UF + 0.68, jz0, CHROME, MAT.Metal, deco("PaperHolder"))
	Kit.hcyl(g, CFrame.new(V(10.93, UF + 0.61, jz0 - 0.065)), M(0.11), M(0.11), rgb(250, 250, 248), MAT.Fabric, deco("PaperRoll"))
	-- 수건장(변기 위): 문 2 + 오픈 선반(말아 둔 수건 3)
	bx(g, 10.0, UF + 1.62, 6.9, 10.9, UF + 2.15, nz, rgb(236, 236, 234), MAT.SmoothPlastic, solid("TowelCabinet"))
	for i = 0, 1 do
		bx(g, 10.0 + i * 0.45 + GAP / 2, UF + 1.62, 6.88, 10.0 + (i + 1) * 0.45 - GAP / 2, UF + 2.15, 6.9, rgb(244, 244, 242), MAT.SmoothPlastic, deco("TowelCabinetDoor"))
	end
	bx(g, 10.0, UF + 1.43, 6.9, 10.9, UF + 1.45, nz, rgb(236, 236, 234), MAT.SmoothPlastic, deco("TowelShelf"))
	bx(g, 10.0, UF + 1.45, 6.9, 10.02, UF + 1.62, nz, rgb(236, 236, 234), MAT.SmoothPlastic, deco("TowelShelfSide"))
	bx(g, 10.88, UF + 1.45, 6.9, 10.9, UF + 1.62, nz, rgb(236, 236, 234), MAT.SmoothPlastic, deco("TowelShelfSide"))
	for i, tc in { rgb(240, 238, 232), rgb(150, 166, 180), rgb(240, 238, 232) } do
		Kit.hcyl(g, CFrame.new(V(10.17 + (i - 1) * 0.28, UF + 1.505, 7.04)) * CFrame.Angles(0, math.rad(90), 0), M(0.24), M(0.11), tc, MAT.Fabric, deco("RolledTowel"))
	end
	-- 수건걸이(서쪽 벽) + 걸린 수건
	for _, z in { 6.5, 6.93 } do
		bx(g, w1 + t, UF + 1.1, z, w1 + t + 0.045, UF + 1.12, z + 0.02, CHROME, MAT.Metal, deco("TowelBarPost"))
	end
	Kit.hcyl(g, CFrame.new(V(w1 + t + 0.035, UF + 1.11, 6.725)) * CFrame.Angles(0, math.rad(90), 0), M(0.46), M(0.02), CHROME, MAT.Metal, deco("TowelBar"))
	bx(g, w1 + t + 0.005, UF + 0.62, 6.54, w1 + t + 0.02, UF + 1.1, 6.91, rgb(214, 210, 202), MAT.Fabric, deco("Towel"))
	bx(g, w1 + t + 0.05, UF + 0.7, 6.54, w1 + t + 0.065, UF + 1.1, 6.91, rgb(214, 210, 202), MAT.Fabric, deco("Towel"))
	-- 샤워: 고정 유리 칸막이 + 프로파일 / 온도조절 수전 + 해바라기 레인 헤드 + 핸드 샤워 / 코너 선반 / 트렌치 배수구
	bx(g, 11.25, bf, bz0 + t, 11.27, UF + 2.0, 6.55, rgb(214, 228, 236), MAT.Glass, glassO("ShowerGlass", 0.78))
	bx(g, 11.235, UF + 2.0, bz0 + t, 11.285, UF + 2.03, 6.55, CHROME, MAT.Metal, deco("ShowerProfile"))
	bx(g, 11.235, bf, bz0 + t, 11.285, UF + 2.0, bz0 + t + 0.035, CHROME, MAT.Metal, deco("ShowerProfile"))
	local sc = 6.15
	bx(g, sw - 0.06, UF + 0.97, sc - 0.2, sw, UF + 1.03, sc + 0.2, CHROME, MAT.Metal, deco("ThermoMixer"))
	for _, dz in { -0.2, 0.2 } do
		Kit.hcyl(g, CFrame.new(V(sw - 0.04, UF + 1.0, sc + dz + (if dz < 0 then -0.02 else 0.02))) * CFrame.Angles(0, math.rad(90), 0), M(0.04), M(0.07), CHROME, MAT.Metal, deco("MixerKnob"))
	end
	cyl(g, sw - 0.035, UF + 1.03, sc, 1.02, 0.025, CHROME, MAT.Metal, deco("ShowerRiser"))
	bx(g, 11.87, UF + 2.04, sc - 0.0125, sw - 0.02, UF + 2.065, sc + 0.0125, CHROME, MAT.Metal, deco("ShowerArm"))
	cyl(g, 11.9, UF + 2.02, sc, 0.02, 0.28, CHROME, MAT.Metal, deco("RainShowerHead"))
	bx(g, sw - 0.06, UF + 1.4, sc - 0.03, sw - 0.02, UF + 1.45, sc + 0.03, CHROME, MAT.Metal, deco("HandShowerHolder"))
	Kit.cylAlongY(g, LCF(sw - 0.08, UF + 1.52, sc) * CFrame.Angles(0, 0, math.rad(12)), M(0.2), M(0.03), CHROME, MAT.Metal, deco("HandShower"))
	bx(g, sw - 0.16, UF + 1.15, bz0 + t, sw, UF + 1.17, bz0 + t + 0.16, CHROME, MAT.Metal, deco("CornerShelf"))
	for i, bc in { rgb(60, 100, 140), rgb(236, 230, 220), rgb(170, 200, 160) } do
		cyl(g, sw - 0.05 - (i - 1) * 0.045, UF + 1.17, bz0 + t + 0.05 + (i % 2) * 0.05, 0.2 - (i - 1) * 0.02, 0.05, bc, MAT.SmoothPlastic, deco("ShowerBottle"))
	end
	bx(g, 11.32, bf, nz - 0.09, sw - 0.02, bf + 0.015, nz - 0.03, rgb(150, 152, 156), MAT.Metal, deco("TrenchDrain"))
	bx(g, 9.86, bf, 6.0, 9.98, bf + 0.015, 6.12, rgb(176, 178, 182), MAT.Metal, deco("FloorDrain"))
	bx(g, 8.62, bf, 5.95, 9.55, bf + 0.015, 6.42, rgb(150, 160, 170), MAT.Carpet, deco("BathMat"))
end

--------------------------------------------------------------------------------------------------
-- 5-8) 서재: 2칸 6단 책장(책 + 소품) · 책상(27" 모니터 · 키보드 · 마우스 · 스탠드) · 프린터 장 · 사무 의자 · 러그
--------------------------------------------------------------------------------------------------
local function unitStudy(g: Model, rng: Random)
	local w1, ex = W4X1, EXW - 0.02
	local bz = 9.58
	-- 책장(2.0 × 2.1 m, 깊이 36.5 cm): 뒤판 · 옆판 · 가운데 칸막이 · 선반
	local KC = rgb(118, 90, 66)
	local kx0 = ex - 0.365
	local kz0, kz1 = 7.45, 9.45
	local km = (kz0 + kz1) / 2
	bx(g, ex - 0.015, UF, kz0, ex, UF + 2.1, kz1, KC, MAT.Wood, solid("BookcaseBack"))
	bx(g, kx0, UF, kz0, ex - 0.015, UF + 2.1, kz0 + 0.025, KC, MAT.Wood, solid("BookcaseSide"))
	bx(g, kx0, UF, kz1 - 0.025, ex - 0.015, UF + 2.1, kz1, KC, MAT.Wood, solid("BookcaseSide"))
	bx(g, kx0, UF, kz0 + 0.025, ex - 0.015, UF + 0.08, kz1 - 0.025, KC, MAT.Wood, solid("BookcaseBase"))
	bx(g, kx0, UF + 2.075, kz0 + 0.025, ex - 0.015, UF + 2.1, kz1 - 0.025, KC, MAT.Wood, solid("BookcaseTop"))
	bx(g, kx0, UF + 0.08, km - 0.0125, ex - 0.015, UF + 2.075, km + 0.0125, KC, MAT.Wood, solid("BookcaseDivider"))
	local levels = {}
	for i = 0, 4 do
		local top = UF + 0.08 + i * 0.4
		if i > 0 then
			bx(g, kx0, top - 0.025, kz0 + 0.025, ex - 0.015, top, km - 0.0125, KC, MAT.Wood, solid("Shelf"))
			bx(g, kx0, top - 0.025, km + 0.0125, ex - 0.015, top, kz1 - 0.025, KC, MAT.Wood, solid("Shelf"))
		end
		table.insert(levels, top)
	end
	local bayW = km - 0.0125 - (kz0 + 0.025)
	local bays = { (kz0 + 0.025 + km - 0.0125) / 2, (km + 0.0125 + kz1 - 0.025) / 2 }
	for li, top in levels do
		for bi, bc in bays do
			local cf = frameAt(kx0, top, bc, 90)
			if (li == 3 and bi == 2) or (li == 4 and bi == 1) or (li == 5 and bi == 2) then
				-- 소품 칸: 책 몇 권 + 화분/수납박스/액자
				Props.fillShelf(g, cf * CFrame.new(M(bayW * 0.25), 0, 0), bayW * 0.45, 0.33, 0.37, "book", rng, { maxItems = 6, front = true })
				if li == 3 then
					smallPlant(g, kx0 + 0.18, top, bc + bayW * 0.25, 0.14, 0.13, 0.22, rng, rgb(232, 228, 220))
				elseif li == 4 then
					bx(g, kx0 + 0.04, top, bc + bayW * 0.12, kx0 + 0.32, top + 0.22, bc + bayW * 0.45, rgb(196, 180, 150), MAT.Fabric, deco("StorageBox"))
				else
					picture(g, "x", ex - 0.015, -1, bc + bayW * 0.12, bc + bayW * 0.42, top + 0.03, top + 0.3, rgb(170, 120, 90), nil)
				end
			else
				-- 폭 여유 4 cm: fillShelf 는 책마다 폭이 달라 마지막 권이 칸막이에 닿을 수 있음
				Props.fillShelf(g, cf, bayW - 0.08, 0.33, 0.37, "book", rng, { maxItems = 14, front = true })
			end
		end
	end
	-- 책상(오크 상판 + 블랙 패널 다리)
	local dt = UF + TABLE_H
	bx(g, 9.2, dt - 0.03, 8.98, 11.3, dt, bz, OAK_L, MAT.Wood, solid("StudyDesk"))
	for _, x in { 9.23, 11.23 } do
		bx(g, x, UF, 9.03, x + 0.04, dt - 0.03, 9.53, rgb(36, 36, 38), MAT.Metal, solid("StudyDeskLeg"))
	end
	-- 27" 모니터(스탠드) + 키보드 + 마우스 + 노트 + 머그 + 스탠드
	bx(g, 10.14, dt, 9.32, 10.36, dt + 0.015, 9.48, rgb(40, 40, 42), MAT.Metal, deco("MonitorFoot"))
	bx(g, 10.23, dt + 0.015, 9.42, 10.27, dt + 0.3, 9.45, rgb(40, 40, 42), MAT.Metal, deco("MonitorNeck"))
	bx(g, 9.945, dt + 0.12, 9.38, 10.555, dt + 0.48, 9.42, rgb(22, 22, 24), MAT.SmoothPlastic, deco("Monitor"))
	bx(g, 9.955, dt + 0.13, 9.365, 10.545, dt + 0.47, 9.38, rgb(52, 80, 116), MAT.Neon, deco("MonitorScreen"))
	bx(g, 10.03, dt, 9.06, 10.47, dt + 0.02, 9.2, rgb(46, 46, 50), MAT.SmoothPlastic, deco("Keyboard"))
	Kit.ellipsoid(g, LCF(10.66, dt + 0.0325, 9.13), SZ(0.06, 0.035, 0.1), rgb(46, 46, 50), MAT.SmoothPlastic, deco("Mouse"))
	bx(g, 10.56, dt, 9.04, 10.78, dt + 0.015, 9.24, rgb(60, 60, 64), MAT.Fabric, deco("MousePad"))
	Kit.box(g, LCF(9.6, dt + 0.008, 9.15) * CFrame.Angles(0, math.rad(12), 0), SZ(0.21, 0.016, 0.28), rgb(30, 50, 80), MAT.SmoothPlastic, deco("Notebook"))
	cyl(g, 11.0, dt, 9.2, 0.09, 0.08, rgb(214, 96, 70), MAT.SmoothPlastic, deco("Mug"))
	cyl(g, 9.38, dt, 9.45, 0.02, 0.14, rgb(30, 30, 32), MAT.Metal, deco("DeskLampBase"))
	Kit.box(g, LCF(9.38, dt + 0.2, 9.42) * CFrame.Angles(math.rad(-10), 0, 0), SZ(0.015, 0.38, 0.015), rgb(30, 30, 32), MAT.Metal, deco("DeskLampArm"))
	Kit.box(g, LCF(9.38, dt + 0.39, 9.3) * CFrame.Angles(math.rad(70), 0, 0), SZ(0.015, 0.26, 0.015), rgb(30, 30, 32), MAT.Metal, deco("DeskLampArm"))
	cyl(g, 9.38, dt + 0.33, 9.19, 0.07, 0.12, rgb(30, 30, 32), MAT.Metal, deco("DeskLampHead"))
	smallPlant(g, 11.15, dt, 9.45, 0.1, 0.1, 0.16, rng, rgb(232, 228, 220))
	-- 프린터 장(2단 서랍) + 레이저 프린터 + 출력 용지
	bx(g, 8.2, UF, 9.06, 8.75, UF + 0.6, bz, rgb(236, 234, 230), MAT.SmoothPlastic, solid("PrinterCabinet"))
	for k = 0, 1 do
		bx(g, 8.203, UF + 0.02 + k * 0.29 + GAP / 2, 9.04, 8.747, UF + 0.02 + (k + 1) * 0.29 - GAP / 2, 9.06, rgb(244, 242, 238), MAT.SmoothPlastic, deco("CabDrawer"))
	end
	bx(g, 8.25, UF + 0.6, 9.12, 8.7, UF + 0.82, 9.55, rgb(226, 226, 224), MAT.SmoothPlastic, deco("Printer"))
	bx(g, 8.3, UF + 0.82, 9.14, 8.5, UF + 0.835, 9.24, rgb(40, 40, 44), MAT.SmoothPlastic, deco("PrinterPanel"))
	bx(g, 8.3, UF + 0.7, 9.0, 8.65, UF + 0.715, 9.12, rgb(70, 70, 74), MAT.SmoothPlastic, deco("PrinterTray"))
	bx(g, 8.33, UF + 0.715, 9.02, 8.62, UF + 0.73, 9.12, rgb(250, 250, 248), MAT.SmoothPlastic, deco("Paper"))
	-- 러그 + 사무 의자(5발 + 캐스터, 가스 실린더, 좌판, 메시 등판, 팔걸이) — 책상을 봄(+Z)
	bx(g, 9.15, UF, 7.7, 11.35, UF + 0.015, 8.9, rgb(120, 112, 106), MAT.Carpet, deco("StudyRug"))
	local ry = UF + 0.015
	local OC = frameAt(10.25, ry, 8.45, 180)
	for k = 0, 4 do
		local a = math.rad(k * 72 + 18)
		fb(g, OC * CFrame.Angles(0, a, 0), 0, 0.075, 0.15, 0.04, 0.03, 0.3, rgb(36, 36, 38), MAT.Metal, deco("ChairLeg"))
		Kit.ball(g, (OC * CFrame.Angles(0, a, 0) * mcf(0, 0.03, 0.29)).Position, M(0.055), rgb(30, 30, 32), MAT.SmoothPlastic, deco("Caster"))
	end
	Kit.vcyl(g, (OC * mcf(0, 0.25, 0)).Position, M(0.33), M(0.05), rgb(36, 36, 38), MAT.Metal, deco("ChairGas"))
	fb(g, OC, 0, 0.46, 0, 0.5, 0.08, 0.48, rgb(46, 48, 52), MAT.Fabric, solid("OfficeSeat"))
	Kit.box(g, OC * mcf(0, 0.83, 0.25) * CFrame.Angles(math.rad(-8), 0, 0), SZ(0.46, 0.58, 0.05), rgb(40, 42, 46), MAT.Fabric, deco("OfficeBack"))
	for _, sx in { -0.27, 0.27 } do
		fb(g, OC, sx, 0.56, 0.05, 0.03, 0.14, 0.04, rgb(36, 36, 38), MAT.Metal, deco("ArmPost"))
		fb(g, OC, sx, 0.64, 0.0, 0.06, 0.025, 0.26, rgb(30, 30, 32), MAT.Rubber, deco("ArmPad"))
	end
	-- 액자 · 식물 · 스위치 · 콘센트
	picture(g, "z", 7.32, 1, 9.0, 10.2, UF + 1.25, UF + 1.95, rgb(214, 170, 90), rgb(70, 96, 120))
	bigPlant(g, "areca", 11.65, UF, 9.25, 1.4, rng, rgb(196, 176, 150))
	switchPlate(g, "x", w1, 1, 8.55, UF + 1.15)
	outlet(g, "z", bz, -1, 11.1, UF + 0.3)
	outlet(g, "z", bz, -1, 8.9, UF + 0.3)
end

--------------------------------------------------------------------------------------------------
-- 5-9) 천장 설비: 다운라이트 · 직부등 · 시스템에어컨(거실 4-way, 침실/서재 1-way) · 감지기 · 컨실드 스프링클러
--      (11층 이상 아파트: 세대 내 스프링클러 의무. 욕실 제외) · 현관 센서등
--------------------------------------------------------------------------------------------------
-- 4-way 카세트(패널 0.95 m 각): 테 4변 + 흡입 그릴(1.5 cm 들어감) + 토출구 4(어두운 띠) + 표시등
local function acCassette4(g: Instance, x: number, z: number, cy: number)
	local h, fr = 0.475, 0.225
	local y0 = cy - 0.035
	local W = rgb(244, 244, 242)
	local yt = cy + 0.035
	bx(g, x - h, y0, z - h, x + h, yt, z - h + fr, W, MAT.SmoothPlastic, deco("AcFrame"))
	bx(g, x - h, y0, z + h - fr, x + h, yt, z + h, W, MAT.SmoothPlastic, deco("AcFrame"))
	bx(g, x - h, y0, z - h + fr, x - h + fr, yt, z + h - fr, W, MAT.SmoothPlastic, deco("AcFrame"))
	bx(g, x + h - fr, y0, z - h + fr, x + h, yt, z + h - fr, W, MAT.SmoothPlastic, deco("AcFrame"))
	bx(g, x - h + fr, y0 + 0.015, z - h + fr, x + h - fr, yt, z + h - fr, rgb(226, 226, 224), MAT.SmoothPlastic, deco("AcGrille"))
	for i = -2, 2 do
		bx(g, x - h + fr + 0.02, y0 + 0.0, z + i * 0.09 - 0.008, x + h - fr - 0.02, y0 + 0.015, z + i * 0.09 + 0.008, rgb(208, 208, 206), MAT.SmoothPlastic, deco("AcGrilleBar"))
	end
	local SL = rgb(78, 80, 84)
	bx(g, x - 0.31, y0 - 0.015, z - h + 0.07, x + 0.31, y0, z - h + 0.14, SL, MAT.SmoothPlastic, deco("AcOutlet"))
	bx(g, x - 0.31, y0 - 0.015, z + h - 0.14, x + 0.31, y0, z + h - 0.07, SL, MAT.SmoothPlastic, deco("AcOutlet"))
	bx(g, x - h + 0.07, y0 - 0.015, z - 0.31, x - h + 0.14, y0, z + 0.31, SL, MAT.SmoothPlastic, deco("AcOutlet"))
	bx(g, x + h - 0.14, y0 - 0.015, z - 0.31, x + h - 0.07, y0, z + 0.31, SL, MAT.SmoothPlastic, deco("AcOutlet"))
	bx(g, x + h - 0.06, y0 - 0.015, z + h - 0.06, x + h - 0.035, y0, z + h - 0.035, rgb(80, 170, 255), MAT.Neon, deco("AcLed"))
end
-- 1-way 슬림 카세트(1.0 × 0.4 m): 패널 + 토출구 + 루버
local function acCassette1(g: Instance, x: number, z: number, cy: number)
	bx(g, x - 0.5, cy - 0.04, z - 0.2, x + 0.5, cy + 0.035, z + 0.2, rgb(244, 244, 242), MAT.SmoothPlastic, deco("AcPanel"))
	bx(g, x - 0.44, cy - 0.055, z - 0.16, x + 0.44, cy - 0.04, z - 0.08, rgb(78, 80, 84), MAT.SmoothPlastic, deco("AcOutlet"))
	bx(g, x - 0.44, cy - 0.055, z + 0.02, x + 0.44, cy - 0.04, z + 0.16, rgb(226, 226, 224), MAT.SmoothPlastic, deco("AcGrille"))
	bx(g, x + 0.4, cy - 0.055, z - 0.05, x + 0.43, cy - 0.04, z - 0.03, rgb(80, 170, 255), MAT.Neon, deco("AcLed"))
end
-- 원형 LED 직부등(얇은 디스크, 테두리 + 발광면)
local function flushLight(g: Instance, x: number, z: number, cy: number, d: number): BasePart
	cyl(g, x, cy - 0.03, z, 0.065, d, rgb(236, 236, 232), MAT.SmoothPlastic, deco("LightRim"))
	return cyl(g, x, cy - 0.045, z, 0.02, d - 0.04, rgb(214, 188, 146), MAT.Neon, neon("LightDiffuser"))
end

local function unitCeiling(g: Model)
	local C = CEIL
	-- 거실: 우물천장 가운데 4-way 에어컨 + 둘레 다운라이트(아트월 워싱 포함) + 감지기 + 스프링클러
	acCassette4(g, (RX0 + RX1) / 2, (RZ0 + RZ1) / 2, C + REC)
	local wash
	for _, p in { { 3.35, 2.4 }, { 3.35, 3.8 }, { 3.35, 5.2 }, { 7.7, 2.4 }, { 7.7, 3.8 }, { 7.7, 5.2 }, { 4.6, 1.95 }, { 6.5, 1.95 } } do
		local d = downlight(g, p[1], p[2], C)
		if p[1] == 7.7 and p[2] == 2.4 then
			wash = d
		end
	end
	if wash then
		light(wash, "SpotLight", { color = rgb(255, 214, 168), brightness = 1.4, range = M(3.2), angle = 70, face = NID.Bottom })
	end
	detector(g, 3.35, 4.5, C)
	concealedSprinkler(g, 3.35, 3.1, C)
	concealedSprinkler(g, 7.7, 4.5, C)
	concealedSprinkler(g, 5.55, 5.9, C)
	-- 식당
	downlight(g, 2.65, 2.4, C)
	downlight(g, 2.65, 4.4, C)
	detector(g, 1.5, 5.15, C)
	concealedSprinkler(g, 1.5, 2.25, C)
	-- 주방: 아일랜드 위 라인 조명 + 다운라이트 + 열감지기 + 스프링클러
	local kl = bx(g, 1.7, C - 0.015, 7.0, 4.1, C + 0.035, 7.1, PANEL_WARM, MAT.Neon, neon("KitchenLine"))
	light(kl, "PointLight", { color = rgb(255, 226, 190), brightness = 0.85, range = M(4) })
	for _, p in { { 0.95, 8.3 }, { 2.0, 8.55 }, { 4.0, 8.55 }, { 5.75, 8.2 } } do
		downlight(g, p[1], p[2], C)
	end
	detector(g, 5.0, 7.6, C)
	concealedSprinkler(g, 2.9, 8.2, C)
	concealedSprinkler(g, 5.4, 6.7, C)
	-- 복도 · 현관(센서등 + 인체감지기)
	downlight(g, 7.2, 5.6, C)
	local cd = downlight(g, 7.2, 7.4, C)
	light(cd, "PointLight", { color = rgb(255, 220, 180), brightness = 0.6, range = M(2.8) })
	detector(g, 7.2, 6.5, C)
	concealedSprinkler(g, 7.2, 7.95, C)
	local el = flushLight(g, 7.2, 8.95, C, 0.26)
	cyl(g, 7.62, C - 0.03, 8.95, 0.065, 0.07, rgb(244, 244, 240), MAT.SmoothPlastic, deco("MotionSensor"))
	light(el, "PointLight", { color = rgb(255, 220, 180), brightness = 0.7, range = M(2.6) })
	-- 안방: 직부등 + 1-way 에어컨(창가) + 감지기 + 스프링클러 2
	local bl = flushLight(g, 10.4, 2.6, C, 0.5)
	light(bl, "PointLight", { color = rgb(255, 214, 168), brightness = 0.55, range = M(4) })
	acCassette1(g, 10.3, 0.75, C)
	detector(g, 9.3, 3.9, C)
	concealedSprinkler(g, 9.3, 1.7, C)
	concealedSprinkler(g, 11.4, 3.95, C)
	-- 서재
	local stl = flushLight(g, 10.25, 8.35, C, 0.4)
	light(stl, "PointLight", { color = rgb(255, 218, 176), brightness = 0.7, range = M(3.5) })
	acCassette1(g, 9.6, 7.75, C)
	detector(g, 11.2, 8.0, C)
	concealedSprinkler(g, 11.2, 8.9, C)
	-- 발코니
	flushLight(g, 4.0, 0.75, C, 0.25)
	concealedSprinkler(g, 2.1, 0.75, C)
end

local function unitInterior(g: Model, rng: Random)
	unitStructure(g)
	unitBalcony(g, rng)
	unitLiving(g, rng)
	unitKitchen(g, rng)
	unitEntry(g, rng)
	unitMaster(g, rng)
	unitBath(g, rng)
	unitStudy(g, rng)
	unitCeiling(g)
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
