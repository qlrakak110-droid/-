--!optimize 2
-- GwangalliTextures (LocalScript, StarterPlayerScripts): runtime surface textures, nothing uploaded.
--
-- The place ships only data: ServerStorage.GwangalliTextures holds GTX1-compressed images made
-- offline by tools/assets/textures.py (fetched on wake-up, see "Data modules") (Korean facade tile, 고벽돌 tile, red face brick, grey / red
-- 보도블록 pavers, asphalt wear, lane-paint wear, wall grime, granite, marble, wood planks, leather).
-- On clients where the in-experience Image API works (AssetService:CreateEditableImage; the creator
-- must be 13+ ID-verified and have "Mesh / Image APIs" enabled for the experience) this script
--   1. decodes every texture once (time sliced, never more than ~2.5 ms per frame) into ONE
--      EditableImage per texture at the tier size (low: 256 px, mid / high: 512 px),
--   2. lays them as Texture instances (ColorMapContent = Content.fromObject(image), real-world
--      StudsPerTile, world-aligned offsets, Transparency so the built-in 2022 PBR material still
--      shows through, Color3 tint towards the part colour) over the relevant faces of NEARBY parts:
--        Asphalt tops -> asphalt_wear, road markings -> lane_wear, Pavement tops -> pavers,
--        CeramicTiles facades -> tile_light / tile_brick, Brick facades -> brick_red,
--        Concrete / Plaster / Limestone / panel facades -> grime, Granite -> granite,
--        Marble -> marble, WoodPlanks floors -> wood_planks, Leather -> leather,
--        CeramicTiles floors -> granite (porcelain look)
--      within the tier radius (low 40 / mid 80 / high 80 studs; interiors 20 / 40 / 50), nearest
--      first, capped per tier (low 150 / mid 400 / high 800 Texture instances), adding / removing
--      them in small batches as the camera moves (spatial grid, ~1.2 ms per frame budget).
-- When the API is unavailable, or anything in the probe fails, the script does nothing at all and
-- the game looks exactly as built (part colours + built-in materials).
--
-- Streaming: parts are discovered through ONE Workspace.DescendantAdded listener (cheap class /
-- material check, queued) plus a chunked initial walk; DescendantRemoving drops them again. Only
-- anchored plain block Parts are used; the club / bowling show elements, auto doors, near-LOD
-- detail, RoomDepth volumes, neon / LED / signal parts and anything under a Humanoid are skipped.
-- Parts are never modified: only Texture children named "GwangalliTex" are added.
--
-- Switches: workspace attribute GwangalliTexturesOff = true disables (and clears) everything.
-- The script's attribute "Status" reports what it is doing (dev console / explorer).
-- Quality tier: ReplicatedStorage.GwangalliQuality (fallback: touch without keyboard = low, else mid).
-- The low tier (phones) keeps the script dormant (see Start).

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TAG = "[GwangalliTextures]"
local TEX_NAME = "GwangalliTex"

local function setStatus(s: string)
	pcall(function()
		script:SetAttribute("Status", s)
	end)
end

if not RunService:IsClient() then
	return
end
if workspace:GetAttribute("GwangalliTexturesOff") == true then
	setStatus("off (workspace.GwangalliTexturesOff)")
	return
end

---------------------------------------------------------------------------------------------------
-- Tier budgets
---------------------------------------------------------------------------------------------------
type TierCfg = {
	radius: number, -- street / facade textures (studs, camera to part box)
	interiorRadius: number, -- floors, tables, sofas
	hysteresis: number, -- extra distance before an applied part is dropped again
	maxTextures: number, -- Texture instances in total
	maxMarkings: number, -- of which on road markings
	maxInterior: number, -- of which in the interior category
	half: boolean, -- 512 px sources decoded at 256 px
	perFrame: number, -- Texture creations per frame
	applyMs: number, -- per-frame budget for creating / destroying textures
	decodeMs: number, -- per-frame budget for decoding
	updateHz: number,
	skip: { [string]: boolean }, -- textures not built on this tier
}

local TIERS: { [string]: TierCfg } = {
	low = {
		radius = 40, interiorRadius = 20, hysteresis = 6,
		maxTextures = 150, maxMarkings = 30, maxInterior = 20,
		half = true, perFrame = 8, applyMs = 0.8, decodeMs = 2.0, updateHz = 3,
		skip = { leather = true },
	},
	mid = {
		radius = 80, interiorRadius = 40, hysteresis = 10,
		maxTextures = 400, maxMarkings = 80, maxInterior = 60,
		half = false, perFrame = 16, applyMs = 1.2, decodeMs = 2.5, updateHz = 4,
		skip = {},
	},
	high = {
		radius = 80, interiorRadius = 50, hysteresis = 12,
		maxTextures = 800, maxMarkings = 150, maxInterior = 120,
		half = false, perFrame = 28, applyMs = 1.5, decodeMs = 2.5, updateHz = 5,
		skip = {},
	},
}

-- decode order: most visible first (roads, sidewalks, facades), interiors last
local ORDER = {
	"asphalt_wear", "paver_grey", "paver_red", "grime", "tile_light", "tile_brick", "brick_red",
	"granite", "lane_wear", "marble", "wood_planks", "leather",
}

---------------------------------------------------------------------------------------------------
-- Quality tier (shared module, pcall-required, with a fallback)
---------------------------------------------------------------------------------------------------
local Quality: any = nil
do
	local m = ReplicatedStorage:FindFirstChild("GwangalliQuality") or ReplicatedStorage:WaitForChild("GwangalliQuality", 10)
	if m and m:IsA("ModuleScript") then
		local ok, q = pcall(require, m)
		if ok and type(q) == "table" and type(q.get) == "function" then
			Quality = q
		end
	end
end

local function currentTier(): string
	if Quality then
		local ok, t = pcall(Quality.get)
		if ok and TIERS[t] then
			return t
		end
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "low"
	end
	return "mid"
end

---------------------------------------------------------------------------------------------------
-- Capability probe: every Editable* / Content call is behind pcall; any failure = do nothing
---------------------------------------------------------------------------------------------------
local contentProp: string? = nil

local function probe(): (boolean, string)
	local okLib, fromObject = pcall(function()
		return (Content :: any).fromObject
	end)
	if not okLib or type(fromObject) ~= "function" then
		return false, "Content.fromObject missing"
	end
	local ok, img = pcall(function()
		return (AssetService :: any):CreateEditableImage({ Size = Vector2.new(4, 4) })
	end)
	if not ok then
		return false, "CreateEditableImage failed: " .. tostring(img)
	end
	if img == nil then
		return false, "CreateEditableImage returned nil"
	end
	local okW, errW = pcall(function()
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(4, 4), buffer.create(64))
	end)
	if not okW then
		pcall(function()
			img:Destroy()
		end)
		return false, "WritePixelsBuffer failed: " .. tostring(errW)
	end
	local okC, content = pcall(fromObject, img)
	if not okC or content == nil then
		pcall(function()
			img:Destroy()
		end)
		return false, "Content.fromObject failed: " .. tostring(content)
	end
	local t = Instance.new("Texture")
	for _, prop in { "ColorMapContent", "TextureContent" } do
		if pcall(function()
			(t :: any)[prop] = content
		end) then
			contentProp = prop
			break
		end
	end
	t:Destroy()
	pcall(function()
		img:Destroy()
	end)
	if not contentProp then
		return false, "Texture content properties not writable"
	end
	return true, contentProp :: string
end


---------------------------------------------------------------------------------------------------
-- Data modules (fetched only when the script wakes up)
---------------------------------------------------------------------------------------------------
-- The GTX1 data (~1.3 MB of strings) lives in ServerStorage.GwangalliTextures: phones on the low
-- tier never download or load it. Once this script wakes up (tier mid / high, Image API present),
-- it fires ReplicatedStorage.GwangalliTexturesRequest and the server
-- (ServerScriptService.GwangalliTextureData) copies the folder into this player's PlayerGui
-- (ScreenGui "GwangalliTexturesData": replicated to this player only). A place that still ships the
-- folder in ReplicatedStorage (older build, Studio test) is used directly.
type Def = {
	name: string, width: number, height: number, repeatU: number, repeatV: number,
	tint: number, transparency: number, overlay: boolean, fitV: boolean,
	mean: { number }, palette: string, blocks: string,
}

local Codec: any = nil
local defs: { [string]: Def } = {}

local function findDataFolder(): Instance?
	local f = ReplicatedStorage:FindFirstChild("GwangalliTextures")
	if f then
		return f
	end
	local player = game:GetService("Players").LocalPlayer
	local pg = player and (player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 30))
	if not pg then
		return nil
	end
	local holder = pg:FindFirstChild("GwangalliTexturesData")
	if not holder then
		local req = ReplicatedStorage:WaitForChild("GwangalliTexturesRequest", 30)
		if not (req and req:IsA("RemoteEvent")) then
			return nil
		end
		req:FireServer()
		holder = pg:WaitForChild("GwangalliTexturesData", 60)
	end
	return holder and holder:WaitForChild("GwangalliTextures", 30)
end

-- Fills Codec / defs; false (with the status set) when the data is missing or broken.
local function loadData(): boolean
	setStatus("loading texture data")
	local dataFolder = findDataFolder()
	if not dataFolder then
		setStatus("inactive: texture data missing (ServerStorage.GwangalliTextures / GwangalliTextureData)")
		return false
	end
	local cm = dataFolder:FindFirstChild("Codec") or dataFolder:WaitForChild("Codec", 10)
	if cm and cm:IsA("ModuleScript") then
		local ok, c = pcall(require, cm)
		if ok and type(c) == "table" and type(c.decode) == "function" and type(c.base64) == "function" then
			Codec = c
		end
	end
	if not Codec then
		setStatus("inactive: Codec missing")
		warn(TAG, "GwangalliTextures.Codec missing or broken; runtime textures disabled")
		return false
	end
	for _, m in dataFolder:GetChildren() do
		if m:IsA("ModuleScript") and m.Name ~= "Codec" then
			local ok, d = pcall(require, m)
			if ok and type(d) == "table" and d.format == "GTX1" and type(d.name) == "string"
				and type(d.width) == "number" and type(d.height) == "number"
				and d.width % 4 == 0 and d.height % 4 == 0 and d.width <= 1024 and d.height <= 1024
				and type(d.palette) == "string" and type(d.blocks) == "string"
				and type(d.repeatU) == "number" and d.repeatU > 0 and type(d.repeatV) == "number" and d.repeatV > 0
				and type(d.mean) == "table" then
				defs[d.name] = d :: any
			end
		end
	end
	if next(defs) == nil then
		setStatus("inactive: no texture data")
		return false
	end
	return true
end

---------------------------------------------------------------------------------------------------
-- Images (one EditableImage per texture, shared by every Texture instance)
---------------------------------------------------------------------------------------------------
type Img = { image: any, content: any, def: Def, w: number, h: number, gen: number }

local images: { [string]: Img } = {}
local imageGen = 0
local failed: { [string]: string } = {}
local budgetExhausted = false
local tierName = currentTier()
local cfg: TierCfg = TIERS[tierName]
local enabled = true

local function destroyImage(img: Img)
	pcall(function()
		img.image:Destroy()
	end)
end

local decodeSlice = os.clock()
local function decodeYield()
	if os.clock() - decodeSlice > cfg.decodeMs / 1000 then
		task.wait()
		decodeSlice = os.clock()
	end
end

local imagesChanged = false

local function buildImages(gen: number)
	for _, name in ORDER do
		if gen ~= imageGen or not enabled then
			return
		end
		local def = defs[name]
		if def and not cfg.skip[name] and not images[name] and not failed[name] and not budgetExhausted then
			decodeSlice = os.clock()
			local ok, err = pcall(function()
				local pal = Codec.base64(def.palette, decodeYield)
				local blocks = Codec.base64(def.blocks, decodeYield)
				local half = cfg.half and def.width > 256
				local pixels, w, h = Codec.decode(def, pal, blocks, half, decodeYield)
				if gen ~= imageGen or not enabled then
					return
				end
				local image = (AssetService :: any):CreateEditableImage({ Size = Vector2.new(w, h) })
				if image == nil then
					budgetExhausted = true
					error("CreateEditableImage returned nil (memory budget)")
				end
				local okW, errW = pcall(function()
					image:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)
				end)
				if not okW then
					pcall(function()
						image:Destroy()
					end)
					error("WritePixelsBuffer: " .. tostring(errW))
				end
				local content = (Content :: any).fromObject(image)
				images[name] = { image = image, content = content, def = def, w = w, h = h, gen = gen }
				imagesChanged = true
			end)
			if not ok then
				failed[name] = tostring(err)
				warn(TAG, "texture " .. name .. " disabled: " .. tostring(err))
				if string.find(string.lower(tostring(err)), "budget") or string.find(string.lower(tostring(err)), "memory") then
					budgetExhausted = true
				end
			end
			task.wait()
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Part rules
---------------------------------------------------------------------------------------------------
type Rule = {
	tex: string,
	faces: string, -- "top" | "vertical" | "any"
	minArea: number,
	cat: string, -- "street" | "marking" | "interior"
	transparency: number?, -- overrides the texture default
	tint: number?, -- overrides the texture default
	maxFaces: number,
}

local RULES: { [string]: Rule } = {
	asphalt = { tex = "asphalt_wear", faces = "top", minArea = 32, cat = "street", transparency = 0.05, maxFaces = 1 },
	marking = { tex = "lane_wear", faces = "top", minArea = 0.3, cat = "marking", transparency = 0.1, maxFaces = 1 },
	paverGrey = { tex = "paver_grey", faces = "top", minArea = 6, cat = "street", maxFaces = 1 },
	paverRed = { tex = "paver_red", faces = "top", minArea = 6, cat = "street", maxFaces = 1 },
	grimeConcrete = { tex = "grime", faces = "vertical", minArea = 8, cat = "street", transparency = 0.15, maxFaces = 2 },
	grimePlaster = { tex = "grime", faces = "vertical", minArea = 8, cat = "street", transparency = 0.25, maxFaces = 2 },
	grimeStone = { tex = "grime", faces = "vertical", minArea = 8, cat = "street", transparency = 0.3, maxFaces = 2 },
	grimePanel = { tex = "grime", faces = "vertical", minArea = 8, cat = "street", transparency = 0.4, maxFaces = 2 },
	tileLight = { tex = "tile_light", faces = "vertical", minArea = 5, cat = "street", maxFaces = 2 },
	tileBrown = { tex = "tile_brick", faces = "vertical", minArea = 5, cat = "street", maxFaces = 2 },
	tileFloor = { tex = "granite", faces = "top", minArea = 6, cat = "interior", transparency = 0.3, maxFaces = 1 },
	brick = { tex = "brick_red", faces = "vertical", minArea = 5, cat = "street", maxFaces = 2 },
	brickPainted = { tex = "brick_red", faces = "vertical", minArea = 5, cat = "street", tint = 1, transparency = 0.2, maxFaces = 2 },
	granite = { tex = "granite", faces = "any", minArea = 3, cat = "street", maxFaces = 2 },
	marble = { tex = "marble", faces = "any", minArea = 1.5, cat = "interior", maxFaces = 2 },
	wood = { tex = "wood_planks", faces = "top", minArea = 6, cat = "interior", maxFaces = 1 },
	leather = { tex = "leather", faces = "any", minArea = 0.6, cat = "interior", maxFaces = 3 },
}

local MARKING_NAMES: { [string]: boolean } = {}
for _, n in {
	"CrosswalkBar", "CentreLine", "LaneDash", "LaneArrow", "LaneLine", "EdgeLine", "StopLine",
	"BikeCentreDash", "BikeLaneLine", "BayLine", "MedianLine", "BusLaneLine", "StallLine", "ParkingLine",
	"LaneLineSolid", "WalkStripLine", "ParkingBayLine", "ParkingBayLines", "HumpStripe", "AlleyEdgeLine",
	"BusStopKerbLine",
} do
	MARKING_NAMES[n] = true
end

-- exterior wall pieces built by build/kit/arch.luau and the district builders
local FACADE_NAMES: { [string]: boolean } = {}
for _, n in {
	"Pier", "CornerPier", "Spandrel", "Lintel", "Parapet", "ParapetCap", "PartyWall", "GroundSide",
	"GroundBack", "GroundWall", "SideWall", "EndWall", "Wall", "WallPanel", "Mass", "GroundMass", "Villa",
	"HouseBody", "Body", "Penthouse", "StairWall", "RooftopRoom", "Divider", "BalconySlab",
	"BalconyParapet", "Crown", "CrownBand", "SlabEdge", "SlabBand", "Coping", "WallCoping", "WaveWall",
	"PoolWall", "PilotisBack", "Pilotis", "PierColumn", "MedianBarrier", "Plinth", "Foundation",
	"Apron", "Cornice", "BorderBand", "StoneBase", "FencePlinth", "GatePier", "Lobby",
} do
	FACADE_NAMES[n] = true
end

-- interior / hidden volumes that never get facade grime
local INTERIOR_NAMES: { [string]: boolean } = {}
for _, n in {
	"Core", "GroundCore", "RoomSlab", "ShopBackWall", "Ceiling", "PilotisCeiling", "Partition",
	"PartitionWall", "ShopPartition", "ShopLight", "Roof", "RoofSlab", "Slab", "Floor", "ParkingFloor",
} do
	INTERIOR_NAMES[n] = true
end

local EXCLUDE_TAGS: { [string]: boolean } = {}
for _, n in {
	"ClubRuntime", "ClubLight", "ClubFloorTile", "ClubLaser", "ClubNPC", "ClubFX", "ClubMirrorRay",
	"ClubShowBeam", "ClubSparkler", "ClubCO2", "ClubConfetti", "ClubHaze", "ClubZone",
	"BowlingLane", "BowlingCosmic", "NightNeon", "NeonTube", "NightGlow", "LEDScreen", "AutoDoor",
	"BridgeLED", "TrafficSignal", "PedSignal", "RoomDepth", "NearLOD", "EditorOnly", "Window",
	"CityLight", "InteriorLight",
} do
	EXCLUDE_TAGS[n] = true
end

local M = Enum.Material
local MAT_ASPHALT, MAT_PAVEMENT, MAT_SMOOTH = M.Asphalt, M.Pavement, M.SmoothPlastic
local MAT_CONCRETE, MAT_PLASTER, MAT_LIMESTONE = M.Concrete, M.Plaster, M.Limestone
local MAT_TILES, MAT_BRICK, MAT_GRANITE = M.CeramicTiles, M.Brick, M.Granite
local MAT_MARBLE, MAT_WOOD, MAT_LEATHER = M.Marble, M.WoodPlanks, M.Leather
local CANDIDATE_MATS: { [EnumItem]: boolean } = {
	[MAT_ASPHALT] = true, [MAT_PAVEMENT] = true, [MAT_SMOOTH] = true, [MAT_CONCRETE] = true,
	[MAT_PLASTER] = true, [MAT_LIMESTONE] = true, [MAT_TILES] = true, [MAT_BRICK] = true,
	[MAT_GRANITE] = true, [MAT_MARBLE] = true, [MAT_WOOD] = true, [MAT_LEATHER] = true,
}

local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

local function isFlat(size: Vector3): boolean
	-- thin horizontal slab (floor / deck / table top) in its own frame
	return size.Y <= math.min(size.X, size.Z) * 0.5
end

local function classify(part: BasePart): Rule?
	local mat = part.Material
	if not CANDIDATE_MATS[mat] then
		return nil
	end
	local name = part.Name
	local color = part.Color
	if mat == MAT_ASPHALT then
		return RULES.asphalt
	elseif mat == MAT_SMOOTH then
		if MARKING_NAMES[name] then
			return RULES.marking
		end
		if FACADE_NAMES[name] and luminance(color) >= 0.45 then
			return RULES.grimePanel
		end
		return nil
	elseif mat == MAT_PAVEMENT then
		if color.R - color.B > 0.12 and color.R > color.G + 0.06 then
			return RULES.paverRed
		end
		return RULES.paverGrey
	elseif mat == MAT_CONCRETE then
		if INTERIOR_NAMES[name] or luminance(color) < 0.3 then
			return nil
		end
		return RULES.grimeConcrete
	elseif mat == MAT_PLASTER then
		if FACADE_NAMES[name] and luminance(color) >= 0.35 then
			return RULES.grimePlaster
		end
		return nil
	elseif mat == MAT_LIMESTONE then
		if FACADE_NAMES[name] then
			return RULES.grimeStone
		end
		return nil
	elseif mat == MAT_TILES then
		if isFlat(part.Size) and not FACADE_NAMES[name] then
			return RULES.tileFloor
		end
		return if luminance(color) >= 0.5 then RULES.tileLight else RULES.tileBrown
	elseif mat == MAT_BRICK then
		return if luminance(color) >= 0.5 then RULES.brickPainted else RULES.brick
	elseif mat == MAT_GRANITE then
		return RULES.granite
	elseif mat == MAT_MARBLE then
		return RULES.marble
	elseif mat == MAT_WOOD then
		return RULES.wood
	elseif mat == MAT_LEATHER then
		return RULES.leather
	end
	return nil
end

-- Ancestry exclusion (cached per ancestor instance)
local exclCache: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function selfExcluded(inst: Instance): boolean
	for _, tag in inst:GetTags() do
		if EXCLUDE_TAGS[tag] then
			return true
		end
	end
	if inst:GetAttribute("LOD") == "near" or inst:GetAttribute("OpenOffset") ~= nil then
		return true
	end
	if inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") then
		return true
	end
	return false
end

local function excluded(part: BasePart): boolean
	if selfExcluded(part) then
		return true
	end
	local chain = {}
	local cur = part.Parent
	local result = false
	while cur and cur ~= workspace do
		local c = exclCache[cur]
		if c ~= nil then
			result = c
			break
		end
		table.insert(chain, cur)
		if selfExcluded(cur) then
			result = true
			break
		end
		cur = cur.Parent
	end
	if cur == nil then
		return true -- not under Workspace (any more)
	end
	for _, a in chain do
		exclCache[a] = result
	end
	return result
end

---------------------------------------------------------------------------------------------------
-- Registry: records in a spatial grid (XZ cells), faces precomputed (anchored parts do not move)
---------------------------------------------------------------------------------------------------
type Face = {
	id: Enum.NormalId, n: Vector3, c: Vector3, u: Vector3, v: Vector3, w: number, h: number, top: boolean,
}
type Rec = {
	part: BasePart, rule: Rule, color: Color3, pos: Vector3,
	rx: Vector3, ry: Vector3, rz: Vector3, hx: number, hy: number, hz: number,
	minX: number, maxX: number, minZ: number, maxZ: number,
	faces: { Face }, cells: { number }, stamp: number, dist: number,
	applied: { [Enum.NormalId]: Texture }?, nApplied: number, want: number,
}

local CELL = 32
local MAX_CELLS = 1024
local grid: { [number]: { Rec } } = {}
local recOf: { [Instance]: Rec } = {}
local appliedRecs: { [Rec]: boolean } = {}
local appliedTotal = 0
local appliedByCat: { [string]: number } = { street = 0, marking = 0, interior = 0 }
local registered = 0
local dirty = true

local function cellKey(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

local NORMAL_TOP, NORMAL_BOTTOM = Enum.NormalId.Top, Enum.NormalId.Bottom
local NORMAL_FRONT, NORMAL_BACK = Enum.NormalId.Front, Enum.NormalId.Back
local NORMAL_RIGHT, NORMAL_LEFT = Enum.NormalId.Right, Enum.NormalId.Left

local function buildFaces(cf: CFrame, size: Vector3, rule: Rule): { Face }
	local rx, ry, rz = cf.RightVector, cf.UpVector, cf.LookVector
	local p = cf.Position
	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	-- { id, normal, centre, U axis (viewer's right), V axis (down the image), width, height }
	local cands = {
		{ NORMAL_TOP, ry, p + ry * hy, rx, -rz, size.X, size.Z },
		{ NORMAL_BOTTOM, -ry, p - ry * hy, rx, rz, size.X, size.Z },
		{ NORMAL_FRONT, rz, p + rz * hz, -rx, -ry, size.X, size.Y },
		{ NORMAL_BACK, -rz, p - rz * hz, rx, -ry, size.X, size.Y },
		{ NORMAL_RIGHT, rx, p + rx * hx, rz, -ry, size.Z, size.Y },
		{ NORMAL_LEFT, -rx, p - rx * hx, -rz, -ry, size.Z, size.Y },
	}
	local out = {}
	for _, c in cands do
		local n: Vector3 = c[2]
		local w: number, h: number = c[6], c[7]
		local area = w * h
		if area >= rule.minArea then
			local isTop = n.Y > 0.8
			local isVert = math.abs(n.Y) < 0.35
			local okFace = false
			if rule.faces == "top" then
				okFace = isTop
			elseif rule.faces == "vertical" then
				okFace = isVert and math.min(w, h) >= 0.8
			else
				okFace = isTop or (isVert and math.min(w, h) >= 0.5)
			end
			if okFace then
				-- V axis of a side face must point down the world for the grime to hang right
				local v: Vector3 = c[5]
				if isVert and v.Y > -0.5 then
					okFace = rule.tex ~= "grime"
				end
				if okFace then
					table.insert(out, { id = c[1], n = n, c = c[3], u = c[4], v = v, w = w, h = h, top = isTop })
				end
			end
		end
	end
	return out
end

local function removeFromCells(rec: Rec)
	for _, key in rec.cells do
		local list = grid[key]
		if list then
			local i = table.find(list, rec)
			if i then
				list[i] = list[#list]
				list[#list] = nil
			end
			if #list == 0 then
				grid[key] = nil
			end
		end
	end
	table.clear(rec.cells)
end

local function dropTextures(rec: Rec)
	local applied = rec.applied
	if applied then
		for _, t in applied do
			task.defer(function()
				pcall(t.Destroy, t)
			end)
		end
		rec.applied = nil
		appliedTotal -= rec.nApplied
		appliedByCat[rec.rule.cat] -= rec.nApplied
		rec.nApplied = 0
	end
	appliedRecs[rec] = nil
end

local function unregister(rec: Rec)
	if recOf[rec.part] ~= rec then
		return
	end
	recOf[rec.part] = nil
	removeFromCells(rec)
	dropTextures(rec)
	registered -= 1
end

local function register(part: BasePart, rule: Rule)
	local cf, size = part.CFrame, part.Size
	local faces = buildFaces(cf, size, rule)
	if #faces == 0 then
		return
	end
	local rx, ry, rz = cf.RightVector, cf.UpVector, cf.LookVector
	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	local p = cf.Position
	local ex = math.abs(rx.X) * hx + math.abs(ry.X) * hy + math.abs(rz.X) * hz
	local ez = math.abs(rx.Z) * hx + math.abs(ry.Z) * hy + math.abs(rz.Z) * hz
	local minX, maxX, minZ, maxZ = p.X - ex, p.X + ex, p.Z - ez, p.Z + ez
	local cx0, cx1 = math.floor(minX / CELL), math.floor(maxX / CELL)
	local cz0, cz1 = math.floor(minZ / CELL), math.floor(maxZ / CELL)
	if (cx1 - cx0 + 1) * (cz1 - cz0 + 1) > MAX_CELLS then
		return -- enormous ground plates: not worth it
	end
	local rec: Rec = {
		part = part, rule = rule, color = part.Color, pos = p,
		rx = rx, ry = ry, rz = rz, hx = hx, hy = hy, hz = hz,
		minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ,
		faces = faces, cells = {}, stamp = 0, dist = math.huge,
		applied = nil, nApplied = 0, want = 0,
	}
	for cx = cx0, cx1 do
		for cz = cz0, cz1 do
			local key = cellKey(cx, cz)
			local list = grid[key]
			if not list then
				list = {}
				grid[key] = list
			end
			table.insert(list, rec)
			table.insert(rec.cells, key)
		end
	end
	recOf[part] = rec
	registered += 1
	dirty = true
end

local function consider(inst: Instance)
	if recOf[inst] or inst.ClassName ~= "Part" then
		return
	end
	local part = inst :: Part
	if part.Parent == nil or not part.Anchored or part.Shape ~= Enum.PartType.Block then
		return
	end
	if part.Transparency > 0.2 or part.Name == TEX_NAME then
		return
	end
	local rule = classify(part)
	if not rule or not defs[rule.tex] then
		return
	end
	if excluded(part) then
		return
	end
	register(part, rule)
end

-- Discovery: the event handlers only queue; the queue is drained with a time budget.
local pending: { Instance } = {}
local pendingHead = 1

local function onAdded(inst: Instance)
	if inst.ClassName == "Part" then
		pending[#pending + 1] = inst
	end
end

local function onRemoving(inst: Instance)
	local rec = recOf[inst]
	if rec then
		unregister(rec)
	end
end

local function drainPending(deadline: number)
	local n = #pending
	while pendingHead <= n do
		local inst = pending[pendingHead]
		pending[pendingHead] = nil :: any
		pendingHead += 1
		local ok, err = pcall(consider, inst)
		if not ok then
			warn(TAG, "consider failed: " .. tostring(err))
		end
		if pendingHead % 16 == 0 and os.clock() > deadline then
			break
		end
	end
	if pendingHead > #pending then
		table.clear(pending)
		pendingHead = 1
	end
end

local function initialScan()
	local visited = 0
	local slice = os.clock()
	local function tick()
		visited += 1
		if visited % 200 == 0 and os.clock() - slice > 0.001 then
			task.wait()
			slice = os.clock()
		end
	end
	for _, top in workspace:GetChildren() do
		if top:IsA("Terrain") or top:IsA("Camera") or top.Parent == nil then
			continue
		end
		onAdded(top)
		for _, district in top:GetChildren() do
			if district.Parent == nil then
				continue
			end
			onAdded(district)
			for _, child in district:GetChildren() do
				if child.Parent == nil then
					continue
				end
				onAdded(child)
				for _, d in child:GetDescendants() do
					onAdded(d)
					tick()
				end
				tick()
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Texture instances
---------------------------------------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)

local function tintFor(def: Def, rule: Rule, color: Color3): Color3
	local k = rule.tint or def.tint or 0
	if k <= 0 or def.overlay then
		return WHITE
	end
	local m = def.mean
	local r = math.clamp(color.R / math.max(m[1], 0.02), 0, 1)
	local g = math.clamp(color.G / math.max(m[2], 0.02), 0, 1)
	local b = math.clamp(color.B / math.max(m[3], 0.02), 0, 1)
	return Color3.new(1 + (r - 1) * k, 1 + (g - 1) * k, 1 + (b - 1) * k)
end

local function makeTexture(rec: Rec, face: Face, img: Img): Texture?
	local def = img.def
	local tu, tv = def.repeatU, def.repeatV
	local offU, offV
	local sLeft = face.c:Dot(face.u) - face.w * 0.5
	offU = sLeft % tu
	if def.fitV then
		-- the image hangs from the top edge of the face; tall faces repeat it once per storey
		local fh = math.max(face.h, 1)
		tv = if fh <= 14 then fh else fh / math.max(1, math.floor(fh / 11 + 0.5))
		offV = 0
	else
		local sTop = face.c:Dot(face.v) - face.h * 0.5
		offV = sTop % tv
	end
	local t = Instance.new("Texture")
	t.Name = TEX_NAME
	t.Face = face.id
	t.StudsPerTileU = tu
	t.StudsPerTileV = tv
	t.OffsetStudsU = offU
	t.OffsetStudsV = offV
	t.Transparency = rec.rule.transparency or def.transparency or 0
	t.Color3 = tintFor(def, rec.rule, rec.color)
	pcall(function()
		t.ZIndex = 0 -- under any decal the builders placed on the same face
	end)
	;(t :: any)[contentProp :: string] = img.content
	t.Parent = rec.part
	return t
end

---------------------------------------------------------------------------------------------------
-- Selection (periodic) and application (per frame, budgeted)
---------------------------------------------------------------------------------------------------
local addQueue: { { rec: Rec, face: Face } } = {}
local addHead = 1
local updateStamp = 0
local lastCam: Vector3? = nil
local lastUpdate = 0

local function obbDistance(rec: Rec, cam: Vector3): number
	local d = cam - rec.pos
	local rx, ry, rz = rec.rx, rec.ry, rec.rz
	local lx = math.abs(d.X * rx.X + d.Y * rx.Y + d.Z * rx.Z) - rec.hx
	local ly = math.abs(d.X * ry.X + d.Y * ry.Y + d.Z * ry.Z) - rec.hy
	local lz = math.abs(d.X * rz.X + d.Y * rz.Y + d.Z * rz.Z) - rec.hz
	lx = if lx > 0 then lx else 0
	ly = if ly > 0 then ly else 0
	lz = if lz > 0 then lz else 0
	return math.sqrt(lx * lx + ly * ly + lz * lz)
end

local BUCKET = 4
local buckets: { { Rec } } = {}
local dead: { Rec } = {}

local function limitFor(rec: Rec): number
	local r = if rec.rule.cat == "interior" then cfg.interiorRadius elseif rec.rule.cat == "marking" then math.min(cfg.radius, 50) else cfg.radius
	if rec.nApplied > 0 then
		r += cfg.hysteresis
	end
	return r
end

local function facingFaces(rec: Rec, cam: Vector3, out: { Face }): number
	local k = 0
	local maxF = rec.rule.maxFaces
	-- already applied faces first (keeps them stable), then the others that face the camera
	local applied = rec.applied
	for _, f in rec.faces do
		if applied and applied[f.id] then
			k += 1
			out[k] = f
		end
	end
	for _, f in rec.faces do
		if k >= maxF then
			break
		end
		if not (applied and applied[f.id]) then
			local c, n = f.c, f.n
			local facing = f.top or ((cam.X - c.X) * n.X + (cam.Y - c.Y) * n.Y + (cam.Z - c.Z) * n.Z) > 0
			if facing then
				k += 1
				out[k] = f
			end
		end
	end
	return k
end

local tmpFaces: { Face } = {}

local function update()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cam = camera.CFrame.Position
	updateStamp += 1
	local stamp = updateStamp
	local reach = math.max(cfg.radius, cfg.interiorRadius) + cfg.hysteresis
	local cx0, cx1 = math.floor((cam.X - reach) / CELL), math.floor((cam.X + reach) / CELL)
	local cz0, cz1 = math.floor((cam.Z - reach) / CELL), math.floor((cam.Z + reach) / CELL)
	local nb = math.ceil(reach / BUCKET) + 1
	for i = 1, nb do
		local b = buckets[i]
		if b then
			table.clear(b)
		else
			buckets[i] = {}
		end
	end
	local reach2 = reach * reach
	for cx = cx0, cx1 do
		for cz = cz0, cz1 do
			local list = grid[cellKey(cx, cz)]
			if list then
				for i = 1, #list do
					local rec = list[i]
					if rec.stamp ~= stamp then
						rec.stamp = stamp
						if rec.part.Parent == nil then
							table.insert(dead, rec)
						else
							local dx = math.max(rec.minX - cam.X, cam.X - rec.maxX, 0)
							local dz = math.max(rec.minZ - cam.Z, cam.Z - rec.maxZ, 0)
							if dx * dx + dz * dz <= reach2 and images[rec.rule.tex] then
								local d = obbDistance(rec, cam)
								if d <= limitFor(rec) then
									rec.dist = d
									local bi = math.floor(d / BUCKET) + 1
									table.insert(buckets[math.min(bi, nb)], rec)
								end
							end
						end
					end
				end
			end
		end
	end
	for _, rec in dead do
		unregister(rec)
	end
	table.clear(dead)

	-- choose nearest first within the caps
	local total, byCat = 0, { street = 0, marking = 0, interior = 0 }
	local capCat = { street = cfg.maxTextures, marking = cfg.maxMarkings, interior = cfg.maxInterior }
	for bi = 1, nb do
		for _, rec in buckets[bi] do
			local k = facingFaces(rec, cam, tmpFaces)
			local cat = rec.rule.cat
			if k > 0 and total + k <= cfg.maxTextures and byCat[cat] + k <= capCat[cat] then
				total += k
				byCat[cat] += k
				rec.want = stamp
				for i = 1, k do
					local f = tmpFaces[i]
					if not (rec.applied and rec.applied[f.id]) then
						table.insert(addQueue, { rec = rec, face = f })
					end
				end
			end
		end
	end
	-- drop everything that is no longer wanted (out of range, capped, streamed out, tier change)
	for rec in appliedRecs do
		if rec.want ~= stamp then
			dropTextures(rec)
		end
	end
	lastCam = cam
	lastUpdate = os.clock()
	dirty = false
end

local function applyQueued(deadline: number)
	local made = 0
	while addHead <= #addQueue do
		local item = addQueue[addHead]
		addQueue[addHead] = nil :: any
		addHead += 1
		local rec, face = item.rec, item.face
		local img = images[rec.rule.tex]
		if img and rec.want == updateStamp and recOf[rec.part] == rec and rec.part.Parent ~= nil
			and not (rec.applied and rec.applied[face.id]) and appliedTotal < cfg.maxTextures then
			local ok, t = pcall(makeTexture, rec, face, img)
			if ok and t then
				if not rec.applied then
					rec.applied = {}
				end
				(rec.applied :: any)[face.id] = t
				rec.nApplied += 1
				appliedTotal += 1
				appliedByCat[rec.rule.cat] += 1
				appliedRecs[rec] = true
			elseif not ok then
				warn(TAG, "Texture creation failed, runtime textures stopped: " .. tostring(t))
				enabled = false
				return
			end
			made += 1
			if made >= cfg.perFrame or os.clock() > deadline then
				break
			end
		end
	end
	if addHead > #addQueue then
		table.clear(addQueue)
		addHead = 1
	end
end

local function clearAll()
	for rec in appliedRecs do
		dropTextures(rec)
	end
	table.clear(addQueue)
	addHead = 1
end

local function rebuildForTier()
	imageGen += 1
	clearAll()
	local old = images
	images = {}
	table.clear(failed)
	budgetExhausted = false
	task.defer(function()
		for _, img in old do
			destroyImage(img)
		end
	end)
	local gen = imageGen
	task.spawn(buildImages, gen)
end

---------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------
if not game:IsLoaded() then
	game.Loaded:Wait()
end
task.wait(1)

-- Phones (low tier) keep the built look and pay nothing: runtime textures add a draw call per
-- textured face (a Texture takes the part out of instanced batching), EditableImage memory, a
-- second pair of Workspace-wide DescendantAdded / DescendantRemoving handlers (one call per
-- streamed instance) and up to ~3 ms per frame of decode / apply work, exactly on the devices that
-- lag most. The script wakes up if the tier later becomes mid / high (settings, slider).
if currentTier() == "low" then
	setStatus("dormant (low quality tier)")
	if not (Quality and Quality.changed) then
		return
	end
	repeat
		Quality.changed:Wait()
	until currentTier() ~= "low"
	tierName = currentTier()
	cfg = TIERS[tierName]
end

-- (probed only now: a phone on the low tier never touches the Image API)
local okProbe, probeInfo = probe()
if not okProbe then
	setStatus("inactive: " .. probeInfo)
	print(TAG, "Image API not available, keeping the built look (" .. probeInfo .. ")")
	return
end

if not loadData() then
	return
end

setStatus(string.format("starting (%s, %s)", tierName, tostring(contentProp)))
workspace.DescendantAdded:Connect(onAdded)
workspace.DescendantRemoving:Connect(onRemoving)
task.spawn(initialScan)
imageGen += 1
task.spawn(buildImages, imageGen)

if Quality and Quality.changed then
	pcall(function()
		Quality.changed:Connect(function()
			local newTier = currentTier()
			if newTier == tierName then
				return
			end
			local oldHalf = cfg.half
			tierName = newTier
			cfg = TIERS[newTier]
			if cfg.half ~= oldHalf then
				rebuildForTier()
			else
				task.spawn(buildImages, imageGen) -- a tier may build textures the previous one skipped
			end
			dirty = true
		end)
	end)
end

workspace:GetAttributeChangedSignal("GwangalliTexturesOff"):Connect(function()
	local off = workspace:GetAttribute("GwangalliTexturesOff") == true
	if off and enabled then
		enabled = false
		imageGen += 1
		clearAll()
		local old = images
		images = {}
		task.defer(function()
			for _, img in old do
				destroyImage(img)
			end
		end)
		setStatus("off (workspace.GwangalliTexturesOff)")
	elseif not off and not enabled then
		enabled = true
		table.clear(failed)
		budgetExhausted = false
		imageGen += 1
		task.spawn(buildImages, imageGen)
		dirty = true
	end
end)

local lastStatus = 0
RunService.Heartbeat:Connect(function()
	if not enabled then
		return
	end
	local t0 = os.clock()
	local deadline = t0 + cfg.applyMs / 1000
	if pendingHead <= #pending then
		drainPending(t0 + 0.0008)
	end
	if imagesChanged then
		imagesChanged = false
		dirty = true
	end
	local camera = workspace.CurrentCamera
	if camera and (t0 - lastUpdate) >= 1 / cfg.updateHz then
		local cam = camera.CFrame.Position
		if dirty or lastCam == nil or (cam - (lastCam :: Vector3)).Magnitude > 2 or (t0 - lastUpdate) > 2 then
			local ok, err = pcall(update)
			if not ok then
				warn(TAG, "update failed: " .. tostring(err))
				lastUpdate = t0
			end
		end
	end
	if addHead <= #addQueue and os.clock() < deadline then
		applyQueued(deadline)
	end
	if t0 - lastStatus > 3 then
		lastStatus = t0
		local nImg = 0
		for _ in images do
			nImg += 1
		end
		setStatus(string.format("%s: %d images, %d textures (%d street / %d markings / %d interior), %d parts tracked%s",
			tierName, nImg, appliedTotal, appliedByCat.street, appliedByCat.marking, appliedByCat.interior, registered,
			if budgetExhausted then ", image memory budget reached" else ""))
	end
end)
