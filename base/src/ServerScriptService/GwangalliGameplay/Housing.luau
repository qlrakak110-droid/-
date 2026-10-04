-- GwangalliGameplay/Housing: 자기집 마련 — the home-ownership layer of the life game.
--   * per-player instancing: the owner's template (ServerStorage.GwangalliHomes "HomeUnit_<tierKey>",
--     else a built-in fallback unit) is cloned into Workspace.GwangalliHomeInstances on a grid high
--     above the map (G.homeSlotPosition), reused while the owner is online, destroyed on leave, on
--     a move / eviction / foreclosure and after G.HOME_IDLE_DESTROY unused; server-authoritative
--   * entering: the HomeEntrance prompts (client-side, per player text: 집으로 들어가기 / 초인종) and
--     the phone ("enterHome"); leaving: ExitDoor / door prompt, HomeAction "leave", phone
--     "leaveHome" -> back to the building's HomeEntrance (or the listing's Destination)
--   * home interactions (server ProximityPrompts on HomeInteract parts): bed (sleep via Life.sleep,
--     lying pose), sofa (Seat) + TV (행복 over time), fridge (집밥 / 장보기 / 배달음식), table,
--     shower, wardrobe, desk, window (photo moment), mailbox (bills)
--   * furniture: slot-based decoration with generated variants (G.furnitureSpec), saved per listing
--   * visiting: doorbell -> owner answers, invites, kick (+ ban), guest limits, 집들이
--   * remodelling (G.HOME_UPGRADES) and 주택담보대출 (G.MORTGAGE) actions
--   * 인테리어 (GwangalliHomesShared = G.HOMES): per-room 벽지 / 바닥 / 조명 themes (parts with Room +
--     Surface attributes recoloured, Color + Material only), quarter turns of a piece (rot), the 현관
--     wall panel (HomeInteract Kind "interior") / HomeAction "openInterior" -> HomeState "interior"
--     {mode = "edit" | "tour", rooms, slots, decor, ...}; "setTheme" {room, kind, id}, "rotateSlot"
--     {slotId, rot}, "placeFurniture" {slotId, variantId, rot?, sellOld?} (sellOld: the replaced piece
--     is sold back at 50 % first), "compliment" (guest), "tour" {listingId} (매물 둘러보기: an empty
--     staged unit; 나가기 returns the viewer to where they stood); results in HomeState
--     "interiorResult" {ok, action, ...}, theme changes broadcast as HomeState "themes" {rooms, decor}.
--     Furniture lights are capped per instance (HS.FURNITURE_LIGHTS). Test hook: ServerStorage
--     .GwangalliHomesAPI (status | open | grant in test mode).
-- Contract (remotes HomeAction / HomeState / HomeQuery, template / tag rules): the "자기집 마련"
-- section of ReplicatedStorage.GwangalliGameplayShared. Required by Life (Life.init -> Housing.init).
-- Housing.Core holds the pure logic (slot grid, visit state machine, template scan, furniture
-- builder, fallback unit) so Lune tests can run it with fakes; nothing touches Roblox services at
-- require time.

local Housing = {}
local Core = {}
Housing.Core = Core

local G: any = nil
local Util: any = nil
local Profiles: any = nil
local ctx: any = nil
local Life: any = nil

local Players: any = nil
local CollectionService: any = nil
local ServerStorage: any = nil
local ReplicatedStorage: any = nil

function Core.setShared(shared: any)
	G = shared
end

-------------------------------------------------------------------------------------------------
-- Core: pure helpers
-------------------------------------------------------------------------------------------------
-- Lowest free 1-based index.
function Core.allocIndex(used: { [number]: any }): number
	local i = 1
	while used[i] ~= nil do
		i += 1
	end
	return i
end

-- May `role` ("owner" | "guest") use an interaction of `kind`?
function Core.canUse(kind: string, role: string?): boolean
	local k = G.HOME_KINDS[kind]
	if not k then
		return false
	end
	if role == "owner" then
		return true
	end
	-- "viewer" = 매물 둘러보기 in an empty staged unit: the same rights as a guest
	return (role == "guest" or role == "viewer") and k.guest == true
end

function Core.canAdmit(guestCount: number, tierKey: string): boolean
	return guestCount < G.homeGuestLimit(tierKey)
end

-- Visit state machine. Keys are opaque (Players at runtime, strings in tests).
--   rings[owner][visitor] = time rung       invites[visitor][owner] = { t, expires }
--   bans[owner][visitor] = until
function Core.newVisits(): any
	return { rings = {}, invites = {}, bans = {} }
end

function Core.banned(vs: any, owner: any, visitor: any, now: number): boolean
	local b = vs.bans[owner]
	local t = b and b[visitor]
	return t ~= nil and now < t
end

-- Returns ok, reason ("self" | "banned" | "pending")
function Core.ring(vs: any, owner: any, visitor: any, now: number): (boolean, string?)
	if owner == visitor then
		return false, "self"
	end
	if Core.banned(vs, owner, visitor, now) then
		return false, "banned"
	end
	local r = vs.rings[owner]
	if not r then
		r = {}
		vs.rings[owner] = r
	end
	local t = r[visitor]
	if t and now - t < 8 then
		return false, "pending"
	end
	r[visitor] = now
	return true, nil
end

-- The owner answers a ring. Returns ok, reason ("none" | "expired")
function Core.answer(vs: any, owner: any, visitor: any, now: number): (boolean, string?)
	local r = vs.rings[owner]
	local t = r and r[visitor]
	if not t then
		return false, "none"
	end
	r[visitor] = nil
	if now - t > G.HOME_RING_TTL then
		return false, "expired"
	end
	return true, nil
end

-- Returns ok, reason ("self" | "banned" | "pending")
function Core.invite(vs: any, owner: any, visitor: any, now: number): (boolean, string?)
	if owner == visitor then
		return false, "self"
	end
	if Core.banned(vs, owner, visitor, now) then
		return false, "banned"
	end
	local inv = vs.invites[visitor]
	if not inv then
		inv = {}
		vs.invites[visitor] = inv
	end
	local cur = inv[owner]
	if cur and now < cur.expires and now - cur.t < 5 then
		return false, "pending"
	end
	inv[owner] = { t = now, expires = now + G.HOME_INVITE_TTL }
	return true, nil
end

-- The visitor accepts (take = true) or declines. Returns ok, reason ("none" | "expired")
function Core.takeInvite(vs: any, visitor: any, owner: any, now: number): (boolean, string?)
	local inv = vs.invites[visitor]
	local cur = inv and inv[owner]
	if not cur then
		return false, "none"
	end
	inv[owner] = nil
	if now > cur.expires then
		return false, "expired"
	end
	return true, nil
end

function Core.kick(vs: any, owner: any, visitor: any, now: number)
	local b = vs.bans[owner]
	if not b then
		b = {}
		vs.bans[owner] = b
	end
	b[visitor] = now + G.HOME_KICK_BAN
	if vs.rings[owner] then
		vs.rings[owner][visitor] = nil
	end
	if vs.invites[visitor] then
		vs.invites[visitor][owner] = nil
	end
end

-- Forgets every reference to `key` (a player left).
function Core.forget(vs: any, key: any)
	vs.rings[key] = nil
	vs.invites[key] = nil
	vs.bans[key] = nil
	for _, r in vs.rings do
		r[key] = nil
	end
	for _, inv in vs.invites do
		inv[key] = nil
	end
end

-- Scans a (cloned) unit Model: root, spawn, exit door, interactions, furniture slots.
function Core.scanUnit(model: any): any
	local T = G.HomeTags
	local info = { root = nil, spawn = nil, exit = nil, interacts = {}, slots = {} }
	local seen = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local name = d.Name
			if name == "UnitRoot" and not info.root then
				info.root = d
			elseif (name == "Spawn" or name == "HomeSpawn") and not info.spawn then
				info.spawn = d
			elseif name == "ExitDoor" and not info.exit then
				info.exit = d
			end
			if d:HasTag(T.Interact) then
				local kind = d:GetAttribute("Kind")
				if type(kind) == "string" and G.HOME_KINDS[kind] then
					table.insert(info.interacts, { part = d, kind = kind })
				end
			end
		end
		if (d:IsA("BasePart") or d:IsA("Model")) and d:HasTag(T.Slot) then
			local id = d:GetAttribute("SlotId")
			local cat = d:GetAttribute("Category")
			if type(id) == "string" and #id > 0 and #id <= 40 and not seen[id] and type(cat) == "string" and G.FURNITURE_CATEGORIES[cat] then
				local geo = G.slotGeometry(d)
				if geo then
					seen[id] = true
					table.insert(info.slots, { part = geo.base, container = d, id = id, category = cat, default = geo.default })
				end
			end
		end
	end
	local pp = model.PrimaryPart
	if pp then
		info.root = pp
	end
	table.sort(info.slots, function(a, b)
		return a.id < b.id
	end)
	table.sort(info.interacts, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		return a.part:GetFullName() < b.part:GetFullName()
	end)
	return info
end

-- HomeInteract parts inside a slot's default furniture get an invisible proxy (so swapping the
-- furniture never removes the interaction). Mutates info.interacts.
function Core.proxifyInteracts(model: any, info: any)
	local folder: any = nil
	for _, it in info.interacts do
		for _, s in info.slots do
			if s.default and it.part:IsDescendantOf(s.default) then
				if not folder then
					folder = Instance.new("Folder")
					folder.Name = "HomeInteractions"
					folder.Parent = model
				end
				local src = it.part
				local p = Instance.new("Part")
				p.Name = "Interact_" .. it.kind
				p.Size = src.Size
				p.CFrame = src.CFrame
				p.Transparency = 1
				p.Anchored = true
				p.CanCollide = false
				p.CanTouch = false
				p.CanQuery = false
				p:SetAttribute("Kind", it.kind)
				p:AddTag(G.HomeTags.Interact)
				pcall(function()
					src:RemoveTag(G.HomeTags.Interact)
				end)
				p.Parent = folder
				it.part = p
				break
			end
		end
	end
end

-- Bottom-centre frame of a FurnitureSlot part (front = its LookVector).
function Core.slotFrame(slotPart: any): any
	return slotPart.CFrame * CFrame.new(0, -slotPart.Size.Y / 2, 0)
end

-- Builds a furniture spec (G.furnitureSpec) as a Model at `frame`. Returns model, extra = {screen,
-- seat, bed = CFrame?, lights = n}. maxLights caps the PointLights the piece may add (nil = all).
function Core.buildSpec(spec: any, frame: any, parent: any, name: string, maxLights: number?): (any, any)
	local m = Instance.new("Model")
	m.Name = name
	local built = {}
	for i, p in spec.parts do
		local part = Instance.new("Part")
		part.Name = p.name
		if p.shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		elseif p.shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		end
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		local cf = frame * CFrame.new(p.pos[1], p.pos[2], p.pos[3])
		if p.rot then
			cf = cf * CFrame.Angles(math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3]))
		end
		part.CFrame = cf
		part.Color = Color3.fromRGB(p.color[1], p.color[2], p.color[3])
		local okM, mat = pcall(function()
			return (Enum.Material :: any)[p.material]
		end)
		part.Material = if okM and mat then mat else Enum.Material.SmoothPlastic
		part.Transparency = p.transparency or 0
		part.Anchored = true
		part.CanCollide = p.collide == true
		part.CanTouch = false
		part.CanQuery = p.collide == true
		part.CastShadow = p.collide == true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = m
		built[i] = part
	end
	local nLights = 0
	for _, l in spec.lights or {} do
		local host = built[l.part]
		if host and (maxLights == nil or nLights < maxLights) then
			local light = Instance.new("PointLight")
			light.Range = l.range
			light.Brightness = l.brightness
			light.Color = Color3.fromRGB(l.color[1], l.color[2], l.color[3])
			light.Shadows = false
			light.Parent = host
			nLights += 1
		end
	end
	local extra: any = { parts = built, lights = nLights }
	if spec.screen and built[spec.screen] then
		extra.screen = built[spec.screen]
	end
	if spec.seat then
		local seat = Instance.new("Seat")
		seat.Name = "HomeSeat"
		seat.Size = Vector3.new(1.6, 0.2, 1.6)
		seat.CFrame = frame * CFrame.new(spec.seat.pos[1], spec.seat.pos[2] + 0.1, spec.seat.pos[3])
		seat.Transparency = 1
		seat.Anchored = true
		seat.CanCollide = false
		seat.CanTouch = false
		seat.CanQuery = false
		seat.Parent = m
		extra.seat = seat
	end
	if spec.bed then
		extra.bed = frame * CFrame.new(spec.bed.pos[1], spec.bed.pos[2], spec.bed.pos[3])
	end
	m.Parent = parent
	return m, extra
end

-------------------------------------------------------------------------------------------------
-- Core: 인테리어 themes (벽지 / 바닥 / 조명 per room) and quarter-turn rotation
-------------------------------------------------------------------------------------------------
-- Collects the themable parts of a unit (the window view excluded):
--   { rooms = { [room] = { wall = {BasePart}, floor = {BasePart}, light = {BasePart}, lights = {Light} } },
--     order = { room ids }, orig = { [Instance] = { color, material } } }
-- Template parts carry Room + Surface (homes_kit H.rooms); the built-in fallback unit has none, so
-- its Floor / Wall / CeilingLight parts form the single room "main".
function Core.collectThemes(model: any, view: any?): any
	local rooms = {}
	local function entry(id: string): any
		local e = rooms[id]
		if not e then
			e = { wall = {}, floor = {}, light = {}, lights = {} }
			rooms[id] = e
		end
		return e
	end
	local fallback = model:GetAttribute("Fallback") == true
	for _, d in model:GetDescendants() do
		if view and d:IsDescendantOf(view) then
			continue
		end
		if d:IsA("BasePart") then
			local room = d:GetAttribute("Room")
			local surf = d:GetAttribute("Surface")
			if type(room) == "string" and #room > 0 and #room <= 24 and (surf == "wall" or surf == "floor" or surf == "light") then
				table.insert(entry(room)[surf], d)
			elseif fallback then
				if d.Name == "Wall" then
					table.insert(entry("main").wall, d)
				elseif d.Name == "Floor" then
					table.insert(entry("main").floor, d)
				elseif d.Name == "CeilingLight" then
					table.insert(entry("main").light, d)
				end
			end
		elseif d:IsA("Light") then
			local room = d:GetAttribute("Room")
			if type(room) == "string" and #room > 0 and #room <= 24 then
				table.insert(entry(room).lights, d)
			elseif fallback and d.Parent and d.Parent.Name == "CeilingLight" then
				table.insert(entry("main").lights, d)
			end
		end
	end
	local ids = {}
	for id, e in rooms do
		if #e.wall + #e.floor + #e.light + #e.lights > 0 then
			table.insert(ids, id)
		end
	end
	local HSm = G and G.HOMES
	local order = if HSm then HSm.sortRooms(ids) else ids
	if not HSm then
		table.sort(order)
	end
	return { rooms = rooms, order = order, orig = {} }
end

-- Theme kinds a room can take: { wall = bool, floor = bool, light = bool }.
function Core.roomKinds(th: any, room: string): any
	local e = th.rooms[room]
	if not e then
		return { wall = false, floor = false, light = false }
	end
	return { wall = #e.wall > 0, floor = #e.floor > 0, light = #e.light + #e.lights > 0 }
end

local function rgb3(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function materialOf(name: any): any
	if type(name) ~= "string" then
		return nil
	end
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok then m else nil
end

-- Applies one theme kind to a room. def = the theme definition (HS.WALLPAPERS[id] / FLOORS / LIGHTS)
-- or nil for the template's own look. Color + Material only. Returns the number of instances set.
function Core.applyRoomTheme(th: any, room: string, kind: string, def: any?): number
	local e = th.rooms[room]
	if not e then
		return 0
	end
	local orig = th.orig
	local n = 0
	local list = if kind == "wall" then e.wall elseif kind == "floor" then e.floor elseif kind == "light" then e.light else {}
	for _, p in list do
		local o = orig[p]
		if not o then
			if not def then
				continue -- never themed: already the template's look
			end
			o = { color = p.Color, material = p.Material }
			orig[p] = o
		end
		if def then
			p.Color = rgb3(def.color)
			if kind ~= "light" then
				local m = materialOf(def.material)
				if m then
					p.Material = m
				end
			end
		else
			p.Color = o.color
			p.Material = o.material
		end
		n += 1
	end
	if kind == "light" then
		for _, l in e.lights do
			local o = orig[l]
			if not o then
				if not def then
					continue
				end
				o = { color = l.Color }
				orig[l] = o
			end
			l.Color = if def then rgb3(def.color) else o.color
			n += 1
		end
	end
	return n
end

-- Applies every saved theme of a unit record (u.walls / u.floors / u.lights) to an instance.
function Core.applyThemes(th: any, unit: any)
	local HSm = G and G.HOMES
	if not HSm then
		return
	end
	for _, room in th.order do
		for _, kind in HSm.THEME_KINDS do
			local field = if kind == "wall" then "walls" elseif kind == "floor" then "floors" else "lights"
			local t = type(unit) == "table" and unit[field] or nil
			local id = type(t) == "table" and t[room] or nil
			Core.applyRoomTheme(th, room, kind, HSm.themeDef(kind, id))
		end
	end
end

-- A room in the unit frame: centre (world Vector3 on the floor top, XZ centre of the floor) and
-- size (X, height to the top of its walls, Z), or nil. Falls back to the walls / lights footprint.
function Core.roomBox(th: any, room: string, frame: CFrame): (Vector3?, Vector3?)
	local e = th.rooms[room]
	if not e then
		return nil, nil
	end
	local parts = if #e.floor > 0 then e.floor elseif #e.wall > 0 then e.wall else e.light
	if #parts == 0 then
		return nil, nil
	end
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in parts do
		local h = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local c = frame:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(sx * h.X, h.Y, sz * h.Z)))
				lo = lo:Min(c)
				hi = hi:Max(c)
			end
		end
	end
	local floorY = if #e.floor > 0 then hi.Y else lo.Y
	-- height: the top of the room's walls (else its lights), at least 6 studs
	local top = floorY + 7.6
	local hiW = -math.huge
	for _, p in (if #e.wall > 0 then e.wall else e.light) do
		local c = frame:PointToObjectSpace(p.Position)
		hiW = math.max(hiW, c.Y + p.Size.Y / 2)
	end
	if hiW > floorY + 2 then
		top = hiW
	end
	local centre = frame:PointToWorldSpace(Vector3.new((lo.X + hi.X) / 2, floorY, (lo.Z + hi.Z) / 2))
	return centre, Vector3.new(hi.X - lo.X, math.clamp(top - floorY, 6, 30), hi.Z - lo.Z)
end

-- The room whose floor footprint contains a world point (nil = none).
function Core.roomAt(th: any, pos: Vector3): string?
	for _, room in th.order do
		local e = th.rooms[room]
		for _, p in e.floor do
			local rel = p.CFrame:PointToObjectSpace(pos)
			local h = p.Size / 2
			if math.abs(rel.X) <= h.X + 0.3 and math.abs(rel.Z) <= h.Z + 0.3 and rel.Y >= -h.Y - 1 and rel.Y <= h.Y + 14 then
				return room
			end
		end
	end
	return nil
end

-- frame turned by `rot` quarter turns about its own Y axis
function Core.rotated(frame: CFrame, rot: number?): CFrame
	local r = math.floor(rot or 0) % 4
	if r == 0 then
		return frame
	end
	return frame * CFrame.Angles(0, r * math.pi / 2, 0)
end

-- May the owner turn the piece in this slot? Builder slots say so (attribute Rotate); plain
-- BasePart slots (the fallback unit) follow HS.ROTATABLE_CATEGORIES.
function Core.slotCanRotate(container: any, category: string): boolean
	if container:IsA("Model") then
		return container:GetAttribute("Rotate") == true
	end
	local HSm = G and G.HOMES
	return HSm ~= nil and HSm.ROTATABLE_CATEGORIES[category] == true
end

-------------------------------------------------------------------------------------------------
-- Core: built-in fallback unit (used when ServerStorage.GwangalliHomes has no template for a tier;
-- follows the same contract as the builder's templates). Origin = floor centre; the door wall is
-- +Z, the window wall -Z.
-------------------------------------------------------------------------------------------------
-- slots: { id, category, x, z, yaw (deg), W, H, D, y0? }  fixtures: { kind, x, z, w, h, d, color }
local FALLBACK = {
	goshiwon = {
		W = 11, D = 13, H = 8.5, floor = { 196, 170, 130 }, wall = { 236, 232, 222 }, window = 3.4,
		slots = {
			{ "bed", "bed", -3.3, -1.6, 90, 3.4, 3.2, 6.8 },
			{ "desk", "desk", 3.6, -4.4, 0, 3.6, 3.8, 2.0 },
			{ "chair", "chair", 3.6, -2.6, 180, 1.8, 3.0, 1.8 },
			{ "shelf", "shelf", 4.7, 0.6, -90, 2.8, 5.4, 1.1 },
			{ "art", "art", -1.0, -6.3, 0, 2.4, 1.8, 0.3, 4.2 },
		},
		fixtures = {
			{ "wardrobe", 4.4, 3.8, 2.2, 6.4, 1.8, { 226, 222, 214 } },
			{ "fridge", 1.8, 5.2, 1.6, 3.4, 1.6, { 236, 238, 240 } },
			{ "shower", -4.1, 4.9, 2.6, 7, 2.6, { 200, 225, 235 } },
		},
	},
	oneroom = {
		W = 20, D = 22, H = 8.8, floor = { 176, 142, 104 }, wall = { 240, 238, 232 }, window = 7,
		slots = {
			{ "bed", "bed", -6.2, -6.0, 90, 4.6, 3.4, 7 },
			{ "sofa", "sofa", 3.2, 1.2, 180, 6.4, 3, 3 },
			{ "tv", "tv", 3.2, -6.6, 0, 5.4, 4.6, 1.5 },
			{ "table", "table", -5.0, 3.8, 0, 3.6, 2.5, 3.2 },
			{ "desk", "desk", 8.3, -3.2, -90, 4, 3.8, 2 },
			{ "chair", "chair", 6.6, -3.2, 90, 1.8, 3.0, 1.8 },
			{ "plant", "plant", 8.6, -9.4, 0, 1.6, 4, 1.6 },
			{ "rug", "rug", 3.2, -2.8, 0, 7, 0.1, 5 },
			{ "lamp", "lamp", -0.6, -9.6, 0, 1.3, 5.2, 1.3 },
			{ "art", "art", -6.2, -10.8, 0, 3, 2.2, 0.3, 4.4 },
		},
		fixtures = {
			{ "wardrobe", -8.6, 0.4, 2.4, 7, 4.2, { 214, 206, 196 } },
			{ "fridge", 1.2, 9.6, 2.2, 5.6, 2.2, { 230, 232, 236 } },
			{ "shower", -8.2, 8.6, 3.4, 7.4, 4.4, { 200, 225, 235 } },
		},
	},
	officetel = {
		W = 26, D = 26, H = 9.5, floor = { 150, 120, 92 }, wall = { 236, 236, 234 }, window = 12,
		slots = {
			{ "bed", "bed", -8.4, -7.0, 90, 5.2, 3.6, 7 },
			{ "sofa", "sofa", 4.2, 2.6, 180, 7, 3, 3.2 },
			{ "tv", "tv", 4.2, -7.8, 0, 6, 5, 1.6 },
			{ "table", "table", -7.2, 5.6, 0, 4.6, 2.5, 3.2 },
			{ "chair", "chair", -7.2, 3.1, 0, 1.8, 3.0, 1.8 },
			{ "desk", "desk", 11.4, -2.4, -90, 4.4, 4, 2.2 },
			{ "shelf", "shelf", 11.8, 5.4, -90, 3.2, 6, 1.3 },
			{ "plant", "plant", 11.4, -10.8, 0, 1.8, 4.4, 1.8 },
			{ "rug", "rug", 4.2, -2.6, 0, 8, 0.1, 6 },
			{ "lamp", "lamp", -2.4, -11.2, 0, 1.4, 5.4, 1.4 },
			{ "art", "art", -8.4, -12.8, 0, 3.6, 2.6, 0.3, 4.6 },
		},
		fixtures = {
			{ "wardrobe", -11.8, -0.2, 2.2, 7.4, 5, { 210, 204, 196 } },
			{ "fridge", 0.4, 11.8, 2.4, 6, 2.2, { 220, 222, 228 } },
			{ "shower", -10.8, 10.4, 4.2, 7.8, 5, { 200, 225, 235 } },
		},
	},
	apartment = {
		W = 38, D = 30, H = 9.5, floor = { 168, 132, 96 }, wall = { 244, 242, 236 }, window = 22,
		slots = {
			{ "bed", "bed", -13.6, -7.6, 90, 5.6, 3.8, 7.2 },
			{ "sofa", "sofa", 5.0, 3.6, 180, 8, 3, 3.4 },
			{ "tv", "tv", 5.0, -9.4, 0, 7, 5.4, 1.6 },
			{ "table", "table", -9.8, 7.2, 0, 6, 2.5, 3.6 },
			{ "chair", "chair", -9.8, 4.4, 0, 1.8, 3.0, 1.8 },
			{ "desk", "desk", -16.6, 1.4, 90, 4.4, 4, 2.2 },
			{ "shelf", "shelf", 17.6, 0.0, -90, 3.6, 6.4, 1.3 },
			{ "plant", "plant", 17.2, -12.6, 0, 2, 4.6, 2 },
			{ "plant2", "plant", -6.4, -12.8, 0, 1.6, 4, 1.6 },
			{ "rug", "rug", 5.0, -3.0, 0, 9, 0.1, 7 },
			{ "lamp", "lamp", 11.6, 4.0, 0, 1.4, 5.4, 1.4 },
			{ "art", "art", 5.0, 14.8, 180, 4.4, 3, 0.3, 4.4 },
			{ "art2", "art", -13.6, -14.8, 0, 3.6, 2.6, 0.3, 4.6 },
		},
		fixtures = {
			{ "wardrobe", -17.8, 10.8, 2.2, 7.6, 5.4, { 206, 198, 188 } },
			{ "fridge", 13.8, 13.6, 2.6, 6.4, 2.4, { 210, 212, 218 } },
			{ "shower", -1.2, 12.6, 5, 8, 4.4, { 200, 225, 235 } },
		},
	},
	penthouse = {
		W = 52, D = 40, H = 12, floor = { 226, 222, 214 }, wall = { 246, 244, 240 }, window = 40,
		slots = {
			{ "bed", "bed", -19.6, -10.4, 90, 6, 4.4, 7.4 },
			{ "sofa", "sofa", 6.0, 4.4, 180, 9, 3, 3.6 },
			{ "sofa2", "sofa", -3.6, -3.0, 90, 7, 3, 3.4 },
			{ "tv", "tv", 6.0, -12.4, 0, 8, 6, 1.6 },
			{ "table", "table", -13.6, 10.4, 0, 7, 2.5, 3.8 },
			{ "chair", "chair", -13.6, 7.4, 0, 1.9, 3.1, 1.9 },
			{ "desk", "desk", -23.6, 2.0, 90, 4.8, 4, 2.4 },
			{ "shelf", "shelf", 24.6, 0.0, -90, 4, 7, 1.4 },
			{ "plant", "plant", 24.2, -17.4, 0, 2.2, 5, 2.2 },
			{ "plant2", "plant", -10.4, -17.6, 0, 2, 4.6, 2 },
			{ "rug", "rug", 6.0, -4.0, 0, 11, 0.1, 8 },
			{ "lamp", "lamp", 13.4, 5.0, 0, 1.5, 5.6, 1.5 },
			{ "lamp2", "lamp", -21.8, -16.8, 0, 1.4, 5.4, 1.4 },
			{ "art", "art", 6.0, 19.8, 180, 6, 3.6, 0.3, 5 },
			{ "art2", "art", -19.6, -19.8, 0, 4, 3, 0.3, 5.4 },
		},
		fixtures = {
			{ "wardrobe", -24.8, 12.4, 2.4, 8.4, 7, { 200, 190, 176 } },
			{ "fridge", 20.0, 18.4, 3, 7, 2.6, { 200, 202, 208 } },
			{ "shower", -2.4, 17.2, 6, 9, 5, { 200, 225, 235 } },
		},
	},
}
Core.FALLBACK = FALLBACK

local function fpart(parent: any, name: string, size: any, cf: any, color: { number }, material: any, opts: { [string]: any }?): any
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = Color3.fromRGB(color[1], color[2], color[3])
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts then
		for k, v in opts do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function backdrop(parent: any, L: any, view: string)
	local bd = Instance.new("Model")
	bd.Name = "WindowView"
	local z0 = -L.D / 2
	local M = Enum.Material
	local noHit = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
	if view == "sea" then
		fpart(bd, "Sky", Vector3.new(520, 220, 2), CFrame.new(0, 60, z0 - 170), { 34, 52, 104 }, M.SmoothPlastic, noHit)
		fpart(bd, "SkyGlow", Vector3.new(520, 30, 1), CFrame.new(0, -10, z0 - 168), { 255, 140, 90 }, M.Neon, { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 0.55 })
		fpart(bd, "Sea", Vector3.new(520, 2, 170), CFrame.new(0, -40, z0 - 85), { 16, 46, 86 }, M.Glass, noHit)
		fpart(bd, "Beach", Vector3.new(520, 2, 24), CFrame.new(0, -39, z0 - 10), { 214, 196, 160 }, M.Sand, noHit)
		-- 광안대교: deck, two towers, cables and the LED strip
		fpart(bd, "BridgeDeck", Vector3.new(420, 3, 5), CFrame.new(0, -24, z0 - 130), { 150, 156, 166 }, M.Concrete, noHit)
		fpart(bd, "BridgeLED", Vector3.new(420, 0.8, 0.8), CFrame.new(0, -22.2, z0 - 127.4), { 120, 200, 255 }, M.Neon, noHit)
		for _, x in { -70, 70 } do
			fpart(bd, "BridgeTower", Vector3.new(4, 56, 4), CFrame.new(x, 2, z0 - 130), { 170, 176, 186 }, M.Concrete, noHit)
			fpart(bd, "TowerLight", Vector3.new(4.4, 1, 4.4), CFrame.new(x, 30, z0 - 130), { 190, 120, 255 }, M.Neon, noHit)
			for _, dir in { -1, 1 } do
				local a = Vector3.new(x, 29, z0 - 130)
				local b = Vector3.new(x + dir * 68, -22, z0 - 130)
				local mid = (a + b) / 2
				fpart(bd, "Cable", Vector3.new(0.5, 0.5, (b - a).Magnitude), CFrame.lookAt(mid, b), { 200, 210, 230 }, M.Neon, { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 0.25 })
			end
		end
		for i = 1, 14 do
			local x = -240 + i * 32
			local h = 18 + (i * 37) % 30
			fpart(bd, "FarTower", Vector3.new(14, h, 10), CFrame.new(x, -38 + h / 2, z0 - 160), { 40, 46, 64 }, M.SmoothPlastic, noHit)
			fpart(bd, "FarLights", Vector3.new(10, 1, 0.5), CFrame.new(x, -38 + h * 0.6, z0 - 154.6), { 255, 214, 140 }, M.Neon, noHit)
		end
	else
		fpart(bd, "Sky", Vector3.new(160, 120, 2), CFrame.new(0, 50, z0 - 40), { 60, 84, 130 }, M.SmoothPlastic, noHit)
		fpart(bd, "OppositeWall", Vector3.new(120, 90, 2), CFrame.new(0, -10, z0 - 14), { 150, 110, 90 }, M.Brick, noHit)
		for r = 0, 3 do
			for c = -3, 3 do
				local lit = ((r * 7 + c * 3) % 4) == 0
				fpart(bd, "AlleyWindow", Vector3.new(5, 4, 0.4), CFrame.new(c * 12, -26 + r * 11, z0 - 12.9), if lit then { 255, 214, 140 } else { 60, 70, 84 }, if lit then M.Neon else M.Glass, noHit)
			end
		end
		fpart(bd, "Sign", Vector3.new(10, 3, 0.4), CFrame.new(-18, 8, z0 - 12.8), { 255, 90, 120 }, M.Neon, noHit)
		fpart(bd, "Pipe", Vector3.new(1, 90, 1), CFrame.new(20, -10, z0 - 12.6), { 90, 90, 96 }, M.Metal, noHit)
	end
	bd.Parent = parent
end

-- Builds the fallback unit Model for a tier key.
function Core.fallbackTemplate(tierKey: string): any
	local L = FALLBACK[tierKey] or FALLBACK.oneroom
	local T = G.HomeTags
	local M = Enum.Material
	local model = Instance.new("Model")
	model.Name = "HomeUnit_" .. tierKey
	model:SetAttribute("Fallback", true)
	local W, D, H = L.W, L.D, L.H
	local root = fpart(model, "UnitRoot", Vector3.new(1, 0.2, 1), CFrame.new(0, 0.1, 0), { 255, 255, 255 }, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false })
	model.PrimaryPart = root
	local shell = Instance.new("Model")
	shell.Name = "Shell"
	shell.Parent = model
	fpart(shell, "Floor", Vector3.new(W + 1, 1, D + 1), CFrame.new(0, -0.5, 0), L.floor, M.WoodPlanks)
	fpart(shell, "Ceiling", Vector3.new(W + 1, 1, D + 1), CFrame.new(0, H + 0.5, 0), { 246, 246, 244 }, M.SmoothPlastic, { CastShadow = false })
	local wt = 1
	fpart(shell, "Wall", Vector3.new(wt, H, D + 1), CFrame.new(-W / 2 - wt / 2, H / 2, 0), L.wall, M.Plaster)
	fpart(shell, "Wall", Vector3.new(wt, H, D + 1), CFrame.new(W / 2 + wt / 2, H / 2, 0), L.wall, M.Plaster)
	-- door wall (+Z) with the exit door
	local doorW, doorH = 3.2, 7
	local doorX = W / 2 - 3
	fpart(shell, "Wall", Vector3.new(W + 2, H - doorH, wt), CFrame.new(0, doorH + (H - doorH) / 2, D / 2 + wt / 2), L.wall, M.Plaster)
	local leftW = (doorX - doorW / 2) + W / 2 + 1
	fpart(shell, "Wall", Vector3.new(leftW, doorH, wt), CFrame.new(-W / 2 - 1 + leftW / 2, doorH / 2, D / 2 + wt / 2), L.wall, M.Plaster)
	local rightW = W / 2 + 1 - (doorX + doorW / 2)
	fpart(shell, "Wall", Vector3.new(rightW, doorH, wt), CFrame.new(W / 2 + 1 - rightW / 2, doorH / 2, D / 2 + wt / 2), L.wall, M.Plaster)
	local door = fpart(model, "ExitDoor", Vector3.new(doorW, doorH, 0.4), CFrame.new(doorX, doorH / 2, D / 2 + 0.2) * CFrame.Angles(0, math.pi, 0), { 120, 92, 70 }, M.Wood)
	fpart(shell, "DoorHandle", Vector3.new(0.3, 0.3, 0.5), CFrame.new(doorX - doorW / 2 + 0.5, 3.4, D / 2 - 0.1), { 210, 190, 120 }, M.Metal, { CanCollide = false })
	-- window wall (-Z): sill + lintel + sides around the glass
	local ww = math.min(L.window, W - 2)
	local sill, top = if tierKey == "penthouse" then 0.4 else 2.6, H - (if tierKey == "penthouse" then 0.4 else 1.4)
	fpart(shell, "Wall", Vector3.new(W + 2, sill, wt), CFrame.new(0, sill / 2, -D / 2 - wt / 2), L.wall, M.Plaster)
	fpart(shell, "Wall", Vector3.new(W + 2, H - top, wt), CFrame.new(0, top + (H - top) / 2, -D / 2 - wt / 2), L.wall, M.Plaster)
	local side = (W + 2 - ww) / 2
	for _, sx in { -1, 1 } do
		fpart(shell, "Wall", Vector3.new(side, top - sill, wt), CFrame.new(sx * (ww / 2 + side / 2), sill + (top - sill) / 2, -D / 2 - wt / 2), L.wall, M.Plaster)
	end
	local glass = fpart(shell, "WindowGlass", Vector3.new(ww, top - sill, 0.2), CFrame.new(0, sill + (top - sill) / 2, -D / 2 - wt / 2), { 200, 225, 240 }, M.Glass, { Transparency = 0.75, CastShadow = false })
	local win = fpart(model, "WindowSpot", Vector3.new(math.min(ww, 6), 3, 1), CFrame.new(0, sill + 2, -D / 2 + 1.2), { 255, 255, 255 }, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false })
	win:SetAttribute("Kind", "window")
	win:AddTag(T.Interact)
	local _ = glass
	-- ceiling lights
	local nx = math.max(1, math.floor(W / 14))
	local nz = math.max(1, math.floor(D / 14))
	for i = 1, nx do
		for j = 1, nz do
			local lamp = fpart(shell, "CeilingLight", Vector3.new(2.4, 0.2, 2.4), CFrame.new(-W / 2 + W * (i - 0.5) / nx, H - 0.1, -D / 2 + D * (j - 0.5) / nz), { 255, 246, 226 }, M.Neon, { CanCollide = false, CastShadow = false })
			local light = Instance.new("PointLight")
			light.Range = 22
			light.Brightness = 1.1
			light.Color = Color3.fromRGB(255, 236, 206)
			light.Shadows = false
			light.Parent = lamp
		end
	end
	-- spawn: inside the door, facing the window
	fpart(model, "Spawn", Vector3.new(2, 0.2, 2), CFrame.new(doorX, 0.1, D / 2 - 3), { 255, 255, 255 }, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false })
	-- mailbox by the door
	local mail = fpart(model, "Mailbox", Vector3.new(1.4, 1.6, 0.6), CFrame.new(doorX + doorW / 2 + 1.2, 4, D / 2 - 0.3), { 70, 110, 170 }, M.Metal, { CanCollide = false })
	mail:SetAttribute("Kind", "mailbox")
	mail:AddTag(T.Interact)
	-- fixtures
	local fx = Instance.new("Model")
	fx.Name = "Fixtures"
	fx.Parent = model
	for _, f in L.fixtures do
		local kind, x, z, w, h, d, color = f[1], f[2], f[3], f[4], f[5], f[6], f[7]
		local cf = CFrame.new(x, h / 2, z)
		if kind == "shower" then
			fpart(fx, "ShowerTray", Vector3.new(w, 0.3, d), CFrame.new(x, 0.15, z), { 236, 240, 244 }, M.Marble)
			for _, sx in { -1, 1 } do
				fpart(fx, "ShowerGlass", Vector3.new(0.15, h, d), CFrame.new(x + sx * w / 2, h / 2, z), color, M.Glass, { Transparency = 0.6, CastShadow = false })
			end
			fpart(fx, "ShowerHead", Vector3.new(0.8, 0.2, 0.8), CFrame.new(x, h - 0.6, z), { 200, 200, 204 }, M.Metal, { CanCollide = false })
			local sp = fpart(model, "ShowerSpot", Vector3.new(w - 0.4, 2, d - 0.4), CFrame.new(x, 1.2, z), { 255, 255, 255 }, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false })
			sp:SetAttribute("Kind", "shower")
			sp:AddTag(T.Interact)
		else
			local body = fpart(fx, if kind == "fridge" then "Fridge" else "Wardrobe", Vector3.new(w, h, d), cf, color, if kind == "fridge" then M.Metal else M.Wood)
			fpart(fx, "Handle", Vector3.new(0.15, 1.4, 0.2), CFrame.new(x + w / 2 - 0.3, h * 0.6, z) * CFrame.new(0, 0, if z > 0 then -d / 2 - 0.1 else d / 2 + 0.1), { 190, 190, 196 }, M.Metal, { CanCollide = false })
			body:SetAttribute("Kind", kind)
			body:AddTag(T.Interact)
		end
	end
	-- furniture slots with their default (이케아풍) furniture
	for _, s in L.slots do
		local id, cat, x, z, yaw, sw, sh, sd, y0 = s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9] or 0
		local frame = CFrame.new(x, y0, z) * CFrame.Angles(0, math.rad(yaw), 0)
		local slot = fpart(model, "Slot_" .. id, Vector3.new(sw, math.max(0.1, sh), sd), frame * CFrame.new(0, math.max(0.1, sh) / 2, 0), { 90, 200, 255 }, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false })
		slot:SetAttribute("SlotId", id)
		slot:SetAttribute("Category", cat)
		slot:AddTag(T.Slot)
		local list = G.furnitureFor(cat)
		local def = list[1] and list[1].id
		local spec = def and G.furnitureSpec(def, sw, math.max(0.1, sh), sd)
		if spec then
			local m, extra = Core.buildSpec(spec, frame, slot, "Default_" .. id)
			m:SetAttribute("Default", true)
			local kind = if cat == "bed" then "bed" elseif cat == "sofa" and id == "sofa" then "sofa" elseif cat == "tv" then "tv" elseif cat == "desk" then "desk" elseif cat == "table" then "table" else nil
			if kind then
				local hot = fpart(m, "Interact_" .. kind, Vector3.new(math.min(sw, 3), 1.5, math.min(sd, 3)), frame * CFrame.new(0, math.min(sh, 3) * 0.6, 0), { 255, 255, 255 }, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false })
				hot:SetAttribute("Kind", kind)
				hot:AddTag(T.Interact)
			end
			local _ = extra
		end
	end
	backdrop(model, L, G.HOME_TIERS[tierKey] and G.HOME_TIERS[tierKey].view or "alley")
	local _ = door
	return model
end

-------------------------------------------------------------------------------------------------
-- Runtime state
-------------------------------------------------------------------------------------------------
type SlotRec = {
	id: string,
	category: string,
	part: BasePart,
	container: Instance,
	geo: any,
	default: Instance?,
	defaultParent: Instance?,
	current: string?,
	model: Model?,
	seat: Seat?,
	bed: CFrame?,
	rot: number,
	canRotate: boolean,
	defaultPivot: CFrame?,
	lights: number,
	room: string?,
}
type Inst = {
	owner: Player,
	ownerId: number,
	listingId: string,
	tierKey: string,
	index: number,
	model: Model,
	hidden: Folder,
	root: BasePart,
	spawn: BasePart?,
	exit: BasePart?,
	slots: { [string]: SlotRec },
	slotOrder: { string },
	interacts: { { part: BasePart, kind: string, prompt: ProximityPrompt?, useCF: CFrame?, pose: string? } },
	interior: { cf: CFrame, size: Vector3 },
	seats: { [BasePart]: Seat },
	occupants: { [Player]: string },
	entry: { [Player]: BasePart? },
	tvOn: boolean,
	emptySince: number?,
	bboxCF: CFrame,
	bboxSize: Vector3,
	food: Model?,
	fallback: boolean,
	themes: any,
	staged: boolean,
	returnCF: { [Player]: CFrame },
	compliments: { [Player]: number },
}
type HSess = {
	tvT: number,
	tvNotified: number,
	lastEat: number,
	lastPhoto: number,
	delivery: { menuId: string, at: number }?,
	pendingFood: string?,
	posing: boolean,
}

local instances: { [Player]: Inst } = {}
local staged: { [Player]: Inst } = {} -- 매물 둘러보기: an empty unit of a listing, one per viewer
local usedIndex: { [number]: Inst } = {}
local where: { [Player]: Inst } = {}
local visits = Core.newVisits()
local entrances: { [BasePart]: string } = {}
local fallbackEntrances: { [string]: BasePart } = {}
local hsess: { [Player]: HSess } = {}
local remotes: { [string]: any } = {}
local instFolder: Folder? = nil
local hiddenRoot: Folder? = nil
local fallbackCache: { [string]: Model } = {}
local warnedTier: { [string]: boolean } = {}

local function HS(player: Player): HSess
	local s = hsess[player]
	if not s then
		s = { tvT = 0, tvNotified = 0, lastEat = -math.huge, lastPhoto = -math.huge, delivery = nil, pendingFood = nil, posing = false }
		hsess[player] = s
	end
	return s
end

local function won(n: number): string
	return G.format.won(n)
end

local function send(player: Player, payload: any)
	if player.Parent == Players and remotes.HomeState then
		remotes.HomeState:FireClient(player, payload)
	end
end

local function sendAll(inst: Inst, payload: any)
	for p in inst.occupants do
		send(p, payload)
	end
end

local function tierName(key: string): string
	local t = G.HOME_TIERS[key]
	return t and t.name or key
end

local function setAttrs(player: Player, ownerId: number, role: string)
	if player.Parent == Players then
		player:SetAttribute("InHome", ownerId)
		player:SetAttribute("HomeRole", role)
	end
end

-------------------------------------------------------------------------------------------------
-- Entrances (map)
-------------------------------------------------------------------------------------------------
local function entranceTier(part: Instance): string?
	return G.homeTierKey(part:GetAttribute("Tier"))
end

local function entranceAdded(inst: Instance)
	if not inst:IsA("BasePart") or not inst:IsDescendantOf(workspace) then
		return
	end
	local key = entranceTier(inst)
	if not key then
		Util.warnOnce("homeEntrTier:" .. inst:GetFullName(), "[GwangalliGameplay] HomeEntrance without a valid Tier: " .. inst:GetFullName())
		return
	end
	entrances[inst] = key
	local fb = fallbackEntrances[key]
	if fb and fb ~= inst and inst:GetAttribute("Fallback") ~= true then
		fallbackEntrances[key] = nil
		fb:Destroy()
	end
end

local function entranceRemoved(inst: Instance)
	entrances[inst :: any] = nil
end

-- All entrances of a tier.
local function entrancesOf(key: string): { BasePart }
	local out = {}
	for part, k in entrances do
		if k == key and part.Parent then
			table.insert(out, part)
		end
	end
	return out
end

-- Nearest entrance of `key` to `pos` (or the first).
local function entranceFor(key: string, pos: Vector3?, preferred: BasePart?): BasePart?
	if preferred and preferred.Parent and entrances[preferred] == key then
		return preferred
	end
	local best, bestD = nil, math.huge
	for _, part in entrancesOf(key) do
		local dd = if pos then (part.Position - pos).Magnitude else 0
		if dd < bestD then
			best, bestD = part, dd
		end
	end
	if best then
		return best
	end
	local lid, l = G.listingForTier(key)
	local dest = l and ctx.dest(l.place) or nil
	local _ = lid
	return dest
end

local function nearEntrance(player: Player, key: string): BasePart?
	local pos = Util.rootPosition(player)
	if not pos then
		return nil
	end
	for _, part in entrancesOf(key) do
		local reach = G.HOME_ENTRANCE_REACH + math.min(12, math.max(part.Size.X, part.Size.Z) / 2)
		if (part.Position - pos).Magnitude <= reach then
			return part
		end
	end
	return nil
end

-- Tiers without a HomeEntrance in the map get one at the listing's Destination.
local function ensureFallbackEntrances()
	local folder = workspace:FindFirstChild("GwangalliHomeEntrances")
	for _, key in G.HOME_TIER_ORDER do
		local has = false
		for part, k in entrances do
			if k == key and part.Parent and part:GetAttribute("Fallback") ~= true then
				has = true
				break
			end
		end
		if not has and not fallbackEntrances[key] then
			local _, l = G.listingForTier(key)
			local dest = l and ctx.dest(l.place)
			if dest then
				if not folder then
					folder = Instance.new("Folder")
					folder.Name = "GwangalliHomeEntrances"
					folder.Parent = workspace
				end
				local p = Instance.new("Part")
				p.Name = "HomeEntrance_" .. key
				p.Size = Vector3.new(4, 7, 1)
				p.CFrame = dest.CFrame * CFrame.new(0, 3.5 - dest.Size.Y / 2, 0)
				p.Transparency = 1
				p.Anchored = true
				p.CanCollide = false
				p.CanTouch = false
				p.CanQuery = false
				p:SetAttribute("Tier", key)
				p:SetAttribute("DisplayName", l.place)
				p:SetAttribute("Fallback", true)
				fallbackEntrances[key] = p
				p.Parent = folder
				p:AddTag(G.HomeTags.Entrance)
				entrances[p] = key
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Templates / instances
-------------------------------------------------------------------------------------------------
local function templateFor(key: string): (Model?, boolean)
	local folder = ServerStorage:FindFirstChild(G.HOME_TEMPLATE_FOLDER)
	local names = { "HomeUnit_" .. key, "HomeUnit_" .. tostring(G.homeTierNumber(key)) }
	if folder then
		for _, n in names do
			local m = folder:FindFirstChild(n)
			if m and m:IsA("Model") then
				return m, false
			end
		end
	end
	local cached = fallbackCache[key]
	if cached then
		return cached, true
	end
	if not warnedTier[key] then
		warnedTier[key] = true
		print(string.format("[GwangalliGameplay] no ServerStorage.%s.HomeUnit_%s template; using the built-in fallback unit", G.HOME_TEMPLATE_FOLDER, key))
	end
	local ok, m = pcall(Core.fallbackTemplate, key)
	if not ok then
		warn("[GwangalliGameplay] fallback home unit failed: " .. tostring(m))
		return nil, true
	end
	fallbackCache[key] = m
	return m, true
end

local function rescanScreens(inst: Inst): { BasePart }
	local out = {}
	for _, d in inst.model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Screen" or d.Name == "TVScreen") then
			table.insert(out, d)
		end
	end
	return out
end

local function applyTv(inst: Inst)
	inst.model:SetAttribute("TvOn", inst.tvOn)
	for _, scr in rescanScreens(inst) do
		if scr:GetAttribute("OffColor") == nil then
			scr:SetAttribute("OffColor", scr.Color)
			scr:SetAttribute("OffMaterial", scr.Material.Name)
		end
		if inst.tvOn then
			scr.Material = Enum.Material.Neon
			scr.Color = Color3.fromRGB(70, 120, 200)
		else
			local c = scr:GetAttribute("OffColor")
			scr.Color = if typeof(c) == "Color3" then c else Color3.fromRGB(12, 12, 16)
			local okM, mat = pcall(function()
				return (Enum.Material :: any)[scr:GetAttribute("OffMaterial")]
			end)
			scr.Material = if okM and mat then mat else Enum.Material.Glass
		end
	end
	for _, it in inst.interacts do
		if it.kind == "tv" and it.prompt then
			it.prompt.ActionText = if inst.tvOn then "TV 끄기" else ((it :: any).label or "TV 켜기")
		end
	end
end

-- Real lights the placed furniture of an instance carries, without slot `except`.
local function furnitureLights(inst: Inst, except: SlotRec?): number
	local n = 0
	for _, r in inst.slots do
		if r ~= except then
			n += r.lights or 0
		end
	end
	return n
end

local function isRotAllowed(rec: SlotRec, isDefault: boolean, rot: number): boolean
	local HSm = G.HOMES
	if not HSm then
		return rot % 4 == 0
	end
	return HSm.rotationAllowed(rec.canRotate, isDefault, rec.geo.w, rec.geo.d, rot)
end

-- Places a variant (or the default when nil) into a slot of an instance, turned `rot` quarter turns
-- (nil keeps the slot's current turn). Generated pieces are rebuilt in the swapped envelope for odd
-- turns so they stay inside the footprint; the template's default piece is pivoted about the slot.
local function applySlot(inst: Inst, rec: SlotRec, variantId: string?, rot: number?)
	if rec.model then
		rec.model:Destroy()
		rec.model = nil
		rec.seat = nil
		rec.bed = nil
	end
	rec.lights = 0
	local r = math.floor(rot or rec.rot or 0) % 4
	local f = variantId and G.FURNITURE[variantId]
	local geo = rec.geo
	if variantId and f and f.category == rec.category then
		if not isRotAllowed(rec, false, r) then
			r = 0
		end
		if rec.default and rec.default.Parent ~= inst.hidden then
			rec.default.Parent = inst.hidden
		end
		local w, d = geo.w, geo.d
		if r % 2 == 1 then
			w, d = d, w
		end
		local spec = G.furnitureSpec(variantId, w, geo.h, d)
		if spec then
			local HSm = G.HOMES
			local cap = (if HSm then HSm.FURNITURE_LIGHTS else 3) - furnitureLights(inst, rec)
			local ok, m, extra = pcall(Core.buildSpec, spec, Core.rotated(geo.frame, r), rec.container, "Furniture_" .. rec.id, math.max(0, cap))
			if ok and m then
				m:SetAttribute("Variant", variantId)
				m:SetAttribute("Rot", r)
				rec.model = m
				rec.seat = extra.seat
				rec.bed = extra.bed
				rec.lights = extra.lights or 0
			else
				warn("[GwangalliGameplay] furniture build failed: " .. tostring(m))
			end
		end
		rec.current = variantId
	else
		if not isRotAllowed(rec, true, r) then
			r = 0
		end
		if rec.default and rec.defaultParent and rec.default.Parent ~= rec.defaultParent then
			rec.default.Parent = rec.defaultParent
		end
		if rec.default and rec.defaultPivot and rec.default:IsA("Model") then
			local base = rec.defaultPivot :: CFrame
			pcall(function()
				(rec.default :: Model):PivotTo(Core.rotated(geo.frame, r) * geo.frame:ToObjectSpace(base))
			end)
		end
		rec.current = nil
	end
	rec.rot = r
	applyTv(inst)
end

local function furnitureList(inst: Inst): { any }
	local out = {}
	for _, id in inst.slotOrder do
		local rec = inst.slots[id]
		local geo = rec.geo
		table.insert(out, {
			slotId = id,
			category = rec.category,
			variantId = rec.current or false,
			rot = rec.rot or 0,
			canRotate = rec.canRotate == true,
			room = rec.room or false,
			w = geo.w,
			h = geo.h,
			d = geo.d,
		})
	end
	return out
end

local function guestList(inst: Inst): { any }
	local out = {}
	for p, role in inst.occupants do
		if role == "guest" then
			table.insert(out, { userId = p.UserId, name = p.DisplayName })
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

local function guestCount(inst: Inst): number
	local n = 0
	for _, role in inst.occupants do
		if role == "guest" then
			n += 1
		end
	end
	return n
end

local onInteract: (Player, Inst, string, BasePart) -> ()

local function makePrompt(part: BasePart, action: string, object: string, hold: number?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "HomePrompt"
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold or 0
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	pp.Parent = part
	return pp
end

local function destroyInstance(inst: Inst)
	if instances[inst.owner] == inst then
		instances[inst.owner] = nil
	end
	if staged[inst.owner] == inst then
		staged[inst.owner] = nil
	end
	if usedIndex[inst.index] == inst then
		usedIndex[inst.index] = nil
	end
	for p in inst.occupants do
		if where[p] == inst then
			where[p] = nil
			setAttrs(p, 0, "")
		end
	end
	pcall(function()
		inst.model:Destroy()
	end)
	pcall(function()
		inst.hidden:Destroy()
	end)
end

-- Grid spacing from the templates' view extents (ViewExtent attribute, else the bounding box).
local homeSpacing: { number } = { 0, 0 }
local function extentOf(m: Model): Vector3
	local ve = m:GetAttribute("ViewExtent")
	if typeof(ve) == "Vector3" then
		return ve
	end
	local ok, _, size = pcall(m.GetBoundingBox, m)
	if ok then
		return size / 2
	end
	return Vector3.new(300, 150, 300)
end
local function computeSpacing()
	local mx = Vector3.new(300, 160, 240) -- the built-in fallback unit with its view
	local folder = ServerStorage:FindFirstChild(G.HOME_TEMPLATE_FOLDER)
	for _, m in (folder and folder:GetChildren() or {}) do
		if m:IsA("Model") then
			mx = mx:Max(extentOf(m))
		end
	end
	homeSpacing = G.homeSpacingFor({ mx.X, mx.Y, mx.Z })
end

-- Interior bounds (everything but the window view), for the fell-out / moved-away checks.
local function interiorBounds(model: Model, root: BasePart): (CFrame, Vector3)
	local frame = CFrame.new(root.Position) * root.CFrame.Rotation
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local view = model:FindFirstChild("Backdrop") or model:FindFirstChild("WindowView")
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and not (view and p:IsDescendantOf(view)) then
			local rel = frame:PointToObjectSpace(p.Position)
			local h = p.Size / 2
			local r = math.max(h.X, h.Y, h.Z)
			lo = lo:Min(rel - Vector3.new(r, r, r))
			hi = hi:Max(rel + Vector3.new(r, r, r))
		end
	end
	if lo.X == math.huge then
		return frame, Vector3.new(80, 40, 80)
	end
	local size = (hi - lo):Min(Vector3.new(400, 200, 400))
	return frame * CFrame.new((lo + hi) / 2), size
end

-- Builds an instance of the tier `key` for `owner`: their home (unit = the saved record of the
-- listing) or, with isStaged, an empty 둘러보기 unit (template furniture only, no themes).
local function buildInstance(owner: Player, listingId: string, key: string, unit: any, isStaged: boolean): Inst?
	local tpl, isFallback = templateFor(key)
	if not tpl then
		return nil
	end
	local ok, model = pcall(function()
		return tpl:Clone()
	end)
	if not ok or not model then
		warn("[GwangalliGameplay] home template clone failed: " .. tostring(model))
		return nil
	end
	model.Name = (if isStaged then "Tour_" else "Home_") .. tostring(owner.UserId)
	for _, sc in model:GetDescendants() do
		if sc:IsA("Script") or sc:IsA("LocalScript") then
			sc:Destroy() -- templates are geometry only
		end
	end
	local info = Core.scanUnit(model)
	local root = info.root
	if not root then
		root = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not root then
		model:Destroy()
		warn("[GwangalliGameplay] home template " .. key .. " has no parts")
		return nil
	end
	pcall(function()
		model.PrimaryPart = root
	end)
	local index = Core.allocIndex(usedIndex)
	if homeSpacing[1] <= 0 then
		computeSpacing()
	end
	local x, y, z = G.homeSlotPosition(index, homeSpacing)
	local target = CFrame.new(x, y, z) * root.CFrame.Rotation
	local pivotOffset = root.CFrame:ToObjectSpace(model:GetPivot())
	model:PivotTo(target * pivotOffset)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			if p:IsA("Seat") then
				p.Disabled = false -- templates save seats Disabled; Housing sits avatars via Seat:Sit()
			end
		end
	end
	Core.proxifyInteracts(model, info)
	local hidden = Instance.new("Folder")
	hidden.Name = model.Name
	hidden.Parent = hiddenRoot
	local inst: Inst = {
		owner = owner,
		ownerId = owner.UserId,
		listingId = listingId,
		tierKey = key,
		index = index,
		model = model,
		hidden = hidden,
		root = root,
		spawn = info.spawn,
		exit = info.exit,
		slots = {},
		slotOrder = {},
		interacts = {},
		seats = {},
		occupants = {},
		entry = {},
		tvOn = false,
		emptySince = os.clock(),
		bboxCF = CFrame.new(x, y, z),
		bboxSize = Vector3.new(80, 40, 80),
		interior = { cf = CFrame.new(x, y, z), size = Vector3.new(80, 40, 80) },
		food = nil,
		fallback = isFallback,
		themes = { rooms = {}, order = {}, orig = {} },
		staged = isStaged,
		returnCF = {},
		compliments = {},
	}
	usedIndex[index] = inst
	if isStaged then
		staged[owner] = inst
	else
		instances[owner] = inst
	end
	pcall(function()
		(model :: any).ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	end)
	pcall(function()
		(model :: any):AddPersistentPlayer(owner)
	end)
	model:SetAttribute("HomeOwnerId", owner.UserId)
	model:SetAttribute("HomeTier", key)
	model:SetAttribute("HomeListing", listingId)
	model:SetAttribute("TvOn", false)
	if isStaged then
		model:SetAttribute("Staged", true)
	end
	model.Parent = instFolder
	local okB, bcf, bsize = pcall(interiorBounds, model, root)
	if okB then
		inst.bboxCF, inst.bboxSize = bcf, bsize
		inst.interior = { cf = bcf, size = bsize }
	end
	-- 인테리어 themes (rooms of the template) + the saved 벽지 / 바닥 / 조명
	local view = model:FindFirstChild("Backdrop") or model:FindFirstChild("WindowView")
	local okT, th = pcall(Core.collectThemes, model, view)
	if okT and th then
		inst.themes = th
		if unit and not isStaged then
			local okA, errA = pcall(Core.applyThemes, th, unit)
			if not okA then
				warn("[GwangalliGameplay] home themes failed: " .. tostring(errA))
			end
		end
	end
	-- slots + saved furniture (+ quarter turns)
	local HSm = G.HOMES
	for _, s in info.slots do
		local sp: BasePart = s.part
		sp.Transparency = 1
		sp.CanCollide = false
		sp.CanTouch = false
		pcall(function()
			sp.CanQuery = false
		end)
		local geo = G.slotGeometry(s.container)
		if not geo then
			continue
		end
		local defPivot: CFrame? = nil
		if s.default and s.default:IsA("Model") then
			local okP, pv = pcall(s.default.GetPivot, s.default)
			defPivot = if okP then pv else nil
		end
		local roomAttr = s.container:GetAttribute("Room")
		local room = if type(roomAttr) == "string" and inst.themes.rooms[roomAttr] then roomAttr else Core.roomAt(inst.themes, (geo.frame * CFrame.new(0, 0.5, 0)).Position)
		local rec: SlotRec = {
			id = s.id,
			category = s.category,
			part = sp,
			container = s.container,
			geo = geo,
			default = s.default,
			defaultParent = s.default and s.default.Parent or nil,
			current = nil,
			model = nil,
			seat = nil,
			bed = nil,
			rot = 0,
			canRotate = Core.slotCanRotate(s.container, s.category),
			defaultPivot = defPivot,
			lights = 0,
			room = room,
		}
		inst.slots[s.id] = rec
		table.insert(inst.slotOrder, s.id)
		if unit and not isStaged then
			local saved = unit.slots and unit.slots[s.id]
			local rot = if HSm then HSm.rotOf(unit, s.id) else 0
			if saved or rot ~= 0 then
				applySlot(inst, rec, saved, rot)
			end
		end
	end
	-- interaction prompts
	for _, it in info.interacts do
		local k = G.HOME_KINDS[it.kind]
		local lbl = it.part:GetAttribute("Label")
		local action = if type(lbl) == "string" and lbl ~= "" and #lbl <= 60 then lbl else k.action
		local prompt = makePrompt(it.part, action, k.object, k.hold)
		local ua = it.part:FindFirstChild("UseAt")
		local useCF: CFrame? = nil
		local pose: string? = nil
		if ua and ua:IsA("Attachment") then
			useCF = ua.WorldCFrame
			local ps = ua:GetAttribute("Pose")
			pose = if type(ps) == "string" then ps else nil
		end
		local rec = { part = it.part, kind = it.kind, prompt = prompt, useCF = useCF, pose = pose, label = action }
		table.insert(inst.interacts, rec)
		prompt.Triggered:Connect(function(player: Player)
			local okI, err = pcall(onInteract, player, inst, it.kind, it.part)
			if not okI then
				warn("[GwangalliGameplay] home interaction failed: " .. tostring(err))
			end
		end)
	end
	if inst.exit and not inst.exit:HasTag(G.HomeTags.Interact) then
		local prompt = makePrompt(inst.exit, "나가기", "현관")
		prompt.Triggered:Connect(function(player: Player)
			local okI, err = pcall(onInteract, player, inst, "door", inst.exit :: BasePart)
			if not okI then
				warn("[GwangalliGameplay] home exit failed: " .. tostring(err))
			end
		end)
	end
	applyTv(inst)
	return inst
end

local function createInstance(owner: Player, d: any): Inst?
	local key = G.homeTierKey(d.home.tier)
	if not key then
		return nil
	end
	local h = G.ensureHousing(d)
	return buildInstance(owner, d.home.listingId, key, h.units[d.home.listingId], false)
end

local function ensureInstance(owner: Player, d: any): Inst?
	local inst = instances[owner]
	if inst and inst.model.Parent and inst.listingId == (d.home and d.home.listingId) then
		return inst
	end
	if inst then
		destroyInstance(inst)
	end
	if not d.home then
		return nil
	end
	return createInstance(owner, d)
end

-------------------------------------------------------------------------------------------------
-- Occupancy
-------------------------------------------------------------------------------------------------
local function spawnPart(inst: Inst): BasePart
	return inst.spawn or inst.root
end

local function attach(player: Player, inst: Inst, role: string, entry: BasePart?)
	local prev = where[player]
	if prev and prev ~= inst then
		prev.occupants[player] = nil
		prev.entry[player] = nil
	end
	where[player] = inst
	inst.occupants[player] = role
	inst.entry[player] = entry
	inst.emptySince = nil
	setAttrs(player, inst.ownerId, role)
	if role == "guest" then
		pcall(function()
			(inst.model :: any):AddPersistentPlayer(player)
		end)
	end
	if Life and Life.session then
		Life.session(player).inUnit = role == "owner"
	end
end

local function unseat(player: Player)
	local _, humanoid = Util.alive(player)
	if humanoid and humanoid.SeatPart then
		humanoid.Sit = false
		local weld = humanoid.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
end

-- Removes the player from their current instance (no teleport).
local function detach(player: Player, silent: boolean?)
	local inst = where[player]
	if not inst then
		return
	end
	where[player] = nil
	local role = inst.occupants[player]
	inst.occupants[player] = nil
	inst.entry[player] = nil
	setAttrs(player, 0, "")
	if role == "guest" then
		pcall(function()
			(inst.model :: any):RemovePersistentPlayer(player)
		end)
	end
	if next(inst.occupants) == nil then
		inst.emptySince = os.clock()
	end
	if Life and Life.session then
		Life.session(player).inUnit = false
	end
	local s = hsess[player]
	if s then
		s.tvT = 0
	end
	if not silent then
		send(player, { kind = "exit" })
	end
	if role == "guest" then
		sendAll(inst, { kind = "guests", guests = guestList(inst), maxGuests = G.homeGuestLimit(inst.tierKey) })
	end
end

local function canTeleport(player: Player): boolean
	if ctx.isRiding(player) then
		ctx.notify(player, "info", "택시 이용 중", "택시에서 내린 뒤 이용해 주세요")
		return false
	end
	if ctx.venueBusy(player) then
		return false
	end
	if HS(player).posing then
		return false
	end
	-- no hiding from the police inside a sky instance (GwangalliCombatShared attributes; absent = fine)
	local wanted = player:GetAttribute("Wanted")
	local char = player.Character
	if (type(wanted) == "number" and wanted > 0) or player:GetAttribute("Arrested") == true or player:GetAttribute("PoliceChase") == true or (char and char:GetAttribute("GwKO") == true) then
		ctx.notify(player, "info", "지금은 이동할 수 없어요", "수배 중이거나 쓰러진 상태에서는 집에 들어갈 수 없어요")
		return false
	end
	return true
end

-- The viewer's staged 둘러보기 unit (if any) is no longer needed.
local function releaseStaged(player: Player)
	local st = staged[player]
	if st then
		destroyInstance(st)
	end
end

local function teleportInto(player: Player, part: BasePart, fade: boolean, caption: string?): boolean
	if fade then
		Util.fade(player, true, 0.35, caption)
	end
	ctx.allowTeleport(player, 8)
	ctx.jobsResetPosition(player)
	unseat(player)
	local ok = Util.teleportTo(player, part, 6)
	if fade then
		task.spawn(Util.fade, player, false, 0.45)
	end
	return ok
end

local function enterPayload(inst: Inst, player: Player, role: string): any
	local l = G.LISTINGS[inst.listingId]
	local t = G.HOME_TIERS[inst.tierKey]
	local payload: any = {
		kind = "enter",
		role = role,
		ownerId = inst.ownerId,
		ownerName = inst.owner.DisplayName,
		listingId = inst.listingId,
		tierKey = inst.tierKey,
		tierName = t and t.name or inst.tierKey,
		tier = t and t.tier or 0,
		homeName = l and l.name or "내 집",
		icon = l and l.icon or "🏠",
		maxGuests = G.homeGuestLimit(inst.tierKey),
		guests = guestList(inst),
		slots = furnitureList(inst),
		tvOn = inst.tvOn,
		modelName = inst.model.Name,
		fallback = inst.fallback,
		staged = inst.staged,
	}
	if inst.staged then
		local l2 = G.LISTINGS[inst.listingId]
		payload.homeName = (l2 and l2.name or "매물") .. " (둘러보기)"
		payload.ownerName = ""
	end
	if role == "owner" then
		local d = Profiles.get(player)
		if d then
			payload.housing = G.housingView(d)
			payload.owned = d.home and d.home.owned or false
		end
	end
	return payload
end

-- Moves every occupant of `inst` out to its building (optionally except `except`).
local function evacuate(inst: Inst, reasonTitle: string, reasonBody: string, except: Player?)
	local list = {}
	for p in inst.occupants do
		if p ~= except then
			table.insert(list, p)
		end
	end
	for _, p in list do
		local target = entranceFor(inst.tierKey, nil, inst.entry[p])
		detach(p)
		if target and p.Parent == Players then
			task.spawn(function()
				teleportInto(p, target, true, "🚪")
				ctx.notify(p, "home", reasonTitle, reasonBody)
			end)
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Public: enter / leave
-------------------------------------------------------------------------------------------------
function Housing.available(): boolean
	return remotes.HomeState ~= nil
end

function Housing.instanceOf(player: Player): any
	return instances[player]
end

function Housing.where(player: Player): (any, string?)
	local inst = where[player]
	return inst, inst and inst.occupants[player] or nil
end

-- Is the player inside their own home (or, without an instance, near its entrance)?
function Housing.isAtHome(player: Player): boolean
	local d = Profiles.get(player)
	if not d or not d.home then
		return false
	end
	local inst = where[player]
	if inst and inst.owner == player and not inst.staged then
		return true
	end
	local key = G.homeTierKey(d.home.tier)
	return key ~= nil and nearEntrance(player, key) ~= nil
end

-- via: "entrance" | "phone" | "respawn". Returns true when the player is (now) inside.
function Housing.enter(player: Player, via: string?, quiet: boolean?): (boolean, string?)
	local d = Profiles.get(player)
	if not d then
		return false
	end
	if not d.home then
		if not quiet then
			ctx.notify(player, "home", "집이 없어요", "부동산 앱이나 광안역 부동산(정실장)에서 집을 구해 보세요")
		end
		return false
	end
	local cur = where[player]
	if cur and cur.owner == player and not cur.staged and cur.listingId == d.home.listingId then
		if not quiet then
			ctx.notify(player, "home", "이미 집이에요 🏠", "나가려면 현관문이나 '나가기'를 눌러요")
		end
		send(player, enterPayload(cur, player, "owner"))
		return true
	end
	local key = G.homeTierKey(d.home.tier) :: string
	local entry: BasePart? = nil
	if via == "entrance" then
		entry = nearEntrance(player, key)
		if not entry then
			ctx.notify(player, "home", "입구가 멀어요", "건물 입구에서 다시 시도해 주세요")
			return false
		end
	else
		entry = entranceFor(key, Util.rootPosition(player))
	end
	if via == "respawn" and (player:GetAttribute("Arrested") == true or (tonumber(player:GetAttribute("Wanted")) or 0) > 0) then
		return false -- 전투·범죄·경찰: a wanted player who respawned goes to the 광안지구대, not home
	end
	if via ~= "respawn" and not canTeleport(player) then
		return false
	end
	local inst = ensureInstance(player, d)
	if not inst then
		return false, "noInstance"
	end
	if cur then
		detach(player, true)
		if cur.staged then
			releaseStaged(player)
		end
	end
	local ok = teleportInto(player, spawnPart(inst), via ~= "respawn", "🏠 집으로 가는 중…")
	if not ok then
		if not quiet then
			ctx.notify(player, "home", "들어갈 수 없어요", "잠시 후 다시 시도해 주세요")
		end
		return false
	end
	attach(player, inst, "owner", entry)
	send(player, enterPayload(inst, player, "owner"))
	local s = HS(player)
	if s.pendingFood and not inst.food then
		task.defer(function()
			Housing._spawnFood(player, inst, s.pendingFood :: string)
		end)
	end
	if not quiet then
		local l = G.LISTINGS[inst.listingId]
		ctx.notify(player, "home", "집에 왔어요 🏠", string.format("%s · 침대에서 잠자기 · 현관 패널(🛠️ 인테리어)로 가구·벽지·조명을 바꿀 수 있어요", l and l.name or "내 집"))
	end
	return true
end

-- Leaves the current home (own or visited). Returns true when moved out.
function Housing.leave(player: Player, quiet: boolean?): boolean
	local inst = where[player]
	if not inst then
		if not quiet then
			ctx.notify(player, "home", "집 밖이에요", "이미 밖에 있어요")
		end
		return false
	end
	if not canTeleport(player) then
		return false
	end
	local role = inst.occupants[player]
	if inst.staged then
		-- 둘러보기: back to where the viewer stood
		local back = inst.returnCF[player]
		detach(player)
		releaseStaged(player)
		if back then
			Util.fade(player, true, 0.35, "🔑 둘러보기 끝")
			ctx.allowTeleport(player, 8)
			ctx.jobsResetPosition(player)
			unseat(player)
			pcall(player.RequestStreamAroundAsync, player, back.Position, 6)
			local okB = Util.placeCharacter(player, back)
			task.spawn(Util.fade, player, false, 0.45)
			if okB and not quiet then
				ctx.notify(player, "home", "둘러보기 끝 🔑", "마음에 들면 부동산 앱이나 건물 입구에서 계약할 수 있어요")
			end
			return okB
		end
		local fb = entranceFor(inst.tierKey, nil, nil)
		return fb ~= nil and teleportInto(player, fb, true, "🚪")
	end
	local target = entranceFor(inst.tierKey, nil, inst.entry[player])
	if not target then
		local spawnLoc = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		target = spawnLoc
	end
	if not target then
		if not quiet then
			ctx.notify(player, "home", "나갈 곳을 찾지 못했어요", "잠시 후 다시 시도해 주세요")
		end
		return false
	end
	if role == "owner" then
		evacuate(inst, "집주인이 외출했어요 🚶", "다음에 또 놀러 오세요!", player)
	end
	detach(player)
	local ok = teleportInto(player, target, true, "🚪 외출")
	if ok and not quiet then
		ctx.notify(player, "home", "외출 🚶", if role == "owner" then "좋은 하루 보내세요!" else "즐거운 방문이었어요 👋")
	end
	return ok
end

-------------------------------------------------------------------------------------------------
-- Poses (server side: anchors + CFrame so everyone sees it; the client adds the animation)
-------------------------------------------------------------------------------------------------
-- Lying on the bed while sleeping. Returns a function that stands the player up again.
function Housing.sleepPose(player: Player): (() -> ())?
	local inst = where[player]
	if not inst or inst.owner ~= player or inst.staged then
		return nil
	end
	local character, humanoid, root = Util.alive(player)
	if not character or not humanoid or not root then
		return nil
	end
	-- where to lie: the bed interaction's UseAt (Pose "lie", LookVector = towards the headboard),
	-- else the bed slot (generated bed / the slot envelope; headboard on the slot's +Z side)
	local pos: Vector3? = nil
	local head: Vector3? = nil
	for _, it in inst.interacts do
		if it.kind == "bed" and it.useCF and it.pose == "lie" then
			local u = it.useCF :: CFrame
			local rec = nil
			for _, r in inst.slots do
				if r.category == "bed" then
					rec = r
				end
			end
			if rec and rec.bed then
				-- a generated bed may be taller / lower than the template's default
				pos = Vector3.new(u.Position.X, (rec.bed :: CFrame).Position.Y, u.Position.Z)
			else
				pos = u.Position
			end
			head = Vector3.new(u.LookVector.X, 0, u.LookVector.Z)
			break
		end
	end
	if not pos then
		for _, rec in inst.slots do
			if rec.category == "bed" then
				local b: CFrame = if rec.bed then rec.bed :: CFrame else rec.geo.frame * CFrame.new(0, math.min(rec.geo.h * 0.5, 2), 0)
				pos = b.Position
				head = -b.LookVector
				break
			end
		end
	end
	if not pos then
		for _, it in inst.interacts do
			if it.kind == "bed" then
				pos = it.part.Position
				head = -it.part.CFrame.LookVector
				break
			end
		end
	end
	if not pos or not head or head.Magnitude < 0.01 then
		return nil
	end
	local up = (head :: Vector3).Unit
	local back = -Vector3.yAxis
	local right = up:Cross(back)
	local lying = CFrame.fromMatrix((pos :: Vector3) + Vector3.new(0, 0.9, 0), right, up, back)
	unseat(player)
	HS(player).posing = true
	root.Anchored = true
	pcall(function()
		character:PivotTo(lying * root.CFrame:ToObjectSpace(character:GetPivot()))
	end)
	send(player, { kind = "pose", pose = "sleep" })
	local bedPos = pos :: Vector3
	return function()
		HS(player).posing = false
		local _, h2, r2 = Util.alive(player)
		if r2 and h2 then
			r2.Anchored = false
			local ok = pcall(function()
				local target = nil
				for _, side in { right, -right } do
					local standPos = bedPos + side * 3.4
					target = Util.safeAt(standPos - Vector3.new(0, 1.5, 0), -side, Util.standHeight(h2, r2), Util.charactersIgnore())
					if target then
						break
					end
				end
				if target then
					Util.placeCharacter(player, target)
				else
					ctx.allowTeleport(player, 5)
					Util.teleportTo(player, spawnPart(inst), 2)
				end
			end)
			local _ = ok
		end
		send(player, { kind = "pose", pose = "none" })
	end
end

-- A small food prop in the right hand for a few seconds (visible to everyone).
local function holdProp(player: Player, color: Color3, seconds: number)
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local p = Instance.new("Part")
	p.Name = "HomeFoodProp"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.35, 0.7, 0.7)
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 - 0.2, -0.2) * CFrame.Angles(0, 0, math.rad(90))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = p
	weld.Parent = p
	p.Parent = character
	task.delay(seconds, function()
		p:Destroy()
	end)
end

-------------------------------------------------------------------------------------------------
-- Interactions
-------------------------------------------------------------------------------------------------
local function ownerProfile(inst: Inst): any?
	return Profiles.get(inst.owner)
end

local function panel(player: Player, name: string, data: any)
	send(player, { kind = "panel", panel = name, data = data })
end

local function fridgeData(d: any): any
	local h = G.ensureHousing(d)
	local menu = {}
	for _, id in G.HOME_FOOD.DELIVERY_ORDER do
		local m = G.HOME_FOOD.delivery[id]
		table.insert(menu, { id = id, name = m.name, icon = m.icon, price = m.price, wait = m.wait, desc = G.describeStats(m.stats) })
	end
	return {
		fridge = h.fridge,
		max = G.HOME_FRIDGE_MAX,
		groceries = { name = G.HOME_FOOD.groceries.name, price = G.HOME_FOOD.groceries.price, meals = G.HOME_FOOD.groceries.meals },
		meal = { name = G.HOME_FOOD.meal.name, desc = G.describeStats(G.HOME_FOOD.meal.stats) },
		menu = menu,
		delivery = false,
	}
end

local function mailboxData(d: any): any
	local v = G.housingView(d)
	local h = d.home
	local l = h and G.LISTINGS[h.listingId]
	return {
		bills = v.bills,
		loan = v.loan,
		homeName = l and l.name or "",
		owned = h and h.owned or false,
		daily = h and G.homeDaily(h.listingId) or 0,
		utility = v.utilityPerDay,
		dueIn = h and math.floor(h.dueIn or 0) or 0,
		missed = h and h.missed or 0,
		arrears = h and h.arrears or 0,
	}
end

local function deskData(player: Player, d: any): any
	local offers = {}
	for id, o in d.offers do
		local def = G.OFFERS[id]
		if def then
			table.insert(offers, { id = id, title = def.title, contact = def.contact, t = o.t })
		end
	end
	table.sort(offers, function(a, b)
		return (a.t or 0) > (b.t or 0)
	end)
	local unread = 0
	for _, t in d.messages.threads do
		unread += t.unread or 0
	end
	local job = d.job and G.JOBS[d.job.id]
	local v = G.housingView(d)
	local _ = player
	return {
		cash = d.cash,
		bank = d.bank,
		netWorth = G.netWorth(d),
		homeValue = v.value,
		furnitureValue = v.furnitureValue,
		loan = v.loan,
		job = if job then job.title else false,
		offers = offers,
		unread = unread,
		lastTx = (function()
			local out = {}
			for i = #d.transactions, math.max(1, #d.transactions - 4), -1 do
				local tx = d.transactions[i]
				table.insert(out, { label = tx.label, amount = tx.amount, account = tx.account })
			end
			return out
		end)(),
	}
end

local function wardrobeData(d: any): any
	local list = { { id = "outfit_default", name = G.CLOTHES.default.name, worn = d.outfit == "default" } }
	for _, id in G.CLOTHES_ORDER do
		if d.owned.outfits[id] then
			table.insert(list, { id = "outfit_" .. id, name = G.CLOTHES[id].name, worn = d.outfit == id })
		end
	end
	return { outfits = list, shopHint = #list <= 1 }
end

-- Sits the player: at the interaction's UseAt (Pose "sit") on the nearest free Seat there (template
-- seats, generated furniture seats), else on the nearest sofa / chair seat, else on an invisible
-- seat made at the spot. Returns true when seated.
local function sit(player: Player, inst: Inst, part: BasePart, useCF: CFrame?, quiet: boolean?): boolean
	local _, humanoid, root = Util.alive(player)
	if not humanoid or not root then
		return false
	end
	if humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(inst.model) then
		return true
	end
	local best: Seat? = nil
	local anchor = if useCF then (useCF :: CFrame).Position else part.Position
	local bestD = if useCF then 4.5 else 12
	for _, dd in inst.model:GetDescendants() do
		if dd:IsA("Seat") and not dd.Occupant then
			local dist = (dd.Position - anchor).Magnitude
			if dist < bestD then
				best, bestD = dd, dist
			end
		end
	end
	if not best then
		local seat = inst.seats[part]
		if not seat or not seat.Parent then
			local s = Instance.new("Seat")
			s.Name = "HomeSeat"
			s.Size = Vector3.new(1.6, 0.2, 1.6)
			if useCF then
				local u = useCF :: CFrame
				local look = Vector3.new(u.LookVector.X, 0, u.LookVector.Z)
				local p = u.Position - Vector3.new(0, 0.1, 0)
				s.CFrame = if look.Magnitude > 0.01 then CFrame.lookAt(p, p + look) else CFrame.new(p)
			else
				local top = part.CFrame * CFrame.new(0, -part.Size.Y / 2 + math.min(part.Size.Y, 1.6), 0)
				s.CFrame = CFrame.new(top.Position) * part.CFrame.Rotation
			end
			s.Transparency = 1
			s.Anchored = true
			s.CanCollide = false
			s.CanTouch = false
			s.CanQuery = false
			s.Parent = inst.model
			inst.seats[part] = s
			seat = s
		end
		if seat and not seat.Occupant then
			best = seat
		end
	end
	if not best then
		if not quiet then
			ctx.notify(player, "home", "자리가 없어요", "다른 자리를 찾아봐요")
		end
		return false
	end
	local b = best :: Seat
	b.Disabled = false
	local ok = pcall(function()
		(b :: any):Sit(humanoid)
	end)
	if ok and not quiet then
		ctx.notify(player, "home", "편하게 앉았어요 🛋️", if inst.tvOn then "TV를 보면 행복이 조금씩 올라요 📺" else "TV를 켜면 행복이 조금씩 올라요")
	end
	return ok
end

local function toggleTv(inst: Inst, player: Player)
	inst.tvOn = not inst.tvOn
	applyTv(inst)
	sendAll(inst, { kind = "tv", on = inst.tvOn })
	local _ = player
end

local function shower(player: Player, inst: Inst, part: BasePart)
	local d = Profiles.get(player)
	if not d then
		return
	end
	local h = G.ensureHousing(d)
	local now = os.time()
	local left = G.HOME_SHOWER_COOLDOWN - (now - (h.lastShower or 0))
	if left > 0 then
		ctx.notify(player, "home", "방금 씻었어요 🚿", G.format.seconds(left) .. " 후에 다시 씻을 수 있어요")
		return
	end
	h.lastShower = now
	local daily = G.housingDaily(d)
	daily.showers += 1
	local s = HS(player)
	s.posing = true
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "HomeSteam"
	steam.Rate = 18
	steam.Lifetime = NumberRange.new(1.5, 2.5)
	steam.Speed = NumberRange.new(1, 2)
	steam.SpreadAngle = Vector2.new(40, 40)
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	steam.Color = ColorSequence.new(Color3.fromRGB(240, 244, 248))
	steam.LightEmission = 0.2
	steam.Acceleration = Vector3.new(0, 2, 0)
	steam.Parent = part
	send(player, { kind = "pose", pose = "shower", seconds = 2.4 })
	task.spawn(function()
		Util.fade(player, true, 0.5, "샤워 중… 🚿")
		task.wait(1.4)
		steam.Enabled = false
		task.delay(3, function()
			steam:Destroy()
		end)
		s.posing = false
		if player.Parent ~= Players then
			return
		end
		local gain = { happiness = 2, stamina = 3 }
		if daily.showers <= 3 then
			(gain :: any).appearance = 0.5
		end
		local applied = ctx.addStats(player, gain, nil, true)
		Util.fade(player, false, 0.5)
		send(player, { kind = "pose", pose = "none" })
		ctx.changed(player, "housing")
		ctx.notify(player, "home", "개운해요! ✨", G.describeStats(applied))
	end)
end

-- the table / fridge meal (and delivery food)
local function eat(player: Player, stats: { [string]: number }, label: string, color: Color3)
	local s = HS(player)
	s.lastEat = os.clock()
	holdProp(player, color, 3)
	send(player, { kind = "pose", pose = "eat", seconds = 3 })
	task.delay(3, function()
		if player.Parent ~= Players then
			return
		end
		local applied = ctx.addStats(player, stats, nil, true)
		send(player, { kind = "pose", pose = "none" })
		ctx.notify(player, "home", label .. " 냠냠 😋", G.describeStats(applied))
	end)
end

function Housing._spawnFood(player: Player, inst: Inst, menuId: string)
	local m = G.HOME_FOOD.delivery[menuId]
	if not m or inst.food then
		return
	end
	local anchor: BasePart? = nil
	for _, it in inst.interacts do
		if it.kind == "table" then
			anchor = it.part
			break
		end
	end
	local cf: CFrame
	if anchor then
		cf = CFrame.new(anchor.Position + Vector3.new(0, anchor.Size.Y / 2 + 0.3, 0))
	else
		local sp = spawnPart(inst)
		cf = sp.CFrame * CFrame.new(0, 2.6, -2.5)
	end
	local box = Instance.new("Model")
	box.Name = "DeliveryFood"
	local base = Instance.new("Part")
	base.Name = "Box"
	base.Size = Vector3.new(1.6, 0.6, 1.2)
	base.CFrame = cf
	base.Color = Color3.fromRGB(236, 232, 222)
	base.Material = Enum.Material.Cardboard
	base.Anchored = true
	base.CanCollide = false
	base.Parent = box
	local lid = Instance.new("Part")
	lid.Name = "Sticker"
	lid.Size = Vector3.new(0.8, 0.05, 0.6)
	lid.CFrame = cf * CFrame.new(0, 0.32, 0)
	lid.Color = Color3.fromRGB(42, 193, 188)
	lid.Material = Enum.Material.SmoothPlastic
	lid.Anchored = true
	lid.CanCollide = false
	lid.Parent = box
	box.PrimaryPart = base
	box.Parent = inst.model
	inst.food = box
	local pp = makePrompt(base, "먹기", m.icon .. " " .. m.name)
	pp.Triggered:Connect(function(who: Player)
		if where[who] ~= inst or inst.food ~= box then
			return
		end
		inst.food = nil
		box:Destroy()
		local owner = inst.owner
		if who == owner then
			HS(owner).pendingFood = nil
		else
			HS(owner).pendingFood = nil
		end
		eat(who, m.stats, m.name, Color3.fromRGB(230, 160, 70))
	end)
end

local function deliveryArrive(player: Player, menuId: string)
	local s = HS(player)
	s.delivery = nil
	s.pendingFood = menuId
	local m = G.HOME_FOOD.delivery[menuId]
	local inst = where[player]
	if inst and inst.owner == player and not inst.staged then
		Housing._spawnFood(player, inst, menuId)
		sendAll(inst, { kind = "doorbell", delivery = true, visitorName = "배달 기사님" })
		ctx.notify(player, "home", "배달 왔습니다! 🛵", (m and m.name or "음식") .. " · 식탁에서 '먹기'")
	else
		ctx.notify(player, "home", "배달 완료 🛵", (m and m.name or "음식") .. "을 문 앞에 두고 갔어요. 집에 가면 먹을 수 있어요")
	end
end

local function doorOpen(player: Player)
	Housing.leave(player)
end

onInteract = function(player: Player, inst: Inst, kind: string, part: BasePart)
	if where[player] ~= inst then
		return
	end
	local useCF: CFrame? = nil
	local pose: string? = nil
	for _, it in inst.interacts do
		if it.part == part then
			useCF, pose = it.useCF, it.pose
			break
		end
	end
	local role = inst.occupants[player]
	if not Core.canUse(kind, role) then
		ctx.notify(player, "home", "집주인만 쓸 수 있어요", string.format("%s님의 %s이에요", inst.owner.DisplayName, G.HOME_KINDS[kind] and G.HOME_KINDS[kind].object or "물건"))
		return
	end
	local pos = Util.rootPosition(player)
	if not pos or (pos - part.Position).Magnitude > 16 + math.max(part.Size.X, part.Size.Z) / 2 then
		return
	end
	if not Util.cooldown(player, "homeKind:" .. kind, 0.8) then
		return
	end
	local d = Profiles.get(player)
	if not d then
		return
	end
	if kind == "door" then
		doorOpen(player)
	elseif kind == "bed" then
		Life.sleep(player)
	elseif kind == "sofa" then
		sit(player, inst, part, useCF)
	elseif kind == "tv" then
		-- "TV 보기": turn it on and sit where the template says (UseAt, usually the sofa)
		toggleTv(inst, player)
		if inst.tvOn and pose == "sit" then
			sit(player, inst, part, useCF, true)
		end
	elseif kind == "fridge" then
		local data = fridgeData(d)
		local sd = HS(player).delivery
		data.delivery = if sd then { menuId = sd.menuId, eta = math.max(0, math.ceil(sd.at - os.clock())) } else false
		panel(player, "fridge", data)
	elseif kind == "table" then
		if pose == "sit" then
			sit(player, inst, part, useCF, true)
		end
		if inst.food then
			ctx.notify(player, "home", "식탁에 음식이 있어요 🍽️", "음식 상자에서 '먹기'를 눌러요")
		else
			local data = fridgeData(d)
			local sd = HS(player).delivery
			data.delivery = if sd then { menuId = sd.menuId, eta = math.max(0, math.ceil(sd.at - os.clock())) } else false
			panel(player, "fridge", data)
		end
	elseif kind == "shower" then
		shower(player, inst, part)
	elseif kind == "wardrobe" then
		panel(player, "wardrobe", wardrobeData(d))
	elseif kind == "desk" then
		if pose == "sit" then
			sit(player, inst, part, useCF, true)
		end
		panel(player, "desk", deskData(player, d))
	elseif kind == "window" then
		local env = ctx.env()
		panel(player, "window", { cf = part.CFrame, view = G.HOME_TIERS[inst.tierKey] and G.HOME_TIERS[inst.tierKey].view or "sea", night = env.night == true, tierKey = inst.tierKey })
	elseif kind == "mailbox" then
		panel(player, "mailbox", mailboxData(d))
	elseif kind == "interior" then
		-- the 현관 wall panel: owner = 인테리어 mode, guests / viewers = 집 구경 (read-only)
		Housing.openInterior(player)
	end
end

-------------------------------------------------------------------------------------------------
-- Visiting
-------------------------------------------------------------------------------------------------
local function playerById(v: any): Player?
	local id = Util.int(v, 1, 2 ^ 53)
	if not id then
		return nil
	end
	local ok, p = pcall(Players.GetPlayerByUserId, Players, id)
	if ok and p and p.Parent == Players then
		return p
	end
	return nil
end

local function ownerAtHome(owner: Player): Inst?
	local inst = instances[owner]
	if inst and where[owner] == inst and inst.occupants[owner] == "owner" then
		return inst
	end
	return nil
end

local function admit(visitor: Player, inst: Inst): boolean
	if not Core.canAdmit(guestCount(inst), inst.tierKey) then
		ctx.notify(visitor, "home", "집이 꽉 찼어요", string.format("%s은 최대 %d명까지 놀러 올 수 있어요", tierName(inst.tierKey), G.homeGuestLimit(inst.tierKey)))
		ctx.notify(inst.owner, "home", "손님이 너무 많아요", string.format("%s은 최대 %d명까지예요", tierName(inst.tierKey), G.homeGuestLimit(inst.tierKey)))
		return false
	end
	if not canTeleport(visitor) then
		return false
	end
	local own = instances[visitor]
	if where[visitor] and where[visitor] == own then
		evacuate(own :: Inst, "집주인이 외출했어요 🚶", "다음에 또 놀러 오세요!", visitor)
	end
	local entry = entranceFor(inst.tierKey, Util.rootPosition(visitor))
	detach(visitor, true)
	local ok = teleportInto(visitor, spawnPart(inst), true, "🔔 " .. inst.owner.DisplayName .. "님 집으로")
	if not ok then
		return false
	end
	attach(visitor, inst, "guest", entry)
	send(visitor, enterPayload(inst, visitor, "guest"))
	sendAll(inst, { kind = "guests", guests = guestList(inst), maxGuests = G.homeGuestLimit(inst.tierKey) })
	ctx.notify(visitor, "home", inst.owner.DisplayName .. "님 집에 놀러 왔어요 🏠", "소파·TV·창밖 구경을 해 봐요")
	-- 집들이
	local od = ownerProfile(inst)
	if od then
		local res = G.housewarmingVisit(od, tostring(visitor.UserId))
		if res.party then
			ctx.addStats(inst.owner, { happiness = 10, popularity = 3 }, "🎉 집들이 성공! " .. visitor.DisplayName .. "님이 첫 손님이에요")
			ctx.addStats(visitor, { happiness = 5, popularity = 0.5 }, "🎉 " .. inst.owner.DisplayName .. "님 집들이")
			pcall(Life.sendMessage, inst.owner, "minji", "집들이 했다며?! 🎉 사진 보니까 집 너무 예쁘다 ㅎㅎ 다음엔 나도 불러줘!")
		elseif res.newGuest and res.count <= 10 then
			ctx.addStats(inst.owner, { happiness = 3, popularity = 1 }, "새 손님 방문 🏠")
			ctx.addStats(visitor, { happiness = 3 }, "친구 집 방문 🏠")
		else
			ctx.addStats(visitor, { happiness = 2 }, nil, true)
		end
		ctx.changed(inst.owner, "housing")
	end
	return true
end

local function ring(visitor: Player, payload: any)
	local owner = playerById(payload.ownerId)
	if not owner or owner == visitor then
		ctx.notify(visitor, "home", "초인종", "지금 집에 있는 사람이 없어요")
		return
	end
	local od = Profiles.get(owner)
	local key = od and od.home and G.homeTierKey(od.home.tier)
	if not key then
		ctx.notify(visitor, "home", "초인종", "이 건물에 사는 사람이 아니에요")
		return
	end
	if not nearEntrance(visitor, key) then
		ctx.notify(visitor, "home", "초인종", "건물 입구에서 눌러 주세요")
		return
	end
	local inst = ownerAtHome(owner)
	if not inst then
		ctx.notify(visitor, "home", "아무도 없어요 🔕", owner.DisplayName .. "님은 외출 중이에요")
		return
	end
	if where[visitor] == inst then
		return
	end
	local ok, reason = Core.ring(visits, owner, visitor, os.clock())
	if not ok then
		if reason == "banned" then
			ctx.notify(visitor, "home", "초인종", "지금은 방문할 수 없어요")
		elseif reason == "pending" then
			ctx.notify(visitor, "home", "초인종", "이미 눌렀어요. 잠시만 기다려 주세요")
		end
		return
	end
	send(owner, { kind = "doorbell", visitorId = visitor.UserId, visitorName = visitor.DisplayName })
	ctx.notify(owner, "home", "딩동 🔔", visitor.DisplayName .. "님이 초인종을 눌렀어요", { sound = "message" })
	ctx.notify(visitor, "home", "딩동 🔔", owner.DisplayName .. "님을 불렀어요. 문 열어 줄 때까지 기다려요")
end

local function answerDoor(owner: Player, payload: any)
	local visitor = playerById(payload.visitorId)
	local inst = ownerAtHome(owner)
	if not visitor or not inst then
		return
	end
	local ok = Core.answer(visits, owner, visitor, os.clock())
	if not ok then
		ctx.notify(owner, "home", "초인종", "방문자가 떠났어요")
		return
	end
	if payload.accept ~= true then
		ctx.notify(visitor, "home", "문이 안 열려요 🙏", owner.DisplayName .. "님이 지금은 곤란하대요")
		return
	end
	local key = inst.tierKey
	local pos = Util.rootPosition(visitor)
	local near = false
	if pos then
		for _, part in entrancesOf(key) do
			if (part.Position - pos).Magnitude <= 80 then
				near = true
				break
			end
		end
	end
	if not near then
		ctx.notify(owner, "home", "초인종", visitor.DisplayName .. "님이 입구를 떠났어요")
		return
	end
	admit(visitor, inst)
end

local function invite(owner: Player, payload: any)
	local visitor = playerById(payload.userId)
	local inst = ownerAtHome(owner)
	if not inst then
		ctx.notify(owner, "home", "초대하기", "집에 있을 때 친구를 초대할 수 있어요")
		return
	end
	if not visitor or visitor == owner then
		ctx.notify(owner, "home", "초대하기", "초대할 친구를 찾지 못했어요")
		return
	end
	if where[visitor] == inst then
		ctx.notify(owner, "home", "초대하기", visitor.DisplayName .. "님은 이미 와 있어요")
		return
	end
	if not Core.canAdmit(guestCount(inst), inst.tierKey) then
		ctx.notify(owner, "home", "초대하기", string.format("%s은 최대 %d명까지예요", tierName(inst.tierKey), G.homeGuestLimit(inst.tierKey)))
		return
	end
	local ok, reason = Core.invite(visits, owner, visitor, os.clock())
	if not ok then
		if reason == "pending" then
			ctx.notify(owner, "home", "초대하기", "이미 초대를 보냈어요")
		elseif reason == "banned" then
			ctx.notify(owner, "home", "초대하기", "방금 내보낸 친구는 잠시 후 초대할 수 있어요")
		end
		return
	end
	local l = G.LISTINGS[inst.listingId]
	send(visitor, { kind = "invite", ownerId = owner.UserId, ownerName = owner.DisplayName, homeName = l and l.name or "집", tierName = tierName(inst.tierKey), expiresIn = G.HOME_INVITE_TTL })
	ctx.notify(visitor, "home", "집들이 초대 🏠", string.format("%s님이 %s에 초대했어요", owner.DisplayName, l and l.name or "집"), { sound = "message" })
	ctx.notify(owner, "home", "초대 보냄 💌", visitor.DisplayName .. "님에게 초대를 보냈어요")
end

local function acceptInvite(visitor: Player, payload: any, accept: boolean)
	local owner = playerById(payload.ownerId)
	if not owner then
		return
	end
	local ok, reason = Core.takeInvite(visits, visitor, owner, os.clock())
	if not ok then
		if accept then
			ctx.notify(visitor, "home", "초대", if reason == "expired" then "초대가 만료됐어요" else "초대를 찾지 못했어요")
		end
		return
	end
	if not accept then
		ctx.notify(owner, "home", "초대", visitor.DisplayName .. "님이 다음에 오겠대요 🙏")
		return
	end
	local inst = ownerAtHome(owner)
	if not inst then
		ctx.notify(visitor, "home", "초대", owner.DisplayName .. "님이 집에 없어요")
		return
	end
	admit(visitor, inst)
end

local function kick(owner: Player, payload: any)
	local visitor = playerById(payload.userId)
	local inst = instances[owner]
	if not visitor or not inst or where[visitor] ~= inst or inst.occupants[visitor] ~= "guest" then
		return
	end
	Core.kick(visits, owner, visitor, os.clock())
	local target = entranceFor(inst.tierKey, nil, inst.entry[visitor])
	detach(visitor)
	if target then
		task.spawn(teleportInto, visitor, target, true, "🚪")
	end
	ctx.notify(visitor, "home", "방문 종료", owner.DisplayName .. "님이 방문을 마쳤어요")
	ctx.notify(owner, "home", "내보냈어요", visitor.DisplayName .. "님을 배웅했어요")
end

-------------------------------------------------------------------------------------------------
-- Furniture / remodelling / loans (server-validated HomeAction handlers)
-------------------------------------------------------------------------------------------------
local FURN_REASON = {
	noHome = "집이 없어요",
	unknown = "없는 가구예요",
	category = "이 자리에 맞지 않는 가구예요",
	same = "이미 놓여 있어요",
	insufficient = "잔액이 부족해요",
	storageFull = "창고가 꽉 찼어요. 안 쓰는 가구를 팔아 주세요",
	empty = "놓인 가구가 없어요",
}

local function ownInstanceInside(player: Player): Inst?
	local inst = where[player]
	if inst and inst.owner == player and not inst.staged then
		return inst
	end
	return nil
end

local function furnitureChanged(player: Player, inst: Inst?)
	local d = Profiles.get(player)
	ctx.changed(player, "housing", "home", "cash", "bank")
	pcall(ctx.refreshAttributes, player)
	if inst and d then
		sendAll(inst, { kind = "furniture", slots = furnitureList(inst) })
		send(player, { kind = "furniture", slots = furnitureList(inst), housing = G.housingView(d) })
	end
end

-- payload { slotId, variantId, rot? (0..3), sellOld? (true: the replaced piece is sold back at 50 %
-- before paying; else it goes to 창고) }. Price / category / variant are checked here, never trusted.
local function placeFurniture(player: Player, payload: any)
	local d = Profiles.get(player)
	local inst = ownInstanceInside(player)
	local slotId = Util.str(payload.slotId, 40)
	local vid = Util.str(payload.variantId, 40)
	if not d or not inst or not slotId or not vid then
		if not inst then
			ctx.notify(player, "home", "꾸미기", "내 집 안에서 꾸밀 수 있어요")
		end
		return
	end
	local rec = inst.slots[slotId]
	if not rec then
		return
	end
	local rot = Util.int(payload.rot, 0, 3) or rec.rot or 0
	if not isRotAllowed(rec, false, rot) then
		rot = 0
	end
	local HSm = G.HOMES
	local ok, info
	if HSm then
		ok, info = HSm.buyFurniture(G, d, slotId, rec.category, vid, payload.sellOld == true, os.time())
	else
		ok, info = G.placeFurniture(d, slotId, rec.category, vid, os.time())
	end
	if not ok then
		local msg = FURN_REASON[info] or "놓을 수 없어요"
		if info == "insufficient" then
			local f = G.FURNITURE[vid]
			msg = string.format("%s · %s (통장 %s · 현금 %s)", f and f.name or "가구", won(f and f.price or 0), won(d.bank), won(d.cash))
		end
		ctx.notify(player, "home", "가구 배치 실패", msg)
		send(player, { kind = "interiorResult", ok = false, action = "place", slotId = slotId, reason = info })
		return
	end
	if HSm then
		HSm.setRot(d, slotId, rot)
	end
	applySlot(inst, rec, vid, rot)
	local f = G.FURNITURE[vid]
	if info.bought then
		local extra = ""
		if info.sold and (info.refund or 0) > 0 then
			extra = " · 기존 가구 50% 환불 +" .. won(info.refund)
		elseif info.displaced then
			extra = " · 원래 가구는 창고로"
		end
		ctx.notify(player, "money", "가구 구매 🛋️ -" .. won(info.price), f.name .. " 배치 완료" .. extra, { sound = "cash" })
	else
		ctx.notify(player, "home", "가구 배치 🛋️", f.name .. " (창고에서 꺼냄)" .. (if info.sold and (info.refund or 0) > 0 then " · 기존 가구 +" .. won(info.refund) else ""))
	end
	if info.bought and f.decor >= 8 then
		ctx.addStats(player, { happiness = 3 }, nil, true)
	end
	send(player, { kind = "interiorResult", ok = true, action = "place", slotId = slotId, variantId = vid, rot = rot, price = info.price, refund = info.refund or 0 })
	furnitureChanged(player, inst)
end

local function resetSlot(player: Player, payload: any)
	local d = Profiles.get(player)
	local inst = ownInstanceInside(player)
	local slotId = Util.str(payload.slotId, 40)
	if not d or not inst or not slotId or not inst.slots[slotId] then
		return
	end
	local ok, res = G.resetSlot(d, slotId)
	if not ok then
		ctx.notify(player, "home", "꾸미기", FURN_REASON[res] or "되돌릴 수 없어요")
		return
	end
	applySlot(inst, inst.slots[slotId], nil)
	if G.HOMES then
		G.HOMES.setRot(d, slotId, inst.slots[slotId].rot)
	end
	ctx.notify(player, "home", "기본 가구로 되돌렸어요", G.FURNITURE[res].name .. "은 창고에 보관했어요")
	furnitureChanged(player, inst)
end

local function sellSlot(player: Player, payload: any)
	local d = Profiles.get(player)
	local inst = ownInstanceInside(player)
	local slotId = Util.str(payload.slotId, 40)
	if not d or not inst or not slotId or not inst.slots[slotId] then
		return
	end
	local name = inst.slots[slotId].current and G.FURNITURE[inst.slots[slotId].current :: string]
	local ok, res = G.sellSlot(d, slotId, os.time())
	if not ok then
		ctx.notify(player, "home", "판매", FURN_REASON[res] or "팔 수 없어요")
		return
	end
	applySlot(inst, inst.slots[slotId], nil)
	if G.HOMES then
		G.HOMES.setRot(d, slotId, inst.slots[slotId].rot)
	end
	ctx.notify(player, "money", "가구 판매 +" .. won(res), (name and name.name or "가구") .. " (구매가의 50%)", { sound = "cash" })
	furnitureChanged(player, inst)
end

local function sellStored(player: Player, payload: any)
	local d = Profiles.get(player)
	local vid = Util.str(payload.variantId, 40)
	if not d or not vid then
		return
	end
	local ok, res = G.sellStored(d, vid, os.time())
	if not ok then
		ctx.notify(player, "home", "판매", FURN_REASON[res] or "팔 수 없어요")
		return
	end
	ctx.notify(player, "money", "가구 판매 +" .. won(res), G.FURNITURE[vid].name .. " (구매가의 50%)", { sound = "cash" })
	furnitureChanged(player, ownInstanceInside(player))
end

local UPGRADE_REASON = {
	unknown = "없는 공사예요",
	noHome = "집이 없어요",
	notOwned = "리모델링은 자가(매매한 집)만 할 수 있어요",
	tier = "펜트하우스에서만 할 수 있어요",
	owned = "이미 공사했어요",
	insufficient = "잔액이 부족해요",
}

local function upgrade(player: Player, payload: any)
	local d = Profiles.get(player)
	local id = Util.str(payload.upgradeId, 40)
	if not d or not id then
		return
	end
	local ok, reason = G.buyUpgrade(d, id, os.time())
	local u = G.HOME_UPGRADES[id]
	if not ok then
		local msg = UPGRADE_REASON[reason or ""] or "공사할 수 없어요"
		if reason == "insufficient" and u then
			msg = string.format("%s · %s 필요 (통장 %s)", u.name, won(u.price), won(d.bank))
		end
		ctx.notify(player, "home", "리모델링 실패", msg)
		return
	end
	ctx.notify(player, "home", "리모델링 완료 " .. u.icon, string.format("%s · 집값 +%s · 편안함 +%d", u.name, won(u.value), u.comfort), { sound = "complete" })
	ctx.addStats(player, { happiness = 4 }, nil, true)
	G.addBill(d, "info", "리모델링 · " .. u.name, u.price, true, os.time())
	furnitureChanged(player, ownInstanceInside(player))
end

local function repayLoan(player: Player)
	local d = Profiles.get(player)
	if not d then
		return
	end
	local ok, res = G.repayLoan(d, os.time())
	if not ok then
		ctx.notify(player, "home", "대출 상환", if res == "noLoan" then "갚을 대출이 없어요" else "잔액이 부족해요 (통장 + 현금)")
		return
	end
	G.addBill(d, "loanPaid", "주택담보대출 완납", res, true, os.time())
	ctx.notify(player, "money", "대출 완납 🎉 -" .. won(res), "이제 온전히 내 집이에요!", { sound = "complete" })
	ctx.addStats(player, { happiness = 10 }, nil, true)
	pcall(Life.sendMessage, player, "banker", "주택담보대출을 모두 갚으셨네요. 축하드려요! 🎉 이제 온전히 고객님 집이에요.")
	ctx.changed(player, "home", "housing", "cash", "bank")
end

-------------------------------------------------------------------------------------------------
-- 인테리어: room themes, quarter turns, the decorating / 집 구경 mode, 매물 둘러보기, 칭찬
-------------------------------------------------------------------------------------------------
local function unitRecord(inst: Inst): any?
	if inst.staged then
		return nil
	end
	local od = Profiles.get(inst.owner)
	local h = od and od.housing
	return if type(h) == "table" and type(h.units) == "table" then h.units[inst.listingId] else nil
end

-- Rooms of an instance for the client: { {id, name, icon, center, size, kinds, theme} } (static
-- geometry cached on the instance).
local function roomList(inst: Inst): { any }
	local HSm = G.HOMES
	local u = unitRecord(inst)
	local boxes = (inst :: any).roomBoxes
	if not boxes then
		boxes = {}
		for _, room in inst.themes.order do
			local c, size = Core.roomBox(inst.themes, room, inst.root.CFrame)
			boxes[room] = { c, size }
		end
		;(inst :: any).roomBoxes = boxes
	end
	local out = {}
	for _, room in inst.themes.order do
		local info = if HSm then HSm.roomInfo(room) else { name = room, icon = "🏠" }
		local b = boxes[room]
		table.insert(out, {
			id = room,
			name = info.name,
			icon = info.icon,
			center = b and b[1] or false,
			size = b and b[2] or false,
			kinds = Core.roomKinds(inst.themes, room),
			theme = if HSm and u then HSm.themeOf(u, room) else { wall = false, floor = false, light = false },
		})
	end
	return out
end

local function interiorPayload(inst: Inst, player: Player, mode: string): any
	local HSm = G.HOMES
	local od = if inst.staged then nil else Profiles.get(inst.owner)
	local l = G.LISTINGS[inst.listingId]
	local data: any = {
		kind = "interior",
		mode = mode, -- "edit" (owner) | "tour" (guests, 둘러보기 viewers: read-only)
		ownerId = inst.ownerId,
		ownerName = inst.owner.DisplayName,
		listingId = inst.listingId,
		tierKey = inst.tierKey,
		homeName = l and l.name or "집",
		staged = inst.staged,
		modelName = inst.model.Name,
		rooms = roomList(inst),
		slots = furnitureList(inst),
		decor = if od then G.homeDecor(od) else 0,
		themeDecor = if od and HSm then HSm.themeDecor(od) else 0,
		comfort = if od then G.homeComfort(od) else 0,
	}
	if mode == "edit" then
		local d = Profiles.get(player)
		if d then
			data.housing = G.housingView(d)
			data.bank = d.bank
			data.cash = d.cash
		end
	elseif inst.staged and l then
		data.listing = { kind = l.kind, price = l.price, rentPerDay = l.rentPerDay, deposit = l.deposit, upkeepPerDay = l.upkeepPerDay, desc = l.desc }
	end
	return data
end

-- Opens the decorating mode (owner inside) or 집 구경 (guest / viewer). From outside with a home of
-- one's own (the phone 홈 app): goes home first, then opens it.
local function openInterior(player: Player)
	local inst = where[player]
	if not inst then
		local d = Profiles.get(player)
		if d and d.home then
			task.spawn(function()
				local ok = Housing.enter(player, "phone", true)
				local i2 = where[player]
				if ok and i2 and i2.owner == player and not i2.staged then
					send(player, interiorPayload(i2, player, "edit"))
				end
			end)
		else
			ctx.notify(player, "home", "인테리어", "집이 있어야 꾸밀 수 있어요. 부동산 앱에서 집을 구해 보세요")
		end
		return
	end
	local role = inst.occupants[player]
	send(player, interiorPayload(inst, player, if role == "owner" and not inst.staged then "edit" else "tour"))
end
Housing.openInterior = openInterior

local function themesChanged(player: Player, inst: Inst)
	ctx.changed(player, "housing", "cash", "bank")
	pcall(ctx.refreshAttributes, player)
	local rooms = roomList(inst)
	local d = Profiles.get(player)
	local HSm = G.HOMES
	sendAll(inst, { kind = "themes", rooms = rooms, decor = if d then G.homeDecor(d) else 0, themeDecor = if d and HSm then HSm.themeDecor(d) else 0 })
	if d then
		send(player, { kind = "furniture", slots = furnitureList(inst), housing = G.housingView(d) })
	end
end

-- payload { room, kind = "wall" | "floor" | "light", id = theme id | "default" }
local function setTheme(player: Player, payload: any)
	local d = Profiles.get(player)
	local inst = ownInstanceInside(player)
	local HSm = G.HOMES
	if not d or not inst or not HSm then
		if d and not inst then
			ctx.notify(player, "home", "인테리어", "내 집 안에서 바꿀 수 있어요")
		end
		return
	end
	local room = Util.str(payload.room, 24)
	local kind = Util.str(payload.kind, 8)
	local id = Util.str(payload.id, 24)
	if not room or not kind or not id or not inst.themes.rooms[room] then
		return
	end
	if kind ~= "wall" and kind ~= "floor" and kind ~= "light" then
		return
	end
	local function fail(msg: string, code: string)
		ctx.notify(player, "home", "인테리어", msg)
		send(player, { kind = "interiorResult", ok = false, action = "theme", room = room, themeKind = kind, id = id, reason = code })
	end
	if not Core.roomKinds(inst.themes, room)[kind] then
		fail("이 방은 바꿀 수 없어요", "kind")
		return
	end
	local def = if id == "default" then nil else HSm.themeDef(kind, id)
	if id ~= "default" and not def then
		return
	end
	local u = HSm.unitOf(d, inst.listingId)
	local cur = HSm.themeOf(u, room)[kind]
	if (id == "default" and not cur) or cur == id then
		fail("이미 적용된 디자인이에요", "same")
		return
	end
	local price = HSm.themePrice(kind, id, inst.tierKey, room)
	local roomName = HSm.roomInfo(room).name
	local kindInfo = HSm.THEME_KIND_NAMES[kind]
	if price > 0 then
		local okPay = G.spend(d, price, string.format("인테리어 · %s %s", roomName, kindInfo.name), os.time(), "bank")
		if not okPay then
			fail(string.format("%s %s · %s 필요 (통장 %s)", roomName, kindInfo.name, won(price), won(d.bank)), "insufficient")
			return
		end
	end
	HSm.saveTheme(d, room, kind, id)
	Core.applyRoomTheme(inst.themes, room, kind, def)
	local label = if def then def.name else "기본 디자인"
	if price > 0 then
		ctx.notify(player, "money", string.format("%s %s 시공 완료 %s -%s", roomName, kindInfo.name, kindInfo.icon, won(price)), label, { sound = "cash" })
	else
		ctx.notify(player, "home", string.format("%s %s %s", roomName, kindInfo.name, kindInfo.icon), label .. "(으)로 되돌렸어요")
	end
	if def and def.decor >= 4 then
		ctx.addStats(player, { happiness = 2 }, nil, true)
	end
	send(player, { kind = "interiorResult", ok = true, action = "theme", room = room, themeKind = kind, id = id, price = price })
	themesChanged(player, inst)
end

-- payload { slotId, rot (0..3) }: turns the piece in a slot (free).
local function rotateSlot(player: Player, payload: any)
	local d = Profiles.get(player)
	local inst = ownInstanceInside(player)
	local slotId = Util.str(payload.slotId, 40)
	local rot = Util.int(payload.rot, 0, 3)
	if not d or not inst or not slotId or not rot then
		return
	end
	local rec = inst.slots[slotId]
	if not rec then
		return
	end
	if not isRotAllowed(rec, rec.current == nil, rot) then
		ctx.notify(player, "home", "회전", if rec.canRotate then "이 가구는 이 방향으로 돌릴 수 없어요" else "이 자리는 회전할 수 없어요")
		send(player, { kind = "interiorResult", ok = false, action = "rotate", slotId = slotId, reason = "rot" })
		return
	end
	if rot == rec.rot then
		return
	end
	if G.HOMES then
		G.HOMES.setRot(d, slotId, rot)
	end
	applySlot(inst, rec, rec.current, rot)
	send(player, { kind = "interiorResult", ok = true, action = "rotate", slotId = slotId, rot = rec.rot })
	ctx.changed(player, "housing")
	sendAll(inst, { kind = "furniture", slots = furnitureList(inst) })
end

-- 매물 둘러보기: an empty staged unit of a listing; leaving puts the viewer back where they stood.
local function startTour(player: Player, payload: any)
	local listingId = Util.str(payload.listingId, 40)
	local l = listingId and G.LISTINGS[listingId]
	local key = l and G.homeTierKey(l.tierKey)
	if not l or not key then
		return
	end
	local cur = where[player]
	if cur and not cur.staged then
		ctx.notify(player, "home", "둘러보기", "밖에서 매물을 둘러볼 수 있어요")
		return
	end
	if not canTeleport(player) then
		return
	end
	local _, _, root = Util.alive(player)
	if not root then
		return
	end
	local back = if cur and cur.staged then cur.returnCF[player] else root.CFrame
	if cur then
		detach(player, true)
		releaseStaged(player)
	end
	local inst = buildInstance(player, listingId :: string, key, nil, true)
	if not inst then
		ctx.notify(player, "home", "둘러보기", "지금은 볼 수 없어요. 잠시 후 다시 시도해 주세요")
		return
	end
	local ok = teleportInto(player, spawnPart(inst), true, "🔑 " .. l.name .. " 둘러보기")
	if not ok then
		destroyInstance(inst)
		return
	end
	inst.returnCF[player] = back
	attach(player, inst, "viewer", nil)
	send(player, enterPayload(inst, player, "viewer"))
	send(player, interiorPayload(inst, player, "tour"))
	ctx.notify(player, "home", "🔑 " .. l.name, "빈 집을 둘러보는 중이에요. 마음에 들면 계약해요 · '나가기'로 돌아가요")
end

-- 칭찬 (집 구경 중인 손님): the owner gets a little 행복 / 인기도, once per guest per 10 minutes.
local function compliment(player: Player)
	local inst = where[player]
	if not inst or inst.staged or inst.occupants[player] ~= "guest" or inst.owner == player then
		return
	end
	local HSm = G.HOMES
	local cd = if HSm then HSm.COMPLIMENT_COOLDOWN else 600
	local last = inst.compliments[player]
	if last and os.clock() - last < cd then
		ctx.notify(player, "home", "칭찬 👍", "이미 칭찬했어요. 집주인이 기뻐하고 있어요")
		return
	end
	inst.compliments[player] = os.clock()
	ctx.addStats(inst.owner, { happiness = 2, popularity = 0.5 }, "✨ " .. player.DisplayName .. "님이 인테리어를 칭찬했어요")
	ctx.notify(player, "home", "칭찬 보냄 👍", inst.owner.DisplayName .. "님에게 인테리어 칭찬을 전했어요")
end

-------------------------------------------------------------------------------------------------
-- Food / TV / photo actions
-------------------------------------------------------------------------------------------------
local function eatHome(player: Player)
	local d = Profiles.get(player)
	local inst = ownInstanceInside(player)
	if not d or not inst then
		ctx.notify(player, "home", "집밥", "집에서 먹을 수 있어요")
		return
	end
	local s = HS(player)
	if os.clock() - s.lastEat < G.HOME_EAT_COOLDOWN then
		ctx.notify(player, "home", "배불러요 😌", "조금 있다가 먹어요")
		return
	end
	local ok, stats = G.eatHomeMeal(d)
	if not ok then
		ctx.notify(player, "home", "냉장고가 비었어요", "장보기로 재료를 채우거나 배달을 시켜요")
		return
	end
	eat(player, stats, G.HOME_FOOD.meal.name, Color3.fromRGB(240, 240, 236))
	ctx.changed(player, "housing")
	panel(player, "fridge", (function()
		local data = fridgeData(d)
		local sd = s.delivery
		data.delivery = if sd then { menuId = sd.menuId, eta = math.max(0, math.ceil(sd.at - os.clock())) } else false
		return data
	end)())
end

local function groceries(player: Player)
	local d = Profiles.get(player)
	if not d or not ownInstanceInside(player) then
		ctx.notify(player, "home", "장보기", "집에서 주문할 수 있어요")
		return
	end
	local ok, reason = G.buyGroceries(d, os.time())
	if not ok then
		ctx.notify(player, "home", "장보기", if reason == "full" then "냉장고가 꽉 찼어요" else "잔액이 부족해요")
		return
	end
	ctx.changed(player, "housing", "cash", "bank")
	ctx.notify(player, "money", "장보기 완료 🛒 -" .. won(G.HOME_FOOD.groceries.price), string.format("냉장고에 집밥 재료 %d끼", G.ensureHousing(d).fridge), { sound = "cash" })
	local data = fridgeData(d)
	data.delivery = false
	panel(player, "fridge", data)
end

local function delivery(player: Player, payload: any)
	local d = Profiles.get(player)
	local id = Util.str(payload.menuId, 20)
	local m = id and G.HOME_FOOD.delivery[id]
	if not d or not m or not ownInstanceInside(player) then
		if d and m then
			ctx.notify(player, "home", "배달 주문", "집에서 주문할 수 있어요")
		end
		return
	end
	local s = HS(player)
	if s.delivery or s.pendingFood then
		ctx.notify(player, "home", "배달 주문", "이미 주문한 음식이 있어요")
		return
	end
	if not ctx.spend(player, m.price, "배달 주문 · " .. m.name, true) then
		ctx.notify(player, "money", "잔액 부족", m.name .. " · " .. won(m.price))
		return
	end
	s.delivery = { menuId = id :: string, at = os.clock() + m.wait }
	ctx.notify(player, "home", "주문 완료 🛵", string.format("%s · 약 %d초 후 도착 (-%s)", m.name, m.wait, won(m.price)), { sound = "cash" })
end

local function windowPhoto(player: Player)
	local d = Profiles.get(player)
	local inst = where[player]
	if not d or not inst then
		return
	end
	local s = HS(player)
	if os.clock() - s.lastPhoto < G.HOME_PHOTO_COOLDOWN then
		ctx.notify(player, "home", "찰칵 📸", "사진을 저장했어요")
		return
	end
	s.lastPhoto = os.clock()
	local daily = G.housingDaily(d)
	daily.photos += 1
	local gain: { [string]: number } = { happiness = 3 }
	if daily.photos == 1 then
		gain.popularity = 0.5
	end
	if daily.photos > 3 then
		gain = { happiness = 1 }
	end
	local view = G.HOME_TIERS[inst.tierKey] and G.HOME_TIERS[inst.tierKey].view or "alley"
	local applied = ctx.addStats(player, gain, nil, true)
	ctx.notify(player, "stat", if view == "sea" then "오션뷰 인증샷 📸" else "창밖 감성샷 📸", G.describeStats(applied) .. (if daily.photos == 1 then " · SNS 업로드!" else ""))
	ctx.changed(player, "housing")
end

-------------------------------------------------------------------------------------------------
-- HomeAction dispatch
-------------------------------------------------------------------------------------------------
local handlers: { [string]: (Player, any) -> () } = {
	enter = function(player, p)
		Housing.enter(player, if p.via == "phone" then "phone" else "entrance")
	end,
	leave = function(player)
		Housing.leave(player)
	end,
	ring = ring,
	answerDoor = answerDoor,
	invite = invite,
	acceptInvite = function(player, p)
		acceptInvite(player, p, true)
	end,
	declineInvite = function(player, p)
		acceptInvite(player, p, false)
	end,
	kick = kick,
	standUp = function(player)
		unseat(player)
	end,
	tv = function(player)
		local inst = where[player]
		if inst and Core.canUse("tv", inst.occupants[player]) then
			toggleTv(inst, player)
		end
	end,
	eat = function(player)
		eatHome(player)
	end,
	groceries = function(player)
		groceries(player)
	end,
	delivery = delivery,
	windowPhoto = function(player)
		windowPhoto(player)
	end,
	openPanel = function(player, p)
		local d = Profiles.get(player)
		if not d then
			return
		end
		local name = p.panel
		if name == "guests" then
			local inst = instances[player]
			panel(player, "guests", { guests = if inst then guestList(inst) else {}, maxGuests = if inst then G.homeGuestLimit(inst.tierKey) else 0, atHome = ownerAtHome(player) ~= nil })
			return
		end
		if name == "mailbox" then
			panel(player, "mailbox", mailboxData(d))
			return
		end
		local inst = ownInstanceInside(player)
		if not inst then
			return
		end
		if name == "fridge" then
			local data = fridgeData(d)
			local sd = HS(player).delivery
			data.delivery = if sd then { menuId = sd.menuId, eta = math.max(0, math.ceil(sd.at - os.clock())) } else false
			panel(player, "fridge", data)
		elseif name == "desk" then
			panel(player, "desk", deskData(player, d))
		elseif name == "wardrobe" then
			panel(player, "wardrobe", wardrobeData(d))
		end
	end,
	placeFurniture = placeFurniture,
	resetSlot = resetSlot,
	sellSlot = sellSlot,
	sellStored = sellStored,
	upgrade = upgrade,
	buyWithLoan = function(player, p)
		if Life.buyHomeLoan then
			Life.buyHomeLoan(player, p.listingId)
		end
	end,
	repayLoan = function(player)
		repayLoan(player)
	end,
	rotateSlot = rotateSlot,
	setTheme = setTheme,
	openInterior = function(player)
		openInterior(player)
	end,
	tour = startTour,
	compliment = function(player)
		compliment(player)
	end,
}

local function onAction(player: Player, action: any, payload: any)
	if type(action) ~= "string" or not handlers[action] or not G.HOME_ACTIONS[action] then
		return
	end
	if payload ~= nil and type(payload) ~= "table" then
		return
	end
	if not Util.bucket(player, 6, 12) then
		return
	end
	if not Util.cooldown(player, "homeAct:" .. action, G.HOME_ACTIONS[action]) then
		return
	end
	if not Profiles.get(player) then
		ctx.notify(player, "info", "잠시만요", "프로필을 불러오는 중이에요")
		return
	end
	local ok, err = pcall(handlers[action], player, payload or {})
	if not ok then
		warn(string.format("[GwangalliGameplay] HomeAction %s from %s failed: %s", action, player.Name, tostring(err)))
	end
end

local function onQuery(player: Player, what: any): any
	if what ~= "summary" or not Util.bucket(player, 2, 6) then
		return nil
	end
	local d = Profiles.get(player)
	if not d then
		return nil
	end
	local inst, role = Housing.where(player)
	local quotes = {}
	for _, id in G.LISTING_ORDER do
		local q = G.mortgageQuote(id)
		if q then
			quotes[id] = q
		end
	end
	local h = d.home
	local l = h and G.LISTINGS[h.listingId]
	return {
		home = if h and l then { listingId = h.listingId, tier = h.tier, tierKey = l.tierKey, name = l.name, owned = h.owned, value = G.homeValue(h, d), dueIn = math.floor(h.dueIn or 0), missed = h.missed or 0 } else false,
		housing = G.housingView(d),
		inHome = inst ~= nil,
		role = role or false,
		mortgage = quotes,
		netWorth = G.netWorth(d),
	}
end

-- The HomeQuery "summary" (also for server code: Housing.summary(player)).
function Housing.summary(player: Player): any
	return onQuery(player, "summary")
end

-------------------------------------------------------------------------------------------------
-- Hooks from Life
-------------------------------------------------------------------------------------------------
-- The player's home changed (rent / buy / eviction / foreclosure): the old instance goes away.
function Housing.onHomeChanged(player: Player, why: string?)
	local inst = instances[player]
	local d = Profiles.get(player)
	if not inst then
		return
	end
	if d and d.home and d.home.listingId == inst.listingId then
		return
	end
	local title, body = "이사했어요 📦", "새 집으로는 폰 → 부동산 → 집으로 가기, 또는 새 건물 입구로 가요"
	if why == "evicted" then
		title, body = "퇴거 😢", "짐(가구)은 창고에 보관했어요"
	elseif why == "foreclosed" then
		title, body = "경매로 집을 잃었어요 😢", "가구는 창고에 보관했어요"
	end
	local list = {}
	for p in inst.occupants do
		table.insert(list, p)
	end
	for _, p in list do
		local target = entranceFor(inst.tierKey, nil, inst.entry[p])
		detach(p)
		if target and p.Parent == Players then
			task.spawn(function()
				teleportInto(p, target, true, "📦")
				if p == player then
					ctx.notify(p, "home", title, body)
				else
					ctx.notify(p, "home", "집주인이 이사했어요 📦", "다음에 새 집에 놀러 가요!")
				end
			end)
		end
	end
	destroyInstance(inst)
end

-- Records bills for the daily charge events (called by Life.advance).
function Housing.onHomeEvents(player: Player, d: any, events: { any }, listingName: string?)
	local now = os.time()
	for _, e in events do
		if e.kind == "charged" then
			local l = d.home and G.LISTINGS[d.home.listingId]
			local kind = if l and l.kind == "rent" then "rent" else "upkeep"
			local label = if kind == "rent" then "월세 자동이체" else "관리비"
			if e.loan and e.loan > 0 then
				G.addBill(d, "upkeep", label, e.amount - e.loan, true, now)
				G.addBill(d, "loan", "주택담보대출 상환", e.loan, true, now)
			else
				G.addBill(d, kind, label, e.amount, true, now)
			end
			local amt, paid = G.chargeUtilities(d, now)
			if amt > 0 then
				if paid then
					ctx.changed(player, "cash", "bank")
				else
					ctx.notify(player, "home", "공과금 미납 💡", won(amt) .. " · 우편함을 확인해 주세요")
				end
			end
		elseif e.kind == "missed" then
			G.addBill(d, "missed", (if e.loan then "관리비·대출 미납" else "월세 미납") .. string.format(" (%d일째)", e.missed or 1), e.amount, false, now)
		elseif e.kind == "evicted" then
			G.addBill(d, "evicted", (listingName or "집") .. " 계약 해지 (퇴거)", e.amount or 0, false, now)
		elseif e.kind == "foreclosed" then
			G.addBill(d, "foreclosed", (listingName or "집") .. " 경매 · 정산금 " .. won(e.refund or 0), e.refund or 0, true, now)
		elseif e.kind == "loanPaid" then
			G.addBill(d, "loanPaid", "주택담보대출 완납 🎉", 0, true, now)
		end
	end
	if #events > 0 then
		ctx.changed(player, "housing")
	end
end

function Housing.onCharacter(player: Player)
	local inst = where[player]
	if inst then
		detach(player)
	end
	releaseStaged(player)
	local s = hsess[player]
	if s then
		s.posing = false
	end
end

function Housing.onLeave(player: Player)
	local inst = where[player]
	if inst then
		detach(player, true)
	end
	local own = instances[player]
	if own then
		evacuate(own, "집주인이 게임을 떠났어요", "다음에 또 놀러 와요!")
		destroyInstance(own)
	end
	releaseStaged(player)
	Core.forget(visits, player)
	hsess[player] = nil
end

-------------------------------------------------------------------------------------------------
-- Tick: occupancy guard, TV happiness, deliveries, idle cleanup
-------------------------------------------------------------------------------------------------
local function inBounds(inst: Inst, pos: Vector3, margin: number): boolean
	local rel = inst.bboxCF:PointToObjectSpace(pos)
	local s = inst.bboxSize
	return math.abs(rel.X) <= s.X / 2 + margin and math.abs(rel.Y) <= s.Y / 2 + margin and math.abs(rel.Z) <= s.Z / 2 + margin
end

local function tick()
	local now = os.clock()
	for player, inst in where do
		if player.Parent ~= Players or not inst.model.Parent then
			where[player] = nil
			inst.occupants[player] = nil
			continue
		end
		local _, humanoid, root = Util.alive(player)
		if root and humanoid then
			local pos = root.Position
			if not inBounds(inst, pos, 30) then
				local rel = inst.bboxCF:PointToObjectSpace(pos)
				local s = inst.bboxSize
				if rel.Y < -s.Y / 2 and math.abs(rel.X) <= s.X / 2 + 30 and math.abs(rel.Z) <= s.Z / 2 + 30 and pos.Y > 1000 then
					-- fell through the floor: put back
					ctx.allowTeleport(player, 5)
					Util.teleportTo(player, spawnPart(inst), 2)
				else
					-- moved away by another system (quick travel, taxi, …)
					detach(player)
				end
				continue
			end
			-- TV watching on a seat of this home
			if inst.tvOn and humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(inst.model) then
				local s = HS(player)
				s.tvT += 1
				if s.tvT >= G.HOME_TV_EVERY then
					s.tvT = 0
					local d = Profiles.get(player)
					if d then
						local daily = G.housingDaily(d)
						if daily.tv < G.HOME_TV_DAILY_MAX then
							daily.tv += 1
							ctx.addStats(player, { happiness = 1 }, nil, true)
							s.tvNotified += 1
							if s.tvNotified % 4 == 1 then
								ctx.notify(player, "stat", "TV 보는 중 📺", "행복 +1 · 오늘 " .. daily.tv .. "/" .. G.HOME_TV_DAILY_MAX)
							end
						end
					end
				end
			end
		end
	end
	for player, s in hsess do
		if s.delivery and now >= s.delivery.at and player.Parent == Players then
			local id = s.delivery.menuId
			pcall(deliveryArrive, player, id)
		end
	end
	for owner, inst in instances do
		if owner.Parent ~= Players then
			destroyInstance(inst)
		elseif next(inst.occupants) == nil and inst.emptySince and now - inst.emptySince > G.HOME_IDLE_DESTROY then
			destroyInstance(inst)
		end
	end
	-- 둘러보기 units live only while their viewer is inside
	for viewer, inst in staged do
		if viewer.Parent ~= Players or (next(inst.occupants) == nil and inst.emptySince and now - inst.emptySince > 5) then
			destroyInstance(inst)
		end
	end
	-- expire stale doorbells so the owner's popup does not linger forever
	for owner, r in visits.rings do
		for visitor, t in r do
			if now - t > G.HOME_RING_TTL then
				r[visitor] = nil
			end
		end
		if next(r) == nil then
			visits.rings[owner] = nil
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Owner / test hook: ServerStorage.GwangalliHomesAPI (BindableFunction, server scripts only)
--   Invoke(op, userId?, a?, b?) ops:
--     status            -> { ok, inside, role, listingId, tierKey, staged, slots = { [id] = { variant,
--                          rot, lights, built } }, rooms = { [room] = { wall, floor, light = {r,g,b},
--                          wallMat, floorMat } }, lights (real Light count), decor, bank, cash }
--     open              -> opens the 인테리어 / 집 구경 mode for the player (as the wall panel does)
--     grant <amount>    -> + bank (only with ServerStorage attribute GwangalliTestMode = true or in Studio)
-------------------------------------------------------------------------------------------------
local function apiPlayer(userId: any): Player?
	if type(userId) == "number" then
		local ok, p = pcall(Players.GetPlayerByUserId, Players, userId)
		if ok and p then
			return p
		end
	end
	return Players:GetPlayers()[1]
end

local function c3(c: Color3): { number }
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function testApi(op: string, userId: any, a: any, _b: any): any
	local player = apiPlayer(userId)
	if not player then
		return { ok = false, message = "no player" }
	end
	local d = Profiles.get(player)
	if op == "status" then
		local inst = where[player]
		local out: any = { ok = true, inside = inst ~= nil, role = inst and inst.occupants[player] or false, bank = d and d.bank or 0, cash = d and d.cash or 0, decor = d and G.homeDecor(d) or 0 }
		if inst then
			out.listingId, out.tierKey, out.staged = inst.listingId, inst.tierKey, inst.staged
			out.slots = {}
			for id, rec in inst.slots do
				out.slots[id] = { variant = rec.current or false, rot = rec.rot or 0, lights = rec.lights or 0, built = rec.model ~= nil, canRotate = rec.canRotate, room = rec.room or false }
			end
			out.rooms = {}
			for _, room in inst.themes.order do
				local e = inst.themes.rooms[room]
				local r: any = {}
				if e.wall[1] then
					r.wall, r.wallMat = c3(e.wall[1].Color), e.wall[1].Material.Name
				end
				if e.floor[1] then
					r.floor, r.floorMat = c3(e.floor[1].Color), e.floor[1].Material.Name
				end
				if e.lights[1] then
					r.light = c3(e.lights[1].Color)
				elseif e.light[1] then
					r.light = c3(e.light[1].Color)
				end
				out.rooms[room] = r
			end
			local n = 0
			for _, dd in inst.model:GetDescendants() do
				if dd:IsA("Light") then
					n += 1
				end
			end
			out.lights = n
		end
		return out
	elseif op == "open" then
		openInterior(player)
		return { ok = true }
	elseif op == "grant" then
		local testMode = ServerStorage:GetAttribute("GwangalliTestMode") == true
		local okS, studio = pcall(function()
			return game:GetService("RunService"):IsStudio()
		end)
		if not testMode and not (okS and studio) then
			return { ok = false, message = "test mode only" }
		end
		local amt = Util.int(a, 1, 1e10)
		if not amt or not d then
			return { ok = false, message = "bad amount" }
		end
		ctx.ledger(player, "bank", amt, "테스트 지원금", true)
		return { ok = true, bank = d.bank }
	end
	return { ok = false, message = "unknown op " .. op }
end

-------------------------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------------------------
function Housing.init(context: any, lifeModule: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	Life = lifeModule
	Players = game:GetService("Players")
	CollectionService = game:GetService("CollectionService")
	ServerStorage = game:GetService("ServerStorage")
	ReplicatedStorage = game:GetService("ReplicatedStorage")

	-- legacy: a Workspace "HomeUnit_<n>" becomes a template
	for _, c in workspace:GetChildren() do
		if c:IsA("Model") and string.match(c.Name, "^HomeUnit_") then
			local folder = ServerStorage:FindFirstChild(G.HOME_TEMPLATE_FOLDER)
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = G.HOME_TEMPLATE_FOLDER
				folder.Parent = ServerStorage
			end
			c.Parent = folder
		end
	end
	local folder = workspace:FindFirstChild(G.HOME_INSTANCE_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = G.HOME_INSTANCE_FOLDER
		folder.Parent = workspace
	end
	instFolder = folder
	local hr = ServerStorage:FindFirstChild("GwangalliHomeHidden")
	if not hr then
		hr = Instance.new("Folder")
		hr.Name = "GwangalliHomeHidden"
		hr.Parent = ServerStorage
	end
	hiddenRoot = hr

	-- remotes
	local rf = ReplicatedStorage:FindFirstChild(G.RemotesFolder)
	if not rf then
		rf = Instance.new("Folder")
		rf.Name = G.RemotesFolder
		rf.Parent = ReplicatedStorage
	end
	local function remote(name: string, className: string): any
		local r = rf:FindFirstChild(name)
		if r and r.ClassName ~= className then
			r:Destroy()
			r = nil
		end
		if not r then
			r = Instance.new(className)
			r.Name = name
			r.Parent = rf
		end
		return r
	end
	remotes.HomeAction = remote("HomeAction", "RemoteEvent")
	remotes.HomeState = remote("HomeState", "RemoteEvent")
	remotes.HomeQuery = remote("HomeQuery", "RemoteFunction")
	remotes.HomeAction.OnServerEvent:Connect(onAction)
	remotes.HomeQuery.OnServerInvoke = function(player: Player, what: any)
		local ok, res = pcall(onQuery, player, what)
		return if ok then res else nil
	end

	-- owner / test hook (see testApi)
	local bf = ServerStorage:FindFirstChild("GwangalliHomesAPI")
	if not bf or not bf:IsA("BindableFunction") then
		bf = Instance.new("BindableFunction")
		bf.Name = "GwangalliHomesAPI"
		bf.Parent = ServerStorage
	end
	;(bf :: BindableFunction).OnInvoke = function(op: any, userId: any, a: any, b: any)
		local ok, res = pcall(testApi, tostring(op), userId, a, b)
		if not ok then
			return { ok = false, message = tostring(res) }
		end
		return res
	end

	-- entrances
	local tag = G.HomeTags.Entrance
	CollectionService:GetInstanceAddedSignal(tag):Connect(entranceAdded)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(entranceRemoved)
	for _, e in CollectionService:GetTagged(tag) do
		entranceAdded(e)
	end
	task.delay(6, function()
		local ok, err = pcall(ensureFallbackEntrances)
		if not ok then
			warn("[GwangalliGameplay] home entrances: " .. tostring(err))
		end
	end)
	task.delay(30, function()
		pcall(ensureFallbackEntrances)
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GwangalliGameplay] housing tick failed: " .. tostring(err))
			end
		end
	end)
end

return Housing
