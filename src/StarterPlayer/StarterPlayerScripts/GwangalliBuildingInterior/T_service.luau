--!strict
-- GwangalliBuildingInterior/T_service: 유형 (lobby residence realty laundry office bank clinic academy) 실내.
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일 (메뉴판 · 진열 · 주방 · 간판 · 소품 · 상호작용)

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))

local T = {}
T.types = { "lobby", "residence", "realty", "laundry", "office", "bank", "clinic", "academy" }

function T.style(V: any): any
	return {
		chair = { style = "padded", frame = Look.blackMetal, seat = Look.fabricGrey },
		table = { top = Look.oak, base = Look.blackMetal },
		counter = { front = "panel", frontL = Look.white, topL = Look.marbleWhite },
		lights = { kind = "downlight" },
	}
end

function T.build(K: any, V: any, S: any) end

return T
