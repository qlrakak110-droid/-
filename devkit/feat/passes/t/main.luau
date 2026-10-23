local function dumpInfo(key, m, info, err)
	if not info then print(key, "ANALYZE FAILED", err) return end
	local keys = {}
	for k, v in info do table.insert(keys, k .. "=" .. typeof(v)) end
	table.sort(keys)
	print(key, "fields:", table.concat(keys, " "))
	print(key, "wheels", #(info.wheels or {}), "complete", Analyze.complete(info), "seats", info.seats and #info.seats)
	for i, w in info.wheels or {} do
		print("  wheel", i, "front", w.front, "side", w.side, "parts", w.parts and #w.parts or (w.spin and #w.spin), "r", w.radius)
	end
	local n = 0
	for _, d in m:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
	print(key, "parts", n)
	if info.frame then print(key, "frame look", info.frame.LookVector, "pos", info.frame.Position) end
	print(key, "L W H", info.L, info.W, info.H, "clear", info.clearance, "wb", info.wheelbase, "box", info.box and (info.box.size or info.box.Size), "frontTop", info.frontTop)
	if info.lamps then for k, v in info.lamps do local names = {} if typeof(v) == "table" then for _, x in v do table.insert(names, if typeof(x) == "Instance" then x.Name else typeof(x)) end end print("  lamps", k, table.concat(names, ",")) end end
end
for _, key in { "hyper", "super" } do
	local m = CarBodies.build(key, Color3.fromRGB(196, 18, 36), Color3.fromRGB(170, 90, 255))
	m:SetAttribute("VehicleKind", "gw_" .. key)
	local ok, info, err = pcall(Analyze.run, m)
	if not ok then print(key, "ERROR", info) else dumpInfo(key, m, info, err) end
	local fr, ext = CarBodies.frameOf(m)
	print(key, "frameOf look", fr.LookVector, "ext", ext)
end
-- a kit-car-like sedan (Spawn.fallbackCar shape) for the VIP / offroad kits
local function kitCar()
	local m = Instance.new("Model")
	local function box(name, size, pos, color, parent)
		local p = Instance.new("Part"); p.Name = name; p.Size = size; p.CFrame = CFrame.new(pos); p.Color = color; p.Anchored = true; p.Parent = parent or m; return p
	end
	local L, W = 16, 6.2
	box("Underbody", Vector3.new(W - 0.7, 0.5, L - 2), Vector3.new(0, 0.75, 0), Color3.fromRGB(26, 26, 28))
	box("BodySide", Vector3.new(W, 1.9, L), Vector3.new(0, 1.95, 0), Color3.fromRGB(236, 237, 236))
	box("Roof", Vector3.new(W - 0.6, 1.4, L * 0.5), Vector3.new(0, 3.6, 0.8), Color3.fromRGB(236, 237, 236))
	box("Windshield", Vector3.new(W - 0.8, 1.2, 0.2), Vector3.new(0, 3.6, -L * 0.25 + 0.9), Color3.fromRGB(36, 46, 52)).Transparency = 0.5
	box("Grille", Vector3.new(W * 0.5, 0.6, 0.2), Vector3.new(0, 1.8, -L / 2 - 0.05), Color3.fromRGB(20, 20, 22))
	box("HeadlampLens", Vector3.new(1, 0.4, 0.2), Vector3.new(-W / 2 + 0.9, 2.3, -L / 2 - 0.05), Color3.fromRGB(208, 216, 226))
	box("TailLamp", Vector3.new(1.2, 0.4, 0.2), Vector3.new(W / 2 - 0.9, 2.4, L / 2 + 0.05), Color3.fromRGB(150, 14, 22))
	box("PlateRear", Vector3.new(1.74, 0.37, 0.1), Vector3.new(0, 1.4, L / 2 + 0.06), Color3.new(1, 1, 1))
	local int = Instance.new("Model"); int.Name = "Interior"; int.Parent = m
	box("SeatCushion", Vector3.new(1.7, 0.48, 1.75), Vector3.new(-1.25, 1.75, 0), Color3.new(), int)
	box("SeatCushion", Vector3.new(1.7, 0.48, 1.75), Vector3.new(1.25, 1.75, 0), Color3.new(), int)
	local d = 2.2
	for _, z in { -L * 0.3, L * 0.28 } do for _, s in { -1, 1 } do
		local t = box("Tyre", Vector3.new(0.78, d, d), Vector3.new(s * (W / 2 - 0.45), d / 2, z), Color3.new()); t.Shape = Enum.PartType.Cylinder
		box("Rim", Vector3.new(0.8, d * 0.6, d * 0.6), Vector3.new(s * (W / 2 - 0.45), d / 2, z), Color3.new(0.7,0.7,0.7)).Shape = Enum.PartType.Cylinder
	end end
	m:PivotTo(CFrame.new(100, 5, 50) * CFrame.Angles(0, math.rad(37), 0))
	return m
end
for _, which in { "vip", "offroad" } do
	local m = kitCar()
	local fr, ext = CarBodies.frameOf(m)
	print(which, "frameOf look", fr.LookVector, "pos", fr.Position, "ext", ext)
	if which == "vip" then CarBodies.kitVip(m, Color3.new(1, 1, 1)) else CarBodies.kitOffroad(m, { lift = 0.9, tyreGrow = 0.55 }) end
	m:SetAttribute("VehicleKind", "gw_" .. which)
	local ok, info, err = pcall(Analyze.run, m)
	if not ok then print(which, "ERROR", info) else print(which, "wheels", #(info.wheels or {}), "complete", Analyze.complete(info), "seats", #(info.seats or {}), "clear", info.clearance, "H", info.H, "L", info.L) end
	for _, w in info.wheels or {} do print("  wheel parts", #(w.parts or {})) end
end
