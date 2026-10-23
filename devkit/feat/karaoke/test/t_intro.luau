local Songs = require("./sh/Songs")
local Chart = require("./sh/Chart")
for _, id in { "s01", "s54", "s33", "s46", "s12", "s42" } do
  local c = Chart.get(Songs.byId[id])
  local inter = 0
  for _, s in c.sects do if s.kind == "inter" then inter += 1 end end
  print(id, "show1", c.lines[1].show, "t0", c.lines[1].t0, "dur", c.duration, "inter", inter)
end
