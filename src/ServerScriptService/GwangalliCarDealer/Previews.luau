-- GwangalliCarDealer/Previews (server): the 3D models the catalog shows. Streaming is on, so the client cannot
-- rely on map cars being near; the server copies the exact car each entry delivers (the spawn system's kit
-- template / parked map car per kind, the ServerStorage.GwangalliCarModels template per showroom model) into
-- ReplicatedStorage.GwangalliCarDealerPreviews as a light, inert clone:
--   * kept: BaseParts (+ meshes, decals, textures, SurfaceAppearance); dropped: scripts, sounds, lights,
--     particles, constraints / joints, GUIs, prompts, humanoids, invisible colliders; over C.PREVIEW.maxParts
--     the Interior goes first, then the smallest parts
--   * every tag / attribute that other systems scan for (GarageDisplayCar, VehicleKind, NoDrive ...) is removed,
--     so nothing mistakes a preview for a real car
--   * normalised: bounding-box centre on the Y axis, wheels on y = 0, the front (PlateFront / headlights)
--     toward +Z. Attributes: PreviewKey, Kind, Size (Vector3 width, height, length)
-- Folder attribute Ready = true when every preview is built.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Previews = {}

local S: any
local C: any
local N: any
local Bridge: any
local folder: Folder? = nil

function Previews.init(shared: any, bridge: any)
	S = shared
	C = shared.Config
	N = shared.NAMES
	Bridge = bridge
end

local function keep(d: Instance): boolean
	return d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder") or d:IsA("Decal") or d:IsA("SurfaceAppearance") or d:IsA("DataModelMesh")
end

local DROP_NAMES = { DriveCollider = true, DriveBase = true }

local FRONT_HINTS = { "PlateFront", "Grille", "Headlight", "HeadLight", "HeadlightL", "Bonnet", "Hood", "Bumper_F", "FrontBumper" }

local function frontPart(m: Model): BasePart?
	for _, n in FRONT_HINTS do
		local p = m:FindFirstChild(n, true)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local lname = string.lower(d.Name)
			if string.find(lname, "headl", 1, true) or string.find(lname, "front", 1, true) then
				return d
			end
		end
	end
	return nil
end

local function build(src: Model, key: string, kind: string): Model?
	local okC, clone = pcall(function()
		local wasArch = src.Archivable
		src.Archivable = true
		local c = src:Clone()
		src.Archivable = wasArch
		return c
	end)
	if not okC or not clone then
		warn("[GwangalliCarDealer] could not copy " .. src:GetFullName() .. " for the preview " .. key)
		return nil
	end
	local m = clone :: Model
	-- strip
	for _, d in m:GetDescendants() do
		if d.Parent then
			if not keep(d) then
				d:Destroy()
			elseif d:IsA("BasePart") and (d.Transparency >= 0.98 or DROP_NAMES[d.Name]) then
				d:Destroy()
			end
		end
	end
	for _, d in m:GetDescendants() do
		for _, tag in d:GetTags() do
			d:RemoveTag(tag)
		end
	end
	for _, tag in m:GetTags() do
		m:RemoveTag(tag)
	end
	for name in m:GetAttributes() do
		m:SetAttribute(name, nil)
	end
	-- part budget
	local parts = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local cap = C.PREVIEW.maxParts
	if #parts > cap then
		local interior = m:FindFirstChild("Interior", true)
		if interior then
			interior:Destroy()
		end
		parts = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	if #parts > cap then
		table.sort(parts, function(a, b)
			local sa, sb = a.Size, b.Size
			return math.max(sa.X, sa.Y, sa.Z) < math.max(sb.X, sb.Y, sb.Z)
		end)
		local over = #parts - cap
		for i = 1, over do
			parts[i]:Destroy()
		end
	end
	local count = 0
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
			d.Massless = true
		end
	end
	if count == 0 then
		m:Destroy()
		return nil
	end
	-- normalise: front toward +Z, centre on the axis, bottom at y = 0
	local cf, size = m:GetBoundingBox()
	local long = if size.Z >= size.X then cf.LookVector else cf.RightVector
	long = Vector3.new(long.X, 0, long.Z)
	if long.Magnitude < 0.1 then
		long = Vector3.zAxis
	end
	long = long.Unit
	local fwd = long
	local fp = frontPart(m)
	local forwardKnown = false
	if fp then
		local d = fp.Position - cf.Position
		local along = d:Dot(long)
		if math.abs(along) > 0.3 then
			fwd = if along >= 0 then long else -long
			forwardKnown = true
		end
	end
	local length = math.max(size.X, size.Z)
	local width = math.min(size.X, size.Z)
	local height = size.Y
	local from = CFrame.lookAt(cf.Position, cf.Position + fwd)
	local to = CFrame.lookAt(Vector3.new(0, height / 2, 0), Vector3.new(0, height / 2, 1))
	m:PivotTo(to * from:Inverse() * m:GetPivot())
	m.Name = key
	m:SetAttribute(N.AttrPreviewKey, key)
	m:SetAttribute("Kind", kind)
	m:SetAttribute("Size", Vector3.new(width, height, length))
	m:SetAttribute(N.AttrForwardOk, forwardKnown)
	-- painted parts are found on the client by GS.paintParts (BodySide / CabSide / Hood keep their names)
	return m
end

function Previews.start()
	local GS = S.GS(30)
	if not GS then
		warn("[GwangalliCarDealer] GwangalliGarageShared missing: no car previews")
		return
	end
	local f = ReplicatedStorage:FindFirstChild(N.Previews)
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = N.Previews
		f:SetAttribute("Ready", false)
		f.Parent = ReplicatedStorage
	end
	folder = f :: Folder
	-- let the map, the spawn system and the showroom settle first
	while workspace.DistributedGameTime < C.WAIT.showroomSettle + 2 do
		task.wait(0.5)
	end
	local kinds = if type(GS.KIND_ORDER) == "table" then GS.KIND_ORDER else { "compact", "sedan", "suv", "truck", "van", "luxury" }
	local sources = Bridge.kitSources(kinds)
	local built = 0
	for _, kind in kinds do
		local key = "kit_" .. kind
		local src = sources[kind]
		if src and not (folder :: Folder):FindFirstChild(key) then
			local ok, res = pcall(build, src, key, kind)
			if ok and res then
				res.Parent = folder
				built += 1
			elseif not ok then
				warn("[GwangalliCarDealer] preview " .. key .. " failed: " .. tostring(res))
			end
			task.wait()
		end
	end
	if type(GS.MODELS) == "table" then
		for _, mi in GS.MODELS do
			local key = "model_" .. tostring(mi.id)
			local src = Bridge.modelTemplate(mi.id)
			if src and not (folder :: Folder):FindFirstChild(key) then
				local ok, res = pcall(build, src, key, mi.kind)
				if ok and res then
					res.Parent = folder
					built += 1
				end
				task.wait()
			end
		end
	end
	;(folder :: Folder):SetAttribute("Ready", true)
	print(string.format("[GwangalliCarDealer] %d car previews ready", built))
end

return Previews
