-- Builder/Shops: INTERIOR TEMPLATES of the shops and the common rooms (lobbies, 관리사무소).
-- Each template has build(ctx, shop, frame) (structure: finishes, counters, kitchen, partitions, room
-- doors, points) and furnish(ctx, shop, frame, into) (tables, seats, props, staff, products) so a shop's
-- heavy props exist only while players are around.
--
-- Shop space: x across the bay (0..w), z from the entrance side (0) to the back (d), y above the FFL.
-- Interaction anchors are invisible Parts tagged GwB_ShopPoint (attrs ShopId, Point, Index, TableId...)
-- wired by the server ShopService; seats are Seat parts tagged GwB_Seat. Adding a shop type = adding a
-- template here + a flow in ShopFlows; nothing else changes.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Kit = Shared.Kit
local Config = Shared.Config
local Palette = Shared.Palette
local Furniture = Shared.Furniture
local Menus = Shared.Menus
local Util = Shared.Util
local Rng = Shared.Rng

local Core = require(script.Parent.Core)

local Shops = {}

local V3, CF = Vector3.new, CFrame.new
local rad = math.rad
local min, max, floor = math.min, math.max, math.floor
local F = Palette.FINISH

-------------------------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------------------------
local function point(parent: Instance, cf: CFrame, shop: any, kind: string, extra: any?): BasePart
	local attrs = { ShopId = shop.id, Point = kind, ShopKind = shop.kind }
	if extra then
		for k, v in extra do
			attrs[k] = v
		end
	end
	local p = Kit.anchor(parent, cf, "Point_" .. kind, attrs, { "GwB_ShopPoint" }, V3(1.2, 1.2, 1.2))
	return p
end
Shops.point = point

-- finishes for a whole bay (floor / ceiling / back + side wall linings) + ceiling lights grid
local function finishes(m: Instance, frame: CFrame, w: number, d: number, h: number, look: any, shopId: string, rng: any)
	local fm = Kit.box(m, frame, 0, 0, 0, w, 0.06, d, look.floorMat or "CeramicTiles", look.floor or { 210, 206, 198 }, { collide = false, name = "ShopFloor" })
	fm:SetAttribute("ShopId", shopId)
	local ceilY = h - Config.SLAB
	if look.ceiling ~= false then
		Kit.box(m, frame, 0, ceilY - 0.1, 0, w, ceilY, d, look.ceilMat or "Plaster", look.ceilColor or { 240, 240, 236 }, { collide = false, name = "ShopCeiling" })
	end
	-- linings on the side and back walls (the walls themselves belong to the building)
	local wc = look.wall or { 236, 234, 228 }
	local wm = look.wallMat or "Plaster"
	Kit.box(m, frame, 0.3, 0.06, d - 0.36, w - 0.3, ceilY - 0.1, d - 0.3, wm, wc, { collide = false, name = "Lining" })
	if look.sides ~= false then
		Kit.box(m, frame, 0.3, 0.06, 0.3, 0.36, ceilY - 0.1, d - 0.3, wm, wc, { collide = false, name = "Lining" })
		Kit.box(m, frame, w - 0.36, 0.06, 0.3, w - 0.3, ceilY - 0.1, d - 0.3, wm, wc, { collide = false, name = "Lining" })
	end
	-- light grid
	local step = look.lightStep or 9
	local nx = max(1, floor(w / step))
	local nz = max(1, floor(d / step))
	for ix = 1, nx do
		for iz = 1, nz do
			local lx = w * (ix - 0.5) / nx
			local lz = d * (iz - 0.5) / nz
			Core.ceilingLight(m, frame * CF(lx, ceilY - 0.18, lz), {
				size = look.lightSize or V3(2.2, 0.12, 2.2),
				color = look.lampColor,
				lightColor = look.lightColor,
				brightness = look.brightness or 1.1,
				range = look.range or 20,
				group = "shop",
				flicker = look.flicker and rng:chance(0.15),
			})
		end
	end
end
Shops.finishes = finishes

-- simple static staff figure (no Humanoid: costs nothing, never falls over)
function Shops.staff(parent: Instance, cf: CFrame, look: any): Model
	local m = Kit.model(parent, "Staff_" .. (look.name or "직원"))
	local skin = look.skin or { 236, 200, 170 }
	local top = look.top or { 240, 240, 240 }
	local apron = look.apron
	local pants = look.pants or { 40, 40, 46 }
	local hair = look.hair or { 30, 24, 20 }
	local function P(x0, y0, z0, x1, y1, z1, mat, color, name)
		return Kit.box(m, cf, x0, y0, z0, x1, y1, z1, mat, color, { collide = false, name = name })
	end
	P(-0.55, 0, -0.3, -0.05, 2.6, 0.3, "SmoothPlastic", pants, "LegL")
	P(0.05, 0, -0.3, 0.55, 2.6, 0.3, "SmoothPlastic", pants, "LegR")
	P(-0.62, 2.6, -0.35, 0.62, 4.6, 0.35, "SmoothPlastic", top, "Torso")
	if apron then
		P(-0.58, 1.6, -0.4, 0.58, 4.2, -0.34, "Fabric", apron, "Apron")
	end
	P(-1.05, 2.6, -0.3, -0.62, 4.6, 0.3, "SmoothPlastic", top, "ArmL")
	P(0.62, 2.6, -0.3, 1.05, 4.6, 0.3, "SmoothPlastic", top, "ArmR")
	local head = Kit.part(m, cf * CF(0, 5.15, 0), V3(1.0, 1.1, 1.0), "SmoothPlastic", skin, { collide = false, name = "Head" })
	P(-0.52, 5.5, -0.45, 0.52, 5.85, 0.52, "SmoothPlastic", hair, "Hair")
	P(-0.28, 5.2, -0.52, -0.14, 5.34, -0.5, "SmoothPlastic", { 20, 20, 20 }, "Eye")
	P(0.14, 5.2, -0.52, 0.28, 5.34, -0.5, "SmoothPlastic", { 20, 20, 20 }, "Eye")
	if look.hat then
		P(-0.56, 5.75, -0.56, 0.56, 6.1, 0.56, "SmoothPlastic", look.hat, "Hat")
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag"
	bb.Size = UDim2.fromOffset(120, 26)
	bb.StudsOffset = V3(0, 1.4, 0)
	bb.MaxDistance = 40
	bb.AlwaysOnTop = false
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 0.35
	t.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	t.TextColor3 = Color3.fromRGB(255, 255, 255)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Text = look.name or "직원"
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = t
	t.Parent = bb
	bb.Parent = head
	m:SetAttribute("Staff", true)
	m:SetAttribute("Bob", true)
	return m
end

-- counter: a box with a top
local function counter(parent: Instance, frame: CFrame, x0: number, z0: number, x1: number, z1: number, h: number, body: any, top: any, mat: string?)
	Kit.box(parent, frame, x0, 0, z0, x1, h - 0.2, z1, mat or "Wood", body, { name = "Counter" })
	Kit.box(parent, frame, x0 - 0.15, h - 0.2, z0 - 0.15, x1 + 0.15, h, z1 + 0.15, "Marble", top, { name = "CounterTop", collide = false })
end
Shops.counter = counter

-- menu board on a wall (SurfaceGui list)
local function menuBoard(parent: Instance, cf: CFrame, w: number, h: number, title: string, list: { any }, look: any?)
	local o = look or {}
	local p = Kit.part(parent, cf, V3(w, h, 0.15), "SmoothPlastic", o.bg or { 24, 26, 30 }, { name = "MenuBoard", collide = false })
	local lines = { title, "" }
	for _, it in list do
		table.insert(lines, string.format("%s  ·  %s", it.name, Util.won(it.price or 0)))
	end
	Kit.text(p, "front", table.concat(lines, "\n"), { color = o.fg or { 255, 236, 200 }, ppS = 36, light = 0, align = "left", font = Enum.Font.GothamMedium, maxDist = 60 })
	CollectionService:AddTag(p, "GwB_Sign")
	return p
end
Shops.menuBoard = menuBoard

local function stool(parent: Instance, frame: CFrame, x: number, z: number, h: number, color: any, attrs: any, yaw: number?)
	Kit.vcyl(parent, frame, x, h / 2, z, h, 0.25, "Metal", { 40, 40, 42 }, { collide = false })
	Kit.vcyl(parent, frame, x, h, z, 0.25, 1.4, "Leather", color, { collide = false })
	local s = Kit.part(parent, frame * CF(x, h + 0.2, z) * CFrame.Angles(0, rad(yaw or 0), 0), V3(1.6, 0.3, 1.6), "SmoothPlastic", { 0, 0, 0 }, { seat = true, tr = 1, name = "Seat", shadow = false, attrs = attrs })
	CollectionService:AddTag(s, "GwB_Seat")
	return s
end

local function chair(parent: Instance, frame: CFrame, x: number, z: number, yaw: number, color: any, attrs: any): BasePart
	local cf = frame * CF(x, 0, z) * CFrame.Angles(0, rad(yaw), 0)
	Kit.part(parent, cf * CF(0, 1.7, 0), V3(1.6, 0.25, 1.6), "Wood", color, { collide = false, name = "ChairSeat" })
	Kit.part(parent, cf * CF(0, 2.9, 0.75), V3(1.6, 2.2, 0.18), "Wood", color, { collide = false, name = "ChairBack" })
	for _, lx in { -0.65, 0.65 } do
		for _, lz in { -0.65, 0.65 } do
			Kit.part(parent, cf * CF(lx, 0.8, lz), V3(0.14, 1.6, 0.14), "Metal", { 40, 40, 42 }, { collide = false, name = "ChairLeg" })
		end
	end
	local s = Kit.part(parent, cf * CF(0, 1.95, 0), V3(1.6, 0.3, 1.6), "SmoothPlastic", { 0, 0, 0 }, { seat = true, tr = 1, name = "Seat", shadow = false, attrs = attrs })
	CollectionService:AddTag(s, "GwB_Seat")
	return s
end
Shops.chair = chair

-- a table with chairs (2 / 4) around it; returns the table model
local function diningTable(parent: Instance, frame: CFrame, shop: any, x: number, z: number, idx: number, opts: any): Model
	local o = opts or {}
	local tw, td = o.w or 4.6, o.d or 3.2
	local m = Kit.model(parent, "Table_" .. idx, { ShopId = shop.id, TableId = idx })
	local top = o.top or { 176, 136, 96 }
	Kit.box(m, frame, x - tw / 2, 2.6, z - td / 2, x + tw / 2, 2.85, z + td / 2, o.topMat or "Wood", top, { name = "Top" })
	Kit.box(m, frame, x - 0.2, 0, z - 0.2, x + 0.2, 2.6, z + 0.2, "Metal", { 40, 40, 42 }, { name = "Leg" })
	Kit.box(m, frame, x - tw / 2 + 0.3, 0, z - td / 2 + 0.3, x + tw / 2 - 0.3, 2.6, z + td / 2 - 0.3, "SmoothPlastic", { 0, 0, 0 }, { tr = 1, name = "Hit" })
	local seats = o.seats or 4
	local cc = o.chair or { 120, 86, 60 }
	local k = 0
	for _, side in { -1, 1 } do
		local cz = z + side * (td / 2 + 1.0)
		local cols = if seats >= 4 then { -1.1, 1.1 } else { 0 }
		for _, cx in cols do
			if k < seats then
				k += 1
				chair(m, frame, x + cx, cz, if side < 0 then 0 else 180, cc, { ShopId = shop.id, TableId = idx, Index = k })
			end
		end
	end
	point(m, frame * CF(x, 3.2, z), shop, "table", { TableId = idx })
	Kit.anchor(m, frame * CF(x, 2.9, z), "TrayPoint", { TableId = idx })
	return m
end
Shops.diningTable = diningTable

-------------------------------------------------------------------------------------------------
-- TEMPLATES
-------------------------------------------------------------------------------------------------
local T = {}
Shops.T = T

-- 편의점 GW25 -----------------------------------------------------------------------------------
T.cvs = {
	look = { floor = { 232, 232, 230 }, wall = { 246, 246, 244 }, lamp = { 255, 255, 255 }, lightColor = { 240, 248, 255 }, brightness = 1.4, lightStep = 7 },
	build = function(ctx, s, frame, m)
		local w, d = s.w, s.d
		finishes(m, frame, w, d, s.fl.h, T.cvs.look, s.id, ctx.rng)
		-- POS counter near the entrance (right side), the clerk works behind it
		counter(m, frame, w - 11, 5, w - 3.5, 7.4, 3.4, { 40, 110, 200 }, { 240, 240, 240 }, "SmoothPlastic")
		Kit.box(m, frame, w - 9.5, 3.4, 5.6, w - 8.3, 4.4, 6.6, "SmoothPlastic", { 30, 30, 34 }, { name = "POS", collide = false })
		local disp = Kit.box(m, frame, w - 9.4, 4.4, 5.65, w - 8.4, 5.2, 5.7, "Neon", { 60, 140, 255 }, { name = "PosScreen", collide = false })
		disp.Transparency = 0.3
		point(m, frame * CF(w - 7.2, 3.8, 4.4), s, "pay")
		-- cigarette / goods rack behind the counter
		Kit.box(m, frame, w - 11, 0, 9.6, w - 3.5, 7.5, 10.6, "SmoothPlastic", { 236, 236, 236 }, { name = "BackRack" })
		-- microwave / hot water / eating bar along the street window
		counter(m, frame, 1, 1.0, 13, 2.6, 3.6, { 220, 220, 216 }, { 240, 240, 236 }, "SmoothPlastic")
		local mw = Furniture.build("microwave", m, frame * CF(2.2, 3.6, 4.4) * CFrame.Angles(0, math.pi, 0), 1, { ShopId = s.id, Public = true })
		local wd = Furniture.build("water_dispenser", m, frame * CF(4.6, 0, 5.0) * CFrame.Angles(0, math.pi, 0), 1, { ShopId = s.id, Public = true })
		counter(m, frame, 1, 3.6, 3.6, 5.2, 3.6, { 220, 220, 216 }, { 240, 240, 236 }, "SmoothPlastic")
		if mw then
			point(m, frame * CF(2.2, 4.4, 5.8), s, "microwave")
		end
		if wd then
			point(m, frame * CF(4.6, 3.0, 6.4), s, "water")
		end
		-- 냉장 쇼케이스 (drinks) along the back wall
		local fridgeN = max(2, floor((w - 4) / 4.5))
		for i = 0, fridgeN - 1 do
			local fx = 2 + i * 4.5
			Kit.box(m, frame, fx, 0, d - 3.2, fx + 4.3, 7.6, d - 0.4, "Metal", { 60, 60, 66 }, { name = "Cooler" })
			local glass = Kit.box(m, frame, fx + 0.1, 0.3, d - 3.3, fx + 4.2, 7.4, d - 3.2, "Glass", { 220, 236, 246 }, { name = "CoolerGlass", tr = 0.55 })
			Kit.light(glass, "surface", { face = "front", color = { 240, 250, 255 }, brightness = 0.6, range = 6, tag = false })
		end
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 4, d - 2), "CoolerHum"), "fridge_hum", { volume = 0.25, maxDist = 30 })
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 6, d / 2), "Ambience"), "store_music", { volume = 0.18, maxDist = 30 })
		Kit.sound(Kit.anchor(m, frame * CF(w - 5, 7, 1), "Chime"), "store_chime", { volume = 0.5, maxDist = 30, loop = false, attrs = { Trigger = "enter" } })
		s.data.cooler = { n = fridgeN, z = d - 3.2 }
	end,
	furnish = function(ctx, s, frame, into)
		local w, d = s.w, s.d
		local rng = Rng.child(ctx.rec.seed, s.id)
		-- gondola shelves: double-sided, 3 levels, product boxes; one anchor per facing section
		local CATS = { "food", "snack", "drink", "goods" }
		local byCat = {}
		for _, it in Menus.CVS do
			byCat[it.cat] = byCat[it.cat] or {}
			table.insert(byCat[it.cat], it)
		end
		local rows = max(1, floor((w - 14) / 5.2))
		local idx = 0
		for r = 0, rows - 1 do
			local gx = 2.5 + r * 5.2
			local z0, z1 = 8.5, min(d - 5, 18)
			Kit.box(into, frame, gx - 1.2, 0, z0, gx + 1.2, 5.6, z1, "SmoothPlastic", { 236, 236, 236 }, { name = "Gondola" })
			for _, side in { -1, 1 } do
				local sx = gx + side * 1.25
				local sections = max(1, floor((z1 - z0) / 3.4))
				for sct = 0, sections - 1 do
					idx += 1
					local cat = CATS[((r * 2 + (if side > 0 then 1 else 0) + sct) % #CATS) + 1]
					local list = byCat[cat] or Menus.CVS
					local it = list[((idx - 1) % #list) + 1]
					local sz0 = z0 + sct * 3.4 + 0.2
					local col = Kit.col(it.color)
					for lvl = 0, 2 do
						local ly = 0.6 + lvl * 1.8
						Kit.box(into, frame, sx - 0.05 * side - 0.3, ly - 0.08, sz0, sx + 0.05 * side + 0.3 * side, ly, sz0 + 3.0, "Metal", { 200, 200, 204 }, { name = "ShelfLip", collide = false })
						for k = 0, 3 do
							local pz = sz0 + 0.35 + k * 0.7
							local prod = Kit.box(into, frame, sx - 0.25, ly, pz - 0.28, sx + 0.25, ly + 0.9 + rng:range(-0.2, 0.2), pz + 0.28, "SmoothPlastic", col:Lerp(Color3.new(1, 1, 1), rng:range(0, 0.2)), { name = "Item", collide = false })
							prod:SetAttribute("ProductId", it.id)
							prod:SetAttribute("Section", idx)
							CollectionService:AddTag(prod, "GwB_Product")
						end
					end
					-- price tag
					local tagP = Kit.box(into, frame, sx + side * 0.32 - 0.02, 0.2, sz0 + 0.6, sx + side * 0.32 + 0.02, 0.5, sz0 + 2.4, "SmoothPlastic", { 255, 230, 40 }, { name = "PriceTag", collide = false })
					Kit.text(tagP, if side > 0 then "right" else "left", it.name .. " " .. Util.won(it.price), { color = { 30, 30, 30 }, ppS = 40, bold = false, maxDist = 20 })
					point(into, frame * CF(sx + side * 1.0, 3.4, sz0 + 1.5), s, "product", { ProductId = it.id, Section = idx })
				end
			end
		end
		-- drinks in the coolers
		local cooler = s.data.cooler
		if cooler then
			local drinks = byCat.drink or {}
			for i = 0, cooler.n - 1 do
				local it = drinks[(i % max(1, #drinks)) + 1]
				if it then
					local fx = 2 + i * 4.5
					for lvl = 0, 3 do
						for k = 0, 4 do
							local prod = Kit.vcyl(into, frame, fx + 0.5 + k * 0.8, 0.9 + lvl * 1.7, cooler.z + 1.2, 1.0, 0.45, "SmoothPlastic", it.color, { name = "Item", collide = false })
							prod:SetAttribute("ProductId", it.id)
							prod:SetAttribute("Section", 100 + i)
							CollectionService:AddTag(prod, "GwB_Product")
						end
					end
					point(into, frame * CF(fx + 2.15, 3.6, cooler.z - 1.0), s, "product", { ProductId = it.id, Section = 100 + i })
				end
			end
		end
		-- ice cream chest freezer
		Kit.box(into, frame, w - 14, 0, 7.5, w - 11.5, 3.0, 11, "SmoothPlastic", { 240, 240, 244 }, { name = "Freezer" })
		Kit.box(into, frame, w - 13.9, 3.0, 7.6, w - 11.6, 3.08, 10.9, "Glass", { 200, 230, 250 }, { name = "FreezerLid", tr = 0.4, collide = false })
		local icecream = Menus.find(Menus.CVS, "icecream")
		if icecream then
			point(into, frame * CF(w - 12.75, 3.6, 7.0), s, "product", { ProductId = "icecream", Section = 200 })
		end
		-- eating bar stools
		for i = 0, 3 do
			stool(into, frame, 6.5 + i * 2.0, 3.6, 2.4, { 40, 110, 200 }, { ShopId = s.id, Index = i + 1 }, 0)
		end
		Shops.staff(into, frame * CF(w - 7.2, 0, 8.4) * CFrame.Angles(0, math.pi, 0), { name = "알바생", top = { 40, 110, 200 }, apron = nil, hat = { 40, 110, 200 } })
	end,
}

-- 부산 돼지국밥 ------------------------------------------------------------------------------
T.gukbap = {
	look = { floor = { 120, 100, 80 }, floorMat = "WoodPlanks", wall = { 236, 226, 206 }, lightColor = { 255, 226, 180 }, lightStep = 8 },
	build = function(ctx, s, frame, m)
		local w, d = s.w, s.d
		finishes(m, frame, w, d, s.fl.h, T.gukbap.look, s.id, ctx.rng)
		local ceilY = s.fl.h - Config.SLAB
		-- kitchen partition with the pass-through window (배식구)
		local kz = d - 8
		Kit.wallX(m, frame, 0.3, w - 0.3, kz, 0.4, 0, ceilY, { { w / 2 - 4, w / 2 + 4, 3.2, 6.8 }, { w - 4.5, w - 1.5, 0, Config.DOOR_H } }, "Plaster", { 214, 196, 170 }, { name = "KitchenWall" })
		counter(m, frame, w / 2 - 4, kz - 1.2, w / 2 + 4, kz + 0.4, 3.4, { 120, 86, 60 }, { 230, 230, 226 })
		Core.door(m, frame * CF(w - 3, 0, kz), { w = 2.8, h = Config.DOOR_H, t = 0.4, kind = "swing", lock = "staff", id = s.id .. "_kitchen", label = "직원 전용" })
		point(m, frame * CF(w / 2 - 2, 3.8, kz - 1.9), s, "pickup")
		-- kitchen: big pots, stove, steam
		for i = 0, 2 do
			local px = 3 + i * 4.2
			Kit.box(m, frame, px - 1.8, 0, d - 4.2, px + 1.8, 2.8, d - 0.6, "Metal", { 160, 160, 164 }, { name = "Stove" })
			local pot = Kit.vcyl(m, frame, px, 4.2, d - 2.4, 2.8, 3.0, "Metal", { 190, 190, 194 }, { name = "Pot", collide = false })
			Kit.vcyl(m, frame, px, 5.62, d - 2.4, 0.05, 2.7, "SmoothPlastic", { 246, 240, 226 }, { name = "Broth", collide = false })
			pot:SetAttribute("Steam", true)
		end
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 4, d - 3), "Boil"), "boiling", { volume = 0.35, maxDist = 30 })
		menuBoard(m, frame * CF(w / 2, 8.6, kz - 0.25) * CFrame.Angles(0, math.pi, 0), 9, 3.2, "🍲 부산 돼지국밥 메뉴", Menus.GUKBAP, { bg = { 40, 30, 22 } })
		-- cashier counter + kiosk by the entrance
		counter(m, frame, w - 6.5, 2.5, w - 1, 5.0, 3.4, { 120, 86, 60 }, { 230, 230, 226 })
		Kit.box(m, frame, w - 5, 3.4, 3.2, w - 3.8, 4.4, 4.2, "SmoothPlastic", { 30, 30, 34 }, { name = "POS", collide = false })
		point(m, frame * CF(w - 3.8, 3.8, 1.7), s, "pay")
		local kiosk = Kit.box(m, frame, w - 9.6, 0, 2.6, w - 8, 6.0, 3.6, "SmoothPlastic", { 236, 236, 236 }, { name = "Kiosk" })
		local ks = Kit.box(m, frame, w - 9.4, 3.4, 2.55, w - 8.2, 5.6, 2.6, "Neon", { 60, 120, 220 }, { name = "KioskScreen", collide = false })
		Kit.text(ks, "front", "주문하기\n📋", { color = { 255, 255, 255 }, ppS = 40, maxDist = 30 })
		point(m, frame * CF(w - 8.8, 3.6, 1.6), s, "order")
		kiosk:SetAttribute("Kiosk", true)
		-- water + side dish self bar
		Furniture.build("water_dispenser", m, frame * CF(1.2, 0, kz - 2.0) * CFrame.Angles(0, rad(-90), 0), 1, { ShopId = s.id, Public = true })
		local tv = Kit.box(m, frame, 0.4, 7.0, 6, 0.6, 9.6, 10.5, "SmoothPlastic", { 20, 20, 22 }, { name = "WallTV", collide = false })
		tv:SetAttribute("ScreenKind", "tv")
		CollectionService:AddTag(tv, "GwB_Screen")
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 6, d / 2 - 4), "Chatter"), "restaurant_chatter", { volume = 0.25, maxDist = 30 })
	end,
	furnish = function(ctx, s, frame, into)
		local w, d = s.w, s.d
		local kz = d - 8
		local cols = max(1, floor((w - 4) / 8))
		local rows = max(1, floor((kz - 9) / 6.4))
		local idx = 0
		for r = 0, rows - 1 do
			for c = 0, cols - 1 do
				idx += 1
				local tm = diningTable(into, frame, s, 4.2 + c * 8, 9 + r * 6.4, idx, { top = { 150, 110, 76 }, chair = { 100, 70, 50 } })
				-- 수저통 + 깍두기 jar on every table
				local tx, tz = 4.2 + c * 8, 9 + r * 6.4
				Kit.vcyl(tm, frame, tx + 1.6, 3.3, tz, 0.9, 0.6, "Metal", { 200, 200, 204 }, { collide = false, name = "Spoons" })
				Kit.vcyl(tm, frame, tx - 1.6, 3.2, tz, 0.7, 0.8, "Glass", { 220, 120, 80 }, { collide = false, name = "Kkakdugi", tr = 0.2 })
			end
		end
		Shops.staff(into, frame * CF(w / 2 + 1, 0, kz + 1.8) * CFrame.Angles(0, math.pi, 0), { name = "주방 이모", top = { 240, 240, 236 }, apron = { 200, 60, 50 }, hat = { 255, 255, 255 } })
		Shops.staff(into, frame * CF(w - 3.8, 0, 6.2) * CFrame.Angles(0, math.pi, 0), { name = "사장님", top = { 60, 60, 70 }, apron = { 40, 40, 44 } })
	end,
}

-- 광안 숯불갈비 (one template per floor: the 1F hall and the 2F 단체석) ------------------------
local function bbqTable(into: Instance, frame: CFrame, s: any, x: number, z: number, idx: number)
	local m = Kit.model(into, "Table_" .. idx, { ShopId = s.id, TableId = idx })
	local tw, td = 6.0, 4.2
	Kit.box(m, frame, x - tw / 2, 2.6, z - td / 2, x + tw / 2, 2.9, z + td / 2, "Wood", { 90, 62, 42 }, { name = "Top" })
	Kit.box(m, frame, x - tw / 2 + 0.3, 0, z - td / 2 + 0.3, x + tw / 2 - 0.3, 2.6, z + td / 2 - 0.3, "Metal", { 60, 58, 56 }, { name = "Base" })
	-- built-in round grill (숯불 화로) + grate
	Kit.vcyl(m, frame, x, 2.75, z, 0.35, 2.6, "Metal", { 50, 50, 52 }, { name = "GrillRim", collide = false })
	local coal = Kit.vcyl(m, frame, x, 2.62, z, 0.12, 2.2, "Neon", { 255, 90, 30 }, { name = "Coal", collide = false })
	coal:SetAttribute("Coal", true)
	coal.Transparency = 0.6
	local grate = Kit.vcyl(m, frame, x, 2.95, z, 0.06, 2.4, "DiamondPlate", { 70, 70, 72 }, { name = "Grate", collide = false })
	grate:SetAttribute("Grill", true)
	-- exhaust duct coming down from the ceiling (the Korean BBQ icon)
	local ceilY = s.fl.h - Config.SLAB
	Kit.vcyl(m, frame, x, (ceilY + 6.6) / 2, z, ceilY - 6.6, 0.9, "Metal", { 196, 198, 202 }, { name = "Duct", collide = false })
	Kit.vcyl(m, frame, x, 6.3, z, 0.7, 2.4, "Metal", { 196, 198, 202 }, { name = "Hood", collide = false })
	local hl = Kit.vcyl(m, frame, x, 5.9, z, 0.1, 1.6, "Neon", { 255, 214, 160 }, { name = "HoodLight", collide = false })
	Kit.light(hl, "spot", { face = "bottom", color = { 255, 214, 160 }, brightness = 1.2, range = 10, angle = 70, attrs = { Group = "shop" } })
	-- stools / benches
	local k = 0
	for _, side in { -1, 1 } do
		for _, cx in { -1.5, 1.5 } do
			k += 1
			stool(m, frame, x + cx, z + side * (td / 2 + 1.0), 1.9, { 150, 40, 30 }, { ShopId = s.id, TableId = idx, Index = k }, if side < 0 then 0 else 180)
		end
	end
	-- side dishes (banchan) + lettuce basket + 쌈장
	local BAN = { { 90, 170, 80 }, { 220, 80, 50 }, { 240, 220, 160 }, { 120, 90, 60 } }
	for i, c in BAN do
		local bx = x - 2.4 + (i - 1) * 1.6
		Kit.vcyl(m, frame, bx, 2.95, z - 1.6, 0.12, 0.9, "SmoothPlastic", { 240, 240, 236 }, { collide = false, name = "Dish" })
		Kit.vcyl(m, frame, bx, 3.02, z - 1.6, 0.08, 0.7, "SmoothPlastic", c, { collide = false, name = "Banchan" })
	end
	-- raw meat plate anchor + grill centre + table point
	Kit.anchor(m, frame * CF(x + 2.2, 3.0, z + 1.4), "MeatPlate", { TableId = idx })
	Kit.vcyl(m, frame, x + 2.2, 2.95, z + 1.4, 0.1, 1.5, "SmoothPlastic", { 245, 245, 245 }, { collide = false, name = "Plate" })
	Kit.anchor(m, frame * CF(x, 3.05, z), "GrillCenter", { TableId = idx })
	point(m, frame * CF(x, 3.6, z), s, "table", { TableId = idx })
	Kit.sound(grate, "sizzle", { volume = 0.5, maxDist = 24, attrs = { Active = false } })
	return m
end

T.bbq = {
	look = { floor = { 70, 60, 54 }, floorMat = "Slate", wall = { 120, 86, 60 }, wallMat = "WoodPlanks", lightColor = { 255, 220, 170 }, brightness = 0.9, lightStep = 10 },
	build = function(ctx, s, frame, m)
		local w, d = s.w, s.d
		finishes(m, frame, w, d, s.fl.h, T.bbq.look, s.id, ctx.rng)
		if s.data.ground then
			counter(m, frame, 1, 2.2, 6.5, 4.6, 3.4, { 60, 40, 30 }, { 40, 40, 42 })
			Kit.box(m, frame, 2.4, 3.4, 2.8, 3.6, 4.4, 3.8, "SmoothPlastic", { 30, 30, 34 }, { name = "POS", collide = false })
			point(m, frame * CF(3.8, 3.8, 5.6), s, "pay")
			-- meat aging fridge (숙성고) at the back with glowing red meat
			Kit.box(m, frame, w - 9, 0, d - 2.6, w - 1, 7.4, d - 0.4, "Metal", { 50, 50, 54 }, { name = "AgingFridge" })
			local g = Kit.box(m, frame, w - 8.8, 0.4, d - 2.7, w - 1.2, 7.2, d - 2.6, "Glass", { 255, 200, 200 }, { name = "AgingGlass", tr = 0.4 })
			Kit.light(g, "surface", { face = "front", color = { 255, 120, 110 }, brightness = 0.7, range = 8, tag = false })
			for i = 0, 5 do
				Kit.box(m, frame, w - 8.4 + i * 1.2, 2 + (i % 3) * 1.6, d - 2.2, w - 7.4 + i * 1.2, 3 + (i % 3) * 1.6, d - 1.2, "SmoothPlastic", { 170, 50, 50 }, { name = "Meat", collide = false })
			end
			menuBoard(m, frame * CF(w / 2, 8.4, d - 0.5) * CFrame.Angles(0, math.pi, 0), 10, 3.4, "🥩 광안 숯불갈비", Menus.BBQ, { bg = { 30, 20, 16 }, fg = { 255, 200, 120 } })
		end
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 6, d / 2), "Chatter"), "restaurant_chatter", { volume = 0.3, maxDist = 34 })
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 9, d / 2), "Exhaust"), "vent_fan", { volume = 0.2, maxDist = 30 })
	end,
	furnish = function(ctx, s, frame, into)
		local w, d = s.w, s.d
		local z0 = if s.data.ground then 9 else 5
		local cols = max(1, floor((w - 4) / 10))
		local rows = max(1, floor((d - z0 - 3) / 8.4))
		local idx = s.data.tableBase or 0
		for r = 0, rows - 1 do
			for c = 0, cols - 1 do
				idx += 1
				bbqTable(into, frame, s, 5.5 + c * 10, z0 + r * 8.4, idx)
			end
		end
		if s.data.ground then
			Shops.staff(into, frame * CF(3.8, 0, 1.4), { name = "사장님", top = { 40, 40, 44 }, apron = { 150, 40, 30 } })
			Shops.staff(into, frame * CF(w - 5, 0, d - 5), { name = "직원", top = { 40, 40, 44 }, apron = { 150, 40, 30 }, hat = { 40, 40, 44 } })
		end
	end,
}

-- 바다 카페 -------------------------------------------------------------------------------------
T.cafe = {
	look = { floor = { 196, 170, 140 }, floorMat = "WoodPlanks", wall = { 246, 244, 240 }, lightColor = { 255, 226, 186 }, brightness = 1.0, lightStep = 9 },
	build = function(ctx, s, frame, m)
		local w, d = s.w, s.d
		finishes(m, frame, w, d, s.fl.h, T.cafe.look, s.id, ctx.rng)
		if not s.data.ground then
			return
		end
		-- the bar: order counter + espresso machine + pickup
		local cz0, cz1 = d - 7.5, d - 5.0
		counter(m, frame, 3, cz0, w - 7, cz1, 3.6, { 236, 234, 228 }, { 60, 56, 52 })
		Kit.box(m, frame, 5, 3.6, cz0 + 0.6, 7.6, 5.4, cz1 - 0.3, "Metal", { 190, 40, 40 }, { name = "Espresso", collide = false })
		Kit.box(m, frame, 8.2, 3.6, cz0 + 0.8, 9.4, 5.6, cz1 - 0.4, "Metal", { 60, 60, 64 }, { name = "Grinder", collide = false })
		local disp = Kit.box(m, frame, 11, 3.6, cz0 + 0.2, 16, 5.6, cz0 + 1.4, "Glass", { 240, 240, 236 }, { name = "CakeCase", tr = 0.4 })
		Kit.light(disp, "point", { color = { 255, 236, 210 }, brightness = 0.6, range = 5, tag = false })
		for i = 0, 3 do
			Kit.vcyl(m, frame, 11.8 + i * 1.2, 4.0, cz0 + 0.8, 0.8, 0.9, "SmoothPlastic", { 250, 230, 230 }, { collide = false, name = "Cake" })
		end
		point(m, frame * CF(w / 2 - 2, 3.9, cz0 - 1.2), s, "order")
		point(m, frame * CF(w - 9, 3.9, cz0 - 1.2), s, "pickup")
		-- order number display (진동벨 대신 번호판)
		local nd = Kit.box(m, frame, w - 11, 7.0, cz0 - 0.1, w - 7, 8.4, cz0, "SmoothPlastic", { 10, 10, 12 }, { name = "OrderDisplay", collide = false })
		nd:SetAttribute("ShopId", s.id)
		nd:SetAttribute("OrderDisplay", true)
		Kit.text(nd, "back", "주문 번호\n—", { color = { 255, 140, 60 }, ppS = 40, maxDist = 60, font = Enum.Font.GothamBlack })
		menuBoard(m, frame * CF(w / 2 - 3, 8.6, d - 0.5) * CFrame.Angles(0, math.pi, 0), 10, 3.4, "☕ SEA BREEZE MENU", Menus.CAFE, { bg = { 34, 40, 44 }, fg = { 240, 240, 236 } })
		-- 반납대 (cup return)
		counter(m, frame, w - 5.5, cz0, w - 1, cz1, 3.6, { 236, 234, 228 }, { 60, 56, 52 })
		point(m, frame * CF(w - 3.2, 3.9, cz0 - 1.2), s, "return")
		Kit.sound(Kit.anchor(m, frame * CF(6, 5, cz0), "Machine"), "espresso", { volume = 0.35, maxDist = 24, attrs = { Active = false } })
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 7, d / 2), "Music"), "cafe_music", { volume = 0.2, maxDist = 34 })
	end,
	furnish = function(ctx, s, frame, into)
		local w, d = s.w, s.d
		local zEnd = if s.data.ground then d - 9 else d - 2
		local idx = 0
		-- window bar facing the street / sea
		counter(into, frame, 1.5, 1.0, w - 1.5, 2.2, 3.6, { 150, 116, 84 }, { 176, 136, 96 })
		for i = 0, floor((w - 4) / 2.4) - 1 do
			stool(into, frame, 2.8 + i * 2.4, 3.4, 2.4, { 60, 56, 52 }, { ShopId = s.id, Index = 100 + i }, 0)
		end
		-- small tables
		local cols = max(1, floor((w - 4) / 7.5))
		local rows = max(1, floor((zEnd - 7) / 6.2))
		for r = 0, rows - 1 do
			for c = 0, cols - 1 do
				idx += 1
				diningTable(into, frame, s, 4.5 + c * 7.5, 8 + r * 6.2, idx, { w = 3.2, d = 2.6, seats = 2, top = { 236, 234, 228 }, chair = { 150, 116, 84 } })
			end
		end
		Furniture.build("monstera", into, frame * CF(w - 1.6, 0, 4.4), 1)
		Furniture.build("monstera", into, frame * CF(1.6, 0, zEnd - 1), 2)
		if s.data.ground then
			Shops.staff(into, frame * CF(6, 0, d - 4.0) * CFrame.Angles(0, math.pi, 0), { name = "바리스타", top = { 30, 30, 32 }, apron = { 110, 80, 60 } })
		end
	end,
}

-- 광안 PC방 -------------------------------------------------------------------------------------
T.pcbang = {
	look = { floor = { 40, 40, 46 }, floorMat = "Carpet", wall = { 30, 30, 38 }, lamp = { 120, 90, 255 }, lightColor = { 170, 150, 255 }, brightness = 0.7, lightStep = 10 },
	build = function(ctx, s, frame, m)
		local w, d = s.w, s.d
		finishes(m, frame, w, d, s.fl.h, T.pcbang.look, s.id, ctx.rng)
		counter(m, frame, 2, 3, 12, 5.4, 3.6, { 30, 30, 38 }, { 120, 80, 255 }, "SmoothPlastic")
		local strip = Kit.box(m, frame, 2, 0.4, 2.9, 12, 0.6, 3.0, "Neon", { 140, 80, 255 }, { name = "LedStrip", collide = false })
		strip:SetAttribute("Rgb", true)
		point(m, frame * CF(7, 4.0, 1.8), s, "counter")
		local sign = Kit.box(m, frame, 3, 7.4, 5.5, 11, 9.0, 5.6, "SmoothPlastic", { 20, 20, 26 }, { name = "CounterSign", collide = false })
		Kit.text(sign, "back", "🎮 GWANGAN PC", { color = { 180, 140, 255 }, ppS = 40, font = Enum.Font.GothamBlack, maxDist = 60 })
		-- snack fridge
		Furniture.build("vending", m, frame * CF(15, 0, 1.6) * CFrame.Angles(0, math.pi, 0), 2, { ShopId = s.id, Public = true })
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 5, d / 2), "Clicks"), "keyboard", { volume = 0.25, maxDist = 34 })
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 8, d / 2), "Hum"), "pc_hum", { volume = 0.18, maxDist = 40 })
	end,
	furnish = function(ctx, s, frame, into)
		local w, d = s.w, s.d
		local seat = 0
		local rowZ = 9
		while rowZ < d - 4 do
			-- a double row of desks facing each other with a divider
			Kit.box(into, frame, 2, 2.6, rowZ - 2.0, w - 2, 2.8, rowZ + 2.0, "SmoothPlastic", { 24, 24, 28 }, { name = "DeskRow" })
			Kit.box(into, frame, 2, 2.8, rowZ - 0.08, w - 2, 5.4, rowZ + 0.08, "Glass", { 60, 50, 90 }, { name = "Divider", tr = 0.4, collide = false })
			Kit.box(into, frame, 2, 0, rowZ - 1.8, w - 2, 2.6, rowZ + 1.8, "SmoothPlastic", { 0, 0, 0 }, { name = "Hit", tr = 1 })
			local n = floor((w - 4) / 3.6)
			for i = 0, n - 1 do
				local px = 3.8 + i * 3.6
				for _, side in { -1, 1 } do
					seat += 1
					local mz = rowZ + side * 0.7
					local mon = Kit.box(into, frame, px - 1.3, 3.0, mz - 0.06, px + 1.3, 4.7, mz + 0.06, "SmoothPlastic", { 10, 10, 12 }, { name = "Monitor", collide = false })
					mon:SetAttribute("ScreenKind", "pc")
					mon:SetAttribute("SeatNo", seat)
					mon:SetAttribute("ShopId", s.id)
					mon:SetAttribute("ScreenFace", if side < 0 then "Front" else "Back")
					CollectionService:AddTag(mon, "GwB_Screen")
					local kb = Kit.box(into, frame, px - 0.9, 2.8, mz - side * 1.2 - 0.3, px + 0.9, 2.86, mz - side * 1.2 + 0.3, "Neon", { 120, 60, 255 }, { name = "Keyboard", collide = false })
					kb:SetAttribute("Rgb", true)
					-- gaming chair
					local cz = rowZ + side * 3.0
					local ccf = frame * CF(px, 0, cz) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0)
					Kit.part(into, ccf * CF(0, 1.7, 0), V3(1.7, 0.3, 1.7), "Leather", { 30, 30, 32 }, { collide = false, name = "ChairSeat" })
					Kit.part(into, ccf * CF(0, 3.4, 0.8), V3(1.7, 3.2, 0.3), "Leather", { 200, 30, 40 }, { collide = false, name = "ChairBack" })
					Kit.part(into, ccf * CF(0, 0.85, 0), V3(0.3, 1.7, 0.3), "Metal", { 40, 40, 42 }, { collide = false, name = "ChairPost" })
					local st = Kit.part(into, ccf * CF(0, 1.95, 0), V3(1.6, 0.3, 1.6), "SmoothPlastic", { 0, 0, 0 }, { seat = true, tr = 1, name = "Seat", shadow = false, attrs = { ShopId = s.id, Index = seat, SeatNo = seat } })
					CollectionService:AddTag(st, "GwB_Seat")
					point(into, ccf * CF(0, 3.0, -0.8), s, "pc", { SeatNo = seat })
					local num = Kit.box(into, frame, px - 0.3, 5.0, mz - 0.07, px + 0.3, 5.4, mz + 0.07, "SmoothPlastic", { 30, 30, 34 }, { name = "SeatNum", collide = false })
					Kit.text(num, if side < 0 then "front" else "back", tostring(seat), { color = { 180, 160, 255 }, ppS = 60, maxDist = 30 })
				end
			end
			rowZ += 9
		end
		Shops.staff(into, frame * CF(7, 0, 6.6) * CFrame.Angles(0, math.pi, 0), { name = "PC방 알바", top = { 30, 30, 38 }, hat = { 120, 80, 255 } })
	end,
}

-- 코인 노래연습장 --------------------------------------------------------------------------------
T.karaoke = {
	look = { floor = { 30, 26, 40 }, floorMat = "Carpet", wall = { 40, 30, 60 }, lamp = { 255, 80, 200 }, lightColor = { 255, 140, 220 }, brightness = 0.8, lightStep = 12 },
	build = function(ctx, s, frame, m)
		local w, d = s.w, s.d
		local ceilY = s.fl.h - Config.SLAB
		finishes(m, frame, w, d, s.fl.h, T.karaoke.look, s.id, ctx.rng)
		counter(m, frame, 1.5, 3, 9.5, 5.4, 3.6, { 60, 30, 90 }, { 255, 120, 220 }, "SmoothPlastic")
		point(m, frame * CF(5.5, 4.0, 1.8), s, "counter")
		Furniture.build("vending", m, frame * CF(10.6, 0, 8.4) * CFrame.Angles(0, rad(-90), 0), 2, { ShopId = s.id, Public = true })
		-- rooms: hall side (z 0..10, x 12..w) and street side (z 14..d), corridor z 10..14
		local rooms = {}
		local rw = 12
		local function room(x0: number, z0: number, x1: number, z1: number, doorSide: string, no: number)
			local rf = Kit.model(m, "Room_" .. no, { ShopId = s.id, RoomNo = no })
			-- walls
			local doorX = (x0 + x1) / 2
			if doorSide == "-z" then
				Kit.wallX(rf, frame, x0, x1, z0, 0.4, 0, ceilY, { { doorX - 1.6, doorX + 1.6, 0, Config.DOOR_H } }, "Plaster", { 60, 40, 90 })
			else
				Kit.wallX(rf, frame, x0, x1, z1, 0.4, 0, ceilY, { { doorX - 1.6, doorX + 1.6, 0, Config.DOOR_H } }, "Plaster", { 60, 40, 90 })
			end
			Kit.wallZ(rf, frame, z0, z1, x0, 0.4, 0, ceilY, nil, "Plaster", { 60, 40, 90 })
			Kit.wallZ(rf, frame, z0, z1, x1, 0.4, 0, ceilY, nil, "Plaster", { 60, 40, 90 })
			local dz = if doorSide == "-z" then z0 else z1
			local dcf = frame * CF(doorX, 0, dz) * CFrame.Angles(0, if doorSide == "-z" then 0 else math.pi, 0)
			local door = Core.door(rf, dcf, { w = 3.0, h = Config.DOOR_H, t = 0.4, kind = "glass", lock = "room", id = s.id .. "_room" .. no, roomKey = s.id .. ":" .. no, label = no .. "번방", color = { 120, 60, 160 } })
			door:SetAttribute("RoomNo", no)
			Core.plate(rf, dcf * CF(2.6, 6.4, -0.3), 1.4, 0.8, no .. "번", { bg = { 255, 80, 200 }, fg = { 255, 255, 255 }, glow = true })
			table.insert(rooms, { no = no, x0 = x0, z0 = z0, x1 = x1, z1 = z1, door = doorSide })
		end
		local no = 0
		local x = 12
		while x + rw <= w - 0.5 do
			no += 1
			room(x, 0.4, x + rw, 10, "+z", no)
			x += rw
		end
		x = 0.4
		while x + rw <= w - 0.4 do
			no += 1
			room(x, 14, x + rw, d - 0.4, "-z", no)
			x += rw
		end
		s.data.rooms = rooms
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 5, 12), "Muffled"), "karaoke_muffled", { volume = 0.2, maxDist = 30 })
	end,
	furnish = function(ctx, s, frame, into)
		for _, r in s.data.rooms or {} do
			local cx = (r.x0 + r.x1) / 2
			local rm = Kit.model(into, "RoomProps_" .. r.no, { ShopId = s.id, RoomNo = r.no })
			local far = if r.door == "-z" then r.z1 else r.z0 -- the wall opposite the door gets the screen
			local near = if r.door == "-z" then r.z0 else r.z1
			local dir = if far > near then 1 else -1
			-- big screen on the far wall
			local scr = Kit.box(rm, frame, cx - 4, 3.2, far - dir * 0.35, cx + 4, 8.2, far - dir * 0.25, "SmoothPlastic", { 10, 10, 14 }, { name = "KaraokeScreen", collide = false })
			scr:SetAttribute("ScreenKind", "karaoke")
			scr:SetAttribute("RoomNo", r.no)
			scr:SetAttribute("ShopId", s.id)
			scr:SetAttribute("ScreenFace", if dir > 0 then "Front" else "Back")
			CollectionService:AddTag(scr, "GwB_Screen")
			-- U sofa along the side walls + near side
			local sofaC = { 120, 30, 90 }
			Kit.box(rm, frame, r.x0 + 0.3, 0, near + dir * 0.4, r.x0 + 2.4, 1.6, far - dir * 3, "Leather", sofaC, { name = "Sofa" })
			Kit.box(rm, frame, r.x1 - 2.4, 0, near + dir * 0.4, r.x1 - 0.3, 1.6, far - dir * 3, "Leather", sofaC, { name = "Sofa" })
			local k = 0
			for _, sx in { r.x0 + 1.35, r.x1 - 1.35 } do
				for i = 0, 2 do
					k += 1
					local sz = near + dir * (2.4 + i * 2.2)
					local st = Kit.part(rm, frame * CF(sx, 1.85, sz) * CFrame.Angles(0, if sx < cx then rad(-90) else rad(90), 0), V3(1.6, 0.3, 1.6), "SmoothPlastic", { 0, 0, 0 }, { seat = true, tr = 1, name = "Seat", shadow = false, attrs = { ShopId = s.id, RoomNo = r.no, Index = k } })
					CollectionService:AddTag(st, "GwB_Seat")
				end
			end
			-- table + remote + mics + tambourine
			Kit.box(rm, frame, cx - 2.2, 0, near + dir * 3, cx + 2.2, 2.2, near + dir * 6.5, "Glass", { 60, 30, 90 }, { name = "Table", tr = 0.3 })
			point(rm, frame * CF(cx, 2.8, near + dir * 4.2), s, "remote", { RoomNo = r.no })
			point(rm, frame * CF(cx + 1.2, 2.8, near + dir * 5.4), s, "mic", { RoomNo = r.no })
			Kit.box(rm, frame, cx + 0.9, 2.2, near + dir * 5.2, cx + 1.5, 2.4, near + dir * 5.6, "Metal", { 30, 30, 30 }, { name = "Mic", collide = false })
			Kit.vcyl(rm, frame, cx - 1.2, 2.3, near + dir * 5.4, 0.2, 1.0, "Wood", { 200, 160, 80 }, { name = "Tambourine", collide = false })
			-- disco ball + party lights
			local ball = Kit.ball(rm, frame, cx, s.fl.h - Config.SLAB - 1.4, (near + far) / 2, 1.4, "Foil", { 220, 220, 230 }, { collide = false, name = "DiscoBall", refl = 0.6 })
			ball:SetAttribute("Rpm", 0)
			ball:SetAttribute("Axis", "Y")
			ball:SetAttribute("RoomNo", r.no)
			CollectionService:AddTag(ball, "GwB_Spin")
			local pl = Kit.light(ball, "point", { color = { 255, 80, 200 }, brightness = 1.0, range = 16, attrs = { Group = "karaoke", RoomNo = r.no } })
			pl.Enabled = false
			Kit.sound(scr, "karaoke_music", { volume = 0.6, maxDist = 18, attrs = { Active = false, RoomNo = r.no } })
		end
		Shops.staff(into, frame * CF(5.5, 0, 6.8) * CFrame.Angles(0, math.pi, 0), { name = "카운터", top = { 60, 30, 90 } })
	end,
}

-- 광안 당구클럽 -----------------------------------------------------------------------------------
T.billiards = {
	look = { floor = { 60, 70, 60 }, floorMat = "Carpet", wall = { 200, 196, 186 }, lightColor = { 255, 240, 220 }, brightness = 0.8, lightStep = 14 },
	build = function(ctx, s, frame, m)
		local w, d = s.w, s.d
		finishes(m, frame, w, d, s.fl.h, T.billiards.look, s.id, ctx.rng)
		counter(m, frame, 2, 3, 11, 5.4, 3.6, { 60, 40, 30 }, { 230, 226, 216 })
		point(m, frame * CF(6.5, 4.0, 1.8), s, "counter")
		-- cue rack
		Kit.box(m, frame, 12.5, 1, 0.5, 18.5, 8, 0.8, "Wood", { 90, 60, 40 }, { name = "CueRack" })
		for i = 0, 9 do
			Kit.box(m, frame, 13 + i * 0.55, 1.4, 0.9, 13.12 + i * 0.55, 7.8, 1.02, "Wood", { 220, 190, 140 }, { name = "Cue", collide = false })
		end
		Furniture.build("vending", m, frame * CF(w - 3, 0, 1.8) * CFrame.Angles(0, math.pi, 0), 1, { ShopId = s.id, Public = true })
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 6, d / 2), "Ambience"), "billiards_ambience", { volume = 0.2, maxDist = 34 })
	end,
	furnish = function(ctx, s, frame, into)
		local w, d = s.w, s.d
		local n = max(1, floor((w - 4) / 15))
		for i = 1, n do
			local cx = 2 + (i - 0.5) * ((w - 4) / n)
			local cz = d / 2 + 2.5
			local tm = Kit.model(into, "BilliardTable_" .. i, { ShopId = s.id, TableId = i })
			-- outer rails, cloth, legs (play area 12 x 6 = Billiards.W x H)
			Kit.box(tm, frame, cx - 7, 0, cz - 4, cx + 7, 2.6, cz + 4, "Wood", { 80, 50, 34 }, { name = "Body" })
			local cloth = Kit.box(tm, frame, cx - 6.0, 2.6, cz - 3.0, cx + 6.0, 2.66, cz + 3.0, "Fabric", { 30, 90, 160 }, { name = "Cloth", collide = false })
			cloth:SetAttribute("Cloth", true)
			for _, side in { -1, 1 } do
				Kit.box(tm, frame, cx - 7, 2.6, cz + side * 3.0, cx + 7, 3.1, cz + side * 4, "Wood", { 80, 50, 34 }, { name = "Rail", collide = false })
				Kit.box(tm, frame, cx + side * 6.0, 2.6, cz - 3.0, cx + side * 7, 3.1, cz + 3.0, "Wood", { 80, 50, 34 }, { name = "Rail", collide = false })
			end
			-- diamonds on the rails
			for k = -3, 3 do
				Kit.box(tm, frame, cx + k * 1.5 - 0.06, 3.1, cz - 3.6, cx + k * 1.5 + 0.06, 3.12, cz - 3.4, "Neon", { 240, 240, 240 }, { collide = false, name = "Diamond" })
			end
			-- balls (positions are driven by the shot replays)
			local Billiards = Shared.Billiards
			local sim = Billiards.new()
			for b, ball in sim.balls do
				local bp = Kit.ball(tm, frame, cx + ball.x, 2.66 + Billiards.R, cz + ball.z, Billiards.R * 2, "SmoothPlastic", Billiards.COLORS[b], { collide = false, name = "Ball" .. b, refl = 0.2 })
				bp:SetAttribute("Ball", b)
			end
			Kit.anchor(tm, frame * CF(cx, 2.66, cz), "TableCenter", { TableId = i })
			-- lamps above the table
			for _, lx in { -3.5, 3.5 } do
				local lamp = Kit.box(tm, frame, cx + lx - 1.6, 7.6, cz - 0.6, cx + lx + 1.6, 8.0, cz + 0.6, "Metal", { 30, 80, 50 }, { name = "TableLamp", collide = false })
				Kit.light(lamp, "spot", { face = "bottom", color = { 255, 244, 220 }, brightness = 1.4, range = 12, angle = 80, attrs = { Group = "shop" } })
			end
			point(tm, frame * CF(cx, 3.8, cz - 4.8), s, "table", { TableId = i })
			-- scoreboard on the back wall
			local sb = Kit.box(tm, frame, cx - 2.4, 6.0, d - 0.5, cx + 2.4, 8.4, d - 0.4, "SmoothPlastic", { 20, 20, 24 }, { name = "Scoreboard", collide = false })
			sb:SetAttribute("Scoreboard", i)
			sb:SetAttribute("ShopId", s.id)
			Kit.text(sb, "back", i .. "번 테이블\n0 점", { color = { 120, 255, 160 }, ppS = 40, maxDist = 50, font = Enum.Font.GothamBlack })
			Kit.sound(cloth, "billiard_hit", { volume = 0.6, maxDist = 30, loop = false, attrs = { Trigger = "hit" } })
		end
		-- waiting sofas
		Furniture.build("sofa3", into, frame * CF(w / 2, 0, 2.2) * CFrame.Angles(0, math.pi, 0), 2)
		Shops.staff(into, frame * CF(6.5, 0, 6.8) * CFrame.Angles(0, math.pi, 0), { name = "사장님", top = { 236, 236, 230 }, pants = { 60, 60, 60 } })
	end,
}

-- 광안 공인중개사 (부동산) --------------------------------------------------------------------------
T.realtor = {
	look = { floor = { 196, 190, 180 }, wall = { 240, 238, 232 }, lightColor = { 245, 248, 255 }, brightness = 1.2, lightStep = 8 },
	build = function(ctx, s, frame, m)
		local w, d = s.w, s.d
		finishes(m, frame, w, d, s.fl.h, T.realtor.look, s.id, ctx.rng)
		-- listings board on the back wall (updated by the housing service)
		local board = Kit.box(m, frame, 2, 3.4, d - 0.5, w - 2, 9.4, d - 0.4, "SmoothPlastic", { 250, 250, 248 }, { name = "ListingBoard", collide = false })
		board:SetAttribute("ListingBoard", true)
		Kit.text(board, "back", "🏠 광안 공인중개사 추천 매물\n원룸 · 빌라 · 오피스텔 · 아파트 · 펜트하우스\n\n상담 받고 바로 계약!", { color = { 30, 40, 60 }, ppS = 30, maxDist = 60 })
		counter(m, frame, w / 2 - 4, d / 2 - 1, w / 2 + 4, d / 2 + 1.6, 3.0, { 236, 234, 228 }, { 120, 92, 70 })
		local p = point(m, frame * CF(w / 2, 3.6, d / 2 - 2.4), s, "realtor")
		CollectionService:AddTag(p, "GwB_Realtor")
		Furniture.build("water_dispenser", m, frame * CF(1.3, 0, d - 2.4) * CFrame.Angles(0, rad(-90), 0), 1, { ShopId = s.id, Public = true })
	end,
	furnish = function(ctx, s, frame, into)
		local w, d = s.w, s.d
		chair(into, frame, w / 2 - 1.6, d / 2 - 2.6, 0, { 60, 60, 66 }, { ShopId = s.id, Index = 1 })
		chair(into, frame, w / 2 + 1.6, d / 2 - 2.6, 0, { 60, 60, 66 }, { ShopId = s.id, Index = 2 })
		Shops.staff(into, frame * CF(w / 2, 0, d / 2 + 3.2) * CFrame.Angles(0, math.pi, 0), { name = "공인중개사", top = { 236, 238, 242 }, pants = { 40, 44, 60 } })
		Furniture.build("sofa3", into, frame * CF(w / 2, 0, 3.0) * CFrame.Angles(0, math.pi, 0), 3)
		Furniture.build("monstera", into, frame * CF(w - 1.6, 0, 2.0), 1)
		Furniture.build("bookshelf", into, frame * CF(w - 1.0, 0, d / 2) * CFrame.Angles(0, rad(90), 0), 1)
	end,
}

-- 호텔 프런트 ----------------------------------------------------------------------------------------
T.hotel_lobby = {
	look = { floor = { 230, 224, 214 }, floorMat = "Marble", wall = { 214, 202, 182 }, wallMat = "Limestone", lightColor = { 255, 230, 190 }, brightness = 1.1, lightStep = 10, sides = false },
	build = function(ctx, s, frame, m)
		local w, d = s.w, s.d
		finishes(m, frame, w, d, s.fl.h, T.hotel_lobby.look, s.id, ctx.rng)
		-- front desk
		counter(m, frame, w / 2 - 7, d - 9, w / 2 + 7, d - 6.6, 3.8, { 60, 44, 32 }, { 236, 230, 220 })
		local logo = Kit.box(m, frame, w / 2 - 6, 5, d - 0.5, w / 2 + 6, 9.5, d - 0.4, "Metal", { 120, 96, 66 }, { name = "LogoWall", collide = false })
		Kit.text(logo, "back", "HOTEL SEASIDE GWANGAN\n호텔 씨사이드 광안", { color = { 255, 236, 200 }, ppS = 30, font = Enum.Font.GothamBlack, maxDist = 80 })
		local p = point(m, frame * CF(w / 2, 4.0, d - 10.2), s, "frontdesk")
		p:SetAttribute("Hotel", ctx.rec.id)
		-- chandelier
		local ch = Kit.ball(m, frame, w / 2, s.fl.h - Config.SLAB - 2.4, d / 2 - 4, 3.2, "Glass", { 255, 240, 210 }, { collide = false, name = "Chandelier", tr = 0.2 })
		Kit.light(ch, "point", { color = { 255, 226, 180 }, brightness = 1.6, range = 30, attrs = { Group = "shop" } })
		Kit.sound(Kit.anchor(m, frame * CF(w / 2, 6, d / 2), "Lounge"), "lobby_music", { volume = 0.18, maxDist = 40 })
	end,
	furnish = function(ctx, s, frame, into)
		local w, d = s.w, s.d
		Shops.staff(into, frame * CF(w / 2 - 3, 0, d - 4.8) * CFrame.Angles(0, math.pi, 0), { name = "프런트", top = { 30, 34, 50 }, pants = { 30, 34, 50 } })
		Shops.staff(into, frame * CF(w / 2 + 3, 0, d - 4.8) * CFrame.Angles(0, math.pi, 0), { name = "컨시어지", top = { 30, 34, 50 }, pants = { 30, 34, 50 } })
		Furniture.build("sofa3", into, frame * CF(6, 0, d / 2 - 6) * CFrame.Angles(0, rad(-90), 0), 2)
		Furniture.build("armchair", into, frame * CF(11, 0, d / 2 - 8) * CFrame.Angles(0, rad(-90), 0), 1)
		Furniture.build("coffee_table", into, frame * CF(8.8, 0, d / 2 - 6) * CFrame.Angles(0, rad(90), 0), 2)
		Furniture.build("monstera", into, frame * CF(2, 0, 3), 2)
		Furniture.build("monstera", into, frame * CF(w - 2, 0, 3), 2)
		Furniture.build("aquarium", into, frame * CF(w - 1.4, 0, d / 2 - 4) * CFrame.Angles(0, rad(90), 0), 1)
	end,
}

-- 관리사무소 (apartment) -----------------------------------------------------------------------------
T.office = {
	look = { floor = { 196, 190, 180 }, wall = { 236, 234, 228 }, lightColor = { 240, 248, 255 }, brightness = 1.2, lightStep = 8 },
	build = function(ctx, s, frame, m)
		finishes(m, frame, s.w, s.d, s.fl.h, T.office.look, s.id, ctx.rng)
		local nb = Kit.box(m, frame, 2, 4, s.d - 0.5, s.w - 2, 8.4, s.d - 0.4, "Fabric", { 200, 160, 110 }, { name = "NoticeBoard", collide = false })
		Kit.text(nb, "back", "📢 관리사무소\n· 재활용 분리배출: 매주 수요일\n· 승강기 점검: 둘째 주 화요일\n· 관리비 자동이체 신청 받습니다", { color = { 30, 30, 34 }, ppS = 30, align = "left", bold = false, maxDist = 40 })
		point(m, frame * CF(s.w / 2, 3.6, s.d / 2 - 2.4), s, "office")
	end,
	furnish = function(ctx, s, frame, into)
		Furniture.build("desk", into, frame * CF(s.w / 2, 0, s.d / 2 + 1) * CFrame.Angles(0, math.pi, 0), 3)
		Shops.staff(into, frame * CF(s.w / 2, 0, s.d / 2 + 2.6) * CFrame.Angles(0, math.pi, 0), { name = "관리소장", top = { 120, 140, 170 }, pants = { 50, 50, 56 } })
		Furniture.build("bookshelf", into, frame * CF(1.0, 0, s.d / 2) * CFrame.Angles(0, rad(-90), 0), 3)
		Furniture.build("water_dispenser", into, frame * CF(s.w - 1.2, 0, 2), 1, { Public = true })
	end,
}

-------------------------------------------------------------------------------------------------
-- public API
-------------------------------------------------------------------------------------------------
function Shops.frameOf(s: any): CFrame
	return s.rec.cf * CF(0, s.fl.y, 0) * s.frame
end

function Shops.build(ctx: any, s: any): Model?
	local t = T[s.kind]
	if not t then
		warn("[GwangalliBuildings] no shop template " .. tostring(s.kind))
		return nil
	end
	local frame = Shops.frameOf(s)
	local m = Kit.model(ctx.parent, "Shop_" .. s.id, { ShopId = s.id, ShopKind = s.kind, DisplayName = s.name, BuildingId = s.rec.id, Floor = s.fl.label }, { "GwB_Shop" })
	m:SetAttribute("Frame", frame)
	m:SetAttribute("W", s.w)
	m:SetAttribute("D", s.d)
	s.model = m
	t.build(ctx, s, frame, m)
	Kit.model(m, "Furnish")
	return m
end

function Shops.furnish(ctx: any, s: any, into: Instance)
	local t = T[s.kind]
	if t and t.furnish then
		t.furnish(ctx, s, Shops.frameOf(s), into)
	end
end

return Shops
