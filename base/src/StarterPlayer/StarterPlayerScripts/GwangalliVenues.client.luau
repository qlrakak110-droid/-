-- GwangalliVenues (LocalScript, StarterPlayerScripts; owner: venues_detail): the client side of the
-- venue interiors — 노래방 (room TV: lyrics, pitch bar, rhythm taps, score fanfare, confetti, chiptune
-- backing), PC방 (camera on the monitor, 광안대교 나이트 레이서 on a SurfaceGui with compact touch
-- controls, ramen order, server leaderboard), 헬스장 (rep loops, equipment motion, compact HUD,
-- routine chip), 볼링장 라운지 (food menu, punch score) and the shared act driver that animates every
-- character carrying the attribute GwVenueAct plus the venue staff rigs (VenueStaff).
-- The server (GwangalliGameplay/Venues + VenueLife / VenueKaraoke / VenuePC) decides everything;
-- remotes GwangalliRemotes.VenueRequest (RemoteFunction) / VenueEvent (RemoteEvent).
-- Modules live in the sibling Folder "GwangalliVenues" (same name as this script: found by class).

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function findFolder(): Instance?
	for _ = 1, 100 do
		local parent = script.Parent
		if parent then
			for _, child in parent:GetChildren() do
				if child.Name == "GwangalliVenues" and child:IsA("Folder") then
					return child
				end
			end
		end
		task.wait(0.1)
	end
	return nil
end

local folder = findFolder()
if not folder then
	warn("[GwangalliVenues] module folder missing next to the LocalScript")
	return
end

local function mod(name: string): any
	local m = (folder :: Instance):FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		warn("[GwangalliVenues] module missing: " .. name)
		return nil
	end
	local ok, res = pcall(require, m)
	if not ok then
		warn("[GwangalliVenues] module " .. name .. " failed: " .. tostring(res))
		return nil
	end
	return res
end

local Common = mod("Common")
if not Common then
	return
end
local C = Common.init(player)
if not C then
	return
end

for _, name in { "Spots", "Gym", "Karaoke", "PC" } do
	local m = mod(name)
	if m and type(m.init) == "function" then
		local ok, err = pcall(m.init, C)
		if not ok then
			warn("[GwangalliVenues] " .. name .. ".init: " .. tostring(err))
		else
			C.modules[name] = m
		end
	end
end

C.start()
