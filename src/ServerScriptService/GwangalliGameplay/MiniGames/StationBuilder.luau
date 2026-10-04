--!strict
-- MiniGames/StationBuilder: builds the minigame spots on the 광안리 promenade at server start (server
-- only; plain Parts, no uploaded assets). One Model per MS.STATIONS entry under
-- workspace.GwangalliMiniGames, tagged MS.Tags.Station (contract in GwangalliMiniGamesShared).
--
-- Placement: the station frame sits on the seaside paving band (n = seed.n studs from the seawall
-- coping, on the MapData coast baseline), X along the promenade (tangent of the coast), -Z toward the
-- sea. The builder probes the floor (raycast) and the space above it (GetPartBoundsInBox) and slides
-- the spot along the promenade (0, +-6, +-12 ... up to MS.SLIDE) until nothing stands there (benches,
-- planters, lamp posts, plaza props), so a table never cuts through the existing street furniture.
--
-- Table station (omok / wordchain / memory / numberguess / quiz): a parasol picnic table between two
--   stools (SeatA west / SeatB east, facing each other), game props on the table (the 15x15 omok board
--   is a real board: grid lines and star points as thin parts; the stones are drawn by every client
--   from the station's OmokBoard attribute), an A-frame sign facing the walk, a warm lantern.
-- Stand station (rps / reaction / timing): two pads; rps face to face around a small sign post,
--   reaction / timing side by side in front of a beach arcade cabinet (screen SurfaceGui is drawn by
--   the clients) that faces the walk with the sea and 광안대교 behind it.
-- Camera hints (invisible parts): CamA / CamB (each player's view), CamSpec (spectators), Focus (the
-- point the cameras look at).

local CollectionService = game:GetService("CollectionService")

local StationBuilder = {}

local M: any = nil
local MS: any = nil
local OC: any = nil

local WOOD = Color3.fromRGB(176, 128, 82)
local WOOD_DARK = Color3.fromRGB(110, 76, 48)
local METAL = Color3.fromRGB(70, 74, 82)
local WHITE = Color3.fromRGB(240, 240, 236)

-- parasol colours per game (stripes A / B)
local PARASOL = {
	omok = { Color3.fromRGB(32, 92, 168), WHITE },
	wordchain = { Color3.fromRGB(230, 110, 40), WHITE },
	memory = { Color3.fromRGB(46, 160, 120), WHITE },
	numberguess = { Color3.fromRGB(200, 60, 80), WHITE },
	quiz = { Color3.fromRGB(120, 80, 200), WHITE },
}

function StationBuilder.init(m: any)
	M = m
	MS = m.MS
	OC = m.OC
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.CanTouch = false
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function cyl(parent: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	-- cylinders are along X in Roblox: stand it up
	local p = part(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function hint(parent: Instance, name: string, cf: CFrame): BasePart
	return part(parent, name, Vector3.new(0.4, 0.4, 0.4), cf, WHITE, { Transparency = 1, CanCollide = false, CanQuery = false })
end

-------------------------------------------------------------------------------------------------
-- placement
-------------------------------------------------------------------------------------------------
local FLOOR_TOP = 6.5
local function frameAt(x: number, n: number): CFrame
	local z = MS.baseline(x) + n
	local tangent = Vector3.new(1, 0, -2 * MS.COAST_A * x).Unit
	local up = Vector3.new(0, 1, 0)
	return CFrame.fromMatrix(Vector3.new(x, FLOOR_TOP, z), tangent, up)
end

local function excluded(): { Instance }
	local list: { Instance } = {}
	local f = workspace:FindFirstChild(MS.FolderName)
	if f then
		table.insert(list, f)
	end
	local npcs = workspace:FindFirstChild(MS.NpcFolder)
	if npcs then
		table.insert(list, npcs)
	end
	for _, pl in game:GetService("Players"):GetPlayers() do
		if pl.Character then
			table.insert(list, pl.Character)
		end
	end
	return list
end

-- floor height at a world point (nil when there is no walkable floor: the sea, sand far below...)
local function floorAt(p: Vector3): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded()
	local ok, r = pcall(function()
		return workspace:Raycast(p + Vector3.new(0, 30, 0), Vector3.new(0, -50, 0), params)
	end)
	if ok and r then
		return r.Position.Y
	end
	return nil
end

-- true when nothing taller than the floor occupies the footprint (half extents along X / Z)
local function clear(cf: CFrame, hx: number, hz: number, floorY: number): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded()
	local box = CFrame.new(cf.Position.X, floorY + 3.4, cf.Position.Z) * cf.Rotation
	local ok, hits = pcall(function()
		return workspace:GetPartBoundsInBox(box, Vector3.new(hx * 2, 6, hz * 2), params)
	end)
	if not ok or type(hits) ~= "table" then
		return true -- engine without spatial queries: trust the seed
	end
	for _, h in hits do
		if h:IsA("BasePart") and h.Transparency < 0.95 then
			local top = h.Position.Y + h.Size.Y / 2
			-- the paving itself (and kerb lips) is fine; anything that rises above it blocks
			if top > floorY + 0.35 and h.Size.Y < 400 then
				return false
			end
		end
	end
	return true
end

local function findSpot(seed: any, hx: number, hz: number): (CFrame, boolean)
	local tries = { 0 }
	local step = 6
	local d = step
	while d <= MS.SLIDE do
		table.insert(tries, d)
		table.insert(tries, -d)
		d += step
	end
	for _, dn in { 0, 1, -1 } do
		for _, dx in tries do
			local cf = frameAt(seed.x + dx, seed.n + dn)
			local fy = floorAt(cf.Position)
			if fy and math.abs(fy - FLOOR_TOP) < 1.2 and clear(cf, hx, hz, fy) then
				return CFrame.new(cf.Position.X, fy, cf.Position.Z) * cf.Rotation, true
			end
		end
	end
	local cf = frameAt(seed.x, seed.n)
	local fy = floorAt(cf.Position) or FLOOR_TOP
	return CFrame.new(cf.Position.X, fy, cf.Position.Z) * cf.Rotation, false
end

-------------------------------------------------------------------------------------------------
-- props
-------------------------------------------------------------------------------------------------
local function sign(model: Model, f: CFrame, info: any, npc: any?, at: Vector3)
	local post = f * CFrame.new(at)
	local face = post * CFrame.new(0, 2.1, 0)
	local board = part(model, "Sign", Vector3.new(2.6, 1.9, 0.18), face, Color3.fromRGB(28, 34, 52), { CanCollide = false })
	part(model, "SignLeg", Vector3.new(0.18, 1.3, 0.18), post * CFrame.new(-0.9, 0.65, 0), METAL, { CanCollide = false })
	part(model, "SignLeg", Vector3.new(0.18, 1.3, 0.18), post * CFrame.new(0.9, 0.65, 0), METAL, { CanCollide = false })
	for _, side in { Enum.NormalId.Back, Enum.NormalId.Front } do
		local g = Instance.new("SurfaceGui")
		g.Name = "SignGui"
		g.Face = side
		g.CanvasSize = Vector2.new(260, 190)
		g.LightInfluence = 0.2
		g.Brightness = 1.4
		g.Parent = board
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0.42, 0)
		title.Position = UDim2.fromScale(0, 0.06)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(255, 214, 110)
		title.Text = info.icon .. " " .. info.name
		title.Parent = g
		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.new(0.92, 0, 0.22, 0)
		sub.Position = UDim2.fromScale(0.04, 0.5)
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(235, 240, 250)
		sub.Text = info.desc
		sub.Parent = g
		local foot = Instance.new("TextLabel")
		foot.BackgroundTransparency = 1
		foot.Size = UDim2.new(0.92, 0, 0.18, 0)
		foot.Position = UDim2.fromScale(0.04, 0.76)
		foot.Font = Enum.Font.Gotham
		foot.TextScaled = true
		foot.TextColor3 = Color3.fromRGB(160, 220, 255)
		foot.Text = if npc then npc.name .. " (" .. MS.DIFFICULTY[npc.difficulty] .. ") 대기 중" else "누구나 한 판!"
		foot.Name = "Foot"
		foot.Parent = g
	end
end

local function lantern(model: Model, cf: CFrame)
	local l = part(model, "Lantern", Vector3.new(0.45, 0.6, 0.45), cf, Color3.fromRGB(255, 220, 160), { Material = Enum.Material.Neon, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 196, 130)
	light.Brightness = 1.2
	light.Range = 14
	light.Shadows = false
	light.Parent = l
end

local function parasol(model: Model, f: CFrame, colors: { Color3 })
	cyl(model, "ParasolPole", 0.22, 8.4, f * CFrame.new(0, 4.2, 0), WHITE, { CanCollide = false })
	-- eight wedge-ish panels as a low cone: alternating colours
	local radius = 4.6
	for i = 0, 7 do
		local a = i * math.pi / 4
		local mid = f * CFrame.Angles(0, a, 0) * CFrame.new(0, 7.9, -radius * 0.5)
		local panel = part(model, "Canopy", Vector3.new(radius * 0.82, 0.12, radius), mid * CFrame.Angles(math.rad(-14), 0, 0), colors[(i % 2) + 1], { CanCollide = false, CanQuery = false })
		panel.Material = Enum.Material.Fabric
	end
	cyl(model, "ParasolTop", 0.5, 0.4, f * CFrame.new(0, 8.6, 0), colors[1], { CanCollide = false })
	lantern(model, f * CFrame.new(0, 7.2, 0))
end

local function stool(model: Model, name: string, f: CFrame, local_: Vector3, yaw: number): Seat
	local base = f * CFrame.new(local_)
	cyl(model, name .. "Leg", 0.35, 1.3, base * CFrame.new(0, 0.65, 0), METAL)
	local seat = Instance.new("Seat")
	seat.Name = name
	seat.Anchored = true
	seat.Size = Vector3.new(1.7, 0.3, 1.7)
	seat.CFrame = base * CFrame.new(0, 1.45, 0) * CFrame.Angles(0, yaw, 0)
	seat.Color = WOOD
	seat.Material = Enum.Material.WoodPlanks
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.CastShadow = false
	seat.CanTouch = false -- only the server seats players (Seat:Sit); walking into it does nothing
	seat.Parent = model
	return seat
end

local function omokBoard(model: Model, top: CFrame)
	local size = OC.SIZE
	local span = (size - 1) * OC.CELL
	local slab = span + OC.CELL * 1.6
	local board = part(model, "Board", Vector3.new(slab, OC.BOARD_Y, slab), top * CFrame.new(0, OC.BOARD_Y / 2, 0), Color3.fromRGB(222, 178, 104), { Material = Enum.Material.Wood })
	board:SetAttribute("Cell", OC.CELL)
	board:SetAttribute("Size", size)
	local surface = top * CFrame.new(0, OC.BOARD_Y + 0.006, 0)
	local lineColor = Color3.fromRGB(60, 40, 22)
	local lines = Instance.new("Model")
	lines.Name = "Grid"
	lines.Parent = model
	for k = 1, size do
		local o = (k - (size + 1) / 2) * OC.CELL
		part(lines, "L", Vector3.new(span, 0.012, 0.025), surface * CFrame.new(0, 0, o), lineColor, { CanCollide = false, CanQuery = false })
		part(lines, "L", Vector3.new(0.025, 0.012, span), surface * CFrame.new(o, 0, 0), lineColor, { CanCollide = false, CanQuery = false })
	end
	for _, s in { { 4, 4 }, { 12, 4 }, { 8, 8 }, { 4, 12 }, { 12, 12 } } do
		local ox = (s[1] - (size + 1) / 2) * OC.CELL
		local oz = (s[2] - (size + 1) / 2) * OC.CELL
		local dot = part(lines, "Star", Vector3.new(0.012, 0.09, 0.09), surface * CFrame.new(ox, 0.004, oz) * CFrame.Angles(0, 0, math.rad(90)), lineColor, { CanCollide = false, CanQuery = false })
		dot.Shape = Enum.PartType.Cylinder
	end
	-- stone bowls (흑 at seat A's side, 백 at seat B's side)
	cyl(model, "BowlBlack", 0.55, 0.28, top * CFrame.new(-slab / 2 - 0.15, 0.14, slab / 2 - 0.4), WOOD_DARK, { CanCollide = false })
	cyl(model, "BowlWhite", 0.55, 0.28, top * CFrame.new(slab / 2 + 0.15, 0.14, -slab / 2 + 0.4), WOOD_DARK, { CanCollide = false })
end

local function tableProps(model: Model, gameId: string, top: CFrame)
	if gameId == "omok" then
		omokBoard(model, top)
	elseif gameId == "wordchain" then
		part(model, "Notebook", Vector3.new(1.0, 0.06, 1.3), top * CFrame.new(-0.4, 0.03, 0.2) * CFrame.Angles(0, 0.2, 0), WHITE, { CanCollide = false })
		part(model, "Pencil", Vector3.new(0.06, 0.06, 0.9), top * CFrame.new(0.4, 0.05, 0.1) * CFrame.Angles(0, -0.5, 0), Color3.fromRGB(250, 200, 40), { CanCollide = false })
	elseif gameId == "quiz" then
		cyl(model, "BuzzerA", 0.6, 0.25, top * CFrame.new(-1.2, 0.12, 0), Color3.fromRGB(230, 60, 70), { CanCollide = false, Material = Enum.Material.Neon })
		cyl(model, "BuzzerB", 0.6, 0.25, top * CFrame.new(1.2, 0.12, 0), Color3.fromRGB(60, 140, 240), { CanCollide = false, Material = Enum.Material.Neon })
	elseif gameId == "memory" then
		for i = 1, 5 do
			part(model, "Card", Vector3.new(0.4, 0.04, 0.56), top * CFrame.new((i - 3) * 0.5, 0.02, 0), if i % 2 == 0 then Color3.fromRGB(240, 90, 90) else WHITE, { CanCollide = false })
		end
	elseif gameId == "numberguess" then
		part(model, "NumberStand", Vector3.new(1.2, 0.8, 0.1), top * CFrame.new(0, 0.4, 0) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(30, 34, 50), { CanCollide = false })
	end
end

local function buildTable(model: Model, f: CFrame, seed: any, info: any, npc: any?)
	local topY = 2.7
	part(model, "Table", Vector3.new(4.6, 0.25, 4.0), f * CFrame.new(0, topY - 0.125, 0), WOOD, { Material = Enum.Material.WoodPlanks })
	cyl(model, "TableLeg", 0.5, topY - 0.25, f * CFrame.new(0, (topY - 0.25) / 2, 0), METAL)
	part(model, "TableFoot", Vector3.new(2.2, 0.15, 2.2), f * CFrame.new(0, 0.075, 0), METAL, { CanCollide = false })
	local top = f * CFrame.new(0, topY, 0)
	tableProps(model, seed.game, top)
	-- seats face the table: A on the west (-X) faces +X, B on the east faces -X
	stool(model, "SeatA", f, Vector3.new(-3.0, 0, 0), -math.pi / 2)
	stool(model, "SeatB", f, Vector3.new(3.0, 0, 0), math.pi / 2)
	parasol(model, f * CFrame.new(0, 0, 0), PARASOL[seed.game] or PARASOL.omok)
	sign(model, f, info, npc, Vector3.new(0, 0, 3.6))
	-- cameras: each player looks over the table from behind their own stool, spectators from the walk
	local focus = top.Position + Vector3.new(0, 0.1, 0)
	hint(model, "Focus", CFrame.new(focus))
	hint(model, "CamA", CFrame.lookAt((f * CFrame.new(-5.6, 9.6, 1.2)).Position, focus))
	hint(model, "CamB", CFrame.lookAt((f * CFrame.new(5.6, 9.6, -1.2)).Position, focus))
	hint(model, "CamSpec", CFrame.lookAt((f * CFrame.new(0, 7.5, 8.5)).Position, focus))
	-- where an NPC host waits when two players take the table
	hint(model, "NpcAside", f * CFrame.new(-1.5, 0, 4.6) * CFrame.Angles(0, math.pi, 0))
end

local function pad(model: Model, name: string, cf: CFrame)
	local p = part(model, name, Vector3.new(0.08, 2.4, 2.4), cf * CFrame.new(0, 0.04, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 194, 71), { CanCollide = false, CanQuery = false, Transparency = 0.25, Material = Enum.Material.Neon })
	p.Shape = Enum.PartType.Cylinder
end

local function buildStand(model: Model, f: CFrame, seed: any, info: any, npc: any?)
	if seed.game == "rps" then
		-- face to face across a little round sign
		cyl(model, "Post", 0.25, 3.2, f * CFrame.new(0, 1.6, 0), METAL, { CanCollide = false })
		local disc = cyl(model, "Disc", 1.6, 0.15, f * CFrame.new(0, 3.4, 0) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(255, 120, 160), { CanCollide = false })
		disc:SetAttribute("Screen", true)
		local padA = f * CFrame.new(-2.4, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
		local padB = f * CFrame.new(2.4, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
		pad(model, "PadA", padA)
		pad(model, "PadB", padB)
		hint(model, "SpotA", padA)
		hint(model, "SpotB", padB)
		local focus = (f * CFrame.new(0, 3.2, 0)).Position
		hint(model, "Focus", CFrame.new(focus))
		hint(model, "CamA", CFrame.lookAt((f * CFrame.new(-6.5, 5.6, 4.5)).Position, focus))
		hint(model, "CamB", CFrame.lookAt((f * CFrame.new(6.5, 5.6, 4.5)).Position, focus))
		hint(model, "CamSpec", CFrame.lookAt((f * CFrame.new(0, 6, 10)).Position, focus))
		sign(model, f, info, npc, Vector3.new(0, 0, 4.2))
	else
		-- a beach arcade cabinet on the sea side; players stand on the walk side facing the sea
		local body = part(model, "Cabinet", Vector3.new(4.6, 5.2, 1.4), f * CFrame.new(0, 2.6, -1.9), Color3.fromRGB(24, 28, 44))
		body.Material = Enum.Material.SmoothPlastic
		local screen = part(model, "Screen", Vector3.new(3.9, 2.3, 0.1), f * CFrame.new(0, 3.75, -1.17), Color3.fromRGB(8, 10, 18), { CanCollide = false, Material = Enum.Material.Neon })
		screen:SetAttribute("Screen", true)
		part(model, "Marquee", Vector3.new(4.6, 0.8, 1.6), f * CFrame.new(0, 5.6, -1.9), if seed.game == "reaction" then Color3.fromRGB(255, 70, 110) else Color3.fromRGB(70, 200, 255), { Material = Enum.Material.Neon, CanCollide = false })
		part(model, "Console", Vector3.new(4.6, 0.3, 1.2), f * CFrame.new(0, 2.3, -0.9) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(40, 44, 64), { CanCollide = false })
		cyl(model, "ButtonA", 0.7, 0.3, f * CFrame.new(-1.2, 2.5, -0.85), Color3.fromRGB(240, 60, 70), { Material = Enum.Material.Neon, CanCollide = false })
		cyl(model, "ButtonB", 0.7, 0.3, f * CFrame.new(1.2, 2.5, -0.85), Color3.fromRGB(60, 140, 255), { Material = Enum.Material.Neon, CanCollide = false })
		lantern(model, f * CFrame.new(0, 6.2, -1.9))
		local padA = f * CFrame.new(-1.3, 0, 0.6)
		local padB = f * CFrame.new(1.3, 0, 0.6)
		pad(model, "PadA", padA)
		pad(model, "PadB", padB)
		hint(model, "SpotA", padA)
		hint(model, "SpotB", padB)
		local focus = (f * CFrame.new(0, 3.4, -1.2)).Position
		hint(model, "Focus", CFrame.new(focus))
		hint(model, "CamA", CFrame.lookAt((f * CFrame.new(-1.0, 6.2, 8.0)).Position, focus))
		hint(model, "CamB", CFrame.lookAt((f * CFrame.new(1.0, 6.2, 8.0)).Position, focus))
		hint(model, "CamSpec", CFrame.lookAt((f * CFrame.new(-5, 6.5, 9)).Position, focus))
		sign(model, f, info, npc, Vector3.new(3.8, 0, 1.2))
	end
	hint(model, "NpcAside", f * CFrame.new(-3.6, 0, 3.4) * CFrame.Angles(0, math.rad(200), 0))
end

-------------------------------------------------------------------------------------------------
-- public
-------------------------------------------------------------------------------------------------
-- -> list of station records { id, seed, game, info, model, frame, npc (NpcHost?), clearSpot }
function StationBuilder.build(): { any }
	local folder = workspace:FindFirstChild(MS.FolderName)
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = MS.FolderName
	folder.Parent = workspace
	local out = {}
	for _, seed in MS.STATIONS do
		local info = MS.GAMES[seed.game]
		if info then
			local npc = if seed.npc then MS.NPCS[seed.npc] else nil
			local tableKind = info.kind == "table"
			local hx = if tableKind then 5 else 4
			local hz = if tableKind then 3.4 else 2.6
			local f, ok = findSpot(seed, hx, hz)
			if not ok then
				warn("[MiniGames] station " .. seed.id .. ": no clear spot found near x = " .. seed.x .. ", built at the seed")
			end
			local model = Instance.new("Model")
			model.Name = seed.id
			if info.kind == "table" then
				buildTable(model, f, seed, info, npc)
			else
				buildStand(model, f, seed, info, npc)
			end
			model:SetAttribute("StationId", seed.id)
			model:SetAttribute("GameId", seed.game)
			model:SetAttribute("Label", seed.label)
			model:SetAttribute("NpcId", if npc then npc.id else "")
			model:SetAttribute("State", "idle")
			model:SetAttribute("P1", "")
			model:SetAttribute("P2", "")
			model:SetAttribute("P1Id", 0)
			model:SetAttribute("P2Id", 0)
			model:SetAttribute("Stake", 0)
			model:SetAttribute("Pot", 0)
			model:SetAttribute("Score", "")
			model:SetAttribute("Turn", 0)
			model:SetAttribute("MatchId", 0)
			model:SetAttribute("WaitStake", -1)
			model:SetAttribute("Spectators", 0)
			pcall(function()
				(model :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			end)
			local primary = model:FindFirstChild("Table") or model:FindFirstChild("Cabinet") or model:FindFirstChild("Post")
			if primary and primary:IsA("BasePart") then
				model.PrimaryPart = primary
			end
			model.Parent = folder
			CollectionService:AddTag(model, MS.Tags.Station)
			table.insert(out, { id = seed.id, seed = seed, game = seed.game, info = info, model = model, frame = f, npc = npc, clearSpot = ok })
		end
	end
	return out
end

return StationBuilder
