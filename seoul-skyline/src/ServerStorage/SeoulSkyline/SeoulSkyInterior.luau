--!strict
-- SeoulSkyline / SeoulSkyInterior
-- 서울스카이 전망대 실내(118F 전망 홀 + 스카이데크 + 카페/기념품 + 123F 스카이 라운지).
-- LandmarkInterior 가 require 해서 호출(Landmark.layout 좌표). 공용 헬퍼/가구는 InteriorKit.

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)
local IK = require(script.Parent.InteriorKit)
local Landmark = require(script.Parent.Landmark) :: any

local P, Real, m2s, rgb, MAT = IK.P, IK.Real, IK.m2s, IK.rgb, IK.MAT
local FRONT, BACK, CYL_UP = IK.FRONT, IK.BACK, IK.CYL_UP
local FACE_PZ, FACE_NZ, FACE_PX, FACE_NX = IK.FACE_PZ, IK.FACE_NZ, IK.FACE_PX, IK.FACE_NX
local SEAT, TABLE_H, COUNTER, C = IK.SEAT, IK.TABLE_H, IK.COUNTER, IK.C
local light, S, D, N, G, VC, sign = IK.light, IK.S, IK.D, IK.N, IK.G, IK.VC, IK.sign
local elevatorButton, elevatorDoor, callPanel, stanchions = IK.elevatorButton, IK.elevatorDoor, IK.callPanel, IK.stanchions
local sofa, chair, roundTable, bench = IK.sofa, IK.chair, IK.roundTable, IK.bench
local treePlanter, pottedPlant, telescope = IK.treePlanter, IK.pottedPlant, IK.telescope
type PartOpts = Kit.PartOpts

local SeoulSkyInterior = {}

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


SeoulSkyInterior.build = buildObservatory
SeoulSkyInterior.CORE_H = CORE_H
SeoulSkyInterior.PRODUCT_C = PRODUCT_C
return SeoulSkyInterior
