-- GwangalliPasses/Util (server): small helpers shared by the pass modules (lookups with timeouts, guarded
-- requires, token buckets, player state checks). Nothing here yields unless its name says wait*.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Util = {}

local warned: { [string]: boolean } = {}
function Util.warnOnce(key: string, msg: any)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[GwangalliPasses] " .. key .. ": " .. tostring(msg))
end

function Util.log(...: any)
	print("[GwangalliPasses]", ...)
end

-- parent:WaitForChild(name) with a timeout and an optional class check (the place has a Script and a Folder
-- of the same name side by side, e.g. ServerScriptService.GwangalliVehicles)
function Util.waitChild(parent: Instance, name: string, className: string?, timeout: number?): Instance?
	local deadline = os.clock() + (timeout or 60)
	while true do
		for _, c in parent:GetChildren() do
			if c.Name == name and (className == nil or c:IsA(className)) then
				return c
			end
		end
		if os.clock() >= deadline then
			return nil
		end
		task.wait(0.25)
	end
end

function Util.findChild(parent: Instance?, name: string, className: string?): Instance?
	if not parent then
		return nil
	end
	for _, c in parent:GetChildren() do
		if c.Name == name and (className == nil or c:IsA(className)) then
			return c
		end
	end
	return nil
end

-- ServerScriptService.<folder>(Folder) / a / b ... -> ModuleScript, required (pcall)
function Util.requirePath(folderName: string, path: { string }, timeout: number?): any
	local folder = Util.waitChild(ServerScriptService, folderName, "Folder", timeout or 60)
	if not folder then
		return nil, "no folder " .. folderName
	end
	local node: Instance = folder
	for _, name in path do
		local nxt = Util.waitChild(node, name, nil, 20)
		if not nxt then
			return nil, "missing " .. name
		end
		node = nxt
	end
	if not node:IsA("ModuleScript") then
		return nil, node.Name .. " is not a ModuleScript"
	end
	local ok, res = pcall(require, node)
	if not ok or type(res) ~= "table" then
		return nil, tostring(res)
	end
	return res, nil
end

function Util.requireShared(parent: Instance, name: string, timeout: number?): any
	local m = Util.waitChild(parent, name, "ModuleScript", timeout or 30)
	if not m then
		return nil
	end
	local ok, res = pcall(require, m)
	return if ok then res else nil
end

-- wraps tbl[name] once: tbl[name] = make(original). Returns the original (or nil when missing).
local wrappedFns = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }
function Util.wrap(tbl: any, name: string, make: (any) -> any): any
	if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then
		return nil
	end
	local cur = tbl[name]
	if wrappedFns[cur] then
		return nil -- already ours
	end
	local wrapper = make(cur)
	wrappedFns[wrapper] = true
	tbl[name] = wrapper
	return cur
end

---------------------------------------------------------------------------------------------------
-- token bucket
---------------------------------------------------------------------------------------------------
local Bucket = {}
Bucket.__index = Bucket
function Util.bucket(burst: number, rate: number): any
	return setmetatable({ burst = burst, rate = rate, per = {} }, Bucket)
end
function Bucket:take(key: any, cost: number?): boolean
	local now = os.clock()
	local b = self.per[key]
	if not b then
		b = { tokens = self.burst, t = now }
		self.per[key] = b
	end
	b.tokens = math.min(self.burst, b.tokens + (now - b.t) * self.rate)
	b.t = now
	local c = cost or 1
	if b.tokens < c then
		return false
	end
	b.tokens -= c
	return true
end
function Bucket:forget(key: any)
	self.per[key] = nil
end

---------------------------------------------------------------------------------------------------
-- player state
---------------------------------------------------------------------------------------------------
function Util.isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

function Util.root(player: Player): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

function Util.humanoid(player: Player): Humanoid?
	local ch = player.Character
	return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end

-- why this player cannot do a "street" action right now (nil = fine)
function Util.blockedState(player: Player): string?
	local ch = player.Character
	local hum = Util.humanoid(player)
	if not ch or not hum or hum.Health <= 0 or not Util.root(player) then
		return "dead"
	end
	if ch:GetAttribute("GwKO") == true then
		return "ko"
	end
	local jail = player:GetAttribute("LawJail")
	if type(jail) == "number" and jail > workspace:GetServerTimeNow() then
		return "jail"
	end
	if player:GetAttribute("LawCuffed") == true or ch:GetAttribute("LawCuffed") == true then
		return "cuffed"
	end
	if hum.SeatPart then
		return "seated"
	end
	return nil
end

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.shortString(v: any, max: number): string?
	return if type(v) == "string" and #v > 0 and #v <= max then v else nil
end

return Util
