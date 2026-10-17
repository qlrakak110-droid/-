-- GwangalliShopCrew client / Net: the add-on's remotes (ReplicatedStorage.GwangalliShopCrewNet, made by the server).
--   Net.init(folder)   Net.on(kind, fn(data))   Net.request(op, payload?) -> table (never errors)

local Net = {}

local rf: RemoteFunction? = nil
local handlers: { [string]: { (any) -> () } } = {}

function Net.init(folder: Instance): boolean
	local r = folder:WaitForChild("Request", 30)
	local e = folder:WaitForChild("Event", 30)
	if not (r and r:IsA("RemoteFunction") and e and e:IsA("RemoteEvent")) then
		return false
	end
	rf = r :: RemoteFunction;
	(e :: RemoteEvent).OnClientEvent:Connect(function(kind, data)
		if type(kind) ~= "string" then
			return
		end
		for _, fn in handlers[kind] or {} do
			task.spawn(function()
				local ok, err = pcall(fn, if type(data) == "table" then data else {})
				if not ok then
					warn("[GwangalliShopCrew] " .. kind .. ": " .. tostring(err))
				end
			end)
		end
	end)
	return true
end

function Net.on(kind: string, fn: (any) -> ())
	handlers[kind] = handlers[kind] or {}
	table.insert(handlers[kind], fn)
end

function Net.request(op: string, payload: any?): any
	local r = rf
	if not r then
		return { ok = false }
	end
	local ok, res = pcall(function()
		return r:InvokeServer(op, payload)
	end)
	if not ok or type(res) ~= "table" then
		return { ok = false }
	end
	return res
end

return Net
