-- GwangalliShopCrew/Director: which shops have a crew right now, and the loops that keep everything honest.
--   * ACTIVATION (1 Hz): a ShopLife shop that is open (Bus "open": players within ~75 studs) gets its crew when
--     a player is within Config.SPAWN_R (3D, so annex rooms upstairs work); the nearest Config.MAX_SHOPS win
--     (the shop a player stands in always wins), at most Config.MAX_CREW_RIGS rigs. A crew goes home when
--     nobody was within DESPAWN_R for DESPAWN_AFTER s, on Bus "close", or when a player WORKS there
--     (Jobs / WorkPlacement / 점장 / 국밥 알바 ...: the crew stands down, never blocking a job flow).
--   * BRAINS (4 Hz), DINERS (1 Hz), SERVE GUARD (1 Hz): separate pcall'd loops; a crew whose brain stops
--     ticking loses staffMode (ShopLife serves by itself again).
--   Director.init(Shared, Bridge, Net, mods)   Director.start()   Director.onBus(kind, d)   Director.shutdown()
--   Director.resolve(id) -> Talk target?       Director.status() -> table

local Players = game:GetService("Players")

local Director = {}

local Config: any = nil
local Bridge: any = nil
local Sites: any = nil
local Crew: any = nil
local Serve: any = nil
local Diners: any = nil
local Talk: any = nil
local Augment: any = nil
local Rig: any = nil

local crews: { [string]: any } = {}
local active: { [string]: boolean } = {}
local moods: { [string]: any } = {}
local lastNear: { [string]: number } = {}
local standUntil: { [string]: number } = {}
local owned: { [string]: number } = {} -- shops we put in staffMode (the guard watches them a while longer)
local stopped = false
local errors = { brain = 0, activation = 0, guard = 0, diners = 0 }
local lastError: string? = nil
local coexist = false

function Director.init(S: any, B: any, N: any, mods: any)
	Config, Bridge = S.Config, B
	local _ = N
	Sites, Crew, Serve, Diners, Talk, Augment, Rig = mods.Sites, mods.Crew, mods.Serve, mods.Diners, mods.Talk, mods.Augment, mods.Rig
end

function Director.setCoexist(on: boolean)
	coexist = on
end

local function now(): number
	return os.clock()
end

local function playerSpots(): { { p: Player, pos: Vector3 } }
	local out = {}
	for _, p in Players:GetPlayers() do
		local pos = Bridge.posOf(p)
		if pos then
			table.insert(out, { p = p, pos = pos })
		end
	end
	return out
end

local function centerOf(site: any): Vector3
	return Vector3.new(site.center.X, site.floorY + 3, site.center.Z)
end

-------------------------------------------------------------------------------------------------
-- talk targets
-------------------------------------------------------------------------------------------------
function Director.resolve(id: string): any?
	local R = Rig.byId(id)
	if R and R.crew and R.crew.alive and Rig.alive(R) then
		local crew = R.crew
		local site = crew.site
		return {
			id = R.id,
			kind = "crew",
			root = R.root,
			persona = R.persona,
			role = R.role,
			shopKey = crew.key,
			shopName = site.name,
			shopType = site.type,
			flow = site.flow,
			menuKey = site.menuKey,
			crew = crew,
			R = R,
		}
	end
	return Augment.target(id)
end

-------------------------------------------------------------------------------------------------
-- spawn / despawn
-------------------------------------------------------------------------------------------------
local function despawn(key: string, why: string)
	local crew = crews[key]
	if not crew then
		return
	end
	crews[key] = nil
	for _, R in crew.rigs do
		Talk.closeFor(R.id)
	end
	pcall(Diners.clear, crew)
	if crew.staffModeOn then
		owned[key] = now()
	end
	Crew.destroy(crew, why)
	Sites.unpublish(key)
	if Config.DEBUG then
		print(string.format("[GwangalliShopCrew] crew off: %s (%s)", crew.site.name, why))
	end
end

local function spawn(site: any): boolean
	moods[site.key] = moods[site.key] or { v = Config.MOOD.base }
	local crew = Crew.new(site, { coexist = coexist, moodRef = moods[site.key] })
	if not crew then
		return false
	end
	crews[site.key] = crew
	lastNear[site.key] = now()
	if crew.staffModeOn then
		owned[site.key] = math.huge
	end
	if Config.DEBUG then
		local roles = {}
		for r in crew.rigs do
			table.insert(roles, r)
		end
		print(string.format("[GwangalliShopCrew] crew on: %s [%s]", site.name, table.concat(roles, ",")))
	end
	return true
end

local function workerInside(site: any): Player?
	for _, p in Players:GetPlayers() do
		if Bridge.working(p) then
			local pos = Bridge.posOf(p)
			if pos and Sites.inside(site, pos, 6) then
				return p
			end
		end
	end
	return nil
end

-- GwangalliShopService waiters that show up after the takeover (a Script that cannot be stopped in this
-- engine / re-enabled by someone): removed again, and our own shops get staffMode back
local function sweepShopService()
	if not Config.TAKE_OVER_SHOP_SERVICE or coexist then
		return
	end
	local f = workspace:FindFirstChild("GwangalliShopStaff")
	if not f then
		return
	end
	local found = false
	for _, m in f:GetChildren() do
		local w = m:GetAttribute("GwWaiter")
		if type(w) == "string" and w ~= "diner" then
			found = true
			break
		end
	end
	if found then
		Bridge.takeOverShopService()
		for key, crew in crews do
			if crew.staffModeOn then
				Bridge.req("staffMode", { shop = key, on = true, roles = { cook = false, serve = true } })
			end
		end
	end
end

local builds = 0
local function activation()
	sweepShopService()
	if workspace:GetAttribute("GwShopCrew") == false then
		for key in crews do
			despawn(key, "switched off")
		end
		return
	end
	local t = now()
	local spots = playerSpots()
	builds = 0
	local cands = {}
	for key in active do
		if standUntil[key] and t < standUntil[key] then
			continue
		end
		local site = Sites.get(key)
		builds += 1
		if site and site.ok then
			local c = centerOf(site)
			local best = math.huge
			local inside = false
			for _, s in spots do
				local d = (s.pos - c).Magnitude
				if d < best then
					best = d
				end
				if Sites.inside(site, s.pos, 1) then
					inside = true
				end
			end
			if best <= Config.DESPAWN_R then
				lastNear[key] = t
			end
			table.insert(cands, { key = key, site = site, d = best, inside = inside, rigs = #site.roles })
		end
		if builds > 3 then
			task.wait() -- (site builds are time sliced across frames)
		end
	end
	table.sort(cands, function(a, b)
		if a.inside ~= b.inside then
			return a.inside
		end
		return a.d < b.d
	end)
	local keep: { [string]: boolean } = {}
	local rigs = 0
	local shops = 0
	for _, c in cands do
		if shops < Config.MAX_SHOPS and rigs + c.rigs <= Config.MAX_CREW_RIGS and (c.d <= Config.SPAWN_R or (crews[c.key] and c.d <= Config.DESPAWN_R)) then
			keep[c.key] = true
			shops += 1
			rigs += c.rigs
		end
	end
	-- stand-down: someone is working this shop
	for key, crew in crews do
		local worker = workerInside(crew.site)
		if worker and not crew.standDown then
			crew.standDown = true
			standUntil[key] = t + 30
			local R = Crew.greeter(crew)
			if R then
				Crew.say(crew, R, "standDown", nil, "plain", 2.6)
			end
			task.delay(2.5, function()
				if crews[key] == crew then
					despawn(key, "stand down")
				end
			end)
		end
	end
	for key, crew in crews do
		if not crew.standDown then
			local gone = not active[key]
			local far = not keep[key] and (t - (lastNear[key] or 0) > Config.DESPAWN_AFTER or shops >= Config.MAX_SHOPS)
			if gone or far then
				despawn(key, if gone then "closed" else "far")
			end
		end
	end
	-- one new crew per second at most (rigs + avatar clones are not free)
	for _, c in cands do
		if keep[c.key] and not crews[c.key] and c.d <= Config.SPAWN_R then
			if not workerInside(c.site) then
				spawn(c.site)
			else
				standUntil[c.key] = t + 30
			end
			break
		end
	end
end

-------------------------------------------------------------------------------------------------
-- bus
-------------------------------------------------------------------------------------------------
function Director.onBus(kind: string, d: any)
	if stopped then
		return
	end
	local key = d.shop
	if type(key) ~= "string" then
		return
	end
	if kind == "open" then
		active[key] = true
		return
	elseif kind == "close" then
		active[key] = nil
		despawn(key, "closed")
		return
	end
	local crew = crews[key]
	if crew then
		local ok, err = pcall(Crew.onBus, crew, kind, d)
		if not ok then
			errors.brain += 1
			lastError = tostring(err)
			Bridge.warnOnce("bus" .. kind, "bus " .. kind .. ": " .. tostring(err))
		end
		pcall(Diners.onBus, crew, kind, d)
	else
		-- order tickets for players in shops without a crew too
		local menuKey = nil
		local rec = Bridge.shopRec(key)
		if rec then
			menuKey = rec.menuKey
		end
		if kind == "order" then
			pcall(Serve.onOrder, d, menuKey)
		elseif kind == "cooking" then
			pcall(Serve.onCooking, d)
		elseif kind == "ready" then
			pcall(Serve.onReady, d, menuKey)
		elseif kind == "served" then
			pcall(Serve.onServed, d)
		elseif kind == "pickup" then
			pcall(Serve.onPickup, d)
		end
	end
end

local function shopName(key: string): string
	local crew = crews[key]
	if crew then
		return crew.site.name
	end
	local rec = Bridge.shopRec(key)
	return if rec then tostring(rec.name) else key
end

-------------------------------------------------------------------------------------------------
-- loops
-------------------------------------------------------------------------------------------------
local function loop(name: string, period: number, fn: () -> ())
	task.spawn(function()
		while not stopped do
			local ok, err = pcall(fn)
			if not ok then
				errors[name] = (errors[name] or 0) + 1
				lastError = name .. ": " .. tostring(err)
				Bridge.warnOnce("loop" .. name, "loop " .. name .. ": " .. tostring(err))
			end
			task.wait(period)
		end
	end)
end

function Director.start()
	-- shops ShopLife already has open (we may start after it)
	for _, info in Bridge.req("shops").shops or {} do
		if type(info) == "table" and info.active and type(info.key) == "string" then
			active[info.key] = true
		end
	end
	loop("activation", 1, activation)
	loop("brain", Config.TICK, function()
		for key, crew in crews do
			local ok, err = pcall(Crew.tick, crew)
			if not ok then
				crew.errors += 1
				crew.lastError = tostring(err)
				Bridge.warnOnce("tick" .. key, "tick " .. crew.site.name .. ": " .. tostring(err))
				if crew.errors > 30 then
					despawn(key, "errors")
				end
			end
		end
		Serve.flushTickets(shopName)
	end)
	loop("diners", 1, function()
		for _, crew in crews do
			pcall(Diners.tick, crew)
		end
	end)
	loop("guard", 1, function()
		local t = now()
		for key, crew in crews do
			-- a brain that stopped ticking gives serving back to ShopLife
			if crew.staffModeOn and t - crew.lastTick > Config.BRAIN_DEAD then
				Crew.staffModeOff(crew)
				owned[key] = t
			end
		end
		Serve.guard(function(key: string): (boolean, boolean)
			local crew = crews[key]
			if crew and crew.staffModeOn then
				return true, Crew.waiter(crew) ~= nil
			end
			local o = owned[key]
			return o ~= nil and t - o < 300, false
		end)
		for key, t0 in owned do
			if t0 ~= math.huge and t - t0 > 300 then
				owned[key] = nil
			end
		end
	end)
end

function Director.shutdown()
	if stopped then
		return
	end
	stopped = true
	local keys = {}
	for key in crews do
		table.insert(keys, key)
	end
	for _, key in keys do
		pcall(despawn, key, "shutdown")
	end
	-- anything still waiting in a shop we ran
	for key in owned do
		pcall(Serve.flush, key)
	end
end

function Director.crewOf(key: string): any?
	return crews[key]
end

function Director.standDown(key: string, on: boolean)
	if on then
		standUntil[key] = math.huge
		despawn(key, "api stand down")
	else
		standUntil[key] = nil
	end
end

function Director.status(): any
	local list = {}
	local rigs = 0
	for _, crew in crews do
		local st = Crew.status(crew)
		for _ in crew.rigs do
			rigs += 1
		end
		table.insert(list, st)
	end
	local nActive = 0
	for _ in active do
		nActive += 1
	end
	return {
		crews = list,
		rigs = rigs,
		diners = Diners.count(),
		augmented = Augment.count(),
		dialogs = Talk.count(),
		activeShops = nActive,
		serve = Serve.stats(),
		errors = errors,
		lastError = lastError,
		sites = Sites.status(),
		coexist = coexist,
	}
end

return Director
