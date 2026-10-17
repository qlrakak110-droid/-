-- GwangalliClubPlus (client): CLUB OCEAN 광안 AAA show add-on. Drop-in LocalScript; pairs with
-- ServerScriptService.GwangalliClubPlus and ReplicatedStorage.GwangalliClubPlusShared.
--   Core      context: remotes, attributes, beat clock, zone, jobs, builders
--   Led       centre LED wall: VJ loops + order / 후원 / 합석 / DJ takeovers (LedArt templates)
--   Fx        CO2 · confetti · sparks · strobe · haze · LED floor · mirror ball · DJ booth glow
--   Lasers    our laser fans + moving heads (layered over ClubLights)
--   Director  turns orders / 후원 / 합석 / DJ pads into synced world cues
--   Boards    side LED "CLUB OCEAN 랭킹전" (4 rankings + ticker)
--   Signs     table LED signs · presenter board · bartender flair · crown nameplates
--   Ui        HUD rail (후원 / 랭킹 / DJ), sheets, DJ pad, receipts
-- Each module starts in its own pcall: one failing part never takes the others down.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedModule = ReplicatedStorage:WaitForChild("GwangalliClubPlusShared", 120)
if not (sharedModule and sharedModule:IsA("ModuleScript")) then
	warn("[GwangalliClubPlus] ReplicatedStorage.GwangalliClubPlusShared is missing; the client show is off")
	return
end
local okS, S = pcall(require, sharedModule)
if not okS or type(S) ~= "table" then
	warn("[GwangalliClubPlus] shared module failed:", S)
	return
end
if not S.Config.Enabled then
	return
end
-- the server creates the folder (parented last); no server script = no add-on
local folder = ReplicatedStorage:WaitForChild(S.Names.Folder, 180)
if not folder then
	return
end

local Core = require(script:WaitForChild("Core"))
Core.init(S, folder)

local function load(name: string): any?
	local m = script:FindFirstChild(name) or script:WaitForChild(name, 10)
	if not m then
		warn("[GwangalliClubPlus] module missing:", name)
		return nil
	end
	local ok, mod = pcall(require, m)
	if not ok then
		warn("[GwangalliClubPlus] module " .. name .. " failed:", mod)
		return nil
	end
	return mod
end

local function start(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[GwangalliClubPlus] " .. name .. " failed to start:", err)
	end
end

local LedArt = load("LedArt")
local Led = load("Led")
local Fx = load("Fx")
local Lasers = load("Lasers")
local Director = load("Director")
local Boards = load("Boards")
local Signs = load("Signs")
local Ui = load("Ui")

-- no-op stand-ins so the Director / Boards still run when one visual module is missing
local function stub(): any
	return setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
end

if LedArt then
	start("LedArt", function()
		LedArt.init(Core)
	end)
end
if Led and LedArt then
	start("Led", function()
		Led.init(Core, LedArt)
	end)
else
	Led = stub()
end
if Fx then
	start("Fx", function()
		Fx.init(Core)
	end)
else
	Fx = stub()
end
if Lasers then
	start("Lasers", function()
		Lasers.init(Core, Led)
	end)
else
	Lasers = stub()
end
if Signs then
	start("Signs", function()
		Signs.init(Core, Fx)
	end)
else
	Signs = stub()
end
if Director then
	start("Director", function()
		Director.init(Core, Led, Fx, Lasers, Signs)
	end)
end
if Boards then
	start("Boards", function()
		Boards.init(Core, Led)
	end)
end
if Ui then
	start("Ui", function()
		Ui.init(Core)
	end)
end

Core.connectEvents()
Core.startWatching()
