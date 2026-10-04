-- GwangalliVehicles (server): drivable cars for 광안리 GTA ("자동차도 탈 수 있게, 내부 디테일도").
--
-- Cars stay the builder's static models (build/kit/vehicles.luau) until someone uses them; then the
-- rigger turns them into a physics assembly at runtime (docs/vehicles_contract.md):
--   Analyze  wheel / seat / lamp / frame detection (names + geometry fallback)
--   Rig      invisible ballast root + collider, wheel hubs (Motor6D), VehicleSeat + Seats, movers
--   Cars     registry, door prompts, enter / exit, network ownership, wake / settle / sleep, lamps,
--            horn, flip-back, sea (eject + sink), sanity checks, despawn / restore, cleanup on leave
--   Spawn    "차 부르기": the player's own car on the nearest road lane (GwangalliNav), limits
--   Parked   30 % of the parked NPC cars are unlocked (stable per position) and get door prompts
-- Physics: ReplicatedStorage.GwangalliVehiclesShared.Controller (raycast suspension). The driver's
-- client owns the car and runs it (StarterPlayerScripts/GwangalliDrive); the server runs it only for
-- a driverless car that still rolls, then anchors it (zero cost while parked).
--
-- Remotes (ReplicatedStorage.GwangalliVehiclesRemotes, created here):
--   Drive (RemoteEvent)   client -> server {op = "exit" | "state" (bits) | "flip"}
--                         server -> client {op = "enter" (car, role, seat) | "exit" | "toast" | "called"}
--   CallCar (RemoteFunction) client -> server ("call", kind) -> {ok, msg, car}, ("dismiss"), ("status")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local sharedModule = ReplicatedStorage:WaitForChild("GwangalliVehiclesShared", 30)
if not sharedModule then
	warn("[GwangalliVehicles] ReplicatedStorage.GwangalliVehiclesShared missing; driving disabled")
	return
end
local VS = require(sharedModule) :: any

local folder: Instance? = nil
for _, c in script.Parent:GetChildren() do
	if c:IsA("Folder") and c.Name == "GwangalliVehicles" then
		folder = c
		break
	end
end
if not folder then
	warn("[GwangalliVehicles] module folder ServerScriptService.GwangalliVehicles missing; driving disabled")
	return
end
local function mod(name: string): any
	local m = (folder :: Instance):FindFirstChild(name)
	assert(m and m:IsA("ModuleScript"), "[GwangalliVehicles] module missing: " .. name)
	return require(m)
end
local Analyze = mod("Analyze")
local Rig = mod("Rig")
local Cars = mod("Cars")
local Spawn = mod("Spawn")
local Parked = mod("Parked")

-- Remotes -------------------------------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild(VS.Remotes.Folder)
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = VS.Remotes.Folder
	remotes.Parent = ReplicatedStorage
end
local remote = remotes:FindFirstChild(VS.Remotes.Event) :: RemoteEvent
if not remote then
	local e = Instance.new("RemoteEvent")
	e.Name = VS.Remotes.Event
	e.Parent = remotes
	remote = e
end
local callFn = remotes:FindFirstChild(VS.Remotes.Call) :: RemoteFunction
if not callFn then
	local f = Instance.new("RemoteFunction")
	f.Name = VS.Remotes.Call
	f.Parent = remotes
	callFn = f
end

Rig.init(VS, Analyze)
Cars.init(VS, Rig, Analyze, remote)
Spawn.init(VS, Rig, Cars)
Parked.init(VS, Analyze, Cars)

-- Prompts ----------------------------------------------------------------------------------------------
local function carOf(inst: Instance): Model?
	local node = inst.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute(VS.Attr.Kind) ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
	local role = prompt:GetAttribute("GwangalliDrive")
	if role ~= "driver" and role ~= "passenger" then
		return
	end
	if not Cars.allow(player, 2) then
		return
	end
	local car = carOf(prompt)
	if not car then
		return
	end
	local ok, msg = Cars.enter(player, car, role)
	if not ok and msg then
		Cars.toast(player, "🚗 " .. msg, nil, "warn")
	end
end)

-- Client events -------------------------------------------------------------------------------------------
remote.OnServerEvent:Connect(function(player: Player, payload: any)
	if type(payload) ~= "table" or type(payload.op) ~= "string" then
		return
	end
	if not Cars.allow(player) then
		return
	end
	local op = payload.op
	if op == "exit" then
		Cars.exit(player)
	elseif op == "state" then
		Cars.setState(player, payload.bits)
	elseif op == "flip" then
		if not Cars.flip(player) then
			Cars.toast(player, "🚗 지금은 뒤집을 수 없어요", "멈춘 상태에서 다시 눌러 주세요", "warn")
		end
	end
end)

callFn.OnServerInvoke = function(player: Player, action: any, kind: any)
	if not Cars.allow(player, 3) then
		return { ok = false, msg = "잠시 후 다시 시도해 주세요" }
	end
	if action == "call" then
		local ok, msg, car = Spawn.call(player, kind)
		if ok then
			local label, meters = string.match(msg, "^(.-)|(%d+)$")
			return { ok = true, msg = msg, label = label, meters = tonumber(meters), car = car }
		end
		return { ok = false, msg = msg }
	elseif action == "dismiss" then
		local ok, msg = Spawn.dismiss(player)
		return { ok = ok, msg = msg }
	elseif action == "status" then
		local st = Spawn.status(player)
		st.ok = true
		return st
	end
	return { ok = false, msg = "unknown action" }
end

Players.PlayerRemoving:Connect(function(player: Player)
	Cars.playerRemoving(player)
	Spawn.playerRemoving(player)
end)

-- Loops -------------------------------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt: number)
	Cars.physicsStep(dt)
end)
task.spawn(function()
	local t = 0
	while true do
		task.wait(0.25)
		t += 1
		local ok, err = pcall(Cars.slowStep)
		if not ok then
			warn("[GwangalliVehicles] slowStep: " .. tostring(err))
		end
		if t % 20 == 0 then
			local ok2, err2 = pcall(Cars.housekeeping)
			if not ok2 then
				warn("[GwangalliVehicles] housekeeping: " .. tostring(err2))
			end
		end
	end
end)

-- Parked NPC cars: scan once the map is in place (and again when the dev switch flips) ------------------
task.delay(2, function()
	local stats = Parked.scan()
	print(string.format("[GwangalliVehicles] parked cars: %d vehicles, %d drivable, %d unlocked", stats.seen, stats.eligible, stats.unlocked))
end)
workspace:GetAttributeChangedSignal("GwangalliDriveUnlockAll"):Connect(function()
	task.spawn(Parked.scan)
end)
