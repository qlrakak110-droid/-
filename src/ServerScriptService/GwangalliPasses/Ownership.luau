-- GwangalliPasses/Ownership (server): who owns which pass.
--   * MarketplaceService:UserOwnsGamePassAsync (retries) on join and every RECHECK s; PromptGamePassPurchaseFinished
--     (purchased = true) grants at once and is re-verified a few seconds later.
--   * Studio: workspace attribute GwPassesStudioTest (true | "garage,flex"); live + Studio: GwPassesAdminFree with
--     the Player attribute GwangalliAdmin (GwangalliLiveOps).
--   * publishes Player attribute GwPass_<key> (the place's convention: GwangalliStore / R$ app read it) and fires
--     ServerStorage.GwangalliPassesChanged (player, key, owned) + module listeners.
--   * when a pass Id is set, adds it to ReplicatedStorage.GamePassConfig (the R$ app / 부스트 상점 list it).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Ownership = {}

local P: any, Config: any, Util: any
local real: { [Player]: { [string]: boolean } } = {} -- Roblox says owned (or bought this session)
local bought: { [Player]: { [string]: boolean } } = {} -- PromptGamePassPurchaseFinished this session
local listeners: { (Player, string, boolean) -> () } = {}
local changedEv: BindableEvent? = nil

local function studioSet(): { [string]: boolean }?
	if not RunService:IsStudio() then
		return nil
	end
	local v = workspace:GetAttribute(Config.STUDIO_ATTR)
	if v == true then
		local all = {}
		for _, k in P.ORDER do
			all[k] = true
		end
		return all
	end
	if type(v) == "string" and v ~= "" then
		local out = {}
		for word in string.gmatch(v, "[^,%s]+") do
			local k = P.key(word)
			if k then
				out[k] = true
			end
		end
		return out
	end
	return nil
end

local function adminFree(player: Player): boolean
	return workspace:GetAttribute(Config.ADMIN_ATTR) == true and player:GetAttribute("GwangalliAdmin") == true
end

-- the effective ownership (real purchase, Studio test, admin free)
function Ownership.owns(player: any, k: any): boolean
	local key = P.key(k)
	if not key or not Util.isPlayer(player) then
		return false
	end
	if not P.available(key) then
		return false
	end
	local r = real[player]
	if r and r[key] then
		return true
	end
	local st = studioSet()
	if st and st[key] then
		return true
	end
	return adminFree(player)
end

function Ownership.onChanged(fn: (Player, string, boolean) -> ())
	table.insert(listeners, fn)
end

local function publish(player: Player)
	if player.Parent ~= Players then
		return
	end
	for _, key in P.ORDER do
		local now = Ownership.owns(player, key)
		local attr = P.Attr.Owned .. key
		local before = player:GetAttribute(attr) == true
		if now ~= before then
			player:SetAttribute(attr, now)
			if changedEv then
				pcall(changedEv.Fire, changedEv, player, key, now)
			end
			for _, fn in listeners do
				task.spawn(fn, player, key, now)
			end
		elseif player:GetAttribute(attr) == nil then
			player:SetAttribute(attr, now)
		end
	end
end
Ownership.publish = publish

local function check(player: Player, key: string): boolean?
	local id = P.idOf(key)
	if id <= 0 then
		return nil
	end
	for i = 1, Config.OWNERSHIP.RETRIES do
		local ok, res = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
		if ok then
			return res == true
		end
		if i < Config.OWNERSHIP.RETRIES then
			task.wait(Config.OWNERSHIP.RETRY_GAP)
		end
		if player.Parent ~= Players then
			return nil
		end
	end
	return nil -- unknown: keep what we had
end

function Ownership.refresh(player: Player)
	local r = real[player] or {}
	real[player] = r
	local b = bought[player] or {}
	for _, key in P.ORDER do
		local res = check(player, key)
		if res ~= nil then
			-- a purchase made this session stays even if Roblox's cache still says no
			r[key] = res or b[key] == true
		end
	end
	publish(player)
end

local function grantBought(player: Player, key: string)
	local r = real[player] or {}
	real[player] = r
	r[key] = true
	local b = bought[player] or {}
	bought[player] = b
	b[key] = true
	publish(player)
end

-- GamePassConfig injection (server table; the client does the same for its own copy)
local function injectStore()
	if not Config.INJECT_STORE then
		return
	end
	local m = ReplicatedStorage:FindFirstChild("GamePassConfig")
	if not m or not m:IsA("ModuleScript") then
		return
	end
	local ok, gpc = pcall(require, m)
	if not ok or type(gpc) ~= "table" then
		return
	end
	for _, key in P.ORDER do
		local d = Config.PASSES[key]
		local id = P.idOf(key)
		if id > 0 and gpc[key] == nil then
			gpc[key] = { Id = id, Name = d.Name, Title = d.Title, Desc = d.Desc, Perk = d.Perk, Store = d.Store, Order = d.Order }
		end
	end
end

function Ownership.start(ctx: any)
	P, Config, Util = ctx.P, ctx.Config, ctx.Util
	local ev = ServerStorage:FindFirstChild(P.CHANGED)
	if not ev then
		ev = Instance.new("BindableEvent")
		ev.Name = P.CHANGED
		ev.Parent = ServerStorage
	end
	changedEv = ev :: BindableEvent
	injectStore()

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased or not Util.isPlayer(player) then
			return
		end
		for _, key in P.ORDER do
			if P.idOf(key) > 0 and P.idOf(key) == passId then
				grantBought(player, key)
				ctx.Net.send(player, { kind = "toast", icon = Config.PASSES[key].Glyph, title = P.Lines.t("bought"), body = P.Lines.t("bought_body", Config.PASSES[key].Title), tone = "success" })
				-- re-verify later (never revokes a fresh purchase on a stale cache)
				task.delay(8, function()
					if player.Parent == Players then
						local res = check(player, key)
						if res == true then
							grantBought(player, key)
						end
					end
				end)
			end
		end
	end)

	local function join(player: Player)
		real[player] = real[player] or {}
		publish(player) -- Studio / admin grants at once
		task.spawn(Ownership.refresh, player)
		player:GetAttributeChangedSignal("GwangalliAdmin"):Connect(function()
			publish(player)
		end)
	end
	for _, p in Players:GetPlayers() do
		join(p)
	end
	Players.PlayerAdded:Connect(join)
	Players.PlayerRemoving:Connect(function(player: Player)
		real[player] = nil
		bought[player] = nil
	end)
	-- switches flipped at run time (Studio test / admin free)
	for _, a in { Config.STUDIO_ATTR, Config.ADMIN_ATTR } do
		workspace:GetAttributeChangedSignal(a):Connect(function()
			for _, p in Players:GetPlayers() do
				publish(p)
			end
		end)
	end
	-- periodic re-check (a pass bought on the website while playing)
	task.spawn(function()
		while true do
			task.wait(Config.OWNERSHIP.RECHECK)
			for _, p in Players:GetPlayers() do
				task.spawn(Ownership.refresh, p)
				task.wait(0.2)
			end
		end
	end)
end

function Ownership.map(player: Player): { [string]: boolean }
	local out = {}
	for _, key in P.ORDER do
		out[key] = Ownership.owns(player, key)
	end
	return out
end

return Ownership
