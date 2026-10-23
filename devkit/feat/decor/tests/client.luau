--!nocheck
-- server.luau: the server pipeline (Homes / Actions / Social / Store) on a real home fixture with a fake Host
local B = require("../out/bundle_cli")
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

-- stubs for client services the mock lacks
local Signal = R.Signal
local UIS = game:GetService("UserInputService")
rawget(UIS, "_p").InputChanged = Signal.new()
rawget(UIS, "_p").GamepadEnabled = false
function UIS:GetMouseLocation() return G.Vector2.new(640, 360) end
function UIS:IsKeyDown() return false end
function UIS:GetFocusedTextBox() return nil end
local CAS = game:GetService("ContextActionService")
function CAS:BindActionAtPriority() end
function CAS:UnbindAction() end
local GS = game:GetService("GuiService")
function GS:GetGuiInset() return G.Vector2.new(0, 36), G.Vector2.new(0, 0) end
function GS:IsTenFootInterface() return false end
local cam = workspace.CurrentCamera
pcall(function() rawset(cam, "ViewportPointToRay", function(self, x, y) return { Origin = self.CFrame.Position, Direction = self.CFrame.LookVector } end) end)

-- more client stubs
local Enum = G.Enum
local camp = rawget(workspace.CurrentCamera, "_p")
camp.CameraType = Enum.CameraType.Custom
camp.FieldOfView = 70
camp.CameraSubject = workspace
local origNew = Instance.new
Instance.new = function(cls, parent)
	local i = origNew(cls, parent)
	if cls == "TextButton" or cls == "ImageButton" then
		local p = rawget(i, "_p")
		for _, n in { "MouseButton1Down", "MouseButton1Up", "MouseLeave", "SelectionGained", "SelectionLost", "Activated", "MouseButton1Click", "InputBegan" } do
			if p[n] == nil then p[n] = Signal.new() end
		end
	elseif cls == "Frame" or cls == "ScrollingFrame" or cls == "TextLabel" then
		local p = rawget(i, "_p")
		if p.InputBegan == nil then p.InputBegan = Signal.new() end
	end
	return i
end
local HS = game:GetService("HttpService")
local function jdec(str)
	local pos = 1
	local function ws() pos = string.find(str, "[^%s]", pos) or #str + 1 end
	local val
	local function strv()
		local e = pos + 1
		local out = {}
		while true do
			local c = string.sub(str, e, e)
			if c == '"' then break end
			if c == "\\" then e += 1 c = string.sub(str, e, e) end
			table.insert(out, c)
			e += 1
		end
		pos = e + 1
		return table.concat(out)
	end
	function val()
		ws()
		local c = string.sub(str, pos, pos)
		if c == "{" then
			pos += 1
			local t = {}
			ws()
			if string.sub(str, pos, pos) == "}" then pos += 1 return t end
			while true do
				ws()
				local k = strv()
				ws(); pos += 1
				t[k] = val()
				ws()
				local d = string.sub(str, pos, pos)
				pos += 1
				if d == "}" then return t end
			end
		elseif c == "[" then
			pos += 1
			local t = {}
			ws()
			if string.sub(str, pos, pos) == "]" then pos += 1 return t end
			while true do
				table.insert(t, val())
				ws()
				local d = string.sub(str, pos, pos)
				pos += 1
				if d == "]" then return t end
			end
		elseif c == '"' then
			return strv()
		else
			local num = string.match(str, "^-?[%d%.eE%+%-]+", pos)
			if num then pos += #num return tonumber(num) end
			if string.sub(str, pos, pos + 3) == "true" then pos += 4 return true end
			if string.sub(str, pos, pos + 4) == "false" then pos += 5 return false end
			pos += 4
			return nil
		end
	end
	return val()
end
function HS:JSONDecode(s2) return jdec(s2) end
local placed = 0
for _, id in { "lv_coffee_round", "rg_wave", "lt_floor_arc", "wl_clock", "lt_chandelier", "hb_aquarium", "tc_speaker_tower" } do
	local f = findPose(id)
	if f then
		R.advance(0.2)
		local res = Actions.handle(P, "place", { rid = "c" .. id, i = id, x = f.x, y = f.y, z = f.z, r = f.r })
		if res.ok then placed += 1 end
	end
end
R.advance(0.5)
Actions.handle(P, "finish", { rid = "fx", room = "main", kind = "wall", id = "mural" })
R.advance(0.5)
Actions.handle(P, "finish", { rid = "fy", kind = "light", id = "party" })
local snap = Actions.handle(P, "open", {})
print("placed", placed, "snap", snap.ok, #snap.items)
P:SetAttribute("InHome", 1)
P:SetAttribute("HomeRole", "owner")
local Editor = B.load("C", "Editor")
local Panels = B.load("C", "Panels")
local Effects = B.load("C", "Effects")
local Visit = B.load("C", "Visit")
local Photo = B.load("C", "Photo")
local Unit = Shared.Unit
local U = Unit.scan(model)
local ok, e = pcall(Editor.begin, snap, model, U)
print("begin", ok, e)
ok, e = pcall(Panels.mount, { snap = snap, model = model, U = U, onClose = function() end, onPhoto = function() end })
print("mount", ok, e)
for i = 1, 5 do R.advance(0.1) end
ok, e = pcall(Editor.pick, "lv_chesterfield", "buy", nil)
print("pick", ok, e, Editor.S.mode)
for i = 1, 5 do R.advance(0.1) end
local t0 = os.clock() while os.clock() - t0 < 0.1 do end R.advance(0.05)
print("valid", Editor.S.valid, Editor.S.code, Editor.S.arg, Editor.S.anchor and Editor.S.anchor.x)
for _, fn in { "finish", "goals", "presets", "settings", "help" } do
	local ok2, e2 = pcall(Panels[fn])
	print("panel", fn, ok2, e2)
end
ok, e = pcall(Panels.info, "lv_sofa_3seat", nil)
print("info", ok, e)
Editor.cancel()
local u1 = nil
for u in Editor.S.recs do u1 = u break end
Editor.select(u1, false)
for i = 1, 3 do R.advance(0.1) end
ok, e = pcall(Panels.refreshBar)
print("selected bar", ok, e)
ok, e = pcall(Editor.moveSelected)
print("moveSelected", ok, e, Editor.S.mode)
R.advance(0.1)
Editor.rotate(1)
Editor.lift(1)
R.advance(0.1)
local t1 = os.clock() while os.clock() - t1 < 0.1 do end R.advance(0.05)
print("move valid", Editor.S.valid, Editor.S.code, #Editor.S.members)
Editor.cancel()
local Picker = B.load("C", "Picker")
ok, e = pcall(Picker.item, Panels.gui(), "lv_sofa_3seat", { c = {}, m = {} }, function() end)
print("picker", ok, e)
ok, e = pcall(Picker.color, Panels.gui(), "색", { 200, 100, 50 }, function() end)
print("picker color", ok, e)
ok, e = pcall(Effects.start, function() return model, U end)
print("effects start", ok, e)
model.DecorPlus:GetChildren()[1]:SetAttribute("On", true)
for i = 1, 12 do R.advance(0.6) end
local pg = P:FindFirstChild("PlayerGui")
local sf = pg and pg:FindFirstChild("GwDecorPlusSurfaces")
print("surfaces", sf and #sf:GetChildren())
ok, e = pcall(Visit.mount, { openEditor = function() end, photo = function() end, role = function() return "owner", 1 end, model = function() return model end })
print("visit", ok, e)
ok, e = pcall(Visit.update)
print("visit update", ok, e)

-- full loop: the client's Net talks to the server Actions directly
local Net = B.load("C", "Net")
Net.call = function(a, pl)
	local t0 = os.clock() while os.clock() - t0 < 0.4 do end
	pl = pl or {}
	if pl.rid == nil then pl.rid = tostring(math.random(1, 1e9)) end
	return Actions.handle(P, a, pl)
end
local okB = pcall(Editor.begin, snap, model, U)
local function settle() local t0 = os.clock() while os.clock() - t0 < 0.08 do end R.advance(0.05) end
local f = findPose("pl_snake")
Editor.pick("pl_snake", "buy", nil)
Editor.S.anchor = { i = "pl_snake", x = f.x, y = f.y, z = f.z, r = 0 }
settle()
print("L ghost valid", Editor.S.valid, Editor.S.code)
local before = 0 for _ in Editor.S.recs do before += 1 end
Editor.confirm()
local after = 0 for _ in Editor.S.recs do after += 1 end
print("L confirm", before, "->", after, "undo", #Editor.S.undo, "mode", Editor.S.mode, "server", #H.home.items)
Editor.cancel()
Editor.undo()
local n2 = 0 for _ in Editor.S.recs do n2 += 1 end
print("L undo", n2, "server", #H.home.items, "redo", #Editor.S.redo)
Editor.redo()
local n3 = 0 for _ in Editor.S.recs do n3 += 1 end
print("L redo", n3, "server", #H.home.items)
-- select newest, move it 1 stud, rotate, recolor, duplicate, remove
local newest = 0 for u in Editor.S.recs do newest = math.max(newest, u) end
Editor.select(newest, false)
Editor.moveSelected()
local a = Editor.S.anchor
for _, dx in { 1, -1, 2, -2, 0.5 } do
	Editor.S.anchor = { i = a.i, x = a.x + dx, y = a.y, z = a.z, r = a.r }
	settle()
	if Editor.S.valid then break end
end
print("L move ghost valid", Editor.S.valid, Editor.S.code)
Editor.confirm()
print("L moved", Editor.S.mode, "rec x", Editor.S.recs[newest].x, "server x", H.recs[newest] and H.recs[newest].x, "undo", #Editor.S.undo)
Editor.undo()
print("L move undo server x", H.recs[newest] and H.recs[newest].x)
print("L recolor", Editor.recolor(newest, { "ff0000" }, nil), H.recs[newest].c and H.recs[newest].c[1])
Editor.select(newest, false)
Editor.duplicate()
print("L dup mode", Editor.S.mode, #Editor.S.members)
Editor.cancel()
Editor.select(newest, false)
Editor.removeSelected("store")
print("L removed", Editor.S.recs[newest] == nil, H.recs[newest] == nil, "storage", H.data.storage.pl_snake)
Editor.undo()
print("L remove undo", Editor.S.recs[newest] ~= nil, H.recs[newest] ~= nil)
-- multi select + group move
local ids = {}
for u in Editor.S.recs do table.insert(ids, u) if #ids >= 2 then break end end
Editor.select(ids[1], false)
Editor.select(ids[2], true)
print("L multi", #Editor.selected())
Editor.moveSelected()
print("L group members", Editor.S.members and #Editor.S.members, Editor.S.mode)
local ga = Editor.S.anchor
local done = false
for _, dz in { 0.5, -0.5, 1, -1, 0 } do
	Editor.S.anchor = { i = ga.i, x = ga.x, y = ga.y, z = ga.z + dz, r = ga.r }
	settle()
	if Editor.S.valid then done = true break end
end
print("L group valid", Editor.S.valid, Editor.S.code, Editor.S.arg)
if done then Editor.confirm() print("L group moved", Editor.S.mode, #Editor.S.undo) end
Editor.cancel()
Editor.finish()

Panels.unmount()
ok, e = pcall(Editor.finish)
print("finish", ok, e)
ok, e = pcall(Photo.open, U, false)
print("photo", ok, e)
R.advance(0.2)
ok, e = pcall(Photo.close)
print("photo close", ok, e)
