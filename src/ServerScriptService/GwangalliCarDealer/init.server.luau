-- GwangalliCarDealer (Script, ServerScriptService): 광안 오토 딜러 add-on — talk to the sales NPC (한서윤 대리 on
-- the showroom floor, or 박사장 at his desk) → full catalog of every car by type → detail with a 3D preview →
-- 시승 / 계약 → 출고 ceremony. A drop-in add-on: it finds the garage's systems at runtime (GwangalliGarageAPI,
-- GwangalliVehiclesAPI, GwangalliGameplayAPI, GarageShop tags) and never edits them; buying always goes
-- through the garage (prices, the 3-car limit, 할부, plates and saving stay the garage's).
-- Needs ReplicatedStorage.GwangalliCarDealerShared and StarterPlayerScripts.GwangalliCarDealer.
-- Off: workspace attribute GwangalliCarDealer = false (at start).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if workspace:GetAttribute("GwangalliCarDealer") == false then
	return
end

local sharedModule = ReplicatedStorage:WaitForChild("GwangalliCarDealerShared", 60)
if not sharedModule then
	warn("[GwangalliCarDealer] ReplicatedStorage.GwangalliCarDealerShared is missing: the dealer add-on is off")
	return
end
local S = require(sharedModule) :: any
local N = S.NAMES

local Bridge = require(script:WaitForChild("Bridge")) :: any
local Store = require(script:WaitForChild("Store")) :: any
local Npc = require(script:WaitForChild("Npc")) :: any
local Previews = require(script:WaitForChild("Previews")) :: any
local TestDrive = require(script:WaitForChild("TestDrive")) :: any
local Service = require(script:WaitForChild("Service")) :: any

Bridge.init(S)
Store.init(S)
Npc.init(S, Bridge)
Previews.init(S, Bridge)

-- remotes (parented last, so a client that finds the folder finds both remotes)
local old = ReplicatedStorage:FindFirstChild(N.Remotes)
if old then
	old:Destroy()
end
local remotes = Instance.new("Folder")
remotes.Name = N.Remotes
local request = Instance.new("RemoteFunction")
request.Name = N.Request
request.Parent = remotes
local event = Instance.new("RemoteEvent")
event.Name = N.Event
event.Parent = remotes

local function fire(player: Player, payload: { [string]: any })
	if player.Parent == Players then
		event:FireClient(player, payload)
	end
end

TestDrive.init(S, Bridge, Store, fire)
Service.init(S, Bridge, Store, Npc, TestDrive)

request.OnServerInvoke = function(player: Player, op: any, payload: any)
	return Service.handle(player, op, payload)
end
remotes.Parent = ReplicatedStorage

-- players
local function joined(player: Player)
	task.spawn(Store.load, player)
end
Players.PlayerAdded:Connect(joined)
for _, p in Players:GetPlayers() do
	joined(p)
end
Players.PlayerRemoving:Connect(function(player)
	task.defer(Store.release, player)
end)
game:BindToClose(function()
	Store.flushAll()
end)
Store.run()

-- world
task.spawn(function()
	local ok, err = pcall(Npc.start)
	if not ok then
		warn("[GwangalliCarDealer] NPC start failed: " .. tostring(err))
	end
end)
task.spawn(function()
	local ok, err = pcall(Previews.start)
	if not ok then
		warn("[GwangalliCarDealer] previews failed: " .. tostring(err))
	end
end)
task.spawn(function()
	if not Bridge.waitGarage(60) then
		warn("[GwangalliCarDealer] ServerStorage.GwangalliGarageAPI not found: the catalog is read-only")
	end
end)

print("[GwangalliCarDealer] server ready (v" .. tostring(S.VERSION) .. ")")
