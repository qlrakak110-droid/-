--!strict
-- GwangalliBuildingInterior/T_club: 큰 시설 방 유형 (clublounge rooftop hiphop) 실내 (Venues.luau 의 방, Scan.fitRoom).
--   style(V) -> S  Common 에 줄 공통 마감 스타일 (Common.luau 머리말의 S 필드)
--   build(K, V, S) 유형별 디테일

local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local Common = require(script.Parent:WaitForChild("Common"))

local T = {}
T.types = { "clublounge", "rooftop", "hiphop", "clublobby", "clubtunnel", "clubmain" }

function T.style(V: any): any
	-- 기본: 기존 가구는 그대로, 천장 설비만 (모듈을 채우면서 바꿈)
	return { chair = false, stool = false, table = false, counter = false, base = false, lower = false, mat = false, clock = false, license = false, cctv = false, ceiling = {}, lights = { kind = "none" }, skip = { upgrades = true, fixtures = true } }
end

function T.build(K: any, V: any, S: any) end

return T
