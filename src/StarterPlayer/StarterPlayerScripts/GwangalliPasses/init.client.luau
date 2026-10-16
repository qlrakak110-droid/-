-- GwangalliPasses (LocalScript, StarterPlayerScripts): the client half of the three game passes.
--   StoreHook runs FIRST, before anything yields: the passes join the client GamePassConfig (phone "R$" app).
--   Then: premium car specs on the client VS table (the driver's controller reads them), the "👑 VIP" app
--   (dock icon + HUD shortcut + /패스), the 차 부르기 sheet hooks (원격 차고 lock / premium rows / kiosk),
--   neon name tags + chat names, KO finish effects and the 편의 패스 KO helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedM = ReplicatedStorage:FindFirstChild("GwangalliPassesShared")
local P = require(sharedM or ReplicatedStorage:WaitForChild("GwangalliPassesShared"))
local StoreHook = require(script:WaitForChild("StoreHook"))
pcall(StoreHook.inject, P)

local function load(name: string): any
	local m = script:WaitForChild(name, 20)
	if not m or not m:IsA("ModuleScript") then
		error("[GwangalliPasses] module missing: " .. name)
	end
	return require(m)
end

local ctx: any = { P = P }
ctx.K = load("Kit")
ctx.Store = StoreHook
ctx.Net = load("Net")
ctx.Hub = load("Hub")
ctx.PhoneHook = load("PhoneHook")
ctx.Preview = load("Preview")
ctx.PassTab = load("PassTab")
ctx.GarageTab = load("GarageTab")
ctx.MarketTab = load("MarketTab")
ctx.FlexTab = load("FlexTab")
ctx.DriveHook = load("DriveHook")
ctx.HudButton = load("HudButton")
ctx.NeonTags = load("NeonTags")
ctx.ChatNeon = load("ChatNeon")
ctx.KoFxClient = load("KoFxClient")
ctx.QoLClient = load("QoLClient")

-- premium kinds on the client's VS table (handling for the driver's controller; not added to Drivable)
task.spawn(function()
	local m = ReplicatedStorage:WaitForChild("GwangalliVehiclesShared", 60)
	if m and m:IsA("ModuleScript") then
		local ok, VS = pcall(require, m)
		if ok then
			P.mod("Cars").install(VS, false)
		end
	end
end)

local order = { "Store", "Net", "Preview", "Hub", "PhoneHook", "DriveHook", "HudButton", "NeonTags", "ChatNeon", "KoFxClient", "QoLClient" }
for _, name in order do
	local mod = ctx[name]
	if type(mod) == "table" and type(mod.start) == "function" then
		task.spawn(function()
			local ok, err = pcall(mod.start, ctx)
			if not ok then
				warn("[GwangalliPasses] " .. name .. " failed: " .. tostring(err))
			end
		end)
	end
end

-- server notices
ctx.Net.on("toast", function(payload: any)
	ctx.K.toast({ kind = payload.tone or "info", icon = payload.icon, title = tostring(payload.title or ""), body = payload.body })
end)
