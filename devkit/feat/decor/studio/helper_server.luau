-- test helper (scratch only): ServerStorage.DecorTest:Invoke(kind, key, a, b) -> "spawned"; result JSON in attribute key
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local SSS = game:GetService("ServerScriptService")

local bf = Instance.new("BindableFunction")
bf.Name = "DecorTest"
bf.Parent = SS

local function gfolder()
	for _, c in SSS:GetChildren() do
		if c:IsA("Folder") and c.Name == "GwangalliGameplay" then
			return c
		end
	end
	return nil
end

local function enc(t)
	local ok, s = pcall(HttpService.JSONEncode, HttpService, t)
	return if ok then s else ("{\"enc\":" .. string.format("%q", tostring(s)) .. "}")
end

local Shared = require(RS:WaitForChild("GwangalliDecorShared"))
local Actions = require(SSS:WaitForChild("GwangalliDecorPlus"):WaitForChild("Actions"))
local Homes = require(SSS.GwangalliDecorPlus:WaitForChild("Homes"))
local Rules, Catalog, Unit, Geometry = Shared.Rules, Shared.Catalog, Shared.Unit, Shared.Geometry

local scen = {}
local log = {}
local function L(s)
	table.insert(log, s)
end

function scen.home(P, tier)
	local f = gfolder()
	local Profiles = require(f.Profiles)
	local Housing = require(f.Housing)
	local Life = require(f.Life)
	local G = require(RS.GwangalliGameplayShared)
	local d = Profiles.get(P)
	for _ = 1, 60 do
		d = Profiles.get(P)
		if d then
			break
		end
		task.wait(0.5)
	end
	if not d then
		return { err = "no profile" }
	end
	G.ledger(d, "bank", 30000000, "test", os.time())
	local rent = nil
	if not d.home then
		local ok, msg = Life.rentHome(P, tier or "oneroom")
		rent = { ok, msg }
	end
	local ok2, why = Housing.enter(P, "phone")
	local model = nil
	for _ = 1, 80 do
		local inst = Housing.instanceOf(P)
		model = inst and inst.model
		if model and model:FindFirstChild("DecorPlus") and Homes.ofOwner(P) then
			break
		end
		task.wait(0.25)
	end
	return { rent = rent, enter = { ok2, why }, model = model and model:GetFullName(), attached = Homes.ofOwner(P) ~= nil, inHome = P:GetAttribute("InHome"), role = P:GetAttribute("HomeRole"), bank = d.bank }
end

-- a valid unit-frame pose for id in room (grid search with the server's own rules)
local function findPose(H, id, roomId)
	local def = Catalog.get(id)
	local U = H.U
	local rooms = {}
	for _, r in U.rooms do
		if not roomId or r.id == roomId then
			table.insert(rooms, r)
		end
	end
	if def.place == "wall" then
		local b = Catalog.bounds(id)
		for _, w in U.walls do
			if not w.window then
				for _, fc in w.faces do
					if fc.hu > (b[4] - b[1]) / 2 + 0.3 then
						local r0 = Geometry.yawFacing(fc.n)
						local rot = CFrame.Angles(0, math.rad(r0), 0)
						local fl = Unit.floorTopAt(U, fc.c.X + fc.n.X * 0.8, fc.c.Z + fc.n.Z * 0.8, fc.c.Y + 3)
						if fl then
							for _, off in { 0, -1.2, 1.2, -2.4, 2.4 } do
								local target = fc.c + fc.u * off + fc.n * 0.02
								local origin = target - rot:VectorToWorldSpace(Vector3.new((b[1] + b[4]) / 2, (b[2] + b[5]) / 2, b[6]))
								local cand = { i = id, x = origin.X, y = fl + 3.0, z = origin.Z, r = r0 }
								local ok, _, _, fx = Rules.check(U, H.idx, cand, {})
								if ok then
									return fx
								end
							end
						end
					end
				end
			end
		end
		return nil
	end
	for _, r in rooms do
		for gx = -3, 3 do
			for gz = -3, 3 do
				local x = r.centre.X + gx * r.size.X / 8
				local z = r.centre.Z + gz * r.size.Z / 8
				local y = r.floorY
				if def.place == "ceiling" then
					y = r.floorY + 6
				end
				local ok, _, _, fx = Rules.check(U, H.idx, { i = id, x = x, y = y, z = z, r = (gx * 45) % 360 }, {})
				if ok then
					return fx
				end
			end
		end
	end
	return nil
end

function scen.run(P)
	log = {}
	local H = Homes.ofOwner(P)
	if not H then
		return { err = "no home" }
	end
	local snap = Actions.handle(P, "open", {})
	L("open ok=" .. tostring(snap.ok) .. " items=" .. tostring(snap.items and #snap.items) .. " rooms=" .. tostring(snap.rooms and #snap.rooms) .. " caps=" .. tostring(snap.caps and snap.caps.items) .. " code=" .. tostring(snap.code))
	local ids = { "lv_sofa_3seat", "lv_coffee_round", "rg_wave", "pl_monstera", "lt_floor_arc", "hb_aquarium", "tc_speaker_tower", "st_wardrobe", "kd_cat_tower", "vr_firepit", "lt_chandelier", "ss_mirrorball", "wl_bridge_art", "tc_tv_frame", "wl_clock", "wl_curtain_linen", "lt_neon_wall" }
	local placed = {}
	local rid = 0
	for _, id in ids do
		local fx = findPose(H, id, nil)
		if fx then
			rid += 1
			local res = Actions.handle(P, "place", { rid = "t" .. rid, i = id, x = fx.x, y = fx.y, z = fx.z, r = fx.r, src = "buy" })
			if res.ok then
				placed[id] = res.rec.u
				L("place " .. id .. " u=" .. res.rec.u .. " price=" .. res.price)
			else
				L("place " .. id .. " FAIL " .. tostring(res.code) .. " " .. tostring(res.msg))
			end
			task.wait(0.15)
		else
			L("place " .. id .. " no pose")
		end
	end
	-- stack a lamp on the coffee table
	local ct = placed.lv_coffee_round and H.recs[placed.lv_coffee_round]
	if ct then
		local top = Rules.support(H.U, H.idx, "surface", ct.x, ct.z, ct.y + 4, nil, nil)
		rid += 1
		local res = Actions.handle(P, "place", { rid = "t" .. rid, i = "lt_table_linen", x = ct.x, y = top, z = ct.z, r = 0, src = "buy" })
		L("stack lamp ok=" .. tostring(res.ok) .. " " .. tostring(res.code) .. " y=" .. tostring(res.rec and res.rec.y) .. " top=" .. tostring(top))
		if res.ok then
			placed.lamp = res.rec.u
		end
		task.wait(0.2)
		-- move the table: the lamp travels along
		local fx = nil
		for _, dx in { 1.5, -1.5, 3, -3 } do
			local ok, _, _, f = Rules.check(H.U, H.idx, { i = ct.i, u = ct.u, x = ct.x + dx, y = ct.y, z = ct.z, r = ct.r }, { ignore = { [ct.u] = true } })
			if ok then
				fx = f
				break
			end
		end
		if fx then
			rid += 1
			local lampBefore = placed.lamp and H.recs[placed.lamp] and H.recs[placed.lamp].x
			local res2 = Actions.handle(P, "move", { rid = "t" .. rid, u = ct.u, x = fx.x, y = fx.y, z = fx.z, r = fx.r })
			L("move table ok=" .. tostring(res2.ok) .. " " .. tostring(res2.code) .. " recs=" .. tostring(res2.recs and #res2.recs) .. " lamp x " .. tostring(lampBefore) .. " -> " .. tostring(placed.lamp and H.recs[placed.lamp] and H.recs[placed.lamp].x))
		end
	end
	task.wait(0.2)
	-- colour
	if placed.lv_sofa_3seat then
		rid += 1
		local res = Actions.handle(P, "color", { rid = "t" .. rid, u = placed.lv_sofa_3seat, c = { "1f3a6e", false, "ffc247" }, m = { 2 } })
		L("color sofa ok=" .. tostring(res.ok) .. " " .. tostring(res.code))
	end
	task.wait(0.2)
	-- remove (store) + restore; sell fresh = refund
	if placed.pl_monstera then
		rid += 1
		local r1 = Actions.handle(P, "remove", { rid = "t" .. rid, uids = { placed.pl_monstera }, how = "store" })
		L("remove monstera ok=" .. tostring(r1.ok) .. " how=" .. tostring(r1.removed and r1.removed[1] and r1.removed[1].how) .. " amount=" .. tostring(r1.removed and r1.removed[1] and r1.removed[1].amount))
		task.wait(0.2)
		rid += 1
		local r2 = Actions.handle(P, "restore", { rid = "t" .. rid, uids = { placed.pl_monstera } })
		L("restore monstera ok=" .. tostring(r2.ok) .. " " .. tostring(r2.code) .. " cost=" .. tostring(r2.cost))
	end
	-- duplicate rid replay = same answer, no double charge
	local bank0 = select(2, require(SSS.GwangalliDecorPlus.Host).balance(P))
	local fxd = findPose(H, "pl_snake", nil)
	if fxd then
		local a = Actions.handle(P, "place", { rid = "dup1", i = "pl_snake", x = fxd.x, y = fxd.y, z = fxd.z, r = 0 })
		task.wait(0.2)
		local b = Actions.handle(P, "place", { rid = "dup1", i = "pl_snake", x = fxd.x, y = fxd.y, z = fxd.z, r = 0 })
		local bank1 = select(2, require(SSS.GwangalliDecorPlus.Host).balance(P))
		L("rid replay same=" .. tostring(a == b) .. " spent=" .. tostring(bank0 - bank1) .. " price=" .. Catalog.price("pl_snake"))
	end
	-- exploits
	local e1 = Actions.handle(P, "place", { rid = "x1", i = "lv_sofa_3seat", x = 0 / 0, y = 0, z = 0, r = 0 })
	local e2 = Actions.handle(P, "place", { rid = "x2", i = "nope", x = 0, y = 0, z = 0, r = 0 })
	local e3 = Actions.handle(P, "move", { rid = "x3", u = 999999, x = 0, y = 0, z = 0, r = 0 })
	local e4 = Actions.handle(P, "place", { rid = "x4", i = "lv_sofa_3seat", x = 5000, y = 0, z = 0, r = 0 })
	L("exploits: nan=" .. tostring(e1.code) .. " id=" .. tostring(e2.code) .. " uid=" .. tostring(e3.code) .. " far=" .. tostring(e4.code))
	-- finish + light preset
	local room = nil
	for id, th in H.U.themes do
		if #th.wall > 0 then
			room = id
			break
		end
	end
	if room then
		local f1 = Actions.handle(P, "finish", { rid = "f1", room = room, kind = "wall", id = "stripe", a = "dfe9f2", b = "ffffff" })
		L("finish wall " .. room .. " ok=" .. tostring(f1.ok) .. " " .. tostring(f1.code) .. " price=" .. tostring(f1.price))
		local f2 = Actions.handle(P, "finish", { rid = "f2", room = room, kind = "floor", id = "herringbone" })
		L("finish floor ok=" .. tostring(f2.ok) .. " " .. tostring(f2.code))
	end
	local f3 = Actions.handle(P, "finish", { rid = "f3", kind = "light", id = "warm" })
	L("light warm ok=" .. tostring(f3.ok) .. " attr=" .. tostring(H.model:GetAttribute("DPLight")))
	-- interactions
	for id, what in { tc_tv_frame = "tv", lt_floor_arc = "lamp", tc_speaker_tower = "music", st_wardrobe = "open", hb_aquarium = "feed" } do
		local u = placed[id]
		if u then
			local b = H.built[u]
			local pr = b and b.prompts[what]
			Homes.interact(H, u, what, P)
			L("interact " .. id .. " " .. what .. " prompt=" .. tostring(pr ~= nil) .. " On=" .. tostring(b and b.model:GetAttribute("On")) .. " Open=" .. tostring(b and b.model:GetAttribute("Open")) .. " lamp=" .. tostring(H.recs[u].on))
			task.wait(0.35)
		end
	end
	-- preset save + plan
	local p1 = Actions.handle(P, "preset", { rid = "p1", op = "save", slot = 1, name = "테스트 배치" })
	L("preset save ok=" .. tostring(p1.ok) .. " " .. tostring(p1.code) .. " name=" .. tostring(p1.name))
	task.wait(1.6)
	local p2 = Actions.handle(P, "preset", { op = "plan", slot = 1 })
	L("preset plan ok=" .. tostring(p2.ok) .. " move=" .. tostring(p2.move) .. " buy=" .. tostring(p2.buy))
	local ph = Actions.handle(P, "photo", { rid = "ph1" })
	L("photo ok=" .. tostring(ph.ok) .. " " .. tostring(ph.code) .. " gain=" .. tostring(ph.gain))
	local folder = H.model:FindFirstChild("DecorPlus")
	local n, parts, lights = 0, 0, 0
	for _, m in folder:GetChildren() do
		n += 1
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			elseif d:IsA("Light") and d.Enabled then
				lights += 1
			end
		end
	end
	local sc = Homes.score(H)
	L(string.format("folder items=%d parts=%d realLights=%d score=%d grade=%s", n, parts, lights, sc.total, sc.grade.name))
	local G = require(RS.GwangalliGameplayShared)
	local f = gfolder()
	local d = require(f.Profiles).get(P)
	L("host decor=" .. tostring(G.homeDecor(d)) .. " comfort=" .. tostring(G.homeComfort and G.homeComfort(d)) .. " value=" .. tostring(G.furnitureValue(d)))
	return { log = log }
end

-- remote-style rebuild: leave + enter -> pieces come back
function scen.rebuild(P)
	local f = gfolder()
	local Housing = require(f.Housing)
	local before = #Homes.ofOwner(P).home.items
	Housing.leave(P)
	task.wait(2)
	local ok = Housing.enter(P, "phone")
	local H = nil
	for _ = 1, 80 do
		H = Homes.ofOwner(P)
		if H and H.model:FindFirstChild("DecorPlus") and #H.model.DecorPlus:GetChildren() > 0 then
			break
		end
		task.wait(0.25)
	end
	return { before = before, after = H and #H.model.DecorPlus:GetChildren() or -1, enter = ok }
end

function scen.cam(P)
	local H = Homes.ofOwner(P)
	local r = H.U.rooms[1]
	local c = H.U.F:PointToWorldSpace(r.centre)
	return { x = c.X, y = c.Y, z = c.Z, sx = r.size.X, sz = r.size.Z }
end

bf.OnInvoke = function(kind, key, a, b)
	local P = Players:GetPlayers()[1]
	task.spawn(function()
		local ok, r = pcall(scen[kind], P, a, b)
		bf:SetAttribute(key, enc(if ok then r else { err = tostring(r), log = log }))
	end)
	return "spawned"
end
