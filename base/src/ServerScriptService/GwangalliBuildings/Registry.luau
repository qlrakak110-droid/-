-- Registry: the server-side index of every building / unit / shop plus the remote plumbing shared by
-- all services.
--   Registry.add(rec)                       register a planned building (units, shops)
--   Registry.get(id) / unit(id) / shop(id)  lookups
--   Registry.on(op, fn)                     handle a client request op: fn(player, payload) -> result table
--   Registry.fire(player, kind, data)       server -> client event
--   Registry.toast(player, text, kind?)     small notice on the player's screen
--   Registry.char(player)                   character, root part, humanoid (or nil)
--   Registry.near(player, pos, dist)        reach check (server authority for every interaction)
--   Registry.buildingAt(pos)                -> rec?, localPos
--   Registry.now()                          server time (the clocks every client animates with)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Names = Shared.Names
local Util = Shared.Util

local Registry = {}
Registry.recs = {} :: { any }
Registry.byId = {} :: { [string]: any }
Registry.units = {} :: { [string]: any }
Registry.shops = {} :: { [string]: any }
Registry.handlers = {} :: { [string]: (Player, any) -> any }
Registry.root = nil :: Instance?
Registry.parked = nil :: Instance?
Registry.Builder = nil :: any

local remotes: any
local requestFn: any
local eventRe: any

-- per-player token bucket against request spam
local buckets: { [Player]: { t: number, n: number } } = {}
local RATE, BURST = 12, 24

function Registry.init(opts: any)
	Registry.root = opts.root
	Registry.parked = opts.parked
	Registry.Builder = opts.Builder
	remotes = ReplicatedStorage:FindFirstChild(Names.REMOTES)
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = Names.REMOTES
		remotes.Parent = ReplicatedStorage
	end
	requestFn = remotes:FindFirstChild("Request")
	if not requestFn then
		requestFn = Instance.new("RemoteFunction")
		requestFn.Name = "Request"
		requestFn.Parent = remotes
	end
	eventRe = remotes:FindFirstChild("Event")
	if not eventRe then
		eventRe = Instance.new("RemoteEvent")
		eventRe.Name = "Event"
		eventRe.Parent = remotes
	end
	requestFn.OnServerInvoke = function(player: Player, op: any, payload: any): any
		if type(op) ~= "string" then
			return { ok = false, msg = "bad request" }
		end
		local now = os.clock()
		local b = buckets[player]
		if not b then
			b = { t = now, n = BURST }
			buckets[player] = b
		end
		b.n = math.min(BURST, b.n + (now - b.t) * RATE)
		b.t = now
		if b.n < 1 then
			return { ok = false, msg = "잠시 후 다시 시도해 주세요" }
		end
		b.n -= 1
		local h = Registry.handlers[op]
		if not h then
			return { ok = false, msg = "unknown op " .. op }
		end
		local ok, res = pcall(h, player, if type(payload) == "table" then payload else {})
		if not ok then
			warn("[GwangalliBuildings] request " .. op .. " failed: " .. tostring(res))
			return { ok = false, msg = "처리 중 문제가 생겼어요" }
		end
		if type(res) ~= "table" then
			return { ok = res == true }
		end
		return res
	end
	-- client -> server fire-and-forget (cheap actions like grill taps)
	eventRe.OnServerEvent:Connect(function(player: Player, op: any, payload: any)
		if type(op) ~= "string" then
			return
		end
		local h = Registry.handlers[op]
		if h then
			local ok, err = pcall(h, player, if type(payload) == "table" then payload else {})
			if not ok then
				warn("[GwangalliBuildings] event " .. op .. ": " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
end

function Registry.add(rec: any)
	table.insert(Registry.recs, rec)
	Registry.byId[rec.id] = rec
	for id, u in rec.units do
		Registry.units[id] = u
	end
	for id, s in rec.shops do
		Registry.shops[id] = s
	end
end

function Registry.get(id: string): any
	return Registry.byId[id]
end
function Registry.unit(id: string?): any
	return if id then Registry.units[id] else nil
end
function Registry.shop(id: string?): any
	return if id then Registry.shops[id] else nil
end
function Registry.unitCount(): number
	local n = 0
	for _ in Registry.units do
		n += 1
	end
	return n
end
function Registry.shopCount(): number
	local n = 0
	for _ in Registry.shops do
		n += 1
	end
	return n
end

function Registry.on(op: string, fn: (Player, any) -> any)
	Registry.handlers[op] = fn
end

function Registry.fire(player: Player, kind: string, data: any?)
	if eventRe and player.Parent == Players then
		eventRe:FireClient(player, kind, data or {})
	end
end

function Registry.fireAll(kind: string, data: any?)
	if eventRe then
		eventRe:FireAllClients(kind, data or {})
	end
end

function Registry.toast(player: Player, text: string, kind: string?)
	Registry.fire(player, "toast", { text = text, kind = kind or "info" })
end

function Registry.char(player: Player): (Model?, BasePart?, Humanoid?)
	local c = player.Character
	if not c then
		return nil, nil, nil
	end
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return c, nil, nil
	end
	return c, root, hum
end

function Registry.pos(player: Player): Vector3?
	local _, root = Registry.char(player)
	return if root then root.Position else nil
end

function Registry.near(player: Player, target: any, dist: number): boolean
	local p = Registry.pos(player)
	if not p then
		return false
	end
	local tp: Vector3
	if typeof(target) == "Vector3" then
		tp = target
	elseif typeof(target) == "Instance" then
		if target:IsA("BasePart") then
			tp = target.Position
		elseif target:IsA("Model") then
			tp = target:GetPivot().Position
		elseif target:IsA("Attachment") then
			tp = target.WorldPosition
		else
			return false
		end
	elseif typeof(target) == "CFrame" then
		tp = target.Position
	else
		return false
	end
	return (p - tp).Magnitude <= dist
end

function Registry.buildingAt(pos: Vector3, pad: number?): (any?, Vector3?)
	for _, rec in Registry.recs do
		local l = rec.cf:PointToObjectSpace(pos)
		local g = pad or 0
		if l.X >= -rec.W / 2 - g and l.X <= rec.W / 2 + g and l.Z >= -g and l.Z <= rec.D + g and l.Y >= rec.floors[1].y - 2 and l.Y <= rec.roofY + 14 then
			return rec, l
		end
	end
	return nil, nil
end

function Registry.now(): number
	return workspace:GetServerTimeNow()
end

-- teleports that are not cheating (the life game's anti-teleport check, when it exists)
function Registry.allowTeleport(player: Player, seconds: number?)
	local api = game:GetService("ServerStorage"):FindFirstChild("GwangalliGameplayAPI")
	if api and api:IsA("BindableFunction") then
		pcall(function()
			(api :: BindableFunction):Invoke("allowTeleport", player, seconds or 3)
		end)
	end
end

function Registry.teleport(player: Player, cf: CFrame)
	local c, root = Registry.char(player)
	if c and root then
		Registry.allowTeleport(player, 3)
		-- moving the root part moves the whole (welded) avatar; the studio engine also only follows a
		-- root-part move for the local avatar
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = cf
	end
end

function Registry.json(v: any): string
	local ok, s = pcall(HttpService.JSONEncode, HttpService, v)
	return if ok then s else "{}"
end

function Registry.unjson(s: any): any
	if type(s) ~= "string" then
		return nil
	end
	local ok, v = pcall(HttpService.JSONDecode, HttpService, s)
	return if ok then v else nil
end

Registry.Util = Util
return Registry
