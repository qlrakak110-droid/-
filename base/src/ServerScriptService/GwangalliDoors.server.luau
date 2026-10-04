-- GwangalliDoors (server)
-- Automatic sliding doors. A Model tagged "AutoDoor" contains BasePart leaves with attribute
-- OpenOffset (Vector3, world space). When any character's HumanoidRootPart (players, plus any
-- Model/BasePart tagged "AutoDoorOpener", e.g. NPCs) comes within Radius studs of the door's
-- centre, the door opens; it closes again after CloseDelay seconds with nobody in range.
-- Optional model attributes: OpenRadius (number), CloseDelay (number), TweenTime (number).
--
-- The server is authoritative for the STATE and the COLLISION; the sliding animation is local
-- (GwangalliDoorsClient in StarterPlayerScripts). Tweening the leaves here replicated a CFrame
-- every server frame for 0.6 s per leaf, which on a phone at 150-400 ms ping arrived late and
-- choppy, so the character bumped into a leaf that looked open. Contract:
--   door (the tagged instance)  Open          boolean  current state (absent = closed)
--                               OpenChangedAt number   workspace:GetServerTimeNow() of the last change
--   each leaf                   ClosedCFrame  CFrame   authored closed pose (the server never moves
--                                                     the leaves, so this is also their CFrame here)
--                               Collides      boolean  authored CanCollide
-- Collision: leaves that are authored CanCollide turn CanCollide = false the moment the door opens
-- and back on TweenTime + 0.15 s after it closes (when the local slide has finished), so nobody
-- is pushed by a closing leaf. Leaves authored non-colliding are never touched.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local configModule = ReplicatedStorage:WaitForChild("GwangalliConfig", 30)
if not configModule then
	warn("[GwangalliDoors] GwangalliConfig missing")
	return
end
local Config = require(configModule)
local cfg = Config.Doors

local COLLIDE_DELAY = 0.15 -- extra seconds after the close slide before collision returns

type Leaf = { part: BasePart, closed: CFrame, collides: boolean }
type Door = {
	inst: Instance,
	center: Vector3,
	radius: number,
	closeDelay: number,
	tweenTime: number,
	leaves: { Leaf },
	isOpen: boolean,
	lastSeen: number,
	generation: number, -- bumped on every state change; stale delayed collision restores are skipped
	conns: { RBXScriptConnection },
}

local doors: { [Instance]: Door } = {}

local function numberAttr(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	if type(v) == "number" and v == v and v > 0 then
		return v
	end
	return default
end

local function pivotOf(inst: Instance): Vector3?
	if inst:IsA("Model") then
		local ok, cf = pcall(inst.GetPivot, inst)
		if ok then
			return cf.Position
		end
	elseif inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

-- A leaf's closed pose is its authored CFrame. ClosedCFrame is written once, so a leaf added again
-- (or a door re-registered after a tag change) keeps the original pose.
local function addLeaf(door: Door, part: BasePart): Leaf?
	for _, leaf in door.leaves do
		if leaf.part == part then
			return nil
		end
	end
	if typeof(part:GetAttribute("OpenOffset")) ~= "Vector3" then
		return nil
	end
	part.Anchored = true -- clients move the leaves by CFrame; physics must not fight them
	local closed = part:GetAttribute("ClosedCFrame")
	if typeof(closed) ~= "CFrame" then
		closed = part.CFrame
		part:SetAttribute("ClosedCFrame", closed)
	end
	local collides = part:GetAttribute("Collides")
	if type(collides) ~= "boolean" then
		collides = part.CanCollide
		part:SetAttribute("Collides", collides)
	end
	local leaf: Leaf = { part = part, closed = closed :: CFrame, collides = collides :: boolean }
	table.insert(door.leaves, leaf)
	if door.isOpen and leaf.collides then
		part.CanCollide = false
	end
	return leaf
end

-- The trigger centre is the mean closed position of the leaves (a Lune-built Model may carry no
-- meaningful WorldPivot); doors without leaves keep the pivot.
local function recenter(door: Door)
	if #door.leaves == 0 then
		return
	end
	local sum = Vector3.zero
	for _, leaf in door.leaves do
		sum += leaf.closed.Position
	end
	door.center = sum / #door.leaves
end

local function setCollision(door: Door, on: boolean)
	for _, leaf in door.leaves do
		if leaf.collides and leaf.part.Parent and leaf.part.CanCollide ~= on then
			leaf.part.CanCollide = on
		end
	end
end

local function setOpen(door: Door, open: boolean)
	door.isOpen = open
	door.generation += 1
	door.inst:SetAttribute("OpenChangedAt", workspace:GetServerTimeNow())
	door.inst:SetAttribute("Open", open)
	if open then
		setCollision(door, false)
	else
		local generation = door.generation
		task.delay(door.tweenTime + COLLIDE_DELAY, function()
			if doors[door.inst] == door and door.generation == generation and not door.isOpen then
				setCollision(door, true)
			end
		end)
	end
end

local function unregister(inst: Instance)
	local door = doors[inst]
	if not door then
		return
	end
	doors[inst] = nil
	for _, c in door.conns do
		c:Disconnect()
	end
	-- tag removed but door kept: leave it closed and solid
	for _, leaf in door.leaves do
		if leaf.part.Parent then
			leaf.part.CFrame = leaf.closed
			if leaf.collides then
				leaf.part.CanCollide = true
			end
		end
	end
	if inst.Parent then
		inst:SetAttribute("Open", false)
	end
end

local function register(inst: Instance)
	if doors[inst] or not inst:IsDescendantOf(workspace) then
		return
	end
	local center = pivotOf(inst)
	if not center then
		return
	end
	local door: Door = {
		inst = inst,
		center = center,
		radius = numberAttr(inst, "OpenRadius", cfg.Radius),
		closeDelay = numberAttr(inst, "CloseDelay", cfg.CloseDelay),
		tweenTime = numberAttr(inst, "TweenTime", cfg.TweenTime),
		leaves = {},
		isOpen = false,
		lastSeen = -math.huge,
		generation = 0,
		conns = {},
	}
	if inst:IsA("BasePart") then
		addLeaf(door, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			addLeaf(door, d)
		end
	end
	-- Leaves added later (e.g. a builder script) are picked up too.
	table.insert(door.conns, inst.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and addLeaf(door, d) then
			recenter(door)
		end
	end))
	table.insert(door.conns, inst.DescendantRemoving:Connect(function(d)
		for i = #door.leaves, 1, -1 do
			if door.leaves[i].part == d then
				table.remove(door.leaves, i)
			end
		end
	end))
	if #door.leaves == 0 then
		warn("[GwangalliDoors] AutoDoor without OpenOffset leaves: " .. inst:GetFullName())
	end
	recenter(door)
	doors[inst] = door
	if inst:GetAttribute("Open") ~= false then
		inst:SetAttribute("Open", false)
	end
end

CollectionService:GetInstanceAddedSignal("AutoDoor"):Connect(register)
CollectionService:GetInstanceRemovedSignal("AutoDoor"):Connect(unregister)
for _, inst in CollectionService:GetTagged("AutoDoor") do
	task.spawn(register, inst)
end

-- Openers ---------------------------------------------------------------------------------------
-- NPC openers are tracked through tag signals, so the 0.15 s loop allocates nothing per tick.
local npcOpeners: { [Instance]: boolean } = {}
CollectionService:GetInstanceAddedSignal("AutoDoorOpener"):Connect(function(inst)
	npcOpeners[inst] = true
end)
CollectionService:GetInstanceRemovedSignal("AutoDoorOpener"):Connect(function(inst)
	npcOpeners[inst] = nil
end)
for _, inst in CollectionService:GetTagged("AutoDoorOpener") do
	npcOpeners[inst] = true
end

local openerPositions: { Vector3 } = {}

local function collectOpeners()
	table.clear(openerPositions)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
				table.insert(openerPositions, root.Position)
			end
		end
	end
	for inst in npcOpeners do
		if not inst.Parent then
			npcOpeners[inst] = nil
		elseif inst:IsDescendantOf(workspace) then
			local root = if inst:IsA("Model") then inst:FindFirstChild("HumanoidRootPart") else inst
			if root and root:IsA("BasePart") then
				table.insert(openerPositions, root.Position)
			else
				local pos = pivotOf(inst)
				if pos then
					table.insert(openerPositions, pos)
				end
			end
		end
	end
end

local function step()
	collectOpeners()
	local now = os.clock()
	for _, door in doors do
		if #door.leaves > 0 then
			local r2 = door.radius * door.radius
			local near = false
			for _, p in openerPositions do
				local d = p - door.center
				if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
					near = true
					break
				end
			end
			if near then
				door.lastSeen = now
				if not door.isOpen then
					setOpen(door, true)
				end
			elseif door.isOpen and now - door.lastSeen >= door.closeDelay then
				setOpen(door, false)
			end
		end
	end
end

while true do
	task.wait(cfg.CheckInterval)
	local ok, err = pcall(step)
	if not ok then
		warn("[GwangalliDoors] " .. tostring(err))
		task.wait(1)
	end
end
