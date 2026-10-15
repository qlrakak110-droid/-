--!strict
-- GwangalliCarInterior/Seats: 좌석 (차종별 인서트 · 볼스터, Styles 참고). 앞좌석 = 레일 + 받침 + 쿠션(가운데 인서트 +
-- 양옆 볼스터 + 앞 롤) + 13° 기울어진 등받이(인서트 · 볼스터 · 어깨 롤 · 뒤판 · 맵포켓) + 크롬 기둥 헤드레스트 + 옆면
-- 파워시트 스위치 + 안전벨트 · 버클. 인서트: perf(쏘나타 세로 스티치) · quilt(G80 다이아몬드 퀼팅 나파) · hstitch(투싼 ·
-- 카니발 가로 섹션) · plain(레이) · fabric(택시 · 포터 · 쏠라티 천). 카니발 2열 = VIP 캡틴 시트(윙 헤드레스트 · 양쪽
-- 팔걸이 · 레그레스트), 쏠라티 = 안쪽 접이식 팔걸이. 뒷좌석 = 3인 벤치 + 등받이 3분할 + 헤드레스트 3 + 가운데 팔걸이.

local Seats = {}

local ROT_X_TO_Y = CFrame.Angles(0, 0, math.pi / 2)

local function quilt(K: any, frame: CFrame, w: number, h: number, look: any)
	-- 다이아몬드 퀼팅 (대각선 스티치 두 방향)
	local n = 3
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
	local st = F.style.seat
	local ins: string = st.insert
	local lux = ins == "quilt"
	local bol: number = st.bolster or 1
	local seatLook = if ins == "fabric" then P.fabricSide else P.leather
	local insertLook = if ins == "fabric" then P.fabricSeat else P.leatherInsert

	-- 레일 + 받침
	for _, sx in { -0.32, 0.32 } do
		K:box("SeatRail", Vector3.new(0.07, 0.06, cs.Z + 0.4), CFrame.new(x + sx * w, floor + 0.04, s.z), P.metalDark)
	end
	local baseH = math.max(0.1, cushTop - 0.3 - floor)
	K:zbox("SeatBase", Vector3.new(w * 0.78, baseH, cs.Z * 0.8), math.min(0.08, baseH / 2 - 0.01), CFrame.new(x, floor + baseH / 2 + 0.05, s.z + 0.05), P.hardDark)
	-- 옆 덮개 + 파워시트 스위치 (바깥쪽)
	local out = if x < 0 then -1 else 1
	if not s.inner then
		local shield = CFrame.new(x + out * (w / 2 + 0.02), cushTop - 0.32, s.z)
		K:zbox("SeatShield", Vector3.new(0.07, 0.3, cs.Z * 0.9), 0.034, shield, P.hard)
		K:capsule("SeatSwitch", (shield * CFrame.new(out * 0.045, 0.02, -0.24)).Position, (shield * CFrame.new(out * 0.045, 0.02, 0.02)).Position, 0.045, P.satin)
		K:capsule("SeatSwitch", (shield * CFrame.new(out * 0.045, -0.02, 0.16)).Position, (shield * CFrame.new(out * 0.045, 0.1, 0.16)).Position, 0.04, P.satin)
	end

	-- 쿠션
	local pan = CFrame.new(x, cushTop - 0.14, s.z)
	K:rbox("CushionPan", Vector3.new(w - 0.14, 0.24, cs.Z - 0.05), 0.1, pan, seatLook)
	K:box("CushionInsert", Vector3.new(w * 0.5, 0.04, cs.Z * 0.72), pan * CFrame.new(0, 0.12, 0.04), insertLook)
	if lux then
		quilt(K, pan * CFrame.new(0, 0.143, 0.04) * CFrame.Angles(math.rad(90), 0, 0), w * 0.5, cs.Z * 0.6, P.stitch)
	elseif ins == "hstitch" then
		for i = -1, 1 do
			K:box("CushionStitch", Vector3.new(w * 0.48, 0.008, 0.01), pan * CFrame.new(0, 0.142, 0.04 + i * cs.Z * 0.2), P.stitch)
		end
	end
	for _, sx in { -1, 1 } do
		K:ell("CushionBolster", Vector3.new(0.34 * bol + 0.06, 0.18 + 0.12 * bol, cs.Z * 0.96), pan * CFrame.new(sx * (w / 2 - 0.2), 0.04 + 0.04 * bol, 0.02), seatLook)
		if ins ~= "plain" then
			K:box("CushionStitch", Vector3.new(0.01, 0.01, cs.Z * 0.72), pan * CFrame.new(sx * (w * 0.25 + 0.01), 0.142, 0.04), P.stitch)
		end
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
	elseif ins == "hstitch" then
		for i = -2, 2 do
			K:box("BackStitch", Vector3.new(w * 0.48, 0.01, 0.008), backC * CFrame.new(0, -0.08 + i * H * 0.12, -0.186), P.stitch)
		end
	end
	for _, sx in { -1, 1 } do
		K:ell("BackBolster", Vector3.new(0.3 + 0.08 * bol, H * 0.82, 0.3 + 0.14 * bol), backC * CFrame.new(sx * (w / 2 - 0.2), -0.06, -0.06 - 0.05 * bol), seatLook)
		if ins ~= "plain" then
			K:box("BackStitch", Vector3.new(0.01, H * 0.66, 0.01), backC * CFrame.new(sx * (w * 0.25 + 0.01), -0.08, -0.185), P.stitch)
		end
	end
	K:ell("BackShoulder", Vector3.new(w - 0.2, 0.3, 0.34), backC * CFrame.new(0, H / 2 - 0.12, 0), seatLook)
	-- 뒤판 (등받이 뒤를 감싸는 둥근 판) + 맵포켓
	K:panel("BackPanel", w - 0.3, H * 0.84, 0.05, 0.16, backC * CFrame.new(0, -0.05, 0.17), P.hard)
	K:box("MapPocket", Vector3.new(w - 0.5, H * 0.3, 0.035), backC * CFrame.new(0, -H * 0.24, 0.205), P.hardDark)
	-- 안쪽 접이식 팔걸이 (쏠라티 운전석) / 캡틴 시트 양쪽 팔걸이 + 레그레스트 (카니발 2열)
	if st.armrest and not s.rear then
		K:rbox("SeatArmrest", Vector3.new(0.72, 0.16, 0.14), 0.06, CFrame.new(x - out * (w / 2 + 0.06), cushTop + 0.32, s.z + 0.05) * CFrame.Angles(0, math.pi / 2, 0), seatLook)
	end
	if st.captains and s.rear then
		for _, sx in { -1, 1 } do
			K:rbox("CaptainArmrest", Vector3.new(cs.Z * 0.8, 0.16, 0.18), 0.07, CFrame.new(x + sx * (w / 2 + 0.05), cushTop + 0.34, s.z + 0.1) * CFrame.Angles(0, math.pi / 2, 0), seatLook)
		end
		K:rbox("LegRest", Vector3.new(w * 0.62, 0.1, 0.5), 0.05, CFrame.new(x, cushTop - 0.32, s.z - cs.Z / 2 - 0.02) * CFrame.Angles(math.rad(80), 0, 0), seatLook)
	end

	-- 헤드레스트 -------------------------------------------------------------------------------------------
	local headTop = backC * CFrame.new(0, H / 2 + 0.08, 0.02)
	local hp: Vector3 = s.head or headTop.Position + Vector3.new(0, 0.32, 0)
	local hcf = CFrame.new(Vector3.new(x, math.max(hp.Y, headTop.Position.Y + 0.3), headTop.Position.Z + 0.02)) * CFrame.Angles(math.rad(13), 0, 0)
	K:rbox("Headrest", Vector3.new(0.92, 0.5, 0.26), 0.12, hcf, seatLook)
	K:ell("HeadrestPad", Vector3.new(0.78, 0.38, 0.16), hcf * CFrame.new(0, 0, -0.1), insertLook)
	if st.captains and s.rear then
		-- VIP 윙 헤드레스트 (양옆 날개)
		for _, sx in { -1, 1 } do
			K:ell("HeadrestWing", Vector3.new(0.16, 0.42, 0.3), hcf * CFrame.new(sx * 0.48, -0.02, -0.06) * CFrame.Angles(0, sx * math.rad(-20), 0), seatLook)
		end
	end
	for _, sx in { -0.22, 0.22 } do
		local a = (headTop * CFrame.new(sx, -0.06, 0)).Position
		local b = (hcf * CFrame.new(sx, -0.24, 0)).Position
		K:seg("HeadrestPost", a, b, 0.045, P.chrome)
	end

	-- 안전벨트 (B필러 트림 바로 앞을 따라 내려옴) + 버클 ---------------------------------------------------------------
	if s.inner then
		return -- 3인 벤치의 가운데 자리
	end
	local half: number = F.halfIn
	if not s.rear then
		local bz = F.bZ or (zR + 0.2)
		local lh: number = F.linerHalf or (half - 0.2)
		local y1: number = F.trimY1 or (F.floorY + 2.2)
		local ty = F.roofY - 0.55
		local tx = (half - 0.08) + (lh - half) * math.clamp((ty - y1) / math.max(0.01, F.roofY - y1), 0, 1) - 0.095
		local top = Vector3.new(out * tx, ty, bz)
		local low = Vector3.new(out * (half - 0.1), cushTop + 0.1, bz - 0.3)
		local v = top - low
		local zAxis = v.Unit
		local xAxis = (Vector3.xAxis - zAxis * Vector3.xAxis:Dot(zAxis)).Unit
		K:box("SeatBelt", Vector3.new(0.02, 0.17, v.Magnitude), CFrame.fromMatrix((top + low) / 2, xAxis, zAxis:Cross(xAxis), zAxis), P.belt)
		K:box("BeltAnchor", Vector3.new(0.04, 0.12, 0.22), CFrame.new(top), P.hardDark)
	end
	-- 버클: 콘솔 안에 묻히지 않게 좌석 쪽 콘솔 옆면으로
	local bkx, bky, bkz = x - out * (w / 2 + 0.06), cushTop + 0.05, zR - 0.2
	local con = F.console
	if con and bkz > con.z0 and bkz < con.z1 then
		local cw = math.min(con.w, 1.15)
		if math.abs(bkx - con.x) < cw / 2 + 0.05 then
			bkx = con.x + out * (cw / 2 - 0.05)
			bky = math.max(bky, con.top + 0.12)
		end
	end
	local buckle = CFrame.new(bkx, bky, bkz) * CFrame.Angles(math.rad(-20), 0, 0)
	K:box("Buckle", Vector3.new(0.09, 0.22, 0.06), buckle, P.hardDark)
	K:box("BuckleRelease", Vector3.new(0.06, 0.03, 0.02), buckle * CFrame.new(0, 0.08, -0.03), P.hazard)
end

local function rearBench(K: any, F: any, P: any, s: any)
	local cs: Vector3 = s.cushSize
	local W = cs.X
	local cushTop = s.cush.Y + cs.Y / 2
	local zR = s.z + cs.Z / 2
	local floor: number = F.floorY
	local ins: string = F.style.seat.insert
	local seatLook = if ins == "fabric" then P.fabricSide else P.leather
	local insertLook = if ins == "fabric" then P.fabricSeat else P.leatherInsert
	-- 받침
	local baseH = math.max(0.1, cushTop - 0.25 - floor)
	K:zbox("BenchBase", Vector3.new(W - 0.1, baseH, cs.Z * 0.85), math.min(0.08, baseH / 2 - 0.01), CFrame.new(s.x, floor + baseH / 2, s.z + 0.05), P.hardDark)
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
	local mid = hinge * CFrame.new(0, H * 0.32, 0)
	K:box("ArmrestSeam", Vector3.new(0.012, H * 0.5, 0.01), mid * CFrame.new(-0.3, 0, -0.125), P.hardDark)
	K:box("ArmrestSeam", Vector3.new(0.012, H * 0.5, 0.01), mid * CFrame.new(0.3, 0, -0.125), P.hardDark)
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
		if s.w > 2.0 then
			-- 트럭 조수석 2인 벤치: 두 자리로
			local hw = s.w / 2
			for _, dx in { -hw / 2, hw / 2 } do
				local p = table.clone(s)
				p.x, p.w, p.head = s.x + dx, hw, nil
				p.inner = math.abs(p.x) < math.abs(s.x)
				frontSeat(K, F, P, p)
			end
		else
			frontSeat(K, F, P, s)
		end
	end
	for _, s in F.rear do
		if s.w >= 2.6 then
			rearBench(K, F, P, s)
		else
			-- 카니발 2열 독립 시트 (캡틴 체어)
			local c = table.clone(s)
			c.rear = true
			frontSeat(K, F, P, c)
		end
	end
	return {}
end

Seats.REPLACES = { "SeatCushion", "SeatBack", "SeatInsert", "SeatPiping", "Headrest", "SeatBase", "SeatSupport", "RearBench" }

return Seats
