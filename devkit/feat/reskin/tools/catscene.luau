--!nocheck
-- catscene.luau [itemId|all] [colorway]: build catalog item(s) at the origin (front = -Z, floor y = 0) with a
-- 24x24 floor + back wall, print "SCENE <id> <json>" lines in the bprev preview.js scene format.
local M = require("./cat_mods")
local R, F = M.R, M.Furniture
local CFrame, Vector3 = R.G.CFrame, R.G.Vector3
local args = { ... }
local which, cw = args[1] or "all", tonumber(args[2] or "1") or 1
local nextId = 1
local function cf12(c)
	local x, y, z, a, b, cc, d, e, f, g, h, i = c:GetComponents()
	return { x, y, z, a, b, cc, d, e, f, g, h, i }
end
local function col(c)
	return { c.R, c.G, c.B }
end
local function dumpModel(m, out)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local id = nextId
			nextId += 1
			local r = { id = id, cls = d.ClassName, name = d.Name, cf = cf12(d.CFrame), size = { d.Size.X, d.Size.Y, d.Size.Z }, col = col(d.Color), mat = d.Material.Name, t = d.Transparency, rf = d.Reflectance }
			if d.ClassName == "Part" and d.Shape ~= R.G.Enum.PartType.Block then
				r.shape = d.Shape.Name
			end
			table.insert(out.parts, r)
			for _, c in d:GetChildren() do
				if c:IsA("Light") then
					table.insert(out.lights, { cls = c.ClassName, part = id, c = col(c.Color), b = c.Brightness, range = c.Range, angle = if c:IsA("PointLight") then 90 else c.Angle, face = if c:IsA("PointLight") then "Front" else c.Face.Name, on = true, shadows = false })
				elseif c:IsA("SurfaceGui") then
					local g = { cls = "SurfaceGui", part = id, face = c.Face.Name, kids = {} }
					for _, k in c:GetDescendants() do
						if k:IsA("TextLabel") then
							table.insert(g.kids, { cls = "TextLabel", text = k.Text, tc = col(k.TextColor3), bg = col(k.BackgroundColor3), bgT = k.BackgroundTransparency, vis = true })
						end
					end
					table.insert(out.guis, g)
				end
			end
		end
	end
end
for _, id in F.ORDER do
	if which == "all" or which == id then
		local def = F.ITEMS[id]
		local out = { parts = {}, guis = {}, lights = {}, venue = { id = 0, path = "reskin/" .. id, name = id } }
		-- room: floor 24 x 24 at y -0.25..0, back wall behind the item (catalog front = -Z, so the wall is at +Z)
		local floorCF = CFrame.new(0, -0.25, 0)
		table.insert(out.parts, { id = nextId, cls = "Part", name = "RoomFloor", cf = cf12(floorCF), size = { 24, 0.5, 24 }, col = { 0.78, 0.74, 0.68 }, mat = "WoodPlanks", t = 0, rf = 0 })
		nextId += 1
		table.insert(out.parts, { id = nextId, cls = "Part", name = "RoomWall", cf = cf12(CFrame.new(0, 6, def.d / 2 + 0.35)), size = { 24, 12, 0.5 }, col = { 0.93, 0.92, 0.9 }, mat = "Plaster", t = 0, rf = 0 })
		nextId += 1
		out.venue.floor = { cf = cf12(floorCF), size = { 24, 0.5, 24 } }
		local m = F.build(id, R.workspace, CFrame.new(0, 0, 0), cw, { W = if id == "kitchen_counter" then 7 else nil })
		dumpModel(m, out)
		m:Destroy()
		print("SCENE " .. id .. " " .. R.json(out))
	end
end
