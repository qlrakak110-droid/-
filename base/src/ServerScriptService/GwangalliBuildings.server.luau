-- GwangalliBuildings (Script, ServerScriptService): 광안리 ENTERABLE BUILDINGS — the server.
--
-- At start: plans every building (the demo district at Config.DISTRICT_ORIGIN and/or Parts tagged
-- GwB_Site), builds the street and every building SHELL (facades, slabs, roofs, entrance doors, signs),
-- then starts the services. Interiors (cores, stairs, elevators, unit walls, shops) are built the first
-- time a player comes near a building and parked in ServerStorage when nobody is around; furniture
-- and shop props are built per storey near players (Streaming). Everything else is a service module:
--   Registry   buildings / units / shops lookup, remotes, server-time helpers
--   Economy    money (the life game's GwangalliGameplayAPI when present, else an own wallet)
--   Doors      every door (swing / double / slide / auto / stall / unit doorlock / hotel card / staff)
--   Elevators  real elevators: hall call -> car arrives -> doors -> car call -> ride -> arrival
--   Streaming  interior build / park / furnish by player proximity (mobile budget)
--   Interact   furniture & fixtures (bed, TV, fridge, microwave, shower, toilet, sink, washer ...)
--   ShopFlows  편의점 · 국밥집 · 고깃집 · 카페 · PC방 · 노래방 · 당구장 · 호텔 · 부동산
--   Housing    내집마련 (원룸 -> 빌라 -> 오피스텔 -> 아파트 -> 펜트하우스), ownership, tours, saves
--   Decor      furniture placement / move / rotate / delete, 벽지 · 바닥 · 조명 themes
--   Sounds     finds / verifies ambient sound ids for every sound key (no uploads)
--   Needs      포만감 · 에너지 · 청결 · 즐거움 (player attributes)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Names = Shared.Names
local Kit = Shared.Kit

local Builder = require(script.Builder)
local District = require(script.Builder.District)

local t0 = os.clock()
local function log(...)
	print("[GwangalliBuildings]", ...)
end

-- containers ------------------------------------------------------------------------------------
local root = workspace:FindFirstChild(Names.ROOT) or Kit.folder(workspace, Names.ROOT)
local parked = ServerStorage:FindFirstChild(Names.PARKED) or Kit.folder(ServerStorage, Names.PARKED)

local Registry = require(script.Registry)
Registry.init({ root = root, parked = parked, Builder = Builder })

-- plans -----------------------------------------------------------------------------------------
local origin = Config.DISTRICT_ORIGIN
do
	local o = workspace:GetAttribute("GwB_Origin")
	if typeof(o) == "CFrame" then
		origin = o
	elseif typeof(o) == "Vector3" then
		origin = CFrame.new(o)
	end
end
local recs = {}
local sites = District.sites()
if Config.get("DEMO_DISTRICT") ~= false and #sites == 0 then
	for _, lot in District.LOTS do
		local rec = Builder.plan(lot.archetype, { id = lot.id, cf = District.siteCF(origin, lot) })
		table.insert(recs, rec)
	end
end
for _, s in sites do
	local ok, rec = pcall(Builder.plan, s.archetype, s)
	if ok then
		table.insert(recs, rec)
	else
		warn("[GwangalliBuildings] site " .. tostring(s.id) .. ": " .. tostring(rec))
	end
end
for _, rec in recs do
	Registry.add(rec)
end
log(string.format("planned %d buildings, %d homes, %d shops (%.0f ms)", #recs, Registry.unitCount(), Registry.shopCount(), (os.clock() - t0) * 1000))

-- services that must exist before the shells (doors register themselves on creation) -------------
local services = {}
local function load(name: string)
	local m = script:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, mod = pcall(require, m)
	if not ok then
		warn("[GwangalliBuildings] service " .. name .. " failed to load: " .. tostring(mod))
		return nil
	end
	services[name] = mod
	return mod
end
for _, name in { "Economy", "Sounds", "Needs", "Doors", "Elevators", "Interact", "ShopFlows", "Housing", "Decor", "Streaming" } do
	load(name)
end
local ctx = { Registry = Registry, Builder = Builder, services = services, log = log }
for _, name in { "Economy", "Sounds", "Needs", "Doors", "Elevators", "Interact", "ShopFlows", "Housing", "Decor" } do
	local s = services[name]
	if s and s.init then
		local ok, err = pcall(s.init, ctx)
		if not ok then
			warn("[GwangalliBuildings] " .. name .. ".init: " .. tostring(err))
		end
	end
end

-- street + shells -------------------------------------------------------------------------------
if #recs > 0 and #sites == 0 then
	District.buildGround(origin, recs, root)
end
for _, rec in recs do
	District.carve(rec)
	local bm = Kit.model(root, rec.id, {
		BuildingId = rec.id,
		Kind = rec.archetype,
		DisplayName = rec.name,
		Floors = #rec.floors,
		Wear = rec.wear,
	}, { Names.TAG.Building })
	local bcf, bsize = Builder.Plan.bounds(rec)
	bm:SetAttribute("BoundsCF", bcf)
	bm:SetAttribute("BoundsSize", bsize)
	rec.model = bm
	local ok, err = pcall(Builder.buildShell, rec, bm)
	if not ok then
		warn("[GwangalliBuildings] shell " .. rec.id .. ": " .. tostring(err))
	end
	task.wait()
end
log(string.format("shells built (%d parts, %.1f s)", Kit.created, os.clock() - t0))

-- the rest of the services (streaming builds interiors on demand) ---------------------------------
if services.Streaming and services.Streaming.init then
	local ok, err = pcall(services.Streaming.init, ctx)
	if not ok then
		warn("[GwangalliBuildings] Streaming.init: " .. tostring(err))
	end
end
for _, name in { "Economy", "Sounds", "Needs", "Doors", "Elevators", "Interact", "ShopFlows", "Housing", "Decor", "Streaming" } do
	local s = services[name]
	if s and s.start then
		task.spawn(function()
			local ok, err = pcall(s.start)
			if not ok then
				warn("[GwangalliBuildings] " .. name .. ".start: " .. tostring(err))
			end
		end)
	end
end
workspace:SetAttribute("GwB_Ready", true)
log(string.format("ready (%.1f s)", os.clock() - t0))
