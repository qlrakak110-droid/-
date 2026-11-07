--!strict
-- SeoulSkyline / TerrainPlan
-- 지형: 한강 수면 + 강바닥 + 호안(돌 사면) + 양쪽 둔치 잔디 + 제방 사면.
-- 도시 지면/도로/산책로 포장은 Riverside/Park 모듈이 파트로 덮습니다.

local Config = require(script.Parent.Config)
local Kit = require(script.Parent.Kit)

local TerrainPlan = {}

function TerrainPlan.build(_ctx: any)
	local L, R, F, N = Config.Level, Config.River, Config.FarBank, Config.NearBank
	local x0, x1 = R.XMin, R.XMax
	local chunk = 2000
	-- 1) 강물 (청크로 나눠 채움)
	local zw0, zw1 = F.WaterEdge - 8, N.WaterEdge + 8
	local x = x0
	while x < x1 do
		local xe = math.min(x + chunk, x1)
		local cx = (x + xe) / 2
		Kit.terrain("Block", CFrame.new(cx, (L.RiverBed + L.Water) / 2, (zw0 + zw1) / 2), Vector3.new(xe - x, L.Water - L.RiverBed, zw1 - zw0), Enum.Material.Water)
		-- 강바닥
		Kit.terrain("Block", CFrame.new(cx, L.RiverBed - 4, (zw0 + zw1) / 2), Vector3.new(xe - x, 8, zw1 - zw0), Enum.Material.Mud)
		x = xe
	end
	-- 2) 양쪽 둔치: 수면 가장자리 돌 사면(웨지) + 잔디 둔치 + 제방 사면
	local function bank(sign: number, B: any)
		-- sign = -1: 먼 쪽(물 → -Z), +1: 가까운 쪽(물 → +Z)
		local edge = B.WaterEdge
		local revW = 14 -- 호안 폭
		local x = x0
		while x < x1 do
			local xe = math.min(x + chunk, x1)
			local cx, w = (x + xe) / 2, xe - x
			-- 호안: 물속 바닥(-10)에서 둔치 높이까지 비스듬히. WedgePart 규약: 높은 면이 +Z.
			local hRev = L.Promenade + 10
			local zc = edge + sign * revW / 2
			local wedgeCF = CFrame.new(cx, -10 + hRev / 2, zc) * (if sign > 0 then CFrame.new() else CFrame.Angles(0, math.pi, 0))
			Kit.terrain("Wedge", wedgeCF, Vector3.new(w, hRev, revW), Enum.Material.Slate)
			-- 둔치 (잔디) : Promenade 높이까지, 두께 18
			local pz0, pz1 = edge + sign * revW, B.ParkTo
			Kit.terrain("Block", CFrame.new(cx, L.Promenade - 9, (pz0 + pz1) / 2), Vector3.new(w, 18, math.abs(pz1 - pz0)), Enum.Material.Grass)
			-- 제방 사면 (Promenade → Levee)
			local sh = L.Levee - L.Promenade
			local sz0, sz1 = B.ParkTo, B.SlopeTo
			local slopeCF = CFrame.new(cx, L.Promenade + sh / 2, (sz0 + sz1) / 2) * (if sign > 0 then CFrame.new() else CFrame.Angles(0, math.pi, 0))
			Kit.terrain("Wedge", slopeCF, Vector3.new(w, sh, math.abs(sz1 - sz0)), Enum.Material.Grass)
			-- 제방/도시 아래 흙 (사면 아래 + 도로 아래)
			Kit.terrain("Block", CFrame.new(cx, L.Promenade - 9, (sz0 + sz1) / 2), Vector3.new(w, 18, math.abs(sz1 - sz0)), Enum.Material.Ground)
			x = xe
		end
	end
	bank(-1, F)
	bank(1, N)
end

return TerrainPlan
