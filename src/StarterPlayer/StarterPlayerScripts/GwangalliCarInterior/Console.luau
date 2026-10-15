--!strict
-- GwangalliCarInterior/Console: 센터 콘솔 (차종별, Styles 참고). 긴 모서리가 둥근 몸체 + 가죽 옆판 + 스티치 + 앰비언트,
-- 모서리가 둥근 상판 · 무선 충전 패드, 변속기:
--   buttons_col  쏘나타: 운전석 쪽 크롬 링 P/R/N/D 세로열 + 손바닥 받침, 옆에 컵홀더
--   lever        쏘나타 택시 · 순찰차: 가죽 노브 6단 레버 + 부츠 + P R N D 표시
--   dial_wood    G80: 우드 패널 위 널링 크롬 변속 다이얼 + 그 뒤 터치 조그 다이얼 + 알루미늄 키, 덮개 컵홀더
--   buttons_row  투싼: P/R/N/D 버튼 가로 한 줄 + 새틴 가니시가 콘솔 양옆으로 이어짐
--   dial         카니발: 광택 판 위 널링 금속 링 다이얼 + 둘레 버튼
--   manual       포터: 바닥에서 올라온 긴 수동 레버 + 고무 부츠 + 검은 공 노브 (콘솔 없음)
-- 콘솔 없는 차(레이 워크스루): 스택 아래 낮은 트레이 + 컵홀더만. 대시 레버(레이) · 대시 포드(쏠라티)는 Dash.

local Console = {}

local ROT_X_TO_Y = CFrame.Angles(0, 0, math.pi / 2) -- 원통 축(X)을 위(+Y)로

-- 세로 널링 다이얼 (cf = 바닥 가운데, +Y 위)
local function vknurl(K: any, P: any, cf: CFrame, d: number, h: number, n: number, topLook: any)
	K:cyl("Dial", h, d, cf * CFrame.new(0, h / 2, 0) * ROT_X_TO_Y, P.alloy)
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		K:box("Knurl", Vector3.new(0.016, h * 0.84, 0.014), cf * CFrame.new(math.cos(a) * d / 2, h / 2, math.sin(a) * d / 2) * CFrame.Angles(0, -a, 0), P.chrome)
	end
	K:cyl("DialTop", 0.014, d * 0.84, cf * CFrame.new(0, h + 0.004, 0) * ROT_X_TO_Y, topLook)
end

-- 크롬 링 버튼 (위를 봄)
local function ringButton(K: any, P: any, cf: CFrame, d: number, lit: boolean)
	K:cyl("ShiftRing", 0.03, d, cf * ROT_X_TO_Y, P.chrome)
	K:cyl("ShiftButton", 0.04, d - 0.03, cf * CFrame.new(0, 0.012, 0) * ROT_X_TO_Y, if lit then P.buttonLit else P.button)
end

local function cupholders(K: any, P: any, x: number, y: number, z: number, along: boolean)
	for _, s in { -1, 1 } do
		local c = if along then CFrame.new(x, y, z + s * 0.17) else CFrame.new(x + s * 0.19, y, z)
		K:cyl("CupholderRing", 0.03, 0.31, c * ROT_X_TO_Y, P.chrome)
		K:cyl("Cupholder", 0.035, 0.27, c * CFrame.new(0, 0.005, 0) * ROT_X_TO_Y, P.duct)
	end
end

local function lowTray(K: any, F: any, P: any)
	-- 레이: 스택 발치 낮은 트레이 + 컵홀더 2 (사이 바닥은 비어 있음)
	local con = F.console
	local y = if con then con.top else F.floorY + 0.4
	local z = if con then math.max(con.z0, F.dashFace) + 0.32 else F.dashFace + 0.32
	local x = if con then con.x else 0
	K:zbox("LowTray", Vector3.new(0.72, 0.16, 0.5), 0.07, CFrame.new(x, y - 0.06, z), P.hard)
	cupholders(K, P, x, y + 0.03, z, false)
end

local function manualLever(K: any, F: any, P: any)
	-- 포터: 운전석과 가운데 자리 사이 바닥에서 올라온 긴 레버
	local toC = -F.side
	local seat = F.front[1]
	for _, s in F.front do
		if (s.x < 0) == (F.side < 0) then
			seat = s
		end
	end
	if not seat then
		return
	end
	local x = seat.x + toC * (math.min(seat.w, 1.85) / 2 + 0.2)
	local z = seat.z - seat.cushSize.Z / 2 - 0.3
	local floor: number = F.floorY
	local a = Vector3.new(x, floor + 0.08, z)
	local b = Vector3.new(x - toC * 0.06, floor + 1.25, z + 0.28)
	K:ell("ShiftBoot", Vector3.new(0.34, 0.26, 0.34), CFrame.new(a + Vector3.new(0, 0.06, 0)), P.rubber)
	K:ell("ShiftBootTop", Vector3.new(0.16, 0.14, 0.16), CFrame.new(a + Vector3.new(0, 0.2, 0.03)), P.rubber)
	K:seg("ShiftStick", a + Vector3.new(0, 0.2, 0.03), b, 0.05, P.metalDark)
	K:ball("ShiftKnob", 0.18, CFrame.new(b + Vector3.new(0, 0.05, 0.02)), P.hardDark)
	K:box("ShiftPattern", Vector3.new(0.09, 0.006, 0.07), CFrame.new(b + Vector3.new(0, 0.14, 0.02)), P.markWhite)
end

function Console.build(K: any, F: any, P: any)
	local S = F.style
	if S.console == "none" then
		if S.shifter == "manual" then
			manualLever(K, F, P)
		elseif F.console then
			lowTray(K, F, P)
		end
		return {}
	end
	local con = F.console
	if not con then
		return {}
	end
	local side = F.side
	local x: number = con.x
	local z0: number, z1: number = con.z0, con.z1
	local topY: number = con.top
	local w: number = math.min(con.w, 1.15)
	local floor: number = F.floorY
	local h = topY - floor
	local len = z1 - z0
	-- 몸체 (위 긴 모서리 둥글게) + 가죽 옆판 + 스티치 + 앰비언트
	K:zbox("ConsoleBody", Vector3.new(w - 0.1, h, len), 0.1, CFrame.new(x, floor + h / 2, (z0 + z1) / 2), P.hard)
	for _, s in { -1, 1 } do
		K:rbox("ConsoleSide", Vector3.new(len - 0.1, h * 0.62, 0.08), 0.035, CFrame.new(x + s * (w / 2 - 0.02), floor + h * 0.55, (z0 + z1) / 2) * CFrame.Angles(0, math.pi / 2, 0), P.soft)
		K:box("ConsoleStitch", Vector3.new(0.01, 0.01, len - 0.2), CFrame.new(x + s * (w / 2 + 0.022), floor + h * 0.84, (z0 + z1) / 2), P.stitch)
		if P.ambient then
			K:cyl("ConsoleAmbient", len * 0.5, 0.02, CFrame.new(x + s * (w / 2 + 0.02), topY - 0.05, z0 + len * 0.35) * CFrame.Angles(0, math.pi / 2, 0), P.ambient)
		end
	end
	-- 쓸 수 있는 상판: 대시 면 뒤 ~ 팔걸이 앞
	local arm = F.consoleArm
	local zU = math.max(z0, F.dashFace + 0.04)
	local zA: number = if arm then arm.z0 else z0 + len * 0.62
	local L = math.max(0.8, zA - zU)
	local deckMid = zU + L / 2
	K:slab("ConsoleDeck", w - 0.06, L, 0.04, 0.1, CFrame.new(x, topY + 0.02, deckMid), if S.shifter == "dial_wood" then P.soft else P.hard)
	-- 무선 충전 패드
	local pz = zU + 0.26
	K:slab("ChargePad", 0.6, 0.32, 0.025, 0.07, CFrame.new(x, topY + 0.045, pz), P.rubber)
	K:box("ChargeIcon", Vector3.new(0.05, 0.01, 0.07), CFrame.new(x, topY + 0.06, pz), P.markWhite)

	-- 변속기 ------------------------------------------------------------------------------------------
	local kind: string = S.shifter
	local top = topY + 0.04
	if kind == "buttons_col" then
		-- 쏘나타: 운전석 쪽 세로열 P R N D + 손바닥 받침 / 조수석 쪽 컵홀더 2 (앞뒤로)
		local gx = x + side * 0.2
		local gz = zU + L * 0.42
		K:slab("ShiftPanelRim", 0.31, 0.75, 0.025, 0.12, CFrame.new(gx, top - 0.004, gz), P.satin)
		K:slab("ShiftPanel", 0.27, 0.71, 0.03, 0.1, CFrame.new(gx, top, gz), P.gloss)
		local names = { "P", "R", "N", "D" }
		for i = 1, 4 do
			ringButton(K, P, CFrame.new(gx, top + 0.02, gz - 0.255 + (i - 1) * 0.17), 0.14, names[i] == "P")
		end
		K:ell("PalmRest", Vector3.new(0.28, 0.1, 0.34), CFrame.new(gx, top + 0.03, gz + 0.56), P.leather)
		cupholders(K, P, x - side * 0.19, top - 0.01, gz + 0.12, true)
		-- 주행 모드 · EPB · 오토홀드 (앞쪽 줄)
		local ry = gz - 0.48
		K:cyl("DriveMode", 0.06, 0.17, CFrame.new(x - side * 0.2, top + 0.03, ry) * ROT_X_TO_Y, P.satin)
		K:slab("EPB", 0.12, 0.17, 0.04, 0.03, CFrame.new(x + side * 0.02, top + 0.01, ry), P.button)
		K:slab("AutoHold", 0.12, 0.1, 0.04, 0.03, CFrame.new(x + side * 0.2, top + 0.01, ry), P.button)
	elseif kind == "lever" then
		-- 택시 · 순찰차: 6단 레버 (가죽 부츠 + 노브 + 시프트 락 버튼 + 게이트 표시)
		local gz = zU + L * 0.42
		local b = CFrame.new(x, top, gz)
		K:slab("GatePlate", 0.42, 0.6, 0.03, 0.12, b, P.gloss)
		for i = 0, 3 do
			K:box("GateMark", Vector3.new(0.04, 0.006, 0.03), b * CFrame.new(-0.15, 0.02, -0.19 + i * 0.12), P.markWhite)
		end
		K:ell("ShiftBoot", Vector3.new(0.26, 0.16, 0.3), b * CFrame.new(0.02, 0.04, 0), P.leather)
		K:seg("ShiftStick", b.Position + Vector3.new(0.02, 0.06, 0), b.Position + Vector3.new(0.02, 0.36, 0.04), 0.06, P.hard)
		K:ell("ShiftKnob", Vector3.new(0.17, 0.22, 0.21), b * CFrame.new(0.02, 0.43, 0.05), P.leather)
		K:cyl("ShiftKnobBand", 0.03, 0.17, b * CFrame.new(0.02, 0.36, 0.05) * ROT_X_TO_Y, P.chrome)
		K:box("ShiftLock", Vector3.new(0.05, 0.05, 0.05), b * CFrame.new(-0.06, 0.45, 0.04), P.satin)
		cupholders(K, P, x, top - 0.01, gz + 0.5, false)
		K:slab("EPB", 0.12, 0.17, 0.04, 0.03, CFrame.new(x + side * 0.2, top + 0.01, gz - 0.4), P.button)
		K:slab("AutoHold", 0.12, 0.1, 0.04, 0.03, CFrame.new(x - side * 0.2, top + 0.01, gz - 0.4), P.button)
	elseif kind == "dial_wood" then
		-- G80: 우드 인레이 + 크롬 변속 다이얼(앞) + 조그 다이얼(뒤), 알루미늄 키
		local gz = zU + L * 0.4
		K:slab("ConsoleWood", w - 0.18, L * 0.62, 0.02, 0.09, CFrame.new(x, top - 0.005, gz + 0.1), P.trim)
		vknurl(K, P, CFrame.new(x, top, gz), 0.27, 0.13, 14, P.gloss)
		K:cyl("ShiftDialRing", 0.02, 0.33, CFrame.new(x, top + 0.005, gz) * ROT_X_TO_Y, P.chrome)
		vknurl(K, P, CFrame.new(x, top, gz + 0.42), 0.23, 0.08, 12, P.screen)
		for _, k in { { -0.24, -0.08 }, { 0.24, -0.08 }, { -0.24, 0.16 }, { 0.24, 0.16 }, { -0.22, 0.42 }, { 0.22, 0.42 } } do
			K:slab("AluKey", 0.12, 0.07, 0.03, 0.025, CFrame.new(x + k[1], top + 0.01, gz + k[2]), P.alloy)
		end
		-- 덮개 컵홀더 (우드 슬라이딩 뚜껑)
		local cz = gz + 0.82
		K:slab("CupLid", w - 0.24, 0.42, 0.025, 0.08, CFrame.new(x, top + 0.005, cz), P.trim)
		K:box("CupLidSeam", Vector3.new(w - 0.3, 0.004, 0.006), CFrame.new(x, top + 0.02, cz - 0.15), P.hardDark)
	elseif kind == "buttons_row" then
		-- 투싼: 충전 트레이 뒤 P R N D 가로 한 줄 + EPB · 오토홀드 · 주행 모드, 컵홀더 2 나란히
		local gz = zU + L * 0.42
		K:slab("ShiftPanel", w - 0.22, 0.26, 0.03, 0.1, CFrame.new(x, top, gz), P.gloss)
		local names = { "P", "R", "N", "D" }
		for i = 1, 4 do
			ringButton(K, P, CFrame.new(x + (i - 2.5) * 0.17, top + 0.02, gz), 0.13, names[i] == "P")
		end
		for i, nm in { "EPB", "AutoHold", "DriveMode" } do
			K:slab(nm, 0.13, 0.08, 0.035, 0.03, CFrame.new(x + (i - 2) * 0.2, top + 0.01, gz + 0.24), P.button)
		end
		cupholders(K, P, x, top - 0.01, gz + 0.62, false)
		-- 대시에서 흘러내린 새틴 두 줄이 콘솔 위 양옆을 따라 뒤로
		for _, s in { -1, 1 } do
			K:cyl("Garnish", L - 0.1, 0.026, CFrame.new(x + s * (w / 2 - 0.035), topY + 0.04, deckMid) * CFrame.Angles(0, math.pi / 2, 0), P.trim)
		end
	else -- dial (카니발)
		local gz = zU + L * 0.42
		K:slab("DialPlate", w - 0.2, 0.62, 0.03, 0.14, CFrame.new(x, top, gz), P.gloss)
		vknurl(K, P, CFrame.new(x, top, gz), 0.26, 0.1, 14, P.gloss)
		K:cyl("DialP", 0.03, 0.08, CFrame.new(x, top + 0.115, gz) * ROT_X_TO_Y, P.satin)
		for _, k in { { -0.28, -0.18 }, { 0.28, -0.18 }, { -0.28, 0.0 }, { 0.28, 0.0 }, { -0.28, 0.18 }, { 0.28, 0.18 } } do
			K:slab("DialKey", 0.1, 0.1, 0.03, 0.03, CFrame.new(x + k[1], top + 0.015, gz + k[2]), P.button)
		end
		cupholders(K, P, x, top - 0.01, gz + 0.62, false)
	end

	-- 팔걸이 -------------------------------------------------------------------------------------------
	local a0: number = if arm then arm.z0 else z0 + len * 0.62
	local a1: number = if arm then arm.z1 else z1
	local aTop: number = if arm then arm.top else topY + 0.2
	local aw: number = if arm then math.min(arm.w, w) else w
	local alen = a1 - a0
	K:rbox("Armrest", Vector3.new(alen, 0.2, aw - 0.04), 0.09, CFrame.new(x, aTop - 0.1, (a0 + a1) / 2) * CFrame.Angles(0, math.pi / 2, 0), P.leather)
	K:ell("ArmrestPad", Vector3.new(aw - 0.14, 0.08, alen - 0.12), CFrame.new(x, aTop + 0.0, (a0 + a1) / 2), P.leather)
	for _, s in { -1, 1 } do
		K:box("ArmrestStitch", Vector3.new(0.01, 0.008, alen - 0.12), CFrame.new(x + s * aw * 0.3, aTop + 0.022, (a0 + a1) / 2), P.stitch)
	end
	-- 뒤쪽: 뒷좌석 송풍구 + USB
	if F.rear and #F.rear > 0 then
		local ventLook = { frame = P.satin, duct = P.duct, slat = P.hard, knob = P.satin }
		for _, s in { -1, 1 } do
			K:vent("RearVent", CFrame.new(x + s * 0.17, floor + h * 0.62, z1 + 0.02), 0.22, 0.12, ventLook, 2)
		end
		K:panel("RearUSB", 0.3, 0.06, 0.02, 0.025, CFrame.new(x, floor + h * 0.38, z1 + 0.01), P.gloss)
	end
	return {}
end

Console.REPLACES = { "CentreConsole", "ConsoleTray", "ConsoleWood", "Cupholder", "ConsoleArmrest", "GearDial", "JogDial", "ShiftBoot", "GearLever", "GearKnob", "GearGate", "ColumnShifter", "RotaryShifter", "Shifter", "ShiftKnob", "FloorConsole" }

return Console
