-- GwangalliWorld/TrafficConfig: tunables of the client ambient traffic (TrafficCars) and the people in
-- and around the cars (TrafficPeople). Per-tier tables are { low, mid, high, saver } (GwangalliQuality;
-- phones run "low", and "saver" while GwangalliQuality's saver sub-level is on).
-- Units: studs (1 stud = 0.3 m), seconds, studs / s (km/h / 1.08).

return {
	-- master switch (also: workspace attribute GwangalliTrafficOff = true stops the system at runtime)
	Enabled = true,

	-------------------------------------------------------------------------------------------------
	-- moving cars around the player
	-------------------------------------------------------------------------------------------------
	-- how many moving cars at most (workspace attribute GwangalliTrafficCap overrides, for tests)
	Cap = { low = 12, mid = 16, high = 20, saver = 6 },
	-- fewer cars late at night (00-06 h): cap * NightShare
	NightShare = 0.6,
	-- spawn ring around the player. In view, cars only appear beyond SpawnViewMin (they drive in);
	-- off screen anywhere in the ring
	SpawnMin = 60,
	SpawnMax = { low = 190, mid = 220, high = 250, saver = 150 },
	SpawnViewMin = 150,
	SpawnEvery = 0.25, -- s between spawn attempts while below the cap
	SpawnGap = 26, -- no other car this close to a spawn point
	-- recycled when farther than Despawn, or farther than DespawnOff while off screen
	Despawn = { low = 240, mid = 270, high = 300, saver = 190 },
	DespawnOff = 160,
	StuckDespawn = 40, -- s without moving (not at a red light) -> recycled once off screen
	-- the mix (weights); kinds without a captured template use a built-in body
	Kinds = { { "sedan", 30 }, { "suv", 18 }, { "taxi", 16 }, { "compact", 14 }, { "van", 9 }, { "luxury", 7 }, { "truck", 6 } },
	-- paint for recoloured traffic (taxis / trucks keep their own colours)
	Paint = {
		{ 238, 239, 238 }, { 238, 239, 238 }, { 244, 244, 242 }, { 18, 19, 21 }, { 18, 19, 21 }, { 26, 27, 30 },
		{ 178, 182, 186 }, { 160, 164, 168 }, { 96, 100, 104 }, { 70, 74, 78 }, { 30, 48, 88 }, { 122, 20, 28 }, { 192, 182, 162 },
	},

	-------------------------------------------------------------------------------------------------
	-- driving (lane following: GwangalliNav lanes; no raycasts except the ground sample below)
	-------------------------------------------------------------------------------------------------
	SpeedFactor = 0.72, -- posted speed x this (busy beach streets); x 0.9..1.1 per driver
	TurnKmh = 22, -- cap on turn / U-turn connectors
	ChangeKmh = 30, -- cap on lane changes
	Accel = 6.5, -- studs / s^2 (~2 m/s^2)
	Brake = 11, -- comfortable deceleration
	HardBrake = 26, -- emergency (someone stepped out)
	MinGap = 3, -- studs bumper to bumper when stopped in a queue
	Headway = 1.1, -- s time gap while following
	StopLine = 1.0, -- studs between the front bumper and the stop node
	-- route choice at a node (weights per lane kind); bus-only lanes and U-turns only when nothing else
	EdgeWeight = { lane = 1, straight = 1, turn = 0.4, change = 0.05, uturn = 0.02, bus = 0.01 },
	ThinkHz = 10, -- leader / signal / pedestrian checks per car
	GroundEvery = 0.5, -- s between ground raycasts of one car (only cars within GroundDist)
	GroundDist = 170,
	-- people near the player: cars within PedDist give way to anyone in the lane ahead
	PedDist = 110,
	PedLook = 9, -- studs ahead beyond the stopping distance
	PedSide = 1.6, -- studs of margin beside the car body
	-- the player standing in the lane: honk once after HonkAfter s of waiting (cooldown per car)
	HonkAfter = 1.2,
	HonkCooldown = 12,
	-- model writes (LOD): every frame when on screen and within NearWrite, else every FarEvery frames
	-- on screen and every OffEvery frames off screen
	NearWrite = 150,
	FarEvery = 2,
	OffEvery = 6,
	-- brake / head / indicator lamps
	BlinkHz = 1.6,
	LampDist = 220, -- lamp state writes only for cars this close

	-------------------------------------------------------------------------------------------------
	-- people in the cars (TrafficPeople)
	-------------------------------------------------------------------------------------------------
	RigMax = { low = 16, mid = 16, high = 16, saver = 8 }, -- pooled GwangalliNPCLooks rigs (drivers + passengers + scenes)
	DriverDist = 120, -- cars closer than this show their driver
	PassengerDist = 70, -- and sometimes a passenger
	PassengerShare = 0.3,
	GestureDist = 45, -- head turns / phone / chatting hands only this close
	AnimOffDist = 60, -- off-screen rigs farther than this stop their tracks
	RigBuildEvery = 0.12, -- s between two rig builds / restyles (spreads the cost)
	LookPlayerDist = 28, -- drivers glance at the player on foot this close
	WaveDist = 50, -- drivers wave back when the player waves this close
	PhoneAtRed = 0.35, -- chance a driver checks the phone while waiting at a red light

	-------------------------------------------------------------------------------------------------
	-- scenes: get in / get out / taxi
	-------------------------------------------------------------------------------------------------
	SceneMax = { low = 4, mid = 4, high = 5, saver = 1 },
	SceneEvery = { 9, 20 }, -- s between two scene starts (random in range)
	DepartDist = { 26, 95 }, -- parked car (ParkedVehicles) -> owner walks up, drives off
	ArriveDist = { 35, 110 }, -- a car pulls into a free bay, the driver walks into a shop
	HailDist = { 30, 120 }, -- someone at the kerb / 택시승강장 flags a taxi
	TaxiStandDist = 160, -- the 택시승강장 scene runs while the player is this close to it
	WalkSpeed = 6.2, -- studs / s (the default walk clip matches ~6.4)
	RestoreDist = 150, -- a bay emptied by a departure gets its car back beyond this (off screen)
	ParkedKeep = 90, -- a car parked by a scene stays this long at most (s) once off screen
	DepartCooldown = 240, -- s before the same parked car can leave again
	Sounds = {
		Horn = "rbxasset://sounds/electronicpingshort.wav",
		HornSpeed = 0.42,
		Lock = "rbxasset://sounds/electronicpingshort.wav",
		LockSpeed = 1.55,
		Door = "rbxasset://sounds/clickfast.wav",
		DoorSpeed = 0.55,
	},

	-- debug: workspace attribute GwangalliTrafficDebug = true prints stats every DebugEvery s
	DebugEvery = 5,
}
