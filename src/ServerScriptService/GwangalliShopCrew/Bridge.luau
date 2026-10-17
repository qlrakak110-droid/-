-- GwangalliShopCrew/Bridge: the ONLY file that touches the place's other systems. Every call is pcall'd and
-- has a nil-safe fallback, so a missing or changed system turns a feature off instead of breaking the crew.
--   ShopLife bus      ServerStorage.GwangalliShopLife {Event, Request}          (required: no bus, no crew)
--   ShopLife module   ServerScriptService.GwangalliBuildings.ShopLife          (shop records, sessions, prompts)
--   Registry          GwangalliBuildings.Registry (ShopLife's own validated player handlers, fire, toast)
--   Needs / Interact / Economy   GwangalliBuildings.{Needs, Interact, Economy}
--   GameplayAPI       ServerStorage.GwangalliGameplayAPI (balance / spend / earn) when Economy is missing
--   ProgressAPI       ServerStorage.GwangalliProgressAPI ("track")
--   ShopStaff         GwangalliGameplay.ShopStaff (counter staff sites)
--   StreetShops       ReplicatedStorage.GwangalliBuildingsShared.StreetShops (menus, items, types)
--   Looks             ReplicatedStorage.GwangalliNPCLooks (rigs)
--   ShopService       ServerScriptService.GwangalliShopService (taken over / coexisting)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Bridge = {}

local Config: any = nil
local bus: Folder? = nil
local busEvent: BindableEvent? = nil
local busRequest: BindableFunction? = nil
local mods: { [string]: any } = {}
local warned: { [string]: number } = {}

Bridge.SS = nil :: any
Bridge.Looks = nil :: any
Bridge.ShopLife = nil :: any
Bridge.Registry = nil :: any

local function log(...)
	if Config and Config.DEBUG then
		print("[GwangalliShopCrew]", ...)
	end
end

local function warnOnce(key: string, msg: string)
	local t = os.clock()
	if warned[key] and t - warned[key] < 60 then
		return
	end
	warned[key] = t
	warn("[GwangalliShopCrew] " .. msg)
end
Bridge.warnOnce = warnOnce

local function tryRequire(inst: Instance?): any
	if not inst or not inst:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, inst)
	if ok and type(res) == "table" then
		return res
	end
	warnOnce("req" .. inst:GetFullName(), "require " .. inst:GetFullName() .. " failed: " .. tostring(res))
	return nil
end

function Bridge.init(cfg: any)
	Config = cfg
end

-------------------------------------------------------------------------------------------------
-- binding (after workspace.GwB_Ready)
-------------------------------------------------------------------------------------------------
function Bridge.bindBus(timeout: number): boolean
	local f = ServerStorage:WaitForChild("GwangalliShopLife", timeout)
	if not f then
		return false
	end
	local e = f:WaitForChild("Event", 10)
	local r = f:WaitForChild("Request", 10)
	if not (e and e:IsA("BindableEvent") and r and r:IsA("BindableFunction")) then
		return false
	end
	bus = f :: Folder
	busEvent = e :: BindableEvent
	busRequest = r :: BindableFunction
	return true
end

function Bridge.bindModules()
	local gb = ServerScriptService:FindFirstChild("GwangalliBuildings")
	if gb then
		for _, n in { "ShopLife", "Registry", "Needs", "Interact", "Economy" } do
			mods[n] = tryRequire(gb:FindFirstChild(n))
		end
	end
	local gp = ServerScriptService:FindFirstChild("GwangalliGameplay")
	if gp then
		mods.ShopStaff = tryRequire(gp:FindFirstChild("ShopStaff"))
	end
	local shared = ReplicatedStorage:FindFirstChild("GwangalliBuildingsShared")
	local S = tryRequire(shared)
	if S then
		Bridge.SS = S.StreetShops
	end
	Bridge.Looks = tryRequire(ReplicatedStorage:FindFirstChild("GwangalliNPCLooks"))
	Bridge.ShopLife = mods.ShopLife
	Bridge.Registry = mods.Registry
	log("bound", mods.ShopLife ~= nil, mods.Registry ~= nil, mods.Needs ~= nil, mods.Interact ~= nil, mods.Economy ~= nil, Bridge.SS ~= nil, Bridge.Looks ~= nil)
end

function Bridge.has(name: string): boolean
	return mods[name] ~= nil
end

-------------------------------------------------------------------------------------------------
-- bus
-------------------------------------------------------------------------------------------------
function Bridge.req(op: string, payload: any?): any
	local r = busRequest
	if not r then
		return { ok = false, code = "no_bus" }
	end
	local ok, res = pcall(function()
		return r:Invoke(op, payload or {})
	end)
	if not ok then
		warnOnce("bus" .. op, "bus " .. op .. ": " .. tostring(res))
		return { ok = false, code = "error" }
	end
	if type(res) ~= "table" then
		return { ok = false, code = "bad_reply" }
	end
	return res
end

function Bridge.onEvent(fn: (string, any) -> ()): RBXScriptConnection?
	local e = busEvent
	if not e then
		return nil
	end
	return e.Event:Connect(function(kind, data)
		if type(kind) == "string" and type(data) == "table" then
			fn(kind, data)
		end
	end)
end

function Bridge.busAlive(): boolean
	return bus ~= nil and bus.Parent ~= nil
end

-------------------------------------------------------------------------------------------------
-- ShopLife records and sessions (read only)
-------------------------------------------------------------------------------------------------
function Bridge.shopRec(key: string): any?
	local SL = mods.ShopLife
	if SL and type(SL.byKey) == "function" then
		local ok, rec = pcall(SL.byKey, key)
		if ok and type(rec) == "table" then
			return rec
		end
	end
	return nil
end

function Bridge.shops(): { any }
	local SL = mods.ShopLife
	if SL and type(SL.shops) == "function" then
		local ok, list = pcall(SL.shops)
		if ok and type(list) == "table" then
			return list
		end
	end
	local r = Bridge.req("shops")
	return if r.ok and type(r.shops) == "table" then r.shops else {}
end

function Bridge.session(p: Player): any?
	local SL = mods.ShopLife
	if SL and type(SL.session) == "function" then
		local ok, s = pcall(SL.session, p)
		if ok and type(s) == "table" then
			return s
		end
	end
	return nil
end

-- where the player sits now: (shopKey, tableId, seatId)
function Bridge.seatOf(p: Player): (string?, number?, number?)
	local s = Bridge.session(p)
	if s and type(s.seat) == "table" and type(s.shop) == "table" then
		local tb = s.seat.table
		return s.shop.key, tb and tb.id, s.seat.id
	end
	return nil, nil, nil
end

-- the shop the player is inside now (ShopLife's own presence tracking)
function Bridge.shopOf(p: Player): string?
	local s = Bridge.session(p)
	if s and type(s.shop) == "table" then
		return s.shop.key
	end
	return nil
end

-- the bill of the player in a shop: (total, lines { {name, qty, price} })
function Bridge.bill(p: Player, key: string): (number, { any })
	local s = Bridge.session(p)
	local total, lines = 0, {}
	if s and type(s.bills) == "table" then
		local b = s.bills[key]
		if type(b) == "table" then
			total = tonumber(b.total) or 0
			for _, it in (if type(b.items) == "table" then b.items else {}) do
				if type(it) == "table" then
					table.insert(lines, { name = tostring(it.name or it.id or "?"), qty = tonumber(it.qty) or 1, price = tonumber(it.price) or 0 })
				end
			end
		end
		if type(s.tabs) == "table" then
			total += tonumber(s.tabs[key]) or 0
		end
	end
	return total, lines
end

-- the dishes on the player's table in a shop: { {item, left, done, kind} }
function Bridge.dishesOfPlayer(p: Player, key: string): { any }
	local SL = mods.ShopLife
	local out = {}
	if not (SL and type(SL.dishes) == "function") then
		return out
	end
	local ok, all = pcall(SL.dishes)
	if not ok or type(all) ~= "table" then
		return out
	end
	for _, d in all do
		if type(d) == "table" and d.owner == p and d.shop and d.shop.key == key then
			table.insert(out, { item = d.item, left = tonumber(d.left) or 1, done = d.done == true, kind = d.kind, water = d.water ~= nil, waterLeft = d.waterLeft })
		end
	end
	return out
end

-- dish models on a table (for clearing): count of Dish_* / Setting_* models whose table id matches
function Bridge.tableDishCount(key: string, tableId: number): number
	local SL = mods.ShopLife
	if not (SL and type(SL.dishes) == "function") then
		return 0
	end
	local ok, all = pcall(SL.dishes)
	if not ok or type(all) ~= "table" then
		return 0
	end
	local n = 0
	for _, d in all do
		if type(d) == "table" and d.shop and d.shop.key == key and not d.gone then
			local tb = d.table or (d.seat and d.seat.table)
			if tb and tb.id == tableId then
				n += 1
			end
		end
	end
	return n
end

-------------------------------------------------------------------------------------------------
-- player actions through ShopLife's own validated handlers
-------------------------------------------------------------------------------------------------
local function handler(op: string): ((Player, any) -> any)?
	local R = mods.Registry
	if R and type(R.handlers) == "table" and type(R.handlers[op]) == "function" then
		return R.handlers[op]
	end
	return nil
end

function Bridge.lifeAct(p: Player, action: string, extra: any?): any
	local h = handler("life.act")
	if not h then
		return { ok = false, msg = "지금은 할 수 없어요" }
	end
	local payload = { action = action }
	for k, v in extra or {} do
		payload[k] = v
	end
	local ok, res = pcall(h, p, payload)
	if not ok then
		warnOnce("act" .. action, "life.act " .. action .. ": " .. tostring(res))
		return { ok = false }
	end
	return if type(res) == "table" then res else { ok = true }
end

-- open one of ShopLife's own station UIs for the player (order / menuboard / pay / checkout / service / pickup)
function Bridge.lifePrompt(p: Player, key: string, kind: string, data: any?): boolean
	local SL = mods.ShopLife
	if not (SL and type(SL.prompt) == "function") then
		return false
	end
	local ok, err = pcall(SL.prompt, p, key, kind, data)
	if not ok then
		warnOnce("prompt" .. kind, "ShopLife.prompt " .. kind .. ": " .. tostring(err))
	end
	return ok
end

function Bridge.lifePay(p: Player, key: string): any
	local h = handler("life.pay")
	if not h then
		return { ok = false, msg = "지금은 계산할 수 없어요" }
	end
	local ok, res = pcall(h, p, { shop = key })
	if not ok then
		return { ok = false }
	end
	return if type(res) == "table" then res else { ok = true }
end

function Bridge.fire(p: Player, kind: string, data: any?)
	local R = mods.Registry
	if R and type(R.fire) == "function" then
		pcall(R.fire, p, kind, data)
	end
end

function Bridge.toast(p: Player, text: string, kind: string?): boolean
	local R = mods.Registry
	if R and type(R.toast) == "function" then
		return (pcall(R.toast, p, text, kind or "info"))
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- needs / held items / money / progress
-------------------------------------------------------------------------------------------------
function Bridge.needs(p: Player, delta: { [string]: number }, label: string?): boolean
	local N = mods.Needs
	if N and type(N.apply) == "function" then
		return (pcall(N.apply, p, delta, nil, label))
	end
	-- no Needs module: the player attributes are still the shared contract (GwB_<Need>, 0..100)
	for n, d in delta do
		local a = "GwB_" .. n
		local v = p:GetAttribute(a)
		if type(v) == "number" then
			p:SetAttribute(a, math.clamp(v + d, 0, 100))
		end
	end
	return false
end

function Bridge.need(p: Player, name: string): number?
	local v = p:GetAttribute("GwB_" .. name)
	return if type(v) == "number" then v else nil
end

function Bridge.held(p: Player): any?
	local I = mods.Interact
	if I and type(I.held) == "function" then
		local ok, it = pcall(I.held, p)
		if ok then
			return it
		end
	end
	return nil
end

function Bridge.give(p: Player, item: any): boolean
	local I = mods.Interact
	if I and type(I.give) == "function" then
		local ok = pcall(I.give, p, item)
		return ok
	end
	return false
end

local function gameplayApi(): BindableFunction?
	local f = ServerStorage:FindFirstChild("GwangalliGameplayAPI")
	return if f and f:IsA("BindableFunction") then f else nil
end

function Bridge.balance(p: Player): number?
	local E = mods.Economy
	if E and type(E.balance) == "function" then
		local ok, n = pcall(E.balance, p)
		if ok and type(n) == "number" then
			return n
		end
	end
	local f = gameplayApi()
	if f then
		local ok, cash, bank = pcall(function()
			return f:Invoke("balance", p)
		end)
		if ok then
			return (tonumber(cash) or 0) + (tonumber(bank) or 0)
		end
	end
	return nil
end

-- money out of the player's wallet: (ok, msg?)
function Bridge.spend(p: Player, amount: number, label: string): (boolean, string?)
	amount = math.floor(amount)
	if amount <= 0 then
		return true, nil
	end
	local E = mods.Economy
	if E and type(E.spend) == "function" then
		local ok, res, msg = pcall(E.spend, p, amount, label)
		if ok then
			return res == true, msg
		end
		warnOnce("spend", "Economy.spend: " .. tostring(res))
	end
	local f = gameplayApi()
	if f then
		local ok, res = pcall(function()
			return f:Invoke("spend", p, amount, label)
		end)
		if ok and res == true then
			return true, nil
		end
		return false, "잔액이 부족해요"
	end
	return false, "지금은 결제할 수 없어요"
end

function Bridge.earn(p: Player, amount: number, label: string): boolean
	amount = math.floor(amount)
	if amount <= 0 then
		return false
	end
	local E = mods.Economy
	if E and type(E.earn) == "function" then
		local ok = pcall(E.earn, p, amount, label)
		if ok then
			return true
		end
	end
	local f = gameplayApi()
	if f then
		local ok, res = pcall(function()
			return f:Invoke("earn", p, amount, label)
		end)
		return ok and res ~= false
	end
	return false
end

function Bridge.track(p: Player, key: string, n: number?)
	local f = ServerStorage:FindFirstChild("GwangalliProgressAPI")
	if f and f:IsA("BindableFunction") then
		task.spawn(function()
			pcall(function()
				f:Invoke("track", p, key, n or 1)
			end)
		end)
	end
end

-------------------------------------------------------------------------------------------------
-- who works where
-------------------------------------------------------------------------------------------------
-- the player is on a job / shift / manager duty right now
function Bridge.working(p: Player): boolean
	if p:GetAttribute("OnShift") == true then
		return true
	end
	for _, a in Config.WORK_ATTRS do
		local v = p:GetAttribute(a)
		if v ~= nil and v ~= false and v ~= "" and v ~= 0 then
			return true
		end
	end
	local act = p:GetAttribute("GwPlayActivity")
	if type(act) == "string" and Config.WORK_ACTIVITIES[act] then
		return true
	end
	return false
end

-- ShopStaff counter sites: { { pos = Vector3 (feet), model = Model?, label } }
function Bridge.staffSites(): { any }
	local out = {}
	local S = mods.ShopStaff
	if S and type(S.sites) == "function" then
		local ok, list = pcall(S.sites)
		if ok and type(list) == "table" then
			for _, s in list do
				if type(s) == "table" and typeof(s.pos) == "Vector3" then
					table.insert(out, { pos = s.pos, model = s.model, label = s.kind and s.kind.label, kind = s.kind and s.kind.k })
				end
			end
		end
	end
	return out
end

-- positions of the Destination parts whose name is a job site (the player works there)
local jobSiteCache: { Vector3 }? = nil
function Bridge.jobSites(): { Vector3 }
	if jobSiteCache then
		return jobSiteCache
	end
	local out = {}
	local want = {}
	for _, n in Config.JOB_SITES do
		want[n] = true
	end
	for _, d in CollectionService:GetTagged("Destination") do
		if d:IsA("BasePart") then
			local name = d:GetAttribute("DisplayName")
			local n = if type(name) == "string" then name else string.gsub(d.Name, "^Destination_", "")
			if want[n] then
				table.insert(out, d.Position)
			end
		end
	end
	jobSiteCache = out
	return out
end

-- 길 묻기: every Destination part { name, pos, order }
function Bridge.destinations(): { any }
	local out = {}
	local seen = {}
	for _, d in CollectionService:GetTagged("Destination") do
		if d:IsA("BasePart") then
			local name = d:GetAttribute("DisplayName")
			local n = if type(name) == "string" and name ~= "" then name else (string.gsub(d.Name, "^Destination_", ""))
			if n ~= "" and not seen[n] then
				seen[n] = true
				table.insert(out, { name = n, pos = d.Position, order = tonumber(d:GetAttribute("Order")) or 999 })
			end
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- GwangalliShopService (the add-on pack's simple waiter)
-------------------------------------------------------------------------------------------------
function Bridge.shopService(): Script?
	local s = ServerScriptService:FindFirstChild("GwangalliShopService")
	return if s and s:IsA("BaseScript") then s :: any else nil
end

function Bridge.shopServiceRunning(): boolean
	local s = Bridge.shopService()
	if not s then
		return false
	end
	local enabled = true
	pcall(function()
		enabled = (s :: any).Enabled
	end)
	local disabled = false
	pcall(function()
		disabled = (s :: any).Disabled
	end)
	return enabled and not disabled
end

-- stop it and hand its shops back to ShopLife (its waiters removed, their ready table orders served)
function Bridge.takeOverShopService(): number
	local s = Bridge.shopService()
	if s then
		local ok = pcall(function()
			(s :: any).Enabled = false
		end)
		if not ok then
			pcall(function()
				(s :: any).Disabled = true
			end)
		end
	end
	local folder = workspace:FindFirstChild("GwangalliShopStaff")
	local n = 0
	if folder then
		for _, m in folder:GetChildren() do
			local key = m:GetAttribute("GwWaiter")
			if m:IsA("Model") and type(key) == "string" and key ~= "diner" then
				n += 1
				if busRequest then
					Bridge.req("staffMode", { shop = key, on = false })
					local q = Bridge.req("queue", { shop = key })
					for _, o in (if q.ok and type(q.orders) == "table" then q.orders else {}) do
						if o.phase == "ready" and o.dest == "table" then
							Bridge.req("serve", { orderId = o.orderId })
						end
					end
				end
				m:Destroy()
			end
		end
	end
	if s or n > 0 then
		print(string.format("[GwangalliShopCrew] took over GwangalliShopService (%d waiter%s removed)", n, if n == 1 then "" else "s"))
	end
	return n
end

-------------------------------------------------------------------------------------------------
-- players
-------------------------------------------------------------------------------------------------
function Bridge.rootOf(p: Player): BasePart?
	local c = p.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		local h = c:FindFirstChildOfClass("Humanoid")
		if h and h.Health <= 0 then
			return nil
		end
		return r
	end
	return nil
end

function Bridge.posOf(p: Player): Vector3?
	local r = Bridge.rootOf(p)
	return r and r.Position
end

function Bridge.playerById(uid: any): Player?
	if type(uid) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(uid)
end

return Bridge
