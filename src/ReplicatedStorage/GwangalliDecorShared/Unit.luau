--!strict
-- GwangalliDecorShared/Unit: reads a life-game home model (Workspace.GwangalliHomeInstances.Home_<id>)
-- into a static index in the UnitRoot frame, identical on the server and on every client (the home
-- model replicates as one persistent model). Only reads instances, never changes them.
--   Unit.scan(model) -> U?   U = { model, root, F, floors, walls, ceilings, solids, slots, keeps, rooms,
--                                  levels, themes, spawn, lo, hi, cut }
--   Unit.roomAt(U, p) / Unit.levelAt(U, y) / Unit.levelOfRoom(U, id) / Unit.roomName(id)
-- Classification (the five templates, see research §1.4):
--   floor   Shell parts with Surface "floor" or names Floor* / LoftFloor / MezzFloor / TerraceDeck /
--           Threshold* / StepNosing (top = walkable)
--   wall    Shell Surface "wall" or names *Wall* / Partition / Spandrel; windows (WindowGlass, Glazing*,
--           Mullion, Sash, Transom, RailingGlass, TerraceBarrier) are walls a curtain may hang on
--   ceiling Shell Ceiling* / *Slab / Canopy (+ the undersides of upper floors)
--   solid   every other colliding part of Shell / Fixtures / Props / Furniture / ExitDoor
--   keep    Door models + ExitDoor (swing), Spawn (현관), HomeInteract parts (fronts), Stair models

local Geometry = require(script.Parent:WaitForChild("Geometry"))
local Config = require(script.Parent:WaitForChild("Config"))

local Unit = {}

Unit.ROOM_NAMES = {
	living = { name = "거실", icon = "🛋️" },
	dining = { name = "다이닝", icon = "🍷" },
	kitchen = { name = "주방", icon = "🍳" },
	bedroom = { name = "침실", icon = "🛏️" },
	loft = { name = "복층", icon = "🪜" },
	study = { name = "서재", icon = "📚" },
	dress = { name = "드레스룸", icon = "👗" },
	bath = { name = "욕실", icon = "🚿" },
	master_bath = { name = "안방 욕실", icon = "🛁" },
	entry = { name = "현관", icon = "🚪" },
	veranda = { name = "베란다", icon = "🌿" },
	terrace = { name = "테라스", icon = "🌊" },
	wine = { name = "와인룸", icon = "🍷" },
	powder = { name = "파우더룸", icon = "🪞" },
	main = { name = "방", icon = "🏠" },
}
Unit.ROOM_ORDER = { "living", "main", "bedroom", "loft", "kitchen", "dining", "study", "dress", "terrace", "veranda", "wine", "bath", "master_bath", "powder", "entry" }

local FLOOR_ROOM = {
	FloorEntry = "entry",
	FloorBath = "bath",
	FloorVeranda = "veranda",
	TerraceDeck = "terrace",
	FloorWine = "wine",
	FloorPowder = "powder",
	LoftFloor = "loft",
	MezzFloor = "bedroom",
	StepNosing = "entry",
	Threshold = "entry",
	ThresholdBath = "bath",
}

local WINDOW = { WindowGlass = true, GlazingFrame = true, WindowFrame = true, Mullion = true, Sash = true, Transom = true, RailingGlass = true, TerraceBarrier = true, DoorGlass = true }
local DOOR_MODELS = { Door = true, WetCellDoor = true, VerandaDoor = true, Jungmun = true }
local SKIP_TOP = { Backdrop = true, Interact = true, Spawn = true, UnitRoot = true }
local KEEP_SKIP_KIND = { window = true, mailbox = true }

-- drops leading emoji / symbols ("🛠 인테리어" -> "인테리어")
function Unit.stripIcon(s: string): string
	local out = s
	for _ = 1, 6 do
		local n = string.gsub(out, "^[\240-\244][\128-\191][\128-\191][\128-\191]", "")
		n = string.gsub(n, "^\226[\128-\191][\128-\191]", "")
		n = string.gsub(n, "^\239\184\143", "")
		n = string.gsub(n, "^%s+", "")
		if n == out then
			break
		end
		out = n
	end
	return if out == "" then s else out
end

function Unit.roomName(id: string): (string, string)
	local r = (Unit.ROOM_NAMES :: any)[id]
	if r then
		return r.name, r.icon
	end
	return id, "🏠"
end

local function isFloorName(n: string): boolean
	return string.sub(n, 1, 5) == "Floor" or n == "LoftFloor" or n == "MezzFloor" or n == "TerraceDeck" or string.sub(n, 1, 9) == "Threshold" or n == "StepNosing"
end

local function isWallName(n: string): boolean
	return string.find(n, "Wall", 1, true) ~= nil or n == "Partition" or n == "Spandrel"
end

local function isCeilingName(n: string): boolean
	return string.sub(n, 1, 7) == "Ceiling" or string.sub(n, -4) == "Slab" or n == "Canopy"
end

local function boxOf(F: CFrame, p: BasePart): any
	local b = Geometry.obb(F:ToObjectSpace(p.CFrame), p.Size / 2)
	return Geometry.prime(b)
end

local function topOf(b: any): number
	return b.hi.Y
end

-- the folder (Shell / Fixtures / ...) right under the model that contains d
local function topFolder(model: Instance, d: Instance): Instance?
	local cur: Instance? = d
	while cur and cur.Parent ~= model do
		cur = cur.Parent
	end
	return cur
end

function Unit.scan(model: Instance): any?
	if not model or not model.Parent then
		return nil
	end
	local root = model:FindFirstChild("UnitRoot")
	if not (root and root:IsA("BasePart")) then
		local pp = (model :: any).PrimaryPart
		root = pp
	end
	if not root then
		return nil
	end
	local F = Geometry.unitFrame(root)
	local U: any = {
		model = model,
		root = root,
		F = F,
		floors = {},
		walls = {},
		ceilings = {},
		solids = {},
		slots = {},
		keeps = {},
		rooms = {},
		roomById = {},
		levels = {},
		themes = {},
		cut = { walls = {}, ceilings = {}, all = {} },
		spawn = Vector3.new(0, 0, 0),
		version = 0,
	}
	local fallback = model:GetAttribute("Fallback") == true
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo

	-- themes (same sets as Housing Core.collectThemes)
	local function themeEntry(id: string): any
		local e = U.themes[id]
		if not e then
			e = { wall = {}, floor = {}, light = {}, lights = {} }
			U.themes[id] = e
		end
		return e
	end

	local slotOf: { [Instance]: any } = {}
	local furniture = model:FindFirstChild("Furniture")
	if furniture then
		for _, s in furniture:GetChildren() do
			local sid = s:GetAttribute("SlotId")
			if type(sid) == "string" then
				local base = (s :: any).PrimaryPart or s:FindFirstChild("SlotBase")
				if base and base:IsA("BasePart") then
					local fp = s:GetAttribute("Footprint")
					local w, h, d
					if typeof(fp) == "Vector3" then
						w, h, d = math.abs(fp.X), math.max(0.05, math.abs(fp.Y)), math.abs(fp.Z)
					else
						w, h, d = base.Size.X, math.max(base.Size.Y, 3), base.Size.Z
					end
					local frame = base.CFrame * CFrame.new(0, -base.Size.Y / 2, 0)
					local cat = s:GetAttribute("Category")
					local mountY = s:GetAttribute("MountY")
					if type(mountY) == "number" then
						frame *= CFrame.new(0, mountY, 0)
					elseif cat == "art" then
						frame *= CFrame.new(0, math.max(0, 5 - h / 2), 0)
					end
					if cat == "art" then
						frame *= CFrame.new(0, 0, -d / 2)
					end
					if s:GetAttribute("Rotate") == true then
						local m = math.max(w, d)
						w, d = m, m
					end
					local env = Geometry.prime(Geometry.obb(F:ToObjectSpace(frame * CFrame.new(0, h / 2, 0)), Vector3.new(w / 2, h / 2, d / 2)))
					local rec = { id = sid, category = cat, box = env, model = s }
					table.insert(U.slots, rec)
					slotOf[s] = rec
				end
			end
		end
	end

	local function slotFor(d: Instance): any?
		local cur: Instance? = d.Parent
		while cur and cur ~= model do
			local s = slotOf[cur]
			if s then
				return s
			end
			cur = cur.Parent
		end
		return nil
	end

	local folderName = Config.FOLDER_NAME
	local decor = model:FindFirstChild(folderName)

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local tf = topFolder(model, d)
			local top = tf and tf.Name or ""
			if SKIP_TOP[top] or (decor and d:IsDescendantOf(decor)) then
				continue
			end
			local room = d:GetAttribute("Room")
			local surf = d:GetAttribute("Surface")
			if type(room) == "string" and #room > 0 and #room <= 24 and (surf == "wall" or surf == "floor" or surf == "light") then
				table.insert(themeEntry(room)[surf], d)
			elseif fallback then
				if d.Name == "Wall" then
					table.insert(themeEntry("main").wall, d)
				elseif d.Name == "Floor" then
					table.insert(themeEntry("main").floor, d)
				elseif d.Name == "CeilingLight" then
					table.insert(themeEntry("main").light, d)
				end
			end
			local n = d.Name
			local b = boxOf(F, d)
			if top == "Shell" or fallback then
				if surf == "floor" or isFloorName(n) then
					local rid = if type(room) == "string" and #room > 0 then room else (FLOOR_ROOM[n] or "main")
					table.insert(U.floors, { box = b, top = topOf(b), room = rid, part = d, name = n })
					lo, hi = lo:Min(b.lo), hi:Max(b.hi)
					table.insert(U.cut.all, d)
					continue
				elseif surf == "wall" or isWallName(n) then
					table.insert(U.walls, { box = b, part = d, faces = Geometry.sideFaces(b) })
					table.insert(U.cut.walls, d)
					table.insert(U.cut.all, d)
					continue
				elseif isCeilingName(n) then
					table.insert(U.ceilings, { box = b, bottom = b.lo.Y, part = d })
					if string.sub(n, 1, 7) == "Ceiling" then
						table.insert(U.cut.ceilings, d)
					end
					table.insert(U.cut.all, d)
					continue
				end
			end
			if WINDOW[n] then
				table.insert(U.walls, { box = b, part = d, window = true, faces = Geometry.sideFaces(b) })
				table.insert(U.cut.all, d)
				continue
			end
			table.insert(U.cut.all, d)
			if d.CanCollide and d.Transparency < 0.98 then
				local s = slotFor(d)
				local horiz = math.abs(b.cf.UpVector.Y) > 0.98
				table.insert(U.solids, {
					box = b,
					part = d,
					top = if horiz then b.hi.Y else nil,
					slot = s and s.id or nil,
					stair = string.sub(n, 1, 5) == "Stair",
					name = n,
				})
			end
		elseif d:IsA("Light") then
			local room = d:GetAttribute("Room")
			if type(room) == "string" and #room > 0 and #room <= 24 then
				table.insert(themeEntry(room).lights, d)
			elseif fallback and d.Parent and d.Parent.Name == "CeilingLight" then
				table.insert(themeEntry("main").lights, d)
			end
		end
	end
	if #U.floors == 0 then
		return nil
	end
	U.lo, U.hi = lo, hi

	-- levels: floor tops clustered (> 2.5 studs apart)
	local tops = {}
	for _, f in U.floors do
		table.insert(tops, f.top)
	end
	table.sort(tops)
	for _, t in tops do
		local last = U.levels[#U.levels]
		if not last or t - last.y > 2.5 then
			table.insert(U.levels, { y = t, name = if #U.levels == 0 then "1층" else "복층" })
		end
	end
	if #U.levels > 1 then
		U.levels[1].name = "1층"
		for i = 2, #U.levels do
			U.levels[i].name = if #U.levels == 2 then "복층" else (tostring(i) .. "층")
		end
	end
	for _, f in U.floors do
		f.level = Unit.levelAt(U, f.top)
	end
	-- upper floors are ceilings for the level below
	for _, f in U.floors do
		if f.level > 1 then
			table.insert(U.ceilings, { box = f.box, bottom = f.box.lo.Y, part = f.part })
		end
	end

	-- rooms (floor footprints grouped by room id)
	for _, f in U.floors do
		local r = U.roomById[f.room]
		if not r then
			local name, icon = Unit.roomName(f.room)
			r = { id = f.room, name = name, icon = icon, lo = f.box.lo, hi = f.box.hi, level = f.level, floorY = f.top, area = 0 }
			U.roomById[f.room] = r
			table.insert(U.rooms, r)
		else
			r.lo, r.hi = r.lo:Min(f.box.lo), r.hi:Max(f.box.hi)
			r.level = math.min(r.level, f.level)
			r.floorY = math.min(r.floorY, f.top)
		end
		r.area += f.box.half.X * f.box.half.Z * 4
	end
	local rank = {}
	for i, id in Unit.ROOM_ORDER do
		rank[id] = i
	end
	table.sort(U.rooms, function(a, b)
		local ra, rb = rank[a.id] or 50, rank[b.id] or 50
		if ra ~= rb then
			return ra < rb
		end
		return a.id < b.id
	end)
	for _, r in U.rooms do
		local c = (r.lo + r.hi) / 2
		local ceil = Unit.ceilingAbove(U, c.X, c.Z, r.floorY + 0.5)
		r.height = math.clamp((ceil or (r.floorY + 7.8)) - r.floorY, 4, 30)
		r.centre = Vector3.new(c.X, r.floorY, c.Z)
		r.size = Vector3.new(r.hi.X - r.lo.X, r.height, r.hi.Z - r.lo.Z)
	end

	-- spawn / keep zones
	local K = Config.KEEP
	local spawn = model:FindFirstChild("Spawn", true)
	if spawn and spawn:IsA("BasePart") then
		local p = F:PointToObjectSpace(spawn.Position)
		local fy = Unit.floorTopAt(U, p.X, p.Z, p.Y + 2) or p.Y
		U.spawn = Vector3.new(p.X, fy, p.Z)
		table.insert(U.keeps, {
			box = Geometry.prime(Geometry.obb(CFrame.new(p.X, fy + 3.5, p.Z), Vector3.new(K.entry / 2, 3.5, K.entry / 2))),
			code = "entry",
			label = "현관",
		})
	end
	local function doorZone(cf: CFrame, size: Vector3, label: string)
		local c = F:ToObjectSpace(cf)
		-- the thin horizontal axis is the door's normal
		local thinX = size.X < size.Z
		local wide = if thinX then size.Z else size.X
		local fy = Unit.floorTopAt(U, c.Position.X, c.Position.Z, c.Position.Y + 1) or (c.Position.Y - size.Y / 2)
		local half = if thinX then Vector3.new(K.doorDepth, 3.6, wide / 2 + K.doorPad) else Vector3.new(wide / 2 + K.doorPad, 3.6, K.doorDepth)
		local centre = CFrame.new(c.Position.X, fy + 3.6, c.Position.Z) * c.Rotation
		table.insert(U.keeps, { box = Geometry.prime(Geometry.obb(centre, half)), code = "door", label = label, door = true })
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and DOOR_MODELS[d.Name] and not (decor and d:IsDescendantOf(decor)) then
			local ok, cf, size = pcall(function()
				return (d :: Model):GetBoundingBox()
			end)
			if ok and cf then
				doorZone(cf, size, "문")
			end
		elseif d:IsA("Model") and d.Name == "Stair" then
			local ok, cf, size = pcall(function()
				return (d :: Model):GetBoundingBox()
			end)
			if ok and cf then
				local b = Geometry.prime(Geometry.obb(F:ToObjectSpace(cf), size / 2 + Vector3.new(0.4, 0.5, 0.4)))
				table.insert(U.keeps, { box = b, code = "stair", label = "계단" })
				U.stair = b
			end
		end
	end
	local exit = model:FindFirstChild("ExitDoor")
	if exit and exit:IsA("BasePart") then
		doorZone(exit.CFrame, exit.Size, "현관문")
	end
	local interact = model:FindFirstChild("Interact")
	if interact then
		for _, p in interact:GetDescendants() do
			if p:IsA("BasePart") then
				local kind = p:GetAttribute("Kind")
				if type(kind) == "string" and not KEEP_SKIP_KIND[kind] then
					local b = boxOf(F, p)
					local label = p:GetAttribute("Label")
					local lb = if type(label) == "string" and #label > 0 then label else kind
					lb = Unit.stripIcon(lb)
					local zone = Geometry.prime(Geometry.inflate(b, K.interactDepth * 0.5, 0, K.interactDepth * 0.5))
					table.insert(U.keeps, { box = zone, code = "interact", label = lb, kind = kind, target = true })
				end
			end
		end
	end
	return U
end

-------------------------------------------------------------------------------------------------
-- Queries (unit frame)
-------------------------------------------------------------------------------------------------
function Unit.levelAt(U: any, y: number): number
	local best = 1
	for i, l in U.levels do
		if y >= l.y - 1.2 then
			best = i
		end
	end
	return best
end

-- highest floor top at (x, z) not above yMax
function Unit.floorTopAt(U: any, x: number, z: number, yMax: number): number?
	local best: number? = nil
	local p = Vector3.new(x, 0, z)
	for _, f in U.floors do
		if f.top <= yMax + 1e-3 and Geometry.pointInXZ(f.box, p, 0.02) then
			if not best or f.top > best then
				best = f.top
			end
		end
	end
	return best
end

-- the floor record under (x, z) at or below yMax
function Unit.floorAt(U: any, x: number, z: number, yMax: number): any?
	local best: any = nil
	local p = Vector3.new(x, 0, z)
	for _, f in U.floors do
		if f.top <= yMax + 1e-3 and Geometry.pointInXZ(f.box, p, 0.02) then
			if not best or f.top > best.top then
				best = f
			end
		end
	end
	return best
end

-- lowest ceiling bottom above (x, z) from height y
function Unit.ceilingAbove(U: any, x: number, z: number, y: number): number?
	local best: number? = nil
	local p = Vector3.new(x, 0, z)
	for _, c in U.ceilings do
		if c.bottom > y and Geometry.pointInXZ(c.box, p, 0.02) then
			if not best or c.bottom < best then
				best = c.bottom
			end
		end
	end
	return best
end

function Unit.roomAt(U: any, p: Vector3): any?
	local f = Unit.floorAt(U, p.X, p.Z, p.Y + 0.6)
	if f then
		return U.roomById[f.room]
	end
	return nil
end

function Unit.levelOfRoom(U: any, id: string): number
	local r = U.roomById[id]
	return r and r.level or 1
end

-- world <-> unit frame
function Unit.toWorld(U: any, cf: CFrame): CFrame
	return U.F * cf
end

function Unit.toUnit(U: any, cf: CFrame): CFrame
	return U.F:ToObjectSpace(cf)
end

function Unit.pointToUnit(U: any, p: Vector3): Vector3
	return U.F:PointToObjectSpace(p)
end

return Unit
