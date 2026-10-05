-- GwangalliStreetLife/Pool: the rig cache. Rigs (GwangalliNPCLooks) are kept when their person leaves
-- the player's surroundings:
--   * the same person / outfit coming back gets its own rig again (a reparent, nothing rebuilt);
--   * anyone else takes the least recently used idle rig and re-dresses it (Looks.restyle: body
--     resized / recoloured, ~15 extra parts rebuilt, loaded animation tracks kept) instead of
--     building a new one (~50 Instance.new);
--   * a new rig is built only when no idle rig is left; idle rigs beyond PoolSpare are destroyed.
-- Unused rigs are parented to nil. Rigs live in a client-only Folder Workspace.GwangalliStreetLife
-- (never streamed, never replicated).

local Pool = {}

local ctx: any
local Looks: any
local Anim: any
local folder: Folder
local rigs: { [string]: any } = {}
local idle: { any } = {}
local built = 0
local reused = 0
local restyled = 0

function Pool.init(context: any)
	ctx = context
	Looks = ctx.Looks
	Anim = ctx.Anim
	local old = workspace:FindFirstChild("GwangalliStreetLife")
	if old and old:IsA("Folder") then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "GwangalliStreetLife"
	folder.Parent = workspace
	Pool.folder = folder
end

local function removeIdle(rig: any)
	for i, r in idle do
		if r == rig then
			table.remove(idle, i)
			return
		end
	end
end

-- key: person id + outfit key; spec: GwangalliNPCLooks spec; name: model name
function Pool.acquire(key: string, spec: any, name: string, cf: CFrame): any
	local rig = rigs[key]
	if rig and not rig.inUse and not rig.destroyed then
		removeIdle(rig)
		reused += 1
	else
		rig = nil
		-- re-dress the least recently used idle rig as this person
		if Looks.restyle and #idle > 0 then
			local old = table.remove(idle, 1)
			if rigs[old.key] == old then
				rigs[old.key] = nil
			end
			local ok = pcall(Looks.restyle, old, spec, name)
			if ok then
				rig = old
				restyled += 1
				if rig.chip then
					rig.chip.StudsOffsetWorldSpace = Vector3.new(0, 1.2 * rig.scale, 0)
					rig.chipDirty = true
				end
			else
				old.destroyed = true
				pcall(old.model.Destroy, old.model)
			end
		end
		if not rig then
			rig = Looks.build(spec, { name = name, shadow = false })
			built += 1
		end
		rig.key = key
		rig.seed = (Looks.hash(key) % 1000) / 1000
		rigs[key] = rig
	end
	rig.inUse = true
	-- move the WHOLE rig (PivotTo), not just the root: the engine records every limb's offset from the
	-- root when the rig enters the Workspace and drops limbs farther than 40 studs from it, so a fresh
	-- rig (limbs at the build origin) or a pooled one (limbs where it was released) placed by its root
	-- alone showed only its name chip / face (bug "NPC가 안 보임")
	rig.model:PivotTo(cf)
	rig.model.Parent = folder
	Anim.setup(rig)
	return rig
end

function Pool.release(rig: any)
	if not rig or not rig.inUse then
		return
	end
	rig.inUse = false
	Anim.reset(rig)
	if rig.chip then
		rig.chip.Enabled = false
	end
	if rig.prompt then
		rig.prompt.Enabled = false
	end
	rig.model.Parent = nil
	rig.lastUsed = os.clock()
	table.insert(idle, rig)
	local spare = ctx.Config.PoolSpare or 10
	while #idle > spare do
		local old = table.remove(idle, 1)
		if old then
			old.destroyed = true
			if rigs[old.key] == old then
				rigs[old.key] = nil
			end
			pcall(old.model.Destroy, old.model)
		end
	end
end

-- a cached rig (in the pool, not in use) exists for this key
function Pool.has(key: string): boolean
	local rig = rigs[key]
	return rig ~= nil and not rig.inUse and not rig.destroyed
end

function Pool.stats(): (number, number, number, number)
	return built, reused, #idle, restyled
end

return Pool
