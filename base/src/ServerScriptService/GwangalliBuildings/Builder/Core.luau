-- Builder/Core: the structural pieces every building shares: doors, switchback stairs, elevators
-- (shaft + car + hall doors + buttons + displays), ceiling lights, signs, restrooms, parking floors,
-- rooftop equipment. Every function takes WORLD frames (callers map plan coordinates through rec.cf).
--
-- Doors are data-driven Models (tag GwB_Door) animated by every client from attributes written by the
-- server Doors service; elevators are Models (tag GwB_Elevator) run by the server Elevators service.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Kit = Shared.Kit
local Config = Shared.Config
local Palette = Shared.Palette
local Furniture = Shared.Furniture
local Util = Shared.Util

local Core = {}

local V3, CF = Vector3.new, CFrame.new
local rad = math.rad
local F = Palette.FINISH
local STAIR_GAP = 0.8 -- same as Plan.STAIR_GAP

local doorCount = 0

-------------------------------------------------------------------------------------------------
-- DOORS
-- frame: world CFrame at the centre-bottom of the opening, on the wall's centre plane; -Z (LookVector)
-- points to the FRONT side (corridor / street). spec:
--   w, h, t (wall thickness), kind = swing | double | slide | auto | glass | stall | fire | unit | room
--   | shutter | sliding_glass, hinge = "left" | "right" (seen from the front), swing = "both" | "front" |
--   "back", lock = none | unit | room | staff | stall, unitId, shopId, label (plate text), id,
--   mat / color (leaf), frameColor, autoClose (seconds), number (unit number plate), bell = true
-------------------------------------------------------------------------------------------------
local DOOR_LOOK = {
	swing = { mat = "Wood", color = { 196, 168, 132 } },
	unit = { mat = "Metal", color = { 86, 92, 100 } },
	fire = { mat = "Metal", color = { 150, 154, 158 } },
	stall = { mat = "SmoothPlastic", color = { 214, 216, 220 } },
	room = { mat = "Wood", color = { 120, 90, 66 } },
	glass = { mat = "Glass", color = { 190, 214, 222 } },
	auto = { mat = "Glass", color = { 190, 214, 222 } },
	slide = { mat = "Wood", color = { 220, 214, 200 } },
	sliding_glass = { mat = "Glass", color = { 200, 222, 230 } },
	shutter = { mat = "Metal", color = { 160, 164, 168 } },
	double = { mat = "Wood", color = { 120, 90, 66 } },
}

local function leafModel(door: Model, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = door
	return m
end

local function glassLeaf(leaf: Model, cf: CFrame, w: number, h: number, frameColor: any, tint: any)
	-- aluminium frame + glass pane, pivot on the panel
	local pane = Kit.part(leaf, cf * CF(0, h / 2, 0), V3(w - 0.3, h - 0.3, 0.12), "Glass", tint or { 190, 214, 222 }, { tr = 0.55, name = "Panel", refl = 0.1 })
	Kit.part(leaf, cf * CF(0, h - 0.08, 0), V3(w, 0.16, 0.22), "Metal", frameColor, { name = "Rail", collide = false })
	Kit.part(leaf, cf * CF(0, 0.08, 0), V3(w, 0.16, 0.22), "Metal", frameColor, { name = "Rail", collide = false })
	Kit.part(leaf, cf * CF(-w / 2 + 0.08, h / 2, 0), V3(0.16, h, 0.22), "Metal", frameColor, { name = "Stile", collide = false })
	Kit.part(leaf, cf * CF(w / 2 - 0.08, h / 2, 0), V3(0.16, h, 0.22), "Metal", frameColor, { name = "Stile", collide = false })
	leaf.PrimaryPart = pane
	return pane
end

function Core.door(parent: Instance, frame: CFrame, spec: any): Model
	doorCount += 1
	local kind = spec.kind or "swing"
	local w, h = spec.w or Config.DOOR_W, spec.h or Config.DOOR_H
	local t = spec.t or Config.WALL_INT
	local id = spec.id or ("d" .. doorCount)
	local look = DOOR_LOOK[kind] or DOOR_LOOK.swing
	local leafMat = spec.mat or look.mat
	local leafColor = spec.color or look.color
	local frameColor = spec.frameColor or (if kind == "glass" or kind == "auto" or kind == "sliding_glass" then { 70, 72, 78 } else { 236, 232, 224 })

	local door = Instance.new("Model")
	door.Name = "Door_" .. id
	door:SetAttribute("DoorId", id)
	door:SetAttribute("DoorKind", kind)
	door:SetAttribute("Open", false)
	door:SetAttribute("OpenDir", 1)
	door:SetAttribute("Width", w)
	door:SetAttribute("Height", h)
	door:SetAttribute("Frame", frame)
	door:SetAttribute("Lock", spec.lock or "none")
	door:SetAttribute("Locked", spec.lock ~= nil and spec.lock ~= "none" and spec.lock ~= "stall")
	door:SetAttribute("Swing", spec.swing or "both")
	if spec.unitId then
		door:SetAttribute("UnitId", spec.unitId)
	end
	if spec.shopId then
		door:SetAttribute("ShopId", spec.shopId)
	end
	if spec.roomKey then
		door:SetAttribute("RoomKey", spec.roomKey)
	end
	if spec.label then
		door:SetAttribute("Label", spec.label)
	end
	if spec.autoClose then
		door:SetAttribute("AutoClose", spec.autoClose)
	end
	if spec.restricted then
		door:SetAttribute("Restricted", spec.restricted)
	end

	-- casing (not for frameless glass / stall)
	if kind ~= "stall" and spec.casing ~= false then
		local cw = 0.26
		local depth = t + 0.12
		local cm = if kind == "glass" or kind == "auto" or kind == "sliding_glass" then "Metal" else "SmoothPlastic"
		Kit.part(door, frame * CF(-w / 2 - cw / 2, h / 2, 0), V3(cw, h + cw, depth), cm, frameColor, { name = "Jamb" })
		Kit.part(door, frame * CF(w / 2 + cw / 2, h / 2, 0), V3(cw, h + cw, depth), cm, frameColor, { name = "Jamb" })
		Kit.part(door, frame * CF(0, h + cw / 2, 0), V3(w + 2 * cw, cw, depth), cm, frameColor, { name = "Head" })
	end

	local hingeLeft = (spec.hinge or "left") == "left"
	if kind == "double" or kind == "glass" then
		-- two hinged leaves
		for i, sgn in { -1, 1 } do
			local leaf = leafModel(door, "Leaf" .. i)
			local lw = w / 2
			local cx = sgn * lw / 2
			if kind == "glass" then
				glassLeaf(leaf, frame * CF(cx, 0.05, 0), lw - 0.04, h - 0.1, frameColor, leafColor)
				Kit.part(leaf, frame * CF(cx - sgn * (lw / 2 - 0.35), 3.6, -0.2), V3(0.1, 2.4, 0.1), "Metal", { 200, 200, 204 }, { name = "Pull", collide = false })
				Kit.part(leaf, frame * CF(cx - sgn * (lw / 2 - 0.35), 3.6, 0.2), V3(0.1, 2.4, 0.1), "Metal", { 200, 200, 204 }, { name = "Pull", collide = false })
			else
				local pane = Kit.part(leaf, frame * CF(cx, h / 2, 0), V3(lw - 0.06, h - 0.1, 0.22), leafMat, leafColor, { name = "Panel" })
				leaf.PrimaryPart = pane
				Kit.part(leaf, frame * CF(cx - sgn * (lw / 2 - 0.4), 3.4, -0.16), V3(0.5, 0.12, 0.12), "Metal", { 190, 190, 194 }, { name = "Handle", collide = false })
				Kit.part(leaf, frame * CF(cx - sgn * (lw / 2 - 0.4), 3.4, 0.16), V3(0.5, 0.12, 0.12), "Metal", { 190, 190, 194 }, { name = "Handle", collide = false })
			end
			leaf:SetAttribute("HingeX", sgn * w / 2)
			leaf:SetAttribute("Mode", "swing")
		end
	elseif kind == "auto" or kind == "slide" or kind == "sliding_glass" then
		local pair = kind == "auto"
		local n = if pair then 2 else 1
		for i = 1, n do
			local leaf = leafModel(door, "Leaf" .. i)
			local lw = if pair then w / 2 + 0.05 else w + 0.1
			local sgn = if pair then (if i == 1 then -1 else 1) else (if hingeLeft then -1 else 1)
			local cx = if pair then sgn * (w / 4) else 0
			local zoff = if pair then 0 else 0.1
			if kind == "slide" then
				local pane = Kit.part(leaf, frame * CF(cx, h / 2, zoff), V3(lw, h - 0.1, 0.18), leafMat, leafColor, { name = "Panel" })
				leaf.PrimaryPart = pane
				Kit.part(leaf, frame * CF(cx - sgn * (lw / 2 - 0.3), 3.4, zoff - 0.12), V3(0.1, 1.2, 0.08), "Metal", { 150, 150, 154 }, { name = "Handle", collide = false })
			else
				glassLeaf(leaf, frame * CF(cx, 0.05, zoff), lw, h - 0.1, frameColor, leafColor)
			end
			leaf:SetAttribute("SlideX", sgn * (if pair then w / 2 - 0.1 else w - 0.2))
			leaf:SetAttribute("Mode", "slide")
		end
		if pair then
			local sensor = Kit.part(door, frame * CF(0, h + 0.7, -0.35), V3(2.2, 0.5, 0.4), "SmoothPlastic", { 40, 40, 44 }, { name = "Sensor", collide = false })
			Kit.part(door, frame * CF(0.6, h + 0.7, -0.56), V3(0.2, 0.15, 0.04), "Neon", { 255, 40, 40 }, { name = "SensorLed", collide = false })
			Kit.sound(sensor, "auto_door", { volume = 0.5, maxDist = 30, loop = false, attrs = { Trigger = "door" } })
		end
	elseif kind == "shutter" then
		local leaf = leafModel(door, "Leaf1")
		local pane = Kit.part(leaf, frame * CF(0, h / 2, -0.3), V3(w + 0.3, h, 0.2), "DiamondPlate", leafColor, { name = "Panel" })
		leaf.PrimaryPart = pane
		leaf:SetAttribute("Mode", "lift")
		leaf:SetAttribute("Lift", h - 0.6)
		Kit.part(door, frame * CF(0, h + 0.6, -0.4), V3(w + 0.6, 1.2, 0.9), "Metal", { 120, 122, 126 }, { name = "Box", collide = false })
	else
		-- single hinged leaf: swing, unit, fire, stall, room
		local leaf = leafModel(door, "Leaf1")
		local lw = w - 0.08
		local y0 = if kind == "stall" then 0.6 else 0.04
		local lh = if kind == "stall" then h - 0.6 else h - 0.08
		local th = if kind == "unit" or kind == "fire" then 0.3 else (if kind == "stall" then 0.1 else 0.2)
		local pane = Kit.part(leaf, frame * CF(0, y0 + lh / 2, 0), V3(lw, lh, th), leafMat, leafColor, { name = "Panel" })
		leaf.PrimaryPart = pane
		local hx = if hingeLeft then -w / 2 else w / 2
		local handleX = -hx * 0.82
		leaf:SetAttribute("HingeX", hx)
		leaf:SetAttribute("Mode", "swing")
		local hc = if kind == "fire" then { 40, 40, 42 } else { 196, 196, 200 }
		Kit.part(leaf, frame * CF(handleX, 3.4, -th / 2 - 0.08), V3(0.55, 0.12, 0.12), "Metal", hc, { name = "Handle", collide = false })
		Kit.part(leaf, frame * CF(handleX, 3.4, th / 2 + 0.08), V3(0.55, 0.12, 0.12), "Metal", hc, { name = "Handle", collide = false })
		if kind == "unit" then
			-- 도어락 (digital lock) on the front face + peephole
			local pad = Kit.part(leaf, frame * CF(handleX, 4.0, -th / 2 - 0.06), V3(0.5, 1.1, 0.1), "SmoothPlastic", { 30, 30, 34 }, { name = "Keypad", collide = false })
			Kit.text(pad, "front", "● ● ●\n● ● ●\n● ● ●", { color = { 120, 200, 255 }, ppS = 60, light = 0, bold = false, maxDist = 30 })
			pad:SetAttribute("Keypad", true)
			Kit.part(leaf, frame * CF(0, 5.4, -th / 2 - 0.02), V3(0.12, 0.12, 0.06), "Metal", { 200, 200, 204 }, { name = "Peephole", collide = false })
			if spec.number then
				local plate = Kit.part(door, frame * CF(0, h + 0.75, -t / 2 - 0.08), V3(1.6, 0.6, 0.08), "SmoothPlastic", { 250, 250, 248 }, { name = "Plate", collide = false })
				Kit.text(plate, "front", spec.number, { color = { 40, 40, 44 }, ppS = 50, maxDist = 40 })
			end
		elseif kind == "fire" then
			Kit.part(leaf, frame * CF(0, 6.4, -th / 2 - 0.02), V3(1.6, 0.4, 0.04), "SmoothPlastic", { 220, 30, 30 }, { name = "Sticker", collide = false })
		elseif kind == "stall" then
			local lockInd = Kit.part(leaf, frame * CF(handleX, 3.9, -th / 2 - 0.05), V3(0.35, 0.2, 0.06), "Neon", { 40, 200, 80 }, { name = "LockInd", collide = false })
			lockInd:SetAttribute("LockIndicator", true)
		elseif kind == "room" and spec.number then
			local plate = Kit.part(leaf, frame * CF(0, 5.6, -th / 2 - 0.04), V3(1.2, 0.5, 0.05), "Metal", { 200, 170, 110 }, { name = "Plate", collide = false })
			Kit.text(plate, "front", spec.number, { color = { 40, 30, 20 }, ppS = 50, maxDist = 30 })
			local reader = Kit.part(door, frame * CF(w / 2 + 0.6, 4.0, -t / 2 - 0.06), V3(0.4, 0.8, 0.08), "SmoothPlastic", { 30, 30, 34 }, { name = "CardReader", collide = false })
			Kit.part(door, frame * CF(w / 2 + 0.6, 4.25, -t / 2 - 0.11), V3(0.2, 0.08, 0.02), "Neon", { 255, 60, 60 }, { name = "ReaderLed", collide = false }):SetAttribute("ReaderLed", true)
			reader:SetAttribute("CardReader", true)
		end
	end

	-- doorbell (outside unit doors)
	if spec.bell then
		local bell = Kit.part(door, frame * CF((if hingeLeft then 1 else -1) * (w / 2 + 0.9), 4.2, -t / 2 - 0.06), V3(0.45, 0.6, 0.1), "SmoothPlastic", { 236, 236, 236 }, { name = "Bell", collide = false })
		Kit.part(door, frame * CF((if hingeLeft then 1 else -1) * (w / 2 + 0.9), 4.25, -t / 2 - 0.12), V3(0.2, 0.2, 0.04), "Neon", { 255, 200, 80 }, { name = "BellLed", collide = false })
		bell:SetAttribute("Doorbell", true)
	end

	-- invisible prompt anchor in the middle of the opening (reachable from both sides)
	Kit.anchor(door, frame * CF(0, math.min(3.6, h / 2), 0), "PromptAt", nil, nil, V3(0.4, 0.4, 0.4))
	-- doors swing through a clear zone where furniture may not be placed
	if spec.blockArc ~= false and kind ~= "auto" and kind ~= "shutter" then
		local blk = Kit.anchor(door, frame * CF(0, 3, 0), "SwingZone", nil, { "GwB_Blocked" }, V3(w + 0.4, 6, w * 2 + 0.4))
		blk.CanQuery = true
	end
	CollectionService:AddTag(door, "GwB_Door")
	door.Parent = parent
	return door
end

-------------------------------------------------------------------------------------------------
-- LIGHTS / SIGNS
-------------------------------------------------------------------------------------------------
-- flat ceiling panel light at world cf (centre of the panel, facing down)
function Core.ceilingLight(parent: Instance, cf: CFrame, opts: any?): (BasePart, Light)
	local o = opts or {}
	local size = o.size or V3(2.4, 0.12, 2.4)
	local panel = Kit.part(parent, cf, size, "Neon", o.color or { 250, 246, 236 }, { name = "LightPanel", collide = false, shadow = false })
	panel.Transparency = 0.1
	panel:SetAttribute("LampOn", panel.Color)
	panel:SetAttribute("LampOff", Color3.fromRGB(200, 200, 196))
	if o.roomId then
		panel:SetAttribute("RoomId", o.roomId)
	end
	if o.unitId then
		panel:SetAttribute("UnitId", o.unitId)
	end
	CollectionService:AddTag(panel, "GwB_Lamp")
	local light = Kit.light(panel, o.kind or "surface", {
		face = "bottom",
		color = o.lightColor or { 255, 238, 214 },
		brightness = o.brightness or 1.1,
		range = o.range or 18,
		angle = 120,
		attrs = { RoomId = o.roomId, UnitId = o.unitId, Group = o.group or "main" },
		tags = o.tags,
	})
	if o.on == false then
		light.Enabled = false
		panel.Material = Enum.Material.SmoothPlastic
		panel.Color = Color3.fromRGB(200, 200, 196)
	end
	if o.flicker then
		CollectionService:AddTag(light, "GwB_Flicker")
	end
	if o.motion then
		CollectionService:AddTag(light, "GwB_MotionLight")
		CollectionService:AddTag(panel, "GwB_MotionLight")
	end
	return panel, light
end

-- small signboard on a wall: cf = world CFrame of the sign centre with -Z facing the reader
function Core.plate(parent: Instance, cf: CFrame, w: number, h: number, text: string, opts: any?): BasePart
	local o = opts or {}
	local p = Kit.part(parent, cf, V3(w, h, o.depth or 0.12), o.mat or "SmoothPlastic", o.bg or { 250, 250, 248 }, { name = o.name or "Plate", collide = false })
	Kit.text(p, "front", text, { color = o.fg or { 40, 40, 44 }, ppS = o.ppS or 40, light = o.light or 0, font = o.font, maxDist = o.maxDist or 60 })
	if o.glow then
		p.Material = Kit.mat("Neon")
		CollectionService:AddTag(p, "GwB_Sign")
	end
	return p
end

-- green 비상구 exit sign
function Core.exitSign(parent: Instance, cf: CFrame)
	local p = Kit.part(parent, cf, V3(1.8, 0.7, 0.2), "Neon", { 30, 170, 80 }, { name = "ExitSign", collide = false })
	Kit.text(p, "front", "🏃 비상구", { color = { 255, 255, 255 }, ppS = 50, maxDist = 60 })
	Kit.text(p, "back", "🏃 비상구", { color = { 255, 255, 255 }, ppS = 50, maxDist = 60 })
end

-------------------------------------------------------------------------------------------------
-- STAIRS (switchback). stair = plan stair; fl = the floor whose flights START here (flights go to the
-- next label in stair.floors). world = rec.cf.
--   landing at v = 0..LD (part of the floor slab), flight A on u < 0 going +v, mid landing at the far
--   end, flight B on u > 0 coming back to the next floor's landing.
-------------------------------------------------------------------------------------------------
function Core.stairFloor(parent: Instance, rec: any, stair: any, idx: number)
	local labels = stair.floors
	local fl = rec.floorByLabel[labels[idx]]
	local nextFl = if labels[idx + 1] then rec.floorByLabel[labels[idx + 1]] else nil
	local isTop = nextFl == nil
	local SW, SL, LD = stair.SW, stair.SL, stair.LD
	local hw = SW / 2
	local fw = (SW - STAIR_GAP) / 2
	local frame = rec.cf * stair.frame * CF(0, fl.y, 0)
	local m = Kit.model(parent, "Stair_" .. fl.label)
	local wallMat, wallCol = F.stairWall.mat, F.stairWall.color
	local stepMat, stepCol = F.stairFloor.mat, F.stairFloor.color
	if stair.style == "wood" then
		stepMat, stepCol = "WoodPlanks", { 150, 110, 76 }
	elseif stair.style == "stone" then
		stepMat, stepCol = "Granite", { 120, 116, 112 }
	end
	local h = fl.h
	local topY = if isTop and stair.roof then fl.h else fl.h
	local wallTop = h - Config.SLAB
	local ext = (if stair.extFn then stair.extFn(fl.label) else stair.exterior) or {}

	-- enclosure walls for this storey (the shell provides walls that are on the facade)
	local doorW = 3.8
	local holes = {}
	if not (stair.noDoor[fl.label]) then
		table.insert(holes, { stair.doorAt - doorW / 2, stair.doorAt + doorW / 2, 0, Config.DOOR_H + 0.2 })
	end
	if not ext.entry then
		Kit.wallX(m, frame, -hw - 0.4, hw + 0.4, -0.2, 0.4, 0, wallTop, holes, wallMat, wallCol)
	end
	if not ext.left then
		Kit.wallZ(m, frame, -0.4, SL + 0.4, -hw - 0.2, 0.4, -Config.SLAB, wallTop, nil, wallMat, wallCol)
	end
	if not ext.right then
		Kit.wallZ(m, frame, -0.4, SL + 0.4, hw + 0.2, 0.4, -Config.SLAB, wallTop, nil, wallMat, wallCol)
	end
	if not ext.far then
		Kit.wallX(m, frame, -hw - 0.4, hw + 0.4, SL + 0.2, 0.4, -Config.SLAB, wallTop, nil, wallMat, wallCol)
	end
	-- landing door (fire door)
	if not stair.noDoor[fl.label] then
		local dk = stair.door
		local lockSpec = nil
		local restricted = stair.private and stair.private[fl.label]
		Core.door(m, frame * CF(stair.doorAt, 0, -0.2) * CFrame.Angles(0, 0, 0), {
			w = doorW - 0.2,
			h = Config.DOOR_H,
			t = 0.4,
			kind = dk,
			hinge = "right",
			lock = lockSpec,
			restricted = restricted,
			autoClose = if dk == "fire" then Config.DOOR_FIRE_CLOSE else nil,
			id = stair.id .. "_" .. fl.label,
		})
	end
	-- floor sign on the landing wall + exit sign over the door
	Core.plate(m, frame * CF(-hw + 1.6, 6.2, 0.08) * CFrame.Angles(0, math.pi, 0), 2.2, 1.4, fl.label, { bg = { 40, 44, 52 }, fg = { 255, 255, 255 }, ppS = 50 })
	if not stair.noDoor[fl.label] then
		Core.exitSign(m, frame * CF(stair.doorAt, Config.DOOR_H + 0.9, 0.16) * CFrame.Angles(0, math.pi, 0))
	end
	-- sensor light over the landing and the mid landing
	Core.ceilingLight(m, frame * CF(0, wallTop - 0.08, LD / 2), { size = V3(1.6, 0.12, 1.6), motion = true, flicker = (rec.wear > 0.5 and rec.rng:chance(0.4)), range = 16, group = "common" })

	if isTop and not stair.roof then
		return m
	end
	local rise = (if isTop then fl.h else fl.h)
	local half = rise / 2
	-- flight A: u in [-hw, -hw + fw], from v = LD (y 0) to v = SL - LD (y half)
	Kit.flight(m, frame, -hw, -hw + fw, LD, SL - LD, 0, half, stepMat, stepCol, { noseColor = F.stairNose })
	-- mid landing
	Kit.box(m, frame, -hw, half - 0.8, SL - LD, hw, half, SL, stepMat, stepCol, { name = "MidLanding" })
	-- flight B: u in [hw - fw, hw], from v = SL - LD (y half) back to v = LD (y rise)
	Kit.flight(m, frame, hw - fw, hw, SL - LD, LD, half, rise, stepMat, stepCol, { noseColor = F.stairNose })
	-- centre wall / balustrade between the flights + handrails
	local gx = 0
	Kit.ramp(m, frame, V3(gx, 0, LD), V3(gx, half, SL - LD), STAIR_GAP - 0.1, { tr = 0, thick = 0.2, collide = false, material = wallMat, color = wallCol, name = "Stringer" })
	Kit.rail(m, frame, V3(-hw + fw - 0.15, 0, LD), V3(-hw + fw - 0.15, half, SL - LD), 3.2, "Metal", { 60, 60, 64 }, { collide = true })
	Kit.rail(m, frame, V3(hw - fw + 0.15, half, SL - LD), V3(hw - fw + 0.15, rise, LD), 3.2, "Metal", { 60, 60, 64 }, { collide = true })
	-- mid landing light + window when the far wall is a facade
	Core.ceilingLight(m, frame * CF(0, half + wallTop - 0.08, SL - LD / 2), { size = V3(1.4, 0.12, 1.4), motion = true, range = 14, group = "common" })
	return m
end

-- the stair tower on the roof (walls, roof slab, the roof door) — part of the SHELL
function Core.roofStairTower(parent: Instance, rec: any, stair: any, style: any)
	local SW, SL = stair.SW, stair.SL
	local hw = SW / 2
	local frame = rec.cf * stair.frame * CF(0, rec.roofY, 0)
	local m = Kit.model(parent, "StairTower")
	local H = 9.6
	local doorW = 3.6
	local LD = stair.LD
	local side = stair.roofDoor or "entry"
	local entryHoles = if side == "entry" then { { stair.doorAt - doorW / 2, stair.doorAt + doorW / 2, 0, Config.DOOR_H + 0.2 } } else nil
	local sideHoles = { { LD / 2 - doorW / 2 + 0.2, LD / 2 + doorW / 2 + 0.2, 0, Config.DOOR_H + 0.2 } }
	Kit.wallX(m, frame, -hw - 0.4, hw + 0.4, -0.2, 0.4, 0, H, entryHoles, style.wall.mat, rec.tone.wall)
	Kit.wallZ(m, frame, -0.4, SL + 0.4, -hw - 0.2, 0.4, 0, H, if side == "left" then sideHoles else nil, style.wall.mat, rec.tone.wall)
	Kit.wallZ(m, frame, -0.4, SL + 0.4, hw + 0.2, 0.4, 0, H, if side == "right" then sideHoles else nil, style.wall.mat, rec.tone.wall)
	Kit.wallX(m, frame, -hw - 0.4, hw + 0.4, SL + 0.2, 0.4, 0, H, nil, style.wall.mat, rec.tone.wall)
	Kit.box(m, frame, -hw - 0.6, H, -0.6, hw + 0.6, H + 0.8, SL + 0.6, "Concrete", style.roof.color, { name = "TowerRoof" })
	local dcf
	if side == "entry" then
		dcf = frame * CF(stair.doorAt, 0, -0.2)
	elseif side == "right" then
		dcf = frame * CF(hw + 0.2, 0, LD / 2 + 0.2) * CFrame.Angles(0, rad(-90), 0)
	else
		dcf = frame * CF(-hw - 0.2, 0, LD / 2 + 0.2) * CFrame.Angles(0, rad(90), 0)
	end
	Core.door(m, dcf, { w = doorW - 0.2, h = Config.DOOR_H, t = 0.4, kind = "fire", hinge = "right", autoClose = Config.DOOR_FIRE_CLOSE, id = stair.id .. "_RF" })
	Core.plate(m, dcf * CF(0, Config.DOOR_H + 1.0, -0.45), 2.6, 0.8, "옥상 출입문", { bg = { 40, 120, 60 }, fg = { 255, 255, 255 } })
	Core.ceilingLight(m, frame * CF(0, H - 0.1, SL / 2), { size = V3(1.6, 0.12, 1.6), motion = true, group = "common" })
	return m
end

-------------------------------------------------------------------------------------------------
-- ELEVATOR (built once per elevator, spanning all its stops). Returns the elevator Model.
-------------------------------------------------------------------------------------------------
local function displayGui(part: BasePart, face: string, big: boolean)
	local g = Instance.new("SurfaceGui")
	g.Name = "Display"
	g.Face = Enum.NormalId[face]
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 60
	g.LightInfluence = 0
	g.MaxDistance = 80
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(0.36, 1)
	arrow.Text = ""
	arrow.TextScaled = true
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextColor3 = Color3.fromRGB(255, 120, 40)
	arrow.Parent = bg
	local num = Instance.new("TextLabel")
	num.Name = "Floor"
	num.BackgroundTransparency = 1
	num.Position = UDim2.fromScale(0.34, 0)
	num.Size = UDim2.fromScale(0.64, 1)
	num.Text = "1"
	num.TextScaled = true
	num.Font = Enum.Font.GothamBlack
	num.TextColor3 = Color3.fromRGB(255, 120, 40)
	num.Parent = bg
	g.Parent = part
	CollectionService:AddTag(part, "GwB_ElevDisplay")
	return g
end

local function shortLabel(label: string): string
	-- "12F" -> "12", "B1" -> "B1", "RF" -> "R"
	local n = string.match(label, "^(%d+)F$")
	return n or label
end
Core.shortLabel = shortLabel

function Core.elevator(parent: Instance, rec: any, e: any): Model
	local EW, ED, cw, cd = e.EW, e.ED, e.cw, e.cd
	local hw = EW / 2
	local base = rec.cf * e.frame
	local stops = e.stops
	local yBottom = stops[1].y - 2.4 -- pit
	local top = stops[#stops]
	local yTop = top.y + top.fl.h + 3.0 -- overrun into the machine room on the roof
	local m = Kit.model(parent, "Elevator_" .. e.id)
	local shaft = Kit.model(m, "Shaft")
	local wallMat, wallCol = "Concrete", { 170, 170, 168 }
	-- shaft walls (side, back); the front wall is built per stop with the hall door opening
	Kit.box(shaft, base, -hw - 0.4, yBottom, 0, -hw, yTop, ED + 0.4, wallMat, wallCol, { name = "ShaftWall" })
	Kit.box(shaft, base, hw, yBottom, 0, hw + 0.4, yTop, ED + 0.4, wallMat, wallCol, { name = "ShaftWall" })
	Kit.box(shaft, base, -hw, yBottom, ED, hw, yTop, ED + 0.4, wallMat, wallCol, { name = "ShaftWall" })
	Kit.box(shaft, base, -hw, yBottom - 0.6, 0, hw, yBottom, ED, wallMat, { 90, 90, 90 }, { name = "Pit" })
	-- guide rails (visible when looking down the shaft through open doors)
	for _, sx in { -hw + 0.3, hw - 0.3 } do
		Kit.box(shaft, base, sx - 0.12, yBottom, ED / 2 - 0.15, sx + 0.12, yTop, ED / 2 + 0.15, "Metal", { 90, 90, 94 }, { collide = false, name = "GuideRail" })
	end
	-- counterweight cable look
	Kit.box(shaft, base, -0.05, yBottom + 4, ED - 0.6, 0.05, yTop, ED - 0.5, "Metal", { 40, 40, 40 }, { collide = false, name = "Cable" })

	-- stops: front wall with the hall door opening, hall doors, buttons, displays
	local doorW, doorH = 4.4, 7.6
	local stopLabels, stopYs = {}, {}
	for i, st in stops do
		local fl = st.fl
		local sf = base * CF(0, st.y, 0)
		local sm = Kit.model(m, "Stop_" .. i)
		sm:SetAttribute("Stop", i)
		sm:SetAttribute("Label", st.label)
		local wallTop = fl.h - Config.SLAB
		-- front wall (v = -0.4 .. 0) with the opening
		Kit.wallX(sm, sf, -hw - 0.4, hw + 0.4, -0.2, 0.4, -Config.SLAB, wallTop, { { -doorW / 2, doorW / 2, 0, doorH } }, "Metal", { 196, 198, 202 }, { name = "HallWall" })
		-- stainless door frame
		Kit.box(sm, sf, -doorW / 2 - 0.35, 0, -0.55, -doorW / 2, doorH + 0.35, -0.35, "Metal", { 210, 212, 216 }, { name = "Frame", collide = false })
		Kit.box(sm, sf, doorW / 2, 0, -0.55, doorW / 2 + 0.35, doorH + 0.35, -0.35, "Metal", { 210, 212, 216 }, { name = "Frame", collide = false })
		Kit.box(sm, sf, -doorW / 2 - 0.35, doorH, -0.55, doorW / 2 + 0.35, doorH + 0.35, -0.35, "Metal", { 210, 212, 216 }, { name = "Frame", collide = false })
		Kit.box(sm, sf, -doorW / 2, -0.02, -0.5, doorW / 2, 0.02, 0.05, "Metal", { 160, 162, 166 }, { name = "Sill" })
		-- hall door leaves (centre opening, inside the shaft side of the wall)
		for li, sgn in { -1, 1 } do
			local leaf = Kit.model(sm, "HallLeaf" .. li)
			local p = Kit.part(leaf, sf * CF(sgn * doorW / 4, doorH / 2, 0.1), V3(doorW / 2 + 0.06, doorH, 0.14), "Metal", { 186, 188, 192 }, { name = "Panel" })
			leaf.PrimaryPart = p
			leaf:SetAttribute("SlideX", sgn * (doorW / 2 - 0.05))
		end
		-- hall lantern / position indicator above the door
		local disp = Kit.part(sm, sf * CF(0, doorH + 1.2, -0.48), V3(2.4, 0.9, 0.1), "SmoothPlastic", { 10, 10, 12 }, { name = "HallDisplay", collide = false })
		disp:SetAttribute("ElevatorId", e.id)
		disp:SetAttribute("Where", "hall")
		disp:SetAttribute("Stop", i)
		displayGui(disp, "Front", false)
		-- call buttons (right of the door, seen from the hall)
		local panel = Kit.part(sm, sf * CF(-doorW / 2 - 1.6, 3.9, -0.46), V3(0.9, 1.6, 0.08), "Metal", { 200, 202, 206 }, { name = "CallPanel", collide = false })
		local function btn(dir: string, y: number)
			local b = Kit.part(sm, sf * CF(-doorW / 2 - 1.6, y, -0.52), V3(0.5, 0.5, 0.06), "SmoothPlastic", { 230, 230, 232 }, { name = "Call_" .. dir, collide = false })
			Kit.text(b, "front", if dir == "up" then "▲" else "▼", { color = { 60, 60, 64 }, ppS = 60, light = 0.5, maxDist = 30 })
			b:SetAttribute("ElevatorId", e.id)
			b:SetAttribute("Where", "hall")
			b:SetAttribute("Stop", i)
			b:SetAttribute("Dir", dir)
			CollectionService:AddTag(b, "GwB_ElevButton")
		end
		if i < #stops then
			btn("up", 4.3)
		end
		if i > 1 then
			btn("down", 3.5)
		end
		panel:SetAttribute("ElevatorId", e.id)
		-- floor number on the wall + chime emitter
		Core.plate(sm, sf * CF(doorW / 2 + 1.9, 5.2, -0.48), 1.6, 1.6, shortLabel(st.label), { bg = { 40, 44, 52 }, fg = { 255, 255, 255 }, ppS = 50 })
		Kit.sound(disp, "elevator_ding", { volume = 0.6, maxDist = 40, loop = false, attrs = { Trigger = "ding", Stop = i } })
		table.insert(stopLabels, st.label)
		table.insert(stopYs, string.format("%.3f", (rec.cf * CF(0, st.y, 0)).Y))
	end
	-- machine room box on the roof (visual)
	local mr = Kit.model(m, "MachineRoom")
	Kit.box(mr, base, -hw - 0.4, yTop, -0.4, hw + 0.4, yTop + 4.5, ED + 0.4, "Concrete", rec.style.roof.color, { name = "MachineRoom" })

	-- the CAR (anchored; moved by the clients every frame and by the server at stops)
	local car = Kit.model(m, "Car")
	local home = 1
	for i, st in stops do
		if st.label == e.home then
			home = i
		end
	end
	local cf0 = base * CF(0, stops[home].y, 0)
	local cx0, cx1 = -cw / 2, cw / 2
	local cz0, cz1 = 0.6, 0.6 + cd
	local floorP = Kit.box(car, cf0, cx0 - 0.2, -0.4, cz0 - 0.55, cx1 + 0.2, 0, cz1 + 0.2, "Marble", { 60, 58, 60 }, { name = "CarFloor" })
	car.PrimaryPart = floorP
	local CARH = Config.ELEV_CAR_H
	local steel = { 200, 202, 206 }
	Kit.box(car, cf0, cx0 - 0.3, 0, cz0, cx0, CARH, cz1, "Metal", steel, { name = "CarWall" })
	Kit.box(car, cf0, cx1, 0, cz0, cx1 + 0.3, CARH, cz1, "Metal", steel, { name = "CarWall" })
	Kit.box(car, cf0, cx0, 0, cz1, cx1, CARH, cz1 + 0.3, "Metal", steel, { name = "CarWall" })
	Kit.box(car, cf0, cx0 + 1.4, 3.0, cz1 - 0.05, cx1 - 1.4, 7.6, cz1, "Glass", { 220, 226, 232 }, { name = "Mirror", refl = 0.55, collide = false })
	Kit.box(car, cf0, cx0 - 0.3, CARH, cz0 - 0.4, cx1 + 0.3, CARH + 0.4, cz1 + 0.3, "Metal", { 230, 230, 232 }, { name = "CarRoof" })
	-- front wall pieces beside the car door
	Kit.box(car, cf0, cx0, 0, cz0 - 0.4, -doorW / 2, CARH, cz0, "Metal", steel, { name = "CarFront" })
	Kit.box(car, cf0, doorW / 2, 0, cz0 - 0.4, cx1, CARH, cz0, "Metal", steel, { name = "CarFront" })
	Kit.box(car, cf0, -doorW / 2, doorH, cz0 - 0.4, doorW / 2, CARH, cz0, "Metal", steel, { name = "CarFront" })
	-- handrail
	Kit.box(car, cf0, cx0 + 0.3, 3.0, cz1 - 0.35, cx1 - 0.3, 3.15, cz1 - 0.2, "Metal", { 230, 230, 232 }, { collide = false, name = "Handrail" })
	-- ceiling light
	local lp = Kit.box(car, cf0, cx0 + 0.8, CARH - 0.15, cz0 + 0.8, cx1 - 0.8, CARH - 0.05, cz1 - 0.8, "Neon", { 250, 248, 240 }, { collide = false, name = "CarLight" })
	Kit.light(lp, "surface", { face = "bottom", color = { 255, 246, 230 }, brightness = 1.3, range = 12, angle = 140, attrs = { Group = "elevator" } })
	-- car door leaves
	for li, sgn in { -1, 1 } do
		local leaf = Kit.model(car, "CarLeaf" .. li)
		local p = Kit.part(leaf, cf0 * CF(sgn * doorW / 4, doorH / 2, cz0 - 0.2), V3(doorW / 2 + 0.06, doorH, 0.12), "Metal", { 206, 208, 212 }, { name = "Panel" })
		leaf.PrimaryPart = p
		leaf:SetAttribute("SlideX", sgn * (doorW / 2 - 0.05))
	end
	-- control panel (COP) on the right of the door, inside
	local copX = cx1 - 0.18
	local cop = Kit.part(car, cf0 * CF(copX, 4.2, cz0 + 1.0) * CFrame.Angles(0, math.pi / 2, 0), V3(1.3, 4.0, 0.08), "Metal", { 170, 172, 176 }, { name = "COP", collide = false })
	cop:SetAttribute("ElevatorId", e.id)
	cop:SetAttribute("Where", "car")
	local n = #stops
	local cols = if n > 8 then 2 else 1
	local rows = math.ceil(n / cols)
	for i, st in stops do
		local col = if cols == 2 then ((i - 1) // rows) else 0
		local row = (i - 1) % rows
		local by = 2.6 + row * (3.0 / math.max(rows, 1))
		local bz = cz0 + 0.75 + col * 0.55
		local b = Kit.part(car, cf0 * CF(copX - 0.06, by, bz) * CFrame.Angles(0, math.pi / 2, 0), V3(0.36, 0.3, 0.05), "SmoothPlastic", { 236, 236, 238 }, { name = "CarBtn_" .. i, collide = false })
		Kit.text(b, "front", shortLabel(st.label), { color = { 40, 40, 44 }, ppS = 80, light = 0.4, maxDist = 20 })
		b:SetAttribute("ElevatorId", e.id)
		b:SetAttribute("Where", "car")
		b:SetAttribute("Stop", i)
		CollectionService:AddTag(b, "GwB_ElevButton")
	end
	-- open / close / alarm
	for k, act in { "open", "close", "alarm" } do
		local b = Kit.part(car, cf0 * CF(copX - 0.06, 2.1, cz0 + 0.55 + (k - 1) * 0.42) * CFrame.Angles(0, math.pi / 2, 0), V3(0.34, 0.34, 0.05), "SmoothPlastic", if act == "alarm" then { 250, 210, 40 } else { 236, 236, 238 }, { name = "CarBtn_" .. act, collide = false })
		Kit.text(b, "front", if act == "open" then "◀▶" elseif act == "close" then "▶◀" else "🔔", { color = { 40, 40, 44 }, ppS = 80, light = 0.4, maxDist = 20 })
		b:SetAttribute("ElevatorId", e.id)
		b:SetAttribute("Where", "car")
		b:SetAttribute("Action", act)
		CollectionService:AddTag(b, "GwB_ElevButton")
	end
	-- car position display over the door (inside)
	local cd2 = Kit.part(car, cf0 * CF(0, doorH + 0.5, cz0 + 0.02), V3(1.8, 0.7, 0.06), "SmoothPlastic", { 10, 10, 12 }, { name = "CarDisplay", collide = false })
	cd2:SetAttribute("ElevatorId", e.id)
	cd2:SetAttribute("Where", "car")
	displayGui(cd2, "Back", false)
	-- 관리사무소 notice board (very Korean detail)
	local notice = Kit.part(car, cf0 * CF(cx0 + 0.18, 5.2, cz0 + cd / 2) * CFrame.Angles(0, -math.pi / 2, 0), V3(2.4, 3.0, 0.06), "SmoothPlastic", { 250, 250, 246 }, { name = "Notice", collide = false })
	Kit.text(notice, "front", "📢 관리사무소 알림\n\n승강기 정기점검\n매월 둘째 주 화요일\n\n" .. rec.name, { color = { 40, 40, 44 }, ppS = 40, light = 0.6, bold = false, maxDist = 20 })
	-- motor hum + anchor for sounds
	Kit.sound(lp, "elevator_hum", { volume = 0.25, maxDist = 24, attrs = { Active = false } })
	Kit.sound(lp, "elevator_ding", { volume = 0.5, maxDist = 24, loop = false, attrs = { Trigger = "ding" } })
	car:SetAttribute("Home", home)
	pcall(function()
		(car :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)

	-- contract attributes
	m:SetAttribute("ElevatorId", e.id)
	m:SetAttribute("Name", e.name)
	m:SetAttribute("Stops", table.concat(stopLabels, "|"))
	m:SetAttribute("StopY", table.concat(stopYs, "|"))
	m:SetAttribute("Home", home)
	m:SetAttribute("Pos", home)
	m:SetAttribute("Moving", false)
	m:SetAttribute("Door", "closed")
	m:SetAttribute("Dir", "")
	m:SetAttribute("Calls", "")
	m:SetAttribute("HallUp", "")
	m:SetAttribute("HallDown", "")
	m:SetAttribute("BaseCF", base)
	m:SetAttribute("DoorW", doorW)
	local restricted = {}
	for label, unitId in e.restricted do
		for i, st in stops do
			if st.label == label then
				table.insert(restricted, i .. "=" .. unitId)
			end
		end
	end
	m:SetAttribute("Restricted", table.concat(restricted, ","))
	m:SetAttribute("CarOffset", 0)
	CollectionService:AddTag(m, "GwB_Elevator")
	return m
end

-------------------------------------------------------------------------------------------------
-- RESTROOM (public: lobbies, 상가 floors). frame: world CFrame of the room's entrance corner,
-- room = u 0..w, v 0..d, door on v = 0 at u = doorU. gender = "m" | "f" | "u".
-------------------------------------------------------------------------------------------------
function Core.restroom(parent: Instance, frame: CFrame, w: number, d: number, h: number, gender: string, opts: any?)
	local o = opts or {}
	local m = Kit.model(parent, "Restroom_" .. gender)
	local tile, floorT = F.toiletTile, F.toiletFloor
	Kit.box(m, frame, 0, 0, 0, w, 0.05, d, floorT.mat, floorT.color, { collide = false, name = "FloorTile" })
	-- wall tiles on the 3 inner faces (the walls themselves come from the floor builder)
	Kit.box(m, frame, 0.25, 0.05, d - 0.3, w - 0.25, h - 0.2, d - 0.22, tile.mat, tile.color, { collide = false, name = "TileWall" })
	Kit.box(m, frame, 0.22, 0.05, 0.25, 0.3, h - 0.2, d - 0.25, tile.mat, tile.color, { collide = false, name = "TileWall" })
	Kit.box(m, frame, w - 0.3, 0.05, 0.25, w - 0.22, h - 0.2, d - 0.25, tile.mat, tile.color, { collide = false, name = "TileWall" })
	Kit.box(m, frame, 0, h - 0.15, 0, w, h - 0.05, d, F.ceiling.mat, F.ceiling.color, { collide = false, name = "Ceiling" })
	Core.ceilingLight(m, frame * CF(w / 2, h - 0.2, d / 2), { size = V3(3, 0.12, 1.2), group = "common", flicker = o.flicker })
	-- stalls along the far wall
	local stallW = 3.4
	local nStalls = math.max(1, math.floor((w - 1) / stallW))
	if gender == "m" then
		nStalls = math.max(1, nStalls - 1)
	end
	local stallD = 4.6
	for i = 1, nStalls do
		local x0 = 0.3 + (i - 1) * stallW
		local x1 = x0 + stallW
		Kit.box(m, frame, x1 - 0.06, 0.4, d - stallD, x1 + 0.06, 7, d - 0.3, "SmoothPlastic", { 214, 216, 220 }, { name = "Partition" })
		if i == 1 then
			Kit.box(m, frame, x0 - 0.06, 0.4, d - stallD, x0 + 0.06, 7, d - 0.3, "SmoothPlastic", { 214, 216, 220 }, { name = "Partition" })
		end
		-- front panel with the stall door
		local dw = 2.6
		Kit.wallX(m, frame, x0, x1, d - stallD, 0.1, 0.4, 7, { { x0 + (stallW - dw) / 2, x0 + (stallW + dw) / 2, 0, 7 } }, "SmoothPlastic", { 214, 216, 220 })
		Core.door(m, frame * CF(x0 + stallW / 2, 0, d - stallD) * CFrame.Angles(0, 0, 0), {
			w = dw,
			h = 7,
			t = 0.1,
			kind = "stall",
			lock = "stall",
			hinge = "left",
			casing = false,
			blockArc = false,
			swing = "back",
			id = (o.id or "wc") .. "_" .. gender .. i,
		})
		local toilet = Furniture.build("toilet", m, frame * CF(x0 + stallW / 2, 0, d - 1.8), 1, { Public = true })
		if toilet then
			Kit.sound(toilet.PrimaryPart :: BasePart, "toilet_flush", { volume = 0.6, maxDist = 30, loop = false, attrs = { Trigger = "use" } })
		end
	end
	if gender == "m" then
		-- urinals along the right wall
		for i = 0, 1 do
			Furniture.build("urinal", m, frame * CF(w - 0.9, 0, 3.0 + i * 2.4) * CFrame.Angles(0, math.rad(90), 0), 1, { Public = true })
		end
	end
	-- sinks + mirror + dryer on the left wall near the door
	local sinks = math.max(1, math.floor((d - stallD - 1) / 3))
	for i = 1, sinks do
		Furniture.build("washbasin", m, frame * CF(0.9, 0, 1.6 + (i - 1) * 3) * CFrame.Angles(0, math.rad(-90), 0), 1, { Public = true })
	end
	Furniture.build("hand_dryer", m, frame * CF(0.5, 0, 1.6 + sinks * 3) * CFrame.Angles(0, math.rad(-90), 0), 1, { Public = true })
	Kit.sound(Kit.anchor(m, frame * CF(w / 2, h - 0.6, d / 2), "Vent"), "vent_fan", { volume = 0.18, maxDist = 18 })
	return m
end

-------------------------------------------------------------------------------------------------
-- PARKING (B1 / 필로티). area = local rect in the floor frame; stalls along both long sides.
-------------------------------------------------------------------------------------------------
function Core.parking(parent: Instance, frame: CFrame, x0: number, z0: number, x1: number, z1: number, h: number, rng: any, opts: any?)
	local o = opts or {}
	local m = Kit.model(parent, "Parking")
	local floorF = F.parkingFloor
	Kit.box(m, frame, x0, 0, z0, x1, 0.05, z1, floorF.mat, floorF.color, { collide = false, name = "Epoxy" })
	-- drive aisle down the middle (lighter), stall lines
	local midZ = (z0 + z1) / 2
	Kit.box(m, frame, x0, 0.05, midZ - 6, x1, 0.07, midZ + 6, "SmoothPlastic", { 128, 146, 134 }, { collide = false, name = "Aisle" })
	local stallW = 5.6
	local stallD = 10
	local n = math.floor((x1 - x0 - 2) / stallW)
	local CARS = { { 236, 236, 236 }, { 30, 30, 32 }, { 140, 144, 150 }, { 40, 70, 130 }, { 150, 30, 40 }, { 220, 220, 214 } }
	local stall = 0
	for side = -1, 1, 2 do
		local zA = if side < 0 then z0 + 0.5 else z1 - 0.5 - stallD
		for i = 0, n - 1 do
			local sx = x0 + 1 + i * stallW
			Kit.box(m, frame, sx - 0.08, 0.06, zA, sx + 0.08, 0.08, zA + stallD, "SmoothPlastic", { 250, 250, 246 }, { collide = false, name = "Line" })
			stall += 1
			local spot = Kit.anchor(m, frame * CF(sx + stallW / 2, 0.1, zA + stallD / 2) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0), "Stall_" .. stall, { Stall = stall }, { "GwB_Parking" }, V3(stallW - 0.4, 0.2, stallD - 0.4))
			spot.CanQuery = false
			-- parked cars (simple bodies) in some stalls
			if o.cars ~= false and rng:chance(o.carChance or 0.45) then
				local c = rng:pick(CARS)
				local ccf = frame * CF(sx + stallW / 2, 0, zA + stallD / 2) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0)
				Kit.part(m, ccf * CF(0, 1.5, 0), V3(4.2, 1.6, 8.6), "SmoothPlastic", c, { name = "CarBody" })
				Kit.part(m, ccf * CF(0, 2.9, 0.4), V3(3.8, 1.3, 4.4), "Glass", { 40, 50, 60 }, { name = "CarCabin", tr = 0.2 })
				for _, wx in { -2.05, 2.05 } do
					for _, wz in { -2.8, 2.8 } do
						Kit.part(m, ccf * CF(wx, 0.75, wz) * CFrame.Angles(0, 0, 0), V3(0.5, 1.5, 1.5), "SmoothPlastic", { 20, 20, 20 }, { shape = "cyl", collide = false, name = "Wheel" })
					end
				end
			end
		end
		local sx = x0 + 1 + n * stallW
		Kit.box(m, frame, sx - 0.08, 0.06, zA, sx + 0.08, 0.08, zA + stallD, "SmoothPlastic", { 250, 250, 246 }, { collide = false, name = "Line" })
	end
	-- columns
	local colStep = stallW * 3
	local cx = x0 + 1 + colStep
	while cx < x1 - 2 do
		for _, cz in { z0 + stallD + 1.2, z1 - stallD - 1.2 } do
			local col = Kit.box(m, frame, cx - 0.9, 0, cz - 0.9, cx + 0.9, h - Config.SLAB, cz + 0.9, "Concrete", { 196, 194, 188 }, { name = "Column" })
			Kit.box(m, frame, cx - 0.92, 0, cz - 0.92, cx + 0.92, 2.2, cz + 0.92, "SmoothPlastic", { 236, 196, 40 }, { collide = false, name = "ColumnGuard" })
			col:SetAttribute("Column", true)
		end
		cx += colStep
	end
	-- fluorescent tube lines (some flicker in old buildings)
	local lx = x0 + 4
	while lx < x1 - 2 do
		for _, lz in { midZ - 4, midZ + 4 } do
			local tube = Kit.box(m, frame, lx - 2, h - Config.SLAB - 0.25, lz - 0.2, lx + 2, h - Config.SLAB - 0.1, lz + 0.2, "Neon", { 236, 246, 250 }, { collide = false, name = "Tube" })
			tube:SetAttribute("LampOn", tube.Color)
			CollectionService:AddTag(tube, "GwB_Lamp")
			local l = Kit.light(tube, "surface", { face = "bottom", color = { 230, 244, 255 }, brightness = 1.0, range = 20, angle = 150, attrs = { Group = "common" } })
			if rng:chance(o.flicker or 0.08) then
				CollectionService:AddTag(l, "GwB_Flicker")
			end
		end
		lx += 14
	end
	Kit.sound(Kit.anchor(m, frame * CF((x0 + x1) / 2, h - 2, midZ), "Hum"), "fluorescent", { volume = 0.15, maxDist = 60 })
	Kit.sound(Kit.anchor(m, frame * CF(x0 + 3, h - 2, midZ), "Fan"), "vent_fan", { volume = 0.2, maxDist = 40 })
	return m
end

-------------------------------------------------------------------------------------------------
-- ROOF EQUIPMENT (shell): water tank, outdoor AC units, antenna, solar panels
-------------------------------------------------------------------------------------------------
function Core.roofStuff(parent: Instance, frame: CFrame, x0: number, z0: number, x1: number, z1: number, rng: any, kind: string, wear: number)
	local m = Kit.model(parent, "RoofStuff")
	local function free(): (number, number)
		return rng:range(x0 + 3, x1 - 3), rng:range(z0 + 3, z1 - 3)
	end
	-- water tank (FRP panel tank, blue-ish or white)
	if kind ~= "minimal" then
		local tx, tz = free()
		local tc = if rng:chance(0.5) then { 70, 130, 190 } else { 220, 222, 218 }
		Kit.box(m, frame, tx - 3, 0, tz - 2.5, tx + 3, 0.6, tz + 2.5, "Concrete", { 150, 150, 148 }, { name = "TankBase" })
		Kit.box(m, frame, tx - 2.8, 0.6, tz - 2.3, tx + 2.8, 5.0, tz + 2.3, "SmoothPlastic", Util.age(Kit.col(tc), wear), { name = "WaterTank" })
		for k = -2, 2 do
			Kit.box(m, frame, tx + k * 1.1 - 0.05, 0.6, tz - 2.35, tx + k * 1.1 + 0.05, 5.0, tz - 2.3, "SmoothPlastic", Util.age(Kit.col(tc), wear + 0.2), { collide = false, name = "TankRib" })
		end
	end
	-- outdoor AC condensers
	local nAc = rng:int(2, 6)
	for _ = 1, nAc do
		local ax, az = free()
		Kit.box(m, frame, ax - 1.4, 0, az - 0.7, ax + 1.4, 2.4, az + 0.7, "SmoothPlastic", Util.age(Color3.fromRGB(226, 226, 222), wear), { name = "AcUnit" })
		local fan = Kit.rod(m, frame, V3(ax - 0.5, 1.2, az - 0.72), V3(ax - 0.5, 1.2, az - 0.76), 1.3, "SmoothPlastic", { 60, 60, 62 }, { collide = false, name = "AcFan" })
		fan:SetAttribute("Rpm", 120)
		fan:SetAttribute("Axis", "X")
		CollectionService:AddTag(fan, "GwB_Spin")
	end
	-- antenna / satellite dish
	if rng:chance(0.7) then
		local ax, az = free()
		Kit.rod(m, frame, V3(ax, 0, az), V3(ax, 9, az), 0.2, "Metal", { 150, 150, 154 }, { collide = false })
		for k = 1, 3 do
			Kit.rod(m, frame, V3(ax - 1.2, 6 + k, az), V3(ax + 1.2, 6 + k, az), 0.1, "Metal", { 150, 150, 154 }, { collide = false })
		end
	end
	if kind == "modern" then
		-- solar panels
		for k = 0, 2 do
			local sx = x0 + 4 + k * 5
			if sx < x1 - 4 then
				Kit.part(m, frame * CF(sx, 1.4, z1 - 5) * CFrame.Angles(rad(-25), 0, 0), V3(4.4, 0.15, 3), "Glass", { 20, 40, 80 }, { name = "Solar", refl = 0.3 })
			end
		end
	end
	return m
end

return Core
