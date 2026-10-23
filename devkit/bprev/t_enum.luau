local Enums = require("./lib/enums")
Enums.setData(require("./lib/enumsdata"))
local DT = require("./lib/datatypes")
local E = DT.globals.Enum
print(E.Material.WoodPlanks, E.Material.WoodPlanks.Name, E.NormalId.Front, E.Font.GothamBold, E.KeyCode.F, E.SurfaceGuiSizingMode.PixelsPerStud)
local CF = DT.globals.CFrame
print(CF.new(1,2,3) * CF.Angles(0, math.pi/2, 0), DT.globals.UDim2.fromScale(1,1), DT.globals.Color3.fromRGB(10,20,30))
