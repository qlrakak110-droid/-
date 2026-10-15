--!strict
-- GwangalliCarInterior/Console: 센터 콘솔. 가죽 옆판 + 스티치, 피아노 블랙 상판, 변속기(쏘나타·택시: 버튼식
-- P/R/N/D, 제네시스: 크롬 다이얼 + 조그 다이얼, SUV·밴·소형·트럭: 가죽 부츠 레버), 주행 모드 다이얼, 전자식
-- 주차 브레이크 · 오토홀드, 무선 충전 패드, 컵홀더 2 (크롬 링), 팔걸이 (둥근 가죽 + 스티치), 뒷좌석 송풍구.

local Console = {}

local ROT_X_TO_Y = CFrame.Angles(0, 0, math.pi / 2) -- 원통 축(X)을 위(+Y)로

function Console.build(K: any, F: any, P: any)
	local con = F.console
	if not con then
		return {}
	end
	local x: number = con.x
	local z0: number, z1: number = con.z0, con.z1
	local topY: number = con.top
	local w: number = math.min(con.w, 1.15)
	local floor: number = F.floorY
	local h = topY - floor
	local len = z1 - z0
	-- 몸체 + 옆판
	K:box("ConsoleBody", Vector3.new(w - 0.1, h, len), CFrame.new(x, floor + h / 2, (z0 + z1) / 2), P.hard)
	for _, s in { -1, 1 } do
		K:rbox("ConsoleSide", Vector3.new(len - 0.1, h * 0.62, 0.08), 0.03, CFrame.new(x + s * (w / 2 - 0.02), floor + h * 0.55, (z0 + z1) / 2) * CFrame.Angles(0, math.pi / 2, 0), P.soft)
		K:box("ConsoleStitch", Vector3.new(0.01, 0.01, len - 0.2), CFrame.new(x + s * (w / 2 + 0.022), floor + h * 0.84, (z0 + z1) / 2), P.stitch)
		K:box("ConsoleAmbient", Vector3.new(0.012, 0.02, len * 0.55), CFrame.new(x + s * (w / 2 + 0.02), topY - 0.05, z0 + len * 0.33), P.ambient)
	end
	-- 상판 (앞쪽 60 %): 피아노 블랙 + 은색 테두리
	local deckLen = len * 0.58
	local dz = z0 + deckLen / 2
	K:box("ConsoleDeck", Vector3.new(w - 0.06, 0.04, deckLen), CFrame.new(x, topY + 0.02, dz), P.gloss)
	K:box("DeckEdge", Vector3.new(w - 0.02, 0.025, 0.03), CFrame.new(x, topY + 0.03, z0 + 0.02), P.satin)

	-- 변속기 -------------------------------------------------------------------------------------------
	local gz = z0 + deckLen * 0.42
	local gx = x - F.side * 0.12
	if F.rotary or F.kind == "luxury" then
		local d = CFrame.new(gx, topY + 0.08, gz)
		K:cyl("ShiftDialRing", 0.05, 0.38, d * ROT_X_TO_Y, P.satin)
		K:cyl("ShiftDial", 0.14, 0.3, d * CFrame.new(0, 0.07, 0) * ROT_X_TO_Y, P.chrome)
		K:cyl("ShiftDialTop", 0.02, 0.24, d * CFrame.new(0, 0.145, 0) * ROT_X_TO_Y, P.gloss)
		K:cyl("JogDial", 0.08, 0.22, CFrame.new(gx, topY + 0.07, gz + 0.42) * ROT_X_TO_Y, P.chrome)
	elseif F.lever or F.kind == "suv" or F.kind == "van" or F.kind == "compact" or F.kind == "truck" or F.kind == "ambulance" then
		local b = CFrame.new(gx, topY + 0.04, gz)
		K:ell("ShiftBoot", Vector3.new(0.3, 0.16, 0.32), b, P.leather)
		K:seg("ShiftStick", b.Position, b.Position + Vector3.new(0, 0.32, 0.03), 0.06, P.hard)
		K:ell("ShiftKnob", Vector3.new(0.17, 0.2, 0.2), b * CFrame.new(0, 0.38, 0.03), P.leather)
		K:ell("ShiftKnobTop", Vector3.new(0.12, 0.03, 0.14), b * CFrame.new(0, 0.47, 0.03), P.chrome)
	else
		-- 버튼식 변속 (쏘나타 DN8): 세로로 P R N D
		local b = CFrame.new(gx, topY + 0.05, gz)
		K:box("ShiftPanel", Vector3.new(0.3, 0.05, 0.6), b, P.satin)
		local names = { "P", "R", "N", "D" }
		for i = 1, 4 do
			K:box("ShiftButton" .. names[i], Vector3.new(0.22, 0.05, 0.11), b * CFrame.new(0, 0.035, -0.24 + (i - 1) * 0.16), if i == 1 then P.buttonLit else P.button)
		end
	end
	-- 주행 모드 다이얼 · 주차 브레이크 · 오토홀드
	local mx = x + F.side * 0.2
	K:cyl("DriveMode", 0.06, 0.17, CFrame.new(mx, topY + 0.06, gz) * ROT_X_TO_Y, P.satin)
	K:box("EPB", Vector3.new(0.1, 0.04, 0.16), CFrame.new(mx, topY + 0.045, gz + 0.24), P.button)
	K:box("AutoHold", Vector3.new(0.1, 0.04, 0.1), CFrame.new(mx, topY + 0.045, gz + 0.42), P.button)
	-- 무선 충전 패드
	local pz = z0 + 0.22
	K:box("ChargePad", Vector3.new(0.62, 0.025, 0.32), CFrame.new(x, topY + 0.035, pz), P.rubber)
	K:box("ChargeIcon", Vector3.new(0.05, 0.01, 0.07), CFrame.new(x, topY + 0.05, pz), P.ambient)
	-- 컵홀더 2
	local cz = z0 + deckLen * 0.85
	for _, s in { -1, 1 } do
		local c = CFrame.new(x + s * 0.2, topY + 0.03, cz)
		K:cyl("CupholderRing", 0.03, 0.31, c * ROT_X_TO_Y, P.chrome)
		K:cyl("Cupholder", 0.035, 0.27, c * CFrame.new(0, 0.005, 0) * ROT_X_TO_Y, P.duct)
	end

	-- 팔걸이 -------------------------------------------------------------------------------------------
	local arm = F.consoleArm
	local a0: number = if arm then arm.z0 else z0 + len * 0.62
	local a1: number = if arm then arm.z1 else z1
	local aTop: number = if arm then arm.top else topY + 0.2
	local aw: number = if arm then math.min(arm.w, w) else w
	local alen = a1 - a0
	K:rbox("Armrest", Vector3.new(alen, 0.2, aw - 0.04), 0.09, CFrame.new(x, aTop - 0.1, (a0 + a1) / 2) * CFrame.Angles(0, math.pi / 2, 0), P.leather)
	K:box("ArmrestStitch", Vector3.new(0.01, 0.008, alen - 0.12), CFrame.new(x - aw * 0.3, aTop + 0.002, (a0 + a1) / 2), P.stitch)
	K:box("ArmrestStitch", Vector3.new(0.01, 0.008, alen - 0.12), CFrame.new(x + aw * 0.3, aTop + 0.002, (a0 + a1) / 2), P.stitch)
	-- 뒤쪽: 뒷좌석 송풍구 + USB
	if F.rear and #F.rear > 0 then
		local ventLook = { frame = P.satin, duct = P.duct, slat = P.hard, knob = P.satin }
		for _, s in { -1, 1 } do
			K:vent("RearVent", CFrame.new(x + s * 0.17, floor + h * 0.62, z1 + 0.01) * CFrame.Angles(0, 0, 0), 0.22, 0.12, ventLook, 2)
		end
		K:box("RearUSB", Vector3.new(0.3, 0.06, 0.02), CFrame.new(x, floor + h * 0.38, z1 + 0.01), P.gloss)
	end
	return {}
end

Console.REPLACES = { "CentreConsole", "ConsoleTray", "ConsoleWood", "Cupholder", "ConsoleArmrest", "GearDial", "JogDial", "ShiftBoot", "GearLever", "GearKnob", "GearGate", "ColumnShifter", "RotaryShifter", "Shifter", "ShiftKnob", "FloorConsole" }

return Console
