--!nocheck
-- datatypes.luau — pure-Luau Roblox datatypes for the RobloxLite player (PLAYER_ARCH §1).
--
-- Runs unchanged in Lune (tests) and in luau-web. Requires "./enums" (the host's require must resolve it).
--
-- Every value is a Luau table whose metatable carries `__type = "<Roblox type name>"`; DT.typeof reads it
-- (any engine table with such a metatable, e.g. Instance or RBXScriptSignal, is reported the same way).
-- Immutable datatypes keep their public fields as raw keys for speed (reads never hit a metamethod):
--   Vector3/Vector2/Vector3int16/Vector2int16  {X, Y, Z}
--   CFrame      array {[1..3] = x, y, z, [4..12] = R00, R01, R02, R10, R11, R12, R20, R21, R22} (row-major);
--               .X/.Y/.Z/.Position etc. go through __index (a pure array allocates ~3x faster than mixed)
--   Color3      {R, G, B}          UDim {Scale, Offset}      UDim2 {X = UDim, Y = UDim}
--   NumberRange {Min, Max}         keypoints {Time, Value[, Envelope]}   TweenInfo {Time, EasingStyle, ...}
--   BrickColor  {Number, Name, Color}  PhysicalProperties {Density, ...}  Ray {Origin, Direction}
--   RaycastResult {Instance, Position, Normal, Material, Distance}
-- Assigning to such a raw field is not trapped (Roblox would error); constants (Vector3.zero, CFrame.identity,
-- ...) are frozen. Numbers are doubles (Roblox stores float32), so results match Roblox within ~1e-6.
-- UDim.Offset is an integer (truncated toward zero, like Roblox).

local Enums = require("./enums")
local Enum = Enums.Enum

local DT = {}

local sqrt, abs, floor, ceil, sin, cos, acos, asin, atan2 = math.sqrt, math.abs, math.floor, math.ceil, math.sin, math.cos, math.acos, math.asin, math.atan2
local pi, huge = math.pi, math.huge
local setmetatable, getmetatable, rawget, type, tostring, tonumber, select, error = setmetatable, getmetatable, rawget, type, tostring, tonumber, select, error
local sformat = string.format
local builtinTypeof = typeof

---------------------------------------------------------------------------------------------------------
-- typeof / type
---------------------------------------------------------------------------------------------------------
local function dtypeof(v): string
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" then
			local n = rawget(mt, "__type")
			if type(n) == "string" then
				return n
			end
		end
		return "table"
	end
	return builtinTypeof(v)
end
DT.typeof = dtypeof

---------------------------------------------------------------------------------------------------------
-- shared helpers
---------------------------------------------------------------------------------------------------------
local function fmtn(n: number): string
	if n == floor(n) and abs(n) < 1e15 then
		if n == 0 and 1 / n < 0 then
			return "-0"
		end
		return sformat("%d", n)
	end
	if n ~= n then
		return "nan"
	end
	if n == huge then
		return "inf"
	elseif n == -huge then
		return "-inf"
	end
	return sformat("%.7g", n)
end
DT.formatNumber = fmtn

local function argError(i: number, fname: string, expected: string, v, level: number?)
	error(sformat("invalid argument #%d to '%s' (%s expected, got %s)", i, fname, expected, dtypeof(v)), level or 3)
end

-- number argument, nil -> default (0)
local function optnum(v, i, fname, default)
	local t = type(v)
	if t == "number" then
		return v
	elseif v == nil then
		return default or 0
	elseif t == "string" then
		local n = tonumber(v)
		if n then
			return n
		end
	end
	argError(i, fname, "number", v, 4)
	return 0
end

local function checknum(v, i, fname)
	local t = type(v)
	if t == "number" then
		return v
	elseif t == "string" then
		local n = tonumber(v)
		if n then
			return n
		end
	end
	argError(i, fname, "number", v, 4)
	return 0
end

local function arithError(op: string, a, b)
	error(sformat("attempt to perform arithmetic (%s) on %s and %s", op, dtypeof(a), dtypeof(b)), 3)
end

local function readOnly(_, k)
	error(sformat("%s cannot be assigned to", tostring(k)), 2)
end

local function member(typeName: string, k)
	error(sformat("%s is not a valid member of %s", tostring(k), typeName), 3)
end

local function enumArg(enumName: string, v, i: number, fname: string)
	local it = Enums.coerce(enumName, v)
	if it == nil then
		argError(i, fname, "Enum." .. enumName, v, 4)
	end
	return it
end

-- round half away from zero (UDim2:Lerp offsets)
local function roundAway(n: number): number
	if n >= 0 then
		return floor(n + 0.5)
	end
	return -floor(-n + 0.5)
end

local function trunc(n: number): number
	if n >= 0 then
		return floor(n)
	end
	return ceil(n)
end

---------------------------------------------------------------------------------------------------------
-- Vector3
---------------------------------------------------------------------------------------------------------
local V3 = { __type = "Vector3" }
local V3m = {}
local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, V3)
end
DT.V3meta, DT.v3 = V3, v3

V3.__index = function(v, k)
	local m = V3m[k]
	if m then
		return m
	end
	if k == "Magnitude" or k == "magnitude" then
		local x, y, z = v.X, v.Y, v.Z
		return sqrt(x * x + y * y + z * z)
	elseif k == "Unit" or k == "unit" then
		local x, y, z = v.X, v.Y, v.Z
		local l = sqrt(x * x + y * y + z * z)
		return setmetatable({ X = x / l, Y = y / l, Z = z / l }, V3)
	elseif k == "x" then
		return v.X
	elseif k == "y" then
		return v.Y
	elseif k == "z" then
		return v.Z
	end
	member("Vector3", k)
	return nil
end
V3.__newindex = readOnly
V3.__add = function(a, b)
	if getmetatable(a) == V3 and getmetatable(b) == V3 then
		return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, V3)
	end
	arithError("add", a, b)
	return nil
end
V3.__sub = function(a, b)
	if getmetatable(a) == V3 and getmetatable(b) == V3 then
		return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, V3)
	end
	arithError("sub", a, b)
	return nil
end
V3.__mul = function(a, b)
	local ta, tb = type(a), type(b)
	if tb == "number" and getmetatable(a) == V3 then
		return setmetatable({ X = a.X * b, Y = a.Y * b, Z = a.Z * b }, V3)
	elseif ta == "number" and getmetatable(b) == V3 then
		return setmetatable({ X = a * b.X, Y = a * b.Y, Z = a * b.Z }, V3)
	elseif getmetatable(a) == V3 and getmetatable(b) == V3 then
		return setmetatable({ X = a.X * b.X, Y = a.Y * b.Y, Z = a.Z * b.Z }, V3)
	end
	arithError("mul", a, b)
	return nil
end
V3.__div = function(a, b)
	local ta, tb = type(a), type(b)
	if tb == "number" and getmetatable(a) == V3 then
		return setmetatable({ X = a.X / b, Y = a.Y / b, Z = a.Z / b }, V3)
	elseif ta == "number" and getmetatable(b) == V3 then
		return setmetatable({ X = a / b.X, Y = a / b.Y, Z = a / b.Z }, V3)
	elseif getmetatable(a) == V3 and getmetatable(b) == V3 then
		return setmetatable({ X = a.X / b.X, Y = a.Y / b.Y, Z = a.Z / b.Z }, V3)
	end
	arithError("div", a, b)
	return nil
end
V3.__idiv = function(a, b)
	local ta, tb = type(a), type(b)
	if tb == "number" and getmetatable(a) == V3 then
		return setmetatable({ X = floor(a.X / b), Y = floor(a.Y / b), Z = floor(a.Z / b) }, V3)
	elseif ta == "number" and getmetatable(b) == V3 then
		return setmetatable({ X = floor(a / b.X), Y = floor(a / b.Y), Z = floor(a / b.Z) }, V3)
	elseif getmetatable(a) == V3 and getmetatable(b) == V3 then
		return setmetatable({ X = floor(a.X / b.X), Y = floor(a.Y / b.Y), Z = floor(a.Z / b.Z) }, V3)
	end
	arithError("idiv", a, b)
	return nil
end
V3.__unm = function(a)
	return setmetatable({ X = -a.X, Y = -a.Y, Z = -a.Z }, V3)
end
V3.__eq = function(a, b)
	return getmetatable(a) == V3 and getmetatable(b) == V3 and a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return fmtn(v.X) .. ", " .. fmtn(v.Y) .. ", " .. fmtn(v.Z)
end

local function checkV3(v, i, fname)
	if getmetatable(v) ~= V3 then
		argError(i, fname, "Vector3", v, 4)
	end
	return v
end

function V3m.Abs(v)
	return setmetatable({ X = abs(v.X), Y = abs(v.Y), Z = abs(v.Z) }, V3)
end
function V3m.Ceil(v)
	return setmetatable({ X = ceil(v.X), Y = ceil(v.Y), Z = ceil(v.Z) }, V3)
end
function V3m.Floor(v)
	return setmetatable({ X = floor(v.X), Y = floor(v.Y), Z = floor(v.Z) }, V3)
end
function V3m.Sign(v)
	return setmetatable({ X = math.sign(v.X), Y = math.sign(v.Y), Z = math.sign(v.Z) }, V3)
end
function V3m.Dot(a, b)
	checkV3(b, 1, "Dot")
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3m.Cross(a, b)
	checkV3(b, 1, "Cross")
	local ax, ay, az, bx, by, bz = a.X, a.Y, a.Z, b.X, b.Y, b.Z
	return setmetatable({ X = ay * bz - az * by, Y = az * bx - ax * bz, Z = ax * by - ay * bx }, V3)
end
function V3m.Angle(a, b, axis)
	checkV3(b, 1, "Angle")
	local ax, ay, az, bx, by, bz = a.X, a.Y, a.Z, b.X, b.Y, b.Z
	local cx, cy, cz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
	local ang = atan2(sqrt(cx * cx + cy * cy + cz * cz), ax * bx + ay * by + az * bz)
	if axis ~= nil then
		checkV3(axis, 2, "Angle")
		if cx * axis.X + cy * axis.Y + cz * axis.Z < 0 then
			ang = -ang
		end
	end
	return ang
end
function V3m.FuzzyEq(a, b, eps)
	checkV3(b, 1, "FuzzyEq")
	eps = eps or 1e-5
	return abs(a.X - b.X) <= eps and abs(a.Y - b.Y) <= eps and abs(a.Z - b.Z) <= eps
end
function V3m.Lerp(a, b, t)
	checkV3(b, 1, "Lerp")
	t = checknum(t, 2, "Lerp")
	return setmetatable({ X = a.X + (b.X - a.X) * t, Y = a.Y + (b.Y - a.Y) * t, Z = a.Z + (b.Z - a.Z) * t }, V3)
end
function V3m.Max(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for i = 1, select("#", ...) do
		local o = checkV3((select(i, ...)), i, "Max")
		if o.X > x then
			x = o.X
		end
		if o.Y > y then
			y = o.Y
		end
		if o.Z > z then
			z = o.Z
		end
	end
	return setmetatable({ X = x, Y = y, Z = z }, V3)
end
function V3m.Min(a, ...)
	local x, y, z = a.X, a.Y, a.Z
	for i = 1, select("#", ...) do
		local o = checkV3((select(i, ...)), i, "Min")
		if o.X < x then
			x = o.X
		end
		if o.Y < y then
			y = o.Y
		end
		if o.Z < z then
			z = o.Z
		end
	end
	return setmetatable({ X = x, Y = y, Z = z }, V3)
end

local NORMAL_VECTORS = {
	Right = { 1, 0, 0 },
	Top = { 0, 1, 0 },
	Back = { 0, 0, 1 },
	Left = { -1, 0, 0 },
	Bottom = { 0, -1, 0 },
	Front = { 0, 0, -1 },
}
local AXIS_VECTORS = { X = { 1, 0, 0 }, Y = { 0, 1, 0 }, Z = { 0, 0, 1 } }

local Vector3 = {
	new = function(x, y, z)
		if type(x) == "number" and type(y) == "number" and type(z) == "number" then
			return setmetatable({ X = x, Y = y, Z = z }, V3)
		end
		return setmetatable({ X = optnum(x, 1, "new"), Y = optnum(y, 2, "new"), Z = optnum(z, 3, "new") }, V3)
	end,
	zero = table.freeze(setmetatable({ X = 0, Y = 0, Z = 0 }, V3)),
	one = table.freeze(setmetatable({ X = 1, Y = 1, Z = 1 }, V3)),
	xAxis = table.freeze(setmetatable({ X = 1, Y = 0, Z = 0 }, V3)),
	yAxis = table.freeze(setmetatable({ X = 0, Y = 1, Z = 0 }, V3)),
	zAxis = table.freeze(setmetatable({ X = 0, Y = 0, Z = 1 }, V3)),
	FromNormalId = function(normalId)
		local it = enumArg("NormalId", normalId, 1, "FromNormalId")
		local d = NORMAL_VECTORS[it.Name]
		return setmetatable({ X = d[1], Y = d[2], Z = d[3] }, V3)
	end,
	FromAxis = function(axis)
		local it = enumArg("Axis", axis, 1, "FromAxis")
		local d = AXIS_VECTORS[it.Name]
		return setmetatable({ X = d[1], Y = d[2], Z = d[3] }, V3)
	end,
}
DT.Vector3 = Vector3

---------------------------------------------------------------------------------------------------------
-- Vector2
---------------------------------------------------------------------------------------------------------
local V2 = { __type = "Vector2" }
local V2m = {}
local function v2(x, y)
	return setmetatable({ X = x, Y = y }, V2)
end
DT.V2meta, DT.v2 = V2, v2

V2.__index = function(v, k)
	local m = V2m[k]
	if m then
		return m
	end
	if k == "Magnitude" or k == "magnitude" then
		local x, y = v.X, v.Y
		return sqrt(x * x + y * y)
	elseif k == "Unit" or k == "unit" then
		local x, y = v.X, v.Y
		local l = sqrt(x * x + y * y)
		return setmetatable({ X = x / l, Y = y / l }, V2)
	elseif k == "x" then
		return v.X
	elseif k == "y" then
		return v.Y
	end
	member("Vector2", k)
	return nil
end
V2.__newindex = readOnly
V2.__add = function(a, b)
	if getmetatable(a) == V2 and getmetatable(b) == V2 then
		return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y }, V2)
	end
	arithError("add", a, b)
	return nil
end
V2.__sub = function(a, b)
	if getmetatable(a) == V2 and getmetatable(b) == V2 then
		return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y }, V2)
	end
	arithError("sub", a, b)
	return nil
end
V2.__mul = function(a, b)
	if type(b) == "number" and getmetatable(a) == V2 then
		return setmetatable({ X = a.X * b, Y = a.Y * b }, V2)
	elseif type(a) == "number" and getmetatable(b) == V2 then
		return setmetatable({ X = a * b.X, Y = a * b.Y }, V2)
	elseif getmetatable(a) == V2 and getmetatable(b) == V2 then
		return setmetatable({ X = a.X * b.X, Y = a.Y * b.Y }, V2)
	end
	arithError("mul", a, b)
	return nil
end
V2.__div = function(a, b)
	if type(b) == "number" and getmetatable(a) == V2 then
		return setmetatable({ X = a.X / b, Y = a.Y / b }, V2)
	elseif type(a) == "number" and getmetatable(b) == V2 then
		return setmetatable({ X = a / b.X, Y = a / b.Y }, V2)
	elseif getmetatable(a) == V2 and getmetatable(b) == V2 then
		return setmetatable({ X = a.X / b.X, Y = a.Y / b.Y }, V2)
	end
	arithError("div", a, b)
	return nil
end
V2.__idiv = function(a, b)
	if type(b) == "number" and getmetatable(a) == V2 then
		return setmetatable({ X = floor(a.X / b), Y = floor(a.Y / b) }, V2)
	elseif type(a) == "number" and getmetatable(b) == V2 then
		return setmetatable({ X = floor(a / b.X), Y = floor(a / b.Y) }, V2)
	elseif getmetatable(a) == V2 and getmetatable(b) == V2 then
		return setmetatable({ X = floor(a.X / b.X), Y = floor(a.Y / b.Y) }, V2)
	end
	arithError("idiv", a, b)
	return nil
end
V2.__unm = function(a)
	return setmetatable({ X = -a.X, Y = -a.Y }, V2)
end
V2.__eq = function(a, b)
	return getmetatable(a) == V2 and getmetatable(b) == V2 and a.X == b.X and a.Y == b.Y
end
V2.__tostring = function(v)
	return fmtn(v.X) .. ", " .. fmtn(v.Y)
end

local function checkV2(v, i, fname)
	if getmetatable(v) ~= V2 then
		argError(i, fname, "Vector2", v, 4)
	end
	return v
end

function V2m.Abs(v)
	return setmetatable({ X = abs(v.X), Y = abs(v.Y) }, V2)
end
function V2m.Ceil(v)
	return setmetatable({ X = ceil(v.X), Y = ceil(v.Y) }, V2)
end
function V2m.Floor(v)
	return setmetatable({ X = floor(v.X), Y = floor(v.Y) }, V2)
end
function V2m.Sign(v)
	return setmetatable({ X = math.sign(v.X), Y = math.sign(v.Y) }, V2)
end
function V2m.Dot(a, b)
	checkV2(b, 1, "Dot")
	return a.X * b.X + a.Y * b.Y
end
function V2m.Cross(a, b)
	checkV2(b, 1, "Cross")
	return a.X * b.Y - a.Y * b.X
end
function V2m.Angle(a, b, isSigned)
	checkV2(b, 1, "Angle")
	local ang = atan2(a.X * b.Y - a.Y * b.X, a.X * b.X + a.Y * b.Y)
	if isSigned then
		return ang
	end
	return abs(ang)
end
function V2m.FuzzyEq(a, b, eps)
	checkV2(b, 1, "FuzzyEq")
	eps = eps or 1e-5
	return abs(a.X - b.X) <= eps and abs(a.Y - b.Y) <= eps
end
function V2m.Lerp(a, b, t)
	checkV2(b, 1, "Lerp")
	t = checknum(t, 2, "Lerp")
	return setmetatable({ X = a.X + (b.X - a.X) * t, Y = a.Y + (b.Y - a.Y) * t }, V2)
end
function V2m.Max(a, ...)
	local x, y = a.X, a.Y
	for i = 1, select("#", ...) do
		local o = checkV2((select(i, ...)), i, "Max")
		if o.X > x then
			x = o.X
		end
		if o.Y > y then
			y = o.Y
		end
	end
	return setmetatable({ X = x, Y = y }, V2)
end
function V2m.Min(a, ...)
	local x, y = a.X, a.Y
	for i = 1, select("#", ...) do
		local o = checkV2((select(i, ...)), i, "Min")
		if o.X < x then
			x = o.X
		end
		if o.Y < y then
			y = o.Y
		end
	end
	return setmetatable({ X = x, Y = y }, V2)
end

local Vector2 = {
	new = function(x, y)
		if type(x) == "number" and type(y) == "number" then
			return setmetatable({ X = x, Y = y }, V2)
		end
		return setmetatable({ X = optnum(x, 1, "new"), Y = optnum(y, 2, "new") }, V2)
	end,
	zero = table.freeze(setmetatable({ X = 0, Y = 0 }, V2)),
	one = table.freeze(setmetatable({ X = 1, Y = 1 }, V2)),
	xAxis = table.freeze(setmetatable({ X = 1, Y = 0 }, V2)),
	yAxis = table.freeze(setmetatable({ X = 0, Y = 1 }, V2)),
}
DT.Vector2 = Vector2

---------------------------------------------------------------------------------------------------------
-- Vector3int16 / Vector2int16 (integer vectors, clamped to int16)
---------------------------------------------------------------------------------------------------------
local function i16(n)
	n = trunc(n)
	if n > 32767 then
		return 32767
	elseif n < -32768 then
		return -32768
	end
	return n
end

local V3i = { __type = "Vector3int16" }
local function v3i(x, y, z)
	return setmetatable({ X = i16(x), Y = i16(y), Z = i16(z) }, V3i)
end
V3i.__index = function(_, k)
	member("Vector3int16", k)
end
V3i.__newindex = readOnly
V3i.__add = function(a, b)
	if getmetatable(a) == V3i and getmetatable(b) == V3i then
		return v3i(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
	end
	arithError("add", a, b)
	return nil
end
V3i.__sub = function(a, b)
	if getmetatable(a) == V3i and getmetatable(b) == V3i then
		return v3i(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
	end
	arithError("sub", a, b)
	return nil
end
V3i.__mul = function(a, b)
	if getmetatable(a) == V3i and getmetatable(b) == V3i then
		return v3i(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	elseif getmetatable(a) == V3i and type(b) == "number" then
		return v3i(a.X * b, a.Y * b, a.Z * b)
	elseif type(a) == "number" and getmetatable(b) == V3i then
		return v3i(a * b.X, a * b.Y, a * b.Z)
	end
	arithError("mul", a, b)
	return nil
end
V3i.__div = function(a, b)
	if getmetatable(a) == V3i and getmetatable(b) == V3i then
		return v3i(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
	elseif getmetatable(a) == V3i and type(b) == "number" then
		return v3i(a.X / b, a.Y / b, a.Z / b)
	end
	arithError("div", a, b)
	return nil
end
V3i.__unm = function(a)
	return v3i(-a.X, -a.Y, -a.Z)
end
V3i.__eq = function(a, b)
	return getmetatable(a) == V3i and getmetatable(b) == V3i and a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3i.__tostring = function(v)
	return v.X .. ", " .. v.Y .. ", " .. v.Z
end
DT.Vector3int16 = {
	new = function(x, y, z)
		return v3i(optnum(x, 1, "new"), optnum(y, 2, "new"), optnum(z, 3, "new"))
	end,
}

local V2i = { __type = "Vector2int16" }
local function v2i(x, y)
	return setmetatable({ X = i16(x), Y = i16(y) }, V2i)
end
V2i.__index = function(_, k)
	member("Vector2int16", k)
end
V2i.__newindex = readOnly
V2i.__add = function(a, b)
	if getmetatable(a) == V2i and getmetatable(b) == V2i then
		return v2i(a.X + b.X, a.Y + b.Y)
	end
	arithError("add", a, b)
	return nil
end
V2i.__sub = function(a, b)
	if getmetatable(a) == V2i and getmetatable(b) == V2i then
		return v2i(a.X - b.X, a.Y - b.Y)
	end
	arithError("sub", a, b)
	return nil
end
V2i.__mul = function(a, b)
	if getmetatable(a) == V2i and getmetatable(b) == V2i then
		return v2i(a.X * b.X, a.Y * b.Y)
	elseif getmetatable(a) == V2i and type(b) == "number" then
		return v2i(a.X * b, a.Y * b)
	elseif type(a) == "number" and getmetatable(b) == V2i then
		return v2i(a * b.X, a * b.Y)
	end
	arithError("mul", a, b)
	return nil
end
V2i.__div = function(a, b)
	if getmetatable(a) == V2i and getmetatable(b) == V2i then
		return v2i(a.X / b.X, a.Y / b.Y)
	elseif getmetatable(a) == V2i and type(b) == "number" then
		return v2i(a.X / b, a.Y / b)
	end
	arithError("div", a, b)
	return nil
end
V2i.__unm = function(a)
	return v2i(-a.X, -a.Y)
end
V2i.__eq = function(a, b)
	return getmetatable(a) == V2i and getmetatable(b) == V2i and a.X == b.X and a.Y == b.Y
end
V2i.__tostring = function(v)
	return v.X .. ", " .. v.Y
end
DT.Vector2int16 = {
	new = function(x, y)
		return v2i(optnum(x, 1, "new"), optnum(y, 2, "new"))
	end,
}

---------------------------------------------------------------------------------------------------------
-- CFrame  (array layout: [1..3] = position, [4..12] = R00 R01 R02 R10 R11 R12 R20 R21 R22, row-major)
---------------------------------------------------------------------------------------------------------
local CF = { __type = "CFrame" }
local CFm = {}
local CFget = {}
local function cf(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return setmetatable({ x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }, CF)
end
DT.CFmeta, DT.cf = CF, cf

local function quatToCF(x, y, z, qx, qy, qz, qw)
	local n = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if n == 0 or n ~= n then
		return cf(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n
	local xx, yy, zz = qx * qx, qy * qy, qz * qz
	local xy, xz, yz = qx * qy, qx * qz, qy * qz
	local wx, wy, wz = qw * qx, qw * qy, qw * qz
	return cf(x, y, z, 1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy), 2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx), 2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy))
end

-- rotation matrix -> unit quaternion (x, y, z, w), w >= 0
local function cfToQuat(c)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]
	local tr = m00 + m11 + m22
	local qx, qy, qz, qw
	if tr > 0 then
		local s = sqrt(tr + 1) * 2
		qw = 0.25 * s
		qx = (m21 - m12) / s
		qy = (m02 - m20) / s
		qz = (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = sqrt(1 + m00 - m11 - m22) * 2
		qw = (m21 - m12) / s
		qx = 0.25 * s
		qy = (m01 + m10) / s
		qz = (m02 + m20) / s
	elseif m11 > m22 then
		local s = sqrt(1 + m11 - m00 - m22) * 2
		qw = (m02 - m20) / s
		qx = (m01 + m10) / s
		qy = 0.25 * s
		qz = (m12 + m21) / s
	else
		local s = sqrt(1 + m22 - m00 - m11) * 2
		qw = (m10 - m01) / s
		qx = (m02 + m20) / s
		qy = (m12 + m21) / s
		qz = 0.25 * s
	end
	local n = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n
	if qw < 0 then
		qx, qy, qz, qw = -qx, -qy, -qz, -qw
	end
	return qx, qy, qz, qw
end
DT.cfToQuat = cfToQuat

local function axisAngleCF(x, y, z, ax, ay, az, t)
	local l = sqrt(ax * ax + ay * ay + az * az)
	if l == 0 or l ~= l then
		return cf(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	ax, ay, az = ax / l, ay / l, az / l
	local c, s = cos(t), sin(t)
	local C = 1 - c
	return cf(
		x,
		y,
		z,
		ax * ax * C + c,
		ax * ay * C - az * s,
		ax * az * C + ay * s,
		ay * ax * C + az * s,
		ay * ay * C + c,
		ay * az * C - ax * s,
		az * ax * C - ay * s,
		az * ay * C + ax * s,
		az * az * C + c
	)
end

-- Rx(a) * Ry(b) * Rz(c)
local function eulerXYZ(a, b, c)
	local ca, sa, cb, sb, cc, sc = cos(a), sin(a), cos(b), sin(b), cos(c), sin(c)
	return cf(0, 0, 0, cb * cc, -cb * sc, sb, ca * sc + sa * sb * cc, ca * cc - sa * sb * sc, -sa * cb, sa * sc - ca * sb * cc, sa * cc + ca * sb * sc, ca * cb)
end
-- Ry(b) * Rx(a) * Rz(c)
local function eulerYXZ(a, b, c)
	local ca, sa, cb, sb, cc, sc = cos(a), sin(a), cos(b), sin(b), cos(c), sin(c)
	return cf(0, 0, 0, cb * cc + sb * sa * sc, -cb * sc + sb * sa * cc, sb * ca, ca * sc, ca * cc, -sa, -sb * cc + cb * sa * sc, sb * sc + cb * sa * cc, cb * ca)
end

-- full product a * b
local function cfMul(a, b)
	local a1, a2, a3, a4, a5, a6, a7, a8, a9 = a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]
	local b1, b2, b3, b4, b5, b6, b7, b8, b9 = b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12]
	local bx, by, bz = b[1], b[2], b[3]
	return setmetatable({
		a1 * bx + a2 * by + a3 * bz + a[1],
		a4 * bx + a5 * by + a6 * bz + a[2],
		a7 * bx + a8 * by + a9 * bz + a[3],
		a1 * b1 + a2 * b4 + a3 * b7,
		a1 * b2 + a2 * b5 + a3 * b8,
		a1 * b3 + a2 * b6 + a3 * b9,
		a4 * b1 + a5 * b4 + a6 * b7,
		a4 * b2 + a5 * b5 + a6 * b8,
		a4 * b3 + a5 * b6 + a6 * b9,
		a7 * b1 + a8 * b4 + a9 * b7,
		a7 * b2 + a8 * b5 + a9 * b8,
		a7 * b3 + a8 * b6 + a9 * b9,
	}, CF)
end

-- inverse, assuming an orthonormal rotation (transpose)
local function cfInverse(c)
	local x, y, z, a, b, d, e, f, g, h, i, j = c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]
	return cf(-(a * x + e * y + h * z), -(b * x + f * y + i * z), -(d * x + g * y + j * z), a, e, h, b, f, i, d, g, j)
end

local function elemRot(axis, t)
	local c, s = cos(t), sin(t)
	if axis == "X" then
		return cf(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
	elseif axis == "Y" then
		return cf(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
	end
	return cf(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end

local ORDER_AXES = { XYZ = { 1, 2, 3 }, XZY = { 1, 3, 2 }, YZX = { 2, 3, 1 }, YXZ = { 2, 1, 3 }, ZXY = { 3, 1, 2 }, ZYX = { 3, 2, 1 } }
local AXIS_LETTER = { "X", "Y", "Z" }

local function orderName(order, i, fname)
	if order == nil then
		return "XYZ"
	end
	local it = enumArg("RotationOrder", order, i, fname)
	return it.Name
end

-- R = R_first(angle_first) * R_second(...) * R_third(...), angles given as (rx, ry, rz)
local function eulerOrdered(rx, ry, rz, order)
	if order == "XYZ" then
		return eulerXYZ(rx, ry, rz)
	elseif order == "YXZ" then
		return eulerYXZ(rx, ry, rz)
	end
	local ang = { rx, ry, rz }
	local ax = ORDER_AXES[order]
	local r = elemRot(AXIS_LETTER[ax[1]], ang[ax[1]])
	r = cfMul(r, elemRot(AXIS_LETTER[ax[2]], ang[ax[2]]))
	return cfMul(r, elemRot(AXIS_LETTER[ax[3]], ang[ax[3]]))
end

-- inverse of eulerOrdered: returns rx, ry, rz
local function toEulerOrdered(c, order)
	local ax = ORDER_AXES[order]
	local i, j, k = ax[1], ax[2], ax[3]
	-- parity: +1 for XYZ/YZX/ZXY, -1 for the others
	local s = if (j - i) % 3 == 1 then 1 else -1
	local function R(r, col)
		return c[r * 3 + col]
	end
	local sij = s * R(i, k)
	local rjk, rkk = R(j, k), R(k, k)
	local cj = sqrt(rjk * rjk + rkk * rkk) -- |cos(theta_j)|
	local tj = atan2(sij, cj)
	local ti, tk
	if cj > 1e-12 then
		ti = atan2(-s * rjk, rkk)
		tk = atan2(-s * R(i, j), R(i, i))
	else
		-- gimbal lock: only theta_i + theta_k is defined; put it all in theta_i
		ti = atan2(s * R(k, j), R(j, j))
		tk = 0
	end
	local out = { 0, 0, 0 }
	out[i], out[j], out[k] = ti, tj, tk
	return out[1], out[2], out[3]
end

local function lookAtCF(px, py, pz, fx, fy, fz, ux, uy, uz)
	local fl = sqrt(fx * fx + fy * fy + fz * fz)
	if fl < 1e-12 or fl ~= fl then
		return cf(px, py, pz, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	fx, fy, fz = fx / fl, fy / fl, fz / fl
	-- right = forward x up
	local rx, ry, rz = fy * uz - fz * uy, fz * ux - fx * uz, fx * uy - fy * ux
	local rl = sqrt(rx * rx + ry * ry + rz * rz)
	if rl < 1e-6 then
		-- looking along the up vector: Roblox switches the up vector to the X axis
		ux, uy, uz = 1, 0, 0
		rx, ry, rz = fy * uz - fz * uy, fz * ux - fx * uz, fx * uy - fy * ux
		rl = sqrt(rx * rx + ry * ry + rz * rz)
		if rl < 1e-6 then
			ux, uy, uz = 0, 0, 1
			rx, ry, rz = fy * uz - fz * uy, fz * ux - fx * uz, fx * uy - fy * ux
			rl = sqrt(rx * rx + ry * ry + rz * rz)
		end
	end
	rx, ry, rz = rx / rl, ry / rl, rz / rl
	-- up = right x forward
	local vx, vy, vz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
	-- columns: right, up, back (= -forward)
	return cf(px, py, pz, rx, vx, -fx, ry, vy, -fy, rz, vz, -fz)
end

CF.__index = function(c, k)
	local g = CFget[k]
	if g then
		return g(c)
	end
	local m = CFm[k]
	if m then
		return m
	end
	member("CFrame", k)
	return nil
end
CF.__newindex = readOnly

function CFget.X(c)
	return c[1]
end
function CFget.Y(c)
	return c[2]
end
function CFget.Z(c)
	return c[3]
end
CFget.x, CFget.y, CFget.z = CFget.X, CFget.Y, CFget.Z
function CFget.Position(c)
	return setmetatable({ X = c[1], Y = c[2], Z = c[3] }, V3)
end
CFget.p = CFget.Position
function CFget.Rotation(c)
	return cf(0, 0, 0, c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
end
function CFget.LookVector(c)
	return setmetatable({ X = -c[6], Y = -c[9], Z = -c[12] }, V3)
end
CFget.lookVector = CFget.LookVector
function CFget.RightVector(c)
	return setmetatable({ X = c[4], Y = c[7], Z = c[10] }, V3)
end
CFget.rightVector = CFget.RightVector
CFget.XVector = CFget.RightVector
function CFget.UpVector(c)
	return setmetatable({ X = c[5], Y = c[8], Z = c[11] }, V3)
end
CFget.upVector = CFget.UpVector
CFget.YVector = CFget.UpVector
function CFget.ZVector(c)
	return setmetatable({ X = c[6], Y = c[9], Z = c[12] }, V3)
end

local function checkCF(v, i, fname)
	if getmetatable(v) ~= CF then
		argError(i, fname, "CFrame", v, 4)
	end
	return v
end

CF.__mul = function(a, b)
	if getmetatable(a) == CF then
		local mb = getmetatable(b)
		if mb == CF then
			return cfMul(a, b)
		elseif mb == V3 then
			local bx, by, bz = b.X, b.Y, b.Z
			return setmetatable({ X = a[4] * bx + a[5] * by + a[6] * bz + a[1], Y = a[7] * bx + a[8] * by + a[9] * bz + a[2], Z = a[10] * bx + a[11] * by + a[12] * bz + a[3] }, V3)
		end
	end
	arithError("mul", a, b)
	return nil
end
CF.__add = function(a, b)
	if getmetatable(a) == CF and getmetatable(b) == V3 then
		return cf(a[1] + b.X, a[2] + b.Y, a[3] + b.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
	end
	arithError("add", a, b)
	return nil
end
CF.__sub = function(a, b)
	if getmetatable(a) == CF and getmetatable(b) == V3 then
		return cf(a[1] - b.X, a[2] - b.Y, a[3] - b.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
	end
	arithError("sub", a, b)
	return nil
end
CF.__eq = function(a, b)
	if getmetatable(a) ~= CF or getmetatable(b) ~= CF then
		return false
	end
	for i = 1, 12 do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end
CF.__tostring = function(c)
	local parts = table.create(12)
	for i = 1, 12 do
		parts[i] = fmtn(c[i])
	end
	return table.concat(parts, ", ")
end

function CFm.Inverse(c)
	return cfInverse(c)
end
CFm.inverse = CFm.Inverse
function CFm.GetComponents(c)
	return c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]
end
CFm.components = CFm.GetComponents

local function mapVariadic(fname, check, fn, c, ...)
	local n = select("#", ...)
	if n == 1 then
		return fn(c, check((...), 1, fname))
	end
	local out = table.create(n)
	for i = 1, n do
		out[i] = fn(c, check((select(i, ...)), i, fname))
	end
	return table.unpack(out, 1, n)
end

local function toWorld(c, o)
	return cfMul(c, o)
end
local function toObject(c, o)
	return cfMul(cfInverse(c), o)
end
local function pointToWorld(c, v)
	local x, y, z = v.X, v.Y, v.Z
	return setmetatable({ X = c[4] * x + c[5] * y + c[6] * z + c[1], Y = c[7] * x + c[8] * y + c[9] * z + c[2], Z = c[10] * x + c[11] * y + c[12] * z + c[3] }, V3)
end
local function pointToObject(c, v)
	local x, y, z = v.X - c[1], v.Y - c[2], v.Z - c[3]
	return setmetatable({ X = c[4] * x + c[7] * y + c[10] * z, Y = c[5] * x + c[8] * y + c[11] * z, Z = c[6] * x + c[9] * y + c[12] * z }, V3)
end
local function vectorToWorld(c, v)
	local x, y, z = v.X, v.Y, v.Z
	return setmetatable({ X = c[4] * x + c[5] * y + c[6] * z, Y = c[7] * x + c[8] * y + c[9] * z, Z = c[10] * x + c[11] * y + c[12] * z }, V3)
end
local function vectorToObject(c, v)
	local x, y, z = v.X, v.Y, v.Z
	return setmetatable({ X = c[4] * x + c[7] * y + c[10] * z, Y = c[5] * x + c[8] * y + c[11] * z, Z = c[6] * x + c[9] * y + c[12] * z }, V3)
end

function CFm.ToWorldSpace(c, ...)
	return mapVariadic("ToWorldSpace", checkCF, toWorld, c, ...)
end
CFm.toWorldSpace = CFm.ToWorldSpace
function CFm.ToObjectSpace(c, ...)
	return mapVariadic("ToObjectSpace", checkCF, toObject, c, ...)
end
CFm.toObjectSpace = CFm.ToObjectSpace
function CFm.PointToWorldSpace(c, ...)
	return mapVariadic("PointToWorldSpace", checkV3, pointToWorld, c, ...)
end
CFm.pointToWorldSpace = CFm.PointToWorldSpace
function CFm.PointToObjectSpace(c, ...)
	return mapVariadic("PointToObjectSpace", checkV3, pointToObject, c, ...)
end
CFm.pointToObjectSpace = CFm.PointToObjectSpace
function CFm.VectorToWorldSpace(c, ...)
	return mapVariadic("VectorToWorldSpace", checkV3, vectorToWorld, c, ...)
end
CFm.vectorToWorldSpace = CFm.VectorToWorldSpace
function CFm.VectorToObjectSpace(c, ...)
	return mapVariadic("VectorToObjectSpace", checkV3, vectorToObject, c, ...)
end
CFm.vectorToObjectSpace = CFm.VectorToObjectSpace

function CFm.Lerp(a, b, t)
	checkCF(b, 1, "Lerp")
	t = checknum(t, 2, "Lerp")
	local ax, ay, az, aw = cfToQuat(a)
	local bx, by, bz, bw = cfToQuat(b)
	local d = ax * bx + ay * by + az * bz + aw * bw
	if d < 0 then
		bx, by, bz, bw, d = -bx, -by, -bz, -bw, -d
	end
	local k0, k1
	if d > 0.9999 then
		k0, k1 = 1 - t, t
	else
		local th = acos(d)
		local st = sin(th)
		k0, k1 = sin((1 - t) * th) / st, sin(t * th) / st
	end
	return quatToCF(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, ax * k0 + bx * k1, ay * k0 + by * k1, az * k0 + bz * k1, aw * k0 + bw * k1)
end
CFm.lerp = CFm.Lerp

-- Orthonormalize: quaternion extraction with glam's branch order (what Lune does; Roblox's exact algorithm
-- is not documented), normalised back to a rotation matrix. Identical for already-orthonormal input.
function CFm.Orthonormalize(c)
	-- glam naming: mCR = column C, row R
	local m00, m01, m02 = c[4], c[7], c[10]
	local m10, m11, m12 = c[5], c[8], c[11]
	local m20, m21, m22 = c[6], c[9], c[12]
	local x, y, z, w
	if m22 <= 0 then
		local dif10, omm22 = m11 - m00, 1 - m22
		if dif10 <= 0 then
			local f = omm22 - dif10
			local inv = 0.5 / sqrt(f)
			x, y, z, w = f * inv, (m01 + m10) * inv, (m02 + m20) * inv, (m12 - m21) * inv
		else
			local f = omm22 + dif10
			local inv = 0.5 / sqrt(f)
			x, y, z, w = (m01 + m10) * inv, f * inv, (m12 + m21) * inv, (m20 - m02) * inv
		end
	else
		local sum10, opm22 = m11 + m00, 1 + m22
		if sum10 <= 0 then
			local f = opm22 - sum10
			local inv = 0.5 / sqrt(f)
			x, y, z, w = (m02 + m20) * inv, (m12 + m21) * inv, f * inv, (m01 - m10) * inv
		else
			local f = opm22 + sum10
			local inv = 0.5 / sqrt(f)
			x, y, z, w = (m12 - m21) * inv, (m20 - m02) * inv, (m01 - m10) * inv, f * inv
		end
	end
	return quatToCF(c[1], c[2], c[3], x, y, z, w)
end

function CFm.ToAxisAngle(c)
	local qx, qy, qz, qw = cfToQuat(c)
	if qw > 1 then
		qw = 1
	end
	local angle = 2 * acos(qw)
	local s = sqrt(qx * qx + qy * qy + qz * qz)
	if s < 1e-12 then
		return setmetatable({ X = 1, Y = 0, Z = 0 }, V3), 0
	end
	return setmetatable({ X = qx / s, Y = qy / s, Z = qz / s }, V3), angle
end
CFm.toAxisAngle = CFm.ToAxisAngle

function CFm.ToEulerAnglesXYZ(c)
	return toEulerOrdered(c, "XYZ")
end
CFm.toEulerAnglesXYZ = CFm.ToEulerAnglesXYZ
function CFm.ToEulerAnglesYXZ(c)
	return toEulerOrdered(c, "YXZ")
end
CFm.toEulerAnglesYXZ = CFm.ToEulerAnglesYXZ
CFm.ToOrientation = CFm.ToEulerAnglesYXZ
CFm.toOrientation = CFm.ToEulerAnglesYXZ
function CFm.ToEulerAngles(c, order)
	return toEulerOrdered(c, orderName(order, 1, "ToEulerAngles"))
end

function CFm.FuzzyEq(a, b, eps)
	checkCF(b, 1, "FuzzyEq")
	eps = eps or 1e-5
	for i = 1, 12 do
		if abs(a[i] - b[i]) > eps then
			return false
		end
	end
	return true
end

function CFm.AngleBetween(a, b)
	checkCF(b, 1, "AngleBetween")
	-- trace of Ra^T * Rb
	local tr = 0
	for i = 4, 12 do
		tr += a[i] * b[i]
	end
	local x = (tr - 1) / 2
	if x > 1 then
		x = 1
	elseif x < -1 then
		x = -1
	end
	return acos(x)
end

local IDENTITY = table.freeze(cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1))

local CFrame = {}
function CFrame.new(...)
	local n = select("#", ...)
	if n == 0 then
		return cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	local a, b, c = ...
	if n == 3 and type(a) == "number" and type(b) == "number" and type(c) == "number" then
		return cf(a, b, c, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	local ma = getmetatable(a)
	if ma == V3 then
		if n == 1 then
			return cf(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		elseif n == 2 then
			checkV3(b, 2, "new")
			return lookAtCF(a.X, a.Y, a.Z, b.X - a.X, b.Y - a.Y, b.Z - a.Z, 0, 1, 0)
		end
		error("Invalid number of arguments: " .. n, 2)
	end
	if n == 3 then
		return cf(optnum(a, 1, "new"), optnum(b, 2, "new"), optnum(c, 3, "new"), 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif n == 7 then
		local x, y, z, qx, qy, qz, qw = ...
		return quatToCF(optnum(x, 1, "new"), optnum(y, 2, "new"), optnum(z, 3, "new"), optnum(qx, 4, "new"), optnum(qy, 5, "new"), optnum(qz, 6, "new"), optnum(qw, 7, "new"))
	elseif n == 12 then
		local t = { ... }
		for i = 1, 12 do
			t[i] = optnum(t[i], i, "new")
		end
		return setmetatable(t, CF)
	end
	error("Invalid number of arguments: " .. n, 2)
	return nil
end
CFrame.identity = IDENTITY
function CFrame.lookAt(at, target, up)
	checkV3(at, 1, "lookAt")
	checkV3(target, 2, "lookAt")
	local ux, uy, uz = 0, 1, 0
	if up ~= nil then
		checkV3(up, 3, "lookAt")
		ux, uy, uz = up.X, up.Y, up.Z
	end
	return lookAtCF(at.X, at.Y, at.Z, target.X - at.X, target.Y - at.Y, target.Z - at.Z, ux, uy, uz)
end
function CFrame.lookAlong(at, dir, up)
	checkV3(at, 1, "lookAlong")
	checkV3(dir, 2, "lookAlong")
	local ux, uy, uz = 0, 1, 0
	if up ~= nil then
		checkV3(up, 3, "lookAlong")
		ux, uy, uz = up.X, up.Y, up.Z
	end
	return lookAtCF(at.X, at.Y, at.Z, dir.X, dir.Y, dir.Z, ux, uy, uz)
end
function CFrame.fromEulerAnglesXYZ(rx, ry, rz)
	return eulerXYZ(optnum(rx, 1, "fromEulerAnglesXYZ"), optnum(ry, 2, "fromEulerAnglesXYZ"), optnum(rz, 3, "fromEulerAnglesXYZ"))
end
CFrame.Angles = CFrame.fromEulerAnglesXYZ
function CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	return eulerYXZ(optnum(rx, 1, "fromEulerAnglesYXZ"), optnum(ry, 2, "fromEulerAnglesYXZ"), optnum(rz, 3, "fromEulerAnglesYXZ"))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromEulerAngles(rx, ry, rz, order)
	return eulerOrdered(optnum(rx, 1, "fromEulerAngles"), optnum(ry, 2, "fromEulerAngles"), optnum(rz, 3, "fromEulerAngles"), orderName(order, 4, "fromEulerAngles"))
end
function CFrame.fromAxisAngle(axis, angle)
	checkV3(axis, 1, "fromAxisAngle")
	return axisAngleCF(0, 0, 0, axis.X, axis.Y, axis.Z, optnum(angle, 2, "fromAxisAngle"))
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	checkV3(pos, 1, "fromMatrix")
	checkV3(vx, 2, "fromMatrix")
	checkV3(vy, 3, "fromMatrix")
	if vz == nil then
		local ax, ay, az, bx, by, bz = vx.X, vx.Y, vx.Z, vy.X, vy.Y, vy.Z
		local cx, cy, cz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
		local l = sqrt(cx * cx + cy * cy + cz * cz)
		vz = setmetatable({ X = cx / l, Y = cy / l, Z = cz / l }, V3)
	else
		checkV3(vz, 4, "fromMatrix")
	end
	return cf(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end
function CFrame.fromRotationBetweenVectors(from, to)
	checkV3(from, 1, "fromRotationBetweenVectors")
	checkV3(to, 2, "fromRotationBetweenVectors")
	local fl, tl = from.Magnitude, to.Magnitude
	local fx, fy, fz = from.X / fl, from.Y / fl, from.Z / fl
	local tx, ty, tz = to.X / tl, to.Y / tl, to.Z / tl
	local d = fx * tx + fy * ty + fz * tz
	local cx, cy, cz = fy * tz - fz * ty, fz * tx - fx * tz, fx * ty - fy * tx
	if d < -0.999999 then
		-- opposite: rotate pi around any axis perpendicular to `from`
		local px, py, pz
		if abs(fx) < 0.9 then
			px, py, pz = 0, fz, -fy -- from x X
		else
			px, py, pz = -fz, 0, fx -- from x Y
		end
		return axisAngleCF(0, 0, 0, px, py, pz, pi)
	end
	return quatToCF(0, 0, 0, cx, cy, cz, 1 + d)
end
DT.CFrame = CFrame

---------------------------------------------------------------------------------------------------------
-- Color3
---------------------------------------------------------------------------------------------------------
local C3 = { __type = "Color3" }
local C3m = {}
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, C3)
end
DT.C3meta, DT.c3 = C3, c3

C3.__index = function(c, k)
	local m = C3m[k]
	if m then
		return m
	end
	if k == "r" then
		return c.R
	elseif k == "g" then
		return c.G
	elseif k == "b" then
		return c.B
	end
	member("Color3", k)
	return nil
end
C3.__newindex = readOnly
C3.__eq = function(a, b)
	return getmetatable(a) == C3 and getmetatable(b) == C3 and a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(c)
	return fmtn(c.R) .. ", " .. fmtn(c.G) .. ", " .. fmtn(c.B)
end

local function checkC3(v, i, fname)
	if getmetatable(v) ~= C3 then
		argError(i, fname, "Color3", v, 4)
	end
	return v
end

local function toHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx = math.max(r, g, b)
	local mn = math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d ~= 0 then
		if mx == r then
			h = (g - b) / d
			if g < b then
				h += 6
			end
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	local s = if mx == 0 then 0 else d / mx
	return h, s, mx
end

local function fromHSV(h, s, v)
	local hh = (h % 1) * 6
	if h ~= 0 and h % 1 == 0 then
		hh = 0 -- h = 1 is red, same as 0
	end
	local i = floor(hh)
	local f = hh - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	if i == 0 then
		return setmetatable({ R = v, G = t, B = p }, C3)
	elseif i == 1 then
		return setmetatable({ R = q, G = v, B = p }, C3)
	elseif i == 2 then
		return setmetatable({ R = p, G = v, B = t }, C3)
	elseif i == 3 then
		return setmetatable({ R = p, G = q, B = v }, C3)
	elseif i == 4 then
		return setmetatable({ R = t, G = p, B = v }, C3)
	end
	return setmetatable({ R = v, G = p, B = q }, C3)
end

function C3m.Lerp(a, b, t)
	checkC3(b, 1, "Lerp")
	t = checknum(t, 2, "Lerp")
	return setmetatable({ R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t }, C3)
end
C3m.lerp = C3m.Lerp
function C3m.ToHSV(c)
	return toHSV(c)
end
local function to255(x)
	if x ~= x then
		return 0
	end
	x = floor(x * 255 + 0.5)
	if x < 0 then
		return 0
	elseif x > 255 then
		return 255
	end
	return x
end
function C3m.ToHex(c)
	return sformat("%02X%02X%02X", to255(c.R), to255(c.G), to255(c.B))
end

local Color3 = {}
function Color3.new(r, g, b)
	if type(r) == "number" and type(g) == "number" and type(b) == "number" then
		return setmetatable({ R = r, G = g, B = b }, C3)
	end
	return setmetatable({ R = optnum(r, 1, "new"), G = optnum(g, 2, "new"), B = optnum(b, 3, "new") }, C3)
end
function Color3.fromRGB(r, g, b)
	if type(r) == "number" and type(g) == "number" and type(b) == "number" then
		return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, C3)
	end
	return setmetatable({ R = optnum(r, 1, "fromRGB") / 255, G = optnum(g, 2, "fromRGB") / 255, B = optnum(b, 3, "fromRGB") / 255 }, C3)
end
function Color3.fromHSV(h, s, v)
	return fromHSV(optnum(h, 1, "fromHSV"), optnum(s, 2, "fromHSV"), optnum(v, 3, "fromHSV"))
end
function Color3.toHSV(c)
	checkC3(c, 1, "toHSV")
	return toHSV(c)
end
function Color3.fromHex(hex)
	if type(hex) ~= "string" then
		argError(1, "fromHex", "string", hex)
	end
	local s = string.gsub(hex, "^#", "")
	if #s == 3 then
		s = string.gsub(s, "%x", "%0%0")
	end
	if #s ~= 6 or string.find(s, "[^%x]") then
		error("Unable to convert characters to hex value", 2)
	end
	return setmetatable({ R = tonumber(string.sub(s, 1, 2), 16) / 255, G = tonumber(string.sub(s, 3, 4), 16) / 255, B = tonumber(string.sub(s, 5, 6), 16) / 255 }, C3)
end
DT.Color3 = Color3

---------------------------------------------------------------------------------------------------------
-- UDim / UDim2
---------------------------------------------------------------------------------------------------------
local UD = { __type = "UDim" }
local function udim(s, o)
	return setmetatable({ Scale = s, Offset = o }, UD)
end
UD.__index = function(_, k)
	member("UDim", k)
end
UD.__newindex = readOnly
UD.__add = function(a, b)
	if getmetatable(a) == UD and getmetatable(b) == UD then
		return udim(a.Scale + b.Scale, a.Offset + b.Offset)
	end
	arithError("add", a, b)
	return nil
end
UD.__sub = function(a, b)
	if getmetatable(a) == UD and getmetatable(b) == UD then
		return udim(a.Scale - b.Scale, a.Offset - b.Offset)
	end
	arithError("sub", a, b)
	return nil
end
UD.__unm = function(a)
	return udim(-a.Scale, -a.Offset)
end
UD.__eq = function(a, b)
	return getmetatable(a) == UD and getmetatable(b) == UD and a.Scale == b.Scale and a.Offset == b.Offset
end
UD.__tostring = function(u)
	return fmtn(u.Scale) .. ", " .. fmtn(u.Offset)
end
DT.UDmeta = UD

local UDim = {
	new = function(s, o)
		if type(s) == "number" and type(o) == "number" then
			return setmetatable({ Scale = s, Offset = if o >= 0 then floor(o) else -floor(-o) }, UD)
		end
		return udim(optnum(s, 1, "new"), trunc(optnum(o, 2, "new")))
	end,
}
DT.UDim = UDim

local UD2 = { __type = "UDim2" }
local UD2m = {}
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = setmetatable({ Scale = xs, Offset = xo }, UD), Y = setmetatable({ Scale = ys, Offset = yo }, UD) }, UD2)
end
DT.UD2meta = UD2
UD2.__index = function(u, k)
	local m = UD2m[k]
	if m then
		return m
	end
	if k == "Width" then
		return u.X
	elseif k == "Height" then
		return u.Y
	end
	member("UDim2", k)
	return nil
end
UD2.__newindex = readOnly
UD2.__add = function(a, b)
	if getmetatable(a) == UD2 and getmetatable(b) == UD2 then
		local ax, ay, bx, by = a.X, a.Y, b.X, b.Y
		return udim2(ax.Scale + bx.Scale, ax.Offset + bx.Offset, ay.Scale + by.Scale, ay.Offset + by.Offset)
	end
	arithError("add", a, b)
	return nil
end
UD2.__sub = function(a, b)
	if getmetatable(a) == UD2 and getmetatable(b) == UD2 then
		local ax, ay, bx, by = a.X, a.Y, b.X, b.Y
		return udim2(ax.Scale - bx.Scale, ax.Offset - bx.Offset, ay.Scale - by.Scale, ay.Offset - by.Offset)
	end
	arithError("sub", a, b)
	return nil
end
UD2.__unm = function(a)
	return udim2(-a.X.Scale, -a.X.Offset, -a.Y.Scale, -a.Y.Offset)
end
UD2.__eq = function(a, b)
	if getmetatable(a) ~= UD2 or getmetatable(b) ~= UD2 then
		return false
	end
	local ax, ay, bx, by = a.X, a.Y, b.X, b.Y
	return ax.Scale == bx.Scale and ax.Offset == bx.Offset and ay.Scale == by.Scale and ay.Offset == by.Offset
end
UD2.__tostring = function(u)
	return "{" .. tostring(u.X) .. "}, {" .. tostring(u.Y) .. "}"
end

function UD2m.Lerp(a, b, t)
	if getmetatable(b) ~= UD2 then
		argError(1, "Lerp", "UDim2", b)
	end
	t = checknum(t, 2, "Lerp")
	local ax, ay, bx, by = a.X, a.Y, b.X, b.Y
	return udim2(ax.Scale + (bx.Scale - ax.Scale) * t, roundAway(ax.Offset + (bx.Offset - ax.Offset) * t), ay.Scale + (by.Scale - ay.Scale) * t, roundAway(ay.Offset + (by.Offset - ay.Offset) * t))
end
UD2m.lerp = UD2m.Lerp

local UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	if getmetatable(xs) == UD then
		if getmetatable(xo) ~= UD then
			argError(2, "new", "UDim", xo)
		end
		return setmetatable({ X = xs, Y = xo }, UD2)
	end
	if type(xs) == "number" and type(xo) == "number" and type(ys) == "number" and type(yo) == "number" then
		-- fast path (hot in UI code): offsets truncated toward zero
		return setmetatable({
			X = setmetatable({ Scale = xs, Offset = if xo >= 0 then floor(xo) else -floor(-xo) }, UD),
			Y = setmetatable({ Scale = ys, Offset = if yo >= 0 then floor(yo) else -floor(-yo) }, UD),
		}, UD2)
	end
	return udim2(optnum(xs, 1, "new"), trunc(optnum(xo, 2, "new")), optnum(ys, 3, "new"), trunc(optnum(yo, 4, "new")))
end
function UDim2.fromScale(x, y)
	if type(x) == "number" and type(y) == "number" then
		return setmetatable({ X = setmetatable({ Scale = x, Offset = 0 }, UD), Y = setmetatable({ Scale = y, Offset = 0 }, UD) }, UD2)
	end
	return udim2(optnum(x, 1, "fromScale"), 0, optnum(y, 2, "fromScale"), 0)
end
function UDim2.fromOffset(x, y)
	if type(x) == "number" and type(y) == "number" then
		return setmetatable({
			X = setmetatable({ Scale = 0, Offset = if x >= 0 then floor(x) else -floor(-x) }, UD),
			Y = setmetatable({ Scale = 0, Offset = if y >= 0 then floor(y) else -floor(-y) }, UD),
		}, UD2)
	end
	return udim2(0, trunc(optnum(x, 1, "fromOffset")), 0, trunc(optnum(y, 2, "fromOffset")))
end
DT.UDim2 = UDim2

---------------------------------------------------------------------------------------------------------
-- Rect
---------------------------------------------------------------------------------------------------------
local RC = { __type = "Rect" }
local function rect(x0, y0, x1, y1)
	if x1 < x0 then
		x0, x1 = x1, x0
	end
	if y1 < y0 then
		y0, y1 = y1, y0
	end
	return setmetatable({ Min = setmetatable({ X = x0, Y = y0 }, V2), Max = setmetatable({ X = x1, Y = y1 }, V2) }, RC)
end
RC.__index = function(r, k)
	if k == "Width" then
		return r.Max.X - r.Min.X
	elseif k == "Height" then
		return r.Max.Y - r.Min.Y
	end
	member("Rect", k)
	return nil
end
RC.__newindex = readOnly
RC.__eq = function(a, b)
	return getmetatable(a) == RC and getmetatable(b) == RC and a.Min == b.Min and a.Max == b.Max
end
RC.__tostring = function(r)
	return tostring(r.Min) .. ", " .. tostring(r.Max)
end
DT.Rect = {
	new = function(a, b, c, d)
		if getmetatable(a) == V2 then
			checkV2(b, 2, "new")
			return rect(a.X, a.Y, b.X, b.Y)
		end
		return rect(optnum(a, 1, "new"), optnum(b, 2, "new"), optnum(c, 3, "new"), optnum(d, 4, "new"))
	end,
}

---------------------------------------------------------------------------------------------------------
-- NumberRange
---------------------------------------------------------------------------------------------------------
local NR = { __type = "NumberRange" }
NR.__index = function(_, k)
	member("NumberRange", k)
end
NR.__newindex = readOnly
NR.__eq = function(a, b)
	return getmetatable(a) == NR and getmetatable(b) == NR and a.Min == b.Min and a.Max == b.Max
end
NR.__tostring = function(r)
	return fmtn(r.Min) .. " " .. fmtn(r.Max) .. " "
end
DT.NumberRange = {
	new = function(mn, mx)
		mn = checknum(mn, 1, "new")
		mx = if mx == nil then mn else checknum(mx, 2, "new")
		if mx < mn then
			mn, mx = mx, mn
		end
		return setmetatable({ Min = mn, Max = mx }, NR)
	end,
}

---------------------------------------------------------------------------------------------------------
-- NumberSequence / ColorSequence (+ keypoints)
---------------------------------------------------------------------------------------------------------
local NSK = { __type = "NumberSequenceKeypoint" }
NSK.__index = function(_, k)
	member("NumberSequenceKeypoint", k)
end
NSK.__newindex = readOnly
NSK.__eq = function(a, b)
	return getmetatable(a) == NSK and getmetatable(b) == NSK and a.Time == b.Time and a.Value == b.Value and a.Envelope == b.Envelope
end
NSK.__tostring = function(k)
	return fmtn(k.Time) .. " " .. fmtn(k.Value) .. " " .. fmtn(k.Envelope)
end
local function nsk(t, v, e)
	return setmetatable({ Time = t, Value = v, Envelope = e }, NSK)
end
DT.NumberSequenceKeypoint = {
	new = function(t, v, e)
		return nsk(checknum(t, 1, "new"), checknum(v, 2, "new"), optnum(e, 3, "new"))
	end,
}

local CSK = { __type = "ColorSequenceKeypoint" }
CSK.__index = function(_, k)
	member("ColorSequenceKeypoint", k)
end
CSK.__newindex = readOnly
CSK.__eq = function(a, b)
	return getmetatable(a) == CSK and getmetatable(b) == CSK and a.Time == b.Time and a.Value == b.Value
end
CSK.__tostring = function(k)
	return fmtn(k.Time) .. " " .. fmtn(k.Value.R) .. " " .. fmtn(k.Value.G) .. " " .. fmtn(k.Value.B) .. " 0"
end
local function csk(t, c)
	return setmetatable({ Time = t, Value = c }, CSK)
end
DT.ColorSequenceKeypoint = {
	new = function(t, c)
		return csk(checknum(t, 1, "new"), checkC3(c, 2, "new"))
	end,
}

local function validateKeypoints(kps, meta, typeName, kpName)
	if type(kps) ~= "table" or getmetatable(kps) ~= nil then
		argError(1, "new", "table", kps, 4)
	end
	local n = #kps
	if n < 2 then
		error(typeName .. ": requires at least 2 keypoints", 3)
	elseif n > 20 then
		error(typeName .. ": table is too long.", 3)
	end
	local out = table.create(n)
	local last = -huge
	for i = 1, n do
		local k = kps[i]
		if getmetatable(k) ~= meta then
			error(sformat("%s: expected %s at index %d, got %s", typeName, kpName, i, dtypeof(k)), 3)
		end
		if k.Time < last then
			error(typeName .. ": all keypoints must be ordered by time", 3)
		end
		last = k.Time
		out[i] = k
	end
	if abs(out[1].Time) > 1e-4 then
		error(typeName .. " time of first keypoint must be 0", 3)
	end
	if abs(out[n].Time - 1) > 1e-4 then
		error(typeName .. " time of last keypoint must be 1", 3)
	end
	return out
end

local NS = { __type = "NumberSequence" }
NS.__index = function(s, k)
	if k == "Keypoints" then
		return table.clone(rawget(s, "_kp"))
	end
	member("NumberSequence", k)
	return nil
end
NS.__newindex = readOnly
NS.__eq = function(a, b)
	if getmetatable(a) ~= NS or getmetatable(b) ~= NS then
		return false
	end
	local ka, kb = rawget(a, "_kp"), rawget(b, "_kp")
	if #ka ~= #kb then
		return false
	end
	for i = 1, #ka do
		if ka[i] ~= kb[i] then
			return false
		end
	end
	return true
end
NS.__tostring = function(s)
	local parts = {}
	for i, k in rawget(s, "_kp") do
		parts[i] = tostring(k) .. " "
	end
	return table.concat(parts)
end
DT.NumberSequence = {
	new = function(a, b)
		if type(a) == "number" then
			local b2 = if b == nil then a else checknum(b, 2, "new")
			return setmetatable({ _kp = { nsk(0, a, 0), nsk(1, b2, 0) } }, NS)
		end
		return setmetatable({ _kp = validateKeypoints(a, NSK, "NumberSequence", "NumberSequenceKeypoint") }, NS)
	end,
}

local CS = { __type = "ColorSequence" }
CS.__index = function(s, k)
	if k == "Keypoints" then
		return table.clone(rawget(s, "_kp"))
	end
	member("ColorSequence", k)
	return nil
end
CS.__newindex = readOnly
CS.__eq = function(a, b)
	if getmetatable(a) ~= CS or getmetatable(b) ~= CS then
		return false
	end
	local ka, kb = rawget(a, "_kp"), rawget(b, "_kp")
	if #ka ~= #kb then
		return false
	end
	for i = 1, #ka do
		if ka[i] ~= kb[i] then
			return false
		end
	end
	return true
end
CS.__tostring = function(s)
	local parts = {}
	for i, k in rawget(s, "_kp") do
		parts[i] = tostring(k) .. " "
	end
	return table.concat(parts)
end
DT.ColorSequence = {
	new = function(a, b)
		if getmetatable(a) == C3 then
			local b2 = if b == nil then a else checkC3(b, 2, "new")
			return setmetatable({ _kp = { csk(0, a), csk(1, b2) } }, CS)
		end
		return setmetatable({ _kp = validateKeypoints(a, CSK, "ColorSequence", "ColorSequenceKeypoint") }, CS)
	end,
}

-- sample helpers for the renderer / tween code
function DT.sampleNumberSequence(s, t: number): number
	local kp = rawget(s, "_kp")
	if t <= kp[1].Time then
		return kp[1].Value
	end
	for i = 2, #kp do
		local k1 = kp[i]
		if t <= k1.Time then
			local k0 = kp[i - 1]
			local span = k1.Time - k0.Time
			local a = if span > 0 then (t - k0.Time) / span else 0
			return k0.Value + (k1.Value - k0.Value) * a
		end
	end
	return kp[#kp].Value
end
function DT.sampleColorSequence(s, t: number)
	local kp = rawget(s, "_kp")
	if t <= kp[1].Time then
		return kp[1].Value
	end
	for i = 2, #kp do
		local k1 = kp[i]
		if t <= k1.Time then
			local k0 = kp[i - 1]
			local span = k1.Time - k0.Time
			local a = if span > 0 then (t - k0.Time) / span else 0
			return C3m.Lerp(k0.Value, k1.Value, a)
		end
	end
	return kp[#kp].Value
end

---------------------------------------------------------------------------------------------------------
-- BrickColor (full palette from gen/enums.json)
---------------------------------------------------------------------------------------------------------
local BC = { __type = "BrickColor" }
BC.__index = function(b, k)
	if k == "r" then
		return b.Color.R
	elseif k == "g" then
		return b.Color.G
	elseif k == "b" then
		return b.Color.B
	end
	member("BrickColor", k)
	return nil
end
BC.__newindex = readOnly
BC.__eq = function(a, b)
	return getmetatable(a) == BC and getmetatable(b) == BC and a.Number == b.Number
end
BC.__tostring = function(b)
	return b.Name
end

local bcList, bcByNumber, bcByName, bcPalette
local DEFAULT_BRICK = 194
local function bcLoad()
	if bcList then
		return
	end
	bcList, bcByNumber, bcByName = {}, {}, {}
	for i, e in Enums.section("brickColors") or {} do
		local b = table.freeze(setmetatable({ Number = e[1], Name = e[2], Color = table.freeze(setmetatable({ R = e[3] / 255, G = e[4] / 255, B = e[5] / 255 }, C3)), _rgb8 = { e[3], e[4], e[5] } }, BC))
		bcList[i] = b
		bcByNumber[e[1]] = b
		if bcByName[e[2]] == nil then
			bcByName[e[2]] = b
		end
	end
	bcPalette = Enums.section("palette") or {}
end
-- Roblox/Lune rule: input channels floored to 0..255, Manhattan distance to the 8-bit palette colours,
-- first minimum in BrickColor-number order wins
local function bcNearest(r, g, b)
	bcLoad()
	local function to8(x)
		x = floor(x * 255)
		if x ~= x or x < 0 then
			return 0
		elseif x > 255 then
			return 255
		end
		return x
	end
	local r8, g8, b8 = to8(r), to8(g), to8(b)
	local best, bd = nil, huge
	for _, e in bcList do
		local c8 = rawget(e, "_rgb8")
		local dist = abs(c8[1] - r8) + abs(c8[2] - g8) + abs(c8[3] - b8)
		if dist < bd then
			best, bd = e, dist
		end
	end
	return best
end
local function bcDefault()
	bcLoad()
	return bcByNumber[DEFAULT_BRICK] or bcList[1]
end

local BrickColor = {}
function BrickColor.new(a, g, b)
	bcLoad()
	local ta = type(a)
	if a == nil then
		return bcDefault()
	elseif ta == "number" and g == nil then
		return bcByNumber[a] or bcDefault()
	elseif ta == "number" then
		return bcNearest(a, checknum(g, 2, "new"), checknum(b, 3, "new"))
	elseif ta == "string" then
		return bcByName[a] or bcDefault()
	elseif getmetatable(a) == C3 then
		return bcNearest(a.R, a.G, a.B)
	elseif getmetatable(a) == BC then
		return a
	end
	argError(1, "new", "number, string or Color3", a)
	return nil
end
function BrickColor.palette(i)
	bcLoad()
	i = checknum(i, 1, "palette")
	local n = bcPalette[i + 1]
	if n == nil then
		error("Invalid palette index " .. tostring(i), 2)
	end
	return bcByNumber[n]
end
function BrickColor.random()
	bcLoad()
	return bcList[math.random(1, #bcList)]
end
function BrickColor.White()
	return BrickColor.new(1)
end
function BrickColor.Gray()
	return BrickColor.new(194)
end
function BrickColor.DarkGray()
	return BrickColor.new(199)
end
function BrickColor.Black()
	return BrickColor.new(26)
end
function BrickColor.Red()
	return BrickColor.new(21)
end
function BrickColor.Yellow()
	return BrickColor.new(24)
end
function BrickColor.Green()
	return BrickColor.new(28)
end
function BrickColor.Blue()
	return BrickColor.new(23)
end
DT.BrickColor = BrickColor

---------------------------------------------------------------------------------------------------------
-- TweenInfo
---------------------------------------------------------------------------------------------------------
local TI = { __type = "TweenInfo" }
TI.__index = function(_, k)
	member("TweenInfo", k)
end
TI.__newindex = readOnly
TI.__eq = function(a, b)
	return getmetatable(a) == TI
		and getmetatable(b) == TI
		and a.Time == b.Time
		and a.EasingStyle == b.EasingStyle
		and a.EasingDirection == b.EasingDirection
		and a.RepeatCount == b.RepeatCount
		and a.Reverses == b.Reverses
		and a.DelayTime == b.DelayTime
end
TI.__tostring = function(t)
	return sformat(
		"Time:%s DelayTime:%s RepeatCount:%s Reverses:%s EasingDirection:%s EasingStyle:%s",
		fmtn(t.Time),
		fmtn(t.DelayTime),
		fmtn(t.RepeatCount),
		if t.Reverses then "True" else "False",
		t.EasingDirection.Name,
		t.EasingStyle.Name
	)
end
DT.TweenInfo = {
	new = function(time, style, direction, repeatCount, reverses, delayTime)
		return setmetatable({
			Time = optnum(time, 1, "new", 1),
			EasingStyle = if style == nil then Enum.EasingStyle.Quad else enumArg("EasingStyle", style, 2, "new"),
			EasingDirection = if direction == nil then Enum.EasingDirection.Out else enumArg("EasingDirection", direction, 3, "new"),
			RepeatCount = trunc(optnum(repeatCount, 4, "new", 0)),
			Reverses = reverses == true,
			DelayTime = optnum(delayTime, 6, "new", 0),
		}, TI)
	end,
}

---------------------------------------------------------------------------------------------------------
-- Ray
---------------------------------------------------------------------------------------------------------
local RY = { __type = "Ray" }
local RYm = {}
local function ray(o, d)
	return setmetatable({ Origin = o, Direction = d }, RY)
end
RY.__index = function(r, k)
	local m = RYm[k]
	if m then
		return m
	end
	if k == "Unit" or k == "unit" then
		return ray(r.Origin, r.Direction.Unit)
	end
	member("Ray", k)
	return nil
end
RY.__newindex = readOnly
RY.__eq = function(a, b)
	return getmetatable(a) == RY and getmetatable(b) == RY and a.Origin == b.Origin and a.Direction == b.Direction
end
RY.__tostring = function(r)
	return "{" .. tostring(r.Origin) .. "}, {" .. tostring(r.Direction) .. "}"
end
function RYm.ClosestPoint(r, p)
	checkV3(p, 1, "ClosestPoint")
	local o, d = r.Origin, r.Direction
	local l = d.Magnitude
	if l == 0 then
		return o
	end
	local ux, uy, uz = d.X / l, d.Y / l, d.Z / l
	local t = (p.X - o.X) * ux + (p.Y - o.Y) * uy + (p.Z - o.Z) * uz
	if t < 0 then
		t = 0
	end
	return setmetatable({ X = o.X + ux * t, Y = o.Y + uy * t, Z = o.Z + uz * t }, V3)
end
function RYm.Distance(r, p)
	return (RYm.ClosestPoint(r, p) - p).Magnitude
end
DT.Ray = {
	new = function(o, d)
		return ray(checkV3(o, 1, "new"), checkV3(d, 2, "new"))
	end,
}

---------------------------------------------------------------------------------------------------------
-- RaycastParams / OverlapParams / RaycastResult
---------------------------------------------------------------------------------------------------------
-- hook: how to recognise an Instance (instance.luau may replace it)
DT.isInstance = function(v)
	return dtypeof(v) == "Instance"
end

local function paramsClass(typeName, defaults, validators)
	local meta = { __type = typeName }
	local methods = {}
	function methods.AddToFilter(p, v)
		local list = rawget(p, "_filter")
		if DT.isInstance(v) then
			table.insert(list, v)
		elseif type(v) == "table" and getmetatable(v) == nil then
			for _, x in v do
				if not DT.isInstance(x) then
					error("AddToFilter: array of Instances expected", 2)
				end
				table.insert(list, x)
			end
		else
			argError(1, "AddToFilter", "Instance or array of Instances", v)
		end
	end
	meta.__index = function(p, k)
		if k == "FilterDescendantsInstances" then
			return table.clone(rawget(p, "_filter"))
		end
		local m = methods[k]
		if m then
			return m
		end
		local f = rawget(p, "_f")
		local v = f[k]
		if v == nil and defaults[k] == nil then
			member(typeName, k)
		end
		return v
	end
	meta.__newindex = function(p, k, v)
		if k == "FilterDescendantsInstances" then
			if type(v) ~= "table" or getmetatable(v) ~= nil then
				error("Unable to assign property FilterDescendantsInstances. Array expected, got " .. dtypeof(v), 2)
			end
			local list = {}
			for _, x in v do
				if not DT.isInstance(x) then
					error("Unable to assign property FilterDescendantsInstances. Array of Instances expected", 2)
				end
				table.insert(list, x)
			end
			rawset(p, "_filter", list)
			return
		end
		local def = defaults[k]
		if def == nil then
			member(typeName, k)
		end
		local val = validators[k]
		if val then
			local ok, cv = val(v)
			if not ok then
				error(sformat("Unable to assign property %s. %s expected, got %s", k, cv, dtypeof(v)), 2)
			end
			v = cv
		end
		rawget(p, "_f")[k] = v
	end
	meta.__tostring = function()
		return typeName .. "{}"
	end
	local lib = {}
	function lib.new(init)
		local f = {}
		for k, v in defaults do
			if v == "<FilterType>" then
				f[k] = Enum.RaycastFilterType.Exclude
			else
				f[k] = v
			end
		end
		local p = setmetatable({ _filter = {}, _f = f }, meta)
		if type(init) == "table" then
			for k, v in init do
				p[k] = v
			end
		end
		return p
	end
	return lib, meta
end

local function vBool(v)
	if type(v) == "boolean" then
		return true, v
	end
	return false, "boolean"
end
local function vString(v)
	if type(v) == "string" then
		return true, v
	end
	return false, "string"
end
local function vFilter(v)
	local it = Enums.coerce("RaycastFilterType", v)
	if it then
		return true, it
	end
	return false, "EnumItem"
end
local function vInt(v)
	if type(v) == "number" then
		return true, trunc(v)
	end
	return false, "number"
end

local RaycastParamsMeta, OverlapParamsMeta
DT.RaycastParams, RaycastParamsMeta = paramsClass("RaycastParams", {
	FilterType = "<FilterType>",
	IgnoreWater = false,
	CollisionGroup = "Default",
	RespectCanCollide = false,
	BruteForceAllSlow = false,
}, { FilterType = vFilter, IgnoreWater = vBool, CollisionGroup = vString, RespectCanCollide = vBool, BruteForceAllSlow = vBool })
DT.OverlapParams, OverlapParamsMeta = paramsClass("OverlapParams", {
	FilterType = "<FilterType>",
	MaxParts = 0,
	CollisionGroup = "Default",
	RespectCanCollide = false,
	BruteForceAllSlow = false,
}, { FilterType = vFilter, MaxParts = vInt, CollisionGroup = vString, RespectCanCollide = vBool, BruteForceAllSlow = vBool })

-- engine access without copying: array of filter instances, and the "include" flag
function DT.paramsFilter(p)
	if p == nil then
		return {}, false
	end
	local f = rawget(p, "_f")
	return rawget(p, "_filter"), f.FilterType == Enum.RaycastFilterType.Include
end

local RR = { __type = "RaycastResult" }
RR.__index = function(_, k)
	member("RaycastResult", k)
end
RR.__newindex = readOnly
RR.__tostring = function(r)
	return "RaycastResult{" .. tostring(r.Instance) .. " @ " .. tostring(r.Position) .. "; " .. tostring(r.Normal) .. "; " .. tostring(r.Material) .. "}"
end
-- engine constructor (not a Roblox global)
function DT.makeRaycastResult(instance, position, normal, material, distance)
	return setmetatable({
		Instance = instance,
		Position = position,
		Normal = normal,
		Material = material or Enum.Material.Plastic,
		Distance = distance or 0,
	}, RR)
end

---------------------------------------------------------------------------------------------------------
-- Region3 / Region3int16
---------------------------------------------------------------------------------------------------------
local R3 = { __type = "Region3" }
local R3m = {}
local function region3(mn, mx)
	return setmetatable({ _min = mn, _max = mx }, R3)
end
R3.__index = function(r, k)
	local m = R3m[k]
	if m then
		return m
	end
	local mn, mx = rawget(r, "_min"), rawget(r, "_max")
	if k == "CFrame" then
		return cf((mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z) / 2, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif k == "Size" then
		return mx - mn
	end
	member("Region3", k)
	return nil
end
R3.__newindex = readOnly
R3.__eq = function(a, b)
	return getmetatable(a) == R3 and getmetatable(b) == R3 and rawget(a, "_min") == rawget(b, "_min") and rawget(a, "_max") == rawget(b, "_max")
end
R3.__tostring = function(r)
	return tostring(r.CFrame) .. "; " .. tostring(r.Size)
end
function R3m.ExpandToGrid(r, res)
	res = checknum(res, 1, "ExpandToGrid")
	local mn, mx = rawget(r, "_min"), rawget(r, "_max")
	return region3(
		setmetatable({ X = floor(mn.X / res) * res, Y = floor(mn.Y / res) * res, Z = floor(mn.Z / res) * res }, V3),
		setmetatable({ X = ceil(mx.X / res) * res, Y = ceil(mx.Y / res) * res, Z = ceil(mx.Z / res) * res }, V3)
	)
end
-- engine access: min and max corners
function DT.regionBounds(r)
	return rawget(r, "_min"), rawget(r, "_max")
end
DT.Region3 = {
	new = function(mn, mx)
		checkV3(mn, 1, "new")
		checkV3(mx, 2, "new")
		return region3(mn, mx)
	end,
}

local R3i = { __type = "Region3int16" }
R3i.__index = function(_, k)
	member("Region3int16", k)
end
R3i.__newindex = readOnly
R3i.__tostring = function(r)
	return tostring(r.Min) .. "; " .. tostring(r.Max)
end
DT.Region3int16 = {
	new = function(mn, mx)
		if getmetatable(mn) ~= V3i then
			argError(1, "new", "Vector3int16", mn)
		end
		if getmetatable(mx) ~= V3i then
			argError(2, "new", "Vector3int16", mx)
		end
		return setmetatable({ Min = mn, Max = mx }, R3i)
	end,
}

---------------------------------------------------------------------------------------------------------
-- Random (xoshiro128**; deterministic per seed, not bit-identical to Roblox's PCG32)
---------------------------------------------------------------------------------------------------------
local RN = { __type = "Random" }
local RNm = {}
local band, bxor, lshift, rshift, lrotate = bit32.band, bit32.bxor, bit32.lshift, bit32.rshift, bit32.lrotate

local function mul32(a, b) -- (a * b) mod 2^32 for 32-bit a, b
	local ah, al = rshift(a, 16), band(a, 0xFFFF)
	return band(al * b + lshift(band(ah * b, 0xFFFF), 16), 0xFFFFFFFF)
end

local function nextU32(r)
	local s0, s1, s2, s3 = r._s0, r._s1, r._s2, r._s3
	local result = mul32(lrotate(mul32(s1, 5), 7), 9)
	local t = lshift(s1, 9)
	s2 = bxor(s2, s0)
	s3 = bxor(s3, s1)
	s1 = bxor(s1, s2)
	s0 = bxor(s0, s3)
	s2 = bxor(s2, t)
	s3 = lrotate(s3, 11)
	r._s0, r._s1, r._s2, r._s3 = s0, s1, s2, s3
	return result
end

local function next01(r) -- [0, 1) with 53 bits
	local a = rshift(nextU32(r), 5) -- 27 bits
	local b = rshift(nextU32(r), 6) -- 26 bits
	return (a * 67108864 + b) / 9007199254740992
end

local function splitmix32(x)
	x = band(x + 0x9E3779B9, 0xFFFFFFFF)
	local z = x
	z = mul32(bxor(z, rshift(z, 16)), 0x85EBCA6B)
	z = mul32(bxor(z, rshift(z, 13)), 0xC2B2AE35)
	return x, bxor(z, rshift(z, 16))
end

local seedCounter = 0
local function newRandom(seed)
	local lo, hi
	if seed == nil then
		seedCounter += 1
		local t = os.clock() * 1e6 + (os.time() % 1e6) * 1e3 + seedCounter * 7919
		lo, hi = floor(t) % 4294967296, floor(t / 4294967296) % 4294967296
	else
		seed = trunc(seed)
		lo = seed % 4294967296
		hi = floor(seed / 4294967296) % 4294967296
	end
	local x = bxor(lo, mul32(hi, 0x27D4EB2F))
	local s0, s1, s2, s3
	x, s0 = splitmix32(x)
	x, s1 = splitmix32(x)
	x, s2 = splitmix32(x)
	x, s3 = splitmix32(x)
	if s0 == 0 and s1 == 0 and s2 == 0 and s3 == 0 then
		s0 = 1
	end
	return setmetatable({ _s0 = s0, _s1 = s1, _s2 = s2, _s3 = s3 }, RN)
end

RN.__index = function(_, k)
	local m = RNm[k]
	if m then
		return m
	end
	member("Random", k)
	return nil
end
RN.__newindex = readOnly
RN.__tostring = function()
	return "Random"
end

local function checkRandom(r, fname)
	if getmetatable(r) ~= RN then
		error("Expected ':' not '.' calling member function " .. fname, 3)
	end
end

function RNm.NextNumber(r, mn, mx)
	checkRandom(r, "NextNumber")
	local u = next01(r)
	if mn == nil and mx == nil then
		return u
	end
	mn = optnum(mn, 1, "NextNumber")
	mx = optnum(mx, 2, "NextNumber", 1)
	return mn + (mx - mn) * u
end
function RNm.NextInteger(r, mn, mx)
	checkRandom(r, "NextInteger")
	mn = floor(checknum(mn, 1, "NextInteger"))
	mx = floor(checknum(mx, 2, "NextInteger"))
	if mx < mn then
		error("invalid argument #2 to 'NextInteger' (interval is empty)", 2)
	end
	return mn + floor(next01(r) * (mx - mn + 1))
end
function RNm.NextUnitVector(r)
	checkRandom(r, "NextUnitVector")
	local z = next01(r) * 2 - 1
	local t = next01(r) * 2 * pi
	local s = sqrt(1 - z * z)
	return setmetatable({ X = s * cos(t), Y = s * sin(t), Z = z }, V3)
end
function RNm.Shuffle(r, tb)
	checkRandom(r, "Shuffle")
	if type(tb) ~= "table" then
		argError(1, "Shuffle", "table", tb)
	end
	local n = #tb
	for k in tb do
		if type(k) ~= "number" or k < 1 or k > n or k ~= floor(k) then
			error("invalid argument #1 to 'Shuffle' (table must be an array)", 2)
		end
	end
	for i = n, 2, -1 do
		local j = 1 + floor(next01(r) * i)
		tb[i], tb[j] = tb[j], tb[i]
	end
end
function RNm.Clone(r)
	checkRandom(r, "Clone")
	return setmetatable({ _s0 = r._s0, _s1 = r._s1, _s2 = r._s2, _s3 = r._s3 }, RN)
end

DT.Random = {
	new = function(seed)
		if seed ~= nil then
			seed = checknum(seed, 1, "new")
		end
		return newRandom(seed)
	end,
}

---------------------------------------------------------------------------------------------------------
-- DateTime (civil-calendar arithmetic; local time = UTC + DT.timezoneOffsetMinutes)
---------------------------------------------------------------------------------------------------------
DT.timezoneOffsetMinutes = 0
local clockBaseMs = os.time() * 1000 - os.clock() * 1000
-- hook: current Unix time in milliseconds (the host may replace it, e.g. with JS Date.now)
DT.nowMillis = function()
	return floor(clockBaseMs + os.clock() * 1000)
end

local function daysFromCivil(y, m, d)
	y = if m <= 2 then y - 1 else y
	local era = floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
local function civilFromDays(z)
	z += 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	return (if m <= 2 then y + 1 else y), m, d
end

local function msFromParts(y, mo, d, h, mi, s, ms)
	-- normalise months so that daysFromCivil sees 1..12
	local m0 = mo - 1
	y += floor(m0 / 12)
	mo = m0 % 12 + 1
	return ((daysFromCivil(y, mo, 1) + (d - 1)) * 86400 + h * 3600 + mi * 60 + s) * 1000 + ms
end
local function partsFromMs(ms)
	local days = floor(ms / 86400000)
	local rem = ms - days * 86400000
	local y, m, d = civilFromDays(days)
	local h = floor(rem / 3600000)
	rem -= h * 3600000
	local mi = floor(rem / 60000)
	rem -= mi * 60000
	local s = floor(rem / 1000)
	return { Year = y, Month = m, Day = d, Hour = h, Minute = mi, Second = s, Millisecond = rem - s * 1000 }
end

local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

local function pad(n, w)
	return sformat("%0" .. w .. "d", n)
end

local function formatParts(p, ms, fmt)
	local weekday = (floor(ms / 86400000) + 4) % 7 + 1 -- 1970-01-01 was a Thursday
	local h12 = p.Hour % 12
	if h12 == 0 then
		h12 = 12
	end
	local tokens = {
		YYYY = function()
			return pad(p.Year, 4)
		end,
		YY = function()
			return pad(p.Year % 100, 2)
		end,
		MMMM = function()
			return MONTHS[p.Month]
		end,
		MMM = function()
			return string.sub(MONTHS[p.Month], 1, 3)
		end,
		MM = function()
			return pad(p.Month, 2)
		end,
		M = function()
			return tostring(p.Month)
		end,
		DD = function()
			return pad(p.Day, 2)
		end,
		D = function()
			return tostring(p.Day)
		end,
		dddd = function()
			return WEEKDAYS[weekday]
		end,
		ddd = function()
			return string.sub(WEEKDAYS[weekday], 1, 3)
		end,
		HH = function()
			return pad(p.Hour, 2)
		end,
		H = function()
			return tostring(p.Hour)
		end,
		hh = function()
			return pad(h12, 2)
		end,
		h = function()
			return tostring(h12)
		end,
		mm = function()
			return pad(p.Minute, 2)
		end,
		m = function()
			return tostring(p.Minute)
		end,
		ss = function()
			return pad(p.Second, 2)
		end,
		s = function()
			return tostring(p.Second)
		end,
		SSS = function()
			return pad(p.Millisecond, 3)
		end,
		A = function()
			return if p.Hour < 12 then "AM" else "PM"
		end,
		a = function()
			return if p.Hour < 12 then "am" else "pm"
		end,
		LT = function()
			return h12 .. ":" .. pad(p.Minute, 2) .. " " .. (if p.Hour < 12 then "AM" else "PM")
		end,
		L = function()
			return pad(p.Month, 2) .. "/" .. pad(p.Day, 2) .. "/" .. pad(p.Year, 4)
		end,
	}
	local order = { "YYYY", "YY", "MMMM", "MMM", "MM", "M", "DD", "D", "dddd", "ddd", "HH", "H", "hh", "h", "mm", "m", "ss", "s", "SSS", "A", "a", "LT", "L" }
	local out, i, n = {}, 1, #fmt
	while i <= n do
		local ch = string.sub(fmt, i, i)
		if ch == "[" then
			local j = string.find(fmt, "]", i + 1, true)
			if j then
				table.insert(out, string.sub(fmt, i + 1, j - 1))
				i = j + 1
				continue
			end
		end
		local matched = false
		for _, tok in order do
			if string.sub(fmt, i, i + #tok - 1) == tok then
				table.insert(out, tokens[tok]())
				i += #tok
				matched = true
				break
			end
		end
		if not matched then
			table.insert(out, ch)
			i += 1
		end
	end
	return table.concat(out)
end

local DTM = { __type = "DateTime" }
local DTm = {}
local function dt(ms)
	return setmetatable({ _ms = floor(ms) }, DTM)
end
DTM.__index = function(d, k)
	if k == "UnixTimestamp" then
		return floor(rawget(d, "_ms") / 1000)
	elseif k == "UnixTimestampMillis" then
		return rawget(d, "_ms")
	end
	local m = DTm[k]
	if m then
		return m
	end
	member("DateTime", k)
	return nil
end
DTM.__newindex = readOnly
DTM.__eq = function(a, b)
	return getmetatable(a) == DTM and getmetatable(b) == DTM and rawget(a, "_ms") == rawget(b, "_ms")
end
DTM.__lt = function(a, b)
	return rawget(a, "_ms") < rawget(b, "_ms")
end
DTM.__le = function(a, b)
	return rawget(a, "_ms") <= rawget(b, "_ms")
end
DTM.__tostring = function(d)
	return DTm.ToIsoDate(d)
end
function DTm.ToUniversalTime(d)
	return partsFromMs(rawget(d, "_ms"))
end
function DTm.ToLocalTime(d)
	return partsFromMs(rawget(d, "_ms") + DT.timezoneOffsetMinutes * 60000)
end
function DTm.ToIsoDate(d)
	local ms = rawget(d, "_ms")
	local p = partsFromMs(ms)
	local base = sformat("%04d-%02d-%02dT%02d:%02d:%02d", p.Year, p.Month, p.Day, p.Hour, p.Minute, p.Second)
	if p.Millisecond ~= 0 then
		base ..= sformat(".%03d", p.Millisecond)
	end
	return base .. "Z"
end
function DTm.FormatUniversalTime(d, fmt, _locale)
	local ms = rawget(d, "_ms")
	return formatParts(partsFromMs(ms), ms, tostring(fmt))
end
function DTm.FormatLocalTime(d, fmt, _locale)
	local ms = rawget(d, "_ms") + DT.timezoneOffsetMinutes * 60000
	return formatParts(partsFromMs(ms), ms, tostring(fmt))
end

local DateTime = {}
function DateTime.now()
	return dt(DT.nowMillis())
end
function DateTime.fromUnixTimestamp(s)
	return dt(checknum(s, 1, "fromUnixTimestamp") * 1000)
end
function DateTime.fromUnixTimestampMillis(ms)
	return dt(checknum(ms, 1, "fromUnixTimestampMillis"))
end
function DateTime.fromUniversalTime(y, mo, d, h, mi, s, ms)
	return dt(msFromParts(optnum(y, 1, "fromUniversalTime", 1970), optnum(mo, 2, "fromUniversalTime", 1), optnum(d, 3, "fromUniversalTime", 1), optnum(h, 4, "fromUniversalTime"), optnum(mi, 5, "fromUniversalTime"), optnum(s, 6, "fromUniversalTime"), optnum(ms, 7, "fromUniversalTime")))
end
function DateTime.fromLocalTime(y, mo, d, h, mi, s, ms)
	local u = DateTime.fromUniversalTime(y, mo, d, h, mi, s, ms)
	return dt(rawget(u, "_ms") - DT.timezoneOffsetMinutes * 60000)
end
function DateTime.fromIsoDate(str)
	if type(str) ~= "string" then
		return nil
	end
	local y, mo, d, rest = string.match(str, "^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
	if not y then
		return nil
	end
	local h, mi, s, frac, tz = 0, 0, 0, 0, 0
	if rest ~= "" then
		local hh, mm, tail = string.match(rest, "^[Tt ](%d%d):(%d%d)(.*)$")
		if not hh then
			return nil
		end
		h, mi = tonumber(hh), tonumber(mm)
		local ss, tail2 = string.match(tail, "^:(%d%d)(.*)$")
		if ss then
			s = tonumber(ss)
			tail = tail2
		end
		local fr, tail3 = string.match(tail, "^[%.,](%d+)(.*)$")
		if fr then
			frac = floor(tonumber("0." .. fr) * 1000 + 0.5)
			tail = tail3
		end
		if tail == "Z" or tail == "z" or tail == "" then
			tz = 0
		else
			local sign, th, tm = string.match(tail, "^([%+%-])(%d%d):?(%d%d)$")
			if not sign then
				return nil
			end
			tz = (tonumber(th) * 60 + tonumber(tm)) * (if sign == "-" then -1 else 1)
		end
	end
	return dt(msFromParts(tonumber(y), tonumber(mo), tonumber(d), h, mi, s, frac) - tz * 60000)
end
DT.DateTime = DateTime

---------------------------------------------------------------------------------------------------------
-- Font (mutable, like Roblox: Weight/Style/Bold/Family can be set)
---------------------------------------------------------------------------------------------------------
local FT = { __type = "Font" }
local function font(family, weight, style)
	return setmetatable({ _family = family, _weight = weight, _style = style }, FT)
end
FT.__index = function(f, k)
	if k == "Family" then
		return rawget(f, "_family")
	elseif k == "Weight" then
		return rawget(f, "_weight")
	elseif k == "Style" then
		return rawget(f, "_style")
	elseif k == "Bold" then
		return rawget(f, "_weight").Value >= 600
	end
	member("Font", k)
	return nil
end
FT.__newindex = function(f, k, v)
	if k == "Family" then
		if type(v) ~= "string" then
			error("Unable to assign property Family. string expected, got " .. dtypeof(v), 2)
		end
		rawset(f, "_family", v)
	elseif k == "Weight" then
		local it = Enums.coerce("FontWeight", v)
		if not it then
			error("Unable to assign property Weight. EnumItem expected, got " .. dtypeof(v), 2)
		end
		rawset(f, "_weight", it)
	elseif k == "Style" then
		local it = Enums.coerce("FontStyle", v)
		if not it then
			error("Unable to assign property Style. EnumItem expected, got " .. dtypeof(v), 2)
		end
		rawset(f, "_style", it)
	elseif k == "Bold" then
		rawset(f, "_weight", if v then Enum.FontWeight.Bold else Enum.FontWeight.Regular)
	else
		member("Font", k)
	end
end
FT.__eq = function(a, b)
	return getmetatable(a) == FT
		and getmetatable(b) == FT
		and rawget(a, "_family") == rawget(b, "_family")
		and rawget(a, "_weight") == rawget(b, "_weight")
		and rawget(a, "_style") == rawget(b, "_style")
end
FT.__tostring = function(f)
	return sformat("Font { Family = %s, Weight = %s, Style = %s }", rawget(f, "_family"), rawget(f, "_weight").Name, rawget(f, "_style").Name)
end

local function fontArgs(weight, style, fname)
	local w = if weight == nil then Enum.FontWeight.Regular else enumArg("FontWeight", weight, 2, fname)
	local s = if style == nil then Enum.FontStyle.Normal else enumArg("FontStyle", style, 3, fname)
	return w, s
end

local Font = {}
function Font.new(family, weight, style)
	if type(family) ~= "string" then
		argError(1, "new", "string", family)
	end
	local w, s = fontArgs(weight, style, "new")
	return font(family, w, s)
end
function Font.fromName(name, weight, style)
	if type(name) ~= "string" then
		argError(1, "fromName", "string", name)
	end
	local w, s = fontArgs(weight, style, "fromName")
	return font("rbxasset://fonts/families/" .. name .. ".json", w, s)
end
function Font.fromId(id, weight, style)
	local n = checknum(id, 1, "fromId")
	local w, s = fontArgs(weight, style, "fromId")
	return font("rbxassetid://" .. fmtn(n), w, s)
end
function Font.fromEnum(value)
	local it = enumArg("Font", value, 1, "fromEnum")
	local e = (Enums.section("fonts") or {})[it.Name]
	if e == nil then
		error("Font.fromEnum: " .. tostring(it) .. " has no font face", 2)
	end
	return font(e[1], Enum.FontWeight[e[2]], Enum.FontStyle[e[3]])
end
DT.Font = Font

-- Font face -> the closest Enum.Font (for renderers / legacy Font property), or nil
function DT.fontToEnum(f)
	local fam, w, st = rawget(f, "_family"), rawget(f, "_weight"), rawget(f, "_style")
	local best, bestScore = nil, huge
	for name, e in Enums.section("fonts") or {} do
		if e[1] == fam then
			local ew = Enum.FontWeight[e[2]]
			local score = abs(ew.Value - w.Value) + (if e[3] == st.Name then 0 else 1000)
			if score < bestScore then
				best, bestScore = name, score
			end
		end
	end
	return best and Enum.Font[best]
end

---------------------------------------------------------------------------------------------------------
-- PhysicalProperties
---------------------------------------------------------------------------------------------------------
local PP = { __type = "PhysicalProperties" }
PP.__index = function(_, k)
	member("PhysicalProperties", k)
end
PP.__newindex = readOnly
PP.__eq = function(a, b)
	return getmetatable(a) == PP
		and getmetatable(b) == PP
		and a.Density == b.Density
		and a.Friction == b.Friction
		and a.Elasticity == b.Elasticity
		and a.FrictionWeight == b.FrictionWeight
		and a.ElasticityWeight == b.ElasticityWeight
end
PP.__tostring = function(p)
	return fmtn(p.Density) .. ", " .. fmtn(p.Friction) .. ", " .. fmtn(p.Elasticity) .. ", " .. fmtn(p.FrictionWeight) .. ", " .. fmtn(p.ElasticityWeight)
end
local function pp(d, f, e, fw, ew)
	return setmetatable({ Density = d, Friction = f, Elasticity = e, FrictionWeight = fw, ElasticityWeight = ew }, PP)
end
DT.PhysicalProperties = {
	new = function(a, f, e, fw, ew)
		if Enums.isEnumItem(a) then
			local it = enumArg("Material", a, 1, "new")
			local m = (Enums.section("materials") or {})[it.Name]
			if not m then
				return pp(0.7, 0.3, 0.5, 1, 1)
			end
			return pp(m[1], m[2], m[3], m[4], m[5])
		end
		return pp(checknum(a, 1, "new"), checknum(f, 2, "new"), checknum(e, 3, "new"), optnum(fw, 4, "new", 1), optnum(ew, 5, "new", 1))
	end,
}

---------------------------------------------------------------------------------------------------------
-- Axes / Faces
---------------------------------------------------------------------------------------------------------
local AX = { __type = "Axes" }
AX.__index = function(a, k)
	if k == "Top" or k == "Bottom" then
		return a.Y
	elseif k == "Left" or k == "Right" then
		return a.X
	elseif k == "Front" or k == "Back" then
		return a.Z
	end
	member("Axes", k)
	return nil
end
AX.__newindex = readOnly
AX.__eq = function(a, b)
	return getmetatable(a) == AX and getmetatable(b) == AX and a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
AX.__tostring = function(a)
	local t = {}
	if a.X then
		table.insert(t, "X")
	end
	if a.Y then
		table.insert(t, "Y")
	end
	if a.Z then
		table.insert(t, "Z")
	end
	return table.concat(t, ", ")
end
local NORMAL_AXIS = { Right = "X", Left = "X", Top = "Y", Bottom = "Y", Back = "Z", Front = "Z" }
DT.Axes = {
	new = function(...)
		local r = { X = false, Y = false, Z = false }
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if Enums.isEnumItem(v) and v.EnumType == Enum.Axis then
				r[v.Name] = true
			elseif Enums.isEnumItem(v) and v.EnumType == Enum.NormalId then
				r[NORMAL_AXIS[v.Name]] = true
			else
				argError(i, "new", "Enum.Axis or Enum.NormalId", v)
			end
		end
		return setmetatable(r, AX)
	end,
}

local FC = { __type = "Faces" }
FC.__index = function(_, k)
	member("Faces", k)
end
FC.__newindex = readOnly
FC.__eq = function(a, b)
	if getmetatable(a) ~= FC or getmetatable(b) ~= FC then
		return false
	end
	for _, n in { "Top", "Bottom", "Left", "Right", "Back", "Front" } do
		if a[n] ~= b[n] then
			return false
		end
	end
	return true
end
FC.__tostring = function(f)
	local t = {}
	for _, n in { "Right", "Top", "Back", "Left", "Bottom", "Front" } do
		if f[n] then
			table.insert(t, n)
		end
	end
	return table.concat(t, ", ")
end
DT.Faces = {
	new = function(...)
		local r = { Top = false, Bottom = false, Left = false, Right = false, Back = false, Front = false }
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if Enums.isEnumItem(v) and v.EnumType == Enum.NormalId then
				r[v.Name] = true
			else
				argError(i, "new", "Enum.NormalId", v)
			end
		end
		return setmetatable(r, FC)
	end,
}

---------------------------------------------------------------------------------------------------------
-- type() replacement, value helpers, tagged encode/decode
---------------------------------------------------------------------------------------------------------
-- Roblox `type`: "vector" for Vector3, "userdata" for any other engine object (table with a __type
-- metatable, including Instances/EnumItems), otherwise the plain Luau type.
function DT.type(v): string
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" and type(rawget(mt, "__type")) == "string" then
			return if mt == V3 then "vector" else "userdata"
		end
	end
	return t
end

-- true when typeof(v) == typeName
function DT.is(v, typeName: string): boolean
	return dtypeof(v) == typeName
end

-- copy for value-semantics on assignment: mutable datatypes (Font, RaycastParams, OverlapParams) are
-- copied, everything else is immutable and returned as-is.
function DT.valueCopy(v)
	local mt = type(v) == "table" and getmetatable(v)
	if mt == FT then
		return font(rawget(v, "_family"), rawget(v, "_weight"), rawget(v, "_style"))
	elseif mt == RaycastParamsMeta or mt == OverlapParamsMeta then
		local c = setmetatable({ _filter = table.clone(rawget(v, "_filter")), _f = table.clone(rawget(v, "_f")) }, mt)
		return c
	end
	return v
end

-- Tagged JSON-friendly representation {t = typeof, v = ...}; primitives pass through untouched.
--   Vector3 [x,y,z]  Vector2 [x,y]  Vector3int16/Vector2int16 likewise  CFrame [x,y,z,r00..r22] (12)
--   Color3 [r,g,b] (0..1)  UDim [s,o]  UDim2 [xs,xo,ys,yo]  Rect [x0,y0,x1,y1]  NumberRange [min,max]
--   NumberSequence [[t,v,e],...]  ColorSequence [[t,r,g,b],...]  BrickColor number
--   EnumItem ["Material","Plastic"] (decode also accepts "Enum.Material.Plastic", ["Material",256],
--   {enum=..,name=..}/{enum=..,value=..})  Font [family, weightName, styleName]
--   PhysicalProperties [d,f,e,fw,ew]  Ray [ox,oy,oz,dx,dy,dz]  Region3 [minx,miny,minz,maxx,maxy,maxz]
--   Axes/Faces [names...]  DateTime ms  NumberSequenceKeypoint [t,v,e]  ColorSequenceKeypoint [t,r,g,b]
local encoders = {
	Vector3 = function(v)
		return { v.X, v.Y, v.Z }
	end,
	Vector2 = function(v)
		return { v.X, v.Y }
	end,
	Vector3int16 = function(v)
		return { v.X, v.Y, v.Z }
	end,
	Vector2int16 = function(v)
		return { v.X, v.Y }
	end,
	CFrame = function(c)
		return { c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12] }
	end,
	Color3 = function(c)
		return { c.R, c.G, c.B }
	end,
	UDim = function(u)
		return { u.Scale, u.Offset }
	end,
	UDim2 = function(u)
		return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
	end,
	Rect = function(r)
		return { r.Min.X, r.Min.Y, r.Max.X, r.Max.Y }
	end,
	NumberRange = function(r)
		return { r.Min, r.Max }
	end,
	NumberSequenceKeypoint = function(k)
		return { k.Time, k.Value, k.Envelope }
	end,
	ColorSequenceKeypoint = function(k)
		return { k.Time, k.Value.R, k.Value.G, k.Value.B }
	end,
	NumberSequence = function(s)
		local out = {}
		for i, k in rawget(s, "_kp") do
			out[i] = { k.Time, k.Value, k.Envelope }
		end
		return out
	end,
	ColorSequence = function(s)
		local out = {}
		for i, k in rawget(s, "_kp") do
			out[i] = { k.Time, k.Value.R, k.Value.G, k.Value.B }
		end
		return out
	end,
	BrickColor = function(b)
		return b.Number
	end,
	EnumItem = function(e)
		return { Enums.nameOf(e.EnumType), e.Name }
	end,
	Font = function(f)
		return { rawget(f, "_family"), rawget(f, "_weight").Name, rawget(f, "_style").Name }
	end,
	PhysicalProperties = function(p)
		return { p.Density, p.Friction, p.Elasticity, p.FrictionWeight, p.ElasticityWeight }
	end,
	Ray = function(r)
		return { r.Origin.X, r.Origin.Y, r.Origin.Z, r.Direction.X, r.Direction.Y, r.Direction.Z }
	end,
	Region3 = function(r)
		local mn, mx = rawget(r, "_min"), rawget(r, "_max")
		return { mn.X, mn.Y, mn.Z, mx.X, mx.Y, mx.Z }
	end,
	Axes = function(a)
		local t = {}
		for _, n in { "X", "Y", "Z" } do
			if a[n] then
				table.insert(t, n)
			end
		end
		return t
	end,
	Faces = function(f)
		local t = {}
		for _, n in { "Right", "Top", "Back", "Left", "Bottom", "Front" } do
			if f[n] then
				table.insert(t, n)
			end
		end
		return t
	end,
	DateTime = function(d)
		return rawget(d, "_ms")
	end,
}

function DT.encode(v)
	local tn = dtypeof(v)
	local enc = encoders[tn]
	if enc then
		return { t = tn, v = enc(v) }
	end
	return v
end

local function decodeEnumItem(v)
	if type(v) == "string" then
		return Enums.parse(v)
	elseif type(v) == "table" then
		local e = v[1] or v.enum or v.e
		local key = v[2]
		if key == nil then
			key = v.name or v.n or v.value or v.v
		end
		if type(e) == "string" and key ~= nil then
			e = string.gsub(e, "^Enum%.", "")
			return Enums.item(e, key)
		end
	end
	return nil
end

local decoders = {
	Vector3 = function(v)
		return setmetatable({ X = v[1] or 0, Y = v[2] or 0, Z = v[3] or 0 }, V3)
	end,
	Vector2 = function(v)
		return setmetatable({ X = v[1] or 0, Y = v[2] or 0 }, V2)
	end,
	Vector3int16 = function(v)
		return v3i(v[1] or 0, v[2] or 0, v[3] or 0)
	end,
	Vector2int16 = function(v)
		return v2i(v[1] or 0, v[2] or 0)
	end,
	CFrame = function(v)
		if #v == 3 then
			return cf(v[1], v[2], v[3], 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		return cf(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12])
	end,
	Color3 = function(v)
		return setmetatable({ R = v[1] or 0, G = v[2] or 0, B = v[3] or 0 }, C3)
	end,
	Color3uint8 = function(v)
		return setmetatable({ R = (v[1] or 0) / 255, G = (v[2] or 0) / 255, B = (v[3] or 0) / 255 }, C3)
	end,
	UDim = function(v)
		return udim(v[1] or 0, trunc(v[2] or 0))
	end,
	UDim2 = function(v)
		return udim2(v[1] or 0, trunc(v[2] or 0), v[3] or 0, trunc(v[4] or 0))
	end,
	Rect = function(v)
		return rect(v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0)
	end,
	NumberRange = function(v)
		return setmetatable({ Min = v[1] or 0, Max = v[2] or v[1] or 0 }, NR)
	end,
	NumberSequenceKeypoint = function(v)
		return nsk(v[1] or 0, v[2] or 0, v[3] or 0)
	end,
	ColorSequenceKeypoint = function(v)
		return csk(v[1] or 0, setmetatable({ R = v[2] or 0, G = v[3] or 0, B = v[4] or 0 }, C3))
	end,
	NumberSequence = function(v)
		local kp = {}
		for i, k in v do
			kp[i] = nsk(k[1], k[2], k[3] or 0)
		end
		return setmetatable({ _kp = kp }, NS)
	end,
	ColorSequence = function(v)
		local kp = {}
		for i, k in v do
			kp[i] = csk(k[1], setmetatable({ R = k[2], G = k[3], B = k[4] }, C3))
		end
		return setmetatable({ _kp = kp }, CS)
	end,
	BrickColor = function(v)
		return BrickColor.new(v)
	end,
	EnumItem = decodeEnumItem,
	Enum = decodeEnumItem,
	Font = function(v)
		return font(v[1] or v.family or "", Enums.coerce("FontWeight", v[2] or v.weight) or Enum.FontWeight.Regular, Enums.coerce("FontStyle", v[3] or v.style) or Enum.FontStyle.Normal)
	end,
	PhysicalProperties = function(v)
		return pp(v[1], v[2], v[3], v[4] or 1, v[5] or 1)
	end,
	Ray = function(v)
		return ray(setmetatable({ X = v[1], Y = v[2], Z = v[3] }, V3), setmetatable({ X = v[4], Y = v[5], Z = v[6] }, V3))
	end,
	Region3 = function(v)
		return region3(setmetatable({ X = v[1], Y = v[2], Z = v[3] }, V3), setmetatable({ X = v[4], Y = v[5], Z = v[6] }, V3))
	end,
	Axes = function(v)
		local r = { X = false, Y = false, Z = false }
		for _, n in v do
			local ax = NORMAL_AXIS[n] or n
			r[ax] = true
		end
		return setmetatable(r, AX)
	end,
	Faces = function(v)
		local r = { Top = false, Bottom = false, Left = false, Right = false, Back = false, Front = false }
		for _, n in v do
			r[n] = true
		end
		return setmetatable(r, FC)
	end,
	DateTime = function(v)
		return dt(v)
	end,
}

-- decode one tagged value; untagged values pass through. Unknown tags return nil + reason.
function DT.decode(x)
	if type(x) ~= "table" or getmetatable(x) ~= nil then
		return x
	end
	local tn = x.t
	if type(tn) ~= "string" then
		return x
	end
	local dec = decoders[tn]
	if not dec then
		return nil, "unknown datatype tag " .. tn
	end
	return dec(x.v)
end

---------------------------------------------------------------------------------------------------------
-- Content (2024+): Content.none / fromUri / fromAssetId / fromObject; SourceType, Uri, Object
-- (the game probes Content.fromObject behind pcall for EditableImage textures; no pixels exist here)
---------------------------------------------------------------------------------------------------------
local CT = { __type = "Content" }
CT.__index = function(c, k)
	local raw = rawget(c, "_d")
	if k == "SourceType" then
		return Enum.ContentSourceType[raw.kind]
	elseif k == "Uri" then
		return raw.uri
	elseif k == "Object" then
		return raw.obj
	end
	member("Content", k)
	return nil
end
CT.__newindex = readOnly
CT.__eq = function(a, b)
	if getmetatable(a) ~= CT or getmetatable(b) ~= CT then
		return false
	end
	local x, y = rawget(a, "_d"), rawget(b, "_d")
	return x.kind == y.kind and x.uri == y.uri and x.obj == y.obj
end
CT.__tostring = function(c)
	local d = rawget(c, "_d")
	if d.kind == "Uri" then
		return d.uri
	elseif d.kind == "Object" then
		return "Content(Object)"
	end
	return "Content(None)"
end
local function newContent(kind, uri, obj)
	return setmetatable({ _d = { kind = kind, uri = uri, obj = obj } }, CT)
end
DT.Content = {
	none = newContent("None", nil, nil),
	fromUri = function(uri)
		if type(uri) ~= "string" then
			argError(1, "fromUri", "string", uri, 3)
		end
		return newContent("Uri", uri, nil)
	end,
	fromAssetId = function(id)
		return newContent("Uri", "rbxassetid://" .. fmtn(checknum(id, 1, "fromAssetId")), nil)
	end,
	fromObject = function(obj)
		if obj == nil or not DT.isInstance(obj) then
			argError(1, "fromObject", "Object", obj, 3)
		end
		return newContent("Object", nil, obj)
	end,
}

---------------------------------------------------------------------------------------------------------
-- globals for script environments
---------------------------------------------------------------------------------------------------------
DT.Enum = Enum
DT.Enums = Enums
DT.globals = {
	Vector3 = DT.Vector3,
	Vector2 = DT.Vector2,
	Vector3int16 = DT.Vector3int16,
	Vector2int16 = DT.Vector2int16,
	CFrame = DT.CFrame,
	Color3 = DT.Color3,
	UDim = DT.UDim,
	UDim2 = DT.UDim2,
	Rect = DT.Rect,
	NumberRange = DT.NumberRange,
	NumberSequence = DT.NumberSequence,
	NumberSequenceKeypoint = DT.NumberSequenceKeypoint,
	ColorSequence = DT.ColorSequence,
	ColorSequenceKeypoint = DT.ColorSequenceKeypoint,
	BrickColor = DT.BrickColor,
	TweenInfo = DT.TweenInfo,
	Ray = DT.Ray,
	RaycastParams = DT.RaycastParams,
	OverlapParams = DT.OverlapParams,
	Region3 = DT.Region3,
	Region3int16 = DT.Region3int16,
	Random = DT.Random,
	DateTime = DT.DateTime,
	Font = DT.Font,
	PhysicalProperties = DT.PhysicalProperties,
	Axes = DT.Axes,
	Faces = DT.Faces,
	Content = DT.Content,
	Enum = Enum,
	typeof = DT.typeof,
}

-- freeze the library tables (Roblox's are read-only); call once after any engine-side extension
function DT.freezeLibraries()
	for name, lib in DT.globals do
		if type(lib) == "table" and name ~= "Enum" and not table.isfrozen(lib) then
			table.freeze(lib)
		end
	end
end

return DT
