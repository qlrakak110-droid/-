--!nocheck
local B = require("../out/bundle")
local R = B.R
local G = R.G
local Vector3, CFrame, Color3 = G.Vector3, G.CFrame, G.Color3
local Unit = B.load("S", "Unit")
local Rules = B.load("S", "Rules")
local Catalog = B.load("S", "Catalog")
local Geometry = B.load("S", "Geometry")
local tier = (...) or "goshiwon"
local fx = require("../../../bprev/fx/home_" .. tier)(Vector3, Color3, CFrame)
local model = R.loadFixture(fx)
local U = Unit.scan(model)
for _, f in U.floors do
	print("floor", f.name, f.room, f.level, string.format("top %.3f lo %.2f,%.2f hi %.2f,%.2f", f.top, f.box.lo.X, f.box.lo.Z, f.box.hi.X, f.box.hi.Z))
end
local r = U.rooms[1]
print("room", r.id, r.centre, r.floorY)
local id = "lv_coffee_round"
local cand = { i = id, x = r.centre.X, y = r.floorY, z = r.centre.Z, r = 0 }
print(Rules.check(U, Rules.newIndex(), cand, {}))
local pose = Geometry.pose(cand.x, cand.y, cand.z, 0)
local cf, half = Catalog.box(id)
local foot = Geometry.obb(pose * cf, half)
for _, c in Geometry.footCorners(foot, 0.15) do
	local fc = Unit.floorAt(U, c.X, c.Z, cand.y + 0.05)
	print("corner", c, fc and fc.name, fc and fc.level)
end
print("bounds", table.concat(Catalog.bounds(id), " "))
local e = Rules.entry({ u = -1, i = id, x = cand.x, y = cand.y, z = cand.z, r = 0 })
for _, bx in e.boxes do
	local sb = Geometry.prime(Geometry.shrink(bx, 0.06))
	for _, s in U.solids do
		if Geometry.overlapFast(sb, s.box) then
			print("hit solid", s.name, s.part:GetFullName(), s.box.lo, s.box.hi, "slot", s.slot)
		end
	end
end
for _, s in U.slots do print("slot", s.id, s.category, s.box.lo, s.box.hi) end
