-- GwangalliWorldBoot (LocalScript, StarterPlayerScripts)
-- Boots the client-side world systems in the sibling folder GwangalliWorld (ModuleScripts):
--   MobileQuality  per-tier post FX, SurfaceGui draw distance / density, RoomDepth hiding
--   Lights         CityLight nearest-N at night, InteriorLight distance culling (tier budgets)
--   Signage        NightGlow SurfaceGuis, NightNeon parts, NeonTube parts, untagged window glass
--                  (lit windows at night, opaque upper-floor glass on the low tier)
--   NightWindows   glass tagged NightWindow (docs/buildings_contract.md): scheduled lit windows
--   Screens        LEDScreen message cycling
--   Traffic        TrafficSignal / PedSignal cycles per Group (server-time synchronised)
--   Bridge         Gwangan Bridge LED shows at night (BridgeLED parts)
--   DroneShow      광안리 M 드론라이트쇼 (formations in DroneFormations)
--   DetailLOD      near-only detail (Models with attribute LOD = "near")
-- The quality tier comes from ReplicatedStorage.GwangalliQuality (low / mid / high).
-- Every module is started in its own thread behind pcall, so one failing system never takes the
-- others down. (A LocalScript and a Folder cannot share a name in one parent, hence "...Boot".)
-- MobileQuality and Lights start before game.Loaded: the place saves its lights Enabled and
-- its post effects on, so switching them off early spares a phone the heaviest first frames.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function fail(msg: string)
	warn("[GwangalliWorldBoot] " .. msg)
end

local configModule = ReplicatedStorage:WaitForChild("GwangalliConfig", 30)
local sharedModule = ReplicatedStorage:WaitForChild("GwangalliShared", 30)
if not configModule or not sharedModule then
	fail("GwangalliConfig / GwangalliShared missing from ReplicatedStorage")
	return
end
local okConfig, Config = pcall(require, configModule)
local okShared, Shared = pcall(require, sharedModule)
if not okConfig or not okShared then
	fail("could not load shared modules: " .. tostring(if okConfig then Shared else Config))
	return
end

local folder = script.Parent:WaitForChild("GwangalliWorld", 30)
if not folder then
	fail("GwangalliWorld folder missing next to the boot script")
	return
end

local function load(name: string): any
	local module = folder:FindFirstChild(name) or folder:WaitForChild(name, 10)
	if not module or not module:IsA("ModuleScript") then
		fail("module " .. name .. " missing")
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		fail("module " .. name .. " failed to load: " .. tostring(result))
		return nil
	end
	return result
end

local Util = load("Util") -- also resolves GwangalliQuality (with a fallback) as Util.Quality
local DayNight = load("DayNight")
if not Util or not DayNight then
	return
end

-- one per-frame work budget shared by every chunked queue in Util (set before any module starts)
local mobileCfg = Config.Mobile or {}
if type(mobileCfg.FrameWriteBudget) == "table" then
	Util.setFrameBudget(function()
		return Util.budget(mobileCfg.FrameWriteBudget)
	end)
end

local ctx = {
	Config = Config,
	Shared = Shared,
	Util = Util,
	DayNight = DayNight,
	Quality = Util.Quality,
	Folder = folder,
}

local function startModules(names: { string })
	for _, name in names do
		local module = load(name)
		if module and type(module.start) == "function" then
			task.spawn(function()
				local ok, err = pcall(module.start, ctx)
				if not ok then
					fail(name .. ".start failed: " .. tostring(err))
				end
			end)
		end
	end
end

print(string.format("[GwangalliWorld] quality tier %s (%s)", tostring(Util.Quality.get()), tostring(Util.Quality.reason())))

startModules({ "MobileQuality", "Lights" })

if not game:IsLoaded() then
	game.Loaded:Wait()
end

startModules({ "DetailLOD" })

local okInit, initErr = pcall(DayNight.init, Shared)
if okInit then
	startModules({ "Signage", "NightWindows", "Screens", "Traffic", "Bridge", "DroneShow" })
else
	-- the night-dependent systems cannot run; the quality systems above still need discovery
	fail("DayNight.init failed: " .. tostring(initErr))
end

-- Every module registered its name / class discovery handlers synchronously in start(); run the
-- shared listener + chunked initial scan once (later registrations catch up on their own).
Util.startDiscovery(function()
	return Util.budget(mobileCfg.DiscoverPerFrame or { low = 150, mid = 300, high = 600 })
end, mobileCfg.ScanDescendants ~= false)
