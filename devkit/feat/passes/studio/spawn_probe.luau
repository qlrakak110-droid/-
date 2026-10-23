local ch = S.player.Character
local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
hrp.Anchored = false
ch:PivotTo(CFrame.new(-556, 10, 487))
local f = S.game:GetService("ServerStorage"):FindFirstChild("GwangalliVehiclesAPI")
local ok, msg = f:Invoke("spawnOwned", S.player, { id = "dbg", kind = "luxury", plate = "12가 3456", cond = 100, label = "dbg" }, { force = true })
local cars = S.game.Workspace:FindFirstChild("GwangalliPlayerCars")
out = "api=" .. tostring(f ~= nil) .. " ok=" .. tostring(ok) .. " msg=" .. tostring(msg) .. " cars=" .. tostring(cars and #cars:GetChildren())
