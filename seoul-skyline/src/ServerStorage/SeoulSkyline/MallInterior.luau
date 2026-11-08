--!strict
-- SeoulSkyline / MallInterior
-- 몰 아트리움(파란 곡면 지붕 홀) 실내 — 잠실 롯데월드몰 1·2층 갤러리아 모티브. 실측 1 stud = 0.3 m (Config.m).
-- LandmarkInterior 가 require 해서 호출(Landmark.layout.hall 좌표). 공용 헬퍼/가구 = InteriorKit, 실물 소품 = Props.
--
--   바닥     : 2.4 m 각 대형 포세린 슬래브(줄눈 0.12 stud = 그라우트 바탕이 0.06 아래로 보임, 톤 변화) + 상점 앞 다크 그래닛 띠.
--   정면 통로 : 폭 9 m. 대형 석재 패널(1.95 × 2.3 m, 리빌 줄눈 + 어두운 바탕) + 스테인리스 걸레받이, 천장 선형 조명·코브·
--              스프링클러·감지기·디퓨저·스피커·CCTV·피난구유도등, 층별 안내 토템, 라이트박스 광고 2, 365 ATM 코너(3 대),
--              소화기·옥내소화전, 우산 비닐 커버기, 매립형 알루미늄 현관 매트, 열린 자동문 4 짝(프레임 + 유리).
--   갤러리아 : 피쿠스 3 그루(Props.tree, 원형 석재 좌대 + 원목 좌석 링 + 화분 + 업라이트), 팝업 키오스크, 안내 데스크,
--              벤치·분리수거함·안내 토템, 메자닌 아래 천장(선형 조명·설비·행잉 안내 사인·피난구유도등·CCTV).
--   메자닌   : 2.4 m 유리 난간 패널 + 스테인리스 핸드레일·베이스 슈, 2층 슬래브 패턴, 다리 2.
--   에스컬레이터: 노란 안전 테두리 디딤판, 콤 플레이트(노란 빗살), 플로어 플레이트, 스커트 브러시, 데크, 외장 패널,
--              뉴얼(손잡이 원형 끝), 비상정지 버튼, 운행 방향 표시, "손잡이를 잡으세요" 안내판.
--   상점 27  : 업종별 집기·상품(패션/아웃도어/아동/남성, 신발/스포츠, 카페/찻집, 베이커리/디저트/젤라토, 꽃, 안경, 서점, 음반,
--              화장품/향수/약국, 주얼리/시계, 리빙, 문구, 전자, 가방, 팝업, 푸드코트, 분식) + 진열창(프레임·문틀·문턱·
--              영업시간 시트) + 간판 글자 + 트랙 조명 + 천장 설비 + 계산대(POS·카드단말·쇼핑백).
--              상품 열(책등·페이싱·접은 옷·안경 벽)은 파트 1 개 + SurfaceGui 색 막대(Frame)로 그려 파트 수를 아낌.
-- z-fighting 규칙: 같은 방향 면은 0.05 stud 이상 띄우거나 상대 파트 속에 묻음. 광원 = IK.light(몰 예산 22).

local Kit = require(script.Parent.Kit)
local IK = require(script.Parent.InteriorKit)
local Props = require(script.Parent.Props)
local P, m2s, rgb, MAT = IK.P, IK.m2s, IK.rgb, IK.MAT
local FRONT, BACK, CYL_UP = IK.FRONT, IK.BACK, IK.CYL_UP
local FACE_PZ, FACE_NZ, FACE_PX, FACE_NX = IK.FACE_PZ, IK.FACE_NZ, IK.FACE_PX, IK.FACE_NX
local SEAT, TABLE_H, C = IK.SEAT, IK.TABLE_H, IK.C
local light, S, D, N, G, VC, sign = IK.light, IK.S, IK.D, IK.N, IK.G, IK.VC, IK.sign
local chair, roundTable, bench, sofa = IK.chair, IK.roundTable, IK.bench, IK.sofa
local TOP = Enum.NormalId.Top
local RIGHT, LEFT = Enum.NormalId.Right, Enum.NormalId.Left

local MallInterior = {}

------------------------------------------------------------------------------------------------------
-- 공용 헬퍼
------------------------------------------------------------------------------------------------------
local function pick<T>(rng: Random, t: { T }): T
	return t[rng:NextInteger(1, #t)]
end
local function jit(rng: Random, c: Color3, a: number): Color3
	local k = 1 + rng:NextNumber(-a, a)
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end
local function dark(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), t)
end
-- 원기둥(축 = cf 의 Y, 기울기 유지). 작은 소품 → 그림자 없음
local function cyl(m: Instance, cf: CFrame, h: number, d: number, col: Color3, mat: Enum.Material, name: string, collide: boolean?): BasePart
	local c = collide == true
	return Kit.part(m, cf * CYL_UP, Vector3.new(h, d, d), { name = name, shape = "Cylinder", material = mat, color = col, collide = c, query = c, shadow = false })
end
-- 가로 원기둥(축 = cf 의 X)
local function hcyl(m: Instance, cf: CFrame, len: number, d: number, col: Color3, mat: Enum.Material, name: string): BasePart
	return Kit.part(m, cf, Vector3.new(len, d, d), { name = name, shape = "Cylinder", material = mat, color = col, collide = false, query = false, shadow = false })
end
local function ell(m: Instance, cf: CFrame, size: Vector3, col: Color3, mat: Enum.Material, name: string): BasePart
	return Kit.ellipsoid(m, cf, size, col, mat, { name = name, collide = false, query = false, shadow = false })
end
local function ball(m: Instance, pos: Vector3, d: number, col: Color3, mat: Enum.Material, name: string): BasePart
	return Kit.ball(m, pos, d, col, mat, { name = name, collide = false, query = false, shadow = false })
end
local function wedge(m: Instance, cf: CFrame, size: Vector3, col: Color3, mat: Enum.Material, name: string): BasePart
	return Kit.wedge(m, cf, size, col, mat, { name = name, collide = false, query = false, shadow = false })
end
-- 투명 캐리어 + 글자(간판 글자 / 유리 시트 / 스티커). 파트 자체는 보이지 않음(감사 도구도 무시)
local function decal(m: Instance, cf: CFrame, w: number, h: number, text: string, col: Color3, glow: boolean?, ppS: number?, font: Enum.Font?): BasePart
	local p = Kit.part(m, cf, Vector3.new(w, h, 0.05), { name = "Decal", material = MAT.SmoothPlastic, color = col, transparency = 1, collide = false, query = false, shadow = false })
	Kit.label(p, FRONT, text, { color = col, glow = glow ~= false, pixelsPerStud = ppS or 40, maxDistance = 400, font = font or Enum.Font.GothamBold })
	return p
end

-- 면 위 색 사각형(Frame) 그림: rects = { {x, y, w, h, Color3} } (0..1, y 는 위에서부터). 책등·상품 페이싱·접은 옷·안경 벽.
local function rectGui(p: BasePart, face: Enum.NormalId, rects: { any }, ppS: number?)
	local g = Instance.new("SurfaceGui")
	g.Name = "Facings"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = ppS or 20
	g.LightInfluence = 1
	g.MaxDistance = 180
	for _, r in rects do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = r[5]
		f.Position = UDim2.fromScale(r[1], r[2])
		f.Size = UDim2.fromScale(r[3], r[4])
		f.Parent = g
	end
	g.Parent = p
end

------------------------------------------------------------------------------------------------------
-- 팔레트
------------------------------------------------------------------------------------------------------
local BOOK_C = { rgb(150, 52, 44), rgb(42, 70, 110), rgb(212, 196, 160), rgb(60, 92, 70), rgb(30, 30, 34), rgb(196, 140, 60), rgb(110, 84, 120), rgb(232, 228, 216), rgb(176, 60, 70), rgb(70, 110, 150), rgb(236, 200, 80) }
local CLOTH: { [string]: { Color3 } } = {
	fashion = { rgb(214, 206, 192), rgb(46, 50, 60), rgb(150, 132, 112), rgb(236, 232, 224), rgb(92, 84, 76), rgb(176, 150, 120), rgb(30, 30, 32) },
	outdoor = { rgb(214, 96, 40), rgb(36, 56, 92), rgb(86, 100, 66), rgb(40, 40, 44), rgb(200, 186, 150), rgb(160, 40, 40), rgb(90, 120, 150) },
	kids = { rgb(250, 200, 210), rgb(190, 222, 240), rgb(255, 230, 160), rgb(200, 236, 200), rgb(240, 240, 236), rgb(250, 160, 120) },
	men = { rgb(40, 46, 64), rgb(90, 92, 98), rgb(30, 30, 32), rgb(170, 140, 104), rgb(220, 218, 212), rgb(110, 60, 50), rgb(70, 80, 70) },
}
local PACK_C = { rgb(196, 40, 44), rgb(30, 70, 150), rgb(250, 196, 40), rgb(36, 120, 70), rgb(240, 240, 236), rgb(232, 110, 40), rgb(120, 60, 140), rgb(40, 40, 44), rgb(236, 140, 170), rgb(90, 170, 220) }
local COSM_C = { rgb(250, 240, 236), rgb(230, 190, 196), rgb(40, 40, 44), rgb(200, 170, 120), rgb(236, 220, 210), rgb(180, 40, 70), rgb(214, 160, 150), rgb(255, 255, 255) }
local HOME_C = { rgb(236, 232, 224), rgb(200, 186, 160), rgb(120, 140, 130), rgb(70, 74, 80), rgb(180, 120, 90), rgb(214, 200, 176), rgb(150, 160, 176) }
local BREAD_C = { rgb(196, 130, 62), rgb(176, 108, 50), rgb(214, 158, 88), rgb(150, 92, 44), rgb(226, 186, 120) }
local FLOWER_C = { rgb(236, 110, 140), rgb(250, 210, 90), rgb(206, 120, 220), rgb(250, 248, 240), rgb(240, 150, 110), rgb(220, 60, 70), rgb(250, 190, 200) }
local GELATO_C = { rgb(250, 240, 210), rgb(110, 70, 50), rgb(236, 130, 150), rgb(160, 210, 120), rgb(250, 220, 90), rgb(240, 160, 90), rgb(200, 170, 230), rgb(250, 250, 246), rgb(150, 100, 70), rgb(220, 90, 90) }
local GLASSES_C = { rgb(24, 24, 26), rgb(80, 52, 36), rgb(120, 90, 60), rgb(190, 160, 90), rgb(140, 140, 146), rgb(30, 40, 60) }
local MED_C = { rgb(240, 240, 236), rgb(36, 140, 80), rgb(30, 90, 170), rgb(220, 60, 50), rgb(250, 200, 60), rgb(150, 200, 230) }
local STONE = { rgb(230, 224, 212), rgb(224, 217, 204), rgb(234, 229, 219), rgb(219, 212, 199), rgb(227, 221, 210) }
local GROUT = rgb(150, 144, 136)
local YELLOW = rgb(250, 200, 30)
local KRAFT = rgb(196, 160, 112)

------------------------------------------------------------------------------------------------------
-- 상품 그림 생성(Frame 사각형)
------------------------------------------------------------------------------------------------------
-- 세로 페이싱(아래 정렬): 같은 SKU 2~5 개 연속 + 가끔 빈 자리, band = 라벨 띠
local function facingRects(rng: Random, L: number, wMin: number, wMax: number, hMin: number, hMax: number, pal: { Color3 }, band: boolean?): { any }
	local out = {}
	local x = 0.04
	while x < L - wMin - 0.04 do
		local w = rng:NextNumber(wMin, wMax)
		local h = rng:NextNumber(hMin, hMax)
		local c = pick(rng, pal)
		local lc = pick(rng, pal)
		if rng:NextNumber() < 0.07 then
			x += w * 1.5
			continue
		end
		for _ = 1, rng:NextInteger(2, 5) do
			if x + w > L - 0.04 then
				break
			end
			local cc = jit(rng, c, 0.04)
			table.insert(out, { x / L, 1 - h, w / L, h, cc })
			if band then
				table.insert(out, { x / L, 1 - h * 0.62, w / L, h * 0.2, lc })
			end
			x += w + 0.03
		end
		x += 0.06
	end
	return out
end
-- 책등(높이·두께 제각각)
local function bookRects(rng: Random, L: number): { any }
	local out = {}
	local x = 0.05
	while x < L - 0.12 do
		if rng:NextNumber() < 0.04 then
			x += rng:NextNumber(0.3, 0.7)
			continue
		end
		local w = math.min(rng:NextNumber(0.08, 0.2), L - 0.05 - x)
		local h = rng:NextNumber(0.62, 0.97)
		table.insert(out, { x / L, 1 - h, w / L, h, jit(rng, pick(rng, BOOK_C), 0.12) })
		x += w + 0.008
	end
	return out
end
-- 접은 옷 더미(층 0.16 stud)
local function stackRects(rng: Random, L: number, H: number, pal: { Color3 }): { any }
	local out = {}
	local x = 0.15
	while x + 1.0 < L - 0.1 do
		local c = pick(rng, pal)
		local sw = rng:NextNumber(0.95, 1.15)
		local n = math.max(2, math.floor(H / 0.16 * rng:NextNumber(0.55, 1.0)))
		for k = 0, n - 1 do
			local y = H - (k + 1) * 0.16
			if y < 0 then
				break
			end
			table.insert(out, { x / L, y / H, sw / L, 0.135 / H, jit(rng, c, 0.05) })
		end
		x += sw + rng:NextNumber(0.25, 0.5)
	end
	return out
end
-- 안경 벽: 아크릴 레일 + 안경(선글라스 = 채운 렌즈, 안경테 = 밝은 렌즈 + 윗테)
local function glassesRects(rng: Random, L: number, H: number, rows: number): { any }
	local out = {}
	for r = 1, rows do
		local yc = (r - 0.5) * H / rows
		table.insert(out, { 0.01, (yc + 0.2) / H, 0.98, 0.05 / H, rgb(206, 208, 212) })
		local x = 0.3
		while x + 0.55 < L - 0.2 do
			local c = pick(rng, GLASSES_C)
			local lh = rng:NextNumber(0.12, 0.17)
			local sun = rng:NextNumber() < 0.45
			local lens = if sun then dark(c, 0.3) else rgb(222, 228, 232)
			for _, lx in { x, x + 0.26 } do
				table.insert(out, { lx / L, (yc - lh / 2) / H, 0.2 / L, lh / H, lens })
			end
			table.insert(out, { x / L, (yc - lh / 2) / H, 0.46 / L, 0.035 / H, c })
			table.insert(out, { (x + 0.2) / L, (yc - lh / 2 + 0.02) / H, 0.06 / L, 0.03 / H, c })
			x += 0.46 + rng:NextNumber(0.28, 0.42)
		end
	end
	return out
end
-- 위에서 본 격자(젤라또 통 / 보석 트레이 / 김밥): cols × rows 칸, 칸마다 색
local function gridRects(rng: Random, cols: number, rows: number, pal: { Color3 }, fill: number, rim: Color3?): { any }
	local out = {}
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local px, pz = 1 / cols, 1 / rows
			if rim then
				table.insert(out, { i * px + px * 0.04, j * pz + pz * 0.04, px * 0.92, pz * 0.92, rim })
			end
			local f = fill * rng:NextNumber(0.85, 1.0)
			table.insert(out, { i * px + px * (1 - f) / 2, j * pz + pz * (1 - f) / 2, px * f, pz * f, jit(rng, pick(rng, pal), 0.06) })
		end
	end
	return out
end
-- 레코드 판(위에서 본 얇은 재킷 모서리)
local function edgeRects(rng: Random, n: number, pal: { Color3 }): { any }
	local out = {}
	for k = 0, n - 1 do
		table.insert(out, { 0.04, (k + 0.15) / n, 0.92, 0.6 / n, jit(rng, pick(rng, pal), 0.1) })
	end
	return out
end

------------------------------------------------------------------------------------------------------
-- 상점 정의
------------------------------------------------------------------------------------------------------
type ShopSpec = { ko: string, en: string, kind: string }
type KindStyle = { wall: Color3, wallMat: Enum.Material, floor: Color3, floorMat: Enum.Material, fascia: Color3, text: Color3, ceil: Color3, track: Color3, lamp: Color3 }

local function ks(wall: Color3, wallMat: Enum.Material, floor: Color3, floorMat: Enum.Material, fascia: Color3, text: Color3, ceil: Color3, track: Color3, lamp: Color3?): KindStyle
	return { wall = wall, wallMat = wallMat, floor = floor, floorMat = floorMat, fascia = fascia, text = text, ceil = ceil, track = track, lamp = lamp or rgb(255, 238, 214) }
end
local WCEIL, DCEIL = rgb(238, 236, 232), rgb(40, 40, 42)
local BLK, WHT = rgb(26, 26, 28), rgb(232, 232, 230)
local KIND: { [string]: KindStyle } = {
	fashion = ks(rgb(236, 233, 228), MAT.Plaster, rgb(176, 172, 166), MAT.Concrete, rgb(22, 22, 24), rgb(250, 250, 250), WCEIL, BLK),
	outdoor = ks(rgb(92, 96, 92), MAT.Concrete, rgb(150, 112, 78), MAT.WoodPlanks, rgb(30, 46, 38), rgb(240, 236, 220), DCEIL, BLK),
	kids = ks(rgb(250, 240, 228), MAT.Plaster, rgb(200, 164, 122), MAT.WoodPlanks, rgb(250, 204, 92), rgb(36, 56, 106), WCEIL, WHT),
	men = ks(rgb(76, 64, 54), MAT.Wood, rgb(126, 104, 86), MAT.WoodPlanks, rgb(30, 34, 44), rgb(232, 216, 182), DCEIL, BLK),
	shoes = ks(rgb(74, 76, 80), MAT.Concrete, rgb(140, 110, 80), MAT.WoodPlanks, rgb(18, 18, 20), rgb(255, 200, 80), DCEIL, BLK),
	sports = ks(rgb(228, 228, 226), MAT.Plaster, rgb(74, 76, 80), MAT.Concrete, rgb(206, 36, 40), rgb(255, 255, 255), DCEIL, BLK),
	cafe = ks(rgb(92, 66, 46), MAT.Wood, rgb(150, 110, 74), MAT.WoodPlanks, rgb(40, 30, 24), rgb(255, 226, 180), rgb(60, 46, 36), BLK, rgb(255, 214, 160)),
	tea = ks(rgb(222, 208, 182), MAT.Plaster, rgb(158, 118, 82), MAT.WoodPlanks, rgb(58, 70, 50), rgb(242, 234, 212), rgb(196, 170, 132), rgb(120, 90, 60), rgb(255, 220, 170)),
	bakery = ks(rgb(236, 216, 180), MAT.Plaster, rgb(196, 170, 140), MAT.CeramicTiles, rgb(120, 70, 40), rgb(255, 236, 200), WCEIL, BLK, rgb(255, 222, 170)),
	dessert = ks(rgb(250, 234, 238), MAT.Plaster, rgb(238, 234, 230), MAT.CeramicTiles, rgb(246, 228, 232), rgb(170, 70, 100), WCEIL, WHT),
	gelato = ks(rgb(236, 248, 244), MAT.Plaster, rgb(228, 224, 218), MAT.Marble, rgb(110, 186, 176), rgb(255, 255, 255), WCEIL, WHT),
	flowers = ks(rgb(84, 112, 80), MAT.Plaster, rgb(150, 140, 126), MAT.Slate, rgb(40, 70, 44), rgb(250, 240, 220), WCEIL, BLK),
	eyewear = ks(rgb(244, 244, 242), MAT.SmoothPlastic, rgb(206, 204, 200), MAT.Marble, rgb(20, 20, 22), rgb(255, 255, 255), WCEIL, WHT, rgb(244, 246, 255)),
	books = ks(rgb(226, 220, 204), MAT.Plaster, rgb(160, 120, 80), MAT.WoodPlanks, rgb(28, 52, 42), rgb(236, 230, 200), WCEIL, BLK),
	records = ks(rgb(44, 44, 48), MAT.Concrete, rgb(120, 96, 74), MAT.WoodPlanks, rgb(20, 20, 22), rgb(250, 130, 70), DCEIL, BLK),
	cosmetics = ks(rgb(246, 236, 238), MAT.Plaster, rgb(238, 236, 234), MAT.Marble, rgb(250, 244, 246), rgb(200, 60, 110), WCEIL, WHT, rgb(255, 246, 250)),
	perfume = ks(rgb(32, 32, 34), MAT.SmoothPlastic, rgb(222, 216, 208), MAT.Marble, rgb(16, 16, 18), rgb(232, 212, 172), DCEIL, BLK),
	pharmacy = ks(rgb(244, 246, 244), MAT.Plaster, rgb(222, 224, 222), MAT.CeramicTiles, rgb(36, 140, 80), rgb(255, 255, 255), WCEIL, WHT, rgb(240, 248, 255)),
	jewelry = ks(rgb(30, 30, 34), MAT.SmoothPlastic, rgb(62, 60, 62), MAT.Marble, rgb(14, 14, 16), rgb(230, 200, 140), DCEIL, BLK),
	watches = ks(rgb(62, 52, 44), MAT.Wood, rgb(72, 68, 66), MAT.Marble, rgb(20, 30, 40), rgb(222, 202, 160), DCEIL, BLK),
	living = ks(rgb(232, 226, 214), MAT.Plaster, rgb(186, 160, 124), MAT.WoodPlanks, rgb(60, 70, 60), rgb(240, 236, 226), WCEIL, BLK),
	stationery = ks(rgb(250, 248, 244), MAT.Plaster, rgb(200, 190, 170), MAT.WoodPlanks, rgb(250, 210, 60), rgb(30, 30, 34), WCEIL, BLK),
	tech = ks(rgb(236, 238, 242), MAT.SmoothPlastic, rgb(206, 208, 212), MAT.Concrete, rgb(240, 240, 244), rgb(30, 30, 34), WCEIL, WHT, rgb(240, 246, 255)),
	bags = ks(rgb(214, 200, 180), MAT.Plaster, rgb(184, 174, 164), MAT.Marble, rgb(110, 70, 46), rgb(250, 236, 210), WCEIL, BLK),
	popup = ks(rgb(255, 214, 120), MAT.Plaster, rgb(240, 236, 230), MAT.SmoothPlastic, rgb(36, 60, 110), rgb(255, 230, 120), WCEIL, WHT),
	food = ks(rgb(56, 58, 62), MAT.CeramicTiles, rgb(120, 116, 110), MAT.CeramicTiles, rgb(196, 54, 42), rgb(255, 244, 220), DCEIL, BLK, rgb(255, 230, 190)),
	snack = ks(rgb(246, 244, 238), MAT.CeramicTiles, rgb(150, 140, 130), MAT.CeramicTiles, rgb(230, 90, 40), rgb(255, 255, 255), WCEIL, WHT, rgb(255, 236, 210)),
}

local function sh_(ko: string, en: string, kind: string): ShopSpec
	return { ko = ko, en = en, kind = kind }
end
-- 줄별 상점 (서→동). L1P 는 가운데 칸(입구 통로)을 건너뜀.
local SHOPS_L1P = { sh_("편집숍", "SELECT SHOP", "fashion"), sh_("신발", "SHOES", "shoes"), sh_("카페", "CAFÉ", "cafe"), sh_("베이커리", "BAKERY", "bakery"), sh_("꽃집", "FLOWERS", "flowers"), sh_("안경", "EYEWEAR", "eyewear") }
local SHOPS_L1N = { sh_("아웃도어", "OUTDOOR", "outdoor"), sh_("서점", "BOOKS", "books"), sh_("향수", "PERFUME", "perfume"), sh_("화장품", "COSMETICS", "cosmetics"), sh_("주얼리", "JEWELRY", "jewelry"), sh_("시계", "WATCHES", "watches"), sh_("디저트", "DESSERT", "dessert") }
local SHOPS_L2P = { sh_("리빙", "LIVING", "living"), sh_("문구", "STATIONERY", "stationery"), sh_("전자", "ELECTRONICS", "tech"), sh_("음반", "RECORDS", "records"), sh_("아동복", "KIDS", "kids"), sh_("스포츠", "SPORTS", "sports"), sh_("푸드코트", "FOOD COURT", "food") }
local SHOPS_L2N = { sh_("남성복", "MEN", "men"), sh_("가방", "BAGS", "bags"), sh_("팝업스토어", "POP-UP", "popup"), sh_("찻집", "TEA HOUSE", "tea"), sh_("약국", "PHARMACY", "pharmacy"), sh_("분식", "SNACK BAR", "snack"), sh_("아이스크림", "GELATO", "gelato") }
-- 2층에서 실제 광원을 받는 상점(나머지 2층은 Neon 띠/주변광)
local LIT_L2 = { ["푸드코트"] = true, ["리빙"] = true, ["전자"] = true, ["찻집"] = true }
local TAGLINE: { [string]: string } = {
	fashion = "F/W 2026\nNEW COLLECTION", outdoor = "TRAIL READY\n가을 산행 컬렉션", kids = "KIDS\n꿈꾸는 아이들", men = "THE TAILORED\nMAN", shoes = "NEW RUNNING\n2026", sports = "MOVE MORE\n더 멀리, 더 빠르게",
	cosmetics = "GLOW SKIN\n수분 크림 1+1", perfume = "EAU DE PARFUM\n시그니처 향", living = "COZY HOME\n가을 홈 스타일링", stationery = "2027 DIARY\n다이어리 입고", tech = "NEW PHONE 17\n사전 예약", bags = "LEATHER\nCOLLECTION", popup = "곰돌이 팝업\n11.01 – 11.30",
}

------------------------------------------------------------------------------------------------------
-- 상점 공용 집기
------------------------------------------------------------------------------------------------------
-- 계산대: 몸통 0.9 m + 상판 + POS(받침·모니터, 직원 쪽 +Z) + 카드단말(손님 쪽) + 종이 쇼핑백
local function counterPOS(sh: any, x: number, z: number, yaw: number, len: number, body: Color3, bodyMat: Enum.Material, top: Color3, topMat: Enum.Material)
	local m = sh.m
	local cf = sh.F(x, 0, z, yaw)
	S(m, cf * CFrame.new(0, 1.55, 0), Vector3.new(len, 3.0, 2.0), body, bodyMat, "CashCounter")
	D(m, cf * CFrame.new(0, 3.11, -0.1), Vector3.new(len + 0.2, 0.12, 2.3), top, topMat, "CounterTop")
	local px = -len / 2 + 1.1
	D(m, cf * CFrame.new(px, 3.35, 0.3), Vector3.new(0.5, 0.36, 0.5), C.black, MAT.SmoothPlastic, "PosBase")
	D(m, cf * CFrame.new(px, 3.95, 0.34) * CFrame.Angles(math.rad(14), 0, 0), Vector3.new(1.25, 0.85, 0.1), rgb(30, 30, 34), MAT.SmoothPlastic, "PosScreen")
	D(m, cf * CFrame.new(px + 1.35, 3.27, -0.55) * CFrame.Angles(math.rad(-18), 0, 0), Vector3.new(0.32, 0.14, 0.52), rgb(40, 42, 46), MAT.SmoothPlastic, "CardTerminal")
	D(m, cf * CFrame.new(len / 2 - 1.0, 3.72, 0.25), Vector3.new(1.05, 1.1, 0.45), KRAFT, MAT.SmoothPlastic, "ShoppingBag")
end

-- 상품 열: cfFront = 선반 윗면 앞 가장자리 가운데(로컬 -Z = 매장 쪽). 파트 1 + 앞면 Frame 그림
local function facings(m: Instance, cfFront: CFrame, L: number, H: number, dep: number, rects: { any }, back: Color3, ppS: number?): BasePart
	local p = D(m, cfFront * CFrame.new(0, H / 2, 0.08 + dep / 2), Vector3.new(L, H, dep), back, MAT.SmoothPlastic, "Facings")
	rectGui(p, FRONT, rects, ppS or 24)
	return p
end

-- 벽 선반 유닛: cf = 벽면 바닥 기준(로컬 -Z = 매장 쪽), ys = 선반 윗면 높이. fill(i, 선반 앞 가장자리 cf, 폭, 높이 여유)
local function shelfUnit(m: Instance, cf: CFrame, w: number, hTop: number, ys: { number }, dep: number, back: Color3, backMat: Enum.Material, shelfC: Color3, fill: (number, CFrame, number, number) -> ())
	D(m, cf * CFrame.new(0, hTop / 2, -0.12), Vector3.new(w, hTop, 0.24), back, backMat, "ShelfBack")
	for i, y in ys do
		D(m, cf * CFrame.new(0, y - 0.06, -0.24 - dep / 2), Vector3.new(w - 0.2, 0.12, dep), shelfC, MAT.SmoothPlastic, "Shelf")
		local nextY = ys[i + 1] or hTop
		fill(i, cf * CFrame.new(0, y, -0.24 - dep), w - 0.6, nextY - y - 0.3)
	end
end

-- 옷걸이에 촘촘히 건 옷(사이드 행): cfRail = 봉 중심(로컬 X = 봉 방향), 파트 1 + 옷 단면 줄무늬
local function garments(m: Instance, cfRail: CFrame, L: number, H: number, pal: { Color3 }, rng: Random, both: boolean)
	D(m, cfRail * CFrame.new(0, -0.15, 0), Vector3.new(L, 0.1, 1.25), rgb(86, 64, 46), MAT.Wood, "Hangers")
	local p = D(m, cfRail * CFrame.new(0, -0.2 - H / 2, 0), Vector3.new(L, H, 1.45), dark(pick(rng, pal), 0.3), MAT.Fabric, "Garments")
	local rects = {}
	local x = 0.02
	while x < L - 0.08 do
		local w = math.min(rng:NextNumber(0.1, 0.24), L - 0.02 - x)
		table.insert(rects, { x / L, 0, w / L, rng:NextNumber(0.88, 1.0), jit(rng, pick(rng, pal), 0.08) })
		x += w + 0.012
	end
	rectGui(p, FRONT, rects, 24)
	if both then
		rectGui(p, BACK, rects, 24)
	end
end

-- 접은 옷 한 더미(테이블 위): 층 줄무늬 + 윗면 색
local function foldedStack(m: Instance, cf: CFrame, rng: Random, pal: { Color3 })
	local n = rng:NextInteger(4, 7)
	local h = n * 0.15
	local c = pick(rng, pal)
	local p = D(m, cf * CFrame.new(0, h / 2, 0), Vector3.new(1.1, h, 0.95), dark(c, 0.35), MAT.Fabric, "FoldedStack")
	local rects = {}
	for k = 0, n - 1 do
		table.insert(rects, { 0, k / n, 1, 0.8 / n, jit(rng, c, 0.06) })
	end
	rectGui(p, FRONT, rects, 30)
	rectGui(p, TOP, { { 0, 0, 1, 1, c } }, 10)
end

-- 마네킹(1.8 m): 받침 + 다리 2 + 몸통(옷) + 머리
local function mannequin(m: Instance, cf: CFrame, top: Color3, bottom: Color3)
	cyl(m, cf * CFrame.new(0, 0.06, 0), 0.12, 1.5, rgb(60, 60, 64), MAT.Metal, "MannequinBase")
	for _, sx in { -0.24, 0.24 } do
		D(m, cf * CFrame.new(sx, 1.58, 0), Vector3.new(0.42, 2.96, 0.48), bottom, MAT.Fabric, "MannequinLeg")
	end
	ell(m, cf * CFrame.new(0, 3.95, 0), Vector3.new(1.55, 2.4, 0.9), top, MAT.Fabric, "MannequinTorso")
	ball(m, (cf * CFrame.new(0, 5.5, 0)).Position, 0.78, rgb(238, 234, 228), MAT.SmoothPlastic, "MannequinHead")
end

-- 운동화 1 짝(진열용 한 짝): 흰 밑창 + 경사진 갑피
local function shoe(m: Instance, cf: CFrame, col: Color3, sole: boolean?)
	if sole then
		D(m, cf * CFrame.new(0, 0.06, 0), Vector3.new(0.44, 0.12, 1.08), rgb(240, 238, 232), MAT.Rubber, "ShoeSole")
		wedge(m, cf * CFrame.new(0, 0.32, 0.03), Vector3.new(0.4, 0.42, 1.0), col, MAT.Fabric, "Shoe")
	else
		wedge(m, cf * CFrame.new(0, 0.25, 0), Vector3.new(0.42, 0.5, 1.05), col, MAT.Fabric, "Shoe")
	end
end

-- 빵 한 개(종류별 모양)
local function bread(m: Instance, cf: CFrame, rng: Random)
	local t = rng:NextInteger(1, 4)
	local c = jit(rng, pick(rng, BREAD_C), 0.06)
	if t == 1 then
		ell(m, cf * CFrame.new(0, 0.3, 0), Vector3.new(1.15, 0.62, 1.1), c, MAT.SmoothPlastic, "Boule")
	elseif t == 2 then
		ell(m, cf * CFrame.new(0, 0.22, 0) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Vector3.new(1.9, 0.44, 0.5), c, MAT.SmoothPlastic, "Baguette")
	elseif t == 3 then
		ell(m, cf * CFrame.new(0, 0.2, 0), Vector3.new(0.85, 0.42, 0.8), dark(c, 0.1), MAT.SmoothPlastic, "Bun")
	else
		ell(m, cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector3.new(1.05, 0.38, 0.55), rgb(214, 150, 70), MAT.SmoothPlastic, "Croissant")
	end
end

-- 테이블(받침 + 상판), 상판 윗면 높이 h
local function table_(m: Instance, cf: CFrame, w: number, d: number, h: number, topC: Color3, topMat: Enum.Material, baseC: Color3)
	S(m, cf * CFrame.new(0, (h - 0.1) / 2, 0), Vector3.new(math.max(0.6, w - 1.0), h - 0.1, math.max(0.6, d - 1.0)), baseC, MAT.Wood, "TableBase")
	D(m, cf * CFrame.new(0, h - 0.1, 0), Vector3.new(w, 0.2, d), topC, topMat, "TableTop")
end

-- 스툴(좌면 높이 hgt): 원통 좌면 + 기둥
local function stool(m: Instance, cf: CFrame, col: Color3, hgt: number?)
	local hs = hgt or SEAT
	VC(m, cf * CFrame.new(0, hs - 0.1, 0), 0.2, 1.25, col, MAT.Wood, true, "StoolSeat")
	VC(m, cf * CFrame.new(0, (hs - 0.2) / 2, 0), hs - 0.2, 0.22, C.black, MAT.Metal, false, "StoolLeg")
end

------------------------------------------------------------------------------------------------------
-- 업종별 집기 (sh.F(x, y, z, yaw) = 상점 로컬: x 폭(±W/2), z 진열창(0) → 뒷벽(Dp), y = 갤러리아 바닥(상점 바닥 0.05))
------------------------------------------------------------------------------------------------------
local function fxFashion(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	local pal = CLOTH[sh.kind] or CLOTH.fashion
	-- 1) 왼쪽 벽 사이드 행거(상의 / 아우터)
	local z0, z1 = 5.5, Dp - 5.0
	local len = z1 - z0
	local cfW = F(-WL, 0, (z0 + z1) / 2, FACE_PX)
	hcyl(m, cfW * CFrame.new(0, 5.7, -1.0), len, 0.14, C.steel, MAT.Metal, "Rail")
	for _, ex in { -1, 1 } do
		D(m, cfW * CFrame.new(ex * (len / 2 - 0.3), 5.7, -0.55), Vector3.new(0.12, 0.12, 1.1), C.steel, MAT.Metal, "RailBracket")
	end
	garments(m, cfW * CFrame.new(-len / 4, 5.7, -1.0), len / 2 - 0.4, 2.6, pal, rng, false)
	garments(m, cfW * CFrame.new(len / 4, 5.7, -1.0), len / 2 - 0.4, 3.8, pal, rng, false)
	-- 2) 오른쪽 벽: 접은 옷 선반 3 단
	local shelfC = if sh.kind == "men" or sh.kind == "outdoor" then rgb(58, 46, 38) else C.oak
	shelfUnit(m, F(WL, 0, 12.5, FACE_NX), 11, 9.0, { 2.2, 4.8, 7.4 }, 1.25, dark(sh.K.wall, 0.08), sh.K.wallMat, shelfC, function(_i, cf, w, h)
		local hh = math.min(h, 1.3)
		facings(m, cf, w, hh, 1.0, stackRects(rng, w, hh, pal), dark(shelfC, 0.4), 30)
	end)
	-- 3) 뒷벽: 그래픽 라이트박스 + 접은 옷 좌대, 계산대, 피팅룸 + 거울
	sign(m, F(1.0, 9.8, Dp - 0.12), Vector3.new(12, 5.4, 0.2), rgb(214, 206, 196), MAT.Neon, TAGLINE[sh.kind] or "NEW SEASON", rgb(40, 38, 36), 20)
	S(m, F(1.0, 0.85, Dp - 1.6), Vector3.new(10, 1.6, 2.6), dark(sh.K.wall, 0.15), MAT.SmoothPlastic, "Plinth")
	facings(m, F(1.0, 1.65, Dp - 2.6), 9.4, 0.9, 1.6, stackRects(rng, 9.4, 0.9, pal), dark(pick(rng, pal), 0.4), 30)
	counterPOS(sh, -WL + 5.2, Dp - 3.4, 0, 6.5, if sh.kind == "men" then rgb(46, 38, 32) else rgb(30, 30, 32), MAT.Wood, C.marble, MAT.Marble)
	D(m, F(WL - 6, 4.0, Dp - 3.25), Vector3.new(0.3, 8.0, 6.5), dark(sh.K.wall, 0.05), MAT.SmoothPlastic, "FittingWall")
	D(m, F(WL - 3, 3.95, Dp - 6.35), Vector3.new(5.6, 7.5, 0.25), rgb(120, 112, 100), MAT.Fabric, "FittingCurtain")
	local fs = D(m, F(WL - 3, 8.3, Dp - 6.4), Vector3.new(3.4, 0.6, 0.1), rgb(30, 30, 32), MAT.SmoothPlastic, "FittingSign")
	Kit.label(fs, FRONT, "FITTING ROOM 피팅룸", { color = rgb(240, 240, 236), glow = true, pixelsPerStud = 40, maxDistance = 160 })
	D(m, F(WL - 6.19, 3.7, Dp - 3.25), Vector3.new(0.08, 5.8, 2.0), rgb(206, 214, 218), MAT.Glass, "Mirror", 0.4)
	-- 4) 가운데: 네스팅 테이블 2 + 접은 옷
	table_(m, F(-2.2, 0, 10.5), 6.5, 3.6, 2.65, C.oak, MAT.Wood, rgb(60, 50, 42))
	table_(m, F(3.4, 0, 13.2), 4.6, 3.0, 1.7, C.oak, MAT.Wood, rgb(60, 50, 42))
	for k = -1, 1 do
		foldedStack(m, F(-2.2 + k * 1.9, 2.65, 10.5 + (if k == 0 then 0.6 else -0.5)), rng, pal)
	end
	for k = -1, 1, 2 do
		foldedStack(m, F(3.4 + k * 1.1, 1.7, 13.2), rng, pal)
	end
	-- 5) 1층: 가운데 이동식 행거(양면)
	if sh.l1 then
		local rcf = F(0.5, 0, 18.5)
		for _, ex in { -1, 1 } do
			D(m, rcf * CFrame.new(ex * 3.6, 2.75, 0), Vector3.new(0.14, 5.4, 0.14), C.steel, MAT.Metal, "RackPost")
			D(m, rcf * CFrame.new(ex * 3.6, 0.1, 0), Vector3.new(0.2, 0.1, 1.6), C.steel, MAT.Metal, "RackFoot")
		end
		hcyl(m, rcf * CFrame.new(0, 5.3, 0), 7.4, 0.14, C.steel, MAT.Metal, "Rail")
		garments(m, rcf * CFrame.new(0, 5.3, 0), 6.8, 2.8, pal, rng, true)
	end
end

local function fxShoes(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	local sports = sh.kind == "sports"
	local SHOE_C = { rgb(240, 240, 236), rgb(30, 30, 32), rgb(200, 60, 50), rgb(60, 90, 160), rgb(230, 200, 60), rgb(120, 130, 120), rgb(236, 120, 60) }
	-- 1) 뒷벽 슈월: 패널 + 떠 있는 선반 3 단 × 5
	local cfB = F(0, 0, Dp)
	D(m, cfB * CFrame.new(0, 6.2, -0.12), Vector3.new(18, 8.6, 0.24), if sports then rgb(30, 30, 32) else rgb(170, 130, 92), if sports then MAT.SmoothPlastic else MAT.Wood, "ShoeWall")
	for r = 0, 2 do
		local y = 3.3 + r * 2.4
		D(m, cfB * CFrame.new(0, y - 0.06, -0.24 - 0.65), Vector3.new(16.6, 0.12, 1.3), rgb(240, 240, 236), MAT.SmoothPlastic, "ShoeShelf")
		for k = 0, 4 do
			shoe(m, cfB * CFrame.new(-6.4 + k * 3.2, y, -0.9) * CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), 0), pick(rng, SHOE_C), false)
		end
	end
	local hs = sign(m, cfB * CFrame.new(0, 11.4, -0.15), Vector3.new(10, 1.6, 0.1), rgb(18, 18, 20), MAT.SmoothPlastic, TAGLINE[sh.kind] or "NEW", rgb(255, 255, 255), 30)
	hs.Name = "WallHeader"
	-- 2) 왼쪽 벽: 신발 상자 재고 벽
	local box = D(m, F(-WL + 0.7, 3.55, 13.5), Vector3.new(1.2, 7.0, 10.5), rgb(60, 50, 40), MAT.Cardboard, "ShoeBoxes")
	local rects = {}
	for r = 0, 13 do
		local x = rng:NextNumber(-0.05, 0)
		while x < 1 do
			local w = rng:NextNumber(0.09, 0.11)
			table.insert(rects, { x, r / 14, math.min(w - 0.005, 1 - x), 1 / 14 - 0.006, jit(rng, pick(rng, { rgb(236, 110, 40), rgb(30, 30, 32), rgb(236, 234, 228), rgb(196, 40, 44), rgb(70, 110, 170) }), 0.06) })
			x += w
		end
	end
	rectGui(box, RIGHT, rects, 16)
	-- 3) 시착 벤치 2 + 바닥 거울 + 디스플레이 큐브
	bench(m, F(-2.5, 0, 12.5), 6, C.leather)
	bench(m, F(3.5, 0, 17.5), 5, rgb(40, 40, 44))
	D(m, F(WL - 0.3, 2.4, 9.0) * CFrame.Angles(0, 0, math.rad(-8)), Vector3.new(0.12, 4.6, 2.0), rgb(206, 214, 218), MAT.Glass, "FloorMirror", 0.4)
	S(m, F(3.5, 1.25, 9.5), Vector3.new(2.4, 2.4, 2.4), rgb(240, 240, 236), MAT.SmoothPlastic, "DisplayCube")
	shoe(m, F(3.0, 2.45, 9.5, 0.4), pick(rng, SHOE_C), true)
	shoe(m, F(4.0, 2.45, 9.4, -0.3), pick(rng, SHOE_C), true)
	-- 4) 오른쪽 벽: (스포츠) 유니폼 페이스아웃 + 공 바스켓 / (신발) 슈케어 선반
	if sports then
		local cfR = F(WL, 0, 14, FACE_NX)
		D(m, cfR * CFrame.new(0, 6.6, -0.5), Vector3.new(7.5, 0.12, 0.12), C.steel, MAT.Metal, "FaceOutBar")
		for k = -1, 1 do
			D(m, cfR * CFrame.new(k * 2.4, 5.2, -0.55), Vector3.new(1.9, 2.6, 0.18), pick(rng, { rgb(200, 36, 40), rgb(30, 60, 140), rgb(240, 240, 236) }), MAT.Fabric, "Jersey")
		end
		G(m, F(WL - 2.2, 1.0, 20.5), Vector3.new(2.4, 1.9, 2.4), rgb(150, 150, 156), 0.55, true, "BallBin")
		for k = 0, 2 do
			ball(m, (F(WL - 2.8 + k * 0.6, 1.95 + (k % 2) * 0.3, 20.5 + (k - 1) * 0.5)).Position, 0.75, pick(rng, { rgb(236, 120, 40), rgb(240, 240, 236), rgb(30, 30, 32) }), MAT.SmoothPlastic, "Ball")
		end
	else
		shelfUnit(m, F(WL, 0, 15, FACE_NX), 6, 7.0, { 3.0, 5.0 }, 1.0, rgb(54, 54, 58), MAT.SmoothPlastic, rgb(230, 230, 228), function(_i, cf, w, h)
			facings(m, cf, w, math.min(h, 0.9), 0.6, facingRects(rng, w, 0.3, 0.5, 0.55, 0.95, PACK_C, true), rgb(40, 40, 42))
		end)
	end
	counterPOS(sh, WL - 4.6, Dp - 3.3, 0, 6.5, rgb(30, 30, 32), MAT.SmoothPlastic, rgb(170, 130, 92), MAT.Wood)
end

local function fxCafe(sh: any)
	local m, F, rng, WL, Dp, CH = sh.m, sh.F, sh.rng, sh.WL, sh.Dp, sh.CH
	local tea = sh.kind == "tea"
	local wood = if tea then rgb(150, 112, 74) else rgb(70, 50, 36)
	-- 1) 앞 카운터 + 상판
	local cx, cz, cl = -2.0, Dp - 5.4, 17.0
	S(m, F(cx, 1.6, cz), Vector3.new(cl, 3.1, 2.4), wood, MAT.Wood, "Counter")
	D(m, F(cx, 3.22, cz - 0.1), Vector3.new(cl + 0.3, 0.14, 2.8), if tea then rgb(96, 70, 48) else C.marble, if tea then MAT.Wood else MAT.Marble, "CounterTop")
	-- 2) 페이스트리 쇼케이스(왼쪽 끝)
	local px = cx - cl / 2 + 2.6
	G(m, F(px, 4.44, cz - 0.1), Vector3.new(4.6, 2.3, 2.4), rgb(220, 232, 240), 0.6, false, "PastryCase")
	N(m, F(px, 4.42, cz - 0.1), Vector3.new(4.3, 0.08, 2.1), rgb(255, 230, 190), "CaseShelf")
	for k = 0, 5 do
		local lx = px - 1.5 + (k % 3) * 1.5
		local ly = if k < 3 then 3.29 else 4.46
		if k % 2 == 0 then
			ell(m, F(lx, ly + 0.2, cz - 0.3, rng:NextNumber(0, 3)), Vector3.new(0.95, 0.4, 0.55), rgb(214, 150, 70), MAT.SmoothPlastic, "Croissant")
		else
			VC(m, F(lx, ly + 0.3, cz - 0.3), 0.6, 0.85, pick(rng, { rgb(250, 240, 230), rgb(110, 70, 50), rgb(240, 180, 190) }), MAT.SmoothPlastic, false, "Cake")
		end
	end
	-- 3) 에스프레소 머신(그룹 2) + 컵 + 그라인더 + POS
	local ex = cx + 2.5
	D(m, F(ex, 4.08, cz), Vector3.new(2.8, 1.6, 1.6), C.steel, MAT.Metal, "Espresso", 0.25)
	D(m, F(ex, 4.98, cz + 0.1), Vector3.new(2.4, 0.22, 1.2), rgb(250, 250, 248), MAT.SmoothPlastic, "CupRow")
	for _, gx in { -0.7, 0.7 } do
		cyl(m, F(ex + gx, 3.62, cz + 0.95), 0.35, 0.36, C.black, MAT.Metal, "GroupHead")
	end
	D(m, F(ex + 2.6, 4.08, cz + 0.3), Vector3.new(0.7, 1.6, 0.9), rgb(30, 30, 32), MAT.Metal, "Grinder")
	cyl(m, F(ex + 2.6, 5.27, cz + 0.3), 0.8, 0.7, rgb(110, 70, 44), MAT.Glass, "Hopper")
	D(m, F(ex + 5.0, 3.47, cz - 0.2), Vector3.new(0.5, 0.36, 0.5), C.black, MAT.SmoothPlastic, "PosBase")
	D(m, F(ex + 5.0, 4.05, cz - 0.15) * CFrame.Angles(math.rad(-14), 0, 0), Vector3.new(1.2, 0.85, 0.1), rgb(30, 30, 34), MAT.SmoothPlastic, "PosScreen")
	-- 4) 백바(뒷벽): 하부장 + 선반 2 + 원두/컵 + 메뉴판 2
	S(m, F(cx, 1.55, Dp - 1.05), Vector3.new(cl, 3.0, 2.0), wood, MAT.Wood, "BackBar")
	for i, y in { 5.9, 7.5 } do
		D(m, F(cx, y - 0.06, Dp - 0.5), Vector3.new(cl - 2, 0.12, 1.0), if tea then rgb(120, 90, 60) else rgb(30, 30, 32), MAT.Wood, "Shelf")
		facings(m, F(cx, y, Dp - 1.0), cl - 3, 0.9, 0.7, facingRects(rng, cl - 3, 0.35, 0.6, 0.5, 0.95, if i == 1 then { rgb(250, 250, 248), rgb(236, 232, 224), rgb(60, 60, 64) } else { KRAFT, rgb(40, 40, 42), rgb(150, 60, 40), rgb(60, 90, 70) }, i == 2), dark(wood, 0.3))
	end
	local menuC = if tea then rgb(60, 70, 50) else rgb(24, 24, 26)
	sign(m, F(cx - 4.0, 10.4, Dp - 0.12), Vector3.new(7.2, 3.6, 0.12), menuC, MAT.SmoothPlastic, if tea then "TEA  차\n녹차 5,000\n보이차 6,000\n유자차 5,500\n대추차 6,500" else "COFFEE  커피\n아메리카노 4,500\n카페라떼 5,000\n바닐라라떼 5,500\n콜드브루 5,000", rgb(255, 236, 204), 30)
	sign(m, F(cx + 4.0, 10.4, Dp - 0.12), Vector3.new(7.2, 3.6, 0.12), menuC, MAT.SmoothPlastic, if tea then "DESSERT  다과\n약과 3,000\n인절미 4,500\n양갱 3,500\n떡 세트 9,000" else "NON-COFFEE  음료\n말차라떼 5,500\n자몽에이드 6,000\n밀크티 5,500\n딸기라떼 6,000", rgb(255, 236, 204), 30)
	-- 5) 펜던트 조명(카운터 위)
	if sh.l1 then
		for _, gx in { -4.5, 0, 4.5 } do
			D(m, F(cx + gx, (CH + 9.0) / 2, cz), Vector3.new(0.05, CH - 9.0, 0.05), C.black, MAT.Metal, "PendantCord")
			cyl(m, F(cx + gx, 8.7, cz), 0.7, 1.2, rgb(150, 112, 70), MAT.Metal, "PendantShade")
			ball(m, (F(cx + gx, 8.3, cz)).Position, 0.5, rgb(255, 214, 160), MAT.Neon, "PendantBulb")
		end
	end
	-- 6) 좌석: 긴 공용 테이블 + 스툴 4, 원탁 + 의자 2
	table_(m, F(4.5, 0, 12.0), 9.0, 3.2, TABLE_H, if tea then rgb(120, 86, 56) else C.oak, MAT.Wood, rgb(40, 34, 30))
	for k = 0, 3 do
		stool(m, F(4.5 + (if k % 2 == 0 then -2.4 else 2.4), 0, 12.0 + (if k < 2 then -2.5 else 2.5)), if tea then rgb(150, 112, 74) else C.oak)
	end
	if sh.l1 then
		roundTable(m, F(-8.8, 0, 11.0), m2s(0.7), TABLE_H, C.marble, MAT.Marble)
		chair(m, F(-8.8, 0, 8.6, math.pi), rgb(60, 44, 34))
		chair(m, F(-8.8, 0, 13.4), rgb(60, 44, 34))
	end
end

local function fxBakery(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	local dessert = sh.kind == "dessert"
	-- 1) 가운데 빵 아일랜드(트레이 4 × 빵 3) / 디저트: 케이크 스탠드 테이블
	local ix, iz = -2.0, 11.5
	S(m, F(ix, 1.3, iz), Vector3.new(8.4, 2.5, 4.2), if dessert then rgb(250, 246, 244) else C.oak, MAT.Wood, "Island")
	D(m, F(ix, 2.62, iz), Vector3.new(9.0, 0.16, 4.8), if dessert then C.marble else rgb(214, 190, 150), if dessert then MAT.Marble else MAT.Wood, "IslandTop")
	if dessert then
		for k = -1, 1 do
			VC(m, F(ix + k * 2.8, 3.15, iz), 0.9, 0.3, C.steel, MAT.Metal, false, "CakeStandStem")
			VC(m, F(ix + k * 2.8, 3.63, iz), 0.08, 2.0, rgb(250, 250, 248), MAT.SmoothPlastic, false, "CakePlate")
			VC(m, F(ix + k * 2.8, 4.12, iz), 0.9, 1.5, pick(rng, { rgb(250, 240, 230), rgb(110, 70, 50), rgb(240, 180, 190), rgb(200, 230, 200) }), MAT.SmoothPlastic, false, "Cake")
		end
	else
		for i = 0, 3 do
			local tx, tz = ix + (if i % 2 == 0 then -2.2 else 2.2), iz + (if i < 2 then -1.15 else 1.15)
			D(m, F(tx, 2.76, tz), Vector3.new(4.0, 0.12, 2.0), rgb(150, 110, 70), MAT.Wood, "BreadTray")
			for k = -1, 1 do
				bread(m, F(tx + k * 1.25, 2.82, tz), rng)
			end
		end
	end
	-- 2) 뒷벽 빵 선반 3 단 × 4 개 + 상단 사인
	shelfUnit(m, F(-2.0, 0, Dp), 15, 8.4, { 2.4, 4.6, 6.8 }, 1.6, rgb(150, 112, 74), MAT.Wood, rgb(170, 130, 88), function(_i, cf, w, _h)
		for k = 0, 3 do
			if dessert then
				VC(m, cf * CFrame.new(-w / 2 + 1.6 + k * (w - 3.2) / 3, 0.4, 0.8), 0.8, 1.3, pick(rng, { rgb(250, 230, 236), rgb(110, 70, 50), rgb(250, 240, 210), rgb(200, 230, 200) }), MAT.SmoothPlastic, false, "GiftBox")
			else
				bread(m, cf * CFrame.new(-w / 2 + 1.6 + k * (w - 3.2) / 3, 0, 0.8), rng)
			end
		end
	end)
	sign(m, F(-2.0, 10.4, Dp - 0.12), Vector3.new(12, 2.0, 0.12), sh.K.fascia, MAT.SmoothPlastic, if dessert then "PÂTISSERIE  케이크 · 마카롱" else "매일 아침 굽는 빵  FRESH DAILY", sh.K.text, 30)
	-- 3) 냉장 쇼케이스(오른쪽, 매장 쪽을 봄) + 케이크 4
	local cfS = F(WL - 1.6, 0, 13.0, FACE_NX)
	S(m, cfS * CFrame.new(0, 1.4, 0), Vector3.new(6.4, 2.7, 2.6), rgb(240, 240, 236), MAT.SmoothPlastic, "Showcase")
	G(m, cfS * CFrame.new(0, 3.75, 0), Vector3.new(6.4, 2.0, 2.6), rgb(220, 232, 240), 0.6, false, "ShowcaseGlass")
	N(m, cfS * CFrame.new(0, 4.62, 0.2), Vector3.new(6.0, 0.08, 1.8), rgb(255, 244, 226), "ShowcaseLight")
	for k = 0, 3 do
		VC(m, cfS * CFrame.new(-2.3 + k * 1.55, 3.18, 0), 0.75, 1.1, pick(rng, { rgb(250, 240, 230), rgb(110, 70, 50), rgb(240, 180, 190), rgb(250, 220, 120) }), MAT.SmoothPlastic, false, "Cake")
	end
	-- 4) 트레이·집게 스테이션 + 계산대
	S(m, F(-WL + 1.6, 1.5, 6.0), Vector3.new(2.6, 2.9, 1.8), C.oak, MAT.Wood, "TrayStation")
	D(m, F(-WL + 1.6, 3.1, 6.0), Vector3.new(1.7, 0.3, 1.3), rgb(150, 110, 70), MAT.Wood, "TrayStack")
	D(m, F(-WL + 1.6, 3.32, 5.8) * CFrame.Angles(0, 0.4, 0), Vector3.new(0.12, 0.1, 1.0), C.steel, MAT.Metal, "Tongs")
	counterPOS(sh, WL - 4.6, Dp - 3.0, 0, 6.6, rgb(240, 240, 236), MAT.SmoothPlastic, C.oak, MAT.Wood)
end

local function fxGelato(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	-- 디핑 케이비닛: 몸통 + 통(위에서 본 14 색) + 기울어진 유리 + 위 조명
	local cz = Dp - 6.0
	S(m, F(-1, 1.45, cz), Vector3.new(13, 2.8, 3.2), rgb(250, 250, 248), MAT.SmoothPlastic, "GelatoCabinet")
	local tubs = D(m, F(-1.5, 2.95, cz + 0.1), Vector3.new(10.4, 0.3, 2.4), rgb(200, 202, 206), MAT.Metal, "GelatoTubs")
	rectGui(tubs, TOP, gridRects(rng, 7, 2, GELATO_C, 0.86, rgb(210, 212, 216)), 16)
	G(m, F(-1, 3.75, cz - 1.25) * CFrame.Angles(math.rad(-35), 0, 0), Vector3.new(13, 1.6, 0.14), rgb(226, 236, 240), 0.55, false, "SneezeGlass")
	D(m, F(4.6, 3.03, cz + 1.0), Vector3.new(0.5, 0.36, 0.5), C.black, MAT.SmoothPlastic, "PosBase")
	D(m, F(4.6, 3.6, cz + 1.05) * CFrame.Angles(math.rad(14), 0, 0), Vector3.new(1.2, 0.85, 0.1), rgb(30, 30, 34), MAT.SmoothPlastic, "PosScreen")
	sign(m, F(-1, 9.4, Dp - 0.12), Vector3.new(11, 3.4, 0.12), rgb(110, 186, 176), MAT.Neon, "GELATO  젤라또\n싱글 4,500 · 더블 6,500 · 트리플 8,500", rgb(255, 255, 255), 30)
	shelfUnit(m, F(-1, 0, Dp), 10, 6.6, { 5.2 }, 1.0, rgb(236, 230, 220), MAT.SmoothPlastic, rgb(240, 240, 236), function(_i, cf, w, _h)
		facings(m, cf, w, 0.9, 0.7, facingRects(rng, w, 0.5, 0.7, 0.6, 0.9, { rgb(214, 170, 110), rgb(250, 250, 246), rgb(110, 186, 176) }, true), rgb(200, 196, 190))
	end)
	-- 좌석 + 파인트 냉동고
	for k, p in { { -8, 10.5 }, { 3, 11.5 } } do
		roundTable(m, F(p[1], 0, p[2]), m2s(0.6), TABLE_H, rgb(250, 250, 248), MAT.SmoothPlastic)
		stool(m, F(p[1] - 2.0, 0, p[2]), rgb(110, 186, 176))
		stool(m, F(p[1] + 2.0, 0, p[2] + (if k == 1 then 0.4 else -0.4)), rgb(250, 220, 90))
	end
	S(m, F(WL - 2, 1.5, 9), Vector3.new(2.6, 2.9, 5.0), rgb(250, 250, 248), MAT.SmoothPlastic, "Freezer")
	local lid = G(m, F(WL - 2, 3.12, 9), Vector3.new(2.3, 0.14, 4.6), rgb(220, 232, 240), 0.5, false, "FreezerLid")
	lid.Name = "FreezerLid"
	local pints = D(m, F(WL - 2, 2.75, 9), Vector3.new(2.2, 0.5, 4.4), rgb(230, 230, 228), MAT.SmoothPlastic, "Pints")
	rectGui(pints, TOP, gridRects(rng, 4, 8, { rgb(110, 186, 176), rgb(250, 240, 210), rgb(110, 70, 50), rgb(236, 130, 150) }, 0.9), 16)
end

local function fxFlowers(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	-- 1) 뒷벽 3 단 스탠드 + 양동이 꽃다발
	for i, st in { { 1.4, 6.0 }, { 2.8, 4.0 }, { 4.2, 2.0 } } do
		S(m, F(-1.5, st[1] / 2, Dp - st[2] / 2), Vector3.new(16, st[1], st[2]), rgb(120, 92, 64), MAT.WoodPlanks, "FlowerStep")
		for k = 0, 2 do
			local bx, bz = -1.5 + (k - 1) * 5.0 + (i - 2) * 0.6, Dp - st[2] + 1.0
			VC(m, F(bx, st[1] + 0.75, bz), 1.5, 1.5, rgb(170, 172, 176), MAT.Metal, false, "Bucket")
			local c = pick(rng, FLOWER_C)
			ell(m, F(bx, st[1] + 2.1, bz) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector3.new(2.3, 1.5, 2.0), c, MAT.Fabric, "Bouquet")
			if k == 1 then
				ell(m, F(bx + 0.5, st[1] + 2.5, bz + 0.3), Vector3.new(1.2, 1.4, 1.0), rgb(70, 110, 60), MAT.Grass, "Greens")
			end
		end
	end
	-- 2) 왼쪽 벽 꽃 냉장고(유리문)
	local cfF = F(-WL, 0, 13.0, FACE_PX)
	S(m, cfF * CFrame.new(0, 4.1, -0.9), Vector3.new(6.2, 8.0, 1.8), rgb(230, 232, 234), MAT.Metal, "FlowerCooler")
	G(m, cfF * CFrame.new(0, 4.1, -1.85), Vector3.new(5.6, 7.2, 0.14), rgb(220, 236, 240), 0.55, false, "CoolerDoor")
	N(m, cfF * CFrame.new(0, 7.75, -1.4), Vector3.new(5.4, 0.1, 0.4), rgb(240, 248, 255), "CoolerLight")
	for k = -1, 1, 2 do
		ell(m, cfF * CFrame.new(k * 1.5, 4.6, -1.3), Vector3.new(2.0, 1.6, 0.9), pick(rng, FLOWER_C), MAT.Fabric, "CoolerFlowers")
	end
	-- 3) 작업대(포장지 롤 + 포장 중 꽃다발) + 계산대
	table_(m, F(5.5, 0, 12.0), 6.0, 3.0, 3.0, rgb(200, 176, 140), MAT.Wood, rgb(90, 70, 54))
	hcyl(m, F(5.5, 3.3, 13.0), 5.0, 0.6, KRAFT, MAT.SmoothPlastic, "PaperRoll")
	D(m, F(4.6, 2.95, 11.8) * CFrame.Angles(0, 0.3, 0), Vector3.new(2.2, 0.06, 1.6), rgb(236, 226, 210), MAT.SmoothPlastic, "WrapSheet")
	ell(m, F(4.6, 3.6, 11.8), Vector3.new(1.4, 1.1, 1.2), pick(rng, FLOWER_C), MAT.Fabric, "Bouquet")
	counterPOS(sh, WL - 4.6, Dp - 3.0, 0, 6.0, rgb(90, 70, 54), MAT.Wood, rgb(200, 176, 140), MAT.Wood)
	-- 4) 관엽(피들리프) 1
	Props.fiddle(m, F(-WL + 2.2, 0.05, 6.5), 1.7, rng, rgb(232, 228, 220))
end

local function fxEyewear(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	local function wallPanel(cf: CFrame, w: number, h: number, y0: number, rows: number)
		local p = D(m, cf * CFrame.new(0, y0 + h / 2, -0.1), Vector3.new(w, h, 0.2), rgb(250, 250, 250), MAT.SmoothPlastic, "GlassesWall")
		rectGui(p, FRONT, glassesRects(rng, w, h, rows), 30)
		S(m, cf * CFrame.new(0, (y0 - 0.2) / 2 + 0.05, -0.8), Vector3.new(w, y0 - 0.2, 1.6), rgb(236, 236, 234), MAT.SmoothPlastic, "DrawerCabinet")
	end
	wallPanel(F(-1.5, 0, Dp), 18, 6.6, 3.0, 7)
	wallPanel(F(-WL, 0, 13.5, FACE_PX), 12, 6.0, 3.0, 6)
	wallPanel(F(WL, 0, 11.0, FACE_NX), 8, 6.0, 3.0, 6)
	D(m, F(WL - 0.1, 3.8, 17.0), Vector3.new(0.08, 6.0, 2.2), rgb(206, 214, 218), MAT.Glass, "Mirror", 0.4)
	sign(m, F(-1.5, 11.2, Dp - 0.12), Vector3.new(8, 1.4, 0.1), rgb(20, 20, 22), MAT.SmoothPlastic, "EYEWEAR · 시력검사 무료", rgb(255, 255, 255), 30)
	-- 가운데 진열 테이블 2 + 안경 트레이 + 탁상 거울
	for i, p in { { -4.0, 11.0 }, { 3.5, 15.0 } } do
		table_(m, F(p[1], 0, p[2]), 5.0, 2.6, 3.1, rgb(250, 250, 250), MAT.SmoothPlastic, rgb(200, 200, 198))
		local tray = D(m, F(p[1], 3.09, p[2]), Vector3.new(3.6, 0.08, 1.6), rgb(30, 30, 32), MAT.Fabric, "GlassesTray")
		rectGui(tray, TOP, glassesRects(rng, 3.6, 1.6, 3), 30)
		cyl(m, F(p[1] + 2.0, 3.7, p[2] + (if i == 1 then 0.6 else -0.6)) * CFrame.Angles(math.rad(80), 0, 0), 0.06, 1.2, rgb(206, 214, 218), MAT.Glass, "TableMirror")
	end
	-- 시력검사 코너(왼쪽 뒤): 테이블 + 자동굴절검사기 + 스툴
	S(m, F(-WL + 3, 1.5, Dp - 3), Vector3.new(3.4, 2.9, 2.0), rgb(236, 236, 234), MAT.SmoothPlastic, "ExamTable")
	D(m, F(-WL + 3, 3.55, Dp - 3.2), Vector3.new(1.4, 1.1, 1.8), rgb(240, 240, 240), MAT.SmoothPlastic, "Refractor")
	D(m, F(-WL + 3, 4.35, Dp - 3.7), Vector3.new(0.9, 0.5, 0.7), rgb(60, 62, 66), MAT.SmoothPlastic, "RefractorHead")
	stool(m, F(-WL + 3, 0, Dp - 5.3), rgb(60, 62, 66), 2.0)
	counterPOS(sh, WL - 4.6, Dp - 3.0, 0, 6.0, rgb(250, 250, 250), MAT.SmoothPlastic, rgb(60, 62, 66), MAT.SmoothPlastic)
end

local function fxBooks(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	local wood = rgb(92, 64, 44)
	local function bookFill(_i: number, cf: CFrame, w: number, _h: number)
		facings(m, cf, w, 1.05, 0.7, bookRects(rng, w), rgb(36, 28, 22), 36)
	end
	shelfUnit(m, F(0, 0, Dp), 22, 9.6, { 0.9, 2.35, 3.8, 5.25, 6.7, 8.15 }, 0.9, wood, MAT.Wood, wood, bookFill)
	shelfUnit(m, F(-WL, 0, 14.5, FACE_PX), 14, 8.1, { 0.9, 2.35, 3.8, 5.25, 6.7 }, 0.9, wood, MAT.Wood, wood, bookFill)
	sign(m, F(0, 10.6, Dp - 0.12), Vector3.new(9, 1.4, 0.1), rgb(28, 52, 42), MAT.SmoothPlastic, "BEST SELLER  베스트셀러", rgb(236, 230, 200), 30)
	-- 오른쪽 벽: 잡지 랙(표지 페이스아웃)
	local rack = D(m, F(WL - 0.6, 2.75, 12.5) * CFrame.Angles(0, 0, math.rad(-12)), Vector3.new(0.5, 5.2, 8.0), rgb(60, 46, 36), MAT.Wood, "MagazineRack")
	local covers = {}
	for r = 0, 2 do
		for c = 0, 5 do
			table.insert(covers, { c / 6 + 0.012, r / 3 + 0.02, 1 / 6 - 0.024, 1 / 3 - 0.06, jit(rng, pick(rng, BOOK_C), 0.1) })
		end
	end
	rectGui(rack, LEFT, covers, 20)
	-- 가운데 진열 테이블 2 + 평대 책 더미(앞 = 책등 줄무늬, 위 = 표지)
	for _, p in { { -4.0, 10.5 }, { 4.0, 14.5 } } do
		table_(m, F(p[1], 0, p[2]), 6.2, 3.4, 2.7, rgb(170, 130, 88), MAT.Wood, rgb(80, 60, 44))
		for k = -1, 1 do
			local n = rng:NextInteger(4, 8)
			local hS = n * 0.12
			local c = pick(rng, BOOK_C)
			local st = D(m, F(p[1] + k * 2.0, 2.7 + hS / 2, p[2] + rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.15, 0.15)), Vector3.new(1.5, hS, 2.1), dark(c, 0.2), MAT.SmoothPlastic, "BookStack")
			local rr = {}
			for j = 0, n - 1 do
				table.insert(rr, { 0.02, j / n, 0.96, 0.85 / n, jit(rng, pick(rng, BOOK_C), 0.1) })
			end
			rectGui(st, FRONT, rr, 30)
			rectGui(st, TOP, { { 0, 0, 1, 1, c }, { 0.1, 0.12, 0.8, 0.18, rgb(250, 248, 240) } }, 12)
		end
	end
	S(m, F(0, 0.75, 19.5), Vector3.new(6, 1.4, 1.8), rgb(170, 130, 88), MAT.Wood, "ReadingBench")
	counterPOS(sh, WL - 4.6, Dp - 3.0, 0, 6.5, wood, MAT.Wood, C.oak, MAT.Wood)
end

local function fxRecords(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	for _, p in { { -4.5, 11.0 }, { 4.5, 11.0 } } do
		table_(m, F(p[1], 0, p[2]), 4.6, 6.4, 2.6, rgb(120, 92, 64), MAT.Wood, rgb(50, 40, 32))
		for k = -1, 1, 2 do
			local crate = D(m, F(p[1], 3.05, p[2] + k * 1.5), Vector3.new(3.6, 0.9, 2.8), rgb(150, 112, 74), MAT.Wood, "RecordCrate")
			rectGui(crate, TOP, edgeRects(rng, 22, BOOK_C), 24)
		end
	end
	local wall = D(m, F(0, 6.6, Dp - 0.1), Vector3.new(18, 6.4, 0.2), rgb(30, 30, 32), MAT.SmoothPlastic, "AlbumWall")
	local covers = {}
	for r = 0, 3 do
		for c = 0, 9 do
			table.insert(covers, { c / 10 + 0.008, r / 4 + 0.03, 0.084, 0.2, jit(rng, pick(rng, BOOK_C), 0.15) })
		end
	end
	rectGui(wall, FRONT, covers, 20)
	local neon = sign(m, F(-WL + 0.12, 9.0, 13.0, FACE_PX), Vector3.new(7, 1.6, 0.1), rgb(30, 30, 32), MAT.SmoothPlastic, "RECORDS · LP · CD", rgb(255, 140, 70), 30)
	neon.Name = "NeonSign"
	-- 청음 코너
	S(m, F(-WL + 1.6, 1.6, 19.0), Vector3.new(2.6, 3.1, 5.0), rgb(60, 46, 36), MAT.Wood, "ListeningDesk")
	D(m, F(-WL + 1.6, 3.27, 18.4), Vector3.new(1.8, 0.24, 1.6), rgb(30, 30, 32), MAT.SmoothPlastic, "Turntable")
	cyl(m, F(-WL + 1.6, 3.42, 18.4), 0.06, 1.3, rgb(20, 20, 22), MAT.SmoothPlastic, "Platter")
	ell(m, F(-WL + 1.6, 3.33, 20.2), Vector3.new(0.9, 0.35, 0.8), rgb(30, 30, 32), MAT.SmoothPlastic, "Headphones")
	counterPOS(sh, WL - 4.6, Dp - 3.0, 0, 6.0, rgb(30, 30, 32), MAT.SmoothPlastic, rgb(120, 92, 64), MAT.Wood)
end

local function fxCosmetics(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	local perf = sh.kind == "perfume"
	local shelfC = if perf then rgb(200, 170, 110) else rgb(250, 250, 250)
	local function lit(cf: CFrame, w: number, ys: { number })
		S(m, cf * CFrame.new(0, 1.0, -0.8), Vector3.new(w, 1.9, 1.6), if perf then rgb(24, 24, 26) else rgb(250, 250, 250), MAT.SmoothPlastic, "BaseCabinet")
		N(m, cf * CFrame.new(0, 6.0, -0.06), Vector3.new(w - 0.4, 7.6, 0.12), if perf then rgb(250, 232, 200) else rgb(255, 250, 250), "BacklitPanel")
		for _, y in ys do
			D(m, cf * CFrame.new(0, y - 0.05, -0.6), Vector3.new(w - 0.6, 0.1, 1.0), shelfC, if perf then MAT.Metal else MAT.Glass, "GlassShelf")
			facings(m, cf * CFrame.new(0, y, -1.1), w - 1.2, 0.9, 0.5, facingRects(rng, w - 1.2, 0.16, 0.34, 0.45, 0.95, if perf then { rgb(230, 200, 140), rgb(250, 240, 220), rgb(170, 120, 70), rgb(40, 40, 44) } else COSM_C), dark(shelfC, 0.6), 36)
		end
	end
	lit(F(0, 0, Dp), 14, { 3.4, 5.0, 6.6, 8.2 })
	lit(F(-WL, 0, 13.5, FACE_PX), 10, { 3.4, 5.0, 6.6 })
	-- 테스터 아일랜드 2
	for _, p in { { -3.5, 10.5 }, { 4.0, 15.0 } } do
		S(m, F(p[1], 1.45, p[2]), Vector3.new(5.6, 2.8, 2.8), if perf then rgb(24, 24, 26) else rgb(250, 250, 250), MAT.SmoothPlastic, "TesterIsland")
		D(m, F(p[1], 2.92, p[2]), Vector3.new(6.0, 0.14, 3.2), if perf then rgb(200, 170, 110) else rgb(236, 210, 214), if perf then MAT.Metal else MAT.SmoothPlastic, "IslandTop")
		if perf then
			for k = 0, 3 do
				local bx = p[1] - 2.1 + k * 1.4
				D(m, F(bx, 3.4, p[2]), Vector3.new(0.7, 0.8, 0.45), pick(rng, { rgb(236, 200, 140), rgb(220, 230, 236), rgb(240, 190, 200) }), MAT.Glass, "PerfumeBottle")
				cyl(m, F(bx, 3.95, p[2]), 0.32, 0.36, pick(rng, { rgb(200, 170, 110), rgb(30, 30, 32) }), MAT.Metal, "PerfumeCap")
			end
		else
			facings(m, F(p[1], 2.99, p[2] - 0.6), 5.2, 0.7, 0.6, facingRects(rng, 5.2, 0.16, 0.3, 0.5, 0.95, COSM_C), rgb(220, 220, 220), 36)
			D(m, F(p[1], 3.25, p[2] + 0.55), Vector3.new(4.6, 0.6, 1.0), rgb(240, 240, 240), MAT.SmoothPlastic, "Riser")
			facings(m, F(p[1], 3.55, p[2] + 0.1), 4.4, 0.7, 0.6, facingRects(rng, 4.4, 0.16, 0.3, 0.5, 0.95, COSM_C), rgb(220, 220, 220), 36)
		end
		cyl(m, F(p[1] + 2.3, 3.75, p[2] + 0.9) * CFrame.Angles(math.rad(80), 0, 0), 0.06, 1.3, rgb(206, 214, 218), MAT.Glass, "TableMirror")
	end
	-- 오른쪽 벽 메이크업 스테이션: 화장대 + 조명 거울 + 스툴 2
	local cfR = F(WL, 0, 12.0, FACE_NX)
	D(m, cfR * CFrame.new(0, 2.9, -1.1), Vector3.new(7.0, 0.2, 2.0), rgb(250, 250, 250), MAT.SmoothPlastic, "Vanity")
	D(m, cfR * CFrame.new(0, 1.4, -0.4), Vector3.new(7.0, 2.8, 0.6), rgb(236, 236, 234), MAT.SmoothPlastic, "VanityBase")
	D(m, cfR * CFrame.new(0, 5.4, -0.1), Vector3.new(6.4, 3.4, 0.12), rgb(206, 214, 218), MAT.Glass, "VanityMirror", 0.4)
	N(m, cfR * CFrame.new(0, 7.25, -0.12), Vector3.new(6.6, 0.25, 0.14), rgb(255, 246, 232), "VanityLight")
	for k = -1, 1, 2 do
		stool(m, cfR * CFrame.new(k * 1.8, 0, -2.6), rgb(236, 210, 214), 2.2)
	end
	counterPOS(sh, WL - 4.6, Dp - 3.0, 0, 6.0, if perf then rgb(24, 24, 26) else rgb(250, 250, 250), MAT.SmoothPlastic, if perf then rgb(200, 170, 110) else rgb(236, 210, 214), MAT.SmoothPlastic)
end

local function fxPharmacy(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	N(m, F(-WL + 2.6, 9.8, Dp - 0.12), Vector3.new(0.9, 2.7, 0.12), rgb(40, 190, 90), "PharmacyCross")
	N(m, F(-WL + 2.6, 9.8, Dp - 0.16), Vector3.new(2.7, 0.9, 0.2), rgb(40, 190, 90), "PharmacyCross")
	shelfUnit(m, F(1.5, 0, Dp), 16, 9.0, { 1.2, 3.2, 5.2, 7.2 }, 1.0, rgb(250, 250, 250), MAT.SmoothPlastic, rgb(240, 240, 240), function(_i, cf, w, _h)
		facings(m, cf, w, 1.0, 0.8, facingRects(rng, w, 0.4, 0.8, 0.5, 0.95, MED_C, true), rgb(200, 200, 200))
	end)
	S(m, F(1.5, 1.6, Dp - 4.4), Vector3.new(14, 3.1, 2.2), rgb(250, 250, 250), MAT.SmoothPlastic, "RxCounter")
	D(m, F(1.5, 3.22, Dp - 4.5), Vector3.new(14.3, 0.14, 2.6), rgb(36, 140, 80), MAT.SmoothPlastic, "RxTop")
	D(m, F(-3.0, 3.47, Dp - 4.2), Vector3.new(0.5, 0.36, 0.5), C.black, MAT.SmoothPlastic, "PosBase")
	D(m, F(-3.0, 4.05, Dp - 4.15) * CFrame.Angles(math.rad(14), 0, 0), Vector3.new(1.2, 0.85, 0.1), rgb(30, 30, 34), MAT.SmoothPlastic, "PosScreen")
	decal(m, F(4.0, 2.3, Dp - 5.56), 6, 0.9, "처방전 접수  PRESCRIPTION", rgb(36, 140, 80), false, 40)
	-- 가운데 곤돌라(양면)
	S(m, F(-1, 2.3, 11.5), Vector3.new(9, 4.5, 2.4), rgb(240, 240, 240), MAT.SmoothPlastic, "Gondola")
	for _, y in { 1.2, 3.0 } do
		local r = D(m, F(-1, y + 0.5, 11.5), Vector3.new(8.6, 1.0, 3.0), rgb(200, 200, 200), MAT.SmoothPlastic, "Facings")
		local rects = facingRects(rng, 8.6, 0.4, 0.8, 0.5, 0.95, MED_C, true)
		rectGui(r, FRONT, rects, 24)
		rectGui(r, BACK, rects, 24)
	end
end

local function fxJewelry(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	local watch = sh.kind == "watches"
	local function case(cf: CFrame, len: number)
		S(m, cf * CFrame.new(0, 1.35, 0), Vector3.new(len, 2.6, 2.2), rgb(20, 20, 22), MAT.SmoothPlastic, "CaseBase")
		G(m, cf * CFrame.new(0, 3.3, 0), Vector3.new(len, 1.3, 2.2), rgb(226, 236, 244), 0.65, false, "JewelCase")
		N(m, cf * CFrame.new(0, 3.88, 0.4), Vector3.new(len - 0.4, 0.06, 0.6), rgb(255, 244, 228), "CaseLight")
		local tray = D(m, cf * CFrame.new(0, 2.7, 0), Vector3.new(len - 0.5, 0.1, 1.8), if watch then rgb(70, 60, 50) else rgb(30, 34, 50), MAT.Fabric, "JewelTray")
		local items = gridRects(rng, math.floor(len / 0.9), 2, if watch then { rgb(220, 220, 224), rgb(200, 170, 110), rgb(30, 30, 32) } else { rgb(236, 210, 140), rgb(230, 230, 236), rgb(250, 250, 255), rgb(220, 190, 200) }, if watch then 0.5 else 0.3)
		rectGui(tray, TOP, items, 30)
	end
	case(F(0, 0, Dp - 5.5), 12)
	case(F(-WL + 2.0, 0, 12.5, FACE_PX), 8)
	case(F(WL - 2.0, 0, 12.5, FACE_NX), 8)
	for k = -1, 1, 2 do
		stool(m, F(k * 2.4, 0, Dp - 8.4), rgb(120, 100, 80), 2.2)
	end
	sign(m, F(0, 8.8, Dp - 0.12), Vector3.new(8, 2.4, 0.12), rgb(14, 14, 16), MAT.SmoothPlastic, if watch then "SWISS WATCHES\n시계 · 수리" else "FINE JEWELRY\n주얼리", rgb(230, 200, 140), 30)
	for k = -1, 1, 2 do
		G(m, F(k * 7.5, 5.6, Dp - 0.6), Vector3.new(3.0, 3.0, 0.9), rgb(226, 236, 244), 0.6, false, "WallVitrine")
		N(m, F(k * 7.5, 7.06, Dp - 0.6), Vector3.new(2.8, 0.08, 0.7), rgb(255, 244, 228), "VitrineLight")
	end
	D(m, F(3.5, 4.12, Dp - 5.3), Vector3.new(0.5, 0.36, 0.5), C.black, MAT.SmoothPlastic, "PosBase")
end

local function fxLiving(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	D(m, F(-5.0, 0.08, 13.0), Vector3.new(10, 0.06, 7.0), rgb(196, 186, 168), MAT.Fabric, "Rug")
	sofa(m, F(-5.0, 0.05, 15.2), 8.0, rgb(150, 156, 150), rgb(200, 140, 90))
	VC(m, F(-5.0, 1.2, 11.5), 0.12, 3.0, C.oak, MAT.Wood, true, "CoffeeTable")
	VC(m, F(-5.0, 0.62, 11.5), 1.1, 0.4, rgb(40, 40, 42), MAT.Metal, false, "CoffeeTableLeg")
	VC(m, F(-10.2, 2.9, 15.6), 5.7, 0.18, rgb(40, 40, 42), MAT.Metal, false, "FloorLampPole")
	cyl(m, F(-10.2, 5.9, 15.6), 1.2, 1.6, rgb(236, 226, 206), MAT.Fabric, "FloorLampShade")
	shelfUnit(m, F(2.0, 0, Dp), 14, 9.0, { 1.6, 4.1, 6.6 }, 1.4, rgb(214, 200, 176), MAT.Wood, rgb(170, 130, 88), function(_i, cf, w, h)
		facings(m, cf, w, math.min(h, 1.6), 1.1, facingRects(rng, w, 0.5, 1.2, 0.4, 0.95, HOME_C), rgb(150, 140, 126), 24)
	end)
	table_(m, F(4.0, 0, 12.0), 6.0, 3.2, 2.6, C.oak, MAT.Wood, rgb(70, 56, 44))
	for k = 0, 3 do
		VC(m, F(2.0 + k * 1.3, 2.6 + 0.5 + (k % 2) * 0.25, 12.0 + (k % 2 - 0.5) * 0.9), 1.0 + (k % 2) * 0.5, 0.6 + (k % 3) * 0.15, pick(rng, HOME_C), MAT.SmoothPlastic, false, "Vase")
	end
	counterPOS(sh, WL - 4.6, Dp - 3.0, 0, 6.0, rgb(214, 200, 176), MAT.Wood, C.oak, MAT.Wood)
end

local function fxStationery(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	for _, gx in { -5.0, 3.5 } do
		S(m, F(gx, 2.3, 12.5), Vector3.new(2.4, 4.5, 9.0), rgb(250, 250, 248), MAT.SmoothPlastic, "Gondola")
		for _, y in { 1.0, 2.9 } do
			local r = D(m, F(gx, y + 0.45, 12.5, FACE_PX), Vector3.new(8.6, 0.9, 3.0), rgb(210, 210, 206), MAT.SmoothPlastic, "Facings")
			local rects = facingRects(rng, 8.6, 0.25, 0.6, 0.5, 0.95, PACK_C, true)
			rectGui(r, FRONT, rects, 24)
			rectGui(r, BACK, rects, 24)
		end
	end
	shelfUnit(m, F(0, 0, Dp), 18, 9.0, { 1.2, 3.4, 5.6, 7.8 }, 1.0, rgb(250, 248, 244), MAT.SmoothPlastic, C.oak, function(_i, cf, w, _h)
		facings(m, cf, w, 1.1, 0.8, facingRects(rng, w, 0.3, 0.9, 0.45, 0.95, PACK_C, true), rgb(200, 196, 190))
	end)
	counterPOS(sh, WL - 4.6, Dp - 4.0, 0, 6.0, rgb(250, 248, 244), MAT.SmoothPlastic, rgb(250, 210, 60), MAT.SmoothPlastic)
end

local function fxTech(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	for i, tx in { -5.0, 3.5 } do
		table_(m, F(tx, 0, 12.5), 4.4, 10, 3.0, rgb(214, 190, 150), MAT.Wood, rgb(214, 190, 150))
		for k = 0, 2 do
			local tz = 9.0 + k * 3.4
			if i == 1 then
				D(m, F(tx, 3.03, tz), Vector3.new(1.1, 0.06, 0.78), rgb(200, 202, 206), MAT.Metal, "LaptopBase")
				N(m, F(tx, 3.38, tz + 0.42) * CFrame.Angles(math.rad(-15), 0, 0), Vector3.new(1.1, 0.72, 0.05), rgb(120, 170, 230), "LaptopScreen")
			else
				D(m, F(tx - 0.8, 3.03, tz), Vector3.new(0.85, 0.05, 0.62), rgb(30, 30, 32), MAT.Glass, "Tablet")
				D(m, F(tx + 0.9, 3.03, tz), Vector3.new(0.28, 0.05, 0.55), rgb(30, 30, 32), MAT.Glass, "Phone")
			end
		end
	end
	D(m, F(0, 8.0, Dp - 0.2), Vector3.new(14, 6.0, 0.3), rgb(20, 20, 22), MAT.SmoothPlastic, "ScreenFrame")
	local scr = N(m, F(0, 8.0, Dp - 0.38), Vector3.new(13.4, 5.5, 0.06), rgb(60, 110, 200), "VideoWall")
	Kit.label(scr, FRONT, TAGLINE.tech, { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 16, maxDistance = 400 })
	shelfUnit(m, F(-WL, 0, 14.0, FACE_PX), 10, 6.0, { 1.6, 3.4 }, 1.0, rgb(244, 244, 246), MAT.SmoothPlastic, rgb(250, 250, 250), function(_i, cf, w, _h)
		facings(m, cf, w, 1.0, 0.6, facingRects(rng, w, 0.4, 0.7, 0.6, 0.95, { rgb(250, 250, 250), rgb(30, 30, 32), rgb(200, 202, 206), rgb(90, 140, 220) }, true), rgb(220, 220, 222))
	end)
	counterPOS(sh, WL - 4.6, Dp - 3.0, 0, 6.5, rgb(250, 250, 250), MAT.SmoothPlastic, rgb(214, 190, 150), MAT.Wood)
	stool(m, F(WL - 6.0, 0, Dp - 5.6), rgb(214, 190, 150), 2.4)
end

local function fxBags(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	local BAG_C = { rgb(110, 70, 46), rgb(30, 30, 32), rgb(196, 160, 120), rgb(150, 40, 40), rgb(230, 222, 206), rgb(60, 70, 90) }
	local function bag(cf: CFrame)
		local c = pick(rng, BAG_C)
		local w, h = rng:NextNumber(1.2, 1.6), rng:NextNumber(0.9, 1.2)
		D(m, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, 0.55), c, MAT.Leather, "Bag")
		D(m, cf * CFrame.new(0, h + 0.25, 0), Vector3.new(w * 0.55, 0.5, 0.08), dark(c, 0.2), MAT.Leather, "BagHandle")
	end
	shelfUnit(m, F(0, 0, Dp), 15, 9.4, { 1.6, 4.4, 7.2 }, 1.6, rgb(240, 236, 228), MAT.SmoothPlastic, rgb(110, 70, 46), function(_i, cf, w, _h)
		for k = -1, 1 do
			bag(cf * CFrame.new(k * w / 3, 0, 0.7))
		end
	end)
	for _, p in { { -4.0, 11.5 }, { 4.0, 15.0 } } do
		S(m, F(p[1], 1.0, p[2]), Vector3.new(4.0, 1.9, 2.4), rgb(240, 236, 228), MAT.SmoothPlastic, "Plinth")
		bag(F(p[1] - 0.9, 1.95, p[2]))
		bag(F(p[1] + 1.0, 1.95, p[2] + 0.2, 0.3))
	end
	D(m, F(-WL + 0.1, 3.8, 12.0), Vector3.new(0.08, 6.0, 2.2), rgb(206, 214, 218), MAT.Glass, "Mirror", 0.4)
	counterPOS(sh, WL - 4.6, Dp - 3.6, 0, 6.0, rgb(110, 70, 46), MAT.Leather, rgb(240, 236, 228), MAT.SmoothPlastic)
end

local function fxPopup(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	local fur = rgb(176, 120, 70)
	local bc = F(0, 0, 14.0)
	VC(m, bc * CFrame.new(0, 0.55, 0), 1.0, 7.0, rgb(250, 250, 248), MAT.SmoothPlastic, true, "Podium")
	ell(m, bc * CFrame.new(0, 3.5, 0), Vector3.new(4.4, 5.0, 3.8), fur, MAT.Fabric, "BearBody")
	ell(m, bc * CFrame.new(0, 7.2, 0), Vector3.new(4.0, 3.5, 3.4), fur, MAT.Fabric, "BearHead")
	for k = -1, 1, 2 do
		ball(m, (bc * CFrame.new(k * 1.5, 8.8, 0)).Position, 1.3, fur, MAT.Fabric, "BearEar")
		ball(m, (bc * CFrame.new(k * 0.7, 7.6, -1.55)).Position, 0.38, rgb(20, 20, 22), MAT.SmoothPlastic, "BearEye")
	end
	ell(m, bc * CFrame.new(0, 6.8, -1.6), Vector3.new(1.6, 1.1, 0.8), rgb(240, 222, 196), MAT.Fabric, "BearMuzzle")
	sign(m, F(0, 8.0, Dp - 0.12), Vector3.new(16, 7.0, 0.12), rgb(255, 196, 80), MAT.Neon, "BEAR POP-UP STORE\n곰돌이 팝업스토어\n11.01 – 11.30", rgb(36, 60, 110), 16)
	for _, p in { { -9.0, 10.0 }, { 9.0, 17.0 } } do
		table_(m, F(p[1], 0, p[2]), 4.6, 3.0, 2.6, rgb(250, 250, 248), MAT.SmoothPlastic, rgb(36, 60, 110))
		facings(m, F(p[1], 2.6, p[2] - 0.9), 4.0, 0.9, 1.6, facingRects(rng, 4.0, 0.5, 0.8, 0.7, 1.0, { fur, rgb(250, 230, 200), rgb(36, 60, 110), rgb(255, 196, 80) }), rgb(230, 226, 220), 24)
	end
	counterPOS(sh, WL - 4.6, Dp - 3.0, 0, 6.0, rgb(36, 60, 110), MAT.SmoothPlastic, rgb(250, 250, 248), MAT.SmoothPlastic)
end

local function fxFoodCourt(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	D(m, F(0, 6.0, Dp - 0.1), Vector3.new(sh.W - 0.6, 6.0, 0.2), rgb(190, 192, 196), MAT.Metal, "KitchenBack", 0.15)
	local STALLS = { { "한식  KOREAN", "비빔밥 9,000\n김치찌개 8,500\n불고기 11,000" }, { "일식  JAPANESE", "돈까스 10,000\n라멘 9,500\n우동 8,000" }, { "중식  CHINESE", "짜장면 7,500\n짬뽕 9,000\n탕수육 16,000" } }
	for i, st in STALLS do
		local sx = -WL + (i - 0.5) * (2 * WL / 3)
		S(m, F(sx, 1.6, Dp - 3.6), Vector3.new(2 * WL / 3 - 0.8, 3.1, 2.2), rgb(70, 72, 76), MAT.Metal, "StallCounter", 0.15)
		local mb = sign(m, F(sx, 10.0, Dp - 0.3), Vector3.new(2 * WL / 3 - 1.2, 3.6, 0.15), rgb(120, 30, 24), MAT.Neon, st[1] .. "\n" .. st[2], rgb(255, 246, 226), 24)
		mb.Name = "MenuLightbox"
		N(m, F(sx + 2.6, 5.4, Dp - 0.25), Vector3.new(1.8, 0.8, 0.1), rgb(30, 30, 34), "OrderDisplay")
	end
	for k = 1, 2 do
		D(m, F(-WL + k * (2 * WL / 3), 4.5, Dp - 2.4), Vector3.new(0.2, 9.0, 4.4), rgb(40, 40, 42), MAT.Metal, "StallDivider")
	end
	for k = 0, 2 do
		local tx, tz = -8 + k * 8, 11.0 + (k % 2) * 2.0
		D(m, F(tx, TABLE_H - 0.1, tz), Vector3.new(4.0, 0.2, 3.0), rgb(250, 250, 248), MAT.SmoothPlastic, "FoodTable")
		VC(m, F(tx, 0.05 + (TABLE_H - 0.2) / 2, tz), TABLE_H - 0.2, 0.4, C.black, MAT.Metal, true, "TableLeg")
		for _, dz in { -2.3, 2.3 } do
			stool(m, F(tx, 0, tz + dz), rgb(220, 70, 50))
		end
	end
	local tr = S(m, F(-WL + 1.0, 3.6, 18.0), Vector3.new(1.6, 7.2, 5.0), rgb(70, 72, 76), MAT.Metal, "TrayReturn")
	Kit.label(tr, RIGHT, "퇴식구\nTRAY RETURN", { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 20, maxDistance = 200 })
	S(m, F(WL - 1.0, 2.15, 8.0), Vector3.new(1.4, 4.2, 1.4), rgb(230, 230, 232), MAT.Metal, "WaterDispenser")
	cyl(m, F(WL - 1.0, 4.95, 8.0), 1.4, 1.0, rgb(180, 210, 230), MAT.Glass, "WaterBottle")
	local _ = rng
end

local function fxSnack(sh: any)
	local m, F, rng, WL, Dp = sh.m, sh.F, sh.rng, sh.WL, sh.Dp
	S(m, F(-1, 1.6, Dp - 4.5), Vector3.new(16, 3.1, 2.6), rgb(230, 90, 40), MAT.SmoothPlastic, "SnackCounter")
	D(m, F(-1, 3.22, Dp - 4.6), Vector3.new(16.3, 0.14, 3.0), rgb(200, 202, 206), MAT.Metal, "CounterTop", 0.2)
	VC(m, F(-5.5, 3.45, Dp - 4.6), 0.3, 4.2, rgb(30, 30, 32), MAT.Metal, false, "TteokPan")
	VC(m, F(-5.5, 3.6, Dp - 4.6), 0.1, 3.8, rgb(200, 50, 30), MAT.SmoothPlastic, false, "Tteokbokki")
	VC(m, F(-0.5, 3.75, Dp - 4.6), 0.9, 2.0, C.steel, MAT.Metal, false, "EomukPot")
	local gb = D(m, F(4.0, 3.37, Dp - 4.6), Vector3.new(3.0, 0.16, 1.6), rgb(196, 150, 100), MAT.Wood, "GimbapBoard")
	rectGui(gb, TOP, gridRects(rng, 8, 2, { rgb(250, 230, 120), rgb(240, 120, 60), rgb(90, 150, 70) }, 0.5, rgb(30, 34, 30)), 30)
	sign(m, F(-1, 9.6, Dp - 0.12), Vector3.new(14, 3.6, 0.12), rgb(230, 90, 40), MAT.Neon, "떡볶이 4,500  순대 5,000  어묵 1,000\n김밥 3,500  튀김 3,000  라면 4,500", rgb(255, 255, 255), 24)
	D(m, F(-WL + 1.0, 3.3, 13.0), Vector3.new(1.6, 0.16, 9.0), rgb(250, 250, 248), MAT.SmoothPlastic, "WallBar")
	for k = 0, 2 do
		stool(m, F(-WL + 2.6, 0, 9.8 + k * 3.2), rgb(230, 90, 40), 2.4)
	end
	D(m, F(5.5, 3.47, Dp - 4.4), Vector3.new(0.5, 0.36, 0.5), C.black, MAT.SmoothPlastic, "PosBase")
end

local FIXTURES: { [string]: (any) -> () } = {
	fashion = fxFashion, outdoor = fxFashion, kids = fxFashion, men = fxFashion,
	shoes = fxShoes, sports = fxShoes, cafe = fxCafe, tea = fxCafe,
	bakery = fxBakery, dessert = fxBakery, gelato = fxGelato, flowers = fxFlowers, eyewear = fxEyewear,
	books = fxBooks, records = fxRecords, cosmetics = fxCosmetics, perfume = fxCosmetics, pharmacy = fxPharmacy,
	jewelry = fxJewelry, watches = fxJewelry, living = fxLiving, stationery = fxStationery, tech = fxTech,
	bags = fxBags, popup = fxPopup, food = fxFoodCourt, snack = fxSnack,
}

-- 진열창 연출(양쪽 창 뒤 z ≈ 0.6 ~ 4.6)
local function windowDisplay(sh: any)
	local m, F, rng, kind, K = sh.m, sh.F, sh.rng, sh.kind, sh.K
	local xw = (sh.ew / 2 + sh.W / 2) / 2
	local gw = sh.W / 2 - sh.ew / 2 - 1.0
	local fashion = kind == "fashion" or kind == "outdoor" or kind == "kids" or kind == "men"
	for side, sx in { -1, 1 } do
		local x = sx * xw
		if fashion then
			S(m, F(x, 0.4, 2.8), Vector3.new(gw - 2, 0.7, 3.2), dark(K.wall, 0.12), MAT.SmoothPlastic, "WindowPlinth")
			local pal = CLOTH[kind] or CLOTH.fashion
			mannequin(m, F(x - sx * 1.2, 0.75, 2.8, rng:NextNumber(-0.3, 0.3)), pick(rng, pal), pick(rng, pal))
			if side == 2 then
				D(m, F(x + 1.6, 1.3, 2.6), Vector3.new(1.4, 1.1, 0.55), pick(rng, pal), MAT.Leather, "Bag")
			end
		elseif kind == "shoes" or kind == "sports" then
			if side == 1 then
				S(m, F(x, 0.6, 2.6), Vector3.new(gw - 1, 1.1, 2.6), rgb(240, 240, 236), MAT.SmoothPlastic, "Riser")
				S(m, F(x + 1.5, 1.6, 3.3), Vector3.new(gw - 4, 0.9, 1.2), rgb(240, 240, 236), MAT.SmoothPlastic, "Riser")
				for k = -1, 1 do
					shoe(m, F(x + k * 2.4, (if k == 1 then 2.05 else 1.15), 2.4 + (if k == 1 then 0.9 else 0), rng:NextNumber(-0.5, 0.5)), pick(rng, { rgb(240, 240, 236), rgb(200, 60, 50), rgb(60, 90, 160) }), true)
				end
			else
				local st = sign(m, F(x, 3.55, 2.4), Vector3.new(4.2, 6.4, 0.25), rgb(18, 18, 20), MAT.SmoothPlastic, TAGLINE[kind] or "NEW", rgb(255, 255, 255), 20)
				st.Name = "Standee"
				D(m, F(x, 0.2, 2.4), Vector3.new(3.0, 0.3, 1.2), rgb(18, 18, 20), MAT.Metal, "StandeeFoot")
			end
		elseif kind == "cafe" or kind == "tea" then
			D(m, F(x, 3.5, 1.2), Vector3.new(gw, 0.14, 1.5), if kind == "tea" then rgb(120, 86, 56) else C.oak, MAT.Wood, "WindowBar")
			D(m, F(x, 1.75, 1.45), Vector3.new(gw - 1, 3.4, 0.2), rgb(40, 34, 30), MAT.Wood, "BarSupport")
			for k = -1, 1, 2 do
				stool(m, F(x + k * gw / 4, 0, 2.8), rgb(40, 34, 30), 2.45)
			end
		elseif kind == "bakery" or kind == "dessert" or kind == "gelato" then
			S(m, F(x, 1.3, 2.6), Vector3.new(gw - 3, 2.5, 2.4), if kind == "bakery" then C.oak else rgb(250, 250, 248), MAT.Wood, "WindowTable")
			VC(m, F(x - 1.2, 2.95, 2.6), 0.8, 0.25, C.steel, MAT.Metal, false, "CakeStandStem")
			VC(m, F(x - 1.2, 3.39, 2.6), 0.08, 1.8, rgb(250, 250, 248), MAT.SmoothPlastic, false, "CakePlate")
			VC(m, F(x - 1.2, 3.83, 2.6), 0.8, 1.3, pick(rng, { rgb(250, 240, 230), rgb(240, 180, 190), rgb(110, 70, 50) }), MAT.SmoothPlastic, false, "Cake")
			if kind == "bakery" then
				D(m, F(x + 1.5, 2.66, 2.6), Vector3.new(2.4, 0.3, 1.6), rgb(150, 110, 70), MAT.Wood, "BreadBasket")
				bread(m, F(x + 1.1, 2.8, 2.6), rng)
				bread(m, F(x + 2.0, 2.8, 2.5), rng)
			end
		elseif kind == "flowers" then
			for k = -1, 1 do
				local bx = x + k * 2.6
				VC(m, F(bx, 0.85 + (k + 1) * 0.15, 2.6), 1.6 + (k + 1) * 0.3, 1.4, rgb(170, 172, 176), MAT.Metal, false, "Bucket")
				ell(m, F(bx, 2.4 + (k + 1) * 0.3, 2.6) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector3.new(2.1, 1.4, 1.9), pick(rng, FLOWER_C), MAT.Fabric, "Bouquet")
			end
		elseif kind == "eyewear" then
			S(m, F(x, 1.0, 2.6), Vector3.new(gw - 3, 1.9, 2.0), rgb(250, 250, 250), MAT.SmoothPlastic, "WindowPlinth")
			for k = -1, 1, 2 do
				VC(m, F(x + k * 1.6, 2.45, 2.6), 1.0, 0.3, rgb(200, 202, 206), MAT.Metal, false, "GlassesStand")
				D(m, F(x + k * 1.6, 3.02, 2.55), Vector3.new(0.5, 0.15, 0.06), pick(rng, GLASSES_C), MAT.SmoothPlastic, "Glasses")
			end
		elseif kind == "books" or kind == "records" then
			S(m, F(x, 1.3, 2.6), Vector3.new(gw - 3, 2.5, 2.2), rgb(170, 130, 88), MAT.Wood, "WindowTable")
			for k = -1, 1 do
				local c = pick(rng, BOOK_C)
				D(m, F(x + k * 1.6, 3.2, 2.7) * CFrame.Angles(math.rad(-12), 0, 0), Vector3.new(1.3, 1.6, 0.15), c, MAT.SmoothPlastic, "BookFaceOut")
			end
		elseif kind == "cosmetics" or kind == "perfume" or kind == "pharmacy" then
			if kind == "pharmacy" then
				local pst = sign(m, F(x, 3.0, 1.0), Vector3.new(4.0, 5.9, 0.2), rgb(36, 140, 80), MAT.Neon, "건강기능식품\n종합비타민\n1+1", rgb(255, 255, 255), 20)
				pst.Name = "PosterLightbox"
			else
				S(m, F(x, 0.9, 2.6), Vector3.new(gw - 3, 1.7, 2.2), if kind == "perfume" then rgb(24, 24, 26) else rgb(250, 240, 242), MAT.SmoothPlastic, "WindowPlinth")
				D(m, F(x, 2.85, 2.6), Vector3.new(1.4, 2.2, 0.9), if kind == "perfume" then rgb(236, 200, 140) else rgb(240, 180, 196), MAT.Glass, "HeroBottle")
				cyl(m, F(x, 4.2, 2.6), 0.55, 0.7, rgb(200, 170, 110), MAT.Metal, "HeroCap")
			end
		elseif kind == "jewelry" or kind == "watches" then
			S(m, F(x, 1.4, 2.6), Vector3.new(2.4, 2.7, 2.0), rgb(20, 20, 22), MAT.SmoothPlastic, "VitrineBase")
			G(m, F(x, 3.75, 2.6), Vector3.new(2.4, 2.0, 2.0), rgb(226, 236, 244), 0.65, false, "Vitrine")
			if kind == "jewelry" then
				ell(m, F(x, 3.6, 2.6), Vector3.new(0.9, 1.6, 0.5), rgb(40, 40, 44), MAT.Fabric, "NeckBust")
			else
				cyl(m, F(x, 3.2, 2.6) * CFrame.Angles(math.rad(70), 0, 0), 0.25, 0.9, rgb(220, 220, 224), MAT.Metal, "Watch")
			end
		elseif kind == "food" then
			S(m, F(x, 1.5, 2.6), Vector3.new(gw - 1, 2.9, 2.0), rgb(70, 72, 76), MAT.Metal, "FoodCaseBase")
			G(m, F(x, 4.0, 2.6), Vector3.new(gw - 1, 2.1, 2.0), rgb(226, 236, 244), 0.6, false, "FoodCase")
			for k = -1, 1 do
				VC(m, F(x + k * 2.4, 3.2, 2.6), 0.5, 1.4, rgb(250, 250, 248), MAT.SmoothPlastic, false, "Bowl")
				VC(m, F(x + k * 2.4, 3.52, 2.6), 0.08, 1.2, pick(rng, { rgb(200, 60, 30), rgb(220, 170, 90), rgb(120, 70, 40) }), MAT.SmoothPlastic, false, "Dish")
			end
		elseif kind == "snack" then
			local pst = sign(m, F(x, 3.0, 1.0), Vector3.new(4.0, 5.9, 0.2), rgb(230, 90, 40), MAT.Neon, "떡볶이\n4,500", rgb(255, 255, 255), 20)
			pst.Name = "PosterLightbox"
		else -- living / stationery / tech / bags / popup
			S(m, F(x, 0.9, 2.6), Vector3.new(gw - 3, 1.7, 2.2), dark(K.wall, 0.06), MAT.SmoothPlastic, "WindowPlinth")
			for k = -1, 1, 2 do
				local c = pick(rng, if kind == "living" then HOME_C else PACK_C)
				if kind == "living" then
					VC(m, F(x + k * 1.4, 2.6, 2.6), 1.8, 0.9 + (k + 1) * 0.15, c, MAT.SmoothPlastic, false, "Vase")
				else
					D(m, F(x + k * 1.4, 2.35, 2.6, rng:NextNumber(-0.3, 0.3)), Vector3.new(1.3, 1.3, 0.9), c, MAT.SmoothPlastic, "Product")
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 상점 한 칸: 셸(바닥·벽·천장·헤더) + 진열창 + 간판 + 천장 설비 + 집기 + 진열창 연출
------------------------------------------------------------------------------------------------------
local function sprinkler(m: Instance, cf: CFrame)
	cyl(m, cf * CFrame.new(0, -0.12, 0), 0.3, 0.2, rgb(206, 208, 212), MAT.Metal, "Sprinkler")
	cyl(m, cf * CFrame.new(0, -0.27, 0), 0.04, 0.3, rgb(206, 208, 212), MAT.Metal, "SprinklerDeflector")
end
local function smokeDetector(m: Instance, cf: CFrame): BasePart
	return cyl(m, cf * CFrame.new(0, -0.05, 0), 0.16, 0.45, rgb(244, 244, 240), MAT.SmoothPlastic, "SmokeDetector")
end
local function speaker(m: Instance, cf: CFrame)
	cyl(m, cf * CFrame.new(0, -0.02, 0), 0.1, 0.72, rgb(226, 226, 222), MAT.SmoothPlastic, "CeilingSpeaker")
end

local function buildShop(m: Instance, HF: CFrame, x0: number, x1: number, s: number, yf: number, ceilB: number, GZ: number, SD: number, spec: ShopSpec, rng: Random, l1: boolean, lit: boolean, bladeY: number?)
	local K = KIND[spec.kind] or KIND.living
	local W = (x1 - x0) - 1.2
	local SF = HF * CFrame.new((x0 + x1) / 2, yf, s * GZ) * CFrame.Angles(0, if s > 0 then 0 else math.pi, 0)
	local function F(x: number, y: number, z: number, yaw: number?): CFrame
		if yaw then
			return SF * CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
		end
		return SF * CFrame.new(x, y, z)
	end
	local Dp = (SD - GZ) - 0.4
	local CH0 = (ceilB - yf) - 0.15 -- 상점 천장판 아랫면(공용 천장 아랫면보다 0.15 아래)
	local darkCeil = (K.ceil.R + K.ceil.G + K.ceil.B) < 1.4
	local panel = l1 or darkCeil
	local CH = if panel then CH0 else CH0 + 0.15
	local contrast = math.abs((K.wall.R + K.wall.G + K.wall.B) - 2.7) > 0.25
	local lining = l1 or contrast
	local fy, ew = 11.5, 8
	local sh = { m = m, F = F, W = W, WL = if lining then W / 2 - 0.3 else W / 2, Dp = Dp, CH = CH, fy = fy, ew = ew, K = K, spec = spec, kind = spec.kind, rng = rng, l1 = l1 }

	-- 셸
	S(m, F(0, -0.125, (Dp + 0.4) / 2), Vector3.new(W, 0.35, Dp + 0.4), K.floor, K.floorMat, "ShopFloor")
	S(m, F(0, (CH - 0.1) / 2, Dp + 0.45), Vector3.new(W, CH + 0.5, 0.9), K.wall, K.wallMat, "ShopWall")
	if panel then
		D(m, F(0, CH + 0.15, (Dp + 1) / 2), Vector3.new(W + 0.4, 0.3, Dp + 1), K.ceil, if darkCeil then MAT.Concrete else MAT.Plaster, "ShopSoffit")
	end
	if lining then
		for _, sx in { -1, 1 } do
			D(m, F(sx * (W / 2 - 0.15), (CH + 0.1) / 2, (1.0 + Dp + 0.2) / 2), Vector3.new(0.3, CH + 0.1, Dp - 0.8), K.wall, K.wallMat, "ShopSideWall")
		end
	end
	if l1 then
		D(m, F(0, (fy + CH + 0.1) / 2, 0.85), Vector3.new(W + 0.4, CH + 0.1 - fy, 0.3), K.ceil, MAT.SmoothPlastic, "ShopHeader")
		D(m, F(0, 0.3, Dp - 0.08), Vector3.new(W - 0.4, 0.5, 0.16), dark(K.wall, 0.35), MAT.SmoothPlastic, "Skirting")
	end

	-- 간판: 브랜드 띠(0.9 m) + 띄운 글자(0.33 m)
	Kit.part(m, F(0, fy + 1.5, -0.25), Vector3.new(W, 3.0, 0.5), { name = "Fascia", material = MAT.SmoothPlastic, color = K.fascia, collide = false, query = false, shadow = false })
	decal(m, F(0, fy + 1.5, -0.56), math.min(W - 8, 18), 1.15, spec.ko .. "  " .. spec.en, K.text, true, 30)

	-- 진열창: 상부 헤드 + 하부 실 + 유리 2(헤드·실·필라스터에 묻힘) + 문설주 2 + 문턱 + 영업시간 시트
	local frameC = if K.fascia.R + K.fascia.G + K.fascia.B > 2.4 then rgb(200, 202, 206) else rgb(40, 40, 44)
	D(m, F(0, fy - 0.2, 0), Vector3.new(W + 0.4, 0.4, 0.6), frameC, MAT.Metal, "StoreHead")
	for _, sx in { -1, 1 } do
		local a, b = ew / 2, W / 2 + 0.2
		D(m, F(sx * (a + b) / 2, 0.25, 0), Vector3.new(b - a, 0.5, 0.6), frameC, MAT.Metal, "StoreSill")
		G(m, F(sx * (a + b) / 2, (0.35 + fy - 0.25) / 2, 0), Vector3.new(b - a, fy - 0.6, 0.3), rgb(200, 216, 226), 0.74, true, "ShopWindow")
		D(m, F(sx * a, (fy - 0.2) / 2, 0), Vector3.new(0.4, fy - 0.2, 0.7), frameC, MAT.Metal, "DoorMullion")
	end
	D(m, F(0, 0.06, 0), Vector3.new(ew - 0.4, 0.08, 0.7), C.steel, MAT.Metal, "Threshold", 0.2)
	if l1 then
		decal(m, F(ew / 2 + 1.7, 5.2, -0.2), 2.4, 0.9, "OPEN 10:30 – 22:00\n영업시간", rgb(250, 250, 250), false, 50, Enum.Font.Gotham)
	end

	-- 천장: 트랙 레일 2 × 스폿 3 + 월워셔 + 스프링클러 2 + 감지기 + 슬롯 디퓨저 (+1층: 피난구유도등·CCTV)
	for _, tx in { -W / 4, W / 4 } do
		local z0, z1 = 3.0, Dp - 2.5
		D(m, F(tx, CH - 0.06, (z0 + z1) / 2), Vector3.new(0.2, 0.18, z1 - z0), K.track, MAT.Metal, "TrackRail")
		for k = 0, 2 do
			local z = z0 + 2 + k * (z1 - z0 - 4) / 2
			cyl(m, F(tx, CH - 0.47, z) * CFrame.Angles(0, 0, (if tx > 0 then 1 else -1) * math.rad(26)), 0.62, 0.34, K.track, MAT.Metal, "Spot")
		end
	end
	N(m, F(0, CH - 0.04, Dp - 0.9), Vector3.new(W - 3, 0.1, 0.3), K.lamp, "WallWasher")
	sprinkler(m, F(-3.6, CH, Dp * 0.32))
	sprinkler(m, F(3.6, CH, Dp * 0.7))
	local det = smokeDetector(m, F(0, CH, Dp * 0.5))
	D(m, F(0, CH - 0.02, 2.2), Vector3.new(W - 6, 0.08, 0.35), if darkCeil then rgb(30, 30, 32) else rgb(70, 70, 72), MAT.SmoothPlastic, "SlotDiffuser")
	if l1 then
		Props.exitSign(m, F(0, fy + 1.0, 1.0, math.pi))
		Props.cctv(m, F(sh.WL - 1.6, CH, 3.0))
	end
	if lit then
		light(det, "PointLight", { color = K.lamp, brightness = 1.15, range = 24 })
	end
	-- 1층: 메자닌 아래 천장에 매단 돌출 간판(양면)
	if bladeY then
		local by = bladeY - yf
		D(m, F(W / 2 - 2.6, by - 0.6, -2.4), Vector3.new(0.1, 1.2, 0.1), rgb(60, 60, 64), MAT.Metal, "BladeRod")
		local bl = Kit.part(m, F(W / 2 - 2.6, by - 2.05, -2.4), Vector3.new(0.25, 1.7, 3.6), { name = "BladeSign", material = MAT.SmoothPlastic, color = K.fascia, collide = false, query = false, shadow = false })
		Kit.label(bl, RIGHT, spec.ko .. "\n" .. spec.en, { color = K.text, glow = true, pixelsPerStud = 30, maxDistance = 300 })
		Kit.label(bl, LEFT, spec.ko .. "\n" .. spec.en, { color = K.text, glow = true, pixelsPerStud = 30, maxDistance = 300 })
	end

	-- 업종별 집기 + 진열창 연출
	local fx = FIXTURES[spec.kind]
	if fx then
		fx(sh)
	end
	windowDisplay(sh)
	-- EAS 도난방지 게이트(옷·신발·화장품·서점·잡화)
	local k = spec.kind
	if k == "fashion" or k == "outdoor" or k == "kids" or k == "men" or k == "shoes" or k == "sports" or k == "cosmetics" or k == "perfume" or k == "books" or k == "bags" or k == "tech" then
		for _, sx in { -1, 1 } do
			D(m, F(sx * (ew / 2 - 0.9), 0.14, 1.9), Vector3.new(0.5, 0.18, 1.9), rgb(120, 122, 128), MAT.Metal, "EasBase")
			G(m, F(sx * (ew / 2 - 0.9), 2.6, 1.9), Vector3.new(0.14, 4.8, 1.6), rgb(220, 230, 236), 0.45, false, "EasGate")
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 에스컬레이터 (xb, yb) → (xt, yt) 30°, 폭 방향 = Z. up = 올라가는 방향 표시
------------------------------------------------------------------------------------------------------
local function escalator(m: Instance, HF: CFrame, xb: number, xt: number, zc: number, yb: number, yt: number, up: boolean)
	local rise, run = yt - yb, xt - xb
	local ang = math.atan2(rise, run)
	local L = math.sqrt(rise * rise + run * run)
	local inc = HF * CFrame.new((xb + xt) / 2, (yb + yt) / 2, zc) * CFrame.Angles(0, 0, ang)
	local NS = 24
	local d, h = run / NS, rise / NS
	local SW = 3.4 -- 디딤판 폭 1.0 m
	local function at(x: number, y: number, z: number): CFrame
		return HF * CFrame.new(x, y, zc + z)
	end
	-- 트러스 + 상부 랜딩 구조
	S(m, inc * CFrame.new(-1.5, -1.75, 0), Vector3.new(L + 3, 3.2, 5.4), rgb(206, 208, 212), MAT.Metal, "EscalatorTruss", 0.12)
	S(m, at(xt + 1.5, yt - 1.62, 0), Vector3.new(5, 3.2, 5.4), rgb(206, 208, 212), MAT.Metal, "EscalatorHead", 0.12)
	-- 디딤판 24 + 노란 안전 테두리(앞 가장자리, 0.05 위)
	for i = 0, NS - 1 do
		local top = yb + (i + 1) * h
		local cx = xb + (i + 0.5) * d
		D(m, at(cx, top - h * 0.75, 0), Vector3.new(d + 0.02, h * 1.5, SW), rgb(62, 64, 70), MAT.DiamondPlate, "Step")
		D(m, at(cx - d / 2 + 0.2, top, 0), Vector3.new(0.28, 0.1, SW - 0.16), YELLOW, MAT.SmoothPlastic, "StepEdge")
	end
	-- 콤 플레이트(노란 빗살) + 플로어 플레이트
	for _, e in { { xb, yb, -1 }, { xt, yt, 1 } } do
		local ex, ey, sg = e[1], e[2], e[3]
		D(m, at(ex + sg * 0.5, ey + 0.01, 0), Vector3.new(1.0, 0.2, SW + 0.3), rgb(196, 198, 202), MAT.Metal, "CombPlate")
		D(m, at(ex + sg * 0.05, ey + 0.11, 0), Vector3.new(0.3, 0.12, SW), YELLOW, MAT.SmoothPlastic, "CombTeeth")
		D(m, at(ex + sg * 2.55, ey - 0.04, 0), Vector3.new(3.1, 0.2, 4.8), rgb(176, 178, 182), MAT.DiamondPlate, "FloorPlate")
	end
	-- 숨은 경사로(충돌): 계단 디딤판 중간선
	local p0 = Vector3.new(xb - d / 2, yb, zc)
	local p1 = Vector3.new(xt - d / 2, yt, zc)
	local dir = (p1 - p0).Unit
	local nrm = Vector3.new(-dir.Y, dir.X, 0)
	local ext = 3
	local ctr = (p0 + p1) / 2 - dir * (ext / 2) - nrm * 0.5
	Kit.part(m, HF * CFrame.fromMatrix(ctr, dir, nrm), Vector3.new((p1 - p0).Magnitude + ext, 1.0, 3.6), { name = "EscalatorRamp", color = C.steel, transparency = 1, collide = true, query = false, shadow = false })
	-- 양쪽 난간: 경사부(외장·스커트·브러시·데크·유리·핸드레일) + 양 끝 수평부(외장·유리·핸드레일·뉴얼 원형 끝)
	for _, sz in { -1, 1 } do
		D(m, inc * CFrame.new(0, 0.7, sz * 2.62), Vector3.new(L, 1.85, 0.16), rgb(206, 208, 212), MAT.Metal, "SideCladding", 0.15)
		D(m, inc * CFrame.new(0, 0.8, sz * 1.85), Vector3.new(L, 1.6, 0.16), rgb(186, 188, 192), MAT.Metal, "Skirt", 0.3)
		D(m, inc * CFrame.new(0, 1.05, sz * 1.72), Vector3.new(L, 0.16, 0.1), rgb(20, 20, 22), MAT.Fabric, "SkirtBrush")
		D(m, inc * CFrame.new(0, 1.66, sz * 2.13), Vector3.new(L, 0.12, 0.72), rgb(196, 198, 202), MAT.Metal, "Deck", 0.2)
		G(m, inc * CFrame.new(0, 2.6, sz * 2.55), Vector3.new(L, 2.2, 0.2), rgb(206, 222, 230), 0.55, true, "EscalatorGlass")
		D(m, inc * CFrame.new(0, 3.76, sz * 2.55), Vector3.new(L, 0.32, 0.42), C.black, MAT.Rubber, "Handrail")
		for _, e in { { xb - 2.0, yb, -1 }, { xt + 2.0, yt, 1 } } do
			local ex, ey, sg = e[1], e[2], e[3]
			local hl = 4.6
			D(m, at(ex, ey + 0.82, sz * 2.62), Vector3.new(hl, 1.64, 0.16), rgb(206, 208, 212), MAT.Metal, "SideCladding", 0.15)
			D(m, at(ex, ey + 0.85, sz * 1.85), Vector3.new(hl, 1.7, 0.16), rgb(186, 188, 192), MAT.Metal, "Skirt", 0.3)
			D(m, at(ex, ey + 1.76, sz * 2.13), Vector3.new(hl, 0.12, 0.72), rgb(196, 198, 202), MAT.Metal, "Deck", 0.2)
			G(m, at(ex, ey + 2.7, sz * 2.55), Vector3.new(hl, 2.0, 0.2), rgb(206, 222, 230), 0.55, true, "EscalatorGlass")
			D(m, at(ex, ey + 3.76, sz * 2.55), Vector3.new(hl, 0.32, 0.42), C.black, MAT.Rubber, "Handrail")
			local nx = ex + sg * hl / 2
			Kit.part(m, at(nx, ey + 2.64, sz * 2.55) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.42, 2.6, 2.6), { name = "NewelEnd", shape = "Cylinder", material = MAT.Rubber, color = C.black, collide = false, query = false, shadow = false })
		end
	end
	-- 비상정지 버튼(데크 위) + 운행 방향 표시(양 끝) + 안전 안내판(타는 쪽, 손님을 봄)
	local by = if up then yb else yt
	D(m, at(if up then xb - 3.6 else xt + 3.6, by + 1.88, -2.13), Vector3.new(0.3, 0.12, 0.3), rgb(220, 30, 30), MAT.SmoothPlastic, "EmergencyStop")
	for _, e in { { xb - 4.35, yb, up, FACE_NX }, { xt + 4.35, yt, not up, FACE_PX } } do
		local ok = e[3]
		local ind = N(m, at(e[1], e[2] + 0.9, -2.62) * CFrame.Angles(0, e[4], 0), Vector3.new(0.7, 0.7, 0.1), if ok then rgb(40, 200, 90) else rgb(230, 40, 40), "DirectionLamp")
		Kit.label(ind, FRONT, if ok then "↑" else "×", { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 60, maxDistance = 160 })
	end
	local bx = if up then xb - 4.38 else xt + 4.38
	local sgn = Kit.part(m, at(bx, by + 0.75, 2.62) * CFrame.Angles(0, if up then FACE_NX else FACE_PX, 0), Vector3.new(1.4, 1.1, 0.08), { name = "SafetySign", material = MAT.SmoothPlastic, color = YELLOW, collide = false, query = false, shadow = false })
	Kit.label(sgn, FRONT, "손잡이를 잡으세요\nHOLD THE HANDRAIL", { color = rgb(20, 20, 22), glow = false, pixelsPerStud = 60, maxDistance = 120 })
end

-- 유리 난간(2.4 m 패널, 줄눈 0.12): cf = 바닥 위 중심, 로컬 X = 길이
local function balustrade(m: Instance, cf: CFrame, len: number)
	local n = math.max(1, math.floor(len / 8 + 0.5))
	local pw = len / n
	for i = 0, n - 1 do
		G(m, cf * CFrame.new(-len / 2 + (i + 0.5) * pw, 1.9, 0), Vector3.new(pw - 0.12, 3.2, 0.25), rgb(206, 222, 230), 0.6, true, "Balustrade")
	end
	D(m, cf * CFrame.new(0, 3.55, 0), Vector3.new(len + 0.2, 0.25, 0.45), C.steel, MAT.Metal, "Handrail", 0.3)
	D(m, cf * CFrame.new(0, 0.27, 0), Vector3.new(len + 0.4, 0.66, 0.5), C.steel, MAT.Metal, "BaseShoe", 0.2)
end

-- 바닥 슬래브 필드: 그라우트 바탕(윗면 y - 0.06) 위에 슬래브(윗면 y, 줄눈 0.12)
local function slabField(m: Instance, at: any, x0: number, x1: number, z0: number, z1: number, y: number, nx: number, nz: number, rng: Random, pal: { Color3 }, name: string)
	local px, pz = (x1 - x0) / nx, (z1 - z0) / nz
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			D(m, at(x0 + (i + 0.5) * px, y - 0.15, z0 + (j + 0.5) * pz), Vector3.new(px - 0.12, 0.3, pz - 0.12), jit(rng, pick(rng, pal), 0.02), MAT.Marble, name)
		end
	end
end

------------------------------------------------------------------------------------------------------
-- 몰 전체
------------------------------------------------------------------------------------------------------
local function buildMall(m: Model, Hl: any, rng: Random)
	local HF: CFrame = Hl.cf
	local GX, GZ, VZ, SD, EX = Hl.GX, Hl.GZ, Hl.VZ, Hl.SD, Hl.EX
	local FY1, FY2, H, HZ = Hl.FY1, Hl.FY2, Hl.H, Hl.HZ
	local nS = Hl.shops
	local sw = 2 * GX / nS
	local slabB = FY2 - 3 -- 메자닌 슬래브 아랫면
	local c1B = slabB - 1.3 -- 1층 상점/통로 천장 아랫면
	local c2B = FY2 + 14.2 -- 2층 상점 천장 아랫면
	local yS = slabB - 0.8 -- 1층 보행로(메자닌 아래) 천장 아랫면 ≈ 4.9 m
	local mid = (nS + 1) // 2 - 1 -- 가운데 칸 = 입구 통로 (0 기반)
	local PW = EX - 0.6 -- 통로 벽(필라스터·통로벽) 안쪽 면 |x|
	local function at(x: number, y: number, z: number, yaw: number?): CFrame
		if yaw then
			return HF * CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
		end
		return HF * CFrame.new(x, y, z)
	end

	--------------------------------------------------------------------------------------------------
	-- 바닥: 그라우트 바탕 + 대형 슬래브 + 상점 앞 그래닛 띠
	--------------------------------------------------------------------------------------------------
	S(m, at(0, FY1 - 0.36, 0), Vector3.new(2 * GX, 0.6, 2 * GZ), GROUT, MAT.Concrete, "FloorBase")
	S(m, at(0, FY1 - 0.36, (GZ + HZ + 0.3) / 2), Vector3.new(2 * EX, 0.6, HZ + 0.3 - GZ), GROUT, MAT.Concrete, "PassageFloorBase")
	slabField(m, at, -GX, GX, -GZ + 4, GZ - 4, FY1, 26, 8, rng, STONE, "FloorSlab")
	for _, sz in { -1, 1 } do
		D(m, at(0, FY1 - 0.15, sz * (GZ - 2)), Vector3.new(2 * GX - 0.12, 0.3, 3.88), rgb(64, 62, 62), MAT.Granite, "GraniteBand")
	end
	slabField(m, at, -PW, PW, GZ, HZ - 10.5, FY1, 4, 6, rng, STONE, "FloorSlab")

	--------------------------------------------------------------------------------------------------
	-- 메자닌(2층 보행로 + 2층 상점 바닥) + 슬래브 패턴 + 보이드 띠(1층 천장 아래까지 내림) + LED, 다리 2
	--------------------------------------------------------------------------------------------------
	for _, sz in { -1, 1 } do
		S(m, at(0, FY2 - 1.53, sz * (VZ + SD) / 2), Vector3.new(2 * GX, 2.94, SD - VZ), C.marble, MAT.Marble, "Mezzanine", 0.05)
		slabField(m, at, -GX, GX, sz > 0 and VZ + 0.8 or -GZ, sz > 0 and GZ or -(VZ + 0.8), FY2, 16, 2, rng, STONE, "MezzSlab")
		D(m, at(0, (yS - 0.4 + FY2 + 0.25) / 2, sz * (VZ - 0.1)), Vector3.new(2 * GX - 28, FY2 + 0.25 - (yS - 0.4), 0.4), C.white, MAT.SmoothPlastic, "MezzFascia")
		N(m, at(0, FY2 - 2.6, sz * (VZ - 0.33)), Vector3.new(2 * GX - 28, 0.14, 0.06), C.coolLight, "MezzLed")
		balustrade(m, at(0, FY2, sz * (VZ + 0.5)), 2 * GX - 28)
	end
	for _, sx in { -1, 1 } do
		S(m, at(sx * (GX - 7), FY2 - 1.53, 0), Vector3.new(14, 2.94, 2 * VZ), C.marble, MAT.Marble, "Bridge", 0.05)
		slabField(m, at, sx > 0 and GX - 13.25 or -GX, sx > 0 and GX or -(GX - 13.25), -VZ, VZ, FY2, 2, 4, rng, STONE, "MezzSlab")
		D(m, at(sx * (GX - 13.9), (yS - 0.4 + FY2 + 0.25) / 2, 0), Vector3.new(0.4, FY2 + 0.25 - (yS - 0.4), 2 * VZ + 0.6), C.white, MAT.SmoothPlastic, "BridgeFascia")
		N(m, at(sx * (GX - 14.13), FY2 - 2.6, 0), Vector3.new(0.06, 0.14, 2 * VZ), C.coolLight, "MezzLed")
		-- 다리 아래 천장 + 선형 조명
		D(m, at(sx * (GX - 7), yS + 0.15, 0), Vector3.new(14, 0.3, 2 * VZ), C.plaster, MAT.Plaster, "BridgeSoffit")
		N(m, at(sx * (GX - 7), yS - 0.04, 0), Vector3.new(0.4, 0.1, 2 * VZ - 6), C.warmLight, "SoffitLight")
	end
	balustrade(m, at(-(GX - 13.5), FY2, 0, math.pi / 2), 2 * VZ + 1)
	local gap = 6.2
	for _, sz in { -1, 1 } do
		local z0, z1 = gap, VZ + 0.5
		balustrade(m, at(GX - 13.5, FY2, sz * (z0 + z1) / 2, math.pi / 2), z1 - z0)
	end

	--------------------------------------------------------------------------------------------------
	-- 메자닌 아래 1층 보행로 천장(4.9 m): 석고 천장 + 선형 조명 2 + 스프링클러·감지기·스피커·CCTV + 행잉 안내 사인
	--------------------------------------------------------------------------------------------------
	for _, sz in { -1, 1 } do
		local zc = sz * (VZ + GZ) / 2
		D(m, at(0, yS + 0.15, zc), Vector3.new(2 * GX, 0.3, GZ - VZ), C.plaster, MAT.Plaster, "SoffitCeiling")
		for _, zz in { VZ + 4.0, GZ - 4.0 } do
			N(m, at(0, yS - 0.04, sz * zz), Vector3.new(2 * GX - 8, 0.1, 0.4), C.warmLight, "SoffitLight")
		end
		for k = 0, 14 do
			sprinkler(m, at(-105 + k * 15, yS, zc))
		end
		for _, x in { -97.5, -37.5, 22.5, 82.5 } do
			smokeDetector(m, at(x, yS, zc))
		end
		for _, x in { -67.5, -7.5, 52.5 } do
			speaker(m, at(x, yS, zc))
		end
		for _, x in { -40, 80 } do
			Props.cctv(m, at(x, yS, sz * (VZ + 2.0)))
		end
		-- 행잉 안내 사인(양면, 진행 방향 기준 ↑ = 앞으로)
		for _, sp in { { -60, "↑ 정문 MAIN ENTRANCE · 에스컬레이터 ESCALATOR", "↑ 고객센터 INFORMATION · 화장실 RESTROOM" }, { 30, "↑ 에스컬레이터 ESCALATOR · 2F 푸드코트 FOOD COURT", "↑ 정문 MAIN ENTRANCE · 고객센터 INFORMATION" } } do
			local hx = sp[1] + (if sz < 0 then 8 else 0)
			for _, rz in { -2.6, 2.6 } do
				D(m, at(hx, yS - 0.55, zc + rz), Vector3.new(0.08, 1.1, 0.08), rgb(60, 60, 64), MAT.Metal, "SignRod")
			end
			local hs = Kit.part(m, at(hx, yS - 1.65, zc, FACE_NX), Vector3.new(7.6, 1.15, 0.2), { name = "HangingSign", material = MAT.SmoothPlastic, color = rgb(40, 42, 46), collide = false, query = false, shadow = false })
			Kit.label(hs, FRONT, sp[2], { color = rgb(244, 244, 240), glow = true, pixelsPerStud = 30, maxDistance = 400 })
			Kit.label(hs, BACK, sp[3], { color = rgb(244, 244, 240), glow = true, pixelsPerStud = 30, maxDistance = 400 })
		end
	end
	Props.exitSign(m, at(-10, 16.0, GZ - 0.25), nil, false) -- 통로 입구 위 벌크헤드
	Props.exitSign(m, at(-96.0, yS - 1.0 - 0.233, -(VZ + GZ) / 2, FACE_PX), "left", true)

	--------------------------------------------------------------------------------------------------
	-- 에스컬레이터 한 쌍(동쪽 다리로): 30°, 층고 6 m
	--------------------------------------------------------------------------------------------------
	local xTop = GX - 14
	local run = (FY2 - FY1) / math.tan(math.rad(30))
	local xb = xTop - 4 - run
	escalator(m, HF, xb, xTop - 4, -3.2, FY1, FY2, true)
	escalator(m, HF, xb, xTop - 4, 3.2, FY1, FY2, false)
	sign(m, at(xb - 6.5, FY1 + 6.2, 0, FACE_NX), Vector3.new(5.6, 1.4, 0.12), rgb(24, 26, 32), MAT.SmoothPlastic, "↑ 2F  푸드코트 · 리빙", C.textWarm, 40)
	D(m, at(xb - 6.5, FY1 + 2.75, 0.2), Vector3.new(0.3, 5.3, 0.3), C.steelDark, MAT.Metal, "SignPost")
	D(m, at(xb - 6.5, FY1 + 0.08, 0.2), Vector3.new(1.4, 0.16, 1.4), C.steelDark, MAT.Metal, "SignFoot")

	--------------------------------------------------------------------------------------------------
	-- 상점 천장 / 1층 벌크헤드 / 클리어스토리 / 칸막이 기둥(상단은 2층 천장 속으로) / 양 끝벽
	--------------------------------------------------------------------------------------------------
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
			S(m, at(x, (FY1 - 0.3 + c2B + 0.45) / 2, sz * (GZ - 0.6 + SD) / 2), Vector3.new(1.2, c2B + 0.75 - FY1, SD - GZ + 0.6), rgb(232, 230, 224), MAT.Limestone, "Pilaster")
		end
	end
	for _, sx in { -1, 1 } do
		S(m, at(sx * (GX + 0.1), (FY1 - 0.3 + H) / 2, 0), Vector3.new(1.0, H - FY1 + 0.3, 2 * GZ - 1.2), C.travertine, MAT.Limestone, "EndWall")
	end
	-- 서쪽 끝벽: 몰 이름 + 안내 / 동쪽 끝벽: 미디어 스크린(다리 위)
	sign(m, at(-GX + 0.45, FY2 + 23, 0, FACE_PX), Vector3.new(40, 7, 0.12), rgb(20, 24, 34), MAT.SmoothPlastic, "아트리움 몰   ATRIUM MALL", rgb(200, 226, 255), 16)
	N(m, at(-GX + 0.43, FY2 + 19.2, 0, FACE_PX), Vector3.new(40, 0.18, 0.08), rgb(120, 182, 255), "SignLine")
	sign(m, at(-GX + 0.45, FY1 + 11.0, 0, FACE_PX), Vector3.new(16, 2.0, 0.12), rgb(24, 26, 32), MAT.SmoothPlastic, "← 화장실 RESTROOM   ·   수유실 NURSING ROOM →", C.textWarm, 30)
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

	--------------------------------------------------------------------------------------------------
	-- 정면 입구 통로(9 m × 16 m): 석재 패널 + 천장 설비 + 문 + 매트 + 안내/광고/ATM/소방/우산
	--------------------------------------------------------------------------------------------------
	local pz0, pz1 = GZ + 0.4, HZ - 1.8 -- 패널 구간(필라스터 앞면 뒤 ~ 문틀 앞)
	local cladT = 0.3
	local CF = PW - cladT -- 패널 앞면 |x|
	for _, sx in { -1, 1 } do
		S(m, at(sx * (EX - 0.1), (FY1 - 0.3 + c1B + 0.6) / 2, (SD + HZ - 1.6) / 2), Vector3.new(1.0, c1B + 0.9 - FY1, HZ - 1.6 - SD), C.travertine, MAT.Limestone, "PassageWall")
		D(m, at(sx * (PW - 0.05), (FY1 + c1B) / 2, (pz0 + pz1) / 2), Vector3.new(0.1, c1B - FY1, pz1 - pz0), rgb(60, 58, 56), MAT.SmoothPlastic, "RevealBacking")
		local ncol, nrow = 8, 2
		local pwid = (pz1 - pz0) / ncol
		local ph = (c1B + 0.1 - (FY1 + 0.55)) / nrow
		for i = 0, ncol - 1 do
			for j = 0, nrow - 1 do
				D(m, at(sx * (PW - cladT / 2), FY1 + 0.55 + (j + 0.5) * ph, pz0 + (i + 0.5) * pwid), Vector3.new(cladT, ph - 0.12, pwid - 0.12), jit(rng, rgb(214, 206, 192), 0.03), MAT.Marble, "WallPanel")
			end
		end
		D(m, at(sx * (CF + 0.03), FY1 + 0.28, (pz0 + pz1) / 2), Vector3.new(0.4, 0.56, pz1 - pz0), C.steel, MAT.Metal, "Skirting", 0.2)
		-- 천장 코브 조명(벽 위 띠)
		N(m, at(sx * (CF - 0.25), c1B - 0.06, (pz0 + pz1) / 2), Vector3.new(0.3, 0.12, pz1 - pz0), C.warmLight, "CoveLight")
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
	for _, x in { -9.5, 0, 9.5 } do
		for k = 0, 4 do
			sprinkler(m, at(x, c1B, 40 + k * 10.7))
		end
	end
	local det2 = smokeDetector(m, at(0, c1B, 45.3))
	smokeDetector(m, at(0, c1B, 66.7))
	for _, p in { { -9.5, 45.3 }, { 9.5, 45.3 }, { -9.5, 66.7 }, { 9.5, 66.7 } } do
		D(m, at(p[1], c1B - 0.03, p[2]), Vector3.new(2.0, 0.1, 2.0), rgb(240, 240, 236), MAT.SmoothPlastic, "Diffuser")
		D(m, at(p[1], c1B - 0.1, p[2]), Vector3.new(0.9, 0.06, 0.9), rgb(206, 206, 202), MAT.SmoothPlastic, "DiffuserCore")
	end
	speaker(m, at(0, c1B, 56.0))
	speaker(m, at(0, c1B, 77.4))
	Props.cctv(m, at(-12.5, c1B, 38.5))
	Props.cctv(m, at(12.5, c1B, 85.0))
	light(det2, "PointLight", { color = rgb(255, 232, 200), brightness = 0.9, range = 26 })
	for _, dx in Hl.doorXs do
		Props.exitSign(m, at(dx, c1B - 1.42, 86.4), nil, true)
	end
	-- 열린 자동문 4 짝: 유리 + 세로틀 2 + 상·하부 레일(틀보다 안쪽, 같은 면 없음)
	local DW, DH = Hl.doorW, Hl.doorH
	for i, dx in Hl.doorXs do
		for _, sx in { -1, 1 } do
			local lx = dx + sx * (DW / 2 + 2.1 - 0.25)
			local zl = if (i == 1 and sx == 1) then HZ - 1.4 else HZ - 1.0
			local lc = at(lx, FY1, zl)
			G(m, lc * CFrame.new(0, (0.4 + DH - 0.25) / 2, 0), Vector3.new(3.9, DH - 0.65, 0.12), C.glass, 0.62, false, "DoorLeaf")
			for _, ex in { -1, 1 } do
				D(m, lc * CFrame.new(ex * 1.98, (0.06 + DH) / 2, 0), Vector3.new(0.24, DH - 0.06, 0.32), C.steelDark, MAT.Metal, "LeafStile")
			end
			D(m, lc * CFrame.new(0, 0.3, 0), Vector3.new(3.82, 0.4, 0.22), C.steelDark, MAT.Metal, "LeafRail")
			D(m, lc * CFrame.new(0, DH - 0.22, 0), Vector3.new(3.82, 0.35, 0.22), C.steelDark, MAT.Metal, "LeafRail")
		end
	end
	-- 매립형 알루미늄 현관 매트(테 + 매트 + 리브 7)
	local mz0, mz1 = HZ - 10.5, HZ - 0.55
	D(m, at(0, FY1 - 0.1, (mz0 + mz1) / 2), Vector3.new(2 * PW - 0.2, 0.3, mz1 - mz0), rgb(170, 172, 176), MAT.Metal, "MatFrame")
	D(m, at(0, FY1 - 0.05, (mz0 + 0.3 + HZ - 2.0) / 2), Vector3.new(2 * PW - 0.8, 0.3, HZ - 2.0 - mz0 - 0.3), rgb(48, 46, 44), MAT.Fabric, "EntranceMat")
	for k = 1, 7 do
		D(m, at(0, FY1 + 0.12, mz0 + 0.3 + k * (HZ - 2.3 - mz0) / 8), Vector3.new(2 * PW - 1.0, 0.06, 0.14), rgb(150, 152, 156), MAT.Metal, "MatRib")
	end
	-- 서쪽 벽: 라이트박스 광고 2 + 소화기 / 동쪽 벽: 365 ATM 코너 + 옥내소화전 + 광고 1
	local function lightbox(sx: number, z: number, bg: Color3, text: string, tc: Color3)
		local yaw = if sx < 0 then FACE_PX else FACE_NX
		D(m, at(sx * (CF - 0.15), FY1 + 5.6, z, yaw), Vector3.new(4.4, 6.6, 0.3), rgb(70, 72, 76), MAT.Metal, "LightboxFrame")
		sign(m, at(sx * (CF - 0.36), FY1 + 5.6, z, yaw), Vector3.new(4.0, 6.2, 0.12), bg, MAT.Neon, text, tc, 24)
	end
	lightbox(-1, 41.5, rgb(214, 200, 182), "F/W 2026\n가을 신상품\nNEW SEASON\n\n2F 패션관", rgb(40, 36, 32))
	lightbox(-1, 48.0, rgb(36, 60, 110), "ATRIUM MALL\n앱 APP\n\n주차 3시간 무료\nFREE PARKING", rgb(255, 255, 255))
	lightbox(1, 70.0, rgb(196, 40, 44), "AUTUMN\nFESTIVAL\n가을 페스티벌\n11.01 – 11.30", rgb(255, 255, 255))
	Props.extinguisher(m, at(-(CF - 0.42), FY1, 56.0, FACE_PX), true)
	Props.hydrant(m, at(CF, FY1, 62.5, FACE_NX))
	-- 365 자동화코너(ATM 3)
	local az = 46.5
	D(m, at(CF - 0.1, FY1 + 4.3, az, FACE_NX), Vector3.new(12.4, 8.6, 0.2), rgb(52, 56, 62), MAT.SmoothPlastic, "AtmSurround")
	sign(m, at(CF - 0.26, FY1 + 7.8, az, FACE_NX), Vector3.new(11.6, 1.3, 0.12), rgb(20, 90, 170), MAT.Neon, "ATM  365 자동화코너  24H", rgb(255, 255, 255), 30)
	for k = -1, 1 do
		local ac = at(CF - 0.2, FY1, az + k * 3.7, FACE_NX)
		S(m, ac * CFrame.new(0, 2.75, -0.85), Vector3.new(2.6, 5.4, 1.7), rgb(196, 198, 202), MAT.Metal, "Atm", 0.1)
		local scr = N(m, ac * CFrame.new(0, 4.25, -1.68) * CFrame.Angles(math.rad(-12), 0, 0), Vector3.new(1.5, 1.1, 0.06), rgb(60, 130, 210), "AtmScreen")
		Kit.label(scr, FRONT, "거래를 선택하세요", { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 40, maxDistance = 60 })
		D(m, ac * CFrame.new(0, 3.3, -1.95) * CFrame.Angles(math.rad(20), 0, 0), Vector3.new(2.0, 0.14, 0.8), rgb(60, 62, 66), MAT.Metal, "AtmKeypad")
		D(m, ac * CFrame.new(0.7, 3.75, -1.72), Vector3.new(0.5, 0.12, 0.06), rgb(20, 20, 22), MAT.SmoothPlastic, "CardSlot")
	end
	-- 층별 안내 토템(들어오는 사람을 봄) + 우산 비닐 커버기 + 쓰레기통
	Props.signTotem(m, at(-10.5, FY1, 78.0, math.pi), "층별 안내 FLOOR GUIDE", "2F  푸드코트 · 리빙 · 전자\n      스포츠 · 아동 · 약국\n1F  카페 · 베이커리 · 화장품\n      서점 · 주얼리 · 패션\n\n← 화장실 · 고객센터 (1F 서쪽)", rgb(36, 60, 110))
	local uc = at(11.6, FY1, 84.0, FACE_NX)
	S(m, uc * CFrame.new(0, 1.55, 0), Vector3.new(1.6, 3.0, 1.1), rgb(200, 202, 206), MAT.Metal, "UmbrellaWrapper", 0.15)
	D(m, uc * CFrame.new(0, 3.1, 0), Vector3.new(1.7, 0.12, 1.2), rgb(60, 62, 66), MAT.Metal, "WrapperTop")
	for _, ox in { -0.4, 0.4 } do
		cyl(m, uc * CFrame.new(ox, 3.19, 0), 0.06, 0.45, rgb(20, 20, 22), MAT.SmoothPlastic, "WrapperSlot")
	end
	local ul = D(m, uc * CFrame.new(0, 2.0, -0.58), Vector3.new(1.3, 1.4, 0.06), rgb(40, 110, 190), MAT.SmoothPlastic, "WrapperLabel")
	Kit.label(ul, FRONT, "우산 비닐\n커버\nUMBRELLA\nBAG", { color = rgb(255, 255, 255), glow = false, pixelsPerStud = 50, maxDistance = 80 })
	VC(m, uc * CFrame.new(1.7, 1.2, 0), 2.4, 1.1, rgb(200, 202, 206), MAT.Metal, true, "BagBin")
	-- 통로 입구(갤러리아 쪽) 벌크헤드 위 안내
	sign(m, at(0, FY1 + 15.6, GZ - 0.3, 0), Vector3.new(14, 1.1, 0.1), rgb(40, 42, 46), MAT.SmoothPlastic, "정문 출구 MAIN EXIT  ·  잠실역 JAMSIL STN.", rgb(244, 244, 240), 30)

	--------------------------------------------------------------------------------------------------
	-- 보이드 펜던트 3(실제 광원)
	--------------------------------------------------------------------------------------------------
	local vaultY = H + 0.8 + m2s(10) - 1
	for _, px in { -60, -20, 20 } do
		local gy = FY2 + 16
		D(m, at(px, (gy + vaultY) / 2, 0), Vector3.new(0.12, vaultY - gy, 0.12), C.black, MAT.Metal, "PendantCable")
		local g = Kit.ball(m, (at(px, gy, 0)).Position, 3.2, rgb(255, 226, 180), MAT.Neon, { name = "PendantGlobe", collide = false, query = false, shadow = false, glow = true, dayMaterial = MAT.Glass, dayColor = rgb(236, 230, 220) })
		D(m, at(px, gy + 1.9, 0), Vector3.new(1.4, 0.6, 1.4), C.bronze, MAT.Metal, "PendantCap", 0.2)
		light(g, "PointLight", { color = rgb(255, 222, 176), brightness = 1.4, range = 58 })
	end

	--------------------------------------------------------------------------------------------------
	-- 상점 27 (1층 북/남 + 2층 북/남). 광원: 1층 전부, 2층 일부
	--------------------------------------------------------------------------------------------------
	local rowsDef = {
		{ s = 1, yf = FY1, ceilB = c1B, list = SHOPS_L1P, skip = mid, l1 = true },
		{ s = -1, yf = FY1, ceilB = c1B, list = SHOPS_L1N, skip = -1, l1 = true },
		{ s = 1, yf = FY2, ceilB = c2B, list = SHOPS_L2P, skip = -1, l1 = false },
		{ s = -1, yf = FY2, ceilB = c2B, list = SHOPS_L2N, skip = -1, l1 = false },
	}
	for _, row in rowsDef do
		local idx = 0
		for k = 0, nS - 1 do
			if k ~= row.skip then
				idx += 1
				local spec = row.list[idx]
				if spec then
					local lit = row.l1 or LIT_L2[spec.ko] == true
					buildShop(m, HF, -GX + k * sw, -GX + (k + 1) * sw, row.s, row.yf, row.ceilB, GZ, SD, spec, rng, row.l1, lit, if row.l1 then yS else nil)
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------------
	-- 갤러리아 1층: 나무 3(석재 좌대 + 원목 좌석 링 + 화분 + 업라이트), 팝업 키오스크, 안내 데스크, 벤치, 분리수거, 토템
	--------------------------------------------------------------------------------------------------
	for _, ix in { -78, -18, 26 } do
		local cf = at(ix, FY1, 0)
		VC(m, cf * CFrame.new(0, 0.65, 0), 1.3, 14.0, rgb(196, 192, 184), MAT.Granite, true, "SeatBase")
		VC(m, cf * CFrame.new(0, 1.34, 0), 0.18, 14.4, C.oak, MAT.Wood, true, "SeatRim")
		local top = Props.planter(m, cf * CFrame.new(0, 1.43, 0), "round", 2.7, 0.55, rgb(206, 202, 194), MAT.Concrete)
		Props.tree(m, cf * CFrame.new(0, 1.43 + top, 0), 7.2, rng, { collide = true })
		for a = 0, 2 do
			local ang = a * math.pi * 2 / 3 + 0.4
			local up = cf * CFrame.new(math.cos(ang) * 3.4, 1.43 + top + 0.1, math.sin(ang) * 3.4)
			cyl(m, up, 0.3, 0.4, rgb(60, 60, 64), MAT.Metal, "Uplight")
			N(m, up * CFrame.new(0, 0.28, 0), Vector3.new(0.28, 0.05, 0.28), rgb(255, 236, 200), "UplightLens")
		end
	end
	-- 팝업 키오스크
	local kc = at(-48, FY1, 0)
	S(m, kc * CFrame.new(0, 1.7, 0), Vector3.new(9, 3.4, 4), rgb(250, 250, 248), MAT.Wood, "KioskCounter")
	D(m, kc * CFrame.new(0, 3.48, 0), Vector3.new(9.4, 0.16, 4.4), C.oak, MAT.Wood, "KioskTop")
	for _, sx in { -1, 1 } do
		D(m, kc * CFrame.new(sx * 4.4, 6.2, 0), Vector3.new(0.3, 5.4, 0.3), C.steelDark, MAT.Metal, "KioskPost")
	end
	D(m, kc * CFrame.new(0, 9.1, 0), Vector3.new(10, 0.5, 5.2), rgb(196, 54, 42), MAT.SmoothPlastic, "KioskRoof")
	local ks2 = sign(m, kc * CFrame.new(0, 8.2, 0), Vector3.new(9, 1.3, 4.6), rgb(250, 246, 240), MAT.SmoothPlastic, "팝업스토어  POP-UP", rgb(196, 54, 42), 30)
	Kit.label(ks2, BACK, "팝업스토어  POP-UP", { color = rgb(196, 54, 42), glow = true, pixelsPerStud = 30, maxDistance = 500 })
	facings(m, kc * CFrame.new(0, 3.56, -0.6), 8.0, 0.9, 1.6, facingRects(rng, 8.0, 0.4, 0.8, 0.6, 0.95, PACK_C, true), rgb(220, 216, 210), 24)
	D(m, kc * CFrame.new(3.2, 3.74, 1.5), Vector3.new(0.5, 0.36, 0.5), C.black, MAT.SmoothPlastic, "PosBase")
	D(m, kc * CFrame.new(3.2, 4.32, 1.55) * CFrame.Angles(math.rad(14), 0, 0), Vector3.new(1.2, 0.85, 0.1), rgb(30, 30, 34), MAT.SmoothPlastic, "PosScreen")
	-- 안내 데스크(서쪽 끝, 다리 아래)
	local ic = at(-GX + 4.5, FY1, 0, FACE_PX)
	S(m, ic * CFrame.new(0, 1.75, 0), Vector3.new(10, 3.4, 2.4), rgb(250, 250, 248), MAT.SmoothPlastic, "InfoDesk")
	D(m, ic * CFrame.new(0, 3.53, -0.1), Vector3.new(10.4, 0.16, 2.8), C.oak, MAT.Wood, "InfoDeskTop")
	sign(m, ic * CFrame.new(0, 2.0, -1.23), Vector3.new(6, 1.0, 0.06), rgb(36, 60, 110), MAT.SmoothPlastic, "INFORMATION  고객센터", rgb(255, 255, 255), 40)
	for _, ox in { -2.4, 2.4 } do
		D(m, ic * CFrame.new(ox, 4.1, 0.4) * CFrame.Angles(math.rad(14), 0, 0), Vector3.new(1.6, 1.0, 0.1), rgb(30, 30, 34), MAT.SmoothPlastic, "InfoMonitor")
	end
	-- 벤치 + 분리수거함 + 안내 토템
	for _, bp in { { -32, 1 }, { 6, 1 }, { -62, -1 }, { 6, -1 } } do
		bench(m, at(bp[1], FY1, bp[2] * (VZ + 4), if bp[2] > 0 then FACE_NZ else FACE_PZ), m2s(2.4), C.oak)
	end
	Props.bin(m, at(-38, FY1, VZ + 4.2, FACE_NZ))
	Props.bin(m, at(12, FY1, -(VZ + 4.2), FACE_PZ))
	Props.signTotem(m, at(46, FY1, -10.5, FACE_PX), "층별 안내 FLOOR GUIDE", "2F  푸드코트 FOOD COURT\n      리빙 · 전자 · 스포츠\n1F  카페 · 베이커리 · 꽃\n      화장품 · 서점 · 주얼리", rgb(196, 40, 44))
	-- 2층 보행로: 벤치 + 긴 화분(관목) + 분리수거
	for _, bp in { { -60, 1 }, { 20, 1 }, { -20, -1 }, { 60, -1 } } do
		bench(m, at(bp[1], FY2, bp[2] * (GZ - 4), if bp[2] > 0 then FACE_NZ else FACE_PZ), m2s(2.4), C.oak)
	end
	for _, pp in { { -40, 1 }, { 40, 1 }, { -40, -1 }, { 40, -1 } } do
		local pcf = at(pp[1], FY2, pp[2] * (VZ + 2.6))
		local ptop = Props.planter(m, pcf, "trough", 1.0, 0.6, rgb(70, 68, 66), MAT.Concrete)
		Props.shrub(m, pcf * CFrame.new(0, ptop, 0), 2.2, 0.8, rng)
	end
	Props.bin(m, at(-2, FY2, GZ - 4.0, FACE_NZ))
	Props.signTotem(m, at(103, FY2, 10.5, FACE_NX), "2F 안내 FLOOR GUIDE", "푸드코트 FOOD COURT →\n리빙 · 전자 · 음반\n남성 · 가방 · 팝업\n찻집 · 약국 · 분식", rgb(36, 60, 110))

	--------------------------------------------------------------------------------------------------
	-- 클리어스토리 행잉 배너 6 + 벽 조명
	--------------------------------------------------------------------------------------------------
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
			N(m, at(x, FY2 + 9.5, sz * (GZ - 0.45), if sz > 0 then FACE_NZ else FACE_PZ), Vector3.new(1.0, 2.2, 0.3), C.warmLight, "Sconce")
		end
	end
end

MallInterior.build = buildMall
return MallInterior
