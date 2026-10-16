--!strict
-- GwangalliBuildingInterior/Homes: 생활 게임 집 (HomeUnit_goshiwon · oneroom · officetel · apartment · penthouse) 을 방 단위로.
-- 집 모델(Workspace.GwangalliHomeInstances 아래 HomeUnit 복제본, 속성 Tier)의 Shell 바닥 파트(속성 Room = main / kitchen / bath /
-- living / bedroom / ...)를 방마다 묶어 Scan.fitRoom 용 spec 을 만듭니다. 방 프레임은 UnitRoot 방향, +Z = 그 방의 문(Door 모델) 쪽.
-- 플레이어가 꾸미는 집이라: 가구 슬롯(FurnitureSlot) 자리 · HomeInteract 파트 둘레는 비워 두고(post), 벽 · 바닥 색은 바꾸지 않습니다.
--   Homes.find() -> { { model, room, spec } }       Homes.rooms(model) -> { spec ... }       Homes.post(V, model)

local CollectionService = game:GetService("CollectionService")

local Homes = {}

local function laabb(cf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local ex = math.abs(cf.XVector.X) * h.X + math.abs(cf.YVector.X) * h.Y + math.abs(cf.ZVector.X) * h.Z
	local ey = math.abs(cf.XVector.Y) * h.X + math.abs(cf.YVector.Y) * h.Y + math.abs(cf.ZVector.Y) * h.Z
	local ez = math.abs(cf.XVector.Z) * h.X + math.abs(cf.YVector.Z) * h.Y + math.abs(cf.ZVector.Z) * h.Z
	local p = cf.Position
	return Vector3.new(p.X - ex, p.Y - ey, p.Z - ez), Vector3.new(p.X + ex, p.Y + ey, p.Z + ez)
end

local ROOM_OF = { FloorEntry = "entry", FloorBath = "bath" }

function Homes.isUnit(m: Instance): boolean
	return m:IsA("Model") and m:GetAttribute("Tier") ~= nil and m:FindFirstChild("Shell") ~= nil and m:FindFirstChild("UnitRoot") ~= nil
end

-- 방 spec 목록
function Homes.rooms(model: Model): { any }
	local root = model:FindFirstChild("UnitRoot") :: BasePart?
	local shell = model:FindFirstChild("Shell")
	if not root or not shell then
		return {}
	end
	local base = CFrame.new(root.Position) * root.CFrame.Rotation
	local boxes: { [string]: { any } } = {}
	local ceilY = -math.huge
	for _, p in shell:GetDescendants() do
		if p:IsA("BasePart") then
			local room = p:GetAttribute("Room") :: string?
			local surface = p:GetAttribute("Surface")
			local nm = p.Name
			if nm == "Ceiling" then
				local mn = laabb(base:ToObjectSpace(p.CFrame), p.Size)
				ceilY = math.max(ceilY, mn.Y)
			end
			local isFloor = surface == "floor" or ROOM_OF[nm] ~= nil or string.sub(nm, 1, 5) == "Floor"
			if isFloor then
				local r = room or ROOM_OF[nm] or "main"
				local mn, mx = laabb(base:ToObjectSpace(p.CFrame), p.Size)
				local b = boxes[r]
				if not b then
					boxes[r] = { mn, mx }
				else
					b[1] = b[1]:Min(mn)
					b[2] = b[2]:Max(mx)
				end
			end
		end
	end
	-- 문 위치 (방 프레임의 +Z 를 문 쪽으로)
	local doors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and (d.Name == "Door" or string.sub(d.Name, 1, 5) == "Door_") then
			local cf = d:GetBoundingBox()
			table.insert(doors, base:PointToObjectSpace(cf.Position))
		end
	end
	local out = {}
	for room, b in boxes do
		local mn, mx = b[1], b[2]
		local floorY = mx.Y
		local top = if ceilY > floorY then ceilY else floorY + 8.5
		local c = Vector3.new((mn.X + mx.X) / 2, floorY, (mn.Z + mx.Z) / 2)
		local sx, sz = mx.X - mn.X, mx.Z - mn.Z
		-- 가장 가까운 문 쪽 방향
		local best, bd = nil, math.huge
		for _, dp in doors do
			local cx = math.clamp(dp.X, mn.X, mx.X)
			local cz = math.clamp(dp.Z, mn.Z, mx.Z)
			local d = Vector3.new(dp.X - cx, 0, dp.Z - cz).Magnitude
			if d < bd then
				best, bd = dp, d
			end
		end
		local dir = Vector3.new(0, 0, 1)
		if best and bd < 4 then
			local dx = (best.X - c.X) / math.max(0.1, sx / 2)
			local dz = (best.Z - c.Z) / math.max(0.1, sz / 2)
			if math.abs(dx) > math.abs(dz) then
				dir = Vector3.new(math.sign(dx), 0, 0)
			else
				dir = Vector3.new(0, 0, if dz == 0 then 1 else math.sign(dz))
			end
		end
		local alongX = math.abs(dir.X) > 0.5
		local W = if alongX then sz else sx
		local D = if alongX then sx else sz
		local wc = base * CFrame.new(c)
		local cf = CFrame.lookAt(wc.Position, wc.Position - base:VectorToWorldSpace(dir))
		local spec: any = {
			cf = cf,
			size = Vector3.new(W, top - floorY, D),
			type = "home",
			room = room,
			kind = "home",
			name = (model:GetAttribute("DisplayName") :: any) or model.Name,
			key = string.format("%s#%s@%d,%d,%d", model.Name, room, math.floor(wc.X + 0.5), math.floor(wc.Y + 0.5), math.floor(wc.Z + 0.5)),
			noDoorGuess = true,
			margin = 0.4,
			tier = model:GetAttribute("Tier"),
		}
		table.insert(out, spec)
	end
	table.sort(out, function(a, b)
		return a.room < b.room
	end)
	return out
end

-- 가구 슬롯 자리 · 집 상호작용 파트 둘레 · 커튼 자리는 비움 (플레이어가 고른 가구가 들어가는 곳)
function Homes.post(V: any, model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and (CollectionService:HasTag(d, "FurnitureSlot") or string.sub(d.Name, 1, 5) == "Slot_") then
			local cf, s = d:GetBoundingBox()
			local fp = d:GetAttribute("Footprint")
			local size = if typeof(fp) == "Vector3" then (fp :: Vector3):Max(s) else s
			local lc = V.cf:ToObjectSpace(cf)
			local mn, mx = laabb(lc, size + Vector3.new(0.4, 0.2, 0.4))
			V:addKeep(Vector3.new(mn.X, 0.05, mn.Z), Vector3.new(mx.X, math.max(mx.Y, 0.3), mx.Z), "slot")
		elseif d:IsA("BasePart") and (CollectionService:HasTag(d, "HomeInteract") or string.sub(d.Name, 1, 9) == "Interact_") then
			local lc = V.cf:ToObjectSpace(d.CFrame)
			local mn, mx = laabb(lc, d.Size + Vector3.new(0.6, 0.4, 0.6))
			V:addKeep(mn, mx, "point")
		elseif d:IsA("Model") and (CollectionService:HasTag(d, "GwDecorItem") or (d.Parent and d.Parent.Name == "DecorPlus")) then
			-- 인테리어 모드(GwangalliDecorPlus)로 플레이어가 직접 놓은 가구
			local cf, s = d:GetBoundingBox()
			local mn, mx = laabb(V.cf:ToObjectSpace(cf), s + Vector3.new(0.4, 0.2, 0.4))
			V:addKeep(mn, mx, "slot")
		end
	end
	-- 플레이어가 자유 배치로 꾸미는 집: 가구 · 소품은 플레이어 몫이라 바닥 위 소품은 만들지 않음 (천장 · 벽 마감만)
	local dp = model:FindFirstChild("DecorPlus")
	if dp and #dp:GetChildren() > 0 then
		V.decorPlus = true
	end
end

function Homes.find(): { any }
	local out = {}
	local root = workspace:FindFirstChild("GwangalliHomeInstances")
	if not root then
		return out
	end
	-- 집 모델은 루트 바로 아래나 플레이어별 폴더 아래 (깊이 3 까지만 봄: 집 안의 수천 파트는 훑지 않음)
	local function visit(node: Instance, depth: number)
		for _, d in node:GetChildren() do
			if Homes.isUnit(d) then
				for _, spec in Homes.rooms(d :: Model) do
					table.insert(out, { model = d, room = spec.room, spec = spec })
				end
			elseif depth < 3 and (d:IsA("Folder") or d:IsA("Model")) then
				visit(d, depth + 1)
			end
		end
	end
	visit(root, 1)
	return out
end

return Homes
