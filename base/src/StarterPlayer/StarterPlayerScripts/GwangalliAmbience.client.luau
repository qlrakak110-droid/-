-- GwangalliAmbience (LocalScript, StarterPlayerScripts): the living sea and beach of 광안리, client-side
-- and near the player only. Boots the ModuleScripts in the sibling Folder "GwangalliAmbience":
--   Env         shared helpers: quality tier, sea geometry (ReplicatedStorage.GwangalliSeaData),
--               clock, wind, the shared swell, part factory, one Heartbeat scheduler + cost stats
--   Surf        animated swash at the water's edge (foam edge, water film, wet sheen, breakers,
--               sand ripples) around the camera
--   Spray       breaking-wave spray on the rock groynes, breakwater tetrapods and sea walls
--   Boats       cruising fishing boats / tour boat / yacht / jet boat / SUP & kayak + the moored and
--               anchored props and buoys riding the swell (tag SeaBob)
--   Birds       gulls soaring, landing and taking off on the beach and at 민락항
--   Motion      parasols / banners swaying (SeaSway) and flags fluttering (SeaFlag) in the wind
--   NightSea    sky (small sun and moon, city-dimmed stars), day / night breeze, the bridge-light
--               reflections on the bay at night
--   Soundscape  spatial ambience by zone (surf, gulls, traffic, crowd, wind, the club's bass at
--               night) from loops found by GwangalliAmbience.server, crossfaded
-- Each module starts in its own thread behind pcall: one failing system never stops the others.
-- Quality: ReplicatedStorage.GwangalliQuality (low / mid / high); the low tier runs lighter
-- versions (fewer stations, gulls, boats; no parasol sway). Debug: Workspace attribute
-- GwangalliAmbienceDebug = true prints the per-system per-frame cost every 20 s.
-- (A LocalScript and a Folder share the name here; the folder is looked up by class.)

local function fail(msg: string)
	warn("[GwangalliAmbience] " .. msg)
end

local folder: Instance? = nil
local parent = script.Parent
if parent then
	for _ = 1, 40 do
		for _, child in parent:GetChildren() do
			if child.Name == "GwangalliAmbience" and child:IsA("Folder") then
				folder = child
				break
			end
		end
		if folder then
			break
		end
		task.wait(0.25)
	end
end
if not folder then
	fail("module folder GwangalliAmbience missing next to the boot script")
	return
end

local function load(name: string): any
	local module = (folder :: Instance):FindFirstChild(name) or (folder :: Instance):WaitForChild(name, 10)
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

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Env = load("Env")
if not Env then
	return
end

local NAMES = { "NightSea", "Surf", "Spray", "Boats", "Birds", "Motion", "Soundscape" }
local modules = {}
for _, name in NAMES do
	local module = load(name)
	if module and type(module.start) == "function" then
		table.insert(modules, { name = name, module = module })
	end
end
local started = {}
local pending = #modules
for i, entry in modules do
	if i > 1 then
		task.wait() -- one system per frame: their part pools are built in their start (join burst)
	end
	task.spawn(function()
		local ok, err = pcall(entry.module.start, Env)
		if ok then
			table.insert(started, entry.name)
		else
			fail(entry.name .. ".start failed: " .. tostring(err))
		end
		pending -= 1
		if pending == 0 then
			Env.log(string.format("started %d/%d systems (%s), tier %s, sea data %s", #started, #NAMES, table.concat(started, ", "), Env.tier(), if Env.hasData then "ok" else "fallback"))
		end
	end)
end

-- optional cost report
task.spawn(function()
	while true do
		task.wait(20)
		if workspace:GetAttribute("GwangalliAmbienceDebug") == true then
			Env.log(Env.report())
		end
	end
end)
