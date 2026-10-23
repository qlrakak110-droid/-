# Reskin research: GwangalliBuildings runtime interiors → client AAA reskin

Scope: every runtime-built GwangalliBuildings interior (광안 종합병원 first, then the district buildings, Annex buildings, homes / hotel rooms / offices / lobbies / restrooms). The client builds a detailed, real-world version of each Furniture-catalog item and of the hospital's own fixtures and medical equipment. The reskin happens locally (originals hidden on this client only, gameplay untouched). It also dresses rooms (ceilings, wall rails, signage, accessories).

Files made by this research (all scratch, read-only reference for the team):
- `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/reskin/tools/catalog_dump.txt`: every part of every catalog item, built by the real Furniture module in the mock runtime: item-local pos / size / rot / material / colour / transparency / collide / tags / attrs / lights / sounds.
- `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/reskin/tools/catalog_summary.json`: per item, the dims, kind, colourways and gameplay parts (Seats with top Y, LieSpot, Screen rects, Lamp parts, Spin, Water heads, hinged doors, Hit / solid boxes, sounds).
- `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/reskin/fx/<itemId>.scene.json` (67 files): the original item at the origin (front = -Z, floor y = 0), with a 24x24 floor and a wall behind it (+Z). The format is bprev's preview.js scene format.
- `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/reskin/tools/preview_rs.js`: a copy of bprev/preview.js. It reads `--scene <file>` (default `feat/reskin/fx/<key>.scene.json`), with gen / out defaulting under `feat/reskin/{out,shots}`. It uses the same global 3-slot render queue. `tools/cams_item.json` holds 4 world cameras (front, left34, right34, top) for an item at the origin.
  Example: `node preview_rs.js sofa3 --base --cams cams_item.json --out <dir>` renders the original. With `--gen <gen.json>` it overlays the reskin and drops the `hidden` part ids.
- `tools/mkcat.py` → `tools/cat_mods.luau` bundles the place's shared Kit + Furniture for the mock (`require("./cat_mods")` gives `{ Kit, Furniture, R }`). It shims CollectionService, because the mock `GetService("CollectionService")` from a bundled module is a dummy whose HasTag always returns true. `tools/catdump.luau`, `tools/catscene.luau` and `tools/summ.py` regenerate the files above.
- Luau CLI gotcha: script args need `-a` (`luau x.luau -a arg1 arg2`). Without it, args are treated as extra files.

---------------------------------------------------------------------------------------------------

## 1. Where the runtime buildings live

```
Workspace.GwangalliBuildings                         Folder (Names.ROOT)
  <BuildingId>                                       Model, tag GwB_Building; attrs BuildingId, Kind (archetype), DisplayName,
                                                     Floors, Wear, BoundsCF, BoundsSize, Annex? (true for Annex buildings)
    Shell                                            Model (always present): facade, slabs, roof, signs. Contains rooftop
                                                     catalog items (sunbed on officetel / hotel roofs) + hospital forecourt Bench
    Interior                                         Model, tag GwB_Interior, attr BuildingId. Built when a player comes within 42,
                                                     parked to ServerStorage after nobody is within 85 for 25 s (re-parented,
                                                     so the client sees remove → add as NEW instances)
      Elevators                                      skip (GwB_Elevator, ElevClient animates)
      Floor_<label>                                  Model attrs BuildingId, Floor, Y (= fl.y, building-local FFL height)
        stair pieces, walls, doors (Door_* GwB_Door), corridor (FloorFinish, Ceiling, LightPanel+Light, Hydrant, CCTV)
        hooks.floor content: THE WHOLE HOSPITAL (beds, chairs, equipment, desks, catalog items) lives here directly
        Shop_<shopId>                                Model tag GwB_Shop; attrs ShopId, ShopKind, DisplayName, BuildingId, Floor,
                                                     Frame (world CFrame of the shop's x0/z0 corner frame), W, D
          ShopFloor, ShopCeiling, Lining, counters, Point_* (GwB_ShopPoint), Seats (GwB_Seat), catalog items
          Furnish                                    per-storey props (furnish pass)
        Unit_<number>                                Model tag GwB_Unit; attrs UnitId, BuildingId, Floor, Template, Tier, Price,
                                                     ForSale, OwnerUserId, Mirror, Frame (world unit frame), W, D, Label, Hotel
          Structure                                  walls, Partition, Wallpaper (GwB_Finish), Floor (GwB_Finish), Ceiling,
                                                     LightPanel (+room light, off by default), entrance + room doors, Glass
          Fixtures                                   built-in catalog fixtures (attrs UnitId, Fixed=true, W for kitchen_counter)
                                                     + Switch parts (BasePart tag GwB_Fixture Kind=switch, RoomIds, Label)
          Furnish                                    staging furniture (Staging=true) OR owner's layout (Placed=true, Uid,
                                                     OwnerUserId, tag GwB_Placed)
          Rooms                                      Room_<id> BasePart, tag GwB_Room; attrs RoomId, UnitId, Kind, Label
                                                     (invisible bounds: CFrame = unit frame * (centre, ceil/2), size (w, ceil, d))
        Furnish                                      tag GwB_Furnish (per storey; lobby sofas / plants: hooks.furnish)
  Annex                                              Folder: Annex storefront rooms (Model attrs AnnexRoom=true, ShopLifeType,
                                                     ShopLifeMenu, ShopLifeKey; children ShopFloor, Interior, Outside) at y≈3000
  AnnexDoors                                         Folder of door prompts on the real map
Workspace.GwangalliBuildingsShopLife/<shopKey>/Anchors   ShopLife prompt anchors (LifePrompt), dishes. Keep clear.
Workspace.GwangalliHospital                          invisible HospitalPoint parts (NPC posts, 119 points). Not visual.
Workspace.GwangalliInfill                            parks / lots (Infill fixtures, optional chunk O1)
ServerStorage.GwangalliBuildingsParked               parked interiors (not replicated)
```

Streaming: `StreamingEnabled=true`. GwB Models use the default ModelStreamingMode, so the Model container arrives first, with its attributes, and its parts stream in one by one. An item can be seen before its Base / Seat / detail parts exist. Interiors are built over many frames (server Kit budget 260 parts per step). Furnish storeys are built per storey near players (`FURNISH_RADIUS` 45, `UNFURNISH_AFTER` 30 s) and the hospital floors exist whole while the interior is hot.

Buildings that use the catalog:
- District (origin `CFrame(4283.5,18.9,-200)*yaw(-90)`, 13-stud podium), 8 lots:
  - apartment 광안 오션뷰: B1 parking, a 1F lobby with a 관리사무소 desk + bookshelf, homes, a penthouse.
  - officetel 해오름: GW25 cvs, a 관리실 office shop, rooftop sunbeds.
  - villa 광안하우스: plus 옥탑방.
  - oneroom 해변 원룸텔.
  - plaza 광안 프라자: 국밥 + 부동산 on 1F, PC방 2F, 노래방 3F, 당구장 4F, restrooms on every floor.
  - hotel 씨사이드: lobby, Royal casino, rooms 4-7F, rooftop sunbeds.
  - bbq 숯불갈비 1F/2F.
  - cafe SEA BREEZE: 1F/2F + rooftop.
- 광안 종합병원 (id `hospital`).
- 삼진전파사 hideout: no catalog items.
- Annex buildings (`annex_<hash>`, at y 3000, slot grid 560 studs from (-9600,3000,-9600)): apartment, officetel, villa, oneroom, hotel, plaza, and `venue` (PC방 / 노래방 / 당구장).
- Annex storefront rooms (`Annex/Rooms`): their catalog pieces include sofa3, water_dispenser, aquarium, bed_single (vet), punching_bag, piano, drum_kit, pc_desk, treadmill, bench_press, dumbbell_rack, office_desk, bookshelf, monstera, massage_chair, armchair, desk, projector_screen, washer.

Shop templates in district / Annex buildings (Builder/Shops T.*): cvs, gukbap, bbq, cafe, pcbang, karaoke, billiards, realtor, hotel_lobby, office. These are **ShopFlows** shops (GwB_Shop, Point_* anchors).

**ShopLife** runtime shops:
- Annex storefront rooms (types soup, noodle, katsu, grill, rawfish, seafood, pocha, pub, chicken, snack, chinese, cafe, burger, dessert, bakery, cvs, retail, pharmacy, laundry, realty, lobby, residence, salon, clinic, academy, gym, bank, office, play).
- The hospital departments (`ShopLifeType` clinic / pharmacy, see §3).

The main client system (init.client.luau) builds AnnexRoom rooms and map shops only. It never touches GwB district / Annex-building / hospital interiors (`isShop` needs ShopFloor+Interior / AnnexRoom / GwShop+ShopBounds). So for GwB buildings the reskin is the only client detailer.

Catalog usage counts (server code): washbasin 21, toilet 17, monstera 17, sofa3 16, tv55 15, wallpad 13, shower 13, armchair 12, desk 11, microwave 10, kitchen_counter 10, fridge 10, bed_single 10, wardrobe 9, coffee_table 9, bed_queen 9, water_dispenser 8, washer 8, vending 7, dining2 7, tv_small 6, then the rest. The Grades.ROOMS sets (gameroom, cinema, gym, workshop, dressroom, homebar, music, office, guestroom) and the decor shop can place any item in owners' homes.

---------------------------------------------------------------------------------------------------

## 2. The Furniture catalog (ReplicatedStorage.GwangalliBuildingsShared.Furniture)

`Furniture.build(itemId, parent, cf, colorway?, extraAttrs?)` builds each item as a Model:
- Name = itemId.
- PrimaryPart **Base**: invisible box w×max(h,0.2)×d centred at `cf * (0, mountY + h/2, 0)`, CanCollide=false, CanQuery=true.
- Attributes: `ItemId`, `Colorway` (clamped 1..#colors), `Label` (Korean name), `Kind` (only when def.kind), plus extraAttrs, which are applied **before** build: `Public`, `UnitId`, `ShopId`, `Fixed`, `Staging`, `Placed`/`Uid`/`OwnerUserId`, `W` (kitchen_counter width), `Ghost` (DecorMode preview, parented directly to Workspace), `RoomSet`.
- Tag `GwB_Fixture` **only when def.kind exists**. 12 items have no kind and no tag: coffee_table, monstera, bookshelf, rug, frame_art, aquarium, shoe_rack, drying_rack, tool_wall, parts_shelf, closet_island, liquor_shelf.

Item frame: origin = floor centre of the footprint, **front = -Z** (the side you use it from), so wall items back onto +Z. Recover it on the client with `F = Base.CFrame * CFrame.new(0, -(mountY + h/2), 0)`. Read w/d/h/mountY from `Furniture.ITEMS[id]`: the client can `require(ReplicatedStorage.GwangalliBuildingsShared).Furniture`, because GwangalliBuildingsClient already does. Do not use Base.Size.Y: rug h=0.1 has Base 0.2.

- **kitchen_counter**: Base is always 9 wide (def.w), but the real width is attribute `W` (5, 6, 7, 8, 14 in templates). Build to `W`.
- Colourways: the builder receives colours rotated so `c[1] = colors[Colorway]`, `c[2] = colors[Colorway+1]`, and so on, wrapping. Mirror that: primary = colors[cw], secondary = next.
- Part naming: details are mostly named `Part`. Named parts are listed below. All details have CanCollide=false. Collision comes from invisible `Hit` boxes and from parts with `collide/solid=true`.
- Seats: class Seat named `Seat`, size 1.8×0.3×1.8, Transparency 1, CanCollide=true, Disabled=true, tag `GwB_Seat`, attr `Index`. Seat top = centre + 0.15.
- Beds and sunbed: `LieSpot` anchor part. The server poses the character at its CFrame (look = +Y, head toward +Z).
- Screens: part `Screen`, tag `GwB_Screen`, attr `ScreenKind` (tv, pc, game, cinema, office, treadmill, wallpad). The SurfaceGui is drawn by the GwangalliBuildingsClient **Living** module on the part's **Front (-Z) face** while the fixture `On`. Living creates the gui lazily near the camera (55 studs) and it renders even when the part is transparent.
- Lamps: tag `GwB_Lamp` with a Light child (attr LampOff). The server toggles `Light.Enabled` and Material (Neon/SmoothPlastic) on lamp kinds.
- Spin: tag `GwB_Spin`, attrs `Rpm` / `Axis`. Living adds `GwB_Blade` child parts while Rpm ≠ 0.
- Water: tag `GwB_Water` heads. Living adds a `GwB_Stream` child part while the fixture's `On`.
- Sounds: `Attachment Snd_<key>` (tag GwB_Sound) inside a part.

Interaction kinds (Furniture.KINDS) and server state (server Interact service; prompts `FxPrompt1/2` live in the item's **PrimaryPart (Base)**, RequiresLineOfSight=false, E / F keys):
- bed (눕기 / 잠자기 hold 1.2): poses on LieSpot.
- seat (앉기): sits on the nearest free Seat.
- tv: `On`, `Channel` 1..6.
- fridge: `Open`=true for 6 s, then false. A menu in homes.
- microwave: `On` while heating 12 s, Turntable Rpm 30, then `Ding` = server time.
- shower / sink / dryer / washer / exercise / office etc.: timedUse sets `On` true for N s (shower 10, sink 3, dryer 3, washer 30 + drum Rpm 160, treadmill 30), `Busy` (server time until), `Done` at the end.
- bathtub: `Fill` 1 then 0 after 30 s, sits on the Seat, On 12 s. The jacuzzi starts with Fill=1.
- toilet: sit, then `Flush` = time after 4 s (urinal has no seat).
- lamp / aircon: toggle `On` + lights.
- fan: toggle `On` + Hub Rpm 600.
- wardrobe: toggle `Open`. closet_wall is kind wardrobe as well.
- pc: sits + `On`.
- wallpad: opens the wallpad UI.
- massage: sit + On 15 s.
- cook: On 12 s (rice_cooker, kitchen_counter).
- water: `Pour` = time (온수: 컵라면).
- vending: `Vend` = time (1,200원 drink).
- switch: `On` + `Click`, room lights.
- game / cinema / bar / instrument (social timed On), popcorn, lift, boxing, workbench, dress.

Nobody animates the fixture `Open` / `Fill` / `Flush` / `Ding` / `Vend` / `Pour` attributes on the client today. The reskin can animate them: fridge / wardrobe / microwave doors, bath water, vending drop, steam. Only door Models (GwB_Door) are animated, by DoorAnim / GwangalliDoorsClient.

Full per-item table: footprint w×d×h (studs, 1 stud ≈ 0.3 m), mountY, kind, number of colourways, gameplay parts (exact item-local coordinates, front -Z).

| id | name | w×d×h | kind (tag) | cw | gameplay / special parts |
|---|---|---|---|---|---|
| sofa3 | 패브릭 3인 소파 | 8×3.4×3.2 | seat | 4 | Seats #1-3 at x -2.2/0/2.2, z -0.3, **top 2.10**. Hit 8×2×3.4. Back cushion at z 0.9..1.7 |
| armchair | 라운지 암체어 | 3.4×3.4×3.4 | seat | 3 | Seat (0, top 2.15, z -0.25). Hit 3.4×2×3.0. Metal swivel base |
| coffee_table | 원목 커피 테이블 | 5×2.6×1.5 | — (no tag) | 3 | top y 1.5 (slab 1.2-1.5), shelf 0.35-0.5. Hit full |
| tv55 | 55인치 TV + 거실장 | 7×1.6×5.6 | tv | 3 | cabinet y 0-1.5; **Screen** x ±3.15, y 2.35-5.45, z 0..0.06 (front face z=0); PowerLed (2.95,2.31); bezel y 2.2-5.6 z 0.05-0.35; snd tv_talk on Base |
| tv_small | 32인치 TV | 3.4×1.2×4.2 | tv | 2 | cabinet 0-2.2; Screen x ±1.5, y 2.5-4.1, z -0.02..0.02 |
| floor_lamp | 아크 플로어 스탠드 | 1.6×1.6×6.2 | lamp | 2 | Shade Lamp (cyl at y 5.1-6.1, PointLight off, range 14). Hit 0.8×6×0.8 |
| monstera | 몬스테라 화분 | 2×2×4.6 | — | 3 (pot) | pot cyl dia 1.8 h 1.6, 7 Leaf parts. Hit 1.6 cube |
| bookshelf | 5단 책장 | 4×1.3×6.4 | — | 3 | 60 parts (shelves every 1.25, books). Hit full |
| aircon | 스탠드 에어컨 | 1.9×1.5×6 | aircon | 1 | Vent (y 3.6-5.5 front, snd aircon_hum), Display neon (y 2.9-3.2) |
| fan | 스탠드 선풍기 | 1.8×1.8×4.4 | fan | 2 | **Hub** Spin (0,3.4,-0.35) Axis X; Guard glass disc dia 2.2 |
| bed_single | 슈퍼싱글 침대 | 4.2×7×4.2 | bed | 3 | LieSpot (0,2.85,0.4); mattress top 2.1, duvet top 2.3, headboard z 3.1..3.5 to y 4.2; 1 pillow. Hit 4.2×2.1×7 |
| bed_queen | 퀸 침대 | 5.6×7.2×4.2 | bed | 4 | same, 2 pillows |
| bed_king | 킹 호텔식 침대 | 6.6×7.4×4.4 | bed | 3 | same, 2 pillows |
| wardrobe | 2도어 옷장 | 4.4×2×7 | wardrobe | 3 | WardrobeDoor1/2 (Hinge -1 / +1) at z -1..-0.92; rail y 5.6; 8 clothes. Open toggles |
| desk | 책상 + 의자 | 4.4×4×3.6 | seat | 3 | desk top y 2.8 over z -0.2..2; laptop; DeskLamp Spot (off); chair Seat (0, top 2.05, z -1.0) yaw 180 (faces +Z, the desk) |
| pc_desk | 게이밍 PC 세트 | 5×4.2×4.4 | pc | 2 | top 2.8; **Screen** pc x ±1.6, y 3.3-5.1, z 1.54-1.56; RGB / RGB2 (attr Rgb); tower glass; chair Seat (0, top 2.05, z -1.1) yaw 180; snd pc_hum |
| fridge | 양문형 냉장고 | 3.2×2.6×6.4 | fridge | 3 | FridgeDoorL/R (Hinge ∓1) z -1.3..-1.1; Inside Lamp (PointLight off) + snd fridge_hum; 4 glass shelves + food |
| kimchi_fridge | 스탠드 김치냉장고 | 2.4×2.4×5.8 | fridge | 2 | 3 drawer fronts; Inside (tr 1) Lamp |
| microwave | 전자레인지 | 1.8×1.3×1.1 | microwave | 2 | MwDoor (Hinge -1), Inside Lamp, **Turntable** Spin Y, Clock neon; usually at y 3.05 on a counter (item `y` offset), cvs at y 3.6 |
| dining4 | 4인 원목 식탁 | 6×6.2×3 | seat | 3 | table top 2.6-2.85 over x ±2.6, z ±1.6; 4 Seats at (±1.3, ±2.5) **top 2.0** (yaw 0 at z<0, 180 at z>0) |
| rice_cooker | 전기밥솥 | 1.2×1.3×1.2 | cook | 2 | Panel neon; on counters at y 3.05 |
| washer | 드럼 세탁기 | 2.4×2.4×3.4 | washer | 2 | **Drum** Spin X (0,1.5,-1.29) dia 1.3; panel y 2.8-3.2 |
| massage_chair | 안마의자 | 3×5×4.6 | massage | 2 | Seat (0, top 2.25, z 0.2); Back ramp to (0,4.6,2.5); Leg ramp to z -2.5 |
| treadmill | 러닝머신 | 2.8×6×4.6 | exercise | 1 | deck 0-0.6 (collides); Belt; **Screen** treadmill (0,4.3,-2.51) 1.4×0.4; console at z -3 (front = -Z) |
| rug | 라운드 러그 | 7×7×0.1 | — | 3 | 2 discs, y ≤ 0.09 |
| frame_art | 광안대교 야경 액자 | 3.6×0.3×2.6, mountY 3.6 | — | 2 | Art with SurfaceGui text "광안대교" |
| mood_light | 무드등 | 0.9×0.9×1.4 | lamp | 3 | Globe ball Lamp (PointLight colour = colourway) |
| aquarium | 열대어 어항 | 3.4×1.6×4.6 | — | 2 | cabinet 0-2.4; Tank glass y 2.4-4.4 + PointLight + snd bubbles; 5 Fish neon |
| vanity | 화장대 | 3.6×1.8×5.6 | seat | 2 | desk 0-2.6 over z 0..1.8; Mirror z 1.58-1.6 y 2.8-5.4; stool Seat (0, top 1.90, z -0.8) |
| shoe_rack | 신발장 | 3.2×1.3×3.6 | — | 2 | box + door line |
| dining2 | 2인 카페 테이블 | 3×5.4×3 | seat | 3 | round top dia 2.6 at y 2.625-2.775; 2 Seats (0, top 2.0, z ±1.9) |
| minibar | 미니 냉장고 | 1.8×1.8×2.8 | fridge | 2 | solid body; Inside tr 1 + snd |
| kitchen_island | 아일랜드 식탁 | 8×3×3.1 | seat | 2 | body solid 8×2.9×2.5 (z -1..1.5); marble top 2.9-3.1; **3 stools OUTSIDE the footprint** Seats (x -2.4/0/2.4, top 2.30, z -2.2); Pendant lamp at y 7.4-8 (on) |
| drying_rack | 빨래 건조대 | 5×2.2×3.6 | — | 2 | rods + 5 clothes |
| jacuzzi | 월풀 자쿠지 | 7×7×2.6 | bathtub | 2 | round shell dia 7 (collides); Water (tr 0.35, Fill=1, PointLight, snd bubbles); Head water (0,2.65,3.15); 3 Seats top 1.75 at (0,1.2), (±1.6,-0.8) |
| sunbed | 선베드 | 2.6×7×2.6 | bed | 2 | LieSpot (0,2.0,0.2) tilted 70°; back ramp toward +Z |
| kitchen_counter | 싱크대 (인덕션 · 후드) | **W**×2.2×9 (fixed) | cook | 2 | body 0-2.8 solid; Top marble 2.8-3.0 (top 3.0); Sink at x -W/2+1..+3; **Spout** water; Cooktop (W/2-3.4..W/2-0.6, y 3.0-3.05) + 2 Burners; Hood (W/2-3.4..-0.6, y 6.6-7.4, snd vent_fan); upper cabinets y 6.2-8.6 over x -W/2..W/2-3.6, z 0..1.1; backsplash tiles z 1.05-1.1 y 3-6.2; UnderLight Lamp Surface (off) |
| toilet | 양변기 | 1.8×3×3.2 (fixed) | toilet | 1 | Seat (0, top 1.60, z -0.1); Tank z 0.8-1.5 y 1.4-3.2; flush button on tank top. Hit 1.2×1.5×2.4 |
| washbasin | 세면대 | 2.4×1.6×6 (fixed) | sink | 1 | Basin y 2.4-2.9 (top 2.9); pedestal; **Spout** water (0,3.42,0.28); Mirror y 3.8-6.0 at z 0.72-0.8 |
| shower | 샤워부스 | 3.6×3.6×7.6 (fixed) | shower | 1 | tray 0-0.2; GlassFront z -1.8..-1.7 (tr 0.7); riser; **Head** water (0,6.9,1.0) + snd shower |
| bathtub | 욕조 | 6×3×2.2 (fixed) | bathtub | 1 | 4 walls collide; Water (tr 1, Fill 0); **Head** water (2.3,2.55,1.2); Seat (0, top 1.05, z 0.2) yaw 90 |
| urinal | 소변기 | 1.6×1.4×4.2 (fixed) | toilet | 1 | bowl y 1.4-4.0; no seat |
| hand_dryer | 핸드 드라이어 | 1.2×0.8×1.4, mountY 3.6 | dryer | 1 | Body (snd hand_dryer) |
| wallpad | 월패드 | 1.4×0.2×1.0, mountY 4.4 | wallpad | 1 | **Screen** wallpad (Neon blue) |
| water_dispenser | 온수기 / 정수기 | 1.4×1.4×4 (fixed) | water | 1 | body 0-3.2; glass top 3.2-4; Hot (red) / cold taps at y 1.9-2.1, z -0.75 |
| vending | 음료 자판기 | 3.6×2.6×6.4 (fixed) | vending | 2 | body solid; Window (tr 0.25 + SurfaceLight) x -1.6..0.8, y 2.4-6; 24 cans; Coin neon; slot y 0.6-1.4; snd fridge_hum |
| gaming_setup | 게이밍 PC 책상 | 5×2.6×5.2 | pc | 2 | desk top 2.6 (solid); 2 Screens pc (-0.6,3.65,0.55) 2.0×1.3 and (1.4,3.55,0.55) 1.6×1.1; Keyboard; RGB strip; Tower; chair Seat (0, top 2.10, z -1.8) yaw 180 |
| console_set | 콘솔 게임 세트 | 7×1.6×5.8 | game | 2 | cabinet 0-1.4; Screen game x ±3.15, y 2.15-5.65, z 0.05-0.1; Console; 2 Pads |
| projector_screen | 홈시네마 스크린 + 프로젝터 | 9×1×7.2 | cinema | 1 | Screen cinema 8.6×5.2 at y 1.6-6.8, z 0.2-0.3; casing y 6.8-7.2; 2 tall Speakers (x ±4); low stand |
| recliner_row | 전동 리클라이너 3인 | 8.4×3.4×3.4 | seat | 2 | 3 Seats (x -2.8/0/2.8, **top 2.0**, z -0.3) |
| popcorn_machine | 팝콘 기계 | 2×2×4.4 | popcorn | 1 | base solid 0-2; glass Bowl 2-3.9; Corn |
| bench_press | 벤치프레스 세트 | 3×6×4.4 | lift | 1 | bench solid y 1.2-1.6; uprights at z 1.6-1.8; bar at y 3.6, z 1.7; 2 Plates; Seat (0, top 1.95, z -0.6) |
| punching_bag | 스탠드 샌드백 | 2.6×2.6×6.6 | boxing | 2 | base disc solid; Bag cylinder y 0..4.4 (solid, h 4.4 around y 2.2) |
| dumbbell_rack | 덤벨 랙 | 4×1.6×3 | lift | 1 | 2 tiers y 1.1 / 2.3, 5 dumbbells each |
| workbench | 정비 작업대 | 7×2.6×3.4 | workbench | 2 | top solid y 2.8-3.1; 4 drawer fronts; Vise |
| tool_wall | 공구 타공판 | 6×0.4×6, mountY 2.5 | — | 1 | board y 2.5..6.0; 8 tools |
| parts_shelf | 부품 선반 | 5×1.6×6 | — | 1 | 4 shelves; 9 boxes |
| closet_wall | 시스템 드레스룸 행거 | 9×2.2×7.4 | wardrobe | 2 | back + 4 posts; rail y 5.8; 14 clothes; drawers 0.2-1.6 |
| closet_island | 드레스룸 아일랜드장 | 4.6×2.6×3.2 | — | 2 | body solid; glass top 3.0-3.2; 6 watches |
| full_mirror | LED 전신거울 | 2.6×0.6×6.6 | dress | 1 | Mirror; LED Lamp (on) |
| bar_counter | 홈바 카운터 | 7×2.4×3.8 | bar | 2 | body solid; marble top 3.5-3.8; neon strip Lamp (on) at y 0.2-0.3; 4 glasses on top |
| bar_stool | 바 스툴 | 1.8×1.8×3.2 | seat | 2 | Seat (0, **top 3.15**) |
| liquor_shelf | 술장 (백바) | 7×1.4×7.6 | — | 1 | 4 glass shelves × 10 bottles; glow Lamp (on) |
| piano | 업라이트 피아노 | 5×2.2×4.4 | instrument | 2 | body solid; Keys at y 2.5-2.6, z -1.05..-0.4; 16 black keys; bench + Seat (0, top 1.90, z -1.85) |
| drum_kit | 드럼 세트 | 5×4.4×4.6 | instrument | 2 | Kick, 4 toms, 2 Cymbals; throne Seat (0, top 2.10, z -1.6) |
| guitar_stand | 기타 + 스탠드 | 1.6×1.6×4 | instrument | 2 | 2 body cylinders + neck |
| office_desk | 듀얼 모니터 업무 책상 | 6×2.8×5 | office | 2 | top 2.6 solid; 2 Screens office at (±1.2, 3.65, 0.65) 2×1.3; Keyboard; chair Seat (0, top 2.10, z -1.95) yaw 180 |

(The exact per-part lists are in catalog_dump.txt.)

---------------------------------------------------------------------------------------------------

## 3. 광안 종합병원 (Builder/Hospital + Hospital service): what exists, where

Site (`Shared.Hospital.SITE`): x -704, z 1236, yaw 90, groundY 12.5. `rec.cf = CF(-704, FFL, 1236) * Angles(0, rad 90, 0)`, with FFL = raycast ground + 0.3 (≈ 12.8 without the map).
- Building-local frame: **x** = across the street facade (-40..40), with +x mapping to **world -Z**. **z** = from the facade (0) into the lot (60), with +z mapping to **world +X** (world X = -704 + z, world Z = 1236 - x). **y** = above the 1F FFL.
- Building model: `Workspace.GwangalliBuildings.hospital` (BuildingId "hospital", Kind "hospital", DisplayName "광안 종합병원"). Workspace attr `GwB_Hospital = "hospital"`.
- **Client-side frame**: `rec.cf = BoundsCF * CFrame.new(0, -BoundsSize.Y/2 + 1, -(BoundsSize.Z - 2)/2)`. This is exact for the hospital: bottom = 1F - 1 slab, D = 60, W = 80. Cross-check: the ShopFloor of dept model `hospital_reception` is `rec.cf*(8, 0.045, 14.2)`.
- Storeys: **1F y 0 (h 13, ceiling 12)**, **2F y 13**, **3F y 24**, **4F y 35** (h 11, ceiling 10), RF y 46 (helipad, in Shell).
- Cores: stair x -9.4..1.4, lifts x 1.7..21.5 (2 elevators at x 6.6 and 16.6, z 36), z 35.6..54.7.
- Restrooms on every storey: `Restroom_m` frame at (22.2, 0, 36.2) and `Restroom_f` at (31.2, 0, 36.2), each 8.6 × 23.4 (door wall z 36; doors at x 26.5 / 35.5).
- Hall z 28..35.6.
- Main entrance auto door (x 12, z 0, w 7). ER walk-in (x -25, w 6). Ambulance door (-x side, z 46, w 8).

Fixture Models the hospital builds itself (tag GwB_Fixture, attrs Kind, Label, Public=true, **no ItemId**). They are children of `Floor_<label>`:
- **HospitalBed** (Kind bed). Frame `cf`, head toward local **+Z**. Recover with `BedFrame.CFrame * CF(0,-1.15,0)`.
  - Parts: BedFrame 3.2×0.3×6.6 @y1.15; 4 BedLeg 0.2×1.1×0.2 @(±1.4, ±2.9); 4 Caster balls d0.5 @y0.25; **Mattress 3.2×0.9×6.6 @y1.75 = PrimaryPart (the prompt lives here)**, top 2.2; Blanket 3.26×0.12×4.6 @(0,2.24,-0.9); Pillow 2.2×0.45×1.2 @(0,2.36,2.5); HeadBoard 3.4×2.8×0.25 @(0,2.6,3.35); FootBoard 3.4×2.0×0.25 @(0,2.2,-3.35); 2 SideRail @(±1.75,2.6,0.9); **LieSpot** (0,2.95,0.4).
  - Label tells the variant: `응급 베드 1-4` (ER, red blanket 230,120,120), `소생실 침대`, `처치실 침대`, `물리치료 베드 1/2`, `진찰 침대`, `소아 진찰 침대`, `301호 1..6`, `302호 1..4`, `303호 1/2`, `304호 1`, `305호 1/2`, `306호 1`, `401호 VIP 1`, `402호 1`, `ICU 1..4`, `403호 1/2`, `404호 1`.
  - Hospital.admit finds beds by Name "HospitalBed" + LieSpot. Never move it.
- **WaitingChairs** (Kind seat). Row frame recovered with `Beam.CFrame * CF(0,-0.95,-0.2)`; n = number of Seat children; len = n×2.2.
  - Parts: Beam (len×0.25×0.5 @(0,0.95,0.2)); 2 ChairLeg (0.25×0.96×1.6 @(±(len/2-0.4),0.48,0.2)); per seat i, **Seat** 1.9×0.3×1.9 @(px,1.8,0) **top 1.95**, Index i, VISIBLE SmoothPlastic coloured; ChairBack 1.9×2.0×0.2 @(px,2.95,0.95) tilted -8°. px = -len/2+1.1+(i-1)×2.2. PrimaryPart = first Seat. Sitters face local -Z.
  - Labels: `대기 의자` (lobby rows of 4, blue 70,130,200), `응급실 대기 의자` (red), `약국 대기 의자` (green), `스테이션 의자` (n=1, teal), `보호자 의자` (n=1 or 3), `수액 의자 1/2` (주사실, n=1), `ICU 의자` (n=2).
- **Wheelchair** (Kind seat). Frame = `Seat.CFrame * CF(0,-1.9,0)`, faces -Z. Parts: Seat (visible Fabric 1.8×0.25×1.8 @y1.9, top 2.025), WheelchairBack @(0,3.1,0.9), 2 Wheel cyl d2.4 @(±1.05,1.3,0.2), FootRest @(0,0.5,-1.1).
- **Bench** (Shell, forecourt x 26 / 32, z -4, yaw 180). Seat WoodPlanks 5×0.3×1.6 @y1.7 + BenchBase concrete.
- Catalog items in the hospital (Public=true): tv55 (lobby, ER?, wards 301 / 304 / 401, day rooms, 2F waiting), sofa3 (304, 401, 3F day room ×2), coffee_table (401), fridge (401), dining2 (401), monstera (lobby ×2, 401), washbasin (처치실, 내과, OR scrub ×2, restrooms), treadmill (rehab), vending (1F ×2, 2F, 3F), water_dispenser (1F, 2F, 3F), toilet / urinal / hand_dryer (restrooms).

Loose named parts, direct children of `Floor_<label>`. The builders take frames whose **front = -Z** (text faces use Kit.text "front" = -Z):
- per bed (wardRoom): GasPanel 2.6×0.7×0.15 at `bed*(0,5.2,3.6)` + 3 GasOutlet (green / yellow / white); VitalMonitor 1.8×1.3×0.3 at `bed*(-1.6,6.4,3.55)` (monitor rooms: 304, 306?, 401, 402; ICU at its own spots; big 3.4×2.2 in resus / ICU wall / OR) with static SurfaceGui text "♥ 72 SpO₂ 98% ..."; BedsideCabinet 1.6×2.8×1.6 at `bed*(2.6,1.4,2.6)`; a `보호자 의자` WaitingChairs n=1 at `bed*(2.8,0,0)*yaw90`, unless noChair.
- ER bays (bz = 17, 23, 29, 35): GasPanel at (-39.45, 5.0, bz) yaw -90; VitalMonitor (-39.4, 6.6, bz-1.6); bay number Plate; IVPole at (-38.4, bz+2.2).
- IVPole (vcyl h 6.8 d0.15) + IVBag 0.5×0.8×0.2 @y6.3 + IVBase 1.4×0.15×1.4.
- Curtain (box x0..x1 or z0..z1, y 0.8..ceil-0.6, 0.1 thick, Fabric 150,200,222, tr 0.15) + CurtainTrack (ceil-0.6..-0.45). ER rows z 14/20/26/32/38 (x -39.6..-31.6) + x -31.6 (z 14..38); wards 301 z 9.5 / 16.5; 302 z 10.5; 303 x 2.1; 305 x 26; ICU x+3.5; 403 x 26; 2F 정형 z 9.5, 내과 x 6.4.
- Cabinet (w×h×1.4, handles at -Z), Cart (2.4×3.0×1.6 body @y1.9 + CartTop + 3 Drawer lines; text label on the front: "CRASH CART", "제세동기", "투약 카트", "수술 기구"), PCScreen 1.6×1.0×0.12 with an "EMR 환자 목록" text + PCStand + Keyboard (on desks at y 3.75).
- Signage:
  - HangSign (double-sided ceiling sign w×h×0.2 + 2 SignRod).
  - Plate (Core.plate wall signs: room names at y 8.2-8.5 on the corridor side, ☢ 방사선 관리구역, eye chart, 📏 height chart, 💀 spine poster, SCRUB 손 씻기 5분, bay numbers).
  - DirectoryKiosk (1F (24,4,24.5) 3×8×0.6 and every lift hall (-12.6,3,34.6) 2.2×6×0.6; tag **GwB_Hospital**, attr HospitalKind=directory: the server puts a "층별 안내 보기" ProximityPrompt in it; keep the part).
  - NumberDisplay 8×1.2×0.3 over 원무과; InfoSign; ExitSign; ORLight (Neon "수술 중 IN OPERATION" 4.6×0.8 at (-24, 9.1, 43.7)).
- Desks:
  - Department desks inside dept Models: FrontDesk (or Counter for 약국) box to y 3.5, DeskTop marble 3.5-3.75, DeskBell (gold cyl at y 3.85). These are **ShopLife desks (R4: overlay only, same top Y 3.75 / XZ)**.
  - StationCounter / StationTop (ER island, 2F station; top 3.8 / 3.75), ICUDesk / ICUDeskTop (top 3.8), InfoDesk / InfoDeskTop (round dia 4.4, top 3.75) + InfoSign + InfoPole, 처방약장 (wood 0.6×9×17 at x 38.9..39.5) + 32 MedBox.
- Equipment:
  - CT: CTGantry cyl d7.2 len2.6 at (-30,4.6,10) yaw 90, CTBore, CTBase, CTTableBase, CTTable z 6..19.
  - X-ray: XrayTable x -38.6..-34.6 z 3..12, XrayColumn, XrayTube.
  - Surgical lights: SurgicalLight (Neon disc d3.2-3.4 + SpotLight) + SurgicalArm, in resus (-18, ceil-1.7, 51) and OR (-22, 50 / 54).
  - OR table: ORTableBase / ORTable x -24.4..-19.6 z 48..56 (top 3.7). AnesthesiaMachine (-16.4..-14, 47..49.4, h 5).
  - ICU: Ventilator 1×4.2×1.4 next to each bed.
  - Rehab: ParallelBar (x -9.6 / -6.4, y 3.4-3.6, z 3..15) + 6 BarPost.
  - Scale (11..13.4, 20..22.4).
  - Peds: ToyBall, Balloon (ceil-2.6), PlayMat (x -39.4..-33.6, z 52..59.4), ToyBlock ×6.
  - Floor markings: SanitizerStand + Sanitizer (손 소독), ArrivalMark / ArrivalMarkIn ("🚑 구급차 도착 · 환자 인계"), GuideLine (red / green floor lines).
- Structure: ShopFloor of each dept (y 0..0.09; ShopLife reads the footprint; never hide), FloorFinish, Ceiling (c-0.1..c), LightPanel (Neon + SurfaceLight, tags GwB_Lamp / GwB_Light, group "common"; host-managed, never toggle), Wall (Plaster 232,230,224, 0.4 thick), GlassWall + GlassBase (resus, ICU front), Door_* models (auto / slide / double / swing; Doors service; skip), Hydrant, CCTV.

ShopLife departments: Models named by `HD.DEPTS[*].name` with attrs `ShopLifeType`, `ShopLifeMenu`, `ShopLifeKey` = `HospitalDept`, `Floor`, `MapIndex=false`, tag `GwB_HospitalDept`, children `Interior` (empty) + `ShopFloor`. Areas:

| key | floor | name | ShopFloor x0..x1, z0..z1 | desk |
|---|---|---|---|---|
| hospital_reception | 1F | 광안 종합병원 원무과 | -9.8..25.8, 0.4..28 (Marble) | FrontDesk x 0..22, z 21..23 (4 windows at x 2.75/8.25/13.75/19.25) |
| hospital_er | 1F | 응급의료센터 | -39.6..-10.2, 0.4..59.6 | triage FrontDesk -38..-30, z 9..11 |
| hospital_pharmacy | 1F | 약국 | 26..39.6, 0.4..19 | Counter x 34..35.6, z 2..17 |
| hospital_imaging | 2F | 영상의학과 | -39.6..-22.2, 0.4..27.8 | -38..-32, z 22..23.6 |
| hospital_rehab | 2F | 정형외과 · 재활의학과 | -21.8..-4.2 | -20..-14 |
| hospital_internal | 2F | 내과 | -3.8..13.8 | -2..4 |
| hospital_peds | 2F | 소아청소년과 | 14.2..31.8 | 16..22 |
| hospital_inject | 2F | 주사실 · 처치실 | 32.2..39.6 | 33..38 |
| hospital_ward3 | 3F | 3층 병동 간호사 스테이션 | -39.6..-9.8, 35.6..59.6 | -36..-16, z 38..39.6 |
| hospital_ward4 | 4F | 4층 병동 간호사 스테이션 | -39.6..-9.8, 35.6..43.8 | same |

ShopLife adds invisible anchors with LifePrompts in `Workspace.GwangalliBuildingsShopLife/<ShopLifeKey>/Anchors`. Keep 2 studs of anchor clearance for new geometry taller than 0.1, and do not add cosmetic prompts within 6.5 studs.

Room table for room dressing (building-local, per storey; doors on the z=28 corridor wall face the hall):
- **1F**:
  - lobby (-9.8..39.6, 0.4..28): 원무과 counter + cabinet wall behind (z 26.6), 안내 desk (2,5), waiting rows x 4 / 19 × z 10 / 13 / 16 (face -z), tv55 (-9,8) yaw -90, wheelchairs (21,3) (23,3), sanitizer (7,2.2), plants (-8.4,26.4) (39,1.6), 1F directory (24,24.5).
  - 약국 (26..39.6, 0.4..19): chairs (28.4,9) yaw -90 ×4.
  - vending corner (25.8..39.6, 19..28): 2 vending at x 38.3 z 21.4 / 25.4 yaw 90, water (27.4,27).
  - ER (-39.6..-10.2, 0.4..44): triage + waiting chairs x -18 / -14 z 7 yaw 90; 4 bays at x -36 head to the -x wall; nurse island x -30..-20, z 21..29; arrival zone (-38.6..-30, 41..51).
  - 소생실 (glass) (-26..-10.2, 44..59.6, door x -18.5): bed (-18,52), big monitor, gas, surgical light, crash cart + defib at x -12.4.
  - 처치실 (-39.6..-26.2, 52..59.6, door x -29.2): bed (-36,56) yaw -90, washbasin (-27.6,59.2).
  - hall (-9.8..39.6, 28..35.6).
- **2F**:
  - Front rooms z 0.4..27.8, partitions x -22 / -4 / 14 / 32. Doors: 영상의학과 x -31, 정형 -13, 내과 5, 소아 23, 주사실 36.
  - imaging: CT + X-ray + desk; ☢ plate.
  - rehab: 2 physio beds x -18.2, z 6 / 13, parallel bars, treadmill (-8,21) yaw 180, spine poster.
  - 내과: exam bed (9.5,4.4), curtain x 6.4, eye chart, scale, washbasin (13.2,14) yaw 90.
  - 소아: exam bed (27,4.4), height chart, toys, balloons, 3 guardian chairs (20,14).
  - 주사실: 2 수액 의자 (36,5) / (36,11) yaw 180 + IV poles x 38.4 + cabinet (36,16.6).
  - Back zone (-39.6..-9.8, 35.6..59.6): 외래 간호사 스테이션 counter -36..-16, z 38..39.6 + cabinets z 44.4; waiting rows (-30 / -19.6, z 50 / 53, face +z); tv55 (-25,46.2) yaw 180; kids corner (PlayMat); water (-11,58.6); vending (-14.6,58.2).
- **3F** (병동):
  - Partitions x -22 / -4 / 8 / 20 / 32.
  - 301 6인실 (-40..-22): beds (-36, z 6/13/20) yaw -90 + (-25.8, z 6/13/20) yaw 90; curtains z 9.5 / 16.5; tv55 (-31,1.6) yaw 180; guardian chair (-31,6).
  - 302 4인실 (-22..-4): beds (-18.2, z 6/15) + (-7.8, z 6/15).
  - 303 2인실 (-4..8): beds (-0.4,4.2) / (4.6,4.2) yaw 180.
  - 304 1인실 (8..20): bed (14,4.2) + monitor + sofa3 (18.6,16) yaw 90 + tv55 (9.2,14) yaw -90.
  - 305 2인실 (20..32).
  - 306 1인실 (32..40).
  - Back: station + 투약 카트 (-14,42) + 휴게실 DAY ROOM (sofas (-34,57.4) / (-24,57.4), tv55 (-29,46) yaw 180, water, vending).
- **4F**:
  - Partitions x -22 / -10 / 20 / 32; ICU front wall x -10.2..19.8 is glass.
  - 401 VIP 특실 (-40..-22): bed (-33,4.2), wood floor, sofa3 (-24,14) yaw 90, coffee_table (-28.6,14), tv55 (-38.8,14) yaw -90, fridge (-38.6,23) yaw -90, dining2 (-30,22), monstera (-23.4,2).
  - 402 1인실 (-22..-10).
  - 중환자실 ICU (-10..20, door x 5 auto w 6): 4 beds at x -6 / 1 / 8 / 15 z 4.2 + vitals + gas + IV + Ventilator + curtains; ICU desk x -2..8, z 18..19.6 with 3 PCs; big monitor (3, 7.4, 27.4); 2 chairs (3, 21.4).
  - 403 2인실, 404 1인실.
  - Back: 4F station (z 35.6..43.8) + OR wall z 44 (double door x -24, ORLight).
  - 수술실 OR (-39.6..-9.8, 44.2..59.6): OR table, 2 surgical lights, anesthesia machine, 2 carts, 2 scrub washbasins (-38.8, z 52 / 56) yaw -90, SCRUB plate.
- Windows (upper storeys): facade z=0 windows every 6 studs from x -39.2 (y 2.8..8.6); -x / +x walls z 2..26; back z=60 x -39.2..-10.

Test shots (bld.js teleport, world): lobby `(-698, FFL+3, 1226)`, ER `(-679, FFL+3, 1261)`, 301 `(-691, FFL+27, 1267)`, ICU `(-694, FFL+38, 1231)`, OR `(-652, FFL+38, 1260)`.

---------------------------------------------------------------------------------------------------

## 4. Rules (map survey R1-R15, applied to the reskin)

- **R1 / R4**: never destroy, move, rename, reparent or resize server instances. Hide only locally. Gameplay parts are overlaid at the exact pose:
  - Seats: seat top ±0.1, same facing.
  - Tops of tables / desks / counters / ShopLife desks: same top Y and XZ extent.
  - Leave alone: LieSpot, Hit boxes, Base / PrimaryPart, Mattress (bed PrimaryPart, prompt), ShopFloor, FrontDesk / DeskTop / DeskBell / Counter, DirectoryKiosk, door Models, elevator, stairs.
- **R2**: everything under `ctx.root` (= `Workspace.GwInteriorDetailLocal`, which carries attr LOD="near" so GwangalliTextures leaves it alone). Use a sub-Model per item.
- **R3**: hide with `ctx.Scan.hide(store, part)`. It handles GwArrive / LOD roots and disables SurfaceGuis / Decals. Call `Scan.reapply(store)` every tick (streaming / LOD can reset) and `Scan.restore(store)` on drop.
- **R5**: new parts are Anchored, CanCollide=false, CanQuery=false, CanTouch=false, Massless, and CastShadow only on big pieces. `K:make` already does this (only a look with `collide = true` collides locally; don't use it). Thin overlays go 0.02-0.05 off the real surface.
- **R6 / R7**: keep door swings / auto-door pockets and ShopLife anchors clear. Add nothing on top of ShopLife desks except flush details. Never block the bed / chair approach (≥2.5-stud aisle).
- **R8**: host prompts never need line of sight, so our parts cannot block them. Cosmetic prompts must use `Interact.prompt`, which is client-local "GwInteriorPrompt", R key, ≤5 studs, never within 6.5 studs of a host prompt. Every kind≠nil item has its host prompt at its Base centre, so **no cosmetic prompts on catalog fixtures with a kind**. Only kind=nil items or room dressing may get them (e.g. 블라인드 올리기, 커튼 치기, 수도꼭지?) and never duplicating a server action.
- **R9**: lights carry attr `GwIndoorDim=0` (`K:light` does it), Shadows=false, and stay within our own budget. Never toggle GwB_Light / InteriorLight lights.
- **R10**: never write Window / RoomGlass / NightWindow / Sign_* props. Blinds and curtains stay ≥0.3 studs inside the glass.
- **R11 / R12**: tag signals, not workspace-wide DescendantAdded. GwB containers are scoped and DescendantAdded on them is OK. Rebuild on remove / add (parking re-parents to ServerStorage, so the client sees instances vanish and come back as NEW instances).
- **R13**: build within the focus radius, time-sliced ≤2.5 ms per frame (Kit:tick already yields), tier budgets.
- **R15**: never weld to characters.

---------------------------------------------------------------------------------------------------

## 5. Discovery strategy (core)

1. `local GB = Workspace:WaitForChild("GwangalliBuildings", 60)`. It may be absent; keep retrying slowly.
2. **Buildings**: `CollectionService` tag `GwB_Building` (initial GetTagged + InstanceAdded / Removed). For each building model, connect `DescendantAdded` / `DescendantRemoving` and do one time-sliced sweep of `GetDescendants()`. Classify each instance:
   - `Model` with attribute `ItemId` → catalog item, key = ItemId. Skip `Ghost` and models outside GB. DecorMode ghosts are in Workspace root, so scoping excludes them.
   - Inside the hospital building (`building.Name == Workspace:GetAttribute("GwB_Hospital")` or BuildingId "hospital"): a `Model` named `HospitalBed` / `WaitingChairs` / `Wheelchair` / `Bench` → key `H:<Name>`. A `BasePart` whose Name is an anchor in the HOSPITAL_GROUPS table → key `H:<Name>`, plus sibling parts grouped by name within a radius:

     | anchor | siblings | radius |
     |---|---|---|
     | CTGantry | CTBore / CTBase / CTTableBase / CTTable | 12 |
     | XrayTable | XrayColumn / XrayTube | 6 |
     | SurgicalLight | SurgicalArm | 2 |
     | ORTable | ORTableBase | — |
     | IVPole | IVBag / IVBase | 1.5 |
     | GasPanel | GasOutlet | 1.6 |
     | Cabinet | Handle | w/2+0.5 |
     | Cart | CartTop / Drawer | 2 |
     | Curtain | CurtainTrack | same span |
     | PCScreen | PCStand / Keyboard | 1.2 |
     | InfoDesk | InfoDeskTop / InfoSign / InfoPole | 3 |
     | SanitizerStand | Sanitizer | 2.5 |
     | ParallelBar | BarPost | 7 |
     | StationCounter | StationTop | — |
     | ICUDesk | ICUDeskTop | — |
     | HangSign | SignRod | — |
     | 처방약장 | MedBox | 9 |
     | PlayMat | ToyBlock / ToyBall | 6 |
     | ArrivalMark | ArrivalMarkIn | — |

     Single anchors: VitalMonitor, BedsideCabinet, Ventilator, Scale, AnesthesiaMachine, NumberDisplay, DirectoryKiosk, ORLight, Balloon, GuideLine, Plate, ExitSign. Dept desks are recognised as a dept Model (attr HospitalDept) → `H:Dept` with its FrontDesk / Counter / DeskTop / DeskBell.
   - `Model` named `Restroom_m|f|u` (Core.restroom, any building) → room `R:restroom`. Frame = FloorTile part (w×0.05×d): `FloorTile.CFrame * CF(-w/2, -0.025, -d/2)` = entrance corner; the door is on v=0.
   - `BasePart` tagged `GwB_Room` (or tag signal) → room `R:<Kind>`, with its `GwB_Unit` ancestor.
   - Hospital rooms: a static ROOMS table (§3) instantiated when the hospital `Interior` appears, using rec.cf from BoundsCF.
   - Optional: `Workspace.GwangalliInfill` fixtures (tag GwB_Fixture, Model names Bench / Vending / DrinkingFountain / Jeongja / Slide / Swings / Seesaw / SpringRider / OutdoorGym / Hoop / PicnicTable / JanggiTable / GardenPlot) → `O:<Name>`.
   - Annex storefront rooms (`GB.Annex` folder) hold catalog items too: same classification, plus the overlap rule.
3. **Settling (streaming)**: a discovered item is *pending* until its anchor part exists (Base for catalog; BedFrame / Mattress; Beam; ...) and its BasePart count has not changed for ~0.6 s. Use `catalog_summary.json nparts` for catalog items as the expected count; build when count ≥ expected or stable for 2 s. While active, `DescendantAdded` on the item model hides late visible parts. If the anchor part leaves (stream-out / park), destroy the overlay + restore.
4. **Main-system overlap** (the main system builds AnnexRoom rooms and may hide / overlay Seat / Base parts in cafe / pub / karaoke):
   1. If any visible-by-design part of the item (catalog dump tr < 1) already has Transparency ≥ 0.99 or LocalTransparencyModifier ≥ 0.99 when we come to build it, someone else hid it, so skip it (re-check every 10 s).
   2. If the item is a descendant of a Model with attr `AnnexRoom` (or any model the main `isShop()` accepts), wait until the main system has a folder for it in ctx.root (child with attr ShopKey) or 4 s pass, then apply (1).
   3. Optional precise registry (needs a 3-line change to Scan.luau by its owner, see §10).
5. **Activation and culling** (each 0.35 s tick):
   - pos = `ctx.focus()`, feet = pos.Y - 3.
   - Per item: world floor frame F; horizontal distance from pos to the footprint AABB.
   - Same-storey gate: `-2.5 < F.Y - feet < 8`. Rooftop / forecourt Shell items use the same rule, so they work when you stand there.
   - Build radius high 46 / mid 34 / low 24; drop at radius + 14.
   - Nearest first; at most 1 item build per tick-slice, time-sliced.
   - Active-item cap 70 / 45 / 24; total part budget 9000 / 5500 / 2600; reskin lights 8 / 5 / 2.
   - Tier from `ctx.limits()`: maxParts 2600 → high, 2100 → mid, 1300 → low. Also respect script attr `Enabled=false`.
   - Rooms (dressing): activate when pos is inside the room box + 6 studs on the same storey; at most 3 dressed rooms (high) / 2 / 1.
6. **Pause in DecorMode**: while the local player's own unit is in decor mode (top-down camera; DecorMode hides parts above its ceiling locally), skip building items in that unit. Detection: `workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable` while the player stands in a GwB_Unit they own (OwnerUserId == LocalPlayer.UserId), or any `SelectionBox` named GhostBox in Workspace. Placed items are rebuilt by the server on every move (new instance), so add / remove handles moves.

---------------------------------------------------------------------------------------------------

## 6. Builder contract (core ↔ chunk modules)

Modules: `GwangalliBuildingInterior/RS_<chunk>.luau` (ModuleScripts under the LocalScript, next to Kit / Props / Look / Interact). The core (`Reskin.luau`) loads them with a static list. Use `script.Parent:FindFirstChild(name)` + pcall(require) in game, so a missing chunk never stalls. Requires inside RS modules must use the literal form `require(script.Parent:WaitForChild("Kit"))`, so tools/gen.py-style bundling works offline. A shared helper module `RS_Common.luau` (written by the core agent first) holds the palette and helpers.

```lua
-- RS_<chunk>.luau
local Look = require(script.Parent:WaitForChild("Look"))
local Props = require(script.Parent:WaitForChild("Props"))
local Interact = require(script.Parent:WaitForChild("Interact"))
local C = require(script.Parent:WaitForChild("RS_Common"))
local M = { items = {}, rooms = {} }
M.items.sofa3 = {
	-- optional policy (defaults shown)
	hide = "all",              -- "all" = every visible BasePart of the source except keepers; "none"; or function(part) -> bool
	keep = { "Screen" },       -- part names never hidden (GwB_Screen / prompt holders / LieSpot / Hit / Base are always kept)
	hideSeats = false,         -- Seat-class parts are kept by default (catalog seats are invisible anyway); set true ONLY when
	                           -- the builder overlays a cushion at the exact pose (hospital WaitingChairs / Wheelchair / Bench
	                           -- seats are VISIBLE coloured Seat parts: R4 allows hiding them when overlaid exactly)
	parts = { high = 220, mid = 140, low = 70 }, -- budget hint (core caps at V.maxParts)
	lights = 0,                -- lights this builder may add
	build = function(K, I)  -- K = Kit instance in the ITEM frame; I = item context
		...
	end,
}
M.rooms["R:bath"] = { build = function(K, V, R) ... end }
return M
```

**Item frame (K.cf = I.cf)**: the catalog convention. Origin = floor centre of the footprint (mountY not included, so a hand dryer's box sits at y 3.6..5.0), **front = -Z**. +X is item-right as seen from the back (the catalog's own +X), so catalog dump coordinates are used **as is**. For Props / T_clinic-style helpers whose pcf front is +Z, use `I.pcf = I.cf * CFrame.Angles(0, math.pi, 0)` expressed in K space: `CFrame.Angles(0, math.pi, 0)`. Mind that it flips X.

`I` (read-only data + helpers):
- Identity: `I.id`, `I.model` (server Model, or anchor part for loose groups), `I.def` (Furniture.ITEMS entry or nil), `I.w, I.d, I.h, I.mountY`, `I.W` (kitchen_counter width attr or w), `I.cw`, `I.colors` (Color3 list rotated so [1] = primary), `I.label` (Label attr), `I.attrs` (snapshot of model attrs), `I.kind`, `I.public`, `I.unitId`, `I.shopId`, `I.placed`, `I.staging`.
- Context: `I.ctx` = "hospital" | "unit" | "hotel" | "shop" | "lobby" | "annex" | "restroom" | "rooftop" | "outdoor"; `I.roomKind` (GwB_Room Kind under the item, if any); `I.dept` (hospital dept key whose ShopFloor contains it); `I.floor` (label), `I.tier` ("high" | "mid" | "low", = K.detail).
- Source parts: `I.part(name)` → first BasePart descendant; `I.parts(name)` → list; `I.lcf(part)` = part CFrame in the item frame; `I.seats` = { { part, lcf, top, index } } (top = local seat top Y); `I.group` = sibling parts for loose hospital groups.
- Hospital extras: `I.B` = { cf = rec.cf (world), fy = storey y, ceil, toB(worldCF) → building-local floor CFrame }, for designers working in Builder/Hospital coordinates.
- Hiding: `I:keep(part)`, `I:hide(part)` (beyond the policy, e.g. a sibling Curtain).
- Live state: `I:on(attr, fn(value))` watches a model attribute (On, Open, Channel, Fill, Busy, Done, Flush, Ding, Vend, Pour, Click), calls fn once now and on change, and is auto-disconnected. `I:onLight(fn(enabled))` (first Light descendant `.Enabled`, for GwB_Lamp items). `I:onRpm(fn(rpm))` (the GwB_Spin part's Rpm). `I:anim(fn(t, dt))` runs at ~15 Hz only while the item is active and near (≤30 studs). `I:now()` = server time (`workspace:GetServerTimeNow()`) to compare with Busy / Ding.

Kit (`K`) is the existing Kit.luau built on a pseudo-venue `V = { cf = I.cf, keep = {}, solid = {}, byName = {}, tables = {}, x0 = -w/2-0.5, x1, z0, z1, key = "rs:"..id, maxParts, maxLights, detail }`. All the Kit primitives work in the item frame: box / wedge / cyl / vcyl / ball / ell / seg / bar / ring / rbox / slab / panel / disc / plate / text / light / group. Props / Look / Interact work too: Interact.prompt needs `V.byName` / `V.tables` / `V.keep`, which are provided; the core fills `K.hostPts` with the item-frame positions of all host ProximityPrompt parents within 12 studs. `K:light` caps at V.maxLights and sets GwIndoorDim=0. `K:group(name, fn)` makes a sub-Model (doors you tween). Parts are counted against V.maxParts (ghosted beyond the cap), so honour `K.detail`.

Rules for item builders:
1. Build first; the core hides the originals after a successful build and restores on error.
2. Stay inside the item's footprint + 0.3 (exceptions: kitchen_island stools at z -2.2; chairs around tables as built). Wall items may reach +Z to the wall plane.
3. Keep the server Screen part visible and build the bezel / body **around** its rectangle. Never put geometry in front of the Screen's -Z face plane inside its rectangle (the Living SurfaceGui is drawn there).
4. Seat cushions: top at `I.seats[i].top ± 0.1`. Tables / desks: same top Y and XZ.
5. Lamps: put the glowing shade / bulb where the original lamp part is; mirror `I:onLight`. Don't add a Light where one exists.
6. Spin: hide Living's `GwB_Blade` children (the core hides DescendantAdded parts of hidden spin parts) and animate your own blades / drum from `I:onRpm`. Water heads: the GwB_Stream stays visible; put your shower head / spout at the original head position.
7. Doors (Hinge parts: fridge L/R, wardrobe 1/2, microwave): build your own door group and tween it open on `I:on("Open")` (fridge pulses 6 s). Microwave: open on Ding for 1.5 s. Use TweenService on your parts only.
8. Text: hospital originals carry SurfaceGui TextLabels (HangSign / Plate / Cart labels / PCScreen / VitalMonitor). Read `gui:FindFirstChildWhichIsA("TextLabel").Text` and re-letter it in your sign design. Hidden parts get their SurfaceGuis disabled by Scan.hide.
9. No Seats, Humanoids, ClickDetectors, Sounds (except tiny client click sounds via Interact), welds or Constraints.
10. Real-world look: Korean residential / hospital references. Use neutral or fictional brand names on logos (no real trademarks), e.g. "GW", "광안".

Room builders get `(K, V, R)`: V = `Scan.fitRoom(model, spec)` (walls / spans / keep / solid; `V:wall(name,u,y,off)`, `V:spans`, Props.baseboard / wallTiles / ...). K = `Kit.new(V, folder)`. R = { key, kind, label, ctx, unit (Model?), building, floor, cf, w, d, h, windows = { {wall, u0, u1, y0, y1} }?, doors }. spec.cf = room floor centre with **-Z = back wall, +Z = entrance side** (Scan's convention). Give `spec.parts` a pre-filtered list (the room AABB +1) to keep fitRoom cheap on big Floor_ models. Room dressing stays on walls / ceiling / corners; floor items only via `K:spot` (never in front of doors, beds or furniture; homes are decorated by owners).

---------------------------------------------------------------------------------------------------

## 7. Room-level dressing plan

**Hospital** (H4; per-room recipe keyed by the room table in §3):
- Ceilings:
  - 600×600 텍스 tile grid overlay 0.03 below `Ceiling`, with T-bar lines. Keep every LightPanel visible: add aluminium edge frames around them (no new Lights).
  - Sprinkler heads, smoke detectors, PA speaker grilles and return-air diffusers on a grid avoiding the panels.
  - Ceiling-mounted curtain tracks are the beds chunk's job (the Curtain group).
  - OR / resus: a laminar-flow ceiling panel around the SurgicalLights.
- Walls:
  - Vinyl cove base (걸레받이 0.4).
  - 벽 보호대 bumper rail (y 2.6-3.1, beige / wood-tone PVC) along corridors and ward walls.
  - 핸드레일 (y 2.9, round rail on brackets) along the halls (z 28 / 35.6 walls), with gaps at doors (V:spans).
  - Corner guards on outside corners.
  - 손소독제 dispensers beside every room door (inside and corridor side).
  - Wall clocks; 소화기 / 소화전 (Hydrant exists: reskin it as a red recessed cabinet); 비상구 signs.
  - Room ID signs replacing the Plate visuals: blue / teal acrylic, room number, ward type, 담당 간호사 / 환자명 slots, braille dots.
  - Infection-control / 낙상주의 posters; health posters in waiting areas.
- Floors: vinyl sheet inlay accents around the nurse stations; GuideLine reskinned as inlaid 2-colour 유도선 with arrows and labels ("응급실", "엘리베이터"); ArrivalMark as an epoxy hatch zone.
- Per room:
  - 원무과 / lobby: 번호표 발권기 kiosk (번호표 printer), LED 대기번호 displays per 창구 (the NumberDisplay text can animate the number), acrylic sneeze guards on the counter, card terminals, 무인 수납기 ×2, brochure rack, 우산 비닐 포장기 by the entrance, 휠체어 보관대, 열화상 체온측정 kiosk, 안내 desk dressing (monitor, phone, flyers), large potted plants, a TV wall bracket for the tv55.
  - 약국: 처방전 접수 / 수납 / 복약지도 window signs, 약 봉투 baskets, back shelving with medicine boxes (from 처방약장 + MedBox), 조제실 door sign.
  - ER: triage signage + 중증도 분류 board, 응급실 현황판 (patient status board, animated), stretcher (트롤리) parking bay, glove / sharps / sanitizer stations per bay, wall suction + O₂ flow meters (bed chunk headwall), RESUS floor zone, ambulance-door bumper rails.
  - 진료실 (내과 / 소아 / 정형): doctor desk set (2 monitors, keyboard, 청진기, otoscope wall set, BP cuff), exam lamp, footstep stool, X-ray light box, kids decor (wall stickers, height chart, toy shelf).
  - 영상의학과: ☢ "촬영중" red lamp over the door, lead-lined door look, control booth window strip, PACS monitor, CT control console, protective apron hooks.
  - 주사실: medication fridge, sharps box, tourniquet / gauze tray, curtain.
  - Wards 6/4/2/1인실: per bed 개인 사물함 (locker) + over-bed table + TV arm (except where a tv55 exists) + 보호자 침대 (chunk H1 via the WaitingChairs `보호자 의자` variant); window roller blinds; wall clock; hand-wash sink by the door (decor only); bathroom door sign (no real bathroom). VIP 401: wood paneling accent wall, artwork, sofa throws, dining set, fruit basket, kitchenette touches.
  - ICU: central monitoring wall (big screen animated), ceiling pendants (decorative columns) per bed, glass sliding fronts look, 감염관리 gown station by the door.
  - OR: scrub station mirror / timer, wall X-ray viewer, OR clock + elapsed timer, instrument cabinets, sterile floor markings, pendant columns, "수술 중" light (ORLight: reskin, keep text).
  - Nurse stations: EMR monitors (from PCScreen), chart racks, phone, label printer, med cart (Cart), whiteboard with the patient list, lamp, station sign (from HangSign).
  - Day room: water dispenser area, magazine rack, TV, plants, window seating cushions.
  - Halls / lift halls: wayfinding signs (HangSign reskinned as edge-lit aluminium sign boxes with pictograms; keep the text), floor-number plates by the lifts, benches, sanitizer stands.
- **Restrooms** (`Restroom_*` in every GwB building incl. hospital / plaza / hotel / venue): toilet paper holders per stall, coat hooks, sanitary bin (f), urinal privacy screens (m), accessible-stall grab bars, LED mirror strip over the basins, soap dispensers, paper-towel dispenser, baby-changing table (f), floor drains, 청소 중 sign, ceiling vent grille at the `Vent` anchor, "🚹 / 🚺" door-side pictogram plates.

**Homes / hotel rooms / offices** (R1; from GwB_Room parts; Unit attrs Template, Hotel, W, D, Mirror; rooms on the unit's far edge z≈D usually have the windows):
- entry 현관: door mat, 센서등 trim, 우산꽂이, 신발 tidy, 거울.
- bath 욕실: 수건걸이 + towels, 휴지걸이, corner shampoo shelf + bottles, 환풍기 grille, 욕실화, floor drain, mirror-cabinet edge.
- kitchen 주방: utensil set on the kitchen_counter top margin (수저통, 도마, 칼꽂이, 전기포트, 양념통), dish rack, wall menu / magnets. Keep the cook prompt area (Base centre) free of tall stuff.
- utility / veranda 다용도실 · 베란다: 보일러 (wall gas boiler + pipes), laundry basket, detergent shelf, 빨래 줄, plants.
- bed 방 · 침실: curtains on the window wall, wall art, outlets / switch plates, AC wall unit (decor only), pendant / ceiling trim (no new lights).
- living 거실: curtains / blinds, wall clock, art, plants, outlet plates.
- dining 식사 공간: pendant trim, wall art.
- dress / study / media: hangers, books, acoustic panels (media).
- hall 복도: art, console.
- hotel rooms (Hotel=true): 카드키 전원 슬롯 by the door, 객실 안내문, 금고, 커피 트레이, 가운 + 슬리퍼, 'DO NOT DISTURB' hanger.
- Lobbies / 관리사무소 / corridors (Floor_ FloorFinish + Ceiling + Hydrant + CCTV; the apartment lobby desk / bookshelf; the officetel 관리실 shop): mailbox reskin, 무인택배함 (ParcelLocker exists), notice boards, CCTV monitors at the 관리실 desk.

---------------------------------------------------------------------------------------------------

## 8. Budgets and quality targets

- Part targets per item (high / mid / low):
  - Beds 200 / 120 / 60; sofas 160 / 100 / 50; chairs 30 / 20 / 10 per seat; appliances 120 / 70 / 35; small decor 60 / 35 / 15.
  - Hospital big equipment (CT, OR set) 350 / 200 / 100.
  - Room dressing ≤400 / 250 / 120 per room.
  - Hospital 3F worst case: ~15 beds + 6 curtains + chairs ≈ 4-5k parts on high.
- Lights: reskin global 8 / 5 / 2. Items mostly reuse the original lights. New lights only for: vending, aquarium, fridge-open, surgical / monitor glow when on-screen, and only the nearest.
- Animations: ECG / vitals, aquarium fish, fan blades, drum, treadmill belt, TV LED, microwave countdown, wallpad clock, popcorn kettle, rice-cooker steam, waiting-number displays. All run ≤15 Hz while within 30 studs.
- Materials and colours: SmoothPlastic / Fabric / Leather / Metal (r 0.08-0.25) / Glass / Marble / Wood / CeramicTiles. Hospital palette (from Builder/Hospital): BLUE 36,110,190; TEAL 30,140,140; RED 206,34,44; GREEN 40,160,90; VINYL 214,224,222; WARDFLOOR 206,196,178; STEEL 196,200,204; CURTAIN 150,200,222; SEATBLUE 70,130,200. Reuse the Look.luau entries.

---------------------------------------------------------------------------------------------------

## 9. Offline workflow for chunk agents

1. (Verified: the pipeline renders; one 4-camera render took ~11 min wall time because of the shared queue, ~3 s per shot once a slot is free. Scale the cams_item.json eye distances for big items: CT / kitchen_counter W14 / projector 9 wide.) The originals already exist as scenes: `feat/reskin/fx/<itemId>.scene.json`. Render the "before" shots with `node feat/reskin/tools/preview_rs.js <id> --base --cams feat/reskin/tools/cams_item.json --out feat/reskin/shots/<id>_base`. Renders queue behind other agents (global 3 slots), so they can take minutes.
2. The core agent should provide `feat/reskin/tools/rs_sim.luau`, run as `luau rs_sim.luau -a <key> [cw] [label]`:
   - bundle `cat_mods.luau` (shared Kit + Furniture), the client modules (gen.py style, incl. Reskin core + RS_*);
   - build the original at the origin with the same ids as catscene;
   - run the item builder through the real core path (`Reskin.buildOne(model, key)`);
   - write `feat/reskin/out/<key>.gen.json` = `{ parts, guis, lights, hidden = [scene part ids], vcf }`;
   - then `node preview_rs.js <key> --gen out/<key>.gen.json --cams cams_item.json`.
   - Hospital virtual keys need a small fixture builder: copy hbed / chairs / wheelchair / vitals / gasPanel / ivPole / cabinet / cart / curtain from Builder/Hospital (pure Kit code) into the harness.
3. Every RS_*.luau must pass `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/luau/luau-compile --binary <file>`.
4. Temp-studio check (core / integration): `flock /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/.studio.lock timeout 1500 <cmd>` with tools/build_studio_cabin.py (env BLD_SRC) + harness/bld.js shots at the hospital positions in §3.

---------------------------------------------------------------------------------------------------

## 10. Suggested diffs outside our files (for the owners; optional)

Scan.luau: a global owner registry, so Reskin and the main system never fight over a part:
```diff
@@ function Scan.hide(store: { [BasePart]: any }, p: BasePart)
 	if store[p] then
 		return
 	end
+	Scan.owner = Scan.owner or setmetatable({}, { __mode = "k" })
+	if Scan.owner[p] and Scan.owner[p] ~= store then
+		return -- another builder (main system / Reskin) already hides this part
+	end
+	Scan.owner[p] = store
 	local root = lodRoot(p, nil)
@@ function Scan.restore(store: { [BasePart]: any })
 	for p, rec in store do
+		if Scan.owner and Scan.owner[p] == store then
+			Scan.owner[p] = nil
+		end
 		if p.Parent then
```
With that, the reskin can test `ctx.Scan.owner and ctx.Scan.owner[part]` before claiming an item. Without it, the heuristic in §5.4 is used. The ADDONS hook in init.client.luau already loads "Reskin"; no change is needed there.
