-- GwangalliShopCrew (LocalScript, StarterPlayerScripts): the client half of the shop crew add-on.
--   Bubbles (speech over the staff), Visuals (name tags · the tray with real dishes · kitchen steam · point pins ·
--   interior keep zones), Dialog (the conversation sheet), Hud (주문서 · 영수증 · 단골 카드).
-- Animation: the rigs are animated by GwangalliNPCClient (tag GwShopStaff); this script only ADDS a few acts /
-- poses to GwangalliAnim's tables (append-only; unknown acts fall back to idle there): crew_tray (one-hand tray),
-- crew_tray2 (two hands, 뚝배기 쟁반), crew_note (order pad), crew_sit_eat, crew_box, crew_cut.
-- Silent when the server half is not installed (no ReplicatedStorage.GwangalliShopCrewNet within 60 s).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local sharedMod = ReplicatedStorage:WaitForChild("GwangalliShopCrewShared", 60)
local netFolder = ReplicatedStorage:WaitForChild("GwangalliShopCrewNet", 60)
if not sharedMod or not netFolder then
	return
end
local Shared = require(sharedMod)

local function optional(name: string, timeout: number): any
	local m = ReplicatedStorage:WaitForChild(name, timeout)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			return res
		end
	end
	return nil
end

-- custom acts (before the first crew rig registers when possible) ------------------------------------
do
	local Anim = optional("GwangalliAnim", 20)
	if Anim and type(Anim.ACTS) == "table" and type(Anim.POSES) == "table" then
		pcall(function()
			local P, A = Anim.POSES, Anim.ACTS
			P.crew_tray2 = P.crew_tray2 or { LeftShoulder = { 34, 0, 10 }, LeftElbow = { 80, 0, 0 }, RightShoulder = { 34, 0, -10 }, RightElbow = { 80, 0, 0 } }
			P.crew_box = P.crew_box or { LeftShoulder = { 40, 0, 14 }, LeftElbow = { 62, 0, 0 }, RightShoulder = { 40, 0, -14 }, RightElbow = { 62, 0, 0 }, Waist = { -3, 0, 0 } }
			if not P.crew_sit_eat then
				local base = P.sit_bench or P.sit or {}
				local pose = table.clone(base)
				pose.RightShoulder = { 34, 0, -8 }
				pose.RightElbow = { 96, 0, 0 }
				pose.Neck = { -10, 0, 0 }
				P.crew_sit_eat = pose
			end
			A.crew_tray = A.crew_tray or { base = "idle", pose = if P.tray then "tray" else "cup", gesture = "breathe", walkPose = if P.tray then "tray" else "cup" }
			A.crew_tray2 = A.crew_tray2 or { base = "idle", pose = "crew_tray2", gesture = "breathe", walkPose = "crew_tray2" }
			A.crew_note = A.crew_note or { base = "idle", pose = "clipboard", gesture = "scroll", walkPose = "clipboard" }
			A.crew_sit_eat = A.crew_sit_eat or { base = "idle", pose = "crew_sit_eat", gesture = "nod" }
			A.crew_box = A.crew_box or { base = "idle", pose = "crew_box", gesture = "breathe", walkPose = "crew_box" }
			A.crew_cut = A.crew_cut or { base = "idle", pose = if P.paint then "paint" else "cook", gesture = "chop" }
		end)
	end
end

local K = optional("GwangalliUI", 10)
local Layout = optional("GwangalliLayout", 10)

local Net = require(script:WaitForChild("Net"))
if not Net.init(netFolder) then
	return
end
local Bubbles = require(script:WaitForChild("Bubbles"))
local Visuals = require(script:WaitForChild("Visuals"))
local Dialog = require(script:WaitForChild("Dialog"))
local Hud = require(script:WaitForChild("Hud"))

-- crew rigs (NpcId) and augmented staff (CrewAugId) by id, for bubbles / fx
local function find(id: string): Model?
	for _, m in CollectionService:GetTagged(Shared.TAG) do
		if m:IsA("Model") and m:GetAttribute("NpcId") == id then
			return m
		end
	end
	for _, m in CollectionService:GetTagged("GwCrewAug") do
		if m:IsA("Model") and m:GetAttribute("CrewAugId") == id then
			return m
		end
	end
	return nil
end

local ctx = {
	player = player,
	gui = playerGui,
	Shared = Shared,
	K = K,
	Layout = Layout,
	Net = Net,
	find = find,
	toast = function(text: string, kind: string?)
		Hud.toast(text, kind)
	end,
}

Bubbles.init(ctx)
Hud.init(ctx)
Dialog.init(ctx)
Visuals.init(ctx)

Net.on("say", function(d)
	if type(d.id) == "string" and type(d.text) == "string" then
		Bubbles.say(d.id, d.text, d.dur, d.tone)
	end
end)
