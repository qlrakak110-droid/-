-- Builder: plans, shells, interiors and furnishing of the enterable buildings.
--   Builder.plan(archetype, def)           -> rec (data only, cheap; done for every building at start)
--   Builder.buildShell(rec, parent)        -> Model "Shell" (always present)
--   Builder.buildInterior(rec)             -> Model "Interior" (cores, stairs, elevators, corridors, shops)
--   Builder.furnishFloor(rec, fl)          the homes of one storey (unit walls, doors, fixtures) + the
--                                          furniture / props of its units, shops and lobby
--   Builder.unfurnishFloor(rec, fl)        drops them again (the storey keeps its core / corridor)
-- Units are the bulk of an interior (a tower has hundreds of rooms), so they only exist on the storeys
-- around players (see the Streaming service); the cores, stairs, corridors and shops exist while the
-- building is "hot".
--   Builder.decorHook(unit, into) -> bool  set by the Decor service: builds an owner's saved furniture
-- Interior Templates live in Units (homes / hotel rooms) and Shops (shops / lobbies); building types in
-- Archetypes. Everything is deterministic from the building seed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Kit = Shared.Kit
local Config = Shared.Config
local Rng = Shared.Rng

local Plan = require(script.Plan)
local Core = require(script.Core)
local Shell = require(script.Shell)
local Units = require(script.Units)
local Shops = require(script.Shops)
local Archetypes = require(script.Archetypes)
Archetypes.bind(Shops)

local Builder = {}
Builder.Plan = Plan
Builder.Core = Core
Builder.Shell = Shell
Builder.Units = Units
Builder.Shops = Shops
Builder.Archetypes = Archetypes
Builder.decorHook = nil :: ((any, Instance) -> boolean)?
Builder.canUnfurnish = nil :: ((any, any) -> boolean)?
Builder.onFurnished = nil :: ((any, any) -> ())?
Builder.onUnfurnished = nil :: ((any, any) -> ())?
Builder.onUnitsBuilt = nil :: ((any, any) -> ())?

function Builder.plan(archetype: string, def: any): any
	local fn = (Archetypes :: any)[archetype]
	assert(type(fn) == "function", "unknown archetype " .. tostring(archetype))
	local rec = fn(def)
	rec.archetype = archetype
	return rec
end

local function storeys(rec: any): { any }
	local out = table.clone(rec.floors)
	for _, fl in rec.extraFloors or {} do
		table.insert(out, fl)
	end
	return out
end
Builder.storeys = storeys

function Builder.buildShell(rec: any, parent: Instance): Model
	Kit.setBudget(Config.BUILD_PARTS_PER_STEP)
	local m = Shell.build(rec, parent)
	Kit.setBudget(nil)
	rec.shell = m
	return m
end

-- the storey context used by every builder
local function ctxFor(rec: any, fl: any, parent: Instance): any
	local walls = {}
	return {
		rec = rec,
		fl = fl,
		parent = parent,
		rng = Rng.child(rec.seed, "fl:" .. fl.label),
		wallOnce = function(key: string): boolean
			if walls[key] then
				return false
			end
			walls[key] = true
			return true
		end,
	}
end
Builder.ctxFor = ctxFor

function Builder.buildInterior(rec: any): Model
	Kit.setBudget(Config.BUILD_PARTS_PER_STEP)
	local m = Kit.model(nil, "Interior", { BuildingId = rec.id }, { "GwB_Interior" })
	local ev = Kit.model(m, "Elevators")
	rec.elevatorModels = {}
	for _, e in rec.elevators do
		local em = Core.elevator(ev, rec, e)
		em:SetAttribute("BuildingId", rec.id)
		rec.elevatorModels[e.id] = em
	end
	rec.floorModels = {}
	for _, fl in storeys(rec) do
		local fm = Kit.model(m, "Floor_" .. fl.label, { BuildingId = rec.id, Floor = fl.label, Y = fl.y })
		rec.floorModels[fl.label] = fm
		local ctx = ctxFor(rec, fl, fm)
		fl.ctx = ctx
		-- stairs: every stair that serves this storey builds its storey part here
		for _, s in rec.stairs do
			for i, label in s.floors do
				if label == fl.label then
					Core.stairFloor(fm, rec, s, i)
				end
			end
		end
		for _, s in fl.shops do
			Shops.build(ctx, s)
		end
		if rec.hooks.floor then
			rec.hooks.floor(ctx, fl)
		end
		Kit.model(fm, "Furnish", { BuildingId = rec.id, Floor = fl.label }, { "GwB_Furnish" })
		fl.furnished = false
		fl.unitsBuilt = false
		for _, u in fl.units do
			u.model = nil
		end
	end
	Kit.setBudget(nil)
	rec.interior = m
	return m
end

-- the homes (unit walls, doors, windows, built-in fixtures) of one storey
function Builder.buildUnits(rec: any, fl: any)
	if fl.unitsBuilt or not rec.floorModels or #fl.units == 0 then
		fl.unitsBuilt = true
		return
	end
	local fm = rec.floorModels[fl.label]
	if not fm then
		return
	end
	fl.unitsBuilt = true
	local ctx = ctxFor(rec, fl, fm) -- fresh shared-wall memory for this storey's units
	for _, u in fl.units do
		Units.build(ctx, u)
	end
	if Builder.onUnitsBuilt then
		Builder.onUnitsBuilt(rec, fl)
	end
end

function Builder.clearUnits(rec: any, fl: any)
	for _, u in fl.units do
		if u.model then
			u.model:Destroy()
			u.model = nil
		end
	end
	fl.unitsBuilt = false
end

function Builder.furnishFloor(rec: any, fl: any)
	if fl.furnished or not rec.floorModels then
		return
	end
	local fm = rec.floorModels[fl.label]
	if not fm then
		return
	end
	fl.furnished = true
	Kit.setBudget(Config.BUILD_PARTS_PER_STEP)
	Builder.buildUnits(rec, fl)
	local ctx = fl.ctx or ctxFor(rec, fl, fm)
	for _, u in fl.units do
		local into = u.model and u.model:FindFirstChild("Furnish")
		if into then
			local handled = false
			if Builder.decorHook then
				handled = Builder.decorHook(u, into)
			end
			if not handled then
				Units.furnish(ctx, u, into)
			end
		end
	end
	for _, s in fl.shops do
		local into = s.model and s.model:FindFirstChild("Furnish")
		if into then
			Shops.furnish(ctx, s, into)
		end
	end
	if rec.hooks.furnish then
		local into = fm:FindFirstChild("Furnish")
		if into then
			rec.hooks.furnish(ctx, fl, into)
		end
	end
	Kit.setBudget(nil)
	if Builder.onFurnished then
		Builder.onFurnished(rec, fl)
	end
end

function Builder.unfurnishFloor(rec: any, fl: any)
	if not fl.furnished or not rec.floorModels then
		return
	end
	if Builder.canUnfurnish and not Builder.canUnfurnish(rec, fl) then
		return
	end
	fl.furnished = false
	local fm = rec.floorModels[fl.label]
	if not fm then
		return
	end
	local function clear(f: Instance?)
		if f then
			for _, c in f:GetChildren() do
				c:Destroy()
			end
		end
	end
	for _, u in fl.units do
		clear(u.model and u.model:FindFirstChild("Furnish"))
	end
	for _, s in fl.shops do
		clear(s.model and s.model:FindFirstChild("Furnish"))
	end
	clear(fm:FindFirstChild("Furnish"))
	Builder.clearUnits(rec, fl)
	if Builder.onUnfurnished then
		Builder.onUnfurnished(rec, fl)
	end
end

-- rebuild one unit's furniture (after a purchase / decor change) when its storey is furnished
function Builder.refurnishUnit(u: any)
	local rec, fl = u.rec, u.fl
	if not fl.furnished or not u.model then
		return
	end
	local into = u.model:FindFirstChild("Furnish")
	if not into then
		return
	end
	for _, c in into:GetChildren() do
		c:Destroy()
	end
	local handled = false
	if Builder.decorHook then
		handled = Builder.decorHook(u, into)
	end
	if not handled then
		Units.furnish(fl.ctx or ctxFor(rec, fl, rec.floorModels[fl.label]), u, into)
	end
end

-- storey of a building-local height (for streaming: which floor a player stands on)
function Builder.floorAt(rec: any, yLocal: number): any?
	local best = nil
	for _, fl in storeys(rec) do
		if yLocal >= fl.y - 1.5 and yLocal < fl.y + fl.h - 0.5 then
			best = fl
		end
	end
	return best
end

return Builder
