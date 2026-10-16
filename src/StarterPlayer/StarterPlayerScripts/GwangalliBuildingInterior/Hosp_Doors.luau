--!strict
-- GwangalliBuildingInterior/Hosp_Doors: 병원 방문 · 직원 문 (설계 §7.4 · §7.5 · §7.7).
--   * 유리 자동 미닫이 5 곳 (진료실 1 · 주사실 · 입원실 201 · 202 · 건강검진센터): 맵 문짝은 열린 채 옆에 세워져
--     있으므로 숨기고, 닫힌 자리에 새 문짝을 그려 사람 · NPC 가 다가가면 열리고 비면 닫힘 (충돌 없음 = NPC 길 그대로)
--   * 진료실 앞 "진료 중 / 진료 대기" 표시등 (누가 치료 중이거나 환자 NPC 가 진료실 안에 있으면 빨강)
--   * 복도 쪽 호실 명판 + 대기 환자 모니터 + 간호사실 매달린 간판
--   * 1F 후면 홀 STAFF ONLY(직원 휴게실) · 창고 문, 2F 비상계단 문, 옥상 RoofDoor → 숨은 방 (Hosp_Portal)
-- 좌표: 병원 프레임 HF.

local Players = game:GetService("Players")

local here = script.Parent
local Lib = require(here:WaitForChild("Hosp_Lib"))
local Look = require(here:WaitForChild("Look"))
local Interact = require(here:WaitForChild("Interact"))

local D = {}

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
	glass = Look.of(214, 232, 236, M.Glass, { t = 0.55, r = 0.15 }),
	frost = Look.of(246, 248, 248, M.Glass, { t = 0.2 }),
	chrome = Look.chrome,
	steelDoor = Look.of(150, 154, 158, M.Metal),
	fireDoor = Look.of(214, 210, 198, M.Metal),
	oak = Look.of(196, 160, 118, M.Wood),
	frame = Look.of(120, 124, 128, M.Metal),
	black = Look.black,
	white = Look.white,
	teal = Look.of(0, 128, 118),
	housing = Look.of(26, 28, 30),
}

-- 유리 자동문 하나 (Geo.GLASS_DOORS 항목)
local function glassDoor(K: any, spec: any)
	local y = spec.y
	local zc = spec.z
	local cx = (spec.x0 + spec.x1) / 2
	local W = spec.x1 - spec.x0
	local low = K.detail == "low"
	-- 맵 문짝 · 레일 · 손잡이 숨김 (Jamb · Head · Sign 은 그대로)
	Lib.hideModel(K, function()
		local fl = Lib.child(Lib.hospital(), { spec.floorName })
		return fl and fl:FindFirstChild(spec.model)
	end, function(p)
		return p.Name == "DoorLeaf" or p.Name == "LeafRail" or p.Name == "Handle"
	end)
	-- 문짝 (닫힘 = 개구부, 양쪽 문틀에 0.1 겹침)
	local leaves = if spec.wide then { { cx - W / 4, W / 2 + 0.1 }, { cx + W / 4, W / 2 + 0.1 } } else { { cx, W + 0.2 } }
	local lead = -spec.slide -- 닫힐 때 앞서는 쪽 (+1 = +x)
	local g = K:group("GlassDoor_" .. spec.id, function()
		K:free(function()
			for li, lf in leaves do
				local lx, lw = lf[1], lf[2]
				local h = 7.90
				local function at(px: number, py: number): CFrame
					return CF(lx + px, y + py, zc)
				end
				K:box("GlassPane", V3(lw - 0.3, h - 0.45, 0.06), at(0, 0.05 + 0.3 + (h - 0.45) / 2), LK.glass)
				K:box("LeafTopRail", V3(lw, 0.15, 0.10), at(0, 0.05 + h - 0.075), LK.alu)
				K:box("LeafBottomRail", V3(lw, 0.30, 0.10), at(0, 0.05 + 0.15), LK.alu)
				for _, sx in { -1, 1 } do
					K:box("LeafStile", V3(0.15, h, 0.10), at(sx * (lw / 2 - 0.075), 0.05 + h / 2), LK.alu)
				end
				-- 반투명 띠 + 방 이름 (양면)
				K:box("FrostBand", V3(lw - 0.3, 1.2, 0.065), at(0, 3.6), LK.frost)
				if li == 1 or not spec.wide then
					for _, n in { 1, -1 } do
						local f = Lib.face(lx, y + 3.6, zc + n * 0.034, 0, n)
						Lib.tx(K, "DoorRoomName", math.min(lw - 0.5, 3.4), 0.7, f, spec.room, C.TEAL_D, nil, { font = Lib.FONT_K })
					end
				end
				-- 막대 손잡이 (앞서는 쪽 가까이, 양면)
				local hx = lx + (if spec.wide then (if li == 1 then 1 else -1) else lead) * (lw / 2 - 0.45)
				for _, n in { 1, -1 } do
					K:seg("BarHandle", V3(hx, y + 2.9, zc + n * 0.2), V3(hx, y + 5.1, zc + n * 0.2), 0.12, LK.chrome)
					for _, hy in { 3.1, 4.9 } do
						K:seg("BarHandleLeg", V3(hx, y + hy, zc + n * 0.04), V3(hx, y + hy, zc + n * 0.2), 0.07, LK.chrome)
					end
				end
				if not low then
					Lib.tx(K, "AutoSticker", 0.9, 0.22, Lib.face(lx, y + 4.6, zc + 0.034, 0, 1), "자동문", C3(60, 64, 70), nil, { font = Lib.FONT_B })
					Lib.tx(K, "AutoSticker", 0.9, 0.22, Lib.face(lx, y + 4.6, zc - 0.034, 0, -1), "자동문", C3(60, 64, 70), nil, { font = Lib.FONT_B })
				end
			end
		end)
	end)
	-- 위 레일 + 동작 감지기 (문짝 쪽)
	local parkW = W + 0.2
	local tx0 = math.min(spec.x0, spec.x0 + spec.slide * parkW) - 0.2
	local tx1 = math.max(spec.x1, spec.x1 + spec.slide * parkW) + 0.2
	K:free(function()
		local side = if zc < spec.cz then -1 else 1 -- 문짝이 벽의 어느 쪽인가 (z)
		local tz0 = zc - 0.15
		local tz1 = zc + 0.15
		Lib.ab(K, "DoorTrack", tx0, y + 7.95, tz0, tx1, y + 8.30, tz1, LK.alu)
		Lib.ab(K, "DoorSensor", cx - 0.35, y + 7.70, zc + side * 0.15 - 0.1, cx + 0.35, y + 7.95, zc + side * 0.15 + 0.1, LK.black)
		K:disc("DoorSensorEye", 0.12, 0.02, CF(cx, y + 7.69, zc + side * 0.15), Look.ledRed)
	end)
	local mv = Lib.Slider(K, Lib.partsOf(g), Geo.HF.XVector * (spec.slide * (W + 0.3)), {
		tOpen = 0.75,
		tClose = 1.0,
		easeOpen = "quartOut",
		easeClose = "sineInOut",
	})
	local lastNear = -1e9
	local snd = g:FindFirstChildWhichIsA("BasePart")
	Interact.anim(K, function(t)
		local near = false
		for _, a in Lib.actors() do
			local dx, dz = a.l.X - cx, a.l.Z - spec.cz
			if dx * dx + dz * dz < 25 and math.abs(a.l.Y - (y + 3)) < 4 then
				near = true
				break
			end
		end
		if near then
			if mv.target < 1 then
				Lib.sfx(snd, SND.swoosh, { vol = 0.15, speed = 0.8 })
			end
			lastNear = t
			mv:set(1)
		elseif t - lastNear > 1.4 and mv.target > 0 then
			mv:set(0)
		end
	end)
end

-- 진료 중 표시등 (ConsultWall 복도 면)
local function treatingLamp(K: any)
	local f = Lib.face(-20.1, 8.95, -5.77, 0, 1)
	K:plate("TreatLampHousing", 1.8, 0.8, 0.30, f, LK.housing)
	local face = K:plate("TreatLampFace", 1.66, 0.66, 0.02, f * CF(0, 0, 0.30), Look.of(60, 20, 20))
	local _, lab = Lib.tx(K, "TreatLampText", 1.6, 0.6, f * CF(0, 0, 0.325), "진료 대기", C3(220, 230, 230), nil, { glow = 0.6, font = Lib.FONT_K })
	local gui = lab.Parent :: SurfaceGui
	local last: boolean? = nil
	Lib.onSec(K, function()
		local busy = false
		for _, pl in Players:GetPlayers() do
			local ch = pl.Character
			if ch and ch:GetAttribute("GwTreating") == true then
				busy = true
			end
		end
		if not busy then
			for _, a in Lib.actors() do
				if a.kind == "npc" and a.role == "patient" and a.l.X > -59.3 and a.l.X < -14.7 and a.l.Z > -34.8 and a.l.Z < -6.4 and a.l.Y < 9 then
					busy = true
				end
			end
		end
		if busy ~= last then
			last = busy
			lab.Text = if busy then "진료 중" else "진료 대기"
			lab.TextColor3 = if busy then C3(255, 70, 60) else C3(220, 230, 230)
			if gui then
				gui.Brightness = if busy then 1.6 else 0.6
			end
			if face.Parent then
				face.Material = if busy then M.Neon else M.SmoothPlastic
				face.Color = if busy then C3(90, 10, 10) else C3(60, 20, 20)
			end
		end
	end)
end

-- 복도 명판 · 대기 모니터 · 간호사실 간판
local function corridorPlates(K: any)
	local low = K.detail == "low"
	local function namePlate(x: number, y: number, z: number, n: number, w: number, h: number, title: string, sub: string)
		local f = Lib.face(x, y, z, 0, n)
		K:plate("RoomPlate", w, h, 0.05, f, LK.teal)
		K:plate("RoomPlateBand", w, 0.08, 0.06, f * CF(0, h / 2 - 0.04, 0), Look.of(196, 232, 226))
		Lib.tx(K, "RoomPlateTitle", w * 0.92, h * 0.5, f * CF(0, h * 0.14, 0.055), title, C.WHITE, nil, { font = Lib.FONT_K })
		Lib.tx(K, "RoomPlateSub", w * 0.92, h * 0.3, f * CF(0, -h * 0.26, 0.055), sub, Color3.fromRGB(214, 240, 236), nil, { font = Lib.FONT_M })
	end
	namePlate(-16.45, 6.7, -5.82, 1, 2.8, 1.0, "진료실 1 · 내과", "Internal Medicine · 전문의 김선생")
	namePlate(15.9, 19.8, -9.82, 1, 2.8, 1.2, "201호 입원실 · 2인실", "김*수 · 이*영")
	namePlate(-16.4, 19.8, -9.82, 1, 2.8, 1.2, "202호 입원실 · 2인실", "박*진")
	namePlate(-17.8, 19.7, -4.42, -1, 3.6, 1.4, "건강검진센터 · Health Check-up", "접수 08:30 ~ 17:00")
	namePlate(41.7, 19.7, -4.42, -1, 2.8, 1.0, "휴게실 LOUNGE", "자판기 · 정수기 · TV")
	namePlate(27.9, 9.6, -2.42, -1, 2.8, 1.0, "주사실 · 처치실", "Injection · Treatment")
	-- 대기 환자 모니터 (진료실 앞)
	local mf = Lib.face(-16.4, 5.2, -5.82, 0, 1)
	K:plate("WaitMonitorBody", 2.1, 1.3, 0.12, mf, LK.black)
	local scr = K:plate("WaitMonitorScreen", 1.96, 1.16, 0.02, mf * CF(0, 0, 0.12), Look.of(18, 40, 60, M.Neon, { t = 0.1 }))
	local _, lab = Lib.tx(K, "WaitMonitorText", 1.9, 1.08, mf * CF(0, 0, 0.145), "", C.WHITE, nil, { glow = 1.2, font = Lib.FONT_B })
	Interact.screenLoop(K, scr, lab, {
		{ text = "진료 대기\n1  김*수\n2  이*영\n3  박*민" },
		{ text = "지금 진료 중\n7 번" },
		{ text = "진료실 1 · 내과\n전문의 김선생" },
	}, 5)
	if not low then
		-- 간호사실 매달린 간판 (양면)
		local c = CF(-0.5, 21.45, -9.2)
		K:free(function()
			for _, sx in { -1, 1 } do
				K:seg("NurseSignWire", (c * CF(sx * 2.0, 0.45, 0)).Position, V3((c * CF(sx * 2.0, 0, 0)).X, Geo.CEIL2, (c * CF(sx * 2.0, 0, 0)).Z), 0.04, LK.alu)
			end
			K:box("NurseSign", V3(4.6, 0.9, 0.14), c, LK.white)
			K:box("NurseSignBand", V3(4.6, 0.1, 0.16), c * CF(0, 0.4, 0), LK.teal)
			for _, n in { 1, -1 } do
				Lib.tx(K, "NurseSignText", 4.3, 0.66, Lib.face(-0.5, 21.42, -9.2 + n * 0.072, 0, n), "간호사실  NURSE STATION", C.TEAL_D, nil, { font = Lib.FONT_K })
			end
		end)
	end
end

-- 숨은 방으로 가는 홀 문 (STAFF ONLY · 창고): 문짝은 전환할 때만 18° 열림
local function hallDoor(K: any, env: any, id: string, xD: number)
	local hub = env.hub
	local UI = env.UI
	local staff = id == "staff"
	Lib.hideModel(K, function()
		local bz = Lib.child(Lib.hospital(), { "1F", "BackZone" })
		return bz and bz:FindFirstChild(if staff then "Door_STAFF ONLY" else "Door_창고")
	end)
	Lib.wall(K, "HallDoorJamb", xD - 2.10, 0, 38.55, xD - 1.90, 7.85, 38.78, LK.frame)
	Lib.wall(K, "HallDoorJamb", xD + 1.90, 0, 38.55, xD + 2.10, 7.85, 38.78, LK.frame)
	Lib.wall(K, "HallDoorHead", xD - 2.10, 7.65, 38.55, xD + 2.10, 7.85, 38.78, LK.frame)
	local leaf: BasePart? = nil
	local lever: BasePart? = nil
	local g = K:group("HallDoor_" .. id, function()
		K:free(function()
			leaf = Lib.ab(K, "HallDoorLeaf", xD - 1.875, 0.05, 38.58, xD + 1.875, 7.65, 38.73, if staff then LK.oak else LK.steelDoor)
			local f = Lib.face(xD, 0, 38.58, 0, -1)
			K:plate("KickPlate", 3.6, 0.7, 0.02, f * CF(0, 0.45, 0), Look.steel)
			lever = K:box("HallDoorLever", V3(0.65, 0.12, 0.12), CF(xD - 1.35, 3.6, 38.42), LK.chrome)
			K:cyl("HallDoorRose", 0.06, 0.3, CF(xD - 1.6, 3.6, 38.55) * ANG(0, PI / 2, 0), LK.chrome)
			if staff then
				K:plate("DoorLockPad", 0.35, 0.9, 0.08, f * CF(-1.6, 4.4, 0), LK.black)
				K:plate("DoorLockKeys", 0.26, 0.5, 0.01, f * CF(-1.6, 4.45, 0.08), Look.neon(C3(90, 160, 255)))
				Lib.plate(K, "StaffPlate", 2.6, 0.9, f * CF(0, 5.6, 0), "직원 휴게실 · STAFF ONLY", { bg = C.WHITE, fg = C.TEAL_D, band = C.TEAL })
				Lib.tx(K, "NoEntry", 1.8, 0.35, f * CF(0, 4.8, 0.02), "관계자 외 출입금지", C.WHITE, C.RED, { font = Lib.FONT_K })
			else
				for i = 0, 5 do
					K:plate("StoreLouver", 2.2, 0.08, 0.03, f * CF(0, 0.95 + i * 0.15, 0), Look.of(110, 114, 118, M.Metal))
				end
				Lib.plate(K, "StorePlate", 2.6, 0.9, f * CF(0, 5.6, 0), "창고 · STORAGE", { bg = C.WHITE, fg = C3(70, 74, 80), band = C3(110, 114, 118) })
				Lib.tx(K, "NoEntry", 1.8, 0.35, f * CF(0, 4.8, 0.02), "관계자 외 출입금지", C.WHITE, C.RED, { font = Lib.FONT_K })
			end
			if K.detail ~= "low" then
				K:box("DoorCloser", V3(1.1, 0.22, 0.2), CF(xD + 1.1, 7.35, 38.47), Look.brushed)
			end
		end)
	end)
	if leaf then
		Lib.solid(leaf, true)
	end
	local hinge = Geo.W(xD + 1.875, 0, 38.58)
	local mv = Lib.Swinger(K, Lib.partsOf(g), hinge, Geo.HF.YVector, rad(-18), { tOpen = 0.25, tClose = 0.6, easeOpen = "quadOut", easeClose = "quadIn", collide = { leaf } })
	local portal = hub.portal
	if portal then
		portal.registerDoor(id, "hall", Geo.ROOMS[id].hallDoor, function(a: number)
			mv:set(a)
		end)
	end
	if lever then
		local armed = 0
		Interact.prompt(K, lever, {
			action = "들어가기",
			object = if staff then "직원 휴게실" else "창고",
			sound = SND.click,
			fn = function(_n, pr)
				if os.clock() - armed > 4 then
					armed = os.clock()
					UI.toast("관계자 외 출입금지 구역이에요. 들어가려면 한 번 더 누르세요.", 3)
					pr.ActionText = "그래도 들어가기"
					task.delay(4, function()
						if pr.Parent and os.clock() - armed >= 3.9 then
							pr.ActionText = "들어가기"
						end
					end)
					return
				end
				armed = 0
				pr.ActionText = "들어가기"
				if portal then
					portal.go(id, "hall")
				end
			end,
		})
	end
end

-- 2F 계단홀 뒷벽의 비상계단 문 (→ 숨은 비상계단 P3)
local function stairDoor2F(K: any, env: any)
	local portal = env.hub.portal
	local x0, x1 = -7.55, -4.35
	local y = 14.15
	Lib.wall(K, "StairDoorJamb", x0 - 0.20, y, 38.70, x0, y + 7.55, 38.94, LK.frame)
	Lib.wall(K, "StairDoorJamb", x1, y, 38.70, x1 + 0.20, y + 7.55, 38.94, LK.frame)
	Lib.wall(K, "StairDoorHead", x0 - 0.20, y + 7.30, 38.70, x1 + 0.20, y + 7.55, 38.94, LK.frame)
	local leaf: BasePart? = nil
	local bar: BasePart? = nil
	local g = K:group("StairDoor2F", function()
		K:free(function()
			leaf = Lib.ab(K, "StairDoorLeaf", x0, y + 0.02, 38.74, x1, y + 7.30, 38.90, LK.fireDoor)
			bar = K:box("StairDoorBar", V3(2.4, 0.3, 0.14), CF((x0 + x1) / 2, y + 3.8, 38.62), Look.of(200, 40, 40))
			for _, sx in { -1.3, 1.3 } do
				K:box("StairDoorBarEnd", V3(0.25, 0.42, 0.22), CF((x0 + x1) / 2 + sx, y + 3.8, 38.62), Look.steel)
			end
			Lib.tx(K, "StairDoorNote", 1.8, 0.5, Lib.face((x0 + x1) / 2, y + 5.6, 38.735, 0, -1), "방화문\n항상 닫아 두십시오", C.RED, C.WHITE, { font = Lib.FONT_B })
		end)
	end)
	if leaf then
		Lib.solid(leaf, true)
	end
	Lib.exitSign(K, Lib.face((x0 + x1) / 2, y + 7.92, 38.94, 0, -1), 1.6, "🏃 비상구", "door")
	Lib.tx(K, "StairDoorPlate", 0.7, 1.4, Lib.face(-3.75, y + 4.6, 38.94, 0, -1), "비상\n계단\n·\n옥상\nRF ↑", C.WHITE, C.GREEN_EXIT, { font = Lib.FONT_K })
	local hinge = Geo.W(x1, 0, 38.74)
	local mv = Lib.Swinger(K, Lib.partsOf(g), hinge, Geo.HF.YVector, rad(18), { tOpen = 0.25, tClose = 0.6, easeOpen = "quadOut", easeClose = "quadIn", collide = { leaf } })
	if portal then
		portal.registerDoor("stair", "hall", Geo.ROOMS.stair.hallDoor, function(a: number)
			mv:set(a)
		end)
	end
	if bar then
		Interact.prompt(K, bar, {
			action = "옥상 계단으로",
			object = "비상계단",
			sound = SND.click,
			fn = function()
				if portal then
					portal.go("stair", "hall")
				end
			end,
		})
	end
end

-- 옥상 RoofDoor (펜트하우스 남쪽 면): 맵 문은 숨기고(충돌 유지) 새 철문 + 캐노피 + 유도등
local function roofDoor(K: any, env: any)
	local portal = env.hub.portal
	Lib.hideOwn(K, function()
		return Lib.find(Geo.PARTS.roofDoor, 3)
	end, false)
	local y = 25.20
	K:free(function()
		Lib.ab(K, "RoofDoorFrame", 36.35, y, -2.42, 36.55, y + 7.15, -2.20, LK.frame)
		Lib.ab(K, "RoofDoorFrame", 39.70, y, -2.42, 39.90, y + 7.15, -2.20, LK.frame)
		Lib.ab(K, "RoofDoorFrameHead", 36.35, y + 6.95, -2.42, 39.90, y + 7.15, -2.20, LK.frame)
		Lib.ab(K, "RoofCanopy", 35.8, y + 7.40, -4.0, 40.4, y + 7.60, -2.22, Look.of(236, 236, 232))
		Lib.ab(K, "RoofCanopyLamp", 37.6, y + 7.36, -3.4, 38.7, y + 7.40, -2.8, Look.neon(C3(255, 236, 200)))
	end)
	local leaf: BasePart? = nil
	local bar: BasePart? = nil
	local g = K:group("RoofDoorLeaf", function()
		K:free(function()
			leaf = Lib.ab(K, "RoofDoorLeaf", 36.55, y, -2.40, 39.70, y + 6.95, -2.25, Look.of(130, 136, 140, M.Metal))
			bar = K:box("RoofDoorPull", V3(0.14, 1.6, 0.14), CF(36.95, y + 3.8, -2.55), LK.chrome)
			for _, hy in { 3.1, 4.5 } do
				K:seg("RoofDoorPullLeg", V3(36.95, y + hy, -2.40), V3(36.95, y + hy, -2.55), 0.08, LK.chrome)
			end
			Lib.tx(K, "RoofDoorNote", 2.2, 0.55, Lib.face(38.12, y + 5.6, -2.405, 0, -1), "옥상 출입문 · 비상시 자동 개방\n문을 닫아 주세요", C.INK, C.WHITE, { font = Lib.FONT_B })
		end)
	end)
	Lib.exitSign(K, Lib.face(38.12, y + 8.05, -2.20, 0, -1), 1.6, "🏃 비상구 · 계단", "door")
	local hinge = Geo.W(39.70, 0, -2.40)
	local mv = Lib.Swinger(K, Lib.partsOf(g), hinge, Geo.HF.YVector, rad(18), { tOpen = 0.25, tClose = 0.6, easeOpen = "quadOut", easeClose = "quadIn" })
	if portal then
		portal.registerDoor("stair", "roof", Geo.ROOMS.stair.roofDoor, function(a: number)
			mv:set(a)
		end)
	end
	if bar then
		Interact.prompt(K, bar, {
			action = "계단으로 내려가기",
			object = "비상계단 · 2층",
			sound = SND.click,
			fn = function()
				if portal then
					portal.go("stair", "roof")
				end
			end,
		})
	end
	local _ = leaf
end

function D.build(K: any, env: any)
	for _, spec in Geo.GLASS_DOORS do
		glassDoor(K, spec)
	end
	treatingLamp(K)
	corridorPlates(K)
	hallDoor(K, env, "staff", -12.09)
	hallDoor(K, env, "store", -22.09)
	stairDoor2F(K, env)
	roofDoor(K, env)
end

function D.unbuild(_K: any, env: any)
	local portal = env.hub.portal
	if portal then
		portal.unregisterDoors()
	end
end

function D.ready(_env: any): boolean
	return Lib.child(Lib.hospital(), { "1F" }) ~= nil and Lib.child(Lib.hospital(), { "2F" }) ~= nil
end

return D
