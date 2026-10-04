-- Net: the client end of the building system's remotes (ReplicatedStorage.GwangalliBuildingsRemotes).
--   Net.request(op, payload) -> result table (never errors)
--   Net.call(op, payload)    -> result, and shows result.msg as a toast
--   Net.send(op, payload)    fire-and-forget (cheap, frequent actions)
--   Net.on(kind, fn)         server -> client events

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local UI = require(script.Parent:WaitForChild("UI"))

local Net = {}

local remotes = ReplicatedStorage:WaitForChild(Shared.Names.REMOTES)
local requestFn = remotes:WaitForChild("Request") :: RemoteFunction
local eventRe = remotes:WaitForChild("Event") :: RemoteEvent
local handlers: { [string]: { (any) -> () } } = {}

function Net.request(op: string, payload: any?): any
	local ok, res = pcall(function()
		return requestFn:InvokeServer(op, payload or {})
	end)
	if not ok then
		warn("[GwangalliBuildings] request " .. op .. ": " .. tostring(res))
		return { ok = false, msg = "연결이 불안정해요. 다시 시도해 주세요" }
	end
	if type(res) ~= "table" then
		return { ok = res == true }
	end
	return res
end

function Net.call(op: string, payload: any?): any
	local res = Net.request(op, payload)
	if type(res.msg) == "string" and res.msg ~= "" then
		UI.toast(res.msg, if res.ok then "ok" else "warn")
	end
	return res
end

function Net.send(op: string, payload: any?)
	eventRe:FireServer(op, payload or {})
end

function Net.on(kind: string, fn: (any) -> ())
	handlers[kind] = handlers[kind] or {}
	table.insert(handlers[kind], fn)
end

eventRe.OnClientEvent:Connect(function(kind: any, data: any)
	local list = handlers[kind]
	if not list then
		return
	end
	for _, fn in list do
		task.spawn(function()
			local ok, err = pcall(fn, if type(data) == "table" then data else {})
			if not ok then
				warn("[GwangalliBuildings] event " .. tostring(kind) .. ": " .. tostring(err))
			end
		end)
	end
end)

return Net
