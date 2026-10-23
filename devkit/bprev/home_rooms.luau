local R = require("./lib/rbx")
local key = ...
local fx = require("./fx/" .. key)(R.G.Vector3, R.G.Color3, R.G.CFrame)
local model = R.loadFixture(fx)
local req = require("./out/mods_homecheck")
local Homes = req("Homes")
for _, sp in Homes.rooms(model) do
	print(sp.room, string.format("W=%.1f D=%.1f H=%.1f", sp.size.X, sp.size.Y, sp.size.Z))
end
