--[[
	📁 위치: ReplicatedStorage  >  ModuleScript  (이름: CarBuilder)
	차량 외부 + 내부 모델을 파트로 자동 생성합니다. (메쉬 업로드 필요 없음)
	- 문은 경첩으로 열림/닫힘 애니메이션
	- 바퀴/핸들은 Motor6D 로 회전
	- 모든 파트는 Weld 로 차체(Chassis)에 고정 → 차가 사라지거나 분해되는 버그 방지
]]

local Config = require(script.Parent:WaitForChild("CarConfig"))

local CarBuilder = {}

-- 차체 모양 데이터 (단위: 스터드, 앞쪽 = -Z, 오른쪽 = +X, 원점 = 차체 중심)
local STYLES = {
	sedan = {
		L = 17, W = 7.6, rideH = 2.6, R = 1.25, track = 3.0,
		bottom = -1.6, belt = 1.1, roof = 3.5,
		noseY = 0.65, cowlZ = -2.1, roofF = 0.4, roofR = 3.7,
		deckZ = 6.0, deckY = 1.2, tailY = 1.05,
		axleF = -5.4, axleR = 6.1,
		doors = { { -2.0, 1.5 }, { 1.5, 4.5 } },
		seatY = -0.6, frontSeatZ = 0.8, rearSeatZ = 3.5,
		rim = Color3.fromRGB(190, 192, 198),
	},
	hatch = {
		L = 15, W = 7.4, rideH = 2.6, R = 1.2, track = 2.95,
		bottom = -1.6, belt = 1.15, roof = 3.6,
		noseY = 0.7, cowlZ = -1.9, roofF = 0.5, roofR = 4.3,
		deckZ = 5.7, deckY = 1.6, tailY = 1.35,
		axleF = -4.6, axleR = 4.9,
		doors = { { -1.8, 1.2 }, { 1.2, 3.4 } },
		seatY = -0.6, frontSeatZ = 0.5, rearSeatZ = 2.5,
		rim = Color3.fromRGB(160, 162, 168),
	},
	suv = {
		L = 17.5, W = 8, rideH = 3.2, R = 1.5, track = 3.15,
		bottom = -1.3, belt = 1.6, roof = 4.4,
		noseY = 1.2, cowlZ = -2.6, roofF = 0.0, roofR = 6.2,
		deckZ = 7.3, deckY = 2.0, tailY = 1.6,
		axleF = -5.6, axleR = 5.6,
		doors = { { -2.5, 1.3 }, { 1.3, 3.7 } },
		seatY = -0.2, frontSeatZ = 0.3, rearSeatZ = 2.6,
		rim = Color3.fromRGB(70, 72, 78), suv = true,
	},
	sports = {
		L = 17, W = 8, rideH = 2.2, R = 1.2, track = 3.2,
		bottom = -1.4, belt = 0.9, roof = 2.9,
		noseY = 0.45, cowlZ = -1.3, roofF = 1.0, roofR = 2.8,
		deckZ = 6.0, deckY = 1.0, tailY = 0.95,
		axleF = -5.3, axleR = 5.4,
		doors = { { -1.2, 2.8 } },
		seatY = -0.85, frontSeatZ = 1.7, rearSeatZ = nil,
		rim = Color3.fromRGB(40, 40, 44), spoiler = true,
	},
}
CarBuilder.STYLES = STYLES

local BLACK = Color3.fromRGB(16, 16, 18)
local TRIM = Color3.fromRGB(34, 34, 37)
local CHROME = Color3.fromRGB(205, 207, 212)
local GLASS = Color3.fromRGB(22, 30, 38)
local NEON_WHITE = Color3.fromRGB(255, 250, 235)
local NEON_RED = Color3.fromRGB(255, 20, 20)
local NEON_ORANGE = Color3.fromRGB(255, 140, 0)

local PLATE_LETTERS = { "가", "나", "다", "라", "마", "거", "너", "더", "러", "머", "버", "서", "어", "저", "고", "노", "도", "로", "모", "보", "소", "오", "조", "구", "누", "두", "루", "무", "부", "수", "우", "주" }

---------------------------------------------------------------- 공통 헬퍼
local function newPart(class, parent, props)
	local p = Instance.new(class)
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "Shape" then
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function weldTo(part, base)
	local w = Instance.new("Weld")
	w.Name = "W"
	w.Part0 = base
	w.Part1 = part
	w.C0 = base.CFrame:Inverse() * part.CFrame
	w.C1 = CFrame.new()
	w.Parent = part
	return w
end

local function mix(a, b)
	local t = {}
	for k, v in pairs(a) do
		t[k] = v
	end
	if b then
		for k, v in pairs(b) do
			t[k] = v
		end
	end
	return t
end

local function surfaceText(part, face, text, textColor, bgColor, ppS)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppS or 80
	sg.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bgColor or Color3.new(1, 1, 1)
	t.BackgroundTransparency = bgColor and 0 or 1
	t.BorderSizePixel = 0
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = textColor
	t.Parent = sg
	sg.Parent = part
	return sg, t
end

---------------------------------------------------------------- 빌더 컨텍스트
local Ctx = {}
Ctx.__index = Ctx

-- 상자 파트 (기본: 차체에 용접)
function Ctx:box(name, size, cf, props, zone, base)
	local p = newPart("Part", self.model, mix({ Name = name, Size = size, CFrame = cf }, props))
	weldTo(p, base or self.root)
	if zone then
		p:SetAttribute("Zone", zone)
	end
	return p
end

function Ctx:wedge(name, size, cf, props, zone, base)
	local p = newPart("WedgePart", self.model, mix({ Name = name, Size = size, CFrame = cf }, props))
	weldTo(p, base or self.root)
	if zone then
		p:SetAttribute("Zone", zone)
	end
	return p
end

function Ctx:cyl(name, size, cf, props, zone, base)
	local p = newPart("Part", self.model, mix({ Name = name, Shape = Enum.PartType.Cylinder, Size = size, CFrame = cf }, props))
	weldTo(p, base or self.root)
	if zone then
		p:SetAttribute("Zone", zone)
	end
	return p
end

-- 기울어진 판넬: a,b = Vector2(z, y) 윗면 라인
function Ctx:slab(name, a, b, width, thick, x, props, zone, base)
	local pa = Vector3.new(x, a.Y, a.X)
	local pb = Vector3.new(x, b.Y, b.X)
	local d = pb - pa
	local len = d.Magnitude
	d = d.Unit
	local n = Vector3.new(0, -d.Z, d.Y)
	if n.Y < 0 then
		n = -n
	end
	local c = (pa + pb) / 2 - n * (thick / 2)
	return self:box(name, Vector3.new(width, thick, len), CFrame.lookAt(c, c + d, n), props, zone, base)
end

-- 옆유리 삼각형: fullAtRear=true 면 뒤쪽이 높음
function Ctx:sideWedge(name, x, z0, z1, y0, y1, fullAtRear, props, zone, base)
	local cf = CFrame.new(x, (y0 + y1) / 2, (z0 + z1) / 2)
	if not fullAtRear then
		cf = cf * CFrame.Angles(0, math.pi, 0)
	end
	return self:wedge(name, Vector3.new(0.12, y1 - y0, z1 - z0), cf, props, zone, base)
end

---------------------------------------------------------------- 바퀴
function Ctx:wheel(name, side, z)
	local st = self.st
	local R = st.R
	local hubCF = CFrame.new(side * st.track, self.wheelY, z)
	local hub = newPart("Part", self.model, { Name = "Hub" .. name, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = hubCF, Transparency = 1 })
	local m = Instance.new("Motor6D")
	m.Name = "Wheel" .. name
	m.Part0 = self.root
	m.Part1 = hub
	m.C0 = hubCF
	m.C1 = CFrame.new()
	m.Parent = self.root

	local function wp(pname, size, offset, props, isCyl)
		local p
		if isCyl then
			p = newPart("Part", self.model, mix({ Name = pname, Shape = Enum.PartType.Cylinder, Size = size, CFrame = hubCF * offset }, props))
		else
			p = newPart("Part", self.model, mix({ Name = pname, Size = size, CFrame = hubCF * offset }, props))
		end
		weldTo(p, hub)
		return p
	end

	local rim = st.rim
	wp("Tire", Vector3.new(1.3, 2 * R, 2 * R), CFrame.new(), { Color = Color3.fromRGB(26, 26, 28) }, true)
	wp("TireWall", Vector3.new(0.06, 2 * R - 0.22, 2 * R - 0.22), CFrame.new(side * 0.66, 0, 0), { Color = Color3.fromRGB(44, 44, 47) }, true)
	wp("RimBarrel", Vector3.new(0.08, 1.42 * R, 1.42 * R), CFrame.new(side * 0.7, 0, 0), { Color = Color3.fromRGB(55, 56, 60), Material = Enum.Material.Metal }, true)
	wp("Disc", Vector3.new(0.1, 1.1 * R, 1.1 * R), CFrame.new(side * 0.48, 0, 0), { Color = Color3.fromRGB(95, 95, 100), Material = Enum.Material.Metal }, true)
	for i = 0, 4 do
		local ang = i * 2 * math.pi / 5
		wp("Spoke", Vector3.new(0.12, 0.24, 0.62 * R), CFrame.new(side * 0.74, 0, 0) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, 0, 0.33 * R),
			{ Color = rim, Material = Enum.Material.Metal, Reflectance = 0.15 })
	end
	-- 림 테두리 (작은 조각 원형)
	local seg = 12
	for i = 0, seg - 1 do
		local ang = i * 2 * math.pi / seg
		wp("RimLip", Vector3.new(0.12, 0.14, 2 * math.pi * 0.7 * R / seg + 0.05),
			CFrame.new(side * 0.73, 0, 0) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, 0.68 * R, 0),
			{ Color = rim, Material = Enum.Material.Metal, Reflectance = 0.15 })
	end
	wp("Cap", Vector3.new(0.1, 0.4 * R, 0.4 * R), CFrame.new(side * 0.78, 0, 0), { Color = CHROME, Material = Enum.Material.Metal, Reflectance = 0.3 }, true)
	return hub
end

-- 휠하우스 (검정 안쪽 + 아치 몰딩 + 모서리 채움)
function Ctx:wheelArch(side, axle)
	local st = self.st
	local Ra = st.R + 0.3
	local W = st.W
	local wy = self.wheelY
	self:cyl("WheelLiner", Vector3.new(0.3, 2 * Ra, 2 * Ra), CFrame.new(side * (st.track - 0.85), wy, axle), { Color = BLACK })
	local n = 9
	local r = Ra + 0.12
	local x = side * (W / 2 - 0.02)
	for i = 1, n do
		local a = (i - 0.5) / n * math.pi
		local pos = Vector3.new(x, wy + r * math.sin(a), axle + r * math.cos(a))
		local tangent = Vector3.new(0, math.cos(a), -math.sin(a))
		local radial = Vector3.new(0, math.sin(a), math.cos(a))
		self:box("ArchTrim", Vector3.new(0.3, 0.28, math.pi * r / n + 0.06), CFrame.lookAt(pos, pos + tangent, radial),
			{ Color = st.suv and BLACK or TRIM })
	end
	local s = Ra * 0.42
	local top = wy + Ra
	local paint = { Color = self.color, Reflectance = 0.12 }
	-- 앞쪽 위 모서리
	self:wedge("ArchFill", Vector3.new(0.5, s, s), CFrame.new(side * (W / 2 - 0.25), top - s / 2, axle - Ra + s / 2) * CFrame.Angles(math.pi, 0, 0), paint)
	-- 뒤쪽 위 모서리
	self:wedge("ArchFill", Vector3.new(0.5, s, s), CFrame.new(side * (W / 2 - 0.25), top - s / 2, axle + Ra - s / 2) * CFrame.Angles(0, 0, math.pi), paint)
end

---------------------------------------------------------------- 문
function Ctx:door(side, z0, z1, isFront)
	local st = self.st
	local W = st.W
	local doorName = "Door_" .. (isFront and "F" or "R") .. (side < 0 and "L" or "R")
	local hingeCF = CFrame.new(side * (W / 2), (st.belt + st.bottom) / 2, z0)
	local hinge = newPart("Part", self.model, { Name = doorName, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = hingeCF, Transparency = 1 })
	local hw = weldTo(hinge, self.root)
	hw.Name = "Hinge"
	hinge:SetAttribute("OpenAngle", side * 70)
	hinge:SetAttribute("IsDoor", true)

	local zone = side < 0 and "L" or "Rt"
	local len = z1 - z0 - 0.08
	local zc = (z0 + z1) / 2
	local bot = st.bottom + 0.25
	local paint = { Color = self.color, Reflectance = 0.12 }
	local inner = { Color = self.interiorDark, Material = Enum.Material.Leather }

	local panel = self:box("DoorPanel", Vector3.new(0.35, st.belt - bot, len), CFrame.new(side * (W / 2 - 0.175), (st.belt + bot) / 2, zc), paint, zone, hinge)
	-- 캐릭터 라인 (프레스 라인)
	self:box("DoorLine", Vector3.new(0.04, 0.07, len), CFrame.new(side * (W / 2 + 0.01), st.belt - 0.5, zc), { Color = self.color:Lerp(Color3.new(0, 0, 0), 0.25), Reflectance = 0.12 }, zone, hinge)
	-- 벨트라인 몰딩
	self:box("BeltTrim", Vector3.new(0.42, 0.08, len), CFrame.new(side * (W / 2 - 0.2), st.belt + 0.03, zc), { Color = self.taxi and BLACK or CHROME, Material = Enum.Material.Metal }, zone, hinge)
	-- 안쪽 트림 + 팔걸이 + 스피커
	self:box("DoorInner", Vector3.new(0.15, st.belt - bot - 0.2, len - 0.3), CFrame.new(side * (W / 2 - 0.42), (st.belt + bot) / 2, zc), inner, nil, hinge)
	self:box("Armrest", Vector3.new(0.35, 0.15, len * 0.5), CFrame.new(side * (W / 2 - 0.6), st.belt - 0.65, zc), { Color = self.interior, Material = Enum.Material.Leather }, nil, hinge)
	self:cyl("Speaker", Vector3.new(0.05, 0.6, 0.6), CFrame.new(side * (W / 2 - 0.5), bot + 0.55, z0 + 0.7), { Color = Color3.fromRGB(70, 70, 75), Material = Enum.Material.Metal }, nil, hinge)
	-- 손잡이
	self:box("Handle", Vector3.new(0.1, 0.16, 0.7), CFrame.new(side * (W / 2 + 0.03), st.belt - 0.35, z1 - 0.75), { Color = CHROME, Material = Enum.Material.Metal, Reflectance = 0.3 }, zone, hinge)

	-- 창문 유리
	local gx = side * (W / 2 - 0.4)
	local glass = { Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }
	local gTop = st.roof - 0.2
	if isFront and st.roofF > z0 + 0.1 then
		local g = self:sideWedge("DoorGlass", gx, z0 + 0.05, st.roofF, st.belt + 0.05, gTop, true, glass, zone, hinge)
		g:SetAttribute("Glass", true)
		local zr = math.min(z1, st.roofR) - 0.05
		if zr > st.roofF + 0.05 then
			local g2 = self:box("DoorGlass", Vector3.new(0.12, gTop - st.belt - 0.05, zr - st.roofF), CFrame.new(gx, (gTop + st.belt + 0.05) / 2, (st.roofF + zr) / 2), glass, zone, hinge)
			g2:SetAttribute("Glass", true)
		end
	else
		local za = z0 + 0.08
		local zr = math.min(z1, st.roofR) - 0.05
		if zr > za then
			local g = self:box("DoorGlass", Vector3.new(0.12, gTop - st.belt - 0.05, zr - za), CFrame.new(gx, (gTop + st.belt + 0.05) / 2, (za + zr) / 2), glass, zone, hinge)
			g:SetAttribute("Glass", true)
		end
	end
	-- 사이드미러 (앞문)
	if isFront then
		local mz = z0 + 0.6
		self:box("MirrorArm", Vector3.new(0.6, 0.15, 0.3), CFrame.new(side * (W / 2 + 0.2), st.belt + 0.15, mz), { Color = BLACK }, zone, hinge)
		self:box("Mirror", Vector3.new(0.45, 0.5, 0.75), CFrame.new(side * (W / 2 + 0.55), st.belt + 0.35, mz), paint, zone, hinge)
		self:box("MirrorGlass", Vector3.new(0.38, 0.4, 0.05), CFrame.new(side * (W / 2 + 0.55), st.belt + 0.35, mz + 0.39), { Color = Color3.fromRGB(180, 190, 200), Reflectance = 0.6 }, zone, hinge)
		local sig = self:box("MirrorSignal", Vector3.new(0.06, 0.08, 0.5), CFrame.new(side * (W / 2 + 0.79), st.belt + 0.3, mz), { Color = NEON_ORANGE, Material = Enum.Material.Neon, Transparency = 0.4 }, zone, hinge)
		sig:SetAttribute("Light", "Signal")
		if self.taxi then
			local face = side < 0 and Enum.NormalId.Left or Enum.NormalId.Right
			local sg = surfaceText(panel, face, "개인택시", Color3.fromRGB(30, 30, 30), nil, 40)
			sg.LightInfluence = 1
		end
	end
	return hinge
end

---------------------------------------------------------------- 좌석
function Ctx:seat(seatName, x, z, width)
	local st = self.st
	local y = st.seatY
	local leather = { Color = self.interior, Material = Enum.Material.Leather }
	local dark = { Color = self.interiorDark, Material = Enum.Material.Leather }
	width = width or 1.8
	self:box("Cushion", Vector3.new(width, 0.45, 1.8), CFrame.new(x, y - 0.22, z), leather)
	self:box("SeatBase", Vector3.new(width - 0.3, 0.4, 1.4), CFrame.new(x, y - 0.6, z), dark)
	for _, s in ipairs({ -1, 1 }) do
		self:box("Bolster", Vector3.new(0.25, 0.25, 1.7), CFrame.new(x + s * (width / 2 - 0.12), y + 0.05, z), dark)
	end
	local backCF = CFrame.new(x, y + 1.0, z + 0.95) * CFrame.Angles(math.rad(12), 0, 0)
	self:box("SeatBack", Vector3.new(width, 2.1, 0.45), backCF, leather)
	self:box("SeatBackRear", Vector3.new(width - 0.1, 2.0, 0.1), backCF * CFrame.new(0, 0, 0.27), dark)
	self:box("Headrest", Vector3.new(math.min(1.0, width), 0.55, 0.35), backCF * CFrame.new(0, 1.4, 0.05), leather)
	self:box("HeadrestPost", Vector3.new(0.5, 0.3, 0.08), backCF * CFrame.new(0, 1.1, 0.05), { Color = CHROME, Material = Enum.Material.Metal })

	local s = newPart("Seat", self.model, {
		Name = seatName, Size = Vector3.new(1.6, 0.2, 1.6), CFrame = CFrame.new(x, y - 0.1, z), Transparency = 1,
	})
	s.CanTouch = false -- 걸어가다 닿아도 앉지 않도록 (스크립트로만 탑승)
	weldTo(s, self.root)
	return s
end

---------------------------------------------------------------- 메인 빌드
function CarBuilder.Build(carType, opts)
	opts = opts or {}
	local spec = Config.Cars[carType]
	assert(spec, "알 수 없는 차량: " .. tostring(carType))
	local st = STYLES[spec.Style]
	local W, L = st.W, st.L

	local model = Instance.new("Model")
	model.Name = carType

	local root = newPart("Part", model, {
		Name = "Chassis", Size = Vector3.new(W - 0.6, 2, L - 1.2), CFrame = CFrame.new(),
		Transparency = 1, CanCollide = true, CanQuery = true, CanTouch = true, Massless = false,
		CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.3, 0.1, 1, 1),
	})
	model.PrimaryPart = root

	local B = setmetatable({}, Ctx)
	B.model, B.root, B.st = model, root, st
	B.color = opts.Color or spec.Color
	B.interior = spec.Interior
	B.interiorDark = spec.Interior:Lerp(Color3.new(0, 0, 0), 0.55)
	B.taxi = spec.Taxi
	B.wheelY = -(st.rideH - st.R)

	local paint = { Color = B.color, Reflectance = 0.12 }
	local black = { Color = BLACK }
	local trim = { Color = TRIM }
	local glass = { Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }
	local chrome = { Color = CHROME, Material = Enum.Material.Metal, Reflectance = 0.3 }
	local Ra = st.R + 0.3
	local frontDoorZ = st.doors[1][1]
	local lastDoorZ = st.doors[#st.doors][2]
	local driverX = -(W / 2 - 2.2)

	------------------------------------------------ 앞 블록
	do
		local zA, zB = -L / 2 + 0.4, frontDoorZ
		local archTop = B.wheelY + Ra
		local upperTop = math.max(st.noseY - 0.05, archTop + 0.15)
		local a0, a1 = st.axleF - Ra, st.axleF + Ra
		B:box("FrontUpper", Vector3.new(W, upperTop - archTop, zB - zA), CFrame.new(0, (upperTop + archTop) / 2, (zA + zB) / 2), paint, "F")
		B:box("FrontLowerA", Vector3.new(W, archTop - st.bottom, a0 - zA), CFrame.new(0, (archTop + st.bottom) / 2, (zA + a0) / 2), paint, "F")
		B:box("FrontLowerB", Vector3.new(W, archTop - st.bottom, zB - a1), CFrame.new(0, (archTop + st.bottom) / 2, (a1 + zB) / 2), paint, "F")
		B:box("FrontUnder", Vector3.new(2 * (st.track - 0.9), archTop - st.bottom - 0.2, a1 - a0), CFrame.new(0, (archTop + st.bottom + 0.2) / 2, st.axleF), black)
		-- 보닛
		local hoodThick = (st.belt - st.noseY) + 0.45
		local hood = B:slab("Hood", Vector2.new(-L / 2 + 0.25, st.noseY), Vector2.new(st.cowlZ, st.belt), W - 0.1, hoodThick, 0, paint, "F")
		hood:SetAttribute("Hood", true)
		for _, s in ipairs({ -1, 1 }) do
			B:slab("HoodLine", Vector2.new(-L / 2 + 0.6, st.noseY + 0.03), Vector2.new(st.cowlZ, st.belt + 0.03), 0.18, 0.3, s * 1.4, paint, "F")
		end
		-- 카울 + 와이퍼
		B:slab("Cowl", Vector2.new(st.cowlZ - 0.6, st.belt + 0.04), Vector2.new(st.cowlZ + 0.05, st.belt + 0.06), W - 1.0, 0.15, 0, black)
		for _, s in ipairs({ -1, 1 }) do
			B:box("Wiper", Vector3.new(2.4, 0.08, 0.1), CFrame.new(s * 1.3, st.belt + 0.14, st.cowlZ + 0.1) * CFrame.Angles(0, 0, math.rad(s * 6)), black)
		end
	end

	------------------------------------------------ 뒷 블록
	do
		local zA, zB = lastDoorZ, L / 2 - 0.4
		local archTop = B.wheelY + Ra
		local a0, a1 = st.axleR - Ra, st.axleR + Ra
		B:box("RearUpper", Vector3.new(W, st.belt - archTop, zB - zA), CFrame.new(0, (st.belt + archTop) / 2, (zA + zB) / 2), paint, "R")
		B:box("RearLowerA", Vector3.new(W, archTop - st.bottom, a0 - zA), CFrame.new(0, (archTop + st.bottom) / 2, (zA + a0) / 2), paint, "R")
		B:box("RearLowerB", Vector3.new(W, archTop - st.bottom, zB - a1), CFrame.new(0, (archTop + st.bottom) / 2, (a1 + zB) / 2), paint, "R")
		B:box("RearUnder", Vector3.new(2 * (st.track - 0.9), archTop - st.bottom - 0.2, a1 - a0), CFrame.new(0, (archTop + st.bottom + 0.2) / 2, st.axleR), black)
		local deckThick = math.max(st.deckY, st.tailY) - st.belt + 0.55
		local deck = B:slab("Trunk", Vector2.new(st.deckZ, st.deckY), Vector2.new(L / 2 - 0.2, st.tailY), W - 0.1, deckThick, 0, paint, "R")
		deck:SetAttribute("Trunk", true)
	end

	------------------------------------------------ 실 / 바닥
	B:box("Sill", Vector3.new(W, 0.45, lastDoorZ - frontDoorZ), CFrame.new(0, st.bottom + 0.225, (frontDoorZ + lastDoorZ) / 2), paint)
	B:box("Floor", Vector3.new(W - 0.9, 0.15, lastDoorZ - frontDoorZ), CFrame.new(0, st.bottom + 0.5, (frontDoorZ + lastDoorZ) / 2), { Color = B.interiorDark, Material = Enum.Material.Fabric })
	for _, s in ipairs({ -1, 1 }) do
		B:box("SideSkirt", Vector3.new(0.2, 0.25, lastDoorZ - frontDoorZ), CFrame.new(s * (W / 2 + 0.02), st.bottom + 0.15, (frontDoorZ + lastDoorZ) / 2), st.spoiler and black or trim)
	end

	------------------------------------------------ 캐빈 (유리/지붕/필러)
	local ws = B:slab("Windshield", Vector2.new(st.cowlZ, st.belt), Vector2.new(st.roofF, st.roof), W - 1.2, 0.12, 0, glass, "F")
	ws:SetAttribute("Windshield", true)
	ws:SetAttribute("Glass", true)
	local rw = B:slab("RearWindow", Vector2.new(st.roofR, st.roof), Vector2.new(st.deckZ, st.deckY), W - 1.2, 0.12, 0, glass, "R")
	rw:SetAttribute("Glass", true)
	B:slab("Roof", Vector2.new(st.roofF - 0.15, st.roof + 0.12), Vector2.new(st.roofR + 0.15, st.roof + 0.12), W - 0.75, 0.4, 0, paint)
	B:box("Headliner", Vector3.new(W - 1.1, 0.1, st.roofR - st.roofF), CFrame.new(0, st.roof - 0.33, (st.roofF + st.roofR) / 2), { Color = Color3.fromRGB(190, 188, 182), Material = Enum.Material.Fabric })
	B:wedge("SharkFin", Vector3.new(0.3, 0.3, 0.8), CFrame.new(0, st.roof + 0.27, st.roofR - 0.6), black)
	for _, s in ipairs({ -1, 1 }) do
		B:slab("APillar", Vector2.new(st.cowlZ, st.belt), Vector2.new(st.roofF, st.roof + 0.05), 0.45, 0.35, s * (W / 2 - 0.45), paint)
		B:slab("CPillar", Vector2.new(st.roofR, st.roof + 0.05), Vector2.new(st.deckZ, st.deckY), 0.6, 0.35, s * (W / 2 - 0.5), paint)
		B:box("RoofRail", Vector3.new(0.3, 0.2, st.roofR - st.roofF), CFrame.new(s * (W / 2 - 0.42), st.roof - 0.05, (st.roofF + st.roofR) / 2), trim)
		if #st.doors > 1 then
			B:box("BPillar", Vector3.new(0.3, st.roof - st.belt, 0.45), CFrame.new(s * (W / 2 - 0.42), (st.roof + st.belt) / 2, st.doors[1][2]), black)
		end
		-- 고정 쿼터 유리
		local gx = s * (W / 2 - 0.4)
		local gTop = st.roof - 0.2
		local zone = s < 0 and "L" or "Rt"
		if st.roofR > lastDoorZ + 0.1 then
			local g = B:box("QuarterGlass", Vector3.new(0.12, gTop - st.belt - 0.05, st.roofR - lastDoorZ), CFrame.new(gx, (gTop + st.belt + 0.05) / 2, (lastDoorZ + st.roofR) / 2), glass, zone)
			g:SetAttribute("Glass", true)
		end
		local g2 = B:sideWedge("QuarterGlass", gx, st.roofR, st.deckZ, st.belt + 0.05, gTop, false, glass, zone)
		g2:SetAttribute("Glass", true)
	end

	------------------------------------------------ 앞 범퍼 / 그릴 / 헤드라이트
	do
		local z = -L / 2
		local bumperTop = st.bottom + 1.15
		local fb = B:box("FrontBumper", Vector3.new(W - 0.2, 1.0, 0.7), CFrame.new(0, st.bottom + 0.65, z + 0.35), paint, "F")
		fb:SetAttribute("Bumper", true)
		B:box("FrontLip", Vector3.new(W - 0.8, 0.25, 0.8), CFrame.new(0, st.bottom + 0.12, z + 0.4), black, "F")
		B:box("Intake", Vector3.new(W * 0.5, 0.35, 0.1), CFrame.new(0, st.bottom + 0.55, z - 0.02), black, "F")
		B:box("NosePanel", Vector3.new(W - 0.2, math.max(0.2, st.noseY - bumperTop), 0.3), CFrame.new(0, (st.noseY + bumperTop) / 2, z + 0.35), paint, "F")
		local gh = math.max(0.25, st.noseY - bumperTop - 0.05)
		B:box("Grille", Vector3.new(W * 0.42, gh, 0.15), CFrame.new(0, bumperTop + gh / 2, z + 0.18), black, "F")
		for i = 1, 3 do
			B:box("GrilleBar", Vector3.new(W * 0.4, 0.06, 0.05), CFrame.new(0, bumperTop + gh * i / 4, z + 0.09), chrome, "F")
		end
		B:box("Emblem", Vector3.new(0.6, 0.3, 0.06), CFrame.new(0, bumperTop + gh / 2, z + 0.05), chrome, "F")
		for _, s in ipairs({ -1, 1 }) do
			local hy = st.noseY - 0.32
			B:box("HeadHousing", Vector3.new(1.9, 0.55, 0.35), CFrame.new(s * (W / 2 - 1.15), hy, z + 0.3), { Color = BLACK, Reflectance = 0.2 }, "F")
			local lamp = B:box("HeadLamp", Vector3.new(0.85, 0.3, 0.06), CFrame.new(s * (W / 2 - 1.5), hy, z + 0.12), { Color = NEON_WHITE, Material = Enum.Material.Neon }, "F")
			lamp:SetAttribute("Light", "Head")
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Range = 70
			spot.Angle = 65
			spot.Brightness = 4
			spot.Shadows = false
			spot.Enabled = false
			spot.Parent = lamp
			local proj = B:box("HeadLamp2", Vector3.new(0.45, 0.3, 0.06), CFrame.new(s * (W / 2 - 0.75), hy, z + 0.12), { Color = NEON_WHITE, Material = Enum.Material.Neon }, "F")
			proj:SetAttribute("Light", "Head")
			local drl = B:box("DRL", Vector3.new(1.8, 0.07, 0.06), CFrame.new(s * (W / 2 - 1.15), hy + 0.22, z + 0.12), { Color = Color3.fromRGB(220, 235, 255), Material = Enum.Material.Neon }, "F")
			drl:SetAttribute("Light", "DRL")
			local fog = B:box("FogLamp", Vector3.new(0.5, 0.25, 0.1), CFrame.new(s * (W / 2 - 1.1), st.bottom + 0.55, z - 0.02), { Color = NEON_WHITE, Material = Enum.Material.Neon, Transparency = 0.2 }, "F")
			fog:SetAttribute("Light", "Fog")
		end
		local plate = B:box("FrontPlate", Vector3.new(2.2, 0.55, 0.06), CFrame.new(0, st.bottom + 0.7, z - 0.03), { Color = Color3.new(1, 1, 1) }, "F")
		local plateText = opts.Plate or (B.taxi and "서울31바" or tostring(math.random(10, 99)) .. PLATE_LETTERS[math.random(#PLATE_LETTERS)]) .. " " .. tostring(math.random(1000, 9999))
		surfaceText(plate, Enum.NormalId.Front, plateText, Color3.fromRGB(20, 20, 20), Color3.new(1, 1, 1), 60)
		model:SetAttribute("Plate", plateText)
	end

	------------------------------------------------ 뒷 범퍼 / 테일램프
	do
		local z = L / 2
		local bumperTop = st.bottom + 1.15
		local rb = B:box("RearBumper", Vector3.new(W - 0.2, 1.0, 0.7), CFrame.new(0, st.bottom + 0.65, z - 0.35), paint, "R")
		rb:SetAttribute("Bumper", true)
		B:box("Diffuser", Vector3.new(W - 1.2, 0.3, 0.8), CFrame.new(0, st.bottom + 0.15, z - 0.4), black, "R")
		B:box("TailPanel", Vector3.new(W - 0.2, math.max(0.2, st.tailY - bumperTop), 0.3), CFrame.new(0, (st.tailY + bumperTop) / 2, z - 0.35), paint, "R")
		for _, s in ipairs({ -1, 1 }) do
			local ty = st.tailY - 0.3
			B:box("TailHousing", Vector3.new(1.9, 0.5, 0.3), CFrame.new(s * (W / 2 - 1.1), ty, z - 0.25), { Color = Color3.fromRGB(60, 8, 8), Reflectance = 0.2 }, "R")
			local tl = B:box("TailLamp", Vector3.new(1.7, 0.32, 0.06), CFrame.new(s * (W / 2 - 1.1), ty + 0.04, z - 0.09), { Color = NEON_RED, Material = Enum.Material.Neon, Transparency = 0.35 }, "R")
			tl:SetAttribute("Light", "Tail")
			local rev = B:box("ReverseLamp", Vector3.new(0.4, 0.12, 0.06), CFrame.new(s * (W / 2 - 1.6), ty - 0.17, z - 0.09), { Color = NEON_WHITE, Material = Enum.Material.Neon, Transparency = 0.7 }, "R")
			rev:SetAttribute("Light", "Reverse")
			local sig = B:box("RearSignal", Vector3.new(0.4, 0.12, 0.06), CFrame.new(s * (W / 2 - 0.55), ty - 0.17, z - 0.09), { Color = NEON_ORANGE, Material = Enum.Material.Neon, Transparency = 0.6 }, "R")
			sig:SetAttribute("Light", "Signal")
		end
		local bar = B:box("TailBar", Vector3.new(W - 4.0, 0.1, 0.06), CFrame.new(0, st.tailY - 0.15, z - 0.12), { Color = NEON_RED, Material = Enum.Material.Neon, Transparency = 0.35 }, "R")
		bar:SetAttribute("Light", "Tail")
		local hb = B:box("HighBrake", Vector3.new(1.2, 0.08, 0.1), CFrame.new(0, st.deckY + 0.12, st.deckZ - 0.1), { Color = NEON_RED, Material = Enum.Material.Neon, Transparency = 0.8 }, "R")
		hb:SetAttribute("Light", "Brake")
		local plate = B:box("RearPlate", Vector3.new(2.2, 0.55, 0.06), CFrame.new(0, st.bottom + 0.95, z + 0.02), { Color = Color3.new(1, 1, 1) }, "R")
		surfaceText(plate, Enum.NormalId.Back, model:GetAttribute("Plate"), Color3.fromRGB(20, 20, 20), Color3.new(1, 1, 1), 60)
		local pipes = st.spoiler and { -2.2, -1.6, 1.6, 2.2 } or { -1.8, 1.8 }
		for _, px in ipairs(pipes) do
			B:cyl("Exhaust", Vector3.new(0.6, 0.38, 0.38), CFrame.new(px, st.bottom + 0.28, z - 0.05) * CFrame.Angles(0, math.pi / 2, 0), chrome, "R")
		end
	end

	------------------------------------------------ 휠하우스 & 바퀴
	for _, s in ipairs({ -1, 1 }) do
		B:wheelArch(s, st.axleF)
		B:wheelArch(s, st.axleR)
	end
	B:wheel("FL", -1, st.axleF)
	B:wheel("FR", 1, st.axleF)
	B:wheel("RL", -1, st.axleR)
	B:wheel("RR", 1, st.axleR)

	------------------------------------------------ 문
	for i, d in ipairs(st.doors) do
		B:door(-1, d[1], d[2], i == 1)
		B:door(1, d[1], d[2], i == 1)
	end

	------------------------------------------------ 실내
	do
		local dk = { Color = B.interiorDark, Material = Enum.Material.SmoothPlastic }
		local soft = { Color = B.interior, Material = Enum.Material.Leather }
		local dashZ = st.cowlZ + 0.62
		B:box("Dash", Vector3.new(W - 0.9, 0.85, 1.25), CFrame.new(0, st.belt - 0.25, dashZ), dk)
		B:box("DashTop", Vector3.new(W - 0.9, 0.1, 1.25), CFrame.new(0, st.belt + 0.22, dashZ), soft)
		B:box("UnderDash", Vector3.new(W - 0.9, 0.9, 0.6), CFrame.new(0, st.belt - 1.1, st.cowlZ + 0.4), dk)
		B:box("DashTrim", Vector3.new(W - 1.0, 0.08, 0.05), CFrame.new(0, st.belt - 0.15, dashZ + 0.63), { Color = CHROME, Material = Enum.Material.Metal })
		B:box("Binnacle", Vector3.new(2.2, 0.3, 0.6), CFrame.new(driverX, st.belt + 0.35, st.cowlZ + 1.0), dk)
		-- 계기판 (클라이언트가 실시간 갱신)
		local cluster = B:box("Cluster", Vector3.new(2.0, 0.7, 0.06), CFrame.new(driverX, st.belt + 0.05, st.cowlZ + 1.26), { Color = Color3.new(0, 0, 0) })
		do
			local sg = Instance.new("SurfaceGui")
			sg.Name = "Gui"
			sg.Face = Enum.NormalId.Back
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 120
			sg.LightInfluence = 0
			local bg = Instance.new("Frame")
			bg.Size = UDim2.fromScale(1, 1)
			bg.BackgroundColor3 = Color3.fromRGB(5, 8, 14)
			bg.BorderSizePixel = 0
			bg.Parent = sg
			local spd = Instance.new("TextLabel")
			spd.Name = "Speed"
			spd.Size = UDim2.fromScale(0.4, 0.7)
			spd.Position = UDim2.fromScale(0.3, 0.05)
			spd.BackgroundTransparency = 1
			spd.Text = "0"
			spd.TextScaled = true
			spd.Font = Enum.Font.GothamBlack
			spd.TextColor3 = Color3.fromRGB(120, 210, 255)
			spd.Parent = bg
			local unit = spd:Clone()
			unit.Name = "Unit"
			unit.Text = "km/h"
			unit.Size = UDim2.fromScale(0.4, 0.22)
			unit.Position = UDim2.fromScale(0.3, 0.74)
			unit.TextColor3 = Color3.fromRGB(150, 160, 175)
			unit.Parent = bg
			local fuelBg = Instance.new("Frame")
			fuelBg.Name = "FuelBg"
			fuelBg.Size = UDim2.fromScale(0.08, 0.8)
			fuelBg.Position = UDim2.fromScale(0.06, 0.1)
			fuelBg.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
			fuelBg.BorderSizePixel = 0
			fuelBg.Parent = bg
			local fuel = Instance.new("Frame")
			fuel.Name = "Fuel"
			fuel.AnchorPoint = Vector2.new(0, 1)
			fuel.Position = UDim2.fromScale(0, 1)
			fuel.Size = UDim2.fromScale(1, 1)
			fuel.BackgroundColor3 = Color3.fromRGB(255, 190, 40)
			fuel.BorderSizePixel = 0
			fuel.Parent = fuelBg
			local hpBg = fuelBg:Clone()
			hpBg.Name = "HpBg"
			hpBg.Position = UDim2.fromScale(0.86, 0.1)
			hpBg.Parent = bg
			hpBg.Fuel.Name = "Hp"
			hpBg.Hp.BackgroundColor3 = Color3.fromRGB(80, 220, 120)
			local gear = spd:Clone()
			gear.Name = "Gear"
			gear.Text = "P"
			gear.Size = UDim2.fromScale(0.12, 0.3)
			gear.Position = UDim2.fromScale(0.17, 0.35)
			gear.TextColor3 = Color3.new(1, 1, 1)
			gear.Parent = bg
			sg.Parent = cluster
		end
		local screen = B:box("Screen", Vector3.new(1.5, 0.9, 0.06), CFrame.new(0, st.belt + 0.35, st.cowlZ + 1.28) * CFrame.Angles(math.rad(-10), 0, 0), { Color = Color3.new(0, 0, 0) })
		do
			local sg, t = surfaceText(screen, Enum.NormalId.Back, B.taxi and "🚕 미터기  빈차" or "🗺️ NAVI", Color3.fromRGB(120, 230, 255), Color3.fromRGB(8, 14, 24), 120)
			sg.Name = "Gui"
			t.Font = Enum.Font.GothamBold
		end
		for _, s in ipairs({ -1, 1 }) do
			B:box("Vent", Vector3.new(0.5, 0.2, 0.06), CFrame.new(s * (W / 2 - 1.0), st.belt - 0.05, st.cowlZ + 1.26), { Color = Color3.fromRGB(25, 25, 25) })
		end
		local fz0, fz1 = st.doors[1][1], st.doors[1][2]
		B:box("Console", Vector3.new(1.1, 0.75, (fz1 - fz0) * 0.8), CFrame.new(0, st.bottom + 0.9, (st.cowlZ + 1.0 + st.frontSeatZ + 0.6) / 2), dk)
		B:box("ConsoleTop", Vector3.new(0.9, 0.06, 1.0), CFrame.new(0, st.bottom + 1.3, st.frontSeatZ - 0.2), soft)
		B:cyl("Shifter", Vector3.new(0.5, 0.12, 0.12), CFrame.new(0, st.bottom + 1.5, st.frontSeatZ - 0.9) * CFrame.Angles(0, 0, math.pi / 2), { Color = BLACK })
		B:box("ShiftKnob", Vector3.new(0.25, 0.25, 0.3), CFrame.new(0, st.bottom + 1.78, st.frontSeatZ - 0.9), { Color = CHROME, Material = Enum.Material.Metal })
		-- 룸미러
		B:box("RearViewMirror", Vector3.new(0.9, 0.28, 0.1), CFrame.new(0, st.roof - 0.6, st.roofF + 0.25), { Color = BLACK })
		B:box("RearViewGlass", Vector3.new(0.82, 0.22, 0.02), CFrame.new(0, st.roof - 0.6, st.roofF + 0.31), { Color = Color3.fromRGB(180, 190, 200), Reflectance = 0.6 })

		-- 핸들 (Motor6D 로 회전)
		local hubPos = Vector3.new(driverX, st.belt + 0.0, st.cowlZ + 1.65)
		local hubCF = CFrame.new(hubPos) * CFrame.Angles(math.rad(-25), 0, 0)
		local colStart = Vector3.new(driverX, st.belt - 0.35, st.cowlZ + 1.0)
		local colEnd = hubCF.Position
		local colMid = (colStart + colEnd) / 2
		B:cyl("Column", Vector3.new((colEnd - colStart).Magnitude, 0.25, 0.25), CFrame.lookAt(colMid, colEnd) * CFrame.Angles(0, math.pi / 2, 0), dk)
		local steerHub = newPart("Part", model, { Name = "SteerHub", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = hubCF, Transparency = 1 })
		local sm = Instance.new("Motor6D")
		sm.Name = "SteerMotor"
		sm.Part0 = root
		sm.Part1 = steerHub
		sm.C0 = hubCF
		sm.C1 = CFrame.new()
		sm.Parent = root
		local swMat = { Color = Color3.fromRGB(28, 28, 30), Material = Enum.Material.Leather }
		local n, r = 16, 0.72
		for i = 0, n - 1 do
			local a = i * 2 * math.pi / n
			local lp = Vector3.new(math.cos(a) * r, math.sin(a) * r, 0)
			local tg = Vector3.new(-math.sin(a), math.cos(a), 0)
			B:box("WheelRim", Vector3.new(0.17, 0.17, 2 * math.pi * r / n + 0.04), hubCF * CFrame.lookAt(lp, lp + tg, Vector3.new(0, 0, 1)), swMat, nil, steerHub)
		end
		B:box("WheelSpokeH", Vector3.new(1.35, 0.14, 0.08), hubCF * CFrame.new(0, -0.05, 0), swMat, nil, steerHub)
		B:box("WheelSpokeV", Vector3.new(0.16, 0.6, 0.08), hubCF * CFrame.new(0, -0.38, 0), swMat, nil, steerHub)
		B:cyl("WheelPad", Vector3.new(0.18, 0.55, 0.55), hubCF * CFrame.new(0, -0.05, 0.03) * CFrame.Angles(0, math.pi / 2, 0), swMat, nil, steerHub)
		B:box("WheelLogo", Vector3.new(0.25, 0.12, 0.03), hubCF * CFrame.new(0, -0.05, 0.13), chrome, nil, steerHub)

		-- 좌석
		local sx = W / 2 - 2.2
		B:seat("DriverSeat", -sx, st.frontSeatZ)
		B:seat("PassengerSeat", sx, st.frontSeatZ)
		if st.rearSeatZ then
			B:box("RearBench", Vector3.new(W - 1.4, 0.45, 1.8), CFrame.new(0, st.seatY - 0.22, st.rearSeatZ), soft)
			local backCF = CFrame.new(0, st.seatY + 1.0, st.rearSeatZ + 0.95) * CFrame.Angles(math.rad(14), 0, 0)
			B:box("RearBack", Vector3.new(W - 1.4, 2.0, 0.45), backCF, soft)
			for _, s in ipairs({ -1, 1 }) do
				B:box("RearHeadrest", Vector3.new(1.0, 0.5, 0.3), backCF * CFrame.new(s * sx, 1.3, 0.05), soft)
			end
			for _, nm in ipairs({ "RearLeft", "RearRight" }) do
				local x = nm == "RearLeft" and -sx or sx
				local s = newPart("Seat", model, { Name = nm, Size = Vector3.new(1.6, 0.2, 1.6), CFrame = CFrame.new(x, st.seatY - 0.1, st.rearSeatZ), Transparency = 1 })
				s.CanTouch = false
				weldTo(s, root)
			end
		end
	end

	------------------------------------------------ 스타일별 추가 파츠
	if st.spoiler then
		B:box("Spoiler", Vector3.new(W - 1.2, 0.12, 1.1), CFrame.new(0, st.tailY + 0.95, L / 2 - 0.9) * CFrame.Angles(math.rad(-6), 0, 0), { Color = Color3.fromRGB(20, 20, 22), Material = Enum.Material.Fabric }, "R")
		for _, s in ipairs({ -1, 1 }) do
			B:box("SpoilerPost", Vector3.new(0.18, 0.9, 0.35), CFrame.new(s * (W / 2 - 1.6), st.tailY + 0.5, L / 2 - 0.9), black, "R")
			B:box("SpoilerEnd", Vector3.new(0.1, 0.45, 1.2), CFrame.new(s * (W / 2 - 0.6), st.tailY + 1.0, L / 2 - 0.9), black, "R")
			B:box("HoodVent", Vector3.new(0.7, 0.06, 1.4), CFrame.new(s * 1.6, st.noseY + 0.3, -L / 2 + 4.2) * CFrame.Angles(math.rad(-4), 0, 0), black, "F")
		end
	end
	if st.suv then
		for _, s in ipairs({ -1, 1 }) do
			B:box("RoofBar", Vector3.new(0.25, 0.18, st.roofR - st.roofF - 0.6), CFrame.new(s * (W / 2 - 0.9), st.roof + 0.45, (st.roofF + st.roofR) / 2), { Color = Color3.fromRGB(170, 172, 178), Material = Enum.Material.Metal })
			for _, zz in ipairs({ st.roofF + 0.5, st.roofR - 0.5 }) do
				B:box("RoofPost", Vector3.new(0.25, 0.3, 0.4), CFrame.new(s * (W / 2 - 0.9), st.roof + 0.3, zz), black)
			end
		end
		B:box("SkidPlate", Vector3.new(W * 0.5, 0.15, 0.6), CFrame.new(0, st.bottom + 0.05, -L / 2 + 0.3), { Color = Color3.fromRGB(170, 172, 178), Material = Enum.Material.Metal }, "F")
	end
	if B.taxi then
		local zc = (st.roofF + st.roofR) / 2
		local sign = B:box("TaxiSign", Vector3.new(2.6, 0.9, 1.1), CFrame.new(0, st.roof + 0.68, zc), { Color = Color3.fromRGB(250, 250, 245) })
		B:box("TaxiSignBase", Vector3.new(2.8, 0.15, 1.3), CFrame.new(0, st.roof + 0.25, zc), black)
		local top = B:box("TaxiSignTop", Vector3.new(2.5, 0.1, 1.0), CFrame.new(0, st.roof + 1.17, zc), { Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Neon })
		top:SetAttribute("Light", "TaxiSign")
		surfaceText(sign, Enum.NormalId.Front, "TAXI", Color3.fromRGB(230, 120, 20), nil, 60)
		surfaceText(sign, Enum.NormalId.Back, "개인 TAXI", Color3.fromRGB(230, 120, 20), nil, 60)
	end

	------------------------------------------------ 물리 장치 (서스펜션 힘 / 자세 제어)
	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = root
	local up = Instance.new("Torque")
	up.Name = "Upright"
	up.Attachment0 = center
	up.RelativeTo = Enum.ActuatorRelativeTo.World
	up.Torque = Vector3.zero
	up.Parent = root
	for _, w in ipairs({ { "FL", -1, st.axleF }, { "FR", 1, st.axleF }, { "RL", -1, st.axleR }, { "RR", 1, st.axleR } }) do
		local a = Instance.new("Attachment")
		a.Name = "Sus" .. w[1]
		a.Position = Vector3.new(w[2] * st.track, 0, w[3])
		a.Parent = root
		local f = Instance.new("VectorForce")
		f.Name = "Force" .. w[1]
		f.Attachment0 = a
		f.RelativeTo = Enum.ActuatorRelativeTo.World
		f.ApplyAtCenterOfMass = false
		f.Force = Vector3.zero
		f.Parent = root
	end
	local smokeAtt = Instance.new("Attachment")
	smokeAtt.Name = "SmokeAtt"
	smokeAtt.Position = Vector3.new(0, st.noseY + 0.3, -L / 2 + 2.5)
	smokeAtt.Parent = root
	local exAtt = Instance.new("Attachment")
	exAtt.Name = "ExhaustAtt"
	exAtt.Position = Vector3.new(st.spoiler and 1.9 or 1.8, st.bottom + 0.28, L / 2)
	exAtt.Parent = root

	------------------------------------------------ 속성
	model:SetAttribute("CarType", carType)
	model:SetAttribute("Style", spec.Style)
	model:SetAttribute("RideH", st.rideH)
	model:SetAttribute("WheelR", st.R)
	model:SetAttribute("Track", st.track)
	model:SetAttribute("AxleF", st.axleF)
	model:SetAttribute("AxleR", st.axleR)
	model:SetAttribute("MaxSpeed", spec.MaxSpeed)
	model:SetAttribute("Accel", spec.Accel)
	model:SetAttribute("Grip", spec.Grip)
	model:SetAttribute("FuelUse", spec.FuelUse)
	model:SetAttribute("Health", 100)
	model:SetAttribute("Fuel", 100)
	model:SetAttribute("Owner", 0)
	model:SetAttribute("Lights", false)
	model:SetAttribute("Color", B.color)

	-- 스트리밍이 켜져 있어도 차가 사라지지 않게
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)

	model:PivotTo(opts.CFrame or CFrame.new())
	return model
end

-- 좌석 → 문 이름
CarBuilder.SEAT_DOOR = {
	DriverSeat = "Door_FL",
	PassengerSeat = "Door_FR",
	RearLeft = "Door_RL",
	RearRight = "Door_RR",
}

return CarBuilder
