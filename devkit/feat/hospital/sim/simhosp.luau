--!nocheck
-- simhosp.luau: HospitalPlus 전체를 오프라인으로 짓고 out/hosp.gen.json 형식(JSON 줄)으로 덤프
local R = require("./lib/rbx")
local G = R.G
local Vector3 = G.Vector3
local fxMain = require("../../../bprev/fx/hospital_backhall")(G.Vector3, G.Color3, G.CFrame)
local fxBld = require("./fx_bld")(G.Vector3, G.Color3, G.CFrame)
R.loadFixture(fxMain)
R.loadFixture(fxBld)
local args0 = ({ ... })[3]
local req = require("./out/mods_hosp")
local HP = req("HospitalPlus")
if args0 == "unlimited" then for _, b in req("Hosp_Geo").BUDGET do b.high, b.mid, b.low = 5000, 5000, 5000 end end
local root = R.Instance.new("Folder")
root.Name = "GwInteriorDetailLocal"
root.Parent = R.workspace
local args = { ... }
local tier = args[1] or "high"
local ctx = {
	root = root,
	focus = function() return Vector3.new(-515, 10, 300) end,
	limits = function()
		if tier == "low" then return 1, 1300, 4 elseif tier == "mid" then return 2, 2100, 6 end
		return 3, 2600, 8
	end,
	dbg = function(...) local t = {} for _, v in { ... } do table.insert(t, tostring(v)) end print("#" .. table.concat(t, " ")) end,
	script = nil,
	Scan = req("Scan"),
}
local t0 = os.clock()
local ok, zones = pcall(HP._buildAll, ctx)
if not ok then print("#BUILD ERROR " .. tostring(zones)) return end
local total, lights, prompts = 0, 0, 0
local hidden = {}
for name, K in zones do
	for _, f in K.anims or {} do
		local okA, e = pcall(f, 1000, 0.1)
		if not okA then print("#anim error " .. name .. " " .. tostring(e)) end
	end
	for _, f in K.secs or {} do
		local okS, e = pcall(f, 1000)
		if not okS then print("#sec error " .. name .. " " .. tostring(e)) end
	end
	local hn = 0
	for p in K.hidden do hn += 1 table.insert(hidden, p) end
	print(string.format("#zone %-12s parts=%4d lights=%d prompts=%2d blocked=%d hidden=%d ghosts=%d", name, #K.parts, #K.lights, #K.prompts, K.blocked, hn, #K.ghosts))
	for _, l in K.log do print("#   " .. l) end
	total += #K.parts lights += #K.lights prompts += #K.prompts
end
print(string.format("#TOTAL parts=%d lights=%d prompts=%d %.0f ms", total, lights, prompts, (os.clock() - t0) * 1000))
if args[2] == "prompts" then
	for name, K in zones do
		for _, p in K.prompts do
			print(string.format("#  [%s] %s / %s @ %s", name, p.ActionText, p.ObjectText, tostring(K.V.cf:PointToObjectSpace(p.Parent.Position))))
		end
	end
end
-- dump (sim.luau 형식)
local function cf12(c) local x, y, z, a, b, cc, d, e, f, g, h, i = c:GetComponents() return { x, y, z, a, b, cc, d, e, f, g, h, i } end
local function col(c) return { c.R, c.G, c.B } end
local function id(i) return rawget(i, "_p")._id end
local out = { parts = {}, guis = {}, lights = {}, hidden = {}, cams = {}, log = {}, vcf = cf12(G.CFrame.new(-515, 6.9, 300)), V = { W = 120, D = 76, H = 11, x0 = -60, x1 = 60, z0 = -38, z1 = 38, type = "hosp" } }
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 0.99 then
		local r = { id = id(d), cls = d.ClassName, name = d.Name, cf = cf12(d.CFrame), size = { d.Size.X, d.Size.Y, d.Size.Z }, col = col(d.Color), mat = d.Material.Name, t = d.Transparency }
		if d.ClassName == "Part" and d.Shape ~= G.Enum.PartType.Block then r.shape = d.Shape.Name end
		local m = d:FindFirstChildOfClass("SpecialMesh")
		if m then r.mesh = { type = m.MeshType.Name, scale = { m.Scale.X, m.Scale.Y, m.Scale.Z } } end
		table.insert(out.parts, r)
		for _, c in d:GetChildren() do
			if c:IsA("SurfaceGui") then
				local gg = { part = id(d), face = c.Face.Name, cls = "SurfaceGui", kids = {} }
				for _, k in c:GetDescendants() do
					if k:IsA("TextLabel") then
						table.insert(gg.kids, { cls = "TextLabel", text = k.Text, tc = col(k.TextColor3), bg = col(k.BackgroundColor3), bgT = k.BackgroundTransparency, vis = k.Visible })
					end
				end
				if c.Enabled then table.insert(out.guis, gg) end
			elseif c:IsA("Light") then
				table.insert(out.lights, { cls = c.ClassName, part = id(d), c = col(c.Color), b = c.Brightness, range = c.Range, angle = if c:IsA("PointLight") then 90 else c.Angle, face = if c:IsA("PointLight") then "Front" else c.Face.Name, on = c.Enabled, gen = true })
			end
		end
	end
end
for _, p in hidden do table.insert(out.hidden, id(p)) end
print("JSON " .. R.json(out))
