--!strict
-- SeoulSkylineClient / ParkedCars — 주차장 칸을 실측 차량으로 채움 (클라이언트 전용, 복제 비용 0, 결정적)
--
--   * 맵 루트의 각 구역 모델 아래 "Parking" 그룹(예: Park.Parking)에서 주차선 파트(StallLine)를 찾아
--     같은 줄(선 방향 위치가 같은 선)끼리 묶고, 이웃한 선 사이(2.0~3.4 m)를 주차 칸으로 봄.
--   * 칸마다 위치 해시로 점유(≈ 78 %)·차종(승용 위주, 택시·1톤 일부)·색·번호판·방향(후면 주차 65 % — 한국식)·
--     좌우 0.12 m / 각도 ±2.5° 흔들림을 결정 → 모든 클라이언트가 같은 주차장을 봄.
--   * 대부분 소등, 일부(≈ 8 %)는 막 도착/출발하는 차처럼 등화 켜짐(밤이면 전조등·후미등).
--   * 서버가 깔아 둔 단순 박스 차(CarBody/CarCabin)는 로컬에서만 숨김(정지 시 원래대로).
--   * 스트리밍으로 주차선이 늦게 오면 1 초 뒤 다시 채움. 루트 속성 ParkedCars = false 면 끔,
--     ParkedCarBudget(기본 80, 모바일 40)으로 최대 대수 제한. 모바일은 lite 모델.

local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Util = require(script.Parent.Util)
local Vehicles = require(script.Parent.Vehicles)

local ParkedCars = {}

local function M(x: number): number
	return x / Util.METERS_PER_STUD
end

type Stall = { pos: Vector3, axis: Vector3, aisle: number, depth: number }
type Parked = { inst: Vehicles.Inst, lit: boolean }
type Line = { c: Vector3, a: Vector3, len: number, bottom: number }

-- 주차선 → 주차 칸
local function stallsOf(lines: { BasePart }): { Stall }
	local rows: { [string]: { Line } } = {}
	local centroid = Vector3.zero
	for _, p in lines do
		local sz = p.Size
		local cf = p.CFrame
		local a = if sz.Z >= sz.X then cf.LookVector else cf.RightVector
		a = Vector3.new(a.X, 0, a.Z)
		if a.Magnitude < 0.5 then
			continue
		end
		a = a.Unit
		if a.X + a.Z * 0.001 < 0 then
			a = -a
		end
		local c = p.Position
		local line: Line = { c = c, a = a, len = math.max(sz.X, sz.Z), bottom = c.Y - sz.Y / 2 }
		local key = string.format("%d:%d:%d", math.floor(a.X * 20 + 0.5), math.floor(a.Z * 20 + 0.5), math.floor(c:Dot(a) / 2 + 0.5))
		rows[key] = rows[key] or {}
		table.insert(rows[key], line)
		centroid += c
	end
	if #lines > 0 then
		centroid /= #lines
	end
	local out: { Stall } = {}
	for _, row in rows do
		local a = row[1].a
		local perp = Vector3.new(-a.Z, 0, a.X)
		table.sort(row, function(x, y)
			return x.c:Dot(perp) < y.c:Dot(perp)
		end)
		local rowC = row[1].c
		local aisle = if (centroid - rowC):Dot(a) >= 0 then 1 else -1
		for i = 1, #row - 1 do
			local l1, l2 = row[i], row[i + 1]
			local gap = l2.c:Dot(perp) - l1.c:Dot(perp)
			if gap > M(2.0) and gap < M(3.4) then
				local c = (l1.c + l2.c) / 2
				table.insert(out, {
					pos = Vector3.new(c.X, math.max(l1.bottom, l2.bottom), c.Z),
					axis = a,
					aisle = aisle,
					depth = math.min(l1.len, l2.len),
				})
			end
		end
	end
	table.sort(out, function(x, y)
		if math.abs(x.pos.Z - y.pos.Z) > 1 then
			return x.pos.Z < y.pos.Z
		end
		return x.pos.X < y.pos.X
	end)
	return out
end

function ParkedCars.start(root: Model): () -> ()
	if root:GetAttribute("ParkedCars") == false then
		return function() end
	end
	local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local budgetAttr = root:GetAttribute("ParkedCarBudget")
	local budget = if typeof(budgetAttr) == "number" then budgetAttr else 80
	if mobile then
		budget = math.floor(budget / 2)
	end

	local folder = Instance.new("Folder")
	folder.Name = "SeoulSkylineParkedCars"
	folder.Parent = workspace
	local alive = true
	local conns: { RBXScriptConnection } = {}
	local lotConns: { RBXScriptConnection } = {}
	local hidden: { [BasePart]: { t: number, s: boolean } } = {}
	local parked: { Parked } = {}
	local night = false
	local pending = false

	local function isNight(): boolean
		local forced = root:GetAttribute("Night")
		if typeof(forced) == "boolean" then
			return forced
		end
		local ct = Lighting.ClockTime
		return ct >= 17.6 or ct < 6.4
	end

	local function hideServerCar(p: BasePart)
		if hidden[p] then
			return
		end
		hidden[p] = { t = p.Transparency, s = p.CastShadow }
		p.Transparency = 1
		p.CastShadow = false
	end

	local function lots(): { Instance }
		local out: { Instance } = {}
		for _, zone in root:GetChildren() do
			local lot = zone:FindFirstChild("Parking")
			if lot then
				table.insert(out, lot)
			end
		end
		return out
	end

	local function fill()
		pending = false
		if not alive then
			return
		end
		for _, pc in parked do
			pc.inst.model:Destroy()
		end
		table.clear(parked)
		Util.disconnectAll(lotConns)
		night = isNight()
		local count = 0
		for _, lot in lots() do
			local lines: { BasePart } = {}
			for _, d in lot:GetDescendants() do
				if d:IsA("BasePart") then
					if d.Name == "StallLine" then
						table.insert(lines, d)
					elseif d.Name == "CarBody" or d.Name == "CarCabin" then
						hideServerCar(d)
					end
				end
			end
			table.insert(lotConns, lot.DescendantAdded:Connect(function(d)
				if d:IsA("BasePart") and (d.Name == "StallLine" or d.Name == "CarBody" or d.Name == "CarCabin") and not pending then
					pending = true
					task.delay(1, fill)
				end
			end))
			for _, st in stallsOf(lines) do
				if count >= budget then
					break
				end
				local key = string.format("P%d,%d", math.floor(st.pos.X * 10 + 0.5), math.floor(st.pos.Z * 10 + 0.5))
				local h = Util.hash(key)
				if (h % 1000) / 1000 >= 0.78 then
					continue -- 빈칸
				end
				local typ = Vehicles.pickParked(((h // 1000) % 1000) / 1000)
				local inf = Vehicles.Info[typ]
				local backIn = ((h // 1000000) % 100) < 65
				-- 차 앞이 향하는 방향: 후면 주차면 통로 쪽, 전면 주차면 반대쪽
				local fwd = st.axis * (if backIn then st.aisle else -st.aisle)
				local jy = math.rad((((h // 7) % 1000) / 1000 - 0.5) * 5)
				local jx = ((((h // 13) % 1000) / 1000) - 0.5) * M(0.24)
				local perp = Vector3.new(-st.axis.Z, 0, st.axis.X)
				-- 차 중심을 칸 중심에(통로 쪽으로 0.2 m), 원점(차축 중간)은 중심에서 (rear-front)/2 만큼 앞
				local center = st.pos + perp * jx + st.axis * (st.aisle * M(0.2))
				local origin = center + fwd * ((inf.rear - inf.front) / 2)
				local cf = CFrame.lookAt(origin, origin + fwd) * CFrame.Angles(0, jy, 0)
				local inst = Vehicles.new(typ, mobile, nil)
				Vehicles.dress(inst, h)
				local lit = ((h // 31) % 100) < 8
				Vehicles.setLights(inst, night, false, lit)
				inst.model:PivotTo(cf)
				inst.model.Parent = folder
				table.insert(parked, { inst = inst, lit = lit })
				count += 1
			end
		end
		if root:GetAttribute("ClientDebug") == true then
			print(string.format("[SeoulSkylineClient] parked cars=%d hidden=%d", count, (function()
				local n = 0
				for _ in hidden do
					n += 1
				end
				return n
			end)()))
		end
	end

	local function schedule()
		if not pending then
			pending = true
			task.delay(1, fill)
		end
	end

	table.insert(conns, root.ChildAdded:Connect(function(c)
		if c:FindFirstChild("Parking") then
			schedule()
		else
			-- 구역 모델이 먼저 오고 Parking 이 나중에 스트리밍될 수 있음
			table.insert(conns, c.ChildAdded:Connect(function(cc)
				if cc.Name == "Parking" then
					schedule()
				end
			end))
		end
	end))
	for _, zone in root:GetChildren() do
		if not zone:FindFirstChild("Parking") then
			table.insert(conns, zone.ChildAdded:Connect(function(cc)
				if cc.Name == "Parking" then
					schedule()
				end
			end))
		end
	end
	fill()

	-- 낮/밤 전환 시 켜진 차의 등화 갱신
	task.spawn(function()
		while alive do
			task.wait(2)
			if not alive then
				break
			end
			local n = isNight()
			if n ~= night then
				night = n
				for _, pc in parked do
					Vehicles.setLights(pc.inst, night, false, pc.lit)
				end
			end
		end
	end)

	return function()
		alive = false
		Util.disconnectAll(conns)
		Util.disconnectAll(lotConns)
		for p, o in hidden do
			if p.Parent then
				p.Transparency = o.t
				p.CastShadow = o.s
			end
		end
		table.clear(hidden)
		table.clear(parked)
		folder:Destroy()
	end
end

return ParkedCars
