-- GwangalliBuildingsClient: the client half of the enterable-building system.
-- Starts the door animator, the elevator client, the screens (shops, homes, chips) and a small HUD
-- (건물 지구 바로가기 / 내 집 / 부동산). Everything it shows comes from the server services; nothing the
-- client sends is trusted beyond "this player pressed this".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- the shared modules must exist before any client module runs
ReplicatedStorage:WaitForChild("GwangalliBuildingsShared")

local UI = require(script:WaitForChild("UI"))
UI.init()
local Net = require(script:WaitForChild("Net"))
local Sfx = require(script:WaitForChild("Sfx"))
local DoorAnim = require(script:WaitForChild("DoorAnim"))
local ElevClient = require(script:WaitForChild("ElevClient"))
local Screens = require(script:WaitForChild("Screens"))
local Ambience = require(script:WaitForChild("Ambience"))
local BbqView = require(script:WaitForChild("BbqView"))
local GameViews = require(script:WaitForChild("GameViews"))
local DecorMode = require(script:WaitForChild("DecorMode"))
local Living = require(script:WaitForChild("Living"))

local player = Players.LocalPlayer

local function safe(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[GwangalliBuildings] client " .. name .. ": " .. tostring(err))
	end
end

safe("doors", DoorAnim.start)
safe("elevators", ElevClient.start)
safe("screens", Screens.start)
safe("ambience", Ambience.start)
safe("living", Living.start)
safe("bbq", function()
	BbqView.start(Screens)
end)
safe("games", function()
	GameViews.start(Screens)
end)
safe("decor", function()
	DecorMode.init()
	Screens.hooks.decor = DecorMode.start
end)

-- HUD: three round buttons on the left edge (under the host game's money / settings widgets)
local function hud()
	local root = UI.root()
	local col = UI.frame(root, {
		Name = "GwB_Hud",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 16, 0, 176),
		Size = UDim2.new(0, 56, 0, 250),
	})
	UI.list(col, 8)
	local function btn(icon: string, label: string, fn: () -> ())
		local b = UI.button(col, icon .. "\n" .. label, fn, { style = "ghost", size = UDim2.new(0, 56, 0, 56), textSize = 11 })
		b.BackgroundColor3 = UI.C.bg
		b.BackgroundTransparency = 0.12
		UI.corner(b, 14)
		return b
	end
	btn("🏢", "건물지구", function()
		Sfx.ui("tap")
		Net.call("district.go", {})
	end)
	btn("🏠", "내 집", function()
		Sfx.ui("tap")
		Net.call("home.enter", {})
	end)
	btn("🛋️", "꾸미기", function()
		Sfx.ui("tap")
		DecorMode.start()
	end)
	btn("📋", "부동산", function()
		Sfx.ui("tap")
		local res = Net.request("home.listings", {})
		if res.ok then
			-- same sheet the realtor counter opens (the 부동산 app on the phone)
			Screens.openListings(res)
		end
	end)
end
safe("hud", hud)

print(string.format("[GwangalliBuildings] client ready (%s)", player.Name))
