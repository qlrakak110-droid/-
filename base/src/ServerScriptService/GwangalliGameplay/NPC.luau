-- GwangalliGameplay/NPC: the key NPCs of 광안리 GTA and their dialogs (server; owner: npc_key).
--   * WHO: G.NPCS (employers, realtor, banker, club MD, friends 민지 / 준호) plus the street key NPCs of
--     the roster (GwangalliCitizens.KEY_IDS that are not G.NPCS: 붕어빵 아저씨, 버스커 하루, 관광객 지수,
--     안전요원 도윤, 홍보 레이 / 나나 (18-02 h), 가드 철민 (19-04 h)). Each is a block-R15 person built
--     from the roster look (GwangalliNPCLooks; GwangalliAnim.buildR15 as a fallback) at a post next to
--     a Destination part, with a name tag and a ProximityPrompt.
--   * LIFE: a routine per NPC (ROUTINES below): work acts at a few spots near the post (the barista
--     wipes tables, the realtor paces on a phone call, the lifeguards patrol and whistle, the promoters
--     wander the plaza / promenade at night with flyers and walk up to people, the MD and the guard
--     work the club door, 민지 and 준호 chat, the busker plays and bows, the 붕어빵 man flips fish
--     bread at his cart ...). They notice players (turn, wave / bow, follow them with the head), stop
--     walking for them, face the speaker during a dialog with talk / listen gestures and react to the
--     outcome (cheer, clap, nod, shrug, laugh, shake ...).
--   * DAILY LIFE (SCHEDULE / POSTS below, in-game clock): 민지 and 준호 walk from 만남의 광장 to CLUB
--     OCEAN in the evening (along GwangalliNav, waiting for the walk light), hang out in front of the
--     club, go in and dance by the bar at night and go home late; the lifeguards patrol by day only
--     (the chief does night paperwork at the tower); the busker, the photo tourist, the 붕어빵 man and
--     the club crew keep their hours. A move is walked when a player is around (from / to a nav node
--     out of sight when appearing / leaving) and skipped (placed at once) when nobody is near either
--     end. A friend with a pending meet (Life "meet", the 치맥 offer) stays at the plaza.
--   * NETWORK / COST: the server is only the brain (4 Hz tick, nothing per frame). Rigs are anchored
--     at the HumanoidRootPart; the server writes model attributes and the root CFrame once per arrival.
--     Every client (StarterPlayerScripts.GwangalliNPCClient) interpolates the walk, plays the
--     GwangalliAnim tracks / poses / gestures and turns heads locally, with distance LOD.
--     Model attributes (the contract with GwangalliNPCClient):
--       NpcId, NpcKind ("key" | "street"), NpcAct (GwangalliAnim.ACTS name),
--       NpcLeg "x0,y0,z0,x1,y1,z1,t0,dur" (feet positions; t0 = workspace:GetServerTimeNow() at the
--         start, dur seconds; after t0 + dur the NPC stands at x1,y1,z1), or a polyline walk
--         "P;t0;speed;x,y,z;x,y,z;..." (feet points, constant speed in studs / s along the 3D segments),
--       NpcPost ("home" | "off" | a POSTS key: where the schedule has the NPC now),
--       NpcYaw (degrees; facing when standing = CFrame.Angles(0, math.rad(yaw), 0)),
--       NpcLook (UserId of the player it looks at, 0 = none), NpcTalk (UserId in a dialog, 0),
--       NpcEmote "name#seq#serverTime" (one-shot GwangalliAnim emote), NpcGround (root height above
--       the feet). Prop parts carry attribute Prop = "phone" | "clipboard" | "cup" | "rag" (shown
--       while the act's prop matches).
--   * DIALOGS are built here (Dialog remote: {npcId, name, role, portraitColor, text, choices =
--     {{id, label}}, remote?, emote?}); every "dialogChoice" is validated against the choices that
--     were offered and the distance to the NPC (unless it is a phone call and the choice is
--     phone-safe). Relationships (ctx.social): memory-aware greeting prefix, "💕 친해지기" in the root
--     menu, "soc:" choices forwarded to it. The street key NPCs' dialogs are Relationships' own
--     (prompt -> ctx.social.openDialog). Phone calls to an NPC contact open the same dialog, remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPC = {}

local G: any
local Util: any
local Profiles: any
local ctx: any

local Anim: any = nil
local Looks: any = nil
local Citizens: any = nil
local Nav: any = nil
local navTried = false

type Dlg = { npcId: string, choices: { [string]: boolean }, remote: boolean, openedAt: number }
local dialogs: { [Player]: Dlg } = {}
local folder: Folder? = nil

local PHONE_SAFE: { [string]: boolean } = {
	hire = true, info = true, status = true, quit = true, start = true, endshift = true,
	list_rent = true, list_buy = true, myhome = true, back = true, bye = true, history = true,
	deposit_all = true, withdraw_50k = true, withdraw_200k = true, chat = true,
}

local TICK = 0.25
local NOTICE_R = 12 -- head follows a player within this
local GREET_R = 9.5 -- turn + wave / bow when a player comes this close
local STAY_R = 7 -- no new walks while a player is this close (so they can talk)
local GREET_AGAIN = 90 -- seconds before the same player is greeted again
local TALK_REACH = 18 -- a dialog partner farther than this ends the engagement
local WALK_SPEED = 5.2

-------------------------------------------------------------------------------------------------
-- Routines. Placement in the post's Destination frame: at = { dx right, dz forward } (default: the
-- G.NPCS offset), yaw = facing relative to the Destination's facing (default: toward the Destination
-- part). spots = { { x right, z forward, act, yaw = relative to home, w = {min, max} s, emote } }
-- relative to the home spot (spot 1 is the home spot itself). order: "random" (home <-> a random
-- spot), "cycle" (1, 2, 3 ...), "pace" (1, 2, 1, 3 ...). nav = wander nav nodes within nav studs
-- instead of fixed spots. greet: emote on approach. keepAct: keeps working while noticed (busker).
-- idle: emotes now and then while standing. call: emote at passers-by (12..26 studs).
-- approach: walks up to players (promoters); pointTo: after the flyer they point the way to that
-- Destination (the club). faceTo: a friend; both at their home spots face each other and take turns
-- talking (chat / listen). night = { home = act } overrides after dark.
-------------------------------------------------------------------------------------------------
local ROUTINES: { [string]: any } = {
	gs25_owner = { greet = "wave", call = "beckon", spots = {
		{ 0, 0, "teller", w = { 6, 12 } },
		{ 3.5, -0.5, "wipe", yaw = -90, w = { 6, 10 } },
		{ -3, 0.5, "arms_crossed", yaw = 25 },
		{ 0.5, -2.5, "phone", yaw = 180 },
	} },
	starbucks_mgr = { greet = "wave", spots = {
		{ 0, 0, "wipe", w = { 7, 12 } },
		{ 2.8, 0.2, "cup", yaw = -30 },
		{ -2.8, 0.4, "wipe", yaw = 40 },
		{ 0, -2, "clipboard", yaw = 180 },
	} },
	rider_mgr = { greet = "wave", order = "pace", spots = {
		{ 0, 0, "phone", w = { 5, 9 } },
		{ 4, 1, "call", yaw = -80 },
		{ -3.5, 0.5, "clipboard", yaw = 70 },
	} },
	hoe_boss = { greet = "wave", call = "beckon", idle = { "nod" }, spots = {
		{ 0, 0, "hips", w = { 6, 12 } },
		{ 3, -1, "chop", yaw = -60, w = { 7, 11 } },
		{ -3, 0, "arms_crossed", yaw = 30 },
		{ 0, 2.5, "look" },
	} },
	lifeguard_chief = { greet = "wave", order = "pace", speed = 4.6, spots = {
		{ 0, 0, "lookout", w = { 6, 10 } },
		{ 9, 0, "whistle", yaw = -90 },
		{ -9, 0, "lookout", yaw = 90 },
		{ 0, 4, "behind" },
	} },
	taxi_dispatcher = { greet = "wave", call = "beckon", spots = {
		{ 0, 0, "clipboard", w = { 6, 11 } },
		{ 3, 1, "call", yaw = -60 },
		{ -3, 0, "look", yaw = 50 },
		{ 0, 2.5, "clipboard" },
	} },
	realtor = { greet = "wave", order = "pace", speed = 4.4, spots = {
		{ 0, 0, "clipboard", w = { 5, 8 } },
		{ -3.5, 0, "call", yaw = 90, w = { 3, 6 } },
		{ 3.5, 0, "call", yaw = -90, w = { 3, 6 } },
	} },
	banker = { greet = "bow", speed = 3.6, spots = {
		{ 0, 0, "teller", w = { 7, 13 } },
		{ 2, 0, "typing", yaw = -20 },
		{ -2, 0, "teller", yaw = 20 },
		{ 0, -1.5, "clipboard", yaw = 180 },
	} },
	club_md = { greet = "wave", home = "phone", night = { home = "clipboard" }, spots = {
		{ 0, 0, "clipboard", w = { 6, 12 } },
		{ 2.5, 0, "guard", yaw = -30 },
		{ -2.5, 0.5, "call", yaw = 40 },
		{ 0, 2, "look" },
	} },
	minji = { greet = "wave", faceTo = "junho", idle = { "laugh", "nod" }, nightIdle = { "laugh", "point", "dance1" }, pointTo = "CLUB OCEAN 광안", spots = {
		{ 0, 0, "chat", w = { 8, 14 } },
		{ 1.6, 2, "phone", yaw = 40 },
		{ 2.4, -0.6, "photo", yaw = -60 },
		{ -1.2, 2.2, "look" },
	} },
	junho = { greet = "wave", faceTo = "minji", idle = { "laugh", "shrug" }, nightIdle = { "laugh", "point", "cheer" }, pointTo = "CLUB OCEAN 광안", spots = {
		{ 0, 0, "listen", w = { 8, 14 } },
		{ -1.5, 2, "stretch" },
		{ 1, 2.5, "pockets", yaw = -30 },
		{ -2, -1, "phone", yaw = 150 },
	} },
	bungeoppang = { at = { 12.4, -6 }, yaw = 90, greet = "wave", call = "beckon", stall = true, speed = 2.5, spots = {
		{ 0, 0, "flip", w = { 10, 18 } },
		{ 1.1, 0, "flip", w = { 6, 10 } },
		{ -1.2, -0.6, "idle", yaw = 25 },
	} },
	busker = { at = { -10, -56 }, yaw = 180, greet = "nod", keepAct = true, amp = true, speed = 2.5, spots = {
		{ 0, 0, "guitar", w = { 26, 40 } },
		{ 0.8, 0.3, "idle", w = { 4, 6 }, emote = "bow" },
		{ -2.4, 1.4, "phone", yaw = 35, w = { 5, 8 } }, -- between sets: checks the phone
	} },
	photo_tourist = { at = { -25, -30 }, yaw = 0, greet = "wave", speed = 4.6, idle = { "point" }, spots = {
		{ 0, 0, "photo", w = { 6, 10 } },
		{ 6, 1, "photo", yaw = 20, emote = "point" },
		{ -5, 2, "phone", yaw = -20 },
		{ 1, 5, "photo", yaw = -10 },
	} },
	beach_guard = { at = { 20, 45 }, yaw = 0, greet = "wave", order = "pace", speed = 4.6, spots = {
		{ 0, 0, "behind", w = { 6, 10 } },
		{ 13, 0, "whistle", yaw = -90 },
		{ -13, 0, "lookout", yaw = 90 },
	} },
	promoter_ray = { at = { 4, -10 }, yaw = 180, greet = "wave", home = "flyers", nav = 24, approach = true, pointTo = "CLUB OCEAN 광안", speed = 6.2, idle = { "wave_small" } },
	promoter_nana = { at = { 8, -76 }, yaw = 180, greet = "wave", home = "flyers", nav = 24, approach = true, pointTo = "CLUB OCEAN 광안", speed = 6.2, idle = { "wave_small" } },
	club_guard = { at = { -15.3, -2.1 }, yaw = 90, greet = "nod", call = "stop_hand", speed = 3.2, spots = {
		{ 0, 0, "arms_crossed", w = { 8, 14 } },
		{ 1.8, 0.5, "guard" },
		{ -1.6, 0, "guard", yaw = 20 },
	} },
}
local DEFAULT_ROUTINE = { greet = "wave", spots = { { 0, 0, "idle", w = { 6, 12 } }, { 2.5, 0.5, "look" }, { -2.5, 0.5, "phone" } } }

-------------------------------------------------------------------------------------------------
-- Daily life. SCHEDULE[id] = { { from, to, post }, ... } in in-game hours (a window may wrap midnight;
-- the first window holding the clock wins; none = "home", the day post above). post = "home" |
-- "off" (gone home / closed: the NPC walks off and is hidden) | a POSTS key. Street key NPCs with
-- roster hours (GwangalliCitizens `hours`, the promoters and the guard) are "off" outside them.
-------------------------------------------------------------------------------------------------
local SCHEDULE: { [string]: { { any } } } = {
	minji = { { 20, 22, "club_front" }, { 22, 3, "club_in" }, { 3, 9, "off" } },
	junho = { { 20.5, 22.5, "club_front" }, { 22.5, 2.5, "club_in" }, { 2.5, 8.5, "off" } },
	lifeguard_chief = { { 19.5, 8, "tower" } }, -- no patrol after dark: paperwork at the tower
	beach_guard = { { 19, 9, "off" } },
	bungeoppang = { { 22, 11, "off" } },
	photo_tourist = { { 20, 10, "off" } },
	busker = { { 0, 16, "off" } }, -- plays 16:00 - 24:00
}
-- POSTS: where = "club_front" (CLUB OCEAN forecourt, beside the door staff, out of the queue lane) |
-- "club_in" (the main hall by the bar, facing the dance floor) | "rel" (the day post itself). The
-- friends share club posts (slot 1 minji, slot 2 junho, facing each other). spots / idle / order /
-- home as in ROUTINES (they replace the day routine's while the NPC is there); turns = false: no
-- chat / listen turn-taking with the partner; pointTo = false: no pointing the way.
local POSTS: { [string]: any } = {
	club_front = { where = "club_front", home = "chat", idle = { "laugh", "point", "nod" }, spots = {
		{ 0, 0, "chat", w = { 8, 14 } },
		{ 1.4, 1.6, "phone", yaw = 30, w = { 5, 8 } },
		{ -1.3, 1.4, "photo", yaw = -40, w = { 4, 7 } },
		{ 0.4, -1.6, "look", yaw = 180, w = { 4, 7 } },
	} },
	club_in = { where = "club_in", home = "dance", turns = false, pointTo = false, idle = { "cheer", "laugh", "clap" }, spots = {
		{ 0, 0, "dance", w = { 10, 18 } },
		{ 1.3, 1.1, "cup", yaw = 20, w = { 6, 10 } },
		{ -1.1, 1.3, "dance2", w = { 8, 12 } },
		{ 0.3, -1.4, "cheer", yaw = 180, w = { 4, 7 } },
	} },
	tower = { where = "rel", home = "clipboard", order = "random", spots = {
		{ 0, 0, "clipboard", w = { 10, 16 } },
		{ 1.6, 0.5, "phone", yaw = -30, w = { 6, 10 } },
		{ -1.6, 0.3, "arms_crossed", yaw = 30, w = { 6, 10 } },
	} },
}
local PAIR_SLOT = { minji = 1, junho = 2 }
local TRANSIT_SPEED = 5.6 -- studs / s between posts (a brisk city walk)
local SKIP_R = 160 -- nobody this close to the NPC nor to where it goes: the move happens at once
local SEEN_R = 60 -- appearing / vanishing points stay at least this far from every player

-- Dialog hints (Relationships emote names) -> GwangalliAnim emotes.
local HINT_EMOTE = { greet = "wave", think = "think", refuse = "shake", dance = "dance1", cheer = "cheer", shy = "shy", laugh = "laugh", nod = "nod" }

-------------------------------------------------------------------------------------------------
-- NPC state
-------------------------------------------------------------------------------------------------
type Spot = { pos: Vector3, yaw: number, act: string, w: { number }?, emote: string?, checked: boolean, ok: boolean, why: string? }
type St = {
	id: string,
	street: boolean,
	disp: any,
	spec: any,
	model: Model,
	root: BasePart,
	ground: number,
	home: Vector3,
	homeYaw: number,
	floorless: boolean,
	spots: { Spot },
	cur: number,
	seq: number,
	pos: Vector3,
	yaw: number,
	act: string,
	leg: any?,
	waitUntil: number,
	attendUntil: number,
	talker: Player?,
	talkUntil: number,
	talkActUntil: number,
	noticed: { [Player]: number },
	approach: Player?,
	offerUntil: number,
	nextIdle: number,
	nextCall: number,
	emoteSeq: number,
	attrs: { [string]: any },
	hidden: boolean,
	lastRootWrite: number,
	pendingRoot: boolean,
	legOk: { [string]: boolean },
	offPath: boolean,
	returnTo: any?,
	nextTalk: number,
	talkStart: number,
	pointAt: number,
	nextSwap: number,
	nextApproach: number,
	-- daily life
	post: string, -- "home" | "off" | a POSTS key
	pspec: any?, -- POSTS[post] while away from the day post
	move: any?, -- a move between posts in progress
	day: any, -- the day post: { home, homeYaw, spots, floorless }
	extras: { Instance }, -- props that leave with the NPC (the busker's amp)
	sched: { { any } }?,
	postFail: { [string]: number },
}
local npcs: { [string]: St } = {}
local order: { St } = {}

local function optional(name: string): any
	local m = ReplicatedStorage:FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, m)
	if ok and type(res) == "table" then
		return res
	end
	warn("[GwangalliGameplay] npc: " .. name .. " failed to load: " .. tostring(res))
	return nil
end

local function nav(): any
	if not navTried then
		navTried = true
		Nav = optional("GwangalliNav")
		if Nav then
			local ok = pcall(Nav.decode)
			if not ok then
				Nav = nil
			end
		end
	end
	return Nav
end

local function color(rgb: any, fallback: Color3): Color3
	return Util.color(rgb, fallback)
end

local function yawOf(v: Vector3): number
	return math.deg(math.atan2(-v.X, -v.Z))
end

local function yawCF(yaw: number): CFrame
	return CFrame.Angles(0, math.rad(yaw), 0)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function serverNow(): number
	local ok, t = pcall(workspace.GetServerTimeNow, workspace)
	return if ok and type(t) == "number" then t else os.clock()
end

local function setAttr(st: St, key: string, value: any)
	if st.attrs[key] ~= value then
		st.attrs[key] = value
		st.model:SetAttribute(key, value)
	end
end

local function writeRoot(st: St)
	st.lastRootWrite = os.clock()
	st.pendingRoot = false
	st.root.CFrame = CFrame.new(st.pos + Vector3.new(0, st.ground, 0)) * yawCF(st.yaw)
end

local function setYaw(st: St, yaw: number)
	yaw = (yaw + 180) % 360 - 180
	if math.abs(((yaw - st.yaw + 180) % 360) - 180) < 2 then
		return
	end
	st.yaw = yaw
	setAttr(st, "NpcYaw", math.floor(yaw * 10 + 0.5) / 10)
	-- the server copy of the root follows (throttled; clients turn smoothly from the attribute)
	if os.clock() - st.lastRootWrite > 1 then
		writeRoot(st)
	else
		st.pendingRoot = true
	end
end

local function faceToward(st: St, pos: Vector3, tolerance: number?)
	local d = flat(pos - st.pos)
	if d.Magnitude < 0.5 then
		return
	end
	local want = yawOf(d)
	if math.abs(((want - st.yaw + 180) % 360) - 180) > (tolerance or 8) then
		setYaw(st, want)
	end
end

local function setAct(st: St, act: string)
	if st.act ~= act then
		st.act = act
		setAttr(st, "NpcAct", act)
	end
end

local function emote(st: St, name: string?)
	if not name or st.hidden then
		return
	end
	st.emoteSeq += 1
	setAttr(st, "NpcEmote", string.format("%s#%d#%.1f", name, st.emoteSeq, serverNow()))
end

local function look(st: St, player: Player?)
	setAttr(st, "NpcLook", if player then player.UserId else 0)
end

-- A point along a polyline leg: (position, direction of the segment it is on).
local function polyAt(poly: any, dist: number): (Vector3, Vector3?)
	local pts, cum = poly.pts, poly.cum
	if dist <= 0 then
		return pts[1], if #pts > 1 then pts[2] - pts[1] else nil
	end
	for i = 2, #pts do
		if dist <= cum[i] then
			local seg = cum[i] - cum[i - 1]
			local u = if seg > 1e-4 then (dist - cum[i - 1]) / seg else 1
			return pts[i - 1]:Lerp(pts[i], u), pts[i] - pts[i - 1]
		end
	end
	return pts[#pts], nil
end

-- Where the NPC's feet are right now (mid-walk: interpolated like the clients do).
local function currentPos(st: St): Vector3
	local leg = st.leg
	if not leg then
		return st.pos
	end
	local a = math.clamp((serverNow() - leg.t0) / leg.dur, 0, 1)
	if leg.poly then
		return (polyAt(leg.poly, a * leg.poly.total))
	end
	return leg.from:Lerp(leg.to, a)
end

local function legAttr(from: Vector3, to: Vector3, t0: number, dur: number): string
	return string.format("%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f", from.X, from.Y, from.Z, to.X, to.Y, to.Z, t0, dur)
end

-- Stands the NPC at `feet` facing `yaw` at once (a zero-length leg: clients snap there too).
local function place(st: St, feet: Vector3, yaw: number)
	st.leg = nil
	st.pos = feet
	st.yaw = (yaw + 180) % 360 - 180
	setAttr(st, "NpcYaw", math.floor(st.yaw * 10 + 0.5) / 10)
	setAttr(st, "NpcLeg", legAttr(feet, feet, serverNow(), 0.01))
	st.root.CFrame = CFrame.new(feet + Vector3.new(0, st.ground, 0)) * yawCF(st.yaw)
	st.lastRootWrite = os.clock()
	st.pendingRoot = false
end

local function startLeg(st: St, to: Vector3, speed: number?, spot: number?)
	local from = currentPos(st)
	local d = flat(to - from).Magnitude
	if d < 0.4 then
		st.pos = to
		st.leg = nil
		return
	end
	local dur = d / (speed or st.spec.speed or WALK_SPEED)
	local t0 = serverNow() + 0.15 -- a little lead so the clients start in step
	st.leg = { from = from, to = to, t0 = t0, dur = dur, arrive = os.clock() + dur + 0.15, spot = spot }
	st.pos = from
	st.yaw = yawOf(flat(to - from))
	setAttr(st, "NpcYaw", math.floor(st.yaw * 10 + 0.5) / 10)
	setAttr(st, "NpcLeg", legAttr(from, to, t0, dur))
end

-- Walks a polyline (feet points; the first is where the NPC stands) at a constant speed: one
-- attribute for the whole walk, so clients glide through the corners without waiting for the server.
local function startPath(st: St, raw: { Vector3 }, speed: number)
	local pts: { Vector3 } = {}
	for _, p in raw do
		-- the same rounding the attribute carries (clients time the walk from those numbers)
		local q = Vector3.new(math.round(p.X * 10) / 10, math.round(p.Y * 100) / 100, math.round(p.Z * 10) / 10)
		if #pts == 0 or (q - pts[#pts]).Magnitude > 0.05 then
			table.insert(pts, q)
		end
	end
	if #pts < 2 then
		st.leg = nil
		return
	end
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	local total = cum[#pts]
	local sp = math.round(speed * 1000) / 1000
	local dur = total / sp
	local t0 = math.round((serverNow() + 0.15) * 100) / 100
	st.leg = { from = pts[1], to = pts[#pts], t0 = t0, dur = dur, arrive = os.clock() + dur + 0.15, spot = nil, poly = { pts = pts, cum = cum, total = total } }
	st.pos = pts[1]
	local d = flat(pts[2] - pts[1])
	if d.Magnitude > 0.05 then
		st.yaw = yawOf(d)
		setAttr(st, "NpcYaw", math.floor(st.yaw * 10 + 0.5) / 10)
	end
	local buf = { "P", string.format("%.2f", t0), string.format("%.3f", sp) }
	for _, p in pts do
		table.insert(buf, string.format("%.1f,%.2f,%.1f", p.X, p.Y, p.Z))
	end
	setAttr(st, "NpcLeg", table.concat(buf, ";"))
end

-- Stops a walk where the NPC is now (clients compute the same point: no jump).
local function halt(st: St)
	if not st.leg then
		return
	end
	local p = currentPos(st)
	st.leg = nil
	st.pos = p
	st.offPath = true -- next walk: back home (the line home is part of the validated walk)
	setAttr(st, "NpcLeg", legAttr(p, p, serverNow(), 0.01))
	writeRoot(st)
end

-------------------------------------------------------------------------------------------------
-- Spatial checks (spots are validated lazily, the first time the NPC wants to walk there)
-------------------------------------------------------------------------------------------------
local function queryParams(): (RaycastParams, OverlapParams)
	local ignore = Util.charactersIgnore({ folder :: any })
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.IgnoreWater = true
	pcall(function()
		(rp :: any).RespectCanCollide = true
	end)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = ignore
	pcall(function()
		(op :: any).RespectCanCollide = true
	end)
	return rp, op
end

-- Characters and our own rigs never count as obstacles / floors.
local function ignoredPart(p: Instance): boolean
	if folder and p:IsDescendantOf(folder) then
		return true
	end
	local m = p:FindFirstAncestorOfClass("Model")
	return m ~= nil and Players:GetPlayerFromCharacter(m) ~= nil
end

-- Raycast that survives a rejected params object (an engine / test-harness quirk: the filtered call
-- errors): it retries unfiltered and drops hits on characters, rigs and non-colliding parts.
local function ray(from: Vector3, dir: Vector3, rp: RaycastParams): (boolean, RaycastResult?)
	local ok, hit = pcall(workspace.Raycast, workspace, from, dir, rp)
	if ok then
		return true, hit
	end
	ok, hit = pcall(workspace.Raycast, workspace, from, dir)
	if ok and hit and (hit.Material == Enum.Material.Water or not hit.Instance.CanCollide or ignoredPart(hit.Instance)) then
		return true, nil
	end
	return ok, hit
end

local function floorY(pos: Vector3, rp: RaycastParams): number?
	local ok, hit = ray(pos + Vector3.new(0, 5, 0), Vector3.new(0, -14, 0), rp)
	if ok and hit then
		return hit.Position.Y
	end
	return nil
end

local function roomAt(feet: Vector3, op: OverlapParams): (boolean, string?)
	local cf, size = CFrame.new(feet + Vector3.new(0, 2.9, 0)), Vector3.new(1.6, 4.4, 1.6)
	local ok, parts = pcall(workspace.GetPartBoundsInBox, workspace, cf, size, op)
	if not ok then
		ok, parts = pcall(workspace.GetPartBoundsInBox, workspace, cf, size)
		if not ok then
			return false, "query failed"
		end
	end
	for _, p in parts do
		if p.CanCollide and not p:IsA("Terrain") and not ignoredPart(p) then
			return false, p:GetFullName()
		end
	end
	return true, nil
end

local function clearLine(a: Vector3, b: Vector3, rp: RaycastParams): (boolean, string?)
	for _, h in { 1.3, 3.4 } do
		local from = a + Vector3.new(0, h, 0)
		local dir = (b + Vector3.new(0, h, 0)) - from
		if dir.Magnitude > 0.2 then
			local ok, hit = ray(from, dir, rp)
			if not ok or (hit and hit.Instance and hit.Instance.CanCollide) then
				return false, if ok and hit then hit.Instance:GetFullName() else "query failed"
			end
		end
	end
	return true, nil
end

local function validSpot(st: St, i: number): boolean
	local s = st.spots[i]
	if not s then
		return false
	end
	if s.checked then
		return s.ok
	end
	s.checked = true
	local rp, op = queryParams()
	local y = floorY(s.pos, rp)
	if not y then
		y = if st.floorless then st.home.Y else nil -- terrain-only ground (beach sand) not loaded / not queryable
	end
	if not y or math.abs(y - st.home.Y) > 2.6 then
		s.ok = false
		s.why = if y then string.format("step %.1f", y - st.home.Y) else "no floor"
		return false
	end
	s.pos = Vector3.new(s.pos.X, y, s.pos.Z)
	local room, blocker = roomAt(s.pos, op)
	local line, hitName = false, nil
	if room then
		line, hitName = clearLine(st.home, s.pos, rp)
	end
	s.ok = room and line
	s.why = if not room then "blocked by " .. tostring(blocker) elseif not line then "line hits " .. tostring(hitName) else nil
	return s.ok
end

local function legClear(st: St, a: number, b: number): boolean
	if a == 1 or b == 1 then
		return true -- every valid spot has a clear line to home
	end
	if not st.spots[a] or not st.spots[b] then
		return false
	end
	local key = if a < b then a .. ":" .. b else b .. ":" .. a
	local v = st.legOk[key]
	if v == nil then
		local rp = queryParams()
		v = clearLine(st.spots[a].pos, st.spots[b].pos, rp)
		st.legOk[key] = v
	end
	return v
end

-------------------------------------------------------------------------------------------------
-- Rigs
-------------------------------------------------------------------------------------------------
local function propPart(model: Model, attach: BasePart, name: string, size: Vector3, offset: CFrame, rgb: Color3, prop: string?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = attach.CFrame * offset
	p.Color = rgb
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Anchored = false
	if prop then
		p.Transparency = 1
		p:SetAttribute("Prop", prop)
	end
	p.Parent = model
	if Anim and Anim.weld then
		Anim.weld(attach, p)
	else
		local w = Instance.new("WeldConstraint")
		w.Part0 = attach
		w.Part1 = p
		w.Parent = p
	end
	return p
end

local function propsFor(spec: any): { [string]: boolean }
	local need: { [string]: boolean } = {}
	local acts = { spec.home, spec.night and spec.night.home }
	for _, s in spec.spots or {} do
		table.insert(acts, s[3])
	end
	for _, a in acts do
		local def = a and Anim and Anim.ACTS[a]
		if def and def.prop then
			need[def.prop] = true
		end
	end
	return need
end

local function citizenLook(id: string): any?
	return Citizens and Citizens.byId and Citizens.byId[id]
end

-- Builds the rig at the origin (feet at y = -ground). Returns model, root, parts, ground.
local function buildRig(id: string, disp: any, spec: any): (Model, BasePart, { [string]: BasePart }, number)
	local c = citizenLook(id)
	local model: Model? = nil
	local root: BasePart? = nil
	local parts: { [string]: BasePart } = {}
	local ground = 3
	if Looks and c then
		local ok, rig = pcall(function()
			return Looks.build(Looks.forCitizen(c, false), { name = "NPC_" .. id, anchored = true, shadow = false })
		end)
		if ok and type(rig) == "table" and rig.model then
			model, root, parts, ground = rig.model, rig.root, rig.parts, rig.ground or 3
			if rig.phone then
				rig.phone:SetAttribute("Prop", "phone")
			end
		else
			warn("[GwangalliGameplay] npc " .. id .. ": look build failed: " .. tostring(rig))
		end
	end
	if not model and Anim then
		local m, p = Anim.buildR15({
			name = "NPC_" .. id,
			shirt = color(disp.shirt or disp.color, Color3.fromRGB(200, 200, 200)),
			pants = color(disp.pants, Color3.fromRGB(40, 40, 50)),
			sleeves = "short",
			build = if c and c.look and c.look.build then c.look.build else "avg",
			body = if c and c.g then c.g else "m",
		})
		-- Anim rigs stand with the feet at y = 0: move the root to the origin like Looks rigs
		m:PivotTo(CFrame.new(0, -Anim.R15.rootY, 0) * m:GetPivot())
		model, root, parts, ground = m, p.HumanoidRootPart, p, Anim.R15.rootY
	end
	assert(model and root, "no rig builder")
	local m = model :: Model
	local r = root :: BasePart
	local s = ground / 3
	-- props for the acts of this routine (hidden until an act shows them)
	local need = propsFor(spec)
	local rh, lh, ut = parts.RightHand, parts.LeftHand, parts.UpperTorso
	if need.phone and rh and not m:FindFirstChild("Phone") then
		propPart(m, rh, "Phone", Vector3.new(0.34, 0.62, 0.08) * s, CFrame.new(0, -0.15 * s, -0.42 * s), Color3.fromRGB(18, 18, 22), "phone")
	end
	if need.clipboard and lh then
		propPart(m, lh, "Clipboard", Vector3.new(0.9, 0.08, 1.15) * s, CFrame.new(0.1 * s, -0.12 * s, -0.45 * s), Color3.fromRGB(60, 64, 76), "clipboard")
	end
	if need.cup and rh then
		propPart(m, rh, "Cup", Vector3.new(0.34, 0.5, 0.34) * s, CFrame.new(0, 0, -0.38 * s), Color3.fromRGB(245, 245, 240), "cup")
	end
	if need.rag and rh then
		propPart(m, rh, "Rag", Vector3.new(0.7, 0.08, 0.6) * s, CFrame.new(0, -0.24 * s, -0.1 * s), Color3.fromRGB(235, 235, 225), "rag")
	end
	if spec.amp and ut then
		-- the busker plays her guitar in front (the look's guitar hangs on the back)
		for _, n in { "GuitarBody", "GuitarNeck" } do
			local g = m:FindFirstChild(n)
			if g then
				g:Destroy()
			end
		end
		local body = propPart(m, ut, "GuitarBody", Vector3.new(1.25, 1.45, 0.34) * s, CFrame.new(0.35 * s, -0.55 * s, -0.74 * s) * CFrame.Angles(0, 0, math.rad(60)), Color3.fromRGB(176, 104, 52))
		body.Material = Enum.Material.Wood
		propPart(m, ut, "GuitarNeck", Vector3.new(0.24, 1.8, 0.16) * s, CFrame.new(-1.0 * s, 0.25 * s, -0.74 * s) * CFrame.Angles(0, 0, math.rad(60)), Color3.fromRGB(58, 38, 28))
	end
	if id == "photo_tourist" and rh then
		local cam = m:FindFirstChild("Camera")
		if cam then
			cam:Destroy()
		end
		propPart(m, rh, "Camera", Vector3.new(0.7, 0.46, 0.4) * s, CFrame.new(-0.1 * s, 0, -0.45 * s), Color3.fromRGB(26, 26, 30))
	end
	return m, r, parts, ground
end

local function nameTag(model: Model, head: BasePart?, disp: any)
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "NameTag"
	bb.Size = UDim2.fromOffset(170, 46)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	bb.MaxDistance = 70
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	bb.Adornee = head
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = disp.name
	nameLabel.Parent = bb
	local roleLabel = Instance.new("TextLabel")
	roleLabel.Name = "Role"
	roleLabel.BackgroundTransparency = 1
	roleLabel.Position = UDim2.fromScale(0, 0.55)
	roleLabel.Size = UDim2.new(1, 0, 0.45, 0)
	roleLabel.Font = Enum.Font.Gotham
	roleLabel.TextScaled = true
	roleLabel.TextColor3 = color(disp.color, Color3.fromRGB(255, 220, 120)):Lerp(Color3.new(1, 1, 1), 0.35)
	roleLabel.TextStrokeTransparency = 0.5
	roleLabel.Text = disp.role
	roleLabel.Parent = bb
	bb.Parent = head
end

-- 붕어빵 cart in front of the vendor (anchored; skipped when the spot is taken).
local function buildStall(st: St)
	local look = yawCF(st.homeYaw).LookVector
	local base = st.home + look * 2.1
	local cf = CFrame.new(base) * yawCF(st.homeYaw)
	local _, op = queryParams()
	local ok, hits = pcall(workspace.GetPartBoundsInBox, workspace, cf * CFrame.new(0, 1.6, 0), Vector3.new(3.8, 2.8, 1.9), op)
	if not ok then
		ok, hits = pcall(workspace.GetPartBoundsInBox, workspace, cf * CFrame.new(0, 1.6, 0), Vector3.new(3.8, 2.8, 1.9))
		if not ok then
			return
		end
	end
	for _, p in hits do
		if p.CanCollide and not p:IsA("Terrain") and not ignoredPart(p) then
			return
		end
	end
	local m = Instance.new("Model")
	m.Name = "Stall_" .. st.id
	local function p(name: string, size: Vector3, off: CFrame, rgb: { number }, mat: Enum.Material?, collide: boolean?): Part
		local q = Instance.new("Part")
		q.Name = name
		q.Size = size
		q.CFrame = cf * off
		q.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		q.Material = mat or Enum.Material.SmoothPlastic
		q.Anchored = true
		q.CanCollide = collide == true
		q.CanTouch = false
		q.CanQuery = collide == true
		q.CastShadow = collide == true
		q.TopSurface = Enum.SurfaceType.Smooth
		q.BottomSurface = Enum.SurfaceType.Smooth
		q.Parent = m
		return q
	end
	p("Cart", Vector3.new(3.6, 2.5, 1.7), CFrame.new(0, 1.35, 0), { 196, 44, 40 }, nil, true)
	p("Counter", Vector3.new(3.8, 0.16, 1.9), CFrame.new(0, 2.68, 0), { 190, 192, 196 }, Enum.Material.Metal)
	p("Grill", Vector3.new(2.4, 0.2, 1.0), CFrame.new(-0.4, 2.84, 0.2), { 40, 40, 44 }, Enum.Material.Metal)
	for i = 0, 3 do
		p("Fish", Vector3.new(0.42, 0.14, 0.26), CFrame.new(-1.2 + i * 0.55, 2.98, 0.15) * CFrame.Angles(0, 0.3, 0), { 196, 136, 64 })
	end
	for _, sx in { -1, 1 } do
		p("Pole", Vector3.new(0.12, 2.3, 0.12), CFrame.new(sx * 1.75, 3.9, 0.7), { 200, 200, 200 }, Enum.Material.Metal)
	end
	for i = 0, 3 do
		p("Awning", Vector3.new(0.98, 0.12, 2.3), CFrame.new(-1.47 + i * 0.98, 5.08, 0.3) * CFrame.Angles(-0.12, 0, 0), if i % 2 == 0 then { 220, 50, 46 } else { 250, 246, 236 })
	end
	local sign = p("Sign", Vector3.new(2.6, 0.7, 0.1), CFrame.new(0, 1.8, -0.9), { 250, 236, 200 })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(260, 70)
	sg.LightInfluence = 0.3
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(160, 30, 30)
	t.Text = "붕어빵 3개 2,000원"
	t.Parent = sg
	sg.Parent = sign
	m.Parent = folder
end

local function buildAmp(st: St)
	local right = yawCF(st.homeYaw).RightVector
	local pos = st.home + right * 1.9 + yawCF(st.homeYaw).LookVector * 0.4
	local a = Instance.new("Part")
	a.Name = "Amp_" .. st.id
	a.Size = Vector3.new(1.3, 1.5, 0.9)
	a.CFrame = CFrame.new(pos + Vector3.new(0, 0.75, 0)) * yawCF(st.homeYaw)
	a.Color = Color3.fromRGB(30, 30, 34)
	a.Material = Enum.Material.SmoothPlastic
	a.Anchored = true
	a.CanCollide = false
	a.CanTouch = false
	a.CanQuery = false
	a.Parent = folder
	table.insert(st.extras, a)
	local grill = Instance.new("Part")
	grill.Name = "AmpGrill"
	grill.Size = Vector3.new(1.0, 1.0, 0.05)
	grill.CFrame = a.CFrame * CFrame.new(0, -0.1, -0.46)
	grill.Color = Color3.fromRGB(80, 80, 86)
	grill.Material = Enum.Material.Fabric
	grill.Anchored = true
	grill.CanCollide = false
	grill.CanTouch = false
	grill.CanQuery = false
	grill.Parent = a
end

-------------------------------------------------------------------------------------------------
-- Spawning
-------------------------------------------------------------------------------------------------
local function ensureFolder(): Folder
	if not folder or not folder.Parent then
		local f = workspace:FindFirstChild("GwangalliNPCs")
		if not f or not f:IsA("Folder") then
			f = Instance.new("Folder")
			f.Name = "GwangalliNPCs"
			f.Parent = workspace
		end
		folder = f :: Folder
	end
	return folder :: Folder
end

local function isNight(): boolean
	local ok, env = pcall(ctx.env)
	return ok and env and env.night == true
end

-- A routine field: the current post's (POSTS) when the NPC is away from its day post, else the day
-- routine's. false in a post disables the day routine's value there.
local function R(st: St, key: string): any
	local ps = st.pspec
	if ps and ps[key] ~= nil then
		return if ps[key] == false then nil else ps[key]
	end
	return st.spec[key]
end

local function homeAct(st: St): string
	local spec = st.spec
	local ps = st.pspec
	if ps then
		return ps.home or (st.spots[1] and st.spots[1].act) or "idle"
	end
	if spec.night and isNight() and spec.night.home then
		return spec.night.home
	end
	return spec.home or (st.spots[1] and st.spots[1].act) or "idle"
end

local function onTrigger(st: St, player: Player)
	if st.hidden then
		return
	end
	if not st.street then
		local ok, err = pcall(NPC.open, player, st.id, false)
		if not ok then
			warn("[GwangalliGameplay] npc dialog failed: " .. tostring(err))
		end
		return
	end
	local pos = Util.rootPosition(player)
	if not pos or (pos - currentPos(st)).Magnitude > G.NPC_TALK_RADIUS + 6 then
		return
	end
	if not Util.cooldown(player, "npcOpen", 0.5) then
		return
	end
	local social = ctx.social
	if social and social.openDialog then
		local ok, err = pcall(social.openDialog, player, st.id, currentPos(st) + Vector3.new(0, st.ground, 0), false)
		if not ok then
			warn("[GwangalliGameplay] street npc dialog failed: " .. tostring(err))
		end
	end
	-- Relationships owns this dialog: engage until the player leaves (or a minute passes)
	NPC.engage(st.id, player, 45)
end

local function spawnNpc(id: string, disp: any, destPart: BasePart, street: boolean)
	if npcs[id] and (npcs[id].model.Parent ~= nil or npcs[id].hidden) then
		return -- (a hidden NPC is off duty, not gone)
	end
	local parent = ensureFolder()
	local spec = ROUTINES[id] or DEFAULT_ROUTINE
	local look = Util.flatLook(destPart.CFrame)
	local right = look:Cross(Vector3.yAxis)
	local groundPt = Util.groundOf(destPart)
	local destYaw = yawOf(look)
	local at = spec.at or (disp.offset and { disp.offset[1], -disp.offset[2] }) or { 4, 3 }
	local guess = groundPt + right * at[1] + look * at[2]
	local ignore = Util.charactersIgnore({ destPart, parent :: Instance })
	local cf = Util.safeAt(guess, look, 0, ignore)
	local feet = if cf then cf.Position - Vector3.new(0, 0.5, 0) else guess
	if not cf then
		-- Util's probe failed (its filtered queries can be rejected): the same probe with our fallbacks
		local rp, op = queryParams()
		for _, o in { { 0, 0 }, { 0, 3 }, { 0, -3 }, { 3, 0 }, { -3, 0 }, { 0, 6 }, { 0, -6 } } do
			local probe = guess + right * o[1] + look * o[2]
			local okR, hit = ray(probe + Vector3.new(0, 4, 0), Vector3.new(0, -16, 0), rp)
			if okR and hit then
				local f = Vector3.new(probe.X, hit.Position.Y, probe.Z)
				if roomAt(f, op) then
					feet = f
					cf = CFrame.new(f + Vector3.new(0, 0.5, 0))
					break
				end
			end
		end
	end
	local homeYaw
	if spec.yaw then
		homeYaw = destYaw + spec.yaw
	else
		local toDest = flat(destPart.Position - feet)
		homeYaw = if toDest.Magnitude > 0.5 then yawOf(toDest) else destYaw
	end
	local model, root, parts, ground = buildRig(id, disp, spec)
	model.Name = "NPC_" .. id
	local st: St = {
		id = id,
		street = street,
		disp = disp,
		spec = spec,
		model = model,
		root = root,
		ground = ground,
		home = feet,
		homeYaw = homeYaw,
		floorless = cf == nil,
		spots = {},
		cur = 1,
		seq = 0,
		pos = feet,
		yaw = homeYaw,
		act = "idle",
		leg = nil,
		waitUntil = os.clock() + 1 + math.random() * 4,
		attendUntil = 0,
		talker = nil,
		talkUntil = 0,
		talkActUntil = 0,
		noticed = {},
		approach = nil,
		offerUntil = 0,
		nextIdle = os.clock() + 8 + math.random() * 10,
		nextCall = os.clock() + 5 + math.random() * 10,
		emoteSeq = 0,
		attrs = {},
		hidden = false,
		lastRootWrite = 0,
		pendingRoot = false,
		legOk = {},
		offPath = false,
		returnTo = nil,
		nextTalk = 0,
		talkStart = 0,
		pointAt = 0,
		nextSwap = 0,
		nextApproach = 0,
		post = "home",
		pspec = nil,
		move = nil,
		day = nil :: any,
		extras = {},
		sched = nil,
		postFail = {},
	}
	-- spots in the home frame
	local hf = CFrame.new(feet) * yawCF(homeYaw)
	if spec.nav then
		table.insert(st.spots, { pos = feet, yaw = homeYaw, act = spec.home or "idle", w = { 4, 8 }, checked = true, ok = true })
		local N = nav()
		if N then
			local okN, cache = pcall(N.decode)
			if okN and cache and cache.pos then
				local count = 0
				local nodes = {}
				for i, p in cache.pos do
					local d = flat(p - feet).Magnitude
					if d > 4 and d <= spec.nav and math.abs(p.Y - feet.Y) < 2.5 then
						table.insert(nodes, { i = i, d = d, p = p })
					end
				end
				table.sort(nodes, function(a, b)
					return a.d < b.d
				end)
				local taken: { Vector3 } = {}
				for _, n in nodes do
					local okSep = true
					for _, q in taken do
						if flat(q - n.p).Magnitude < 6 then
							okSep = false
							break
						end
					end
					if okSep then
						table.insert(taken, n.p)
						count += 1
						table.insert(st.spots, { pos = n.p, yaw = math.random(-180, 180), act = spec.home or "idle", w = { 3, 7 }, checked = false, ok = false })
						if count >= 10 then
							break
						end
					end
				end
			end
		end
		if #st.spots == 1 then
			for _, o in { { 5, 2 }, { -5, 2 }, { 0, 6 }, { 6, -3 }, { -6, -3 } } do
				table.insert(st.spots, { pos = (hf * CFrame.new(o[1], 0, -o[2])).Position, yaw = homeYaw + math.random(-60, 60), act = spec.home or "idle", checked = false, ok = false })
			end
		end
	else
		for i, s in spec.spots or {} do
			local p = (hf * CFrame.new(s[1], 0, -s[2])).Position
			table.insert(st.spots, { pos = if i == 1 then feet else p, yaw = homeYaw + (s.yaw or 0), act = s[3] or "idle", w = s.w, emote = s.emote, checked = i == 1, ok = i == 1 })
		end
		if #st.spots == 0 then
			table.insert(st.spots, { pos = feet, yaw = homeYaw, act = spec.home or "idle", checked = true, ok = true })
		end
	end
	st.day = { home = feet, homeYaw = homeYaw, spots = st.spots, floorless = st.floorless, legOk = st.legOk }
	st.act = homeAct(st)
	-- attributes before parenting (clients see a complete state on stream-in)
	model:SetAttribute("NpcId", id)
	model:SetAttribute("NpcPost", "home")
	st.attrs.NpcPost = "home"
	model:SetAttribute("NpcKind", if street then "street" else "key")
	model:SetAttribute("NpcGround", ground)
	st.attrs.NpcAct = st.act
	model:SetAttribute("NpcAct", st.act)
	st.attrs.NpcYaw = math.floor(homeYaw * 10 + 0.5) / 10
	model:SetAttribute("NpcYaw", st.attrs.NpcYaw)
	model:SetAttribute("NpcLook", 0)
	model:SetAttribute("NpcTalk", 0)
	model:SetAttribute("NpcLeg", "")
	model:SetAttribute("NpcEmote", "")
	st.attrs.NpcLook, st.attrs.NpcTalk, st.attrs.NpcLeg, st.attrs.NpcEmote = 0, 0, "", ""
	model:PivotTo(CFrame.new(feet + Vector3.new(0, ground, 0)) * yawCF(homeYaw))
	st.lastRootWrite = os.clock()
	nameTag(model, parts.Head, disp)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GwangalliTalkPrompt"
	prompt.ActionText = if street then "말 걸기" else "대화"
	prompt.ObjectText = disp.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.UIOffset = Vector2.new(0, 0)
	prompt.Parent = root
	prompt.Triggered:Connect(function(player: Player)
		onTrigger(st, player)
	end)
	pcall(function()
		(model :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	model.Parent = parent
	npcs[id] = st
	table.insert(order, st)
	if spec.stall then
		pcall(buildStall, st)
	end
	if spec.amp then
		pcall(buildAmp, st)
	end
end

local function streetDisp(c: any): any
	return { name = c.name, role = c.job, color = c.accent, shirt = c.accent }
end

local scheduleNow: (St) -> () -- (Daily life, below) puts a fresh NPC where the clock says

function NPC.onDest(name: string, destPart: BasePart)
	for _, id in G.NPC_ORDER do
		local def = G.NPCS[id]
		if def.dest == name then
			local ok, err = pcall(spawnNpc, id, def, destPart, false)
			if not ok then
				warn("[GwangalliGameplay] npc " .. id .. " spawn failed: " .. tostring(err))
			elseif npcs[id] then
				pcall(scheduleNow, npcs[id])
			end
		end
	end
	if Citizens and Citizens.KEY_IDS and Citizens.AREAS then
		for _, id in Citizens.KEY_IDS do
			local c = Citizens.byId[id]
			if c and not G.NPCS[id] and c.post then
				local area = Citizens.AREAS[c.post]
				if area and area.dest == name then
					local ok, err = pcall(spawnNpc, id, streetDisp(c), destPart, true)
					if not ok then
						warn("[GwangalliGameplay] street npc " .. id .. " spawn failed: " .. tostring(err))
					elseif npcs[id] then
						pcall(scheduleNow, npcs[id])
					end
				end
			end
		end
	end
end

local function npcPosition(npcId: string): Vector3?
	local st = npcs[npcId]
	if st then
		if st.hidden then
			return nil -- gone home / not in yet: nobody to talk to in person
		end
		return currentPos(st) + Vector3.new(0, st.ground, 0)
	end
	local def = G.NPCS[npcId]
	local dp = def and ctx.dest(def.dest)
	return dp and dp.Position or nil
end

local function near(player: Player, npcId: string, slack: number?): boolean
	local pos = Util.rootPosition(player)
	local at = npcPosition(npcId)
	return pos ~= nil and at ~= nil and (pos - at).Magnitude <= G.NPC_TALK_RADIUS + (slack or 0)
end

-------------------------------------------------------------------------------------------------
-- Engagement (called by the dialog code; also usable by other server code)
-------------------------------------------------------------------------------------------------
-- A player talks to the NPC: it stops, faces them, greets (once in a while) and listens.
function NPC.engage(npcId: string, player: Player, seconds: number?)
	local st = npcs[npcId]
	if not st or st.hidden then
		return
	end
	local now = os.clock()
	halt(st)
	if st.move and st.move.stage == "walk" then
		st.move.stage = "reroute" -- on its way somewhere: goes on from here after the talk
	end
	st.approach = nil
	local fresh = st.talker ~= player
	st.talker = player
	st.talkUntil = now + (seconds or 180)
	if fresh then
		st.talkStart = now
		st.nextTalk = now + 0.6
	end
	setAttr(st, "NpcTalk", player.UserId)
	look(st, player)
	local pos = Util.rootPosition(player)
	if pos then
		faceToward(st, pos, 4)
	end
	if fresh then
		local last = st.noticed[player]
		if not last or now - last > 20 then
			emote(st, st.spec.greet or "wave")
		end
		st.noticed[player] = now
	end
	setAct(st, "listen")
	st.talkActUntil = 0
end

-- The NPC says a line: talk gestures for a while (by the length of the text), then listens.
local function spoke(npcId: string, text: string?, hint: string?)
	local st = npcs[npcId]
	if not st or st.hidden or not st.talker then
		return
	end
	local n = if text then utf8.len(text) or #text else 20
	st.talkActUntil = os.clock() + math.clamp(1.2 + n / 18, 1.5, 6)
	setAct(st, "talk")
	if hint and HINT_EMOTE[hint] then
		emote(st, HINT_EMOTE[hint])
	end
end

function NPC.disengage(npcId: string, player: Player?, bye: boolean?)
	local st = npcs[npcId]
	if not st or (player and st.talker ~= player) then
		return
	end
	st.talker = nil
	st.talkActUntil = 0
	setAttr(st, "NpcTalk", 0)
	if bye then
		emote(st, "wave")
	end
	st.attendUntil = os.clock() + 2.5
	st.waitUntil = math.max(st.waitUntil, os.clock() + 3)
	local s = st.spots[st.cur]
	setAct(st, if st.cur == 1 or not s then homeAct(st) else s.act)
end

-- 어깨빵 landed on a key NPC (Bump.luau decided the outcome): every client plays the fall from the
-- NpcKnock attribute (GwangalliNPCClient); the NPC halts, then reacts.
function NPC.knock(npcId: string, dx: number, dz: number, outcome: string, _player: Player?)
	local st = npcs[npcId]
	if not st or st.hidden then
		return false
	end
	local now = os.clock()
	halt(st)
	if st.move and st.move.stage == "walk" then
		st.move.stage = "reroute"
	end
	local down = outcome == "knockdown"
	setAttr(st, "NpcKnock", string.format("%.2f|%.3f|%.3f|%s", serverNow(), dx, dz, if down then "knockdown" else "stagger"))
	st.waitUntil = math.max(st.waitUntil, now + (if down then 3.2 else 1.6))
	st.attendUntil = now + (if down then 4 else 2.5)
	task.delay(if down then 2.4 else 1.0, function()
		if npcs[npcId] == st and not st.hidden then
			emote(st, if down then "shake" else "stop_hand")
		end
	end)
	return true
end

-- One-shot reaction (visible to everyone nearby).
function NPC.react(npcId: string, name: string?)
	local st = npcs[npcId]
	if st then
		emote(st, name)
	end
end

-------------------------------------------------------------------------------------------------
-- Behaviour tick
-------------------------------------------------------------------------------------------------
type Near = { player: Player, pos: Vector3, seated: boolean }

-------------------------------------------------------------------------------------------------
-- Daily life: where the schedule wants each NPC, the post anchors, and the moves between posts
-------------------------------------------------------------------------------------------------
local Shared: any = nil
local sharedTried = false

local function clockNow(): number
	local ok, env = pcall(ctx.env)
	return if ok and env and type(env.clock) == "number" then env.clock % 24 else 12
end

local function inWindow(c: number, a: number, b: number): boolean
	if a <= b then
		return c >= a and c < b
	end
	return c >= a or c < b
end

local function scheduleOf(st: St): { { any } }?
	local s = SCHEDULE[st.id]
	if s then
		return s
	end
	if st.sched then
		return st.sched
	end
	local c = st.street and Citizens and Citizens.byId and Citizens.byId[st.id]
	if c and type(c.hours) == "table" and type(c.hours[1]) == "number" and type(c.hours[2]) == "number" then
		st.sched = { { c.hours[2], c.hours[1], "off" } } -- roster working hours: off outside them
		return st.sched
	end
	return nil
end

-- A friend somebody is on the way to meet (the 치맥 offer: "나 거기 있을게!") waits at the day post.
local function heldHome(st: St): boolean
	if st.street or type(ctx.meetPending) ~= "function" then
		return false
	end
	for _, p in Players:GetPlayers() do
		local ok, yes = pcall(ctx.meetPending, p, st.id)
		if ok and yes then
			return true
		end
	end
	return false
end

local function wantedPost(st: St, clock: number): string
	if heldHome(st) then
		return "home"
	end
	local s = scheduleOf(st)
	if s then
		for _, w in s do
			if inWindow(clock, w[1], w[2]) then
				local post = w[3]
				if post ~= "home" and post ~= "off" and (st.postFail[post] or 0) > os.clock() then
					-- that post cannot be placed right now (its spot is still being searched): stay put
					return if st.move then st.move.to else st.post
				end
				return post
			end
		end
	end
	return "home"
end

local function nearestPlayer(p: Vector3, list: { Near }): number
	local best = math.huge
	for _, q in list do
		local d = (q.pos - p).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end

local function walkLight(sig: string, phase: number): boolean
	if not sharedTried then
		sharedTried = true
		Shared = optional("GwangalliShared")
	end
	if not Shared or type(Shared.pedState) ~= "function" then
		return true
	end
	local ok, s = pcall(Shared.pedState, sig, phase, serverNow())
	return not ok or s == "walk"
end

-- Standing spot near `p` (feet on a floor within 1.6 of refY, head room, away from `avoid` points).
local function standAt(p: Vector3, refY: number, rp: RaycastParams, op: OverlapParams, avoid: { Vector3 }, gap: number): Vector3?
	local y = floorY(Vector3.new(p.X, refY, p.Z), rp)
	if not y or math.abs(y - refY) > 1.6 then
		return nil
	end
	local f = Vector3.new(p.X, y, p.Z)
	for _, q in avoid do
		if flat(q - f).Magnitude < gap then
			return nil
		end
	end
	if not roomAt(f, op) then
		return nil
	end
	return f
end

-- Two facing slots: the first valid candidate and a neighbour 2.3 studs away.
local function pairAt(cands: { Vector3 }, refY: number, dirs: { Vector3 }, avoid: { Vector3 }, gap: number): any?
	local rp, op = queryParams()
	for k, c in cands do
		if k % 4 == 0 then
			task.wait() -- (runs in a background thread: a few candidates per frame)
		end
		local f1 = standAt(c, refY, rp, op, avoid, gap)
		if f1 then
			for _, dir in dirs do
				local f2 = standAt(f1 + dir * 2.3, f1.Y, rp, op, avoid, gap)
				if f2 and clearLine(f1, f2, rp) then
					return { { pos = f1, yaw = yawOf(flat(f2 - f1)) }, { pos = f2, yaw = yawOf(flat(f1 - f2)) } }
				end
			end
		end
	end
	return nil
end

-- The club's own rigs (build-time crowd, door staff) and the other key NPCs' posts: keep clear.
local function clubAvoid(): { Vector3 }
	local out: { Vector3 } = {}
	local CS = game:GetService("CollectionService")
	local ok, list = pcall(CS.GetTagged, CS, "ClubNPC")
	if ok then
		for _, m in list do
			local p: Vector3? = nil
			if m:IsA("Model") then
				local okP, cf = pcall(m.GetPivot, m)
				if okP then
					p = cf.Position
				else
					local pp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
					p = pp and pp.Position
				end
			elseif m:IsA("BasePart") then
				p = m.Position
			end
			if p then
				table.insert(out, p)
			end
		end
	end
	for _, o in order do
		if not PAIR_SLOT[o.id] and o.day then
			table.insert(out, o.day.home)
		end
	end
	return out
end

-- CLUB OCEAN forecourt: beside the door staff on the far side from the queue lane.
local function findClubFront(): any?
	local dp = ctx.dest("CLUB OCEAN 광안")
	if not dp then
		return nil
	end
	local look = Util.flatLook(dp.CFrame)
	local right = look:Cross(Vector3.yAxis)
	local g = Util.groundOf(dp)
	local cands = {}
	for _, o in { { 10.5, 1.5 }, { 11.5, -1 }, { 9.5, 4 }, { 12.5, 3 }, { 13, 0.5 }, { 8.5, -2.5 }, { 14.5, -1.5 }, { 15.5, 2 }, { -5, 6 }, { -7, 4.5 } } do
		table.insert(cands, g + right * o[1] + look * o[2])
	end
	return pairAt(cands, g.Y, { right, -right, look, -look }, clubAvoid(), 2.6)
end

-- CLUB OCEAN main hall: between the main bar and the LED floor (else the bar's entrance side).
local function findClubIn(): any?
	local CS = game:GetService("CollectionService")
	local venue = CS:GetTagged("ClubVenue")[1]
	local bar = venue and venue:FindFirstChild("MainBar", true)
	local tiles = CS:GetTagged("ClubFloorTile")
	if not bar or #tiles == 0 then
		return nil
	end
	local fc = Vector3.zero
	for _, t in tiles do
		fc += (t :: BasePart).Position
	end
	fc /= #tiles
	local bmin, bmax = Vector3.new(math.huge, 0, math.huge), Vector3.new(-math.huge, 0, -math.huge)
	local barParts = {}
	for _, p in bar:GetDescendants() do
		if p:IsA("BasePart") then
			local q = p.Position
			bmin = Vector3.new(math.min(bmin.X, q.X), 0, math.min(bmin.Z, q.Z))
			bmax = Vector3.new(math.max(bmax.X, q.X), 0, math.max(bmax.Z, q.Z))
			table.insert(barParts, q)
		end
	end
	if #barParts == 0 then
		return nil
	end
	local bc = Vector3.new((bmin.X + bmax.X) / 2, fc.Y, (bmin.Z + bmax.Z) / 2)
	local toF = flat(fc - bc)
	if toF.Magnitude < 1 then
		return nil
	end
	toF = toF.Unit
	local side = toF:Cross(Vector3.yAxis)
	local barNear, barFar, tileNear = math.huge, -math.huge, math.huge
	for _, q in barParts do
		local s = flat(q - bc):Dot(toF)
		barNear, barFar = math.min(barNear, s), math.max(barFar, s)
	end
	for _, t in tiles do
		tileNear = math.min(tileNear, flat((t :: BasePart).Position - bc):Dot(toF) - 1.2)
	end
	local list = {}
	local want = tileNear - 3.5
	local s = barFar + 2.5
	while s <= tileNear - 1.8 do
		for _, lat in { 0, 3, -3, 6, -6, 9, -9 } do
			table.insert(list, { p = bc + toF * s + side * lat, score = math.abs(s - want) + 0.5 * math.abs(lat) })
		end
		s += 1.5
	end
	for _, back in { 4, 6, 8, 10 } do
		for _, lat in { 0, 3, -3, 6, -6 } do
			table.insert(list, { p = bc + toF * (barNear - back) + side * lat, score = 20 + back + 0.5 * math.abs(lat) })
		end
	end
	table.sort(list, function(a, b)
		return a.score < b.score
	end)
	local cands = {}
	for _, e in list do
		table.insert(cands, e.p)
	end
	return pairAt(cands, fc.Y, { side, -side, toF, -toF }, clubAvoid(), 2.4)
end

-- Post anchors are searched once, in the background (the search yields between candidates, so
-- no frame pays for it): (anchor | nil, busy).
local anchors: { [string]: any } = {}
local anchorRetry: { [string]: number } = {}
local anchorBusy: { [string]: boolean } = {}
local function anchorFor(where: string): (any?, boolean)
	local a = anchors[where]
	if a then
		return a, false
	end
	if anchorBusy[where] then
		return nil, true
	end
	if (anchorRetry[where] or 0) > os.clock() then
		return nil, false
	end
	anchorBusy[where] = true
	task.spawn(function()
		local ok, res = pcall(if where == "club_front" then findClubFront else findClubIn)
		anchorBusy[where] = nil
		if ok and res then
			anchors[where] = res
		else
			anchorRetry[where] = os.clock() + 15
			if not ok then
				warn("[GwangalliGameplay] npc post " .. where .. " failed: " .. tostring(res))
			end
		end
	end)
	return nil, anchorBusy[where] == true
end

-- Where a post puts this NPC: feet, facing (nil for "off" or a post that cannot be placed; busy =
-- its spot is still being searched).
local function targetOf(st: St, post: string): (Vector3?, number?, boolean)
	if post == "home" then
		return st.day.home, st.day.homeYaw, false
	end
	local ps = POSTS[post]
	if not ps then
		return nil, nil, false
	end
	if ps.where == "rel" then
		return st.day.home, st.day.homeYaw, false
	end
	local a, busy = anchorFor(ps.where)
	if not a then
		return nil, nil, busy
	end
	local slot = a[PAIR_SLOT[st.id] or 1] or a[1]
	return slot.pos, slot.yaw, false
end

local function clubDoor(): Vector3?
	local N = nav()
	local p = N and N.places and N.places.club_door
	if p and type(p.x) == "number" then
		return Vector3.new(p.x, p.y, p.z)
	end
	return nil
end

local function edgeOf(c: any, a: number, b: number): number?
	local l = c.adj[a]
	for k = 1, #l, 2 do
		if l[k] == b then
			return l[k + 1]
		end
	end
	return nil
end

-- The walk from `from` to `to` along the pedestrian graph, cut into chunks at signalised crossings
-- ({ pts, wait = { sig, ph, across }? }); crossings follow the asphalt (0.5 below the kerbs).
local function routeChunks(from: Vector3, to: Vector3): { any }?
	local N = nav()
	if not N or type(N.route) ~= "function" or type(N.nearest) ~= "function" then
		return nil
	end
	local c = N.decode()
	local a, b = N.nearest(from, 40), N.nearest(to, 40)
	if not a or not b then
		return nil
	end
	local nodes = if a == b then { a } else N.route(a, b, false)
	if not nodes or #nodes == 0 then
		return nil
	end
	-- the NPC starts / ends between two nodes: skip a first node behind it and a last one beyond
	if #nodes >= 2 and flat(c.pos[nodes[2]] - from).Magnitude <= flat(c.pos[nodes[2]] - c.pos[nodes[1]]).Magnitude then
		table.remove(nodes, 1)
	end
	if #nodes >= 2 and flat(c.pos[nodes[#nodes - 1]] - to).Magnitude <= flat(c.pos[nodes[#nodes - 1]] - c.pos[nodes[#nodes]]).Magnitude then
		table.remove(nodes)
	end
	local KX = N.KIND and N.KIND.xwalk
	local KG = N.KIND and N.KIND.xing
	local chunks = {}
	local cur = { from }
	for k, n in nodes do
		local p = c.pos[n]
		table.insert(cur, p)
		local nxt = nodes[k + 1]
		local e = nxt and edgeOf(c, n, nxt)
		if e then
			local _, _, _, kind = N.pedEdge(e)
			local isX, sig, ph = N.crossing(e)
			if isX and sig then
				table.insert(chunks, { pts = cur, wait = { sig = sig, ph = ph, across = c.pos[nxt] } })
				cur = { p }
			end
			if kind == KX or kind == KG then
				local q = c.pos[nxt]
				local d = q - p
				local len = d.Magnitude
				if len > 3 then
					table.insert(cur, p + d * (1.2 / len) - Vector3.new(0, 0.5, 0))
					table.insert(cur, q - d * (1.2 / len) - Vector3.new(0, 0.5, 0))
				end
			end
		end
	end
	table.insert(cur, to)
	table.insert(chunks, { pts = cur })
	return chunks
end

local function routeLength(chunks: { any }): number
	local len = 0
	for _, c in chunks do
		for k = 2, #c.pts do
			len += (c.pts[k] - c.pts[k - 1]).Magnitude
		end
	end
	return len
end

-- A pedestrian nav node minR..maxR from `center` on its level and out of every player's sight
-- (SEEN_R): where an NPC appears from / walks off to. The nearest such node with a sensible walk
-- (the route no longer than twice the distance) wins. Scans the flat node array (numbers only).
local function hiddenNode(center: Vector3, minR: number, maxR: number, list: { Near }): Vector3?
	local N = nav()
	local P = N and N.ped
	if not P or type(P.pos) ~= "table" then
		return nil
	end
	local pos = P.pos
	local cx, cy, cz = center.X, center.Y, center.Z
	local lo, hi = minR * minR, maxR * maxR
	local pl = {}
	for _, q in list do
		table.insert(pl, { q.pos.X, q.pos.Y, q.pos.Z })
	end
	local seen2 = SEEN_R * SEEN_R
	local cands = {}
	for i = 1, P.n do
		local k = (i - 1) * 3
		local x, y, z = pos[k + 1], pos[k + 2], pos[k + 3]
		local dx, dz = x - cx, z - cz
		local d2 = dx * dx + dz * dz
		if d2 >= lo and d2 <= hi and math.abs(y - cy) < 1.5 then
			local ok = true
			for _, q in pl do
				local ex, ey, ez = x - q[1], y - q[2], z - q[3]
				if ex * ex + ey * ey + ez * ez < seen2 then
					ok = false
					break
				end
			end
			if ok then
				table.insert(cands, { x = x, y = y, z = z, d2 = d2 })
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.d2 < b.d2
	end)
	for k = 1, math.min(#cands, 3) do
		local e = cands[k]
		local p = Vector3.new(e.x, e.y, e.z)
		local chunks = routeChunks(p, center)
		if chunks and routeLength(chunks) <= math.sqrt(e.d2) * 2 + 15 then
			return p
		end
	end
	return nil
end

local function hideNpc(st: St)
	st.hidden = true
	st.leg = nil
	st.approach = nil
	st.returnTo = nil
	st.model.Parent = nil
	for _, e in st.extras do
		e.Parent = nil
	end
end

local function showNpc(st: St)
	st.hidden = false
	st.model.Parent = ensureFolder()
	for _, e in st.extras do
		e.Parent = folder
	end
end

-- Makes `post` the NPC's current post (its spots, home, routine fields).
local function setupPost(st: St, post: string, feet: Vector3?, yaw: number?)
	if post == "home" or post == "off" or not POSTS[post] then
		local d = st.day
		st.pspec = nil
		st.home, st.homeYaw, st.spots, st.floorless, st.legOk = d.home, d.homeYaw, d.spots, d.floorless, d.legOk
	else
		local ps = POSTS[post]
		local f = feet or st.day.home
		local y = yaw or st.day.homeYaw
		st.pspec = ps
		st.home, st.homeYaw, st.floorless, st.legOk = f, y, false, {}
		local hf = CFrame.new(f) * yawCF(y)
		local spots = {}
		for i, s in ps.spots do
			local p = (hf * CFrame.new(s[1], 0, -s[2])).Position
			table.insert(spots, { pos = if i == 1 then f else p, yaw = y + (s.yaw or 0), act = s[3] or "idle", w = s.w, emote = s.emote, checked = i == 1, ok = i == 1 })
		end
		st.spots = spots
	end
	st.cur = 1
	st.offPath = false
	st.returnTo = nil
	st.post = post
	setAttr(st, "NpcPost", post)
end

-- Lands the move at once: at the target post (shown), or gone ("off").
local function finishMove(st: St)
	local mv = st.move
	st.move = nil
	if not mv then
		return
	end
	if mv.to == "off" then
		hideNpc(st)
		setupPost(st, "off", nil, nil)
		return
	end
	setupPost(st, mv.to, mv.target, mv.yaw)
	place(st, mv.target, mv.yaw)
	setAct(st, homeAct(st))
	if st.hidden then
		showNpc(st)
	end
	st.waitUntil = os.clock() + 3 + math.random() * 3
	st.nextIdle = os.clock() + 6 + math.random() * 8
end

local function beginMove(st: St, want: string)
	local target, yaw, busy = targetOf(st, want)
	if want ~= "off" and not target then
		st.postFail[want] = os.clock() + (if busy then 1.5 else 20) -- stays where it is for now
		return
	end
	if st.leg then
		halt(st)
	end
	st.approach, st.returnTo, st.offerUntil, st.pointAt = nil, nil, 0, 0
	local act = if not st.street and math.random() < 0.35 then "phone" else "idle"
	st.move = { to = want, target = target, yaw = yaw, stage = "start", t0 = os.clock(), act = act, holdUntil = 0 }
	-- friends heading the same way at the same time: the second one sets off a moment later
	local partner = st.spec.faceTo and npcs[st.spec.faceTo]
	if partner and partner.id < st.id and partner.move and partner.move.to == want and os.clock() - partner.move.t0 < 3 then
		st.move.holdUntil = os.clock() + 2.4
	end
end

-- One tick of a move. Returns true while the move owns the NPC.
local function stepMove(st: St, now: number, list: { Near }): boolean
	local mv = st.move
	if not mv then
		return false
	end
	local here = currentPos(st)
	-- nobody near the NPC nor near where it goes: done at once
	if mv.stage ~= "inside" and (st.hidden or nearestPlayer(here, list) > SKIP_R) and (mv.target == nil or nearestPlayer(mv.target, list) > SKIP_R) then
		finishMove(st)
		return true
	end
	if mv.stage == "start" or mv.stage == "reroute" then
		if mv.stage == "start" and now < (mv.holdUntil or 0) and not st.hidden then
			return true
		end
		if mv.stage == "start" and not st.hidden and mv.target and flat(mv.target - here).Magnitude > 130 and nearestPlayer(here, list) > SKIP_R then
			hideNpc(st) -- nobody sees it leave: it comes in near where it goes instead (below)
			mv.rehid = true
		end
		if mv.stage == "start" then
			if st.hidden then
				-- coming back on duty: in from a nav node out of sight (inside the club: straight in)
				if mv.to == "club_in" or (mv.target and (mv.target - st.day.home).Magnitude < 1 and POSTS[mv.to] and POSTS[mv.to].where == "rel") then
					if nearestPlayer(mv.target, list) > 30 or now - mv.t0 > 30 then
						finishMove(st)
					end
					return true
				end
				if now < (mv.nextTry or 0) then
					return true
				end
				local from = hiddenNode(mv.target, 45, 110, list)
				if not from then
					mv.nextTry = now + 2 -- everything around is in view: look again in a moment
					if now - mv.t0 > 40 then
						finishMove(st)
					end
					return true
				end
				place(st, from, yawOf(flat(mv.target - from)))
				showNpc(st)
				here = from
			elseif st.post == "club_in" and mv.to ~= "club_in" then
				-- out of the hall through the front door
				local door = clubDoor()
				if door then
					hideNpc(st)
					place(st, door, st.yaw)
					showNpc(st)
					here = door
				end
			end
		end
		local goal: Vector3? = mv.target
		if mv.to == "club_in" then
			goal = if st.post == "club_in" then mv.target else clubDoor()
		elseif mv.to == "off" then
			goal = mv.exit or hiddenNode(here, 45, 90, list)
			mv.exit = goal
		end
		if not goal then
			mv.stage = "vanish"
			mv.untilT = now + 30
			return true
		end
		local chunks: { any }? = nil
		if flat(goal - here).Magnitude < 25 then
			local rp = queryParams()
			if clearLine(here, goal, rp) then
				chunks = { { pts = { here, goal } } } -- a few steps: straight there
			end
		end
		chunks = chunks or routeChunks(here, goal)
		if not chunks and flat(goal - here).Magnitude < 30 then
			chunks = { { pts = { here, goal } } }
		end
		if not chunks then
			finishMove(st) -- no way to walk it: lands when it can be (the skip rule) or now
			return true
		end
		mv.chunks, mv.ci, mv.wait, mv.pending, mv.stage = chunks, 1, nil, nil, "walk"
		setAct(st, mv.act)
		return true
	end
	if mv.stage == "walk" then
		if mv.target and not mv.rehid and flat(mv.target - here).Magnitude > 130 and nearestPlayer(here, list) > SKIP_R then
			-- a long way still to go where nobody sees it, somebody near where it goes: comes in near there
			mv.rehid = true
			if st.leg then
				halt(st)
			end
			hideNpc(st)
			mv.stage = "start"
			return true
		end
		if st.leg then
			return true
		end
		if mv.pending then
			-- at the kerb: the crossing starts with the walk light
			mv.wait = { sig = mv.pending.sig, ph = mv.pending.ph, across = mv.pending.across, giveUp = now + 75 }
			mv.pending = nil
		end
		if mv.wait then
			if walkLight(mv.wait.sig, mv.wait.ph) or now > mv.wait.giveUp then
				mv.wait = nil
			else
				faceToward(st, mv.wait.across, 12)
				setAct(st, "idle")
				return true
			end
		end
		local chunk = mv.chunks[mv.ci]
		if not chunk then
			if mv.to == "club_in" and st.post ~= "club_in" then
				hideNpc(st) -- in through the door
				mv.stage = "inside"
				mv.untilT = now + 1.5
			elseif mv.to == "off" then
				mv.stage = "vanish"
				mv.untilT = now + 30
				setAct(st, "phone")
			else
				finishMove(st)
			end
			return true
		end
		local pts = table.clone(chunk.pts)
		pts[1] = here
		startPath(st, pts, TRANSIT_SPEED)
		setAct(st, mv.act)
		mv.ci += 1
		mv.pending = chunk.wait
		return true
	end
	if mv.stage == "inside" then
		if now >= mv.untilT then
			finishMove(st)
		end
		return true
	end
	if mv.stage == "vanish" then
		-- walks off once nobody is close enough to watch (at the latest after half a minute)
		if nearestPlayer(here, list) > 40 or now >= mv.untilT then
			finishMove(st)
		end
		return true
	end
	finishMove(st)
	return true
end

-- Every couple of seconds: start / redirect moves toward the post the clock wants.
local function scheduleTick(list: { Near })
	local clock = clockNow()
	for _, st in order do
		if not st.talker and st.day then
			local want = wantedPost(st, clock)
			local cur = if st.move then st.move.to else st.post
			if want ~= cur then
				if st.move then
					local mv = st.move
					if mv.stage == "inside" then
						finishMove(st)
					else
						st.move = nil
						if mv.stage ~= "start" and st.leg then
							halt(st)
						end
					end
				end
				beginMove(st, want) -- (also when it is back to the post it left: walks back along the nav)
			end
		end
	end
	local _ = list
end

-- The club posts' spots are searched a few seconds after start (background), long before dusk.
local function prefetchAnchors()
	for _, ps in POSTS do
		if ps.where ~= "rel" then
			anchorFor(ps.where)
		end
	end
end

scheduleNow = function(st: St)
	local want = wantedPost(st, clockNow())
	if want ~= st.post then
		beginMove(st, want)
		if st.move then
			finishMove(st)
		end
	end
end


local function arrive(st: St)
	local leg = st.leg
	st.leg = nil
	st.pos = leg.to
	if leg.poly then
		-- a walk between posts: face the way the last segment went (the move logic goes on from here)
		local pts = leg.poly.pts
		local d = flat(pts[#pts] - pts[#pts - 1])
		if d.Magnitude > 0.05 then
			st.yaw = yawOf(d)
			setAttr(st, "NpcYaw", math.floor(st.yaw * 10 + 0.5) / 10)
		end
		writeRoot(st)
		return
	end
	local s = leg.spot and st.spots[leg.spot]
	if leg.spot then
		st.cur = leg.spot
	end
	if st.approach then
		-- promoter reached a player: offer the flyer
		local p = st.approach
		st.approach = nil
		local pos = p.Parent == Players and Util.rootPosition(p)
		if pos then
			st.yaw = yawOf(flat(pos - st.pos))
			setAttr(st, "NpcYaw", math.floor(st.yaw * 10 + 0.5) / 10)
			look(st, p)
			emote(st, st.spec.greet or "wave")
			setAct(st, "flyers")
			st.offerUntil = os.clock() + 4.5
			st.noticed[p] = os.clock()
			if R(st, "pointTo") then
				st.pointAt = os.clock() + 2.4
			end
		end
		writeRoot(st)
		st.waitUntil = os.clock() + 5
		return
	end
	if s then
		st.yaw = s.yaw
		setAttr(st, "NpcYaw", math.floor(st.yaw * 10 + 0.5) / 10)
		setAct(st, if leg.spot == 1 then homeAct(st) else s.act)
		if s.emote then
			emote(st, s.emote)
		end
		local w = s.w or { 5, 11 }
		st.waitUntil = os.clock() + w[1] + math.random() * (w[2] - w[1])
	else
		st.waitUntil = os.clock() + 4
	end
	writeRoot(st)
end

local function nextSpot(st: St)
	if st.returnTo then
		-- back from walking up to a player, along the same (checked) line
		local r = st.returnTo
		st.returnTo = nil
		st.offPath = false
		startLeg(st, r.pos, nil, if r.idx >= 1 then r.idx else 1)
		return
	end
	if st.offPath then
		st.offPath = false
		if st.cur ~= 1 or flat(st.pos - st.home).Magnitude > 0.5 then
			startLeg(st, st.home, nil, 1)
			return
		end
	end
	local n = #st.spots
	if n <= 1 then
		setAct(st, homeAct(st))
		st.waitUntil = os.clock() + 10
		return
	end
	local mode = R(st, "order") or "random"
	local target: number
	if mode == "cycle" then
		target = st.cur % n + 1
	elseif mode == "pace" then
		st.seq += 1
		target = if st.seq % 2 == 1 then 1 + ((st.seq // 2) % (n - 1)) + 1 else 1
		if st.cur == target then
			target = 1
		end
	else
		if st.cur ~= 1 then
			target = 1
		else
			target = math.random(2, n)
		end
	end
	if target ~= 1 and not validSpot(st, target) then
		target = 1
	end
	if target ~= 1 and not legClear(st, st.cur, target) then
		target = 1
	end
	if target == st.cur then
		-- nowhere to go: a new act on the spot for a while
		local s = st.spots[target]
		setAct(st, if target == 1 then homeAct(st) else s.act)
		st.waitUntil = os.clock() + 6 + math.random() * 6
		return
	end
	startLeg(st, st.spots[target].pos, nil, target)
end

local function tryApproach(st: St, p: Near): boolean
	local toNpc = flat(st.pos - p.pos)
	local d = toNpc.Magnitude
	if d < 4.5 then
		return false
	end
	local target = p.pos + (if d > 0.1 then toNpc.Unit else Vector3.xAxis) * 3.4
	if flat(target - st.home).Magnitude > (st.spec.nav or 12) + 4 then
		return false
	end
	local rp = queryParams()
	local y = floorY(target, rp) or st.pos.Y
	if math.abs(y - st.pos.Y) > 2.5 then
		return false
	end
	target = Vector3.new(target.X, y, target.Z)
	if not clearLine(st.pos, target, rp) then
		return false
	end
	st.approach = p.player
	st.returnTo = { pos = st.pos, idx = st.cur }
	startLeg(st, target, (st.spec.speed or WALK_SPEED) * 1.1, nil)
	st.cur = 0
	return true
end

local function think(st: St, now: number, nearList: { Near })
	if st.hidden then
		if st.move then
			stepMove(st, now, nearList) -- coming back on duty
		end
		return
	end
	if st.leg and now >= st.leg.arrive then
		arrive(st)
	end
	if st.pendingRoot and not st.leg and now - st.lastRootWrite > 1 then
		writeRoot(st)
	end
	-- dialog partner
	local talker = st.talker
	if talker then
		local tp = talker.Parent == Players and Util.rootPosition(talker)
		if not tp or (tp - st.pos).Magnitude > TALK_REACH or now > st.talkUntil then
			NPC.disengage(st.id, talker, false)
			talker = nil
		else
			if st.leg then
				halt(st)
			end
			faceToward(st, tp, 25)
			if st.talkActUntil > 0 and now > st.talkActUntil then
				st.talkActUntil = 0
				setAct(st, "listen")
			end
			if st.street then
				-- Relationships runs this conversation: keep engaged while they stay close, and
				-- alternate talking / listening gestures
				if (tp - st.pos).Magnitude < 9 then
					st.talkUntil = math.min(math.max(st.talkUntil, now + 8), st.talkStart + 150)
				end
				if st.talkActUntil == 0 and now > st.nextTalk then
					st.talkActUntil = now + 2 + math.random() * 1.5
					st.nextTalk = st.talkActUntil + 2.5 + math.random() * 2
					setAct(st, "talk")
				end
			end
			return
		end
	end
	-- on the way to another post: a glance and a wave at players close by, no stopping
	if st.move then
		local near: Near? = nil
		local nd = NOTICE_R
		local at = currentPos(st)
		for _, p in nearList do
			local d = (p.pos - at).Magnitude
			if d < nd then
				near, nd = p, d
			end
		end
		look(st, near and near.player or nil)
		if near and nd < GREET_R then
			local last = st.noticed[near.player]
			if not last or now - last > GREET_AGAIN then
				st.noticed[near.player] = now
				emote(st, st.spec.greet or "wave")
			end
		end
		stepMove(st, now, nearList)
		local leg = st.leg
		if leg and leg.poly and now - st.lastRootWrite > 1 then
			-- the server copy follows a long walk (prompt / social reach checks read it)
			local a = math.clamp((serverNow() - leg.t0) / leg.dur, 0, 1)
			local p, dir = polyAt(leg.poly, a * leg.poly.total)
			local y = if dir and flat(dir).Magnitude > 0.05 then yawOf(flat(dir)) else st.yaw
			st.root.CFrame = CFrame.new(p + Vector3.new(0, st.ground, 0)) * yawCF(y)
			st.lastRootWrite = now
		end
		return
	end
	-- a promoter shows the way to the club after handing over the flyer
	if st.pointAt > 0 and now >= st.pointAt and not st.leg then
		st.pointAt = 0
		local pt = R(st, "pointTo")
		local dp = pt and ctx.dest(pt)
		if dp and flat(dp.Position - st.pos).Magnitude > 8 then
			faceToward(st, dp.Position, 5)
			emote(st, "point")
			st.attendUntil = now + 2.2
			st.waitUntil = math.max(st.waitUntil, now + 3)
			return
		end
	end
	-- nearest player
	local best: Near? = nil
	local bestD = math.huge
	for _, p in nearList do
		local d = (p.pos - st.pos).Magnitude
		if d < bestD then
			best, bestD = p, d
		end
	end
	-- a promoter walking up to someone
	if st.approach then
		local ap = st.approach
		local still = false
		for _, p in nearList do
			if p.player == ap and (p.pos - st.pos).Magnitude < 22 then
				still = true
			end
		end
		if not still then
			st.approach = nil
			halt(st)
			st.waitUntil = now + 2
		end
		return
	end
	-- promoters walk up to players passing by (within 22 studs, once per 150 s each)
	if st.spec.approach and best and bestD >= GREET_R and bestD < 22 and not best.seated and not st.leg and now > st.offerUntil and now > st.nextApproach then
		local last = st.noticed[best.player]
		if not last or now - last > 150 then
			if tryApproach(st, best) then
				st.noticed[best.player] = now -- one walk-up per player per 150 s, arrived or not
				look(st, best.player)
				return
			end
			st.nextApproach = now + 3 -- no clear way there: look again in a moment
		end
	end
	if best and bestD < NOTICE_R and not best.seated then
		local pl = best.player
		local last = st.noticed[pl]
		if bestD < GREET_R and (not last or now - last > GREET_AGAIN) then
			st.noticed[pl] = now
			if st.spec.keepAct then
				emote(st, st.spec.greet or "nod")
			else
				if st.leg then
					halt(st)
				end
				faceToward(st, best.pos, 4)
				emote(st, st.spec.greet or "wave")
				st.attendUntil = now + 3.5
				if st.spec.approach then
					setAct(st, "flyers")
					st.offerUntil = now + 4
					if R(st, "pointTo") then
						st.pointAt = now + 2.4
					end
				end
			end
		end
		look(st, pl)
		if now < st.attendUntil then
			faceToward(st, best.pos, 20)
			return
		end
		if bestD < STAY_R then
			if st.leg then
				halt(st)
				setAct(st, st.spots[st.cur] and st.spots[st.cur].act or homeAct(st))
			end
			st.waitUntil = math.max(st.waitUntil, now + 1.5)
			return
		end
	else
		look(st, nil)
		-- calling out to passers-by
		if st.spec.call and best and bestD < 26 and not best.seated and now > st.nextCall and not st.leg then
			st.nextCall = now + 14 + math.random() * 12
			faceToward(st, best.pos, 30)
			emote(st, st.spec.call)
			st.attendUntil = now + 2.5
			st.waitUntil = math.max(st.waitUntil, now + 2.5)
			return
		end
	end
	if st.leg then
		return
	end
	-- attention over: back to the spot's facing (friends at their meeting spot face each other)
	local spot = st.spots[st.cur]
	local partner = st.spec.faceTo and npcs[st.spec.faceTo]
	local together = partner ~= nil and st.cur == 1 and not partner.hidden and not partner.leg and partner.move == nil and partner.post == st.post and partner.cur == 1 and partner.talker == nil and flat(partner.pos - st.pos).Magnitude < 10
	if spot and now > st.attendUntil and (not best or bestD > STAY_R) then
		if together and partner then
			faceToward(st, partner.pos, 6)
		else
			setYaw(st, spot.yaw)
		end
	end
	-- ... and take turns talking (the one with the smaller id leads the turns)
	if together and partner and st.id < partner.id and now > st.nextSwap and not (st.pspec and st.pspec.turns == false) then
		st.nextSwap = now + 5 + math.random() * 5
		local iTalk = st.act ~= "chat"
		setAct(st, if iTalk then "chat" else "listen")
		setAct(partner, if iTalk then "listen" else "chat")
		if math.random() < 0.35 then
			emote(if iTalk then partner else st, if math.random() < 0.5 then "laugh" else "nod")
		end
	end
	-- idle flourish (laugh with a friend, a nod, a point at the bridge; after dark the friends point
	-- at the club and get in the mood)
	local idleList = if st.pspec then R(st, "idle") else ((isNight() and st.spec.nightIdle) or st.spec.idle)
	if idleList and now > st.nextIdle then
		st.nextIdle = now + 10 + math.random() * 12
		local e = idleList[math.random(1, #idleList)]
		if e == "point" and R(st, "pointTo") then
			st.pointAt = now -- faces the place and points (next tick)
		else
			emote(st, e)
		end
	end
	if now >= st.waitUntil then
		if st.offerUntil > 0 and now > st.offerUntil then
			st.offerUntil = 0
		end
		nextSpot(st)
	end
end

local lastNight: boolean? = nil
local schedT = 0
local function behaviour()
	local now = os.clock()
	local list: { Near } = {}
	for _, p in Players:GetPlayers() do
		local _, hum, root = Util.alive(p)
		if hum and root then
			table.insert(list, { player = p, pos = root.Position - Vector3.new(0, 3, 0), seated = hum.SeatPart ~= nil })
		end
	end
	schedT += TICK
	if schedT >= 2 then
		schedT = 0
		local okS, errS = pcall(scheduleTick, list)
		if not okS then
			warn("[GwangalliGameplay] npc schedule failed: " .. tostring(errS))
		end
	end
	local night = isNight()
	if night ~= lastNight then
		lastNight = night
		for _, st in order do
			if st.spec.night and st.cur == 1 and not st.leg and not st.talker then
				setAct(st, homeAct(st))
			end
		end
	end
	for _, st in order do
		local ok, err = pcall(think, st, now, list)
		if not ok then
			warn("[GwangalliGameplay] npc " .. st.id .. " think failed: " .. tostring(err))
			st.waitUntil = now + 5
		end
	end
	-- forget players who left
	for _, st in order do
		for p in st.noticed do
			if p.Parent ~= Players then
				st.noticed[p] = nil
			end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Dialog nodes
-------------------------------------------------------------------------------------------------
type Node = { text: string, choices: { { id: string, label: string } }, emote: string? }

local function won(n: number): string
	return G.format.won(n)
end

local function employerNode(player: Player, d: any, def: any, sub: string?): Node
	local jobId = def.job
	local job = G.JOBS[jobId]
	local lv = G.jobLevel(jobId, d.careerXp[jobId] or 0)
	local mine = d.job and d.job.id == jobId
	if sub == "info" then
		local lines = {}
		for _, t in (job.tasks or job.cycle or {}) do
			if t.kind ~= "choice" then
				table.insert(lines, "· " .. string.gsub(t.prompt, "%%s", "…"))
			end
		end
		return {
			text = string.format("%s\n%s\n승진: %s", job.desc, table.concat(lines, "\n", 1, math.min(#lines, 3)), (function()
				local names = {}
				for _, l in job.levels do
					table.insert(names, string.format("%s(%s)", l.title, won(l.wage)))
				end
				return table.concat(names, " → ")
			end)()),
			choices = if mine then { { id = "start", label = "근무 시작" }, { id = "bye", label = "알겠어요" } } else { { id = "hire", label = "할게요!" }, { id = "bye", label = "다음에요" } },
		}
	end
	if sub == "status" then
		local xp = d.careerXp[jobId] or 0
		local nxt = G.nextLevelXp(jobId, lv)
		return {
			text = string.format("지금 %s예요. 시급 %s · 경험치 %d%s\n지금까지 근무 %d번!", job.levels[lv].title, won(job.levels[lv].wage), xp, if nxt then string.format(" (다음 승진까지 %d)", nxt - xp) else " (최고 직급!)", d.shifts or 0),
			choices = { { id = "start", label = "근무 시작" }, { id = "bye", label = "고마워요" } },
		}
	end
	if not mine then
		return {
			text = string.format("어서 와요! %s에서 %s 구하고 있는데, 해 볼래요? 시급 %s부터 시작해요.", job.place, job.title, won(job.levels[lv].wage)),
			choices = { { id = "hire", label = "할게요!" }, { id = "info", label = "무슨 일을 해요?" }, { id = "bye", label = "다음에요" } },
		}
	end
	if ctx.onShift(player) then
		return {
			text = "열심히 하고 있네요! 폰에 뜨는 업무를 하나씩 해 주면 돼요 💪",
			choices = { { id = "endshift", label = "오늘은 여기까지 할게요" }, { id = "bye", label = "계속할게요" } },
		}
	end
	return {
		text = string.format("왔어요, %s님? 오늘도 잘 부탁해요! (%s · 시급 %s)", player.DisplayName, job.levels[lv].title, won(job.levels[lv].wage)),
		choices = { { id = "start", label = "근무 시작" }, { id = "status", label = "제 경력은요?" }, { id = "quit", label = "그만둘게요" }, { id = "bye", label = "잠깐 들렀어요" } },
	}
end

local function realtorNode(_player: Player, d: any, sub: string?): Node
	if sub == "list_rent" or sub == "list_buy" then
		local kind = if sub == "list_rent" then "rent" else "buy"
		local choices = {}
		local lines = {}
		for _, id in G.LISTING_ORDER do
			local l = G.LISTINGS[id]
			if l.kind == kind then
				if kind == "rent" then
					table.insert(lines, string.format("%s %s · 보증금 %s · 하루 %s", l.icon, l.name, won(l.deposit), won(l.rentPerDay)))
					table.insert(choices, { id = "rent:" .. id, label = string.format("%s 계약", l.name) })
				else
					table.insert(lines, string.format("%s %s · %s · 관리비 하루 %s", l.icon, l.name, won(l.price), won(l.upkeepPerDay)))
					table.insert(choices, { id = "buy:" .. id, label = string.format("%s 매수", l.name) })
				end
			end
		end
		table.insert(choices, { id = "back", label = "다른 매물" })
		table.insert(choices, { id = "bye", label = "생각해 볼게요" })
		return { text = table.concat(lines, "\n"), choices = choices }
	end
	if sub == "myhome" and d.home then
		local l = G.LISTINGS[d.home.listingId]
		return {
			text = string.format("%s · %s\n하루 %s · 다음 납부까지 %s%s", l.name, if d.home.owned then "자가" else "월세", won(G.homeDaily(d.home.listingId)), G.format.seconds(d.home.dueIn or 0), if (d.home.missed or 0) > 0 then string.format("\n⚠️ 연체 %d일 (%s)", d.home.missed, won(d.home.arrears or 0)) else ""),
			choices = { { id = "back", label = "다른 매물 보기" }, { id = "bye", label = "고마워요" } },
		}
	end
	local choices = { { id = "list_rent", label = "월세 매물 보기" }, { id = "list_buy", label = "매매 매물 보기" } }
	if d.home then
		table.insert(choices, { id = "myhome", label = "내 집 정보" })
	end
	table.insert(choices, { id = "bye", label = "나중에 올게요" })
	return {
		text = if d.home then "또 오셨네요! 더 좋은 집으로 옮기실 때가 됐나요? 😉" else "어서 오세요, 광안역 부동산입니다! 보증금 없는 고시원부터 오션뷰 펜트하우스까지 다 있어요.",
		choices = choices,
	}
end

local function bankerNode(_player: Player, d: any, sub: string?): Node
	if sub == "history" then
		local lines = {}
		local tx = d.transactions or {}
		for i = #tx, math.max(1, #tx - 4), -1 do
			local t = tx[i]
			table.insert(lines, string.format("%s %s%s · %s", if t.account == "cash" then "💵" else "🏦", if t.amount > 0 then "+" else "-", won(math.abs(t.amount)), t.label))
		end
		return { text = if #lines > 0 then table.concat(lines, "\n") else "아직 거래 내역이 없어요.", choices = { { id = "back", label = "돌아가기" }, { id = "bye", label = "고마워요" } } }
	end
	return {
		text = string.format("BNK부산은행입니다 😊\n통장 잔고 %s · 현금 %s\n총자산 %s", won(d.bank), won(d.cash), won(G.netWorth(d))),
		choices = {
			{ id = "deposit_all", label = "현금 전부 입금" },
			{ id = "withdraw_50k", label = "5만원 출금" },
			{ id = "withdraw_200k", label = "20만원 출금" },
			{ id = "history", label = "최근 거래 내역" },
			{ id = "bye", label = "괜찮아요" },
		},
	}
end

local function clubNode(player: Player, d: any): Node
	local hasPass = ctx.hasClubPass(player)
	local vipLabel = { id = "vip", label = string.format("VIP 테이블 잡기 (%s)", won(G.CLUB.vipTable)) }
	if hasPass then
		return { text = "들어가세요! 오늘 물 좋아요 🎶", choices = { vipLabel, { id = "bye", label = "고마워요" } } }
	end
	if ctx.clubInvited(player) then
		return { text = "아, 민지 친구분! 게스트 리스트에 있어요. 바로 입장하세요 😎", choices = { { id = "entry", label = "입장할게요" }, vipLabel, { id = "bye", label = "나중에요" } } }
	end
	if (d.stats.appearance or 0) >= G.CLUB.entryAppearance then
		return { text = "오, 스타일 좋은데요? 입장하세요! 🕺", choices = { { id = "entry", label = "입장할게요" }, vipLabel, { id = "bye", label = "나중에요" } } }
	end
	return {
		text = string.format("음… 오늘 드레스코드가 좀 있어서요. (외모지수 %d 이상 무료) 입장료 %s 내시면 들어가실 수 있어요.", G.CLUB.entryAppearance, won(G.CLUB.cover)),
		choices = { { id = "cover", label = string.format("입장료 내기 (%s)", won(G.CLUB.cover)) }, { id = "bye", label = "꾸미고 다시 올게요" } },
	}
end

local FRIEND_LINES = {
	minji = { "왔어? 오늘 광안리 바다 진짜 예쁘다 🌊", "요즘 일은 할 만해? 무리하지 마~", "나중에 클럽 오션 같이 가자! 🎶" },
	junho = { "오 왔냐! 치맥 각? 🍗", "나 요즘 헬스 다니는데 몸 좋아진 것 같지 않냐 ㅋㅋ", "돈 모아서 광안자이 사는 게 내 꿈이다…" },
}

-- Where the friend is right now changes what they say (the club at night, asleep late at night).
local FRIEND_AT = {
	club_front = {
		here = { "왔어? 오늘 CLUB OCEAN 라인업 대박이래 🎶 태양 오빠한테 말하면 바로 들어가!", "여기 줄 금방 줄어~ 우리 조금 있다 들어갈 거야 😎" },
		phone = "여보세요? 나 지금 CLUB OCEAN 앞이야! 🎶 너도 빨리 와~",
	},
	club_in = {
		here = { "왔구나!! 오늘 음악 미쳤어 🎶 같이 춤추자!", "여기 바 옆이야! 한 잔 하고 놀자 🍹" },
		phone = "여보세요?? 여기 클럽 안이라 잘 안 들려 ㅋㅋ 🎶 너도 와! 바 옆에 있어!",
	},
	off = { phone = "(졸린 목소리) 여보세요…? 나 자고 있었어 ㅋㅋ 내일 광장에서 보자 😴" },
}

local function friendNode(player: Player, _d: any, npcId: string, remote: boolean): Node
	local lines = FRIEND_LINES[npcId] or { "안녕!" }
	local text = lines[math.random(1, #lines)]
	local st = npcs[npcId]
	local post = st and (if st.hidden and not st.move then "off" else st.post) or "home"
	local at = FRIEND_AT[post]
	if ctx.meetPending(player, npcId) and not remote then
		text = "왔구나! 치맥 준비됐다 🍗🍺"
	elseif remote then
		text = if at and at.phone then at.phone else "여보세요? 응 나야! " .. text
	elseif at and at.here then
		text = at.here[math.random(1, #at.here)]
	end
	return { text = text, choices = { { id = "chat", label = "수다 떨기" }, { id = "bye", label = "또 보자!" } } }
end

local function buildNode(player: Player, npcId: string, sub: string?, remote: boolean): Node?
	local def = G.NPCS[npcId]
	local d = Profiles.get(player)
	if not def or not d then
		return nil
	end
	if def.kind == "employer" then
		return employerNode(player, d, def, sub)
	elseif def.kind == "realtor" then
		return realtorNode(player, d, sub)
	elseif def.kind == "banker" then
		return bankerNode(player, d, sub)
	elseif def.kind == "clubmd" then
		return clubNode(player, d)
	elseif def.kind == "friend" then
		return friendNode(player, d, npcId, remote)
	end
	return nil
end

-- Root menus get the relationship entry ("💕 친해지기") before the goodbye.
local function withSocial(player: Player, npcId: string, node: Node): Node
	local social = ctx.social
	if not social or type(social.menuChoice) ~= "function" then
		return node
	end
	local ok, mc = pcall(social.menuChoice, player, npcId)
	if not ok or type(mc) ~= "table" or type(mc.id) ~= "string" then
		return node
	end
	local choices = table.clone(node.choices)
	local at = #choices + 1
	for i, c in choices do
		if c.id == "bye" then
			at = i
			break
		end
	end
	table.insert(choices, at, { id = mc.id, label = mc.label })
	return { text = node.text, choices = choices, emote = node.emote }
end

local function phoneSafe(id: string): boolean
	return PHONE_SAFE[id] == true or string.sub(id, 1, 5) == "rent:" or string.sub(id, 1, 4) == "buy:" or string.sub(id, 1, 4) == "soc:"
end

local function send(player: Player, npcId: string, node: Node, remote: boolean, prefix: string?)
	local def = G.NPCS[npcId]
	local choices: { [string]: boolean } = {}
	local out = {}
	for _, c in node.choices do
		if (not remote or phoneSafe(c.id)) and not choices[c.id] then
			choices[c.id] = true
			table.insert(out, { id = c.id, label = c.label })
		end
	end
	if not choices.bye then
		choices.bye = true
		table.insert(out, { id = "bye", label = if remote then "전화 끊기" else "안녕히 계세요" })
	end
	dialogs[player] = { npcId = npcId, choices = choices, remote = remote, openedAt = os.clock() }
	local text = (if prefix and prefix ~= "" then prefix .. "\n" else "") .. node.text
	ctx.remotes.Dialog:FireClient(player, {
		npcId = npcId,
		name = def.name,
		role = def.role,
		portraitColor = color(def.color, Color3.fromRGB(120, 120, 140)),
		text = text,
		choices = out,
		remote = if remote then true else nil,
		emote = node.emote,
	})
	if not remote then
		spoke(npcId, text, nil)
	end
end

function NPC.close(player: Player)
	local dlg = dialogs[player]
	if dlg then
		dialogs[player] = nil
		if not dlg.remote then
			NPC.disengage(dlg.npcId, player, false)
		end
		if player.Parent == Players then
			ctx.remotes.Dialog:FireClient(player, { close = true })
		end
	end
end

function NPC.open(player: Player, npcId: string, remote: boolean)
	if not G.NPCS[npcId] or not Profiles.get(player) then
		return
	end
	if not remote and not near(player, npcId, 6) then
		return
	end
	if not Util.cooldown(player, "npcOpen", 0.5) then
		return
	end
	local node = buildNode(player, npcId, nil, remote)
	if not node then
		return
	end
	local prefix: string? = nil
	local social = ctx.social
	if social and type(social.onTalk) == "function" then
		local ok, line = pcall(social.onTalk, player, npcId, remote)
		if ok and type(line) == "string" and line ~= "" then
			prefix = line
		end
	end
	local st = npcs[npcId]
	if remote and st and st.hidden and not st.move and G.NPCS[npcId].kind == "friend" then
		prefix = nil -- woken up by the call: just the sleepy answer
	end
	if not remote then
		NPC.engage(npcId, player)
	end
	send(player, npcId, withSocial(player, npcId, node), remote, prefix)
end

-- Follow-up line after an action, then the NPC's root menu again.
local function reopen(player: Player, dlg: Dlg, line: string?, sub: string?)
	local node = buildNode(player, dlg.npcId, sub, dlg.remote)
	if node then
		if sub == nil then
			node = withSocial(player, dlg.npcId, node)
		end
		send(player, dlg.npcId, node, dlg.remote, line)
	end
end

function NPC.choice(player: Player, p: any)
	local dlg = dialogs[player]
	local npcId = Util.str(p.npcId, 40)
	local choiceId = Util.str(p.choiceId or p.choice, 60)
	if not npcId or not choiceId then
		return
	end
	if not dlg or dlg.npcId ~= npcId then
		-- a street key NPC's dialog is Relationships' own (it gets the same PhoneAction): here only
		-- the body language follows it (talk while answering, wave goodbye, back to work)
		local st = npcs[npcId]
		if st and st.street and st.talker == player then
			if choiceId == "bye" or choiceId == "close" then
				NPC.disengage(npcId, player, choiceId == "bye")
			elseif Util.cooldown(player, "npcStreetTalk", 0.5) then
				st.talkUntil = math.max(st.talkUntil, os.clock() + 20)
				spoke(npcId, nil, nil)
			end
		end
		return
	end
	if choiceId == "close" then
		-- the dialog sheet closed itself (the player walked away / opened the phone)
		NPC.close(player)
		return
	end
	if not dlg.choices[choiceId] then
		return
	end
	if not dlg.remote and not near(player, npcId, 10) then
		NPC.close(player)
		return
	end
	local def = G.NPCS[npcId]
	local d = Profiles.get(player)
	if not d then
		return
	end
	if choiceId == "bye" then
		dialogs[player] = nil
		if not dlg.remote then
			NPC.disengage(npcId, player, true)
		end
		if player.Parent == Players then
			ctx.remotes.Dialog:FireClient(player, { close = true })
		end
		return
	end
	if choiceId == "back" then
		reopen(player, dlg, nil, nil)
		return
	end
	-- relationship menu (Relationships.luau)
	if string.sub(choiceId, 1, 4) == "soc:" then
		local social = ctx.social
		if not social or type(social.handleChoice) ~= "function" then
			return
		end
		local ok, res = pcall(social.handleChoice, player, npcId, choiceId, dlg.remote)
		if not ok then
			warn("[GwangalliGameplay] social choice failed: " .. tostring(res))
			return
		end
		if type(res) ~= "table" or not res.handled then
			return
		end
		if not dlg.remote and res.emote and HINT_EMOTE[res.emote] then
			NPC.react(npcId, HINT_EMOTE[res.emote])
		end
		if type(res.node) == "table" and type(res.node.text) == "string" and type(res.node.choices) == "table" then
			send(player, npcId, res.node, dlg.remote, res.line)
		elseif res.close then
			if not dlg.remote then
				NPC.react(npcId, "shake")
			end
			send(player, npcId, { text = res.line or "…", choices = {} }, dlg.remote)
		else
			reopen(player, dlg, res.line, nil)
		end
		return
	end
	local function react(name: string)
		if not dlg.remote then
			NPC.react(npcId, name)
		end
	end
	-- employer
	if def.kind == "employer" then
		if choiceId == "hire" then
			local ok = ctx.applyJob(player, def.job, "npc")
			if ok then
				react("cheer")
				reopen(player, dlg, "좋아요, 오늘부터 우리 식구예요! 🎉", nil)
			else
				react("shrug")
				NPC.close(player)
			end
		elseif choiceId == "info" or choiceId == "status" then
			reopen(player, dlg, nil, choiceId)
		elseif choiceId == "start" then
			react("point")
			NPC.close(player)
			if not (d.job and d.job.id == def.job) then
				ctx.applyJob(player, def.job, "npc")
			end
			ctx.startShift(player)
		elseif choiceId == "endshift" then
			react("clap")
			NPC.close(player)
			ctx.endShift(player)
		elseif choiceId == "quit" then
			react("shrug")
			NPC.close(player)
			ctx.quitJob(player)
		end
		return
	end
	if def.kind == "realtor" then
		if choiceId == "list_rent" or choiceId == "list_buy" or choiceId == "myhome" then
			react("nod")
			reopen(player, dlg, nil, choiceId)
		elseif string.sub(choiceId, 1, 5) == "rent:" then
			local ok, msg = ctx.rentHome(player, string.sub(choiceId, 6))
			react(if ok then "clap" else "shake")
			reopen(player, dlg, msg, if ok then nil else "list_rent")
		elseif string.sub(choiceId, 1, 4) == "buy:" then
			local ok, msg = ctx.buyHome(player, string.sub(choiceId, 5))
			react(if ok then "clap" else "shake")
			reopen(player, dlg, msg, if ok then nil else "list_buy")
		end
		return
	end
	if def.kind == "banker" then
		if choiceId == "history" then
			react("nod")
			reopen(player, dlg, nil, "history")
			return
		end
		local line: string? = nil
		local okT = false
		if choiceId == "deposit_all" then
			okT, line = ctx.bankTransfer(player, "deposit", d.cash)
		elseif choiceId == "withdraw_50k" then
			okT, line = ctx.bankTransfer(player, "withdraw", 50000)
		elseif choiceId == "withdraw_200k" then
			okT, line = ctx.bankTransfer(player, "withdraw", 200000)
		end
		react(if okT then "bow" else "shake")
		reopen(player, dlg, line, nil)
		return
	end
	if def.kind == "clubmd" then
		local line = ctx.clubAction(player, choiceId)
		react(if choiceId == "vip" then "cheer" else "point")
		reopen(player, dlg, line, nil)
		return
	end
	if def.kind == "friend" then
		if choiceId == "chat" then
			local line = ctx.friendChat(player, def.contact or npcId, npcId, dlg.remote)
			react("laugh")
			reopen(player, dlg, line, nil)
		end
		return
	end
end

-- Closes dialogs of players who walked away.
local function tick()
	for player, dlg in dialogs do
		if player.Parent ~= Players then
			dialogs[player] = nil
		elseif not dlg.remote and not near(player, dlg.npcId, 14) then
			NPC.close(player)
		elseif os.clock() - dlg.openedAt > (if dlg.remote then 90 else 180) then
			NPC.close(player) -- idle: never leave a dialog covering the touch controls
		end
	end
end

function NPC.onLeave(player: Player)
	dialogs[player] = nil
	for _, st in order do
		if st.talker == player then
			NPC.disengage(st.id, player, false)
		end
		st.noticed[player] = nil
		if st.approach == player then
			st.approach = nil
		end
	end
end

function NPC.onCharacter(player: Player)
	NPC.close(player)
end

-- For other server code / tests: the live state of a key NPC (nil when not spawned).
function NPC.state(npcId: string): any?
	local st = npcs[npcId]
	if not st then
		return nil
	end
	local spots = {}
	for i, s in st.spots do
		spots[i] = { pos = s.pos, act = s.act, checked = s.checked, ok = s.ok, why = s.why }
	end
	return {
		pos = currentPos(st),
		act = st.act,
		yaw = st.yaw,
		walking = st.leg ~= nil,
		hidden = st.hidden,
		talker = st.talker,
		model = st.model,
		home = st.home,
		spots = spots,
		post = st.post,
		move = if st.move then { to = st.move.to, stage = st.move.stage } else nil,
	}
end

function NPC.init(context: any)
	ctx = context
	G = context.G
	Util = context.Util
	Profiles = context.Profiles
	Anim = optional("GwangalliAnim")
	Looks = optional("GwangalliNPCLooks")
	Citizens = optional("GwangalliCitizens")
	task.delay(8, function()
		local ok, err = pcall(prefetchAnchors)
		if not ok then
			warn("[GwangalliGameplay] npc posts: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GwangalliGameplay] npc tick failed: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(behaviour)
			if not ok then
				warn("[GwangalliGameplay] npc behaviour failed: " .. tostring(err))
			end
		end
	end)
end

return NPC
