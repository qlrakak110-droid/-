--!nocheck
local B = require("./mods")
local R = B.R
local p = R.env.Instance.new("Part")
print(R.env.typeof(p), typeof(p), p:IsA("BasePart"))
