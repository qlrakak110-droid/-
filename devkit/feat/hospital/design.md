> **사장님 지시: "장애인" 글자와 ♿ 기호는 게임 어디에도 넣지 않습니다.** 이 설계 문서의 화장실 칸은 "넓은 칸"으로 표기합니다(구현된 코드도 같음).

# 광안 메디컬 의원: facility layer (HospitalPlus), research and detailed design

Owner request: "병원도 내부 구현해 나갈수 있는 문이랑 등등 다 구현해서 AAA급 시설 퀄리티". Every door must be one you can actually go through and come back out of, and the building must work as a real facility.
This layer is client-only (one LocalScript world, `GwInteriorDetailLocal/HospitalPlus`). It does not touch the server, other players or gameplay contracts.
T_clinic.luau (being written by another agent) dresses the 11 rooms. This layer owns doors, passages, the elevator, new rooms, exits, the roof and wayfinding.

---------------------------------------------------------------------------------------------------

## 0. Key findings and decisions (read first)

| # | Finding / decision |
|---|---|
| F1 | **The 2F stair hall is sealed (map bug).** The 1F→2F stair arrives in `LandingHall` (local x -8.09..19.91). CheckupWall (west), LoungeWall (east), BackWall2 piece x -8.09..33.91 (south) and PartyWall (north) all run full length, so a player who walks up the stairs cannot leave except by going back down. The BackWall2 gap at x -12.09..-8.09 opens into the checkup centre, not into the hall. **Fix:** a new 3.6-wide passage in BackWall2 at x -7.60..-4.00 (local replacement wall plus a held-open 방화문). See §7.7. |
| F2 | **`init.client.luau` never builds hospital rooms in the live game.** `venueScan()` (line 235) filters with `skipped(f.model)`, and `SKIP_ROOTS` (line 104) contains `"hospital"`, `"garage"`, `"club"` and `"bowling"`. The whole `T_clinic` output (and the garage/club/bowling venue rooms) is therefore dead in-game. Only the offline sim (which bypasses init) shows it. Patch in §11 (not my file). HospitalPlus does not depend on it. |
| F3 | Only one position check matters for client teleports: **Jobs.luau:1304-1319** (`TELEPORT_JUMP = 160` studs between 0.5 s ticks, for players on a job shift → `s.teleported` halves task pay). Every teleport in this design is ≤ 95 studs. No noclip, speed or anti-teleport kick exists anywhere. |
| F4 | Hidden location for portal rooms: **directly under the hospital, local y -50 (world y -43.1 … -22.6)**. Below the FarGround foundation slab (bottom y -12), above FallenPartsDestroyHeight (-120). place.bin has 0 parts there, there are no terrain ops, and no script parks anything there. Every jump stays < 160, the area stays inside the streaming MinRadius of the hospital, and other players cannot see a floating avatar (§2.16). |
| F5 | **The elevator is in place, not a fade portal.** A shaft enclosure protrudes 5.5 studs from the back wall on 1F and 2F, with a new penthouse on the roof, all at the existing fake-elevator x. One cabin model moves between floors. At arrival the cabin and the passenger are shifted vertically in the same render frame while the doors are closed (seamless, no fade). The Law/Hospital NPC lift spots (-548,332) end exactly at the new doors, so NPC rides are animated as well (§7.3). |
| F6 | **The ER entrance and fire exit are real walk-through passages.** The east wall `GroundSide` (one 74.8-long part) is hidden locally and its local collision is turned off. Identical replacement segments with two openings are drawn first (allowed: "keep its collision unless you provide the passage"). The 2F `BackWall2` piece gets the same treatment. No step-teleport is needed; a fallback mode is in §12. |
| F7 | The 5 map glass doors (`Door_*`) are **sliding doors parked open**: the leaf sits beside the opening. Three door signs face the wrong side or sit above the 2F ceiling (2F CeilingBoard bottom = world 29.5; signs at 30.35), so they are invisible from the corridors. This layer animates real leaves and adds corridor-side name plates. |
| F8 | The roof view to 광안대교 is **blocked** by the beachfront row (광안샤인빌딩 Core top y 94-108, 파스쿠찌 센트로, 호텔 바다, all about 100 studs south). The telescope therefore uses a raised virtual eye (raycast search, §7.8). |
| F9 | T_clinic already does a lot in the back hall: floor overlay, baseboards, wainscot, stair nosing, exit sign above the fire exit, hydrant, bulletin board, floor directory and hang signs. Ownership split and coordination requests are in §3. |

---------------------------------------------------------------------------------------------------

## 1. Frames and conventions

**Hospital frame HF** (all coordinates in this document are HF-local unless marked W):

```lua
-- Hosp_Geo
local HF = CFrame.new(-515, 6.9, 300) * CFrame.Angles(0, math.rad(-1.8747), 0)
-- HF.XVector = (0.999465, 0, 0.032713)  ≈ world +X (east, ambulance bay)
-- HF.ZVector = (-0.032713, 0, 0.999465) ≈ world +Z (north, back yard)
-- y_local = y_world - 6.9  (1F floor top = 0, 2F floor top = 14.15, roof top = 25.2)
local function W(x: number, y: number, z: number): Vector3 return HF * Vector3.new(x, y, z) end
local function L(p: Vector3): Vector3 return HF:PointToObjectSpace(p) end
```

* Directions: south = -z (street/facade, z ≈ -36), north = +z (back wall z 38.78), east = +x (GroundSide x 59.11), west = -x (GroundSide x -59.29).
* The map parts' own rotation is Ry(178.125°): their X axis is -HF.X. R00 = -0.99946594 and R02 = 0.03271484 were read exactly from place.bin.
* Validation at runtime: GroundBack must be at W(-516.3695, 13.2, 339.1512) = L(-0.09, 6.30, 39.18). If the live part is more than 0.5 studs off, rebuild HF as `GroundBack.CFrame * (GB_EXPECTED:Inverse() * HF)` and log it. The keep zones (registered before the map exists) use the constants.
* Scale: 1 stud ≈ 0.28 m. Character ≈ 5 studs. Doors are 2.0-2.1 m = 7.2-7.6 studs.
* Look values below use `Look.lua` names or `(r,g,b, Material)`.

---------------------------------------------------------------------------------------------------

## 2. Survey (exact geometry; sources: dump.json + place.bin exact CFrames)

### 2.1 Shell and key parts (HF-local AABB; W = world centre; collide: default = true)

| Part (path under `hospital['광안 메디컬 의원']` unless 건물) | local min .. max | W centre / size | notes |
|---|---|---|---|
| 1F/Floor | (-59.29,-0.30,-34.83)..(59.11,0.00,38.78) | (-515.15,6.75,301.97) 118.4×0.3×73.6 | SmoothPlastic (222,224,222) |
| GroundSide **east** | (59.11,-0.40,-35.22)..(59.91,13.00,39.58) | (-455.59,13.20,304.12) 0.8×13.4×74.8 | Concrete (196,188,174). Exterior and interior face; 1F east wall of waiting, treat and back hall |
| GroundSide west | (-60.09,-0.40,-35.23)..(-59.29,13.00,39.58) | (-574.73,13.20,300.22) | same |
| GroundBack | (-59.29,-0.40,38.78)..(59.11,13.00,39.58) | (-516.37,13.20,339.15) 118.4×13.4×0.8 | 1F back exterior wall |
| 1F/BackWall (two pieces) | x -59.29..-0.09 and 11.91..59.11, z 21.58..22.18, y 0..11 | | Plaster; south side of back hall; gap x -0.09..11.91 = mid hall |
| 1F/Ceiling1F/CeilingBoard | y 11.00..11.30 | world bottom 17.90 | TBar 10.90..11.00, LightPanel slabs 10.86..11.00 |
| 2F/Floor2 ×4 | top y 14.15; void x -3.33..19.31, z 23.58..36.58 | | |
| 2F/Ceiling2F/CeilingBoard | y 22.60..22.90 | world bottom 29.50 | |
| 건물/PartyWall back | (-59.99,13.60,38.94)..(59.81,24.60,39.55) | (-516.37,26.00,339.22) | 2F back wall, Concrete (184,182,176), 0.6 thick |
| 건물/PartyWall east/west | x 59.28..59.88 / -60.06..-59.46, y 13.6..24.6 | | 2F side walls; small windows at z 18.93..22.13 / -18.97..-15.77, y 17.6..21.1 |
| 2F/BackWall2 (four pieces) | z -4.42..-3.82, y 14.15..22.60; x 39.91..59.11 / **-8.09..33.91** / -20.09..-12.09 / -59.29..-28.09 | piece 2: W(-501.96,25.27,296.30) 42×8.45×0.6 | Plaster (222,218,208). Piece 2 = landing hall south wall (F1) |
| 2F/CheckupWall | (-8.69,14.15,-3.82)..(-8.09,22.60,38.78) | | full length (no door) |
| 2F/LoungeWall | (19.91,14.15,-3.82)..(20.51,22.60,38.78) | | full length (no door) |
| 건물/Roof | (-60.04,24.60,-36.38)..(59.86,25.20,39.53) | (-515.14,31.80,301.57) | top = **25.20** (W 32.10) |
| 건물/Parapet ×4 | y 24.60..28.10; front z -36.53..-35.72, back z 38.87..39.58, east x 59.21..59.91, west x -60.09..-59.39 | | Metal (70,74,78); Coping y 28.10..28.42 |
| 건물/Penthouse | (33.39,25.20,-2.22)..(42.88,34.20,7.78) | (-476.98,36.60,304.02) 9.49×9×10 | **solid block**; stair head over the lounge |
| 건물/RoofDoor | (36.53,25.20,-2.32)..(39.73,32.20,-2.02) | (-476.81,35.60,299.07) 3.2×7×0.3 | Metal, collidable, faces south |
| 건물/WaterTank (+2 TankStand) | (-12.86,25.20,17.93)..(-6.86,32.20,23.93) | | |
| 건물/ACSkid + 3 ACCondenser | (-17.23,25.20,-17.56)..(-6.43,28.92,-13.96) | | |
| 건물/VentStack | (-19.41,25.20,7.90)..(-18.68,28.26,8.62) | | |
| 건물/RoofPatch | (-46.94,25.10,1.12)..(10.76,25.28,30.72) | | greenish Concrete (77,113,88); flat |
| PlotPaving (outside) | top y -0.34 | (-515.83,6.33,322.56) 168.6×0.46×138 | outside is 0.34 below the inside floor |

### 2.2 Wall thickness at each door

| Door | Wall part | Thickness | Inner face | Outer face |
|---|---|---|---|---|
| 남/여 화장실 (fake), STAFF ONLY, 창고, fake elevator | GroundBack | 0.80 | z 38.78 | z 39.58 (back yard) |
| 비상구 (FireExitDoor) | GroundSide east | 0.80 | x 59.11 | x 59.91 |
| new 응급실 출입구 | GroundSide east | 0.80 | x 59.11 | x 59.91 |
| 2F elevator (new) | PartyWall back (not cut: enclosure inside) | 0.60 | z 38.94 | 39.55 |
| 2F roof-stair door (new, portal) | PartyWall back | 0.60 | z 38.94 | |
| 2F landing passage (new) | BackWall2 piece 2 | 0.60 | z -3.82 (landing) | z -4.42 (corridor) |
| Door_진료실 1 · 내과 | ConsultWall | 0.60 | opening x -22.09..-18.09, z -6.42..-5.82 | |
| Door_주사실 · 처치실 | TreatWall | 0.60 | opening x 25.91..29.91, z -2.42..-1.82 | |
| Door_입원실 201 / 202 | WardWall | 0.60 | openings x 17.91..21.91 / -22.09..-18.09, z -10.42..-9.82 | |
| Door_건강검진센터 | BackWall2 | 0.60 | opening x -28.09..-20.09 (8 wide), z -4.42..-3.82 | |
| RoofDoor | Penthouse (solid 9.49×10 block) | n/a | | face z -2.22 |

### 2.3 1F back hall: west end free volume (restrooms in place)

Back hall interior: x -59.29..59.11, z 22.18 (BackWall north face) .. 38.78 (GroundBack), y 0..10.86. Light slabs: 112×4 at z 24.57..28.58 and 112×3 at z 33.58..36.58.
**Free west end: x -59.29..-35.0, z 22.18..38.78, y 0..10.86** = W(-575.53,6.90,320.23)..(-550.71,17.76,337.61). Contents:
* `BackZone/Plant` pot x -58.62..-56.76, z 23.25..25.10 (stays).
* Fake `Door_남자 화장실` (leaf x -50.09..-46.09) and `Door_여자 화장실` (x -56.09..-52.09) flush on GroundBack, z 38.57..38.82, all CanCollide=false.
* CCTV dome at x -36.49..-35.69, z 23.18..23.98, y 10.4..11.2.
* No NPC spot or lane west of x -33.6 (lift1 = (-31.9, 33.1)).

### 2.4 Fake elevator and 2F checkup back wall

* 1F (BackZone, at the GroundBack face): ElevatorJamb ×2 x -34.79..-34.29 / -29.89..-29.39 (z 38.48..38.78, y 0..9.10, **collidable**). ElevatorHead y 8.60..9.10. ElevatorDoor ×2 x -34.29..-32.13 / -32.05..-29.89, z 38.60..38.76, y 0..8.60, **collidable**. FloorIndicator neon at y 8.68..9.02. CallButton x -35.69..-35.19, y 3.2..4.4. Sign_엘리베이터 x -33.69..-30.49, y 9.5..10.5. Behind it: GroundBack, then the back yard (no shaft).
* 2F at the same x: PartyWall inner face z 38.94. Floor2 covers up to z 38.78 (0.16 gap). In the way: **`CheckupCenter/Sign_건강검진 안내`** x -34.09..-26.09, y 19.95..23.95 (top 1.35 above the ceiling), z 38.68..38.80. Nearby: CheckupBed x -51.79..-46.14, z 27.93..35.23; ECGCart x -41.09..-38.09, z 27.58..29.98; HearingBooth x -20.09..-12.09, z 25.58..33.58; LightPanel 44×8 z 25.57..33.58 (y 22.46).
* Roof above the shaft (x -36.6..-27.6, z 30.5..38.87): **empty** (only the back Coping at z 38.83).

### 2.5 East wall at the 주사실 and ambulance bay

* Treatment room: x 12.51..59.11, z -1.82..21.58. Along the east wall: Plant pot x 55.98..57.84, z -0.75..1.10. TreatBed1 x 48.21..51.61, z 3.93..11.23 (curtain rail to z 11.68; BedsideCabinet x 52.01..53.81, z 8.88..10.68). MedicineCabinet x 39.91..55.91, z 18.58..21.48. **Free strip x 54.2..59.11, z 11.7..18.5.**
* BedSeat TreatBed1 W(-465.34,8.80,308.60) = L(49.95,1.90,6.97). Patients.TRANSIT W(-465.3,9.6,304.5) = L(49.82,2.70,2.87).
* Outside (x > 59.91): PlotPaving only. AmbulanceBay BayLine x 60.91..82.91, z -34.42..3.58. Car_Ambulance x 68.11..76.71, z -26.83..-6.01. Bollards at (72.4, 4.6) and (72.4, -35.4). Law/Rescue BAY = L(72.6, -12.4). BaySign x 83.4. 2F east window above at z 18.93..22.13, y 17.6..21.1.

### 2.6 Fire exit and what is outside

* `BackZone/FireExitDoor`: x 59.11..59.31, z 27.58..31.58, y 0..8 (Metal (140,144,148), **collidable**). PushBar x 58.71..59.11, z 28.18..28.98, y 3.6..4.4 (red). ExitSign x 58.76..59.11, y 8.75..9.85, z 28.08..31.08 (**hidden and replaced by T_clinic**). FireExtinguisher x 57.92..58.70, z 25.19..25.96.
* Outside: open PlotPaving (no part in x 59.9..90, z 15..45). Nothing else.

### 2.7 Stair geometry

* 17 solid `Step` boxes, each 1.33 run (x) × 10 wide (z 25.08..35.08), rising 0.83 toward -x. Bottom step x 17.98..19.31 (top 0.83), top step x -3.33..-2.00 (top 14.15 = 2F floor).
* Rails at z 24.75..25.01 and 35.15..35.41 (`Rail` collidable, posts/MidRail not). 2F void glass rails (`RailGlass`, collidable, t 0.6) at z 23.32..23.44 and 36.72..36.84 for x -3.73..19.31.
* T_clinic adds nosing, treads and stringers. This layer **does not touch** the stair or its volume.
* 2F arrival: landing x -8.09..-3.33, z 23.58..36.58, plus the strip z 36.58..38.78 behind the void. **Sealed room (F1).**

### 2.8 Roof walkable area

* Inside the parapets: x -59.39..59.21, z -35.72..38.87, top y 25.20 (RoofPatch 25.28). Parapet + coping = 3.22 above the roof top (jumpable).
* Obstacles: WaterTank, ACSkid, VentStack, Penthouse (§2.1).
* View: the bridge suspension section spans W x -1606..1606, z -3372..-3228, towers to y 391, about 3,600 studs south. Every sight line from the roof (E = W(-529,40.5,262)) to bridge points x -1500..300, y 200-300 is blocked about 100 studs out by 파스쿠찌 센트로 / 광안샤인빌딩 / 호텔 바다 (top y 94-108).

### 2.9 Glass room doors (Door_* models)

Each model: Jamb ×2 (collidable), Head, DoorLeaf (Glass t0.35, **CanCollide=false**), LeafRail ×2 (cc false), Handle (cc false), Sign_*. The leaf is **parked beside the opening** (open position):

| Door | Opening x (inner jamb faces) | Leaf plane z / side | Parked leaf x | Slide to open |
|---|---|---|---|---|
| 진료실 1 · 내과 (1F) | -22.09..-18.09 | -6.59 (room side) | -26.39..-22.39 | -x 4.30 |
| 주사실 · 처치실 (1F) | 25.91..29.91 | -2.59 (corridor side) | 30.21..34.21 | +x 4.30 |
| 입원실 201 (2F) | 17.91..21.91 | -10.59 (ward side) | 13.61..17.61 | -x 4.30 |
| 입원실 202 (2F) | -22.09..-18.09 | -10.59 (ward side) | -26.39..-22.39 | -x 4.30 |
| 건강검진센터 (2F) | -28.09..-20.09 | -4.59 (corridor side) | -36.39..-28.39 | -x 8.30 |

Signs: 진료실 1 is on the room side; 입원실 201/202 are on the ward side and at y 22.8..24.1, above the 2F ceiling (22.6); 건강검진센터 and Sign_휴게실 / Sign_계단 · 비상구 are on the corridor side but also above the 2F ceiling. All are invisible from the corridors.

### 2.10 StreamingEnabled and world properties (place.bin Workspace)

`StreamingEnabled = true`. StreamingMinRadius, TargetRadius, IntegrityMode and StreamOutBehavior are not set (engine defaults, Min 64 / Target 1024). `FallenPartsDestroyHeight = -120`. No terrain voxels are saved. Terrain is filled at runtime by GwangalliEnvironment → TerrainBaker from `GwangalliTerrainOps` (water, beach sand/salt; no op within x -660..-380, z 200..450).

### 2.11 Anti-teleport / position checks (all server and client scripts grepped)

| Where | What | Impact |
|---|---|---|
| `ServerScriptService/GwangalliGameplay/Jobs.ModuleScript.luau:1304` `local TELEPORT_JUMP = 160` and `:1317` `if s.lastPos and (pos - s.lastPos).Magnitude > TELEPORT_JUMP and not ctx.teleportAllowed(player) and not ctx.isRiding(player) then s.teleported = true` (tick every 0.5 s, `:1528`) | players **on a job shift**; consequences `:770` / `:999` / `:1097` and `JobDelivery.ModuleScript.luau:525` halve the pay | keep every client jump < 160 (max here 95) |
| `GwangalliGameplay.Script.luau:149-157` `ctx.allowTeleport / teleportAllowed` | server-side whitelist window | not reachable from the client; not needed |
| `Taxi.ModuleScript.luau:81` `movedLimit = 6` | taxi riders only | n/a (block portals while seated) |
| `GwangalliBuildings/Annex.ModuleScript.luau:938` | instance players below ORIGIN.Y-80 | Annex band y > 2500 only |
| `GwangalliLivingConfig.ModuleScript.luau:135` `kickToCorridor` | inside home units (y ≥ 900 band) | n/a |
| `CarServer.Script.luau:1714` `if root.Position.Y < -50 then model:Destroy()` | player **cars** only | n/a (portal floor W y -43.1 anyway) |
| `GwangalliGameplay/Interact.ModuleScript.luau:1674` | beach balls y < -20 | n/a |

No noclip, speed or "inside wall" checks exist. Server teleports that can interrupt a portal stay: Health collapse → ward bed (`Health.ModuleScript.luau:364-375`, `Util.teleportTo`), seatOnExamBed, Ems Patients → TRANSIT. These are handled in §7.1.

### 2.12 Law/Hospital NPC contract (`Law/Hospital.ModuleScript.luau`)

* Active when any player is within **flat** 170 of CENTER (-515,7,300); the underground portal rooms stay active. Actors live in `Workspace.GwangalliNPCs` with attributes `NpcKind="hospital"` and `HospitalRole` (doctor/nurse/reception/patient/inpatient/guardian/er).
* Walk grid built once from SERVER parts (passable: names with Leaf/Threshold/Track/Prompt/Floor/Rug/Mat, CanCollide=false; `Door_*` / `AutoDoor*` footprints carved). Client parts are invisible to it.
* **Lift:** the route leg `lift1 → lift2` calls `P.standAt(o, leg.pts[1])` (pivot to the other floor), then `model.Parent = nil` for 3-5 s, then `Parent = home` (`:471-489`). On the client the model vanishes at lift1 and reappears at lift2 (same xz, other floor).
* Spots (HF local x,z). 1F: fore(17.4,-48.6) door(18.0,-30.6) lobby(9.2,-24.3) desk_front(-0.6,-19.0) desk(11.5,-16.4) wait1..3(48.2..48.5,-26.6/-20.6/-14.6) hall(10.0,-0.3) hall2(-10.2,-5.7) **bench(-4.1,28.1)** pharm(-25.2,-5.2) cons_door(-22.1,-2.3) cons(-30.5,-14.0) treat_door(29.9,-5.0) treat(37.2,6.8) treat_bed(47.3,7.5) **lift1(-31.9,33.1)**. 2F: **lift2(-31.9,33.1)** landing(-25.2,-5.2) corr2(-5.3,-9.8) station(-0.5,-16.0) w201_door(17.8,-7.6) w201(34.4,-18.1) w201_bed(48.4,-19.6) w202_door(-22.2,-7.3) w202(-35.6,-17.8) w202_bed(-25.6,-18.2) check_door(-28.1,-1.1) check(-36.6,13.2) lounge(37.3,9.8).
* Corridors that must stay clear are the T_clinic `LANES1/LANES2` polylines (half width 1.25). Relevant to this layer: `bench → lift1` (passes z ≈ 32.4 at x -28.3: it skims the front-east corner of the new lift enclosure, which is acceptable because the NPC vanishes at the doors); `pharm → lift1` via the mid hall; `lift2 → check → check_door` (south, clear); `w201_door → (36.25,-5.19) → lounge` through the lounge opening x 33.91..39.91 (this is why no stair can go into the Penthouse footprint).

### 2.13 GwangalliDoors contract (`ServerScriptService/GwangalliDoors.Script.luau`, client `GwangalliDoorsClient`)

Tag `AutoDoor` Model. Leaves carry `OpenOffset` (world Vector3). The server sets `Open`, `OpenChangedAt`, `ClosedCFrame` and `Collides`, and toggles collision. The client slides locally, predicting at Radius+4 (Radius 10). **This layer never tags `AutoDoor` / `AutoDoorOpener`** (the client script would adopt the leaves and never close them; init.client would treat the parent as a shop candidate). `AutoDoor_Hospital` (doorway x -500..-491.9, z 264.5..268) is untouched.

### 2.14 Health / EMS contracts (`GwangalliGameplay/Health.ModuleScript.luau`, `Play/Ems/Patients`)

Do not move, hide or rename: `HospitalPrompt_desk` L(-0.12,2.5,-18.81), `HospitalPrompt_doctor` L(-40.07,2.5,-19.80) and their prompts; the 8 `HospitalBed` BedSeats; the `HospitalStaff` rigs and Motor6Ds; GwProp syringe parts; `Destination '광안메디컬'` L(17.92,0.2,-39.41); `AmbulanceBay/Car_Ambulance` (template).
Character attributes used here (read-only): `GwTreating` (Health, during treatment) drives the 진료 중 lamp. `GwKO` (Combat), `GwEmsPatient` (Ems) and player `GwCollapse` (Health) block portals. `nearClinic` uses anchor distance + 26, so a player inside a portal room is "far". This is harmless and expected.

### 2.15 Client systems this layer touches

* `GwangalliTextures` adds `Texture` children named **`GwangalliTex`** (grime) to nearby Concrete/Plaster faces and skips parts with Transparency > 0.2 or under `LOD="near"` roots (our root). A Texture on a hidden part still renders, so hidden map walls must hide new `GwangalliTex` children (ChildAdded hook). Optionally clone them onto the replacement segments.
* `Scan.hide/reapply/restore`: per-store original transparency. This layer hides only parts that T_clinic does not (ownership list §3), so stores never overlap (optional ref-count patch in §11).
* Kit parts default to `CanQuery=false`, `CastShadow=false`, `CanCollide=false`. Structural parts here must set `CanQuery=true` (camera popper) and `CastShadow=true` (portal rooms are lit only by their own lights).
* init's anim loop only animates venue recs. HospitalPlus runs its own 10 Hz loop over its zones' `K.anims`.
* `Interact.prompt` refuses prompts closer than 2.5 to another prompt of the same K. Fixture spacing below respects this.

### 2.16 Hidden location for portal rooms (proof)

Chosen box (all three rooms plus shells): **local x -31..-1, y -51..-29.5, z -25..37 = W(-547.2,-44.1,274.0)..(-515.2,-22.6,336.9)**.
* place.bin AABB scan of 256,801 parts: `W x -560..-500, y -119..-12.01, z 260..350` → **0 parts**. Up to y 0 → only the two `roads/FarGround (persistent foundations)/Foundation` slabs (y -12.0..5.9).
* Terrain: 2,063 Block/Wedge + 384 Ball/Cylinder ops in GwangalliTerrainOps; none intersect x -660..-380 × z 200..450. The nearest are beach sand/salt at z ≤ +30, more than 240 studs away.
* Scripts parking things underground: `StreetInteract/Routine:485` (GS25 door feet −60, W x≈-311), `GwangalliStaff:1965` (GS25/Starbucks −30), `GwangalliAmbience/Env HIDDEN_CF (0,-500,0)`, `DroneFormations (x,-150,0)`. All more than 200 studs away.
* Bands used by other systems: homes y ≥ 900, Annex y ≥ 2500. Not in conflict.
* Teleport distances: STAFF door↔room 53.4, 창고 55.3, 2F door↔stair bottom 90.4, RoofDoor↔stair top 79.5 (all < 160). The hospital floors are 50-65 studs above, inside StreamingMinRadius 64 to the 1F floor, so the map stays streamed. Other players see the avatar underground, not floating in the air.

---------------------------------------------------------------------------------------------------

## 3. T_clinic.luau as it stands (5,744 lines): coverage, collisions, coordination

**Covers (do not duplicate):** all 11 rooms are built. lobby (desk, kiosk/번호표 call board, sanitizer, thermal camera, entrance, floor directory from map `Sign_층별 안내`, hang signs, AED), waiting, consult (partitions + `slideDoor` 초음파실 + exam couch etc.), pharmacy, treat (beds as hospital beds, cabinet, sink, infusion), **backhall** (ceilingKit with 7 lights + LightPanel hide, floorKit overlay, baseKit, lowerWall back/front, green floor guide "◀ 비상구", stair nosing/treads/stringers, "2F ↑" stair sign post at about L(20.2,25.7), bench reskin, **exit sign over the fire exit (hides map ExitSign, SurfaceLight)**, **hydrant on the east wall**, evac map, bulletin board (front wall about x -39.5..-30.5), purifier, 2 wheelchairs by STAFF ONLY, **floor directory "beside the elevator" on the back wall**, hang signs, sanitizer, handrails, corner guards), ward (beds, **in-room 병실 화장실**, blinds, front posters), nurse, lounge, checkup (lockers, blood, X-ray room partitions, signs ①-⑤, posters).
Helpers it has (local, not exported): exitSign, hydrantBox, aedBox, sanitizerWall, wheelchair, purifier, partition, slideDoor, hangSign, roomSign, poster.

**Keep handling in T_clinic:** `refit` → `Scan.fitRoom` → `Scan.keepouts` → **our `Scan.worldKeeps` apply**. Non-free parts and `V:spans` users (baseboard, lowerWall, handrailSpans, wallSpot, wallFloor, floorAt) avoid our boxes. **`K:free` users ignore them:** floorKit (FloorSkin + grout at y ≤ 0.025 across the whole room), ceilingKit (skin at H, LED panels chosen by `avoid`), hangSign, the stair kit and exitSign.

**Collisions with this plan and how they are resolved:**

| # | T_clinic item | Problem | Resolution |
|---|---|---|---|
| C1 | backhall `hangSign(K, 51.0, -4.6, …, "🚹 남자 화장실 여자 화장실 🚺")` (free) → L(-50.9, y 7.8..8.8, 36.8) | lands **inside our women's restroom** (below its 9.2 ceiling) | **Request: T_clinic removes it.** HospitalPlus draws the restroom signage (column, blade sign, door plates) |
| C2 | floorKit FloorSkin/grout (y 0.002..0.025) under the restroom block and lift enclosure | z-fighting | our floors start at **y 0.03** (restroom tiles 0.03..0.10, cabin floor 0.03..0.12, thresholds 0.03..0.08) |
| C3 | ceilingKit LED panels + SurfaceLights could land over the restroom block or shaft (hidden above our ceilings, wasted lights) | budget | **Request:** add every `Scan.worldKeeps` box of kind `facility_room` to `oo.avoid` in backhall and checkup |
| C4 | backhall floor directory text `"R   옥상 (관계자 외 출입금지)"` | the roof is now a garden | **Request:** `"R   옥상 정원 · 휴게 공간"`. Its wallSpot (u 38.6) will move out of K01/K03 to the nearest free span (between 창고 and STAFF doors) |
| C5 | backhall exit sign above the fire exit, hydrant (east wall) | overlap with our fire-exit kit | **T_clinic owns both.** HospitalPlus draws no inside 피난구 유도등 at the fire exit and no hydrant. Our door frame head stays below y 8.3 |
| C6 | backhall `lowerWall` / `baseKit` / `handrailSpans` along back/front/left walls | across our doors and openings | handled by spans + K01/K03/K05/K06/K07 (kept ≥ 1.6 away from the BackWall face so the hall wainscot is not cut, K02 z ≥ 24.0) |
| C7 | treat room posters (`wallSpot "left"` = east wall), TreatBed1 rebuild | ER door strip | K09 (x 54.2..59.11, z 9.4..19.8) clears the bedside cabinet (x ≤ 53.81) |
| C8 | checkup `wallSpot("back", 4.2, …, -8.0)` poster ≈ L(-28..-24) | next to the 2F enclosure / relocated guide board | K18/K19 make it move |
| C9 | Door_* models: T_clinic keeps them (contract) and does not hide leaves | none | **HospitalPlus owns** the Door_* DoorLeaf/LeafRail/Handle hide + animated leaves. Request: T_clinic must not reskin or hide them |
| C10 | consult/ward/checkup "front" wall decor near doors | our sliding leaves park there | K12, K15, K16, K17 |

**Ownership list (map parts this layer hides; T_clinic must not hide or reskin them):** `1F/BackZone/Door_남자 화장실/*`, `Door_여자 화장실/*`, `Door_STAFF ONLY/*`, `Door_창고/*`, `ElevatorJamb`×2, `ElevatorHead`, `ElevatorDoor`×2, `FloorIndicator`, `CallButton`, `Sign_엘리베이터`, `FireExitDoor`, `PushBar`; `GroundSide` (east); `2F/BackWall2` (piece x -8.09..33.91); `2F/CheckupCenter/Sign_건강검진 안내`; the five `Door_*` `DoorLeaf`/`LeafRail`/`Handle`; `건물/RoofDoor`. T_clinic keeps `BackZone/ExitSign` (fire exit).

---------------------------------------------------------------------------------------------------

## 4. What gets built (overview)

| Item | Type | Where (local) |
|---|---|---|
| 여자 화장실 + 남자 화장실 (AAA, a wide stall in each) | in place, real walls | 1F back hall west end x -59.29..-35.9, z 27.0..38.78 |
| 엘리베이터 1F / 2F / R (shaft enclosures, one moving cabin) | in place, seamless vertical shift | x -35.9..-28.3, z 33.3..38.8 on each level; roof penthouse |
| 진료실 / 주사실 / 입원실 201·202 / 건강검진센터 automatic sliding glass doors + 진료 중 lamp | in place (animated copies) | §2.9 |
| STAFF ONLY → 직원 휴게실 (P1) | fade portal | hall door x -12.09; room under the building |
| 창고 (P2) | fade portal | hall door x -22.09 |
| 응급실 출입구 (double sets of auto sliding doors, canopy, light box, ramp) | real passage (east wall replacement) | x 59.11..59.91, z 12.0..17.0 |
| 비상구 (steel fire door, panic bar, closer, outside lever) | real passage | z 27.58..31.58 |
| 2F 계단홀 출입구 (map fix) + held-open 방화문 | real passage (BackWall2 replacement) | x -7.60..-4.00, z -4.42..-3.82 |
| 2F 비상계단 door → stairwell (P3) → RoofDoor | fade portal ×2 | 2F door x -5.95, z 38.94; RoofDoor |
| 옥상 정원 · 휴게 공간 (deck, pergola, string lights, planters, benches, tables, view deck, telescope, rails, fences) | in place on the real roof | roof y 25.2 |
| Wayfinding (name plates, 피난구/통로 유도등, floor numbers, 층별 안내, guide board) | in place | §7.9 |

---------------------------------------------------------------------------------------------------

## 5. Module split and APIs

All files live in `GwangalliBuildingInterior/`, `--!strict`, and are required via `require(script.Parent:WaitForChild("Hosp_X"))` **inside `start`**. Exception: `HospitalPlus` top level uses non-yielding `FindFirstChild` for Scan and Hosp_Geo so it can register keeps before any yield.

| File | Responsibility | Est. lines |
|---|---|---|
| `HospitalPlus.luau` | top-level keep registration; `start(ctx)` / `stop()`; director (4 Hz), anim loop (10 Hz), zone registry, quality/budget, `status()` | 350 |
| `Hosp_Geo.luau` | **pure data, no requires**: HF, W/L helpers, floor levels, every coordinate in this doc, KEEPS (world AABBs), spot/lane tables, map-part locator specs, palette (same values as T_clinic: TEAL (0,128,118), TEAL_D (0,92,86), MINT (196,232,226), INK (30,34,38), RED (206,36,40), NAVY (28,50,92), GREEN_EXIT (0,150,80)) | 450 |
| `Hosp_Lib.luau` | zone/Kit factory (synthetic V), `solid()`, text/sign/pictogram helpers, map lookup, hide/uncollide registry + restore, `replaceWall`, actor sensor, `Slider` / `Swinger` animators with door-closer easing, sound and particle helpers, UI (fade/toast/lift panel/scope), `teleport`, `canTravel`, client Seat helper | 1,100 |
| `Hosp_Restroom.luau` | both restrooms, fixtures, interactions, motion lights | 900 |
| `Hosp_Elevator.luau` | landing kits ×3, roof penthouse shell, cabin model, state machine, GUI binding, NPC sync | 1,000 |
| `Hosp_Doors.luau` | 5 glass doors, 진료 중 lamp, corridor name plates + wait monitor, STAFF/창고 hall doors, 2F roof-stair door, RoofDoor leaf (portal triggers → Hosp_Portal) | 700 |
| `Hosp_Exits.luau` | east wall replacement, ER entrance in/out, fire exit in/out, 2F landing passage (BackWall2 replacement + held-open door) | 750 |
| `Hosp_Portal.luau` | portal manager (prefetch, go/back, safety, cleanup) + room builders P1 직원 휴게실, P2 창고, P3 비상계단 (split into `Hosp_Rooms.luau` if > 1,500 lines) | 1,400 |
| `Hosp_Roof.luau` | garden, pergola, string lights, planters/trees, benches/tables, view deck, telescope view, rails + invisible guards, mechanical fences, roof signs | 900 |
| `Hosp_Signs.luau` | wayfinding (exit signs, 통로유도등, floor numbers, 2F 층별 안내, relocated 건강검진 안내, corridor hang signs) | 400 |

### 5.1 HospitalPlus.luau (top level and lifecycle)

```lua
--!strict
local here = script.Parent
local Scan = require(here:FindFirstChild("Scan") :: ModuleScript)      -- already loaded by init (cached), no yield
local GeoM = here:FindFirstChild("Hosp_Geo")
local Geo = if GeoM and GeoM:IsA("ModuleScript") then require(GeoM) :: any else nil
if Geo then
	for _, k in Geo.KEEPS do
		Scan.addWorldKeep(k.min, k.max, k.kind) -- synchronous, before anything yields
	end
end
local M = {}
function M.start(ctx: any) ... end   -- ctx = { root, focus, limits, dbg, script, Scan }
function M.stop() ... end
function M.status(): string ... end
M._buildAll = function(ctx: any) ... end -- offline sim: build every zone at once (no portals/UI)
return M
```

`start` creates `ctx.root/HospitalPlus` (Model) and spawns the director. It connects `ctx.script.AncestryChanged` (destroyed → `stop`) and watches `ctx.script:GetAttribute("Enabled") == false` → `stop`.

### 5.2 Hosp_Lib key APIs

```lua
Lib.zone(name: string, parent: Instance, budget: { parts: number, lights: number }): any
  -- K = Kit.new(V, folder) with V = { cf = Geo.HF, keep = Geo.SAFE_KEEPS (local boxes), solid = {}, byName = {}, tables = {},
  --   x0 = -1e4, x1 = 1e4, z0 = -1e4, z1 = 1e4, W = 2e4, D = 2e4, H = 11.05, key = "HospitalPlus#" .. name,
  --   maxParts = budget.parts, maxLights = budget.lights }; K.hidden = {}, K.conns = {}, K.anims = {},
  --   K.hostPts = { L(HospitalPrompt_desk), L(HospitalPrompt_doctor) }, K.uncollided = {}, K.walls = {}
Lib.solid(p: BasePart, collide: boolean?): BasePart          -- CanQuery=true, CastShadow=true, CanCollide=collide~=false
Lib.tx(K, name, w, h, dcf, text, fg, bg?, o?)               -- same contract as T_clinic tx (Kit:text)
Lib.plate / Lib.exitSign(K, dcf, w, arrow, kind)             -- kind "door" (피난구) | "path" (통로, low)
Lib.pictogram(K, dcf, h, kind)                                -- "f" | "m" | "run" (TextLabel emoji 🚺 🚹 🏃, as T_clinic does)
Lib.hospital(): Model?                                         -- workspace.Gwangalli.hospital['광안 메디컬 의원'] (FindFirstChild chain, no yields)
Lib.find(spec): BasePart?                                      -- spec = { path = {...}, name, centre = L-coords, tol }
Lib.hide(K, p) / Lib.uncollide(K, p) / Lib.restore(K)          -- uncollided[p] = original CanCollide
Lib.replaceWall(K, mapPart, openings, look?)                   -- §7.1
Lib.actors(): { { root: BasePart, kind: "local"|"player"|"npc", role: string? } } -- 5 Hz cache
Lib.Slider.new(K, parts, offset: Vector3 (world), o)          -- :set(target 0..1)  o = { tOpen, tClose, settle }
Lib.Swinger.new(K, model, hinge: Vector3, axis: Vector3, maxAngle, o) -- :set(target 0..1), closer easing
Lib.sfx(part, id, o) -- o = { vol, speed, loop, dur }       Lib.particles(part, kind, dur)  -- "water" | "air" | "steam"
Lib.ui(): any  -- fade(toBlack, t) (yields), toast(text, t), liftPanel(show, handlers), scope(show)
Lib.canTravel(): (boolean, string?)                           Lib.teleport(cf: CFrame, faceDir: Vector3?): boolean
Lib.seat(K, name, size, lcf, look): Seat                      -- client Seat (local sitting only, untagged)
```

---------------------------------------------------------------------------------------------------

## 6. Keep boxes to register (`Scan.addWorldKeep`, world AABBs of rotated local boxes)

K11 (the whole east wall) was deliberately **not** registered: it would remove all east-wall decor from the waiting and treat rooms. The replacement wall is coplanar with the map wall.

| id | what | kind | local min | local max | WORLD min | WORLD max |
|---|---|---|---|---|---|---|
| K01 | restroom block (both rooms, walls, ceilings) | `facility_room` | (-59.29, 0.00, 26.60) | (-35.90, 11.05, 38.78) | `(-575.53, 6.90, 324.65)` | `(-551.75, 17.95, 337.58)` |
| K02 | restroom door approach (hall) | `facility` | (-52.40, 0.00, 24.00) | (-43.40, 8.00, 26.60) | `(-568.24, 6.90, 322.27)` | `(-559.16, 14.90, 325.17)` |
| K03 | 1F lift enclosure + landing | `facility_room` | (-36.40, 0.00, 31.00) | (-27.80, 11.05, 38.78) | `(-552.65, 6.90, 329.79)` | `(-543.80, 17.95, 337.85)` |
| K04 | 1F west niche (extinguisher, exit light) | `facility` | (-36.00, 0.00, 27.60) | (-34.60, 8.00, 31.00) | `(-551.99, 6.90, 326.41)` | `(-550.48, 14.90, 329.85)` |
| K05 | STAFF ONLY hall door | `opening` | (-15.00, 0.00, 35.00) | (-9.20, 10.00, 38.78) | `(-531.26, 6.90, 334.49)` | `(-525.34, 16.90, 338.46)` |
| K06 | 창고 hall door | `opening` | (-25.00, 0.00, 35.00) | (-19.20, 10.00, 38.78) | `(-541.26, 6.90, 334.16)` | `(-535.33, 16.90, 338.13)` |
| K07 | fire exit, inside swing/push zone | `opening` | (54.50, 0.00, 26.20) | (59.11, 10.00, 33.60) | `(-461.63, 6.90, 327.97)` | `(-456.78, 16.90, 335.52)` |
| K08 | fire exit, outside swing + lamp | `facility` | (59.91, -0.40, 25.60) | (65.50, 10.00, 33.60) | `(-456.22, 6.50, 327.55)` | `(-450.37, 16.90, 335.72)` |
| K09 | ER entrance, inside leaves/header | `opening` | (54.20, 0.00, 9.40) | (59.11, 11.05, 19.80) | `(-461.48, 6.90, 311.17)` | `(-456.23, 17.95, 321.72)` |
| K10 | ER entrance, outside leaves/canopy/ramp | `facility` | (59.91, -0.40, 8.50) | (68.50, 12.60, 20.50) | `(-455.79, 6.50, 310.46)` | `(-446.81, 19.50, 322.73)` |
| K12 | glass door 진료실 1 (slide + park) | `opening` | (-26.60, 0.00, -7.00) | (-17.70, 8.60, -5.40) | `(-541.41, 6.90, 292.13)` | `(-532.46, 15.50, 294.02)` |
| K13 | glass door 주사실 (slide + park) | `opening` | (25.70, 0.00, -2.90) | (34.50, 8.60, -1.60) | `(-489.26, 6.90, 297.94)` | `(-480.42, 15.50, 299.53)` |
| K14 | 진료 중 lamp + plate + wait monitor (corridor) | `facility` | (-23.00, 4.50, -5.82) | (-14.70, 10.00, -5.20) | `(-537.82, 11.40, 293.43)` | `(-529.50, 16.90, 294.32)` |
| K15 | glass door 입원실 201 | `opening` | (13.40, 14.15, -10.90) | (22.20, 22.60, -9.60) | `(-501.29, 21.05, 289.54)` | `(-492.46, 29.50, 291.13)` |
| K16 | glass door 입원실 202 | `opening` | (-26.60, 14.15, -10.90) | (-17.70, 22.60, -9.60) | `(-541.27, 21.05, 288.24)` | `(-532.33, 29.50, 289.83)` |
| K17 | glass door 건강검진센터 | `opening` | (-36.60, 14.15, -4.90) | (-19.70, 22.60, -3.60) | `(-551.46, 21.05, 293.91)` | `(-534.53, 29.50, 295.76)` |
| K18 | 2F lift enclosure + landing | `facility_room` | (-36.40, 14.15, 31.00) | (-27.80, 22.60, 38.94) | `(-552.65, 21.05, 329.79)` | `(-543.80, 29.50, 338.01)` |
| K19 | 2F 건강검진 안내 board (relocated) | `facility` | (-28.00, 16.60, 38.40) | (-19.40, 22.00, 38.94) | `(-544.26, 23.50, 337.46)` | `(-535.65, 28.90, 338.28)` |
| K20 | 2F landing passage (BackWall2 opening + held-open door) | `opening` | (-8.10, 14.15, -6.00) | (-2.00, 22.60, 0.20) | `(-523.10, 21.05, 293.74)` | `(-516.80, 29.50, 300.13)` |
| K21 | 2F roof-stair door (landing back wall) | `opening` | (-8.09, 14.15, 34.50) | (-3.30, 22.60, 38.94) | `(-524.36, 21.05, 334.22)` | `(-519.43, 29.50, 338.81)` |
| K22 | roof lift penthouse + door apron | `facility_room` | (-36.60, 25.20, 30.50) | (-27.60, 35.20, 38.87) | `(-552.85, 32.10, 329.29)` | `(-543.58, 42.10, 337.95)` |
| K23 | 1F "1F" floor plate beside map Sign_2F ↑ | `facility` | (24.30, 7.60, 22.18) | (26.10, 9.40, 22.45) | `(-491.45, 14.50, 322.96)` | `(-489.64, 16.30, 323.29)` |

`Hosp_Geo.KEEPS` literal:
```lua
Geo.KEEPS = {
	{ id = "K01", kind = "facility_room", min = Vector3.new(-575.53, 6.90, 324.65), max = Vector3.new(-551.75, 17.95, 337.58) },
	{ id = "K02", kind = "facility", min = Vector3.new(-568.24, 6.90, 322.27), max = Vector3.new(-559.16, 14.90, 325.17) },
	{ id = "K03", kind = "facility_room", min = Vector3.new(-552.65, 6.90, 329.79), max = Vector3.new(-543.80, 17.95, 337.85) },
	{ id = "K04", kind = "facility", min = Vector3.new(-551.99, 6.90, 326.41), max = Vector3.new(-550.48, 14.90, 329.85) },
	{ id = "K05", kind = "opening", min = Vector3.new(-531.26, 6.90, 334.49), max = Vector3.new(-525.34, 16.90, 338.46) },
	{ id = "K06", kind = "opening", min = Vector3.new(-541.26, 6.90, 334.16), max = Vector3.new(-535.33, 16.90, 338.13) },
	{ id = "K07", kind = "opening", min = Vector3.new(-461.63, 6.90, 327.97), max = Vector3.new(-456.78, 16.90, 335.52) },
	{ id = "K08", kind = "facility", min = Vector3.new(-456.22, 6.50, 327.55), max = Vector3.new(-450.37, 16.90, 335.72) },
	{ id = "K09", kind = "opening", min = Vector3.new(-461.48, 6.90, 311.17), max = Vector3.new(-456.23, 17.95, 321.72) },
	{ id = "K10", kind = "facility", min = Vector3.new(-455.79, 6.50, 310.46), max = Vector3.new(-446.81, 19.50, 322.73) },
	{ id = "K12", kind = "opening", min = Vector3.new(-541.41, 6.90, 292.13), max = Vector3.new(-532.46, 15.50, 294.02) },
	{ id = "K13", kind = "opening", min = Vector3.new(-489.26, 6.90, 297.94), max = Vector3.new(-480.42, 15.50, 299.53) },
	{ id = "K14", kind = "facility", min = Vector3.new(-537.82, 11.40, 293.43), max = Vector3.new(-529.50, 16.90, 294.32) },
	{ id = "K15", kind = "opening", min = Vector3.new(-501.29, 21.05, 289.54), max = Vector3.new(-492.46, 29.50, 291.13) },
	{ id = "K16", kind = "opening", min = Vector3.new(-541.27, 21.05, 288.24), max = Vector3.new(-532.33, 29.50, 289.83) },
	{ id = "K17", kind = "opening", min = Vector3.new(-551.46, 21.05, 293.91), max = Vector3.new(-534.53, 29.50, 295.76) },
	{ id = "K18", kind = "facility_room", min = Vector3.new(-552.65, 21.05, 329.79), max = Vector3.new(-543.80, 29.50, 338.01) },
	{ id = "K19", kind = "facility", min = Vector3.new(-544.26, 23.50, 337.46), max = Vector3.new(-535.65, 28.90, 338.28) },
	{ id = "K20", kind = "opening", min = Vector3.new(-523.10, 21.05, 293.74), max = Vector3.new(-516.80, 29.50, 300.13) },
	{ id = "K21", kind = "opening", min = Vector3.new(-524.36, 21.05, 334.22), max = Vector3.new(-519.43, 29.50, 338.81) },
	{ id = "K22", kind = "facility_room", min = Vector3.new(-552.85, 32.10, 329.29), max = Vector3.new(-543.58, 42.10, 337.95) },
	{ id = "K23", kind = "facility", min = Vector3.new(-491.45, 14.50, 322.96), max = Vector3.new(-489.64, 16.30, 323.29) },
}
```

**Our own Kit safety keeps (`Geo.SAFE_KEEPS`, local):**
* T_clinic `LANES1/LANES2` (half width 1.25, y 0.1..6.5 above each floor), **trimmed 4 studs short of lift1/lift2**: the lift doors are ours.
* HospitalPrompt anchors (r 1.4).
* All `HospitalBed` seats (seat box + 4 up).
* Stair volume x -3.33..19.31, z 24.6..35.5, y 0..21.
* AutoDoor doorway x 13.4..22.4, z -37..-31.
* TRANSIT (r 2.0).

---------------------------------------------------------------------------------------------------

## 7. Components

### 7.1 Shared mechanics

**Zones.** Each component builds into its own Kit `K` (`Lib.zone`) under `root/HospitalPlus/<zone>`: `hall1` (restrooms), `lift`, `doors`, `exits`, `level2` (signs etc.), `roof`, `portal`.

**Doors, general rules.**
* Moving leaves are built in a `K:group` Model and animated by `Slider`/`Swinger`, which run `TweenService` per part on CFrame. No per-frame Lua.
* Open: 0.45-0.75 s, Quart/Quad Out. Close ("door closer"): phase 1 Quint Out to 8° or 6% open over 0.9-1.0 s, phase 2 latch 0.18 s Quad In, then a `clickfast.wav` click at PlaybackSpeed 0.6.
* Leaves are `CanCollide=false` while not fully closed. Leaves that must stop the player when closed (fire exit, ER, locked stalls) are `CanCollide=true` only at alpha 0.
* Sensors run at 10 Hz on `Lib.actors()`: the local HRP, other players' HRPs, and `GwangalliNPCs` children with `NpcKind=="hospital"` (`GetPivot`). The NPC list is refreshed every 2 s.

**Wall replacement (`Lib.replaceWall`).**
1. Compute the map part's HF-local AABB; the thin axis is the wall normal.
2. Subtract openings `{ u0, u1, v0, v1 }` (u = along the wall, v = height) to get full-height segments, plus lintels above (and sills below, if v0 > bottom).
3. Build each segment with `K:box(..., { c = p.Color, m = p.Material, r = p.Reflectance, shadow = true, collide = true, free = true })`, then `CanQuery = true`. Copy `MaterialVariant`. Clone non-`GwangalliTex` Texture/Decal children with the same Face and StudsPerTile, with OffsetStudsU/V shifted by the segment offset. Optionally clone `GwangalliTex` too.
4. **Only after all segments exist:** `Lib.hide(K, p)` and `Lib.uncollide(K, p)`. Connect `p.ChildAdded` to hide new Texture/Decal children (recorded for restore).
5. Every 1 s: if `p.Parent == nil` (streamed out), re-find by name and expected centre. When found again, re-hide and re-uncollide. The segments stay, so it looks identical either way.
6. `Lib.restore` (zone teardown or stop) restores Transparency, Texture transparency and CanCollide.

**Teleport (`Lib.teleport`), used only by portals.**
`canTravel()` fails if:
* the humanoid is dead, `Sit`, has a `SeatPart`, is in `PlatformStand`, or its state is Ragdoll/Physics/FallingDown;
* the HRP is Anchored;
* the character has `GwKO`, `GwEmsPatient` or `GwTreating`, or the player has `GwCollapse`.

Sequence:
1. Save `off = hrp.CFrame:ToObjectSpace(cam.CFrame)`.
2. `pcall(player.RequestStreamAroundAsync, player, targetPos, 1)` inside a `task.spawn` (does not block).
3. `char:PivotTo(CFrame.lookAt(p, p + face))` with `p = floorPoint + (0, hum.HipHeight + hrp.Size.Y/2, 0)`.
4. Zero `AssemblyLinearVelocity` and `AssemblyAngularVelocity`.
5. `cam.CFrame = hrp.CFrame * off`.
Distances are fixed by geometry (< 100), so Jobs is never triggered.

**Portal manager (`Hosp_Portal`).**
* **Prefetch:** build the target room when the local HRP is within 10 studs of its door, so entering is one fade.
* **go(room, door):** prompt → `canTravel` → door crack (hall leaf swings 18° toward the player, 0.25 s, `clickfast`) → `ui.fade(true, 0.22)` + caption → ensure built (wait ≤ 1.5 s) → teleport → room door leaf goes from 18° to closed (0.6 s, thunk `action_jump_land.mp3` at 0.7) → `ui.fade(false, 0.35)` → toast. **back()** is the mirror.
* **Watchdog (4 Hz):** if the player is "in room" but the HRP is more than 25 from the room box (server teleport, e.g. collapse → ward bed), un-fade, set state outside, and destroy the room after 20 s. On `CharacterAdded` / death → same. On teardown while inside → `back()` first.
* Rooms are destroyed 20 s after the player is more than 30 from all of the room's doors.

**UI (`GwHospitalUI` ScreenGui in PlayerGui).**
* `ResetOnSpawn=false`, `IgnoreGuiInset=true`, `DisplayOrder=55` (below the server `GwangalliFade` at 60). Enabled only while something shows.
* Children: `Fade` (black Frame + Caption label), `Toast` (bottom centre, rounded, 2.5 s), `LiftPanel`, `Scope`. Created lazily and destroyed on stop.

**Sounds** (built-ins used elsewhere in this place): `electronicpingshort.wav` (chimes, bells), `clickfast.wav` (latches, buttons), `swoosh.wav` (sliding doors, pages), `action_swim.mp3` (running water), `impact_water.mp3` (flush), `action_falling.mp3` (looped wind = hand dryer / motor hum at low speed), `action_jump_land.mp3` (door thunk). Particles: `rbxasset://textures/particles/sparkles_main.dds` (water drops), `smoke_main.dds` (air, steam).

### 7.2 Restrooms (in place, 1F back hall west end)

**Concept.** Two rooms side by side, each 11.4 × 11.5 studs (3.2 × 3.2 m), with doors next to each other facing the hall (south) and a shared sign column between them.
* 여자 화장실 (west): 넓은 칸, 일반 칸, 청소도구함, 2-basin vanity, hand dryer, paper towel, 기저귀 교환대.
* 남자 화장실 (east): 넓은 칸, 2 urinals with dividers, 2-basin vanity, hand dryer, paper towel, 기저귀 교환대.
Corridor left in front: z 22.18..27.0 (4.8 studs ≈ 1.35 m).

All coordinates are HF-local, y = 0 at the 1F floor. "col" means `collide + query` (Lib.solid). Materials use Look names or (r,g,b, Material).

**Shell**

| Part | min .. max | look | col |
|---|---|---|---|
| FrontWall_W | (-59.29,0,27.00)..(-51.40,10.85,27.30) | Plaster (222,218,208) | ✓ |
| FrontLintel_W | (-51.40,7.45,27.00)..(-48.40,10.85,27.30) | same | ✓ |
| FrontPier (sign column backing) | (-48.40,0,27.00)..(-47.10,10.85,27.30) | same | ✓ |
| FrontLintel_M | (-47.10,7.45,27.00)..(-44.10,10.85,27.30) | same | ✓ |
| FrontWall_M | (-44.10,0,27.00)..(-35.90,10.85,27.30) | same | ✓ |
| Divider | (-47.90,0,27.30)..(-47.60,10.85,38.78) | same | ✓ |
| EastWall | (-36.20,0,27.30)..(-35.90,10.85,38.78) | same | ✓ |
| Ceiling_W / Ceiling_M | x -59.29..-47.90 / -47.60..-36.20, y 9.20..9.35, z 27.30..38.78 | (240,240,236) SmoothPlastic (SMC) | ✓ |
| Floor_W / Floor_M | same xz, y 0.03..0.10 | (200,196,188) CeramicTiles | ✓ |
| Threshold_W / _M | x -51.40..-48.40 / -47.10..-44.10, y 0.03..0.10, z 27.00..27.30 | Look.brushed | |
| Wall tiles (each inner face; 5 segments per room × 3 bands) | base y 0.10..0.90 (150,152,154) CeramicTiles; field y 0.90..9.20 (240,240,236) CeramicTiles; accent band y 3.30..3.55, 0.06 proud: W (214,166,166), M (126,156,186) | faces: W x -59.29 (west), z 38.74 (back), x -47.94 (divider), z 27.34 (front, split around the door); M x -47.56, z 38.74, x -36.24, z 27.34 | |
| FloorDrain ×2 | 0.6×0.6 at (-53.5, 0.105, 31.0) and (-40.5, 0.105, 31.0) | Look.steel | |

**Entrance doors** (auto swing on approach, inward, door closer)

| Part | spec |
|---|---|
| Door frames | alu jambs x -51.55..-51.40 / -48.40..-48.25 (W) and -47.25..-47.10 / -44.10..-43.95 (M), y 0..7.55, z 26.95..27.35; heads y 7.40..7.55 |
| Leaf W | 2.90×7.30×0.15, closed x -51.35..-48.45, y 0.10..7.40, z 27.075..27.225. HPL (204,200,194). Hall face: push plate Look.steel 0.5×1.6 at y 3.4..5.0; kick plate 2.9×0.7. Inside: D-handle and closer arm. **Hinge (-48.45, z 27.30), +92° inward**; the open leaf rests along the divider |
| Leaf M | closed x -47.05..-44.15. **Hinge (-47.05, z 27.30), inward 92°**; rests along the divider |
| Door plates (on leaves, hall face) | 2.0×1.0 at y 5.4..6.4: "🚺 여자 화장실 · WOMEN" (red (206,36,40)) / "🚹 남자 화장실 · MEN" (navy) |
| Sensor | open when the local HRP is in x door ±1.8 and z 24.5..30.0 (both sides); close 1.2 s after leaving |
| Emergency strobe (both doors) | box 0.6×0.3×0.2 on each lintel hall face at y 7.9..8.2, red neon off; flashes 10 s when a bell is pressed |

**Women's fixtures**

| # | Part | spec |
|---|---|---|
| W4 | Stall W1 (넓은 칸) front panels | x -59.25..-58.30 and -54.90..-53.90, y 0.45..6.85, z 33.00..33.12, HPL (220,214,206); headrail alu 0.12² from x -59.25 to -49.70 at y 6.85..6.97 |
| W5 | Partition W1/W2 | x -53.96..-53.84, y 0.45..6.85, z 33.12..38.74 + 2 steel feet 0.2×0.45×0.2 |
| W6 | Stall W1 door | 3.35×6.30×0.12, closed x -58.275..-54.925, z 33.00..33.12. **Hinge (-54.925, z 33.06), opens OUTWARD (-z) 88°** (clears the vanity, end at z 29.6). Outside: lock indicator TextLabel at y 3.6 ("비어있음" green / "사용중" red). Inside: coat hook |
| W7 | Toilet W1 (centre x -57.60) | Base 1.0×1.1×1.2 (y 0.10..1.20, z 37.15..38.35); Bowl ell 1.40×0.85×2.00 @(x,1.15,36.95); Seat ell 1.45×0.12×2.05 @(x,1.56,36.95); Water ell 0.80×0.13×1.20 @(x,1.57,36.85) (150,190,210) Glass t0.2; Lid 1.35×1.90×0.10 @(x,2.50,38.05) tilted 8°; flush pipe vcyl d0.16 y 1.55..3.30 @ z 38.55; valve cyl d0.34 L0.6 @(x,3.40,38.50); **lever 0.55×0.08×0.08 @(x+0.5,3.40,38.40) → prompt "물 내리기"**. White porcelain (246,246,243) SmoothPlastic r0.04; col on base/bowl |
| W8 | Grab bars | ㄱ on the west wall: seg (-59.15,2.65,34.6)→(-59.15,2.65,37.6) + (-59.15,2.65,34.6)→(-59.15,5.2,34.6), d0.13 chrome with flanges; fold-up bar (-55.95,2.65,38.6)→(-55.95,2.65,36.2) + pivot block |
| W9 | Paper holder (jumbo) | x -59.25..-58.85, y 1.9..2.9, z 35.4..36.4, Look.steel + roll |
| W10 | 비상벨 W1 | plate 0.6² at x -59.25..-59.20, y 2.75..3.35, z 35.0..35.6 + red disc d0.32 + label "비상벨" → **prompt "비상벨 누르기"** (3.76 from the lever) |
| W11 | Sanitary bin | 0.7×1.1×0.6 at x -55.7..-55.0, z 37.9..38.5, pale pink (236,214,214) |
| W12-13 | Stall W2 front panels / east panel | x -53.84..-53.30 and -50.50..-49.70 (z 33.00..33.12); east x -49.76..-49.64, z 33.12..38.74 |
| W14 | Stall W2 door | 2.75×6.30×0.12, closed x -53.275..-50.525. **Hinge (-50.525, z 33.06), opens INWARD (+z) 95°**. Rests ajar 20° when free |
| W15 | Toilet W2 | as W7 at centre x -51.75 (lever prompt at x -51.25) |
| W16-18 | Paper holder (east panel inner face x -50.16..-49.76, z 35.6..36.6), 비상벨 W2 (partition east face x -53.84, z 35.0..35.6, prompt, 4.06 from the lever), sanitary bin | |
| W19 | 청소도구함 | front panel x -49.64..-47.94, y 0..9.20, z 33.00..33.12 with static door x -49.40..-48.10, y 0.1..6.8, label "청소도구함" + louver |
| W20 | Vanity | top x -58.90..-52.00, y 2.85..3.00, z 27.34..29.29, Marble (238,236,230); apron y 2.15..2.85 at z 29.19..29.29, HPL (214,204,190); col |
| W21 | Basins ×2 at x -56.95 / -53.95 | rim ell 1.50×0.06×1.05 @(x,3.02,28.45) white; inner ell 1.20×0.07×0.80 (210,216,220); drain disc d0.16 chrome |
| W22 | Sensor faucets ×2 | neck vcyl d0.18 y 3.00..3.85 @ z 27.70; spout cyl L0.55 d0.13 @(x,3.82,27.95); sensor dot. **Prompt "손 씻기"** (3.0 apart) |
| W23 | Soap pump | @(-55.45,3.00,27.70) vcyl d0.30 h0.60 + head |
| W24-25 | Mirror + LED bar | mirror x -58.85..-52.05, y 3.60..7.40, z 27.34..27.40 (Look.mirror) + chrome edge strips; LED x -58.6..-52.3, y 7.55..7.63, neon (255,240,220) |
| W26 | Hand dryer (west wall) | x -59.25..-58.40, y 3.30..5.30, z 29.60..30.80, white + silver face, blue LED, slot. **Prompt "손 말리기"** |
| W27 | Paper towel + bin | dispenser x -59.25..-58.80, y 4.00..5.40, z 31.20..32.20; bin vcyl d0.9 h1.8 @(-58.6,0.1,31.7) |
| W28 | 기저귀 교환대 (divider west face) | body x -48.39..-47.94, y 2.20..4.60, z 30.60..32.60 (white + teal); deck group with hinge axis z at (x -48.39, y 2.20), swings 90° down to a 2.0×1.6 shelf. **Prompt "기저귀 교환대 펼치기 / 접기"**; label "기저귀 교환대 · 최대 15kg" |
| W29 | Ceiling | downlights d0.9 neon @(-56.0,9.18,30.8), (-51.5,9.18,30.8); **SurfaceLight** Bottom, Range 14, Brightness 0 → 1.1 (motion); exhaust grille 0.9² @(-55.5,9.18,36.0); motion sensor dome d0.35 @(-50.0,9.18,28.6); smoke detector; sprinkler |
| W31 | Signs | stall door insides "화장지는 변기에 버려 주세요"; door inside "🚭 금연"; mirror corner "물을 아껴 씁시다"; near bells "위급할 때 누르세요" |

**Men's fixtures**

| # | Part | spec |
|---|---|---|
| M4 | Stall M1 (넓은 칸) front panels / headrail / east panel | x -47.56..-46.60 and -43.20..-42.00, y 0.45..6.85, z 32.60..32.72; east panel x -42.06..-41.94, z 32.72..38.74 |
| M5 | Stall M1 door | 3.35×6.30×0.12, closed x -46.575..-43.225. **Hinge (-46.575, z 32.66), opens OUTWARD 85°**. At 85° it lies at x ≈ -46.58..-46.29, z 29.3..32.66: 0.3 clear of the open entrance leaf and the baby table |
| M6-9 | Toilet (centre x -45.90), grab bars on the divider east face (x -47.50), fold-up bar x -44.25, paper holder on the divider z 35.4..36.4, 비상벨 on the east panel west face (x -42.06, z 35.0..35.6, 4.57 from the lever) | as W7-W10 |
| M10 | Urinals U1 / U2 at x -39.90 / -37.30 (back wall) | back plate 1.25×2.60×0.12 (y 1.45..4.05, z 38.62..38.74); body ell 1.25×2.30×1.15 @(x,2.65,38.20); lip ell 1.10×0.60×0.70 @(x,1.85,37.75); inner ell (226,230,232) @(x,2.65,37.68); drain disc; **sensor box 0.50×0.60×0.35 @(x,4.35,38.56) with red eye → auto-flush when the local HRP leaves the 1.6-radius stand zone after ≥ 2 s + prompt "물 내리기"** (2.6 apart); darker floor strip x -41.94..-36.24, z 37.2..38.74 |
| M10b | Stickers above urinals | y 5.6..6.4: "남자가 흘리지 말아야 할 것은 눈물만이 아닙니다" / "한 걸음 더 가까이 ♥" |
| M11 | Urinal dividers | x -38.65..-38.55 and -41.25..-41.15, y 1.60..5.40, z 37.00..38.74, frosted Glass t0.3 + chrome edge |
| M12-13 | Vanity, basins, faucets, soap, mirror | top x -43.70..-36.60 (z 27.34..29.29); basins/faucets at x -41.90 / -38.60 (prompts, 3.3 apart); soap x -40.25; mirror x -43.65..-36.65, y 3.60..7.40 + LED |
| M14-15 | Hand dryer (east wall), paper towel + bin | dryer x -37.09..-36.24, y 3.30..5.30, z 30.00..31.20 (prompt); towel z 31.60..32.60; bin @(-36.8, z 32.1) |
| M16 | 기저귀 교환대 (divider east face) | x -47.56..-47.11, y 2.20..4.60, z 30.50..32.40 (1.9 wide), prompt |
| M17 | Ceiling | downlights @(-44.5,9.18,30.8), (-39.0,9.18,30.8); SurfaceLight (motion); exhaust over urinals (-38.6,9.18,37.5); motion sensor (-45.6,9.18,28.6) |
| M18 | Signs | "🚭 금연", "소변기는 자동으로 물이 내려갑니다", "화장지는 변기에 버려 주세요" |

**Hall-side signage and safety (this layer owns the restroom signage; T_clinic C1 removed)**
* **Sign column** on FrontPier hall face, x -48.35..-47.15, y 4.20..8.60, z 26.94..27.00: white acrylic. Top teal band "화장실 · Restroom". Below: "🚺 여 ←" (red), "🚹 남 →" (navy) as TextLabels.
* **Blade sign:** x -37.26..-37.14, y 7.40..8.60, z 25.30..26.90 (double-sided, faces ±x) "🚺 화장실 🚹". Visible down the hall from the east.
* **통로유도등** (low) on the FrontWall_M hall face x -38.4..-37.2, y 0.9..1.5: green neon "🏃 →" toward the east fire exit (matches T_clinic's floor guide).
* **Fire extinguisher box** on the EastWall hall face (x -35.90) z 28.5..29.5, y 0.1..2.2 + "소화기" plate at y 2.6. T_clinic owns the hydrant and AED.

**Interactions (all prompts R / ButtonY, ≤ 5 studs, via Interact.prompt on K_hall1)**

| Prompt | Effect |
|---|---|
| 물 내리기 (toilets ×3, urinals ×2) | `impact_water.mp3` at 0.55 + `action_swim.mp3` at 0.6 for 2 s. Water ellipse spins 2 turns while its colour flashes (180,215,235) and shrinks 0.8× then restores (1.6 s). 3 s cooldown |
| 손 씻기 (faucets ×4) | water stream cyl d0.08 from the spout tip to y 3.03 (Glass (180,220,240) t0.45) for 3 s + drops ParticleEmitter (sparkles, Rate 40, Life 0.3, Speed 3, down) + `action_swim.mp3` looped at 1.4, vol 0.25 |
| 손 말리기 (dryers ×2) | LED blue → green; air emitter (smoke_main, t0.85, Rate 30, Speed 6 down) + `action_falling.mp3` looped at 1.6, vol 0.3, for 3 s |
| 잠그기 / 잠금 해제 (stall doors, only from inside the stall box) | door closes and becomes collidable; outside indicator turns red "사용중". Unlock → green "비어있음"; the door opens on approach again |
| 비상벨 누르기 (×3) | `electronicpingshort` ×6 (0.25 s apart, speed 1.6), hall strobe 10 s, toast "비상벨이 울렸어요. 직원이 곧 확인해요 (연출)" |
| 기저귀 교환대 펼치기 / 접기 (×2) | Swinger 90° about the bottom edge, 0.6 s |

Motion lights: the SurfaceLight and neon downlights fade in (0.4 s) while the local HRP is inside the room box and stay on 20 s after leaving. Light count 0 while outside.

Parts ≈ 300 (W 125, M 120, shell/signs 55).

### 7.3 Elevator (in place, seamless)

**Geometry (identical xz on every level; yF = 0 / 14.15 / 25.20)**

| Part | spec |
|---|---|
| Shaft side walls (1F, 2F) | W x -35.90..-35.60, E x -28.60..-28.30, z 33.55..ZB (ZB = 38.78 on 1F, 38.94 on 2F), y yF..yF+HF (HF 10.85 on 1F, 8.40 on 2F). Plaster (222,218,208), col |
| Front cladding (hall face z 33.30..33.55) | left panel x -35.90..-33.69, right panel x -30.49..-28.30, y yF..yF+HF; transom x -33.69..-30.49, y yF+7.20..yF+HF. Stone (214,210,204) Marble up to yF+7.9, plaster above; stainless trim 0.25 around the opening (0.04 proud) |
| Door opening | x -33.69..-30.49 (3.2 = 0.9 m), y yF..yF+7.20 |
| Landing leaves ×2 | L closed x -33.74..-32.09, R closed x -32.09..-30.44, y yF+0.05..yF+7.20, z 33.60..33.72, Look.brushed r0.1. Open: L −1.60, R +1.60 in x (hidden behind the cladding). Collidable only when closed |
| Sill | x -33.80..-30.38, y yF..yF+0.06, z 33.30..33.95, alu with a groove line |
| Hall lantern | black glass x -33.0..-31.18 at z 33.25..33.30. 1F y 7.55..8.15; 2F y 21.45..21.95; R y 32.75..33.35. TextLabel red digital "1" / "2" / "R" + ▲▼ |
| Hall call plate | stainless 0.55×1.50 at x -29.90..-29.35, y yF+3.10..yF+4.60, z 33.25..33.30. ▲ d0.36 at yF+4.15 (1F, 2F), ▼ at yF+3.55 (2F, R); neon rings white → amber when registered. **One prompt per landing "엘리베이터 호출"** |
| Barrier-free low plate | x -35.10..-34.60, y yF+2.40..yF+3.00, "▲▼" (visual only) |
| Fire warning plate | x -35.60..-34.00, y yF+3.40..yF+5.00, red border: "화재 발생 시 엘리베이터를 이용하지 마시고 계단을 이용하십시오" |
| Floor plate on the left jamb | "1F" / "2F" / "RF" 0.6² at x -34.2, y yF+5.6 |
| Sign | 1F: "엘리베이터 ELEVATOR" at y 8.50..9.30 on the transom. R: on the penthouse front, y 33.4..34.2 |
| 2F floor directory (on the enclosure E wall outer face x -28.30, facing +x) | z 33.8..38.6, y 16.0..20.8, teal header "층별 안내": "RF 옥상 정원 · 휴게 공간 / 2F 입원실 201·202 · 간호사실 · 건강검진센터 · 휴게실 / 1F 접수·수납 · 진료실 1 · 주사실·처치실 · 약국 · 화장실" |
| **Roof penthouse** (Hosp_Elevator owns it) | walls W x -36.20..-35.60, E x -28.60..-28.00, back z 38.40..38.80 (x -36.20..-28.00), y 25.20..34.50; front = landing cladding at full height/width; roof slab x -36.50..-27.70, y 34.50..34.85, z 33.00..39.00 + coping; machine-room louvers on side walls at y 31..33.5; canopy x -34.6..-29.6, y 32.9..33.1, z 31.6..33.3 + neon lamp; Concrete (184,182,176) to match the map penthouse; col |
| Map parts hidden (1F) | ElevatorJamb×2, ElevatorHead, ElevatorDoor×2, FloorIndicator, CallButton, Sign_엘리베이터. They stay collidable behind the cabin back wall |
| Map part hidden (2F) | CheckupCenter/Sign_건강검진 안내 → redrawn (Hosp_Signs) at x -27.4..-20.0, y 17.2..21.2 on the PartyWall (K19) |

**Cabin model** (one instance; pivot at its floor centre (-32.09, yF, 36.10))

| Part | spec |
|---|---|
| Floor | x -34.89..-29.29, y +0.03..+0.12, z 33.85..38.35, granite (90,92,96) + stainless border 0.1 |
| Back wall | x -34.89..-29.29, z 38.35..38.45, y 0.12..7.90: stainless lower panel (y ≤ 3.30); **mirror** x -34.30..-29.88, y 3.40..7.40 (Look.mirror) |
| Side walls | x -34.99..-34.89 / -29.29..-29.19, z 33.75..38.45: lower hairline stainless, upper champagne stainless (190,182,170) with seam lines |
| Handrails | d0.16 chrome at y +2.95, 0.3 off the walls, 2 brackets each: back x -34.4..-29.8 @ z 38.0; sides z 34.6..37.9 @ x -34.55 / -29.63 |
| Front returns | x -34.89..-33.69 / -30.49..-29.29 and transom y 7.20..7.90, z 33.75..33.85; inside sill strip |
| **COP** (right return inner face x -30.42..-29.36, z 33.86..33.91, y 2.4..6.2) | display (black glass 0.8×0.35 at y 5.75) "1 ▲"; buttons d0.30 with neon rings: R (y 5.15), 2 (4.65), 1 (4.15), 열림 ◀▶ (x -30.15, y 3.55), 닫힘 ▶◀ (x -29.65, y 3.55), 🔔 비상 (yellow, y 2.95); key switch; plates "정원 9인 · 600kg" and "비상시 인터폰 버튼을 누르세요". **Prompt "층 선택"** |
| Inside indicator | black glass x -32.6..-31.6, y 7.35..7.75 on the transom inner face |
| Ceiling | y 7.90..8.00: white panel, 2 LED strips (neon 4.4×0.12) at x -33.2 / -31.0, **SurfaceLight** (Range 10, Brightness 1.0; off after 60 s idle with nobody in or at the doors), vent slot, speaker grille, **CCTV dome** d0.5 at (-29.8, 7.9, 37.9) + "CCTV 녹화 중" |
| Inspection certificate | framed 0.9×1.25 on the W side wall (x -34.88) at z 34.3..35.2, y 4.5..5.75: "승강기 안전검사 합격증명서 / 승강기번호 2601-0317 / 정기검사 · 합격 / 유효기간 2026.04.01 ~ 2027.03.31 / 한국승강기안전공단" |
| Misc | "🚭" sticker, "만원 시 다음 운행을 이용해 주세요" |

Parts: 3 landing kits ≈ 3×45, enclosure shells ≈ 20, penthouse ≈ 30, cabin ≈ 110 → **≈ 295**. Lights: 1.

**State machine (Hosp_Elevator, 10 Hz tick + tweens)**
```text
LEVELS = { [1] = 0, [2] = 14.15, [3] = 25.20 }, LABEL = { "1", "2", "R" }
state  = { floor = 1, mode = "idle", doors = 0, calls = {}, dir = 0, tOpen, from, to, t0, dur }
idle     : calls[floor] → clear, mode = opening, chime ; elseif any call → choose next (nearest in dir, else nearest) →
           mode = moving, from = floor, to = next, dur = 1.4 + 1.1 * |to - from|  (1↔2 2.5 s, 1↔R 3.6 s), motor hum on
opening  : leaves → 1 (0.9 s Quad InOut, swoosh 0.55) → mode = open, tOpen = now
open     : hold 4.0 s; someone in the doorway box (x -33.8..-30.4, z 33.0..34.2, same floor) → tOpen = now;
           닫힘 → closing (minimum 0.5 s open); 열림 → tOpen = now
closing  : leaves → 0 (1.1 s); someone enters the doorway box → opening (safety reopen); done → idle
moving   : indicator steps at segment midpoints; at now - t0 ≥ dur → ARRIVE
ARRIVE   : (BindToRenderStep "GwHospLift", Camera + 1, once)
           dy = LEVELS[to] - LEVELS[from]
           if local HRP inside cabin box (x -34.95..-29.25, z 33.30..38.45, y LEVELS[from]-1..+8.5) then
               char:PivotTo(char:GetPivot() + Vector3.new(0, dy, 0)); cam.CFrame += Vector3.new(0, dy, 0)
           cabin:PivotTo(cabin:GetPivot() + Vector3.new(0, dy, 0))
           floor = to; calls[to] = nil; chime (electronicpingshort ×2: speed 1.0 then 0.8, 0.35 s apart); hum off
           toast "1층입니다" / "2층입니다 · 입원실 · 건강검진센터" / "옥상입니다 · 옥상 정원"; mode = opening
```
* HF is Y-up, so the vertical shift is a pure world-Y shift: the passenger sees nothing.
* Jobs jump ≤ 25.2. Other players see the avatar walk to the map's flat elevator door and pop up on 2F, like the server NPCs.
* **Inputs.** Hall prompt → `calls[f] = true` (instant open if the cabin is idle there). Cabin GUI: `LiftPanel` with TextButtons [1] [2] [R] [◀▶ 열림] [▶◀ 닫힘] [🔔 비상] and a display. It auto-shows while the HRP is in the cabin box and hides when outside; the "층 선택" prompt also toggles it. Gamepad: `GuiService.SelectedObject` = first button. Keyboard: ContextActionService keys One/Two/Three (bound only while shown). Pressing the current floor while idle opens the doors. Pressing 비상 → alarm bell 2 s + toast "비상벨이 울렸습니다. 관리실과 연결 중이에요 (연출)".
* **NPC sync** (GwangalliNPCs, NpcKind == "hospital"). Approaching lift1/lift2 (within 6 studs, `Moving` attribute > 0) → `calls[f] = true`. ChildRemoved near a lift spot → nothing. ChildAdded with pivot within 3 studs of lift1/lift2 → if the player is not in the cabin and mode is idle or open, snap the cabin to that floor (`PivotTo`, no animation) and open the doors. Never move the cabin while the local player is inside or during `moving`.
* Respawn or zone rebuild → cabin at 1F, idle.

### 7.4 Glass room doors, 진료 중 lamp, corridor plates (Hosp_Doors)

* For each `Door_*` (table §2.9), read the live parts: Jambs (sorted by local x) give the opening; DoorLeaf gives the plane z and park range; Head gives the top.
* Hide DoorLeaf, LeafRail ×2 and Handle (all already CanCollide=false; the NPC grid is unaffected). Keep the Jambs, Head and Sign.
* **Our leaf** (closed in the opening): alu frame 0.15 + Glass (214,232,236) t0.55 r0.15 + frosted band (Glass t0.2 white) at y +3.0..+4.2 with the room name (TEAL_D text), vertical bar handles d0.12 h2.2 on both faces near the leading edge, bottom rail 0.3, "자동문" sticker at y +4.6.
* **Top track** (alu 0.30×0.35) over opening + park at y +7.95..+8.30 on the leaf side, with a motion sensor box at the opening centre.
* 건강검진센터 (8 wide): two telescopic 4.1 leaves (z offset 0.12) that both park in x -36.4..-28.3.
* Sensor: any actor (local, players, hospital NPCs) within 5.0 flat of the opening centre and |dy| < 4 → open (0.75 s Quart Out, `swoosh` 0.8 vol 0.15). Close 1.4 s after empty (1.0 s Sine InOut + 0.15 settle). Leaves never collide.

**진료 중 lamp** (corridor face of ConsultWall, z -5.82):
* housing x -21.0..-19.2, y 8.55..9.35, z -5.77..-5.47 (black) + glowing TextLabel.
* "진료 중" red (255,70,60) glow 1.6 when any `Players` character has `GwTreating == true` or a hospital NPC with `HospitalRole == "patient"` is inside the consult box (x -59.3..-14.7, z -34.8..-6.4, 1F). Otherwise "진료 대기" (220,230,230) glow 0.6.

**Corridor name plates** (TEAL acrylic 0.04, white text, y = floor + 5.0..6.2 unless noted):

| Plate | Where (wall face) |
|---|---|
| "진료실 1 · 내과 / Internal Medicine · 전문의 김선생" 2.8×1.0 | ConsultWall piece x -18.09..-14.69, corridor face z -5.82, x -17.85..-15.05, y 6.2..7.2 |
| 대기 환자 monitor 2.0×1.2 (screenLoop 5 s: "대기 1  김*수 · 2  이*영 · 3  박*민" / "진료 중  7번") | same face, x -17.4..-15.4, y 4.6..5.8 |
| "201호 입원실 · 2인실 / 김*수 · 이*영" | WardWall piece x 13.91..17.91, corridor face z -9.82, x 14.5..17.3, y 19.2..20.4 |
| "202호 입원실 · 2인실 / 박*진" | WardWall piece x -18.09..-14.69, z -9.82, x -17.8..-15.0, y 19.2..20.4 |
| "간호사실 NURSE STATION" hang sign (double-sided 4.6×0.9) | ceiling over the open station at (−0.5, 21.0..21.9, -9.2), faces ±z |
| "건강검진센터 · Health Check-up / 접수 08:30~17:00" | BackWall2 piece x -20.09..-12.09, corridor face z -4.42, x -19.6..-16.0, y 19.0..20.4 |
| "휴게실 LOUNGE" | BackWall2 piece x 39.91..59.11, z -4.42, x 40.3..43.1, y 19.2..20.2 |
| "계단 · 비상구 / 옥상 정원 RF" | replacement BackWall2 R2, corridor face, x -3.6..-0.8, y 19.0..20.2 |

### 7.5 STAFF ONLY → 직원 휴게실 (P1) and 창고 (P2) (Hosp_Doors + Hosp_Portal)

**Hall door kits** (xD = -12.09 STAFF / -22.09 창고; wall face z 38.78). The map Door_STAFF ONLY / Door_창고 groups are hidden (all non-colliding).

| Part | spec |
|---|---|
| Casing | jambs x xD-2.10..xD-1.90 / xD+1.90..xD+2.10, y 0..7.85, z 38.55..38.78; head y 7.65..7.85 |
| Leaf | 3.75×7.60×0.15 at x xD±1.875, y 0.05..7.65, z 38.58..38.73. **Hinge x xD+1.875**, cracks 18° toward the hall during transitions only; collidable. STAFF: oak HPL (196,160,118 Wood), digital door lock keypad (0.35×0.9 at y 3.3, blue backlight neon), lever, kick plate, closer arm, plate "직원 휴게실 · STAFF ONLY" (2.6×0.9 at y 5.6) and red "관계자 외 출입금지" (1.8×0.35 at y 4.8). 창고: grey steel (150,154,158 Metal), bottom louver 2.2×0.9, plate "창고 · STORAGE / 관계자 외 출입금지" |
| Prompt on the lever | "들어가기" (ObjectText "직원 휴게실" / "창고"). First press → toast "관계자 외 출입금지 구역이에요. 들어가려면 한 번 더 누르세요." and ActionText "그래도 들어가기" for 4 s. Second press → `Portal.go` |
| Exit spawn (back) | (xD, 0, 35.6) facing -z |

**P1 직원 휴게실:** interior x -24.0..-2.0 (6.2 m), z 22.0..36.0 (3.9 m), floor y -50 (top), ceiling y -41.4. W(-540.2,-43.1,321.2)..(-517.7,-34.5,335.9).

| Element | spec (local; y relative to floor -50 shown as +h) |
|---|---|
| Shell | floor slab x -24.4..-1.6, y -50.6..-50.0, z 21.6..36.4; walls 0.4 thick; ceiling slab -41.4..-40.9; floor WoodPlanks (176,140,104) 데코타일; walls (238,234,226) + HPL wainscot (196,198,198) to +3.0 + baseboards; collide + query + **shadow** |
| Door (inside) | leaf at z 22.00..22.15, x -13.975..-10.225 (inside face of the same design). **Prompt "나가기"** (ObjectText "1층 후면 홀"). Spawn in at (-12.1, -50, 24.6) facing +z |
| Lockers (west wall) | x -24.0..-22.3, z 23.0..30.0, 2 tiers × 5 (1.4 wide × 3.2 tall), grey steel, name tags "간호부 01…10", vent slots; **2 interactive doors (swing 100°, "사물함 열기 / 닫기")** with scrubs inside |
| Uniform hooks (east wall) | rail x -2.25..-2.00, y +4.6, z 29.2..33.0; 3 hanging garments (teal scrubs, white 의사 가운 with name tag "김선생", navy cardigan): hanger + body 0.25×3.2×1.4 + sleeve boxes |
| 근무표 whiteboard (east wall) | x -2.10..-2.00, y +3.4..+6.6, z 23.6..28.0, TextLabel grid "10월 근무표 (간호부) · 월 화 수 목 금 토 일 / 김 D D E E N - - / 박 E E N N - D D / 이 N - D D E E N / 최 - N N D D E E"; prompt "근무표 보기" → toast |
| 게시판 (south wall, east of the door) | cork 4.6×3.0 at x -8.9..-4.3, y +3.3..+6.3, 6 pinned notes ("감염관리 교육 10/24 14:00", "휴게실 냉장고 금요일 정리", "직원 독감 예방접종", "주차권 신청은 원무과", "회식 11/7(금) 19시 광안리 횟집", "화재 대피 훈련 11/3"); prompt "게시판 보기" → toasts in turn |
| TV (south wall, west of the door) | Props.tv 4.0 at x -20.0..-16.0, y +3.7..+6.0; prompt "채널 바꾸기" (뉴스 / 날씨 / 광안리 해변 CCTV) |
| Sofa (north wall west) | x -23.2..-15.6, z 33.6..36.0, seat top +1.9, grey-blue Fabric, **3 client Seats** |
| Coffee table | x -21.6..-17.6, z 30.8..32.6, top +1.4 (oak) |
| Kitchenette (north wall east) | base cabinets x -14.8..-4.6, z 33.8..36.0, counter top +3.15 Marble white; sink x -12.3 (steel basin + faucet, prompt "물 틀기"); **coffee machine** x -9.6 (black/chrome 1.2×1.6×1.3, prompt "커피 내리기": cup appears, steam 3 s, `clickfast` + `action_swim` 0.9, toast "따뜻한 아메리카노 ☕"); **microwave** x -7.3 (1.6×0.95×1.2, prompt "데우기": light on + hum 3 s + `electronicpingshort`); kettle x -5.6; upper cabinets y +5.4..+7.6, z 35.0..36.0 |
| Fridge (NE) | x -4.4..-2.0, z 33.4..36.0, h 6.3, 2-door; **prompt "냉장고 열기"** (Interact.swing) |
| Dining table | x -10.0..-5.8, z 26.8..29.6, top +2.8 + 4 chairs |
| Ceiling | 4 LED panels (2×2) at (-18, z 26/32) and (-7, z 26/32), **2 SurfaceLights**, AC cassette, smoke detector, sprinkler; wall clock above the door (Props.clock + Interact.clock); light switch by the door (Interact.lightSwitch); posters "손 위생 5원칙", "직원 휴게실 이용 수칙" |

Parts ≈ 330.

**P2 창고:** interior x -30.0..-15.0, z 2.0..14.0, floor -50, ceiling -41.4 (W(-545.4,-43.1,301.0)..(-530.1,-34.5,313.5)). Epoxy floor Concrete (120,124,128), block walls (206,206,200).
* Door inside at z 2.0, x -23.975..-20.225, prompt "나가기"; spawn (-22.1, -50, 4.6) facing +z.
* **Steel shelving:**
  * A: west wall x -30.0..-28.3, z 3.0..13.0 (2 bays).
  * B: north wall x -28.0..-17.0, z 12.3..14.0 (2 bays).
  * C: east wall x -16.7..-15.0, z 6.0..13.0.
  * Each bay has 4 uprights 0.12² h6.6 and shelves at +0.3/1.8/3.3/4.8/6.3, with 2-3 labelled boxes per shelf (kraft or white, label plate TextLabel): 거즈, 주사기 1cc/3cc/5cc, 수액세트, 생리식염수 1L (crate of bags), 마스크 KF94, 니트릴 장갑 M/L, 알코올 솜, 드레싱 키트, 소독제, 붕대, 반창고, 검체 용기, 체온계 커버, 환자복, 시트·베개커버, 일회용 가운.
* **Linen cart:** x -24.0..-21.4, z 8.0..9.6, h3.6, steel frame, 3 tiers of folded linen + canvas hamper.
* **Wheelchairs ×2** (folded, parked): x -16.8..-15.2, z 2.6..5.4.
* **O₂ cylinders ×3:** d0.85 h4.6, green (40,120,70) + white shoulder + valve, chained to a wall bracket; x -29.6..-26.0, z 2.1..2.9; sign "산소 O₂ · 화기엄금".
* IV poles ×2, step ladder.
* 2 LED tube fixtures + **1 SurfaceLight** + light switch.
* Clipboard "재고 점검표" (prompt "재고 확인" → toast "거즈 42 · 주사기 3cc 120 · 수액세트 36 · KF94 400 · 장갑 M 12박스 (10/16 점검 · 간호부 박선생)").
* Signs "선입선출 (FIFO) · 유효기간 확인", "물품 반출 시 장부 기록".
Parts ≈ 300.

### 7.6 East wall: 응급실 출입구 and 비상구 (Hosp_Exits)

**East wall replacement.** `Lib.replaceWall(GroundSide east, openings)` builds these segments (Concrete (196,188,174), x 59.11..59.91):

| Segment | z | y |
|---|---|---|
| E1 | -35.22..12.00 | -0.40..13.00 |
| E2 | 17.00..27.58 | full |
| E3 | 31.58..39.58 | full |
| E4 ER lintel | 12.00..17.00 | 8.00..13.00 |
| E5 FE lintel | 27.58..31.58 | 8.00..13.00 |

FireExitDoor is hidden and un-collided (the passage is ours); PushBar is hidden.

**응급실 출입구** (z 12.00..17.00, 5.0 = 1.4 m clear, y 0..8.0):

| Part | spec |
|---|---|
| Inner door set (treat-room side) | 2 leaves x 58.90..59.05, closed z 12.05..14.50 / 14.50..16.95, y 0.05..7.90; open → z 9.60..12.05 / 16.95..19.40 (slide along the inner face). Glass (200,224,230) t0.45, alu frames, frosted red band (220,60,60) at y 3.2..4.2 "응급실 EMERGENCY", "자동문" stickers. Header x 58.55..59.11, y 8.05..8.85, z 9.4..19.6, stainless + sensor |
| Outer door set | x 59.97..60.12, same z/y, header x 59.91..60.55 |
| Opening returns | alu x 59.11..59.91 at z 11.85..12.00 / 17.00..17.15; threshold x 58.90..60.20, y 0..0.06 |
| Ramp outside | wedge x 60.12..62.60, z 12.00..17.00, from y -0.34 to 0.00 |
| Canopy | slab x 59.91..65.50, y 9.40..9.70, z 10.0..19.0 (white) + red fascia x 65.40..65.50, y 9.10..9.70 "응급실 EMERGENCY" (facing +x) + 2 tie rods + downlight with **SurfaceLight** at night (ClockTime ≥ 18 or < 6) |
| Light box | x 59.91..60.25, y 10.0..11.6, z 12.0..17.0, red neon box, glowing "응급실 / EMERGENCY" |
| Outside 호출 button | plate x 59.91..60.0, z 17.4..17.9, y 3.6..4.6. **Prompt "응급실 호출"** → chime + toast "응급실에 연락했어요. 의료진이 곧 나와요 (연출)" |
| Floor markings | yellow stripes x 61.0..61.2 and 66.8..67.0 along z 3.6..12.0, "응급실 ▲" text decals x 63..65, at y -0.33 (on PlotPaving) |
| Inside | plate "응급실 출입구 · 구급차 전용" at x 58.50, y 9.0..9.8; **피난구 유도등 "출구"** above the header (y 9.2..9.9); yellow 응급 동선 strip x 54.2..58.9, z 14.4..14.6, y 0.03 |
| Sensors | inside zone x 54.2..59.11, z 11.0..18.0; outside zone x 59.91..65.0, z 11.0..18.0. Both sets open together (0.6 s), close 1.5 s after empty. Leaves collidable when closed |

**비상구** (z 27.58..31.58, y 0..8.0, opens outward):

| Part | spec |
|---|---|
| Leaf | steel (140,144,148) 3.95×7.95×0.25 at x 59.35..59.60, z 27.62..31.54. **Hinge (x 59.60, z 31.54), swings outward (+x) to 95°**. Collidable only when closed. Sticker inside "방화문 · 항상 닫아 두십시오" |
| Panic bar (inside) | bar x 58.95..59.30, y 3.6..4.1, z 28.0..31.0 (red + stainless end boxes); depresses 0.12 in +x for 0.12 s before the swing |
| Outside | lever handle at z 28.3, y 3.8; small canopy x 59.91..62.5, y 8.8..9.0, z 27.0..32.2; bulkhead lamp (neon + **PointLight** Range 12 at night); sign "비상구 · 문 앞 물건 적치 금지" |
| Interaction | inside prompt "비상구 열기" on the bar, plus **auto-push** when the local HRP is within 1.4 of the inner face inside the door span with `MoveDirection·(+x) > 0.6`; outside prompt "문 열기" on the lever. Open: `clickfast` 0.6 + `action_jump_land` 0.7 + 3 short beeps (`electronicpingshort` 2.0) + toast "비상구 문이 열렸어요 (비상시에만 이용해 주세요)". Close 3 s after nobody is in K07/K08: hydraulic 1.8 s to 8° then latch 0.25 s + thunk |
| T_clinic | keeps its exit sign above (y 8.75..9.85) and the hydrant |

### 7.7 2F landing passage (map fix), 2F roof-stair door, stairwell P3, RoofDoor

**Landing passage.** `Lib.replaceWall(BackWall2 piece x -8.09..33.91)` with opening x -7.60..-4.00, y 14.15..21.50 (below the 2F WayBand at 21.55):

| Part | spec |
|---|---|
| Segments | R1 x -8.09..-7.60, R2 x -4.00..33.91 (full height 14.15..22.60), R3 lintel x -7.60..-4.00, y 21.50..22.60; z -4.42..-3.82, Plaster (222,218,208) |
| Frame | jambs x -7.75..-7.60 / -4.00..-3.85 (both faces), head y 21.35..21.50, threshold y 14.15..14.20 |
| 방화문 (held open) | 3.5×7.25×0.15 grey-ivory steel, **hinge x -7.55 on the landing side, permanently open 92°** (lies at x -7.55..-7.40, z -3.82..-0.32), magnetic holder box on the CheckupWall at z -0.6, y 17.5; label "자동폐쇄 방화문 · 화재 시 자동으로 닫힙니다" |
| Signs | corridor side "계단 · 비상구 / 옥상 정원 RF" (§7.4); landing side "복도 · 입원실 · 간호사실 · 검진센터 →" at x -3.6..-0.8, y 19.0..20.2 on R2's north face; hanging 피난구 유도등 in the corridor at (−5.8, 21.7..22.4, -6.2), double-sided "🏃 비상구 · 계단" |

**2F roof-stair door** (landing back wall, centre x -5.95, wall face z 38.94):
* frame + steel fire door 3.2×7.3 (x -7.55..-4.35); 피난구 유도등 above (y 21.75..22.43);
* plate "비상계단 · 옥상 RF ↑" at x -4.1..-3.4;
* **prompt "옥상 계단으로"** (ObjectText "비상계단") → P3 bottom; return spawn (-5.95, 14.15, 36.0) facing -z (floor present: Floor2 x < -3.33 plus the back strip).

**P3 비상계단** (interior x -10.0..-1.4, z -24.0..-7.0, y -50.0..-30.5; W(-524.8,-43.1,275.7)..(-515.6,-23.6,293.0)):

| Element | spec |
|---|---|
| Bottom landing (2F level) | y -50 (top), z -24..-19.5, full width |
| Flight 1 (west half x -10.0..-6.0) | 8 solid steps rise 0.6906, run 1.0, from z -19.5 north to -11.5 (step k top = -50 + 0.6906k) |
| Mid landing | x -10..-1.4, z -11.5..-7.0, top -44.475 |
| Flight 2 (east half x -5.4..-1.4) | 8 steps from the mid landing south to z -19.5, top -38.95 |
| Top landing (RF level) | x -5.4..-1.4, z -24..-19.5, slab -39.45..-38.95 (headroom over the bottom landing 10.55) |
| Railings | steel balusters every 1.0 + handrail d0.16 at +3.0 on walls and the 0.6 gap (x -6.0..-5.4); top-landing west edge: solid steel/glass panel 3.3 tall + invisible collider |
| Doors | bottom: x -9.7..-6.3, y -50..-42.8, z -24.0..-23.85, steel 방화문 + panic bar, **prompt "2층으로 나가기"**, spawn in (-8.0, -50, -21.6) facing +z. Top: x -5.1..-1.7, y -38.95..-31.75, **prompt "옥상으로 나가기"**, spawn in (-3.4, -38.95, -21.6) facing +z |
| Finish | concrete two-tone (lower (150,152,154) to +3.5, upper (236,236,232)), yellow/black nosing on each step, wall graphics "2F" (west wall bottom landing, 3.0 tall), "RF ↑ 옥상" (mid landing north wall), "RF 옥상" (top landing east wall); 피난구 유도등 over both doors; "옥상 출입문 · 비상시 자동 개방"; fire extinguisher; 2 bulkhead lamps with **PointLights** (Range 14) |

Parts ≈ 180.

**RoofDoor (roof side):**
* hide `건물/RoofDoor` (keep its collision);
* our steel leaf x 36.55..39.70, y 25.20..32.15, z -2.40..-2.25 + frame + push bar;
* canopy x 35.8..40.4, y 32.6..32.8, z -4.0..-2.22; 피난구 유도등 above (y 32.9..33.6); lamp;
* **prompt "계단으로 내려가기"** (ObjectText "비상계단 · 2층") → P3 top; roof spawn (38.13, 25.2, -4.8) facing -z.

### 7.8 Roof garden (Hosp_Roof; roof top y 25.20)

| Element | spec (local) |
|---|---|
| Lift exit paving | pavers x -34.6..-29.6, z 26.0..33.3, y 25.20..25.30 |
| Main deck | WoodPlanks (150,110,78) x -50.0..-22.0, z 4.0..26.0, y 25.20..25.50 + alu edge trim |
| Pergola | posts 0.6² at (-46,8), (-46,20), (-32,8), (-32,20), y 25.5..33.1, dark wood (92,66,46); beams along x at z 8/20, 0.5×0.8×15, y 32.6..33.4; 11 rafters 0.25×0.5×13.5 every 1.5 at y 33.4..33.9 |
| String lights | 4 catenary runs between the beams, warm neon bulbs d0.22 every 1.2 (≈ 40) + wires; **2 PointLights** (Range 18, Brightness 0.8, warm) on at ClockTime ≥ 18:30 or < 06:00 |
| Tables | 2 round teak d3.2 on alu pedestals at (-42,14) and (-36,14), 4 chairs each (client Seats) |
| Benches | B1 x -47.0..-40.0 and B2 x -38.0..-31.0 at z 23.6 facing south (teak + steel, client Seats) |
| Planters | P-west x -52.5..-50.0, z 4.0..26.0, h2.4 (corten (120,72,48)) with shrubs and grasses; P-south x -50..-26, z 1.0..3.6, h1.6, flowers; P-north x -50..-36, z 26.2..28.0, hedge; tree planters d3.2 h2.0 at (-24,6) and (-24,23), small maples in **autumn colours** ((180,60,40) / (214,120,40)) |
| View deck | x -50.0..-24.0, z -35.2..-29.5, y 25.20..25.45; benches x -47..-41 and -33..-27 at z -31.5 facing south; panorama board "광안리 해변 · 광안대교 방향" 2.8×1.6 on the rail |
| Telescope | at (-37.0, 25.45, -34.2) facing -z: base, post d1.0 h3.0, binocular head, eyepiece. **Prompt "광안대교 보기"** |
| Paths | stepping pavers x -38..-35, z -29.5..4.0; RoofDoor path z -5.4..-4.0 from x 36 to -22 (clear of ACSkid fence z ≤ -12.5 and VentStack z ≥ 7.9); bollard lights (neon caps) ×8 |
| Mechanical fences | chain-link look (alu frame + Fabric (150,154,158) t0.55) h4.4 around WaterTank x -14.0..-5.5, z 16.5..25.5 and ACSkid x -18.5..-5.0, z -19.0..-12.5; gate + "기계실 · 관계자 외 출입금지" |
| Safety rail | on the coping (y 28.42): stainless posts 0.15² every 6.0, Glass (200,220,226) t0.5 panels y 28.42..29.62, top rail d0.18 at y 29.7, all 4 sides (≈ 140 parts) + **invisible guards** (Transparency 1, CanCollide true, CanQuery false) on the parapets to y 34.0 |
| Signs | board on the penthouse W wall outer face (x -36.20) z 34..37, y 27.0..29.6: "하늘정원 · 옥상 휴게공간 / 이용 시간 09:00~21:00 · 금연 · 환자분은 보호자와 함께"; standing "🚭 금연 구역 · 위반 시 과태료 10만원 (국민건강증진법)" ×2 (deck, RoofDoor); "난간에 기대거나 올라가지 마세요" ×3 on rails |

**Telescope view:**
1. Prompt → `ui.scope(true)` (black screen with a circular window: Frame + UICorner(1,0) + UIStroke thickness 2000 black).
2. Camera Scriptable. Eye search: start from E = eyepiece and raycast toward T = W(0, 230, -3300), excluding our folder and characters. If the first hit is not under `Gwangalli.bridge`, raise E by +15 (max +120) until it is clear. The measured obstacles mean expect about +75.
3. FOV 70 → 22 over 0.8 s; slow pan ±4° (0.08 Hz).
4. Toast "광안대교 · 총연장 7,420m · 2002년 개통 · 밤에는 경관조명이 켜져요".
5. Exit on prompt again, Jump/ButtonA (ContextActionService), moving away more than 3, or 30 s → restore CameraType, FOV and CFrame.

Parts ≈ 470 (high tier). Lights: 2 at night.

### 7.9 Wayfinding (Hosp_Signs + the kits above)

* **피난구 유도등** (green neon box + "🏃 비상구" / "출구"): ER inner header; RoofDoor; 2F roof-stair door; 2F corridor (hanging, at the passage); P3 doors. **T_clinic owns the 1F fire-exit one.**
* **통로유도등** (low, y 0.9..1.5): restroom front (→ east); 2F WardWall corridor face at x 30 (← to the passage) and x -40 (→); P3 mid landing.
* **Floor numbers:** "1F" 1.6² TEAL plate at x 24.4..26.0, y 7.7..9.3 on the BackWall north face next to map `Sign_2F ↑` (K23); "2F" 3.0×3.0 on the CheckupWall east face (x -8.09) at z 28.5..31.5, y 17.2..20.2; "↓ 1F" at z 24.5..26.0; lift-jamb plates "1F/2F/RF"; P3 wall graphics.
* **층별 안내:** 2F on the enclosure E face (§7.3). 1F is T_clinic's backhall directory (C4 text change).
* **Relocated "건강검진 안내"** board (TEAL band + "접수 → 신체계측 → 혈압 → 시력 → 청력 → 심전도 → 상담"): PartyWall x -27.4..-20.0, y 17.2..21.2 (K19).
* Corridor name plates, 진료 중 lamp and wait monitor: §7.4.

---------------------------------------------------------------------------------------------------

## 8. Lifecycle, budgets, performance

**Director (4 Hz, `task.wait(0.25)`):**
1. `pos = ctx.focus()`. Flat distance d to CENTER (-515,300).
2. Build when d < 140 and `Lib.hospital()` exists with its anchor parts (GroundBack, GroundSide east, Floor, BackWall2 piece, ElevatorDoor). Missing anchors (streaming) → retry next tick.
3. Build order: `exits` (visible from the street/bay) → `lift` → `hall1` → `doors` → `level2` → `roof`. `roof` is built when d < 90 or pos.Y > 18. Each zone is a coroutine; Kit time-slices at 2.5 ms per frame; only one zone builds at a time.
4. Tear down (reverse order) when d > 170 and the player is not in a portal. Teardown = `Lib.restore(K)` + folder destroy + disconnect.
5. Every 1 s: `Scan.reapply` on all hidden stores, wall-replacement reacquire, cabin light timer.
6. Portal watchdog (§7.1).

**Anim loop:** Heartbeat accumulator at 10 Hz → every zone's `K.anims` (door sensors, elevator state machine, lamps, motion lights, clocks, screens). TweenService drives the motion. `BindToRenderStep` is used only for the one-frame elevator shift.

**Budgets (high / mid / low from `ctx.limits()`):**

| Zone | parts high | mid | low | lights |
|---|---|---|---|---|
| hall1 (restrooms) | 320 | 260 | 180 (no wall-tile bands, simplified toilets) | 2 (motion, only while inside) |
| lift | 300 | 280 | 220 | 1 |
| doors | 140 | 120 | 80 | 0 |
| exits | 160 | 140 | 100 | 1 ER canopy + 1 fire-exit lamp (night) |
| level2 | 120 | 100 | 70 | 0 |
| roof | 480 | 300 | 140 (penthouse, rails, deck, telescope only) | 2 (night) |
| portal (one room at a time) | 340 | 300 | 200 | 2 |
| **total** | **≈ 1,860** | 1,500 | 990 | **≤ 7 at once** (≤ 10 required); low tier: 3 |

Prompts at once ≈ 45 (only those within 5 studs show).

**Teardown on stop:** restore hidden parts and textures, restore CanCollide (GroundSide, BackWall2, FireExitDoor), destroy folders and UI, unbind ContextActionService, disconnect all, reset the camera if the scope is open, and run `back()` first if the player is in a portal.

---------------------------------------------------------------------------------------------------

## 9. Korean UI strings (prompts / toasts)

* Prompts:
  * 물 내리기, 손 씻기, 손 말리기, 잠그기, 잠금 해제, 비상벨 누르기, 기저귀 교환대 펼치기, 기저귀 교환대 접기
  * 엘리베이터 호출, 층 선택
  * 들어가기, 그래도 들어가기, 나가기, 옥상 계단으로, 2층으로 나가기, 옥상으로 나가기, 계단으로 내려가기
  * 비상구 열기, 문 열기, 응급실 호출, 광안대교 보기
  * 커피 내리기, 데우기, 냉장고 열기, 사물함 열기, 사물함 닫기, 채널 바꾸기, 게시판 보기, 근무표 보기, 재고 확인, 물 틀기
* Toasts:
  * 관계자 외 출입금지 구역이에요. 들어가려면 한 번 더 누르세요.
  * 직원 휴게실 / 창고 / 비상계단 (fade captions)
  * 1층입니다 / 2층입니다 · 입원실 · 건강검진센터 / 옥상입니다 · 옥상 정원
  * 비상벨이 울렸어요. 직원이 곧 확인해요 (연출) / 비상벨이 울렸습니다. 관리실과 연결 중이에요 (연출)
  * 비상구 문이 열렸어요 (비상시에만 이용해 주세요) / 응급실에 연락했어요. 의료진이 곧 나와요 (연출)
  * 따뜻한 아메리카노 ☕ / 광안대교 · 총연장 7,420m · 2002년 개통 · 밤에는 경관조명이 켜져요
  * 지금은 이동할 수 없어요 (canTravel fail: 앉아 있거나 치료 중일 때)

---------------------------------------------------------------------------------------------------

## 10. Test and preview plan

* **Compile:** `luau-compile --binary` on every `HospitalPlus.luau` / `Hosp_*.luau`.
* **Offline preview:**
  * Fixture `bprev/fx/hosp_facility.luau` + `.scene.json` = the full hospital tree (same export as `hospital_backhall`, which already contains the whole `광안 메디컬 의원` model) plus `광안 메디컬 의원 (건물)`.
  * Driver `bprev/simhosp.luau` (scratch copy of sim.luau): loads the fixture, requires `HospitalPlus` from the bundle, calls `HospitalPlus._buildAll(mockCtx)` (all zones, portal rooms built in place, no UI), and dumps `parts` + `hidden` JSON in the sim.luau format.
  * Render with `node preview.js hosp_facility --gen … --cams cams/hosp_facility.json`.
* **Cameras (W; pos = character, eye/at):**
```json
[{"name":"hosp_rr_hall","pos":[-543.8,6.9,324.07],"eye":[-543.77,12.4,323.07],"at":[-563.86,10.9,325.62]},
 {"name":"hosp_rr_women","pos":[-565.82,6.9,327.35],"eye":[-565.11,12.5,326.98],"at":[-572.15,9.9,334.15]},
 {"name":"hosp_rr_men","pos":[-561.52,6.9,327.49],"eye":[-562.51,12.5,326.96],"at":[-554.69,9.9,335.72]},
 {"name":"hosp_lift_1f","pos":[-539.84,6.9,325.2],"eye":[-538.81,12.9,324.23],"at":[-548.18,10.9,332.33]},
 {"name":"hosp_lift_cabin","pos":[-548.24,6.9,334.43],"eye":[-548.2,12.3,333.13],"at":[-548.34,11.1,337.23]},
 {"name":"hosp_lift_2f","pos":[-555.76,21.05,322.68],"eye":[-555.76,26.9,322.68],"at":[-548.18,24.9,332.33]},
 {"name":"hosp_lift_rf","pos":[-547.77,32.1,322.94],"eye":[-547.7,37.9,320.94],"at":[-548.17,35.9,332.23]},
 {"name":"hosp_er_out","pos":[-449.3,6.9,310.15],"eye":[-445.22,13.4,307.79],"at":[-455.61,10.9,316.45]},
 {"name":"hosp_er_in","pos":[-465.52,6.9,316.63],"eye":[-467.5,13.4,316.06],"at":[-456.51,10.9,316.42]},
 {"name":"hosp_fe_out","pos":[-450.02,6.9,332.14],"eye":[-448.0,13.4,331.81],"at":[-456.1,10.9,331.54]},
 {"name":"hosp_pass_2f","pos":[-524.75,21.05,292.18],"eye":[-526.71,26.5,291.01],"at":[-520.66,24.9,295.71]},
 {"name":"hosp_roofstair_2f","pos":[-521.88,21.05,329.79],"eye":[-522.45,26.5,328.77],"at":[-522.22,24.9,338.68]},
 {"name":"hosp_glass_consult","pos":[-528.86,6.9,295.54],"eye":[-527.38,12.5,296.19],"at":[-534.88,10.9,292.95]},
 {"name":"hosp_roof_garden","pos":[-534.66,32.1,289.35],"eye":[-532.6,40.9,287.42],"at":[-553.47,33.9,313.75]},
 {"name":"hosp_roof_view","pos":[-550.97,32.1,267.81],"eye":[-551.13,36.9,272.8],"at":[-550.87,33.9,264.81]},
 {"name":"hosp_p1_staff","pos":[-527.91,-43.1,324.59],"eye":[-519.63,-38.1,334.37],"at":[-533.81,-41.1,324.4]},
 {"name":"hosp_p2_store","pos":[-537.25,-43.1,304.27],"eye":[-531.4,-38.6,311.97],"at":[-542.15,-41.1,304.11]},
 {"name":"hosp_p3_stair","pos":[-522.29,-43.1,278.25],"eye":[-517.22,-34.1,291.42],"at":[-522.44,-39.1,282.75]}]
```
  Night pass: `--night` for string lights, ER box and lamps.
* **Temp studio:** `tools/build_studio_cabin.py` with `BLD_SRC` = this folder, then `harness/bld.js` with the shots above (under `flock …/.studio.lock timeout 1500`). Scripted checks via `GW.engine.eval`:
  1. Walk through the restroom doors (auto swing).
  2. Lock and unlock a stall.
  3. Elevator 1→2→R→1 (assert HRP Y = floor + hip, cabin pivot, indicator).
  4. ER in and out, fire exit out and in.
  5. 2F stair → passage → corridor.
  6. STAFF and 창고 portals in and back (assert positions; jump < 160).
  7. Roof-stair round trip.
  8. Telescope.
  9. Teardown restores GroundSide/BackWall2 `CanCollide=true` and Transparency.

---------------------------------------------------------------------------------------------------

## 11. Patches needed outside my files (for the orchestrator / other agent)

**P-1 (required; `init.client.luau`, line 235): venue rooms of skipped groups never build (F2).**
```lua
-- 큰 시설 (Venues.LIST) 은 그룹 루트가 SKIP_ROOTS(club · bowling · garage · hospital) 안에 있어도 짓는다.
-- SKIP_ROOTS 는 일반 매장 후보(addCandidate) 스캔용이다.
local function skippedVenue(m: Instance): boolean
	return m:GetAttribute("GwInterior") == false or m:GetAttribute("ShopLife") == false
end
...
		if not recs[spec.key] and not skippedVenue(f.model) then   -- was: not skipped(f.model)
```

**P-2 (optional; `Scan.luau`): ref-counted hide**, so two stores hiding the same part restore correctly.
* Add weak tables `hideCount[p]` and `hideOrig[p]` (Transparency + LTM captured on the first hide).
* In `Scan.hide`: increment the count; take `rec.t` from `hideOrig`.
* In `Scan.restore`: decrement; restore only when the count reaches 0, and restore from `hideOrig`.
* Not needed with the ownership split in §3; recommended for robustness.

**P-3 (requests to the T_clinic author):**
1. Remove the backhall `hangSign(K, 51.0, -4.6, …)` restroom sign (C1).
2. Add `facility_room` world keeps to ceilingKit `avoid` in backhall and checkup (C3).
3. Change the floor directory R line to "R   옥상 정원 · 휴게 공간" (C4).
4. Do not hide or reskin the parts on the ownership list (§3).
5. If T_clinic adds free wall finishes in treat/backhall/checkup, skip u-ranges of `opening` / `facility_room` world keeps.

No change is needed in Kit, Props, Interact or Common.

---------------------------------------------------------------------------------------------------

## 12. Risks and fallbacks

| Risk | Mitigation |
|---|---|
| Wall replacement looks different from the map wall (GwangalliTex grime, MaterialVariant) | copy Color/Material/Reflectance/MaterialVariant and Textures (optionally `GwangalliTex`). Fallback `Geo.EAST_MODE = "step"`: keep GroundSide; leaves on both faces; when a door is open and the HRP is within 1.0 of a face inside the span moving into it, `PivotTo` 2.4 across (a 2.4-stud jump, invisible behind the open leaves). Same flag for BackWall2 (`LANDING_MODE`) |
| Streaming swaps GroundSide/BackWall2 instances | 1 s reacquire by name + centre; segments stay; restore only touches live parts |
| Character physics pause after an underground teleport (StreamingIntegrityMode default) | teleports happen under the fade; `RequestStreamAroundAsync` pcall; the client-built floor exists before the jump |
| Server teleports a player out of a portal (collapse → ward) | watchdog un-fades and cleans up |
| Elevator shift during a jump/landing | the shift is applied to the whole character pivot plus the camera in one RenderStep; the velocity is kept |
| NPC visually clips the lift-enclosure corner on bench→lift1 | ≤ 1 stud, at the moment it vanishes; acceptable |
| Players jumping off the roof | glass rail + invisible guards to y 34.0 |
| Low-end devices | tier budgets (§8); roof furniture and tile bands skipped on low |
| T_clinic not yet updated (C1 sign inside the restroom) | HospitalPlus can additionally ghost-hide any part named `HangSign*` from other GwInteriorDetailLocal venues whose centre lies inside K01 (local-only, our parts are unaffected). Kept as a last resort; prefer the request |
