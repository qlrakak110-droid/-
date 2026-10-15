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
	-- 얕고 촘촘한 널링 (톱니바퀴처럼 보이지 않게)
	local tw = math.min(0.014, math.pi * d / n * 0.45)
	local rr = d / 2 - 0.001
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		K:box("Knurl", Vector3.new(0.01, h * 0.84, tw), cf * CFrame.new(math.cos(a) * rr, h / 2, math.sin(a) * rr) * CFrame.Angles(0, -a, 0), P.chrome)
	end
	K:cyl("DialTop", 0.014, d * 0.84, cf * CFrame.new(0, h + 0.004, 0) * ROT_X_TO_Y, topLook)
end

-- 크롬 링 버튼 (위를 봄)
local function ringButton(K: any, P: any, cf: CFrame, d: number, lit: boolean)
	K:cyl("ShiftRing", 0.03, d, cf * ROT_X_TO_Y, P.chrome)
	K:cyl("ShiftButton", 0.04, d - 0.03, cf * CFrame.new(0, 0.012, 0) * ROT_X_TO_Y, P.button)
	if lit then
		-- 선택된 단: 버튼 전체가 아니라 앞쪽 작은 표시등만
		K:box("ShiftLed", Vector3.new(0.03, 0.006, 0.018), cf * CFrame.new(0, 0.033, -(d / 2 - 0.035)), P.buttonLit)
	end
end

local function cupholders(K: any, P: any, x: number, y: number, z: number, along: boolean)
	for _, s in { -1, 1 } do
		local c = if along then CFrame.new(x, y, z + s * 0.17) else CFrame.new(x + s * 0.19, y, z)
		-- 어두운 테두리 + 얇은 새틴 립 + 검은 안쪽 (밝은 크롬 원판은 위에서 보면 하얀 핫플레이트처럼 보임)
		K:cyl("CupholderRing", 0.03, 0.31, c * ROT_X_TO_Y, P.hardDark)
		K:cyl("CupholderLip", 0.033, 0.287, c * CFrame.new(0, 0.002, 0) * ROT_X_TO_Y, P.satin)
		K:cyl("Cupholder", 0.035, 0.265, c * CFrame.new(0, 0.005, 0) * ROT_X_TO_Y, P.duct)
	end
end

local function lowTray(K: any, F: any, P: any)
	-- 레이: 스택 발치 낮은 트레이 + 컵홀더 2 (사이 바닥은 비어 있음)
	local con = F.console
	local y = if con then con.top else F.floorY + 0.4
	-- 레이: 트레이 앞 끝을 StackFoot 뒤 면(dashFace + 0.17)에 붙임
	local z = if F.style.key == "ray" then F.dashFace + 0.42 elseif con then math.max(con.z0, F.dashFace) + 0.32 else F.dashFace + 0.32
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
	local a = Vector3.new(x, floor + 0.04, z)
	local b = Vector3.new(x - toC * 0.06, floor + 1.25, z + 0.28)
	local dir = (b - a).Unit
	-- 바닥 트림판(위에서 보면 둥근 사각) + 아래가 넓은 4단 주름 고무 부츠 + 긴 검은 레버 + 서양배 노브
	K:slab("ShiftPlate", 0.46, 0.46, 0.03, 0.1, CFrame.new(a.X, floor + 0.03, a.Z), P.hardDark)
	for i = 0, 3 do
		local d = 0.36 - i * 0.065
		K:ell("ShiftBoot", Vector3.new(d, 0.11, d), CFrame.new(a + dir * (0.05 + i * 0.085)), P.rubber)
	end
	K:seg("ShiftStick", a + dir * 0.3, b, 0.045, P.metalDark)
	local kc = b + Vector3.new(0, 0.06, 0.02)
	K:ell("ShiftKnob", Vector3.new(0.17, 0.2, 0.18), CFrame.new(kc), P.hardDark)
	-- 노브 위 5단 무늬: 작은 광택 원판 + 가는 회색 선 4 (빛나는 흰 사각형 대신)
	local cap = CFrame.new(kc + Vector3.new(0, 0.094, 0))
	K:cyl("ShiftCap", 0.012, 0.08, cap * CFrame.Angles(0, 0, math.pi / 2), P.gloss)
	local ink = { c = Color3.fromRGB(170, 174, 180), m = Enum.Material.SmoothPlastic }
	for _, px in { -0.022, 0, 0.022 } do
		K:box("ShiftPattern", Vector3.new(0.006, 0.004, 0.045), cap * CFrame.new(px, 0.007, 0), ink)
	end
	K:box("ShiftPattern", Vector3.new(0.05, 0.004, 0.006), cap * CFrame.new(0, 0.007, 0), ink)
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
		if P.ambient and S.consoleAmbient ~= false then
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
	-- 무선 충전 패드 (개인택시: 그 자리에 카드결제기)
	local pz = zU + 0.26
	if S.shifter == "buttons_row" then
		-- 투싼 NX4: 공조 패널 밑 스택 아래에 기대 선 무선 충전 트레이 (35°)
		local tz = F.dashFace + 0.09
		local tc = CFrame.new(x, topY + 0.145, tz + 0.15)
		K:wedge("ChargeTray", Vector3.new(0.64, 0.21, 0.3), tc * CFrame.Angles(0, math.pi, 0), P.gloss)
		local pc = tc * CFrame.Angles(math.rad(35), 0, 0) * CFrame.new(0, 0.012, 0)
		K:slab("ChargePad", 0.54, 0.3, 0.02, 0.06, pc, P.rubber)
		K:box("ChargeIcon", Vector3.new(0.05, 0.008, 0.07), pc * CFrame.new(0, 0.012, 0), P.markWhite)
	elseif S.key == "sonata_taxi" and F.kind ~= "police" then
		-- 카드결제기: 20° 세운 작은 검은 단말기 (위 LCD · 키패드 3줄 · 카드 태그 표시) + 앞쪽 받침
		local tc = CFrame.new(x, topY + 0.075, pz + 0.04) * CFrame.Angles(math.rad(-70), 0, 0)
		K:box("TerminalStand", Vector3.new(0.16, 0.07, 0.12), CFrame.new(x, topY + 0.06, pz - 0.07), P.hardDark)
		K:panel("CardTerminal", 0.26, 0.36, 0.08, 0.05, tc, P.hardDark)
		K:box("TerminalLcd", Vector3.new(0.19, 0.1, 0.006), tc * CFrame.new(0, 0.1, 0.042), P.lcd)
		for i = 0, 2 do
			K:box("TerminalKeys", Vector3.new(0.18, 0.035, 0.01), tc * CFrame.new(0, -0.01 - i * 0.05, 0.042), P.button)
		end
		K:box("TerminalTap", Vector3.new(0.07, 0.012, 0.004), tc * CFrame.new(0, -0.15, 0.043), P.markWhite)
	else
		K:slab("ChargePad", 0.6, 0.32, 0.025, 0.07, CFrame.new(x, topY + 0.045, pz), P.rubber)
		K:box("ChargeIcon", Vector3.new(0.05, 0.01, 0.07), CFrame.new(x, topY + 0.06, pz), P.markWhite)
	end

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
		-- 택시 · 순찰차: 6단 레버. 가죽 부츠가 노브 밑까지 감싸 막대가 안 보이고(조이스틱 X), 세로로 긴 가죽 노브 +
		-- 뒤쪽 새틴 띠 + 운전석 쪽 시프트 락 버튼, 부츠 밑 새틴 칼라, 운전석 쪽 P R N D 표시 (주차 중 P 만 켜짐)
		local gz = zU + L * 0.42
		local b = CFrame.new(x, top, gz)
		K:slab("GatePlate", 0.42, 0.6, 0.03, 0.12, b, P.gloss)
		for i = 0, 3 do
			K:box("GateMark", Vector3.new(0.04, 0.006, 0.03), b * CFrame.new(side * 0.18, 0.02, -0.19 + i * 0.12), if i == 0 then P.markWhite else P.button)
		end
		K:cyl("BootCollar", 0.016, 0.32, b * CFrame.new(0.02, 0.022, 0.01) * ROT_X_TO_Y, P.satin)
		K:ell("ShiftBoot", Vector3.new(0.26, 0.22, 0.3), b * CFrame.new(0.02, 0.07, 0.01), P.leather)
		K:ell("ShiftBootNeck", Vector3.new(0.13, 0.28, 0.15), b * CFrame.new(0.02, 0.2, 0.03), P.leather)
		local kn = b * CFrame.new(0.02, 0.4, 0.05) * CFrame.Angles(math.rad(8), 0, 0)
		K:ell("ShiftKnob", Vector3.new(0.15, 0.27, 0.2), kn, P.leather)
		K:box("ShiftKnobSpine", Vector3.new(0.035, 0.12, 0.016), kn * CFrame.new(0, 0.02, 0.095), P.satin)
		K:box("ShiftLock", Vector3.new(0.03, 0.06, 0.06), kn * CFrame.new(side * 0.072, 0.02, 0), P.satin)
		cupholders(K, P, x, top - 0.01, gz + 0.5, false)
		K:slab("EPB", 0.12, 0.17, 0.04, 0.03, CFrame.new(x + side * 0.2, top + 0.01, gz - 0.4), P.button)
		K:slab("AutoHold", 0.12, 0.1, 0.04, 0.03, CFrame.new(x - side * 0.2, top + 0.01, gz - 0.4), P.button)
	elseif kind == "dial_wood" then
		-- G80: 우드 인레이 + 크롬 변속 다이얼(앞) + 조그 다이얼(뒤), 알루미늄 키
		local gz = zU + L * 0.4
		K:slab("ConsoleWood", w - 0.18, L * 0.62, 0.02, 0.09, CFrame.new(x, top - 0.005, gz + 0.1), P.trim)
		vknurl(K, P, CFrame.new(x, top, gz), 0.27, 0.13, 24, P.gloss)
		K:cyl("ShiftDialRing", 0.02, 0.33, CFrame.new(x, top + 0.005, gz) * ROT_X_TO_Y, P.chrome)
		vknurl(K, P, CFrame.new(x, top, gz + 0.42), 0.23, 0.08, 20, P.screen)
		for _, k in { { -0.24, -0.08 }, { 0.24, -0.08 }, { -0.24, 0.16 }, { 0.24, 0.16 }, { -0.22, 0.42 }, { 0.22, 0.42 } } do
			-- 우드 면에서 0.011 만 솟은 납작한 렌즈형 알루미늄 키 (1파트, 모서리 없음)
			K:ell("AluKey", Vector3.new(0.11, 0.022, 0.062), CFrame.new(x + k[1], top + 0.005, gz + k[2]), P.aluKey)
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
		local g0, g1 = F.dashFace - 0.067, zA - 0.05 -- 대시 라인이 내려앉은 곳 -> 팔걸이
		for _, s in { -1, 1 } do
			K:cyl("Garnish", g1 - g0, 0.026, CFrame.new(x + s * (w / 2 - 0.035), topY + 0.04, (g0 + g1) / 2) * CFrame.Angles(0, math.pi / 2, 0), P.trim)
		end
	else -- dial (카니발)
		local gz = zU + L * 0.42
		if S.startButton then
			-- 시동 버튼: 무선 충전 패드(폭 0.6) 운전석 쪽 옆
			local sb = CFrame.new(x + side * 0.385, top + 0.012, pz)
			K:cyl("StartRing", 0.03, 0.13, sb * ROT_X_TO_Y, P.chrome)
			K:cyl("StartButton", 0.04, 0.1, sb * CFrame.new(0, 0.012, 0) * ROT_X_TO_Y, P.hardDark)
		end
		-- KA4: 다이얼 · 버튼 · 컵홀더를 피아노 블랙 판 한 장 + 새틴 테두리가 감쌈
		local pc = CFrame.new(x, top, gz + 0.32)
		K:slab("DialPlateRim", w - 0.12, 1.34, 0.02, 0.15, pc * CFrame.new(0, -0.006, 0), P.satin)
		K:slab("DialPlate", w - 0.16, 1.3, 0.03, 0.14, pc, P.glossMatte)
		vknurl(K, P, CFrame.new(x, top, gz), 0.26, 0.1, 14, P.gloss)
		K:cyl("DialP", 0.03, 0.08, CFrame.new(x, top + 0.115, gz) * ROT_X_TO_Y, P.satin)
		for _, k in { { -0.28, -0.18 }, { 0.28, -0.18 }, { -0.28, 0.0 }, { 0.28, 0.0 }, { -0.28, 0.18 }, { 0.28, 0.18 } } do
			K:box("DialKey", Vector3.new(0.1, 0.03, 0.1), CFrame.new(x + k[1], top + 0.015, gz + k[2]), P.button)
		end
		cupholders(K, P, x, top + 0.002, gz + 0.62, false)
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
