-- Builder/Units: the INTERIOR TEMPLATES of homes and hotel rooms (원룸 · 투룸 · 3룸 · 펜트하우스 ·
-- 오피스텔 · 빌라 · 옥탑방 · 호텔 객실) and the interpreter that builds them.
--
-- A template is pure data in "template space": x across the unit (0..w), z from the entrance wall
-- (z = 0, corridor / stair side) to the far wall (z = d). rooms / walls / doors / windows / fixtures /
-- stage. Variant 2 is the MIRROR image (x -> w - x, yaw -> -yaw, hinges swap), so neighbouring units of
-- the same type are never copy-pasted. Adding a new home type = adding one entry to T (and its size to
-- Shared.Homes.TEMPLATES); every service (doors, lights, housing, decor) works with it automatically.
--
-- Units.add(rec, fl, def)       plan time: Plan.unit + facade openings for the template's windows
-- Units.build(ctx, unit)        structure: walls, doors, finishes (themeable), rooms, lights, switches,
--                               built-in fixtures (kitchen, bathroom, wallpad), the entrance door
-- Units.furnish(ctx, unit)      staging furniture of a vacant unit (model-house look) — owners' homes
--                               are furnished by the Decor service from their saved layout instead.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("GwangalliBuildingsShared"))
local Kit = Shared.Kit
local Config = Shared.Config
local Palette = Shared.Palette
local Furniture = Shared.Furniture
local Homes = Shared.Homes
local Rng = Shared.Rng

local Plan = require(script.Parent.Plan)
local Core = require(script.Parent.Core)

local Units = {}

local V3, CF = Vector3.new, CFrame.new
local rad = math.rad
local min, max, abs = math.min, math.max, math.abs
local F = Palette.FINISH

-------------------------------------------------------------------------------------------------
-- TEMPLATES (template space). door: u of the entrance door; doorW.
-- rooms: { id, kind, label, x0, z0, x1, z1 }
-- walls: { x0, z0, x1, z1 } partitions (axis-aligned). Holes are cut automatically where doors sit.
-- doors: { x, z, axis = "x" (wall at constant z) | "z" (wall at constant x), w, kind = swing | slide |
--          opening | glass_slide, front = side the door faces, swing = "both" | "front" | "back" }
-- windows: { edge = far | left | right | entry, a0, a1, y0?, y1?, kind? }
-- fixtures / stage: { itemId, x, z, yaw, y?, attrs? }
-------------------------------------------------------------------------------------------------
local T = {}
Units.T = T

T.oneroom_studio = {
	door = 2.5,
	rooms = {
		{ "entry", "entry", "현관", 0, 0, 8.5, 4 },
		{ "bath", "bath", "욕실", 8.5, 0, 14, 8 },
		{ "kitchen", "kitchen", "주방", 0, 4, 8.5, 12 },
		{ "utility", "utility", "다용도실", 8.5, 8, 14, 12 },
		{ "room", "bed", "방", 0, 12, 14, 22 },
	},
	walls = { { 8.5, 0, 8.5, 8 }, { 8.5, 8, 14, 8 }, { 0, 12, 14, 12 } },
	doors = {
		{ x = 8.5, z = 6, axis = "z", w = 2.6, kind = "swing", front = "-x", swing = "front" },
		{ x = 5, z = 12, axis = "x", w = 5, kind = "slide", front = "-z" },
	},
	windows = { { edge = "far", a0 = 2, a1 = 12 } },
	fixtures = {
		{ "kitchen_counter", 1.4, 6.8, -90, attrs = { W = 5 } },
		{ "washer", 1.5, 10.6, -90 },
		{ "toilet", 10.0, 1.8, 180 },
		{ "washbasin", 12.9, 2.2, 90 },
		{ "shower", 12.0, 6.0, 0 },
		{ "fridge", 12.4, 10.0, 90 },
		{ "wallpad", 6.5, 0.4, 180 },
		{ "shoe_rack", 7.65, 2.2, 90 },
	},
	stage = {
		{ "bed_single", 10.2, 18.5, 90 },
		{ "desk", 3.4, 19.6, 0 },
		{ "wardrobe", 11.2, 13.3, 180 },
		{ "tv_small", 0.9, 15.5, -90 },
		{ "rug", 5.5, 16.5, 0 },
		{ "microwave", 1.4, 8.4, -90, y = 3.05 },
		{ "rice_cooker", 1.4, 5.2, -90, y = 3.05 },
		{ "fan", 2.0, 13.4, 135 },
	},
}

T.officetel_a = {
	door = 2.5,
	rooms = {
		{ "entry", "entry", "현관", 0, 0, 7.5, 4 },
		{ "bath", "bath", "욕실", 7.5, 0, 14, 7 },
		{ "kitchen", "kitchen", "주방", 0, 4, 7.5, 10.5 },
		{ "utility", "utility", "다용도", 7.5, 7, 14, 10.5 },
		{ "room", "bed", "방", 0, 10.5, 14, 20 },
	},
	walls = { { 7.5, 0, 7.5, 7 }, { 7.5, 7, 14, 7 } },
	doors = { { x = 7.5, z = 5.0, axis = "z", w = 2.6, kind = "swing", front = "-x", swing = "front" } },
	windows = { { edge = "far", a0 = 0.8, a1 = 13.2 } },
	fixtures = {
		{ "kitchen_counter", 1.4, 7.0, -90, attrs = { W = 5 } },
		{ "toilet", 9.6, 1.8, 180 },
		{ "washbasin", 12.9, 1.8, 90 },
		{ "shower", 12.0, 5.1, 0 },
		{ "fridge", 12.4, 8.75, 90 },
		{ "washer", 9.3, 8.5, 180 },
		{ "wallpad", 5.5, 0.4, 180 },
	},
	stage = {
		{ "bed_queen", 10.1, 16, 90 },
		{ "pc_desk", 3.2, 17.5, 0 },
		{ "tv_small", 0.9, 13.4, -90 },
		{ "microwave", 1.4, 8.6, -90, y = 3.05 },
		{ "mood_light", 6.6, 11.3, 0 },
		{ "monstera", 1.4, 11.6, 0 },
	},
}

T.officetel_b = {
	door = 2.5,
	rooms = {
		{ "entry", "entry", "현관", 0, 0, 6, 4 },
		{ "bath", "bath", "욕실", 6, 0, 13, 7 },
		{ "dress", "dress", "드레스룸", 13, 0, 20, 7 },
		{ "kitchen", "kitchen", "주방", 0, 4, 6, 11 },
		{ "dining", "dining", "식사 공간", 6, 7, 11.5, 11 },
		{ "living", "living", "거실", 0, 11, 11.5, 20 },
		{ "bed", "bed", "침실", 11.5, 7, 20, 20 },
	},
	walls = { { 6, 0, 6, 7 }, { 6, 7, 13, 7 }, { 13, 0, 13, 7 }, { 13, 7, 20, 7 }, { 11.5, 7, 11.5, 20 } },
	doors = {
		{ x = 9.5, z = 7, axis = "x", w = 2.6, kind = "swing", front = "+z", swing = "front" },
		{ x = 16.5, z = 7, axis = "x", w = 2.8, kind = "slide", front = "+z" },
		{ x = 11.5, z = 14.5, axis = "z", w = 4.4, kind = "slide", front = "-x" },
	},
	windows = { { edge = "far", a0 = 0.8, a1 = 10.8 }, { edge = "far", a0 = 12.3, a1 = 19.2 } },
	fixtures = {
		{ "kitchen_counter", 1.4, 7.5, -90, attrs = { W = 6 } },
		{ "toilet", 7.6, 1.8, 180 },
		{ "washbasin", 12.0, 2.0, 90 },
		{ "shower", 10.8, 5.0, 0 },
		{ "washer", 10.0, 1.5, 180 },
		{ "fridge", 4.5, 5.8, 90 },
		{ "wallpad", 4.4, 0.4, 180 },
	},
	stage = {
		{ "bed_queen", 16.1, 15.5, 90 },
		{ "wardrobe", 16.5, 1.3, 180 },
		{ "sofa3", 2.0, 15.5, -90 },
		{ "tv55", 10.5, 15.5, 90 },
		{ "coffee_table", 6.2, 15.5, 90 },
		{ "dining2", 8.8, 9.0, 90 },
		{ "microwave", 1.4, 9.6, -90, y = 3.05 },
		{ "floor_lamp", 1.4, 19.0, 0 },
	},
}

T.apt_1room = {
	door = 2.5,
	rooms = {
		{ "entry", "entry", "현관", 0, 0, 5, 6 },
		{ "utility", "utility", "다용도실", 5, 0, 10, 6 },
		{ "bath", "bath", "욕실", 10, 0, 16, 8 },
		{ "kitchen", "kitchen", "주방", 0, 6, 10, 14 },
		{ "dining", "dining", "식사 공간", 10, 8, 16, 14 },
		{ "room", "bed", "방", 0, 14, 16, 26 },
		{ "veranda", "veranda", "베란다", 0, 26, 16, 30 },
	},
	walls = { { 5, 0, 5, 6 }, { 5, 6, 10, 6 }, { 10, 0, 10, 8 }, { 10, 8, 16, 8 }, { 0, 14, 16, 14 }, { 0, 26, 16, 26 } },
	doors = {
		{ x = 5, z = 3, axis = "z", w = 2.8, kind = "slide", front = "-x" },
		{ x = 13, z = 8, axis = "x", w = 2.6, kind = "swing", front = "+z", swing = "front" },
		{ x = 6, z = 14, axis = "x", w = 5, kind = "slide", front = "-z" },
		{ x = 8, z = 26, axis = "x", w = 9, kind = "glass_slide", front = "+z" },
	},
	windows = { { edge = "far", a0 = 0.8, a1 = 15.2, y0 = 1.2 } },
	fixtures = {
		{ "kitchen_counter", 1.4, 10, -90, attrs = { W = 7 } },
		{ "toilet", 14.2, 3.2, 90 },
		{ "washbasin", 11.6, 1.1, 180 },
		{ "shower", 12.0, 6.0, 0 },
		{ "washer", 7.5, 1.5, 180 },
		{ "fridge", 7.5, 7.5, 180 },
		{ "wallpad", 0.4, 3.5, -90 },
	},
	stage = {
		{ "bed_queen", 12.1, 19, 90 },
		{ "tv_small", 0.9, 19, -90 },
		{ "desk", 2.3, 23.5, -90 },
		{ "dining2", 13, 11, 90 },
		{ "drying_rack", 8, 28.2, 0 },
		{ "monstera", 1.4, 28.2, 0 },
		{ "microwave", 1.4, 12.6, -90, y = 3.05 },
		{ "aircon", 15.0, 15.2, 90 },
	},
}

T.apt_2room = {
	door = 2.5,
	rooms = {
		{ "entry", "entry", "현관", 0, 0, 5, 8 },
		{ "bath", "bath", "욕실", 5, 0, 12, 8 },
		{ "bed2", "bed", "작은방", 12, 0, 24, 12 },
		{ "kitchen", "kitchen", "주방", 0, 8, 12, 16 },
		{ "living", "living", "거실", 0, 16, 12, 26 },
		{ "bed1", "bed", "안방", 12, 12, 24, 26 },
		{ "veranda", "veranda", "베란다", 0, 26, 24, 30 },
	},
	walls = { { 5, 0, 5, 8 }, { 5, 8, 12, 8 }, { 12, 0, 12, 12 }, { 12, 12, 24, 12 }, { 12, 12, 12, 26 }, { 0, 26, 24, 26 } },
	doors = {
		{ x = 5, z = 5.5, axis = "z", w = 2.6, kind = "swing", front = "-x", swing = "front" },
		{ x = 12, z = 10.2, axis = "z", w = 3.0, kind = "swing", front = "-x" },
		{ x = 12, z = 14, axis = "z", w = 3.0, kind = "swing", front = "-x" },
		{ x = 6, z = 26, axis = "x", w = 8, kind = "glass_slide", front = "+z" },
		{ x = 18, z = 26, axis = "x", w = 7, kind = "glass_slide", front = "+z" },
	},
	windows = { { edge = "far", a0 = 0.8, a1 = 23.2, y0 = 1.2 }, { edge = "entry", a0 = 15, a1 = 21, y0 = 4.2, y1 = 7.4 } },
	fixtures = {
		{ "kitchen_counter", 1.4, 12, -90, attrs = { W = 7 } },
		{ "bathtub", 8.5, 6.3, 0 },
		{ "toilet", 6.7, 1.8, 180 },
		{ "washbasin", 11.0, 2.0, 90 },
		{ "fridge", 6.5, 9.5, 180 },
		{ "wallpad", 0.4, 5.2, -90 },
		{ "shoe_rack", 0.95, 2.4, -90 },
	},
	stage = {
		{ "sofa3", 2.0, 21, -90 },
		{ "tv55", 11.0, 21, 90 },
		{ "coffee_table", 6.5, 21, 90 },
		{ "rug", 6.5, 21, 0 },
		{ "dining2", 8, 13.5, 90 },
		{ "bed_queen", 20.1, 19, 90 },
		{ "wardrobe", 20, 13.2, 180 },
		{ "vanity", 13.1, 22, -90 },
		{ "bed_single", 20.2, 7, 90 },
		{ "desk", 15, 2.3, 180 },
		{ "washer", 1.5, 28.2, -90 },
		{ "drying_rack", 12, 28.2, 0 },
		{ "microwave", 1.4, 14.5, -90, y = 3.05 },
	},
}

T.apt_3room = {
	door = 2.5,
	rooms = {
		{ "entry", "entry", "현관", 0, 0, 5, 8 },
		{ "bath2", "bath", "공용 욕실", 5, 0, 11, 8 },
		{ "bed3", "bed", "작은방", 11, 0, 21, 10 },
		{ "bed2", "bed", "방2", 21, 0, 32, 10 },
		{ "kitchen", "kitchen", "주방", 0, 8, 11, 17 },
		{ "hall", "hall", "복도", 11, 10, 32, 14 },
		{ "dining", "dining", "식사 공간", 11, 14, 17, 17 },
		{ "living", "living", "거실", 0, 17, 17, 26 },
		{ "master", "bed", "안방", 17, 14, 26, 26 },
		{ "bath1", "bath", "안방 욕실", 26, 14, 32, 20 },
		{ "dress", "dress", "드레스룸", 26, 20, 32, 26 },
		{ "veranda", "veranda", "베란다", 0, 26, 32, 30 },
	},
	walls = {
		{ 5, 0, 5, 8 },
		{ 5, 8, 11, 8 },
		{ 11, 0, 11, 10 },
		{ 11, 10, 32, 10 },
		{ 21, 0, 21, 10 },
		{ 17, 14, 32, 14 },
		{ 17, 14, 17, 26 },
		{ 26, 14, 26, 26 },
		{ 26, 20, 32, 20 },
		{ 0, 26, 32, 26 },
	},
	doors = {
		{ x = 5, z = 5.5, axis = "z", w = 2.6, kind = "swing", front = "-x", swing = "front" },
		{ x = 17.4, z = 10, axis = "x", w = 3.0, kind = "swing", front = "+z" },
		{ x = 25.4, z = 10, axis = "x", w = 3.0, kind = "swing", front = "+z" },
		{ x = 21.5, z = 14, axis = "x", w = 3.0, kind = "swing", front = "-z" },
		{ x = 27.6, z = 14, axis = "x", w = 2.6, kind = "swing", front = "-z", swing = "front" },
		{ x = 26, z = 23, axis = "z", w = 2.8, kind = "slide", front = "-x" },
		{ x = 9, z = 26, axis = "x", w = 10, kind = "glass_slide", front = "+z" },
		{ x = 22, z = 26, axis = "x", w = 6, kind = "glass_slide", front = "+z" },
	},
	windows = {
		{ edge = "far", a0 = 0.8, a1 = 31.2, y0 = 1.2 },
		{ edge = "entry", a0 = 13, a1 = 19, y0 = 4.2, y1 = 7.4 },
		{ edge = "entry", a0 = 23, a1 = 30, y0 = 4.2, y1 = 7.4 },
	},
	fixtures = {
		{ "kitchen_counter", 1.4, 12.5, -90, attrs = { W = 8 } },
		{ "fridge", 8.5, 9.5, 180 },
		{ "kimchi_fridge", 4.6, 9.4, 180 },
		{ "toilet", 6.5, 1.8, 180 },
		{ "washbasin", 10.0, 2.0, 90 },
		{ "shower", 9.0, 5.9, 0 },
		{ "toilet", 30.8, 18.3, 0 },
		{ "shower", 28.0, 17.9, 0 },
		{ "washbasin", 30.4, 15.0, 180 },
		{ "wallpad", 0.4, 5.5, -90 },
		{ "shoe_rack", 0.95, 2.6, -90 },
	},
	stage = {
		{ "sofa3", 15.1, 21.5, 90 },
		{ "tv55", 1.1, 21.5, -90 },
		{ "coffee_table", 9.5, 21.5, 90 },
		{ "rug", 9.5, 21.5, 0 },
		{ "aircon", 15.9, 17.6, 0 },
		{ "dining4", 6.5, 14, 0 },
		{ "bed_queen", 22.2, 20.5, 90 },
		{ "vanity", 18.1, 15.9, -90 },
		{ "wardrobe", 30.7, 23, 90 },
		{ "bed_single", 28.2, 5, 90 },
		{ "desk", 24.5, 2.3, 180 },
		{ "bed_single", 13.6, 3.8, 180 },
		{ "pc_desk", 18.7, 5.5, 90 },
		{ "washer", 1.5, 28.2, -90 },
		{ "drying_rack", 13, 28.2, 0 },
		{ "monstera", 30, 28.2, 0 },
		{ "microwave", 1.4, 15.4, -90, y = 3.05 },
		{ "rice_cooker", 1.4, 9.4, -90, y = 3.05 },
	},
}

T.apt_penthouse = {
	door = 48,
	doorW = 4.4,
	doorKind = "double",
	rooms = {
		{ "mbath", "bath", "안방 욕실", 0, 0, 12, 8 },
		{ "dress", "dress", "드레스룸", 12, 0, 24, 8 },
		{ "media", "media", "시네마룸", 24, 0, 36, 8 },
		{ "powder", "bath", "파우더룸", 36, 0, 40, 8 },
		{ "foyer", "entry", "현관 홀", 40, 0, 56, 8 },
		{ "kitchen", "kitchen", "주방", 56, 0, 72, 8 },
		{ "bed2", "bed", "게스트룸", 72, 0, 84, 12 },
		{ "bed3", "bed", "침실3", 84, 0, 96, 12 },
		{ "master", "bed", "안방", 0, 8, 24, 26 },
		{ "living", "living", "거실", 24, 8, 72, 26 },
		{ "hall", "hall", "복도", 72, 12, 96, 16 },
		{ "study", "study", "서재", 72, 16, 82, 26 },
		{ "bath2", "bath", "욕실", 82, 16, 88, 26 },
		{ "bed4", "bed", "침실4", 88, 16, 96, 26 },
		{ "sunroom", "veranda", "선룸", 0, 26, 96, 30 },
	},
	walls = {
		{ 12, 0, 12, 8 },
		{ 0, 8, 24, 8 },
		{ 24, 0, 24, 26 },
		{ 24, 8, 40, 8 },
		{ 36, 0, 36, 8 },
		{ 40, 0, 40, 8 },
		{ 40, 8, 56, 8 },
		{ 56, 0, 56, 8 },
		{ 72, 0, 72, 12 },
		{ 72, 16, 72, 26 },
		{ 84, 0, 84, 12 },
		{ 72, 12, 96, 12 },
		{ 72, 16, 96, 16 },
		{ 82, 16, 82, 26 },
		{ 88, 16, 88, 26 },
		{ 0, 26, 96, 26 },
	},
	doors = {
		{ x = 6, z = 8, axis = "x", w = 2.8, kind = "swing", front = "+z" },
		{ x = 18, z = 8, axis = "x", w = 2.8, kind = "slide", front = "+z" },
		{ x = 24, z = 13, axis = "z", w = 3.0, kind = "swing", front = "+x" },
		{ x = 30, z = 8, axis = "x", w = 2.8, kind = "swing", front = "+z" },
		{ x = 38, z = 8, axis = "x", w = 2.6, kind = "swing", front = "+z", swing = "front" },
		{ x = 48, z = 8, axis = "x", w = 12, kind = "opening", front = "+z" },
		{ x = 56, z = 4, axis = "z", w = 5, kind = "opening", front = "-x" },
		{ x = 77.5, z = 12, axis = "x", w = 3.0, kind = "swing", front = "+z" },
		{ x = 90, z = 12, axis = "x", w = 3.0, kind = "swing", front = "+z" },
		{ x = 76, z = 16, axis = "x", w = 3.0, kind = "swing", front = "-z" },
		{ x = 85, z = 16, axis = "x", w = 2.6, kind = "swing", front = "-z", swing = "front" },
		{ x = 91.5, z = 16, axis = "x", w = 3.0, kind = "swing", front = "-z" },
		{ x = 12, z = 26, axis = "x", w = 10, kind = "glass_slide", front = "+z" },
		{ x = 38, z = 26, axis = "x", w = 10, kind = "glass_slide", front = "+z" },
		{ x = 58, z = 26, axis = "x", w = 10, kind = "glass_slide", front = "+z" },
		{ x = 77, z = 26, axis = "x", w = 6, kind = "glass_slide", front = "+z" },
		{ x = 92, z = 26, axis = "x", w = 6, kind = "glass_slide", front = "+z" },
	},
	windows = {
		{ edge = "far", a0 = 0.8, a1 = 95.2, y0 = 0.4 },
		{ edge = "left", a0 = 10, a1 = 24, y0 = 2.4 },
		{ edge = "right", a0 = 2, a1 = 10, y0 = 2.4 },
		{ edge = "right", a0 = 18, a1 = 24, y0 = 2.4 },
	},
	fixtures = {
		{ "kitchen_counter", 64, 1.4, 180, attrs = { W = 14 } },
		{ "kitchen_island", 64, 6.4, 0 },
		{ "bathtub", 4, 1.8, 180 },
		{ "shower", 9.9, 2.1, 0 },
		{ "toilet", 1.8, 6, -90 },
		{ "washbasin", 10, 7.0, 0 },
		{ "toilet", 38, 1.8, 180 },
		{ "washbasin", 39.0, 5.0, 90 },
		{ "shower", 85, 24.0, 0 },
		{ "toilet", 83.7, 19.5, -90 },
		{ "washbasin", 87.0, 19.5, 90 },
		{ "wallpad", 44, 0.4, 180 },
		{ "shoe_rack", 40.85, 4, -90 },
		{ "fridge", 70.3, 1.6, 180 },
	},
	stage = {
		{ "tv55", 25.0, 19, -90 },
		{ "sofa3", 36, 19, 90 },
		{ "coffee_table", 30.5, 19, 90 },
		{ "rug", 31, 19, 0 },
		{ "armchair", 29, 24.4, 0 },
		{ "armchair", 33, 24.4, 0 },
		{ "dining4", 62, 15, 0 },
		{ "monstera", 70.5, 24.5, 0 },
		{ "monstera", 25.5, 9.6, 0 },
		{ "floor_lamp", 38.5, 24.6, 0 },
		{ "aquarium", 70.9, 21, 90 },
		{ "massage_chair", 46, 22, 180 },
		{ "bed_king", 12, 11.9, 180 },
		{ "tv55", 23.0, 20, 90 },
		{ "vanity", 1.2, 22, -90 },
		{ "wardrobe", 15, 1.3, 180 },
		{ "wardrobe", 20.5, 1.3, 180 },
		{ "tv55", 35.0, 4, 90 },
		{ "armchair", 26.2, 2.4, -90 },
		{ "armchair", 26.2, 5.6, -90 },
		{ "bed_queen", 80.1, 5, 90 },
		{ "wardrobe", 73.2, 5, -90 },
		{ "bed_single", 92.2, 5, 90 },
		{ "pc_desk", 86.3, 5, -90 },
		{ "bookshelf", 72.85, 21, -90 },
		{ "desk", 79.8, 21, 90 },
		{ "bed_single", 92.1, 20.5, 90 },
		{ "jacuzzi", 6, 28.2, 0, scale = true },
		{ "sunbed", 30, 28.1, 90 },
		{ "sunbed", 36, 28.1, 90 },
		{ "monstera", 50, 28.4, 0 },
		{ "monstera", 70, 28.4, 0 },
		{ "microwave", 59, 1.4, 180, y = 3.05 },
	},
}

T.villa_2room = {
	door = 2.4,
	rooms = {
		{ "entry", "entry", "현관", 0, 0, 5, 6 },
		{ "bath", "bath", "욕실", 5, 0, 14, 6 },
		{ "bed2", "bed", "작은방", 14, 0, 26, 12 },
		{ "ldk", "living", "거실 · 주방", 0, 6, 14, 24 },
		{ "bed1", "bed", "안방", 14, 12, 26, 24 },
	},
	walls = { { 5, 0, 5, 6 }, { 5, 6, 14, 6 }, { 14, 0, 14, 24 }, { 14, 12, 26, 12 } },
	doors = {
		{ x = 5, z = 3, axis = "z", w = 2.6, kind = "swing", front = "-x", swing = "front" },
		{ x = 14, z = 9, axis = "z", w = 3.0, kind = "swing", front = "-x" },
		{ x = 14, z = 15, axis = "z", w = 3.0, kind = "swing", front = "-x" },
	},
	windows = {
		{ edge = "left", a0 = 8, a1 = 22, y0 = 1.2 },
		{ edge = "far", a0 = 2, a1 = 12 },
		{ edge = "far", a0 = 16, a1 = 24 },
		{ edge = "right", a0 = 2, a1 = 10 },
		{ edge = "right", a0 = 15, a1 = 22 },
	},
	fixtures = {
		{ "kitchen_counter", 10, 7.3, 180, attrs = { W = 7 } },
		{ "toilet", 12.5, 1.8, 180 },
		{ "washbasin", 9.8, 1.1, 180 },
		{ "shower", 7.5, 3.9, 0 },
		{ "washer", 11.8, 4.6, 0 },
		{ "fridge", 3.1, 7.5, 180 },
		{ "wallpad", 0.4, 4.2, -90 },
	},
	stage = {
		{ "sofa3", 2.1, 18, -90 },
		{ "tv55", 13.0, 20, 90 },
		{ "coffee_table", 7, 18.5, 90 },
		{ "dining2", 8, 11, 90 },
		{ "bed_single", 22.2, 5, 90 },
		{ "desk", 17, 2.3, 180 },
		{ "bed_queen", 22.1, 18, 90 },
		{ "wardrobe", 21, 13.2, 180 },
		{ "microwave", 8.0, 7.3, 180, y = 3.05 },
	},
}

T.villa_3room = {
	door = 2.4,
	rooms = {
		{ "entry", "entry", "현관", 0, 0, 5, 6 },
		{ "bath", "bath", "욕실", 5, 0, 14, 6 },
		{ "bed2", "bed", "작은방", 14, 0, 26, 11 },
		{ "ldk", "living", "거실 · 주방", 0, 6, 14, 16 },
		{ "bed1", "bed", "안방", 0, 16, 14, 24 },
		{ "bed3", "bed", "방3", 14, 11, 26, 24 },
	},
	walls = { { 5, 0, 5, 6 }, { 5, 6, 14, 6 }, { 14, 0, 14, 24 }, { 14, 11, 26, 11 }, { 0, 16, 14, 16 } },
	doors = {
		{ x = 5, z = 3, axis = "z", w = 2.6, kind = "swing", front = "-x", swing = "front" },
		{ x = 14, z = 8.5, axis = "z", w = 3.0, kind = "swing", front = "-x" },
		{ x = 14, z = 13.5, axis = "z", w = 3.0, kind = "swing", front = "-x" },
		{ x = 10, z = 16, axis = "x", w = 3.0, kind = "swing", front = "-z" },
	},
	windows = {
		{ edge = "left", a0 = 7, a1 = 15, y0 = 1.2 },
		{ edge = "left", a0 = 17, a1 = 23 },
		{ edge = "far", a0 = 2, a1 = 12 },
		{ edge = "far", a0 = 16, a1 = 24 },
		{ edge = "right", a0 = 2, a1 = 9 },
		{ edge = "right", a0 = 14, a1 = 22 },
	},
	fixtures = {
		{ "kitchen_counter", 10, 7.3, 180, attrs = { W = 7 } },
		{ "toilet", 12.5, 1.8, 180 },
		{ "washbasin", 9.8, 1.1, 180 },
		{ "shower", 7.5, 3.9, 0 },
		{ "washer", 11.8, 4.6, 0 },
		{ "kimchi_fridge", 3.1, 7.3, 180 },
		{ "wallpad", 0.4, 4.2, -90 },
	},
	stage = {
		{ "sofa3", 4.4, 14.1, 0 },
		{ "tv_small", 0.9, 10, -90 },
		{ "armchair", 5, 10, 90 },
		{ "dining2", 10.5, 11.5, 90 },
		{ "bed_queen", 4.0, 20, -90 },
		{ "wardrobe", 12.8, 20, 90 },
		{ "bed_single", 22.2, 5, 90 },
		{ "bed_single", 22.2, 18, 90 },
		{ "desk", 17, 21.6, 0 },
		{ "microwave", 8.0, 7.3, 180, y = 3.05 },
	},
}

T.villa_rooftop = {
	door = 4,
	standalone = true,
	rooms = {
		{ "kitchen", "kitchen", "주방", 0, 0, 10, 6 },
		{ "bath", "bath", "욕실", 10, 0, 18, 6 },
		{ "room", "bed", "방", 0, 6, 18, 16 },
	},
	walls = { { 10, 0, 10, 6 }, { 0, 6, 18, 6 } },
	doors = {
		{ x = 10, z = 3, axis = "z", w = 2.6, kind = "swing", front = "-x", swing = "front" },
		{ x = 5, z = 6, axis = "x", w = 5, kind = "opening", front = "-z" },
	},
	windows = { { edge = "far", a0 = 4, a1 = 14 }, { edge = "left", a0 = 8, a1 = 14 }, { edge = "right", a0 = 8, a1 = 14 } },
	fixtures = {
		{ "kitchen_counter", 1.4, 3.2, -90, attrs = { W = 5 } },
		{ "toilet", 16.2, 4.2, 90 },
		{ "washbasin", 14.5, 1.1, 180 },
		{ "shower", 12.1, 3.9, 0 },
		{ "wallpad", 7.5, 0.4, 180 },
	},
	stage = {
		{ "bed_single", 14.2, 11, 90 },
		{ "tv_small", 0.9, 11, -90 },
		{ "desk", 5, 13.6, 0 },
		{ "fan", 8.5, 8.0, 180 },
		{ "fridge", 8.2, 4.4, 0 },
	},
}

T.hotel_standard = {
	door = 2.5,
	doorKind = "room",
	rooms = {
		{ "entry", "entry", "입구", 0, 0, 5, 7 },
		{ "bath", "bath", "욕실", 5, 0, 12.5, 7 },
		{ "room", "bed", "객실", 0, 7, 12.5, 21 },
	},
	walls = { { 5, 0, 5, 7 }, { 5, 7, 12.5, 7 } },
	doors = { { x = 5, z = 4.5, axis = "z", w = 2.6, kind = "swing", front = "-x", swing = "front" } },
	windows = { { edge = "far", a0 = 0.8, a1 = 11.7, y0 = 1.2 } },
	fixtures = {
		{ "toilet", 11.0, 1.8, 180 },
		{ "washbasin", 8.0, 1.1, 180 },
		{ "shower", 8.0, 5.0, 0 },
		{ "wallpad", 0.4, 5, -90 },
	},
	stage = {
		{ "bed_queen", 8.6, 15, 90 },
		{ "desk", 2.3, 10, -90 },
		{ "tv_small", 0.9, 15, -90 },
		{ "armchair", 2.5, 19.0, 135 },
		{ "minibar", 1.2, 7.9, -90 },
	},
}

T.hotel_deluxe = {
	door = 2.5,
	doorKind = "room",
	rooms = {
		{ "entry", "entry", "입구", 0, 0, 5, 7 },
		{ "bath", "bath", "욕실", 5, 0, 14.4, 7 },
		{ "room", "bed", "객실", 0, 7, 14.4, 21 },
	},
	walls = { { 5, 0, 5, 7 }, { 5, 7, 14.4, 7 } },
	doors = { { x = 5, z = 4.5, axis = "z", w = 2.6, kind = "swing", front = "-x", swing = "front" } },
	windows = { { edge = "far", a0 = 0.8, a1 = 13.6, y0 = 0.6 } },
	fixtures = {
		{ "bathtub", 10, 5.3, 0 },
		{ "toilet", 6.4, 1.8, 180 },
		{ "washbasin", 11.5, 1.1, 180 },
		{ "wallpad", 0.4, 5, -90 },
	},
	stage = {
		{ "bed_king", 10.3, 14.5, 90 },
		{ "tv55", 1.1, 14, -90 },
		{ "armchair", 2.2, 19.2, 160 },
		{ "armchair", 5.6, 19.4, 200 },
		{ "minibar", 4.0, 8.0, 180 },
		{ "floor_lamp", 13.4, 19.8, 0 },
	},
}

T.hotel_suite = {
	door = 2.5,
	doorKind = "room",
	rooms = {
		{ "entry", "entry", "입구", 0, 0, 5, 6 },
		{ "powder", "bath", "파우더룸", 5, 0, 14, 6 },
		{ "living", "living", "거실", 0, 6, 14, 21 },
		{ "bath", "bath", "욕실", 14, 0, 25, 8 },
		{ "bedroom", "bed", "침실", 14, 8, 25, 21 },
	},
	walls = { { 5, 0, 5, 6 }, { 5, 6, 14, 6 }, { 14, 0, 14, 21 }, { 14, 8, 25, 8 } },
	doors = {
		{ x = 5, z = 3, axis = "z", w = 2.6, kind = "swing", front = "-x", swing = "front" },
		{ x = 14, z = 11, axis = "z", w = 3.0, kind = "swing", front = "-x" },
		{ x = 19.5, z = 8, axis = "x", w = 2.6, kind = "swing", front = "+z", swing = "front" },
	},
	windows = { { edge = "far", a0 = 0.8, a1 = 24.2, y0 = 0.6 }, { edge = "right", a0 = 10, a1 = 19, y0 = 1.2 } },
	fixtures = {
		{ "toilet", 12.5, 1.8, 180 },
		{ "washbasin", 8.5, 1.1, 180 },
		{ "bathtub", 18, 1.8, 180 },
		{ "shower", 23, 3.9, 0 },
		{ "washbasin", 16.5, 7.0, 0 },
		{ "wallpad", 0.4, 4.5, -90 },
	},
	stage = {
		{ "sofa3", 2.1, 14, -90 },
		{ "tv55", 13.0, 16.5, 90 },
		{ "coffee_table", 7, 14, 90 },
		{ "armchair", 6, 19.4, 180 },
		{ "dining2", 9.5, 9.2, 90 },
		{ "bed_king", 21.2, 15, 90 },
		{ "minibar", 15.2, 19.8, -90 },
		{ "monstera", 1.4, 19.8, 0 },
	},
}

-------------------------------------------------------------------------------------------------
-- layout (mirroring)
-------------------------------------------------------------------------------------------------
local FLIP_FRONT = { ["-x"] = "+x", ["+x"] = "-x", ["-z"] = "-z", ["+z"] = "+z" }
local FLIP_EDGE = { left = "right", right = "left", far = "far", entry = "entry" }
local cache = {}

function Units.layout(tid: string, mirror: boolean): any
	local key = tid .. (if mirror then "#m" else "")
	if cache[key] then
		return cache[key]
	end
	local t = T[tid]
	assert(t, "no interior template " .. tid)
	local w = Homes.TEMPLATES[tid].w
	local function mx(x: number): number
		return if mirror then w - x else x
	end
	local L = { w = w, d = Homes.TEMPLATES[tid].d, standalone = t.standalone, doorKind = t.doorKind, doorW = t.doorW or 3.4 }
	L.door = mx(t.door)
	L.rooms = {}
	for _, r in t.rooms do
		local x0, x1 = mx(r[4]), mx(r[6])
		table.insert(L.rooms, { id = r[1], kind = r[2], label = r[3], x0 = min(x0, x1), z0 = r[5], x1 = max(x0, x1), z1 = r[7] })
	end
	L.walls = {}
	for _, s in t.walls do
		local x0, x1 = mx(s[1]), mx(s[3])
		table.insert(L.walls, { x0 = min(x0, x1), z0 = min(s[2], s[4]), x1 = max(x0, x1), z1 = max(s[2], s[4]) })
	end
	L.doors = {}
	for _, d in t.doors do
		local nd = table.clone(d)
		nd.x = mx(d.x)
		if mirror then
			nd.front = FLIP_FRONT[d.front] or d.front
			nd.hinge = if (d.hinge or "left") == "left" then "right" else "left"
		end
		table.insert(L.doors, nd)
	end
	L.windows = {}
	for _, wn in t.windows do
		local nw = table.clone(wn)
		if mirror then
			nw.edge = FLIP_EDGE[wn.edge]
			if wn.edge == "far" or wn.edge == "entry" then
				nw.a0, nw.a1 = w - wn.a1, w - wn.a0
			end
		end
		table.insert(L.windows, nw)
	end
	local function items(list: { any }): { any }
		local out = {}
		for _, f in list do
			table.insert(out, { id = f[1], x = mx(f[2]), z = f[3], yaw = if mirror then -(f[4] or 0) else (f[4] or 0), y = f.y, attrs = f.attrs })
		end
		return out
	end
	L.fixtures = items(t.fixtures)
	L.stage = items(t.stage)
	cache[key] = L
	return L
end

-- template-space <-> frame-space conversion of a furniture placement (decor layouts are saved in
-- template space so a layout fits every unit of the type, mirrored or not)
function Units.toFrame(unit: any, x: number, z: number, yaw: number): (number, number, number)
	if unit.mirror then
		return unit.w - x, z, -yaw
	end
	return x, z, yaw
end
Units.fromFrame = Units.toFrame -- the mirror is its own inverse

-------------------------------------------------------------------------------------------------
-- plan time: register a unit and its facade windows
-------------------------------------------------------------------------------------------------
-- edge of the unit rectangle in frame space -> two frame-space points along it
local function edgePoints(L: any, edge: string, a0: number, a1: number): (Vector3, Vector3)
	if edge == "far" then
		return V3(a0, 0, L.d), V3(a1, 0, L.d)
	elseif edge == "entry" then
		return V3(a0, 0, 0), V3(a1, 0, 0)
	elseif edge == "left" then
		return V3(0, 0, a0), V3(0, 0, a1)
	else
		return V3(L.w, 0, a0), V3(L.w, 0, a1)
	end
end

function Units.add(rec: any, fl: any, def: any): any
	local u = Plan.unit(rec, fl, def)
	u.mirror = def.mirror == true
	u.windowKind = def.windowKind
	u.balcony = def.balcony
	local L = Units.layout(u.template, u.mirror)
	u.layout = L
	local ceil = fl.h - Config.SLAB
	for _, wn in L.windows do
		if wn.edge ~= "entry" then
			local p0, p1 = edgePoints(L, wn.edge, wn.a0, wn.a1)
			local q0, q1 = u.frame * p0, u.frame * p1
			local n = u.frame:VectorToWorldSpace(if wn.edge == "far" then V3(0, 0, 1) elseif wn.edge == "left" then V3(-1, 0, 0) else V3(1, 0, 0))
			local side = Plan.sideOf(n)
			local kind = wn.kind or u.windowKind or "window"
			local y0 = wn.y0 or 2.8
			local y1 = wn.y1 or min(8.2, ceil - 1.0)
			if kind == "curtain" then
				y0, y1 = 0.3, ceil - 0.2
			end
			if u.balcony and wn.edge == "far" and kind == "window" then
				kind = "balcony"
				y0 = 0.1
			end
			if not L.standalone then
				Plan.opening(fl, side, Plan.lineOf(side, q0), Plan.along(side, q0), Plan.along(side, q1), y0, y1, kind, { unitId = u.id, zone = if Homes.TEMPLATES[u.template].hotel then "hotel" else "home" })
			end
		end
	end
	return u
end

-------------------------------------------------------------------------------------------------
-- BUILD (structure)
-------------------------------------------------------------------------------------------------
local ROOM_FLOOR = {
	entry = { mat = "CeramicTiles", color = { 150, 146, 140 }, theme = false },
	bath = { mat = "CeramicTiles", color = { 140, 142, 146 }, theme = false },
	veranda = { mat = "CeramicTiles", color = { 176, 170, 160 }, theme = false },
	utility = { mat = "CeramicTiles", color = { 160, 160, 156 }, theme = false },
}
local ROOM_WALL = {
	bath = { mat = "CeramicTiles", color = { 238, 238, 236 }, theme = false },
	veranda = { mat = "Plaster", color = { 236, 234, 228 }, theme = false },
	utility = { mat = "Plaster", color = { 232, 230, 226 }, theme = false },
}

local DOOR_FRONT_YAW = { ["-z"] = 0, ["+z"] = 180, ["-x"] = 90, ["+x"] = -90 }

-- holes on a wall line (frame space) from doors / windows / entrance
local function holesOn(L: any, axis: string, line: number, extra: { any }?): { any }
	local hs = {}
	for _, d in L.doors do
		if d.axis == axis and abs((if axis == "x" then d.z else d.x) - line) < 0.05 then
			local c = if axis == "x" then d.x else d.z
			local h = if d.kind == "opening" then 8.0 elseif d.kind == "glass_slide" then 8.0 else Config.DOOR_H + 0.1
			table.insert(hs, { c - d.w / 2, c + d.w / 2, 0, h })
		end
	end
	for _, e in extra or {} do
		table.insert(hs, e)
	end
	return hs
end

-- is the building-local segment on an exterior edge of the floor?
local function isExterior(fl: any, side: string, line: number, a0: number, a1: number): boolean
	fl._edges = fl._edges or Plan.edges(fl.rects)
	for _, e in fl._edges do
		if e.side == side and abs(e.line - line) < 0.35 and e.a0 <= max(a0, a1) - 0.2 and e.a1 >= min(a0, a1) + 0.2 then
			return true
		end
	end
	return false
end

-- ctx: { rec, fl, parent (floor interior model), wallOnce(key) -> bool }
function Units.build(ctx: any, u: any): Model
	local rec, fl = ctx.rec, ctx.fl
	local L = u.layout
	local w, d = L.w, L.d
	local ceil = fl.h - Config.SLAB
	local frameLocal = CF(0, fl.y, 0) * u.frame
	local frame = rec.cf * frameLocal
	local hotel = Homes.TEMPLATES[u.template].hotel == true
	local m = Kit.model(ctx.parent, "Unit_" .. u.number, {
		UnitId = u.id,
		BuildingId = rec.id,
		Floor = fl.label,
		Template = u.template,
		Tier = u.tier or "",
		Price = u.price,
		ForSale = not hotel,
		OwnerUserId = 0,
		Mirror = u.mirror,
		Frame = frame,
		W = w,
		D = d,
		Label = u.label,
		Hotel = hotel,
	}, { "GwB_Unit" })
	u.model = m
	local st = Kit.model(m, "Structure")
	local fx = Kit.model(m, "Fixtures")
	Kit.model(m, "Furnish")

	-- perimeter walls --------------------------------------------------------------------------
	local PW = 0.6
	local function perim(axis: string, line: number, a0: number, a1: number, holes: { any }, label: string)
		-- frame-space segment -> building-local for the exterior / duplicate test
		local p0 = if axis == "x" then V3(a0, 0, line) else V3(line, 0, a0)
		local p1 = if axis == "x" then V3(a1, 0, line) else V3(line, 0, a1)
		local q0, q1 = u.frame * p0, u.frame * p1
		local nrm = u.frame:VectorToWorldSpace(if axis == "x" then V3(0, 0, if line > 0 then 1 else -1) else V3(if line > 0 then 1 else -1, 0, 0))
		local side = Plan.sideOf(nrm)
		if not L.standalone and isExterior(fl, side, Plan.lineOf(side, q0), Plan.along(side, q0), Plan.along(side, q1)) then
			return
		end
		local key = string.format("%s:%d:%d:%d:%d", fl.label, math.round(min(q0.X, q1.X) * 5), math.round(min(q0.Z, q1.Z) * 5), math.round(max(q0.X, q1.X) * 5), math.round(max(q0.Z, q1.Z) * 5))
		if label ~= "entry" and not L.standalone and not ctx.wallOnce(key) then
			return
		end
		local t = if L.standalone then Config.WALL_EXT else PW
		local mat = if L.standalone then rec.style.wall.mat else "Plaster"
		local col = if L.standalone then rec.tone.wall else { 226, 224, 218 }
		if axis == "x" then
			Kit.wallX(st, frame, a0 - t / 2, a1 + t / 2, line, t, -Config.SLAB, ceil, holes, mat, col, { name = "Wall_" .. label })
		else
			Kit.wallZ(st, frame, a0 - t / 2, a1 + t / 2, line, t, -Config.SLAB, ceil, holes, mat, col, { name = "Wall_" .. label })
		end
	end
	local doorW = L.doorW
	local entryHoles = { { L.door - doorW / 2, L.door + doorW / 2, 0, Config.DOOR_H + 0.1 } }
	local winHoles = { entry = {}, far = {}, left = {}, right = {} }
	for _, wn in L.windows do
		if wn.edge == "entry" or L.standalone then
			local y0 = wn.y0 or 2.8
			local y1 = wn.y1 or min(8.2, ceil - 1)
			table.insert(winHoles[wn.edge], { wn.a0, wn.a1, y0, y1 })
		end
	end
	for _, hh in winHoles.entry do
		table.insert(entryHoles, hh)
	end
	if not u.shellBuilt then
		perim("x", 0, 0, w, entryHoles, "entry")
		perim("z", 0, 0, d, winHoles.left, "left")
		perim("z", w, 0, d, winHoles.right, "right")
		if L.standalone then
			perim("x", d, 0, w, winHoles.far, "far")
			-- roof of a standalone unit (옥탑방)
			Kit.box(st, frame, -0.6, ceil, -0.6, w + 0.6, ceil + 0.8, d + 0.6, "Concrete", rec.style.roof.color, { name = "UnitRoof" })
			-- window glass
			for edge, list in winHoles :: { [string]: { any } } do
				for _, hh in list do
					local p0, p1 = edgePoints(L, edge, hh[1], hh[2])
					local mid = (p0 + p1) / 2
					local len = (p1 - p0).Magnitude
					local yaw = if edge == "far" or edge == "entry" then 0 else 90
					Kit.part(st, frame * CF(mid.X, (hh[3] + hh[4]) / 2, mid.Z) * CFrame.Angles(0, rad(yaw), 0), V3(len, hh[4] - hh[3], 0.15), "Glass", rec.style.glass.color, { tr = rec.style.glass.tr, name = "Glass" })
				end
			end
		end
		-- corridor windows (glass in the entry wall)
		for _, hh in winHoles.entry do
			Kit.part(st, frame * CF((hh[1] + hh[2]) / 2, (hh[3] + hh[4]) / 2, 0), V3(hh[2] - hh[1], hh[4] - hh[3], 0.15), "Glass", { 200, 214, 220 }, { tr = 0.45, name = "CorridorGlass" })
			Kit.part(st, frame * CF((hh[1] + hh[2]) / 2, (hh[3] + hh[4]) / 2, -0.4), V3(hh[2] - hh[1], hh[4] - hh[3], 0.1), "Metal", { 150, 154, 160 }, { tr = 0.55, name = "SecurityBars", collide = false })
		end

		-- entrance door (도어락 / hotel card)
		local entranceKind = L.doorKind or "unit"
		local door = Core.door(st, frame * CF(L.door, 0, 0), {
			w = doorW - 0.2,
			h = Config.DOOR_H,
			t = PW,
			kind = if entranceKind == "double" then "double" else (if hotel then "room" else "unit"),
			lock = if hotel then "room" else "unit",
			unitId = u.id,
			number = if hotel then u.number else u.label,
			hinge = if u.mirror then "right" else "left",
			swing = if hotel then "back" else "front",
			bell = not hotel,
			autoClose = Config.DOOR_UNIT_CLOSE,
			id = "u_" .. u.id,
			color = if entranceKind == "double" then { 60, 50, 44 } else nil,
			mat = if entranceKind == "double" then "Wood" else nil,
		})
		door:SetAttribute("Entrance", true)
		u.doorModel = door
	end

	-- partitions + interior doors -------------------------------------------------------------
	for _, s in L.walls do
		local axis = if abs(s.z1 - s.z0) < 0.01 then "x" else "z"
		local line = if axis == "x" then s.z0 else s.x0
		local hs = holesOn(L, axis, line)
		if axis == "x" then
			Kit.wallX(st, frame, s.x0 - 0.2, s.x1 + 0.2, line, Config.WALL_INT, 0, ceil, hs, "Plaster", { 232, 230, 224 }, { name = "Partition" })
		else
			Kit.wallZ(st, frame, s.z0 - 0.2, s.z1 + 0.2, line, Config.WALL_INT, 0, ceil, hs, "Plaster", { 232, 230, 224 }, { name = "Partition" })
		end
	end
	for i, dd in L.doors do
		if dd.kind ~= "opening" then
			local pos = V3(dd.x, 0, dd.z)
			local yaw = DOOR_FRONT_YAW[dd.front] or 0
			local kind = if dd.kind == "glass_slide" then "sliding_glass" elseif dd.kind == "slide" then "slide" else "swing"
			Core.door(st, frame * CF(pos) * CFrame.Angles(0, rad(yaw), 0), {
				w = dd.w - (if kind == "swing" then 0.2 else 0),
				h = if kind == "sliding_glass" then 7.9 else Config.DOOR_H,
				t = Config.WALL_INT,
				kind = kind,
				hinge = dd.hinge or "left",
				swing = dd.swing or "both",
				unitId = u.id,
				id = u.id .. "_d" .. i,
				casing = kind ~= "sliding_glass",
			})
		end
	end

	-- rooms: finishes, ceiling, bounds, light + switch ----------------------------------------
	local roomsF = Kit.model(m, "Rooms")
	for _, r in L.rooms do
		local rid = u.id .. ":" .. r.id
		local ff = ROOM_FLOOR[r.kind]
		local floorMat = if ff then ff.mat else "WoodPlanks"
		local floorCol = if ff then ff.color else { 204, 168, 122 }
		local f = Kit.box(st, frame, r.x0, 0, r.z0, r.x1, 0.06, r.z1, floorMat, floorCol, { collide = false, name = "Floor" })
		f:SetAttribute("FinishKind", if ff and ff.theme == false then "fixed" else "floor")
		f:SetAttribute("RoomId", rid)
		f:SetAttribute("UnitId", u.id)
		CollectionService:AddTag(f, "GwB_Finish")
		Kit.box(st, frame, r.x0, ceil - 0.08, r.z0, r.x1, ceil, r.z1, F.ceiling.mat, F.ceiling.color, { collide = false, name = "Ceiling" })
		-- wall finishes (wallpaper / tile) on the 4 inner faces, with holes
		local wf = ROOM_WALL[r.kind]
		local wmat = if wf then wf.mat else "Plaster"
		local wcol = if wf then wf.color else { 244, 243, 239 }
		local function panel(axis: string, line: number, a0: number, a1: number, inward: number)
			-- skip open edges (no wall between rooms): perimeter edges always have a wall
			local onPerim = (axis == "x" and (abs(line) < 0.05 or abs(line - d) < 0.05)) or (axis == "z" and (abs(line) < 0.05 or abs(line - w) < 0.05))
			local spans = {}
			if onPerim then
				table.insert(spans, { a0, a1 })
			else
				for _, s in L.walls do
					local sAxis = if abs(s.z1 - s.z0) < 0.01 then "x" else "z"
					if sAxis == axis then
						local sLine = if axis == "x" then s.z0 else s.x0
						if abs(sLine - line) < 0.05 then
							local s0 = if axis == "x" then s.x0 else s.z0
							local s1 = if axis == "x" then s.x1 else s.z1
							local o0, o1 = max(a0, s0), min(a1, s1)
							if o1 - o0 > 0.05 then
								table.insert(spans, { o0, o1 })
							end
						end
					end
				end
			end
			local off = if onPerim then (if (axis == "x" and abs(line - d) < 0.05 and not L.standalone) then 0.44 else 0.34) else 0.24
			if L.standalone and onPerim then
				off = Config.WALL_EXT / 2 + 0.04
			end
			local pl = line + inward * off
			-- holes on this line: doors, windows (far edge from the template list)
			local extra = {}
			if axis == "x" and abs(line) < 0.05 then
				for _, hh in entryHoles do
					table.insert(extra, hh)
				end
			end
			for _, wn in L.windows do
				local wy0 = wn.y0 or 2.8
				local wy1 = wn.y1 or min(8.2, ceil - 1)
				if (wn.kind or u.windowKind) == "curtain" then
					wy0, wy1 = 0.3, ceil - 0.2
				end
				if u.balcony and wn.edge == "far" then
					wy0 = 0.1
				end
				if wn.edge == "far" and axis == "x" and abs(line - d) < 0.05 then
					table.insert(extra, { wn.a0, wn.a1, wy0, wy1 })
				elseif wn.edge == "left" and axis == "z" and abs(line) < 0.05 then
					table.insert(extra, { wn.a0, wn.a1, wy0, wy1 })
				elseif wn.edge == "right" and axis == "z" and abs(line - w) < 0.05 then
					table.insert(extra, { wn.a0, wn.a1, wy0, wy1 })
				end
			end
			local hs = holesOn(L, axis, line, extra)
			for _, sp in spans do
				local parts
				if axis == "x" then
					parts = Kit.wallX(st, frame, sp[1], sp[2], pl, 0.06, 0.06, ceil - 0.08, hs, wmat, wcol, { collide = false, name = "Wallpaper" })
				else
					parts = Kit.wallZ(st, frame, sp[1], sp[2], pl, 0.06, 0.06, ceil - 0.08, hs, wmat, wcol, { collide = false, name = "Wallpaper" })
				end
				for _, p in parts do
					p:SetAttribute("FinishKind", if wf and wf.theme == false then "fixed" else "wall")
					p:SetAttribute("RoomId", rid)
					p:SetAttribute("UnitId", u.id)
					CollectionService:AddTag(p, "GwB_Finish")
				end
			end
		end
		panel("x", r.z0, r.x0, r.x1, 1)
		panel("x", r.z1, r.x0, r.x1, -1)
		panel("z", r.x0, r.z0, r.z1, 1)
		panel("z", r.x1, r.z0, r.z1, -1)
		-- invisible room bounds (rooms, light groups, decor validation)
		local cy = ceil / 2
		local b = Kit.part(roomsF, frame * CF((r.x0 + r.x1) / 2, cy, (r.z0 + r.z1) / 2), V3(r.x1 - r.x0, ceil, r.z1 - r.z0), "SmoothPlastic", { 255, 255, 255 }, {
			tr = 1,
			collide = false,
			touch = false,
			name = "Room_" .. r.id,
			shadow = false,
			attrs = { RoomId = rid, UnitId = u.id, Kind = r.kind, Label = r.label },
			tags = { "GwB_Room" },
		})
		b.CanQuery = false
		-- light
		local area = (r.x1 - r.x0) * (r.z1 - r.z0)
		local lightSize = if area > 120 then V3(4, 0.12, 4) elseif area > 40 then V3(2.6, 0.12, 2.6) else V3(1.6, 0.12, 1.6)
		local lights = {}
		if r.x1 - r.x0 > 30 then
			-- long rooms (penthouse living, sunroom): several lights
			local n = math.floor((r.x1 - r.x0) / 16) + 1
			for k = 1, n do
				local lx = r.x0 + (r.x1 - r.x0) * (k - 0.5) / n
				table.insert(lights, V3(lx, ceil - 0.16, (r.z0 + r.z1) / 2))
			end
		else
			table.insert(lights, V3((r.x0 + r.x1) / 2, ceil - 0.16, (r.z0 + r.z1) / 2))
		end
		for _, lp in lights do
			local _, l = Core.ceilingLight(st, frame * CF(lp), {
				size = lightSize,
				roomId = rid,
				unitId = u.id,
				range = if area > 120 then 26 else 18,
				brightness = if r.kind == "bath" then 1.2 else 1.05,
				on = false,
			})
			l:SetAttribute("RoomId", rid)
		end
		-- switch next to the room's first door (inside), else on the entrance wall
		local sw = nil
		for _, dd in L.doors do
			local onEdge = (dd.axis == "x" and (abs(dd.z - r.z0) < 0.05 or abs(dd.z - r.z1) < 0.05) and dd.x > r.x0 and dd.x < r.x1)
				or (dd.axis == "z" and (abs(dd.x - r.x0) < 0.05 or abs(dd.x - r.x1) < 0.05) and dd.z > r.z0 and dd.z < r.z1)
			if onEdge and dd.kind ~= "opening" then
				sw = dd
				break
			end
		end
		local swCF
		if sw then
			if sw.axis == "x" then
				local inward = if abs(sw.z - r.z0) < 0.05 then 1 else -1
				local sx = sw.x + sw.w / 2 + 0.9
				if sx > r.x1 - 0.5 then
					sx = sw.x - sw.w / 2 - 0.9
				end
				swCF = frame * CF(sx, 4.2, sw.z + inward * 0.29) * CFrame.Angles(0, if inward > 0 then math.pi else 0, 0)
			else
				local inward = if abs(sw.x - r.x0) < 0.05 then 1 else -1
				local sz = sw.z + sw.w / 2 + 0.9
				if sz > r.z1 - 0.5 then
					sz = sw.z - sw.w / 2 - 0.9
				end
				swCF = frame * CF(sw.x + inward * 0.29, 4.2, sz) * CFrame.Angles(0, if inward > 0 then rad(-90) else rad(90), 0)
			end
		elseif r.z0 < 0.05 then
			local sx = if abs(L.door - r.x0) < abs(L.door - r.x1) then min(r.x1 - 0.6, L.door + doorW / 2 + 0.9) else max(r.x0 + 0.6, L.door - doorW / 2 - 0.9)
			swCF = frame * CF(sx, 4.2, 0.39) * CFrame.Angles(0, math.pi, 0)
		end
		if swCF then
			local s = Kit.part(fx, swCF, V3(0.5, 0.75, 0.08), "SmoothPlastic", { 246, 246, 244 }, { name = "Switch", collide = false })
			Kit.part(fx, swCF * CF(0, 0, -0.05), V3(0.3, 0.45, 0.04), "SmoothPlastic", { 230, 230, 228 }, { name = "Rocker", collide = false })
			s:SetAttribute("Kind", "switch")
			s:SetAttribute("RoomIds", rid)
			s:SetAttribute("UnitId", u.id)
			s:SetAttribute("Label", r.label .. " 조명")
			CollectionService:AddTag(s, "GwB_Fixture")
		end
	end

	-- built-in fixtures
	for _, f in L.fixtures do
		local cf = frame * CF(f.x, f.y or 0, f.z) * CFrame.Angles(0, rad(f.yaw), 0)
		local attrs = { UnitId = u.id, Fixed = true }
		if f.attrs then
			for k, v in f.attrs do
				attrs[k] = v
			end
		end
		Furniture.build(f.id, fx, cf, 1, attrs)
	end
	-- 매물 sign beside the door (corridor side) for units for sale
	if not hotel then
		local sign = Kit.part(st, frame * CF(L.door + (if u.mirror then -1 else 1) * (doorW / 2 + 2.0), 6.4, -0.4), V3(2.4, 1.0, 0.1), "SmoothPlastic", { 30, 120, 220 }, { name = "SaleSign", collide = false })
		local _, lbl = Kit.text(sign, "front", "매매 " .. Shared.Util.won(u.price), { color = { 255, 255, 255 }, ppS = 40, maxDist = 40 })
		lbl.Name = "SaleText"
		sign:SetAttribute("SaleSign", true)
		sign:SetAttribute("UnitId", u.id)
	end
	return m
end

-------------------------------------------------------------------------------------------------
-- FURNISH (staging)
-------------------------------------------------------------------------------------------------
function Units.furnish(ctx: any, u: any, into: Instance)
	local rec, fl = ctx.rec, ctx.fl
	local L = u.layout
	local frame = rec.cf * CF(0, fl.y, 0) * u.frame
	local rng = Rng.child(rec.seed, "stage:" .. u.id)
	for i, f in L.stage do
		local def = Furniture.ITEMS[f.id]
		if def then
			-- a few optional decor pieces are skipped at random so staged units differ
			local optional = def.cat == "decor" and i > 3
			if not optional or rng:chance(0.7) then
				local cw = rng:int(1, #def.colors)
				local cf = frame * CF(f.x, f.y or 0, f.z) * CFrame.Angles(0, rad(f.yaw), 0)
				Furniture.build(f.id, into, cf, cw, { UnitId = u.id, Staging = true })
			end
		end
	end
end

-- a unit's world frame and the frame-space bounds usable for furniture
function Units.frameOf(u: any): CFrame
	return u.rec.cf * CF(0, u.fl.y, 0) * u.frame
end

return Units
