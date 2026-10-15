--!nocheck
-- GwangalliCarInterior (LocalScript, StarterPlayerScripts): AAA급 차량 실내 + 검은 반투명 틴팅 유리.
-- 메쉬 업로드 없이 파트로만 만들고, 전부 이 클라이언트에만 생깁니다 (서버·네트워크 부담 없음).
--   Glass    맵의 모든 차 유리를 틴팅 (앞유리 스모크 / 옆·뒤 검은 틴팅 + 반사)
--   Fit      기존 Interior 파트(핸들 림·대시·좌석·도어 트림…)에서 차마다 실내 치수를 읽음
--   Cockpit  핸들(실시간 조향 회전)·컬럼·레버·파노라믹 디스플레이(계기판+내비)·차양·HUD·시동 버튼
--   Dash     대시보드·송풍구·트림 띠·앰비언트·공조·글로브박스·A필러
--   Console  센터 콘솔·변속기(버튼/다이얼/레버)·컵홀더·무선충전·팔걸이·뒷좌석 송풍구
--   Seats    앞좌석(볼스터·퀼팅·헤드레스트·벨트) + 뒷좌석 3인 벤치
--   Trim     도어 트림·필러·헤드라이너·오버헤드 콘솔·선바이저·룸미러·매트·페달
--   Styles   차종별 실제 실내 사양 (쏘나타 DN8 · 택시 · G80 · 투싼 · 레이 · 카니발 · 포터 · 쏠라티 119)
--   Gauges   실물 계기판 (눈금 · 링 · 회전 바늘 · 7세그먼트 숫자), Screens 지도 · 글자판
--   Lights   실내등 (밤: 앰비언트 발밑 조명 · 화면 빛, 정차 중: 천장등 · 맵램프)
-- 성능: 카메라 근처 차 3대 + 내가 탄 차만 실내를 만들고(차당 약 400 파트, 프레임당 70개씩), 멀어지면 지웁니다.
-- 기존 Interior 파트는 지우지 않고 이 클라이언트에서만 Transparency = 1 로 숨깁니다 (좌석 Seat·스크립트 영향 없음).
-- GwangalliWorld/DetailLOD 가 차 실내(LOD = "near")를 LocalTransparencyModifier 로 켜고 끄기 때문에 그 값은 건드리지
-- 않고, 옛 화면 SurfaceGui 는 MaxDistance 로 끕니다 (DetailLOD 가 Enabled 를 되돌려도 안 보이게).
-- (한 파일 버전: tools/bundle_luau.py 가 GwangalliCarInterior 폴더를 묶은 것. StarterPlayerScripts 에 LocalScript 로 넣으세요)

local __defs, __cache = {}, {}
local function __require(name)
	local v = __cache[name]
	if v == nil then
		v = __defs[name]()
		__cache[name] = v
	end
	return v
end

__defs["Cockpit"] = function()
-- GwangalliCarInterior/Cockpit: 운전석 앞 (차종별, Styles 참고).
--   핸들   스포크 형태(vee4 · u4 · two · three · bus2), 에어백 패드, 브랜드 엠블럼(현대 H · 제네시스 날개 · 기아 로고),
--          버튼 패널 / G80 알루미늄 롤러, 새틴 · 하이글로시 가니시, 패들. 피벗째 실시간 조향 회전.
--   컬럼   스티어링 컬럼 · 슈라우드 · 방향지시/와이퍼 레버 · (포터·쏠라티) 키 실린더
--   계기판 디지털(형광 링 + 짧은 바늘 + 7세그먼트 속도 · 기어) / 아날로그(크롬 베젤 + 바늘 + 가운데 LCD), 방향지시 화살표
--          차양: slim(쏘나타) · short(G80) · none(투싼 플로팅) · deep(레이 · 포터 · 쏠라티) · brow(카니발)
--   화면   float(쏘나타 플로팅 + S자 연결) · flush(G80 14.5" 낮고 넓게) · stack/pod/fascia(대시 쪽 스택에 박힘) ·
--          joined(카니발 한 장 유리). 지도는 Screens.nav
--   기타   HUD 창, 시동 버튼

local Screens = __require("Screens")
local Gauges = __require("Gauges")

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
		elseif S.key == "tucson" then
			-- 투싼 NX4: 앞면이 평평한 가로로 넓은 둥근 사다리꼴 패드 (넓은 위 + 좁은 턱), 앞면이 엠블럼 면과 맞음
			local pz = 0.06 + hub.Z / 2 - hub.Z * 0.35
			K:panel("Airbag", hub.X * 0.92, hub.Y * 0.62, hub.Z * 0.7, 0.1, W * CFrame.new(0, hy + hub.Y * 0.14, pz), P.wheelHub)
			K:panel("AirbagChin", hub.X * 0.62, hub.Y * 0.5, hub.Z * 0.7, 0.08, W * CFrame.new(0, hy - hub.Y * 0.2, pz - 0.004), P.wheelHub)
		elseif kind == "two" then
			-- G80 RG3: 가로로 넓은 알약(스타디움)형 납작한 패드 + 얕은 크라운 (달걀형 돔 X)
			K:panel("Airbag", hub.X, hub.Y, hub.Z * 0.55, hub.Y / 2 - 0.004, W * CFrame.new(0, hy, 0.03), P.wheelHub)
			K:ell("AirbagCrown", Vector3.new(hub.X * 0.86, hub.Y * 0.78, 0.07), W * CFrame.new(0, hy, 0.03 + hub.Z * 0.275), P.wheelHub)
		elseif ws.hubShape == "trap" then
			-- 카니발 KA4: 가로로 넓은 둥근 사다리꼴 패드 (위 폭 0.6 · 아래 턱 폭 0.42), 앞면 평평 (엠블럼 바로 뒤)
			K:panel("Airbag", hub.X, hub.Y * 0.72, hub.Z, 0.11, W * CFrame.new(0, hy + hub.Y * 0.1, 0.06), P.wheelHub)
			K:panel("AirbagChin", hub.X * 0.7, hub.Y * 0.5, hub.Z * 0.9, 0.08, W * CFrame.new(0, hy - hub.Y * 0.2, 0.055), P.wheelHub)
		elseif kind == "vee4" then
			-- 쏘나타 DN8: 공 모양 돔이 아니라 납작한 둥근 사각 패드 (앞에서 본 모서리 r 0.13) + 얕은 크라운
			K:rbox("Airbag", Vector3.new(0.1, hub.Y, hub.X), 0.13, W * CFrame.new(0, hy, 0.05) * ROT_X_TO_Z, P.wheelHub)
			K:ell("AirbagCrown", Vector3.new(hub.X - 0.04, hub.Y - 0.04, 0.09), W * CFrame.new(0, hy, 0.105), P.wheelHub)
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
					if ws.icons then
						K:box("ButtonIcon", Vector3.new(0.026, 0.009, 0.004), pan * CFrame.new(bx, by, 0.022), P.markWhite)
					end
				end
			end
			-- 아래쪽 두 스포크: 쏘나타는 5시·7시로 벌어진 역V, 투싼·카니발·쏠라티는 6시 쪽으로 붙은 U
			if ws.lowerV then
				-- 카니발 KA4: 허브 턱 양끝에서 6시 림(±4°)으로 모이는 납작한 V 블레이드 + 하이글로시 인레이
				local a2 = Vector2.new(s * 0.13, hy - hub.Y * 0.42)
				local t = math.rad(-90 + s * 4)
				local b2 = Vector2.new(math.cos(t) * (R - 0.03), math.sin(t) * (R - 0.03))
				local d = b2 - a2
				local bc = W * CFrame.new((a2.X + b2.X) / 2, (a2.Y + b2.Y) / 2, -0.01) * CFrame.Angles(0, 0, math.atan2(d.Y, d.X))
				K:rbox("LowerSpoke", Vector3.new(d.Magnitude, 0.085, 0.05), 0.022, bc, P.hard)
				if ws.lowerTrim then
					K:box("LowerSpokeTrim", Vector3.new(d.Magnitude - 0.1, 0.032, 0.012), bc * CFrame.new(0, 0, 0.027), if ws.lowerTrim == "gloss" then P.gloss else P.satin)
				end
			elseif kind == "vee4" or kind == "u4" then
				local spread = if kind == "vee4" then 32 else 10
				local t = math.rad(-90 + s * spread)
				local a = (W * CFrame.new(s * 0.075, hy - hub.Y * 0.42, 0)).Position
				local b = (W * CFrame.new(math.cos(t) * (R - 0.03), math.sin(t) * (R - 0.03), -0.01)).Position
				if kind == "vee4" then
					-- 쏘나타: 막대가 아니라 납작한 판 스포크 (폭 0.12 · 두께 0.06, 긴 모서리 둥글게) + 가운데 새틴 띠
					local zA = W.ZVector
					local yv = zA:Cross(b - a).Unit
					local spf = CFrame.fromMatrix((a + b) / 2, yv:Cross(zA), yv, zA)
					local sl = (b - a).Magnitude
					K:rbox("LowerSpoke", Vector3.new(sl + 0.02, 0.12, 0.06), 0.028, spf, P.hard)
					K:box("LowerSpokeTrim", Vector3.new(sl - 0.12, 0.024, 0.01), spf * CFrame.new(0.03, 0, 0.032), P.satin)
				elseif S.key == "tucson" then
					-- 투싼: 가까이 붙은 납작한 아래 스포크 두 개 + 운전자 쪽 새틴 띠
					local cfL = CFrame.lookAt((a + b) / 2, b, W.ZVector)
					local lenL = (b - a).Magnitude
					K:box("LowerSpoke", Vector3.new(0.09, 0.05, lenL + 0.04), cfL, P.hard)
					K:box("LowerSpokeTrim", Vector3.new(0.05, 0.012, lenL - 0.1), cfL * CFrame.new(0, 0.027, 0.03), P.satin)
				else
					K:seg("LowerSpoke", a, b, 0.08, P.hard)
					if ws.lowerTrim then
						local a2 = (W * CFrame.new(s * 0.075, hy - hub.Y * 0.42, 0.04)).Position
						local b2 = (W * CFrame.new(math.cos(t) * (R - 0.08), math.sin(t) * (R - 0.08), 0.03)).Position
						K:seg("LowerSpokeTrim", a2, b2, 0.032, if ws.lowerTrim == "gloss" then P.gloss else P.satin)
					end
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
		emblem(K, P, S.brand, W * CFrame.new(0, hy + 0.005, if kind == "two" then 0.03 + hub.Z * 0.275 + 0.037 else 0.06 + hub.Z / 2 + 0.002))
		if ws.paddles then
			for _, s in { -1, 1 } do
				K:panel("Paddle", 0.07, 0.24, 0.025, 0.03, W * CFrame.new(s * (R - 0.12), 0.02, -0.11) * CFrame.Angles(0, 0, math.rad(s * 8)), P.paddle)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------- 계기판 내용
local function gaugeLook(P: any): any
	return { mark = P.gaugeMark, red = P.gaugeRed, ring = P.gaugeRing, needle = P.needle, cap = P.needleCap, bezel = P.satin }
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
		if hoodKind == "slim" then
			-- 쏘나타: 각진 상자 대신 둥근 포드 (앞 끝은 베젤 바로 뒤, 뒤쪽 절반은 대시 속)
			K:ell("ClusterBack", Vector3.new(w + 0.14, h + 0.14, 0.7), clCF * CFrame.new(0, 0.02, -0.37), P.soft)
		else
			K:panel("ClusterBack", w + 0.12, h + 0.1, 0.42, 0.12, clCF * CFrame.new(0, 0.02, -0.22), P.hard)
		end
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
			if not (S.sCurve and s == toC) then -- 쏘나타: 화면 쪽 볼은 S자 드롭이 대신
				K:ell("ClusterCheek", Vector3.new(0.1, h * (if deep then 1.15 else 0.8), hd * 0.7), clCF * CFrame.new(s * (hw / 2 - 0.05), h * (if deep then 0.05 else 0.15), -hd * 0.3), P.soft)
			end
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
		if S.sCurve then
			-- 쏘나타 DN8: 화면을 계기판과 같은 면 · 같은 높이에 (아래쪽이 대시에 묻힌 반통합 받침, 목 없음).
			-- S자 테두리: 차양 오른쪽 끝이 두 화면 사이로 흘러내리고(드롭) 화면 아래 광택 턱으로 이어짐
			ccf = CFrame.new(x, yS + (h - ch) / 2 + 0.08, zS - 0.02) * CFrame.Angles(0, F.side * math.rad(6), 0) * tilt
			K:panel("CenterBack", cw - 0.1, ch - 0.08, 0.14, 0.1, ccf * CFrame.new(0, 0, -0.09), P.hard)
			local gx = cl.X + toC * (w / 2 + 0.07)
			K:ell("SCurveDrop", Vector3.new(0.13, h + 0.12, 0.24), CFrame.new(gx, yS + 0.03, zS - 0.12) * tilt, P.soft)
			K:ell("SCurveChin", Vector3.new(cw + 0.16, 0.08, 0.24), ccf * CFrame.new(-toC * 0.04, -ch / 2 - 0.03, -0.08), P.gloss)
		else
			-- 단독 플로팅 화면 (쏘나타 택시 8"): 대시 위 받침
			ccf = CFrame.new(x, top + ch / 2 + 0.05, face - 0.06) * CFrame.Angles(0, F.side * math.rad(6), 0) * CFrame.Angles(math.rad(-6), 0, 0)
			K:panel("CenterBack", cw - 0.1, ch - 0.08, 0.14, 0.1, ccf * CFrame.new(0, 0, -0.09), P.hard)
			K:panel("CenterNeck", cw * 0.55, 0.14, 0.18, 0.06, ccf * CFrame.new(0, -ch / 2 - 0.02, -0.1), P.hard)
		end
	elseif kind == "flush" then
		-- G80: 대시 위쪽 가운데에 낮고 넓게 박힌 화면 (가죽 둔덕이 감쌈)
		-- G80 RG3: 대시 면과 거의 같은 면에 박힌 초광폭 화면. 유리 아래 끝(top - 0.12)은 헤어라인 송풍구 위 립 바로 위,
		-- 뒤는 얕은 가죽 하우징만 (앞유리 밑에 얹힌 태블릿 X)
		ccf = CFrame.new(cx + toC * 0.16, top - 0.12 + ch / 2, face + 0.05) * CFrame.Angles(math.rad(-3), 0, 0)
		K:panel("CenterHousing", cw + 0.1, ch + 0.04, 0.1, 0.1, ccf * CFrame.new(0, 0, -0.07), P.soft)
	elseif kind == "stack" then
		ccf = CFrame.new(cx, top - ch / 2 + 0.02, face + 0.12) * CFrame.Angles(math.rad(-10), 0, 0)
	elseif kind == "pod" then
		ccf = CFrame.new(cx, top - ch / 2 - 0.06, face + 0.17) * CFrame.Angles(math.rad(-8), 0, 0)
	else -- fascia
		ccf = CFrame.new(cx, math.min(F.dashMidY + 0.42, top - ch / 2 - 0.25), face + 0.1) * CFrame.Angles(math.rad(-10), 0, 0)
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
	if S.startButton and S.shifter ~= "dial" then -- 카니발: 콘솔 충전 패드 옆 (Console)
		-- 센터 스택(반폭 ~0.65 + 테두리) 바깥, 크롬 라인 아래 대시 아랫면(대시 면보다 0.08 안쪽)에 붙임
		local scx = if F.console then F.console.x else 0
		local off = math.min(F.wheel.R + 0.32, math.abs(scx - W.Position.X) - 0.86)
		local sb = CFrame.new(W.Position.X - F.side * off, F.dashMidY - 0.12, F.dashFace - 0.06)
		K:cyl("StartRing", 0.04, 0.2, sb * ROT_X_TO_Z, P.chrome)
		K:cyl("StartButton", 0.05, 0.15, sb * CFrame.new(0, 0, 0.012) * ROT_X_TO_Z, if S.brand == "genesis" then P.gloss else P.startBtn)
	end
	return out
end

---------------------------------------------------------------------------------------------- 실시간
-- state = { kmh, rpm, gear, turnL, turnR }, k = 바늘이 따라가는 비율 (0..1)
local TURN_ON = Color3.fromRGB(60, 255, 110)
local TURN_OFF = Color3.fromRGB(16, 46, 26)
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
	-- 방향지시: 켜짐 = 밝은 Neon, 꺼짐 = 어두운 초록 (투명도 대신 재질로: Neon 은 반투명이어도 빛나 보임)
	for _, pair in { { c.turnL, state.turnL }, { c.turnR, state.turnR } } do
		local on = pair[2] == true
		for _, p in pair[1] do
			local m = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			if p.Material ~= m then
				p.Material = m
				p.Color = if on then TURN_ON else TURN_OFF
			end
		end
	end
	Screens.update({ info = c.info, nav = ck.screens.nav })
end

return Cockpit

end

__defs["Console"] = function()
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

end

__defs["Dash"] = function()
-- GwangalliCarInterior/Dash: 대시보드 (차종별, Styles 참고).
--   공통   상단 패드 + 둥근 앞 모서리 + 앞유리까지 덮는 상판(성에 제거 슬롯 · 트위터), 하단 패널(투톤), 무릎 패널,
--          글로브박스, A필러 트림
--   가니시 line(쏘나타 문~문 새틴 크롬 + 앰비언트 + 조수석 질감 패널) · wood(G80 헤어라인 송풍구 + 우드 띠) ·
--          waterfall(투싼 새틴 두 줄이 스택 양옆으로 흘러내림) · metal_wood(카니발 금속 띠 슬롯 송풍구 + 우드그레인)
--   스택   쏘나타 좁은 스택(가로 송풍구 2 + 비상등 + AVN 키 + 널링 다이얼 공조) · G80 우드 아래 매달린 공조 ·
--          투싼 피아노 블랙 세로 스택(세로 송풍구 + 터치 공조) · 레이 메탈 베젤 돌출 포드(대시 기어 레버 + 3다이얼) ·
--          카니발 터치 띠 · 포터 센터페시아(위 송풍구 + 3다이얼) · 쏠라티 은색 프레임 스택(사다리꼴 송풍구 + 3다이얼)
--   기타   포터 대시 위 수납 트레이, 쏠라티 뚜껑 수납함 + 사이렌 · 경광등 조작 박스 + 무전기 + 대시 기어 포드

local Screens = __require("Screens")
local Gauges = __require("Gauges")

local Dash = {}

local ROT_X_TO_Z = CFrame.Angles(0, -math.pi / 2, 0)

---------------------------------------------------------------------------------------------- 작은 부품
-- 널링 다이얼 (cf 의 +Z 가 운전자 쪽): 원통 + 둘레 홈 + 광택 캡 + 표시선
local function knurl(K: any, P: any, cf: CFrame, d: number, len: number, n: number?)
	K:cyl("KnurlDial", len, d, cf * CFrame.new(0, 0, len / 2) * ROT_X_TO_Z, P.alloy)
	local k = n or 12
	for i = 1, k do
		local a = (i / k) * math.pi * 2
		K:box("Knurl", Vector3.new(0.012, 0.018, len * 0.86), cf * CFrame.new(math.cos(a) * d / 2, math.sin(a) * d / 2, len / 2) * CFrame.Angles(0, 0, a), P.chrome)
	end
	K:cyl("KnurlCap", 0.012, d * 0.82, cf * CFrame.new(0, 0, len + 0.004) * ROT_X_TO_Z, P.gloss)
	K:box("KnurlMark", Vector3.new(0.012, d * 0.28, 0.006), cf * CFrame.new(0, d * 0.24, len + 0.012), P.seg)
end

-- 일반 공조 노브 (크롬 링 + 검은 노브 + 흰 표시선)
local function knob(K: any, P: any, cf: CFrame, d: number)
	K:cyl("KnobRing", 0.03, d + 0.04, cf * CFrame.new(0, 0, 0.015) * ROT_X_TO_Z, P.satin)
	K:cyl("Knob", 0.08, d, cf * CFrame.new(0, 0, 0.05) * ROT_X_TO_Z, P.hardDark)
	K:box("KnobMark", Vector3.new(0.014, d * 0.32, 0.008), cf * CFrame.new(0, d * 0.22, 0.094), P.markWhite)
end

-- 버튼 한 줄 (가운데 = 비상등이면 빨강)
local function buttonRow(K: any, P: any, cf: CFrame, n: number, bw: number, gap: number, hazardAt: number?)
	for i = 1, n do
		local x = (i - (n + 1) / 2) * (bw + gap)
		K:box("StackButton", Vector3.new(bw, 0.06, 0.035), cf * CFrame.new(x, 0, 0.018), if i == hazardAt then P.hazard else P.button)
	end
end

-- 송풍구 (세로형이면 프레임을 90° 돌려 날개가 세로)
local function vent(K: any, P: any, name: string, cf: CFrame, w: number, h: number, vertical: boolean?, look: any?)
	local L = look or { frame = P.chrome, duct = P.duct, slat = P.hard, knob = P.satin }
	if vertical then
		K:vent(name, cf * CFrame.Angles(0, 0, math.pi / 2), h, w, L, math.max(3, math.floor(w / 0.05)))
	else
		K:vent(name, cf, w, h, L, math.max(2, math.floor(h / 0.045)))
	end
end

-- 얇은 틀 (사각 테두리 4장)
local function frameRect(K: any, name: string, cf: CFrame, w: number, h: number, th: number, look: any)
	K:box(name, Vector3.new(w + th, th, 0.03), cf * CFrame.new(0, h / 2, 0), look)
	K:box(name, Vector3.new(w + th, th, 0.03), cf * CFrame.new(0, -h / 2, 0), look)
	K:box(name, Vector3.new(th, h, 0.03), cf * CFrame.new(w / 2, 0, 0), look)
	K:box(name, Vector3.new(th, h, 0.03), cf * CFrame.new(-w / 2, 0, 0), look)
end

---------------------------------------------------------------------------------------------- 몸체
local function body(K: any, F: any, P: any, S: any)
	local half: number = F.halfIn
	local width = half * 2 - 0.04
	local face: number, front: number = F.dashFace, F.dashFront
	local top: number, mid: number, bottom: number = F.dashTop, F.dashMidY, F.dashBottom
	-- 앞유리 안쪽 면이 대시 윗면 높이에서 지나는 z (그보다 앞으로는 아무것도 나가지 않게)
	local ws: Vector3 = F.wsLow
	local hiW: Vector3 = F.wsHigh
	local zTop = ws.Z + math.max(0, top - ws.Y) * (hiW.Z - ws.Z) / math.max(0.01, hiW.Y - ws.Y)
	local uf = math.max(front, zTop + 0.06)
	local upperY0 = mid + 0.12
	local lowerH = upperY0 - bottom
	K:box("DashLower", Vector3.new(width, lowerH, face - front - 0.08), CFrame.new(0, bottom + lowerH / 2, (front + face - 0.08) / 2), P.lower)
	K:cyl("DashLowerRoll", width, 0.22, CFrame.new(0, bottom + 0.11, face - 0.19), P.lower)
	-- 위 패드: 앞 모서리를 반지름 0.13 롤로 둥글게 (롤이 대시 면보다 튀어나오지 않게 면 안쪽에 둠)
	local rr = 0.13
	local upH = top - rr - upperY0
	K:box("DashUpper", Vector3.new(width, upH, face - uf), CFrame.new(0, upperY0 + upH / 2, (uf + face) / 2), P.soft)
	K:box("DashUpper", Vector3.new(width, rr, face - rr - uf), CFrame.new(0, top - rr / 2, (uf + face - rr) / 2), P.soft)
	K:cyl("DashRoll", width, rr * 2, CFrame.new(0, top - rr, face - rr), P.soft)
	-- 문 쪽 양끝도 둥글게 (세로 롤 + 위 모서리 공)
	for _, s in { -1, 1 } do
		local ex = s * (half - 0.14)
		K:seg("DashEndRoll", Vector3.new(ex, bottom + 0.1, face - 0.1), Vector3.new(ex, top - 0.13, face - 0.1), 0.26, P.soft)
		K:ball("DashEndRoll", 0.26, CFrame.new(ex, top - 0.13, face - 0.1), P.soft)
	end
	if S.trimMat ~= "plastic" then
		K:box("DashStitch", Vector3.new(width - 0.1, 0.01, 0.01), CFrame.new(0, top - rr + rr * 0.72, face - rr + rr * 0.72), P.stitch)
	end
	local zA, zB = zTop + 0.06, face - 0.12
	if zB - zA > 0.1 then
		K:box("DashDeck", Vector3.new(width, 0.08, zB - zA), CFrame.new(0, top - 0.04, (zA + zB) / 2), P.soft)
		if ws.Y < top - 0.05 and zA - ws.Z > 0.03 then
			-- 앞유리 아래 끝 ~ 상판 앞 끝 사이 틈: 앞이 낮고 뒤가 높은 경사로 덮기
			local h = top - ws.Y
			K:wedge("DashSlope", Vector3.new(width, h, zA - ws.Z), CFrame.new(0, ws.Y + h / 2, (ws.Z + zA) / 2), P.soft)
		end
		for i = -3, 3 do
			K:box("DefrostSlot", Vector3.new(0.34, 0.012, 0.05), CFrame.new(i * 0.55, top + 0.002, zA + 0.25), P.hardDark)
		end
		if S.speaker ~= "plain" then
			for _, s in { -1, 1 } do
				K:ell("Tweeter", Vector3.new(0.3, 0.025, 0.2), CFrame.new(s * (half - 0.45), top + 0.006, zA + 0.32), P.grille)
			end
		end
	end
	-- 무릎 패널 (운전석 쪽), 글로브박스 (조수석 쪽)
	local ds = F.side
	local cx = if F.console then F.console.x else 0
	K:rbox("KneePanel", Vector3.new(1.45, 0.42, 0.14), 0.065, CFrame.new(ds * 1.15, bottom - 0.12, face - 0.22) * CFrame.Angles(math.rad(-12), 0, 0), P.lower)
	local gIn = math.abs(cx) + 1.02
	local gw = math.clamp((half - 0.12) - gIn, 0.6, 1.25)
	local gx = -ds * (gIn + gw / 2)
	local gTop = if S.garnish == "metal_wood" then mid - 0.24 else mid - 0.1 -- 카니발: 내려간 우드 띠 밑으로
	local gBot = math.max(bottom + 0.06, gTop - 0.46)
	local gh = gTop - gBot
	local gy = (gTop + gBot) / 2
	if S.garnish == "waterfall" then
		-- 투싼: 아래층에 묻힌 매끈한 뚜껑(둥근 모서리, 서랍 틀 X) + 새틴 라인 밑 검은 손잡이 홈
		K:panel("GloveLid", gw, gh, 0.03, 0.07, CFrame.new(gx, gy, face - 0.065), P.lower)
		K:box("GlovePull", Vector3.new(0.3, 0.04, 0.02), CFrame.new(gx, gTop - 0.05, face - 0.04), P.hardDark)
	else
		for _, e in { { 0, gh / 2, gw, 0.012 }, { 0, -gh / 2, gw, 0.012 }, { gw / 2, 0, 0.012, gh }, { -gw / 2, 0, 0.012, gh } } do
			K:box("GloveGap", Vector3.new(e[3], e[4], 0.01), CFrame.new(gx + e[1], gy + e[2], face - 0.075), P.hardDark)
		end
		K:box("GloveHandle", Vector3.new(0.3, 0.035, 0.03), CFrame.new(gx, gy + gh / 2 - 0.08, face - 0.07), P.satin)
	end
	-- A필러 트림 (헤드라이너 천, 앞유리 안쪽으로)
	local wsHalf = (F.wsW or width) / 2
	local nOut = (hiW - ws):Cross(Vector3.xAxis).Unit
	if nOut.Z > 1e-4 or (math.abs(nOut.Z) <= 1e-4 and nOut.Y < 0) then
		nOut = -nOut -- 바깥 = 앞(-Z) · 위
	end
	for _, s in { -1, 1 } do
		local a = Vector3.new(s * (wsHalf - 0.1), ws.Y, ws.Z) - nOut * 0.17
		local b = Vector3.new(s * (wsHalf - 0.24), hiW.Y, hiW.Z) - nOut * 0.17
		-- 넓고 납작한 천 트림 (둥근 막대 X): 앞유리와 나란히, 바깥 끝은 문 유리 쪽으로 30° 접힘
		local along = (b - a).Unit
		local wx = (Vector3.xAxis - along * along.X).Unit
		local cf = CFrame.fromMatrix((a + b) / 2, wx, along:Cross(wx), along) * CFrame.Angles(0, 0, -s * math.rad(30))
		K:zbox("APillarTrim", Vector3.new(0.34, 0.09, (b - a).Magnitude + 0.1), 0.044, cf, P.pillar)
	end
end

---------------------------------------------------------------------------------------------- 공조
local function temps(K: any, P: any, cf: CFrame, dx: number, h: number)
	-- 좌우 온도 표시 (7세그먼트 "22")
	for _, s in { -1, 1 } do
		Gauges.digits(K, cf * CFrame.new(s * dx, 0, 0), 2, h, P.seg, "22")
	end
end

local function climate(K: any, F: any, P: any, S: any, cx: number, y: number, z: number)
	local kind: string = S.climate
	if kind == "knurl" then
		-- 쏘나타: 광택 띠 양 끝 다이아몬드 널링 온도 다이얼 + 가운데 버튼 줄 + 온도 숫자
		local cf = CFrame.new(cx, y, z) * CFrame.Angles(math.rad(-8), 0, 0)
		K:panel("ClimateStrip", 1.2, 0.22, 0.05, 0.1, cf, P.gloss)
		for _, s in { -1, 1 } do
			knurl(K, P, cf * CFrame.new(s * 0.47, 0, 0.025), 0.19, 0.07, 12)
		end
		buttonRow(K, P, cf * CFrame.new(0, -0.04, 0.025), 6, 0.1, 0.02, nil)
		temps(K, P, cf * CFrame.new(0, 0.05, 0.03), 0.22, 0.06)
	elseif kind == "hang" then
		-- G80: 우드 띠 아래 매달린 슬림 광택 패널 + 작은 화면 + 양끝 널링 금속 다이얼 + 터치 키
		local cf = CFrame.new(cx, y, z) * CFrame.Angles(math.rad(-10), 0, 0)
		K:panel("ClimateHang", 1.36, 0.2, 0.06, 0.09, cf, P.gloss)
		K:cyl("ClimateHangEdge", 1.2, 0.016, cf * CFrame.new(0, 0.1, 0.02), P.satin)
		local disp = cf * CFrame.new(0, 0.01, 0.032)
		K:panel("ClimateDisplay", 0.44, 0.1, 0.006, 0.03, disp, P.lcd)
		Screens.climate(K, disp * CFrame.new(0, 0, 0.006), 0.4, 0.06, P.accentColor)
		for _, s in { -1, 1 } do
			knurl(K, P, cf * CFrame.new(s * 0.56, 0, 0.03), 0.19, 0.08, 12)
			for i = 1, 3 do
				K:box("TouchKey", Vector3.new(0.05, 0.012, 0.004), cf * CFrame.new(s * (0.16 + i * 0.08), -0.04, 0.032), P.markWhite)
			end
		end
	elseif kind == "touch" then
		-- 투싼: 버튼 없는 평평한 터치 패널 (아이콘만)
		local cf = CFrame.new(cx, y, z) * CFrame.Angles(math.rad(-10), 0, 0)
		K:panel("ClimateTouch", 1.02, 0.2, 0.025, 0.07, cf, P.gloss)
		temps(K, P, cf * CFrame.new(0, 0.03, 0.015), 0.4, 0.06)
		for i = -3, 3 do
			K:box("TouchIcon", Vector3.new(if i == 0 then 0.08 else 0.04, 0.012, 0.004), cf * CFrame.new(i * 0.11, -0.06, 0.014), P.markWhite)
		end
		K:box("TouchDivider", Vector3.new(0.86, 0.004, 0.004), cf * CFrame.new(0, -0.032, 0.014), P.button)
		Screens.climate(K, cf * CFrame.new(0, 0.03, 0.016), 0.4, 0.05, P.accentColor)
	elseif kind == "touch_knobs" then
		-- 카니발: 광택 터치 공조 패널 + 작은 노브 2
		local cf = CFrame.new(cx, y, z) * CFrame.Angles(math.rad(-10), 0, 0)
		K:panel("ClimateTouch", 1.1, 0.15, 0.03, 0.06, cf, P.gloss)
		temps(K, P, cf * CFrame.new(0, 0.01, 0.017), 0.26, 0.055)
		for _, s in { -1, 1 } do
			K:cyl("SmallKnob", 0.05, 0.11, cf * CFrame.new(s * 0.46, 0, 0.04) * ROT_X_TO_Z, P.alloy)
		end
		for i = -2, 2 do
			K:box("TouchIcon", Vector3.new(0.04, 0.026, 0.004), cf * CFrame.new(i * 0.07, -0.05, 0.017), P.markWhite)
		end
	else -- dials3
		-- 레이 · 포터 · 쏠라티: 큰 다이얼 3개 (온도 · 풍량 · 모드) + A/C · 내기 버튼
		local cf = CFrame.new(cx, y, z) * CFrame.Angles(math.rad(-8), 0, 0)
		K:panel("ClimatePlate", 1.16, 0.34, 0.04, 0.1, cf, P.gloss)
		for i = -1, 1 do
			knob(K, P, cf * CFrame.new(i * 0.38, 0.04, 0.02), 0.19)
		end
		buttonRow(K, P, cf * CFrame.new(0, -0.12, 0.02), 4, 0.12, 0.04, nil)
	end
end

---------------------------------------------------------------------------------------------- 차종별 가운데
function Dash.build(K: any, F: any, P: any)
	local S = F.style
	body(K, F, P, S)
	local half: number = F.halfIn
	local width = half * 2 - 0.04
	local face: number = F.dashFace
	local top: number, mid: number, bottom: number = F.dashTop, F.dashMidY, F.dashBottom
	local ds = F.side
	local toC = -ds
	local con = F.console
	local cx = if con then con.x else 0
	local conTop: number = if con then con.top else bottom
	local ccf: CFrame = F.centerCF or CFrame.new(cx, top, face + 0.1)
	local cw: number, ch: number = F.centerW or 1, F.centerH or 0.4
	local scrY = ccf.Position.Y
	local amb = P.ambient

	local g: string = S.garnish
	if g == "line" then
		-- 쏘나타: 문에서 문까지 가는 새틴 크롬 라인 + 바로 아래 앰비언트 + 조수석 넓은 질감 패널
		local ly = mid + 0.1
		K:cyl("DashChromeLine", width - 0.12, 0.03, CFrame.new(0, ly, face + 0.012), P.trim)
		if amb then
			K:cyl("DashAmbient", width - 0.3, 0.02, CFrame.new(0, ly - 0.045, face + 0.012), amb)
		end
		local x0, x1 = cx + toC * 0.78, toC * (half - 0.25)
		K:panel("DashPanel", math.abs(x1 - x0), 0.22, 0.03, 0.09, CFrame.new((x0 + x1) / 2, ly - 0.2, face + 0.01), P.panel)
		-- 화면 바로 아래 가로 송풍구 2 + 가운데 비상등 (화면 턱 아래로, 가리지 않게)
		local vy = math.min(top - 0.24, scrY - ch / 2 - 0.19)
		for _, s in { -1, 1 } do
			vent(K, P, "CentreVent", CFrame.new(cx + s * 0.28, vy, face + 0.01), 0.44, 0.1)
		end
		K:box("Hazard", Vector3.new(0.09, 0.07, 0.04), CFrame.new(cx, vy, face + 0.03), P.hazard)
		-- 끝 송풍구 (날개 끝, 크롬 라인 위)
		for _, s in { -1, 1 } do
			vent(K, P, "SideVent", CFrame.new(s * (half - 0.38), ly + 0.17, face + 0.01), 0.46, 0.12)
		end
		-- 스택 둘레는 대시와 같은 소프트 패드: 위(AVN · 공조 폭 1.3) -> 아래는 콘솔 폭으로 좁아짐. 광택은 키 · 공조 띠만
		local ky = vy - 0.17
		local cyc = ky - 0.2
		local sTop, sMid = vy - 0.08, cyc - 0.13
		K:panel("StackBack", 1.3, sTop - sMid, 0.06, 0.1, CFrame.new(cx, (sTop + sMid) / 2, face), P.soft)
		if sMid > conTop then
			local lw = (if con then math.min(con.w, 1.15) else 0.9) + 0.06
			K:panel("StackLower", lw, sMid - conTop + 0.06, 0.06, 0.08, CFrame.new(cx, (sMid + conTop) / 2 + 0.03, face - 0.005), P.soft)
		end
		K:panel("AvnKeys", 1.0, 0.1, 0.04, 0.045, CFrame.new(cx, ky, face + 0.05), P.gloss)
		K:cyl("AvnTrim", 1.04, 0.016, CFrame.new(cx, ky - 0.062, face + 0.05), P.satin)
		buttonRow(K, P, CFrame.new(cx, ky, face + 0.06), 6, 0.11, 0.03, nil)
		for _, s in { -1, 1 } do
			-- 전원 · 볼륨(왼쪽) / 튜닝(오른쪽): 스택 면에 붙은 검은 노브 + 새틴 링 + 흰 표시선
			local kc = CFrame.new(cx + s * 0.56, ky, face + 0.04)
			K:cyl("AvnKnobRing", 0.03, 0.11, kc * CFrame.new(0, 0, 0.015) * ROT_X_TO_Z, P.satin)
			K:cyl("AvnKnob", 0.06, 0.085, kc * CFrame.new(0, 0, 0.045) * ROT_X_TO_Z, P.hardDark)
			K:box("AvnKnobMark", Vector3.new(0.01, 0.026, 0.006), kc * CFrame.new(0, 0.022, 0.077), P.markWhite)
		end
		climate(K, F, P, S, cx, cyc, face + 0.07)
	elseif g == "wood" then
		-- G80: 전폭 헤어라인 송풍구 (크롬 립) -> 앰비언트 -> 넓은 우드 띠 -> 아래 매달린 공조
		local sy = top - 0.2
		-- 슬롯 앞면을 대시 면에 맞춰 안으로 들어간 검은 틈 + 위 · 아래 크롬 립 2줄 = 한 줄 헤어라인 송풍구
		K:panel("HairlineVent", width - 0.3, 0.05, 0.06, 0.024, CFrame.new(0, sy, face - 0.028), P.duct)
		for _, ly in { sy + 0.035, sy - 0.035 } do
			K:cyl("HairlineLip", width - 0.32, 0.016, CFrame.new(0, ly, face + 0.012), P.chrome)
		end
		for _, x in { cx - 0.35, cx + 0.35, -(half - 0.55), half - 0.55 } do
			K:box("VentTab", Vector3.new(0.06, 0.035, 0.03), CFrame.new(x, sy, face + 0.025), P.satin)
		end
		local wy = sy - 0.2
		K:rbox("WoodBand", Vector3.new(width - 0.12, 0.24, 0.06), 0.028, CFrame.new(0, wy, face + 0.006), P.trim)
		K:cyl("WoodChrome", width - 0.14, 0.018, CFrame.new(0, wy - 0.13, face + 0.02), P.chrome)
		if amb then
			K:cyl("DashAmbient", width - 0.3, 0.018, CFrame.new(0, wy + 0.13, face + 0.02), amb)
		end
		local hy = wy - 0.26
		climate(K, F, P, S, cx, hy, face + 0.05)
		local sy0, sy1 = conTop, hy - 0.1
		if sy1 > sy0 then
			K:panel("StackBack", 1.2, sy1 - sy0, 0.08, 0.12, CFrame.new(cx, (sy0 + sy1) / 2, face - 0.01), P.soft)
		end
	elseif g == "waterfall" then
		-- 투싼: 피아노 블랙 세로 스택 (화면 + 양옆 세로 송풍구 + 터치 공조)
		local sw = cw + 0.5
		local conW: number = if con then math.min(con.w, 1.15) else 0.9
		local yJ = mid + 0.1 -- 여기서 스택이 콘솔 폭으로 좁아짐 (위 새틴 라인 바로 아래)
		local sy0, sy1 = conTop - 0.02, top + 0.04
		K:panel("CentreStack", sw, sy1 - yJ, 0.12, 0.14, CFrame.new(cx, (yJ + sy1) / 2, face + 0.04), P.gloss)
		K:panel("CentreStackLow", conW - 0.13, yJ + 0.1 - sy0, 0.11, 0.06, CFrame.new(cx, (yJ + 0.1 + sy0) / 2, face + 0.035), P.gloss)
		for _, s in { -1, 1 } do
			vent(K, P, "StackVent", CFrame.new(cx + s * (cw / 2 + 0.13), scrY, face + 0.11), 0.13, ch * 0.95, true, { frame = P.gloss, duct = P.duct, slat = P.hard, knob = P.satin })
		end
		climate(K, F, P, S, cx, scrY - ch / 2 - 0.17, face + 0.115)
		-- 새틴 두 줄: 문 -> 대시 -> 스택 옆에서 S자로 안쪽 · 아래로 흘러 콘솔 윗모서리로 합류 (워터폴)
		local zf, ze = face + 0.014, face - 0.067
		for i, ly in { mid + 0.13, mid + 0.05 } do
			for _, s in { -1, 1 } do
				local xin = cx + s * (sw / 2 + 0.04 + (i - 1) * 0.06)
				local xout = s * (half - 0.06)
				K:cyl("Garnish", math.abs(xout - xin), 0.026, CFrame.new((xin + xout) / 2, ly, zf), P.trim)
				K:ball("Garnish", 0.026, CFrame.new(xin, ly, zf), P.trim)
				local xe, ye = cx + s * (conW / 2 - 0.035), conTop + 0.04
				local prev = Vector3.new(xin, ly, zf)
				for k = 1, 5 do
					local t = k / 5
					local st = t * t * (3 - 2 * t)
					local p = Vector3.new(xin + (xe - xin) * st, ly + (ye - ly) * t, zf + (ze - zf) * st)
					K:seg("Garnish", prev, p, 0.026, P.trim, 0.02)
					prev = p
				end
			end
		end
		if amb then
			K:cyl("DashAmbient", half - sw / 2 - 0.2, 0.018, CFrame.new(toC * (half + sw / 2) / 2, mid + 0.09, face + 0.02), amb)
		end
		-- 숨은 슬롯 송풍구: 운전석 끝 + 조수석 쪽 긴 슬롯
		K:panel("SlotVent", 0.5, 0.05, 0.04, 0.024, CFrame.new(ds * (half - 0.38), mid + 0.24, face + 0.005), P.duct)
		K:panel("SlotVent", half - sw / 2 - 0.3, 0.045, 0.04, 0.022, CFrame.new(toC * (half + sw / 2) / 2, mid + 0.24, face + 0.005), P.duct)
	elseif g == "metal_wood" then
		-- 카니발 KA4: 화면 바로 아래 금속 띠(슬롯 송풍구 2 + 비상등, 양끝 슬롯) -> 우드 띠(가운데 인포 터치 띠) -> 공조 터치 띠
		-- 띠 윗면(my + 0.065)이 시선상 화면 아래 끝보다 아래여야 송풍구가 보임
		local scrBottom = math.min(F.clusterBottom or top, scrY - ch / 2)
		local my = math.min(top - 0.405, scrBottom - 0.21)
		K:rbox("MetalBand", Vector3.new(width - 0.12, 0.13, 0.05), 0.024, CFrame.new(0, my, face + 0.01), P.trim)
		for _, s in { -1, 1 } do
			vent(K, P, "CentreVent", CFrame.new(cx + s * 0.34, my, face + 0.03), 0.5, 0.06)
			vent(K, P, "SideVent", CFrame.new(s * (half - 0.42), my, face + 0.03), 0.5, 0.06)
		end
		K:box("Hazard", Vector3.new(0.08, 0.06, 0.04), CFrame.new(cx, my, face + 0.04), P.hazard)
		local wy = my - 0.115
		K:rbox("WoodBand", Vector3.new(width - 0.2, 0.1, 0.05), 0.022, CFrame.new(0, wy, face + 0.006), P.wood)
		if amb then
			K:cyl("DashAmbient", width - 0.3, 0.016, CFrame.new(0, my - 0.065, face + 0.03), amb)
		end
		-- 센터 페시아 몸체 (콘솔 윗면 ~ 우드 띠 윗면): 띠들이 0.08 들어간 하단 대시 면 앞에 떠 보이지 않게
		local fy0, fy1 = conTop, wy + 0.05
		if fy1 - fy0 > 0.05 then
			K:panel("StackBack", 1.24, fy1 - fy0, 0.12, 0.06, CFrame.new(cx, (fy0 + fy1) / 2, face - 0.03), P.hard)
		end
		-- 인포테인먼트 터치 띠: 우드 띠 가운데 (양끝 볼륨 · 튠 노브)
		local iy = wy
		K:panel("InfoTouch", 1.0, 0.08, 0.03, 0.035, CFrame.new(cx, iy, face + 0.04), P.gloss)
		for _, s in { -1, 1 } do
			K:cyl("InfoKnob", 0.05, 0.08, CFrame.new(cx + s * 0.42, iy, face + 0.07) * ROT_X_TO_Z, P.alloy)
		end
		for i = -2, 2 do
			K:box("TouchIcon", Vector3.new(0.04, 0.024, 0.004), CFrame.new(cx + i * 0.12, iy, face + 0.057), P.markWhite)
		end
		-- 공조 터치 띠: 인포 띠 아래 0.01 틈, 콘솔 윗면 위
		climate(K, F, P, S, cx, math.max(conTop + 0.115, iy - 0.125), face + 0.05)
	else
		-- 레이 · 포터 · 쏠라티: 가니시 없이 센터 스택(포드 / 페시아)
		local vk: string = S.vents
		if vk == "pod_v" then
			-- 레이: 메탈 베젤 돌출 포드. 위: 화면 + 양옆 세로 송풍구, 비상등, 대시 기어, 아래: 3다이얼 공조
			local pw = cw + 0.46
			local py0, py1 = math.max(bottom - 0.3, F.floorY + 0.7), top - 0.02
			K:panel("StackPod", pw, py1 - py0, 0.24, 0.16, CFrame.new(cx, (py0 + py1) / 2, face + 0.04), P.satin)
			K:panel("StackPodFace", pw - 0.07, py1 - py0 - 0.07, 0.03, 0.13, CFrame.new(cx, (py0 + py1) / 2, face + 0.16), P.hard)
			for _, s in { -1, 1 } do
				vent(K, P, "PodVent", CFrame.new(cx + s * (cw / 2 + 0.12), scrY, face + 0.17), 0.13, ch * 0.92)
			end
			local hz = scrY - ch / 2 - 0.08
			K:box("Hazard", Vector3.new(0.1, 0.06, 0.04), CFrame.new(cx, hz, face + 0.18), P.hazard)
			-- 대시 기어 레버 (직선 게이트 + 은색 테두리)
			local gy = hz - 0.27
			local gate = CFrame.new(cx, gy, face + 0.17)
			K:panel("GearGateRim", 0.29, 0.43, 0.02, 0.08, gate, P.satin)
			K:panel("GearGatePlate", 0.25, 0.39, 0.02, 0.07, gate * CFrame.new(0, 0, 0.006), P.gloss)
			K:panel("GearSlot", 0.035, 0.32, 0.01, 0.016, gate * CFrame.new(0, 0, 0.015), P.duct)
			local a = (gate * CFrame.new(0, 0.1, 0.02)).Position
			local b = a + Vector3.new(0, 0.08, 0.2)
			K:seg("GearStem", a, b, 0.04, P.alloy)
			K:ell("GearKnob", Vector3.new(0.13, 0.15, 0.13), CFrame.new(b + Vector3.new(0, 0.04, 0.02)), P.leather)
			K:box("GearButton", Vector3.new(0.04, 0.03, 0.03), CFrame.new(b + Vector3.new(0, 0.06, 0.085)), P.satin)
			climate(K, F, P, S, cx, py0 + 0.24, face + 0.17)
		else
			-- 포터 · 쏠라티: 센터페시아 (포터 = 화면 위 송풍구 2, 쏠라티 = 은색 프레임 + 양옆 사다리꼴 송풍구)
			local fw = cw + 0.6
			local fy0, fy1 = mid - (if vk == "trap_v" then 0.2 else 0.5), top - 0.04
			K:panel("Fascia", fw, fy1 - fy0, 0.14, 0.16, CFrame.new(cx, (fy0 + fy1) / 2, face + 0.02), P.hard)
			if vk == "trap_v" then
				K:panel("FasciaFrame", cw + 0.56, ch + 0.18, 0.02, 0.1, ccf * CFrame.new(0, 0, -0.035), P.satin)
				for _, s in { -1, 1 } do
					vent(K, P, "TrapVent", CFrame.new(cx + s * (cw / 2 + 0.13), scrY, face + 0.1) * CFrame.Angles(0, 0, math.rad(s * 7)), 0.14, ch * 0.9, true)
				end
			else
				for _, s in { -1, 1 } do
					vent(K, P, "TopVent", CFrame.new(cx + s * 0.27, scrY + ch / 2 + 0.14, face + 0.1), 0.42, 0.15)
				end
			end
			K:box("Hazard", Vector3.new(0.1, 0.06, 0.04), CFrame.new(cx, scrY - ch / 2 - 0.07, face + 0.1), P.hazard)
			climate(K, F, P, S, cx, scrY - ch / 2 - 0.3, face + 0.1)
		end
		-- 끝 송풍구 (둥근 사각 / 사각)
		for _, s in { -1, 1 } do
			local look = { frame = if vk == "pod_v" then P.gloss else P.satin, duct = P.duct, slat = P.hard, knob = P.satin }
			vent(K, P, "SideVent", CFrame.new(s * (half - 0.36), mid + 0.36, face + 0.01), if S.sideVent == "round" then 0.32 else 0.42, if S.sideVent == "round" then 0.26 else 0.22, false, look)
		end
	end

	-- 기타 -------------------------------------------------------------------------------------------
	local ex = S.extras or {}
	if ex.tray then
		-- 포터: 대시 위 전폭 수납 트레이 (테두리 + 바닥)
		local tw, td = width - 1.6, 0.5
		local tc = CFrame.new(toC * 0.35, top + 0.02, face - 0.42)
		K:box("TrayFloor", Vector3.new(tw, 0.02, td), tc, P.hardDark)
		frameRect(K, "TrayRim", tc * CFrame.Angles(math.rad(90), 0, 0), tw, td, 0.05, P.hard)
	end
	if ex.bins then
		-- 쏠라티: 대시 위 뚜껑 수납함 2 + 가운데 열린 트레이
		for _, s in { -1, 1 } do
			local bc = CFrame.new(cx + s * 0.7, top + 0.06, face - 0.42)
			K:rbox("DashBin", Vector3.new(0.9, 0.12, 0.5), 0.05, bc, P.hard)
			K:box("BinSeam", Vector3.new(0.86, 0.008, 0.008), bc * CFrame.new(0, 0.061, 0.2), P.hardDark)
			K:box("BinLatch", Vector3.new(0.12, 0.03, 0.03), bc * CFrame.new(0, 0.04, 0.26), P.satin)
		end
		K:box("DashTray", Vector3.new(0.42, 0.03, 0.42), CFrame.new(cx, top + 0.01, face - 0.4), P.hardDark)
	end
	if ex.siren then
		-- 119: 사이렌 · 경광등 · 확성 조작 박스 (스위치 2줄 + 표시등) + 무전기
		local sc = CFrame.new(cx + toC * 0.08, mid - 0.42, face + 0.14) * CFrame.Angles(math.rad(-12), 0, 0)
		K:rbox("SirenBox", Vector3.new(0.92, 0.28, 0.2), 0.05, sc, P.hardDark)
		local cols = { P.hazard, P.lampBlue, P.lampAmber, P.button, P.button, P.button }
		for r = 0, 1 do
			for i = 1, 6 do
				local x = -0.38 + (i - 1) * 0.152
				K:box("SirenSwitch", Vector3.new(0.09, 0.07, 0.04), sc * CFrame.new(x, 0.05 - r * 0.1, 0.11), if r == 0 then cols[i] else P.button)
				if r == 0 then
					K:box("SirenLed", Vector3.new(0.025, 0.012, 0.01), sc * CFrame.new(x, 0.105, 0.105), if i <= 3 then P.ledRed else P.ledGreen)
				end
			end
		end
		local rc = CFrame.new(cx + toC * 0.68, mid - 0.4, face + 0.12)
		K:rbox("Radio", Vector3.new(0.4, 0.14, 0.24), 0.04, rc, P.hardDark)
		K:box("RadioFace", Vector3.new(0.16, 0.06, 0.01), rc * CFrame.new(-0.08, 0.02, 0.125), P.lcd)
		K:rbox("RadioMic", Vector3.new(0.07, 0.22, 0.12), 0.03, CFrame.new(cx + toC * 0.95, mid - 0.38, face + 0.16), P.hardDark)
	end
	if S.key == "sonata_taxi" and F.kind ~= "police" then
		-- 개인택시 (순찰차 제외): 빈차표시등 + 운수종사자 자격증명
		local wsL: Vector3, wsH: Vector3 = F.wsLow, F.wsHigh
		local slope = (wsH.Y - wsL.Y) / math.max(0.01, wsH.Z - wsL.Z)
		-- 빈차등: 조수석 쪽 앞유리 바로 아래 대시 위, 빨간 LED "빈차" 면이 밖(-Z)을 봄 (안에서는 검은 뒷면 + 빨간 빛)
		local zs = math.min(face - 0.3, wsL.Z + (top + 0.34 - wsL.Y) / math.max(0.05, slope))
		local vc = CFrame.new(toC * 1.45, top + 0.087, zs)
		K:rbox("VacancySign", Vector3.new(0.64, 0.17, 0.09), 0.035, vc, P.hardDark)
		K:box("VacancyLed", Vector3.new(0.56, 0.11, 0.01), vc * CFrame.new(0, 0, -0.047), P.ledRed)
		Screens.plate(K, "VacancyText", vc * CFrame.new(0, 0, -0.058) * CFrame.Angles(0, math.pi, 0), 0.5, 0.1, { "빈차" }, Color3.fromRGB(255, 236, 230), true)
		-- 운수종사자 자격증명: 조수석 대시 앞면, 크롬 라인 바로 위 (뒷자리 승객 쪽을 봄)
		local idc = CFrame.new(toC * 1.3, mid + 0.2, face + 0.006)
		K:panel("DriverIdFrame", 0.38, 0.17, 0.012, 0.025, idc, P.gloss)
		K:box("DriverIdCard", Vector3.new(0.34, 0.13, 0.004), idc * CFrame.new(0, 0, 0.007), P.card)
		K:box("DriverIdPhoto", Vector3.new(0.075, 0.095, 0.003), idc * CFrame.new(-0.11, 0, 0.0095), P.cardPhoto)
		Screens.plate(K, "DriverIdText", idc * CFrame.new(0.045, 0, 0.012), 0.22, 0.1, { "운수종사자 자격증명", "개인택시" }, Color3.fromRGB(28, 36, 52), true)
	end
	if S.shifter == "dash_pod" then
		-- 쏠라티: 운전자 오른쪽 무릎 옆 대시 기어 포드 + 짧은 부츠 + 검은 노브
		local px = F.wheel.c.X + toC * 0.82
		local pc = CFrame.new(px, mid - 0.22, face + 0.14)
		K:rbox("GearPod", Vector3.new(0.4, 0.44, 0.3), 0.08, pc * CFrame.Angles(0, math.pi / 2, 0), P.hard)
		local a = (pc * CFrame.new(0, 0.05, 0.15)).Position
		K:ell("ShiftBoot", Vector3.new(0.2, 0.12, 0.2), CFrame.new(a), P.rubber)
		local b = a + Vector3.new(0, 0.26, 0.2)
		K:seg("ShiftStick", a, b, 0.04, P.metalDark)
		K:ball("ShiftKnob", 0.15, CFrame.new(b + Vector3.new(0, 0.03, 0.01)), P.hardDark)
	end
	return {}
end

Dash.REPLACES = { "Dash", "DashTop", "DashUpper", "DashLower", "VentBand", "VentSlot", "DashChrome", "WoodBand", "AmbientStrip", "ClimatePanel", "TempKnob", "ClimateKnob", "ClusterScreen", "ClusterHood", "NavScreen", "FloatingScreen", "Screen", "CentrePanel", "VerticalVent", "CornerVent", "Glovebox", "DashSpeaker", "StartButton", "SquareVent", "RadioPanel", "StackFrame", "TabletMount", "TabletScreen", "Gauges" }

return Dash

end

__defs["Fit"] = function()
-- GwangalliCarInterior/Fit: 기존 차 모델(build/kit/vehicles 규약)의 Interior 파트에서 실내 치수를 읽습니다.
-- 이름 우선 (WheelRim / WheelHub / Dash / DashTop / ClusterScreen / NavScreen / CentreConsole / SeatCushion /
-- SeatBack / Headrest / DoorTrim / Headliner / Carpet / Firewall / Pedal / RearViewMirror / SunVisor + 차체의
-- Windshield / BPillar), 없는 값은 차 크기에서 추정. 결과는 전부 차체(Underbody) 프레임 기준.
-- 읽기만 합니다 (아무것도 바꾸지 않음).

local Fit = {}

-- seat = { cush, cushSize, back?, backSize?, head?, x, z, y, w } (차체 기준)

local function localBox(U: CFrame, p: BasePart): (CFrame, Vector3)
	return U:ToObjectSpace(p.CFrame), p.Size
end

local function frameOf(model: Model): BasePart?
	local u = model:FindFirstChild("Underbody", true)
	if u and u:IsA("BasePart") then
		return u
	end
	local c = model:FindFirstChild("Chassis", true)
	if c and c:IsA("BasePart") then
		return c
	end
	return nil
end
Fit.frameOf = frameOf

local function avg(list: { Vector3 }): Vector3
	local s = Vector3.zero
	for _, v in list do
		s += v
	end
	return s / math.max(1, #list)
end

function Fit.run(model: Model): (any?, string?)
	local base = frameOf(model)
	if not base then
		return nil, "no Underbody/Chassis"
	end
	local interior = model:FindFirstChild("Interior")
	if not interior then
		return nil, "no Interior"
	end
	local U = base.CFrame
	local by: { [string]: { BasePart } } = {}
	for _, d in interior:GetDescendants() do
		if d:IsA("BasePart") then
			local t = by[d.Name]
			if not t then
				t = {}
				by[d.Name] = t
			end
			table.insert(t, d)
		end
	end
	local body: { [string]: { BasePart } } = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			local t = body[d.Name]
			if not t then
				t = {}
				body[d.Name] = t
			end
			table.insert(t, d)
		end
	end
	local function first(names: { string }, src: { [string]: { BasePart } }?): BasePart?
		for _, n in names do
			local t = (src or by)[n]
			if t and t[1] then
				return t[1]
			end
		end
		return nil
	end
	local F: any = { model = model, base = base, kind = model:GetAttribute("VehicleKind") or "sedan", interior = interior }

	-- 1) 핸들 -------------------------------------------------------------------------------------
	local rims = by.WheelRim or {}
	local hub = first({ "WheelHub" })
	if #rims < 3 and not hub then
		return nil, "no steering wheel anchors"
	end
	local pts = {}
	for _, r in rims do
		table.insert(pts, U:PointToObjectSpace(r.Position))
	end
	local c = if #pts > 0 then avg(pts) else U:PointToObjectSpace((hub :: BasePart).Position)
	local up, axis
	if #pts >= 6 then
		-- 림 조각 중 가장 높은 것 - 가장 낮은 것 = 핸들 평면의 위쪽
		local hi, lo = pts[1], pts[1]
		local left, right = pts[1], pts[1]
		for _, p in pts do
			if p.Y > hi.Y then
				hi = p
			end
			if p.Y < lo.Y then
				lo = p
			end
			if p.X < left.X then
				left = p
			end
			if p.X > right.X then
				right = p
			end
		end
		-- 같은 높이의 조각이 둘씩 있으니 평균
		local function meanNear(sel: Vector3, key: string): Vector3
			local acc = {}
			for _, p in pts do
				if math.abs((p :: any)[key] - (sel :: any)[key]) < 0.06 then
					table.insert(acc, p)
				end
			end
			return avg(acc)
		end
		hi, lo = meanNear(hi, "Y"), meanNear(lo, "Y")
		left, right = meanNear(left, "X"), meanNear(right, "X")
		up = (hi - lo).Unit
		local rx = (right - left).Unit
		axis = rx:Cross(up).Unit -- 운전자 쪽 (+Z 쪽)
		if axis.Z < 0 then
			axis = -axis
		end
	elseif hub then
		local hcf = U:ToObjectSpace(hub.CFrame)
		axis = hcf.LookVector
		if axis.Z < 0 then
			axis = -axis
		end
		up = hcf.UpVector
	else
		axis, up = Vector3.new(0, 0.4, 0.92).Unit, Vector3.new(0, 0.92, -0.4).Unit
	end
	local right = up:Cross(axis).Unit
	up = axis:Cross(right).Unit
	local R = 0.6
	if #pts >= 6 then
		local sum = 0
		for _, p in pts do
			sum += (p - c).Magnitude
		end
		R = (sum / #pts) / math.cos(math.pi / 8) -- 팔각형 조각 중심 -> 꼭짓점 반지름
	end
	F.wheel = { c = c, R = math.clamp(R, 0.45, 0.8), cf = CFrame.fromMatrix(c, right, up, axis) }
	F.side = if c.X < 0 then -1 else 1 -- 운전석 쪽 (좌핸들 = -X)

	-- 2) 실내 폭 / 바닥 / 천장 -------------------------------------------------------------------------
	local trims = by.DoorTrim or {}
	local halfIn = 2.5
	if #trims > 0 then
		local s = 0
		for _, t in trims do
			local lc, sz = localBox(U, t)
			s += math.abs(lc.Position.X) - sz.X / 2
		end
		halfIn = s / #trims
	end
	if #trims == 0 then
		-- 도어 트림이 없는 차(솔라티 등): 대시 / 바닥 폭으로
		local dsh = first({ "Dash", "DashUpper", "DashLower" })
		local flr = first({ "Carpet", "CabCarpet", "Floor" })
		halfIn = (dsh and dsh.Size.X / 2 - 0.02) or (flr and flr.Size.X / 2 - 0.02) or 2.5
	end
	F.halfIn = halfIn
	local carpet = first({ "Carpet", "CabCarpet", "Floor" })
	F.floorY = if carpet then U:PointToObjectSpace(carpet.Position).Y + carpet.Size.Y / 2 else c.Y - 1.9
	local liner = first({ "Headliner", "Ceiling" })
	if liner then
		local lc, sz = localBox(U, liner)
		F.roofY = lc.Position.Y - sz.Y / 2
		F.linerZ0, F.linerZ1 = lc.Position.Z - sz.Z / 2, lc.Position.Z + sz.Z / 2
		F.linerHalf = sz.X / 2
	else
		F.roofY = c.Y + 1.6
	end
	local doorZ0, doorZ1 = c.Z - 1.2, c.Z + 5
	if #trims > 0 then
		-- 문마다 DoorTrim 이 따로 있으면 전체 범위로
		doorZ0, doorZ1 = math.huge, -math.huge
		for _, t in trims do
			local lc, sz = localBox(U, t)
			doorZ0 = math.min(doorZ0, lc.Position.Z - sz.Z / 2)
			doorZ1 = math.max(doorZ1, lc.Position.Z + sz.Z / 2)
		end
		local lc, sz = localBox(U, trims[1])
		F.trimY0, F.trimY1 = lc.Position.Y - sz.Y / 2, lc.Position.Y + sz.Y / 2
	end
	if #trims == 0 then
		local pt = first({ "Partition" })
		if pt then
			doorZ1 = math.min(doorZ1, U:PointToObjectSpace(pt.Position).Z - pt.Size.Z / 2 - 0.05)
		end
	end
	F.doorZ0, F.doorZ1 = doorZ0, doorZ1
	local bp = first({ "BPillar" }, body)
	F.bZ = if bp then U:PointToObjectSpace(bp.Position).Z else nil

	-- 3) 대시보드 / 앞유리 -------------------------------------------------------------------------------
	local dash = first({ "Dash", "DashUpper", "DashLower" })
	if dash then
		local lc, sz = localBox(U, dash)
		F.dashFace = lc.Position.Z + sz.Z / 2 -- 실내 쪽 면
		F.dashFront = lc.Position.Z - sz.Z / 2
		F.dashMidY = lc.Position.Y
		F.dashBottom = lc.Position.Y - sz.Y / 2
		F.dashW = sz.X
	else
		F.dashFace = c.Z - 0.65
		F.dashFront = c.Z - 1.9
		F.dashMidY = c.Y - 0.25
		F.dashBottom = c.Y - 0.75
		F.dashW = halfIn * 2
	end
	for _, n in { "DashLower" } do
		local p = first({ n })
		if p then
			local lc, sz = localBox(U, p)
			F.dashBottom = math.min(F.dashBottom, lc.Position.Y - sz.Y / 2)
		end
	end
	local top = first({ "DashTop" })
	if top then
		local lc, sz = localBox(U, top)
		F.dashTop = lc.Position.Y + sz.Y / 2
	else
		F.dashTop = (F.dashMidY :: number) + 0.55
	end
	local ws = first({ "Windshield" }, body)
	if ws then
		local lc, sz = localBox(U, ws)
		local e1 = lc * Vector3.new(0, 0, sz.Z / 2)
		local e2 = lc * Vector3.new(0, 0, -sz.Z / 2)
		if sz.Y > sz.Z then -- 세워진 앞유리 (트럭): Y 축이 길이
			e1 = lc * Vector3.new(0, sz.Y / 2, 0)
			e2 = lc * Vector3.new(0, -sz.Y / 2, 0)
		end
		local lo, hi = if e1.Y < e2.Y then e1 else e2, if e1.Y < e2.Y then e2 else e1
		F.wsLow, F.wsHigh, F.wsW = lo, hi, sz.X
	else
		F.wsLow = Vector3.new(0, F.dashTop, F.dashFront)
		F.wsHigh = Vector3.new(0, F.roofY, c.Z)
		F.wsW = F.dashW
	end

	-- 4) 화면 / 콘솔 ----------------------------------------------------------------------------------
	local cl = first({ "ClusterScreen", "Gauges" })
	F.cluster = if cl then U:PointToObjectSpace(cl.Position) else Vector3.new(c.X, F.dashTop + 0.12, F.dashFace + 0.2)
	local nav = first({ "NavScreen", "FloatingScreen", "Screen", "TabletScreen" })
	F.nav = if nav then U:PointToObjectSpace(nav.Position) else Vector3.new(0, F.cluster.Y, F.cluster.Z + 0.1)
	F.navWide = nav and nav.Size.X or 1.3
	local con = first({ "CentreConsole", "FloorConsole" })
	if con then
		local lc, sz = localBox(U, con)
		F.console = { x = lc.Position.X, z0 = lc.Position.Z - sz.Z / 2, z1 = lc.Position.Z + sz.Z / 2, top = lc.Position.Y + sz.Y / 2, w = sz.X }
	end
	local arm = first({ "ConsoleArmrest" })
	if arm then
		local lc, sz = localBox(U, arm)
		F.consoleArm = { z0 = lc.Position.Z - sz.Z / 2, z1 = lc.Position.Z + sz.Z / 2, top = lc.Position.Y + sz.Y / 2, w = sz.X }
	end
	F.wood = by.WoodBand ~= nil or by.ConsoleWood ~= nil
	F.rotary = by.GearDial ~= nil or by.RotaryShifter ~= nil
	F.lever = by.GearLever ~= nil or by.GearKnob ~= nil
	F.taxi = by.TaxiMeter ~= nil

	-- 5) 좌석 ------------------------------------------------------------------------------------------
	local cush = by.SeatCushion or {}
	local backs = by.SeatBack or {}
	local heads = by.Headrest or {}
	local seats: { any } = {}
	for _, s in cush do
		local lc, sz = localBox(U, s)
		local p = lc.Position
		local rec: any = { cush = p, cushSize = sz, x = p.X, z = p.Z, y = p.Y, w = sz.X }
		-- 같은 x 근처의 등받이 / 헤드레스트
		local bestB, bd = nil, math.huge
		for _, b in backs do
			local bl = U:PointToObjectSpace(b.Position)
			local dd = math.abs(bl.X - p.X) + math.abs(bl.Z - p.Z) * 0.3
			if bl.Z > p.Z - 0.2 and dd < bd then
				bd, bestB = dd, b
			end
		end
		if bestB then
			local bl, bs = localBox(U, bestB)
			rec.back, rec.backSize = bl.Position, bs
		end
		local bestH, hd = nil, math.huge
		for _, h in heads do
			local hl = U:PointToObjectSpace(h.Position)
			local dd = math.abs(hl.X - p.X) + math.abs(hl.Z - p.Z) * 0.3
			if hl.Z > p.Z and dd < hd then
				hd, bestH = dd, hl
			end
		end
		rec.head = bestH
		table.insert(seats, rec)
	end
	table.sort(seats, function(a, b)
		return a.z < b.z
	end)
	local front, rear = {}, {}
	if #seats > 0 then
		local z0 = seats[1].z
		for _, s in seats do
			if s.z < z0 + 1.0 then
				table.insert(front, s)
			else
				table.insert(rear, s)
			end
		end
	end
	F.front, F.rear = front, rear
	-- 뒷좌석 헤드레스트 위치 (벤치는 하나로 되어 있음)
	F.rearHeads = {}
	for _, h in heads do
		local hl = U:PointToObjectSpace(h.Position)
		if #front > 0 and hl.Z > front[1].z + 2.2 then
			table.insert(F.rearHeads, hl)
		end
	end

	-- 6) 기타 -----------------------------------------------------------------------------------------
	F.pedals = {}
	for _, p in by.Pedal or {} do
		table.insert(F.pedals, U:PointToObjectSpace(p.Position))
	end
	local mir = first({ "RearViewMirror" })
	F.mirror = if mir then U:PointToObjectSpace(mir.Position) else nil
	local fw = first({ "Firewall" })
	F.firewallZ = if fw then U:PointToObjectSpace(fw.Position).Z else F.dashFront

	-- 7) 색 (차마다 원래 실내 색을 살림) --------------------------------------------------------------------
	local function colorOf(names: { string }, fallback: Color3): Color3
		local p = first(names)
		return if p then p.Color else fallback
	end
	F.colors = {
		seat = colorOf({ "SeatCushion", "SeatBack" }, Color3.fromRGB(30, 30, 32)),
		dash = colorOf({ "DashUpper", "Dash" }, Color3.fromRGB(26, 26, 28)),
		trim = colorOf({ "DoorTrim" }, Color3.fromRGB(30, 30, 32)),
		liner = colorOf({ "Headliner", "Ceiling" }, Color3.fromRGB(150, 150, 152)),
		accent = colorOf({ "AmbientStrip", "AmbientDoor" }, Color3.fromRGB(110, 170, 255)),
		wood = colorOf({ "WoodBand", "ConsoleWood" }, Color3.fromRGB(70, 50, 38)),
	}
	F.seatFabric = (by.SeatCushion and by.SeatCushion[1] and by.SeatCushion[1].Material == Enum.Material.Fabric) or false
	return F, nil
end

-- 디버그용 요약 (스크립트 속성 Debug = true 일 때 차 모델의 GwCabinFit 속성으로)
function Fit.summary(F: any): string
	local function v(p: Vector3?): string
		return if p then string.format("(%.2f,%.2f,%.2f)", p.X, p.Y, p.Z) else "nil"
	end
	local t = {
		string.format("half=%.2f floor=%.2f roof=%.2f side=%d", F.halfIn, F.floorY, F.roofY, F.side),
		string.format("dash face=%.2f front=%.2f top=%.2f mid=%.2f bot=%.2f w=%.2f", F.dashFace, F.dashFront, F.dashTop, F.dashMidY, F.dashBottom, F.dashW),
		"ws=" .. v(F.wsLow) .. v(F.wsHigh) .. string.format(" wsW=%.2f", F.wsW or 0),
		"wheel=" .. v(F.wheel.c) .. string.format(" R=%.2f", F.wheel.R) .. " axis=" .. v(F.wheel.cf.LookVector),
		"cluster=" .. v(F.cluster) .. " nav=" .. v(F.nav) .. string.format(" navW=%.2f", F.navWide),
		if F.console then string.format("console x=%.2f z=%.2f..%.2f top=%.2f w=%.2f", F.console.x, F.console.z0, F.console.z1, F.console.top, F.console.w) else "console=nil",
		if F.consoleArm then string.format("arm z=%.2f..%.2f top=%.2f w=%.2f", F.consoleArm.z0, F.consoleArm.z1, F.consoleArm.top, F.consoleArm.w) else "arm=nil",
		string.format("door z=%.2f..%.2f bZ=%s trimY=%s..%s liner=%s..%s lh=%s", F.doorZ0, F.doorZ1, tostring(F.bZ), tostring(F.trimY0), tostring(F.trimY1), tostring(F.linerZ0), tostring(F.linerZ1), tostring(F.linerHalf)),
	}
	for _, s in F.front do
		table.insert(t, string.format("front x=%.2f z=%.2f w=%.2f cush=%s size=%s", s.x, s.z, s.w, v(s.cush), v(s.cushSize)))
	end
	for _, s in F.rear do
		table.insert(t, string.format("rear x=%.2f z=%.2f w=%.2f cush=%s size=%s", s.x, s.z, s.w, v(s.cush), v(s.cushSize)))
	end
	table.insert(t, string.format("pedals=%d mirror=%s fw=%.2f wood=%s rotary=%s lever=%s taxi=%s", #F.pedals, v(F.mirror), F.firewallZ, tostring(F.wood), tostring(F.rotary), tostring(F.lever), tostring(F.taxi)))
	return table.concat(t, "\n")
end

return Fit

end

__defs["Gauges"] = function()
-- GwangalliCarInterior/Gauges: 실물 계기판 부품. 원형 게이지(눈금 · 형광 링 · 크롬 베젤 · 회전 바늘)와 7세그먼트 숫자
-- (속도 · 기어 · 공조 온도). 전부 파트라서 로블록스와 임시 스튜디오에서 똑같이 보이고, 바늘은 피벗째 돌고(setNeedle)
-- 숫자는 세그먼트 Transparency 만 바꿉니다(show).

local Gauges = {}

local ROT_X_TO_Z = CFrame.Angles(0, -math.pi / 2, 0)
-- 0 = 7시 반 방향, 최대 = 4시 반 방향 (시계 방향 270°)
local A0, A1 = math.rad(225), math.rad(-45)

-- 원형 게이지. frame: 게이지 중심 (차체 기준, +Z = 보는 사람 쪽), r: 반지름
-- opt = { analog: boolean?, ticks: number? (큰 눈금 간격 수), red: number? (빨간 구간 시작 비율), max: number,
--         look = { mark, red, ring, needle, cap, bezel } }
function Gauges.dial(K: any, frame: CFrame, r: number, opt: any): any
	local L = opt.look
	local analog = opt.analog == true
	if analog then
		K:ring("GaugeBezel", frame * CFrame.new(0, 0, 0.012), r + 0.018, 0.018, 14, L.bezel)
	else
		K:ring("GaugeArc", frame * CFrame.new(0, 0, 0.004), r, 0.016, 18, L.ring, A1, A0)
	end
	local n = opt.ticks or 12
	for i = 0, n * 2 do
		local major = i % 2 == 0
		if major or analog then
			local v = i / (n * 2)
			local a = A0 + (A1 - A0) * v
			local len = if major then (if analog then 0.07 else 0.05) else 0.035
			local th = if major then 0.017 else 0.01
			local rr = r - (if analog then 0.014 else 0.04) - len / 2
			local look = if opt.red and v >= opt.red - 1e-6 then L.red else L.mark
			K:box("GaugeTick", Vector3.new(len, th, 0.006), frame * CFrame.new(math.cos(a) * rr, math.sin(a) * rr, 0.006) * CFrame.Angles(0, 0, a), look)
		end
	end
	-- 바늘: 피벗의 +X 를 가리키게 만든 뒤 0 위치로 돌림
	-- (디지털 계기판은 가운데에 숫자가 있으니 링 가장자리의 짧은 바늘만)
	local lcf = frame * CFrame.new(0, 0, 0.02)
	local p, w = K:pivot("NeedlePivot", lcf, function()
		if opt.short then
			K:box("Needle", Vector3.new(r * 0.4, 0.026, 0.008), lcf * CFrame.new(r * 0.74, 0, 0), L.needle)
		else
			K:box("Needle", Vector3.new(r * 0.98, 0.026, 0.008), lcf * CFrame.new(r * 0.37, 0, 0), L.needle)
			K:cyl("NeedleCap", 0.024, math.max(0.07, r * 0.42), lcf * CFrame.new(0, 0, 0.01) * ROT_X_TO_Z, L.cap)
		end
	end)
	local g = { pivot = p, weld = w, cf = lcf, cur = A0, max = opt.max or 1, base = K.base }
	Gauges.setNeedle(g, 0, 1)
	return g
end

-- 바늘 값 (k = 따라가는 비율 0..1)
function Gauges.setNeedle(g: any, value: number, k: number)
	local t = A0 + (A1 - A0) * math.clamp(value / g.max, 0, 1)
	local nxt = g.cur + (t - g.cur) * k
	if math.abs(nxt - g.cur) < 1e-4 and k < 1 then
		return
	end
	g.cur = nxt
	local cf = g.cf * CFrame.Angles(0, 0, nxt)
	if g.weld then
		g.weld.C0 = cf
	else
		g.pivot.CFrame = g.base.CFrame * cf
	end
end

---------------------------------------------------------------------------------------------- 7세그먼트
-- 세그먼트: a 위, b 오른쪽 위, c 오른쪽 아래, d 아래, e 왼쪽 아래, f 왼쪽 위, g 가운데
local SEG_ORDER = { "a", "b", "c", "d", "e", "f", "g" }
local MAP: { [string]: string } = {
	["0"] = "abcdef",
	["1"] = "bc",
	["2"] = "abdeg",
	["3"] = "abcdg",
	["4"] = "bcfg",
	["5"] = "acdfg",
	["6"] = "acdefg",
	["7"] = "abc",
	["8"] = "abcdefg",
	["9"] = "abcdfg",
	P = "abefg",
	R = "eg",
	N = "ceg",
	D = "bcdeg",
	["-"] = "g",
	[" "] = "",
}

-- 숫자 n 자리 (frame = 전체 가운데, +X 방향으로 나열, 높이 h). static 이면 그 글자의 켜진 세그먼트만 만듦.
function Gauges.digits(K: any, frame: CFrame, n: number, h: number, look: any, static: string?): any
	local W = 0.56 * h
	local t = 0.15 * h
	local pitch = W + 0.24 * h
	local out = { segs = {}, last = static, t = look.t or 0 }
	for i = 1, n do
		local cx = (i - (n + 1) / 2) * pitch
		local on = if static then (MAP[string.sub(static, i, i)] or "") else "abcdefg"
		local segs = {}
		for _, s in SEG_ORDER do
			if string.find(on, s, 1, true) then
				local horiz = s == "a" or s == "d" or s == "g"
				local x = if horiz then 0 elseif s == "b" or s == "c" then W / 2 - t / 2 else -W / 2 + t / 2
				local y = if s == "a" then h / 2 - t / 2 elseif s == "d" then -h / 2 + t / 2 elseif s == "g" then 0 elseif s == "b" or s == "f" then h / 4 else -h / 4
				local size = if horiz then Vector3.new(W - 1.5 * t, t, 0.006) else Vector3.new(t, h / 2 - 1.3 * t, 0.006)
				segs[s] = K:box("Seg", size, frame * CFrame.new(cx + x, y, 0), look)
			end
		end
		out.segs[i] = segs
	end
	if not static then
		Gauges.show(out, "0")
	end
	return out
end

-- 오른쪽 맞춤으로 표시
function Gauges.show(d: any, str: string)
	if d.last == str then
		return
	end
	d.last = str
	local n = #d.segs
	local pad = string.rep(" ", math.max(0, n - #str)) .. string.sub(str, -n)
	for i = 1, n do
		local on = MAP[string.sub(pad, i, i)] or ""
		for s, p in d.segs[i] do
			p.Transparency = if string.find(on, s, 1, true) then d.t else 1
		end
	end
end

-- 방향지시 화살표 (Neon 웨지 2장): dir = -1 왼쪽 / 1 오른쪽
function Gauges.arrow(K: any, frame: CFrame, dir: number, size: number, look: any): { BasePart }
	-- 웨지(직각삼각형 기둥)를 얇게 세워서 frame 의 XY 평면에 직각 꼭짓점이 왼쪽 아래인 삼각형으로: 위 · 아래 두 장 = ▶
	local toXY = CFrame.Angles(0, -math.pi / 2, 0)
	local m = if dir < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
	local sz = Vector3.new(0.006, size * 0.5, size)
	local a = K:wedge("TurnArrow", sz, frame * CFrame.new(0, size * 0.25, 0) * m * toXY, look)
	local b = K:wedge("TurnArrow", sz, frame * CFrame.new(0, -size * 0.25, 0) * m * CFrame.Angles(math.pi, 0, 0) * toXY, look)
	return { a, b }
end

return Gauges

end

__defs["Glass"] = function()
-- GwangalliCarInterior/Glass: 차 유리를 검은 반투명 틴팅 + 반사로 (클라이언트 로컬, 서버·다른 플레이어에 영향 없음).
--   앞유리: 스모크 (Transparency 0.55, Reflectance 0.16) — 운전 시야 확보
--   옆·뒤·쿼터 유리: 검은 틴팅 (Transparency 0.3, Reflectance 0.24) — 밖에서 실내가 거의 안 보임
-- 운전석 시점에서는 GwangalliDrive 카메라가 유리 LocalTransparencyModifier 를 올려 조금 더 맑게 보입니다.

local Glass = {}

local ROLE: { [string]: string } = {
	Windshield = "ws",
	FrontGlass = "ws",
	RearGlass = "rear",
	RearWindow = "rear",
	BackGlass = "rear",
	SideGlass = "side",
	QuarterGlass = "side",
	DoorGlass = "side",
	CabGlass = "side",
	SideWindow = "side",
	Window = "side",
}

Glass.NAMES = ROLE

Glass.LOOK = {
	ws = { color = Color3.fromRGB(18, 22, 27), transparency = 0.55, reflectance = 0.16 },
	side = { color = Color3.fromRGB(8, 10, 13), transparency = 0.3, reflectance = 0.24 },
	rear = { color = Color3.fromRGB(8, 10, 13), transparency = 0.3, reflectance = 0.24 },
}

function Glass.roleOf(p: BasePart): string?
	local r = ROLE[p.Name]
	if not r and p:GetAttribute("Glass") == true then
		r = if p:GetAttribute("Windshield") == true then "ws" else "side"
	end
	return r
end

-- 유리 한 장 틴팅 (원래 반투명한 유리만: 주차장 블록 차의 불투명 앞유리 웨지는 그대로)
function Glass.tintOne(d: Instance): boolean
	if not d:IsA("BasePart") or not d.Parent or d.Parent.Name == "CabinAAA" then
		return false
	end
	local role = Glass.roleOf(d)
	if role and d.Transparency > 0.05 and d.Transparency < 0.95 and d:GetAttribute("GwTinted") ~= true then
		local look = Glass.LOOK[role]
		d.Material = Enum.Material.Glass
		d.Color = look.color
		d.Transparency = look.transparency
		d.Reflectance = look.reflectance
		d.CastShadow = false
		d:SetAttribute("GwTinted", true)
		return true
	end
	return false
end

-- 차 한 대의 유리를 틴팅. 반환: 바꾼 개수
function Glass.tint(model: Model): number
	local n = 0
	for _, d in model:GetDescendants() do
		if ROLE[d.Name] or d:GetAttribute("Glass") == true then
			if Glass.tintOne(d) then
				n += 1
			end
		end
	end
	return n
end

return Glass

end

__defs["Kit"] = function()
-- GwangalliCarInterior/Kit: 파트 조립 도구. 모든 좌표는 차체 프레임(Underbody) 기준 스터드:
-- +X = 오른쪽, +Y = 위, -Z = 앞 (Roblox 차량 규약). 파트는 전부 클라이언트 로컬, 질량 없음, 충돌·쿼리·터치 없음.
-- 두 가지 방식: anchored = true (주차된 차: 파트를 고정만 하고 용접 없음 -> 가장 가벼움) / false (움직이는 차:
-- 차체에 Weld). 회전하는 핸들은 피벗 파트에 붙고, 피벗만 움직이면 됩니다.
--   box / wedge / cyl / ball / ell(타원체: SpecialMesh Sphere) / seg(두 점 사이 원통) / ring(원환: 원통 n개)
--   rbox(모서리가 둥근 상자) / pivot(회전 피벗: 핸들) / slats(송풍구 날개)

local Kit = {}
Kit.__index = Kit

-- look = { c: Color3?, m: Enum.Material?, t: number? (Transparency), r: number? (Reflectance), shadow: boolean? }

local DEFAULT_COLOR = Color3.fromRGB(30, 30, 32)

function Kit.new(base: BasePart, parent: Instance, anchored: boolean?)
	local self = setmetatable({}, Kit)
	self.base = base
	self.anchored = anchored == true
	self.parent = parent
	self.count = 0
	self.budget = 70 -- 프레임당 생성 수 (그 이상이면 다음 프레임으로 양보)
	self.attach = base -- 지금 붙일 대상 (pivot 안에서 만들 때 바뀜)
	self.attachCF = CFrame.new() -- attach 의 차체 기준 CFrame
	self.parts = {} :: { BasePart }
	return self
end

-- 프레임 양보 (빌드 코루틴 안에서만)
function Kit:tick()
	self.count += 1
	if self.count % self.budget == 0 then
		task.wait()
	end
end

local function apply(p: BasePart, look: any?)
	local l: any = look or {}
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = l.shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = l.c or DEFAULT_COLOR
	p.Material = l.m or Enum.Material.SmoothPlastic
	p.Transparency = l.t or 0
	p.Reflectance = l.r or 0
end

-- lcf: 차체 기준 CFrame. 파트를 만들고 현재 attach 에 용접.
function Kit:make(class: string, name: string, size: Vector3, lcf: CFrame, look: any?, shape: Enum.PartType?): BasePart
	local p = Instance.new(class) :: BasePart
	if shape then
		(p :: Part).Shape = shape
	end
	p.Name = name
	apply(p, look)
	p.Size = size
	p.CFrame = self.base.CFrame * lcf
	if self.anchored and self.attach == self.base then
		p.Anchored = true
	else
		local w = Instance.new("Weld")
		w.Name = "CabinWeld"
		w.Part0 = self.attach
		w.Part1 = p
		w.C0 = self.attachCF:Inverse() * lcf
		w.C1 = CFrame.new()
		w.Parent = p
	end
	p.Parent = self.parent
	table.insert(self.parts, p)
	self:tick()
	return p
end

function Kit:box(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, size, lcf, look)
end

function Kit:wedge(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	return self:make("WedgePart", name, size, lcf, look)
end

-- 원통: 축 = lcf 의 X 축 (Roblox Cylinder 규약). len = 길이, d = 지름
function Kit:cyl(name: string, len: number, d: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(len, d, d), lcf, look, Enum.PartType.Cylinder)
end

function Kit:ball(name: string, d: number, lcf: CFrame, look: any?): BasePart
	return self:make("Part", name, Vector3.new(d, d, d), lcf, look, Enum.PartType.Ball)
end

-- 타원체 (쿠션·볼스터·헤드레스트·에어백 커버): SpecialMesh Sphere 는 파트 크기에 맞춰 늘어납니다
function Kit:ell(name: string, size: Vector3, lcf: CFrame, look: any?): BasePart
	local p = self:make("Part", name, size, lcf, look)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- 두 점 a, b (차체 기준) 사이 원통
function Kit:seg(name: string, a: Vector3, b: Vector3, d: number, look: any?, extra: number?): BasePart?
	local v = b - a
	local len = v.Magnitude
	if len < 1e-3 then
		return nil
	end
	local mid = (a + b) / 2
	local x = v / len
	local up = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return self:cyl(name, len + (extra or 0), d, CFrame.fromMatrix(mid, x, y, z), look)
end

-- 원환 (핸들 림·송풍구 테두리·스피커 링): frame 의 XY 평면, 반지름 R, 단면 지름 d, n 조각, a0..a1 (라디안)
function Kit:ring(name: string, frame: CFrame, R: number, d: number, n: number, look: any?, a0: number?, a1: number?, fat: ((number) -> number)?)
	local s0, s1 = a0 or 0, a1 or math.pi * 2
	local full = math.abs((s1 - s0) - math.pi * 2) < 1e-3
	local out = {}
	for i = 0, n - 1 do
		local t0 = s0 + (s1 - s0) * i / n
		local t1 = s0 + (s1 - s0) * (i + 1) / n
		local pa = frame * Vector3.new(math.cos(t0) * R, math.sin(t0) * R, 0)
		local pb = frame * Vector3.new(math.cos(t1) * R, math.sin(t1) * R, 0)
		local dd = if fat then d * fat((t0 + t1) / 2) else d
		local p = self:seg(name, pa, pb, dd, look, dd * 0.42)
		if p then
			table.insert(out, p)
		end
	end
	if not full then
		-- 열린 호의 끝은 둥글게
		self:ball(name, d, CFrame.new(frame * Vector3.new(math.cos(s0) * R, math.sin(s0) * R, 0)), look)
		self:ball(name, d, CFrame.new(frame * Vector3.new(math.cos(s1) * R, math.sin(s1) * R, 0)), look)
	end
	return out
end

-- 모서리가 둥근 상자 (lcf 의 X 축 방향 4개 모서리를 반지름 r 로): 상자 2개 + 원통 4개
function Kit:rbox(name: string, size: Vector3, r: number, lcf: CFrame, look: any?)
	r = math.min(r, size.Y / 2 - 1e-3, size.Z / 2 - 1e-3)
	if r <= 0.01 then
		return { self:box(name, size, lcf, look) }
	end
	local out = {}
	table.insert(out, self:box(name, Vector3.new(size.X, size.Y - 2 * r, size.Z), lcf, look))
	table.insert(out, self:box(name, Vector3.new(size.X, size.Y, size.Z - 2 * r), lcf, look))
	for _, sy in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(out, self:cyl(name, size.X, 2 * r, lcf * CFrame.new(0, sy * (size.Y / 2 - r), sz * (size.Z / 2 - r)), look))
		end
	end
	return out
end

-- 앞에서 보면 네 모서리가 둥근 판 (보는 방향 = cf 의 +Z): 폭 w, 높이 h, 두께 d, 모서리 반지름 r
-- (화면 베젤 · 송풍구 테두리 · 센터 스택 · 공조 패널 · 페달)
function Kit:panel(name: string, w: number, h: number, d: number, r: number, cf: CFrame, look: any?)
	return self:rbox(name, Vector3.new(d, h, w), math.min(r, w / 2 - 0.002, h / 2 - 0.002), cf * CFrame.Angles(0, -math.pi / 2, 0), look)
end

-- 위에서 보면 네 모서리가 둥근 판 (수평 판: 콘솔 상판 · 충전 패드 · 트레이): 폭 w(X), 길이 len(Z), 두께 t
function Kit:slab(name: string, w: number, len: number, t: number, r: number, cf: CFrame, look: any?)
	return self:rbox(name, Vector3.new(t, w, len), math.min(r, w / 2 - 0.002, len / 2 - 0.002), cf * CFrame.Angles(0, 0, math.pi / 2), look)
end

-- 길이 방향(Z)으로 긴 상자의 긴 모서리 4개를 둥글게 (콘솔 몸체 · 도어 패널 · 팔걸이)
function Kit:zbox(name: string, size: Vector3, r: number, cf: CFrame, look: any?)
	return self:rbox(name, Vector3.new(size.Z, size.Y, size.X), r, cf * CFrame.Angles(0, math.pi / 2, 0), look)
end

-- 캡슐 (두 점 사이 원통 + 양끝 공): 손잡이 · 레버 · 크롬 라인 끝
function Kit:capsule(name: string, a: Vector3, b: Vector3, d: number, look: any?)
	self:seg(name, a, b, d, look)
	self:ball(name, d, CFrame.new(a), look)
	self:ball(name, d, CFrame.new(b), look)
end

-- 회전 피벗: 이후 fn 안에서 만든 파트는 피벗에 붙습니다 (핸들처럼 통째로 돌릴 부품).
-- 반환: 피벗, 차체와의 Weld (고정 방식이면 nil: 피벗 CFrame 을 직접 바꿉니다)
function Kit:pivot(name: string, lcf: CFrame, fn: () -> ()): (BasePart, Weld?)
	local p = Instance.new("Part")
	p.Name = name
	apply(p, { t = 1 })
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.CFrame = self.base.CFrame * lcf
	local w: Weld? = nil
	if self.anchored then
		p.Anchored = true
	else
		local wl = Instance.new("Weld")
		wl.Name = "PivotWeld"
		wl.Part0 = self.base
		wl.Part1 = p
		wl.C0 = lcf
		wl.Parent = p
		w = wl
	end
	p.Parent = self.parent
	local prevA, prevCF = self.attach, self.attachCF
	self.attach, self.attachCF = p, lcf
	fn()
	self.attach, self.attachCF = prevA, prevCF
	return p, w
end

-- 송풍구: frame 중심, 폭 w, 높이 h; 모서리가 둥근 테두리(크롬) + 둥근 안쪽 덕트 + 가로 날개 n 개 + 조절 노브
function Kit:vent(name: string, frame: CFrame, w: number, h: number, look: any, n: number?)
	local th = 0.035
	local r = math.min(w, h) * 0.38
	self:panel(name .. "Rim", w + 2 * th, h + 2 * th, 0.05, r + th, frame * CFrame.new(0, 0, -0.01), look.frame)
	self:panel(name .. "Duct", w, h, 0.05, r, frame * CFrame.new(0, 0, 0.0), look.duct)
	local k = n or 4
	for i = 1, k do
		local y = -h / 2 + h * (i - 0.5) / k
		-- 둥근 덕트 안에 들어가도록 위아래 날개는 짧게
		local edge = math.abs(y) / (h / 2)
		local sw = (w - 0.03) * (if edge > 0.6 then 1 - (edge - 0.6) * 0.6 else 1)
		self:cyl(name .. "Slat", sw, 0.024, frame * CFrame.new(0, y, 0.03), look.slat)
	end
	self:cyl(name .. "Knob", 0.07, 0.045, frame * CFrame.new(0, 0, 0.05), look.knob)
end

return Kit

end

__defs["Lights"] = function()
-- GwangalliCarInterior/Lights: 실내등.
--   밤   앰비언트 발밑 조명 (차종 앰비언트 색, 앞 · 뒤 발밑) + 계기판 · 내비 화면 빛 (화면 앞으로 은은하게)
--   정차 내가 탄 차가 밤에 서 있으면 천장 실내등 + 맵램프 2개가 켜지고 렌즈가 빛남 (달리면 꺼짐)
-- 전부 그림자 없는 작은 Point / Spot / SurfaceLight 라서 가볍고, 실내가 있는 차(최대 3~4대)에만 생깁니다.

local Lights = {}

local WARM = Color3.fromRGB(255, 232, 200)
local SCREEN = Color3.fromRGB(170, 200, 255)

local function light(class: string, parent: Instance, color: Color3, brightness: number, range: number): Light
	local l = Instance.new(class) :: Light
	l.Color = color
	l.Brightness = brightness;
	(l :: any).Range = range
	l.Shadows = false
	l.Enabled = false
	l.Parent = parent
	return l
end

function Lights.build(K: any, F: any, P: any): any
	local L: any = { ambient = {}, dome = {}, screen = {}, lenses = {}, state = "" }
	for _, p in K.parts do
		local n = p.Name
		if n == "DomeLamp" then
			table.insert(L.dome, light("PointLight", p, WARM, 0.7, 7))
			table.insert(L.lenses, p)
		elseif n == "MapLamp" then
			local s = light("SpotLight", p, WARM, 0.8, 6) :: SpotLight
			s.Face = Enum.NormalId.Bottom
			s.Angle = 60
			table.insert(L.dome, s)
			table.insert(L.lenses, p)
		elseif n == "NavGlass" or n == "ClusterGlass" then
			local s = light("SurfaceLight", p, SCREEN, 0.6, 4) :: SurfaceLight
			s.Face = Enum.NormalId.Back
			s.Angle = 110
			table.insert(L.screen, s)
		end
	end
	-- 앰비언트 발밑 조명 (앰비언트가 있는 차종)
	if P.ambient then
		local floor: number = F.floorY
		local spots = {}
		for _, s in F.front do
			table.insert(spots, Vector3.new(s.x, floor + 0.45, F.dashFace + 0.35))
		end
		for _, s in F.rear do
			table.insert(spots, Vector3.new(s.x, floor + 0.35, s.z - s.cushSize.Z / 2 - 0.4))
		end
		for _, v in spots do
			local a = K:box("FootLight", Vector3.new(0.1, 0.1, 0.1), CFrame.new(v), { t = 1 })
			table.insert(L.ambient, light("PointLight", a, P.accentColor, 0.9, 4.5))
		end
	end
	return L
end

-- night: 밤이고 실내가 보이는 거리, dome: 내가 탄 차가 밤에 서 있음
function Lights.set(L: any, night: boolean, dome: boolean)
	local key = (if night then "n" else "d") .. (if dome then "1" else "0")
	if L.state == key then
		return
	end
	L.state = key
	for _, l in L.ambient do
		l.Enabled = night
	end
	for _, l in L.screen do
		l.Enabled = night
	end
	for _, l in L.dome do
		l.Enabled = dome
	end
	for _, p in L.lenses do
		if dome then
			p.Material = Enum.Material.Neon
			p.Color = WARM
		else
			p.Material = Enum.Material.SmoothPlastic
			p.Color = Color3.fromRGB(176, 174, 166)
		end
	end
end

return Lights

end

__defs["Screens"] = function()
-- GwangalliCarInterior/Screens: 화면 내용. 그림(지도 · 바다 · 도로 · 광안대교 · 경로 · 상단 바 · 독 아이콘 · 막대)은
-- 유리 바로 앞 얇은 Neon 파트로, 글자는 투명한 글자판 파트의 SurfaceGui 로 만듭니다. 그래서 로블록스에서는
-- 선명한 글자 + 빛나는 화면, 임시 스튜디오(SurfaceGui 를 간판 글자로만 그림)에서도 같은 자리에 같은 모습입니다.
-- 화면 유리 자체에는 SurfaceGui 를 붙이지 않습니다 (스튜디오 간판 판이 앞의 바늘·지도를 가리지 않게).

local Lighting = game:GetService("Lighting")

local Screens = {}

-- 글자판: 투명 파트(두께 0.01) + SurfaceGui (+Z 면 = 보는 쪽). lines 를 위에서부터 한 줄씩.
function Screens.plate(K: any, name: string, cf: CFrame, w: number, h: number, lines: { string }, color: Color3, bold: boolean?): { TextLabel }
	local p = K:box(name, Vector3.new(w, h, 0.01), cf, { t = 1 })
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Text"
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 420
	sg.LightInfluence = 0
	sg.Brightness = 1.5
	sg.MaxDistance = 45
	local out = {}
	local n = #lines
	for i, s in lines do
		local t = Instance.new("TextLabel")
		t.Name = "Line" .. i
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1 / n)
		t.Position = UDim2.fromScale(0, (i - 1) / n)
		t.Text = s
		t.TextScaled = true
		t.Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium
		t.TextColor3 = color
		t.Parent = sg
		table.insert(out, t)
	end
	sg.Parent = p
	return out
end

local function clockText(addMin: number?): string
	local m = math.floor(Lighting.ClockTime * 60 + (addMin or 0)) % (24 * 60)
	return string.format("%02d:%02d", math.floor(m / 60), m % 60)
end

local function etaText(): string
	return clockText(12) .. " 도착 · 2.1km"
end

-- 내비게이션 (광안리 지도). cf = 유리 가운데 (+Z = 보는 쪽), w × h = 화면 크기.
function Screens.nav(K: any, cf: CFrame, w: number, h: number, P: any): any
	local z = 0.012
	local function at(x: number, y: number, dz: number?): CFrame
		return cf * CFrame.new(x * w, y * h, z + (dz or 0))
	end
	local function bar(name: string, x: number, y: number, bw: number, bh: number, rot: number, look: any, dz: number?)
		K:box(name, Vector3.new(bw * w, bh * h, 0.004), at(x, y, dz) * CFrame.Angles(0, 0, math.rad(rot)), look)
	end
	-- 상단 안내 바 + 하단 독
	bar("NavTop", 0, 0.42, 0.98, 0.15, 0, P.mapUI)
	bar("NavDock", 0, -0.435, 0.98, 0.12, 0, P.mapUI)
	for k = 0, 4 do
		bar("NavIcon", -0.36 + k * 0.18, -0.435, 0.055, 0.08, 0, if k == 0 then P.mapRoute else P.mapIcon, 0.002)
	end
	-- 지도: 땅 · 바다 · 해변 · 광안대교 · 도로
	bar("MapLand", 0, 0.08, 0.98, 0.52, 0, P.mapLand)
	bar("MapSea", 0, -0.27, 0.98, 0.2, 0, P.mapSea)
	bar("MapBeach", 0, -0.165, 0.98, 0.025, 0, P.mapBeach, 0.001)
	-- 회전한 막대도 유리 안에 (오른쪽 끝 <= 0.47w, 왼쪽 끝 >= -0.49w)
	bar("MapBridge", 0.1, -0.26, 0.74, 0.022, -6, P.mapBridge, 0.002)
	for _, r in { { -0.01, -0.1, 0.96, 0.03, 0 }, { -0.14, 0.12, 0.62, 0.022, -14 }, { 0.26, 0.06, 0.022, 0.42, 6 }, { -0.33, 0.04, 0.018, 0.42, -4 }, { 0.04, 0.26, 0.86, 0.018, 3 } } do
		bar("MapRoad", r[1], r[2], r[3], r[4], r[5], P.mapRoad, 0.001)
	end
	-- 경로 + 내 위치
	bar("MapRoute", -0.12, -0.1, 0.5, 0.045, 0, P.mapRoute, 0.002)
	bar("MapRoute", 0.13, 0.03, 0.035, 0.3, 6, P.mapRoute, 0.002)
	bar("MapRoute", 0.2, 0.2, 0.18, 0.04, 3, P.mapRoute, 0.002)
	K:box("MapMe", Vector3.new(0.05 * h, 0.05 * h, 0.004), at(-0.36, -0.1, 0.003) * CFrame.Angles(0, 0, math.rad(45)), P.mapMe)
	-- 글자: 상단 안내 + 도착 정보
	local top = Screens.plate(K, "NavText", at(0.06, 0.42, 0.006), w * 0.8, h * 0.11, { "↱ 300m  광안해변로" }, Color3.fromRGB(235, 242, 250), true)
	local eta = Screens.plate(K, "NavEta", at(0.36, 0.3, 0.006), w * 0.22, h * 0.07, { etaText() }, Color3.fromRGB(200, 214, 230))
	return { top = top[1], eta = eta[1] }
end

-- 공조 표시 (작은 글자판): 온도 · 모드
function Screens.climate(K: any, cf: CFrame, w: number, h: number, accent: Color3): any
	Screens.plate(K, "ClimateText", cf, w, h, { "AUTO  22.0°  A/C" }, accent, true)
	return {}
end

-- 아날로그 계기판 가운데 LCD: 시계 · 기온 · 주행거리
function Screens.lcd(K: any, cf: CFrame, w: number, h: number): any
	local l = Screens.plate(K, "LcdText", cf, w, h, { clockText() .. "  24°C", "ODO 12,480" }, Color3.fromRGB(225, 236, 248))
	return { clock = l[1] }
end

-- 디지털 계기판 가운데 정보 (두 게이지 사이)
function Screens.info(K: any, cf: CFrame, w: number, h: number, brand: string): any
	local l = Screens.plate(K, "ClusterText", cf, w, h, { clockText() .. "  24°C", brand, "ODO 12,480 km" }, Color3.fromRGB(215, 228, 242))
	return { clock = l[1] }
end

-- 10 Hz: 시계 (바늘 · 숫자는 Gauges)
function Screens.update(s: any)
	local txt = clockText()
	if s.info and s.info.clock then
		local c = s.info.clock :: TextLabel
		local want = txt .. "  24°C"
		if c.Text ~= want then
			c.Text = want
		end
	end
	if s.nav and s.nav.eta then
		local e = s.nav.eta :: TextLabel
		local want = etaText()
		if e.Text ~= want then
			e.Text = want
		end
	end
end

return Screens

end

__defs["Seats"] = function()
-- GwangalliCarInterior/Seats: 좌석 (차종별 인서트 · 볼스터, Styles 참고). 앞좌석 = 레일 + 받침 + 쿠션(가운데 인서트 +
-- 양옆 볼스터 + 앞 롤) + 13° 기울어진 등받이(인서트 · 볼스터 · 어깨 롤 · 뒤판 · 맵포켓) + 크롬 기둥 헤드레스트 + 옆면
-- 파워시트 스위치 + 안전벨트 · 버클. 인서트: perf(쏘나타 세로 스티치) · quilt(G80 다이아몬드 퀼팅 나파) · hstitch(투싼 ·
-- 카니발 가로 섹션) · plain(레이) · fabric(택시 · 포터 · 쏠라티 천). 카니발 2열 = VIP 캡틴 시트(윙 헤드레스트 · 양쪽
-- 팔걸이 · 레그레스트), 쏠라티 = 안쪽 접이식 팔걸이. 뒷좌석 = 3인 벤치 + 등받이 3분할 + 헤드레스트 3 + 가운데 팔걸이.

local Seats = {}

local ROT_X_TO_Y = CFrame.Angles(0, 0, math.pi / 2)

local function quilt(K: any, frame: CFrame, w: number, h: number, look: any)
	-- 다이아몬드 퀼팅: 두 방향 대각선 스티치를 인서트 사각형(w × h) 안으로 잘라서 (볼스터 · 좌석 밖으로 삐져나오지 않게)
	local ang = math.rad(35)
	local ux, uy = math.sin(ang), math.cos(ang)
	local pitch = w / 3.5
	local n = math.ceil((w / 2 + (h / 2) * ux / uy) / pitch)
	for i = -n, n do
		local off = i * pitch
		for _, s in { -1, 1 } do
			local dx = s * ux
			-- 선 (off, 0) + t·(dx, uy) 를 |x| <= w/2, |y| <= h/2 로 자름
			local ta, tb = (-w / 2 - off) / dx, (w / 2 - off) / dx
			local t0 = math.max(-(h / 2) / uy, math.min(ta, tb))
			local t1 = math.min((h / 2) / uy, math.max(ta, tb))
			if t1 - t0 > 0.05 then
				local tm = (t0 + t1) / 2
				K:box("Quilt", Vector3.new(0.008, t1 - t0, 0.006), frame * CFrame.new(off + tm * dx, tm * uy, 0) * CFrame.Angles(0, 0, -s * ang), look)
			end
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

end

__defs["Styles"] = function()
-- GwangalliCarInterior/Styles: 차종별 실제 실내 사양 (현대·기아·제네시스 공식 자료 + 시승기 기준, 2019~2023 국내형).
-- 고르는 순서: 차 모델의 InteriorStyle 속성 (키 직접 지정) > CarModel 속성 / 모델 이름 > VehicleKind.
-- 새 차종을 넣을 때: 외부 모델에 CarModel = "Hyundai Sonata (DN8)" 처럼 이름만 있으면 같은 실내가 붙습니다.
--
--   wheel   핸들 스포크 (vee4: 쏘나타 4스포크 역V · u4: 투싼/카니발 아래 두 스포크가 가깝게 · two: G80 2스포크 ·
--           three: 레이 3스포크 · bus2: 포터 2스포크 버스형), hub 에어백 크기, paddles 패들시프트
--   cluster 계기판 (digital / analog 실물 바늘), hood 차양 (slim · short · none · deep · brow)
--   center  가운데 화면 (float 대시 위 태블릿 · flush G80 낮고 넓게 · stack 투싼 세로 스택 맨 위 ·
--           pod 레이 돌출 스택 · fascia 포터/쏠라티 센터페시아 · joined 카니발 한 장 유리)
--   vents · climate · shifter · console · garnish · speaker · seat · extras (차마다 다른 부분)

local Styles = {}

local function hex(s: string): Color3
	local h = string.gsub(s, "#", "")
	return Color3.fromRGB(tonumber(string.sub(h, 1, 2), 16) or 0, tonumber(string.sub(h, 3, 4), 16) or 0, tonumber(string.sub(h, 5, 6), 16) or 0)
end

local LIST: { [string]: any } = {}

-- 현대 쏘나타 DN8 (2019~2023): 스텔스 날개형 낮은 대시 + 문에서 문까지 새틴 크롬 라인, 12.3" 계기판 차양이
-- S자로 흘러 10.25" 플로팅 화면으로 이어짐, 화면 바로 아래 가로 송풍구 2개 + 비상등, 버튼식 P/R/N/D 세로 배열,
-- 다이아몬드 널링 온도 다이얼 2개, 4스포크(아래 두 스포크 역V) 핸들, 보스 스피커.
LIST.sonata = {
	key = "sonata",
	label = "Hyundai Sonata (DN8)",
	brand = "hyundai",
	wheel = { spokes = "vee4", hub = Vector3.new(0.5, 0.4, 0.18), sideTrim = true, lowerTrim = "satin", paddles = false },
	cluster = { kind = "digital", hood = "slim", w = 1.22, h = 0.44, speedMax = 260, rpmMax = 8 },
	center = { kind = "float", w = 1.02, h = 0.4 },
	sCurve = true,
	vents = "twin_h",
	sideVent = "slim",
	climate = "knurl",
	shifter = "buttons_col",
	console = "full",
	garnish = "line",
	speaker = "bose",
	seat = { insert = "perf", bolster = 1 },
	hud = true,
	startButton = true,
	ambient = true,
	trimMat = "alu",
	colors = {
		dash = hex("#1d1e20"),
		seat = hex("#232325"),
		stitch = hex("#4a4a4c"),
		trim = hex("#a9adb2"),
		liner = hex("#c8c4bc"),
		ambient = hex("#4aa3ff"),
		wheel = hex("#1a1a1a"),
	},
}

-- 쏘나타 LPi 택시 / 순찰차: 같은 대시에 아날로그 2눈 계기판(속도·RPM 바늘 + 4.2" LCD), 8" 화면,
-- 일반 6단 기어 레버 (버튼식 아님), 천/인조가죽 시트, 앰비언트 없음.
LIST.sonata_taxi = {
	key = "sonata_taxi",
	label = "Hyundai Sonata (DN8) LPi Taxi",
	brand = "hyundai",
	wheel = { spokes = "vee4", hub = Vector3.new(0.5, 0.4, 0.18), sideTrim = true, lowerTrim = "satin", paddles = false },
	cluster = { kind = "analog", hood = "slim", w = 1.22, h = 0.44, speedMax = 260, rpmMax = 8 },
	center = { kind = "float", w = 0.64, h = 0.37 }, -- 8" 디스플레이 오디오 (약 5:3, 단독 플로팅)
	sCurve = false, -- S자 연결은 12.3" 디지털 계기판 + 10.25" 패키지 전용
	vents = "twin_h",
	sideVent = "slim",
	climate = "knurl",
	shifter = "lever",
	console = "full",
	garnish = "line",
	speaker = "plain",
	seat = { insert = "fabric", bolster = 0.8 },
	hud = false,
	startButton = true,
	ambient = false,
	trimMat = "alu",
	colors = {
		dash = hex("#1d1e20"),
		seat = hex("#2a2b2e"),
		stitch = hex("#4a4a4c"),
		trim = hex("#9fa3a8"),
		liner = hex("#c8c4bc"),
		ambient = hex("#4aa3ff"),
		wheel = hex("#1c1c1d"),
	},
}

-- 제네시스 G80 RG3 (2020~2023): "여백의 미" 낮고 넓은 수평 대시, 전폭 한 줄 헤어라인 송풍구 + 크롬 립,
-- 오픈 포어 애쉬 우드 띠(문까지), 우드 아래 매달린 공조 패널 + 널링 금속 다이얼, 대시에 낮게 박힌 14.5" 초광폭 화면,
-- 짧은 가죽 차양의 12.3" 3D 계기판, 우드 콘솔 위 크롬 변속 다이얼 + 그 뒤 조그 다이얼, 2스포크 핸들 + 날개 엠블럼,
-- 다이아몬드 퀼팅 나파 시트 (블랙 대시 + 베이지 시트 투톤), 렉시콘 메탈 메쉬 스피커.
LIST.g80 = {
	key = "g80",
	label = "Genesis G80 (RG3)",
	brand = "genesis",
	wheel = { spokes = "two", hub = Vector3.new(0.62, 0.4, 0.2), sideTrim = false, paddles = true },
	cluster = { kind = "digital", hood = "short", w = 1.2, h = 0.42, speedMax = 260, rpmMax = 8 },
	center = { kind = "flush", w = 1.42, h = 0.5 },
	vents = "hairline",
	sideVent = "hairline",
	climate = "hang",
	shifter = "dial_wood",
	console = "full",
	garnish = "wood",
	speaker = "lexicon",
	seat = { insert = "quilt", bolster = 0.9 },
	hud = true,
	startButton = true,
	ambient = true,
	trimMat = "wood",
	colors = {
		dash = hex("#1b1a19"),
		lower = hex("#2a2826"),
		seat = hex("#cbb89a"),
		insert = hex("#d6c5a8"),
		stitch = hex("#a8916f"),
		trim = hex("#7d6650"),
		door = hex("#cbb89a"),
		liner = hex("#cfc7ba"),
		ambient = hex("#ffd7a0"),
		wheel = hex("#1c1b1a"),
	},
}

-- 현대 투싼 NX4 (2021~2023): 인터스페이스 대시, 차양 없는 10.25" 플로팅 계기판(유리판), 피아노 블랙 세로
-- 센터 스택 맨 위 10.25" 화면 + 양옆 세로 송풍구, 버튼 없는 터치 공조, 문에서 대시를 지나 스택 양옆으로 흘러내리는
-- 새틴 두 줄(워터폴), 숨은 슬롯 송풍구, 버튼식 P/R/N/D 가로 배열, 4스포크(아래 두 스포크가 가깝게 + 새틴).
LIST.tucson = {
	key = "tucson",
	label = "Hyundai Tucson (NX4)",
	brand = "hyundai",
	wheel = { spokes = "u4", hub = Vector3.new(0.6, 0.38, 0.18), sideTrim = false, lowerTrim = "satin", paddles = true },
	cluster = { kind = "digital", hood = "none", w = 1.12, h = 0.4, speedMax = 260, rpmMax = 8 },
	center = { kind = "stack", w = 1.0, h = 0.4 },
	vents = "stack_v",
	sideVent = "slot",
	climate = "touch",
	shifter = "buttons_row",
	console = "full",
	garnish = "waterfall",
	speaker = "bose",
	seat = { insert = "hstitch", bolster = 1 },
	hud = false,
	startButton = true,
	ambient = true,
	trimMat = "alu",
	colors = {
		dash = hex("#1c1c1e"),
		lower = hex("#34353a"),
		seat = hex("#232325"),
		stitch = hex("#6b6b70"),
		trim = hex("#b8bbc0"),
		liner = hex("#cfcbc4"),
		ambient = hex("#5aa8ff"),
		wheel = hex("#1a1a1a"),
	},
}

-- 기아 레이 TAM (2022 더 뉴 기아 레이): 박스형 서 있는 대시, 메탈 베젤 돌출 센터 스택(맨 위 8" 화면 + 양옆
-- 세로 송풍구 → 비상등 → 대시 기어 레버 → 3다이얼 공조), 콘솔 없는 워크스루 바닥, 작은 차양 아날로그 2눈 + 4.2" LCD,
-- 3스포크(아래 스포크 하이글로시) + 새 기아 로고, 둥근 사각 끝 송풍구.
LIST.ray = {
	key = "ray",
	label = "Kia Ray (TAM)",
	brand = "kia",
	wheel = { spokes = "three", hub = Vector3.new(0.44, 0.36, 0.17), sideTrim = false, lowerTrim = "gloss", paddles = false },
	cluster = { kind = "analog", hood = "deep", w = 1.06, h = 0.42, speedMax = 200, rpmMax = 8 },
	center = { kind = "pod", w = 0.84, h = 0.36 },
	vents = "pod_v",
	sideVent = "round",
	climate = "dials3",
	shifter = "dash_lever",
	console = "none",
	garnish = "none",
	speaker = "plain",
	seat = { insert = "plain", bolster = 0.6 },
	hud = false,
	startButton = true,
	ambient = false,
	trimMat = "black",
	colors = {
		dash = hex("#1a1a1b"),
		lower = hex("#232325"),
		seat = hex("#2b2b2d"),
		stitch = hex("#3a3a3c"),
		trim = hex("#0e0e10"),
		liner = hex("#c9c5bc"),
		ambient = hex("#4aa3ff"),
		wheel = hex("#1a1a1a"),
	},
}

-- 기아 카니발 KA4 (2021~2023): 12.3" 계기판 + 12.3" 내비가 한 장 유리(파노라믹), 계기판 쪽만 짧은 차양,
-- 화면 아래 금속 가니시 띠에 슬롯 송풍구 2 + 비상등, 그 아래 우드그레인 띠, 터치 인포테인먼트 · 공조 띠,
-- 높고 넓은 콘솔의 널링 변속 다이얼, 2열 VIP 캡틴 시트(윙 헤드레스트 · 레그레스트), 크렐 스피커.
LIST.carnival = {
	key = "carnival",
	label = "Kia Carnival (KA4)",
	brand = "kia",
	wheel = { spokes = "u4", hub = Vector3.new(0.6, 0.38, 0.18), sideTrim = false, lowerTrim = "gloss", paddles = true, hubShape = "trap", lowerV = true, icons = true },
	cluster = { kind = "digital", hood = "brow", w = 1.22, h = 0.44, speedMax = 260, rpmMax = 8 },
	center = { kind = "joined", w = 1.22, h = 0.44 },
	vents = "garnish",
	sideVent = "slot",
	climate = "touch_knobs",
	shifter = "dial",
	console = "full",
	garnish = "metal_wood",
	speaker = "krell",
	seat = { insert = "hstitch", bolster = 0.9, captains = true },
	consoleAmbient = false, -- 무드등은 크래시패드 · 도어 라인에만
	hud = false,
	startButton = true,
	ambient = true,
	trimMat = "alu",
	colors = {
		dash = hex("#1c1c1e"),
		seat = hex("#2a2a2c"),
		stitch = hex("#5c5c60"),
		trim = hex("#a7abb0"),
		wood = hex("#4a3a2e"),
		liner = hex("#c9c4ba"),
		ambient = hex("#9ec5ff"),
		wheel = hex("#1c1c1e"),
	},
}

-- 현대 포터 II (1톤 트럭): 캡오버의 서 있는 대시 + 전폭 평평한 수납 트레이, 차콜/회색 투톤 하드 플라스틱,
-- 둥근 차양 세미 아날로그 2눈 + 3.5" LCD, 센터페시아(위 송풍구 2 → 8" 화면 → 3다이얼 공조),
-- 버스처럼 눕힌 2스포크 큰 허브 핸들, 바닥에서 올라온 긴 수동 기어 + 고무 부츠, 3인 벤치 캡.
LIST.porter = {
	key = "porter",
	label = "Hyundai Porter II",
	brand = "hyundai",
	wheel = { spokes = "bus2", hub = Vector3.new(0.56, 0.48, 0.2), sideTrim = false, paddles = false },
	cluster = { kind = "analog", hood = "deep", w = 1.1, h = 0.44, speedMax = 180, rpmMax = 6 },
	center = { kind = "fascia", w = 0.84, h = 0.36 },
	vents = "top_rect",
	sideVent = "round",
	climate = "dials3",
	shifter = "manual",
	console = "none",
	garnish = "none",
	speaker = "plain",
	seat = { insert = "fabric", bolster = 0.5 },
	hud = false,
	startButton = false,
	ambient = false,
	trimMat = "plastic",
	extras = { tray = true },
	colors = {
		dash = hex("#3a3c40"),
		lower = hex("#6a6d72"),
		seat = hex("#45474b"),
		stitch = hex("#5a5c60"),
		trim = hex("#8a8d92"),
		door = hex("#6a6d72"),
		liner = hex("#c4c2bc"),
		ambient = hex("#4aa3ff"),
		wheel = hex("#2a2b2d"),
	},
}

-- 현대 쏠라티 H350 119 구급차 운전석: 깊고 서 있는 밴 대시 + 위에 뚜껑 달린 수납함, 은색 프레임 센터 스택(8" 화면 +
-- 양옆 세로 사다리꼴 송풍구 → 3다이얼), 깊은 차양 2눈 + LCD, 대시에 붙은 기어 포드(운전자 오른쪽 무릎 옆),
-- 4스포크 밴 핸들, 사이렌 · 경광등 조작 박스 + 무전기.
LIST.solati = {
	key = "solati",
	label = "Hyundai Solati H350 119",
	brand = "hyundai",
	wheel = { spokes = "u4", hub = Vector3.new(0.52, 0.4, 0.18), sideTrim = false, lowerTrim = nil, paddles = false },
	cluster = { kind = "analog", hood = "deep", w = 1.14, h = 0.46, speedMax = 180, rpmMax = 6 },
	center = { kind = "fascia", w = 0.84, h = 0.36 },
	vents = "trap_v",
	sideVent = "rect",
	climate = "dials3",
	shifter = "dash_pod",
	console = "none",
	garnish = "none",
	speaker = "plain",
	seat = { insert = "fabric", bolster = 0.5, armrest = true },
	hud = false,
	startButton = false,
	ambient = false,
	trimMat = "plastic",
	extras = { bins = true, siren = true },
	colors = {
		dash = hex("#2e2f31"),
		lower = hex("#5d6064"),
		seat = hex("#2b2b2d"),
		stitch = hex("#4a4a4c"),
		trim = hex("#8e9196"),
		door = hex("#5d6064"),
		liner = hex("#b8b8b2"),
		ambient = hex("#4aa3ff"),
		wheel = hex("#232325"),
	},
}

Styles.LIST = LIST

-- 이름 매칭 (소문자, 위에서부터: 택시·순찰차가 쏘나타보다 먼저)
local MATCH: { { string } } = {
	{ "taxi", "sonata_taxi" },
	{ "택시", "sonata_taxi" },
	{ "police", "sonata_taxi" },
	{ "경찰", "sonata_taxi" },
	{ "순찰", "sonata_taxi" },
	{ "g80", "g80" },
	{ "genesis", "g80" },
	{ "제네시스", "g80" },
	{ "rg3", "g80" },
	{ "sonata", "sonata" },
	{ "쏘나타", "sonata" },
	{ "소나타", "sonata" },
	{ "dn8", "sonata" },
	{ "tucson", "tucson" },
	{ "투싼", "tucson" },
	{ "nx4", "tucson" },
	{ "%f[%w]ray%f[%W]", "ray" },
	{ "레이", "ray", "kor" },
	{ "carnival", "carnival" },
	{ "카니발", "carnival" },
	{ "ka4", "carnival" },
	{ "%f[%w]porter%f[%W]", "porter" },
	{ "포터", "porter", "kor" },
	{ "solati", "solati" },
	{ "쏠라티", "solati" },
	{ "솔라티", "solati" },
	{ "h350", "solati" },
	{ "%f[%d]119%f[%D]", "solati" },
	{ "ambulance", "solati" },
	{ "구급", "solati" },
}

local KIND: { [string]: string } = {
	sedan = "sonata",
	taxi = "sonata_taxi",
	taxi_service = "sonata_taxi",
	police = "sonata_taxi",
	luxury = "g80",
	suv = "tucson",
	compact = "ray",
	van = "carnival",
	truck = "porter",
	ambulance = "solati",
}

-- 한글 낱말 경계: 앞뒤가 문자열 끝이거나 한글이 아닌 글자 ("기아 레이" O, "플레이어" · "트레이" · "서포터" X)
local function korWord(low: string, word: string): boolean
	local i = 1
	while true do
		local a, b = string.find(low, word, i, true)
		if not a then
			return false
		end
		local prev = if a > 1 then string.byte(low, a - 1) else nil
		local nxt = if b < #low then string.byte(low, b + 1) else nil
		if (prev == nil or prev < 0x80) and (nxt == nil or nxt < 0x80) then
			return true
		end
		i = b + 1
	end
end

local function byName(s: string?): string?
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local low = string.lower(s)
	for _, m in MATCH do
		local hit = if m[3] == "kor" then korWord(low, m[1]) else string.find(low, m[1]) ~= nil
		if hit then
			return m[2]
		end
	end
	return nil
end

-- 반환: 스타일 표 (공유 표이므로 바꾸지 말 것)
function Styles.resolve(model: Model, kind: string?): any
	local forced = model:GetAttribute("InteriorStyle")
	if type(forced) == "string" and LIST[forced] then
		return LIST[forced]
	end
	-- 택시·순찰차는 차종 이름보다 용도(VehicleKind)가 우선 (예: CarModel = "Hyundai Sonata (DN8)" + VehicleKind = "police")
	if kind == "taxi" or kind == "taxi_service" or kind == "police" then
		return LIST.sonata_taxi
	end
	local key = byName(model:GetAttribute("CarModel") :: any) or byName(model.Name) or (kind and KIND[kind]) or "sonata"
	return LIST[key] or LIST.sonata
end

return Styles

end

__defs["Trim"] = function()
-- GwangalliCarInterior/Trim: 도어 트림(앞·뒤 문마다: 모서리가 둥근 하단 · 중단(가죽 + 스티치) · 상단 패널, 차종별 가니시
-- (쏘나타 새틴 라인 · G80 우드 띠 · 투싼 새틴 두 줄 · 카니발 금속 띠), 앰비언트, 팔걸이 + 창문 스위치, IMS 메모리 버튼,
-- 손잡이 컵 + 캡슐형 크롬 핸들, 원형 스피커(보스 · 렉시콘 메탈 메쉬 · 크렐 배지), 맵포켓, 창틀 롤), B·C 필러 트림,
-- 헤드라이너 + 둥근 가장자리, 오버헤드 콘솔(맵램프 · SOS), 손잡이, 선바이저(화장 거울 커버), 룸미러(자동 감광),
-- 바닥 매트, 알루미늄 페달 + 고무 띠 + 풋레스트.

local Gauges = __require("Gauges")

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
	-- 팔걸이 + 창문 스위치
	-- 팔걸이: 그 문 쪽 좌석 쿠션 위 0.5 (팔꿈치 높이)
	local cushTop = y0 + lowH
	for _, s in (if front then F.front else F.rear) do
		if s.w >= 2.6 or (s.x < 0) == (side < 0) then
			cushTop = s.cush.Y + s.cushSize.Y / 2
		end
	end
	local armY = math.clamp(cushTop + 0.5, y0 + lowH + 0.02, math.max(y0 + lowH + 0.02, y1 - 0.62))
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
	K:ell("HandleCup", Vector3.new(0.06, 0.18, 0.46), CFrame.new(x + inward * 0.055, hy, hz), P.duct)
	K:capsule("DoorHandle", Vector3.new(x + inward * 0.085, hy + 0.01, hz - 0.14), Vector3.new(x + inward * 0.085, hy + 0.01, hz + 0.14), 0.05, P.chrome)
	K:box("LockTab", Vector3.new(0.05, 0.05, 0.08), CFrame.new(x + inward * 0.09, hy, hz + 0.27), P.button)
	-- IMS 시트 메모리 (1 · 2 · SET, 운전석 문)
	if driver and (S.key == "sonata" or S.key == "g80") then
		for i = 0, 2 do
			K:box("ImsButton", Vector3.new(0.03, 0.045, 0.07), CFrame.new(x + inward * 0.08, hy - 0.24, hz - 0.1 + i * 0.09), P.alloy)
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
		local oc = CFrame.new(0, roofY - 0.06, lz0 + 0.45)
		-- 아래에서 보면 네 모서리가 둥근 판 + 면에 묻힌 타원 렌즈 · 둥근 SOS (튀어나온 흰 타일 X)
		K:slab("OverheadConsole", 0.78, 0.5, 0.12, 0.16, oc, P.hard)
		for _, s in { -1, 1 } do
			K:ell("MapLamp", Vector3.new(0.2, 0.024, 0.13), oc * CFrame.new(s * 0.22, -0.06, 0.02), P.lampLens)
		end
		K:cyl("SOS", 0.016, 0.065, oc * CFrame.new(0, -0.064, 0.15) * CFrame.Angles(0, 0, math.pi / 2), P.hazard)
		K:box("RoofSwitch", Vector3.new(0.14, 0.02, 0.06), oc * CFrame.new(0, -0.065, -0.12), P.button)
		if F.style.key == "carnival" then
			-- 파워 슬라이딩 도어 좌 · 우 + 파워 테일게이트 (맵램프 앞 · 사이)
			for _, s in { -1, 1 } do
				K:box("SlideDoorSwitch", Vector3.new(0.1, 0.02, 0.07), oc * CFrame.new(s * 0.24, -0.065, -0.16), P.button)
			end
			K:box("TailgateSwitch", Vector3.new(0.1, 0.02, 0.07), oc * CFrame.new(0, -0.065, 0.04), P.button)
		end
		-- 실내등 (뒤)
		K:box("DomeLamp", Vector3.new(0.4, 0.02, 0.2), CFrame.new(0, roofY - 0.01, lz0 + llen * 0.6), P.lampLens)
		-- 손잡이 (조수석 + 뒤 양쪽)
		for _, g in { { -F.side, lz0 + 0.9 }, { -1, lz0 + llen * 0.7 }, { 1, lz0 + llen * 0.7 } } do
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
		K:box("VanityCover", Vector3.new(0.5, 0.012, 0.26), v * CFrame.new(-s * 0.1, -0.035, 0.04), P.pillar)
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
	if fz1 - fz0 > 0.5 then
		K:box("CabinCarpet", Vector3.new(half * 2 - 0.06, 0.04, fz1 - fz0), CFrame.new(0, floor + 0.005, (fz0 + fz1) / 2), P.carpet)
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
	for i = 1, #ped - 2 do
		-- 클러치: 브레이크와 같은 패드
		local c = CFrame.new(ped[i]) * CFrame.Angles(math.rad(-25), 0, 0)
		K:panel("ClutchPedal", 0.36, 0.28, 0.04, 0.08, c, P.alloy)
		K:seg("PedalArm", ped[i] + Vector3.new(0, 0.1, -0.05), ped[i] + Vector3.new(0, 0.62, -0.32), 0.05, P.metalDark)
	end
	if brake then
		local c = CFrame.new(brake) * CFrame.Angles(math.rad(-25), 0, 0)
		K:panel("BrakePedal", 0.44, 0.3, 0.04, 0.08, c, P.alloy)
		for i = -1, 1 do
			K:box("PedalRubber", Vector3.new(0.36, 0.035, 0.02), c * CFrame.new(0, i * 0.08, 0.025), P.rubber)
		end
		K:seg("PedalArm", brake + Vector3.new(0, 0.1, -0.05), brake + Vector3.new(0, 0.62, -0.32), 0.05, P.metalDark)
		-- 풋레스트
		local fx = brake.X + F.side * 0.55
		K:panel("FootRest", 0.3, 0.5, 0.04, 0.08, CFrame.new(fx, floor + 0.35, brake.Z - 0.1) * CFrame.Angles(math.rad(-40), 0, 0), P.alloy)
	end
	if gas then
		local c = CFrame.new(gas + Vector3.new(0, -0.05, 0)) * CFrame.Angles(math.rad(-35), 0, 0)
		K:panel("GasPedal", 0.26, 0.6, 0.04, 0.07, c, P.alloy)
		for i = -2, 2 do
			K:box("PedalRubber", Vector3.new(0.035, 0.5, 0.02), c * CFrame.new(i * 0.05, 0, 0.025), P.rubber)
		end
	end
	return {}
end

Trim.REPLACES = { "DoorTrim", "DoorTrimUpper", "Armrest", "AmbientDoor", "SpeakerGrille", "Headliner", "SunVisor", "RearViewMirror", "Pedal", "FloorMat", "Carpet", "CabCarpet" }

return Trim

end


local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = __require("Kit")
local Fit = __require("Fit")
local Glass = __require("Glass")
local Cockpit = __require("Cockpit")
local Dash = __require("Dash")
local Console = __require("Console")
local Seats = __require("Seats")
local Trim = __require("Trim")
local Styles = __require("Styles")
local Lights = __require("Lights")

local player = Players.LocalPlayer

-- 그래픽 품질 단계 (GwangalliQuality 가 있으면): 저사양 폰은 실내 1대, 절전 모드는 0대
local Quality: any = nil
task.spawn(function()
	local m = ReplicatedStorage:WaitForChild("GwangalliQuality", 10)
	if m and m:IsA("ModuleScript") then
		local ok, q = pcall(require, m)
		if ok and type(q) == "table" and type(q.pick) == "function" then
			Quality = q
		end
	end
end)

local CFG = {
	buildRadius = 52, -- 이 안의 가까운 차부터 실내 생성
	dropRadius = 72, -- 이 밖으로 나가면 실내 제거
	maxCabins = 3, -- 동시에 유지할 실내 수 (+ 내가 탄 차). 스크립트 속성 MaxCabins 로 바꿀 수 있음
	tintRadius = 180, -- 이 안에 들어온 차부터 유리 틴팅 (한 번만)
	liveRadius = 34, -- 이 안이면 핸들·계기판 실시간
	scanBatch = 2500, -- 처음 맵 스캔: 프레임당 인스턴스 수
	steerRatio = 14, -- 앞바퀴 각도 x 조향비 = 핸들 각도
	kinds = { sedan = true, taxi = true, taxi_service = true, police = true, luxury = true, suv = true, compact = true, van = true, truck = true, ambulance = true },
}

type Rec = {
	model: Model,
	base: BasePart?,
	cabin: any?,
	building: boolean,
	failed: string?,
	failedAt: number,
	tinted: boolean,
	moving: boolean, -- 고정(Anchored)인데 CFrame 으로 움직이는 차 (클라이언트 교통 등) -> 용접 방식
	lastPos: Vector3?,
	lastT: number?,
	still: number, -- 연속으로 멈춰 있던 LOD 단계 수 (지나가는 차에는 실내를 만들지 않음)
	intN: number, -- Interior 자손 수 (스트리밍이 끝났는지)
}

local cars: { [Model]: Rec } = {}
local destroyCabinRef: (Rec) -> () = function() end

---------------------------------------------------------------------------------------------------- 팔레트
-- 차종 스타일(Styles)의 실제 색. 가죽은 SmoothPlastic (Leather 재질 무늬는 가까이서 파충류 비늘처럼 보임).
-- 실내 파트는 그림자를 드리우지 않음 (지붕 · 차체가 이미 실내에 그림자를 드리우고, 큰 면의 그림자 계단 현상도 없앰)
local M = Enum.Material
local function lighten(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end
local function darken(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local function palette(F: any): any
	local S = F.style
	local C = S.colors
	local seat: Color3 = C.seat
	local dash: Color3 = C.dash
	local accent: Color3 = C.ambient
	local SP = M.SmoothPlastic
	local trim = if S.trimMat == "wood"
		then { c = C.trim, m = M.Wood }
		elseif S.trimMat == "alu" then { c = C.trim, m = M.Metal, r = 0.05 }
		elseif S.trimMat == "black" then { c = C.trim, m = SP, r = 0.15 }
		else { c = C.trim, m = SP }
	return {
		leather = { c = seat, m = SP },
		leatherInsert = { c = C.insert or darken(seat, 0.18), m = SP },
		fabricSeat = { c = C.insert or lighten(seat, 0.05), m = M.Fabric },
		fabricSide = { c = seat, m = SP },
		wheelLeather = { c = C.wheel, m = SP },
		wheelHub = { c = lighten(C.wheel, 0.05), m = SP },
		soft = { c = lighten(dash, 0.04), m = SP },
		lower = { c = C.lower or dash, m = SP },
		doorSoft = { c = C.door or lighten(dash, 0.07), m = SP },
		hard = { c = dash, m = SP },
		hardDark = { c = darken(dash, 0.5), m = SP },
		panel = { c = lighten(dash, 0.1), m = SP },
		gloss = { c = rgb(7, 7, 9), m = SP, r = 0.12 },
		glossMatte = { c = rgb(7, 7, 9), m = SP, r = 0.05 },
		aluKey = { c = rgb(104, 106, 110), m = M.Metal },
		screen = { c = rgb(4, 6, 10), m = M.Glass, r = 0.06 },
		lcd = { c = rgb(10, 18, 28), m = SP, r = 0.05 },
		dialFace = { c = rgb(14, 15, 18), m = SP },
		dialBack = { c = rgb(8, 9, 11), m = SP, r = 0.04 },
		satin = { c = rgb(150, 153, 158), m = M.Metal },
		chrome = { c = rgb(184, 188, 194), m = M.Metal, r = 0.14 },
		alloy = { c = rgb(176, 179, 184), m = M.Metal },
		metalDark = { c = rgb(58, 60, 64), m = M.Metal },
		trim = trim,
		wood = { c = C.wood or rgb(74, 58, 46), m = M.Wood },
		stitch = { c = C.stitch, m = SP },
		fabric = { c = C.liner, m = M.Fabric },
		pillar = { c = darken(C.liner, 0.38), m = M.Fabric },
		rubber = { c = rgb(20, 20, 22), m = M.Rubber },
		mat = { c = rgb(24, 24, 26), m = M.Carpet },
		carpet = { c = darken(C.lower or dash, 0.25), m = M.Carpet },
		duct = { c = rgb(6, 6, 7), m = SP },
		button = { c = rgb(34, 36, 40), m = SP, r = 0.04 },
		buttonLit = { c = rgb(225, 236, 255), m = M.Neon, t = 0.35 },
		hazard = { c = rgb(196, 28, 28), m = SP },
		startBtn = { c = rgb(170, 22, 24), m = SP, r = 0.08 },
		paddle = { c = rgb(72, 74, 78), m = M.Metal },
		grille = { c = rgb(16, 16, 18), m = M.DiamondPlate },
		mesh = { c = rgb(120, 124, 130), m = M.DiamondPlate },
		reflector = { c = rgb(200, 30, 20), m = M.Neon, t = 0.5 },
		lampLens = { c = rgb(176, 174, 166), m = SP, r = 0.05 },
		mirror = { c = rgb(34, 38, 44), m = M.Glass, r = 0.22 },
		belt = { c = rgb(20, 20, 22), m = M.Fabric },
		ambient = if S.ambient then { c = accent, m = M.Neon, t = 0.45 } else nil,
		accentColor = accent,
		-- 계기판 · 화면 (빛나는 부분)
		seg = { c = rgb(236, 242, 250), m = M.Neon, t = 0.05 },
		segAccent = { c = accent, m = M.Neon },
		turn = { c = rgb(16, 46, 26), m = SP },
		gaugeMark = { c = rgb(222, 230, 240), m = M.Neon, t = 0.1 },
		gaugeRed = { c = rgb(255, 58, 48), m = M.Neon },
		gaugeRing = { c = accent, m = M.Neon, t = 0.15 },
		needle = { c = rgb(255, 92, 36), m = M.Neon },
		needleCap = { c = rgb(28, 30, 34), m = SP, r = 0.1 },
		markWhite = { c = rgb(215, 222, 232), m = M.Neon, t = 0.35 },
		mapUI = { c = rgb(14, 18, 25), m = M.Neon },
		mapIcon = { c = rgb(58, 72, 92), m = M.Neon },
		mapLand = { c = rgb(30, 37, 47), m = M.Neon },
		mapSea = { c = rgb(16, 46, 84), m = M.Neon },
		mapBeach = { c = rgb(120, 104, 72), m = M.Neon },
		mapBridge = { c = rgb(190, 196, 206), m = M.Neon },
		mapRoad = { c = rgb(78, 90, 106), m = M.Neon },
		mapRoute = { c = accent, m = M.Neon },
		mapMe = { c = rgb(255, 255, 255), m = M.Neon },
		lampBlue = { c = rgb(40, 90, 230), m = SP },
		lampAmber = { c = rgb(230, 150, 30), m = SP },
		ledRed = { c = rgb(255, 40, 40), m = M.Neon },
		ledGreen = { c = rgb(60, 255, 110), m = M.Neon },
		card = { c = rgb(222, 226, 232), m = SP },
		cardPhoto = { c = rgb(96, 104, 118), m = SP },
		meterGlass = { c = rgb(16, 5, 5), m = SP, r = 0.1 },
	}
end

---------------------------------------------------------------------------------------------------- 차 찾기
local function track(m: Instance)
	if not m:IsA("Model") or cars[m] then
		return
	end
	local kind = m:GetAttribute("VehicleKind")
	if not CFG.kinds[kind] then
		return
	end
	local rec: Rec = { model = m, base = Fit.frameOf(m), cabin = nil, building = false, failed = nil, failedAt = 0, tinted = false, moving = false, still = 0, intN = -1 }
	-- 실내가 있던 차에서 복제된 모델(교통 시스템 템플릿)은 숨김 값을 원래대로 + 따라온 옛 실내 제거
	local old = m:FindFirstChild("CabinAAA")
	if old then
		old:Destroy()
	end
	local int = m:FindFirstChild("Interior")
	if int then
		for _, d in int:GetDescendants() do
			local t = d:GetAttribute("GwCabinT")
			if type(t) == "number" and d:IsA("BasePart") then
				d.Transparency = t
				d:SetAttribute("GwCabinT", nil)
			end
			local md = d:GetAttribute("GwCabinMD")
			if type(md) == "number" and d:IsA("SurfaceGui") then
				d.MaxDistance = md
				d:SetAttribute("GwCabinMD", nil)
			end
			if d:GetAttribute("GwCabinV") == true and d:IsA("GuiObject") then
				d.Visible = true
				d:SetAttribute("GwCabinV", nil)
			end
		end
	end
	cars[m] = rec
	-- 실내 스타일을 바꾸면(InteriorStyle 속성) 다음 단계에 새 스타일로 다시 만듦
	m:GetAttributeChangedSignal("InteriorStyle"):Connect(function()
		if cars[m] == rec then
			destroyCabinRef(rec)
		end
	end)
end

-- 차 찾기 1: 서버가 붙이는 태그 (GwangalliEnvironment discovery: 가장 바깥 LOD = "near" 모델 = 차의 Interior 에 "NearLOD").
-- 맵 전체를 훑지 않아서 가볍고, 스트리밍으로 들어오는 차도 태그 신호로 잡힙니다.
local function fromInterior(inst: Instance)
	if inst.Name == "Interior" and inst.Parent and inst.Parent:IsA("Model") then
		track(inst.Parent)
	end
end

local function scan()
	local stack: { Instance } = { Workspace }
	local n = 0
	while #stack > 0 do
		local node = table.remove(stack) :: Instance
		for _, c in node:GetChildren() do
			n += 1
			if c:IsA("Model") then
				if c:GetAttribute("VehicleKind") ~= nil then
					track(c)
				else
					table.insert(stack, c)
				end
			elseif c:IsA("Folder") then
				table.insert(stack, c)
			end
			if n % CFG.scanBatch == 0 then
				task.wait()
			end
		end
	end
end

for _, inst in CollectionService:GetTagged("NearLOD") do
	fromInterior(inst)
end
CollectionService:GetInstanceAddedSignal("NearLOD"):Connect(fromInterior)

-- 차 찾기 2: 새로 생기는 차 (내 차 호출, 택시 등)
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(function()
			if d.Parent and d:GetAttribute("VehicleKind") ~= nil then
				track(d)
			end
		end)
	elseif Glass.NAMES[d.Name] then
		-- 나중에 붙는 유리 (스트리밍 / 문 리빌드): 그 유리 한 장만
		local p = d.Parent
		local rec = p and (cars[p :: any] or (p.Parent and cars[p.Parent :: any]))
		if rec and rec.tinted then
			task.defer(Glass.tintOne, d)
		end
	end
end)

---------------------------------------------------------------------------------------------------- 실내 만들기 / 지우기
local REPLACES: { [string]: boolean } = { WheelRim = true, WheelHub = true, WheelSpoke = true, WheelBadge = true, WingBadge = true, KiaLogo = true }
for _, list in { Dash.REPLACES, Console.REPLACES, Seats.REPLACES, Trim.REPLACES } do
	for _, n in list do
		REPLACES[n] = true
	end
end

local function steerMotors(model: Model): { Motor6D }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 and string.find(d.Part1.Name, "^DriveHub") and d.C0.Position.Z < 0 then
			table.insert(out, d)
		end
	end
	return out
end

-- 이름이 달라 REPLACES 에 없는 옛 실내 파트도, 새 핸들 원판 · 대시 앞면 부피 안에 있으면 숨김
-- (택시 미터 · 경찰 장비처럼 게임 기능이 붙은 파트는 이름으로 유지)
local KEEP = { "Taxi", "Meter", "Police", "Siren", "Radio" }
local function insideNew(cab: any, p: Instance): boolean
	if not p:IsA("BasePart") then
		return false
	end
	for _, k in KEEP do
		if string.find(p.Name, k, 1, true) then
			return false
		end
	end
	local F = cab.fit
	local lp = cab.base.CFrame:PointToObjectSpace((p :: BasePart).Position)
	local w = F.wheel.cf:PointToObjectSpace(lp)
	if math.abs(w.Z) < 0.3 and Vector2.new(w.X, w.Y).Magnitude < F.wheel.R + 0.06 then
		return true
	end
	return math.abs(lp.X) < F.halfIn and lp.Y > F.dashBottom - 0.15 and lp.Y < F.dashTop + 0.5 and lp.Z > F.dashFront + 0.1 and lp.Z < F.dashFace + 0.35
end

local function hideOld(cab: any, d: Instance)
	if d:IsA("BasePart") and (REPLACES[d.Name] or insideNew(cab, d)) and not d:IsA("Seat") and not d:IsA("VehicleSeat") then
		if cab.hidden[d] == nil then
			cab.hidden[d] = d.Transparency
			d:SetAttribute("GwCabinT", d.Transparency) -- 복제되어도 원래 값을 알 수 있게
		end
		d.Transparency = 1
	elseif d:IsA("SurfaceGui") and d.Parent and (REPLACES[d.Parent.Name] or insideNew(cab, d.Parent)) and cab.guis[d] == nil then
		-- 옛 화면 글자: 보이는 거리를 0 으로 + 안의 글자 · 판을 Visible = false (Enabled 를 다루는 DetailLOD 와 겹치지 않고,
		-- 게임 스크립트가 글자를 계속 바꿔도 오류 없음). 복제되어도 원래 값을 알 수 있게 속성으로도 남김
		local g = d :: SurfaceGui
		cab.guis[g] = { g.MaxDistance }
		g:SetAttribute("GwCabinMD", g.MaxDistance)
		g.MaxDistance = 0.01
		for _, e in g:GetDescendants() do
			if e:IsA("GuiObject") and e.Visible then
				cab.guiVis[e] = true
				e:SetAttribute("GwCabinV", true)
				e.Visible = false
			end
		end
		-- 품질 설정 등이 MaxDistance 를 되돌리면 다시 끔
		table.insert(cab.conns, g:GetPropertyChangedSignal("MaxDistance"):Connect(function()
			if g.MaxDistance ~= 0.01 and cab.alive then
				cab.guis[g][1] = g.MaxDistance
				g:SetAttribute("GwCabinMD", g.MaxDistance)
				g.MaxDistance = 0.01
			end
		end))
	end
end

local function destroyCabin(rec: Rec)
	local cab = rec.cabin
	if not cab then
		return
	end
	rec.cabin = nil
	cab.alive = false
	for _, c in cab.conns do
		c:Disconnect()
	end
	for p, old in cab.hidden do
		if p.Parent then
			p.Transparency = old
			p:SetAttribute("GwCabinT", nil)
		end
	end
	for g, old in cab.guis do
		if g.Parent then
			g.MaxDistance = old[1]
			g:SetAttribute("GwCabinMD", nil)
		end
	end
	for e in cab.guiVis do
		if e.Parent then
			e.Visible = true
			e:SetAttribute("GwCabinV", nil)
		end
	end
	cab.folder:Destroy()
end

destroyCabinRef = destroyCabin

local function buildCabin(rec: Rec)
	rec.building = true
	rec.failed = nil
	local building_folder: Instance? = nil
	local ok, err = pcall(function()
		local F, why = Fit.run(rec.model)
		if not F then
			rec.failed = why
			rec.failedAt = os.clock()
			rec.model:SetAttribute("GwCabinError", why)
			return
		end
		F.style = Styles.resolve(rec.model, F.kind)
		rec.model:SetAttribute("GwCabinStyle", F.style.key)
		if script:GetAttribute("Debug") == true then
			rec.model:SetAttribute("GwCabinFit", Fit.summary(F))
		end
		local P = palette(F)
		local folder = Instance.new("Model")
		folder.Name = "CabinAAA"
		folder.Archivable = false -- 차가 복제되어도(교통 · 리그) 따라가지 않게
		folder:SetAttribute("GwSkinKeep", true) -- 임시 스튜디오: 실사 차체 스킨이 이 실내를 가리지 않게
		folder.Parent = rec.model -- 먼저 넣어서 70개씩 나눠 들어감 (한 프레임에 몰리지 않게)
		building_folder = folder
		-- 주차된(고정) 차는 용접 없이 고정 파트로: 가장 가볍고(물리 어셈블리를 건드리지 않음) 실제 로블록스에서도 싸요
		local anchored = F.base.Anchored and not rec.moving
		local K = Kit.new(F.base, folder, anchored)
		local cockpit = Cockpit.build(K, F, P)
		Dash.build(K, F, P)
		Console.build(K, F, P)
		Seats.build(K, F, P)
		Trim.build(K, F, P)
		local lights = Lights.build(K, F, P)
		if not rec.model.Parent or cars[rec.model] ~= rec then
			folder:Destroy()
			return
		end
		local ambient = {}
		for _, p in K.parts do
			if string.find(p.Name, "Ambient") then
				table.insert(ambient, p)
			end
		end
		local cab: any = {
			alive = true,
			folder = folder,
			fit = F,
			base = F.base,
			interior = F.interior,
			cockpit = cockpit,
			lights = lights,
			guiVis = {},
			hidden = {},
			guis = {},
			conns = {},
			ambient = ambient,
			anchored = anchored,
			builtCF = F.base.CFrame,
			motors = steerMotors(rec.model),
			steer = 0,
			lastScreen = 0,
			night = nil,
			parts = #K.parts,
		}
		-- 바뀐 기존 실내 파트 숨기기 (지우지 않음, 이 클라이언트에서만) + 나중에 들어오는 파트도
		for _, d in F.interior:GetDescendants() do
			hideOld(cab, d)
		end
		table.insert(cab.conns, F.interior.DescendantAdded:Connect(function(d)
			if cab.alive then
				hideOld(cab, d)
			end
		end))
		rec.cabin = cab
	end)
	if not ok then
		if building_folder then
			building_folder:Destroy()
		end
		rec.failed = tostring(err)
		rec.failedAt = os.clock()
		rec.model:SetAttribute("GwCabinError", tostring(err))
		warn("[CarInterior] " .. rec.model:GetFullName() .. ": " .. tostring(err))
	elseif rec.cabin then
		rec.model:SetAttribute("GwCabinParts", rec.cabin.parts)
	end
	rec.building = false
end

---------------------------------------------------------------------------------------------------- 내가 탄 차
local function myCar(): Rec?
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat then
		return nil
	end
	local node: Instance? = seat
	while node and node ~= Workspace do
		if node:IsA("Model") and cars[node :: Model] then
			return cars[node :: Model]
		end
		node = node.Parent
	end
	return nil
end

---------------------------------------------------------------------------------------------------- LOD 루프
local building = false
local lastRp: Vector3?, lastT = nil, 0
local function maxCabins(): number
	local a = tonumber(script:GetAttribute("MaxCabins"))
	if a then
		return a
	end
	if Quality then
		local ok, v = pcall(Quality.pick, { low = 1, mid = 2, high = CFG.maxCabins, saver = 0 })
		if ok and type(v) == "number" then
			return v
		end
	end
	return CFG.maxCabins
end

local function lodStep()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local cp = cam.CFrame.Position
	-- 카메라와 내 캐릭터 중 가까운 쪽 기준 (카메라를 멀리 돌려도 옆 차 실내가 사라지지 않게)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local rp = if root and root:IsA("BasePart") then root.Position else cp
	local fp = script:GetAttribute("FocusPoint") -- 디버그 / 미리보기: 이 위치도 '내 위치'로 취급
	if typeof(fp) == "Vector3" then
		rp = fp
	end
	local t = os.clock()
	-- 빠르게 지나가는 중이면(차를 몰고 달릴 때) 길가 차 실내는 새로 만들지 않음
	local camV = if lastRp and t > lastT then (rp - lastRp).Magnitude / (t - lastT) else 0
	lastRp, lastT = rp, t
	local mine = myCar()
	local list = {}
	for m, rec in cars do
		if not m.Parent then
			destroyCabin(rec)
			cars[m] = nil
			continue
		end
		-- 클라이언트 교통이 숨긴 정적 차 (TrafficCars 가 복제본을 대신 몰고 다님)
		local hs = m:GetAttribute("GwHideState")
		if hs == "hidden" or hs == "mixed" then
			destroyCabin(rec)
			continue
		end
		local base = rec.base
		if not base or not base.Parent or not base:IsDescendantOf(m) then
			rec.base = Fit.frameOf(m)
			base = rec.base
		end
		local cab = rec.cabin
		if cab and (cab.base ~= base or not cab.interior.Parent or cab.interior.Parent ~= m) then
			-- 탈 때 서버가 Interior 를 새로 복제했거나(Rig) 차체 파트가 바뀜: 다음 단계에 다시 만듦
			destroyCabin(rec)
			cab = nil
		elseif cab and #cab.motors == 0 then
			cab.motors = steerMotors(m) -- 조향 모터는 서버가 리그를 만들 때 생김
		end
		if base then
			local p = base.Position
			local d = math.min((p - cp).Magnitude, (p - rp).Magnitude)
			local v = if rec.lastPos and rec.lastT and t > rec.lastT then (p - rec.lastPos).Magnitude / (t - rec.lastT) else 0
			rec.lastPos, rec.lastT = p, t
			rec.still = if v < 8 then rec.still + 1 else 0
			if rec == mine then
				d = 0
			end
			if not rec.tinted and d < CFG.tintRadius then
				rec.tinted = true
				Glass.tint(m)
			end
			if cab and cab.anchored and (not base.Anchored or (p - cab.builtCF.Position).Magnitude > 0.05) then
				-- 고정 실내를 만든 뒤 차가 풀리거나(타서 운전 시작) 움직이면 용접 방식으로 다시
				rec.moving = rec.moving or base.Anchored
				destroyCabin(rec)
				cab = nil
			end
			if cab and d > CFG.dropRadius then
				destroyCabin(rec)
				cab = nil
			end
			-- 스트리밍 중인 Interior 는 다 들어온 뒤에 (자손 수가 두 번 연속 같을 때)
			local int = m:FindFirstChild("Interior")
			local n = if int then #int:GetDescendants() else 0
			local settled = n > 0 and n == rec.intN
			rec.intN = n
			local canBuild = rec == mine or (settled and rec.still >= 2 and camV < 25)
			if cab or (d < CFG.buildRadius and canBuild and (not rec.failed or t - rec.failedAt > 8)) then
				-- 이미 있는 실내는 순위 다툼에서 8 스터드 이득 (3·4등이 엎치락뒤치락해도 다시 만들지 않게)
				table.insert(list, { rec = rec, d = if cab then d - 8 else d })
			end
		elseif cab then
			destroyCabin(rec) -- 차체 파트가 스트리밍으로 빠짐
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	if list[1] then
		script:SetAttribute("Nearest", string.format("%s %.0f", list[1].rec.model.Name, list[1].d))
	end
	-- 가까운 순으로 maxCabins 개만 유지
	local maxC = maxCabins()
	for i, e in list do
		if i > maxC + (if mine then 1 else 0) then
			if e.rec.cabin and e.rec ~= mine then
				destroyCabin(e.rec)
			end
		elseif not e.rec.cabin and not e.rec.building and not building then
			building = true
			task.spawn(function()
				buildCabin(e.rec)
				building = false
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------- 실시간 (핸들 · 계기판 · 앰비언트)
local function isNight(): boolean
	local ov = script:GetAttribute("NightOverride") -- 미리보기 / 디버그
	if type(ov) == "boolean" then
		return ov
	end
	local t = Lighting.ClockTime
	return t >= 18.25 or t < 5.75
end

local function turnState(model: Model, base: BasePart): (boolean, boolean)
	local l, r = false, false
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and (d.Name == "Repeater" or d.Name == "TurnLamp") and d.Material == Enum.Material.Neon then
			if base.CFrame:PointToObjectSpace(d.Position).X < 0 then
				l = true
			else
				r = true
			end
		end
	end
	return l, r
end

RunService.RenderStepped:Connect(function(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local cp = cam.CFrame.Position
	local now = os.clock()
	local night = isNight()
	local mine = myCar()
	for _, rec in cars do
		local cab = rec.cabin
		local base = rec.base
		if not cab or not base then
			continue
		end
		local near = rec == mine or (base.Position - cp).Magnitude < CFG.liveRadius
		-- 앰비언트: 밤에만 빛남. 낮에는 Neon 이 아닌 어두운 같은 색 선 (낮에 형광등 막대처럼 보이지 않게)
		if cab.night ~= night then
			cab.night = night
			local acc: Color3 = cab.fit.style.colors.ambient
			for _, p in cab.ambient do
				p.Material = if night then Enum.Material.Neon else Enum.Material.SmoothPlastic
				p.Color = if night then acc else acc:Lerp(Color3.new(0, 0, 0), 0.6)
				p.Transparency = if night then 0.1 else 0
			end
		end
		-- 실내등: 밤 = 앰비언트 발밑 · 화면 빛, 내가 탄 차가 서 있으면 천장등 · 맵램프 (속성 DomeLights = 미리보기용 강제 켜기)
		local stopped = rec == mine and base.AssemblyLinearVelocity.Magnitude < 1.5
		Lights.set(cab.lights, night and (near or rec == mine), night and (stopped or script:GetAttribute("DomeLights") == true))
		if not near then
			continue
		end
		-- 핸들: 앞바퀴 조향 모터의 실제 각도 x 조향비
		local yaw = 0
		for _, m in cab.motors do
			if m.Parent then
				local _, ry = m.Transform:ToOrientation()
				yaw += ry
			end
		end
		if #cab.motors > 0 then
			yaw /= #cab.motors
		end
		local angle = math.clamp(yaw * CFG.steerRatio, -7.5, 7.5)
		if math.abs(angle - cab.steer) > 0.002 then
			cab.steer = angle
			local ck = cab.cockpit
			if ck.wheelWeld then
				ck.wheelWeld.C0 = ck.wheelCF * CFrame.Angles(0, 0, angle)
			else
				ck.wheelPivot.CFrame = base.CFrame * ck.wheelCF * CFrame.Angles(0, 0, angle)
			end
		end
		-- 계기판: 바늘은 매 프레임 부드럽게, 숫자 · 방향지시 · 시계는 10 Hz. 주차된 차는 시동 꺼짐 (P, 0 rpm)
		local slow = now - cab.lastScreen > 0.1
		if slow then
			cab.lastScreen = now
		end
		local running = rec == mine
		local kmh = if running then base.AssemblyLinearVelocity:Dot(base.CFrame.LookVector) * 1.08 else 0 -- 1 stud = 0.3 m
		local gear = if running then (if kmh < -0.8 then "R" else "D") else "P"
		local spd = math.abs(kmh)
		local rpm = if not running then 0 elseif spd < 0.5 then 780 else 900 + (spd % 40) / 40 * 3600 + math.min(spd, 40) * 18
		local tl, tr = false, false
		if slow and running then
			tl, tr = turnState(rec.model, base)
		end
		Cockpit.live(cab.cockpit, { kmh = kmh, rpm = rpm, gear = gear, turnL = tl, turnR = tr }, math.min(1, dt * 8), slow)
	end
end)

---------------------------------------------------------------------------------------------------- 시작
task.spawn(function()
	-- 태그가 없는 빌드(서버 discovery 가 꺼진 place)에서만 맵을 나눠서 훑음
	local t0 = os.clock()
	while next(cars) == nil and os.clock() - t0 < 20 do
		task.wait(1)
	end
	if next(cars) == nil then
		scan()
	end
	local n = 0
	for _ in cars do
		n += 1
	end
	print(string.format("[CarInterior] ready: %d cars (tinted glass, AAA cabins near the camera)", n))
	while true do
		local ok, err = pcall(lodStep)
		if not ok then
			warn("[CarInterior] " .. tostring(err))
		end
		local nc = 0
		for _, rec in cars do
			if rec.cabin then
				nc += 1
			end
		end
		script:SetAttribute("Cabins", nc)
		task.wait(0.35)
	end
end)
