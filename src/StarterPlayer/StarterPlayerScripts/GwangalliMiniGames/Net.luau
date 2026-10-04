--!strict
-- GwangalliMiniGames/Net: the client's only link to the minigame server (ReplicatedStorage.
-- GwangalliMiniGames: Request / Update / Query). Every money / result decision is the server's;
-- this module only sends intents ("I want to sit here with ₩10,000", "my move is H8").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local MS: any = nil
local request: RemoteEvent? = nil
local query: RemoteFunction? = nil
local handlers: { [string]: { (any) -> () } } = {}

function Net.init(ms: any): boolean
	MS = ms
	local folder = ReplicatedStorage:WaitForChild(MS.FolderName, 60)
	if not folder then
		return false
	end
	request = folder:WaitForChild(MS.Remote.Request, 30) :: RemoteEvent
	query = folder:WaitForChild(MS.Remote.Query, 30) :: RemoteFunction
	local update = folder:WaitForChild(MS.Remote.Update, 30) :: RemoteEvent
	if not request or not update then
		return false
	end
	update.OnClientEvent:Connect(function(kind: any, payload: any)
		if type(kind) ~= "string" then
			return
		end
		if kind == MS.Kinds.ping then
			Net.send("ping", { s = payload and payload.s })
			return
		end
		local list = handlers[kind]
		if list then
			for _, fn in list do
				task.spawn(fn, payload)
			end
		end
	end)
	return true
end

function Net.send(action: string, payload: { [string]: any }?)
	if request then
		request:FireServer(action, payload or {})
	end
end

function Net.on(kind: string, fn: (any) -> ())
	local list = handlers[kind]
	if not list then
		list = {}
		handlers[kind] = list
	end
	table.insert(list, fn)
end

function Net.query(what: string): any
	if not query then
		return nil
	end
	local ok, res = pcall(function()
		return (query :: RemoteFunction):InvokeServer(what)
	end)
	return if ok then res else nil
end

return Net
