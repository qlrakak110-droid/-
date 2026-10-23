--!nocheck
-- rules.luau: Unit.scan + Rules.check on the real home templates (bprev fixtures), Codec round trip
local B = require("../out/bundle")
local R = B.R
local G = R.G
local Vector3, CFrame, Color3 = G.Vector3, G.CFrame, G.Color3
local Unit = B.load("S", "Unit")
local Rules = B.load("S", "Rules")
local Catalog = B.load("S", "Catalog")
local Codec = B.load("S", "Codec")
local Geometry = B.load("S", "Geometry")
local FX = "../../../bprev/fx/"
local tiers = { ... }
if #tiers == 0 then tiers = { "goshiwon", "oneroom", "officetel", "apartment", "penthouse" } end
local codes = {}
for _, tier in tiers do
	local fx = require(FX .. "home_" .. tier)(Vector3, Color3, CFrame)
	local model = R.loadFixture(fx)
	local t0 = os.clock()
	local U = Unit.scan(model)
	local dt = os.clock() - t0
	if not U then print(tier, "SCAN FAILED") continue end
	local rooms = {}
	for _, r in U.rooms do table.insert(rooms, string.format("%s(%s L%d %.0fx%.0f h%.1f)", r.id, r.name, r.level, r.size.X, r.size.Z, r.height)) end
	local kc = {}
	for _, k in U.keeps do kc[k.code] = (kc[k.code] or 0) + 1 end
	local th = 0
	for _ in U.themes do th += 1 end
	print(string.format("== %s scan %.1fms floors %d walls %d ceilings %d solids %d slots %d keeps door%d entry%d interact%d stair%d levels %d themes %d", tier, dt * 1000, #U.floors, #U.walls, #U.ceilings, #U.solids, #U.slots, kc.door or 0, kc.entry or 0, kc.interact or 0, kc.stair or 0, #U.levels, th))
	print("   rooms: " .. table.concat(rooms, ", "))
	local idx = Rules.newIndex()
	local uid = 1
	local placed, failed = 0, {}
	local t1 = os.clock()
	local checks = 0
	-- try a grid of positions in each room for a few floor items, then surface items on top, wall + ceiling
	local samples = { "lv_coffee_round", "pl_monstera", "lt_floor_arc", "st_cube", "rg_jute", "kd_bear_big", "hb_guitar", "lv_ottoman_pouf" }
	for _, r in U.rooms do
		for _, id in samples do
			local b = Catalog.bounds(id)
			local ok, code, arg, fx2
			local tried = 0
			for gx = -2, 2 do
				for gz = -2, 2 do
					local x = r.centre.X + gx * r.size.X / 6
					local z = r.centre.Z + gz * r.size.Z / 6
					tried += 1
					checks += 1
					ok, code, arg, fx2 = Rules.check(U, idx, { i = id, x = x, y = r.floorY, z = z, r = 0 }, {})
					codes[code or "ok"] = (codes[code or "ok"] or 0) + 1
					if ok then break end
				end
				if ok then break end
			end
			if ok then
				Rules.add(idx, { u = uid, i = id, x = fx2.x, y = fx2.y, z = fx2.z, r = fx2.r })
				uid += 1
				placed += 1
			else
				table.insert(failed, r.id .. ":" .. id .. "=" .. tostring(code))
			end
		end
	end
	-- surface items on top of placed coffee tables
	local stacked = 0
	for u, e in idx.items do
		if e.i == "lv_coffee_round" then
			local p = e.pose.Position
			local top = Rules.support(U, idx, "surface", p.X, p.Z, p.Y + 5, nil, nil)
			local ok, code, _, fx2 = Rules.check(U, idx, { i = "lt_table_linen", x = p.X, y = top or p.Y, z = p.Z, r = 0 }, {})
			checks += 1
			if ok then
				Rules.add(idx, { u = uid, i = "lt_table_linen", x = fx2.x, y = fx2.y, z = fx2.z, r = fx2.r })
				uid += 1
				stacked += 1
				local on = Rules.standingOn(idx, u)
				if #on == 0 then print("   !! standingOn found nothing for", u) end
			else
				table.insert(failed, "stack=" .. tostring(code))
			end
		end
	end
	-- wall items: for each wall face near a room, try a frame at 4 studs high
	local wallOk, wallFail = 0, {}
	for wi, w in U.walls do
		if wi > 12 then break end
		for _, f in w.faces do
			local r0 = Geometry.yawFacing(f.n)
			local id = "wl_bridge_art"
			local bb = Catalog.bounds(id)
			local target = f.c + f.n * 0.02
			local rot = CFrame.Angles(0, math.rad(r0), 0)
			local origin = target - rot:VectorToWorldSpace(Vector3.new(0, (bb[2] + bb[5]) / 2, bb[6]))
			local fl = Unit.floorTopAt(U, target.X + f.n.X, target.Z + f.n.Z, target.Y + 4)
			if fl then
				origin = Vector3.new(origin.X, fl + 3.2, origin.Z)
				local ok, code, _, fx2 = Rules.check(U, idx, { i = id, x = origin.X, y = origin.Y, z = origin.Z, r = r0 }, {})
				checks += 1
				if ok then
					wallOk += 1
					Rules.add(idx, { u = uid, i = id, x = fx2.x, y = fx2.y, z = fx2.z, r = fx2.r })
					uid += 1
					break
				else
					wallFail[code] = (wallFail[code] or 0) + 1
				end
			end
		end
	end
	local wf = {}
	for c, n in wallFail do table.insert(wf, c .. "=" .. n) end
	-- ceiling
	local ceilOk = 0
	for _, r in U.rooms do
		local ok, code = Rules.check(U, idx, { i = "lt_chandelier", x = r.centre.X, y = r.floorY + 5, z = r.centre.Z, r = 0 }, {})
		checks += 1
		if ok then ceilOk += 1 else table.insert(failed, r.id .. ":ceil=" .. tostring(code)) end
	end
	local dt2 = os.clock() - t1
	print(string.format("   placed %d stacked %d wall %d (fails %s) ceiling %d/%d  checks %d in %.0fms (%.2fms each)", placed, stacked, wallOk, table.concat(wf, " "), ceilOk, #U.rooms, checks, dt2 * 1000, dt2 * 1000 / checks))
	if #failed > 0 then print("   failed: " .. table.concat(failed, " ")) end
	-- codec round trip of everything placed
	local recs = {}
	for u, e in idx.items do
		local p = e.pose
		table.insert(recs, { u = u, i = e.i, x = p.X, y = p.Y, z = p.Z, r = Geometry.yawOf(p), c = { "ff0000", false }, m = { 2 } })
	end
	local data = Codec.newData()
	data.homes[tier] = { items = recs, n = uid, fin = { rooms = { living = { w = { p = "stripe", a = "112233" } } }, light = "party" } }
	data.storage = { lv_sofa_3seat = 2, bogus = 3 }
	local back = Codec.sanitize(Codec.serialize(data))
	local h = back.homes[tier]
	local bad = 0
	for i, rr in recs do
		local b2 = h.items[i]
		if not b2 or b2.i ~= rr.i or math.abs(b2.x - rr.x) > 0.011 or math.abs(b2.z - rr.z) > 0.011 or math.abs(b2.y - rr.y) > 0.0011 then bad += 1 end
	end
	print(string.format("   codec: %d recs back %d bad %d storage %s light %s", #recs, #h.items, bad, tostring(back.storage.lv_sofa_3seat) .. "/" .. tostring(back.storage.bogus), tostring(h.fin.light)))
end
local cs = {}
for c, n in codes do table.insert(cs, c .. "=" .. n) end
table.sort(cs)
print("codes: " .. table.concat(cs, " "))
