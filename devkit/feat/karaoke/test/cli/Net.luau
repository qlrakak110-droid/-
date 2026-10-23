-- GwangalliKaraokePlus/Net (client): requests with a timeout and event dispatch.
--   Net.request(op, payload?) -> { ok, code?, message?, ... }    (yields; never errors)
--   Net.call(op, payload?, onDone?)                             (fire-and-forget in a thread, toasts errors)
--   Net.on(kind, fn)          KPEvent (reliable, server -> me)
--   Net.onLive(kind, fn)      KPLive (unreliable fx / judgements of my room)

local Net = {}

local K: any
local request: RemoteFunction
local handlers: { [string]: { (any) -> () } } = {}
local liveHandlers: { [string]: { (any) -> () } } = {}

local TIMEOUT = 12

function Net.request(op: string, payload: any?): any
	local box = { done = false, res = nil :: any }
	task.spawn(function()
		local ok, res = pcall(request.InvokeServer, request, op, payload or {})
		if box.done then
			return
		end
		box.done = true
		box.res = if ok and type(res) == "table" then res else { ok = false, code = "error", message = "잠시 후에 다시 시도해 주세요" }
	end)
	local t0 = os.clock()
	while not box.done do
		if os.clock() - t0 > TIMEOUT then
			box.done = true
			return { ok = false, code = "timeout", message = "연결이 느려요 · 다시 시도해 주세요" }
		end
		task.wait(0.03)
	end
	return box.res
end

-- runs the request in its own thread; failed requests show their Korean message
function Net.call(op: string, payload: any?, onDone: ((any) -> ())?, quiet: boolean?)
	task.spawn(function()
		local res = Net.request(op, payload)
		if not res.ok and not quiet and res.code ~= "rate" then
			K.Kit.toast(res.message or "잠시 후에 다시 시도해 주세요", nil, "warn")
		end
		if onDone then
			local ok, err = pcall(onDone, res)
			if not ok then
				warn("[GwangalliKaraokePlus]", op, "callback:", err)
			end
		end
	end)
end

function Net.on(kind: string, fn: (any) -> ())
	handlers[kind] = handlers[kind] or {}
	table.insert(handlers[kind], fn)
end

function Net.onLive(kind: string, fn: (any) -> ())
	liveHandlers[kind] = liveHandlers[kind] or {}
	table.insert(liveHandlers[kind], fn)
end

local function dispatch(map: { [string]: { (any) -> () } }, payload: any)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return
	end
	for _, fn in map[payload.kind] or {} do
		local ok, err = pcall(fn, payload)
		if not ok then
			warn("[GwangalliKaraokePlus] event", payload.kind, err)
		end
	end
end

function Net.init(k: any)
	K = k
	local remotes = k.remotes :: Instance
	request = remotes:WaitForChild(k.S.NAMES.Request) :: RemoteFunction
	local ev = remotes:WaitForChild(k.S.NAMES.Event) :: RemoteEvent
	local live = remotes:WaitForChild(k.S.NAMES.Live) :: any
	ev.OnClientEvent:Connect(function(p)
		dispatch(handlers, p)
	end)
	live.OnClientEvent:Connect(function(p)
		dispatch(liveHandlers, p)
	end)
end

return Net
