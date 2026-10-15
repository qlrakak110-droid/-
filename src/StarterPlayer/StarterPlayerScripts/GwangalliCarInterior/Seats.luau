--!strict
-- GwangalliCarInterior/Seats: 좌석. 앞좌석 = 레일 + 받침 + 쿠션(가운데 인서트 + 양옆 볼스터 + 앞 롤) + 13° 기울어진
-- 등받이(인서트 · 볼스터 · 어깨 롤 · 뒤판 · 맵포켓) + 크롬 기둥 헤드레스트 + 옆면 파워시트 스위치 + 안전벨트 · 버클.
-- 고급차(제네시스)는 인서트에 다이아몬드 퀼팅. 뒷좌석 = 3인 벤치(바깥 두 자리 볼스터) + 등받이 3분할 +
-- 헤드레스트 3 + 가운데 팔걸이.

local Seats = {}

local ROT_X_TO_Y = CFrame.Angles(0, 0, math.pi / 2)

local function quilt(K: any, frame: CFrame, w: number, h: number, look: any)
	-- 다이아몬드 퀼팅 (대각선 스티치 두 방향)
	local n = 4
	for i = -n, n do
		local off = i * w / (n + 1)
		for _, s in { -1, 1 } do
			K:box("Quilt", Vector3.new(0.008, h * 1.2, 0.006), frame * CFrame.new(off, 0, 0) * CFrame.Angles(0, 0, s * math.rad(35)), look)
		end
	end
end

local function frontSeat(K: any, F: any, P: any, s: any)
	local x, w = s.x, math.min(s.w, 1.85)
	local cs: Vector3 = s.cushSize
	local cushTop = s.cush.Y + cs.Y / 2
	local zR = s.z + cs.Z / 2 -- 뒤 끝
	local floor: number = F.floorY
	local lux = F.kind == "luxury"
	local seatLook = P.leather
	local insertLook = if F.seatFabric then P.fabricSeat else P.leatherInsert

	-- 레일 + 받침
	for _, sx in { -0.32, 0.32 } do
		K:box("SeatRail", Vector3.new(0.07, 0.06, cs.Z + 0.4), CFrame.new(x + sx * w, floor + 0.04, s.z), P.metalDark)
	end
	local baseH = math.max(0.1, cushTop - 0.3 - floor)
	K:box("SeatBase", Vector3.new(w * 0.78, baseH, cs.Z * 0.8), CFrame.new(x, floor + baseH / 2 + 0.05, s.z + 0.05), P.hardDark)
	-- 옆 덮개 + 파워시트 스위치 (바깥쪽)
	local out = if x < 0 then -1 else 1
	local shield = CFrame.new(x + out * (w / 2 + 0.02), cushTop - 0.32, s.z)
	K:box("SeatShield", Vector3.new(0.06, 0.3, cs.Z * 0.9), shield, P.hard)
	K:box("SeatSwitch", Vector3.new(0.03, 0.06, 0.32), shield * CFrame.new(out * 0.04, 0.02, -0.1), P.satin)
	K:box("SeatSwitch", Vector3.new(0.03, 0.12, 0.06), shield * CFrame.new(out * 0.04, 0.04, 0.16), P.satin)

	-- 쿠션
	local pan = CFrame.new(x, cushTop - 0.14, s.z)
	K:rbox("CushionPan", Vector3.new(w - 0.14, 0.24, cs.Z - 0.05), 0.1, pan, seatLook)
	K:box("CushionInsert", Vector3.new(w * 0.5, 0.04, cs.Z * 0.72), pan * CFrame.new(0, 0.12, 0.04), insertLook)
	if lux then
		quilt(K, pan * CFrame.new(0, 0.143, 0.04) * CFrame.Angles(math.rad(90), 0, 0), w * 0.5, cs.Z * 0.6, P.stitch)
	end
	for _, sx in { -1, 1 } do
		K:ell("CushionBolster", Vector3.new(0.34, 0.3, cs.Z * 0.96), pan * CFrame.new(sx * (w / 2 - 0.2), 0.08, 0.02), seatLook)
		K:box("CushionStitch", Vector3.new(0.01, 0.01, cs.Z * 0.72), pan * CFrame.new(sx * (w * 0.25 + 0.01), 0.142, 0.04), P.stitch)
	end
	K:cyl("CushionRoll", w - 0.2, 0.26, pan * CFrame.new(0, 0.0, -cs.Z / 2 + 0.1), seatLook)

	-- 등받이 (13° 뒤로) -------------------------------------------------------------------------------------
	local bs: Vector3 = s.backSize or Vector3.new(w, 2.0, 0.45)
	local H = math.max(1.7, bs.Y)
	local hinge = CFrame.new(x, cushTop - 0.05, zR - 0.12) * CFrame.Angles(math.rad(13), 0, 0)
	local backC = hinge * CFrame.new(0, H / 2, 0.05)
	K:rbox("BackCore", Vector3.new(H, w - 0.2, 0.3), 0.12, backC * ROT_X_TO_Y, seatLook)
	K:box("BackInsert", Vector3.new(w * 0.5, H * 0.66, 0.04), backC * CFrame.new(0, -0.08, -0.16), insertLook)
	if lux then
		quilt(K, backC * CFrame.new(0, -0.08, -0.185), w * 0.5, H * 0.56, P.stitch)
	end
	for _, sx in { -1, 1 } do
		K:ell("BackBolster", Vector3.new(0.36, H * 0.82, 0.42), backC * CFrame.new(sx * (w / 2 - 0.2), -0.06, -0.1), seatLook)
		K:box("BackStitch", Vector3.new(0.01, H * 0.66, 0.01), backC * CFrame.new(sx * (w * 0.25 + 0.01), -0.08, -0.185), P.stitch)
	end
	K:ell("BackShoulder", Vector3.new(w - 0.2, 0.3, 0.34), backC * CFrame.new(0, H / 2 - 0.12, 0), seatLook)
	K:box("BackPanel", Vector3.new(w - 0.32, H * 0.8, 0.04), backC * CFrame.new(0, -0.05, 0.17), P.hard)
	K:box("MapPocket", Vector3.new(w - 0.5, H * 0.3, 0.035), backC * CFrame.new(0, -H * 0.24, 0.2), P.hardDark)

	-- 헤드레스트 -------------------------------------------------------------------------------------------
	local headTop = backC * CFrame.new(0, H / 2 + 0.08, 0.02)
	local hp: Vector3 = s.head or headTop.Position + Vector3.new(0, 0.32, 0)
	local hcf = CFrame.new(Vector3.new(x, math.max(hp.Y, headTop.Position.Y + 0.3), headTop.Position.Z + 0.02)) * CFrame.Angles(math.rad(13), 0, 0)
	K:rbox("Headrest", Vector3.new(0.92, 0.5, 0.26), 0.12, hcf, seatLook)
	K:ell("HeadrestPad", Vector3.new(0.78, 0.38, 0.16), hcf * CFrame.new(0, 0, -0.1), insertLook)
	for _, sx in { -0.22, 0.22 } do
		local a = (headTop * CFrame.new(sx, -0.06, 0)).Position
		local b = (hcf * CFrame.new(sx, -0.24, 0)).Position
		K:seg("HeadrestPost", a, b, 0.045, P.chrome)
	end

	-- 안전벨트 (B필러를 따라 내려옴) + 버클 ----------------------------------------------------------------------
	local half: number = F.halfIn
	local bz = (F.bZ or zR + 0.2) + 0.12
	local top = Vector3.new(out * (half - 0.08), F.roofY - 0.55, bz)
	local low = Vector3.new(out * (half - 0.06), cushTop + 0.1, bz + 0.25)
	local v = top - low
	local zAxis = v.Unit
	local xAxis = (Vector3.xAxis - zAxis * Vector3.xAxis:Dot(zAxis)).Unit
	K:box("SeatBelt", Vector3.new(0.02, 0.17, v.Magnitude), CFrame.fromMatrix((top + low) / 2, xAxis, zAxis:Cross(xAxis), zAxis), P.belt)
	K:box("BeltAnchor", Vector3.new(0.04, 0.12, 0.22), CFrame.new(top), P.hardDark)
	local buckle = CFrame.new(x - out * (w / 2 + 0.06), cushTop + 0.05, zR - 0.2) * CFrame.Angles(math.rad(-20), 0, 0)
	K:box("Buckle", Vector3.new(0.09, 0.22, 0.06), buckle, P.hardDark)
	K:box("BuckleRelease", Vector3.new(0.06, 0.03, 0.02), buckle * CFrame.new(0, 0.08, -0.03), P.hazard)
end

local function rearBench(K: any, F: any, P: any, s: any)
	local cs: Vector3 = s.cushSize
	local W = cs.X
	local cushTop = s.cush.Y + cs.Y / 2
	local zR = s.z + cs.Z / 2
	local floor: number = F.floorY
	local seatLook = P.leather
	local insertLook = if F.seatFabric then P.fabricSeat else P.leatherInsert
	-- 받침
	local baseH = math.max(0.1, cushTop - 0.25 - floor)
	K:box("BenchBase", Vector3.new(W - 0.1, baseH, cs.Z * 0.85), CFrame.new(s.x, floor + baseH / 2, s.z + 0.05), P.hardDark)
	-- 3 자리 쿠션
	local seatW = W / 3
	for i = -1, 1 do
		local cx = s.x + i * seatW
		local pan = CFrame.new(cx, cushTop - 0.13, s.z)
		K:rbox("BenchPan", Vector3.new(seatW - 0.04, 0.24, cs.Z - 0.05), 0.1, pan, seatLook)
		K:box("BenchInsert", Vector3.new(seatW * 0.62, 0.04, cs.Z * 0.7), pan * CFrame.new(0, 0.12, 0.05), insertLook)
		if i ~= 0 then
			K:ell("BenchBolster", Vector3.new(0.3, 0.24, cs.Z * 0.92), pan * CFrame.new(i * (seatW / 2 - 0.12), 0.07, 0.02), seatLook)
		end
		K:cyl("BenchRoll", seatW - 0.12, 0.24, pan * CFrame.new(0, 0, -cs.Z / 2 + 0.1), seatLook)
	end
	-- 등받이 (18°)
	local bs: Vector3 = s.backSize or Vector3.new(W, 1.8, 0.45)
	local H = math.max(1.5, bs.Y)
	local hinge = CFrame.new(s.x, cushTop - 0.05, zR - 0.1) * CFrame.Angles(math.rad(18), 0, 0)
	for i = -1, 1 do
		local bc = hinge * CFrame.new(i * seatW, H / 2, 0.06)
		K:rbox("BenchBack", Vector3.new(H, seatW - 0.05, 0.3), 0.11, bc * ROT_X_TO_Y, seatLook)
		K:box("BenchBackInsert", Vector3.new(seatW * 0.6, H * 0.62, 0.04), bc * CFrame.new(0, -0.1, -0.16), insertLook)
		K:ell("BenchShoulder", Vector3.new(seatW - 0.1, 0.26, 0.32), bc * CFrame.new(0, H / 2 - 0.1, 0), seatLook)
	end
	-- 가운데 팔걸이 (접힌 상태: 등받이 면에 보이는 경계)
	local mid = hinge * CFrame.new(0, H * 0.32, -0.12)
	K:box("ArmrestSeam", Vector3.new(0.012, H * 0.5, 0.01), mid * CFrame.new(-0.3, 0, -0.06), P.hardDark)
	K:box("ArmrestSeam", Vector3.new(0.012, H * 0.5, 0.01), mid * CFrame.new(0.3, 0, -0.06), P.hardDark)
	-- 헤드레스트 3
	local heads = F.rearHeads or {}
	local xs = {}
	for _, h in heads do
		table.insert(xs, h)
	end
	if #xs < 2 then
		xs = { Vector3.new(s.x - seatW, 0, 0), Vector3.new(s.x + seatW, 0, 0) }
	end
	table.insert(xs, Vector3.new(s.x, 0, 0))
	for k, hp in xs do
		local topC = hinge * CFrame.new(hp.X - s.x, H + 0.05, 0.06)
		local small = k == #xs
		local hc = topC * CFrame.new(0, if small then 0.18 else 0.24, 0)
		K:rbox("RearHeadrest", Vector3.new(if small then 0.62 else 0.82, if small then 0.3 else 0.42, 0.24), 0.1, hc, seatLook)
		for _, sx in { -0.18, 0.18 } do
			K:seg("RearHeadPost", (topC * CFrame.new(sx * (if small then 0.7 else 1), -0.05, 0)).Position, (hc * CFrame.new(sx * (if small then 0.7 else 1), -0.12, 0)).Position, 0.04, P.chrome)
		end
	end
end

function Seats.build(K: any, F: any, P: any)
	for _, s in F.front do
		frontSeat(K, F, P, s)
	end
	for _, s in F.rear do
		if s.w >= 2.6 then
			rearBench(K, F, P, s)
		end
	end
	return {}
end

Seats.REPLACES = { "SeatCushion", "SeatBack", "SeatInsert", "Headrest", "SeatBase", "SeatSupport", "RearBench" }

return Seats
