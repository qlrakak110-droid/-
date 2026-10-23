# gw-furniture-reskin (wf_496951fd-a58)

- status: completed
- failed agents (never finished, usually the usage limit): core:reskin, fix:reskin, items:C1_bath_public_fixtures, items:C2_living_room, items:C3_kitchen_dining_bar, items:C4_bedroom_dress, items:C5_office_media_music_gym_workshop, items:H1_hospital_beds_patient, items:H2_hospital_desks_reception, items:H3_hospital_medical_equipment, items:H4_hospital_rooms_signage, items:O1_outdoor_infill_optional, items:R1_home_hotel_office_rooms, review:reskin:correctness, review:reskin:experience, test:reskin

## research:reskin

```json
{
 "summary": "# Reskin research: GwangalliBuildings runtime interiors → client AAA reskin\nThe full document, identical to this summary, is at `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/reskin/research.md`.\n\nScope: every runtime-built GwangalliBuildings interior (광안 종합병원 first, then the district buildings, Annex buildings, homes / hotel rooms / offices / lobbies / restrooms). The client builds a detailed, real-world version of each Furniture-catalog item and of the hospital's own fixtures and medical equipment. The reskin happens locally (originals hidden on this client only, gameplay untouched). It also dresses rooms (ceilings, wall rails, signage, accessories).\n\n## 0. Research outputs (scratch, for every agent)\n- `feat/reskin/tools/catalog_dump.txt`: every part of every catalog item, built by the REAL Furniture module in the mock runtime: item-local pos / size / rot / material / colour / transparency / collide / tags / attrs / lights / sounds.\n- `feat/reskin/tools/catalog_summary.json`: per item, the dims, kind, colourways and gameplay parts (Seats with top Y, LieSpot, Screen rects, Lamp parts, Spin, Water heads, hinged doors, Hit / solid boxes, sounds).\n- `feat/reskin/fx/<itemId>.scene.json` (67 files): the original item at the origin (front = -Z, floor y = 0), with a 24x24 floor and a wall behind it (+Z). The format is bprev's preview.js scene format.\n- `feat/reskin/tools/preview_rs.js`: a copy of bprev/preview.js. It takes `--scene`; gen / out default under feat/reskin. It uses the same global 3-slot render queue. `tools/cams_item.json` holds 4 world cameras (front, left34, right34, top).\n  - Render the original: `node preview_rs.js sofa3 --base --cams cams_item.json --out <dir>`.\n  - Verified working: shots/sofa3_base. One render took ~11 min wall time in the shared queue, ~3 s per shot once a slot is free.\n  - With `--gen <gen.json>` (`{parts,guis,lights,hidden:[scene ids],vcf}`) it overlays the reskin.\n  - Scale the cams for big items.\n- `tools/mkcat.py` → `tools/cat_mods.luau` bundles the place's shared Kit + Furniture for the mock (`require(\"./cat_mods\")` gives `{Kit, Furniture, R}`). It shims CollectionService, because a bundled module's mock GetService(\"CollectionService\") is a dummy whose HasTag is always true.\n- `tools/catdump.luau`, `tools/catscene.luau` and `tools/summ.py` regenerate the files above. Luau CLI script args need `-a` (`luau x.luau -a arg1`).\n- Paths are relative to `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/`.\n\n## 1. Where runtime buildings live\n```\nWorkspace.GwangalliBuildings (Folder)\n  <BuildingId> Model tag GwB_Building; attrs BuildingId, Kind(archetype), DisplayName, Floors, Wear, BoundsCF, BoundsSize, Annex?\n    Shell        always present: facade, slabs, roof, signs. Rooftop sunbeds (officetel/hotel), hospital forecourt Bench\n    Interior     tag GwB_Interior. Built when a player comes within 42 studs, PARKED to ServerStorage after nobody is\n                 within 85 studs for 25 s (re-parented; the client sees remove → re-add as NEW instances)\n      Elevators  (skip)\n      Floor_<label>  attrs BuildingId, Floor, Y(=fl.y). Walls, Door_* (GwB_Door), corridor (FloorFinish, Ceiling,\n                 LightPanel+Light, Hydrant, CCTV). hooks.floor content: THE WHOLE HOSPITAL lives directly here\n        Shop_<id>   tag GwB_Shop; attrs ShopId, ShopKind, DisplayName, BuildingId, Floor, Frame, W, D;\n                    ShopFloor/ShopCeiling/Lining, counters, Point_* (GwB_ShopPoint), Seats (GwB_Seat), catalog items, Furnish\n        Unit_<n>    tag GwB_Unit; attrs UnitId, BuildingId, Floor, Template, Tier, Price, ForSale, OwnerUserId, Mirror,\n                    Frame(world unit frame: x 0..W across, z 0 = entrance wall .. D = far/window wall), W, D, Label, Hotel\n          Structure  walls, Partition, Wallpaper/Floor (GwB_Finish), Ceiling, LightPanel (room light, off), doors, Glass\n          Fixtures   built-in catalog fixtures (UnitId, Fixed=true, W for kitchen_counter) + Switch parts (BasePart,\n                     GwB_Fixture Kind=switch, RoomIds)\n          Furnish    staging (Staging=true) OR the owner's layout (Placed=true, Uid, OwnerUserId, tag GwB_Placed)\n          Rooms      Room_<id> BasePart tag GwB_Room; attrs RoomId, UnitId, Kind, Label (CFrame = unitFrame*(cx, ceil/2, cz),\n                     size (w, ceil, d))\n        Furnish    tag GwB_Furnish (per-storey lobby props)\n  Annex (Folder)   Annex storefront rooms: Model attrs AnnexRoom=true, ShopLifeType, ShopLifeMenu, ShopLifeKey; ShopFloor,\n                   Interior, Outside; y≈3000\n  AnnexDoors       prompts on the real map\nWorkspace.GwangalliBuildingsShopLife/<key>/Anchors   ShopLife LifePrompt anchors (keep clear)\nWorkspace.GwangalliHospital                          invisible HospitalPoint parts\nWorkspace.GwangalliInfill                            parks / lots (optional chunk O1)\n```\n- `StreamingEnabled=true`. GwB models use the default streaming mode: the Model container arrives first, with its attributes, and its parts stream in one by one.\n- The server builds over many frames (260 parts per step). Furnish storeys exist near players only (radius 45, unfurnish after 30 s). Hospital floors exist whole while the interior is hot.\n- District (origin CFrame(4283.5,18.9,-200)*yaw(-90)):\n  - apartment: B1, 1F lobby + 관리사무소 desk / bookshelf, homes, penthouse.\n  - officetel: GW25 cvs, 관리실, rooftop sunbeds.\n  - villa: + 옥탑방.\n  - oneroom.\n  - plaza: 국밥 / 부동산 1F, PC방 2F, 노래방 3F, 당구장 4F, restrooms on every floor.\n  - hotel: lobby, Royal casino, rooms 4-7F, rooftop.\n  - bbq 1F/2F.\n  - cafe: 1F/2F + rooftop.\n- Also: 광안 종합병원 (id `hospital`); hideout (no catalog); Annex buildings `annex_<hash>` at y 3000 (slot 560 from (-9600,3000,-9600)); Annex storefront rooms.\n- Builder/Shops kinds (ShopFlows shops): cvs, gukbap, bbq, cafe, pcbang, karaoke, billiards, realtor, hotel_lobby, office.\n- **ShopLife runtime shops**:\n  - Annex storefront rooms (types soup, noodle, katsu, grill, rawfish, seafood, pocha, pub, chicken, snack, chinese, cafe, burger, dessert, bakery, cvs, retail, pharmacy, laundry, realty, lobby, residence, salon, clinic, academy, gym, bank, office, play).\n  - The 10 hospital departments.\n- The main client system (init.client.luau) builds map shops, Venues and AnnexRoom rooms only. It never builds GwB district, Annex-building or hospital interiors, so for those the Reskin is the only client detailer.\n- Catalog usage counts: washbasin 21, toilet 17, monstera 17, sofa3 16, tv55 15, wallpad 13, shower 13, armchair 12, desk 11, microwave 10, kitchen_counter 10, fridge 10, bed_single 10, wardrobe 9, coffee_table 9, bed_queen 9, water_dispenser 8, washer 8, vending 7, dining2 7, tv_small 6, ...\n- Grades.ROOMS sets and the decor shop can put any item in owners' homes.\n\n## 2. Furniture catalog contract\n`Furniture.build(id, parent, cf, colorway, extra)` builds each item as a Model:\n- Name = id.\n- PrimaryPart **Base**: invisible box w×max(h,0.2)×d at `cf*(0, mountY+h/2, 0)`, CanQuery=true. The **server prompts FxPrompt1/2 are inside Base** (no LOS).\n- Attrs: ItemId, Colorway, Label, Kind (only with def.kind), plus extras applied BEFORE build: Public, UnitId, ShopId, Fixed, Staging, Placed / Uid / OwnerUserId, **W** (kitchen_counter width), Ghost, RoomSet.\n- Tag GwB_Fixture ONLY when def.kind exists. **12 untagged items**: coffee_table, monstera, bookshelf, rug, frame_art, aquarium, shoe_rack, drying_rack, tool_wall, parts_shelf, closet_island, liquor_shelf.\n\nItem frame and parts:\n- **Item frame**: origin = floor centre, **front = -Z** (wall items back onto +Z).\n- On the client: `F = Base.CFrame * CF(0, -(mountY + h/2), 0)`, with dims from `require(ReplicatedStorage.GwangalliBuildingsShared).Furniture.ITEMS` (the client may require it). Never use Base.Size.Y (rug).\n- kitchen_counter: Base is always 9 wide; the real width is attr W (5 / 6 / 7 / 8 / 14).\n- Colourways: rotated so c[1] = colors[cw], c[2] = next.\n- Details are mostly named \"Part\" and CanCollide=false; collision comes from invisible `Hit` boxes / solid parts.\n- Seats: class Seat \"Seat\" 1.8×0.3×1.8, Transparency 1, Disabled, tag GwB_Seat, attr Index; top = centre + 0.15.\n- Beds / sunbed: `LieSpot` part, which the server poses the character at.\n- Screens: part \"Screen\", tag GwB_Screen, ScreenKind. The client Living module draws its SurfaceGui on the **Front (-Z) face** while the fixture is On. The gui renders even when the part is transparent, so keep Screens visible and build around them.\n- GwB_Lamp parts with a Light child (the server toggles Light.Enabled and Neon / SmoothPlastic).\n- GwB_Spin (Rpm / Axis): Living adds `GwB_Blade` children while Rpm≠0.\n- GwB_Water heads: Living adds a `GwB_Stream` child while On.\n- Sounds are Attachments `Snd_<key>`.\n\nServer state attributes on the fixture Model (Interact service). No client animates Open / Fill / Flush / Ding / Vend / Pour today, so the reskin may.\n- tv: On, Channel 1..6.\n- fridge: Open true for 6 s.\n- wardrobe / closet_wall: Open toggle.\n- microwave: On 12 s + turntable Rpm 30, then Ding = server time.\n- timedUse sets On for N s plus Busy (server time until) and Done: shower 10, sink 3, dryer 3, washer 30 + Drum Rpm 160, treadmill 30, massage 15, cook 12, instruments / bar / game / cinema social, lift / boxing / workbench / dress / office / popcorn.\n- bathtub: Fill 1→0 after 30 s. The jacuzzi starts at Fill=1.\n- toilet: sits, then Flush after 4 s.\n- lamp / aircon: On toggle. fan: On + Rpm 600.\n- pc: On + sit. water: Pour. vending: Vend. switch: On + Click.\n- bed: 눕기 / 잠자기 on LieSpot.\n\nItem table (studs; 1 stud ≈ 0.3 m; coordinates item-local, front -Z):\n\n| id | name | w×d×h | kind | cw | gameplay / special parts |\n|---|---|---|---|---|---|\n| sofa3 | 패브릭 3인 소파 | 8×3.4×3.2 | seat | 4 | Seats x -2.2/0/2.2, z -0.3, top 2.10; Hit 8×2×3.4 |\n| armchair | 라운지 암체어 | 3.4³ | seat | 3 | Seat (0, top 2.15, z -0.25); swivel base |\n| coffee_table | 원목 커피 테이블 | 5×2.6×1.5 | — | 3 | top 1.5, shelf 0.35-0.5 |\n| tv55 | 55인치 TV + 거실장 | 7×1.6×5.6 | tv | 3 | cabinet 0-1.5; Screen x ±3.15, y 2.35-5.45, z 0..0.06 (face z=0); PowerLed (2.95, 2.31); snd tv_talk on Base |\n| tv_small | 32인치 TV | 3.4×1.2×4.2 | tv | 2 | cabinet 0-2.2; Screen x ±1.5, y 2.5-4.1, z ±0.02 |\n| floor_lamp | 아크 플로어 스탠드 | 1.6²×6.2 | lamp | 2 | Shade lamp (y 5.1-6.1, PointLight off) |\n| monstera | 몬스테라 화분 | 2²×4.6 | — | 3 | pot dia 1.8 h 1.6, 7 Leaf |\n| bookshelf | 5단 책장 | 4×1.3×6.4 | — | 3 | 60 parts, shelves every 1.25 |\n| aircon | 스탠드 에어컨 | 1.9×1.5×6 | aircon | 1 | Vent (y 3.6-5.5, snd aircon_hum), Display neon y 2.9-3.2 |\n| fan | 스탠드 선풍기 | 1.8²×4.4 | fan | 2 | Hub spin (0, 3.4, -0.35) axis X; Guard dia 2.2 |\n| bed_single / bed_queen / bed_king | 슈퍼싱글 / 퀸 / 킹 호텔식 침대 | 4.2×7 / 5.6×7.2 / 6.6×7.4, h 4.2 / 4.2 / 4.4 | bed | 3 / 4 / 3 | LieSpot (0, 2.85, 0.4); mattress top 2.1, duvet 2.3; headboard at +Z to y 4.2; pillows 1 / 2 / 2 |\n| wardrobe | 2도어 옷장 | 4.4×2×7 | wardrobe | 3 | WardrobeDoor1/2 Hinge -1/+1 at z -1..-0.92; rail y 5.6 |\n| desk | 책상 + 의자 | 4.4×4×3.6 | seat | 3 | top 2.8 over z -0.2..2; DeskLamp spot off; chair Seat (0, top 2.05, z -1.0) yaw 180 |\n| pc_desk | 게이밍 PC 세트 | 5×4.2×4.4 | pc | 2 | top 2.8; Screen x ±1.6, y 3.3-5.1, z 1.54-1.56; RGB / RGB2 (Rgb attr); chair Seat (0, top 2.05, z -1.1) |\n| fridge | 양문형 냉장고 | 3.2×2.6×6.4 | fridge | 3 | FridgeDoorL/R Hinge ∓1 (z -1.3..-1.1); Inside lamp (off) + snd |\n| kimchi_fridge | 스탠드 김치냉장고 | 2.4²×5.8 | fridge | 2 | 3 drawer fronts; Inside tr 1 |\n| microwave | 전자레인지 | 1.8×1.3×1.1 | microwave | 2 | MwDoor Hinge -1, Inside lamp, Turntable spin Y, Clock neon; usually at item y 3.05 (cvs 3.6) |\n| dining4 | 4인 원목 식탁 | 6×6.2×3 | seat | 3 | top 2.85 over x ±2.6, z ±1.6; Seats (±1.3, ±2.5) top 2.0 |\n| rice_cooker | 전기밥솥 | 1.2×1.3×1.2 | cook | 2 | Panel neon; on counters y 3.05 |\n| washer | 드럼 세탁기 | 2.4²×3.4 | washer | 2 | Drum spin X (0, 1.5, -1.29) dia 1.3 |\n| massage_chair | 안마의자 | 3×5×4.6 | massage | 2 | Seat (0, top 2.25, z 0.2); back ramp to (0, 4.6, 2.5); leg ramp to z -2.5 |\n| treadmill | 러닝머신 | 2.8×6×4.6 | exercise | 1 | deck 0-0.6 collides; Belt; Screen (0, 4.3, -2.51) 1.4×0.4; console at z -3 |\n| rug | 라운드 러그 | 7 dia ×0.1 | — | 3 | 2 discs ≤0.09 |\n| frame_art | 광안대교 야경 액자 | 3.6×0.3×2.6, mountY 3.6 | — | 2 | Art with SurfaceGui |\n| mood_light | 무드등 | 0.9²×1.4 | lamp | 3 | Globe lamp, light colour = colourway |\n| aquarium | 열대어 어항 | 3.4×1.6×4.6 | — | 2 | cabinet 0-2.4; Tank 2.4-4.4 + PointLight + snd; 5 Fish |\n| vanity | 화장대 | 3.6×1.8×5.6 | seat | 2 | desk 0-2.6, z 0..1.8; Mirror z 1.6; stool Seat (0, top 1.90, z -0.8) |\n| shoe_rack | 신발장 | 3.2×1.3×3.6 | — | 2 | |\n| dining2 | 2인 카페 테이블 | 3×5.4×3 | seat | 3 | round top dia 2.6, top 2.775; Seats (0, top 2.0, z ±1.9) |\n| minibar | 미니 냉장고 | 1.8²×2.8 | fridge | 2 | solid body, Inside tr 1 |\n| kitchen_island | 아일랜드 식탁 | 8×3×3.1 | seat | 2 | body solid z -1..1.5; marble top 3.1; 3 stools OUTSIDE the footprint: Seats (x -2.4/0/2.4, top 2.30, z -2.2); Pendant lamp y 7.4-8 (on) |\n| drying_rack | 빨래 건조대 | 5×2.2×3.6 | — | 2 | |\n| jacuzzi | 월풀 자쿠지 | 7 dia ×2.6 | bathtub | 2 | shell collides; Water tr 0.35, Fill 1, PointLight; Head (0, 2.65, 3.15); Seats top 1.75 at (0, 1.2), (±1.6, -0.8) |\n| sunbed | 선베드 | 2.6×7×2.6 | bed | 2 | LieSpot (0, 2.0, 0.2) tilted 70°; back toward +Z; rooftops |\n| kitchen_counter | 싱크대 (인덕션 · 후드) | W×2.2×9 (fixed) | cook | 2 | body solid 0-2.8; Top 3.0; Sink x -W/2+1..+3 + Spout water; Cooktop W/2-3.4..-0.6 + 2 Burners; Hood y 6.6-7.4 (snd); upper cabinets 6.2-8.6 over x -W/2..W/2-3.6; backsplash z 1.05-1.1; UnderLight surface (off) |\n| toilet | 양변기 | 1.8×3×3.2 | toilet | 1 | Seat (0, top 1.60, z -0.1); Tank z 0.8-1.5 to y 3.2 |\n| washbasin | 세면대 | 2.4×1.6×6 | sink | 1 | Basin top 2.9; Spout (0, 3.42, 0.28); Mirror y 3.8-6 at z 0.76 |\n| shower | 샤워부스 | 3.6²×7.6 | shower | 1 | tray 0-0.2; GlassFront z -1.75 tr 0.7; Head (0, 6.9, 1.0) + snd |\n| bathtub | 욕조 | 6×3×2.2 | bathtub | 1 | walls collide; Water tr 1 (Fill); Head (2.3, 2.55, 1.2); Seat (0, top 1.05, z 0.2) yaw 90 |\n| urinal | 소변기 | 1.6×1.4×4.2 | toilet | 1 | no seat |\n| hand_dryer | 핸드 드라이어 | 1.2×0.8×1.4, mountY 3.6 | dryer | 1 | Body (snd) |\n| wallpad | 월패드 | 1.4×0.2×1, mountY 4.4 | wallpad | 1 | Screen (neon) |\n| water_dispenser | 온수기 | 1.4²×4 | water | 1 | body 0-3.2, bottle 3.2-4, taps y 2.0 at z -0.75 (Hot red / cold blue) |\n| vending | 음료 자판기 | 3.6×2.6×6.4 | vending | 2 | solid; Window x -1.6..0.8, y 2.4-6 + SurfaceLight; 24 cans; Coin neon; slot y 0.6-1.4 |\n| gaming_setup | 게이밍 PC 책상 | 5×2.6×5.2 | pc | 2 | top 2.6; Screens (-0.6, 3.65, 0.55) 2×1.3 and (1.4, 3.55, 0.55) 1.6×1.1; Keyboard; RGB; Tower; Seat (0, top 2.10, z -1.8) |\n| console_set | 콘솔 게임 세트 | 7×1.6×5.8 | game | 2 | cabinet 0-1.4; Screen x ±3.15, y 2.15-5.65, z 0.05-0.1; Console; 2 Pads |\n| projector_screen | 홈시네마 스크린 + 프로젝터 | 9×1×7.2 | cinema | 1 | Screen 8.6×5.2 y 1.6-6.8, z 0.2-0.3; 2 Speakers x ±4 |\n| recliner_row | 전동 리클라이너 3인 | 8.4×3.4×3.4 | seat | 2 | Seats x -2.8/0/2.8, top 2.0, z -0.3 |\n| popcorn_machine | 팝콘 기계 | 2²×4.4 | popcorn | 1 | base solid 0-2; glass Bowl 2-3.9 |\n| bench_press | 벤치프레스 세트 | 3×6×4.4 | lift | 1 | bench y 1.2-1.6; uprights z 1.6-1.8; bar y 3.6; Seat (0, top 1.95, z -0.6) |\n| punching_bag | 스탠드 샌드백 | 2.6²×6.6 | boxing | 2 | base + Bag solid |\n| dumbbell_rack | 덤벨 랙 | 4×1.6×3 | lift | 1 | tiers y 1.1 / 2.3 |\n| workbench | 정비 작업대 | 7×2.6×3.4 | workbench | 2 | top 3.1; Vise |\n| tool_wall | 공구 타공판 | 6×0.4×6, mountY 2.5 | — | 1 | board y 2.5-6 |\n| parts_shelf | 부품 선반 | 5×1.6×6 | — | 1 | 4 shelves, 9 boxes |\n| closet_wall | 시스템 드레스룸 행거 | 9×2.2×7.4 | wardrobe | 2 | rail y 5.8; drawers 0.2-1.6 |\n| closet_island | 드레스룸 아일랜드장 | 4.6×2.6×3.2 | — | 2 | glass top 3.0-3.2 |\n| full_mirror | LED 전신거울 | 2.6×0.6×6.6 | dress | 1 | Mirror + LED lamp (on) |\n| bar_counter | 홈바 카운터 | 7×2.4×3.8 | bar | 2 | top 3.8; neon strip lamp (on) |\n| bar_stool | 바 스툴 | 1.8²×3.2 | seat | 2 | Seat (0, top 3.15) |\n| liquor_shelf | 술장 (백바) | 7×1.4×7.6 | — | 1 | 4 glass shelves × 10 bottles; glow lamp (on) |\n| piano | 업라이트 피아노 | 5×2.2×4.4 | instrument | 2 | Keys y 2.5-2.6, z -1.05..-0.4; Seat (0, top 1.90, z -1.85) |\n| drum_kit | 드럼 세트 | 5×4.4×4.6 | instrument | 2 | throne Seat (0, top 2.10, z -1.6) |\n| guitar_stand | 기타 + 스탠드 | 1.6²×4 | instrument | 2 | |\n| office_desk | 듀얼 모니터 업무 책상 | 6×2.8×5 | office | 2 | top 2.6; Screens (±1.2, 3.65, 0.65) 2×1.3; Seat (0, top 2.10, z -1.95) |\n\n## 3. 광안 종합병원\n- Site x -704, z 1236, yaw 90. `rec.cf = CF(-704, FFL, 1236)*Angles(0, rad 90, 0)`, with FFL = raycast ground + 0.3 (≈12.8).\n- Building-local frame: x across the facade (-40..40), +x maps to world -Z. z from the facade (0) into the lot (60), +z maps to world +X (world X = -704+z, Z = 1236-x). y above the 1F FFL.\n- The building model is `Workspace.GwangalliBuildings.hospital`; Workspace attr `GwB_Hospital=\"hospital\"`.\n- **Client frame**: `rec.cf = BoundsCF * CF(0, -BoundsSize.Y/2 + 1, -(BoundsSize.Z-2)/2)` (exact; cross-check ShopFloor of `hospital_reception` = rec.cf*(8, 0.045, 14.2)).\n- Storeys: 1F y 0 (ceiling 12); 2F y 13, 3F y 24, 4F y 35 (ceiling 10); RF 46.\n- Cores: stair x -9.4..1.4, lifts x 1.7..21.5, z 35.6..54.7.\n- Restrooms every floor: Restroom_m frame (22.2, 0, 36.2) and Restroom_f (31.2, 0, 36.2), 8.6×23.4.\n- Hall z 28..35.6. Doors: main auto (x 12, z 0, w 7), ER walk-in (x -25), ambulance (-x side z 46).\n- Test shots (world): lobby (-698, FFL+3, 1226), ER (-679, FFL+3, 1261), 301 (-691, FFL+27, 1267), ICU (-694, FFL+38, 1231), OR (-652, FFL+38, 1260).\n\nHospital fixture Models (tag GwB_Fixture, Kind, Label, Public; NO ItemId; children of Floor_<label>):\n- **HospitalBed** (bed), head +Z. Frame = `BedFrame.CFrame*CF(0,-1.15,0)`.\n  - Parts: BedFrame 3.2×0.3×6.6 @1.15; 4 BedLeg; 4 Caster; **Mattress 3.2×0.9×6.6 @1.75 = PrimaryPart (the prompt lives here)**, top 2.2; Blanket @(0, 2.24, -0.9) 3.26×0.12×4.6; Pillow @(0, 2.36, 2.5); HeadBoard 3.4×2.8×0.25 @(0, 2.6, 3.35); FootBoard @(0, 2.2, -3.35); 2 SideRail @(±1.75, 2.6, 0.9); LieSpot (0, 2.95, 0.4). Hospital.admit finds beds by Name.\n  - Labels: 응급 베드 1-4, 소생실 침대, 처치실 침대, 물리치료 베드 1/2, 진찰 침대, 소아 진찰 침대, 301호 1-6, 302호 1-4, 303호, 304호, 305호, 306호, 401호 VIP 1, 402호, ICU 1-4, 403호, 404호.\n- **WaitingChairs** (seat). Frame = `Beam.CFrame*CF(0,-0.95,-0.2)`; n = number of Seats; len = 2.2n.\n  - Parts: Beam (len×0.25×0.5 @(0, 0.95, 0.2)); ChairLeg ×2; per seat a VISIBLE coloured Seat 1.9×0.3×1.9 @(px, 1.8, 0) (top 1.95; px = -len/2+1.1+2.2(i-1)) + ChairBack 1.9×2×0.2 @(px, 2.95, 0.95) tilted -8°. Sitters face -Z; PrimaryPart = first Seat.\n  - Labels: 대기 의자 (blue rows of 4), 응급실 대기 의자 (red), 약국 대기 의자 (green), 스테이션 의자 (n 1), 보호자 의자 (n 1 / 3), 수액 의자 1/2 (n 1), ICU 의자 (n 2).\n- **Wheelchair**: frame Seat.CFrame*CF(0,-1.9,0); visible Seat top 2.025; WheelchairBack, 2 Wheel d2.4, FootRest.\n- **Bench**: Shell forecourt; Seat WoodPlanks 5×0.3×1.6 @1.7.\n- Catalog items in the hospital (Public): tv55 (lobby, wards 301 / 304 / 401, day rooms, 2F waiting), sofa3 (304, 401, day room ×2), coffee_table / fridge / dining2 (401), monstera (lobby ×2, 401), washbasin (처치실, 내과, OR scrub ×2, restrooms), treadmill (rehab), vending (1F ×2, 2F, 3F), water_dispenser (1F / 2F / 3F), toilet / urinal / hand_dryer.\n\nLoose named parts (direct children of Floor_<label>; builder frames face -Z; Kit.text \"front\" = -Z):\n- Per bed: GasPanel 2.6×0.7×0.15 at bed*(0, 5.2, 3.6) + 3 GasOutlet; VitalMonitor 1.8×1.3×0.3 at bed*(-1.6, 6.4, 3.55) (big 3.4×2.2 in resus / ICU wall / OR), static text; BedsideCabinet 1.6×2.8×1.6 at bed*(2.6, 1.4, 2.6); 보호자 의자 at bed*(2.8, 0, 0)*yaw90 unless noChair.\n- ER bays bz 17 / 23 / 29 / 35: GasPanel (-39.45, 5, bz) yaw -90; VitalMonitor (-39.4, 6.6, bz-1.6); number Plate; IVPole (-38.4, bz+2.2).\n- IVPole (h 6.8, d 0.15) + IVBag + IVBase.\n- Curtain (span, y 0.8..ceil-0.6, Fabric 150,200,222 tr 0.15) + CurtainTrack.\n- Cabinet (w×h×1.4, Handles at -Z), Cart (body 2.4×3×1.6 @1.9 + CartTop + 3 Drawer; front text CRASH CART / 제세동기 / 투약 카트 / 수술 기구), PCScreen 1.6×1×0.12 \"EMR 환자 목록\" + PCStand + Keyboard.\n- Signage:\n  - HangSign (double-sided) + 2 SignRod.\n  - Plate (room names y 8.2-8.5 on the corridor side, ☢ 방사선 관리구역, eye chart, height chart, spine poster, SCRUB 손 씻기 5분, bay numbers).\n  - **DirectoryKiosk** (tag GwB_Hospital, HospitalKind=directory, server prompt \"층별 안내 보기\"; 1F (24, 4, 24.5) 3×8×0.6 and lift halls (-12.6, 3, 34.6) 2.2×6×0.6).\n  - NumberDisplay 8×1.2; InfoSign; ORLight (neon \"수술 중 IN OPERATION\" (-24, 9.1, 43.7)); ExitSign.\n- Desks:\n  - Dept Models (ShopLife) hold FrontDesk (box to 3.5) / Counter + DeskTop marble 3.5-3.75 + DeskBell (y 3.85). R4: overlay only, same top 3.75 / XZ, keep DeskBell.\n  - StationCounter / StationTop (top 3.8 or 3.75), ICUDesk / ICUDeskTop (3.8), InfoDesk / InfoDeskTop (round dia 4.4, top 3.75) + InfoPole, 처방약장 (x 38.9..39.5, z 1..18, h 9) + 32 MedBox.\n- Equipment:\n  - CT: CTGantry cyl d7.2 @(-30, 4.6, 10) yaw 90 + CTBore / CTBase / CTTableBase / CTTable (z 6..19).\n  - X-ray: XrayTable (-38.6..-34.6, 3..12) + XrayColumn + XrayTube.\n  - SurgicalLight neon d3.2-3.4 + SpotLight, with SurgicalArm: resus (-18, c-1.7, 51), OR (-22, z 50 / 54).\n  - ORTableBase / ORTable (-24.4..-19.6, 48..56, top 3.7); AnesthesiaMachine (-16.4..-14, 47..49.4, h 5).\n  - Ventilator 1×4.2×1.4 per ICU bed.\n  - ParallelBar (x -9.6 / -6.4, y 3.4-3.6, z 3..15) + 6 BarPost.\n  - Scale (11..13.4, 20..22.4).\n  - ToyBall, Balloon, PlayMat (-39.4..-33.6, 52..59.4), ToyBlock ×6.\n  - SanitizerStand + Sanitizer; ArrivalMark / ArrivalMarkIn; GuideLine (red / green).\n- Structure: dept ShopFloor (y 0-0.09, never hide), FloorFinish, Ceiling, LightPanel (GwB_Lamp / GwB_Light, host-managed), Wall (Plaster 232,230,224), GlassWall / GlassBase (resus, ICU), Door_* (skip), Hydrant, CCTV.\n\nDepartments (Model attrs ShopLifeType / ShopLifeMenu / ShopLifeKey = HospitalDept, Floor; tag GwB_HospitalDept; ShopFloor area | desk):\n- 1F\n  - hospital_reception 원무과: -9.8..25.8, 0.4..28 | FrontDesk x 0..22, z 21..23 (4 windows at x 2.75 / 8.25 / 13.75 / 19.25).\n  - hospital_er: -39.6..-10.2, 0.4..59.6 | triage -38..-30, z 9..11.\n  - hospital_pharmacy: 26..39.6, 0.4..19 | Counter x 34..35.6, z 2..17.\n- 2F (desks at z 22..23.6)\n  - imaging: -39.6..-22.2 | -38..-32.\n  - rehab: -21.8..-4.2 | -20..-14.\n  - internal: -3.8..13.8 | -2..4.\n  - peds: 14.2..31.8 | 16..22.\n  - inject: 32.2..39.6 | 33..38.\n- 3F ward3: -39.6..-9.8, 35.6..59.6 | -36..-16, z 38..39.6.\n- 4F ward4: -39.6..-9.8, 35.6..43.8 | same.\n- ShopLife anchors live in Workspace.GwangalliBuildingsShopLife/<key>/Anchors: 2-stud clearance, no cosmetic prompts within 6.5.\n\nRoom table (building-local; front rooms z 0.4..27.8 with doors on the z=28 corridor wall):\n- **1F**\n  - lobby (-9.8..39.6, 0.4..28): 원무과 counter + cabinet wall z 26.6; 안내 desk (2, 5); waiting rows x 4 / 19 × z 10 / 13 / 16 (face -z); tv55 (-9, 8) yaw -90; wheelchairs (21, 3) and (23, 3); sanitizer (7, 2.2); plants; directory (24, 24.5).\n  - 약국 (26..39.6, 0.4..19): chairs (28.4, 9) yaw -90 ×4.\n  - vending corner (25.8..39.6, 19..28): vending x 38.3 at z 21.4 / 25.4 yaw 90; water (27.4, 27).\n  - ER (-39.6..-10.2, 0.4..44): waiting chairs x -18 / -14, z 7 yaw 90; 4 bays at x -36; nurse island -30..-20, z 21..29; arrival zone (-38.6..-30, 41..51).\n  - 소생실 (-26..-10.2, 44..59.6, glass, door x -18.5).\n  - 처치실 (-39.6..-26.2, 52..59.6, door -29.2).\n  - hall (-9.8..39.6, 28..35.6).\n- **2F**\n  - Partitions x -22 / -4 / 14 / 32. Doors: 영상 x -31, 정형 -13, 내과 5, 소아 23, 주사 36.\n  - imaging: CT, X-ray.\n  - rehab: physio beds x -18.2 at z 6 / 13, bars, treadmill (-8, 21) yaw 180.\n  - 내과: exam bed (9.5, 4.4), curtain x 6.4, eye chart, scale, washbasin (13.2, 14).\n  - 소아: exam bed (27, 4.4), height chart, toys, 3 guardian chairs (20, 14).\n  - 주사실: 수액 의자 (36, 5) / (36, 11) + IV x 38.4 + cabinet (36, 16.6).\n  - back zone (-39.6..-9.8, 35.6..59.6): station + cabinets z 44.4; waiting rows (-30 / -19.6, z 50 / 53); tv55 (-25, 46.2) yaw 180; kids PlayMat; water (-11, 58.6); vending (-14.6, 58.2).\n- **3F**\n  - Partitions x -22 / -4 / 8 / 20 / 32.\n  - 301 6인실: beds (-36, z 6 / 13 / 20) yaw -90 + (-25.8, z 6 / 13 / 20) yaw 90; curtains z 9.5 / 16.5; tv55 (-31, 1.6) yaw 180.\n  - 302 4인실: beds (-18.2, z 6 / 15) + (-7.8, z 6 / 15).\n  - 303 2인실: beds (-0.4, 4.2), (4.6, 4.2) yaw 180.\n  - 304 1인실: bed (14, 4.2) + monitor + sofa3 (18.6, 16) yaw 90 + tv55 (9.2, 14) yaw -90.\n  - 305 2인실, 306 1인실.\n  - Back: station + 투약 카트 (-14, 42) + 휴게실 (sofas (-34, 57.4) and (-24, 57.4), tv55 (-29, 46)).\n- **4F**\n  - Partitions x -22 / -10 / 20 / 32; the ICU front x -10.2..19.8 is glass.\n  - 401 VIP: bed (-33, 4.2), wood floor, sofa3 (-24, 14), coffee_table, tv55 (-38.8, 14), fridge (-38.6, 23), dining2 (-30, 22).\n  - 402.\n  - ICU (-10..20, door x 5 auto w 6): beds at x -6 / 1 / 8 / 15, z 4.2 + Ventilators; desk x -2..8, z 18..19.6; big monitor (3, 7.4, 27.4).\n  - 403, 404.\n  - Station z 35.6..43.8; OR wall z 44 (double door x -24).\n  - OR (-39.6..-9.8, 44.2..59.6): table, 2 lights, anesthesia, 2 carts, 2 scrub basins (-38.8, z 52 / 56).\n- Windows (upper storeys): facade z=0 every 6 studs (y 2.8..8.6); side walls z 2..26; back wall x -39.2..-10.\n\n## 4. Rules (map survey R1-R15, applied to the reskin)\n- **R1 / R4**: never destroy, move, rename, reparent or resize server instances; hide only locally. Gameplay parts are overlaid at the exact pose: seat top ±0.1 and same facing; tops of tables / desks / counters / ShopLife desks same top Y and XZ. Leave alone: LieSpot, Hit, Base / PrimaryPart, Mattress, ShopFloor, FrontDesk / DeskTop / DeskBell / Counter, DirectoryKiosk, door Models, elevators, stairs.\n- **R2**: parent everything under `ctx.root` (Workspace.GwInteriorDetailLocal, LOD=\"near\"), one sub-Model per item.\n- **R3**: hide with `ctx.Scan.hide(store, part)` (handles GwArrive / LOD roots, disables SurfaceGuis / Decals); call `Scan.reapply(store)` every tick and `Scan.restore(store)` on drop.\n- **R5**: new parts are Anchored, CanCollide / CanQuery / CanTouch = false, Massless, and CastShadow only on big pieces (`K:make` does this). Never use `look.collide`. Thin overlays go 0.02-0.05 off the surface.\n- **R6 / R7**: keep door swings, auto-door pockets and ShopLife anchors clear; add nothing on top of ShopLife desks except flush details; keep ≥2.5-stud approaches to beds and chairs.\n- **R8**: host prompts need no line of sight, so overlays never block them. Cosmetic prompts only through `Interact.prompt` (client \"GwInteriorPrompt\", R key, ≤5 studs, ≥6.5 from host prompts). Every kind≠nil item has its prompt at its Base, so NO cosmetic prompts on those; never duplicate a server action.\n- **R9**: lights carry attr GwIndoorDim=0 (`K:light`), Shadows off, own budget; never toggle GwB_Light / InteriorLight lights.\n- **R10**: never write Window / RoomGlass / NightWindow / Sign_* props; blinds stay ≥0.3 inside the glass.\n- **R11 / R12**: use tag signals; DescendantAdded scoped to GwB containers is fine. Parked interiors return as new instances.\n- **R13**: time-slice ≤2.5 ms per frame; tier budgets. **R15**: no welds to characters.\n\n## 5. Discovery strategy (core)\n1. `GB = Workspace:WaitForChild(\"GwangalliBuildings\", 60)`; retry slowly if absent.\n2. Tag `GwB_Building` (GetTagged + Added / Removed). For each building: `DescendantAdded` / `DescendantRemoving` + one time-sliced `GetDescendants` sweep. Classify:\n   - Model with attr ItemId → catalog item (skip Ghost; DecorMode ghosts sit in the Workspace root, so scoping excludes them).\n   - In the hospital building: Models HospitalBed / WaitingChairs / Wheelchair / Bench → `H:<Name>`. BasePart anchors → `H:<Name>` with siblings grouped by name within a radius:\n\n     | anchor | siblings | radius |\n     |---|---|---|\n     | CTGantry | CTBore / CTBase / CTTableBase / CTTable | 12 |\n     | XrayTable | XrayColumn / XrayTube | 6 |\n     | SurgicalLight | SurgicalArm | 2 |\n     | ORTable | ORTableBase | — |\n     | IVPole | IVBag / IVBase | 1.5 |\n     | GasPanel | GasOutlet | 1.6 |\n     | Cabinet | Handle | w/2+0.5 |\n     | Cart | CartTop / Drawer | 2 |\n     | Curtain | CurtainTrack | same span |\n     | PCScreen | PCStand / Keyboard | 1.2 |\n     | InfoDesk | InfoDeskTop / InfoSign / InfoPole | 3 |\n     | SanitizerStand | Sanitizer | 2.5 |\n     | ParallelBar | BarPost | 7 |\n     | StationCounter | StationTop | — |\n     | ICUDesk | ICUDeskTop | — |\n     | HangSign | SignRod | — |\n     | 처방약장 | MedBox | 9 |\n     | PlayMat | ToyBlock / ToyBall | 6 |\n     | ArrivalMark | ArrivalMarkIn | — |\n\n     Singles: VitalMonitor, BedsideCabinet, Ventilator, Scale, AnesthesiaMachine, NumberDisplay, DirectoryKiosk, ORLight, Balloon, GuideLine, Plate, ExitSign. Dept Models (attr HospitalDept) → `H:Dept`.\n   - Models `Restroom_m|f|u` (any building) → room `R:restroom`; frame = `FloorTile.CFrame*CF(-w/2, -0.025, -d/2)` (entrance corner, door on v=0).\n   - GwB_Room parts → `R:<Kind>` (with their GwB_Unit ancestor).\n   - Hospital rooms come from the static table in §3, instantiated when the hospital Interior appears.\n   - Optional: GwangalliInfill fixtures → `O:<Name>`.\n   - Annex rooms (GB.Annex) are classified the same way, plus the overlap rule.\n3. **Settle**: an item is pending until its anchor part exists and its BasePart count has been stable for ~0.6 s (use catalog_summary nparts; give up waiting after 2 s of stability). Late `DescendantAdded` parts of an active item get hidden. If the anchor disappears, destroy + restore.\n4. **Main-system overlap**:\n   1. If any visible-by-design part (dump tr<1) already has Transparency ≥0.99 or LocalTransparencyModifier ≥0.99, skip (re-check every 10 s).\n   2. For items under AnnexRoom / main-system shop models, wait until the main folder (ctx.root child with attr ShopKey) exists or 4 s pass, then apply 1.\n   3. Optional precise registry (§10).\n5. **Culling** (0.35 s tick):\n   - focus = `ctx.focus()`, feet = focus.Y-3; same-storey gate `-2.5 < F.Y - feet < 8`.\n   - Horizontal distance to the footprint: build radius 46 / 34 / 24 (high / mid / low), drop at radius + 14.\n   - Nearest first, one build at a time, time-sliced.\n   - Caps: active items 70 / 45 / 24, parts 9000 / 5500 / 2600, reskin lights 8 / 5 / 2.\n   - Tier from `ctx.limits()` maxParts (2600 high, 2100 mid, 1300 low). Script attr `Enabled=false` turns everything off.\n   - Rooms activate when focus is inside the room box + 6 studs; at most 3 / 2 / 1 dressed rooms.\n6. **DecorMode pause**: skip or restore items of the local player's own unit while the camera is Scriptable (decor top-down) or a SelectionBox \"GhostBox\" exists. The server rebuilds placed furniture on every move (new instance).\n\n## 6. Builder contract (core ↔ RS_*.luau)\n- Modules `RS_<chunk>.luau` sit next to Kit / Props / Look / Interact. The core loads a static list with FindFirstChild + pcall(require).\n- Inside modules use literal `require(script.Parent:WaitForChild(\"Kit\"))` (offline bundler regex).\n- The core agent writes **RS_Common.luau** first (palette, hospital colours, cushion / fabric / chrome / screen-bezel / door-tween / ECG / text helpers).\n```lua\nlocal M = { items = {}, rooms = {} }\nM.items.sofa3 = {\n  hide = \"all\",          -- or \"none\" or function(part)->bool; keepers are never hidden\n  keep = { \"Screen\" },   -- always kept: GwB_Screen parts, prompt holders, LieSpot, Hit, Base\n  hideSeats = false,     -- Seat parts kept by default; true ONLY with an exact-pose cushion overlay\n                         -- (hospital WaitingChairs / Wheelchair / Bench seats are VISIBLE coloured Seats)\n  parts = { high = 220, mid = 140, low = 70 },\n  lights = 0,\n  build = function(K, I) end,\n}\nM.rooms[\"R:bath\"] = { build = function(K, V, R) end }\nreturn M\n```\n\n**Item frame** `K.cf = I.cf`:\n- Catalog convention: origin = footprint floor centre (mountY not included), **front = -Z**, catalog dump coordinates used as is.\n- For Props / T_clinic helpers whose pcf front is +Z, use `CFrame.Angles(0, math.pi, 0)` in K space (`I.pcf`); it flips X.\n\n**I** (item context):\n- Identity: id, model, def (ITEMS entry), w, d, h, mountY, W, cw, colors (rotated, [1] = primary), label, attrs snapshot, kind, public, unitId, shopId, placed, staging.\n- Context: ctx (\"hospital\" | \"unit\" | \"hotel\" | \"shop\" | \"lobby\" | \"annex\" | \"restroom\" | \"rooftop\" | \"outdoor\"), roomKind, dept, floor, tier (\"high\" | \"mid\" | \"low\" = K.detail).\n- Source parts: `part(name)`, `parts(name)`, `lcf(part)`, `seats` = { {part, lcf, top, index} }, `group` (hospital siblings).\n- Hospital: `B` = { cf = rec.cf, fy, ceil, toB(worldCF) }.\n- Hiding: `keep(part)`, `hide(part)`.\n- Live state: `on(attr, fn)` (watches On / Open / Channel / Fill / Busy / Done / Flush / Ding / Vend / Pour / Click: called now and on change, auto-disconnected), `onLight(fn)`, `onRpm(fn)`, `anim(fn(t, dt))` (≤15 Hz while within 30 studs), `now()` = workspace:GetServerTimeNow().\n\n**K** is the existing Kit.luau on a pseudo-venue `V = {cf=I.cf, keep={}, solid={}, byName={}, tables={}, x0..z1 = footprint+0.5, key=\"rs:\"..id, maxParts, maxLights, detail}`:\n- Every primitive works (box / wedge / cyl / vcyl / ball / ell / seg / bar / ring / rbox / slab / panel / disc / plate / text / light / group).\n- Props / Look / Interact work; the core fills `K.hostPts` with host prompt positions.\n- Parts beyond maxParts are ghosted, so honour K.detail.\n\nItem builder rules:\n1. Build first; the core hides originals after a successful build and restores on error.\n2. Stay inside the footprint + 0.3 (exceptions: kitchen_island stools at z -2.2, chairs around tables).\n3. Keep Screen parts visible and build bezels around their rectangle; nothing in front of the Screen's -Z face inside it.\n4. Seat cushion top = `I.seats[i].top ±0.1`; table tops at the same Y / XZ.\n5. Lamps: put the glowing shade where the original lamp part is; mirror `onLight`; no duplicate Light.\n6. Spin: the core hides Living's GwB_Blade children of hidden spin parts; animate your own from `onRpm`. Water: put the head / spout at the original head (the GwB_Stream stays).\n7. Hinged doors (fridge / wardrobe / microwave): make your own door group (`K:group`) and tween it on `on(\"Open\")` (fridge pulses 6 s) or `on(\"Ding\")`.\n8. Hospital text: read `TextLabel.Text` from the original SurfaceGui and re-letter it.\n9. No Seats, Humanoids, ClickDetectors, Sounds, welds or Constraints.\n10. Korean real-world look; neutral or fictional logos only (GW / 광안).\n\n**Room builders** `(K, V, R)`:\n- V = `Scan.fitRoom(model, spec)` with spec.cf = room floor centre, **-Z = back wall, +Z = entrance side**, and `spec.parts` = a pre-filtered list (room AABB + 1). V gives walls / spans / keep / solid; `V:wall` and Props.baseboard / wallTiles work.\n- R = { key, kind, label, ctx, unit, building, floor, cf, w, d, h, windows?, doors }.\n- Dress walls, ceilings and corners only; floor items go through `K:spot` and never in front of doors, beds or furniture (owners decorate homes).\n\n## 7. Room dressing plan\n**Hospital (H4)**\n- Ceilings:\n  - 600×600 텍스 grid overlay 0.03 below Ceiling with T-bar lines. Keep the LightPanels visible and add aluminium frames around them (no new Lights).\n  - Sprinklers, smoke detectors, PA speakers, return-air diffusers.\n  - OR / resus: laminar-flow panel.\n- Walls:\n  - Vinyl cove base; 벽 보호대 bumper rail (y 2.6-3.1); corridor 핸드레일 (y 2.9, gaps at doors via V:spans); corner guards.\n  - 손소독제 at every door; wall clocks; 소화전 (Hydrant) as a recessed cabinet; 비상구.\n  - Room signs replacing Plate visuals (room number, ward type, name slots, braille); infection / 낙상주의 posters; health posters.\n- Floors: inlaid GuideLines with arrows / labels; ArrivalMark as an epoxy hatch.\n- Per room:\n  - 원무과 / lobby: 번호표 발권기, per-창구 LED 대기번호 (NumberDisplay animated), acrylic guards, card terminals, 무인 수납기, brochure rack, 우산 비닐 포장기, 휠체어 보관대, 열화상 체온 kiosk, plants, TV bracket.\n  - 약국: 처방전 접수 / 수납 / 복약지도 signs, 약 봉투 baskets, shelving.\n  - ER: triage board, 응급실 현황판 (animated), stretcher bay, glove / sharps per bay, RESUS zone.\n  - 진료실: doctor desk set (2 monitors, 청진기, otoscope wall set, BP cuff), exam lamp, step stool, light box; peds decor.\n  - 영상의학과: \"촬영중\" lamp, lead door look, control window, PACS.\n  - 주사실: med fridge, sharps, tray.\n  - Wards: 사물함 + over-bed table + TV arm per bed, roller blinds, clock, door sign. VIP: wood accent wall, art, throws, fruit basket.\n  - ICU: central monitor wall, ceiling pendants, gown station.\n  - OR: scrub mirror / timer, X-ray viewer, OR clock, cabinets, pendants, sterile marks.\n  - Stations: EMR monitors, chart racks, phones, whiteboard, med cart.\n  - Day room: magazine rack, plants, cushions.\n  - Halls / lift halls: HangSign as edge-lit aluminium wayfinding boxes with pictograms (keep the text), floor plates, benches.\n- **Restrooms** (Restroom_* in every GwB building): 휴지걸이, coat hooks, sanitary bin (f), urinal screens (m), grab bars, LED mirror, soap / paper-towel dispensers, baby-changing table (f), floor drains, 청소 중 sign, vent grille at the `Vent` anchor, 🚹 / 🚺 plates.\n\n**Homes / hotels / offices (R1, from GwB_Room Kind; rooms touching z≈D usually have the windows)**\n- entry: mat, 우산꽂이, mirror.\n- bath: 수건걸이, 휴지걸이, shampoo shelf, 환풍기, 욕실화, drain.\n- kitchen: utensils on the counter top margin (수저통, 도마, 칼꽂이, 전기포트, 양념통), dish rack. Keep the cook prompt zone clear.\n- utility / veranda: 보일러 + pipes, laundry basket, detergent shelf, 빨래줄, plants.\n- bed / living: curtains or blinds on the window wall, art, clock, outlet / switch plates, AC wall unit (decor).\n- dining: pendant trim. dress / study / media: hangers, books, acoustic panels. hall: art.\n- hotel rooms: 카드키 전원 슬롯, 안내문, 금고, coffee tray, 가운 / 슬리퍼, DND hanger.\n- Lobbies / 관리사무소 / corridors: mailboxes, ParcelLocker reskin, notice boards, CCTV monitors.\n\n## 8. Budgets and quality targets\n- Parts per item (high / mid / low): beds 200 / 120 / 60, sofas 160 / 100 / 50, per seat 30 / 20 / 10, appliances 120 / 70 / 35, decor 60 / 35 / 15, CT / OR sets 350 / 200 / 100, room dressing ≤400 / 250 / 120 per room. Hospital 3F worst case ≈4-5k on high.\n- Lights: global 8 / 5 / 2, reusing the original lights. New lights only for vending / aquarium / fridge-open / monitor glow, nearest first.\n- Animations (≤15 Hz within 30 studs): ECG, fish, fan, drum, treadmill belt, TV LED, microwave countdown, wallpad clock, popcorn, rice-cooker steam, number displays.\n- Hospital palette: BLUE 36,110,190; TEAL 30,140,140; RED 206,34,44; GREEN 40,160,90; VINYL 214,224,222; WARDFLOOR 206,196,178; STEEL 196,200,204; CURTAIN 150,200,222; SEATBLUE 70,130,200. Use Look.luau materials.\n\n## 9. Offline workflow for chunk agents\n1. \"Before\" shots: `node feat/reskin/tools/preview_rs.js <id> --base --cams feat/reskin/tools/cams_item.json --out feat/reskin/shots/<id>_base`.\n2. The core agent provides `feat/reskin/tools/rs_sim.luau` (`luau rs_sim.luau -a <key> [cw] [label]`):\n   - bundle cat_mods + the client modules (gen.py style, incl. Reskin + RS_*);\n   - build the original with catscene ids;\n   - run the core path (`Reskin.buildOne`);\n   - write `feat/reskin/out/<key>.gen.json`, then render with `--gen`.\n   - Hospital keys need the Builder/Hospital piece functions (hbed / chairs / wheelchair / vitals / gasPanel / ivPole / cabinet / cart / curtain are pure Kit code) copied into the harness.\n3. Every RS file must pass `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/luau/luau-compile --binary <file>`.\n4. Temp studio: `flock .../scratchpad/.studio.lock timeout 1500 <cmd>` with build_studio_cabin.py + harness/bld.js at the §3 positions.\n5. T_clinic.luau (another agent's file, read-only) has reusable local helpers to copy into RS modules: hospitalBed, examCouch, ivPole + dripAnim, curtainRun, wheelchair, bpMachine, cart, drawerBank, sinkUnit, sharpsBox, medWasteBox, pedalBin, officeChair, rollStool, beamChairs, deskMonitor, keyboard, deskPhone, roomSign, hangSign, exitSign, hydrantBox, aedBox, sanitizerWall, handrail.\n\n## 10. Optional diff outside our files (Scan.luau owner: precise ownership registry)\n```diff\n@@ function Scan.hide(store, p)\n \tif store[p] then return end\n+\tScan.owner = Scan.owner or setmetatable({}, { __mode = \"k\" })\n+\tif Scan.owner[p] and Scan.owner[p] ~= store then return end -- another builder hides it\n+\tScan.owner[p] = store\n@@ function Scan.restore(store)\n \tfor p, rec in store do\n+\t\tif Scan.owner and Scan.owner[p] == store then Scan.owner[p] = nil end\n```\nWith it, the reskin checks `ctx.Scan.owner[part]` before claiming an item; otherwise the §5.4 heuristic applies. init.client.luau already loads \"Reskin\" through ADDONS, so no change is needed there.\n\nCoordination:\n- HospitalPlus (another agent) targets the STATIC 광안 메디컬 의원 (Workspace.Gwangalli.hospital, which the main system skips). 광안 종합병원 is entirely the Reskin's.\n- DecorPlus targets the life-game HomeUnits (GwangalliHomes), not GwB units, so there is no overlap.\n\n## 11. Chunk order\nH1, H2, H3, H4 (hospital), then C1 bath / public, C2 living, C3 kitchen / dining / bar, C4 bedroom, C5 office / media / music / gym / workshop, R1 home / hotel / office rooms, O1 outdoor (optional). The 67 catalog ItemIds are all assigned exactly once across C1-C5.",
 "chunks": [
  {
   "name": "H1_hospital_beds_patient",
   "items": [
    {
     "id": "H:HospitalBed",
     "what": "병상: real electric hospital bed reskin with variants chosen by Label",
     "notes": "Model HospitalBed (Kind bed, PrimaryPart Mattress = host prompt; LieSpot (0,2.95,0.4) never moved). Frame = BedFrame.CFrame*CF(0,-1.15,0), head +Z, footprint 3.4x6.95. Mattress top 2.2 (cushion top 2.2±0.1). Variants: '응급 베드 n' → ER stretcher bed (trolley base, side rails, IV socket, O2 bottle holder, red blanket 230,120,120); '소생실 침대' → resus bed (blanket 120,200,160); '처치실 침대', '진찰 침대', '소아 진찰 침대' → exam couch (vinyl, paper roll, adjustable back, step stool; peds pink 250,170,200); '물리치료 베드 n' → physio table (face hole, hot-pack, 240,180,120); '30xhoN', '40xhoN' → 3-motor ward bed (split rails, control pendant, footboard chart holder, brake castors, striped blue duvet 120,180,222); 'ICU n' → ICU bed (scale base, x-ray tray, air mattress, 200,220,230); '401호 VIP 1' → wood-panel head / foot boards, premium bedding 230,210,170. Hide all visible parts except Mattress? Mattress is the prompt holder (prompt shows regardless of transparency, so hiding is OK). Keep the LieSpot pose clear (no geometry above y 2.4 inside the mattress outline)."
    },
    {
     "id": "H:BedsideCabinet",
     "what": "병상 협탁 / 보호자 사물함 next to each ward bed",
     "notes": "Loose part 1.6x2.8x1.6 at bed*(2.6,1.4,2.6) (bed frame as above, so it sits at the bed's head-right corner). Real: ABS hospital bedside cabinet (drawer + door + top tray rim + towel bar), items on top (water bottle, tissue, cup). Optionally add a C-base over-bed table beside it."
    },
    {
     "id": "H:GasPanel",
     "what": "의료가스 헤드월 unit behind each bed",
     "notes": "Part 2.6x0.7x0.15 + 3 GasOutlet children (green / yellow / white) at bed*(0,5.2,3.6), facing -Z (into the room); ER bays at (-39.45,5.0,bz) yaw -90. Real: aluminium bed-head rail with O2 / air / vacuum outlets (Korean colour code), O2 flowmeter + humidifier bottle, suction regulator + canister, nurse-call button, reading-light strip (emissive, no Light), outlets, bed-number label."
    },
    {
     "id": "H:VitalMonitor",
     "what": "환자감시장치 patient monitor with animated waveforms",
     "notes": "Part 1.8x1.3x0.3 (big 3.4x2.2x0.3 in resus / ICU wall / OR) with a static SurfaceGui (♥ 72 SpO2 98% ...); faces -Z. Wards at bed*(-1.6,6.4,3.55) when monitor=true (304, 401, 402); ER (-39.4,6.6,bz-1.6). Reskin: bezel + wall arm + cable, green ECG / cyan pleth / white resp waves animated via I:anim, numeric HR / SpO2 / NIBP. Scan.hide disables the original gui."
    },
    {
     "id": "H:IVPole",
     "what": "수액 걸대 with infusion pump and drip",
     "notes": "Group IVPole (vcyl h 6.8 d 0.15 at floor) + IVBag (0.5x0.8x0.2 at y 6.3) + IVBase (1.4x0.15x1.4). Real: 5-leg castor base, chrome pole, 4 hooks, infusion pump with LCD, labelled bag + drip chamber (drip anim) + tubing toward the bed."
    },
    {
     "id": "H:Curtain",
     "what": "병상 칸막이 커튼 + ceiling track",
     "notes": "Group Curtain (box over span x0..x1 or z0..z1, y 0.8..ceil-0.6, 0.1 thick, Fabric 150,200,222 tr 0.15) + CurtainTrack (ceil-0.6..ceil-0.45). Spans: ER z 14/20/26/32/38 (x -39.6..-31.6) + x -31.6 (z 14..38); 301 z 9.5/16.5; 302 z 10.5; 303 x 2.1; 305/403 x 26; ICU x+3.5; 2F 정형 z 9.5; 내과 x 6.4. Real: pleated pastel curtain with a 50 cm mesh top band, hooks and gliders on an aluminium track; partly drawn (bunched) look. No prompt (host bed prompts within 6.5 studs)."
    },
    {
     "id": "H:Ventilator",
     "what": "인공호흡기 next to each ICU bed",
     "notes": "Part 1x4.2x1.4 at (x+1.9..x+2.9, z 5..6.4) per ICU bed (x -6/1/8/15, 4F). Real: rolling ventilator cart (touch screen with waveforms anim, humidifier, hose arm to the bed, gas hoses)."
    },
    {
     "id": "H:Wheelchair",
     "what": "휠체어 (lobby entrance)",
     "notes": "Model Wheelchair (Kind seat). Frame = Seat.CFrame*CF(0,-1.9,0), faces -Z. Seat is VISIBLE Fabric 1.8x0.25x1.8, top 2.025 → hideSeats=true with an exact cushion. Real: steel folding wheelchair (large rear wheels with spokes + push rims, front casters, armrests, swing-away footrests, push handles, brake levers). Positions 1F (21,3), (23,3)."
    },
    {
     "id": "H:WaitingChairs",
     "what": "병원 빔 의자 rows + single-chair variants by Label",
     "notes": "Model WaitingChairs (Kind seat; PrimaryPart = first Seat = prompt). Frame = Beam.CFrame*CF(0,-0.95,-0.2); n = number of Seats; px = -len/2+1.1+2.2(i-1); visible Seat top 1.95 (hideSeats=true, exact overlays); sitters face -Z. Variants: '대기 의자' (lobby / 2F rows of 4, blue 70,130,200) → 4-seat beam chairs with aluminium beam, upholstered seat / back, armrests between seats; '응급실 대기 의자' red; '약국 대기 의자' green; '스테이션 의자' n=1 → nurse task stool on castors; '보호자 의자' n=1 (wards) → 보호자 간이침대 / fold-out chair-bed, n=3 (peds) → kid-friendly chairs; '수액 의자 1/2' → 수액 리클라이너 with an IV arm + footrest; 'ICU 의자' n=2 stools."
    },
    {
     "id": "H:Bench",
     "what": "정문 광장 벤치 (exterior forecourt)",
     "notes": "Model Bench in Shell at forecourt x 26 / 32, z -4, yaw 180. Seat is visible WoodPlanks 5x0.3x1.6 at y 1.7 (top 1.85) + BenchBase concrete. Real: slatted wood bench with cast-aluminium legs and armrests. Active only when the focus is outside at street level (same-storey gate with the ground)."
    }
   ]
  },
  {
   "name": "H2_hospital_desks_reception",
   "items": [
    {
     "id": "H:Dept",
     "what": "ShopLife department desks (원무과, triage, 약국 투약구, 외래 접수, station desks)",
     "notes": "Dept Models (attr HospitalDept / ShopLifeKey; tag GwB_HospitalDept) contain FrontDesk (box 0..3.5) or Counter (약국), DeskTop marble 3.5..3.75, DeskBell (gold cyl y 3.85). R4: overlay only; desk top EXACTLY y 3.75 and the same XZ; keep DeskBell; never hide ShopFloor. Customer side = toward the waiting area (원무과 faces -z: counter x 0..22, z 21..23 with 4 windows at x 2.75/8.25/13.75/19.25; Plates '1 접수 창구' ... exist at y 2.3, z 20.85). Real: solid-surface counter with a raised transaction ledge, acrylic shields per 창구, card terminals, receipt printers, staff-side monitors, LED window numbers. ShopLife anchors sit above the desks (Workspace.GwangalliBuildingsShopLife/<key>/Anchors): no tall items on the top."
    },
    {
     "id": "H:StationCounter",
     "what": "간호사 스테이션 counters (ER island, 2F outpatient station)",
     "notes": "Group StationCounter (0..3.6) + StationTop (3.6..3.8): ER island pieces (-30..-20, 21..22), (-30..-20, 28..29), (-30..-29, 22..28) on 1F; 2F station box -36..-16, z 38..39.6 (0..3.5, top 3.75). Keep the top Y. Real: nurse station with a high ledge, solid-surface top, kick plate, LED band, EMR terminals (PCScreen items), chart racks, phones, label printer."
    },
    {
     "id": "H:ICUDesk",
     "what": "ICU central monitoring desk",
     "notes": "ICUDesk (-2..8, 18..19.6, 0..3.6) + ICUDeskTop (to 3.8), 4F. Real: curved monitoring console with a multi-monitor central station, keyboard trays, alarm light."
    },
    {
     "id": "H:InfoDesk",
     "what": "1F 안내 desk + hanging sign",
     "notes": "Group InfoDesk (round vcyl dia 4.4, h 3.6 at (2,·,5)), InfoDeskTop (dia 4.6, top 3.75), InfoSign (4x1.2x0.2 at y 6.4, double-sided 'ⓘ 안내 INFORMATION'), InfoPole. Real: curved white solid-surface info desk with blue LED reveal, brochure holders, monitor + phone, lit 안내 sign box."
    },
    {
     "id": "H:PCScreen",
     "what": "EMR 워크스테이션 on desks",
     "notes": "Group PCScreen (1.6x1.0x0.12, SurfaceGui 'EMR 환자 목록', faces -Z of its yaw) + PCStand + Keyboard at desk tops y 3.75-3.8 (원무과 x 2.75.., stations x -32/-26/-20, ICU x 0/3/6, dept desks). Real: thin-bezel monitor with an EMR table UI (SurfaceGui), keyboard, mouse, barcode scanner, card reader. Stay within the desk top margin (ShopLife anchors)."
    },
    {
     "id": "H:NumberDisplay",
     "what": "원무과 호출 번호 LED display",
     "notes": "Part 8x1.2x0.3 at (11, c-4.4, 22), text '🔔 접수 번호 0127 → 2번 창구'. Real: LED number board (red / green digits) per window; animate incrementing numbers (I:anim, every 6-10 s) with a 'ding' visual flash; ceiling-hung on rods."
    },
    {
     "id": "H:DirectoryKiosk",
     "what": "층별 안내 디지털 키오스크 (server prompt)",
     "notes": "Tag GwB_Hospital, attr HospitalKind=directory; the server adds a ProximityPrompt '층별 안내 보기' inside the part. Parts 1F (24,4,24.5) 3x8x0.6; lift halls (-12.6,3,34.6) 2.2x6x0.6 every floor. Hiding the visual is fine (the prompt keeps working); overlay at the same box: portrait LCD with floor map + floor list (RF 헬기장 ... 1F), brushed aluminium frame, hospital logo."
    },
    {
     "id": "H:SanitizerStand",
     "what": "손 소독 스탠드",
     "notes": "Group SanitizerStand (0.8x3.6x0.8 at (7,·,2.2)) + Sanitizer (0.7x0.6x0.5 at y 3.9, text '손 소독'). Real: stainless pedal-operated dispenser stand with bottle, drip tray, sign plate."
    },
    {
     "id": "H:MedShelf",
     "what": "약국 조제실 선반 (처방약장 + MedBox)",
     "notes": "Part '처방약장' (Wood 0.6 x 9 x 17 at x 38.9..39.5, z 1..18, inside the pharmacy dept Model) + 32 MedBox (0.4x1.2x1.6) on the floor model. Real: white melamine shelving with labelled bins / drawers, varied medicine boxes, bottles, 약 봉투 roll, tablet counter on the work surface."
    },
    {
     "id": "H:Cabinet",
     "what": "병원 수납장 (원무과 back wall, station cabinets, 주사실)",
     "notes": "Group Cabinet (w x h x 1.4 at cf*(0,h/2,0), front -Z) + Handle bars at z -0.72: 원무과 (11,26.6) 22x4 yaw 180; stations (-30,44.4) 10x6.4 and (-20,44.4) 8x6.4 (4F cabZ 42.8); 주사실 (36,16.6) 6x3.6. Real: medical storage cabinets (glass-door uppers with supplies, labelled drawers, file binders for 원무과)."
    },
    {
     "id": "H:Cart",
     "what": "병원 카트 by label",
     "notes": "Group Cart (body 2.4x3.0x1.6 at y 1.9) + CartTop + 3 Drawer lines; front text (-Z) = label. 'CRASH CART' (red, ER (-12.4,50) yaw -90): 5 colour-coded drawers, defibrillator on top, O2 tank, backboard, sharps; '제세동기' (white, (-12.4,54)): defib unit on a cart; '투약 카트' (3F (-14,42) yaw 90): med cart with many small drawers + laptop arm; '수술 기구' (OR (-29,52) steel): stainless instrument table / Mayo stand with instruments; nil label teal (OR (-29,47.6)): supply cart."
    }
   ]
  },
  {
   "name": "H3_hospital_medical_equipment",
   "items": [
    {
     "id": "H:CT",
     "what": "CT 스캐너 (영상의학과 2F)",
     "notes": "Group CTGantry (cyl d7.2 len 2.6 at (-30,4.6,10) yaw 90, text 'CT'), CTBore (d3.6), CTBase (-33..-27, 8.6..11.4, h 1.2), CTTableBase (-31.2..-28.8, 11.4..19, h 2.4), CTTable (-31.3..-28.7, z 6..19, 2.4..2.8). Real: ring gantry with a rounded cowl, front display panels, laser alignment lights, patient couch with cushion + head holder, foot pedals. Up to 350 parts on high."
    },
    {
     "id": "H:Xray",
     "what": "일반 X-ray 촬영대",
     "notes": "Group XrayTable (-38.6..-34.6, z 3..12, h 2.8), XrayColumn (-36.8..-36.4, 7..7.4, 2.8..8.6), XrayTube (-37.6..-35.6, 6.6..8.4, y 6.4..7.6). Real: floating-top table, column stand with tube head + collimator + handles, wall bucky stand, lead apron hooks."
    },
    {
     "id": "H:SurgicalLight",
     "what": "수술등 (소생실 + 수술실)",
     "notes": "Group SurgicalLight (Neon disc d3.2-3.4, 0.3 thick at ceil-1.7, with a SpotLight: keep the light) + SurgicalArm (vcyl 1.6 at ceil-0.8). Resus (-18,·,51) 1F; OR (-22,·,50) and (-22,·,54) 4F. Real: dual LED surgical light heads (dome with LED clusters, sterile handle) on articulated ceiling arms + central hub. Mirror the original spot light state if present."
    },
    {
     "id": "H:ORTable",
     "what": "수술대",
     "notes": "Group ORTableBase (-24..-20, 49..55, 0..3.2) + ORTable (-24.4..-19.6, 48..56, 3.2..3.7), 4F OR. Real: column-base surgical table (articulated top with gel pads, head section, arm boards, side rails, foot control), sterile drapes."
    },
    {
     "id": "H:AnesthesiaMachine",
     "what": "마취기",
     "notes": "Part (-16.4..-14, 47..49.4, h 5) 4F OR, with a big VitalMonitor beside it. Real: anesthesia workstation (vaporizers, flowmeters, ventilator screen anim, breathing circuit + bag, gas cylinders, drawers)."
    },
    {
     "id": "H:ParallelBar",
     "what": "재활 평행봉",
     "notes": "Group ParallelBar (x -9.6 / -6.4, y 3.4-3.6, z 3..15) + 6 BarPost, 2F rehab. Real: wooden platform base, height-adjustable chrome posts, padded bars, a mirror at one end, floor footprints."
    },
    {
     "id": "H:Scale",
     "what": "신장 · 체중계",
     "notes": "Part 'Scale' (11..13.4, 20..22.4, h 0.4) in 내과 2F. Real: column stadiometer scale with a digital display head and a sliding measuring arm."
    },
    {
     "id": "H:KidsCorner",
     "what": "키즈 코너 · 소아과 장난감",
     "notes": "PlayMat (Fabric -39.4..-33.6, 52..59.4, 2F back zone) + 6 ToyBlock (1.1 cubes) + ToyBall (balls d1.2 in 소아과 at y 0.6) + Balloon (d1.4 at ceil-2.6). Real: foam puzzle mat, low toy shelf, soft blocks, picture books, balloons with strings (sway anim)."
    },
    {
     "id": "H:WallCharts",
     "what": "벽 차트 · 경고 표지 (Plate texts)",
     "notes": "Plate parts whose text is: 'E\\nF P\\nT O Z\\nL P E D' (내과 eye chart, x -3.6 z 12 yaw -90) → Snellen light box; '📏 150...' (소아 x 31.6 z 14, 2x9) → height chart sticker; '💀 척추 모형 바른 자세!' (정형 x -21.6 z 20) → spine poster / model; '☢ 방사선 관리구역' (imaging) → yellow trefoil warning sign; 'SCRUB 손 씻기 5분' (OR) → scrub instruction panel; ER bay numbers. Read the text from the SurfaceGui; keep the meaning."
    },
    {
     "id": "H:ORLight",
     "what": "수술 중 표시등",
     "notes": "Neon part 4.6x0.8x0.2 at (-24, 9.1, 43.7) above the OR double door (4F), text '수술 중 IN OPERATION'. Real: recessed lightbox with a red glow panel and white lettering; keep the text."
    },
    {
     "id": "H:FloorMarks",
     "what": "응급실 바닥 유도선 · 구급차 인계 구역",
     "notes": "GuideLine boxes (red: (-30..-11, z 30.6..31.2) and (-11.6..-11, 31.2..43.6); green (-25.6..-24.4, z 1..30.6)) y 0.1-0.11; ArrivalMark (yellow -38.6..-30, 41..51) + ArrivalMarkIn (text '🚑 구급차 도착 · 환자 인계'). Real: inlaid vinyl wayfinding lines with chevrons and printed labels ('응급실', '소생실', '출구'); epoxy hatch zone with stencil text. Overlays ≤0.03 above."
    }
   ]
  },
  {
   "name": "H4_hospital_rooms_signage",
   "items": [
    {
     "id": "R:hosp_lobby",
     "what": "1F 로비 · 원무과 · 안내 room dressing",
     "notes": "Building-local -9.8..39.6, 0.4..28 (ceiling 12). Ceiling 텍스 grid + LightPanel frames; 번호표 발권기 by the entrance; per-창구 signage; 무인 수납기 ×2; brochure rack; 우산 비닐 포장기 at the main auto door (x 12, z 0: keep a 4x4 vestibule + door pocket clear); 휠체어 보관대 at (21-23, 3); 열화상 체온 kiosk; plants; TV bracket for the tv55 at (-9,8); health posters; hang-sign reskin '← 응급실 원무과 접수 ↑ 약국 →'."
    },
    {
     "id": "R:hosp_pharmacy",
     "what": "1F 약국 + 자판기 코너",
     "notes": "26..39.6, 0.4..19 + vending corner 25.8..39.6, 19..28. 처방전 접수 / 수납 / 복약지도 window signs over the Counter (x 34..35.6), 약 봉투 baskets, 조제실 door sign, waiting area poster; vending corner: recycle bins, cup holder, floor mat."
    },
    {
     "id": "R:hosp_er",
     "what": "1F 응급의료센터 (triage, bays, station, arrival)",
     "notes": "-39.6..-10.2, 0.4..44. Triage board + 중증도 분류 sign; 응급실 현황판 (patient status board, animated) near the island; stretcher parking bay; per bay glove box + sharps + sanitizer + wall suction / O2 (H1 GasPanel) + bay numbers; ambulance-door bumper rails at the -x wall z 42..50 (keep the auto-door pocket clear); 'RESUS →' arrows."
    },
    {
     "id": "R:hosp_resus_proc",
     "what": "1F 소생실 + 처치실",
     "notes": "소생실 -26..-10.2, 44..59.6 (glass walls, auto door x -18.5 on z 44): laminar ceiling panel, wall X-ray viewer, crash-cart parking marks, clock + timer. 처치실 -39.6..-26.2, 52..59.6 (slide door x -29.2): procedure light (decor), supply shelves, sink splash-back."
    },
    {
     "id": "R:hosp_imaging",
     "what": "2F 영상의학과",
     "notes": "-39.6..-22.2, 0.4..27.8 (door x -31 on z 28). '촬영중' red lamp above the door (corridor side y 8.6), lead-lined door look, control booth window strip + PACS desk, protective apron hooks, radiation sign."
    },
    {
     "id": "R:hosp_consult",
     "what": "2F 진료실 (정형 · 재활 / 내과 / 소아청소년과)",
     "notes": "정형 -21.8..-4.2; 내과 -3.8..13.8; 소아 14.2..31.8 (all z 0.4..27.8, doors x -13 / 5 / 23). Doctor desk set at the dept desk (2 monitors, 청진기, BP cuff, otoscope wall set), exam lamp, step stool, X-ray light box, sink accessories; rehab: mirror wall, wall bars, therapy balls, hot-pack cabinet; peds: wall stickers, toy shelf, colourful cushions."
    },
    {
     "id": "R:hosp_inject",
     "what": "2F 주사실 · 처치실",
     "notes": "32.2..39.6, 0.4..27.8 (door x 36, w 3.6). Medication fridge, sharps box, tourniquet / gauze tray on the cabinet, privacy curtain rail, IV hooks over the 수액 의자 (36,5) / (36,11)."
    },
    {
     "id": "R:hosp_outpatient_back",
     "what": "2F 외래 대기실 · 간호사 스테이션 · 키즈 코너",
     "notes": "-39.6..-9.8, 35.6..59.6. Station dressing (counter -36..-16, z 38..39.6), cabinets z 44.4, waiting area wall art / health posters / TV bracket (tv55 (-25,46.2)), kids corner mural near the PlayMat, water / vending niche (-11 / -14.6, 58.x)."
    },
    {
     "id": "R:hosp_ward",
     "what": "병실 6 / 4 / 2 / 1인실 (301-306, 402-404) + VIP 401",
     "notes": "Rooms z 0.4..27.8 between partitions; 3F x -40/-22/-4/8/20/32/40, 4F x -40/-22/-10/20/32/40 (ICU separate). Per bed: 개인 사물함 + over-bed table + TV arm (where no tv55) + bed-number plate; roller blinds on facade windows (z 0, y 2.8..8.6, ≥0.3 inside the glass); wall clock; door-side hand-sanitizer; bathroom-door-style storage. VIP 401: wood accent wall behind the bed, art, throws on the sofa3, fruit basket on the dining2, kitchenette shelf by the fridge."
    },
    {
     "id": "R:hosp_icu",
     "what": "4F 중환자실 ICU",
     "notes": "-9.8..19.8, 0.4..27.8 (glass front, auto door x 5 w 6). Central monitoring wall (big VitalMonitor (3,7.4,27.4) + animated screens), ceiling pendant columns per bed (decor), gown / glove station by the door, isolation signage, floor markings around the beds."
    },
    {
     "id": "R:hosp_or",
     "what": "4F 수술실 OR",
     "notes": "-39.6..-9.8, 44.2..59.6 (double door x -24 on z 44). Laminar-flow ceiling around the SurgicalLights, wall X-ray viewer, OR clock + elapsed timer, glass-front instrument cabinets, scrub sinks (washbasin at (-38.8, 52 / 56) are catalog items) with mirror / timer, sterile floor border, pendant columns."
    },
    {
     "id": "R:hosp_station_dayroom",
     "what": "3F / 4F 간호사 스테이션 + 3F 휴게실 DAY ROOM",
     "notes": "Stations -36..-16, z 38..39.6 (3F dept hospital_ward3; 4F hospital_ward4 desk z 38..39.6, cabinets 42.8): whiteboard with patient list, chart racks, phones, label printer; 3F day room z 50..59.6: magazine rack, plants, window-seat cushions, hang-sign 'DAY ROOM' (-26, c-1.6, 52)."
    },
    {
     "id": "R:hosp_hall",
     "what": "복도 · 엘리베이터 홀 (all floors)",
     "notes": "Hall z 28..35.6 (1F x -9.8..39.6, upper -39.6..39.6). Handrails (y 2.9) + bumper rails both sides with gaps at doors; corner guards; room ID signs (from Plate); 소화전 (Hydrant) reskin; CCTV dome; lift-hall floor plates; benches out of the walking line; ceiling grid + speaker / sprinkler pattern."
    },
    {
     "id": "H:HangSign",
     "what": "천장 안내 사인 (wayfinding) reskin",
     "notes": "Group HangSign (w x h x 0.2, double-sided SurfaceGui texts) + 2 SignRod. Examples: '원무과 접수 · 수납 · 서류 발급' (22x1.8), '응급실 접수 · 중증도 분류 TRIAGE' (red), 'NURSE STATION 간호사 스테이션' (teal), lift halls '2F 외래 진료 ← ...' (16x1.4), '🛗 엘리베이터 ...'. Real: edge-lit aluminium sign boxes with colour bands + pictograms + arrows; keep the original text and colour family (BLUE 36,110,190 / RED 206,34,44 / TEAL 30,140,140 / GREEN 40,160,90)."
    },
    {
     "id": "H:Plate",
     "what": "벽 명판 · 실명판 reskin",
     "notes": "Core.plate parts (w x h x 0.12, SurfaceGui front) on corridor walls y 8.2-8.5: room names ('301호 6인실', '중환자실 ICU 면회 12:00 · 18:00', '401호 VIP 특실', ...), restroom '🚹 남자' / '🚺 여자' (y 8.2, z 35.72). Real: acrylic room ID signs with a number band, ward type, 담당 slot, braille dots; restroom pictogram plates. Wall charts are H3."
    },
    {
     "id": "R:restroom",
     "what": "공용 화장실 dressing (Core.restroom, every GwB building)",
     "notes": "Model Restroom_m / Restroom_f / Restroom_u: frame = FloorTile.CFrame*CF(-w/2,-0.025,-d/2) (entrance corner; door at v=0; stalls along the far wall v=d, stallW 3.4, stallD 4.6, stall doors are Door models (skip)). Tile walls, Partition parts, toilets / urinals / washbasins / hand_dryer are catalog items (C1). Add: 휴지걸이 + coat hook per stall, sanitary bin (f), urinal privacy screens (m), grab bars in one stall, LED mirror strip over the basins, soap + paper-towel dispensers, baby-changing table (f), floor drains, 청소 중 sign, ceiling vent grille at the 'Vent' anchor (w/2, h-0.6, d/2). Used in the hospital (every floor), plaza floors, hotel lobby, venue buildings."
    }
   ]
  },
  {
   "name": "C1_bath_public_fixtures",
   "items": [
    {
     "id": "toilet",
     "what": "양변기 + 비데",
     "notes": "1.8x3x3.2 fixed, kind toilet (사용하기, sit then Flush=time after 4 s). Seat (0, top 1.60, z -0.1): cushion / seat-ring top 1.6±0.1. Tank at the back (+Z, y 1.4..3.2). Real: one-piece ceramic toilet with a soft-close seat + 비데 side control panel + nozzle, chrome flush button; animate a flush swirl / button press on Flush. Contexts: unit bath, public restroom (Restroom_* ancestor: back-to-wall concealed-tank look), hospital."
    },
    {
     "id": "urinal",
     "what": "소변기",
     "notes": "1.6x1.4x4.2 fixed, kind toilet (no seat). Bowl y 1.4..4.0 against the wall (+Z). Real: wall-hung ceramic urinal with an infrared sensor flush unit (chrome plate + dark sensor window), drain, optional privacy screen between urinals (Restroom_m has 2 at w-0.9, z 3.0 / 5.4)."
    },
    {
     "id": "washbasin",
     "what": "세면대 (home / public / hospital scrub)",
     "notes": "2.4x1.6x6 fixed, kind sink (손 씻기 3 s → On). Basin y 2.4..2.9 (top 2.9), pedestal, faucet; Spout water head (0, 3.42, 0.28) (the GwB_Stream stays); Mirror y 3.8..6.0 at z 0.72..0.8. Variants: unit bath → semi-pedestal basin + one-hole mixer + LED mirror cabinet + toothbrush cup; Restroom_* → counter basin with a sensor faucet + soap dispenser; hospital OR / 처치실 (I.ctx hospital, label-less, positions (-38.8, 52/56) 4F, (-27.6,59.2) 1F, (13.2,14) 2F) → stainless scrub sink with a gooseneck + elbow / knee lever."
    },
    {
     "id": "shower",
     "what": "샤워부스",
     "notes": "3.6x3.6x7.6 fixed, kind shower (On 10 s). Tray Slate 0..0.2, GlassFront z -1.8..-1.7 (tr 0.7), riser at z 1.6..1.7, Head water (0, 6.9, 1.0) + snd. Real: tempered-glass enclosure with a chrome hinge / handle + frame, 해바라기 rain head + hand shower on a slide bar + thermostatic mixer, corner shelf with bottles, trench drain, anti-slip tiles; steam / glass-fog hint while On."
    },
    {
     "id": "bathtub",
     "what": "욕조",
     "notes": "6x3x2.2 fixed, kind bathtub (반신욕: Fill 1 for 30 s, sit, On 12 s). Walls collide (keep the volume); Water tr 1; Head water (2.3, 2.55, 1.2); Seat (0, top 1.05, z 0.2) yaw 90. Real: acrylic built-in tub with a tiled apron, deck mixer + hand shower, headrest pillow, bath caddy; show a water surface + foam at y ~1.6 when Fill = 1."
    },
    {
     "id": "hand_dryer",
     "what": "핸드 드라이어",
     "notes": "Wall unit 1.2x0.8x1.4, mountY 3.6 (box y 3.6..5.0), kind dryer (3 s On). Real: jet-style hands-in dryer (top opening, drip tray, LED) or a compact white dryer; air-flow glow while On."
    },
    {
     "id": "jacuzzi",
     "what": "월풀 자쿠지 (penthouse)",
     "notes": "7 dia x 2.6, kind bathtub, starts Fill=1; Water (tr 0.35, PointLight: reuse it), Head water (0, 2.65, 3.15), 3 Seats top 1.75 at (0, z 1.2), (±1.6, -0.8); the shell collides. Real: acrylic spa with chrome jet rings, LED underwater, headrests, steps, wood deck surround; bubble anim while On."
    },
    {
     "id": "water_dispenser",
     "what": "냉온수기 / 정수기",
     "notes": "1.4x1.4x4 fixed, kind water (온수 받기: Pour=time; the cvs uses the 컵라면 flow). Body 0..3.2, water bottle 3.2..4, red Hot / blue Cold taps at y 1.9..2.1, z -0.75. Real: floor-standing hot / cold dispenser with an 18.9 L bottle (or a direct-pipe purifier), paper-cup holder on the side, drip tray, LED indicators; pour stream on Pour."
    },
    {
     "id": "vending",
     "what": "음료 자판기",
     "notes": "3.6x2.6x6.4 fixed, kind vending (Vend=time, 1,200원). Body solid; Window x -1.6..0.8, y 2.4..6.0 + SurfaceLight (reuse); 24 cans; Coin neon (1.0..1.6, 3.6..4.2); slot y 0.6..1.4; colourways red / blue. Real: Korean drink vending machine with a neutral brand header lightbox, 3-4 display tiers of dummy cans / PET bottles with price LEDs + selection buttons, bill / coin / T-money reader, return lever, pickup flap; drop anim on Vend."
    },
    {
     "id": "washer",
     "what": "드럼 세탁기",
     "notes": "2.4x2.4x3.4, kind washer (30 s, Drum Rpm 160). Drum spin part (0, 1.5, -1.29) dia 1.3. Real: front-load drum washer (chrome door ring, glass bowl door + handle, dial + LCD with remaining time while On, detergent drawer, adjustable feet); animate the drum / laundry with onRpm (hide Living's GwB_Blade)."
    },
    {
     "id": "drying_rack",
     "what": "빨래 건조대",
     "notes": "5x2.2x3.6, no kind / tag. Real: stainless A-frame folding rack with wings, towels, T-shirts, socks with clothespins, hangers."
    },
    {
     "id": "wallpad",
     "what": "월패드 (비디오폰)",
     "notes": "1.4x0.2x1.0, mountY 4.4 (y 4.4..5.4), kind wallpad (opens the UI). Screen part is GwB_Screen (Neon) → keep it visible, build the bezel around it. Real: 7-inch video wallpad (glossy black / white housing, buttons 통화 · 문열림 · 조명 · 가스 · 난방, speaker grille, clock UI optional)."
    }
   ]
  },
  {
   "name": "C2_living_room",
   "items": [
    {
     "id": "sofa3",
     "what": "패브릭 3인 소파",
     "notes": "8x3.4x3.2, kind seat, 4 colourways (grey / beige / navy / rust). Seats x -2.2 / 0 / 2.2, z -0.3, top 2.10 (cushion top 2.1±0.1). Hit 8x2x3.4. Hospital (304 / 401 / day rooms), lobbies, cafe, homes. Real: plush 3-seat sofa with piped seat cushions, back cushions with a slight recline, track arms, wooden legs, 2-3 throw pillows + a knit throw."
    },
    {
     "id": "armchair",
     "what": "라운지 암체어",
     "notes": "3.4 cube, kind seat, leather 3 colourways; Seat (0, top 2.15, z -0.25); metal swivel base. Real: leather club / barrel lounge chair with a swivel base, piping, seat cushion."
    },
    {
     "id": "coffee_table",
     "what": "원목 커피 테이블",
     "notes": "5x2.6x1.5, no tag; top y 1.5 (slab 1.2..1.5), shelf 0.35..0.5. Real: solid-wood table with a lower shelf; top props: tray, magazines, remote, coasters, small vase."
    },
    {
     "id": "tv55",
     "what": "55인치 TV + 거실장",
     "notes": "7x1.6x5.6, kind tv (On / Channel). KEEP Screen (x ±3.15, y 2.35..5.45, z 0..0.06, front face z=0; Living draws channels). PowerLed (2.95, 2.31): show red when off / white when On. Cabinet y 0..1.5. Real: slim-bezel 55\" TV on a stand / wall bracket over a low TV console (fluted doors, drawers), soundbar, set-top box, router LEDs, decor objects. Very common (hospital lobby / wards / day rooms)."
    },
    {
     "id": "tv_small",
     "what": "32인치 TV",
     "notes": "3.4x1.2x4.2, kind tv; KEEP Screen (x ±1.5, y 2.5..4.1, z ±0.02); cabinet 0..2.2. Real: 32\" TV with a stand on a storage cabinet, set-top box."
    },
    {
     "id": "floor_lamp",
     "what": "플로어 스탠드",
     "notes": "1.6x1.6x6.2, kind lamp (On toggles the PointLight in Shade at y 5.6). Mirror onLight for the shade glow; the light position is fixed at the centre top. Real: marble-base floor lamp with a linen drum shade (or tripod), pull switch."
    },
    {
     "id": "monstera",
     "what": "몬스테라 화분",
     "notes": "2x2x4.6, no tag, 3 pot colourways (white / brown / charcoal). Real: large monstera with split leaves on stems, moss pole, ceramic pot with soil + bark, saucer (Props.floorPlant monstera as a base, richer)."
    },
    {
     "id": "rug",
     "what": "라운드 러그",
     "notes": "7 dia, flat h 0.1, no tag, 3 colourways. Overlay ≤0.06 high: tufted round rug with a pattern ring / fringe."
    },
    {
     "id": "frame_art",
     "what": "광안대교 야경 액자",
     "notes": "3.6x0.3x2.6, mountY 3.6 (y 3.6..6.2), no tag; Art has a SurfaceGui '광안대교'. Real: gallery frame with a mat + glass; artwork = 광안대교 night (bridge silhouette, LED arch lines, city lights) built from thin parts / SurfaceGui frames."
    },
    {
     "id": "mood_light",
     "what": "무드등",
     "notes": "0.9x0.9x1.4, kind lamp; Globe lamp (PointLight colour = colourway pink / blue / warm). Real: moon lamp on a wooden stand or a mushroom lamp; glow follows onLight."
    },
    {
     "id": "aquarium",
     "what": "열대어 어항",
     "notes": "3.4x1.6x4.6, no tag; cabinet 0..2.4, Tank 2.4..4.4 (PointLight, snd bubbles), 5 Fish. Real: rimless glass tank on a cabinet, aquascape (rocks, driftwood, plants, sand), filter, LED lid, neon tetras / guppies swimming (I:anim), bubble column. Hospital lobby? No (hotel lobby, homes, annex vet)."
    },
    {
     "id": "bookshelf",
     "what": "5단 책장",
     "notes": "4x1.3x6.4, no tag, 60 parts, 3 colourways; shelves every 1.25. Real: 5-tier bookshelf with varied books (heights, leaning), binders, bookends, plant, photo frame, storage baskets (Props.row books)."
    },
    {
     "id": "shoe_rack",
     "what": "신발장",
     "notes": "3.2x1.3x3.6, no tag (entry). Real: 2-door shoe cabinet (louvred or handleless) with a top key tray, diffuser, mirror above (room dressing), shoes on a low open shelf."
    },
    {
     "id": "aircon",
     "what": "스탠드 에어컨",
     "notes": "1.9x1.5x6, kind aircon (On toggle). Vent (y 3.6..5.5, snd), Display neon y 2.9..3.2. Real: tall stand AC (white body, round micro-hole vent / louvre, LED display '24°' while On, control panel); louvre opens with On."
    },
    {
     "id": "fan",
     "what": "스탠드 선풍기",
     "notes": "1.8x1.8x4.4, kind fan (On + Hub Rpm 600). Hub (0, 3.4, -0.35) axis X; Guard dia 2.2. Real: 5-blade stand fan with a wire guard cage, round base with buttons, timer knob; blades from onRpm (hide Living's blades)."
    },
    {
     "id": "massage_chair",
     "what": "안마의자",
     "notes": "3x5x4.6, kind massage (sit + On 15 s). Seat (0, top 2.25, z 0.2); back ramp to (0, 4.6, 2.5); leg ramp to z -2.5. Real: full-body massage chair (sculpted shell, shoulder airbags, leg / foot module, armrest control tablet, headrest speakers, LED); a gentle anim while On."
    }
   ]
  },
  {
   "name": "C3_kitchen_dining_bar",
   "items": [
    {
     "id": "kitchen_counter",
     "what": "싱크대 (인덕션 · 후드 · 상부장)",
     "notes": "Fixed, width = attr W (5 / 6 / 7 / 8 / 14; Base is always 9!), d 2.2, h 9, kind cook (12 s On). Body 0..2.8 solid; Top 3.0; Sink x -W/2+1..-W/2+3 (+ Spout water at x -W/2+2, y 3.78, z 0.55); Cooktop W/2-3.4..W/2-0.6 + 2 Burners; Hood y 6.6..7.4 (snd vent_fan); upper cabinets y 6.2..8.6 over x -W/2..W/2-3.6, z 0..1.1; backsplash z 1.05..1.1, y 3..6.2; UnderLight surface lamp (off). Real: Korean apartment kitchen (handleless upper / lower cabinets, engineered-stone top, square sink + pull-out mixer, 3-zone induction with a red glow while On, slim hood with lights, tile backsplash, dishwasher panel, utensils, kettle)."
    },
    {
     "id": "fridge",
     "what": "양문형 냉장고",
     "notes": "3.2x2.6x6.4, kind fridge (Open = true for 6 s). Doors FridgeDoorL / R (Hinge -1 / +1, z -1.3..-1.1); Inside lamp (off) + snd. 3 colourways (silver / black / beige). Real: side-by-side fridge with panel doors, vertical bar handles, dispenser / home-bar on the left door, display; doors swing open on Open, revealing detailed shelves (김치통, 반찬통, milk, eggs, drinks) + an interior glow. Hospital 401 VIP."
    },
    {
     "id": "kimchi_fridge",
     "what": "스탠드형 김치냉장고",
     "notes": "2.4x2.4x5.8, kind fridge (Open pulse). 3 drawer fronts, Inside tr 1. Real: 4-door stand kimchi fridge (2 top doors + 2 drawers, display '김치 보관 중'); the top drawer slides out with kimchi containers on Open."
    },
    {
     "id": "minibar",
     "what": "미니 냉장고 (호텔 미니바)",
     "notes": "1.8x1.8x2.8, kind fridge; solid body, Inside tr 1. Real: hotel minibar (glass door with drinks lit inside) or a compact fridge with a handle; door swings on Open."
    },
    {
     "id": "microwave",
     "what": "전자레인지",
     "notes": "1.8x1.3x1.1, kind microwave (On 12 s, turntable Rpm 30, Ding = time). Usually at item y 3.05 on a kitchen counter (cvs at y 3.6). MwDoor Hinge -1, Inside lamp, Turntable spin Y, Clock neon. Real: black-glass door microwave with a touch panel, LED clock / countdown while On, interior light + plate turning; door pops open briefly on Ding."
    },
    {
     "id": "rice_cooker",
     "what": "전기 압력밥솥",
     "notes": "1.2x1.3x1.2, kind cook (On 12 s); on counters at y 3.05. Real: IH pressure rice cooker (rounded body, lid handle, steam valve with a puff anim while On, LED panel '취사 중' / '보온', paddle holder)."
    },
    {
     "id": "dining4",
     "what": "4인 원목 식탁 + 의자",
     "notes": "6x6.2x3, kind seat; table top 2.6..2.85 over x ±2.6, z ±1.6 (keep top 2.85 + XZ); 4 Seats at (±1.3, ±2.5) top 2.0 (z<0 chairs face +z, z>0 face -z). Real: Scandinavian oak table + upholstered dining chairs (backs away from the table), runner, placemats, fruit bowl."
    },
    {
     "id": "dining2",
     "what": "2인 카페 테이블",
     "notes": "3x5.4x3, kind seat; round top dia 2.6 at 2.625..2.775 (keep); Seats (0, top 2.0, z ±1.9). Real: marble round top on a black pedestal + bentwood chairs; small vase / sugar pot. Hospital 401."
    },
    {
     "id": "kitchen_island",
     "what": "아일랜드 식탁",
     "notes": "8x3x3.1, kind seat; body solid 8x2.9x2.5 (z -1..1.5); marble top 3.1; 3 stools OUTSIDE the footprint, Seats (x -2.4/0/2.4, top 2.30, z -2.2); Pendant lamp y 7.4..8 (on, reuse). Real: waterfall-marble island, counter stools, 3 pendant lights, fruit bowl / cookbook (penthouse)."
    },
    {
     "id": "bar_counter",
     "what": "홈바 카운터",
     "notes": "7x2.4x3.8, kind bar; body solid; marble top 3.5..3.8 (keep 3.8); neon strip lamp (on) at y 0.2..0.3 front. Real: fluted-wood bar front, brass foot rail, LED under-counter, top with a cocktail shaker, bottles, glasses, ice bucket."
    },
    {
     "id": "bar_stool",
     "what": "바 스툴",
     "notes": "1.8x1.8x3.2, kind seat; Seat (0, top 3.15). Real: swivel bar stool (leather seat with a low back, chrome column + foot ring, round base)."
    },
    {
     "id": "liquor_shelf",
     "what": "술장 (백바)",
     "notes": "7x1.4x7.6, no tag; 4 glass shelves x 10 bottles; glow lamp (on, reuse). Real: backlit glass shelving with LED strips, mirror back, bottle variety (whisky, wine, soju, gin, liqueurs), an overhead glass rack."
    },
    {
     "id": "popcorn_machine",
     "what": "팝콘 기계",
     "notes": "2x2x4.4, kind popcorn (8 s On). Base solid 0..2, glass Bowl 2..3.9. Real: retro red popcorn cart with a glass box, kettle (stir anim while On), popcorn heap, warming lamp, wheels."
    }
   ]
  },
  {
   "name": "C4_bedroom_dress",
   "items": [
    {
     "id": "bed_single",
     "what": "슈퍼싱글 침대",
     "notes": "4.2x7x4.2, kind bed (눕기 / 잠자기 at LieSpot (0, 2.85, 0.4); keep the space above the mattress open). Mattress top 2.1, duvet 2.3; headboard at +Z to y 4.2; 3 colourways (frame), duvet = colors[2]. Hit 4.2x2.1x7. Real: fabric headboard bed, quilted mattress, folded duvet, 1 pillow + cushion, bed runner."
    },
    {
     "id": "bed_queen",
     "what": "퀸 침대",
     "notes": "5.6x7.2x4.2, kind bed, LieSpot (0, 2.85, 0.4), 4 colourways, 2 pillows. Real: upholstered headboard + platform frame, hotel-like duvet + runner, 2-4 pillows."
    },
    {
     "id": "bed_king",
     "what": "킹 호텔식 침대",
     "notes": "6.6x7.4x4.4, kind bed, LieSpot (0, 2.85, 0.4), 3 colourways. Real: tall padded hotel headboard panel, crisp white duvet + runner, 4 pillows + cushions (hotel rooms / penthouse)."
    },
    {
     "id": "wardrobe",
     "what": "2도어 옷장",
     "notes": "4.4x2x7, kind wardrobe (Open toggles). WardrobeDoor1 / 2 Hinge -1 / +1 at z -1..-0.92; rail y 5.6; 8 clothes. Real: built-in style wardrobe (handles, inside rail with hangers + clothes, shelves, drawer); doors swing about 100° on Open (own door group)."
    },
    {
     "id": "vanity",
     "what": "화장대",
     "notes": "3.6x1.8x5.6, kind seat; desk 0..2.6 over z 0..1.8; Mirror z 1.58..1.6, y 2.8..5.4; stool Seat (0, top 1.90, z -0.8). Real: dressing table with a Hollywood LED-bulb mirror, drawers, cosmetics (bottles, brushes, palette), padded stool."
    },
    {
     "id": "desk",
     "what": "책상 + 의자",
     "notes": "4.4x4x3.6, kind seat; desk top 2.8 over z -0.2..2; DeskLamp spot (off) at (1.65, 4.0, 1.45); chair Seat (0, top 2.05, z -1.0) yaw 180 (faces the desk +Z). Real: study desk (laptop open, LED arm lamp, pencil cup, books, mouse pad) + mesh office chair at the exact seat."
    },
    {
     "id": "closet_wall",
     "what": "시스템 드레스룸 행거",
     "notes": "9x2.2x7.4, kind wardrobe (Open toggle, no doors). Back + 4 posts; rail y 5.8; 14 clothes; drawers 0.2..1.6. Real: aluminium system closet (shelves, double rails, drawers, shoes, bags, folded knits)."
    },
    {
     "id": "closet_island",
     "what": "드레스룸 아일랜드장",
     "notes": "4.6x2.6x3.2, no tag; body solid; glass top 3.0..3.2; 6 watches. Real: island cabinet with a glass-top display (watches, sunglasses, jewellery on velvet trays), drawers with handles."
    },
    {
     "id": "full_mirror",
     "what": "LED 전신거울",
     "notes": "2.6x0.6x6.6, kind dress; Mirror + LED lamp (on, reuse). Real: arched / rectangular floor mirror with an LED halo backlight and stand."
    },
    {
     "id": "sunbed",
     "what": "선베드 (루프탑)",
     "notes": "2.6x7x2.6, kind bed; LieSpot (0, 2.0, 0.2) tilted 70°; back ramp toward +Z. Rooftops (officetel / hotel Shell, Public). Real: aluminium / rattan lounger with a cushion, adjustable back, rear wheels, rolled towel; outdoors (ctx rooftop)."
    }
   ]
  },
  {
   "name": "C5_office_media_music_gym_workshop",
   "items": [
    {
     "id": "pc_desk",
     "what": "게이밍 PC 세트",
     "notes": "5x4.2x4.4, kind pc (sit + On). Top 2.8; KEEP Screen (x ±1.6, y 3.3..5.1, z 1.54..1.56); RGB / RGB2 (attr Rgb); tower glass; chair Seat (0, top 2.05, z -1.1). Real: 27\" monitor on an arm, RGB mechanical keyboard, XL mouse pad, tower with animated RGB fans, headset stand, racing-style gaming chair."
    },
    {
     "id": "gaming_setup",
     "what": "게이밍 PC 책상 (듀얼)",
     "notes": "5x2.6x5.2, kind pc. Top 2.6 (solid); KEEP 2 Screens ((-0.6, 3.65, 0.55) 2.0x1.3 and (1.4, 3.55, 0.55) 1.6x1.1); Keyboard; RGB strip; Tower; chair Seat (0, top 2.10, z -1.8). Real: dual-monitor gaming desk, LED backlight strip, speakers, figures, RGB tower."
    },
    {
     "id": "console_set",
     "what": "콘솔 게임 세트 (65인치)",
     "notes": "7x1.6x5.8, kind game. Cabinet 0..1.4; KEEP Screen (x ±3.15, y 2.15..5.65, z 0.05..0.1); Console; 2 Pads. Real: 65\" TV, white console tower (neutral brand), controllers on a charging dock, soundbar, game cases."
    },
    {
     "id": "projector_screen",
     "what": "홈시네마 스크린",
     "notes": "9x1x7.2, kind cinema. KEEP Screen 8.6x5.2 (y 1.6..6.8, z 0.2..0.3); casing y 6.8..7.2; 2 Speakers x ±4 (y 0..4); low stand. Real: motorised screen casing, floor-standing tower speakers, centre speaker + AV receiver on the stand, LED strip."
    },
    {
     "id": "recliner_row",
     "what": "전동 리클라이너 3인",
     "notes": "8.4x3.4x3.4, kind seat; Seats x -2.8 / 0 / 2.8, top 2.0, z -0.3; leather 2 colourways. Real: cinema recliners (cup holders in the armrests, power buttons, footrest seams), LED under-light."
    },
    {
     "id": "office_desk",
     "what": "듀얼 모니터 업무 책상",
     "notes": "6x2.8x5, kind office. Top 2.6; KEEP 2 Screens (±1.2, 3.65, 0.65) 2x1.3; Keyboard; chair Seat (0, top 2.10, z -1.95). Real: monitor arms, docked laptop, desk phone, documents tray, plant, mesh office chair (annex offices, home office room)."
    },
    {
     "id": "piano",
     "what": "업라이트 피아노",
     "notes": "5x2.2x4.4, kind instrument; body solid; Keys y 2.5..2.6, z -1.05..-0.4; bench Seat (0, top 1.90, z -1.85). Real: glossy black upright (fallboard, 88 keys with a correct black-key 2-3 pattern, 3 pedals, music stand with a score, cushioned bench, metronome)."
    },
    {
     "id": "drum_kit",
     "what": "드럼 세트",
     "notes": "5x4.4x4.6, kind instrument; kick, toms, snare, 2 cymbals; throne Seat (0, top 2.10, z -1.6). Real: full kit (kick with a logo head, 2 rack toms, floor tom, snare, hi-hat, crash, ride, pedals, stands)."
    },
    {
     "id": "guitar_stand",
     "what": "기타 + 스탠드",
     "notes": "1.6x1.6x4, kind instrument. Real: acoustic guitar (body with a sound hole + bridge, neck with frets, headstock + tuners, strings) on an A-frame stand."
    },
    {
     "id": "treadmill",
     "what": "러닝머신",
     "notes": "2.8x6x4.6, kind exercise (30 s On). Deck 0..0.6 collides (keep); Belt; KEEP Screen (0, 4.3, -2.51) 1.4x0.4; console / front at -Z. Real: motor hood, belt with side rails, handlebars with HR sensors, LCD console (speed / time), cup holder, safety key; belt scroll anim while On. Hospital rehab (-8, 21)."
    },
    {
     "id": "bench_press",
     "what": "벤치프레스 세트",
     "notes": "3x6x4.4, kind lift; bench y 1.2..1.6, Seat (0, top 1.95, z -0.6); uprights at z 1.6..1.8; bar y 3.6, z 1.7; 2 Plates. Real: power rack uprights + J-hooks, knurled olympic bar, bumper plates, collars, padded bench."
    },
    {
     "id": "punching_bag",
     "what": "스탠드 샌드백",
     "notes": "2.6x2.6x6.6, kind boxing (20 s On); base + Bag (h 4.4) solid. Real: free-standing water-base bag (leather with seams, logo band, spring neck); sway anim while On."
    },
    {
     "id": "dumbbell_rack",
     "what": "덤벨 랙",
     "notes": "4x1.6x3, kind lift; 2 tiers y 1.1 / 2.3, 5 dumbbells each. Real: steel rack with rubber hex dumbbells (chrome knurled handles, weight labels 2-20 kg)."
    },
    {
     "id": "workbench",
     "what": "정비 작업대",
     "notes": "7x2.6x3.4, kind workbench; top solid 2.8..3.1 (keep 3.1); 4 drawer fronts; Vise. Real: steel drawer cabinet with handles + butcher-block top, bench vise, laid-out tools, parts tray, work lamp."
    },
    {
     "id": "tool_wall",
     "what": "공구 타공판",
     "notes": "6x0.4x6, mountY 2.5 (board y 2.5..6.0), no tag. Real: pegboard with a hole grid, hooks, wrench set, screwdrivers, hammer, pliers, tape measure, small shelf."
    },
    {
     "id": "parts_shelf",
     "what": "부품 선반",
     "notes": "5x1.6x6, no tag; 4 shelves, 9 boxes. Real: steel angle shelving with labelled bins, car parts (brake discs, filters, oil cans), boxes, a tyre on the bottom."
    }
   ]
  },
  {
   "name": "R1_home_hotel_office_rooms",
   "items": [
    {
     "id": "R:entry",
     "what": "현관 dressing",
     "notes": "GwB_Room Kind entry (Label 현관 / 입구 / 현관 홀); room box from the Room_ part (unit frame; z=0 = entrance wall with the doorlock door). Door mat, 우산꽂이, full mirror on the wall, 센서등 trim, key tray (on shoe_rack if present). Keep the door swing clear."
    },
    {
     "id": "R:bath",
     "what": "욕실 dressing",
     "notes": "Kind bath (욕실 / 안방 욕실 / 공용 욕실 / 파우더룸). Tiles are fixed finishes. Add 수건걸이 + towels, 휴지걸이 near the toilet, corner shampoo shelf + bottles, 환풍기 grille on the ceiling, 욕실화 slippers by the door, floor drain, toothbrush cup. Avoid the toilet / basin / shower footprints."
    },
    {
     "id": "R:kitchen",
     "what": "주방 dressing",
     "notes": "Kind kitchen (주방 / 거실 · 주방 uses living). kitchen_counter (C3) owns the counter itself; room dressing adds wall items: magnets / memo, a hanging utensil rail, a wall clock, a small window curtain if on the far wall. Never on the counter top near the Base centre (cook prompt)."
    },
    {
     "id": "R:utility",
     "what": "다용도실 dressing",
     "notes": "Kind utility. Wall gas boiler with pipes, detergent shelf, laundry basket, mop + bucket, 빨래줄. The washer is C1."
    },
    {
     "id": "R:veranda",
     "what": "베란다 · 선룸 dressing",
     "notes": "Kind veranda. Plants in planters, a folding chair (K:spot), a clothes line, a window frame / sill accent (≥0.3 inside the glass)."
    },
    {
     "id": "R:bed",
     "what": "침실 dressing",
     "notes": "Kind bed (방 / 안방 / 작은방 / 침실 / 객실 / 게스트룸). Curtains or blinds on the window wall (rooms touching z≈unit D), wall art, outlet / switch plates (overlay Switch parts? keep them; plates around them only), a decorative AC wall unit high on a wall, a ceiling medallion around the LightPanel (no new lights)."
    },
    {
     "id": "R:living",
     "what": "거실 dressing",
     "notes": "Kind living. Curtains on the window wall, wall clock, art, plants (K:spot), outlet plates, AC wall unit, intercom area near the wallpad."
    },
    {
     "id": "R:dining",
     "what": "식사 공간 dressing",
     "notes": "Kind dining. Pendant trim around the LightPanel, wall art / shelf, sideboard decor only if the floor spot is free."
    },
    {
     "id": "R:dress",
     "what": "드레스룸 dressing",
     "notes": "Kind dress. Wall hooks, hats / bags on hooks, full-length mirror if absent, shoe shelf (K:spot)."
    },
    {
     "id": "R:study",
     "what": "서재 dressing",
     "notes": "Kind study. Wall bookshelf / floating shelves, certificate frames, desk-side bin (K:spot)."
    },
    {
     "id": "R:media",
     "what": "시네마룸 dressing",
     "notes": "Kind media. Acoustic wall panels, star-ceiling dots, ceiling projector mount (decor), dark carpet edge."
    },
    {
     "id": "R:hall",
     "what": "복도 (세대 내) dressing",
     "notes": "Kind hall. Art frames, console shelf, runner rug (thin, ≤0.04)."
    },
    {
     "id": "R:hotel_room",
     "what": "호텔 객실 extras",
     "notes": "Units with Hotel=true (templates hotel_standard / deluxe / suite). 카드키 전원 슬롯 next to the entrance (inside), 객실 안내문 / room-service menu, safe in the wardrobe, coffee / tea tray with a kettle, robe + slippers, DND hanger on the door handle side wall, luggage rack (K:spot)."
    },
    {
     "id": "R:lobby_common",
     "what": "건물 로비 · 관리사무소 · 공용 복도",
     "notes": "Floor_ corridor parts (FloorFinish / Ceiling / LightPanel / Hydrant / CCTV), Mailboxes + MailDoor, ParcelLocker (무인택배함), apartment 관리사무소 (desk + bookshelf catalog items), officetel 관리실 shop, plaza / hotel lobbies. Notice boards, CCTV monitor wall at the 관리실 desk, floor-number signs, handrail-free clean finishes (no door blocking), mailbox reskin overlay."
    }
   ]
  },
  {
   "name": "O1_outdoor_infill_optional",
   "items": [
    {
     "id": "O:Bench",
     "what": "공원 벤치 (Infill)",
     "notes": "OPTIONAL. Workspace.GwangalliInfill fixture Models (tag GwB_Fixture, Kind seat, Public). Read the geometry in ServerScriptService/GwangalliBuildings/Infill/Props (P.fixture). Exact-pose seat overlays only."
    },
    {
     "id": "O:Vending",
     "what": "공원 자판기",
     "notes": "OPTIONAL. Infill Model 'Vending' (Kind vending). Same as the C1 vending look."
    },
    {
     "id": "O:DrinkingFountain",
     "what": "음수대",
     "notes": "OPTIONAL. Kind fountain (물 마시기)."
    },
    {
     "id": "O:Jeongja",
     "what": "정자",
     "notes": "OPTIONAL. Kind seat; traditional pavilion reskin (roof tiles, dancheong trim)."
    },
    {
     "id": "O:Slide",
     "what": "미끄럼틀",
     "notes": "OPTIONAL. Kind slide (SlideEnd teleport part: keep)."
    },
    {
     "id": "O:Swings",
     "what": "그네",
     "notes": "OPTIONAL. Kind seat."
    },
    {
     "id": "O:Seesaw",
     "what": "시소",
     "notes": "OPTIONAL. Kind seat."
    },
    {
     "id": "O:SpringRider",
     "what": "흔들 말",
     "notes": "OPTIONAL. Kind seat."
    },
    {
     "id": "O:OutdoorGym",
     "what": "야외 운동기구",
     "notes": "OPTIONAL. Kind outdoorgym."
    },
    {
     "id": "O:Hoop",
     "what": "농구 골대",
     "notes": "OPTIONAL. Kind hoop (Shot attr)."
    },
    {
     "id": "O:PicnicTable",
     "what": "피크닉 테이블",
     "notes": "OPTIONAL. Kind seat; keep the table top + seats exact."
    },
    {
     "id": "O:JanggiTable",
     "what": "장기판 테이블",
     "notes": "OPTIONAL. Kind board."
    },
    {
     "id": "O:GardenPlot",
     "what": "텃밭",
     "notes": "OPTIONAL. Kind garden (물 주기)."
    }
   ]
  }
 ]
}
```
