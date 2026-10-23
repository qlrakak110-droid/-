--!nocheck
-- Minimal Roblox server mock for GwangalliKaraokePlus logic tests (luau CLI).
-- Cooperative scheduler with a fake clock, instances with attributes / tags / children, Players,
-- RemoteFunction dispatch, BindableFunction APIs, JSON, and a module loader that runs the add-on
-- sources unchanged.
local DT = require("./datatypes")
local Enums = require("./enums")
Enums.setData(require("./enumsdata"))
local Enum = Enums.Enum
local Vector3, CFrame, Color3 = DT.Vector3, DT.CFrame, DT.Color3

local M = {}
M.srcs = require("./srcs")
M.clock = 1000
M.threads = {} -- { co, wake }
M.log = {}

-------------------------------------------------------------------------------------------------
-- scheduler
-------------------------------------------------------------------------------------------------
local task = {}
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		print("[thread error] " .. tostring(err) .. "\n" .. debug.traceback(co))
	end
end
function task.spawn(f, ...)
	if type(f) == "thread" then
		resume(f, ...)
		return f
	end
	local co = coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local args = table.pack(...)
	local co = coroutine.create(function()
		f(table.unpack(args, 1, args.n))
	end)
	table.insert(M.threads, { co = co, wake = M.clock })
	return co
end
function task.delay(t, f, ...)
	local args = table.pack(...)
	local co = coroutine.create(function()
		f(table.unpack(args, 1, args.n))
	end)
	table.insert(M.threads, { co = co, wake = M.clock + (t or 0) })
	return co
end
function task.wait(t)
	local co = coroutine.running()
	table.insert(M.threads, { co = co, wake = M.clock + math.max(t or 0.03, 0.001) })
	coroutine.yield()
	return t
end
function task.cancel() end
M.task = task

function M.advance(seconds, step)
	step = step or 0.05
	local target = M.clock + seconds
	while M.clock < target - 1e-9 do
		M.clock = math.min(target, M.clock + step)
		local due = {}
		for i = #M.threads, 1, -1 do
			if M.threads[i].wake <= M.clock then
				table.insert(due, table.remove(M.threads, i))
			end
		end
		table.sort(due, function(a, b)
			return a.wake < b.wake
		end)
		for _, d in due do
			if coroutine.status(d.co) == "suspended" then
				resume(d.co)
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- signals
-------------------------------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ fns = {} }, Signal)
end
function Signal:Connect(fn)
	table.insert(self.fns, fn)
	local s = self
	return { Disconnect = function()
		local i = table.find(s.fns, fn)
		if i then
			table.remove(s.fns, i)
		end
	end }
end
function Signal:Fire(...)
	for _, fn in table.clone(self.fns) do
		task.spawn(fn, ...)
	end
end
function Signal:Wait()
	local co = coroutine.running()
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		task.spawn(co, ...)
	end)
	return coroutine.yield()
end
M.Signal = Signal

-------------------------------------------------------------------------------------------------
-- instances
-------------------------------------------------------------------------------------------------
local tags = {} -- tag -> { inst }
local tagAdded = {}
local GUI = { "GuiObject", "GuiBase2d" }
local ISA = {
	Frame = GUI, TextLabel = GUI, TextButton = { "GuiObject", "GuiButton", "GuiBase2d" }, TextBox = GUI, ScrollingFrame = GUI, ImageLabel = GUI,
	ScreenGui = { "LayerCollector" }, SurfaceGui = { "LayerCollector" },
	Part = { "BasePart", "PVInstance" },
	Model = { "PVInstance" },
	Folder = {},
	Configuration = {},
	ModuleScript = { "LuaSourceContainer" },
	RemoteFunction = {},
	RemoteEvent = {},
	UnreliableRemoteEvent = {},
	BindableFunction = {},
	ProximityPrompt = {},
	Humanoid = {},
	Player = {},
	Wire = {},
	WeldConstraint = {},
}
local Inst = {}
local function newInst(class, name)
	local o = { ClassName = class, Name = name or class, _ch = {}, _attr = {}, _sig = {}, Parent = nil }
	o.AttributeChanged = Signal.new()
	o.ChildAdded = Signal.new()
	o.DescendantAdded = Signal.new()
	o.Destroying = Signal.new()
	setmetatable(o, { __index = Inst })
	if class == "Part" then
		o.CFrame = CFrame.new()
		o.Size = Vector3.new(1, 1, 1)
		o.Transparency = 0
	end
	return o
end
M.newInst = newInst
function Inst:IsA(c)
	if self.ClassName == c or c == "Instance" then
		return true
	end
	for _, a in ISA[self.ClassName] or {} do
		if a == c then
			return true
		end
	end
	return false
end
function Inst:SetParent(p)
	if self.Parent then
		local i = table.find(self.Parent._ch, self)
		if i then
			table.remove(self.Parent._ch, i)
		end
	end
	rawset(self, "Parent", p)
	if p then
		table.insert(p._ch, self)
		p.ChildAdded:Fire(self)
		local a = p
		while a do
			a.DescendantAdded:Fire(self)
			a = a.Parent
		end
	end
end
function Inst:GetChildren()
	return table.clone(self._ch)
end
function Inst:GetDescendants()
	local out = {}
	local function rec(o)
		for _, c in o._ch do
			table.insert(out, c)
			rec(c)
		end
	end
	rec(self)
	return out
end
function Inst:FindFirstChild(name, rec)
	for _, c in self._ch do
		if c.Name == name then
			return c
		end
	end
	if rec then
		for _, c in self._ch do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function Inst:FindFirstChildOfClass(cls)
	for _, c in self._ch do
		if c.ClassName == cls then
			return c
		end
	end
	return nil
end
function Inst:FindFirstChildWhichIsA(cls, rec)
	for _, c in (if rec then self:GetDescendants() else self._ch) do
		if c:IsA(cls) then
			return c
		end
	end
	return nil
end
function Inst:WaitForChild(name)
	return self:FindFirstChild(name)
end
function Inst:SetAttribute(k, v)
	if self._attr[k] ~= v then
		self._attr[k] = v
		self.AttributeChanged:Fire(k)
		local a = rawget(self, "_asig")
		if a and a[k] then
			a[k]:Fire()
		end
	end
end
function Inst:GetAttribute(k)
	return self._attr[k]
end
function Inst:GetAttributeChangedSignal(k)
	local a = rawget(self, "_asig")
	if not a then
		a = {}
		rawset(self, "_asig", a)
	end
	a[k] = a[k] or Signal.new()
	return a[k]
end
function Inst:GetPropertyChangedSignal(k)
	local a = rawget(self, "_psig")
	if not a then
		a = {}
		rawset(self, "_psig", a)
	end
	a[k] = a[k] or Signal.new()
	return a[k]
end
function Inst:Destroy()
	self.Destroying:Fire()
	self:SetParent(nil)
end
function Inst:GetFullName()
	local n = self.Name
	local a = self.Parent
	while a do
		n = a.Name .. "." .. n
		a = a.Parent
	end
	return n
end
function Inst:PivotTo(cf)
	local hrp = self:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = cf
		hrp.Position = cf.Position
	end
end
function Inst:IsDescendantOf(a)
	local p = self.Parent
	while p do
		if p == a then
			return true
		end
		p = p.Parent
	end
	return false
end
-- Parent assignment through a proxy table
local function wrap(o)
	return o
end

local Instance = {}
function Instance.new(class)
	if class == "UnreliableRemoteEvent" or class == "Wire" or class:sub(1, 5) == "Audio" then
		error("not supported in mock: " .. class)
	end
	local o = newInst(class)
	if class == "RemoteFunction" then
		o.OnServerInvoke = nil
	elseif class == "RemoteEvent" then
		o.fired = {}
		function o:FireClient(p, payload)
			table.insert(self.fired, { p = p, payload = payload })
			M.onEvent(self, p, payload)
		end
	end
	return o
end
M.onEvent = function() end

-- parent setter: tests and modules write inst.Parent = x; emulate with __newindex
local mt = getmetatable(newInst("Folder"))
local EVENTS = { Activated = true, MouseEnter = true, MouseLeave = true, MouseButton1Down = true, MouseButton1Up = true, MouseButton1Click = true, InputBegan = true, InputChanged = true, InputEnded = true, Triggered = true, Changed = true, FocusLost = true, OnClientEvent = true, OnServerEvent = true }
M.validate = nil -- { [ClassName] = { [member] = true } }
M.defaults = {}
local function setmeta(o)
	setmetatable(o, {
		__index = function(t, k)
			local raw = rawget(t, "_props")
			if raw and raw[k] ~= nil then
				return raw[k]
			end
			local m = Inst[k]
			if m ~= nil then
				return m
			end
			if EVENTS[k] then
				local sg = Signal.new()
				raw[k] = sg
				return sg
			end
			for _, c in rawget(t, "_ch") do
				if c.Name == k then
					return c
				end
			end
			local d = M.defaults[k]
			if d ~= nil then
				return d
			end
			return nil
		end,
		__newindex = function(t, k, v)
			if k == "Parent" then
				Inst.SetParent(t, v)
				return
			end
			local cls = rawget(t, "ClassName")
			local V = M.validate and M.validate[cls]
			if V and not V[k] then
				error(string.format("%s is not a valid member of %s", tostring(k), cls), 2)
			end
			rawget(t, "_props")[k] = v
			if k == "CFrame" and cls == "Part" then
				rawget(t, "_props").Position = v.Position
			end
			local ps = rawget(t, "_psig")
			if ps and ps[k] then
				ps[k]:Fire()
			end
		end,
	})
end
-- rebuild newInst with props table so Parent goes through SetParent
newInst = function(class, name)
	local o = { ClassName = class, _ch = {}, _attr = {}, _props = { Name = name or class } }
	o.AttributeChanged = Signal.new()
	o.ChildAdded = Signal.new()
	o.DescendantAdded = Signal.new()
	o.Destroying = Signal.new()
	setmeta(o)
	if class == "Part" then
		o.CFrame = CFrame.new()
		o.Size = Vector3.new(1, 1, 1)
		o.Transparency = 0
	end
	return o
end
M.newInst = newInst
function Inst:SetParent(p)
	local old = rawget(self, "_props").Parent
	if old then
		local i = table.find(old._ch, self)
		if i then
			table.remove(old._ch, i)
		end
	end
	rawget(self, "_props").Parent = p
	if p then
		table.insert(p._ch, self)
		p.ChildAdded:Fire(self)
		local a = p
		while a do
			a.DescendantAdded:Fire(self)
			a = rawget(a, "_props").Parent
		end
	end
end
Instance.new = function(class)
	if class == "UnreliableRemoteEvent" or class == "Wire" or class:sub(1, 5) == "Audio" then
		error("not supported in mock: " .. class)
	end
	local o = newInst(class)
	if class == "RemoteEvent" then
		rawget(o, "_props").FireClient = function(self, p, payload)
			M.onEvent(self, p, payload)
			if p == M.localPlayer then
				self.OnClientEvent:Fire(payload)
			end
		end
	elseif class == "RemoteFunction" then
		rawget(o, "_props").InvokeServer = function(self, op, payload)
			return self.OnServerInvoke(M.localPlayer, op, payload)
		end
	elseif class == "Sound" then
		rawget(o, "_props").Play = function(self)
			rawget(self, "_props").IsPlaying = true
			M.plays = (M.plays or 0) + 1
		end
		rawget(o, "_props").Stop = function(self)
			rawget(self, "_props").IsPlaying = false
		end
	elseif class == "ParticleEmitter" then
		rawget(o, "_props").Emit = function() end
	end
	return o
end
M.Instance = Instance

-- part position mirrors CFrame
local function part(name, pos, size, rotY)
	local p = newInst("Part", name)
	p.CFrame = CFrame.new(pos.X, pos.Y, pos.Z) * CFrame.Angles(0, rotY or 0, 0)
	p.Position = pos
	p.Size = size
	return p
end
M.part = part

-------------------------------------------------------------------------------------------------
-- services
-------------------------------------------------------------------------------------------------
local game = newInst("DataModel", "Game")
game.PlaceId = 0
local services = {}
local function svc(name)
	local s = newInst("Service", name)
	s.Parent = game
	services[name] = s
	return s
end
local workspace = svc("Workspace")
function workspace:GetServerTimeNow()
	return M.clock
end
game.Workspace = workspace
local Players = svc("Players")
Players.PlayerAdded = Signal.new()
Players.PlayerRemoving = Signal.new()
function Players:GetPlayers()
	local out = {}
	for _, c in self._ch do
		if c.ClassName == "Player" then
			table.insert(out, c)
		end
	end
	return out
end
function Players:GetPlayerByUserId(id)
	for _, p in self:GetPlayers() do
		if p.UserId == id then
			return p
		end
	end
	return nil
end
local CS = svc("CollectionService")
function CS:GetTagged(t)
	return table.clone(tags[t] or {})
end
function CS:GetInstanceAddedSignal(t)
	tagAdded[t] = tagAdded[t] or Signal.new()
	return tagAdded[t]
end
function CS:GetInstanceRemovedSignal(t)
	return Signal.new()
end
function M.tag(inst, t)
	tags[t] = tags[t] or {}
	table.insert(tags[t], inst)
end
svc("ServerStorage")
svc("ServerScriptService")
svc("ReplicatedStorage")
svc("RunService")
local DSS = svc("DataStoreService")
function DSS:GetDataStore()
	error("no datastore in mock")
end
local Http = svc("HttpService")

-- JSON
local function enc(v)
	local t = type(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "number" then
		if math.floor(v) == v and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.6f", v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			return string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local o = {}
			for i, x in v do
				o[i] = enc(x)
			end
			return "[" .. table.concat(o, ",") .. "]"
		end
		local keys = {}
		for k in v do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local o = {}
		for _, k in keys do
			table.insert(o, enc(k) .. ":" .. enc(v[k] == nil and v[tonumber(k)] or v[k]))
		end
		return "{" .. table.concat(o, ",") .. "}"
	end
	error("cannot encode " .. t)
end
local function dec(s)
	local i = 1
	local function ws()
		i = s:find("[^%s]", i) or #s + 1
	end
	local val
	local function str()
		local out = {}
		i += 1
		while true do
			local c = s:sub(i, i)
			if c == '"' then
				i += 1
				break
			elseif c == "\\" then
				local n = s:sub(i + 1, i + 1)
				if n == "u" then
					table.insert(out, utf8.char(tonumber(s:sub(i + 2, i + 5), 16)))
					i += 6
				else
					table.insert(out, ({ n = "\n", t = "\t" })[n] or n)
					i += 2
				end
			else
				table.insert(out, c)
				i += 1
			end
		end
		return table.concat(out)
	end
	val = function()
		ws()
		local c = s:sub(i, i)
		if c == "{" then
			i += 1
			local t = {}
			ws()
			if s:sub(i, i) == "}" then
				i += 1
				return t
			end
			while true do
				ws()
				local k = str()
				ws()
				i += 1 -- :
				t[k] = val()
				ws()
				local d = s:sub(i, i)
				i += 1
				if d == "}" then
					return t
				end
			end
		elseif c == "[" then
			i += 1
			local t = {}
			ws()
			if s:sub(i, i) == "]" then
				i += 1
				return t
			end
			while true do
				table.insert(t, val())
				ws()
				local d = s:sub(i, i)
				i += 1
				if d == "]" then
					return t
				end
			end
		elseif c == '"' then
			return str()
		elseif s:sub(i, i + 3) == "true" then
			i += 4
			return true
		elseif s:sub(i, i + 4) == "false" then
			i += 5
			return false
		elseif s:sub(i, i + 3) == "null" then
			i += 4
			return nil
		else
			local num = s:match("^-?[%d%.eE+-]+", i)
			i += #num
			return tonumber(num)
		end
	end
	return val()
end
function Http:JSONEncode(t)
	return enc(t)
end
function Http:JSONDecode(s)
	return dec(s)
end
function Http:GenerateGUID()
	return "guid"
end
function game:GetService(n)
	return services[n] or svc(n)
end
function game:BindToClose() end
M.game, M.workspace, M.Players = game, workspace, Players

-------------------------------------------------------------------------------------------------
-- players
-------------------------------------------------------------------------------------------------
function M.addPlayer(uid, name, pos)
	local p = newInst("Player", name)
	p.UserId = uid
	p.DisplayName = name
	p.CharacterAdded = Signal.new()
	function p:IsFriendsWith(other)
		return M.friends[uid .. ":" .. other] == true
	end
	local ch = newInst("Model", name)
	local hrp = part("HumanoidRootPart", pos, Vector3.new(2, 2, 1))
	hrp.Parent = ch
	local hum = newInst("Humanoid", "Humanoid")
	hum.Health = 100
	hum.Parent = ch
	ch.Parent = workspace
	p.Character = ch
	p.Parent = Players
	Players.PlayerAdded:Fire(p)
	return p
end
M.friends = {}
function M.move(p, pos)
	local hrp = p.Character.HumanoidRootPart
	hrp.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)
	hrp.Position = pos
end
function M.removePlayer(p)
	Players.PlayerRemoving:Fire(p)
	p.Parent = nil
end

-------------------------------------------------------------------------------------------------
-- module loader
-------------------------------------------------------------------------------------------------
local cache = {}
M.env = nil
local function scriptObj(path, dir)
	local s = newInst("ModuleScript", path:match("([^/]+)%.luau$"))
	s._path = path
	s._dir = dir
	function s:WaitForChild(name)
		local f = self:FindFirstChild(name)
		if f then
			return f
		end
		local c = scriptObj(self._dir .. name .. ".luau", self._dir)
		c.Name = name
		c.Parent = self
		return c
	end
	return s
end
M.scriptObj = scriptObj
function M.load(path, scr)
	if cache[path] then
		return cache[path]
	end
	local src = M.srcs[path]
	if not src then
		error("no source " .. path)
	end
	local fn, err = loadstring(src, "=" .. path)
	if not fn then
		error(err)
	end
	local env = setmetatable({ script = scr }, { __index = M.env })
	setfenv(fn, env)
	local r = fn()
	cache[path] = r
	return r
end
M.Vector3, M.CFrame, M.Color3, M.Enum = Vector3, CFrame, Color3, Enum
M.env = setmetatable({
	game = game,
	workspace = workspace,
	Instance = Instance,
	Enum = Enum,
	Vector3 = Vector3,
	CFrame = CFrame,
	Color3 = Color3,
	task = task,
	warn = function(...)
		print("[warn]", ...)
	end,
	typeof = DT.typeof or typeof,
	require = function(m)
		if type(m) == "table" and m._path then
			return M.load(m._path, m)
		end
		error("require " .. tostring(m))
	end,
	os = setmetatable({ clock = function()
		return M.clock
	end }, { __index = os }),
}, { __index = getfenv(0) })
return M
