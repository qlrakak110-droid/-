-- GwangalliNPCLooks: the shared avatar / outfit generator for every NPC of 광안리 GTA (owner: npc_ambient).
-- Korean street fashion from plain Parts (no uploaded assets): block R15 rigs whose Motor6Ds carry the
-- R15 part / joint names, so Roblox's default R15 animations (GwangalliAnim) play on them.
--
--   local Looks = require(ReplicatedStorage.GwangalliNPCLooks)
--   local spec = Looks.forCitizen(citizen, night?)   -- GwangalliCitizens entry (c.look) -> outfit spec
--   local spec = Looks.random(seed, hint?)           -- anonymous passer-by; hint = { body?, age?, style?, night? }
--   local spec = Looks.resolve(look, seed?, night?)  -- any partial `look` table (the roster's fields)
--   local rig = Looks.build(spec, opts?)             -- builds the model (see below)
--   Looks.restyle(rig, spec, name?)                  -- re-dress a pooled rig (outside the Workspace)
--                                                       as another spec: body resized / recoloured,
--                                                       extras rebuilt, animation tracks kept
--   Looks.key(spec) -> string   stable cache key of an outfit (same spec -> same rig)
--
-- SPEC (pure data, Lune-loadable: colours are {r, g, b} triples):
--   body "f"|"m", age, scale (height factor), width (build factor), skin, hair = {style, color},
--   top = {color, sleeve "short"|"long", trim?, jacket?, apron?, wetsuit?}, bottom = {color, kind
--   "pants"|"shorts"|"skirt"|"longskirt"|"leggings"}, shoes, acc = { name, ... } (see ACCESSORIES),
--   style, night (true = club outfit), seed.
--
-- RIG (Looks.build): Model `opts.name or "NPC"`, PrimaryPart HumanoidRootPart (2x2x1, invisible,
--   Anchored unless opts.anchored == false), R15 parts LowerTorso / UpperTorso / Head / Left|Right
--   UpperArm, LowerArm, Hand / UpperLeg, LowerLeg, Foot and Motor6Ds Root, Waist, Neck, *Shoulder,
--   *Elbow, *Wrist, *Hip, *Knee, *Ankle with identity-oriented joint frames (like R15 rig attachments).
--   Built around the HumanoidRootPart at the origin; the feet stand `rig.ground` studs below it
--   (3 x scale). opts.humanoid = true adds a Humanoid (RigType R15, HipHeight, no name display)
--   instead of an AnimationController; both carry an Animator. Every part: CanCollide / CanTouch /
--   CanQuery false, Massless, CastShadow = opts.shadow == true. A "Phone" part (hidden,
--   Transparency 1) sits in the right hand for phone / photo poses. A face Decal
--   (rbxasset://textures/face.png, shipped with the client) on the head.
--   Returns rig = { model, root, head, parts = {name -> BasePart}, motors = {name -> Motor6D},
--   rest = {name -> C0}, phone, ground, scale, spec, extras = {hair / accessory / phone parts} }.
--   opts: { name, humanoid, anchored, shadow, parent, face = true, cframe (pivot after build) }.

local Looks = {}

Looks.VERSION = 1
Looks.FACE = "rbxasset://textures/face.png"
Looks.GROUND = 3 -- HumanoidRootPart centre above the soles at scale 1
Looks.PARTS = { "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
Looks.MOTORS = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }

-------------------------------------------------------------------------------------------------
-- deterministic randomness (FNV-1a + xorshift)
-------------------------------------------------------------------------------------------------
local function mul32(a: number, b: number): number
	local aLo, aHi = a % 65536, a // 65536
	local bLo, bHi = b % 65536, b // 65536
	return ((aHi * bLo + aLo * bHi) % 65536 * 65536 + aLo * bLo) % 4294967296
end

local function hashString(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = mul32(h, 16777619)
	end
	return h
end
Looks.hash = hashString

local function rngFrom(seed: any): () -> number
	local s: number
	if type(seed) == "number" then
		s = math.floor(math.abs(seed)) % 4294967296
	else
		s = hashString(tostring(seed))
	end
	if s == 0 then
		s = 0x9E3779B9
	end
	return function(): number
		s = bit32.bxor(s, bit32.lshift(s, 13))
		s = bit32.bxor(s, bit32.rshift(s, 17))
		s = bit32.bxor(s, bit32.lshift(s, 5))
		return (s % 1000003) / 1000003
	end
end
Looks.rng = rngFrom

local function pick(list: { any }, r: () -> number): any
	return list[1 + math.floor(r() * #list) % #list]
end

-------------------------------------------------------------------------------------------------
-- Palettes
-------------------------------------------------------------------------------------------------
Looks.SKIN = {
	{ 255, 226, 204 },
	{ 246, 212, 184 },
	{ 234, 194, 160 },
	{ 214, 170, 134 },
	{ 188, 142, 106 },
}

Looks.HAIR_COLOR = {
	black = { 26, 24, 26 },
	darkbrown = { 58, 40, 30 },
	brown = { 104, 70, 44 },
	ash = { 150, 140, 132 },
	blonde = { 222, 190, 128 },
	pink = { 236, 140, 170 },
	gray = { 150, 150, 152 },
	white = { 222, 222, 220 },
	blue = { 70, 110, 190 },
	red = { 150, 50, 44 },
}

local WHITE = { 246, 246, 244 }
local BLACK = { 24, 24, 27 }
local NAVY = { 32, 40, 72 }
local CHAR = { 52, 54, 60 }
local JEANS = { { 70, 96, 140 }, { 48, 66, 104 }, { 104, 130, 170 }, { 36, 40, 52 } }
local PASTEL = { { 250, 200, 205 }, { 196, 222, 250 }, { 210, 236, 206 }, { 252, 236, 190 }, { 222, 206, 246 }, { 250, 250, 250 }, { 240, 220, 200 } }
local BRIGHT = { { 255, 206, 60 }, { 80, 200, 232 }, { 250, 108, 108 }, { 250, 250, 250 }, { 120, 214, 140 }, { 255, 150, 60 } }
local EARTH = { { 150, 120, 90 }, { 110, 120, 90 }, { 180, 150, 120 }, { 90, 70, 60 }, { 200, 184, 160 } }
local MONO = { { 26, 26, 28 }, { 120, 122, 128 }, { 206, 206, 202 }, { 78, 84, 72 }, { 60, 64, 80 } }
local SNEAKER = { { 244, 244, 242 }, { 244, 244, 242 }, { 30, 30, 32 }, { 200, 190, 170 } }
local DRESS = { { 20, 20, 24 }, { 180, 20, 60 }, { 240, 240, 240 }, { 60, 30, 110 }, { 200, 170, 120 }, { 30, 90, 140 } }

-- style -> { top = colours, sleeve, bottom = colours, kind = { f = kinds, m = kinds }, shoes, acc = likely
-- extras, trim / jacket / apron / wetsuit flags }
Looks.STYLES = {
	school = { top = { WHITE }, sleeve = "short", bottom = { NAVY, { 60, 60, 70 } }, kind = { f = { "skirt" }, m = { "pants" } }, shoes = { BLACK, { 244, 244, 242 } }, acc = { "backpack" } },
	office = { top = { WHITE, { 200, 216, 236 }, { 236, 236, 230 } }, sleeve = "long", bottom = { { 40, 46, 62 }, CHAR, BLACK }, kind = { f = { "pants", "skirt" }, m = { "pants" } }, shoes = { { 30, 24, 22 } }, acc = { "tote", "glasses" } },
	casual = { top = PASTEL, sleeve = "short", bottom = JEANS, kind = { f = { "pants", "shorts", "skirt" }, m = { "pants", "shorts" } }, shoes = SNEAKER, acc = { "tote", "cap", "glasses" } },
	street = { top = MONO, sleeve = "long", bottom = { BLACK, { 140, 134, 120 }, { 80, 84, 90 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = SNEAKER, acc = { "cap", "headphones", "backpack" } },
	hoodie = { top = { { 120, 122, 128 }, BLACK, { 200, 170, 150 }, { 60, 80, 120 } }, sleeve = "long", bottom = JEANS, kind = { f = { "pants", "leggings" }, m = { "pants" } }, shoes = SNEAKER, acc = { "headphones", "backpack" } },
	sporty = { top = { WHITE, BLACK, { 230, 90, 110 }, { 60, 120, 200 } }, sleeve = "short", bottom = { BLACK, { 60, 60, 70 } }, kind = { f = { "leggings" }, m = { "shorts" } }, shoes = { WHITE, { 250, 120, 60 } }, acc = { "visor", "earpiece" } },
	surf = { top = { BLACK }, trim = { { 40, 160, 220 }, { 250, 120, 40 }, { 230, 60, 90 } }, sleeve = "long", bottom = { BLACK }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { "skin" }, wetsuit = true, acc = { "surfboard" } },
	apron = { top = { WHITE, BLACK, { 40, 44, 60 } }, sleeve = "short", bottom = { BLACK, { 50, 60, 90 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { BLACK }, apron = { { 30, 110, 76 }, { 130, 80, 44 }, { 40, 40, 44 } } },
	suit = { top = { WHITE }, jacket = { { 28, 30, 38 }, { 50, 54, 66 }, { 90, 80, 70 } }, sleeve = "long", bottom = { { 28, 30, 38 } }, kind = { f = { "pants", "skirt" }, m = { "pants" } }, shoes = { { 20, 18, 18 } } },
	fisher = { top = { { 60, 90, 120 }, { 120, 60, 50 } }, sleeve = "long", bottom = { { 50, 50, 56 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { { 240, 196, 40 } }, apron = { { 240, 196, 40 }, { 220, 90, 40 } }, acc = { "cap" } },
	granny = { top = { { 170, 90, 160 }, { 210, 120, 140 }, { 120, 90, 160 }, { 200, 80, 90 } }, sleeve = "long", bottom = { { 52, 46, 62 }, { 90, 80, 70 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { { 60, 50, 50 } }, acc = { "visor", "tote" } },
	grandpa = { top = { { 180, 160, 120 }, { 90, 110, 90 }, { 150, 150, 160 } }, sleeve = "long", bottom = { { 92, 92, 98 }, { 120, 110, 90 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { { 40, 34, 30 } }, acc = { "cap", "cane" } },
	tourist = { top = BRIGHT, sleeve = "short", bottom = { { 190, 176, 140 }, { 60, 90, 130 }, WHITE }, kind = { f = { "shorts", "skirt" }, m = { "shorts" } }, shoes = SNEAKER, acc = { "camera", "bucket_hat", "sunglasses", "backpack" } },
	rider = { top = { { 40, 190, 185 } }, sleeve = "long", bottom = { BLACK }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { BLACK }, acc = { "helmet" } },
	taxi = { top = { { 172, 202, 232 } }, sleeve = "short", bottom = { { 40, 42, 54 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { BLACK }, acc = { "cap" } },
	artsy = { top = EARTH, sleeve = "long", bottom = { { 60, 60, 70 }, { 190, 176, 150 } }, kind = { f = { "longskirt", "pants" }, m = { "pants" } }, shoes = { { 130, 90, 60 } }, acc = { "bucket_hat", "sketchbook", "glasses" } },
	trendy = { top = { { 232, 216, 190 }, { 250, 242, 232 }, { 204, 176, 204 }, BLACK }, sleeve = "long", bottom = { { 242, 236, 222 }, { 60, 60, 70 }, { 104, 130, 170 } }, kind = { f = { "skirt", "pants", "longskirt" }, m = { "pants" } }, shoes = { WHITE, BLACK }, acc = { "tote", "sunglasses" } },
	chef = { top = { WHITE }, sleeve = "long", bottom = { { 40, 40, 44 }, { 200, 200, 200 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { BLACK }, apron = { WHITE } },
	black = { top = { BLACK }, sleeve = "long", bottom = { BLACK }, kind = { f = { "pants", "skirt" }, m = { "pants" } }, shoes = { BLACK }, acc = { "earpiece" } },
	uniform = { top = { { 34, 44, 80 } }, sleeve = "short", bottom = { { 30, 34, 50 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { BLACK }, acc = { "cap" } },
	lifeguard = { top = { { 230, 50, 44 } }, sleeve = "short", bottom = { { 250, 206, 40 } }, kind = { f = { "shorts" }, m = { "shorts" } }, shoes = { "skin" }, acc = { "visor" } },
	merch = { top = { BLACK }, trim = { { 40, 220, 255 }, { 255, 60, 170 } }, sleeve = "short", bottom = { BLACK, JEANS[2] }, kind = { f = { "pants" }, m = { "pants" } }, shoes = SNEAKER },
	-- npc_mind archetypes: 경찰 (navy shirt + the neon vest as an apron panel + cap), 노숙자 (faded layers),
	-- 걸렁뱅이 (loud colours, open jacket), 불량배 (black / red track suits), 부자 (cream suits, gold trim)
	police = { top = { { 26, 40, 86 } }, sleeve = "long", bottom = { { 22, 28, 48 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { BLACK }, apron = { { 196, 236, 40 } }, acc = { "cap" } },
	shabby = { top = { { 120, 108, 92 }, { 96, 100, 86 }, { 132, 120, 110 } }, jacket = { { 84, 72, 60 }, { 70, 74, 66 } }, sleeve = "long", bottom = { { 82, 76, 66 }, { 70, 70, 74 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { { 60, 52, 44 } }, acc = { "tote" } },
	punk = { top = { { 250, 80, 140 }, { 255, 206, 60 }, { 120, 220, 90 }, WHITE }, jacket = { BLACK, { 120, 30, 40 } }, sleeve = "long", bottom = { BLACK, JEANS[4] }, kind = { f = { "pants", "skirt" }, m = { "pants" } }, shoes = SNEAKER, acc = { "headphones", "sunglasses", "cap" } },
	thug = { top = { BLACK, { 150, 26, 36 }, { 30, 30, 34 } }, trim = { WHITE, { 255, 206, 60 } }, sleeve = "long", bottom = { BLACK, { 40, 40, 46 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { WHITE, BLACK }, acc = { "cap", "sunglasses" } },
	-- 특임대 / 119 / 병원 (Law/Swat, Law/Rescue, Law/Hospital)
	swat = { top = { { 30, 32, 38 } }, sleeve = "long", bottom = { { 26, 28, 34 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { BLACK }, apron = { { 52, 56, 62 } }, acc = { "tac_helmet" } },
	paramedic = { top = { { 236, 110, 40 } }, sleeve = "long", bottom = { { 28, 38, 72 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { BLACK }, apron = { { 214, 236, 60 } } },
	doctor = { top = { { 176, 206, 232 }, { 200, 220, 210 } }, jacket = { WHITE }, sleeve = "long", bottom = { { 60, 70, 90 }, { 40, 44, 56 } }, kind = { f = { "pants", "skirt" }, m = { "pants" } }, shoes = { { 40, 34, 30 }, WHITE } },
	nurse = { top = { { 150, 206, 214 } }, sleeve = "short", bottom = { { 150, 206, 214 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { WHITE } },
	reception = { top = { WHITE }, jacket = { { 40, 70, 110 } }, sleeve = "long", bottom = { { 40, 70, 110 } }, kind = { f = { "skirt", "pants" }, m = { "pants" } }, shoes = { BLACK } },
	gown = { top = { { 176, 200, 226 } }, sleeve = "short", bottom = { { 176, 200, 226 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { { 230, 230, 230 } } },
	luxe = { top = { { 246, 240, 228 }, WHITE, { 30, 30, 34 } }, jacket = { { 232, 220, 196 }, { 26, 26, 30 }, { 120, 24, 40 } }, trim = { { 214, 176, 90 } }, sleeve = "long", bottom = { { 236, 228, 212 }, { 26, 26, 30 } }, kind = { f = { "longskirt", "pants" }, m = { "pants" } }, shoes = { { 120, 70, 40 }, BLACK }, acc = { "sunglasses", "tote" } },
}

-- club outfits (look.night)
Looks.NIGHT = {
	dress = { top = DRESS, sleeve = "none", bottom = "same", kind = { f = { "skirt" }, m = { "pants" } }, shoes = { BLACK, { 200, 170, 120 } } },
	sparkle = { top = { { 212, 212, 220 }, { 220, 180, 110 }, { 200, 120, 200 } }, sleeve = "none", bottom = "same", kind = { f = { "skirt" }, m = { "pants" } }, shoes = { BLACK }, metal = true },
	jacket = { top = { BLACK, WHITE }, jacket = { { 22, 22, 24 }, { 70, 50, 40 } }, sleeve = "long", bottom = { BLACK, JEANS[2] }, kind = { f = { "skirt", "pants" }, m = { "pants" } }, shoes = { BLACK, WHITE } },
	streetnight = { top = MONO, trim = { { 40, 220, 255 }, { 255, 60, 170 }, { 255, 206, 60 } }, sleeve = "long", bottom = { BLACK }, kind = { f = { "pants", "skirt" }, m = { "pants" } }, shoes = SNEAKER },
	black = { top = { BLACK }, sleeve = "long", bottom = { BLACK }, kind = { f = { "skirt", "pants" }, m = { "pants" } }, shoes = { BLACK } },
	suit = { top = { WHITE, BLACK }, jacket = { { 22, 22, 26 }, { 40, 40, 70 } }, sleeve = "long", bottom = { { 22, 22, 26 } }, kind = { f = { "pants" }, m = { "pants" } }, shoes = { BLACK } },
}

local HAIR_F = { "long", "long", "bob", "ponytail", "bun", "wave" }
local HAIR_M = { "short", "short", "side", "twoblock", "perm", "buzz" }
local HC_YOUNG = { "black", "black", "darkbrown", "brown", "ash", "blonde" }
local HC_ADULT = { "black", "black", "darkbrown", "brown" }
local HC_OLD = { "gray", "gray", "white", "black" }

local AGE_SCALE = { teen = 0.93, young = 1, adult = 1, middle = 0.98, senior = 0.95 }
local BUILD_W = { slim = 0.92, avg = 1, broad = 1.1 }

local function styleFor(age: string, body: string, r: () -> number): string
	if age == "teen" then
		return pick({ "school", "casual", "hoodie", "street", "sporty" }, r)
	elseif age == "senior" then
		return if body == "f" then pick({ "granny", "granny", "casual" }, r) else pick({ "grandpa", "grandpa", "casual" }, r)
	elseif age == "middle" then
		return pick({ "office", "casual", "sporty", "suit", "artsy" }, r)
	end
	return pick({ "casual", "casual", "street", "trendy", "hoodie", "office", "sporty", "tourist", "artsy" }, r)
end

-------------------------------------------------------------------------------------------------
-- Spec resolution (pure)
-------------------------------------------------------------------------------------------------
function Looks.resolve(look: any?, seed: any?, night: boolean?): any
	local L = look or {}
	local r = rngFrom(seed or L.seed or "npc")
	local body = if L.body == "f" or L.body == "m" then L.body else (if r() < 0.5 then "f" else "m")
	local age = L.age or pick({ "teen", "young", "young", "adult", "adult", "middle", "senior" }, r)
	local skinIdx = math.clamp(math.floor(tonumber(L.skin) or (1 + math.floor(r() * 4))), 1, #Looks.SKIN)
	local skin = Looks.SKIN[skinIdx]
	local hairStyle = L.hair or (if body == "f" then pick(HAIR_F, r) else pick(HAIR_M, r))
	if age == "senior" and L.hair == nil then
		hairStyle = if body == "f" then "granny_perm" else pick({ "short", "bald", "buzz" }, r)
	end
	local hcName = L.hc or pick(if age == "senior" then HC_OLD elseif age == "teen" or age == "young" then HC_YOUNG else HC_ADULT, r)
	local hairColor = Looks.HAIR_COLOR[hcName] or Looks.HAIR_COLOR.black
	local styleName = L.style or styleFor(age, body, r)
	local isNight = night == true and L.night ~= nil and Looks.NIGHT[L.night] ~= nil
	local st = if isNight then Looks.NIGHT[L.night] else (Looks.STYLES[styleName] or Looks.STYLES.casual)
	local topColor = pick(st.top, r)
	local kinds = (st.kind and st.kind[body]) or { "pants" }
	local kind = pick(kinds, r)
	local bottomColor
	if st.bottom == "same" then
		bottomColor = topColor
	else
		bottomColor = pick(st.bottom :: any, r)
	end
	local shoes = pick(st.shoes, r)
	if shoes == "skin" then
		shoes = skin
	end
	local top: any = { color = topColor, sleeve = st.sleeve or "short" }
	if st.trim then
		top.trim = pick(st.trim, r)
	end
	if st.jacket then
		top.jacket = pick(st.jacket, r)
	end
	if st.apron then
		top.apron = pick(st.apron, r)
	end
	if st.wetsuit then
		top.wetsuit = true
	end
	if st.metal then
		top.metal = true
	end
	-- accessories: the roster's own + sometimes one from the style (anonymous people)
	local acc = {}
	if L.acc then
		table.insert(acc, L.acc)
	elseif not isNight and st.acc and r() < 0.55 then
		table.insert(acc, pick(st.acc, r))
	end
	if not isNight and L.acc == nil and r() < 0.18 and age ~= "senior" then
		local extra = pick({ "glasses", "sunglasses", "tote", "headphones" }, r)
		if extra ~= acc[1] then
			table.insert(acc, extra)
		end
	end
	-- work gear the roster gives (day and night): 배달 box / bag, the scooter
	if type(L.gear) == "table" then
		for _, g in L.gear do
			if not table.find(acc, g) then
				table.insert(acc, g)
			end
		end
	end
	local height = tonumber(L.height) or (0.95 + r() * 0.1)
	local scale = math.clamp(height * (AGE_SCALE[age] or 1) * (if body == "f" then 0.97 else 1), 0.82, 1.15)
	local width = (BUILD_W[L.build or "avg"] or 1) * (if body == "f" then 0.92 else 1)
	return {
		seed = seed or L.seed,
		body = body,
		age = age,
		style = if isNight then L.night else styleName,
		night = isNight,
		scale = math.floor(scale * 100 + 0.5) / 100,
		width = math.floor(width * 100 + 0.5) / 100,
		skin = skin,
		hair = { style = hairStyle, color = hairColor },
		top = top,
		bottom = { color = bottomColor, kind = kind },
		shoes = shoes,
		acc = acc,
	}
end

-- NPC-type accents (npc_types): the roster look is kept, a few fields are nudged so the type reads
-- from afar: 폭력적 = dark street wear, broad, sunglasses; 동네바보 = bright casual + bucket hat;
-- 걸렁뱅이 = worn grandpa colours, no club outfit, a little hunched (height), a paper cup held out in the
-- right hand (acc "cup"); 주정뱅이 = a rumpled office look (no alcohol props anywhere).
Looks.TYPE_ACCENT = {
	violent = { style = "street", build = "broad", acc = "sunglasses", hc = nil },
	fool = { style = "casual", acc = "bucket_hat" },
	beggar = { style = "grandpa", acc = "cup", night = false, height = 0.94 }, -- the paper cup in the right hand
	drunk = { style = "office", acc = nil, height = 0.98 },
}

function Looks.forCitizen(c: any, night: boolean?): any
	if type(c) ~= "table" then
		return Looks.resolve(nil, "npc", night)
	end
	local look = c.look or {}
	local accent = c.type and Looks.TYPE_ACCENT[c.type]
	if accent then
		local l = table.clone(look)
		if accent.style and l.style == nil then
			l.style = accent.style
		elseif accent.style and c.type ~= "fool" then
			l.style = accent.style
		end
		if accent.build then
			l.build = accent.build
		end
		if accent.acc ~= nil then
			l.acc = accent.acc
		elseif c.type == "beggar" or c.type == "drunk" then
			l.acc = nil
		end
		if accent.night == false then
			l.night = nil
		end
		if accent.height and l.height == nil then
			l.height = accent.height
		end
		look = l
	end
	return Looks.resolve(look, look.seed or hashString(tostring(c.id)), night)
end

-- hint = { body?, age?, style?, night? (club outfit name or true = pick one), dog? (walks a dog) }
function Looks.random(seed: any, hint: any?): any
	local h = hint or {}
	local r = rngFrom(tostring(seed) .. "#rnd")
	local look: any = { body = h.body, age = h.age, style = h.style }
	local night = false
	if h.night then
		night = true
		look.night = if type(h.night) == "string" then h.night else pick({ "dress", "jacket", "streetnight", "black", "sparkle", "dress" }, r)
		if look.body == nil then
			look.body = if r() < 0.55 then "f" else "m"
		end
		if look.body == "m" and (look.night == "dress" or look.night == "sparkle") then
			look.night = pick({ "jacket", "streetnight", "black", "suit" }, r)
		end
		look.age = look.age or pick({ "young", "young", "adult" }, r)
	end
	local spec = Looks.resolve(look, seed, night)
	if h.dog then
		-- the leash goes in the right hand: no cane / flyers there
		for i = #spec.acc, 1, -1 do
			if spec.acc[i] == "cane" or spec.acc[i] == "surfboard" then
				table.remove(spec.acc, i)
			end
		end
		table.insert(spec.acc, "dog")
	end
	return spec
end

-- dog breeds (a passer-by's dog): coat, ear / tail shade, size
Looks.DOGS = {
	{ name = "maltese", coat = { 246, 244, 238 }, ear = { 226, 220, 210 }, size = 0.8 },
	{ name = "poodle", coat = { 150, 96, 58 }, ear = { 120, 76, 46 }, size = 0.85 },
	{ name = "shiba", coat = { 214, 140, 70 }, ear = { 190, 116, 54 }, size = 1.0, belly = { 246, 236, 220 } },
	{ name = "jindo", coat = { 236, 226, 206 }, ear = { 214, 200, 176 }, size = 1.15 },
	{ name = "black", coat = { 36, 34, 36 }, ear = { 24, 22, 24 }, size = 1.0 },
	{ name = "corgi", coat = { 222, 150, 80 }, ear = { 200, 126, 62 }, size = 0.9, belly = { 250, 246, 238 }, short = true },
}

local function rgbKey(c: any): string
	return string.format("%d.%d.%d", c[1], c[2], c[3])
end

function Looks.key(spec: any): string
	local t = spec.top
	return table.concat({
		spec.body,
		tostring(spec.scale),
		tostring(spec.width),
		rgbKey(spec.skin),
		spec.hair.style,
		rgbKey(spec.hair.color),
		rgbKey(t.color),
		t.sleeve,
		t.trim and rgbKey(t.trim) or "-",
		t.jacket and rgbKey(t.jacket) or "-",
		t.apron and rgbKey(t.apron) or "-",
		spec.bottom.kind,
		rgbKey(spec.bottom.color),
		rgbKey(spec.shoes),
		table.concat(spec.acc, "+"),
	}, "|")
end

-------------------------------------------------------------------------------------------------
-- Rig geometry (scale 1, HumanoidRootPart centre at the origin, soles at y = -3, facing -Z)
-------------------------------------------------------------------------------------------------
-- joint pivots (world, scale 1, before the width factor on X)
local PIVOT = {
	Root = { 0, -0.8, 0 },
	Waist = { 0, -0.6, 0 },
	Neck = { 0, 1.0, 0 },
	LeftShoulder = { -1.0, 0.76, 0 },
	RightShoulder = { 1.0, 0.76, 0 },
	LeftElbow = { -1.5, -0.1, 0 },
	RightElbow = { 1.5, -0.1, 0 },
	LeftWrist = { -1.5, -1.0, 0 },
	RightWrist = { 1.5, -1.0, 0 },
	LeftHip = { -0.5, -1.0, 0 },
	RightHip = { 0.5, -1.0, 0 },
	LeftKnee = { -0.5, -1.85, 0 },
	RightKnee = { 0.5, -1.85, 0 },
	LeftAnkle = { -0.5, -2.7, 0 },
	RightAnkle = { 0.5, -2.7, 0 },
}
-- part -> { size, centre, motor, parent part }
local BODY = {
	LowerTorso = { { 2, 0.4, 1 }, { 0, -0.8, 0 }, "Root", "HumanoidRootPart" },
	UpperTorso = { { 2, 1.6, 1 }, { 0, 0.2, 0 }, "Waist", "LowerTorso" },
	Head = { { 1.2, 1.2, 1.2 }, { 0, 1.6, 0 }, "Neck", "UpperTorso" },
	LeftUpperArm = { { 1, 1.1, 1 }, { -1.5, 0.37, 0 }, "LeftShoulder", "UpperTorso" },
	RightUpperArm = { { 1, 1.1, 1 }, { 1.5, 0.37, 0 }, "RightShoulder", "UpperTorso" },
	LeftLowerArm = { { 0.96, 1.0, 0.96 }, { -1.5, -0.55, 0 }, "LeftElbow", "LeftUpperArm" },
	RightLowerArm = { { 0.96, 1.0, 0.96 }, { 1.5, -0.55, 0 }, "RightElbow", "RightUpperArm" },
	LeftHand = { { 0.8, 0.4, 0.8 }, { -1.5, -1.22, 0 }, "LeftWrist", "LeftLowerArm" },
	RightHand = { { 0.8, 0.4, 0.8 }, { 1.5, -1.22, 0 }, "RightWrist", "RightLowerArm" },
	LeftUpperLeg = { { 1, 0.95, 1 }, { -0.5, -1.425, 0 }, "LeftHip", "LowerTorso" },
	RightUpperLeg = { { 1, 0.95, 1 }, { 0.5, -1.425, 0 }, "RightHip", "LowerTorso" },
	LeftLowerLeg = { { 0.96, 0.95, 0.96 }, { -0.5, -2.275, 0 }, "LeftKnee", "LeftUpperLeg" },
	RightLowerLeg = { { 0.96, 0.95, 0.96 }, { 0.5, -2.275, 0 }, "RightKnee", "RightUpperLeg" },
	LeftFoot = { { 0.96, 0.3, 1.14 }, { -0.5, -2.85, -0.08 }, "LeftAnkle", "LeftLowerLeg" },
	RightFoot = { { 0.96, 0.3, 1.14 }, { 0.5, -2.85, -0.08 }, "RightAnkle", "RightLowerLeg" },
}
Looks.BODY = BODY
Looks.PIVOT = PIVOT

-- width factor applies to the torso width and to how far out the arms sit
local function wx(x: number, name: string, w: number): number
	if name == "LeftUpperArm" or name == "RightUpperArm" or name == "LeftLowerArm" or name == "RightLowerArm" or name == "LeftHand" or name == "RightHand" or name == "LeftElbow" or name == "RightElbow" or name == "LeftWrist" or name == "RightWrist" then
		local inner = (math.abs(x) - 1.5) + 1 + 0.5 * w -- arm centre follows the shoulder edge
		return math.sign(x) * inner
	elseif name == "LeftShoulder" or name == "RightShoulder" then
		return x * w
	elseif name == "LeftHip" or name == "RightHip" or name == "LeftKnee" or name == "RightKnee" or name == "LeftAnkle" or name == "RightAnkle" or name == "LeftUpperLeg" or name == "RightUpperLeg" or name == "LeftLowerLeg" or name == "RightLowerLeg" or name == "LeftFoot" or name == "RightFoot" then
		return x * (0.5 + 0.5 * w)
	end
	return x
end

-- Which body parts show skin, clothes or shoes
local function partColor(spec: any, name: string): any
	local top, bottom = spec.top, spec.bottom
	if name == "Head" or name == "LeftHand" or name == "RightHand" then
		return spec.skin
	elseif name == "UpperTorso" then
		return top.color
	elseif name == "LeftUpperArm" or name == "RightUpperArm" then
		return if top.sleeve == "none" then spec.skin else top.color
	elseif name == "LeftLowerArm" or name == "RightLowerArm" then
		return if top.sleeve == "long" then top.color else spec.skin
	elseif name == "LowerTorso" then
		return if bottom.kind == "skirt" or bottom.kind == "longskirt" then bottom.color else bottom.color
	elseif name == "LeftUpperLeg" or name == "RightUpperLeg" then
		return bottom.color
	elseif name == "LeftLowerLeg" or name == "RightLowerLeg" then
		if bottom.kind == "shorts" or bottom.kind == "skirt" then
			return spec.skin
		end
		return bottom.color
	elseif name == "LeftFoot" or name == "RightFoot" then
		return spec.shoes
	end
	return spec.skin
end
Looks.partColor = partColor

-------------------------------------------------------------------------------------------------
-- Build (Roblox)
-------------------------------------------------------------------------------------------------
local function c3(t: any): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function shade(t: any, k: number): any
	return { math.clamp(math.floor(t[1] * k), 0, 255), math.clamp(math.floor(t[2] * k), 0, 255), math.clamp(math.floor(t[3] * k), 0, 255) }
end

local templates: { [boolean]: Part } = {}
local function templatePart(shadow: boolean): Part
	local t = templates[shadow]
	if t then
		return t
	end
	t = Instance.new("Part")
	t.Material = Enum.Material.SmoothPlastic
	t.TopSurface = Enum.SurfaceType.Smooth
	t.BottomSurface = Enum.SurfaceType.Smooth
	t.CanCollide = false
	t.CanTouch = false
	t.CanQuery = false
	t.Massless = true
	t.CastShadow = shadow
	t.Anchored = false
	templates[shadow] = t
	return t
end


-- rig-local layout of a body (scale s, width w): part sizes / centres and joint pivots
local function partSize(name: string, s: number, w: number): Vector3
	local sz = BODY[name][1]
	local sx = sz[1]
	if name == "UpperTorso" or name == "LowerTorso" then
		sx = sz[1] * w
	elseif name == "LeftUpperArm" or name == "RightUpperArm" or name == "LeftLowerArm" or name == "RightLowerArm" then
		sx = sz[1] * (0.85 + 0.15 * w)
	end
	return Vector3.new(sx * s, sz[2] * s, sz[3] * s)
end

local function partCentre(name: string, s: number, w: number): Vector3
	local ctr = BODY[name][2]
	return Vector3.new(wx(ctr[1], name, w) * s, ctr[2] * s, ctr[3] * s)
end

local function pivotPos(mname: string, s: number, w: number): Vector3
	local pv = PIVOT[mname]
	return Vector3.new(wx(pv[1], mname, w) * s, pv[2] * s, pv[3] * s)
end

-- sizes, rest CFrames, joint frames (identity-oriented, at the pivots) and base colours of the body.
-- The root is put at the origin: only call this on a rig outside the Workspace (build / pool).
local function layoutBody(rig: any, spec: any)
	local s = spec.scale or 1
	local w = spec.width or 1
	local parts, motors, rest = rig.parts, rig.motors, rig.rest
	local root = rig.root
	root.Size = Vector3.new(2 * s, 2 * s, 1 * s)
	root.CFrame = CFrame.new()
	local centre: { [string]: Vector3 } = { HumanoidRootPart = Vector3.zero }
	for _, name in Looks.PARTS do
		local p = parts[name]
		local c = partCentre(name, s, w)
		centre[name] = c
		p.Size = partSize(name, s, w)
		p.CFrame = CFrame.new(c)
		p.Color = c3(partColor(spec, name))
	end
	if rig.metal then
		local torso = parts.UpperTorso
		torso.Material = Enum.Material.SmoothPlastic
		torso.Reflectance = 0
		rig.metal = false
	end
	for _, name in Looks.PARTS do
		local d = BODY[name]
		local mname = d[3]
		local m = motors[mname]
		local pv = pivotPos(mname, s, w)
		local c0 = CFrame.new(pv - centre[d[4]])
		m.C0 = c0
		m.C1 = CFrame.new(pv - centre[name])
		rest[mname] = c0
	end
	rig.centre = centre
end

-- clothes details, hair, accessories and the hand phone (every extra part goes in rig.extras)
local function dress(rig: any, spec: any)
	local s = spec.scale or 1
	local w = spec.width or 1
	local model = rig.model
	local parts = rig.parts
	local extras = rig.extras
	local centre = rig.centre
	local tpl = templatePart(rig.shadow == true)

	local function newPart(name: string, size: Vector3, cf: CFrame, color: any, shape: Enum.PartType?): Part
		local p = tpl:Clone()
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = cf
		p.Color = c3(color)
		p.Parent = model
		table.insert(extras, p)
		return p
	end
	local function weld(p: BasePart, to: BasePart)
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = to
		wc.Part1 = p
		wc.Parent = p
	end
	local function acc(name: string, size: Vector3, cf: CFrame, color: any, to: BasePart, shape: Enum.PartType?, mat: Enum.Material?): Part
		local p = newPart(name, size * s, cf, color, shape)
		if mat then
			p.Material = mat
		end
		weld(p, to)
		return p
	end
	local head = parts.Head
	local torso = parts.UpperTorso
	local lower = parts.LowerTorso
	local hc = CFrame.new(centre.Head)
	local tc = CFrame.new(centre.UpperTorso)
	local lc = CFrame.new(centre.LowerTorso)
	local rhc = CFrame.new(centre.RightHand)
	local lhc = CFrame.new(centre.LeftHand)
	local function H(x: number, y: number, z: number): CFrame
		return hc * CFrame.new(x * s, y * s, z * s)
	end
	local function T(x: number, y: number, z: number): CFrame
		return tc * CFrame.new(x * s, y * s, z * s)
	end

	-- clothes details ------------------------------------------------------------------------
	local top, bottom = spec.top, spec.bottom
	local tw = 2 * w
	if top.metal then
		torso.Material = Enum.Material.Foil
		torso.Reflectance = 0.15
		rig.metal = true
	end
	if top.wetsuit and top.trim then
		acc("WetsuitStripe", Vector3.new(tw + 0.04, 0.22, 1.04), T(0, 0.35, 0), top.trim, torso)
	elseif top.trim then
		acc("PrintStripe", Vector3.new(tw * 0.6, 0.18, 0.04), T(0, 0.3, -0.52), top.trim, torso, nil, Enum.Material.Neon)
	end
	if top.jacket then
		for _, sx in { -1, 1 } do
			acc("JacketPanel", Vector3.new(tw * 0.3, 1.64, 1.08), T(sx * (tw / 2 - tw * 0.15 + 0.02), 0.0, 0), top.jacket, torso)
		end
		for _, side in { "Left", "Right" } do
			parts[side .. "UpperArm"].Color = c3(top.jacket)
			parts[side .. "LowerArm"].Color = c3(top.jacket)
		end
	end
	if top.apron then
		acc("Apron", Vector3.new(tw * 0.82, 2.0, 0.08), T(0, -0.45, -0.54), top.apron, torso)
	end
	if bottom.kind == "skirt" or bottom.kind == "longskirt" then
		local len = if bottom.kind == "longskirt" then 1.55 else 0.85
		acc("Skirt", Vector3.new(tw + 0.12, len, 1.14), lc * CFrame.new(0, (0.15 - len / 2) * s, 0), bottom.color, lower)
	end

	-- hair -------------------------------------------------------------------------------------
	local hs = spec.hair.style
	local hcol = spec.hair.color
	local hat = false
	for _, a in spec.acc do
		if a == "cap" or a == "bucket_hat" or a == "helmet" then
			hat = true
		end
	end
	local function cap(thick: number)
		if not hat then
			acc("HairTop", Vector3.new(1.28, thick, 1.28), H(0, 0.6 - thick / 2 + 0.08, 0.02), hcol, head)
		end
	end
	if hs == "short" then
		cap(0.34)
		acc("HairBack", Vector3.new(1.28, 0.62, 0.3), H(0, 0.18, 0.5), hcol, head)
	elseif hs == "side" then
		cap(0.36)
		acc("HairBack", Vector3.new(1.28, 0.62, 0.3), H(0, 0.18, 0.5), hcol, head)
		if not hat then
			acc("HairFringe", Vector3.new(1.0, 0.24, 0.26), H(0.1, 0.46, -0.56) * CFrame.Angles(0, 0, -0.18), hcol, head)
		end
	elseif hs == "twoblock" then
		cap(0.44)
		acc("HairBack", Vector3.new(1.24, 0.45, 0.26), H(0, 0.3, 0.52), hcol, head)
	elseif hs == "perm" or hs == "curly" then
		if hat then
			acc("HairBack", Vector3.new(1.3, 0.7, 0.34), H(0, 0.15, 0.5), hcol, head)
		else
			acc("HairCloud", Vector3.new(1.4, 1.4, 1.4), H(0, 0.36, 0.17), hcol, head, Enum.PartType.Ball)
		end
	elseif hs == "buzz" then
		if not hat then
			acc("HairTop", Vector3.new(1.23, 0.12, 1.23), H(0, 0.6, 0), hcol, head)
		end
	elseif hs == "long" or hs == "wave" then
		cap(0.34)
		local len = if hs == "wave" then 1.5 else 1.7
		acc("HairBack", Vector3.new(1.3, len, 0.34), H(0, 0.62 - len / 2, 0.52), hcol, head)
		for _, sx in { -1, 1 } do
			acc("HairSide", Vector3.new(0.18, 1.05, 0.62), H(sx * 0.66, 0.02, 0.2), hcol, head)
		end
	elseif hs == "bob" then
		cap(0.36)
		acc("HairBack", Vector3.new(1.32, 0.95, 0.36), H(0, 0.1, 0.5), hcol, head)
		for _, sx in { -1, 1 } do
			acc("HairSide", Vector3.new(0.2, 0.85, 0.9), H(sx * 0.67, 0.12, 0.08), hcol, head)
		end
	elseif hs == "ponytail" then
		cap(0.34)
		acc("HairBack", Vector3.new(1.28, 0.5, 0.3), H(0, 0.28, 0.5), hcol, head)
		acc("Ponytail", Vector3.new(0.36, 1.0, 0.36), H(0, -0.05, 0.82) * CFrame.Angles(0.25, 0, 0), hcol, head)
	elseif hs == "bun" then
		cap(0.34)
		acc("HairBack", Vector3.new(1.28, 0.5, 0.3), H(0, 0.28, 0.5), hcol, head)
		if not hat then
			acc("HairBun", Vector3.new(0.66, 0.66, 0.66), H(0, 0.78, 0.3), hcol, head, Enum.PartType.Ball)
		end
	elseif hs == "granny_perm" then
		if not hat then
			acc("HairCloud", Vector3.new(1.38, 1.38, 1.38), H(0, 0.4, 0.16), hcol, head, Enum.PartType.Ball)
		end
	elseif hs == "bald" then
		acc("HairRing", Vector3.new(1.26, 0.34, 0.28), H(0, -0.02, 0.52), hcol, head)
	end

	-- accessories ------------------------------------------------------------------------------
	local dark = { 26, 26, 30 }
	for _, a in spec.acc do
		if a == "glasses" then
			acc("Glasses", Vector3.new(1.06, 0.24, 0.05), H(0, 0.1, -0.62), dark, head).Transparency = 0.45
		elseif a == "sunglasses" then
			acc("Sunglasses", Vector3.new(1.1, 0.28, 0.07), H(0, 0.1, -0.63), { 12, 12, 14 }, head)
		elseif a == "cap" then
			local cc = shade(top.color, 0.8)
			acc("CapCrown", Vector3.new(1.3, 0.4, 1.3), H(0, 0.62, 0.02), cc, head)
			acc("CapBrim", Vector3.new(1.16, 0.08, 0.66), H(0, 0.46, -0.9), cc, head)
		elseif a == "bucket_hat" then
			acc("HatCrown", Vector3.new(1.3, 0.45, 1.3), H(0, 0.66, 0), { 214, 204, 180 }, head)
			acc("HatBrim", Vector3.new(1.95, 0.07, 1.95), H(0, 0.46, 0), { 214, 204, 180 }, head)
		elseif a == "visor" then
			acc("VisorBrim", Vector3.new(1.2, 0.07, 0.7), H(0, 0.42, -0.9), { 250, 250, 250 }, head)
			acc("VisorBand", Vector3.new(1.3, 0.16, 1.3), H(0, 0.42, 0), { 250, 250, 250 }, head)
		elseif a == "helmet" then
			acc("Helmet", Vector3.new(1.55, 1.55, 1.55), H(0, 0.3, 0.02), { 240, 240, 240 }, head, Enum.PartType.Ball)
		elseif a == "headphones" then
			acc("HeadphoneBand", Vector3.new(1.46, 0.14, 0.26), H(0, 0.68, 0), dark, head)
			for _, sx in { -1, 1 } do
				acc("EarCup", Vector3.new(0.24, 0.52, 0.52), H(sx * 0.68, 0.05, 0), dark, head)
			end
		elseif a == "earpiece" then
			acc("Earpiece", Vector3.new(0.12, 0.24, 0.12), H(0.64, 0, 0), dark, head)
		elseif a == "backpack" then
			acc("Backpack", Vector3.new(1.5, 1.35, 0.6), T(0, 0.05, 0.8), shade(bottom.color, 1.1), torso)
		elseif a == "tote" then
			acc("ToteBag", Vector3.new(1.0, 1.0, 0.24), T(0.45 * w, -0.75, 0.62), { 232, 222, 196 }, torso)
		elseif a == "camera" then
			acc("Camera", Vector3.new(0.72, 0.5, 0.36), T(0.25, 0.05, -0.68), dark, torso)
		elseif a == "surfboard" then
			acc("Surfboard", Vector3.new(0.22, 5.6, 1.6), T(0, 0.4, 0.72) * CFrame.Angles(0, 0, 0.26), top.trim or { 250, 250, 250 }, torso)
		elseif a == "guitar" then
			acc("GuitarBody", Vector3.new(1.3, 1.5, 0.34), T(0.2, -0.3, 0.72) * CFrame.Angles(0, 0, 0.35), { 150, 90, 50 }, torso)
			acc("GuitarNeck", Vector3.new(0.26, 1.7, 0.18), T(-0.3, 1.2, 0.72) * CFrame.Angles(0, 0, 0.35), { 60, 40, 30 }, torso)
		elseif a == "apron" then
			acc("Apron", Vector3.new(tw * 0.82, 2.0, 0.08), T(0, -0.45, -0.54), { 40, 40, 44 }, torso)
		elseif a == "cane" then
			acc("Cane", Vector3.new(0.16, 2.4, 0.16), rhc * CFrame.new(0, -1.1 * s, -0.25 * s), { 90, 60, 40 }, parts.RightHand)
		elseif a == "cup" then
			-- 걸렁뱅이's paper cup (two parts: the cup + a few coins on top), held out in the right hand
			-- (Cylinder: Size.X is the axis -> rotated 90 deg about Z so the cup stands upright)
			acc("Cup", Vector3.new(0.58, 0.46, 0.46), rhc * CFrame.new(0, -0.2 * s, -0.46 * s) * CFrame.Angles(0, 0, math.pi / 2), { 236, 232, 222 }, parts.RightHand, Enum.PartType.Cylinder)
			acc("CupCoins", Vector3.new(0.06, 0.34, 0.34), rhc * CFrame.new(0, 0.1 * s, -0.46 * s) * CFrame.Angles(0, 0, math.pi / 2), { 212, 175, 72 }, parts.RightHand, Enum.PartType.Cylinder)
		elseif a == "flyers" then
			acc("Flyers", Vector3.new(0.6, 0.1, 0.85), lhc * CFrame.new(0, -0.1 * s, -0.3 * s), { 255, 60, 170 }, parts.LeftHand)
		elseif a == "laptop" then
			acc("Laptop", Vector3.new(0.1, 0.8, 1.1), lhc * CFrame.new(0.45 * s, 0.4 * s, 0), { 170, 172, 178 }, parts.LeftHand)
		elseif a == "sketchbook" then
			acc("Sketchbook", Vector3.new(0.1, 0.9, 1.2), lhc * CFrame.new(0.45 * s, 0.35 * s, 0), { 230, 210, 170 }, parts.LeftHand)
		elseif a == "delivery_bag" then
			-- 도보 배달: the square insulated bag on the back (mint, a white band, a small logo plate)
			acc("DeliveryBag", Vector3.new(1.75, 1.7, 1.15), T(0, -0.05, 1.05), { 40, 190, 185 }, torso)
			acc("DeliveryBagBand", Vector3.new(1.77, 0.24, 1.17), T(0, 0.3, 1.05), { 248, 248, 248 }, torso)
			acc("DeliveryBagLogo", Vector3.new(0.7, 0.42, 0.06), T(0, -0.25, 1.64), { 255, 214, 60 }, torso)
			for _, sx in { -1, 1 } do
				acc("DeliveryStrap", Vector3.new(0.18, 1.5, 0.12), T(sx * 0.55 * w, 0.05, -0.52), { 30, 30, 34 }, torso)
			end
		elseif a == "tac_helmet" then
			-- 특임대 helmet (dark, a little visor) + vest plate
			acc("TacHelmet", Vector3.new(1.42, 0.86, 1.46), H(0, 0.5, 0.02), { 34, 38, 44 }, head)
			acc("TacVisor", Vector3.new(1.2, 0.2, 0.2), H(0, 0.16, -0.68), { 20, 22, 26 }, head).Transparency = 0.25
			acc("TacVest", Vector3.new(tw * 0.92, 1.3, 1.16), T(0, 0.05, 0), { 46, 50, 56 }, torso)
			acc("TacPatch", Vector3.new(0.9, 0.24, 0.05), T(0, 0.35, 0.6), { 230, 230, 230 }, torso)
		elseif a == "rifle" then
			acc("Rifle", Vector3.new(0.2, 0.32, 2.3), rhc * CFrame.new(0.05 * s, 0.05 * s, -0.75 * s), { 24, 24, 28 }, parts.RightHand)
			acc("RifleMag", Vector3.new(0.16, 0.42, 0.24), rhc * CFrame.new(0.05 * s, -0.25 * s, -0.55 * s), { 30, 30, 34 }, parts.RightHand)
		elseif a == "kitbag" then
			acc("KitBag", Vector3.new(1.2, 0.8, 0.55), T(0.5 * w, -1.0, 0.1), { 220, 60, 50 }, torso)
			acc("KitCross", Vector3.new(0.32, 0.32, 0.06), T(0.5 * w, -0.95, -0.2), { 250, 250, 250 }, torso)
		elseif a == "stethoscope" then
			acc("Stetho", Vector3.new(0.9, 0.08, 0.08), T(0, 0.55, -0.55), { 40, 40, 44 }, torso)
			acc("StethoBell", Vector3.new(0.2, 0.2, 0.08), T(0.2, -0.05, -0.56), { 190, 196, 204 }, torso)
		elseif a == "clipboard" then
			acc("Clipboard", Vector3.new(0.1, 0.9, 0.7), lhc * CFrame.new(0.4 * s, 0.3 * s, 0), { 200, 170, 120 }, parts.LeftHand)
		elseif a == "bandage" then
			acc("Bandage", Vector3.new(1.26, 0.26, 1.26), H(0, 0.32, 0), { 248, 248, 248 }, head)
		elseif a == "delivery_box" or a == "scooter" then
			-- built once below (the box rides on the scooter's rear rack)
		elseif a == "stroller" then
			acc("ToteBag", Vector3.new(1.0, 1.0, 0.24), T(0.45 * w, -0.75, 0.62), { 120, 160, 200 }, torso)
		end
	end

	-- 배달 scooter (riders sit on it: the sit loop) + the rear delivery box; welded to the root so the
	-- body animation never moves it. rig.scooter = its parts (GwangalliStreetLife/Delivery hides them
	-- when the rider gets off and leaves a parked copy)
	if table.find(spec.acc, "scooter") or table.find(spec.acc, "delivery_box") then
		local root = rig.root
		local function R0(x: number, y: number, z: number): CFrame
			return CFrame.new(x * s, y * s, z * s)
		end
		local list = {}
		local function sp(name: string, size: Vector3, cf: CFrame, color: any, shape: Enum.PartType?, mat: Enum.Material?): Part
			local p = acc(name, size, cf, color, root, shape, mat)
			table.insert(list, p)
			return p
		end
		local paint = { 205, 45, 50 }
		local dark2 = { 28, 28, 32 }
		if table.find(spec.acc, "scooter") then
			sp("ScooterSeat", Vector3.new(1.1, 0.3, 1.9), R0(0, -1.62, 0.55), dark2)
			sp("ScooterBody", Vector3.new(1.15, 0.9, 2.0), R0(0, -2.15, 0.75), paint)
			sp("ScooterFloor", Vector3.new(1.0, 0.22, 1.5), R0(0, -2.55, -0.8), dark2)
			sp("ScooterShield", Vector3.new(1.05, 1.5, 0.35), R0(0, -1.85, -1.65) * CFrame.Angles(-0.2, 0, 0), paint)
			sp("ScooterStem", Vector3.new(0.22, 1.1, 0.22), R0(0, -0.95, -1.85), dark2)
			sp("ScooterBar", Vector3.new(2.1, 0.16, 0.16), R0(0, -0.45, -1.85), dark2)
			sp("ScooterLamp", Vector3.new(0.5, 0.3, 0.12), R0(0, -1.2, -1.87), { 255, 236, 170 }, nil, Enum.Material.Neon)
			for _, z in { -1.75, 1.35 } do
				sp("ScooterWheel", Vector3.new(0.45, 1.25, 1.25), R0(0, -2.375, z), { 20, 20, 22 }, Enum.PartType.Cylinder)
			end
		end
		if table.find(spec.acc, "delivery_box") then
			sp("DeliveryBox", Vector3.new(1.55, 1.35, 1.35), R0(0, -0.85, 1.6), { 40, 190, 185 })
			sp("DeliveryBoxBand", Vector3.new(1.57, 0.22, 1.37), R0(0, -0.6, 1.6), { 248, 248, 248 })
			sp("DeliveryBoxLogo", Vector3.new(0.06, 0.45, 0.75), R0(0.8, -0.95, 1.6), { 255, 214, 60 })
		end
		rig.scooter = list
		rig.onScooter = table.find(spec.acc, "scooter") ~= nil
	else
		rig.scooter = nil
		rig.onScooter = false
	end

	-- phone in the right hand (hidden until a phone / photo pose shows it)
	local phone = newPart("Phone", Vector3.new(0.34 * s, 0.62 * s, 0.08 * s), rhc * CFrame.new(0, -0.15 * s, -0.42 * s), { 18, 18, 22 })
	phone.Transparency = 1
	weld(phone, parts.RightHand)
	rig.phone = phone

	-- a dog on a leash, trotting at the right side a little ahead: welded to the root (it never
	-- leaves its owner), legs on Motor6Ds (rig.dogLegs / rig.dogRest / rig.dogPhase) so the
	-- street life can swing them while walking. Rig-local: ground at y = -3 * s, facing -Z.
	rig.dogLegs = nil
	rig.dogRest = nil
	rig.dogPhase = nil
	for _, a in spec.acc do
		if a == "dog" then
			local r = rngFrom(tostring(spec.seed) .. "#dog")
			local breed = pick(Looks.DOGS, r)
			local k = breed.size * (0.92 + r() * 0.16)
			local coat, ear = breed.coat, breed.ear
			local root = rig.root
			local gy = -Looks.GROUND * s
			local ox, oz = 2.1 * s, -1.5 * s
			local legH = (if breed.short then 0.4 else 0.62) * k
			local bodyH, bodyL, bodyW = 0.62 * k, 1.5 * k, 0.74 * k
			local by = gy + legH + bodyH / 2
			local bodyCF = CFrame.new(ox, by, oz)
			local function dpart(name: string, size: Vector3, cf: CFrame, color: any, to: BasePart?, shape: Enum.PartType?): Part
				local p = newPart(name, size, cf, color, shape)
				if to then
					weld(p, to)
				end
				return p
			end
			local body = dpart("DogBody", Vector3.new(bodyW, bodyH, bodyL), bodyCF, coat, root)
			if breed.belly then
				dpart("DogBelly", Vector3.new(bodyW * 0.8, 0.08, bodyL * 0.8), bodyCF * CFrame.new(0, -bodyH / 2 - 0.02, 0), breed.belly, body)
			end
			local headCF = bodyCF * CFrame.new(0, bodyH * 0.55, -bodyL / 2 - 0.12 * k)
			local head = dpart("DogHead", Vector3.new(0.66 * k, 0.6 * k, 0.62 * k), headCF, coat, body)
			dpart("DogSnout", Vector3.new(0.34 * k, 0.28 * k, 0.32 * k), headCF * CFrame.new(0, -0.1 * k, -0.44 * k), shade(coat, 0.92), head)
			dpart("DogNose", Vector3.new(0.14 * k, 0.1 * k, 0.06 * k), headCF * CFrame.new(0, -0.02 * k, -0.62 * k), { 20, 18, 18 }, head)
			for _, sx in { -1, 1 } do
				dpart("DogEar", Vector3.new(0.16 * k, 0.28 * k, 0.12 * k), headCF * CFrame.new(sx * 0.22 * k, 0.38 * k, 0.05 * k) * CFrame.Angles(0, 0, -sx * 0.25), ear, head)
			end
			dpart("DogTail", Vector3.new(0.14 * k, 0.14 * k, 0.55 * k), bodyCF * CFrame.new(0, bodyH * 0.45, bodyL / 2 + 0.18 * k) * CFrame.Angles(0.7, 0, 0), shade(coat, 0.95), body)
			-- legs: pivot at the top of each leg, diagonal pairs swing together
			local legs, rest, phase = {}, {}, {}
			local lx, lz = bodyW / 2 - 0.13 * k, bodyL / 2 - 0.18 * k
			for i, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
				local pivot = Vector3.new(ox + c[1] * lx, gy + legH, oz + c[2] * lz)
				local legC = Vector3.new(pivot.X, gy + legH / 2, pivot.Z)
				local leg = dpart("DogLeg", Vector3.new(0.22 * k, legH, 0.22 * k), CFrame.new(legC), coat, nil)
				local m = Instance.new("Motor6D")
				m.Name = "DogHip"
				m.Part0 = body
				m.Part1 = leg
				local c0 = CFrame.new(pivot - bodyCF.Position)
				m.C0 = c0
				m.C1 = CFrame.new(pivot - legC)
				m.Parent = leg
				legs[i] = m
				rest[i] = c0
				phase[i] = if i == 1 or i == 4 then 0 else math.pi
			end
			rig.dogLegs, rig.dogRest, rig.dogPhase = legs, rest, phase
			-- leash: right hand -> collar
			local hand = centre.RightHand + Vector3.new(0, -0.2 * s, 0)
			local collar = (headCF * CFrame.new(0, -0.2 * k, 0.3 * k)).Position
			local len = (collar - hand).Magnitude
			if len > 0.2 then
				dpart("Leash", Vector3.new(0.06, 0.06, len), CFrame.lookAt((hand + collar) / 2, collar), { 200, 40, 60 }, root)
			end
		end
	end
end

function Looks.build(spec: any, opts: any?): any
	local o = opts or {}
	local s = spec.scale or 1
	local shadow = o.shadow == true
	local model = Instance.new("Model")
	model.Name = o.name or "NPC"
	local parts: { [string]: BasePart } = {}
	local motors: { [string]: Motor6D } = {}
	local rest: { [string]: CFrame } = {}

	-- parts are cloned from one template (a few property writes per part instead of 15)
	local tpl = templatePart(shadow)
	local root = tpl:Clone()
	root.Name = "HumanoidRootPart"
	root.Transparency = 1
	root.Anchored = o.anchored ~= false
	root.CastShadow = false
	root.Parent = model
	parts.HumanoidRootPart = root
	model.PrimaryPart = root
	for _, name in Looks.PARTS do
		local p = tpl:Clone()
		p.Name = name
		p.Parent = model
		parts[name] = p
	end
	for _, name in Looks.PARTS do
		local d = BODY[name]
		local m = Instance.new("Motor6D")
		m.Name = d[3]
		m.Part0 = parts[d[4]]
		m.Part1 = parts[name]
		m.Parent = parts[name]
		motors[d[3]] = m
	end
	local rig: any = {
		model = model,
		root = root,
		head = parts.Head,
		parts = parts,
		motors = motors,
		rest = rest,
		extras = {},
		shadow = shadow,
		metal = false,
	}
	layoutBody(rig, spec)
	dress(rig, spec)

	-- face
	if o.face ~= false then
		local decal = Instance.new("Decal")
		decal.Name = "face"
		decal.Face = Enum.NormalId.Front
		decal.Texture = Looks.FACE
		decal.Parent = parts.Head
	end

	-- animation host ------------------------------------------------------------------------------
	if o.humanoid then
		local hum = Instance.new("Humanoid")
		hum.RigType = Enum.HumanoidRigType.R15
		hum.HipHeight = 2 * s
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.Parent = model
		local an = Instance.new("Animator")
		an.Parent = hum
	else
		local ac = Instance.new("AnimationController")
		ac.Parent = model
		local an = Instance.new("Animator")
		an.Parent = ac
	end

	rig.ground = Looks.GROUND * s
	rig.scale = s
	rig.spec = spec
	if o.cframe then
		model:PivotTo(o.cframe)
	end
	if o.parent then
		model.Parent = o.parent
	end
	return rig
end

-- Re-dress a built rig as another spec (pooled pedestrians: a new passer-by costs ~15 Instance.new
-- instead of ~50 and keeps the rig's loaded animation tracks). Body parts and joints are kept and
-- resized / recoloured, the extras (hair, accessories, phone) are rebuilt. The rig must be outside
-- the Workspace (its root is moved to the origin); pivot it afterwards. A Humanoid's HipHeight is
-- updated too. Returns the rig.
function Looks.restyle(rig: any, spec: any, name: string?): any
	for _, p in rig.extras do
		p:Destroy()
	end
	table.clear(rig.extras)
	rig.phone = nil
	if name then
		rig.model.Name = name
	end
	layoutBody(rig, spec)
	dress(rig, spec)
	local s = spec.scale or 1
	if rig.scale ~= s then
		local hum = rig.model:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.HipHeight = 2 * s
		end
	end
	rig.ground = Looks.GROUND * s
	rig.scale = s
	rig.spec = spec
	return rig
end

return Looks
