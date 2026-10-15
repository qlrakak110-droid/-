--!strict
-- GwangalliCarInterior/Cockpit: 운전석 앞 (차종별, Styles 참고).
--   핸들   스포크 형태(vee4 · u4 · two · three · bus2), 에어백 패드, 브랜드 엠블럼(현대 H · 제네시스 날개 · 기아 로고),
--          버튼 패널 / G80 알루미늄 롤러, 새틴 · 하이글로시 가니시, 패들. 피벗째 실시간 조향 회전.
--   컬럼   스티어링 컬럼 · 슈라우드 · 방향지시/와이퍼 레버 · (포터·쏠라티) 키 실린더
--   계기판 디지털(형광 링 + 짧은 바늘 + 7세그먼트 속도 · 기어) / 아날로그(크롬 베젤 + 바늘 + 가운데 LCD), 방향지시 화살표
--          차양: slim(쏘나타) · short(G80) · none(투싼 플로팅) · deep(레이 · 포터 · 쏠라티) · brow(카니발)
--   화면   float(쏘나타 플로팅 + S자 연결) · flush(G80 14.5" 낮고 넓게) · stack/pod/fascia(대시 쪽 스택에 박힘) ·
--          joined(카니발 한 장 유리). 지도는 Screens.nav
--   기타   HUD 창, 시동 버튼

local Screens = require(script.Parent:WaitForChild("Screens"))
local Gauges = require(script.Parent:WaitForChild("Gauges"))

local Cockpit = {}

local ROT_X_TO_Z = CFrame.Angles(0, -math.pi / 2, 0) -- 원통 축(X)을 프레임의 +Z 로

---------------------------------------------------------------------------------------------- 엠블럼
local function stroke(K: any, cf: CFrame, a: Vector2, b: Vector2, th: number, look: any)
	local d = b - a
	local mid = (a + b) / 2
	K:box("EmblemStroke", Vector3.new(d.Magnitude + th * 0.6, th, 0.008), cf * CFrame.new(mid.X, mid.Y, 0) * CFrame.Angles(0, 0, math.atan2(d.Y, d.X)), look)
end

local function emblem(K: any, P: any, brand: string, cf: CFrame)
	if brand == "genesis" then
		-- 방패 크레스트 + 양쪽 날개 깃 3줄
		K:ell("Crest", Vector3.new(0.05, 0.062, 0.014), cf, P.chrome)
		K:ell("CrestInner", Vector3.new(0.034, 0.044, 0.01), cf * CFrame.new(0, 0, 0.004), P.hardDark)
		for _, s in { -1, 1 } do
			for i, len in { 0.12, 0.1, 0.075 } do
				K:box("Wing", Vector3.new(len, 0.011, 0.008), cf * CFrame.new(s * (0.03 + len / 2), 0.017 - (i - 1) * 0.017, 0.002) * CFrame.Angles(0, 0, math.rad(s * 4)), P.chrome)
			end
		end
	elseif brand == "kia" then
		-- 2021 새 기아 로고 (이어진 K · I · 가로획 없는 A)
		local th = 0.011
		stroke(K, cf, Vector2.new(-0.075, -0.026), Vector2.new(-0.068, 0.026), th, P.chrome)
		stroke(K, cf, Vector2.new(-0.07, 0.0), Vector2.new(-0.038, 0.026), th, P.chrome)
		stroke(K, cf, Vector2.new(-0.06, 0.006), Vector2.new(-0.034, -0.026), th, P.chrome)
		stroke(K, cf, Vector2.new(-0.012, -0.026), Vector2.new(-0.005, 0.026), th, P.chrome)
		stroke(K, cf, Vector2.new(0.018, -0.026), Vector2.new(0.045, 0.026), th, P.chrome)
		stroke(K, cf, Vector2.new(0.045, 0.026), Vector2.new(0.07, -0.026), th, P.chrome)
	else
		-- 현대: 크롬 타원 + 기울어진 H
		K:ell("Emblem", Vector3.new(0.17, 0.1, 0.012), cf, P.chrome)
		K:ell("EmblemInner", Vector3.new(0.146, 0.078, 0.01), cf * CFrame.new(0, 0, 0.004), P.hardDark)
		local H = cf * CFrame.new(0, 0, 0.01)
		stroke(K, H, Vector2.new(-0.042, -0.026), Vector2.new(-0.026, 0.026), 0.014, P.chrome)
		stroke(K, H, Vector2.new(0.026, -0.026), Vector2.new(0.042, 0.026), 0.014, P.chrome)
		stroke(K, H, Vector2.new(-0.03, -0.004), Vector2.new(0.03, 0.006), 0.011, P.chrome)
	end
end

---------------------------------------------------------------------------------------------- 컬럼
local function column(K: any, F: any, P: any, S: any)
	local W: CFrame = F.wheel.cf
	local R: number = F.wheel.R
	K:seg("SteeringColumn", (W * CFrame.new(0, -0.03, -0.14)).Position, (W * CFrame.new(0, -0.1, -0.95)).Position, 0.18, P.hard)
	local shroud = W * CFrame.new(0, -0.13, -0.5) * CFrame.Angles(0, math.pi / 2, 0)
	K:rbox("ColumnShroud", Vector3.new(0.62, 0.24, 0.36), 0.09, shroud, P.soft)
	for _, s in { -1, 1 } do
		local a = (W * CFrame.new(s * 0.16, -0.09, -0.3)).Position
		local b = (W * CFrame.new(s * (R + 0.02), -0.16, -0.22)).Position
		K:seg("Stalk", a, b, 0.045, P.hard)
		K:ell("StalkTip", Vector3.new(0.13, 0.065, 0.065), CFrame.lookAt(b, a) * CFrame.Angles(0, math.pi / 2, 0), P.hard)
	end
	if not S.startButton then
		-- 키 실린더 + 키 (슈라우드 오른쪽)
		local kc = W * CFrame.new(-F.side * 0.2, -0.12, -0.42)
		K:cyl("IgnitionRing", 0.03, 0.1, kc, P.chrome)
		K:box("Key", Vector3.new(0.09, 0.03, 0.05), kc * CFrame.new(-F.side * 0.05, 0, 0), P.hardDark)
		K:box("KeyHead", Vector3.new(0.03, 0.11, 0.07), kc * CFrame.new(-F.side * 0.1, 0, 0), P.hardDark)
	end
end

---------------------------------------------------------------------------------------------- 핸들
local function wheel(K: any, F: any, P: any, S: any): (BasePart, Weld?)
	local W: CFrame = F.wheel.cf
	local R: number = F.wheel.R
	local ws = S.wheel
	local hub: Vector3 = ws.hub
	local kind: string = ws.spokes
	return K:pivot("SteeringPivot", W, function()
		-- 림: 3시·9시 그립이 두꺼운 가죽 원환 (포터는 얇고 고른 림)
		local grip = if kind == "bus2" then 0.05 else 0.17
		K:ring("WheelRim", W, R, if kind == "bus2" then 0.118 else 0.13, 36, P.wheelLeather, nil, nil, function(t: number)
			return 1 + grip * math.cos(t) ^ 2
		end)
		local hy = -0.03
		-- 허브 껍데기 + 에어백 패드
		K:ell("HubShell", Vector3.new(hub.X + 0.06, hub.Y + 0.05, 0.22), W * CFrame.new(0, hy, -0.05), P.hard)
		if kind == "three" then
			K:rbox("Airbag", Vector3.new(hub.Z, hub.Y, hub.X), 0.1, W * CFrame.new(0, hy, 0.06) * ROT_X_TO_Z, P.wheelHub)
		else
			K:ell("Airbag", hub, W * CFrame.new(0, hy, 0.06), P.wheelHub)
		end
		-- 좌우 스포크 (허브 -> 림, 약간 아래로) + 버튼
		local ang = if kind == "bus2" then math.rad(-15) elseif kind == "two" then math.rad(-8) else math.rad(-4)
		local th = if kind == "two" then 0.2 elseif kind == "bus2" then 0.19 else 0.15
		local x0, x1 = hub.X * 0.4, R - 0.03
		local len = x1 - x0
		local mid = (x0 + x1) / 2
		for _, s in { -1, 1 } do
			local sp = W * CFrame.new(s * mid * math.cos(ang), hy + mid * math.sin(ang), 0) * CFrame.Angles(0, 0, s * ang)
			K:rbox("Spoke", Vector3.new(len, th, 0.075), 0.035, sp, P.hard)
			if ws.sideTrim then
				-- 쏘나타: 스포크 위아래를 감싸는 새틴 크롬 (요크 느낌)
				K:box("SpokeTrim", Vector3.new(len - 0.04, 0.018, 0.02), sp * CFrame.new(0, th / 2 - 0.006, 0.035), P.satin)
				K:box("SpokeTrim", Vector3.new(len - 0.04, 0.018, 0.02), sp * CFrame.new(0, -th / 2 + 0.006, 0.035), P.satin)
			end
			-- 버튼 패널 (허브 쪽 끝)
			local pan = sp * CFrame.new(-s * (len / 2 - 0.13), 0.004, 0.046)
			if kind == "two" then
				-- G80: 알루미늄 롤러 + 토글
				K:panel("ButtonPanel", 0.22, 0.14, 0.02, 0.04, pan, P.gloss)
				K:cyl("Roller", 0.03, 0.075, pan * CFrame.new(-s * 0.05, 0, 0.02), P.alloy)
				for _, by in { 0.035, -0.035 } do
					K:box("Toggle", Vector3.new(0.06, 0.03, 0.03), pan * CFrame.new(s * 0.045, by, 0.02), P.alloy)
				end
			elseif kind ~= "bus2" or s < 0 then
				K:panel("ButtonPanel", 0.2, 0.13, 0.02, 0.04, pan, P.gloss)
				for i = 0, 3 do
					local bx = -0.05 + (i % 2) * 0.1
					local by = 0.03 - math.floor(i / 2) * 0.06
					K:box("Button", Vector3.new(0.065, 0.035, 0.012), pan * CFrame.new(bx, by, 0.014), P.button)
				end
			end
			-- 아래쪽 두 스포크: 쏘나타는 5시·7시로 벌어진 역V, 투싼·카니발·쏠라티는 6시 쪽으로 붙은 U
			if kind == "vee4" or kind == "u4" then
				local spread = if kind == "vee4" then 32 else 10
				local t = math.rad(-90 + s * spread)
				local a = (W * CFrame.new(s * 0.075, hy - hub.Y * 0.42, 0)).Position
				local b = (W * CFrame.new(math.cos(t) * (R - 0.03), math.sin(t) * (R - 0.03), -0.01)).Position
				K:seg("LowerSpoke", a, b, 0.08, P.hard)
				if ws.lowerTrim then
					local a2 = (W * CFrame.new(s * 0.075, hy - hub.Y * 0.42, 0.04)).Position
					local b2 = (W * CFrame.new(math.cos(t) * (R - 0.08), math.sin(t) * (R - 0.08), 0.03)).Position
					K:seg("LowerSpokeTrim", a2, b2, 0.032, if ws.lowerTrim == "gloss" then P.gloss else P.satin)
				end
			end
		end
		if kind == "three" then
			-- 레이: 아래 스포크 하나 + 하이글로시 가니시
			local y0, y1 = hy - hub.Y * 0.45, -(R - 0.03)
			K:panel("LowerSpoke", 0.16, y0 - y1, 0.07, 0.06, W * CFrame.new(0, (y0 + y1) / 2, 0), P.hard)
			K:panel("LowerSpokeTrim", 0.11, y0 - y1 - 0.06, 0.02, 0.04, W * CFrame.new(0, (y0 + y1) / 2, 0.04), P.gloss)
		elseif kind == "two" then
			-- G80: 아래가 비어 있고 허브가 아래로 조금 불룩
			K:ell("HubChin", Vector3.new(hub.X * 0.55, hub.Y * 0.5, hub.Z * 0.85), W * CFrame.new(0, hy - hub.Y * 0.36, 0.04), P.wheelHub)
		end
		emblem(K, P, S.brand, W * CFrame.new(0, hy + 0.005, 0.06 + hub.Z / 2 + 0.002))
		if ws.paddles then
			for _, s in { -1, 1 } do
				K:panel("Paddle", 0.07, 0.24, 0.025, 0.03, W * CFrame.new(s * (R - 0.12), 0.02, -0.11) * CFrame.Angles(0, 0, math.rad(s * 8)), P.paddle)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------- 계기판 내용
local function gaugeLook(P: any): any
	return { mark = P.gaugeMark, red = P.gaugeRed, ring = P.gaugeRing, needle = P.needle, cap = P.needleCap, bezel = P.chrome }
end

-- 유리(cf, +Z = 운전자 쪽) 앞에 두 게이지 + 숫자 + 방향지시 + 정보
local function clusterFace(K: any, P: any, S: any, cf: CFrame, w: number, h: number): any
	local C = S.cluster
	local analog = C.kind == "analog"
	local r = math.min(h * 0.43, w * 0.2)
	local dx = w * 0.31
	local look = gaugeLook(P)
	-- 디지털: 왼쪽 속도 / 오른쪽 RPM, 아날로그(현대·기아 전통 배치): 왼쪽 RPM / 오른쪽 속도
	local sx = if analog then dx else -dx
	local speedCF = cf * CFrame.new(sx, -0.008, 0.012)
	local rpmCF = cf * CFrame.new(-sx, -0.008, 0.012)
	local out: any = {}
	if analog then
		for _, g in { speedCF, rpmCF } do
			K:cyl("DialFace", 0.006, 2 * r + 0.03, g * ROT_X_TO_Z, P.dialFace)
		end
	end
	out.speed = Gauges.dial(K, speedCF, r, { analog = analog, short = not analog, ticks = math.floor(C.speedMax / 20), max = C.speedMax, look = look })
	out.rpm = Gauges.dial(K, rpmCF, r * (if analog then 1 else 0.94), { analog = analog, short = not analog, ticks = C.rpmMax, red = if C.rpmMax <= 6 then 0.75 else 0.8, max = C.rpmMax * 1000, look = look })
	if analog then
		-- 가운데 LCD: 시계 · 주행거리 + 기어
		local lw, lh = w * 0.25, h * 0.66
		local lcd = cf * CFrame.new(0, -0.02, 0.008)
		K:panel("ClusterLcd", lw, lh, 0.006, 0.03, lcd, P.lcd)
		out.info = Screens.lcd(K, lcd * CFrame.new(0, lh * 0.24, 0.006), lw * 0.9, lh * 0.34)
		out.gear = Gauges.digits(K, lcd * CFrame.new(0, -lh * 0.17, 0.006), 1, lh * 0.32, P.seg)
	else
		out.speedNum = Gauges.digits(K, speedCF * CFrame.new(0, 0.018, 0.01), 3, r * 0.42, P.seg)
		Screens.plate(K, "SpeedUnit", speedCF * CFrame.new(0, -r * 0.34, 0.012), r * 0.62, r * 0.15, { "km/h" }, Color3.fromRGB(150, 165, 185))
		out.gear = Gauges.digits(K, rpmCF * CFrame.new(0, 0.012, 0.01), 1, r * 0.5, P.segAccent)
		out.info = Screens.info(K, cf * CFrame.new(0, 0.03, 0.012), w * 0.22, h * 0.36, string.upper(S.brand))
		-- 연료 · 수온 막대
		for i, fill in { 0.72, 0.55 } do
			local y = -h * 0.28 - (i - 1) * 0.036
			K:box("BarTrack", Vector3.new(w * 0.2, 0.016, 0.004), cf * CFrame.new(0, y, 0.012), P.mapUI)
			K:box("BarFill", Vector3.new(w * 0.2 * fill, 0.016, 0.004), cf * CFrame.new(-w * 0.1 * (1 - fill), y, 0.015), if i == 1 then P.gaugeRing else P.mapRoute)
		end
	end
	out.turnL = Gauges.arrow(K, cf * CFrame.new(-w * 0.085, h * 0.37, 0.012), -1, 0.05, P.turn)
	out.turnR = Gauges.arrow(K, cf * CFrame.new(w * 0.085, h * 0.37, 0.012), 1, 0.05, P.turn)
	return out
end

---------------------------------------------------------------------------------------------- 시선 (계기판 높이)
-- 운전자 눈(좌석 위)에서 핸들 위쪽 빈 곳 가운데를 지나는 선이 계기판 면과 만나는 높이: 핸들에 가리지 않는 높이
local function sightY(F: any, hubH: number, z: number): number
	local W: CFrame = F.wheel.cf
	local R: number = F.wheel.R
	local seat = nil
	for _, s in F.front do
		if (s.x < 0) == (F.side < 0) then
			seat = s
		end
	end
	local cushTop = if seat then seat.cush.Y + seat.cushSize.Y / 2 else F.floorY + 1.0
	local sz = if seat then seat.z else F.wheel.c.Z + 1.5
	local eye = Vector3.new(F.wheel.c.X, cushTop + 1.95, sz + 0.6)
	local m = (W * CFrame.new(0, (hubH / 2 + R) / 2, 0)).Position
	local slope = (m.Y - eye.Y) / math.min(-0.05, m.Z - eye.Z)
	return eye.Y + slope * (z - eye.Z)
end

---------------------------------------------------------------------------------------------- 계기판 + 화면
local function displays(K: any, F: any, P: any, S: any): any
	local C, CE = S.cluster, S.center
	local cl: Vector3 = F.cluster
	local nv: Vector3 = F.nav
	local face: number, top: number = F.dashFace, F.dashTop
	local toC = -F.side -- 운전석에서 가운데 쪽 (+1 = 좌핸들)
	local cx = if F.console then F.console.x else 0
	local w, h = C.w, C.h
	local zS = math.max(cl.Z, face + 0.15)
	local yS = math.clamp(sightY(F, S.wheel.hub.Y, zS), top - h / 2 + 0.08, top + h / 2 + 0.12)
	if CE.kind == "joined" then
		yS = math.max(yS, top + h / 2 - 0.2) -- 카니발 파노라믹: 대시 위로 올라선 한 장 유리
	end
	local tilt = CFrame.Angles(math.rad(-9), 0, 0)
	local screens: any = {}

	-- 카니발: 계기판 + 내비 한 장 유리 (계기판 쪽만 짧은 차양) -----------------------------------------------
	if CE.kind == "joined" then
		local navW = math.max(CE.w, 1.2)
		local xL, xR = cl.X - w / 2 - 0.05, cl.X + w / 2 + 0.1 + navW + 0.05
		if toC < 0 then
			xL, xR = cl.X - w / 2 - 0.1 - navW - 0.05, cl.X + w / 2 + 0.05
		end
		local midX = (xL + xR) / 2
		local base = CFrame.new(midX, yS, zS) * tilt
		K:panel("DisplayBezel", xR - xL, h + 0.1, 0.07, 0.07, base, P.gloss)
		K:cyl("DisplayEdge", xR - xL - 0.12, 0.022, base * CFrame.new(0, -h / 2 - 0.05, 0.03), P.satin)
		K:panel("DisplayBack", xR - xL - 0.1, h, 0.14, 0.1, base * CFrame.new(0, -0.02, -0.1), P.hard)
		local cCF = base * CFrame.new(cl.X - midX, 0, 0.045)
		K:box("ClusterGlass", Vector3.new(w, h, 0.02), cCF, P.screen)
		screens.cluster = clusterFace(K, P, S, cCF, w, h)
		local nX = cl.X + toC * (w / 2 + 0.1 + navW / 2)
		local nCF = base * CFrame.new(nX - midX, 0, 0.045)
		K:box("NavGlass", Vector3.new(navW, h, 0.02), nCF, P.screen)
		screens.nav = Screens.nav(K, nCF, navW, h, P)
		-- 계기판 쪽만 짧은 눈썹 차양 (납작한 타원체)
		K:ell("ClusterHood", Vector3.new(w + 0.16, 0.12, 0.5), base * CFrame.new(cl.X - midX, h / 2 + 0.09, -0.08), P.soft)
		F.centerCF, F.centerW, F.centerH = nCF, navW, h
		return screens
	end

	-- 계기판 ------------------------------------------------------------------------------------------
	local clCF = CFrame.new(cl.X, yS, zS) * tilt
	local hoodKind: string = C.hood
	if hoodKind == "none" then
		-- 투싼: 차양 없는 얇은 유리판, 대시 위 받침
		K:panel("ClusterBezel", w + 0.05, h + 0.05, 0.03, 0.05, clCF * CFrame.new(0, 0, -0.02), P.gloss)
		K:panel("ClusterBack", w - 0.06, h - 0.06, 0.07, 0.08, clCF * CFrame.new(0, 0, -0.06), P.hard)
		local footH = (yS - h / 2) - (top - 0.06)
		if footH > 0.03 then
			K:panel("ClusterFoot", w * 0.45, footH, 0.16, 0.06, CFrame.new(cl.X, top - 0.06 + footH / 2, zS - 0.08), P.hard)
		end
	else
		K:panel("ClusterBack", w + 0.12, h + 0.1, 0.42, 0.12, clCF * CFrame.new(0, 0.02, -0.22), P.hard)
		K:panel("ClusterBezel", w + 0.06, h + 0.06, 0.03, 0.07, clCF * CFrame.new(0, 0, -0.012), P.gloss)
		-- 차양: 납작한 타원체 돔 (앞 끝이 유리 위로 살짝 나옴) + 양옆으로 내려오는 둥근 볼
		local deep = hoodKind == "deep"
		local hd = if deep then 0.62 elseif hoodKind == "short" then 0.4 else 0.5
		local hw = w + (if deep then 0.3 else 0.2)
		local hh = if deep then 0.2 else 0.13
		local hoodCF = clCF * CFrame.new(0, h / 2 + hh * 0.42, -hd * 0.3)
		K:ell("ClusterHood", Vector3.new(hw, hh, hd), hoodCF, P.soft)
		if hoodKind ~= "deep" then
			K:box("ClusterHoodStitch", Vector3.new(hw * 0.8, 0.008, 0.008), hoodCF * CFrame.new(0, hh * 0.32, hd * 0.36), P.stitch)
		end
		for _, s in { -1, 1 } do
			K:ell("ClusterCheek", Vector3.new(0.1, h * (if deep then 1.15 else 0.8), hd * 0.7), clCF * CFrame.new(s * (hw / 2 - 0.05), h * (if deep then 0.05 else 0.15), -hd * 0.3), P.soft)
		end
	end
	K:box("ClusterGlass", Vector3.new(w, h, 0.02), clCF, if C.kind == "analog" then P.dialBack else P.screen)
	screens.cluster = clusterFace(K, P, S, clCF, w, h)

	-- 가운데 화면 ---------------------------------------------------------------------------------------
	local cw, ch = CE.w, CE.h
	local ccf: CFrame
	local kind: string = CE.kind
	if kind == "float" then
		local minX = cl.X + toC * (w / 2 + cw / 2 + 0.14)
		local x = if toC > 0 then math.max(nv.X, minX) else math.min(nv.X, minX)
		ccf = CFrame.new(x, top + ch / 2 + 0.05, face - 0.06) * CFrame.Angles(0, F.side * math.rad(6), 0) * CFrame.Angles(math.rad(-6), 0, 0)
		K:panel("CenterBack", cw - 0.1, ch - 0.08, 0.14, 0.1, ccf * CFrame.new(0, 0, -0.09), P.hard)
		K:panel("CenterNeck", cw * 0.55, 0.14, 0.18, 0.06, ccf * CFrame.new(0, -ch / 2 - 0.02, -0.1), P.hard)
		if S.sCurve then
			-- 쏘나타: 계기판 차양 끝에서 화면 테두리로 흘러내리는 S자 띠
			local a = (clCF * CFrame.new(toC * (w / 2 + 0.08), h / 2 + 0.06, -0.06)).Position
			local b = (ccf * CFrame.new(-toC * (cw / 2 + 0.02), ch * 0.25, -0.03)).Position
			local prev = a
			for i = 1, 5 do
				local t = i / 5
				local st = t * t * (3 - 2 * t)
				local p = Vector3.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * st, a.Z + (b.Z - a.Z) * t)
				K:seg("SCurve", prev, p, 0.07, P.soft, 0.03)
				prev = p
			end
		end
	elseif kind == "flush" then
		-- G80: 대시 위쪽 가운데에 낮고 넓게 박힌 화면 (가죽 둔덕이 감쌈)
		ccf = CFrame.new(cx + toC * 0.12, top + ch / 2 - 0.06, face - 0.28) * CFrame.Angles(math.rad(-8), 0, 0)
		K:rbox("CenterCowl", Vector3.new(cw + 0.22, ch * 0.62, 0.44), 0.12, ccf * CFrame.new(0, -ch * 0.2, -0.17), P.soft)
		K:panel("CenterBack", cw - 0.06, ch - 0.06, 0.1, 0.08, ccf * CFrame.new(0, 0, -0.07), P.hard)
	elseif kind == "stack" then
		ccf = CFrame.new(cx, top - ch / 2 + 0.02, face + 0.12) * CFrame.Angles(math.rad(-10), 0, 0)
	elseif kind == "pod" then
		ccf = CFrame.new(cx, top - ch / 2 - 0.06, face + 0.17) * CFrame.Angles(math.rad(-8), 0, 0)
	else -- fascia
		ccf = CFrame.new(cx, F.dashMidY + 0.42, face + 0.1) * CFrame.Angles(math.rad(-10), 0, 0)
	end
	K:panel("NavBezel", cw + 0.06, ch + 0.06, 0.04, 0.05, ccf * CFrame.new(0, 0, -0.02), P.gloss)
	K:box("NavGlass", Vector3.new(cw, ch, 0.02), ccf, P.screen)
	screens.nav = Screens.nav(K, ccf, cw, ch, P)
	F.centerCF, F.centerW, F.centerH = ccf, cw, ch
	return screens
end

---------------------------------------------------------------------------------------------- 조립
function Cockpit.build(K: any, F: any, P: any)
	local S = F.style
	local out: any = {}
	column(K, F, P, S)
	local pivot, weld = wheel(K, F, P, S)
	out.wheelPivot, out.wheelWeld, out.wheelCF = pivot, weld, F.wheel.cf
	out.screens = displays(K, F, P, S)
	local W: CFrame = F.wheel.cf
	if S.hud then
		K:slab("HudWindow", 0.62, 0.3, 0.02, 0.08, CFrame.new(W.Position.X, F.dashTop + 0.012, F.dashFace - 0.75), P.gloss)
	end
	if S.startButton then
		local sb = CFrame.new(W.Position.X - F.side * (F.wheel.R + 0.32), F.dashMidY + 0.05, F.dashFace + 0.03)
		K:cyl("StartRing", 0.04, 0.2, sb * ROT_X_TO_Z, P.chrome)
		K:cyl("StartButton", 0.05, 0.15, sb * CFrame.new(0, 0, 0.012) * ROT_X_TO_Z, P.startBtn)
	end
	return out
end

---------------------------------------------------------------------------------------------- 실시간
-- state = { kmh, rpm, gear, turnL, turnR }, k = 바늘이 따라가는 비율 (0..1)
local TURN_OFF = 0.86
function Cockpit.live(ck: any, state: any, k: number, slow: boolean)
	local c = ck.screens and ck.screens.cluster
	if not c then
		return
	end
	Gauges.setNeedle(c.speed, math.abs(state.kmh), k)
	Gauges.setNeedle(c.rpm, state.rpm, k)
	if not slow then
		return
	end
	if c.speedNum then
		Gauges.show(c.speedNum, tostring(math.floor(math.abs(state.kmh) + 0.5)))
	end
	Gauges.show(c.gear, state.gear)
	for _, pair in { { c.turnL, state.turnL }, { c.turnR, state.turnR } } do
		local tr = if pair[2] then 0 else TURN_OFF
		for _, p in pair[1] do
			if p.Transparency ~= tr then
				p.Transparency = tr
			end
		end
	end
	Screens.update({ info = c.info, nav = ck.screens.nav })
end

return Cockpit
