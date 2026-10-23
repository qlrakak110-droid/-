--!nocheck
-- catdump.luau: build every Furniture catalog item at the origin (front = -Z) and print its parts in item-local space
local M = require("./cat_mods")
local R, F = M.R, M.Furniture
local CFrame, Vector3 = R.G.CFrame, R.G.Vector3
local CS = { HasTag = function(_, i, t) return i:HasTag(t) end }
local out = {}
for _, id in F.ORDER do
	local def = F.ITEMS[id]
	local m = F.build(id, R.workspace, CFrame.new(0, 0, 0), 1, {})
	local parts = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			local tags = {}
			for _, t in { "GwB_Seat", "GwB_Screen", "GwB_Lamp", "GwB_Spin", "GwB_Water" } do
				if CS:HasTag(d, t) then table.insert(tags, t) end
			end
			local extra = {}
			for _, c in d:GetChildren() do
				if c:IsA("Light") then table.insert(extra, c.ClassName) end
				if c:IsA("SurfaceGui") then table.insert(extra, "SurfaceGui") end
				if c:IsA("Attachment") and c:GetAttribute("SoundKey") then table.insert(extra, "snd:" .. c:GetAttribute("SoundKey")) end
			end
			local attrs = {}
			for k, v in d:GetAttributes() do
				if k ~= "LampOff" then table.insert(attrs, k .. "=" .. tostring(v)) end
			end
			local shape = if d.ClassName == "Part" and d.Shape ~= R.G.Enum.PartType.Block then d.Shape.Name else ""
			local rot = d.CFrame - p
			local rx, ry, rz = rot:ToEulerAnglesXYZ()
			table.insert(parts, string.format("    %-14s %-9s %-10s pos(%.2f,%.2f,%.2f) size(%.2f,%.2f,%.2f)%s mat=%s col=%d,%d,%d tr=%.2f coll=%s q=%s%s%s%s%s",
				d.Name, d.ClassName, shape, p.X, p.Y, p.Z, d.Size.X, d.Size.Y, d.Size.Z,
				if math.abs(rx) + math.abs(ry) + math.abs(rz) > 1e-3 then string.format(" rot(%.0f,%.0f,%.0f)", math.deg(rx), math.deg(ry), math.deg(rz)) else "",
				d.Material.Name, math.floor(d.Color.R * 255 + 0.5), math.floor(d.Color.G * 255 + 0.5), math.floor(d.Color.B * 255 + 0.5), d.Transparency,
				tostring(d.CanCollide), tostring(d.CanQuery),
				#tags > 0 and (" tags=" .. table.concat(tags, ",")) or "", #extra > 0 and (" +" .. table.concat(extra, ",")) or "",
				#attrs > 0 and (" attrs{" .. table.concat(attrs, ",") .. "}") or "", d == m.PrimaryPart and " [PRIMARY]" or ""))
		end
	end
	local cols = {}
	for i, c in def.colors do cols[i] = string.format("(%d,%d,%d)", c[1], c[2], c[3]) end
	print(string.format("## %s  \"%s\"  cat=%s kind=%s wall=%s flat=%s mountY=%s fixed=%s  w=%.2f d=%.2f h=%.2f  parts=%d  colors=%s  fixtureTag=%s",
		id, def.name, def.cat, tostring(def.kind), tostring(def.wall == true), tostring(def.flat == true), tostring(def.mountY or 0), tostring(def.fixed == true),
		def.w, def.d, def.h, #parts, table.concat(cols, " "), tostring(CS:HasTag(m, "GwB_Fixture"))))
	for _, l in parts do print(l) end
	m:Destroy()
end
