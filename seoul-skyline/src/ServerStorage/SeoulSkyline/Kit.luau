--!strict
-- SeoulSkyline / Kit
-- 모든 모듈이 공유하는 파트 팩토리 + 예약(발자국) + 조명 예산 + 야간 조명 태그 + 지형/차선 기록.
--
--   Kit.part(parent, cf, size, opts)         -> BasePart  (opts: PartOpts)
--   Kit.box(parent, cf, size, color, material, opts?)
--   Kit.vcyl(parent, centerPos, height, diameter, color, material, opts?)   세로 원기둥
--   Kit.hcyl(parent, cf, length, diameter, color, material, opts?)          cf 의 X 축 방향 원기둥
--   Kit.ball(parent, pos, diameter, color, material, opts?)
--   Kit.wedge(parent, cf, size, color, material, opts?)                      WedgePart
--   Kit.ellipsoid(parent, cf, size, color, material, opts?)                  SpecialMesh 구(타원체), 크기 제한 없음
--   Kit.glow(part, dayMaterial?, dayColor?)    야간 발광 파트로 등록(태그 SeoulNight) — 낮/밤 전환용
--   Kit.light(part, "PointLight"|"SpotLight"|"SurfaceLight", props) -> Light?   예산 초과 시 nil
--   Kit.beacon(parent, pos, diameter?)        빨간 항공장애등(클라이언트가 깜빡임)
--   Kit.label(part, face, text, opts?)        SurfaceGui 글자(아파트 동 번호, 표지판)
--   Kit.reflection(parent, x, z, width, length, color, transparency?)       수면 위 빛 번짐(세로 스트릭)
--   Kit.reserve(x0, z0, x1, z1, tag?) / Kit.isFree(x0, z0, x1, z1, margin?)  도시 생성 충돌 방지
--   Kit.terrain(kind, cf, size, material)     지형 채우기 기록(+실제 적용)
--   Kit.lane(name, points, opts)              차량 불빛 차선(클라이언트 Traffic 이 사용)
--   Kit.group(parent, name, streaming?)       Model (기본 Persistent: 원경도 항상 보이게)
--   Kit.groundY(x, z)                          레이아웃 기준 지면 높이
--   Kit.yield()                                주기적 task.wait (Kit.part 가 자동 호출)

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)

local Kit = {}

export type PartOpts = {
	name: string?,
	shape: string?, -- "Block" | "Cylinder" | "Ball" | "Wedge" | "Corner"
	material: Enum.Material?,
	color: Color3?,
	transparency: number?,
	reflectance: number?,
	collide: boolean?, -- 기본 true (걷는 곳/건물). 장식은 false 권장
	shadow: boolean?, -- 기본: 크기 기준 자동, Neon/투명은 항상 false
	query: boolean?, -- 기본 = collide
	glow: boolean?, -- true: Kit.glow 등록 (Neon 야간 발광)
	dayMaterial: Enum.Material?,
	dayColor: Color3?,
}

Kit.stats = { parts = 0, lights = 0, beacons = 0, labels = 0, terrainOps = 0 }
Kit.terrainOps = {} :: { any } -- { kind, cf, size, material } (미리보기/디버그용 기록)
Kit.applyTerrain = true -- false: 기록만 (미리보기 하네스가 사용)
Kit.root = nil :: Model?
Kit.lanesFolder = nil :: Instance?

local reservations: { { number } } = {}
local sinceYield = 0

function Kit.reset(root: Model)
	Kit.stats = { parts = 0, lights = 0, beacons = 0, labels = 0, terrainOps = 0 }
	Kit.terrainOps = {}
	Kit.root = root
	Kit.lanesFolder = nil
	reservations = {}
	sinceYield = 0
end

function Kit.yield()
	sinceYield += 1
	if sinceYield >= Config.Quality.YieldEvery then
		sinceYield = 0
		task.wait()
	end
end

------------------------------------------------------------------------------------------------------
-- 그룹
------------------------------------------------------------------------------------------------------
function Kit.group(parent: Instance, name: string, streaming: Enum.ModelStreamingMode?): Model
	local m = Instance.new("Model")
	m.Name = name
	pcall(function()
		m.ModelStreamingMode = streaming or Enum.ModelStreamingMode.Persistent
	end)
	m.Parent = parent
	return m
end

------------------------------------------------------------------------------------------------------
-- 파트
------------------------------------------------------------------------------------------------------
local MAX_SIZE = 2048
local SHAPES = {
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

local function clampSize(s: Vector3): Vector3
	if s.X > MAX_SIZE or s.Y > MAX_SIZE or s.Z > MAX_SIZE then
		warn(string.format("[SeoulSkyline] part size %s clamped to %d", tostring(s), MAX_SIZE))
		return Vector3.new(math.min(s.X, MAX_SIZE), math.min(s.Y, MAX_SIZE), math.min(s.Z, MAX_SIZE))
	end
	return Vector3.new(math.max(s.X, 0.05), math.max(s.Y, 0.05), math.max(s.Z, 0.05))
end

function Kit.part(parent: Instance, cf: CFrame, size: Vector3, opts: PartOpts?): BasePart
	local o: PartOpts = opts or {}
	local shape = o.shape or "Block"
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	elseif shape == "Corner" then
		p = Instance.new("CornerWedgePart")
	else
		local part = Instance.new("Part")
		local st = SHAPES[shape]
		if st then
			part.Shape = st
		end
		p = part
	end
	local mat = o.material or Enum.Material.SmoothPlastic
	p.Name = o.name or "Part"
	p.Anchored = true
	p.Size = clampSize(size)
	p.CFrame = cf
	p.Material = mat
	p.Color = o.color or Color3.fromRGB(163, 162, 165)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local tr = o.transparency or 0
	if tr ~= 0 then
		p.Transparency = tr
	end
	if o.reflectance then
		p.Reflectance = o.reflectance
	end
	local collide = if o.collide == nil then true else o.collide
	p.CanCollide = collide
	p.CanQuery = if o.query == nil then collide else o.query
	p.CanTouch = false
	local shadow = o.shadow
	if shadow == nil then
		shadow = math.max(size.X, size.Y, size.Z) >= Config.Quality.ShadowMinSize
	end
	if mat == Enum.Material.Neon or tr >= 0.5 then
		shadow = false
	end
	p.CastShadow = shadow
	if o.glow then
		Kit.glow(p, o.dayMaterial, o.dayColor)
	end
	p.Parent = parent
	Kit.stats.parts += 1
	Kit.yield()
	return p
end

function Kit.box(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, opts: PartOpts?): BasePart
	local o: PartOpts = opts or {}
	o.color = color
	o.material = material or o.material
	return Kit.part(parent, cf, size, o)
end

-- 세로 원기둥: center = 중심점, 축 = 월드 Y
local CYL_UP = CFrame.Angles(0, 0, math.rad(90))
function Kit.vcyl(parent: Instance, center: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?, opts: PartOpts?): BasePart
	local o: PartOpts = opts or {}
	o.shape = "Cylinder"
	o.color = color
	o.material = material or o.material
	return Kit.part(parent, CFrame.new(center) * CYL_UP, Vector3.new(height, diameter, diameter), o)
end

-- 회전된 세로 원기둥(기울어진 기둥 등): cf 의 Y 축 방향
function Kit.cylAlongY(parent: Instance, cf: CFrame, height: number, diameter: number, color: Color3, material: Enum.Material?, opts: PartOpts?): BasePart
	local o: PartOpts = opts or {}
	o.shape = "Cylinder"
	o.color = color
	o.material = material or o.material
	return Kit.part(parent, cf * CYL_UP, Vector3.new(height, diameter, diameter), o)
end

-- 가로 원기둥: cf 의 X 축 방향
function Kit.hcyl(parent: Instance, cf: CFrame, length: number, diameter: number, color: Color3, material: Enum.Material?, opts: PartOpts?): BasePart
	local o: PartOpts = opts or {}
	o.shape = "Cylinder"
	o.color = color
	o.material = material or o.material
	return Kit.part(parent, cf, Vector3.new(length, diameter, diameter), o)
end

function Kit.ball(parent: Instance, pos: Vector3, diameter: number, color: Color3, material: Enum.Material?, opts: PartOpts?): BasePart
	local o: PartOpts = opts or {}
	o.shape = "Ball"
	o.color = color
	o.material = material or o.material
	return Kit.part(parent, CFrame.new(pos), Vector3.new(diameter, diameter, diameter), o)
end

function Kit.wedge(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, opts: PartOpts?): BasePart
	local o: PartOpts = opts or {}
	o.shape = "Wedge"
	o.color = color
	o.material = material or o.material
	return Kit.part(parent, cf, size, o)
end

-- 타원체(나무 수관, 원경 산, 구름 덩어리). 2048 을 넘는 크기는 메시 스케일로 키움.
function Kit.ellipsoid(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, opts: PartOpts?): BasePart
	local o: PartOpts = opts or {}
	o.color = color
	o.material = material or o.material
	if o.collide == nil then
		o.collide = false
	end
	local k = math.max(1, math.max(size.X, size.Y, size.Z) / MAX_SIZE)
	local p = Kit.part(parent, cf, size / k, o)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(k, k, k)
	mesh.Parent = p
	return p
end

------------------------------------------------------------------------------------------------------
-- 야간 발광 / 광원 / 항공장애등 / 글자
------------------------------------------------------------------------------------------------------
Kit.GLOW_TAG = "SeoulNight"
Kit.BEACON_TAG = "SeoulBeacon"

-- 밤에는 현재(Neon) 상태, 낮에는 dayMaterial/dayColor 로 전환되도록 기록
function Kit.glow(p: BasePart, dayMaterial: Enum.Material?, dayColor: Color3?)
	p:SetAttribute("NightMaterial", p.Material.Name)
	p:SetAttribute("NightColor", p.Color)
	p:SetAttribute("DayMaterial", (dayMaterial or Enum.Material.Glass).Name)
	p:SetAttribute("DayColor", dayColor or Config.Palette.GlassDeep)
	CollectionService:AddTag(p, Kit.GLOW_TAG)
end

export type LightProps = {
	color: Color3?,
	brightness: number?,
	range: number?,
	angle: number?,
	face: Enum.NormalId?,
	shadows: boolean?,
	force: boolean?, -- 예산 무시(중요 광원)
}

function Kit.light(p: BasePart, className: string, props: LightProps?): Light?
	local o: LightProps = props or {}
	if not o.force and Kit.stats.lights >= Config.Quality.MaxLights then
		return nil
	end
	local L = Instance.new(className) :: any
	L.Color = o.color or Config.Palette.LampWarm
	L.Brightness = o.brightness or 1
	L.Range = o.range or 16
	L.Shadows = o.shadows == true
	if className == "SpotLight" or className == "SurfaceLight" then
		L.Angle = o.angle or 90
		L.Face = o.face or Enum.NormalId.Bottom
	end
	L.Parent = p
	Kit.stats.lights += 1
	CollectionService:AddTag(L, Kit.GLOW_TAG)
	return L :: Light
end

function Kit.beacon(parent: Instance, pos: Vector3, diameter: number?): BasePart
	local d = diameter or 3
	local b = Kit.ball(parent, pos, d, Config.Palette.Beacon, Enum.Material.Neon, { name = "Beacon", collide = false })
	CollectionService:AddTag(b, Kit.BEACON_TAG)
	Kit.stats.beacons += 1
	return b
end

export type LabelOpts = {
	color: Color3?,
	font: Enum.Font?,
	glow: boolean?, -- true: 빛 영향 0(밤에도 밝게)
	pixelsPerStud: number?,
	maxDistance: number?,
	stroke: boolean?,
}

function Kit.label(p: BasePart, face: Enum.NormalId, text: string, opts: LabelOpts?): SurfaceGui
	local o: LabelOpts = opts or {}
	local g = Instance.new("SurfaceGui")
	g.Name = "Label"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = o.pixelsPerStud or 12
	g.LightInfluence = if o.glow then 0 else 1
	g.MaxDistance = o.maxDistance or 2600
	g.AlwaysOnTop = false
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = text
	t.TextScaled = true
	t.Font = o.font or Enum.Font.GothamBold
	t.TextColor3 = o.color or Color3.fromRGB(240, 240, 240)
	if o.stroke then
		t.TextStrokeTransparency = 0.6
	end
	t.Parent = g
	g.Parent = p
	Kit.stats.labels += 1
	return g
end

-- 수면 위 빛 번짐: 광원 바로 앞(카메라 쪽 +Z)으로 길게 늘어진 반투명 Neon 띠
function Kit.reflection(parent: Instance, x: number, z: number, width: number, length: number, color: Color3, transparency: number?): BasePart
	local y = Config.Level.Water + 0.25
	return Kit.part(parent, CFrame.new(x, y, z + length / 2), Vector3.new(width, 0.12, length), {
		name = "WaterGlint",
		material = Enum.Material.Neon,
		color = color,
		transparency = transparency or 0.62,
		collide = false,
		query = false,
		shadow = false,
		glow = true,
		dayMaterial = Enum.Material.Glass,
		dayColor = Color3.fromRGB(40, 60, 80),
	})
end

------------------------------------------------------------------------------------------------------
-- 발자국 예약 (AABB, X/Z)
------------------------------------------------------------------------------------------------------
function Kit.reserve(x0: number, z0: number, x1: number, z1: number, _tag: string?)
	table.insert(reservations, { math.min(x0, x1), math.min(z0, z1), math.max(x0, x1), math.max(z0, z1) })
end

function Kit.isFree(x0: number, z0: number, x1: number, z1: number, margin: number?): boolean
	local m = margin or 0
	local ax0, az0, ax1, az1 = math.min(x0, x1) - m, math.min(z0, z1) - m, math.max(x0, x1) + m, math.max(z0, z1) + m
	for _, r in reservations do
		if ax0 < r[3] and ax1 > r[1] and az0 < r[4] and az1 > r[2] then
			return false
		end
	end
	return true
end

-- 회전된 사각형(중심, 폭, 깊이, yaw 도)의 AABB 예약/검사
local function rotatedAABB(cx: number, cz: number, w: number, d: number, yawDeg: number): (number, number, number, number)
	local a = math.rad(yawDeg)
	local hx = (math.abs(math.cos(a)) * w + math.abs(math.sin(a)) * d) / 2
	local hz = (math.abs(math.sin(a)) * w + math.abs(math.cos(a)) * d) / 2
	return cx - hx, cz - hz, cx + hx, cz + hz
end
Kit.rotatedAABB = rotatedAABB

function Kit.reserveRect(cx: number, cz: number, w: number, d: number, yawDeg: number?, tag: string?)
	local x0, z0, x1, z1 = rotatedAABB(cx, cz, w, d, yawDeg or 0)
	Kit.reserve(x0, z0, x1, z1, tag)
end

function Kit.isFreeRect(cx: number, cz: number, w: number, d: number, yawDeg: number?, margin: number?): boolean
	local x0, z0, x1, z1 = rotatedAABB(cx, cz, w, d, yawDeg or 0)
	return Kit.isFree(x0, z0, x1, z1, margin)
end

------------------------------------------------------------------------------------------------------
-- 지면 높이 (Config 레이아웃 기준; 실제 지형/바닥 파트도 이 단면을 따름)
------------------------------------------------------------------------------------------------------
local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

function Kit.groundY(_x: number, z: number): number
	local L, F, N = Config.Level, Config.FarBank, Config.NearBank
	if z > F.WaterEdge and z < N.WaterEdge then
		return L.Water
	end
	if z <= F.WaterEdge then
		if z > F.ParkTo then
			return L.Promenade
		elseif z > F.SlopeTo then
			return lerp(L.Promenade, L.Levee, (F.ParkTo - z) / (F.ParkTo - F.SlopeTo))
		end
		return L.City
	end
	if z < N.ParkTo then
		return L.Promenade
	elseif z < N.SlopeTo then
		return lerp(L.Promenade, L.Levee, (z - N.ParkTo) / (N.SlopeTo - N.ParkTo))
	end
	return L.City
end

------------------------------------------------------------------------------------------------------
-- 지형
------------------------------------------------------------------------------------------------------
-- kind: "Block" | "Ball" | "Cylinder" | "Wedge".  Ball: size.X = 지름.  Cylinder: size.Y = 높이, size.X = 지름
function Kit.terrain(kind: string, cf: CFrame, size: Vector3, material: Enum.Material)
	table.insert(Kit.terrainOps, { kind = kind, cf = cf, size = size, material = material })
	Kit.stats.terrainOps += 1
	if not Kit.applyTerrain then
		return
	end
	local T = workspace.Terrain
	if kind == "Block" then
		T:FillBlock(cf, size, material)
	elseif kind == "Ball" then
		T:FillBall(cf.Position, size.X / 2, material)
	elseif kind == "Cylinder" then
		T:FillCylinder(cf, size.Y, size.X / 2, material)
	elseif kind == "Wedge" then
		T:FillWedge(cf, size, material)
	end
	sinceYield += 40
	Kit.yield()
end

------------------------------------------------------------------------------------------------------
-- 차선 (클라이언트 Traffic 이 불빛 차량을 흘려보냄)
--   points: 월드 좌표 경로(차량 불빛 높이 포함). opts.speed(studs/s), opts.density(대/100stud),
--   opts.kind "head"(흰 전조등, 카메라 쪽으로 옴) | "tail"(붉은 후미등) — 방향은 points 순서.
------------------------------------------------------------------------------------------------------
export type LaneOpts = { speed: number?, density: number?, kind: string?, spacing: number? }

function Kit.lane(name: string, points: { Vector3 }, opts: LaneOpts?)
	local o: LaneOpts = opts or {}
	local root = Kit.root
	if not root then
		return
	end
	if not Kit.lanesFolder then
		local f = Instance.new("Folder")
		f.Name = "TrafficLanes"
		f.Parent = root
		Kit.lanesFolder = f
	end
	local lane = Instance.new("Configuration")
	lane.Name = name
	lane:SetAttribute("Count", #points)
	for i, p in points do
		lane:SetAttribute("P" .. i, p)
	end
	lane:SetAttribute("Speed", o.speed or 60)
	lane:SetAttribute("Density", o.density or 1)
	lane:SetAttribute("Kind", o.kind or "head")
	lane:SetAttribute("Spacing", o.spacing or 3.2) -- 전조등 두 개 간격
	lane.Parent = Kit.lanesFolder
end

return Kit
