-- Builder/District: the demo street of the building system — a 2-lane road with sidewalks, crosswalks,
-- street lights, trees, a bus stop and a pocket park, with eight lots:
--   north side (facing south): 아파트 · 오피스텔 · 빌라 · 원룸텔
--   south side (facing north): 호텔 · 상가 · 고깃집 · 카페
-- Hand-placed sites: any Part tagged GwB_Site (attributes Archetype, Seed?, Name?, Wear?, Floors?) gets
-- a building whose street facade stands on the part's front face (LookVector = toward the street).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Kit = Shared.Kit
local Config = Shared.Config
local Rng = Shared.Rng

local Plan = require(script.Parent.Plan)

local District = {}

local V3, CF = Vector3.new, CFrame.new
local rad = math.rad

District.LOTS = {
	{ archetype = "apartment", id = "apt", side = "N", x = -112 },
	{ archetype = "officetel", id = "otl", side = "N", x = -24 },
	{ archetype = "villa", id = "villa", side = "N", x = 33 },
	{ archetype = "oneroom", id = "oneroom", side = "N", x = 95 },
	{ archetype = "hotel", id = "hotel", side = "S", x = -135 },
	{ archetype = "plaza", id = "plaza", side = "S", x = -70 },
	{ archetype = "bbq", id = "bbq", side = "S", x = -20 },
	{ archetype = "cafe", id = "cafe", side = "S", x = 18 },
}

District.X0, District.X1 = -172, 132
District.Z0, District.Z1 = -70, 76
District.ROAD = 12 -- half width of the carriageway
District.WALK = 8 -- sidewalk width

-- site frame of a lot (building-local -z faces the street)
function District.siteCF(origin: CFrame, lot: any): CFrame
	local front = District.ROAD + District.WALK
	if lot.side == "N" then
		return origin * CF(lot.x, 0, front)
	end
	return origin * CF(lot.x, 0, -front) * CFrame.Angles(0, math.pi, 0)
end

-- building-local rect -> district-local rect (sites are rotated by 0 or 180 degrees only)
local function toDistrict(origin: CFrame, rec: any, r: any): any
	local a = origin:ToObjectSpace(rec.cf * CF(r.x0, 0, r.z0)).Position
	local b = origin:ToObjectSpace(rec.cf * CF(r.x1, 0, r.z1)).Position
	return Plan.rect(a.X, a.Z, b.X, b.Z)
end

-- ground, road, sidewalks, street furniture (static, built once)
function District.buildGround(origin: CFrame, recs: { any }, parent: Instance): Model
	local m = Kit.model(parent, "Street")
	local X0, X1 = District.X0, District.X1
	local R, Wk = District.ROAD, District.WALK
	local rng = Rng.new(Rng.hash("district"))
	Kit.setBudget(Config.BUILD_PARTS_PER_STEP)
	-- carriageway (0.5 below the sidewalks) + markings
	Kit.box(m, origin, X0, -1.5, -R, X1, -0.5, R, "Asphalt", { 58, 58, 62 }, { name = "Road" })
	local x = X0 + 2
	while x < X1 - 4 do
		Kit.box(m, origin, x, -0.5, -0.2, x + 4, -0.46, 0.2, "SmoothPlastic", { 250, 210, 40 }, { collide = false, name = "CenterLine" })
		x += 8
	end
	for _, cx in { -90, 0, 60 } do
		for k = -5, 5 do
			Kit.box(m, origin, cx - 4, -0.5, k * 2.2 - 0.6, cx + 4, -0.46, k * 2.2 + 0.6, "SmoothPlastic", { 245, 245, 245 }, { collide = false, name = "Crosswalk" })
		end
	end
	-- sidewalks + curbs
	local WK = Wk - 0.42 -- the last 0.42 belongs to the buildings' slabs / yards (no coplanar overlap)
	for _, s in { -1, 1 } do
		local z0, z1 = if s > 0 then R else -R - WK, if s > 0 then R + WK else -R
		Kit.box(m, origin, X0, -1.5, z0, X1, 0, z1, "Pavement", { 196, 186, 172 }, { name = "Sidewalk" })
		local cz = if s > 0 then R else -R
		Kit.box(m, origin, X0, -0.6, cz - 0.4, X1, 0.05, cz + 0.4, "Concrete", { 210, 208, 204 }, { name = "Curb", collide = false })
		-- street lights + trees
		local lx = X0 + 8
		local i = 0
		while lx < X1 - 4 do
			i += 1
			local lz = cz + s * 1.2
			if i % 2 == 0 then
				Kit.vcyl(m, origin, lx, 7, lz, 14, 0.5, "Metal", { 70, 74, 80 }, { name = "LampPole" })
				Kit.box(m, origin, lx - 0.15, 13.6, lz - s * 3.2, lx + 0.15, 13.9, lz, "Metal", { 70, 74, 80 }, { name = "LampArm", collide = false })
				local head = Kit.box(m, origin, lx - 0.7, 13.1, lz - s * 3.6, lx + 0.7, 13.6, lz - s * 2.4, "Neon", { 255, 236, 200 }, { name = "LampHead", collide = false })
				head:SetAttribute("NightGlow", true)
				Kit.light(head, "spot", { face = "bottom", color = { 255, 220, 170 }, brightness = 2, range = 30, angle = 110, attrs = { Group = "street" } })
			else
				local tz = cz + s * (Wk - 2.2)
				Kit.box(m, origin, lx - 1.4, -0.2, tz - 1.4, lx + 1.4, 0.05, tz + 1.4, "Ground", { 90, 70, 50 }, { collide = false, name = "TreePit" })
				Kit.vcyl(m, origin, lx, 3, tz, 6, 0.7, "Wood", { 90, 66, 46 }, { name = "Trunk" })
				local c = Kit.ball(m, origin, lx, 8, tz, 6.5 + rng:range(-1, 1), "LeafyGrass", { 70, 120 + rng:int(0, 30), 60 }, { collide = false, name = "Canopy" })
				c.CastShadow = true
			end
			lx += 12
		end
	end
	-- bus stop (south side, by the park)
	local bs = origin * CF(70, 0, -R - Wk + 1.6)
	Kit.part(m, bs * CF(0, 4.6, 0), V3(10, 0.3, 3), "Glass", { 200, 220, 230 }, { name = "ShelterRoof", tr = 0.3 })
	Kit.part(m, bs * CF(0, 2.4, 1.3), V3(10, 4.4, 0.15), "Glass", { 200, 220, 230 }, { name = "ShelterBack", tr = 0.5 })
	Kit.part(m, bs * CF(0, 1.2, 0.6), V3(6, 0.3, 1.2), "Wood", { 150, 110, 76 }, { name = "Bench" })
	local busSign = Kit.part(m, bs * CF(-5.6, 3.6, -0.6), V3(0.3, 2.6, 1.8), "SmoothPlastic", { 30, 90, 180 }, { name = "BusSign" })
	Kit.text(busSign, "left", "🚌 광안리해수욕장\n41 · 42 · 83 · 108", { color = { 255, 255, 255 }, ppS = 30, maxDist = 60 })
	Kit.text(busSign, "right", "🚌 광안리해수욕장\n41 · 42 · 83 · 108", { color = { 255, 255, 255 }, ppS = 30, maxDist = 60 })
	-- ground (yards) = district box minus road, sidewalks, building footprints and ramp holes
	local holes = { Plan.rect(X0, -R - WK, X1, R + WK) }
	for _, rec in recs do
		-- footprint at street level: the ground storey's rects and every basement's rects
		for _, fl in rec.floors do
			if fl.y <= 0.01 then
				for _, r in fl.rects do
					table.insert(holes, toDistrict(origin, rec, Plan.rect(r.x0 - 0.4, r.z0 - 0.4, r.x1 + 0.4, r.z1 + 0.4)))
				end
			end
		end
		for _, h in rec.groundHoles or {} do
			table.insert(holes, toDistrict(origin, rec, h))
		end
	end
	local zMin, zMax = District.Z0, District.Z1
	for _, piece in Plan.subtract(Plan.rect(X0, zMin, X1, zMax), holes) do
		local inPark = piece.x0 >= 40 and piece.z1 <= -R - Wk + 0.1
		Kit.box(m, origin, piece.x0, -1.5, piece.z0, piece.x1, 0, piece.z1, if inPark then "Grass" else "Pavement", if inPark then { 96, 150, 80 } else { 176, 170, 160 }, { name = "Yard" })
	end
	-- pocket park furniture (south-east corner)
	for i = 0, 3 do
		local px = 52 + i * 18
		Kit.box(m, origin, px - 3, 0, -42, px + 3, 1.2, -40.6, "Wood", { 150, 110, 76 }, { name = "ParkBench" })
		Kit.vcyl(m, origin, px + 6, 3, -52, 6, 0.8, "Wood", { 90, 66, 46 }, { name = "Trunk" })
		Kit.ball(m, origin, px + 6, 8.5, -52, 8, "LeafyGrass", { 70, 140, 70 }, { collide = false, name = "Canopy" })
	end
	local parkSign = Kit.part(m, origin * CF(60, 2.2, -R - Wk - 1.5), V3(6, 2.4, 0.4), "Wood", { 120, 86, 60 }, { name = "ParkSign" })
	Kit.text(parkSign, "front", "광안 쌈지공원", { color = { 255, 250, 230 }, ppS = 40, maxDist = 60 })
	-- podium (축대): stone retaining walls around the district + grand stairs at both road ends
	local podium = tonumber(Config.get("DISTRICT_PODIUM")) or 0
	if podium > 0 then
		local stone = { 150, 144, 132 }
		local Z0, Z1 = District.Z0, District.Z1
		local stairW = R + Wk
		local run = podium * 1.6
		-- long sides
		Kit.box(m, origin, X0 - 1.2, -podium - 0.5, Z1, X1 + 1.2, 0.6, Z1 + 1.2, "Cobblestone", stone, { name = "Retaining" })
		Kit.box(m, origin, X0 - 1.2, -podium - 0.5, Z0 - 1.2, X1 + 1.2, 0.6, Z0, "Cobblestone", stone, { name = "Retaining" })
		-- short sides with the stair openings over the road + sidewalks
		for _, ex in { X0 - 1.2, X1 } do
			Kit.box(m, origin, ex, -podium - 0.5, Z0, ex + 1.2, 0.6, -stairW, "Cobblestone", stone, { name = "Retaining" })
			Kit.box(m, origin, ex, -podium - 0.5, stairW, ex + 1.2, 0.6, Z1, "Cobblestone", stone, { name = "Retaining" })
		end
		-- grand stairs down to the surrounding ground (one at each end)
		for _, e in { { X0 - 1.2, -1 }, { X1 + 1.2, 1 } } do
			local x0 = e[1]
			local dir = e[2]
			local x1 = x0 + dir * run
			Kit.flight(m, origin * CF(x0, 0, 0) * CFrame.Angles(0, math.rad(90 * dir), 0), -stairW, stairW, 0, run, 0, -podium, "Granite", { 168, 160, 150 }, {})
			-- side walls of the stair
			for _, sz in { -stairW - 0.6, stairW + 0.6 } do
				Kit.box(m, origin, math.min(x0, x1), -podium - 0.5, sz - 0.6, math.max(x0, x1), 1.2, sz + 0.6, "Cobblestone", stone, { name = "StairWall" })
			end
			local sign = Kit.part(m, origin * CF(x0 + dir * 1.5, 3.2, stairW + 0.2), V3(0.4, 2.4, 10), "SmoothPlastic", { 20, 60, 120 }, { name = "DistrictSign" })
			Kit.text(sign, if dir > 0 then "right" else "left", "광안 리빙 스트리트\n아파트 · 오피스텔 · 빌라 · 상가 · 호텔", { color = { 255, 255, 255 }, ppS = 30, maxDist = 120 })
		end
	end
	Kit.setBudget(nil)
	return m
end

-- carve terrain where basements / ramps go (no-op when the place has no terrain there)
function District.carve(rec: any)
	if not Config.CARVE_TERRAIN then
		return
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	local boxes = table.clone(rec.carve or {})
	local bottom = rec.floors[1].y - Config.SLAB - 1
	if bottom < -1 then
		table.insert(boxes, { -rec.W / 2 - 1, bottom, -1, rec.W / 2 + 1, 2, rec.D + 1 })
	end
	for _, b in boxes do
		local c = rec.cf * CF((b[1] + b[4]) / 2, (b[2] + b[5]) / 2, (b[3] + b[6]) / 2)
		pcall(function()
			terrain:FillBlock(c, V3(math.abs(b[4] - b[1]), math.abs(b[5] - b[2]), math.abs(b[6] - b[3])), Enum.Material.Air)
		end)
	end
end

-- hand-placed sites in the place (Parts tagged GwB_Site)
function District.sites(): { any }
	local out = {}
	for _, p in CollectionService:GetTagged("GwB_Site") do
		if p:IsA("BasePart") then
			local arch = p:GetAttribute("Archetype")
			if type(arch) == "string" then
				local look = p.CFrame.LookVector
				local yaw = math.atan2(-look.X, -look.Z)
				local base = p.Position - V3(0, p.Size.Y / 2, 0)
				local front = base + V3(look.X, 0, look.Z).Unit * (p.Size.Z / 2)
				table.insert(out, {
					archetype = arch,
					id = (p:GetAttribute("Id") :: string?) or (arch .. "_" .. p.Name),
					cf = CF(front) * CFrame.Angles(0, yaw, 0),
					seed = p:GetAttribute("Seed"),
					name = p:GetAttribute("Name"),
					wear = p:GetAttribute("Wear"),
					floors = p:GetAttribute("Floors"),
				})
				p.Transparency = 1
				p.CanCollide = false
			end
		end
	end
	return out
end

return District
