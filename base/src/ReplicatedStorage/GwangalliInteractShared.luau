-- GwangalliInteractShared: data + pure helpers of the WORLD INTERACTION LAYER (owner: interactions;
-- docs/INTERACTIONS.md). Server: ServerScriptService.GwangalliGameplay.Interact (feature module).
-- Client: StarterPlayerScripts.GwangalliInteract (+ folder GwangalliInteract/*).
--
-- What the layer does ("자유도 지리게"): sit / lie / lean on anything that makes sense (benches,
-- chairs, stools, sofas, sea-wall parapets, stair edges, planters, beach towels, loungers, railings),
-- sunbathing (happiness + a light reversible tan), an emote wheel (Roblox default emotes through
-- Humanoid:PlayEmote + GwangalliAnim procedural emotes / poses), photo mode (orbit camera, filters,
-- polaroid card, 20 photo spots -> popularity), swimming splash + the lifeguard whistle at the buoy
-- line, beach balls / frisbees (server physics, catch), fishing on the 민락항 breakwater (12 species
-- by time of day, sold at the 수산시장 stall), sandcastles, buyable night fireworks, street-food carts
-- (떡볶이 · 어묵 · 호떡 · 붕어빵) and the existing food trucks, vending machines, NPC buskers (tips),
-- stray cats / dogs (client-side), the 포토존 frame and the 인형뽑기 claw machines of 광안 게임랜드.
--
-- CONTRACT FOR OTHER SYSTEMS (also in docs/INTERACTIONS.md):
--   * Tag a BasePart "GwSittable" (+ attribute SitKind = "chair" | "bench" | "sofa" | "edge" |
--     "towel" | "lounger" | "rail" | "seat") and the client hub offers 앉기 / 눕기 / 기대기 on it. A
--     Seat part is used through Seat:Sit; anything else through a temporary invisible Seat.
--     Optional SitFace (Vector3, object space): the direction a sitter faces (benches with a back).
--   * Tag a BasePart "GwInteract" with GwKind (a key of IS.KINDS) + GwId and the hub shows its
--     prompt; the client module registered for that kind handles it (GwangalliInteract/*).
--   * Character attributes (server-set, every client renders them): GwPose (IS.POSES key or Anim
--     pose / act name, "" = none), GwEmote ("<name>#<seq>": one-shot), GwHeld (held prop id), GwTan
--     (0..1). Player attribute GwInteractBusy (string) while a mini-game / sit / photo owns the player.
--   * Nothing here yields or creates instances at require time (safe on server and client).

local IS = {}
IS.VERSION = 1

IS.Tags = {
	Sittable = "GwSittable", -- BasePart: sit / lie / lean target
	Interact = "GwInteract", -- BasePart: world interaction (GwKind, GwId, GwLabel)
	Rig = "GwInteractRig", -- Model: server-built NPC (busker, vendor, beach friend); GwAct = act name
	Ball = "GwBall", -- BasePart: beach ball / frisbee (server physics)
	Prop = "GwInteractProp", -- Model / BasePart created by the layer (cleanup, discovery)
}

IS.Attr = {
	SitKind = "SitKind",
	SitFace = "SitFace",
	SitLean = "SitLean", -- edge parts that are also railing-height (lean offered as the 2nd action)
	Kind = "GwKind",
	Id = "GwId",
	Label = "GwLabel",
	Act = "GwAct",
	Pose = "GwPose",
	Emote = "GwEmote",
	Held = "GwHeld",
	Tan = "GwTan",
	Busy = "GwInteractBusy",
	Holder = "GwHolder", -- ball: UserId of the holder (0 = free)
	BallKind = "GwBallKind", -- "ball" | "frisbee"
	Show = "GwShowAt", -- fireworks: server time the show started
	Castle = "GwCastle",
}

IS.Remote = { Request = "InteractRequest", Event = "InteractEvent" }
IS.STORE = "GwangalliInteract_v1"
IS.STORE_KEY = "u_"
IS.FOLDER = "GwangalliInteract" -- workspace folder of the runtime props (server)

---------------------------------------------------------------------------------------------------
-- Masterplan geometry (mirrors build/kit/plan.luau: sea toward -Z, promenade y 6.5, beach crescent)
---------------------------------------------------------------------------------------------------
local A = 0.0000324
IS.WALK = 6.5
IS.BEACH = { x0 = -2380, x1 = 2380 }
IS.BUOY = { xa = -2040, xb = 1540, d = 170, leg = 40 } -- coast_beach.luau swim-zone buoys

function IS.P(x: number): number
	return -A * x * x
end
function IS.normal(x: number): Vector3 -- inland unit normal
	local s = -2 * A * x
	local k = math.sqrt(1 + s * s)
	return Vector3.new(-s / k, 0, 1 / k)
end
function IS.tangent(x: number): Vector3
	local s = -2 * A * x
	local k = math.sqrt(1 + s * s)
	return Vector3.new(1 / k, 0, s / k)
end
-- Station x / inland offset n -> world point (y defaults to the promenade surface).
function IS.point(x: number, n: number, y: number?): Vector3
	local nn = IS.normal(x)
	return Vector3.new(x + nn.X * n, y or IS.WALK, IS.P(x) + nn.Z * n)
end
function IS.sandWidth(x: number): number
	local t = math.clamp(x / 2380, -1, 1)
	return 280 - 170 * t * t
end
-- Waterline z at world x (approximate, along world z).
function IS.shoreZ(x: number): number
	return IS.P(x) - IS.sandWidth(x)
end

-- On the beach sand (between the sea wall and the waterline), near sand height.
function IS.onBeachSand(pos: Vector3): boolean
	local x = pos.X
	if x < IS.BEACH.x0 + 20 or x > IS.BEACH.x1 - 20 then
		return false
	end
	local z = pos.Z
	return z < IS.P(x) - 2 and z > IS.shoreZ(x) + 3 and pos.Y > -2 and pos.Y < 7
end

-- In the bay off the beach (seaward of the waterline).
function IS.inBay(pos: Vector3): boolean
	local x = pos.X
	return x >= IS.BEACH.x0 and x <= IS.BEACH.x1 and pos.Z < IS.shoreZ(x)
end

-- Seaward of the swim-zone buoy line (and low enough to be swimming, not on a pier / boat deck).
function IS.pastBuoys(pos: Vector3): boolean
	local x = pos.X
	if x < IS.BEACH.x0 or x > IS.BEACH.x1 or pos.Y > 3 or pos.Y < -40 then
		return false
	end
	local sz = IS.shoreZ(x)
	local b = IS.BUOY
	if x >= b.xa and x <= b.xb then
		return pos.Z < sz - b.d - 6
	end
	return pos.Z < sz - b.leg - 6
end

-- A safe point in shallow water just inside the buoy line, straight in from `pos`.
function IS.backInside(pos: Vector3): Vector3
	local x = math.clamp(pos.X, IS.BUOY.xa + 30, IS.BUOY.xb - 30)
	return Vector3.new(x, 1.2, IS.shoreZ(x) - 14)
end

---------------------------------------------------------------------------------------------------
-- Sit heuristics (server classification of map parts; pure)
---------------------------------------------------------------------------------------------------
IS.SIT = {
	reach = 11, -- max studs between the character and the sit point (server check)
	edgeMin = 0.9, -- edge sit: part top above the feet (studs)
	edgeMax = 3.7,
	railMin = 2.3, -- lean on a railing: top above the feet
	railMax = 4.6,
	scanChunk = 4000, -- descendants per server step at start
}

-- name fragments (lower case) that are never a sitting surface
local SKIP = {
	"back", "leg", "foot", "feet", "base", "frame", "post", "arm", "glow", "plinth", "light", "lamp",
	"cable", "stripe", "accent", "shelf", "sign", "neon", "led", "holder", "bar", "trim", "edge",
	"bolt", "screw", "wheel", "engine", "under", "shadow", "rope", "chain", "pole", "panel", "cap",
	"belt", "slot", "window", "rack", "cabinet", "case", "box", "hinge", "pipe", "mount",
}
local function hasSkip(n: string): boolean
	for _, w in SKIP do
		if string.find(n, w, 1, true) then
			return true
		end
	end
	return false
end
local function has(n: string, w: string): boolean
	return string.find(n, w, 1, true) ~= nil
end

-- Classifies one part from its name, class and size. Returns a SitKind or nil. The server adds the
-- context rules (owned venues, vehicles, ground-height checks for edges and rails).
function IS.classify(name: string, className: string, size: Vector3): string?
	if className == "VehicleSeat" then
		return nil
	end
	local n = string.lower(name)
	local sx, sy, sz = size.X, size.Y, size.Z
	local lo, hi = math.min(sx, sz), math.max(sx, sz)
	if className == "Seat" then
		return if lo >= 0.8 then "seat" else nil
	end
	-- lying surfaces
	if has(n, "towel") and not hasSkip(n) and not has(n, "paper") then
		if sy <= 0.6 and lo >= 1.8 and hi >= 3.6 then
			return "towel"
		end
		return nil
	end
	if (has(n, "lounger") or has(n, "sunbed") or has(n, "daybed")) and (has(n, "pad") or has(n, "cushion") or n == "lounger") then
		return if lo >= 1.6 and hi >= 3.4 then "lounger" else nil
	end
	-- edges: sea wall parapets, planters, steps / stair treads (height checked against the ground)
	if has(n, "parapet") and (has(n, "seawall") or has(n, "promenade") or has(n, "wave")) then
		return if sy <= 4.5 and lo >= 0.8 then "edge" else nil
	end
	if has(n, "seatplanter") or has(n, "seatstep") or n == "planter" or has(n, "edgeplanter") or has(n, "planterbox") then
		return if sy <= 4 and lo >= 1.2 then "edge" else nil
	end
	if (n == "step" or n == "steps" or has(n, "stairtread") or has(n, "grandstep") or has(n, "bleacher") or has(n, "terrace")) and not hasSkip(n) then
		return if lo >= 1.2 and hi >= 3 then "edge" else nil
	end
	-- railings (lean only)
	if (n == "rail" or n == "toprail" or has(n, "railing") or has(n, "handrail") or has(n, "guardrail") or has(n, "balustrade") or has(n, "searail")) and not has(n, "post") then
		return if hi >= 2 then "rail" else nil
	end
	if hasSkip(n) and not (has(n, "seat") or has(n, "cushion")) then
		return nil
	end
	-- seats
	local seatish = has(n, "chair") or has(n, "stool") or has(n, "seat") or has(n, "cushion")
	local benchish = has(n, "bench") or has(n, "sofa") or has(n, "couch") or has(n, "settee")
	if benchish then
		if sy > 3 or lo < 0.9 then
			return nil
		end
		if hi >= 3 then
			return if has(n, "sofa") or has(n, "couch") then "sofa" else "bench"
		end
		return "chair"
	end
	if seatish then
		if lo < 0.8 or hi > 14 then
			return nil
		end
		-- a seat cushion / stool top, not a tall slab (a chair modelled as one block back)
		if sy > 1.8 and not (sy <= 3 and lo >= 1.3 and has(n, "stool")) then
			return nil
		end
		if hi >= 4 then
			return "bench"
		end
		return "chair"
	end
	return nil
end

-- Prompt text per sit kind: primary action, secondary action (nil = none).
IS.SIT_ACTIONS = {
	seat = { "앉기", nil },
	chair = { "앉기", nil },
	bench = { "앉기", "눕기" },
	sofa = { "앉기", "눕기" },
	edge = { "걸터앉기", nil },
	towel = { "선탠하기", "앉기" },
	lounger = { "눕기", "앉기" },
	rail = { "기대기", nil },
}
IS.SIT_LABEL = {
	seat = "의자", chair = "의자", bench = "벤치", sofa = "소파", edge = "턱", towel = "비치 타월", lounger = "선베드", rail = "난간",
}

---------------------------------------------------------------------------------------------------
-- Poses (GwangalliAnim rig-controller tables: { pitch, yaw, roll, dx, dy, dz } in degrees / studs;
-- see GwangalliAnim's header for the conventions). Seated poses layer over the default sit track.
---------------------------------------------------------------------------------------------------
IS.POSES = {
	-- lying on the back on a seat (cancels the sit track's bent hips / knees)
	lie = {
		Root = { 88, 0, 0, 0, -0.85, 0 },
		RightHip = { -86, 0, 4 },
		LeftHip = { -86, 0, -4 },
		RightKnee = { 84, 0, 0 },
		LeftKnee = { 84, 0, 0 },
		RightShoulder = { 20, 0, 18 },
		LeftShoulder = { 20, 0, -18 },
		Neck = { -14, 0, 0 },
	},
	-- sunbathing: lying + hands behind the head
	sunbathe = {
		Root = { 88, 0, 0, 0, -0.85, 0 },
		RightHip = { -86, 0, 6 },
		LeftHip = { -86, 0, -6 },
		RightKnee = { 84, 0, 0 },
		LeftKnee = { 84, 0, 0 },
		RightShoulder = { 150, 0, 34 },
		RightElbow = { 118, 0, 0 },
		LeftShoulder = { 150, 0, -34 },
		LeftElbow = { 118, 0, 0 },
		Neck = { -10, 0, 0 },
	},
	-- relaxed seated (hands on the knees) / legs crossed on a bench
	sit_relax = { RightShoulder = { 14, 0, -4 }, RightElbow = { 34, 0, 0 }, LeftShoulder = { 14, 0, 4 }, LeftElbow = { 34, 0, 0 }, Neck = { -4, 0, 0 } },
	sit_edge = { RightShoulder = { -10, 0, 16 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -10, 0, -16 }, LeftElbow = { 10, 0, 0 }, RightKnee = { 10, 0, 0 }, LeftKnee = { 22, 0, 0 }, Neck = { 4, 0, 0 } },
	-- back against a wall, one foot up, arms crossed
	lean_back = {
		Root = { 7, 0, 0, 0, -0.05, 0.25 },
		Waist = { 3, 0, 0 },
		RightShoulder = { 40, 90, 0 },
		RightElbow = { 112, 0, 0 },
		LeftShoulder = { 46, -90, 0 },
		LeftElbow = { 108, 0, 0 },
		RightHip = { 34, 0, 6 },
		RightKnee = { -62, 0, 0 },
		Neck = { 4, 8, 0 },
	},
	-- forearms on a railing / parapet, looking out
	lean_rail = {
		Root = { -16, 0, 0, 0, -0.1, -0.35 },
		Waist = { -10, 0, 0 },
		RightShoulder = { 70, 12, -6 },
		RightElbow = { 92, 0, 0 },
		LeftShoulder = { 70, -12, 6 },
		LeftElbow = { 92, 0, 0 },
		RightHip = { 10, 0, 0 },
		LeftKnee = { -14, 0, 0 },
		Neck = { 22, 0, 0 },
	},
	-- sitting on the ground hugging the knees (standing humanoid, body lowered)
	sit_ground = {
		Root = { 0, 0, 0, 0, -1.75, 0.2 },
		RightHip = { 108, 0, 10 },
		LeftHip = { 108, 0, -10 },
		RightKnee = { -146, 0, 0 },
		LeftKnee = { -146, 0, 0 },
		RightShoulder = { 46, 50, 0 },
		RightElbow = { 54, 0, 0 },
		LeftShoulder = { 46, -50, 0 },
		LeftElbow = { 54, 0, 0 },
		Waist = { -10, 0, 0 },
	},
	heart = { RightShoulder = { 168, 0, 34 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 168, 0, -34 }, LeftElbow = { 100, 0, 0 }, Neck = { 4, 0, 6 } },
	v_sign = { RightShoulder = { 116, 0, 4 }, RightElbow = { 120, 0, 0 }, RightWrist = { -10, 0, 0 }, LeftShoulder = { 0, 0, -30 }, LeftElbow = { 0, 0, 100 }, Neck = { 0, 0, -10 }, Waist = { 0, 0, 4 } },
	eat = { RightShoulder = { 40, 20, -8 }, RightElbow = { 118, 0, 0 }, LeftShoulder = { 30, -20, 8 }, LeftElbow = { 86, 0, 0 }, Neck = { -10, 0, 0 } },
	drink = { RightShoulder = { 52, 26, -4 }, RightElbow = { 136, 0, 0 }, Neck = { 18, 0, 0 } },
	hold_front = { RightShoulder = { 40, 40, 0 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 40, -40, 0 }, LeftElbow = { 70, 0, 0 } },
	hold_one = { RightShoulder = { 18, 0, -6 }, RightElbow = { 84, 0, 0 } },
	fish_hold = { RightShoulder = { 62, 0, -10 }, RightElbow = { 42, 0, 0 }, LeftShoulder = { 54, 0, 14 }, LeftElbow = { 52, 0, 0 }, Neck = { -6, 0, 0 } },
	pet_low = { Root = { 0, 0, 0, 0, -1.1, 0 }, RightHip = { 110, 0, 6 }, LeftHip = { 110, 0, -6 }, RightKnee = { -130, 0, 0 }, LeftKnee = { -130, 0, 0 }, Waist = { -20, 0, 0 }, RightShoulder = { 70, 0, -6 }, RightElbow = { 20, 0, 0 } },
	build_sand = { Root = { 0, 0, 0, 0, -1.4, 0 }, RightHip = { 116, 0, 10 }, LeftHip = { 116, 0, -10 }, RightKnee = { -140, 0, 0 }, LeftKnee = { -140, 0, 0 }, Waist = { -26, 0, 0 }, RightShoulder = { 60, 20, 0 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 60, -20, 0 }, LeftElbow = { 40, 0, 0 } },
	throw_ready = { RightShoulder = { 150, 0, -10 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 50, 0, 10 }, LeftElbow = { 20, 0, 0 }, Waist = { 4, -14, 0 } },
	claw_play = { RightShoulder = { 46, 10, -6 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 46, -10, 6 }, LeftElbow = { 60, 0, 0 }, Neck = { 6, 0, 0 } },
}
-- Poses that are also GwangalliAnim pose / act names (validated by the server for GwPose).
IS.ANIM_POSES = {
	phone = true, camera = true, arms_crossed = true, stretch = true, squat = true, hips = true, pockets = true, guitar = true, fish = true,
	hands_behind = true, shade_eyes = true, cup = true,
}
function IS.validPose(name: any): boolean
	return type(name) == "string" and (name == "" or IS.POSES[name] ~= nil or IS.ANIM_POSES[name] == true)
end

---------------------------------------------------------------------------------------------------
-- Emote wheel (3 pages + photo mode)
---------------------------------------------------------------------------------------------------
-- kind: "emote" = Humanoid:PlayEmote default emote (Animate script) with a GwangalliAnim track
-- fallback; "proc" = GwangalliAnim procedural one-shot (Anim.EMOTES); "pose" = toggled pose (until
-- the player moves).
IS.EMOTE_PAGES = {
	{
		title = "인사 · 춤",
		items = {
			{ id = "wave", kind = "emote", label = "인사", icon = "👋" },
			{ id = "point", kind = "emote", label = "가리키기", icon = "👉" },
			{ id = "cheer", kind = "emote", label = "환호", icon = "🙌" },
			{ id = "laugh", kind = "emote", label = "웃음", icon = "😂" },
			{ id = "dance", kind = "emote", label = "춤 1", icon = "💃" },
			{ id = "dance2", kind = "emote", label = "춤 2", icon = "🕺" },
			{ id = "dance3", kind = "emote", label = "춤 3", icon = "🪩" },
			{ id = "bow", kind = "proc", label = "꾸벅", icon = "🙇" },
		},
	},
	{
		title = "리액션",
		items = {
			{ id = "clap", kind = "proc", label = "박수", icon = "👏" },
			{ id = "thumbs", kind = "proc", label = "최고", icon = "👍" },
			{ id = "shrug", kind = "proc", label = "글쎄", icon = "🤷" },
			{ id = "facepalm", kind = "proc", label = "아이고", icon = "🤦" },
			{ id = "shy", kind = "proc", label = "수줍", icon = "☺️" },
			{ id = "think", kind = "proc", label = "생각", icon = "🤔" },
			{ id = "beckon", kind = "proc", label = "이리 와", icon = "🫴" },
			{ id = "nod", kind = "proc", label = "끄덕", icon = "🙂" },
		},
	},
	{
		title = "포즈",
		items = {
			{ id = "heart", kind = "pose", label = "하트", icon = "🫶" },
			{ id = "v_sign", kind = "pose", label = "브이", icon = "✌️" },
			{ id = "sit_ground", kind = "pose", label = "바닥 앉기", icon = "🧘" },
			{ id = "squat", kind = "pose", label = "쪼그려", icon = "🧎" },
			{ id = "arms_crossed", kind = "pose", label = "팔짱", icon = "🙅" },
			{ id = "phone", kind = "pose", label = "폰 보기", icon = "📱" },
			{ id = "camera", kind = "pose", label = "찰칵", icon = "📷" },
			{ id = "stretch", kind = "pose", label = "기지개", icon = "🙆" },
		},
	},
}
IS.EMOTE_BY_ID = {} :: { [string]: any }
for _, page in IS.EMOTE_PAGES do
	for _, it in page.items do
		IS.EMOTE_BY_ID[it.id] = it
	end
end
-- Roblox default emote name for Humanoid:PlayEmote, and the GwangalliAnim track fallback
IS.DEFAULT_EMOTES = { wave = "wave", point = "point", cheer = "cheer", laugh = "laugh", dance = "dance", dance2 = "dance2", dance3 = "dance3" }
IS.EMOTE_TRACK = { wave = "wave", point = "point", cheer = "cheer", laugh = "laugh", dance = "dance1", dance2 = "dance2", dance3 = "dance3" }

---------------------------------------------------------------------------------------------------
-- Photo mode: filters + 20 photo spots (popularity +1 for each new one)
---------------------------------------------------------------------------------------------------
IS.FILTERS = {
	{ id = "none", label = "기본", cc = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = { 255, 255, 255 } } },
	{ id = "sunset", label = "노을", cc = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.18, TintColor = { 255, 222, 196 } } },
	{ id = "ocean", label = "바다", cc = { Brightness = 0.02, Contrast = 0.05, Saturation = 0.1, TintColor = { 206, 232, 255 } } },
	{ id = "vivid", label = "선명", cc = { Brightness = 0.02, Contrast = 0.18, Saturation = 0.42, TintColor = { 255, 255, 255 } } },
	{ id = "film", label = "필름", cc = { Brightness = 0.04, Contrast = -0.08, Saturation = -0.22, TintColor = { 255, 240, 214 } } },
	{ id = "mono", label = "흑백", cc = { Brightness = 0.02, Contrast = 0.16, Saturation = -1, TintColor = { 255, 255, 255 } } },
	{ id = "night", label = "야경", cc = { Brightness = 0.05, Contrast = 0.12, Saturation = 0.3, TintColor = { 220, 210, 255 } } },
}

-- { id, name, pos, r (horizontal radius), yMin?, yMax? }
IS.PHOTO_SPOTS = {
	{ id = "plaza", name = "광안리 만남의 광장", pos = Vector3.new(-250, 7, 24), r = 70 },
	{ id = "beach", name = "광안리해수욕장 한가운데", pos = Vector3.new(-20, 3, -90), r = 110, yMax = 40 },
	{ id = "frame", name = "광안대교 뷰 포토존", pos = Vector3.new(120, 4, -40), r = 26, yMax = 30 },
	{ id = "sup", name = "광안리 SUP존", pos = Vector3.new(1716, 3, -136), r = 90, yMax = 40 },
	{ id = "leports", name = "광안리 해양레포츠센터", pos = Vector3.new(2354, 4, -339), r = 80, yMax = 60 },
	{ id = "namcheon", name = "남천해변공원", pos = Vector3.new(2501, 7, -199), r = 100, yMax = 60 },
	{ id = "samik", name = "삼익비치 해안 산책로", pos = Vector3.new(3306, 7, -360), r = 140, yMax = 80 },
	{ id = "millakpark", name = "민락수변공원", pos = Vector3.new(-3679, 7, -531), r = 160, yMax = 60 },
	{ id = "busking", name = "밀락더마켓 버스킹 스퀘어", pos = Vector3.new(-3194, 7, -530), r = 80, yMax = 60 },
	{ id = "fishmarket", name = "민락 활어직판장", pos = Vector3.new(-2930, 4, -323), r = 70, yMax = 60 },
	{ id = "hoetown", name = "민락회타운 골목", pos = Vector3.new(-2582, 7, -118), r = 70, yMax = 60 },
	{ id = "breakwater", name = "민락항 방파제", pos = Vector3.new(-2700, 4, -510), r = 150, yMax = 40 },
	{ id = "bridge", name = "광안대교 위", pos = Vector3.new(0, 150, -3282), r = 1500, yMin = 90 },
	{ id = "bread", name = "빵천동 빵집골목", pos = Vector3.new(2975, 7, 300), r = 80, yMax = 60 },
	{ id = "info", name = "광안리 관광안내소", pos = Vector3.new(105, 7, 112), r = 45, yMax = 40 },
	{ id = "hotelrow", name = "광안해변로 호텔 거리", pos = Vector3.new(-42, 7, 110), r = 60, yMax = 40 },
	{ id = "rooftop", name = "호텔 루프탑 라운지", pos = Vector3.new(209, 75, 135), r = 45, yMin = 60, yMax = 110 },
	{ id = "infinity", name = "인피니티풀 루프탑", pos = Vector3.new(-60, 258, 155), r = 70, yMin = 220 },
	{ id = "arcade", name = "광안 게임랜드 오락실", pos = Vector3.new(-330, 7, 433), r = 45, yMax = 40 },
	{ id = "station", name = "지하철 광안역 앞", pos = Vector3.new(-280, 9, 850), r = 80, yMax = 60 },
}
IS.PHOTO_BY_ID = {} :: { [string]: any }
for _, s in IS.PHOTO_SPOTS do
	IS.PHOTO_BY_ID[s.id] = s
end

function IS.photoSpotAt(pos: Vector3): any?
	local best, bestD = nil, math.huge
	for _, s in IS.PHOTO_SPOTS do
		if (s.yMin == nil or pos.Y >= s.yMin) and (s.yMax == nil or pos.Y <= s.yMax) then
			local dx, dz = pos.X - s.pos.X, pos.Z - s.pos.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= s.r and d / s.r < bestD then
				best, bestD = s, d / s.r
			end
		end
	end
	return best
end

-- A readable place name anywhere on the map (photo cards, fish cards).
function IS.areaName(pos: Vector3): string
	local spot = IS.photoSpotAt(pos)
	if spot then
		return spot.name
	end
	if pos.Y > 60 and pos.Z < -1500 then
		return "광안대교"
	end
	local x, z = pos.X, pos.Z
	if x >= IS.BEACH.x0 and x <= IS.BEACH.x1 then
		if z < IS.shoreZ(x) then
			return "광안리 앞바다"
		elseif z < IS.P(x) then
			return "광안리해수욕장"
		elseif z < IS.P(x) + 46 then
			return "광안리 해변 산책로"
		elseif z < IS.P(x) + 110 then
			return "광안해변로"
		end
	end
	if x < -2380 then
		return if z < -200 then "민락항" else "민락동"
	elseif x > 2380 then
		return "남천동"
	end
	return "광안동 골목"
end

---------------------------------------------------------------------------------------------------
-- Street food, vending, fireworks, tips, claw (server-authoritative prices)
---------------------------------------------------------------------------------------------------
-- prop: the hand-held prop the server welds while eating ("cup" | "skewer" | "disc" | "fish" |
-- "can" | "cone" | "box"), eat = seconds of the eating animation.
IS.FOOD = {
	tteok = { name = "떡볶이", icon = "🌶️", price = 3500, stats = { stamina = 8, happiness = 2 }, prop = "cup", color = { 214, 54, 40 }, eat = 4.5, line = "쫄깃쫄깃 매콤달콤!" },
	eomuk = { name = "어묵 꼬치", icon = "🍢", price = 1000, stats = { stamina = 3, happiness = 1 }, prop = "skewer", color = { 226, 196, 140 }, eat = 3.5, line = "국물까지 뜨끈하게 후루룩" },
	hotteok = { name = "씨앗호떡", icon = "🥞", price = 1500, stats = { stamina = 4, happiness = 2 }, prop = "disc", color = { 196, 128, 56 }, eat = 3.5, line = "겉바속촉, 꿀이 주르륵" },
	bungeo = { name = "붕어빵 3개", icon = "🐟", price = 2000, stats = { stamina = 5, happiness = 2 }, prop = "fish", color = { 204, 140, 64 }, eat = 4, line = "팥이 꼬리까지 꽉!" },
	gyeranppang = { name = "계란빵", icon = "🥚", price = 2000, stats = { stamina = 5, happiness = 1 }, prop = "disc", color = { 236, 196, 92 }, eat = 3.5, line = "폭신폭신 계란 한 알" },
	-- existing food trucks (build/districts/coast_life.luau menus)
	dakkochi = { name = "닭꼬치", icon = "🍗", price = 4000, stats = { stamina = 7, happiness = 2 }, prop = "skewer", color = { 170, 70, 30 }, eat = 4, line = "불향 가득 닭꼬치" },
	potato = { name = "회오리감자", icon = "🥔", price = 5000, stats = { stamina = 7, happiness = 3 }, prop = "skewer", color = { 236, 180, 70 }, eat = 4, line = "바삭바삭 회오리!" },
	sotteok = { name = "소떡소떡", icon = "🍡", price = 4500, stats = { stamina = 7, happiness = 2 }, prop = "skewer", color = { 200, 80, 50 }, eat = 4, line = "소시지 떡 소시지 떡" },
	lemonade = { name = "레모네이드", icon = "🍋", price = 4000, stats = { stamina = 3, happiness = 2 }, prop = "can", color = { 250, 230, 90 }, eat = 3, drink = true, line = "상큼하게 쭉!" },
	steak = { name = "큐브스테이크", icon = "🥩", price = 12000, stats = { stamina = 14, happiness = 4 }, prop = "box", color = { 120, 50, 36 }, eat = 5, line = "불맛 제대로!" },
	gangjeong = { name = "닭강정", icon = "🍗", price = 8000, stats = { stamina = 10, happiness = 3 }, prop = "cup", color = { 180, 70, 30 }, eat = 4.5, line = "달콤바삭 닭강정" },
	cola = { name = "콜라", icon = "🥤", price = 2000, stats = { stamina = 2, happiness = 1 }, prop = "can", color = { 200, 30, 30 }, eat = 2.5, drink = true, line = "캬~ 시원하다" },
	churros = { name = "츄러스", icon = "🥖", price = 4000, stats = { stamina = 5, happiness = 3 }, prop = "skewer", color = { 200, 140, 70 }, eat = 4, line = "설탕 솔솔 츄러스" },
	takoyaki = { name = "타코야끼", icon = "🐙", price = 6000, stats = { stamina = 8, happiness = 3 }, prop = "box", color = { 190, 120, 60 }, eat = 4.5, line = "뜨거우니까 호호 불어서" },
	icetea = { name = "아이스티", icon = "🧋", price = 3500, stats = { stamina = 2, happiness = 2 }, prop = "can", color = { 200, 120, 50 }, eat = 3, drink = true, line = "얼음 동동" },
	-- vending machine drinks
	water = { name = "생수", icon = "💧", price = 800, stats = { stamina = 2 }, prop = "can", color = { 120, 190, 255 }, eat = 2.5, drink = true, vend = true, line = "꿀꺽꿀꺽" },
	ion = { name = "이온음료", icon = "🧃", price = 1200, stats = { stamina = 4, happiness = 1 }, prop = "can", color = { 70, 150, 255 }, eat = 2.5, drink = true, vend = true, line = "갈증 해소 완료" },
	coffee = { name = "캔커피", icon = "☕", price = 1000, stats = { stamina = 3, happiness = 1 }, prop = "can", color = { 120, 80, 50 }, eat = 2.5, drink = true, vend = true, line = "달달한 캔커피" },
	soda = { name = "사이다", icon = "🥤", price = 1200, stats = { stamina = 2, happiness = 2 }, prop = "can", color = { 90, 200, 110 }, eat = 2.5, drink = true, vend = true, line = "톡 쏘는 맛" },
	sikhye = { name = "식혜", icon = "🍚", price = 1300, stats = { stamina = 3, happiness = 2 }, prop = "can", color = { 236, 220, 180 }, eat = 2.5, drink = true, vend = true, line = "밥알 동동 식혜" },
}
IS.FOOD_DAILY_STATS = 4 -- per item per in-game day; after that eating is just for fun (no stats)

-- New street-food carts (server builds them on the promenade; x / n = station / inland offset, the
-- server nudges each along x until the footprint is free).
IS.CARTS = {
	{ id = "cart_tteok", name = "떡볶이 · 어묵", items = { "tteok", "eomuk" }, x = -336, n = 33, color = { 214, 54, 40 } },
	{ id = "cart_hotteok", name = "씨앗호떡", items = { "hotteok", "gyeranppang" }, x = -186, n = 33, color = { 196, 128, 56 } },
	{ id = "cart_bungeo", name = "붕어빵", items = { "bungeo", "eomuk" }, x = 64, n = 33, color = { 60, 90, 180 } },
	{ id = "cart_millak", name = "떡볶이 · 어묵", items = { "tteok", "eomuk" }, x = -1980, n = 33, color = { 214, 54, 40 } },
}
-- Existing food trucks (model "푸드트럭 <name>"): menu by the truck's name.
IS.TRUCK_MENUS = {
	["닭꼬치 · 회오리감자"] = { "dakkochi", "potato", "sotteok", "lemonade" },
	["불맛 스테이크 큐브"] = { "steak", "gangjeong", "cola" },
	["츄러스 · 타코야끼"] = { "churros", "takoyaki", "icetea" },
}
IS.TRUCK_DEFAULT = { "dakkochi", "cola" }

IS.VENDING = {
	{ id = "vend_plaza", x = -118, n = 40, items = { "water", "ion", "coffee", "soda" } },
	{ id = "vend_center", x = 330, n = 40, items = { "water", "ion", "coffee", "sikhye" } },
	{ id = "vend_sup", x = 1650, n = 40, items = { "water", "ion", "soda", "sikhye" } },
}

IS.FIREWORKS = {
	price = 5000,
	name = "불꽃놀이 세트",
	maxOwned = 5,
	showSeconds = 10,
	cooldown = 20, -- per player between shows
	maxShows = 3, -- concurrent shows on the server
	nightFrom = 18.5, -- game clock window (wraps midnight)
	nightTo = 5,
	stall = { id = "fireworks_stall", x = -24, n = 36 },
	sparkler = { price = 2000, name = "손불꽃 (스파클러)", seconds = 40 },
}
function IS.isFireworksTime(clock: number): boolean
	local f = IS.FIREWORKS
	return clock >= f.nightFrom or clock < f.nightTo
end

IS.BUSKER = {
	tip = 1000,
	tipCooldown = 25, -- per player per busker
	happinessCooldown = 90,
	-- NPC performers at their own small kits on the promenade (the three existing busking kits are the
	-- player stages of GwangalliDetails: 만남의 광장 무대 / 해맞이광장 / 밀락 버스킹 스퀘어)
	spots = {
		{ id = "busker_west", x = -760, n = 22, song = "파도 위의 고백", look = { body = "m", style = "street" } },
		{ id = "busker_center", x = 210, n = 22, song = "모래 위 발자국", look = { body = "f", style = "artsy" } },
	},
}

IS.CLAW = {
	price = 1000,
	moveSeconds = 12, -- time to aim before the claw drops on its own
	baseChance = 0.12, -- chance with a sloppy aim
	bestChance = 0.55, -- chance dead centre over a plush
	holdSeconds = 90,
	prizes = {
		{ id = "bear", name = "곰돌이 인형", icon = "🧸", color = { 196, 140, 90 } },
		{ id = "bunny", name = "토끼 인형", icon = "🐰", color = { 250, 236, 240 } },
		{ id = "gull", name = "광안리 갈매기 인형", icon = "🕊️", color = { 245, 245, 245 } },
		{ id = "cat", name = "고양이 인형", icon = "🐱", color = { 240, 180, 90 } },
		{ id = "penguin", name = "펭귄 인형", icon = "🐧", color = { 40, 44, 60 } },
		{ id = "duck", name = "오리 인형", icon = "🦆", color = { 255, 214, 60 } },
	},
}

---------------------------------------------------------------------------------------------------
-- Beach: rental stand (balls / frisbees), beach friends, sandcastles, photo frame
---------------------------------------------------------------------------------------------------
IS.RENTAL = {
	stand = { id = "rental_stand", x = -140, n = -26 },
	pool = { "ball", "ball", "frisbee", "frisbee" }, -- max 4 per server
	rentSeconds = 600,
	idleReturn = 40, -- a free ball lying around goes back to the stand after this
	maxSpeed = 95, -- server clamp on throw speed (studs/s)
	catchRadius = 5,
	friends = { -- server-built beach NPCs that catch and throw back
		{ id = "friend_a", x = -112, n = -64, look = { body = "m", style = "sporty" } },
		{ id = "friend_b", x = -176, n = -76, look = { body = "f", style = "tourist" } },
	},
}
IS.SAND = {
	spot = { id = "sandcastle", x = 40, n = -74 },
	pieces = 5,
	maxCastles = 6,
	lifetime = 600,
	radius = 30, -- build within this distance of the spot sign
}
IS.PHOTO_FRAME = { id = "photo_frame", x = 120, n = -34 }

---------------------------------------------------------------------------------------------------
-- Fishing (민락항 방파제): 12 species by time of day
---------------------------------------------------------------------------------------------------
-- windows: game-clock ranges (wrap past 24); w = rarity weight; size cm; price at the median size;
-- diff = 1 (easy, wide zone) .. 3 (hard, narrow zone)
IS.FISH = {
	{ id = "mackerel", name = "고등어", icon = "🐟", w = 10, size = { 24, 40 }, price = 900, diff = 1, windows = { { 5, 12 } } },
	{ id = "jeoneo", name = "전어", icon = "🐟", w = 9, size = { 15, 24 }, price = 700, diff = 1, windows = { { 16, 21 } } },
	{ id = "horse", name = "전갱이", icon = "🐟", w = 9, size = { 16, 30 }, price = 700, diff = 1, windows = { { 19, 29 } } },
	{ id = "halfbeak", name = "학꽁치", icon = "🐠", w = 8, size = { 20, 34 }, price = 600, diff = 1, windows = { { 8, 17 } } },
	{ id = "greenling", name = "노래미", icon = "🐠", w = 9, size = { 18, 36 }, price = 1100, diff = 2, windows = { { 0, 24 } } },
	{ id = "filefish", name = "쥐치", icon = "🐠", w = 6, size = { 15, 26 }, price = 1000, diff = 2, windows = { { 9, 18 } } },
	{ id = "rockfish", name = "우럭", icon = "🐡", w = 6, size = { 20, 42 }, price = 1800, diff = 2, windows = { { 18, 30 } } },
	{ id = "blackrock", name = "볼락", icon = "🐡", w = 6, size = { 15, 28 }, price = 1500, diff = 2, windows = { { 19, 29 } } },
	{ id = "cuttlefish", name = "갑오징어", icon = "🦑", w = 4, size = { 14, 30 }, price = 2400, diff = 2, windows = { { 15, 22 } } },
	{ id = "flounder", name = "광어", icon = "🐟", w = 2.5, size = { 30, 62 }, price = 4200, diff = 3, windows = { { 6, 18 } } },
	{ id = "porgy", name = "감성돔", icon = "🐟", w = 1.6, size = { 25, 50 }, price = 6000, diff = 3, windows = { { 4, 8 }, { 17, 20 } } },
	{ id = "seabream", name = "참돔", icon = "🐟", w = 1, size = { 30, 70 }, price = 8000, diff = 3, windows = { { 5, 10 } } },
}
IS.FISH_BY_ID = {} :: { [string]: any }
for _, f in IS.FISH do
	IS.FISH_BY_ID[f.id] = f
end
IS.FISH_JUNK = { id = "can", name = "빈 캔 (바다 청소!)", icon = "🥫", price = 0 }
IS.FISHING = {
	biteMin = 5, -- seconds after the cast
	biteMax = 13,
	hookWindow = 1.4, -- seconds to tap after the bite (+ latency allowance on the server)
	latency = 0.6,
	cooler = 10, -- fish kept until sold
	junkChance = 0.12,
	sellCap = 25000, -- 원 per sellWindow seconds (the market buys a limited amount)
	sellWindow = 900,
	spotsMax = 8,
	market = { id = "fish_market", near = Vector3.new(-2930, 4, -323) },
	zone = { 0.34, 0.24, 0.16 }, -- green zone width by difficulty (fraction of the bar)
}

function IS.inWindow(clock: number, w: { number }): boolean
	local a, b = w[1], w[2]
	if b <= 24 then
		return clock >= a and clock < b
	end
	return clock >= a or clock < b - 24
end
-- Species available at this game clock with their weights.
function IS.fishPool(clock: number): { any }
	local out = {}
	for _, f in IS.FISH do
		for _, w in f.windows do
			if IS.inWindow(clock, w) then
				table.insert(out, f)
				break
			end
		end
	end
	return out
end
-- Deterministic pick: r01 / r02 in [0,1). Returns species, size (cm), price (원).
function IS.rollFish(clock: number, r01: number, r02: number): (any, number, number)
	local pool = IS.fishPool(clock)
	if #pool == 0 then
		pool = { IS.FISH[1] }
	end
	local total = 0
	for _, f in pool do
		total += f.w
	end
	local t = r01 * total
	local pick = pool[#pool]
	for _, f in pool do
		t -= f.w
		if t <= 0 then
			pick = f
			break
		end
	end
	local s0, s1 = pick.size[1], pick.size[2]
	local size = math.floor((s0 + (s1 - s0) * (r02 ^ 1.6)) * 10 + 0.5) / 10
	local mid = (s0 + s1) / 2
	local price = math.floor(pick.price * math.clamp(size / mid, 0.6, 1.6) / 10 + 0.5) * 10
	return pick, size, price
end

---------------------------------------------------------------------------------------------------
-- Stray animals (client only)
---------------------------------------------------------------------------------------------------
IS.ANIMALS = {
	followSeconds = 22,
	maxNear = 4, -- pooled rigs per client
	nearRadius = 140, -- spawn / keep simulated within this radius of the player
	petCooldown = 90, -- happiness +1 at most this often (server)
	spawns = { -- { x, z, kind } on the ground (y found with one raycast when spawned)
		{ -300, 60, "cat" }, { -150, 70, "cat" }, { 120, 48, "dog" }, { -520, 40, "cat" }, { 420, 40, "cat" },
		{ -2560, -100, "cat" }, { -2620, -140, "cat" }, { -2900, -300, "cat" }, { 2960, 300, "cat" }, { 3000, 280, "dog" },
		{ 2480, -180, "dog" }, { -3650, -500, "cat" }, { -80, 200, "cat" }, { 230, 180, "cat" }, { -330, 420, "cat" },
		{ 900, 60, "dog" }, { -900, 70, "cat" }, { 1700, 20, "dog" }, { -1500, 60, "cat" }, { 60, 560, "cat" },
	},
	coats = {
		cat = { { 240, 170, 80 }, { 60, 56, 54 }, { 236, 232, 226 }, { 140, 110, 90 }, { 200, 196, 190 } },
		dog = { { 236, 220, 190 }, { 196, 140, 80 }, { 250, 250, 246 }, { 120, 84, 60 } },
	},
}

---------------------------------------------------------------------------------------------------
-- Prompt kinds of GwInteract parts (client hub text; the module that handles each kind)
---------------------------------------------------------------------------------------------------
IS.KINDS = {
	food = { action = "사 먹기", icon = "🍢", module = "Street" },
	truck = { action = "주문하기", icon = "🚚", module = "Street" },
	vending = { action = "음료 뽑기", icon = "🥤", module = "Street" },
	busker = { action = "팁 주기 1,000원", icon = "🎸", module = "Street" },
	claw = { action = "인형뽑기 1,000원", icon = "🧸", module = "Claw" },
	fireworks = { action = "불꽃놀이 사기", icon = "🎆", module = "Beach" },
	rental = { action = "공 · 원반 빌리기", icon = "🏐", module = "Beach" },
	ball = { action = "줍기", icon = "🏐", module = "Beach" },
	sandcastle = { action = "모래성 쌓기", icon = "🏰", module = "Beach" },
	fish = { action = "낚시하기", icon = "🎣", module = "Fishing" },
	fishsell = { action = "생선 팔기", icon = "🐟", module = "Fishing" },
	photozone = { action = "포토존 찍기", icon = "📸", module = "Photo" },
	pet = { action = "쓰다듬기", icon = "🐾", module = "Animals" },
}

-- Busy states (Player attribute GwInteractBusy): the hub hides prompts while one is set.
IS.BUSY = { sit = "sit", fish = "fish", claw = "claw", photo = "photo", eat = "eat", build = "build", lean = "lean" }

-- Held props (GwHeld): id -> { kind, size, color, offset (CFrame components in the right hand) }
IS.HELD = {
	cup = { size = { 0.5, 0.55, 0.5 }, shape = "cyl" },
	skewer = { size = { 0.12, 1.4, 0.12 }, shape = "block", top = { 0.34, 0.6, 0.34 } },
	disc = { size = { 0.7, 0.16, 0.7 }, shape = "cyl" },
	fish = { size = { 0.35, 0.3, 0.9 }, shape = "ball" },
	can = { size = { 0.36, 0.6, 0.36 }, shape = "cyl" },
	box = { size = { 0.8, 0.3, 0.6 }, shape = "block" },
	plush = { size = { 0.9, 1.0, 0.8 }, shape = "ball" },
	rod = { size = { 0.1, 0.1, 6.5 }, shape = "block" },
	sparkler = { size = { 0.06, 1.2, 0.06 }, shape = "block" },
	fireworks = { size = { 0.9, 0.7, 0.6 }, shape = "block" },
}

return IS
