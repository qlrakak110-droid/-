--!strict
-- GwangalliCarInterior/Fit: 기존 차 모델(build/kit/vehicles 규약)의 Interior 파트에서 실내 치수를 읽습니다.
-- 이름 우선 (WheelRim / WheelHub / Dash / DashTop / ClusterScreen / NavScreen / CentreConsole / SeatCushion /
-- SeatBack / Headrest / DoorTrim / Headliner / Carpet / Firewall / Pedal / RearViewMirror / SunVisor + 차체의
-- Windshield / BPillar), 없는 값은 차 크기에서 추정. 결과는 전부 차체(Underbody) 프레임 기준.
-- 읽기만 합니다 (아무것도 바꾸지 않음).

local Fit = {}

-- seat = { cush, cushSize, back?, backSize?, head?, x, z, y, w } (차체 기준)

local function localBox(U: CFrame, p: BasePart): (CFrame, Vector3)
	return U:ToObjectSpace(p.CFrame), p.Size
end

local function frameOf(model: Model): BasePart?
	local u = model:FindFirstChild("Underbody", true)
	if u and u:IsA("BasePart") then
		return u
	end
	local c = model:FindFirstChild("Chassis", true)
	if c and c:IsA("BasePart") then
		return c
	end
	return nil
end
Fit.frameOf = frameOf

local function avg(list: { Vector3 }): Vector3
	local s = Vector3.zero
	for _, v in list do
		s += v
	end
	return s / math.max(1, #list)
end

function Fit.run(model: Model): (any?, string?)
	local base = frameOf(model)
	if not base then
		return nil, "no Underbody/Chassis"
	end
	local interior = model:FindFirstChild("Interior")
	if not interior then
		return nil, "no Interior"
	end
	local U = base.CFrame
	local by: { [string]: { BasePart } } = {}
	for _, d in interior:GetDescendants() do
		if d:IsA("BasePart") then
			local t = by[d.Name]
			if not t then
				t = {}
				by[d.Name] = t
			end
			table.insert(t, d)
		end
	end
	local body: { [string]: { BasePart } } = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			local t = body[d.Name]
			if not t then
				t = {}
				body[d.Name] = t
			end
			table.insert(t, d)
		end
	end
	local function first(names: { string }, src: { [string]: { BasePart } }?): BasePart?
		for _, n in names do
			local t = (src or by)[n]
			if t and t[1] then
				return t[1]
			end
		end
		return nil
	end
	local F: any = { model = model, base = base, kind = model:GetAttribute("VehicleKind") or "sedan", interior = interior }

	-- 1) 핸들 -------------------------------------------------------------------------------------
	local rims = by.WheelRim or {}
	local hub = first({ "WheelHub" })
	if #rims < 3 and not hub then
		return nil, "no steering wheel anchors"
	end
	local pts = {}
	for _, r in rims do
		table.insert(pts, U:PointToObjectSpace(r.Position))
	end
	local c = if #pts > 0 then avg(pts) else U:PointToObjectSpace((hub :: BasePart).Position)
	local up, axis
	if #pts >= 6 then
		-- 림 조각 중 가장 높은 것 - 가장 낮은 것 = 핸들 평면의 위쪽
		local hi, lo = pts[1], pts[1]
		local left, right = pts[1], pts[1]
		for _, p in pts do
			if p.Y > hi.Y then
				hi = p
			end
			if p.Y < lo.Y then
				lo = p
			end
			if p.X < left.X then
				left = p
			end
			if p.X > right.X then
				right = p
			end
		end
		-- 같은 높이의 조각이 둘씩 있으니 평균
		local function meanNear(sel: Vector3, key: string): Vector3
			local acc = {}
			for _, p in pts do
				if math.abs((p :: any)[key] - (sel :: any)[key]) < 0.06 then
					table.insert(acc, p)
				end
			end
			return avg(acc)
		end
		hi, lo = meanNear(hi, "Y"), meanNear(lo, "Y")
		left, right = meanNear(left, "X"), meanNear(right, "X")
		up = (hi - lo).Unit
		local rx = (right - left).Unit
		axis = rx:Cross(up).Unit -- 운전자 쪽 (+Z 쪽)
		if axis.Z < 0 then
			axis = -axis
		end
	elseif hub then
		local hcf = U:ToObjectSpace(hub.CFrame)
		axis = hcf.LookVector
		if axis.Z < 0 then
			axis = -axis
		end
		up = hcf.UpVector
	else
		axis, up = Vector3.new(0, 0.4, 0.92).Unit, Vector3.new(0, 0.92, -0.4).Unit
	end
	local right = up:Cross(axis).Unit
	up = axis:Cross(right).Unit
	local R = 0.6
	if #pts >= 6 then
		local sum = 0
		for _, p in pts do
			sum += (p - c).Magnitude
		end
		R = (sum / #pts) / math.cos(math.pi / 8) -- 팔각형 조각 중심 -> 꼭짓점 반지름
	end
	F.wheel = { c = c, R = math.clamp(R, 0.45, 0.8), cf = CFrame.fromMatrix(c, right, up, axis) }
	-- 원래 허브 · 배지 · 스포크가 핸들 면에서 운전자 쪽(+Z)으로 얼마나 나와 있는지: 새 패드 · 스포크를 그 바로 앞에 둠
	-- (숨긴 원래 파트가 새 핸들을 뚫고 보이지 않게)
	local wcf: CFrame = F.wheel.cf
	local function frontOf(names: { string }): number?
		local zmax: number? = nil
		for _, n in names do
			for _, p in by[n] or {} do
				local lc = wcf:ToObjectSpace(U:ToObjectSpace(p.CFrame))
				if Vector2.new(lc.Position.X, lc.Position.Y).Magnitude < F.wheel.R + 0.1 and math.abs(lc.Position.Z) < 0.5 then
					local h = p.Size / 2
					for _, sx in { -1, 1 } do
						for _, sy in { -1, 1 } do
							for _, sz in { -1, 1 } do
								local z = (lc * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)).Z
								zmax = if zmax then math.max(zmax, z) else z
							end
						end
					end
				end
			end
		end
		return zmax
	end
	F.wheel.hubFront = frontOf({ "WheelBadge", "WheelHub", "HornPad" })
	F.wheel.spokeFront = frontOf({ "WheelSpoke" })
	-- 원래 가로 스포크 막대 (높이 · 두께): 새 좌우 스포크가 같은 높이로 덮게
	for _, p in by.WheelSpoke or {} do
		local lc = wcf:ToObjectSpace(U:ToObjectSpace(p.CFrame))
		if math.abs(lc.RightVector.X) > 0.95 and p.Size.X > 0.6 and (not F.wheel.spokeBar or p.Size.X > F.wheel.spokeBar.len) then
			F.wheel.spokeBar = { y = lc.Position.Y, h = p.Size.Y, len = p.Size.X }
		end
	end
	F.side = if c.X < 0 then -1 else 1 -- 운전석 쪽 (좌핸들 = -X)

	-- 2) 실내 폭 / 바닥 / 천장 -------------------------------------------------------------------------
	local trims = by.DoorTrim or {}
	local halfIn = 2.5
	if #trims > 0 then
		local s = 0
		for _, t in trims do
			local lc, sz = localBox(U, t)
			s += math.abs(lc.Position.X) - sz.X / 2
		end
		halfIn = s / #trims
	end
	if #trims == 0 then
		-- 도어 트림이 없는 차(솔라티 등): 대시 / 바닥 폭으로
		local dsh = first({ "Dash", "DashUpper", "DashLower" })
		local flr = first({ "Carpet", "CabCarpet", "Floor" })
		halfIn = (dsh and dsh.Size.X / 2 - 0.02) or (flr and flr.Size.X / 2 - 0.02) or 2.5
	end
	F.halfIn = halfIn
	local carpet = first({ "Carpet", "CabCarpet", "Floor" })
	F.floorY = if carpet then U:PointToObjectSpace(carpet.Position).Y + carpet.Size.Y / 2 else c.Y - 1.9
	local liner = first({ "Headliner", "Ceiling" })
	if liner then
		local lc, sz = localBox(U, liner)
		F.roofY = lc.Position.Y - sz.Y / 2
		F.linerZ0, F.linerZ1 = lc.Position.Z - sz.Z / 2, lc.Position.Z + sz.Z / 2
		F.linerHalf = sz.X / 2
	else
		F.roofY = c.Y + 1.6
	end
	local doorZ0, doorZ1 = c.Z - 1.2, c.Z + 5
	if #trims > 0 then
		-- 문마다 DoorTrim 이 따로 있으면 전체 범위로
		doorZ0, doorZ1 = math.huge, -math.huge
		for _, t in trims do
			local lc, sz = localBox(U, t)
			doorZ0 = math.min(doorZ0, lc.Position.Z - sz.Z / 2)
			doorZ1 = math.max(doorZ1, lc.Position.Z + sz.Z / 2)
		end
		local lc, sz = localBox(U, trims[1])
		F.trimY0, F.trimY1 = lc.Position.Y - sz.Y / 2, lc.Position.Y + sz.Y / 2
	end
	if #trims == 0 then
		local pt = first({ "Partition" })
		if pt then
			doorZ1 = math.min(doorZ1, U:PointToObjectSpace(pt.Position).Z - pt.Size.Z / 2 - 0.05)
		end
		-- 도어 트림 파트가 없는 밴(쏠라티): 차체 CabDoor 위 끝(= 옆 유리 아래 끝)까지 문 안쪽을 덮음
		local cd = first({ "CabDoor" }, body)
		if cd then
			local lc, sz = localBox(U, cd)
			F.trimY0, F.trimY1 = F.floorY, lc.Position.Y + sz.Y / 2 - 0.04
		end
	end
	F.doorZ0, F.doorZ1 = doorZ0, doorZ1
	local bp = first({ "BPillar" }, body)
	F.bZ = if bp then U:PointToObjectSpace(bp.Position).Z else nil

	-- 3) 대시보드 / 앞유리 -------------------------------------------------------------------------------
	local dash = first({ "Dash", "DashUpper", "DashLower" })
	if dash then
		local lc, sz = localBox(U, dash)
		F.dashFace = lc.Position.Z + sz.Z / 2 -- 실내 쪽 면
		F.dashFront = lc.Position.Z - sz.Z / 2
		F.dashMidY = lc.Position.Y
		F.dashBottom = lc.Position.Y - sz.Y / 2
		F.dashW = sz.X
	else
		F.dashFace = c.Z - 0.65
		F.dashFront = c.Z - 1.9
		F.dashMidY = c.Y - 0.25
		F.dashBottom = c.Y - 0.75
		F.dashW = halfIn * 2
	end
	for _, n in { "DashLower" } do
		local p = first({ n })
		if p then
			local lc, sz = localBox(U, p)
			F.dashBottom = math.min(F.dashBottom, lc.Position.Y - sz.Y / 2)
		end
	end
	local top = first({ "DashTop" })
	if top then
		local lc, sz = localBox(U, top)
		F.dashTop = lc.Position.Y + sz.Y / 2
	else
		F.dashTop = (F.dashMidY :: number) + 0.55
	end
	local ws = first({ "Windshield" }, body)
	if ws then
		local lc, sz = localBox(U, ws)
		local e1 = lc * Vector3.new(0, 0, sz.Z / 2)
		local e2 = lc * Vector3.new(0, 0, -sz.Z / 2)
		if sz.Y > sz.Z then -- 세워진 앞유리 (트럭): Y 축이 길이
			e1 = lc * Vector3.new(0, sz.Y / 2, 0)
			e2 = lc * Vector3.new(0, -sz.Y / 2, 0)
		end
		local lo, hi = if e1.Y < e2.Y then e1 else e2, if e1.Y < e2.Y then e2 else e1
		F.wsLow, F.wsHigh, F.wsW = lo, hi, sz.X
	else
		F.wsLow = Vector3.new(0, F.dashTop, F.dashFront)
		F.wsHigh = Vector3.new(0, F.roofY, c.Z)
		F.wsW = F.dashW
	end

	-- 4) 화면 / 콘솔 ----------------------------------------------------------------------------------
	local cl = first({ "ClusterScreen", "Gauges" })
	F.cluster = if cl then U:PointToObjectSpace(cl.Position) else Vector3.new(c.X, F.dashTop + 0.12, F.dashFace + 0.2)
	local nav = first({ "NavScreen", "FloatingScreen", "Screen", "TabletScreen" })
	F.nav = if nav then U:PointToObjectSpace(nav.Position) else Vector3.new(0, F.cluster.Y, F.cluster.Z + 0.1)
	F.navWide = nav and nav.Size.X or 1.3
	local con = first({ "CentreConsole", "FloorConsole" })
	if con then
		local lc, sz = localBox(U, con)
		F.console = { x = lc.Position.X, z0 = lc.Position.Z - sz.Z / 2, z1 = lc.Position.Z + sz.Z / 2, top = lc.Position.Y + sz.Y / 2, w = sz.X }
	end
	local arm = first({ "ConsoleArmrest" })
	if arm then
		local lc, sz = localBox(U, arm)
		F.consoleArm = { z0 = lc.Position.Z - sz.Z / 2, z1 = lc.Position.Z + sz.Z / 2, top = lc.Position.Y + sz.Y / 2, w = sz.X }
	end
	F.wood = by.WoodBand ~= nil or by.ConsoleWood ~= nil
	F.rotary = by.GearDial ~= nil or by.RotaryShifter ~= nil
	F.lever = by.GearLever ~= nil or by.GearKnob ~= nil
	F.taxi = by.TaxiMeter ~= nil

	-- 5) 좌석 ------------------------------------------------------------------------------------------
	local cush = by.SeatCushion or {}
	local backs = by.SeatBack or {}
	local heads = by.Headrest or {}
	local seats: { any } = {}
	for _, s in cush do
		local lc, sz = localBox(U, s)
		local p = lc.Position
		local rec: any = { cush = p, cushSize = sz, x = p.X, z = p.Z, y = p.Y, w = sz.X }
		-- 같은 x 근처의 등받이 / 헤드레스트
		local bestB, bd = nil, math.huge
		for _, b in backs do
			local bl = U:PointToObjectSpace(b.Position)
			local dd = math.abs(bl.X - p.X) + math.abs(bl.Z - p.Z) * 0.3
			if bl.Z > p.Z - 0.2 and dd < bd then
				bd, bestB = dd, b
			end
		end
		if bestB then
			local bl, bs = localBox(U, bestB)
			rec.back, rec.backSize = bl.Position, bs
		end
		local bestH, hd = nil, math.huge
		for _, h in heads do
			local hl = U:PointToObjectSpace(h.Position)
			local dd = math.abs(hl.X - p.X) + math.abs(hl.Z - p.Z) * 0.3
			if hl.Z > p.Z and dd < hd then
				hd, bestH = dd, hl
			end
		end
		rec.head = bestH
		table.insert(seats, rec)
	end
	table.sort(seats, function(a, b)
		return a.z < b.z
	end)
	local front, rear = {}, {}
	if #seats > 0 then
		local z0 = seats[1].z
		for _, s in seats do
			if s.z < z0 + 1.0 then
				table.insert(front, s)
			else
				table.insert(rear, s)
			end
		end
	end
	F.front, F.rear = front, rear
	-- 뒷좌석 헤드레스트 위치 (벤치는 하나로 되어 있음)
	F.rearHeads = {}
	for _, h in heads do
		local hl = U:PointToObjectSpace(h.Position)
		if #front > 0 and hl.Z > front[1].z + 2.2 then
			table.insert(F.rearHeads, hl)
		end
	end

	-- 6) 기타 -----------------------------------------------------------------------------------------
	F.pedals = {}
	for _, p in by.Pedal or {} do
		table.insert(F.pedals, U:PointToObjectSpace(p.Position))
	end
	local mir = first({ "RearViewMirror" })
	F.mirror = if mir then U:PointToObjectSpace(mir.Position) else nil
	local fw = first({ "Firewall" })
	F.firewallZ = if fw then U:PointToObjectSpace(fw.Position).Z else F.dashFront

	-- 7) 색 (차마다 원래 실내 색을 살림) --------------------------------------------------------------------
	local function colorOf(names: { string }, fallback: Color3): Color3
		local p = first(names)
		return if p then p.Color else fallback
	end
	F.colors = {
		seat = colorOf({ "SeatCushion", "SeatBack" }, Color3.fromRGB(30, 30, 32)),
		dash = colorOf({ "DashUpper", "Dash" }, Color3.fromRGB(26, 26, 28)),
		trim = colorOf({ "DoorTrim" }, Color3.fromRGB(30, 30, 32)),
		liner = colorOf({ "Headliner", "Ceiling" }, Color3.fromRGB(150, 150, 152)),
		accent = colorOf({ "AmbientStrip", "AmbientDoor" }, Color3.fromRGB(110, 170, 255)),
		wood = colorOf({ "WoodBand", "ConsoleWood" }, Color3.fromRGB(70, 50, 38)),
	}
	F.seatFabric = (by.SeatCushion and by.SeatCushion[1] and by.SeatCushion[1].Material == Enum.Material.Fabric) or false
	-- 구급차: Headliner 없이 격벽 뒤 환자실 Ceiling 만 있음 -> 운전석 천장 = 차체 CabHeader 아랫면
	if F.linerZ0 and F.linerZ0 > F.doorZ1 - 0.2 then
		local hd = first({ "CabHeader" }, body)
		if hd then
			local lc, sz = localBox(U, hd)
			local wl: Vector3, wh: Vector3 = F.wsLow, F.wsHigh
			F.roofY = lc.Position.Y - sz.Y / 2
			-- 앞유리가 천장 높이와 만나는 z
			local zWs = wl.Z + (F.roofY - wl.Y) * (wh.Z - wl.Z) / math.max(0.01, wh.Y - wl.Y)
			F.linerZ0, F.linerZ1 = math.max(zWs, lc.Position.Z - sz.Z / 2), F.doorZ1
			F.cabRoof = true -- 운전석 칸만 덮는 짧은 천장 (뒷좌석 손잡이 없음, 오버헤드 콘솔은 룸미러 뒤)
		end
	end
	return F, nil
end

-- 디버그용 요약 (스크립트 속성 Debug = true 일 때 차 모델의 GwCabinFit 속성으로)
function Fit.summary(F: any): string
	local function v(p: Vector3?): string
		return if p then string.format("(%.2f,%.2f,%.2f)", p.X, p.Y, p.Z) else "nil"
	end
	local t = {
		string.format("half=%.2f floor=%.2f roof=%.2f side=%d", F.halfIn, F.floorY, F.roofY, F.side),
		string.format("dash face=%.2f front=%.2f top=%.2f mid=%.2f bot=%.2f w=%.2f", F.dashFace, F.dashFront, F.dashTop, F.dashMidY, F.dashBottom, F.dashW),
		"ws=" .. v(F.wsLow) .. v(F.wsHigh) .. string.format(" wsW=%.2f", F.wsW or 0),
		"wheel=" .. v(F.wheel.c) .. string.format(" R=%.2f", F.wheel.R) .. " axis=" .. v(F.wheel.cf.LookVector),
		"cluster=" .. v(F.cluster) .. " nav=" .. v(F.nav) .. string.format(" navW=%.2f", F.navWide),
		if F.console then string.format("console x=%.2f z=%.2f..%.2f top=%.2f w=%.2f", F.console.x, F.console.z0, F.console.z1, F.console.top, F.console.w) else "console=nil",
		if F.consoleArm then string.format("arm z=%.2f..%.2f top=%.2f w=%.2f", F.consoleArm.z0, F.consoleArm.z1, F.consoleArm.top, F.consoleArm.w) else "arm=nil",
		string.format("door z=%.2f..%.2f bZ=%s trimY=%s..%s liner=%s..%s lh=%s", F.doorZ0, F.doorZ1, tostring(F.bZ), tostring(F.trimY0), tostring(F.trimY1), tostring(F.linerZ0), tostring(F.linerZ1), tostring(F.linerHalf)),
	}
	for _, s in F.front do
		table.insert(t, string.format("front x=%.2f z=%.2f w=%.2f cush=%s size=%s", s.x, s.z, s.w, v(s.cush), v(s.cushSize)))
	end
	for _, s in F.rear do
		table.insert(t, string.format("rear x=%.2f z=%.2f w=%.2f cush=%s size=%s", s.x, s.z, s.w, v(s.cush), v(s.cushSize)))
	end
	table.insert(t, string.format("pedals=%d mirror=%s fw=%.2f wood=%s rotary=%s lever=%s taxi=%s", #F.pedals, v(F.mirror), F.firewallZ, tostring(F.wood), tostring(F.rotary), tostring(F.lever), tostring(F.taxi)))
	return table.concat(t, "\n")
end

return Fit
