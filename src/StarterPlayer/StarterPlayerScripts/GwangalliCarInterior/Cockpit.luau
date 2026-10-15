--!strict
-- GwangalliCarInterior/Cockpit: 운전석 앞. 핸들(가죽 림 36조각 · 3시/9시 그립 · 에어백 커버 · 엠블럼 · 스포크 버튼 ·
-- 패들시프트, 피벗째 회전), 스티어링 컬럼 · 슈라우드 · 레버, 파노라믹 디스플레이(계기판 + 내비 한 장의 유리),
-- 계기판 차양, HUD 창, 시동 버튼.

local Screens = require(script.Parent:WaitForChild("Screens"))

local Cockpit = {}

local ROT_X_TO_Z = CFrame.Angles(0, -math.pi / 2, 0) -- 원통 축(X)을 프레임의 +Z 로

function Cockpit.build(K: any, F: any, P: any)
	local W: CFrame = F.wheel.cf
	local R: number = F.wheel.R
	local sport = F.kind == "luxury" or F.kind == "sedan" or F.kind == "police" or F.kind == "taxi"
	local out: any = {}

	-- 스티어링 컬럼 (고정) ------------------------------------------------------------------------------
	local colA = (W * CFrame.new(0, -0.03, -0.14)).Position
	local colB = (W * CFrame.new(0, -0.1, -0.95)).Position
	K:seg("SteeringColumn", colA, colB, 0.18, P.hard)
	local shroud = W * CFrame.new(0, -0.13, -0.5) * CFrame.Angles(0, math.pi / 2, 0)
	K:rbox("ColumnShroud", Vector3.new(0.62, 0.24, 0.36), 0.09, shroud, P.soft)
	-- 방향지시 / 와이퍼 레버
	for _, s in { -1, 1 } do
		local a = (W * CFrame.new(s * 0.16, -0.09, -0.3)).Position
		local b = (W * CFrame.new(s * (R + 0.02), -0.16, -0.22)).Position
		K:seg("Stalk", a, b, 0.045, P.hard)
		K:ell("StalkTip", Vector3.new(0.13, 0.065, 0.065), CFrame.lookAt(b, a) * CFrame.Angles(0, math.pi / 2, 0), P.hard)
	end

	-- 핸들 (피벗째 회전) ---------------------------------------------------------------------------------
	local pivot, weld = K:pivot("SteeringPivot", W, function()
		-- 림: 3시·9시 그립이 두꺼운 가죽 원환
		K:ring("WheelRim", W, R, 0.125, 36, P.wheelLeather, nil, nil, function(t: number)
			return 1 + 0.16 * math.cos(t) ^ 2
		end)
		-- 림 안쪽 장식 링 (운전자 쪽에서 보이는 은색 띠, 위쪽 반원)
		K:ring("RimTrim", W * CFrame.new(0, 0, 0.035), R - 0.075, 0.025, 14, P.satin, math.rad(30), math.rad(150))
		-- 허브 + 에어백 커버 + 엠블럼
		K:cyl("HubBody", 0.18, 0.46, W * CFrame.new(0, -0.03, -0.03) * ROT_X_TO_Z, P.hard)
		K:ell("Airbag", Vector3.new(0.52, 0.42, 0.18), W * CFrame.new(0, -0.03, 0.07), P.wheelHub)
		K:ell("AirbagSeam", Vector3.new(0.4, 0.3, 0.02), W * CFrame.new(0, -0.03, 0.155), P.hardDark)
		if F.kind == "luxury" then
			K:box("WingL", Vector3.new(0.12, 0.022, 0.012), W * CFrame.new(-0.08, -0.01, 0.168) * CFrame.Angles(0, 0, math.rad(8)), P.chrome)
			K:box("WingR", Vector3.new(0.12, 0.022, 0.012), W * CFrame.new(0.08, -0.01, 0.168) * CFrame.Angles(0, 0, math.rad(-8)), P.chrome)
			K:ell("Crest", Vector3.new(0.05, 0.06, 0.014), W * CFrame.new(0, -0.01, 0.17), P.chrome)
		else
			K:ell("Emblem", Vector3.new(0.16, 0.09, 0.016), W * CFrame.new(0, -0.02, 0.165), P.chrome)
			K:ell("EmblemInner", Vector3.new(0.12, 0.06, 0.012), W * CFrame.new(0, -0.02, 0.17), P.hardDark)
		end
		-- 좌우 스포크 + 은색 띠 + 버튼 패널
		for _, s in { -1, 1 } do
			local len = R - 0.24
			local cx = s * (0.22 + len / 2)
			local sp = W * CFrame.new(cx, -0.06, 0.02) * CFrame.Angles(0, 0, math.rad(s * -5))
			K:box("Spoke", Vector3.new(len + 0.06, 0.17, 0.07), sp, P.hard)
			K:box("SpokeTrim", Vector3.new(len, 0.024, 0.02), sp * CFrame.new(0, -0.075, 0.035), P.satin)
			local pan = W * CFrame.new(s * 0.33, -0.04, 0.06)
			K:box("ButtonPanel", Vector3.new(0.19, 0.12, 0.02), pan, P.gloss)
			for i = 0, 3 do
				local bx = -0.055 + (i % 2) * 0.11
				local by = 0.028 - math.floor(i / 2) * 0.056
				K:box("Button", Vector3.new(0.07, 0.036, 0.012), pan * CFrame.new(bx, by, 0.014), P.button)
			end
			-- 아래쪽 스포크
			local a = (W * CFrame.new(s * 0.07, -0.2, 0.0)).Position
			local ang = math.rad(-90 + s * 30)
			local b = (W * CFrame.new(math.cos(ang) * (R - 0.04), math.sin(ang) * (R - 0.04), -0.01)).Position
			K:seg("LowerSpoke", a, b, 0.075, P.hard)
			if sport then
				K:box("Paddle", Vector3.new(0.06, 0.26, 0.025), W * CFrame.new(s * (R - 0.1), 0.03, -0.1) * CFrame.Angles(0, 0, math.rad(s * 8)), P.paddle)
			end
		end
	end)
	out.wheelPivot, out.wheelWeld, out.wheelCF = pivot, weld, W

	-- 파노라믹 디스플레이 ---------------------------------------------------------------------------------
	local cl: Vector3 = F.cluster
	local nv: Vector3 = F.nav
	local commercial = F.kind == "truck" or F.kind == "ambulance"
	local yS = cl.Y + 0.03
	local zS = math.max(cl.Z, F.dashFace + 0.15)
	local tilt = CFrame.Angles(math.rad(-9), 0, 0)
	local accent: Color3 = P.accentColor
	local screens: any = {}
	if not commercial and math.abs(nv.X - cl.X) < 2.4 then
		local xL = cl.X - 0.72
		local xR = math.max(nv.X + math.max(F.navWide, 1.25) / 2 + 0.06, cl.X + 0.85)
		if F.side > 0 then -- 우핸들: 거울상
			xL, xR = math.min(nv.X - math.max(F.navWide, 1.25) / 2 - 0.06, cl.X - 0.85), cl.X + 0.72
		end
		local midX = (xL + xR) / 2
		local base = CFrame.new(midX, yS, zS) * tilt
		K:box("DisplayBezel", Vector3.new(xR - xL, 0.56, 0.07), base, P.gloss)
		K:box("DisplayEdge", Vector3.new(xR - xL - 0.02, 0.018, 0.02), base * CFrame.new(0, -0.27, 0.04), P.satin)
		K:box("DisplayBack", Vector3.new(xR - xL - 0.1, 0.42, 0.12), base * CFrame.new(0, 0, -0.09), P.hard)
		local clW = 1.36
		local clPart = K:box("ClusterGlass", Vector3.new(clW, 0.46, 0.02), base * CFrame.new(cl.X - midX, 0, 0.045), P.screen)
		local nvW = (xR - xL) - clW - 0.12
		local nvX = if F.side < 0 then (xR - 0.04 - nvW / 2) else (xL + 0.04 + nvW / 2)
		local nvPart = K:box("NavGlass", Vector3.new(nvW, 0.46, 0.02), base * CFrame.new(nvX - midX, 0, 0.045), P.screen)
		screens.cluster = Screens.cluster(clPart, accent, F.kind)
		screens.nav = Screens.nav(nvPart, accent)
		-- 계기판 차양 (부드러운 가죽 + 둥근 앞 끝)
		local hood = CFrame.new(cl.X, yS + 0.31, zS - 0.12) * CFrame.Angles(math.rad(-6), 0, 0)
		K:box("ClusterHood", Vector3.new(clW + 0.2, 0.05, 0.46), hood, P.soft)
		K:cyl("ClusterHoodLip", clW + 0.2, 0.09, hood * CFrame.new(0, -0.01, 0.23), P.soft)
		K:box("ClusterHoodStitch", Vector3.new(clW + 0.1, 0.008, 0.008), hood * CFrame.new(0, 0.03, 0.21), P.stitch)
	else
		-- 상용차: 계기판 + 태블릿형 화면 따로 (계기판은 대시 위로)
		local yC = math.max(yS, F.dashTop + 0.23)
		local clPart = K:box("ClusterGlass", Vector3.new(1.1, 0.42, 0.02), CFrame.new(cl.X, yC, zS + 0.04) * tilt, P.screen)
		K:box("ClusterBezel", Vector3.new(1.2, 0.5, 0.06), CFrame.new(cl.X, yC, zS) * tilt, P.gloss)
		K:box("ClusterHood", Vector3.new(1.3, 0.05, 0.42), CFrame.new(cl.X, yC + 0.28, zS - 0.1) * CFrame.Angles(math.rad(-6), 0, 0), P.soft)
		screens.cluster = Screens.cluster(clPart, accent, F.kind)
		local nvPart = K:box("NavGlass", Vector3.new(1.2, 0.5, 0.02), CFrame.new(nv.X, nv.Y, math.max(nv.Z, F.dashFace) + 0.04) * tilt, P.screen)
		K:box("NavBezel", Vector3.new(1.3, 0.58, 0.06), CFrame.new(nv.X, nv.Y, math.max(nv.Z, F.dashFace)) * tilt, P.gloss)
		screens.nav = Screens.nav(nvPart, accent)
	end
	out.screens = screens

	-- HUD 투사 창 + 시동 버튼 --------------------------------------------------------------------------------
	if not commercial then
		K:box("HudWindow", Vector3.new(0.62, 0.02, 0.3), CFrame.new(W.Position.X, F.dashTop + 0.012, F.dashFace - 0.75), P.gloss)
	end
	local sb = CFrame.new(W.Position.X - F.side * (R + 0.32), F.dashMidY + 0.05, F.dashFace + 0.03)
	K:cyl("StartRing", 0.04, 0.2, sb * ROT_X_TO_Z, P.chrome)
	K:cyl("StartButton", 0.05, 0.15, sb * CFrame.new(0, 0, 0.012) * ROT_X_TO_Z, P.startBtn)
	return out
end

return Cockpit
