-- Builder/Archetypes: the eight building types of the district as PLANS (pure data + floor hooks):
--   apartment  광안 오션뷰 아파트   복도식 12F + B1 주차장 + 펜트하우스 + 옥상
--   officetel  해오름 오피스텔      중복도 9F, 1F 편의점 GW25 + 보안 로비, 커튼월
--   villa      광안하우스 빌라      필로티 + 계단실형 2세대 x 4층 + 옥탑방 (적벽돌, 노후)
--   oneroom    해변 원룸텔          필로티 + 중복도 원룸 4세대 x 4층, 소형 엘리베이터 (노후)
--   plaza      광안 프라자 (상가)    1F 국밥 · 부동산, 2F PC방, 3F 노래방, 4F 당구장, 층별 화장실
--   hotel      호텔 씨사이드 광안    B1 주차 + 로비 + 객실 8개 층 + 루프탑 바
--   bbq        광안 숯불갈비         2층 단독 고깃집
--   cafe       바다 카페             2층 + 루프탑 테라스
-- Each archetype function returns a plan (Builder/Plan) with hooks:
--   hooks.floor(ctx, fl)          structure of a storey that is not a unit / shop / stair / elevator
--                                  (lobbies, corridors, hall walls, restrooms, parking)
--   hooks.furnish(ctx, fl, into)  storey props built only near players (lobby furniture ...)
--   hooks.shell(m, rec, rng)      exterior extras (ramps, forecourts, rooftop decks, 옥탑 shell)
-- def = { id, name?, cf, seed?, wear?, style?, floors? } (floors = number of typical storeys)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Kit = Shared.Kit
local Config = Shared.Config
local Palette = Shared.Palette
local Furniture = Shared.Furniture
local Rng = Shared.Rng
local Util = Shared.Util

local Plan = require(script.Parent.Plan)
local Core = require(script.Parent.Core)
local Units = require(script.Parent.Units)

local A = {}
local Shops: any = nil -- bound by A.bind (Builder init) to avoid a require cycle

local V3, CF = Vector3.new, CFrame.new
local rad = math.rad
local min, max, floor = math.min, math.max, math.floor
local FIN = Palette.FINISH
local RES = Config.FLOOR_H_RES

-------------------------------------------------------------------------------------------------
-- helpers (ctx = { rec, fl, parent, rng, wallOnce })
-------------------------------------------------------------------------------------------------
local function ffl(ctx: any): CFrame
	return ctx.rec.cf * CF(0, ctx.fl.y, 0)
end

local function ceilOf(ctx: any): number
	return ctx.fl.h - Config.SLAB
end

local function wallX(ctx: any, x0: number, x1: number, z: number, holes: { any }?, opts: any?)
	local o = opts or {}
	return Kit.wallX(ctx.parent, ffl(ctx), x0, x1, z, o.t or Config.WALL_INT, o.y0 or 0, o.y1 or ceilOf(ctx), holes, o.mat or "Plaster", o.color or { 232, 230, 224 }, { name = o.name or "Wall" })
end

local function wallZ(ctx: any, z0: number, z1: number, x: number, holes: { any }?, opts: any?)
	local o = opts or {}
	return Kit.wallZ(ctx.parent, ffl(ctx), z0, z1, x, o.t or Config.WALL_INT, o.y0 or 0, o.y1 or ceilOf(ctx), holes, o.mat or "Plaster", o.color or { 232, 230, 224 }, { name = o.name or "Wall" })
end

local function door(ctx: any, x: number, z: number, yaw: number, spec: any): Model
	return Core.door(ctx.parent, ffl(ctx) * CF(x, 0, z) * CFrame.Angles(0, rad(yaw), 0), spec)
end

local function floorFinish(ctx: any, x0: number, z0: number, x1: number, z1: number, mat: string, color: any)
	return Kit.box(ctx.parent, ffl(ctx), x0, 0, z0, x1, 0.06, z1, mat, color, { collide = false, name = "FloorFinish" })
end

local function ceiling(ctx: any, x0: number, z0: number, x1: number, z1: number)
	local c = ceilOf(ctx)
	return Kit.box(ctx.parent, ffl(ctx), x0, c - 0.1, z0, x1, c, z1, FIN.ceiling.mat, FIN.ceiling.color, { collide = false, name = "Ceiling" })
end

-- a common corridor / hall: finish, ceiling, sensor lights, fire extinguisher, CCTV, exit sign
local function corridor(ctx: any, x0: number, z0: number, x1: number, z1: number, opts: any?)
	local o = opts or {}
	floorFinish(ctx, x0, z0, x1, z1, o.mat or FIN.corridorFloor.mat, o.color or FIN.corridorFloor.color)
	if o.ceiling ~= false then
		ceiling(ctx, x0, z0, x1, z1)
	end
	local c = ceilOf(ctx)
	local alongX = (x1 - x0) >= (z1 - z0)
	local len = if alongX then x1 - x0 else z1 - z0
	local n = max(1, floor(len / (o.lightStep or 11)))
	local wear = ctx.rec.wear
	for i = 1, n do
		local t = (i - 0.5) / n
		local lx = if alongX then x0 + (x1 - x0) * t else (x0 + x1) / 2
		local lz = if alongX then (z0 + z1) / 2 else z0 + (z1 - z0) * t
		Core.ceilingLight(ctx.parent, ffl(ctx) * CF(lx, c - 0.18, lz), {
			size = V3(1.8, 0.12, 1.8),
			motion = o.motion ~= false,
			flicker = wear > 0.4 and ctx.rng:chance(wear * 0.35),
			group = "common",
			range = 18,
		})
	end
	if o.extinguisher ~= false then
		local ex = if alongX then V3(x0 + 2, 0, z1 - 0.6) else V3(x1 - 0.6, 0, z0 + 2)
		local box = Kit.box(ctx.parent, ffl(ctx), ex.X - 0.7, 1.0, ex.Z - 0.35, ex.X + 0.7, 3.6, ex.Z + 0.35, "SmoothPlastic", { 200, 30, 30 }, { name = "Hydrant", collide = false })
		Kit.text(box, if alongX then "front" else "left", "소화전", { color = { 255, 255, 255 }, ppS = 40, maxDist = 30 })
	end
	if o.cctv ~= false then
		Kit.ball(ctx.parent, ffl(ctx), x0 + 1.2, c - 0.5, z0 + 1.2, 0.8, "Glass", { 30, 30, 34 }, { collide = false, name = "CCTV", tr = 0.2 })
	end
end

-- facade entrance: a shell door + the hole in the facade
local function entrance(rec: any, fl: any, side: string, line: number, at: number, spec: any)
	local w = spec.w or 5
	local h = spec.h or 8
	local d = table.clone(spec)
	d.floor = fl.label
	d.side = side
	d.line = line
	d.at = at
	d.w = w - (if spec.kind == "auto" then 0 else 0.3)
	d.h = h
	table.insert(rec.doors, d)
	Plan.opening(fl, side, line, at - w / 2, at + w / 2, 0, h + 0.05, "door")
end

local function storefront(fl: any, side: string, line: number, a0: number, a1: number, y1: number, extra: any?)
	Plan.opening(fl, side, line, a0, a1, 0.5, y1, "storefront", extra)
end

-- repeated windows along a facade
local function windows(fl: any, side: string, line: number, a0: number, a1: number, width: number, gap: number, y0: number, y1: number, kind: string?, extra: any?)
	local x = a0
	while x + width <= a1 + 0.01 do
		Plan.opening(fl, side, line, x, x + width, y0, y1, kind or "window", extra)
		x += width + gap
	end
end

local function sign(rec: any, s: any)
	table.insert(rec.signs, s)
end

-- mailboxes grid on a wall: cf = world CFrame of the grid centre, -Z toward the reader
local function mailboxes(parent: Instance, cf: CFrame, cols: number, rows: number)
	local w, h = cols * 1.0, rows * 0.8
	Kit.part(parent, cf, V3(w + 0.3, h + 0.3, 0.8), "Metal", { 180, 182, 186 }, { name = "Mailboxes" })
	for c = 0, cols - 1 do
		for r = 0, rows - 1 do
			local p = Kit.part(parent, cf * CF(-w / 2 + 0.5 + c, -h / 2 + 0.4 + r * 0.8, -0.42), V3(0.9, 0.7, 0.05), "Metal", { 206, 208, 212 }, { name = "MailDoor", collide = false })
			if r == rows - 1 and c % 2 == 0 then
				p.Color = Color3.fromRGB(196, 198, 202)
			end
		end
	end
end

-- 무인택배함 (parcel lockers) + directory + bench used by several lobbies
local function lobbyKit(parent: Instance, cf: CFrame, rec: any)
	Kit.part(parent, cf * CF(0, 3.6, 0), V3(6, 7.2, 1.6), "Metal", { 60, 110, 180 }, { name = "ParcelLocker" })
	for c = 0, 4 do
		for r = 0, 3 do
			Kit.part(parent, cf * CF(-2.4 + c * 1.2, 1.2 + r * 1.6, -0.82), V3(1.1, 1.5, 0.05), "Metal", { 80, 140, 210 }, { name = "LockerDoor", collide = false })
		end
	end
	local scr = Kit.part(parent, cf * CF(0, 5.6, -0.84), V3(1.4, 1.0, 0.05), "Neon", { 40, 90, 160 }, { name = "LockerScreen", collide = false })
	Kit.text(scr, "front", "무인택배함", { color = { 255, 255, 255 }, ppS = 50, maxDist = 30 })
end

-- floor numbers of a storey list
local function labels(prefix: { string }, from: number, to: number): { string }
	local out = table.clone(prefix)
	for i = from, to do
		table.insert(out, i .. "F")
	end
	return out
end

local function typical(n: number, h: number, kind: string, rects: { any }, extra: any?): { any }
	local out = {}
	for i = 2, n do
		local f = { label = i .. "F", h = h, kind = kind, rects = rects, data = {} }
		if extra then
			for k, v in extra do
				f.data[k] = v
			end
		end
		table.insert(out, f)
	end
	return out
end

-- underground parking ramp in the lot (shell hook helper): retaining walls, sloped slab, ground hole
local function ramp(m: Instance, rec: any, x0: number, x1: number, zTop: number, zBottom: number, zEnd: number, depth: number)
	local f = rec.cf
	local wallC = Util.age(Color3.fromRGB(176, 174, 170), rec.wear)
	-- sloped driving surface (collides) + flat landing
	Kit.ramp(m, f, V3((x0 + x1) / 2, 0, zTop), V3((x0 + x1) / 2, -depth, zBottom), x1 - x0, { tr = 0, thick = 1, material = "Concrete", color = { 120, 120, 118 }, name = "RampSlab" })
	Kit.box(m, f, x0, -depth - 1, zBottom, x1, -depth, zEnd, "Concrete", { 120, 120, 118 }, { name = "RampLanding" })
	-- grooves (anti-slip) on the slope
	-- retaining walls
	Kit.box(m, f, x0 - 0.6, -depth - 1, zTop - 1, x0, 3.4, zEnd, "Concrete", wallC, { name = "RampWall" })
	Kit.box(m, f, x1, -depth - 1, zTop - 1, x1 + 0.6, 3.4, zEnd, "Concrete", wallC, { name = "RampWall" })
	Kit.box(m, f, x0, -depth - 1, zEnd, x1, 0, zEnd + 0.6, "Concrete", wallC, { name = "RampWall" })
	-- roof over the bottom part (the ramp dives under the ground slab)
	Kit.box(m, f, x0 - 0.6, -1, zBottom - 6, x1 + 0.6, 0, zEnd + 0.6, "Concrete", { 150, 150, 148 }, { name = "RampRoof" })
	-- entrance frame + clearance bar + sign
	local bar = Kit.box(m, f, x0, 7.6, zTop + 0.2, x1, 8.2, zTop + 0.6, "SmoothPlastic", { 250, 200, 30 }, { name = "HeightBar", collide = false })
	Kit.text(bar, "front", "높이 제한 2.3m  ·  지하주차장 입구", { color = { 30, 30, 30 }, ppS = 40, maxDist = 80 })
	Kit.box(m, f, x0 - 0.6, 3.4, zTop - 1, x0, 8.2, zTop - 0.4, "Metal", { 60, 60, 64 }, { name = "Post" })
	Kit.box(m, f, x1, 3.4, zTop - 1, x1 + 0.6, 8.2, zTop - 0.4, "Metal", { 60, 60, 64 }, { name = "Post" })
	for k = 0, 6 do
		local zz = zTop + (zBottom - zTop) * (k + 0.5) / 7
		local yy = -depth * (k + 0.5) / 7
		local lamp = Kit.box(m, f, x0 + 0.05, yy + 4.5, zz - 0.6, x0 + 0.25, yy + 4.9, zz + 0.6, "Neon", { 255, 220, 160 }, { name = "RampLight", collide = false })
		if k % 2 == 0 then
			Kit.light(lamp, "point", { color = { 255, 220, 160 }, brightness = 0.8, range = 12, attrs = { Group = "exterior" } })
		end
	end
	rec.groundHoles = rec.groundHoles or {}
	table.insert(rec.groundHoles, Plan.rect(x0 - 0.6, zTop - 1, x1 + 0.6, zEnd + 0.6))
	rec.carve = rec.carve or {}
	table.insert(rec.carve, { x0 - 1, -depth - 2, zTop - 1, x1 + 1, 4, zEnd + 1 })
end

-------------------------------------------------------------------------------------------------
-- 광안 오션뷰 아파트 (복도식, core in front, units behind the open corridor)
-------------------------------------------------------------------------------------------------
function A.apartment(def: any): any
	local W, D = 96, 55
	local rec = Plan.new({
		id = def.id,
		archetype = "apartment",
		name = def.name or "광안 오션뷰 아파트",
		nameEn = "GWANGAN OCEANVIEW APT.",
		cf = def.cf,
		seed = def.seed,
		wear = def.wear or 0.12,
		style = def.style or "modern_tile",
		W = W,
		D = D,
	})
	local nTyp = def.floors or 11 -- 2F .. (nTyp)F typical, then the penthouse storey
	local phLabel = (nTyp + 1) .. "F"
	local rCorr = Plan.rect(-48, 19, 48, 25)
	local rUnits = Plan.rect(-48, 25, 48, 55)
	local rCoreUp = Plan.rect(-15.6, 1.3, 14.8, 19)
	local rCore1 = Plan.rect(-15.6, 0, 14.8, 19)
	local floors = {
		{ label = "B1", h = 12, kind = "parking", rects = { Plan.rect(-48, 0, 48, 55) }, data = { band = false } },
		{ label = "1F", h = 11.5, kind = "lobby", rects = { rCore1, rCorr, rUnits }, data = { base = true } },
	}
	for _, f in typical(nTyp, RES, "res", { rCoreUp, rCorr, rUnits }) do
		table.insert(floors, f)
	end
	table.insert(floors, { label = phLabel, h = 12, kind = "penthouse", rects = { rCoreUp, rCorr, rUnits }, data = {} })
	Plan.floors(rec, floors)
	local all = { "B1", "1F" }
	for i = 2, nTyp + 1 do
		table.insert(all, i .. "F")
	end

	-- units ------------------------------------------------------------------------------------
	local MIXES = {
		{ "apt_1room", "apt_1room", "apt_1room", "apt_2room", "apt_2room" },
		{ "apt_2room", "apt_1room", "apt_1room", "apt_1room", "apt_2room" },
		{ "apt_2room", "apt_2room", "apt_1room", "apt_1room", "apt_1room" },
		{ "apt_3room", "apt_3room", "apt_3room" },
		{ "apt_3room", "apt_2room", "apt_2room", "apt_1room" },
		{ "apt_1room", "apt_2room", "apt_2room", "apt_3room" },
	}
	local phUnit = nil
	for _, fl in rec.floors do
		if fl.kind == "lobby" or fl.kind == "res" then
			local mix
			if fl.level <= 1 then
				mix = MIXES[1]
			elseif fl.level <= 4 then
				mix = MIXES[((fl.level - 2) % 3) + 1]
			elseif fl.level <= 8 then
				mix = MIXES[4]
			else
				mix = MIXES[5 + (fl.level % 2)]
			end
			local x = -48
			for i, tid in mix do
				local w = Shared.Homes.TEMPLATES[tid].w
				Units.add(rec, fl, {
					template = tid,
					number = string.format("%d%02d", fl.level, i),
					frame = Plan.frame(x, 0, 25, 0),
					mirror = (i + fl.level) % 2 == 0,
					view = if fl.level >= 5 then "ocean" else "city",
				})
				x += w
			end
		elseif fl.kind == "penthouse" then
			phUnit = Units.add(rec, fl, { template = "apt_penthouse", number = string.format("%d01", fl.level), frame = Plan.frame(-48, 0, 25, 0), view = "ocean" })
		end
	end

	-- core -------------------------------------------------------------------------------------
	local private = if phUnit then { [phLabel] = phUnit.id } else nil
	Plan.stair(rec, {
		x = -10.3,
		z = 19,
		rot = 180,
		floors = all,
		roof = true,
		private = private,
		extFn = function(label: string)
			if label == "B1" then
				return {}
			elseif label == "1F" then
				return { right = true }
			end
			return { right = true, far = true }
		end,
	})
	Plan.elevator(rec, { x = 9.9, z = 19, rot = 180, floors = all, name = "1호기", restricted = private })

	-- facade -------------------------------------------------------------------------------------
	for _, fl in rec.floors do
		if fl.kind == "res" or fl.kind == "lobby" then
			Plan.openEdge(fl, "-z", 19, -48, -15.6, "parapet")
			Plan.openEdge(fl, "-z", 19, 14.8, 48, "parapet")
		elseif fl.kind == "penthouse" then
			windows(fl, "-z", 19, -46.5, -17.5, 5, 1, 2.0, 9.6, "window", { curtain = false })
			windows(fl, "-z", 19, 16.5, 46, 5, 1, 2.0, 9.6, "window", { curtain = false })
		end
		if fl.kind ~= "parking" then
			-- corridor end windows
			Plan.opening(fl, "-x", -48, 20, 24, 3, 8, "window", { curtain = false, ac = false })
			Plan.opening(fl, "+x", 48, 20, 24, 3, 8, "window", { curtain = false, ac = false })
		end
		if fl.kind == "res" or fl.kind == "penthouse" then
			-- hall window over the street + stair window at the mid landing
			Plan.opening(fl, "-z", 1.3, -4, 4, 2.5, 8.5, "window", { curtain = false, ac = false, zone = "corridor" })
			Plan.opening(fl, "-z", 1.3, -14, -7, 6.2, 9.0, "window", { curtain = false, ac = false, zone = "corridor" })
		end
	end
	local f1 = rec.floorByLabel["1F"]
	entrance(rec, f1, "-z", 0, 0, { kind = "auto", w = 5.6, h = 8, canopy = "glass", id = rec.id .. "_lobby", signText = rec.name .. " 공동현관" })
	storefront(f1, "-z", 0, -4.6, -3.0, 9.6)
	storefront(f1, "-z", 0, 3.0, 4.6, 9.6)
	Plan.opening(f1, "-z", 0, 6.5, 13.5, 2.5, 8.5, "window", { curtain = false })
	Plan.opening(f1, "-z", 0, -14, -7, 6.0, 9.0, "window", { curtain = false, zone = "corridor" })
	-- B1 ramp opening (side wall)
	Plan.opening(rec.floorByLabel["B1"], "+x", 48, 39, 51, 0, 9.4, "void")
	sign(rec, { side = "-z", line = 1.3, at = 0, y = rec.roofY - 6.2, w = 26, h = 4.2, text = rec.name, sub = rec.nameEn, kind = "name", bg = { 40, 44, 52 }, fg = { 255, 255, 255 }, depth = 0.4 })
	sign(rec, { side = "+z", line = D, at = 0, y = rec.roofY - 5.5, w = 30, h = 4, text = "OCEAN VIEW 광안", kind = "name", bg = { 30, 60, 110 }, fg = { 255, 255, 255 }, depth = 0.4 })
	rec.roof.equipRect = { -46, 27, 46, 53 }

	-- hooks ------------------------------------------------------------------------------------
	rec.hooks.floor = function(ctx: any, fl: any)
		if fl.kind == "parking" then
			Core.parking(ctx.parent, ffl(ctx), -46.5, 21, 46.5, 54, fl.h, ctx.rng, { flicker = 0.06 })
			Core.parking(ctx.parent, ffl(ctx), 17, 1.5, 46.5, 18.5, fl.h, ctx.rng, { flicker = 0.06, cars = true })
			Core.parking(ctx.parent, ffl(ctx), -46.5, 1.5, -18, 18.5, fl.h, ctx.rng, { flicker = 0.06, cars = true })
			Core.plate(ctx.parent, ffl(ctx) * CF(0, 8, 24.8) * CFrame.Angles(0, 0, 0), 6, 1.2, "🛗 엘리베이터  ·  비상계단", { bg = { 40, 120, 60 }, fg = { 255, 255, 255 }, glow = true })
			floorFinish(ctx, -5, 19, 15, 25, "CeramicTiles", { 196, 192, 184 })
			return
		end
		-- corridor + hall
		corridor(ctx, -48, 19, 48, 25, { motion = fl.kind ~= "penthouse" })
		if fl.kind == "lobby" then
			-- lobby x -5..5, z 0..19 (auto door from the street), office in front of the elevator
			floorFinish(ctx, -5, 0, 5, 19, FIN.lobbyFloor.mat, FIN.lobbyFloor.color)
			ceiling(ctx, -5, 0, 5, 19)
			Core.ceilingLight(ctx.parent, ffl(ctx) * CF(0, ceilOf(ctx) - 0.18, 5), { size = V3(3, 0.12, 3), group = "common", brightness = 1.3 })
			Core.ceilingLight(ctx.parent, ffl(ctx) * CF(0, ceilOf(ctx) - 0.18, 13), { size = V3(3, 0.12, 3), group = "common", brightness = 1.3 })
			wallZ(ctx, 0, 1.6, -5.2, nil, { mat = "Marble", color = { 220, 214, 204 } })
			wallX(ctx, -15.4, -5.2, 1.5, nil)
			wallZ(ctx, 0, 10.4, 5.2, { { 5.5, 8.5, 0, Config.DOOR_H } }, { mat = "Marble", color = { 220, 214, 204 } })
			door(ctx, 5.2, 7, -90, { w = 2.8, kind = "swing", id = rec.id .. "_office", label = "관리사무소" })
			Core.plate(ctx.parent, ffl(ctx) * CF(4.95, 8.0, 7) * CFrame.Angles(0, rad(90), 0), 2.6, 0.7, "관리사무소", { bg = { 40, 44, 52 }, fg = { 255, 255, 255 } })
			mailboxes(ctx.parent, ffl(ctx) * CF(-4.75, 4.2, 10) * CFrame.Angles(0, rad(-90), 0), 8, 6)
			-- 공동현관 intercom
			local ic = Kit.box(ctx.parent, ffl(ctx), 2.9, 3.4, 1.2, 3.7, 5.2, 1.5, "SmoothPlastic", { 30, 30, 34 }, { name = "Intercom", collide = false })
			Kit.text(ic, "front", "▦\n호출", { color = { 120, 200, 255 }, ppS = 50, maxDist = 20 })
			lobbyKit(ctx.parent, ffl(ctx) * CF(-1.5, 0, 18.2) * CFrame.Angles(0, math.pi, 0), rec)
			-- office room (in front of the elevator)
			floorFinish(ctx, 5.4, 0, 14.8, 10.4, "CeramicTiles", { 200, 196, 188 })
			ceiling(ctx, 5.4, 0, 14.8, 10.4)
			Core.ceilingLight(ctx.parent, ffl(ctx) * CF(10, ceilOf(ctx) - 0.18, 5), { size = V3(2.4, 0.12, 2.4), group = "common" })
			local desk = Furniture.build("desk", ctx.parent, ffl(ctx) * CF(10, 0, 3) * CFrame.Angles(0, 0, 0), 3)
			Furniture.build("bookshelf", ctx.parent, ffl(ctx) * CF(14.0, 0, 6) * CFrame.Angles(0, rad(90), 0), 3)
			local nb = Kit.box(ctx.parent, ffl(ctx), 6, 4.2, 10.0, 13, 8.4, 10.1, "SmoothPlastic", { 250, 250, 246 }, { name = "Notice", collide = false })
			Kit.text(nb, "front", "📢 관리사무소\n· 분리배출: 매주 수요일\n· 승강기 점검: 둘째 주 화요일\n· 펜트하우스 층은 입주민 전용", { color = { 30, 30, 34 }, ppS = 30, align = "left", bold = false, maxDist = 30 })
			local _ = desk
		else
			-- elevator hall (x -5..5, z 1.3..19) open to the corridor, window to the street
			floorFinish(ctx, -5, 1.3, 5, 19, FIN.corridorFloor.mat, FIN.corridorFloor.color)
			ceiling(ctx, -5, 1.3, 5, 19)
			Core.ceilingLight(ctx.parent, ffl(ctx) * CF(0, ceilOf(ctx) - 0.18, 10), { size = V3(2, 0.12, 2), group = "common", motion = fl.kind ~= "penthouse" })
			wallZ(ctx, 1.3, 10.4, 5.2, nil)
			Core.plate(ctx.parent, ffl(ctx) * CF(4.95, 6, 6) * CFrame.Angles(0, rad(90), 0), 2.6, 1.6, Core.shortLabel(fl.label) .. "층", { bg = { 40, 44, 52 }, fg = { 255, 255, 255 }, ppS = 50 })
			if fl.kind == "penthouse" then
				Core.plate(ctx.parent, ffl(ctx) * CF(0, 7.4, 24.7) * CFrame.Angles(0, 0, 0), 5, 1.0, "PENTHOUSE  " .. (phUnit and phUnit.label or ""), { bg = { 20, 20, 24 }, fg = { 220, 190, 120 } })
			end
		end
	end
	rec.hooks.furnish = function(ctx: any, fl: any, into: Instance)
		if fl.kind == "lobby" then
			Furniture.build("monstera", into, ffl(ctx) * CF(3.6, 0, 16.6), 1)
			Furniture.build("sofa3", into, ffl(ctx) * CF(-3.0, 0, 14.6) * CFrame.Angles(0, rad(-90), 0), 2, { Public = true })
		elseif fl.kind == "res" then
			if ctx.rng:chance(0.5) then
				Furniture.build("monstera", into, ffl(ctx) * CF(3.8, 0, 2.6), 2)
			end
		end
	end
	rec.hooks.shell = function(m: Instance, r: any, rng: any)
		ramp(m, r, 49, 58, 3, 39, 51, 12)
		-- connect the ramp landing to the B1 opening (driveway through the wall)
		Kit.box(m, r.cf, 47.6, -13, 39, 49, -12, 51, "Concrete", { 120, 120, 118 }, { name = "RampThreshold" })
		-- forecourt planters + bike rack
		for _, px in { -24, 24 } do
			Kit.box(m, r.cf, px - 6, 0, -4.5, px + 6, 1.6, -1.5, "Granite", { 110, 108, 104 }, { name = "Planter" })
			Kit.box(m, r.cf, px - 5.7, 1.6, -4.2, px + 5.7, 2.2, -1.8, "LeafyGrass", { 70, 130, 70 }, { name = "Shrubs", collide = false })
		end
	end
	return rec
end

-------------------------------------------------------------------------------------------------
-- 해오름 오피스텔 (double-loaded corridor, 1F GW25 + security lobby)
-------------------------------------------------------------------------------------------------
function A.officetel(def: any): any
	local W, D = 42, 46
	local rec = Plan.new({ id = def.id, archetype = "officetel", name = def.name or "해오름 오피스텔", nameEn = "HAEOREUM OFFICETEL", cf = def.cf, seed = def.seed, wear = def.wear or 0.05, style = def.style or "curtain_glass", W = W, D = D })
	local nTop = def.floors or 9
	local all = Plan.rect(-21, 0, 21, 46)
	local floors = { { label = "1F", h = 13, kind = "lobby", rects = { all }, data = { base = true } } }
	for _, f in typical(nTop, RES, "res", { all }) do
		table.insert(floors, f)
	end
	Plan.floors(rec, floors)
	local labelsAll = labels({}, 1, nTop)
	Plan.stair(rec, { x = 15.5, z = 26, rot = 0, floors = labelsAll, roof = true })
	Plan.elevator(rec, { x = 5.3, z = 26, rot = 0, floors = labelsAll, name = "1호기" })
	for _, fl in rec.floors do
		if fl.kind == "res" then
			for i = 0, 2 do
				local x0 = -21 + i * 14
				local mir = (i + fl.level) % 2 == 0
				Units.add(rec, fl, { template = "officetel_a", number = string.format("%d%02d", fl.level, i + 1), frame = Plan.frame(x0 + 14, 0, 20, 180), mirror = mir, view = "city", windowKind = "curtain" })
			end
			Units.add(rec, fl, { template = "officetel_b", number = string.format("%d04", fl.level), frame = Plan.frame(-21, 0, 26, 0), mirror = fl.level % 2 == 0, view = "ocean", windowKind = "curtain" })
			Plan.opening(fl, "-x", -21, 21, 25, 2, 8, "window", { curtain = false, zone = "corridor" })
			Plan.opening(fl, "+x", 21, 21, 25, 2, 8, "window", { curtain = false, zone = "corridor" })
		end
	end
	local f1 = rec.floorByLabel["1F"]
	Plan.shop(rec, f1, { kind = "cvs", name = "GW25 해오름점", frame = Plan.frame(-21, 0, 0, 0), w = 28, d = 20, id = rec.id .. "_cvs" })
	Plan.shop(rec, f1, { kind = "office", name = "관리실 · 택배보관", frame = Plan.frame(-21, 0, 26, 0), w = 20, d = 20, id = rec.id .. "_office" })
	entrance(rec, f1, "-z", 0, 3, { kind = "auto", w = 5, h = 8, id = rec.id .. "_cvsdoor", shopId = rec.id .. "_cvs" })
	storefront(f1, "-z", 0, -20.2, 0.2, 10.4)
	entrance(rec, f1, "-z", 0, 14, { kind = "auto", w = 5.6, h = 8.4, canopy = "metal", id = rec.id .. "_lobby", signText = "해오름 오피스텔" })
	storefront(f1, "-z", 0, 7.8, 11, 10.4)
	storefront(f1, "-z", 0, 17, 20.2, 10.4)
	sign(rec, { side = "-z", at = -7, y = 10.6, w = 24, h = 1.9, text = "GW25", sub = nil, bg = { 0, 120, 200 }, fg = { 255, 255, 255 }, depth = 0.5, ppS = 30 })
	sign(rec, { side = "-z", at = 20.3, y = 18, w = 3.4, h = 30, text = "해\n오\n름\n오\n피\n스\n텔", kind = "vertical", bg = { 20, 30, 50 }, fg = { 120, 220, 255 } })
	sign(rec, { side = "-z", at = 0, y = rec.roofY - 3.6, w = 22, h = 3.0, text = "HAEOREUM", kind = "name", bg = { 20, 20, 24 }, fg = { 140, 220, 255 }, depth = 0.4 })

	rec.hooks.floor = function(ctx: any, fl: any)
		corridor(ctx, -21, 20, 21, 26, { lightStep = 9 })
		-- filler between the back unit and the elevator shaft
		wallX(ctx, -1.3, 0.6, 26, nil)
		if fl.kind == "lobby" then
			-- CVS / lobby partition, CVS back wall, security lobby
			wallZ(ctx, 0, 20, 7, nil, { mat = "Marble", color = { 210, 206, 198 } })
			wallX(ctx, -21, 7, 20, { { -12, -9.2, 0, Config.DOOR_H } })
			door(ctx, -10.6, 20, 180, { w = 2.6, kind = "swing", lock = "staff", id = rec.id .. "_cvsback", label = "직원 전용" })
			floorFinish(ctx, 7.2, 0, 21, 20, FIN.lobbyFloor.mat, FIN.lobbyFloor.color)
			ceiling(ctx, 7.2, 0, 21, 20)
			for _, z in { 5, 14 } do
				Core.ceilingLight(ctx.parent, ffl(ctx) * CF(14, ceilOf(ctx) - 0.18, z), { size = V3(3.4, 0.12, 3.4), group = "common", brightness = 1.3 })
			end
			mailboxes(ctx.parent, ffl(ctx) * CF(7.6, 4.2, 12) * CFrame.Angles(0, rad(-90), 0), 8, 5)
			-- security gate (speed gate look) + guard desk
			for _, gx in { 11, 14, 17 } do
				Kit.box(ctx.parent, ffl(ctx), gx - 0.3, 0, 8, gx + 0.3, 3.4, 10, "Metal", { 200, 202, 206 }, { name = "GatePost" })
				Kit.box(ctx.parent, ffl(ctx), gx - 0.32, 3.0, 8.2, gx + 0.32, 3.3, 9.8, "Neon", { 60, 200, 120 }, { name = "GateLight", collide = false })
			end
			Shops.counterLike(ctx.parent, ffl(ctx), 17.5, 2, 20.6, 5.5)
			lobbyKit(ctx.parent, ffl(ctx) * CF(10.5, 0, 19.2) * CFrame.Angles(0, math.pi, 0), rec)
			-- office door on the corridor
			wallX(ctx, -21, -1, 26, { { -12.5, -9.5, 0, Config.DOOR_H } })
			door(ctx, -11, 26, 0, { w = 2.8, kind = "swing", id = rec.id .. "_officedoor", label = "관리실" })
		end
	end
	rec.hooks.furnish = function(ctx: any, fl: any, into: Instance)
		if fl.kind == "lobby" then
			Shops.staffRef(into, ffl(ctx) * CF(19, 0, 5.8) * CFrame.Angles(0, rad(-90), 0), { name = "보안요원", top = { 30, 34, 50 }, pants = { 30, 34, 50 }, hat = { 30, 34, 50 } })
			Furniture.build("monstera", into, ffl(ctx) * CF(19.6, 0, 18), 2)
		end
	end
	rec.hooks.shell = function(m: Instance, r: any, rng: any)
		-- rooftop garden: deck, planters, benches, string lights
		local f = r.cf * CF(0, r.roofY, 0)
		Kit.box(m, f, -19, 0, 2, 9, 0.3, 24, "WoodPlanks", { 150, 116, 84 }, { name = "Deck" })
		for i = 0, 3 do
			Kit.box(m, f, -18 + i * 7, 0.3, 21, -14 + i * 7, 2.0, 23.5, "Wood", { 120, 90, 66 }, { name = "Planter" })
			Kit.box(m, f, -17.8 + i * 7, 2.0, 21.2, -14.2 + i * 7, 3.2, 23.3, "LeafyGrass", { 70, 140, 80 }, { name = "Plants", collide = false })
		end
		for i = 0, 2 do
			Furniture.build("sunbed", m, f * CF(-14 + i * 6, 0.3, 10) * CFrame.Angles(0, math.pi, 0), 2, { Public = true })
		end
		for k = 0, 8 do
			local b = Kit.ball(m, f, -18 + k * 3.3, 7 + math.sin(k) * 0.3, 2.5, 0.35, "Neon", { 255, 214, 150 }, { collide = false, name = "Bulb" })
			b:SetAttribute("NightGlow", true)
		end
	end
	return rec
end

-------------------------------------------------------------------------------------------------
-- 광안하우스 빌라 (필로티 + 계단실형 2세대 + 옥탑방)
-------------------------------------------------------------------------------------------------
function A.villa(def: any): any
	local W, D = 58.6, 26
	local rec = Plan.new({ id = def.id, archetype = "villa", name = def.name or "광안하우스", nameEn = "GWANGAN HOUSE", cf = def.cf, seed = def.seed, wear = def.wear or 0.45, style = def.style or "red_brick", W = W, D = D, lobbyLabel = "G" })
	local nTop = def.floors or 5
	local all = Plan.rect(-29.3, 0, 29.3, 26)
	local floors = { { label = "G", h = 9, kind = "pilotis", rects = { all }, data = { pilotis = true, band = false } } }
	for _, f in typical(nTop, 10, "res", { all }) do
		table.insert(floors, f)
	end
	Plan.floors(rec, floors)
	local stairFloors = labels({ "G" }, 2, nTop)
	local noDoor = {}
	for i = 2, nTop do
		noDoor[i .. "F"] = true
	end
	Plan.stair(rec, {
		x = 0,
		z = 0,
		rot = 0,
		floors = stairFloors,
		roof = true,
		roofDoor = "right",
		noDoor = noDoor,
		door = "swing",
		style = "stone",
		extFn = function(label: string)
			if label == "G" then
				return {}
			end
			return { entry = true, left = true, right = true }
		end,
	})
	for _, fl in rec.floors do
		if fl.kind == "res" then
			local leftT = if fl.level % 2 == 0 then "villa_2room" else "villa_3room"
			local rightT = if fl.level % 2 == 0 then "villa_3room" else "villa_2room"
			Units.add(rec, fl, { template = leftT, number = string.format("%d01", fl.level), frame = Plan.frame(-5.3, 0, 0, -90), view = "street" })
			Units.add(rec, fl, { template = rightT, number = string.format("%d02", fl.level), frame = Plan.frame(5.3, 0, 26, 90), mirror = true, view = "street" })
			Plan.opening(fl, "-z", 0, -3, 3, 3.2, 7.6, "window", { curtain = false, ac = false, zone = "corridor" })
		end
	end
	-- 옥탑방 on the roof: a pseudo storey that is not part of the facade stack
	local rf = { index = #rec.floors + 1, label = "RF", level = nTop + 1, y = rec.roofY, h = 9.6, kind = "rooftop", rects = {}, holes = {}, openings = {}, open = {}, units = {}, shops = {}, rooms = {}, doors = {}, ceiling = 8.6, data = {} }
	rec.extraFloors = { rf }
	rec.floorByLabel.RF = rf
	local roofUnit = Units.add(rec, rf, { template = "villa_rooftop", number = "옥탑", frame = Plan.frame(8, 0, 6, 0), view = "ocean" })
	roofUnit.shellBuilt = true
	-- G entrance (공동현관) is the stair's own door; signs
	sign(rec, { side = "-z", at = -14, y = rec.roofY - 0.2, w = 22, h = 3.2, text = rec.name, kind = "name", bg = { 236, 230, 214 }, fg = { 120, 50, 40 }, depth = 0.3, glow = false })
	sign(rec, { side = "-z", at = 8.5, y = 6.2, w = 5, h = 1.0, text = "광안로 123번길 7", bg = { 30, 70, 140 }, fg = { 255, 255, 255 }, depth = 0.15, glow = false })

	rec.hooks.floor = function(ctx: any, fl: any)
		if fl.kind == "pilotis" then
			floorFinish(ctx, -29, 0, 29, 26, "Concrete", { 140, 140, 138 })
			-- painted stalls
			for i = 0, 4 do
				local sx = -28 + i * 5.4
				Kit.box(ctx.parent, ffl(ctx), sx - 0.08, 0.06, 2, sx + 0.08, 0.08, 12, "SmoothPlastic", { 250, 250, 246 }, { collide = false, name = "Line" })
				Kit.box(ctx.parent, ffl(ctx), -sx - 0.08, 0.06, 2, -sx + 0.08, 0.08, 12, "SmoothPlastic", { 250, 250, 246 }, { collide = false, name = "Line" })
			end
			Core.ceilingLight(ctx.parent, ffl(ctx) * CF(-15, ceilOf(ctx) - 0.1, 10), { size = V3(2, 0.12, 2), group = "common", flicker = true })
			Core.ceilingLight(ctx.parent, ffl(ctx) * CF(15, ceilOf(ctx) - 0.1, 10), { size = V3(2, 0.12, 2), group = "common" })
			-- 분리수거장 corner
			Kit.box(ctx.parent, ffl(ctx), 22, 0, 20, 28.8, 4, 25.6, "SmoothPlastic", { 40, 120, 70 }, { name = "RecycleBins" })
			Core.plate(ctx.parent, ffl(ctx) * CF(25.4, 5, 19.9), 6, 1, "분리수거장", { bg = { 40, 120, 70 }, fg = { 255, 255, 255 } })
			mailboxes(ctx.parent, ffl(ctx) * CF(-8.2, 4.2, 1.0), 4, 3)
		else
			-- stair landing finish
			floorFinish(ctx, -4.9, 0, 4.9, 4.4, "Granite", { 120, 116, 112 })
		end
	end
	rec.hooks.shell = function(m: Instance, r: any, rng: any)
		-- 옥탑방 shell: brick box with windows, roof, door; laundry lines + rubber-tub garden on the roof
		local u = roofUnit
		local L = u.layout
		local f = r.cf * CF(0, r.roofY, 0) * u.frame
		local H = 8.6
		local col = Util.age(r.tone.wall, r.wear)
		local winY0, winY1 = 2.8, 7.4
		local function holes(edge: string): { any }
			local hs = {}
			for _, wn in L.windows do
				if wn.edge == edge then
					table.insert(hs, { wn.a0, wn.a1, winY0, winY1 })
				end
			end
			return hs
		end
		local entry = holes("entry")
		table.insert(entry, { L.door - 1.7, L.door + 1.7, 0, Config.DOOR_H + 0.1 })
		Kit.wallX(m, f, -0.4, L.w + 0.4, 0, 0.8, 0, H, entry, r.style.wall.mat, col)
		Kit.wallX(m, f, -0.4, L.w + 0.4, L.d, 0.8, 0, H, holes("far"), r.style.wall.mat, col)
		Kit.wallZ(m, f, 0, L.d, 0, 0.8, 0, H, holes("left"), r.style.wall.mat, col)
		Kit.wallZ(m, f, 0, L.d, L.w, 0.8, 0, H, holes("right"), r.style.wall.mat, col)
		Kit.box(m, f, -0.8, H, -0.8, L.w + 0.8, H + 0.6, L.d + 0.8, "Metal", { 60, 110, 160 }, { name = "PanelRoof" })
		for _, wn in L.windows do
			local p0 = if wn.edge == "far" then V3(wn.a0, 0, L.d) elseif wn.edge == "left" then V3(0, 0, wn.a0) else V3(L.w, 0, wn.a0)
			local p1 = if wn.edge == "far" then V3(wn.a1, 0, L.d) elseif wn.edge == "left" then V3(0, 0, wn.a1) else V3(L.w, 0, wn.a1)
			local mid = (p0 + p1) / 2
			local yaw = if wn.edge == "far" then 0 else 90
			local g = Kit.part(m, f * CF(mid.X, (winY0 + winY1) / 2, mid.Z) * CFrame.Angles(0, rad(yaw), 0), V3((p1 - p0).Magnitude, winY1 - winY0, 0.15), "Glass", r.style.glass.color, { tr = r.style.glass.tr, name = "Glass" })
			g:SetAttribute("LitChance", 0.8)
			g:SetAttribute("Zone", "home")
			CollectionService:AddTag(g, "NightWindow")
		end
		local d = Core.door(m, f * CF(L.door, 0, 0), { w = 3.2, h = Config.DOOR_H, t = 0.8, kind = "unit", lock = "unit", unitId = u.id, number = "옥탑", bell = true, autoClose = Config.DOOR_UNIT_CLOSE, id = "u_" .. u.id, swing = "front" })
		d:SetAttribute("Entrance", true)
		u.doorModel = d
		-- laundry line + rubber tubs with peppers (고추 화분)
		local rf0 = r.cf * CF(0, r.roofY, 0)
		Kit.rod(m, rf0, V3(-26, 5.5, 20), V3(-8, 5.5, 20), 0.06, "Metal", { 200, 200, 200 }, { collide = false })
		for i = 0, 5 do
			Kit.box(m, rf0, -24 + i * 3, 3.0, 19.9, -22.6 + i * 3, 5.4, 20.1, "Fabric", ({ { 240, 240, 236 }, { 60, 90, 150 }, { 220, 120, 120 } })[(i % 3) + 1], { collide = false, name = "Laundry" })
		end
		for i = 0, 3 do
			Kit.vcyl(m, rf0, -24 + i * 4, 0.8, 8, 1.6, 2.6, "Rubber", { 30, 30, 30 }, { name = "Tub" })
			Kit.vcyl(m, rf0, -24 + i * 4, 2.2, 8, 1.4, 2.2, "LeafyGrass", { 60, 130, 60 }, { name = "Pepper", collide = false })
		end
	end
	return rec
end

-------------------------------------------------------------------------------------------------
-- 해변 원룸텔 (필로티 + 중복도 원룸 4세대)
-------------------------------------------------------------------------------------------------
function A.oneroom(def: any): any
	local W, D = 50, 51.2
	local rec = Plan.new({ id = def.id, archetype = "oneroom", name = def.name or "해변 원룸텔", nameEn = "BEACH ONEROOM", cf = def.cf, seed = def.seed, wear = def.wear or 0.65, style = def.style or "old_tile", W = W, D = D, lobbyLabel = "G" })
	local nTop = def.floors or 5
	local rBlock = Plan.rect(-25, 0, 25, 28)
	local rCore = Plan.rect(-11, 28, 11, 51.2)
	local floors = {
		{
			label = "G",
			h = 9,
			kind = "pilotis",
			rects = { rBlock, rCore },
			data = {
				pilotis = true,
				band = false,
				walls = {
					{ side = "-x", line = -11, a0 = 28, a1 = 51.2 },
					{ side = "+x", line = 11, a0 = 28, a1 = 51.2 },
					{ side = "+z", line = 51.2, a0 = -11, a1 = 11 },
					{ side = "-z", line = 28, a0 = -11, a1 = 11 },
				},
			},
		},
	}
	for _, f in typical(nTop, RES, "res", { rBlock, rCore }) do
		table.insert(floors, f)
	end
	Plan.floors(rec, floors)
	local all = labels({ "G" }, 2, nTop)
	Plan.elevator(rec, { x = -5.3, z = 34, rot = 0, floors = all, name = "소형 승강기" })
	Plan.stair(rec, { x = 4.9, z = 34, rot = 0, floors = all, roof = true })
	local fG = rec.floorByLabel.G
	entrance(rec, fG, "-z", 28, 0, { kind = "glass", w = 5, h = 7.6, id = rec.id .. "_entry", signText = rec.name })
	storefront(fG, "-z", 28, -10, -2.6, 7.6)
	storefront(fG, "-z", 28, 2.6, 10, 7.6)
	for _, fl in rec.floors do
		if fl.kind == "res" then
			local n = 0
			for side = -1, 1, 2 do
				for k = 0, 1 do
					n += 1
					local z0 = k * 14
					local frame = if side < 0 then Plan.frame(-3, 0, z0, -90) else Plan.frame(3, 0, z0 + 14, 90)
					Units.add(rec, fl, { template = "oneroom_studio", number = string.format("%d%02d", fl.level, n), frame = frame, mirror = side > 0, view = if side < 0 then "city" else "ocean" })
				end
			end
			Plan.opening(fl, "-z", 0, -2, 2, 3, 8, "window", { curtain = false, ac = false, zone = "corridor" })
		end
	end
	sign(rec, { side = "-z", at = 19, y = 14, w = 3.2, h = 24, text = "해\n변\n원\n룸\n텔", kind = "vertical", bg = { 230, 230, 220 }, fg = { 200, 40, 40 } })
	sign(rec, { side = "-z", at = -13, y = 9.6, w = 16, h = 2.4, text = "풀옵션 원룸 임대 ☎ 051-753-0000", bg = { 250, 240, 120 }, fg = { 200, 30, 30 }, depth = 0.1, glow = false })

	rec.hooks.floor = function(ctx: any, fl: any)
		if fl.kind == "pilotis" then
			floorFinish(ctx, -25, 0, 25, 28, "Concrete", { 132, 132, 130 })
			for i = 0, 3 do
				for _, sx in { -1, 1 } do
					local z = 2 + i * 6.4
					Kit.box(ctx.parent, ffl(ctx), sx * 4, 0.06, z - 0.08, sx * 23, 0.08, z + 0.08, "SmoothPlastic", { 250, 250, 246 }, { collide = false, name = "Line" })
				end
			end
			-- hall (inside the glass entrance) + mailboxes
			corridor(ctx, -10.6, 28.4, 10.6, 34, { extinguisher = true })
			mailboxes(ctx.parent, ffl(ctx) * CF(-10.3, 4.0, 31) * CFrame.Angles(0, rad(-90), 0), 5, 4)
			Core.ceilingLight(ctx.parent, ffl(ctx) * CF(0, ceilOf(ctx) - 0.1, 14), { size = V3(2, 0.12, 2), group = "common", flicker = true })
			return
		end
		corridor(ctx, -3, 0, 3, 28, { lightStep = 9 })
		corridor(ctx, -11, 28, 11, 34, { extinguisher = false })
		-- hall side walls between the unit block and the core
		wallX(ctx, -11, -3, 28, nil)
		wallX(ctx, 3, 11, 28, nil)
	end
	rec.hooks.shell = function(m: Instance, r: any, rng: any)
		-- laundry + old satellite dish on the roof, posters at the entrance
		local f = r.cf * CF(0, r.roofY, 0)
		Kit.rod(m, f, V3(-20, 5.5, 4), V3(-4, 5.5, 4), 0.06, "Metal", { 200, 200, 200 }, { collide = false })
		for i = 0, 4 do
			Kit.box(m, f, -19 + i * 3, 3.2, 3.9, -17.5 + i * 3, 5.4, 4.1, "Fabric", ({ { 240, 240, 236 }, { 200, 200, 120 }, { 120, 160, 200 } })[(i % 3) + 1], { collide = false, name = "Laundry" })
		end
		local fg = r.cf
		for i = 0, 2 do
			local p = Kit.box(m, fg, -9 + i * 2.6, 3.6, 27.55, -7.2 + i * 2.6, 6.0, 27.6, "SmoothPlastic", { 250, 250, 246 }, { name = "Poster", collide = false })
			Kit.text(p, "front", ({ "원룸\n임대", "치킨\n배달", "분실물\n찾아요" })[i + 1], { color = { 30, 30, 30 }, ppS = 40, bold = false, maxDist = 20 })
		end
	end
	return rec
end

-------------------------------------------------------------------------------------------------
-- 광안 프라자 (근린생활시설 상가)
-------------------------------------------------------------------------------------------------
function A.plaza(def: any): any
	local W, D = 48, 51.2
	local rec = Plan.new({ id = def.id, archetype = "plaza", name = def.name or "광안 프라자", nameEn = "GWANGAN PLAZA", cf = def.cf, seed = def.seed, wear = def.wear or 0.35, style = def.style or "commercial", W = W, D = D })
	local all = Plan.rect(-24, 0, 24, 51.2)
	Plan.floors(rec, {
		{ label = "1F", h = 13, kind = "lobby", rects = { all }, data = { base = true } },
		{ label = "2F", h = 12, kind = "com", rects = { all }, data = {} },
		{ label = "3F", h = 12, kind = "com", rects = { all }, data = {} },
		{ label = "4F", h = 12, kind = "com", rects = { all }, data = {} },
	})
	local fl4 = { "1F", "2F", "3F", "4F" }
	Plan.stair(rec, { x = -18.5, z = 32, rot = 0, floors = fl4, roof = true })
	Plan.elevator(rec, { x = -8.1, z = 32, rot = 0, floors = fl4, name = "승강기" })
	local f1 = rec.floorByLabel["1F"]
	Plan.shop(rec, f1, { kind = "gukbap", name = "부산 돼지국밥", frame = Plan.frame(-24, 0, 0, 0), w = 22, d = 26, id = rec.id .. "_gukbap" })
	Plan.shop(rec, f1, { kind = "realtor", name = "광안 공인중개사", frame = Plan.frame(6, 0, 0, 0), w = 18, d = 26, id = rec.id .. "_realtor" })
	local upper = { ["2F"] = { "pcbang", "GWANGAN PC방" }, ["3F"] = { "karaoke", "광안 코인노래연습장" }, ["4F"] = { "billiards", "광안 당구클럽" } }
	for label, s in upper do
		Plan.shop(rec, rec.floorByLabel[label], { kind = s[1], name = s[2], frame = Plan.frame(24, 0, 26, 180), w = 48, d = 26, id = rec.id .. "_" .. s[1] })
	end
	-- facade
	entrance(rec, f1, "-z", 0, -18, { kind = "glass", w = 5, h = 8, id = rec.id .. "_gukbapdoor", shopId = rec.id .. "_gukbap" })
	storefront(f1, "-z", 0, -23, -20.6, 9.6)
	storefront(f1, "-z", 0, -15.4, -3, 9.6)
	entrance(rec, f1, "-z", 0, 2, { kind = "auto", w = 5, h = 8, canopy = "metal", id = rec.id .. "_entry", signText = "광안 프라자" })
	entrance(rec, f1, "-z", 0, 10, { kind = "glass", w = 4.4, h = 8, id = rec.id .. "_realtordoor", shopId = rec.id .. "_realtor" })
	storefront(f1, "-z", 0, 12.4, 23, 9.6)
	for _, label in { "2F", "3F", "4F" } do
		local fl = rec.floorByLabel[label]
		windows(fl, "-z", 0, -23, 23, 6.8, 0.4, 1.6, 8.8, "window", { curtain = false, ac = false, zone = "shop", lit = 1 })
		Plan.opening(fl, "-x", -24, 2, 24, 2.4, 8.8, "window", { curtain = false, ac = false, zone = "shop", lit = 1 })
	end
	sign(rec, { side = "-z", at = -12.8, y = 9.9, w = 21, h = 2.4, text = "🍲 부산 돼지국밥  24시", bg = { 200, 30, 40 }, fg = { 255, 255, 255 }, depth = 0.5 })
	sign(rec, { side = "-z", at = 15, y = 9.9, w = 17, h = 2.4, text = "🏠 광안 공인중개사", bg = { 20, 70, 160 }, fg = { 255, 255, 255 }, depth = 0.5 })
	local y2, y3, y4 = rec.floorByLabel["2F"].y, rec.floorByLabel["3F"].y, rec.floorByLabel["4F"].y
	sign(rec, { side = "-z", at = 0, y = y2 + 9.3, w = 46, h = 1.6, text = "🎮 GWANGAN PC방 · 최신 RTX · 24H", bg = { 30, 20, 60 }, fg = { 180, 140, 255 }, depth = 0.4, ppS = 30 })
	sign(rec, { side = "-z", at = 0, y = y3 + 9.3, w = 46, h = 1.6, text = "🎤 코인노래연습장 · 1곡 500원", bg = { 120, 20, 90 }, fg = { 255, 220, 250 }, depth = 0.4, ppS = 30 })
	sign(rec, { side = "-z", at = 0, y = y4 + 9.3, w = 46, h = 1.6, text = "🎱 광안 당구클럽 · 4구 · 3구", bg = { 20, 90, 50 }, fg = { 220, 255, 220 }, depth = 0.4, ppS = 30 })
	sign(rec, { side = "-z", at = 23.6, y = 13, w = 3.4, h = 34, text = "P\nC\n방\n·\n노\n래\n방\n·\n당\n구\n장", kind = "vertical", bg = { 250, 210, 40 }, fg = { 30, 30, 30 } })
	sign(rec, { side = "-z", at = 0, y = rec.roofY + 1.2, w = 30, h = 5, text = "광안 프라자", kind = "roof", bg = { 20, 20, 24 }, fg = { 255, 200, 60 }, depth = 0.6, offset = -1.0 })

	rec.hooks.floor = function(ctx: any, fl: any)
		local ceil = ceilOf(ctx)
		corridor(ctx, -24, 26, 24, 32, { lightStep = 10 })
		-- restrooms: M x -2.8..10.4, F x 10.4..24 (z 32..51.2)
		wallZ(ctx, 32, 51.2, -3.0, nil)
		wallZ(ctx, 32, 51.2, 10.4, nil)
		wallX(ctx, -3.2, 24, 32, { { 2.3, 5.1, 0, Config.DOOR_H }, { 15.9, 18.7, 0, Config.DOOR_H } })
		door(ctx, 3.7, 32, 0, { w = 2.6, kind = "swing", id = rec.id .. "_" .. fl.label .. "_wcm", label = "남자 화장실" })
		door(ctx, 17.3, 32, 0, { w = 2.6, kind = "swing", id = rec.id .. "_" .. fl.label .. "_wcf", label = "여자 화장실" })
		Core.plate(ctx.parent, ffl(ctx) * CF(3.7, 8.0, 31.75), 2.4, 0.8, "🚹 남자", { bg = { 30, 80, 180 }, fg = { 255, 255, 255 } })
		Core.plate(ctx.parent, ffl(ctx) * CF(17.3, 8.0, 31.75), 2.4, 0.8, "🚺 여자", { bg = { 200, 50, 90 }, fg = { 255, 255, 255 } })
		Core.restroom(ctx.parent, ffl(ctx) * CF(-2.8, 0, 32), 13.2, 19.2, fl.h - Config.SLAB, "m", { id = rec.id .. fl.label, flicker = rec.wear > 0.3 })
		Core.restroom(ctx.parent, ffl(ctx) * CF(10.6, 0, 32), 13.2, 19.2, fl.h - Config.SLAB, "f", { id = rec.id .. fl.label })
		-- floor guide at the elevator
		local guide = { ["1F"] = "1F 국밥 · 부동산", ["2F"] = "2F PC방", ["3F"] = "3F 노래연습장", ["4F"] = "4F 당구클럽" }
		Core.plate(ctx.parent, ffl(ctx) * CF(-8.1, 9.0, 31.5), 6, 1.2, guide[fl.label] or fl.label, { bg = { 30, 30, 34 }, fg = { 255, 230, 120 } })
		if fl.label == "1F" then
			-- bay walls + the entrance passage x -2..6
			wallZ(ctx, 0, 26, -2, nil, { mat = "Granite", color = { 90, 88, 86 } })
			wallZ(ctx, 0, 26, 6, nil, { mat = "Granite", color = { 90, 88, 86 } })
			wallX(ctx, -24, -2, 26, nil)
			wallX(ctx, 6, 24, 26, nil)
			corridor(ctx, -1.8, 0, 5.8, 26, { extinguisher = false })
			local dir = Kit.box(ctx.parent, ffl(ctx), -1.75, 3, 12, -1.7, 9, 18, "SmoothPlastic", { 30, 30, 34 }, { name = "Directory", collide = false })
			Kit.text(dir, "right", "층별 안내\n\n4F 🎱 광안 당구클럽\n3F 🎤 코인노래연습장\n2F 🎮 GWANGAN PC방\n1F 🍲 부산 돼지국밥\n1F 🏠 광안 공인중개사", { color = { 255, 230, 160 }, ppS = 30, align = "left", maxDist = 40 })
			mailboxes(ctx.parent, ffl(ctx) * CF(5.75, 4.2, 18) * CFrame.Angles(0, rad(90), 0), 6, 4)
		else
			-- shop front wall on the hall with its glass door
			local doorX = ({ pcbang = 8, karaoke = 13.4, billiards = 2 })[fl.shops[1] and fl.shops[1].kind or ""] or 0
			wallX(ctx, -24, 24, 26, { { doorX - 2, doorX + 2, 0, Config.DOOR_H }, { doorX + 3, doorX + 9, 3, 8 } }, { mat = "Plaster", color = { 220, 218, 212 } })
			Kit.part(ctx.parent, ffl(ctx) * CF(doorX + 6, 5.5, 26), V3(6, 5, 0.15), "Glass", { 190, 214, 222 }, { tr = 0.5, name = "ShopWindow" })
			local s = fl.shops[1]
			door(ctx, doorX, 26, 0, { w = 3.8, kind = "glass", id = rec.id .. "_" .. fl.label .. "_shop", shopId = s and s.id })
			if s then
				Core.plate(ctx.parent, ffl(ctx) * CF(doorX, 8.6, 25.75), 7, 1.2, s.name, { bg = { 20, 20, 24 }, fg = { 255, 220, 120 }, glow = true })
			end
		end
		local _ = ceil
	end
	return rec
end

-------------------------------------------------------------------------------------------------
-- 호텔 씨사이드 광안
-------------------------------------------------------------------------------------------------
function A.hotel(def: any): any
	local W, D = 50, 48
	local rec = Plan.new({ id = def.id, archetype = "hotel", name = def.name or "호텔 씨사이드 광안", nameEn = "HOTEL SEASIDE GWANGAN", cf = def.cf, seed = def.seed, wear = def.wear or 0.15, style = def.style or "hotel_stone", W = W, D = D })
	local nTop = def.floors or 9
	local all = Plan.rect(-25, 0, 25, 48)
	local floors = {
		{ label = "B1", h = 12, kind = "parking", rects = { all }, data = { band = false } },
		{ label = "1F", h = 13, kind = "lobby", rects = { all }, data = { base = true } },
	}
	for _, f in typical(nTop, RES, "res", { all }) do
		table.insert(floors, f)
	end
	Plan.floors(rec, floors)
	local allL = labels({ "B1" }, 1, nTop)
	Plan.stair(rec, { x = -5.3, z = 27, rot = 0, floors = allL, roof = true })
	Plan.elevator(rec, { x = 5.3, z = 27, rot = 0, floors = allL, name = "객실 승강기" })
	local f1 = rec.floorByLabel["1F"]
	Plan.shop(rec, f1, { kind = "hotel_lobby", name = rec.name, frame = Plan.frame(-25, 0, 0, 0), w = 50, d = 21, id = rec.id .. "_front" })
	for _, fl in rec.floors do
		if fl.kind == "res" then
			if fl.level == nTop then
				Units.add(rec, fl, { template = "hotel_suite", number = string.format("%d01", fl.level), frame = Plan.frame(0, 0, 21, 180), view = "city" })
				Units.add(rec, fl, { template = "hotel_suite", number = string.format("%d02", fl.level), frame = Plan.frame(25, 0, 21, 180), mirror = true, view = "city" })
			else
				for i = 0, 3 do
					Units.add(rec, fl, { template = "hotel_standard", number = string.format("%d%02d", fl.level, i + 1), frame = Plan.frame(-25 + (i + 1) * 12.5, 0, 21, 180), mirror = i % 2 == 1, view = "city" })
				end
			end
			Units.add(rec, fl, { template = "hotel_deluxe", number = string.format("%d05", fl.level), frame = Plan.frame(-25, 0, 27, 0), view = "ocean" })
			Units.add(rec, fl, { template = "hotel_deluxe", number = string.format("%d06", fl.level), frame = Plan.frame(10.6, 0, 27, 0), mirror = true, view = "ocean" })
			Plan.opening(fl, "-x", -25, 22, 26, 2.5, 8, "window", { curtain = false, zone = "corridor" })
			Plan.opening(fl, "+x", 25, 22, 26, 2.5, 8, "window", { curtain = false, zone = "corridor" })
		end
	end
	entrance(rec, f1, "-z", 0, 0, { kind = "auto", w = 6, h = 8.6, canopy = "metal", id = rec.id .. "_entry", signText = "HOTEL SEASIDE" })
	storefront(f1, "-z", 0, -24, -3.4, 10.6)
	storefront(f1, "-z", 0, 3.4, 24, 10.6)
	Plan.opening(rec.floorByLabel.B1, "-x", -25, 34, 46, 0, 9.4, "void")
	sign(rec, { side = "-z", at = 0, y = rec.roofY + 0.6, w = 28, h = 4.4, text = "HOTEL SEASIDE", kind = "roof", bg = { 20, 20, 24 }, fg = { 255, 226, 160 }, depth = 0.6, offset = -1.2 })
	sign(rec, { side = "-z", at = -24.2, y = 20, w = 3.4, h = 36, text = "호\n텔\n씨\n사\n이\n드", kind = "vertical", bg = { 30, 26, 22 }, fg = { 255, 226, 160 } })
	rec.roof.parapet = 1.4
	rec.roof.equipRect = { -22, 38, -12, 46 }

	rec.hooks.floor = function(ctx: any, fl: any)
		if fl.kind == "parking" then
			Core.parking(ctx.parent, ffl(ctx), -23.5, 1, 23.5, 25, fl.h, ctx.rng, {})
			floorFinish(ctx, -11, 25, 11, 27, "CeramicTiles", { 196, 192, 184 })
			return
		end
		corridor(ctx, -25, 21, 25, 27, { mat = if fl.kind == "res" then "Carpet" else "Marble", color = if fl.kind == "res" then { 120, 40, 44 } else { 230, 224, 214 }, motion = false, lightStep = 8 })
		if fl.kind == "lobby" then
			-- restrooms behind the corridor
			wallX(ctx, -25, -10.6, 27, { { -19.4, -16.6, 0, Config.DOOR_H } })
			wallX(ctx, 10.6, 25, 27, { { 16.6, 19.4, 0, Config.DOOR_H } })
			door(ctx, -18, 27, 0, { w = 2.6, kind = "swing", id = rec.id .. "_wcm", label = "남자 화장실" })
			door(ctx, 18, 27, 0, { w = 2.6, kind = "swing", id = rec.id .. "_wcf", label = "여자 화장실" })
			Core.plate(ctx.parent, ffl(ctx) * CF(-18, 8.0, 26.75), 2.4, 0.8, "🚹", { bg = { 30, 80, 180 }, fg = { 255, 255, 255 } })
			Core.plate(ctx.parent, ffl(ctx) * CF(18, 8.0, 26.75), 2.4, 0.8, "🚺", { bg = { 200, 50, 90 }, fg = { 255, 255, 255 } })
			Core.restroom(ctx.parent, ffl(ctx) * CF(-25, 0, 27), 14.4, 21, fl.h - Config.SLAB, "m", { id = rec.id })
			Core.restroom(ctx.parent, ffl(ctx) * CF(10.6, 0, 27), 14.4, 21, fl.h - Config.SLAB, "f", { id = rec.id })
		else
			Core.plate(ctx.parent, ffl(ctx) * CF(0, 6.5, 26.75), 6, 1.2, "◀ " .. fl.level .. "01-" .. fl.level .. "04   " .. fl.level .. "05-" .. fl.level .. "06 ▶", { bg = { 40, 34, 28 }, fg = { 255, 226, 160 } })
		end
	end
	rec.hooks.shell = function(m: Instance, r: any, rng: any)
		ramp(m, r, -37, -26, 3, 34, 46, 12)
		Kit.box(m, r.cf, -26.4, -13, 34, -24.6, -12, 46, "Concrete", { 120, 120, 118 }, { name = "RampThreshold" })
		-- rooftop bar: deck, bar counter, pool, sunbeds, string lights, glass railing
		local f = r.cf * CF(0, r.roofY, 0)
		Kit.box(m, f, -24, 0, 1, 24, 0.3, 26, "WoodPlanks", { 140, 104, 76 }, { name = "Deck" })
		Kit.box(m, f, -24, 0, 1, -8, 1.6, 9, "Granite", { 60, 60, 64 }, { name = "PoolRim" })
		local water = Kit.box(m, f, -23.4, 0.6, 1.6, -8.6, 1.5, 8.4, "Glass", { 60, 170, 230 }, { name = "PoolWater", tr = 0.3, collide = false })
		Kit.light(water, "point", { color = { 120, 210, 255 }, brightness = 0.9, range = 14, attrs = { Group = "exterior" } })
		Kit.box(m, f, 8, 0.3, 4, 22, 3.8, 6.4, "Wood", { 60, 40, 30 }, { name = "BarCounter" })
		Kit.box(m, f, 7.8, 3.8, 3.8, 22.2, 4.1, 6.6, "Marble", { 236, 236, 232 }, { name = "BarTop", collide = false })
		for i = 0, 4 do
			Kit.box(m, f, 9 + i * 3, 4.1, 5.0, 9.4 + i * 3, 5.2, 5.4, "Glass", { 200, 120, 60 }, { name = "Bottle", collide = false, tr = 0.2 })
		end
		for i = 0, 3 do
			Furniture.build("sunbed", m, f * CF(-20 + i * 4, 0.3, 14) * CFrame.Angles(0, math.pi, 0), 1, { Public = true })
		end
		for k = 0, 12 do
			local b = Kit.ball(m, f, -23 + k * 3.8, 9.5 + math.sin(k * 0.8) * 0.4, 12, 0.35, "Neon", { 255, 214, 150 }, { collide = false, name = "Bulb" })
			b:SetAttribute("NightGlow", true)
		end
		Kit.sound(Kit.anchor(m, f * CF(14, 4, 8), "BarMusic"), "lobby_music", { volume = 0.25, maxDist = 40 })
	end
	return rec
end

-------------------------------------------------------------------------------------------------
-- 광안 숯불갈비 (2층 단독)
-------------------------------------------------------------------------------------------------
function A.bbq(def: any): any
	local W, D = 40, 30
	local rec = Plan.new({ id = def.id, archetype = "bbq", name = def.name or "광안 숯불갈비", nameEn = "GWANGAN BBQ", cf = def.cf, seed = def.seed, wear = def.wear or 0.3, style = def.style or "wood_warm", W = W, D = D })
	local all = Plan.rect(-20, 0, 20, 30)
	Plan.floors(rec, {
		{ label = "1F", h = 12, kind = "lobby", rects = { all }, data = { base = true } },
		{ label = "2F", h = 11, kind = "com", rects = { all }, data = {} },
	})
	Plan.stair(rec, { x = 14.7, z = 12.3, rot = 0, floors = { "1F", "2F" }, roof = false, door = "swing", style = "wood", exterior = { right = true, far = true }, noDoor = { ["1F"] = true } })
	local f1, f2 = rec.floorByLabel["1F"], rec.floorByLabel["2F"]
	Plan.shop(rec, f1, { kind = "bbq", name = rec.name, frame = Plan.frame(-20, 0, 0, 0), w = 29.4, d = 30, id = rec.id .. "_1f", data = { ground = true, tableBase = 0 } })
	Plan.shop(rec, f2, { kind = "bbq", name = rec.name .. " 2층 단체석", frame = Plan.frame(-20, 0, 0, 0), w = 29.4, d = 30, id = rec.id .. "_2f", data = { ground = false, tableBase = 10, payShop = rec.id .. "_1f" } })
	entrance(rec, f1, "-z", 0, -8, { kind = "glass", w = 5.4, h = 8, canopy = "metal", id = rec.id .. "_entry", shopId = rec.id .. "_1f" })
	storefront(f1, "-z", 0, -19, -11, 9)
	storefront(f1, "-z", 0, -5, 19, 9)
	windows(f2, "-z", 0, -19, 19, 5.6, 0.8, 2.4, 8.4, "window", { curtain = false, ac = false, zone = "shop", lit = 1 })
	sign(rec, { side = "-z", at = 0, y = 9.4, w = 38, h = 2.8, text = "🔥 광안 숯불갈비 🐷", bg = { 40, 24, 16 }, fg = { 255, 170, 60 }, depth = 0.6 })
	sign(rec, { side = "-z", at = -19.6, y = 12.5, w = 3.2, h = 12, text = "숯\n불\n갈\n비", kind = "vertical", bg = { 200, 40, 20 }, fg = { 255, 240, 200 } })
	rec.roof.kind = "minimal"

	rec.hooks.floor = function(ctx: any, fl: any)
		if fl.label == "1F" then
			floorFinish(ctx, 9.4, 0, 20, 12.3, "Slate", { 70, 60, 54 })
			ceiling(ctx, 9.4, 0, 20, 12.3)
			Core.ceilingLight(ctx.parent, ffl(ctx) * CF(14.7, ceilOf(ctx) - 0.18, 6), { size = V3(2.2, 0.12, 2.2), group = "shop", lightColor = { 255, 214, 160 } })
		else
			-- restroom (front-right) + landing hall
			wallZ(ctx, 0, 7, 9.4, { { 2.2, 4.8, 0, Config.DOOR_H } })
			wallX(ctx, 9.4, 20, 7, nil)
			door(ctx, 9.4, 3.5, 90, { w = 2.6, kind = "swing", id = rec.id .. "_wc", label = "화장실" })
			Core.restroom(ctx.parent, ffl(ctx) * CF(9.6, 0, 7) * CFrame.Angles(0, rad(90), 0), 7, 10.4, fl.h - Config.SLAB, "u", { id = rec.id })
			floorFinish(ctx, 9.4, 7, 20, 12.3, "Slate", { 70, 60, 54 })
			ceiling(ctx, 9.4, 7, 20, 12.3)
		end
	end
	rec.hooks.furnish = function(ctx: any, fl: any, into: Instance)
		if fl.label == "1F" then
			Furniture.build("water_dispenser", into, ffl(ctx) * CF(19, 0, 2.5) * CFrame.Angles(0, rad(90), 0), 1, { Public = true })
			for i = 0, 1 do
				Shops.chairRef(into, ffl(ctx), 12 + i * 2.2, 2.2, 180, { 60, 40, 30 }, { Index = i + 1 })
			end
		end
	end
	rec.hooks.shell = function(m: Instance, r: any, rng: any)
		local f = r.cf * CF(0, r.roofY, 0)
		for i = 0, 3 do
			local fan = Kit.box(m, f, -14 + i * 8, 0, 14, -10 + i * 8, 3.0, 18, "Metal", { 170, 172, 176 }, { name = "ExhaustFan" })
			local blade = Kit.rod(m, f, V3(-12 + i * 8, 3.2, 16), V3(-12 + i * 8, 3.4, 16), 3.4, "Metal", { 120, 120, 124 }, { collide = false, name = "FanBlade" })
			blade:SetAttribute("Rpm", 90)
			blade:SetAttribute("Axis", "X")
			CollectionService:AddTag(blade, "GwB_Spin")
			local _ = fan
		end
		-- 입간판 (sandwich board) outside
		local board = Kit.part(m, r.cf * CF(-14, 2.4, -3) * CFrame.Angles(rad(-10), 0, 0), V3(3, 4.6, 0.3), "SmoothPlastic", { 30, 20, 16 }, { name = "ABoard" })
		Kit.text(board, "front", "오늘의 추천\n생삼겹 16,000\n양념갈비 17,000", { color = { 255, 220, 160 }, ppS = 30, maxDist = 40 })
	end
	return rec
end

-------------------------------------------------------------------------------------------------
-- 바다 카페 (2층 + 루프탑)
-------------------------------------------------------------------------------------------------
function A.cafe(def: any): any
	local W, D = 28, 30
	local rec = Plan.new({ id = def.id, archetype = "cafe", name = def.name or "바다 카페 SEA BREEZE", nameEn = "SEA BREEZE COFFEE", cf = def.cf, seed = def.seed, wear = def.wear or 0.05, style = def.style or "white_minimal", W = W, D = D })
	local all = Plan.rect(-14, 0, 14, 30)
	Plan.floors(rec, {
		{ label = "1F", h = 12, kind = "lobby", rects = { all }, data = {} },
		{ label = "2F", h = 11, kind = "com", rects = { all }, data = {} },
	})
	Plan.stair(rec, { x = 8.7, z = 12.3, rot = 0, floors = { "1F", "2F" }, roof = true, door = "swing", style = "wood", exterior = { right = true, far = true }, noDoor = { ["1F"] = true, ["2F"] = true } })
	local f1, f2 = rec.floorByLabel["1F"], rec.floorByLabel["2F"]
	Plan.shop(rec, f1, { kind = "cafe", name = "SEA BREEZE", frame = Plan.frame(-14, 0, 0, 0), w = 17.4, d = 30, id = rec.id .. "_1f", data = { ground = true } })
	Plan.shop(rec, f2, { kind = "cafe", name = "SEA BREEZE 2F", frame = Plan.frame(-14, 0, 0, 0), w = 17.4, d = 30, id = rec.id .. "_2f", data = { ground = false, orderShop = rec.id .. "_1f" } })
	entrance(rec, f1, "-z", 0, -7, { kind = "glass", w = 5, h = 8.4, id = rec.id .. "_entry", shopId = rec.id .. "_1f" })
	storefront(f1, "-z", 0, -13, -9.6, 10.4)
	storefront(f1, "-z", 0, -4.4, 13, 10.4)
	storefront(f2, "-z", 0, -13, 13, 9.6, { lit = 1, zone = "shop" })
	Plan.opening(f2, "-x", -14, 2, 28, 1.0, 9.0, "window", { curtain = false, ac = false, zone = "shop", lit = 1 })
	sign(rec, { side = "-z", at = -2, y = 10.7, w = 16, h = 1.0, text = "SEA BREEZE COFFEE · 바다 카페", bg = { 246, 244, 240 }, fg = { 40, 40, 42 }, depth = 0.15, ppS = 40 })
	rec.roof.parapet = 1.0
	rec.roof.equipment = false

	rec.hooks.floor = function(ctx: any, fl: any)
		floorFinish(ctx, 3.4, 0, 14, 12.3, "WoodPlanks", { 196, 170, 140 })
		ceiling(ctx, 3.4, 0, 14, 12.3)
		Core.ceilingLight(ctx.parent, ffl(ctx) * CF(8.7, ceilOf(ctx) - 0.18, 6), { size = V3(2.2, 0.12, 2.2), group = "shop", lightColor = { 255, 226, 186 } })
	end
	rec.hooks.furnish = function(ctx: any, fl: any, into: Instance)
		Furniture.build("sofa3", into, ffl(ctx) * CF(8.7, 0, 9.6) * CFrame.Angles(0, 0, 0), 2, { Public = true })
		Furniture.build("coffee_table", into, ffl(ctx) * CF(8.7, 0, 6.2), 1)
		Furniture.build("armchair", into, ffl(ctx) * CF(5.4, 0, 3.4) * CFrame.Angles(0, rad(-30), 0), 1, { Public = true })
		Furniture.build("armchair", into, ffl(ctx) * CF(12.0, 0, 3.4) * CFrame.Angles(0, rad(30), 0), 2, { Public = true })
	end
	rec.hooks.shell = function(m: Instance, r: any, rng: any)
		-- rooftop terrace: deck, glass rail, parasol tables, string lights
		local f = r.cf * CF(0, r.roofY, 0)
		Kit.box(m, f, -13.6, 0, 0.4, 13.6, 0.3, 11.8, "WoodPlanks", { 150, 116, 84 }, { name = "Deck" })
		Kit.box(m, f, -13.6, 0, 11.8, 3.2, 0.3, 29.6, "WoodPlanks", { 150, 116, 84 }, { name = "Deck" })
		for _, e in { { V3(-13.6, 1.0, 0.2), V3(13.6, 1.0, 0.2) }, { V3(-13.8, 1.0, 0.2), V3(-13.8, 1.0, 29.8) } } do
			Kit.rail(m, f, e[1], e[2], 2.6, "Metal", { 40, 40, 42 }, { solid = true })
		end
		for i, p in { V3(-9, 0.3, 5), V3(-2, 0.3, 5), V3(-8, 0.3, 18), V3(-2, 0.3, 24) } do
			Kit.vcyl(m, f, p.X, 2.9, p.Z, 0.2, 3.0, "Wood", { 236, 234, 228 }, { name = "TableTop" })
			Kit.vcyl(m, f, p.X, 1.6, p.Z, 2.6, 0.25, "Metal", { 40, 40, 42 }, { name = "TableLeg" })
			Kit.vcyl(m, f, p.X, 5.0, p.Z, 9.4, 0.15, "Metal", { 200, 200, 200 }, { name = "ParasolPole", collide = false })
			Kit.part(m, f * CF(p.X, 9.4, p.Z), V3(0.6, 7, 7), "Fabric", if i % 2 == 0 then { 236, 236, 230 } else { 40, 120, 160 }, { shape = "cyl", collide = false, name = "Parasol" }).CFrame = f * CF(p.X, 9.6, p.Z) * CFrame.Angles(0, 0, rad(90))
			for k, a in { 0, 180 } do
				Shops.chairRef(m, f, p.X + math.sin(rad(a)) * 2.4, p.Z + math.cos(rad(a)) * 2.4, a + 180, { 236, 236, 230 }, { Index = i * 10 + k, Public = true })
			end
		end
		for k = 0, 8 do
			local b = Kit.ball(m, f, -13 + k * 3.2, 7 + math.sin(k) * 0.3, 0.8, 0.35, "Neon", { 255, 214, 150 }, { collide = false, name = "Bulb" })
			b:SetAttribute("NightGlow", true)
		end
	end
	return rec
end

-------------------------------------------------------------------------------------------------
-- late-bound helpers (Shops requires Core; Archetypes uses a few Shops helpers through these)
-------------------------------------------------------------------------------------------------
function A.bind(shops: any)
	Shops = shops
	shops.counterLike = function(parent: Instance, frame: CFrame, x0: number, z0: number, x1: number, z1: number)
		shops.counter(parent, frame, x0, z0, x1, z1, 3.6, { 60, 64, 72 }, { 236, 236, 232 })
	end
	shops.staffRef = shops.staff
	shops.chairRef = function(parent: Instance, frame: CFrame, x: number, z: number, yaw: number, color: any, attrs: any)
		return shops.chair(parent, frame, x, z, yaw, color, attrs)
	end
end

return A
