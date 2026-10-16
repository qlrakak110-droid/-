-- GwangalliClinic/Net (client): ClinicRequest with a timeout (never hangs the UI) and the ClinicEvent bus.
--   Net.call(op, payload?) -> reply table ({ ok = false, code = "timeout" } when the server is slow)
--   Net.on(kind, fn)        ClinicEvent payloads by kind ("visit" | "call" | "line" | "toast" | "done" | ...)

local Net = {}

local S: any
local request: RemoteFunction? = nil
local listeners: { [string]: { (any) -> () } } = {}
local busy: { [string]: boolean } = {}

function Net.on(kind: string, fn: (any) -> ())
	listeners[kind] = listeners[kind] or {}
	table.insert(listeners[kind], fn)
end

function Net.emit(kind: string, payload: any)
	local list = listeners[kind]
	if not list then
		return
	end
	for _, fn in list do
		task.spawn(function()
			local ok, err = pcall(fn, payload)
			if not ok then
				warn("[GwangalliClinic] event", kind, "handler:", err)
			end
		end)
	end
end

-- one request per op at a time (double taps never send twice)
function Net.call(op: string, payload: any?, timeout: number?): any
	if not request then
		return { ok = false, code = "error", message = S.err("error") }
	end
	if busy[op] then
		return { ok = false, code = "busy", message = S.err("busy") }
	end
	busy[op] = true
	local box = { done = false, res = nil :: any }
	task.spawn(function()
		local ok, res = pcall(function()
			return (request :: RemoteFunction):InvokeServer(op, payload or {})
		end)
		box.res = if ok then res else nil
		box.done = true
	end)
	local t0 = os.clock()
	while not box.done and os.clock() - t0 < (timeout or 10) do
		task.wait(0.03)
	end
	busy[op] = nil
	if not box.done then
		return { ok = false, code = "timeout", message = "서버 응답이 늦어요. 잠시 후 다시 해 주세요" }
	end
	if type(box.res) ~= "table" then
		return { ok = false, code = "error", message = S.err("error") }
	end
	return box.res
end

function Net.init(ctx: any)
	S = ctx.S
	local folder = ctx.sharedModule:WaitForChild(S.NAMES.Remotes, 60)
	if not folder then
		warn("[GwangalliClinic] remotes missing")
		return false
	end
	request = folder:WaitForChild(S.NAMES.Request, 20) :: RemoteFunction
	local event = folder:WaitForChild(S.NAMES.Event, 20) :: RemoteEvent
	if not request or not event then
		return false
	end
	event.OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and type(payload.kind) == "string" then
			Net.emit(payload.kind, payload)
		end
	end)
	return true
end

return Net
