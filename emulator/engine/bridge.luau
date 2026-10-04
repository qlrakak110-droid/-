--!nocheck
-- tools/player/engine/bridge.luau — the JS <-> Luau boundary of the RobloxLite runtime (PLAYER_ARCH §2, §5).
--
--   local bridge = require("bridge")
--   bridge.boot(placeBuffer, opts) -> nil | errorString      (shell: GW.readBlob("place.bin"), docs/player_api/shell.md)
--   bridge.step(dt, inputJSON) -> changesJSON               ONE call per engine tick
--   bridge.studio(requestJSON) -> replyJSON                 engine/studio.luau (call mode)
--   bridge.bootJSON(placeBlobName, optsJSON) -> JSON        test harness convenience (reads the blob itself)
--
-- Frame order inside step (Roblox task scheduler): clock += dt; input (camera, character, UserInputService, GUI,
-- prompts); RenderStepped/PreRender/BindToRenderStep (client); PreAnimation/Stepped/PreSimulation; humanoid
-- walking + tweens; Heartbeat/PostSimulation; task.wait/delay resumption; remote delivery; join timeline;
-- then the batched change list. Every phase is followed by a flush of deferred threads.
--
-- Change ops (docs/player_api/engine.md has the full field list): part, partRemoved, light, lightRemoved, sign,
-- lighting, camera, humanoid, teleport, character, gui/guiSet/guiAdd/guiDel/guiParent/guiPos/guiFocus, prompt,
-- notify, output, studio, studioReplies, core, nightWindows, ready, engineStats, joint, jointRemoved.
-- joint {id, type, part0, part1, c0?, c1?, enabled}: rigid joints (JointInstance / WeldConstraint) that touch a part the
-- JS physics simulates (unanchored + JS has a record), so welded assemblies behave like Roblox (a part welded to an
-- anchored part stays put). Joints between untouched place parts are never sent.

local DT = require("./datatypes")
local Enums = require("./enums")
local Signal = require("./signal")
local ClassDB = require("./classdb")
local I = require("./instance")
local Loader = require("./loader")
local Sched = require("./sched")
local Env = require("./env")
local Remotes = require("./remotes")
local Services = require("./services")
local okStudio, Studio = pcall(require, "./studio")
if not okStudio then
	Studio = nil
end
-- Rigid assemblies (welds move parts together, Roblox assembly semantics)
local okAsm, Asm = pcall(require, "./assembly")
if not okAsm or type(Asm) ~= "table" then
	Asm = nil
end
-- Sound playback + audio environment ops for js/audio.js (optional module)
local okAudio, Audio = pcall(require, "./audio")
if not okAudio or type(Audio) ~= "table" then
	Audio = nil
end

local Bridge = {}
Bridge.VERSION = 1

local Enum = Enums.Enum
local S = Services.S
local floor, abs, sqrt = math.floor, math.abs, math.sqrt
local clock = os.clock
local tostring, type, pairs = tostring, type, pairs

local host = nil
local booted = false
local studio = nil
local bootInfo = nil
local frameCount = 0
local stepMsAcc, stepMsMax, stepN = 0, 0, 0
local PH = { decode = 0, input = 0, phases = 0, collect = 0, encode = 0, steps = 0, cParts = 0, cGui = 0, cPrompts = 0, cJoints = 0, cOut = 0 }
Bridge.phaseTimes = PH

---------------------------------------------------------------------------------------------------------
-- JSON encoding (compact, fast paths for numbers)
---------------------------------------------------------------------------------------------------------
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function escChar(c)
	return ESC[c] or string.format("\\u%04x", string.byte(c))
end
local function jstr(s)
	if string.find(s, '[%c"\\]') then
		return '"' .. string.gsub(s, '[%c"\\]', escChar) .. '"'
	end
	return '"' .. s .. '"'
end
local function jnum(n)
	if n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end
	if n == floor(n) and abs(n) < 1e15 then
		return tostring(floor(n))
	end
	return tostring(floor(n * 10000 + 0.5) / 10000)
end
local function jnum3(n) -- positions: millistuds
	if n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end
	local r = floor(n * 1000 + 0.5) / 1000
	if r == floor(r) then
		return tostring(floor(r))
	end
	return tostring(r)
end
Bridge.jstr, Bridge.jnum = jstr, jnum

local encodeValue
local function encodeArrayOrObject(t, out, depth)
	local n = #t
	local count = 0
	local isArr = true
	for k in t do
		count += 1
		if type(k) ~= "number" or k < 1 or k > n or k ~= floor(k) then
			isArr = false
			break
		end
	end
	if isArr and count == n then
		if n == 0 then
			out[#out + 1] = "[]"
			return
		end
		out[#out + 1] = "["
		for i = 1, n do
			if i > 1 then
				out[#out + 1] = ","
			end
			encodeValue(t[i], out, depth + 1)
		end
		out[#out + 1] = "]"
		return
	end
	out[#out + 1] = "{"
	local first = true
	for k, v in t do
		if v ~= nil and type(v) ~= "function" then
			if not first then
				out[#out + 1] = ","
			end
			first = false
			out[#out + 1] = jstr(tostring(k))
			out[#out + 1] = ":"
			encodeValue(v, out, depth + 1)
		end
	end
	out[#out + 1] = "}"
end

-- datatype -> tagged JSON text (DT.encode format, gui.md)
local function encodeTyped(v, out)
	if I.isInstance(v) then
		out[#out + 1] = '{"t":"Ref","v":' .. tostring(I.idOf(v)) .. "}"
		return true
	end
	local ty = DT.typeof(v)
	if ty == "UDim2" then
		out[#out + 1] = '{"t":"UDim2","v":[' .. jnum(v.X.Scale) .. "," .. jnum(v.X.Offset) .. "," .. jnum(v.Y.Scale) .. "," .. jnum(v.Y.Offset) .. "]}"
	elseif ty == "Color3" then
		out[#out + 1] = '{"t":"Color3","v":[' .. jnum(v.R) .. "," .. jnum(v.G) .. "," .. jnum(v.B) .. "]}"
	elseif ty == "Vector2" then
		out[#out + 1] = '{"t":"Vector2","v":[' .. jnum(v.X) .. "," .. jnum(v.Y) .. "]}"
	elseif ty == "Vector3" then
		out[#out + 1] = '{"t":"Vector3","v":[' .. jnum3(v.X) .. "," .. jnum3(v.Y) .. "," .. jnum3(v.Z) .. "]}"
	elseif ty == "UDim" then
		out[#out + 1] = '{"t":"UDim","v":[' .. jnum(v.Scale) .. "," .. jnum(v.Offset) .. "]}"
	elseif ty == "EnumItem" then
		out[#out + 1] = '{"t":"Enum","v":[' .. jstr(tostring(v.EnumType)) .. "," .. jstr(v.Name) .. "]}"
	elseif ty == "Font" then
		out[#out + 1] = '{"t":"Font","v":[' .. jstr(v.Family) .. "," .. jstr(v.Weight.Name) .. "," .. jstr(v.Style.Name) .. "]}"
	elseif ty == "CFrame" then
		out[#out + 1] = '{"t":"CFrame","v":['
		for i = 1, 12 do
			if i > 1 then
				out[#out + 1] = ","
			end
			out[#out + 1] = if i <= 3 then jnum3(v[i]) else jnum(v[i])
		end
		out[#out + 1] = "]}"
	else
		local ok, tagged = pcall(DT.encode, v)
		if ok and type(tagged) == "table" and getmetatable(tagged) == nil then
			encodeArrayOrObject(tagged, out, 0)
		else
			out[#out + 1] = "null"
		end
	end
	return true
end

function encodeValue(v, out, depth)
	local t = type(v)
	if t == "nil" then
		out[#out + 1] = "null"
	elseif t == "boolean" then
		out[#out + 1] = if v then "true" else "false"
	elseif t == "number" then
		out[#out + 1] = jnum(v)
	elseif t == "string" then
		out[#out + 1] = jstr(v)
	elseif t == "table" then
		if depth > 40 then
			out[#out + 1] = "null"
			return
		end
		if getmetatable(v) ~= nil then
			encodeTyped(v, out)
			return
		end
		encodeArrayOrObject(v, out, depth)
	else
		out[#out + 1] = "null"
	end
end
local function jsonEncode(v)
	local out = {}
	encodeValue(v, out, 0)
	return table.concat(out)
end
Bridge.jsonEncode = jsonEncode

local function cfArray(cf, out)
	out[#out + 1] = "["
	out[#out + 1] = jnum3(cf[1])
	out[#out + 1] = ","
	out[#out + 1] = jnum3(cf[2])
	out[#out + 1] = ","
	out[#out + 1] = jnum3(cf[3])
	for i = 4, 12 do
		out[#out + 1] = ","
		out[#out + 1] = jnum(cf[i])
	end
	out[#out + 1] = "]"
end
local function cfJSON(cf)
	local out = {}
	cfArray(cf, out)
	return table.concat(out)
end
local function colorNum(c)
	local r = math.clamp(floor(c.R * 255 + 0.5), 0, 255)
	local g = math.clamp(floor(c.G * 255 + 0.5), 0, 255)
	local b = math.clamp(floor(c.B * 255 + 0.5), 0, 255)
	return r * 65536 + g * 256 + b
end

---------------------------------------------------------------------------------------------------------
-- Change tracking state
---------------------------------------------------------------------------------------------------------
local F_CF, F_SIZE, F_COLOR, F_TR, F_MAT, F_SHAPE, F_VIS, F_REFL, F_COLL, F_ANCH, F_MESH, F_LTM, F_FULL, F_VEL = 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192
local PART_PROP = {
	CFrame = F_CF, Position = F_CF, Orientation = F_CF, Rotation = F_CF, Size = F_SIZE, Color = F_COLOR, BrickColor = F_COLOR,
	Transparency = F_TR, LocalTransparencyModifier = F_LTM, Material = F_MAT, MaterialVariant = F_MAT, Shape = F_SHAPE,
	Reflectance = F_REFL, CanCollide = F_COLL, CanQuery = F_COLL, CanTouch = F_COLL, CollisionGroup = F_COLL,
	Massless = F_COLL, Anchored = F_ANCH, AssemblyLinearVelocity = F_VEL, AssemblyAngularVelocity = F_VEL, RootPriority = F_COLL,
	CustomPhysicalProperties = F_COLL,
}
local SPATIAL_MASK = F_CF + F_SIZE + F_VIS + F_COLL -- (CanQuery changes move parts in / out of the query grid)
local T = {} -- tracking tables (reset on boot)

local function resetTracking()
	T.partDirty = {} -- part -> mask
	T.partKnown = setmetatable({}, { __mode = "k" }) -- part -> true (JS has a full record)
	T.runtime = setmetatable({}, { __mode = "k" }) -- instance created at runtime
	T.removed = {} -- ids of destroyed parts
	T.guiKnown = setmetatable({}, { __mode = "k" }) -- gui node -> parent node id (0 = root)
	T.guiTouched = {} -- inst -> true (structure changed this step)
	T.guiDirty = {} -- inst -> { prop = true }
	T.guiRoots = setmetatable({}, { __mode = "k" }) -- root -> true
	T.billboards = setmetatable({}, { __mode = "k" }) -- billboard root -> last pos string
	T.lightDirty = {} -- light -> true
	T.lightKnown = setmetatable({}, { __mode = "k" })
	T.lightRemoved = {}
	T.signDirty = {} -- surfaceGui -> true
	T.lightingDirty = true
	T.lightingAt = -1
	T.cameraDirty = false
	T.humanoidDirty = false
	T.teleport = false
	T.characterOp = false
	T.promptSig = ""
	T.promptAt = -1
	T.nightDirty = {}
	T.focus = {}
	T.jointDirty = {} -- joint -> true
	T.jointKnown = setmetatable({}, { __mode = "k" }) -- joint -> true (JS has it)
	T.jointRemoved = {} -- ids
	T.jointsOf = setmetatable({}, { __mode = "k" }) -- part -> { joint = true }
	T.consDirty = {} -- mover constraint -> true
	T.consKnown = setmetatable({}, { __mode = "k" }) -- constraint -> true (JS has it)
	T.consRemoved = {} -- ids
	T.asmMember = setmetatable({}, { __mode = "k" }) -- part -> root id (member of an assembly JS places from its root)
	T.coreSent = false
	T.npcDirty = {} -- humanoid -> true (rig (re)registration)
	T.npcKnown = setmetatable({}, { __mode = "k" }) -- humanoid -> id sent to JS
	T.npcAnim = {} -- humanoid -> true (animation / Sit changed)
	T.npcPose = setmetatable({}, { __mode = "k" }) -- humanoid -> {pose, speed, track}
	-- NPC rig follow: the limbs of a registered rig follow its root part (Roblox moves a whole assembly when its root
	-- moves; the engine has no joint solver). Limb CFrames are rawSet in the engine (prompts / billboards / queries
	-- stay right) and NOT sent: render3d places them from the same rest offsets (npc op `rel`).
	T.rigs = setmetatable({}, { __mode = "k" }) -- controller (Humanoid / AnimationController) -> rig
	T.rigByRoot = setmetatable({}, { __mode = "k" }) -- root part -> rig
	T.rigByModel = setmetatable({}, { __mode = "k" }) -- model -> rig
	T.rigPart = setmetatable({}, { __mode = "k" }) -- limb part -> rig
	T.rigMoved = {} -- rig -> true (root moved since the last collect)
end
resetTracking()

-- local character parts are drawn by character.js: never emitted as part ops
local function isCharacterPart(inst)
	local set = S.characterPartSet
	return set ~= nil and set[inst] == true
end

local function inWorkspace(inst)
	local ws = S.workspace
	local x = I.parentOf(inst)
	while x ~= nil do
		if x == ws then
			return true
		end
		x = I.parentOf(x)
	end
	return false
end

local function markPart(part, mask)
	if isCharacterPart(part) then
		return
	end
	local cur = T.partDirty[part]
	T.partDirty[part] = if cur then bit32.bor(cur, mask) else mask
end

-- GUI roots: ScreenGui/BillboardGui/SurfaceGui under PlayerGui; BillboardGuis under Workspace
local function isGuiRoot(inst)
	local cls = I.classOf(inst)
	if not cls.isA.LayerCollector then
		return false
	end
	local p = I.parentOf(inst)
	if p == nil then
		return false
	end
	if S.playerGui and (p == S.playerGui) then
		return true
	end
	if cls.isA.BillboardGui and S.workspace and inWorkspace(inst) then
		return true
	end
	return false
end

local function isNodeClass(inst)
	return not I.classOf(inst).isA.LuaSourceContainer
end

-- nearest tracked root of inst (or nil)
local function guiRootOf(inst)
	local x = inst
	local n = 0
	while x ~= nil and n < 200 do
		if T.guiRoots[x] then
			return x
		end
		if isGuiRoot(x) then
			return x
		end
		x = I.parentOf(x)
		n += 1
	end
	return nil
end

---------------------------------------------------------------------------------------------------------
-- Hooks (instance.luau)
---------------------------------------------------------------------------------------------------------
local handlerCache = {} -- class name -> handler kind
-- Roblox movers the JS physics simulates (constraint ops)
local CONSTRAINT_TYPES = { VectorForce = true, Torque = true, LinearVelocity = true, AngularVelocity = true, AlignOrientation = true, AlignPosition = true }
local ASM_FLAG_PROPS = { Anchored = true, Massless = true, RootPriority = true, Size = true }
local function kindOf(inst)
	local cls = I.classOf(inst)
	local k = handlerCache[cls.name]
	if k == nil then
		local isA = cls.isA
		if isA.BasePart then
			k = "part"
		elseif isA.GuiBase2d or isA.UIComponent or isA.UIBase then
			k = "gui"
		elseif isA.Light then
			k = "light"
		elseif isA.Humanoid or cls.name == "AnimationController" then
			-- NPC rigs: Humanoid models and AnimationController rigs (GwangalliNPCLooks pedestrians, club crowd)
			k = "humanoid"
		elseif isA.Camera then
			k = "camera"
		elseif cls.name == "Lighting" or isA.PostEffect or cls.name == "Atmosphere" or cls.name == "Sky" or cls.name == "Clouds" then
			k = "lighting"
		elseif isA.DataModelMesh then
			k = "mesh"
		elseif isA.BaseScript then
			k = "script"
		elseif isA.ProximityPrompt then
			k = "prompt"
		elseif isA.JointInstance or cls.name == "WeldConstraint" then
			k = "joint"
		elseif CONSTRAINT_TYPES[cls.name] then
			k = "constraint"
		else
			k = "other"
		end
		handlerCache[cls.name] = k
	end
	return k
end

local SIGN_PROPS = { Text = true, TextColor3 = true, BackgroundColor3 = true, BackgroundTransparency = true, Visible = true, TextTransparency = true, Enabled = true, Face = true }

local function onChanged(inst, prop, value)
	local k = kindOf(inst)
	if k == "part" then
		if prop == "CFrame" then
			local rig = T.rigByRoot[inst]
			if rig then
				T.rigMoved[rig] = true
			end
			if Asm then
				Asm.partMoved(inst)
			end
		elseif Asm and ASM_FLAG_PROPS[prop] then
			Asm.partFlags(inst)
		end
		local m = PART_PROP[prop]
		if m then
			if S.hrp == inst and prop == "CFrame" and not S.applyingInput then
				T.teleport = true
			end
			if not isCharacterPart(inst) then
				local cur = T.partDirty[inst]
				T.partDirty[inst] = if cur then bit32.bor(cur, m) else m
				if bit32.band(m, SPATIAL_MASK) ~= 0 then
					Services.spatial.partChanged(inst)
				end
				if m == F_ANCH then
					local js = T.jointsOf[inst]
					if js then
						for j in js do
							T.jointDirty[j] = true
						end
					end
				end
			end
		end
	elseif k == "joint" then
		if Asm and (prop == "Part0" or prop == "Part1" or prop == "C0" or prop == "C1" or prop == "Enabled" or prop == "Transform") then
			Asm.jointTouched(inst)
		end
		if prop == "C0" or prop == "C1" then
			-- Motor6D animation inside a registered NPC rig: render3d poses the limbs itself (no joint op per step)
			local p1 = I.rawGet(inst, "Part1")
			if p1 and T.rigPart[p1] then
				return
			end
		end
		if prop == "Part0" or prop == "Part1" or prop == "C0" or prop == "C1" or prop == "Enabled" then
			T.jointDirty[inst] = true
		end
	elseif k == "gui" then
		local known = T.guiKnown[inst]
		if known ~= nil then
			local d = T.guiDirty[inst]
			if not d then
				d = {}
				T.guiDirty[inst] = d
			end
			d[prop] = true
		end
		if Services.GUI_GEOM_PROPS[prop] then
			local x = I.data(inst)
			x._stale = true
		end
		-- SurfaceGui text in the world (signs): text / colour / visibility changes only
		if SIGN_PROPS[prop] and S.workspace then
			if I.className(inst) == "SurfaceGui" then
				if prop == "Enabled" or prop == "Face" then
					T.signDirty[inst] = true
				end
			else
				local x = inst
				for _ = 1, 4 do
					x = I.parentOf(x)
					if x == nil then
						break
					end
					if I.className(x) == "SurfaceGui" then
						T.signDirty[x] = true
						break
					end
				end
			end
		end
	elseif k == "light" then
		T.lightDirty[inst] = true
	elseif k == "humanoid" then
		if inst == S.humanoid then
			T.humanoidDirty = true
		elseif (prop == "Sit" or prop == "RigType") and T.npcKnown[inst] then
			T.npcAnim[inst] = true
		end
	elseif k == "camera" then
		if not S.applyingInput and inst == S.camera then
			T.cameraDirty = true
			if prop == "FieldOfView" then
				S.cameraFovScripted = true
			end
		end
	elseif k == "lighting" then
		T.lightingDirty = true
	elseif k == "mesh" then
		local p = I.parentOf(inst)
		if p and kindOf(p) == "part" then
			markPart(p, F_MESH)
		end
	elseif k == "script" then
		Env.onChanged(inst, prop, value)
	elseif k == "prompt" then
		S.promptsDirty = true
	elseif k == "constraint" then
		T.consDirty[inst] = true
	end
end

local function visitSubtree(root, fn)
	fn(root)
	for _, d in root:GetDescendants() do
		fn(d)
	end
end

local function onReparent(child, old, new)
	Env.onReparent(child, old, new)
	local k = kindOf(child)
	local hasKids = I.childCount(child) > 0
	-- parts / lights / prompts in the moved subtree
	if k == "part" or k == "light" or k == "prompt" or k == "joint" or k == "humanoid" or k == "constraint" or hasKids then
		local nowIn = new ~= nil and I.inDataModel(child)
		local nowWs = nowIn and inWorkspace(child)
		local function visit(x)
			local kx = kindOf(x)
			if kx == "part" then
				if not isCharacterPart(x) then
					local cur = T.partDirty[x]
					T.partDirty[x] = if cur then bit32.bor(cur, F_VIS) else F_VIS
					if nowWs then
						Services.spatial.partChanged(x)
					else
						Services.spatial.partRemoved(x)
					end
				end
				if Asm then
					Asm.partReparented(x)
				end
			elseif kx == "light" then
				T.lightDirty[x] = true
			elseif kx == "prompt" then
				Services.trackPrompt(x, nowIn)
			elseif kx == "joint" then
				T.jointDirty[x] = true
				if Asm then
					Asm.jointTouched(x)
				end
			elseif kx == "constraint" then
				T.consDirty[x] = true
			elseif kx == "humanoid" then
				T.npcDirty[x] = true
			elseif kx == "mesh" then
				local p = I.parentOf(x)
				if p and kindOf(p) == "part" then
					markPart(p, F_MESH)
				end
			end
		end
		if hasKids then
			visitSubtree(child, visit)
		else
			visit(child)
		end
		if k == "mesh" and old and kindOf(old) == "part" then
			markPart(old, F_MESH)
		end
	end
	-- GUI structure
	if isNodeClass(child) then
		local known = T.guiKnown[child] ~= nil
		local root = if new ~= nil then guiRootOf(child) else nil
		if known or root then
			T.guiTouched[child] = true
		end
		if kindOf(child) == "gui" and SIGN_PROPS then
			-- a label moved into / out of a world SurfaceGui
			local x = new
			if x and I.className(x) == "SurfaceGui" then
				T.signDirty[x] = true
			end
			if old and I.className(old) == "SurfaceGui" then
				T.signDirty[old] = true
			end
		end
	end
	if child == S.character and new == nil then
		S.characterPartSet = nil
	end
end

local function onDestroyed(inst)
	local k = kindOf(inst)
	if k == "humanoid" then
		if T.npcKnown[inst] then
			T.npcDirty[inst] = true
		end
	elseif k == "part" then
		T.partDirty[inst] = nil
		if T.partKnown[inst] or not T.runtime[inst] then
			table.insert(T.removed, I.idOf(inst))
		end
		Services.spatial.partRemoved(inst)
	elseif k == "light" then
		T.lightDirty[inst] = nil
		if T.lightKnown[inst] then
			table.insert(T.lightRemoved, I.idOf(inst))
			T.lightKnown[inst] = nil
		end
	elseif k == "prompt" then
		Services.trackPrompt(inst, false)
	elseif k == "joint" then
		T.jointDirty[inst] = nil
		if T.jointKnown[inst] then
			T.jointKnown[inst] = nil
			table.insert(T.jointRemoved, I.idOf(inst))
		end
		if Asm then
			Asm.jointRemoved(inst)
		end
	elseif k == "constraint" then
		T.consDirty[inst] = nil
		if T.consKnown[inst] then
			T.consKnown[inst] = nil
			table.insert(T.consRemoved, I.idOf(inst))
		end
	end
	if k == "part" and Asm then
		Asm.partRemoved(inst)
	end
end

local function onCreated(inst)
	T.runtime[inst] = true
	Remotes.noteCreated(inst)
end

local function onAttributeChanged(inst, name, value)
	if name == "GwControlsEnabled" and inst == S.playerModule then
		S.controlsEnabled = value ~= false
		T.humanoidDirty = true
		return
	end
	if (name == "Lit" or name == "LitColor") and I.hasTag(inst, "NightWindow") then
		T.nightDirty[inst] = true
	end
end

---------------------------------------------------------------------------------------------------------
-- Serialisers
---------------------------------------------------------------------------------------------------------
local SHAPE_BY_CLASS = { WedgePart = "Wedge", CornerWedgePart = "CornerWedge", TrussPart = "Truss" }
local asmOps, constraintRecord -- (defined with the collect code)

local function partRecord(part, mask, out)
	local id = I.idOf(part)
	local full = bit32.band(mask, F_FULL) ~= 0
	out[#out + 1] = '{"op":"part","id":'
	out[#out + 1] = tostring(id)
	local visible = inWorkspace(part) and I.inDataModel(part)
	if full then
		out[#out + 1] = ',"className":'
		out[#out + 1] = jstr(I.className(part))
		out[#out + 1] = ',"name":'
		out[#out + 1] = jstr(I.nameOf(part))
		if T.runtime[part] then
			out[#out + 1] = ',"new":true'
		end
	end
	if full or bit32.band(mask, F_CF) ~= 0 then
		out[#out + 1] = ',"cf":'
		cfArray(I.rawGet(part, "CFrame"), out)
	end
	if full or bit32.band(mask, F_SIZE) ~= 0 then
		local s = I.rawGet(part, "Size")
		out[#out + 1] = ',"size":[' .. jnum3(s.X) .. "," .. jnum3(s.Y) .. "," .. jnum3(s.Z) .. "]"
	end
	if full or bit32.band(mask, F_COLOR) ~= 0 then
		out[#out + 1] = ',"color":' .. tostring(colorNum(I.rawGet(part, "Color")))
	end
	if full or bit32.band(mask, F_TR) ~= 0 then
		out[#out + 1] = ',"transparency":' .. jnum(I.rawGet(part, "Transparency"))
	end
	if full or bit32.band(mask, F_LTM) ~= 0 then
		out[#out + 1] = ',"localTransparencyModifier":' .. jnum(I.rawGet(part, "LocalTransparencyModifier") or 0)
	end
	if full or bit32.band(mask, F_MAT) ~= 0 then
		out[#out + 1] = ',"material":' .. jstr(I.rawGet(part, "Material").Name)
	end
	if full or bit32.band(mask, F_SHAPE) ~= 0 then
		local sh = SHAPE_BY_CLASS[I.className(part)]
		if not sh then
			local ok, v = pcall(I.rawGet, part, "Shape")
			sh = if ok and v then v.Name else "Block"
		end
		out[#out + 1] = ',"shape":' .. jstr(sh)
	end
	if full or bit32.band(mask, F_REFL) ~= 0 then
		out[#out + 1] = ',"reflectance":' .. jnum(I.rawGet(part, "Reflectance"))
	end
	if full or bit32.band(mask, F_COLL) ~= 0 then
		out[#out + 1] = ',"canCollide":' .. tostring(I.rawGet(part, "CanCollide") == true)
		out[#out + 1] = ',"canQuery":' .. tostring(I.rawGet(part, "CanQuery") == true)
		out[#out + 1] = ',"collisionGroup":' .. jstr(tostring(I.rawGet(part, "CollisionGroup") or "Default"))
		out[#out + 1] = ',"canTouch":' .. tostring(I.rawGet(part, "CanTouch") == true) .. ',"massless":' .. tostring(I.rawGet(part, "Massless") == true)
		local rp = I.rawGet(part, "RootPriority")
		if rp and rp ~= 0 then
			out[#out + 1] = ',"rootPriority":' .. tostring(rp)
		end
		local cpp = I.rawGet(part, "CustomPhysicalProperties")
		if cpp then
			out[#out + 1] = ',"customPhysicalProperties":{"density":' .. jnum(cpp.Density) .. ',"friction":' .. jnum(cpp.Friction) .. ',"elasticity":' .. jnum(cpp.Elasticity) .. ',"frictionWeight":' .. jnum(cpp.FrictionWeight) .. ',"elasticityWeight":' .. jnum(cpp.ElasticityWeight) .. "}"
		end
	end
	if full or bit32.band(mask, F_ANCH) ~= 0 then
		out[#out + 1] = ',"anchored":' .. tostring(I.rawGet(part, "Anchored") == true)
	end
	if full or bit32.band(mask, F_MESH) ~= 0 then
		local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
		if mesh and I.className(mesh) == "SpecialMesh" then
			local sc, of = I.rawGet(mesh, "Scale"), I.rawGet(mesh, "Offset")
			out[#out + 1] = ',"mesh":{"meshType":' .. jstr(I.rawGet(mesh, "MeshType").Name) .. ',"scale":[' .. jnum(sc.X) .. "," .. jnum(sc.Y) .. "," .. jnum(sc.Z) .. '],"offset":[' .. jnum(of.X) .. "," .. jnum(of.Y) .. "," .. jnum(of.Z) .. "]}"
		elseif bit32.band(mask, F_MESH) ~= 0 then
			out[#out + 1] = ',"mesh":null'
		end
	end
	if full or bit32.band(mask, F_VIS) ~= 0 then
		out[#out + 1] = ',"visible":' .. tostring(visible)
	end
	if bit32.band(mask, F_VEL) ~= 0 then
		-- a script set the assembly's velocity (JS physics: body velocity)
		local v, w = part.AssemblyLinearVelocity, part.AssemblyAngularVelocity
		out[#out + 1] = ',"velocity":[' .. jnum(v.X) .. "," .. jnum(v.Y) .. "," .. jnum(v.Z) .. '],"angularVelocity":[' .. jnum(w.X) .. "," .. jnum(w.Y) .. "," .. jnum(w.Z) .. "]"
	end
	out[#out + 1] = "}"
end

-- lights
local function lightRecord(light, out)
	local id = I.idOf(light)
	local p = I.parentOf(light)
	local alive = p ~= nil and I.inDataModel(light) and inWorkspace(light)
	local cls = I.className(light)
	out[#out + 1] = '{"op":"light","id":' .. tostring(id) .. ',"className":' .. jstr(cls)
	if p and kindOf(p) == "part" then
		out[#out + 1] = ',"part":' .. tostring(I.idOf(p))
	elseif p and I.className(p) == "Attachment" then
		local wp = p.WorldPosition
		out[#out + 1] = ',"position":[' .. jnum3(wp.X) .. "," .. jnum3(wp.Y) .. "," .. jnum3(wp.Z) .. "]"
		local pp = I.parentOf(p)
		if pp and kindOf(pp) == "part" then
			out[#out + 1] = ',"part":' .. tostring(I.idOf(pp))
		end
	end
	out[#out + 1] = ',"color":' .. tostring(colorNum(I.rawGet(light, "Color")))
	out[#out + 1] = ',"brightness":' .. jnum(I.rawGet(light, "Brightness"))
	out[#out + 1] = ',"range":' .. jnum(I.rawGet(light, "Range"))
	out[#out + 1] = ',"shadows":' .. tostring(I.rawGet(light, "Shadows") == true)
	if cls ~= "PointLight" then
		out[#out + 1] = ',"angle":' .. jnum(I.rawGet(light, "Angle"))
		out[#out + 1] = ',"face":' .. jstr(I.rawGet(light, "Face").Name)
	end
	out[#out + 1] = ',"enabled":' .. tostring(alive and I.rawGet(light, "Enabled") == true)
	out[#out + 1] = "}"
	T.lightKnown[light] = true
end

-- world SurfaceGui text (sign placeholder)
local function signRecord(sg, out)
	local id = I.idOf(sg)
	local adornee = nil
	pcall(function()
		adornee = I.rawGet(sg, "Adornee")
	end)
	local part = adornee or I.parentOf(sg)
	if not part or kindOf(part) ~= "part" or not I.inDataModel(sg) then
		out[#out + 1] = '{"op":"signRemoved","id":' .. tostring(id) .. "}"
		return
	end
	local texts = {}
	local fg, bg = nil, nil
	for _, d in sg:GetDescendants() do
		local c = I.className(d)
		if (c == "TextLabel" or c == "TextButton" or c == "TextBox") and I.rawGet(d, "Visible") then
			local t = I.rawGet(d, "Text")
			if I.rawGet(d, "RichText") then
				t = I.stripRichText(t)
			end
			if t ~= "" then
				table.insert(texts, t)
				fg = fg or I.rawGet(d, "TextColor3")
				if not bg and I.rawGet(d, "BackgroundTransparency") < 1 then
					bg = I.rawGet(d, "BackgroundColor3")
				end
			end
		elseif c == "Frame" and not bg and I.rawGet(d, "Visible") and I.rawGet(d, "BackgroundTransparency") < 1 then
			bg = I.rawGet(d, "BackgroundColor3")
		end
	end
	out[#out + 1] = '{"op":"sign","id":' .. tostring(id) .. ',"part":' .. tostring(I.idOf(part)) .. ',"face":' .. jstr(I.rawGet(sg, "Face").Name)
	out[#out + 1] = ',"text":' .. jstr(table.concat(texts, "\n"))
	if fg then
		out[#out + 1] = ',"fg":' .. tostring(colorNum(fg))
	end
	if bg then
		out[#out + 1] = ',"bg":' .. tostring(colorNum(bg))
	end
	out[#out + 1] = ',"enabled":' .. tostring(I.rawGet(sg, "Enabled") == true)
	out[#out + 1] = "}"
end

-- GUI nodes ---------------------------------------------------------------------------------------------
local GUI_SKIP_PROPS = { Archivable = true, Source = true, RobloxLocked = true, Tags = true, Attributes = true }

local function propsJSON(inst, out, only)
	out[#out + 1] = "{"
	local first = true
	local pv = I.propsOf(inst)
	if only then
		for prop in only do
			if not GUI_SKIP_PROPS[prop] and prop ~= "Parent" then
				local ok, v = pcall(function()
					if prop == "Name" then
						return I.nameOf(inst)
					end
					return I.rawGet(inst, prop)
				end)
				if ok then
					if not first then
						out[#out + 1] = ","
					end
					first = false
					out[#out + 1] = jstr(prop)
					out[#out + 1] = ":"
					encodeValue(v, out, 0)
				end
			end
		end
	elseif pv then
		for prop, v in pv do
			if not GUI_SKIP_PROPS[prop] and type(prop) == "string" then
				if not first then
					out[#out + 1] = ","
				end
				first = false
				out[#out + 1] = jstr(prop)
				out[#out + 1] = ":"
				encodeValue(v, out, 0)
			end
		end
	end
	out[#out + 1] = "}"
end

-- (gwangalli npc_mind patch) SurfaceGui roots (PlayerGui + Adornee): the centre of the adorned face
-- and its world normal, so the JS layer can draw it on that face and hide it when it faces away
local FACE_AXIS = { Front = { 0, 0, -1 }, Back = { 0, 0, 1 }, Top = { 0, 1, 0 }, Bottom = { 0, -1, 0 }, Right = { 1, 0, 0 }, Left = { -1, 0, 0 } }
local function billboardPos(bb)
	local ad = nil
	pcall(function()
		ad = I.rawGet(bb, "Adornee")
	end)
	local target = ad or I.parentOf(bb)
	if target == nil then
		return nil
	end
	local k = kindOf(target)
	local p = nil
	if k == "part" and I.className(bb) == "SurfaceGui" then
		local okC, cf = pcall(function()
			return target.CFrame
		end)
		if not okC or not cf then
			cf = I.rawGet(target, "CFrame")
		end
		local size = I.rawGet(target, "Size")
		local face = nil
		pcall(function()
			face = I.rawGet(bb, "Face")
		end)
		local ax = FACE_AXIS[face and face.Name or "Front"] or FACE_AXIS.Front
		if not cf then
			return nil
		end
		local n = cf:VectorToWorldSpace(DT.v3(ax[1], ax[2], ax[3]))
		local half = if size then math.abs(ax[1]) * size.X * 0.5 + math.abs(ax[2]) * size.Y * 0.5 + math.abs(ax[3]) * size.Z * 0.5 else 0.5
		return cf.Position + n * (half + 0.02), n
	end
	if k == "part" then
		-- the live CFrame (welded / simulated parts move without their raw value changing)
		local okC, cf = pcall(function()
			return target.CFrame
		end)
		if not okC or not cf then
			cf = I.rawGet(target, "CFrame")
		end
		if not cf then
			return nil
		end
		p = cf.Position
	elseif I.className(target) == "Attachment" then
		p = target.WorldPosition
	elseif I.isA(target, "Model") then
		local ok, pv = pcall(I.getPivot, target)
		p = if ok then pv.Position else nil
	end
	return p
end

local function nodeJSON(inst, parentId, out)
	T.guiKnown[inst] = parentId
	T.guiDirty[inst] = nil
	T.guiTouched[inst] = nil
	out[#out + 1] = '{"id":' .. tostring(I.idOf(inst)) .. ',"class":' .. jstr(I.className(inst)) .. ',"name":' .. jstr(I.nameOf(inst)) .. ',"props":'
	propsJSON(inst, out, nil)
	if I.className(inst) == "BillboardGui" and parentId == 0 then
		local p = billboardPos(inst)
		if p then
			out[#out + 1] = ',"pos":[' .. jnum3(p.X) .. "," .. jnum3(p.Y) .. "," .. jnum3(p.Z) .. "]"
			T.billboards[inst] = jnum3(p.X) .. "," .. jnum3(p.Y) .. "," .. jnum3(p.Z)
		end
	end
	local kids = I.children(inst)
	local wrote = false
	local myId = I.idOf(inst)
	for _, c in kids do
		if isNodeClass(c) then
			if not wrote then
				out[#out + 1] = ',"children":['
				wrote = true
			else
				out[#out + 1] = ","
			end
			nodeJSON(c, myId, out)
		end
	end
	if wrote then
		out[#out + 1] = "]"
	end
	out[#out + 1] = "}"
end

local function forgetGui(inst)
	T.guiKnown[inst] = nil
	T.guiDirty[inst] = nil
	T.guiRoots[inst] = nil
	T.billboards[inst] = nil
	for _, d in inst:GetDescendants() do
		T.guiKnown[d] = nil
		T.guiDirty[d] = nil
	end
end

local function nodeParentId(inst)
	local p = I.parentOf(inst)
	while p ~= nil and not isNodeClass(p) do
		p = I.parentOf(p)
	end
	return p
end

local function indexIn(parent, inst)
	local i = 0
	for _, c in I.children(parent) do
		if c == inst then
			return i
		end
		if isNodeClass(c) then
			i += 1
		end
	end
	return i
end

local function flushGui(out)
	-- structure: resolve the final state of every touched node
	local touched = T.guiTouched
	T.guiTouched = {}
	local list = {}
	for inst in touched do
		table.insert(list, inst)
	end
	-- parents before children
	local depth = {}
	for _, inst in list do
		local d, x = 0, I.parentOf(inst)
		while x ~= nil and d < 200 do
			d += 1
			x = I.parentOf(x)
		end
		depth[inst] = d
	end
	table.sort(list, function(a, b)
		return depth[a] < depth[b]
	end)
	for _, inst in list do
		local known = T.guiKnown[inst]
		local alive = not I.isDestroyed(inst) and I.inDataModel(inst)
		local root = if alive then guiRootOf(inst) else nil
		if root == inst then
			-- a root
			if known == nil then
				T.guiRoots[inst] = true
				out[#out + 1] = '{"op":"gui","tree":'
				nodeJSON(inst, 0, out)
				out[#out + 1] = "}"
				out[#out + 1] = ","
			end
		elseif root ~= nil then
			local p = nodeParentId(inst)
			local pid = if p then I.idOf(p) else 0
			if known == nil then
				-- added (skip when the parent's node was written this step: it contained this subtree)
				if p and T.guiKnown[p] ~= nil then
					out[#out + 1] = '{"op":"guiAdd","parent":' .. tostring(pid) .. ',"index":' .. tostring(indexIn(p, inst)) .. ',"node":'
					nodeJSON(inst, pid, out)
					out[#out + 1] = "}"
					out[#out + 1] = ","
				end
			elseif known ~= pid then
				T.guiKnown[inst] = pid
				out[#out + 1] = '{"op":"guiParent","id":' .. tostring(I.idOf(inst)) .. ',"parent":' .. tostring(pid) .. ',"index":' .. tostring(indexIn(p, inst)) .. "}"
				out[#out + 1] = ","
			end
		elseif known ~= nil then
			out[#out + 1] = '{"op":"guiDel","id":' .. tostring(I.idOf(inst)) .. "}"
			out[#out + 1] = ","
			forgetGui(inst)
		end
	end
	-- property patches
	local first = true
	for inst, props in T.guiDirty do
		if T.guiKnown[inst] ~= nil and not I.isDestroyed(inst) then
			if first then
				out[#out + 1] = '{"op":"guiSet","list":['
				first = false
			else
				out[#out + 1] = ","
			end
			out[#out + 1] = "[" .. tostring(I.idOf(inst)) .. ","
			propsJSON(inst, out, props)
			out[#out + 1] = "]"
		end
	end
	T.guiDirty = {}
	if not first then
		out[#out + 1] = "]}"
		out[#out + 1] = ","
	end
	-- billboard world positions. (gwangalli npc_mind patch) Roots that had no position when they were
	-- first written (scripts create a BillboardGui / SurfaceGui, parent it, then set the Adornee) are
	-- tracked too, like Roblox draws them; SurfaceGui roots also send their face normal ("n").
	for root in T.guiRoots do
		if T.billboards[root] == nil and not I.isDestroyed(root) then
			local cn = I.className(root)
			if cn == "BillboardGui" or cn == "SurfaceGui" then
				T.billboards[root] = ""
			end
		end
	end
	for bb, last in T.billboards do
		if not I.isDestroyed(bb) and T.guiKnown[bb] ~= nil then
			local okP, p, nrm = pcall(billboardPos, bb)
			if okP and p then
				local key = jnum3(p.X) .. "," .. jnum3(p.Y) .. "," .. jnum3(p.Z)
				local nk = if nrm then jnum3(nrm.X) .. "," .. jnum3(nrm.Y) .. "," .. jnum3(nrm.Z) else nil
				local full = if nk then key .. ";" .. nk else key
				if full ~= last then
					T.billboards[bb] = full
					out[#out + 1] = '{"op":"guiPos","id":' .. tostring(I.idOf(bb)) .. ',"pos":[' .. key .. "]" .. (if nk then ',"n":[' .. nk .. "]" else "") .. "}"
					out[#out + 1] = ","
				end
			end
		end
	end
end

-- lighting ------------------------------------------------------------------------------------------
local LIGHTING_PROPS = { "ClockTime", "GeographicLatitude", "Brightness", "ExposureCompensation", "Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows", "ShadowSoftness", "FogColor", "FogStart", "FogEnd" }
local EFFECTS = {
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	Sky = { "CelestialBodiesShown", "StarCount", "SunAngularSize", "MoonAngularSize", "SkyboxBk" },
	Clouds = { "Cover", "Density", "Color", "Enabled" },
	BloomEffect = { "Intensity", "Size", "Threshold", "Enabled" },
	ColorCorrectionEffect = { "Brightness", "Contrast", "Saturation", "TintColor", "Enabled" },
	SunRaysEffect = { "Intensity", "Spread", "Enabled" },
	DepthOfFieldEffect = { "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity", "Enabled" },
}
local EFFECT_KEY = { Atmosphere = "Atmosphere", Sky = "Sky", Clouds = "Clouds", BloomEffect = "Bloom", ColorCorrectionEffect = "ColorCorrection", SunRaysEffect = "SunRays", DepthOfFieldEffect = "DepthOfField" }

local function lightingRecord(out)
	local L = S.lighting
	if not L then
		return
	end
	local props = {}
	for _, p in LIGHTING_PROPS do
		local ok, v = pcall(I.rawGet, L, p)
		if ok then
			props[p] = v
		end
	end
	props.TimeOfDay = L.TimeOfDay
	local seen = {}
	for _, c in I.children(L) do
		local cn = I.className(c)
		local list = EFFECTS[cn]
		if list and not seen[cn] then
			seen[cn] = true
			local e = {}
			for _, p in list do
				local ok, v = pcall(I.rawGet, c, p)
				if ok then
					e[p] = v
				end
			end
			props[EFFECT_KEY[cn]] = e
		end
	end
	-- camera-parented effects count too (Roblox allows effects under the Camera)
	if S.camera then
		for _, c in I.children(S.camera) do
			local cn = I.className(c)
			local list = EFFECTS[cn]
			if list and not seen[cn] then
				seen[cn] = true
				local e = {}
				for _, p in list do
					local ok, v = pcall(I.rawGet, c, p)
					if ok then
						e[p] = v
					end
				end
				props[EFFECT_KEY[cn]] = e
			end
		end
	end
	if S.terrain then
		local t = {}
		for _, p in { "WaterColor", "WaterTransparency", "WaterReflectance", "WaterWaveSize", "WaterWaveSpeed" } do
			local ok, v = pcall(I.rawGet, S.terrain, p)
			if ok then
				t[p] = v
			end
		end
		props.Terrain = t
	end
	out[#out + 1] = '{"op":"lighting","props":'
	encodeValue(props, out, 0)
	out[#out + 1] = "}"
end

local function cameraRecord(out)
	local cam = S.camera
	if not cam then
		return
	end
	local subj = I.rawGet(cam, "CameraSubject")
	local subjId = "null"
	local subjKind = "humanoid"
	if subj ~= nil and subj ~= S.humanoid then
		if kindOf(subj) == "part" then
			subjId = tostring(I.idOf(subj))
			subjKind = if I.isA(subj, "VehicleSeat") then "vehicleSeat" else "part"
		elseif I.isA(subj, "Humanoid") then
			local r = subj.RootPart
			subjId = if r then tostring(I.idOf(r)) else "null"
		elseif I.isA(subj, "Model") then
			local pp = I.rawGet(subj, "PrimaryPart")
			subjId = if pp then tostring(I.idOf(pp)) else "null"
			subjKind = "part"
		end
	end
	out[#out + 1] = '{"op":"camera","cameraType":' .. jstr(I.rawGet(cam, "CameraType").Name) .. ',"cf":'
	cfArray(I.rawGet(cam, "CFrame"), out)
	out[#out + 1] = ',"fov":' .. jnum(I.rawGet(cam, "FieldOfView")) .. ',"subject":' .. subjId .. ',"subjectKind":"' .. subjKind .. '"'
	-- a Scriptable camera that jumped far (cut) must not glide there
	local cf = I.rawGet(cam, "CFrame")
	local last = S.lastCamSent
	if last and (cf.Position - last.Position).Magnitude > 60 then
		out[#out + 1] = ',"cut":true'
	end
	S.lastCamSent = cf
	if S.player then
		out[#out + 1] = ',"minZoom":' .. jnum(I.rawGet(S.player, "CameraMinZoomDistance")) .. ',"maxZoom":' .. jnum(I.rawGet(S.player, "CameraMaxZoomDistance"))
	end
	out[#out + 1] = "}"
end

local function humanoidRecord(out)
	local hum = S.humanoid
	if not hum or I.isDestroyed(hum) then
		return
	end
	local seat = I.rawGet(hum, "SeatPart")
	local rec = {
		op = "humanoid",
		id = I.idOf(hum),
		WalkSpeed = I.rawGet(hum, "WalkSpeed"),
		JumpPower = I.rawGet(hum, "JumpPower"),
		JumpHeight = I.rawGet(hum, "JumpHeight"),
		UseJumpPower = I.rawGet(hum, "UseJumpPower"),
		AutoRotate = I.rawGet(hum, "AutoRotate"),
		HipHeight = I.rawGet(hum, "HipHeight"),
		PlatformStand = I.rawGet(hum, "PlatformStand"),
		MaxSlopeAngle = I.rawGet(hum, "MaxSlopeAngle"),
		Health = I.rawGet(hum, "Health"),
		MaxHealth = I.rawGet(hum, "MaxHealth"),
		Sit = I.rawGet(hum, "Sit"),
		SeatPart = if seat then I.idOf(seat) else false,
		ControlsEnabled = S.controlsEnabled ~= false,
	}
	-- carried by another assembly (taxi seat weld, VehicleSeat SeatWeld): the JS avatar rides on that root
	local at = Asm and Asm.attach
	if at and at.root and not I.isDestroyed(at.root) and at.rel then
		rec.attach = { part = I.idOf(at.root), cf = { at.rel:GetComponents() }, seat = seat ~= nil, mass = Asm.characterMass() }
	else
		rec.attach = false
	end
	local x = I.data(hum)
	if x._disabled then
		local se = {}
		for st, off in x._disabled do
			if off then
				se[st.Name] = false
			end
		end
		rec.stateEnabled = se
	end
	encodeValue(rec, out, 0)
end

local function characterRecord(out)
	local model = S.character
	if not model then
		return
	end
	local ids = {}
	for _, p in S.characterParts or {} do
		table.insert(ids, I.idOf(p))
	end
	out[#out + 1] = '{"op":"character","model":' .. tostring(I.idOf(model)) .. ',"rootId":' .. tostring(I.idOf(S.hrp)) .. ',"humanoid":' .. tostring(I.idOf(S.humanoid)) .. ',"ids":['
	out[#out + 1] = table.concat(ids, ",")
	out[#out + 1] = '],"cf":'
	cfArray(I.rawGet(S.hrp, "CFrame"), out)
	out[#out + 1] = ',"colors":{"head":16109360,"torso":880044,"arms":16109360,"legs":10796359},"name":' .. jstr(I.nameOf(model)) .. "}"
end

-- prompts: every enabled prompt near the character (prompts.js applies the Roblox visibility rules)
-- ProximityPrompt list for prompts.js. O(near prompts) per call: every prompt's world position is cached and only
-- refreshed for prompts near the player (they may sit on moving NPCs / cars); a full refresh runs when the prompt set
-- changes (S.promptsDirty) or at most once per second.
local promptCache = setmetatable({}, { __mode = "k" }) -- prompt -> { pos, maxD, ignore }
-- ids of the parts that belong to the prompt's object: its adornee part, plus every part of the nearest Model above it
-- when that model is small (an NPC, a car, a vending machine); "" when nothing
local function promptIgnore(prompt)
	local x = I.parentOf(prompt)
	if x and I.classOf(x).isA.Attachment then
		x = I.parentOf(x)
	end
	local ids = {}
	if x and kindOf(x) == "part" then
		ids[#ids + 1] = tostring(I.idOf(x))
	end
	local m = x
	local n = 0
	while m ~= nil and not I.classOf(m).isA.Model and n < 4 do
		m = I.parentOf(m)
		n += 1
	end
	if m and I.classOf(m).isA.Model and m ~= S.workspace and m ~= I.dataModel then
		local parts = I.modelParts(m)
		if #parts <= 64 then
			for _, q in parts do
				if q ~= x then
					ids[#ids + 1] = tostring(I.idOf(q))
				end
			end
		end
	end
	return table.concat(ids, ",")
end
local promptFullAt = -1
local function promptList(full)
	local center = nil
	if S.hrp and not I.isDestroyed(S.hrp) then
		center = I.rawGet(S.hrp, "CFrame").Position
	end
	local now = Sched.now()
	if full or now - promptFullAt >= 1 then
		full = true
		promptFullAt = now
	end
	local items = {}
	for prompt in S.prompts do
		local c = promptCache[prompt]
		local near = full or c == nil or center == nil or (c.pos ~= nil and (c.pos - center).Magnitude <= c.maxD + 100)
		if near then
			if not I.isDestroyed(prompt) and I.inDataModel(prompt) and inWorkspace(prompt) and I.rawGet(prompt, "Enabled") then
				local pos = Services.promptWorldPos(prompt)
				local maxD = I.rawGet(prompt, "MaxActivationDistance")
				if not c then
					c = {}
					promptCache[prompt] = c
				end
				c.pos, c.maxD = pos, maxD
				if pos and (not center or (pos - center).Magnitude <= maxD + 60) then
					table.insert(items, { prompt, pos, maxD })
				end
			elseif c then
				c.pos = nil
				c.maxD = 0
			end
		end
	end
	table.sort(items, function(a, b)
		return I.idOf(a[1]) < I.idOf(b[1])
	end)
	local out = {}
	for _, it in items do
		local p, pos, maxD = it[1], it[2], it[3]
		local off = I.rawGet(p, "UIOffset")
		-- RequiresLineOfSight: the parts of the prompt's own object never block it (its part / small model)
		local c = promptCache[p]
		if c and c.ignore == nil then
			c.ignore = promptIgnore(p)
		end
		out[#out + 1] = '{"id":' .. tostring(I.idOf(p)) .. ',"pos":[' .. jnum3(pos.X) .. "," .. jnum3(pos.Y) .. "," .. jnum3(pos.Z) .. "]"
			.. ',"actionText":' .. jstr(I.rawGet(p, "ActionText")) .. ',"objectText":' .. jstr(I.rawGet(p, "ObjectText"))
			.. ',"holdDuration":' .. jnum(I.rawGet(p, "HoldDuration")) .. ',"maxDistance":' .. jnum(maxD)
			.. ',"keyCode":' .. jstr(I.rawGet(p, "KeyboardKeyCode").Name) .. ',"enabled":true'
			.. ',"exclusivity":' .. jstr(I.rawGet(p, "Exclusivity").Name) .. ',"style":' .. jstr(I.rawGet(p, "Style").Name)
			.. ',"uiOffset":[' .. jnum(off.X) .. "," .. jnum(off.Y) .. '],"clickable":' .. tostring(I.rawGet(p, "ClickablePrompt") == true)
			.. ',"requiresLineOfSight":' .. tostring(I.rawGet(p, "RequiresLineOfSight") == true) .. ',"ignore":[' .. (if c and c.ignore then c.ignore else "") .. "]}"
	end
	return "[" .. table.concat(out, ",") .. "]"
end

---------------------------------------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------------------------------------
local function progress(frac, text)
	if host and host.progress then
		pcall(host.progress, frac, text)
	end
end

local function hostCompile(src, name)
	if host and host.compile then
		local f = host.compile(src, name)
		if type(f) == "function" then
			return f
		end
		return nil, tostring(f)
	end
	return nil, "no compiler available (host.compile missing)"
end

function Bridge.boot(placeBuffer, opts)
	local t0 = clock()
	opts = opts or {}
	host = opts.host or (GW and GW.host) or rawget(_G, "GW_HOST")
	progress(0.05, "엔진 준비")
	-- core modules
	DT.isInstance = I.isInstance
	local classdb = opts.classdbJSON or rawget(_G, "CLASSDB_JSON")
	if classdb == nil and not ClassDB.loaded() then
		return "bridge.boot: classdb JSON missing (opts.classdbJSON / CLASSDB_JSON)"
	end
	Sched.reset()
	-- per-step time budget for task.wait/delay resumptions (sched.luau): phones 10 ms, PC 25 ms; opts.resumeBudgetMs
	-- overrides (0 = unlimited, the Roblox behaviour). The rest stays due and resumes first at the next step.
	local rb = tonumber(opts.resumeBudgetMs)
	if rb == nil then
		rb = if opts.quality == "low" or opts.quality == nil then 10 elseif opts.quality == "mid" then 14 else 25
	end
	Sched.resumeBudget = if rb > 0 then rb / 1000 else nil
	resetTracking()
	local hooks = Services.hooks()
	hooks.onChanged = onChanged
	hooks.onReparent = onReparent
	hooks.onDestroyed = onDestroyed
	hooks.onCreated = onCreated
	hooks.onAttributeChanged = onAttributeChanged
	hooks.onCallbackSet = function(inst, name, fn)
		Remotes.onCallbackSet(inst, name, fn)
	end
	local prevPlay, prevStop = hooks.animationPlay, hooks.animationStop
	hooks.animationPlay = function(track, fade, weight, speed)
		if prevPlay then
			prevPlay(track, fade, weight, speed)
		end
		pcall(onAnimPlay, track)
	end
	hooks.animationStop = function(track, fade)
		if prevStop then
			prevStop(track, fade)
		end
		pcall(onAnimStop, track, fade)
	end
	hooks.warn = function(msg, ctx, tb)
		Env.output("warn", msg, ctx and ctx.name or nil, nil, Env.cleanTraceback(tb))
	end
	if Audio then
		Audio.wrapHooks(hooks)
	end
	I.init({
		types = DT,
		Enum = Enum,
		typeof = DT.typeof,
		classdb = if ClassDB.loaded() and not opts.reloadClassdb then nil else classdb,
		sched = Sched.hook,
		hooks = hooks,
	})
	Signal.reportError = function(msg, tb, ctx)
		Env.reportError(msg, tb, ctx)
	end
	Sched.onError = function(msg, tb, ctx)
		Env.reportError(msg, tb, ctx)
	end
	Env.init({ Instance = I, types = DT, Enum = Enum })
	Env.compile = opts.compile or hostCompile
	Remotes.init({ Instance = I, Env = Env, Signal = Signal })
	Services.init({ Instance = I, types = DT, Enum = Enum, Env = Env, Remotes = Remotes, host = host })
	if Asm then
		Asm.init({ I = I, CFrame = DT.CFrame, Vector3 = DT.Vector3, S = S, Services = Services, Enum = Enum })
		Asm.reset()
		I.asm = Asm
		Asm.markDirty = function(part, what)
			markPart(part, if what == "full" then F_FULL else F_CF)
		end
		Asm.moveCharacter = function(cf)
			local hrp, model = S.hrp, S.character
			if not hrp or not model or I.isDestroyed(hrp) then
				return
			end
			local old = I.rawGet(hrp, "CFrame")
			local was = S.applyingInput
			S.applyingInput = true
			if old.X ~= old.X or old.Y ~= old.Y or old.Z ~= old.Z or old.XVector.X ~= old.XVector.X then
				-- a NaN rig (should not happen): put every part back at the carrier pose instead of multiplying NaN
				if not S.nanRigWarned then
					S.nanRigWarned = true
					Env.output("warn", "[engine] NaN character rig re-placed on its carrier", "engine", nil, debug.traceback())
				end
				for _, p in S.characterParts or I.modelParts(model) do
					if not I.isDestroyed(p) and p ~= hrp then
						I.rawSet(p, "CFrame", cf)
					end
				end
				I.setPartCFrame(hrp, cf)
				S.applyingInput = was
				return
			end
			Services.moveModel(model, S.characterParts or I.modelParts(model), old, cf)
			S.applyingInput = was
			S.rootCF = cf
		end
	end
	if Audio then
		Audio.init({ I = I, jsonEncode = jsonEncode, S = S })
	end
	local tInit = clock()
	progress(0.15, "장소 불러오는 중")
	-- place
	local idx = opts.index
	if idx == nil and GW and GW.readBlob and host and host.blobSize then
		local okS, n = pcall(host.blobSize, "place.idx")
		if okS and type(n) == "number" and n > 0 then
			idx = GW.readBlob("place.idx")
		end
	end
	local game
	local loadRes = nil
	if placeBuffer ~= nil then
		loadRes = Loader.fromBinary(placeBuffer, { Instance = I, types = DT, Enum = Enum }, idx)
		game = loadRes.root
	elseif opts.placeDoc then
		loadRes = Loader.fromDoc(opts.placeDoc, { Instance = I, types = DT, Enum = Enum })
		game = loadRes.root
	else
		game = I.create("DataModel", { name = "Game" })
		loadRes = { count = 1, ms = { total = 0 }, lazy = 0 }
	end
	I.setDataModel(game)
	local tLoad = clock()
	progress(0.55, "서비스 시작")
	Services.boot(game, opts)
	Env.setGame(game, S.workspace)
	if host and host.wall then
		local okW, w = pcall(host.wall)
		if okW and type(w) == "number" then
			Env.setWallClock(w)
			S.epoch = w
		end
	end
	-- spatial index (optional section of place.idx)
	local spatialOk = false
	if idx and loadRes and loadRes.count then
		local nInst = buffer.readu32(idx, 8)
		local instBase = buffer.readu32(idx, 20)
		local off = instBase + nInst * 20
		spatialOk = Services.spatial.setIndex(idx, off, loadRes.count)
	end
	-- studio
	if Studio then
		local okS, st = pcall(Studio.new, {
			root = game,
			typeof = I.typeof,
			Vector3 = DT.Vector3,
			Vector2 = DT.Vector2,
			Color3 = DT.Color3,
			CFrame = DT.CFrame,
			UDim = DT.UDim,
			UDim2 = DT.UDim2,
			BrickColor = DT.BrickColor,
			Enum = Enum,
			idOf = I.idOf,
			byId = I.byId,
			properties = I.properties,
			getChildren = I.children,
			childCount = I.childCount,
			nameOf = I.nameOf,
			className = I.className,
			parentOf = I.parentOf,
			getSource = Env.sourceOf,
			getTags = I.getTags,
			now = os.clock,
		})
		studio = if okS then st else nil
	end
	Env.echo = function(kind, text, source, line, tb)
		if studio then
			pcall(studio.log, studio, kind, text, source, line, tb)
		end
	end
	-- server scripts
	progress(0.7, "서버 스크립트 실행")
	local tS = clock()
	local nServer = Env.startServer()
	Sched.flush()
	local tServer = clock()
	booted = true
	frameCount = 0
	bootInfo = {
		instances = loadRes.count,
		lazy = loadRes.lazy,
		indexed = loadRes.indexed == true,
		spatialIndex = spatialOk,
		loadMs = floor((tLoad - tInit) * 1000),
		initMs = floor((tInit - t0) * 1000),
		serverScripts = nServer,
		serverMs = floor((tServer - tS) * 1000),
		bootMs = floor((clock() - t0) * 1000),
		gcKB = gcinfo(),
	}
	progress(0.9, "플레이어 입장")
	return nil
end

-- harness helper: boot from an embedded blob name + JSON opts; returns JSON boot info or {"error":...}
function Bridge.bootJSON(placeName, optsJSON)
	local opts = {}
	if type(optsJSON) == "string" and optsJSON ~= "" then
		local ok, o = pcall(ClassDB.jsonDecode, optsJSON)
		if ok and type(o) == "table" then
			opts = o
		end
	end
	local buf = nil
	if placeName and GW and GW.readBlob then
		buf = GW.readBlob(placeName)
	end
	opts.host = opts.host or (GW and GW.host)
	local ok, err = pcall(Bridge.boot, buf, opts)
	if not ok then
		return jsonEncode({ error = tostring(err) })
	end
	if type(err) == "string" then
		return jsonEncode({ error = err })
	end
	return jsonEncode(bootInfo)
end

function Bridge.info()
	return bootInfo
end

---------------------------------------------------------------------------------------------------------
-- Step
---------------------------------------------------------------------------------------------------------
local function applyPhysicsParts(list)
	-- unanchored parts simulated by the JS physics (Character.getState().parts): positions come back here
	for _, e in list do
		if type(e) == "table" then
			local inst = I.byId(tonumber(e.id) or -1)
			if inst and not I.isDestroyed(inst) and kindOf(inst) == "part" then
				local cf = Services.cframe(e.cf)
				local px = cf and cf.X
				-- never take NaN / inf positions from the JS physics (a NaN root made Humanoid:MoveTo walk on NaN and
				-- the spatial cell loops spin forever)
				if cf and px == px and cf.Y == cf.Y and cf.Z == cf.Z and math.abs(px) < 1e7 and math.abs(cf.Y) < 1e7 and math.abs(cf.Z) < 1e7 then
					I.rawSet(inst, "CFrame", cf)
					Services.spatial.partChanged(inst)
					if Asm then
						Asm.partMoved(inst)
					end
					if I.hasListeners(inst, "\1CFrame") or I.hasListeners(inst, "Changed") then
						I.notifyChanged(inst, "CFrame")
					end
				end
				local v = Services.vec3(e.velocity)
				local av = Services.vec3(e.angVel)
				if v then
					I.rawSet(inst, "AssemblyLinearVelocity", v)
				end
				if av then
					I.rawSet(inst, "AssemblyAngularVelocity", av)
				end
				if Asm then
					local a = Asm.asmOf[inst]
					if a then
						if v then
							a.vel = v
						end
						if av then
							a.angVel = av
						end
						local m = tonumber(e.mass)
						local com = Services.vec3(e.com)
						if m and m > 0 and com then
							a.jsMass, a.jsCom = m, com
						end
					end
				end
			end
		end
	end
end

local function applyCharacterEvents(list)
	for _, e in list do
		if type(e) == "table" and e.type == "FallenPartsDestroyed" and type(e.ids) == "table" then
			-- Workspace.FallenPartsDestroyHeight (rblx_physics reports assemblies that fell below it)
			for _, id in e.ids do
				local inst = I.byId(tonumber(id) or -1)
				if inst and not I.isDestroyed(inst) and kindOf(inst) == "part" then
					pcall(inst.Destroy, inst)
				end
			end
		elseif type(e) == "table" and e.type == "Seated" and S.humanoid then
			if e.active then
				local seat = I.byId(tonumber(e.seatPartId) or -1)
				if seat and (I.isA(seat, "Seat") or I.isA(seat, "VehicleSeat")) and I.rawGet(S.humanoid, "SeatPart") == nil then
					Sched.runIn(Env.serverCtx, I.seatSit, seat, S.humanoid)
				end
			elseif I.rawGet(S.humanoid, "SeatPart") ~= nil then
				I.humanoidUnseat(S.humanoid)
			end
		end
	end
end

local function drainOutput(out)
	local lines = Env.drain()
	if lines then
		out[#out + 1] = '{"op":"output","lines":['
		for i, l in lines do
			if i > 1 then
				out[#out + 1] = ","
			end
			out[#out + 1] = '{"kind":' .. jstr(l.kind) .. ',"text":' .. jstr(tostring(l.text)) .. ',"source":' .. (if l.source then jstr(l.source) else "null") .. ',"line":' .. (if l.line then tostring(l.line) else "null") .. ',"t":' .. jnum(l.t)
			if l.tb and l.tb ~= "" then
				out[#out + 1] = ',"tb":' .. jstr(l.tb)
			end
			out[#out + 1] = "}"
		end
		out[#out + 1] = "]}"
		out[#out + 1] = ","
	end
	if studio then
		local ok, ev = pcall(studio.drain, studio)
		if ok and ev and ev.dirty then
			out[#out + 1] = jsonEncode({ op = "studio", out = {}, dirty = ev.dirty })
			out[#out + 1] = ","
		end
	end
end

-- joints ---------------------------------------------------------------------------------------------
-- a joint matters to the JS physics only when one of its parts is simulated there: unanchored and known to JS
-- (runtime part or a place part that already got a part op). Everything else stays out of the physics world.
local function jointParts(j)
	local a, b = I.rawGet(j, "Part0"), I.rawGet(j, "Part1")
	if a ~= nil and (I.isDestroyed(a) or kindOf(a) ~= "part") then
		a = nil
	end
	if b ~= nil and (I.isDestroyed(b) or kindOf(b) ~= "part") then
		b = nil
	end
	return a, b
end
local function simulatedPart(p)
	return p ~= nil and not I.rawGet(p, "Anchored") and (T.partKnown[p] == true or T.runtime[p] == true) and not isCharacterPart(p)
end
local function noteJointOf(p, j)
	if p == nil then
		return
	end
	local js = T.jointsOf[p]
	if not js then
		js = setmetatable({}, { __mode = "k" })
		T.jointsOf[p] = js
	end
	js[j] = true
end
local function jointRecord(j, out)
	local a, b = jointParts(j)
	noteJointOf(a, j)
	noteJointOf(b, j)
	local known = T.jointKnown[j]
	local alive = a ~= nil and b ~= nil and a ~= b and not I.isDestroyed(j) and I.inDataModel(j) and inWorkspace(a) and inWorkspace(b)
	if not alive or (not known and not (simulatedPart(a) or simulatedPart(b))) then
		if known then
			T.jointKnown[j] = nil
			out[#out + 1] = '{"op":"jointRemoved","id":' .. tostring(I.idOf(j)) .. "},"
		end
		return
	end
	T.jointKnown[j] = true
	local cls = I.className(j)
	out[#out + 1] = '{"op":"joint","id":' .. tostring(I.idOf(j)) .. ',"type":' .. jstr(cls) .. ',"part0":' .. tostring(I.idOf(a)) .. ',"part1":' .. tostring(I.idOf(b))
	if cls ~= "WeldConstraint" then
		out[#out + 1] = ',"c0":'
		cfArray(I.rawGet(j, "C0"), out)
		out[#out + 1] = ',"c1":'
		cfArray(I.rawGet(j, "C1"), out)
	end
	out[#out + 1] = ',"enabled":' .. tostring(I.rawGet(j, "Enabled") ~= false) .. "},"
end

-- NPC rigs ----------------------------------------------------------------------------------------------------------------------------
-- {op="npc", id=humanoid, model, root, rig="R15"|"R6", parts={Name=id}, pose, speed, sit} and {op="npcPose", id, pose, speed, sit}
-- render3d animates the limbs procedurally: walk / idle from the root's motion (like Animate's locomotion blend), dance /
-- wave / sit / cheer ... from the playing AnimationTracks (names / common asset ids), {op="npcRemoved", id}.
local RIG_NAMES = {
	Head = true, Torso = true, UpperTorso = true, LowerTorso = true, HumanoidRootPart = true,
	["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}
-- common Roblox animation asset ids (default Animate / emotes) -> pose
local ANIM_IDS = {
	["507770239"] = "wave", ["507770453"] = "point", ["507771019"] = "dance", ["507776043"] = "dance", ["507777268"] = "dance",
	["507770677"] = "cheer", ["507770818"] = "laugh", ["2506281703"] = "sit", ["128777973"] = "wave", ["182435998"] = "dance",
	["182491037"] = "dance", ["182491065"] = "dance", ["507766666"] = "idle", ["507766388"] = "idle", ["507777826"] = "walk",
	["913402848"] = "walk", ["913376220"] = "walk", ["180435571"] = "idle", ["180426354"] = "walk",
}
local function poseOfTrack(track)
	local anim = I.rawGet(track, "Animation")
	local id = if anim then tostring(I.rawGet(anim, "AnimationId") or "") else ""
	local num = string.match(id, "(%d+)")
	if num and ANIM_IDS[num] then
		return ANIM_IDS[num]
	end
	local s = string.lower(I.nameOf(track) .. " " .. (if anim then I.nameOf(anim) else "") .. " " .. id)
	local function has(w)
		return string.find(s, w, 1, true) ~= nil
	end
	if has("dance") or has("shuffle") or has("groove") or has("club") or has("춤") then
		return "dance"
	elseif has("wave") or has("hello") or has("greet") or has("인사") then
		return "wave"
	elseif has("sit") or has("seat") or has("앉") then
		return "sit"
	elseif has("cheer") or has("clap") or has("hype") or has("jump") or has("박수") then
		return "cheer"
	elseif has("point") then
		return "point"
	elseif has("laugh") then
		return "laugh"
	elseif has("phone") or has("text") or has("call") then
		return "phone"
	elseif has("talk") or has("chat") or has("argue") then
		return "talk"
	elseif has("walk") or has("run") or has("jog") then
		return "walk"
	elseif has("idle") or has("stand") or has("breath") then
		return "idle"
	end
	return "custom"
end
Bridge.poseOfTrack = poseOfTrack
local function humanoidOfTrack(track)
	local x = I.data(track)
	local animator = x and x._animator
	if not animator then
		return nil
	end
	local owner = I.parentOf(animator)
	if not owner then
		return nil
	end
	if I.isA(owner, "Humanoid") then
		return owner
	end
	-- AnimationController rigs: the model's Humanoid (if any), else the controller itself
	local model = I.parentOf(owner)
	if model then
		for _, c in I.children(model) do
			if I.isA(c, "Humanoid") then
				return c
			end
		end
	end
	if I.className(owner) == "AnimationController" then
		return owner
	end
	return nil
end
local function onAnimPlay(track)
	local hum = humanoidOfTrack(track)
	if not hum or hum == S.humanoid then
		return
	end
	local pose = poseOfTrack(track)
	if pose == "walk" or pose == "idle" then
		return -- locomotion comes from the rig's motion
	end
	T.npcPose[hum] = { pose = pose, speed = tonumber(I.rawGet(track, "Speed")) or 1, track = track }
	T.npcAnim[hum] = true
	if not T.npcKnown[hum] then
		T.npcDirty[hum] = true
	end
end
local function onAnimStop(track, fade)
	local hum = humanoidOfTrack(track)
	if not hum then
		return
	end
	local cur = T.npcPose[hum]
	if cur and cur.track == track then
		T.npcPose[hum] = nil
		T.npcAnim[hum] = true
	end
end
local function unregisterRig(hum)
	local rig = T.rigs[hum]
	if not rig then
		return
	end
	T.rigs[hum] = nil
	if T.rigByRoot[rig.root] == rig then
		T.rigByRoot[rig.root] = nil
	end
	if T.rigByModel[rig.model] == rig then
		T.rigByModel[rig.model] = nil
	end
	for _, p in rig.parts do
		if T.rigPart[p] == rig then
			T.rigPart[p] = nil
		end
	end
	T.rigMoved[rig] = nil
end
-- rest offsets of every part of the model relative to its root (captured when the rig is registered)
local function registerRig(hum, model, root)
	unregisterRig(hum)
	local rcf = I.rawGet(root, "CFrame")
	local inv = rcf:Inverse()
	local rig = { hum = hum, model = model, root = root, rel = {}, parts = {} }
	for _, p in I.modelParts(model) do
		if p ~= root and not isCharacterPart(p) and not T.rigPart[p] then
			local rel = inv * I.rawGet(p, "CFrame")
			if rel.Position.Magnitude < 40 then
				rig.rel[p] = rel
				rig.parts[#rig.parts + 1] = p
				T.rigPart[p] = rig
			end
		end
	end
	T.rigs[hum] = rig
	T.rigByRoot[root] = rig
	T.rigByModel[model] = rig
	return rig
end
local function followRig(rig)
	local root = rig.root
	if I.isDestroyed(root) then
		return
	end
	local rcf = I.rawGet(root, "CFrame")
	if rcf.X ~= rcf.X or rcf.XVector.X ~= rcf.XVector.X then
		return
	end
	local spatial = Services.spatial
	for _, p in rig.parts do
		if not I.isDestroyed(p) then
			I.rawSet(p, "CFrame", rcf * rig.rel[p])
			if I.rawGet(p, "CanQuery") or I.rawGet(p, "CanCollide") then
				spatial.partChanged(p)
			end
		end
	end
end
-- services.moveModel (Humanoid:MoveTo walking): a registered rig only moves its root (the limbs follow at collect)
Services.rigMove = function(model, oldRoot, newRoot)
	local rig = T.rigByModel[model]
	if not rig or I.isDestroyed(rig.root) then
		return false
	end
	local cur = I.rawGet(rig.root, "CFrame")
	-- the walker passes the root's own CFrame as oldRoot: the root simply becomes newRoot (no inverse: the product
	-- with a slightly non-orthonormal CFrame gave NaN, and a NaN root hung the spatial loops)
	local target = newRoot
	if (cur.Position - oldRoot.Position).Magnitude > 1e-3 then
		target = newRoot * oldRoot:Inverse() * cur
	end
	if target.X ~= target.X or target.Y ~= target.Y or target.Z ~= target.Z or target.XVector.X ~= target.XVector.X then
		return true -- never write NaN (the walk just does not advance this step)
	end
	I.setPartCFrame(rig.root, target)
	local pv = I.propsOf(model)
	local wp = pv and pv.WorldPivot
	if wp then
		local nwp = newRoot * oldRoot:Inverse() * wp
		if nwp.X == nwp.X then
			I.rawSet(model, "WorldPivot", nwp)
		end
	end
	return true
end
local function npcRecord(hum, out)
	local model = I.parentOf(hum)
	if not model or not I.isA(model, "Model") or model == S.character or not inWorkspace(model) then
		unregisterRig(hum)
		return false
	end
	local parts, n = {}, 0
	for _, c in I.children(model) do
		if kindOf(c) == "part" then
			local nm = I.nameOf(c)
			if RIG_NAMES[nm] then
				parts[nm] = I.idOf(c)
				n += 1
			end
		end
	end
	if n == 0 then
		return false
	end
	local hrp = I.rawGet(hum, "RootPart")
	if hrp == nil then
		hrp = I.rawGet(model, "PrimaryPart")
	end
	local rootPart = hrp
	if rootPart == nil then
		for _, c in I.children(model) do
			local nm = I.nameOf(c)
			if kindOf(c) == "part" and (nm == "HumanoidRootPart" or nm == "Torso" or nm == "UpperTorso") then
				rootPart = c
				if nm == "HumanoidRootPart" then
					break
				end
			end
		end
	end
	local root = if rootPart then I.idOf(rootPart) else nil
	local rig = if parts.UpperTorso or parts.LeftUpperArm then "R15" else "R6"
	local pose = T.npcPose[hum]
	out[#out + 1] = jsonEncode({
		op = "npc", id = I.idOf(hum), model = I.idOf(model), root = root, rig = rig, parts = parts, name = I.nameOf(model),
		pose = if pose then pose.pose else "", speed = if pose then pose.speed else 1, sit = I.rawGet(hum, "Sit") == true,
	})
	-- rest offsets for the rig follow (render3d places the limbs from the root: [[id, x,y,z, r00..r22], ...])
	if rootPart and not I.isDestroyed(rootPart) and not Bridge.noRigFollow then
		local rg = registerRig(hum, model, rootPart)
		out[#out] = string.sub(out[#out], 1, -2) .. ',"rel":['
		local first = true
		for _, p in rg.parts do
			if not first then
				out[#out + 1] = ","
			end
			first = false
			out[#out + 1] = "[" .. tostring(I.idOf(p)) .. ","
			local cf = rg.rel[p]
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			out[#out + 1] = jnum3(x) .. "," .. jnum3(y) .. "," .. jnum3(z) .. "," .. jnum(r00) .. "," .. jnum(r01) .. "," .. jnum(r02) .. "," .. jnum(r10) .. "," .. jnum(r11) .. "," .. jnum(r12) .. "," .. jnum(r20) .. "," .. jnum(r21) .. "," .. jnum(r22) .. "]"
		end
		out[#out + 1] = "]}"
	end
	out[#out + 1] = ","
	return true
end
local function collectNpcs(out)
	if next(T.npcDirty) then
		-- at most 24 rig (re)registrations per step (the ~160 map rigs at boot made the first step, which ends the
		-- boot screen, several seconds long on a phone); the rest stay dirty for the next steps
		local d = T.npcDirty
		T.npcDirty = {}
		local budget = 24
		local later = nil
		for hum in d do
			if budget <= 0 then
				later = later or {}
				later[hum] = true
				continue
			end
			budget -= 1
			if hum ~= S.humanoid then
				if not I.isDestroyed(hum) and npcRecord(hum, out) then
					T.npcKnown[hum] = I.idOf(hum)
					T.npcAnim[hum] = nil
				else
					unregisterRig(hum)
					if T.npcKnown[hum] then
						out[#out + 1] = '{"op":"npcRemoved","id":' .. tostring(T.npcKnown[hum]) .. "},"
						T.npcKnown[hum] = nil
					end
				end
			end
		end
		if later then
			for hum in later do
				T.npcDirty[hum] = true
			end
		end
	end
	if next(T.npcAnim) then
		local a = T.npcAnim
		T.npcAnim = {}
		for hum in a do
			if T.npcKnown[hum] and not I.isDestroyed(hum) then
				local pose = T.npcPose[hum]
				out[#out + 1] = jsonEncode({ op = "npcPose", id = T.npcKnown[hum], pose = if pose then pose.pose else "", speed = if pose then pose.speed else 1, sit = I.rawGet(hum, "Sit") == true })
				out[#out + 1] = ","
			end
		end
	end
end

-- assemblies: member offsets relative to the root (render3d / rblx_physics place members from the root's CFrame)
local function relEntry(p, cf, out)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	out[#out + 1] = "[" .. tostring(I.idOf(p)) .. "," .. jnum3(x) .. "," .. jnum3(y) .. "," .. jnum3(z) .. "," .. jnum(r00) .. "," .. jnum(r01) .. "," .. jnum(r02) .. "," .. jnum(r10) .. "," .. jnum(r11) .. "," .. jnum(r12) .. "," .. jnum(r20) .. "," .. jnum(r21) .. "," .. jnum(r22) .. "]"
end
asmOps = function(out)
	Asm.ensureAll()
	local late = Asm.dropped
	if #late > 0 then
		Asm.dropped = {}
		for _, d in late do
			out[#out + 1] = '{"op":"asmRemoved","id":' .. tostring(d.id) .. ',"v":' .. tostring(d.serial or 0) .. "},"
			for _, p in d.parts do
				if T.asmMember[p] == d.id then
					T.asmMember[p] = nil
				end
				if not I.isDestroyed(p) and not Asm.asmOf[p] then
					markPart(p, F_CF) -- (its record goes out next step)
				end
			end
		end
	end
	local changed = Asm.changed
	if next(changed) then
		Asm.changed = {}
		for a in changed do
			if Asm.live[a] and not I.isDestroyed(a.root) then
				local rid = I.idOf(a.root)
				out[#out + 1] = '{"op":"asm","id":' .. tostring(rid) .. ',"v":' .. tostring(a.serial or 0)
				if a.charRooted then
					out[#out + 1] = ',"char":true'
				end
				out[#out + 1] = ',"anchored":' .. tostring(I.rawGet(a.root, "Anchored") == true) .. ',"rel":['
				local first = true
				for _, p in a.parts do
					if p ~= a.root and not isCharacterPart(p) and not I.isDestroyed(p) then
						if not first then
							out[#out + 1] = ","
						end
						first = false
						relEntry(p, a.rel[p], out)
						T.asmMember[p] = rid
						if not T.partKnown[p] then
							markPart(p, F_FULL)
						end
					end
				end
				out[#out + 1] = "]},"
				a.sent = true
				Asm.relDirty[a] = nil
			end
		end
	end
	local rd = Asm.relDirty
	if next(rd) then
		Asm.relDirty = {}
		for a, set in rd do
			if Asm.live[a] and a.sent and not I.isDestroyed(a.root) then
				out[#out + 1] = '{"op":"asmRel","id":' .. tostring(I.idOf(a.root)) .. ',"rel":['
				local first = true
				for p in set do
					if a.rel[p] and not isCharacterPart(p) and not I.isDestroyed(p) then
						if not first then
							out[#out + 1] = ","
						end
						first = false
						relEntry(p, a.rel[p], out)
					end
				end
				out[#out + 1] = "]},"
			end
		end
	end
end

local function v3json(v)
	return "[" .. jnum3(v.X) .. "," .. jnum3(v.Y) .. "," .. jnum3(v.Z) .. "]"
end
local function attPart(att)
	if att == nil or I.isDestroyed(att) then
		return nil, nil
	end
	local p = I.parentOf(att)
	if p and kindOf(p) == "part" and not I.isDestroyed(p) then
		return p, I.rawGet(att, "CFrame")
	end
	return nil, nil
end
constraintRecord = function(c, out)
	local id = I.idOf(c)
	local cls = I.className(c)
	local p0, a0 = attPart(I.rawGet(c, "Attachment0"))
	local p1, a1 = attPart(I.rawGet(c, "Attachment1"))
	local alive = I.inDataModel(c) and p0 ~= nil and inWorkspace(p0)
	if not alive then
		if T.consKnown[c] then
			T.consKnown[c] = nil
			out[#out + 1] = '{"op":"constraintRemoved","id":' .. tostring(id) .. "},"
		end
		return
	end
	T.consKnown[c] = true
	out[#out + 1] = '{"op":"constraint","id":' .. tostring(id) .. ',"type":' .. jstr(cls) .. ',"part0":' .. tostring(I.idOf(p0)) .. ',"att0":'
	cfArray(a0, out)
	if p1 then
		out[#out + 1] = ',"part1":' .. tostring(I.idOf(p1)) .. ',"att1":'
		cfArray(a1, out)
	end
	out[#out + 1] = ',"enabled":' .. tostring(I.rawGet(c, "Enabled") ~= false)
	local function en(prop)
		local v = I.rawGet(c, prop)
		return jstr(if v then v.Name else "")
	end
	if cls == "VectorForce" then
		out[#out + 1] = ',"force":' .. v3json(I.rawGet(c, "Force")) .. ',"relativeTo":' .. en("RelativeTo") .. ',"applyAtCenterOfMass":' .. tostring(I.rawGet(c, "ApplyAtCenterOfMass") == true)
	elseif cls == "Torque" then
		out[#out + 1] = ',"torque":' .. v3json(I.rawGet(c, "Torque")) .. ',"relativeTo":' .. en("RelativeTo")
	elseif cls == "LinearVelocity" then
		out[#out + 1] = ',"vectorVelocity":' .. v3json(I.rawGet(c, "VectorVelocity")) .. ',"maxForce":' .. jnum(math.min(I.rawGet(c, "MaxForce"), 1e300)) .. ',"relativeTo":' .. en("RelativeTo")
			.. ',"velocityConstraintMode":' .. en("VelocityConstraintMode") .. ',"lineDirection":' .. v3json(I.rawGet(c, "LineDirection")) .. ',"lineVelocity":' .. jnum(I.rawGet(c, "LineVelocity"))
			.. ',"forceLimitsEnabled":' .. tostring(I.rawGet(c, "ForceLimitsEnabled") ~= false)
	elseif cls == "AngularVelocity" then
		out[#out + 1] = ',"angularVelocity":' .. v3json(I.rawGet(c, "AngularVelocity")) .. ',"maxTorque":' .. jnum(math.min(I.rawGet(c, "MaxTorque"), 1e300)) .. ',"relativeTo":' .. en("RelativeTo")
			.. ',"reactionTorqueEnabled":' .. tostring(I.rawGet(c, "ReactionTorqueEnabled") == true)
	elseif cls == "AlignOrientation" then
		out[#out + 1] = ',"mode":' .. en("Mode") .. ',"cframe":'
		cfArray(I.rawGet(c, "CFrame"), out)
		out[#out + 1] = ',"maxTorque":' .. jnum(math.min(I.rawGet(c, "MaxTorque"), 1e300)) .. ',"maxAngularVelocity":' .. jnum(math.min(I.rawGet(c, "MaxAngularVelocity"), 1e300))
			.. ',"responsiveness":' .. jnum(I.rawGet(c, "Responsiveness")) .. ',"rigidityEnabled":' .. tostring(I.rawGet(c, "RigidityEnabled") == true) .. ',"primaryAxisOnly":' .. tostring(I.rawGet(c, "PrimaryAxisOnly") == true)
	elseif cls == "AlignPosition" then
		out[#out + 1] = ',"mode":' .. en("Mode") .. ',"position":' .. v3json(I.rawGet(c, "Position")) .. ',"maxForce":' .. jnum(math.min(I.rawGet(c, "MaxForce"), 1e300))
			.. ',"maxVelocity":' .. jnum(math.min(I.rawGet(c, "MaxVelocity"), 1e300)) .. ',"responsiveness":' .. jnum(I.rawGet(c, "Responsiveness"))
			.. ',"rigidityEnabled":' .. tostring(I.rawGet(c, "RigidityEnabled") == true) .. ',"applyAtCenterOfMass":' .. tostring(I.rawGet(c, "ApplyAtCenterOfMass") == true)
	end
	out[#out + 1] = "},"
end

local function collectChanges(out)
	local tc0 = clock()
	-- character spawn
	if S.characterDirty and S.character then
		S.characterDirty = false
		S.characterPartSet = {}
		for _, p in S.characterParts or {} do
			S.characterPartSet[p] = true
			T.partDirty[p] = nil
		end
		characterRecord(out)
		out[#out + 1] = ","
		T.teleport = true
		T.humanoidDirty = true
		T.cameraDirty = true
		if Asm then
			Asm.characterChanged()
		end
	end
	-- rigid assemblies: rebuild / re-place, the carried character, ended assemblies first
	if Asm then
		Asm.ensureAll()
		Asm.updateAttach()
		if Asm.attachDirty then
			Asm.attachDirty = false
			S.carried = Asm.attach ~= nil
			T.humanoidDirty = true
		end
		local dropped = Asm.dropped
		if #dropped > 0 then
			Asm.dropped = {}
			for _, d in dropped do
				out[#out + 1] = '{"op":"asmRemoved","id":' .. tostring(d.id) .. ',"v":' .. tostring(d.serial or 0) .. "},"
				for _, p in d.parts do
					if T.asmMember[p] == d.id then
						T.asmMember[p] = nil
					end
					if not I.isDestroyed(p) and not Asm.asmOf[p] then
						markPart(p, F_CF)
					end
				end
			end
		end
	end
	-- NPC rigs whose root moved: limbs follow (engine-side only; render3d does the same from the npc op's rest offsets)
	if next(T.rigMoved) then
		local rm = T.rigMoved
		T.rigMoved = {}
		for rig in rm do
			if T.rigs[rig.hum] == rig then
				followRig(rig)
			end
		end
	end
	-- parts
	local removed = T.removed
	if #removed > 0 then
		for _, id in removed do
			out[#out + 1] = '{"op":"partRemoved","id":' .. tostring(id) .. "},"
		end
		T.removed = {}
	end
	local dirty = T.partDirty
	if next(dirty) then
		T.partDirty = {}
		local members = T.asmMember
		for part, mask in dirty do
			if not I.isDestroyed(part) then
				local known = T.partKnown[part]
				if known and mask == F_CF and members[part] then
					continue -- placed from its assembly root by render3d / the JS physics
				end
				if not known then
					-- first record of this part. Runtime parts: everything, once they are in the Workspace.
					-- Place parts are already in the renderer's static arrays, except the ones the exporter drops
					-- (fully transparent and CanCollide=false): those get a full record too.
					if T.runtime[part] then
						if not inWorkspace(part) then
							continue
						end
						mask = bit32.bor(mask, F_FULL)
					elseif I.peek(part, "Transparency") >= 1 and not I.peek(part, "CanCollide") then
						mask = bit32.bor(mask, F_FULL)
					end
					T.partKnown[part] = true
					local js = T.jointsOf[part]
					if js then
						for j in js do
							T.jointDirty[j] = true
						end
					end
				end
				partRecord(part, mask, out)
				out[#out + 1] = ","
			end
		end
	end
	if Asm then
		asmOps(out)
	end
	local tc1 = clock()
	PH.cParts += tc1 - tc0
	-- joints (after the part records they reference)
	if #T.jointRemoved > 0 then
		for _, id in T.jointRemoved do
			out[#out + 1] = '{"op":"jointRemoved","id":' .. tostring(id) .. "},"
		end
		T.jointRemoved = {}
	end
	if next(T.jointDirty) then
		local jd = T.jointDirty
		T.jointDirty = {}
		for j in jd do
			jointRecord(j, out)
		end
	end
	if #T.consRemoved > 0 then
		for _, id in T.consRemoved do
			out[#out + 1] = '{"op":"constraintRemoved","id":' .. tostring(id) .. "},"
		end
		T.consRemoved = {}
	end
	if next(T.consDirty) then
		local cd = T.consDirty
		T.consDirty = {}
		for c in cd do
			constraintRecord(c, out)
		end
	end
	local tc2 = clock()
	PH.cJoints += tc2 - tc1
	-- lights
	for _, id in T.lightRemoved do
		out[#out + 1] = '{"op":"lightRemoved","id":' .. tostring(id) .. "},"
	end
	T.lightRemoved = {}
	if next(T.lightDirty) then
		local ld = T.lightDirty
		T.lightDirty = {}
		for light in ld do
			if not I.isDestroyed(light) and (T.lightKnown[light] or inWorkspace(light)) then
				lightRecord(light, out)
				out[#out + 1] = ","
			end
		end
	end
	-- signs
	if next(T.signDirty) then
		local sd = T.signDirty
		T.signDirty = {}
		for sg in sd do
			if not I.isDestroyed(sg) and (inWorkspace(sg) or T.signKnown) then
				signRecord(sg, out)
				out[#out + 1] = ","
			end
		end
	end
	-- lighting (throttled to 10 Hz)
	local now = Sched.now()
	if T.lightingDirty and now - T.lightingAt >= 0.1 then
		T.lightingDirty = false
		T.lightingAt = now
		lightingRecord(out)
		out[#out + 1] = ","
	end
	-- camera (script driven)
	if T.cameraDirty then
		T.cameraDirty = false
		cameraRecord(out)
		out[#out + 1] = ","
	end
	-- humanoid
	if T.humanoidDirty then
		T.humanoidDirty = false
		humanoidRecord(out)
		out[#out + 1] = ","
	end
	-- teleport (script moved the local character)
	if T.teleport and S.hrp and not I.isDestroyed(S.hrp) then
		T.teleport = false
		S.teleportSeq += 1
		S.teleportFrame = Sched.frame()
		out[#out + 1] = '{"op":"teleport","seq":' .. tostring(S.teleportSeq) .. ',"cf":'
		cfArray(I.rawGet(S.hrp, "CFrame"), out)
		out[#out + 1] = "},"
	end
	S.localWalk = false
	-- NPC rigs (humanoid models other than the local character): rig part map once, poses on change
	collectNpcs(out)
	-- GUI
	local tg0 = clock()
	flushGui(out)
	local tg1 = clock()
	PH.cGui += tg1 - tg0
	-- TextBox focus requests
	if S.focusRequest and not S.guiInputApplying then
		local f = S.focusRequest
		S.focusRequest = nil
		out[#out + 1] = '{"op":"' .. (if f.focus then "guiFocus" else "guiBlur") .. '","id":' .. tostring(f.id) .. "},"
	end
	-- prompts (every 5 frames or when something changed)
	if S.promptsDirty or frameCount - T.promptAt >= 5 then
		local full = S.promptsDirty
		S.promptsDirty = false
		T.promptAt = frameCount
		local sig = promptList(full)
		if sig ~= T.promptSig then
			T.promptSig = sig
			out[#out + 1] = '{"op":"prompt","prompts":' .. sig .. "},"
		end
	end
	local tp1 = clock()
	PH.cPrompts += tp1 - tg1
	-- night windows
	if next(T.nightDirty) then
		local nd = T.nightDirty
		T.nightDirty = {}
		local items = {}
		for inst in nd do
			if not I.isDestroyed(inst) then
				table.insert(items, { id = I.idOf(inst), Lit = inst:GetAttribute("Lit"), LitColor = inst:GetAttribute("LitColor") })
			end
		end
		out[#out + 1] = jsonEncode({ op = "nightWindows", list = items })
		out[#out + 1] = ","
	end
	-- CoreGui / topbar
	if S.coreChanged then
		S.coreChanged = false
		out[#out + 1] = jsonEncode({ op = "core", coreGui = S.coreGui, topbar = S.coreValues.TopbarEnabled ~= false })
		out[#out + 1] = ","
	end
	-- notifications
	if #S.notifications > 0 then
		for _, n in S.notifications do
			out[#out + 1] = jsonEncode({ op = "notify", text = n.text, title = n.title, kind = n.kind, duration = n.duration })
			out[#out + 1] = ","
		end
		S.notifications = {}
	end
	-- sounds + audio environment (js/audio.js)
	if Audio and S.player then
		local okA, errA = pcall(Audio.collect, out, frameCount, Sched.now())
		if not okA and not T.audioErr then
			T.audioErr = true
			Env.output("warn", "[audio] " .. tostring(errA), "engine/audio", nil, nil)
		end
	end
	drainOutput(out)
	PH.cOut += clock() - tp1
end

local function bootChanges(out)
	-- initial records: ready + lighting + every light in the Workspace
	local info = table.clone(bootInfo or {})
	info.op = "ready"
	out[#out + 1] = jsonEncode(info)
	out[#out + 1] = ","
	T.lightingDirty = true
	for _, d in S.workspace:GetDescendants() do
		local k = kindOf(d)
		if k == "light" then
			T.lightDirty[d] = true
		elseif k == "joint" then
			T.jointDirty[d] = true
		elseif k == "humanoid" then
			T.npcDirty[d] = true -- key NPCs / club crowd rigs placed in the map
		end
	end
	T.cameraDirty = true
end

function Bridge.step(dt, inputJSON)
	if not booted then
		return '[{"op":"fatal","text":"engine not booted"}]'
	end
	local t0 = clock()
	dt = tonumber(dt) or 1 / 30
	if dt < 0 then
		dt = 0
	elseif dt > 0.25 then
		dt = 0.25
	end
	local out = { "[" }
	if frameCount == 0 then
		bootChanges(out)
	end
	frameCount += 1
	Sched.advance(dt)
	-- input
	local inp = nil
	if type(inputJSON) == "string" and #inputJSON > 2 then
		local ok, v = pcall(ClassDB.jsonDecode, inputJSON)
		if ok and type(v) == "table" then
			inp = v
		end
	elseif type(inputJSON) == "table" then
		inp = inputJSON
	end
	local studioReplies = nil
	local tIn = clock()
	PH.decode += tIn - t0
	if inp then
		local ok, err = pcall(Services.applyInput, inp)
		if not ok then
			Env.reportError("[bridge input] " .. tostring(err), debug.traceback(), nil)
		end
		if type(inp.character) == "table" then
			if type(inp.character.parts) == "table" then
				pcall(applyPhysicsParts, inp.character.parts)
			end
			if type(inp.character.events) == "table" then
				pcall(applyCharacterEvents, inp.character.events)
			end
		end
		if type(inp.studio) == "table" and #inp.studio > 0 and studio then
			local ok2, rep = pcall(studio.handleBatch, studio, inp.studio)
			if ok2 then
				studioReplies = rep
			end
		end
	end
	-- frame phases
	local tPh = clock()
	PH.input += tPh - tIn
	local ok, err = pcall(function()
		if S.player then
			Services.renderPhase(dt)
		end
		Services.simPhase(dt)
		Services.heartbeatPhase(dt)
		Sched.resumeDue()
		Remotes.pump()
		Sched.flush()
		Services.tickBoot()
		Sched.flush()
	end)
	if not ok then
		Env.reportError("[engine frame] " .. tostring(err), debug.traceback(), nil)
	end
	-- changes
	local tCol = clock()
	PH.phases += tCol - tPh
	local ok2, err2 = pcall(collectChanges, out)
	if not ok2 then
		Env.reportError("[bridge changes] " .. tostring(err2), debug.traceback(), nil)
		pcall(drainOutput, out)
	end
	if studioReplies then
		out[#out + 1] = '{"op":"studioReplies","replies":' .. jsonEncode(studioReplies) .. "},"
	end
	PH.collect += clock() - tCol
	PH.steps += 1
	local ms = (clock() - t0) * 1000
	stepMsAcc += ms
	stepN += 1
	if ms > stepMsMax then
		stepMsMax = ms
	end
	if frameCount % 30 == 0 then
		local hp, dq = Sched.pending()
		out[#out + 1] = jsonEncode({
			op = "engineStats",
			frame = frameCount,
			t = Sched.now(),
			stepMs = stepMsAcc / math.max(stepN, 1),
			stepMsMax = stepMsMax,
			gcKB = gcinfo(),
			timers = hp,
			errors = Env.errorCount,
			lazyDecodes = Loader.lazyDecodes(),
			rays = Services.spatial.stats.rays,
			resumes = Sched.stats.resumes,
			deferredResumes = Sched.stats.budgetDeferred or 0,
		})
		out[#out + 1] = ","
		stepMsAcc, stepN, stepMsMax = 0, 0, 0
	end
	local tEnc = clock()
	local s = table.concat(out)
	PH.encode += clock() - tEnc
	if string.sub(s, -1) == "," then
		s = string.sub(s, 1, -2)
	end
	return s .. "]"
end

---------------------------------------------------------------------------------------------------------
-- Studio (call mode)
---------------------------------------------------------------------------------------------------------
function Bridge.studio(req)
	if not studio then
		return '{"ok":false,"err":"studio unavailable"}'
	end
	if type(req) == "table" then
		return jsonEncode(studio:handle(req))
	end
	return studio:handleJSON(req)
end

-- profiling report (tests): per-script CPU (Sched.profile must be enabled first) + bridge phase times
function Bridge.enableProfile()
	Sched.profile = {}
	for k in PH do
		PH[k] = 0
	end
end
function Bridge.profileReport()
	local list = {}
	for k, v in Sched.profile or {} do
		table.insert(list, { name = k, ms = floor(v * 10000) / 10 })
	end
	table.sort(list, function(a, b)
		return a.ms > b.ms
	end)
	local ph = {}
	for k, v in PH do
		ph[k] = if k == "steps" then v else floor(v * 10000) / 10
	end
	return jsonEncode({ scripts = list, phases = ph, lazyDecodes = Loader.lazyDecodes(), rays = Services.spatial.stats })
end

-- engine internals for tests / tools
Bridge.modules = { DT = DT, Enum = Enum, I = I, Sched = Sched, Env = Env, Remotes = Remotes, Services = Services, Loader = Loader, Studio = Studio }
Bridge.S = S
function Bridge.game()
	return I.dataModel
end
function Bridge.studioInstance()
	return studio
end

return Bridge
