-- Builder/Shell: the always-present part of a building — slabs (with stair / shaft holes), the facade
-- walls with real openings (windows, storefronts, balcony doors, curtain wall), balconies you can step
-- onto, terraces on setbacks, parapets, the roof with its stair tower and equipment, the entrance doors,
-- signage and the wear details (rain streaks, outdoor AC units, gas pipes, cracks, faded paint).
-- Everything is built from the plan (Builder/Plan); the interior is built later and slots inside.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Kit = Shared.Kit
local Config = Shared.Config
local Util = Shared.Util
local Rng = Shared.Rng
local Palette = Shared.Palette

local Plan = require(script.Parent.Plan)
local Core = require(script.Parent.Core)

local Shell = {}

local V3, CF = Vector3.new, CFrame.new
local rad = math.rad
local min, max = math.min, math.max

local SLAB = Config.SLAB
local WT = Config.WALL_EXT

-- outward normal + yaw for a facade side (LookVector = outward)
local SIDE = {
	["-z"] = { n = V3(0, 0, -1), yaw = 0 },
	["+z"] = { n = V3(0, 0, 1), yaw = 180 },
	["-x"] = { n = V3(-1, 0, 0), yaw = 90 },
	["+x"] = { n = V3(1, 0, 0), yaw = -90 },
}
Shell.SIDE = SIDE

-- local frame of a wall: origin at (along = 0) on the wall centre line at y, X along the wall in
-- increasing `along`, -Z outward. Returns a building-local CFrame.
local function wallFrame(side: string, line: number, y: number): (CFrame, number)
	if side == "-z" then
		return CF(0, y, line), 1
	elseif side == "+z" then
		-- along = x, but X axis must increase with x while -Z points +z: rotate 180 and mirror along
		return CF(0, y, line) * CFrame.Angles(0, math.pi, 0), -1
	elseif side == "-x" then
		return CF(line, y, 0) * CFrame.Angles(0, rad(90), 0), -1
	else
		return CF(line, y, 0) * CFrame.Angles(0, rad(-90), 0), 1
	end
end
Shell.wallFrame = wallFrame

-- along-coordinate -> local X of the wall frame
local function ax(sign: number, a: number): number
	return sign * a
end

-------------------------------------------------------------------------------------------------
-- windows
-------------------------------------------------------------------------------------------------
local NIGHT_ZONE = { apartment = "home", officetel = "home", villa = "home", oneroom = "home", hotel = "hotel", plaza = "office", bbq = "shop", cafe = "shop" }

local function fillOpening(m: Instance, rec: any, wf: CFrame, sign: number, o: any, fl: any, rng: any)
	local style = rec.style
	local a0, a1 = ax(sign, o.a0), ax(sign, o.a1)
	local x0, x1 = min(a0, a1), max(a0, a1)
	local w = x1 - x0
	local cx = (x0 + x1) / 2
	local y0, y1 = o.y0, o.y1
	local h = y1 - y0
	local frameCol = style.frame
	local glass = style.glass
	local kind = o.kind
	if kind == "door" or kind == "entrance" or kind == "void" then
		return -- doors are placed separately; voids stay open
	end
	-- glass pane (on the wall centre plane) + night window contract
	local tint = o.tint or glass.color
	local pane = Kit.part(m, wf * CF(cx, y0 + h / 2, 0), V3(w - 0.1, h - 0.1, 0.14), "Glass", tint, { tr = glass.tr, refl = glass.refl, name = "Glass" })
	if kind ~= "balcony" then
		pane:SetAttribute("LitChance", o.lit or (if kind == "storefront" then 1 else 0.5))
		pane:SetAttribute("LitColor", o.litColor or (if kind == "storefront" then Color3.fromRGB(255, 236, 200) else Color3.fromRGB(255, 206, 140)))
		pane:SetAttribute("Zone", o.zone or NIGHT_ZONE[rec.archetype] or "home")
		CollectionService:AddTag(pane, "NightWindow")
	end
	if kind == "balcony" then
		-- sliding door look: the actual sliding leaf is a Door built by Shell.balcony; this pane is the fixed half
		pane.Size = V3(w / 2 - 0.05, h - 0.1, 0.14)
		pane.CFrame = wf * CF(cx - w / 4, y0 + h / 2, 0.15)
	end
	-- frame
	local fd = 0.3
	Kit.part(m, wf * CF(cx, y1 - 0.1, 0), V3(w, 0.2, fd), "Metal", frameCol, { name = "WinFrame", collide = false })
	Kit.part(m, wf * CF(cx, y0 + 0.1, 0), V3(w, 0.2, fd), "Metal", frameCol, { name = "WinFrame", collide = false })
	Kit.part(m, wf * CF(x0 + 0.1, y0 + h / 2, 0), V3(0.2, h, fd), "Metal", frameCol, { name = "WinFrame", collide = false })
	Kit.part(m, wf * CF(x1 - 0.1, y0 + h / 2, 0), V3(0.2, h, fd), "Metal", frameCol, { name = "WinFrame", collide = false })
	-- mullions
	local seg = if kind == "storefront" then 5 elseif kind == "curtain" then 4 else 3.4
	local nm = math.max(0, math.floor(w / seg))
	if kind ~= "balcony" then
		for i = 1, nm do
			local mx = x0 + i * (w / (nm + 1))
			Kit.part(m, wf * CF(mx, y0 + h / 2, 0), V3(0.14, h, fd), "Metal", frameCol, { name = "Mullion", collide = false })
		end
	end
	if kind == "curtain" or (kind == "storefront" and h > 9) then
		Kit.part(m, wf * CF(cx, y0 + h - 2.4, 0), V3(w, 0.14, fd), "Metal", frameCol, { name = "Transom", collide = false })
	end
	-- exterior sill + rain streaks
	if kind == "window" then
		Kit.part(m, wf * CF(cx, y0 - 0.12, -WT / 2 - 0.2), V3(w + 0.4, 0.24, 0.5), style.accent.mat, rec.tone.accent, { name = "Sill", collide = false })
		if rec.wear > 0.25 and rng:chance(rec.wear) then
			local sw = rng:range(0.3, 1.0)
			local sx = rng:range(x0 + 0.3, x1 - 0.3)
			local len = rng:range(1.5, 3.5) * (0.5 + rec.wear)
			Kit.part(m, wf * CF(sx, y0 - 0.3 - len / 2, -WT / 2 - 0.02), V3(sw, len, 0.04), "SmoothPlastic", Util.age(rec.tone.wall, 1, Color3.fromRGB(60, 50, 40)), { name = "Streak", collide = false, tr = 0.35 })
		end
	end
	-- curtains / blinds just inside (homes and hotels): the facade looks lived in from the street
	local zone = NIGHT_ZONE[rec.archetype] or "home"
	if (kind == "window" or kind == "balcony") and (zone == "home" or zone == "hotel") and o.curtain ~= false then
		local CUR = { { 240, 236, 226 }, { 214, 206, 190 }, { 180, 196, 210 }, { 236, 220, 220 }, { 120, 120, 126 } }
		local c = rng:pick(CUR)
		local cw = w * rng:range(0.18, 0.4)
		local side = if rng:chance(0.5) then x0 + cw / 2 + 0.1 else x1 - cw / 2 - 0.1
		Kit.part(m, wf * CF(side, y0 + h / 2 + 0.2, WT / 2 + 0.35), V3(cw, h + 0.2, 0.08), "Fabric", c, { name = "Curtain", collide = false })
		if zone == "hotel" then
			local other = if side < cx then x1 - cw / 2 - 0.1 else x0 + cw / 2 + 0.1
			Kit.part(m, wf * CF(other, y0 + h / 2 + 0.2, WT / 2 + 0.35), V3(cw, h + 0.2, 0.08), "Fabric", c, { name = "Curtain", collide = false })
		end
	end
	-- outdoor AC unit hanging under the window of older homes (실외기 + rusty bracket)
	if kind == "window" and zone == "home" and rng:chance(0.15 + rec.wear * 0.5) and o.ac ~= false then
		local axp = rng:range(x0 + 1.2, max(x0 + 1.3, x1 - 1.2))
		local acf = wf * CF(axp, y0 - 1.6, -WT / 2 - 0.85)
		Kit.part(m, acf, V3(2.6, 2.0, 1.1), "SmoothPlastic", Util.age(Color3.fromRGB(230, 230, 226), rec.wear), { name = "AcUnit", collide = false })
		Kit.part(m, acf * CF(-0.4, 0, -0.56), V3(1.4, 1.4, 0.04), "SmoothPlastic", { 70, 70, 72 }, { name = "AcGrille", collide = false })
		Kit.part(m, acf * CF(0, -1.1, 0.1), V3(2.8, 0.15, 1.4), "Metal", Util.age(Color3.fromRGB(120, 120, 124), rec.wear, Color3.fromRGB(150, 70, 30)), { name = "Bracket", collide = false })
	end
end

-------------------------------------------------------------------------------------------------
-- balconies: slab + railing projecting outward in front of a "balcony" opening; a real sliding door
-------------------------------------------------------------------------------------------------
local function balcony(m: Instance, rec: any, wf: CFrame, sign: number, o: any, fl: any)
	-- wf: WORLD wall frame
	local style = rec.style
	local a0, a1 = ax(sign, o.a0), ax(sign, o.a1)
	local x0, x1 = min(a0, a1), max(a0, a1)
	local depth = o.depth or 4
	local w = x1 - x0
	-- slab (top flush with the floor)
	Kit.part(m, wf * CF((x0 + x1) / 2, -SLAB / 2, -WT / 2 - depth / 2), V3(w + 0.8, SLAB, depth), "Concrete", rec.tone.accent, { name = "BalconySlab" })
	Kit.part(m, wf * CF((x0 + x1) / 2, 0.03, -WT / 2 - depth / 2), V3(w + 0.6, 0.06, depth - 0.2), "CeramicTiles", { 196, 190, 180 }, { name = "BalconyTile", collide = false })
	-- railing on the 3 open sides
	local railKind = o.rail or style.rail
	local h = 3.6
	local p1 = V3(x0 - 0.3, 0, -WT / 2 - depth + 0.1)
	local p2 = V3(x1 + 0.3, 0, -WT / 2 - depth + 0.1)
	local p0 = V3(x0 - 0.3, 0, -WT / 2)
	local p3 = V3(x1 + 0.3, 0, -WT / 2)
	local railCol = if railKind == "glass" then style.frame else Util.age(Color3.fromRGB(70, 74, 80), rec.wear, Color3.fromRGB(140, 70, 30))
	for _, seg in { { p0, p1 }, { p1, p2 }, { p2, p3 } } do
		Kit.rail(m, wf, seg[1], seg[2], h, "Metal", railCol, { solid = railKind == "glass", spacing = 0.5, postDia = 0.08 })
	end
	-- the sliding glass door (the moving half of the balcony opening)
	local doorW = w / 2
	Core.door(m, wf * CF((x0 + x1) / 2 + doorW / 2 - 0.05, 0, 0), {
		w = doorW,
		h = o.y1 - o.y0,
		t = WT,
		kind = "sliding_glass",
		hinge = "right",
		casing = false,
		blockArc = false,
		color = style.glass.color,
		frameColor = style.frame,
		id = (o.id or (rec.id .. "_bal")) .. "_" .. tostring(math.floor((x0 + x1) * 10)),
		unitId = o.unitId,
	})
	-- a potted plant / drying rack on some balconies
	if rec.rng:chance(0.45) then
		local px = rec.rng:range(x0 + 0.8, x1 - 0.8)
		Kit.part(m, wf * CF(px, 0.8, -WT / 2 - depth + 1), V3(1.0, 1.6, 1.0), "SmoothPlastic", { 150, 90, 60 }, { name = "Pot", collide = false })
		Kit.part(m, wf * CF(px, 2.2, -WT / 2 - depth + 1), V3(1.6, 1.4, 1.6), "LeafyGrass", { 60, 130, 70 }, { name = "Plant", collide = false })
	end
end

-------------------------------------------------------------------------------------------------
-- walls of one edge (with openings and open spans)
-------------------------------------------------------------------------------------------------
local function edgeWalls(m: Instance, rec: any, fl: any, e: any, yBot: number, yTop: number, mat: string, color: Color3, rng: any)
	local wf, sign = wallFrame(e.side, e.line, fl.y)
	local wfw = rec.cf * wf
	-- open spans on this edge
	local spans = {}
	for _, op in fl.open do
		if op.side == e.side and math.abs(op.line - e.line) < 0.3 then
			local s0, s1 = max(e.a0, op.a0), min(e.a1, op.a1)
			if s1 - s0 > 0.05 then
				table.insert(spans, { s0, s1, op.rail })
			end
		end
	end
	-- holes: openings on this edge + open spans
	local holes = {}
	local mine = {}
	for _, o in fl.openings do
		if o.side == e.side and math.abs(o.line - e.line) < 0.3 and o.a1 > e.a0 + 0.05 and o.a0 < e.a1 - 0.05 then
			local a0, a1 = ax(sign, o.a0), ax(sign, o.a1)
			table.insert(holes, { min(a0, a1), max(a0, a1), o.y0, o.y1 })
			table.insert(mine, o)
		end
	end
	for _, s in spans do
		local a0, a1 = ax(sign, s[1]), ax(sign, s[2])
		table.insert(holes, { min(a0, a1), max(a0, a1), -0.01, yTop + 1 })
	end
	local e0, e1 = ax(sign, e.a0), ax(sign, e.a1)
	-- walls extend half a wall past the edge ends so corners close
	local x0, x1 = min(e0, e1) - WT / 2, max(e0, e1) + WT / 2
	Kit.wallX(m, wfw, x0, x1, 0, WT, yBot, yTop, holes, mat, color, { name = "Facade" })
	for _, o in mine do
		fillOpening(m, rec, wfw, sign, o, fl, rng)
		if o.kind == "balcony" then
			balcony(m, rec, wfw, sign, o, fl)
		end
	end
	-- open spans: parapet + rail (open-air corridors, terraces)
	for _, s in spans do
		local a0, a1 = ax(sign, s[1]), ax(sign, s[2])
		local sx0, sx1 = min(a0, a1), max(a0, a1)
		local kind = s[3]
		if kind == "parapet" then
			Kit.box(m, wfw, sx0, yBot, -WT / 2, sx1, 3.4, WT / 2, mat, color, { name = "Parapet" })
			Kit.box(m, wfw, sx0, 3.4, -WT / 2 - 0.1, sx1, 3.7, WT / 2 + 0.1, rec.style.accent.mat, rec.tone.accent, { name = "ParapetCap" })
			Kit.rail(m, wfw, V3(sx0, 3.7, 0), V3(sx1, 3.7, 0), 1.0, "Metal", Util.age(Color3.fromRGB(80, 84, 90), rec.wear), { spacing = 2.5, collide = true })
		elseif kind == "none" then
			-- nothing (pilotis, gate)
		else
			Kit.box(m, wfw, sx0, yBot, -WT / 2, sx1, 0, WT / 2, mat, color, { name = "Curb" })
			Kit.rail(m, wfw, V3(sx0, 0, 0), V3(sx1, 0, 0), 3.6, "Metal", rec.style.frame, { solid = kind == "glass", spacing = 0.5, postDia = 0.08 })
		end
	end
	return wfw, sign, x0, x1
end

-------------------------------------------------------------------------------------------------
-- slabs, terraces, roof
-------------------------------------------------------------------------------------------------
local function insideAny(rects: { any }, px: number, pz: number): boolean
	for _, r in rects do
		if px > r.x0 + 0.01 and px < r.x1 - 0.01 and pz > r.z0 + 0.01 and pz < r.z1 - 0.01 then
			return true
		end
	end
	return false
end

local function slabFor(m: Instance, rec: any, rects: { any }, holes: { any }, y: number, mat: string, color: any, name: string)
	local frame = rec.cf
	for _, r in rects do
		for _, piece in Plan.subtract(r, holes) do
			Kit.box(m, frame, piece.x0 - WT / 2, y - SLAB, piece.z0 - WT / 2, piece.x1 + WT / 2, y, piece.z1 + WT / 2, mat, color, { name = name })
		end
	end
end

-- parapet along the exposed edges of `rects` at height y (roofs and terraces)
local function parapets(m: Instance, rec: any, rects: { any }, upper: { any }?, y: number, height: number)
	for _, e in Plan.edges(rects) do
		-- skip spans covered by the floor above (its facade continues there)
		local wf, sign = wallFrame(e.side, e.line, y)
		local wfw = rec.cf * wf
		local inward = -SIDE[e.side].n
		local cuts = { e.a0, e.a1 }
		if upper then
			for _, r in upper do
				for _, c in { r.x0, r.x1, r.z0, r.z1 } do
					if c > e.a0 and c < e.a1 then
						table.insert(cuts, c)
					end
				end
			end
		end
		table.sort(cuts)
		for i = 1, #cuts - 1 do
			local s, t = cuts[i], cuts[i + 1]
			if t - s > 0.05 then
				local mid = (s + t) / 2
				local probe = if e.side == "-z" or e.side == "+z" then V3(mid, 0, e.line) + inward * 0.6 else V3(e.line, 0, mid) + inward * 0.6
				local covered = upper and insideAny(upper, probe.X, probe.Z)
				if not covered then
					local a0, a1 = ax(sign, s), ax(sign, t)
					local sx0, sx1 = min(a0, a1) - WT / 2, max(a0, a1) + WT / 2
					Kit.box(m, wfw, sx0, 0, -WT / 2, sx1, height, WT / 2, rec.style.wall.mat, rec.tone.wall, { name = "Parapet" })
					Kit.box(m, wfw, sx0 - 0.1, height, -WT / 2 - 0.12, sx1 + 0.1, height + 0.3, WT / 2 + 0.12, rec.style.accent.mat, rec.tone.accent, { name = "Coping" })
				end
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- wear decorations on a facade edge (whole building height)
-------------------------------------------------------------------------------------------------
local function wearDetails(m: Instance, rec: any, rng: any)
	if rec.wear < 0.2 then
		return
	end
	local fl0 = rec.floors[1]
	for _, fl in rec.floors do
		if fl.label == rec.lobbyLabel then
			fl0 = fl
		end
	end
	local edges = Plan.edges(fl0.rects)
	for _, e in edges do
		local wf, sign = wallFrame(e.side, e.line, 0)
		local wfw = rec.cf * wf
		local len = e.a1 - e.a0
		-- exposed yellow gas pipe climbing the facade (old Korean buildings)
		if rng:chance(rec.wear * 0.9) and len > 12 then
			local px = ax(sign, rng:range(e.a0 + 2, e.a1 - 2))
			Kit.box(m, wfw, px - 0.12, 0.5, -WT / 2 - 0.35, px + 0.12, rec.roofY - 1, -WT / 2 - 0.12, "Metal", Util.age(Color3.fromRGB(230, 190, 40), rec.wear), { name = "GasPipe", collide = false })
			for _, fl in rec.floors do
				if fl.y > 0 and fl.kind ~= "roof" then
					Kit.box(m, wfw, px - 0.12, fl.y + 1.0, -WT / 2 - 0.35, px + 1.2, fl.y + 1.25, -WT / 2 - 0.12, "Metal", Util.age(Color3.fromRGB(230, 190, 40), rec.wear), { name = "GasMeter", collide = false })
					Kit.box(m, wfw, px + 0.6, fl.y + 1.25, -WT / 2 - 0.5, px + 1.6, fl.y + 2.2, -WT / 2 - 0.1, "SmoothPlastic", { 200, 200, 196 }, { name = "GasMeter", collide = false })
				end
			end
		end
		-- cracks
		local nCracks = math.floor(rec.wear * 4 * len / 30)
		for _ = 1, nCracks do
			local cx = ax(sign, rng:range(e.a0 + 1, e.a1 - 1))
			local cy = rng:range(1, rec.roofY - 2)
			local a = rng:range(-60, 60)
			for k = 0, 2 do
				Kit.part(m, wfw * CF(cx + k * 0.5 * math.sin(rad(a)), cy - k * 0.9, -WT / 2 - 0.02) * CFrame.Angles(0, 0, rad(a + rng:range(-20, 20))), V3(0.06, 1.0, 0.03), "SmoothPlastic", { 70, 66, 60 }, { name = "Crack", collide = false, tr = 0.3 })
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- signage
-------------------------------------------------------------------------------------------------
-- sign = { side, line?, at (along centre), y, w, h, text, sub?, kind = "band" | "vertical" | "box" | "roof" | "name",
--          bg, fg, glow, depth }
function Shell.sign(m: Instance, rec: any, s: any)
	local side = s.side or "-z"
	local line = s.line
	if not line then
		line = if side == "-z" then 0 elseif side == "+z" then rec.D elseif side == "-x" then -rec.W / 2 else rec.W / 2
	end
	local wf, sign = wallFrame(side, line, 0)
	local wfw = rec.cf * wf
	local x = ax(sign, s.at or 0)
	local depth = s.depth or 0.6
	local out = -WT / 2 - depth / 2 - (s.offset or 0.02)
	local bg = s.bg or { 30, 30, 34 }
	local fg = s.fg or { 255, 255, 255 }
	local wear = rec.wear
	local bgc = Util.age(Kit.col(bg), wear * 0.8)
	local p
	if s.kind == "vertical" then
		-- 돌출 간판 sticking out of the corner, readable from both directions of the street
		local scf = wfw * CF(x, s.y + s.h / 2, -WT / 2 - s.w / 2 - 0.3) * CFrame.Angles(0, rad(90), 0)
		p = Kit.part(m, scf, V3(s.w, s.h, depth), "SmoothPlastic", bgc, { name = "VSign", collide = false })
		Kit.text(p, "front", s.text, { color = fg, ppS = 30, font = s.font or Enum.Font.GothamBlack, maxDist = 400 })
		Kit.text(p, "back", s.text, { color = fg, ppS = 30, font = s.font or Enum.Font.GothamBlack, maxDist = 400 })
		Kit.part(m, wfw * CF(x, s.y + s.h * 0.2, -WT / 2 - 0.15), V3(0.2, 0.2, 0.6), "Metal", { 80, 80, 84 }, { collide = false, name = "Bracket" })
		Kit.part(m, wfw * CF(x, s.y + s.h * 0.8, -WT / 2 - 0.15), V3(0.2, 0.2, 0.6), "Metal", { 80, 80, 84 }, { collide = false, name = "Bracket" })
	else
		p = Kit.part(m, wfw * CF(x, s.y + s.h / 2, out), V3(s.w, s.h, depth), if s.glass then "Glass" else "SmoothPlastic", bgc, { name = "Sign", collide = false })
		if s.text and s.text ~= "" then
			local txt = s.text
			if s.sub then
				txt = txt .. "\n" .. s.sub
			end
			Kit.text(p, "front", txt, { color = fg, ppS = s.ppS or 24, font = s.font or Enum.Font.GothamBlack, maxDist = 500, wrap = s.sub ~= nil })
		end
	end
	if s.glow ~= false then
		p:SetAttribute("SignGlow", true)
		CollectionService:AddTag(p, "GwB_Sign")
		if wear > 0.55 and rec.rng:chance(0.5) then
			p:SetAttribute("Flicker", true)
		end
	end
	return p
end

-------------------------------------------------------------------------------------------------
-- build the shell
-------------------------------------------------------------------------------------------------
function Shell.build(rec: any, parent: Instance): Model
	local m = Kit.model(parent, "Shell")
	local rng = Rng.child(rec.seed, "shell")
	local style = rec.style
	local wallCol = Util.age(rec.tone.wall, rec.wear * 0.7, Color3.fromRGB(110, 96, 80))
	local accentCol = Util.age(rec.tone.accent, rec.wear * 0.6)
	local baseCol = Util.age(rec.tone.base, rec.wear * 0.5)
	local floors = rec.floors
	for i, fl in floors do
		local fm = Kit.model(m, "F_" .. fl.label)
		local upper = floors[i + 1]
		-- slab
		if not fl.noSlab then
			slabFor(fm, rec, fl.rects, fl.holes, fl.y, "Concrete", { 156, 156, 152 }, "Slab")
		end
		-- terraces: parts of this floor not covered by the next floor
		if upper then
			local terr = {}
			for _, r in fl.rects do
				for _, piece in Plan.subtract(r, upper.rects) do
					table.insert(terr, piece)
				end
			end
			if #terr > 0 then
				local underground = upper.y <= 0.01
				slabFor(fm, rec, terr, {}, upper.y, if underground then "Pavement" else "Concrete", if underground then { 176, 170, 160 } else style.roof.color, "TerraceSlab")
				local railH = if underground then 0 else (fl.data.terraceRail or 3.6)
				if railH > 0 then
					parapets(fm, rec, terr, upper.rects, upper.y, railH)
				end
			end
		end
		-- walls on the exterior edges
		local mat = fl.data.wallMat or style.wall.mat
		local col = if fl.data.wallMat == style.base.mat or fl.data.base then baseCol else wallCol
		if fl.data.wallColor then
			col = Kit.col(fl.data.wallColor)
		end
		if fl.data.base then
			mat = style.base.mat
		end
		local yTop = fl.h - SLAB
		if not fl.data.pilotis then
			for _, e in Plan.edges(fl.rects) do
				edgeWalls(fm, rec, fl, e, -SLAB, yTop, mat, col, rng)
			end
		else
			-- 필로티: columns on the perimeter + grid, open walls except where the plan says
			for _, r in fl.rects do
				local nx = math.max(1, math.floor((r.x1 - r.x0) / 12))
				local nz = math.max(1, math.floor((r.z1 - r.z0) / 12))
				for ix = 0, nx do
					for iz = 0, nz do
						local px = r.x0 + (r.x1 - r.x0) * ix / nx
						local pz = r.z0 + (r.z1 - r.z0) * iz / nz
						Kit.box(fm, rec.cf, px - 0.8, fl.y - SLAB, pz - 0.8, px + 0.8, fl.y + yTop, pz + 0.8, style.base.mat, baseCol, { name = "Column" })
					end
				end
			end
			for _, w in fl.data.walls or {} do
				-- explicit wall pieces of the pilotis floor (stair enclosure, storage)
				local e = { side = w.side, line = w.line, a0 = w.a0, a1 = w.a1 }
				edgeWalls(fm, rec, fl, e, -SLAB, yTop, mat, col, rng)
			end
		end
		-- slab edge bands (horizontal accent lines on the facade)
		if fl.y ~= 0 or fl.label ~= floors[1].label then
			for _, e in Plan.edges(fl.rects) do
				if fl.data.band ~= false and style.curtain ~= true then
					local wf, sign = wallFrame(e.side, e.line, fl.y)
					local a0, a1 = ax(sign, e.a0), ax(sign, e.a1)
					Kit.box(fm, rec.cf * wf, min(a0, a1) - WT / 2 - 0.1, -SLAB - 0.05, -WT / 2 - 0.12, max(a0, a1) + WT / 2 + 0.1, 0.1, -WT / 2 + 0.05, style.accent.mat, accentCol, { name = "Band", collide = false })
				elseif style.curtain then
					local wf, sign = wallFrame(e.side, e.line, fl.y)
					local a0, a1 = ax(sign, e.a0), ax(sign, e.a1)
					Kit.box(fm, rec.cf * wf, min(a0, a1) - WT / 2 - 0.1, -SLAB - 0.6, -WT / 2 - 0.1, max(a0, a1) + WT / 2 + 0.1, 0.5, -WT / 2 + 0.05, "Metal", Kit.col(style.frame), { name = "Spandrel", collide = false })
				end
			end
		end
		if i % 2 == 0 then
			task.wait()
		end
	end

	-- roof
	local top = floors[#floors]
	local roofRects = top.rects
	local roofHoles = {}
	for _, s in rec.stairs do
		if s.roof and s.roofHole then
			table.insert(roofHoles, s.roofHole)
		end
	end
	local rm = Kit.model(m, "Roof")
	slabFor(rm, rec, roofRects, roofHoles, rec.roofY, "Concrete", style.roof.color, "RoofSlab")
	parapets(rm, rec, roofRects, nil, rec.roofY, rec.roof.parapet or 3.6)
	for _, s in rec.stairs do
		if s.roof then
			Core.roofStairTower(rm, rec, s, style)
		end
	end
	for _, e in rec.elevators do
		-- elevator machine room above the shaft
		local f = rec.cf * e.frame * CF(0, rec.roofY, 0)
		Kit.box(rm, f, -e.EW / 2 - 0.4, 0, -0.4, e.EW / 2 + 0.4, 6.5, e.ED + 0.4, style.wall.mat, wallCol, { name = "MachineRoom" })
		Kit.box(rm, f, -e.EW / 2 - 0.6, 6.5, -0.6, e.EW / 2 + 0.6, 7.0, e.ED + 0.6, "Concrete", style.roof.color, { name = "MachineRoof" })
		Core.plate(rm, f * CF(0, 4.6, -0.48), 3.2, 0.8, "승강기 기계실", { bg = { 220, 220, 216 }, fg = { 60, 60, 64 } })
	end
	if rec.roof.equipment ~= false then
		local r = roofRects[1]
		local fr = rec.cf * CF(0, rec.roofY, 0)
		local avoid = {}
		for _, s in rec.stairs do
			table.insert(avoid, s.box)
		end
		-- pick the largest roof rect area away from towers
		local best = r
		for _, q in roofRects do
			if (q.x1 - q.x0) * (q.z1 - q.z0) > (best.x1 - best.x0) * (best.z1 - best.z0) then
				best = q
			end
		end
		local ex0, ez0, ex1, ez1 = best.x0, best.z0, best.x1, best.z1
		if rec.roof.equipRect then
			ex0, ez0, ex1, ez1 = table.unpack(rec.roof.equipRect)
		end
		Core.roofStuff(rm, fr, ex0, ez0, ex1, ez1, rng, rec.roof.kind or (if rec.wear < 0.25 then "modern" else "old"), rec.wear)
	end

	-- entrance doors and other shell doors
	for _, d in rec.doors do
		local fl = rec.floorByLabel[d.floor]
		local s = SIDE[d.side]
		local p = if d.side == "-z" or d.side == "+z" then V3(d.at, fl.y, d.line) else V3(d.line, fl.y, d.at)
		local dcf = rec.cf * CF(p) * CFrame.Angles(0, rad(s.yaw), 0)
		local spec = table.clone(d)
		spec.t = spec.t or WT
		spec.id = spec.id or (rec.id .. "_" .. d.floor .. "_" .. math.floor(d.at))
		Core.door(m, dcf, spec)
		-- canopy over main entrances
		if d.canopy then
			local cw = (d.w or 4) + 3
			Kit.part(m, dcf * CF(0, (d.h or 7.6) + 1.2, -2.0), V3(cw, 0.35, 4.0), if d.canopy == "glass" then "Glass" else "Metal", if d.canopy == "glass" then { 200, 220, 230 } else style.frame, { name = "Canopy", tr = if d.canopy == "glass" then 0.4 else 0, collide = false })
			local lamp = Kit.part(m, dcf * CF(0, (d.h or 7.6) + 0.98, -2.0), V3(1.2, 0.1, 1.2), "Neon", { 255, 236, 200 }, { name = "CanopyLight", collide = false })
			Kit.light(lamp, "spot", { face = "bottom", color = { 255, 226, 180 }, brightness = 1.5, range = 14, angle = 100, attrs = { Group = "exterior" } })
		end
		if d.signText then
			Core.plate(m, dcf * CF(0, (d.h or 7.6) + 2.4, -0.6), math.max(4, (d.w or 4) + 1), 1.0, d.signText, { bg = d.signBg or { 30, 30, 34 }, fg = d.signFg or { 255, 255, 255 }, ppS = 30 })
		end
	end
	-- signs
	for _, s in rec.signs do
		Shell.sign(m, rec, s)
	end
	-- archetype extras (forecourt, ramp walls, pilotis furniture ...)
	if rec.hooks.shell then
		rec.hooks.shell(m, rec, rng)
	end
	wearDetails(m, rec, rng)
	return m
end

return Shell
