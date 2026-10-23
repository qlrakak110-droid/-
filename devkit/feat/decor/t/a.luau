local x: number = 3
x += 1
local s = `v={x}`
print(s, if x > 2 then "big" else "small", loadstring ~= nil, typeof)
FOO = 5
local m = require("./b")
print(m())
