--!strict
-- GwangalliCarInterior/Trim: 도어 트림(앞·뒤 문마다: 모서리가 둥근 하단 · 중단(가죽 + 스티치) · 상단 패널, 차종별 가니시
-- (쏘나타 새틴 라인 · G80 우드 띠 · 투싼 새틴 두 줄 · 카니발 금속 띠), 앰비언트, 팔걸이 + 창문 스위치, IMS 메모리 버튼,
-- 손잡이 컵 + 캡슐형 크롬 핸들, 원형 스피커(보스 · 렉시콘 메탈 메쉬 · 크렐 배지), 맵포켓, 창틀 롤), B·C 필러 트림,
-- 헤드라이너 + 둥근 가장자리, 오버헤드 콘솔(맵램프 · SOS), 손잡이, 선바이저(화장 거울 커버), 룸미러(자동 감광),
-- 바닥 매트, 알루미늄 페달 + 고무 띠 + 풋레스트.

local Gauges = require(script.Parent:WaitForChild("Gauges"))

local Trim = {}

local function doorCard(K: any, F: any, P: any, side: number, z0: number, z1: number, front: boolean, driver: boolean, armDepth: number)
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
	local S = F.style
	local plastic = S.trimMat == "plastic" or S.garnish == "none"
	local lowH = (y1 - y0) * 0.42
	K:zbox("DoorLower", Vector3.new(0.1, lowH, len - 0.06), 0.045, CFrame.new(x, y0 + lowH / 2, zc), P.hard)
	local midY = y0 + lowH + 0.24
	K:zbox("DoorSoft", Vector3.new(0.09, 0.46, len - 0.2), 0.042, CFrame.new(x + inward * 0.03, midY, zc), P.doorSoft)
	if not plastic then
		K:box("DoorStitch", Vector3.new(0.01, 0.01, len - 0.3), CFrame.new(x + inward * 0.077, midY + 0.2, zc), P.stitch)
		K:box("DoorStitch", Vector3.new(0.01, 0.01, len - 0.3), CFrame.new(x + inward * 0.077, midY - 0.2, zc), P.stitch)
	end
	local upY0 = midY + 0.23
	local upH = y1 - upY0
	if upH > 0.05 then
		K:zbox("DoorUpper", Vector3.new(0.09, upH, len - 0.08), math.min(0.044, upH / 2 - 0.005), CFrame.new(x, upY0 + upH / 2, zc), P.soft)
	end
	K:cyl("DoorSill", len - 0.1, 0.14, CFrame.new(x + inward * 0.01, y1 - 0.02, zc) * CFrame.Angles(0, math.pi / 2, 0), P.soft)
	-- 대시에서 이어지는 가니시
	local AZ = CFrame.Angles(0, math.pi / 2, 0)
	local g: string = S.garnish
	-- 쏘나타: 대시의 새틴 라인 · 앰비언트와 같은 높이로 문까지 끊김 없이
	local lineY = if g == "line" then math.clamp((F.dashMidY :: number) + 0.1, upY0 + 0.06, y1 - 0.08) else upY0 + 0.1
	-- G80: 대시 우드 띠 가운데 높이 (Dash: sy = top - 0.2, wy = sy - 0.2)
	local woodY = math.clamp((F.dashTop :: number) - 0.4, upY0 + 0.12, math.max(upY0 + 0.12, y1 - 0.3))
	if g == "line" then
		K:cyl("DoorTrimBand", len - 0.4, 0.03, CFrame.new(x + inward * 0.06, lineY, zc) * AZ, P.trim)
	elseif g == "wood" then
		-- 우드 띠(0.24) + 위 크롬 립(송풍구 아래 립 높이)이 대시에서 문으로 끊김 없이
		K:zbox("DoorTrimBand", Vector3.new(0.05, 0.24, len - 0.4), 0.024, CFrame.new(x + inward * 0.05, woodY, zc), P.trim)
		K:cyl("DoorChrome", len - 0.42, 0.016, CFrame.new(x + inward * 0.07, woodY + 0.165, zc) * AZ, P.chrome)
	elseif g == "waterfall" then
		for i = 0, 1 do
			K:cyl("DoorTrimBand", len - 0.4, 0.026, CFrame.new(x + inward * 0.06, upY0 + 0.14 - i * 0.08, zc) * AZ, P.trim)
		end
	elseif g == "metal_wood" then
		K:zbox("DoorTrimBand", Vector3.new(0.04, 0.1, len - 0.4), 0.019, CFrame.new(x + inward * 0.05, upY0 + 0.1, zc), P.trim)
		K:zbox("DoorWood", Vector3.new(0.04, 0.08, len - 0.5), 0.019, CFrame.new(x + inward * 0.05, upY0 - 0.0, zc), P.wood)
	end
	if P.ambient then
		K:cyl("DoorAmbient", len - 0.6, 0.02, CFrame.new(x + inward * 0.07, if g == "line" then lineY - 0.045 elseif g == "wood" then woodY + 0.13 else upY0 + 0.03, zc) * AZ, P.ambient)
	end
	-- 문 가니시 띠의 아래 · 위 끝 (팔걸이 · 창문 스위치 · 손잡이 컵 · IMS 가 띠를 뚫지 않게)
	local bandLo, bandHi = math.huge, -math.huge
	if g == "line" then
		bandLo, bandHi = lineY - 0.06, lineY + 0.02 -- 새틴 라인 + 바로 아래 앰비언트
	elseif g == "wood" then
		bandLo, bandHi = woodY - 0.12, woodY + 0.18 -- 우드 띠 + 위 크롬 · 앰비언트
	elseif g == "waterfall" then
		bandLo, bandHi = upY0 + 0.02, upY0 + 0.155 -- 앰비언트 + 새틴 두 줄
	elseif g == "metal_wood" then
		bandLo, bandHi = upY0 - 0.04, upY0 + 0.15 -- 우드 + 금속 띠
	end
	-- 팔걸이 + 창문 스위치
	-- 팔걸이: 그 문 쪽 좌석 쿠션 위 0.5 (팔꿈치 높이). 팔걸이 밑(-0.075) ~ 스위치 윗면(+0.11)이 띠와 겹치면 띠 바로 아래로
	local cushTop = y0 + lowH
	for _, s in (if front then F.front else F.rear) do
		if s.w >= 2.6 or (s.x < 0) == (side < 0) then
			cushTop = s.cush.Y + s.cushSize.Y / 2
		end
	end
	local armMin = y0 + lowH + 0.02
	local armY = math.clamp(cushTop + 0.5, armMin, math.max(armMin, y1 - 0.62))
	if armY + 0.11 > bandLo and armY - 0.075 < bandHi then
		armY = math.max(armMin, bandLo - 0.13)
	end
	local armZ = zc + len * 0.08
	K:rbox("DoorArmrest", Vector3.new(len * 0.55, 0.13, armDepth), 0.06, CFrame.new(x + inward * (0.02 + armDepth / 2), armY, armZ) * CFrame.Angles(0, math.pi / 2, 0), P.leather)
	local sw = CFrame.new(x + inward * (0.02 + armDepth / 2), armY + 0.075, armZ - len * 0.14)
	K:slab("WindowSwitches", 0.2, if driver then 0.5 else 0.22, 0.025, 0.06, sw, P.gloss)
	for i = 0, (if driver then 3 else 0) do
		K:box("WindowSwitch", Vector3.new(0.08, 0.03, 0.07), sw * CFrame.new(0, 0.02, (if driver then -0.16 else 0) + i * 0.105), P.button)
	end
	-- 손잡이 컵 + 크롬 핸들 (문 앞쪽)
	local hz = if front then math.max(z0 + 0.42, (F.dashFace :: number) + 0.35) else z0 + 0.42
	local hy = armY + 0.45
	if armY < bandLo then
		-- 팔걸이가 띠 아래면 손잡이 컵(±0.09)과 IMS 가 띠 위에 오게
		hy = math.max(hy, bandHi + (if g == "line" then 0.11 else 0.18))
	end
	hy = math.min(hy, y1 - 0.2) -- 창틀 롤(DoorSill) 아래
	K:ell("HandleCup", Vector3.new(0.06, 0.18, 0.46), CFrame.new(x + inward * 0.055, hy, hz), P.duct)
	K:capsule("DoorHandle", Vector3.new(x + inward * 0.085, hy + 0.01, hz - 0.14), Vector3.new(x + inward * 0.085, hy + 0.01, hz + 0.14), 0.05, P.chrome)
	K:box("LockTab", Vector3.new(0.05, 0.05, 0.08), CFrame.new(x + inward * 0.09, hy, hz + 0.27), P.button)
	-- IMS 시트 메모리 (1 · 2 · SET, 운전석 문)
	if driver and (S.key == "sonata" or S.key == "g80") then
		for i = 0, 2 do
			K:box("ImsButton", Vector3.new(0.03, 0.045, 0.07), CFrame.new(x + inward * 0.08, if g == "line" then hy - 0.24 else hy - 0.14, hz - 0.1 + i * 0.09), P.alloy)
		end
	end
	if plastic then
		-- 상용차: 크게 성형된 당김 손잡이
		K:zbox("PullGrip", Vector3.new(0.12, 0.1, 0.5), 0.045, CFrame.new(x + inward * 0.1, armY + 0.2, armZ), P.hard)
	end
	-- 원형 스피커 (문 아래 앞쪽): 보스 / 렉시콘 메탈 메쉬 / 크렐 배지 / 일반 + 맵포켓
	-- 앞문 스피커는 대시 뒤 문 앞쪽 아래 (조수석 발밑으로 나가지 않게)
	local spz = if front and not plastic then math.max(z0 + 0.5, (F.dashFace :: number) + 0.38) else z0 + 0.5
	local sp = CFrame.new(x + inward * 0.06, y0 + lowH * 0.6, spz)
	local spk: string = S.speaker
	K:cyl("SpeakerRing", 0.03, 0.6, sp, if spk == "plain" then P.hard else P.chrome)
	K:cyl("SpeakerGrille", 0.035, 0.54, sp * CFrame.new(inward * 0.005, 0, 0), if spk == "lexicon" then P.mesh else P.grille)
	if spk ~= "plain" then
		K:slab("SpeakerBadge", 0.03, 0.12, 0.012, 0.01, sp * CFrame.new(inward * 0.026, -0.2, 0) * CFrame.Angles(0, 0, math.pi / 2), P.satin)
	end
	K:zbox("MapPocket", Vector3.new(0.13, 0.22, len * 0.45), 0.05, CFrame.new(x + inward * 0.07, y0 + 0.2, zc + len * 0.12), P.hardDark)
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
	local lh: number = F.linerHalf or (half - 0.2)
	-- 도어 팔걸이 깊이: 앞좌석 옆면과 겹치지 않게 (레이처럼 좁은 차)
	local outerSeat = 0
	for _, s in F.front do
		outerSeat = math.max(outerSeat, math.abs(s.x) + math.min(s.w, 1.85) / 2 + 0.06)
	end
	local armDepth = math.clamp(half - outerSeat - 0.02, 0.15, 0.36)
	for _, side in { -1, 1 } do
		local driver = side == F.side
		if split then
			doorCard(K, F, P, side, z0 + 0.05, split - 0.08, true, driver, armDepth)
			if not commercial then
				doorCard(K, F, P, side, split + 0.08, z1 - 0.05, false, false, armDepth)
			end
			-- B필러 트림 (창틀에서 지붕 안쪽까지 기울어짐)
			local y1: number = F.trimY1 or (F.floorY + 2.2)
			if F.roofY - y1 > 0.2 then
				K:seg("BPillarTrim", Vector3.new(side * (half - 0.08), y1, split), Vector3.new(side * (lh - 0.08), F.roofY, split), 0.16, P.fabric)
			end
		else
			doorCard(K, F, P, side, z0 + 0.05, z1 - 0.05, true, driver, armDepth)
		end
	end

	-- 헤드라이너 + 둥근 가장자리 + 오버헤드 콘솔 ----------------------------------------------------------------
	local roofY: number = F.roofY
	local lz0: number = F.linerZ0 or (F.wsHigh :: Vector3).Z
	local lz1: number = F.linerZ1 or z1
	local llen = lz1 - lz0
	if llen > 0.5 then
		K:box("Headliner", Vector3.new(lh * 2, 0.06, llen), CFrame.new(0, roofY + 0.02, (lz0 + lz1) / 2), P.fabric)
		for _, s in { -1, 1 } do
			K:cyl("HeadlinerEdge", llen, 0.24, CFrame.new(s * (lh - 0.12), roofY - 0.02, (lz0 + lz1) / 2) * CFrame.Angles(0, math.pi / 2, 0), P.fabric)
		end
		local ocz = lz0 + 0.45
		local mz: number = if F.mirror then (F.mirror :: Vector3).Z else (F.wsHigh :: Vector3).Z + 0.35
		if F.cabRoof and math.abs(ocz - mz) < 0.45 then
			ocz = mz + 0.5 -- 짧은 캡 천장(쏠라티): 콘솔이 룸미러 · 미러 기둥을 삼키지 않게 뒤로
		end
		local oc = CFrame.new(0, roofY - 0.06, ocz)
		if F.style.key ~= "porter" then -- 포터: 오버헤드 콘솔 · 맵램프 · SOS 없음 (지붕 가운데 실내등 하나)
			-- 아래에서 보면 네 모서리가 둥근 판 + 면에 묻힌 타원 렌즈 · 둥근 SOS (튀어나온 흰 타일 X)
			K:slab("OverheadConsole", 0.78, 0.5, 0.12, 0.16, oc, P.hard)
			for _, s in { -1, 1 } do
				K:ell("MapLamp", Vector3.new(0.2, 0.024, 0.13), oc * CFrame.new(s * 0.22, -0.06, 0.02), P.lampLens)
			end
			K:cyl("SOS", 0.016, 0.065, oc * CFrame.new(0, -0.064, 0.15) * CFrame.Angles(0, 0, math.pi / 2), P.hazard)
			K:box("RoofSwitch", Vector3.new(0.14, 0.02, 0.06), oc * CFrame.new(0, -0.065, -0.12), P.button)
		end
		if F.style.key == "carnival" then
			-- 파워 슬라이딩 도어 좌 · 우 + 파워 테일게이트 (맵램프 앞 · 사이)
			for _, s in { -1, 1 } do
				K:box("SlideDoorSwitch", Vector3.new(0.1, 0.02, 0.07), oc * CFrame.new(s * 0.24, -0.065, -0.16), P.button)
			end
			K:box("TailgateSwitch", Vector3.new(0.1, 0.02, 0.07), oc * CFrame.new(0, -0.065, 0.04), P.button)
		end
		-- 실내등 (뒤)
		-- 실내등: 오버헤드 콘솔 뒤 (짧은 캡 천장에서 콘솔이 뒤로 밀리면 실내등도 그 뒤로, 천장 끝 안쪽)
		local dlz = math.min(math.max(lz0 + llen * 0.6, ocz + 0.45), lz1 - 0.15)
		local dl = CFrame.new(0, roofY - 0.01, dlz)
		if F.style.key == "porter" then
			-- 포터: 회색 사각 하우징 + 렌즈 + 3단 스위치
			K:rbox("DomeHousing", Vector3.new(0.56, 0.05, 0.32), 0.022, dl * CFrame.new(0, -0.005, 0), P.hard)
			dl = dl * CFrame.new(0, -0.03, -0.03)
			K:box("RoofSwitch", Vector3.new(0.1, 0.02, 0.04), dl * CFrame.new(0, 0, 0.13), P.button)
		end
		K:box("DomeLamp", Vector3.new(0.4, 0.02, 0.2), dl, P.lampLens)
		-- 손잡이 (조수석 + 뒤 양쪽)
		local grabs = if F.cabRoof then { { -F.side, lz0 + 0.9 } } else { { -F.side, lz0 + 0.9 }, { -1, lz0 + llen * 0.7 }, { 1, lz0 + llen * 0.7 } }
		for _, g in grabs do
			local gx = g[1] * (lh - 0.1)
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
		if F.style.key ~= "porter" then -- 포터: 비닐 바이저 (화장 거울 덮개 없음)
			K:box("VanityCover", Vector3.new(0.5, 0.012, 0.26), v * CFrame.new(-s * 0.1, -0.035, 0.04), P.pillar)
		end
		K:cyl("VisorRod", 0.4, 0.04, v * CFrame.new(s * 0.62, 0.0, -0.22) * CFrame.Angles(0, math.pi / 2, 0), P.hard)
	end
	local mp: Vector3 = F.mirror or Vector3.new(0, roofY - 0.3, hi.Z + 0.35)
	-- 운전자 쪽으로 살짝 돌리고 아래로 숙임
	local mcf = CFrame.new(mp) * CFrame.Angles(math.rad(6), math.rad(15) * F.side, 0)
	K:seg("MirrorStem", Vector3.new(mp.X, roofY + 0.02, hi.Z + 0.05), mp + Vector3.new(0, 0.08, -0.04), 0.06, P.hardDark)
	K:rbox("MirrorBody", Vector3.new(0.86, 0.25, 0.1), 0.06, mcf, P.hardDark)
	K:box("MirrorGlass", Vector3.new(0.78, 0.18, 0.01), mcf * CFrame.new(0, 0, 0.055), P.mirror)
	-- 개인택시 룸미러 일체형 미터기 (순찰차 제외): 거울 조수석 쪽 절반에 빨간 LED 요금 + 초록 상태등,
	-- 거울 아래 가장자리에 빈차 · 주행 · 할증 · 지불 버튼
	if F.style.key == "sonata_taxi" and F.kind ~= "police" then
		local mm = mcf * CFrame.new(-F.side * 0.17, -0.025, 0.062)
		K:box("MeterWindow", Vector3.new(0.32, 0.1, 0.004), mm, P.meterGlass)
		Gauges.digits(K, mm * CFrame.new(-F.side * 0.03, 0, 0.004), 4, 0.06, P.ledRed, "4800")
		K:box("MeterLed", Vector3.new(0.03, 0.03, 0.006), mm * CFrame.new(F.side * 0.12, 0, 0.004), P.ledGreen)
		for i = 0, 3 do
			K:box("MeterKey", Vector3.new(0.07, 0.025, 0.05), mcf * CFrame.new(-0.27 + i * 0.18, -0.13, 0.02), P.button)
		end
	end

	-- 바닥 카펫(실내 전체, 어두운 니들펠트) + 매트 + 페달 ------------------------------------------------------
	local floor: number = F.floorY
	local fz0: number = F.dashFace - 0.05
	local fz1: number = F.doorZ1
	local porter = F.style.key == "porter"
	if fz1 - fz0 > 0.5 then
		K:box("CabinCarpet", Vector3.new(half * 2 - 0.06, 0.04, fz1 - fz0), CFrame.new(0, floor + 0.005, (fz0 + fz1) / 2), if porter then P.rubber else P.carpet)
	end
	do
		-- 대시 아래 발 공간: 앞벽(토보드)까지 바닥 + 양옆 킥 패널 (원래 카펫은 숨겨져 있어 그대로면 땅이 보임,
		-- 포터처럼 문이 대시 면에서 시작하는 캡오버는 옆도 뚫려 보임). 포터는 고무 바닥
		local zf: number = F.dashFront + 0.04
		local th: number = F.dashBottom - floor
		if fz0 - zf > 0.05 then
			K:box("ToeFloor", Vector3.new(half * 2 - 0.06, 0.04, fz0 - zf), CFrame.new(0, floor + 0.005, (zf + fz0) / 2), if porter then P.rubber else P.carpet)
		end
		if th > 0.1 then
			K:box("ToeBoard", Vector3.new(half * 2 - 0.06, th, 0.06), CFrame.new(0, floor + th / 2, zf + 0.03), if porter then P.hardDark else P.carpet)
			local kz1: number = math.max(zf + 0.2, (F.doorZ0 :: number) + 0.1)
			local kh = th + 0.08
			for _, sx in { -1, 1 } do
				K:zbox("KickPanel", Vector3.new(0.06, kh, kz1 - zf), 0.025, CFrame.new(sx * (half - 0.05), floor + kh / 2, (zf + kz1) / 2), P.lower)
			end
		end
	end
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
	-- 좌핸들 기준 바깥 -> 안쪽: (클러치) · 브레이크 · 가속. 페달 파트가 없는 차(포터 · 쏠라티)는 운전석 앞에 만듦
	if #ped == 0 then
		local wx = F.wheel.c.X
		local pz = F.dashFace + 0.25
		local py = F.floorY + 0.38
		if F.style.shifter == "manual" or F.style.shifter == "dash_pod" then
			table.insert(ped, Vector3.new(wx + F.side * 0.38, py, pz))
		end
		table.insert(ped, Vector3.new(wx, py, pz))
		table.insert(ped, Vector3.new(wx - F.side * 0.4, py, pz))
	end
	local gas, brake = ped[#ped], ped[#ped - 1]
	-- 상용차(포터 · 쏠라티, trimMat = "plastic"): 검은 고무 패드, 알루미늄 스포츠 페달 · 고무 띠 없음
	local sport = F.style.trimMat ~= "plastic"
	local pad = if sport then P.alloy else P.rubber
	for i = 1, #ped - 2 do
		-- 클러치: 브레이크와 같은 패드
		local c = CFrame.new(ped[i]) * CFrame.Angles(math.rad(-25), 0, 0)
		K:panel("ClutchPedal", 0.36, 0.28, 0.04, 0.08, c, pad)
		K:seg("PedalArm", ped[i] + Vector3.new(0, 0.1, -0.05), ped[i] + Vector3.new(0, 0.62, -0.32), 0.05, P.metalDark)
	end
	if brake then
		local c = CFrame.new(brake) * CFrame.Angles(math.rad(-25), 0, 0)
		K:panel("BrakePedal", 0.44, 0.3, 0.04, 0.08, c, pad)
		for i = -1, (if sport then 1 else -2) do
			K:box("PedalRubber", Vector3.new(0.36, 0.035, 0.02), c * CFrame.new(0, i * 0.08, 0.025), P.rubber)
		end
		K:seg("PedalArm", brake + Vector3.new(0, 0.1, -0.05), brake + Vector3.new(0, 0.62, -0.32), 0.05, P.metalDark)
		-- 풋레스트: 수동(클러치 있음)은 그 자리에 클러치 페달이 있어 생략 (겹침)
		if #ped < 3 then
			local fx = brake.X + F.side * 0.55
			K:panel("FootRest", 0.3, 0.5, 0.04, 0.08, CFrame.new(fx, floor + 0.35, brake.Z - 0.1) * CFrame.Angles(math.rad(-40), 0, 0), P.alloy)
		end
	end
	if F.style.key == "ray" and brake then
		-- 레이: 발 주차 브레이크 (핸드브레이크 없음) - 풋레스트 위, 대시 아래 왼쪽 끝
		local pb = brake + Vector3.new(F.side * 0.55, 0.06, -0.08) -- 브레이크 왼쪽, 대시 아랫면 밑
		K:panel("ParkBrakePedal", 0.22, 0.15, 0.04, 0.05, CFrame.new(pb) * CFrame.Angles(math.rad(-30), 0, 0), P.rubber)
		K:seg("PedalArm", pb + Vector3.new(0, 0.06, -0.04), pb + Vector3.new(0, 0.45, -0.32), 0.045, P.metalDark)
	end
	if gas then
		local c = CFrame.new(gas + Vector3.new(0, -0.05, 0)) * CFrame.Angles(math.rad(-35), 0, 0)
		K:panel("GasPedal", 0.26, 0.6, 0.04, 0.07, c, pad)
		for i = -2, (if sport then 2 else -3) do
			K:box("PedalRubber", Vector3.new(0.035, 0.5, 0.02), c * CFrame.new(i * 0.05, 0, 0.025), P.rubber)
		end
	end
	if F.style.key == "solati" then
		-- 119 격벽 (운전석 쪽 면 = doorZ1 + 0.05): 가운데 작은 미닫이 창 (회색 틀 + 어두운 유리 + 가운데 창살 + 걸쇠)
		local wc = CFrame.new(0, F.roofY - 1.18, F.doorZ1 + 0.03)
		K:panel("PartitionWindowFrame", 1.3, 0.72, 0.04, 0.12, wc, P.hard)
		K:panel("PartitionWindowGlass", 1.18, 0.6, 0.01, 0.08, wc * CFrame.new(0, 0, -0.025), P.screen)
		K:box("PartitionWindowMullion", Vector3.new(0.04, 0.6, 0.02), wc * CFrame.new(0.05, 0, -0.035), P.hard)
		K:box("PartitionWindowLatch", Vector3.new(0.05, 0.09, 0.025), wc * CFrame.new(0.12, 0, -0.04), P.satin)
	end
	return {}
end

Trim.REPLACES = { "DoorTrim", "DoorTrimUpper", "Armrest", "AmbientDoor", "SpeakerGrille", "Headliner", "SunVisor", "RearViewMirror", "Pedal", "FloorMat", "Carpet", "CabCarpet" }

return Trim
