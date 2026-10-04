
-- Shared model adapter: original Gwangalli economy, navigation and physics remain authoritative.
local Builder = require(game:GetService("ReplicatedStorage"):WaitForChild("CarBuilder"))
local Adapter = {}
local types = { compact = "Hatch", sedan = "Sedan", suv = "SUV", luxury = "Sports" }
function Adapter.Build(kind)
 local key = types[kind]
 if not key then return nil end
 local m = Builder.Build(key)
 -- The existing rigger creates its own joints, seats and forces.
 for _, d in m:GetDescendants() do
  if d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("Seat") or d:IsA("VehicleSeat") then
   d:Destroy()
  elseif d:IsA("BasePart") then
   d.Anchored = true; d.CanCollide = false; d.CanTouch = false; d.CanQuery = false
   if d.Name == "Chassis" then d.Name = "Underbody" end
   if d.Name == "Cushion" then d.Name = "SeatCushion" end
   if d.Name == "SeatBase" then d.Name = "SeatSupport" end
  end
 end
 m:SetAttribute("VehicleKind", kind)
 m:SetAttribute("DriveLabel", require(game:GetService("ReplicatedStorage").CarConfig).Cars[key].Name)
 m:SetAttribute("GWIntegratedCar", true)
 -- Ground-relative pivot; legacy lane placement expects the bottom of the tyres at Y=0.
 m:PivotTo(CFrame.new(0, m:GetAttribute("RideH") or 2.6, 0))
 local root = m.PrimaryPart
 m.PrimaryPart = nil
 m.WorldPivot = CFrame.new()
 return m
end
return Adapter
