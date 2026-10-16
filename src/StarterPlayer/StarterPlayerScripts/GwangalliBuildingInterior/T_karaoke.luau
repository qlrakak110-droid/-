--!strict
local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))

local T = {}
T.types = { "karaoke", "kcorridor", "kbooth" }

function T.style(V: any): any
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = false, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true, ceiling = true } }
end

function T.build(K: any, V: any, S: any)
	for _, k in V.keep do
		K:note(string.format("keep %s (%.1f,%.1f,%.1f)-(%.1f,%.1f,%.1f)", k.kind, k.min.X, k.min.Y, k.min.Z, k.max.X, k.max.Y, k.max.Z))
	end
	for _, t in V.tables do
		K:note(string.format("table %s y=%.2f (%.1f,%.1f)-(%.1f,%.1f)", t.top.name, t.y, t.min.X, t.min.Z, t.max.X, t.max.Z))
	end
	for _, c in V.chairs do
		K:note(string.format("chair %s top=%.2f c=(%.1f,%.1f) face=(%.1f,%.1f) n=%d", c.seat.name, c.top, c.c.X, c.c.Z, c.face.X, c.face.Z, #c.parts))
	end
	for _, s in V.solid do
		if #K.log < 58 then
			K:note(string.format("solid %s (%.1f,%.1f,%.1f)-(%.1f,%.1f,%.1f)", s.name, s.min.X, s.min.Y, s.min.Z, s.max.X, s.max.Y, s.max.Z))
		end
	end
end

return T
