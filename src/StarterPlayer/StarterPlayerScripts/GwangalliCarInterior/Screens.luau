--!strict
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
