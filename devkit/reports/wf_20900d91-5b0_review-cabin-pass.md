# review-cabin-pass (wf_20900d91-5b0)

- status: completed
- failed agents (never finished, usually the usage limit): none

## review:runtime

```json
{
 "findings": [
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Fit.luau",
   "line": 391,
   "title": "Solati: the new short cab headliner puts two passenger grab handles on top of each other",
   "detail": "The new CabHeader block sets the Solati liner to linerZ0=-5.281 and linerZ1=doorZ1=-3.60, so llen is about 1.68. Trim.build (Trim.luau:198) still places a passenger handle at lz0+0.9 and two 'rear' handles at lz0+llen*0.7. Before this diff the liner was the patient-compartment Ceiling, so the rear handles sat behind the partition at z about 5.5-6.1 and could not be seen. I ran the build offline on the real ambulance model (car_304603). The passenger front handle covers z -4.69..-4.07 and the passenger 'rear' handle covers z -4.41..-3.79. Both sit at x 2.79..2.91 and y 5.64..5.80, so they intersect over about 0.3 studs. A third handle also appears over the driver door. No other car is affected, because the block only runs when linerZ0 > doorZ1-0.2.",
   "fix": "When the cabin roof comes from CabHeader (a cab with no rear seats), skip the two rear grab handles. For example, have Fit set a flag such as F.cabRoof=true and skip the {-1,...} and {1,...} entries in Trim when it is set, or skip them whenever #F.rear == 0."
  },
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "line": 171,
   "title": "Solati: the overhead console now sits right above the rear-view mirror, and the mirror stem passes through it",
   "detail": "With the new CabHeader liner, lz0 (-5.281) is 0.18 in front of wsHigh.Z (-5.10). On the other cars it is about 0.6 behind. So OverheadConsole at lz0+0.45 (z -5.08..-4.58, y 5.70..5.82, x ±0.39) lands right on the fallback mirror at hi.Z+0.35 (MirrorBody z -4.92..-4.58, y 5.39..5.66). The MirrorStem runs from (0, roofY+0.02, hi.Z+0.05) to the mirror, and at z -4.95 it is at y ≈5.75, inside the console. The RoofSwitch at z -4.98..-4.92 is pierced too. In the old build the console sat behind the partition (z -3.2..-2.7), where it could not be seen. On every other car (sonata, g80, tucson, carnival, ray, taxi) the console is clear of the mirror.",
   "fix": "Place the overhead console relative to the mirror or windshield top, for example oc z = math.max(lz0 + 0.45, mirrorZ + 0.45). Or, for the CabHeader roof, derive lz0 from math.max(zWs, hi.Z) so the console and the mirror do not share a z range."
  },
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "line": 100,
   "title": "G80: raising the door handle above the wood band pushes the handle cup into the DoorSill roll",
   "detail": "For g == 'wood', bandHi = woodY+0.18 and the new lift sets hy = max(hy, bandHi+0.18). Nothing caps it against the door top y1. On the G80 fixture (car_44149): woodY=2.225, so hy goes from 2.235 to 2.585 while y1=2.695. The HandleCup ellipsoid now covers y 2.50..2.68 at x -2.66..-2.60. The DoorSill roll (diameter 0.14, centre y1-0.02=2.675, x -2.75..-2.61) covers y 2.605..2.745, so the cup's top 0.07 is inside the sill roll. The chrome DoorHandle top (2.62) almost touches it. This happens on all four G80 door cards (front and rear). The IMS buttons move with it to 2.445. Sonata, tucson and carnival are unaffected.",
   "fix": "Cap the lifted value: hy = math.min(math.max(hy, bandHi + lift), y1 - 0.2), so the cup's top (hy+0.09) stays clear of the sill roll (y1-0.09). If it does not fit above the band, keep the handle below the band instead."
  },
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Seats.luau",
   "line": 268,
   "title": "Porter: the full-width SeatRiser swallows the door-card map pockets",
   "detail": "The new riser width is F.halfIn*2-0.12, which covers x ±2.39. The doorCard MapPocket sits at x + inward*0.07 with depth 0.13 (Trim.luau:125). On the Porter fixture (car_14415) that is x -2.47..-2.34, y 0.94..1.16, z -5.79..-4.23. The riser covers x -2.39..2.39, y 0.85..1.49, z -5.40..-3.67. So about 3/4 of each door pocket's length is buried 0.05 inside the riser, with only its front end sticking out. The DoorReflector is also squeezed into the 0.03 gap between the door and the riser.",
   "fix": "Keep the riser clear of the door cards. For example, use w = F.halfIn*2 - 0.4, or about (F.halfIn - 0.2)*2, so it ends inboard of the pocket's inner face (half - 0.335). Another option is to skip or move the door MapPocket for the porter style."
  },
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "line": 311,
   "title": "Ray: the new parking-brake pedal pad is half inside the dash underside",
   "detail": "pb = brake + (side*0.5, 0.42, -0.12). The Ray fixture's Pedal parts are at y 0.905, so the pad centre is at y 1.325. F.dashBottom is 1.335, and DashLower is the box from y 1.335 over z -3.38..-2.13 across the full width. The ParkBrakePedal panel (0.15 tall, tilted -30°) covers y 1.25..1.40 at z -2.72..-2.62, so its upper ~0.065 is inside DashLower. From the driver's eye position the sight line is also blocked by DashLower and DashLowerRoll. In practice the new pedal is mostly buried or hidden.",
   "fix": "Place the pad relative to the dash underside rather than a fixed +0.42 from the brake. For example, pb.Y = math.min(brake.Y + 0.42, F.dashBottom - 0.15), and move it slightly toward the driver (larger z) so it clears DashLower and the knee panel."
  }
 ]
}
```

## review:gating

```json
{
 "findings": [
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "line": 100,
   "title": "G80 door handle is pushed up into the window-sill roll (shared band-clearance logic, G80 not a target car)",
   "detail": "The new garnish-band clearance runs for every garnish type, so the G80 ('wood') is affected too. For 'wood', bandHi = woodY + 0.18. When the armrest sits below the band, hy = max(armY + 0.45, bandHi + 0.18), which is 0.36 above the wood band's centre, and nothing caps it at the top of the door card. I ran the offline sim on the G80 fixture (car_44149): y1 = 2.695, woodY = 2.225, armY = 1.785, which gives hy = 2.585 (it was 2.235 before this diff). On both front and rear doors, HandleCup spans y 2.495..2.675 at x -2.665..-2.605. DoorSill is the cylinder at y1 - 0.02 with diameter 0.14, so it spans y 2.605..2.745 and x -2.75..-2.61. That buries the top 0.07 of the cup inside the sill roll. The chrome DoorHandle capsule (y 2.57..2.62, x -2.63..-2.58) and the LockTab (y 2.56..2.61) also reach into the sill. The interior handle ends up jammed under the window line rather than sitting on the door panel. Sonata, Tucson and Carnival handles stay well below their sills.",
   "fix": "Cap the handle height against the door top, e.g. after the band adjustment add `hy = math.min(hy, y1 - 0.2)` (sill radius 0.07 + cup half-height 0.09 + margin). Alternatively use a smaller clearance for 'wood' (bandHi + ~0.1), or keep the old placement for G80 if the band overlap there was acceptable."
  },
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "line": 198,
   "title": "Solati: new cab-only headliner makes the passenger roof grab handle overlap a 'rear' grab handle",
   "detail": "Fit.luau:383-392 (new) swaps the ambulance's liner span from the patient-compartment Ceiling to the short cab span from CabHeader: linerZ0 = -5.28, linerZ1 = doorZ1 = -3.60, so llen = 1.68. Trim still places one passenger handle at lz0 + 0.9 and two 'rear passenger' handles at lz0 + llen*0.7. Both formulas assume a long cabin. With llen = 1.68, the passenger handle (gz = -4.38, legs from z -4.66 to -4.10) and the rear-right handle (gz = -4.10, z -4.38..-3.82) land at the same x (+lh - 0.1 = 2.88) and the same y, only 0.28 apart. Their segments intersect and their middle bars coincide over z -4.30..-4.18, so the result reads as two crossed grab handles on the passenger side. A third roof handle also appears above the driver's door (x -2.88, z -4.10). The sim confirms 9 GrabHandle segments in the Solati cab after the change. Before the change these handles were behind the partition and did not collide.",
   "fix": "Only build the two rear handles when there is a rear row or a long enough liner, e.g. `if #F.rear > 0 and llen * 0.7 - 0.9 > 0.7 then ... end`, or skip them when `commercial`. Keep the passenger handle only."
  },
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Seats.luau",
   "line": 269,
   "title": "Porter: full-width SeatRiser swallows the lower door map pockets",
   "detail": "The new SeatRiser is w = halfIn*2 - 0.12 wide (x ±2.39 on car_14415) and spans y floor..cushTop-0.26 (0.85..1.49) and z -5.395..-3.67. The unchanged door-card MapPocket in Trim (zbox 0.13 deep at x ±(half+0.02-0.07) = ±2.40, y 0.94..1.16, z -5.79..-4.235) overlaps it over x 2.335..2.39. That covers 1.16 of the pocket's 1.55 length on both doors. Only the front ~0.39 of each pocket shows in front of the riser. The rest is sandwiched between the riser side (2.39) and the DoorLower (inner face 2.42), so the pocket appears to run into the seat box.",
   "fix": "Narrow the riser so it clears the door-card furniture, e.g. `w = F.halfIn * 2 - 0.36` (pocket inner face is at half - 0.115). Or skip or raise the door MapPocket for the porter when the riser is present."
  }
 ]
}
```

## verify:Solati: the new short cab headliner puts

```json
{
 "real": true,
 "reason": "Confirmed by running the build offline on the HEAD sources (git show HEAD:..., not the uncommitted working tree) with car_304603, which resolves to style solati. Before the diff, the old Fit gave linerZ0=-3.40 and linerZ1=9.70, so the rear handles sat behind the partition at z 5.53..6.01, where nobody sees them. After the diff, the new CabHeader block in Fit.luau:382-393 runs because linerZ0 (-3.40) > doorZ1-0.2 (-3.80). It sets linerZ0=-5.281 and linerZ1=doorZ1=-3.600, so llen=1.681. Trim.build (Trim.luau ~197-203) still draws three handles: {-F.side, lz0+0.9}, {-1, lz0+llen*0.7} and {1, lz0+llen*0.7}. Solati has F.side=-1, so the first and third handles both land at x=+2.82..2.85 and y 5.665..5.725 (roofY=5.825). The front passenger handle's segments span z -4.621..-4.141. The 'rear' right handle spans z -4.344..-3.864. Same x and y with about 0.2 studs of z overlap (more counting the 0.05 radius), so two grab handles are fused on the passenger side. A third handle also appears on the driver side at x=-2.85, z -4.34..-3.86, over the driver door, where the old build had nothing in the cab. This is overlapping and misplaced geometry introduced by the diff, and it shows only for cars that take the new CabHeader path (Solati).",
 "fix": "In Fit.luau's CabHeader block, set F.cabRoof = true when the liner is replaced. In Trim.build's handle loop, use only the passenger-front entry {-F.side, lz0+0.9} when F.cabRoof is set, for example: local grabs = if F.cabRoof then { { -F.side, lz0 + 0.9 } } else { { -F.side, lz0 + 0.9 }, { -1, lz0 + llen * 0.7 }, { 1, lz0 + llen * 0.7 } }. Gating on #F.rear == 0 would also change Porter, so the flag is the narrower fix."
}
```

## verify:Solati: the overhead console now sits ri

```json
{
 "real": true,
 "reason": "I confirmed this by running the Solati build (fixture car_304603) at both commits, using a fresh copy of the offline sim in /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/vt_ocmirror (outputs out_old.txt and out_new.txt). The diff's new CabHeader block in Fit.luau only applies to the ambulance. It changes Solati's roofY from 6.055 to 5.825 and linerZ0 from -3.40 to -5.281. hi.Z is -5.10 and the mirror uses the fallback position, mp = (0, 5.525, -4.75).\n\nTrim.luau:171 then places the OverheadConsole at lz0 + 0.45 = -4.831. The console spans x ±0.39, y 5.705..5.825, z -5.081..-4.581. The MirrorBody sits at z about -4.91..-4.59 with its top near y 5.65. So the whole mirror hangs under the console, about 4-5 cm below the map lamps (lamp bottom y 5.693). Those lamps are at x ±0.22, inside the mirror's 0.86 width.\n\nThe MirrorStem runs from (0, 5.845, -5.05) to (0, 5.605, -4.79) with radius 0.03. Its axis enters the console's top face at z -5.028 and leaves the bottom face at z -4.898. About half of the stem's 0.354 length is inside the console.\n\nThe RoofSwitch (y 5.69..5.71, z -4.981..-4.921) is clipped by the stem. Its back edge is 0.012 to 0.027 from the stem axis, inside the 0.03 radius. So the stem comes out of the console right through the edge of the switch.\n\nAt the base commit, the Solati console was at z -2.95, behind the partition (doorZ1 is -3.6), so this is a regression from this diff. On sonata, sonata_taxi, g80, tucson, ray and carnival, the numbers are unchanged between commits, and the console centre is 0.6-0.7 behind the stem centre. The console's front edge sits about 0.2 behind the stem on those cars, with nothing intersecting. Porter's console, which had the same stack-up at the base commit, is removed by this diff.\n\nOne part of the claim's proposed fix does not work. Using lz0 = max(zWs, hi.Z) = -5.10 gives a console at z -4.90..-4.40, which still covers the mirror.",
 "fix": "In Trim.build, work out the mirror position before the headliner block: local mirZ = (F.mirror and F.mirror.Z) or (hi.Z + 0.35), with hi = F.wsHigh. Then set local ocZ = math.max(lz0 + 0.45, mirZ + 0.55) and use oc = CFrame.new(0, roofY - 0.06, ocZ).\n\nThis leaves the other cars where they are now. Their current lz0 + 0.45 is already at least mirZ + 0.6, so the max keeps today's value. For Solati the console moves to about z -4.20 (range -4.45..-3.95).\n\nThat position collides with Solati's DomeLamp at lz0 + llen*0.6 = -4.27, so the dome lamp has to move too. Use dlZ = math.max(lz0 + llen*0.6, ocZ + 0.45). Skip the DomeLamp when dlZ > lz1 - 0.15; for Solati, -3.75 still fits under lz1 = -3.6.\n\nA simpler option is to skip the OverheadConsole, MapLamp, SOS and RoofSwitch on the short CabHeader liner (llen < 2), the same way the diff already gates them off for Porter."
}
```

## verify:G80: raising the door handle above the w

```json
{
 "real": true,
 "reason": "The overlap is real. I generated mods from HEAD and from 724c72d with porterrev/gen.py and ran Trim.build offline on the G80 fixture car_44149 (it resolves to the g80 style) in /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/g80handle/sim/run.luau.\n\nValues on car_44149:\n- y1 is 2.695, dashTop is 2.625 and woodY is 2.225, so bandLo is 2.105 and bandHi is 2.405.\n- armY is 1.785. That is below bandLo, so the new branch at Trim.luau:98-101 sets hy = max(2.235, 2.405 + 0.18) = 2.585. Before the diff hy was 2.235 (front) and 2.285 (rear).\n- HandleCup is an ell 0.06 x 0.18 x 0.46 centred at (+-2.635, 2.585). It spans y 2.495 to 2.675.\n- DoorSill is a cyl with diameter 0.14 (Kit:cyl takes a diameter), so radius 0.07. Its axis runs along Z at (+-2.68, 2.675). Both sills cover the cups' z ranges: front cup at z -1.0, rear cup at z 2.45.\n- In the x-y cross-section, the cup's top (x -2.635, y 2.675) is 0.045 from the sill axis, inside the 0.07 radius.\n- Sampling the cup ellipse against the sill circle gives an overlap over y 2.607 to 2.675. That is about 38% of the cup's height, on all four door cards (left and right, front and rear).\n- The chrome DoorHandle capsule (diameter 0.05) misses the sill by only 0.015.\n\nThe old code did not reach the sill; its cup sat inside the wood band instead. So this clash is new in this diff. The cause is that the lift has no cap against y1. Forcing the g80 style onto the other fixtures shows the same pattern: the cup top lands at the sill axis. On 14415 and 304603 the cup centre ends up above the door top.\n\nSonata uses the 0.11 lift and tucson/carnival use different garnish branches. IMS buttons on car_44149 sit at y 2.445; claimed values are confirmed.",
 "fix": "Cap the lift so the cup's top (hy + 0.09) stays below the sill roll's bottom (y1 - 0.09): hy = math.min(math.max(hy, bandHi + lift), y1 - 0.2). If the capped hy is less than bandHi + 0.09, there is no room above the band, so keep the old armY + 0.45 position. Note that with the cap alone, the G80 hy becomes 2.495 and the IMS buttons at hy - 0.14 = 2.355 land exactly on DoorAmbient (2.355), inside the band. So the IMS row also needs to move: put it level with the cup, fore or aft of it in z, or below bandLo. Do not keep a fixed hy - 0.14 offset for the wood garnish."
}
```

## verify:Porter: the full-width SeatRiser swallow

```json
{
 "real": true,
 "reason": "The claim is correct. I checked it by running the HEAD versions of the modules (the working tree has uncommitted Cockpit and Fit edits, so I exported HEAD instead) in the offline harness with the porter style on car_14415. The bundle is /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/riserchk/mods_head.luau and the runner is /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/riserchk/run.luau.\n\nFit values: halfIn = 2.450, floorY = 0.850, doorZ0 = -7.200, doorZ1 = -3.650, bZ = nil. Because bZ is nil, each side gets one front door card.\n\n- **SeatRiser** (new, Seats.luau:268, gated to porter): the union of its rbox pieces spans x -2.390..2.390, y 0.850..1.490, z -5.395..-3.670, so its side faces sit at ±(halfIn - 0.06).\n- **Door MapPocket** (Trim.luau:125, existing code): zbox at x + inward*0.07 = ±(halfIn - 0.05), depth 0.13. It spans x 2.335..2.465 (mirrored on the left), y 0.940..1.160, z -5.787..-4.235.\n- **Overlap:** the AABB check reports MapPocket against SeatRiser with an overlap of 0.055 in x, the full pocket height in y, and 1.16 of the pocket's 1.55 length in z. That is about 75% of the pocket's length. Its inner face (x = ±2.335) is buried 0.055 inside the riser's side face (±2.39). The front 0.39 (z -5.787..-5.395) sticks out past the riser's front face as a dark block. This happens on both doors.\n- **DoorLower:** inner face at ±2.42, so the gap to the riser is only 0.03.\n- **DoorReflector:** x 2.395..2.425, z -4.05..-3.85. It ends 0.005 short of the riser, so it doesn't intersect but sits hidden in the 0.03 slot, as the claim says.\n\nBefore this diff, Porter had no full-width box here (only a per-seat SeatBase at w*0.78), so the diff introduced the interpenetration. Other cars are unaffected because the riser is gated to porter.\n\nOne correction to the claim's detail: the pocket's inner face is at halfIn - 0.115, not halfIn - 0.335. Both proposed widths still clear it.",
 "fix": "Seats.luau:268: narrow the riser so it ends inboard of the pocket's inner face (halfIn - 0.115). For example, use local w = (F.halfIn - 0.2) * 2, which puts the side faces at ±2.25 on car_14415. That clears the pocket by about 0.085, and the rubber CabinCarpet still covers the floor strip next to the door. The other option is to keep the full-width riser and skip the door MapPocket for porter in Trim.luau doorCard: if S.key ~= \"porter\" then K:zbox(\"MapPocket\", ...) end. The DoorReflector can then stay where it is, or move up above riser height."
}
```

## verify:Ray: the new parking-brake pedal pad is

```json
{
 "real": true,
 "reason": "The claim holds. I ran the Ray fixture (car_43395, Car_Kia Ray) through the offline sim against the HEAD sources taken with git show. I used HEAD rather than the working tree because the working tree has uncommitted Cockpit/Fit edits.\n\nFit gives side = -1, dashBottom = 1.335 and dashFace = -2.05. The fixture has two pedals: (-1.10, 0.905, -2.55), which is the brake after the |X| sort, and (-0.63, 0.735, -2.50), which is the gas. So Trim.luau:311 gives pb = (-1.10 - 0.5, 0.905 + 0.42, -2.55 - 0.12) = (-1.60, 1.325, -2.67). The pad centre ends up 0.01 below the dash underside.\n\nMeasured part extents:\n- **ParkBrakePedal** (panel 0.22 x 0.15, tilted -30 deg): x [-1.71, -1.49], y [1.25, 1.40], z [-2.725, -2.615].\n- **DashLower** (Dash.luau:70, a solid box from dashBottom up to upperY0): x [-2.10, 2.10], y [1.335, 1.955], z [-3.38, -2.13].\n\nThe two boxes overlap fully in x and z. In y, the top 0.065 of the pad's 0.15 height (about 43%) is inside the solid DashLower box. Only a 0.085-high strip shows below the dash underside.\n\nThat strip is also behind the KneePanel (x [-1.875, -0.425], y about [1.0, 1.43], z [-2.38, -2.16]), which lies between the pad and the driver. From the cabin side the pad is effectively buried or hidden. The code comment says the pedal should sit \"below the dash\" (대시 아래), but the pad is placed flush with the underside and partly inside it.\n\nThis is new in the diff: there is no ParkBrakePedal in 724c72d. It is gated to F.style.key == \"ray\", so only the Ray is affected. There is no runtime error; the defect is misplaced, overlapping geometry. The PedalArm running up into the dash is fine, since the brake arm does the same.",
 "fix": "Clamp the pad so it hangs clear of the dash underside. For example, after computing pb:\n\npb = Vector3.new(pb.X, math.min(pb.Y, F.dashBottom - 0.13), pb.Z)\n\nThat puts the tilted pad's top (half-height about 0.075) below dashBottom, with the centre near y 1.205 on the Ray. Keep the arm going up into the dash as it does now. Optionally move the pad slightly toward the driver, but keep it in front of the KneePanel's front face (face - 0.22 - 0.07), so it stays visible below the knee panel's lower edge rather than behind it."
}
```

## verify:G80 door handle is pushed up into the wi

```json
{
 "real": true,
 "reason": "The overlap is real; I reproduced it. I rebuilt the sim modules from 724c72d and from HEAD into /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/g80verify/sim. The working tree has uncommitted Cockpit and Fit edits, so I used HEAD only. I then ran Trim.build on the G80 fixture car_44149 (style g80, garnish 'wood').\n\nValues: y1 = 2.695, woodY = 2.225, bandLo/bandHi = 2.105/2.405, armY = 1.785 on the front door and 1.835 on the rear. Because armY < bandLo, the new branch sets hy = max(armY + 0.45, bandHi + 0.18) = 2.585 on both doors. Before the diff hy was 2.235 (front) and 2.285 (rear).\n\nOverlap: HandleCup is a SpecialMesh sphere (Kit:ell) centred at (-2.635, 2.585) with semi-axes 0.03 in x and 0.09 in y. DoorSill is a true Cylinder with its axis along Z through (-2.680, 2.675) and radius 0.07. The cup's top point (-2.635, 2.675) is only 0.045 from the sill axis. On the cup's centre plane the sill's lower surface is at y ≈ 2.621, so the top ~0.054 of the 0.18-tall cup is buried in the window-sill roll. This happens on the front and rear doors; the cup's z range lies inside the sill length on both. Before the diff the cup top was 2.325 or below, far from the sill, so the diff introduced this. Nothing in the diff caps hy against y1. Worse, woodY can be clamped as high as y1 - 0.3, which would give hy up to y1 + 0.06, putting the handle above the door card.\n\nTwo parts of the claim are wrong:\n1. The G80 is a target, not a bystander. Only sonata and g80 get IMS buttons, so the new non-'line' IMS offset (hy - 0.14) only ever applies to G80. The +0.18 clearance is sized so those G80 IMS buttons clear the band.\n2. Only the cup actually intersects the sill; the chrome handle and LockTab overlap it only by bounding box. The DoorHandle capsule (axis at (-2.605, 2.595), r = 0.025) has about 0.015 of clearance, and the closest corner of LockTab is 0.085 from the sill axis, outside its 0.07 radius.\n\nNet effect: the diff moved the cup from overlapping the wood band to overlapping the sill roll, jammed against the window line.",
 "fix": "Capping the handle alone isn't enough. With `hy = math.min(hy, y1 - 0.2)` (2.495 on this car), the cup clears both the band (top 2.405) and the sill. But the G80 IMS buttons at hy - 0.14 (≈ 2.355) would then fall back onto DoorAmbient (2.355) and just under the DoorChrome lip (2.39): about 0.01 of overlap in x. So also move the non-'line' IMS buttons beside the handle cup (offset in z, at about hy) rather than below it. Or, for 'wood', use hy = min(bandHi + 0.11, y1 - 0.2) and relocate the IMS to match."
}
```

## verify:Solati: new cab-only headliner makes the

```json
{
 "real": true,
 "reason": "The claim holds. I rebuilt the sim modules from the HEAD sources (git show HEAD into /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/grabchk/src, run through porterrev/gen.py) and built the Solati fixture (car_304603, VehicleKind=ambulance, style key solati).\n\nAfter the change: the new block in Fit.luau (around line 383) sets the liner to the cab span from CabHeader, giving linerZ0 = -5.2806 and linerZ1 = doorZ1 = -3.6000, so llen = 1.68. roofY is 5.825, side is -1 and #F.rear is 0. The grab-handle loop in Trim.luau did not change, but it now runs on this short span:\n- Passenger handle: gz = lz0 + 0.9 = -4.381.\n- Two \"rear\" handles: gz = lz0 + llen*0.7 = -4.104, one on each side.\n\nOn +X both handles sit at the same x and y (bar at x 2.82, y 5.665; legs at x 2.85, y 5.725). The passenger handle's middle bar covers z -4.581..-4.181 and the rear-right bar covers z -4.304..-3.904, so the two bars occupy the same space over 0.12 studs, which will z-fight. The passenger handle's rear leg (top at z -4.10) also comes down through the rear handle's bar, and the rear handle's front leg (top at z -4.38) comes down through the passenger handle's bar. The result is two handles fused together above the passenger door. A third handle also appears above the driver door (x -2.85, z -4.10), even though the Solati has no rear row. In total the sim prints 9 GrabHandle parts, all inside the cab (z < -3.6).\n\nBefore the change (old modules, same fixture): linerZ0 was -3.40 and linerZ1 was 9.70. The passenger handle was at z -2.5 and the rear handles at z 5.77, all behind the partition at doorZ1 = -3.6, so none of them were in the cab or overlapping.\n\nSo the overlap comes from this diff and is visible from the cab.",
 "fix": "In Trim.luau, build the two rear roof handles only when there is a rear row and they don't run into the passenger handle. For example, build the handle list first and add the two rear entries only `if #F.rear > 0 and llen * 0.7 - 0.9 > 0.6 then`. For the Solati cab this keeps just the passenger handle at lz0 + 0.9; cars with a rear row and a long liner come out as before."
}
```

## verify:Porter: full-width SeatRiser swallows th

```json
{
 "real": true,
 "reason": "The claim holds. I confirmed it by running the HEAD sources (exported with git show HEAD, not the modified working tree) through the offline luau harness for porter on car_14415. The run had no errors. I copied the harness into /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/riser_pocket_v1/run.luau.\n\nValues from the run: halfIn=2.450, floorY=0.85, doorZ1=-3.650. Front seat cushion top is 1.75, cushSize.Z=1.55, z=-4.70.\n\n- **New SeatRiser** (Seats.luau:259-271, porter only, not in 724c72d): x -2.390..2.390, y 0.85..1.49, z -5.395..-3.670.\n- **Door MapPocket** (Trim.luau:125, unchanged and drawn for every car; front door len=3.45): x ±2.335..±2.465, y 0.94..1.16, z -5.787..-4.235. Its inner face is at half+0.02-0.07-0.065 = half-0.115 = 2.335.\n- **DoorLower inner face**: ±2.420.\n\nThe overlap is the same on both doors: x 2.335..2.390 (0.055 deep), z -5.395..-4.235 (1.16 of the pocket's 1.55 length), and the pocket's full height (0.94..1.16 is inside the riser's 0.85..1.49). Only the front 0.39 of each pocket (z -5.787..-5.395) is in front of the riser. That stub sticks 0.055 past the riser's side and ends in the riser's front face. The rest is buried in the riser's side and in the 0.03 gap between the riser and DoorLower.\n\nBefore this diff, porter had no full-width box there (only the narrow SeatBase), so the pocket was fully visible. This is new interpenetrating geometry caused by the diff, and it shows up on porter.",
 "fix": "Seats.luau:267: narrow the riser so it clears the door-card furniture. The pocket's inner face is at half-0.115, so for example use `local w = F.halfIn * 2 - 0.3` (riser at ±(half-0.15) = ±2.30), and narrow RiserKick to match through its existing `w - 0.1`. Alternative: in Trim.luau doorCard, skip the lower MapPocket for porter, or raise it above the riser top (y > cushTop - 0.26 = 1.49)."
}
```

## review:geometry

```json
{
 "findings": [
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "line": 198,
   "title": "Solati: the new cab-only headliner makes the passenger grab handles intersect, and the mirror stem now passes through the overhead console",
   "detail": "Fit.luau:383-391 (new) now limits the Solati headliner to the cab: roofY = CabHeader underside = 5.825, linerZ0 = -5.28 and linerZ1 = doorZ1 = -3.60, so llen = 1.68. Before this change the liner ran -3.40..9.70 in the patient bay, behind the partition. The grab-handle loop at Trim.luau:198 still uses offsets meant for a full-length liner. It puts the front-passenger handle at lz0+0.9 = -4.38 and both 'rear' handles at lz0+llen*0.7 = -4.10, each spanning gz +/-0.28 at the same x = +/-(lh-0.1) and the same y. On the passenger (+X) side the two handles end up 0.28 apart: one spans z -4.69..-4.07 (sim parts #736-738) and the other -4.41..-3.79 (#742-744). Their grip bars (x 2.795..2.845, y 5.64..5.69) cut through each other over z -4.30..-4.18. A 'rear' handle also lands above the driver. Second problem: the visors and mirror are still placed from hi = wsHigh, whose top (y 6.02, z -5.10) sits above the new roof, while the overhead console now starts at lz0 = -5.28. As a result MirrorStem (0,5.845,-5.05)->(0,5.605,-4.79) runs straight through OverheadConsole (y 5.705..5.825, z -5.08..-4.58) and touches the console's RoofSwitch. The mirror body (y 5.38..5.67, x +/-0.43) hangs about 0.04 under the console, directly below the map lamps. In the old build none of this was visible from the cab because the console and handles were in the patient bay.",
   "fix": "When the liner is short (for example llen < 2.5, or whenever the CabHeader branch in Fit ran), emit only the front-passenger grab handle, or space the handles by at least 0.7. Anchor the mirror stem and visor z to max(hi.Z, lz0), or move the console back so its front edge is behind the mirror (for example oc.Z = max(lz0 + 0.45, mirrorZ + 0.4))."
  },
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Seats.luau",
   "line": 268,
   "title": "Porter: the full-width SeatRiser swallows both door map pockets",
   "detail": "The new riser width w = halfIn*2 - 0.12 makes the box span x +/-2.39, y 0.85..1.49, z -5.40..-3.67. The door-card MapPocket from Trim.luau:125 sits at x +/-2.335..+/-2.465, y 0.94..1.16, z -5.79..-4.24 (0.13 thick, protruding inward from the door at +/-2.42). On both doors, 75% of the pocket's length lies inside the riser and 15-42% of each pocket part's volume is buried (sim parts #609-614 and #661-666). The front 0.39 of the pocket sticks out past the riser's front face at z -5.40 and then disappears into the box. The riser also leaves only a 0.03 slit to the DoorLower inner face at +/-2.42. The old build had seat rails and a base here and no such clash. Pedals and the floor shift lever are clear (the shift plate is about 0.15 in front of the riser face), and so is the recline lever.",
   "fix": "Keep the riser inside the door-trim envelope, for example w = 2*(F.halfIn - 0.2) (so x stays within about +/-2.25). Or, for Porter, skip the door MapPocket or move it forward so it ends before zf = s0.z - cs.Z/2 + 0.08."
  },
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "line": 100,
   "title": "G80 (wood garnish): door handle cup moved up into the window-sill roll",
   "detail": "On G80 the armrest (y 1.72..1.85) is below bandLo, so the new branch sets hy = max(armY+0.45, bandHi+0.18) = woodY+0.36 = 2.585 (it was 2.235). HandleCup is 0.18 tall, so it now spans y 2.495..2.675. That is above the DoorUpper top (2.651) and into the DoorSill roll (cylinder at y about 2.675, radius 0.07, bottom 2.605). The sim reports HandleCup x DoorSill on all four G80 doors. The chrome DoorHandle (top 2.62) and LockTab (top 2.61) sit flush against the sill's underside. The gap between bandHi (2.405) and the sill bottom (2.605) is about 0.20, but the +0.18 offset puts the 0.18-tall cup 0.09 above the band. The fix moved the overlap from the wood band to the sill. Sonata (line), Tucson (waterfall) and Carnival (metal_wood) show no new clash.",
   "fix": "Clamp hy against the sill, for example hy = math.min(hy, y1 - 0.02 - 0.07 - 0.1), so the cup top stays below the sill bottom. Or use offset bandHi + 0.11 for wood as well. If you do, recheck the IMS row at hy - 0.14 so it stays clear of DoorChrome at 2.382..2.398."
  },
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Trim.luau",
   "line": 311,
   "title": "Ray: the new foot parking-brake pedal pad is centred on the dash underside and about 35% buried in DashLower",
   "detail": "pb = brake + (side*0.5, 0.42, -0.12) gives pb.y = 0.905 + 0.42 = 1.325, but F.dashBottom = 1.335. The 0.15-tall pad (y 1.25..1.40, x -1.71..-1.49, z -2.725..-2.615) lies inside the DashLower box (y 1.335 and up, z -3.38..-2.13). By sampled volume, 28-67% of the individual pad parts (#910-915) are inside it, about 35% overall. What sticks out is also behind the DashLower rear edge and the KneePanel from the driver's eye, so the new part reads as a pad sunk into the dash rather than a hanging pedal. It is clear of the FootRest (0.36 below) and the KickPanel.",
   "fix": "Hang the pad below the dash, for example pb.y = math.min(brake.Y + 0.42, F.dashBottom - 0.12). Possibly move it rearward a little (+Z) so it sits below the KneePanel line, and keep the arm going up into the dash."
  },
  {
   "file": "src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Dash.luau",
   "line": 542,
   "title": "Solati: the rewritten GearPod still swallows the right column stalk tip, and the boot grazes the wheel rim",
   "detail": "px = wheel.c.X + toC*0.82 = -0.68 and py = mid - 0.3 = 2.22, so the GearPod ellipsoid (0.5 x 0.56 x 0.64) covers x -0.93..-0.43, y 1.945..2.505, z -6.77..-6.13. The right column stalk tip from Cockpit.luau:66-67 sits at about (-0.77, 2.27, -6.20) and is 100% inside GearPod plus ShiftBoot (point-sampled). The new ShiftBootTop touches WheelRim segment #50 (min distance about 0.005, a point overlap), and ShiftStick passes 0.03 from the rim. The old rbox pod also buried the stalk tip, so this was not newly introduced, but the rewrite did not fix it and the new boot parts add contact with the rim. The pod is clear of the SirenBox (0.05 gap in x) and only covers the left corner of ClimatePlate by about 0.05. The knob is about 0.1 from the rim.",
   "fix": "Move the pod out of the stalk and rim envelope, for example px = F.wheel.c.X + toC*(F.wheel.R + 0.3) and/or py = mid - 0.45, then re-derive the boot and lever from the new pod. Alternatively, shorten the right stalk on Solati."
  }
 ]
}
```

## verify:Porter: the full-width SeatRiser swallow

```json
{
 "real": false,
 "reason": "The claim describes code that is not in the change under review. `git diff 724c72d HEAD` ends at HEAD 65a3f3f (\"review fixes ... Porter riser\"). That commit already replaced `local w = F.halfIn * 2 - 0.12` with `local w = (F.halfIn - 0.2) * 2` at Seats.luau:268. I regenerated the mods from the HEAD source with gen.py and ran the Porter build in the luau sim. The build succeeds (725 parts). SeatRiser is 4.500 wide at x=0, so it spans x -2.25 to +2.25. The door MapPocket parts sit at x -2.400 (0.13 thick) with edge cylinders at -2.385/-2.415 (diameter 0.1), so their inner face is at x -2.335. Both sides are symmetric. That leaves about 0.085 of clearance between the riser side face and each pocket. No pocket part is inside the riser, and the riser no longer leaves the 0.03 slit at the DoorLower face (x 2.42). The RiserKick (4.40 wide) is narrower still. The Y and Z ranges overlap, but the boxes are separated in X, so there is no clash. The claimed numbers (x +/-2.39, 15-42% of the pocket buried) match the intermediate commit cbc1477, not HEAD."
}
```

## verify:Solati: the new cab-only headliner makes

```json
{
 "real": false,
 "reason": "The claim describes code that is not in HEAD. HEAD's Trim.luau already handles both cases. Line 198 builds the grab-handle list as `if F.cabRoof then { { -F.side, lz0 + 0.9 } } else {...three handles...}`, so on the Solati, where Fit sets F.cabRoof = true in the CabHeader branch, only the front-passenger handle is made. Lines 172-176 move the overhead console back with `if F.cabRoof and math.abs(ocz - mz) < 0.45 then ocz = mz + 0.5`, which puts it behind the mirror.\n\nI checked this by running HEAD (and 724c72d for comparison) on the Solati ambulance fixture (car_304603, style solati, side -1) in the offline Luau sim at /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/solati_grabv/run.luau. Fit values: linerZ0 -5.28, linerZ1 -3.60, roofY 5.825, cabRoof true.\n\n- **Grab handles:** HEAD builds exactly one GrabHandle (parts #713-715). It sits at x about 2.79..2.875, z -4.66..-4.10, on the passenger (+X) side. There is no second handle on that side to intersect it, and none above the driver.\n- **Overhead console:** it is centred at z -4.25, spanning about z -4.50..-4.00 and y 5.705..5.825. It does not start at lz0 = -5.28 as the claim says.\n- **Mirror stem:** it runs from (0, 5.845, -5.05) to (0, 5.605, -4.79), so its z range is -5.05..-4.79. That ends at least 0.29 in front of the console's front edge, so the stem cannot pass through the console.\n- **RoofSwitch:** it is at z -4.37, nowhere near the stem.\n- **Mirror body:** it is at about z -4.80..-4.70, also in front of the console.\n- **Sun visors:** they are at x ±(0.56..1.74), clear of both the console and the grab handle.\n\nNone of the claimed intersections exist in HEAD.\n\nUnrelated, minor: on the Solati, the DomeLamp at z -4.27, y 5.805..5.825 sits entirely inside the OverheadConsole's volume. It is hidden, not a visible clash, and it is not what this claim describes."
}
```

## verify:G80 (wood garnish): door handle cup move

```json
{
 "real": false,
 "reason": "The claim does not hold at HEAD (65a3f3f). Its numbers come from a version without the sill clamp. The diff also adds `hy = math.min(hy, y1 - 0.2)` at Trim.luau:102, right after the wood/band branch and before HandleCup is built.\n\nTrace for G80 (car 44149): trimY1 = 2.695, dashTop = 2.625, so woodY = 2.225, bandLo = 2.105 and bandHi = 2.405. The armrest (1.785 front, 1.835 rear) is below bandLo, so the branch sets hy = max(armY + 0.45, 2.405 + 0.18) = 2.585. The clamp then lowers it to min(2.585, 2.695 - 0.2) = 2.495.\n\nI ran the offline sim on sources extracted from HEAD and from 724c72d (/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/hcupv/sim, run2.luau). It confirms these positions on all four G80 doors:\n- HandleCup is centred at y = 2.495 (span 2.405..2.585).\n- DoorHandle is at y = 2.505 (top 2.53).\n- LockTab is at y = 2.495 (top 2.52).\n- DoorSill is a cylinder at y = 2.675 with diameter 0.14, so its bottom is at 2.605.\n\nThe cup top (2.585) sits 0.02 below the sill bottom, and handle and lock tab are well clear of it. The cup bottom (2.405) also clears DoorChrome (2.382..2.398). There is no HandleCup x DoorSill overlap, and the fix the claim proposes (a sill clamp) is already in the code.\n\nSide note, a separate issue and not this claim: on the G80 driver door the new IMS row at hy - 0.14 = 2.355 (y 2.3325..2.3775, x -2.625..-2.595) runs through DoorAmbient (y 2.345..2.365, x -2.63..-2.61). It also touches the top of the wood DoorTrimBand (top 2.345, x out to -2.615). In the base version the IMS row was at 1.995 and clear of both."
}
```

## verify:Ray: the new foot parking-brake pedal pa

```json
{
 "real": false,
 "reason": "The claim describes code that HEAD no longer has. The offset (side*0.5, 0.42, -0.12) was in ac9ae56, 322f95a and cbc1477, but the last commit in the range, 65a3f3f (\"Ray: the foot parking brake sits below the dash underside instead of inside it\"), changed Trim.luau:318 to `local pb = brake + Vector3.new(F.side * 0.55, 0.06, -0.08)`. `git diff 724c72d HEAD` therefore contains the fixed version, and the working tree matches HEAD for this file.\n\nI ran the offline sim on HEAD sources for all 8 cars, using the scratchpad luau and porterrev/gen.py with pbrev/sim/run_all.luau. Nothing errored. Ray is car 43395, with floorY 0.335, dashBottom 1.335 and brake pedal at (-1.10, 0.905, -2.55). There the pad centre is (-1.65, 0.965, -2.63), and its parts #890-895 reach at most y ≈ 1.04. That is about 0.3 below the DashLower underside at y 1.335. A volume-sampling overlap check of every ParkBrakePedal part against every other Ray part finds no overlap with DashLower, KneePanel, FootRest, KickPanel or ToeBoard. The only contact is 0.5% with its own PedalArm, which is intended.\n\nThe FootRest's top edge is at about (y 0.88, z -2.81), well below and ahead of the pad. The arm runs from (-1.65, 1.025, -2.67) up into the dash, as intended. The same check on the pre-fix output (pbrev/sim/out.txt) reproduces the claimed burial: 8-67% of each pad part sits inside DashLower. So the defect existed only in an intermediate commit and is not in the HEAD diff."
}
```

## verify:Solati: the rewritten GearPod still swal

```json
{
 "real": false,
 "reason": "I built Solati (fixture car_304603, which resolves to style \"solati\") with the offline Luau sim at both 724c72d and HEAD. Solati is the only style that uses shifter=\"dash_pod\". The part dumps are in /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/solrev/old.txt and head.txt; the checks are in dist.py and stalk.py in the same folder.\n\n1) Stalk tip: the right StalkTip sits at about (-0.766, 2.273, -6.202). On the sampled surface, 100% of it is hidden at HEAD. It was also 100% hidden in the old code, inside the old rbox GearPod, which spanned x -0.83..-0.53, y 2.085..2.525, z -6.51..-6.11. The Stalk shaft is about 19% hidden in the old code and about 21% at HEAD. So this burial already existed before the diff, and the claim itself says so. The diff did not introduce it.\n\n2) Wheel rim: I measured the minimum signed distance from each shifter part's surface to the WheelRim cylinder segments.\n- New code: GearPod +0.089 (clear), ShiftBoot +0.023, ShiftBootTop -0.005 against segment 50, ShiftStick +0.016, ShiftKnob +0.090.\n- Old code: the GearPod rbox pieces went into the rim by up to 0.051 (-0.024, -0.033 and -0.051 against segment 50). The old ShiftStick was at +0.0145 and the old ShiftBoot at +0.013.\n\nSo the rewrite reduces the shifter's overlap with the rim, from about 0.05 into the rim to a 0.005 touch by ShiftBootTop. A 0.005-stud kiss at the thick 3 o'clock grip is a near-tangent touch, not clearly misplaced or overlapping geometry. Turning the wheel changes it by only a few thousandths, because the rim is a circle and the grip is already at its thickest there.\n\nNo runtime error and no gating mistake is involved. Nothing in this claim is a real defect introduced by the diff."
}
```
