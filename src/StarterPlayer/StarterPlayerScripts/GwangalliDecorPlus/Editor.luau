--!strict
-- GwangalliDecorPlus/Editor: the 자유 배치 editing core on the client — ghost placement with live Rules
-- tint, grid / rotation snap, lift (Q/E), stacking on surfaces, wall + ceiling mounting, selection and
-- multi-select (Shift+클릭 / 다중 선택), move / group move (stacked pieces travel along), duplicate,
-- 창고 / 팔기, undo / redo, 스타일 세트 cart. PC mouse + keys, touch (drag, tap, long-press, pinch) and
-- gamepad (centre cursor) all drive the same actions. The server re-validates everything.
--   Editor.begin(snapshot, model) / Editor.finish() / Editor.isOpen()
--   Editor.pick(id, src, look?) / Editor.confirm() / Editor.cancel() / Editor.rotate(dir) / Editor.lift(dir)
--   Editor.cycleGrid() / Editor.setRotStep(n) / Editor.setOverlap(b) / Editor.setMulti(b) / Editor.moveSelected()
--   Editor.duplicate() / Editor.removeSelected(how) / Editor.undo() / Editor.redo() / Editor.recolor(u, c, m)
--   Editor.onChange(fn)  (fires with a reason string; the panels redraw from Editor.S)

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("GwangalliDecorShared"))
local Config, Catalog, Rules, Spec, Geometry, Unit, Text = Shared.Config, Shared.Catalog, Shared.Rules, Shared.Spec, Shared.Geometry, Shared.Unit, Shared.Text

local Net = require(script.Parent:WaitForChild("Net"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local player = Players.LocalPlayer

local Editor = {}

local S: any = {
	open = false,
	mode = "browse", -- browse | place | move
	settings = { grid = Config.GRID_DEFAULT, rot = Config.ROT_DEFAULT, cut = true, overlap = false },
	sel = {},
	selOrder = {},
	multi = false,
	undo = {},
	redo = {},
	busy = false,
}
Editor.S = S

local listeners: { (string) -> () } = {}
function Editor.onChange(fn: (string) -> ()): () -> ()
	table.insert(listeners, fn)
	return function()
		local i = table.find(listeners, fn)
		if i then
			table.remove(listeners, i)
		end
	end
end
local function changed(why: string)
	for _, fn in listeners do
		task.spawn(fn, why)
	end
end

local ghostFolder: Folder? = nil
local conns: { RBXScriptConnection } = {}
local hiddenParts: { [BasePart]: number } = {}
local promptStates: { [ProximityPrompt]: boolean } = {}
local selBoxes: { [number]: Instance } = {}

-------------------------------------------------------------------------------------------------
-- Records (client mirror of the server state)
-------------------------------------------------------------------------------------------------
local function rebuildIndex()
	S.idx = Rules.newIndex()
	for _, rec in S.recs do
		Rules.add(S.idx, rec)
	end
end

local function applyRecs(list: { any }?)
	if not list then
		return
	end
	for _, r in list do
		S.recs[r.u] = r
		Rules.add(S.idx, r)
	end
end

local function dropUids(uids: { number })
	for _, u in uids do
		S.recs[u] = nil
		Rules.remove(S.idx, u)
	end
end

function Editor.counts(): any
	local items, parts = 0, 0
	for _, rec in S.recs do
		items += 1
		parts += Catalog.partCount(rec.i)
	end
	return { items = items, parts = parts }
end

local function itemModel(u: number): Model?
	local folder = S.model and S.model:FindFirstChild(Config.FOLDER_NAME)
	local m = folder and folder:FindFirstChild("Item_" .. tostring(u))
	return if m and m:IsA("Model") then m else nil
end
Editor.itemModel = itemModel

-------------------------------------------------------------------------------------------------
-- Ghosts
-------------------------------------------------------------------------------------------------
local function clearGhosts()
	if S.members then
		for _, mb in S.members do
			if mb.ghost then
				mb.ghost:Destroy()
			end
		end
	end
	if S.plate then
		S.plate:Destroy()
		S.plate = nil
	end
	if S.gridLines then
		for _, l in S.gridLines do
			l:Destroy()
		end
		S.gridLines = nil
	end
	S.members = nil
end

local function hideModel(u: number, on: boolean)
	local m = itemModel(u)
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			if on then
				hiddenParts[d] = d.LocalTransparencyModifier
				d.LocalTransparencyModifier = 1
			elseif hiddenParts[d] ~= nil then
				d.LocalTransparencyModifier = 0
				hiddenParts[d] = nil
			end
		end
	end
end

local function tint(model: Model, ok: boolean)
	local col = if ok then Color3.fromRGB(90, 220, 140) else Color3.fromRGB(235, 80, 80)
	local hl = model:FindFirstChild("DPHighlight")
	if hl then
		(hl :: any).FillColor = col
		;(hl :: any).OutlineColor = col
	else
		local box = model:FindFirstChild("DPGhostBox")
		if box then
			(box :: any).Color3 = col
		end
	end
end

local function makeGhost(id: string, look: any?): Model?
	local spec = Catalog.spec(id, look and look.c, look and look.m)
	if not spec then
		return nil
	end
	local m = Spec.build(spec, CFrame.new(0, -500, 0), nil, "Ghost", { ghost = true })
	local ok = pcall(function()
		local hl = Instance.new("Highlight")
		hl.Name = "DPHighlight"
		hl.FillTransparency = 0.65
		hl.OutlineTransparency = 0.1
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = m
	end)
	if not ok then
		local box = Instance.new("SelectionBox")
		box.Name = "DPGhostBox"
		box.LineThickness = 0.05
		box.Adornee = m
		box.Parent = m
	end
	m.Parent = ghostFolder
	return m
end

local function ensurePlate(): Part
	if not S.plate then
		local p = Instance.new("Part")
		p.Name = "DPPlate"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Transparency = 0.55
		p.Parent = ghostFolder
		S.plate = p
	end
	return S.plate
end

local function updateGrid(centre: Vector3?, kind: string?)
	local step = S.settings.grid
	if not centre or step <= 0 or kind == "wall" or kind == "ceiling" then
		if S.gridLines then
			for _, l in S.gridLines do
				l.Transparency = 1
			end
		end
		return
	end
	local n = 7
	if not S.gridLines then
		S.gridLines = {}
		for i = 1, n * 2 do
			local l = Instance.new("Part")
			l.Name = "DPGrid"
			l.Anchored = true
			l.CanCollide = false
			l.CanQuery = false
			l.CanTouch = false
			l.CastShadow = false
			l.Material = Enum.Material.Neon
			l.Color = Color3.fromRGB(61, 214, 245)
			l.Parent = ghostFolder
			S.gridLines[i] = l
		end
	end
	local spacing = math.max(step, 0.5)
	local half = (n - 1) / 2 * spacing
	local cx = math.floor(centre.X / spacing + 0.5) * spacing
	local cz = math.floor(centre.Z / spacing + 0.5) * spacing
	for i = 0, n - 1 do
		local off = -half + i * spacing
		local a = S.gridLines[i + 1]
		local b = S.gridLines[n + i + 1]
		a.Size = Vector3.new(0.03, 0.01, half * 2)
		b.Size = Vector3.new(half * 2, 0.01, 0.03)
		a.CFrame = S.U.F * CFrame.new(cx + off, centre.Y + 0.012, cz)
		b.CFrame = S.U.F * CFrame.new(cx, centre.Y + 0.012, cz + off)
		local t = 0.55 + math.abs(off) / (half + 0.01) * 0.4
		a.Transparency = t
		b.Transparency = t
	end
end

-------------------------------------------------------------------------------------------------
-- Aim (pointer -> unit-frame hit)
-------------------------------------------------------------------------------------------------
local function movingSet(): { [number]: boolean }
	local out = {}
	if S.members then
		for _, mb in S.members do
			if mb.u then
				out[mb.u] = true
			end
		end
	end
	return out
end

local function skipHit(inst: Instance, moving: { [number]: boolean }): boolean
	if inst.Name == "DPHit" or not inst:IsA("BasePart") then
		return true
	end
	local p = inst :: BasePart
	if p.LocalTransparencyModifier >= 0.8 or p.Transparency >= 0.95 then
		return true
	end
	local item = inst:FindFirstAncestorWhichIsA("Model")
	while item and item.Parent and item.Parent.Name ~= Config.FOLDER_NAME do
		item = item.Parent:FindFirstAncestorWhichIsA("Model")
	end
	if item then
		local u = item:GetAttribute("DecorUid")
		if type(u) == "number" and moving[u] then
			return true
		end
	end
	return false
end

-- hit point + normal in the unit frame
local function aim(screen: Vector2): (Vector3?, Vector3?)
	if not S.model then
		return nil, nil
	end
	local origin, dir = Camera.ray(screen)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { S.model }
	local moving = movingSet()
	local o = origin
	local d = dir.Unit * 600
	for _ = 1, 10 do
		local r = workspace:Raycast(o, d, params)
		if not r then
			return nil, nil
		end
		if not skipHit(r.Instance, moving) then
			return S.U.F:PointToObjectSpace(r.Position), S.U.F:VectorToObjectSpace(r.Normal)
		end
		o = r.Position + dir.Unit * 0.02
		d = dir.Unit * (600 - (o - origin).Magnitude)
		if d.Magnitude < 1 then
			return nil, nil
		end
	end
	return nil, nil
end

-- the placed piece under the pointer
local function pickItem(screen: Vector2): number?
	local folder = S.model and S.model:FindFirstChild(Config.FOLDER_NAME)
	if not folder then
		return nil
	end
	local origin, dir = Camera.ray(screen)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local o = origin
	for _ = 1, 6 do
		local r = workspace:Raycast(o, dir.Unit * 600, params)
		if not r then
			return nil
		end
		local m = r.Instance:FindFirstAncestorWhichIsA("Model")
		while m and m.Parent ~= folder do
			m = m.Parent and m.Parent:FindFirstAncestorWhichIsA("Model")
		end
		local skip = (r.Instance :: BasePart).LocalTransparencyModifier >= 0.8
		if m and not skip then
			local u = m:GetAttribute("DecorUid")
			if type(u) == "number" and S.recs[u] then
				return u
			end
		end
		o = r.Position + dir.Unit * 0.02
	end
	return nil
end
Editor.pickAt = pickItem

local function snapV(v: number): number
	local g = S.settings.grid
	if g <= 0 then
		return Geometry.round(v, 0.01)
	end
	return Geometry.snap(v, g)
end

-- candidate pose of a piece of `id` from a unit-frame hit, keeping yaw / lift
local function poseFromHit(id: string, P: Vector3, N: Vector3, ignore: { [number]: boolean }): any?
	local def = Catalog.get(id)
	if not def then
		return nil
	end
	local b = Catalog.bounds(id)
	local kind = def.place
	local lift = S.lift or 0
	if kind == "wall" then
		if math.abs(N.Y) > 0.5 then
			return nil
		end
		local n = Vector3.new(N.X, 0, N.Z).Unit
		local r = Geometry.yawFacing(n)
		local u = Vector3.new(-n.Z, 0, n.X)
		local t = P:Dot(u)
		local tp = P + u * (snapV(t) - t)
		local cy = (b[2] + b[5]) / 2
		local ty = snapV(P.Y + lift)
		local target = Vector3.new(tp.X, ty, tp.Z) + n * Config.WALL_GAP
		local rot = CFrame.Angles(0, math.rad(r), 0)
		local origin = target - rot:VectorToWorldSpace(Vector3.new((b[1] + b[4]) / 2, cy, b[6]))
		return { i = id, x = origin.X, y = origin.Y, z = origin.Z, r = r }
	elseif kind == "ceiling" then
		local x, z = snapV(P.X), snapV(P.Z)
		local ft = Unit.floorTopAt(S.U, x, z, P.Y + 0.5) or P.Y
		local ceil = Unit.ceilingAbove(S.U, x, z, ft + 0.5) or (P.Y + 7)
		return { i = id, x = x, y = ceil - b[5] - 0.01, z = z, r = S.yaw or 0 }
	end
	local p = P
	if math.abs(N.Y) < 0.5 then
		local hx = math.max(b[4] - b[1], b[6] - b[3]) / 2
		p = P + Vector3.new(N.X, 0, N.Z).Unit * (hx + 0.05)
	end
	local x, z = snapV(p.X), snapV(p.Z)
	local top = Rules.support(S.U, S.idx, kind, x, z, p.Y + 0.08, ignore, nil)
	local y = (top or p.Y) + (if kind == "rug" then 0 else lift)
	return { i = id, x = x, y = y, z = z, r = S.yaw or 0 }
end

-------------------------------------------------------------------------------------------------
-- Validation + ghost pose
-------------------------------------------------------------------------------------------------
local lastCheck = 0
local pending = false

local function memberPoses(anchor: any): { any }
	local out = {}
	local base = Geometry.pose(anchor.x, anchor.y, anchor.z, anchor.r)
	for i, mb in S.members do
		if i == 1 then
			table.insert(out, { u = mb.u, i = mb.i, x = anchor.x, y = anchor.y, z = anchor.z, r = anchor.r })
		else
			local cf = base * mb.rel
			table.insert(out, { u = mb.u, i = mb.i, x = cf.X, y = cf.Y, z = cf.Z, r = Geometry.yawOf(cf) })
		end
	end
	return out
end

local function validate()
	if not S.members or not S.anchor then
		return
	end
	local list = memberPoses(S.anchor)
	local ok, code, arg, fixed
	-- people standing in the home (the server refuses to place a piece on someone)
	local people = {}
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local q = S.U.F:PointToObjectSpace(hrp.Position)
			if q.X > S.U.lo.X - 2 and q.X < S.U.hi.X + 2 and q.Z > S.U.lo.Z - 2 and q.Z < S.U.hi.Z + 2 and q.Y > S.U.lo.Y - 4 and q.Y < S.U.hi.Y + 20 then
				table.insert(people, q)
			end
		end
	end
	local opts = { overlap = S.settings.overlap, caps = S.caps, counts = Editor.counts(), isNew = S.mode == "place", people = people }
	if #list == 1 then
		if S.mode == "move" then
			opts.ignore = { [list[1].u] = true }
		end
		local f
		ok, code, arg, f = Rules.check(S.U, S.idx, list[1], opts)
		fixed = if f then { f } else nil
	else
		ok, code, arg, fixed = Rules.checkGroup(S.U, S.idx, list, opts)
	end
	S.valid = ok
	S.code, S.arg = code, arg
	S.fixed = fixed
	S.list = list
	local final = if ok and fixed then fixed else list
	for i, mb in S.members do
		local f = final[i]
		if mb.ghost and f then
			mb.ghost:PivotTo(S.U.F * Geometry.pose(f.x, f.y, f.z, f.r))
			tint(mb.ghost, ok)
		end
	end
	-- footprint plate under the anchor
	local f1 = final[1]
	if f1 then
		local def = Catalog.get(S.members[1].i)
		local cf, half = Catalog.box(S.members[1].i)
		local pose = S.U.F * Geometry.pose(f1.x, f1.y, f1.z, f1.r)
		local plate = ensurePlate()
		plate.Color = if ok then Color3.fromRGB(90, 220, 140) else Color3.fromRGB(235, 80, 80)
		if def and def.place == "wall" then
			local b = Catalog.bounds(S.members[1].i)
			plate.Size = Vector3.new(half.X * 2 + 0.1, half.Y * 2 + 0.1, 0.03)
			plate.CFrame = pose * CFrame.new(cf.Position.X, cf.Position.Y, b[6] + 0.01)
		elseif def and def.place == "ceiling" then
			plate.Size = Vector3.new(half.X * 2 + 0.1, 0.03, half.Z * 2 + 0.1)
			plate.CFrame = pose * CFrame.new(cf.Position.X, cf.Position.Y + half.Y + 0.02, cf.Position.Z)
		else
			plate.Size = Vector3.new(half.X * 2 + 0.06, 0.03, half.Z * 2 + 0.06)
			plate.CFrame = pose * CFrame.new(cf.Position.X, 0.016, cf.Position.Z)
		end
		updateGrid(Vector3.new(f1.x, f1.y, f1.z), def and def.place)
	end
	changed("status")
end

local function requestCheck()
	pending = true
end

-------------------------------------------------------------------------------------------------
-- Modes
-------------------------------------------------------------------------------------------------
local function clearSelection()
	for u, b in selBoxes do
		b:Destroy()
		selBoxes[u] = nil
	end
	S.sel = {}
	S.selOrder = {}
end

local function selectBox(u: number, on: boolean)
	if on and not selBoxes[u] then
		local m = itemModel(u)
		if m then
			local b = Instance.new("SelectionBox")
			b.Name = "DPSel"
			b.LineThickness = 0.06
			b.Color3 = Color3.fromRGB(61, 214, 245)
			b.SurfaceTransparency = 0.88
			b.SurfaceColor3 = Color3.fromRGB(61, 214, 245)
			b.Adornee = m
			b.Parent = ghostFolder
			selBoxes[u] = b
		end
	elseif not on and selBoxes[u] then
		selBoxes[u]:Destroy()
		selBoxes[u] = nil
	end
end

function Editor.select(u: number?, additive: boolean?)
	if S.mode ~= "browse" then
		return
	end
	if not additive then
		clearSelection()
	end
	if u then
		if S.sel[u] and additive then
			S.sel[u] = nil
			local i = table.find(S.selOrder, u)
			if i then
				table.remove(S.selOrder, i)
			end
			selectBox(u, false)
		else
			S.sel[u] = true
			table.insert(S.selOrder, u)
			selectBox(u, true)
		end
	end
	changed("selection")
end

function Editor.selected(): { number }
	return table.clone(S.selOrder)
end

local function startMembers(list: { any }, anchorPose: any)
	clearGhosts()
	S.members = {}
	local base = Geometry.pose(anchorPose.x, anchorPose.y, anchorPose.z, anchorPose.r)
	for i, e in list do
		local mb = { u = e.u, i = e.i, look = e.look, src = e.src }
		mb.ghost = makeGhost(e.i, e.look)
		if i > 1 then
			mb.rel = base:Inverse() * Geometry.pose(e.x, e.y, e.z, e.r)
		end
		table.insert(S.members, mb)
	end
	S.anchor = { i = list[1].i, x = anchorPose.x, y = anchorPose.y, z = anchorPose.z, r = anchorPose.r }
	S.yaw = anchorPose.r
	requestCheck()
end

-- new piece from the catalog / 창고
function Editor.pick(id: string, src: string?, look: any?)
	if not S.open or not Catalog.get(id) then
		return
	end
	Editor.cancel(true)
	clearSelection()
	S.mode = "place"
	S.lift = 0
	S.pickSrc = src or "buy"
	S.pickLook = look
	local P = Camera.focus()
	local def = Catalog.get(id)
	local start = { i = id, x = P.X, y = P.Y, z = P.Z, r = S.yaw or 0 }
	if def.place == "ceiling" then
		local ceil = Unit.ceilingAbove(S.U, P.X, P.Z, P.Y + 0.5) or (P.Y + 7.5)
		start.y = ceil - Catalog.bounds(id)[5] - 0.01
	end
	startMembers({ { i = id, look = look, src = src, x = start.x, y = start.y, z = start.z, r = start.r } }, start)
	S.lastAimOk = false
	changed("mode")
end

-- move the selection (single: stacked pieces travel along; multi: group move)
function Editor.moveSelected()
	if S.mode ~= "browse" or #S.selOrder == 0 then
		return
	end
	local uids = table.clone(S.selOrder)
	local seen = {}
	for _, u in uids do
		seen[u] = true
	end
	-- pieces standing on the selection come along
	local i = 1
	while i <= #uids and #uids < Config.BATCH_MAX do
		for _, d in Rules.standingOn(S.idx, uids[i]) do
			if not seen[d] then
				seen[d] = true
				table.insert(uids, d)
			end
		end
		i += 1
	end
	local list = {}
	for _, u in uids do
		local r = S.recs[u]
		if r then
			table.insert(list, { u = u, i = r.i, look = { c = r.c, m = r.m }, x = r.x, y = r.y, z = r.z, r = r.r })
		end
	end
	if #list == 0 then
		return
	end
	S.moveFrom = {}
	for _, e in list do
		S.moveFrom[e.u] = { x = e.x, y = e.y, z = e.z, r = e.r }
		hideModel(e.u, true)
	end
	S.mode = "move"
	S.moveMulti = #S.selOrder > 1
	local a = S.recs[list[1].u]
	S.lift = 0
	local top = Rules.support(S.U, S.idx, Catalog.get(a.i).place, a.x, a.z, a.y + 0.05, { [a.u] = true }, nil)
	if top and a.y - top > 0.05 then
		S.lift = a.y - top
	end
	startMembers(list, { x = a.x, y = a.y, z = a.z, r = a.r })
	clearSelection()
	changed("mode")
end

function Editor.cancel(silent: boolean?)
	if S.mode == "move" and S.members then
		for _, mb in S.members do
			if mb.u then
				hideModel(mb.u, false)
			end
		end
	end
	clearGhosts()
	S.mode = "browse"
	S.anchor = nil
	S.valid = nil
	S.code = nil
	if not silent then
		changed("mode")
	end
end

local function pushUndo(entry: any)
	table.insert(S.undo, entry)
	while #S.undo > Config.UNDO_MAX do
		table.remove(S.undo, 1)
	end
	S.redo = {}
end

local function serverFail(res: any)
	Ui.toast("❌ " .. (res.msg or Text.reason(res.code)), "bad")
	if res.code == "insufficient" then
		changed("insufficient")
	end
end

local function setBalance(res: any)
	if res.balance then
		S.balance = res.balance
	end
	if res.storage then
		S.storage = res.storage
	end
end

local function placeOne(e: any, src: string, look: any?): any
	return Net.call("place", { i = e.i, x = e.x, y = e.y, z = e.z, r = e.r, c = look and look.c, m = look and look.m, src = src, ov = S.settings.overlap })
end

function Editor.confirm()
	if S.busy or not S.members or not S.anchor then
		return
	end
	validate()
	if not S.valid then
		Ui.toast("❌ " .. Text.reason(S.code, S.arg), "bad")
		return
	end
	S.busy = true
	local fixed = S.fixed
	if S.mode == "place" then
		local placedU = {}
		local stopped = false
		for i, mb in S.members do
			local f = fixed[i]
			local src = if (S.storage and (S.storage[mb.i] or 0) > 0) and (mb.src == "storage" or S.pickSrc == "storage") then "storage" else "buy"
			local res = placeOne({ i = mb.i, x = f.x, y = f.y, z = f.z, r = f.r }, src, mb.look)
			if res.ok then
				applyRecs({ res.rec })
				res.rec.src = res.src
				table.insert(placedU, res.rec.u)
				if res.fresh and res.fresh > 0 then
					S.fresh[res.rec.u] = os.clock() + res.fresh
				end
				setBalance(res)
				local def = Catalog.get(mb.i)
				if res.price and res.price > 0 then
					Ui.toast(Text.fmt(Text.TOAST.placedPaid, Text.josa(def.name, "을", "를"), Text.won(res.price)), "good")
				else
					Ui.toast(Text.fmt(Text.TOAST.placed, Text.josa(def.name, "을", "를")), "good")
				end
				if res.warn then
					Ui.toast("💡 " .. res.warn)
				end
			else
				serverFail(res)
				stopped = true
				break
			end
		end
		if #placedU > 0 then
			pushUndo({ op = "place", uids = placedU, src = S.pickSrc })
			S.counts = Editor.counts()
			changed("placed")
		end
		S.busy = false
		if not stopped then
			-- 연속 배치: keep the ghost of the same piece (cart advances to the next one)
			if S.cart then
				S.cart.i += 1
				local nextId = S.cart.set.items[S.cart.i]
				if nextId then
					local inStore = S.storage and (S.storage[nextId] or 0) > 0
					Editor.pick(nextId, if inStore then "storage" else "buy", nil)
					return
				else
					Ui.toast(Text.UI.setDone, "gold")
					Net.call("set", { id = S.cart.set.id })
					S.cart = nil
					Editor.cancel()
					return
				end
			end
			if #S.members > 1 or (S.pickSrc == "storage" and not (S.storage and (S.storage[S.members[1].i] or 0) > 0)) then
				Editor.cancel()
			end
		end
		return
	elseif S.mode == "move" then
		local res
		local list = {}
		for i, mb in S.members do
			local f = fixed[i]
			table.insert(list, { u = mb.u, x = f.x, y = f.y, z = f.z, r = f.r })
		end
		if S.moveMulti then
			res = Net.call("moveMany", { list = list, ov = S.settings.overlap })
		else
			local a = list[1]
			res = Net.call("move", { u = a.u, x = a.x, y = a.y, z = a.z, r = a.r, ov = S.settings.overlap })
		end
		S.busy = false
		if res.ok then
			local entry = { op = "move", list = {} }
			for _, r in res.recs do
				local from = S.moveFrom and S.moveFrom[r.u]
				if from then
					table.insert(entry.list, { u = r.u, from = from, to = { x = r.x, y = r.y, z = r.z, r = r.r } })
				end
			end
			applyRecs(res.recs)
			pushUndo(entry)
			local ids = {}
			for _, mb in S.members do
				table.insert(ids, mb.u)
			end
			Editor.cancel(true)
			S.mode = "browse"
			for _, u in ids do
				Editor.select(u, true)
			end
			changed("moved")
		else
			serverFail(res)
		end
	end
end

function Editor.rotate(dir: number)
	local step = S.settings.rot
	if S.mode == "browse" and #S.selOrder > 0 then
		-- quick turn of the selection in place
		Editor.moveSelected()
		if S.mode ~= "move" then
			return
		end
		S.anchor.r = Geometry.wrapYaw(S.anchor.r + dir * step)
		S.yaw = S.anchor.r
		validate()
		Editor.confirm()
		return
	end
	if not S.anchor then
		return
	end
	local def = Catalog.get(S.anchor.i)
	if def and def.place == "wall" then
		return -- a wall piece always faces out of its wall
	end
	local r = S.anchor.r + dir * step
	S.anchor.r = if step > 1 then Geometry.snapYaw(r, step) else Geometry.wrapYaw(r)
	S.yaw = S.anchor.r
	requestCheck()
end

function Editor.lift(dir: number)
	if not S.anchor then
		return
	end
	local def = Catalog.get(S.anchor.i)
	if not def or def.place == "rug" or def.place == "ceiling" then
		return
	end
	S.lift = math.clamp((S.lift or 0) + dir * Config.LIFT_STEP, if def.place == "wall" then -6 else 0, Config.MAX_LIFT)
	S.anchor.y += dir * Config.LIFT_STEP
	if def.place ~= "wall" then
		local top = Rules.support(S.U, S.idx, def.place, S.anchor.x, S.anchor.z, S.anchor.y - dir * Config.LIFT_STEP + 0.08, movingSet(), nil)
		if top then
			S.anchor.y = top + S.lift
		end
	end
	requestCheck()
	changed("lift")
end

function Editor.cycleGrid()
	local steps = Config.GRID_STEPS
	local i = table.find(steps, S.settings.grid) or 1
	S.settings.grid = steps[(i % #steps) + 1]
	Ui.toast("📐 " .. (if S.settings.grid == 0 then Text.UI.gridOff else (Text.UI.grid .. " " .. tostring(S.settings.grid))))
	requestCheck()
	changed("settings")
end

function Editor.setRotStep(n: number)
	S.settings.rot = n
	changed("settings")
end

function Editor.setOverlap(b: boolean)
	S.settings.overlap = b
	requestCheck()
	changed("settings")
end

function Editor.setMulti(b: boolean)
	S.multi = b
	changed("settings")
end

-- 하나 더: the same piece with the same look, as a new ghost (group duplicate for a multi-selection)
function Editor.duplicate()
	if S.mode ~= "browse" or #S.selOrder == 0 then
		return
	end
	local list = {}
	local lo, hi = math.huge, -math.huge
	for _, u in S.selOrder do
		local r = S.recs[u]
		if r then
			local b = Catalog.bounds(r.i)
			lo = math.min(lo, r.x + b[1])
			hi = math.max(hi, r.x + b[4])
			table.insert(list, { i = r.i, look = { c = r.c, m = r.m }, x = r.x, y = r.y, z = r.z, r = r.r, src = if S.storage and (S.storage[r.i] or 0) > 0 then "storage" else "buy" })
		end
	end
	if #list == 0 then
		return
	end
	local off = math.max(1, hi - lo + 0.5)
	for _, e in list do
		e.x += off
	end
	clearSelection()
	S.mode = "place"
	S.pickSrc = list[1].src
	S.lift = 0
	startMembers(list, { x = list[1].x, y = list[1].y, z = list[1].z, r = list[1].r })
	changed("mode")
end

function Editor.removeSelected(how: string)
	if S.busy or S.mode ~= "browse" or #S.selOrder == 0 then
		return
	end
	S.busy = true
	local res = Net.call("remove", { uids = table.clone(S.selOrder), how = how })
	S.busy = false
	if not res.ok then
		serverFail(res)
		return
	end
	local uids = {}
	local total, refund = 0, 0
	for _, r in res.removed do
		table.insert(uids, r.u)
		if r.how == "refund" then
			refund += r.amount
		else
			total += r.amount
		end
	end
	local howUsed = how
	dropUids(uids)
	clearSelection()
	setBalance(res)
	pushUndo({ op = "remove", uids = uids, how = howUsed })
	if refund > 0 then
		Ui.toast(Text.fmt(Text.TOAST.refunded, Text.won(refund)), "good")
	end
	if how == "sell" and total > 0 then
		Ui.toast(Text.fmt(Text.TOAST.sold, Text.won(total)), "gold")
	elseif how == "store" and refund == 0 then
		Ui.toast(Text.TOAST.stored)
	end
	changed("removed")
end

function Editor.recolor(u: number, c: any, m: any): boolean
	local r = S.recs[u]
	if not r or S.busy then
		return false
	end
	S.busy = true
	local from = { c = r.c, m = r.m }
	local res = Net.call("color", { u = u, c = c, m = m })
	S.busy = false
	if not res.ok then
		if res.code ~= "same" then
			serverFail(res)
		end
		return false
	end
	applyRecs({ res.rec })
	pushUndo({ op = "color", u = u, from = from, to = { c = res.rec.c, m = res.rec.m } })
	Ui.toast(Text.TOAST.colored)
	-- the selection box follows the rebuilt model
	task.delay(0.3, function()
		if S.sel[u] then
			selectBox(u, false)
			selectBox(u, true)
		end
	end)
	changed("colored")
	return true
end

-------------------------------------------------------------------------------------------------
-- Undo / redo
-------------------------------------------------------------------------------------------------
local function runOp(entry: any, backwards: boolean): boolean
	local op = entry.op
	if op == "place" then
		if backwards then
			local res = Net.call("remove", { uids = entry.uids, how = if entry.src == "storage" then "store" else "sell" })
			if not res.ok then
				serverFail(res)
				return false
			end
			local uids = {}
			for _, r in res.removed do
				table.insert(uids, r.u)
			end
			dropUids(uids)
			entry.uids = uids
			setBalance(res)
		else
			local res = Net.call("restore", { uids = entry.uids, ov = true })
			if not res.ok then
				serverFail(res)
				return false
			end
			applyRecs(res.recs)
			setBalance(res)
		end
	elseif op == "move" then
		local list = {}
		for _, e in entry.list do
			local p = if backwards then e.from else e.to
			table.insert(list, { u = e.u, x = p.x, y = p.y, z = p.z, r = p.r })
		end
		local res = Net.call("moveMany", { list = list, ov = true })
		if not res.ok then
			serverFail(res)
			return false
		end
		applyRecs(res.recs)
	elseif op == "color" then
		local look = if backwards then entry.from else entry.to
		local res = Net.call("color", { u = entry.u, c = look.c, m = look.m })
		if not res.ok and res.code ~= "same" then
			serverFail(res)
			return false
		end
		if res.rec then
			applyRecs({ res.rec })
		end
	elseif op == "remove" then
		if backwards then
			local res = Net.call("restore", { uids = entry.uids, ov = true })
			if not res.ok then
				serverFail(res)
				return false
			end
			applyRecs(res.recs)
			setBalance(res)
		else
			local res = Net.call("remove", { uids = entry.uids, how = entry.how })
			if not res.ok then
				serverFail(res)
				return false
			end
			local uids = {}
			for _, r in res.removed do
				table.insert(uids, r.u)
			end
			dropUids(uids)
			setBalance(res)
		end
	end
	return true
end

function Editor.undo()
	if S.busy or S.mode ~= "browse" then
		return
	end
	local e = table.remove(S.undo)
	if not e then
		Ui.toast("되돌릴 작업이 없어요")
		return
	end
	S.busy = true
	clearSelection()
	local ok = runOp(e, true)
	S.busy = false
	if ok then
		table.insert(S.redo, e)
		Ui.toast("↶ " .. Text.UI.undo)
	end
	changed("undo")
end

function Editor.redo()
	if S.busy or S.mode ~= "browse" then
		return
	end
	local e = table.remove(S.redo)
	if not e then
		Ui.toast("다시 할 작업이 없어요")
		return
	end
	S.busy = true
	clearSelection()
	local ok = runOp(e, false)
	S.busy = false
	if ok then
		table.insert(S.undo, e)
		Ui.toast("↷ " .. Text.UI.redo)
	end
	changed("redo")
end

-- 스타일 세트: place the pieces of a set one after another
function Editor.startSet(set: any)
	S.cart = { set = set, i = 1 }
	local id = set.items[1]
	local inStore = S.storage and (S.storage[id] or 0) > 0
	Editor.pick(id, if inStore then "storage" else "buy", nil)
	Ui.toast(Text.fmt(Text.UI.setProgress, 1, #set.items, Text.won(set.total)))
end

-------------------------------------------------------------------------------------------------
-- Input
-------------------------------------------------------------------------------------------------
local pointer = Vector2.new(0, 0)
local mouseDown: any = nil
local rmb: any = nil
local mmb: any = nil
local touches: { [InputObject]: Vector2 } = {}
local touchStart: any = nil
local pinch: any = nil
local gpStick = { pan = Vector2.zero, orbit = Vector2.zero, zoom = 0 }

local function viewportFromGui(p: Vector3): Vector2
	local inset = GuiService:GetGuiInset()
	return Vector2.new(p.X + inset.X, p.Y + inset.Y)
end

local function updateAim()
	if not S.members or not S.anchor then
		return
	end
	local P, N = aim(pointer)
	if not P or not N then
		return
	end
	local a = poseFromHit(S.anchor.i, P, N, movingSet())
	if a then
		local def = Catalog.get(S.anchor.i)
		if def.place ~= "wall" then
			a.r = S.anchor.r
		end
		S.anchor = a
		S.yaw = a.r
		requestCheck()
	end
end

local function onPointerMoved(p: Vector2)
	pointer = p
	if S.mode == "place" or S.mode == "move" then
		updateAim()
	end
end

local function tapAt(p: Vector2, additive: boolean)
	pointer = p
	if S.mode == "place" or S.mode == "move" then
		updateAim()
		if not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled then
			Editor.confirm()
		end
		return
	end
	local u = pickItem(p)
	if u then
		Editor.select(u, additive or S.multi)
	else
		Editor.select(nil, false)
	end
end

local function inputBegan(input: InputObject, gp: boolean)
	if not S.open or S.paused then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 and not gp then
		local p = UserInputService:GetMouseLocation()
		mouseDown = { p = p, t = os.clock(), item = if S.mode == "browse" then pickItem(p) else nil, dragging = false }
	elseif t == Enum.UserInputType.MouseButton2 and not gp then
		rmb = { p = UserInputService:GetMouseLocation(), moved = false }
	elseif t == Enum.UserInputType.MouseButton3 and not gp then
		mmb = { p = UserInputService:GetMouseLocation() }
	elseif t == Enum.UserInputType.Touch then
		if gp then
			return
		end
		touches[input] = viewportFromGui(input.Position)
		local n = 0
		for _ in touches do
			n += 1
		end
		if n == 1 then
			local p = touches[input]
			touchStart = { input = input, p = p, t = os.clock(), moved = false, item = if S.mode == "browse" then pickItem(p) else nil, long = false }
			if S.mode == "place" or S.mode == "move" then
				onPointerMoved(p)
			end
			-- long press on a piece = start moving it
			local ts = touchStart
			task.delay(0.45, function()
				if touchStart == ts and not ts.moved and ts.item and S.mode == "browse" then
					ts.long = true
					Editor.select(ts.item, false)
					Editor.moveSelected()
				end
			end)
		elseif n == 2 then
			touchStart = nil
			local pts = {}
			for _, v in touches do
				table.insert(pts, v)
			end
			pinch = { d = (pts[1] - pts[2]).Magnitude, c = (pts[1] + pts[2]) / 2 }
		end
	end
end

local function inputChanged(input: InputObject, gp: boolean)
	if not S.open or S.paused then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseMovement then
		local p = UserInputService:GetMouseLocation()
		local delta = input.Delta
		if rmb then
			rmb.moved = rmb.moved or (p - rmb.p).Magnitude > 4
			Camera.orbit(-delta.X * 0.35, delta.Y * 0.25)
			return
		end
		if mmb then
			Camera.pan(-delta.X * 0.05, delta.Y * 0.05)
			return
		end
		if mouseDown and mouseDown.item and not mouseDown.dragging and (p - mouseDown.p).Magnitude > 8 and S.mode == "browse" then
			mouseDown.dragging = true
			if not S.sel[mouseDown.item] then
				Editor.select(mouseDown.item, UserInputService:IsKeyDown(Enum.KeyCode.LeftShift))
			end
			Editor.moveSelected()
		end
		if not gp then
			onPointerMoved(p)
		end
	elseif t == Enum.UserInputType.MouseWheel and not gp then
		Camera.zoom(if input.Position.Z > 0 then 0.88 else 1.14)
	elseif t == Enum.UserInputType.Touch and touches[input] then
		local p = viewportFromGui(input.Position)
		local prev = touches[input]
		touches[input] = p
		local n = 0
		for _ in touches do
			n += 1
		end
		if n >= 2 and pinch then
			local pts = {}
			for _, v in touches do
				table.insert(pts, v)
			end
			local d = (pts[1] - pts[2]).Magnitude
			local c = (pts[1] + pts[2]) / 2
			if pinch.d > 1 then
				Camera.zoom(math.clamp(pinch.d / math.max(d, 1), 0.85, 1.18))
			end
			local dc = c - pinch.c
			Camera.pan(-dc.X * 0.04, dc.Y * 0.04)
			pinch = { d = d, c = c }
		elseif touchStart and touchStart.input == input then
			if (p - touchStart.p).Magnitude > 10 then
				touchStart.moved = true
			end
			if S.mode == "place" or S.mode == "move" then
				onPointerMoved(p)
			elseif touchStart.moved and not touchStart.long then
				local d = p - prev
				Camera.orbit(-d.X * 0.4, d.Y * 0.3)
			end
		end
	elseif t == Enum.UserInputType.Gamepad1 then
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			gpStick.pan = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gpStick.orbit = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			gpStick.zoom = -input.Position.Z
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			gpStick.zoom = input.Position.Z
		end
	end
end

local function inputEnded(input: InputObject, gp: boolean)
	if not S.open or S.paused then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 then
		local md = mouseDown
		mouseDown = nil
		if not md then
			return
		end
		if md.dragging then
			if S.mode == "move" then
				Editor.confirm()
			end
			return
		end
		if not gp and (UserInputService:GetMouseLocation() - md.p).Magnitude < 8 then
			tapAt(UserInputService:GetMouseLocation(), UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift))
		end
	elseif t == Enum.UserInputType.MouseButton2 then
		local r = rmb
		rmb = nil
		if r and not r.moved and (S.mode == "place" or S.mode == "move") then
			Editor.cancel()
		end
	elseif t == Enum.UserInputType.MouseButton3 then
		mmb = nil
	elseif t == Enum.UserInputType.Touch then
		local ts = touchStart
		touches[input] = nil
		local n = 0
		for _ in touches do
			n += 1
		end
		if n < 2 then
			pinch = nil
		end
		if ts and ts.input == input then
			touchStart = nil
			if not ts.moved and not ts.long and os.clock() - ts.t < 0.45 then
				tapAt(ts.p, false)
			elseif S.mode == "move" and ts.long then
				-- lifted the finger after a long-press drag: keep the ghost, the ✓ button confirms
				changed("status")
			end
		end
	elseif t == Enum.UserInputType.Gamepad1 then
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			gpStick.pan = Vector2.zero
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gpStick.orbit = Vector2.zero
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
			gpStick.zoom = 0
		end
	end
end

local ACTION = "GwDecorPlusKeys"
local KEYS = {
	Enum.KeyCode.R, Enum.KeyCode.T, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.G, Enum.KeyCode.Delete, Enum.KeyCode.Backspace,
	Enum.KeyCode.Z, Enum.KeyCode.Y, Enum.KeyCode.D, Enum.KeyCode.M, Enum.KeyCode.F, Enum.KeyCode.Return, Enum.KeyCode.X,
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Space,
	Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1,
	Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.ButtonSelect,
	Enum.KeyCode.ButtonY, Enum.KeyCode.Tab,
}
local held: { [Enum.KeyCode]: boolean } = {}

local function ctrl(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta)
end

local function onKey(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not S.open or S.paused then
		return Enum.ContextActionResult.Pass
	end
	local k = input.KeyCode
	if UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end
	-- a gamepad navigating our menus keeps A / B / D-pad for the GUI
	if GuiService.SelectedObject ~= nil and (k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.ButtonB or k == Enum.KeyCode.DPadUp or k == Enum.KeyCode.DPadDown or k == Enum.KeyCode.DPadLeft or k == Enum.KeyCode.DPadRight) then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.End then
		held[k] = nil
		return Enum.ContextActionResult.Sink
	end
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	held[k] = true
	local placing = S.mode == "place" or S.mode == "move"
	if k == Enum.KeyCode.R or k == Enum.KeyCode.ButtonR1 or k == Enum.KeyCode.ButtonX then
		Editor.rotate(1)
	elseif k == Enum.KeyCode.T or k == Enum.KeyCode.ButtonL1 then
		Editor.rotate(-1)
	elseif k == Enum.KeyCode.E or k == Enum.KeyCode.DPadUp then
		if placing then
			Editor.lift(1)
		end
	elseif k == Enum.KeyCode.Q or k == Enum.KeyCode.DPadDown then
		if placing then
			Editor.lift(-1)
		end
	elseif k == Enum.KeyCode.G or k == Enum.KeyCode.DPadRight then
		Editor.cycleGrid()
	elseif k == Enum.KeyCode.DPadLeft then
		Editor.setOverlap(not S.settings.overlap)
		Ui.toast(if S.settings.overlap then "🧩 겹치기 허용 켬" else "🧩 겹치기 허용 끔")
	elseif k == Enum.KeyCode.Delete or k == Enum.KeyCode.Backspace then
		Editor.removeSelected(Config.DELETE_DEFAULT)
	elseif k == Enum.KeyCode.Z and ctrl() then
		Editor.undo()
	elseif k == Enum.KeyCode.Y and ctrl() then
		Editor.redo()
	elseif k == Enum.KeyCode.D and ctrl() then
		Editor.duplicate()
	elseif k == Enum.KeyCode.M then
		Editor.moveSelected()
	elseif k == Enum.KeyCode.F then
		local u = S.selOrder[1]
		local r = u and S.recs[u]
		if r then
			Camera.focusOn(Vector3.new(r.x, r.y, r.z))
		end
	elseif k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA then
		if placing then
			if k == Enum.KeyCode.ButtonA then
				pointer = Ui.viewport() / 2
				updateAim()
			end
			Editor.confirm()
		elseif k == Enum.KeyCode.ButtonA then
			tapAt(Ui.viewport() / 2, false)
		end
	elseif k == Enum.KeyCode.X or k == Enum.KeyCode.ButtonB then
		if placing then
			Editor.cancel()
		elseif #S.selOrder > 0 then
			Editor.select(nil, false)
		elseif k == Enum.KeyCode.ButtonB then
			changed("requestClose")
		end
	elseif k == Enum.KeyCode.ButtonSelect then
		Editor.undo()
	elseif k == Enum.KeyCode.ButtonY or k == Enum.KeyCode.Tab then
		changed("toggleCatalog")
	end
	return Enum.ContextActionResult.Sink
end

local repeatAcc = 0
local function heartbeat(dt: number)
	if not S.open or S.paused then
		return
	end
	-- keyboard pan (camera relative)
	local px, pz = 0, 0
	if held[Enum.KeyCode.W] or held[Enum.KeyCode.Up] then
		pz += 1
	end
	if held[Enum.KeyCode.S] or held[Enum.KeyCode.Down] then
		pz -= 1
	end
	if held[Enum.KeyCode.A] or held[Enum.KeyCode.Left] then
		px -= 1
	end
	if held[Enum.KeyCode.D] and not ctrl() or held[Enum.KeyCode.Right] then
		px += 1
	end
	if px ~= 0 or pz ~= 0 then
		Camera.pan(px * dt * 14, pz * dt * 14)
		if S.mode ~= "browse" and not UserInputService.TouchEnabled then
			updateAim()
		end
	end
	-- held rotate (fine step repeats)
	if (held[Enum.KeyCode.R] or held[Enum.KeyCode.T]) and S.settings.rot <= 1 then
		repeatAcc += dt
		if repeatAcc > 0.04 then
			repeatAcc = 0
			Editor.rotate(if held[Enum.KeyCode.R] then 1 else -1)
		end
	end
	-- gamepad sticks
	local dead = 0.18
	if gpStick.pan.Magnitude > dead then
		Camera.pan(gpStick.pan.X * dt * 16, gpStick.pan.Y * dt * 16)
		if S.mode ~= "browse" then
			pointer = Ui.viewport() / 2
			updateAim()
		end
	end
	if gpStick.orbit.Magnitude > dead then
		Camera.orbit(-gpStick.orbit.X * dt * 140, gpStick.orbit.Y * dt * 90)
	end
	if math.abs(gpStick.zoom) > 0.1 then
		Camera.zoom(1 + gpStick.zoom * dt * 1.6)
	end
	if pending and os.clock() - lastCheck > Config.CHECK_INTERVAL then
		pending = false
		lastCheck = os.clock()
		validate()
	end
end

-------------------------------------------------------------------------------------------------
-- Open / close
-------------------------------------------------------------------------------------------------
local controlsOff = false
local function setControls(on: boolean)
	pcall(function()
		local pm = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 3) :: any)
		local c = pm:GetControls()
		if on then
			c:Enable()
		else
			c:Disable()
		end
	end)
	controlsOff = not on
end

local function setPrompts(model: Instance, on: boolean)
	if not on then
		for _, d in model:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				promptStates[d] = d.Enabled
				d.Enabled = false
			end
		end
	else
		for pr, was in promptStates do
			if pr.Parent then
				pr.Enabled = was
			end
		end
		promptStates = {}
	end
end

function Editor.begin(snap: any, model: Model, U: any): boolean
	if S.open then
		return true
	end
	S.snap = snap
	S.model = model
	S.U = U
	S.caps = snap.caps
	S.recs = {}
	for _, r in snap.items do
		S.recs[r.u] = r
	end
	rebuildIndex()
	S.storage = snap.storage or {}
	S.balance = snap.balance
	S.fresh = {}
	for k, v in snap.fresh or {} do
		local u = tonumber(k)
		if u then
			S.fresh[u] = os.clock() + v
		end
	end
	S.undo, S.redo = {}, {}
	S.mode = "browse"
	S.open = true
	S.paused = false
	S.cart = nil
	clearSelection()
	local f = Instance.new("Folder")
	f.Name = "Editor"
	local root = workspace:FindFirstChild(Config.LOCAL_FOLDER)
	if not root then
		root = Instance.new("Folder")
		root.Name = Config.LOCAL_FOLDER
		root.Parent = workspace
	end
	f.Parent = root
	ghostFolder = f
	-- camera around the player's room
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	local at = nil
	if hrp and hrp:IsA("BasePart") then
		local q = U.F:PointToObjectSpace(hrp.Position)
		local room = Unit.roomAt(U, q - Vector3.new(0, 2.5, 0))
		if room then
			Camera.start(U, nil)
			Camera.focusRoom(room)
		elseif Unit.floorAt(U, q.X, q.Z, q.Y) then
			at = Vector3.new(q.X, q.Y - 3, q.Z)
			Camera.start(U, at)
		else
			Camera.start(U, nil)
		end
	else
		Camera.start(U, nil)
	end
	Camera.setCut(S.settings.cut)
	setControls(false)
	setPrompts(model, false)
	ContextActionService:BindActionAtPriority(ACTION, onKey, false, Enum.ContextActionPriority.High.Value + 50, table.unpack(KEYS))
	table.insert(conns, UserInputService.InputBegan:Connect(inputBegan))
	table.insert(conns, UserInputService.InputChanged:Connect(inputChanged))
	table.insert(conns, UserInputService.InputEnded:Connect(inputEnded))
	table.insert(conns, RunService.Heartbeat:Connect(heartbeat))
	-- the server rebuilt a model (recolour): reselect
	local folder = model:FindFirstChild(Config.FOLDER_NAME)
	if folder then
		table.insert(conns, folder.ChildAdded:Connect(function(m)
			local u = m:GetAttribute("DecorUid")
			if type(u) == "number" and S.sel[u] then
				task.defer(function()
					selectBox(u, false)
					selectBox(u, true)
				end)
			end
			for _, d in m:GetDescendants() do
				if d:IsA("ProximityPrompt") then
					promptStates[d] = true
					d.Enabled = false
				end
			end
		end))
	end
	changed("open")
	return true
end

function Editor.finish()
	if not S.open then
		return
	end
	Editor.cancel(true)
	clearSelection()
	S.open = false
	S.cart = nil
	ContextActionService:UnbindAction(ACTION)
	for _, c in conns do
		c:Disconnect()
	end
	conns = {}
	held = {}
	touches = {}
	mouseDown, rmb, mmb, touchStart, pinch = nil, nil, nil, nil, nil
	for p in hiddenParts do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	hiddenParts = {}
	if S.model then
		setPrompts(S.model, true)
	end
	Camera.stop()
	if controlsOff then
		setControls(true)
	end
	if ghostFolder then
		ghostFolder:Destroy()
		ghostFolder = nil
	end
	changed("close")
end

-- seconds left of the 10-minute 구매 취소 window of a piece (0 = none)
function Editor.freshLeft(u: number): number
	local t = S.fresh and S.fresh[u]
	return if t then math.max(0, t - os.clock()) else 0
end

-- photo mode on top of the editor: input goes to the photo controls
function Editor.pause(on: boolean)
	if not S.open then
		return
	end
	S.paused = on
	if on then
		ContextActionService:UnbindAction(ACTION)
		held = {}
	else
		ContextActionService:BindActionAtPriority(ACTION, onKey, false, Enum.ContextActionPriority.High.Value + 50, table.unpack(KEYS))
	end
end

function Editor.isOpen(): boolean
	return S.open
end

function Editor.setCut(on: boolean)
	S.settings.cut = on
	Camera.setCut(on)
	changed("settings")
end

-- server snapshot after a preset load (everything changed)
function Editor.resync(snap: any)
	Editor.cancel(true)
	clearSelection()
	S.recs = {}
	for _, r in snap.items do
		S.recs[r.u] = r
	end
	rebuildIndex()
	S.storage = snap.storage or S.storage
	S.balance = snap.balance or S.balance
	S.undo, S.redo = {}, {}
	changed("resync")
end

-- the Unit index after a slot swap / rescan
function Editor.setUnit(U: any)
	S.U = U
	requestCheck()
end

return Editor
