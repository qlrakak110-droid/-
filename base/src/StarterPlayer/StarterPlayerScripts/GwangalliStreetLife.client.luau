-- GwangalliStreetLife (LocalScript, StarterPlayerScripts): the living streets of 광안리, client-side.
-- Boots the ModuleScripts in the sibling Folder "GwangalliStreetLife":
--   Config     tunables (caps per quality tier, radii, update rates)
--   NavWorld   GwangalliNav queries: nodes near the player, flow fields, random walks, POIs, crosswalks
--   Anim       default R15 animations (GwangalliAnim ids) + procedural gestures / head look
--   Pool       rig cache (GwangalliNPCLooks rigs: the same person gets their rig back, anyone else
--              re-dresses an idle one with Looks.restyle, new rigs only when none is idle)
--   Agent      one pedestrian: plans from the roster schedule / local activity, walking, idling
--              (with small sub-states), reactions (making way, bumps, cars, glances, friends,
--              club pitch), riding along / waiting as a companion, talking
--   Crowd      spawner / despawner (GTA-style ring, activity people start at their spot), club
--              queue, companions, cars, events (drone show, busker, street food), the per-frame update
--   SocialUI   name + tier chips, 말 걸기 prompts, speech bubbles, SocialState / Dialog remotes
--   ClubCrowd  CLUB OCEAN crowd rigs: 10 + 30 * hype shown while the camera is at the club (only the
--              outside queue guests otherwise), named citizens dancing in the place of some of them
-- Data: ReplicatedStorage.GwangalliNav (pedestrian graph), GwangalliCitizens (roster + schedules),
-- GwangalliNight (hype), GwangalliNPCLooks (avatars), GwangalliSocialShared (tiers / remotes),
-- GwangalliQuality (tier), GwangalliShared (clock, signals), GwangalliAnim (animation ids).
-- Everything runs behind pcall: a missing optional module only turns its feature off.
-- (A LocalScript and a Folder share the name here; the folder is looked up by class.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function fail(msg: string)
	warn("[GwangalliStreetLife] " .. msg)
end

local player = Players.LocalPlayer

local folder: Instance? = nil
local parent = script.Parent
if parent then
	for _ = 1, 40 do
		for _, child in parent:GetChildren() do
			if child.Name == "GwangalliStreetLife" and child:IsA("Folder") then
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
	fail("module folder GwangalliStreetLife missing next to the boot script")
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

local function shared(name: string, wait: number?): any
	local m = ReplicatedStorage:FindFirstChild(name)
	if not m and wait then
		m = ReplicatedStorage:WaitForChild(name, wait)
	end
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
		fail(name .. " failed to load: " .. tostring(res))
	end
	return nil
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Nav = shared("GwangalliNav", 30)
local Looks = shared("GwangalliNPCLooks", 10)
local Night = shared("GwangalliNight", 10)
if not Nav or not Looks or not Night then
	fail("GwangalliNav / GwangalliNPCLooks / GwangalliNight missing: street life disabled")
	return
end
local Citizens = shared("GwangalliCitizens", 10)
local Quality = shared("GwangalliQuality", 5)
local Shared = shared("GwangalliShared", 5)
local Social = shared("GwangalliSocialShared", 5)
local AnimLib = shared("GwangalliAnim", 5)
local UIKit = shared("GwangalliUI")
local BumpShared = shared("GwangalliBumpShared", 5) -- 어깨빵 rules / knockdown motion / bubbles (npc_types)

local Config = load("Config")
local World = load("NavWorld")
local Anim = load("Anim")
local Pool = load("Pool")
local Agent = load("Agent")
local Crowd = load("Crowd")
local SocialUI = load("SocialUI")
local ClubCrowd = load("ClubCrowd")
if not (Config and World and Anim and Pool and Agent and Crowd and SocialUI) then
	fail("core modules missing: street life disabled")
	return
end

local ctx = {
	player = player,
	Nav = Nav,
	Looks = Looks,
	Night = Night,
	Citizens = Citizens,
	Quality = Quality,
	Shared = Shared,
	Social = Social,
	AnimLib = AnimLib,
	UIKit = UIKit,
	BumpShared = BumpShared,
	Config = Config,
	World = World,
	Anim = Anim,
	Pool = Pool,
	Agent = Agent,
	Crowd = Crowd,
	SocialUI = SocialUI,
	ClubCrowd = ClubCrowd,
	clock = function(): number
		return Night.clock()
	end,
}

local okInit, initErr = pcall(function()
	World.init(ctx)
	Anim.init(ctx)
	Pool.init(ctx)
	Agent.init(ctx)
	SocialUI.init(ctx)
end)
if not okInit then
	fail("init failed: " .. tostring(initErr))
	return
end

task.spawn(function()
	local ok, err = pcall(Crowd.start, ctx)
	if not ok then
		fail("Crowd.start failed: " .. tostring(err))
	end
end)

-- LocalPlayer.GwangalliStreetAPI: other client scripts (GwangalliBump: 어깨빵 targets / knockdowns /
-- bubbles over pedestrians) reach the client-side crowd through this BindableFunction
do
	local api = player:FindFirstChild("GwangalliStreetAPI")
	if not api then
		api = Instance.new("BindableFunction")
		api.Name = "GwangalliStreetAPI"
		api.Parent = player
	end
	(api :: BindableFunction).OnInvoke = function(method: any, ...: any)
		local ok, res = pcall(Crowd.api, method, ...)
		if not ok then
			fail("api " .. tostring(method) .. ": " .. tostring(res))
			return nil
		end
		return res
	end
end

if ClubCrowd then
	task.spawn(function()
		local ok, err = pcall(ClubCrowd.start, ctx)
		if not ok then
			fail("ClubCrowd.start failed: " .. tostring(err))
		end
	end)
end
