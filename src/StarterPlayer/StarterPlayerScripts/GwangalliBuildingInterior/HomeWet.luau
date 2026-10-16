--!strict
-- GwangalliBuildingInterior/HomeWet: 생활 게임 집의 물 쓰는 방 · 붙박이 (T_home 이 부름).
--   HomeWet.rooms[room] = true 인 방 (kitchen 주방 · bath 욕실 · entry 현관) 의 붙박이 · 설비 · 작은 물건을 짓습니다.
--   HomeWet.build(K, V, S)   V.room / V.tier (goshiwon · oneroom · officetel · apartment · penthouse) 로 갈래

local HomeWet = {}
HomeWet.rooms = { kitchen = true, bath = true, entry = true }

function HomeWet.build(K: any, V: any, S: any) end

return HomeWet
