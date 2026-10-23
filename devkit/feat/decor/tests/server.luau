--!nocheck
-- server.luau: the server pipeline (Homes / Actions / Social / Store) on a real home fixture with a fake Host
local B = require("../out/bundle_srv")
local R = B.R
local G = R.G
local Vector3, CFrame, Color3 = G.Vector3, G.CFrame, G.Color3
local Instance = R.env.Instance
local game, workspace = R.env.game, R.env.workspace
local RS = game:GetService("ReplicatedStorage")
local tok = Instance.new("ModuleScript")
tok.Name = "GwangalliDecorShared"
tok.__key = "S/init"
tok.Parent = RS
local Shared = B.load("S")
local Players = game:GetService("Players")
local P = Players:GetPlayers()[1]
function Players:GetPlayerByUserId(id) return if id == 1 then P else nil end
local tier = "oneroom"
local fx = require("../../../bprev/fx/home_" .. tier)(Vector3, Color3, CFrame)
local model = R.loadFixture(fx)
local container = Instance.new("Folder")
container.Name = "GwangalliHomeInstances"
container.Parent = workspace
model.Name = "Home_1"
model:SetAttribute("HomeOwnerId", 1)
model.Parent = container
local inst = { owner = P, ownerId = 1, listingId = "oneroom", tierKey = "oneroom", model = model, staged = false, occupants = { [P] = "owner" } }
local d = { cash = 1000000, bank = 50000000, home = { listingId = "oneroom" } }
local spent = 0
local Host = {}
function Host.ready() return true end
function Host.inside(p) return inst, "owner" end
function Host.ownInside(p) return inst, nil end
function Host.instOfModel(m) return if m == model then inst else nil end
function Host.listingName() return "광안동 풀옵션 원룸" end
function Host.balance() return d.cash, d.bank end
function Host.spend(p, a, label) if d.bank + d.cash < a then return false end if d.bank >= a then d.bank -= a else d.cash -= (a - d.bank) d.bank = 0 end spent += a return true end
function Host.refund(p, a) d.bank += a spent -= a return true end
function Host.canPay() return true end
function Host.changed() end
function Host.notify(p, t, b) end
function Host.addStats(p, delta, reason) print("   stats", reason) end
function Host.profile() return d end
function Host.G() return nil end
function Host.persistent() return false end
local pushes = {}
local function pause(t) local t0 = os.clock() while os.clock() - t0 < t do end end
local oldAdvance = R.advance
R.advance = function(dt) pause(math.min(dt, 2)) oldAdvance(dt) end
local function push(p, payload) table.insert(pushes, payload.kind) end
local Store = B.load("V", "Store")
local Homes = B.load("V", "Homes")
local Social = B.load("V", "Social")
local Actions = B.load("V", "Actions")
Store.load(P)
Homes.init({ Host = Host, Store = Store, push = push, onChanged = function() end })
Social.init({ Host = Host, Store = Store, Homes = Homes, push = push })
Actions.init({ Host = Host, Store = Store, Homes = Homes, Social = Social, push = push })
Homes.start()
for i = 1, 20 do R.advance(0.1) end
local H = Homes.ofOwner(P)
print("attached", H ~= nil, H and #H.U.rooms)
local Rules, Catalog, Geometry, Unit = Shared.Rules, Shared.Catalog, Shared.Geometry, Shared.Unit
local function findPose(id)
	local def = Catalog.get(id)
	local U = H.U
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
								local ok, _, _, f = Rules.check(U, H.idx, { i = id, x = origin.X, y = fl + 3.0, z = origin.Z, r = r0 }, {})
								if ok then return f end
							end
						end
					end
				end
			end
		end
		return nil
	end
	for _, r in U.rooms do
		for gx = -3, 3 do
			for gz = -3, 3 do
				local x, z = r.centre.X + gx * r.size.X / 8, r.centre.Z + gz * r.size.Z / 8
				local y = if def.place == "ceiling" then r.floorY + 6 else r.floorY
				local ok, _, _, f = Rules.check(U, H.idx, { i = id, x = x, y = y, z = z, r = (gx * 45) % 360 }, {})
				if ok then return f end
			end
		end
	end
	return nil
end
local snap = Actions.handle(P, "open", {})
print("open", snap.ok, snap.code, snap.caps and snap.caps.items, #snap.rooms, snap.score and snap.score.total)
local placed = {}
local n = 0
for _, id in { "lv_sofa_3seat", "lv_coffee_round", "rg_wave", "pl_monstera", "lt_floor_arc", "tc_speaker_tower", "st_wardrobe", "lt_chandelier", "wl_bridge_art", "tc_tv_frame", "wl_clock", "wl_curtain_linen", "hb_aquarium" } do
	local f = findPose(id)
	if f then
		n += 1
		R.advance(0.2)
		local res = Actions.handle(P, "place", { rid = "r" .. n, i = id, x = f.x, y = f.y, z = f.z, r = f.r })
		print("place", id, res.ok, res.code, res.msg, res.rec and res.rec.u, res.price)
		if res.ok then placed[id] = res.rec.u end
	else
		print("place", id, "no pose")
	end
end
local ct = placed.lv_coffee_round and H.recs[placed.lv_coffee_round]
if ct then
	local top = Rules.support(H.U, H.idx, "surface", ct.x, ct.z, ct.y + 4)
	R.advance(0.2)
	local res = Actions.handle(P, "place", { rid = "lamp", i = "lt_table_linen", x = ct.x, y = top, z = ct.z, r = 0 })
	print("stack", res.ok, res.code, res.rec and res.rec.y, top)
	local lamp = res.rec and res.rec.u
	for _, dx in { 1.5, -1.5, 3, -3, 0.5, -0.5 } do
		local ok, c = Rules.check(H.U, H.idx, { u = ct.u, i = ct.i, x = ct.x + dx, y = ct.y, z = ct.z, r = ct.r }, { ignore = { [ct.u] = true } })
		if ok then
			R.advance(0.2)
			local lx = lamp and H.recs[lamp].x
			local res2 = Actions.handle(P, "move", { rid = "mv", u = ct.u, x = ct.x + dx, y = ct.y, z = ct.z, r = ct.r })
			print("move table", res2.ok, res2.code, res2.msg, res2.recs and #res2.recs, "lamp x", lx, "->", lamp and H.recs[lamp].x)
			break
		end
	end
end
R.advance(0.2)
print("color", Actions.handle(P, "color", { rid = "c1", u = placed.lv_coffee_round, c = { "1f3a6e", false, "ffc247" }, m = { 2 } }).ok)
R.advance(0.2)
local rm = Actions.handle(P, "remove", { rid = "rm1", uids = { placed.tc_speaker_tower }, how = "store" })
print("remove fresh", rm.ok, rm.removed and rm.removed[1].how, rm.removed and rm.removed[1].amount, "storage", rm.storage and rm.storage.tc_speaker_tower, "bank", d.bank)
R.advance(0.2)
local rs = Actions.handle(P, "restore", { rid = "rs1", uids = { placed.tc_speaker_tower } })
print("restore", rs.ok, rs.code, rs.msg, rs.cost, "bank", d.bank, "built", H.built[placed.tc_speaker_tower] ~= nil)
R.advance(0.2)
local b0 = d.bank
local a1 = Actions.handle(P, "remove", { rid = "dup", uids = { placed.lt_floor_arc }, how = "sell" })
R.advance(0.2)
local a2 = Actions.handle(P, "remove", { rid = "dup", uids = { placed.lt_floor_arc }, how = "sell" })
print("rid replay same", a1 == a2, "refund", d.bank - b0, Catalog.price("lt_floor_arc"))
R.advance(0.2)
print("exploit nan", Actions.handle(P, "place", { rid = "x1", i = "lv_sofa_3seat", x = 0 / 0, y = 0, z = 0, r = 0 }).code)
R.advance(0.2)
print("exploit uid", Actions.handle(P, "move", { rid = "x2", u = 4242, x = 0, y = 0, z = 0, r = 0 }).code)
R.advance(0.2)
print("exploit far", Actions.handle(P, "place", { rid = "x3", i = "lv_sofa_3seat", x = 900, y = 0, z = 0, r = 0 }).code)
R.advance(0.2)
print("exploit batch", Actions.handle(P, "remove", { rid = "x4", uids = "nope", how = "sell" }).code)
local room
for id, th in H.U.themes do if #th.wall > 0 then room = id break end end
R.advance(0.4)
local f1 = Actions.handle(P, "finish", { rid = "f1", room = room, kind = "wall", id = "stripe", a = "dfe9f2" })
print("finish wall", room, f1.ok, f1.code, f1.price, model:GetAttribute("DPFinish"))
R.advance(0.4)
print("finish light", Actions.handle(P, "finish", { rid = "f2", kind = "light", id = "party" }).ok, model:GetAttribute("DPLight"))
R.advance(2)
local p1 = Actions.handle(P, "preset", { rid = "p1", op = "save", slot = 1, name = "" })
print("preset save", p1.ok, p1.code, p1.name)
-- move everything to storage, then load the preset back
R.advance(2)
local all = {}
for u in H.recs do table.insert(all, u) end
local rmall = Actions.handle(P, "remove", { rid = "rmall", uids = all, how = "store" })
print("remove all", rmall.ok, rmall.code, rmall.removed and #rmall.removed, "items", #H.home.items)
R.advance(2)
local plan = Actions.handle(P, "preset", { op = "plan", slot = 1 })
print("plan", plan.ok, plan.move, plan.fromStorage, plan.buy, plan.cost, plan.finCost, plan.leftover)
R.advance(2)
local ld = Actions.handle(P, "preset", { rid = "ld", op = "load", slot = 1, buy = true })
print("load", ld.ok, ld.code, ld.msg, ld.placed, ld.skipped, ld.spent, "items", #H.home.items)
R.advance(1)
print("interact tv"); local tvu = nil
for u, r in H.recs do if r.i == "tc_tv_frame" then tvu = u end end
if tvu then Homes.interact(H, tvu, "tv", P) print("  On", H.built[tvu].model:GetAttribute("On")) end
local sc = Homes.score(H)
print("score", sc.total, sc.grade.name, "spent", spent, "pushes", table.concat(pushes, ","))
local folder = model:FindFirstChild("DecorPlus")
print("folder kids", #folder:GetChildren(), "badges", (function() local t = {} for k in H.data.badges do table.insert(t, k) end return table.concat(t, ",") end)())
local ser = Shared.Codec.serialize(H.data)
print("blob homes", #ser.homes.oneroom.items, "example", ser.homes.oneroom.items[1])
