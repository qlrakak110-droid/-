--!strict
-- GwangalliCarInterior/Screens: 화면 (SurfaceGui). 디지털 계기판(속도·RPM 원형 게이지 + 바늘, 기어, 방향지시,
-- 연료·수온, 시계·기온), 내비게이션(광안리 지도 + 경로 + 상단 바 + 하단 독), 공조 패널.
-- 모든 화면은 파트의 Back(+Z) 면 = 운전자 쪽에 붙습니다. Screens.update(screens, state) 로 살아 움직입니다.

local Lighting = game:GetService("Lighting")

local Screens = {}

local function gui(part: BasePart, pps: number, bg: Color3): (SurfaceGui, Frame)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Screen"
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pps
	sg.LightInfluence = 0
	sg.Brightness = 1.6
	sg.ClipsDescendants = true
	local root = Instance.new("Frame")
	root.Name = "Face"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = bg
	root.BorderSizePixel = 0
	root.Parent = sg
	sg.Parent = part
	return sg, root
end

local function frame(parent: Instance, name: string, pos: UDim2, size: UDim2, color: Color3, transp: number?, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transp or 0
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function label(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3, font: Enum.Font?, z: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = pos
	t.Size = size
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = font or Enum.Font.GothamMedium
	t.TextColor3 = color
	t.ZIndex = z or 3
	t.Parent = parent
	return t
end

local function round(f: GuiObject, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r or 1, 0)
	c.Parent = f
end

local function stroke(f: GuiObject, color: Color3, th: number, tr: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = th
	s.Transparency = tr or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
end

local function gradient(f: GuiObject, a: Color3, b: Color3, rot: number)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rot
	g.Parent = f
end

-- 원형 게이지: 눈금 + 바늘 (바늘은 회전하는 Frame; 회전 중심 = 게이지 중심이 되도록 길이 2배 프레임의 반만 보이게)
local function dial(parent: Frame, cx: number, cy: number, dpx: number, accent: Color3, ticks: number, redFrom: number?): Frame
	local d = frame(parent, "Dial", UDim2.new(cx, 0, cy, 0), UDim2.fromOffset(dpx, dpx), Color3.fromRGB(10, 13, 18), 0.05, 2)
	round(d)
	stroke(d, accent, math.max(2, dpx * 0.018), 0.15)
	gradient(d, Color3.fromRGB(26, 32, 42), Color3.fromRGB(6, 8, 12), 90)
	for i = 0, ticks do
		local a = math.rad(-225 + 270 * i / ticks)
		local major = i % 2 == 0
		local r = dpx * 0.42
		local t = frame(d, "Tick", UDim2.new(0.5, math.cos(a) * r, 0.5, math.sin(a) * r), UDim2.fromOffset(if major then dpx * 0.07 else dpx * 0.04, math.max(1, dpx * 0.012)), if redFrom and i / ticks >= redFrom then Color3.fromRGB(255, 70, 60) else Color3.fromRGB(190, 205, 222), 0, 3)
		t.Rotation = math.deg(a)
	end
	-- 바늘: 중심을 지나는 프레임, 바깥쪽 절반만 색 (UIGradient 투명도로 안쪽 절반을 숨김)
	local needle = frame(d, "Needle", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(dpx * 0.82, math.max(2, dpx * 0.022)), Color3.fromRGB(255, 96, 40), 0, 4)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.499, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0) })
	g.Parent = needle
	needle.Rotation = -225
	local cap = frame(d, "Cap", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(dpx * 0.1, dpx * 0.1), Color3.fromRGB(40, 46, 56), 0, 5)
	round(cap)
	return d
end

-- 디지털 계기판 ---------------------------------------------------------------------------------------
function Screens.cluster(part: BasePart, accent: Color3, kind: string)
	local _, root = gui(part, 260, Color3.fromRGB(4, 6, 10))
	gradient(root, Color3.fromRGB(14, 20, 30), Color3.fromRGB(2, 3, 6), 90)
	local W, H = part.Size.X * 260, part.Size.Y * 260
	local dpx = H * 0.86
	local speed = dial(root, 0.2, 0.52, dpx, accent, 12, nil)
	local rpm = dial(root, 0.8, 0.52, dpx, accent, 8, 0.75)
	local spd = label(speed, "Speed", "0", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.26), Color3.fromRGB(240, 246, 255), Enum.Font.GothamBold, 6)
	label(speed, "Unit", "km/h", UDim2.fromScale(0.5, 0.68), UDim2.fromScale(0.36, 0.1), Color3.fromRGB(140, 160, 185), nil, 6)
	label(rpm, "Unit", "x1000 rpm", UDim2.fromScale(0.5, 0.68), UDim2.fromScale(0.5, 0.1), Color3.fromRGB(140, 160, 185), nil, 6)
	-- 가운데 정보
	local mid = frame(root, "Info", UDim2.fromScale(0.5, 0.52), UDim2.fromOffset(W * 0.34, H * 0.82), Color3.fromRGB(0, 0, 0), 1, 2)
	local clock = label(mid, "Clock", "14:00", UDim2.fromScale(0.5, 0.1), UDim2.fromScale(0.5, 0.14), Color3.fromRGB(220, 230, 240))
	local temp = label(mid, "Temp", "24°C", UDim2.fromScale(0.5, 0.24), UDim2.fromScale(0.3, 0.1), Color3.fromRGB(140, 160, 185))
	local gears = {}
	local i = 0
	for _, g in { "P", "R", "N", "D" } do
		gears[g] = label(mid, "Gear" .. g, g, UDim2.fromScale(0.2 + 0.2 * i, 0.5), UDim2.fromScale(0.16, 0.22), Color3.fromRGB(90, 100, 115), Enum.Font.GothamBold)
		i += 1
	end
	local turnL = label(mid, "TurnL", "◀", UDim2.fromScale(0.08, 0.1), UDim2.fromScale(0.14, 0.16), Color3.fromRGB(40, 70, 45))
	local turnR = label(mid, "TurnR", "▶", UDim2.fromScale(0.92, 0.1), UDim2.fromScale(0.14, 0.16), Color3.fromRGB(40, 70, 45))
	local odo = label(mid, "Odo", "ODO 12,480 km", UDim2.fromScale(0.5, 0.78), UDim2.fromScale(0.8, 0.09), Color3.fromRGB(120, 135, 155))
	-- 연료 / 수온 바
	local function bar(name: string, y: number, fill: number, col: Color3): Frame
		local b = frame(mid, name, UDim2.fromScale(0.5, y), UDim2.fromScale(0.78, 0.035), Color3.fromRGB(30, 36, 46), 0, 3)
		round(b)
		local f = frame(b, "Fill", UDim2.fromScale(fill / 2, 0.5), UDim2.fromScale(fill, 1), col, 0, 4)
		round(f)
		return f
	end
	bar("Fuel", 0.9, 0.72, accent)
	bar("Coolant", 0.96, 0.5, Color3.fromRGB(120, 200, 255))
	local brand = if kind == "luxury" then "GENESIS" else "HYUNDAI"
	label(root, "Brand", brand, UDim2.fromScale(0.5, 0.06), UDim2.fromScale(0.12, 0.07), Color3.fromRGB(70, 80, 95))
	return {
		speedNeedle = speed:FindFirstChild("Needle") :: Frame,
		rpmNeedle = rpm:FindFirstChild("Needle") :: Frame,
		speed = spd,
		gears = gears,
		clock = clock,
		temp = temp,
		turnL = turnL,
		turnR = turnR,
		odo = odo,
		accent = accent,
	}
end

-- 내비게이션 (광안리) --------------------------------------------------------------------------------------
function Screens.nav(part: BasePart, accent: Color3)
	local _, root = gui(part, 220, Color3.fromRGB(16, 22, 30))
	local map = frame(root, "Map", UDim2.fromScale(0.5, 0.52), UDim2.fromScale(1, 0.76), Color3.fromRGB(26, 33, 42), 0, 1)
	-- 바다 (광안리 앞바다) + 해변 + 도로 + 광안대교
	frame(map, "Sea", UDim2.fromScale(0.5, 0.86), UDim2.fromScale(1.1, 0.4), Color3.fromRGB(14, 40, 70), 0, 1)
	frame(map, "Beach", UDim2.fromScale(0.5, 0.66), UDim2.fromScale(1.1, 0.06), Color3.fromRGB(150, 130, 90), 0.4, 2)
	local roads = {
		{ 0.5, 0.58, 1.2, 0.035, 0 },
		{ 0.3, 0.3, 0.9, 0.025, -18 },
		{ 0.72, 0.32, 0.028, 0.7, 8 },
		{ 0.18, 0.4, 0.02, 0.7, -4 },
		{ 0.55, 0.15, 0.9, 0.02, 4 },
	}
	for _, r in roads do
		local f = frame(map, "Road", UDim2.fromScale(r[1], r[2]), UDim2.fromScale(r[3], r[4]), Color3.fromRGB(70, 80, 94), 0, 2)
		f.Rotation = r[5]
	end
	local bridge = frame(map, "Bridge", UDim2.fromScale(0.62, 0.86), UDim2.fromScale(0.95, 0.03), Color3.fromRGB(200, 205, 215), 0.1, 3)
	bridge.Rotation = -8
	local route = frame(map, "Route", UDim2.fromScale(0.42, 0.58), UDim2.fromScale(0.62, 0.05), accent, 0, 4)
	round(route)
	local route2 = frame(map, "Route", UDim2.fromScale(0.72, 0.44), UDim2.fromScale(0.05, 0.32), accent, 0, 4)
	round(route2)
	local me = frame(map, "Me", UDim2.fromScale(0.2, 0.58), UDim2.fromOffset(18, 18), Color3.fromRGB(255, 255, 255), 0, 6)
	me.Rotation = 45
	stroke(me, accent, 3)
	-- 상단 안내 바
	local top = frame(root, "Top", UDim2.fromScale(0.5, 0.07), UDim2.fromScale(1, 0.14), Color3.fromRGB(8, 12, 18), 0.05, 5)
	label(top, "Turn", "↱ 300m", UDim2.fromScale(0.12, 0.5), UDim2.fromScale(0.2, 0.8), Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 6)
	label(top, "Road", "광안해변로 → 광안대교", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.7), Color3.fromRGB(210, 225, 240), nil, 6)
	local clock = label(top, "Clock", "14:00", UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.14, 0.7), Color3.fromRGB(210, 225, 240), nil, 6)
	-- 하단 독
	local dock = frame(root, "Dock", UDim2.fromScale(0.5, 0.95), UDim2.fromScale(1, 0.1), Color3.fromRGB(8, 12, 18), 0.05, 5)
	local icons = { "⌂", "♪", "☎", "❄", "⚙" }
	for k, ic in icons do
		local b = frame(dock, "Icon", UDim2.fromScale(0.1 + 0.2 * (k - 1), 0.5), UDim2.fromOffset(26, 26), Color3.fromRGB(34, 44, 58), 0, 6)
		round(b, 0.3)
		label(b, "Glyph", ic, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.8), Color3.fromRGB(200, 215, 230), nil, 7)
	end
	label(map, "Eta", "도착 14:12 · 2.1km", UDim2.fromScale(0.82, 0.08), UDim2.fromScale(0.32, 0.09), Color3.fromRGB(220, 230, 240), nil, 6)
	return { clock = clock }
end

-- 공조 패널 ---------------------------------------------------------------------------------------------
function Screens.climate(part: BasePart, accent: Color3)
	local _, root = gui(part, 220, Color3.fromRGB(6, 8, 11))
	label(root, "L", "22.0°", UDim2.fromScale(0.13, 0.5), UDim2.fromScale(0.2, 0.6), Color3.fromRGB(230, 238, 248), Enum.Font.GothamBold)
	label(root, "Auto", "AUTO  ❄  A/C", UDim2.fromScale(0.5, 0.32), UDim2.fromScale(0.4, 0.3), accent)
	for i = 1, 7 do
		local f = frame(root, "Fan", UDim2.fromScale(0.32 + i * 0.045, 0.72), UDim2.fromScale(0.03, 0.08 + i * 0.03), if i <= 3 then accent else Color3.fromRGB(50, 60, 72), 0, 2)
		f.AnchorPoint = Vector2.new(0.5, 1)
		f.Position = UDim2.fromScale(0.32 + i * 0.045, 0.85)
	end
	label(root, "R", "22.0°", UDim2.fromScale(0.87, 0.5), UDim2.fromScale(0.2, 0.6), Color3.fromRGB(230, 238, 248), Enum.Font.GothamBold)
	return {}
end

local GEAR_ON = Color3.fromRGB(255, 255, 255)
local GEAR_OFF = Color3.fromRGB(80, 90, 105)

-- state = { kmh, rpm, gear, turnL, turnR }
function Screens.update(s: any, state: any)
	local c = s.cluster
	if c then
		local kmh = math.abs(state.kmh or 0)
		c.speed.Text = tostring(math.floor(kmh + 0.5))
		c.speedNeedle.Rotation = -225 + 270 * math.clamp(kmh / 240, 0, 1)
		c.rpmNeedle.Rotation = -225 + 270 * math.clamp((state.rpm or 800) / 8000, 0, 1)
		for g, l in c.gears do
			l.TextColor3 = if g == state.gear then GEAR_ON else GEAR_OFF
		end
		c.turnL.TextColor3 = if state.turnL then Color3.fromRGB(60, 255, 110) else Color3.fromRGB(40, 70, 45)
		c.turnR.TextColor3 = if state.turnR then Color3.fromRGB(60, 255, 110) else Color3.fromRGB(40, 70, 45)
	end
	local t = Lighting.ClockTime
	local hh, mm = math.floor(t), math.floor((t % 1) * 60)
	local txt = string.format("%02d:%02d", hh, mm)
	if c then
		c.clock.Text = txt
	end
	if s.nav then
		s.nav.clock.Text = txt
	end
end

return Screens
