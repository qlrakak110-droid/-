--!strict
-- GwangalliCarInterior/Trim: 도어 트림(앞·뒤 문마다: 하단 패널, 가죽 중단 + 스티치, 우드/알루미늄 띠, 앰비언트,
-- 팔걸이 + 창문 스위치, 손잡이 컵 + 크롬 도어 핸들, 원형 스피커 + 크롬 링, 맵포켓, 창틀 롤), B·C 필러 트림,
-- 헤드라이너 + 둥근 가장자리, 오버헤드 콘솔(맵램프 · SOS), 손잡이, 선바이저(화장 거울 커버), 룸미러(자동 감광),
-- 바닥 매트, 알루미늄 페달 + 고무 띠 + 풋레스트.

local Trim = {}

local ROT_X_TO_Z = CFrame.Angles(0, -math.pi / 2, 0)
local ROT_X_TO_SIDE = CFrame.new() -- 원통 축 X = 차 옆 방향 그대로

local function doorCard(K: any, F: any, P: any, side: number, z0: number, z1: number, front: boolean, driver: boolean)
	local half: number = F.halfIn
	local x = side * (half + 0.02)
	local y0: number = F.trimY0 or F.floorY
	local y1: number = F.trimY1 or (F.floorY + 2.2)
	local len = z1 - z0
	if len < 0.8 then
		return
	end
	local zc = (z0 + z1) / 2
	local inward = -side
	-- 하단 / 중단 / 상단
	local lowH = (y1 - y0) * 0.42
	K:box("DoorLower", Vector3.new(0.1, lowH, len - 0.06), CFrame.new(x, y0 + lowH / 2, zc), P.hard)
	local midY = y0 + lowH + 0.24
	K:box("DoorSoft", Vector3.new(0.08, 0.46, len - 0.2), CFrame.new(x + inward * 0.03, midY, zc), P.doorSoft)
	K:box("DoorStitch", Vector3.new(0.01, 0.01, len - 0.3), CFrame.new(x + inward * 0.075, midY + 0.2, zc), P.stitch)
	K:box("DoorStitch", Vector3.new(0.01, 0.01, len - 0.3), CFrame.new(x + inward * 0.075, midY - 0.2, zc), P.stitch)
	local upY0 = midY + 0.23
	local upH = y1 - upY0
	if upH > 0.05 then
		K:box("DoorUpper", Vector3.new(0.09, upH, len - 0.08), CFrame.new(x, upY0 + upH / 2, zc), P.soft)
	end
	K:cyl("DoorSill", len - 0.1, 0.14, CFrame.new(x + inward * 0.01, y1 - 0.02, zc) * CFrame.Angles(0, math.pi / 2, 0), P.soft)
	K:box("DoorTrimBand", Vector3.new(0.04, 0.09, len - 0.4), CFrame.new(x + inward * 0.06, upY0 + 0.1, zc), P.trim)
	K:box("DoorAmbient", Vector3.new(0.02, 0.02, len - 0.6), CFrame.new(x + inward * 0.07, upY0 + 0.03, zc), P.ambient)
	-- 팔걸이 + 창문 스위치
	local armY = y0 + lowH + 0.02
	local armZ = zc + len * 0.08
	K:rbox("DoorArmrest", Vector3.new(len * 0.55, 0.13, 0.36), 0.06, CFrame.new(x + inward * 0.2, armY, armZ) * CFrame.Angles(0, math.pi / 2, 0), P.leather)
	local sw = CFrame.new(x + inward * 0.25, armY + 0.075, armZ - len * 0.14)
	K:box("WindowSwitches", Vector3.new(0.2, 0.025, if driver then 0.48 else 0.2), sw, P.gloss)
	for i = 0, (if driver then 3 else 0) do
		K:box("WindowSwitch", Vector3.new(0.08, 0.03, 0.07), sw * CFrame.new(0, 0.02, (if driver then -0.16 else 0) + i * 0.105), P.button)
	end
	-- 손잡이 컵 + 크롬 핸들 (문 앞쪽)
	local hz = z0 + 0.42
	local hy = armY + 0.42
	K:box("HandleCup", Vector3.new(0.05, 0.16, 0.42), CFrame.new(x + inward * 0.06, hy, hz), P.duct)
	K:box("DoorHandle", Vector3.new(0.05, 0.05, 0.32), CFrame.new(x + inward * 0.09, hy + 0.01, hz), P.chrome)
	K:box("LockTab", Vector3.new(0.05, 0.05, 0.07), CFrame.new(x + inward * 0.09, hy, hz + 0.26), P.button)
	-- 원형 스피커 (문 아래 앞쪽) + 맵포켓
	local sp = CFrame.new(x + inward * 0.06, y0 + lowH * 0.55, z0 + 0.5)
	K:cyl("SpeakerRing", 0.03, 0.58, sp, P.chrome)
	K:cyl("SpeakerGrille", 0.035, 0.52, sp * CFrame.new(inward * 0.005, 0, 0), P.grille)
	K:box("MapPocket", Vector3.new(0.12, 0.2, len * 0.45), CFrame.new(x + inward * 0.07, y0 + 0.2, zc + len * 0.12), P.hardDark)
	-- 바닥 쪽 반사등
	K:box("DoorReflector", Vector3.new(0.03, 0.05, 0.2), CFrame.new(x + inward * 0.06, y0 + 0.06, z1 - 0.25), P.reflector)
end

function Trim.build(K: any, F: any, P: any)
	local half: number = F.halfIn
	local commercial = F.kind == "truck" or F.kind == "ambulance"
	-- 문 ---------------------------------------------------------------------------------------------
	local z0: number, z1: number = F.doorZ0, F.doorZ1
	local bz: number? = F.bZ
	local split = if bz and bz > z0 + 1 and bz < z1 - 0.8 then bz else nil
	for _, side in { -1, 1 } do
		local driver = side == F.side
		if split then
			doorCard(K, F, P, side, z0 + 0.05, split - 0.08, true, driver)
			if not commercial then
				doorCard(K, F, P, side, split + 0.08, z1 - 0.05, false, false)
			end
			-- B필러 트림
			local y1: number = F.trimY1 or (F.floorY + 2.2)
			local ph = F.roofY - y1
			if ph > 0.2 then
				K:box("BPillarTrim", Vector3.new(0.14, ph, 0.5), CFrame.new(side * (half - 0.02), y1 + ph / 2, split), P.fabric)
			end
		else
			doorCard(K, F, P, side, z0 + 0.05, z1 - 0.05, true, driver)
		end
	end

	-- 헤드라이너 + 둥근 가장자리 + 오버헤드 콘솔 ----------------------------------------------------------------
	local roofY: number = F.roofY
	local lz0: number = F.linerZ0 or (F.wsHigh :: Vector3).Z
	local lz1: number = F.linerZ1 or z1
	local llen = lz1 - lz0
	if llen > 0.5 then
		K:box("Headliner", Vector3.new(half * 2 - 0.1, 0.06, llen), CFrame.new(0, roofY + 0.02, (lz0 + lz1) / 2), P.fabric)
		for _, s in { -1, 1 } do
			K:cyl("HeadlinerEdge", llen, 0.24, CFrame.new(s * (half - 0.1), roofY - 0.02, (lz0 + lz1) / 2) * CFrame.Angles(0, math.pi / 2, 0), P.fabric)
		end
		local oc = CFrame.new(0, roofY - 0.06, lz0 + 0.45)
		K:rbox("OverheadConsole", Vector3.new(0.78, 0.12, 0.5), 0.05, oc, P.hard)
		for _, s in { -1, 1 } do
			K:box("MapLamp", Vector3.new(0.2, 0.02, 0.12), oc * CFrame.new(s * 0.22, -0.065, 0.02), P.lampLens)
		end
		K:box("SOS", Vector3.new(0.08, 0.02, 0.05), oc * CFrame.new(0, -0.065, 0.15), P.hazard)
		K:box("RoofSwitch", Vector3.new(0.14, 0.02, 0.06), oc * CFrame.new(0, -0.065, -0.12), P.button)
		-- 실내등 (뒤)
		K:box("DomeLamp", Vector3.new(0.4, 0.02, 0.2), CFrame.new(0, roofY - 0.01, lz0 + llen * 0.6), P.lampLens)
		-- 손잡이 (조수석 + 뒤 양쪽)
		for _, g in { { -F.side, lz0 + 0.9 }, { -1, lz0 + llen * 0.7 }, { 1, lz0 + llen * 0.7 } } do
			local gx = g[1] * (half - 0.14)
			local gz = g[2]
			K:seg("GrabHandle", Vector3.new(gx, roofY - 0.04, gz - 0.28), Vector3.new(gx - g[1] * 0.06, roofY - 0.16, gz - 0.2), 0.05, P.hard)
			K:seg("GrabHandle", Vector3.new(gx - g[1] * 0.06, roofY - 0.16, gz - 0.2), Vector3.new(gx - g[1] * 0.06, roofY - 0.16, gz + 0.2), 0.05, P.hard)
			K:seg("GrabHandle", Vector3.new(gx - g[1] * 0.06, roofY - 0.16, gz + 0.2), Vector3.new(gx, roofY - 0.04, gz + 0.28), 0.05, P.hard)
		end
	end

	-- 선바이저 + 룸미러 --------------------------------------------------------------------------------------
	local hi: Vector3 = F.wsHigh
	for _, s in { -1, 1 } do
		local v = CFrame.new(s * 1.15, roofY - 0.06, hi.Z + 0.42)
		K:rbox("SunVisor", Vector3.new(1.18, 0.06, 0.6), 0.03, v, P.fabric)
		K:box("VanityCover", Vector3.new(0.5, 0.012, 0.26), v * CFrame.new(-s * 0.1, -0.035, 0.04), P.hard)
		K:cyl("VisorRod", 0.4, 0.04, v * CFrame.new(s * 0.62, 0.0, -0.22) * CFrame.Angles(0, math.pi / 2, 0), P.hard)
	end
	local mp: Vector3 = F.mirror or Vector3.new(0, roofY - 0.3, hi.Z + 0.35)
	local mcf = CFrame.new(mp) * CFrame.Angles(math.rad(-8), 0, 0)
	K:seg("MirrorStem", Vector3.new(mp.X, roofY + 0.02, hi.Z + 0.05), mp + Vector3.new(0, 0.08, -0.04), 0.06, P.hardDark)
	K:rbox("MirrorBody", Vector3.new(0.86, 0.25, 0.1), 0.06, mcf, P.hardDark)
	K:box("MirrorGlass", Vector3.new(0.78, 0.18, 0.01), mcf * CFrame.new(0, 0, 0.055), P.mirror)

	-- 바닥 매트 + 페달 ---------------------------------------------------------------------------------------
	local floor: number = F.floorY
	for _, s in F.front do
		K:box("FloorMat", Vector3.new(math.min(s.w, 1.7) - 0.1, 0.03, 1.6), CFrame.new(s.x, floor + 0.016, s.z - s.cushSize.Z / 2 - 0.85), P.mat)
		K:box("MatPiping", Vector3.new(math.min(s.w, 1.7) - 0.05, 0.035, 0.035), CFrame.new(s.x, floor + 0.018, s.z - s.cushSize.Z / 2 - 0.05), P.stitch)
	end
	for _, s in F.rear do
		if s.w >= 2.6 then
			for _, sx in { -1, 1 } do
				K:box("FloorMat", Vector3.new(1.5, 0.03, 1.1), CFrame.new(s.x + sx * s.w / 3, floor + 0.016, s.z - s.cushSize.Z / 2 - 0.6), P.mat)
			end
		end
	end
	local ped = F.pedals or {}
	table.sort(ped, function(a: Vector3, b: Vector3)
		return math.abs(a.X) > math.abs(b.X)
	end)
	-- 바깥쪽 = 브레이크, 안쪽 = 가속 (좌핸들)
	local brake, gas = ped[1], ped[2]
	if brake then
		local c = CFrame.new(brake) * CFrame.Angles(math.rad(-25), 0, 0)
		K:box("BrakePedal", Vector3.new(0.44, 0.3, 0.04), c, P.alloy)
		for i = -1, 1 do
			K:box("PedalRubber", Vector3.new(0.36, 0.035, 0.02), c * CFrame.new(0, i * 0.08, 0.025), P.rubber)
		end
		K:seg("PedalArm", brake + Vector3.new(0, 0.1, -0.05), brake + Vector3.new(0, 0.62, -0.32), 0.05, P.metalDark)
		-- 풋레스트
		local fx = brake.X + F.side * 0.55
		K:box("FootRest", Vector3.new(0.3, 0.5, 0.04), CFrame.new(fx, floor + 0.35, brake.Z - 0.1) * CFrame.Angles(math.rad(-40), 0, 0), P.alloy)
	end
	if gas then
		local c = CFrame.new(gas + Vector3.new(0, -0.05, 0)) * CFrame.Angles(math.rad(-35), 0, 0)
		K:box("GasPedal", Vector3.new(0.26, 0.6, 0.04), c, P.alloy)
		for i = -2, 2 do
			K:box("PedalRubber", Vector3.new(0.035, 0.5, 0.02), c * CFrame.new(i * 0.05, 0, 0.025), P.rubber)
		end
	end
	return {}
end

Trim.REPLACES = { "DoorTrim", "DoorTrimUpper", "Armrest", "AmbientDoor", "SpeakerGrille", "Headliner", "SunVisor", "RearViewMirror", "Pedal", "FloorMat" }

return Trim
