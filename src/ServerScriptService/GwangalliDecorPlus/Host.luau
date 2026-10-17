--!strict
-- GwangalliDecorPlus/Host: finds the life game at runtime and adapts to it (never edits its scripts).
--   Host.discover() -> boolean (retried by init until ready)
--   Host.ready() / Host.profile(p) / Host.inside(p) -> (inst?, role?) / Host.ownInside(p) -> (inst?, code?)
--   Host.instOfModel(model) / Host.listingName(id) / Host.balance(p)
--   Host.spend(p, amount, label) -> boolean / Host.refund(p, amount, label) / Host.changed(p)
--   Host.notify(p, title, body) / Host.addStats(p, delta, reason) / Host.linkScore(bonusOf)
-- Life-game modules (research §1): ServerScriptService Folder "GwangalliGameplay" (found by class:
-- a Script of the same name sits next to it) -> Profiles, Housing, VenueLife.ctx / StreetInteract.ctx;
-- fallback wallet = ServerStorage.GwangalliGameplayAPI (BindableFunction).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Host = {}

local folder: Instance? = nil
local Profiles: any = nil
local Housing: any = nil
local ctx: any = nil
local api: BindableFunction? = nil
local G: any = nil
Host.notifyFallback = nil :: ((Player, string, string?) -> ())?

local function tryRequire(m: Instance?): any
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, r = pcall(require, m)
	if ok then
		return r
	end
	return nil
end

local function findFolder(): Instance?
	for _, c in ServerScriptService:GetChildren() do
		if c:IsA("Folder") and c.Name == "GwangalliGameplay" then
			return c
		end
	end
	return nil
end

local function ctxOk(c: any): boolean
	return type(c) == "table" and type(c.spend) == "function" and type(c.ledger) == "function" and type(c.changed) == "function"
end

-- one discovery attempt; true once Profiles + Housing answer
function Host.discover(): boolean
	if Host.ready() then
		return true
	end
	folder = folder or findFolder()
	if not folder then
		return false
	end
	Profiles = Profiles or tryRequire(folder:FindFirstChild("Profiles"))
	Housing = Housing or tryRequire(folder:FindFirstChild("Housing"))
	if not ctxOk(ctx) then
		local vl = tryRequire(folder:FindFirstChild("VenueLife"))
		if vl and ctxOk(vl.ctx) then
			ctx = vl.ctx
		else
			local si = tryRequire(folder:FindFirstChild("StreetInteract"))
			if si and ctxOk(si.ctx) then
				ctx = si.ctx
			end
		end
	end
	local a = ServerStorage:FindFirstChild("GwangalliGameplayAPI")
	api = if a and a:IsA("BindableFunction") then a else nil
	if not G then
		local gs = ReplicatedStorage:FindFirstChild("GwangalliGameplayShared")
		G = tryRequire(gs)
	end
	return Host.ready()
end

function Host.ready(): boolean
	if not (Profiles and Housing and type(Profiles.get) == "function" and type(Housing.where) == "function") then
		return false
	end
	local ok, avail = pcall(function()
		return type(Housing.available) ~= "function" or Housing.available()
	end)
	return ok and avail == true
end

-- a host-side free-placement feature (future HomeDecor module) switches this add-on off
function Host.dormant(): boolean
	local f = folder or findFolder()
	if f and f:FindFirstChild("HomeDecor") then
		return true
	end
	return workspace:GetAttribute("GwHostDecor") == true
end

function Host.G(): any
	return G
end

function Host.housing(): any
	return Housing
end

function Host.profile(p: Player): any?
	if not Profiles then
		return nil
	end
	local ok, d = pcall(Profiles.get, p)
	return if ok then d else nil
end

function Host.persistent(p: Player): boolean
	if Profiles and type(Profiles.persistent) == "function" then
		local ok, v = pcall(Profiles.persistent, p)
		return ok and v == true
	end
	return false
end

-- the home instance the player stands in (+ role "owner" | "guest" | "viewer")
function Host.inside(p: Player): (any?, string?)
	if not Housing then
		return nil, nil
	end
	local ok, inst, role = pcall(Housing.where, p)
	if not ok or type(inst) ~= "table" or not inst.model or not inst.model.Parent then
		return nil, nil
	end
	return inst, role
end

-- the player's own live home, with the player inside it
function Host.ownInside(p: Player): (any?, string?)
	if not Host.ready() then
		return nil, "booting"
	end
	local inst, role = Host.inside(p)
	if not inst then
		return nil, "notHome"
	end
	if inst.staged then
		return nil, "staged"
	end
	if inst.owner ~= p or role ~= "owner" then
		return nil, "notOwner"
	end
	local d = Host.profile(p)
	if not d then
		return nil, "noProfile"
	end
	if not (d.home and d.home.listingId == inst.listingId) then
		return nil, "notHome"
	end
	return inst, nil
end

function Host.instOfModel(model: Instance): any?
	if not Housing then
		return nil
	end
	local uid = model:GetAttribute("HomeOwnerId")
	if type(uid) ~= "number" or uid <= 0 then
		return nil
	end
	local owner = Players:GetPlayerByUserId(uid)
	if not owner then
		return nil
	end
	local ok, inst = pcall(Housing.instanceOf, owner)
	if ok and type(inst) == "table" and inst.model == model then
		return inst
	end
	return nil
end

function Host.listingName(listingId: string?): string
	if G and listingId and G.LISTINGS and G.LISTINGS[listingId] then
		return G.LISTINGS[listingId].name or listingId
	end
	return "우리 집"
end

function Host.balance(p: Player): (number, number)
	local d = Host.profile(p)
	if d then
		return d.cash or 0, d.bank or 0
	end
	if api then
		local ok, c, b = pcall(function()
			return (api :: BindableFunction):Invoke("balance", p)
		end)
		if ok then
			return tonumber(c) or 0, tonumber(b) or 0
		end
	end
	return 0, 0
end

-- pays (bank first, then cash). Never yields with ctx.
function Host.spend(p: Player, amount: number, label: string): boolean
	if amount <= 0 then
		return true
	end
	if ctxOk(ctx) then
		local ok, r = pcall(ctx.spend, p, math.floor(amount), label, true, "bank")
		return ok and r == true
	end
	if api then
		local ok, r = pcall(function()
			return (api :: BindableFunction):Invoke("spend", p, math.floor(amount), label)
		end)
		return ok and r == true
	end
	return false
end

function Host.refund(p: Player, amount: number, label: string): boolean
	if amount <= 0 then
		return true
	end
	if ctxOk(ctx) then
		local ok, r = pcall(ctx.ledger, p, "bank", math.floor(amount), label, true)
		return ok and r == true
	end
	if api then
		local ok, r = pcall(function()
			return (api :: BindableFunction):Invoke("earn", p, math.floor(amount), label)
		end)
		return ok and r == true
	end
	return false
end

function Host.canPay(): boolean
	return ctxOk(ctx) or api ~= nil
end

function Host.changed(p: Player)
	if ctxOk(ctx) then
		pcall(ctx.changed, p, "housing", "cash", "bank")
	elseif Profiles and type(Profiles.markDirty) == "function" then
		pcall(Profiles.markDirty, p)
	end
end

function Host.notify(p: Player, title: string, body: string?)
	if ctx and type(ctx.notify) == "function" then
		local ok = pcall(ctx.notify, p, "home", title, body or "")
		if ok then
			return
		end
	end
	if Host.notifyFallback then
		Host.notifyFallback(p, title, body)
	end
end

function Host.addStats(p: Player, delta: { [string]: number }, reason: string?)
	if ctx and type(ctx.addStats) == "function" then
		pcall(ctx.addStats, p, delta, reason, false)
	elseif api then
		pcall(function()
			(api :: BindableFunction):Invoke("addStats", p, delta, reason)
		end)
	end
end

function Host.roomTheme(): any
	if Housing and Housing.Core then
		return Housing.Core
	end
	return nil
end

-- placed pieces count toward the life game's 인테리어 점수 / 편안함 and 가구 가치 (server side G only).
-- bonusOf(d) -> (decor, value)
function Host.linkScore(bonusOf: (any) -> (number, number))
	if not G or G.__gwDecorPlusLinked then
		return
	end
	if type(G.homeDecor) ~= "function" or type(G.furnitureValue) ~= "function" then
		return
	end
	G.__gwDecorPlusLinked = true
	local baseDecor = G.homeDecor
	G.homeDecor = function(d: any): number
		local v = baseDecor(d)
		local ok, dec = pcall(bonusOf, d)
		return v + (if ok and type(dec) == "number" then dec else 0)
	end
	local baseValue = G.furnitureValue
	G.furnitureValue = function(d: any): number
		local v = baseValue(d)
		local ok, _, val = pcall(bonusOf, d)
		return v + (if ok and type(val) == "number" then val else 0)
	end
end

function Host.profiles(): any
	return Profiles
end

return Host
