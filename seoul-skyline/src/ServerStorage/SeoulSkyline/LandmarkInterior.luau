--!strict
-- SeoulSkyline / LandmarkInterior
-- 롯데월드타워 모티브 타워 + 몰의 "걸어 들어가는" 실내 (Landmark 바로 다음에 빌드, Landmark.layout 을 읽음).
-- 실제 스케일 1 stud = 0.3 m. 모든 치수는 Config.m(미터) / Config.Real.
--
--   1) 타워 로비 (지상, 강 쪽 +Z 로컬 면 가운데): 32 × 25 m, 천장 12.6 m 대리석 2개 층 높이 홀.
--      자동 미닫이문 2곳(유효 2.4 × 2.7 m) + 방풍실, 안내 데스크(1.1 m), 보안 게이트 7대(차선 1.1 m), 라운지 2조,
--      미디어 아트 월(28 × 6 m Neon 타일), 실내 나무 4 그루, 한/영 안내 사인, 엘리베이터 알코브(8.4 × 10 m, 천장 4.2 m):
--      양쪽 3대씩 + 끝벽 서울스카이 직행 셔틀(호출 버튼 = 태그 SeoulElevator → 전망대).
--   2) 서울스카이 전망대 (본체 꼭대기 유리 띠): 118F 전망 홀(천장 ≈ 8.6 m) — 광택 바닥, 스카이데크 유리 바닥(7.2 × 3.6 m,
--      빛나는 무한 거울 구덩이 아래 "500 m 아래 야경"), 파노라마 벤치, 망원경, 카페 카운터 + 메뉴판, 기념품숍,
--      반환 엘리베이터 / 123F 스카이 라운지(바 + 라운지 의자)로 가는 엘리베이터.
--      천장·바닥·코어(밖에서 보이는 밝은 유리 띠의 내용)는 Persistent 그룹 → 원경에서도 띠가 밝게 읽힘.
--   3) 몰 아트리움 (파란 곡면 지붕 홀): 정면 입구 통로(자동문) → 66 × 21.6 m 2개 층 갤러리아.
--      양쪽 2개 층 상점 27곳(진열창 + 한글 간판), 에스컬레이터 한 쌍(보이는 계단 + 숨은 경사로), 유리 난간 메자닌 + 다리 2,
--      앉음 섬(나무 화분), 팝업 키오스크, 행잉 배너, 미디어 스크린, 지붕을 열어 실내에서 보이는 파란 볼트 + 리브.
--   광원 30개 이하(로비 8 · 전망대 9 · 몰 12), 파트 ≈ 2000.

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local Landmark = require(script.Parent.Landmark) :: any

local LandmarkInterior = {}

local P = Config.Palette
local Real = Config.Real
local m2s = Config.m
local rgb = Color3.fromRGB
local MAT = Enum.Material
local FRONT = Enum.NormalId.Front
local BACK = Enum.NormalId.Back
local CYL_UP = CFrame.Angles(0, 0, math.rad(90))
type PartOpts = Kit.PartOpts

-- 파트 Front(-Z) 가 로컬 방향을 보게 하는 yaw
local FACE_PZ, FACE_NZ, FACE_PX, FACE_NX = math.pi, 0, -math.pi / 2, math.pi / 2

local SEAT = Real.Seat -- 0.43 m
local TABLE_H = Real.Table -- 0.75 m
local COUNTER = Real.Counter -- 0.9 m

local C = {
	marble = rgb(228, 223, 214),
	marbleWarm = rgb(214, 200, 178),
	granite = rgb(56, 54, 56),
	floorDark = rgb(52, 52, 58),
	travertine = rgb(214, 202, 182),
	plaster = rgb(234, 231, 224),
	walnut = rgb(84, 60, 42),
	oak = rgb(170, 130, 88),
	bronze = rgb(146, 112, 72),
	steel = rgb(196, 198, 202),
	steelDark = rgb(66, 68, 74),
	black = rgb(24, 25, 28),
	white = rgb(240, 240, 236),
	leather = rgb(96, 64, 44),
	fabricGrey = rgb(122, 120, 116),
	fabricBlue = rgb(54, 72, 106),
	fabricSand = rgb(198, 184, 160),
	warmLight = rgb(255, 226, 182),
	coolLight = rgb(224, 236, 255),
	glass = rgb(186, 204, 216),
	textWarm = rgb(255, 236, 204),
	textWhite = rgb(244, 244, 240),
}

------------------------------------------------------------------------------------------------------
-- 공용 헬퍼
------------------------------------------------------------------------------------------------------
local LIGHT_CAP = 30
local lightsUsed = 0

local function light(p: BasePart, kind: string, props: Kit.LightProps)
	if lightsUsed >= LIGHT_CAP then
		return
	end
	if Kit.light(p, kind, props) then
		lightsUsed += 1
	end
end

-- 충돌하는 큰 덩어리(바닥/벽/가구)
local function S(m: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material, name: string?, refl: number?): BasePart
	return Kit.part(m, cf, size, { name = name or "Solid", material = mat, color = color, collide = true, reflectance = refl })
end
-- 장식 소품(충돌·쿼리 없음)
local function D(m: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material, name: string?, refl: number?): BasePart
	return Kit.part(m, cf, size, { name = name or "Prop", material = mat, color = color, collide = false, query = false, reflectance = refl })
end
-- 발광(밤 Neon / 낮 밝은 무광)
local function N(m: Instance, cf: CFrame, size: Vector3, color: Color3, name: string?, tr: number?): BasePart
	return Kit.part(m, cf, size, {
		name = name or "Lamp",
		material = MAT.Neon,
		color = color,
		transparency = tr,
		collide = false,
		query = false,
		shadow = false,
		glow = true,
		dayMaterial = MAT.SmoothPlastic,
		dayColor = color:Lerp(rgb(236, 236, 232), 0.55),
	})
end
local function G(m: Instance, cf: CFrame, size: Vector3, color: Color3, tr: number, collide: boolean, name: string?): BasePart
	return Kit.part(m, cf, size, { name = name or "Glass", material = MAT.Glass, color = color, transparency = tr, reflectance = 0.05, collide = collide, query = collide, shadow = false })
end
-- 세로 원기둥 (cf 위치 = 중심)
local function VC(m: Instance, cf: CFrame, h: number, d: number, color: Color3, mat: Enum.Material, collide: boolean, name: string?): BasePart
	return Kit.part(m, CFrame.new(cf.Position) * CYL_UP, Vector3.new(h, d, d), { name = name or "Cyl", shape = "Cylinder", material = mat, color = color, collide = collide, query = collide })
end
-- 글자 판(Front 면). glow: 글자가 빛 영향 없이 밝음
local function sign(m: Instance, cf: CFrame, size: Vector3, bg: Color3, bgMat: Enum.Material, text: string, tc: Color3?, ppS: number?): BasePart
	local p = Kit.part(m, cf, size, { name = "Sign", material = bgMat, color = bg, collide = false, query = false, shadow = false })
	if bgMat == MAT.Neon then
		Kit.glow(p, MAT.SmoothPlastic, bg)
	end
	Kit.label(p, FRONT, text, { color = tc or C.textWhite, glow = true, pixelsPerStud = ppS or 24, maxDistance = 500, font = Enum.Font.GothamBold })
	return p
end

-- 엘리베이터 호출 버튼(SeoulSkylineBoot 가 ElevatorTarget 으로 순간 이동)
local function elevatorButton(m: Instance, cf: CFrame, target: Vector3, action: string, object: string): BasePart
	local b = Kit.part(m, cf, Vector3.new(0.55, 0.55, 0.16), {
		name = "ElevatorCall",
		material = MAT.Neon,
		color = rgb(150, 214, 255),
		collide = false,
		query = true,
		shadow = false,
		glow = true,
		dayMaterial = MAT.SmoothPlastic,
		dayColor = rgb(206, 214, 222),
	})
	b:SetAttribute("ElevatorTarget", target)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "ElevatorPrompt"
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0.25
	pp.MaxActivationDistance = 8
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = b
	CollectionService:AddTag(b, "SeoulElevator")
	return b
end

------------------------------------------------------------------------------------------------------
-- 가구 (cf = 바닥 위 발자국 중심, 로컬 -Z = 정면(앉은 사람이 보는 쪽))
------------------------------------------------------------------------------------------------------
-- 소파: 좌면 0.43 m, 깊이 0.9 m, 등받이 0.8 m
local function sofa(m: Instance, cf: CFrame, len: number, col: Color3, pillow: Color3?)
	S(m, cf * CFrame.new(0, 0.5, 0), Vector3.new(len, 1.0, 3.0), col:Lerp(C.black, 0.45), MAT.Fabric, "SofaBase")
	D(m, cf * CFrame.new(0, SEAT - 0.21, -0.2), Vector3.new(len - 1.52, 0.42, 2.5), col, MAT.Fabric, "Cushion")
	S(m, cf * CFrame.new(0, 1.85, 1.15), Vector3.new(len, 1.7, 0.7), col, MAT.Fabric, "SofaBack")
	for _, sx in { -1, 1 } do
		S(m, cf * CFrame.new(sx * (len / 2 - 0.37), 1.5, -0.05), Vector3.new(0.74, 1.0, 2.9), col, MAT.Fabric, "SofaArm")
	end
	if pillow then
		D(m, cf * CFrame.new(-len / 2 + 1.6, 2.0, 0.55) * CFrame.Angles(math.rad(-14), 0, math.rad(9)), Vector3.new(1.4, 1.25, 0.36), pillow, MAT.Fabric, "Pillow")
	end
end

-- 라운지/카페 의자(좌면 0.43 m)
local function chair(m: Instance, cf: CFrame, col: Color3, mat: Enum.Material?)
	local mt = mat or MAT.Wood
	S(m, cf * CFrame.new(0, SEAT - 0.07, 0), Vector3.new(1.45, 0.14, 1.45), col, mt, "ChairSeat")
	D(m, cf * CFrame.new(0, SEAT + 0.95, 0.66), Vector3.new(1.45, 1.6, 0.12), col, mt, "ChairBack")
	for _, sx in { -1, 1 } do
		D(m, cf * CFrame.new(sx * 0.62, (SEAT - 0.14) / 2, 0), Vector3.new(0.1, SEAT - 0.14, 1.3), C.black, MAT.Metal, "ChairLeg")
	end
end

-- 둥근 테이블(높이 h, 지름 dia)
local function roundTable(m: Instance, cf: CFrame, dia: number, h: number, top: Color3, topMat: Enum.Material)
	VC(m, cf * CFrame.new(0, 0.08, 0), 0.16, dia * 0.55, C.black, MAT.Metal, true, "TableFoot")
	VC(m, cf * CFrame.new(0, h / 2, 0), h - 0.2, 0.3, C.black, MAT.Metal, true, "TableStem")
	VC(m, cf * CFrame.new(0, h - 0.07, 0), 0.14, dia, top, topMat, true, "TableTop")
end

-- 등받이 없는 가죽 벤치(좌면 0.43 m, 폭 0.6 m)
local function bench(m: Instance, cf: CFrame, len: number, col: Color3)
	S(m, cf * CFrame.new(0, 0.5, 0), Vector3.new(len - 0.8, 1.0, 1.3), C.black, MAT.Metal, "BenchBase")
	S(m, cf * CFrame.new(0, SEAT - 0.21, 0), Vector3.new(len, 0.42, 2.0), col, MAT.Leather, "BenchSeat")
end

-- 화분 + 나무(실내): potD 지름, potH 높이, treeH 나무 높이
local function treePlanter(m: Instance, cf: CFrame, potD: number, potH: number, treeH: number, rng: Random, potCol: Color3, potMat: Enum.Material)
	VC(m, cf * CFrame.new(0, potH / 2, 0), potH, potD, potCol, potMat, true, "Planter")
	VC(m, cf * CFrame.new(0, potH + 0.02, 0), 0.1, potD - 0.7, P.Soil, MAT.Ground, false, "Soil")
	VC(m, cf * CFrame.new(0, potH + treeH * 0.32, 0), treeH * 0.64, math.max(0.55, treeH * 0.026), P.Bark, MAT.Wood, true, "Trunk")
	local leaves = { P.Leaf2, P.Leaf3, P.Leaf1 }
	for k = 1, 3 do
		local cw = treeH * rng:NextNumber(0.3, 0.4)
		local off = Vector3.new(rng:NextNumber(-0.1, 0.1) * treeH, potH + treeH * (0.55 + 0.13 * k) - cw * 0.15, rng:NextNumber(-0.1, 0.1) * treeH)
		Kit.ellipsoid(m, cf * CFrame.new(off), Vector3.new(cw, cw * 0.78, cw), leaves[k], MAT.Grass, { name = "Foliage", query = false })
	end
end

-- 작은 화분(관엽식물)
local function pottedPlant(m: Instance, cf: CFrame, h: number, potCol: Color3)
	VC(m, cf * CFrame.new(0, h * 0.18, 0), h * 0.36, h * 0.32, potCol, MAT.Concrete, true, "Pot")
	Kit.ellipsoid(m, cf * CFrame.new(0, h * 0.62, 0), Vector3.new(h * 0.5, h * 0.62, h * 0.5), P.Leaf2, MAT.Grass, { name = "Plant", query = false })
end

-- 동전 망원경(접안부 ≈ 1.45 m), 로컬 -Z = 보는 방향
local function telescope(m: Instance, cf: CFrame)
	VC(m, cf * CFrame.new(0, 0.1, 0), 0.2, 2.0, C.steelDark, MAT.Metal, true, "ScopeFoot")
	VC(m, cf * CFrame.new(0, 2.1, 0), 4.0, 0.6, C.steelDark, MAT.Metal, true, "ScopePost")
	D(m, cf * CFrame.new(0, 3.1, 0.38), Vector3.new(0.75, 1.0, 0.36), rgb(40, 96, 168), MAT.Metal, "CoinBox", 0.1)
	local head = cf * CFrame.new(0, 4.75, 0) * CFrame.Angles(math.rad(-5), 0, 0)
	S(m, head, Vector3.new(2.1, 1.05, 1.8), rgb(40, 96, 168), MAT.Metal, "ScopeHead", 0.15)
	for _, sx in { -0.52, 0.52 } do
		D(m, head * CFrame.new(sx, 0.05, -1.0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.3, 0.72, 0.72), rgb(30, 40, 52), MAT.Glass, "ScopeLens", 0.3)
		D(m, head * CFrame.new(sx * 1.05, 0.12, 1.02) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.36, 0.38, 0.38), C.black, MAT.Rubber, "Eyepiece")
	end
end

-- 엘리베이터 문(벽면 위 cf, 로컬 -Z = 복도 쪽): 스테인리스 문틀 + 미닫이 두 짝 + 홀 랜턴 + 층 표시
local function elevatorDoor(m: Instance, cf: CFrame, dw: number, dh: number, floorTxt: string)
	D(m, cf * CFrame.new(0, (dh + 0.7) / 2, -0.15), Vector3.new(dw + 1.2, dh + 0.7, 0.3), C.steel, MAT.Metal, "DoorFrame", 0.25)
	for _, sx in { -1, 1 } do
		S(m, cf * CFrame.new(sx * (dw / 4 + 0.02), dh / 2, -0.42), Vector3.new(dw / 2 - 0.04, dh, 0.2), rgb(182, 184, 188), MAT.Metal, "DoorLeaf", 0.35)
	end
	N(m, cf * CFrame.new(0, dh + 1.25, -0.34), Vector3.new(1.4, 0.42, 0.06), rgb(255, 238, 206), "HallLantern")
	sign(m, cf * CFrame.new(0, dh + 2.15, -0.36), Vector3.new(1.7, 0.85, 0.1), C.black, MAT.Glass, floorTxt, rgb(255, 140, 70), 40)
end

-- 호출 패널(▲▼ 버튼 장식)
local function callPanel(m: Instance, cf: CFrame)
	D(m, cf * CFrame.new(0, 3.7, -0.07), Vector3.new(0.6, 1.3, 0.14), C.steel, MAT.Metal, "CallPanel", 0.25)
	N(m, cf * CFrame.new(0, 3.95, -0.16), Vector3.new(0.22, 0.22, 0.05), rgb(255, 230, 190), "CallUp")
	N(m, cf * CFrame.new(0, 3.45, -0.16), Vector3.new(0.22, 0.22, 0.05), rgb(255, 230, 190), "CallDown")
end

-- 차단봉(스탠션): 기둥 사이 벨트
local function stanchions(m: Instance, pts: { CFrame }, belt: Color3)
	for i, cf in pts do
		VC(m, cf * CFrame.new(0, 0.08, 0), 0.16, 1.2, C.steel, MAT.Metal, false, "StanchionBase")
		VC(m, cf * CFrame.new(0, 1.6, 0), 3.1, 0.22, C.steel, MAT.Metal, true, "Stanchion")
		if i > 1 then
			local a, b = pts[i - 1].Position + Vector3.new(0, 2.95, 0), cf.Position + Vector3.new(0, 2.95, 0)
			D(m, CFrame.lookAt((a + b) / 2, b), Vector3.new(0.06, 0.24, (b - a).Magnitude), belt, MAT.Fabric, "Belt")
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 1) 타워 로비
------------------------------------------------------------------------------------------------------
local ART = { rgb(34, 48, 140), rgb(96, 58, 178), rgb(196, 74, 160), rgb(244, 118, 84), rgb(250, 190, 100) }
local function artColor(t: number): Color3
	local x = math.clamp(t, 0, 0.999) * (#ART - 1)
	local i = math.floor(x)
	return ART[i + 1]:Lerp(ART[i + 2], x - i)
end

local function buildLobby(m: Model, TF: CFrame, Lb: any, obsTarget: Vector3, rng: Random)
	local W, HX, ZB, AX, AZ0 = Lb.W, Lb.HX, Lb.ZB, Lb.AX, Lb.AZ0
	local FY, CY = Lb.floorY, Lb.ceilY
	local gIn = Lb.glassZ - 0.2 -- 정면 유리 안쪽 면
	local AH = FY + m2s(4.2) -- 알코브 천장
	local cyB = CY - 1.4 -- 홀 천장 아랫면 (바닥에서 12.6 m)
	local function at(x: number, y: number, z: number, yaw: number?): CFrame
		return TF * CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0)
	end

	-- 바닥: 밝은 대리석 + 화강석 런너/테두리 + 가운데 원형 메달리온, 알코브는 어두운 화강석
	S(m, at(0, FY - 0.25, (ZB + W + 0.4) / 2), Vector3.new(2 * HX, 0.5, W + 0.4 - ZB), C.marble, MAT.Marble, "LobbyFloor", 0.08)
	S(m, at(0, FY - 0.25, (AZ0 + ZB) / 2), Vector3.new(2 * AX, 0.5, ZB - AZ0), C.granite, MAT.Granite, "AlcoveFloor", 0.12)
	local function inlay(x0: number, x1: number, z0: number, z1: number, c: Color3)
		D(m, at((x0 + x1) / 2, FY - 0.125, (z0 + z1) / 2), Vector3.new(x1 - x0, 0.35, z1 - z0), c, MAT.Granite, "Inlay", 0.1)
	end
	local bz0, bz1, bx = ZB + 9, gIn - 15, HX - 5
	inlay(-5, 5, bz0, bz1, C.granite)
	inlay(-bx, -bx + 0.8, bz0, bz1, C.granite)
	inlay(bx - 0.8, bx, bz0, bz1, C.granite)
	inlay(-bx, bx, bz0, bz0 + 0.8, C.granite)
	inlay(-bx, bx, bz1 - 0.8, bz1, C.granite)
	local medZ = (bz0 + bz1) / 2 + 4
	VC(m, at(0, FY - 0.1, medZ), 0.36, 15, rgb(170, 140, 98), MAT.Marble, false, "Medallion")
	VC(m, at(0, FY - 0.06, medZ), 0.36, 9, C.granite, MAT.Granite, false, "MedallionCore")

	-- 벽: 트래버틴 마감(Neon 덩어리 속으로 0.4 겹침) + 청동 세로 리빌 + 걸레받이
	local wallTop = CY - 0.9
	local wh = wallTop - FY + 0.3
	local wy = (FY - 0.3 + wallTop) / 2
	for _, sx in { -1, 1 } do
		S(m, at(sx * (HX + 0.1), wy, (ZB + gIn - 0.1) / 2), Vector3.new(1.0, wh, gIn - 0.1 - ZB), C.travertine, MAT.Limestone, "WallClad")
		for k = 1, 5 do
			local z = ZB + (gIn - ZB) * k / 6
			D(m, at(sx * (HX - 0.45), wy, z), Vector3.new(0.12, wh, 0.3), C.bronze, MAT.Metal, "Reveal", 0.2)
		end
		D(m, at(sx * (HX - 0.47), FY + 0.25, (ZB + gIn) / 2), Vector3.new(0.16, 0.5, gIn - ZB - 1.2), C.bronze, MAT.Metal, "Skirting")
	end
	for _, sx in { -1, 1 } do
		S(m, at(sx * (HX + AX) / 2, wy, ZB + 0.1), Vector3.new(HX - AX, wh, 1.0), C.travertine, MAT.Limestone, "BackClad")
		D(m, at(sx * (HX + AX) / 2, FY + 0.25, ZB + 0.67), Vector3.new(HX - AX - 1.0, 0.5, 0.16), C.bronze, MAT.Metal, "Skirting")
	end
	S(m, at(0, (AH + wallTop) / 2, ZB + 0.1), Vector3.new(2 * AX, wallTop - AH, 1.0), C.travertine, MAT.Limestone, "BackClad")

	-- 천장(12.6 m): 석고 + 가로 선형 조명 6줄 (3줄은 실제 SurfaceLight)
	D(m, at(0, cyB + 0.3, (ZB + gIn) / 2), Vector3.new(2 * HX, 0.6, gIn - ZB), C.plaster, MAT.Plaster, "Ceiling")
	for k = 0, 5 do
		local z = ZB + 8 + (gIn - ZB - 16) * k / 5
		local s = N(m, at(0, cyB - 0.05, z), Vector3.new(2 * HX - 10, 0.12, 0.8), rgb(255, 238, 212), "CeilingSlot")
		if k % 2 == 1 then
			light(s, "SurfaceLight", { color = rgb(255, 232, 200), brightness = 1.6, range = 52, angle = 120, face = Enum.NormalId.Bottom })
		end
	end

	-- 엘리베이터 알코브: 어두운 화강석 벽, 청동 포털, 낮은 천장(4.2 m) + 조명 3줄
	for _, sx in { -1, 1 } do
		S(m, at(sx * (AX - 0.1), (FY - 0.3 + AH + 0.5) / 2, (AZ0 + ZB) / 2), Vector3.new(1.0, AH + 0.8 - FY, ZB - AZ0), C.granite, MAT.Granite, "AlcoveWall", 0.12)
		D(m, at(sx * (AX - 0.67), FY + 0.25, (AZ0 + ZB) / 2), Vector3.new(0.16, 0.5, ZB - AZ0 - 1.2), C.bronze, MAT.Metal, "Skirting")
		S(m, at(sx * (AX - 0.2), (FY - 0.3 + AH + 1.0) / 2, ZB + 0.2), Vector3.new(1.2, AH + 1.3 - FY, 1.6), C.bronze, MAT.Metal, "PortalJamb", 0.2)
	end
	S(m, at(0, (FY - 0.3 + AH + 0.5) / 2, AZ0 + 0.1), Vector3.new(2 * AX, AH + 0.8 - FY, 1.0), C.granite, MAT.Granite, "AlcoveEnd", 0.12)
	S(m, at(0, AH + 0.4, ZB + 0.2), Vector3.new(2 * AX + 1.2, 1.2, 1.6), C.bronze, MAT.Metal, "PortalLintel", 0.2)
	D(m, at(0, AH + 0.3, (AZ0 + ZB - 0.6) / 2), Vector3.new(2 * AX, 0.6, ZB - 0.6 - AZ0), C.plaster, MAT.Plaster, "AlcoveCeiling")
	local alcLamp: BasePart? = nil
	for _, x in { -6.5, 0, 6.5 } do
		local s = N(m, at(x, AH - 0.05, (AZ0 + ZB) / 2 - 0.5), Vector3.new(0.5, 0.12, ZB - AZ0 - 5), rgb(236, 242, 255), "AlcoveLight")
		alcLamp = alcLamp or s
	end
	if alcLamp then
		light(alcLamp, "PointLight", { color = rgb(236, 240, 255), brightness = 1.2, range = 26 })
	end
	-- 양쪽 엘리베이터 3대씩 + 호출 패널 + 뱅크 표시
	local edw, edh = m2s(1.1), m2s(2.4)
	local doorZ = { AZ0 + 6.5, AZ0 + 16.5, AZ0 + 26.5 }
	for side, sx in { -1, 1 } do
		local wx = sx * (AX - 0.6)
		local yaw = if sx < 0 then FACE_PX else FACE_NX
		for k, z in doorZ do
			elevatorDoor(m, at(wx, FY, z, yaw), edw, edh, if side == 1 then tostring(14 + k * 2) else tostring(40 + k * 3))
			if k < 3 then
				callPanel(m, at(wx, FY, z + 5, yaw))
			end
		end
		sign(m, at(wx + sx * -0.3, FY + edh + 4.4, (doorZ[1] + doorZ[3]) / 2, yaw), Vector3.new(14, 1.5, 0.1), C.black, MAT.SmoothPlastic, if side == 1 then "14–38F  오피스 OFFICE" else "42–71F  레지던스 RESIDENCE", C.textWarm, 30)
	end
	-- 끝벽: 서울스카이 직행 셔틀(넓은 문 1.5 × 2.6 m) + 백라이트 오닉스 패널 + 사인 + 호출 버튼(→ 전망대)
	local sdw, sdh = m2s(1.5), m2s(2.6)
	local endCF = at(0, FY, AZ0 + 0.6, FACE_PZ)
	elevatorDoor(m, endCF, sdw, sdh, "118")
	for _, sx in { -1, 1 } do
		N(m, endCF * CFrame.new(sx * (sdw / 2 + 5.0), 5.6, -0.12), Vector3.new(4.6, 10.4, 0.2), rgb(156, 112, 66), "OnyxPanel")
	end
	sign(m, endCF * CFrame.new(0, sdh + 3.6, -0.12), Vector3.new(16, 2.2, 0.2), C.black, MAT.SmoothPlastic, "서울스카이 전망대 직행  SEOUL SKY SHUTTLE", C.textWarm, 30)
	D(m, endCF * CFrame.new(sdw / 2 + 1.7, 3.8, -0.08), Vector3.new(1.0, 2.4, 0.16), C.steel, MAT.Metal, "ShuttlePanel", 0.25)
	sign(m, endCF * CFrame.new(sdw / 2 + 1.7, 4.65, -0.18), Vector3.new(0.85, 0.42, 0.04), C.black, MAT.SmoothPlastic, "▲ 118F", rgb(150, 214, 255), 60)
	elevatorButton(m, endCF * CFrame.new(sdw / 2 + 1.7, 3.6, -0.2), obsTarget, "서울스카이로 올라가기", "전망대 엘리베이터")

	-- 보안 게이트(스피드 게이트 7대, 차선 1.1 m) + 알코브 입구 유리 칸막이 + 보안 데스크
	local gz0, gz1 = ZB + 2.2, ZB + 7.2
	local nPed = 7
	for k = 0, nPed - 1 do
		local x = -AX + 0.45 + k * (2 * AX - 0.9) / (nPed - 1)
		S(m, at(x, FY + 1.6, (gz0 + gz1) / 2), Vector3.new(0.85, 3.2, gz1 - gz0), C.steel, MAT.Metal, "GatePedestal", 0.2)
		D(m, at(x, FY + 3.27, (gz0 + gz1) / 2), Vector3.new(0.95, 0.14, gz1 - gz0 + 0.1), C.black, MAT.Glass, "GateTop", 0.3)
		N(m, at(x, FY + 3.36, gz1 - 0.8), Vector3.new(0.34, 0.05, 0.5), rgb(80, 230, 140), "GateArrow")
		D(m, at(x, FY + 3.38, gz1 - 2.1), Vector3.new(0.6, 0.08, 0.8), rgb(36, 38, 44), MAT.SmoothPlastic, "CardReader")
		if k > 0 and k < nPed - 1 then
			for _, sx in { -1, 1 } do
				G(m, at(x + sx * 0.5, FY + 2.2, (gz0 + gz1) / 2 + 0.6), Vector3.new(0.08, 1.4, 1.6), rgb(200, 220, 230), 0.55, false, "GateFlap")
			end
		end
	end
	for _, sx in { -1, 1 } do
		G(m, at(sx * (AX - 0.45), FY + 1.8, (ZB + 0.9 + gz0) / 2), Vector3.new(0.3, 3.6, gz0 - ZB - 0.9), C.glass, 0.55, true, "GateBarrier")
	end
	local secX, secZ = -AX - 6, ZB + 8
	S(m, at(secX, FY + 1.75, secZ), Vector3.new(4.5, 3.5, 2.0), C.walnut, MAT.Wood, "SecurityDesk")
	D(m, at(secX, FY + 3.56, secZ), Vector3.new(4.8, 0.12, 2.3), C.marble, MAT.Marble, "SecurityTop")
	D(m, at(secX + 0.8, FY + 4.3, secZ - 0.5) * CFrame.Angles(math.rad(10), 0, 0), Vector3.new(1.6, 1.0, 0.1), C.black, MAT.SmoothPlastic, "Monitor")
	sign(m, at(secX, FY + 2.6, secZ + 1.06, FACE_PZ), Vector3.new(3.2, 0.7, 0.1), C.bronze, MAT.Metal, "보안 SECURITY", C.textWarm, 40)

	-- 미디어 아트 월(뒷벽 알코브 위, 28 × 6 m): 검은 프레임 + 12 × 5 Neon 타일 "한강의 노을"
	local mx0, mx1 = -HX + 7, HX - 7
	local my0, my1 = AH + 5, CY - 5
	S(m, at(0, (my0 + my1) / 2, ZB + 0.8), Vector3.new(mx1 - mx0 + 1.4, my1 - my0 + 1.4, 0.5), C.black, MAT.SmoothPlastic, "MediaWallFrame")
	local cols, rows = 12, 5
	local cw, rh = (mx1 - mx0) / cols, (my1 - my0) / rows
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local u, v = (i + 0.5) / cols, (j + 0.5) / rows
			local t = 0.12 + 0.45 * (1 - v) + 0.32 * (0.5 + 0.5 * math.sin(u * math.pi * 2.3 + v * 2.6)) + rng:NextNumber(-0.05, 0.05)
			local c = artColor(t)
			N(m, at(mx0 + (i + 0.5) * cw, my0 + (j + 0.5) * rh, ZB + 1.15), Vector3.new(cw - 0.25, rh - 0.25, 0.16), Color3.new(c.R * 0.82, c.G * 0.82, c.B * 0.82), "MediaTile")
		end
	end
	local mwLamp = N(m, at(0, my0 - 1.3, ZB + 1.0), Vector3.new(mx1 - mx0, 0.15, 0.3), rgb(160, 120, 255), "MediaUplight")
	light(mwLamp, "PointLight", { color = rgb(170, 120, 255), brightness = 0.9, range = 34 })
	sign(m, at(0, AH + 3.2, ZB + 0.7, FACE_PZ), Vector3.new(26, 2.2, 0.1), C.black, MAT.SmoothPlastic, "엘리베이터  ELEVATORS   ·   서울스카이  SEOUL SKY", C.textWarm, 30)

	-- 안내 데스크(카운터 1.1 m, 작업면 0.75 m) + 백월 사인 + 모니터/의자 + 소품
	local dX, dZ = -HX + 19, ZB + 40
	D(m, at(dX, FY + 0.3, dZ), Vector3.new(19.4, 0.6, 2.2), C.black, MAT.Metal, "DeskPlinth")
	N(m, at(dX, FY + 0.66, dZ + 1.18), Vector3.new(19.2, 0.1, 0.1), C.warmLight, "DeskGlow")
	S(m, at(dX, FY + 0.6 + 1.43, dZ), Vector3.new(20, 2.86, 2.6), C.marble, MAT.Marble, "ReceptionDesk", 0.08)
	S(m, at(dX, FY + 3.56, dZ + 0.2), Vector3.new(20.4, 0.2, 3.0), C.walnut, MAT.Wood, "DeskTop")
	D(m, at(dX, FY + TABLE_H - 0.08, dZ - 2.1), Vector3.new(19, 0.16, 1.8), C.walnut, MAT.Wood, "WorkTop")
	sign(m, at(dX, FY + 2.2, dZ + 1.36, FACE_PZ), Vector3.new(6.5, 1.0, 0.1), C.bronze, MAT.Metal, "안내  INFORMATION", rgb(255, 238, 206), 40)
	for _, ox in { -5, 5 } do
		D(m, at(dX + ox, FY + 3.0, dZ - 1.9), Vector3.new(0.25, 1.0, 0.25), C.black, MAT.Metal, "MonitorStand")
		D(m, at(dX + ox, FY + 3.95, dZ - 1.95) * CFrame.Angles(math.rad(8), 0, 0), Vector3.new(2.0, 1.2, 0.1), C.black, MAT.SmoothPlastic, "Monitor")
		N(m, at(dX + ox, FY + 3.95, dZ - 2.02) * CFrame.Angles(math.rad(8), 0, 0), Vector3.new(1.8, 1.0, 0.04), rgb(70, 110, 160), "Screen")
		local chairCF = at(dX + ox, FY, dZ - 4.6)
		VC(m, chairCF * CFrame.new(0, 0.9, 0), 1.8, 0.3, C.black, MAT.Metal, false, "ChairPost")
		S(m, chairCF * CFrame.new(0, SEAT + 0.6, 0), Vector3.new(1.6, 0.3, 1.6), C.black, MAT.Leather, "OfficeSeat")
		D(m, chairCF * CFrame.new(0, SEAT + 2.0, -0.75), Vector3.new(1.5, 2.2, 0.25), C.black, MAT.Leather, "OfficeBack")
	end
	D(m, at(dX - 7, FY + 4.0, dZ + 0.6), Vector3.new(1.8, 0.75, 1.0), C.bronze, MAT.Metal, "BrochureRack")
	for k = 0, 2 do
		D(m, at(dX - 7.6 + k * 0.6, FY + 4.35, dZ + 0.55) * CFrame.Angles(math.rad(-12), 0, 0), Vector3.new(0.5, 0.75, 0.04), ({ rgb(36, 96, 170), rgb(220, 170, 60), rgb(196, 60, 70) })[k + 1], MAT.SmoothPlastic, "Brochure")
	end
	VC(m, at(dX + 7.5, FY + 4.2, dZ + 0.4), 1.1, 0.7, rgb(230, 230, 236), MAT.Glass, false, "Vase")
	Kit.ellipsoid(m, at(dX + 7.5, FY + 5.2, dZ + 0.4), Vector3.new(1.7, 1.3, 1.7), rgb(220, 226, 236), MAT.Fabric, { name = "Orchids", query = false })
	-- 백월: 호두나무 + 청동 테 + 빛나는 글자
	local bwZ = dZ - 8.5
	S(m, at(dX, FY + 7.5, bwZ), Vector3.new(24, 15, 1.2), C.walnut, MAT.Wood, "BackdropWall")
	D(m, at(dX, FY + 9.8, bwZ + 0.66), Vector3.new(17.2, 5.2, 0.1), C.bronze, MAT.Metal, "BackdropFrame", 0.2)
	sign(m, at(dX, FY + 9.8, bwZ + 0.75, FACE_PZ), Vector3.new(16.4, 4.4, 0.1), rgb(20, 20, 22), MAT.SmoothPlastic, "서울스카이  SEOUL SKY\n안내 · 매표  Information & Tickets", C.textWarm, 30)
	N(m, at(dX, FY + 6.7, bwZ + 0.68), Vector3.new(17.2, 0.12, 0.12), C.warmLight, "BackdropLine")
	local rcLamp = N(m, at(dX, cyB - 0.3, dZ - 1), Vector3.new(4, 0.1, 0.6), C.warmLight, "DeskPendantLine")
	light(rcLamp, "SpotLight", { color = rgb(255, 222, 180), brightness = 2.2, range = 48, angle = 70, face = Enum.NormalId.Bottom })
	-- 무인 발권기 2대 + 대기줄 차단봉
	for k = 0, 1 do
		local kc = at(dX + 13 + k * 3.4, FY, dZ + 5, FACE_PZ)
		S(m, kc * CFrame.new(0, 2.6, 0), Vector3.new(2.2, 5.2, 1.4), rgb(36, 38, 44), MAT.Metal, "Kiosk", 0.15)
		N(m, kc * CFrame.new(0, 3.9, -0.73) * CFrame.Angles(math.rad(10), 0, 0), Vector3.new(1.7, 2.2, 0.05), rgb(96, 150, 220), "KioskScreen")
		sign(m, kc * CFrame.new(0, 5.6, 0), Vector3.new(2.2, 0.7, 1.42), rgb(196, 40, 60), MAT.SmoothPlastic, "발권 TICKET", C.textWhite, 40)
	end
	local sq = {}
	for k = 0, 3 do
		table.insert(sq, at(dX - 8 + k * 5.3, FY, dZ + 7))
	end
	stanchions(m, sq, rgb(150, 24, 36))

	-- 라운지 2조: 러그 + 소파(2.2 m) + 안락의자 2 + 커피 테이블 + 플로어 램프 + 소품
	local lounges = { { HX - 19, ZB + 34 }, { HX - 19, ZB + 58 } }
	for li, lp in lounges do
		local lx, lz = lp[1], lp[2]
		D(m, at(lx, FY + 0.03, lz), Vector3.new(15, 0.06, 13), rgb(150, 138, 120), MAT.Fabric, "Rug")
		local col = if li == 1 then C.fabricSand else C.fabricBlue
		sofa(m, at(lx + 5.4, FY + 0.06, lz, FACE_NX), m2s(2.2), col, rgb(196, 120, 60))
		for _, sz in { -1, 1 } do
			sofa(m, at(lx - 5.0, FY + 0.06, lz + sz * 3.2, FACE_PX), m2s(0.9), C.leather)
		end
		S(m, at(lx, FY + 0.66, lz), Vector3.new(2.6, 1.2, 5.2), C.black, MAT.Metal, "TableBase")
		S(m, at(lx, FY + 1.36, lz), Vector3.new(3.4, 0.2, 6.2), C.marble, MAT.Marble, "TableTop", 0.06)
		VC(m, at(lx - 0.5, FY + 1.71, lz - 1.6), 0.5, 0.42, C.white, MAT.SmoothPlastic, false, "Cup")
		VC(m, at(lx + 0.6, FY + 1.71, lz - 1.1), 0.5, 0.42, C.white, MAT.SmoothPlastic, false, "Cup")
		D(m, at(lx + 0.2, FY + 1.56, lz + 1.4) * CFrame.Angles(0, 0.3, 0), Vector3.new(1.4, 0.2, 1.9), rgb(40, 70, 120), MAT.SmoothPlastic, "Book")
		D(m, at(lx + 0.2, FY + 1.76, lz + 1.4) * CFrame.Angles(0, -0.2, 0), Vector3.new(1.3, 0.2, 1.8), rgb(180, 60, 50), MAT.SmoothPlastic, "Book")
		local lampCF = at(lx + 6.2, FY, lz + 5.2)
		VC(m, lampCF * CFrame.new(0, 0.1, 0), 0.2, 1.4, C.black, MAT.Metal, false, "LampBase")
		VC(m, lampCF * CFrame.new(0, 2.8, 0), 5.4, 0.15, C.black, MAT.Metal, false, "LampPole")
		local shade = VC(m, lampCF * CFrame.new(0, 5.8, 0), 1.3, 1.6, rgb(255, 220, 170), MAT.Neon, false, "LampShade")
		Kit.glow(shade, MAT.Fabric, rgb(236, 226, 206))
		light(shade, "PointLight", { color = rgb(255, 214, 164), brightness = 1.1, range = 18 })
		pottedPlant(m, at(lx - 6.5, FY, lz - 6.5), 5, rgb(70, 66, 62))
	end

	-- 실내 나무 4 그루(7 m, 화강석 화분 Ø 2.4 m) + 그 옆 벤치
	for _, tp in { { -26, ZB + 14 }, { 26, ZB + 14 }, { -14, ZB + 52 }, { 14, ZB + 52 } } do
		treePlanter(m, at(tp[1], FY, tp[2]), m2s(2.4), m2s(0.6), m2s(7), rng, rgb(62, 60, 58), MAT.Granite)
	end
	for _, sx in { -1, 1 } do
		bench(m, at(sx * 26, FY, ZB + 22, FACE_PZ), m2s(2.4), C.leather)
	end

	-- 방풍실(입구 안쪽 3.6 m, 높이 3.3 m): 유리 벽/지붕 + 안쪽 자동문 + 매트, 바깥/안쪽 미닫이문은 열린 상태
	local dxs, DW, DH = Lb.doorXs, Lb.doorW, Lb.doorH
	local VX = math.abs(dxs[2]) + DW / 2 + 4.9
	local VD, VH = m2s(3.6), m2s(3.3)
	local zI = gIn - VD
	for _, sx in { -1, 1 } do
		G(m, at(sx * VX, FY + VH / 2, (gIn + zI) / 2), Vector3.new(0.3, VH, VD), C.glass, 0.6, true, "VestibuleGlass")
		D(m, at(sx * VX, FY + VH / 2, zI), Vector3.new(0.5, VH, 0.5), C.steelDark, MAT.Metal, "VestibulePost")
	end
	G(m, at(0, FY + VH + 0.2, (gIn + zI) / 2), Vector3.new(2 * VX + 0.5, 0.4, VD), rgb(206, 214, 220), 0.35, true, "VestibuleRoof")
	sign(m, at(0, FY + VH + 0.1, zI - 0.05), Vector3.new(2 * VX + 0.5, 1.2, 0.4), C.steelDark, MAT.Metal, "서울스카이  SEOUL SKY   ·   117–123F", C.textWarm, 24)
	local function vPane(x0: number, x1: number, y0: number, y1: number)
		G(m, at((x0 + x1) / 2, (y0 + y1) / 2, zI), Vector3.new(x1 - x0, y1 - y0, 0.3), C.glass, 0.6, true, "VestibuleGlass")
	end
	vPane(-VX, dxs[1] - DW / 2, FY, FY + VH)
	vPane(dxs[1] + DW / 2, dxs[2] - DW / 2, FY, FY + VH)
	vPane(dxs[2] + DW / 2, VX, FY, FY + VH)
	for _, dx in dxs do
		vPane(dx - DW / 2, dx + DW / 2, FY + DH + 0.7, FY + VH)
		D(m, at(dx, FY + DH + 0.35, zI), Vector3.new(DW + 0.5, 0.7, 0.9), C.steelDark, MAT.Metal, "DoorOperator")
		-- 열린 미닫이 두 짝(바깥: 멀리언 안쪽 / 안쪽: 방풍실 안쪽) — 유리 + 바닥 레일 + 손잡이 스타일
		for _, zl in { Lb.W - 1.65, zI + 0.6 } do
			for _, sx in { -1, 1 } do
				local lx = dx + sx * (DW / 2 + 2.1 - 0.25)
				G(m, at(lx, FY + DH / 2, zl), Vector3.new(4.2, DH - 0.1, 0.22), C.glass, 0.62, false, "DoorLeaf")
				D(m, at(lx, FY + 0.22, zl), Vector3.new(4.2, 0.36, 0.3), C.steelDark, MAT.Metal, "LeafRail")
				D(m, at(lx - sx * 2.0, FY + DH / 2, zl), Vector3.new(0.22, DH - 0.1, 0.32), C.steelDark, MAT.Metal, "LeafStile")
			end
		end
	end
	D(m, at(0, FY + 0.04, (gIn + zI) / 2), Vector3.new(2 * VX - 0.6, 0.08, VD - 0.4), rgb(46, 44, 42), MAT.Fabric, "EntranceMat")
	-- 미끄럼 주의 A형 표지
	local wet = at(VX + 4, FY, zI - 3, FACE_PZ)
	for _, sz in { -1, 1 } do
		D(m, wet * CFrame.new(0, 1.55, sz * 0.32) * CFrame.Angles(-sz * math.rad(10), 0, 0), Vector3.new(1.7, 3.1, 0.1), rgb(250, 200, 30), MAT.SmoothPlastic, "WetFloorSign")
	end
	sign(m, wet * CFrame.new(0, 1.55, -0.32) * CFrame.Angles(math.rad(10), 0, 0) * CFrame.new(0, 0.45, -0.08), Vector3.new(1.5, 1.0, 0.04), rgb(250, 200, 30), MAT.SmoothPlastic, "미끄럼 주의\nCAUTION", rgb(30, 30, 30), 50)

	-- 안내 사인: 행잉 사인(입구 쪽을 봄), 토템, 층별 안내, 환영 디지털 사이니지
	local hz = ZB + 19
	local hs = sign(m, at(0, FY + 17, hz, FACE_PZ), Vector3.new(26, 3.4, 0.4), rgb(28, 30, 34), MAT.Metal, "서울스카이 전망대  SEOUL SKY  ↑\n엘리베이터  Elevators  ↑", C.textWarm, 24)
	Kit.label(hs, BACK, "출구  EXIT  ↑", { color = C.textWhite, glow = true, pixelsPerStud = 24, maxDistance = 500 })
	for _, sx in { -1, 1 } do
		D(m, at(sx * 11, (FY + 18.7 + cyB) / 2, hz), Vector3.new(0.15, cyB - FY - 18.7, 0.15), C.steelDark, MAT.Metal, "SignRod")
	end
	local totem = at(-VX - 6, FY, zI - 4, FACE_PZ)
	S(m, totem * CFrame.new(0, 3.65, 0), Vector3.new(2.2, 7.3, 0.9), rgb(34, 36, 40), MAT.Metal, "Totem", 0.15)
	N(m, totem * CFrame.new(0, 3.65, -0.48), Vector3.new(0.12, 7.0, 0.08), C.warmLight, "TotemEdge")
	sign(m, totem * CFrame.new(0, 4.6, -0.47), Vector3.new(2.0, 4.6, 0.04), rgb(34, 36, 40), MAT.SmoothPlastic, "서울스카이\n전망대\nSEOUL\nSKY\n117–123F\n↑", C.textWarm, 40)
	sign(m, at(HX - 0.5, FY + 9, ZB + 24, FACE_NX), Vector3.new(11, 9, 0.12), rgb(30, 30, 34), MAT.SmoothPlastic, "층별 안내  DIRECTORY\n117–123F  서울스카이 SEOUL SKY\n76–101F  호텔 HOTEL\n42–71F  레지던스 RESIDENCE\n14–38F  오피스 OFFICE\nB1–B2  쇼핑몰 MALL", C.textWarm, 30)
	local ds = at(VX + 3, FY, zI - 7, FACE_PZ)
	D(m, ds * CFrame.new(0, 0.1, 0), Vector3.new(2.4, 0.2, 1.6), C.steelDark, MAT.Metal, "SignageFoot")
	D(m, ds * CFrame.new(0, 3.8, 0.1), Vector3.new(2.6, 6.0, 0.5), C.black, MAT.Metal, "SignageBody")
	sign(m, ds * CFrame.new(0, 3.9, -0.17), Vector3.new(2.3, 5.6, 0.04), rgb(22, 30, 56), MAT.Neon, "환영합니다\nWELCOME\n\n서울스카이\n오늘의 일몰\n17:31", rgb(255, 240, 220), 40)
	for _, sx in { -1, 1 } do
		VC(m, at(sx * (VX + 1.6), FY + 1.5, zI - 1.5), 3.0, 1.4, C.steel, MAT.Metal, true, "Bin")
	end
end

------------------------------------------------------------------------------------------------------
-- 2) 서울스카이 전망대 (118F 전망 홀 + 123F 스카이 라운지)
------------------------------------------------------------------------------------------------------
local function optsFn(name: string, mat: Enum.Material, refl: number?, collide: boolean): (Color3, boolean) -> PartOpts
	return function(c: Color3, cyl: boolean): PartOpts
		return { name = name, shape = if cyl then "Cylinder" else "Block", material = mat, color = c, reflectance = refl, collide = collide, query = collide, shadow = false }
	end
end

local CORE_H = m2s(5.4) -- 전망대 코어 반폭(엘리베이터/계단 코어 10.8 m)
local SHUTTLE_W, SHUTTLE_H = m2s(1.5), m2s(2.6)

local MENUS = {
	"COFFEE  커피\n아메리카노 Americano  6.0\n카페라떼 Café Latte  6.5\n바닐라라떼 Vanilla Latte  7.0\n콜드브루 Cold Brew  6.5",
	"SKY SPECIAL\n서울스카이 라떼  8.0\n한강 노을 에이드  8.5\n117 블렌드 티  7.0\n구름 솜사탕  5.0",
	"DESSERT  디저트\n크루아상 Croissant  4.5\n치즈케이크 Cheesecake  7.5\n마카롱 Macaron  3.0\n젤라토 Gelato  5.5",
}
local PRODUCT_C = { rgb(196, 60, 70), rgb(40, 96, 170), rgb(236, 190, 70), rgb(70, 150, 110), rgb(236, 236, 230), rgb(150, 90, 170), rgb(236, 140, 90), rgb(60, 60, 66) }

local function buildObservatory(m: Model, gm: Model, TF: CFrame, Ob: any, lobbyT: Vector3, obsT: Vector3, loungeT: Vector3, rng: Random)
	local CH = CORE_H
	local gT, cr = Ob.glassT, Ob.cornerR
	local FY1, FY2 = Ob.yA + 0.15, Ob.yB + 0.15
	local function at(x: number, y: number, z: number, yaw: number?): CFrame
		return TF * CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0)
	end
	-- 층 둘레(유리 모서리 원과 같은 중심의 둥근 정사각 판)
	local function ringOf(gw: number): (number, number, number, number)
		local gIn = gw / 2 - gT
		local o = gw / 2 - gw * cr
		local fw = 2 * (gIn - 0.1)
		return gIn, o, fw, fw / 2 - o
	end
	local gIn1, o1, fw1, fr1 = ringOf(Ob.gw1)
	local gIn2, o2, fw2, fr2 = ringOf(Ob.gw2)
	local cove = rgb(255, 232, 200)

	-- ── 밖에서 보이는 밝은 띠의 내용(Persistent): 바닥, 천장 + 빛 띠, 코어 ─────────────────────────────
	Landmark.rsquareCut(gm, TF * CFrame.new(0, Ob.yA - 0.1, 0), fw1, 0.5, fr1, Ob.pit, C.floorDark, optsFn("ObsFloor", MAT.Marble, 0.14, true))
	Landmark.rsquare(gm, TF * CFrame.new(0, Ob.yB - 0.1, 0), fw2, 0.5, fr2, C.oak, C.oak, C.oak, optsFn("LoungeFloor", MAT.WoodPlanks, nil, true))
	Landmark.rsquare(gm, TF * CFrame.new(0, Ob.yA1 - 0.6, 0), fw1, 0.6, fr1, C.plaster, C.plaster, C.plaster, optsFn("ObsCeiling", MAT.Plaster, nil, false))
	Landmark.rsquare(gm, TF * CFrame.new(0, Ob.yB1 - 0.6, 0), fw2, 0.6, fr2, C.plaster, C.plaster, C.plaster, optsFn("LoungeCeiling", MAT.Plaster, nil, false))
	for lv = 1, 2 do
		local yc = (if lv == 1 then Ob.yA1 else Ob.yB1) - 0.95
		local gIn, o = (if lv == 1 then gIn1 else gIn2), (if lv == 1 then o1 else o2)
		local inner = CH + 5
		for f = 0, 3 do
			local FR = TF * CFrame.Angles(0, f * math.pi / 2, 0)
			local s = N(gm, FR * CFrame.new(0, yc, gIn - 6), Vector3.new(2 * o - 2, 0.12, 0.9), cove, "CeilingCove")
			N(gm, FR * CFrame.new(0, yc, inner), Vector3.new(2 * inner + 0.9, 0.12, 0.9), cove, "CeilingCove")
			if lv == 1 or f ~= 3 then
				light(s, "PointLight", { color = rgb(255, 224, 186), brightness = if lv == 1 then 1.3 else 1.0, range = if lv == 1 then 44 else 34 })
			end
		end
		local fy = if lv == 1 then FY1 else FY2
		local top = if lv == 1 then Ob.yA1 else Ob.yB1
		S(gm, at(0, (fy - 0.2 + top + 0.3) / 2, 0), Vector3.new(2 * CH, top + 0.5 - fy, 2 * CH), C.walnut, MAT.Wood, "Core")
		D(m, at(0, fy + 0.25, 0), Vector3.new(2 * CH + 0.3, 0.5, 2 * CH + 0.3), C.bronze, MAT.Metal, "CoreSkirting")
		for _, s in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			D(m, at(s[1] * CH, (fy + top) / 2, s[2] * CH), Vector3.new(0.7, top - fy, 0.7), C.bronze, MAT.Metal, "CoreTrim", 0.2)
		end
	end

	-- ── 118F: 엘리베이터(코어 -Z 면, 도착 지점 앞) + 반환/라운지 버튼 + 큰 사인 ───────────────────────
	local eF = at(0, FY1, -CH, FACE_NZ)
	for _, x in { -7.5, 7.5 } do
		elevatorDoor(m, eF * CFrame.new(x, 0, 0), SHUTTLE_W, SHUTTLE_H, "118")
	end
	D(m, eF * CFrame.new(0, 3.8, -0.08), Vector3.new(1.1, 2.4, 0.16), C.steel, MAT.Metal, "CallPanel", 0.25)
	sign(m, eF * CFrame.new(0, 4.7, -0.18), Vector3.new(0.95, 0.42, 0.04), C.black, MAT.SmoothPlastic, "▼ 1F", rgb(150, 214, 255), 60)
	elevatorButton(m, eF * CFrame.new(0, 3.6, -0.2), lobbyT, "1층으로 내려가기", "전망대 엘리베이터")
	D(m, eF * CFrame.new(14, 3.8, -0.08), Vector3.new(1.1, 2.4, 0.16), C.steel, MAT.Metal, "CallPanel", 0.25)
	sign(m, eF * CFrame.new(14, 4.7, -0.18), Vector3.new(0.95, 0.42, 0.04), C.black, MAT.SmoothPlastic, "▲ 123F", rgb(150, 214, 255), 60)
	elevatorButton(m, eF * CFrame.new(14, 3.6, -0.2), loungeT, "123층 라운지로 올라가기", "스카이 라운지 엘리베이터")
	sign(m, eF * CFrame.new(0, 14.5, -0.12), Vector3.new(28, 3.4, 0.2), rgb(18, 18, 22), MAT.SmoothPlastic, "서울스카이  SEOUL SKY   118F", C.textWarm, 24)
	N(m, eF * CFrame.new(0, 12.6, -0.14), Vector3.new(28, 0.14, 0.1), C.warmLight, "SignLine")
	sign(m, eF * CFrame.new(-14, 5.5, -0.12), Vector3.new(5.5, 4.5, 0.1), rgb(24, 26, 32), MAT.SmoothPlastic, "스카이데크 SKY DECK ↑\n(코어 건너편)\n\n카페 CAFÉ →\n기념품 GIFT SHOP ←", C.textWarm, 36)

	-- ── 스카이데크: 강 쪽(+Z) 유리 바닥 7.2 × 3.6 m, 아래는 무한 거울 + "500 m 아래 야경" ───────────────
	local px0, px1, pz0, pz1 = Ob.pit[1], Ob.pit[2], Ob.pit[3], Ob.pit[4]
	local pb = Ob.y0 + 0.8
	local pw, pd = px1 - px0, pz1 - pz0
	local pcx, pcz = (px0 + px1) / 2, (pz0 + pz1) / 2
	local wallH, wy = Ob.yA - pb, (pb + Ob.yA) / 2
	local MIR = rgb(16, 18, 26)
	D(m, at(px0 + 0.2, wy, pcz), Vector3.new(0.4, wallH, pd), MIR, MAT.Glass, "PitMirror", 0.5)
	D(m, at(px1 - 0.2, wy, pcz), Vector3.new(0.4, wallH, pd), MIR, MAT.Glass, "PitMirror", 0.5)
	D(m, at(pcx, wy, pz0 + 0.2), Vector3.new(pw - 0.8, wallH, 0.4), MIR, MAT.Glass, "PitMirror", 0.5)
	D(m, at(pcx, wy, pz1 - 0.2), Vector3.new(pw - 0.8, wallH, 0.4), MIR, MAT.Glass, "PitMirror", 0.5)
	D(m, at(pcx, pb - 0.25, pcz), Vector3.new(pw, 0.5, pd), rgb(8, 10, 16), MAT.SmoothPlastic, "PitFloor")
	N(m, at(pcx, pb + 0.03, pz0 + pd * 0.32), Vector3.new(pw - 0.8, 0.06, pd * 0.22), rgb(18, 34, 72), "PitRiver")
	N(m, at(pcx + pw * 0.2, pb + 0.15, pcz), Vector3.new(0.2, 0.04, pd - 0.8), rgb(255, 200, 120), "PitBridge")
	for _, zz in { 0.62, 0.84 } do
		N(m, at(pcx, pb + 0.08, pz0 + pd * zz), Vector3.new(pw - 0.8, 0.04, 0.12), rgb(230, 150, 70), "PitRoad")
	end
	N(m, at(pcx - pw * 0.28, pb + 0.08, pz0 + pd * 0.73), Vector3.new(0.12, 0.04, pd * 0.48), rgb(230, 150, 70), "PitRoad")
	for _ = 1, 30 do
		local zz = rng:NextNumber(0.5, 0.97)
		local sz = rng:NextNumber(0.18, 0.5)
		local c = if rng:NextNumber() < 0.7 then rgb(255, 210, 150) else rgb(210, 226, 255)
		N(m, at(px0 + rng:NextNumber(0.7, pw - 0.7), pb + 0.12, pz0 + pd * zz), Vector3.new(sz, 0.04, sz * rng:NextNumber(0.8, 1.6)), c, "PitCityLight")
	end
	for k, dpt in { 1.2, 2.6, 4.0 } do
		local y = FY1 - dpt
		if y > pb + 0.5 then
			local c = rgb(160, 210, 255):Lerp(rgb(20, 34, 64), (k - 1) / 3)
			N(m, at(px0 + 0.45, y, pcz), Vector3.new(0.1, 0.12, pd - 0.9), c, "PitFrame")
			N(m, at(px1 - 0.45, y, pcz), Vector3.new(0.1, 0.12, pd - 0.9), c, "PitFrame")
			N(m, at(pcx, y, pz0 + 0.45), Vector3.new(pw - 0.9, 0.12, 0.1), c, "PitFrame")
			N(m, at(pcx, y, pz1 - 0.45), Vector3.new(pw - 0.9, 0.12, 0.1), c, "PitFrame")
		end
	end
	G(m, at(pcx, Ob.yA - 0.05, pcz), Vector3.new(pw + 0.4, 0.48, pd + 0.4), rgb(206, 228, 240), 0.84, true, "SkyDeckGlass")
	local fy = FY1 + 0.09
	D(m, at(px0 - 0.05, fy, pcz), Vector3.new(0.6, 0.12, pd + 1.0), C.steel, MAT.Metal, "SkyDeckFrame", 0.3)
	D(m, at(px1 + 0.05, fy, pcz), Vector3.new(0.6, 0.12, pd + 1.0), C.steel, MAT.Metal, "SkyDeckFrame", 0.3)
	D(m, at(pcx, fy, pz0 - 0.05), Vector3.new(pw + 1.0, 0.12, 0.6), C.steel, MAT.Metal, "SkyDeckFrame", 0.3)
	D(m, at(pcx, fy, pz1 + 0.05), Vector3.new(pw + 1.0, 0.12, 0.6), C.steel, MAT.Metal, "SkyDeckFrame", 0.3)
	D(m, at(pcx, FY1 + 0.09, pcz), Vector3.new(0.4, 0.1, pd), C.steel, MAT.Metal, "SkyDeckFrame", 0.3)
	local lec = at(px1 + 3.2, FY1, pz0 - 1.6, FACE_NZ)
	D(m, lec * CFrame.new(0, 1.5, 0), Vector3.new(0.4, 3.0, 0.4), C.steelDark, MAT.Metal, "LecternPost")
	sign(m, lec * CFrame.new(0, 3.2, 0) * CFrame.Angles(math.rad(35), 0, 0), Vector3.new(3.6, 2.0, 0.12), rgb(24, 26, 32), MAT.Metal, string.format("SKY DECK  스카이데크\n지상 %d m\n유리 바닥 위를 걸어 보세요", math.floor(Ob.yA * Config.METERS_PER_STUD + 0.5)), C.textWarm, 50)

	-- ── 창가: 망원경 5, 파노라마 벤치 6, 전망 안내판 ───────────────────────────────────────────────
	for _, x in { -22, 22 } do
		telescope(m, at(x, FY1, gIn1 - 4.5, FACE_PZ))
	end
	for _, x in { -26, 26 } do
		telescope(m, at(x, FY1, -gIn1 + 4.5, FACE_NZ))
	end
	telescope(m, at(-gIn1 + 4.5, FY1, 30, FACE_NX))
	telescope(m, at(gIn1 - 4.5, FY1, -30, FACE_PX))
	for _, x in { -34, 34 } do
		bench(m, at(x, FY1, gIn1 - 10, FACE_PZ), m2s(2.4), C.leather)
	end
	for _, x in { -34, 34 } do
		bench(m, at(x, FY1, -gIn1 + 10, FACE_NZ), m2s(2.4), C.leather)
	end
	bench(m, at(gIn1 - 10, FY1, 30, FACE_PX), m2s(2.4), C.leather)
	bench(m, at(-gIn1 + 10, FY1, -32, FACE_NX), m2s(2.4), C.leather)
	bench(m, at(0, FY1, CH + 7, FACE_PZ), m2s(3.0), C.leather)
	local function plaque(cf: CFrame, text: string)
		D(m, cf * CFrame.new(0, 1.3, 0), Vector3.new(0.3, 2.6, 0.3), C.steelDark, MAT.Metal, "PlaquePost")
		sign(m, cf * CFrame.new(0, 2.9, 0) * CFrame.Angles(math.rad(35), 0, 0), Vector3.new(3.6, 1.7, 0.12), rgb(28, 30, 36), MAT.Metal, text, C.textWarm, 50)
	end
	plaque(at(-30, FY1, gIn1 - 2.2, FACE_NZ), "잠실대교  JAMSIL BRIDGE\n↑ 1.3 km")
	plaque(at(30, FY1, gIn1 - 2.2, FACE_NZ), "한강공원  HANGANG PARK\n↑ 강 건너")
	plaque(at(0, FY1, -gIn1 + 2.2, FACE_PZ), "잠실 시가지  JAMSIL CITY\n↑")
	plaque(at(-gIn1 + 2.2, FY1, 0 + 40, FACE_PX), "노을  SUNSET\n← 서쪽 WEST")
	-- 코어 +Z 면: 그래픽 월 + 높이 막대
	local zF = at(0, FY1, CH, FACE_PZ)
	sign(m, zF * CFrame.new(0, 10, -0.12), Vector3.new(24, 6.5, 0.2), rgb(16, 18, 26), MAT.SmoothPlastic, "SEOUL SKY\n서울스카이  117F – 123F", C.textWarm, 24)
	N(m, zF * CFrame.new(0, 6.4, -0.14), Vector3.new(24, 0.14, 0.1), C.warmLight, "GraphicLine")
	N(m, zF * CFrame.new(-14.5, 8.2, -0.14), Vector3.new(0.18, 14, 0.1), rgb(150, 214, 255), "HeightBar")
	for k, t in { "500 m", "300 m", "100 m" } do
		sign(m, zF * CFrame.new(-16.3, 14.6 - (k - 1) * 5.2, -0.13), Vector3.new(3.2, 0.9, 0.06), rgb(16, 18, 26), MAT.SmoothPlastic, t, rgb(150, 214, 255), 50)
	end

	-- ── 카페(코어 -X 면): 뒤 카운터 + 앞 카운터 + 쇼케이스 + 메뉴판 3 + 펜던트 + 테이블 4 ──────────────
	local cX = -CH
	S(m, at(cX - 1.1, FY1 + COUNTER / 2, 0), Vector3.new(2.2, COUNTER, 26), C.walnut, MAT.Wood, "BackCounter")
	D(m, at(cX - 1.15, FY1 + COUNTER + 0.06, 0), Vector3.new(2.4, 0.12, 26.2), C.marble, MAT.Marble, "BackTop", 0.05)
	D(m, at(cX - 1.2, FY1 + COUNTER + 0.92, -6), Vector3.new(1.6, 1.6, 2.8), C.steel, MAT.Metal, "Espresso", 0.3)
	N(m, at(cX - 2.02, FY1 + COUNTER + 1.4, -6), Vector3.new(0.05, 0.25, 1.6), rgb(120, 200, 255), "EspressoLed")
	VC(m, at(cX - 1.1, FY1 + COUNTER + 0.8, -2), 1.5, 0.8, C.black, MAT.Metal, false, "Grinder")
	for k = 0, 3 do
		VC(m, at(cX - 1.1, FY1 + COUNTER + 0.3 + k * 0.42, 2.5), 0.4, 0.55, C.white, MAT.SmoothPlastic, false, "CupStack")
	end
	for k = 0, 3 do
		VC(m, at(cX - 1.2, FY1 + COUNTER + 0.6, 6 + k * 0.7), 1.1, 0.4, ({ rgb(150, 70, 40), rgb(220, 180, 90), rgb(110, 40, 50), rgb(230, 220, 200) })[k + 1], MAT.Glass, false, "Syrup")
	end
	S(m, at(cX - 6.4, FY1 + 1.45, 0), Vector3.new(2.4, 2.9, 22), C.oak, MAT.Wood, "CafeCounter")
	D(m, at(cX - 6.5, FY1 + COUNTER + 0.08, 0), Vector3.new(2.9, 0.16, 22.4), C.white, MAT.Marble, "CafeTop", 0.05)
	G(m, at(cX - 6.4, FY1 + COUNTER + 0.92, 5.5), Vector3.new(2.2, 1.6, 8), rgb(220, 232, 240), 0.55, false, "PastryCase")
	N(m, at(cX - 6.4, FY1 + COUNTER + 0.25, 5.5), Vector3.new(2.0, 0.08, 7.8), rgb(255, 236, 200), "CaseShelf")
	for k = 0, 3 do
		Kit.ellipsoid(m, at(cX - 6.4, FY1 + COUNTER + 0.55, 2.6 + k * 1.9), Vector3.new(1.0, 0.55, 1.4), rgb(206, 146, 72):Lerp(rgb(240, 220, 200), (k % 2) * 0.5), MAT.SmoothPlastic, { name = "Pastry", query = false })
	end
	D(m, at(cX - 6.4, FY1 + COUNTER + 0.55, -5), Vector3.new(1.2, 0.8, 1.4), C.black, MAT.SmoothPlastic, "Register")
	N(m, at(cX - 7.08, FY1 + COUNTER + 0.95, -5) * CFrame.Angles(0, 0, math.rad(-15)), Vector3.new(0.05, 0.6, 1.1), rgb(90, 140, 200), "RegisterScreen")
	for k, txt in MENUS do
		sign(m, at(cX - 0.12, FY1 + 8.6, (k - 2) * 8.4, FACE_NX), Vector3.new(7.6, 4.8, 0.2), C.black, MAT.SmoothPlastic, txt, C.textWarm, 30)
	end
	sign(m, at(cX - 0.12, FY1 + 12.8, 0, FACE_NX), Vector3.new(16, 2.2, 0.2), C.walnut, MAT.Wood, "SKY CAFÉ  스카이 카페", C.textWarm, 30)
	local pendantTop = Ob.yA1 - 0.9
	for k, z in { -7, 0, 7 } do
		D(m, at(cX - 6.4, (FY1 + 8.6 + pendantTop) / 2, z), Vector3.new(0.06, pendantTop - FY1 - 8.6, 0.06), C.black, MAT.Metal, "PendantCord")
		local pend = Kit.ball(m, (at(cX - 6.4, FY1 + 8.1, z)).Position, 1.3, rgb(255, 214, 160), MAT.Neon, { name = "Pendant", collide = false, query = false, shadow = false, glow = true, dayMaterial = MAT.Glass, dayColor = rgb(236, 228, 214) })
		if k == 2 then
			light(pend, "PointLight", { color = rgb(255, 212, 160), brightness = 1.2, range = 24 })
		end
	end
	for _, tx in { -46, -36 } do
		for _, tz in { -10, 9 } do
			roundTable(m, at(tx, FY1, tz), m2s(0.7), TABLE_H, C.marble, MAT.Marble)
			chair(m, at(tx, FY1, tz - 2.6, FACE_PZ), C.oak)
			chair(m, at(tx, FY1, tz + 2.6, FACE_NZ), C.oak)
			VC(m, at(tx + 0.4, FY1 + TABLE_H + 0.25, tz - 0.3), 0.5, 0.42, C.white, MAT.SmoothPlastic, false, "Cup")
		end
	end
	pottedPlant(m, at(cX - 4, FY1, 15), 5, rgb(70, 66, 62))
	pottedPlant(m, at(cX - 4, FY1, -15), 5, rgb(70, 66, 62))

	-- ── 기념품숍(코어 +X 면): 벽 선반 3 + 진열 테이블 2 + 계산대 + 사인 ─────────────────────────────
	local gX = CH
	D(m, at(gX + 13, FY1 + 0.04, 0), Vector3.new(24, 0.08, 36), C.oak, MAT.WoodPlanks, "ShopFloor")
	local shelfLamp: BasePart? = nil
	for _, z in { -11.5, 0, 11.5 } do
		S(m, at(gX + 0.9, FY1 + 4.5, z), Vector3.new(1.8, 9, 10.6), C.white, MAT.Wood, "WallShelf")
		for r = 0, 3 do
			for h = -1, 1, 2 do
				D(m, at(gX + 1.97, FY1 + 1.3 + r * 2.0, z + h * 2.5), Vector3.new(0.3, rng:NextNumber(0.9, 1.4), 4.6), PRODUCT_C[rng:NextInteger(1, #PRODUCT_C)], MAT.SmoothPlastic, "Products")
			end
		end
		local sl = N(m, at(gX + 1.88, FY1 + 8.7, z), Vector3.new(0.12, 0.12, 10), C.warmLight, "ShelfLight")
		shelfLamp = shelfLamp or sl
	end
	if shelfLamp then
		light(shelfLamp, "PointLight", { color = rgb(255, 232, 200), brightness = 1.0, range = 22 })
	end
	for _, tz in { -8, 8 } do
		local tcf = at(gX + 12, FY1, tz)
		S(m, tcf * CFrame.new(0, 1.4, 0), Vector3.new(4.5, 2.8, 6.5), C.white, MAT.Wood, "DisplayTable")
		for k = 0, 2 do
			local mc = tcf * CFrame.new(-1.3 + k * 1.3, 2.8, -1.8)
			D(m, mc * CFrame.new(0, 0.8, 0), Vector3.new(0.55, 1.6, 0.55), rgb(176, 190, 206), MAT.Glass, "MiniTower", 0.2)
			D(m, mc * CFrame.new(0, 1.95, 0), Vector3.new(0.32, 0.7, 0.32), rgb(220, 196, 150), MAT.Metal, "MiniTowerTop", 0.2)
		end
		for k = 0, 1 do
			Kit.ball(m, (tcf * CFrame.new(-0.8 + k * 1.6, 3.45, 1.0)).Position, 1.3, ({ rgb(240, 200, 120), rgb(150, 200, 236) })[k + 1], MAT.Fabric, { name = "Plush", collide = false, query = false })
		end
		D(m, tcf * CFrame.new(1.4, 3.1, 2.2), Vector3.new(1.2, 0.6, 1.2), rgb(196, 40, 60), MAT.SmoothPlastic, "GiftBox")
	end
	S(m, at(gX + 21, FY1 + 1.6, -15), Vector3.new(2.6, 3.2, 6), C.walnut, MAT.Wood, "GiftCounter")
	D(m, at(gX + 20.8, FY1 + 3.6, -16), Vector3.new(1.0, 0.8, 1.2), C.black, MAT.SmoothPlastic, "Register")
	sign(m, at(gX + 0.2, FY1 + 11, 0, FACE_PX), Vector3.new(14, 2.2, 0.2), C.white, MAT.Wood, "기념품  GIFT SHOP", rgb(170, 40, 50), 30)

	-- ── 123F 스카이 라운지: 엘리베이터 + 바 + 창가 라운지 의자 6조 ──────────────────────────────────
	local eF2 = at(0, FY2, -CH, FACE_NZ)
	elevatorDoor(m, eF2 * CFrame.new(-8, 0, 0), SHUTTLE_W, SHUTTLE_H, "123")
	D(m, eF2 * CFrame.new(2, 3.8, -0.08), Vector3.new(1.1, 2.4, 0.16), C.steel, MAT.Metal, "CallPanel", 0.25)
	sign(m, eF2 * CFrame.new(2, 4.7, -0.18), Vector3.new(0.95, 0.42, 0.04), C.black, MAT.SmoothPlastic, "▼ 118F", rgb(150, 214, 255), 60)
	elevatorButton(m, eF2 * CFrame.new(2, 3.6, -0.2), obsT, "118층 전망대로 내려가기", "스카이 라운지 엘리베이터")
	D(m, eF2 * CFrame.new(12, 3.8, -0.08), Vector3.new(1.1, 2.4, 0.16), C.steel, MAT.Metal, "CallPanel", 0.25)
	sign(m, eF2 * CFrame.new(12, 4.7, -0.18), Vector3.new(0.95, 0.42, 0.04), C.black, MAT.SmoothPlastic, "▼ 1F", rgb(150, 214, 255), 60)
	elevatorButton(m, eF2 * CFrame.new(12, 3.6, -0.2), lobbyT, "1층으로 내려가기", "전망대 엘리베이터")
	sign(m, at(0, FY2 + 11, CH + 0.12, FACE_PZ), Vector3.new(22, 3.4, 0.2), rgb(16, 18, 26), MAT.SmoothPlastic, "SKY LOUNGE 123  스카이 라운지", C.textWarm, 24)
	-- 바(코어 -X 면): 백바(빛나는 선반 + 병) + 바 카운터 1.05 m + 스툴 5
	S(m, at(cX - 1.0, FY2 + 1.5, 0), Vector3.new(2.0, 3.0, 24), C.walnut, MAT.Wood, "BackBar")
	for r = 0, 1 do
		N(m, at(cX - 0.5, FY2 + 5.2 + r * 2.4, 0), Vector3.new(0.8, 0.1, 22), rgb(255, 190, 110), "BackBarShelf")
		for k = 0, 9 do
			VC(m, at(cX - 0.55, FY2 + 6.05 + r * 2.4, -9.9 + k * 2.2), 1.6, 0.42, ({ rgb(150, 90, 40), rgb(60, 110, 70), rgb(200, 200, 210), rgb(120, 40, 50) })[(k + r) % 4 + 1], MAT.Glass, false, "Bottle")
		end
	end
	S(m, at(cX - 6.4, FY2 + 1.75, 0), Vector3.new(2.4, 3.5, 20), rgb(30, 30, 34), MAT.Marble, "BarCounter", 0.1)
	D(m, at(cX - 6.6, FY2 + 3.58, 0), Vector3.new(3.0, 0.16, 20.4), C.walnut, MAT.Wood, "BarTop")
	N(m, at(cX - 7.65, FY2 + 0.5, 0), Vector3.new(0.1, 0.1, 19.6), rgb(255, 190, 110), "BarGlow")
	D(m, at(cX - 8.0, FY2 + 0.9, 0), Vector3.new(0.18, 0.18, 19.6), C.bronze, MAT.Metal, "FootRail", 0.3)
	for k = -2, 2 do
		local sc = at(cX - 9.6, FY2, k * 4)
		VC(m, sc * CFrame.new(0, 1.25, 0), 2.5, 0.3, C.bronze, MAT.Metal, true, "StoolPost")
		VC(m, sc * CFrame.new(0, 2.55, 0), 0.3, 1.5, C.leather, MAT.Leather, true, "StoolSeat")
	end
	-- 창가 라운지 세트(안락의자 2 + 낮은 원탁 + 촛불)
	local sets = {
		{ -20, gIn2 - 8, FACE_PZ },
		{ 20, gIn2 - 8, FACE_PZ },
		{ gIn2 - 8, -14, FACE_PX },
		{ gIn2 - 8, 16, FACE_PX },
		{ -24, -gIn2 + 8, FACE_NZ },
		{ 26, -gIn2 + 8, FACE_NZ },
	}
	for i, st in sets do
		local cf = at(st[1], FY2, st[2], st[3])
		local col = if i % 2 == 0 then C.fabricBlue else C.fabricSand
		for _, sx in { -1, 1 } do
			sofa(m, cf * CFrame.new(sx * 2.4, 0, 0), m2s(0.85), col)
		end
		roundTable(m, cf * CFrame.new(0, 0, -3.0), 2.2, 1.6, C.marble, MAT.Marble)
		N(m, cf * CFrame.new(0, 1.85, -3.0), Vector3.new(0.3, 0.4, 0.3), rgb(255, 196, 120), "Candle")
	end
	pottedPlant(m, at(16, FY2, CH + 5), 6, rgb(60, 58, 56))
	pottedPlant(m, at(-16, FY2, CH + 5), 6, rgb(60, 58, 56))
end

------------------------------------------------------------------------------------------------------
-- 3) 몰 아트리움 (파란 곡면 지붕 홀 속)
------------------------------------------------------------------------------------------------------
type ShopSpec = { ko: string, en: string, kind: string }
type KindStyle = { wall: Color3, wallMat: Enum.Material, floor: Color3, floorMat: Enum.Material, fascia: Color3, text: Color3, lamp: Color3 }

local KIND: { [string]: KindStyle } = {
	cafe = { wall = rgb(92, 66, 46), wallMat = MAT.Wood, floor = rgb(150, 110, 74), floorMat = MAT.WoodPlanks, fascia = rgb(40, 30, 24), text = rgb(255, 226, 180), lamp = rgb(255, 214, 160) },
	books = { wall = rgb(226, 220, 204), wallMat = MAT.Plaster, floor = rgb(160, 120, 80), floorMat = MAT.WoodPlanks, fascia = rgb(28, 52, 42), text = rgb(236, 230, 200), lamp = rgb(255, 232, 196) },
	fashion = { wall = rgb(238, 236, 232), wallMat = MAT.Plaster, floor = rgb(172, 170, 166), floorMat = MAT.Concrete, fascia = rgb(20, 20, 22), text = rgb(250, 250, 250), lamp = rgb(240, 244, 255) },
	cosmetics = { wall = rgb(246, 230, 234), wallMat = MAT.Plaster, floor = rgb(236, 234, 232), floorMat = MAT.CeramicTiles, fascia = rgb(250, 244, 246), text = rgb(200, 60, 110), lamp = rgb(255, 246, 250) },
	bakery = { wall = rgb(228, 198, 152), wallMat = MAT.Plaster, floor = rgb(206, 186, 158), floorMat = MAT.CeramicTiles, fascia = rgb(120, 70, 40), text = rgb(255, 236, 200), lamp = rgb(255, 214, 150) },
	food = { wall = rgb(56, 58, 62), wallMat = MAT.CeramicTiles, floor = rgb(120, 116, 110), floorMat = MAT.CeramicTiles, fascia = rgb(196, 54, 42), text = rgb(255, 244, 220), lamp = rgb(255, 230, 190) },
	goods = { wall = rgb(214, 216, 220), wallMat = MAT.Plaster, floor = rgb(190, 188, 182), floorMat = MAT.CeramicTiles, fascia = rgb(36, 60, 110), text = rgb(240, 244, 255), lamp = rgb(240, 244, 255) },
	shoes = { wall = rgb(74, 76, 80), wallMat = MAT.Concrete, floor = rgb(140, 110, 80), floorMat = MAT.WoodPlanks, fascia = rgb(18, 18, 20), text = rgb(255, 200, 80), lamp = rgb(255, 236, 210) },
	jewelry = { wall = rgb(30, 30, 34), wallMat = MAT.SmoothPlastic, floor = rgb(60, 58, 60), floorMat = MAT.Marble, fascia = rgb(14, 14, 16), text = rgb(230, 200, 140), lamp = rgb(255, 240, 220) },
	flowers = { wall = rgb(84, 112, 80), wallMat = MAT.Plaster, floor = rgb(150, 140, 126), floorMat = MAT.Slate, fascia = rgb(40, 70, 44), text = rgb(250, 240, 220), lamp = rgb(255, 236, 200) },
	tech = { wall = rgb(236, 238, 242), wallMat = MAT.SmoothPlastic, floor = rgb(200, 202, 206), floorMat = MAT.SmoothPlastic, fascia = rgb(240, 240, 244), text = rgb(30, 30, 34), lamp = rgb(236, 244, 255) },
}

local function sh(ko: string, en: string, kind: string): ShopSpec
	return { ko = ko, en = en, kind = kind }
end
-- 줄별 상점 (서→동). L1P 는 가운데 칸(입구 통로)을 건너뜀.
local SHOPS_L1P = { sh("편집숍", "SELECT SHOP", "fashion"), sh("신발", "SHOES", "shoes"), sh("카페", "CAFÉ", "cafe"), sh("베이커리", "BAKERY", "bakery"), sh("꽃집", "FLOWERS", "flowers"), sh("안경", "EYEWEAR", "goods") }
local SHOPS_L1N = { sh("아웃도어", "OUTDOOR", "fashion"), sh("서점", "BOOKS", "books"), sh("향수", "PERFUME", "cosmetics"), sh("화장품", "COSMETICS", "cosmetics"), sh("주얼리", "JEWELRY", "jewelry"), sh("시계", "WATCHES", "jewelry"), sh("디저트", "DESSERT", "bakery") }
local SHOPS_L2P = { sh("리빙", "LIVING", "goods"), sh("문구", "STATIONERY", "goods"), sh("전자", "ELECTRONICS", "tech"), sh("음반", "RECORDS", "books"), sh("아동복", "KIDS", "fashion"), sh("스포츠", "SPORTS", "shoes"), sh("푸드코트", "FOOD COURT", "food") }
local SHOPS_L2N = { sh("남성복", "MEN", "fashion"), sh("가방", "BAGS", "fashion"), sh("팝업스토어", "POP-UP", "goods"), sh("찻집", "TEA HOUSE", "cafe"), sh("약국", "PHARMACY", "cosmetics"), sh("분식", "SNACK BAR", "food"), sh("아이스크림", "GELATO", "bakery") }
local LIT_SHOPS = { ["카페"] = true, ["베이커리"] = true, ["화장품"] = true, ["서점"] = true, ["푸드코트"] = true }
local BOOK_C = { rgb(150, 60, 50), rgb(46, 70, 110), rgb(196, 170, 110), rgb(60, 96, 70), rgb(120, 96, 140), rgb(210, 200, 186) }
local CLOTH_C = { rgb(196, 186, 170), rgb(46, 52, 66), rgb(150, 70, 60), rgb(90, 110, 90), rgb(220, 214, 204), rgb(60, 60, 64) }
local PASTEL_C = { rgb(250, 200, 210), rgb(200, 230, 240), rgb(250, 236, 200), rgb(220, 210, 246), rgb(255, 255, 255) }

local function pick<T>(rng: Random, t: { T }): T
	return t[rng:NextInteger(1, #t)]
end

-- 진열창 상품(cf = 받침 윗면 중심, 로컬 -Z = 진열창 밖)
local function windowItem(m: Instance, cf: CFrame, kind: string, rng: Random)
	if kind == "fashion" or kind == "shoes" then
		VC(m, cf * CFrame.new(0, 1.2, 0), 2.4, 0.18, C.steel, MAT.Metal, false, "MannequinStand")
		Kit.ellipsoid(m, cf * CFrame.new(0, 3.7, 0), Vector3.new(1.5, 3.4, 0.9), pick(rng, CLOTH_C), MAT.Fabric, { name = "Mannequin" })
		Kit.ball(m, (cf * CFrame.new(0, 5.85, 0)).Position, 0.85, rgb(236, 232, 226), MAT.SmoothPlastic, { name = "MannequinHead", collide = false, query = false })
	elseif kind == "cosmetics" or kind == "jewelry" or kind == "tech" then
		for k = 0, 2 do
			local sz = 1.5 - k * 0.4
			D(m, cf * CFrame.new(-1 + k * 1.1, sz / 2, 0) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), Vector3.new(sz * 0.7, sz, sz * 0.7), if kind == "jewelry" then rgb(220, 190, 120) else pick(rng, PASTEL_C), if kind == "jewelry" then MAT.Metal else MAT.SmoothPlastic, "Product", 0.2)
		end
	elseif kind == "cafe" or kind == "bakery" or kind == "food" then
		VC(m, cf * CFrame.new(0, 0.6, 0), 1.2, 0.3, C.steel, MAT.Metal, false, "CakeStand")
		VC(m, cf * CFrame.new(0, 1.25, 0), 0.1, 2.2, C.white, MAT.SmoothPlastic, false, "Plate")
		VC(m, cf * CFrame.new(0, 1.75, 0), 0.9, 1.7, rgb(236, 214, 190), MAT.SmoothPlastic, false, "Cake")
	elseif kind == "books" then
		for k = 0, 2 do
			D(m, cf * CFrame.new(0, 0.2 + k * 0.4, 0) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Vector3.new(1.8, 0.4, 2.4), pick(rng, BOOK_C), MAT.SmoothPlastic, "Book")
		end
	elseif kind == "flowers" then
		VC(m, cf * CFrame.new(0, 0.9, 0), 1.8, 1.0, rgb(230, 230, 236), MAT.Glass, false, "Vase")
		Kit.ellipsoid(m, cf * CFrame.new(0, 2.4, 0), Vector3.new(2.2, 1.6, 2.2), pick(rng, { rgb(236, 120, 140), rgb(250, 210, 90), rgb(210, 120, 220) }), MAT.Fabric, { name = "Bouquet", query = false })
	else
		D(m, cf * CFrame.new(-0.6, 0.8, 0), Vector3.new(1.6, 1.6, 1.6), pick(rng, PRODUCT_C), MAT.SmoothPlastic, "Product")
		D(m, cf * CFrame.new(0.9, 0.5, 0.3), Vector3.new(1.2, 1.0, 1.2), pick(rng, PRODUCT_C), MAT.SmoothPlastic, "Product")
	end
end

-- 상점 내부 집기 (sp(dx, y, d) = 상점 앞 중심 기준, d = 진열창에서 안쪽 깊이)
local function shopFixtures(m: Instance, sp: (number, number, number) -> CFrame, kind: string, inner: number, depth: number, rng: Random, K: KindStyle)
	local back = depth - 0.4
	if kind == "cafe" then
		S(m, sp(0, COUNTER / 2, back - 3.2), Vector3.new(inner - 8, COUNTER, 2.4), C.walnut, MAT.Wood, "Counter")
		D(m, sp(0, COUNTER + 0.08, back - 3.3), Vector3.new(inner - 7.6, 0.16, 2.8), C.marble, MAT.Marble, "CounterTop")
		D(m, sp(-3, COUNTER + 0.9, back - 3.0), Vector3.new(2.2, 1.6, 1.4), C.steel, MAT.Metal, "Espresso", 0.3)
		sign(m, sp(0, 8.4, back - 0.06), Vector3.new(8, 3.8, 0.1), C.black, MAT.SmoothPlastic, "MENU  메뉴\n아메리카노 4,500\n카페라떼 5,000\n말차라떼 5,500", C.textWarm, 30)
		for _, dx in { -5.5, 5.5 } do
			roundTable(m, sp(dx, 0, 7), m2s(0.6), TABLE_H, C.marble, MAT.Marble)
			VC(m, sp(dx + 2.2, SEAT / 2, 7), SEAT, 1.3, C.oak, MAT.Wood, true, "Stool")
		end
	elseif kind == "books" then
		for _, sx in { -1, 1 } do
			local dx = sx * inner / 4
			S(m, sp(dx, 4.5, back - 0.9), Vector3.new(inner / 2 - 1.5, 9, 1.8), C.walnut, MAT.Wood, "Bookcase")
			for r = 0, 2 do
				D(m, sp(dx, 1.6 + r * 2.6, back - 1.9), Vector3.new(inner / 2 - 2.4, 1.7, 0.3), pick(rng, BOOK_C), MAT.SmoothPlastic, "Books")
			end
		end
		S(m, sp(0, 1.3, 9), Vector3.new(8, 2.6, 4), C.oak, MAT.Wood, "BookTable")
		for _, dx in { -2.2, 1.8 } do
			D(m, sp(dx, 2.9, 9) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Vector3.new(1.8, 0.6, 2.4), pick(rng, BOOK_C), MAT.SmoothPlastic, "BookStack")
		end
	elseif kind == "fashion" then
		for _, sx in { -1, 1 } do
			local dx = sx * inner / 4
			local len = inner / 2 - 4
			D(m, sp(dx, 4.7, 10), Vector3.new(len, 0.15, 0.15), C.steel, MAT.Metal, "Rail", 0.3)
			for _, ex in { -1, 1 } do
				D(m, sp(dx + ex * len / 2, 2.35, 10), Vector3.new(0.15, 4.7, 0.15), C.steel, MAT.Metal, "RailPost", 0.3)
			end
			D(m, sp(dx, 3.0, 10), Vector3.new(len - 0.6, 3.2, 1.3), pick(rng, CLOTH_C), MAT.Fabric, "Clothes")
		end
		D(m, sp(0, 5.0, back - 0.7), Vector3.new(inner - 6, 0.25, 1.4), C.oak, MAT.Wood, "WallShelf")
		D(m, sp(0, 5.6, back - 0.8), Vector3.new(inner - 7, 1.0, 1.2), pick(rng, CLOTH_C), MAT.Fabric, "FoldedClothes")
	elseif kind == "cosmetics" then
		for _, sx in { -1, 1 } do
			S(m, sp(sx * inner / 4, 1.5, 9), Vector3.new(6, 3.0, 3.5), C.white, MAT.SmoothPlastic, "Island")
			D(m, sp(sx * inner / 4, 3.3, 9), Vector3.new(5, 0.6, 2.8), pick(rng, PASTEL_C), MAT.Glass, "Products", 0.2)
		end
		N(m, sp(0, 6.2, back - 0.3), Vector3.new(inner - 4, 0.15, 0.3), rgb(255, 246, 250), "ShelfLight")
		D(m, sp(0, 5.2, back - 0.4), Vector3.new(inner - 5, 1.2, 0.6), pick(rng, PASTEL_C), MAT.SmoothPlastic, "WallProducts")
	elseif kind == "bakery" then
		S(m, sp(0, 1.5, 6), Vector3.new(inner - 10, 3.0, 2.6), C.oak, MAT.Wood, "DisplayBase")
		G(m, sp(0, 3.85, 6), Vector3.new(inner - 10, 1.7, 2.4), rgb(220, 232, 240), 0.55, false, "DisplayCase")
		N(m, sp(0, 3.06, 6), Vector3.new(inner - 10.4, 0.08, 2.2), rgb(255, 230, 190), "CaseShelf")
		for k = -1, 1 do
			Kit.ellipsoid(m, sp(k * (inner - 14) / 3, 3.4, 6), Vector3.new(2.2, 0.6, 1.4), rgb(200, 140, 70), MAT.SmoothPlastic, { name = "Bread", query = false })
		end
		S(m, sp(0, 3.5, back - 0.9), Vector3.new(inner - 6, 7, 1.6), C.oak, MAT.Wood, "BreadRack")
		for r = 0, 1 do
			D(m, sp(0, 2.6 + r * 2.6, back - 1.9), Vector3.new(inner - 7, 0.9, 0.5), rgb(196, 136, 70), MAT.SmoothPlastic, "BreadRow")
		end
	elseif kind == "food" then
		S(m, sp(0, COUNTER / 2, back - 3.4), Vector3.new(inner - 6, COUNTER, 2.4), rgb(70, 72, 76), MAT.Metal, "FoodCounter", 0.15)
		sign(m, sp(0, 8.2, back - 0.06), Vector3.new(inner - 4, 4.4, 0.1), rgb(120, 30, 24), MAT.Neon, "비빔밥 9,000   떡볶이 5,000\n돈까스 10,000   라멘 9,500\n김밥 4,000   냉면 9,000", rgb(255, 246, 226), 24)
		for _, dx in { -5.5, 5.5 } do
			S(m, sp(dx, TABLE_H - 0.1, 7.5), Vector3.new(4.2, 0.2, 3.0), C.white, MAT.SmoothPlastic, "FoodTable")
			D(m, sp(dx, (TABLE_H - 0.2) / 2, 7.5), Vector3.new(0.4, TABLE_H - 0.2, 0.4), C.black, MAT.Metal, "TableLeg")
			for _, dz in { -2.4, 2.4 } do
				VC(m, sp(dx, SEAT / 2, 7.5 + dz), SEAT, 1.2, rgb(220, 70, 50), MAT.SmoothPlastic, true, "Stool")
			end
		end
	elseif kind == "shoes" then
		for r = 0, 2 do
			D(m, sp(0, 2.0 + r * 2.6, back - 0.6), Vector3.new(inner - 4, 0.2, 1.2), C.oak, MAT.Wood, "ShoeShelf")
			D(m, sp(0, 2.55 + r * 2.6, back - 0.7), Vector3.new(inner - 5, 0.9, 1.0), pick(rng, CLOTH_C), MAT.Leather, "Shoes")
		end
		bench(m, sp(0, 0, 9), 8, C.leather)
	elseif kind == "jewelry" then
		for _, sx in { -1, 1 } do
			S(m, sp(sx * inner / 4, 1.3, 8), Vector3.new(6, 2.6, 2.6), C.black, MAT.SmoothPlastic, "CaseBase")
			G(m, sp(sx * inner / 4, 3.2, 8), Vector3.new(6, 1.2, 2.6), rgb(226, 236, 244), 0.6, false, "JewelCase")
			N(m, sp(sx * inner / 4, 2.66, 8), Vector3.new(5.6, 0.08, 2.2), rgb(255, 240, 220), "CaseLight")
		end
	elseif kind == "flowers" then
		for k = 0, 3 do
			local dx = -inner / 2 + 3 + k * (inner - 6) / 3
			VC(m, sp(dx, 1.0, back - 2.5), 2.0, 1.8, C.steel, MAT.Metal, true, "Bucket")
			Kit.ellipsoid(m, sp(dx, 2.6, back - 2.5), Vector3.new(2.4, 1.8, 2.4), pick(rng, { rgb(236, 120, 140), rgb(250, 210, 90), rgb(210, 120, 220), rgb(250, 250, 240) }), MAT.Fabric, { name = "Flowers", query = false })
		end
		S(m, sp(0, COUNTER / 2, 9), Vector3.new(7, COUNTER, 2.4), C.oak, MAT.Wood, "Counter")
	else -- goods / tech
		for _, sx in { -1, 1 } do
			S(m, sp(sx * inner / 4, 2.1, 9.5), Vector3.new(inner / 2 - 4, 4.2, 3.0), if kind == "tech" then C.white else C.oak, MAT.Wood, "Gondola")
			D(m, sp(sx * inner / 4, 4.5, 9.5), Vector3.new(inner / 2 - 5, 0.6, 2.4), pick(rng, PRODUCT_C), MAT.SmoothPlastic, "Products")
		end
		D(m, sp(0, 5.0, back - 0.4), Vector3.new(inner - 5, 3.0, 0.6), pick(rng, PRODUCT_C), MAT.SmoothPlastic, "WallProducts")
	end
end

local function buildShop(m: Instance, HF: CFrame, x0: number, x1: number, s: number, yf: number, ytop: number, ceilB: number, GZ: number, SD: number, spec: ShopSpec, rng: Random)
	local K = KIND[spec.kind] or KIND.goods
	local xc, inner = (x0 + x1) / 2, (x1 - x0) - 1.2
	local depth = SD - GZ
	local yawF = if s > 0 then FACE_NZ else FACE_PZ -- 갤러리아(정면)를 보는 yaw
	local function sp(dx: number, y: number, d: number): CFrame
		return HF * CFrame.new(xc + dx, yf + y, s * (GZ + d)) * CFrame.Angles(0, yawF, 0)
	end
	S(m, sp(0, -0.125, depth / 2), Vector3.new(inner, 0.35, depth), K.floor, K.floorMat, "ShopFloor")
	S(m, sp(0, (ytop - yf) / 2, depth + 0.05), Vector3.new(inner, ytop - yf, 0.9), K.wall, K.wallMat, "ShopWall")
	local lamp = N(m, sp(0, ceilB - yf - 0.05, depth / 2 + 1), Vector3.new(inner - 6, 0.12, depth - 8), K.lamp, "ShopLight")
	if LIT_SHOPS[spec.ko] then
		light(lamp, "PointLight", { color = K.lamp, brightness = 1.3, range = 26 })
	end
	-- 간판 띠(진열창 위 3.45 m ~ 4.35 m)
	local fy = 11.5
	local fas = Kit.part(m, sp(0, fy + 1.5, -0.25), Vector3.new(inner, 3.0, 0.5), { name = "Fascia", material = MAT.SmoothPlastic, color = K.fascia, collide = false, query = false, shadow = false })
	Kit.label(fas, FRONT, spec.ko .. "   " .. spec.en, { color = K.text, glow = true, pixelsPerStud = 20, maxDistance = 700, font = Enum.Font.GothamBold })
	-- 진열창 2 + 입구(2.4 m) 문설주 + 진열 받침 + 상품
	local ew = 8
	local gw = inner / 2 - ew / 2
	for _, sx in { -1, 1 } do
		local wx = sx * (ew / 2 + gw / 2)
		G(m, sp(wx, fy / 2, 0), Vector3.new(gw, fy, 0.3), rgb(200, 216, 226), 0.7, true, "ShopWindow")
		D(m, sp(sx * ew / 2, fy / 2, 0), Vector3.new(0.35, fy, 0.5), C.steelDark, MAT.Metal, "Mullion")
		S(m, sp(wx, 0.6, 2.6), Vector3.new(gw - 2.4, 1.2, 3.0), K.wall:Lerp(C.white, 0.6), MAT.SmoothPlastic, "WindowPlinth")
		windowItem(m, sp(wx, 1.2, 2.6), spec.kind, rng)
	end
	shopFixtures(m, sp, spec.kind, inner, depth, rng, K)
end

-- 에스컬레이터: (xb, yb) → (xt, yt) 30° 경사, 폭 방향 = Z. 보이는 계단 24 + 숨은 경사로(투명, 충돌) + 유리 난간 + 고무 손잡이
local function escalator(m: Instance, HF: CFrame, xb: number, xt: number, zc: number, yb: number, yt: number)
	local rise, run = yt - yb, xt - xb
	local ang = math.atan2(rise, run)
	local L = math.sqrt(rise * rise + run * run)
	local inc = HF * CFrame.new((xb + xt) / 2, (yb + yt) / 2, zc) * CFrame.Angles(0, 0, ang)
	local NS = 24
	local d, h = run / NS, rise / NS
	S(m, inc * CFrame.new(-1.5, -1.75, 0), Vector3.new(L + 3, 3.2, 5.4), C.steel, MAT.Metal, "EscalatorTruss", 0.12)
	S(m, HF * CFrame.new(xt + 1.5, yt - 1.62, zc), Vector3.new(5, 3.2, 5.4), C.steel, MAT.Metal, "EscalatorHead", 0.12)
	for i = 0, NS - 1 do
		local top = yb + (i + 1) * h
		D(m, HF * CFrame.new(xb + (i + 0.5) * d, top - h * 0.75, zc), Vector3.new(d + 0.02, h * 1.5, 3.4), rgb(70, 72, 78), MAT.DiamondPlate, "Step")
	end
	S(m, HF * CFrame.new(xb - 2.0, yb + 0.03, zc), Vector3.new(4, 0.1, 3.6), rgb(190, 190, 184), MAT.DiamondPlate, "CombPlate")
	S(m, HF * CFrame.new(xt + 2.0 - d / 4, yt + 0.03, zc), Vector3.new(4 + d / 2, 0.1, 3.6), rgb(190, 190, 184), MAT.DiamondPlate, "CombPlate")
	-- 숨은 경사로: 계단 디딤판 중간선
	local p0 = Vector3.new(xb - d / 2, yb, zc)
	local p1 = Vector3.new(xt - d / 2, yt, zc)
	local dir = (p1 - p0).Unit
	local nrm = Vector3.new(-dir.Y, dir.X, 0)
	local ext = 3
	local ctr = (p0 + p1) / 2 - dir * (ext / 2) - nrm * 0.5
	Kit.part(m, HF * CFrame.fromMatrix(ctr, dir, nrm), Vector3.new((p1 - p0).Magnitude + ext, 1.0, 3.6), { name = "EscalatorRamp", color = C.steel, transparency = 1, collide = true, query = false, shadow = false })
	for _, sz in { -1, 1 } do
		G(m, inc * CFrame.new(0, 2.05, sz * 2.45), Vector3.new(L + 1.0, 3.0, 0.2), rgb(206, 222, 230), 0.55, true, "EscalatorGlass")
		D(m, inc * CFrame.new(0, 3.7, sz * 2.45), Vector3.new(L + 1.2, 0.32, 0.42), C.black, MAT.Rubber, "Handrail")
		D(m, inc * CFrame.new(0, 0.55, sz * 1.85), Vector3.new(L, 1.1, 0.16), C.steel, MAT.Metal, "Skirt", 0.3)
		for _, e in { { xt + 2.0, yt }, { xb - 2.0, yb } } do
			G(m, HF * CFrame.new(e[1], e[2] + 2.05, zc + sz * 2.45), Vector3.new(4.0, 3.0, 0.2), rgb(206, 222, 230), 0.55, true, "EscalatorGlass")
			D(m, HF * CFrame.new(e[1], e[2] + 3.7, zc + sz * 2.45), Vector3.new(4.2, 0.32, 0.42), C.black, MAT.Rubber, "Handrail")
		end
	end
end

local function balustrade(m: Instance, cf: CFrame, len: number) -- cf = 바닥 위 중심, 로컬 X = 길이
	G(m, cf * CFrame.new(0, 1.85, 0), Vector3.new(len, 3.1, 0.25), rgb(206, 222, 230), 0.6, true, "Balustrade")
	D(m, cf * CFrame.new(0, 3.55, 0), Vector3.new(len + 0.2, 0.25, 0.45), C.steel, MAT.Metal, "Handrail", 0.3)
	D(m, cf * CFrame.new(0, 0.35, 0), Vector3.new(len, 0.5, 0.5), C.steel, MAT.Metal, "BaseShoe", 0.2)
end

local function buildMall(m: Model, Hl: any, rng: Random)
	local HF: CFrame = Hl.cf
	local GX, GZ, VZ, SD, EX = Hl.GX, Hl.GZ, Hl.VZ, Hl.SD, Hl.EX
	local FY1, FY2, H, HZ = Hl.FY1, Hl.FY2, Hl.H, Hl.HZ
	local nS = Hl.shops
	local sw = 2 * GX / nS
	local slabB = FY2 - 3 -- 메자닌 슬래브 아랫면
	local c1B = slabB - 1.3 -- 1층 상점 천장 아랫면
	local c2B = FY2 + 14.2 -- 2층 상점 천장 아랫면
	local mid = (nS + 1) // 2 - 1 -- 가운데 칸 = 입구 통로 (0 기반)
	local function at(x: number, y: number, z: number, yaw: number?): CFrame
		return HF * CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0)
	end

	-- 바닥(밝은 대리석) + 상점 앞 화강석 띠 + 보이드 테두리 띠
	S(m, at(0, FY1 - 0.3, 0), Vector3.new(2 * GX, 0.6, 2 * GZ), C.marble, MAT.Marble, "AtriumFloor", 0.06)
	S(m, at(0, FY1 - 0.3, (GZ + HZ + 0.3) / 2), Vector3.new(2 * EX, 0.6, HZ + 0.3 - GZ), C.marble, MAT.Marble, "PassageFloor", 0.06)
	for _, sz in { -1, 1 } do
		D(m, at(0, FY1 - 0.125, sz * (GZ - 2.5)), Vector3.new(2 * GX - 2, 0.35, 1.2), C.granite, MAT.Granite, "Inlay", 0.1)
		D(m, at(0, FY1 - 0.125, sz * VZ), Vector3.new(2 * GX - 30, 0.35, 0.8), rgb(178, 160, 128), MAT.Marble, "Inlay")
	end

	-- 메자닌(2층 보행로 + 2층 상점 바닥) + 보이드 쪽 흰 띠 + LED + 하부 조명, 양 끝 다리 2
	for _, sz in { -1, 1 } do
		S(m, at(0, FY2 - 1.5, sz * (VZ + SD) / 2), Vector3.new(2 * GX, 3, SD - VZ), C.marble, MAT.Marble, "Mezzanine", 0.05)
		D(m, at(0, FY2 - 1.4, sz * (VZ - 0.1)), Vector3.new(2 * GX - 28, 3.3, 0.4), C.white, MAT.SmoothPlastic, "MezzFascia")
		N(m, at(0, FY2 - 2.6, sz * (VZ - 0.33)), Vector3.new(2 * GX - 28, 0.14, 0.06), C.coolLight, "MezzLed")
		N(m, at(0, FY2 - 3.05, sz * (GZ - 5)), Vector3.new(2 * GX - 8, 0.12, 0.7), C.warmLight, "SoffitLight")
		balustrade(m, at(0, FY2, sz * (VZ + 0.5)), 2 * GX - 28)
	end
	for _, sx in { -1, 1 } do
		S(m, at(sx * (GX - 7), FY2 - 1.5, 0), Vector3.new(14, 3, 2 * VZ), C.marble, MAT.Marble, "Bridge", 0.05)
		D(m, at(sx * (GX - 13.9), FY2 - 1.4, 0), Vector3.new(0.4, 3.3, 2 * VZ + 0.6), C.white, MAT.SmoothPlastic, "BridgeFascia")
		N(m, at(sx * (GX - 14.13), FY2 - 2.6, 0), Vector3.new(0.06, 0.14, 2 * VZ), C.coolLight, "MezzLed")
	end
	balustrade(m, at(-(GX - 13.5), FY2, 0, math.pi / 2), 2 * VZ + 1)
	local gap = 6.2
	for _, sz in { -1, 1 } do
		local z0, z1 = gap, VZ + 0.5
		balustrade(m, at(GX - 13.5, FY2, sz * (z0 + z1) / 2, math.pi / 2), z1 - z0)
	end

	-- 에스컬레이터 한 쌍(동쪽 다리로): 30°, 층고 6 m
	local xTop = GX - 14
	local run = (FY2 - FY1) / math.tan(math.rad(30))
	local xb = xTop - 4 - run
	for _, zc in { -3.2, 3.2 } do
		escalator(m, HF, xb, xTop - 4, zc, FY1, FY2)
	end
	sign(m, at(xb - 4.3, FY1 + 6.2, 0, FACE_NX), Vector3.new(5.6, 1.4, 0.12), rgb(24, 26, 32), MAT.SmoothPlastic, "↑ 2F  푸드코트 · 리빙", C.textWarm, 40)
	D(m, at(xb - 4.3, FY1 + 3.4, 0), Vector3.new(0.3, 5.0, 0.3), C.steelDark, MAT.Metal, "SignPost")

	-- 상점 천장 / 1층 벌크헤드 / 클리어스토리(2층 간판 위 ~ 지붕) / 칸막이 기둥 / 양 끝벽
	for _, sz in { -1, 1 } do
		if sz > 0 then
			for _, sx in { -1, 1 } do
				D(m, at(sx * (GX + EX) / 2, c1B + 0.3, (GZ + SD) / 2), Vector3.new(GX - EX, 0.6, SD - GZ), C.plaster, MAT.Plaster, "ShopCeiling")
			end
		else
			D(m, at(0, c1B + 0.3, -(GZ + SD) / 2), Vector3.new(2 * GX, 0.6, SD - GZ), C.plaster, MAT.Plaster, "ShopCeiling")
		end
		D(m, at(0, c2B + 0.3, sz * (GZ + SD) / 2), Vector3.new(2 * GX, 0.6, SD - GZ), C.plaster, MAT.Plaster, "ShopCeiling")
		S(m, at(0, (FY1 + 14.3 + slabB + 0.1) / 2, sz * (GZ + 0.2)), Vector3.new(2 * GX, slabB + 0.1 - FY1 - 14.3, 0.9), C.white, MAT.Plaster, "Bulkhead")
		S(m, at(0, (c2B - 0.2 + H) / 2, sz * (GZ + 0.2)), Vector3.new(2 * GX, H - c2B + 0.2, 0.9), rgb(232, 228, 220), MAT.Limestone, "Clerestory")
		for _, y in { FY2 + 22, FY2 + 30 } do
			N(m, at(0, y, sz * (GZ - 0.3)), Vector3.new(2 * GX - 2, 0.15, 0.1), C.warmLight, "ClerestoryLine")
		end
		for k = 0, nS do
			local x = -GX + k * sw
			S(m, at(x, (FY1 - 0.3 + c2B + 0.6) / 2, sz * (GZ - 0.6 + SD) / 2), Vector3.new(1.2, c2B + 0.9 - FY1, SD - GZ + 0.6), rgb(232, 230, 224), MAT.Limestone, "Pilaster")
		end
	end
	for _, sx in { -1, 1 } do
		S(m, at(sx * (GX + 0.1), (FY1 - 0.3 + H) / 2, 0), Vector3.new(1.0, H - FY1 + 0.3, 2 * GZ - 1.2), C.travertine, MAT.Limestone, "EndWall")
	end
	-- 서쪽 끝벽: 몰 이름 + 1층 안내 / 동쪽 끝벽: 미디어 스크린(다리 위)
	sign(m, at(-GX + 0.45, FY2 + 23, 0, FACE_PX), Vector3.new(40, 7, 0.12), rgb(20, 24, 34), MAT.SmoothPlastic, "아트리움 몰   ATRIUM MALL", rgb(200, 226, 255), 16)
	N(m, at(-GX + 0.43, FY2 + 19.2, 0, FACE_PX), Vector3.new(40, 0.18, 0.08), rgb(120, 182, 255), "SignLine")
	sign(m, at(-GX + 0.45, FY1 + 9, 0, FACE_PX), Vector3.new(16, 2.2, 0.12), rgb(24, 26, 32), MAT.SmoothPlastic, "화장실 RESTROOM   ·   고객센터 INFO", C.textWarm, 30)
	local scr0, scr1 = FY2 + 7, FY2 + 25
	S(m, at(GX - 0.65, (scr0 + scr1) / 2, 0), Vector3.new(0.5, scr1 - scr0 + 1.2, 2 * VZ + 1.2), C.black, MAT.SmoothPlastic, "ScreenFrame")
	local cols, rows = 6, 3
	local cw, rh = 2 * VZ / cols, (scr1 - scr0) / rows
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local t = (i + 0.5) / cols
			local c = rgb(40, 110, 220):Lerp(rgb(120, 220, 255), (j + 0.5) / rows * 0.7 + 0.3 * math.sin(t * math.pi))
			N(m, at(GX - 0.98, scr0 + (j + 0.5) * rh, -VZ + (i + 0.5) * cw), Vector3.new(0.12, rh - 0.25, cw - 0.25), Color3.new(c.R * 0.8, c.G * 0.8, c.B * 0.8), "ScreenTile")
		end
	end
	sign(m, at(GX - 1.08, scr0 + rh * 1.5, 0, FACE_NX), Vector3.new(2 * VZ - 6, rh * 0.8, 0.05), rgb(20, 40, 90), MAT.SmoothPlastic, "가을 페스티벌  AUTUMN FESTIVAL  11.01 – 11.30", C.textWhite, 20)

	-- 1층 통로(정면 입구 → 갤러리아): 벽 마감 + 천장 + 열린 자동문 + 매트 + 층별 안내 + 라이트박스
	for _, sx in { -1, 1 } do
		S(m, at(sx * (EX - 0.1), (FY1 - 0.3 + c1B + 0.6) / 2, (SD + HZ - 1.6) / 2), Vector3.new(1.0, c1B + 0.9 - FY1, HZ - 1.6 - SD), C.travertine, MAT.Limestone, "PassageWall")
	end
	D(m, at(0, c1B + 0.3, (GZ + HZ - 0.6) / 2), Vector3.new(2 * EX - 1.2, 0.6, HZ - 0.6 - GZ), C.plaster, MAT.Plaster, "PassageCeiling")
	local psLamp: BasePart? = nil
	for _, x in { -5, 5 } do
		local s = N(m, at(x, c1B - 0.05, (GZ + HZ) / 2), Vector3.new(0.6, 0.12, HZ - GZ - 6), C.warmLight, "PassageLight")
		psLamp = psLamp or s
	end
	if psLamp then
		light(psLamp, "PointLight", { color = rgb(255, 228, 190), brightness = 1.2, range = 30 })
	end
	local dxs, DW, DH = Hl.doorXs, Hl.doorW, Hl.doorH
	for i, dx in dxs do
		for _, sx in { -1, 1 } do
			local lx = dx + sx * (DW / 2 + 2.1 - 0.25)
			local zl = if (i == 1 and sx == 1) then HZ - 1.4 else HZ - 1.0
			G(m, at(lx, FY1 + DH / 2, zl), Vector3.new(4.2, DH - 0.1, 0.22), C.glass, 0.62, false, "DoorLeaf")
			D(m, at(lx, FY1 + 0.22, zl), Vector3.new(4.2, 0.36, 0.3), C.steelDark, MAT.Metal, "LeafRail")
			D(m, at(lx - sx * 2.0, FY1 + DH / 2, zl), Vector3.new(0.22, DH - 0.1, 0.32), C.steelDark, MAT.Metal, "LeafStile")
		end
	end
	D(m, at(0, FY1 + 0.04, HZ - 6), Vector3.new(2 * EX - 1.4, 0.08, 9), rgb(46, 44, 42), MAT.Fabric, "EntranceMat")
	sign(m, at(EX - 0.65, FY1 + 6.5, SD + 9, FACE_NX), Vector3.new(10, 8, 0.12), rgb(26, 28, 34), MAT.SmoothPlastic, "층별 안내  FLOOR GUIDE\n2F  푸드코트 · 리빙 · 스포츠 · 전자\n1F  카페 · 베이커리 · 화장품 · 서점\n← 아트리움 ATRIUM →", C.textWarm, 30)
	sign(m, at(-EX + 0.65, FY1 + 6.5, SD + 9, FACE_PX), Vector3.new(9, 9, 0.12), rgb(36, 70, 140), MAT.Neon, "ATRIUM MALL\n아트리움 몰\n\n가을 페스티벌\n11.01 – 11.30", rgb(255, 255, 255), 30)

	-- 갤러리아 1층: 앉음 섬(Ø 3.3 m 화분 + 나무 8 m + 원목 좌면 0.43 m) 3, 팝업 키오스크, 벤치
	for _, ix in { -78, -18, 26 } do
		local cf = at(ix, FY1, 0)
		treePlanter(m, cf, 11, 1.25, m2s(8), rng, rgb(232, 228, 220), MAT.Concrete)
		VC(m, cf * CFrame.new(0, 1.34, 0), 0.18, 11.8, C.oak, MAT.Wood, true, "SeatRim")
		VC(m, cf * CFrame.new(0, 1.47, 0), 0.1, 9.6, P.Soil, MAT.Ground, false, "Soil")
	end
	local kc = at(-48, FY1, 0)
	S(m, kc * CFrame.new(0, 1.7, 0), Vector3.new(9, 3.4, 4), C.white, MAT.Wood, "KioskCounter")
	D(m, kc * CFrame.new(0, 3.48, 0), Vector3.new(9.4, 0.16, 4.4), C.oak, MAT.Wood, "KioskTop")
	for _, sx in { -1, 1 } do
		D(m, kc * CFrame.new(sx * 4.4, 6.2, 0), Vector3.new(0.3, 5.4, 0.3), C.steelDark, MAT.Metal, "KioskPost")
	end
	local roof = D(m, kc * CFrame.new(0, 9.1, 0), Vector3.new(10, 0.5, 5.2), rgb(196, 54, 42), MAT.SmoothPlastic, "KioskRoof")
	local ks = sign(m, kc * CFrame.new(0, 8.2, 0), Vector3.new(9, 1.3, 4.6), rgb(250, 246, 240), MAT.SmoothPlastic, "팝업스토어  POP-UP", rgb(196, 54, 42), 30)
	Kit.label(ks, BACK, "팝업스토어  POP-UP", { color = rgb(196, 54, 42), glow = true, pixelsPerStud = 30, maxDistance = 500 })
	light(roof, "PointLight", { color = rgb(255, 226, 190), brightness = 1.0, range = 20 })
	for k = 0, 2 do
		D(m, kc * CFrame.new(-2.8 + k * 2.8, 4.0, 0), Vector3.new(1.4, 0.9, 1.4), pick(rng, PRODUCT_C), MAT.SmoothPlastic, "Goods")
	end
	for _, bp in { { -32, 1 }, { 6, 1 }, { -62, -1 }, { 6, -1 } } do
		bench(m, at(bp[1], FY1, bp[2] * (VZ + 4), if bp[2] > 0 then FACE_NZ else FACE_PZ), m2s(2.4), C.oak)
	end
	-- 2층 보행로: 벤치 + 긴 화분
	for _, bp in { { -60, 1 }, { 20, 1 }, { -20, -1 }, { 60, -1 } } do
		bench(m, at(bp[1], FY2, bp[2] * (GZ - 4), if bp[2] > 0 then FACE_NZ else FACE_PZ), m2s(2.4), C.oak)
	end
	for _, pp in { { -40, 1 }, { 40, 1 }, { -40, -1 }, { 40, -1 } } do
		S(m, at(pp[1], FY2 + 1.0, pp[2] * (VZ + 2.6)), Vector3.new(9, 2.0, 2.2), rgb(70, 68, 66), MAT.Concrete, "Planter")
		Kit.ellipsoid(m, at(pp[1], FY2 + 2.1, pp[2] * (VZ + 2.6)), Vector3.new(8.6, 2.2, 2.0), P.Leaf2, MAT.Grass, { name = "Shrub", query = false })
	end

	-- 보이드: 볼트에서 내려오는 대형 펜던트 3(실제 광원), 클리어스토리 행잉 배너 6, 벽 조명
	local vaultY = H + 0.8 + m2s(10) - 1
	for _, px in { -60, -20, 20 } do
		local gy = FY2 + 16
		D(m, at(px, (gy + vaultY) / 2, 0), Vector3.new(0.12, vaultY - gy, 0.12), C.black, MAT.Metal, "PendantCable")
		local g = Kit.ball(m, (at(px, gy, 0)).Position, 3.2, rgb(255, 226, 180), MAT.Neon, { name = "PendantGlobe", collide = false, query = false, shadow = false, glow = true, dayMaterial = MAT.Glass, dayColor = rgb(236, 230, 220) })
		D(m, at(px, gy + 1.9, 0), Vector3.new(1.4, 0.6, 1.4), C.bronze, MAT.Metal, "PendantCap", 0.2)
		light(g, "PointLight", { color = rgb(255, 222, 176), brightness = 1.4, range = 58 })
	end
	local BANNERS = { "가을 페스티벌\nAUTUMN\nFESTIVAL", "11.01\n—\n11.30", "아트리움 몰\nATRIUM\nMALL" }
	for i, bx in { -72, 0, 72 } do
		for _, sz in { -1, 1 } do
			local yawB = if sz > 0 then FACE_NZ else FACE_PZ
			local bcf = at(bx, FY2 + 26, sz * (GZ - 1.6), yawB)
			D(m, bcf * CFrame.new(0, 8.6, 0), Vector3.new(6.2, 0.25, 0.25), C.steelDark, MAT.Metal, "BannerRod")
			local col = if (i + (if sz > 0 then 0 else 1)) % 2 == 0 then rgb(150, 30, 44) else rgb(28, 50, 110)
			sign(m, bcf, Vector3.new(5.6, 16.6, 0.12), col, MAT.Fabric, BANNERS[i], rgb(255, 244, 224), 20)
		end
	end
	for _, sz in { -1, 1 } do
		for _, x in { -50, 50 } do
			local sc = N(m, at(x, FY2 + 9.5, sz * (GZ - 0.45), if sz > 0 then FACE_NZ else FACE_PZ), Vector3.new(1.0, 2.2, 0.3), C.warmLight, "Sconce")
			if x == 50 then
				light(sc, "PointLight", { color = rgb(255, 224, 186), brightness = 0.9, range = 24 })
			end
		end
	end

	-- 상점 27 (1층 북/남 + 2층 북/남)
	local rowsDef = {
		{ s = 1, yf = FY1, ytop = slabB, ceilB = c1B, list = SHOPS_L1P, skip = mid },
		{ s = -1, yf = FY1, ytop = slabB, ceilB = c1B, list = SHOPS_L1N, skip = -1 },
		{ s = 1, yf = FY2, ytop = c2B + 0.6, ceilB = c2B, list = SHOPS_L2P, skip = -1 },
		{ s = -1, yf = FY2, ytop = c2B + 0.6, ceilB = c2B, list = SHOPS_L2N, skip = -1 },
	}
	for _, row in rowsDef do
		local idx = 0
		for k = 0, nS - 1 do
			if k ~= row.skip then
				idx += 1
				local spec = row.list[idx]
				if spec then
					buildShop(m, HF, -GX + k * sw, -GX + (k + 1) * sw, row.s, row.yf, row.ytop, row.ceilB, GZ, SD, spec, rng)
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 진입점
------------------------------------------------------------------------------------------------------
function LandmarkInterior.build(ctx: any)
	local L = Landmark.layout
	if not L or not L.lobby or not L.obs or not L.hall then
		warn("[SeoulSkyline] LandmarkInterior: Landmark.layout 이 없습니다 — Landmark 를 먼저 빌드하세요")
		return
	end
	lightsUsed = 0
	local rng: Random = ctx.rng
	local root: Model = ctx.model
	local TF: CFrame = L.TF
	local Lb, Ob, Hl = L.lobby, L.obs, L.hall
	-- 엘리베이터 도착 지점(캐릭터 피벗 = 바닥 + 3.5, SeoulSkylineBoot 가 -Z 를 보게 세움)
	local obsT = (TF * CFrame.new(0, Ob.yA + 0.15 + 3.5, -CORE_H - 9)).Position
	local loungeT = (TF * CFrame.new(0, Ob.yB + 0.15 + 3.5, -CORE_H - 9)).Position
	local lobbyT = (TF * CFrame.new(0, Lb.floorY + 3.5, Lb.ZB + 22)).Position
	local p0 = Kit.stats.parts
	buildLobby(Kit.group(root, "TowerLobby", Config.InteriorStreaming), TF, Lb, obsT, rng)
	local p1 = Kit.stats.parts
	buildObservatory(Kit.group(root, "SeoulSky", Config.InteriorStreaming), Kit.group(root, "SeoulSkyGlow"), TF, Ob, lobbyT, obsT, loungeT, rng)
	local p2 = Kit.stats.parts
	buildMall(Kit.group(root, "MallAtrium", Config.InteriorStreaming), Hl, rng)
	local p3 = Kit.stats.parts
	-- 다른 도구/디버그용 좌표
	root:SetAttribute("LobbyEntrance", (TF * CFrame.new(0, Lb.floorY + 3.5, Lb.W + 8)).Position)
	root:SetAttribute("LobbyArrival", lobbyT)
	root:SetAttribute("ObservatoryArrival", obsT)
	root:SetAttribute("LoungeArrival", loungeT)
	root:SetAttribute("MallEntrance", (Hl.cf * CFrame.new(0, Hl.FY1 + 3.5, Hl.HZ + 8)).Position)
	root:SetAttribute("Parts", string.format("lobby %d / observatory %d / mall %d", p1 - p0, p2 - p1, p3 - p2))
	root:SetAttribute("Lights", lightsUsed)
end

return LandmarkInterior
