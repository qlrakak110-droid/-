--!nocheck
local B = require("../out/bundle")
local R = B.R
local G = R.G
local Vector3, CFrame, Color3 = G.Vector3, G.CFrame, G.Color3
local Unit = B.load("S", "Unit")
local Rules = B.load("S", "Rules")
local Catalog = B.load("S", "Catalog")
local fx = require("../../../bprev/fx/home_oneroom")(Vector3, Color3, CFrame)
local model = R.loadFixture(fx)
local U = Unit.scan(model)
local r = U.rooms[1]
print(r.id, r.centre, r.size)
for _, id in { "pl_monstera", "lv_sofa_3seat", "tc_tv_frame", "wl_curtain_linen" } do
	local codes = {}
	for gx = -4, 4 do
		local row = {}
		for gz = -4, 4 do
			local x, z = r.centre.X + gx * r.size.X / 10, r.centre.Z + gz * r.size.Z / 10
			local ok, code, arg = Rules.check(U, Rules.newIndex(), { i = id, x = x, y = r.floorY, z = z, r = 0 }, {})
			table.insert(row, string.sub(ok and "ok" or code, 1, 4))
		end
		table.insert(codes, table.concat(row, " "))
	end
	print(id, Catalog.dims(id))
	print("  " .. table.concat(codes, "\n  "))
end
for _, s in U.slots do print("slot", s.id, s.category, s.box.lo, s.box.hi) end
for _, k in U.keeps do print("keep", k.code, k.label, k.box.lo, k.box.hi) end
local Geometry = B.load("S", "Geometry")
local e = Rules.entry({ u = -1, i = "lv_sofa_3seat", x = r.centre.X, y = r.floorY, z = r.centre.Z, r = 0 })
for _, bx in e.boxes do
	local sb = Geometry.prime(Geometry.shrink(bx, 0.06))
	for _, s in U.solids do
		if Geometry.overlapFast(sb, s.box) then
			print("hit", s.name, s.part:GetFullName(), s.box.lo, s.box.hi, s.part.Size)
		end
	end
end
