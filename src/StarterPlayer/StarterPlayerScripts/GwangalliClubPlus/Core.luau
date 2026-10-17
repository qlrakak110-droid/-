-- GwangalliClubPlus.Core: client context shared by every module of the club show add-on.
--   * remotes / attributes of ReplicatedStorage.GwangalliClubPlus (Stage / Boards / DJ) and the club's
--     own GwangalliClubShow attributes (Show / Tables / Booking), decoded once per change
--   * the existing client modules when present (ClubShared.Bus, GwangalliClubShowShared, GwangalliUI,
--     GwangalliLayout, GwangalliQuality, ClubMusicShared), all optional
--   * where the local player is (own ClubZone poll; ClubLights' Bus for the beat when it runs)
--   * beat clock (Bus beats in LIVE mode, ClubShared.clock from ShowEpoch otherwise)
--   * one Heartbeat driver for every job, local world folder, PlayerGui surfaces, small builders

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Core: any = {}

Core.player = Players.LocalPlayer
Core.started = os.clock()
Core.scriptInst = nil :: Instance? -- the LocalScript (diagnostic attributes for Studio: Zone, Err_*, JobErr_*)

function Core.debug(key: string, value: any)
	local inst = Core.scriptInst
	if inst then
		pcall(inst.SetAttribute, inst, key, value)
	end
end

local function optional(name: string, wait: number?): any?
	local m = ReplicatedStorage:FindFirstChild(name)
	if not m and wait then
		m = ReplicatedStorage:WaitForChild(name, wait)
	end
	if m and m:IsA("ModuleScript") then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" then
			return mod
		end
	end
	return nil
end

function Core.init(S: any, folder: Instance)
	Core.S = S
	Core.L = S.Lines
	Core.remoteFolder = folder
	Core.Request = folder:WaitForChild(S.Names.Request) :: RemoteEvent
	Core.Event = folder:WaitForChild(S.Names.Event) :: RemoteEvent
	Core.ClubShared = optional(S.Names.ClubShared, 10)
	Core.ShowShared = optional(S.Names.ShowShared, 5)
	Core.K = optional("GwangalliUI", 5)
	Core.Layout = optional("GwangalliLayout")
	Core.Quality = optional("GwangalliQuality")
	Core.Music = optional("ClubMusicShared")
	Core.Bus = (Core.ClubShared and Core.ClubShared.Bus) or {
		state = "Idle",
		section = "intro",
		bpm = 126,
		energy = 0.4,
		beatAt = 0,
		beatSerial = 0,
		dropAt = -1e9,
		countdown = 0,
		playerDanceAt = -1e9,
	}
end

-- one OnClientEvent connection for every module: Core.onEvent(kind, fn(payload))
local eventFns: { [string]: { (any) -> () } } = {}
function Core.onEvent(kind: string, fn: (any) -> ())
	eventFns[kind] = eventFns[kind] or {}
	table.insert(eventFns[kind], fn)
end
function Core.connectEvents()
	Core.Event.OnClientEvent:Connect(function(kind: any, payload: any)
		if type(kind) ~= "string" then
			return
		end
		for _, fn in eventFns[kind] or {} do
			task.spawn(function()
				local ok, err = pcall(fn, if type(payload) == "table" then payload else {})
				if not ok then
					warn("[GwangalliClubPlus] event " .. kind .. " failed:", err)
				end
			end)
		end
	end)
end

function Core.now(): number
	return workspace:GetServerTimeNow()
end

function Core.send(op: string, payload: any)
	Core.Request:FireServer(op, payload or {})
end

local ridN = 0
function Core.rid(): string
	ridN += 1
	return string.format("%d-%d", math.floor(os.clock() * 10) % 100000, ridN)
end

-------------------------------------------------------------------------------------------------
-- quality
-------------------------------------------------------------------------------------------------
local qCache: any = nil
local qAt = -1e9
function Core.q(): any
	if os.clock() - qAt > 3 or not qCache then
		qAt = os.clock()
		local tierName, saver = "mid", false
		local Q = Core.Quality
		if Q then
			local ok, t = pcall(Q.get)
			if ok and type(t) == "string" then
				tierName = t
			end
			if type(Q.isSaver) == "function" then
				local okS, s = pcall(Q.isSaver)
				saver = okS and s == true
			end
		end
		local q = table.clone(Core.S.quality(tierName, saver))
		q.name = if saver then "saver" elseif Core.S.Config.Quality[tierName] then tierName else "mid"
		if Core.reduced() then
			q.reduced = true
		end
		qCache = q
	end
	return qCache
end

function Core.reduced(): boolean
	local K = Core.K
	if K then
		if type(K.reduced) == "function" then
			local ok, r = pcall(K.reduced)
			if ok and r == true then
				return true
			end
		end
		if type(K.settings) == "table" and K.settings.reducedMotion == true then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------------------------
-- where am I: ClubZone parts (attribute Zone = Main / Lobby / ... ; "Near" is the street)
-------------------------------------------------------------------------------------------------
Core.zone = ""
Core.inside = false
Core.showRoom = false
local SHOW_ROOMS = { Main = true, Lobby = true, Corridor = true, VIPStair = true }

function Core.root(): BasePart?
	local ch = Core.player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

-- a ClubZone part's room name: its Zone attribute (Club.server / ClubLights contract), else its name
function Core.zoneName(z: Instance): string
	local a = z:GetAttribute("Zone")
	if type(a) == "string" and a ~= "" then
		return (a:gsub("^Zone_", ""))
	end
	return (z.Name:gsub("^Zone_", ""))
end

local function pollZone()
	local r = Core.root()
	local zone = ""
	if r then
		local pos = r.Position
		local bestPri = -1
		for _, z in CollectionService:GetTagged("ClubZone") do
			if z:IsA("BasePart") then
				local lp = z.CFrame:PointToObjectSpace(pos)
				local h = z.Size * 0.5
				if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y + 2 and math.abs(lp.Z) <= h.Z then
					local name = Core.zoneName(z)
					local pri = tonumber(z:GetAttribute("Priority")) or (if name == "Near" then 1 else 5)
					if pri > bestPri then
						bestPri = pri
						zone = name
					end
				end
			end
		end
	end
	-- ClubLights' own zone state wins when it runs
	local bus = Core.Bus
	if bus.state == "Inside" and type(bus.zone) == "string" and bus.zone ~= "" then
		zone = (bus.zone:gsub("^Zone_", ""))
	end
	if zone ~= Core.zone then
		Core.debug("Zone", zone)
	end
	Core.zone = zone
	Core.inside = zone ~= "" and zone ~= "Near"
	Core.showRoom = SHOW_ROOMS[zone] == true
end

-------------------------------------------------------------------------------------------------
-- beat clock
-------------------------------------------------------------------------------------------------
local epochCache, epochAt = 0, -1e9
function Core.epoch(): number
	if os.clock() - epochAt > 5 then
		epochAt = os.clock()
		for _, m in CollectionService:GetTagged("ClubRuntime") do
			local e = m:GetAttribute("ShowEpoch")
			if type(e) == "number" then
				epochCache = e
				break
			end
		end
	end
	return epochCache
end

local clk: any = {}
-- -> phase 0..1 within the beat, beat counter, bpm, section name, bar (0..63), energy 0..1
function Core.beat(): (number, number, number, string, number, number)
	local bus = Core.Bus
	local bpm = tonumber(bus.bpm) or 126
	if bpm < 60 or bpm > 200 then
		bpm = 126
	end
	local CS = Core.ClubShared
	local bar = 0
	if CS and type(CS.clock) == "function" then
		local ok = pcall(CS.clock, Core.now(), Core.epoch(), bpm, clk)
		if ok then
			bar = clk.bar or 0
		end
	end
	local t = os.clock()
	if bus.beatAt and t - bus.beatAt < 2.5 then
		local period = 60 / bpm
		local phase = math.clamp((t - bus.beatAt) / period, 0, 0.999)
		return phase, bus.beatSerial or 0, bpm, tostring(bus.section or "groove"), bar, tonumber(bus.energy) or 0.6
	end
	if clk.beat then
		local sec = clk.section and clk.section.name or "groove"
		return clk.frac or 0, math.floor(clk.beat), bpm, sec, bar, clk.section and clk.section.energy or 0.5
	end
	local beat = Core.now() * bpm / 60
	return beat % 1, math.floor(beat), bpm, "groove", 0, 0.5
end

-- run fn on the next beat at least `delay` seconds from now
function Core.onBeat(delay: number, fn: () -> ())
	local phase, _, bpm = Core.beat()
	local period = 60 / bpm
	local toNext = (1 - phase) * period
	while toNext < delay do
		toNext += period
	end
	task.delay(toNext, fn)
end

-- the house show owns the screen (LED countdown / DROP flash)
function Core.houseMoment(): boolean
	local bus = Core.Bus
	if (tonumber(bus.countdown) or 0) > 0 then
		return true
	end
	return os.clock() - (tonumber(bus.dropAt) or -1e9) < 2.4
end

-------------------------------------------------------------------------------------------------
-- jobs: one Heartbeat connection; job(dt, now) returns false to stop
-------------------------------------------------------------------------------------------------
local jobs: { [string]: { fn: (number, number) -> boolean?, period: number, acc: number, errors: number } } = {}
function Core.job(name: string, hz: number, fn: (number, number) -> boolean?)
	jobs[name] = { fn = fn, period = if hz > 0 then 1 / hz else 0, acc = 0, errors = 0 }
end
function Core.stop(name: string)
	jobs[name] = nil
end
function Core.running(name: string): boolean
	return jobs[name] ~= nil
end
RunService.Heartbeat:Connect(function(dt: number)
	local now = Core.now()
	for name, j in jobs do
		j.acc += dt
		if j.acc >= j.period then
			local step = j.acc
			j.acc = if j.period > 0 then j.acc % j.period else 0
			local ok, res = pcall(j.fn, step, now)
			if not ok then
				-- a job survives a few bad frames (streamed-out parts, a respawn); it stops on the 5th in a row
				j.errors += 1
				Core.debug("JobErr_" .. name, tostring(res))
				if j.errors == 1 or j.errors >= 5 then
					warn("[GwangalliClubPlus] job " .. name .. " failed:", res)
				end
				if j.errors >= 5 and jobs[name] == j then
					jobs[name] = nil
				end
			elseif res == false then
				if jobs[name] == j then
					jobs[name] = nil
				end
			else
				j.errors = 0
			end
		end
	end
end)

-------------------------------------------------------------------------------------------------
-- attributes (decoded once per change)
-------------------------------------------------------------------------------------------------
Core.state = {} :: { [string]: any } -- Stage / Boards / DJ / Show / Tables / Booking
local listeners: { [string]: { (any) -> () } } = {}

function Core.on(key: string, fn: (any) -> ())
	listeners[key] = listeners[key] or {}
	table.insert(listeners[key], fn)
	if Core.state[key] ~= nil then
		task.spawn(fn, Core.state[key])
	end
end
local function emit(key: string, value: any)
	Core.state[key] = value
	for _, fn in listeners[key] or {} do
		task.spawn(function()
			local ok, err = pcall(fn, value)
			if not ok then
				warn("[GwangalliClubPlus] " .. key .. " listener failed:", err)
			end
		end)
	end
end
local function watch(inst: Instance, attr: string, key: string)
	local function read()
		local v = Core.S.decode(inst:GetAttribute(attr))
		emit(key, if type(v) == "table" then v else {})
	end
	inst:GetAttributeChangedSignal(attr):Connect(read)
	read()
end

function Core.startWatching()
	local f = Core.remoteFolder
	watch(f, "Stage", "Stage")
	watch(f, "Boards", "Boards")
	watch(f, "DJ", "DJ")
	task.spawn(function()
		local club = ReplicatedStorage:WaitForChild(Core.S.Names.ClubFolder, 300)
		if club then
			Core.clubFolder = club
			watch(club, "Show", "Show")
			watch(club, "Tables", "Tables")
			watch(club, "Booking", "Booking")
		end
	end)
	Core.job("zone", 2, function()
		pollZone()
		return true
	end)
	pollZone()
end

-- the club menu item (GwangalliClubShowShared.item, else the add-on's fallback copy of the menu)
function Core.menuItem(id: any): any?
	local SS = Core.ShowShared
	if SS and type(SS.item) == "function" then
		local ok, it = pcall(SS.item, id)
		if ok and type(it) == "table" then
			return it
		end
	end
	if type(id) == "string" then
		return Core.S.Config.Fallback.Menu[id]
	end
	return nil
end

function Core.allAges(): boolean
	local SS = Core.ShowShared
	if SS and type(SS.allAges) == "function" then
		local ok, v = pcall(SS.allAges)
		if ok and type(v) == "boolean" then
			return v
		end
	end
	return true
end

-------------------------------------------------------------------------------------------------
-- map lookups (read only; streamed parts are looked up again when gone)
-------------------------------------------------------------------------------------------------
local anchorCache: { [string]: BasePart } = {}
function Core.anchor(name: string): BasePart?
	local a = anchorCache[name]
	if a and a.Parent and a:IsDescendantOf(workspace) then
		return a
	end
	for _, p in CollectionService:GetTagged("ClubShowAnchor") do
		if p.Name == name and p:IsA("BasePart") and p:IsDescendantOf(workspace) then
			anchorCache[name] = p
			return p
		end
	end
	return nil
end

-- the LED wall frame: CFrame (front face = -Z into the room) + size
function Core.ledFrame(): (CFrame, Vector3)
	local a = Core.anchor("Show_LEDWall")
	if a then
		return a.CFrame, a.Size
	end
	local fb = Core.S.Config.Fallback.LEDWall
	return CFrame.lookAt(fb.pos, fb.pos + Vector3.new(-0.9999, 0, -0.015)), fb.size
end

function Core.clubModel(): Instance?
	local c = Core.clubCache
	if c and c.Parent then
		return c
	end
	for _, m in CollectionService:GetTagged("ClubVenue") do
		if m:IsDescendantOf(workspace) then
			Core.clubCache = m
			return m
		end
	end
	local g = workspace:FindFirstChild("Gwangalli")
	local club = g and g:FindFirstChild("club")
	local venue = club and club:FindFirstChild("CLUB OCEAN 광안")
	Core.clubCache = venue
	return venue
end

-- first descendant of the club's MainRoom with this name (cached)
local findCache: { [string]: Instance } = {}
function Core.mainPart(name: string): BasePart?
	local c = findCache[name]
	if c and c.Parent and c:IsDescendantOf(workspace) then
		return c :: BasePart
	end
	local club = Core.clubModel()
	local main = club and club:FindFirstChild("MainRoom")
	local hit = main and main:FindFirstChild(name, true)
	if hit and hit:IsA("BasePart") then
		findCache[name] = hit
		return hit
	end
	return nil
end
function Core.mainParts(name: string, parentName: string?): { BasePart }
	local out = {}
	local club = Core.clubModel()
	local main = club and club:FindFirstChild("MainRoom")
	local scope: Instance? = main
	if main and parentName then
		scope = main:FindFirstChild(parentName, true)
	end
	if scope then
		for _, d in scope:GetDescendants() do
			if d.Name == name and d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- the main room's box (Zone_Main), used to clip laser beams inside the walls
function Core.mainBox(): (CFrame?, Vector3?)
	local c = Core.mainBoxCache
	if c and c.Parent then
		return c.CFrame, c.Size
	end
	for _, z in CollectionService:GetTagged("ClubZone") do
		if z:IsA("BasePart") and Core.zoneName(z) == "Main" then
			Core.mainBoxCache = z
			return z.CFrame, z.Size
		end
	end
	return nil, nil
end

-- the main room as a world box: CFrame + size (Zone_Main, else the config fallback)
function Core.roomBox(): (CFrame, Vector3)
	local cf, size = Core.mainBox()
	if cf and size then
		return cf, size
	end
	local fb = Core.S.Config.Fallback.Room
	return CFrame.new(fb.pos), fb.size
end

-- clip a ray from `from` along unit `dir` to the inside of the room box (minus `margin`)
function Core.clipToRoom(from: Vector3, dir: Vector3, reach: number, margin: number?): Vector3
	local cf, size = Core.roomBox()
	local o = cf:PointToObjectSpace(from)
	local d = cf:VectorToObjectSpace(dir)
	local h = size * 0.5 - Vector3.one * (margin or 0.6)
	local tMax = reach
	for _, ax in { "X", "Y", "Z" } do
		local dv = (d :: any)[ax]
		local ov = (o :: any)[ax]
		local hv = (h :: any)[ax]
		if math.abs(dv) > 1e-6 then
			local t = ((if dv > 0 then hv else -hv) - ov) / dv
			if t > 0 and t < tMax then
				tMax = t
			end
		end
	end
	return from + dir * math.max(1, tMax)
end

-- ClubTable models by TableId: { model, top (centre of the table top), size }
local tableCache: { [string]: any } = {}
local tableScanAt = -1e9
local function scanTables()
	tableScanAt = os.clock()
	for _, m in CollectionService:GetTagged("ClubTable") do
		local id = m:GetAttribute("TableId")
		if type(id) == "string" and m:IsDescendantOf(workspace) then
			local e = tableCache[id]
			if not e or e.model ~= m or not e.model.Parent then
				tableCache[id] = { model = m }
			end
		end
	end
end
function Core.tableInfo(id: any): any?
	if type(id) ~= "string" then
		return nil
	end
	local e = tableCache[id]
	if (not e or not e.model.Parent or not e.model:IsDescendantOf(workspace)) and os.clock() - tableScanAt > 3 then
		scanTables()
		e = tableCache[id]
	end
	if not e or not e.model.Parent then
		return nil
	end
	if not e.top then
		local m = e.model
		local top = m:FindFirstChild("TableTop", true) or m:FindFirstChild("Top", true) or m:FindFirstChild("VIPTableTop", true) or m:FindFirstChild("TableSlab", true)
		if top and top:IsA("BasePart") then
			-- (the slab may be rotated: use its world AABB height)
			local h = math.abs(top.CFrame.UpVector.Y) * top.Size.Y + math.abs(top.CFrame.RightVector.Y) * top.Size.X + math.abs(top.CFrame.LookVector.Y) * top.Size.Z
			e.top = top.Position + Vector3.new(0, h * 0.5, 0)
		elseif m:IsA("Model") then
			local cf, size = m:GetBoundingBox()
			e.top = cf.Position + Vector3.new(0, size.Y * 0.5 - 1, 0)
		elseif m:IsA("BasePart") then
			e.top = m.Position + Vector3.new(0, m.Size.Y * 0.5, 0)
		end
		local serve = m:FindFirstChild("ServePoint", true)
		e.serve = if serve and serve:IsA("BasePart") then serve.Position else e.top
	end
	return e
end

-- an invisible anchored part in the room centre: beam end attachments live in it (Position = local offset)
function Core.sink(): Part
	local s = Core.sinkPart
	if s and s.Parent then
		return s
	end
	local cf = Core.roomBox()
	local p = Core.part("PlusSink", Vector3.new(0.2, 0.2, 0.2), CFrame.new(cf.Position))
	p.Transparency = 1
	Core.sinkPart = p
	return p
end
function Core.sinkAttachment(name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = Core.sink()
	return a
end
-- move a sink attachment to a world position
function Core.place(a: Attachment, world: Vector3)
	local s = Core.sink()
	a.Position = world - s.Position
end

-- the club's NPCs with a role (ClubNPC tag; Role / Zone attributes)
function Core.npcs(role: string, zone: string?): { Model }
	local out = {}
	for _, m in CollectionService:GetTagged("ClubNPC") do
		if m:IsA("Model") and m:GetAttribute("Role") == role and (zone == nil or m:GetAttribute("Zone") == zone) and m:IsDescendantOf(workspace) then
			table.insert(out, m)
		end
	end
	return out
end

-- parts named `name` anywhere under the club model (cached per name for 20 s)
local allCache: { [string]: { at: number, list: { BasePart } } } = {}
function Core.clubParts(name: string): { BasePart }
	local c = allCache[name]
	if c and os.clock() - c.at < 20 then
		local alive = true
		for _, p in c.list do
			if not p.Parent then
				alive = false
				break
			end
		end
		if alive and #c.list > 0 then
			return c.list
		end
	end
	local out = {}
	local club = Core.clubModel()
	if club then
		for _, d in club:GetDescendants() do
			if d.Name == name and d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
	end
	allCache[name] = { at = os.clock(), list = out }
	return out
end

-- positions of map parts named `name`, else the fallback list
function Core.spots(name: string, fallback: { Vector3 }, offset: Vector3?): { Vector3 }
	local list = {}
	for _, p in Core.clubParts(name) do
		table.insert(list, p.Position + (offset or Vector3.zero))
	end
	if #list == 0 then
		for _, v in fallback do
			table.insert(list, v + (offset or Vector3.zero))
		end
	end
	return list
end

-------------------------------------------------------------------------------------------------
-- builders
-------------------------------------------------------------------------------------------------
function Core.make(class: string, props: { [string]: any }?, parent: Instance?): any
	local inst = Instance.new(class)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Core.folder(): Folder
	local f = Core.worldFolder
	if f and f.Parent then
		return f
	end
	local existing = workspace:FindFirstChild(Core.S.Names.LocalFolder)
	if existing and existing:IsA("Folder") then
		Core.worldFolder = existing
		return existing
	end
	local nf = Instance.new("Folder")
	nf.Name = Core.S.Names.LocalFolder
	nf.Parent = workspace
	Core.worldFolder = nf
	return nf
end

-- a local, non-colliding, non-queryable part in our own folder
function Core.part(name: string, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.Size = size
	p.CFrame = cf
	p.Color = color or Color3.new(0, 0, 0)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or Core.folder()
	return p
end

function Core.playerGui(): PlayerGui
	return Core.player:WaitForChild("PlayerGui") :: PlayerGui
end

function Core.surface(name: string, adornee: BasePart, face: Enum.NormalId, pps: number, opts: { [string]: any }?): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Name = name
	sg.ResetOnSpawn = false
	sg.Adornee = adornee
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pps
	sg.LightInfluence = 0
	sg.Brightness = 2
	sg.MaxDistance = 220
	sg.ClipsDescendants = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	if opts then
		for k, v in opts do
			(sg :: any)[k] = v
		end
	end
	sg.Parent = Core.playerGui()
	return sg
end

function Core.billboard(name: string, adornee: Instance, size: UDim2, offset: Vector3, opts: { [string]: any }?): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.ResetOnSpawn = false
	bb.Adornee = adornee
	bb.Size = size
	bb.StudsOffset = offset
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.MaxDistance = 80
	bb.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	if opts then
		for k, v in opts do
			(bb :: any)[k] = v
		end
	end
	bb.Parent = Core.playerGui()
	return bb
end

function Core.tween(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end

-- text label with sane defaults for the LED canvases (scaled text, stroke for readability)
function Core.text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextScaled = true
	t.TextWrapped = false
	t.RichText = false
	t.Text = ""
	for k, v in props do
		if k ~= "max" and k ~= "stroke" then
			(t :: any)[k] = v
		end
	end
	if props.max then
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = props.max
		c.MinTextSize = 6
		c.Parent = t
	end
	if props.stroke then
		local s = Instance.new("UIStroke")
		s.Color = props.stroke
		s.Thickness = 2
		s.Transparency = 0.25
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = t
	end
	t.Parent = parent
	return t
end

function Core.frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	for k, v in props do
		if k ~= "corner" and k ~= "gradient" and k ~= "strokeColor" and k ~= "strokeT" then
			(f :: any)[k] = v
		end
	end
	if props.corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = if typeof(props.corner) == "UDim" then props.corner else UDim.new(0, props.corner)
		c.Parent = f
	end
	if props.gradient then
		local g = Instance.new("UIGradient")
		g.Color = props.gradient
		g.Parent = f
	end
	if props.strokeColor then
		local s = Instance.new("UIStroke")
		s.Color = props.strokeColor
		s.Thickness = 2
		s.Transparency = props.strokeT or 0.2
		s.Parent = f
	end
	f.Parent = parent
	return f
end

function Core.seq(...: any): ColorSequence
	local cols = { ... }
	if #cols == 1 then
		return ColorSequence.new(cols[1])
	end
	local kps = {}
	for i, c in cols do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#cols - 1), c))
	end
	return ColorSequence.new(kps)
end

-------------------------------------------------------------------------------------------------
-- feedback
-------------------------------------------------------------------------------------------------
function Core.toast(title: string, body: string?, icon: string?, kind: string?)
	local K = Core.K
	if K and type(K.toast) == "function" then
		local ok = pcall(K.toast, { title = title, body = body or "", icon = icon, kind = kind or "club" })
		if ok then
			return
		end
	end
	if Core.fallbackToast then
		Core.fallbackToast(title, body or "", icon or "🎶")
	end
end

-- username (Roblox-moderated) of a player in this server, for the LED's "@name"
function Core.userName(uid: number?): string?
	if type(uid) ~= "number" then
		return nil
	end
	local p = Players:GetPlayerByUserId(uid)
	return p and p.Name or nil
end

-- the club show's local rigs (staff / MD / guests) by name
function Core.showRig(name: string): Model?
	local f = workspace:FindFirstChild(Core.S.Names.ShowLocal)
	local m = f and f:FindFirstChild(name)
	return if m and m:IsA("Model") then m else nil
end
function Core.rigRoot(m: Model?): BasePart?
	if not m then
		return nil
	end
	local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
	return if r and r:IsA("BasePart") then r else nil
end

return Core
