--!nocheck
local B = require("../out/bundle")
local Catalog = B.load("S", "Catalog")
local n = 0
local cats = {}
local tot = 0
local maxP, maxId = 0, ""
local problems = {}
for _, id in Catalog.ORDER do
	n += 1
	local def = Catalog.get(id)
	cats[def.cat] = (cats[def.cat] or 0) + 1
	local spec = Catalog.spec(id)
	if not spec then
		table.insert(problems, id .. ": no spec")
	else
		local pc = Catalog.partCount(id)
		tot += pc
		if pc > maxP then maxP, maxId = pc, id end
		local d = Catalog.dims(id)
		local sz = def.size
		if math.abs(d.X - sz[1]) > 1.2 or math.abs(d.Y - sz[2]) > 1.2 or math.abs(d.Z - sz[3]) > 1.2 then
			table.insert(problems, string.format("%s: dims %.2f %.2f %.2f vs size %.1f %.1f %.1f", id, d.X, d.Y, d.Z, sz[1], sz[2], sz[3]))
		end
		local b = Catalog.bounds(id)
		if b[2] < -0.05 then table.insert(problems, id .. ": below origin " .. b[2]) end
		if def.place == "wall" and b[6] > 0.05 + (sz[3] / 2) then table.insert(problems, id .. string.format(": wall back z1=%.2f", b[6])) end
	end
end
print("items", n, "avgParts", tot / math.max(n, 1), "max", maxP, maxId)
for c, v in cats do print("cat", c, v) end
for _, p in problems do print("PROBLEM", p) end
