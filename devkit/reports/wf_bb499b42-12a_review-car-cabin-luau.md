# review-car-cabin-luau (wf_bb499b42-12a)

- status: completed
- failed agents (never finished, usually the usage limit): none

## review:api

```json
{
 "findings": [
  {
   "title": "Entering a parked car swaps out its Interior and adds the steering motors after the cabin was built: the stock interior shows through the AAA cabin and the steering wheel never turns",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "buildCabin L229-254 (hidden set and `motors = steerMotors(rec.model)` taken once); lodStep L304-325 (never checks whether the cabin is still valid)",
   "severity": "critical",
   "failure": "Parked cars are only rigged when someone gets in (Parked.luau: 'the physics rig is built only when someone gets in'; Cars.enter -> rigCandidate -> Rig.rig). Rig.rig calls freshLodModels, which Destroys the `Interior` model and parents a new clone. It also creates the DriveWheel<i> Motor6Ds at that moment. The player has to walk up to the door, so the client has already built this car's cabin within 52 studs. In that cabin, `hidden` points at parts that are now destroyed, and the cloned SeatCushion/WheelRim/Dash/ClusterScreen parts arrive with server Transparency 0 and normal SurfaceGuis. DetailLOD then shows them because they are now in its moving set. `cab.motors` was collected before the rig, so it is `{}`. Because the car becomes `mine` (d = 0), this cabin is never dropped or rebuilt. For the whole drive the player sees the old octagon rim, dash box and seats overlapping the AAA parts, and the AAA steering wheel stays still. This happens on every first entry into one of the 30% of parked cars that are unlocked.",
   "fix": "In lodStep, after `base` is resolved:\n```lua\nlocal cab = rec.cabin\nif cab and (not base or cab.fit.base ~= base or cab.fit.interior.Parent ~= m) then\n    destroyCabin(rec) -- Interior re-cloned by Rig.rig (enter) / frame part changed: rebuild next pass\nelseif cab and #cab.motors == 0 then\n    cab.motors = steerMotors(m) -- DriveWheel Motor6Ds appear when the server rigs the car\nend\n```\nAlso hide REPLACES parts that arrive later while the cabin lives. In buildCabin: `cab.conn = F.interior.DescendantAdded:Connect(function(d) if d:IsA(\"BasePart\") and REPLACES[d.Name] and not d:IsA(\"Seat\") then hidden[d] = d.Transparency; d.Transparency = 1 end end)`, and call `cab.conn:Disconnect()` in destroyCabin."
  },
  {
   "title": "Steering wheel turns the opposite way to the front wheels",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "RenderStepped L406 `local angle = math.clamp(-yaw * CFG.steerRatio, -7.5, 7.5)`",
   "severity": "major",
   "failure": "Visuals and Drive set the hub Transform to `CFrame.Angles(0, -steer, 0)`, so `ry` from ToOrientation is the real wheel yaw. In Roblox, ry > 0 swings the LookVector toward -X (Angles(0, pi/2, 0).LookVector = (-1, 0, 0)), meaning the wheels point left. Visuals confirms this: on a left turn, AngularVelocity·Up > 0 gives steer < 0 and ry > 0. The pivot frame W has its Z axis toward the driver (Fit flips axis to +Z), so `CFrame.Angles(0, 0, angle)` with angle > 0 moves the top of the rim to -X, which is counter-clockwise as the driver sees it (a left turn). The code passes `-yaw`, so wheels turned left (ry > 0) give angle < 0 and the wheel turns clockwise. On every live car, including the player's own, the steering wheel visibly rotates against the direction the car is turning.",
   "fix": "`local angle = math.clamp(yaw * CFG.steerRatio, -7.5, 7.5)`"
  },
  {
   "title": "AAA cabins are built on map traffic cars that the client traffic system has already hidden, using up the 3 cabin slots",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "lodStep L304-325 (candidate selection has no hidden-state check)",
   "severity": "major",
   "failure": "GwangalliWorld/TrafficCars adopts every static car under roads/TrafficVehicles (e.g. Car_Sonata, VehicleKind 'sedan') once the player is within 320 studs. It hides that car locally with Util.setHidden (LocalTransparencyModifier = 1 plus a managed DescendantAdded handler that hides anything added later) and drives a live clone from the same spot. This script still tracks the hidden static model. Those cars sit in queues at lights right next to the road, so they are often the nearest cars and take the maxCabins = 3 slots. Each one builds about 400 parts that the managed handler immediately hides. The visible cars around them, including the live traffic clones and parked cars, get no cabin. Standing at a crossing with 3 frozen cars therefore shows no AAA interiors anywhere and costs about 1200 hidden welded parts.",
   "fix": "At the top of the lodStep loop, after the `not m.Parent` check:\n```lua\nif m:GetAttribute(\"GwHideState\") == \"hidden\" then -- Util.setHidden root state (TrafficCars adoption)\n    destroyCabin(rec)\n    continue\nend\n```\nAlternatively, skip models that have a `TrafficVehicles` ancestor."
  },
  {
   "title": "If the frame part streams out, the cabin is left unwelded: its parts fall and it is never rebuilt",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "lodStep L310-325 (`if base then` ... else nothing); RenderStepped L381",
   "severity": "minor",
   "failure": "The place uses StreamingEnabled, and parked cars are Default/non-atomic models. If Underbody streams out while a cabin exists, the Model stays parented. This can happen when the camera is near a car more than 128 studs from the character under low-memory stream-out. All 400 CabinWeld joints then lose Part0, so the unanchored local parts fall through the map until FallenPartsDestroyHeight removes them. `rec.base` becomes nil and the `if base` branch is skipped, so destroyCabin never runs. When Underbody streams back in, `rec.cabin` is still non-nil and nothing is rebuilt. The Interior parts that streamed back in are new instances at Transparency 0, so the stock interior shows with no AAA cabin.",
   "fix": "Use the same validity check as for the rig: `if rec.cabin and (not base or rec.cabin.fit.base ~= base) then destroyCabin(rec) end`, evaluated before the `if base then` block so it also runs when base is nil."
  },
  {
   "title": "Cluster turn arrows never light on the Porter truck because its indicators are named TurnLamp",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "turnState L358 `d.Name == \"Repeater\"`",
   "severity": "minor",
   "failure": "Visuals.setTurn switches any part whose name contains repeater/turnlamp/indicator/blinker to Neon. The Porter II dump (car_14415) has `TurnLamp` parts as direct children and no `Repeater`. When a Porter blinks or uses hazards, turnState returns false, false and the cluster arrows stay dark.",
   "fix": "`if d:IsA(\"BasePart\") and (d.Name == \"Repeater\" or d.Name == \"TurnLamp\") and d.Material == Enum.Material.Neon then`"
  },
  {
   "title": "Carnival's second-row captain seats are hidden and nothing replaces them",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Seats.luau",
   "where": "Seats.build L165-169 (`if s.w >= 2.6 then rearBench`) with Fit.run L291 and Seats.REPLACES L173",
   "severity": "minor",
   "failure": "Car_Carnival (car_42373) has SeatCushion 1.65 wide at z = 3.0 in row 2. Fit puts them in F.rear because z > z0 + 1.0. Seats.build only rebuilds rear entries with w >= 2.6, so these two are skipped. buildCabin still sets Transparency = 1 on every SeatCushion, SeatBack and Headrest by name, so the van's second row is left with no seats at all.",
   "fix": "Rebuild narrow rear seats as buckets: `if s.w >= 2.6 then rearBench(K, F, P, s) else frontSeat(K, F, P, s) end`. Alternatively, do not hide seat parts whose seat record was not rebuilt."
  },
  {
   "title": "Hiding with a client-side Transparency write gets copied into client traffic templates",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "buildCabin L233-234 (`hidden[d] = d.Transparency; d.Transparency = 1`)",
   "severity": "minor",
   "failure": "Unlike LocalTransparencyModifier, Transparency is copied by Instance:Clone(). TrafficModels.offer checks map cars every 2 s and clones one as the template for any kind that has none yet. It keeps Interior SeatCushion, SeatBack, Dash, DashTop, WheelHub and Headrest, all of which are in REPLACES. Suppose a car of a template-less kind (e.g. right after a teleport next to the only parked G80 or Carnival) finishes streaming after its cabin was built. The template then captures Transparency = 1 on those parts, and every live traffic car of that kind for the rest of the session has no seats or dash.",
   "fix": "Record the original value on the part and repair clones as they are tracked. In buildCabin add `d:SetAttribute(\"GwCabinT\", d.Transparency)`. In destroyCabin add `p:SetAttribute(\"GwCabinT\", nil)`. In track(m) add `for _, d in m:GetDescendants() do local t = d:GetAttribute(\"GwCabinT\") if t ~= nil and not d:IsDescendantOf(<a model with a live cabin>) then d.Transparency = t; d:SetAttribute(\"GwCabinT\", nil) end end`. Traffic clones keep VehicleKind, so they pass through track."
  }
 ]
}
```

## review:geometry

```json
{
 "findings": [
  {
   "title": "Steering wheel turns the opposite way to the front wheels",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "RenderStepped, line 406: local angle = math.clamp(-yaw * CFG.steerRatio, -7.5, 7.5); ck.wheelWeld.C0 = ck.wheelCF * CFrame.Angles(0, 0, angle)",
   "severity": "major",
   "failure": "Visuals and Drive set the hub Transform to CFrame.Angles(0, -steer, 0). Positive steer means a right turn (Ctl: steerFwd = fwd*cos + right*sin(steer); Visuals: target = -atan(yaw*wb/v), and yaw < 0 when turning right). So ToOrientation gives ry = -steer and angle = +14*steer. wheelCF's +Z is the column axis pointing at the driver (Sonata: (0, 0.407, 0.914)), and Rz(+a) moves the 3 o'clock point toward 12 o'clock, which the driver sees as counter-clockwise. On a right turn the rim therefore spins left, and on a left turn it spins right. The legacy CarClient used CFrame.Angles(0, 0, -S.steer*6) for the same reason.",
   "fix": "local angle = math.clamp(yaw * CFG.steerRatio, -7.5, 7.5)  -- yaw = -steer, so a right turn gives a negative (clockwise) rotation"
  },
  {
   "title": "Headliner, headliner edge rolls, B-pillar trim and grab handles stick out through the side windows",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "where": "lines 80 (BPillarTrim), 93 (Headliner width half*2-0.1), 95 (HeadlinerEdge x = s*(half-0.1)), 108 (GrabHandle gx = g[1]*(half-0.14)); halfIn comes from Fit.luau 153-160 (DoorTrim inner face, measured at door height)",
   "severity": "major",
   "failure": "halfIn is the door-level half width (Sonata 2.56), but the side glass leans inward about 10 degrees, so the cabin is narrower at the roof. Sonata: the new Headliner spans x ±2.51 at y 3.745-3.805, while the SideGlass outer face at y 3.78 is at x ±2.41, so the liner sticks out 0.10 along its whole length (z -0.23 to 3.20). HeadlinerEdge (r 0.12, centred at ±2.46) reaches ±2.58, 0.16 outside the glass. BPillarTrim (x ±2.47-2.61, up to y 3.755) is 0.19 outside the glass and 0.14 outside the black BPillar body at its top. Grab handles cut into the glass. None of these points are covered by any opaque body part, so from the street you see a grey fabric lip along the top of every side window and grey wedges on the B-pillars. The old Headliner was only 4.67 wide (±2.335). Measured overshoot: G80 0.20 / 0.17 / 0.11, Carnival 0.24 / 0.20 / 0.14, Tucson 0.12 / 0.09.",
   "fix": "Fit: F.linerHalf = if liner then liner.Size.X / 2 else halfIn - 0.2\nTrim: local lh = F.linerHalf\n  Headliner size X = lh * 2; HeadlinerEdge x = s * (lh - 0.12); GrabHandle gx = g[1] * (lh - 0.1)\n  BPillarTrim follows the tumblehome: K:seg(\"BPillarTrim\", Vector3.new(side*(half-0.08), y1, split), Vector3.new(side*(lh-0.08), F.roofY, split), 0.16, P.fabric)"
  },
  {
   "title": "Front-door interior handle, handle cup and lock tab are inside the new dashboard",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "where": "doorCard, line 48: local hz = z0 + 0.42 (also LockTab at hz + 0.26)",
   "severity": "major",
   "failure": "The front card starts at the DoorTrim front edge, which lies under the dash. Sonata: z0 = -2.80, so hz = -2.38 (cup z -2.59 to -2.17) and LockTab = -2.12. The dash face is at -1.95, and DashLower spans x ±2.54, y 1.485-2.07, z up to -2.03. HandleCup (x -2.545 to -2.495, y 1.64-1.80), DoorHandle and LockTab are 100% inside DashLower, so the front doors have no visible inner handle. The same happens on every car: G80 hz -1.78 vs face -1.35, Tucson -1.98 vs -1.55, Ray -2.48 vs -2.05, Carnival -2.73 vs -2.30, Solati -6.83 vs -6.45.",
   "fix": "local hz = if front then math.max(z0 + 0.42, (F.dashFace :: number) + 0.35) else z0 + 0.42\n(Sonata: hz = -1.60, which clears the dash and the window-switch pod at -1.27 to -0.79.)"
  },
  {
   "title": "Centre-stack buttons and the lower part of the climate screen are buried in the centre console",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Dash.luau",
   "where": "lines 78 (cpY = bandY - 0.36), 79-88 (ClimateGlass/Bezel/Knobs, StackButton at cpY - 0.3, z face+0.06)",
   "severity": "major",
   "failure": "The stack is placed at fixed offsets below bandY, and F.console.top and dashBottom are never checked. Sonata/taxi: cpY = 1.61, so the six StackButtons sit at y 1.275-1.345, z -1.89. ConsoleBody runs from y 0.335 to 1.535 and z -2.25 to 1.35 over x ±0.40, so the four middle buttons (including the hazard) are 100% inside it and the outer two are 40-60% inside ConsoleSide. The ClimateGlass (y 1.44-1.78) has 26% of its face behind ConsoleBody, ConsoleDeck and ChargePad, which hides the fan bars. Tucson: buttons are 100% inside the console (top 1.90) and 64% of the climate screen face is covered. Carnival: buttons inside the console, 36% of the screen covered. Kia Ray (low console): the buttons hang at y 1.16-1.23, below the dash bottom (1.335), floating 0.12 in front of the DashLower face. On all cars the ClimateKnobs float 0.09 in front of the DashLower face (face-0.08).",
   "fix": "local lo = if F.console then F.console.top + 0.06 else bottom\nlocal hi = bandY - 0.1\nlocal cpY = math.max(bandY - 0.36, lo + 0.22)\nlocal ph = math.min(0.34, hi - lo - 0.1)  -- shrink ClimateGlass/Bezel heights to fit between lo and hi\nlocal btnY = cpY - 0.3\nif btnY - 0.035 < lo then btnY = nil end  -- skip or relocate the StackButton row when it does not fit\nAlso set the knob and button z to face - 0.03 so they sit on the DashLower face instead of floating."
  },
  {
   "title": "G80: centre stack shifted ~1 stud toward the passenger and sitting on the glovebox",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Dash.luau",
   "where": "line 71: local cx = if math.abs(nvX) < 1 then nvX else 0 (also glovebox gx = -ds*1.3, line 52)",
   "severity": "major",
   "failure": "The G80 FloatingScreen sits at local X = 0.99998 (float32), which is just under the threshold, so cx = 1.0. Whether a given G80 lands above or below 1 depends on its yaw rounding. With cx = 1.0 the centre vents move to x 0.64/1.36. The ClimateBezel spans x 0.29-1.71, y 1.385-1.825 and sits 0.11 in front of the glovebox outline (x 0.675-1.925, y 1.535-1.995), and the right climate knob ends up at x 1.86. The console and shifter stay at x≈0, so the stack is misaligned with them. Even with cx = 0 (every other car), the passenger ClimateKnob (x 0.74-0.96, y 1.50-1.72) lies inside the glovebox outline.",
   "fix": "local cx = if F.console then F.console.x else 0  -- align the stack to the console, not to an off-centre nav\nlocal gx = -ds * math.max(1.3, math.abs(cx) + 0.97 + 0.05 + gw / 2)  -- keep the glovebox clear of the climate knob"
  },
  {
   "title": "Carnival 2nd-row captain chairs disappear",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Seats.luau",
   "where": "Seats.build lines 165-169 (rear seats are built only if s.w >= 2.6)",
   "severity": "major",
   "failure": "Fit puts the Carnival's 2nd-row chairs (SeatCushion 1.65 wide at x ±1.30, z 3.0) into F.rear. Seats.build only builds benches, so nothing replaces them, but init still hides their SeatCushion, SeatBack, SeatInsert and Headrest (all in REPLACES). The van ends up with no seats between z 2.1 and 4.9; only the old SeatPiping slabs stay floating there (see the next finding). Trim's rear FloorMat has the same w >= 2.6 filter.",
   "fix": "for _, s in F.rear do\n\tif s.w >= 2.6 then rearBench(K, F, P, s) else frontSeat(K, F, P, s) end\nend\n(Optionally skip the belt and buckle for rear captain chairs.)"
  },
  {
   "title": "Carnival: old SeatPiping slabs are not hidden and float in front of the new seat backs",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Seats.luau",
   "where": "line 173: Seats.REPLACES (missing \"SeatPiping\")",
   "severity": "major",
   "failure": "Carnival seats contain a dark SeatPiping part (1.23 x 1.60 x 0.08, rgb 30,34,44) that used to sit between SeatBack and SeatInsert. SeatInsert and SeatBack are now hidden but SeatPiping is not. On the front seats its rear face is 0.126 in front of the new BackInsert and 0.156 in front of the new BackCore, so a dark slab covers the new seat back. The 2nd-row piping (x ±1.30, z 3.64) floats alone in the cabin.",
   "fix": "Seats.REPLACES = { \"SeatCushion\", \"SeatBack\", \"SeatInsert\", \"SeatPiping\", \"Headrest\", \"SeatBase\", \"SeatSupport\", \"RearBench\" }"
  },
  {
   "title": "Seat-belt buckles are inside the centre console",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Seats.luau",
   "where": "frontSeat line 98: CFrame.new(x - out*(w/2 + 0.06), cushTop + 0.05, zR - 0.2)",
   "severity": "major",
   "failure": "Sonata driver: the buckle is at x -0.34, y 1.285, z 1.025 (size 0.09 x 0.22 x 0.06, so y 1.175-1.395). ConsoleBody spans x ±0.40 up to y 1.535 and z to 1.35, so both buckles and the red release buttons are 100% inside the console. Measured the same on the G80, Tucson, Carnival and taxi. On the Kia Ray (console top 0.735) the buckle floats in mid-air 0.85 above the console.",
   "fix": "local bx, by = x - out * (w / 2 + 0.06), cushTop + 0.05\nif F.console and math.abs(bx - F.console.x) < F.console.w / 2 + 0.05 then\n\tbx = F.console.x - out * (F.console.w / 2 - 0.02)\n\tby = F.console.top + 0.12\nend\nlocal buckle = CFrame.new(bx, by, zR - 0.2) * CFrame.Angles(math.rad(-20), 0, 0)"
  },
  {
   "title": "Dash roll cuts through the instrument screens; on the Solati the steering rim also clips the cluster and dash",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Cockpit.luau",
   "where": "line 83: local zS = math.max(cl.Z, F.dashFace + 0.05); commercial branch lines 110-117 (yS = cl.Y + 0.03)",
   "severity": "major",
   "failure": "DashRoll (Ø0.26 at dashTop-0.13) reaches 0.13 behind the dash face toward the cabin, but the screen glass face sits only about 0.10-0.12 from the face. G80: a band at local y -0.14 to -0.07 (19% of the ClusterGlass and NavGlass faces) is inside the roll. Kia Ray: same, 19%. Porter cluster: 24%. Solati cluster (yS 3.145, z -6.36; roll y 3.095-3.355 out to z -6.32): 52% of the face is covered. On the Solati the rebuilt rim (R = 0.714, the vertex radius, versus 0.66 at the old piece centres) also reaches z -6.543, 0.09 into DashUpper (face -6.45), behind the cluster glass, and WheelRim/RimTrim samples intersect ClusterBezel and ClusterGlass. The cluster ends up floating in front of the top of the steering wheel.",
   "fix": "local zS = math.max(cl.Z, F.dashFace + 0.15)  -- glass face clears the roll (face + 0.13)\nCommercial branch: local yC = math.max(cl.Y + 0.03, F.dashTop + 0.23) and use yC for ClusterGlass/Bezel/Hood, so the cluster sits on top of the dash and above the rim. Optionally use the mean piece-centre distance for R (drop the / cos(pi/8)) so the new rim is not larger than the old one."
  },
  {
   "title": "Solati (no DoorTrim): dash 1 stud too narrow, door cards float inboard and run through the partition",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Fit.luau",
   "where": "lines 153-160 (halfIn defaults to 2.5 when there is no DoorTrim) and 173 (doorZ0, doorZ1 = c.Z - 1.2, c.Z + 5)",
   "severity": "major",
   "failure": "The Solati has no DoorTrim, so halfIn = 2.5, but the cab is 5.96 wide (Floor and old Dash; CabDoor inner face at ±2.98). The new DashUpper and DashLower are 4.96 wide while the old 5.96-wide Dash is hidden, leaving 0.5-stud holes at both dash ends (x 2.48-2.98, y 1.78-3.36). The door cards sit at x ±2.52, about 0.46 inboard of the real doors, from y 0.525 to 2.725. They run from z -7.25 to -1.15 (6.0 long), straight through the Partition at z -3.48 and 2.3 studs into the patient bay, cutting through the OxygenTank (z -2.95 to -2.25). Grab handles and headliner edges (x ±2.36-2.52) also cut into the Cabinet.",
   "fix": "Fit: if #trims == 0 then halfIn = (dash and dash.Size.X / 2 - 0.02) or (carpet and carpet.Size.X / 2 - 0.02) or 2.5 end\nand clamp the door range when there is no DoorTrim:\nlocal part = first({ \"Partition\" })\ndoorZ1 = if part then U:PointToObjectSpace(part.Position).Z - 0.1 else (front seat back z + 0.6)"
  },
  {
   "title": "Solati dash deck pokes through the windshield",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Dash.luau",
   "where": "lines 34-41: zA = math.min(ws.Z, front); DashDeck at full height `top` from zA",
   "severity": "major",
   "failure": "The deck top (y = dashTop) is extended forward to the windshield's bottom edge even when that edge is lower than dashTop. Solati: wsLow = (3.145, -7.70) and dashTop = 3.355, so DashDeck (y 3.275-3.355) runs to z -7.70 while the glass only reaches y 3.355 at z -7.51. The front 0.19 of the deck is 0.10 outside the glass's outer face, and no body part covers those points, so a dark strip is visible above the cowl from outside. The DashSlope wedge is created but sits entirely under the deck, so it fixes nothing.",
   "fix": "local hiW: Vector3 = F.wsHigh\nlocal zTop = ws.Z + math.max(0, top - ws.Y) * (hiW.Z - ws.Z) / math.max(0.01, hiW.Y - ws.Y)\nlocal zA, zB = math.min(zTop - 0.05, front), face - 0.12\n(The DashSlope then fills from ws up to zTop as intended.)"
  },
  {
   "title": "Seat belt is coplanar with the B-pillar trim and runs back onto the rear door handle",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Seats.luau",
   "where": "lines 90-97: bz = (F.bZ or zR+0.2) + 0.12; top x = out*(half-0.08); low = (out*(half-0.06), cushTop+0.1, bz+0.25)",
   "severity": "minor",
   "failure": "Sonata: the belt top is at x -2.48 with thickness 0.02, so its inner face is at -2.47. BPillarTrim's inner face is also -2.47 (centre -2.54, thickness 0.14), so the upper third of the belt (y 2.575-3.205) is coplanar or buried and z-fights. BeltAnchor is 80% inside the trim. The belt then slopes rearward to z 1.67, past the pillar (z 1.05-1.55), onto the rear door card, and passes over the rear door's HandleCup and DoorHandle (z 1.59-2.01, y 1.72) instead of going toward the front seat (zR 1.225). Measured the same on the G80, Tucson, Ray and Carnival.",
   "fix": "local bz = F.bZ or (zR + 0.2)\nlocal top = Vector3.new(out * (half - 0.105), F.roofY - 0.55, bz)\nlocal low = Vector3.new(out * (half - 0.10), cushTop + 0.1, bz - 0.3)\n(BeltAnchor at top as before, now 0.015 proud of the trim face.)"
  },
  {
   "title": "A-pillar trim centreline lies on or outside the windshield; its bottom end sticks out above the hood",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Dash.luau",
   "where": "lines 107-110: a = (s*(wsHalf+0.05), ws.Y+0.05, ws.Z+0.05), b = (s*(wsHalf-0.05), hi.Y-0.08, hi.Z+0.05), Ø0.22",
   "severity": "minor",
   "failure": "Sonata: endpoint a is at (±2.527, 2.545, -3.20), which is +0.02 outside the windshield mid-plane (normal (0, 0.90, -0.44)). With a 0.11 radius the cylinder reaches 0.13 outside the glass, and the end cap sits about 0.13 above the hood surface (y≈2.525 at z -3.2), beyond the end of the APillar body (z -3.13). That leaves a grey fabric stub on the outside at each windshield corner (exposed points at (±2.62, 2.60, -3.22)). Along its length the trim sits about 0.12 outboard of the side glass, mostly hidden inside the APillar body.",
   "fix": "local nOut = (hi - ws):Cross(Vector3.xAxis).Unit  -- (0, 0.90, -0.44) on the Sonata, points outward\nlocal a = Vector3.new(s * (wsHalf - 0.06), ws.Y, ws.Z) - nOut * 0.15\nlocal b = Vector3.new(s * (wsHalf - 0.12), hi.Y, hi.Z) - nOut * 0.15"
  },
  {
   "title": "Cluster and nav glass overlap by 0.02 on the same plane (z-fighting strip)",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Cockpit.luau",
   "where": "lines 88-102: xL = cl.X - 0.78 (RHD: xR = cl.X + 0.78); ClusterGlass centred at cl.X; NavGlass at xR - 0.04 - nvW/2",
   "severity": "minor",
   "failure": "The cluster's right edge is at cl.X + 0.68 and the nav's left edge at xL + 1.44 = cl.X + 0.66. Sonata: the cluster spans x -1.93 to -0.57 and the nav -0.59 to 0.66. Both glass parts sit at base z +0.045 with 0.02 thickness, so their SurfaceGuis z-fight in a 0.02 x 0.46 strip. This happens on every LHD and RHD car with the panoramic display.",
   "fix": "local xL = cl.X - (0.04 + clW / 2)  -- = cl.X - 0.72 (declare clW before use); RHD: xR = cl.X + 0.72\nThis leaves a 0.04 gap between the two glasses."
  },
  {
   "title": "Glovebox handle and top seam are hidden behind the dash trim band",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Dash.luau",
   "where": "lines 54-59: gy = mid - 0.18; GloveHandle at gy + gh/2 - 0.08, z face - 0.07",
   "severity": "minor",
   "failure": "The handle sits at y mid-0.03 (Sonata 1.92, y 1.903-1.938, z -2.035 to -2.005). DashTrimBand covers y mid-0.065 to mid+0.105 (1.885-2.055) at z -1.975 to -1.925, so the handle and the glovebox's top gap line (y 2.0) are fully behind the band. Only the lower 0.35 of the glovebox is visible, with no handle. The same formula applies to every car.",
   "fix": "local gy = mid - 0.33  -- top seam at mid - 0.10, below the trim band\nThe handle at gy + gh/2 - 0.08 is then visible."
  },
  {
   "title": "Rear-view mirror is tilted to face the headliner, not the driver",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "where": "line 125: local mcf = CFrame.new(mp) * CFrame.Angles(math.rad(-8), 0, 0)",
   "severity": "minor",
   "failure": "Rx(-8 deg) maps the face normal +Z to (0, 0.139, 0.990), so MirrorGlass (Sonata at y 3.59, z -0.46) faces 8 degrees upward. The driver's eye (about y 3.3, z 1.4, x -1.25) is about 7 degrees below and 34 degrees to the left, so the reflective face points at the roof. The sign is copied from the screens, which sit below eye level and should face up.",
   "fix": "local mcf = CFrame.new(mp) * CFrame.Angles(math.rad(6), math.rad(15) * F.side, 0)  -- face down and yaw toward the driver's side"
  },
  {
   "title": "Rear-bench armrest seams float in front of the backrest",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Seats.luau",
   "where": "lines 137-139: mid = hinge * CFrame.new(0, H*0.32, -0.12); seams at mid * (±0.3, 0, -0.06)",
   "severity": "minor",
   "failure": "The seams sit at hinge-local z -0.18. The bench back's front face is at -0.09 and BenchBackInsert's front face at -0.12. Sonata: the seams at (±0.30, 1.82, 3.70) hover 0.055 in front of the insert and 0.085 in front of the backrest, so from the side they are visible as two dark floating rods.",
   "fix": "local mid = hinge * CFrame.new(0, H * 0.32, 0)\nSeams at mid * CFrame.new(±0.3, 0, -0.125), flush on the insert face."
  },
  {
   "title": "Porter double passenger seat rebuilt as one narrower single seat",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Seats.luau",
   "where": "frontSeat line 23: local x, w = s.x, math.min(s.w, 1.85)",
   "severity": "minor",
   "failure": "The Porter's passenger cushion is 2.4 wide (x -0.05 to 2.35) with two headrests (x 0.55 and 1.75). After hiding it, the code builds one 1.85-wide seat (cushion pan 0.30-2.00) with a single headrest at x 1.15. This leaves a 0.7-stud empty gap between the driver and passenger seats and removes the middle seating position.",
   "fix": "In Seats.build, split wide front seats: if s.w > 2.0 then build two seats of width s.w/2 at x = s.x ± s.w/4 (copying s with x and w overridden); otherwise call frontSeat(K, F, P, s)."
  },
  {
   "title": "Kia Ray door armrest intrudes into the seat side shield and power-seat switches",
   "file": "/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "where": "line 41: DoorArmrest at x + inward*0.2, depth 0.36",
   "severity": "minor",
   "failure": "Ray: halfIn = 2.12, so the armrest's inner edge is at ±1.76 (y 1.21-1.34, z -1.64 to 0.62). The seat's SeatShield is at ±1.815-1.875 (y 1.165-1.465, z -0.37 to 1.07). The armrest overlaps the shield by about 0.1, and the SeatSwitch parts are 52-68% inside the armrest. The Porter passenger side overlaps by about 0.035.",
   "fix": "Clamp the depth to the free gap: local outerSeat = (max over F.front of |s.x| + min(s.w,1.85)/2 + 0.06); local depth = math.clamp(half - outerSeat - 0.02, 0.15, 0.36)\nPlace the armrest at x + inward * (0.02 + depth / 2) with size Z = depth."
  }
 ]
}
```

## review:lifecycle

```json
{
 "findings": [
  {
   "title": "Cabin is not rebuilt after the server rigs a parked car on entry: the old Interior shows through and the steering wheel stays frozen",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "buildCabin L230-259 (hidden/guis/motors are captured once); lodStep L304-326 (never invalidates a cabin)",
   "severity": "major",
   "failure": "A player walks to an unlocked parked car (Parked unlocks about 30%). At 52 studs or closer, lodStep builds the cabin while the car is still a static model. At that point cab.motors = steerMotors() = {} because there are no DriveWheel Motor6Ds yet, and cab.hidden holds the current Interior parts. The player presses 타기, so the server runs Cars.enter -> rigCandidate -> Rig.rig. freshLodModels() Destroys the Interior model and parents a fresh clone, then Rig adds the DriveWheel<i> Motor6Ds. On the client, the new Interior's SeatCushion/SeatBack/Dash/DashTop, 8x WheelRim, WheelHub and the ClusterScreen/NavScreen/ClimatePanel SurfaceGuis arrive at their original Transparency and MaxDistance and render inside the AAA cabin. The wheel never turns because yaw is averaged over the empty cab.motors. The car is now `mine` (d = 0), so nothing drops or rebuilds the cabin for the whole drive. Player-called cars are rigged before parenting and are not affected. This is the normal parked-car flow, and the cabin always exists before the player reaches the door.",
   "fix": "-- buildCabin, add to the rec.cabin table:\ninterior = F.interior, base = F.base, rigged = rec.model:GetAttribute(\"DriveRigged\") == true,\n\n-- lodStep, right after the `rec.base = Fit.frameOf(m)` refresh and BEFORE `if base then`:\nlocal cab = rec.cabin\nif cab and (cab.interior.Parent ~= m or cab.base ~= base\n\tor (m:GetAttribute(\"DriveRigged\") == true) ~= cab.rigged) then\n\tdestroyCabin(rec) -- Interior swapped / motors added / base gone: rebuilt next step (mine ranks first)\nend"
  },
  {
   "title": "Static TrafficVehicles hidden by client traffic still get full cabins and take the maxCabins slots",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "lodStep L304-326 (no visibility check before list insert / build)",
   "severity": "major",
   "failure": "Within 320 studs, TrafficCars.processAdoptions calls hideStatic(m, true) on every workspace.Gwangalli.roads.TrafficVehicles car. That runs Util.setHidden (LTM = 1, GwHideState = \"hidden\") and spawns a live clone at the same lane spot. Both models have VehicleKind and sit at the same distance. At a red-light queue next to the player, the hidden statics take about half of the 3 slots. Each one gets a full build of about 560-630 parts, 3 SurfaceGuis and the per-part Welds. Util's managed-root DescendantAdded handler then sets LTM = 1 on every cabin part and sets Enabled = false on its guis, so all that work is invisible. Meanwhile the visible clones beside the player get no cabin. The static stays hidden after its clone drives off on green, so it keeps the slot.",
   "fix": "-- lodStep, first thing inside `if base then`:\nif m:GetAttribute(\"GwHideState\") == \"hidden\" then -- adopted static (TrafficCars.hideStatic -> Util.setHidden)\n\tif rec.cabin then destroyCabin(rec) end\n\tcontinue\nend"
  },
  {
   "title": "Cabins thrash on passing traffic, on drive-by parked cars and on rank 3/4 swaps (no speed, dwell or rank hysteresis)",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "lodStep L315-346",
   "severity": "major",
   "failure": "(a) Client traffic clones under workspace.GwangalliTraffic keep VehicleKind and an Interior containing WheelHub, so Fit succeeds. A player standing at a busy road sees cars pass within 52 studs every second or two. Each pass builds a ~600-part cabin (about 9 frames at 70 parts per frame plus the parent spike), keeps it for 1-3 s, then destroys it beyond 72. Traffic roots are anchored and moved by BulkMoveTo, so velocity-based checks would read 0. (b) Driving at 60-100 km/h (55-90 studs/s) past parked cars: every 0.35 s lodStep starts a cabin on the nearest car, which is behind the player before it finishes. (c) Standing in a parking lot with cars at similar distances: d = min(camDist, rootDist) changes as the camera orbits, so ranks 3 and 4 swap. Each swap destroys one ~600-part cabin and builds another, and the next swap reverses it. All three cases cause sustained Instance creation, GC and frame spikes on phones.",
   "fix": "-- lodStep, once per step:\nlocal t = os.clock()\nlocal camV = if lastRp then (rp - lastRp).Magnitude / (t - lastT) else 0\nlastRp, lastT = rp, t\n-- per car (inside `if base then`):\nlocal p = base.Position\nlocal v = if rec.lastT then (p - rec.lastPos).Magnitude / (t - rec.lastT) else 0\nrec.lastPos, rec.lastT = p, t\nrec.still = if v < 8 then (rec.still or 0) + 1 else 0\nlocal ok = rec == mine or rec.cabin ~= nil or (rec.still >= 2 and camV < 25)\nelseif ok and d < CFG.buildRadius and (...) then\n\t-- existing cabins win ties: rank them 8 studs closer\n\ttable.insert(list, { rec = rec, d = if rec.cabin then d - 8 else d })"
  },
  {
   "title": "maxCabins is not enforced for cabins between buildRadius and dropRadius",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "lodStep L320-323 and L334-346",
   "severity": "minor",
   "failure": "A car with a cabin at 52 < d <= 72 fails both branches: it is not beyond dropRadius and not within buildRadius. It is never added to `list`, so it is never ranked and never destroyed by the cap. A player walks or drives past a short row of parked cars. Cabins on cars that fall behind stay until 72 studs, while up to 3 new cabins are built ahead. The result is 5-6 cabins at once (about 3,000-3,600 parts plus Welds), double the intended budget.",
   "fix": "elseif (d < CFG.buildRadius or (rec.cabin and d <= CFG.dropRadius)) and (not rec.failed or os.clock() - rec.failedAt > 8) then\n\ttable.insert(list, { rec = rec, d = d })\n...\n-- in the rank loop, only build inside buildRadius:\nelseif e.d < CFG.buildRadius and not e.rec.cabin and not e.rec.building and not building then"
  },
  {
   "title": "With StreamingEnabled, cabins are built from a half-streamed car; late Interior parts are never hidden, and a transient failure waits 8 s",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "lodStep L311-323 (build as soon as Underbody exists); buildCabin L208-214 and L230-239 (single hide pass); Fit.luau L83-85, L152-171 (fallbacks)",
   "severity": "major",
   "failure": "The place streams: rigged cars are Atomic, and parked and static cars are non-atomic, so their Model containers exist from join while BaseParts trickle in. After join, respawn or quick travel (taxi skip, GwangalliTravel), a mobile client fills the area over 1-5 s, and lodStep runs every 0.35 s. Case 1: Underbody has arrived but WheelRim/WheelHub have not. Fit returns \"no steering wheel anchors\", the car is marked failed, and it waits 8 s before retrying, so the cabin appears 8 s late next to the player. Case 2: the rims are in but DoorTrim/SeatCushion/Dash/Headliner are not. Fit falls back to halfIn = 2.5, floorY = c.Y - 1.9 and no seats, and the degraded cabin stays until the player walks 72 studs away. The Dash/Seat/ClusterScreen parts (and their SurfaceGuis) that stream in later are never hidden, because hiding is a one-time pass over F.interior:GetDescendants(), so they draw through the AAA cabin.",
   "fix": "-- lodStep: only build when the Interior stopped changing\nlocal int = m:FindFirstChild(\"Interior\")\nlocal n = if int then #int:GetChildren() else 0\nlocal settled = n > 0 and n == rec.intN\nrec.intN = n\n-- (add `settled` to the build condition)\n\n-- buildCabin, after the hide loop: keep hiding late arrivals\nlocal conn = F.interior.DescendantAdded:Connect(function(d)\n\tif d:IsA(\"BasePart\") and REPLACES[d.Name] and not d:IsA(\"Seat\") and not d:IsA(\"VehicleSeat\") then\n\t\thidden[d] = d.Transparency; d.Transparency = 1\n\telseif d:IsA(\"SurfaceGui\") and d.Parent and REPLACES[d.Parent.Name] then\n\t\tguis[d] = d.MaxDistance; d.MaxDistance = 0.01\n\tend\nend)\n-- store as rec.cabin.conn; destroyCabin: `if cab.conn then cab.conn:Disconnect() end` first\n-- transient streaming failure: retry on the next step instead of 8 s\nif Workspace.StreamingEnabled then rec.failedAt -= 7.5 end"
  },
  {
   "title": "A cabin whose Underbody streams out is orphaned: its parts fall and the cabin is never destroyed",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "lodStep L310-326 (all drop logic is inside `if base then`)",
   "severity": "minor",
   "failure": "On a phone under memory pressure, the engine streams out non-atomic parts beyond StreamingMinRadius (default 64), and dropRadius is 72. A parked car at 64-72 studs loses its Underbody. Every cabin part is unanchored and welded only to that Underbody (or to the pivot), so the whole client-owned cabin free-falls through the map. lodStep sets rec.base = nil and skips the car entirely, so destroyCabin never runs and rec.cabin/hidden keep references. When the Underbody streams back in as a new instance, the original Interior parts (also new instances) are visible again. rec.cabin is still non-nil, so no cabin is rebuilt until the player leaves 72 studs.",
   "fix": "Use the same guard as the rig finding, placed before `if base then` so it also fires when base is nil:\nif rec.cabin and rec.cabin.base ~= base then destroyCabin(rec) end\n(with `base = F.base` stored in rec.cabin)."
  },
  {
   "title": "Workspace.DescendantAdded handler runs per instance on every stream-in, and each streamed glass part re-tints the whole car",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "L148-165 (handler); Glass.luau L29-35 (roleOf GetAttribute), L38-57 (full-model tint)",
   "severity": "minor",
   "failure": "The place's own Util.discover was moved to tag mode to avoid exactly this: one handler per streamed-in instance, about 270k on join or quick travel. This handler runs synchronously for every instance and does the following. (1) Two IsA calls per instance, plus a task.defer closure for every Model (buildings, NPCs, accessories). (2) Glass.roleOf on every BasePart, which calls GetAttribute(\"Glass\") whenever the name is not a glass name. (3) For every building pane named \"Window\" (thousands; Signage discovers them by that name), a FindFirstAncestorWhichIsA climb to the map root. (4) Under streaming, car containers are tracked at join, so each of a sedan's 8 glass parts that streams in queues a full Glass.tint(m): GetDescendants of about 200+ instances with GetAttribute on each non-glass part, 8 times per car. Hundreds of milliseconds of main-thread Lua are added to the join and quick-travel burst on phones. Each cabin parent also runs about 600 GetAttribute calls.",
   "fix": "local GLASS_NAMES = { Windshield=true, FrontGlass=true, RearGlass=true, RearWindow=true, BackGlass=true, SideGlass=true, QuarterGlass=true, DoorGlass=true, CabGlass=true, SideWindow=true, Window=true }\nWorkspace.DescendantAdded:Connect(function(d)\n\tif d.ClassName == \"Model\" then\n\t\tif d:GetAttribute(\"VehicleKind\") ~= nil then task.defer(track, d) end\n\telseif GLASS_NAMES[d.Name] then -- name only; attribute-glass cars are covered by track()'s full tint\n\t\tlocal p = d.Parent\n\t\tif p and (cars[p] or cars[p.Parent]) then task.defer(Glass.tintOne, d) end -- tint this part only\n\tend\nend)\n-- Glass.tintOne(d): the body of Glass.tint's loop for a single part."
  },
  {
   "title": "The 70-parts-per-frame budget does not spread the expensive work: the whole cabin enters the world in one frame",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "buildCabin L216-246 (folder parented only after Cockpit/Dash/Console/Seats/Trim finish); Kit.luau L28-33, L52-72",
   "severity": "minor",
   "failure": "Kit yields every 70 parts, but those parts are created inside a parentless folder, which is the cheap part. `folder.Parent = rec.model` then inserts about 560-630 parts, the same number of Welds, about 20 SpecialMeshes and 3 SurfaceGuis (about 130 TextScaled GuiObjects) in a single frame. That one frame pays for joint and assembly building (into the moving car's assembly when it is the player's car), render registration, and every Workspace.DescendantAdded listener on about 1,400 instances (this script's own, Util.discover, MobileQuality's SurfaceGui discovery). Phones see a visible hitch on every build, which is multiplied by the churn described in the thrash finding. If a builder errors mid-build, the parentless partial folder is simply dropped.",
   "fix": "local folder = Instance.new(\"Model\")\nfolder.Name = \"CabinAAA\"\nfolder:SetAttribute(\"GwSkinKeep\", true)\nfolder.Parent = rec.model -- each 70-part slice now enters the world in its own frame\n-- (optionally set p.LocalTransparencyModifier = 1 in Kit apply and reveal all K.parts at the end)\n...\nif not rec.model.Parent or cars[rec.model] ~= rec then folder:Destroy() return end\n-- and declare `folder` outside the pcall: `if not ok and folder then folder:Destroy() end`"
  },
  {
   "title": "A quality-tier change re-shows the hidden original dash screens inside the cabin",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "buildCabin L235-238 (MaxDistance = 0.01); destroyCabin L196-200",
   "severity": "minor",
   "failure": "MobileQuality keeps every Workspace SurfaceGui in a registry and, on Util.onTierChanged, runs applyGui, which writes MaxDistance = md0 x SurfaceGuiDistanceScale (high 1, mid 0.85, low 0.6, saver 0.42) whenever it differs. Tier changes happen automatically: a desktop below 40 fps for 10 s drops to mid, and a phone below 22 fps for 8 s goes to saver. The cabins themselves can cause either drop. When that happens, every hidden ClusterScreen/NavScreen/ClimatePanel gui at MaxDistance 0.01 is reset to its tier distance and glows on the invisible old parts inside the AAA cabin. Later, destroyCabin restores the previous tier's value, not the current one.",
   "fix": "-- buildCabin, per hidden gui:\nguiConns[g] = g:GetPropertyChangedSignal(\"MaxDistance\"):Connect(function()\n\tif g.MaxDistance ~= 0.01 then guis[g] = g.MaxDistance; g.MaxDistance = 0.01 end -- keep the newest tier value for restore\nend)\n-- destroyCabin: disconnect all guiConns BEFORE writing the restored MaxDistance"
  },
  {
   "title": "Hiding with Transparency leaks into the traffic templates TrafficModels clones from a car that has a cabin",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "buildCabin L231-234 (d.Transparency = 1 on the real Interior parts)",
   "severity": "minor",
   "failure": "TrafficModels.offer clones the first complete car of each kind that is present when TrafficCars first scans ParkedVehicles/TrafficVehicles. It never re-offers that container. Under streaming, the complete cars are the ones near the spawn, which are the same cars this script gives cabins within about 1-3 s, while TrafficCars first waits for GwangalliNav and decode. If the cabin wins that race, the clone's kept Interior parts (SeatCushion, SeatBack, Dash, DashTop, WheelHub, Headrest, all in REPLACES) have Transparency = 1. CabinAAA itself is stripped as a non-Interior Model. Every traffic car of that kind for the rest of the session then has no seats or dash, and TrafficPeople drivers float in an empty shell behind the windshield.",
   "fix": "-- buildCabin hide: record the original on the part\nd:SetAttribute(\"GwCabinT\", d.Transparency); hidden[d] = d.Transparency; d.Transparency = 1\n-- destroyCabin restore: p.Transparency = old; p:SetAttribute(\"GwCabinT\", nil)\n-- TrafficModels.offer, right after `local clone = model:Clone()`:\nfor _, p in clone:GetDescendants() do\n\tlocal t = p:GetAttribute(\"GwCabinT\")\n\tif t then (p :: BasePart).Transparency = t; p:SetAttribute(\"GwCabinT\", nil) end\nend"
  },
  {
   "title": "Cabins are ~560-630 parts each (not ~400) with no quality-tier gating on phones",
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/init.client.luau",
   "where": "CFG L34-42 (maxCabins = 3 + mine, fixed); header L12",
   "severity": "minor",
   "failure": "The emulator log measured 560 parts for the Porter cabin (shots/cabin3.log, \"cabin 560\"). Counting the code paths for the Sonata gives about 560: seats 169, trim 158, cockpit 97, dash 78, console 58. The G80 adds 72 quilt strips, for about 630. Each part also has its own Weld, plus about 130 GuiObjects. Four cabins come to roughly 2.3-2.5k extra unanchored, welded, non-batched parts and as many joints. Every other world system scales with GwangalliQuality (DetailLOD radius, lights, SurfaceGui distance). The cabins keep the full budget even on a phone already in the saver sub-level (below 22 fps), where they are the biggest optional cost.",
   "fix": "local Quality = require(game:GetService(\"ReplicatedStorage\"):WaitForChild(\"GwangalliQuality\"))\nlocal function maxCabins(): number\n\treturn Quality.pick({ low = 1, mid = 2, high = 3, saver = 0 })\nend\n-- lodStep: `if i > maxCabins() + (if mine then 1 else 0) then`\n-- optionally skip quilt()/stitch/MapPocket micro-parts when Quality.isLow()"
  }
 ]
}
```

## verify:all

```json
{
 "verdicts": [
  {
   "index": 0,
   "real": true,
   "reason": "Confirmed. The Interior has LOD=\"near\" (car dumps), and Rig.rig calls freshLodModels, which does `ch:Destroy(); copy.Parent = model`. Rig.rig then creates the DriveWheel<i> Motor6Ds; Parked builds the rig only on entry. buildCabin takes `hidden`, `guis` and `motors = steerMotors()` once, and lodStep never re-checks them. The clone's parts replicate with server Transparency 0 and their screen SurfaceGuis keep their normal MaxDistance; a SurfaceGui still draws on a fully transparent part. Because the player's own car gets d = 0, its cabin is never dropped, `cab.motors` stays `{}` and the AAA wheel never turns. The Underbody is a top-level child, so the cabin welds survive the rig.",
   "fix": "-- buildCabin: record what the cabin was built on, and keep hiding parts that arrive later\nlocal conn = F.interior.DescendantAdded:Connect(function(d)\n\tif d:IsA(\"BasePart\") and REPLACES[d.Name] and not d:IsA(\"Seat\") and not d:IsA(\"VehicleSeat\") then\n\t\thidden[d] = d.Transparency; d.Transparency = 1\n\telseif d:IsA(\"SurfaceGui\") and d.Parent and REPLACES[d.Parent.Name] then\n\t\tguis[d] = d.MaxDistance; d.MaxDistance = 0.01\n\tend\nend)\n-- add to rec.cabin: conn = conn, interior = F.interior, base = F.base\n-- destroyCabin, right after rec.cabin = nil:\nif cab.conn then cab.conn:Disconnect() end\n-- lodStep, after base is resolved and BEFORE `if base then`:\nlocal cab = rec.cabin\nif cab and (cab.base ~= base or cab.interior.Parent ~= m) then\n\tdestroyCabin(rec) -- Interior re-cloned by Rig.rig / frame part gone: rebuilt next pass (mine ranks first)\nelseif cab and #cab.motors == 0 and m:GetAttribute(\"DriveRigged\") == true then\n\tcab.motors = steerMotors(m)\nend"
  },
  {
   "index": 1,
   "real": true,
   "reason": "Confirmed. Ctl uses `steerFwd = fwd*cos(steer) + right*sin(steer)`, so steer > 0 is a right turn. Visuals and Ctl.wheelTransforms set the hub Transform to Angles(0, -steer, 0), so ToOrientation gives ry = -steer. Fit makes the W frame's Z axis point at the driver (sim: back = (0, 0.407, 0.914)) and its X axis the car's right. Rz(+a) lifts the 3 o'clock point, which the driver sees as counter-clockwise (a left turn). With `-yaw`, a right turn (ry < 0) gives angle > 0, so the wheel rotates counter-clockwise. The rim turns the opposite way to the front wheels.",
   "fix": "local angle = math.clamp(yaw * CFG.steerRatio, -7.5, 7.5)"
  },
  {
   "index": 2,
   "real": true,
   "reason": "Confirmed. TrafficCars.processAdoptions calls hideStatic(m, true) on every roads/TrafficVehicles car within 320 studs. That goes through Util.setHidden, which sets the root attribute GwHideState to \"mixed\" and then \"hidden\". It also installs a managed DescendantAdded handler that sets LocalTransparencyModifier = 1 on anything added later, including CabinAAA. This script tracks those statics (VehicleKind \"sedan\", Fit succeeds) and ranks them by distance only, so invisible statics take up the 3 cabin slots.",
   "fix": "-- lodStep loop, right after the `if not m.Parent then ... end` block:\nlocal hs = m:GetAttribute(\"GwHideState\") -- Util.setHidden root state (TrafficCars.hideStatic)\nif hs == \"hidden\" or hs == \"mixed\" then\n\tdestroyCabin(rec)\n\tcontinue\nend"
  },
  {
   "index": 3,
   "real": true,
   "reason": "The defect is real but the trigger is narrow (minor). All drop logic sits inside `if base then`. Once the Underbody streams out, rec.base is nil and the cabin is never destroyed. Every CabinWeld has Part0 = Underbody (or the pivot welded to it), so the unanchored local parts fall. When the Underbody streams back in, rec.cabin is still set and nothing is rebuilt. Stream-out only happens beyond StreamingMinRadius, and the dev comment says 128. A car can still be within 72 of the camera while more than 128 from the character, because StarterPlayer.CameraMaxZoomDistance is 120.",
   "fix": "Store `base = F.base` in rec.cabin. In lodStep, after `base` is resolved and before `if base then`, add:\nif rec.cabin and rec.cabin.base ~= base then destroyCabin(rec) end\n(This is the same check as in fix #0.)"
  },
  {
   "index": 4,
   "real": true,
   "reason": "Confirmed. The Porter II dump has `TurnLamp` parts as direct model children and no `Repeater`. Visuals.isIndicator matches \"turnlamp\", and setTurn switches the part's Material to Neon. turnState only checks `d.Name == \"Repeater\"`, so the Porter cluster arrows never light.",
   "fix": "if d:IsA(\"BasePart\") and (d.Name == \"Repeater\" or d.Name == \"TurnLamp\") and d.Material == Enum.Material.Neon then"
  },
  {
   "index": 5,
   "real": true,
   "reason": "Confirmed. The Carnival's second-row cushions are 1.65 wide at z = 3.0, which is more than seats[1].z + 1.0, so Fit puts them in F.rear. Seats.build only builds rear entries with w >= 2.6. buildCabin still hides every SeatCushion, SeatBack, SeatInsert and Headrest by name. When I applied the proposed fix in the sim, the captain chairs also got a frontSeat belt anchored at F.bZ. That belt is a coplanar duplicate of the front seat's belt (both at (±2.56, 2.9, 1.05)), so the rear belt has to be skipped.",
   "fix": "-- Seats.build\nfor _, s in F.rear do\n\tif s.w >= 2.6 then\n\t\trearBench(K, F, P, s)\n\telse\n\t\tlocal c = table.clone(s); c.rear = true\n\t\tfrontSeat(K, F, P, c) -- captain chair\n\tend\nend\n-- frontSeat: wrap the SeatBelt + BeltAnchor block in `if not s.rear then ... end` (keep the buckle)"
  },
  {
   "index": 6,
   "real": true,
   "reason": "Real race (minor). In Roblox, Clone() copies a client's local Transparency writes and attributes. TrafficModels.offer clones the first complete car of each kind and keeps Interior SeatCushion, SeatBack, Dash, DashTop, WheelHub and Headrest, all of which are in REPLACES. TrafficCars only reaches its first container scan after waiting for GwangalliNav and decoding it. By then this script has usually already hidden the Interior of the nearest complete car (the GS25 and club lots are also re-offered every 2 s). The result is that every traffic car of that kind has no seats, dash or hub for the session. The claim that offers repeat every 2 s for ParkedVehicles/TrafficVehicles is wrong, but the race stands.",
   "fix": "-- buildCabin hide: d:SetAttribute(\"GwCabinT\", d.Transparency); hidden[d] = d.Transparency; d.Transparency = 1\n-- destroyCabin restore: if p.Parent then p.Transparency = old; p:SetAttribute(\"GwCabinT\", nil) end\n-- TrafficModels.offer, right after `local clone = model:Clone()`:\nfor _, d in clone:GetDescendants() do\n\tlocal t = d:GetAttribute(\"GwCabinT\")\n\tif type(t) == \"number\" then (d :: BasePart).Transparency = t; d:SetAttribute(\"GwCabinT\", nil) end\nend\n-- If TrafficModels must not change: run the same loop in track(m) before cars[m] = rec (an untracked model never has a live cabin)."
  },
  {
   "index": 7,
   "real": true,
   "reason": "Same defect as #1, and the analysis is correct: ry = -steer, a right turn gives angle = +14*steer, and Rz(+) about the driver-facing column axis is counter-clockwise for the driver.",
   "fix": "local angle = math.clamp(yaw * CFG.steerRatio, -7.5, 7.5)"
  },
  {
   "index": 8,
   "real": true,
   "reason": "Reproduced with the geometry sim (geo/glasscheck.py and exposed.py on the current code). On the Sonata, BPillarTrim pokes 0.192 through the SideGlass, HeadlinerEdge 0.159, Headliner 0.102 and GrabHandle 0.019. Exposed points include the Headliner at (±2.51, 3.745–3.805) along z -0.23..3.2 and HeadlinerEdge at (2.58, 3.735). With the fix below applied, glasscheck is clean on the Sonata, G80, Carnival and Tucson.",
   "fix": "-- Fit, liner branch: F.linerHalf = sz.X / 2\n-- Trim.build: local lh: number = F.linerHalf or (half - 0.2)\nK:box(\"Headliner\", Vector3.new(lh * 2, 0.06, llen), CFrame.new(0, roofY + 0.02, (lz0 + lz1) / 2), P.fabric)\nK:cyl(\"HeadlinerEdge\", llen, 0.24, CFrame.new(s * (lh - 0.12), roofY - 0.02, (lz0 + lz1) / 2) * CFrame.Angles(0, math.pi / 2, 0), P.fabric)\nlocal gx = g[1] * (lh - 0.1)\nK:seg(\"BPillarTrim\", Vector3.new(side * (half - 0.08), y1, split), Vector3.new(side * (lh - 0.08), F.roofY, split), 0.16, P.fabric)"
  },
  {
   "index": 9,
   "real": true,
   "reason": "Reproduced in the sim. The front HandleCup, DoorHandle and LockTab are 100% inside DashLower on the Sonata (-2.38), G80 (-1.78) and Ray (-2.48). With the fix applied they sit on the door card: the cup is 50% set into DoorSoft, the same as the rear doors.",
   "fix": "local hz = if front then math.max(z0 + 0.42, (F.dashFace :: number) + 0.35) else z0 + 0.42"
  },
  {
   "index": 10,
   "real": true,
   "reason": "Reproduced in the sim. On the Sonata and taxi, four StackButtons are 100% inside ConsoleBody and ClimateGlass has 26% of its face covered. On the Tucson the buttons are 80–100% buried and 64% of the face is covered; on the Carnival 35%. The proposed fix is off: `cpY = max(bandY-0.36, lo+0.22)` pushes the glass top into DashAmbient and the trim band, and it does nothing for the Tucson and Carnival, where the console top is only about 0.1 below the band. The version below is tested: Sonata, G80, Ray and taxi are clear, and the Tucson and Carnival climate faces are clear.",
   "fix": "local lo = math.max(bottom, if F.console then F.console.top + 0.04 else bottom)\nlocal hiY = bandY - 0.115 -- under DashAmbient\nlocal ph = math.min(0.34, hiY - lo - 0.12)\nlocal cpY = (lo + hiY) / 2\nlocal tall = ph < 0.2\nif tall then ph = 0.3; cpY = lo + 0.2 end -- Tucson/Carnival: stack sits on the console, in front of the trim band\n-- ClimateGlass size Y = ph; ClimateBezel size Y = ph + 0.1 (same cpY)\n-- ClimateKnob: CFrame.new(cx + s * 0.86, cpY, if tall then face + 0.075 else face - 0.03)\nlocal btnY = cpY - ph / 2 - 0.1\nif btnY - 0.035 >= lo then -- StackButton row only when it fits\n\tfor i = 0, 5 do K:box(\"StackButton\", Vector3.new(0.17, 0.07, 0.04), CFrame.new(cx - 0.47 + i * 0.188, btnY, face - 0.06), if i == 2 then P.hazard else P.button) end\nend"
  },
  {
   "index": 11,
   "real": true,
   "reason": "Confirmed. In the sim the G80 FloatingScreen comes out at local X = 0.999980, so `math.abs(nvX) < 1` gives cx ≈ 1.0. That moves the vents, ClimateBezel (x 0.29–1.71) and knobs onto the glovebox at x 0.675–1.925, away from the console at x 0. Whether a given G80 lands above or below 1 depends on float32 rounding. The proposed glovebox formula, however, pushes the Ray's glovebox (half 2.12) past the dash edge, so it is clamped below.",
   "fix": "-- Dash.build: compute cx before the glovebox\nlocal cx = if F.console then F.console.x else 0\nlocal gIn = math.abs(cx) + 1.02 -- clear of the passenger climate knob (cx + 0.97)\nlocal gw = math.clamp((half - 0.12) - gIn, 0.6, 1.25)\nlocal gx = -ds * (gIn + gw / 2)"
  },
  {
   "index": 12,
   "real": true,
   "reason": "Same defect as #5. The Carnival's 1.65-wide second-row seats go into F.rear and only rear entries with w >= 2.6 are built, but all their seat parts are hidden. Trim's rear FloorMat uses the same filter. The rear belt has to be skipped, otherwise it z-fights with the front belt (seen in the sim).",
   "fix": "Same as #5:\nfor _, s in F.rear do\n\tif s.w >= 2.6 then rearBench(K, F, P, s) else local c = table.clone(s); c.rear = true; frontSeat(K, F, P, c) end\nend\n-- frontSeat: skip SeatBelt/BeltAnchor when s.rear."
  },
  {
   "index": 13,
   "real": true,
   "reason": "Confirmed. The Carnival dump has four SeatPiping parts (dark 30,34,44; front at z 0.61–0.69, second row at z 3.64). SeatPiping is not in REPLACES, so it stays visible in front of the rebuilt seat backs (or floats on its own in the second row).",
   "fix": "Seats.REPLACES = { \"SeatCushion\", \"SeatBack\", \"SeatInsert\", \"SeatPiping\", \"Headrest\", \"SeatBase\", \"SeatSupport\", \"RearBench\" }"
  },
  {
   "index": 14,
   "real": true,
   "reason": "Reproduced in the sim. Buckle and BuckleRelease are 100% inside ConsoleBody on the Sonata and Carnival. The proposed fix has a sign error: `F.console.x - out * (...)` moves the driver's buckle (out = -1) to the passenger side of the console, and vice versa. With the corrected sign the buckle sits on the seat-side top edge of the console (10% touching the armrest).",
   "fix": "local bkx, bky, bkz = x - out * (w / 2 + 0.06), cushTop + 0.05, zR - 0.2\nlocal con = F.console\nif con and bkz > con.z0 and bkz < con.z1 then\n\tlocal cw = math.min(con.w, 1.15) -- same clamp as Console.build\n\tif math.abs(bkx - con.x) < cw / 2 + 0.05 then\n\t\tbkx = con.x + out * (cw / 2 - 0.05) -- seat side of the console\n\t\tbky = math.max(bky, con.top + 0.12)\n\tend\nend\nlocal buckle = CFrame.new(bkx, bky, bkz) * CFrame.Angles(math.rad(-20), 0, 0)"
  },
  {
   "index": 15,
   "real": true,
   "reason": "Reproduced in the sim (faceocc). DashRoll covers 19% of the ClusterGlass and NavGlass faces on the G80 and Ray, 24% of the Porter cluster, and 52% of the Solati cluster (roll plus WheelRim/RimTrim). With zS = dashFace + 0.15 and the commercial cluster raised to dashTop + 0.23, all of these are clear (the Ray keeps a 2% overlap with the column shroud).",
   "fix": "local zS = math.max(cl.Z, F.dashFace + 0.15)\n-- commercial branch: local yC = math.max(yS, F.dashTop + 0.23); use yC instead of yS for ClusterGlass / ClusterBezel / ClusterHood"
  },
  {
   "index": 16,
   "real": true,
   "reason": "Confirmed in the sim. The Solati has no DoorTrim, so Fit gives halfIn = 2.5 against a 5.96-wide Dash and Floor, and doorZ0..doorZ1 = -7.30..-1.10, which crosses the Partition at -3.48 and the OxygenTank. With the fix: halfIn = 2.96, doorZ1 = -3.60, glasscheck is clean and the door cards stop before the partition.",
   "fix": "-- Fit, before F.halfIn = halfIn:\nif #trims == 0 then\n\tlocal dsh = first({ \"Dash\", \"DashUpper\", \"DashLower\" })\n\tlocal flr = first({ \"Carpet\", \"CabCarpet\", \"Floor\" })\n\thalfIn = (dsh and dsh.Size.X / 2 - 0.02) or (flr and flr.Size.X / 2 - 0.02) or 2.5\nend\n-- before F.doorZ0, F.doorZ1 = doorZ0, doorZ1:\nif #trims == 0 then\n\tlocal pt = first({ \"Partition\" })\n\tif pt then doorZ1 = math.min(doorZ1, U:PointToObjectSpace(pt.Position).Z - pt.Size.Z / 2 - 0.05) end\nend"
  },
  {
   "index": 17,
   "real": true,
   "reason": "Confirmed (exposed.py: Solati DashDeck front edge at (±2.48, 3.275–3.355, -7.70), and DashUpper's front edge at -7.58 is also outside the glass). The proposed fix is wrong in sign: zTop - 0.05 is IN FRONT of the glass, and taking the min with front keeps the deck at -7.58, still 0.07 outside. It also leaves DashUpper poking out. The fix below is tested and leaves no exposed points on the Solati or Sonata.",
   "fix": "local hiW: Vector3 = F.wsHigh\nlocal zTop = ws.Z + math.max(0, top - ws.Y) * (hiW.Z - ws.Z) / math.max(0.01, hiW.Y - ws.Y) -- glass mid-plane z at dash-top height\nlocal zA, zB = zTop + 0.06, face - 0.12 -- deck ends just behind the glass\n-- DashUpper: compute zTop before it and use uf = math.max(front, zTop + 0.06) as its front:\nK:box(\"DashUpper\", Vector3.new(width, upH, face - uf), CFrame.new(0, upperY0 + upH / 2, (uf + face) / 2), P.soft)"
  },
  {
   "index": 18,
   "real": true,
   "reason": "Reproduced in the sim. On the Sonata, SeatBelt is 38% inside BPillarTrim and BeltAnchor 80%. The rear HandleCup and DoorHandle are about 10% occupied by the SeatBelt, and the belt's lower end sits at bz + 0.25, past the pillar. The proposed fix works with the current box trim, but the top x has to follow the trim's inner face once #8 tilts the trim. With the fix below, the belt only touches its own anchor and no longer crosses the rear handle.",
   "fix": "local bz = F.bZ or (zR + 0.2)\nlocal lh: number = F.linerHalf or (half - 0.2)\nlocal y1: number = F.trimY1 or (F.floorY + 2.2)\nlocal ty = F.roofY - 0.55\nlocal tx = (half - 0.08) + (lh - half) * math.clamp((ty - y1) / math.max(0.01, F.roofY - y1), 0, 1) - 0.095 -- 0.015 proud of the B-pillar trim face (box trim: half - 0.105)\nlocal top = Vector3.new(out * tx, ty, bz)\nlocal low = Vector3.new(out * (half - 0.10), cushTop + 0.1, bz - 0.3)"
  },
  {
   "index": 19,
   "real": true,
   "reason": "Confirmed. APillarTrim goes 0.12 through the SideGlass and 0.039 through the Windshield, with exposed stubs at (±2.62, 2.60, -3.22). With the proposed endpoints (wsHalf - 0.06 / - 0.12), the sim still shows the top end through the side glass (Sonata 0.065, G80 0.06, Carnival 0.089), with exposed points at (±2.45, 3.78–3.88). Moving the top end further inboard clears every car.",
   "fix": "local nOut = (hi - ws):Cross(Vector3.xAxis).Unit -- outward windshield normal\nlocal a = Vector3.new(s * (wsHalf - 0.1), ws.Y, ws.Z) - nOut * 0.15\nlocal b = Vector3.new(s * (wsHalf - 0.26), hi.Y, hi.Z) - nOut * 0.15\nK:seg(\"APillarTrim\", a, b, 0.22, P.fabric)"
  },
  {
   "index": 20,
   "real": true,
   "reason": "Confirmed in the sim output. On the Sonata, ClusterGlass spans x -1.93..-0.57 and NavGlass -0.59..0.66; on the G80, -0.62 vs -0.64. Both glasses sit on the same plane (z -1.856), so their SurfaceGuis z-fight in a 0.02 strip. With xL = cl.X - 0.72 there is a 0.04 gap.",
   "fix": "local xL = cl.X - 0.72 -- (= cl.X - (0.04 + clW / 2))\n-- RHD branch: xL, xR = math.min(nv.X - math.max(F.navWide, 1.25) / 2 - 0.06, cl.X - 0.85), cl.X + 0.72"
  },
  {
   "index": 21,
   "real": true,
   "reason": "Confirmed. GloveHandle (y mid-0.0475..mid-0.0125, z face-0.085..-0.055) and the top seam (mid+0.05) sit behind DashTrimBand (y mid-0.065..mid+0.105, z face±0.025). The proposed `gy = mid - 0.33` puts the glovebox bottom at mid - 0.56, below DashLower's bottom on the Sonata (mid - 0.465) and G80, so the bottom seam would float in the air. The version below is tested: the handle is visible on all cars.",
   "fix": "local gTop = mid - 0.1 -- below DashAmbient / trim band\nlocal gBot = math.max(bottom + 0.06, gTop - 0.46)\nlocal gh = gTop - gBot\nlocal gy = (gTop + gBot) / 2\n-- GloveGap / GloveHandle code unchanged (the handle at gy + gh / 2 - 0.08 = mid - 0.18)"
  },
  {
   "index": 22,
   "real": true,
   "reason": "Cosmetic but real. Rx(-8°) maps the +Z face normal to (0, 0.139, 0.990), so MirrorGlass faces upward even though the driver's eye is below and to the side of it. Roblox draws no real mirror image, so the only effect is how the mirror body is oriented.",
   "fix": "local mcf = CFrame.new(mp) * CFrame.Angles(math.rad(6), math.rad(15) * F.side, 0)"
  },
  {
   "index": 23,
   "real": true,
   "reason": "Confirmed. The seams sit at hinge-local z -0.18, while the BenchBackInsert front face is at -0.12 and the back face at -0.09, so they float 0.055 in front of the insert (0% overlap in the sim). With the fix they are flush on the insert (16% contact).",
   "fix": "local mid = hinge * CFrame.new(0, H * 0.32, 0)\nK:box(\"ArmrestSeam\", Vector3.new(0.012, H * 0.5, 0.01), mid * CFrame.new(-0.3, 0, -0.125), P.hardDark)\nK:box(\"ArmrestSeam\", Vector3.new(0.012, H * 0.5, 0.01), mid * CFrame.new(0.3, 0, -0.125), P.hardDark)"
  },
  {
   "index": 24,
   "real": true,
   "reason": "Confirmed (Fit in the sim: the Porter passenger cushion is 2.40 wide at x 1.15, with headrests at 0.55 and 1.75). frontSeat caps w at 1.85 and builds one seat with one headrest. The proposed split as written would give the inner place its own SeatShield and switches inside the outer seat, and a second belt coplanar with the outer one. Skipping the door-side extras on the inner place avoids that; tested with no cross-seat clashes.",
   "fix": "-- Seats.build\nfor _, s in F.front do\n\tif s.w > 2.0 then\n\t\tlocal hw = s.w / 2\n\t\tfor _, dx in { -hw / 2, hw / 2 } do\n\t\t\tlocal p = table.clone(s)\n\t\t\tp.x, p.w, p.head = s.x + dx, hw, nil\n\t\t\tp.inner = math.abs(p.x) < math.abs(s.x)\n\t\t\tfrontSeat(K, F, P, p)\n\t\tend\n\telse\n\t\tfrontSeat(K, F, P, s)\n\tend\nend\n-- frontSeat: wrap SeatShield + both SeatSwitch in `if not s.inner then ... end`, and put `if s.inner then return end` before the SeatBelt block"
  },
  {
   "index": 25,
   "real": true,
   "reason": "Confirmed. On the Ray, SeatSwitch is 52–68% and SeatShield 24% inside DoorArmrest. With the clamped depth they are clear. WindowSwitches also has to move with the armrest; at its old position (inward 0.25) it would hang off the narrower armrest toward the seat.",
   "fix": "local outerSeat = 0\nfor _, s in F.front do outerSeat = math.max(outerSeat, math.abs(s.x) + math.min(s.w, 1.85) / 2 + 0.06) end\nlocal depth = math.clamp(half - outerSeat - 0.02, 0.15, 0.36)\nK:rbox(\"DoorArmrest\", Vector3.new(len * 0.55, 0.13, depth), 0.06, CFrame.new(x + inward * (0.02 + depth / 2), armY, armZ) * CFrame.Angles(0, math.pi / 2, 0), P.leather)\nlocal sw = CFrame.new(x + inward * (0.02 + depth / 2), armY + 0.075, armZ - len * 0.14)"
  },
  {
   "index": 26,
   "real": true,
   "reason": "Same defect as #0, and the analysis is correct. Rig.rig re-clones the near-LOD Interior and adds the DriveWheel Motor6Ds after the cabin already exists, and it sets DriveRigged afterwards. The `mine` cabin is never invalidated, so stale `hidden`/`guis` and an empty `motors` list persist for the whole drive.",
   "fix": "Same as #0. Store interior = F.interior and base = F.base in rec.cabin. In lodStep, before `if base then`: if cab and (cab.base ~= base or cab.interior.Parent ~= m) then destroyCabin(rec) end. Otherwise refresh cab.motors = steerMotors(m) when it is empty and DriveRigged is true. (Comparing a stored `rigged` flag against DriveRigged also works.)"
  },
  {
   "index": 27,
   "real": true,
   "reason": "Same defect as #2. Util.setHidden sets GwHideState on the adopted static root, and its managed DescendantAdded handler hides every cabin part, so the 3 slots go to invisible cars.",
   "fix": "-- lodStep, at the top of the loop body (after the `not m.Parent` block):\nlocal hs = m:GetAttribute(\"GwHideState\")\nif hs == \"hidden\" or hs == \"mixed\" then destroyCabin(rec) continue end"
  },
  {
   "index": 28,
   "real": true,
   "reason": "Confirmed. TrafficModels clones keep VehicleKind and their Interior keeps WheelHub, so Fit passes and they are tracked through Workspace.DescendantAdded. Candidate selection is distance only: no speed, dwell or rank hysteresis. Passing traffic, drive-by parked cars and rank 3/4 swaps as the camera orbits all build a 560–630-part cabin and drop it soon after. TrafficRoot is moved with BulkMoveTo, so speed has to come from position deltas, which the proposed fix does.",
   "fix": "-- lodStep, once per step:\nlocal t = os.clock()\nlocal camV = if lastRp then (rp - lastRp).Magnitude / (t - lastT) else 0\nlastRp, lastT = rp, t\n-- per car, inside `if base then`:\nlocal p = base.Position\nlocal v = if rec.lastT then (p - rec.lastPos).Magnitude / (t - rec.lastT) else 0\nrec.lastPos, rec.lastT = p, t\nrec.still = if v < 8 then (rec.still or 0) + 1 else 0\nlocal ok = rec == mine or rec.cabin ~= nil or (rec.still >= 2 and camV < 25)\n-- add `ok and` to the build branch and insert { rec = rec, d = if rec.cabin then d - 8 else d } (existing cabins win ties)"
  },
  {
   "index": 29,
   "real": true,
   "reason": "Confirmed. A cabin at 52 < d <= 72 matches neither branch, so it is never put in `list` and never counted against the cap, while up to 3 new cabins are built within 52. That gives 5–6 cabins at once.",
   "fix": "elseif (d < CFG.buildRadius or (rec.cabin and d <= CFG.dropRadius)) and (not rec.failed or os.clock() - rec.failedAt > 8) then\n\ttable.insert(list, { rec = rec, d = d })\n-- rank loop: build only inside buildRadius\nelseif e.d < CFG.buildRadius and not e.rec.cabin and not e.rec.building and not building then"
  },
  {
   "index": 30,
   "real": true,
   "reason": "Real under StreamingEnabled (on in the place). Parts of parked/static cars (non-atomic) stream in individually, and lodStep builds as soon as any frame part exists. A missing WheelRim/WheelHub becomes an 8 s failure. Missing DoorTrim, Dash or seats give a degraded fallback cabin that is never rebuilt. The hide pass runs once over F.interior:GetDescendants(), so stock parts and screen SurfaceGuis that arrive later stay visible. The retry shortcut should only apply to streaming-type failures, so cars that genuinely lack anchors do not re-run Fit every step.",
   "fix": "-- lodStep: build only once the Interior stopped changing\nlocal int = m:FindFirstChild(\"Interior\")\nlocal n = if int then #int:GetDescendants() else 0\nlocal settled = n > 0 and n == rec.intN\nrec.intN = n\n-- add `settled` to the build condition (mine excepted)\n-- buildCabin: the DescendantAdded hide connection from fix #0 (disconnected in destroyCabin)\n-- on failure: if Workspace.StreamingEnabled and (why == \"no steering wheel anchors\" or why == \"no Interior\") then rec.failedAt -= 6 end"
  },
  {
   "index": 31,
   "real": true,
   "reason": "Same orphaned-cabin defect as #3: base disappears, all drop logic is inside `if base`, the welds lose Part0, and the cabin is never rebuilt. The premise is off for this place: the dev comment says StreamingMinRadius is 128, so a car 64–72 studs from the character is not streamed out. The trigger is a camera-near car that is more than 128 from the character (zoom up to 120) under low memory. Minor.",
   "fix": "Same as #3/#0: store base = F.base in rec.cabin, and before `if base then` add: if rec.cabin and rec.cabin.base ~= base then destroyCabin(rec) end"
  },
  {
   "index": 32,
   "real": true,
   "reason": "Real (minor perf). Every one of the roughly 270k instances that stream in hits this handler: two IsA calls, a task.defer closure per Model, and a GetAttribute(\"Glass\") call per non-glass BasePart. Every building pane named \"Window\" triggers an ancestor climb. Each streamed-in car glass part queues a full Glass.tint(model) walk, about 8 per sedan. The place itself moved Util.discover to tag mode (one signal per tagged instance) to avoid exactly this per-instance cost.",
   "fix": "Workspace.DescendantAdded:Connect(function(d)\n\tif d.ClassName == \"Model\" then\n\t\tif d:GetAttribute(\"VehicleKind\") ~= nil then task.defer(track, d) end\n\telseif GLASS_NAMES[d.Name] then -- name check only (copy of Glass ROLE keys)\n\t\tlocal p = d.Parent\n\t\tif p and (cars[p] or (p.Parent and cars[p.Parent])) then task.defer(Glass.tintOne, d) end\n\tend\nend)\n-- Glass.tintOne(d) = the body of Glass.tint's loop for one part. Alternative: discover cars via the server's \"NearLOD\" tag on their Interior (CollectionService) plus a per-car DescendantAdded, with no workspace-wide listener."
  },
  {
   "index": 33,
   "real": true,
   "reason": "Confirmed. Kit creates all parts inside a parentless Model and yields every 70 parts. `folder.Parent = rec.model` then inserts about 560–630 parts, as many Welds, the meshes and 3 SurfaceGuis into the world in a single frame. Join building, render registration and DescendantAdded handlers (this script's own, Util's managed roots) all fire in that one frame, so the per-frame budget only spreads the cheap part. Minor hitch, repeated on every build.",
   "fix": "local folder = Instance.new(\"Model\")\nfolder.Name = \"CabinAAA\"\nfolder:SetAttribute(\"GwSkinKeep\", true)\nfolder.Parent = rec.model -- each 70-part slice enters the world in its own frame\n-- declare `folder` outside the pcall and clean up a partial build:\nif not ok and folder then folder:Destroy() end"
  },
  {
   "index": 34,
   "real": true,
   "reason": "Confirmed. The server tags every SurfaceGui GwSurfaceGui, and MobileQuality registers all of them, including car interior screens. On Util.onTierChanged, guiSweep runs applyGui, which writes MaxDistance = md0 (times the tier scale) whenever it differs by more than 0.01, so the 0.01 hide is overwritten. A SurfaceGui still renders on a Transparency = 1 part, so the old cluster, nav and climate screens glow inside the cabin. destroyCabin later restores the previous tier's value.",
   "fix": "-- buildCabin, per hidden gui:\nguiConns[g] = g:GetPropertyChangedSignal(\"MaxDistance\"):Connect(function()\n\tif g.MaxDistance ~= 0.01 then guis[g] = g.MaxDistance; g.MaxDistance = 0.01 end\nend)\n-- destroyCabin: disconnect every guiConns entry BEFORE restoring g.MaxDistance = guis[g]"
  },
  {
   "index": 35,
   "real": true,
   "reason": "Same defect as #6. TrafficModels.offer's `model:Clone()` copies the client's Transparency = 1 on the kept Interior parts (SeatCushion, SeatBack, Dash, DashTop, WheelHub, Headrest). CabinAAA itself is stripped because it is a non-Interior Model, so the traffic template has no seats or dash. The race with TrafficCars' delayed first scan (it waits for GwangalliNav and decodes first) is plausible.",
   "fix": "-- buildCabin: d:SetAttribute(\"GwCabinT\", d.Transparency) before d.Transparency = 1; destroyCabin: p:SetAttribute(\"GwCabinT\", nil) after restoring\n-- TrafficModels.offer, right after `local clone = model:Clone()`:\nfor _, p in clone:GetDescendants() do\n\tlocal t = p:GetAttribute(\"GwCabinT\")\n\tif type(t) == \"number\" then (p :: BasePart).Transparency = t; p:SetAttribute(\"GwCabinT\", nil) end\nend"
  },
  {
   "index": 36,
   "real": true,
   "reason": "Confirmed (minor perf). The sim builds 357 parts (Porter, Solati) to 556–631 parts (sedans, G80), each with its own Weld, not the \"about 400\" in the header. The cap is a fixed maxCabins = 3 (+ the player's own car) with no GwangalliQuality gating, while the other world systems scale by tier. Quality.pick({low, mid, high, saver}) exists in ReplicatedStorage.GwangalliQuality.",
   "fix": "local Quality = require(game:GetService(\"ReplicatedStorage\"):WaitForChild(\"GwangalliQuality\"))\nlocal function maxCabins(): number\n\treturn Quality.pick({ low = 1, mid = 2, high = 3, saver = 0 })\nend\n-- lodStep: if i > maxCabins() + (if mine then 1 else 0) then\n-- (and fix the header comment: ~360-630 parts per cabin)"
  }
 ]
}
```
