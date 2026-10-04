-- GwangalliPhone (LocalScript, StarterPlayerScripts): the in-game smartphone.
--
-- The code lives in the sibling Folder "GwangalliPhone" (src/StarterPlayerScripts/GwangalliPhone/,
-- inserted as a Folder of ModuleScripts by build/build.luau). This LocalScript has the same name,
-- so the folder is looked up by class, never with WaitForChild("GwangalliPhone").
--
--   Phone.luau    shell: 폰 button (GwangalliLayout "rightColumn.phone"), toast layer ("toasts"),
--                 device ("sheetRight"), status bar, widget home screen, navigation, blur, notifications,
--                 photo mode
--   Overlay.luau  money chip ("topLeftChips"), shift card ("topRight"), NPC / work dialog ("dialog")
--   Tracker.luau  guidance widget ("topRight"), 3D objective marker, off-screen arrow
--   AppKit.luau   shared app scaffolding (scroll body, loading / offline states)
--   Net.luau      CONTRACT remotes (ReplicatedStorage.GwangalliRemotes), profile, taxi / work state
--   Data.luau     GwangalliGameplayShared access + normalisers (threads, stats, items, contacts)
--   Life.luau     life-game catalogue (jobs, listings, contacts) with fallbacks
--   Dest.luau     Destination list / positions, quick travel (GwangalliTravel remote)
--   MapData.luau  static positions and map polylines
--   UI.luau       legacy helpers (formatting) used by Data / Tracker
--   Apps/         전화, 택시, 메시지, 지도, 통장, 알바, 부동산, 내 정보, 쇼핑 / 옷장, 설정, 카메라
-- Every screen is built with ReplicatedStorage.GwangalliUI (the kit) and placed with
-- ReplicatedStorage.GwangalliLayout (the screen slot contract shared with GwangalliHUD).

local function findFolder(): Instance?
	local parent = script.Parent
	for _ = 1, 100 do
		if parent then
			for _, child in parent:GetChildren() do
				if child.Name == "GwangalliPhone" and child:IsA("Folder") then
					return child
				end
			end
		end
		task.wait(0.1)
		parent = script.Parent
	end
	return nil
end

local folder = findFolder()
if not folder then
	warn("[GwangalliPhone] module folder missing next to the LocalScript")
	return
end

local phoneModule = folder:WaitForChild("Phone", 10)
if not (phoneModule and phoneModule:IsA("ModuleScript")) then
	warn("[GwangalliPhone] Phone module missing")
	return
end

local ok, Phone = pcall(require, phoneModule)
if not ok or type(Phone) ~= "table" then
	warn("[GwangalliPhone] failed to load: " .. tostring(Phone))
	return
end

local started, err = pcall(Phone.start)
if not started then
	warn("[GwangalliPhone] failed to start: " .. tostring(err))
end
