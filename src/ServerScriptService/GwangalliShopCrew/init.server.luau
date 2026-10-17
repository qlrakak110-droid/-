-- GwangalliShopCrew (Script, ServerScriptService): 가게 직원 크루 — staff who greet you, take your order at the
-- table, cook in view, carry the tray to your table, clear it, answer questions (메뉴 · 추천 · 길 묻기 · 칭찬 ·
-- 항의 · 팁), remember regulars (단골 · 도장 쿠폰) and NPC diners who eat there too. Every shop's own staff
-- (ShopStaff counter rigs, GwShopClerk figures, PC방 / 노래방 알바) get the same conversation.
-- An ADD-ON: it plugs into ShopLife's bus (ServerStorage.GwangalliShopLife) and finds every other system at
-- runtime (pcall + timeouts); no place script is edited. Without the bus it does nothing.
--   Off switch: workspace attribute GwShopCrew = false.   Debug: workspace attribute GwShopCrewDebug = true.
--   This Script's attributes (optional): TakeOverShopService (bool), Diners (bool), MaxShops (number), Debug (bool),
--     Augment (bool).
--   ServerStorage.GwangalliShopCrew: API (BindableFunction) "status" | "standDown"(key, on) | "crew"(key) |
--     "regular"(userId, key) | "serveNow"(key); attribute Ready.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

if workspace:GetAttribute("GwShopCrew") == false then
	return
end

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliShopCrewShared", 60))
local Config = Shared.Config

-- overrides ---------------------------------------------------------------------------------------
do
	local a = script:GetAttribute("TakeOverShopService")
	if type(a) == "boolean" then
		Config.TAKE_OVER_SHOP_SERVICE = a
	end
	a = script:GetAttribute("Diners")
	if type(a) == "boolean" then
		Config.DINERS.enabled = a
	end
	a = script:GetAttribute("MaxShops")
	if type(a) == "number" then
		Config.MAX_SHOPS = math.clamp(math.floor(a), 1, 12)
	end
	a = script:GetAttribute("Augment")
	if type(a) == "boolean" then
		Config.AUGMENT_STAFF = a
	end
	if script:GetAttribute("Debug") == true or workspace:GetAttribute("GwShopCrewDebug") == true then
		Config.DEBUG = true
	end
end

local Bridge = require(script:WaitForChild("Bridge"))
local Net = require(script:WaitForChild("Net"))
local Sites = require(script:WaitForChild("Sites"))
local Rig = require(script:WaitForChild("Rig"))
local Serve = require(script:WaitForChild("Serve"))
local Regulars = require(script:WaitForChild("Regulars"))
local Crew = require(script:WaitForChild("Crew"))
local Diners = require(script:WaitForChild("Diners"))
local Talk = require(script:WaitForChild("Talk"))
local Augment = require(script:WaitForChild("Augment"))
local Director = require(script:WaitForChild("Director"))

Bridge.init(Config)

-- the add-on pack's simple waiter: taken over before it can spawn anyone (pass #1)
local shopServiceSeen = Bridge.shopService() ~= nil
if Config.TAKE_OVER_SHOP_SERVICE and shopServiceSeen then
	Bridge.takeOverShopService()
end

Net.create(Shared)

-- ServerStorage API -----------------------------------------------------------------------------------
local apiFolder = ServerStorage:FindFirstChild(Shared.API)
if not apiFolder then
	apiFolder = Instance.new("Folder")
	apiFolder.Name = Shared.API
	apiFolder.Parent = ServerStorage
end
apiFolder:SetAttribute("Ready", false)
local api = apiFolder:FindFirstChild("API") or Instance.new("BindableFunction")
api.Name = "API"
api.Parent = apiFolder
local apiEvent = apiFolder:FindFirstChild("Event") or Instance.new("BindableEvent")
apiEvent.Name = "Event"
apiEvent.Parent = apiFolder

-- wait for the building system (ShopLife) ----------------------------------------------------------------
-- (GwB_Ready: every building service is up; GwB_ShopLife: ShopLife finished its map scan)
local t0 = os.clock()
while workspace:GetAttribute("GwB_Ready") ~= true and workspace:GetAttribute("GwB_ShopLife") == nil and os.clock() - t0 < 120 do
	task.wait(1)
end
if not Bridge.bindBus(60) then
	warn("[GwangalliShopCrew] ServerStorage.GwangalliShopLife (ShopLife bus) not found: shop crew off")
	return
end
Bridge.bindModules()
if not Bridge.Looks then
	warn("[GwangalliShopCrew] ReplicatedStorage.GwangalliNPCLooks missing: no crew rigs (dialogs with the shops' own staff still work)")
end

-- pass #2: its waiters may have spawned while we waited
if Config.TAKE_OVER_SHOP_SERVICE and Bridge.shopService() then
	Bridge.takeOverShopService()
end
local coexist = (not Config.TAKE_OVER_SHOP_SERVICE) and Bridge.shopServiceRunning()

local mods = { Sites = Sites, Rig = Rig, Serve = Serve, Regulars = Regulars, Crew = Crew, Diners = Diners, Talk = Talk, Augment = Augment }
Sites.init(Shared, Bridge)
Rig.init(Shared, Bridge, Net)
Serve.init(Shared, Bridge, Net)
Regulars.init(Shared, Bridge, Net)
Crew.init(Shared, Bridge, Net, mods)
Diners.init(Shared, Bridge, Net, mods)
Talk.init(Shared, Bridge, Net, mods)
Augment.init(Shared, Bridge, Net, mods)
Director.init(Shared, Bridge, Net, mods)
Director.setCoexist(coexist)
Crew.setTalk(Talk)
Talk.setResolver(Director.resolve)
Rig.onTalk(function(player, R)
	local T = Director.resolve(R.id)
	if T then
		Talk.open(player, T)
	end
end)

-- remotes the client uses besides talk / choose
Net.on("card", function(p, d)
	local key = Shared.Util.cleanString(d.shop, 120)
	if not key then
		return { ok = false }
	end
	local rec = Bridge.shopRec(key)
	return { ok = true, card = Regulars.card(p, key, rec and tostring(rec.name) or key) }
end)
Net.on("hello", function(p)
	local key = Bridge.shopOf(p)
	return { ok = true, version = Shared.VERSION, shop = key }
end)

Regulars.start()
Bridge.onEvent(Director.onBus)
Director.start()
Augment.start()

api.OnInvoke = function(op: any, a: any, b: any)
	if op == "status" then
		return Director.status()
	elseif op == "standDown" and type(a) == "string" then
		Director.standDown(a, b ~= false)
		return true
	elseif op == "crew" and type(a) == "string" then
		local crew = Director.crewOf(a)
		return if crew then Crew.status(crew) else nil
	elseif op == "regular" and type(a) == "number" and type(b) == "string" then
		return Regulars.view(a, b)
	elseif op == "serveNow" and type(a) == "string" then
		return Serve.flush(a)
	end
	return nil
end

local function shutdown()
	pcall(Director.shutdown)
	pcall(Augment.cleanup)
	pcall(Regulars.saveAll)
end
game:BindToClose(shutdown)
script.Destroying:Connect(shutdown)
pcall(function()
	script:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not (script :: any).Enabled then
			shutdown()
		end
	end)
end)

apiFolder:SetAttribute("Ready", true)
local eligible = 0
for _ in Bridge.shops() do
	eligible += 1
end
print(string.format("[GwangalliShopCrew] ready (%d ShopLife shops, %s, augment %s, diners %s)", eligible, if coexist then "coexisting with GwangalliShopService" else "serving", tostring(Config.AUGMENT_STAFF), tostring(Config.DINERS.enabled)))
