-- GwangalliPasses/StoreHook (client): the passes in the place's own store and the purchase prompt.
--   * runs FIRST (before anything yields): passes whose Id is set are added to the client's
--     ReplicatedStorage.GamePassConfig table, so the phone "R$" app (and the side 부스트 상점 when it starts after
--     us) lists them next to the existing passes. Id 0 ("판매 준비 중") is never injected.
--   * Store.buy(key): MarketplaceService:PromptGamePassPurchase; Id 0 shows "판매 준비 중".
--   * Store.price(key, cb): the real price from Roblox (falls back to Config Price).
--   * Store.changed(fn): ownership attributes changed (bought in game, Studio test switch...).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Store = {}

local P: any, K: any
local prices: { [string]: number } = {}

function Store.inject(Pm: any)
	local m = ReplicatedStorage:FindFirstChild("GamePassConfig")
	if not m or not m:IsA("ModuleScript") or not Pm.Config.INJECT_STORE then
		return
	end
	local ok, gpc = pcall(require, m)
	if not ok or type(gpc) ~= "table" then
		return
	end
	for _, key in Pm.ORDER do
		local d = Pm.Config.PASSES[key]
		local id = Pm.idOf(key)
		if id > 0 and gpc[key] == nil then
			gpc[key] = { Id = id, Name = d.Name, Title = d.Title, Desc = d.Desc, Perk = d.Perk, Store = d.Store, Order = d.Order }
		end
	end
end

function Store.start(ctx: any)
	P, K = ctx.P, ctx.K
end

function Store.owned(key: string): boolean
	return P.has(Players.LocalPlayer, key)
end

function Store.buy(k: any)
	local key = P.key(k)
	if not key then
		return
	end
	local id = P.idOf(key)
	if id <= 0 then
		K.toast({ kind = "info", icon = "⏳", title = P.Lines.t("not_ready"), body = if RunService:IsStudio() then P.Lines.t("not_ready_studio") else nil })
		return
	end
	if Store.owned(key) then
		K.toast({ kind = "info", icon = P.Config.PASSES[key].Glyph, title = P.Lines.t("owned") })
		return
	end
	pcall(function()
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
	end)
end

function Store.price(key: string, cb: (number) -> ())
	if prices[key] then
		cb(prices[key])
		return
	end
	local fallback = P.Config.PASSES[key].Price or 0
	local id = P.idOf(key)
	if id <= 0 then
		cb(fallback)
		return
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, Enum.InfoType.GamePass)
		local price = if ok and type(info) == "table" then tonumber(info.PriceInRobux) else nil
		prices[key] = price or fallback
		cb(prices[key])
	end)
end

function Store.changed(fn: (string, boolean) -> ()): RBXScriptConnection
	return P.changed(Players.LocalPlayer, fn)
end

return Store
