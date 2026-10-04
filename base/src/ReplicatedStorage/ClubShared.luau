-- ClubShared: data + pure helpers for CLUB OCEAN 광안 (used by ClubLights.client, ClubDance.client
-- and Club.server). No instances are created here.
--   * contract names (tags, attributes, remote / bindable names), show script, palettes, cues
--   * bottle-service menu + prices, parade timing and the parade path to any table (paradePath)
--   * the player dance animations (Roblox's public R6 / R15 emotes)
--   * the 5x7 LED font (ledText sanitises any string for it) and textColumns
--   * ClubShared.Bus: client-side runtime state shared by the club LocalScripts (ModuleScripts are
--     cached per peer, so ClubLights and ClubDance see the same table); ClubLights writes it

local ClubShared = {}

ClubShared.BPM = 126
ClubShared.BEATS_PER_BAR = 4
ClubShared.SHOW_BARS = 64 -- one show cycle = 64 bars (~122 s at 126 BPM)

-- Tags / attribute names (single source of truth; the builder uses the same strings)
ClubShared.Tags = {
	Venue = "ClubVenue",
	Runtime = "ClubRuntime",
	Zone = "ClubZone",
	Light = "ClubLight",
	FloorTile = "ClubFloorTile",
	Laser = "ClubLaser",
	CO2 = "ClubCO2",
	Confetti = "ClubConfetti",
	Sparkler = "ClubSparkler",
	Haze = "ClubHaze",
	NPC = "ClubNPC",
	FX = "ClubFX", -- ParticleEmitters with attribute Kind (ColdSpark | Flame | LowFog | MirrorGlint | ParadeSparkler)
	MirrorRay = "ClubMirrorRay", -- Beams radiating from the mirror ball
	ShowBeam = "ClubShowBeam", -- other show Beams (pin spots), saved off; attribute Room (Main | HipHop)
	Table = "ClubTable", -- table / booth Models: TableId, TableType, child part "ServePoint"
	IDCheck = "ClubIDCheck", -- ProximityPrompt at the door (wristband)
}
ClubShared.Attr = {
	MusicAssetId = "MusicAssetId",
	ShowEpoch = "ShowEpoch",
	Wristband = "ClubOceanWristband",
	-- NPC rigs (builder contract)
	Anim = "Anim", -- dance | dance2 | idle | sit | drink | cheer | walk | dj | bartend | guard | serve
	AnimSpeed = "AnimSpeed",
	AnimOffset = "AnimOffset", -- optional 0..1 start phase (else a hash of the rig's position)
	Zone = "Zone", -- ClubRuntime zone the NPC stands in ("Main" or "Zone_Main")
	Role = "Role", -- guest | staff | dj | bartender | md | guard
	-- tables (builder contract)
	TableId = "TableId", -- G1..G4, T1..T10, B1..B8, D1..D3, S1..S6
	TableType = "TableType", -- VIP | Booth | Standing | Bar | DJ
	-- bottle service (set by Club.server on the table Model, read by every client)
	BottleAt = "BottleAt", -- server time the last order's bottles land on this table (future: parade)
	BottleBy = "BottleBy", -- UserId of the player who ordered
	-- bottle-service parade (ClubRuntime model = schedule, ParadeRoute folder = route)
	TargetTable = "TargetTable", -- on ClubRuntime/ParadeRoute: the VIP table the route ends at
	ParadeAt = "ParadeAt", -- on ClubRuntime (server): server time the current parade started
	ParadeTable = "ParadeTable", -- on ClubRuntime (server): TableId the current parade walks to
	ParadePath = "ParadePath", -- on ClubRuntime (server): encodePath of the walk (route start -> table)
	-- LED wall banner (Club.server on ClubRuntime; every client inside draws it on the LED wall)
	WallMsg = "WallMsg", -- text (ledText: A-Z 0-9 and a little punctuation)
	WallMsgAt = "WallMsgAt", -- server time the banner starts
	WallMsgFor = "WallMsgFor", -- seconds it stays
	WallMsgKind = "WallMsgKind", -- birthday | vip | welcome
	WallMsgSerial = "WallMsgSerial", -- increments on every new banner
	-- music system (ClubMusic.server writes it on ClubRuntime): "ClubMusic" = it owns the music, so
	-- ClubLights never plays its legacy MusicAssetId sound
	MusicOwner = "MusicOwner",
	-- player attributes
	Order = "ClubOrder", -- "<status>|<TableId>|<server time x10>" (Club.server -> the ordering player)
	VIPTable = "ClubVIPTable", -- set true by the life-game when the player paid the MD's VIP table
	GuestList = "ClubGuestList", -- life-game: false = no free entry (pay the cover to the MD first)
	ClubVIP = "ClubVIP", -- life-game: Appearance high enough for VIP treatment
}
ClubShared.Names = {
	ParadeRoute = "ParadeRoute", -- Folder under the ClubRuntime model; parts WP1..WPn
	ServePoint = "ServePoint", -- part inside each ClubTable model
	OrderPrompt = "ClubOrderPrompt",
	SitPrompt = "ClubSitPrompt",
	Remote = "ClubRemote", -- RemoteEvent under ReplicatedStorage (created by Club.server)
	GameplayEvent = "ClubGameplayEvent", -- BindableEvent under ServerStorage (created by Club.server;
	-- the life-game server may :Fire("vipTable" | "birthday" | "entry", player))
	GameplayAPI = "GwangalliGameplayAPI", -- optional BindableFunction under ServerStorage (life-game):
	-- :Invoke("spend", player, amount, label) -> boolean ; :Invoke("addStats", player, delta, label)
}

-- Bottle-service menu (prices in won, like the life-game's G.CLUB.vipTable = 300,000). `parade` items
-- send the staff line with sparklers and put `msg` (with the player's name) on the LED wall.
ClubShared.Menu = {
	{ id = "champagne", label = "샴페인 1병", desc = "바로 테이블로 서빙돼요", icon = "🍾", price = 150000, parade = false },
	{ id = "vip", label = "VIP 보틀 퍼레이드", desc = "스파클러 퍼레이드 + LED 월에 VIP 이름", icon = "👑", price = 300000, parade = true, msg = "VIP %s", kind = "vip" },
	{ id = "birthday", label = "생일 축하 보틀", desc = "퍼레이드 + LED 월에 HAPPY BIRTHDAY", icon = "🎂", price = 250000, parade = true, msg = "HAPPY BIRTHDAY %s *", kind = "birthday" },
}
function ClubShared.menuItem(id: any): { [string]: any }?
	if type(id) ~= "string" then
		return nil
	end
	for _, item in ClubShared.Menu do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Player dances (ClubDance.client): Roblox's own public emote animations from the default Animate
-- scripts (playable in any experience); the R6 ids are the ones the NPC crowd dances with.
ClubShared.PlayerDances = {
	{ id = "dance1", label = "댄스 1", icon = "💃", r6 = "rbxassetid://182435998", r15 = "rbxassetid://507771019" },
	{ id = "dance2", label = "댄스 2", icon = "🕺", r6 = "rbxassetid://182491037", r15 = "rbxassetid://507776043" },
	{ id = "dance3", label = "댄스 3", icon = "🪩", r6 = "rbxassetid://182491065", r15 = "rbxassetid://507777268" },
}
ClubShared.PlayerCheer = { r6 = "rbxassetid://129423030", r15 = "rbxassetid://507770677" } -- hands up

-- Client runtime bus (see the header). Plain values only; os.clock() times.
ClubShared.Bus = {
	state = "Idle", -- Idle | Near | Inside (ClubLights zone state)
	zone = "", -- ClubZone name the player is in
	showRoom = false, -- in a room that sees the show (Main / Lobby / Corridor / HipHop)
	section = "intro", -- intro | build | drop | breakdown | groove
	live = false, -- the show follows real music (ClubMusicShared beats) instead of the clock
	bpm = 126,
	energy = 0.3,
	beatAt = 0, -- last beat (os.clock)
	beatSerial = 0,
	dropAt = -1e9, -- last drop moment (os.clock)
	dropSerial = 0,
	countdown = 0, -- LED-wall countdown digit on screen (0 = none)
	photoAt = -1e9, -- ClubDance: the local player asked for a photo moment (os.clock)
	playerDanceAt = -1e9, -- ClubDance: the local player started a dance (os.clock)
	night = false,
}

-- Roblox's own public R6 animations (owned by Roblox, playable in any experience; the same ids the
-- default R6 Animate script uses)
ClubShared.Animations = {
	Dance = {
		"rbxassetid://182435998", -- dance
		"rbxassetid://182491037", -- dance2
		"rbxassetid://182491065", -- dance3
	},
	Idle = "rbxassetid://180435571",
	Walk = "rbxassetid://180426354",
	Sit = "rbxassetid://178130996",
	Cheer = "rbxassetid://129423030",
}

-- Anim attribute -> animation id + speed. `pose` is the rig's Pose attribute: the builder bends a
-- posed rig with its Motor6D C0s, so a posed sitter gets the subtle idle on top of its seated pose
-- (the R6 sit animation would bend the legs twice). `seed` in [0, 1) picks between variants.
-- Returns nil for rigs without an animation (legacy AnimIndex -1 / Anim "none").
local IDLE_SPEED = { idle = 1, drink = 0.8, bartend = 1.25, guard = 0.6, serve = 1, staff = 1 }
function ClubShared.animFor(anim: any, animIndex: any, pose: any, seed: number): (string?, number)
	local A = ClubShared.Animations
	local posed = type(pose) == "string" and pose ~= ""
	if type(anim) == "string" and anim ~= "" then
		local a = string.lower(anim)
		if a == "dance" then
			return (if seed < 0.5 then A.Dance[1] else A.Dance[3]), 1
		elseif a == "dance2" then
			return A.Dance[2], 1
		elseif a == "cheer" then
			return A.Cheer, 1
		elseif a == "walk" then
			return A.Walk, 1
		elseif a == "sit" then
			local p = if posed then string.lower(pose) else ""
			if string.find(p, "sit", 1, true) or string.find(p, "perch", 1, true) then
				return A.Idle, 0.6
			end
			return A.Sit, 1
		elseif a == "dj" then
			if posed then
				return A.Idle, 1.5 -- at the decks (posed hands): head-nodding idle
			end
			return A.Dance[2], 0.8
		elseif a == "none" then
			return nil, 1
		elseif IDLE_SPEED[a] then
			return A.Idle, IDLE_SPEED[a]
		end
		return A.Idle, 1
	end
	-- legacy rigs: AnimIndex 1..3 = dance, 0 = idle, -1 = none (procedural)
	if type(animIndex) == "number" and animIndex == animIndex then
		if animIndex < 0 then
			return nil, 1
		end
		local i = math.floor(animIndex)
		if i >= 1 and i <= #A.Dance then
			return A.Dance[i], 1
		end
	end
	return A.Idle, 1
end

-- "Zone_Main" / "Main" -> "Main"
function ClubShared.zoneKey(name: any): string?
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return (string.gsub(name, "^Zone_", ""))
end

-- Bottle-service parade timing (server schedule + client walk)
ClubShared.Parade = {
	Period = 150, -- a parade every 150 s (server), unless a player ordered one recently
	FirstDelay = 25, -- first parade this long after the server starts
	Speed = 4.2, -- walking speed (studs / s)
	Gap = 3.4, -- spacing between the staff in the line (studs)
	Hold = 22, -- seconds at the table with the sparklers burning
	Spread = 2.6, -- sideways spacing of the staff lined up in front of the table
	Busy = 85, -- seconds after a start during which the server starts no other parade
	RetargetRadius = 36, -- an ordered table this close to the route end gets the parade
}

-- Parade state for a staff member `tt` seconds after its own start along a path `total` long.
-- Returns distance along the path, walking, forward, sparklers on, phase name.
function ClubShared.paradeAt(tt: number, total: number, speed: number, hold: number): (number, boolean, boolean, boolean, string)
	if tt < 0 or total <= 0 then
		return 0, false, true, false, "wait"
	end
	local walkT = total / math.max(0.1, speed)
	if tt < walkT then
		return tt * speed, true, true, true, "out"
	elseif tt < walkT + hold then
		return total, false, true, true, "hold"
	elseif tt < walkT * 2 + hold then
		return math.max(0, total - (tt - walkT - hold) * speed), true, false, false, "back"
	end
	return 0, false, false, false, "done"
end

-- Path of a bottle-service parade to any table: along the ParadeRoute (world points WP1..n, last leg
-- extended by `ext` studs, e.g. along the VIP rope) to a branch point, then straight to `dest` (the
-- table's ServePoint). Branch points are sampled every 4 studs along the route; the best one scores
-- leg length + 0.08 x walk along the route, and when `clear(a, b)` is given (server: a spherecast
-- against the furniture) the best one whose straight leg is clear wins. nil when the table is more
-- than `maxLeg` studs from the route (the parade then walks to the route's own table).
-- Pure (flat distances; heights from the route). Returns the points (the last one is dest at the
-- route's height), the flat length and whether the leg was found clear (true without `clear`).
function ClubShared.paradePath(route: { Vector3 }, dest: Vector3, maxLeg: number, ext: number, clear: ((Vector3, Vector3) -> boolean)?): ({ Vector3 }?, number, boolean)
	local n = #route
	if n < 2 then
		return nil, 0, false
	end
	local pts = table.clone(route)
	if ext > 0 then
		local a, b = pts[n - 1], pts[n]
		local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		if d.Magnitude > 1e-3 then
			pts[n + 1] = b + d.Unit * ext
		end
	end
	local cands: { { number } } = {} -- { score, segment, t, leg }
	local run = 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local segLen = ab.Magnitude
		local function add(t: number)
			local p = a:Lerp(b, t)
			local leg = Vector3.new(dest.X - p.X, 0, dest.Z - p.Z).Magnitude
			if leg <= maxLeg then
				table.insert(cands, { leg + 0.08 * (run + segLen * t), i, t, leg })
			end
		end
		if segLen > 1e-3 then
			local ap = Vector3.new(dest.X - a.X, 0, dest.Z - a.Z)
			add(math.clamp(ap:Dot(ab) / (segLen * segLen), 0, 1))
			local steps = math.floor(segLen / 4)
			for k = 1, steps do
				add(k / (steps + 1))
			end
		end
		if i == #pts - 1 then
			add(1)
		end
		run += segLen
	end
	if #cands == 0 then
		return nil, 0, false
	end
	table.sort(cands, function(x, y)
		return x[1] < y[1]
	end)
	local pick = cands[1]
	local ok = clear == nil
	if clear then
		for k = 1, math.min(#cands, 40) do
			local c = cands[k]
			local p = pts[c[2]]:Lerp(pts[c[2] + 1], c[3])
			local okC, res = pcall(clear, p, Vector3.new(dest.X, p.Y, dest.Z))
			if okC and res == true then
				pick, ok = c, true
				break
			end
		end
	end
	local bestI = pick[2]
	local bestP = pts[bestI]:Lerp(pts[bestI + 1], pick[3])
	local out: { Vector3 } = {}
	for i = 1, bestI do
		out[i] = pts[i]
	end
	local last = out[#out]
	if Vector3.new(bestP.X - last.X, 0, bestP.Z - last.Z).Magnitude > 0.3 then
		table.insert(out, bestP)
	end
	table.insert(out, Vector3.new(dest.X, bestP.Y, dest.Z))
	return out, ClubShared.pathLength(out), ok
end

function ClubShared.pathLength(pts: { Vector3 }): number
	local len = 0
	for i = 2, #pts do
		len += Vector3.new(pts[i].X - pts[i - 1].X, 0, pts[i].Z - pts[i - 1].Z).Magnitude
	end
	return len
end

-- "x,z;x,z;..." (the server publishes the parade's path on ClubRuntime; heights come from the floor)
function ClubShared.encodePath(pts: { Vector3 }): string
	local parts = {}
	for _, p in pts do
		table.insert(parts, string.format("%.1f,%.1f", p.X, p.Z))
	end
	return table.concat(parts, ";")
end
function ClubShared.decodePath(s: any, y: number): { Vector3 }?
	if type(s) ~= "string" or s == "" or #s > 2000 then
		return nil
	end
	local out: { Vector3 } = {}
	for xs, zs in string.gmatch(s, "(-?[%d%.]+),(-?[%d%.]+)") do
		local x, z = tonumber(xs), tonumber(zs)
		if not x or not z or x ~= x or z ~= z then
			return nil
		end
		table.insert(out, Vector3.new(x, y, z))
		if #out > 64 then
			return nil
		end
	end
	return if #out >= 2 then out else nil
end
ClubShared.PARADE_MAX_LEG = 60 -- studs from the route to a table the parade still walks to
ClubShared.PARADE_EXTEND = 48 -- the route's last leg continued this far (VIP rope -> G1 / left aisle)

-- Client fallback when the server publishes no ParadeAt: the same fixed schedule on every client.
function ClubShared.paradeFallbackStart(now: number, epoch: number): number
	local P = ClubShared.Parade
	local k = math.floor((now - epoch - P.FirstDelay) / P.Period)
	return epoch + P.FirstDelay + math.max(0, k) * P.Period
end

-- Table interaction (server rate limits + client visuals)
ClubShared.TableCfg = {
	PromptCooldown = 1.2, -- per player, any table prompt
	OrderCooldownPlayer = 20, -- per player between orders
	OrderCooldownTable = 25, -- per table: minimum between orders (and no order while bottles are out)
	BottleSeconds = 26, -- how long the sparkler bottles stay on the table (from BottleAt)
	MaxDistance = 16, -- server check: character within this of the ServePoint
	VisualRadius = 90, -- clients further than this from the table skip the bottle visuals
}
ClubShared.TableTypeLabel = {
	VIP = "VIP 부스",
	Booth = "부스",
	Standing = "스탠딩 테이블",
	Bar = "바 테이블",
	DJ = "DJ 테이블",
}

-- Show script: sections by bar (0-based, inclusive start, exclusive end).
-- energy 0..1 drives speeds and brightness; palette picks the colour set.
ClubShared.Sections = {
	{ name = "intro", from = 0, to = 16, energy = 0.25, palette = 1 },
	{ name = "build", from = 16, to = 24, energy = 0.6, palette = 2 },
	{ name = "drop", from = 24, to = 40, energy = 1.0, palette = 3 },
	{ name = "breakdown", from = 40, to = 48, energy = 0.35, palette = 4 },
	{ name = "build", from = 48, to = 56, energy = 0.65, palette = 2 },
	{ name = "drop", from = 56, to = 64, energy = 1.0, palette = 5 },
}

-- One-shot cues (bar numbers within the show)
ClubShared.Cues = {
	CO2 = { [24] = true, [32] = true, [56] = true, [60] = true },
	Confetti = { [24] = true, [56] = true },
	SparklerFrom = 40,
	SparklerTo = 48,
	-- cold-spark fountains: bar -> number of bars they burn
	ColdSpark = { [24] = 2, [32] = 1, [39] = 1, [56] = 2, [63] = 1 },
	-- flame jets fire short bursts on beats 1 and 3 of these bars
	Flame = { [24] = true, [25] = true, [26] = true, [27] = true, [36] = true, [37] = true, [56] = true, [57] = true, [58] = true, [59] = true },
	-- low fog rolls over the floor in these bar ranges (inclusive start, exclusive end)
	LowFog = { { 0, 6 }, { 40, 48 } },
	-- mirror-ball rays / glints (the "slow" moments)
	MirrorBall = { { 0, 16 }, { 40, 48 } },
}

function ClubShared.inRanges(bar: number, ranges: { { number } }): boolean
	for _, r in ranges do
		if bar >= r[1] and bar < r[2] then
			return true
		end
	end
	return false
end

ClubShared.Palettes = {
	-- { a, b, accent }
	{ Color3.fromRGB(20, 40, 170), Color3.fromRGB(110, 30, 200), Color3.fromRGB(40, 220, 255) }, -- intro: deep blue / purple
	{ Color3.fromRGB(40, 220, 255), Color3.fromRGB(230, 240, 255), Color3.fromRGB(150, 60, 255) }, -- build: cyan -> white
	{ Color3.fromRGB(255, 40, 170), Color3.fromRGB(40, 220, 255), Color3.fromRGB(255, 255, 255) }, -- drop A: magenta / cyan
	{ Color3.fromRGB(255, 150, 50), Color3.fromRGB(30, 40, 150), Color3.fromRGB(255, 220, 160) }, -- breakdown: amber / blue
	{ Color3.fromRGB(150, 50, 255), Color3.fromRGB(255, 190, 40), Color3.fromRGB(255, 255, 255) }, -- drop B: purple / gold
}

local BLACK = Color3.new(0, 0, 0)
ClubShared.Black = BLACK

-- Beat clock synchronised to the server: returns
-- { beat (float, total), showBeat, bar (0..63), beatInBar (0..3 float), frac (0..1), section,
--   barInSection, sectionBars }
-- `out` (optional) is filled and returned instead of a new table (no per-frame garbage on phones).
function ClubShared.clock(serverTime: number, epoch: number?, bpm: number?, out: { [string]: any }?)
	local b = bpm or ClubShared.BPM
	local t = serverTime - (epoch or 0)
	local beat = t * b / 60
	local total = ClubShared.SHOW_BARS * ClubShared.BEATS_PER_BAR
	local showBeat = beat % total
	local bar = math.floor(showBeat / ClubShared.BEATS_PER_BAR)
	local section = ClubShared.Sections[1]
	for _, s in ClubShared.Sections do
		if bar >= s.from and bar < s.to then
			section = s
			break
		end
	end
	local r = out or {}
	r.beat = beat
	r.showBeat = showBeat
	r.bar = bar
	r.beatInBar = showBeat % ClubShared.BEATS_PER_BAR
	r.frac = beat % 1
	r.section = section
	r.barInSection = bar - section.from
	r.sectionBars = section.to - section.from
	return r
end

-- Deterministic hash -> [0, 1)
function ClubShared.hash(a: number, b: number?): number
	local x = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- 5x7 pixel font for the LED wall (columns rendered left -> right, rows top -> bottom)
ClubShared.Glyphs = {
	A = { " ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #" },
	B = { "#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### " },
	C = { " ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### " },
	D = { "#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### " },
	E = { "#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####" },
	G = { " ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####" },
	H = { "#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #" },
	I = { " ### ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### " },
	J = { "  ###", "   # ", "   # ", "   # ", "#  # ", "#  # ", " ##  " },
	L = { "#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####" },
	M = { "#   #", "## ##", "# # #", "#   #", "#   #", "#   #", "#   #" },
	N = { "#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #" },
	O = { " ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### " },
	P = { "#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    " },
	R = { "#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #" },
	S = { " ####", "#    ", "#    ", " ### ", "    #", "    #", "#### " },
	T = { "#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  " },
	U = { "#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### " },
	W = { "#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #" },
	Y = { "#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  " },
	["0"] = { " ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### " },
	["1"] = { "  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### " },
	["2"] = { " ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####" },
	["5"] = { "#####", "#    ", "#### ", "    #", "    #", "#   #", " ### " },
	["6"] = { " ### ", "#    ", "#    ", "#### ", "#   #", "#   #", " ### " },
	F = { "#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    " },
	K = { "#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #" },
	Q = { " ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #" },
	V = { "#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  " },
	X = { "#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #" },
	Z = { "#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####" },
	["3"] = { "#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### " },
	["4"] = { "   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # " },
	["7"] = { "#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   " },
	["8"] = { " ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### " },
	["9"] = { " ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  " },
	["-"] = { "     ", "     ", "     ", " ### ", "     ", "     ", "     " },
	["'"] = { "  #  ", "  #  ", " #   ", "     ", "     ", "     ", "     " },
	["&"] = { " ##  ", "#  # ", "# #  ", " #   ", "# # #", "#  # ", " ## #" },
	[":"] = { "     ", "  #  ", "  #  ", "     ", "  #  ", "  #  ", "     " },
	["/"] = { "    #", "    #", "   # ", "  #  ", " #   ", "#    ", "#    " },
	["?"] = { " ### ", "#   #", "    #", "   # ", "  #  ", "     ", "  #  " },
	["("] = { "   # ", "  #  ", " #   ", " #   ", " #   ", "  #  ", "   # " },
	[")"] = { " #   ", "  #  ", "   # ", "   # ", "   # ", "  #  ", " #   " },
	["#"] = { " # # ", " # # ", "#####", " # # ", "#####", " # # ", " # # " },
	["+"] = { "     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     " },
	[","] = { "     ", "     ", "     ", "     ", "     ", "  #  ", " #   " },
	["_"] = { "     ", "     ", "     ", "     ", "     ", "     ", "#####" },
	["*"] = { "     ", " # # ", "#####", "#####", " ### ", "  #  ", "     " }, -- heart
	["~"] = { "  ## ", "  # #", "  #  ", "  #  ", " ##  ", "###  ", " #   " }, -- music note
	[" "] = { "     ", "     ", "     ", "     ", "     ", "     ", "     " },
	["."] = { "     ", "     ", "     ", "     ", "     ", "     ", "  #  " },
	["!"] = { "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "     ", "  #  " },
}

-- Any string -> what the LED font can draw: upper case, glyphs it has, runs of anything else (Hangul,
-- emoji, symbols) collapsed to one space, trimmed, at most `maxLen` characters (default 48).
function ClubShared.ledText(text: any, maxLen: number?): string
	if type(text) ~= "string" then
		return ""
	end
	local out = {}
	local lastSpace = true
	local ok = pcall(function()
		for _, cp in utf8.codes(text) do
			local ch = if cp < 128 then string.upper(string.char(cp)) else nil
			if ch and ch ~= " " and ClubShared.Glyphs[ch] then
				table.insert(out, ch)
				lastSpace = false
			elseif not lastSpace then
				table.insert(out, " ")
				lastSpace = true
			end
		end
	end)
	if not ok then
		return "" -- invalid UTF-8
	end
	local s = string.match(table.concat(out), "^%s*(.-)%s*$") or ""
	local limit = maxLen or 48
	if #s > limit then
		s = string.match(string.sub(s, 1, limit), "^(.-)%s*$") or ""
	end
	return s
end

-- Renders text into an array of columns; each column is a table of 7 booleans (top -> bottom).
-- One blank column between glyphs. Characters the font lacks render as spaces (use ledText first).
function ClubShared.textColumns(text: string): { { boolean } }
	local cols = {}
	for i = 1, #text do
		local ch = string.upper(string.sub(text, i, i))
		local g = ClubShared.Glyphs[ch] or ClubShared.Glyphs[" "]
		for c = 1, 5 do
			local col = {}
			for r = 1, 7 do
				col[r] = string.sub(g[r], c, c) == "#"
			end
			table.insert(cols, col)
		end
		table.insert(cols, { false, false, false, false, false, false, false })
	end
	return cols
end

-- Normalises the MusicAssetId attribute (number, "123", "rbxassetid://123") -> SoundId or nil
function ClubShared.soundIdFrom(value: any): string?
	if type(value) == "number" then
		if value > 0 and value == math.floor(value) then
			return "rbxassetid://" .. string.format("%d", value)
		end
		return nil
	end
	if type(value) ~= "string" then
		return nil
	end
	local s = string.match(value, "^%s*(.-)%s*$") or ""
	if s == "" then
		return nil
	end
	if string.match(s, "^%d+$") then
		return "rbxassetid://" .. s
	end
	if string.match(s, "^rbxassetid://%d+$") or string.match(s, "^rbxasset://") or string.match(s, "^https?://") then
		return s
	end
	return nil
end

return ClubShared
