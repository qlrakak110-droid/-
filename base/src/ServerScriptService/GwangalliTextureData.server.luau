-- GwangalliTextureData (server): hands the runtime texture data only to the clients that use it.
--
-- ServerStorage.GwangalliTextures holds the GTX1 texture data (Codec + 12 data modules, ~1.3 MB of
-- strings, made by tools/assets/textures.py). It used to sit in ReplicatedStorage, so every client
-- (every phone) downloaded and kept it at join, although StarterPlayerScripts/GwangalliTextures
-- stays dormant on the low tier (phones). Now a client whose GwangalliTextures script wakes up
-- (tier mid / high and the Image API works) fires ReplicatedStorage.GwangalliTexturesRequest once;
-- the server copies the folder into that player's PlayerGui inside a disabled ScreenGui
-- "GwangalliTexturesData" (ResetOnSpawn = false), which replicates to that player only.
-- A copy found in ReplicatedStorage at start (the generator still writes there) is moved into
-- ServerStorage first, before any client can join, and replaces an older ServerStorage copy.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local NAME = "GwangalliTextures"
local HOLDER = "GwangalliTexturesData"

local data = ServerStorage:FindFirstChild(NAME)
local stray = ReplicatedStorage:FindFirstChild(NAME)
if stray then
	if data then
		data:Destroy()
	end
	stray.Parent = ServerStorage
	data = stray
end
if not data then
	return -- nothing to serve (the client script then stays inactive)
end

local remote = Instance.new("RemoteEvent")
remote.Name = "GwangalliTexturesRequest"
remote.Parent = ReplicatedStorage

local served: { [Player]: boolean } = {}

remote.OnServerEvent:Connect(function(player: Player)
	if served[player] then
		return -- once per player (the copy survives respawns)
	end
	served[player] = true
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if not pg or not player.Parent then
		served[player] = nil
		return
	end
	local holder = Instance.new("ScreenGui")
	holder.Name = HOLDER
	holder.ResetOnSpawn = false
	holder.Enabled = false
	local copy = (data :: Instance):Clone()
	copy.Name = NAME
	copy.Parent = holder
	holder.Parent = pg
end)

Players.PlayerRemoving:Connect(function(player: Player)
	served[player] = nil
end)
