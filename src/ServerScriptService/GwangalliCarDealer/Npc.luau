-- GwangalliCarDealer/Npc (server): the sales NPCs.
--   * OUR CONSULTANT(S) (Config.NPCS): a GwangalliNPCLooks rig (a real avatar from GwangalliAvatarPool when the
--     pool is ready, else the block body), anchored, non-colliding, in Workspace.GwangalliCarDealer. Its spot is
--     the first candidate that stands on the showroom floor (ray), is free of map parts (box test), stays off the
--     turntable sweeps, keeps 8 studs from the garage's prompts and is outside the showroom display cars. It
--     is placed only after GwangalliShowroom has finished (its box test would otherwise see our NPC). The
--     client animates it (look-at, wave, talk) with GwangalliAnim; the server never moves it.
--   * HOOKED MAP STAFF (Config.HOOK_STAFF): rigs tagged GarageStaff whose Role is listed (박사장 = owner) get a
--     "딜러와 상담하기" prompt on an invisible anchor part of ours placed at the rig (F key: his desk's own E
--     prompt keeps opening the garage panel). The rig itself only gets attribute GwDealerNpc = true; its pose,
--     look and parts are never touched.
--   Npc.start()          (yields; run in a thread)
--   Npc.list() -> { { id, name, role, voice, icon, pos, ours } }     Npc.info(id)     Npc.nearest(pos) -> info, dist

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Npc = {}

local C: any
local Bridge: any
local N: any

local folder: Folder? = nil
local npcs: { [string]: any } = {}

function Npc.init(shared: any, bridge: any)
	C = shared.Config
	N = shared.NAMES
	Bridge = bridge
end

function Npc.folder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = workspace:FindFirstChild(N.World)
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = N.World
		f.Parent = workspace
	end
	folder = f :: Folder
	return folder :: Folder
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function characters(): { Instance }
	local out: { Instance } = { Npc.folder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(out, p.Character)
		end
	end
	return out
end

-- Spot checks ---------------------------------------------------------------------------------------------------
local function promptPositions(): { Vector3 }
	local out = {}
	local venue = Bridge.venue()
	local roots: { Instance } = {}
	if venue then
		table.insert(roots, venue)
	end
	local showroom = workspace:FindFirstChild("GwangalliShowroom")
	if showroom then
		table.insert(roots, showroom)
	end
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				local p = d.Parent
				if p and p:IsA("Attachment") then
					table.insert(out, p.WorldPosition)
				elseif p and p:IsA("BasePart") then
					table.insert(out, p.Position)
				end
			end
		end
	end
	return out
end

local function turntableCentres(): { Vector3 }
	local out = {}
	for _, t in CollectionService:GetTagged("GarageTurntable") do
		if t:IsA("BasePart") then
			local c = t:GetAttribute("Centre")
			table.insert(out, if typeof(c) == "Vector3" then c else t.Position)
		end
	end
	return out
end

local function insideShowroomCar(pos: Vector3, pad: number): boolean
	for _, m in CollectionService:GetTagged("GarageShowroomCar") do
		if m:IsA("Model") and m:IsDescendantOf(workspace) then
			local ok, cf, size = pcall(function()
				return m:GetBoundingBox()
			end)
			if ok then
				local l = cf:PointToObjectSpace(pos)
				if math.abs(l.X) <= size.X / 2 + pad and math.abs(l.Z) <= size.Z / 2 + pad then
					return true
				end
			end
		end
	end
	return false
end

local function floorY(x: number, z: number, startY: number): (number?, BasePart?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characters()
	local res = workspace:Raycast(Vector3.new(x, startY, z), Vector3.new(0, -C.SPOT_RULES.maxFloorDrop - 6, 0), params)
	if res and res.Normal.Y > 0.7 then
		return res.Position.Y, res.Instance :: BasePart
	end
	return nil, nil
end

local function boxFree(pos: Vector3, fy: number): (boolean, string?)
	local fp = C.SPOT_RULES.footprint
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characters()
	local parts = workspace:GetPartBoundsInBox(CFrame.new(pos.X, fy + 0.2 + fp.Y / 2, pos.Z), fp, params)
	for _, p in parts do
		local invisible = p.Transparency >= 0.95
		if not (invisible and not p.CanCollide) then
			-- floor-level parts (rugs, floor tiles, the turntable disc edge) never block
			local ok, cf, size = pcall(function()
				return p.CFrame, p.Size
			end)
			if ok then
				local top = cf.Position.Y + math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
				if top > fy + 0.35 then
					return false, p:GetFullName()
				end
			end
		end
	end
	return true, nil
end

-- -> floorY?, reason?
local function checkSpot(pos: Vector3, startY: number, relaxed: boolean): (number?, string?)
	local R = C.SPOT_RULES
	for _, c in turntableCentres() do
		if flat(pos, c) < R.turntableClear then
			return nil, "turntable"
		end
	end
	for _, p in promptPositions() do
		if flat(pos, p) < R.promptClear then
			return nil, "prompt"
		end
	end
	if insideShowroomCar(pos, R.showroomPad) then
		return nil, "showroom car"
	end
	local fy = floorY(pos.X, pos.Z, startY)
	if not fy then
		return nil, "no floor"
	end
	if not relaxed then
		local free, why = boxFree(pos, fy)
		if not free then
			return nil, "blocked by " .. tostring(why)
		end
	end
	return fy, nil
end

-- Rig ----------------------------------------------------------------------------------------------------------------
local function strip(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart" or d.Anchored
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("BaseScript") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			d:Destroy()
		end
	end
end

-- A plain anchored mannequin when GwangalliNPCLooks is missing (old places).
local function fallbackRig(name: string, suitColor: Color3): (Model, BasePart, number)
	local m = Instance.new("Model")
	m.Name = name
	local function part(n: string, size: Vector3, offset: Vector3, color: Color3): BasePart
		local p = Instance.new("Part")
		p.Name = n
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	local skin = Color3.fromRGB(234, 198, 170)
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero, skin)
	root.Transparency = 1
	part("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 0.5, 0), suitColor)
	part("LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, -0.5, 0), suitColor)
	local head = part("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.9, 0), skin)
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	part("LeftUpperArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0.3, 0), suitColor)
	part("RightUpperArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0.3, 0), suitColor)
	part("LeftUpperLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), Color3.fromRGB(30, 32, 40))
	part("RightUpperLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), Color3.fromRGB(30, 32, 40))
	m.PrimaryPart = root
	return m, root, 3
end

local function buildRig(cfg: any): (Model, BasePart, number)
	local name = "GwangalliCarDealer_NPC_" .. cfg.id
	local lm = ReplicatedStorage:FindFirstChild("GwangalliNPCLooks")
	if lm and lm:IsA("ModuleScript") then
		local ok, res = pcall(function()
			local Looks = require(lm) :: any
			local spec = Looks.resolve(cfg.look or { style = "suit" }, "GwCarDealer_" .. cfg.id)
			return Looks.build(spec, { name = name, humanoid = false, anchored = true, shadow = true })
		end)
		if ok and type(res) == "table" and res.model and res.root then
			return res.model, res.root, tonumber(res.ground) or 3
		end
		warn("[GwangalliCarDealer] NPC look build failed, using a plain figure: " .. tostring(res))
	end
	return fallbackRig(name, Color3.fromRGB(32, 36, 48))
end

local function addPrompt(parent: Instance, id: string, objectText: string, hook: boolean)
	local p = Instance.new("ProximityPrompt")
	p.Name = "DealerPrompt"
	p.ActionText = C.PROMPT.action
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.RequiresLineOfSight = false
	p.MaxActivationDistance = if hook then C.HOOK_STAFF.range else C.PROMPT.range
	pcall(function()
		if hook then
			p.KeyboardKeyCode = C.HOOK_STAFF.key
			p.GamepadKeyCode = C.HOOK_STAFF.gamepadKey
			p.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
		else
			p.KeyboardKeyCode = Enum.KeyCode.E
			p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		end
	end)
	p:SetAttribute(N.AttrNpc, id)
	p.Parent = parent
end

local function stamp(inst: Instance, info: any, ours: boolean)
	inst:SetAttribute(N.AttrNpc, info.id)
	inst:SetAttribute(N.AttrDealer, true)
	inst:SetAttribute(N.AttrName, info.name)
	inst:SetAttribute(N.AttrRole, info.role)
	inst:SetAttribute(N.AttrVoice, info.voice)
	inst:SetAttribute(N.AttrIcon, info.icon)
	inst:SetAttribute(N.AttrOurs, ours)
	CollectionService:AddTag(inst, N.TagNpc)
end

local function spawnConsultant(cfg: any, startY: number)
	if npcs[cfg.id] then
		return
	end
	local chosen, fy, why
	for pass = 1, 2 do
		for i, spot in cfg.spots do
			local y, reason = checkSpot(spot.pos, startY, pass == 2)
			if y then
				chosen, fy = spot, y
				if pass == 2 then
					warn(string.format("[GwangalliCarDealer] %s: no spot passed the box test, using spot %d (%s)", cfg.id, i, tostring(why)))
				end
				break
			end
			why = reason
			Bridge.log(cfg.id, "spot", i, "rejected:", reason)
		end
		if chosen then
			break
		end
	end
	if not chosen or not fy then
		warn("[GwangalliCarDealer] no free spot for NPC " .. cfg.id .. " (" .. tostring(why) .. "): not placed")
		return
	end
	local model, root, ground = buildRig(cfg)
	strip(model)
	root.Anchored = true
	local face = chosen.face or Vector3.zAxis
	local look = Vector3.new(face.X, 0, face.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.zAxis
	end
	local at = Vector3.new(chosen.pos.X, fy + ground, chosen.pos.Z)
	model:PivotTo(CFrame.lookAt(at, at + look.Unit))
	pcall(function()
		(model :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	local info = { id = cfg.id, name = cfg.name, role = cfg.role, voice = cfg.voice or "consult", icon = cfg.icon or "🧑‍💼", tab = cfg.tab, ours = true, pos = at, model = model }
	stamp(model, info, true)
	local att = Instance.new("Attachment")
	att.Name = "DealerPromptAnchor"
	att.Position = Vector3.new(0, C.PROMPT.height, 0)
	att.Parent = root
	addPrompt(att, cfg.id, cfg.name .. " · " .. cfg.role, false)
	model.Parent = Npc.folder()
	npcs[cfg.id] = info
	print(string.format("[GwangalliCarDealer] %s %s at (%.1f, %.1f, %.1f)", cfg.name, cfg.role, at.X, at.Y, at.Z))
end

-- Hooked staff -----------------------------------------------------------------------------------------------------
local hooked: { [Instance]: boolean } = {}

local function rigRoot(rig: Model): BasePart?
	local r = rig:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r
	end
	if rig.PrimaryPart then
		return rig.PrimaryPart
	end
	return rig:FindFirstChildWhichIsA("BasePart", true)
end

local function hookRig(rig: Instance)
	if hooked[rig] or not rig:IsA("Model") or not rig:IsDescendantOf(workspace) then
		return
	end
	local role = rig:GetAttribute("Role")
	local conf = type(role) == "string" and C.HOOK_STAFF.roles[role]
	if not conf then
		return
	end
	local root = rigRoot(rig)
	if not root then
		return
	end
	hooked[rig] = true
	local id = conf.id
	local n = 1
	while npcs[id] do
		n += 1
		id = conf.id .. tostring(n)
	end
	local name = conf.name or (string.match(rig.Name, "^%s*([^%(]-)%s*%(") or rig.Name)
	if name == "" then
		name = rig.Name
	end
	local anchor = Instance.new("Part")
	anchor.Name = "DealerHook_" .. id
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.CFrame = root.CFrame + Vector3.new(0, C.PROMPT.height, 0)
	local info = { id = id, name = name, role = conf.role, voice = conf.voice or "consult", icon = conf.icon or "🧑‍💼", ours = false, pos = root.Position, rig = rig, anchor = anchor }
	stamp(anchor, info, false)
	local ref = Instance.new("ObjectValue")
	ref.Name = "Rig"
	ref.Value = rig
	ref.Parent = anchor
	addPrompt(anchor, id, name .. " · " .. conf.role, true)
	anchor.Parent = Npc.folder()
	rig:SetAttribute(N.AttrDealer, true)
	npcs[id] = info
	print(string.format("[GwangalliCarDealer] hooked %s (%s) as a dealer", rig.Name, tostring(role)))
	rig.AncestryChanged:Connect(function()
		if not rig:IsDescendantOf(workspace) then
			hooked[rig] = nil
			npcs[id] = nil
			anchor:Destroy()
		end
	end)
end

local function hookAll()
	if not C.HOOK_STAFF.enabled then
		return
	end
	for _, tag in C.HOOK_STAFF.tags do
		for _, rig in CollectionService:GetTagged(tag) do
			hookRig(rig)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(rig)
			task.defer(hookRig, rig)
		end)
	end
end

-- Start ------------------------------------------------------------------------------------------------------------
local function waitShowroom()
	-- GwangalliShowroom places its display cars about 6 s after start, testing free grid spots against server parts.
	while workspace.DistributedGameTime < C.WAIT.showroomSettle do
		task.wait(0.5)
	end
	if not ServerStorage:FindFirstChild("GwangalliCarModels") then
		return -- no templates: the showroom places nothing
	end
	local t0 = os.clock()
	while os.clock() - t0 < C.WAIT.showroomPlaced do
		local f = workspace:FindFirstChild("GwangalliShowroom")
		if f and f:GetAttribute("Placed") ~= nil then
			return
		end
		task.wait(0.5)
	end
end

function Npc.start()
	local t0 = os.clock()
	while not Bridge.venue() and os.clock() - t0 < C.WAIT.venue do
		task.wait(1)
	end
	local venue = Bridge.venue()
	if not venue then
		warn("[GwangalliCarDealer] the garage venue (tag GarageShop) was not found: no dealer NPC")
		return
	end
	hookAll()
	waitShowroom()
	local ref = Bridge.marker("GarageReturn") or Bridge.marker("GarageSpawn")
	local baseY = if ref then ref.Position.Y elseif venue:IsA("Model") then venue:GetPivot().Position.Y else 7
	for _, cfg in C.NPCS do
		if cfg.enabled then
			local ok, err = pcall(spawnConsultant, cfg, baseY + 8)
			if not ok then
				warn("[GwangalliCarDealer] NPC " .. tostring(cfg.id) .. " failed: " .. tostring(err))
			end
		end
	end
end

function Npc.list(): { any }
	local out = {}
	for _, n in npcs do
		local pos = n.pos
		if n.anchor and n.anchor.Parent then
			pos = n.anchor.Position
		end
		table.insert(out, { id = n.id, name = n.name, role = n.role, voice = n.voice, icon = n.icon, pos = pos, ours = n.ours, tab = n.tab })
	end
	return out
end

function Npc.info(id: any): any?
	if type(id) ~= "string" then
		return nil
	end
	local n = npcs[id]
	if not n then
		return nil
	end
	return { id = n.id, name = n.name, role = n.role, voice = n.voice, icon = n.icon, ours = n.ours, tab = n.tab, pos = n.pos }
end

function Npc.nearest(pos: Vector3): (any?, number)
	local best, bestD = nil, math.huge
	for _, n in Npc.list() do
		local d = (n.pos - pos).Magnitude
		if d < bestD then
			best, bestD = n, d
		end
	end
	return best, bestD
end

return Npc
