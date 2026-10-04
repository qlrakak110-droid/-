-- Streaming: interiors exist only where players are (the mobile budget of the building system).
--   * a building's INTERIOR (cores, stairs, elevators, unit walls / doors, shops' counters) is built the
--     first time any player comes within Config.ACTIVATE studs, and parked in ServerStorage (the same
--     instances, re-parented: doors, elevators, owners' furniture keep their state) after nobody was
--     within Config.DEACTIVATE studs for Config.PARK_AFTER seconds;
--   * FURNITURE / shop props of a storey are built while a player is on that storey (or the storeys
--     next to it, Config.FURNISH_FLOORS) or near its street level, and dropped Config.UNFURNISH_AFTER
--     seconds after the last such player left (owners' layouts are rebuilt from their saved data).
-- Clients additionally switch off far interior lights / sounds / screens (client InteriorLOD), and
-- StreamingEnabled streams the parts themselves.
--   Streaming.ensure(rec)            build / unpark now (tours, teleports into a building)
--   Streaming.ensureFloor(rec, fl)   furnish one storey now

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Util = Shared.Util

local Streaming = {}

local Registry: any
local Builder: any
local services: any

type State = { hot: boolean, building: boolean, lastNear: number, floorWanted: { [string]: number }, hold: { [string]: number } }
local state: { [any]: State } = {}

function Streaming.init(ctx: any)
	Registry = ctx.Registry
	Builder = ctx.Builder
	services = ctx.services
	for _, rec in Registry.recs do
		state[rec] = { hot = false, building = false, lastNear = 0, floorWanted = {}, hold = {} }
	end
	-- storeys with an active session (shop order, decor, karaoke, a guest list...) are never dropped
	Builder.canUnfurnish = function(rec: any, fl: any): boolean
		for _, name in { "ShopFlows", "Decor", "Interact" } do
			local s = services[name]
			if s and s.busyFloor and s.busyFloor(rec, fl) then
				return false
			end
		end
		return true
	end
end

local function interiorParent(rec: any): Instance
	return rec.model
end

function Streaming.isHot(rec: any): boolean
	local st = state[rec]
	return st ~= nil and st.hot
end

function Streaming.ensure(rec: any)
	local st = state[rec]
	if not st then
		return
	end
	while st.building do
		task.wait()
	end
	if st.hot then
		return
	end
	if not rec.interior then
		st.building = true
		local t = os.clock()
		local ok, err = pcall(Builder.buildInterior, rec)
		st.building = false
		if not ok then
			warn("[GwangalliBuildings] interior " .. rec.id .. ": " .. tostring(err))
			return
		end
		print(string.format("[GwangalliBuildings] interior %s built (%.0f ms)", rec.id, (os.clock() - t) * 1000))
	end
	rec.interior.Parent = interiorParent(rec)
	st.hot = true
	st.lastNear = os.clock()
	if services.Elevators and services.Elevators.onHot then
		services.Elevators.onHot(rec)
	end
	if services.Housing and services.Housing.onHot then
		services.Housing.onHot(rec)
	end
end

function Streaming.park(rec: any)
	local st = state[rec]
	if not st or not st.hot or not rec.interior then
		return
	end
	for _, fl in Builder.storeys(rec) do
		Builder.unfurnishFloor(rec, fl)
	end
	rec.interior.Parent = Registry.parked
	st.hot = false
end

function Streaming.ensureFloor(rec: any, fl: any)
	Streaming.ensure(rec)
	local st = state[rec]
	if st then
		st.floorWanted[fl.label] = os.clock()
		st.hold[fl.label] = os.clock() + 10
	end
	if not fl.furnished then
		Builder.furnishFloor(rec, fl)
	end
end

-- keep a storey furnished for `seconds` more (tours, karaoke rooms ...)
function Streaming.hold(rec: any, fl: any, seconds: number)
	local st = state[rec]
	if st then
		st.hold[fl.label] = math.max(st.hold[fl.label] or 0, os.clock() + seconds)
	end
end

local function pass()
	local now = os.clock()
	local positions = {}
	for _, p in Players:GetPlayers() do
		local pos = Registry.pos(p)
		if pos then
			table.insert(positions, pos)
		end
	end
	for _, rec in Registry.recs do
		local st = state[rec]
		if st and not st.building then
			local bcf, bsize = Builder.Plan.bounds(rec)
			local nearest = math.huge
			for _, pos in positions do
				nearest = math.min(nearest, Util.boxDistance(bcf, bsize, pos))
			end
			if nearest <= Config.ACTIVATE then
				st.lastNear = now
				if not st.hot then
					task.spawn(Streaming.ensure, rec)
				end
			elseif st.hot and nearest > Config.DEACTIVATE and now - st.lastNear > Config.PARK_AFTER then
				Streaming.park(rec)
			end
			if st.hot and rec.interior then
				-- which storeys are wanted
				for _, pos in positions do
					local l = rec.cf:PointToObjectSpace(pos)
					local horiz = math.max(0, math.abs(l.X) - rec.W / 2, -l.Z, l.Z - rec.D)
					if horiz <= Config.FURNISH_RADIUS then
						local fl = Builder.floorAt(rec, l.Y)
						local storeys = Builder.storeys(rec)
						for _, f in storeys do
							local wanted = false
							if fl then
								local di = math.abs(f.index - fl.index)
								wanted = di <= Config.FURNISH_FLOORS
								if not wanted and di == 1 then
									-- on the stairs: the storey you are walking to is built before you arrive
									wanted = math.abs((l.Y - 3) - f.y) < Config.STAIR_PREFETCH
								end
								if fl.label == "RF" or f.label == "RF" then
									wanted = wanted or (f.label == "RF" and math.abs(l.Y - f.y) < 14)
								end
							end
							-- people on the street see the ground storey's shops / lobby
							if horiz > 0.5 and horiz <= Config.STREET_FURNISH and math.abs(f.y) < 1 and math.abs(l.Y) < 16 then
								wanted = true
							end
							if wanted then
								st.floorWanted[f.label] = now
							end
						end
					end
				end
				for _, f in Builder.storeys(rec) do
					local last = st.floorWanted[f.label] or 0
					local held = (st.hold[f.label] or 0) > now
					if now - last < 1 or held then
						if not f.furnished then
							Builder.furnishFloor(rec, f)
						end
					elseif f.furnished and now - last > Config.UNFURNISH_AFTER then
						Builder.unfurnishFloor(rec, f)
					end
				end
			end
		end
	end
end

function Streaming.start()
	-- a forced flag for tests / screenshots: Workspace attribute GwB_BuildAll = true builds everything
	if workspace:GetAttribute("GwB_BuildAll") == true then
		for _, rec in Registry.recs do
			Streaming.ensure(rec)
			for _, fl in Builder.storeys(rec) do
				Builder.furnishFloor(rec, fl)
			end
		end
	end
	while true do
		local ok, err = pcall(pass)
		if not ok then
			warn("[GwangalliBuildings] streaming: " .. tostring(err))
		end
		task.wait(Config.STREAM_TICK)
	end
end

return Streaming
