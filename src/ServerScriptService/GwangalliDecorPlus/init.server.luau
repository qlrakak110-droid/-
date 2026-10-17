--!strict
-- GwangalliDecorPlus (Script): 내 집 마련 자유 배치 인테리어 add-on — server boot.
-- Drop-in: needs ReplicatedStorage.GwangalliDecorShared (ModuleScript) and the client LocalScript
-- StarterPlayerScripts.GwangalliDecorPlus. Nothing in the existing place is edited: the life game
-- (Profiles / Housing / ctx) is found at runtime, the home models are watched in
-- Workspace.GwangalliHomeInstances and pieces are built into each home's own "DecorPlus" folder.
-- Remotes: ReplicatedStorage.GwangalliDecorPlusRemotes { Request (RemoteFunction), Event (RemoteEvent) }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliDecorShared"))
local Config = Shared.Config

local Host = require(script:WaitForChild("Host"))
local Store = require(script:WaitForChild("Store"))
local Homes = require(script:WaitForChild("Homes"))
local Actions = require(script:WaitForChild("Actions"))
local Social = require(script:WaitForChild("Social"))

-- remotes (folder parented last so clients see it complete)
local old = ReplicatedStorage:FindFirstChild(Config.REMOTES_NAME)
if old then
	old:Destroy()
end
local remotes = Instance.new("Folder")
remotes.Name = Config.REMOTES_NAME
local request = Instance.new("RemoteFunction")
request.Name = "Request"
request.Parent = remotes
local event = Instance.new("RemoteEvent")
event.Name = "Event"
event.Parent = remotes

local function push(p: Player, payload: any)
	if p and p.Parent == Players then
		event:FireClient(p, payload)
	end
end

Host.notifyFallback = function(p: Player, title: string, body: string?)
	push(p, { kind = "toast", title = title, body = body or "" })
end

local changeQueued: { [any]: boolean } = {}
local function onChanged(H: any, _why: string)
	if changeQueued[H] then
		return
	end
	changeQueued[H] = true
	task.delay(0.6, function()
		changeQueued[H] = nil
		if H.model.Parent then
			Social.after(H)
		end
	end)
end

Homes.init({ Host = Host, Store = Store, push = push, onChanged = onChanged })
Social.init({ Host = Host, Store = Store, Homes = Homes, push = push })
Actions.init({ Host = Host, Store = Store, Homes = Homes, Social = Social, push = push })

request.OnServerInvoke = function(p: Player, action: any, payload: any): any
	return Actions.handle(p, action, payload)
end
remotes.Parent = ReplicatedStorage

-- profiles of this add-on (own DataStore)
local function joined(p: Player)
	task.spawn(function()
		Store.load(p)
		if Host.ready() then
			Homes.ensure(p)
		end
	end)
end
Players.PlayerAdded:Connect(joined)
for _, p in Players:GetPlayers() do
	joined(p)
end
Players.PlayerRemoving:Connect(function(p: Player)
	Homes.dropOwner(p)
	Actions.drop(p)
	Social.drop(p)
	Store.release(p)
end)
Store.startAutosave()

-- life-game discovery (our Script may start before GwangalliGameplay has finished its init)
task.spawn(function()
	local t0 = os.clock()
	while not Host.discover() do
		if os.clock() - t0 > 180 then
			warn("[GwangalliDecorPlus] life-game housing not found (ServerScriptService.GwangalliGameplay) — add-on idle")
			return
		end
		task.wait(1)
	end
	if Config.DORMANT_IF_HOST_DECOR and Host.dormant() then
		warn("[GwangalliDecorPlus] the host ships its own HomeDecor feature — add-on dormant")
		remotes:SetAttribute("Dormant", true)
		return
	end
	if Config.LINK_HOST_SCORE then
		Host.linkScore(function(d: any): (number, number)
			local b = Homes.bonus[d]
			if b then
				return b.decor, b.value
			end
			return 0, 0
		end)
	end
	Homes.start()
	remotes:SetAttribute("Ready", true)
end)
