local game = S.game
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ws = game:GetService("Workspace")
local L = {}
local function add(s) table.insert(L, s) end
local function nparts(m) local n = 0 for _, d in m:GetDescendants() do if d:IsA("BasePart") then n += 1 end end return n end
local function v(p) return string.format("(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z) end
add("SS: " .. (function() local t = {} for _, c in SS:GetChildren() do table.insert(t, c.ClassName .. ":" .. c.Name) end return table.concat(t, ", ") end)())
local cm = SS:FindFirstChild("GwangalliCarModels")
if cm then
  for _, c in cm:GetChildren() do
    local ok, cf, size = pcall(function() return c:GetBoundingBox() end)
    local mp = 0 for _, d in c:GetDescendants() do if d:IsA("MeshPart") then mp += 1 end end
    add("  tmpl " .. c.Name .. " parts=" .. nparts(c) .. " mesh=" .. mp .. " kind=" .. tostring(c:GetAttribute("VehicleKind")) .. " gw=" .. tostring(c:GetAttribute("GwCarModel")) .. (ok and (" size=" .. v(size)) or ""))
  end
else add("  NO GwangalliCarModels") end
local dt = SS:FindFirstChild("GwangalliDriveTemplates")
if dt then for _, c in dt:GetChildren() do add("  drivetmpl " .. c.Name .. " parts=" .. nparts(c) .. " kind=" .. tostring(c:GetAttribute("VehicleKind")) .. " cm=" .. tostring(c:GetAttribute("CarModel"))) end end
local bk = SS:FindFirstChild("GwangalliBikes") add("bikes tmpl: " .. tostring(bk ~= nil))
add("WS: " .. (function() local t = {} for _, c in ws:GetChildren() do table.insert(t, c.ClassName .. ":" .. c.Name) end return table.concat(t, ", ") end)())
local sr = ws:FindFirstChild("GwangalliShowroom")
if sr then
  add("showroom Placed=" .. tostring(sr:GetAttribute("Placed")) .. " n=" .. #sr:GetChildren())
  for _, c in sr:GetChildren() do
    if c:IsA("Model") then
      local cf, size = c:GetBoundingBox()
      local yaw = math.deg(math.atan2(-cf.LookVector.X, -cf.LookVector.Z))
      add("  " .. c.Name .. " id=" .. tostring(c:GetAttribute("GwShowroomModel")) .. " at " .. v(cf.Position) .. " size " .. v(size) .. " parts=" .. nparts(c) .. " look=" .. v(cf.LookVector))
    end
  end
else add("NO GwangalliShowroom") end
local bs = ws:FindFirstChild("GwangalliBikeShop") add("bikeshop: " .. tostring(bs ~= nil) .. (bs and (" at " .. v(bs:GetPivot().Position)) or ""))
local rem = RS:FindFirstChild("GwangalliRemotes")
if rem then local t = {} for _, c in rem:GetChildren() do table.insert(t, c.Name) end add("remotes: " .. table.concat(t, ",")) end
for _, n in { "GwangalliGarageAPI", "GwangalliVehiclesAPI", "GwangalliGameplayAPI", "GwangalliProgressAPI" } do add(n .. ": " .. tostring(SS:FindFirstChild(n) and SS:FindFirstChild(n).ClassName)) end
for _, m in CS:GetTagged("GarageStaff") do
  local hrp = m:FindFirstChild("HumanoidRootPart")
  local cf = m:GetPivot()
  add("staff " .. m.Name .. " role=" .. tostring(m:GetAttribute("Role")) .. " pivot " .. v(cf.Position) .. " look " .. v(cf.LookVector) .. " hrp=" .. tostring(hrp and v(hrp.Position)) .. " hum=" .. tostring(m:FindFirstChildOfClass("Humanoid") ~= nil) .. " ac=" .. tostring(m:FindFirstChildOfClass("AnimationController") ~= nil))
end
for _, m in CS:GetTagged("GarageDisplayCar") do local cf, size = m:GetBoundingBox() add("display " .. m.Name .. " at " .. v(cf.Position) .. " size " .. v(size) .. " parts=" .. nparts(m)) end
local okD = pcall(function() return Players.CreateHumanoidModelFromDescription end)
add("CreateHumanoidModelFromDescription: " .. tostring(okD) .. " " .. tostring(pcall(function() return typeof(Players.CreateHumanoidModelFromDescription) end)))
local okV, vf = pcall(function() return Instance.new("ViewportFrame") end) add("ViewportFrame: " .. tostring(okV))
local okW, wm = pcall(function() return Instance.new("WorldModel") end) add("WorldModel: " .. tostring(okW))
local pc = ws:FindFirstChild("GwangalliPlayerCars") add("playerCars folder: " .. tostring(pc ~= nil))
local prompts = 0 for _, d in ws:GetDescendants() do if d:IsA("ProximityPrompt") and (d.ActionText == "신차 보기" or d.ActionText == "구매 / 시승") then prompts += 1 end end add("garage prompts: " .. prompts)
out = table.concat(L, "\n")
