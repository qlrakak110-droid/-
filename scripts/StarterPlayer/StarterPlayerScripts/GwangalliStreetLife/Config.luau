-- GwangalliStreetLife/Config: tunables of the client-side street life (pedestrians, club crowd).
-- Per-tier tables are { low, mid, high, saver } (GwangalliQuality); phones run the low tier and the
-- "saver" entry while GwangalliQuality's saver sub-level of low is on (a phone under ~22 fps).

return {
	-- street pedestrians around the player (named citizens first, anonymous passers-by fill up);
	-- at night the cap shrinks away from the club: cap * (1 - 0.3 * hype) (GwangalliNight.streetCap),
	-- blended by the distance to the club door between NightBlend[1] and NightBlend[2] studs
	-- (saver: GwangalliQuality's emergency brake for a phone stuck under ~22 fps on low - at or below
	-- the last phone-tested low tier, 22)
	Cap = { low = 50, mid = 50, high = 50, saver = 20 },
	NightBlend = { 180, 320 },
	-- spawn ring (studs from the player). Steady state spawns go ahead of the player's direction of
	-- travel, off-screen or at least SpawnViewMin studs away when on screen; people despawn behind
	-- the player first
	SpawnMin = { low = 26, mid = 30, high = 34, saver = 24 },
	SpawnMax = { low = 75, mid = 90, high = 110, saver = 60 },
	SpawnViewMin = 42,
	FillMin = 12, -- first fill (join / quick travel): people may appear this close
	Despawn = { low = 120, mid = 145, high = 170, saver = 95 },
	-- update rates by distance: every frame within Near, MidHz within Mid, FarHz beyond; off-screen
	-- agents never run faster than OffHz
	Near = { low = 50, mid = 70, high = 90, saver = 40 },
	Mid = { low = 100, mid = 130, high = 160, saver = 80 },
	MidHz = 12,
	FarHz = { low = 5, mid = 5, high = 6, saver = 3 },
	OffHz = 6,
	-- animations: every on-screen agent inside the despawn radius keeps its base loop (walk / idle /
	-- sit ...). Tracks stop only for agents that are off-screen AND farther than OffFreeze studs; the
	-- camera check for those runs every frame so they start again as soon as they come into view
	OffFreeze = { low = 60, mid = 70, high = 80, saver = 45 },
	-- procedural gestures (chat hands, eating, head look) only this close
	GestureDist = { low = 32, mid = 45, high = 60, saver = 20 },
	-- name + tier chip / 말 걸기 prompt
	ChipDist = 26,
	ChipMax = { low = 3, mid = 4, high = 5, saver = 2 },
	PromptDist = 10,
	PromptMax = 3,
	-- spawner cadence
	TickHz = 3,
	SpawnPerTick = 1,
	FillPerTick = 3,
	CandidateEvery = 2.5, -- s between GwangalliCitizens.candidates refreshes
	TeleportJump = 120, -- the player moved this far between ticks: refill around the new spot
	-- the mix: when more than WalkShareMax of the people near the player are walking, the next
	-- passer-by starts at an activity spot (bench, towel, photo spot, shop window ...). By day at
	-- least SunbathersMin people lie on towels whenever sand is inside the ring
	WalkShareMax = 0.55,
	SunbathersMin = 2,
	InPlaceChance = 0.75, -- activity passers-by that start at their spot (the rest walk there)
	-- groups of friends (2-3 people walking / standing together)
	GroupChance = 0.3,
	GroupSide = 3.1, -- studs between friends walking side by side (the rigs are ~4 studs wide)
	HoldHands = 0.4, -- two-person groups that walk hand in hand
	-- night on the beach / promenade / plazas / parks (away from the club): more pairs, more of them
	-- couples, more hand in hand. GroupChance x (1 + NightCoupleBoost x hype); HoldHands blends to
	-- HoldHandsNight with the night hype
	NightCoupleBoost = 0.6,
	HoldHandsNight = 0.7,
	-- passers-by out for a walk who walk a dog (promenade / plazas / parks, 07-21 h)
	DogChance = 0.16,
	-- walkers who keep looking at the phone while walking (head down, a bit slower)
	PhoneWalk = 0.22,
	-- pooled rigs kept beyond the active ones (reused when the same person comes back)
	PoolSpare = 10,
	PoolSpareSaver = 4, -- idle rigs kept while GwangalliQuality's saver is on
	-- walking speeds (studs/s): the default R15 walk animation matches ~6.4 studs/s, run ~12.8
	WalkAnimSpeed = 6.4,
	RunAnimSpeed = 12.8,
	-- how long people stay at a spot (s, real time); idle sub-states change every SubIdle s
	SpotTime = { 22, 70 },
	PauseTime = { 3, 10 },
	SubIdle = { 4, 10 },
	-- club queue: the head goes in every QueueStep seconds at the peak (slower early)
	QueueStep = { 7, 13 },
	-- reactions to the player on foot
	SprintSpeed = 20.5, -- faster than this is running (GwangalliConfig.Sprint: walk 16, run 26)
	GlanceChance = 0.35, -- chance that an eligible person glances at a runner / a passer-by
	GlanceMax = 3, -- people glancing at the player at the same time
	AvoidTTC = 1.2, -- s: start stepping aside when the player would reach us this soon
	AvoidShift = 2.5, -- studs sideways
	AvoidRate = 7, -- studs/s
	ContactDist = 1.8, -- the player walked into someone
	BumpCooldown = 8,
	-- vehicles: a car faster than CarFast studs/s makes people within reach jump out of the way
	CarFast = 25,
	CarTTC = 1.5,
	CarReach = 40, -- studs (grows with the car's speed)
	-- the player's own car below CarFast: most people step aside, a few do not (a light hit: a stagger;
	-- 15+ studs/s: they go down); slower than CarCrawl a touch is nothing
	CarSlowFail = 0.06,
	CarSlowDistracted = 0.25, -- added for drunks / people on the phone / sitting / asleep
	CarCrawl = 3,
	DiveSpeed = { 14, 18 },
	HornReach = 30,
	-- the evening club pitch: at most one every LureCooldown s, the same person not again for
	-- LureSameId s, none for LureAfterWalkAway s after the player walked away from one
	LureCooldown = 50,
	LureSameId = 600,
	LureAfterWalkAway = 180,
	-- the drone show / the busker / street food vendors
	DroneReach = 260, -- studs from the waterline: people there stop and watch the show
	AudienceMax = { low = 3, mid = 4, high = 5, saver = 2 },
	CustomersMax = 2,
	-- 포장마차 carts (the Interact layer's street-food carts, read only): the nearest cart within 110
	-- studs gets at most CartCustomers.day / .evening (17:30-03:00) customers at once; a new one is
	-- sent every CartEvery / CartEveryEvening s (none 03-06 h)
	CartCustomers = { day = 1, evening = 3 },
	CartEvery = { 16, 32 },
	CartEveryEvening = { 6, 14 },
	-- anonymous passer-by ids (rig cache keys)
	Extras = 60,
	-- debug: Workspace attribute GwangalliStreetLifeDebug = true prints stats every DebugEvery s
	DebugEvery = 5,
}
