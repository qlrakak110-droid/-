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
		-- 둥근 모서리 틈(r 0.07) + 뚜껑 + 손잡이 홈 (서랍처럼 각진 테두리 X)
		local gc = CFrame.new(gx, gy, face - 0.075)
		K:panel("GloveGap", gw, gh, 0.01, 0.07, gc, P.hardDark)
		K:panel("GloveLid", gw - 0.03, gh - 0.03, 0.01, 0.06, gc * CFrame.new(0, 0, 0.005), P.lower)
		K:box("GloveRecess", Vector3.new(0.34, 0.07, 0.01), gc * CFrame.new(0, gh / 2 - 0.09, 0.009), P.duct)
		K:box("GloveHandle", Vector3.new(0.28, 0.03, 0.02), gc * CFrame.new(0, gh / 2 - 0.1, 0.016), P.satin)
		if S.key == "solati" then
			-- 쏠라티: 위 대시 면에도 뚜껑 달린 글로브박스 (밴 수납 23곳 중 하나)
			local uy0, uy1 = mid + 0.18, top - rr - 0.06
			local uc = CFrame.new(gx, (uy0 + uy1) / 2, face + 0.004)
			K:panel("UpperGloveGap", gw - 0.1, uy1 - uy0, 0.01, 0.07, uc, P.hardDark)
			K:panel("UpperGloveLid", gw - 0.13, uy1 - uy0 - 0.03, 0.01, 0.06, uc * CFrame.new(0, 0, 0.004), P.soft)
			K:box("UpperGloveLatch", Vector3.new(0.16, 0.035, 0.02), uc * CFrame.new(0, (uy1 - uy0) / 2 - 0.07, 0.011), P.satin)
		end
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
			vent(K, P, "CentreVent", CFrame.new(cx + s * 0.29, vy, face + 0.01), 0.42, 0.1)
		end
		K:box("Hazard", Vector3.new(0.09, 0.07, 0.04), CFrame.new(cx, vy, face + 0.02), P.hazard)
		-- 끝 송풍구 (날개 끝, 크롬 라인 위)
		for _, s in { -1, 1 } do
			vent(K, P, "SideVent", CFrame.new(s * (half - 0.38), ly + 0.17, face + 0.01), 0.46, 0.12)
		end
		-- 스택 둘레는 대시와 같은 소프트 패드: 위(AVN · 공조 폭 1.3) -> 아래는 콘솔 폭으로 좁아짐. 광택은 키 · 공조 띠만
		-- 앞면 face + 0.045, 뒤는 0.08 들어간 아래 대시 면(face - 0.08) 속까지 (옆에서 봐도 떠 있는 판이 아님)
		local ky = vy - 0.17
		local cyc = ky - 0.2
		local sTop, sMid = vy - 0.09, cyc - 0.13
		K:panel("StackBack", 1.3, sTop - sMid, 0.155, 0.1, CFrame.new(cx, (sTop + sMid) / 2, face - 0.0325), P.soft)
		if sMid > conTop then
			local lw = (if con then math.min(con.w, 1.15) else 0.9) + 0.06
			K:panel("StackLower", lw, sMid - conTop + 0.06, 0.145, 0.08, CFrame.new(cx, (sMid + conTop) / 2 + 0.03, face - 0.0375), P.soft)
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
			local pw = cw + 0.62 -- 8" 화면 + 양옆 세로 송풍구 0.15 → 포드 폭 1.26
			local py0, py1 = math.max(bottom - 0.3, F.floorY + 0.7), top - 0.02
			K:panel("StackPod", pw, py1 - py0, 0.24, 0.16, CFrame.new(cx, (py0 + py1) / 2, face + 0.04), P.satin)
			K:panel("StackPodFace", pw - 0.07, py1 - py0 - 0.07, 0.03, 0.13, CFrame.new(cx, (py0 + py1) / 2, face + 0.16), P.hard)
			for _, s in { -1, 1 } do
				-- 화면 베젤(반폭 cw/2 + 0.03)과 0.015 띄우고 포드 면(반폭 pw/2 - 0.035) 안에
				vent(K, P, "PodVent", CFrame.new(cx + s * (cw / 2 + 0.155), scrY, face + 0.18), 0.15, ch * 0.95)
			end
			local hz = scrY - ch / 2 - 0.08
			K:box("Hazard", Vector3.new(0.1, 0.06, 0.04), CFrame.new(cx, hz, face + 0.18), P.hazard)
			-- 대시 기어 레버 (직선 게이트 + 은색 테두리)
			local gy = hz - 0.27
			local gate = CFrame.new(cx, gy, face + 0.17)
			K:panel("GearGateRim", 0.29, 0.43, 0.02, 0.08, gate, P.satin)
			K:panel("GearGatePlate", 0.25, 0.39, 0.02, 0.07, gate * CFrame.new(0, 0, 0.006), P.gloss)
			K:box("GearSlot", Vector3.new(0.035, 0.32, 0.01), gate * CFrame.new(0, 0, 0.015), P.duct)
			-- 레버: P 자리에서 승객 쪽으로 0.28 나온 검은 막대 + 새틴 칼라, 큰 검은 노브 + 새틴 띠 + 운전석 쪽 해제 버튼
			local a = (gate * CFrame.new(0, 0.1, 0.02)).Position
			local b = a + Vector3.new(0, 0.05, 0.28)
			K:ell("GearBoot", Vector3.new(0.1, 0.07, 0.08), CFrame.new(a + Vector3.new(0, 0, 0.02)), P.rubber)
			K:seg("GearStem", a, b, 0.05, P.hardDark)
			K:seg("GearCollar", a:Lerp(b, 0.55), a:Lerp(b, 0.7), 0.066, P.satin)
			local kc = CFrame.new(b + Vector3.new(0, 0.05, 0.04))
			K:ell("GearKnob", Vector3.new(0.17, 0.2, 0.19), kc, P.hardDark)
			K:ell("GearKnobBand", Vector3.new(0.176, 0.045, 0.196), kc * CFrame.new(0, -0.035, 0), P.satin)
			K:box("GearButton", Vector3.new(0.03, 0.05, 0.06), kc * CFrame.new(ds * 0.086, 0.02, 0), P.satin)
			-- 슬롯 운전석 쪽 P R N D 표시 (글자판 1 파트)
			Screens.plate(K, "GearLetters", gate * CFrame.new(ds * 0.085, -0.005, 0.021), 0.045, 0.3, { "P", "R", "N", "D" }, Color3.fromRGB(225, 232, 242), true)
			climate(K, F, P, S, cx, py0 + 0.24, face + 0.17)
			-- 포드 아래 → 바닥: 하단 페시아가 발치 트레이까지 이어짐 (포드가 공중에 떠 보이지 않게)
			local fy0, fy1 = F.floorY, py0 + 0.06
			K:zbox("StackFoot", Vector3.new(pw - 0.34, fy1 - fy0, 0.34), 0.08, CFrame.new(cx, (fy0 + fy1) / 2, face), P.hard)
		else
			-- 포터 · 쏠라티: 센터페시아 (포터 = 화면 위 송풍구 2, 쏠라티 = 은색 프레임 + 양옆 사다리꼴 송풍구)
			local fw = cw + 0.6
			local fy0, fy1 = mid - (if vk == "trap_v" then 0.6 else 0.5), top - 0.04 -- 쏠라티: 스택이 아래로 이어져 기어 포드 · 사이렌 박스가 붙음
			K:panel("Fascia", fw, fy1 - fy0, 0.14, 0.16, CFrame.new(cx, (fy0 + fy1) / 2, face + 0.02), P.hard)
			if vk == "trap_v" then
				K:panel("FasciaFrame", cw + 0.56, ch + 0.18, 0.02, 0.1, ccf * CFrame.new(0, 0, -0.035), P.satin)
				-- 세로 사다리꼴 송풍구: 화면 쪽 변은 수직, 바깥 변은 위로 갈수록 넓어짐 (아래 0.11 -> 위 0.17, 높이 0.33)
				local vh, wb, wt, vz = ch * 0.92, 0.11, 0.17, face + 0.13
				local y0, y1 = scrY - vh / 2, scrY + vh / 2
				for _, s in { -1, 1 } do
					local xi = cx + s * (cw / 2 + 0.07)
					local c = { Vector3.new(xi, y0, vz + 0.02), Vector3.new(xi, y1, vz + 0.02), Vector3.new(xi + s * wt, y1, vz + 0.02), Vector3.new(xi + s * wb, y0, vz + 0.02) }
					for i = 1, 4 do
						K:seg("TrapVentRim", c[i], c[i % 4 + 1], 0.035, P.satin)
						K:ball("TrapVentRim", 0.035, CFrame.new(c[i]), P.satin)
					end
					K:box("TrapVentDuct", Vector3.new(wb, vh, 0.05), CFrame.new(xi + s * wb / 2, scrY, vz), P.duct)
					-- 웨지: 직각 꼭짓점 = (xi + s*wb, y1), 빗변 = 기울어진 바깥 변
					K:wedge("TrapVentDuct", Vector3.new(0.05, vh, wt - wb), CFrame.fromMatrix(Vector3.new(xi + s * (wb + wt) / 2, scrY, vz), Vector3.new(0, 0, -s), Vector3.new(0, -1, 0)), P.duct)
					for k = 1, 5 do
						local L = wb + (wt - wb) * (k - 0.5) / 5 - 0.035
						K:cyl("TrapVentSlat", L, 0.022, CFrame.new(xi + s * (0.0175 + L / 2), y0 + vh * (k - 0.5) / 5, vz + 0.03), P.hard)
					end
					K:box("TrapVentTab", Vector3.new(0.03, 0.05, 0.03), CFrame.new(xi + s * 0.07, scrY, vz + 0.05), P.satin)
				end
			else
				for _, s in { -1, 1 } do
					vent(K, P, "TopVent", CFrame.new(cx + s * 0.27, scrY + ch / 2 + 0.14, face + 0.1), 0.42, 0.15, false, { frame = P.hardDark, duct = P.duct, slat = P.hard, knob = P.satin })
				end
				-- 포터 8" 디스플레이 오디오: 광택 판 + 화면 양옆 단축키 3개씩 + 아래 볼륨 · 튜닝 노브
				K:panel("AvnFace", cw + 0.34, ch + 0.06, 0.03, 0.06, ccf * CFrame.new(0, 0, -0.035), P.gloss)
				for _, s in { -1, 1 } do
					for i = 0, 2 do
						K:box("AvnKey", Vector3.new(0.09, 0.055, 0.03), ccf * CFrame.new(s * (cw / 2 + 0.085), ch / 2 - 0.05 - i * 0.075, -0.005), P.button)
					end
					K:cyl("AvnKnob", 0.05, 0.075, ccf * CFrame.new(s * (cw / 2 + 0.085), -ch / 2 + 0.035, 0) * ROT_X_TO_Z, P.alloy)
				end
			end
			K:box("Hazard", Vector3.new(0.1, 0.06, 0.04), CFrame.new(cx, scrY - ch / 2 - 0.07, face + 0.1), P.hazard)
			climate(K, F, P, S, cx, scrY - ch / 2 - 0.3, face + 0.1)
			if S.key == "porter" then
				-- 공조 아래: 동전 트레이(어두운 홈 + 둥근 턱) + 12V 소켓 + USB
				local ty = fy0 + 0.13
				K:panel("CoinTray", fw - 0.5, 0.16, 0.02, 0.05, CFrame.new(cx, ty, face + 0.092), P.duct)
				K:capsule("CoinTrayLip", Vector3.new(cx - (fw - 0.56) / 2, ty - 0.08, face + 0.11), Vector3.new(cx + (fw - 0.56) / 2, ty - 0.08, face + 0.11), 0.05, P.hard)
				K:cyl("PowerOutlet", 0.03, 0.08, CFrame.new(cx + 0.18, ty + 0.01, face + 0.1) * ROT_X_TO_Z, P.satin)
				K:box("UsbPort", Vector3.new(0.07, 0.03, 0.02), CFrame.new(cx - 0.18, ty + 0.01, face + 0.105), P.hardDark)
			end
		end
		-- 끝 송풍구 (둥근 사각 / 사각)
		for _, s in { -1, 1 } do
			local look = { frame = if vk == "pod_v" then P.gloss elseif vk == "top_rect" then P.hardDark else P.satin, duct = P.duct, slat = P.hard, knob = P.satin }
			vent(K, P, "SideVent", CFrame.new(s * (half - 0.36), mid + 0.36, face + 0.01), if S.sideVent == "round" then 0.32 else 0.42, if S.sideVent == "round" then 0.26 else 0.22, false, look)
		end
	end

	-- 기타 -------------------------------------------------------------------------------------------
	local ex = S.extras or {}
	if ex.tray then
		-- 포터: 대시 위 열린 수납 트레이. 계기판 차양 오른쪽부터 조수석 끝까지, 성에 슬롯 뒤.
		-- 0.07 솟은 둥근 턱(원통 4 + 모서리 공 4) + 둥근 칸막이 2
		local cl: Vector3 = F.cluster
		local xa = cl.X + toC * ((S.cluster.w + 0.3) / 2 + 0.15)
		local xb = toC * (half - 0.3)
		local tz0, tz1 = face - 0.66, face - 0.18
		local ly = top + 0.035
		K:box("TrayFloor", Vector3.new(math.abs(xb - xa) - 0.04, 0.012, tz1 - tz0 - 0.04), CFrame.new((xa + xb) / 2, top + 0.006, (tz0 + tz1) / 2), P.hardDark)
		local c = { Vector3.new(xa, ly, tz0), Vector3.new(xb, ly, tz0), Vector3.new(xb, ly, tz1), Vector3.new(xa, ly, tz1) }
		for i = 1, 4 do
			K:seg("TrayLip", c[i], c[i % 4 + 1], 0.07, P.hard)
			K:ball("TrayLip", 0.07, CFrame.new(c[i]), P.hard)
		end
		for _, f in { 1 / 3, 2 / 3 } do
			local dx = xa + (xb - xa) * f
			K:seg("TrayDivider", Vector3.new(dx, top + 0.03, tz0 + 0.03), Vector3.new(dx, top + 0.03, tz1 - 0.03), 0.06, P.hard)
		end
	end
	if ex.shelf then
		-- 포터: 조수석 쪽 위 대시의 열린 선반 (어두운 안쪽 + 둥근 아래 턱 + 위 눈썹) + 투톤 경계의 둥근 단
		local fw = cw + 0.6
		local xa, xb = cx + toC * (fw / 2 + 0.12), toC * (half - 0.62)
		local yb, yt = mid + 0.26, top - 0.28
		K:panel("ShelfCavity", math.abs(xb - xa), yt - yb, 0.03, 0.07, CFrame.new((xa + xb) / 2, (yb + yt) / 2, face + 0.006), P.duct)
		K:capsule("ShelfLip", Vector3.new(xa + toC * 0.02, yb, face + 0.05), Vector3.new(xb - toC * 0.02, yb, face + 0.05), 0.1, P.soft)
		K:capsule("ShelfBrow", Vector3.new(xa + toC * 0.02, yt, face + 0.03), Vector3.new(xb - toC * 0.02, yt, face + 0.03), 0.06, P.soft)
		K:cyl("DashSplitRoll", width - 0.34, 0.1, CFrame.new(0, mid + 0.12, face - 0.04), P.soft)
	end
	if ex.bins then
		-- 쏠라티: 대시 윗면에서 0.02 만 솟은 둥근 뚜껑 2 (어두운 틈 + 푸시 래치) + 사이 열린 트레이
		for _, bx in { cx - toC * 0.38, cx + toC * 0.76 } do
			local bc = CFrame.new(bx, top, face - 0.42)
			K:slab("BinGap", 0.72, 0.46, 0.012, 0.09, bc * CFrame.new(0, 0.004, 0), P.hardDark)
			K:slab("DashBinLid", 0.68, 0.42, 0.02, 0.08, bc * CFrame.new(0, 0.012, 0), P.soft)
			K:cyl("BinLatch", 0.02, 0.07, bc * CFrame.new(0, 0.024, 0.15) * CFrame.Angles(0, 0, math.pi / 2), P.satin)
		end
		K:slab("DashTray", 0.3, 0.42, 0.02, 0.06, CFrame.new(cx + toC * 0.19, top + 0.002, face - 0.42), P.hardDark)
	end
	if F.kind == "ambulance" and not ex.siren then
		-- 다른 차를 고친 구급차(카니발 등): 대시 아래에 매단 사이렌 · 경광등 조작기 (스위치 6 + 표시등 + 모드 다이얼),
		-- 콘솔 조수석 쪽, 운전자 쪽으로 15° 기울임
		local hx = cx + toC * ((if con then con.w / 2 else 0.45) + 0.42)
		local sc = CFrame.new(hx, bottom - 0.13, face + 0.06) * CFrame.Angles(math.rad(-15), 0, 0)
		K:rbox("SirenBracket", Vector3.new(0.5, 0.05, 0.18), 0.02, sc * CFrame.new(0, 0.14, -0.02), P.hardDark)
		K:rbox("SirenBox", Vector3.new(0.66, 0.22, 0.18), 0.045, sc, P.hardDark)
		local cols = { P.hazard, P.lampBlue, P.lampAmber, P.button, P.button }
		for i = 1, 5 do
			local x = -0.25 + (i - 1) * 0.095
			K:box("SirenSwitch", Vector3.new(0.065, 0.06, 0.035), sc * CFrame.new(x, -0.015, 0.1), cols[i])
			K:box("SirenLed", Vector3.new(0.022, 0.011, 0.008), sc * CFrame.new(x, 0.06, 0.094), if i <= 3 then P.ledRed else P.ledGreen)
		end
		K:cyl("SirenDialRing", 0.02, 0.15, sc * CFrame.new(0.25, 0, 0.095) * ROT_X_TO_Z, P.satin)
		K:cyl("SirenDial", 0.05, 0.12, sc * CFrame.new(0.25, 0, 0.115) * ROT_X_TO_Z, P.hardDark)
		K:box("SirenDialMark", Vector3.new(0.01, 0.04, 0.005), sc * CFrame.new(0.25, 0.03, 0.142), P.markWhite)
	end
	if ex.siren then
		-- 119: 사이렌 · 경광등 조작 헤드 (스위치 2줄 + 표시등 + 오른쪽 사이렌 모드 다이얼), 스택 아래 칸. 무전기 핸드셋은 스택 오른쪽
		local sc = CFrame.new(cx + toC * 0.17, mid - 0.42, face + 0.14) * CFrame.Angles(math.rad(-12), 0, 0)
		K:rbox("SirenBox", Vector3.new(1.1, 0.28, 0.2), 0.05, sc, P.hardDark)
		local cols = { P.hazard, P.lampBlue, P.lampAmber, P.button, P.button, P.button }
		for r = 0, 1 do
			for i = 1, 6 do
				local x = -0.47 + (i - 1) * 0.14
				K:box("SirenSwitch", Vector3.new(0.09, 0.07, 0.04), sc * CFrame.new(x, 0.05 - r * 0.1, 0.11), if r == 0 then cols[i] else P.button)
				if r == 0 then
					K:box("SirenLed", Vector3.new(0.025, 0.012, 0.01), sc * CFrame.new(x, 0.105, 0.105), if i <= 3 then P.ledRed else P.ledGreen)
				end
			end
		end
		K:cyl("SirenDialRing", 0.02, 0.2, sc * CFrame.new(0.4, 0, 0.105) * ROT_X_TO_Z, P.satin)
		K:cyl("SirenDial", 0.06, 0.16, sc * CFrame.new(0.4, 0, 0.13) * ROT_X_TO_Z, P.hardDark)
		K:box("SirenDialMark", Vector3.new(0.012, 0.05, 0.006), sc * CFrame.new(0.4, 0.04, 0.162), P.markWhite)
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
		-- 쏠라티: 스택 왼쪽 아래에서 솟은 둥근 포드 (스택과 같은 차콜, 스택 왼쪽 끝과 겹쳐 한 덩어리) + 2단 부츠
		-- + 운전자 쪽으로 45° 기운 레버 + 6단 무늬 노브
		local px, py = F.wheel.c.X + toC * 0.82, mid - 0.3
		K:ell("GearPod", Vector3.new(0.5, 0.56, 0.64), CFrame.new(px, py, face), P.hard)
		local dir = Vector3.new(0, 0.7, 0.71).Unit
		local a = Vector3.new(px, py + 0.12, face + 0.27)
		K:ell("ShiftBoot", Vector3.new(0.21, 0.16, 0.21), CFrame.new(a), P.rubber)
		K:ell("ShiftBootTop", Vector3.new(0.13, 0.13, 0.13), CFrame.new(a + dir * 0.09), P.rubber)
		local b = a + dir * 0.34
		K:seg("ShiftStick", a + dir * 0.1, b, 0.04, P.metalDark)
		local kc = b + dir * 0.05
		K:ball("ShiftKnob", 0.15, CFrame.new(kc), P.hardDark)
		K:box("ShiftPattern", Vector3.new(0.07, 0.006, 0.06), CFrame.fromMatrix(kc + dir * 0.074, Vector3.xAxis, dir), { c = Color3.fromRGB(170, 174, 180), m = Enum.Material.SmoothPlastic })
	end
	return {}
end

Dash.REPLACES = { "Dash", "DashTop", "DashUpper", "DashLower", "VentBand", "VentSlot", "DashChrome", "WoodBand", "AmbientStrip", "ClimatePanel", "TempKnob", "ClimateKnob", "ClusterScreen", "ClusterHood", "NavScreen", "FloatingScreen", "Screen", "CentrePanel", "VerticalVent", "CornerVent", "Glovebox", "DashSpeaker", "StartButton", "SquareVent", "RadioPanel", "StackFrame", "TabletMount", "TabletScreen", "Gauges" }

return Dash
