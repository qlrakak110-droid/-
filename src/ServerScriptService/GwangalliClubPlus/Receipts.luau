-- GwangalliClubPlus.Receipts: developer-product receipts for the optional Robux 후원 (server).
-- A place has exactly one MarketplaceService.ProcessReceipt. This module:
--   * always exports its handler as ServerStorage.GwangalliReceiptHandlers.GwangalliClubPlus
--     (BindableFunction: Invoke(receiptInfo) -> Enum.ProductPurchaseDecision, or nil when the product
--     is not one of ours), so a central receipt script can route to it;
--   * assigns ProcessReceipt itself ONLY when Config.Robux.Products is not empty, InstallProcessReceipt
--     is on and nobody claimed it (ServerStorage attribute GwProcessReceiptOwner) within ClaimWait s.
--     The installed router asks every BindableFunction in GwangalliReceiptHandlers (other add-ons can
--     register there too) and grants nothing it does not recognise (NotProcessedYet).
-- Receipts are idempotent: PurchaseId is remembered in memory and in DataStore "GwClubPlus_Receipts_v1".

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Receipts = {}

local C: any
local S: any
local granted: { [string]: boolean } = {}
local store: any = nil
local storeOff = false

local function ds(): any?
	if storeOff then
		return nil
	end
	if store then
		return store
	end
	local ok, st = pcall(DataStoreService.GetDataStore, DataStoreService, "GwClubPlus_Receipts_v1")
	if ok then
		store = st
		return st
	end
	storeOff = true
	return nil
end

-- "yes" | "no" | "unknown" (the store could not be read: try the receipt again later)
local function lookup(purchaseId: string): string
	if granted[purchaseId] then
		return "yes"
	end
	local st = ds()
	if not st then
		return "no" -- memory only (Studio / no DataStore access)
	end
	local ok, v = pcall(st.GetAsync, st, purchaseId)
	if not ok then
		return "unknown"
	end
	if v then
		granted[purchaseId] = true
		return "yes"
	end
	return "no"
end

local function remember(purchaseId: string): boolean
	granted[purchaseId] = true
	local st = ds()
	if not st then
		return true -- memory only (Studio / no DataStore access)
	end
	for i = 1, 3 do
		local ok = pcall(st.UpdateAsync, st, purchaseId, function()
			return true
		end)
		if ok then
			return true
		end
		task.wait(i)
	end
	return false
end

-- the exported handler
function Receipts.handle(info: any): any
	if type(info) ~= "table" then
		return nil
	end
	local product = S.product(info.ProductId)
	if not product then
		return nil
	end
	local purchaseId = tostring(info.PurchaseId)
	local state = lookup(purchaseId)
	if state == "yes" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif state == "unknown" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local p = Players:GetPlayerByUserId(info.PlayerId)
	if not p then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, delivered = pcall(C.Donate.grantRobux, p, product.id)
	if not ok or not delivered then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not remember(purchaseId) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function handlersFolder(): Folder
	local f = ServerStorage:FindFirstChild(S.Names.ReceiptFolder)
	if not f then
		f = Instance.new("Folder")
		f.Name = S.Names.ReceiptFolder
		f.Parent = ServerStorage
	end
	return f :: Folder
end

-- the router installed as ProcessReceipt (asks every registered handler)
local function router(info: any): any
	local f = ServerStorage:FindFirstChild(S.Names.ReceiptFolder)
	if f then
		for _, h in f:GetChildren() do
			if h:IsA("BindableFunction") then
				local ok, decision = pcall(h.Invoke, h, info)
				if ok and typeof(decision) == "EnumItem" then
					return decision
				end
			end
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function Receipts.init(ctx: any)
	C = ctx
	S = ctx.S
	local f = handlersFolder()
	local bf = f:FindFirstChild(S.Names.ReceiptHandler)
	if not bf then
		bf = Instance.new("BindableFunction")
		bf.Name = S.Names.ReceiptHandler
		bf.Parent = f
	end
	;(bf :: BindableFunction).OnInvoke = Receipts.handle

	local cfg = S.Config.Robux
	if #cfg.Products == 0 or not cfg.InstallProcessReceipt then
		return
	end
	task.delay(cfg.ClaimWait, function()
		local owner = ServerStorage:GetAttribute(S.Names.ReceiptOwnerAttr)
		if owner ~= nil and owner ~= S.Names.ReceiptHandler then
			-- a central handler owns ProcessReceipt: it routes to our BindableFunction
			return
		end
		ServerStorage:SetAttribute(S.Names.ReceiptOwnerAttr, S.Names.ReceiptHandler)
		local ok, err = pcall(function()
			MarketplaceService.ProcessReceipt = router
		end)
		if not ok then
			warn("[GwangalliClubPlus] could not set ProcessReceipt:", err)
		end
	end)
end

return Receipts
