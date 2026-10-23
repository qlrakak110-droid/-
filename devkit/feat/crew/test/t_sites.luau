--!nocheck
-- t_sites.luau <fixtureKey> [ascii]: real ShopLife Scan on a place fixture -> GwangalliShopCrew Sites -> checks
local B = require("./mods")
local req, R = B.req, B.R
local G = R.G
local Vector3, CFrame = G.Vector3, G.CFrame
local args = { ... }
local key = args[1]
local FX = "../../../bprev/fx/"
local fx = require(FX .. key)(G.Vector3, G.Color3, G.CFrame)
local model = R.loadFixture(fx)
local Scan = req("Scan")
local kind = if model:HasTag("GwShop") then "gwshop" else "street"
local rec = Scan.shop(model, kind, 1)
if not rec then print("NO REC") return end
local Shared = req("CS_init")
local Sites = req("SV_Sites")
local Bridge = {
	shopRec = function() return rec end, staffSites = function() return {} end, jobSites = function() return {} end,
	has = function() return false end, warnOnce = function(_, m) print("WARN", m) end,
}
Sites.init(Shared, Bridge)
local t0 = os.clock()
local site = Sites.build(rec.key)
local ms = (os.clock() - t0) * 1000
print(string.format("%s type=%s flow=%s tables=%d ok=%s why=%s  %.1f ms  grid %dx%d", rec.name, rec.type, site.flow, #site.tables, tostring(site.ok), tostring(site.why), ms, site.nav and site.nav.nx or 0, site.nav and site.nav.nz or 0))
local roles = {}
for _, d in site.roles or {} do table.insert(roles, d.role) end
print("roles", table.concat(roles, ","), "station", site.station and site.station.Name or "-", "pass", rec.pass and rec.pass.Name or "-", "counter", rec.counter and rec.counter.Name or "-")
local sp = site.spots or {}
local function fmt(s) if not s then return "-" end return string.format("(%.1f,%.1f yaw %d)", s.lx, s.lz, math.floor(s.yaw)) end
print("C", fmt(sp.C), "S", fmt(sp.S), "H", fmt(sp.H), "K", fmt(sp.K), "Din", fmt(sp.Din), "Dout", fmt(sp.Dout))
local bad = 0
local function inTable(p)
	for _, tb in site.tables do
		if tb.min and tb.max and tb.kind ~= "bar" and tb.kind ~= "counter" and p.X > tb.min.X - 0.05 and p.X < tb.max.X + 0.05 and p.Z > tb.min.Z - 0.05 and p.Z < tb.max.Z + 0.05 then return tb.id end
	end
end
local function checkPath(a, b, label)
	local pts = Sites.path(site, a, b, site.main)
	if not pts then print("  NO PATH", label) bad += 1 return nil end
	-- sample the polyline
	for i = 2, #pts do
		local p0, p1 = pts[i - 1], pts[i]
		for s = 0, 10 do
			local q = p0:Lerp(p1, s / 10)
			local t = inTable(q)
			if t then print("  THROUGH TABLE", t, label) bad += 1 return pts end
		end
	end
	return pts
end
local marks = {}
for _, tb in site.tables do
	local e = sp.A[tb.id]
	if not e then print("  table", tb.id, "NO APPROACH") bad += 1
	else
		local n = 0
		for _ in e.seats do n += 1 end
		local pts = sp.S and checkPath(sp.S.pos, e.best.pos, "S->T" .. tb.id)
		if sp.Dout then checkPath(sp.Dout.pos, e.best.pos, "Dout->T" .. tb.id) end
		local lx, lz = Sites.toLocal(site, e.best.pos)
		table.insert(marks, { lx, lz })
		print(string.format("  T%d %s seats %d/%d best %s path %s", tb.id, tb.kind, n, #tb.seats, fmt(e.best), pts and string.format("%d pts %.1f", #pts, 0) or "-"))
	end
end
if sp.C and sp.S then checkPath(sp.S.pos, sp.H.pos, "S->H") end
print("BAD", bad)
if args[2] == "ascii" then
	if sp.C then table.insert(marks, 1, { sp.C.lx, sp.C.lz }) end
	print(site.nav:ascii(marks))
end
