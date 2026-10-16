--!strict
-- GwangalliBuildingInterior/Hosp_Exits: 걸어서 드나드는 출입구 (설계 §7.6 · §7.7).
--   * 동쪽 외벽 GroundSide 를 같은 재질 조각으로 바꿔 끼우고 두 곳을 뚫음 (맵 벽은 이 클라이언트에서만 숨김 + 통과):
--       - 응급실 출입구 (처치실 → 구급차 베이): 안 · 밖 2 중 자동문(방풍실), 캐노피, EMERGENCY 라이트박스, 경사로,
--         바닥 유도선, 바깥 호출 버튼
--       - 비상구: 철제 방화문 (패닉바 · 도어클로저), 안에서 밀면 열리고 밖에서는 손잡이로, 바깥 계단참 · 등
--   * 2F 계단홀 남쪽 벽(BackWall2) 에 복도로 나가는 통로 + 열어 둔 방화문 (맵에서는 막혀 있던 곳)
-- 좌표: 병원 프레임 HF. 바깥 포장 윗면 y -0.34.

local Lighting = game:GetService("Lighting")

local Lib = require(script.Parent:WaitForChild("Hosp_Lib"))
local Look = require(script.Parent:WaitForChild("Look"))
local Interact = require(script.Parent:WaitForChild("Interact"))

local X = {}

local CF, V3, ANG = CFrame.new, Vector3.new, CFrame.Angles
local PI = math.pi
local M = Enum.Material
local C3 = Color3.fromRGB
local rad = math.rad

local Geo = Lib.Geo
local C = Geo.C
local SND = Geo.SND

local LK = {
	alu = Look.alu,
	glass = Look.of(200, 224, 230, M.Glass, { t = 0.45, r = 0.15 }),
	redBand = Look.of(220, 60, 60, M.Glass, { t = 0.15 }),
	steel = Look.steel,
	fireDoor = Look.of(140, 144, 148, M.Metal),
	concrete = Look.of(176, 172, 164, M.Concrete),
	canopy = Look.of(240, 240, 238),
	red = Look.of(206, 36, 40),
	yellow = Look.of(240, 200, 40),
	white = Look.white,
	black = Look.black,
	fireIvory = Look.of(214, 210, 198, M.Metal),
	frame = Look.of(120, 124, 128, M.Metal),
}

local function night(): boolean
	local t = Lighting.ClockTime
	return t >= 18 or t < 6
end

-- 응급실 출입구 ------------------------------------------------------------------------------------

local function erEntrance(K: any, env: any)
	local UI = env.UI
	local low = K.detail == "low"
	local z0, z1, zc = 12.00, 17.00, 14.50
	-- 개구부 마감 (자른 면 덮기) + 문턱 + 경사로
	K:free(function()
		Lib.ab(K, "ERReturn", 59.11, 0, z0, 59.91, 8.0, z0 + 0.08, LK.alu)
		Lib.ab(K, "ERReturn", 59.11, 0, z1 - 0.08, 59.91, 8.0, z1, LK.alu)
		Lib.ab(K, "ERReturnHead", 59.11, 7.92, z0, 59.91, 8.0, z1, LK.alu)
	end)
	Lib.wall(K, "ERThreshold", 58.90, 0, z0, 60.20, 0.06, z1, LK.alu)
	local ramp = K:wedge("ERRamp", V3(z1 - z0, 0.34, 2.48), CF(61.36, -0.17, zc) * ANG(0, -PI / 2, 0), { c = C3(170, 168, 162), m = M.Concrete, collide = true, shadow = true, free = true })
	Lib.solid(ramp, true)
	-- 자동문 2 세트 (안: x 58.90..59.05, 밖: x 59.97..60.12)
	local sets = {}
	for si, xs in { { 58.90, 59.05 }, { 59.97, 60.12 } } do
		local movers = {}
		for li, zz in { { z0 + 0.05, zc }, { zc, z1 - 0.05 } } do
			local g = K:group("ERLeaf" .. si .. li, function()
				K:free(function()
					local za, zb = zz[1], zz[2]
					Lib.ab(K, "ERGlass", xs[1] + 0.04, 0.35, za + 0.12, xs[2] - 0.04, 7.75, zb - 0.12, LK.glass)
					Lib.ab(K, "ERLeafTop", xs[1], 7.75, za, xs[2], 7.90, zb, LK.alu)
					Lib.ab(K, "ERLeafBottom", xs[1], 0.05, za, xs[2], 0.35, zb, LK.alu)
					Lib.ab(K, "ERLeafStile", xs[1], 0.05, za, xs[2], 7.90, za + 0.12, LK.alu)
					Lib.ab(K, "ERLeafStile", xs[1], 0.05, zb - 0.12, xs[2], 7.90, zb, LK.alu)
					Lib.ab(K, "ERBand", xs[1] + 0.02, 3.2, za + 0.12, xs[2] - 0.02, 4.2, zb - 0.12, LK.redBand)
					for _, n in { -1, 1 } do
						local fx = (if n < 0 then xs[1] else xs[2]) + n * 0.005
						Lib.tx(K, "ERBandText", zb - za - 0.4, 0.8, Lib.face(fx, 3.7, (za + zb) / 2, n, 0), "응급실 EMERGENCY", C.WHITE, nil, { font = Lib.FONT_K })
						if not low then
							Lib.tx(K, "ERAuto", 0.9, 0.22, Lib.face(fx, 4.6, (za + zb) / 2, n, 0), "자동문", C3(60, 64, 70), nil, { font = Lib.FONT_B })
						end
					end
				end)
			end)
			local dir = if li == 1 then -1 else 1
			local parts = Lib.partsOf(g)
			local mv = Lib.Slider(K, parts, Geo.HF.ZVector * (dir * 2.45), {
				tOpen = 0.6,
				tClose = 1.0,
				easeOpen = "quartOut",
				easeClose = "sineInOut",
				collide = parts,
			})
			table.insert(movers, mv)
		end
		sets[si] = movers
	end
	-- 헤더 (안 · 밖) + 감지기
	K:free(function()
		Lib.solid(Lib.ab(K, "ERHeaderIn", 58.55, 8.05, 9.4, 59.11, 8.85, 19.6, LK.steel), true)
		Lib.solid(Lib.ab(K, "ERHeaderOut", 59.91, 8.05, 9.4, 60.55, 8.85, 19.6, LK.steel), true)
		Lib.ab(K, "ERTrackIn", 58.86, 7.90, 9.5, 59.09, 8.05, 19.5, LK.alu)
		Lib.ab(K, "ERTrackOut", 59.93, 7.90, 9.5, 60.16, 8.05, 19.5, LK.alu)
		Lib.ab(K, "ERSensorIn", 58.45, 7.85, zc - 0.4, 58.55, 8.05, zc + 0.4, LK.black)
		Lib.ab(K, "ERSensorOut", 60.55, 7.85, zc - 0.4, 60.65, 8.05, zc + 0.4, LK.black)
	end)
	-- 캐노피 + 라이트박스 + 간판
	local canopyLamp: BasePart? = nil
	K:free(function()
		Lib.solid(Lib.ab(K, "ERCanopy", 59.91, 9.40, 10.0, 65.50, 9.70, 19.0, LK.canopy), true)
		Lib.ab(K, "ERFascia", 65.40, 9.10, 10.0, 65.50, 9.70, 19.0, LK.red)
		Lib.tx(K, "ERFasciaText", 8.4, 0.52, Lib.face(65.505, 9.40, 14.5, 1, 0), "응급실  EMERGENCY", C.WHITE, nil, { font = Lib.FONT_K, glow = 1.3 })
		for _, z in { 11.0, 18.0 } do
			K:seg("ERTieRod", V3(64.8, 9.70, z), V3(59.91, 12.4, z), 0.12, LK.steel)
		end
		canopyLamp = Lib.ab(K, "ERCanopyLamp", 62.0, 9.34, 13.6, 63.4, 9.40, 15.4, Look.neon(C3(255, 240, 220)))
		Lib.ab(K, "ERLightBox", 59.91, 10.0, 12.0, 60.25, 11.6, 17.0, Look.neon(C3(214, 30, 30)))
	end)
	Lib.tx(K, "ERLightBoxText", 4.7, 1.4, Lib.face(60.255, 10.8, 14.5, 1, 0), "응급실\nEMERGENCY", C.WHITE, nil, { glow = 2, font = Lib.FONT_K })
	-- 바깥 호출 버튼
	local callBtn = K:plate("ERCallPlate", 0.5, 1.0, 0.09, Lib.face(59.91, 4.1, 20.15, 1, 0), LK.steel)
	K:disc("ERCallButton", 0.3, 0.05, Lib.face(59.995, 4.25, 20.15, 1, 0) * ANG(PI / 2, 0, 0), LK.red)
	Lib.tx(K, "ERCallLabel", 0.46, 0.2, Lib.face(59.996, 3.82, 20.15, 1, 0), "호출", C.INK, nil, { font = Lib.FONT_B })
	Interact.prompt(K, callBtn, {
		action = "응급실 호출",
		object = "응급실 인터폰",
		sound = SND.click,
		fn = function()
			Lib.beeps(callBtn, SND.chime, 2, 0.35, { vol = 0.5, speed = 1.2 })
			UI.toast("응급실에 연락했어요. 의료진이 곧 나와요 (연출)", 3)
		end,
	})
	-- 바닥 유도선 (구급차 베이 → 응급실)
	if not low then
		K:free(function()
			Lib.ab(K, "ERGuideLine", 61.0, -0.34, 3.6, 61.2, -0.33, 12.0, LK.yellow)
			Lib.ab(K, "ERGuideLine", 66.8, -0.34, 3.6, 67.0, -0.33, 12.0, LK.yellow)
			for _, z in { 5.0, 9.0 } do
				local f = CF(64.0, -0.325, z) * ANG(-PI / 2, 0, 0) * ANG(0, 0, PI)
				K:text("ERFloorText", 2.0, 1.0, f, "응급실 ▲", { fg = C3(240, 200, 40), font = Lib.FONT_K, d = 0.01 })
			end
		end)
	end
	-- 안쪽 안내
	Lib.exitSign(K, Lib.face(58.55, 9.45, 13.0, -1, 0), 1.6, "🏃 출구", "door")
	Lib.plate(K, "ERInsidePlate", 2.6, 0.8, Lib.face(58.55, 9.45, 16.4, -1, 0), "응급실 출입구 · 구급차 전용", { bg = C.WHITE, fg = C.RED, band = C.RED })
	K:free(function()
		Lib.ab(K, "ERFloorStrip", 54.2, 0.03, 14.4, 58.9, 0.045, 14.6, LK.yellow)
	end)
	-- 감지 (안 · 밖 둘 다 같이 열림)
	local lastNear = -1e9
	local open = false
	Interact.anim(K, function(t)
		local near = false
		for _, a in Lib.actors() do
			local l = a.l
			if l.Y > -1 and l.Y < 8 and l.Z > 11.0 and l.Z < 18.0 and ((l.X > 54.2 and l.X < 59.11) or (l.X >= 59.11 and l.X < 65.0)) then
				near = true
				break
			end
		end
		if near then
			lastNear = t
			if not open then
				open = true
				Lib.sfx(callBtn, SND.swoosh, { vol = 0.18, speed = 0.75 })
				for _, s in sets do
					for _, mv in s do
						mv:set(1)
					end
				end
			end
		elseif open and t - lastNear > 1.5 then
			open = false
			for _, s in sets do
				for _, mv in s do
					mv:set(0)
				end
			end
		end
	end)
	-- 밤 조명
	local lt: Light? = nil
	if canopyLamp then
		lt = K:light(canopyLamp, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 16, Brightness = 1.2, Angle = 120, Color = Look.neutralLight, Enabled = night() })
	end
	Lib.onSec(K, function()
		if lt then
			lt.Enabled = night()
		end
	end)
end

-- 비상구 --------------------------------------------------------------------------------------------

local function fireExit(K: any, env: any)
	local UI = env.UI
	local z0, z1 = 27.58, 31.58
	-- 맵 방화문 · 패닉바 숨김 (통로는 우리 문짝이 맡음)
	Lib.hideOwn(K, function()
		return Lib.find(Geo.PARTS.fireExitDoor, 2)
	end, true)
	Lib.hideOwn(K, function()
		return Lib.find(Geo.PARTS.pushBar, 2)
	end, true)
	-- 문틀 + 문턱
	K:free(function()
		Lib.ab(K, "FEFrame", 59.11, 0, z0, 59.91, 8.0, z0 + 0.08, LK.frame)
		Lib.ab(K, "FEFrame", 59.11, 0, z1 - 0.08, 59.91, 8.0, z1, LK.frame)
		Lib.ab(K, "FEFrameHead", 59.11, 7.92, z0, 59.91, 8.0, z1, LK.frame)
	end)
	Lib.wall(K, "FEThreshold", 59.11, 0, z0, 59.91, 0.04, z1, LK.steel)
	-- 바깥 계단참 + 계단 한 단
	Lib.wall(K, "FELanding", 59.91, -0.34, 26.8, 63.5, -0.02, 32.4, LK.concrete)
	Lib.wall(K, "FELandingNose", 63.5, -0.34, 26.8, 63.62, -0.04, 32.4, Look.of(240, 200, 40))
	-- 문짝 (경첩 x 59.60, z 31.54 → 바깥(+x)으로 90°)
	local leaf: BasePart? = nil
	local bar: BasePart? = nil
	local lever: BasePart? = nil
	local g = K:group("FireExitLeaf", function()
		K:free(function()
			leaf = Lib.ab(K, "FELeaf", 59.35, 0.03, z0 + 0.04, 59.60, 7.95, z1 - 0.04, LK.fireDoor)
			bar = Lib.ab(K, "FEPanicBar", 58.95, 3.6, 28.0, 59.30, 4.1, 31.0, LK.red)
			Lib.ab(K, "FEPanicEnd", 58.98, 3.45, 27.75, 59.35, 4.25, 28.05, LK.steel)
			Lib.ab(K, "FEPanicEnd", 58.98, 3.45, 30.95, 59.35, 4.25, 31.25, LK.steel)
			Lib.tx(K, "FEInsideNote", 2.4, 0.7, Lib.face(59.345, 5.6, 29.58, -1, 0), "방화문\n항상 닫아 두십시오", C.RED, C.WHITE, { font = Lib.FONT_B })
			Lib.tx(K, "FEPushNote", 1.4, 0.3, Lib.face(58.945, 3.85, 29.5, -1, 0), "밀면 열립니다 PUSH", C.WHITE, nil, { font = Lib.FONT_K })
			-- 바깥 손잡이
			lever = K:box("FELever", V3(0.12, 0.12, 0.6), CF(59.70, 3.8, 28.55), Look.chrome)
			K:cyl("FELeverRose", 0.06, 0.3, CF(59.63, 3.8, 28.3), Look.chrome)
			if K.detail ~= "low" then
				K:box("FECloser", V3(0.22, 0.25, 1.2), CF(59.0, 7.65, 30.7), Look.brushed)
			end
		end)
	end)
	if leaf then
		Lib.solid(leaf, true)
	end
	local hinge = Geo.W(59.60, 0, 31.54)
	local mv = Lib.Swinger(K, Lib.partsOf(g), hinge, Geo.HF.YVector, rad(-90), {
		tOpen = 0.6,
		tClose = 1.8,
		closer = true,
		tLatch = 0.25,
		easeOpen = "quadOut",
		collide = { leaf },
		onLatch = function()
			Lib.sfx(leaf, SND.thunk, { vol = 0.5, speed = 0.7 })
			Lib.sfx(leaf, SND.click, { vol = 0.4, speed = 0.6 })
		end,
	})
	-- 바깥: 캐노피 · 벽등 · 안내
	local lamp: BasePart? = nil
	K:free(function()
		Lib.solid(Lib.ab(K, "FECanopy", 59.91, 8.8, 27.0, 62.5, 9.0, 32.2, LK.canopy), true)
		Lib.ab(K, "FELampBody", 59.91, 8.2, 32.4, 60.2, 8.7, 32.9, LK.black)
		lamp = Lib.ab(K, "FELamp", 60.2, 8.25, 32.45, 60.24, 8.65, 32.85, Look.neon(C3(255, 236, 200)))
	end)
	Lib.tx(K, "FEOutSign", 2.4, 0.7, Lib.face(59.915, 6.0, 33.9, 1, 0), "비상구\n문 앞 물건 적치 금지", C.WHITE, C.GREEN_EXIT, { font = Lib.FONT_B })
	local lt: Light? = nil
	if lamp then
		lt = K:light(lamp, "PointLight", { Range = 12, Brightness = 0.9, Color = Look.warmLight, Enabled = night() })
	end
	-- 열기 / 닫기
	local openUntil = 0
	local function openDoor(fromInside: boolean)
		if mv.target >= 1 then
			openUntil = os.clock() + 3
			return
		end
		openUntil = os.clock() + 3
		local function swing()
			mv:set(1)
			Lib.sfx(leaf, SND.click, { vol = 0.45, speed = 0.6 })
			Lib.sfx(leaf, SND.thunk, { vol = 0.4, speed = 0.7 })
			Lib.beeps(leaf, SND.chime, 3, 0.18, { vol = 0.35, speed = 2.0 })
			if fromInside then
				UI.toast("비상구 문이 열렸어요 (비상시에만 이용해 주세요)", 2.8)
			end
		end
		if fromInside and bar and bar.Parent then
			-- 패닉바 눌림 0.12 초
			local b: BasePart = bar
			local base = b.CFrame
			b.CFrame = base + Geo.HF.XVector * 0.12
			task.delay(0.12, function()
				if b.Parent then
					b.CFrame = base
				end
				swing()
			end)
		else
			swing()
		end
	end
	if bar then
		Interact.prompt(K, bar, { action = "비상구 열기", object = "비상구", sound = false, fn = function()
			openDoor(true)
		end })
	end
	if lever then
		Interact.prompt(K, lever, { action = "문 열기", object = "비상구", sound = false, fn = function()
			openDoor(false)
		end })
	end
	Interact.anim(K, function()
		-- 안에서 문을 향해 걸어가면 자동으로 밀림 (패닉바)
		local hrp, hum = Lib.localRoot()
		if hrp and hum and mv.target < 1 then
			local l = Geo.L(hrp.Position)
			if l.X > 59.11 - 1.4 and l.X < 59.11 and l.Z > z0 + 0.2 and l.Z < z1 - 0.2 and l.Y > -1 and l.Y < 8 then
				local md = Geo.HF:VectorToObjectSpace(hum.MoveDirection)
				if md.X > 0.6 then
					openDoor(true)
				end
			end
		end
		-- 아무도 문 근처(K07 · K08)에 없으면 3 초 뒤 닫힘
		if mv.target > 0 then
			for _, a in Lib.actors() do
				local p = a.l
				if a.kind ~= "npc" and p.Y > -1 and p.Y < 9 and p.Z > 25.6 and p.Z < 33.6 and p.X > 54.5 and p.X < 65.5 then
					openUntil = math.max(openUntil, os.clock() + 3)
				end
			end
			if os.clock() > openUntil then
				mv:set(0)
			end
		end
	end)
	Lib.onSec(K, function()
		if lt then
			lt.Enabled = night()
		end
	end)
end

-- 2F 계단홀 통로 (BackWall2 2 번 조각에 출입구) ------------------------------------------------------

local function landingPassage(K: any)
	local y = 14.15
	local segs = Lib.replaceWall(K, function()
		return Lib.find(Geo.PARTS.backWall2, 2)
	end, { { -7.60, -4.00, y, 21.50 } }, { name = "BackWall2Seg" })
	if #segs == 0 then
		return
	end
	K:free(function()
		for _, zz in { { -4.46, -4.42 }, { -3.82, -3.78 } } do
			Lib.ab(K, "PassJamb", -7.75, y, zz[1], -7.60, 21.50, zz[2], LK.frame)
			Lib.ab(K, "PassJamb", -4.00, y, zz[1], -3.85, 21.50, zz[2], LK.frame)
			Lib.ab(K, "PassHead", -7.75, 21.35, zz[1], -3.85, 21.50, zz[2], LK.frame)
		end
		Lib.ab(K, "PassReturn", -7.60, y, -4.42, -7.56, 21.50, -3.82, LK.frame)
		Lib.ab(K, "PassReturn", -4.04, y, -4.42, -4.00, 21.50, -3.82, LK.frame)
		Lib.ab(K, "PassReturnHead", -7.60, 21.46, -4.42, -4.00, 21.50, -3.82, LK.frame)
		Lib.ab(K, "PassThreshold", -7.60, y, -4.46, -4.00, y + 0.05, -3.78, Look.steel)
		-- 열어 둔 방화문 (자석 홀더에 붙어 있음)
		Lib.ab(K, "HeldFireDoor", -7.55, y + 0.05, -3.78, -7.40, y + 7.30, -0.28, LK.fireIvory)
		K:box("HeldFireDoorBar", V3(0.14, 0.3, 2.2), CF(-7.33, y + 3.8, -2.0), Look.of(200, 40, 40))
		Lib.ab(K, "MagHolder", -8.09, y + 3.2, -0.75, -7.75, y + 3.6, -0.45, Look.steel)
		Lib.ab(K, "MagHolderPad", -7.75, y + 3.25, -0.70, -7.55, y + 3.55, -0.50, Look.black)
		Lib.tx(K, "HeldFireDoorNote", 2.6, 0.7, Lib.face(-7.395, y + 5.6, -2.03, 1, 0), "자동폐쇄 방화문\n화재 시 자동으로 닫힙니다", C.RED, C.WHITE, { font = Lib.FONT_B })
	end)
	-- 안내
	Lib.plate(K, "PassSignCorridor", 2.8, 1.2, Lib.face(-2.2, 19.6, -4.42, 0, -1), "계단 · 비상구\n옥상 정원 RF ↑", { bg = C.GREEN_EXIT, fg = C.WHITE })
	Lib.plate(K, "PassSignLanding", 2.8, 1.2, Lib.face(-2.2, 19.6, -3.82, 0, 1), "복도 · 입원실 · 간호사실\n검진센터 →", { bg = C.TEAL, fg = C.WHITE })
	-- 복도 매달린 피난구 유도등 (양면)
	K:free(function()
		local c = CF(-5.8, 22.05, -6.2)
		for _, sx in { -0.7, 0.7 } do
			K:seg("ExitHangWire", (c * CF(sx, 0.3, 0)).Position, V3((c * CF(sx, 0, 0)).X, Geo.CEIL2, (c * CF(sx, 0, 0)).Z), 0.04, Look.alu)
		end
		for _, n in { 1, -1 } do
			Lib.exitSign(K, Lib.face(-5.8, 22.05, -6.2 + n * 0.0, 0, n) * CF(0, 0, -0.08), 1.6, "🏃 비상구 · 계단", "door")
		end
	end)
end

function X.build(K: any, env: any)
	-- 동쪽 외벽 바꿔 끼우기 (응급실 · 비상구 두 구멍)
	local segs = Lib.replaceWall(K, function()
		return Lib.find(Geo.PARTS.groundEast, 3)
	end, { { 12.00, 17.00, 0, 8.0 }, { 27.58, 31.58, 0, 8.0 } }, { name = "GroundSideSeg" })
	if #segs > 0 then
		erEntrance(K, env)
		fireExit(K, env)
	else
		warn("[HospitalPlus] east wall not replaced; ER entrance and fire exit skipped")
	end
	landingPassage(K)
end

function X.ready(_env: any): boolean
	return Lib.find(Geo.PARTS.groundEast, 3) ~= nil and Lib.find(Geo.PARTS.backWall2, 2) ~= nil
end

return X
