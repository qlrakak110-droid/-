--[[
	📁 위치: ServerScriptService  >  ModuleScript  (이름: CityBuilder)
	도로(격자), 차선, 인도, 건물, 가로등, 나무, 주차장, 주유소, 자동차 매장, 정비소를 자동 생성합니다.
	※ 기존 Baseplate 는 자동으로 지워집니다 (도로랑 겹쳐서 깜빡이는 것 방지).
]]

local Lighting = game:GetService("Lighting")

local CityBuilder = {}

local function mk(class, parent, props)
	local p = Instance.new(class)
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "Shape" then
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function deco(parent, props)
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	return mk("Part", parent, props)
end

local function marker(parent, pos, text, color)
	local p = mk("Part", parent, { Name = "Marker", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos + Vector3.new(0, 45, 0)), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 220, 0, 56)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 2500
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = color
	t.BackgroundTransparency = 0.15
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = t
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = Color3.new(1, 1, 1)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = t
	t.Parent = bb
	bb.Parent = p
	return p
end

local function zone(parent, name, cf, size, attrs)
	local z = mk("Part", parent, { Name = name, CFrame = cf, Size = size, Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	if attrs then
		for k, v in pairs(attrs) do
			z:SetAttribute(k, v)
		end
	end
	return z
end

function CityBuilder.Build(Config)
 if Config.GW_INTEGRATED and workspace:FindFirstChild("Gwangalli") then
  return { integrated = true, map = workspace.Gwangalli,
   navigation = game:GetService("ReplicatedStorage"):FindFirstChild("GwangalliNav") }
 end
	local N, S, RW, LANE = Config.CITY_N, Config.CITY_S, Config.ROAD_W, Config.LANE
	local city = { N = N, S = S, RW = RW, LANE = LANE, roadY = 0.2 }
	local function X(i)
		return (i - N / 2) * S
	end
	city.X = X
	function city.nodePos(i, j)
		return Vector3.new(X(i), city.roadY, X(j))
	end
	function city.blockCenter(bx, bz)
		return Vector3.new((X(bx) + X(bx + 1)) / 2, 0.4, (X(bz) + X(bz + 1)) / 2)
	end

	local old = workspace:FindFirstChild("Baseplate")
	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "City"
	folder.Parent = workspace
	local zones = Instance.new("Folder")
	zones.Name = "CityZones"
	zones.Parent = workspace

	------------------------------------------------ 조명 (고퀄 느낌)
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.6
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 135)
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local a = Instance.new("Atmosphere")
		a.Density = 0.3
		a.Haze = 1.2
		a.Color = Color3.fromRGB(200, 215, 235)
		a.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local b = Instance.new("BloomEffect")
		b.Intensity = 0.6
		b.Size = 28
		b.Threshold = 1.6
		b.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Saturation = 0.12
		cc.Contrast = 0.08
		cc.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("SunRaysEffect") then
		local sr = Instance.new("SunRaysEffect")
		sr.Intensity = 0.06
		sr.Parent = Lighting
	end

	------------------------------------------------ 지면 + 도로
	local span = N * S
	mk("Part", folder, { Name = "Ground", Size = Vector3.new(span + 500, 2, span + 500), CFrame = CFrame.new(0, -1, 0), Material = Enum.Material.Grass, Color = Color3.fromRGB(86, 120, 64) })
	local asphalt = Color3.fromRGB(48, 48, 52)
	for j = 0, N do
		mk("Part", folder, { Name = "Road", Size = Vector3.new(span + RW, 0.2, RW), CFrame = CFrame.new(0, 0.1, X(j)), Material = Enum.Material.Asphalt, Color = asphalt })
	end
	for i = 0, N do
		for j = 0, N - 1 do
			mk("Part", folder, { Name = "Road", Size = Vector3.new(RW, 0.2, S - RW), CFrame = CFrame.new(X(i), 0.1, (X(j) + X(j + 1)) / 2), Material = Enum.Material.Asphalt, Color = asphalt })
		end
	end
	-- 차선
	local yellow = Color3.fromRGB(240, 190, 30)
	local white = Color3.fromRGB(235, 235, 235)
	local ly = 0.21
	for a = 0, N do
		for b = 0, N - 1 do
			local mid = (X(b) + X(b + 1)) / 2
			local len = S - RW - 2
			for _, off in ipairs({ -0.35, 0.35 }) do
				deco(folder, { Name = "Line", Size = Vector3.new(len, 0.02, 0.3), CFrame = CFrame.new(mid, ly, X(a) + off), Material = Enum.Material.SmoothPlastic, Color = yellow })
				deco(folder, { Name = "Line", Size = Vector3.new(0.3, 0.02, len), CFrame = CFrame.new(X(a) + off, ly, mid), Material = Enum.Material.SmoothPlastic, Color = yellow })
			end
			for _, off in ipairs({ -(RW / 2 - 1), RW / 2 - 1 }) do
				deco(folder, { Name = "Edge", Size = Vector3.new(len, 0.02, 0.3), CFrame = CFrame.new(mid, ly, X(a) + off), Material = Enum.Material.SmoothPlastic, Color = white })
				deco(folder, { Name = "Edge", Size = Vector3.new(0.3, 0.02, len), CFrame = CFrame.new(X(a) + off, ly, mid), Material = Enum.Material.SmoothPlastic, Color = white })
			end
			-- 횡단보도 + 정지선 (각 구간 양 끝)
			for _, e in ipairs({ { X(b) + RW / 2 + 3, 1 }, { X(b + 1) - RW / 2 - 3, -1 } }) do
				for k = -3, 3 do
					local o = k * 4.2
					deco(folder, { Name = "Cross", Size = Vector3.new(4, 0.02, 1.8), CFrame = CFrame.new(e[1] - e[2] * 1.5, ly, X(a) + o), Color = white })
					deco(folder, { Name = "Cross", Size = Vector3.new(1.8, 0.02, 4), CFrame = CFrame.new(X(a) + o, ly, e[1] - e[2] * 1.5), Color = white })
				end
			end
		end
	end

	------------------------------------------------ 블록
	local special = {
		["1,1"] = "parking", ["2,1"] = "gas", ["1,2"] = "dealer", ["2,2"] = "repair",
	}
	city.spaces, city.pumps, city.dealerSlots, city.pois = {}, {}, {}, {}
	local inner = (S - RW) / 2
	local usable = inner - 6
	local rng = Random.new(1234)
	local concrete = Color3.fromRGB(175, 175, 170)
	local paved = Color3.fromRGB(62, 62, 66)

	local function lot(c)
		mk("Part", folder, { Name = "Lot", Size = Vector3.new(usable * 2, 0.1, usable * 2), CFrame = CFrame.new(c.X, 0.42, c.Z), Material = Enum.Material.Asphalt, Color = paved })
	end

	for bx = 0, N - 1 do
		for bz = 0, N - 1 do
			local c = city.blockCenter(bx, bz)
			mk("Part", folder, { Name = "Sidewalk", Size = Vector3.new(S - RW, 0.4, S - RW), CFrame = CFrame.new(c.X, 0.2, c.Z), Material = Enum.Material.Pavement, Color = concrete })
			-- 가로등
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local p = Vector3.new(c.X + sx * (inner - 2), 0.4, c.Z + sz * (inner - 2))
					mk("Part", folder, { Name = "Pole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(22, 0.7, 0.7), CFrame = CFrame.new(p + Vector3.new(0, 11, 0)) * CFrame.Angles(0, 0, math.pi / 2), Material = Enum.Material.Metal, Color = Color3.fromRGB(60, 62, 66) })
					deco(folder, { Name = "Arm", Size = Vector3.new(0.4, 0.4, 5), CFrame = CFrame.new(p + Vector3.new(sx * 2, 21.8, 0)) * CFrame.Angles(0, math.pi / 2, 0), Material = Enum.Material.Metal, Color = Color3.fromRGB(60, 62, 66) })
					deco(folder, { Name = "Lamp", Size = Vector3.new(1.8, 0.35, 1), CFrame = CFrame.new(p + Vector3.new(sx * 4.2, 21.5, 0)), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 240, 210) })
				end
			end
			local kind = special[bx .. "," .. bz]
			if kind == nil then
				-- 나무
				for k = -1, 1, 2 do
					for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
						local p
						if side[1] ~= 0 then
							p = Vector3.new(c.X + side[1] * (inner - 3), 0.4, c.Z + k * 25)
						else
							p = Vector3.new(c.X + k * 25, 0.4, c.Z + side[2] * (inner - 3))
						end
						mk("Part", folder, { Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 1.2, 1.2), CFrame = CFrame.new(p + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), Material = Enum.Material.Wood, Color = Color3.fromRGB(90, 64, 40) })
						deco(folder, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), CFrame = CFrame.new(p + Vector3.new(0, 9, 0)), Material = Enum.Material.Grass, Color = Color3.fromRGB(60, 120, 55) })
						deco(folder, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), CFrame = CFrame.new(p + Vector3.new(1.5, 11.5, 1)), Material = Enum.Material.Grass, Color = Color3.fromRGB(75, 135, 60) })
					end
				end
				-- 건물 2x2
				for _, ox in ipairs({ -1, 1 }) do
					for _, oz in ipairs({ -1, 1 }) do
						local w = rng:NextNumber(34, 46)
						local d = rng:NextNumber(34, 46)
						local h = rng:NextInteger(3, 11) * 14
						local bc = Vector3.new(c.X + ox * usable / 2, 0.4, c.Z + oz * usable / 2)
						local tint = ({ Color3.fromRGB(90, 130, 170), Color3.fromRGB(70, 100, 120), Color3.fromRGB(120, 150, 160), Color3.fromRGB(60, 80, 110) })[rng:NextInteger(1, 4)]
						local frame = ({ Color3.fromRGB(210, 210, 205), Color3.fromRGB(150, 110, 90), Color3.fromRGB(90, 92, 98), Color3.fromRGB(230, 225, 215) })[rng:NextInteger(1, 4)]
						mk("Part", folder, { Name = "Building", Size = Vector3.new(w - 2, h, d - 2), CFrame = CFrame.new(bc + Vector3.new(0, h / 2, 0)), Material = Enum.Material.Glass, Color = tint, Reflectance = 0.25 })
						for fy = 0, h, 14 do
							deco(folder, { Name = "Floor", Size = Vector3.new(w, 1.4, d), CFrame = CFrame.new(bc + Vector3.new(0, fy + 0.7, 0)), Material = Enum.Material.Concrete, Color = frame })
						end
						deco(folder, { Name = "Roof", Size = Vector3.new(w * 0.4, 4, d * 0.3), CFrame = CFrame.new(bc + Vector3.new(0, h + 2, 0)), Material = Enum.Material.Metal, Color = Color3.fromRGB(120, 122, 128) })
					end
				end
			elseif kind == "parking" then
				lot(c)
				local idx = 0
				for _, row in ipairs({ { -22, 0 }, { 22, math.pi } }) do
					local rz = c.Z + row[1]
					for k = 0, 9 do
						idx += 1
						local x = c.X + (k - 4.5) * 11
						local cf = CFrame.new(x, 0.95, rz) * CFrame.Angles(0, row[2], 0)
						zone(zones, "ParkSpace", cf, Vector3.new(11, 1.5, 20), { Index = idx })
						table.insert(city.spaces, cf)
					end
					for k = 0, 10 do
						deco(folder, { Name = "ParkLine", Size = Vector3.new(0.35, 0.02, 20), CFrame = CFrame.new(c.X + (k - 5) * 11, 0.48, rz), Color = white })
					end
					deco(folder, { Name = "ParkLine", Size = Vector3.new(110, 0.02, 0.35), CFrame = CFrame.new(c.X, 0.48, rz + (row[1] > 0 and 10 or -10)), Color = white })
					-- 카스토퍼
					for k = 0, 9 do
						deco(folder, { Name = "Stopper", Size = Vector3.new(5, 0.4, 0.6), CFrame = CFrame.new(c.X + (k - 4.5) * 11, 0.65, rz + (row[1] > 0 and 9 or -9)), Color = Color3.fromRGB(230, 200, 40) })
					end
				end
				local sp = mk("SpawnLocation", folder, { Name = "Spawn", Size = Vector3.new(8, 1, 8), CFrame = CFrame.new(c.X - 48, 0.6, c.Z), Neutral = true, Color = Color3.fromRGB(80, 160, 255), Material = Enum.Material.Neon, Transparency = 0.4, CanCollide = true, Duration = 0 })
				city.spawnCF = sp.CFrame
				marker(folder, Vector3.new(c.X, 0, c.Z), "🅿️ 주차장", Color3.fromRGB(40, 110, 220))
				table.insert(city.pois, { name = "주차장", pos = Vector3.new(c.X, 0.4, c.Z) })
			elseif kind == "gas" then
				lot(c)
				for _, sx in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						mk("Part", folder, { Name = "CanopyPillar", Size = Vector3.new(2, 18, 2), CFrame = CFrame.new(c.X + sx * 24, 9.4, c.Z + sz * 14), Material = Enum.Material.Metal, Color = Color3.fromRGB(230, 230, 230) })
					end
				end
				mk("Part", folder, { Name = "Canopy", Size = Vector3.new(60, 2, 40), CFrame = CFrame.new(c.X, 19.4, c.Z), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(245, 245, 245) })
				deco(folder, { Name = "CanopyStripe", Size = Vector3.new(60.4, 0.8, 40.4), CFrame = CFrame.new(c.X, 18.6, c.Z), Material = Enum.Material.Neon, Color = Color3.fromRGB(230, 40, 40) })
				for k = -2, 2 do
					local l = deco(folder, { Name = "CanopyLight", Size = Vector3.new(8, 0.2, 1.5), CFrame = CFrame.new(c.X + k * 11, 18.3, c.Z), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 255, 240) })
					local pl = Instance.new("PointLight")
					pl.Range = 30
					pl.Brightness = 1.5
					pl.Parent = l
				end
				for _, ix in ipairs({ -10, 10 }) do
					local ip = Vector3.new(c.X + ix, 0.45, c.Z)
					mk("Part", folder, { Name = "Island", Size = Vector3.new(3, 0.6, 18), CFrame = CFrame.new(ip + Vector3.new(0, 0.3, 0)), Material = Enum.Material.Concrete, Color = Color3.fromRGB(200, 200, 200) })
					local pump = mk("Part", folder, { Name = "Pump", Size = Vector3.new(2.2, 6, 3), CFrame = CFrame.new(ip + Vector3.new(0, 3.6, 0)), Color = Color3.fromRGB(240, 240, 240) })
					deco(folder, { Name = "PumpTop", Size = Vector3.new(2.4, 1, 3.2), CFrame = CFrame.new(ip + Vector3.new(0, 7, 0)), Material = Enum.Material.Neon, Color = Color3.fromRGB(230, 40, 40) })
					for _, s in ipairs({ -1, 1 }) do
						local scr = deco(folder, { Name = "PumpScreen", Size = Vector3.new(0.05, 1.2, 1.6), CFrame = CFrame.new(ip + Vector3.new(s * 1.13, 4.6, 0)), Material = Enum.Material.Neon, Color = Color3.fromRGB(40, 200, 120) })
						deco(folder, { Name = "Nozzle", Size = Vector3.new(0.5, 1.2, 0.4), CFrame = CFrame.new(ip + Vector3.new(s * 1.3, 3, 0.8)), Color = Color3.fromRGB(30, 30, 30) })
						local _ = scr
						local zp = zone(zones, "Pump", CFrame.new(ip + Vector3.new(s * 6.5, 2, 0)), Vector3.new(9, 6, 22))
						table.insert(city.pumps, zp)
					end
					local _ = pump
				end
				mk("Part", folder, { Name = "Store", Size = Vector3.new(34, 14, 18), CFrame = CFrame.new(c.X, 7.4, c.Z + 42), Material = Enum.Material.Concrete, Color = Color3.fromRGB(235, 235, 230) })
				deco(folder, { Name = "StoreGlass", Size = Vector3.new(26, 8, 0.4), CFrame = CFrame.new(c.X, 5.4, c.Z + 32.9), Material = Enum.Material.Glass, Color = Color3.fromRGB(120, 170, 200), Transparency = 0.3 })
				marker(folder, Vector3.new(c.X, 0, c.Z), "⛽ 주유소", Color3.fromRGB(220, 50, 50))
				table.insert(city.pois, { name = "주유소", pos = Vector3.new(c.X, 0.4, c.Z) })
			elseif kind == "dealer" then
				lot(c)
				local fz = c.Z - 18
				mk("Part", folder, { Name = "ShowFloor", Size = Vector3.new(96, 0.3, 54), CFrame = CFrame.new(c.X, 0.6, fz), Material = Enum.Material.Marble, Color = Color3.fromRGB(240, 240, 238), Reflectance = 0.1 })
				mk("Part", folder, { Name = "ShowRoof", Size = Vector3.new(100, 2, 58), CFrame = CFrame.new(c.X, 27, fz), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(30, 32, 36) })
				deco(folder, { Name = "RoofStripe", Size = Vector3.new(100.4, 0.6, 58.4), CFrame = CFrame.new(c.X, 26, fz), Material = Enum.Material.Neon, Color = Color3.fromRGB(80, 160, 255) })
				mk("Part", folder, { Name = "BackGlass", Size = Vector3.new(96, 26, 0.6), CFrame = CFrame.new(c.X, 13.6, fz - 27), Material = Enum.Material.Glass, Color = Color3.fromRGB(150, 190, 220), Transparency = 0.5 })
				for _, s in ipairs({ -1, 1 }) do
					mk("Part", folder, { Name = "SideGlass", Size = Vector3.new(0.6, 26, 54), CFrame = CFrame.new(c.X + s * 48, 13.6, fz), Material = Enum.Material.Glass, Color = Color3.fromRGB(150, 190, 220), Transparency = 0.5 })
				end
				for k, px in ipairs({ -33, -11, 11, 33 }) do
					local pc = Vector3.new(c.X + px, 0.75, fz - 4)
					deco(folder, { Name = "Turntable", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 19, 19), CFrame = CFrame.new(pc + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(45, 45, 50) })
					deco(folder, { Name = "TurntableRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 19.6, 19.6), CFrame = CFrame.new(pc) * CFrame.Angles(0, 0, math.pi / 2), Material = Enum.Material.Neon, Color = Color3.fromRGB(80, 160, 255) })
					table.insert(city.dealerSlots, CFrame.new(pc + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, math.rad(25 - (k - 1) * 0), 0))
				end
				city.deliverCF = CFrame.new(c.X + 30, 0.45, c.Z + 38) * CFrame.Angles(0, math.rad(90), 0)
				marker(folder, Vector3.new(c.X, 0, c.Z), "🚗 자동차 매장", Color3.fromRGB(30, 150, 90))
				table.insert(city.pois, { name = "자동차 매장", pos = Vector3.new(c.X, 0.4, c.Z) })
			elseif kind == "repair" then
				lot(c)
				local gz = c.Z + 12
				mk("Part", folder, { Name = "GarageBack", Size = Vector3.new(54, 22, 2), CFrame = CFrame.new(c.X, 11.4, gz + 22), Material = Enum.Material.Brick, Color = Color3.fromRGB(150, 90, 70) })
				for _, s in ipairs({ -1, 1 }) do
					mk("Part", folder, { Name = "GarageSide", Size = Vector3.new(2, 22, 44), CFrame = CFrame.new(c.X + s * 27, 11.4, gz), Material = Enum.Material.Brick, Color = Color3.fromRGB(150, 90, 70) })
				end
				mk("Part", folder, { Name = "GarageRoof", Size = Vector3.new(56, 2, 46), CFrame = CFrame.new(c.X, 23.4, gz), Material = Enum.Material.Metal, Color = Color3.fromRGB(90, 92, 98) })
				deco(folder, { Name = "GarageSign", Size = Vector3.new(30, 4, 0.5), CFrame = CFrame.new(c.X, 20, gz - 22.5), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 170, 40) })
				deco(folder, { Name = "RepairPad", Size = Vector3.new(16, 0.05, 26), CFrame = CFrame.new(c.X, 0.49, gz), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(240, 190, 40) })
				deco(folder, { Name = "RepairPadIn", Size = Vector3.new(14, 0.06, 24), CFrame = CFrame.new(c.X, 0.5, gz), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(60, 60, 64) })
				for _, s in ipairs({ -1, 1 }) do
					mk("Part", folder, { Name = "LiftPost", Size = Vector3.new(1.2, 12, 1.2), CFrame = CFrame.new(c.X + s * 9.5, 6.4, gz), Material = Enum.Material.Metal, Color = Color3.fromRGB(200, 40, 40) })
					mk("Part", folder, { Name = "ToolBox", Size = Vector3.new(4, 5, 2.5), CFrame = CFrame.new(c.X + s * 20, 2.9, gz + 18), Color = Color3.fromRGB(190, 30, 30) })
				end
				zone(zones, "RepairPad", CFrame.new(c.X, 2, gz), Vector3.new(18, 6, 28))
				marker(folder, Vector3.new(c.X, 0, c.Z), "🔧 정비소", Color3.fromRGB(230, 140, 30))
				table.insert(city.pois, { name = "정비소", pos = Vector3.new(c.X, 0.4, c.Z) })
			end
		end
	end
	table.insert(city.pois, { name = "도심", pos = city.blockCenter(0, 0) })
	table.insert(city.pois, { name = "외곽", pos = city.blockCenter(N - 1, N - 1) })

	return city
end

return CityBuilder
