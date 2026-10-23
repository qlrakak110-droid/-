--!nocheck
local R = require("./lib/rbx")
print(R.env.typeof(R.player), R.player:IsA("Player"), R.player.ClassName)
