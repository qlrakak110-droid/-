--!nocheck
local B = require("./mods")
local req, R = B.req, B.R
local G = R.G
local args = { ... }
local fx = require("../../../bprev/fx/" .. args[1])(G.Vector3, G.Color3, G.CFrame)
local model = R.loadFixture(fx)
local rec = req("Scan").shop(model, "street", 1)
local z0, z1 = tonumber(args[2]), tonumber(args[3])
local _, yaw = rec.frame:ToEulerAnglesYXZ()
local frame = G.CFrame.new(rec.frame.X, rec.floorY, rec.frame.Z) * G.CFrame.Angles(0, yaw, 0)
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		local l = frame:PointToObjectSpace(d.Position)
		if l.Z > z0 and l.Z < z1 and l.Y > 0.3 and l.Y < 5.5 then
			print(string.format("%-16s %-14s x=%.1f y=%.1f z=%.1f size=%.1f,%.1f,%.1f T=%.2f CC=%s", d.Name, d.Parent.Name, l.X, l.Y, l.Z, d.Size.X, d.Size.Y, d.Size.Z, d.Transparency, tostring(d.CanCollide)))
		end
	end
end
for _, tb in rec.tables do
	local a, b = frame:PointToObjectSpace(tb.min), frame:PointToObjectSpace(tb.max)
	print("table", tb.id, tb.kind, tb.part and tb.part.Name, string.format("%.1f,%.1f .. %.1f,%.1f", a.X, a.Z, b.X, b.Z), #tb.seats)
end
print("counter", rec.counter and rec.counter.Name, rec.counter and tostring(frame:PointToObjectSpace(rec.counter.Position)), rec.counter and tostring(rec.counter.Size))
