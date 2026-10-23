-- minimal Roblox mock for bundle prelude tests
local IS_SERVER = true
local Inst = {}
Inst.__index = function(self, k)
	local m = rawget(Inst, k)
	if m then return m end
	local ch = rawget(self, "_children")
	for _, c in ch do if rawget(c, "_props").Name == k then return c end end
	local v = rawget(self, "_props")[k]
	if v ~= nil then return v end
	if k == "Parent" then return nil end
	error("mock: no member " .. tostring(k) .. " on " .. tostring(rawget(self, "_props").Name), 2)
end
Inst.__newindex = function(self, k, v)
	local p = rawget(self, "_props")
	if k == "Parent" then
		local old = p.Parent
		if old then
			local ch = rawget(old, "_children")
			for i, c in ch do if c == self then table.remove(ch, i) break end end
		end
		p.Parent = v
		if v then table.insert(rawget(v, "_children"), self) end
		return
	end
	p[k] = v
end
local function new(cls, name)
	local o = setmetatable({ _props = { ClassName = cls, Name = name or cls }, _children = {}, _attrs = {} }, Inst)
	return o
end
function Inst.IsA(self, c) local cls = rawget(self, "_props").ClassName return c == cls or c == "Instance" or (c == "BaseScript" and cls ~= "ModuleScript") or c == "LuaSourceContainer" end
function Inst.GetAttribute(self, k) return rawget(self, "_attrs")[k] end
function Inst.SetAttribute(self, k, v) rawget(self, "_attrs")[k] = v end
function Inst.FindFirstChild(self, n) for _, c in rawget(self, "_children") do if rawget(c, "_props").Name == n then return c end end return nil end
function Inst.WaitForChild(self, n, t) local c = Inst.FindFirstChild(self, n) if not c then warn("mock WaitForChild miss " .. n) end return c end
function Inst.GetChildren(self) return table.clone(rawget(self, "_children")) end
function Inst.Destroy(self) self.Parent = nil end
function Inst.GetFullName(self) return rawget(self, "_props").Name end
local services = {}
for _, n in { "ReplicatedStorage", "ServerScriptService", "Players" } do services[n] = new(n, n) end
services.RunService = { IsServer = function() return IS_SERVER end, IsStudio = function() return true end }
game = { GetService = function(_, n) return services[n] or error("mock service " .. n) end }
Instance = { new = function(cls) return new(cls) end }
local realTypeof = typeof
typeof = function(x) if type(x) == "table" and getmetatable(x) == Inst then return "Instance" end return realTypeof(x) end
task = { spawn = function(f, ...) local co = coroutine.create(f) local ok, e = coroutine.resume(co, ...) if not ok then error(e) end end, wait = function() end }
warn = function(...) print("WARN", ...) end
local realRequire = require
require = function(x) error("mock: real require called on " .. tostring(typeof(x) == "Instance" and x.Name or x)) end
local PlayerScripts = new("PlayerScripts", "PlayerScripts")
local function asServer() IS_SERVER = true script = new("Script", "GwangalliPlus") script.Parent = services.ServerScriptService end
local function asClient() IS_SERVER = false script = new("LocalScript", "GwangalliPlus") script.Parent = PlayerScripts end
