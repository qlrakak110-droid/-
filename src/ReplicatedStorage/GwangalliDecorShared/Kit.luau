--!strict
-- GwangalliDecorShared/Kit: the little modelling language the catalog items are written in.
-- An item's build(k, W, H, D) adds parts to a spec in the item's own frame:
--   origin = bottom centre of the piece, +X right, +Y up, front = -Z (a wall piece's back is +Z).
-- Paints: a colour slot key of the item ("fabric", "frame", "light" ...) follows the player's colour and
-- material choice; k:lit(rgb, mat) is a fixed paint; k:sh(slot, f) / k:mx(slot, rgb, t) are derived
-- from a slot (they follow the colour, keep the slot's material).
-- Part flags (opts): rx ry rz (degrees), solid (collides + collision box), top (others can stand on
-- it), t (transparency), rf (reflectance), glow (light-coloured Neon), screen (TV picture), cast
-- (shadow; default = solid), name tags for interactions.
-- Interaction markers: k:light, k:seat, k:bed, k:hinge / k:slide (open pose), k:tank, k:fire,
-- k:speaker, k:screenAt. Spec = { parts, lights, seats, screen?, tank?, fire?, speaker?, hasPose }.

local Palette = require(script.Parent:WaitForChild("Palette"))

local Kit = {}
Kit.__index = Kit

export type Paint = { rgb: { number }, mat: string, slot: string? }

local rad = math.rad

local function paintOf(self: any, p: any): Paint
	if type(p) == "string" then
		local s = self.c[p]
		if s then
			return { rgb = s.rgb, mat = s.mat, slot = p }
		end
		local sw = Palette.BY_KEY[p]
		if sw then
			return { rgb = sw.rgb, mat = "plastic" }
		end
		return { rgb = { 200, 200, 200 }, mat = "plastic" }
	elseif type(p) == "table" then
		if p.rgb then
			return p :: Paint
		end
		return { rgb = p, mat = "plastic" }
	end
	return { rgb = { 200, 200, 200 }, mat = "plastic" }
end

-- c: resolved colour slots { [key] = { rgb, mat } }, st: item state (on / op / ch ...)
function Kit.new(c: { [string]: any }, st: { [string]: any }?): any
	local self = setmetatable({}, Kit)
	self.c = c
	self.st = st or {}
	self.parts = {}
	self.lights = {}
	self.seats = {}
	self.hasPose = false
	return self
end

-- fixed paint
function Kit:lit(rgb: { number }, mat: string?): Paint
	return { rgb = rgb, mat = mat or "plastic" }
end

-- slot colour scaled by f (keeps the slot material)
function Kit:sh(slot: string, f: number, mat: string?): Paint
	local p = paintOf(self, slot)
	return { rgb = Palette.shade(p.rgb, f), mat = mat or p.mat, slot = p.slot }
end

-- slot colour mixed towards rgb by t
function Kit:mx(slot: string, rgb: { number }, t: number, mat: string?): Paint
	local p = paintOf(self, slot)
	return { rgb = Palette.mix(p.rgb, rgb, t), mat = mat or p.mat, slot = p.slot }
end

-- the slot's colour with another material (a leather sofa's piping in metal ...)
function Kit:as(slot: string, mat: string): Paint
	local p = paintOf(self, slot)
	return { rgb = p.rgb, mat = mat, slot = p.slot }
end

function Kit:rgb(slot: string): { number }
	return paintOf(self, slot).rgb
end

function Kit:matOf(slot: string): string
	return paintOf(self, slot).mat
end

local function addPart(self: any, name: string, shape: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, paint: any, o: any?): number
	local p = paintOf(self, paint)
	local cf = CFrame.new(x, y, z)
	if o and (o.rx or o.ry or o.rz) then
		cf *= CFrame.Angles(rad(o.rx or 0), rad(o.ry or 0), rad(o.rz or 0))
	end
	if o and o.cf then
		cf = o.cf
	end
	local mdef = (Palette.MATERIALS :: any)[p.mat]
	local rec: any = {
		n = name,
		shape = shape,
		size = Vector3.new(math.max(0.05, sx), math.max(0.05, sy), math.max(0.05, sz)),
		cf = cf,
		rgb = p.rgb,
		mat = p.mat,
		slot = p.slot,
		t = if o and o.t then o.t elseif mdef and mdef.transparency then mdef.transparency else 0,
		rf = if o and o.rf then o.rf elseif mdef and mdef.reflect then mdef.reflect else 0,
		solid = o ~= nil and o.solid == true,
		top = o ~= nil and o.top == true,
		glow = o ~= nil and o.glow == true,
		screen = o ~= nil and o.screen == true,
		cast = if o and o.cast ~= nil then o.cast else (o ~= nil and o.solid == true),
	}
	if rec.glow then
		rec.mat = "neon"
	end
	table.insert(self.parts, rec)
	return #self.parts
end

-- box: size sx sy sz, centre x y z
function Kit:box(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, paint: any, o: any?): number
	return addPart(self, name, "Block", sx, sy, sz, x, y, z, paint, o)
end

-- cylinder of length l and diameter dia along axis "x" | "y" | "z"
function Kit:cyl(name: string, l: number, dia: number, x: number, y: number, z: number, axis: string, paint: any, o: any?): number
	local oo: any = {}
	if o then
		for k2, v in o do
			oo[k2] = v
		end
	end
	local base = CFrame.new(x, y, z)
	if axis == "y" then
		base *= CFrame.Angles(0, 0, rad(90))
	elseif axis == "z" then
		base *= CFrame.Angles(0, rad(90), 0)
	end
	if oo.rx or oo.ry or oo.rz then
		-- tilt applied in the item frame around the cylinder centre
		base = CFrame.new(x, y, z) * CFrame.Angles(rad(oo.rx or 0), rad(oo.ry or 0), rad(oo.rz or 0)) * (CFrame.new(x, y, z):Inverse() * base)
		oo.rx, oo.ry, oo.rz = nil, nil, nil
	end
	oo.cf = base
	return addPart(self, name, "Cylinder", l, dia, dia, x, y, z, paint, oo)
end

function Kit:ball(name: string, dia: number, x: number, y: number, z: number, paint: any, o: any?): number
	return addPart(self, name, "Ball", dia, dia, dia, x, y, z, paint, o)
end

-- part placed by an explicit CFrame
function Kit:boxAt(name: string, sx: number, sy: number, sz: number, cf: CFrame, paint: any, o: any?): number
	local oo: any = { cf = cf }
	if o then
		for k2, v in o do
			oo[k2] = v
		end
		oo.cf = cf
	end
	return addPart(self, name, "Block", sx, sy, sz, 0, 0, 0, paint, oo)
end

-- flat ellipse-ish disc (cylinder along Y) of thickness h
function Kit:disc(name: string, h: number, dia: number, x: number, y: number, z: number, paint: any, o: any?): number
	return self:cyl(name, h, dia, x, y, z, "y", paint, o)
end

-------------------------------------------------------------------------------------------------
-- Composite helpers
-------------------------------------------------------------------------------------------------
-- four legs under a W x D top whose underside is at height h (from y0)
function Kit:legs(W: number, D: number, h: number, inset: number, thick: number, paint: any, round: boolean?, y0: number?)
	local base = y0 or 0
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (W / 2 - inset), sz * (D / 2 - inset)
			if round then
				self:cyl("Leg", h, thick, x, base + h / 2, z, "y", paint, { solid = false })
			else
				self:box("Leg", thick, h, thick, x, base + h / 2, z, paint)
			end
		end
	end
end

-- splayed mid-century legs (tilted outwards)
function Kit:splayLegs(W: number, D: number, h: number, inset: number, thick: number, paint: any, tilt: number?)
	local a = tilt or 8
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (W / 2 - inset), sz * (D / 2 - inset)
			self:cyl("Leg", h, thick, x, h / 2, z, "y", paint, { rx = -sz * a, rz = sx * a })
		end
	end
end

-- soft cushion: block + rounded front edge (cylinder along X)
function Kit:cushion(name: string, w: number, h: number, d: number, x: number, y: number, z: number, paint: any, o: any?): number
	local idx = self:box(name, w, h, d - h * 0.5, x, y, z + h * 0.25, paint, o)
	self:cyl(name .. "Roll", w, h, x, y, z - d / 2 + h * 0.5, "x", paint)
	return idx
end

-- seat cushion with a piping line
function Kit:seatPad(w: number, h: number, d: number, x: number, y: number, z: number, paint: any, piping: any?): number
	local idx = self:cushion("SeatCushion", w, h, d, x, y, z, paint, { top = true })
	if piping then
		self:box("Piping", w + 0.02, 0.05, 0.05, x, y + h / 2 - 0.03, z - d / 2 + 0.03, piping)
	end
	return idx
end

-- drawer / door front with a bar handle; front at z (facing -Z)
function Kit:front(w: number, h: number, x: number, y: number, z: number, paint: any, handle: any?, vertical: boolean?)
	self:box("Front", w - 0.06, h - 0.06, 0.06, x, y, z - 0.03, paint)
	if handle then
		if vertical then
			self:box("Handle", 0.06, math.min(h * 0.5, 1.2), 0.08, x + w / 2 - 0.22, y, z - 0.1, handle)
		else
			self:box("Handle", math.min(w * 0.45, 1.2), 0.06, 0.08, x, y + h / 2 - 0.22, z - 0.1, handle)
		end
	end
end

-- row of books between x0 and x1 standing on y (bottom), depth d, centred at z
function Kit:books(x0: number, x1: number, y: number, z: number, d: number, hMax: number, seed: number?)
	local cols = {
		{ 176, 56, 52 }, { 52, 82, 120 }, { 226, 214, 190 }, { 60, 100, 76 }, { 212, 164, 60 }, { 40, 40, 44 }, { 150, 110, 160 }, { 200, 120, 80 },
	}
	local x = x0
	local i = seed or 1
	while x < x1 - 0.12 do
		local bw = 0.12 + ((i * 37) % 7) * 0.025
		if x + bw > x1 then
			break
		end
		local bh = hMax * (0.72 + ((i * 53) % 5) * 0.06)
		local c = cols[(i % #cols) + 1]
		if (i % 9) == 4 and x + bh < x1 then
			-- one lying book
			self:box("Book", bh, bw, d * 0.9, x + bh / 2, y + bw / 2, z, self:lit(c, "plastic"))
			x += bh + 0.03
		else
			self:box("Book", bw, bh, d * (0.85 + (i % 3) * 0.05), x + bw / 2, y + bh / 2, z, self:lit(c, "plastic"))
			x += bw + 0.01
		end
		i += 1
	end
end

-- cluster of leaf balls (foliage) around (cx, cy, cz)
function Kit:foliage(cx: number, cy: number, cz: number, r: number, n: number, paint: any, spread: number?)
	local sp = spread or 1
	for i = 1, n do
		local a = i * 2.39996
		local rr = r * (0.35 + 0.65 * ((i * 0.618) % 1)) * sp
		local y = cy + (((i * 0.37) % 1) - 0.4) * r * 1.1
		local dia = r * (0.75 + ((i * 0.29) % 1) * 0.6)
		local tint = if i % 3 == 0 then self:sh(if type(paint) == "string" then paint else "leaf", 1.12) else paint
		self:ball("Leaf", dia, cx + math.cos(a) * rr, y, cz + math.sin(a) * rr, tint)
	end
end

-- big flat leaves (monstera style) fanned around (cx, cy, cz)
function Kit:leaves(cx: number, cy: number, cz: number, len: number, n: number, paint: any)
	for i = 1, n do
		local a = (i / n) * 360 + (i % 2) * 17
		local tilt = 25 + (i % 3) * 14
		local ar = math.rad(a)
		local lx, lz = math.sin(ar) * len * 0.45, math.cos(ar) * len * 0.45
		self:box("Leaf", len * 0.55, 0.04, len, cx + lx, cy + (i % 3) * 0.25, cz + lz, if i % 2 == 0 then paint else self:sh(if type(paint) == "string" then paint else "leaf", 0.88), { rx = tilt, ry = a })
		self:box("Stem", 0.05, 0.05, len * 0.6, cx + lx * 0.4, cy - 0.3 + (i % 3) * 0.2, cz + lz * 0.4, self:lit({ 70, 110, 60 }, "plastic"), { rx = tilt + 10, ry = a })
	end
end

-- pot with rim + soil; returns the soil top height
function Kit:pot(x: number, z: number, dia: number, h: number, paint: any, round: boolean?): number
	if round == false then
		self:box("Pot", dia, h, dia, x, h / 2, z, paint, { solid = true })
		self:box("Rim", dia + 0.08, 0.1, dia + 0.08, x, h - 0.05, z, self:sh(if type(paint) == "string" then paint else "pot", 0.92))
		self:box("Soil", dia - 0.12, 0.06, dia - 0.12, x, h - 0.06, z, self:lit({ 70, 52, 38 }, "slate"))
	else
		self:cyl("Pot", h, dia, x, h / 2, z, "y", paint, { solid = true })
		self:cyl("Rim", 0.12, dia + 0.1, x, h - 0.06, z, "y", self:sh(if type(paint) == "string" then paint else "pot", 0.92))
		self:cyl("Soil", 0.06, dia - 0.12, x, h - 0.05, z, "y", self:lit({ 70, 52, 38 }, "slate"))
	end
	return h
end

-- picture frame on a wall (back at +Z = D/2): outer w x h, centred at (x, y), depth d
function Kit:frame(w: number, h: number, d: number, x: number, y: number, zBack: number, frame: any, mat: any?)
	local z = zBack - d / 2
	local b = math.min(0.16, w * 0.08, h * 0.08)
	self:box("Frame", w, b, d, x, y + h / 2 - b / 2, z, frame)
	self:box("Frame", w, b, d, x, y - h / 2 + b / 2, z, frame)
	self:box("Frame", b, h - 2 * b, d, x - w / 2 + b / 2, y, z, frame)
	self:box("Frame", b, h - 2 * b, d, x + w / 2 - b / 2, y, z, frame)
	if mat then
		self:box("Mat", w - 2 * b, h - 2 * b, 0.03, x, y, zBack - 0.04, mat)
	end
end

-- TV panel: w x h screen centred at (x, y), front face at zFront; bezel paint
function Kit:tvPanel(w: number, h: number, x: number, y: number, zFront: number, bezel: any, depth: number?): number
	local dd = depth or 0.18
	self:box("Bezel", w, h, dd, x, y, zFront + dd / 2, bezel, { solid = true })
	local scr = self:box("Screen", w - 0.12, h - 0.12, 0.03, x, y, zFront - 0.005, self:lit({ 14, 14, 18 }, "glass"), { screen = true, t = 0, rf = 0.12 })
	self:box("Logo", 0.3, 0.04, 0.02, x, y - h / 2 + 0.05, zFront - 0.01, self:lit({ 170, 172, 178 }, "metal"))
	return scr
end

-------------------------------------------------------------------------------------------------
-- Interaction markers
-------------------------------------------------------------------------------------------------
-- a real light on part idx (range, brightness); colour = the "light" slot (or rgb)
function Kit:light(idx: number, range: number, brightness: number, o: any?)
	table.insert(self.lights, {
		p = idx,
		range = range,
		bright = brightness,
		spot = o ~= nil and o.spot == true,
		face = o and o.face or "Bottom",
		angle = o and o.angle or 70,
		rgb = o and o.rgb,
	})
end

-- sitting spot (top of the seat cushion), facing yaw degrees (0 = -Z)
function Kit:seat(x: number, y: number, z: number, yaw: number?)
	table.insert(self.seats, { cf = CFrame.new(x, y, z) * CFrame.Angles(0, rad(yaw or 0), 0), lie = false })
end

-- lying spot on a mattress (head towards +Z unless yaw)
function Kit:bed(x: number, y: number, z: number, yaw: number?)
	table.insert(self.seats, { cf = CFrame.new(x, y, z) * CFrame.Angles(0, rad(yaw or 0), 0), lie = true })
end

-- open pose: parts idx list rotate deg about a hinge axis through (px, py, pz)
function Kit:hinge(idxs: { number }, px: number, py: number, pz: number, axis: string, deg: number)
	local pivot = CFrame.new(px, py, pz)
	local rot = if axis == "x" then CFrame.Angles(rad(deg), 0, 0) elseif axis == "z" then CFrame.Angles(0, 0, rad(deg)) else CFrame.Angles(0, rad(deg), 0)
	local tf = pivot * rot * pivot:Inverse()
	for _, i in idxs do
		local p = self.parts[i]
		if p then
			p.open = tf * p.cf
		end
	end
	self.hasPose = true
end

-- open pose: parts slide by (dx, dy, dz); optional size scale (sx, sy, sz) for gathered curtains
function Kit:slide(idxs: { number }, dx: number, dy: number, dz: number, scale: Vector3?)
	for _, i in idxs do
		local p = self.parts[i]
		if p then
			p.open = CFrame.new(dx, dy, dz) * p.cf
			if scale then
				p.openSize = Vector3.new(p.size.X * scale.X, p.size.Y * scale.Y, p.size.Z * scale.Z)
			end
		end
	end
	self.hasPose = true
end

-- explicit open pose of one part
function Kit:pose(idx: number, cf: CFrame, size: Vector3?)
	local p = self.parts[idx]
	if p then
		p.open = cf
		p.openSize = size
		self.hasPose = true
	end
end

-- water volume where the client animates fish (centre + size, item frame)
function Kit:tank(x: number, y: number, z: number, w: number, h: number, d: number)
	self.tank = { cf = CFrame.new(x, y, z), size = Vector3.new(w, h, d) }
end

-- fire box (fireplace / fire pit): Fire + flickering light
function Kit:fire(x: number, y: number, z: number, w: number, h: number, d: number)
	self.fire = { cf = CFrame.new(x, y, z), size = Vector3.new(w, h, d) }
end

-- the part a speaker plays from
function Kit:speaker(idx: number)
	self.speaker = idx
end

function Kit:spec(): any
	return {
		parts = self.parts,
		lights = self.lights,
		seats = self.seats,
		tank = self.tank,
		fire = self.fire,
		speaker = self.speaker,
		hasPose = self.hasPose,
	}
end

return Kit
