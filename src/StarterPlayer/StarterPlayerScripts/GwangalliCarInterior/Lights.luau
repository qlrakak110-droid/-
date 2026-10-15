--!strict
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
			table.insert(L.dome, light("PointLight", p, WARM, 1.1, 8))
			table.insert(L.lenses, p)
		elseif n == "MapLamp" then
			local s = light("SpotLight", p, WARM, 1.6, 7) :: SpotLight
			s.Face = Enum.NormalId.Bottom
			s.Angle = 75
			table.insert(L.dome, s)
			table.insert(L.lenses, p)
		elseif n == "NavGlass" or n == "ClusterGlass" then
			local s = light("SurfaceLight", p, SCREEN, 0.35, 3) :: SurfaceLight
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
