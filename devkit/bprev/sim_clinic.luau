--!nocheck
-- sim.luau -a <key> [x y z]: build one venue offline and write out/<key>.gen.json (stdout = JSON, log on stderr-ish lines prefixed "#")
local R = require("./lib/rbx")
local Enum, Vector3, CFrame = R.G.Enum, R.G.Vector3, R.G.CFrame
local args = { ... }
local key = args[1]
local fx = require("./fx/" .. key)(R.G.Vector3, R.G.Color3, R.G.CFrame)
local model = R.loadFixture(fx)
do
	local okS, shFn = pcall(require, "./clinic_shell")
	if okS and type(shFn) == "function" then
		R.loadFixture(shFn(R.G.Vector3, R.G.Color3, R.G.CFrame))
	end
end
local req = require("./out/mods")
local Scan, Build = req("Scan"), req("Build")
-- 큰 시설의 방: fx/<key>_room.luau (function(Vector3, CFrame) -> spec) 가 있으면 Scan.fitRoom
local okR, roomFn = pcall(require, "../fx/" .. key .. "_room") -- (sim runs from out/)
local ok, V, why
if okR and type(roomFn) == "function" then
	local spec = roomFn(R.G.Vector3, R.G.CFrame)
	if spec.home and spec.room then
		-- 생활 게임 집의 방 (Homes.rooms 와 같은 spec / keep)
		local Homes = req("Homes")
		local pick = nil
		for _, sp in Homes.rooms(model) do
			if sp.room == spec.room then
				pick = sp
			end
		end
		if not pick then
			local names = {}
			for _, sp in Homes.rooms(model) do
				table.insert(names, sp.room)
			end
			print("#no home room " .. tostring(spec.room) .. " (have " .. table.concat(names, ",") .. ")")
			return
		end
		ok, V, why = pcall(Scan.fitRoom, model, pick)
		if ok and V then
			Homes.post(V, model)
		end
	elseif spec.venue and spec.room then
		-- Venues.LIST 의 방 (생성된 Venues.luau 와 같은 spec / keep)
		local Venues = req("Venues")
		local vv, rr
		for _, v in Venues.LIST do
			if v.name == spec.venue then
				for _, r in v.rooms do
					if r.room == spec.room then
						vv, rr = v, r
					end
				end
			end
		end
		if not rr then
			print("#no venue room " .. tostring(spec.venue) .. "#" .. tostring(spec.room))
			return
		end
		ok, V, why = pcall(Scan.fitRoom, model, Venues.spec(model, vv, rr))
		if ok and V then
			Venues.post(V, rr)
		end
	else
		ok, V, why = pcall(Scan.fitRoom, model, spec)
	end
else
	ok, V, why = pcall(Scan.fit, model)
end
if not ok then
	print("#FIT ERROR " .. tostring(V))
	return
end
if not V then
	print("#fit failed: " .. tostring(why))
	return
end
print(string.format("#V %s type=%s menu=%s W=%.1f D=%.1f H=%.1f x0=%.1f x1=%.1f z0=%.1f z1=%.1f door=%s chairs=%d stools=%d tables=%d counters=%d keep=%d solid=%d", V.key, tostring(V.type), tostring(V.menu), V.W, V.D, V.H, V.x0, V.x1, V.z0, V.z1, V.door and string.format("%.1f,%.1f w%.1f", V.door.x, V.door.z, V.door.w) or "nil", #V.chairs, #V.stools, #V.tables, #V.counters, #V.keep, #V.solid))
local folder = R.Instance.new("Model")
folder.Name = "Venue"
folder.Parent = R.workspace
local t0 = os.clock()
local ok2, K = pcall(Build.run, V, folder)
if not ok2 then
	print("#BUILD ERROR " .. tostring(K))
	return
end
-- run animations once (clock hands etc.)
for _, f in K.anims or {} do
	local okA, e = pcall(f, 1000, 0.1)
	if not okA then
		print("#anim error " .. tostring(e))
	end
end
local hiddenN = 0
for _ in K.hidden do
	hiddenN += 1
end
print(string.format("#K parts=%d hidden=%d lights=%d prompts=%d blocked=%d ghosts=%d %.0fms", #K.parts, hiddenN, #K.lights, #K.prompts, K.blocked, #K.ghosts, (os.clock() - t0) * 1000))
for _, l in K.log do
	print("#  " .. l)
end
for _, p in K.prompts do
	print(string.format("#  prompt %s / %s @ %s", p.ActionText, p.ObjectText, tostring(V.cf:PointToObjectSpace(p.Parent.Position))))
end
-- dump
local function cf12(c)
	local x, y, z, a, b, cc, d, e, f, g, h, i = c:GetComponents()
	return { x, y, z, a, b, cc, d, e, f, g, h, i }
end
local function col(c)
	return { c.R, c.G, c.B }
end
local out = { parts = {}, guis = {}, lights = {}, hidden = {}, cams = {}, log = K.log, vcf = nil, V = nil }
local function id(i)
	return rawget(i, "_p")._id
end
for _, d in folder:GetDescendants() do
	if d:IsA("BasePart") then
		local r = { id = id(d), cls = d.ClassName, name = d.Name, cf = cf12(d.CFrame), size = { d.Size.X, d.Size.Y, d.Size.Z }, col = col(d.Color), mat = d.Material.Name, t = d.Transparency }
		if d.ClassName == "Part" and d.Shape ~= Enum.PartType.Block then
			r.shape = d.Shape.Name
		end
		local m = d:FindFirstChildOfClass("SpecialMesh")
		if m then
			r.mesh = { type = m.MeshType.Name, scale = { m.Scale.X, m.Scale.Y, m.Scale.Z } }
		end
		table.insert(out.parts, r)
		for _, c in d:GetChildren() do
			if c:IsA("SurfaceGui") then
				local g = { part = id(d), face = c.Face.Name, cls = "SurfaceGui", kids = {} }
				for _, k in c:GetDescendants() do
					if k:IsA("TextLabel") then
						table.insert(g.kids, { cls = "TextLabel", text = k.Text, tc = col(k.TextColor3), bg = col(k.BackgroundColor3), bgT = k.BackgroundTransparency, vis = k.Visible })
					elseif k:IsA("Frame") then
						table.insert(g.kids, { cls = "Frame", bg = col(k.BackgroundColor3), bgT = k.BackgroundTransparency, vis = k.Visible })
					end
				end
				if c.Enabled then
					table.insert(out.guis, g)
				end
			elseif c:IsA("Light") then
				table.insert(out.lights, { cls = c.ClassName, part = id(d), c = col(c.Color), b = c.Brightness, range = c.Range, angle = if c:IsA("PointLight") then 90 else c.Angle, face = if c:IsA("PointLight") then "Front" else c.Face.Name, on = c.Enabled, gen = true })
			end
		end
	end
end
for p in K.hidden do
	table.insert(out.hidden, id(p))
end
out.keeps = {}
do
	local KV = K.V or V
	out.v2cf = cf12(KV.cf)
	out.v2 = { x0 = KV.x0, x1 = KV.x1, z0 = KV.z0, z1 = KV.z1, H = KV.H }
	for _, k in KV.keep or {} do
		local cs = {}
		for _, q in { { k.min.X, k.min.Z }, { k.max.X, k.min.Z }, { k.max.X, k.max.Z }, { k.min.X, k.max.Z } } do
			local w = KV.cf:PointToWorldSpace(Vector3.new(q[1], 0, q[2]))
			table.insert(cs, { w.X, w.Z })
		end
		table.insert(out.keeps, { kind = tostring(k.kind), pts = cs, y0 = k.min.Y, y1 = k.max.Y })
	end
end
out.vcf = cf12(V.cf)
out.V = { W = V.W, D = V.D, H = V.H, x0 = V.x0, x1 = V.x1, z0 = V.z0, z1 = V.z1, type = V.type }
-- cameras from the venue frame (+Z = entrance)
local function w(x, y, z)
	local p = V.cf * Vector3.new(x, y, z)
	return { p.X, p.Y, p.Z }
end
local W, D = V.x1 - V.x0, V.z1 - V.z0
local cx, cz = (V.x0 + V.x1) / 2, (V.z0 + V.z1) / 2
local eyeY = math.min(5.4, V.H - 1)
out.cams = {
	{ name = "entry", eye = w(cx, eyeY, V.z1 - 1.0), at = w(cx, 3.4, V.z0), fov = 76 },
	{ name = "back", eye = w(cx, eyeY + 0.3, V.z0 + 1.2), at = w(cx, 3.0, V.z1), fov = 76 },
	{ name = "cornerL", eye = w(V.x1 - 0.9, math.min(6.6, V.H - 0.6), V.z1 - 0.9), at = w(cx - W / 4, 2.2, cz - D / 4), fov = 76 },
	{ name = "cornerR", eye = w(V.x0 + 0.9, math.min(6.6, V.H - 0.6), V.z1 - 0.9), at = w(cx + W / 4, 2.2, cz - D / 4), fov = 76 },
	{ name = "backL", eye = w(V.x1 - 0.9, math.min(6.2, V.H - 0.6), V.z0 + 0.9), at = w(cx - W / 4, 2.4, cz + D / 4), fov = 76 },
	{ name = "backR", eye = w(V.x0 + 0.9, math.min(6.2, V.H - 0.6), V.z0 + 0.9), at = w(cx + W / 4, 2.4, cz + D / 4), fov = 76 },
}
if #V.counters > 0 then
	local g = V.counters[1]
	local c = (g.min + g.max) / 2
	out.cams[#out.cams + 1] = { name = "counter", eye = w(c.X + 1.5, 5.2, math.min(V.z1 - 1, g.max.Z + 6)), at = w(c.X, 3.2, c.Z - 1), fov = 70 }
end
local f = io and io.open
print("JSON " .. R.json(out))
