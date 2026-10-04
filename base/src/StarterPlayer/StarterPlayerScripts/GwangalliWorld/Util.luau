-- Client helpers shared by the GwangalliWorld modules.
--   * quality tier access (GwangalliQuality, with a safe fallback when the module is missing)
--   * Util.watchTag            CollectionService added/removed (streaming-safe)
--   * Util.discover            instances found by ClassName / Name (SurfaceGuis, glass named
--                              "Window", LOD models, ...) through their CollectionService tag once
--                              the place is tagged (GwDiscoverTagged), else through ONE shared
--                              Workspace.DescendantAdded listener; processed in per-frame batches
--   * Util.setHidden           local hide / show of a model (LocalTransparencyModifier), batched,
--                              and kept hidden when more of its parts stream in
--   * Util.sweeper             chunked apply over many items (optionally nearest-first)
--   * Util.canDo / Util.spend  ONE per-frame write budget shared by every queue above (tag
--                              arrivals, discovery, hide / show, sweeps, registry drops), so their
--                              bursts after a quick-travel never add up in the same frame
--   * Util.registry            strong instance registry, pruned in the background once its
--                              instances leave the Workspace
--
-- State that must last as long as an instance never lives in a weak-keyed table: on Roblox the Lua
-- handle of an instance can be collected while the instance is still in the game (a new handle is
-- made on the next access), and the weak entry silently disappears with the old handle. Weak
-- tables are used only as caches that can be rebuilt.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Util = {}

function Util.warn(moduleName: string, ...: any)
	local parts = table.create(select("#", ...))
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	warn("[GwangalliWorld/" .. moduleName .. "] " .. table.concat(parts, " "))
end

-- True while `inst` is part of the Workspace. Use this, not `inst.Parent ~= nil`, to ask whether
-- an instance is still streamed in: streaming out parents the ROOT of the removed subtree to nil,
-- and everything below it keeps its Parent.
function Util.inWorld(inst: Instance): boolean
	return inst:IsDescendantOf(workspace)
end

---------------------------------------------------------------------------------------------------
-- Quality tier
---------------------------------------------------------------------------------------------------

local function fallbackQuality(): any
	-- Used only when ReplicatedStorage.GwangalliQuality is missing or fails: touch devices
	-- without a keyboard count as "low", everything else as "high"; the tier never changes.
	local okTen, tenFoot = pcall(GuiService.IsTenFootInterface, GuiService)
	local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not (okTen and tenFoot)
	local tier = if mobile then "low" else "high"
	local event = Instance.new("BindableEvent")
	return {
		get = function()
			return tier
		end,
		isMobile = function()
			return mobile
		end,
		isLow = function()
			return tier == "low"
		end,
		pick = function(map: any)
			local v = map[tier]
			if v == nil then
				v = if tier == "low" then (if map.mid ~= nil then map.mid else map.high) else (if map.mid ~= nil then map.mid else map.low)
			end
			return v
		end,
		fps = function()
			return 0
		end,
		reason = function()
			return "fallback (GwangalliQuality missing)"
		end,
		changed = event.Event,
	}
end

local Quality: any
do
	local module = ReplicatedStorage:FindFirstChild("GwangalliQuality") or ReplicatedStorage:WaitForChild("GwangalliQuality", 10)
	local ok, result = false, nil
	if module and module:IsA("ModuleScript") then
		ok, result = pcall(require, module)
	end
	if ok and type(result) == "table" and type(result.get) == "function" then
		Quality = result
	else
		Util.warn("Util", "GwangalliQuality unavailable, using the touch-device fallback:", result)
		Quality = fallbackQuality()
	end
end
Util.Quality = Quality

-- Snapshot kept for older callers; prefer Util.tier() / Util.isLow(), which follow tier changes.
Util.isMobile = Quality.isMobile() == true

function Util.tier(): string
	return Quality.get()
end

function Util.isLow(): boolean
	return Quality.get() == "low"
end

-- The SAVER sub-level of "low" (GwangalliQuality: a phone still under ~22 fps on low). Budget maps
-- may carry a `saver` entry (Quality.pick returns it while the saver is on), and a system table's
-- Tier.saver is laid over Tier.low by Util.tierConfig.
function Util.isSaver(): boolean
	return type(Quality.isSaver) == "function" and Quality.isSaver() == true
end

-- Calls fn(newTier, oldTier) whenever the tier changes, and fn(tier, tier) when the saver switches
-- on or off (every budget may have changed: re-apply). Errors are contained.
function Util.onTierChanged(fn: (string, string?) -> ())
	local function call(newTier, oldTier)
		local ok, err = pcall(fn, newTier, oldTier)
		if not ok then
			Util.warn("Quality", "tier change handler failed:", err)
		end
	end
	local conn = Quality.changed:Connect(call)
	if Quality.saverChanged then
		Quality.saverChanged:Connect(function()
			local t = Quality.get()
			call(t, t)
		end)
	end
	return conn
end

-- Budget for the current tier from { low=, mid=, high= } or the legacy { Desktop=, Mobile= }
-- ("low" -> Mobile, "mid"/"high" -> Desktop). Read it at use time: the tier can change.
function Util.budget(pair: any): any
	if pair.low ~= nil or pair.mid ~= nil or pair.high ~= nil then
		return Quality.pick(pair)
	end
	return if Quality.get() == "low" then pair.Mobile else pair.Desktop
end

-- The system table `cfg` with cfg.Tier[currentTier] laid over it, and cfg.Tier.saver on top while
-- the saver is on (cached per tier; plain reads).
local tierCache: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
function Util.tierConfig(cfg: any): any
	local tier = Quality.get()
	local saver = tier == "low" and Util.isSaver()
	local key = if saver then "saver" else tier
	local perCfg = tierCache[cfg]
	if not perCfg then
		perCfg = {}
		tierCache[cfg] = perCfg
	end
	local merged = perCfg[key]
	if not merged then
		merged = table.clone(cfg)
		local tiers = type(cfg.Tier) == "table" and cfg.Tier or nil
		for _, name in (if saver then { tier, "saver" } else { tier }) do
			local over = tiers and tiers[name]
			if type(over) == "table" then
				for k, v in over do
					merged[k] = v
				end
			end
		end
		perCfg[key] = merged
	end
	return merged
end

---------------------------------------------------------------------------------------------------
-- Shared per-frame work budget
---------------------------------------------------------------------------------------------------
-- Every chunked queue in this folder (watchTag arrivals, discovery deliveries, setHidden slices,
-- sweeps, registry drops) draws from ONE budget of property writes per frame instead of using only
-- its own cap: after a quick-travel all of them are busy at once, and their own caps alone added
-- up to more than a thousand writes in one frame on a phone.
--   * Util.canDo(done, cap): before each item a queue asks whether it may do one more this frame
--     (`done` = items it did this frame, `cap` = its own per-frame cap). The first FRAME_FLOOR items
--     of every queue are always allowed, so none of them starves while the others drain; after
--     that only while the shared budget lasts. Every item counts 1 write (the queue reports it).
--   * Util.spend(n): writes beyond that 1 are reported by whoever does them (Signage: a pane is up
--     to 4 writes, MobileQuality: a gui up to 4, a registry drop 4).
-- It is a token bucket: whatever a frame overspent (floors, extra writes) is paid back from the
-- next frames' budgets (at most one frame's worth of debt), so bursts are spread instead of piling
-- up, and the average stays at the budget.
-- Every queue does its budgeted work only in threads resumed by task.wait() (the Heartbeat step,
-- where the budget is also refilled): a pump started from an event (DescendantAdded, a tag signal,
-- a day / night or tier change) first waits for that step instead of working right away, so a
-- frame never gets one burst before the refill and another after it.
local FRAME_FLOOR = 16
local frameCount = 0
RunService.Heartbeat:Connect(function()
	frameCount += 1
end)
local tokenFrame = -1
local tokens = 0
local frameBudgetFn: () -> number = function()
	return Quality.pick({ low = 350, mid = 700, high = 1200 }) -- the boot script installs the Config budget
end

local function refill()
	if tokenFrame ~= frameCount then
		tokenFrame = frameCount
		local ok, b = pcall(frameBudgetFn)
		local budget = if ok and type(b) == "number" and b > 0 then b else 350
		tokens = budget + math.clamp(tokens, -budget, 0) -- unused tokens expire, debt carries over
	end
end

-- May a queue that did `done` items this frame (each reported with Util.spend) do one more?
function Util.canDo(done: number, cap: number): boolean
	if done >= cap then
		return false
	end
	if done < FRAME_FLOOR then
		return true
	end
	refill()
	return tokens > 0
end

-- How many more items a queue that did `done` this frame may do in one go (for slices of cheap
-- items: at most `cap - done`; report them with Util.spend afterwards).
function Util.allowance(done: number, cap: number): number
	local left = math.floor(cap - done)
	if left <= 0 then
		return 0
	end
	refill()
	return math.max(0, math.min(left, math.max(math.floor(tokens), FRAME_FLOOR - done)))
end

-- Reports `n` extra property writes done by the current item (beyond the 1 unit it was granted).
function Util.spend(n: number)
	if n > 0 then
		refill()
		tokens -= n
	end
end

-- What is left of this frame's budget (<= 0: spent).
function Util.budgetLeft(): number
	refill()
	return tokens
end

function Util.setFrameBudget(fn: () -> number)
	frameBudgetFn = fn
end

-- Tells GwangalliQuality that a queue is still draining a burst (stream-in after a quick travel,
-- the join), so those slow seconds do not count as a slow phone (automatic low / saver switch).
-- Called by every queue that carries work over to the next frame; at most once a second.
local lastBusyNote = -math.huge
local function noteBusy()
	local now = os.clock()
	if now - lastBusyNote >= 1 then
		lastBusyNote = now
		local q: any = Quality
		if type(q.noteBusy) == "function" then
			pcall(q.noteBusy, 2)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Instance registries (strong, pruned in the background)
---------------------------------------------------------------------------------------------------
-- reg.map[inst] -> value (read it directly), reg.list = the instances as an array. Entries are
-- added with Util.regSet and removed with Util.regRemove, or by the shared pruner: every
-- PRUNE_INTERVAL seconds it checks up to PRUNE_PER_STEP entries of every registry (one
-- IsDescendantOf each) and drops the ones no longer inside the Workspace (streamed out,
-- destroyed), calling onDrop(inst, value) first. A streamed-out instance is therefore released
-- within about #list / 1000 seconds (20 s for 20k entries), and one that streams back in as the
-- same object before that keeps its entry. onDrop may write (report the writes with Util.spend):
-- drops wait while the shared frame budget is spent, and resume at the next step. Iterate a snapshot (Util.regItems) when the loop
-- yields: the pruner reorders `list`.
export type Registry = {
	map: { [Instance]: any },
	list: { Instance },
	pos: { [Instance]: number },
	cursor: number,
	onDrop: ((Instance, any) -> ())?,
	delay: number, -- seconds between prune steps of this registry (adaptive, see below)
	acc: number,
}

-- Adaptive cadence: a registry whose last step found nothing to drop is checked half as often
-- (down to every PRUNE_IDLE seconds); one step that drops something brings it back to every
-- PRUNE_INTERVAL. A player standing still pays ~1/8 of the checks, streaming churn is pruned at
-- full speed.
local PRUNE_INTERVAL = 0.25
local PRUNE_IDLE = 2
local PRUNE_PER_STEP = 250
local registries: { Registry } = {}
local pruneStarted = false

function Util.regSet(reg: Registry, inst: Instance, value: any)
	assert(value ~= nil, "Util.regSet: value must not be nil")
	if reg.pos[inst] == nil then
		table.insert(reg.list, inst)
		reg.pos[inst] = #reg.list
	end
	reg.map[inst] = value
end

function Util.regRemove(reg: Registry, inst: Instance): any
	local i = reg.pos[inst]
	if i == nil then
		return nil
	end
	local list = reg.list
	local last = list[#list]
	list[i] = last
	reg.pos[last] = i
	list[#list] = nil
	reg.pos[inst] = nil
	local value = reg.map[inst]
	reg.map[inst] = nil
	return value
end

function Util.regItems(reg: Registry): { Instance }
	return table.clone(reg.list)
end

-- Walks the list downward from the cursor (wrapping), so the entry swapped into a removed slot
-- comes from the part of the list this cycle has already checked.
local function pruneStep(reg: Registry, budget: number): number
	local list = reg.list
	local i = reg.cursor
	local dropped = 0
	for _ = 1, math.min(budget, #list) do
		local n = #list
		if n == 0 then
			break
		end
		if i < 1 or i > n then
			i = n
		end
		local inst = list[i]
		if not inst:IsDescendantOf(workspace) then
			if reg.onDrop and Util.budgetLeft() <= 0 then
				dropped = math.max(dropped, 1) -- (work left: keep the fast cadence)
				break -- resume here at the next step
			end
			local value = Util.regRemove(reg, inst)
			dropped += 1
			if reg.onDrop then
				local ok, err = pcall(reg.onDrop, inst, value)
				if not ok then
					Util.warn("registry", "drop failed:", err)
				end
			end
		end
		i -= 1
	end
	reg.cursor = i
	return dropped
end

function Util.registry(onDrop: ((Instance, any) -> ())?): Registry
	local reg: Registry = { map = {}, list = {}, pos = {}, cursor = 0, onDrop = onDrop, delay = PRUNE_INTERVAL, acc = 0 }
	table.insert(registries, reg)
	if not pruneStarted then
		pruneStarted = true
		task.spawn(function()
			while true do
				task.wait(PRUNE_INTERVAL)
				for _, r in registries do
					r.acc += PRUNE_INTERVAL
					if r.acc + 1e-6 >= r.delay then
						r.acc = 0
						local ok, dropped = pcall(pruneStep, r, PRUNE_PER_STEP)
						if not ok then
							Util.warn("registry", dropped)
						elseif dropped > 0 then
							r.delay = PRUNE_INTERVAL
						else
							r.delay = math.min(PRUNE_IDLE, r.delay * 2)
						end
					end
				end
			end
		end)
	end
	return reg
end

---------------------------------------------------------------------------------------------------
-- Tags
---------------------------------------------------------------------------------------------------

-- Calls onAdded for every instance with `tag` inside Workspace (now and whenever one streams in)
-- and onRemoved when it streams out / loses the tag. Errors in callbacks are contained.
-- Arrivals (the instances present when watchTag is called, and every later stream-in) go through
-- ONE shared queue drained at a per-tier budget across all tags: thousands of NightNeon /
-- NightGlow / lights at join, or after a quick-travel teleport, would otherwise land in one
-- frame. Removals are handled immediately (an arrival still queued is then skipped).
-- Returns a function that disconnects everything.
-- Note: a streamed-out instance can come back as the SAME object (the engine parents it to nil
-- on stream-out), so onAdded may see an instance again, possibly still carrying local changes.
local function watchBudget(): number
	return Quality.pick({ low = 200, mid = 300, high = 500 })
end
local tagFns: { (Instance) -> () } = {}
local tagInsts: { Instance } = {}
local tagHead = 1
local tagPumping = false

local function tagPump()
	if tagPumping then
		return
	end
	tagPumping = true
	task.spawn(function()
		task.wait() -- work only in the Heartbeat step (see the shared budget above)
		while tagHead <= #tagInsts do
			local cap = watchBudget()
			local done = 0
			while tagHead <= #tagInsts and Util.canDo(done, cap) do
				local i = tagHead
				tagHead += 1
				local inst = tagInsts[i]
				if inst.Parent ~= nil then -- (cheap pre-filter; add() checks the ancestry)
					local ok, err = pcall(tagFns[i], inst)
					if not ok then
						Util.warn("watchTag", err)
					end
				end
				done += 1
				Util.spend(1)
			end
			if tagHead > #tagInsts then
				break
			end
			noteBusy()
			task.wait()
		end
		table.clear(tagFns)
		table.clear(tagInsts)
		tagHead = 1
		tagPumping = false
	end)
end

local function queueTagged(fn: (Instance) -> (), inst: Instance)
	table.insert(tagFns, fn)
	table.insert(tagInsts, inst)
	tagPump()
end

function Util.watchTag(tag: string, onAdded: (Instance) -> (), onRemoved: ((Instance) -> ())?): () -> ()
	local tracked: { [Instance]: boolean } = {}
	local alive = true
	local function add(inst: Instance)
		if not alive or tracked[inst] or not inst:IsDescendantOf(workspace) or not inst:HasTag(tag) then
			return -- (queued initial entries can be stale by the time they are handed over)
		end
		tracked[inst] = true
		local ok, err = pcall(onAdded, inst)
		if not ok then
			Util.warn(tag, "add failed:", err)
		end
	end
	local function remove(inst: Instance)
		if not tracked[inst] then
			return
		end
		tracked[inst] = nil
		if onRemoved then
			local ok, err = pcall(onRemoved, inst)
			if not ok then
				Util.warn(tag, "remove failed:", err)
			end
		end
	end
	local added = CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		if alive and not tracked[inst] then
			queueTagged(add, inst)
		end
	end)
	local removed = CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
	for _, inst in CollectionService:GetTagged(tag) do
		queueTagged(add, inst)
	end
	return function()
		alive = false
		added:Disconnect()
		removed:Disconnect()
		table.clear(tracked)
	end
end

---------------------------------------------------------------------------------------------------
-- Local hide / show state (LocalTransparencyModifier), used by Util.setHidden further below
---------------------------------------------------------------------------------------------------
-- Hiding never reparents anything (reparenting streamed instances on the client breaks the
-- streaming bookkeeping). BaseParts and Decals / Textures get LocalTransparencyModifier = 1;
-- SurfaceGuis / BillboardGuis / ParticleEmitters / Beams / Trails are disabled (guis draw even on
-- invisible parts) and re-enabled on show only if this module disabled them (attribute ATTR_OFF
-- on the effect: it lives exactly as long as the instance, whatever happens to its Lua handle).
--
-- Every root setHidden has worked on is "managed": its RootState sits in the strong registry
-- `rootReg` (released by the pruner after the root left the Workspace), and one shared
-- DescendantAdded handler applies the root's effective state (hidden if the root or any managed
-- ancestor is hidden) to instances that stream into it later.
-- The root also carries what its parts actually wear in the attribute ATTR_STATE ("hidden",
-- "mixed" while a job runs or after one was cut short, nil = shown). A root that streams out and
-- back in as the SAME object after the pruner released its state (its parts may still carry our
-- LocalTransparencyModifier values) is recognised by that attribute and always gets a full job.
-- A root that comes back as a new object has no attribute and starts fresh.
--
-- ARRIVE-HIDDEN roots (Model attribute GwArrive = true; GwangalliEnvironment.server sets it on
-- eligible near-only models at start, see its section 5): their parts / decals are SAVED hidden
-- (Transparency 1 on the server) and the shown value is 0, or the number in the part's attribute
-- GwT (the model carries GwTMix = true when any part has one). Showing writes Transparency locally
-- (a client write never replicates) and hiding writes 1 back. Their default state is therefore
-- hidden: a root that streams in far away costs nothing at all (no job, no state, no handler), and
-- a fresh copy that streams back in is hidden again whatever this client wrote before. ATTR_STATE
-- on them: nil = hidden as saved, "shown", "mixed". They never nest (the server skips near models
-- inside zones / RoomDepth / vehicles), and only a non-Atomic one keeps a DescendantAdded handler
-- (parts that trickle into it arrive hidden, so the handler only has work while it is shown).

local ATTR_STATE = "GwHideState"
local ATTR_OFF = "GwHideOff"
local ATTR_ARRIVE = "GwArrive"
local ATTR_ARRIVE_T = "GwT"
local ATTR_ARRIVE_MIX = "GwTMix"

-- list / listDirty / removing: the cached kind ~= 0 descendants of a big root (zones: thousands of
-- instances), so toggling it does not walk its whole subtree again; invalidated by any descendant
-- added (managedHandler) or removed (`removing`, connected only while a list is cached)
type RootState = {
	conn: RBXScriptConnection?,
	hidden: boolean,
	dirty: boolean,
	list: { Instance }?,
	listDirty: boolean?,
	removing: RBXScriptConnection?,
	arrive: boolean?, -- arrive-hidden root (Transparency writes, see above)
	mix: boolean?, -- arrive root with parts whose shown Transparency is in their GwT attribute
}

local rootReg = Util.registry(function(_root: Instance, st: RootState)
	if st and st.conn then
		st.conn:Disconnect()
		st.conn = nil
	end
	if st and st.removing then
		st.removing:Disconnect()
		st.removing = nil
		st.list = nil
	end
end)
local roots: { [Instance]: RootState } = rootReg.map
-- latest wish per root still waiting in hideOrder (each entry is removed when processed)
local pendingHide: { [Instance]: boolean } = {}

-- What a hide / show does to an instance, by ClassName (cached per class, so the per-instance
-- cost is one ClassName read and a table lookup instead of up to six IsA calls; model subtrees are
-- mostly Attachments, welds, meshes and gui children, which are kind 0):
--   1 = BasePart / Decal / Texture (LocalTransparencyModifier), 2 = effect with Enabled
--   (SurfaceGui / BillboardGui / ParticleEmitter / Beam / Trail), 0 = nothing to do
local kindByClass: { [string]: number } = {}
local function kindOf(inst: Instance): number
	local cn = inst.ClassName
	local k = kindByClass[cn]
	if k == nil then
		if inst:IsA("BasePart") or inst:IsA("Decal") then -- (Decal includes Texture)
			k = 1
		elseif inst:IsA("LayerCollector") or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
			k = 2
		else
			k = 0
		end
		kindByClass[cn] = k
	end
	return k :: number
end

local function applyKind(inst: Instance, kind: number, hide: boolean)
	if kind == 1 then
		local v = if hide then 1 else 0
		local p = inst :: any
		if p.LocalTransparencyModifier ~= v then
			p.LocalTransparencyModifier = v
		end
	elseif kind == 2 then
		local e = inst :: any
		if hide then
			if e.Enabled then
				e.Enabled = false
				inst:SetAttribute(ATTR_OFF, true)
				Util.spend(1)
			end
		elseif not e.Enabled and inst:GetAttribute(ATTR_OFF) == true then
			inst:SetAttribute(ATTR_OFF, nil)
			e.Enabled = true
			Util.spend(1)
		end
	end
end

-- Arrive-hidden roots: parts / decals write Transparency (1 hidden, else 0 or their GwT value);
-- effects as usual.
local function applyArrive(inst: Instance, kind: number, hide: boolean, mix: boolean?)
	if kind == 1 then
		local v = 1
		if not hide then
			v = 0
			if mix then
				local t = inst:GetAttribute(ATTR_ARRIVE_T)
				if type(t) == "number" then
					v = t
				end
			end
		end
		local p = inst :: any
		if p.Transparency ~= v then
			p.Transparency = v
		end
	else
		applyKind(inst, kind, hide)
	end
end

local function applyOne(inst: Instance, hide: boolean): number
	local kind = kindOf(inst)
	if kind ~= 0 then
		applyKind(inst, kind, hide)
		return 1
	end
	return 0
end

local function hiddenAncestor(inst: Instance): boolean
	local a = inst.Parent
	while a and a ~= workspace do
		local st = roots[a]
		if st and st.hidden then
			return true
		end
		a = a.Parent
	end
	return false
end

-- DescendantAdded handler of one managed root (it fires once per managed ancestor of `desc`, and
-- the result does not depend on the order of those runs):
--   * hidden root: the new instance is inside a hidden root, so it is hidden, whatever the others say;
--   * shown root: nothing to do for a fresh instance (it arrives visible). Only an instance that
--     still wears a hide (a part that streamed back in as the same object after an earlier hide,
--     or one a hidden root's run just hid) is looked at, and it is shown again only when no managed
--     ancestor at all is hidden.
local function managedHandler(st: RootState): (Instance) -> ()
	return function(desc: Instance)
		if st.list then
			st.listDirty = true
		end
		local kind = kindOf(desc)
		if kind == 0 then
			return
		end
		if st.arrive then
			-- arrives hidden (saved Transparency 1): only a shown root has work (never nested)
			applyArrive(desc, kind, st.hidden, st.mix)
			return
		end
		if st.hidden then
			applyKind(desc, kind, true)
			return
		end
		local d = desc :: any
		local wearsHide = if kind == 1 then d.LocalTransparencyModifier ~= 0 else (not d.Enabled and desc:GetAttribute(ATTR_OFF) == true)
		if wearsHide and not hiddenAncestor(desc) then
			applyKind(desc, kind, false)
		end
	end
end

-- State of a root setHidden works on (created on first use; a root that carries ATTR_STATE from
-- an earlier life starts dirty, so its first job rewrites every part).
-- (hidden, dirty, arrive) of a root this client holds no state for, from its attributes: a plain
-- root is visible unless an earlier life left ATTR_STATE (then its parts are unreliable: dirty); an
-- arrive-hidden root is hidden as saved unless ATTR_STATE says otherwise (then dirty too: parts that
-- streamed in meanwhile arrived hidden).
local function initialState(root: Instance): (boolean, boolean, boolean)
	local a = root:GetAttribute(ATTR_STATE)
	if root:GetAttribute(ATTR_ARRIVE) == true then
		return a ~= "shown", a ~= nil, true
	end
	return a == "hidden", a ~= nil, false
end

local function manage(root: Instance): RootState
	local st = roots[root]
	if not st then
		local hidden, dirty, arrive = initialState(root)
		local fresh: RootState = { conn = nil, hidden = hidden, dirty = dirty }
		if arrive then
			fresh.arrive = true
			fresh.mix = root:GetAttribute(ATTR_ARRIVE_MIX) == true
		end
		-- an Atomic arrive root streams as one piece and holds no script: nothing ever trickles in
		if not arrive or not (root:IsA("Model") and (root :: Model).ModelStreamingMode == Enum.ModelStreamingMode.Atomic) then
			fresh.conn = root.DescendantAdded:Connect(managedHandler(fresh))
		end
		st = fresh
		Util.regSet(rootReg, root, fresh)
	end
	return st :: RootState
end

local function setState(root: Instance, value: string?)
	local ok, err = pcall(root.SetAttribute, root, ATTR_STATE, value)
	if not ok then
		Util.warn("setHidden", err)
	end
	Util.spend(1)
end

-- True when a setHidden(root, hide) would change nothing.
local function alreadyThere(root: Instance, hide: boolean): boolean
	local st = roots[root]
	if st then
		return st.hidden == hide and not st.dirty
	end
	-- never worked on in this life: as it arrived (visible, or hidden when saved hidden), unless an
	-- earlier life left our state on it
	local hidden, dirty = initialState(root)
	return hidden == hide and not dirty
end

---------------------------------------------------------------------------------------------------
-- Shared discovery of untagged instances (one DescendantAdded listener for every module)
---------------------------------------------------------------------------------------------------
-- Util.discover({ class = "SurfaceGui" } | { name = "Window" }, fn): fn(inst) is called for every
-- matching instance inside Workspace, including ones that stream in later. The event callback
-- only reads ClassName / Name and queues matches; the queue is drained in batches
-- (Config.Mobile.DiscoverPerFrame) so the join burst (tens of thousands of instances) and the
-- initial scan never land in one frame. Removal is not reported: callers keep a Util.registry
-- (pruned in the background) and check Util.inWorld(inst) before writing. fn must be idempotent: an instance that streams out and
-- back in as the same object is delivered again (possibly still carrying the caller's changes),
-- and one that streams in while the initial scan runs can be delivered twice.
--
-- Tag mode: a filter can name a CollectionService tag (Util.discover({ class = "SurfaceGui",
-- tag = "GwSurfaceGui" }, fn)); fn then also gets every instance carrying that tag. Once the place
-- says every matching instance carries its filter's tag (Workspace attribute GwDiscoverTagged =
-- true, set by the build or by GwangalliEnvironment.server after tagging at server start), and
-- every filter has a tag, the Workspace-wide DescendantAdded listener and the initial scan are not
-- used at all: a client that joins or quick-travels then pays one signal per TAGGED instance
-- (about 10k in the place) instead of one handler per streamed-in instance (270k). A client that
-- started before the attribute appeared switches over when it does.
local TAGGED_ATTR = "GwDiscoverTagged"
type DiscoverFilter = { class: string?, name: string?, tag: string? }
type Registration = { filter: DiscoverFilter, fn: (Instance) -> () }
local registrations: { Registration } = {}
local tagMode = false
local listenerConn: RBXScriptConnection? = nil
local scanAbort = false

local byClass: { [string]: { (Instance) -> () } } = {}
local byName: { [string]: { (Instance) -> () } } = {}
local discoverStarted = false
local discoverEnabled = true
local perFrameFn: () -> number = function()
	return 300
end
local queue: { Instance } = {}
local queueHead = 1
local pumping = false
-- waiting in `queue` (every entry is removed when its first queue entry is delivered)
local queued: { [Instance]: boolean } = {}

local function deliver(inst: Instance)
	if not queued[inst] then
		return -- a duplicate entry, already delivered
	end
	queued[inst] = nil
	if not inst:IsDescendantOf(workspace) then
		return -- streamed out again before its turn (possibly with an ancestor: test the ancestry)
	end
	local list = byClass[inst.ClassName]
	if list then
		for _, fn in list do
			local ok, err = pcall(fn, inst)
			if not ok then
				Util.warn("discover", inst.ClassName, err)
			end
		end
	end
	list = byName[inst.Name]
	if list then
		for _, fn in list do
			local ok, err = pcall(fn, inst)
			if not ok then
				Util.warn("discover", inst.Name, err)
			end
		end
	end
end

local function budgetNow(): number
	local ok, n = pcall(perFrameFn)
	return math.max(20, if ok and type(n) == "number" then n else 300)
end


-- Drains the queue from a deferred thread, at most budgetNow() deliveries per frame, so every
-- match of one frame (join burst, initial scan) shares that frame's budget.
local function pump()
	if pumping then
		return
	end
	pumping = true
	task.spawn(function()
		task.wait() -- work only in the Heartbeat step (see the shared budget above)
		while queueHead <= #queue do
			local cap = budgetNow()
			local done = 0
			while queueHead <= #queue and Util.canDo(done, cap) do
				local inst = queue[queueHead]
				queueHead += 1
				local ok, err = pcall(deliver, inst)
				if not ok then
					Util.warn("discover", err)
				end
				done += 1
				Util.spend(1)
			end
			if queueHead > #queue then
				break
			end
			noteBusy()
			task.wait()
		end
		table.clear(queue)
		queueHead = 1
		pumping = false
	end)
end

local function matches(inst: Instance): boolean
	return byClass[inst.ClassName] ~= nil or byName[inst.Name] ~= nil
end

local function enqueue(inst: Instance)
	if not queued[inst] and matches(inst) then
		queued[inst] = true
		table.insert(queue, inst)
		pump()
	end
end

-- Chunked walk of the Workspace (yields): the tree is walked by GetChildren down to SCAN_DEPTH
-- levels (map root -> districts -> rows -> groups -> buildings), and deeper wherever a container
-- is flat (more than SCAN_FLAT children); only below that with GetDescendants, so no single call
-- returns a giant list. visit(inst) is called for every instance; the walk yields every
-- budgetNow() * 10 visits (and calls onYield first, if given).
local SCAN_DEPTH = 4
local SCAN_FLAT = 200
local function walkWorkspace(visit: (Instance) -> (), onYield: (() -> ())?)
	local visited = 0
	local function step(inst: Instance)
		visit(inst)
		visited += 1
		if visited >= math.max(500, budgetNow() * 10) then
			visited = 0
			if onYield then
				onYield()
			end
			task.wait()
			if scanAbort then
				error("scan aborted (tag mode)", 0) -- caught by the caller's pcall
			end
		end
	end
	local function walk(node: Instance, depth: number)
		local children = node:GetChildren()
		if depth >= SCAN_DEPTH and #children <= SCAN_FLAT then
			for _, d in node:GetDescendants() do
				step(d)
			end
			return
		end
		for _, child in children do
			if child.Parent ~= nil then
				step(child)
				walk(child, depth + 1)
			end
		end
	end
	for _, top in workspace:GetChildren() do
		if top.Parent == nil or top:IsA("Terrain") or top:IsA("Camera") then
			continue
		end
		step(top)
		walk(top, 0)
	end
end

local function initialScan()
	local ok, err = pcall(walkWorkspace, function(inst)
		if not queued[inst] and matches(inst) then
			queued[inst] = true
			table.insert(queue, inst)
		end
	end, pump)
	if not ok and not scanAbort then
		Util.warn("discover", "initial scan:", err)
	end
	pump()
end

-- fn for the tag path of a registration (the tag is authoritative for the name; the class is
-- still checked, so a stray tag never hands fn an instance of another class)
local function tagHandler(reg: Registration): (Instance) -> ()
	local cls = reg.filter.class
	local fn = reg.fn
	return function(inst: Instance)
		if cls and inst.ClassName ~= cls then
			return
		end
		fn(inst)
	end
end

local function allTagged(): boolean
	for _, reg in registrations do
		if not reg.filter.tag then
			return false
		end
	end
	return #registrations > 0
end

-- Drops the Workspace-wide listener: every filter is served by its tag from now on.
local function enterTagMode()
	if tagMode then
		return
	end
	tagMode = true
	scanAbort = true
	if listenerConn then
		listenerConn:Disconnect()
		listenerConn = nil
	end
	table.clear(byClass)
	table.clear(byName)
	-- entries still queued are skipped by deliver (no handlers left); their tags deliver them
end

-- Registers a handler (call from a module's start; Util.startDiscovery runs the scan once all
-- modules registered; a later registration triggers its own chunked catch-up scan).
function Util.discover(filter: DiscoverFilter, fn: (Instance) -> ())
	local reg: Registration = { filter = filter, fn = fn }
	table.insert(registrations, reg)
	if filter.tag then
		-- the tag path runs in every mode (tagged instances that do not match the name / class
		-- filter are delivered too; fn is idempotent, so a double delivery is harmless)
		Util.watchTag(filter.tag, tagHandler(reg))
	end
	if not discoverEnabled then
		return
	end
	if tagMode then
		if filter.tag then
			return
		end
		-- an untagged filter after the switch: back to the listener for it (catch-up below)
		tagMode = false
		scanAbort = false
		if not listenerConn then
			listenerConn = workspace.DescendantAdded:Connect(enqueue)
		end
	end
	if filter.class then
		local list = byClass[filter.class] or {}
		byClass[filter.class] = list
		table.insert(list, fn)
	end
	if filter.name then
		local list = byName[filter.name] or {}
		byName[filter.name] = list
		table.insert(list, fn)
	end
	if discoverStarted then
		-- late registration: catch up only for this filter (instances delivered before the
		-- registration never reach fn through the queue), chunked like the initial scan
		task.spawn(function()
			task.wait() -- (the walk and the calls below run in the Heartbeat step)
			local found: { Instance } = {}
			pcall(walkWorkspace, function(inst)
				if (filter.class and inst.ClassName == filter.class) or (filter.name and inst.Name == filter.name) then
					table.insert(found, inst)
				end
			end)
			local done = 0
			for _, inst in found do
				if inst:IsDescendantOf(workspace) then
					if not Util.canDo(done, budgetNow()) then
						task.wait()
						done = 0
					end
					local ok, err = pcall(fn, inst)
					if not ok then
						Util.warn("discover", err)
					end
					done += 1
					Util.spend(1)
				end
			end
		end)
	end
end

-- Starts the shared listener + the chunked initial scan. `enabled == false` (Config
-- Mobile.ScanDescendants) turns name / class discovery off entirely (tags only).
function Util.startDiscovery(perFrame: () -> number, enabled: boolean?)
	if discoverStarted then
		return
	end
	discoverStarted = true
	perFrameFn = perFrame
	if enabled == false then
		discoverEnabled = false
		table.clear(byClass)
		table.clear(byName)
		return
	end
	if next(byClass) == nil and next(byName) == nil then
		return
	end
	if workspace:GetAttribute(TAGGED_ATTR) == true and allTagged() then
		enterTagMode() -- (every filter's tag watch is already running)
		return
	end
	listenerConn = workspace.DescendantAdded:Connect(enqueue)
	task.spawn(initialScan)
	local attrConn: RBXScriptConnection? = nil
	attrConn = workspace:GetAttributeChangedSignal(TAGGED_ATTR):Connect(function()
		if workspace:GetAttribute(TAGGED_ATTR) == true and allTagged() then
			enterTagMode()
			if attrConn then
				attrConn:Disconnect()
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Local hide / show (LocalTransparencyModifier), batched
---------------------------------------------------------------------------------------------------
-- Util.setHidden(root, hide) queues the wish; a deferred pump processes one root at a time in
-- slices of the per-frame budget (Util.setHideBudget), so a big model never lands in one frame.
-- Nested roots (near-only detail inside a RoomDepth model or a venue zone) are supported: a root
-- inside a hidden root stays hidden whatever its own wish, and gets its own wish back when the outer
-- one is shown (the show job skips the subtrees of nested roots that want to stay hidden). A slice
-- counts parts / decals / guis / effects as one unit and other instances as 1/8, and big roots
-- (zones) keep their filtered descendant list between toggles.

-- Two lanes: shows first (geometry the camera is approaching, a venue the player just walked or
-- travelled into), then hides (far detail, which may take its time). A root whose queued hide turns
-- into a show is promoted to the show lane; each root is processed once, with its latest wish.
local hideOrder: { Instance } = {}
local showOrder: { Instance } = {}
local hidePumping = false
local BIG_LIST = 600 -- roots with at least this many descendants keep their filtered list cached
local hideBudgetFn: () -> number = function()
	return Quality.pick({ low = 200, mid = 400, high = 800 }) -- DetailLOD installs the Config budget
end

-- blocked (show jobs): memo per container below the root: true = inside a nested root that wants
-- to stay hidden (its subtree keeps the hide), false = not
type HideJob = { root: Instance, hide: boolean, list: { Instance }, i: number, nested: { Instance }, blocked: { [Instance]: boolean }?, arrive: boolean?, mix: boolean? }

local function startJob(root: Instance, hide: boolean): HideJob?
	if not root:IsDescendantOf(workspace) then
		-- streamed out meanwhile: leave the state as it is (it still describes the parts); the
		-- consumer asks again when the root is back
		return nil
	end
	if alreadyThere(root, hide) then
		return nil -- already in that state (a never-hidden root is visible)
	end
	local st = manage(root)
	st.dirty = false
	st.hidden = hide
	if hiddenAncestor(root) then
		-- an enclosing hidden root already keeps everything under it hidden (and hides parts that
		-- stream in); this root's own wish is re-applied when that ancestor is shown (finishJob)
		return nil
	end
	setState(root, "mixed") -- until the job completes (stays if it is cut short)
	applyOne(root, hide)
	local list = st.list
	if not list or st.listDirty then
		list = nil
		local all = root:GetDescendants()
		if #all >= BIG_LIST then
			-- keep only what a hide / show writes (nested roots are found through the ancestors)
			local keep = table.create(#all)
			for _, d in all do
				if kindOf(d) ~= 0 then
					table.insert(keep, d)
				end
			end
			st.list = keep
			st.listDirty = false
			if not st.removing then
				-- one call is enough to invalidate the list (a zone that streams out would otherwise
				-- run this for each of its thousands of descendants); re-armed with the next list
				st.removing = root.DescendantRemoving:Once(function()
					st.listDirty = true
					st.removing = nil
				end)
			end
			list = keep
		else
			list = all
		end
	end
	if st.arrive then
		-- arrive roots never hold nested roots: no ancestor memo needed
		return { root = root, hide = hide, list = list :: { Instance }, i = 1, nested = {}, blocked = nil, arrive = true, mix = st.mix }
	end
	return { root = root, hide = hide, list = list :: { Instance }, i = 1, nested = {}, blocked = if hide then nil else {} }
end

local queueRoot: (Instance, boolean) -> ()

local function finishJob(job: HideJob)
	if job.arrive then
		setState(job.root, if job.hide then nil else "shown")
		return
	end
	setState(job.root, if job.hide then "hidden" else nil)
	if job.hide then
		return
	end
	-- nested roots that still want to be hidden: the show job skipped their subtrees, so their parts
	-- kept the hide. Only a root whose own state is unreliable (dirty: a job of its own was cut short,
	-- or it came back with an earlier life's state) gets a full, budgeted re-hide in the hide lane.
	for _, other in job.nested do
		local st = roots[other]
		if st and st.hidden and st.dirty and other:IsDescendantOf(workspace) and not hiddenAncestor(other) then
			queueRoot(other, true)
		end
	end
end

-- A job that could not finish: its root's parts are mixed, so the next setHidden runs in full.
local function markDirty(root: Instance)
	local st = roots[root]
	if st then
		st.dirty = true
	end
end

-- Show jobs: is `inst` inside a nested root (below job.root) that wants to stay hidden? Walks up to
-- the first container with a known answer and memoises the answer for every container on the way,
-- so each container is looked at once per job. Such roots are collected in job.nested.
local function insideHiddenNested(job: HideJob, inst: Instance): boolean
	local memo = job.blocked :: { [Instance]: boolean }
	local chain: { Instance }? = nil
	local x = inst.Parent
	local v = false
	while x and x ~= job.root do
		local m = memo[x]
		if m ~= nil then
			v = m
			break
		end
		local st = roots[x]
		if st and st.hidden then
			memo[x] = true
			table.insert(job.nested, x)
			v = true
			break
		elseif pendingHide[x] == true then
			memo[x] = true -- its own hide is queued: leave its parts for that job
			v = true
			break
		end
		if not chain then
			chain = {}
		end
		table.insert(chain :: { Instance }, x)
		x = x.Parent
	end
	if chain then
		for _, c in chain do
			memo[c] = v
		end
	end
	return v
end

-- Processes the job's list until `budget` work units are spent: a write-capable instance (part,
-- decal, gui, effect) is 1 unit, anything else (attachments, welds, meshes, gui children) and
-- anything skipped 1/8. Show jobs skip the subtrees of nested roots that want to stay hidden (their
-- parts keep the hide: no show-then-hide flash, no double writes). Returns the units spent.
local function runSlice(job: HideJob, budget: number): number
	local list = job.list
	local n = #list
	local i = job.i
	local hide = job.hide
	local blocked = job.blocked
	local work = 0
	if job.arrive then
		local mix = job.mix
		while i <= n and work < budget do
			local inst = list[i]
			i += 1
			local kind = kindOf(inst)
			if kind ~= 0 then
				applyArrive(inst, kind, hide, mix)
				work += 1
			else
				work += 0.125
			end
		end
		job.i = i
		return math.ceil(work)
	end
	while i <= n and work < budget do
		local inst = list[i]
		i += 1
		if blocked and insideHiddenNested(job, inst) then
			work += 0.125
			continue
		end
		local kind = kindOf(inst)
		if kind ~= 0 then
			applyKind(inst, kind, hide)
			work += 1
		else
			work += 0.125
		end
	end
	job.i = i
	return math.ceil(work)
end

local function hidePump()
	if hidePumping then
		return
	end
	hidePumping = true
	-- waits for the Heartbeat step first: every setHidden of the current burst (a watchTag chunk,
	-- a discovery batch) is queued before the first slice runs, and the slices share the budget
	task.spawn(function()
		task.wait()
		local i, si = 1, 1
		local job: HideJob? = nil
		while true do
			local okBudget, b = pcall(hideBudgetFn)
			local cap = math.max(50, if okBudget and type(b) == "number" then b else 200)
			local done = 0
			while true do
				local allowed = Util.allowance(done, cap)
				if allowed <= 0 then
					break
				end
				if job then
					if not job.root:IsDescendantOf(workspace) then
						markDirty(job.root) -- streamed out mid-way (may come back as the same object)
						job = nil
						continue
					end
					local ok, result = pcall(runSlice, job, allowed)
					if not ok then
						Util.warn("setHidden", result)
						markDirty(job.root)
						job = nil
						continue
					end
					done += result
					Util.spend(result)
					if job.i > #job.list then
						local okFinish, err = pcall(finishJob, job)
						if not okFinish then
							Util.warn("setHidden", err)
						end
						job = nil
					end
				elseif si <= #showOrder or i <= #hideOrder then
					local root
					if si <= #showOrder then
						root = showOrder[si]
						si += 1
					else
						root = hideOrder[i]
						i += 1
					end
					local want = pendingHide[root]
					if want ~= nil then
						pendingHide[root] = nil
						local ok, result = pcall(startJob, root, want)
						if ok then
							job = result
						else
							Util.warn("setHidden", result)
						end
						done += 1
						Util.spend(1)
					end
				else
					break
				end
			end
			if not job and i > #hideOrder and si > #showOrder then
				break
			end
			noteBusy()
			task.wait()
		end
		table.clear(hideOrder)
		table.clear(showOrder)
		hidePumping = false
	end)
end

-- Queues a local hide (true) or show (false) of `root` and everything under it. Repeated calls
-- before the queue reaches the root keep only the latest wish. Cheap when nothing changes.
function Util.setHidden(root: Instance, hide: boolean)
	local prev = pendingHide[root]
	if prev == nil then
		if alreadyThere(root, hide) then
			return
		end
		table.insert(if hide then hideOrder else showOrder, root)
	elseif prev and not hide then
		table.insert(showOrder, root) -- a queued hide became a show: promote it
	end
	pendingHide[root] = hide
	hidePump()
end
queueRoot = Util.setHidden

-- True while `root` itself wants to be hidden (not counting hidden ancestors).
function Util.isHidden(root: Instance): boolean
	local st = roots[root]
	if st then
		return st.hidden
	end
	return (initialState(root))
end

function Util.setHideBudget(fn: () -> number)
	hideBudgetFn = fn
end

---------------------------------------------------------------------------------------------------
-- Sweeps
---------------------------------------------------------------------------------------------------

-- Returns a function sweep(items, fn) that calls fn(item) for every item of the array, at most
-- perFrame per frame (a number, or a function returning one, read every frame). Starting a new
-- sweep cancels the previous one (generation counter).
function Util.sweeper(perFrame: number | () -> number): (items: { any }, fn: (any) -> ()) -> ()
	local generation = 0
	local function cap(): number
		local n = if type(perFrame) == "function" then perFrame() else perFrame
		return math.max(1, math.floor(tonumber(n) or 200))
	end
	return function(items: { any }, fn: (any) -> ())
		generation += 1
		local mine = generation
		task.spawn(function()
			task.wait() -- work only in the Heartbeat step (see the shared budget above)
			local done = 0
			local limit = cap()
			for _, item in items do
				if generation ~= mine then
					return
				end
				if not Util.canDo(done, limit) then
					task.wait()
					if generation ~= mine then
						return
					end
					done = 0
					limit = cap()
				end
				local ok, err = pcall(fn, item)
				if not ok then
					Util.warn("sweep", err)
				end
				done += 1
				Util.spend(1)
			end
		end)
	end
end

-- Reorders `items` nearest-first around `origin` using distance rings (O(n), no sort):
-- posOf(item) returns a Vector3 or nil (unknown positions go last).
function Util.nearestFirst<T>(items: { T }, origin: Vector3?, posOf: (T) -> Vector3?, ring: number?): { T }
	if not origin or #items < 2 then
		return items
	end
	local step = ring or 120
	local rings: { { T } } = {}
	local unknown: { T } = {}
	local maxRing = 0
	for _, item in items do
		local p = posOf(item)
		if p then
			local r = math.min(64, math.floor((p - origin).Magnitude / step)) + 1
			local bucket = rings[r]
			if not bucket then
				bucket = {}
				rings[r] = bucket
			end
			table.insert(bucket, item)
			if r > maxRing then
				maxRing = r
			end
		else
			table.insert(unknown, item)
		end
	end
	local out = table.create(#items)
	for r = 1, maxRing do
		local bucket = rings[r]
		if bucket then
			table.move(bucket, 1, #bucket, #out + 1, out)
		end
	end
	table.move(unknown, 1, #unknown, #out + 1, out)
	return out
end

function Util.keys<K>(t: { [K]: any }): { K }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	return out
end

function Util.cameraPosition(): Vector3?
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position
end

-- Camera position and view direction (nil when there is no camera yet).
function Util.cameraView(): (Vector3?, Vector3?)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local cf = camera.CFrame
	return cf.Position, cf.LookVector
end

-- World position of a light's host (BasePart or Attachment).
function Util.hostPosition(host: Instance?): Vector3?
	if host == nil then
		return nil
	elseif host:IsA("BasePart") then
		return host.Position
	elseif host:IsA("Attachment") then
		return host.WorldPosition
	end
	return nil
end

-- True while any shared queue (tag arrivals, discovery, hide / show) still has work waiting.
function Util.busy(): boolean
	return tagPumping or pumping or hidePumping
end

-- Heartbeat-driven ticker at `hz` (a number or a function returning one); fn(dtSinceLastTick).
-- The per-frame cost between ticks is one addition and a compare.
function Util.ticker(hz: number | () -> number, fn: (number) -> ()): RBXScriptConnection
	local acc = 0
	return RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		local rate = if type(hz) == "function" then hz() else hz
		local interval = 1 / math.max(0.1, rate)
		if acc >= interval then
			local elapsed = acc
			acc = if acc > interval * 3 then 0 else acc - interval
			fn(elapsed)
		end
	end)
end

return Util
