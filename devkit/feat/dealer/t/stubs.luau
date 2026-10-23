--!nocheck
local V = {}
V.__index = V
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
_G.Vector3 = { new = v3, zero = v3(0,0,0), zAxis = v3(0,0,1), xAxis = v3(1,0,0), yAxis = v3(0,1,0), one = v3(1,1,1) }
_G.Color3 = { fromRGB = function(r,g,b) return {R=r/255,G=g/255,B=b/255} end, new = function(r,g,b) return {R=r,G=g,B=b} end }
local function enumProxy(path) return setmetatable({}, { __index = function(t, k) local p = enumProxy(path .. "." .. k); rawset(t, k, p); return p end, __tostring = function() return path end }) end
_G.Enum = enumProxy("Enum")
_G.game = { GetService = function() return {} end }
_G.utf8 = utf8
return true
