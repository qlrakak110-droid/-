-- DoorAnim: moves the leaves of every building door on this client from the server's attributes
-- (Open, OpenDir, OpenT on the door Model, see the server Doors service). Hinged leaves swing 95°
-- away from the person who opened them, sliding leaves slide along the wall, shutters roll up.
-- Leaf geometry is captured once per door (relative to the door's Frame attribute) and cached, so
-- a door parked with the interior and streamed back in keeps its true closed pose.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Config = Shared.Config
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local DoorAnim = {}

type LeafRec = { mode: string, hingeX: number, slideX: number, lift: number, parts: { { part: BasePart, rel: CFrame } } }
type DoorRec = {
	model: Model,
	frame: CFrame,
	leaves: { LeafRec },
	p: number, -- current progress 0 (closed) .. 1 (open)
	from: number,
	target: number,
	t0: number,
	dur: number,
	dir: number,
	kind: string,
	conns: { RBXScriptConnection },
}

local cache: { [Model]: DoorRec } = setmetatable({}, { __mode = "k" }) :: any
local active: { [DoorRec]: boolean } = {}
local MAX_SWING = math.rad(95)

local function ease(k: number): number
	-- ease in-out (a door accelerates and is braked by its closer)
	return k * k * (3 - 2 * k)
end

local function frameOf(m: Model): CFrame
	local f = m:GetAttribute("Frame")
	if typeof(f) == "CFrame" then
		return f
	end
	return m:GetPivot()
end

local function capture(m: Model): DoorRec
	local frame = frameOf(m)
	local leaves = {}
	for _, c in m:GetChildren() do
		if c:IsA("Model") and string.sub(c.Name, 1, 4) == "Leaf" then
			local lr: LeafRec = {
				mode = (c:GetAttribute("Mode") :: string?) or (if c:GetAttribute("SlideX") then "slide" else "swing"),
				hingeX = tonumber(c:GetAttribute("HingeX")) or 0,
				slideX = tonumber(c:GetAttribute("SlideX")) or 0,
				lift = tonumber(c:GetAttribute("Lift")) or 6,
				parts = {},
			}
			for _, p in c:GetDescendants() do
				if p:IsA("BasePart") then
					table.insert(lr.parts, { part = p, rel = frame:ToObjectSpace(p.CFrame) })
				end
			end
			table.insert(leaves, lr)
		end
	end
	local kind = (m:GetAttribute("DoorKind") :: string?) or "swing"
	return {
		model = m,
		frame = frame,
		leaves = leaves,
		p = 0,
		from = 0,
		target = 0,
		t0 = 0,
		dur = Config.DOOR_SWING_TIME,
		dir = 1,
		kind = kind,
		conns = {},
	}
end

local function apply(d: DoorRec, p: number)
	d.p = p
	for _, lf in d.leaves do
		local T: CFrame
		if lf.mode == "slide" then
			T = CFrame.new(lf.slideX * p, 0, 0)
		elseif lf.mode == "lift" then
			T = CFrame.new(0, lf.lift * p, 0)
		else
			local hx = lf.hingeX
			local ang = (if hx < 0 then -1 else 1) * d.dir * MAX_SWING * p
			T = CFrame.new(hx, 0, 0) * CFrame.Angles(0, ang, 0) * CFrame.new(-hx, 0, 0)
		end
		local base = d.frame * T
		for _, e in lf.parts do
			if e.part.Parent then
				e.part.CFrame = base * e.rel
			end
		end
	end
end

local function durationOf(d: DoorRec): number
	if d.kind == "shutter" then
		return 1.6
	end
	local mode = d.leaves[1] and d.leaves[1].mode
	if mode == "slide" then
		return Config.DOOR_SLIDE_TIME
	end
	return Config.DOOR_SWING_TIME
end

local function nearCamera(m: Model, dist: number): boolean
	local cam = workspace.CurrentCamera
	if not cam then
		return true
	end
	local f = m:GetAttribute("Frame")
	local pos = if typeof(f) == "CFrame" then f.Position else m:GetPivot().Position
	return (pos - cam.CFrame.Position).Magnitude < dist
end

local function sound(d: DoorRec, open: boolean)
	if not nearCamera(d.model, 45) then
		return
	end
	local anchor = d.leaves[1] and d.leaves[1].parts[1] and d.leaves[1].parts[1].part
	if not anchor then
		return
	end
	if d.kind == "auto" or d.kind == "sliding_glass" then
		Sfx.at("auto_door", anchor, { volume = 0.35, maxDist = 30 })
	elseif d.kind == "shutter" then
		Sfx.at("shutter", anchor, { volume = 0.5, maxDist = 45 })
	else
		Sfx.at(if open then "door_open" else "door_close", anchor, { volume = 0.45, maxDist = 30 })
	end
end

local function onState(d: DoorRec, initial: boolean)
	local m = d.model
	local open = m:GetAttribute("Open") == true
	local dir = tonumber(m:GetAttribute("OpenDir")) or 1
	if open then
		-- a door opening the other way first swings back through closed
		if d.p > 0.02 and dir ~= d.dir then
			d.p = 0
		end
		d.dir = dir
	end
	local target = if open then 1 else 0
	if initial or not nearCamera(m, 220) then
		d.target = target
		apply(d, target)
		active[d] = nil
		return
	end
	if target == d.target and not active[d] then
		return
	end
	d.from = d.p
	d.target = target
	d.t0 = os.clock()
	d.dur = durationOf(d) * math.max(0.25, math.abs(target - d.p))
	active[d] = true
	sound(d, open)
end

local function register(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local d = cache[m]
	if not d then
		d = capture(m)
		cache[m] = d
	end
	local dd = d :: DoorRec
	for _, c in dd.conns do
		c:Disconnect()
	end
	dd.conns = {
		m:GetAttributeChangedSignal("Open"):Connect(function()
			onState(dd, false)
		end),
		m:GetAttributeChangedSignal("OpenDir"):Connect(function()
			if m:GetAttribute("Open") == true then
				onState(dd, false)
			end
		end),
	}
	onState(dd, true)
end

local function unregister(m: Instance)
	local d = cache[m :: Model]
	if not d then
		return
	end
	for _, c in d.conns do
		c:Disconnect()
	end
	d.conns = {}
	active[d] = nil
	-- leave the leaves in their closed pose (a parked interior comes back closed)
	apply(d, 0)
	d.target = 0
end

local function step()
	local t = os.clock()
	for d in active do
		local k = if d.dur > 0 then math.clamp((t - d.t0) / d.dur, 0, 1) else 1
		apply(d, d.from + (d.target - d.from) * ease(k))
		if k >= 1 then
			active[d] = nil
		end
	end
end

function DoorAnim.start()
	CollectionService:GetInstanceAddedSignal("GwB_Door"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("GwB_Door"):Connect(unregister)
	for _, m in CollectionService:GetTagged("GwB_Door") do
		task.spawn(register, m)
	end
	RunService.RenderStepped:Connect(step)
end

-- debug / tests
function DoorAnim.progress(m: Model): number?
	local d = cache[m]
	return d and d.p
end

return DoorAnim
