-- GwangalliGameplay/Garage: 광안 오토 정비소 & 중고차 (owner: garage; docs/GARAGE.md, data + pure rules in
-- ReplicatedStorage.GwangalliGarageShared = GS). Feature module: init(ctx) / onLoaded / onCharacter / onLeave.
--
--   * OWNERSHIP: d.cars = { {id, kind, color, plate, cond, dirt, bought, grade, t, studs, loan?, rental?,
--     towed?}, ... } (GS.sanitizeCars). Max GS.MAX_CARS owned cars + one rental. Profiles.sanitize keeps
--     only the keys it knows, so the list is also kept in this module's own DataStore (GS.STORE, key
--     "u_<UserId>", written with UpdateAsync on every purchase / sale / rental and on autosave / leave,
--     never written when the read failed or the profile itself is memory-only). If Profiles one day keeps
--     raw.cars, the profile copy is used and the store stays a mirror.
--   * PURCHASE (server authoritative, at the showroom only): price GS.price(kind, grade) paid from the BANK
--     (cash fallback) through ctx.spend (= G.ledger); 할부 = the down payment now and equal daily charges
--     on the player's own day counter (d.lifeDay, the same clock as rent / 주택담보대출), every charge a
--     normal ledger entry + a "loan" bill (G.addBill); missed charges are retried daily, GS.LOAN.missLimit
--     misses repossess the car. Plates "부산12가 3456" are generated here (unique per player).
--   * SELL back GS.SELL_RATE of what was paid (remaining 할부 deducted). RENT: a 큐비 for one in-game day.
--   * 시승: a 60 s test drive (any kind, spawned in front of the garage through the vehicles API with the
--     player in the driver's seat; the 시승 loop markers are GarageRoutePoint parts); at the end the
--     player is put back in front of the showroom and the car disappears.
--   * CALL: the 차 부르기 sheet lists d.cars; "call" spawns the chosen car (colour + plate) through
--     ServerStorage.GwangalliVehiclesAPI "spawnOwned" (GwangalliVehicles/Spawn).
--   * CONDITION (0..100 per car, saved): hard hits (DriveCollider.Touched with the relative speed, and the
--     replicated velocity dropping by more than GS.COND.hitSpeed between two 10 Hz samples, because map
--     parts are CanTouch = false), 1 s debounce per car; -1 per GS.COND.wearStuds driven; dirt +1 per
--     GS.COND.dirtStuds. Written to the model (DriveCondition / DriveDirt): the controller reads the
--     condition (VS.enginePower: stutter < 60, -40 % top speed < 30, dead at 0), clients draw the gauge,
--     smoke and dirt. A dead car can be towed (GS.TOW.fee) to the 정비소.
--   * REPAIR / WASH at the 정비소: "repair" (car in the service-bay zone, or remotely on the lift car) and
--     "wash" (car under the wash gantry); clients play the choreography (GarageEvent), the server applies
--     the result after GS.REPAIR.seconds / GS.WASH.seconds.
--
-- REMOTES (ReplicatedStorage.GwangalliRemotes): GarageRequest (RemoteFunction) (op, payload) -> result
-- {ok, code, message, ...}; GarageEvent (RemoteEvent) server -> client (see GS header).
-- SERVER API: ServerStorage.GwangalliGarageAPI (BindableFunction) Invoke(op, player, ...):
--   "cars" (player) -> views; "give" (player, kind, grade?, colorId?) -> view (tests / rewards);
--   "setCondition" (player, id, cond) -> ok (tests); "status" (player) -> table

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local Garage = {}

local ctx: any = nil
local G: any = nil
local Profiles: any = nil
local Util: any = nil
local GS: any = nil

local requestFn: RemoteFunction? = nil
local eventRe: RemoteEvent? = nil
local store: any = nil
local storeEnabled = false
local rng = Random.new()

type Track = {
	id: string,
	model: Model,
	base: BasePart,
	lastPos: Vector3,
	lastVel: Vector3,
	peak: number,
	lastHit: number,
	wear: number,
	conns: { RBXScriptConnection },
	zone: string?,
}
type State = {
	loaded: boolean,
	canSave: boolean,
	dirty: boolean,
	busy: boolean,
	track: Track?,
	test: { model: Model?, kind: string, untilT: number, startedAt: number, leftAt: number? }?,
	lastTest: number,
	lastSaved: number,
	working: boolean, -- repair / wash choreography running
}
local states: { [Player]: State } = {}

local function S(player: Player): State
	local s = states[player]
	if not s then
		s = { loaded = false, canSave = false, dirty = false, busy = false, track = nil, test = nil, lastTest = -math.huge, lastSaved = 0, working = false }
		states[player] = s
	end
	return s
end

local function won(n: number): string
	return GS.formatWon(n)
end

local function res(ok: boolean, code: string, message: string?, extra: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = { ok = ok, code = code, message = message or "" }
	if extra then
		for k, v in extra do
			out[k] = v
		end
	end
	return out
end

local function fire(player: Player, payload: { [string]: any })
	if eventRe and player.Parent == Players then
		(eventRe :: RemoteEvent):FireClient(player, payload)
	end
end

-- Everyone within `radius` studs of `pos` (choreography visible to bystanders).
local function fireNear(pos: Vector3, radius: number, payload: { [string]: any })
	if not eventRe then
		return
	end
	for _, p in Players:GetPlayers() do
		local r = Util.rootPosition(p)
		if r and (r - pos).Magnitude <= radius then
			(eventRe :: RemoteEvent):FireClient(p, payload)
		end
	end
end

local function now(): number
	return os.time()
end

local function carsOf(player: Player): { any }?
	local d = Profiles.get(player)
	if not d or type(d.cars) ~= "table" then
		return nil
	end
	return d.cars
end

local function views(player: Player): { any }
	local out = {}
	local t = now()
	for _, c in carsOf(player) or {} do
		local v = GS.carView(c, t)
		local tr = S(player).track
		v.out = tr ~= nil and tr.id == c.id and tr.model.Parent ~= nil
		table.insert(out, v)
	end
	return out
end

local function pushCars(player: Player)
	fire(player, { kind = "cars", cars = views(player), max = GS.MAX_CARS })
end

---------------------------------------------------------------------------------------------------
-- Persistence (own DataStore; see the header)
---------------------------------------------------------------------------------------------------
local function keyOf(player: Player): string
	return GS.STORE_KEY .. tostring(player.UserId)
end

local function saveNow(player: Player): boolean
	local s = states[player]
	local cars = carsOf(player)
	if not s or not s.canSave or not cars or not storeEnabled or not store then
		if s then
			s.dirty = false
		end
		return false
	end
	if not Profiles.persistent(player) then
		s.dirty = false
		return false
	end
	local snapshot = GS.sanitizeCars(cars)
	s.dirty = false
	local ok, err = pcall(function()
		store:UpdateAsync(keyOf(player), function(_old: any)
			return { v = GS.VERSION, cars = snapshot, t = os.time() }
		end)
	end)
	if not ok then
		s.dirty = true
		warn("[Garage] save failed for " .. player.Name .. ": " .. tostring(err))
		return false
	end
	s.lastSaved = os.clock()
	return true
end

local function markDirty(player: Player, soon: boolean?)
	local s = S(player)
	s.dirty = true
	if soon then
		task.spawn(saveNow, player)
		pcall(Profiles.saveSoon, player, 2)
	end
end

local function loadCars(player: Player): ({ any }, boolean, string?)
	if not storeEnabled or not store then
		return {}, false, nil
	end
	for attempt = 1, 3 do
		local ok, data = pcall(function()
			return store:GetAsync(keyOf(player))
		end)
		if ok then
			local raw = if type(data) == "table" then data.cars else nil
			return GS.sanitizeCars(raw), true, nil
		end
		local e = string.lower(tostring(data))
		if string.find(e, "studio", 1, true) or string.find(e, "publish", 1, true) or string.find(e, "403", 1, true) or (string.find(e, "api", 1, true) and string.find(e, "access", 1, true)) then
			storeEnabled = false
			return {}, false, nil
		end
		warn(string.format("[Garage] load %s failed (try %d): %s", player.Name, attempt, tostring(data)))
		task.wait(2 ^ attempt)
		if player.Parent ~= Players then
			break
		end
	end
	return {}, false, "차 정보를 불러오지 못했어요. 이번 접속에서 산 차는 저장되지 않을 수 있어요."
end

---------------------------------------------------------------------------------------------------
-- World (venue parts placed by build/venues/garage.luau)
---------------------------------------------------------------------------------------------------
local function tagged(tag: string): { Instance }
	return CollectionService:GetTagged(tag)
end

local function firstTagged(tag: string, attr: string?, value: any?): Instance?
	for _, inst in tagged(tag) do
		if inst:IsDescendantOf(workspace) and (attr == nil or inst:GetAttribute(attr) == value) then
			return inst
		end
	end
	return nil
end

local function shopPos(): Vector3?
	local shop = firstTagged(GS.Tags.Shop)
	if shop then
		if shop:IsA("Model") then
			return shop:GetPivot().Position
		elseif shop:IsA("BasePart") then
			return shop.Position
		end
	end
	local dest = ctx.dest and ctx.dest(GS.PLACE)
	return dest and dest.Position or nil
end

-- Is the player at the 정비소 (showroom / bay / desk)? Purchases and repairs need it.
local function atGarage(player: Player, radius: number?): boolean
	local p = shopPos()
	local r = Util.rootPosition(player)
	if not p or not r then
		return false
	end
	return (Vector3.new(r.X, 0, r.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude <= (radius or 150)
end

local function inPart(part: BasePart, pos: Vector3, pad: number?): boolean
	local l = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2 + Vector3.one * (pad or 0)
	return math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y + 6 and math.abs(l.Z) <= h.Z
end

local function zoneAt(pos: Vector3): (string?, BasePart?)
	for _, z in tagged(GS.Tags.Zone) do
		if z:IsA("BasePart") and z:IsDescendantOf(workspace) and inPart(z, pos) then
			return z:GetAttribute(GS.Attr.ZoneKind), z
		end
	end
	return nil, nil
end

-- Ground frame of a marker part (its bottom centre, LookVector = heading).
local function groundFrame(part: BasePart): CFrame
	local cf = part.CFrame
	local p = cf.Position - Vector3.new(0, part.Size.Y / 2, 0)
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.zAxis
	end
	return CFrame.lookAt(p, p + look.Unit)
end

---------------------------------------------------------------------------------------------------
-- Vehicles API
---------------------------------------------------------------------------------------------------
local vapiFn: BindableFunction? = nil
local function vapi(op: string, ...: any): ...any
	if not (vapiFn and vapiFn.Parent) then
		local f = ServerStorage:FindFirstChild(GS.VEHICLES_API) or ServerStorage:WaitForChild(GS.VEHICLES_API, 10)
		vapiFn = if f and f:IsA("BindableFunction") then f else nil
	end
	local f = vapiFn
	if not f then
		return nil
	end
	local out = table.pack(pcall(f.Invoke, f, op, ...))
	if not out[1] then
		warn("[Garage] vehicles API " .. op .. " failed: " .. tostring(out[2]))
		return nil
	end
	return table.unpack(out, 2, out.n)
end

---------------------------------------------------------------------------------------------------
-- Condition tracking of the spawned owned car
---------------------------------------------------------------------------------------------------
local function setModelCond(model: Model, car: any)
	if model.Parent then
		model:SetAttribute(GS.Attr.Condition, car.cond)
		model:SetAttribute(GS.Attr.Dirt, math.floor(car.dirt * 50 + 0.5) / 50)
	end
end

local function untrack(player: Player)
	local s = states[player]
	local tr = s and s.track
	if not tr then
		return
	end
	s.track = nil
	for _, c in tr.conns do
		c:Disconnect()
	end
	if tr.zone then
		fire(player, { kind = "zone", zone = nil })
	end
	pushCars(player)
end

local function damage(player: Player, tr: Track, speed: number, why: string)
	local t = os.clock()
	if t - tr.lastHit < GS.COND.hitDebounce then
		return
	end
	local dmg = GS.hitDamage(speed)
	if dmg <= 0 then
		return
	end
	tr.lastHit = t
	local car = GS.findCar(carsOf(player) or {}, tr.id)
	if not car then
		return
	end
	local before = car.cond
	car.cond = GS.clampCond(car.cond - dmg)
	if car.cond == before then
		return
	end
	setModelCond(tr.model, car)
	markDirty(player)
	fire(player, { kind = "hit", id = car.id, cond = car.cond, dmg = before - car.cond, why = why })
	if car.cond <= 0 and before > 0 then
		ctx.notify(player, "warn", "🛑 엔진이 멈췄어요", "차가 크게 부서졌어요. 차 부르기에서 '견인'을 누르면 정비소로 옮겨 드려요 (" .. won(GS.TOW.fee) .. ")")
		fire(player, { kind = "dead", id = car.id })
	elseif GS.band(car.cond) ~= GS.band(before) then
		local b = GS.bandInfo(car.cond)
		ctx.notify(player, "warn", b.icon .. " 차 상태: " .. b.label, string.format("상태 %d%% · 정비소에서 정비하면 100%%가 돼요", car.cond))
	end
end

local function track(player: Player, car: any, model: Model)
	untrack(player)
	local base = model:FindFirstChild("DriveBase") :: BasePart?
	if not (base and base:IsA("BasePart")) then
		return
	end
	local tr: Track = {
		id = car.id,
		model = model,
		base = base,
		lastPos = base.Position,
		lastVel = Vector3.zero,
		peak = 0,
		lastHit = -math.huge,
		wear = 0,
		conns = {},
		zone = nil,
	}
	S(player).track = tr
	setModelCond(model, car)
	-- hard hits against other cars / players / anything that can touch (the map is CanTouch = false: the
	-- velocity check in step() catches walls)
	local collider = model:FindFirstChild("DriveCollider")
	if collider and collider:IsA("BasePart") then
		collider.CanTouch = true
		table.insert(tr.conns, collider.Touched:Connect(function(other: BasePart)
			if other:IsDescendantOf(model) then
				return
			end
			local mine = base.AssemblyLinearVelocity
			local theirs = if other:IsA("BasePart") then other.AssemblyLinearVelocity else Vector3.zero
			local rel = math.max((mine - theirs).Magnitude, tr.peak * 0.8)
			if rel >= GS.COND.hitSpeed then
				damage(player, tr, rel, "touch")
			end
		end))
	end
	table.insert(tr.conns, model.AncestryChanged:Connect(function()
		if model.Parent == nil then
			local s = states[player]
			if s and s.track == tr then
				untrack(player)
			end
		end
	end))
	pushCars(player)
end

-- 10 Hz: distance, dirt, wear, impacts, zones (every tracked car).
local function step(dt: number)
	for player, s in states do
		local tr = s.track
		if not tr or not tr.model.Parent then
			continue
		end
		local car = GS.findCar(carsOf(player) or {}, tr.id)
		if not car then
			continue
		end
		local base = tr.base
		local pos = base.Position
		local vel = base.AssemblyLinearVelocity
		local driver = tr.model:GetAttribute("DriveDriver")
		if driver ~= nil and driver ~= 0 then
			local flat = Vector3.new(pos.X - tr.lastPos.X, 0, pos.Z - tr.lastPos.Z).Magnitude
			if flat < 60 * math.max(dt, 0.1) * 10 then
				car.studs += flat
				tr.wear += flat
				local oldDirt = car.dirt
				car.dirt = math.min(1, car.dirt + flat / GS.COND.dirtStuds)
				local changed = math.floor(car.dirt * 50) ~= math.floor(oldDirt * 50)
				while tr.wear >= GS.COND.wearStuds do
					tr.wear -= GS.COND.wearStuds
					if car.cond > 0 then
						local before = car.cond
						car.cond = GS.clampCond(car.cond - 1)
						changed = true
						if car.cond <= 0 and before > 0 then
							ctx.notify(player, "warn", "🛑 엔진이 멈췄어요", "너무 오래 정비를 안 했어요. '견인'으로 정비소에 보내 주세요")
							fire(player, { kind = "dead", id = car.id })
						end
					end
				end
				if changed then
					setModelCond(tr.model, car)
					s.dirty = true
				end
			end
			-- impact: the replicated velocity dropped hard between two samples
			local drop = tr.lastVel.Magnitude - vel.Magnitude
			local dv = (tr.lastVel - vel).Magnitude
			if drop > 4 and dv >= GS.COND.hitSpeed then
				damage(player, tr, dv, "impact")
			end
		end
		tr.peak = math.max(vel.Magnitude, tr.peak * 0.7)
		tr.lastPos = pos
		tr.lastVel = vel
		-- zones of the 정비소 (service bay / wash gantry)
		local z = zoneAt(pos)
		if z ~= tr.zone then
			tr.zone = z
			local quote: { [string]: any } = { repair = GS.repairCost(car.kind, car.cond), wash = GS.WASH.fee, cond = car.cond, dirt = car.dirt }
			fire(player, { kind = "zone", zone = z, id = car.id, quote = quote })
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Money helpers
---------------------------------------------------------------------------------------------------
-- Bank first (check card), cash when the bank is short. Returns ok, account.
local function pay(player: Player, amount: number, label: string): (boolean, string?)
	local d = Profiles.get(player)
	if not d then
		return false, nil
	end
	if amount <= 0 then
		return true, "bank"
	end
	local before = { cash = d.cash, bank = d.bank }
	local ok = ctx.spend(player, amount, label, true, "bank")
	if not ok then
		return false, nil
	end
	local account = if d.bank < before.bank then "bank" else "cash"
	return true, account
end

local function uniquePlate(cars: { any }): string
	for _ = 1, 20 do
		local p = GS.plate(function()
			return rng:NextNumber()
		end)
		local dup = false
		for _, c in cars do
			if c.plate == p then
				dup = true
			end
		end
		if not dup then
			return p
		end
	end
	return GS.plate(function()
		return rng:NextNumber()
	end)
end

local function newId(cars: { any }): string
	for _ = 1, 20 do
		local id = GS.newId(function()
			return rng:NextNumber()
		end)
		if not GS.findCar(cars, id) then
			return id
		end
	end
	return "c" .. tostring(os.time() % 1000000)
end

local function validColor(id: any): string
	for _, c in GS.COLORS do
		if c.id == id then
			return id
		end
	end
	return GS.DEFAULT_COLOR
end

local function addBill(player: Player, label: string, amount: number, paid: boolean)
	local d = Profiles.get(player)
	if d and G.addBill then
		pcall(G.addBill, d, "loan", label, amount, paid, os.time())
		ctx.changed(player, "housing")
	end
end

---------------------------------------------------------------------------------------------------
-- Ops
---------------------------------------------------------------------------------------------------
local function despawnCarOf(player: Player, id: string, reason: string?): boolean
	local s = S(player)
	local tr = s.track
	if tr and tr.id == id and tr.model.Parent then
		local occ = vapi("occupants", tr.model) or {}
		for _, p in occ do
			if p ~= player then
				return false
			end
		end
		vapi("despawn", player, reason)
		untrack(player)
	end
	return true
end

local function makeCar(player: Player, kind: string, grade: string, colorId: string, paid: number): any
	local cars = carsOf(player) or {}
	local used = grade == "used"
	return {
		id = newId(cars),
		kind = kind,
		color = validColor(colorId),
		plate = uniquePlate(cars),
		cond = if used then rng:NextInteger(GS.USED_COND[1], GS.USED_COND[2]) else 100,
		dirt = if used then 0.2 else 0,
		bought = paid,
		grade = if used then "used" else "new",
		t = now(),
		studs = 0,
	}
end

local function opBuy(player: Player, p: any): { [string]: any }
	local d = Profiles.get(player)
	local cars = carsOf(player)
	if not d or not cars then
		return res(false, "loading", "잠시 후 다시 시도해 주세요")
	end
	local kind = p.kind
	local grade = if p.grade == "used" then "used" else "new"
	local price = type(kind) == "string" and GS.price(kind, grade)
	if not price then
		return res(false, "bad", "없는 차종이에요")
	end
	if not atGarage(player, 160) then
		return res(false, "far", "정비소 쇼룸에서만 살 수 있어요")
	end
	if GS.owned(cars) >= GS.MAX_CARS then
		return res(false, "max", string.format("차는 최대 %d대까지 가질 수 있어요. 먼저 한 대를 팔아 주세요", GS.MAX_CARS))
	end
	local colorId = validColor(p.color)
	local info = GS.CATALOG[kind]
	local label = string.format("%s %s (%s)", info.full or info.label, GS.GRADES[grade], GS.colorEntry(colorId).name)
	local loan = p.loan == true and GS.canLoan(price)
	if loan then
		for _, c in cars do
			if c.loan and c.loan.missed > 0 then
				return res(false, "loanMissed", "밀린 할부가 있어서 새 할부를 할 수 없어요")
			end
		end
		local q = GS.loanQuote(price)
		local ok, account = pay(player, q.down, "자동차 계약금 · " .. label)
		if not ok then
			return res(false, "insufficient", string.format("계약금 %s이 부족해요 (통장 %s · 현금 %s)", won(q.down), won(d.bank), won(d.cash)))
		end
		local car = makeCar(player, kind, grade, colorId, price)
		car.loan = { remaining = q.total, daily = q.daily, lastDay = d.lifeDay or 1, missed = 0, total = q.total }
		table.insert(cars, car)
		addBill(player, string.format("자동차 할부 계약 · %s (계약금 %s)", label, won(q.down)), q.down, true)
		markDirty(player, true)
		ctx.notify(player, "money", "🚗 구매 완료 · " .. info.label, string.format("계약금 %s 결제 · 할부 하루 %s × %d일 · 번호판 %s", won(q.down), won(q.daily), q.days, car.plate))
		pushCars(player)
		return res(true, "ok", "구매 완료", { car = GS.carView(car, now()), receipt = { label = label, plate = car.plate, paid = q.down, account = account, loan = q, price = price, grade = grade, kind = kind, color = colorId } })
	end
	local ok, account = pay(player, price, "자동차 구매 · " .. label)
	if not ok then
		return res(false, "insufficient", string.format("잔액이 부족해요 (%s 필요 · 통장 %s · 현금 %s)%s", won(price), won(d.bank), won(d.cash), if GS.canLoan(price) then " · 할부를 이용해 보세요" else ""))
	end
	local car = makeCar(player, kind, grade, colorId, price)
	table.insert(cars, car)
	markDirty(player, true)
	ctx.notify(player, "money", "🚗 구매 완료 · " .. info.label, string.format("%s %s 결제 · 번호판 %s", won(price), if account == "bank" then "(통장)" else "(현금)", car.plate))
	ctx.addStats(player, { happiness = if kind == "luxury" then 15 else 6 }, nil, true)
	pushCars(player)
	return res(true, "ok", "구매 완료", { car = GS.carView(car, now()), receipt = { label = label, plate = car.plate, paid = price, account = account, price = price, grade = grade, kind = kind, color = colorId } })
end

local function opSell(player: Player, p: any): { [string]: any }
	local cars = carsOf(player)
	local car, idx = GS.findCar(cars or {}, p.id)
	if not cars or not car or not idx then
		return res(false, "bad", "없는 차예요")
	end
	if car.rental then
		return res(false, "rental", "렌트한 차는 팔 수 없어요")
	end
	if not atGarage(player, 160) then
		return res(false, "far", "정비소에서만 팔 수 있어요")
	end
	local value = GS.sellValue(car)
	local remaining = if car.loan then car.loan.remaining else 0
	local payout = value - remaining
	if payout < 0 then
		return res(false, "loan", string.format("남은 할부(%s)가 매입가(%s)보다 많아서 팔 수 없어요", won(remaining), won(value)))
	end
	if not despawnCarOf(player, car.id, nil) then
		return res(false, "occupied", "지금 그 차에 누가 타고 있어요")
	end
	table.remove(cars, idx)
	local label = string.format("중고차 매각 · %s %s", GS.carLabel(car), car.plate)
	if payout > 0 then
		ctx.ledger(player, "bank", payout, label, true)
	end
	if remaining > 0 then
		addBill(player, "자동차 할부 정산 (매각) · " .. car.plate, remaining, true)
	end
	markDirty(player, true)
	ctx.notify(player, "money", "💸 차를 팔았어요", string.format("%s · 매입가 %s%s → 통장 +%s", GS.carLabel(car), won(value), if remaining > 0 then string.format(" - 남은 할부 %s", won(remaining)) else "", won(payout)))
	pushCars(player)
	return res(true, "ok", "판매 완료", { payout = payout, value = value })
end

local function opCall(player: Player, p: any): { [string]: any }
	local cars = carsOf(player)
	local car = GS.findCar(cars or {}, p.id)
	if not car then
		return res(false, "bad", "없는 차예요")
	end
	local s = S(player)
	if s.test then
		return res(false, "test", "시승 중에는 차를 부를 수 없어요")
	end
	if s.working then
		return res(false, "busy", "정비 · 세차가 끝난 뒤 불러 주세요")
	end
	local okC, why = GS.callable(car, now())
	if not okC then
		return res(false, "dead", why)
	end
	local info = GS.CATALOG[car.kind]
	local ok, msg, model = vapi("spawnOwned", player, {
		id = car.id,
		kind = car.kind,
		color = GS.color3(car.color),
		colorId = car.color,
		plate = car.plate,
		cond = car.cond,
		dirt = car.dirt,
		label = if car.rental then info.label .. " (렌트)" else info.label,
		rental = car.rental ~= nil,
	}, { near = if p.near and typeof(p.near) == "Vector3" then p.near else nil })
	if not ok or not model then
		return res(false, "spawn", if type(msg) == "string" then msg else "차를 부르지 못했어요")
	end
	car.towed = nil
	track(player, car, model)
	local label, meters = string.match(msg, "^(.-)|(%d+)$")
	return res(true, "ok", "", { label = label or info.label, meters = tonumber(meters) or 0, car = model, plate = car.plate, id = car.id })
end

local function opRent(player: Player): { [string]: any }
	local d = Profiles.get(player)
	local cars = carsOf(player)
	if not d or not cars then
		return res(false, "loading", "잠시 후 다시 시도해 주세요")
	end
	for _, c in cars do
		if c.rental then
			return res(false, "rented", "이미 렌트한 차가 있어요")
		end
	end
	if not atGarage(player, 160) then
		return res(false, "far", "렌트는 정비소에서 할 수 있어요")
	end
	local R = GS.RENTAL
	local ok = pay(player, R.fee, R.label)
	if not ok then
		return res(false, "insufficient", string.format("렌트비 %s이 부족해요", won(R.fee)))
	end
	local colorIds = { "white", "mint", "beige", "silver" }
	local car = {
		id = newId(cars),
		kind = R.kind,
		color = colorIds[rng:NextInteger(1, #colorIds)],
		plate = uniquePlate(cars),
		cond = 100,
		dirt = 0,
		bought = 0,
		grade = "new",
		t = now(),
		studs = 0,
		rental = { ["until"] = now() + R.seconds },
	}
	-- the 렌트 plate is a 허 plate, like real Korean rental cars
	car.plate = string.gsub(car.plate, "^(부산%d%d)[^%s]+", "%1허")
	table.insert(cars, car)
	markDirty(player, true)
	ctx.notify(player, "money", "🔑 렌트 완료", string.format("%s · %s 결제 · 게임 시간 하루(%d분) 동안 탈 수 있어요", GS.CATALOG[R.kind].label, won(R.fee), math.floor(R.seconds / 60)))
	pushCars(player)
	-- bring it round to the front of the garage
	local spawnPart = firstTagged(GS.Tags.Spawn) :: BasePart?
	local callRes = opCall(player, { id = car.id, near = if spawnPart then spawnPart.Position else nil })
	return res(true, "ok", "렌트 완료", { car = GS.carView(car, now()), called = callRes.ok == true })
end

-- The 시승 loop: "x,y,z|x,y,z|..." on the GarageShop root (build/venues/garage.luau), else tagged parts.
local function routeInfo(): { Vector3 }
	local out = {}
	local shop = firstTagged(GS.Tags.Shop)
	local packed = shop and shop:GetAttribute("Route")
	if type(packed) == "string" then
		for item in string.gmatch(packed, "[^|]+") do
			local x, y, z = string.match(item, "^([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$")
			if x then
				table.insert(out, Vector3.new(tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number))
			end
		end
		return out
	end
	local pts = {}
	for _, p in tagged(GS.Tags.RoutePoint) do
		if p:IsA("BasePart") then
			table.insert(pts, { i = p:GetAttribute("Index") or 0, pos = p.Position })
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

local function endTest(player: Player, why: string)
	local s = states[player]
	local tst = s and s.test
	if not s or not tst then
		return
	end
	s.test = nil
	s.lastTest = os.clock()
	local model = tst.model
	if model and model.Parent then
		vapi("eject", model)
		task.wait(0.2)
		vapi("despawn", player, nil)
	end
	local ret = firstTagged(GS.Tags.Return) :: BasePart?
	if ret and player.Parent == Players then
		ctx.allowTeleport(player, 8)
		task.spawn(function()
			pcall(Util.teleportTo, player, ret, 2)
		end)
	end
	fire(player, { kind = "testdrive", stage = "end", carKind = tst.kind, why = why })
	if why == "time" then
		ctx.notify(player, "info", "🏁 시승 끝!", "마음에 드셨나요? 쇼룸에서 바로 계약할 수 있어요")
	end
end

local function opTestDrive(player: Player, p: any): { [string]: any }
	local kind = p.kind
	if type(kind) ~= "string" or not GS.CATALOG[kind] then
		return res(false, "bad", "없는 차종이에요")
	end
	local s = S(player)
	if s.test then
		return res(false, "test", "이미 시승 중이에요")
	end
	local cd = GS.TEST_DRIVE.cooldown - (os.clock() - s.lastTest)
	if cd > 0 then
		return res(false, "cooldown", string.format("%d초 뒤에 다시 시승할 수 있어요", math.ceil(cd)))
	end
	if not atGarage(player, 160) then
		return res(false, "far", "시승은 정비소 쇼룸에서 신청해요")
	end
	-- the called car (if any) goes home first
	local tr = s.track
	if tr and tr.model.Parent then
		if not despawnCarOf(player, tr.id, nil) then
			return res(false, "occupied", "내 차에 누가 타고 있어서 시승을 시작할 수 없어요")
		end
	end
	local spawnPart = firstTagged(GS.Tags.Spawn) :: BasePart?
	local info = GS.CATALOG[kind]
	local untilT = now() + GS.TEST_DRIVE.seconds
	local colorId = validColor(p.color)
	local ok, msg, model = vapi("spawnOwned", player, {
		id = "test",
		kind = kind,
		color = GS.color3(colorId),
		colorId = colorId,
		plate = "시승 " .. string.format("%04d", rng:NextInteger(1000, 9999)),
		cond = 100,
		dirt = 0,
		label = info.label .. " 시승차",
		testDrive = untilT,
	}, {
		near = if spawnPart then spawnPart.Position else nil,
		cframe = if spawnPart then groundFrame(spawnPart) else nil,
		radius = 200,
		force = true,
		seat = true,
	})
	if not ok or not model then
		return res(false, "spawn", if type(msg) == "string" then msg else "시승차를 준비하지 못했어요")
	end
	s.test = { model = model, kind = kind, untilT = os.clock() + GS.TEST_DRIVE.seconds, startedAt = os.clock(), leftAt = nil }
	ctx.allowTeleport(player, 6)
	fire(player, { kind = "testdrive", stage = "start", carKind = kind, seconds = GS.TEST_DRIVE.seconds, route = routeInfo(), car = model })
	return res(true, "ok", "시승 시작", { seconds = GS.TEST_DRIVE.seconds, car = model })
end

local function opTow(player: Player, p: any): { [string]: any }
	local cars = carsOf(player)
	local car = GS.findCar(cars or {}, p.id)
	if not car then
		return res(false, "bad", "없는 차예요")
	end
	if car.towed then
		return res(false, "towed", "이미 정비소에 있어요")
	end
	if car.cond > 0 then
		return res(false, "fine", "아직 달릴 수 있는 차예요 · 직접 정비소로 몰고 가세요")
	end
	local ok = pay(player, GS.TOW.fee, "견인비 · " .. car.plate)
	if not ok then
		return res(false, "insufficient", string.format("견인비 %s이 부족해요", won(GS.TOW.fee)))
	end
	despawnCarOf(player, car.id, nil)
	car.towed = true
	markDirty(player)
	pcall(ctx.setWaypoint, player, GS.PLACE)
	ctx.notify(player, "info", "🚛 견인 완료", string.format("%s를 광안 오토 정비소로 옮겼어요. 지도에 표시했어요 · 정비 받으면 다시 탈 수 있어요", car.plate))
	pushCars(player)
	return res(true, "ok", "견인 완료")
end

local function liftCarModel(): Model?
	local m = firstTagged(GS.Tags.LiftCar)
	return if m and m:IsA("Model") then m else nil
end

local function opRepair(player: Player, p: any): { [string]: any }
	local cars = carsOf(player)
	local s = S(player)
	if not cars then
		return res(false, "loading", "잠시 후 다시 시도해 주세요")
	end
	if s.working then
		return res(false, "busy", "작업 중이에요")
	end
	if not atGarage(player, 170) then
		return res(false, "far", "정비소에서 정비 받을 수 있어요")
	end
	local car = if p.id then GS.findCar(cars, p.id) else nil
	local tr = s.track
	if not car and tr and tr.model.Parent then
		car = GS.findCar(cars, tr.id)
	end
	if not car then
		-- the worst car
		for _, c in cars do
			if not car or c.cond < car.cond then
				car = c
			end
		end
	end
	if not car then
		return res(false, "none", "정비할 차가 없어요")
	end
	local cost = GS.repairCost(car.kind, car.cond)
	if cost <= 0 then
		return res(false, "fine", "정비가 필요 없는 상태예요 (100%)")
	end
	local ok = pay(player, cost, "정비비 · " .. car.plate)
	if not ok then
		return res(false, "insufficient", string.format("정비비 %s이 부족해요", won(cost)))
	end
	s.working = true
	-- the car itself when it stands in the service bay, else the lift's own car stands in for it
	local model: Model? = nil
	if tr and tr.id == car.id and tr.model.Parent then
		local z = zoneAt(tr.base.Position)
		if z == "service" then
			model = tr.model
			vapi("eject", model)
			vapi("park", model)
			model:SetAttribute(GS.Attr.Repairing, true)
		end
	end
	local lift = firstTagged(GS.Tags.Lift)
	local stage = model or liftCarModel()
	local pos = if stage then stage:GetPivot().Position else (shopPos() or Vector3.zero)
	local seconds = GS.REPAIR.seconds
	fireNear(pos, 260, { kind = "repair", stage = "start", car = stage, lift = lift, onLift = model == nil, seconds = seconds, owner = player.UserId })
	task.delay(seconds, function()
		s.working = false
		local c2 = GS.findCar(carsOf(player) or {}, car.id)
		if c2 then
			c2.cond = GS.COND.max
			c2.towed = nil
			local t2 = s.track
			if t2 and t2.id == c2.id and t2.model.Parent then
				setModelCond(t2.model, c2)
				t2.model:SetAttribute(GS.Attr.Repairing, nil)
			end
			markDirty(player, true)
		end
		fireNear(pos, 260, { kind = "repair", stage = "done", car = stage, lift = lift, owner = player.UserId })
		if player.Parent == Players then
			ctx.notify(player, "success", "🔧 정비 완료!", string.format("%s 상태 100%% · 정비비 %s", car.plate, won(cost)))
			pushCars(player)
		end
	end)
	return res(true, "ok", "정비 시작", { seconds = seconds, cost = cost, id = car.id, onLift = model == nil })
end

local function opWash(player: Player, _p: any): { [string]: any }
	local s = S(player)
	local tr = s.track
	if s.working then
		return res(false, "busy", "작업 중이에요")
	end
	if not tr or not tr.model.Parent then
		return res(false, "nocar", "세차할 내 차를 세차장 안에 세워 주세요")
	end
	local z, zonePart = zoneAt(tr.base.Position)
	if z ~= "wash" then
		return res(false, "zone", "차를 세차장 안(초록 선)에 세워 주세요")
	end
	local car = GS.findCar(carsOf(player) or {}, tr.id)
	if not car then
		return res(false, "bad", "없는 차예요")
	end
	local ok = pay(player, GS.WASH.fee, "자동 세차 · " .. car.plate)
	if not ok then
		return res(false, "insufficient", string.format("세차비 %s이 부족해요", won(GS.WASH.fee)))
	end
	s.working = true
	local model = tr.model
	vapi("park", model)
	model:SetAttribute(GS.Attr.Washing, true)
	local gantry = firstTagged(GS.Tags.Gantry)
	local seconds = GS.WASH.seconds
	fireNear(model:GetPivot().Position, 260, { kind = "wash", stage = "start", car = model, gantry = gantry, zone = zonePart, seconds = seconds, owner = player.UserId })
	task.delay(seconds, function()
		s.working = false
		local c2 = GS.findCar(carsOf(player) or {}, car.id)
		if c2 then
			c2.dirt = 0
			markDirty(player)
		end
		if model.Parent then
			model:SetAttribute(GS.Attr.Washing, nil)
			model:SetAttribute(GS.Attr.ShineUntil, os.time() + 600)
			if c2 then
				setModelCond(model, c2)
			end
		end
		fireNear(model:GetPivot().Position, 260, { kind = "wash", stage = "done", car = model, gantry = gantry, owner = player.UserId })
		if player.Parent == Players then
			ctx.addStats(player, { happiness = GS.WASH.happiness }, nil, true)
			ctx.notify(player, "success", "✨ 세차 완료!", string.format("반짝반짝 · 행복 +%d · %s", GS.WASH.happiness, won(GS.WASH.fee)))
			pushCars(player)
		end
	end)
	return res(true, "ok", "세차 시작", { seconds = seconds })
end

local function opQuote(player: Player, p: any): { [string]: any }
	local d = Profiles.get(player)
	local kind = p.kind
	local grade = if p.grade == "used" then "used" else "new"
	local price = type(kind) == "string" and GS.price(kind, grade)
	if not d or not price then
		return res(false, "bad", "없는 차종이에요")
	end
	local q = if GS.canLoan(price) then GS.loanQuote(price) else nil
	return res(true, "ok", "", {
		price = price,
		loan = q,
		canLoan = q ~= nil,
		afford = d.bank >= price or d.cash >= price,
		affordDown = q ~= nil and (d.bank >= q.down or d.cash >= q.down),
		bank = d.bank,
		cash = d.cash,
	})
end

local function opStatus(player: Player): { [string]: any }
	local d = Profiles.get(player)
	local s = S(player)
	local tr = s.track
	return res(true, "ok", "", {
		cars = views(player),
		max = GS.MAX_CARS,
		owned = GS.owned(carsOf(player) or {}),
		bank = d and d.bank or 0,
		cash = d and d.cash or 0,
		atGarage = atGarage(player, 170),
		zone = tr and tr.zone or nil,
		outId = if tr and tr.model.Parent then tr.id else nil,
		testCooldown = math.max(0, GS.TEST_DRIVE.cooldown - (os.clock() - s.lastTest)),
		testing = s.test ~= nil,
		loaded = s.loaded,
		free = player:GetAttribute("GwangalliAdmin") == true or workspace:GetAttribute("GwangalliDriveUnlockAll") == true,
	})
end

local OPS: { [string]: (Player, any) -> { [string]: any } } = {
	status = function(player)
		return opStatus(player)
	end,
	list = function(player)
		return res(true, "ok", "", { cars = views(player), max = GS.MAX_CARS })
	end,
	quote = opQuote,
	buy = opBuy,
	sell = opSell,
	rent = function(player)
		return opRent(player)
	end,
	testdrive = opTestDrive,
	call = function(player, p)
		return opCall(player, { id = p.id })
	end,
	dismiss = function(player)
		local tr = S(player).track
		local ok = vapi("despawn", player, nil)
		if tr then
			untrack(player)
		end
		return res(ok == true, if ok then "ok" else "none", if ok then "차를 돌려보냈어요" else "부른 차가 없어요")
	end,
	tow = opTow,
	repair = opRepair,
	wash = opWash,
	waypoint = function(player)
		pcall(ctx.setWaypoint, player, GS.PLACE)
		ctx.notify(player, "travel", "🧭 광안 오토 정비소", "지도에 표시했어요 · 쇼룸에서 차를 사거나 하루 렌트를 할 수 있어요")
		return res(true, "ok", "")
	end,
	endtest = function(player)
		if S(player).test then
			task.spawn(endTest, player, "player")
			return res(true, "ok", "")
		end
		return res(false, "none", "")
	end,
}
local MUTATING = { buy = true, sell = true, rent = true, testdrive = true, call = true, tow = true, repair = true, wash = true, dismiss = true }
local COOLDOWN = { buy = 1, sell = 1, rent = 1, testdrive = 1.5, call = 1, tow = 1, repair = 1, wash = 1, dismiss = 0.5, quote = 0.15, status = 0.2, list = 0.2, waypoint = 0.5, endtest = 0.5 }

local function handle(player: Player, op: any, payload: any): { [string]: any }
	if type(op) ~= "string" or not OPS[op] then
		return res(false, "bad", "잘못된 요청이에요")
	end
	if payload ~= nil and type(payload) ~= "table" then
		return res(false, "bad", "잘못된 요청이에요")
	end
	if not Util.bucket(player, 6, 12) then
		return res(false, "rate", "잠시 후 다시 시도해 주세요")
	end
	if not Util.cooldown(player, "garage:" .. op, COOLDOWN[op] or 0.3) then
		return res(false, "rate", "잠시 후 다시 시도해 주세요")
	end
	local s = S(player)
	if not Profiles.get(player) or not s.loaded then
		return res(false, "loading", "프로필을 불러오는 중이에요")
	end
	if MUTATING[op] then
		if s.busy then
			return res(false, "busy", "처리 중이에요")
		end
		s.busy = true
	end
	local ok, out = pcall(OPS[op], player, payload or {})
	if MUTATING[op] then
		s.busy = false
	end
	if not ok then
		warn(string.format("[Garage] %s from %s failed: %s", op, player.Name, tostring(out)))
		return res(false, "error", "처리하지 못했어요")
	end
	return out
end

---------------------------------------------------------------------------------------------------
-- Daily: 할부 charges, rental expiry, test-drive timeout (1 Hz)
---------------------------------------------------------------------------------------------------
local function daily(player: Player)
	local d = Profiles.get(player)
	local cars = carsOf(player)
	local s = states[player]
	if not d or not cars or not s or not s.loaded then
		return
	end
	local t = now()
	local changed = false
	for i = #cars, 1, -1 do
		local c = cars[i]
		if c.rental and c.rental["until"] <= t then
			despawnCarOf(player, c.id, "렌트 기간이 끝나서 차를 반납했어요")
			local tr = s.track
			if tr and tr.id == c.id and tr.model.Parent then
				vapi("eject", tr.model)
				vapi("despawn", player, "렌트 기간이 끝나서 차를 반납했어요")
				untrack(player)
			end
			table.remove(cars, i)
			changed = true
			ctx.notify(player, "info", "🔑 렌트가 끝났어요", "정비소에서 내 차를 사면 계속 탈 수 있어요")
		elseif c.loan then
			local day = d.lifeDay or 1
			local due = math.min(day - (c.loan.lastDay or day), 3)
			while due > 0 and c.loan do
				due -= 1
				c.loan.lastDay += 1
				local amount = math.min(c.loan.daily, c.loan.remaining)
				local okPay = pay(player, amount, "자동차 할부 상환 · " .. c.plate)
				changed = true
				if okPay then
					c.loan.remaining -= amount
					c.loan.missed = 0
					addBill(player, "자동차 할부 상환 · " .. c.plate, amount, true)
					ctx.notify(player, "money", "자동이체 -" .. won(amount), string.format("자동차 할부 · 남은 금액 %s", won(c.loan.remaining)))
					if c.loan.remaining <= 0 then
						c.loan = nil
						ctx.notify(player, "success", "🎉 자동차 할부 완납!", c.plate .. " 이제 완전히 내 차예요")
						ctx.addStats(player, { happiness = 6 }, nil, true)
					end
				else
					c.loan.missed += 1
					addBill(player, "자동차 할부 미납 · " .. c.plate, amount, false)
					ctx.notify(player, "warn", "⚠️ 자동차 할부 미납", string.format("%s · %d번 밀리면 차를 가져가요 (%d/%d)", won(amount), GS.LOAN.missLimit, c.loan.missed, GS.LOAN.missLimit))
					if c.loan.missed >= GS.LOAN.missLimit then
						despawnCarOf(player, c.id, nil)
						table.remove(cars, i)
						ctx.notify(player, "warn", "🚫 차를 회수당했어요", string.format("할부가 %d번 밀려 %s를 가져갔어요", GS.LOAN.missLimit, c.plate))
						break
					end
				end
			end
		end
	end
	if changed then
		markDirty(player)
		pushCars(player)
	end
	-- test drive: time up, or the driver left the car for 5 s, or the car is gone
	local tst = s.test
	if tst then
		local model = tst.model
		local gone = not model or model.Parent == nil
		local driverId = model and model:GetAttribute("DriveDriver")
		if not gone and driverId ~= player.UserId then
			tst.leftAt = tst.leftAt or os.clock()
		else
			tst.leftAt = nil
		end
		if os.clock() >= tst.untilT then
			task.spawn(endTest, player, "time")
		elseif gone or (tst.leftAt and os.clock() - tst.leftAt > 5 and os.clock() - tst.startedAt > 4) then
			task.spawn(endTest, player, "left")
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Server API (tests / other modules)
---------------------------------------------------------------------------------------------------
local function bindApi()
	local f = ServerStorage:FindFirstChild(GS.API)
	if f and not f:IsA("BindableFunction") then
		f:Destroy()
		f = nil
	end
	if not f then
		f = Instance.new("BindableFunction")
		f.Name = GS.API
		f.Parent = ServerStorage
	end
	(f :: BindableFunction).OnInvoke = function(op: any, player: any, a: any, b: any, c: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return nil
		end
		if op == "cars" then
			return views(player)
		elseif op == "status" then
			return opStatus(player)
		elseif op == "give" then
			local cars = carsOf(player)
			if not cars or type(a) ~= "string" or not GS.CATALOG[a] or GS.owned(cars) >= GS.MAX_CARS then
				return nil
			end
			local car = makeCar(player, a, if b == "used" then "used" else "new", validColor(c), GS.price(a, b) or 0)
			table.insert(cars, car)
			markDirty(player, true)
			pushCars(player)
			return GS.carView(car, now())
		elseif op == "setCondition" then
			local car = GS.findCar(carsOf(player) or {}, a)
			if not car or type(b) ~= "number" then
				return false
			end
			car.cond = GS.clampCond(b)
			local tr = S(player).track
			if tr and tr.id == car.id and tr.model.Parent then
				setModelCond(tr.model, car)
			end
			pushCars(player)
			return true
		elseif op == "request" then
			return handle(player, a, b)
		end
		return nil
	end
end

---------------------------------------------------------------------------------------------------
-- Feature hooks
---------------------------------------------------------------------------------------------------
function Garage.init(c: any)
	ctx = c
	G = ctx.G
	Profiles = ctx.Profiles
	Util = ctx.Util
	local m = ReplicatedStorage:WaitForChild("GwangalliGarageShared", 20)
	assert(m and m:IsA("ModuleScript"), "GwangalliGarageShared missing")
	GS = require(m)

	local folder = ReplicatedStorage:FindFirstChild(G.RemotesFolder) or ReplicatedStorage:WaitForChild(G.RemotesFolder, 10)
	assert(folder, "GwangalliRemotes missing")
	local function remote(name: string, className: string): any
		local r = folder:FindFirstChild(name)
		if r and r.ClassName ~= className then
			r:Destroy()
			r = nil
		end
		if not r then
			r = Instance.new(className)
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	requestFn = remote(GS.Remotes.Request, "RemoteFunction")
	eventRe = remote(GS.Remotes.Event, "RemoteEvent");
	(requestFn :: RemoteFunction).OnServerInvoke = function(player: Player, op: any, payload: any)
		return handle(player, op, payload)
	end

	local okStore, st = pcall(function()
		return DataStoreService:GetDataStore(GS.STORE)
	end)
	if okStore and st then
		store = st
		storeEnabled = true
	else
		storeEnabled = false
	end

	bindApi()

	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 0.1 then
			local d = acc
			acc = 0
			local ok, err = pcall(step, d)
			if not ok then
				warn("[Garage] step: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			tick += 1
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(daily, player)
				if not ok then
					warn("[Garage] daily: " .. tostring(err))
				end
			end
			if tick % 120 == 0 then
				for player, s in states do
					if s.dirty and player.Parent == Players then
						task.spawn(saveNow, player)
					end
				end
			end
		end
	end)
	game:BindToClose(function()
		for player, s in states do
			if s.dirty and player.Parent == Players then
				pcall(saveNow, player)
			end
		end
	end)
end

function Garage.onLoaded(player: Player)
	local d = Profiles.get(player)
	if not d then
		return
	end
	local s = S(player)
	if type(d.cars) == "table" and #d.cars > 0 then
		-- Profiles kept the list (after the integration): it wins; the store mirrors it
		d.cars = GS.sanitizeCars(d.cars)
		s.canSave = storeEnabled
	else
		d.cars = {}
		-- the store read yields: never hold up the other feature hooks
		task.spawn(function()
			local cars, ok, msg = loadCars(player)
			if player.Parent ~= Players or Profiles.get(player) ~= d then
				return
			end
			-- anything granted while loading (tests) is kept
			for _, c in d.cars do
				if not GS.findCar(cars, c.id) then
					table.insert(cars, c)
				end
			end
			d.cars = GS.sanitizeCars(cars)
			s.canSave = ok
			s.loaded = true
			if msg then
				ctx.notify(player, "warn", "차 정보", msg)
			end
			pushCars(player)
		end)
		return
	end
	s.loaded = true
	pushCars(player)
end

function Garage.onCharacter(player: Player, _character: Model)
	local s = states[player]
	if s and s.test then
		task.spawn(endTest, player, "respawn")
	end
end

function Garage.onLeave(player: Player)
	local s = states[player]
	if not s then
		return
	end
	if s.track then
		untrack(player)
	end
	if s.test then
		s.test = nil
	end
	if s.dirty then
		saveNow(player)
	end
	states[player] = nil
end

return Garage
