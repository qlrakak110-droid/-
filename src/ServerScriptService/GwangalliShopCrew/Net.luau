-- GwangalliShopCrew/Net: the add-on's remotes and their guard rails.
--   ReplicatedStorage.GwangalliShopCrewNet (Folder, created here)
--     Request  RemoteFunction   client -> server: Request:InvokeServer(op, payload) -> { ok, ... }
--     Event    RemoteEvent      server -> client only (anything a client fires at it is ignored)
--   Net.create(Shared)   Net.on(op, fn(player, payload) -> table)   Net.fire(p, kind, data)
--   Net.fireNear(pos, r, kind, data)   Net.fireAll(kind, data)
-- Every request: op must be a registered short string, payload a table (or nil), a per-player token bucket
-- (Config.RATE per second, Config.BURST burst), and the handler runs under pcall (a bug answers
-- { ok = false } instead of erroring on the client).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local Config: any = nil
local folder: Folder? = nil
local request: RemoteFunction? = nil
local event: RemoteEvent? = nil
local handlers: { [string]: (Player, any) -> any } = {}
local buckets: { [Player]: { tokens: number, t: number } } = {}

local BUSY = { ok = false, code = "rate", msg = "잠시 후 다시 시도해 주세요" }

local function allow(p: Player): boolean
	local now = os.clock()
	local b = buckets[p]
	if not b then
		b = { tokens = Config.BURST, t = now }
		buckets[p] = b
	end
	b.tokens = math.min(Config.BURST, b.tokens + (now - b.t) * Config.RATE)
	b.t = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function Net.create(Shared: any)
	Config = Shared.Config
	local f = ReplicatedStorage:FindFirstChild(Shared.NET)
	if f and not f:IsA("Folder") then
		f:Destroy()
		f = nil
	end
	if not f then
		local nf = Instance.new("Folder")
		nf.Name = Shared.NET
		nf.Parent = ReplicatedStorage
		f = nf
	end
	folder = f :: Folder
	local rf = (f :: Folder):FindFirstChild("Request")
	if not rf or not rf:IsA("RemoteFunction") then
		if rf then
			rf:Destroy()
		end
		rf = Instance.new("RemoteFunction")
		rf.Name = "Request"
		rf.Parent = f
	end
	local re = (f :: Folder):FindFirstChild("Event")
	if not re or not re:IsA("RemoteEvent") then
		if re then
			re:Destroy()
		end
		re = Instance.new("RemoteEvent")
		re.Name = "Event"
		re.Parent = f
	end
	request = rf :: RemoteFunction
	event = re :: RemoteEvent;
	(request :: RemoteFunction).OnServerInvoke = function(p: Player, op: any, payload: any)
		if typeof(p) ~= "Instance" or not p:IsA("Player") or p.Parent ~= Players then
			return { ok = false }
		end
		if type(op) ~= "string" or #op > 24 then
			return { ok = false, code = "op" }
		end
		local fn = handlers[op]
		if not fn then
			return { ok = false, code = "op" }
		end
		if payload ~= nil and type(payload) ~= "table" then
			return { ok = false, code = "payload" }
		end
		if not allow(p) then
			return BUSY
		end
		local ok, res = pcall(fn, p, payload or {})
		if not ok then
			warn("[GwangalliShopCrew] request " .. op .. ": " .. tostring(res))
			return { ok = false, code = "error", msg = "앗, 잠시 후 다시 말 걸어 주세요" }
		end
		return if type(res) == "table" then res else { ok = true }
	end;
	(event :: RemoteEvent).OnServerEvent:Connect(function() end)
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
	folder:SetAttribute("Version", Shared.VERSION)
end

function Net.on(op: string, fn: (Player, any) -> any)
	handlers[op] = fn
end

function Net.fire(p: Player, kind: string, data: any?)
	local e = event
	if e and p.Parent == Players then
		e:FireClient(p, kind, data or {})
	end
end

function Net.fireAll(kind: string, data: any?)
	local e = event
	if e then
		e:FireAllClients(kind, data or {})
	end
end

-- players whose character is within r studs of pos
function Net.near(pos: Vector3, r: number): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - pos).Magnitude <= r then
			table.insert(out, p)
		end
	end
	return out
end

function Net.fireNear(pos: Vector3, r: number, kind: string, data: any?)
	for _, p in Net.near(pos, r) do
		Net.fire(p, kind, data)
	end
end

return Net
