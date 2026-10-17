--!strict
-- GwangalliDecorPlus/Net: Request wrapper (rid for every mutating call, timeout, busy flag) + Event fan-out.
--   Net.start() (waits for ReplicatedStorage.GwangalliDecorPlusRemotes) / Net.ready()
--   Net.call(action, payload?) -> result (yields; never throws; { ok = false, code = "timeout" } on timeout)
--   Net.on(kind, fn) -> disconnect

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliDecorShared"))
local Config, Text = Shared.Config, Shared.Text

local Net = {}

local folder: Instance? = nil
local request: RemoteFunction? = nil
local listeners: { [string]: { (any) -> () } } = {}
local seq = 0

local MUTATING = { place = true, move = true, moveMany = true, color = true, remove = true, restore = true, sellStored = true, finish = true, preset = true, like = true, guestbook = true, gbDelete = true, photo = true, set = true }

function Net.start(): boolean
	folder = ReplicatedStorage:WaitForChild(Config.REMOTES_NAME, 120)
	if not folder then
		return false
	end
	request = folder:WaitForChild("Request", 30) :: RemoteFunction
	local ev = folder:WaitForChild("Event", 30) :: RemoteEvent
	if not request or not ev then
		return false
	end
	ev.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.kind) ~= "string" then
			return
		end
		local l = listeners[payload.kind]
		if l then
			for _, fn in table.clone(l) do
				task.spawn(fn, payload)
			end
		end
		local all = listeners["*"]
		if all then
			for _, fn in table.clone(all) do
				task.spawn(fn, payload)
			end
		end
	end)
	return true
end

function Net.ready(): boolean
	return folder ~= nil and folder.Parent ~= nil and folder:GetAttribute("Ready") == true and folder:GetAttribute("Dormant") ~= true
end

function Net.folder(): Instance?
	return folder
end

function Net.call(action: string, payload: any?): any
	if not request then
		return { ok = false, code = "booting", msg = Text.reason("booting") }
	end
	local pl = payload or {}
	if MUTATING[action] and pl.rid == nil then
		seq += 1
		pl.rid = string.sub(HttpService:GenerateGUID(false), 1, 12) .. tostring(seq % 1000)
	end
	local done = false
	local result: any = nil
	task.spawn(function()
		local ok, r = pcall(function()
			return (request :: RemoteFunction):InvokeServer(action, pl)
		end)
		result = if ok and type(r) == "table" then r else { ok = false, code = "bad", msg = Text.reason("bad") }
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 12 do
		task.wait()
	end
	if not done then
		return { ok = false, code = "timeout", msg = Text.reason("timeout") }
	end
	if result.ok == false and not result.msg then
		result.msg = Text.reason(result.code)
	end
	return result
end

function Net.on(kind: string, fn: (any) -> ()): () -> ()
	local l = listeners[kind]
	if not l then
		l = {}
		listeners[kind] = l
	end
	table.insert(l, fn)
	return function()
		local i = table.find(l, fn)
		if i then
			table.remove(l, i)
		end
	end
end

return Net
