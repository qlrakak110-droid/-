-- Housing: 내집마련 — buying homes on the ladder 원룸 -> 빌라 -> 오피스텔 -> 아파트 -> 펜트하우스.
--   * every unit of every building is a real, enterable home with a price (floor, view, age) and a
--     매매 sign at its door; vacant units are open houses (staged furniture, anyone can look around)
--   * buying (부동산 / 관리사무소 / the 매물 sign): ladder check (Config.LADDER_REQUIRED), the old home
--     is sold back (Config.TRADE_IN) and the difference is charged through Economy
--   * the home record is saved per player (DataStore Config.HOME_STORE): template, building, tier,
--     furniture layout in TEMPLATE space (fits mirrored units too), themes, storage. On join the player
--     gets a physical unit of that type (the same one when free)
--   * 도어락: owner, invited guests and tour viewers open the door; others ring the bell -> the owner
--     gets "문 열어주기"
--   Housing.canEnter(p, unitId) / rightsOf(p, unitId) / record(p) / unitOf(p) / ring / openRealtor

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Homes = Shared.Homes
local Util = Shared.Util

local Housing = {}

local Registry: any
local services: any
local Builder: any
local store: DataStore? = nil

local records: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}
local owner: { [string]: Player } = {} -- unitId -> owner online in this server
local guests: { [string]: { [Player]: number } } = {} -- unitId -> guest -> expiry (os.clock)
local tours: { [Player]: { unitId: string, untilT: number } } = {}

local function defaultRecord(): any
	return { v = 1, tier = nil, maxTier = nil, template = nil, buildingId = nil, preferUnit = nil, price = 0, layout = { items = {} }, themes = {}, storage = {} }
end

function Housing.record(p: Player): any
	return records[p]
end

function Housing.markDirty(p: Player)
	dirty[p] = true
end

function Housing.unitOf(p: Player): any?
	for id, o in owner do
		if o == p then
			return Registry.unit(id)
		end
	end
	return nil
end

function Housing.ownerOf(unitId: string): Player?
	local o = owner[unitId]
	if o and o.Parent then
		return o
	end
	return nil
end

-- "owner" | "guest" | "viewer" | nil
function Housing.rightsOf(p: Player, unitId: string?): string?
	if not unitId then
		return nil
	end
	local u = Registry.unit(unitId)
	if not u then
		return nil
	end
	local o = Housing.ownerOf(unitId)
	if o == p then
		return "owner"
	end
	local g = guests[unitId]
	if g and g[p] and os.clock() < g[p] then
		return "guest"
	end
	if not o then
		return "viewer" -- open house: vacant units can be looked around
	end
	local t = tours[p]
	if t and t.unitId == unitId and os.clock() < t.untilT then
		return "viewer"
	end
	if u.model and u.model:GetAttribute("OpenHouse") == true then
		return "guest"
	end
	return nil
end

function Housing.canEnter(p: Player, unitId: any): boolean
	if type(unitId) ~= "string" then
		return false
	end
	return Housing.rightsOf(p, unitId) ~= nil
end

-------------------------------------------------------------------------------------------------
-- unit presentation (sale sign, attributes)
-------------------------------------------------------------------------------------------------
local function present(u: any)
	local m = u.model
	if not m then
		return
	end
	local o = Housing.ownerOf(u.id)
	m:SetAttribute("OwnerUserId", if o then o.UserId else 0)
	m:SetAttribute("OwnerName", if o then o.DisplayName else "")
	m:SetAttribute("ForSale", o == nil)
	local st = m:FindFirstChild("Structure")
	local sign = st and st:FindFirstChild("SaleSign")
	if sign and sign:IsA("BasePart") then
		local g = sign:FindFirstChildWhichIsA("SurfaceGui")
		local t = g and g:FindFirstChild("SaleText")
		if o then
			sign.Color = Color3.fromRGB(40, 44, 52)
			if t and t:IsA("TextLabel") then
				t.Text = "🏠 " .. o.DisplayName .. "님 댁"
			end
		else
			sign.Color = Color3.fromRGB(30, 120, 220)
			if t and t:IsA("TextLabel") then
				t.Text = "매매 " .. Util.won(u.price)
			end
		end
	end
end
Housing.present = present

local function refurnish(u: any)
	present(u)
	if Builder then
		Builder.refurnishUnit(u)
	end
end

-------------------------------------------------------------------------------------------------
-- allocation
-------------------------------------------------------------------------------------------------
local function freeUnit(template: string, buildingId: string?, prefer: string?): any?
	if prefer then
		local u = Registry.unit(prefer)
		if u and u.template == template and not Housing.ownerOf(prefer) then
			return u
		end
	end
	local fallback = nil
	for _, rec in Registry.recs do
		for _, u in rec.unitList do
			if u.template == template and not Housing.ownerOf(u.id) then
				if rec.id == buildingId then
					return u
				end
				fallback = fallback or u
			end
		end
	end
	return fallback
end

local function assign(p: Player, u: any)
	owner[u.id] = p
	p:SetAttribute("GwB_HomeUnit", u.id)
	p:SetAttribute("GwB_HomeLabel", string.format("%s %s", u.rec.name, u.label))
	p:SetAttribute("GwB_HomeTier", u.tier)
	refurnish(u)
end

local function release(p: Player)
	for id, o in owner do
		if o == p then
			owner[id] = nil
			guests[id] = nil
			local u = Registry.unit(id)
			if u then
				refurnish(u)
			end
		end
	end
	p:SetAttribute("GwB_HomeUnit", nil)
	p:SetAttribute("GwB_HomeLabel", nil)
end

-------------------------------------------------------------------------------------------------
-- listings / UI payloads
-------------------------------------------------------------------------------------------------
local function listing(u: any, p: Player): any
	local t = Homes.TEMPLATES[u.template]
	local o = Housing.ownerOf(u.id)
	return {
		id = u.id,
		building = u.rec.name,
		buildingId = u.rec.id,
		archetype = u.rec.archetype,
		floor = u.floor,
		level = u.level,
		number = u.label,
		template = u.template,
		name = t.name,
		type = t.type,
		tier = t.tier,
		rooms = t.rooms,
		baths = t.baths,
		area = Util.area(t.w * t.d),
		view = u.view,
		price = u.price,
		wear = u.rec.wear,
		owned = o ~= nil,
		ownerName = o and o.DisplayName or nil,
		mine = o == p,
	}
end

function Housing.listings(p: Player, buildingId: string?): { any }
	local out = {}
	for _, rec in Registry.recs do
		if not buildingId or rec.id == buildingId then
			for _, u in rec.unitList do
				local t = Homes.TEMPLATES[u.template]
				if t and not t.hotel then
					table.insert(out, listing(u, p))
				end
			end
		end
	end
	table.sort(out, function(a, b)
		local ta, tb = Homes.tierIndex(a.tier), Homes.tierIndex(b.tier)
		if ta ~= tb then
			return ta < tb
		end
		return a.price < b.price
	end)
	return out
end

local function summary(p: Player): any
	local r = records[p] or defaultRecord()
	local u = Housing.unitOf(p)
	return {
		tier = r.tier,
		maxTier = r.maxTier,
		template = r.template,
		price = r.price,
		unitId = u and u.id,
		label = u and (u.rec.name .. " " .. u.label),
		balance = services.Economy and services.Economy.balance(p) or 0,
		canTest = services.Economy and services.Economy.canTestGrant() and p:GetAttribute("GwB_TestGranted") ~= true,
		ladder = Config.LADDER_REQUIRED,
		tradeIn = Config.TRADE_IN,
	}
end

function Housing.openRealtor(p: Player, buildingId: string?)
	Registry.fire(p, "home.listings", { listings = Housing.listings(p, buildingId), me = summary(p), buildingId = buildingId, tiers = Homes.TIERS })
end

-------------------------------------------------------------------------------------------------
-- buying
-------------------------------------------------------------------------------------------------
function Housing.buy(p: Player, unitId: string): any
	local u = Registry.unit(unitId)
	local r = records[p]
	if not u or not r then
		return { ok = false, msg = "매물을 찾을 수 없어요" }
	end
	local t = Homes.TEMPLATES[u.template]
	if not t or t.hotel then
		return { ok = false, msg = "판매하지 않는 집이에요" }
	end
	local o = Housing.ownerOf(unitId)
	if o == p then
		return { ok = false, msg = "이미 내 집이에요" }
	elseif o then
		return { ok = false, msg = "다른 주인이 살고 있는 집이에요" }
	end
	local ok, why = Homes.canClimb(r.maxTier, t.tier, Config.LADDER_REQUIRED)
	if not ok then
		return { ok = false, msg = why }
	end
	local tradeIn = if r.template then math.floor((r.price or 0) * Config.TRADE_IN) else 0
	local net = u.price - tradeIn
	if net > 0 then
		local paid, msg = services.Economy.spend(p, net, string.format("%s %s 매매", u.rec.name, u.label))
		if not paid then
			return { ok = false, msg = (msg or "잔액 부족") .. (if tradeIn > 0 then string.format(" (기존 집 매각 %s 반영)", Util.won(tradeIn)) else "") }
		end
	elseif net < 0 then
		services.Economy.earn(p, -net, "집 갈아타기 차액")
	end
	local sameTemplate = r.template == u.template
	release(p)
	-- furniture of the old home goes to storage when the floor plan changes
	if not sameTemplate and r.layout and r.layout.items then
		for _, it in r.layout.items do
			r.storage[it.id] = (r.storage[it.id] or 0) + 1
		end
		r.layout = { items = {} }
		r.themes = {}
	end
	r.template = u.template
	r.buildingId = u.rec.id
	r.preferUnit = u.id
	r.tier = t.tier
	r.price = u.price
	if Homes.tierIndex(t.tier) > Homes.tierIndex(r.maxTier) then
		r.maxTier = t.tier
	end
	r.boughtAt = os.time()
	dirty[p] = true
	assign(p, u)
	Registry.fire(p, "fx", { kind = "celebrate", label = string.format("🎉 내 집 마련! %s %s", u.rec.name, u.label) })
	Registry.fire(p, "home.update", summary(p))
	if services.Economy then
		services.Economy.addStats(p, { happiness = 5 }, "내 집 마련")
	end
	return { ok = true, msg = string.format("계약 완료! %s %s (%s%s)", u.rec.name, u.label, Util.won(u.price), if tradeIn > 0 then ", 기존 집 매각 " .. Util.won(tradeIn) else ""), unitId = u.id }
end

-- the spot just outside / inside a unit's entrance
local function doorSpot(u: any, inside: boolean): CFrame?
	local L = u.layout
	if not L then
		return nil
	end
	local frame = u.rec.cf * CFrame.new(0, u.fl.y, 0) * u.frame
	local z = if inside then 2.2 else -2.4
	return frame * CFrame.new(L.door, 3.2, z) * CFrame.Angles(0, if inside then math.pi else 0, 0)
end

function Housing.visit(p: Player, u: any, inside: boolean)
	local St = services.Streaming
	if St then
		-- the storey builds in its own thread (the floor slab is part of the shell, so arriving early is safe)
		task.spawn(St.ensureFloor, u.rec, u.fl)
	end
	local cf = doorSpot(u, inside)
	if cf then
		Registry.teleport(p, cf)
	end
end

function Housing.ring(visitor: Player, unitId: any)
	if type(unitId) ~= "string" then
		return
	end
	local o = Housing.ownerOf(unitId)
	if o and o ~= visitor then
		Registry.fire(o, "home.ring", { from = visitor.DisplayName, userId = visitor.UserId, unitId = unitId })
		Registry.toast(visitor, "띵동~ " .. o.DisplayName .. "님께 알렸어요", "info")
	end
end

-------------------------------------------------------------------------------------------------
-- persistence
-------------------------------------------------------------------------------------------------
local function load(p: Player)
	local data = nil
	if store then
		local ok, v = pcall(function()
			return (store :: DataStore):GetAsync("u_" .. p.UserId)
		end)
		if ok and type(v) == "table" then
			data = v
		end
	end
	local r = defaultRecord()
	if data then
		for k, v in data do
			r[k] = v
		end
		r.layout = if type(r.layout) == "table" then r.layout else { items = {} }
		r.layout.items = if type(r.layout.items) == "table" then r.layout.items else {}
		r.themes = if type(r.themes) == "table" then r.themes else {}
		r.storage = if type(r.storage) == "table" then r.storage else {}
	end
	records[p] = r
	dirty[p] = false
	if r.template and Homes.TEMPLATES[r.template] then
		local u = freeUnit(r.template, r.buildingId, r.preferUnit)
		if u then
			assign(p, u)
		else
			Registry.toast(p, "이 서버에는 같은 타입의 빈 집이 없어 오늘은 숙소를 이용해요", "warn")
		end
	end
	Registry.fire(p, "home.update", summary(p))
end

local function save(p: Player)
	local r = records[p]
	if not store or not r or not dirty[p] then
		return
	end
	local copy = table.clone(r)
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync("u_" .. p.UserId, copy)
	end)
	if ok then
		dirty[p] = false
	else
		warn("[GwangalliBuildings] home save failed: " .. tostring(err))
	end
end
Housing.save = save

-------------------------------------------------------------------------------------------------
-- lifecycle
-------------------------------------------------------------------------------------------------
function Housing.onHot(rec: any)
	for _, u in rec.unitList do
		present(u)
	end
end

function Housing.init(ctx: any)
	Registry = ctx.Registry
	services = ctx.services
	Builder = ctx.Builder
	pcall(function()
		store = DataStoreService:GetDataStore(Config.HOME_STORE)
	end)
	Registry.on("home.listings", function(p: Player, d: any)
		return { ok = true, listings = Housing.listings(p, d.buildingId), me = summary(p), tiers = Homes.TIERS }
	end)
	Registry.on("home.state", function(p: Player)
		return { ok = true, me = summary(p) }
	end)
	Registry.on("home.buy", function(p: Player, d: any)
		if type(d.unitId) ~= "string" then
			return { ok = false }
		end
		return Housing.buy(p, d.unitId)
	end)
	Registry.on("home.tour", function(p: Player, d: any)
		local u = Registry.unit(d.unitId)
		if not u or Homes.TEMPLATES[u.template].hotel then
			return { ok = false }
		end
		local o = Housing.ownerOf(u.id)
		if o and o ~= p then
			return { ok = false, msg = "다른 사람이 사는 집은 둘러볼 수 없어요" }
		end
		tours[p] = { unitId = u.id, untilT = os.clock() + Config.TOUR_SECONDS }
		Housing.visit(p, u, true)
		return { ok = true, msg = string.format("🏠 %s %s 둘러보기 (%s)", u.rec.name, u.label, Util.clock(Config.TOUR_SECONDS)) }
	end)
	Registry.on("home.enter", function(p: Player)
		local u = Housing.unitOf(p)
		if not u then
			return { ok = false, msg = "아직 집이 없어요. 부동산에서 집을 구해요" }
		end
		Housing.visit(p, u, true)
		return { ok = true }
	end)
	Registry.on("home.invite", function(p: Player, d: any)
		local u = Housing.unitOf(p)
		local guest = Players:GetPlayerByUserId(tonumber(d.userId) or 0)
		if not u or not guest then
			return { ok = false }
		end
		guests[u.id] = guests[u.id] or {}
		guests[u.id][guest] = os.clock() + 1800
		local D = services.Doors
		if D then
			for _, door in D.forUnit(u.id) do
				D.setOpen(door, true, guest)
			end
		end
		Registry.toast(guest, "🔓 " .. p.DisplayName .. "님이 문을 열어줬어요", "ok")
		return { ok = true }
	end)
	Registry.on("home.openHouse", function(p: Player, d: any)
		local u = Housing.unitOf(p)
		if not u or not u.model then
			return { ok = false }
		end
		u.model:SetAttribute("OpenHouse", d.on == true)
		return { ok = true, msg = if d.on then "🎉 집들이 모드: 누구나 들어올 수 있어요" else "🔒 다시 잠갔어요" }
	end)
	Registry.on("home.testMoney", function(p: Player)
		local E = services.Economy
		if not E or not E.testGrant(p) then
			return { ok = false, msg = "테스트 자금은 테스트 환경에서 한 번만 받을 수 있어요" }
		end
		return { ok = true, msg = "💰 테스트 자금 " .. Util.won(Config.TEST_MONEY_GRANT) .. " 지급!", me = summary(p) }
	end)
	Registry.on("district.go", function(p: Player, d: any)
		-- quick travel to the district street (and to a building's entrance)
		local rec = if type(d.buildingId) == "string" then Registry.get(d.buildingId) else nil
		local cf
		if rec then
			cf = rec.cf * CFrame.new(0, 3.2, -6) * CFrame.Angles(0, math.pi, 0)
		else
			local origin = Config.DISTRICT_ORIGIN
			local o = workspace:GetAttribute("GwB_Origin")
			if typeof(o) == "CFrame" then
				origin = o
			end
			cf = origin * CFrame.new(-60, 3.2, 0)
		end
		Registry.teleport(p, cf)
		return { ok = true }
	end)
	-- homes are built per storey (Builder.buildUnits): show the owner / sale sign as soon as they exist
	Builder.onUnitsBuilt = function(_rec: any, fl: any)
		for _, u in fl.units do
			present(u)
		end
	end
	Builder.decorHook = function(u: any, into: Instance): boolean
		local o = Housing.ownerOf(u.id)
		if not o then
			return false
		end
		local D = services.Decor
		if D and D.buildLayout then
			D.buildLayout(u, into, records[o])
			return true
		end
		return false
	end
end

function Housing.start()
	Players.PlayerAdded:Connect(function(p)
		load(p)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		release(p)
		records[p] = nil
		dirty[p] = nil
		tours[p] = nil
		for _, g in guests do
			g[p] = nil
		end
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

return Housing
