--!strict
-- GwangalliBuildingInterior/Look: 재질 · 색 팔레트. look 테이블 = { c, m, t, r, shadow, collide, free }.
--   L.of(r, g, b, material?, extra?)  임의 색
--   L.<이름>                         자주 쓰는 마감재 (아래 목록)
--   L.neon(color) / L.screen(color) / L.glass(tint, t)
--   L.with(look, { ... })             look 에 필드 덧씌우기 (예: L.with(L.oak, { shadow = true }))
-- 실제 한국 매장 마감 기준: 무광 화이트 도장, 오크 · 월넛 무늬목, 스테인리스 주방, 테라조 · 포세린 타일 바닥,
-- 블랙 파우더 코팅 철제 다리, PVC 레더 의자, 아크릴 간판, 텍스 천장 (흡음 텍스 600각).

local M = Enum.Material
local L = {}

local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
L.rgb = c3

function L.of(r: number, g: number, b: number, m: Enum.Material?, extra: { [string]: any }?): { [string]: any }
	local t: { [string]: any } = { c = c3(r, g, b), m = m or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end

function L.with(look: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local t = table.clone(look)
	for k, v in extra do
		t[k] = v
	end
	return t
end

function L.neon(c: Color3, t: number?): { [string]: any }
	return { c = c, m = M.Neon, t = t or 0 }
end

-- 켜진 화면 (LCD): 약하게 빛나는 SmoothPlastic 위에 글자판 · 화면 GUI 를 얹어 씀
function L.screen(c: Color3?): { [string]: any }
	return { c = c or c3(18, 22, 30), m = M.Glass, r = 0.12 }
end

function L.glass(tint: Color3?, t: number?): { [string]: any }
	return { c = tint or c3(200, 225, 230), m = M.Glass, t = t or 0.6, r = 0.15 }
end

-- 금속
L.chrome = L.of(222, 224, 228, M.Metal, { r = 0.25 })
L.steel = L.of(178, 182, 186, M.Metal, { r = 0.08 }) -- 스테인리스 (주방 · 냉장고 · 싱크)
L.brushed = L.of(160, 163, 168, M.Metal) -- 헤어라인
L.blackMetal = L.of(32, 32, 34, M.Metal) -- 블랙 파우더 코팅 (의자 다리 · 레일 · 조명)
L.brass = L.of(186, 152, 88, M.Metal, { r = 0.1 })
L.goldMetal = L.of(196, 164, 98, M.Metal, { r = 0.12 })
L.alu = L.of(196, 198, 202, M.Metal) -- 알루미늄 프레임 · 섀시
L.darkAlu = L.of(70, 72, 76, M.Metal)

-- 나무 (Wood = 결이 보이는 무늬목, WoodPlanks = 마루 · 루버)
L.oak = L.of(196, 160, 118, M.Wood)
L.lightOak = L.of(214, 186, 148, M.Wood)
L.walnut = L.of(110, 76, 52, M.Wood)
L.darkWood = L.of(72, 50, 36, M.Wood)
L.birch = L.of(226, 206, 174, M.Wood)
L.pine = L.of(208, 168, 112, M.Wood)
L.plywood = L.of(214, 182, 136, M.Wood)
L.floorOak = L.of(170, 128, 88, M.WoodPlanks)
L.louver = L.of(160, 120, 84, M.WoodPlanks)

-- 도장 · 플라스틱
L.white = L.of(242, 242, 238, M.SmoothPlastic) -- 무광 화이트 도장
L.offWhite = L.of(232, 226, 214, M.SmoothPlastic)
L.warmGrey = L.of(170, 164, 156, M.SmoothPlastic)
L.grey = L.of(128, 130, 134, M.SmoothPlastic)
L.charcoal = L.of(48, 50, 54, M.SmoothPlastic)
L.black = L.of(22, 22, 24, M.SmoothPlastic)
L.plasticWhite = L.of(236, 236, 232, M.Plastic)
L.plasticBlack = L.of(28, 28, 30, M.Plastic)
L.rubber = L.of(30, 30, 32, M.Rubber)
L.cardboard = L.of(176, 136, 92, M.Cardboard)
L.paper = L.of(246, 244, 236, M.SmoothPlastic)
L.kraft = L.of(196, 162, 118, M.Cardboard)

-- 돌 · 타일 · 바닥
L.marbleWhite = L.of(236, 234, 228, M.Marble)
L.marbleBlack = L.of(40, 40, 42, M.Marble)
L.terrazzo = L.of(214, 210, 200, M.Granite)
L.granite = L.of(120, 116, 112, M.Granite)
L.concrete = L.of(150, 148, 144, M.Concrete)
L.polishedConcrete = L.of(168, 166, 162, M.Slate, { r = 0.04 })
L.tileWhite = L.of(240, 240, 236, M.CeramicTiles) -- 주방 · 화장실 벽 타일
L.tileGrey = L.of(170, 172, 172, M.CeramicTiles)
L.porcelain = L.of(206, 202, 194, M.CeramicTiles) -- 600각 포세린 바닥 타일
L.brickRed = L.of(150, 82, 62, M.Brick)
L.brickWhite = L.of(226, 222, 214, M.Brick)
L.slate = L.of(70, 72, 74, M.Slate)
L.plaster = L.of(236, 232, 222, M.Plaster)
L.ceilingTex = L.of(240, 238, 232, M.Plaster) -- 흡음 텍스

-- 섬유 · 가죽
L.leatherBlack = L.of(34, 32, 32, M.Leather)
L.leatherBrown = L.of(118, 74, 46, M.Leather)
L.leatherCream = L.of(222, 210, 188, M.Leather)
L.leatherRed = L.of(150, 36, 34, M.Leather)
L.fabricGrey = L.of(140, 140, 138, M.Fabric)
L.fabricBeige = L.of(204, 190, 166, M.Fabric)
L.fabricNavy = L.of(44, 54, 84, M.Fabric)
L.fabricGreen = L.of(70, 98, 74, M.Fabric)
L.carpetGrey = L.of(96, 96, 98, M.Fabric)
L.rattan = L.of(190, 156, 104, M.Fabric)

-- 식물
L.leaf = L.of(70, 112, 58, M.Grass)
L.leafDark = L.of(46, 82, 44, M.Grass)
L.leafLight = L.of(110, 150, 74, M.Grass)
L.soil = L.of(76, 56, 40, M.Ground)
L.terracotta = L.of(182, 104, 70, M.SmoothPlastic)

-- 유리 · 빛
L.glassClear = L.glass(c3(214, 232, 236), 0.7)
L.glassDark = L.glass(c3(40, 46, 52), 0.35)
L.mirror = { c = c3(196, 206, 212), m = M.Glass, t = 0.05, r = 0.55 }
L.acrylicWhite = { c = c3(252, 250, 244), m = M.Glass, t = 0.15 } -- 조명 확산판 · 아크릴
L.lampWarm = L.neon(c3(255, 214, 160)) -- 백열 · 3000K
L.lampNeutral = L.neon(c3(255, 240, 220)) -- 4000K
L.lampCool = L.neon(c3(232, 242, 255)) -- 형광 · 6500K
L.ledRed = L.neon(c3(255, 60, 50))
L.ledGreen = L.neon(c3(60, 230, 120))
L.ledBlue = L.neon(c3(70, 150, 255))

-- 불빛 색 (Light.Color)
L.warmLight = c3(255, 214, 170)
L.neutralLight = c3(255, 238, 220)
L.coolLight = c3(236, 244, 255)

return L
