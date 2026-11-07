--!strict
-- SeoulSkyline / Atmosphere
-- 해질녘(블루아워 직전) 조명·대기·하늘·구름·후처리·수면 색. 맵의 "룩"을 결정하는 모듈.
--   * Lighting.Technology = Future 는 Studio(커맨드 바/설정)에서만 바꿀 수 있어 pcall 로 시도합니다.
--   * 기존 Sky/Atmosphere/Clouds/후처리 효과는 이 맵의 값으로 교체됩니다.

local Lighting = game:GetService("Lighting")
local Config = require(script.Parent.Config)

local Atmosphere = {}
local rgb = Color3.fromRGB

local function replace(parent: Instance, className: string, name: string): Instance
	for _, c in parent:GetChildren() do
		if c:IsA(className) then
			c:Destroy()
		end
	end
	local inst = Instance.new(className)
	inst.Name = name
	return inst
end

function Atmosphere.apply()
	local L = Config.Lighting
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
	Lighting.ClockTime = L.ClockTime
	Lighting.GeographicLatitude = L.GeographicLatitude
	Lighting.Brightness = 2.4
	Lighting.ExposureCompensation = 0.15
	Lighting.Ambient = rgb(38, 42, 58)
	Lighting.OutdoorAmbient = rgb(104, 100, 124)
	Lighting.ColorShift_Top = rgb(255, 178, 116)
	Lighting.ColorShift_Bottom = rgb(78, 92, 140)
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.FogEnd = 100000

	local atm = replace(Lighting, "Atmosphere", "DuskAtmosphere") :: Atmosphere
	atm.Density = 0.11 -- 실제 스케일(거리 ×1.67)에 맞춘 값
	atm.Offset = 0.25
	atm.Color = rgb(228, 150, 108)
	atm.Decay = rgb(40, 88, 178)
	atm.Glare = 0.9
	atm.Haze = 1.0
	atm.Parent = Lighting

	local sky = replace(Lighting, "Sky", "DuskSky") :: Sky
	sky.StarCount = 400
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local bloom = replace(Lighting, "BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.9
	bloom.Size = 40
	bloom.Threshold = 1.25
	bloom.Parent = Lighting

	local cc = replace(Lighting, "ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	cc.Brightness = 0.02
	cc.Contrast = 0.14
	cc.Saturation = 0.12
	cc.TintColor = rgb(246, 246, 255)
	cc.Parent = Lighting

	local rays = replace(Lighting, "SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = 0.045
	rays.Spread = 0.55
	rays.Parent = Lighting

	local dof = replace(Lighting, "DepthOfFieldEffect", "DepthOfField") :: DepthOfFieldEffect
	dof.Enabled = false -- 포토 스팟/인트로에서만 클라이언트가 켬
	dof.FarIntensity = 0.08
	dof.FocusDistance = 600
	dof.InFocusRadius = 900
	dof.NearIntensity = 0
	dof.Parent = Lighting

	local terrain = workspace.Terrain
	local clouds = replace(terrain, "Clouds", "DuskClouds") :: Clouds
	clouds.Cover = 0.5
	clouds.Density = 0.45
	clouds.Color = rgb(255, 214, 200)
	clouds.Parent = terrain

	terrain.WaterColor = rgb(26, 50, 70)
	terrain.WaterTransparency = 0.12
	terrain.WaterReflectance = 1
	terrain.WaterWaveSize = 0.1
	terrain.WaterWaveSpeed = 7
	pcall(function()
		(terrain :: any).Decoration = true -- 잔디 블레이드 (일부 환경에서 스크립트 설정 불가 → pcall)
	end)
	pcall(function()
		terrain:SetMaterialColor(Enum.Material.Grass, rgb(70, 102, 54))
		terrain:SetMaterialColor(Enum.Material.LeafyGrass, rgb(62, 96, 48))
		terrain:SetMaterialColor(Enum.Material.Mud, rgb(64, 56, 48))
		terrain:SetMaterialColor(Enum.Material.Rock, rgb(110, 108, 104))
		terrain:SetMaterialColor(Enum.Material.Slate, rgb(96, 98, 102))
		terrain:SetMaterialColor(Enum.Material.Sand, rgb(160, 146, 120))
		terrain:SetMaterialColor(Enum.Material.Ground, rgb(92, 82, 66))
	end)
end

function Atmosphere.build(_ctx: any)
	Atmosphere.apply()
end

return Atmosphere
