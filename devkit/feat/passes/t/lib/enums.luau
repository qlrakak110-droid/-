--!nocheck
-- enums.luau — the Roblox `Enum` global for the RobloxLite player (PLAYER_ARCH §1).
--
-- Data comes from tools/player/gen/enums.json (tools/player/tools/gen_enums.luau, Lune reflection DB).
-- Load it before the first Enum access with Enums.setData(jsonText) (or a decoded table). Under Lune the
-- file is read automatically; in the browser the host passes the JSON text (or sets the global
-- __PLAYER_ENUMS_JSON to it before the first Enum access).
--
-- Given the JSON text in the generator's canonical layout (one enum per line), nothing is decoded up front:
-- an Enum is parsed from its own line on first access, so boot cost stays near zero on phones.
--
-- Semantics follow Roblox:
--   Enum                 typeof "Enums"    Enum.Material, Enum:GetEnums()
--   Enum.Material        typeof "Enum"     .Plastic, :GetEnumItems(), :FromName("Wood"), :FromValue(512); tostring -> "Material"
--   Enum.Material.Wood   typeof "EnumItem" .Name, .Value, .EnumType, :IsA("Material"); tostring -> "Enum.Material.Wood"
-- EnumItems are frozen singletons (== is identity).

local Enums = {}

local sbyte, ssub, sfind = string.byte, string.sub, string.find

---------------------------------------------------------------------------------------------------------
-- JSON decoder (generic; exported for other engine modules)
---------------------------------------------------------------------------------------------------------
local ESCAPES = { [34] = '"', [92] = "\\", [47] = "/", [98] = "\b", [102] = "\f", [110] = "\n", [114] = "\r", [116] = "\t" }

-- decode the JSON value starting at byte `start`; returns value, index after it
local function decodeFrom(str: string, start: number): (any, number)
	local pos = start
	local function perr(msg)
		error(string.format("JSON decode error at character %d: %s", pos, msg), 0)
	end
	local function skip()
		local c = sbyte(str, pos)
		if c == 32 or c == 10 or c == 13 or c == 9 then
			local _, e = sfind(str, "^[ \t\r\n]*", pos)
			pos = e + 1
		end
	end
	local function decodeString()
		local startp = pos + 1
		local s = sfind(str, '["\\]', startp)
		if not s then
			perr("unterminated string")
		end
		if sbyte(str, s) == 34 then
			pos = s + 1
			return ssub(str, startp, s - 1)
		end
		local buf, n = {}, 0
		local i = startp
		while true do
			local s2 = sfind(str, '["\\]', i)
			if not s2 then
				perr("unterminated string")
			end
			if s2 > i then
				n += 1
				buf[n] = ssub(str, i, s2 - 1)
			end
			if sbyte(str, s2) == 34 then
				pos = s2 + 1
				return table.concat(buf)
			end
			local esc = sbyte(str, s2 + 1)
			if esc == 117 then
				local cp = tonumber(ssub(str, s2 + 2, s2 + 5), 16)
				if not cp then
					pos = s2
					perr("bad \\u escape")
				end
				i = s2 + 6
				if cp >= 0xD800 and cp <= 0xDBFF and ssub(str, i, i + 1) == "\\u" then
					local lo = tonumber(ssub(str, i + 2, i + 5), 16)
					if lo and lo >= 0xDC00 and lo <= 0xDFFF then
						cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
						i += 6
					end
				end
				n += 1
				buf[n] = utf8.char(cp)
			else
				local r = ESCAPES[esc]
				if not r then
					pos = s2
					perr("bad escape")
				end
				n += 1
				buf[n] = r
				i = s2 + 2
			end
		end
	end
	local decodeValue
	function decodeValue()
		skip()
		local c = sbyte(str, pos)
		if c == 34 then
			return decodeString()
		elseif c == 91 then -- [
			local arr, n = {}, 0
			pos += 1
			skip()
			if sbyte(str, pos) == 93 then
				pos += 1
				return arr
			end
			while true do
				n += 1
				arr[n] = decodeValue()
				skip()
				local d = sbyte(str, pos)
				pos += 1
				if d == 93 then
					return arr
				elseif d ~= 44 then
					pos -= 1
					perr("expected ',' or ']'")
				end
			end
		elseif c == 123 then -- {
			local obj = {}
			pos += 1
			skip()
			if sbyte(str, pos) == 125 then
				pos += 1
				return obj
			end
			while true do
				skip()
				if sbyte(str, pos) ~= 34 then
					perr("expected string key")
				end
				local k = decodeString()
				skip()
				if sbyte(str, pos) ~= 58 then
					perr("expected ':'")
				end
				pos += 1
				obj[k] = decodeValue()
				skip()
				local d = sbyte(str, pos)
				pos += 1
				if d == 125 then
					return obj
				elseif d ~= 44 then
					pos -= 1
					perr("expected ',' or '}'")
				end
			end
		elseif c == 116 then
			if ssub(str, pos, pos + 3) == "true" then
				pos += 4
				return true
			end
		elseif c == 102 then
			if ssub(str, pos, pos + 4) == "false" then
				pos += 5
				return false
			end
		elseif c == 110 then
			if ssub(str, pos, pos + 3) == "null" then
				pos += 4
				return nil
			end
		elseif c then
			local s, e = sfind(str, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			if s then
				local v = tonumber(ssub(str, s, e))
				if v then
					pos = e + 1
					return v
				end
			end
		end
		perr(if c then "unexpected character '" .. string.char(c) .. "'" else "unexpected end of input")
		return nil
	end
	local v = decodeValue()
	return v, pos
end

local function jsonDecode(str: string): any
	if type(str) ~= "string" then
		error("jsonDecode: string expected, got " .. type(str), 2)
	end
	local v, pos = decodeFrom(str, 1)
	local _, e = sfind(str, "^[ \t\r\n]*", pos)
	if e + 1 <= #str then
		error(string.format("JSON decode error at character %d: trailing characters", e + 1), 0)
	end
	return v
end
Enums.jsonDecode = jsonDecode
Enums.jsonDecodeFrom = decodeFrom

---------------------------------------------------------------------------------------------------------
-- data source
---------------------------------------------------------------------------------------------------------
local text = nil -- JSON text (lazy mode)
local decoded = nil -- fully decoded table (table given, or text not in canonical layout)
local enumsFrom, enumsTo = 0, 0 -- byte range of the "enums" object inside `text` (canonical layout)
local enumCache = {} -- enumName -> raw item array | false (lazy mode)
local sectionCache = {} -- top-level key -> decoded value (lazy mode)

-- Deprecated item names Roblox still accepts; they resolve to the same (canonical) EnumItem.
local ALIASES = {
	RaycastFilterType = { Blacklist = "Exclude", Whitelist = "Include" },
}

local function tryLuneLoad()
	-- only under Lune (never touch require/pcall in the browser: luau-web's JSPI build does not catch errors
	-- inside pcall, and the player's require shim has no @lune/* modules)
	if type(_VERSION) ~= "string" or string.sub(_VERSION, 1, 4) ~= "Lune" or type(require) ~= "function" then
		return nil
	end
	local okFs, fs = pcall(require, "@lune/fs")
	if not okFs or type(fs) ~= "table" or type(fs.readFile) ~= "function" then
		return nil
	end
	local candidates = {}
	local src = if debug and debug.info then debug.info(1, "s") else nil
	if type(src) == "string" then
		src = string.gsub(src, "^@", "")
		local dir = string.match(src, "^(.*)[/\\][^/\\]*$")
		if dir then
			table.insert(candidates, dir .. "/../gen/enums.json")
		end
	end
	table.insert(candidates, "tools/player/gen/enums.json")
	table.insert(candidates, "gen/enums.json")
	table.insert(candidates, "../gen/enums.json")
	for _, p in candidates do
		local ok, t = pcall(fs.readFile, p)
		if ok and type(t) == "string" and #t > 0 then
			return t
		end
	end
	return nil
end

function Enums.setData(src)
	if type(src) == "string" then
		local s = sfind(src, '"enums":{\n', 1, true)
		local e = s and sfind(src, "\n}", s, true)
		if s and e then
			text, decoded = src, nil
			enumsFrom, enumsTo = s, e
		else
			text, decoded = nil, jsonDecode(src)
		end
	elseif type(src) == "table" and type(src.enums) == "table" then
		text, decoded = nil, src
	else
		error("Enums.setData: expected tools/player/gen/enums.json text (or the decoded table)", 2)
	end
	if type(decoded) == "table" and type(decoded.enums) ~= "table" then
		decoded = nil
		error("Enums.setData: no 'enums' object in the data", 2)
	end
	enumCache, sectionCache = {}, {}
end

-- Under Lune, read gen/enums.json while this module loads (Lune's require/fs must not be called later
-- from inside a metamethod such as Enum.__index). Elsewhere this is a no-op.
local luneText = tryLuneLoad()

local function ensureSource()
	if text or decoded then
		return
	end
	local src = __PLAYER_ENUMS_JSON -- optional host-provided global (JSON text or decoded table)
	if src == nil then
		src = luneText
	end
	if src == nil then
		error("Enum data not loaded: call Enums.setData(<tools/player/gen/enums.json text>) before using Enum", 4)
	end
	Enums.setData(src)
end

function Enums.isLoaded(): boolean
	return text ~= nil or decoded ~= nil
end

-- raw item array {{name, value}, ...} of one enum, or nil
local function rawEnum(name: string)
	ensureSource()
	if decoded then
		return decoded.enums[name]
	end
	local c = enumCache[name]
	if c ~= nil then
		return c or nil
	end
	local s = sfind(text, '\n"' .. name .. '":[', enumsFrom, true)
	if s and s < enumsTo then
		local v = decodeFrom(text, s + #name + 4)
		enumCache[name] = v
		return v
	end
	enumCache[name] = false
	return nil
end

-- sorted list of every enum name
local function enumNames()
	ensureSource()
	local names = {}
	if decoded then
		for n in decoded.enums do
			table.insert(names, n)
		end
	else
		local body = ssub(text, enumsFrom, enumsTo)
		for n in string.gmatch(body, '\n"([%w_]+)":%[') do
			table.insert(names, n)
		end
	end
	table.sort(names)
	return names
end

-- decoded top-level section of enums.json ("fonts", "brickColors", "palette", "materials", "version"), or nil
function Enums.section(key: string)
	ensureSource()
	if decoded then
		return decoded[key]
	end
	local c = sectionCache[key]
	if c ~= nil then
		return c or nil
	end
	local pat = '\n"' .. key .. '":'
	local s = sfind(text, pat, enumsTo, true) or sfind(text, pat, 1, true)
	local v = false
	if s and not (s > enumsFrom and s < enumsTo) then
		v = decodeFrom(text, s + #pat)
	end
	sectionCache[key] = v
	return v or nil
end

-- the whole decoded enums.json (forces a full decode in lazy mode; tests/tools only)
function Enums.data()
	ensureSource()
	if not decoded then
		decoded = jsonDecode(text)
	end
	return decoded
end

---------------------------------------------------------------------------------------------------------
-- objects
---------------------------------------------------------------------------------------------------------
local EnumsMeta = { __type = "Enums" }
local EnumMeta = { __type = "Enum" }
local ItemMeta = { __type = "EnumItem" }
Enums.EnumsMeta, Enums.EnumMeta, Enums.ItemMeta = EnumsMeta, EnumMeta, ItemMeta

local root = setmetatable({}, EnumsMeta)
Enums.Enum = root

-- per Enum object info (kept outside the object: item names such as "Name" live in the object itself)
local info = {} -- [enumObj] = { name, list = {items}, byValue = {}, byName = {} }
local built = {} -- enumName -> enumObj

local function build(name)
	local b = built[name]
	if b then
		return b
	end
	if type(name) ~= "string" then
		return nil
	end
	local raw = rawEnum(name)
	if raw == nil then
		return nil
	end
	local e = setmetatable({}, EnumMeta)
	local inf = { name = name, list = table.create(#raw), byValue = {}, byName = {} }
	for i, pair in raw do
		local it = table.freeze(setmetatable({ Name = pair[1], Value = pair[2], EnumType = e }, ItemMeta))
		rawset(e, pair[1], it)
		inf.list[i] = it
		inf.byName[pair[1]] = it
		if inf.byValue[pair[2]] == nil then
			inf.byValue[pair[2]] = it
		end
	end
	local al = ALIASES[name]
	if al then
		for alias, target in al do
			local it = inf.byName[target]
			if it and rawget(e, alias) == nil then
				rawset(e, alias, it)
				inf.byName[alias] = it
			end
		end
	end
	table.freeze(e)
	info[e] = inf
	built[name] = e
	rawset(root, name, e)
	return e
end

-- Enums (root) ------------------------------------------------------------------------------------------
local function getEnums(self)
	if self ~= root then
		error("Expected ':' not '.' calling member function GetEnums", 2)
	end
	local names = enumNames()
	local out = table.create(#names)
	for i, n in names do
		out[i] = build(n)
	end
	return out
end

EnumsMeta.__index = function(_, k)
	if k == "GetEnums" then
		return getEnums
	end
	local e = build(k)
	if e then
		return e
	end
	error(string.format('%s is not a valid member of "Enum"', tostring(k)), 2)
end
EnumsMeta.__newindex = function(_, k)
	error(string.format("%s cannot be assigned to", tostring(k)), 2)
end
EnumsMeta.__tostring = function()
	return "Enums"
end

-- Enum ----------------------------------------------------------------------------------------------------
local EnumMethods = {}
function EnumMethods.GetEnumItems(self)
	local inf = info[self]
	if not inf then
		error("Expected ':' not '.' calling member function GetEnumItems", 2)
	end
	return table.clone(inf.list)
end
function EnumMethods.FromName(self, name)
	local inf = info[self]
	if not inf then
		error("Expected ':' not '.' calling member function FromName", 2)
	end
	return inf.byName[name]
end
function EnumMethods.FromValue(self, value)
	local inf = info[self]
	if not inf then
		error("Expected ':' not '.' calling member function FromValue", 2)
	end
	return inf.byValue[value]
end

EnumMeta.__index = function(self, k)
	local m = EnumMethods[k]
	if m then
		return m
	end
	local inf = info[self]
	error(string.format('%s is not a valid member of "Enum.%s"', tostring(k), if inf then inf.name else "?"), 2)
end
EnumMeta.__newindex = function(_, k)
	error(string.format("%s cannot be assigned to", tostring(k)), 2)
end
EnumMeta.__tostring = function(self)
	local inf = info[self]
	return if inf then inf.name else "Enum"
end

-- EnumItem -------------------------------------------------------------------------------------------------
local function itemIsA(self, enumName)
	if getmetatable(self) ~= ItemMeta then
		error("Expected ':' not '.' calling member function IsA", 2)
	end
	local inf = info[self.EnumType]
	return inf ~= nil and inf.name == enumName
end

ItemMeta.__index = function(_, k)
	if k == "IsA" then
		return itemIsA
	end
	error(string.format("%s is not a valid member of EnumItem", tostring(k)), 2)
end
ItemMeta.__newindex = function(_, k)
	error(string.format("%s cannot be assigned to", tostring(k)), 2)
end
ItemMeta.__tostring = function(self)
	local inf = info[self.EnumType]
	return "Enum." .. (if inf then inf.name else "?") .. "." .. self.Name
end

---------------------------------------------------------------------------------------------------------
-- helpers for other engine modules
---------------------------------------------------------------------------------------------------------
-- Enum object by name, or nil (no error)
function Enums.get(enumName: string)
	return build(enumName)
end

-- name of an Enum object (Enum.Material -> "Material"), or nil
function Enums.nameOf(enumObj): string?
	local inf = info[enumObj]
	return inf and inf.name
end

function Enums.isEnumItem(v): boolean
	return type(v) == "table" and getmetatable(v) == ItemMeta
end

function Enums.isEnum(v): boolean
	return type(v) == "table" and getmetatable(v) == EnumMeta
end

-- EnumItem by name (string) or value (number) inside enum `enumName`, or nil
function Enums.item(enumName: string, key)
	local e = build(enumName)
	if not e then
		return nil
	end
	local inf = info[e]
	if type(key) == "number" then
		return inf.byValue[key]
	end
	return inf.byName[key]
end

-- Roblox property-assignment coercion: an EnumItem of the right enum, its Name (string) or Value (number).
-- Returns the EnumItem or nil when `v` is not acceptable.
function Enums.coerce(enumName: string, v)
	if type(v) == "table" and getmetatable(v) == ItemMeta then
		local inf = info[v.EnumType]
		if inf and inf.name == enumName then
			return v
		end
		return nil
	end
	if type(v) == "string" or type(v) == "number" then
		return Enums.item(enumName, v)
	end
	return nil
end

-- "Enum.Material.Wood" / "Material.Wood" -> EnumItem or nil
function Enums.parse(path: string)
	if type(path) ~= "string" then
		return nil
	end
	local e, n = string.match(path, "^Enum%.([%w_]+)%.([%w_]+)$")
	if not e then
		e, n = string.match(path, "^([%w_]+)%.([%w_]+)$")
	end
	if not e then
		return nil
	end
	return Enums.item(e, n)
end

return Enums
