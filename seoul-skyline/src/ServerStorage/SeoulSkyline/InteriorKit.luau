--!strict
-- SeoulSkyline / InteriorKit
-- 실내 모듈 공용 키트(LandmarkInterior · TowerLobby · SeoulSkyInterior · MallInterior, 필요하면 다른 실내도):
--   파트 헬퍼 S(충돌)/D(장식)/N(야간 발광)/G(유리)/VC(세로 원기둥)/sign(글자판), 엘리베이터 버튼·문·호출 패널,
--   가구(소파·의자·원탁·벤치·화분·나무·망원경·스탠션), 실내 팔레트 C, 광원 예산(IK.resetLights / IK.lightsUsed).
-- 모든 치수는 실측(Config.m / Config.Real). 가구 cf = 바닥 위 발자국 중심, 로컬 -Z = 정면.

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)


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
-- 내보내기
------------------------------------------------------------------------------------------------------
local IK = {
	P = P, Real = Real, m2s = m2s, rgb = rgb, MAT = MAT, FRONT = FRONT, BACK = BACK, CYL_UP = CYL_UP,
	FACE_PZ = FACE_PZ, FACE_NZ = FACE_NZ, FACE_PX = FACE_PX, FACE_NX = FACE_NX,
	SEAT = SEAT, TABLE_H = TABLE_H, COUNTER = COUNTER, C = C,
	light = light, S = S, D = D, N = N, G = G, VC = VC, sign = sign, elevatorButton = elevatorButton,
	sofa = sofa, chair = chair, roundTable = roundTable, bench = bench, treePlanter = treePlanter, pottedPlant = pottedPlant,
	telescope = telescope, elevatorDoor = elevatorDoor, callPanel = callPanel, stanchions = stanchions,
}

-- 광원 예산: LandmarkInterior.build 가 시작할 때 0 으로, cap = 이 묶음 전체 상한
function IK.resetLights(cap: number?)
	lightsUsed = 0
	LIGHT_CAP = cap or LIGHT_CAP
end
function IK.lightsUsed(): number
	return lightsUsed
end

return IK
