-- GwangalliPhone/Dest: the Destination list (quick travel / taxi / quest targets) and positions.
--   * list: the server-published ReplicatedStorage.GwangalliTravel attribute "Destinations" (JSON
--     { id, name, order }), because with StreamingEnabled the client only has nearby parts
--     (see src/ServerScriptService/GwangalliTravel.server.luau). Before it arrives: the live tagged
--     parts plus the static table in MapData.
--   * position(name): a live tagged part (exact) > the last position seen this session > MapData.
--   * travel(id): the existing quick-travel remote (FireServer("travel", id)); results come back as
--     OnClientEvent("result", ok, message) and are forwarded to onResult listeners.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(script.Parent:WaitForChild("MapData"))

local TAG = "Destination"

local Dest = {}
Dest.remote = nil :: RemoteEvent?

local published: { { id: string, name: string, order: number } } = {}
local live: { [string]: BasePart } = {}
local seen: { [string]: Vector3 } = {}
local changedListeners: { () -> () } = {}
local resultListeners: { (boolean, string) -> () } = {}

function Dest.onChanged(fn: () -> ())
	table.insert(changedListeners, fn)
end
function Dest.onResult(fn: (boolean, string) -> ())
	table.insert(resultListeners, fn)
end

local changeQueued = false
local function fireChanged()
	if changeQueued then
		return
	end
	changeQueued = true
	task.delay(0.5, function() -- streaming adds parts in bursts: coalesce
		changeQueued = false
		for _, fn in changedListeners do
			task.spawn(fn)
		end
	end)
end

local function nameOf(part: Instance): string
	local n = part:GetAttribute("DisplayName")
	if type(n) == "string" and n ~= "" then
		return n
	end
	return part.Name
end

local function onAdded(inst: Instance)
	if inst:IsA("BasePart") then
		local name = nameOf(inst)
		live[name] = inst
		seen[name] = inst.Position
		fireChanged()
	end
end

local function onRemoved(inst: Instance)
	if inst:IsA("BasePart") then
		local name = nameOf(inst)
		if live[name] == inst then
			live[name] = nil
			fireChanged()
		end
	end
end

local function parsePublished()
	local remote = Dest.remote
	if not remote then
		return
	end
	local raw = remote:GetAttribute("Destinations")
	local list = {}
	if type(raw) == "string" and raw ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(decoded) == "table" then
			for i, e in decoded do
				if type(e) == "table" and type(e.id) == "string" then
					table.insert(list, {
						id = e.id,
						name = if type(e.name) == "string" then e.name else e.id,
						order = if type(e.order) == "number" then e.order else 1000 + i,
					})
				end
			end
		end
	end
	published = list
	fireChanged()
end

function Dest.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(onAdded)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(onRemoved)
	for _, inst in CollectionService:GetTagged(TAG) do
		onAdded(inst)
	end
	task.spawn(function()
		local remote = ReplicatedStorage:FindFirstChild("GwangalliTravel")
		while not (remote and remote:IsA("RemoteEvent")) do
			remote = ReplicatedStorage:WaitForChild("GwangalliTravel", 30)
		end
		local re = remote :: RemoteEvent
		Dest.remote = re
		re:GetAttributeChangedSignal("Destinations"):Connect(parsePublished)
		re.OnClientEvent:Connect(function(kind: any, ok: any, message: any)
			if kind ~= "result" then
				return
			end
			local msg = if type(message) == "string" then message else ""
			for _, fn in resultListeners do
				task.spawn(fn, ok == true, msg)
			end
		end)
		parsePublished()
	end)
end

-- Sorted list of { id, name, order }.
function Dest.list(): { { id: string, name: string, order: number } }
	if #published > 0 then
		return published
	end
	local names: { [string]: boolean } = {}
	local out = {}
	for name in live do
		names[name] = true
	end
	for name in MapData.Destinations do
		names[name] = true
	end
	for name in names do
		table.insert(out, { id = name, name = name, order = 1000 })
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

-- Canonical Destination name for a possibly-inexact one (exact > case-insensitive > substring).
function Dest.resolve(name: string?): string?
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local list = Dest.list()
	for _, e in list do
		if e.name == name or e.id == name then
			return e.name
		end
	end
	if live[name] or seen[name] or MapData.Destinations[name] or MapData.Extra[name] then
		return name
	end
	local lower = string.lower(name)
	for _, e in list do
		local n = string.lower(e.name)
		if string.find(n, lower, 1, true) or string.find(lower, n, 1, true) then
			return e.name
		end
	end
	return name
end

local function v3(t: { number }?): Vector3?
	if t then
		return Vector3.new(t[1], t[2], t[3])
	end
	return nil
end

function Dest.position(name: string?): Vector3?
	if type(name) ~= "string" then
		return nil
	end
	local part = live[name]
	if part then
		if part.Parent and part:IsDescendantOf(workspace) then
			local p = part.Position
			seen[name] = p
			return p
		end
		live[name] = nil
	end
	local p = seen[name] or v3(MapData.Destinations[name]) or v3(MapData.Extra[name])
	if p then
		return p
	end
	local resolved = Dest.resolve(name)
	if resolved and resolved ~= name then
		return Dest.position(resolved)
	end
	-- substring match over the static table (e.g. a quest that says "헬스장")
	for n, t in MapData.Extra do
		if string.find(n, name, 1, true) then
			return v3(t)
		end
	end
	return nil
end

function Dest.idFor(name: string): string
	for _, e in Dest.list() do
		if e.name == name then
			return e.id
		end
	end
	return name
end

-- Quick travel through the existing GwangalliTravel remote. Returns false + reason when unavailable.
function Dest.travel(id: string): (boolean, string?)
	local remote = Dest.remote
	if not remote then
		return false, "이동 서비스를 준비하는 중이에요"
	end
	local ok = pcall(remote.FireServer, remote, "travel", id)
	return ok, nil
end

return Dest
