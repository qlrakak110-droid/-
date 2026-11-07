--!strict
-- SeoulSkyline — 한강 잠실 야경 맵 빌더 (롯데월드타워 모티브)
--
-- 사용법
--   * Studio 커맨드 바(편집 모드에 맵을 굽기, 권장):
--       require(game.ServerStorage.SeoulSkyline).Build()
--     → Workspace.SeoulSkyline + Terrain + Lighting 이 생성됩니다. 그대로 저장(Ctrl+S)하세요.
--   * 실행 중 자동 생성: ServerScriptService.SeoulSkylineBoot 가 Workspace 에 맵이 없으면 Build() 를 호출합니다.
--   * SeoulSkyline.Clear()  : 맵 모델 + 맵이 만든 지형 영역 제거
--   * SeoulSkyline.SetNight(true/false) : 창문/가로등 발광 전환 (DayNightCycle 용)
--
-- 모듈 규약: 각 모듈은 build(ctx) 를 가진 ModuleScript.
--   ctx = { Config, Kit, Facade, root: Model, model: Model(모듈 전용 그룹), rng: Random(모듈별 시드) }

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Config)
local Kit = require(script.Kit)
local Facade = require(script.Facade)

local SeoulSkyline = {}
local nightState: boolean? = nil -- SetNight 의 마지막 상태(중복 적용 방지)
SeoulSkyline.Config = Config
SeoulSkyline.Kit = Kit
SeoulSkyline.Facade = Facade

-- 빌드 순서 = 발자국 예약 우선순위 (랜드마크/히어로가 먼저 자리를 잡고, 도시가 빈 곳을 채움)
SeoulSkyline.MODULES = {
	"Atmosphere",
	"TerrainPlan",
	"Landmark",
	"Skyline",
	"Bridge",
	"Riverside",
	"Park",
	"Apartments",
	"CityCarpet",
	"WaterFx",
}

local function hash(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

export type BuildOpts = {
	only: { [string]: boolean }?, -- 일부 모듈만 (미리보기/디버그)
	applyTerrain: boolean?, -- false: 지형은 기록만
	parent: Instance?,
	quiet: boolean?,
}

function SeoulSkyline.Build(opts: BuildOpts?): Model
	local o: BuildOpts = opts or {}
	local t0 = os.clock()
	local old = workspace:FindFirstChild(Config.ROOT_NAME)
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = Config.ROOT_NAME
	pcall(function()
		root.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	root:SetAttribute("Version", Config.VERSION)
	root:SetAttribute("HeroCamPos", Config.Viewpoint.HeroCamPos)
	root:SetAttribute("HeroCamLook", Config.Viewpoint.HeroCamLook)
	root:SetAttribute("HeroFov", Config.Viewpoint.HeroFov)
	root:SetAttribute("IntroCinematic", Config.Client.IntroCinematic)
	root:SetAttribute("Traffic", Config.Client.Traffic)
	root:SetAttribute("TrafficDensity", Config.Client.TrafficDensity)
	root:SetAttribute("Beacons", Config.Client.Beacons)
	root:SetAttribute("Boats", Config.Client.Boats)
	Kit.reset(root)
	Kit.applyTerrain = o.applyTerrain ~= false
	local report = {}
	for _, name in SeoulSkyline.MODULES do
		if o.only and not o.only[name] then
			continue
		end
		local mod = script:FindFirstChild(name)
		if not mod then
			continue
		end
		local p0, tm = Kit.stats.parts, os.clock()
		local ok, err = pcall(function()
			local M = require(mod :: ModuleScript) :: any
			local model = Kit.group(root, name)
			M.build({ Config = Config, Kit = Kit, Facade = Facade, root = root, model = model, rng = Random.new(Config.SEED + hash(name)) })
			if #model:GetChildren() == 0 then
				model:Destroy()
			end
		end)
		if not ok then
			warn(string.format("[SeoulSkyline] %s 빌드 실패: %s", name, tostring(err)))
		end
		table.insert(report, string.format("%s %d parts %.1fs", name, Kit.stats.parts - p0, os.clock() - tm))
		task.wait()
	end
	root.Parent = o.parent or workspace
	-- 새 파트는 모두 밤 상태로 만들어지므로 캐시를 비우고 현재 하늘 시각으로 다시 맞춤(재빌드 시 낮인데 불이 켜진 채 남는 문제 방지)
	nightState = nil
	SeoulSkyline.SetNight(SeoulSkyline.IsNightClock(game:GetService("Lighting").ClockTime))
	if not o.quiet then
		print(string.format("[SeoulSkyline] 완료: 파트 %d · 광원 %d · 항공등 %d · 지형 %d · %.1f초\n  %s", Kit.stats.parts, Kit.stats.lights, Kit.stats.beacons, Kit.stats.terrainOps, os.clock() - t0, table.concat(report, "\n  ")))
	end
	return root
end

function SeoulSkyline.ApplyLighting()
	require(script.Atmosphere).apply()
end

function SeoulSkyline.Clear()
	local old = workspace:FindFirstChild(Config.ROOT_NAME)
	if old then
		old:Destroy()
	end
	local R, F, N, L = Config.River, Config.FarBank, Config.NearBank, Config.Level
	local zMin, zMax = F.SlopeTo - 40, N.SlopeTo + 40
	workspace.Terrain:FillBlock(CFrame.new((R.XMin + R.XMax) / 2, (L.RiverBed - 20 + L.Levee + 20) / 2, (zMin + zMax) / 2), Vector3.new(R.XMax - R.XMin, L.Levee - L.RiverBed + 40, zMax - zMin), Enum.Material.Air)
end

function SeoulSkyline.IsNightClock(t: number): boolean
	local L = Config.Lighting
	return t >= L.NightFrom or t < L.NightTo
end

function SeoulSkyline.SetNight(on: boolean)
	if nightState == on then
		return
	end
	nightState = on
	for _, inst in CollectionService:GetTagged(Kit.GLOW_TAG) do
		if inst:IsA("BasePart") then
			local key = if on then "Night" else "Day"
			local mat = inst:GetAttribute(key .. "Material")
			local col = inst:GetAttribute(key .. "Color")
			if typeof(mat) == "string" then
				local ok, m = pcall(function()
					return (Enum.Material :: any)[mat]
				end)
				if ok and m then
					inst.Material = m
				end
			end
			if typeof(col) == "Color3" then
				inst.Color = col
			end
		elseif inst:IsA("Light") then
			inst.Enabled = on
		end
	end
end

return SeoulSkyline
