--!strict
-- SeoulSkyline / Props
-- 실내·실외 공용 "실물 같은" 소품 라이브러리. 모든 치수는 실측(m → Config.m) 기준, cf = 바닥(또는 붙는 면) 위 기준점,
-- 로컬 -Z = 정면(사람이 보는/서는 쪽). 결정적: 난수는 호출자가 넘긴 rng 만 사용.
--
-- 규칙(엄격): 보이는 면끼리 같은 평면 금지 — 붙는 부품은 0.05 stud 이상 튀어나오거나 부모 속으로 파묻힘.
--   흙/자갈 윗면은 화분 테두리보다 0.25 stud 낮음. 라벨 띠는 상품 앞면보다 0.05 stud 앞. 천장 부착물은 천장 속으로 0.03 묻힘.
--
-- 식물/나무
--   Props.tree(parent, cf, heightM, rng, opts?)          가지 + 잎 뭉치(12~24)로 된 활엽수(실내 피쿠스/올리브/느티 스타일)
--   Props.planter(parent, cf, kind, wM, hM, color?, mat?) 화분(round|square|trough) + 흙/자갈 마감 → 윗면 높이(stud) 반환
--   Props.monstera / sansevieria / areca / fiddle(parent, cf, heightM, rng, potColor?)   화분 포함 관엽식물
--   Props.shrub(parent, cf, wM, hM, rng)                  회양목류 덤불(잎 뭉치 여러 개)
-- 상품/진열
--   Props.fillShelf(parent, cf, wM, dM, hM, kind, rng)   선반 윗면(cf = 앞 가장자리 가운데, 로컬 +Z = 안쪽)을 상품 페이싱으로 채움
--      kind: "box" "bottle" "can" "jar" "book" "folded" "shoe" "mug" "cosmetic" "snack" "plush" "gift" "ramen" "drink"
--   Props.hangRail(parent, cf, wM, rng, palette?)         옷걸이 봉 + 걸린 옷(셔츠/재킷 실루엣)
-- 천장/설비/안전 (한국 실내 규격 느낌)
--   Props.ceilingKit(parent, cf, wM, dM, opts?)           천장 아랫면(cf, 로컬 Y = 아래로 보는 면 법선 반대) 스프링클러·감지기·디퓨저·스피커·점검구
--   Props.exitSign(parent, cf, arrow?)                     피난구유도등(녹색, "비상구 EXIT" + 화살표), cf = 부착면 위 중심
--   Props.extinguisher(parent, cf, withSign?)              분말 소화기(받침대 + "소화기" 표지)
--   Props.hydrant(parent, cf)                              옥내소화전함(적색 표시등 + 문 + 표지)
--   Props.cctv(parent, cf)                                 천장 돔 카메라
--   Props.outlet(parent, cf, kind?)                        벽 콘센트/스위치 플레이트(kind "outlet"|"switch"|"card")
--   Props.bin(parent, cf, kinds?)                          분리수거함(스테인리스, 일반/재활용/캔 투입구)
--   Props.signTotem(parent, cf, title, lines, accent?)     안내 사인 토템(층별 안내/길 안내)

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local Props = {}

local rgb = Color3.fromRGB
local M = Config.m
local MAT = Enum.Material
local CYL_UP = CFrame.Angles(0, 0, math.rad(90))
local FRONT = Enum.NormalId.Front

local function D(m: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material, name: string?, refl: number?): BasePart
	return Kit.part(m, cf, size, { name = name or "Prop", material = mat, color = color, collide = false, query = false, reflectance = refl })
end
local function S(m: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material, name: string?, refl: number?): BasePart
	return Kit.part(m, cf, size, { name = name or "Solid", material = mat, color = color, collide = true, reflectance = refl })
end
-- 세로 원기둥: cf 의 위치 = 중심, cf 회전의 Y 축 = 원기둥 축
local function cylY(m: Instance, cf: CFrame, h: number, d: number, color: Color3, mat: Enum.Material, name: string?, collide: boolean?): BasePart
	local c = collide == true
	return Kit.part(m, cf * CYL_UP, Vector3.new(h, d, d), { name = name or "Cyl", shape = "Cylinder", material = mat, color = color, collide = c, query = c })
end
local function glowPart(m: Instance, cf: CFrame, size: Vector3, color: Color3, name: string, shape: string?): BasePart
	return Kit.part(m, cf, size, {
		name = name,
		shape = shape,
		material = MAT.Neon,
		color = color,
		collide = false,
		query = false,
		shadow = false,
		glow = true,
		dayMaterial = MAT.SmoothPlastic,
		dayColor = color:Lerp(rgb(236, 236, 232), 0.5),
	})
end
local function jitter(rng: Random, c: Color3, amt: number): Color3
	local k = 1 + rng:NextNumber(-amt, amt)
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end
local function pick<T>(rng: Random, t: { T }): T
	return t[rng:NextInteger(1, #t)]
end
Props.pick = pick
Props.jitter = jitter

------------------------------------------------------------------------------------------------------
-- 식물
------------------------------------------------------------------------------------------------------
local LEAF = { rgb(52, 92, 46), rgb(64, 104, 52), rgb(78, 116, 58), rgb(46, 82, 44), rgb(70, 110, 64) }
local LEAF_OLIVE = { rgb(104, 118, 86), rgb(118, 130, 96), rgb(92, 108, 80) }
local LEAF_TROPIC = { rgb(36, 84, 44), rgb(44, 96, 50), rgb(30, 72, 40) }
local BARK = rgb(88, 72, 58)
local SOIL = rgb(70, 58, 46)
local PEBBLE = rgb(150, 146, 138)

export type TreeOpts = { leaves: { Color3 }?, crown: number?, trunkColor: Color3?, collide: boolean?, clusters: number? }

-- 활엽수: 줄기 2마디(약간 기울어짐) + 주가지 3~5 + 가지 끝마다 잎 뭉치 3~5 + 정수리 뭉치. h = 전체 높이(m)
function Props.tree(parent: Instance, cf: CFrame, hM: number, rng: Random, opts: TreeOpts?): number
	local o: TreeOpts = opts or {}
	local h = M(hM)
	local leaves = o.leaves or LEAF
	local crown = o.crown or 0.42 -- 수관 반지름 / 높이
	local bark = o.trunkColor or BARK
	local n0 = Kit.stats.parts
	local tD = math.max(0.35, h * 0.032)
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-3, 3)), 0, math.rad(rng:NextNumber(-3, 3)))
	local base = cf * lean
	local t1 = h * 0.38
	cylY(parent, base * CFrame.new(0, t1 / 2, 0), t1, tD, bark, MAT.Wood, "Trunk", o.collide)
	local top = base * CFrame.new(0, t1, 0) * CFrame.Angles(math.rad(rng:NextNumber(-5, 5)), 0, math.rad(rng:NextNumber(-5, 5)))
	local t2 = h * 0.3
	cylY(parent, top * CFrame.new(0, t2 / 2 - 0.1, 0), t2, tD * 0.72, bark, MAT.Wood, "Trunk")
	local leader = (top * CFrame.new(0, t2, 0)).Position
	local nb = rng:NextInteger(3, 5)
	local tips: { Vector3 } = { leader + Vector3.new(0, h * 0.06, 0) }
	local a0 = rng:NextNumber(0, math.pi * 2)
	for i = 1, nb do
		local ang = a0 + (i - 1) * (math.pi * 2 / nb) + rng:NextNumber(-0.35, 0.35)
		local y0 = t1 + (t2 * rng:NextNumber(0.1, 0.8))
		local from = (base * CFrame.new(0, y0, 0)).Position
		local tilt = math.rad(rng:NextNumber(35, 58))
		local len = h * rng:NextNumber(0.24, 0.34)
		local dir = Vector3.new(math.cos(ang) * math.sin(tilt), math.cos(tilt), math.sin(ang) * math.sin(tilt))
		local to = from + dir * len
		local mid = (from + to) / 2
		-- 가지: CFrame.lookAt 의 -Z 를 가지 방향으로 → 원기둥 축(Y)을 가지 방향으로 돌림
		local bc = CFrame.lookAt(mid, to) * CFrame.Angles(math.rad(90), 0, 0)
		cylY(parent, bc, len, tD * rng:NextNumber(0.34, 0.45), bark, MAT.Wood, "Branch")
		table.insert(tips, to)
	end
	-- 잎 뭉치: 가지 끝마다 작은 뭉치 5~7 + 정수리 6 (크기 R×0.22~0.42) → 덩어리가 아닌 잎이 성긴 수관 실루엣.
	-- 가지 끝 근처엔 잔가지(가는 원기둥) 2개로 잎 사이로 보이는 가지 구조를 만듦.
	local R = h * crown
	for ti, tp in tips do
		local nc = if ti == 1 then 7 else rng:NextInteger(6, 8)
		local stemDir = if ti == 1 then Vector3.yAxis else (tp - leader).Unit
		if ti > 1 then
			for _ = 1, 2 do
				local tw = (stemDir + Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0.1, 0.6), rng:NextNumber(-0.6, 0.6))).Unit
				local tl = R * rng:NextNumber(0.2, 0.32)
				cylY(parent, CFrame.lookAt(tp + tw * tl / 2, tp + tw * tl) * CFrame.Angles(math.rad(90), 0, 0), tl, math.max(0.12, tD * 0.16), bark, MAT.Wood, "Twig")
			end
		end
		for _ = 1, nc do
			local s = R * rng:NextNumber(0.3, 0.5)
			local off = Vector3.new(rng:NextNumber(-0.38, 0.38) * R, rng:NextNumber(-0.18, 0.34) * R, rng:NextNumber(-0.38, 0.38) * R)
			local c = jitter(rng, pick(rng, leaves), 0.12)
			local rot = CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.5, 0.5))
			Kit.ellipsoid(parent, CFrame.new(tp + off) * rot, Vector3.new(s, s * rng:NextNumber(0.55, 0.78), s * rng:NextNumber(0.75, 1.0)), c, MAT.Grass, { name = "Foliage", query = false, shadow = s > 3 })
		end
	end
	return Kit.stats.parts - n0
end

-- 화분: kind "round" | "square" | "trough"(직사각), w = 지름/폭(m), h = 높이(m). trough 는 cf 로컬 X 로 길이 = 2.4 × w.
-- 흙(또는 자갈 멀칭) 윗면 높이(stud, cf 기준)를 반환 → 식물 기준점.
function Props.planter(parent: Instance, cf: CFrame, kind: string, wM: number, hM: number, color: Color3?, mat: Enum.Material?, mulch: string?): number
	local w, h = M(wM), M(hM)
	local col = color or rgb(62, 62, 64)
	local mt = mat or MAT.Concrete
	local fill = if mulch == "pebble" then PEBBLE else SOIL
	local fillMat = if mulch == "pebble" then MAT.Pebble else MAT.Ground
	local top = h - 0.25
	if kind == "round" then
		cylY(parent, cf * CFrame.new(0, h / 2, 0), h, w, col, mt, "Planter", true)
		cylY(parent, cf * CFrame.new(0, h - 0.06, 0), 0.24, w + 0.16, col:Lerp(rgb(0, 0, 0), 0.12), mt, "PlanterRim")
		cylY(parent, cf * CFrame.new(0, top - 0.3, 0), 0.6, w - 0.5, fill, fillMat, "Mulch")
		-- 굽(바닥에서 띄운 그림자 선)
		cylY(parent, cf * CFrame.new(0, 0.1, 0), 0.2, w - 0.6, rgb(30, 30, 32), MAT.SmoothPlastic, "PlanterFoot")
	else
		local L = if kind == "trough" then w * 2.4 else w
		S(parent, cf * CFrame.new(0, h / 2 + 0.1, 0), Vector3.new(L, h - 0.2, w), col, mt, "Planter")
		D(parent, cf * CFrame.new(0, 0.1, 0), Vector3.new(L - 0.6, 0.2, w - 0.6), rgb(30, 30, 32), MAT.SmoothPlastic, "PlanterFoot")
		-- 테두리 캡(0.08 바깥으로)
		D(parent, cf * CFrame.new(0, h - 0.06, 0), Vector3.new(L + 0.16, 0.24, w + 0.16), col:Lerp(rgb(0, 0, 0), 0.12), mt, "PlanterRim")
		D(parent, cf * CFrame.new(0, top - 0.3, 0), Vector3.new(L - 0.5, 0.6, w - 0.5), fill, fillMat, "Mulch")
	end
	return top
end

-- 잎(납작한 타원): 줄기 끝 위치·방향·크기
local function leafBlade(parent: Instance, at: Vector3, dir: Vector3, len: number, wid: number, col: Color3, roll: number)
	local cfL = CFrame.lookAt(at + dir * (len / 2), at + dir * len) * CFrame.Angles(0, 0, roll)
	Kit.ellipsoid(parent, cfL, Vector3.new(wid, 0.12, len), col, MAT.SmoothPlastic, { name = "Leaf", query = false, shadow = false })
end
local function stem(parent: Instance, a: Vector3, b: Vector3, d: number, col: Color3)
	local L = (b - a).Magnitude
	if L < 0.05 then
		return
	end
	cylY(parent, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(math.rad(90), 0, 0), L, d, col, MAT.SmoothPlastic, "Stem")
end

local POT_DEFAULT = rgb(226, 222, 214)

function Props.monstera(parent: Instance, cf: CFrame, hM: number, rng: Random, potColor: Color3?)
	local top = Props.planter(parent, cf, "round", hM * 0.32, hM * 0.3, potColor or POT_DEFAULT, MAT.SmoothPlastic)
	local h = M(hM) - top
	local o = (cf * CFrame.new(0, top, 0)).Position
	local n = rng:NextInteger(7, 10)
	for i = 1, n do
		local ang = (i / n) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local rise = rng:NextNumber(0.45, 0.95) * h
		local out = rng:NextNumber(0.18, 0.42) * h
		local tip = o + Vector3.new(math.cos(ang) * out, rise, math.sin(ang) * out)
		stem(parent, o, tip, 0.12, rgb(72, 110, 58))
		local dir = (Vector3.new(math.cos(ang), -0.35, math.sin(ang))).Unit
		local L = h * rng:NextNumber(0.3, 0.42)
		leafBlade(parent, tip, dir, L, L * 0.86, jitter(rng, pick(rng, LEAF_TROPIC), 0.12), rng:NextNumber(-0.3, 0.3))
	end
end

function Props.sansevieria(parent: Instance, cf: CFrame, hM: number, rng: Random, potColor: Color3?)
	local top = Props.planter(parent, cf, "square", hM * 0.3, hM * 0.32, potColor or rgb(46, 46, 48), MAT.SmoothPlastic)
	local h = M(hM) - top
	local n = rng:NextInteger(9, 13)
	for _ = 1, n do
		local L = h * rng:NextNumber(0.6, 1.0)
		local x, z = rng:NextNumber(-0.5, 0.5) * M(hM * 0.18), rng:NextNumber(-0.5, 0.5) * M(hM * 0.18)
		local bcf = cf * CFrame.new(x, top + L / 2 - 0.1, z) * CFrame.Angles(math.rad(rng:NextNumber(-9, 9)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-9, 9)))
		local c = jitter(rng, rgb(54, 86, 52), 0.15)
		Kit.ellipsoid(parent, bcf, Vector3.new(L * 0.12, L, 0.12), c, MAT.SmoothPlastic, { name = "Blade", query = false, shadow = false })
		-- 노란 테두리(실제 산세베리아 로렌티): 살짝 넓고 짧은 판 뒤에
		Kit.ellipsoid(parent, bcf * CFrame.new(0, -L * 0.04, 0.04), Vector3.new(L * 0.14, L * 0.94, 0.1), rgb(176, 168, 92), MAT.SmoothPlastic, { name = "BladeEdge", query = false, shadow = false })
	end
end

function Props.areca(parent: Instance, cf: CFrame, hM: number, rng: Random, potColor: Color3?)
	local top = Props.planter(parent, cf, "round", hM * 0.26, hM * 0.28, potColor or rgb(196, 176, 150), MAT.Concrete)
	local h = M(hM) - top
	local o = (cf * CFrame.new(0, top, 0)).Position
	local n = rng:NextInteger(6, 8)
	for i = 1, n do
		local ang = (i / n) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local rise = rng:NextNumber(0.55, 0.85) * h
		local tip = o + Vector3.new(math.cos(ang) * h * 0.18, rise, math.sin(ang) * h * 0.18)
		stem(parent, o, tip, 0.1, rgb(140, 150, 84))
		-- 아치형 잎: 두 마디(올라가다 처짐)
		local d1 = Vector3.new(math.cos(ang) * 0.8, 0.45, math.sin(ang) * 0.8).Unit
		local d2 = Vector3.new(math.cos(ang) * 0.8, -0.55, math.sin(ang) * 0.8).Unit
		local L = h * rng:NextNumber(0.28, 0.36)
		local c = jitter(rng, rgb(86, 126, 60), 0.1)
		leafBlade(parent, tip, d1, L, L * 0.34, c, 0)
		leafBlade(parent, tip + d1 * L * 0.9, d2, L * 0.9, L * 0.3, c, 0)
	end
end

function Props.fiddle(parent: Instance, cf: CFrame, hM: number, rng: Random, potColor: Color3?)
	local top = Props.planter(parent, cf, "round", hM * 0.24, hM * 0.22, potColor or rgb(232, 228, 220), MAT.SmoothPlastic)
	local h = M(hM) - top
	local base = cf * CFrame.new(0, top, 0)
	cylY(parent, base * CFrame.new(0, h * 0.45, 0), h * 0.9, 0.3, BARK, MAT.Wood, "Trunk")
	local n = rng:NextInteger(12, 16)
	for i = 1, n do
		local t = i / n
		local y = h * (0.35 + 0.62 * t)
		local ang = i * 2.4 + rng:NextNumber(-0.3, 0.3)
		local at = (base * CFrame.new(0, y, 0)).Position
		local dir = Vector3.new(math.cos(ang), rng:NextNumber(-0.1, 0.5), math.sin(ang)).Unit
		local L = M(hM) * rng:NextNumber(0.12, 0.17)
		leafBlade(parent, at, dir, L, L * 0.72, jitter(rng, pick(rng, LEAF), 0.1), rng:NextNumber(-0.5, 0.5))
	end
end

function Props.shrub(parent: Instance, cf: CFrame, wM: number, hM: number, rng: Random, leaves: { Color3 }?)
	local w, h = M(wM), M(hM)
	local n = math.clamp(math.floor(w / 1.8) + 3, 3, 9)
	for _ = 1, n do
		local s = math.min(w, h * 1.6) * rng:NextNumber(0.4, 0.62)
		local off = Vector3.new(rng:NextNumber(-0.5, 0.5) * (w - s), s * 0.38 + rng:NextNumber(0, 0.25) * (h - s * 0.7), rng:NextNumber(-0.25, 0.25) * s)
		Kit.ellipsoid(parent, cf * CFrame.new(off) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Vector3.new(s, math.min(h, s * 0.8), s * 0.9), jitter(rng, pick(rng, leaves or LEAF), 0.12), MAT.Grass, { name = "Shrub", query = false, shadow = false })
	end
end

------------------------------------------------------------------------------------------------------
-- 상품 페이싱
------------------------------------------------------------------------------------------------------
-- 브랜드 느낌 색(포장 바탕, 라벨): 한 "SKU" 는 같은 색으로 2~5개 연속 진열(실제 매대처럼)
local PACK = {
	{ rgb(196, 40, 44), rgb(250, 236, 210) },
	{ rgb(30, 70, 150), rgb(240, 240, 236) },
	{ rgb(250, 196, 40), rgb(196, 40, 44) },
	{ rgb(36, 120, 70), rgb(246, 240, 220) },
	{ rgb(240, 240, 236), rgb(30, 70, 150) },
	{ rgb(232, 110, 40), rgb(250, 240, 220) },
	{ rgb(120, 60, 140), rgb(250, 220, 90) },
	{ rgb(40, 40, 44), rgb(220, 180, 90) },
	{ rgb(236, 140, 170), rgb(255, 255, 255) },
	{ rgb(90, 170, 220), rgb(255, 255, 255) },
}
local BOTTLE = { rgb(40, 110, 60), rgb(200, 60, 40), rgb(230, 230, 226), rgb(60, 120, 200), rgb(240, 196, 60), rgb(120, 70, 40), rgb(160, 210, 230) }
local CLOTH = { rgb(206, 198, 184), rgb(44, 52, 68), rgb(150, 62, 56), rgb(86, 108, 86), rgb(232, 228, 220), rgb(58, 58, 62), rgb(196, 160, 120), rgb(110, 130, 160) }
local BOOKS = { rgb(150, 52, 44), rgb(42, 70, 110), rgb(212, 196, 160), rgb(60, 92, 70), rgb(30, 30, 34), rgb(196, 140, 60), rgb(110, 84, 120), rgb(232, 228, 216) }
local COSM = { rgb(250, 240, 236), rgb(230, 190, 196), rgb(40, 40, 44), rgb(200, 170, 120), rgb(236, 220, 210), rgb(180, 40, 70) }

type Item = { w: number, h: number, d: number, make: (parent: Instance, cf: CFrame, sku: { any }, rng: Random) -> () }

local function labelBand(parent: Instance, cf: CFrame, w: number, h: number, d: number, col: Color3, yc: number, bh: number)
	-- 앞면 띠: 앞면보다 0.05 앞, 뒤는 상자 속
	D(parent, cf * CFrame.new(0, yc, -d / 2 + 0.02), Vector3.new(w - 0.04, bh, 0.14), col, MAT.SmoothPlastic, "PackLabel")
end

local ITEMS: { [string]: (rng: Random) -> Item } = {}
ITEMS.box = function(rng)
	local w, h, d = rng:NextNumber(0.55, 0.9), rng:NextNumber(0.9, 1.3), rng:NextNumber(0.25, 0.4)
	return { w = w, h = h, d = d, make = function(p, cf, sku)
		D(p, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), sku[1], MAT.SmoothPlastic, "Pack")
		labelBand(p, cf, w, h, d, sku[2], h * 0.6, h * 0.22)
	end }
end
ITEMS.snack = function(rng)
	local w, h, d = rng:NextNumber(0.6, 0.85), rng:NextNumber(0.75, 1.0), rng:NextNumber(0.28, 0.4)
	return { w = w, h = h, d = d, make = function(p, cf, sku)
		-- 봉지: 위가 눌린 베개 모양(타원체) + 아래 상자
		D(p, cf * CFrame.new(0, h * 0.4, 0), Vector3.new(w, h * 0.8, d), sku[1], MAT.SmoothPlastic, "Bag")
		Kit.ellipsoid(p, cf * CFrame.new(0, h * 0.8, 0), Vector3.new(w, h * 0.4, d * 0.7), sku[1], MAT.SmoothPlastic, { name = "BagTop", query = false, shadow = false })
		labelBand(p, cf, w, h, d, sku[2], h * 0.45, h * 0.25)
	end }
end
ITEMS.ramen = function(rng)
	local w, h, d = rng:NextNumber(0.55, 0.62), rng:NextNumber(0.42, 0.52), 0.55
	return { w = w, h = h, d = d, make = function(p, cf, sku)
		-- 컵라면: 뚜껑 + 원통 몸통 (2단 적재)
		for k = 0, 1 do
			local y = k * (h + 0.02)
			cylY(p, cf * CFrame.new(0, y + h / 2, 0), h, w, sku[1], MAT.SmoothPlastic, "Cup")
			cylY(p, cf * CFrame.new(0, y + h + 0.01, 0), 0.06, w + 0.04, sku[2], MAT.SmoothPlastic, "Lid")
		end
	end }
end
ITEMS.bottle = function(rng)
	local d = rng:NextNumber(0.24, 0.32)
	local h = rng:NextNumber(0.8, 1.15)
	return { w = d + 0.04, h = h, d = d + 0.04, make = function(p, cf, sku)
		cylY(p, cf * CFrame.new(0, h * 0.36, 0), h * 0.72, d, sku[1], MAT.Glass, "Bottle")
		cylY(p, cf * CFrame.new(0, h * 0.8, 0), h * 0.18, d * 0.45, sku[1], MAT.Glass, "BottleNeck")
		cylY(p, cf * CFrame.new(0, h * 0.94, 0), h * 0.1, d * 0.5, sku[2], MAT.SmoothPlastic, "Cap")
		cylY(p, cf * CFrame.new(0, h * 0.36, 0), h * 0.28, d + 0.04, sku[2], MAT.SmoothPlastic, "BottleLabel")
	end }
end
ITEMS.drink = function(rng)
	local d = 0.22
	local h = rng:NextNumber(0.62, 0.72)
	return { w = d + 0.03, h = h, d = d + 0.03, make = function(p, cf, sku)
		cylY(p, cf * CFrame.new(0, h * 0.42, 0), h * 0.84, d, sku[1], MAT.SmoothPlastic, "PetBottle")
		cylY(p, cf * CFrame.new(0, h * 0.92, 0), h * 0.16, d * 0.5, sku[2], MAT.SmoothPlastic, "Cap")
		cylY(p, cf * CFrame.new(0, h * 0.45, 0), h * 0.24, d + 0.03, sku[2], MAT.SmoothPlastic, "BottleLabel")
	end }
end
ITEMS.can = function(rng)
	local d, h = 0.22, rng:NextNumber(0.4, 0.55)
	return { w = d + 0.02, h = h, d = d + 0.02, make = function(p, cf, sku)
		cylY(p, cf * CFrame.new(0, h / 2, 0), h, d, sku[1], MAT.Metal, "Can")
		cylY(p, cf * CFrame.new(0, h + 0.015, 0), 0.03, d * 0.9, rgb(196, 198, 202), MAT.Metal, "CanTop")
	end }
end
ITEMS.jar = function(rng)
	local d, h = rng:NextNumber(0.3, 0.38), rng:NextNumber(0.35, 0.5)
	return { w = d + 0.03, h = h, d = d + 0.03, make = function(p, cf, sku)
		cylY(p, cf * CFrame.new(0, h * 0.42, 0), h * 0.84, d, sku[1], MAT.Glass, "Jar")
		cylY(p, cf * CFrame.new(0, h * 0.92, 0), h * 0.16, d + 0.02, sku[2], MAT.Metal, "Lid")
	end }
end
ITEMS.book = function(rng)
	local w, h, d = rng:NextNumber(0.08, 0.16), rng:NextNumber(0.7, 0.95), rng:NextNumber(0.5, 0.7)
	return { w = w, h = h, d = d, make = function(p, cf, _sku, r)
		D(p, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), jitter(r, pick(r, BOOKS), 0.1), MAT.SmoothPlastic, "Book")
	end }
end
ITEMS.folded = function(rng)
	local w, d = rng:NextNumber(0.9, 1.1), 0.9
	local n = rng:NextInteger(3, 6)
	return { w = w, h = n * 0.14, d = d, make = function(p, cf, _sku, r)
		local c = pick(r, CLOTH)
		for k = 0, n - 1 do
			D(p, cf * CFrame.new(r:NextNumber(-0.03, 0.03), 0.07 + k * 0.14, r:NextNumber(-0.02, 0.02)), Vector3.new(w - k % 2 * 0.04, 0.13, d), jitter(r, c, 0.06), MAT.Fabric, "Folded")
		end
	end }
end
ITEMS.shoe = function(rng)
	local w, h, d = 0.65, 0.42, 0.95
	return { w = w, h = h, d = d, make = function(p, cf, _sku, r)
		local c = pick(r, CLOTH)
		for _, sx in { -0.16, 0.16 } do
			D(p, cf * CFrame.new(sx, 0.05, 0), Vector3.new(0.28, 0.1, d), rgb(236, 234, 228), MAT.Rubber, "Sole")
			D(p, cf * CFrame.new(sx, 0.2, 0.1), Vector3.new(0.27, 0.22, d * 0.7), c, MAT.Fabric, "Upper")
			Kit.ellipsoid(p, cf * CFrame.new(sx, 0.16, -d * 0.3), Vector3.new(0.27, 0.2, d * 0.42), c, MAT.Fabric, { name = "Toe", query = false, shadow = false })
		end
	end }
end
ITEMS.mug = function(rng)
	local d, h = 0.3, 0.33
	return { w = 0.42, h = h, d = 0.36, make = function(p, cf, sku)
		cylY(p, cf * CFrame.new(-0.04, h / 2, 0), h, d, sku[1], MAT.SmoothPlastic, "Mug")
		D(p, cf * CFrame.new(0.15, h * 0.5, 0), Vector3.new(0.1, h * 0.6, 0.05), sku[1], MAT.SmoothPlastic, "MugHandle")
	end }
end
ITEMS.cosmetic = function(rng)
	local d = rng:NextNumber(0.12, 0.2)
	local h = rng:NextNumber(0.3, 0.55)
	return { w = d + 0.04, h = h, d = d + 0.04, make = function(p, cf, _sku, r)
		local c = pick(r, COSM)
		cylY(p, cf * CFrame.new(0, h * 0.4, 0), h * 0.8, d, c, MAT.SmoothPlastic, "Tube")
		cylY(p, cf * CFrame.new(0, h * 0.9, 0), h * 0.2, d * 0.8, pick(r, { rgb(212, 190, 140), rgb(30, 30, 32), rgb(236, 236, 236) }), MAT.Metal, "TubeCap")
	end }
end
ITEMS.plush = function(rng)
	local s = rng:NextNumber(0.6, 0.85)
	return { w = s, h = s * 1.15, d = s * 0.8, make = function(p, cf, sku)
		Kit.ellipsoid(p, cf * CFrame.new(0, s * 0.35, 0), Vector3.new(s, s * 0.7, s * 0.75), sku[1], MAT.Fabric, { name = "PlushBody", query = false, shadow = false })
		Kit.ellipsoid(p, cf * CFrame.new(0, s * 0.85, -0.04), Vector3.new(s * 0.7, s * 0.6, s * 0.6), sku[1], MAT.Fabric, { name = "PlushHead", query = false, shadow = false })
		for _, ex in { -0.24, 0.24 } do
			Kit.ellipsoid(p, cf * CFrame.new(ex * s, s * 1.12, 0), Vector3.new(s * 0.2, s * 0.24, s * 0.12), sku[1], MAT.Fabric, { name = "PlushEar", query = false, shadow = false })
		end
	end }
end
ITEMS.gift = function(rng)
	local w, h, d = rng:NextNumber(0.6, 1.1), rng:NextNumber(0.35, 0.8), rng:NextNumber(0.5, 0.8)
	return { w = w, h = h, d = d, make = function(p, cf, sku)
		D(p, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), sku[1], MAT.SmoothPlastic, "GiftBox")
		D(p, cf * CFrame.new(0, h / 2 + 0.005, 0), Vector3.new(0.1, h + 0.06, d + 0.06), sku[2], MAT.Fabric, "Ribbon")
	end }
end

export type FillOpts = { gap: number?, maxItems: number?, front: boolean? }

-- 선반 채우기: cf = 선반 윗면 "앞 가장자리 가운데", 로컬 +X = 길이, 로컬 +Z = 선반 안쪽(깊이), w/d/h(m) = 사용 가능 폭/깊이/높이.
-- 같은 SKU 를 2~5 페이싱씩, 깊이 방향으로 1~3 줄. 반환: 만든 상품 수.
function Props.fillShelf(parent: Instance, cf: CFrame, wM: number, dM: number, hM: number, kind: string, rng: Random, opts: FillOpts?): number
	local o: FillOpts = opts or {}
	local w, d, h = M(wM), M(dM), M(hM)
	local gen = ITEMS[kind] or ITEMS.box
	local x = -w / 2 + 0.05
	local count = 0
	local maxN = o.maxItems or 120
	while x < w / 2 - 0.3 and count < maxN do
		local proto = gen(rng)
		if proto.h > h - 0.05 then
			proto = gen(rng)
			if proto.h > h - 0.05 then
				x += 0.4
				continue
			end
		end
		local sku = pick(rng, PACK)
		if kind == "bottle" or kind == "drink" then
			sku = { pick(rng, BOTTLE), pick(rng, PACK)[2] }
		end
		local facings = rng:NextInteger(2, 5)
		if kind == "book" then
			facings = 1
		end
		for _ = 1, facings do
			if x + proto.w > w / 2 - 0.02 or count >= maxN then
				break
			end
			local item = if kind == "book" then gen(rng) else proto
			if item.h > h - 0.05 then
				break
			end
			local rows = if o.front then 1 else math.clamp(math.floor(d / (item.d + 0.04)), 1, 3)
			for r = 0, rows - 1 do
				local zc = 0.06 + item.d / 2 + r * (item.d + 0.04)
				item.make(parent, cf * CFrame.new(x + item.w / 2, 0.005, zc) * CFrame.Angles(0, rng:NextNumber(-0.03, 0.03), 0), sku, rng)
			end
			count += 1
			x += item.w + (if kind == "book" then 0.005 else 0.04)
		end
		-- SKU 사이 틈 (가끔 빈 페이싱 = 팔린 자리)
		x += if rng:NextNumber() < 0.12 then proto.w * 0.8 else (o.gap or 0.08)
	end
	return count
end

-- 옷걸이 봉 + 옷: cf = 봉 중심, 로컬 X = 봉 방향, 옷은 로컬 Z 로 납작
function Props.hangRail(parent: Instance, cf: CFrame, wM: number, rng: Random, palette: { Color3 }?)
	local w = M(wM)
	Kit.hcyl(parent, cf, w, 0.12, rgb(190, 192, 196), MAT.Metal, { name = "Rail", collide = false, query = false, reflectance = 0.2 })
	local x = -w / 2 + 0.35
	local pal = palette or CLOTH
	while x < w / 2 - 0.35 do
		local c = jitter(rng, pick(rng, pal), 0.08)
		local long = rng:NextNumber() < 0.35
		local L = if long then rng:NextNumber(3.4, 4.2) else rng:NextNumber(2.2, 2.7)
		local g = cf * CFrame.new(x, 0, 0) * CFrame.Angles(0, math.pi / 2 + rng:NextNumber(-0.08, 0.08), 0)
		D(parent, g * CFrame.new(0, -0.12, 0), Vector3.new(1.3, 0.06, 0.06), rgb(70, 52, 38), MAT.Wood, "Hanger")
		-- 어깨(사다리꼴 느낌: 위 좁고 아래 넓은 두 판)
		D(parent, g * CFrame.new(0, -0.45, 0), Vector3.new(1.45, 0.6, 0.14), c, MAT.Fabric, "Garment")
		D(parent, g * CFrame.new(0, -0.45 - L / 2, 0), Vector3.new(1.6, L - 0.3, 0.16), c, MAT.Fabric, "Garment")
		x += rng:NextNumber(0.2, 0.32)
	end
end

------------------------------------------------------------------------------------------------------
-- 천장 / 설비 / 안전
------------------------------------------------------------------------------------------------------
export type CeilOpts = { sprinkler: number?, smoke: number?, diffusers: number?, speakers: number?, access: boolean?, grid: boolean?, color: Color3? }

-- cf = 천장 아랫면의 중심(로컬 Y 위 = 천장 속), w × d(m). 스프링클러 간격 기본 3.2 m, 감지기·디퓨저·스피커 개수.
-- grid=true: 600각 텍스 천장 그리드(T-bar 선, 0.04 stud 아래로 돌출).
function Props.ceilingKit(parent: Instance, cf: CFrame, wM: number, dM: number, opts: CeilOpts?)
	local o: CeilOpts = opts or {}
	local w, d = M(wM), M(dM)
	local chrome = rgb(200, 202, 206)
	local white = o.color or rgb(240, 240, 236)
	local sp = M(o.sprinkler or 3.2)
	if sp > 0 and (o.sprinkler ~= 0) then
		local nx, nz = math.max(1, math.floor(w / sp)), math.max(1, math.floor(d / sp))
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				local x = -w / 2 + (i + 0.5) * w / nx
				local z = -d / 2 + (j + 0.5) * d / nz
				cylY(parent, cf * CFrame.new(x, -0.02, z), 0.1, 0.32, chrome, MAT.Metal, "SprinklerRose")
				cylY(parent, cf * CFrame.new(x, -0.17, z), 0.22, 0.09, chrome, MAT.Metal, "SprinklerHead")
				cylY(parent, cf * CFrame.new(x, -0.29, z), 0.03, 0.22, chrome, MAT.Metal, "SprinklerDeflector")
			end
		end
	end
	local function spots(n: number, salt: number): { Vector2 }
		local out = {}
		for k = 1, n do
			local t = (k - 0.5) / n
			out[k] = Vector2.new(-w / 2 + w * t, ((k + salt) % 2 == 0) and -d * 0.22 or d * 0.22)
		end
		return out
	end
	for _, p in spots(o.smoke or 1, 0) do
		cylY(parent, cf * CFrame.new(p.X + M(0.4), -0.05, p.Y), 0.14, 0.42, white, MAT.SmoothPlastic, "SmokeDetector")
		glowPart(parent, cf * CFrame.new(p.X + M(0.4) + 0.12, -0.13, p.Y), Vector3.new(0.04, 0.04, 0.04), rgb(255, 40, 30), "DetectorLed")
	end
	for _, p in spots(o.diffusers or 0, 1) do
		D(parent, cf * CFrame.new(p.X, -0.03, p.Y), Vector3.new(M(0.6), 0.1, M(0.6)), white, MAT.SmoothPlastic, "Diffuser")
		D(parent, cf * CFrame.new(p.X, -0.07, p.Y), Vector3.new(M(0.42), 0.06, M(0.42)), white:Lerp(rgb(0, 0, 0), 0.08), MAT.SmoothPlastic, "DiffuserRing")
		D(parent, cf * CFrame.new(p.X, -0.1, p.Y), Vector3.new(M(0.24), 0.06, M(0.24)), white:Lerp(rgb(0, 0, 0), 0.16), MAT.SmoothPlastic, "DiffuserCore")
	end
	for _, p in spots(o.speakers or 0, 0) do
		cylY(parent, cf * CFrame.new(p.X - M(0.5), -0.03, -p.Y), 0.1, M(0.2), white, MAT.SmoothPlastic, "CeilingSpeaker")
		cylY(parent, cf * CFrame.new(p.X - M(0.5), -0.07, -p.Y), 0.04, M(0.15), white:Lerp(rgb(0, 0, 0), 0.25), MAT.DiamondPlate, "SpeakerGrille")
	end
	if o.access then
		D(parent, cf * CFrame.new(w * 0.3, -0.02, -d * 0.3), Vector3.new(M(0.45), 0.08, M(0.45)), white:Lerp(rgb(0, 0, 0), 0.04), MAT.SmoothPlastic, "AccessPanel")
	end
	if o.grid then
		local step = M(0.6)
		local nx, nz = math.floor(w / step), math.floor(d / step)
		local tb = rgb(226, 226, 222)
		for i = 1, nx - 1 do
			D(parent, cf * CFrame.new(-w / 2 + i * w / nx, -0.03, 0), Vector3.new(0.08, 0.1, d), tb, MAT.Metal, "TBar")
		end
		for j = 1, nz - 1 do
			D(parent, cf * CFrame.new(0, -0.035, -d / 2 + j * d / nz), Vector3.new(w, 0.11, 0.08), tb, MAT.Metal, "TBar")
		end
	end
end

-- 피난구유도등(벽/천장 매달기): cf = 설치 면 위 중심, 로컬 -Z = 보이는 면. 40 × 13 cm 녹색 발광 + 흰 글자.
function Props.exitSign(parent: Instance, cf: CFrame, arrow: string?, hang: boolean?)
	local w, h, t = M(0.4), M(0.14), M(0.05)
	if hang then
		for _, sx in { -w * 0.35, w * 0.35 } do
			D(parent, cf * CFrame.new(sx, h / 2 + 0.6, 0), Vector3.new(0.05, 1.2, 0.05), rgb(200, 200, 204), MAT.Metal, "SignHanger")
		end
	end
	D(parent, cf * CFrame.new(0, 0, -t / 2), Vector3.new(w + 0.12, h + 0.12, t), rgb(236, 236, 232), MAT.SmoothPlastic, "ExitHousing")
	local face = glowPart(parent, cf * CFrame.new(0, 0, -t - 0.03), Vector3.new(w, h, 0.06), rgb(40, 190, 90), "ExitSign")
	Kit.label(face, FRONT, (if arrow == "left" then "← " else "") .. "비상구 EXIT" .. (if arrow == "right" then " →" else ""), { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 60, maxDistance = 220 })
	if hang then
		Kit.label(face, Enum.NormalId.Back, (if arrow == "right" then "← " else "") .. "비상구 EXIT" .. (if arrow == "left" then " →" else ""), { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 60, maxDistance = 220 })
	end
end

-- 분말 소화기 3.3 kg(높이 ≈ 0.5 m): cf = 바닥 위 기준, 받침대 + 표지판(벽, 높이 1.5 m)
function Props.extinguisher(parent: Instance, cf: CFrame, withSign: boolean?)
	local red = rgb(196, 30, 30)
	D(parent, cf * CFrame.new(0, 0.12, 0), Vector3.new(M(0.26), 0.24, M(0.22)), rgb(200, 30, 30), MAT.Metal, "ExtStand")
	cylY(parent, cf * CFrame.new(0, 0.24 + M(0.21), 0), M(0.42), M(0.13), red, MAT.Metal, "Extinguisher", true)
	Kit.ellipsoid(parent, cf * CFrame.new(0, 0.24 + M(0.42), 0), Vector3.new(M(0.13), M(0.06), M(0.13)), red, MAT.Metal, { name = "ExtDome", query = false, shadow = false })
	D(parent, cf * CFrame.new(0, 0.24 + M(0.47), 0), Vector3.new(M(0.03), M(0.07), M(0.03)), rgb(40, 40, 42), MAT.Metal, "ExtValve")
	D(parent, cf * CFrame.new(M(0.03), 0.24 + M(0.5), -M(0.02)), Vector3.new(M(0.1), M(0.02), M(0.03)), rgb(30, 30, 30), MAT.Metal, "ExtHandle")
	D(parent, cf * CFrame.new(-M(0.075), 0.24 + M(0.28), -M(0.02)), Vector3.new(M(0.025), M(0.32), M(0.025)), rgb(30, 30, 30), MAT.Rubber, "ExtHose")
	D(parent, cf * CFrame.new(0, 0.24 + M(0.24), -M(0.066)), Vector3.new(M(0.1), M(0.12), 0.06), rgb(240, 236, 200), MAT.SmoothPlastic, "ExtLabel")
	if withSign then
		local s = Kit.part(parent, cf * CFrame.new(0, M(1.5), M(0.11)), Vector3.new(M(0.22), M(0.3), 0.08), { name = "ExtSign", material = MAT.SmoothPlastic, color = red, collide = false, query = false, shadow = false })
		Kit.label(s, FRONT, "소화기", { color = rgb(255, 255, 255), glow = false, pixelsPerStud = 60, maxDistance = 120 })
	end
end

-- 옥내소화전함(0.75 × 1.3 m, 바닥에서 0.3 m 띄움): cf = 벽면 위 바닥 기준, 로컬 -Z = 복도 쪽
function Props.hydrant(parent: Instance, cf: CFrame)
	local w, h, t = M(0.75), M(1.3), M(0.18)
	local y0 = M(0.3)
	D(parent, cf * CFrame.new(0, y0 + h / 2, -t / 2 + 0.05), Vector3.new(w, h, t + 0.1), rgb(186, 188, 192), MAT.Metal, "HydrantBox", 0.15)
	local door = D(parent, cf * CFrame.new(0, y0 + h / 2, -t - 0.05), Vector3.new(w - 0.3, h - 0.3, 0.1), rgb(206, 40, 36), MAT.Metal, "HydrantDoor", 0.1)
	Kit.label(door, FRONT, "소화전\nFIRE HOSE", { color = rgb(255, 255, 255), glow = false, pixelsPerStud = 40, maxDistance = 120 })
	D(parent, cf * CFrame.new(w * 0.36, y0 + h / 2, -t - 0.14), Vector3.new(0.12, 0.6, 0.12), rgb(40, 40, 42), MAT.Metal, "HydrantLatch")
	local lamp = glowPart(parent, cf * CFrame.new(0, y0 + h + M(0.12), -M(0.06)), Vector3.new(M(0.12), M(0.12), M(0.12)), rgb(255, 40, 30), "HydrantLamp", "Ball")
	lamp.Name = "HydrantLamp"
end

function Props.cctv(parent: Instance, cf: CFrame)
	cylY(parent, cf * CFrame.new(0, -0.06, 0), 0.16, M(0.14), rgb(236, 236, 232), MAT.SmoothPlastic, "CctvBase")
	Kit.ellipsoid(parent, cf * CFrame.new(0, -0.14, 0), Vector3.new(M(0.11), M(0.08), M(0.11)), rgb(30, 32, 36), MAT.Glass, { name = "CctvDome", query = false, shadow = false, reflectance = 0.3 })
end

-- 벽 플레이트: cf = 벽면 위 중심, 로컬 -Z = 방 쪽
function Props.outlet(parent: Instance, cf: CFrame, kind: string?)
	local k = kind or "outlet"
	D(parent, cf * CFrame.new(0, 0, -0.02), Vector3.new(M(0.07), M(0.12), 0.08), rgb(244, 244, 240), MAT.SmoothPlastic, "WallPlate")
	if k == "outlet" then
		for _, y in { -M(0.028), M(0.028) } do
			cylY(parent, cf * CFrame.new(0, y, -0.065) * CFrame.Angles(math.rad(90), 0, 0), 0.02, M(0.036), rgb(226, 226, 222), MAT.SmoothPlastic, "Socket")
		end
	elseif k == "switch" then
		D(parent, cf * CFrame.new(0, 0, -0.07), Vector3.new(M(0.045), M(0.08), 0.03), rgb(236, 236, 232), MAT.SmoothPlastic, "Rocker")
	else
		glowPart(parent, cf * CFrame.new(0, M(0.03), -0.07), Vector3.new(M(0.03), M(0.01), 0.02), rgb(80, 220, 120), "CardLed")
	end
end

-- 분리수거함(스테인리스, 0.9 × 0.4 × 0.9 m): cf = 바닥 위 중심, 로컬 -Z = 투입구 면
function Props.bin(parent: Instance, cf: CFrame, kinds: { string }?)
	local ks = kinds or { "일반", "재활용", "캔·병" }
	local n = #ks
	local w, d, h = M(0.3) * n, M(0.4), M(0.9)
	S(parent, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), rgb(178, 180, 184), MAT.Metal, "Bin", 0.2)
	D(parent, cf * CFrame.new(0, h + 0.06, 0), Vector3.new(w + 0.12, 0.12, d + 0.12), rgb(60, 62, 66), MAT.Metal, "BinLid")
	local cols = { rgb(80, 82, 86), rgb(40, 120, 70), rgb(40, 90, 170), rgb(220, 160, 40) }
	for i, k in ks do
		local x = -w / 2 + (i - 0.5) * w / n
		D(parent, cf * CFrame.new(x, h - M(0.16), -d / 2 - 0.02), Vector3.new(M(0.18), M(0.08), 0.1), rgb(20, 20, 22), MAT.SmoothPlastic, "BinSlot")
		local tag = D(parent, cf * CFrame.new(x, h - M(0.34), -d / 2 - 0.03), Vector3.new(M(0.22), M(0.1), 0.08), cols[(i - 1) % #cols + 1], MAT.SmoothPlastic, "BinTag")
		Kit.label(tag, FRONT, k, { color = rgb(255, 255, 255), glow = false, pixelsPerStud = 50, maxDistance = 80 })
	end
end

-- 안내 토템(0.6 × 2.0 m): 제목 + 여러 줄, 양면
function Props.signTotem(parent: Instance, cf: CFrame, title: string, lines: string, accent: Color3?)
	local w, h, t = M(0.6), M(2.0), M(0.12)
	local ac = accent or rgb(196, 40, 44)
	S(parent, cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, t), rgb(40, 42, 46), MAT.Metal, "Totem", 0.1)
	D(parent, cf * CFrame.new(0, 0.1, 0), Vector3.new(w + 0.2, 0.2, t + 0.2), rgb(30, 30, 32), MAT.Metal, "TotemFoot")
	for _, face in { FRONT, Enum.NormalId.Back } do
		local z = if face == FRONT then -t / 2 - 0.03 else t / 2 + 0.03
		local hd = Kit.part(parent, cf * CFrame.new(0, h - M(0.18), z), Vector3.new(w - 0.2, M(0.22), 0.06), { name = "TotemHead", material = MAT.SmoothPlastic, color = ac, collide = false, query = false, shadow = false })
		Kit.label(hd, face, title, { color = rgb(255, 255, 255), glow = true, pixelsPerStud = 40, maxDistance = 200 })
		local bd = glowPart(parent, cf * CFrame.new(0, h * 0.48, z), Vector3.new(w - 0.3, h * 0.62, 0.06), rgb(236, 236, 230), "TotemPanel")
		Kit.label(bd, face, lines, { color = rgb(30, 30, 34), glow = true, pixelsPerStud = 40, maxDistance = 120, font = Enum.Font.Gotham })
	end
end

return Props
