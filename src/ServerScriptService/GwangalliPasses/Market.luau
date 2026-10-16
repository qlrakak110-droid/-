-- GwangalliPasses/Market (server): pass #3 편의 패스, the phone 블랙마켓 app.
-- The app reuses the existing Arms weapon shop end to end (stock, prices, money, nonces, inventory, the
-- full-screen WeaponShopUI): every owner gets a server-only shop "dealer:gwphone_<UserId>" anchored on their own
-- HumanoidRootPart (GwangalliArmsAPI "setShopState"), opened with GwangalliArmsAPI "openShop" (a trusted request).
-- Clients cannot open "dealer:" shops themselves, so nobody can use someone else's phone shop. The shop's own
-- street checks still apply: police / SWAT near, gunfire, being chased, KO / cuffed / seated (playerReady).
-- Registered lazily (the first open) because the first registered shop removes the studio-only trade point.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Market = {}

local ctx: any
local P: any, Config: any, Util: any, Lines: any
local registered: { [Player]: boolean } = {}
local lastOpen: { [Player]: number } = {}
local feePaid: { [Player]: number } = {}

Market.ready = false

local REASON = {
	police = "market_police",
	swat = "market_swat",
	gunfire = "market_gunfire",
	chased = "market_chased",
	busy = "market_busy",
	inactive = "market_inactive",
	attacked = "market_inactive",
	fleeing = "market_inactive",
	unknown = "market_inactive",
	offline = "market_inactive",
	grudge = "market_grudge",
	far = "market_inactive",
	seated = "market_seated",
	ko = "market_busy",
	jail = "market_busy",
	cuffed = "market_busy",
	dead = "market_busy",
}

local function armsApi(op: string, ...: any): ...any
	local f = ServerStorage:FindFirstChild("GwangalliArmsAPI")
	if not f or not f:IsA("BindableFunction") then
		return nil
	end
	local r = table.pack(pcall((f :: BindableFunction).Invoke, f, op, ...))
	if not r[1] then
		Util.warnOnce("arms api " .. op, r[2])
		return nil
	end
	return table.unpack(r, 2, r.n)
end

local function shopId(player: Player): string
	return "dealer:gwphone_" .. tostring(player.UserId)
end

local function textOf(reason: string?): string
	return Lines.t(REASON[reason or ""] or "market_inactive")
end

local function register(player: Player): boolean
	local root = Util.root(player)
	if not root then
		return false
	end
	armsApi("setShopState", shopId(player), { open = true, name = Config.MARKET.SHOP_NAME, anchor = root, radius = Config.MARKET.RADIUS })
	registered[player] = true
	return true
end

-- -> { ok, open, reason, text }
function Market.state(player: Player): { [string]: any }
	if not Market.ready then
		return { ok = true, open = false, reason = "offline", text = Lines.t("feature_off") }
	end
	if not ctx.Ownership.owns(player, "Convenience") then
		return { ok = true, open = false, reason = "locked", text = Lines.t("locked_tab", Config.PASSES.Convenience.Title) }
	end
	local why = Util.blockedState(player)
	if why then
		return { ok = true, open = false, reason = why, text = textOf(why) }
	end
	if registered[player] then
		local st = armsApi("shopState", shopId(player))
		if type(st) == "table" and st.open == false then
			return { ok = true, open = false, reason = st.reason, text = textOf(st.reason) }
		end
	elseif player:GetAttribute("PoliceChase") == true then
		return { ok = true, open = false, reason = "chased", text = textOf("chased") }
	end
	return { ok = true, open = true, reason = nil, text = Lines.t("market_ok") }
end

function Market.open(player: Player, tab: any): { [string]: any }
	if not Market.ready then
		return { ok = false, code = "off", text = Lines.t("feature_off") }
	end
	if not ctx.Ownership.owns(player, "Convenience") then
		return { ok = false, code = "locked", text = Lines.t("locked_tab", Config.PASSES.Convenience.Title) }
	end
	local t = os.clock()
	if t - (lastOpen[player] or -1e9) < Config.MARKET.OPEN_GAP then
		return { ok = false, code = "cooldown", text = Lines.t("busy") }
	end
	lastOpen[player] = t
	local why = Util.blockedState(player)
	if why then
		return { ok = false, code = why, text = textOf(why) }
	end
	if not register(player) then
		return { ok = false, code = "dead", text = textOf("dead") }
	end
	-- optional 접속료 (once per 3 minutes = one shop session)
	local fee = math.floor(tonumber(Config.MARKET.OPEN_FEE) or 0)
	if fee > 0 and t - (feePaid[player] or -1e9) > 180 then
		local f = ServerStorage:FindFirstChild("GwangalliGameplayAPI")
		local okF, paid = false, false
		if f and f:IsA("BindableFunction") then
			okF, paid = pcall((f :: BindableFunction).Invoke, f, "spend", player, fee, Lines.t("market_fee"))
		end
		if not okF or not paid then
			return { ok = false, code = "money", text = Lines.t("market_money", P.won(fee)) }
		end
		feePaid[player] = t
	end
	local okTab = if tab == "basic" or tab == "upper" or tab == "ammo" then tab else nil
	local ok, reason = armsApi("openShop", player, shopId(player), { tab = okTab })
	if ok == true then
		return { ok = true, text = Lines.t("market_ok") }
	end
	return { ok = false, code = tostring(reason or "inactive"), text = textOf(if type(reason) == "string" then reason else "inactive") }
end

function Market.start(c: any): boolean
	ctx = c
	P, Config, Util, Lines = c.P, c.Config, c.Util, c.P.Lines
	local api = Util.waitChild(ServerStorage, "GwangalliArmsAPI", "BindableFunction", 150)
	if not api then
		Util.warnOnce("market", "ServerStorage.GwangalliArmsAPI not found: 블랙마켓 off")
		return false
	end
	-- the weapon shop child registers its ops during Arms init; wait for "shopState" to answer
	local t0 = os.clock()
	while os.clock() - t0 < 60 do
		local st = armsApi("shopState", "gwpasses:probe")
		if type(st) == "table" then
			break
		end
		task.wait(1)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		if registered[p] then
			armsApi("setShopState", shopId(p), { open = false, reason = "inactive" })
		end
		registered[p] = nil
		lastOpen[p] = nil
		feePaid[p] = nil
	end)
	-- a new character: re-anchor the shop on the new root (the old one is gone)
	local function join(p: Player)
		p.CharacterAdded:Connect(function(ch: Model)
			if registered[p] then
				local root = ch:WaitForChild("HumanoidRootPart", 10)
				if root and root:IsA("BasePart") then
					armsApi("setShopState", shopId(p), { open = true, anchor = root, radius = Config.MARKET.RADIUS })
				end
			end
		end)
	end
	for _, p in Players:GetPlayers() do
		join(p)
	end
	Players.PlayerAdded:Connect(join)
	Market.ready = true
	return true
end

return Market
