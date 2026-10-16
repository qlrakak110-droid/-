-- GwangalliClinic/Net: the remotes and the request router.
--   ClinicRequest  RemoteFunction   client -> server (op, payload) -> { ok, code?, message?, ... }
--   ClinicEvent    RemoteEvent      server -> one client { kind = ..., ... }
-- Every op has a rate class (token bucket per player, Config.Rate), payloads must be tables, ops are
-- whitelisted, and handler errors are caught and answered with a Korean message.
-- Net.invoke(player, op, payload) runs the same router from server code (tests / other add-ons).

local Players = game:GetService("Players")

local Net = {}

local S: any
local C: any
local request: RemoteFunction
local event: RemoteEvent

type Bucket = { tokens: number, last: number }
local handlers: { [string]: { cls: string, fn: (Player, any) -> any } } = {}
local buckets: { [Player]: { [string]: Bucket } } = {}

local function take(player: Player, cls: string): boolean
	local c = C.Rate[cls] or C.Rate.ui
	local pb = buckets[player]
	if not pb then
		pb = {}
		buckets[player] = pb
	end
	local b = pb[cls]
	local t = os.clock()
	if not b then
		b = { tokens = c.burst, last = t }
		pb[cls] = b
	end
	b.tokens = math.min(c.burst, b.tokens + (t - b.last) * c.rate)
	b.last = t
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function Net.fail(code: string, ...: any): any
	return { ok = false, code = code, message = S.err(code, ...) }
end

function Net.handle(op: string, cls: string, fn: (Player, any) -> any)
	handlers[op] = { cls = cls, fn = fn }
end

function Net.fire(player: Player, payload: any)
	if player and player.Parent == Players and event then
		event:FireClient(player, payload)
	end
end

function Net.fireAll(payload: any)
	if event then
		event:FireAllClients(payload)
	end
end

function Net.toast(player: Player, title: string, body: string?, tone: string?)
	Net.fire(player, { kind = "toast", title = title, body = body or "", tone = tone or "info" })
end

-- a staff dialogue line on the client (who = "desk" | "doctor" | "nurse" | "nurse2" | "pharm" | "check")
function Net.line(player: Player, who: string, text: string, extra: any?)
	local p: any = { kind = "line", who = who, text = text }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	Net.fire(player, p)
end

local function dispatch(player: Player, op: any, payload: any): any
	if type(op) ~= "string" or #op > 16 then
		return Net.fail("bad")
	end
	local h = handlers[op]
	if not h then
		return Net.fail("bad")
	end
	if payload == nil then
		payload = {}
	end
	if type(payload) ~= "table" then
		return Net.fail("bad")
	end
	if not take(player, h.cls) then
		return Net.fail("rate")
	end
	local ok, res = pcall(h.fn, player, payload)
	if not ok then
		warn("[GwangalliClinic] op", op, "failed:", res)
		return Net.fail("error")
	end
	if type(res) ~= "table" then
		return { ok = res == true }
	end
	return res
end

-- server-side entry with the same validation (other server add-ons / automated tests)
function Net.invoke(player: Player, op: string, payload: any?): any
	return dispatch(player, op, payload or {})
end

function Net.create(k: any)
	S = k.S
	C = S.Config
	local shared = k.sharedModule :: Instance
	local old = shared:FindFirstChild(S.NAMES.Remotes)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = S.NAMES.Remotes
	request = Instance.new("RemoteFunction")
	request.Name = S.NAMES.Request
	request.Parent = folder
	event = Instance.new("RemoteEvent")
	event.Name = S.NAMES.Event
	event.Parent = folder
	request.OnServerInvoke = dispatch
	folder.Parent = shared -- parented last: a client that finds the folder finds both remotes
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
end

return Net
