--!strict
-- SeoulSkyline / MallInterior
-- 몰 아트리움(파란 곡면 지붕 홀) 실내: 2개 층 갤러리아 + 상점 27 + 에스컬레이터 + 메자닌.
-- LandmarkInterior 가 require 해서 호출(Landmark.layout 좌표). 공용 헬퍼/가구는 InteriorKit.

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local IK = require(script.Parent.InteriorKit)
local P, Real, m2s, rgb, MAT = IK.P, IK.Real, IK.m2s, IK.rgb, IK.MAT
local FRONT, BACK, CYL_UP = IK.FRONT, IK.BACK, IK.CYL_UP
local FACE_PZ, FACE_NZ, FACE_PX, FACE_NX = IK.FACE_PZ, IK.FACE_NZ, IK.FACE_PX, IK.FACE_NX
local SEAT, TABLE_H, COUNTER, C = IK.SEAT, IK.TABLE_H, IK.COUNTER, IK.C
local light, S, D, N, G, VC, sign = IK.light, IK.S, IK.D, IK.N, IK.G, IK.VC, IK.sign
local elevatorButton, elevatorDoor, callPanel, stanchions = IK.elevatorButton, IK.elevatorDoor, IK.callPanel, IK.stanchions
local sofa, chair, roundTable, bench = IK.sofa, IK.chair, IK.roundTable, IK.bench
local treePlanter, pottedPlant, telescope = IK.treePlanter, IK.pottedPlant, IK.telescope
type PartOpts = Kit.PartOpts

local MallInterior = {}
local PRODUCT_C = require(script.Parent.SeoulSkyInterior).PRODUCT_C

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


MallInterior.build = buildMall
return MallInterior
