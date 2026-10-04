-- Decor: 인테리어 — furniture placement (배치 / 이동 / 회전 / 삭제) and per-room themes (벽지 · 바닥 ·
-- 조명) in the player's own home. The client runs the build mode (top-down camera, ghost preview,
-- grid, rotate); the server validates everything:
--   * owner only, inside the unit's rectangle, not through walls / built-in fixtures / other pieces /
--     door swing zones (GetPartBoundsInBox on the unit), Config.MAX_FURNITURE pieces
--   * prices from Shared.Furniture / Shared.Palette; removed pieces go to storage (창고) or are sold
--     back at 50 %
--   * layouts are saved in TEMPLATE space (Units.toFrame), so they survive mirrored units / moving to
--     another unit of the same type
--   Decor.buildLayout(unit, into, record)  (the Builder.decorHook used by Housing)

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Furniture = Shared.Furniture
local Palette = Shared.Palette
local Util = Shared.Util

local Decor = {}

local Registry: any
local services: any
local Units: any

local sessions: { [Player]: { unitId: string, t: number } } = {}

local function unitFrame(u: any): CFrame
	return u.rec.cf * CFrame.new(0, u.fl.y, 0) * u.frame
end

local function ownerUnit(p: Player): any?
	local H = services.Housing
	if not H then
		return nil
	end
	local u = H.unitOf(p)
	return u
end

-------------------------------------------------------------------------------------------------
-- themes
-------------------------------------------------------------------------------------------------
local function remember(part: BasePart)
	if part:GetAttribute("OrigColor") == nil then
		part:SetAttribute("OrigColor", part.Color)
		part:SetAttribute("OrigMaterial", part.Material.Name)
	end
end

-- themes: { [templateRoomId] = { wall = id, floor = id, light = id } }; nil -> defaults
function Decor.applyThemes(u: any, themes: any?)
	local m = u.model
	if not m then
		return
	end
	local prefix = u.id .. ":"
	for _, part in m:GetDescendants() do
		if part:IsA("BasePart") and CollectionService:HasTag(part, "GwB_Finish") then
			local kind = part:GetAttribute("FinishKind")
			local rid = part:GetAttribute("RoomId")
			if (kind == "wall" or kind == "floor") and type(rid) == "string" then
				local roomKey = string.sub(rid, #prefix + 1)
				local th = themes and themes[roomKey]
				local pick = th and Palette.find(if kind == "wall" then Palette.WALLPAPER else Palette.FLOORING, th[kind])
				remember(part)
				if pick then
					part.Material = Shared.Kit.mat(pick.mat)
					part.Color = Shared.Kit.col(pick.color)
				else
					local c = part:GetAttribute("OrigColor")
					local mt = part:GetAttribute("OrigMaterial")
					if typeof(c) == "Color3" then
						part.Color = c
					end
					if type(mt) == "string" then
						part.Material = Shared.Kit.mat(mt)
					end
				end
			end
		end
	end
	-- lights
	for _, l in m:GetDescendants() do
		if l:IsA("Light") and type(l:GetAttribute("RoomId")) == "string" then
			local roomKey = string.sub(l:GetAttribute("RoomId") :: string, #prefix + 1)
			local th = themes and themes[roomKey]
			local pick = Palette.find(Palette.LIGHTING, th and th.light or "neutral") or Palette.LIGHTING[1]
			l.Color = Shared.Kit.col(pick.color)
			l.Brightness = pick.brightness
			local lamp = l.Parent
			if lamp and lamp:IsA("BasePart") and CollectionService:HasTag(lamp, "GwB_Lamp") then
				lamp:SetAttribute("LampOn", Shared.Kit.col(pick.color):Lerp(Color3.new(1, 1, 1), 0.5))
				if l.Enabled then
					lamp.Color = lamp:GetAttribute("LampOn") :: Color3
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- layout building
-------------------------------------------------------------------------------------------------
local function buildItem(u: any, into: Instance, it: any, ownerId: number): Model?
	local fx, fz, fyaw = Units.toFrame(u, it.x, it.z, it.yaw)
	local def = Furniture.ITEMS[it.id]
	if not def then
		return nil
	end
	local cf = unitFrame(u) * CFrame.new(fx, it.y or 0, fz) * CFrame.Angles(0, math.rad(fyaw), 0)
	local m = Furniture.build(it.id, into, cf, it.cw or 1, { UnitId = u.id, Uid = it.uid, OwnerUserId = ownerId, Placed = true })
	if m then
		CollectionService:AddTag(m, "GwB_Placed")
	end
	return m
end

function Decor.buildLayout(u: any, into: Instance, record: any?)
	local ownerId = 0
	local H = services.Housing
	local o = H and H.ownerOf(u.id)
	if o then
		ownerId = o.UserId
	end
	if record and record.layout and record.template == u.template then
		for _, it in record.layout.items do
			buildItem(u, into, it, ownerId)
		end
		Decor.applyThemes(u, record.themes)
	else
		Decor.applyThemes(u, nil)
	end
end

-------------------------------------------------------------------------------------------------
-- validation
-------------------------------------------------------------------------------------------------
local function validPlacement(u: any, itemId: string, x: number, z: number, yaw: number, ignoreUid: string?): (boolean, string?)
	local def = Furniture.ITEMS[itemId]
	if not def or def.fixed then
		return false, "배치할 수 없는 물건이에요"
	end
	local L = u.layout
	local fw, fd = Furniture.footprint(itemId, yaw)
	local margin = 0.3
	if x - fw / 2 < margin or x + fw / 2 > L.w - margin or z - fd / 2 < margin or z + fd / 2 > L.d - margin then
		return false, "집 밖으로 나가요"
	end
	if def.flat then
		return true, nil
	end
	-- overlap test in the world
	local frame = unitFrame(u)
	local y0 = (def.mountY or 0) + 0.25
	local h = math.max(0.4, def.h - 0.35)
	local cf = frame * CFrame.new(x, y0 + h / 2, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local size = Vector3.new(def.w - 0.12, h, def.d - 0.12)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { u.model }
	params.MaxParts = 64
	local parts = workspace:GetPartBoundsInBox(cf, size, params)
	for _, part in parts do
		local fm = part:FindFirstAncestorWhichIsA("Model")
		local uid = fm and fm:GetAttribute("Uid")
		if ignoreUid and uid == ignoreUid then
			continue
		end
		local name: string = part.Name
		local skin = name == "Wallpaper" or name == "Floor" or name == "Ceiling" or string.sub(name, 1, 5) == "Room_"
		local blocking = part.CanCollide or name == "Base" or name == "SwingZone"
		if blocking then
			if skin then
				continue
			end
			if def.wall and (name == "Base") and fm and fm:GetAttribute("Fixed") then
				-- wall pieces may hang above built-in counters? no: still blocked
				return false, "다른 물건과 겹쳐요"
			end
			return false, if name == "SwingZone" then "문이 열리는 자리예요" elseif string.find(name, "Wall") or name == "Partition" then "벽을 뚫을 수 없어요" else "다른 물건과 겹쳐요"
		end
	end
	return true, nil
end

-------------------------------------------------------------------------------------------------
-- requests
-------------------------------------------------------------------------------------------------
local function snapshot(p: Player, u: any): any
	local H = services.Housing
	local r = H.record(p)
	local rooms = {}
	for _, rm in u.layout.rooms do
		local th = r.themes[rm.id] or {}
		table.insert(rooms, { id = rm.id, kind = rm.kind, label = rm.label, x0 = rm.x0, z0 = rm.z0, x1 = rm.x1, z1 = rm.z1, wall = th.wall, floor = th.floor, light = th.light })
	end
	local items = {}
	for _, it in r.layout.items do
		local fx, fz, fyaw = Units.toFrame(u, it.x, it.z, it.yaw)
		table.insert(items, { uid = it.uid, id = it.id, x = fx, z = fz, yaw = fyaw, cw = it.cw })
	end
	return {
		ok = true,
		unitId = u.id,
		frame = unitFrame(u),
		w = u.layout.w,
		d = u.layout.d,
		h = u.fl.h - Config.SLAB,
		rooms = rooms,
		items = items,
		storage = r.storage,
		catalog = Furniture.shopList(),
		categories = Furniture.CATEGORIES,
		wallpaper = Palette.WALLPAPER,
		flooring = Palette.FLOORING,
		lighting = Palette.LIGHTING,
		max = Config.MAX_FURNITURE,
		grid = Config.GRID,
		rotate = Config.ROTATE_STEP,
		balance = services.Economy.balance(p),
	}
end

local function inUnit(p: Player, u: any, pad: number): boolean
	local pos = Registry.pos(p)
	if not pos then
		return false
	end
	local l = unitFrame(u):PointToObjectSpace(pos)
	return l.X > -pad and l.X < u.layout.w + pad and l.Z > -pad and l.Z < u.layout.d + pad and l.Y > -3 and l.Y < u.fl.h + 2
end

function Decor.busyFloor(rec: any, fl: any): boolean
	for _, s in sessions do
		local u = Registry.unit(s.unitId)
		if u and u.rec == rec and u.fl == fl then
			return true
		end
	end
	return false
end

function Decor.init(ctx: any)
	Registry = ctx.Registry
	services = ctx.services
	Units = ctx.Builder.Units

	Registry.on("decor.begin", function(p: Player)
		local u = ownerUnit(p)
		if not u then
			return { ok = false, msg = "내 집에서만 인테리어를 할 수 있어요" }
		end
		if not inUnit(p, u, 2) then
			return { ok = false, msg = "집 안에 들어가서 시작해요 (월패드 · 인테리어 버튼)" }
		end
		if services.Streaming then
			task.spawn(services.Streaming.ensureFloor, u.rec, u.fl)
		end
		sessions[p] = { unitId = u.id, t = os.clock() }
		return snapshot(p, u)
	end)
	Registry.on("decor.end", function(p: Player)
		sessions[p] = nil
		return { ok = true }
	end)
	local function current(p: Player): any?
		local s = sessions[p]
		local u = s and Registry.unit(s.unitId)
		if not u or ownerUnit(p) ~= u then
			return nil
		end
		return u
	end
	local function furnishOf(u: any): Instance?
		return u.model and u.model:FindFirstChild("Furnish")
	end
	local function findModel(u: any, uid: string): Model?
		local into = furnishOf(u)
		if not into then
			return nil
		end
		for _, m in into:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Uid") == uid then
				return m
			end
		end
		return nil
	end

	Registry.on("decor.place", function(p: Player, d: any)
		local u = current(p)
		if not u then
			return { ok = false, msg = "인테리어 모드가 아니에요" }
		end
		local r = services.Housing.record(p)
		local itemId = d.itemId
		local def = Furniture.ITEMS[itemId]
		if type(itemId) ~= "string" or not def then
			return { ok = false }
		end
		if #r.layout.items >= Config.MAX_FURNITURE then
			return { ok = false, msg = "가구는 최대 " .. Config.MAX_FURNITURE .. "개까지예요" }
		end
		local x, z = Util.round(tonumber(d.x) or 0, Config.GRID), Util.round(tonumber(d.z) or 0, Config.GRID)
		local yaw = Util.round(tonumber(d.yaw) or 0, Config.ROTATE_STEP) % 360
		local ok, msg = validPlacement(u, itemId, x, z, yaw, nil)
		if not ok then
			return { ok = false, msg = msg }
		end
		local fromStorage = (r.storage[itemId] or 0) > 0
		if fromStorage then
			r.storage[itemId] -= 1
			if r.storage[itemId] <= 0 then
				r.storage[itemId] = nil
			end
		else
			local paid, pmsg = services.Economy.spend(p, def.price, "가구 · " .. def.name)
			if not paid then
				return { ok = false, msg = pmsg }
			end
		end
		local tx, tz, tyaw = Units.fromFrame(u, x, z, yaw)
		local it = { uid = HttpService:GenerateGUID(false), id = itemId, x = tx, z = tz, yaw = tyaw, cw = math.clamp(math.floor(tonumber(d.cw) or 1), 1, #def.colors), y = 0 }
		table.insert(r.layout.items, it)
		services.Housing.markDirty(p)
		local into = furnishOf(u)
		if into then
			buildItem(u, into, it, p.UserId)
		end
		return { ok = true, uid = it.uid, msg = if fromStorage then "창고에서 꺼내 배치했어요" else (def.name .. " 구매 · 배치 (" .. Util.won(def.price) .. ")"), balance = services.Economy.balance(p) }
	end)

	Registry.on("decor.move", function(p: Player, d: any)
		local u = current(p)
		if not u then
			return { ok = false }
		end
		local r = services.Housing.record(p)
		local it = nil
		for _, e in r.layout.items do
			if e.uid == d.uid then
				it = e
			end
		end
		if not it then
			return { ok = false }
		end
		local x, z = Util.round(tonumber(d.x) or 0, Config.GRID), Util.round(tonumber(d.z) or 0, Config.GRID)
		local yaw = Util.round(tonumber(d.yaw) or 0, Config.ROTATE_STEP) % 360
		local ok, msg = validPlacement(u, it.id, x, z, yaw, it.uid)
		if not ok then
			return { ok = false, msg = msg }
		end
		it.x, it.z, it.yaw = Units.fromFrame(u, x, z, yaw)
		if type(d.cw) == "number" then
			it.cw = math.clamp(math.floor(d.cw), 1, #Furniture.ITEMS[it.id].colors)
		end
		services.Housing.markDirty(p)
		local m = findModel(u, it.uid)
		if m then
			m:Destroy()
		end
		local into = furnishOf(u)
		if into then
			buildItem(u, into, it, p.UserId)
		end
		return { ok = true }
	end)

	Registry.on("decor.remove", function(p: Player, d: any)
		local u = current(p)
		if not u then
			return { ok = false }
		end
		local r = services.Housing.record(p)
		for i, e in r.layout.items do
			if e.uid == d.uid then
				table.remove(r.layout.items, i)
				local def = Furniture.ITEMS[e.id]
				if d.sell and def then
					services.Economy.earn(p, math.floor(def.price * 0.5), "중고 판매 · " .. def.name)
				else
					r.storage[e.id] = (r.storage[e.id] or 0) + 1
				end
				services.Housing.markDirty(p)
				local m = findModel(u, e.uid)
				if m then
					m:Destroy()
				end
				return { ok = true, msg = if d.sell then "반값에 팔았어요" else "창고에 넣었어요", storage = r.storage }
			end
		end
		return { ok = false }
	end)

	Registry.on("decor.theme", function(p: Player, d: any)
		local u = current(p)
		if not u then
			return { ok = false }
		end
		local kind = d.kind
		local list = if kind == "wall" then Palette.WALLPAPER elseif kind == "floor" then Palette.FLOORING elseif kind == "light" then Palette.LIGHTING else nil
		if not list then
			return { ok = false }
		end
		local pick = Palette.find(list, d.id)
		local roomOk = false
		for _, rm in u.layout.rooms do
			if rm.id == d.room then
				roomOk = true
				if kind ~= "light" and (rm.kind == "bath" or rm.kind == "veranda" or rm.kind == "utility") then
					return { ok = false, msg = "욕실 · 베란다는 타일 마감이라 바꿀 수 없어요" }
				end
			end
		end
		if not pick or not roomOk then
			return { ok = false }
		end
		local r = services.Housing.record(p)
		r.themes[d.room] = r.themes[d.room] or {}
		if r.themes[d.room][kind] ~= pick.id and pick.price > 0 then
			local paid, msg = services.Economy.spend(p, pick.price, "인테리어 · " .. pick.name)
			if not paid then
				return { ok = false, msg = msg }
			end
		end
		r.themes[d.room][kind] = pick.id
		services.Housing.markDirty(p)
		Decor.applyThemes(u, r.themes)
		return { ok = true, msg = pick.name .. " 적용!", balance = services.Economy.balance(p) }
	end)

	Players.PlayerRemoving:Connect(function(p)
		sessions[p] = nil
	end)
end

function Decor.start() end

return Decor
