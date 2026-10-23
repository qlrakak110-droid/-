--!nocheck
-- export.luau <cat|id,id,...> [cols]: builds a showroom of catalog pieces -> JSON scene for render.js (stdout line "JSON ...")
local B = require("../out/bundle")
local Catalog = B.load("S", "Catalog")
local Palette = B.load("S", "Palette")
local CFrame, Vector3 = B.R.G.CFrame, B.R.G.Vector3
local args = { ... }
local sel = args[1] or "living"
local COLS = tonumber(args[2] or "4")
local ids = {}
if string.find(sel, ",") or Catalog.get(sel) then
	ids = string.split(sel, ",")
else
	for _, id in Catalog.ORDER do
		if Catalog.get(id).cat == sel then
			table.insert(ids, id)
		end
	end
end
local parts, lights, cams = {}, {}, {}
local function cfArr(cf)
	local x, y, z, a, b, c, d, e, f, g, h, i = cf:GetComponents()
	return { x, y, z, a, b, c, d, e, f, g, h, i }
end
local function add(shape, size, cf, rgb, mat, t)
	table.insert(parts, { shape = shape, size = { size.X, size.Y, size.Z }, cf = cfArr(cf), col = { rgb[1] / 255, rgb[2] / 255, rgb[3] / 255 }, mat = mat, t = t or 0 })
	return #parts - 1
end
local CELL = 9
local rows = math.ceil(#ids / COLS)
-- floor + back wall per row
for r = 0, rows - 1 do
	local ox = r * (COLS * CELL + 40)
	add("Block", Vector3.new(COLS * CELL + 4, 0.4, 13), CFrame.new(ox + (COLS - 1) * CELL / 2, -0.2, 0), { 196, 170, 132 }, "WoodPlanks")
	add("Block", Vector3.new(COLS * CELL + 4, 9, 0.4), CFrame.new(ox + (COLS - 1) * CELL / 2, 4.5, 4.2), { 236, 232, 224 }, "Plaster")
end
for i, id in ids do
	local col = (i - 1) % COLS
	local row = math.floor((i - 1) / COLS)
	local def = Catalog.get(id)
	local spec = Catalog.spec(id)
	if spec then
		local b = Catalog.bounds(id)
		local zBack = 4.0
		local ox = row * (COLS * CELL + 40)
		local base
		if def.place == "wall" then
			base = CFrame.new(ox + col * CELL, 2.2, zBack - b[6])
		elseif def.place == "ceiling" then
			base = CFrame.new(ox + col * CELL, 8.0 - b[5], 0)
		else
			base = CFrame.new(ox + col * CELL, 0, math.min(0, 3.9 - b[6]))
		end
		local first = #parts
		for _, p in spec.parts do
			local m = Palette.MATERIALS[p.mat]
			add(p.shape, p.size, base * p.cf, p.rgb, m and m.enum or "SmoothPlastic", p.t)
		end
		for _, l in spec.lights do
			local rgb = l.rgb or (spec.parts[l.p] and spec.parts[l.p].rgb) or { 255, 220, 180 }
			table.insert(lights, { part = first + l.p - 1, cls = "PointLight", c = { rgb[1] / 255, rgb[2] / 255, rgb[3] / 255 }, b = l.bright, range = l.range })
		end
		if def.place == "ceiling" then
			add("Block", Vector3.new(CELL - 0.5, 0.3, 8), CFrame.new(ox + col * CELL, 8.15, 0), { 240, 240, 236 }, "Plaster")
		end
	end
end
-- cameras: one per row
for r = 0, rows - 1 do
	local cx = r * (COLS * CELL + 40) + (COLS - 1) * CELL / 2
	local nm = string.sub((string.gsub(sel, ",", "_")), 1, 30)
	table.insert(cams, { name = string.format("%s_r%d", nm, r), eye = { cx, 6.5, -19 }, at = { cx, 2.2, 1 }, fov = 44 })
	table.insert(cams, { name = string.format("%s_r%d_iso", nm, r), eye = { cx + 13, 11, -13 }, at = { cx, 1.6, 1 }, fov = 52 })
end
local function enc(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 or next(v) == nil then
			local o = {}
			for _, x in v do
				table.insert(o, enc(x))
			end
			return "[" .. table.concat(o, ",") .. "]"
		end
		local o = {}
		for k, x in v do
			table.insert(o, string.format("%q:%s", k, enc(x)))
		end
		return "{" .. table.concat(o, ",") .. "}"
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "0"
		end
		return string.format("%.4f", v)
	elseif t == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end
print("JSON " .. enc({ parts = parts, lights = lights, cams = cams, clock = tonumber(args[3] or "14") }))
