--!strict
-- SeoulSkyline / WaterFx
-- 한강 유람선(움직임은 클라이언트 Boats 가 담당) + 먼 쪽 강변 앞 수면의 은은한 빛 반짝임.
--
--   * 유람선 3척: 실측 55 m / 50 m / 42 m, 폭 9~11 m, 흘수 1.3 m, 건현 1.5 m, 2층 선실(층고 2.7 / 2.5 m),
--     창 띠 1.4 m(창 2.8 m + 기둥 0.5 m), 유리 난간 1.1 m, 마스트 4 m(백색 마스트등), 좌현 빨강 / 우현 초록 현등,
--     선미등, 장식 전구줄(마스트 → 선수/선미), 선실 LED 라인.
--     각 배 = Model "Boat" (태그 SeoulBoat), 피벗 = 수선면 중심, LookVector = 선수 방향.
--     속성 PathA / PathB (Vector3, 수면 위 X 방향 직선 구간), Speed (stud/s, 약 9~10 노트), TurnRadius, Phase(0~1, A→B 구간 위 시작점).
--     모든 파트 Anchored + CanCollide false(클라이언트가 PivotTo 로 움직임 — 서버 사본은 Phase 위치에 정지).
--     경로는 다리 띠(Config.Bridge.X ± 80)와 Kit 예약 영역을 피하고, U턴 반경까지 포함해 수면 안에 머뭅니다.
--   * 수면 반짝임: 먼 쪽 호안 앞(Z = FarBank.WaterEdge + 30 ~ +170)에 짧고 옅은 Kit.reflection 몇 개.
--     다른 모듈의 반사(WaterGlint)와 겹치지 않는 자리만 사용.
--   * 클라이언트용 색 정보(Config.Palette 차량 불빛)를 루트 속성으로 내보냅니다(클라이언트는 ServerStorage 를 못 읽음).
--   예산: 300 파트.

local CollectionService = game:GetService("CollectionService")

local WaterFx = {}

local BUDGET = 300
local BOAT_TAG = "SeoulBoat"

type BoatSpec = {
	length: number, -- m
	beam: number, -- m
	z: number, -- 항로 Z (River.HalfWidth 비율)
	xFar: number, -- A 끝 X (stud)
	xNear: number, -- B 끝 X (stud, 다리 쪽)
	phase: number,
	knots: number,
	hull: Color3,
	accent: Color3,
	led: Color3,
}

function WaterFx.build(ctx: any)
	local Config = ctx.Config
	local Kit = ctx.Kit
	local rng: Random = ctx.rng
	local model: Model = ctx.model
	local root: Model = ctx.root
	local P = Config.Palette
	local m = Config.m
	local MAT = Enum.Material
	local rgb = Color3.fromRGB
	local p0 = Kit.stats.parts

	-- 클라이언트용 팔레트/스케일 (Traffic/Beacons 가 읽음)
	root:SetAttribute("HeadlightColor", P.Headlight)
	root:SetAttribute("TaillightColor", P.Taillight)
	root:SetAttribute("BeaconColor", P.Beacon)
	root:SetAttribute("MetersPerStud", Config.METERS_PER_STUD)

	local function used(): number
		return Kit.stats.parts - p0
	end

	local function deco(name: string, extra: { [string]: any }?): any
		local o: { [string]: any } = { name = name, collide = false, query = false }
		if extra then
			for k, v in extra do
				o[k] = v
			end
		end
		return o
	end

	local function glowOpts(name: string, dayColor: Color3?, extra: { [string]: any }?): any
		local o = deco(name, { shadow = false, glow = true, dayMaterial = MAT.Glass, dayColor = dayColor or P.GlassDeep })
		if extra then
			for k, v in extra do
				o[k] = v
			end
		end
		return o
	end

	--------------------------------------------------------------------------------------------------
	-- 유람선
	--------------------------------------------------------------------------------------------------
	local HW = Config.River.HalfWidth
	local BX = Config.Bridge.X
	local BRIDGE_CLEAR = 80 -- 다리 띠 반폭(stud)
	local TURN_R = m(30) -- U턴 반경 30 m

	local WINDOW_COLORS = { P.WindowWarm, P.WindowWarm, P.WindowWarm, P.WindowGold, P.WindowWarmDim, P.WindowWarm }

	-- 선체 + 2층 선실. cf0: 수선면 중심, LookVector = 선수.
	local function buildBoat(parent: Model, cf0: CFrame, s: BoatSpec)
		local L, B = m(s.length), m(s.beam)
		local bowLen = m(s.beam * 0.95)
		local yB, yT = -m(1.3), m(1.5) -- 선저 / 주갑판
		local hh = yT - yB
		local zBowRoot = -L / 2 + bowLen
		local function at(x: number, y: number, z: number): CFrame
			return cf0 * CFrame.new(x, y, z)
		end

		-- 선체 본체(선미 쪽 사각) + 뾰족한 선수(웨지 2)
		Kit.box(parent, at(0, (yB + yT) / 2, (zBowRoot + L / 2) / 2), Vector3.new(B, hh, L / 2 - zBowRoot), s.hull, MAT.SmoothPlastic, deco("Hull", { shadow = false }))
		local bowRotS = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1))
		local bowRotP = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1))
		Kit.wedge(parent, at(B / 4, (yB + yT) / 2, zBowRoot - bowLen / 2) * bowRotS, Vector3.new(hh, B / 2, bowLen), s.hull, MAT.SmoothPlastic, deco("Bow"))
		Kit.wedge(parent, at(-B / 4, (yB + yT) / 2, zBowRoot - bowLen / 2) * bowRotP, Vector3.new(hh, B / 2, bowLen), s.hull, MAT.SmoothPlastic, deco("Bow"))

		-- 선체 색 띠(현측 + 선수 사면), 선체 면에서 0.4 stud 돌출
		local bandY, bandH = m(0.55), m(0.45)
		local mainLen = L / 2 - zBowRoot - m(0.6)
		for _, sx in { -1, 1 } do
			Kit.box(parent, at(sx * (B / 2 + 0.1), bandY, (zBowRoot + L / 2) / 2 + m(0.3)), Vector3.new(0.6, bandH, mainLen), s.accent, MAT.SmoothPlastic, deco("HullBand"))
			-- 선수 사면: (sx*B/2, zBowRoot) → (0, -L/2)
			local a = Vector3.new(sx * B / 2, 0, zBowRoot)
			local b = Vector3.new(0, 0, -L / 2)
			local mid = (a + b) / 2
			local along = (b - a).Unit
			local out = Vector3.new(along.Z, 0, -along.X)
			if out.X * sx < 0 then
				out = -out
			end
			local cfBand = CFrame.lookAt(mid, mid + along) + out * 0.1
			Kit.box(parent, cf0 * (cfBand + Vector3.new(0, bandY, 0)), Vector3.new(0.6, bandH, (b - a).Magnitude * 0.9), s.accent, MAT.SmoothPlastic, deco("HullBand"))
		end

		-- 수선부 짙은 띠(boot-top, 수면 -0.1 ~ +0.4 m)
		for _, sx in { -1, 1 } do
			Kit.box(parent, at(sx * (B / 2 + 0.1), m(0.15), (zBowRoot + L / 2) / 2 + m(0.2)), Vector3.new(0.6, m(0.5), mainLen + m(0.2)), rgb(26, 32, 48), MAT.SmoothPlastic, deco("BootTop"))
		end

		-- 주갑판 유리 난간(선체 가장자리, 1.1 m)
		local railH = Config.Real.Railing
		local GLASS_RAIL = rgb(150, 176, 196)
		for _, sx in { -1, 1 } do
			Kit.box(parent, at(sx * (B / 2 - 0.4), yT + railH / 2, (zBowRoot + L / 2) / 2), Vector3.new(0.3, railH, L / 2 - zBowRoot - 0.8), GLASS_RAIL, MAT.Glass, deco("Rail", { transparency = 0.55 }))
		end

		-- 1층 선실
		local w1 = B - m(1.6)
		local h1 = m(2.7)
		local z1a, z1b = zBowRoot + m(1.0), L / 2 - m(4.0)
		local cab1 = Kit.box(parent, at(0, yT + h1 / 2, (z1a + z1b) / 2), Vector3.new(w1, h1, z1b - z1a), rgb(236, 236, 232), MAT.SmoothPlastic, deco("Cabin1", { shadow = false }))
		-- 창 띠: 2.8 m 창 + 0.5 m 기둥, 선실 벽에서 0.3 stud 돌출
		local function windowRow(w: number, y0: number, wh: number, za: number, zb: number)
			local pw, gap = m(2.8), m(0.5)
			local n = math.max(1, math.floor((zb - za + gap) / (pw + gap)))
			local span = n * pw + (n - 1) * gap
			local zs = (za + zb) / 2 - span / 2
			for _, sx in { -1, 1 } do
				for i = 0, n - 1 do
					local c = WINDOW_COLORS[rng:NextInteger(1, #WINDOW_COLORS)]
					Kit.box(parent, at(sx * (w / 2 + 0.05), y0 + wh / 2, zs + pw / 2 + i * (pw + gap)), Vector3.new(0.5, wh, pw), c, MAT.Neon, glowOpts("Window"))
				end
			end
		end
		windowRow(w1, yT + m(0.9), m(1.4), z1a + m(0.8), z1b - m(0.8))
		-- 전면 파노라마 창 / 후면 유리문
		Kit.box(parent, at(0, yT + m(1.6), z1a - 0.05), Vector3.new(w1 - m(1.2), m(1.4), 0.5), P.WindowWarm, MAT.Neon, glowOpts("WindowFront"))
		Kit.box(parent, at(0, yT + m(1.25), z1b + 0.05), Vector3.new(w1 * 0.55, m(2.1), 0.5), P.WindowGold, MAT.Neon, glowOpts("WindowAft"))

		-- 1층 지붕 = 2층 바닥(0.3 m, 0.4 m 차양)
		local slabT = m(0.3)
		local slabW, slabL = w1 + m(0.8), z1b - z1a + m(1.0)
		local y2 = yT + h1 + slabT
		Kit.box(parent, at(0, yT + h1 + slabT / 2, (z1a + z1b) / 2), Vector3.new(slabW, slabT, slabL), rgb(240, 240, 236), MAT.SmoothPlastic, deco("Deck2Slab", { shadow = false }))
		-- 차양 옆면 LED 라인
		for _, sx in { -1, 1 } do
			Kit.box(parent, at(sx * (slabW / 2 + 0.05), yT + h1 + slabT * 0.45, (z1a + z1b) / 2), Vector3.new(0.4, 0.35, slabL - 1), s.led, MAT.Neon, glowOpts("LedLine"))
		end
		-- 2층 유리 난간(옆 2 + 앞 + 뒤)
		for _, sx in { -1, 1 } do
			Kit.box(parent, at(sx * (slabW / 2 - 0.45), y2 + railH / 2, (z1a + z1b) / 2), Vector3.new(0.3, railH, slabL - 1.2), GLASS_RAIL, MAT.Glass, deco("Rail", { transparency = 0.55 }))
		end
		for _, zz in { z1a - m(0.5) + 0.45, z1b + m(0.5) - 0.45 } do
			Kit.box(parent, at(0, y2 + railH / 2, zz), Vector3.new(slabW - 1.6, railH, 0.3), GLASS_RAIL, MAT.Glass, deco("Rail", { transparency = 0.55 }))
		end

		-- 2층 선실(앞쪽 = 조타실), 뒤쪽은 개방 갑판
		local w2 = w1 - m(1.4)
		local h2 = m(2.5)
		local z2a, z2b = z1a + m(4.5), z1b - math.max(m(7), (z1b - z1a) * 0.3)
		Kit.box(parent, at(0, y2 + h2 / 2, (z2a + z2b) / 2), Vector3.new(w2, h2, z2b - z2a), rgb(238, 238, 234), MAT.SmoothPlastic, deco("Cabin2", { shadow = false }))
		windowRow(w2, y2 + m(0.8), m(1.3), z2a + m(4.0), z2b - m(0.6))
		-- 조타실 창(어두운 유리) — 측면 앞부분 + 전면
		for _, sx in { -1, 1 } do
			Kit.box(parent, at(sx * (w2 / 2 + 0.05), y2 + m(1.55), z2a + m(1.8)), Vector3.new(0.5, m(1.0), m(2.8)), rgb(30, 44, 56), MAT.Glass, deco("BridgeWindow"))
		end
		Kit.box(parent, at(0, y2 + m(1.55), z2a - 0.05), Vector3.new(w2 - m(0.8), m(1.0), 0.5), rgb(30, 44, 56), MAT.Glass, deco("BridgeWindow"))
		-- 2층 지붕
		local y3 = y2 + h2
		Kit.box(parent, at(0, y3 + m(0.25) / 2, (z2a + z2b) / 2), Vector3.new(w2 + m(0.6), m(0.25), z2b - z2a + m(0.6)), rgb(244, 244, 240), MAT.SmoothPlastic, deco("Roof", { shadow = false }))

		-- 마스트 + 항해등
		local mastH = m(4.0)
		local mz = z2a + m(2.0)
		local yRoof = y3 + m(0.25)
		Kit.vcyl(parent, (at(0, yRoof + mastH / 2, mz)).Position, mastH, 0.6, rgb(220, 222, 226), MAT.Metal, deco("Mast"))
		local mastTop = at(0, yRoof + mastH + 0.4, mz).Position
		Kit.ball(parent, mastTop, 1.1, P.LampWhite, MAT.Neon, glowOpts("MastheadLight"))
		-- 현등: 좌현(-X) 빨강, 우현(+X) 초록 — 조타실 양옆
		Kit.box(parent, at(-(w2 / 2 + 0.6), y3 - m(0.4), z2a + m(0.6)), Vector3.new(0.6, 0.9, 1.4), rgb(255, 40, 32), MAT.Neon, glowOpts("PortLight"))
		Kit.box(parent, at(w2 / 2 + 0.6, y3 - m(0.4), z2a + m(0.6)), Vector3.new(0.6, 0.9, 1.4), rgb(40, 255, 110), MAT.Neon, glowOpts("StarboardLight"))
		-- 선미등(백색)
		Kit.box(parent, at(0, yT + railH + 0.6, L / 2 - 0.8), Vector3.new(1.0, 0.9, 0.6), P.LampWhite, MAT.Neon, glowOpts("SternLight"))
		-- 장식 전구줄: 마스트 꼭대기 → 선수 끝 / 선미 (원기둥 축 = 로컬 X)
		local bowTip = at(0, yT + railH, -L / 2 + 1.0).Position
		local sternTop = at(0, yT + railH + 1.2, L / 2 - 1.5).Position
		for _, b in { bowTip, sternTop } do
			local mid = (mastTop + b) / 2
			Kit.part(parent, CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0), Vector3.new((b - mastTop).Magnitude, 0.35, 0.35), glowOpts("LightString", nil, { shape = "Cylinder", material = MAT.Neon, color = P.LampWarm }))
		end

		-- 수면에 번진 창 불빛(배와 함께 이동) + 선미 항적
		for _, sx in { -1, 1 } do
			Kit.box(parent, at(sx * (B / 2 + m(2.2)), 0.3, (z1a + z1b) / 2), Vector3.new(m(3.2), 0.12, (z1b - z1a) * 0.9), P.WindowWarmDim, MAT.Neon, glowOpts("BoatGlow", rgb(40, 60, 80), { transparency = 0.84 }))
			local wa = at(sx * B * 0.32, 0.22, L / 2 + m(9))
			Kit.box(parent, wa * CFrame.Angles(0, math.rad(sx * 7), 0), Vector3.new(m(1.6), 0.12, m(18)), rgb(214, 226, 236), MAT.SmoothPlastic, deco("Wake", { transparency = 0.72, shadow = false }))
		end

		-- 선실 실내광(물 위를 비춤) — 광원 예산 안에서만
		Kit.light(cab1, "PointLight", { color = P.WindowWarm, brightness = 1.4, range = 48 })
	end

	local SPECS: { BoatSpec } = {
		-- 가장 큰 배: 먼 쪽 절반, 다리 왼쪽(대표 구도 중앙)
		{ length = 55, beam = 11, z = -0.47, xFar = -2200, xNear = BX - BRIDGE_CLEAR - m(60), phase = 0.66, knots = 9.5, hull = rgb(242, 242, 238), accent = rgb(28, 74, 150), led = P.LedGold },
		-- 다리 오른쪽(동쪽) 구간
		{ length = 50, beam = 10.5, z = 0.33, xFar = 2700, xNear = BX + BRIDGE_CLEAR + m(60), phase = 0.8, knots = 9, hull = rgb(236, 238, 240), accent = rgb(186, 40, 48), led = P.LedCyan },
		-- 작은 배: 가까운 쪽 절반, 왼쪽
		{ length = 42, beam = 9, z = 0.5, xFar = -3000, xNear = -480, phase = 0.82, knots = 10, hull = rgb(244, 242, 236), accent = rgb(24, 120, 128), led = P.LedMagenta },
	}

	local KNOT = 0.5144 -- m/s
	local boats = 0
	for idx, s in SPECS do
		local L = m(s.length)
		local z = s.z * HW
		local zSide = if z < 0 then 1 else -1 -- U턴은 강 중심 쪽으로
		local xA, xB = s.xFar, s.xNear
		local reach = math.max(TURN_R + m(s.beam), L / 2) + m(8)
		-- 다리 띠 / 예약 영역 / 수면 경계를 피하도록 B 끝을 A 쪽으로 당김
		local ok = false
		for _ = 1, 20 do
			local x0, x1 = math.min(xA, xB) - reach, math.max(xA, xB) + reach
			local z0 = math.min(z - m(s.beam), z + zSide * (2 * TURN_R + m(s.beam)))
			local z1 = math.max(z + m(s.beam), z + zSide * (2 * TURN_R + m(s.beam)))
			local clearBridge = x1 < BX - BRIDGE_CLEAR or x0 > BX + BRIDGE_CLEAR
			local inWater = z0 > -HW + m(20) and z1 < HW - m(20) and x0 > Config.River.XMin and x1 < Config.River.XMax
			if clearBridge and inWater and Kit.isFree(x0, z0, x1, z1, m(5)) then
				ok = true
				break
			end
			xB += if xA < xB then -m(30) else m(30)
			if math.abs(xB - xA) < L * 4 then
				break
			end
		end
		if not ok or used() > BUDGET - 80 then
			continue
		end
		local A = Vector3.new(xA, Config.Level.Water, z)
		local Bp = Vector3.new(xB, Config.Level.Water, z)
		local pos = A:Lerp(Bp, s.phase)
		local cf0 = CFrame.lookAt(pos, pos + (Bp - A).Unit)
		local boat = Kit.group(model, "Boat")
		buildBoat(boat, cf0, s)
		boat.WorldPivot = cf0
		boat:SetAttribute("PathA", A)
		boat:SetAttribute("PathB", Bp)
		boat:SetAttribute("Speed", math.floor(m(s.knots * KNOT) * 10 + 0.5) / 10)
		boat:SetAttribute("TurnRadius", TURN_R)
		boat:SetAttribute("Phase", s.phase)
		boat:SetAttribute("Length", L)
		boat:SetAttribute("Index", idx)
		CollectionService:AddTag(boat, BOAT_TAG)
		boats += 1
	end

	--------------------------------------------------------------------------------------------------
	-- 먼 쪽 호안 앞 수면 반짝임 (옅고 짧은 스트릭, 기존 반사와 겹치지 않게)
	--------------------------------------------------------------------------------------------------
	local F = Config.FarBank
	local zNear, zFar = F.WaterEdge + 30, F.WaterEdge + 170
	local existing: { { any } } = {} -- { 위치, 반경 }
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "WaterGlint" and d.Position.Z < zFar + 400 then
			table.insert(existing, { d.Position, (d.Size.X + d.Size.Z) / 2 })
		end
	end
	local cam = Config.Viewpoint.ReflectionEye
	local function clear(x: number, z: number, len: number, w: number): boolean
		local a = Vector3.new(x, 0, z)
		local dir = Vector3.new(cam.X - x, 0, cam.Z - z).Unit
		local b = a + dir * len
		local ab = b - a
		for _, e in existing do
			local q: Vector3 = e[1]
			local qa = Vector3.new(q.X, 0, q.Z) - a
			local t = math.clamp(qa:Dot(ab) / ab:Dot(ab), 0, 1)
			local d = (Vector3.new(q.X, 0, q.Z) - (a + ab * t)).Magnitude
			if d < w + e[2] + 6 then
				return false
			end
		end
		return true
	end
	local GLINT_COLORS = { P.WindowWarm, P.LampSodium, P.WindowCool, P.WindowGold, P.LedBlue }
	local placed = 0
	for _ = 1, 160 do
		if used() > BUDGET - 6 or placed >= 24 then
			break
		end
		local x = rng:NextNumber(-2600, 2600)
		local z = rng:NextNumber(zNear, zFar)
		local len = rng:NextNumber(m(10), m(26))
		local w = rng:NextNumber(m(0.6), m(1.2))
		if math.abs(x - BX) < BRIDGE_CLEAR + m(15) or not clear(x, z, len, w) then
			continue
		end
		local c = GLINT_COLORS[rng:NextInteger(1, #GLINT_COLORS)]:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0.3, 0.5))
		local first = Kit.reflection(model, x, z, w, len, c, rng:NextNumber(0.86, 0.91))
		if first then
			placed += 1
			local dir = Vector3.new(cam.X - x, 0, cam.Z - z).Unit
			for k = 0, 3 do
				table.insert(existing, { Vector3.new(x, 0, z) + dir * (len * k / 3), len / 6 + w })
			end
		end
	end

	model:SetAttribute("Boats", boats)
	model:SetAttribute("Glints", placed)
end

return WaterFx
