--!strict
-- GwangalliBuildingInterior/Hosp_Restroom: 1F 후면 홀 서쪽 끝의 진짜 남/여 화장실 (설계 §7.2).
--   여자 화장실 (서쪽): 넓은 칸 + 일반 칸 + 청소도구함, 세면대 2, 핸드드라이어, 종이타월, 기저귀 교환대
--   남자 화장실 (동쪽): 넓은 칸, 소변기 2 (칸막이 · 자동 물 내림), 세면대 2, 핸드드라이어, 종이타월, 기저귀 교환대
--   입구 문: 다가가면 안쪽으로 열리고 도어클로저로 닫힘. 칸 문: 안에서 잠그면 "사용중" (빨강), 풀면 "비어있음" (초록).
--   상호작용: 물 내리기 · 손 씻기 · 손 말리기 · 잠그기/잠금 해제 · 비상벨 · 기저귀 교환대 펼치기/접기.
--   동작 감지 조명: 안에 들어가면 켜지고, 나간 뒤 20 초 지나면 꺼짐.
-- 좌표: 병원 프레임 HF (y 0 = 1F 바닥). 바닥 오버레이(T_clinic 0.002..0.025) 위 y 0.03 부터 짓습니다.

local TweenService = game:GetService("TweenService")

local Lib = require(script.Parent:WaitForChild("Hosp_Lib"))
local Look = require(script.Parent:WaitForChild("Look"))
local Interact = require(script.Parent:WaitForChild("Interact"))

local R = {}

local CF, V3, ANG = CFrame.new, Vector3.new, CFrame.Angles
local PI = math.pi
local M = Enum.Material
local C3 = Color3.fromRGB
local rad = math.rad

local Geo = Lib.Geo
local C = Geo.C
local SND = Geo.SND

-- 마감재
local LK = {
	plaster = Look.of(222, 218, 208, M.Plaster),
	ceiling = Look.of(240, 240, 236, M.SmoothPlastic),
	floorTile = Look.of(200, 196, 188, M.CeramicTiles),
	floorDark = Look.of(168, 164, 158, M.CeramicTiles),
	tileBase = Look.of(150, 152, 154, M.CeramicTiles),
	tileField = Look.of(240, 240, 236, M.CeramicTiles),
	accentW = Look.of(214, 166, 166, M.CeramicTiles),
	accentM = Look.of(126, 156, 186, M.CeramicTiles),
	hpl = Look.of(220, 214, 206, M.SmoothPlastic),
	hplDoor = Look.of(204, 200, 194, M.SmoothPlastic),
	porcelain = Look.of(246, 246, 243, M.SmoothPlastic, { r = 0.04 }),
	porcelainIn = Look.of(226, 230, 232, M.SmoothPlastic, { r = 0.04 }),
	water = Look.of(150, 190, 210, M.Glass, { t = 0.2 }),
	marble = Look.of(238, 236, 230, M.Marble),
	apron = Look.of(214, 204, 190, M.SmoothPlastic),
	basinIn = Look.of(210, 216, 220, M.SmoothPlastic, { r = 0.05 }),
	chrome = Look.chrome,
	steel = Look.steel,
	brushed = Look.brushed,
	alu = Look.alu,
	white = Look.white,
	frost = Look.of(230, 236, 238, M.Glass, { t = 0.3 }),
	led = Look.neon(C3(255, 240, 220)),
	ledOff = Look.of(200, 200, 196, M.SmoothPlastic),
	pink = Look.of(236, 214, 214, M.SmoothPlastic),
	grey = Look.of(150, 154, 158, M.SmoothPlastic),
	base = Look.of(90, 94, 98, M.SmoothPlastic),
	stream = Look.of(180, 220, 240, M.Glass, { t = 0.45 }),
}

local function solidLook(l: any): any
	local t = table.clone(l)
	t.collide = true
	t.shadow = true
	t.free = true
	return t
end

-- 상태 ---------------------------------------------------------------------------------------------------

local function newRoom(K: any, env: any, id: string, box: { number }): any
	return { id = id, box = box, lights = {}, glow = {}, lastIn = -1e9, on = false }
end

-- 벽 타일 (한 면): axis "x" (벽이 x = plane 에 서 있음, 법선 ±x) | "z". u0..u1 = 벽을 따라, holes = { { a, b, top } }
local function tileFace(K: any, axis: string, plane: number, n: number, u0: number, u1: number, holes: { { number } }, accent: any)
	local low = K.detail == "low"
	local bands = if low then { { 0.10, 9.20, LK.tileField, 0.04 } } else {
		{ 0.10, 0.90, LK.tileBase, 0.04 },
		{ 0.90, 9.20, LK.tileField, 0.04 },
		{ 3.30, 3.55, accent, 0.06 },
	}
	-- 구간 나누기
	table.sort(holes, function(a, b)
		return a[1] < b[1]
	end)
	local spans = {}
	local cur = u0
	for _, h in holes do
		if h[1] > cur then
			table.insert(spans, { cur, h[1], 0 })
		end
		table.insert(spans, { h[1], h[2], h[3] }) -- 문 위
		cur = h[2]
	end
	if u1 > cur then
		table.insert(spans, { cur, u1, 0 })
	end
	K:free(function()
		for _, sp in spans do
			for bi, b in bands do
				local y0, y1 = b[1], b[2]
				if sp[3] > 0 then
					y0 = math.max(y0, sp[3])
				end
				if y1 - y0 > 0.02 then
					local d = b[4]
					local p0, p1 = plane, plane + n * d
					if axis == "z" then
						Lib.ab(K, "WallTile" .. bi, sp[1], y0, p0, sp[2], y1, p1, b[3])
					else
						Lib.ab(K, "WallTile" .. bi, p0, y0, sp[1], p1, y1, sp[2], b[3])
					end
				end
			end
		end
	end)
end

-- 변기 (뒤 = +z 벽, 앞 = -z). cx = 중심 x. 반환: 레버 파트, 물 파트
local function toilet(K: any, cx: number): (BasePart, BasePart)
	local low = K.detail == "low"
	local pl = solidLook(LK.porcelain)
	Lib.ab(K, "ToiletBase", cx - 0.5, 0.10, 37.15, cx + 0.5, 1.20, 38.35, pl)
	local bowl = K:ell("ToiletBowl", V3(1.40, 0.85, 2.00), CF(cx, 1.15, 36.95), pl)
	Lib.solid(bowl, true)
	local water = K:ell("ToiletWater", V3(0.80, 0.06, 1.20), CF(cx, 1.585, 36.85), LK.water)
	if low then
		K:ell("ToiletSeat", V3(1.45, 0.08, 2.05), CF(cx, 1.60, 36.95), LK.porcelain)
	else
		-- 타원 링 좌판 (가운데 물이 보이게)
		local n = if K.detail == "mid" then 10 else 14
		local a, b = 0.62, 0.92
		for i = 0, n - 1 do
			local t0, t1 = i / n * 2 * PI, (i + 1) / n * 2 * PI
			local p0 = V3(cx + math.cos(t0) * a, 1.61, 36.95 + math.sin(t0) * b)
			local p1 = V3(cx + math.cos(t1) * a, 1.61, 36.95 + math.sin(t1) * b)
			K:seg("ToiletSeat", p0, p1, 0.13, LK.porcelain, 0.06)
		end
		-- 좌판 경첩 · 들어 올린 뚜껑
		for _, sx in { -0.35, 0.35 } do
			K:cyl("SeatHinge", 0.2, 0.12, CF(cx + sx, 1.66, 37.92), LK.chrome)
		end
		K:box("ToiletLid", V3(1.35, 1.90, 0.10), CF(cx, 2.55, 38.12) * ANG(rad(-8), 0, 0), LK.porcelain)
	end
	-- 플러시 밸브 (벽 매입 배관 + 레버)
	K:vcyl("FlushPipe", 1.75, 0.16, CF(cx - 0.12, 2.36, 38.50), LK.chrome)
	K:cyl("FlushValve", 0.6, 0.34, CF(cx, 3.40, 38.50), LK.chrome)
	if not low then
		K:cyl("FlushStop", 0.3, 0.14, CF(cx - 0.12, 3.40, 38.62) * ANG(0, PI / 2, 0), LK.chrome)
		K:cyl("FlushBend", 0.4, 0.16, CF(cx - 0.12, 1.50, 38.30) * ANG(0, PI / 2, 0), LK.chrome)
	end
	local lever = K:bar("FlushLever", V3(cx + 0.34, 3.40, 38.42), V3(cx + 0.36, 3.33, 37.92), 0.08, 0.08, LK.chrome) :: BasePart
	return lever, water
end

-- 물 내리기 연출: 물 타원이 두 바퀴 돌며 색이 바뀌고 줄었다가 돌아옴
local function flushFx(water: BasePart, at: BasePart)
	Lib.sfx(at, SND.flush, { vol = 0.55, speed = 0.9 })
	Lib.sfx(at, SND.water, { vol = 0.6, speed = 0.8, dur = 2.2 })
	if not water.Parent then
		return
	end
	local base = water.CFrame
	local size = water.Size
	local col = water.Color
	task.spawn(function()
		local t0 = os.clock()
		while water.Parent do
			local k = (os.clock() - t0) / 1.6
			if k >= 1 then
				break
			end
			local s = 1 - 0.2 * math.sin(k * PI)
			water.CFrame = base * ANG(0, k * 4 * PI, 0)
			water.Size = V3(size.X * s, size.Y, size.Z * s)
			water.Color = col:Lerp(C3(180, 215, 235), math.sin(k * PI))
			task.wait()
		end
		if water.Parent then
			water.CFrame = base
			water.Size = size
			water.Color = col
		end
	end)
end

-- 세면대 한 자리 (앞벽 z 27.34 쪽, 사용자는 -z 를 봄). 반환: 수전 토출구 파트
local function basin(K: any, x: number): BasePart
	K:ell("BasinRim", V3(1.50, 0.06, 1.05), CF(x, 3.02, 28.45), LK.porcelain)
	K:ell("BasinBowl", V3(1.20, 0.07, 0.80), CF(x, 3.035, 28.47), LK.basinIn)
	K:disc("BasinDrain", 0.16, 0.02, CF(x, 3.075, 28.50), LK.chrome)
	K:vcyl("FaucetNeck", 0.85, 0.18, CF(x, 3.425, 27.70), LK.chrome)
	local spout = K:cyl("FaucetSpout", 0.55, 0.13, CF(x, 3.82, 27.95) * ANG(0, PI / 2, 0), LK.chrome)
	if K.detail ~= "low" then
		K:disc("FaucetSensor", 0.08, 0.02, CF(x, 3.62, 27.80) * ANG(PI / 2, 0, 0), Look.ledRed)
		K:disc("FaucetBase", 0.30, 0.04, CF(x, 3.02, 27.70), LK.chrome)
	end
	return spout
end

-- 손 씻기: 물줄기 + 물방울 + 물소리 3 초
local function washFx(K: any, spout: BasePart, x: number)
	if not spout.Parent then
		return
	end
	local stream = Lib.temp(K, "WaterStream", V3(0.79, 0.08, 0.08), CF(x, 3.42, 28.20) * ANG(0, 0, PI / 2), LK.stream, Enum.PartType.Cylinder)
	Lib.particles(spout, "water", 3)
	local s = Lib.sfx(spout, SND.water, { vol = 0.25, speed = 1.4, loop = true, dur = 3.0 })
	task.delay(3.0, function()
		if stream.Parent then
			stream:Destroy()
		end
		if s and s.Parent then
			s:Destroy()
		end
	end)
end

-- 핸드드라이어 (벽 dcf). 반환: 몸체, LED
local function dryer(K: any, dcf: CFrame): (BasePart, BasePart)
	local body = K:plate("DryerBody", 1.2, 2.0, 0.85, dcf, LK.white)
	K:plate("DryerFace", 1.0, 1.1, 0.02, dcf * CF(0, 0.3, 0.85), LK.steel)
	local led = K:plate("DryerLED", 0.5, 0.05, 0.02, dcf * CF(0, 0.75, 0.86), Look.ledBlue)
	K:plate("DryerSlot", 0.9, 0.12, 0.03, dcf * CF(0, -0.92, 0.80), Look.black)
	Lib.tx(K, "DryerLabel", 0.9, 0.18, dcf * CF(0, -0.45, 0.86), "손을 넣으면 작동해요", C3(70, 74, 80), nil, { font = Lib.FONT_M })
	return body, led
end

-- 종이타월 디스펜서 + 휴지통
local function towel(K: any, dcf: CFrame, binAt: Vector3)
	K:plate("TowelBox", 1.0, 1.4, 0.45, dcf, LK.white)
	K:plate("TowelWindow", 0.5, 0.25, 0.02, dcf * CF(0, 0.2, 0.45), Look.with(Look.glassDark, { t = 0.3 }))
	K:plate("TowelSlot", 0.7, 0.06, 0.02, dcf * CF(0, -0.62, 0.45), Look.black)
	K:plate("TowelSheet", 0.6, 0.3, 0.01, dcf * CF(0, -0.82, 0.42), Look.paper)
	local bin = K:vcyl("TowelBin", 1.8, 0.9, CF(binAt.X, 1.0, binAt.Z), LK.steel)
	Lib.solid(bin, true)
	K:disc("TowelBinLid", 0.92, 0.06, CF(binAt.X, 1.93, binAt.Z), LK.brushed)
end

-- 안전 손잡이 (두 점 + 벽 쪽 받침)
local function grab(K: any, a: Vector3, b: Vector3, wallN: Vector3)
	K:seg("GrabBar", a, b, 0.13, LK.chrome)
	for _, p in { a, b } do
		K:seg("GrabFlange", p, p - wallN * 0.12, 0.2, LK.chrome)
	end
end

-- 칸 문 ---------------------------------------------------------------------------------------------

-- spec = { x0, x1 (닫힌 문짝 x), z0, z1 (문짝 두께), hinge = x, sign (경첩 회전 부호), maxDeg, rest (0..1),
--          box = { x0, x1, z0, z1 } (칸 안), front = { x0, x1, z0, z1 } (문 앞 감지), wheel = bool, knobX }
local function stall(K: any, spec: any): any
	local outZ = spec.z0 -- 문짝 바깥면 (홀 쪽 -z)
	local inZ = spec.z1
	local w = spec.x1 - spec.x0
	local indicator: TextLabel? = nil
	local knob: BasePart? = nil
	local leafPart: BasePart? = nil
	local g = K:group("StallDoor_" .. spec.id, function()
		leafPart = Lib.ab(K, "StallLeaf", spec.x0, 0.50, spec.z0, spec.x1, 6.80, spec.z1, LK.hplDoor)
		-- 바깥: 사용 표시창
		local latchX = if spec.hinge > (spec.x0 + spec.x1) / 2 then spec.x0 + 0.42 else spec.x1 - 0.42
		K:plate("LockWindowRim", 0.62, 0.30, 0.02, Lib.face(latchX, 3.6, outZ, 0, -1), LK.chrome)
		local _, t = Lib.tx(K, "LockIndicator", 0.56, 0.24, Lib.face(latchX, 3.6, outZ - 0.02, 0, -1), "비어있음", C.WHITE, C3(40, 170, 90), { font = Lib.FONT_K })
		indicator = t
		-- 안쪽: 잠금 손잡이 · 옷걸이 · 안내
		knob = K:box("LockKnob", V3(0.28, 0.14, 0.10), CF(spec.knobX, 3.6, inZ + 0.05), LK.chrome)
		K:cyl("LockBase", 0.04, 0.3, CF(spec.knobX, 3.6, inZ + 0.01) * ANG(0, PI / 2, 0), LK.chrome)
		K:seg("CoatHook", V3((spec.x0 + spec.x1) / 2, 5.6, inZ), V3((spec.x0 + spec.x1) / 2, 5.75, inZ + 0.3), 0.07, LK.chrome)
		if K.detail ~= "low" then
			Lib.tx(K, "StallNote", 1.4, 0.32, Lib.face((spec.x0 + spec.x1) / 2, 4.6, inZ + 0.005, 0, 1), "화장지는 변기에 버려 주세요", C.TEAL_D, C.WHITE, { font = Lib.FONT_M })
		end
		-- 바깥 손잡이 (작은 당김 손잡이)
		K:seg("PullHandle", V3(latchX, 3.1, outZ - 0.02), V3(latchX, 3.1, outZ - 0.14), 0.08, LK.chrome)
	end)
	local hingeW = Geo.W(spec.hinge, 0, (spec.z0 + spec.z1) / 2)
	local st: any = { spec = spec, locked = false, indicator = indicator, knob = knob, prompt = nil :: ProximityPrompt? }
	st.mover = Lib.Swinger(K, Lib.partsOf(g), hingeW, Geo.HF.YVector, rad(spec.maxDeg) * spec.sign, {
		tOpen = 0.55,
		tClose = 0.9,
		closer = true,
		collide = { leafPart },
		onLatch = function()
			Lib.sfx(knob, SND.click, { vol = 0.35, speed = 0.6 })
		end,
	})
	local function setLocked(v: boolean)
		st.locked = v
		if indicator then
			indicator.Text = if v then "사용중" else "비어있음"
			indicator.BackgroundColor3 = if v then C3(206, 40, 40) else C3(40, 170, 90)
		end
		if st.prompt then
			st.prompt.ActionText = if v then "잠금 해제" else "잠그기"
		end
		if v then
			st.mover:set(0)
		end
	end
	st.setLocked = setLocked
	if knob then
		st.prompt = Interact.prompt(K, knob, {
			action = "잠그기",
			object = if spec.wheel then "넓은 칸" else "화장실 칸",
			sound = SND.click,
			fn = function()
				local me = Lib.me()
				local b = spec.box
				if not me or not (me.X > b[1] and me.X < b[2] and me.Z > b[3] and me.Z < b[4]) then
					return
				end
				setLocked(not st.locked)
			end,
		})
		if st.prompt then
			st.prompt.Enabled = false
		end
	end
	st.mover:set(spec.rest or 0, true) -- 프롬프트 간격은 닫힌 자리 기준
	-- 10 Hz: 안에 있으면 프롬프트, 잠기지 않았으면 다가갈 때 열림
	Interact.anim(K, function()
		local me = Lib.me()
		local b = spec.box
		local inside = me ~= nil and me.X > b[1] and me.X < b[2] and me.Z > b[3] and me.Z < b[4] and me.Y > -1 and me.Y < 8
		if st.prompt then
			st.prompt.Enabled = inside
		end
		if st.locked then
			if not inside then
				setLocked(false) -- 순간 이동 · 리스폰으로 나갔으면 자동 해제
			end
			return
		end
		local f = spec.front
		local near = false
		for _, a in Lib.actors() do
			if a.kind ~= "npc" and a.l.Y > -1 and a.l.Y < 8 then
				if (a.l.X > f[1] and a.l.X < f[2] and a.l.Z > f[3] and a.l.Z < f[4]) or (a.l.X > b[1] and a.l.X < b[2] and a.l.Z > b[3] and a.l.Z < b[4]) then
					near = true
				end
			end
		end
		if near then
			st.mover:set(1)
		else
			st.mover:set(spec.rest or 0)
		end
	end)
	return st
end

-- 입구 문 (안쪽 여닫이, 도어클로저) --------------------------------------------------------------------

local function entranceDoor(K: any, id: string, x0: number, x1: number, hingeX: number, sign: number, women: boolean)
	local leaf: BasePart? = nil
	local g = K:group("EntranceDoor_" .. id, function()
		leaf = Lib.ab(K, "DoorLeaf", x0, 0.10, 27.075, x1, 7.40, 27.225, LK.hplDoor)
		local cx = (x0 + x1) / 2
		local hall = Lib.face(cx, 4.2, 27.075, 0, -1)
		K:plate("PushPlate", 0.5, 1.6, 0.02, Lib.face(if hingeX > cx then x0 + 0.45 else x1 - 0.45, 4.2, 27.075, 0, -1), LK.steel)
		K:plate("KickPlate", x1 - x0 - 0.04, 0.7, 0.02, Lib.face(cx, 0.48, 27.075, 0, -1), LK.steel)
		local label = if women then "🚺 여자 화장실 · WOMEN" else "🚹 남자 화장실 · MEN"
		K:plate("DoorPlateBack", 2.0, 1.0, 0.03, hall * CF(0, 1.7, 0), LK.white)
		Lib.tx(K, "DoorPlate", 1.84, 0.84, hall * CF(0, 1.7, 0.035), label, if women then C.RED else C.NAVY, nil, { font = Lib.FONT_K })
		-- 안쪽: D 손잡이 + 도어클로저 암
		local inX = if hingeX > cx then x0 + 0.45 else x1 - 0.45
		K:seg("DHandle", V3(inX, 3.4, 27.30), V3(inX, 4.6, 27.30), 0.09, LK.chrome)
		for _, y in { 3.4, 4.6 } do
			K:seg("DHandleLeg", V3(inX, y, 27.225), V3(inX, y, 27.30), 0.07, LK.chrome)
		end
		if K.detail ~= "low" then
			K:box("CloserBody", V3(1.2, 0.25, 0.22), CF(hingeX + (if hingeX > cx then -0.85 else 0.85), 7.1, 27.34), LK.brushed)
			Lib.tx(K, "NoSmoke", 0.9, 0.9, Lib.face(cx, 5.3, 27.225, 0, 1), "🚭 금연", C.RED, C.WHITE, { font = Lib.FONT_K })
		end
	end)
	local hingeW = Geo.W(hingeX, 0, 27.30)
	local mv = Lib.Swinger(K, Lib.partsOf(g), hingeW, Geo.HF.YVector, rad(92) * sign, {
		tOpen = 0.6,
		tClose = 1.0,
		closer = true,
		onLatch = function()
			Lib.sfx(leaf, SND.click, { vol = 0.3, speed = 0.6 })
		end,
	})
	local lastNear = -1e9
	local cx = (x0 + x1) / 2
	Interact.anim(K, function(t)
		local near = false
		for _, a in Lib.actors() do
			if a.kind ~= "npc" and math.abs(a.l.X - cx) < 1.8 and a.l.Z > 24.5 and a.l.Z < 30.0 and a.l.Y > -1 and a.l.Y < 8 then
				near = true
			end
		end
		if near then
			lastNear = t
			mv:set(1)
		elseif t - lastNear > 1.2 then
			mv:set(0)
		end
	end)
	return mv
end

-- 기저귀 교환대 (칸막이 벽에 접이식). wallX = 벽면 x, n = 법선 x 부호 (보는 쪽)
local function babyStation(K: any, wallX: number, n: number, z0: number, z1: number)
	local zc = (z0 + z1) / 2
	local bx = wallX + n * 0.45
	-- 몸체 (벽에 붙은 함)
	Lib.ab(K, "BabyBody", wallX, 2.20, z0, bx, 4.60, z1, LK.white)
	Lib.ab(K, "BabyBand", bx, 4.25, z0, bx + n * 0.01, 4.45, z1, Look.of(0, 128, 118))
	local deck: BasePart? = nil
	local g = K:group("BabyDeck", function()
		-- 접힌 판 (경첩 = 아래쪽, x = bx, y 2.9)
		deck = Lib.ab(K, "BabyDeckPanel", bx, 2.90, z0 + 0.05, bx + n * 0.10, 4.50, z1 - 0.05, LK.white)
		Lib.ab(K, "BabyDeckRim", bx + n * 0.10, 4.36, z0 + 0.05, bx + n * 0.16, 4.50, z1 - 0.05, Look.of(0, 128, 118))
		Lib.tx(K, "BabyLabel", 1.7, 0.42, Lib.face(bx + n * 0.105, 3.95, zc, n, 0), "🚼 기저귀 교환대 · 최대 15kg", C.TEAL_D, nil, { font = Lib.FONT_B })
		K:box("BabyStrap", V3(0.04, 0.12, 1.2), CF(bx + n * 0.11, 3.35, zc), Look.of(40, 120, 110, M.Fabric))
	end)
	local hinge = Geo.W(bx, 2.90, zc)
	local mv = Lib.Swinger(K, Lib.partsOf(g), hinge, Geo.HF.ZVector, rad(90) * -n, { tOpen = 0.6, tClose = 0.6, easeOpen = "quadOut", easeClose = "quadInOut" })
	local open = false
	if deck then
		-- 남/여 교환대는 칸막이 벽 양쪽 (서로 안 보임): 간격 검사 생략
		Lib.promptAny(K, deck, {
			action = "기저귀 교환대 펼치기",
			object = "기저귀 교환대",
			sound = SND.click,
			fn = function(_n, pr)
				open = not open
				mv:set(if open then 1 else 0)
				pr.ActionText = if open then "기저귀 교환대 접기" else "기저귀 교환대 펼치기"
			end,
		})
	end
end

-- 비상벨 (벽 dcf). 반환: 버튼 파트
local function bell(K: any, dcf: CFrame): BasePart
	K:plate("BellPlate", 0.6, 0.6, 0.05, dcf, LK.white)
	local b = K:disc("BellButton", 0.32, 0.08, dcf * CF(0, 0.02, 0.07) * ANG(PI / 2, 0, 0), Look.of(214, 30, 30, M.SmoothPlastic))
	Lib.tx(K, "BellLabel", 0.56, 0.12, dcf * CF(0, -0.22, 0.055), "비상벨", C.RED, nil, { font = Lib.FONT_K })
	if K.detail ~= "low" then
		Lib.tx(K, "BellNote", 1.0, 0.16, dcf * CF(0, 0.42, 0.01), "위급할 때 누르세요", C.GREY_T, nil, { font = Lib.FONT_M })
	end
	return b
end

-- 천장 (판 · 다운라이트 · 배기 그릴 · 감지기 · 스프링클러). 반환: 빛 파트 목록
local function ceilingKit(K: any, x0: number, x1: number, lights: { { number } }, grille: { number }, sensor: { number }): { BasePart }
	Lib.wall(K, "Ceiling", x0, 9.20, 27.30, x1, 9.35, 38.78, LK.ceiling)
	local glow = {}
	K:free(function()
		for _, l in lights do
			K:disc("DownTrim", 0.9, 0.04, CF(l[1], 9.18, l[2]), LK.white)
			local lens = K:disc("DownLens", 0.7, 0.03, CF(l[1], 9.165, l[2]), LK.ledOff)
			table.insert(glow, lens)
		end
		K:box("ExhaustGrille", V3(0.9, 0.04, 0.9), CF(grille[1], 9.18, grille[2]), LK.white)
		if K.detail ~= "low" then
			for i = -3, 3 do
				K:box("GrilleSlat", V3(0.8, 0.02, 0.04), CF(grille[1], 9.155, grille[2] + i * 0.11), Look.of(190, 192, 194))
			end
			K:ell("MotionSensor", V3(0.35, 0.18, 0.35), CF(sensor[1], 9.18, sensor[2]), LK.white)
			K:disc("SmokeDetector", 0.55, 0.12, CF((x0 + x1) / 2, 9.14, 34.5), LK.white)
			K:disc("Sprinkler", 0.28, 0.12, CF((x0 + x1) / 2 + 2, 9.14, 32.0), Look.brass)
		end
	end)
	return glow
end

-- 동작 감지 조명: 안에 있으면 켬, 나간 뒤 20 초면 끔
local function motionLights(K: any, room: any)
	local light: Light? = nil
	if room.glow[1] then
		light = K:light(room.glow[1], "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 14, Brightness = 0, Angle = 150, Color = Look.neutralLight, Enabled = false })
	end
	local b = room.box
	Interact.anim(K, function(t)
		local me = Lib.me()
		local inside = me ~= nil and me.X > b[1] and me.X < b[2] and me.Z > b[3] and me.Z < b[4] and me.Y > -1 and me.Y < 9
		if inside then
			room.lastIn = t
		end
		local want = inside or (t - room.lastIn) < 20
		if want ~= room.on then
			room.on = want
			for _, g in room.glow do
				if g.Parent then
					g.Material = if want then M.Neon else M.SmoothPlastic
					g.Color = if want then C3(255, 240, 220) else C3(200, 200, 196)
				end
			end
			if light then
				if want then
					light.Enabled = true
					TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 1.1 }):Play()
				else
					local tw = TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0 })
					tw:Play()
					task.delay(0.65, function()
						if light and not room.on then
							light.Enabled = false
						end
					end)
				end
			end
		end
	end)
end

-- 짓기 -----------------------------------------------------------------------------------------------

function R.build(K: any, env: any)
	local UI = env.UI
	local low = K.detail == "low"
	-- 1) 맵 가짜 문 숨김 (모두 충돌 없음)
	local function backZone(): Instance?
		return Lib.child(Lib.hospital(), { "1F", "BackZone" })
	end
	for _, n in { "Door_남자 화장실", "Door_여자 화장실" } do
		Lib.hideModel(K, function()
			local bz = backZone()
			return bz and bz:FindFirstChild(n)
		end)
	end

	-- 다른 실내 빌더의 keep 무시 장식(매단 표지 등)이 화장실 안에 들어오면 이 클라이언트에서 숨김
	Lib.ghostForeign(K, env.ctx and env.ctx.root, env.folder, { { -59.25, 0.12, 27.32, -35.95, 9.18, 38.76 } })

	-- 2) 벽 · 천장 · 바닥
	local P = solidLook(LK.plaster)
	Lib.wall(K, "FrontWall_W", -59.29, 0, 27.00, -51.40, 10.85, 27.30, P)
	Lib.wall(K, "FrontLintel_W", -51.40, 7.45, 27.00, -48.40, 10.85, 27.30, P)
	Lib.wall(K, "FrontPier", -48.40, 0, 27.00, -47.10, 10.85, 27.30, P)
	Lib.wall(K, "FrontLintel_M", -47.10, 7.45, 27.00, -44.10, 10.85, 27.30, P)
	Lib.wall(K, "FrontWall_M", -44.10, 0, 27.00, -35.90, 10.85, 27.30, P)
	Lib.wall(K, "Divider", -47.90, 0, 27.30, -47.60, 10.85, 38.78, P)
	Lib.wall(K, "EastWall", -36.20, 0, 27.30, -35.90, 10.85, 38.78, P)
	Lib.wall(K, "Floor_W", -59.29, 0.03, 27.30, -47.90, 0.10, 38.78, LK.floorTile)
	Lib.wall(K, "Floor_M", -47.60, 0.03, 27.30, -36.20, 0.10, 38.78, LK.floorTile)
	Lib.wall(K, "Threshold_W", -51.40, 0.03, 27.00, -48.40, 0.10, 27.30, LK.brushed)
	Lib.wall(K, "Threshold_M", -47.10, 0.03, 27.00, -44.10, 0.10, 27.30, LK.brushed)
	K:free(function()
		K:box("FloorDrain", V3(0.6, 0.01, 0.6), CF(-53.5, 0.105, 31.0), LK.steel)
		K:box("FloorDrain", V3(0.6, 0.01, 0.6), CF(-40.5, 0.105, 31.0), LK.steel)
		-- 홀 쪽 걸레받이 (문 피함)
		for _, s in { { -59.29, -51.55 }, { -48.25, -47.25 }, { -43.95, -35.90 } } do
			Lib.ab(K, "HallBase", s[1], 0, 26.96, s[2], 0.5, 27.00, LK.base)
		end
		Lib.ab(K, "HallBaseE", -35.90, 0, 27.00, -35.86, 0.5, 33.30, LK.base)
		-- 모서리 보호대
		Lib.ab(K, "CornerGuard", -36.00, 0, 26.92, -35.82, 5.0, 27.10, LK.steel)
	end)
	-- 문틀 (알루미늄)
	for _, d in { { -51.55, -51.40, -48.40, -48.25 }, { -47.25, -47.10, -44.10, -43.95 } } do
		K:free(function()
			Lib.ab(K, "DoorJamb", d[1], 0, 26.95, d[2], 7.55, 27.35, LK.alu)
			Lib.ab(K, "DoorJamb", d[3], 0, 26.95, d[4], 7.55, 27.35, LK.alu)
			Lib.ab(K, "DoorHead", d[1], 7.40, 26.95, d[4], 7.55, 27.35, LK.alu)
		end)
	end
	-- 벽 타일
	tileFace(K, "x", -59.29, 1, 27.30, 38.78, {}, LK.accentW)
	tileFace(K, "z", 38.78, -1, -59.25, -47.90, {}, LK.accentW)
	tileFace(K, "x", -47.90, -1, 27.30, 38.74, {}, LK.accentW)
	tileFace(K, "z", 27.30, 1, -59.25, -47.94, { { -51.40, -48.40, 7.45 } }, LK.accentW)
	tileFace(K, "x", -47.60, 1, 27.30, 38.74, {}, LK.accentM)
	tileFace(K, "z", 38.78, -1, -47.56, -36.20, {}, LK.accentM)
	tileFace(K, "x", -36.20, -1, 27.30, 38.74, {}, LK.accentM)
	tileFace(K, "z", 27.30, 1, -47.56, -36.24, { { -47.10, -44.10, 7.45 } }, LK.accentM)

	-- 3) 천장 + 동작 감지 조명
	local roomW = newRoom(K, env, "W", { -59.29, -47.90, 27.30, 38.78 })
	local roomM = newRoom(K, env, "M", { -47.60, -36.20, 27.30, 38.78 })
	roomW.glow = ceilingKit(K, -59.29, -47.90, { { -56.0, 30.8 }, { -51.5, 30.8 }, { -57.4, 36.0 }, { -51.8, 36.2 } }, { -55.5, 36.0 }, { -50.0, 28.6 })
	roomM.glow = ceilingKit(K, -47.60, -36.20, { { -44.5, 30.8 }, { -39.0, 30.8 }, { -45.0, 36.0 } }, { -38.6, 37.5 }, { -45.6, 28.6 })
	motionLights(K, roomW)
	motionLights(K, roomM)

	-- 4) 입구 문
	entranceDoor(K, "W", -51.35, -48.45, -48.45, 1, true)
	entranceDoor(K, "M", -47.05, -44.15, -47.05, -1, false)

	-- 5) 여자 화장실 ---------------------------------------------------------------------------------
	Lib.wall(K, "StallFront", -59.25, 0.45, 33.00, -58.30, 6.85, 33.12, LK.hpl)
	Lib.wall(K, "StallFront", -54.90, 0.45, 33.00, -53.90, 6.85, 33.12, LK.hpl)
	Lib.wall(K, "StallPartition", -53.96, 0.45, 33.12, -53.84, 6.85, 38.74, LK.hpl)
	Lib.wall(K, "StallFront", -53.84, 0.45, 33.00, -53.30, 6.85, 33.12, LK.hpl)
	Lib.wall(K, "StallFront", -50.50, 0.45, 33.00, -49.70, 6.85, 33.12, LK.hpl)
	Lib.wall(K, "StallPartition", -49.76, 0.45, 33.12, -49.64, 6.85, 38.74, LK.hpl)
	K:free(function()
		Lib.ab(K, "HeadRail", -59.25, 6.85, 33.00, -49.64, 6.97, 33.12, LK.alu)
		for _, x in { -53.90, -49.70 } do
			Lib.ab(K, "StallFoot", x - 0.1, 0.10, 32.95, x + 0.1, 0.45, 33.17, LK.steel)
		end
		for _, z in { 34.5, 37.8 } do
			Lib.ab(K, "StallFoot", -54.0, 0.10, z - 0.1, -53.8, 0.45, z + 0.1, LK.steel)
			Lib.ab(K, "StallFoot", -49.8, 0.10, z - 0.1, -49.6, 0.45, z + 0.1, LK.steel)
		end
	end)
	stall(K, {
		id = "W1",
		x0 = -58.275,
		x1 = -54.925,
		z0 = 33.00,
		z1 = 33.12,
		hinge = -54.925,
		sign = -1,
		maxDeg = 88,
		rest = 0,
		wheel = true,
		knobX = -57.9,
		box = { -59.25, -53.96, 33.12, 38.74 },
		front = { -58.3, -54.9, 30.6, 33.0 },
	})
	stall(K, {
		id = "W2",
		x0 = -53.275,
		x1 = -50.525,
		z0 = 33.00,
		z1 = 33.12,
		hinge = -50.525,
		sign = 1,
		maxDeg = 95,
		rest = 20 / 95,
		wheel = false,
		knobX = -52.9,
		box = { -53.84, -49.76, 33.12, 38.74 },
		front = { -53.3, -50.5, 30.8, 33.0 },
	})
	local flushers = {}
	local lw1, ww1 = toilet(K, -57.60)
	table.insert(flushers, { lever = lw1, water = ww1 })
	local lw2, ww2 = toilet(K, -51.75)
	table.insert(flushers, { lever = lw2, water = ww2 })
	-- 넓은 칸 손잡이 + 휴지걸이 + 비상벨 + 위생용품 수거함
	grab(K, V3(-59.15, 2.65, 34.6), V3(-59.15, 2.65, 37.6), V3(-1, 0, 0))
	grab(K, V3(-59.15, 2.65, 34.6), V3(-59.15, 5.2, 34.6), V3(-1, 0, 0))
	if not low then
		K:seg("FoldBar", V3(-55.95, 2.65, 38.6), V3(-55.95, 2.65, 36.2), 0.13, LK.chrome)
		K:box("FoldBarPivot", V3(0.3, 0.5, 0.14), CF(-55.95, 2.65, 38.67), LK.chrome)
	end
	local function paper(dcf: CFrame)
		K:plate("PaperHolder", 1.0, 1.0, 0.4, dcf, LK.steel)
		K:plate("PaperRoll", 0.7, 0.18, 0.02, dcf * CF(0, -0.42, 0.3), Look.paper)
	end
	paper(Lib.face(-59.25, 2.4, 35.9, 1, 0))
	paper(Lib.face(-49.76, 2.4, 36.1, -1, 0))
	local bells = {}
	table.insert(bells, bell(K, Lib.face(-59.25, 3.7, 35.9, 1, 0)))
	table.insert(bells, bell(K, Lib.face(-53.84, 3.7, 35.9, 1, 0)))
	for _, x in { -55.35, -50.40 } do
		Lib.ab(K, "SanitaryBin", x - 0.35, 0.10, 37.9, x + 0.35, 1.2, 38.5, LK.pink)
		K:box("SanitaryLid", V3(0.72, 0.06, 0.62), CF(x, 1.23, 38.2), LK.pink)
	end
	-- 청소도구함
	Lib.wall(K, "JanitorFront", -49.64, 0, 33.00, -47.94, 9.20, 33.12, LK.hpl)
	K:free(function()
		Lib.ab(K, "JanitorDoor", -49.40, 0.1, 32.97, -48.10, 6.8, 33.00, LK.grey)
		Lib.tx(K, "JanitorLabel", 1.1, 0.3, Lib.face(-48.75, 6.0, 32.965, 0, -1), "청소도구함", C.WHITE, C3(110, 114, 118), { font = Lib.FONT_B })
		if not low then
			for i = 0, 4 do
				Lib.ab(K, "JanitorLouver", -49.2, 0.6 + i * 0.22, 32.95, -48.3, 0.68 + i * 0.22, 32.97, Look.of(120, 124, 128))
			end
		end
	end)
	-- 세면대 (W)
	local VAN = solidLook(LK.marble)
	Lib.wall(K, "VanityTop", -58.90, 2.85, 27.34, -52.00, 3.00, 29.29, VAN)
	Lib.wall(K, "VanityApron", -58.90, 2.15, 29.19, -52.00, 2.85, 29.29, LK.apron)
	local faucets = {}
	for _, x in { -56.95, -53.95 } do
		table.insert(faucets, { spout = basin(K, x), x = x })
	end
	K:vcyl("SoapPump", 0.6, 0.30, CF(-55.45, 3.30, 27.70), LK.white)
	K:box("SoapHead", V3(0.12, 0.12, 0.35), CF(-55.45, 3.66, 27.82), LK.chrome)
	K:plate("Mirror", 6.8, 3.8, 0.06, Lib.face(-55.45, 5.50, 27.34, 0, 1), Look.mirror)
	if not low then
		K:plate("MirrorEdge", 6.86, 0.04, 0.07, Lib.face(-55.45, 7.42, 27.34, 0, 1), LK.chrome)
		K:plate("MirrorEdge", 6.86, 0.04, 0.07, Lib.face(-55.45, 3.58, 27.34, 0, 1), LK.chrome)
		Lib.tx(K, "SaveWater", 1.6, 0.25, Lib.face(-52.85, 3.85, 27.41, 0, 1), "물을 아껴 씁시다", C.TEAL_D, nil, { font = Lib.FONT_M })
	end
	K:plate("MirrorLED", 6.3, 0.08, 0.05, Lib.face(-55.45, 7.59, 27.34, 0, 1), LK.led)
	local dryW, ledW = dryer(K, Lib.face(-59.25, 4.30, 30.20, 1, 0))
	towel(K, Lib.face(-59.25, 4.70, 31.70, 1, 0), V3(-58.6, 0, 31.7))
	babyStation(K, -47.90, -1, 30.60, 32.60)

	-- 6) 남자 화장실 ---------------------------------------------------------------------------------
	Lib.wall(K, "StallFront", -47.56, 0.45, 32.60, -46.60, 6.85, 32.72, LK.hpl)
	Lib.wall(K, "StallFront", -43.20, 0.45, 32.60, -42.00, 6.85, 32.72, LK.hpl)
	Lib.wall(K, "StallPartition", -42.06, 0.45, 32.72, -41.94, 6.85, 38.74, LK.hpl)
	K:free(function()
		Lib.ab(K, "HeadRail", -47.56, 6.85, 32.60, -41.94, 6.97, 32.72, LK.alu)
		Lib.ab(K, "StallFoot", -42.1, 0.10, 32.55, -41.9, 0.45, 32.77, LK.steel)
		for _, z in { 34.5, 37.8 } do
			Lib.ab(K, "StallFoot", -42.1, 0.10, z - 0.1, -41.9, 0.45, z + 0.1, LK.steel)
		end
	end)
	stall(K, {
		id = "M1",
		x0 = -46.575,
		x1 = -43.225,
		z0 = 32.60,
		z1 = 32.72,
		hinge = -46.575,
		sign = 1,
		maxDeg = 85,
		rest = 0,
		wheel = true,
		knobX = -43.6,
		box = { -47.56, -42.06, 32.72, 38.74 },
		front = { -46.6, -43.2, 30.2, 32.6 },
	})
	local lm1, wm1 = toilet(K, -45.90)
	table.insert(flushers, { lever = lm1, water = wm1 })
	grab(K, V3(-47.46, 2.65, 34.6), V3(-47.46, 2.65, 37.6), V3(-1, 0, 0))
	grab(K, V3(-47.46, 2.65, 34.6), V3(-47.46, 5.2, 34.6), V3(-1, 0, 0))
	if not low then
		K:seg("FoldBar", V3(-44.25, 2.65, 38.6), V3(-44.25, 2.65, 36.2), 0.13, LK.chrome)
		K:box("FoldBarPivot", V3(0.3, 0.5, 0.14), CF(-44.25, 2.65, 38.67), LK.chrome)
	end
	paper(Lib.face(-47.56, 2.4, 35.9, 1, 0))
	table.insert(bells, bell(K, Lib.face(-42.06, 3.7, 35.9, -1, 0)))
	-- 소변기 2 + 칸막이 + 자동 감지
	Lib.ab(K, "UrinalFloor", -41.94, 0.10, 37.2, -36.24, 0.11, 38.74, LK.floorDark)
	local urinals = {}
	for i, x in { -39.90, -37.30 } do
		Lib.ab(K, "UrinalPlate", x - 0.625, 1.45, 38.62, x + 0.625, 4.05, 38.74, LK.porcelain)
		local body = K:ell("UrinalBody", V3(1.25, 2.30, 1.15), CF(x, 2.65, 38.20), LK.porcelain)
		Lib.solid(body, true)
		K:ell("UrinalLip", V3(1.10, 0.60, 0.70), CF(x, 1.85, 37.75), LK.porcelain)
		K:ell("UrinalInner", V3(0.85, 1.70, 0.20), CF(x, 2.70, 37.68), LK.porcelainIn)
		K:disc("UrinalDrain", 0.22, 0.02, CF(x, 1.92, 37.78) * ANG(rad(70), 0, 0), LK.chrome)
		local sensor = K:box("UrinalSensor", V3(0.50, 0.60, 0.35), CF(x, 4.35, 38.56), LK.white)
		K:disc("UrinalEye", 0.12, 0.02, CF(x, 4.30, 38.38) * ANG(PI / 2, 0, 0), Look.ledRed)
		K:vcyl("UrinalPipe", 0.4, 0.12, CF(x, 4.85, 38.62), LK.chrome)
		if not low then
			local msg = if i == 1 then "남자가 흘리지 말아야 할 것은\n눈물만이 아닙니다" else "한 걸음 더 가까이 ♥"
			Lib.tx(K, "UrinalSticker", 1.5, 0.7, Lib.face(x, 6.0, 38.74, 0, -1), msg, C.NAVY, C.WHITE, { font = Lib.FONT_M, wrap = true })
		end
		table.insert(urinals, { x = x, sensor = sensor, water = nil, stand = -1, used = false })
	end
	for _, x in { -41.20, -38.60 } do
		K:free(function()
			Lib.ab(K, "UrinalDivider", x - 0.05, 1.60, 37.00, x + 0.05, 5.40, 38.74, LK.frost)
			Lib.ab(K, "UrinalDividerEdge", x - 0.06, 1.60, 36.95, x + 0.06, 5.40, 37.02, LK.chrome)
		end)
	end
	if not low then
		Lib.tx(K, "AutoFlushNote", 2.4, 0.3, Lib.face(-38.6, 7.0, 38.74, 0, -1), "소변기는 자동으로 물이 내려갑니다", C.GREY_T, nil, { font = Lib.FONT_M })
	end
	-- 세면대 (M)
	Lib.wall(K, "VanityTop", -43.70, 2.85, 27.34, -36.60, 3.00, 29.29, VAN)
	Lib.wall(K, "VanityApron", -43.70, 2.15, 29.19, -36.60, 2.85, 29.29, LK.apron)
	for _, x in { -41.90, -38.60 } do
		table.insert(faucets, { spout = basin(K, x), x = x })
	end
	K:vcyl("SoapPump", 0.6, 0.30, CF(-40.25, 3.30, 27.70), LK.white)
	K:box("SoapHead", V3(0.12, 0.12, 0.35), CF(-40.25, 3.66, 27.82), LK.chrome)
	K:plate("Mirror", 7.0, 3.8, 0.06, Lib.face(-40.15, 5.50, 27.34, 0, 1), Look.mirror)
	if not low then
		K:plate("MirrorEdge", 7.06, 0.04, 0.07, Lib.face(-40.15, 7.42, 27.34, 0, 1), LK.chrome)
		K:plate("MirrorEdge", 7.06, 0.04, 0.07, Lib.face(-40.15, 3.58, 27.34, 0, 1), LK.chrome)
		Lib.tx(K, "NoSmokeM", 0.9, 0.9, Lib.face(-36.24, 6.2, 34.6, -1, 0), "🚭 금연", C.RED, C.WHITE, { font = Lib.FONT_K })
	end
	K:plate("MirrorLED", 6.5, 0.08, 0.05, Lib.face(-40.15, 7.59, 27.34, 0, 1), LK.led)
	local dryM, ledM = dryer(K, Lib.face(-36.24, 4.30, 30.60, -1, 0))
	towel(K, Lib.face(-36.24, 4.70, 32.10, -1, 0), V3(-36.8, 0, 32.1))
	babyStation(K, -47.60, 1, 30.50, 32.40)

	-- 7) 홀 쪽 안내 · 안전
	local col = Lib.face(-47.75, 6.40, 27.00, 0, -1)
	K:plate("SignColumn", 1.2, 4.4, 0.06, col, Look.acrylicWhite)
	Lib.tx(K, "SignColumnTop", 1.14, 0.5, col * CF(0, 1.9, 0.065), "화장실 · Restroom", C.WHITE, C.TEAL, { font = Lib.FONT_B })
	-- 홀에서 북쪽을 보면 서쪽(여자)이 오른쪽, 동쪽(남자)이 왼쪽
	Lib.tx(K, "SignColumnW", 1.0, 0.8, col * CF(0, 0.9, 0.065), "🚺 여 →", C.RED, nil, { font = Lib.FONT_K })
	Lib.tx(K, "SignColumnM", 1.0, 0.8, col * CF(0, -0.1, 0.065), "← 남 🚹", C.NAVY, nil, { font = Lib.FONT_K })
	Lib.tx(K, "SignColumnWheel", 1.0, 0.6, col * CF(0, -1.1, 0.065), "넓은 칸", C.NAVY, nil, { font = Lib.FONT_B })
	-- 돌출 간판 (양면, 동쪽에서 보임)
	K:free(function()
		Lib.ab(K, "BladeSign", -37.26, 7.40, 25.30, -37.14, 8.60, 26.90, LK.white)
		Lib.ab(K, "BladeBracket", -37.24, 8.0, 26.90, -37.16, 8.1, 27.00, LK.alu)
		for _, sx in { 1, -1 } do
			Lib.tx(K, "BladeText", 1.5, 1.1, Lib.face(-37.20 + sx * 0.065, 8.0, 26.1, sx, 0), "🚺 화장실 🚹", C.NAVY, nil, { font = Lib.FONT_K })
		end
	end)
	Lib.exitSign(K, Lib.face(-37.8, 1.2, 27.00, 0, -1), 1.2, "← 🏃", "path") -- 비상구는 동쪽 (북쪽을 보면 왼쪽)
	-- 소화기함
	K:plate("ExtBox", 1.0, 2.1, 0.35, Lib.face(-35.90, 1.15, 29.0, 1, 0), Look.of(196, 30, 34))
	K:vcyl("ExtBottle", 1.5, 0.5, CF(-35.30, 1.0, 29.0), Look.of(214, 36, 36))
	Lib.tx(K, "ExtLabel", 0.9, 0.3, Lib.face(-35.90, 2.6, 29.0, 1, 0), "소화기", C.WHITE, C.RED, { font = Lib.FONT_K })
	-- 홀 쪽 벽 보호판(T_clinic 복도와 같은 아이보리 + 청록 띠) + 안전 손잡이 (문 · 안내 기둥 피함)
	K:free(function()
		for _, s in { { -59.29, -51.55 }, { -43.95, -35.90 } } do
			local len = s[2] - s[1]
			local u = (s[1] + s[2]) / 2
			K:plate("HallGuardPanel", len, 2.55, 0.04, Lib.face(u, 0.5 + 2.55 / 2, 27.00, 0, -1), Look.of(232, 230, 224, M.SmoothPlastic))
			K:plate("HallGuardCap", len, 0.12, 0.09, Lib.face(u, 3.05, 27.00, 0, -1), Look.of(0, 128, 118))
			if not low then
				local a, b = s[1] + 0.35, s[2] - 0.35
				K:seg("HallRail", V3(a, 2.75, 26.62), V3(b, 2.75, 26.62), 0.17, Look.of(236, 234, 228, M.SmoothPlastic))
				local n = math.max(2, math.floor((b - a) / 3.2) + 1)
				for i = 0, n - 1 do
					local x = a + 0.15 + (b - a - 0.3) * i / (n - 1)
					K:seg("HallRailBracket", V3(x, 2.75, 26.62), V3(x, 2.75, 26.96), 0.08, Look.brushed)
				end
			end
		end
	end)
	-- 비상 경광등 (입구 위 홀 쪽, 비상벨 누르면 깜빡임)
	local strobes = {}
	for _, x in { -49.9, -45.6 } do
		table.insert(strobes, K:box("EmergencyStrobe", V3(0.6, 0.3, 0.2), CF(x, 8.05, 26.90), Look.of(120, 30, 30)))
	end

	-- 8) 상호작용 -------------------------------------------------------------------------------------
	local busy: { [any]: number } = {}
	local function cool(key: any, s: number): boolean
		local now = os.clock()
		if busy[key] and now - busy[key] < s then
			return false
		end
		busy[key] = now
		return true
	end
	for _, f in flushers do
		Interact.prompt(K, f.lever, {
			action = "물 내리기",
			object = "변기",
			sound = SND.click,
			fn = function()
				if cool(f, 3) then
					flushFx(f.water, f.lever)
				end
			end,
		})
	end
	for _, f in faucets do
		Interact.prompt(K, f.spout, {
			action = "손 씻기",
			object = "세면대",
			sound = false,
			fn = function()
				if cool(f, 3.2) then
					washFx(K, f.spout, f.x)
				end
			end,
		})
	end
	for _, dpair in { { dryW, ledW }, { dryM, ledM } } do
		local body, led = dpair[1], dpair[2]
		Interact.prompt(K, body, {
			action = "손 말리기",
			object = "핸드드라이어",
			sound = false,
			fn = function()
				if not cool(body, 3.2) then
					return
				end
				if led.Parent then
					led.Color = C3(60, 230, 120)
				end
				local slot = body
				Lib.particles(slot, "air", 3)
				Lib.sfx(body, SND.wind, { vol = 0.3, speed = 1.6, loop = true, dur = 3 })
				task.delay(3, function()
					if led.Parent then
						led.Color = C3(70, 150, 255)
					end
				end)
			end,
		})
	end
	local strobeUntil = 0
	for _, b in bells do
		Interact.prompt(K, b, {
			action = "비상벨 누르기",
			object = "비상벨",
			sound = SND.click,
			fn = function()
				if not cool("bell", 4) then
					return
				end
				Lib.beeps(b, SND.chime, 6, 0.25, { vol = 0.6, speed = 1.6 })
				strobeUntil = os.clock() + 10
				UI.toast("비상벨이 울렸어요. 간호사실에 호출이 전달됐어요", 3)
			end,
		})
	end
	Interact.anim(K, function(t)
		local on = os.clock() < strobeUntil and math.floor(t * 4) % 2 == 0
		for _, s in strobes do
			if s.Parent then
				s.Material = if on then M.Neon else M.SmoothPlastic
				s.Color = if on then C3(255, 40, 30) else C3(120, 30, 30)
			end
		end
	end)
	-- 소변기: 앞에 2 초 이상 서 있다가 떠나면 자동 물 내림 + 프롬프트
	for _, u in urinals do
		Interact.prompt(K, u.sensor, {
			action = "물 내리기",
			object = "소변기",
			sound = SND.click,
			fn = function()
				if cool(u, 3) then
					Lib.sfx(u.sensor, SND.flush, { vol = 0.45, speed = 1.1 })
					Lib.sfx(u.sensor, SND.water, { vol = 0.5, speed = 0.9, dur = 1.8 })
				end
			end,
		})
		Interact.anim(K, function(t)
			local me = Lib.me()
			local standing = me ~= nil and math.abs(me.X - u.x) < 0.9 and me.Z > 36.0 and me.Z < 38.2 and me.Y > -1 and me.Y < 8
			if standing then
				if u.stand < 0 then
					u.stand = t
				end
			else
				if u.stand >= 0 and t - u.stand >= 2 and cool(u, 3) then
					Lib.sfx(u.sensor, SND.flush, { vol = 0.45, speed = 1.1 })
					Lib.sfx(u.sensor, SND.water, { vol = 0.5, speed = 0.9, dur = 1.8 })
				end
				u.stand = -1
			end
		end)
	end
end

-- 맵 1F 후면 홀이 스트리밍 됐을 때만
function R.ready(_env: any): boolean
	return Lib.child(Lib.hospital(), { "1F", "BackZone" }) ~= nil
end

return R
