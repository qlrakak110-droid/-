-- GwangalliDrive (LocalScript, StarterPlayerScripts): the driving client ("자동차도 탈 수 있게").
--
-- Modules live in the sibling Folder "GwangalliDrive" (same name as this script: found by class):
--   Drive    seat detection, controller loop on the owned car, lamp / horn bits, flip, markers
--   Input    keyboard / gamepad / touch -> one input state (keys bound only while driving)
--   UI       mobile driving HUD (steer pad, pedals, handbrake, horn, camera, lights, exit,
--            speedometer) + PC hints + the 차 부르기 sheet (GwangalliUI kit, GwangalliLayout)
--   Camera   chase / hood / interior first person, FOV kick, orbit drag
--   Visuals  wheel spin / steer of other players' cars, indicator blinking
--   Radio    car radio (relays the club's discovered music, muffled outside the cabin)
--   Api      public API: open("callcar"), callCar(kind), dismiss(), status(), changed
-- Server side: ServerScriptService/GwangalliVehicles; shared: ReplicatedStorage.GwangalliVehiclesShared;
-- car model contract: docs/vehicles_contract.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function findFolder(): Instance?
	for _ = 1, 100 do
		local parent = script.Parent
		if parent then
			for _, child in parent:GetChildren() do
				if child.Name == "GwangalliDrive" and child:IsA("Folder") then
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
	warn("[GwangalliDrive] module folder missing next to the LocalScript")
	return
end

local function load(name: string): any
	local m = (folder :: Instance):WaitForChild(name, 10)
	if not (m and m:IsA("ModuleScript")) then
		error("[GwangalliDrive] module missing: " .. name)
	end
	return require(m)
end

local okAll, err = pcall(function()
	local VS = require(ReplicatedStorage:WaitForChild("GwangalliVehiclesShared", 30))
	local K = require(ReplicatedStorage:WaitForChild("GwangalliUI", 30))
	local ctx: any = {
		VS = VS,
		K = K,
		Layout = K.Layout or require(ReplicatedStorage:WaitForChild("GwangalliLayout", 30)),
		Input = load("Input"),
		Camera = load("Camera"),
		Visuals = load("Visuals"),
		Radio = load("Radio"),
		UI = load("UI"),
		Api = load("Api"),
		Drive = load("Drive"),
	}
	ctx.Api.init(ctx)
	ctx.UI.build(ctx)
	ctx.Visuals.start(VS)
	ctx.Radio.start(ctx)
	ctx.Drive.start(ctx)
	ctx.Api.registerEntryPoints()
end)
if not okAll then
	warn("[GwangalliDrive] failed to start: " .. tostring(err))
end
