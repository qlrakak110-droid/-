--!strict
-- GwangalliBuildingInterior/T_seafood: 유형 (rawfish seafood) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 주방 · 간판 · 소품 · 상호작용)

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))

local T = {}
T.types = { "rawfish", "seafood" }

function T.style(V: any): any
	return {
		chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
		table = { top = Look.oak, base = Look.blackMetal },
		counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
		lights = { kind = "downlight" },
	}
end

function T.build(K: any, V: any, S: any)
	for _, k in V.keep do
		print(string.format("KEEP %-10s %6.1f %5.1f %6.1f  ->  %6.1f %5.1f %6.1f", k.kind, k.min.X, k.min.Y, k.min.Z, k.max.X, k.max.Y, k.max.Z))
	end
	for _, s in V.solid do
		print(string.format("SOLID %-14s %6.1f %5.1f %6.1f  ->  %6.1f %5.1f %6.1f", tostring(s.name), s.min.X, s.min.Y, s.min.Z, s.max.X, s.max.Y, s.max.Z))
	end
	for _, w in { "back", "left", "right" } do
		local t = {}
		for _, sp in V:spans(w, 1.0, 7.0, 1.0) do table.insert(t, string.format("[%.1f,%.1f]", sp[1], sp[2])) end
		print("SPANS " .. w .. " a=" .. V.walls[w].a .. " b=" .. V.walls[w].b .. " " .. table.concat(t, " "))
	end
end

return T
