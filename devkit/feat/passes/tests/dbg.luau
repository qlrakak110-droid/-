local R = require("../t/lib/rbx")
local E = R.env
local p = R.player
print(E.typeof(p), p:IsA("Player"), p.Parent == E.game:GetService("Players"), p.Parent, p.ClassName)
