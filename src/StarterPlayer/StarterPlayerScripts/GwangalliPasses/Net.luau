-- GwangalliPasses/Net (client): the add-on's remotes (ReplicatedStorage.GwangalliPassesRemotes).
--   Net.request(op, payload?) -> result table (yields; never errors: { ok = false, message = ... } offline)
--   Net.on(kind, fn(payload))        server events by payload.kind
--   Net.ready() -> { garage, gate, jail, ko, market, kofx, plate, neon }   features whose hooks are live
--   Net.connected() -> boolean

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Net = {}

local P: any
local folder: Instance? = nil
local requestFn: RemoteFunction? = nil
local listeners: { [string]: { (any) -> () } } = {}
local readyCache: { [string]: boolean } = {}
local readyEv = Instance.new("BindableEvent")
Net.readyChanged = readyEv.Event

function Net.on(kind: string, fn: (any) -> ())
	listeners[kind] = listeners[kind] or {}
	table.insert(listeners[kind], fn)
end

function Net.connected(): boolean
	return requestFn ~= nil
end

function Net.ready(): { [string]: boolean }
	return readyCache
end

function Net.request(op: string, payload: any?): { [string]: any }
	local t0 = os.clock()
	while not requestFn and os.clock() - t0 < 8 do
		task.wait(0.25)
	end
	local fn = requestFn
	if not fn then
		return { ok = false, code = "offline", message = P.Lines.t("offline") }
	end
	local ok, res = pcall(function()
		return fn:InvokeServer(op, payload)
	end)
	if not ok or type(res) ~= "table" then
		return { ok = false, code = "offline", message = P.Lines.t("offline") }
	end
	return res
end

local function readReady()
	local f = folder
	if not f then
		return
	end
	local raw = f:GetAttribute(P.Attr.Ready)
	if type(raw) == "string" then
		local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(t) == "table" then
			readyCache = t
			readyEv:Fire(t)
		end
	end
end

function Net.start(ctx: any)
	P = ctx.P
	task.spawn(function()
		local f = ReplicatedStorage:WaitForChild(P.REMOTES, 120)
		if not f then
			warn("[GwangalliPasses] server remotes missing: is the GwangalliPasses Script in ServerScriptService?")
			return
		end
		folder = f
		local rf = f:WaitForChild(P.REQUEST, 30)
		local re = f:WaitForChild(P.EVENT, 30)
		if rf and rf:IsA("RemoteFunction") then
			requestFn = rf
		end
		if re and re:IsA("RemoteEvent") then
			re.OnClientEvent:Connect(function(payload: any)
				if type(payload) ~= "table" or type(payload.kind) ~= "string" then
					return
				end
				for _, fn in listeners[payload.kind] or {} do
					task.spawn(fn, payload)
				end
			end)
		end
		readReady()
		f:GetAttributeChangedSignal(P.Attr.Ready):Connect(readReady)
	end)
end

return Net
