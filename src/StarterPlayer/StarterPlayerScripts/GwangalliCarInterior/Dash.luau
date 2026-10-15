--!strict
-- GwangalliCarInterior/Dash: 대시보드 (차종별, Styles 참고).
--   공통   상단 패드 + 둥근 앞 모서리 + 앞유리까지 덮는 상판(성에 제거 슬롯 · 트위터), 하단 패널(투톤), 무릎 패널,
--          글로브박스, A필러 트림
--   가니시 line(쏘나타 문~문 새틴 크롬 + 앰비언트 + 조수석 질감 패널) · wood(G80 헤어라인 송풍구 + 우드 띠) ·
--          waterfall(투싼 새틴 두 줄이 스택 양옆으로 흘러내림) · metal_wood(카니발 금속 띠 슬롯 송풍구 + 우드그레인)
--   스택   쏘나타 좁은 스택(가로 송풍구 2 + 비상등 + AVN 키 + 널링 다이얼 공조) · G80 우드 아래 매달린 공조 ·
--          투싼 피아노 블랙 세로 스택(세로 송풍구 + 터치 공조) · 레이 메탈 베젤 돌출 포드(대시 기어 레버 + 3다이얼) ·
--          카니발 터치 띠 · 포터 센터페시아(위 송풍구 + 3다이얼) · 쏠라티 은색 프레임 스택(사다리꼴 송풍구 + 3다이얼)
--   기타   포터 대시 위 수납 트레이, 쏠라티 뚜껑 수납함 + 사이렌 · 경광등 조작 박스 + 무전기 + 대시 기어 포드

local Screens = require(script.Parent:WaitForChild("Screens"))
local Gauges = require(script.Parent:WaitForChild("Gauges"))

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
	local gTop = mid - 0.1
	local gBot = math.max(bottom + 0.06, gTop - 0.46)
	local gh = gTop - gBot
	local gy = (gTop + gBot) / 2
	for _, e in { { 0, gh / 2, gw, 0.012 }, { 0, -gh / 2, gw, 0.012 }, { gw / 2, 0, 0.012, gh }, { -gw / 2, 0, 0.012, gh } } do
		K:box("GloveGap", Vector3.new(e[3], e[4], 0.01), CFrame.new(gx + e[1], gy + e[2], face - 0.075), P.hardDark)
	end
	K:box("GloveHandle", Vector3.new(0.3, 0.035, 0.03), CFrame.new(gx, gy + gh / 2 - 0.08, face - 0.07), P.satin)
	-- A필러 트림 (헤드라이너 천, 앞유리 안쪽으로)
	local wsHalf = (F.wsW or width) / 2
	local nOut = (hiW - ws):Cross(Vector3.xAxis).Unit
	if nOut.Z > 1e-4 or (math.abs(nOut.Z) <= 1e-4 and nOut.Y < 0) then
		nOut = -nOut -- 바깥 = 앞(-Z) · 위
	end
	for _, s in { -1, 1 } do
		local a = Vector3.new(s * (wsHalf - 0.1), ws.Y, ws.Z) - nOut * 0.12
		local b = Vector3.new(s * (wsHalf - 0.24), hiW.Y, hiW.Z) - nOut * 0.12
		K:seg("APillarTrim", a, b, 0.15, P.pillar)
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
			K:box("TouchIcon", Vector3.new(0.045, 0.03, 0.004), cf * CFrame.new(i * 0.1, -0.055, 0.014), P.markWhite)
		end
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
		K:panel("HairlineVent", width - 0.3, 0.05, 0.06, 0.024, CFrame.new(0, sy, face + 0.0), P.duct)
		K:cyl("HairlineLip", width - 0.32, 0.016, CFrame.new(0, sy - 0.035, face + 0.02), P.chrome)
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
		local sy0, sy1 = conTop - 0.02, top + 0.04
		K:panel("CentreStack", sw, sy1 - sy0, 0.12, 0.14, CFrame.new(cx, (sy0 + sy1) / 2, face + 0.04), P.gloss)
		for _, s in { -1, 1 } do
			vent(K, P, "StackVent", CFrame.new(cx + s * (cw / 2 + 0.13), scrY, face + 0.11), 0.13, ch * 0.95, true, { frame = P.gloss, duct = P.duct, slat = P.hard, knob = P.satin })
		end
		climate(K, F, P, S, cx, scrY - ch / 2 - 0.17, face + 0.115)
		-- 새틴 두 줄: 문 -> 대시 -> 스택 양옆으로 흘러내림
		for i, ly in { mid + 0.13, mid + 0.05 } do
			for _, s in { -1, 1 } do
				local xin = cx + s * (sw / 2 + 0.04 + (i - 1) * 0.06)
				local xout = s * (half - 0.06)
				-- 둥근 새틴 막대 + 꺾이는 곳은 공으로
				K:cyl("Garnish", math.abs(xout - xin), 0.026, CFrame.new((xin + xout) / 2, ly, face + 0.014), P.trim)
				K:seg("Garnish", Vector3.new(xin, ly, face + 0.014), Vector3.new(xin, conTop, face + 0.014), 0.026, P.trim)
				K:ball("Garnish", 0.026, CFrame.new(xin, ly, face + 0.014), P.trim)
			end
		end
		if amb then
			K:cyl("DashAmbient", half - sw / 2 - 0.2, 0.018, CFrame.new(toC * (half + sw / 2) / 2, mid + 0.09, face + 0.02), amb)
		end
		-- 숨은 슬롯 송풍구: 운전석 끝 + 조수석 쪽 긴 슬롯
		K:panel("SlotVent", 0.5, 0.05, 0.04, 0.024, CFrame.new(ds * (half - 0.38), mid + 0.24, face + 0.005), P.duct)
		K:panel("SlotVent", half - sw / 2 - 0.3, 0.045, 0.04, 0.022, CFrame.new(toC * (half + sw / 2) / 2, mid + 0.24, face + 0.005), P.duct)
	elseif g == "metal_wood" then
		-- 카니발: 화면 아래 금속 가니시 띠(슬롯 송풍구 2 + 비상등, 양끝 슬롯) + 우드그레인 띠 + 터치 띠 2단
		local scrBottom = math.min(F.clusterBottom or top, scrY - ch / 2)
		local my = math.min(top - 0.22, scrBottom - 0.1)
		K:rbox("MetalBand", Vector3.new(width - 0.12, 0.15, 0.05), 0.024, CFrame.new(0, my, face + 0.01), P.trim)
		for _, s in { -1, 1 } do
			vent(K, P, "CentreVent", CFrame.new(cx + s * 0.34, my, face + 0.03), 0.5, 0.065)
			vent(K, P, "SideVent", CFrame.new(s * (half - 0.42), my, face + 0.03), 0.5, 0.065)
		end
		K:box("Hazard", Vector3.new(0.08, 0.06, 0.04), CFrame.new(cx, my, face + 0.04), P.hazard)
		local wy = my - 0.15
		K:rbox("WoodBand", Vector3.new(width - 0.2, 0.13, 0.05), 0.024, CFrame.new(0, wy, face + 0.006), P.wood)
		if amb then
			K:cyl("DashAmbient", width - 0.3, 0.016, CFrame.new(0, my - 0.083, face + 0.03), amb)
		end
		local iy = wy - 0.13
		K:panel("InfoTouch", 1.0, 0.1, 0.03, 0.045, CFrame.new(cx, iy, face + 0.04), P.gloss)
		for _, s in { -1, 1 } do
			K:cyl("InfoKnob", 0.05, 0.09, CFrame.new(cx + s * 0.42, iy, face + 0.07) * ROT_X_TO_Z, P.alloy)
		end
		for i = -2, 2 do
			K:box("TouchIcon", Vector3.new(0.04, 0.024, 0.004), CFrame.new(cx + i * 0.12, iy, face + 0.057), P.markWhite)
		end
		climate(K, F, P, S, cx, math.max(conTop + 0.1, iy - 0.15), face + 0.05)
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
