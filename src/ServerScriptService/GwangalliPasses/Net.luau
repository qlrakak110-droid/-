-- GwangalliPasses/Net (server): ReplicatedStorage.GwangalliPassesRemotes
--   Request (RemoteFunction)  client -> server  (op: string, payload: table?) -> { ok, code?, message?, ... }
--   Event   (RemoteEvent)     server -> client  payload { kind = ..., ... }   (client -> server is ignored)
-- Every request passes a per-player token bucket (Config.NET) and the op's own cooldown; handlers get a
-- shallow-copied payload table (or {}) and must type-check every field they read.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local P: any, Config: any, Util: any
local folder: Folder? = nil
local requestFn: RemoteFunction? = nil
local eventRe: RemoteEvent? = nil
local handlers: { [string]: { fn: (Player, any) -> any, cooldown: number } } = {}
local last: { [Player]: { [string]: number } } = {}
local bucket: any = nil

function Net.on(op: string, cooldown: number, fn: (Player, any) -> any)
	handlers[op] = { fn = fn, cooldown = cooldown }
end

function Net.send(player: Player, payload: any)
	if eventRe and Util.isPlayer(player) then
		pcall(eventRe.FireClient, eventRe, player, payload)
	end
end

function Net.sendNear(pos: Vector3, range: number, payload: any, extra: ((Player) -> any)?)
	if not eventRe then
		return
	end
	for _, p in Players:GetPlayers() do
		local r = Util.root(p)
		local cam = r and r.Position
		if cam and (cam - pos).Magnitude <= range then
			local data = payload
			if extra then
				data = table.clone(payload)
				local add = extra(p)
				if type(add) == "table" then
					for k, v in add do
						data[k] = v
					end
				end
			end
			pcall((eventRe :: RemoteEvent).FireClient, eventRe, p, data)
		end
	end
end

local function copy(payload: any): { [string]: any }
	local out = {}
	if type(payload) == "table" then
		local n = 0
		for k, v in payload do
			n += 1
			if n > 16 then
				break
			end
			if type(k) == "string" and #k <= 24 then
				local t = type(v)
				if t == "string" then
					if #v <= 200 then
						out[k] = v
					end
				elseif t == "number" then
					if v == v and math.abs(v) < 1e12 then
						out[k] = v
					end
				elseif t == "boolean" then
					out[k] = v
				end
			end
		end
	end
	return out
end

local function invoke(player: Player, op: any, payload: any): any
	if type(op) ~= "string" or #op > 24 then
		return { ok = false, code = "bad" }
	end
	local h = handlers[op]
	if not h then
		return { ok = false, code = "bad" }
	end
	if not bucket:take(player) then
		return { ok = false, code = "rate", message = P.Lines.t("busy") }
	end
	local per = last[player]
	if not per then
		per = {}
		last[player] = per
	end
	local t = os.clock()
	if t - (per[op] or -1e9) < h.cooldown then
		return { ok = false, code = "cooldown", message = P.Lines.t("busy") }
	end
	per[op] = t
	local ok, res = pcall(h.fn, player, copy(payload))
	if not ok then
		Util.warnOnce("op " .. op, res)
		return { ok = false, code = "error", message = P.Lines.t("busy") }
	end
	if type(res) ~= "table" then
		return { ok = res == true }
	end
	return res
end

function Net.start(ctx: any)
	P, Config, Util = ctx.P, ctx.Config, ctx.Util
	bucket = Util.bucket(Config.NET.BURST, Config.NET.RATE)
	local old = ReplicatedStorage:FindFirstChild(P.REMOTES)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = P.REMOTES
	local rf = Instance.new("RemoteFunction")
	rf.Name = P.REQUEST
	rf.Parent = f
	local re = Instance.new("RemoteEvent")
	re.Name = P.EVENT
	re.Parent = f
	folder, requestFn, eventRe = f, rf, re
	rf.OnServerInvoke = function(player: Player, op: any, payload: any)
		return invoke(player, op, payload)
	end
	re.OnServerEvent:Connect(function() end) -- server -> client only
	Players.PlayerRemoving:Connect(function(p: Player)
		last[p] = nil
		bucket:forget(p)
	end)
end

-- parent the folder once every handler is bound (clients WaitForChild it)
function Net.publish(ready: { [string]: boolean })
	if folder then
		local okJ, json = pcall(function()
			return game:GetService("HttpService"):JSONEncode(ready)
		end)
		folder:SetAttribute(P.Attr.Ready, if okJ then json else "{}")
		folder.Parent = ReplicatedStorage
	end
end

function Net.setReady(ready: { [string]: boolean })
	if folder then
		local okJ, json = pcall(function()
			return game:GetService("HttpService"):JSONEncode(ready)
		end)
		folder:SetAttribute(P.Attr.Ready, if okJ then json else "{}")
	end
end

return Net
