--!strict
-- GwangalliCarInterior/Dash: 대시보드. 소프트 가죽 상단 + 둥근 앞 모서리 + 앞유리까지 덮는 상판, 하단 패널,
-- 무릎 패널, 우드/알루미늄 트림 띠 + 크롬 라인 + 앰비언트 라이트, 송풍구(가운데 2 + 양끝 2, 크롬 테두리 · 날개),
-- 공조 패널(화면 + 다이얼 + 버튼 줄 + 비상등), 센터 스택 → 콘솔 연결, 글로브박스, 성에 제거 슬롯,
-- 트위터 스피커, A필러 트림.

local Screens = require(script.Parent:WaitForChild("Screens"))

local Dash = {}

local ROT_X_TO_Z = CFrame.Angles(0, -math.pi / 2, 0)

function Dash.build(K: any, F: any, P: any)
	local half: number = F.halfIn
	local width = half * 2 - 0.04
	local face: number = F.dashFace
	local front: number = F.dashFront
	local top: number = F.dashTop
	local mid: number = F.dashMidY
	local bottom: number = F.dashBottom
	local commercial = F.kind == "truck" or F.kind == "ambulance"

	-- 몸체 --------------------------------------------------------------------------------------------
	local upperY0 = mid + 0.12
	local lowerH = upperY0 - bottom
	K:box("DashLower", Vector3.new(width, lowerH, face - front - 0.08), CFrame.new(0, bottom + lowerH / 2, (front + face - 0.08) / 2), P.hard)
	local upH = top - upperY0
	K:box("DashUpper", Vector3.new(width, upH, face - front), CFrame.new(0, upperY0 + upH / 2, (front + face) / 2), P.soft)
	-- 둥근 앞 모서리 (실내 쪽) + 스티치
	K:cyl("DashRoll", width, 0.26, CFrame.new(0, top - 0.13, face), P.soft)
	K:box("DashStitch", Vector3.new(width - 0.1, 0.01, 0.01), CFrame.new(0, top - 0.02, face + 0.07), P.stitch)
	-- 상판: 대시 위에서 앞유리 아래 끝까지
	local ws: Vector3 = F.wsLow
	local zA, zB = math.min(ws.Z, front), face - 0.12
	if zB - zA > 0.1 then
		K:box("DashDeck", Vector3.new(width, 0.08, zB - zA), CFrame.new(0, top - 0.04, (zA + zB) / 2), P.soft)
		if ws.Y < top - 0.05 then
			-- 앞유리 아래가 더 낮으면 경사로 덮기
			local h = top - ws.Y
			K:wedge("DashSlope", Vector3.new(width, h, math.max(0.2, zB - zA) * 0.5), CFrame.new(0, ws.Y + h / 2, zA + (zB - zA) * 0.25), P.soft)
		end
		-- 성에 제거 슬롯 + 트위터
		for i = -3, 3 do
			K:box("DefrostSlot", Vector3.new(0.34, 0.012, 0.05), CFrame.new(i * 0.55, top + 0.002, zA + 0.25), P.hardDark)
		end
		for _, s in { -1, 1 } do
			K:ell("Tweeter", Vector3.new(0.3, 0.025, 0.2), CFrame.new(s * (half - 0.45), top + 0.006, zA + 0.32), P.grille)
		end
	end
	-- 무릎 패널 (운전석 쪽), 글로브박스 (조수석 쪽)
	local ds = F.side
	K:box("KneePanel", Vector3.new(1.45, 0.42, 0.12), CFrame.new(ds * 1.15, bottom - 0.12, face - 0.22) * CFrame.Angles(math.rad(-12), 0, 0), P.soft)
	local gx = -ds * 1.3
	local gy = mid - 0.18
	local gw, gh = 1.25, 0.46
	for _, e in { { 0, gh / 2, gw, 0.012 }, { 0, -gh / 2, gw, 0.012 }, { gw / 2, 0, 0.012, gh }, { -gw / 2, 0, 0.012, gh } } do
		K:box("GloveGap", Vector3.new(e[3], e[4], 0.01), CFrame.new(gx + e[1], gy + e[2], face - 0.075), P.hardDark)
	end
	K:box("GloveHandle", Vector3.new(0.3, 0.035, 0.03), CFrame.new(gx, gy + gh / 2 - 0.08, face - 0.07), P.satin)

	-- 트림 띠 + 크롬 + 앰비언트 ---------------------------------------------------------------------------
	local bandY = mid + 0.02
	K:box("DashTrimBand", Vector3.new(width - 0.12, 0.17, 0.05), CFrame.new(0, bandY, face + 0.0), P.trim)
	K:box("DashChromeLine", Vector3.new(width - 0.12, 0.02, 0.03), CFrame.new(0, bandY + 0.095, face + 0.01), P.chrome)
	K:box("DashAmbient", Vector3.new(width - 0.3, 0.022, 0.025), CFrame.new(0, bandY - 0.1, face + 0.01), P.ambient)

	-- 송풍구 ------------------------------------------------------------------------------------------
	local ventLook = { frame = P.chrome, duct = P.duct, slat = P.hard, knob = P.satin }
	local vy = bandY + 0.24
	local nvX: number = if commercial then 0 else (F.nav :: Vector3).X
	local cx = if math.abs(nvX) < 1 then nvX else 0
	for _, s in { -1, 1 } do
		K:vent("CentreVent", CFrame.new(cx + s * 0.36, vy, face + 0.0), 0.56, 0.13, ventLook, 3)
		K:vent("SideVent", CFrame.new(s * (half - 0.36), vy, face + 0.0), 0.4, 0.2, ventLook, 4)
	end

	-- 공조 패널 + 센터 스택 --------------------------------------------------------------------------------
	local cpY = bandY - 0.36
	local panel = K:box("ClimateGlass", Vector3.new(1.3, 0.34, 0.03), CFrame.new(cx, cpY, face + 0.06) * CFrame.Angles(math.rad(-6), 0, 0), P.screen)
	Screens.climate(panel, P.accentColor)
	K:box("ClimateBezel", Vector3.new(1.42, 0.44, 0.05), CFrame.new(cx, cpY, face + 0.035) * CFrame.Angles(math.rad(-6), 0, 0), P.gloss)
	for _, s in { -1, 1 } do
		local kc = CFrame.new(cx + s * 0.86, cpY, face + 0.06)
		K:cyl("ClimateKnob", 0.1, 0.22, kc * ROT_X_TO_Z, P.chrome)
		K:cyl("ClimateKnobCap", 0.03, 0.17, kc * CFrame.new(0, 0, 0.05) * ROT_X_TO_Z, P.gloss)
	end
	for i = 0, 5 do
		K:box("StackButton", Vector3.new(0.17, 0.07, 0.04), CFrame.new(cx - 0.47 + i * 0.188, cpY - 0.3, face + 0.06), if i == 2 then P.hazard else P.button)
	end
	-- 센터 스택 아래: 콘솔 앞쪽까지 이어지는 경사 판
	local con = F.console
	if con then
		local y0 = cpY - 0.4
		local h = y0 - con.top
		if h > 0.12 then
			local zc0, zc1 = face - 0.15, con.z0 + 0.35
			local depth = math.max(0.3, zc1 - zc0)
			-- 웨지: 실내 쪽(+Z)이 높음 -> 뒤집어서 대시 쪽이 높게
			K:wedge("StackSlope", Vector3.new(math.min(con.w, 1.1), h, depth), CFrame.new(cx, con.top + h / 2, zc0 + depth / 2) * CFrame.Angles(0, math.pi, 0), P.hard)
			K:box("StackTray", Vector3.new(0.7, 0.03, 0.4), CFrame.new(cx, con.top + 0.05, zc0 + depth * 0.62), P.rubber)
		end
	end

	-- A필러 트림 (천) -----------------------------------------------------------------------------------
	local hi: Vector3 = F.wsHigh
	local wsHalf = (F.wsW or width) / 2
	for _, s in { -1, 1 } do
		local a = Vector3.new(s * (wsHalf + 0.05), ws.Y + 0.05, ws.Z + 0.05)
		local b = Vector3.new(s * (wsHalf - 0.05), hi.Y - 0.08, hi.Z + 0.05)
		K:seg("APillarTrim", a, b, 0.22, P.fabric)
	end
	return {}
end

Dash.REPLACES = { "Dash", "DashTop", "DashUpper", "DashLower", "VentBand", "VentSlot", "DashChrome", "WoodBand", "AmbientStrip", "ClimatePanel", "TempKnob", "ClimateKnob", "ClusterScreen", "ClusterHood", "NavScreen", "FloatingScreen", "Screen", "CentrePanel", "VerticalVent", "CornerVent", "Glovebox", "DashSpeaker", "StartButton", "SquareVent", "RadioPanel", "StackFrame", "TabletMount", "TabletScreen", "Gauges" }

return Dash
