--!nocheck
typeof = typeof or function(v) return type(v) end
warn = warn or print
local G = require("./G")
local HS = require("./HS")
HS.extend(G)
local n, kinds, cats, parts = 0, {}, {}, {}
local tot = 0
local rows = {}
for _, id in G.FURNITURE_ORDER do
  local f = G.FURNITURE[id]
  n += 1
  local k = HS.placeKind(id)
  kinds[k] = (kinds[k] or 0) + 1
  cats[f.category] = (cats[f.category] or 0) + 1
  local pc = HS.itemPartCount(id, false)
  tot += pc
  local spec = HS.itemSpec(id, 1, false)
  local nl = spec and spec.lights and #spec.lights or 0
  local b = HS.itemBounds(id, false)
  table.insert(rows, string.format("%s\t%s\t%s\t%s\t%d\tparts=%d\tlights=%d\tcw=%d\tseat=%s\tscreen=%s\tbounds=%.1fx%.1fx%.1f", id, f.category, f.style, k, f.price, pc, nl, HS.colorwayCount(id), tostring(spec and spec.seat ~= nil), tostring(spec and spec.screen ~= nil), b[4]-b[1], b[5]-b[2], b[6]-b[3]))
end
print("items", n, "avgParts", tot / n)
for k, v in kinds do print("kind", k, v) end
for k, v in cats do print("cat", k, v) end
for _, r in rows do print(r) end
