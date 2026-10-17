-- GwangalliCarDealer/Bridge (server): every integration with the owner's existing systems, found at runtime
-- and pcall-guarded. Buying, selling, renting, calling and the kit test drive always go through the garage's
-- own server API, so prices, the 3-car limit, 할부, plates, saving, notifications and achievements stay the
-- garage's; this add-on never re-implements them.
--
--   Garage API     ServerStorage.GwangalliGarageAPI (BindableFunction, Garage.luau bindApi):
--                  "status" (player) -> { cars, max, owned, bank, cash, atGarage, outId, testCooldown, testing, loaded }
--                  "cars" (player) -> { carView }   "request" (player, op, payload) -> the GarageRequest result
--   Vehicles API   ServerStorage.GwangalliVehiclesAPI: spawnOwned / despawn / current / eject / seat (dealer test)
--   Gameplay API   ServerStorage.GwangalliGameplayAPI: balance -> cash, bank · earn (refund-labelled cash-back)
--   map markers    tags GarageShop (venue, Route attribute) · GarageSpawn · GarageReturn · GarageTurntable ·
--                  GarageShowroomCar · GarageStaff
--   templates      ServerStorage.GwangalliCarModels (showroom models) · ServerStorage.GwangalliDriveTemplates /
--                  parked map cars (kit kinds), the same lookup as GwangalliVehicles/Spawn

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Bridge = {}

local S: any
local C: any

function Bridge.init(shared: any)
	S = shared
	C = shared.Config
end

local function log(...)
	if C and C.Debug then
		print("[GwangalliCarDealer]", ...)
	end
end
Bridge.log = log

local function bindable(name: string): BindableFunction?
	local f = ServerStorage:FindFirstChild(name)
	if f and f:IsA("BindableFunction") then
		return f
	end
	return nil
end

-- Invoke a BindableFunction on its own thread with a timeout -> status ("ok" | "noapi" | "error" | "timeout"), results...
local function invoke(name: string, timeout: number, ...: any): (string, ...any)
	local api = bindable(name)
	if not api then
		return "noapi"
	end
	local args = table.pack(...)
	local done, ok, res = false, false, nil
	task.spawn(function()
		local r = table.pack(pcall(api.Invoke, api, table.unpack(args, 1, args.n)))
		ok = r[1]
		res = r
		done = true
	end)
	local t0 = os.clock()
	while not done do
		if os.clock() - t0 > timeout then
			warn("[GwangalliCarDealer] " .. name .. " timed out")
			return "timeout"
		end
		task.wait()
	end
	if not ok then
		warn("[GwangalliCarDealer] " .. name .. " failed: " .. tostring(res and res[2]))
		return "error"
	end
	return "ok", table.unpack(res :: any, 2, (res :: any).n)
end

-- Garage ----------------------------------------------------------------------------------------------
function Bridge.garageReady(): boolean
	return bindable(S.NAMES.Garage.Api) ~= nil
end

-- Waits (once, in the background caller) for the garage API to appear.
function Bridge.waitGarage(timeout: number): boolean
	local t0 = os.clock()
	while not Bridge.garageReady() and os.clock() - t0 < timeout do
		task.wait(0.5)
	end
	return Bridge.garageReady()
end

local function failRes(code: string, message: string): { [string]: any }
	return { ok = false, code = code, message = message }
end
Bridge.fail = failRes

-- The garage's own request handler (same validation as its RemoteFunction). Always returns a table.
function Bridge.request(player: Player, op: string, payload: { [string]: any }?): { [string]: any }
	local st, res = invoke(S.NAMES.Garage.Api, 20, "request", player, op, payload or {})
	if st == "noapi" then
		return failRes("offline", "정비소 전산이 아직 준비되지 않았어요")
	elseif st ~= "ok" then
		return failRes("error", "처리하지 못했어요 · 잠시 후 다시 시도해 주세요")
	end
	if type(res) ~= "table" then
		return failRes("error", "처리하지 못했어요")
	end
	return res
end

function Bridge.status(player: Player): { [string]: any }?
	local st, res = invoke(S.NAMES.Garage.Api, 10, "status", player)
	if st == "ok" and type(res) == "table" then
		-- the newer garage wraps status in its result format; both carry the fields at the top level
		return res
	end
	return nil
end

-- Vehicles ----------------------------------------------------------------------------------------------
function Bridge.vehicles(op: string, ...: any): ...any
	local st = table.pack(invoke("GwangalliVehiclesAPI", 15, op, ...))
	if st[1] ~= "ok" then
		return nil
	end
	return table.unpack(st, 2, st.n)
end

-- Money ---------------------------------------------------------------------------------------------------
function Bridge.balance(player: Player): (number, number)
	local st, cash, bank = invoke("GwangalliGameplayAPI", 5, "balance", player)
	if st == "ok" and type(cash) == "number" and type(bank) == "number" then
		return bank, cash
	end
	local b = player:GetAttribute("Bank")
	local m = player:GetAttribute("Money")
	return (if type(b) == "number" then b else 0), (if type(m) == "number" then m else 0)
end

-- Bank credit (refund-labelled benefits). -> ok
function Bridge.credit(player: Player, amount: number, label: string): boolean
	if not S.Util.finite(amount) or amount <= 0 then
		return false
	end
	local st, ok = invoke("GwangalliGameplayAPI", 8, "earn", player, math.floor(amount), label)
	return st == "ok" and ok ~= false and ok ~= nil
end

-- Player state ---------------------------------------------------------------------------------------------
function Bridge.level(player: Player): number
	local v = player:GetAttribute("LifeLevel")
	return if type(v) == "number" and v == v then math.clamp(math.floor(v), 1, 999) else 1
end

function Bridge.root(player: Player): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

function Bridge.alive(player: Player): boolean
	local ch = player.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

-- Why this player cannot start a test drive / contract right now (nil = fine): shift, taxi, cuffs, dead.
function Bridge.blocked(player: Player): string?
	if player:GetAttribute("OnShift") == true then
		return "shift"
	end
	if player:GetAttribute("InTaxi") == true then
		return "taxi"
	end
	if player:GetAttribute("LawCuffed") == true then
		return "cuffed"
	end
	if not Bridge.alive(player) then
		return "dead"
	end
	return nil
end

-- Map ------------------------------------------------------------------------------------------------------
local function firstTagged(tag: string): Instance?
	for _, x in CollectionService:GetTagged(tag) do
		if x:IsDescendantOf(workspace) then
			return x
		end
	end
	return nil
end
Bridge.firstTagged = firstTagged

function Bridge.venue(): Instance?
	return firstTagged("GarageShop")
end

function Bridge.marker(tag: string): BasePart?
	local x = firstTagged(tag)
	return if x and x:IsA("BasePart") then x else nil
end

-- Ground frame of a marker part (bottom centre, LookVector = heading), like the garage's groundFrame.
function Bridge.groundFrame(part: BasePart): CFrame
	local cf = part.CFrame
	local p = cf.Position - Vector3.new(0, part.Size.Y / 2, 0)
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.zAxis
	end
	return CFrame.lookAt(p, p + look.Unit)
end

-- The 시승 loop of the venue ("x,y,z|x,y,z|..." on the GarageShop root, else tagged route points).
function Bridge.route(): { Vector3 }
	local out = {}
	local shop = Bridge.venue()
	local packed = shop and shop:GetAttribute("Route")
	if type(packed) == "string" then
		for item in string.gmatch(packed, "[^|]+") do
			local x, y, z = string.match(item, "^([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$")
			if x then
				table.insert(out, Vector3.new(tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number))
			end
			if #out >= 40 then
				break
			end
		end
		if #out > 0 then
			return out
		end
	end
	local pts = {}
	for _, p in CollectionService:GetTagged("GarageRoutePoint") do
		if p:IsA("BasePart") then
			table.insert(pts, { i = tonumber(p:GetAttribute("Index")) or 0, pos = p.Position })
		end
	end
	table.sort(pts, function(a, b)
		return a.i < b.i
	end)
	for _, p in pts do
		table.insert(out, p.pos)
	end
	return out
end

-- Templates ---------------------------------------------------------------------------------------------------
-- The real 3D template of a showroom model id (same lookup as GwangalliVehicles/Spawn.modelTemplate).
function Bridge.modelTemplate(id: string): Model?
	local GS = S.GS(0)
	local entry = GS and type(GS.modelInfo) == "function" and GS.modelInfo(id)
	if not entry then
		return nil
	end
	local holder = ServerStorage:FindFirstChild(GS.MODELS_FOLDER or "GwangalliCarModels")
	if not holder then
		return nil
	end
	local t = holder:FindFirstChild(entry.real)
	if t and t:IsA("Model") then
		return t
	end
	for _, c in holder:GetChildren() do
		if c:IsA("Model") and c:GetAttribute("GwCarModel") == entry.real then
			return c
		end
	end
	return nil
end

-- showroom model id -> true when its template exists (what the catalog lists and the dealer test drives)
function Bridge.availableModels(): { [string]: boolean }
	local out = {}
	local GS = S.GS(0)
	if GS and type(GS.MODELS) == "table" then
		for _, m in GS.MODELS do
			if type(m) == "table" and type(m.id) == "string" and Bridge.modelTemplate(m.id) then
				out[m.id] = true
			end
		end
	end
	return out
end

local function isTraffic(m: Instance): boolean
	local node = m.Parent
	while node and node ~= workspace do
		if node.Name == "TrafficVehicles" then
			return true
		end
		node = node.Parent
	end
	return false
end

-- The model the garage delivers for a kit kind: the spawn system's cached template, else the first parked map
-- car of that kind (never traffic / NoDrive / rigged), else the showroom display car of that kind.
function Bridge.kitSource(kind: string): Model?
	local holder = ServerStorage:FindFirstChild("GwangalliDriveTemplates")
	if holder then
		for _, c in holder:GetChildren() do
			if c:IsA("Model") and c:GetAttribute("VehicleKind") == kind then
				return c
			end
		end
	end
	local map = workspace:FindFirstChild("Gwangalli") or workspace
	local n = 0
	for _, d in map:GetDescendants() do
		n += 1
		if n % 4000 == 0 then
			task.wait()
		end
		if d:IsA("Model") and d:GetAttribute("VehicleKind") == kind and not d:GetAttribute("DriveRigged") and not d:GetAttribute("NoDrive") and not isTraffic(d) then
			return d
		end
	end
	for _, d in CollectionService:GetTagged("GarageDisplayCar") do
		if d:IsA("Model") and d:GetAttribute("GarageKind") == kind then
			return d
		end
	end
	return nil
end

function Bridge.players(): { Player }
	return Players:GetPlayers()
end

return Bridge
