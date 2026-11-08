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

return LandmarkInterior
