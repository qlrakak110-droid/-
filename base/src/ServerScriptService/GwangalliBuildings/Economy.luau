-- Economy: money for the building system.
--   * When the life game is present (ServerStorage.GwangalliGameplayAPI), purchases are charged
--     through it ("spend": cash first, then the bank card) and stat gains go through "addStats", so
--     one wallet / one ledger exists for the player.
--   * Money the building system PAYS OUT (selling a home back, refunds) is kept as 건물 크레딧 (credit),
--     saved per player, and spent first on the next purchase. Without the life game the credit is the
--     whole wallet (starts at Config.FALLBACK_START_MONEY) and shows as leaderstats "돈".
--   Economy.balance(player) -> number        Economy.spend(player, amount, label) -> ok, msg
--   Economy.earn(player, amount, label)      Economy.addStats(player, { stamina = 1 }, label)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Util = Shared.Util

local Economy = {}

local Registry: any
local store: DataStore? = nil
local loaded: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}

local function api(): BindableFunction?
	local f = ServerStorage:FindFirstChild("GwangalliGameplayAPI")
	return if f and f:IsA("BindableFunction") then f else nil
end
Economy.hasLifeGame = function(): boolean
	return api() ~= nil
end

local function credit(p: Player): number
	return tonumber(p:GetAttribute("GwB_Credit")) or 0
end

local function setCredit(p: Player, v: number)
	p:SetAttribute("GwB_Credit", math.max(0, math.floor(v)))
	dirty[p] = true
	local ls = p:FindFirstChild("leaderstats")
	local money = ls and ls:FindFirstChild("돈")
	if money and money:IsA("IntValue") then
		money.Value = math.floor(v)
	end
end

function Economy.balance(p: Player): number
	local total = credit(p)
	local f = api()
	if f then
		local ok, cash, bank = pcall(function()
			return f:Invoke("balance", p)
		end)
		if ok then
			total += (tonumber(cash) or 0) + (tonumber(bank) or 0)
		end
	end
	return total
end

function Economy.spend(p: Player, amount: number, label: string): (boolean, string?)
	amount = math.floor(amount)
	if amount <= 0 then
		return true, nil
	end
	local c = credit(p)
	local fromCredit = math.min(c, amount)
	local rest = amount - fromCredit
	if rest > 0 then
		local f = api()
		if not f then
			return false, string.format("잔액이 부족해요 (%s 필요)", Util.won(amount))
		end
		local ok, res = pcall(function()
			return f:Invoke("spend", p, rest, label)
		end)
		if not ok or res ~= true then
			return false, string.format("잔액이 부족해요 (%s 필요)", Util.won(amount))
		end
	end
	if fromCredit > 0 then
		setCredit(p, c - fromCredit)
	end
	Registry.fire(p, "money", { delta = -amount, label = label, balance = Economy.balance(p) })
	return true, nil
end

function Economy.earn(p: Player, amount: number, label: string)
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end
	local f = api()
	if f then f:Invoke("earn", p, amount, label) else setCredit(p, credit(p) + amount) end
	Registry.fire(p, "money", { delta = amount, label = label, balance = Economy.balance(p) })
end

function Economy.addStats(p: Player, delta: { [string]: number }?, label: string?)
	if not delta then
		return
	end
	local f = api()
	if f then
		pcall(function()
			f:Invoke("addStats", p, delta, label or "생활")
		end)
	end
end

-- test grant (unpublished places only: the temporary studio, local Studio tests)
function Economy.canTestGrant(): boolean
	return game.PlaceId == 0
end

function Economy.testGrant(p: Player): boolean
	if not Economy.canTestGrant() then
		return false
	end
	if (p:GetAttribute("GwB_TestGranted") :: any) == true then
		return false
	end
	p:SetAttribute("GwB_TestGranted", true)
	Economy.earn(p, Config.TEST_MONEY_GRANT, "테스트 자금")
	return true
end

local function load(p: Player)
	local data = nil
	if store then
		local ok, v = pcall(function()
			return (store :: DataStore):GetAsync("u_" .. p.UserId)
		end)
		if ok then
			data = v
		end
	end
	local start = if api() then 0 else Config.FALLBACK_START_MONEY
	local c = if type(data) == "table" and type(data.credit) == "number" then data.credit else start
	if not api() then
		local ls = p:FindFirstChild("leaderstats") or Instance.new("Folder")
		ls.Name = "leaderstats"
		local money = ls:FindFirstChild("돈") or Instance.new("IntValue")
		money.Name = "돈"
		money.Parent = ls
		ls.Parent = p
	end
	setCredit(p, c)
	if type(data) == "table" and data.testGranted then
		p:SetAttribute("GwB_TestGranted", true)
	end
	loaded[p] = true
	dirty[p] = false
end

local function save(p: Player)
	if not store or not loaded[p] or not dirty[p] then
		return
	end
	local c = credit(p)
	local tg = p:GetAttribute("GwB_TestGranted") == true
	pcall(function()
		(store :: DataStore):SetAsync("u_" .. p.UserId, { credit = c, testGranted = tg, t = os.time() })
	end)
	dirty[p] = false
end

function Economy.init(ctx: any)
	Registry = ctx.Registry
	pcall(function()
		store = DataStoreService:GetDataStore(Config.FALLBACK_STORE)
	end)
	Registry.on("money.balance", function(p: Player)
		return { ok = true, balance = Economy.balance(p), credit = credit(p), lifeGame = api() ~= nil }
	end)
end

function Economy.start()
	-- the life game creates its API at start; give it a moment before the first player loads
	local t = os.clock()
	while not api() and os.clock() - t < 8 do
		task.wait(0.5)
	end
	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		loaded[p] = nil
		dirty[p] = nil
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			save(p)
		end
	end)
	while true do
		task.wait(Config.HOME_SAVE_EVERY)
		for _, p in Players:GetPlayers() do
			save(p)
		end
	end
end

return Economy
