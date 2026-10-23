-- GwangalliKaraokePlus/Net: the remotes and the request router.
--   KPRequest  RemoteFunction   client -> server (op, payload) -> { ok, code?, message?, ... }
--   KPEvent    RemoteEvent      server -> one client
--   KPLive     UnreliableRemoteEvent (RemoteEvent fallback)  server -> room members (fx, judgements)
-- Every op has a rate class (token bucket per player), payloads must be tables, and handler errors
-- are caught and answered with a Korean message.

local Players = game:GetService("Players")

local Net = {}

local S: any
local folder: Folder
local request: RemoteFunction
local event: RemoteEvent
local live: any

type Bucket = { tokens: number, last: number }
local CLASSES = {
	ui = { rate = 5, burst = 12 },
	money = { rate = 0.8, burst = 3 },
	game = { rate = 10, burst = 20 },
	fx = { rate = 4, burst = 8 },
}
local handlers: { [string]: { cls: string, fn: (Player, any) -> any } } = {}
local buckets: { [Player]: { [string]: Bucket } } = {}

local function take(player: Player, cls: string): boolean
	local c = CLASSES[cls] or CLASSES.ui
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
	if player and player.Parent == Players then
		event:FireClient(player, payload)
	end
end

-- reliable to several players
function Net.fireMany(players: { Player }, payload: any)
	for _, p in players do
		Net.fire(p, payload)
	end
end

-- unreliable (fx / judgements); small payloads only
function Net.live(players: { Player }, payload: any)
	for _, p in players do
		if p.Parent == Players then
			live:FireClient(p, payload)
		end
	end
end

-- Korean toast on the client (our own HUD)
function Net.toast(player: Player, title: string, body: string?, kind: string?)
	Net.fire(player, { kind = "toast", title = title, body = body or "", tone = kind or "info" })
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
		warn("[GwangalliKaraokePlus] op", op, "failed:", res)
		return Net.fail("error")
	end
	if type(res) ~= "table" then
		return { ok = res == true }
	end
	return res
end

function Net.create(k: any)
	S = k.S
	local shared = k.sharedModule :: Instance
	local old = shared:FindFirstChild(S.NAMES.Remotes)
	if old then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = S.NAMES.Remotes
	request = Instance.new("RemoteFunction")
	request.Name = S.NAMES.Request
	request.Parent = folder
	event = Instance.new("RemoteEvent")
	event.Name = S.NAMES.Event
	event.Parent = folder
	local okU, u = pcall(Instance.new, "UnreliableRemoteEvent")
	if okU and u then
		live = u
	else
		live = Instance.new("RemoteEvent")
	end
	live.Name = S.NAMES.Live
	live.Parent = folder
	request.OnServerInvoke = dispatch
	folder.Parent = shared -- parented last: a client that finds the folder finds every remote
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
end

return Net
