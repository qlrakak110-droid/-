# building-interior-survey (wf_3248cdf4-7c8)

- status: completed
- failed agents (never finished, usually the usage limit): none

## survey:systems

```json
{
 "systems": [
  {
   "script": "ServerScriptService/GwangalliBuildings (Script) + Registry, Streaming, Builder/{Plan,Core,Shell,Units,Shops,Archetypes,District}",
   "role": "Procedural enterable-building system. It plans every building, builds the shells at start and streams interiors in near players.",
   "buildsAtRuntime": "Workspace.GwangalliBuildings/<BuildingId> (tag GwB_Building; attrs BuildingId, Kind, DisplayName, Floors, Wear, BoundsCF, BoundsSize) -> Shell (always present) + Interior (tag GwB_Interior) -> Floor_<label> -> Furnish (tag GwB_Furnish). The demo district sits at Config.DISTRICT_ORIGIN CFrame(4283.5,18.9,-200)*yaw(-90) on a 13-stud podium. It has 8 lots: apt(x-112,N), otl(-24,N), villa(33,N), oneroom(95,N), hotel(-135,S: 호텔 씨사이드 + 로열 카지노), plaza(-70,S: 광안 프라자 with 부산 돼지국밥 + 광안 공인중개사 on 1F and PC방/노래방/당구장 on 2F-4F), bbq(-20,S: 광안 숯불갈비 1F+2F) and cafe(18,S). Also built here: 광안 종합병원 (Shared.Hospital.SITE x-704 z1236 yaw90 groundY12.5) and the hideout 삼진전파사 (Shared.Hideout.SITE x-767.8 z348 yaw177). Shop templates (Builder/Shops T.*): cvs (GW25), gukbap, bbq, cafe, pcbang, karaoke, billiards, realtor, hotel_lobby, office. Each template = finishes() (ShopFloor/ShopCeiling/Lining boxes + a ceiling light grid) + counters + Point_<kind> anchors (tag GwB_ShopPoint, attrs ShopId/Point/ShopKind) + Seat parts (tag GwB_Seat) + Shops.staff static figures (no Humanoid). Interiors are parked in ServerStorage.GwangalliBuildingsParked when nobody is near.",
   "dependsOn": "Workspace attribute overrides GwB_<ConfigKey> (GwB_Origin, GwB_DEMO_DISTRICT, GwB_BuildAll, GwB_HOSPITAL, GwB_HIDEOUT, GwB_INFILL ...). Parts tagged GwB_Site: none in v7, so the demo district is built. Streaming constants: ACTIVATE 42, DEACTIVATE 85, PARK_AFTER 25 s, FURNISH_RADIUS 45, STREET_FURNISH 28, UNFURNISH_AFTER 30 s, BUILD_PARTS_PER_STEP 260. Workspace attribute GwB_Ready = true once started.",
   "interactions": "Doors (GwB_Door: swing/double/slide/auto/stall/fire/unit 도어락/room key card/shutter/staff). Real elevators (GwB_Elevator, GwB_ElevButton, GwB_ElevDisplay). Interact fixtures (GwB_Fixture: bed, tv, fridge, microwave, shower, toilet, sink, washer, pc, wallpad, massage, vending ...). ShopFlows: 편의점 GW25 shelf->basket->POS, 국밥 kiosk->number call, 숯불갈비 grill/flip, 카페 진동벨, PC방 tickets + games, 노래방 rooms + rhythm/voice mode, 당구 physics replay, 호텔 check-in key card, 부동산. Also Housing/Decor (free furniture placement in owned units), Royal (casino lounges, no gambling) and Needs.",
   "constraintsForNewProps": "The server creates, destroys and reparents everything here at runtime: interiors are parked, and storeys are unfurnished after 30 s. Bind to tags (GwB_Interior, GwB_Furnish, GwB_Shop, GwB_Unit) with GetInstanceAdded/RemovedSignal and AncestryChanged; never cache instances. Do not hide or move any GwB_*-tagged part: door leaves are animated client-side by DoorAnim from the Frame attribute, elevator cars move client-side, Screen/Spin/Water/Flicker/MotionLight parts are driven by GwangalliBuildingsClient.Living, and Light/Lamp by the Ambience LOD. Keep Point_* anchors and GwB_Seat seats reachable. Keep door swing volumes (GwB_Blocked) and the fronts of elevator doors clear. Player-owned homes (GwB_Unit with OwnerUserId, GwB_Placed furniture) must not get extra props."
  },
  {
   "script": "ServerScriptService/GwangalliBuildings/ShopLife (+ ShopLife/Scan, ShopLife/Bus)",
   "role": "Makes every existing walk-in shop of the static map work (order, sit, eat, pay, services) without changing its parts. This is the main gameplay layer for the 134 street shops, the 7 GwShop shops, the GS25 venue and Homeplus.",
   "buildsAtRuntime": "A Workspace.GwangalliBuildingsShopLife/<shopKey> Folder (attrs ShopKey, ShopName, ShopType, Accent, Calling/CallingAt, DisplayPath).\n\nAnchors/ holds invisible 1x1x1 Parts (CanCollide/CanQuery/CanTouch false). Each has one ProximityPrompt 'LifePrompt' (MaxActivationDistance 6.5, RequiresLineOfSight false, Exclusivity AlwaysShow, attr LifeKind). Anchor names: Cook, Display, Order, Pickup, Table_<n> (1.2 above the table top), MenuBoard, Restroom, Bin, Water, Shelf_<i>, HotWater, Microwave, ATM, Tap, Tank, Bell, Mailbox, Tester, Fitting, Chair, and NightLight_<i> (tag GwB_NightLight; pocha/grill only, 7.6 studs above the floor along the front).\n\nDishes/ holds: Dish_<id>; Setting_<id> (banchan + water cup + 'Sujeo' spoon at seat.spot offsets up to +-1.6 x, -0.1..1.05 z); a callbell at the table corner (max.X-0.35, max.Z-0.35); GrillPlate/OnGrill pieces (tag GwB_GrillPiece); and GwB_LifeSeat (an invisible Seat at seat top +0.1, used when the map seat is not a real Seat).\n\nMissing props are filled in: a FoodKit 'bin' (1.2x2.2x1.0) and a 'water' purifier (1.3x3.5x1.2), placed by Scan.freeSpot along the inside of the back wall. A shop activates when a player is within 75 studs and deactivates beyond 120.",
   "dependsOn": "Candidates (Scan.candidates):\n- any Model with children 'Interior' AND 'ShopFloor' (kind street/gwshop)\n- Models with 'Gondola_1' or 'OpenChiller' (venue)\n- tag GwShop\n\nFootprint: ShopBounds (GwShop) or ShopFloor; floorY = ShopFloor top.\n\nNames it reads (must keep):\n- Seats: ChairSeat, StoolSeat, Stool, Seat, Cushion, SeatCushion, StoolTop, BarStool.\n- Tables: TableTop, LowTableTop, LowTable, CommunalTable, Table, BarTop, WindowBar, Ledge, CounterTop, PassTop, BarCounter, PlasticTable/Top. A table needs area >= 1.2 and a top 1.2..5.5 above the floor. Seats link to it if they are 0.15..3.2 below the top and < 3.0 studs away (bar: 2.6).\n- Grills: GrillTable + Coals/CharcoalPot.\n- Ordering: OrderKiosk, KioskScreen, PosBase, CustomerDisplay, PosScreen, CashDeskTop, PosScreenBack, CardReader, Counter, FrontDesk, WorkDesk, 처방약장.\n- Kitchen: EspressoBody, GroupHead, TapPost, TapHandle, TapBar, CuttingBoard, FryBasket, Fryer, StockPot, Broth, Burner, KitchenPass, PassLedge, PassTray, DripTray, Hood, Grinder, GelatoTub, WaffleIron, SteamerCase.\n- Menus: Sign_메  뉴, Sign_MENU, MDBoard, PosterFrame, AFrameBack, XBannerBase.\n- Bins: Bin, RecycleBins, 쓰레기통, TrashBin. Water: WaterBottle, WaterPurifier, WaterDispenser.\n- Other stations: TankWater, HotWater, Microwave/MicrowaveWindow, ATMScreen, DeskBell, Mailboxes, TrayStation, Tester/TesterTable, Door_restroom/DoorLeaf.\n- Shelves: Gondola/Gondola_n, Fridge/FridgeDoor, OpenChiller, IceCreamChest/ChestGlass, HotBar, PastryCase, CaseGlass, BreadShelf, BreadCabinet, DisplayCase, WallRack, DisplayTable, Rack, WallBay, Hanger, WallShelf, Shelf, Product.\n- Door point: AutoDoor / AutoDoor_GS25 / an AutoDoor-tagged model. Also ShopBackWall, GwShopPoint parts (PointKind order/counter/fitting/chair) and GwShopTable models (TableTop/Top + TrayPoint).\n\nA Seat with attribute Sittable=false is skipped.\n\nOverrides: Model attrs ShopLife=false, ShopLifeType, ShopLifeMenu, ShopLifeKey; container attr ShopLifeRoot=false.\n\nShop key = '<model name>@<round x>,<round z>' of the floor frame.\n\nBus = ServerStorage.GwangalliShopLife (Event/Request), used by GwangalliShopService and the NPC systems.",
   "interactions": "Prompts: 앉기 (table), 주문하기, 키오스크 주문, 계산하기, 바에서 주문, 픽업하기, 메뉴판 보기, 화장실 이용, 버리기, 물 따르기, 고르기 (shelves), 온수 붓기, 데우기, 잔액 조회 (ATM), 직접 따라보기 (tap pour minigame), 수조에서 고르기, 벨 누르기, 우편함 확인, 테스터 써보기, 입어 보기, 앉아서 스타일 고르기.\n\nSeated HUD: 먹기, 뒤집기, 짠, 추가 주문, 계산.\n\nDine-and-dash is auto-paid after 10 s; N빵/treat go through the Together bridge.\n\nCharacter attrs GwB_Act/GwB_ActBeat/GwB_Utensil/GwB_Hold* drive ShopAnim on every client.",
   "constraintsForNewProps": "Scan runs on the SERVER, so local client changes never break the classification. But every runtime anchor and dish position is computed from the ORIGINAL parts: players sit at the original seat-top CFrame, dishes land at the TableTop top Y around seat.spot, and prompts float over the original counters.\n\nA client re-skin must therefore keep:\n- every seat's top within ~0.1 stud, facing the same table;\n- every table top at the same Y and XZ extent. Dishes spread +-1.6 x 1.05 studs around each seat spot and the bell sits at the far corner, so put no decorative props on table tops except a narrow centre strip on large tables;\n- counter, pass and POS tops at their Y;\n- the back-wall strip where the bin / water purifier may spawn free (back wall inner side, 0.12..0.45 of the width either side of centre);\n- a 7-stud reach around every Anchors part uncluttered.\n\nDo not name new parts like the names above. Scan only reads server-side parts, so client parts are invisible to it (even on a future rescan or Annex addShop), but keep the names distinct anyway, e.g. prefix 'GwID_'."
  },
  {
   "script": "ServerScriptService/GwangalliShopService (Script)",
   "role": "Shop staff that greet you, take your order and SERVE it, through the ShopLife bus.",
   "buildsAtRuntime": "One waiter rig per open table shop in workspace.GwangalliShopStaff (tag GwShopStaff; NPC.luau attribute contract NpcId/NpcKind/NpcLeg/NpcYaw/NpcAct/NpcEmote; GwangalliNPCLooks body). The waiter walks pass -> table with a tray via PathfindingService (WALK 8.5 studs/s) and sets staffMode {serve=true}. Also speech bubbles.",
   "dependsOn": "The ServerStorage.GwangalliShopLife bus; counter rigs within STAFF_R 32 of the pass/order point; a SERVE_TIMEOUT 25 s fallback.",
   "interactions": "Greeting on entry, 'N번 손님' pickup calls, response to the 호출벨, serving the dish, goodbye lines.",
   "constraintsForNewProps": "The waiter's path is computed on server geometry and then interpolated on clients along the NpcLeg polyline, so the waiter will walk through any client props in the aisle between the kitchen pass and the tables. Keep aisles of 2.5+ studs from the pass/counter to every table free of new geometry (rugs and floor decals are fine)."
  },
  {
   "script": "ServerScriptService/GwangalliGameplay/ShopStaff (feature module)",
   "role": "A staff NPC behind the counter of every storefront (~400 sites) near players.",
   "buildsAtRuntime": "Rigs in workspace.GwangalliShopStaff (tag GwShopStaff, NpcKind 'shop'). They exist only within ON_R 150 studs (removed beyond OFF_R 180), at most MAX_ACTIVE 36, nearest first. Each has a BillboardGui bubble on the Head and a ProximityPrompt '말 걸기', switches work acts (teller/wipe/typing/cup/cook ...) every 20-40 s, and says '어서 오세요' within GREET_R 11.",
   "dependsOn": "A site = a Model with a ShopFloor child and a cashier anchor: the first of PosBase, CashierPanel, OrderKiosk, FrontDesk, BackBar, POS, BarCounter, 바 카운터, 안내 · 접수 카운터, ShopCounter-tagged, Counter. Loose landmark counters also count (PosBase, POS, BarCounter, FrontDesk, CashierPanel ...).\n\nStand spot: from the counter, away from the nearest AutoDoor/Door/ShopWindow (or toward ShopBackWall), at counter half-depth + 1.7 / 2.6 / 3.6 studs, with side offsets 0, +-1.4, +-2.4. It needs a free 1.6x2.6x1.6 box at chest height. Blockers are CanCollide parts with Transparency < 0.95 whose names are not Pos/Counter/Display/Screen/Kiosk/Panel/Register/Till/Card/Band/Desk/Bar.\n\nSkipped: counters with a GwShopClerk/VenueStaff/HospitalStaff/GarageStaff/GwInteractRig within 9 studs, and the JOB_SITES 스타벅스 광안리점 / GS25 광안리점.",
   "interactions": "말 걸기 (talk lines per shop kind), greeting, looking at the player.",
   "constraintsForNewProps": "The spot is chosen on the server, so a client prop behind the counter will intersect the rig. In every shop with a cashier anchor, keep a 2x3-stud standing zone free from the counter's back edge to ~4 studs behind it (the strip between counter and back wall). No tall props there; back-bar shelving must hug the back wall."
  },
  {
   "script": "ServerScriptService/GwangalliStaticNpcSkins (Script)",
   "role": "Gives the static block NPC figures saved in the map (의사 김선생, 분식 이모, 트레이너 김코치, 볼링장 직원, the GwShopClerk rigs ...) a real avatar look.",
   "buildsAtRuntime": "Hides the map figure's body parts and stands an anchored, non-colliding GwangalliAvatarPool clone in the same spot.",
   "dependsOn": "Figures found by name/part. Workspace attribute GwangalliStaticNpcSkins=false disables it.",
   "interactions": "None of its own; the figure's name tag, bubbles and prompts keep working.",
   "constraintsForNewProps": "Do not hide, move or overlap the static NPC figures (GwShopClerk models in Workspace.Gwangalli.shops.*.Interior, VenueStaff, hospital/garage Staff) or their avatar stand-ins. Keep 2 studs around them clear."
  },
  {
   "script": "ServerScriptService/GwangalliBuildings/Annex (+ Annex/Rooms) / client AnnexClient",
   "role": "Gives every building the map shows only from the street (facade + glass + sign) an inside: storefront rooms and whole buildings, built OFF the map.",
   "buildsAtRuntime": "Door prompts: 'AnnexPrompt' (attr AnnexDoor) in Workspace.GwangalliBuildings/AnnexDoors, only within NEAR 70 studs (FAR 110), PROMPT_DIST 8.\n\nInstance slots: ORIGIN (-9600,3000,-9600) + (col*560, 0, row*560), 16 cols, MAX_LIVE 6, each kept 150 s after the last person leaves.\n\nStorefront = Rooms.build ShopLife room. Sizes: table 38x30, kiosk 32x26, counter 28x24, pick 32x26, service 30x24 studs. It uses the names ShopFloor, CounterTop, PosBase, OrderKiosk, TableTop+ChairSeat, GrillTable+Coals, PlasticTable+Top+StoolSeat, BarTop+BarStool, StockPot, Fryer, EspressoBody, TapPost, TankWater, CuttingBoard, Gondola_n, Fridge, HotWater, Microwave, PastryCase, WallRack, FrontDesk, DeskBell, ATMScreen, Door_restroom/DoorLeaf, MDBoard, WaterPurifier and TrashBin. Model attrs: ShopLifeType/ShopLifeMenu/ShopLifeKey/AnnexRoom/DoorX. A little fake street sits outside the glass. The room is registered with ShopLife.addShop.\n\nBuilding = a Builder archetype (apartment/officetel/villa/oneroom/hotel/plaza/venue) at the slot, with an AnnexGround pad (Plaza/Lawn + invisible 40-stud Bound walls).\n\nExit prompts: AnnexExit '나가기'.",
   "dependsOn": "Buildings are indexed by MapIndex. Eligible if height >= 14, footprint >= 380, not park/transit, no SKIP_WORDS, not inside HOST_VENUES (bowling, club, karaoke, pcbang, convenience, arcade, hospital, garage, delivery, shops), and attrs Annex~=false / AnnexKind~='none'.\n\nDoors are found by part name: Door/GlassDoor/ShopDoor (shop), LobbyDoor/EntranceDoor/DoorLeaf/FrontDoor (main), BackDoor/ServiceDoor (back). Glass: ShopGlass/ShopWindow. Signs: Sign_<text> (Sign_2F <name> for upper floors). Doors inside ShopLife walk-in shops, AutoDoor models and cars are skipped.\n\nPlayer attrs while inside: GwB_AnnexPos/GwB_AnnexName/GwB_AnnexInst/GwB_AnnexKey.",
   "interactions": "들어가기 / 층별 안내 directory / 나가기 chip / loading fade. Inside: all ShopLife flows, Interact furniture (Public=true), Builder buildings with elevators, homes to tour, hotel rooms.",
   "constraintsForNewProps": "Interiors at y~3000 are created and destroyed on demand. Detect them by the player's GwB_AnnexInst attribute or the Model attribute AnnexRoom=true under Workspace.GwangalliBuildings, and build detail only while the player is inside.\n\nNever touch the Bound walls, the AnnexExit anchors (inside the glass door: doorCF*(0,-1,-2.2); outside: doorCF*(0,-1,+2.6)) or the spawn spot (DoorX, 3.2, 3.5).\n\nOn the map side, keep storefront Door/ShopDoor/LobbyDoor parts visible and the area in front of them free; the prompt sits 2.4 studs outside the door, 3 studs up."
  },
  {
   "script": "ServerScriptService/GwangalliBuildings/Interact, Doors, Elevators, Decor, Housing, HostBridge, Residence, Royal, Hospital, Hideout, Infill (+Kinds/Lots/Props), MapIndex",
   "role": "Services of the building system: fixtures, doors, elevators, 내집마련, decor, 로열 카지노, 광안 종합병원, the weapon dealer's hideout, and lawn infill with 근린상가.",
   "buildsAtRuntime": "Infill: Workspace.GwangalliInfill, one Model per lot (놀이터, 정자, 체육시설, 농구장, 주말농장, 주차장, 푸드트럭 광장, 쌈지공원, 분리수거장, 자판기 쉼터) plus 근린상가 shells whose ShopDoor/LobbyDoor/Sign_ parts Annex reads.\n\nHospital: the building + Workspace.GwangalliHospital points (tag HospitalPoint: AmbulanceSpawn, EmergencyEntrance, TreatmentPoint ...).\n\nHideout: Workspace.GwangalliWeaponDealer points (tag WeaponDealerPoint: WeaponDealerSpawn, WeaponDealerInteractionPoint, WeaponShopCounter, WeaponDealerExitPoint, WeaponDealerEntrance).\n\nResidence: renames 호텔 바다 (attrs GwB_DisplayName, AnnexKind='officetel').\n\nDestinations go in Workspace.GwangalliBuildingsDestinations.",
   "dependsOn": "Interact: fixture Models tagged GwB_Fixture (attrs Kind, FixtureId, UnitId?, ShopId?, Label, Public). The prompt is anchored on the model's FIRST part. State attributes: On/Channel/Open/Busy/Fill.\n\nDoors: tag GwB_Door, attrs Open/OpenDir/OpenT/Locked/Ring; the server only toggles leaf collision.\n\nElevators: attrs Stops/StopY/Pos/Seg*/Door/Calls on the Model.\n\nDecor: server-side GetPartBoundsInBox inside the unit.",
   "interactions": "Fixture prompts (눕기, 잠자기, 켜기, 꺼내 먹기, 데우기, 샤워, 세탁, 운동하기, 슛 던지기 ...), door toggles/doorbells/locks, elevator hall/car calls, hospital admit/treat, the hideout counter.",
   "constraintsForNewProps": "Never reorder or prepend parts inside a GwB_Fixture model (the prompt uses the first part). Never hide fixture parts the client animates. Keep the hospital/hideout point parts (invisible) and the stretcher routes free. Don't add props inside owned units: Decor validates only against server geometry, so client props would overlap the player's furniture."
  },
  {
   "script": "ServerScriptService/GwangalliBuildings/StreetSigns + ServerScriptService/GwangalliUpperSigns",
   "role": "Restyles the map's Sign_* boards as a real Korean street and adds sign hardware.",
   "buildsAtRuntime": "Workspace.GwangalliSignage: 갈바 frames, neon rims (NightNeon), pavement wash lights (CityLight), LED strips (LEDScreen), 유리창 시트지 (window film on storefront glass), 입간판, 돌출 간판, 층별 세로 간판, 포차 천막 + 전구 (NearLOD models), and UpperTenants 2F/3F box signs. All of it is CanQuery=false. Workspace attr GwB_SIGNAGE=false reverts it; GwB_Signage is set when done.",
   "dependsOn": "Parts named Sign_* with a SurfaceGui; block names for the street zones; SignStyles.classify (the same classifier gives shops their type).",
   "interactions": "None (decorative).",
   "constraintsForNewProps": "Do not cover or change ShopWindow/ShopGlass parts or the 시트지 film quads on them. Keep the 1-2 stud strip inside the front glass free of tall props so the window film and menu posters read. 입간판 stand outside the door, so put no props in the doorway."
  },
  {
   "script": "ServerScriptService/GwangalliEnvironment (sections 4-5) + client GwangalliWorld/DetailLOD + GwangalliWorld/Util.setHidden",
   "role": "Near-only detail LOD for every map interior.",
   "buildsAtRuntime": "Server discovery tags (Workspace already has GwDiscoverTagged=true in v7) and the arrive-hidden pass.\n\nArrive-hidden pass: each eligible outermost NearLOD Model inside Workspace.Gwangalli gets Transparency=1 on all parts (the shown value is kept in part attr GwT; model attr GwTMix) and attr GwArrive=true. Eligible = anchored parts only; no tagged/attributed parts, lights, guis, effects, prompts, scripts, seats or humanoids; not in homes/npcnav/zones/RoomDepth/vehicles. Workspace GwArriveReady=true when done.\n\nClients then show near models within DetailLOD.Radius (low 70 / mid 100 / high 150 / saver 48, + 12 hysteresis), at 3 Hz, with 200/400/800 writes per frame. Zone models (LOD='zone', LODRadius, LODCenter, tag ZoneLOD) are hidden as a whole beyond their radius.",
   "dependsOn": "Shop interiors are Models named Interior/NearDetail/ShopDetail/Detail with attr LOD='near' and tag NearLOD (269 'Interior' models, 2589 NearDetail; ModelStreamingMode Atomic). The GwShop Interiors, GS25, karaoke Booth_NN, the PC hall, the arcade, the club rooms and the bowling alley are ZoneLOD.",
   "interactions": "None.",
   "constraintsForNewProps": "To hide a crude map part, use the property DetailLOD does NOT drive for that root:\n- Inside a GwArrive=true root, DetailLOD writes Transparency (0/GwT when shown, 1 when hidden), so hide with LocalTransparencyModifier=1.\n- Inside a non-arrive NearLOD/ZoneLOD root, it writes LocalTransparencyModifier, so hide with a local Transparency=1, and disable the part's SurfaceGuis/Decals yourself.\n\nRe-apply on every stream-in (Atomic models come back as new instances) and whenever the root's GwHideState attribute changes. Don't reparent streamed instances (it breaks streaming). Your own detail should follow the same radius, or tag your Models NearLOD locally so DetailLOD manages them."
  },
  {
   "script": "Client GwangalliIndoorLight (LocalScript)",
   "role": "Dims indoor lights and adds indoor eye adaptation.",
   "buildsAtRuntime": "Lighting.GwangalliIndoorGrade ColorCorrectionEffect (indoor Brightness -0.06, Contrast +0.07).",
   "dependsOn": "Every PointLight/SpotLight/SurfaceLight in Workspace (via DescendantAdded). If Brightness >= 0.9 and an upward raycast hits a roof: Brightness x0.55, Range capped at 18, attr GwIndoorDim=<old>. Opt-out: set the light's attr GwIndoorDim before parenting, or give an ancestor Model attr GwKeepBright=true. Parents named LampHead/SignFrame/Lantern/... are skipped. Indoor test: a camera ray up 30 studs hits a part with Transparency <= 0.6, and >= 3 of 4 horizontal 28-stud rays hit.",
   "interactions": "None.",
   "constraintsForNewProps": "New lights are dimmed x0.55 unless you set GwIndoorDim (e.g. 0) first. Do not make ceilings Transparency > 0.6, or the indoor grade switches off: overlay ceiling skins instead of hiding ShopCeiling."
  },
  {
   "script": "Client GwangalliWorld/Lights, Signage, NightWindows, MobileQuality; client GwangalliTextures",
   "role": "Light budgets, window glass day/night, mobile switches and runtime surface textures.",
   "buildsAtRuntime": "Lights: InteriorLight-tagged (AlwaysOn) lights are kept on only for the nearest 6/16/24 within 90/140/160 studs (low/mid/high); saver 3 within 60.\n\nSignage/NightWindows own every write to glass named Window/RoomGlass and to glass tagged NightWindow.\n\nMobileQuality hides RoomDepth models on low (Config.Mobile.HideRoomDepth) and scales SurfaceGui MaxDistance (x0.6 on low).\n\nGwangalliTextures adds Texture children 'GwangalliTex' to the faces of plain anchored block Parts (including ShopBackWall, ShopPartition, Partition, Ceiling, Floor ...) within 20/40/50 studs indoors.",
   "dependsOn": "Tags InteriorLight, CityLight, NightWindow, NightNeon, NeonTube, NightGlow, RoomDepth, RoomGlass, Window, GwSurfaceGui. GwangalliTextures skips parts under an ancestor with attr LOD='near' or OpenOffset, Humanoid models, and its EXCLUDE_TAGS (NearLOD, RoomDepth, EditorOnly, Window, AutoDoor, InteriorLight, CityLight ...).",
   "interactions": "None.",
   "constraintsForNewProps": "Never write Material/Color/Transparency of window glass. ShopWindow is safe to leave alone; Window/RoomGlass are owned by these systems. Budget your own lights (Lights does not count them). If you hide a map wall with Transparency, the GwangalliTex textures on it stay visible, so prefer overlays. Put your root under a Folder with attr LOD='near' if you do not want GwangalliTextures to texture your parts."
  },
  {
   "script": "ServerScriptService/GwangalliDoors + client GwangalliDoorsClient",
   "role": "Automatic sliding doors of every storefront (166 AutoDoor models).",
   "buildsAtRuntime": "Door state attrs Open/OpenChangedAt; leaf attrs ClosedCFrame/Collides. The client slides the leaves by OpenOffset and predicts opening within OpenRadius (default ~9).",
   "dependsOn": "Model tag AutoDoor (or AutoDoor_<name> models); leaves with OpenOffset (Vector3 world, ~+-1.88 studs along the facade).",
   "interactions": "Doors open as you walk up. NPCs open them through invisible AutoDoorOpener proxies (StreetInteract/Places).",
   "constraintsForNewProps": "Keep the slide pocket (leaf width + 2 studs each side along the glass, 0.6 deep) and a 4x4-stud vestibule inside every AutoDoor completely clear. Never hide or move door leaves or handles."
  },
  {
   "script": "ServerScriptService/GwangalliGameplay/Venues + VenueLife + VenueKaraoke + VenuePC (client GwangalliVenues)",
   "role": "Venue interiors of the life game: 노래방, PC방, 헬스장, 볼링장 라운지, salon/clothing counters, elevator buttons.",
   "buildsAtRuntime": "Prompts on tagged parts; Workspace.GwangalliVenueProps (food props, shoe shells); leaderboard text rows. The PC clerk walks food orders to the seat.",
   "dependsOn": "- KaraokeRoom: models Booth_01..08 in Workspace.Gwangalli.karaoke['광안 코인노래연습장'] (ZoneLOD, LODCenter e.g. (32,12.4,299), attrs RoomNo/RoomName), with KaraokeZone + KaraokePanel parts. Prompt '방 잡기'; song state in attrs KSong/KStart/KSerial.\n- PCStation: models PC_01..48 in pcbang['광안 PC방'].PCHall, with a Seat child + Keyboard/MonitorScreen. Prompt 'PC 켜기'; attrs PCNo, AislePos, RamenCF, ServePos, PCUser.\n- GymStation parts (StationType, UsePoint, Equipment) in bowling/상층_2F-4F/4F_광안휘트니스24 (25).\n- VenueSpot: bowl_shoes (316.6,9.5,458.3), bowl_punch, bowl_snack, gym spots.\n- VenueBoard: BoardFace + BoardGui Row1..5.\n- ShopCounter_gym_store/_salon/_clothing; SalonChair (5).\n- ElevatorButton_2F/3F/4F with Target ElevatorStop_n.\n- VenueStaff rigs (HomeCF).",
   "interactions": "방 잡기 + song picker + rhythm/score; PC 켜기 + racer game + 라면 주문 delivered to ServePos/RamenCF; gym sets; 볼링화 대여; 펀치기계; venue counters (구매 / 다음 상품); elevator rides (fade + teleport).",
   "constraintsForNewProps": "Never hide or move KaraokePanel, KaraokeZone, the PC Seat/Keyboard/MonitorScreen (the server sets Keyboard CanQuery=true), the RamenCF desk spot, the ServePos/AislePos walkway, UsePoint, BoardFace, ElevatorButton or ElevatorStop parts. Keep the PC aisle at AislePos and the area in front of each GymStation free."
  },
  {
   "script": "ServerScriptService/GwangalliGameplay/Jobs + JobWorld + JobCvs + JobCvsPlus (+JobCvsPlusBoot) + JobShop + JobDelivery; client GwangalliJobs (World, CvsWorld, Shop)",
   "role": "알바 in the world: the GS25 광안리점 store job, 광안 딜리버리, and purchases for every player.",
   "buildsAtRuntime": "- Pooled customer rigs (max 3 per store) in workspace.GwangalliNPCs, walking the GwJobStation graph.\n- Carried restock box / parcel props, and Workspace.GwangalliWorkPoints anchors.\n- JobCvsPlus builds Workspace.GwCvsPlus/Display_slot_food|snack|drink|life product models at init (3 tiers x 4 cols x 2 rows, price tags, 1+1 tags), so the GS25 slot shelves are fuller in game than in the static place.\n- JobShop prompts '고르기' (F, 8 studs) on Station_buy_drink / Station_buy_shelf.\n- Client-local props on the counter (basket items, receipt, bills) in GwangalliJobLocal.",
   "dependsOn": "Workspace.Gwangalli.convenience['GS25 광안리점'].JobStations (tag GwJobStation, attrs Job='gs25', Station):\n- counter (-329.0,7.5,304.4), counter_items (-325.9,11.1,304.3), counter_scanned (-325.9,11.1,301.4), boss (-329.3,7.5,300.2)\n- backroom (-370.7,7.5,291.2), chiller (-346.7,7.5,301.4), chiller_items (-346.7,10.2,304.0)\n- slot_food (-353.7,8.2,291.6), slot_snack (-353.5,8.2,283.1), slot_life (-353.3,8.2,274.6), slot_drink (-321.0,8.2,275.2)\n- door_out (-299.7,7.5,302.1), door_in (-311.7,7.5,301.9), front (-319.4,7.5,299.3)\n- aisle1 (-319.2,7.5,288.0), aisle2 (-319.1,7.5,279.5), aisle3 (-318.9,7.5,269.3), b3mid (-355.4,7.5,287.4)\n- browse1 (-337.4,7.5,287.7), browse2 (-331.3,7.5,279.3), browse3 (-356.0,7.5,283.6), browse4 (-337.1,7.5,268.9)\n- queue1 (-322.8,7.5,304.7), queue2 (-319.8,7.5,304.8), queue3 (-316.9,7.5,304.2)\n- buy_drink (-356.4,7.5,276.6), buy_shelf (-319.7,7.5,292.3), GwJobSpawn (-331.9,7.5,301.1)\n\nAlso the delivery/광안 딜리버리 JobStations (dispatch ...), and the employer NPC 김사장님 (G.NPCS gs25_owner, offset {1.4,-24.6} from the Destination (-304.7,7.1,302.1)).",
   "interactions": "Shift tasks (계산 scan minigame, 2-phase 진열 restock, 유통기한, 택배 접수, the 🔔 counter interrupt, 🙋 greet); 돌발 상황 prompts (바닥 흘림, 냉장고 문, 영수증 용지 ...); 상품 정리 facing prompts; purchase sheets.",
   "constraintsForNewProps": "Keep every GwJobStation point free of collidable or tall props (2.5-stud radius), and the straight walk lines between consecutive points too (3-stud wide lanes): door_out->door_in->front->aisle1->aisle2->aisle3, aisle->browseN, front->queue3->queue2->queue1->counter, b3mid. Never cover the slot shelves in front of Display_slot_* (the products appear there) or counter_items/counter_scanned (the basket props land there). Do not rebuild the GS25 shelves at different positions."
  },
  {
   "script": "ServerScriptService/GwangalliGameplay/Work + WorkCafe + WorkProps + WorkOrders + WorkMini + WorkOnboard + Customers + WorkPlacement (+NpcPort) + Play/Career/{Cafe,Hooks} + ServerScriptService/GwangalliStaff + Play/Manager (+StaffSim)",
   "role": "Barista work simulation at 스타벅스 광안리점, NPC customers, 점장 mode NPC 알바생, and auto-placement at clock-in.",
   "buildsAtRuntime": "- Workspace.GwangalliWork_starbucks, built lazily by Work.storeFor: cup stacks, ice bin, 2 espresso machines, steam pitchers, milk fridge, water, syrup, lids, work slots, a 4-slot pickup counter, trash, labels, puddles. Positions come from WorkCafe.LAYOUT in the frame of Destination_스타벅스 광안리점 (-833.8,10.9,83.2): front counter local z 29-31, staff lane z 32.25, back counter z 35-36, posCustomer (3.21,-4.2,26.23), pickupCustomer (-30.76,-4.2,27.76).\n- Customers (Career.Cafe / Customers SITES.starbucks) in workspace.GwangalliNPCs: door (0,-4.2,3), lobby (1.5,-4.2,15), order (3.21,-4.2,26.23), waits (-26.5..-31.4,-4.2,22..23.6), pickup (-30.76,-4.2,27.76).\n- GwangalliStaff NPC staff (max 3 per store; stations pos/bar/serve at Starbucks and counter/stock/clean at GS25) + Workspace.GwangalliStaffProps.\n- Uniforms welded to players.",
   "dependsOn": "Parts tagged GwWorkStation (Store, Station) override LAYOUT. Also GwWorkSpot (JobId/Job) parts and GwangalliWorkSpots.JOBS: the gukbap spot is (-897.5,8,104) facing (-897.5,8,92); the hoe hall camera shots are around (-2610..-2640, 8..11, -24..-49). WS.CLEAR_SIZE 2.2x4.8x2.2 free box for the worker; NEGLECT radius 38.",
   "interactions": "POS, cups, ice, espresso pull/tamp/steam minigames, pickup call-outs, tip jar, receipt printer, 미끄럼 주의 sign, time clock; 점장 hire/assign/praise/teach.",
   "constraintsForNewProps": "Inside 스타벅스 광안리점, keep the bar line (Destination-frame z 28-37, x -34..8) and the customer lanes (door->lobby->order->waits->pickup) free. Never add parts on the front counter (z 29-31) or back counter (z 35-36) tops, where the cups, machines and slots sit. Keep the 2.2x4.8x2.2 worker clear box around every GwWorkSpot and the gukbap spot."
  },
  {
   "script": "ServerScriptService/GwangalliGameplay/Play/Career/Gukbap",
   "role": "국밥집 알바 in Workspace.Gwangalli.shops['행복 돼지국밥'] (GwShop gukbap).",
   "buildsAtRuntime": "Under workspace.GwangalliPlay.Career.Gukbap: prompts (GwCareerPrompt), BillboardGui labels (GwCareerLabel), GwCareerSet table sets and GwCareerTray trays, plus Destination_행복 돼지국밥. NPC parties (1-2 per table, max 4) sit at the 8 GwShopTable Seats.",
   "dependsOn": "ShopBounds (-894.2,11.8,98.8), 39.1x9.9x39.9; 8 GwShopTable models (Seat + TrayPoint); PassTray at the kitchen pass; Points/Point_order_1; GwShopClerk rigs.",
   "interactions": "주문 받기, 국밥 말기 (cook panel), 쟁반 들기, 서빙하기, 계산하기 (change panel), 치우기.",
   "constraintsForNewProps": "Never move or hide the 8 Table_n models, their Seats and TrayPoints, PassTray or Point_order_1. Keep the hall between the pass and the tables open."
  },
  {
   "script": "ServerScriptService/GwangalliGameplay/Play/{Pocha, Grill, Gym, Arcade(+World,Games,Hub,Adapters), Actors, Scene, Boards, Missions, Street}",
   "role": "Play content layered on the venues.",
   "buildsAtRuntime": "- Pocha: an owner actor, invisible Seats on existing stools + folding tables beside the 5 tent 포장마차_* and in the indoor 민락 포장마차 (CU 민락비치점 빌딩, floor (-1778,6.6,13)), signs, and a Destination '광안 포장마차', in workspace.GwangalliPlay.Pocha.\n- Arcade: prompt anchors per machine (광안 게임랜드 펀치기계, BasketballMachine_1/2; 볼링장 오락코너 농구게임), a 팔씨름 table at the first free spot and wall boards, in workspace.GwangalliPlay.Arcade.\n- Gym: RecordBoard parts in workspace.GwangalliPlay.Gym.\n- Grill: wraps ShopFlows bbq (the district building).\n- Actors: temporary NPC rigs in workspace.GwangalliNPCs.",
   "dependsOn": "Machine names/parts (ScoreDisplay, ScoreLED, FrontScore, Messages LED), the existing stools (PlasticStool), CartBody/CartTop/TentRoof.",
   "interactions": "Pocha: 자리 앉기 / 주문하기 / 먹기 / 건배 / 계산. Arcade: 펀치/농구/팔씨름 games. Gym: PB boards.",
   "constraintsForNewProps": "Do not hide or move the arcade machines or their score parts, or the pocha stools, counter stools and window tables (invisible Seats sit on them). Leave ~6 free studs of floor in the arcade for the 팔씨름 table search."
  },
  {
   "script": "ServerScriptService/GwangalliGameplay/Interact + StreetInteract/Places + Details + MiniGames/StationBuilder + Housing (life game); client GwangalliHome (+Interior)",
   "role": "World interaction layer (sittables, props, purchases), city NPCs using facilities, Korean-life details, minigame stations, life-game homes.",
   "buildsAtRuntime": "- Interact: tags GwSittable (+SitKind, SitFace) on chair/stool/seat/cushion/bench/sofa parts across the Workspace, except homes, npcnav, the club, Car_ models, and ClubTable/HospitalBed/SalonChair/GymStation/BowlingLane/ShopCounter-tagged parts. v7 has no client hub, so the tags do nothing for players, but the server's sitOn uses them. Props/carts/vending/claw machines go in workspace.GwangalliInteract.\n- Places: city NPC shoppers use the GS25 terrace ChairSeats and the GS25 station graph; AutoDoorOpener proxies at doors.\n- Details: 네컷사진관 booths (clearance search next to walkways) in workspace.GwangalliDetailsWorld.\n- MiniGames: promenade tables/cabinets in workspace.GwangalliMiniGames.\n- Housing: HomeUnit_<tier> templates from ServerStorage.GwangalliHomes are cloned to Workspace.GwangalliHomeInstances at (0, 4000+row*spacing, col grid). They contain HomeInteract parts (Kind bed/sofa/tv/fridge/desk/window/mailbox/interior), FurnitureSlot models (SlotId, Category, DefaultItem, Footprint, Rotate) and Room + Surface attributes for themes.",
   "dependsOn": "IS.classify by name/size. HomeEntrance parts in Workspace.Gwangalli.homes.Entrances: goshiwon (-489.1,10.1,255.4), oneroom (209.6,10.1,601.5), officetel (-1495.2,10.1,34.8) ...",
   "interactions": "Home: sleep, sofa/TV, fridge sheet, shower, wardrobe, desk, window photo, mailbox, 인테리어 slots/themes, doorbell/invites. Details: booth photos, gull feeding, delivery, fireworks, busking.",
   "constraintsForNewProps": "Homes already have a slot-based decor system (the client Interior.luau highlights slots and shows ghost pieces). Do NOT add detail inside GwangalliHomeInstances or HomeUnit_*: it would fight the owner's furniture and themes. Keep any part a city NPC may sit on (GwSittable) at its position."
  },
  {
   "script": "Club (ServerScriptService/Club, ClubMusic, GwangalliClub/*; client ClubLights/ClubDance/ClubMusic/GwangalliClubShow) and Bowling (ServerScriptService/Bowling; client BowlingClient/BowlingFX), GwangalliShowroom, GwangalliGameplay/Garage, Law/Hospital (map clinic)",
   "role": "Dedicated venue systems with their own scripted interiors.",
   "buildsAtRuntime": "- Club: show sync, door/eject, 130 ClubNPC rigs animated locally, LED floor/walls, lasers, CO2.\n- Bowling: a physics ball + pins per lane (the only physics in the hall).\n- Showroom: display cars in Workspace.GwangalliShowroom on free floor spots.\n- Clinic: HospitalPrompt desk/doctor, HospitalBed seats.",
   "dependsOn": "Club tags ClubVenue/ClubTable/ClubZone/ClubLight/ClubFloorTile/ClubNPC/ClubShowAnchor/ClubRuntime/ClubDoor. BowlingLane models (LaneFrame, Pins/Pin_n Collider, Ball BallCore, BallRackPrompt, HallLeaderboard, LaneMonitor_XX). Garage tags GarageTurntable/GarageDisplayCar/GaragePrompt. HospitalBed BedSeat.",
   "interactions": "Club entry/bottle service/dance; bowling lanes; car purchase/test drive/service/wash; clinic treatment.",
   "constraintsForNewProps": "Exclude Workspace.Gwangalli.club, .bowling (lanes + 실내 + 상층), the .garage showroom floor and the clinic beds from the new detail pass, or only add wall-mounted, non-colliding decor there. Never put anything on the bowling lanes/approach (physics) or the LED dance floor."
  }
 ],
 "rules": [
  "R1 Read-only map: never Destroy, rename, reparent, resize or re-CFrame any instance the client did not create. The servers find shops by part names and bounding boxes, and reparenting streamed instances on the client breaks the streaming bookkeeping. The only allowed edit to a map part is local visibility (see R3), and only on purely decorative parts.",
  "R2 Own root: put everything under one client-created Folder, e.g. Workspace.GwInteriorDetailLocal. It must not be under Workspace.Gwangalli, must not be named GwangalliBuildings*/GwB_*/GwangalliPlay/GwangalliNPCs/GwCvsPlus*, and must carry no tags the host systems use. Give it attr LOD='near' if GwangalliTextures must not texture your parts.",
  "R3 Hiding crude parts: inside a root with GwArrive=true, hide with LocalTransparencyModifier=1 (DetailLOD writes Transparency there). Inside other NearLOD/ZoneLOD roots, hide with a local Transparency=1 (DetailLOD writes LocalTransparencyModifier there), and disable the parts' SurfaceGuis/Decals/Textures (including GwangalliTex) yourself. Re-apply on stream-in and whenever the root's GwHideState changes; restore exactly on unload.",
  "R4 Never hide or move gameplay parts:\n- Seats: ChairSeat, StoolSeat, Stool, Seat, Cushion, SeatCushion, StoolTop, BarStool, any Seat, anything GwSittable-tagged.\n- Table tops: TableTop, LowTableTop, LowTable, CommunalTable, Table, BarTop, WindowBar, Ledge, CounterTop, PassTop, BarCounter, PlasticTable/Top, GrillTable/Coals/CharcoalPot.\n- Cashier/kitchen/station parts: OrderKiosk, KioskScreen, PosBase, CustomerDisplay, PosScreen, CashDeskTop, CardReader, Counter, FrontDesk, WorkDesk, EspressoBody, GroupHead, TapPost/TapHandle/TapBar, CuttingBoard, Fryer, StockPot, Burner, KitchenPass, PassLedge, PassTray, DripTray, Hood, Grinder, GelatoTub, WaffleIron, SteamerCase, TankWater, HotWater, Microwave, ATMScreen, DeskBell, Mailboxes, TrayStation, Tester, WaterPurifier/WaterDispenser, Bin/TrashBin/RecycleBins, MDBoard, Sign_메  뉴/Sign_MENU.\n- Shelving: Gondola_n, Fridge, OpenChiller, IceCreamChest, PastryCase, WallRack, Shelf.\n- Shell and doors: Door_restroom/DoorLeaf, ShopFloor, ShopBounds, ShopBackWall, ShopPartition, ShopCeiling, AutoDoor leaves/handles, Door/GlassDoor/ShopDoor/LobbyDoor/EntranceDoor/FrontDoor/BackDoor/ServiceDoor.\n- Every tagged anchor: GwShopPoint, GwShopSpot, GwShopTable, GwShopClerk, GwJobStation, GwJobSpawn, GwWorkStation, GwWorkSpot, VenueSpot, VenueBoard, VenueStaff, the KaraokeRoom parts KaraokePanel/KaraokeZone, the PCStation Seat/Keyboard/MonitorScreen, GymStation/UsePoint, SalonChair, ShopCounter, ElevatorButton/ElevatorStop_n, HospitalBed, HomeEntrance, all GwB_* tags.\n- All NPC rigs and figures.\n\nYou MAY re-skin these only by overlaying a nicer non-colliding copy at exactly the same pose (seat top +-0.1 stud, same facing; table top at the same Y and XZ extent) and hiding the original per R3.",
  "R5 New geometry is non-interactive by default: Anchored=true, CanCollide=false, CanTouch=false, CanQuery=false, Massless, CastShadow only on large pieces. No Seats, no Humanoids, no ClickDetectors. Thin overlays (wall/floor/ceiling skins) go 0.02-0.05 stud in front of the map surface, so IndoorLight's roof/wall raycasts and the ShopLife/ShopStaff server checks keep hitting the real parts.",
  "R6 Keep these volumes clear (no new geometry taller than 0.1 stud):\n- the AutoDoor slide pocket (leaf width + 2 studs each side, 0.6 deep) and a 4x4-stud vestibule inside every door;\n- a 2x3-stud staff zone from each cashier anchor's back edge to 4 studs behind it (the ShopStaff stand spot is at half-depth + 1.7..3.6 studs and needs a 1.6x2.6x1.6 box);\n- 2.5-stud aisles from the pass/counter to every table (ShopService waiter + ShopLife staffMode);\n- 7 studs around every ShopLife Anchors part, and the back-wall strip where the bin / water purifier may be added;\n- a 2.5-stud radius around every GwJobStation, and 3-stud lanes between consecutive GS25 station points;\n- the Starbucks bar line and customer lanes (Destination frame z 3..37);\n- PC AislePos/ServePos, GymStation fronts, the arcade's free floor;\n- 2 studs around static NPC figures.",
  "R7 Table tops: ShopLife places banchan, a water cup, 수저 and dishes at seat.spot offsets up to +-1.6 x / -0.1..+1.05 z, and the 호출벨 at the (max.X-0.35, max.Z-0.35) corner. Most map tables are only 3.6x2.4 studs, so add nothing on them except flush textures/decals (a napkin/spoon box only where a SpoonBox already sits).",
  "R8 Prompts: none of the host prompts use line of sight, so your parts cannot block them. Your own cosmetic ProximityPrompts must:\n- be client-local;\n- be named distinctly (not LifePrompt/AnnexPrompt/GwCareerPrompt/GwangalliPCPrompt/GwangalliKaraokePrompt);\n- use MaxActivationDistance <= 5 and Exclusivity OnePerButton;\n- not sit within 6.5 studs of a host anchor that already offers an action;\n- never duplicate a server action (order, pay, sit, buy).",
  "R9 Lights: set attr GwIndoorDim (e.g. 0) on your lights before parenting, or GwangalliIndoorLight multiplies Brightness by 0.55 and caps Range at 18. Keep your own nearest-N budget; the host budget is 6/16/24 interior lights within 90/140/160 studs (low/mid/high), saver 3. Use Shadows=false. Never toggle the InteriorLight/CityLight/GwB_Light lights the host manages.",
  "R10 Glass and signs: never write Material/Color/Transparency/Reflectance of Window, RoomGlass, NightWindow-tagged glass or Sign_* parts/guis (Signage, NightWindows and StreetSigns own them). Keep the 1-2 stud strip behind ShopWindow glass low so StreetSigns' 시트지 window film and posters read. If you detail RoomDepth, respect Config.Mobile.HideRoomDepth (the low tier hides the RoomDepth fake rooms).",
  "R11 Streaming / discovery: StreamingEnabled=true and GwDiscoverTagged=true, so use CollectionService tag signals, not a Workspace-wide DescendantAdded. Discover map shops through:\n- tag AutoDoor (door.Parent is the shop Model; require a ShopFloor child);\n- the NearLOD/ZoneLOD Interior models;\n- tag GwShop.\n\nKey a shop the way ShopLife does: '<model name>@<round(floor X)>,<round(floor Z)>'. Interior/NearDetail/ShopDetail models use ModelStreamingMode Atomic: they arrive whole and may return as new instances. The shop Model itself is default, so ShopFloor, walls and counters stream separately: wait for parts with ChildAdded, and rebuild on AncestryChanged.",
  "R12 Runtime interiors:\n- GwangalliBuildings interiors: build only after the tags GwB_Interior / GwB_Furnish / GwB_Shop appear, and drop on removal (the server parks interiors after 25 s and unfurnishes storeys after 30 s).\n- Annex rooms/buildings live at y~3000 (ORIGIN (-9600,3000,-9600), slot 560) and exist only while someone is inside. Detect them via the local player's GwB_AnnexInst attribute or Model attr AnnexRoom=true.\n- Skip player homes (Workspace.GwangalliHomeInstances, GwB_Unit with OwnerUserId, GwB_Placed).",
  "R13 Budget: build only within ~60-80 studs of the camera (DetailLOD radius is 70/100/150). Time-slice under ~2-3 ms per frame; the host uses 3 ms slices and 200-800 writes per frame. Cap parts per shop by tier, and read the tier from ReplicatedStorage.GwangalliQuality.get() (fallback: touch = low).",
  "R14 Skip venues with their own systems: Workspace.Gwangalli.club (CLUB OCEAN), .bowling (lanes, 실내, 상층 venues), the .garage showroom floor/turntables and the hospital clinic beds. For .karaoke, .pcbang, .convenience (GS25), .arcade and .shops (the 7 GwShop shops), only add wall/ceiling/floor finish overlays and decor that respects R4/R6.",
  "R15 Work shifts: when the local player has OnShift / GwWorkShift set (or is GwMgrDuty), do not spawn or animate decor at that store's stations. Do not weld or attach anything to characters: the host welds uniforms, held props (GwB_HoldWeld/GwB_UtensilWeld) and restock boxes."
 ],
 "notes": "The street shops look as empty in game as they do in the static place. The map's own walk-in shops are not filled at runtime: the 134 beachfront street shops (a Model with Interior + ShopFloor children), the 7 GwShop shops in Workspace.Gwangalli.shops, GS25 광안리점 and 홈플러스 익스프레스 keep exactly the furniture saved in the place.\n\nWhat runtime does add to those shops:\n- ShopLife: invisible prompt anchors, a bin or water purifier where none exists, a 호출벨 plus banchan/dishes while you eat, and pocha lanterns.\n- ShopStaff: one clerk rig behind the counter (at most 36 within 150 studs).\n- GwangalliShopService: one waiter in open table shops.\n- Customers: only at GS25 and Starbucks, and only during shifts.\n\nWhat is missing from the static place and built only at runtime:\n- The whole GwangalliBuildings district at (4283.5,18.9,-200): 8 buildings with shells and streamed interiors (GW25 편의점, 부산 돼지국밥, 광안 숯불갈비 1F/2F, 바다 카페, PC방, 노래방, 당구장, 부동산, the 호텔 씨사이드 lobby + 로열 카지노, and apartment/officetel/villa/oneroom homes).\n- 광안 종합병원 at (-704,~13,1236) and the 삼진전파사 hideout at (-767.8,~7,348).\n- Every Annex interior of a facade-only building, in slots at y~3000.\n- Infill lots and 근린상가 (Workspace.GwangalliInfill).\n- Life-game homes (Workspace.GwangalliHomeInstances, y 4000+).\n- GS25 shelf products (Workspace.GwCvsPlus Display_slot_*) and the Starbucks bar equipment (Workspace.GwangalliWork_starbucks).\n- Sign hardware and window film (Workspace.GwangalliSignage), 네컷사진관 booths, minigame tables, showroom cars and venue props.\n\nThese placeholders are empty in v7 and nothing fills them: Workspace.Gwangalli.living, living_shops, police, hideout, mafia and npcnav (0 children). The Living* feature modules listed in GwangalliGameplay FEATURE_MODULES are not in the place.\n\nWhat looks crude (134 static street shops scanned):\n- The Interior model has a median of 43.5 parts (min 0, max 182).\n- 48 of 134 have no counter-type part.\n- 83 of 134 have no Light instance (51 lights in total).\n- 24 have 12 or fewer interior parts. Apartment and hotel lobbies such as 협진태양맨션 are 6 MailboxLine strips, one Mailboxes box and fake ElevatorDoor slabs. OCEAN STAY has 1 part; CITY NINE, L MOTEL and TERRASTAR OCEAN have 0.\n\nA typical restaurant, 남천 해장국 (floor 34x18 studs), has:\n- 20 chairs of 3 boxes each (ChairSeat, ChairBack, ChairLeg);\n- 5 tables, each one 3.6x0.1x2.4 TableTop on a single 1.5-stud TableFoot;\n- 5 SpoonBox, 2 TubeLamp and one Sign_메  뉴.\n\nA real Korean 해장국집 would also have:\n- a stainless kitchen pass with 육수 솥 and a 반찬 냉장고;\n- a 정수기 and 컵소독기;\n- a wall menu with prices;\n- a TV, a standing 에어컨 and a 카드단말기 at the counter;\n- real floor, wall and ceiling finishes (here they are single ShopFloor, ShopBackWall and ShopPartition slabs and one flat ShopCeiling);\n- 수저통 and 냅킨 on every table.\n\nRuntime-built interiors are boxy too. Annex rooms are Kit.box rooms; a table room is 38x30 studs with six identical box tables, a box counter, a PassLedge and a menu board. The GwangalliBuildings shop templates are finishes() boxes plus counters plus static staff figures without a Humanoid.\n\nFiles are in /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/:\n- systems.json: the full findings, plus runtime folders, key coordinates and static counts.\n- systems_streetshops_static.json: per-shop static stats.\n- tags_static.json: the static tag inventory with sample positions.\n- eff/: the effective runtime sources (place scripts with the addon overlays applied)."
}
```

## survey:districts

```json
{
 "venues": [
  {
   "name": "beachfront 구간06 광안해변로209번길 ~ homers (1 bldg, 3 shops)",
   "path": "Workspace.Gwangalli.beachfront.구간06 광안해변로209번길 ~ homers",
   "bounds": "(291,6.5,99)..(358,151.6,181)",
   "rooms": [
    {
     "name": "SideShop · 바다곁 [cafe]",
     "center": [
      350,
      6.8,
      138
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "바다곁 파스타 & 와인 [bistro; ShopLife soup]",
     "center": [
      317,
      6.8,
      115
     ],
     "size": [
      41,
      10,
      19
     ]
    },
    {
     "name": "OCEAN VIEW RESIDENCE [residence]",
     "center": [
      348,
      6.8,
      112
     ],
     "size": [
      16,
      11,
      14
     ]
    }
   ],
   "props": [
    "광안 오션뷰 레지던스: SideShop · 바다곁: 4ch, 2tb; ctr, POS, esp, grd {d14.1 no pastry case, menu board, pickup counter, ice/blender, restroom door} | 바다곁 파스타 & 와인: 14ch, 7tb; ctr, POS, pass, wine wall, barshelf x3 {d19.0 no menu board} | OCEAN VIEW RESIDENCE: elev-leaves x4, mailbox x6 {d10.6 no desk, doorlock, parcel lockers, seating; 14-deep box}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "바다곁 파스타 & 와인: ShopLife classifies it soup/gukbap by contents (sign says 파스타 & 와인) -> menu mismatch",
    "OCEAN VIEW RESIDENCE: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance"
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "광안 오션뷰 레지던스: OCEAN VIEW RESIDENCE: lobby is a 14-deep box with flat elevator leaves"
   ],
   "realWorld": [
    "types: cafe, bistro, residence — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: cafe, bistro, residence — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간12 광안해변로278번길 ~ edge (8 bldg, 14 shops)",
   "path": "Workspace.Gwangalli.beachfront.구간12 광안해변로278번길 ~ edge",
   "bounds": "(-2467,6.5,-93)..(-2030,178.4,43)",
   "rooms": [
    {
     "name": "SideShop · 스시 오션 [rawfish]",
     "center": [
      -2454,
      6.8,
      -52
     ],
     "size": [
      34,
      11,
      10
     ]
    },
    {
     "name": "스시 & 사케 오션 [rawfish]",
     "center": [
      -2436,
      6.8,
      -77
     ],
     "size": [
      40,
      11,
      18
     ]
    },
    {
     "name": "MILLAK OCEAN TOWER [residence]",
     "center": [
      -2405,
      6.8,
      -74
     ],
     "size": [
      18,
      12,
      14
     ]
    },
    {
     "name": "민락 스낵 편의점 [cvs]",
     "center": [
      -2380,
      6.8,
      -66
     ],
     "size": [
      22,
      10,
      22
     ]
    },
    {
     "name": "BBQ [chicken; ShopLife burger]",
     "center": [
      -2356,
      6.8,
      -65
     ],
     "size": [
      22,
      10,
      18
     ]
    },
    {
     "name": "SUNSET ROOFTOP [cafe; ShopLife pub]",
     "center": [
      -2318,
      6.8,
      -58
     ],
     "size": [
      49,
      11,
      19
     ]
    },
    {
     "name": "민락 활어횟집 [rawfish]",
     "center": [
      -2270,
      6.8,
      -46
     ],
     "size": [
      44,
      10,
      18
     ]
    },
    {
     "name": "HOTEL 야자수 [lobby]",
     "center": [
      -2228,
      6.8,
      -48
     ],
     "size": [
      31,
      10,
      14
     ]
    },
    {
     "name": "민락수산 [rawfish]",
     "center": [
      -2179,
      6.8,
      -39
     ],
     "size": [
      22,
      10,
      18
     ]
    },
    {
     "name": "민락 초장집 [rawfish]",
     "center": [
      -2153,
      6.8,
      -35
     ],
     "size": [
      27,
      10,
      18
     ]
    },
    {
     "name": "갯마을 조개구이 [grill]",
     "center": [
      -2114,
      6.8,
      -23
     ],
     "size": [
      46,
      10,
      19
     ]
    },
    {
     "name": "SideShop · 민락 복국 [soup]",
     "center": [
      -2042,
      6.8,
      4
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "민락 복국 [soup]",
     "center": [
      -2070,
      6.8,
      -24
     ],
     "size": [
      35,
      10,
      18
     ]
    },
    {
     "name": "MILLAK BEACH HOTEL [lobby]",
     "center": [
      -2041,
      6.8,
      -22
     ],
     "size": [
      18,
      11,
      14
     ]
    }
   ],
   "props": [
    "민락 오션타워: SideShop · 스시 오션: 8ch, 2tb; pass {d10.2 no POS/cashier, counter, restroom door} | 스시 & 사케 오션: 24ch, 6st, 6tb; ctr, pass {d18.6 no POS/cashier} | MILLAK OCEAN TOWER: elev-leaves x4, mailbox x6 {d9.8 no desk, doorlock, parcel lockers, seating; 14-deep box}",
    "민락 노래빌딩: 민락 스낵 편의점: ctr x2, POS, steamer, mw x2, hotwater, ATM, fridge, gond, cig cab; CCTV {d14.9 no window eat-in bar} | BBQ: 16ch, 4tb; kiosk, pass {d17.1 no counter}",
    "선셋 루프탑 카페: SUNSET ROOFTOP: 8ch, 4tb; ctr x2, POS, esp, grd, pastry case, wallshelf {d10.5 no menu board, pickup counter, ice/blender}",
    "민락 활어횟집: 민락 활어횟집: 16st, 4tb; ctr, board, tank {d5.5 no POS/cashier}",
    "호텔 야자수: HOTEL 야자수: elev-leaves x4, mailbox x6 {d5.6 no desk, doorlock, parcel lockers, seating; 14-deep box}",
    "민락 활어 초장집: 민락수산: 8st, 2tb; ctr, board, tank {d7.1 no POS/cashier} | 민락 초장집: 8st, 2tb; ctr, board, tank {d5.9 no POS/cashier}",
    "갯마을 조개구이: 갯마을 조개구이: 28st, 7tb, 7 grilltb; fridge {d10.4 no POS/cashier, counter, kitchen line}",
    "민락 비치호텔: SideShop · 민락 복국: 8ch, 2tb; pass {d10.2 no POS/cashier, counter, restroom door} | 민락 복국: 12ch, 8cush, 5tb; pass {d10.0 no POS/cashier, counter} | MILLAK BEACH HOTEL: 2seat; monitor x2, elev-leaves x4, desk {d16.0 no doorlock, parcel lockers; 14-deep box}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "MILLAK OCEAN TOWER: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance",
    "BBQ: ShopLife classifies it burger by contents (BBQ = chicken brand) -> menu mismatch",
    "HOTEL 야자수: ShopLife lobby lobby -> annexLink \"올라가기\" to an Annex building instance",
    "갯마을 조개구이: no AutoDoor (open shutter front), ShopLife grill",
    "MILLAK BEACH HOTEL: ShopLife lobby lobby -> annexLink \"올라가기\" to an Annex building instance"
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "민락 오션타워: MILLAK OCEAN TOWER: lobby is a 14-deep box with flat elevator leaves",
    "민락 활어횟집: 민락 활어횟집: very sparse (d5.5)",
    "호텔 야자수: HOTEL 야자수: very sparse (d5.6); lobby is a 14-deep box with flat elevator leaves",
    "민락 활어 초장집: 민락 초장집: very sparse (d5.9)",
    "민락 비치호텔: MILLAK BEACH HOTEL: lobby is a 14-deep box with flat elevator leaves"
   ],
   "realWorld": [
    "types: rawfish, residence, cvs, chicken, cafe, lobby, grill, soup — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: rawfish, residence, cvs, chicken, cafe, lobby, grill, soup — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간11 광안해변로255번길 ~ 광안해변로278번길 (8 bldg, 13 shops)",
   "path": "Workspace.Gwangalli.beachfront.구간11 광안해변로255번길 ~ 광안해변로278번길",
   "bounds": "(-2004,6.5,-29)..(-1587,145.0,86)",
   "rooms": [
    {
     "name": "SideShop · BLUE WAVE [cafe]",
     "center": [
      -1994,
      6.8,
      15
     ],
     "size": [
      34,
      11,
      10
     ]
    },
    {
     "name": "BLUE WAVE COFFEE [cafe]",
     "center": [
      -1973,
      6.8,
      -11
     ],
     "size": [
      48,
      11,
      19
     ]
    },
    {
     "name": "민락 대게 [seafood]",
     "center": [
      -1924,
      6.8,
      1
     ],
     "size": [
      46,
      10,
      18
     ]
    },
    {
     "name": "민락 포차 [pocha]",
     "center": [
      -1878,
      6.8,
      7
     ],
     "size": [
      41,
      10,
      19
     ]
    },
    {
     "name": "라운지 카페 씨엘로 [cafe]",
     "center": [
      -1835,
      6.8,
      6
     ],
     "size": [
      39,
      11,
      19
     ]
    },
    {
     "name": "HOTEL CIELO [lobby]",
     "center": [
      -1803,
      6.8,
      7
     ],
     "size": [
      20,
      12,
      14
     ]
    },
    {
     "name": "민락 포장마차 [pocha]",
     "center": [
      -1778,
      6.8,
      13
     ],
     "size": [
      26,
      10,
      19
     ]
    },
    {
     "name": "CU [cvs]",
     "center": [
      -1751,
      6.8,
      17
     ],
     "size": [
      24,
      10,
      22
     ]
    },
    {
     "name": "신라횟집 [rawfish]",
     "center": [
      -1703,
      6.8,
      26
     ],
     "size": [
      41,
      10,
      18
     ]
    },
    {
     "name": "돗자리 · 폭죽 · 튜브 [retail]",
     "center": [
      -1670,
      6.8,
      22
     ],
     "size": [
      18,
      10,
      14
     ]
    },
    {
     "name": "CU [cvs]",
     "center": [
      -1648,
      6.8,
      28
     ],
     "size": [
      24,
      10,
      22
     ]
    },
    {
     "name": "SideShop · WILD WAVE TAPROOM [pub]",
     "center": [
      -1598,
      6.8,
      61
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "WILD WAVE [pub]",
     "center": [
      -1611,
      6.8,
      31
     ],
     "size": [
      43,
      10,
      19
     ]
    }
   ],
   "props": [
    "블루웨이브 커피: SideShop · BLUE WAVE: 4ch, 2tb; ctr, POS, esp, grd {d14.1 no pastry case, menu board, pickup counter, ice/blender, restroom door} | BLUE WAVE COFFEE: 8ch, 4tb; ctr x2, POS, esp, grd, pastry case, wallshelf {d9.0 no menu board, pickup counter, ice/blender}",
    "민락 대게: 민락 대게: 16st, 4tb; ctr, board, tank {d5.4 no POS/cashier}",
    "민락 포차: 민락 포차: 28st, 7tb, 7 grilltb; fridge {d11.8 no POS/cashier, counter, kitchen line}",
    "호텔 씨엘로 민락: 라운지 카페 씨엘로: 8ch, 4tb; ctr x2, POS, esp, grd, pastry case, wallshelf {d10.9 no menu board, pickup counter, ice/blender} | HOTEL CIELO: 2seat; monitor x2, elev-leaves x4, desk {d14.5 no doorlock, parcel lockers; 14-deep box}",
    "CU 민락비치점 빌딩: 민락 포장마차: 8st, 3seat, 1 booths, 3tb; ctr, taps x4, back bar, barshelf x3; TV {d13.2 no POS/cashier, menu board} | CU: ctr x2, POS, steamer, mw x2, hotwater, ATM, fridge, gond, cig cab; CCTV {d14.2 no window eat-in bar}",
    "신라횟집: 신라횟집: 16st, 4tb; ctr, board, tank {d5.9 no POS/cashier}",
    "CU 광안해변로점 빌딩: 돗자리 · 폭죽 · 튜브: ctr, POS; CCTV {d8.3} | CU: ctr x2, POS, steamer, mw x2, hotwater, ATM, fridge, gond, cig cab; CCTV {d14.2 no window eat-in bar}",
    "와일드웨이브 광안본점: SideShop · WILD WAVE TAPROOM: 9st, 2tb; ctr, taps x4, back bar, barshelf x3; TV {d16.7 no POS/cashier, menu board, restroom door} | WILD WAVE: 9st, 3seat, 1 booths, 3tb; ctr, taps x4, back bar, barshelf x3; TV {d8.3 no POS/cashier, menu board}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "민락 포차: no AutoDoor (open shutter front), ShopLife pocha",
    "HOTEL CIELO: ShopLife lobby lobby -> annexLink \"올라가기\" to an Annex building instance",
    "민락 포장마차: Play.Pocha indoor venue \"millak\" found by model name (reads CounterTop, ShopFloor, BackBarCabinet, AutoDoor) — keep name/parts"
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "민락 대게: 민락 대게: very sparse (d5.4)",
    "호텔 씨엘로 민락: HOTEL CIELO: lobby is a 14-deep box with flat elevator leaves",
    "신라횟집: 신라횟집: very sparse (d5.9)"
   ],
   "realWorld": [
    "types: cafe, seafood, pocha, lobby, cvs, rawfish, retail, pub — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: cafe, seafood, pocha, lobby, cvs, rawfish, retail, pub — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간10 광안해변로241번길 ~ 광안해변로255번길 (7 bldg, 11 shops)",
   "path": "Workspace.Gwangalli.beachfront.구간10 광안해변로241번길 ~ 광안해변로255번길",
   "bounds": "(-1532,6.5,28)..(-1153,197.2,123)",
   "rooms": [
    {
     "name": "커피 테라스 [cafe]",
     "center": [
      -1514,
      6.8,
      44
     ],
     "size": [
      20,
      11,
      19
     ]
    },
    {
     "name": "TERRASTAR OCEAN [residence]",
     "center": [
      -1496,
      6.8,
      44
     ],
     "size": [
      12,
      12,
      14
     ]
    },
    {
     "name": "오션 공인중개사 [realty]",
     "center": [
      -1478,
      6.8,
      42
     ],
     "size": [
      18,
      11,
      6
     ]
    },
    {
     "name": "새벽집 [pocha]",
     "center": [
      -1433,
      6.8,
      48
     ],
     "size": [
      39,
      10,
      18
     ]
    },
    {
     "name": "탕후루 & 젤라또 [dessert]",
     "center": [
      -1392,
      6.8,
      50
     ],
     "size": [
      37,
      10,
      16
     ]
    },
    {
     "name": "1984 이바구밀면 [noodle]",
     "center": [
      -1347,
      6.8,
      55
     ],
     "size": [
      43,
      10,
      18
     ]
    },
    {
     "name": "조개구이 바다마을 [grill]",
     "center": [
      -1307,
      6.8,
      65
     ],
     "size": [
      32,
      10,
      19
     ]
    },
    {
     "name": "L MOTEL [lobby]",
     "center": [
      -1269,
      6.8,
      60
     ],
     "size": [
      8,
      10,
      14
     ]
    },
    {
     "name": "GS25 [cvs]",
     "center": [
      -1253,
      6.8,
      65
     ],
     "size": [
      20,
      9,
      22
     ]
    },
    {
     "name": "SideShop · 조개구이 [grill]",
     "center": [
      -1164,
      6.8,
      102
     ],
     "size": [
      28,
      10,
      10
     ]
    },
    {
     "name": "광안 조개구이 [grill]",
     "center": [
      -1177,
      6.8,
      76
     ],
     "size": [
      43,
      10,
      19
     ]
    }
   ],
   "props": [
    "테라스타오션: 커피 테라스: 4ch, 2tb; ctr x2, POS, esp, grd, wallshelf {d13.4 no pastry case, menu board, pickup counter, ice/blender} | TERRASTAR OCEAN: elev-leaves x4 {d8.0 no desk, doorlock, parcel lockers, seating; 14-deep box} | 오션 공인중개사: 1ch, 1tb {d7.7}",
    "새벽집: 새벽집: 24ch, 8cush, 8tb; pass {d15.9 no POS/cashier, counter}",
    "민락 브릿지뷰 게스트하우스: 탕후루 & 젤라또: 2ch, 1tb; ctr, POS, gelato tubs x9, disp case {d12.0}",
    "1984 이바구밀면 · 칠성횟집: 1984 이바구밀면: 24ch, 8cush, 8tb; pass {d14.4 no POS/cashier, counter}",
    "조개구이 바다마을: 조개구이 바다마을: 20st, 5tb, 5 grilltb; fridge {d11.4 no POS/cashier, counter, kitchen line}",
    "GS25 광안목화점 · 엘모텔: L MOTEL: elev-leaves x2 {d5.9 no desk, doorlock, parcel lockers, seating; 14-deep box} | GS25: ctr x2, POS, steamer, mw x2, hotwater, ATM, fridge, gond, cig cab; CCTV {d14.9 no ice-cream chest, window eat-in bar}",
    "광안 조개구이: SideShop · 조개구이: clam 5 {d2.4 no POS/cashier, counter, kitchen line, restroom door; very sparse} | 광안 조개구이: 28st, 7tb, 7 grilltb; fridge {d11.3 no POS/cashier, counter, kitchen line}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "TERRASTAR OCEAN: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance",
    "테라스타오션: Destination \"테라스타오션\"",
    "조개구이 바다마을: no AutoDoor (open shutter front), ShopLife grill",
    "L MOTEL: ShopLife lobby lobby -> annexLink \"올라가기\" to an Annex building instance",
    "광안 조개구이: no AutoDoor (open shutter front), ShopLife grill"
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "테라스타오션: TERRASTAR OCEAN: lobby is a 14-deep box with flat elevator leaves",
    "GS25 광안목화점 · 엘모텔: L MOTEL: very sparse (d5.9); lobby is a 14-deep box with flat elevator leaves",
    "광안 조개구이: SideShop · 조개구이: very sparse (d2.4)"
   ],
   "realWorld": [
    "types: cafe, residence, realty, pocha, dessert, noodle, grill, lobby, cvs — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: cafe, residence, realty, pocha, dessert, noodle, grill, lobby, cvs — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간09 광안로61번길 ~ 광안해변로241번길 (6 bldg, 10 shops, 1 empty shells)",
   "path": "Workspace.Gwangalli.beachfront.구간09 광안로61번길 ~ 광안해변로241번길",
   "bounds": "(-1127,6.5,62)..(-722,167.0,157)",
   "rooms": [
    {
     "name": "SideShop · 치킨 & 맥주 [chicken]",
     "center": [
      -1117,
      6.8,
      102
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "베이커리 해변 [bakery]",
     "center": [
      -1075,
      6.8,
      76
     ],
     "size": [
      31,
      10,
      16
     ]
    },
    {
     "name": "OCEAN RESIDENCE [residence]",
     "center": [
      -1049,
      6.8,
      76
     ],
     "size": [
      18,
      11,
      14
     ]
    },
    {
     "name": "광안 치킨 & 맥주 [EMPTY SHELL]",
     "center": [
      -1106,
      6.5,
      74
     ],
     "size": [
      31,
      13.4,
      16
     ]
    },
    {
     "name": "동면식밀면 [noodle]",
     "center": [
      -1023,
      6.8,
      80
     ],
     "size": [
      22,
      10,
      18
     ]
    },
    {
     "name": "광안리 테이스티 [grill]",
     "center": [
      -996,
      6.8,
      82
     ],
     "size": [
      27,
      10,
      19
     ]
    },
    {
     "name": "CASA BUSANO TERRACE [cafe]",
     "center": [
      -949,
      6.8,
      92
     ],
     "size": [
      64,
      10,
      19
     ]
    },
    {
     "name": "STARBUCKS [cafe]",
     "center": [
      -835,
      6.8,
      106
     ],
     "size": [
      73,
      12,
      28
     ]
    },
    {
     "name": "ORANGEPADA [retail]",
     "center": [
      -781,
      6.8,
      92
     ],
     "size": [
      27,
      10,
      14
     ]
    },
    {
     "name": "SideShop · I AM BUSAN [bakery; ShopLife retail]",
     "center": [
      -730,
      6.8,
      122
     ],
     "size": [
      34,
      11,
      10
     ]
    },
    {
     "name": "I AM BUSAN [bakery; ShopLife retail]",
     "center": [
      -744,
      6.8,
      95
     ],
     "size": [
      42,
      11,
      16
     ]
    }
   ],
   "props": [
    "광안 오션 레지던스: SideShop · 치킨 & 맥주: 8ch, 2tb; kiosk, pass {d10.7 no counter, restroom door} | 베이커리 해변: 2ch, 1tb; ctr, POS, disp case {d7.5} | OCEAN RESIDENCE: elev-leaves x4, mailbox x6 {d9.8 no desk, doorlock, parcel lockers, seating; 14-deep box}",
    "광안리 테이스티: 동면식밀면: 16ch, 4tb; pass {d16.6 no POS/cashier, counter} | 광안리 테이스티: 12st, 3tb, 3 grilltb; fridge {d9.7 no POS/cashier, counter, kitchen line}",
    "까사부사노 테라스 · 광안어썸: CASA BUSANO TERRACE: 8ch, 4tb; ctr x2, POS, esp, grd, pastry case, wallshelf {d6.5 no menu board, pickup counter, ice/blender}",
    "스타벅스 광안리점: STARBUCKS: 8ch, 21st, 6seat, banquette, 3tb, window bar; ctr x2, POS x2, esp x2, grd, pastry case, MD shelf {d11.8 no ice/blender}",
    "오랜지바다 (ORANGEPADA): ORANGEPADA: ctr, POS; CCTV {d7.0}",
    "아이엠부산 광안리점: SideShop · I AM BUSAN: ctr, POS, disp case {d5.4 no restroom door} | I AM BUSAN: 2ch, 1tb; ctr, POS, disp case {d5.5}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "OCEAN RESIDENCE: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance",
    "STARBUCKS: Work-sim cafe \"starbucks\", Career.Cafe NPC customers, Manager; WorkCafe.LAYOUT offsets in Destination frame (-833.8,10.95,83.2) look (0.054,0,-0.999) (front counter local z 29-31, lane 32.3, back counter 35-36) — keep bar/POS/espresso in place",
    "스타벅스 광안리점: Destination \"스타벅스 광안리점\"",
    "SideShop · I AM BUSAN: ShopLife classifies it retail/souvenir by name, but it is stocked with bread/pastry",
    "I AM BUSAN: ShopLife classifies it retail/souvenir by name, but it is stocked with bread/pastry"
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "광안 오션 레지던스: OCEAN RESIDENCE: lobby is a 14-deep box with flat elevator leaves | 광안 치킨 & 맥주: EMPTY — working AutoDoor into an unlit void ~31x16, no floor/walls/ceiling/props; not ShopLife; Annex puts no prompt here (leaves are under the AutoDoor model)",
    "아이엠부산 광안리점: SideShop · I AM BUSAN: very sparse (d5.4) | I AM BUSAN: very sparse (d5.5)"
   ],
   "realWorld": [
    "types: chicken, bakery, residence, empty, noodle, grill, cafe, retail — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: chicken, bakery, residence, empty, noodle, grill, cafe, retail — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간08 광안로 (만남의 광장) ~ 광안로61번길 (5 bldg, 9 shops, 2 empty shells)",
   "path": "Workspace.Gwangalli.beachfront.구간08 광안로 (만남의 광장) ~ 광안로61번길",
   "bounds": "(-691,6.5,86)..(-290,112.3,181)",
   "rooms": [
    {
     "name": "SideShop · BILLBOARD CAFE [cafe]",
     "center": [
      -682,
      6.8,
      127
     ],
     "size": [
      32,
      10,
      10
     ]
    },
    {
     "name": "BILLBOARD CAFE [cafe]",
     "center": [
      -664,
      6.8,
      100
     ],
     "size": [
      47,
      10,
      19
     ]
    },
    {
     "name": "PASCUCCI [dessert]",
     "center": [
      -554,
      6.8,
      113
     ],
     "size": [
      76,
      11,
      24
     ]
    },
    {
     "name": "SUBWAY 부산광안비치점 [burger]",
     "center": [
      -464,
      6.8,
      107
     ],
     "size": [
      31,
      10,
      18
     ]
    },
    {
     "name": "비치용품 · 튜브대여 [EMPTY SHELL]",
     "center": [
      -497,
      6.5,
      104
     ],
     "size": [
      33,
      13.4,
      14
     ]
    },
    {
     "name": "THEME TOWER [residence]",
     "center": [
      -437,
      6.8,
      106
     ],
     "size": [
      16,
      11,
      14
     ]
    },
    {
     "name": "광안 기념품샵 PORT [EMPTY SHELL]",
     "center": [
      -413,
      6.5,
      103
     ],
     "size": [
      31,
      13.4,
      6
     ]
    },
    {
     "name": "SideShop · OLIVE YOUNG [retail]",
     "center": [
      -298,
      6.8,
      143
     ],
     "size": [
      34,
      11,
      10
     ]
    },
    {
     "name": "WORKING HOLIDAY [pub]",
     "center": [
      -349,
      6.8,
      110
     ],
     "size": [
      18,
      11,
      19
     ]
    },
    {
     "name": "MAD DOGS [pub]",
     "center": [
      -329,
      6.8,
      110
     ],
     "size": [
      18,
      11,
      18
     ]
    },
    {
     "name": "OLIVE YOUNG [retail]",
     "center": [
      -305,
      6.8,
      113
     ],
     "size": [
      27,
      11,
      22
     ]
    }
   ],
   "props": [
    "부산 광안리 빌보드: SideShop · BILLBOARD CAFE: 9st, window bar; ctr, POS, esp, grd {d16.9 no pastry case, menu board, pickup counter, ice/blender, restroom door} | BILLBOARD CAFE: 8ch, 4tb; ctr x2, POS, esp, grd, pastry case, wallshelf {d8.8 no menu board, pickup counter, ice/blender}",
    "파스쿠찌 센트로 광안리점: PASCUCCI: 24st, 3seat, banquette, 2tb, window bar; ctr x2, POS, esp, grd, pastry case, wallshelf {d7.0}",
    "광안샤인빌딩: SUBWAY 부산광안비치점: 4ch, 4st, 2tb, window bar; ctr x2, POS, oven x2, fridge {d16.2}",
    "테마타워: THEME TOWER: elev-leaves x4, mailbox x6 {d11.1 no desk, doorlock, parcel lockers, seating; 14-deep box}",
    "광안해변로 235 (올리브영 광안비치점): SideShop · OLIVE YOUNG: ctr, POS x2, cashier, mirror, tester table, wall bay x2; CCTV {d14.1} | WORKING HOLIDAY: 4ch, 2tb; ctr x2, POS, esp, grd, wallshelf {d16.7 no kitchen line, menu board} | MAD DOGS: 4ch, 1tb; pass; spoon boxes {d6.1 no POS/cashier, counter} | OLIVE YOUNG: ctr, POS x2, cashier, mirror, tester table, wall bay x2; CCTV {d10.3}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "THEME TOWER: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance"
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "광안샤인빌딩: 비치용품 · 튜브대여: EMPTY — working AutoDoor into an unlit void ~33x14, no floor/walls/ceiling/props; not ShopLife; Annex puts no prompt here (leaves are under the AutoDoor model)",
    "테마타워: THEME TOWER: lobby is a 14-deep box with flat elevator leaves | 광안 기념품샵 PORT: EMPTY — working AutoDoor into an unlit void ~31x6, no floor/walls/ceiling/props; not ShopLife; Annex puts no prompt here (leaves are under the AutoDoor model)"
   ],
   "realWorld": [
    "types: cafe, dessert, burger, empty, residence, retail, pub — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: cafe, dessert, burger, empty, residence, retail, pub — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간07 kent ~ 광안로 (만남의 광장) (1 bldg, 2 shops)",
   "path": "Workspace.Gwangalli.beachfront.구간07 kent ~ 광안로 (만남의 광장)",
   "bounds": "(-239,6.5,98)..(-208,96.2,169)",
   "rooms": [
    {
     "name": "SideShop · PHOTO & CLAW [claw]",
     "center": [
      -232,
      6.8,
      138
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "인형뽑기 [claw]",
     "center": [
      -223,
      6.8,
      111
     ],
     "size": [
      27,
      10,
      16
     ]
    }
   ],
   "props": [
    "만남의광장 빌딩: SideShop · PHOTO & CLAW: claw machines x9, change machine; CCTV {d17.1} | 인형뽑기: claw machines x10, change machine; CCTV {d14.5}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "SideShop · PHOTO & CLAW: not a ShopLife shop (claw arcade, no type)",
    "인형뽑기: not a ShopLife shop (claw arcade, no type)"
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props"
   ],
   "realWorld": [
    "types: claw — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: claw — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간05 광남로142번길 ~ 광안해변로209번길 (6 bldg, 15 shops)",
   "path": "Workspace.Gwangalli.beachfront.구간05 광남로142번길 ~ 광안해변로209번길",
   "bounds": "(388,6.5,78)..(812,127.2,170)",
   "rooms": [
    {
     "name": "SideShop · CAFE HAUTE [cafe]",
     "center": [
      396,
      6.8,
      132
     ],
     "size": [
      34,
      11,
      10
     ]
    },
    {
     "name": "광안 기념품 [retail]",
     "center": [
      402,
      6.8,
      107
     ],
     "size": [
      24,
      11,
      14
     ]
    },
    {
     "name": "CAFE HAUTE [cafe]",
     "center": [
      437,
      6.8,
      109
     ],
     "size": [
      42,
      11,
      20
     ]
    },
    {
     "name": "진미횟집 [rawfish]",
     "center": [
      486,
      6.8,
      112
     ],
     "size": [
      50,
      10,
      18
     ]
    },
    {
     "name": "씨앗호떡 [dessert]",
     "center": [
      528,
      6.8,
      104
     ],
     "size": [
      22,
      10,
      16
     ]
    },
    {
     "name": "광안 밀면 [noodle]",
     "center": [
      554,
      6.8,
      104
     ],
     "size": [
      26,
      10,
      18
     ]
    },
    {
     "name": "광안리 호텔1 [lobby]",
     "center": [
      587,
      6.8,
      101
     ],
     "size": [
      33,
      13,
      14
     ]
    },
    {
     "name": "HOTEL 1  CAFE & LOUNGE [cafe]",
     "center": [
      627,
      6.8,
      102
     ],
     "size": [
      44,
      12,
      19
     ]
    },
    {
     "name": "네모네 [cafe]",
     "center": [
      666,
      6.8,
      107
     ],
     "size": [
      26,
      10,
      19
     ]
    },
    {
     "name": "조새호 [soup]",
     "center": [
      694,
      6.8,
      105
     ],
     "size": [
      26,
      10,
      18
     ]
    },
    {
     "name": "광연이포차 [pocha]",
     "center": [
      730,
      6.8,
      104
     ],
     "size": [
      42,
      10,
      19
     ]
    },
    {
     "name": "SideShop · 광안 오징어 [seafood]",
     "center": [
      804,
      6.8,
      121
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "와플 & 젤라또 [dessert]",
     "center": [
      761,
      6.8,
      94
     ],
     "size": [
      15,
      10,
      16
     ]
    },
    {
     "name": "CITY NINE [residence]",
     "center": [
      776,
      6.8,
      92
     ],
     "size": [
      11,
      11,
      14
     ]
    },
    {
     "name": "광안 오징어 [seafood]",
     "center": [
      796,
      6.8,
      93
     ],
     "size": [
      24,
      10,
      18
     ]
    }
   ],
   "props": [
    "카페오뜨 광안비치점: SideShop · CAFE HAUTE: 4ch, 2tb; ctr, POS, esp, grd {d14.1 no pastry case, menu board, pickup counter, ice/blender, restroom door} | 광안 기념품: ctr, POS; CCTV {d7.7} | CAFE HAUTE: 8ch, 2seat, banquette, 5tb; ctr x2, POS, esp, grd, pastry case, wallshelf {d11.2 no menu board, pickup counter, ice/blender}",
    "진미횟집: 진미횟집: 24st, 6tb; ctr, board, tank {d6.6 no POS/cashier}",
    "광안해변 205빌딩: 씨앗호떡: 2ch, 1tb; disp case {d9.1 no POS/cashier, counter} | 광안 밀면: 8ch, 8cush, 4tb; pass {d10.1 no POS/cashier, counter}",
    "광안리 호텔1: 광안리 호텔1: 2seat; monitor x2, elev-leaves x4, desk {d8.7 no doorlock, parcel lockers; 14-deep box} | HOTEL 1  CAFE & LOUNGE: 8ch, 4tb; ctr x2, POS, esp, grd, pastry case, wallshelf {d9.8 no menu board, pickup counter, ice/blender}",
    "비치비키니: 네모네: 6st, window bar; ctr x2, POS, esp, grd, wallshelf {d10.4 no pastry case, menu board, pickup counter, ice/blender} | 조새호: 16st, 4tb; pass {d10.7 no POS/cashier, counter} | 광연이포차: 28st, 7tb, 7 grilltb; fridge {d11.6 no POS/cashier, counter, kitchen line}",
    "시티나인: SideShop · 광안 오징어: tank {d2.5 no POS/cashier, counter, kitchen line, restroom door; very sparse} | 와플 & 젤라또: ctr, POS, gelato tubs x8, waffle iron, disp case {d15.0} | CITY NINE: elev-leaves x2 {d4.4 no desk, doorlock, parcel lockers, seating; 14-deep box} | 광안 오징어: 8st, 2tb; ctr, board, tank {d6.5 no POS/cashier}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "광안리 호텔1: ShopLife lobby lobby -> annexLink \"올라가기\" to an Annex building instance",
    "광연이포차: no AutoDoor (open shutter front), ShopLife pocha",
    "CITY NINE: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance"
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "광안리 호텔1: 광안리 호텔1: lobby is a 14-deep box with flat elevator leaves",
    "시티나인: SideShop · 광안 오징어: very sparse (d2.5) | CITY NINE: very sparse (d4.4); lobby is a 14-deep box with flat elevator leaves"
   ],
   "realWorld": [
    "types: cafe, retail, rawfish, dessert, noodle, lobby, soup, pocha, seafood, residence — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: cafe, retail, rawfish, dessert, noodle, lobby, soup, pocha, seafood, residence — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간04 광남로120번길 ~ 광남로142번길 (8 bldg, 13 shops)",
   "path": "Workspace.Gwangalli.beachfront.구간04 광남로120번길 ~ 광남로142번길",
   "bounds": "(842,6.5,50)..(1257,205.7,163)",
   "rooms": [
    {
     "name": "SideShop · 조개찜 [seafood]",
     "center": [
      852,
      6.8,
      118
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "광안 조개찜 [seafood]",
     "center": [
      865,
      6.8,
      90
     ],
     "size": [
      42,
      10,
      18
     ]
    },
    {
     "name": "THURSDAY PARTY [pub]",
     "center": [
      910,
      6.8,
      88
     ],
     "size": [
      42,
      10,
      19
     ]
    },
    {
     "name": "광안 곱창 [grill]",
     "center": [
      953,
      6.8,
      85
     ],
     "size": [
      38,
      10,
      19
     ]
    },
    {
     "name": "CAFE BAY [cafe]",
     "center": [
      987,
      6.8,
      89
     ],
     "size": [
      24,
      12,
      19
     ]
    },
    {
     "name": "HOTEL CENTRAL BAY [lobby]",
     "center": [
      1014,
      6.8,
      85
     ],
     "size": [
      27,
      13,
      14
     ]
    },
    {
     "name": "BEER BAT [pub]",
     "center": [
      1045,
      6.8,
      85
     ],
     "size": [
      31,
      12,
      19
     ]
    },
    {
     "name": "HAPPY MONK [pub]",
     "center": [
      1083,
      6.8,
      77
     ],
     "size": [
      40,
      10,
      19
     ]
    },
    {
     "name": "오뎅바 어묵 [snack]",
     "center": [
      1126,
      6.8,
      74
     ],
     "size": [
      35,
      10,
      19
     ]
    },
    {
     "name": "버거스테이션 [burger]",
     "center": [
      1169,
      6.8,
      70
     ],
     "size": [
      44,
      10,
      18
     ]
    },
    {
     "name": "SideShop · 하카타 라멘 [noodle]",
     "center": [
      1247,
      6.8,
      88
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "하카타 라멘 광안 [noodle]",
     "center": [
      1214,
      6.8,
      66
     ],
     "size": [
      40,
      10,
      18
     ]
    },
    {
     "name": "CAFE 181 · 15F [cafe]",
     "center": [
      1243,
      6.8,
      62
     ],
     "size": [
      16,
      11,
      14
     ]
    }
   ],
   "props": [
    "부단 빌딩: SideShop · 조개찜: tank {d2.6 no POS/cashier, counter, kitchen line, restroom door; very sparse} | 광안 조개찜: 16st, 4tb; ctr, board, tank {d5.8 no POS/cashier}",
    "썰스데이파티 광안리점: THURSDAY PARTY: 9st, 3seat, 1 booths, 3tb; ctr, taps x4, back bar, barshelf x3; TV {d8.6 no POS/cashier, menu board}",
    "취월 빌딩: 광안 곱창: 20st, 5tb, 5 grilltb; fridge {d9.9 no POS/cashier, counter, kitchen line}",
    "호텔 센트럴베이 광안리: CAFE BAY: 4st, window bar; ctr x2, POS, esp, grd, wallshelf {d9.9 no pastry case, menu board, pickup counter, ice/blender} | HOTEL CENTRAL BAY: 2seat; monitor x2, elev-leaves x4, desk {d10.7 no doorlock, parcel lockers; 14-deep box} | BEER BAT: 9st, 3seat, 1 booths, 3tb; ctr, taps x4, back bar, barshelf x3; TV {d11.7 no POS/cashier, menu board}",
    "해피몽크: HAPPY MONK: 9st, 3seat, 1 booths, 3tb; ctr, taps x4, back bar, barshelf x3; TV {d9.1 no POS/cashier, menu board}",
    "광안해변 185빌딩: 오뎅바 어묵: 9st, 3seat, 1 booths, 3tb; ctr, taps x4, back bar, barshelf x3; TV {d10.2 no POS/cashier}",
    "리코리카 · 로그인노래타운: 버거스테이션: 32ch, 8tb; kiosk, pass {d16.5 no counter}",
    "게스후 카페181 빌딩: SideShop · 하카타 라멘: 8ch, 2tb; pass {d10.2 no POS/cashier, counter, restroom door} | 하카타 라멘 광안: 30st, 6tb; ctr, pass {d13.3 no POS/cashier} | CAFE 181 · 15F: elev-leaves x4, mailbox x6 {d11.1 no POS/cashier, counter, espresso bar, pastry case, menu board, pickup counter, ice/blender, restroom door}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "HOTEL CENTRAL BAY: ShopLife lobby lobby -> annexLink \"올라가기\" to an Annex building instance",
    "호텔 센트럴베이 광안리: Destination \"호텔 센트럴베이\""
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "부단 빌딩: SideShop · 조개찜: very sparse (d2.6) | 광안 조개찜: very sparse (d5.8)",
    "호텔 센트럴베이 광안리: HOTEL CENTRAL BAY: lobby is a 14-deep box with flat elevator leaves"
   ],
   "realWorld": [
    "types: seafood, pub, grill, cafe, lobby, snack, burger, noodle — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: seafood, pub, grill, cafe, lobby, snack, burger, noodle — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간03 광남로94번길 ~ 광남로120번길 (8 bldg, 18 shops)",
   "path": "Workspace.Gwangalli.beachfront.구간03 광남로94번길 ~ 광남로120번길",
   "bounds": "(1285,6.5,8)..(1726,220.4,141)",
   "rooms": [
    {
     "name": "SideShop · 팔도통닭 [chicken]",
     "center": [
      1296,
      6.8,
      88
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "팔도통닭 [chicken]",
     "center": [
      1297,
      6.8,
      60
     ],
     "size": [
      19,
      10,
      18
     ]
    },
    {
     "name": "CASA BUSANO [cafe]",
     "center": [
      1320,
      6.8,
      58
     ],
     "size": [
      24,
      10,
      19
     ]
    },
    {
     "name": "FUZZY NAVEL [pub]",
     "center": [
      1357,
      6.8,
      62
     ],
     "size": [
      43,
      10,
      19
     ]
    },
    {
     "name": "라운지 바다 [cafe]",
     "center": [
      1396,
      6.8,
      52
     ],
     "size": [
      30,
      10,
      19
     ]
    },
    {
     "name": "BELIV A-PARK OCEAN [residence]",
     "center": [
      1419,
      6.8,
      47
     ],
     "size": [
      13,
      11,
      14
     ]
    },
    {
     "name": "7-ELEVEn [cvs]",
     "center": [
      1439,
      6.8,
      49
     ],
     "size": [
      22,
      10,
      22
     ]
    },
    {
     "name": "바다분식 [snack]",
     "center": [
      1467,
      6.8,
      45
     ],
     "size": [
      30,
      10,
      18
     ]
    },
    {
     "name": "COMPOSE COFFEE [cafe]",
     "center": [
      1502,
      6.8,
      42
     ],
     "size": [
      34,
      10,
      19
     ]
    },
    {
     "name": "OCEAN STAY [lobby]",
     "center": [
      1528,
      6.8,
      37
     ],
     "size": [
      13,
      11,
      14
     ]
    },
    {
     "name": "광안 해물포차 [pocha]",
     "center": [
      1560,
      6.8,
      42
     ],
     "size": [
      38,
      10,
      19
     ]
    },
    {
     "name": "츄러스 & 젤라또 [dessert]",
     "center": [
      1590,
      6.8,
      32
     ],
     "size": [
      17,
      10,
      16
     ]
    },
    {
     "name": "광안 탭하우스 [pub]",
     "center": [
      1610,
      6.8,
      31
     ],
     "size": [
      19,
      10,
      19
     ]
    },
    {
     "name": "SideShop · A TWOSOME PLACE [cafe]",
     "center": [
      1713,
      6.8,
      58
     ],
     "size": [
      34,
      11,
      10
     ]
    },
    {
     "name": "CAFE 051 [cafe]",
     "center": [
      1638,
      6.8,
      36
     ],
     "size": [
      28,
      11,
      19
     ]
    },
    {
     "name": "GWANGAN JIWELL [residence]",
     "center": [
      1660,
      6.8,
      31
     ],
     "size": [
      13,
      12,
      14
     ]
    },
    {
     "name": "BINGBING [dessert]",
     "center": [
      1676,
      6.8,
      30
     ],
     "size": [
      15,
      11,
      16
     ]
    },
    {
     "name": "A TWOSOME PLACE [cafe]",
     "center": [
      1700,
      6.8,
      30
     ],
     "size": [
      30,
      11,
      20
     ]
    }
   ],
   "props": [
    "까사부사노 · 팔도통닭 · 퍼니비어: SideShop · 팔도통닭: 8ch, 2tb; kiosk, pass {d10.7 no counter, restroom door} | 팔도통닭: 16ch, 4tb; kiosk, pass {d19.7 no counter} | CASA BUSANO: 4st, window bar; ctr x2, POS, esp, grd, wallshelf {d10.5 no pastry case, menu board, pickup counter, ice/blender}",
    "퍼지네이블 · 컵앤컵: FUZZY NAVEL: 9st, 3seat, 1 booths, 3tb; ctr, taps x4, back bar, barshelf x3; TV {d8.4 no POS/cashier, menu board}",
    "빌리브 광안에이파크오션: 라운지 바다: 6st, window bar; ctr x2, POS, esp, grd, pastry case, wallshelf {d10.1 no menu board, pickup counter, ice/blender} | BELIV A-PARK OCEAN: elev-leaves x4, mailbox x6 {d13.5 no desk, doorlock, parcel lockers, seating; 14-deep box} | 7-ELEVEn: ctr x2, POS, steamer, mw x2, hotwater, ATM, fridge, gond, cig cab; CCTV {d16.0 no window eat-in bar}",
    "바다분식: 바다분식: 20st, 5tb; pass {d11.6 no POS/cashier, counter}",
    "광안 오션스테이: COMPOSE COFFEE: 4ch, 2tb; ctr x2, POS, esp, grd, pastry case, wallshelf {d10.4 no menu board, pickup counter, ice/blender} | OCEAN STAY: monitor x2, elev-leaves x4, desk {d16.7 no doorlock, parcel lockers, seating; 14-deep box}",
    "바다향빌딩: 광안 해물포차: 20st, 5tb, 5 grilltb; fridge {d9.6 no POS/cashier, counter, kitchen line}",
    "광안비치빌딩: 츄러스 & 젤라또: gelato tubs x3, disp case {d9.9 no POS/cashier, counter} | 광안 탭하우스: 3st; ctr, taps x4, back bar, barshelf x3; TV {d9.3 no POS/cashier, menu board}",
    "광안지웰에스테이트: SideShop · A TWOSOME PLACE: 4ch, 2tb; ctr, POS, esp, grd {d13.9 no pastry case, menu board, pickup counter, ice/blender, restroom door} | CAFE 051: 6st, window bar; ctr x2, POS, esp, grd, wallshelf {d9.8 no pastry case, menu board, pickup counter, ice/blender} | GWANGAN JIWELL: elev-leaves x4, mailbox x6 {d13.5 no desk, doorlock, parcel lockers, seating; 14-deep box} | BINGBING: claw machines x7, change machine; CCTV {d18.6 no POS/cashier, counter, restroom door} | A TWOSOME PLACE: 4ch, 2seat, banquette, 3tb; ctr x2, POS, esp, grd, pastry case, wallshelf {d11.9 no menu board, pickup counter, ice/blender}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "BELIV A-PARK OCEAN: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance",
    "OCEAN STAY: ShopLife lobby lobby -> annexLink \"올라가기\" to an Annex building instance",
    "광안 해물포차: no AutoDoor (open shutter front), ShopLife pocha",
    "GWANGAN JIWELL: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance",
    "광안지웰에스테이트: Destination \"광안지웰에스테이트\""
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "빌리브 광안에이파크오션: BELIV A-PARK OCEAN: lobby is a 14-deep box with flat elevator leaves",
    "광안 오션스테이: OCEAN STAY: lobby is a 14-deep box with flat elevator leaves",
    "광안지웰에스테이트: GWANGAN JIWELL: lobby is a 14-deep box with flat elevator leaves"
   ],
   "realWorld": [
    "types: chicken, cafe, pub, residence, cvs, snack, lobby, pocha, dessert — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: chicken, cafe, pub, residence, cvs, snack, lobby, pocha, dessert — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간02 광안해변로141번길 ~ 광남로94번길 (8 bldg, 13 shops)",
   "path": "Workspace.Gwangalli.beachfront.구간02 광안해변로141번길 ~ 광남로94번길",
   "bounds": "(1748,6.5,-46)..(2157,115.1,75)",
   "rooms": [
    {
     "name": "SideShop · COFFEE IWA [cafe]",
     "center": [
      1760,
      6.8,
      44
     ],
     "size": [
      34,
      11,
      10
     ]
    },
    {
     "name": "COFFEE IWA [cafe]",
     "center": [
      1784,
      6.8,
      12
     ],
     "size": [
      66,
      11,
      20
     ]
    },
    {
     "name": "emart24 [cvs]",
     "center": [
      1828,
      6.8,
      8
     ],
     "size": [
      18,
      10,
      22
     ]
    },
    {
     "name": "광안 돼지국밥 [soup]",
     "center": [
      1852,
      6.8,
      4
     ],
     "size": [
      26,
      10,
      18
     ]
    },
    {
     "name": "파도횟집 [rawfish]",
     "center": [
      1887,
      6.8,
      5
     ],
     "size": [
      37,
      10,
      18
     ]
    },
    {
     "name": "BEANS BINS COFFEE [cafe]",
     "center": [
      1931,
      6.8,
      1
     ],
     "size": [
      46,
      10,
      19
     ]
    },
    {
     "name": "OLIVE YOUNG [retail]",
     "center": [
      1983,
      6.8,
      -11
     ],
     "size": [
      52,
      11,
      22
     ]
    },
    {
     "name": "해변포차 [pocha]",
     "center": [
      2034,
      6.8,
      -13
     ],
     "size": [
      37,
      10,
      19
     ]
    },
    {
     "name": "COFFEE LAB 149 [cafe]",
     "center": [
      2072,
      6.8,
      -24
     ],
     "size": [
      35,
      10,
      19
     ]
    },
    {
     "name": "BEACH STUDIO [residence]",
     "center": [
      2098,
      6.8,
      -30
     ],
     "size": [
      13,
      11,
      14
     ]
    },
    {
     "name": "SideShop · SUNSET PUB [pub]",
     "center": [
      2147,
      6.8,
      -5
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "비치용품 · 튜브대여 [retail]",
     "center": [
      2116,
      6.8,
      -32
     ],
     "size": [
      18,
      10,
      14
     ]
    },
    {
     "name": "SUNSET PUB [pub]",
     "center": [
      2138,
      6.8,
      -33
     ],
     "size": [
      22,
      10,
      19
     ]
    }
   ],
   "props": [
    "씨타워 (커피아이와): SideShop · COFFEE IWA: 9st, window bar; ctr, POS, esp, grd {d15.8 no pastry case, menu board, pickup counter, ice/blender, restroom door} | COFFEE IWA: 8ch, 2seat, banquette, 5tb; ctr x2, POS, esp, grd, pastry case, wallshelf {d7.1 no menu board, pickup counter, ice/blender}",
    "광안 오션하우스: emart24: ctr x2, POS, steamer, mw x2, hotwater, fridge, gond, cig cab; CCTV {d15.7 no ATM, ice-cream chest, window eat-in bar} | 광안 돼지국밥: 8ch, 8cush, 4tb; pass {d10.1 no POS/cashier, counter}",
    "파도횟집: 파도횟집: 16st, 4tb; ctr, board, tank {d6.6 no POS/cashier}",
    "빈스빈스 광안리점: BEANS BINS COFFEE: 12st, window bar; ctr x2, POS, esp, grd, pastry case, wallshelf {d8.6 no menu board, pickup counter, ice/blender}",
    "올리브영 광안리점: OLIVE YOUNG: ctr, POS x2, cashier, mirror, tester table, gond x2, wall bay x3; CCTV {d9.4}",
    "해변포차 151: 해변포차: 20st, 5tb, 5 grilltb; fridge {d9.9 no POS/cashier, counter, kitchen line}",
    "광안비치 스튜디오: COFFEE LAB 149: 8st, window bar; ctr x2, POS, esp, grd, pastry case, wallshelf {d9.5 no menu board, pickup counter, ice/blender} | BEACH STUDIO: elev-leaves x4, mailbox x6 {d13.1 no desk, doorlock, parcel lockers, seating; 14-deep box}",
    "남천 비치하우스: SideShop · SUNSET PUB: 9st, 2tb; ctr, taps x4, back bar, barshelf x3; TV {d16.7 no POS/cashier, menu board, restroom door} | 비치용품 · 튜브대여: ctr, POS; CCTV {d9.9} | SUNSET PUB: 4st, 3seat, 1 booths, 1tb; ctr, taps x4, back bar, barshelf x3; TV {d11.5 no POS/cashier, menu board}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "해변포차: no AutoDoor (open shutter front), ShopLife pocha",
    "BEACH STUDIO: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance"
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "광안비치 스튜디오: BEACH STUDIO: lobby is a 14-deep box with flat elevator leaves"
   ],
   "realWorld": [
    "types: cafe, cvs, soup, rawfish, retail, pocha, residence, pub — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: cafe, cvs, soup, rawfish, retail, pocha, residence, pub — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "beachfront 구간01 edge ~ 광안해변로141번길 (3 bldg, 13 shops)",
   "path": "Workspace.Gwangalli.beachfront.구간01 edge ~ 광안해변로141번길",
   "bounds": "(2180,6.5,-91)..(2465,164.2,16)",
   "rooms": [
    {
     "name": "SideShop · 수제버거 [burger]",
     "center": [
      2192,
      6.8,
      -13
     ],
     "size": [
      34,
      10,
      10
     ]
    },
    {
     "name": "광안 수제버거 [burger]",
     "center": [
      2190,
      6.8,
      -40
     ],
     "size": [
      14,
      10,
      18
     ]
    },
    {
     "name": "MEGA COFFEE [cafe]",
     "center": [
      2209,
      6.8,
      -43
     ],
     "size": [
      20,
      10,
      19
     ]
    },
    {
     "name": "남천 해물칼국수 [noodle]",
     "center": [
      2238,
      6.8,
      -47
     ],
     "size": [
      34,
      10,
      18
     ]
    },
    {
     "name": "SideShop · 태양공인중개사 [realty]",
     "center": [
      2454,
      6.8,
      -48
     ],
     "size": [
      34,
      8,
      10
     ]
    },
    {
     "name": "남천 해장국 [soup]",
     "center": [
      2282,
      6.8,
      -38
     ],
     "size": [
      34,
      8,
      18
     ]
    },
    {
     "name": "협진태양맨션 2 [residence]",
     "center": [
      2308,
      6.8,
      -44
     ],
     "size": [
      14,
      9,
      14
     ]
    },
    {
     "name": "바다슈퍼 [cvs]",
     "center": [
      2331,
      6.8,
      -43
     ],
     "size": [
      28,
      8,
      22
     ]
    },
    {
     "name": "남천 크린세탁 [laundry]",
     "center": [
      2357,
      6.8,
      -55
     ],
     "size": [
      22,
      8,
      6
     ]
    },
    {
     "name": "협진태양맨션 [residence]",
     "center": [
      2377,
      6.8,
      -54
     ],
     "size": [
      14,
      9,
      14
     ]
    },
    {
     "name": "남천 로스터리 [cafe]",
     "center": [
      2400,
      6.8,
      -55
     ],
     "size": [
      28,
      8,
      19
     ]
    },
    {
     "name": "해변약국 [pharmacy]",
     "center": [
      2424,
      6.8,
      -57
     ],
     "size": [
      16,
      8,
      22
     ]
    },
    {
     "name": "태양공인중개사 [realty]",
     "center": [
      2445,
      6.8,
      -68
     ],
     "size": [
      24,
      8,
      6
     ]
    }
   ],
   "props": [
    "오션빌: SideShop · 수제버거: 8ch, 2tb; kiosk, pass {d10.7 no counter, restroom door} | 광안 수제버거: 4ch, 1tb; kiosk, pass; spoon boxes {d8.5 no counter, restroom door} | MEGA COFFEE: 4st, window bar; ctr x2, POS, esp, grd, wallshelf {d12.1 no pastry case, menu board, pickup counter, ice/blender}",
    "남천해변빌딩: 남천 해물칼국수: 12ch, 8cush, 5tb; pass {d10.4 no POS/cashier, counter}",
    "협진태양맨션: SideShop · 태양공인중개사: 2ch, 1tb; ctr, monitor {d4.6} | 남천 해장국: 20ch, 5tb {d12.8 no POS/cashier, counter, kitchen line} | 협진태양맨션 2: elev-leaves x4, mailbox x6 {d12.4 no desk, doorlock, parcel lockers, seating; 14-deep box} | 바다슈퍼: ctr x2, POS, steamer, mw x2, hotwater, ATM, fridge x2, gond x2, cig cab; CCTV {d17.2 no window eat-in bar} | 남천 크린세탁: 1ch, 1tb {d6.4} | 협진태양맨션: elev-leaves x4, mailbox x6 {d12.4 no desk, doorlock, parcel lockers, seating; 14-deep box} | 남천 로스터리: 6st, window bar; ctr x2, POS, esp, grd, wallshelf {d9.7 no pastry case, menu board, pickup counter, ice/blender} | 해변약국: ctr, POS, gond, Rx cabinet, drug shelf {d16.5} | 태양공인중개사: 1ch, 1tb {d5.8}"
   ],
   "gameplay": [
    "every shop: ShopLife street shop + ShopStaff anchor + AutoDoor + StreetSigns (see notes); specifics:",
    "협진태양맨션 2: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance",
    "협진태양맨션: ShopLife residence lobby -> annexLink \"올라가기\" to an Annex building instance"
   ],
   "emptyOrCrude": [
    "all shops: GLOBAL CRUDENESS in notes; per-shop {d=density, no=type-specific misses} in props",
    "협진태양맨션: SideShop · 태양공인중개사: very sparse (d4.6) | 협진태양맨션 2: lobby is a 14-deep box with flat elevator leaves | 협진태양맨션: lobby is a 14-deep box with flat elevator leaves | 태양공인중개사: very sparse (d5.8)"
   ],
   "realWorld": [
    "types: burger, cafe, noodle, realty, soup, residence, cvs, laundry, pharmacy — per-type Korean checklists in notes (REAL-WORLD CHECKLISTS); full lines in bld/districts.json"
   ],
   "interactionIdeas": [
    "types: burger, cafe, noodle, realty, soup, residence, cvs, laundry, pharmacy — per-type ideas in notes (INTERACTION IDEAS)"
   ],
   "enterable": true
  },
  {
   "name": "광안 중앙병원 (외래 로비)",
   "path": "Workspace.Gwangalli.uptown.RowC_광남로-수영로.Landmarks.광안 중앙병원",
   "bounds": "(721.3,6.4,704.3)..(840.8,124.6,797.6)",
   "rooms": [
    {
     "name": "외래 로비 1F (원무과·약제과·안내)",
     "center": [
      772.2,
      6.8,
      749.3
     ],
     "size": [
      99,
      14,
      86
     ]
    }
   ],
   "props": [
    "Interior_로비: Product 65, WaitingBackRow 5, WaitingSeatRow 5, Board 3, PriceRail 3, WaitingBeam 3 …",
    "shell 외래 로비: Floor 95x82, Ceiling at 20.8, 20 CeilingLight, BackWall/SideWall, 14 ShopWindow + AutoDoor (front) + AutoDoor_Side (ER side, OpenRadius 12)",
    "outside: ER canopy, AmbulanceLane, Car_Ambulance (Kia Carnival)"
   ],
   "gameplay": [
    "LANDMARK RULES (notes)",
    "Destination \"광안 중앙병원\"; Ems/Hospital gameplay (Law/Hospital.luau scans Door_/AutoDoor models; GwangalliBuildings Hospital service is a separate built hospital) — keep AutoDoor names",
    "Citizens/Nav point"
   ],
   "emptyOrCrude": [
    "huge 95x82 hall with only 5 waiting bench rows (22 studs long), 3 single chairs, 1 InfoDesk box, 2 desks (원무과/약제과) as single boxes, one LEDScreen; 65 \"Product\" parts = a pharmacy shelf",
    "no 진료과 corridors/consult rooms, no 접수 번호표 기계, no 수납 kiosks, no wheelchairs, no water purifier, no TV, no signage wayfinding floor stripes",
    "ElevatorDoor x2 are flat leaves on the back wall; upper 9 floors are facade (RoomDepth fake rooms)"
   ],
   "realWorld": [
    "원무과 접수·수납 카운터(번호표 발권기, 대기번호 LED, 수납 키오스크 3~4대)",
    "대기 의자 열(연결형 철제 의자) + 진료과 안내 사인(내과/정형외과/영상의학과) + 바닥 유도선",
    "약제과 처방전 접수/수령 창구, 휠체어 보관대, 손소독제, 정수기, 자판기"
   ],
   "interactionIdeas": [
    "번호표 뽑기 → 대기 LED 호출 → 접수·수납",
    "처방전 → 약제과 수령, 휠체어 빌리기",
    "EMS 플레이(구급차 하차 → 응급실)"
   ],
   "enterable": true
  },
  {
   "name": "광안동우체국 (우편 창구)",
   "path": "Workspace.Gwangalli.uptown.RowC_광남로-수영로.Landmarks.광안동우체국",
   "bounds": "(37.6,6.4,563.8)..(107.6,53.0,634.9)",
   "rooms": [
    {
     "name": "우편 창구 1F",
     "center": [
      72.7,
      6.8,
      604
     ],
     "size": [
      64,
      13,
      54
     ]
    }
   ],
   "props": [
    "Interior_창구: Product 27, Seat 7, ChairBack 4, BackCushion 3, Board 3, PriceRail 3 …",
    "shell: Floor 64x54, Ceiling, 9 CeilingLight, 4 ShopWindow, AutoDoor"
   ],
   "gameplay": [
    "LANDMARK RULES (notes)",
    "Destination \"광안동우체국\""
   ],
   "emptyOrCrude": [
    "one CounterScreen box + one WritingDesk, 7 seats, a PostATM, ParcelScale and a 27-product shelf in a 64x54 room — mostly empty floor",
    "no 번호표 발권기/대기 LED is wired (one LEDScreen), no 택배 상자 판매대, no 우체국 금융 창구 split, no posters/notice boards"
   ],
   "realWorld": [
    "창구 4~6개(우편/택배/금융) + 번호표 발권기·대기 LED",
    "포장대(테이프·가위·뽁뽁이), 택배 박스 판매대, 우편함(빨간 우체통 외부)",
    "우체국 ATM, 기념우표 진열, 대기 의자"
   ],
   "interactionIdeas": [
    "번호표 → 택배 접수(무게 측정 → 요금)",
    "포장대에서 박스 포장",
    "ATM 입출금"
   ],
   "enterable": true
  },
  {
   "name": "스타벅스 광안역점 (매장)",
   "path": "Workspace.Gwangalli.uptown.RowC_광남로-수영로.Landmarks.스타벅스 광안역점",
   "bounds": "(-244.5,6.5,747.4)..(-178.7,85.6,814.3)",
   "rooms": [
    {
     "name": "매장 1F",
     "center": [
      -211.5,
      6.8,
      778.4
     ],
     "size": [
      63,
      14,
      59
     ]
    }
   ],
   "props": [
    "Interior_매장: ChairLeg 32, ChairBack 12, Seat 12, TableFoot 4, TableTop 4, TableLeg 4 …",
    "shell: Floor 63x59 (13.8 ceiling), 12 CeilingLight, 9 ShopWindow, AutoDoor; 2F sign only"
   ],
   "gameplay": [
    "LANDMARK RULES (notes)",
    "Destination \"스타벅스 광안역점\" — NOT the Work sim store (that is beachfront 스타벅스 광안리점)"
   ],
   "emptyOrCrude": [
    "63x59 store with only 4 tables/12 chairs, 1 counter box, 2 EspressoMachine, 1 PastryCase, 1 window bar — ~80% bare floor",
    "no POS/order screen parts, no pickup counter, no condiment bar, no MD wall, no menu board lighting (one sign), no restroom"
   ],
   "realWorld": [
    "주문대: POS 2대·카드단말기·진동벨 충전대(또는 키오스크)",
    "바: 2~3그룹 에스프레소 머신+그라인더·제빙기·블렌더·온수기·싱크",
    "냉장 디저트 쇼케이스, 픽업대(번호 디스플레이) + 퇴식대(분리수거)"
   ],
   "interactionIdeas": [
    "키오스크/POS 주문 → 진동벨 → 픽업대 수령",
    "퇴식대 반납·분리수거, 창가 바 착석",
    "MD 텀블러 구매, 화장실 비번"
   ],
   "enterable": true
  },
  {
   "name": "BNK부산은행 광안동지점 (영업점)",
   "path": "Workspace.Gwangalli.uptown.RowC_광남로-수영로.Landmarks.BNK부산은행 광안동지점",
   "bounds": "(-376.6,6.5,740.2)..(-306.3,89.0,812.3)",
   "rooms": [
    {
     "name": "영업점 1F + ATM 코너",
     "center": [
      -341.4,
      6.8,
      774.2
     ],
     "size": [
      68,
      14,
      63
     ]
    }
   ],
   "props": [
    "Interior_영업점: Seat 11, BackCushion 6, ChairBack 5, Arm 4, ATMTopper 3, ATMScreen 3 …",
    "shell: Floor 68x63, 9 CeilingLight, 2 AutoDoor (ATM corner + branch)"
   ],
   "gameplay": [
    "LANDMARK RULES (notes)",
    "Destination \"BNK부산은행 광안동지점\"; GwangalliGameplay Bank.luau does not reference this branch (banking is UI-only) — room is free to redesign"
   ],
   "emptyOrCrude": [
    "one TellerScreen box for the whole counter line, 11 seats, 3 ATMs, 1 TicketMachine; huge empty floor",
    "no 창구 partitions/번호 표시, no 상담석 desks, no 금리 LED board, no 대여금고/vault door, no brochure rack"
   ],
   "realWorld": [
    "창구 6~8석(유리 칸막이·번호 표시) + 번호표 발권기",
    "대기 소파, 금리·환율 LED 보드, 상품 안내 리플렛 랙",
    "ATM 코너(24h, 별도 출입) + 공과금 수납기"
   ],
   "interactionIdeas": [
    "번호표 → 창구 입출금/대출 상담(Bank.luau)",
    "ATM 코너 24시간",
    "금고 강도 이벤트(문 잠금)"
   ],
   "enterable": true
  },
  {
   "name": "광안지구대 (민원실)",
   "path": "Workspace.Gwangalli.uptown.RowC_광남로-수영로.Landmarks.광안지구대 (부산수영경찰서)",
   "bounds": "(-395.5,6.4,560.5)..(-302.0,55.5,648.4)",
   "rooms": [
    {
     "name": "민원실 1F + 보호실",
     "center": [
      -334.6,
      6.8,
      612.6
     ],
     "size": [
      57,
      12,
      45
     ]
    }
   ],
   "props": [
    "Interior_민원실: CellBar 7, Seat 7, ChairBack 4, MonitorScreen 4, Monitor 4, DeskPanel 4 …",
    "shell: Floor 57x45 (11.8 ceiling), 6 CeilingLight, AutoDoor; outside 3 PoliceCar models, flags, fence"
   ],
   "gameplay": [
    "LANDMARK RULES (notes)",
    "Destination \"광안지구대\"; referenced by name in GwangalliLawShared and StreetInteract/Police (police NPC / arrest flows)"
   ],
   "emptyOrCrude": [
    "4 desks with monitors, 3 filing cabinets, 1 holding cell (7 bars + bench), counter glass — plausible but sparse; walls bare except 관할구역도/112 signs",
    "no 민원 대기석 rows, no 무전기 충전대, no 수갑/장비 lockers, no CCTV monitor wall, no 분실물 shelf"
   ],
   "realWorld": [
    "민원 접수 카운터(유리), 대기 의자, 분실물 보관함",
    "사무 책상(무전기·모니터), 상황판/관할구역도·CCTV 모니터 벽",
    "보호실(창살·벤치), 장비 보관함, 태극기/경찰 엠블럼"
   ],
   "interactionIdeas": [
    "분실물 신고/찾기(관광안내소 지갑 퀘스트와 연계)",
    "보호실 입감 연출",
    "112 신고 처리"
   ],
   "enterable": true
  },
  {
   "name": "홈플러스 익스프레스 광안점 (매장)",
   "path": "Workspace.Gwangalli.uptown.RowC_광남로-수영로.Landmarks.홈플러스 익스프레스 광안점",
   "bounds": "(-1459.0,6.4,499.5)..(-1326.6,38.3,613.4)",
   "rooms": [
    {
     "name": "매장 1F (2F 헬스 간판만)",
     "center": [
      -1394,
      6.8,
      563.5
     ],
     "size": [
      127,
      15,
      96
     ]
    }
   ],
   "props": [
    "Interior_매장: Products 42, GondolaCore 7, Belt 3, POS 3, CheckoutCounter 3, FridgeDoor 3 …",
    "shell: Floor 127x96 (14.8 ceiling), 15 CeilingLight, 2 AutoDoor"
   ],
   "gameplay": [
    "LANDMARK RULES (notes) (POS is a LOOSE anchor -> NPC 계산원)",
    "Citizens \"homeplus\" destination"
   ],
   "emptyOrCrude": [
    "127x96 supermarket with only 7 GondolaCore blocks (42 \"Products\" slabs), 3 checkouts, 3 fridge bodies, 2 produce tables — aisles are single boxes",
    "no 카트/바구니 stacks, no 정육/수산 counter, no 냉동 평대, no 행사 POP, no 시식대, no 셀프계산대"
   ],
   "realWorld": [
    "곤돌라 10~14열(카테고리 행거 사인) + 엔드캡 행사",
    "신선(과일·채소 진열대·미스트), 정육/수산 대면 코너, 냉장/냉동 평대",
    "계산대 4~6 + 셀프계산대, 카트·바구니, 배달 접수"
   ],
   "interactionIdeas": [
    "카트 밀기, 바구니 담기 → 계산",
    "시식 코너, 정육 주문"
   ],
   "enterable": true
  },
  {
   "name": "광안교회 (예배당)",
   "path": "Workspace.Gwangalli.uptown.RowC_광남로-수영로.Landmarks.광안교회 (대한예수교장로회)",
   "bounds": "(-2063.6,6.4,433.7)..(-1957.8,130.5,548.3)",
   "rooms": [
    {
     "name": "예배당 (1F sanctuary, 34 high)",
     "center": [
      -2028.5,
      6.9,
      498.8
     ],
     "size": [
      65,
      34,
      87
     ]
    }
   ],
   "props": [
    "Interior_예배당: PewBack 20, Pew 20, CeilingLight 8, AltarCross 2, Piano 1, Pulpit 1 …",
    "shell: FrontWall split into 2 pieces leaving an ~8.7-stud open doorway (no door), SideWall/BackWall 36 tall, 종탑 with neon cross"
   ],
   "gameplay": [
    "LANDMARK RULES (notes)",
    "Annex PUBLIC_WORDS \"교회\" -> one big room if Annex is used"
   ],
   "emptyOrCrude": [
    "20 pews + pulpit + piano + 2 altar crosses in a 65x87 hall; no 강대상 stage steps, no 성가대석, no 스크린/프로젝터, no 헌금함, no 주보 rack; plain walls (no stained glass, no 십자가 wall)",
    "doorway is just a gap in the wall"
   ],
   "realWorld": [
    "강대상 단상(계단)+십자가 벽, 성가대석, 피아노/드럼",
    "장의자 열 + 성경/찬송가 꽂이, 대형 스크린·프로젝터",
    "현관 로비(주보 rack, 헌금함, 신발장), 스테인드글라스"
   ],
   "interactionIdeas": [
    "예배 시간 이벤트(찬송 소리), 장의자 앉기",
    "피아노 연주"
   ],
   "enterable": true
  },
  {
   "name": "켄트호텔 광안리 by 켄싱턴 (로비 · GS25 · 2F 카페 · 15F 스카이라운지 · 루프탑 바)",
   "path": "Workspace.Gwangalli.landmarks.켄트호텔 광안리 by 켄싱턴 KENT HOTEL",
   "bounds": "(-207.2,6.0,102.0)..(-126.1,206.2,230.8)",
   "rooms": [
    {
     "name": "켄트호텔 로비",
     "center": [
      -147.6,
      6.8,
      137.4
     ],
     "size": [
      39,
      13,
      42
     ]
    },
    {
     "name": "GS25 광안해변점",
     "center": [
      -186.2,
      6.8,
      137
     ],
     "size": [
      36,
      12,
      42
     ]
    },
    {
     "name": "2F 카페",
     "center": [
      -166.3,
      23.2,
      122.7
     ],
     "size": [
      74,
      9,
      16
     ]
    },
    {
     "name": "15F 스카이라운지 SKY LOUNGE",
     "center": [
      -166.7,
      160.8,
      153.6
     ],
     "size": [
      78,
      13,
      81
     ]
    },
    {
     "name": "루프탑 바 ROOFTOP BAR",
     "center": [
      -166.7,
      175.3,
      153.9
     ],
     "size": [
      79,
      0,
      81
     ]
    }
   ],
   "props": [
    "켄트호텔 로비: Downlight 7, Arm 6, Seat 5, CoveLED 4, CoveSoffit 4, ElevatorDoor 4 …",
    "GS25 광안해변점: Bottle 160, Product 120, ChairLeg 16, DoorHandle 12, WireShelf 12, CeilingLight 9 …",
    "2F 카페: Chair 12, PendantShade 6, PendantCord 6, TableLeg 6, CafeTable 6, PendantBulb 6 …",
    "15F 스카이라운지 SKY LOUNGE: Product 87, Seat 26, Mullion 25, LoungeGlass 22, ChairLeg 14, ChairBack 14 …"
   ],
   "gameplay": [
    "LANDMARK RULES (notes)",
    "Destinations \"켄트호텔 광안리\", \"GS25 광안해변점 (켄트호텔 1F)\" (Citizens gs25_beach, Nav)",
    "GS25: PosBase x2 -> ShopStaff 편의점 점원; not a ShopLife \"venue\" (no Gondola_1/OpenChiller names)"
   ],
   "emptyOrCrude": [
    "로비 39x42: 1 sofa (3 seats) + 2 chairs, concierge desk, 4 ElevatorDoor leaves on the back wall, cove LED — no luggage room, no key-card kiosk, no art, plain floor",
    "GS25 36x42: 4 fridges (160 bottles), 3 shelves, 1 counter, cigarette cabinet, 1 ice-cream chest, 2 outdoor plastic tables — no ATM, no window eat-in bar, no 택배/복권, bare ceiling",
    "2F 카페 74x15 (8.9 ceiling): 6 tables/12 chairs, 1 pastry counter — unreachable (no stairs); 15F lounge (bar, back bar 87 bottles, sofa, 7 tables) and rooftop bar (6 tables/17 stools) also unreachable"
   ],
   "realWorld": [
    "프런트 데스크(PC·카드키 인코더·벨·명함), 뒤 로고 월",
    "로비 소파·사이드테이블, 벨카트·짐 보관",
    "엘리베이터 홀(호출버튼·층표시), 객실 안내도"
   ],
   "interactionIdeas": [
    "체크인 → 카드키 → 엘리베이터로 15F/루프탑 이동(정적 방을 실제로 쓰기)",
    "GS25 장보기(ShopLife pick flow를 붙이면 됨)",
    "스카이라운지 칵테일 주문"
   ],
   "enterable": true
  },
  {
   "name": "호텔 아쿠아펠리스 (로비 · fondx 홍미당 · 워터파크/찜질방 입구 · 6F 워터파크 · 8-9F 찜질방 · 루프탑 인피니티풀)",
   "path": "Workspace.Gwangalli.landmarks.호텔 아쿠아펠리스 HOTEL AQUA PALACE",
   "bounds": "(-120.8,6.0,103.0)..(36.7,276.5,231.2)",
   "rooms": [
    {
     "name": "주차장 입구",
     "center": [
      26.8,
      6.6,
      121.1
     ],
     "size": [
      16,
      0,
      8
     ]
    },
    {
     "name": "워터파크 · 스파 입구",
     "center": [
      -0.4,
      6.8,
      140.2
     ],
     "size": [
      38,
      13,
      46
     ]
    },
    {
     "name": "호텔 로비 Lobby",
     "center": [
      -42.3,
      6.8,
      140
     ],
     "size": [
      42,
      13,
      46
     ]
    },
    {
     "name": "fondx 홍미당 부산광안리점",
     "center": [
      -90.9,
      6.8,
      139.9
     ],
     "size": [
      52,
      13,
      46
     ]
    },
    {
     "name": "아쿠아펠리스 워터파크 6F",
     "center": [
      -15.4,
      67,
      169
     ],
     "size": [
      76,
      24,
      8
     ]
    },
    {
     "name": "아쿠아펠리스 찜질방 8F-9F",
     "center": [
      -41.4,
      103.5,
      139.5
     ],
     "size": [
      114,
      0,
      11
     ]
    },
    {
     "name": "루프탑 인피니티풀",
     "center": [
      -41.4,
      256.5,
      160.2
     ],
     "size": [
      116,
      0,
      58
     ]
    }
   ],
   "props": [
    "주차장 입구: Stripe 8, Floor 1, Void 1, Header 1, Driveway 1",
    "워터파크 · 스파 입구: ElevatorDoor 4, ElevatorJamb 4, Glass 3, CallButton 2, ElevatorHead 2, FloorIndicator 2 …",
    "호텔 로비 Lobby: Downlight 16, Crystal 8, Arm 6, Leaves 4, Seat 4, CoveLED 4 …",
    "fondx 홍미당 부산광안리점: Bread 45, Seat 16, Tray 12, ChairLeg 8, ChairBack 8, StoolLeg 8 …"
   ],
   "gameplay": [
    "LANDMARK RULES (notes)",
    "Destinations \"호텔 아쿠아펠리스\", \"fondx 홍미당 (아쿠아펠리스 1F)\", \"아쿠아펠리스 워터파크 · 찜질방\" (Citizens aqua)",
    "HomesFloors: 아쿠아펠리스 레지던스 penthouse units 20-25F (life-game housing, separate instances)",
    "홍미당 POS -> ShopStaff 빵집 직원"
   ],
   "emptyOrCrude": [
    "로비 42x46: chandelier + 4 seats + desk — sparse",
    "워터파크·스파 입구 38x46: only 4 ElevatorDoor leaves + 1 counter — an empty hall; the waterpark (6F) / 찜질방 (8-9F, 12 mats + 2 cedar walls) / rooftop pool exist as static rooms but nothing connects to them",
    "홍미당 51x46: 45 bread, 16 seats, 4 display tables — OK but no bakery kitchen/oven wall, no drinks fridge"
   ],
   "realWorld": [
    "프런트 데스크(PC·카드키 인코더·벨·명함), 뒤 로고 월",
    "워터파크 입구: 매표 키오스크·락커 키 밴드·신발장·탈의실",
    "찜질방: 불가마/황토방/소금방, 매점(식혜·맥반석 계란), 수면실, 찜질복 지급"
   ],
   "interactionIdeas": [
    "매표 → 락커 키 → 워터파크/찜질방 이동(엘리베이터 연결)",
    "식혜·계란 매점, 양머리 수건",
    "빵 고르기(트레이·집게)"
   ],
   "enterable": true
  },
  {
   "name": "호메르스호텔 (로비 · 브롱스브루잉 · 웨딩/컨벤션 로비 · 2-4F 연회장 · 6F 프론트 라운지)",
   "path": "Workspace.Gwangalli.landmarks.호메르스호텔 HOMERS HOTEL",
   "bounds": "(152.5,6.0,100.7)..(293.6,255.9,231.4)",
   "rooms": [
    {
     "name": "호텔 로비 Lobby",
     "center": [
      268.3,
      6.8,
      133.3
     ],
     "size": [
      23,
      14,
      37
     ]
    },
    {
     "name": "브롱스브루잉 광안리BP점 BRONX BREWING",
     "center": [
      220,
      6.8,
      139.5
     ],
     "size": [
      73,
      14,
      49
     ]
    },
    {
     "name": "호메르스 웨딩 · 컨벤션 로비",
     "center": [
      168.7,
      6.8,
      126.7
     ],
     "size": [
      28,
      13,
      21
     ]
    },
    {
     "name": "2F-4F 다이닝 · 웨딩홀 · 연회장",
     "center": [
      222.8,
      23.7,
      123.2
     ],
     "size": [
      104,
      11,
      18
     ]
    },
    {
     "name": "6F 프론트 · 라운지",
     "center": [
      223.4,
      73.3,
      168.5
     ],
     "size": [
      95,
      12,
      27
     ]
    }
   ],
   "props": [
    "호텔 로비 Lobby: Crystal 6, Arm 6, ElevatorDoor 6, ElevatorJamb 6, Seat 4, Bloom 4 …",
    "브롱스브루잉 광안리BP점 BRONX BREWING: Bottle 97, StoolLeg 41, Seat 41, BeerGlass 18, BeerFoam 18, TapHandle 18 …",
    "호메르스 웨딩 · 컨벤션 로비: Leaves 4, LobbyGlass 3, TieRod 2, Soil 2, Pot 2, DoorStile 2 …",
    "2F-4F 다이닝 · 웨딩홀 · 연회장: Chair 16, CeilingLight 12, Flowers 8, FlowerStand 8, TableLeg 8, TableTop 8 …"
   ],
   "gameplay": [
    "LANDMARK RULES (notes)",
    "Destinations \"호메르스호텔\", \"브롱스 광안리 (호메르스호텔 1F)\"; BarCounter -> ShopStaff 바텐더; GwangalliLivingPlan has a site against its west party wall (keep that wall)"
   ],
   "emptyOrCrude": [
    "브롱스브루잉 73x49: best-dressed room on the map (41 stools, 18 taps, 97 bottles, 11 pendants) but no brew tanks/kettle wall, no kitchen, no TV",
    "웨딩·컨벤션 로비 28x21: 4 plants + glass canopy only — empty",
    "로비 23x37: crystal chandelier, 4 seats, 6 elevator leaves — no front desk (front is on 6F); 2-4F banquet and 6F front lounge are static and unreachable"
   ],
   "realWorld": [
    "바 카운터 + 하이스툴·발받침, 탭 핸들 6~12개 + 드립트레이",
    "브루펍: 스테인리스 발효조·브루하우스 유리벽, 탭월, 펍 키친",
    "웨딩홀 로비: 신랑신부 대기실, 축의금 접수대, 포토월, 하객 안내 모니터"
   ],
   "interactionIdeas": [
    "탭 맥주 따르기·건배",
    "웨딩 하객 이벤트(축의금 접수 → 연회장)",
    "6F 프런트 체크인 엘리베이터"
   ],
   "enterable": true
  },
  {
   "name": "수영구 생활문화센터 · 광안리 관광안내소 (+ 여름경찰서)",
   "path": "Workspace.Gwangalli.landmarks.수영구 생활문화센터 · 광안리 관광안내소",
   "bounds": "(43.6,6.0,102.7)..(145.7,94.2,233.0)",
   "rooms": [
    {
     "name": "광안리 관광안내소 Gwangalli Tourist Information Center",
     "center": [
      110.9,
      6.8,
      142.7
     ],
     "size": [
      60,
      14,
      44
     ]
    },
    {
     "name": "광안리 여름경찰서",
     "center": [
      63.9,
      6.8,
      143
     ],
     "size": [
      30,
      13,
      44
     ]
    }
   ],
   "props": [
    "광안리 관광안내소 Gwangalli Tourist Information Center: Product 103, Board 15, PriceRail 15, Wing 6, Upright 6, Seat 5 …",
    "광안리 여름경찰서: Spoke 12, WheelRim 8, SideGlass 6, ArchTrim 5, BrakeDisc 4, Rim 4 …"
   ],
   "gameplay": [
    "landmark hotel complex: rooms use Floor/LoungeFloor (not ShopFloor) so ShopLife ignores them (no order/pay); InfoDoor AutoDoor; Destination \"광안리 관광안내소\"",
    "Details.luau: lost-wallet quest returned at the 관광안내소 분실물 센터 — keep the room reachable",
    "여름경찰서 room holds a parked police car model (182 parts are the car)"
   ],
   "emptyOrCrude": [
    "안내소 60x44: 103 souvenir products on shelves, 4 lockers, bike/bridge model, 5 seats — decent but no 안내 데스크 staff screens, no brochure racks, no 관광 지도 wall",
    "여름경찰서 30x44: mostly a police car; 2 seats, no desks"
   ],
   "realWorld": [
    "안내 데스크(다국어 안내원, 지도·브로셔 랙), 대형 관광 지도/광안대교 사진 벽",
    "물품 보관함, 분실물 센터, 휴대폰 충전",
    "기념품 진열, 포토존, 여름경찰서 민원 책상"
   ],
   "interactionIdeas": [
    "브로셔 집기·지도 보기(퀘스트 힌트)",
    "분실물 신고/반환(Details 지갑 퀘스트)",
    "물품 보관함 사용"
   ],
   "enterable": true
  },
  {
   "name": "밀락더마켓 MILLAC THE MARKET (food hall + 2F shops + 계단식 버스킹 객석)",
   "path": "Workspace.Gwangalli.millak.밀락더마켓 MILLAC THE MARKET (민락수변로17번길 56)",
   "bounds": "(-3384.8,6.0,-605.6)..(-3044.4,71.0,-310.0)",
   "rooms": [
    {
     "name": "Market hall 1F (Floor 228x139, open to roof ~59) + mezzanine 2F shops",
     "center": [
      -3210.3,
      6.5,
      -457
     ],
     "size": [
      251,
      0,
      182
     ]
    }
   ],
   "props": [
    "Interior: Seat 54, AisleStep 24, Partition 14, Pedestal 12, TableTop 12, SpotHousing 10 …",
    "sub-models: 8 \"F&B ...\" stalls (밀락포차, 밀락 떡볶이, 부산 어묵 바, 크래프트 비어 WAVE, 회 한 접시, 타코 & 버거, 돈카츠 모모, 젤라또 피콜로) each = Kitchen box + Counter + CounterTop + Partition + LightBar + MENU sign; 12 pedestal tables x2 seats; 스타벅스 밀락더마켓점 = BarCounter + BarTop + BackBar + PendantBar only; 6 mezzanine shops each = 1 Rack + 1 DisplayTable + glass; stepped busking seating 30 seats + stage + 2 speakers",
    "Shell (벽돌 창고동) + Glass wall (통유리) with 5 AutoDoors (2 sea-side, 2 1F, 1 2F main)"
   ],
   "gameplay": [
    "not a ShopLife shop (Floor not ShopFloor); ShopStaff LOOSE anchor BarCounter (Starbucks) -> barista NPC; Destination \"밀락더마켓\" (millak/Destinations); Details.luau busking stage (one of 3 stages \"found in the map\": 버스킹 스퀘어) — keep BuskingStage/Seat names; Nav names \"밀락더마켓 버스킹 스퀘어\""
   ],
   "emptyOrCrude": [
    "a 228x139 hall with ~230 furniture parts: 8 food stalls are a single \"Kitchen\" box each (no equipment, no menu boards with prices, no stools at the counters), Starbucks is just a counter + back bar (no machines/POS/seating)",
    "mezzanine shops are one rack + one table each; floor single slab; no 화장실, no 키오스크/진동벨 pickup, no trash/tray return, no string-light density near ceiling"
   ],
   "realWorld": [
    "푸드홀: 스톨별 주방 장비(철판/튀김기/맥주 탭/회 냉장고), 조명 메뉴판, 진동벨 픽업, 공용 테이블 수백 석",
    "스타벅스 매장 구성(바·POS·픽업·MD·좌석)",
    "편집숍/플라워/서점/보틀샵 디테일(책장·꽃 냉장고·와인랙)"
   ],
   "interactionIdeas": [
    "스톨별 주문(진동벨) → 공용석 식사",
    "버스킹 공연 관람/참여(Details busking)",
    "2F 편집숍 쇼핑, 스타벅스 주문"
   ],
   "enterable": true
  },
  {
   "name": "민락어민활어직판장 (fishermen's live fish market)",
   "path": "Workspace.Gwangalli.millak.민락어민활어직판장 (Millak fishermen's live fish market)",
   "bounds": "(-3029.0,4.0,-333.7)..(-2839.5,22.3,-265.0)",
   "rooms": [
    {
     "name": "market hall (8 stalls 1호~8호), open side, WetFloor 183x31",
     "center": [
      -2934.2,
      4.2,
      -299.5
     ],
     "size": [
      185,
      0,
      65
     ]
    }
   ],
   "props": [
    "hall: PlasticStool 16, Fish_광어 10, Column 9, StyrofoamBoxes 8, PrepCounter 8, AirHose 8 …",
    "each 점포 = 1 PrepCounter, 1 tank (TankStand/TankGlass/TankWater/TankLED + AirHose), 1 StyrofoamBoxes, 2 PlasticStool, 2-3 Fish_ parts, 1 sign"
   ],
   "gameplay": [
    "not ShopLife; Destination \"민락어민활어직판장\"; Nav name"
   ],
   "emptyOrCrude": [
    "8 identical stalls of ~20 parts each in a 183x31 hall; no 저울, no 회 뜨는 도마/칼, no 가격표, no 바구니/고무 대야, no 비닐 앞치마 mannequins, no 수조 bubbles/pumps detail"
   ],
   "realWorld": [
    "점포별 대형 수조 여러 개(광어·우럭·도미·멍게·해삼·전복), 고무 대야·바구니",
    "저울, 도마·회칼, 비닐봉지, 아이스박스·스티로폼 포장",
    "가격표 판, 물 호스·젖은 바닥 배수로, 상인(앞치마·장화), 초장집 안내"
   ],
   "interactionIdeas": [
    "수조에서 고르기 → 무게 재기 → 흥정 → 회 뜨기 → 초장집 이동",
    "포장(아이스박스)"
   ],
   "enterable": true
  },
  {
   "name": "민락회타운 (1F 활어직판장; 2F-10F 초장집은 facade)",
   "path": "Workspace.Gwangalli.millak.민락회타운 (Millak Hoe Town · 민락수변로 1)",
   "bounds": "(-2674.2,6.5,-128.3)..(-2505.6,147.0,8.2)",
   "rooms": [
    {
     "name": "1F 활어직판장 (WetFloor 145x107)",
     "center": [
      -2592.4,
      6.8,
      -57.8
     ],
     "size": [
      161,
      0,
      129
     ]
    }
   ],
   "props": [
    "1F: Fish_광어 36, TankLED 27, TankWater 27, TankGlass 27, TankStand 27, AirHose 22 …",
    "27 tanks, 8 PrepCounters, 20 CeilingLight, elevator core + sign \"엘리베이터 · 2F~10F 초장집 식당가\" (elevator goes nowhere)",
    "upper floors: RoomDepth fake rooms (59 RoomLight, 49 RoomWall)"
   ],
   "gameplay": [
    "Work sim job \"hoe\" place \"민락회타운\" (GwangalliWorkConfig) — job stations/customers are positioned by the place name; Destination \"민락회타운\"; not ShopLife"
   ],
   "emptyOrCrude": [
    "tanks and counters only; no 초장집 floors (the sign points to an elevator with no car), no seating anywhere, no 저울/가격표/stall signs density (8 signs for 27 tanks)"
   ],
   "realWorld": [
    "1F 활어 판매 점포 20+개(수조 벽), 2F~ 초장집(좌식 테이블·초장·쌈채소·매운탕 버너)",
    "엘리베이터/계단, 점포 번호 간판, 시세판"
   ],
   "interactionIdeas": [
    "회 고르기 → 엘리베이터로 초장집 → 상차림비 결제 → 식사",
    "hoe 알바: 수조 관리·포장"
   ],
   "enterable": true
  },
  {
   "name": "광안리 해양레포츠센터 (접수 · 탈의실)",
   "path": "Workspace.Gwangalli.coast.Beach (광안리해수욕장).광안리 해양레포츠센터 (Gwangalli Marine Leports Center)",
   "bounds": "(2250.6,-2.3,-441.3)..(2416.6,31.6,-171.8)",
   "rooms": [
    {
     "name": "1층 접수 · 탈의실 (Floor 84x34, ceiling 11)",
     "center": [
      2350.4,
      3.1,
      -362.2
     ],
     "size": [
      88,
      11,
      46
     ]
    }
   ],
   "props": [
    "building: Mullion 29, StorefrontGlass 26, RailPost 22, RailGlass 20, Rail 20, LifeJacket 10 …",
    "outside: 보행교 access pier, 3 kayaks, 3 jet boats, banana boat, yacht (SeaBob tags)"
   ],
   "gameplay": [
    "AutoDoor_Entrance (GwangalliDoors); Destination \"해양레포츠센터\" (coast/Destinations); not ShopLife"
   ],
   "emptyOrCrude": [
    "84x34 hall: 1 reception counter, 8 lockers, 10 life jackets on 1 rail, 2 benches — no 탈의실 partitions/showers, no equipment racks (paddles/wetsuits), no safety-video screen, no waiting seats"
   ],
   "realWorld": [
    "접수 데스크(체험 예약·요금표·안전서약서), 구명조끼/웻슈트 렌탈 랙",
    "탈의실·샤워실·락커, 안전교육 영상 모니터",
    "패들·카약 보관 랙, 대기 벤치"
   ],
   "interactionIdeas": [
    "체험 예약 → 구명조끼 착용 → 카약/SUP 출발",
    "락커 이용·샤워"
   ],
   "enterable": true
  },
  {
   "name": "공중화장실 · 샤워장 (-1600) (해변 테마거리)",
   "path": "Workspace.Gwangalli.coast.Promenade (광안리 해변 테마거리).Plazas.공중화장실 · 샤워장 (-1600)",
   "bounds": "(-1614.5,6.5,-84.0)..(-1587.4,16.6,-64.7)",
   "rooms": [
    {
     "name": "화장실 남/여 + 외부 샤워",
     "center": [
      -1600.9,
      6.9,
      -74.4
     ],
     "size": [
      21,
      0,
      12
     ]
    }
   ],
   "props": [
    "parts: Wall 6, StallWall 4, ShowerGrate 2, ShowerHead 2, ShowerPost 2, Fascia 2 …"
   ],
   "gameplay": [
    "no scripts; InteriorLight tag (night light); Nav pedestrian area"
   ],
   "emptyOrCrude": [
    "walk-in through gaps behind PrivacyScreens, but stalls are 4 bare StallWall slabs: no toilets, urinals, stall doors, sinks, mirrors, hand dryers; WashCounter is a plain box; one ceiling panel"
   ],
   "realWorld": [
    "양변기 칸(문·잠금), 소변기, 세면대·거울·핸드드라이어",
    "발 씻는 수도·샤워 부스, 휴지·비누 디스펜서, 청소 안내판"
   ],
   "interactionIdeas": [
    "칸 문 잠그기, 손 씻기, 샤워(해수욕 후 청결 Needs)"
   ],
   "enterable": true
  },
  {
   "name": "공중화장실 · 샤워장 (1250) (해변 테마거리)",
   "path": "Workspace.Gwangalli.coast.Promenade (광안리 해변 테마거리).Plazas.공중화장실 · 샤워장 (1250)",
   "bounds": "(1237.3,6.5,-51.6)..(1264.1,16.6,-32.6)",
   "rooms": [
    {
     "name": "화장실 남/여 + 외부 샤워",
     "center": [
      1250.7,
      6.9,
      -42.1
     ],
     "size": [
      21,
      0,
      12
     ]
    }
   ],
   "props": [
    "parts: Wall 6, StallWall 4, ShowerGrate 2, ShowerHead 2, ShowerPost 2, Fascia 2 …"
   ],
   "gameplay": [
    "no scripts; InteriorLight tag (night light); Nav pedestrian area"
   ],
   "emptyOrCrude": [
    "walk-in through gaps behind PrivacyScreens, but stalls are 4 bare StallWall slabs: no toilets, urinals, stall doors, sinks, mirrors, hand dryers; WashCounter is a plain box; one ceiling panel"
   ],
   "realWorld": [
    "양변기 칸(문·잠금), 소변기, 세면대·거울·핸드드라이어",
    "발 씻는 수도·샤워 부스, 휴지·비누 디스펜서, 청소 안내판"
   ],
   "interactionIdeas": [
    "칸 문 잠그기, 손 씻기, 샤워(해수욕 후 청결 Needs)"
   ],
   "enterable": true
  },
  {
   "name": "지하철 출입구 x5 (광안역 3/6번, 금련산역 1번, 남천역 3번, 수영역 7번)",
   "path": "Workspace.Gwangalli.roads.MetroEntrances.Metro_*",
   "bounds": "e.g. Metro_광안역_3번출구 (-228.7,-12.0,813.0)..(-198.9,20.6,820.8)",
   "rooms": [
    {
     "name": "Metro_광안역_3번출구 stair pit",
     "center": [
      -212.4,
      -2.3,
      816.9
     ],
     "size": [
      26,
      12,
      7
     ]
    }
   ],
   "props": [
    "each: ~17 Step parts down to a 9.7x5.6 LandingFloor at y≈-2.3, 2 SideWall + tiles, 2 Handrail, closed RollingShutter at the bottom, line sign, glass canopy"
   ],
   "gameplay": [
    "Destination parts \"지하철 ... 출구\" (GwangalliTravel); GwangalliTransitShared exits table keys each model name with landing + shutter XZ (metro ride starts at the shutter) — keep LandingFloor/RollingShutter positions; InteriorLight tag"
   ],
   "emptyOrCrude": [
    "stairs end at a rolling shutter: no concourse, no 개찰구, no 매표기, no 역명판 platform"
   ],
   "realWorld": [
    "계단 + 에스컬레이터/엘리베이터, 출구 번호 노란 사인",
    "대합실: 개찰구(교통카드 태그), 승차권 발매기, 노선도, 편의점/화장실",
    "승강장 스크린도어"
   ],
   "interactionIdeas": [
    "교통카드 태그 → 개찰구 → 지하철 이동(Transit)"
   ],
   "enterable": true
  },
  {
   "name": "city storefront dioramas (139 buildings, 281 ShopFloor rooms)",
   "path": "Workspace.Gwangalli.city.블록01..블록11.<side>.<building> (Archetype food/shop/motel/pub/officetel/tower/house)",
   "bounds": "(-2528.7,6.3,60.1)..(2563.4,123.1,497.0)",
   "rooms": [],
   "props": [
    "per storefront: ShopFloor (~12-25 x 13-14), ShopBackWall 9 high, ShopLight panel, Counter box, MenuBoard, sometimes TableLeg/Bench, TankBase/TankWater (횟집), Door (solid, T 0.3) + ShopWindow (solid glass); upper floors RoomDepth fake rooms"
   ],
   "gameplay": [
    "Archetype buildings have the ShopFloor parts as direct children of the building Model -> ShopStaff treats the whole building as one storefront and puts NPC staff behind the first Counter; Annex adds \"들어가기\" prompts at the Door parts and teleports to an off-map room (y 3000 band) named after the nearest Sign_; MapIndex lists them"
   ],
   "emptyOrCrude": [
    "NOT walk-in: diorama behind collidable Door + glass; counter box + sign; Annex teleports to an unrelated off-map room"
   ],
   "realWorld": [
    "the shop type on each sign — see REAL-WORLD CHECKLISTS in notes"
   ],
   "interactionIdeas": [
    "make Door non-collidable client-side + deepen ShopFloor into the hollow ground storey, then furnish by sign type"
   ],
   "enterable": false
  },
  {
   "name": "uptown storefront dioramas (88 buildings, 206 ShopFloor rooms)",
   "path": "Workspace.Gwangalli.uptown.RowC_광남로-수영로.Frontage.Block_C1..C11.<kind>.<building> + 단지내상가",
   "bounds": "(-2565.9,5.6,365.7)..(2564.4,186.4,814.7)",
   "rooms": [],
   "props": [
    "same kit as city: ShopFloor + ShopBackWall + ShopLight + Counter + DoorFrame/Door + ShopWindow; shophouse/commercial/tower/officetel kinds"
   ],
   "gameplay": [
    "ShopStaff + Annex as above"
   ],
   "emptyOrCrude": [
    "NOT walk-in: diorama behind collidable Door + glass; counter box + sign; Annex teleports to an unrelated off-map room"
   ],
   "realWorld": [
    "the shop type on each sign — see REAL-WORLD CHECKLISTS in notes"
   ],
   "interactionIdeas": [
    "make Door non-collidable client-side + deepen ShopFloor into the hollow ground storey, then furnish by sign type"
   ],
   "enterable": false
  },
  {
   "name": "beachfront storefront dioramas (21 buildings, 43 ShopFloor rooms)",
   "path": "Workspace.Gwangalli.beachfront.구간NN.<building> e.g. 해변빌딩 (황금치킨), 일신빌 (할매순대국밥), 삼성빌딩 (신짬뽕중화요리), 모텔 달빛",
   "bounds": "(-2475.5,6.4,-92.7)..(2474.4,220.4,249.1)",
   "rooms": [],
   "props": [
    "ShopFloor 9-42 x 10-36, Counter, MenuBoard, Drum/ExhaustDuct, Bench/TableLeg; Door solid"
   ],
   "gameplay": [
    "ShopStaff + Annex as above"
   ],
   "emptyOrCrude": [
    "NOT walk-in: diorama behind collidable Door + glass; counter box + sign; Annex teleports to an unrelated off-map room"
   ],
   "realWorld": [
    "the shop type on each sign — see REAL-WORLD CHECKLISTS in notes"
   ],
   "interactionIdeas": [
    "make Door non-collidable client-side + deepen ShopFloor into the hollow ground storey, then furnish by sign type"
   ],
   "enterable": false
  },
  {
   "name": "millak storefront dioramas (12 buildings, 20 ShopFloor rooms)",
   "path": "Workspace.Gwangalli.millak.민락동 건물.rowA..rowD.<building> e.g. 신라횟집, 오션브릿지 A/B동, 자연활어 수정궁, 바다마루",
   "bounds": "(-4356.0,6.5,-460.1)..(-2533.5,243.1,857.3)",
   "rooms": [],
   "props": [
    "same kit"
   ],
   "gameplay": [
    "ShopStaff + Annex"
   ],
   "emptyOrCrude": [
    "NOT walk-in: diorama behind collidable Door + glass; counter box + sign; Annex teleports to an unrelated off-map room"
   ],
   "realWorld": [
    "the shop type on each sign — see REAL-WORLD CHECKLISTS in notes"
   ],
   "interactionIdeas": [
    "make Door non-collidable client-side + deepen ShopFloor into the hollow ground storey, then furnish by sign type"
   ],
   "enterable": false
  },
  {
   "name": "빵천동 빵집골목 bakery dioramas (6) + 136 lit storefronts without floor",
   "path": "Workspace.Gwangalli.namcheon.남천동 시가지 (Namcheon-dong streets).rowC 광남로 · 수영로.빵천동 빵집골목 (Bakery alley).<소금빵연구소|남천제과|크루아상 드 남천|베이글 스탠드|우리밀 식빵집|빵천동 카페>",
   "bounds": "(2946.5,6.5,287.1)..(3045.5,43.1,535.9)",
   "rooms": [],
   "props": [
    "each bakery: ShopFloor 31.9x12.7 (nocol), BackWall, Ceiling, 2 Shelf with 8 Loaf, BreadTable, CashCounter+POS, DisplayCase+CaseGlass, ChalkBoard; Door (solid, T 0.45) + DisplayWindow; 136 other namcheon buildings have ShopBackWall+ShopLight+ShopWindow+Door with NO floor (lit glass only)"
   ],
   "gameplay": [
    "Destination \"빵천동 빵집골목\"; ShopStaff (POS anchor) bakers; Annex doors"
   ],
   "emptyOrCrude": [
    "NOT walk-in: diorama behind collidable Door + glass; counter box + sign; Annex teleports to an unrelated off-map room"
   ],
   "realWorld": [
    "the shop type on each sign — see REAL-WORLD CHECKLISTS in notes"
   ],
   "interactionIdeas": [
    "make Door non-collidable client-side + deepen ShopFloor into the hollow ground storey, then furnish by sign type"
   ],
   "enterable": false
  },
  {
   "name": "apartment/officetel pilotis vestibules (uptown 25, millak 17, namcheon 4)",
   "path": "e.g. Workspace.Gwangalli.uptown.RowD_금련산기슭_아파트.광안 SK VIEW.Towers.광안 SK VIEW 101동",
   "bounds": "per tower e.g. 101동 (1916.9,6.5,807.3)..(2037.6,232.1,873.4)",
   "rooms": [
    {
     "name": "광안 SK VIEW 101동 LobbyFloor (vestibule)",
     "center": [
      1975.2,
      6.8,
      825.4
     ],
     "size": [
      15,
      12,
      7
     ]
    },
    {
     "name": "광안 SK VIEW 101동 PilotisFloor (open, walkable)",
     "center": [
      1938.8,
      6.7,
      836.4
     ],
     "size": [
      34,
      12,
      22
     ]
    }
   ],
   "props": [
    "LobbyGlass (T 0.45, collidable) + LobbyWall 0.6 behind it + LobbyFloor 15x7 + LobbyLight + LobbySide; EntranceCanopy, Sign_공동현관, Sign_101동; Pilotis columns + PilotisSoffit + PilotisFloor (open), SoffitLight, GroundCore solid"
   ],
   "gameplay": [
    "Annex \"공동현관\" door -> off-map apartment instance (Builder plan); uptown Kind/Complex/NightHomes attrs drive night windows; GwangalliHomes life game uses its own instances"
   ],
   "emptyOrCrude": [
    "the lobby is a 15x7 glass box with nothing inside (no mailboxes, no elevator, no door lock); pilotis is a bare covered slab"
   ],
   "realWorld": [
    "공동현관 번호 도어락 + 인터폰, 우편함 벽",
    "택배 무인보관함, 관리사무소 공지 게시판",
    "엘리베이터 2대(층표시·CCTV), 소화전"
   ],
   "interactionIdeas": [
    "도어락 비번/인터폰 호출 → 엘리베이터(Annex 올라가기)",
    "우편함·택배함 확인"
   ],
   "enterable": false
  }
 ],
 "notes": "Scope: Workspace.Gwangalli.{city,uptown,beachfront,millak,namcheon,coast,skyline,bridge,roads,landmarks} of v7 place.bin (dedicated venue folders skipped). Full per-building/per-shop detail (93 venues): /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/districts.json; this condensed copy (beachfront grouped by 구간): /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/districts_summary.json; working data (shops.json, extra.json, counts.json, dumped script sources) in bld/work/. Building list = MapIndex.isBuilding rule (Model with FacadeDetail/WallServices or a Roof/Slab/Core/Parapet/Crown/Coping/Pier/Spandrel/ShopFloor/Facade/Tower/Podium child) plus landmark/venue groups. THREE INTERIOR KINDS: (1) WALK-IN: beachfront ShopLife street shops = Model with children Interior (Model, LOD near, NearLOD tag) + ShopFloor + ShopBackWall + 2 ShopPartition + ShopCeiling + AutoDoor (tag AutoDoor, leaves with OpenOffset) — 134 shops in 72 buildings, floors 8-76 wide x 6-28 deep, ceilings 7.9-12.7 studs above floor (floor top y≈6.8); floor finishes: 61 Slate-like, 36 WoodPlanks, 19 Marble-like, 15 Concrete, 3 Carpet; landmark rooms (Floor/Ceiling/BackWall + Interior_* sibling) in uptown Landmarks, landmarks hotels, millak market/fish halls, coast leports + toilets. (2) DIORAMA: ShopFloor rooms behind collidable Door + glass (city 281, uptown 206, beachfront 43, millak 20, namcheon 6) — NPC staff stand inside (ShopStaff) and Annex teleports you to an unrelated off-map room. (3) FACADE: solid Core/GroundCore/Mass; RoomDepth/RoomGlass fake rooms on upper floors; namcheon lit storefronts without floor. COUNTS: city: 139 buildings, 0 walk-in, 139 storefront-diorama buildings (281 ShopFloor rooms), 0 pure facade (every city building has ground-floor dioramas; upper floors are RoomDepth fake rooms) || uptown: 140 buildings (excl. 3 PoliceCar models) — 7 walk-in landmark venues (hospital, post office, Starbucks 광안역점, BNK, 지구대, Homeplus Express, church), 88 diorama (206 ShopFloor), 25 apartment towers with glass vestibule + open pilotis, 18 villas with a solid Lobby box, 2 pure facade (광안초등학교 본관, 광안 공영주차장 주차빌딩), plus 99 small 다가구주택 boxes, gas station kiosk (solid), apartment 정문/후문 경비실 booths || beachfront: 93 buildings — 72 with walk-in shops (134 ShopLife shops + 7 empty AutoDoor shells), 21 diorama (43 ShopFloor); 0 pure facade; all upper floors facade || millak: 126 MapIndex buildings — 2 walk-in (민락회타운 1F, 밀락더마켓 shell) + 활어직판장 (open hall), 12 diorama (20 ShopFloor), 17 apartment vestibules, 95 pure facade (빌라 · <shop> blocks, motels, officetels, lighthouses, seawall, toilet) || namcheon: 214 buildings — 0 walk-in, 6 bakery dioramas, 4 apartment vestibules, 52 villas with solid Lobby box + LobbyDoor, 152 pure facade (136 of them with lit ShopBackWall/ShopWindow/Door storefronts but no floor; 삼익비치 towers; KBS 부산방송총국 (Door + ShopBackWall only); 삼익비치 상가 4 lit storefronts; 관리사무소) || coast: 7 structures — 2 walk-in public toilets/showers + 해양레포츠센터 (walk-in), 4 lifeguard towers (facade), 41 tetrapods/1 boat matched the building rule (not buildings); open-air: SUP 비치바 (counter + 6 stools), 파라솔·튜브 대여소 x3 (counter only), 3 food trucks (counter + stand tables), festival stage, pavilions || skyline: 98 far-shore boxes (마린시티/해운대/용호동) — all facade, intentionally || bridge: 1 approach structure — facade (deck Destination only) || roads: 0 buildings; 5 metro entrance stair pits (walk-down to a closed shutter), bus stops, vehicles || landmarks: 4 hotel complexes, all with walk-in ground floors (lobbies, GS25, 홍미당, 브롱스, 관광안내소); their upper-floor static rooms (2F cafe, 15F lounge, rooftop bar, 6F waterpark, 8-9F 찜질방, rooftop pool, 2-4F banquet, 6F front) have no route. GLOBAL CRUDENESS (walk-in shops): every shop uses the same kit — one flat floor slab (WoodPlanks / Slate-like / Marble-like / Concrete), one flat back wall and two flat partitions with no finish, one flat ceiling slab with downlights; the same template fixtures in 111 of 134 shops (2 CassetteAC, FireExtinguisher+ExitSign, Baseboard x3, DoorPlanter/DoorShrub, A-frame/X-banner) and a Door_restroom leaf on the back wall that leads nowhere in 74; no water purifiers, trash/tray return, napkin/condiment sets, wall menus with prices, 원산지 boards, TVs (except pubs), wall decor; kitchens are a KitchenPass/PassLedge strip (no burners/pots/fryers); seats are kit chairs. 7 storefronts (바삭치킨, 해변 호프, 광안 치킨 & 맥주, 행복 돼지국밥, 부산어묵 광안점, 비치용품 · 튜브대여, 광안 기념품샵 PORT) have WORKING AutoDoors into an empty unlit void up to the GroundCore. Big landmark halls (hospital 95x82, Homeplus 127x96, market 228x139, Starbucks 광안역점 63x59, BNK 68x63) hold only 50-230 furniture parts. GAMEPLAY TO PRESERVE: ShopLife.Scan (name-based stations; key \"<model name>@x,z\" must stay stable -> do not rename/move shop Models), ShopStaff anchors, GwangalliDoors AutoDoor tags/OpenOffset, Annex (skips walk-in shops, uses Door/LobbyDoor/EntranceDoor parts and Sign_ texts of other buildings), StreetSigns (Sign_ parts), Destination parts + GwangalliNav names, Work sim (스타벅스 광안리점 LAYOUT offsets in its Destination frame; 민락회타운 \"hoe\"; GS25 광안리점 is in the convenience folder), Play.Pocha \"민락 포장마차\" model (CU 민락비치점 빌딩), Details (관광안내소 lost&found, busking stages), Citizens indoor destinations, GwangalliTransitShared metro exits (landing/shutter XZ). A client-side upgrade should add parts under its own folder, hide (LocalTransparencyModifier/Transparency) crude parts locally instead of deleting, keep part names that scripts read, and keep seats/counters/POS at their positions (ShopLife seat->table spots, Career.Cafe customer paths). Material codes in place.bin are compact indices; names given are inferred from usage (83 WoodPlanks, 88 Slate-like, 233 Marble-like, 28 Concrete, 231 Carpet). REAL-WORLD CHECKLISTS: [soup] 입구 POS 계산대, 배식구+육수솥·화구, 테이블 수저통/양념통/호출벨, 가격 메뉴판+원산지판, 정수기·반찬 셀프바, 좌식 평상, TV / [noodle] 면 솥·육수 냉장고, 식초/겨자/가위, 메뉴판(물/비빔), 정수기; 라멘은 카운터 바+식권기 / [grill] 테이블 화로+석쇠+원통 배기후드, 수납 스툴, 조개 얼음 진열대, 소주 냉장고, 앞치마/집게/목장갑, 롤휴지, 셔터 개방 전면 / [rawfish] 입구 활어 수조 벽+기포기, 회 칼판 주방, 좌식 룸+창가석, 기본 상차림, 시가표/원산지 / [seafood] 수조+대형 찜기, 비닐 테이블보·집게·가위, 단체 룸, 시가표 / [pocha] 천막/줄전구, 빨강·파랑 플라스틱 테이블+원형 스툴, 오픈 철판 키친, 소주 냉장고·포스터, TV / [pub] 바+하이스툴·발받침, 탭 6~12, 백바 조명 병 진열, 하이테이블/부스, TV/다트, 칠판 메뉴 / [chicken] 튀김기 2~3, 박스 더미, 배달 태블릿/프린터, 치킨무 셀프, 생맥주 디스펜서 / [snack] 떡볶이 철판, 어묵 꼬치통, 튀김 진열, 순대 찜기, 스탠딩 바, 선불 POS / [cafe] POS 2+진동벨/키오스크, 2~3그룹 머신·그라인더·제빙기·블렌더·싱크, 디저트 쇼케이스, 픽업대+퇴식대, 조명 메뉴보드, MD 벽, 다양한 좌석+콘센트 / [burger] 키오스크+번호 모니터, 그릴/튀김기, 셀프 음료, 퇴식대 / [dessert] 젤라또 쇼케이스/와플기/빙수기/호떡 철판, 토핑·시식 스푼, 2인석, 포토월 / [bakery] 원목 빵 진열대+트레이·집게, 케이크 쇼케이스, 오븐 창, 포장 계산대, 음료 냉장고 / [cvs] 곤돌라 4~6열+엔드캡, 음료 워크인 냉장 10~14도어, 아이스크림 평대, POS 2+담배장+온장고, 전자레인지·온수, 시식 바, ATM/택배 / [retail] 올리브영 벽면 브랜드 유닛·테스터 아일랜드·거울·바구니 / 기념품 회전 스탠드·티셔츠 랙 / 튜브·구명조끼 대여 걸이 / [pharmacy] 서랍식 처방약장+조제실, 일반약 진열, 건기식, 혈압계, 대기 의자 / [laundry] 전동 옷걸이 컨베이어, 스팀 프레스, 재봉틀, 요금표 / [realty] 책상+모니터 2~3, 상담 테이블, 매물 시세표/지도, 유리창 전단, 정수기 / [lobby] 프런트(PC·카드키·벨), 로고 월, 소파, 벨카트/짐 보관, 엘리베이터 홀, 무인 체크인(모텔) / [residence] 번호 도어락+인터폰, 우편함 벽, 택배 보관함, 엘리베이터 2, 게시판, CCTV / [claw] LED 기계 열, 지폐 교환기, 경품, 네온/거울벽 / [bistro] 오픈 키친·피자 오븐, 와인 셀러/랙 벽, 테이블 세팅(와인잔·캔들) / [empty] 간판 업종(치킨/호프/국밥/어묵/기념품/비치용품)의 실제 매장 구성. INTERACTION IDEAS: [soup] 호출벨 주문→배식구 서빙, 다대기/새우젓 넣기, 정수기, 수저통 / [noodle] 물/비빔 선택, 가위·식초, 라멘 식권기 / [grill] 화로에 올리기/뒤집기(ShopLife grill), 소주 꺼내기 / [rawfish] 수조에서 고르기→회 뜨기, 매운탕 버너 / [seafood] 수조 고르기→찜기 타이머 / [pocha] 스툴 앉기→안주 주문→짠, TV / [pub] 탭 따르기, 다트/TV / [chicken] 포장 픽업, 생맥주 / [snack] 어묵 꼬치/국물, 선불 / [cafe] 키오스크→진동벨→픽업대, 퇴식대 반납, 창가 바 / [burger] 키오스크→번호 호출 / [dessert] 시식 스푼, 와플/호떡 굽기 / [bakery] 트레이+집게→계산 / [cvs] 바구니→POS, 전자레인지/온수 컵라면, ATM / [retail] 테스터·거울, 튜브 대여 / [pharmacy] 상담→약 / [laundry] 맡기기→컨베이어→찾기 / [realty] 매물 상담(Housing) / [lobby] 체크인→카드키→엘리베이터(Annex) / [residence] 도어락/인터폰→엘리베이터(Annex 올라가기), 우편함 / [claw] 인형뽑기 미니게임 / [bistro] 와인 고르기, 파스타 주문 / [empty] 간판 업종 매장을 클라이언트에서 생성. LANDMARK RULES: not a ShopLife shop (Floor, not ShopFloor) — no order/pay flows; ShopStaff puts an NPC at a loose landmark counter (PosBase/POS/BarCounter/FrontDesk/CashierPanel/\"안내 · 접수 카운터\") if present; AutoDoor tag + OpenRadius attr (GwangalliDoors); Destination part (GwangalliTravel, GwangalliNav, MapIndex); hotels: rooms use Floor/LoungeFloor (not ShopFloor) so ShopLife ignores them (no order/pay); ShopStaff LOOSE anchors (PosBase/POS/BarCounter/FrontDesk) get NPC staff; AutoDoor-tagged LobbyDoor/CafeDoor/GS25Door/PubDoor (GwangalliDoors); Destination parts (GwangalliTravel); upper-floor rooms have NO stairs/elevator route (ElevatorDoor leaves only) — visible from outside only. Beachfront props/crude lines omit the template fixtures every shop has (2 CassetteAC, extinguisher+exit sign, baseboard, door planters, noren) and the misses every shop shares (water purifier, bin/tray return, wall decor, TV, table condiments); \"d\" = furniture parts per 100 sq studs excl. goods. ShopLife type mismatches worth fixing with ShopLifeType/ShopLifeMenu attributes: 바다곁 파스타 & 와인 (soup/gukbap by contents), BBQ (burger by contents, real chicken brand), I AM BUSAN x2 (souvenir by name, stocked with bread), BINGBING (dessert sign but contains 7 claw machines), 인형뽑기/PHOTO & CLAW (no ShopLife type)."
}
```

## survey:cvs_delivery

```json
{
 "venues": [
  {
   "name": "GS25 광안리점 (매장 / sales floor + eat-in + terrace)",
   "path": "Workspace.Gwangalli.convenience[\"GS25 광안리점\"]",
   "bounds": "min(-363.78,7.0,261.76) max(-308.46,18.0,307.17)  [interior; floor top 7.0, ceiling underside 18.0; terrace deck outside x -307.8..-294.9 z 262.0..308.2]",
   "enterable": true,
   "rooms": [
    {
     "name": "Sales floor (매장 전체)",
     "center": [
      -336.12,
      12.5,
      284.47
     ],
     "size": [
      55.32,
      11,
      45.41
     ],
     "floorY": 7,
     "ceilingY": 18
    },
    {
     "name": "Cashier zone behind counter (계산대 안쪽: POS x2, back counter, cigarette wall)",
     "center": [
      -330.3,
      12.5,
      301.4
     ],
     "size": [
      12.1,
      11,
      10.4
     ],
     "floorY": 7,
     "ceilingY": 18
    },
    {
     "name": "Counter + queue lane (CounterTop x-327.6..-324.3, queue1-3 z~304.5 x-323..-317)",
     "center": [
      -320,
      8.5,
      302.5
     ],
     "size": [
      11,
      3,
      8.4
     ],
     "floorY": 7,
     "ceilingY": 18
    },
    {
     "name": "Gondola aisles (Gondola_1..3 along X, aisles 4.6 studs wide)",
     "center": [
      -337.4,
      10.3,
      283.5
     ],
     "size": [
      33.3,
      6.6,
      21
     ],
     "floorY": 7,
     "ceilingY": 18
    },
    {
     "name": "Beverage wall (5 Fridge units, 15 doors, west wall)",
     "center": [
      -361.45,
      11,
      283.5
     ],
     "size": [
      4.5,
      8,
      35
     ],
     "floorY": 7,
     "ceilingY": 18
    },
    {
     "name": "Open chiller / 도시락 zone (north wall)",
     "center": [
      -346.75,
      11,
      304.85
     ],
     "size": [
      14.7,
      8,
      3.3
     ],
     "floorY": 7,
     "ceilingY": 18
    },
    {
     "name": "Eat-in + services strip along south window (standing bar, hot water, 2 microwaves, soup sink, ATM)",
     "center": [
      -333.2,
      12.5,
      263.95
     ],
     "size": [
      36.4,
      11,
      4.3
     ],
     "floorY": 7,
     "ceilingY": 18
    },
    {
     "name": "Front window promo strip (mostly empty floor; ice-cream chest only)",
     "center": [
      -314.85,
      12.5,
      280
     ],
     "size": [
      11.7,
      11,
      35
     ],
     "floorY": 7,
     "ceilingY": 18
    },
    {
     "name": "Entrance (AutoDoor_GS25, 9 wide x 9.3 tall, EntranceMat)",
     "center": [
      -309.1,
      11.7,
      302
     ],
     "size": [
      1,
      9.3,
      9
     ],
     "floorY": 7,
     "ceilingY": 16.9
    },
    {
     "name": "Terrace deck (outdoor, 3 PlasticTable sets, awning above at y16.3)",
     "center": [
      -301.37,
      6.78,
      285.11
     ],
     "size": [
      12.86,
      0.44,
      46.2
     ],
     "floorY": 7
    }
   ],
   "props": [
    "Floor x1: one 44.4x0.5x54.5 CeramicTiles slab #d6d6d2 (whole sales floor) - OK tile material but no border/threshold detail",
    "Ceiling/CeilingBoard x1 44.4x0.3x54.5 SmoothPlastic #ecece8 + TBar x22 (0.16x0.1 metal grid) - flat, no tiles/sprinklers/detectors",
    "LightPanel x8 Neon: 4 strips 0.9x46 along Z, 2 panels 3.2x16 (SurfaceLight Range32, InteriorLight AlwaysOn), 1 cashier panel 8.8x8.6 (Range18), 1 fridge strip 35x1 (Range14)",
    "CassetteAC x2 3.8x0.35x3.8 + ACGrille x2 + ACVane x8 (NearDetail) at (-319.4,17.8,285.3) and (-347.4,17.8,284.8) - decent",
    "WallLining/SideWallLining/BackWall Plaster #dedad0 + BrandBand x2 (GS blue 1-stud band at y16.4) - otherwise blank walls",
    "AutoDoor_GS25 Model (tag AutoDoor): 2 glass DoorLeaf 4x8.8 + rails/stiles + DoorOperator + MotionSensor + 2 'Sign_자동문 · 어서오세요' decals - functional sliding door",
    "ShopWindow x14 Glass t0.6 (front x-309 z263..297; side z~262 x-347..-308) + Mullion x19 + Head/SillRail - no window posters inside",
    "CounterBody 8x3.3x2.6 SmoothPlastic box + CounterTop 8.25x0.3x3.1 Granite + CounterFront blue + CounterFrontStrip Neon + CounterNotice '19세 미만…' - boxy counter",
    "POSMonitor x2 2x1.4x0.15 (POS 1 tagged GwPosScreen, attrs Job=gs25 Register=1, SurfaceGui PosScreen.Bg.{Head,Lines,Total}); POSStand x2",
    "CustomerDisplay x2 1.4x1 (one tagged GwPosCustomer) + DisplayStand x2; BarcodeScanner x2 0.34x0.75x0.3 (one tagged GwPosScanner) + ScannerCradle x2 + ScannerWindow neon x2",
    "ReceiptPrinter x2 0.9x0.65x0.9 (one tagged GwPosPrinter) + ReceiptPaper x2; CashDrawer x2 2.2x0.7x1.05 + DrawerHandle x2; CardTerminal x2 0.7x0.25x0.7 + CardTerminalScreen neon x2",
    "BagHolder x1 1.1x1x0.5, GumRack x3 0.4x0.55x0.55 cubes (yellow/green/pink) - the only impulse display",
    "Sign_계산대 · 택배 접수 7x1.3 hanging on 2 SignRod; StaffOnlyChain 1.8x0.6 '직원 외 출입금지'; CashierSideWall 0.3x3.3x9 + CashierSideTop",
    "BackCounter 10x3.2x2 + BackCounterTop; CashierPartition 10.35x11.5x0.6 Plaster wall behind cashier (x-336.6)",
    "CoffeeMachine 2.4x2.8x1.7 black box with SurfaceGui '원두커피 / 아메리카노 1,200원' (behind counter - customers cannot reach)",
    "StaffMicrowave 2.6x1.5x1.7 box + MicrowaveWindow; SteamerGlass 3x1.6x1.5 + SteamerHeader '핫바 · 찐빵' + SteamerBase + HotBar x4 cylinders",
    "CigaretteCabinet 9.7x6x0.6 + CigaretteBacklight Neon 9.3x4.9 + CigarettePacks x30 strips (0.57-2.3 x0.6x0.2, 8 colours) + CigaretteHeader '담배 · 전자담배 | 신분증을 제시해 주세요'",
    "Gondola_1..3 Models (LOD=zone, radius ~98): each = Plinth 3.2x0.3x30 + ShelfA/ShelfB (BackPanel 30x5.6, 2 Upright, 5 Board 29.6x0.15x1.2, 4 PriceRail) + EndCap (red, 3 boards) + 2 PriceRail with PriceTags gui (8 tags '1,000원…') + CategoryHeader 0.6x1x30 ('즉석식품 · 라면' / '과자 · 간식' / '생활용품 · 위생') + Sign_1+1 / Sign_2+1; ~286 'Product' each",
    "Product x950 total (gondolas + endcaps + chiller): plain SmoothPlastic boxes 0.51-0.95 x 0.6-1.1 x 1.05-1.5 in 14 flat colours, CanCollide false - crude coloured bricks",
    "Gondola end slots x4 (slot_food/snack/life at west ends x~-353, slot_drink at G3 east end x-321): SlotBack 3.2x5, SlotSide x2 red, SlotBoard x3, Sign_📦 <category>, RestockCard '품절 · 채워 주세요', Leftover x3 - intentionally sparse (JobCvsPlus fills them)",
    "OpenChiller Model (LOD zone r89) x-354.1..-339.4 z303.2..306.5: ChillerPlinth, 2 ChillerSide, ChillerCanopy, ChillerLight neon, AirCurtainLip glass, ChillerHeader '도시락 · 삼각김밥 · 샌드위치', BackPanel/Upright/Board x5, ~77 Product boxes",
    "Fridge x5 Models (LOD zone r86) x-363.7..-359.2 z266..301: Body 7x1x3.6 (top), Kick, 2 SidePanel, FridgeGlow neon 6.6x6.2 back, FridgeDoor one 6.6x6.2x0.1 glass slab, 2 DoorMullion, 3 DoorHandle, FridgeLamp, 3 WireShelf, 40 Bottle each (200 total: 0.27-dia single-colour cylinders) + FridgeLiner neon x5",
    "Sign_음료 · 생수 · 유제품 21x1.1 and Sign_맥주 4캔 11,000원 7x1.1 above fridges",
    "IceCreamFreezer 9x3x3.5 box + FreezerLid glass 8.4x2.9 + FreezerFront '아이스크림 2+1' + IceCream x14 blocks 0.9x0.6x1.1 embedded in the top of the solid body (y9.3..9.9, body top 10.0) under the lid (at front window x-315.7 z285.8..294.9)",
    "StandingCounterTop 2.8x0.3x22 WoodPlanks + StandingCounterBase (x-337..-315 z262.2..265.5) + TissueBox x3, ChopstickHolder x3, CupRamen x1 - no stools",
    "HotWaterCabinet 3.4x3.4x7 + HotWaterMachine 2.2x3x1.8 Metal '온수' + HotWaterTap; Microwave x2 2.6x1.4x2.6 stacked + MicrowaveWindow; SoupSink 2.2x0.1x1.1 plate + Sign_라면 국물은 여기에 버려 주세요",
    "ATM 4.2x6.4x3.2 Metal box + ATMScreen '입금 · 출금 · 이체' + ATMKeypadShelf + CashSlot + Sign_ATM (x-351.4..-347.1 z262.1..265.4)",
    "Sign_아르바이트 모집 4.2x3.2, Sign_반값택배 3.2x3.2 on north wall (x-320..-312.7); ExitSign over staff door; FireExtinguisher x1 (x-356.3 z305.5); CCTV ball x2 + CCTVMount x2",
    "QueueMark x2 + QueueText '여기서 기다려 주세요' floor decals at queue1/2; EntranceMat 7.2x4 navy",
    "StaffDoorJamb x2 + StaffDoorHead + StaffDoorLeaf (swung open, CanCollide false) + Sign_STAFF ONLY at x-364 z301.4..304.9 -> stock room",
    "Exterior: Sign_GS25 x2, FasciaStripeBlue/Cyan, Awning 43.8x4.3 Fabric blue + AwningValance, Sign_24시 · 택배 · ATM, Sign_LOTTO 6/45, window decal signs (1+1 · 2+1 행사 / 반값택배 접수 / 도시락 · 김밥 할인), IceFreezer '얼음 ICE' outdoor 4.8x3.6x2.8, WaterPack x4, PromoBanner '도시락 할인', RecycleBins (4 Bin + Lid)",
    "Terrace: Deck 46x0.44x12 WoodPlanks + DeckEdge; PlasticTable x3 (Top 3.4 square, Leg, UmbrellaPole, Umbrella 9-dia cylinder, 4 ChairSeat Seat (Disabled) + 4 ChairBack + 8 ChairLeg each) - green plastic, blocky",
    "JobStations folder: 24 invisible 1x1x1 Station_* anchors + GwJobSpawn 4x1x4 (see gameplay)",
    "Destination 4x1x4 invisible at (-304.69,7.06,302.05) DisplayName 'GS25 광안리점' (tag Destination)"
   ],
   "gameplay": [
    "JobWorld (server, job 'gs25'): reads GwJobStation-tagged Station_* parts by attrs Job/Station/Place: counter(-329.04,7.5,304.40), counter_items(-325.93,11.1,304.26, Span 3.2), counter_scanned(-325.88,11.1,301.36), boss(-329.26,7.5,300.20), backroom(-370.70,7.5,291.22), chiller(-346.68,7.5,301.37), chiller_items(-346.73,10.25,303.97, Span 7), slot_food(-353.65,8.25,291.64), slot_snack(-353.50,8.25,283.14), slot_life(-353.34,8.25,274.64), slot_drink(-321.04,8.25,275.24) [slots: Category, Rows 3, RowGap 1.5, Width 2.8; runtime Stock/StockMax attrs], door_out(-299.69,7.5,302.15), door_in(-311.69,7.5,301.92), front(-319.44,7.5,299.28), aisle1(-319.23,7.5,288.03), aisle2(-319.07,7.5,279.53), aisle3(-318.88,7.5,269.28), b3mid(-355.42,7.5,287.36), browse1..4 (attrs Path,Say), queue1(-322.84,7.5,304.72), queue2(-319.84,7.5,304.77), queue3(-316.93,7.5,304.23), buy_drink(-356.42,7.5,276.59, Shop=store_drink), buy_shelf(-319.71,7.5,292.27, Shop=store_shelf); GwJobSpawn(-331.88,7.5,301.15)",
    "JobWorld cvs.setup: storeModel = counter.Parent.Parent (the GS25 model); creates JobStations/GwCvsRuntime anchors microwave/hotwater/scale/parcel_pile/drawer/card_reader/alarm/wall_clock and SNAPS them by searching storeModel:GetChildren() for DIRECT children named StaffMicrowave (reach 12), HotWaterMachine (70), CashDrawer (5), CardTerminalScreen (6) -> these names must stay direct children at their positions; counter station gets CvsBell/CvsBellSeq attrs",
    "JobWorld customers walk the station graph door_out->door_in->front->aisleN->browse/slot->queue1..3->counter; carried props RestockBox / ParcelBox welded to the player",
    "JobCvs (server): 진열 = hold E at backroom (box of emptiest slot) then hold E at the glowing slot (ProximityPrompt 'GwangalliWorkPrompt' with attr GwCvsSlot under workspace.GwangalliWorkPoints); counter 🔔 interrupt; 🙋 greet window after the AutoDoor chime; specials parcel/ask/heat/wrap/charge/find/refund",
    "JobCvsPlus (server, everyone sees): builds workspace.GwCvsPlus/Display_<slot> product models at each slot anchor (anchor.CFrame * (col x, row*RowGap-0.5, z): 3 rows x 4 cols x 2 deep + PriceTag parts), Stock-driven visibility, '상품 정리' facing prompts; events: spill (aisle near a slot), parcel_driver (backroom), fridge_door (chiller), basket (front), receipt (counter), promo (slot), umbrella (door_in, rain), trash (door_out), quick-button boss_call/cctv/drunk",
    "GwangalliStaff (점장 mode NPC 알바생 counter/stock/clean): uses gs25 stations; builds a walk visibility graph ONCE by server raycasts against CanCollide parts with Transparency<0.9 plus a 3-stud grid -> any new server-side collidable prop in aisles changes/blocks NPC paths (client-only props are invisible to it)",
    "GwangalliJobs/World (client): finds GwPosScreen POSMonitor -> PosScreen.Bg.{Head,Lines,Total} text; GwPosCustomer/GwPosScanner/GwPosPrinter tags; frameStation camera framing at counter_items / chiller_items; Highlight on active restock slot; CvsWorld persona cards over customers in workspace.GwangalliNPCs",
    "ShopLife/Scan (server): GS25 model is a 'venue' candidate because it has direct child Gondola_1 / OpenChiller; reads Gondola_n + Fridge/OpenChiller (FridgeDoor) as pick shelves, CustomerDisplay as POS, CounterTop as counter, Microwave/MicrowaveWindow, ATMScreen, RecycleBins model (bin), HotBar (steamer), AutoDoor_GS25 (door), Terrace 'Top' under PlasticTable as tables + ChairSeat seats. NOTE: looks for 'HotWater' (part is 'HotWaterMachine') and 'IceCreamChest'/'ChestGlass' (part is 'IceCreamFreezer') so those two fixtures get no ShopLife prompt today",
    "ShopFlows cvs pick ('담기') / pay ('계산하기'), unpaid goods leaving the store put back; JobShop F-prompt '고르기' on Station_buy_drink (cvs_water/cola/banana/coffee/energy/tea) and Station_buy_shelf (cvs_samgak/ramen/dosirak/sandwich/choco/chips), held prop in hand, takes Stock from the matching slot",
    "Bank: any part named 'ATM' gets an ATM ProximityPrompt (kind cvs from the 'GS25'/'convenience' ancestor) - keep the 'ATM' part",
    "Law/Crimes: 편의점 슬쩍하기 hold prompt at the Destination of GS25 (SHOP_WORDS 'GS25'); StreetInteract/Places + Play/Manager/StaffSim: NPC shoppers use the station graph, terrace ChairSeat within 60 studs of door_out become NPC seats 'gs25_chairN'; Places opens AutoDoor via AutoDoorOpener proxy",
    "GwangalliNav: node 3022 'GS25 광안리점' at (-304.7,6.6,302.1); Coach lesson gs25 steps at backroom/chiller/counter/microwave/alarm stations",
    "DetailLOD (client): Gondola_n/Fridge/OpenChiller are LOD='zone' (TAG ZoneLOD), NearDetail/Detail are LOD='near' (NearLOD) - hidden via LocalTransparencyModifier (Util.setHidden) -> an interior replacer must not hide originals with LTM alone (DetailLOD rewrites it) and should tag its own detail NearLOD",
    "Lights: SurfaceLights tagged InteriorLight with AlwaysOn=true are enabled by GwangalliWorld/Lights within InteriorRadius; signs tagged GwSurfaceGui / NightGlow, FasciaStripeCyan NeonTube",
    "Annex skips everything under 'convenience' (HOST_VENUES) -> no generated interior; DO NOT rename/move/block: Station_* + JobStations + GwJobSpawn, Destination, AutoDoor_GS25, StaffMicrowave, HotWaterMachine, CashDrawer, CardTerminalScreen, POSMonitor(+PosScreen gui), CustomerDisplay, BarcodeScanner, ReceiptPrinter, CounterTop, Gondola_1..3, OpenChiller, Fridge(+FridgeDoor), ATM/ATMScreen, Microwave, HotBar, RecycleBins, Terrace ChairSeat; keep 2.2-stud stand spots in front of each slot anchor and the queue lane z~304.5 x-323..-317 clear"
   ],
   "emptyOrCrude": [
    "950 'Product' parts are flat-coloured SmoothPlastic bricks (0.5-0.95 x 0.6-1.1 x 1.05-1.5): no bag/cup/can/bottle/box silhouettes, no labels or brand art, no peg-hook bags, identical depth on every shelf -> reads as Lego blocks, not 과자/라면/생활용품",
    "200 fridge 'Bottle' parts are single-colour cylinders 0.27 dia: no caps, no PET vs can vs glass vs 우유 carton, no labels, no shelf price strips on the 15 WireShelf; the whole fridge front is ONE 6.6x6.2 glass slab per unit (3 handles, 2 mullions) - doors cannot open, FridgeGlow is a flat neon slab",
    "Cigarette wall = 30 strip parts (~2 x 0.6) instead of ~150 individual packs with price labels; no e-cigarette devices/sticks, no lighters",
    "Counter is a single 8x3.3x2.6 box; no lotto terminal / slip stand / pens even though 'LOTTO 6/45 로또 판매점' sign is outside; no 교통카드 charger; no parcel scale / label printer for the 계산대 · 택배 접수 + 반값택배 signage; no 종량제 bag rack; impulse display = 3 GumRack cubes",
    "Coffee machine and steamer sit behind the counter on the BackCounter: no customer self-coffee station (cups, lids, straws, ice cups)",
    "IceCreamFreezer is a solid 9x3x3.5 box with a flat glass lid; the 14 IceCream blocks are sunk into the solid body; no wire baskets, no frost, no discount POP besides the front label",
    "No shopping-basket stack at the entrance (JobCvsPlus 'basket' event refers to one), no umbrella stand/bag dispenser, no bread rack, no promo 평대 - the front window strip x-320.7..-309 z263..285 (~11x22 studs) is empty floor",
    "No reach-in frozen-food freezer (만두/얼음컵/봉지얼음), no ramen tower/컵라면 wall, no liquor-specific section (only a beer sign on the 5th fridge), no hot-pack/charger/battery peg display",
    "Eat-in: 22-stud standing bar with no stools; HotWaterMachine/Microwave/SoupSink are plain boxes/plates; recycling bins only outside; no napkin/utensil dispensers beyond 3 TissueBox + 3 ChopstickHolder",
    "Ceiling: plain board + T-bars + neon strips; no sprinkler heads, smoke detectors, speakers, convex mirror, hanging promo POP; only 2 CCTV balls for a 55x45 store",
    "Walls: north wall above the open chiller/counter and the west wall above the fridges are blank plaster; no posters/menus (카페25 menu), no wall clock (wall_clock is only an invisible runtime anchor), no category wall graphics, no window posters on the inside of the glass",
    "Floor: one tile slab, no wet-floor sign/mop for the spill event, only one queue decal set",
    "Gondola shelves: 4 boards + base, no shelf-edge lips, no hooks, uprights are 0.2 slabs; CategoryHeader is a single 30-long blue bar",
    "Terrace: blocky green plastic chairs (seat/back slabs + 2 legs each) with 9-dia cylinder umbrellas; ChairSeat Seats are Disabled (cannot sit)"
   ],
   "realWorld": [
    "Entrance: 자동문 + 딩동 차임, 바닥 매트, 24H/영업시간·결제수단 스티커 (삼성페이·카카오페이·네이버페이·제로페이·VISA), 파란 GS25 장바구니 스택, 우산 비닐 커버기·우산꽂이 (비 오는 날), 유리창 안쪽 행사 포스터 (1+1·2+1·반값택배·알바 모집)",
    "Counter (계산대): POS 2대 + 고객용 디스플레이, 핸드 스캐너 + 거치대, IC 카드단말기/서명패드, 교통카드 충전기, 영수증 프린터, 금전함, 비상벨(112), 신분증 확인·19세 미만 스티커, 종량제/종이봉투 걸이, 계산대 앞 충동구매 매대 (껌·사탕·젤리·초콜릿·핫팩·건전지·충전케이블)",
    "Lotto (로또 판매점): 로또 단말기 + 슬립/펜 거치대 + 당첨 안내 포스터; 택배: 반값택배/GS Postbox 접수 저울 + 송장 출력, 택배 픽업 선반",
    "Behind counter: 백라이트 담배장 (개별 갑 ~150 SKU, 가격표), 전자담배 기기·스틱 (IQOS/glo/lil), 라이터 랙, 상품권/기프트카드 랙",
    "Hot food: 카페25 셀프 원두커피 머신 + 컵/뚜껑/빨대/아이스컵 스테이션, 호빵·찐빵 스티머, 핫바/어묵 워머, (일부) 치킨25 튀김기·워머",
    "Cold: 워크인 냉장 도어 10~15칸 (탄산·이온·생수·커피·차·우유·요구르트·주스·맥주·소주·막걸리·하이볼), 칸별 가격 레일·행사 POP, 문 닫힘 경보, 오픈 쇼케이스 (도시락·삼각김밥·김밥·샌드위치·햄버거·샐러드·디저트), 리치인 냉동고 (냉동식품·얼음컵·봉지얼음), 슬라이딩 유리 아이스크림 평형 냉동고 + 할인 POP",
    "Gondolas 1.35-1.6 m, 5단 + 후크: 라면 (봉지 묶음·컵라면 탑), 과자, 초콜릿·사탕, 빵 랙, 즉석밥·통조림·즉석식품, 생활용품 (휴지·물티슈·세제·칫솔·면도기·생리대·마스크·건전지·충전기·우산·양말), 반려동물 간식, 문구; 엔드캡 1+1/2+1, 전자가격표(ESL)/쇼카드",
    "Eat-in: 창가 바 테이블 + 하이체어, 온수기 (물 붓는 선 안내), 전자레인지 2~3대 + 사용법 스티커, 라면 국물 버리는 통/싱크, 냅킨·젓가락·포크 디스펜서, 분리수거함 (일반·캔·페트·음식물), 콘센트",
    "Building services: ATM, CCTV 돔 4~8대, 볼록거울, 매장 스피커, 스프링클러·화재감지기·유도등·소화기, 벽시계, 카테고리 행잉 사인, 600각 타일, '미끄럼 주의' A-board",
    "Terrace: 플라스틱 테이블·의자 + 파라솔, 금연 스티커, 쓰레기통"
   ],
   "interactionIdeas": [
    "Fridge door (each of 15 doors, x≈-359.8): E = swing hinged glass door open (fog/cold light, auto-close after 6 s, door-ajar chime); pick a drink -> routes to existing JobShop buy_drink sheet; JobCvsPlus 'fridge_door' event shows the door visibly ajar",
    "Gondola product pick: E on a shelf facing = take that item into hand/basket (ShopFlows cvs '담기'), the facing gets a gap until restocked (ties to slot Stock)",
    "Basket stack at entrance (x-311, z299): E = take a 장바구니 (carried in hand), return it at the stack; 'basket' event = tidy toppled baskets",
    "Self coffee (move CoffeeMachine-like station to customer side near x-339 z296): place cup -> choose 아메리카노/라떼 (HOT/ICE) -> 25 s brew with steam and sound -> cup in hand",
    "Microwave (x-342.6 z263.7): E open door, put 도시락, set 1:30, ding; hot-water dispenser: fill 컵라면 to the line, 3-min timer, eat at standing bar (fix: alias HotWaterMachine as ShopLife 'HotWater')",
    "Soup sink: E = 국물 버리기 after eating; recycling bins: sort cup/lid/chopsticks",
    "Ice-cream chest: E slide glass lid, choose bar/cone/cup; steamer: open lid, take 호빵/핫바",
    "Counter extras: lotto terminal (buy 로또 6/45 auto/manual, draw on Saturday 20:35 game time), 교통카드 충전 (special 'charge'), 반값택배 kiosk (weigh parcel on scale, print label - special 'parcel'), cigarette request with ID check (Staff id_check)",
    "Umbrella stand appears in rain (umbrella event) with 우산 비닐 dispenser; wet-floor A-board + mop for spill event",
    "Eat-in stools: sit (ShopLife seat), window view to the street; terrace: enable ChairSeat sitting",
    "CCTV monitor in stock room mirrors 4 camera views (CCTV event)"
   ]
  },
  {
   "name": "GS25 광안리점 창고 · 직원실 (StockRoom / back room)",
   "path": "Workspace.Gwangalli.convenience[\"GS25 광안리점\"].StockRoom (+ StaffDoor*, BackDoor, RollCage/Boxes outside)",
   "bounds": "min(-386.97,7.0,261.33) max(-363.75,18.0,306.14)",
   "enterable": true,
   "rooms": [
    {
     "name": "Stock room (창고 + 직원 공간)",
     "center": [
      -375.36,
      12.5,
      283.73
     ],
     "size": [
      23.22,
      11,
      44.81
     ],
     "floorY": 7,
     "ceilingY": 18
    },
    {
     "name": "Staff door opening (always open, from sales floor)",
     "center": [
      -364.12,
      11.2,
      303.15
     ],
     "size": [
      1,
      8,
      3.6
     ],
     "floorY": 7,
     "ceilingY": 15
    },
    {
     "name": "Back door (closed metal slab, to yard)",
     "center": [
      -387.41,
      11.05,
      284.71
     ],
     "size": [
      0.15,
      9.1,
      4.4
     ],
     "floorY": 7,
     "ceilingY": 15.6
    }
   ],
   "props": [
    "StockFloor 44.4x0.5x22.4 Concrete #969692, StockCeiling SmoothPlastic, StockLining Plaster (north)",
    "LightPanel x2 Neon (16x2 with SurfaceLight Range24 AlwaysOn; 14x2 without light)",
    "Racks x3 along west wall (x-386.8..-382.8, z265..303): RackPost x12 0.3x8.5 + RackDeck x9 11.3x0.15x3.3 DiamondPlate + Carton x44 blank Cardboard 0.8-2.6 x1.3-2.3 x2.5",
    "RestockBoxes (NearLOD): RestockBox x5 Cardboard 2.2-2.6 x1.85 (one with '입고 · 진열용' gui) on HandTruckBase 6.4x0.4x3 blue slab at (-373.2,7.2,291) next to Station_backroom",
    "RollCage 3x5.6x2.6 DiamondPlate t0.5 + CageBoxes",
    "StaffSink 2.85x3.2x4 solid Metal box (no basin/faucet) at (-367,8.6,263.3)",
    "StaffDesk 4.4x0.3x4 WoodPlanks + DeskLeg x2 + CCTVMonitor 2.2x1.6 'CCTV 1 · 2 · 3 · 4' text (no chair)",
    "StaffLocker x4 2x7x1.6 solid metal blocks (x-366.2..-364.5 z268.6..276.9)",
    "WorkNotice 6x3 '알바 수칙 ① 손님께 인사 ② 유통기한 확인 ③ 박스는 빈 칸부터 진열', TimeClock 1.4x1.6 '출퇴근 기록기', MopBucket cylinder",
    "Outside the back wall: RollCage x2 + Boxes x2 at x-390 z289..295, OutdoorAC x3 + ACFan x3 at x-389.6 z322..332"
   ],
   "gameplay": [
    "Station_backroom (-370.70,7.5,291.22): JobCvs 진열 phase 1 (hold E, takes the box of the emptiest slot -> RestockBox welded to chest); JobCvsPlus 'parcel_driver' event (hold E '물건 받기'); Coach 'backroom' step; GwangalliStaff stock role walks here",
    "Staff door gap x-364.1 z301.4..304.9 is the only route sales floor <-> backroom for players and NPC graph - must stay open/walkable",
    "DetailLOD NearLOD on RestockBoxes/NearDetail; InteriorLight on the 16x2 panel"
   ],
   "emptyOrCrude": [
    "Racks are 4 bare posts + 3 plank decks each - no beams, braces, labels; 44 cartons are blank brown bricks (no tape, print, barcodes)",
    "No walk-in cooler behind the beverage doors: FridgeGlow backs sit flush on BackWall x-364 and the stock-room side is empty wall - in a real GS25 staff restock drinks from inside the walk-in",
    "Half the room (x-382..-366, z261..281) is empty concrete; ceiling is a plain board",
    "Staff sink is a solid box; desk has no chair/PC/발주 단말기; lockers are solid blocks with no doors; no uniform (GS25 조끼) hooks, safe (금고), 폐기 basket, flattened cardboard pile, milk crates, cleaning shelf",
    "Back door is a flat 4.4x9.1 metal slab with no push bar/handle/closer; hand truck is just a blue slab"
   ],
   "realWorld": [
    "워크인 냉장고 내부 (음료 뒤 보충 통로, 랙에 박스 음료, 냉기 커튼)",
    "철제 앵글 랙 + 상품 박스 (라면·과자·생수 6입·휴지), 입고 박스 카트(롤테이너), 우유 플라스틱 상자, 도시락 배송 트레이",
    "발주 단말기/PDA 충전 거치대 + 점포 PC, 금고 (시재), CCTV 모니터, 근무 스케줄표·체크리스트·유통기한 폐기 바구니",
    "직원 사물함 + GS25 유니폼(조끼) 걸이, 의자, 소형 냉장고/전자레인지 (직원용)",
    "청소 도구 (대걸레·양동이·빗자루·쓰레기봉투), 개수대 + 수전, 박스칼·테이프, 납작하게 접은 박스 더미, 분전반, 소화기, 비상구 유도등"
   ],
   "interactionIdeas": [
    "TimeClock: E = 출근/퇴근 찍기 (start the gs25 shift from here as an alternative to the counter)",
    "Locker: E open door -> put on GS25 vest (uniform from GwangalliWorkSpots), store items",
    "Walk-in cooler (build behind the fridge wall, enter from stock room): push bottles forward -> front facings fill (mirrors slot_drink Stock)",
    "CCTV monitor: E = view 4 camera feeds (ViewportFrame of the sales floor) - resolves JobCvsPlus 'cctv' event",
    "Expiry check: E on 폐기 basket = scan expired 삼각김밥 (special 'expiry'), safe: 시재 점검 mini-task",
    "Back door: E = 택배 기사 receive (parcel_driver event) with a delivery man NPC and sign pad"
   ]
  },
  {
   "name": "광안로 상가 (GS25) - 1F 공용 로비·계단 + 2F 수영 365 내과의원 + 3F 광안 공인중개사 + 옥상",
   "path": "Workspace.Gwangalli.convenience[\"광안로 상가 (GS25)\"] (shell/upper floors) + lobby parts inside Workspace.Gwangalli.convenience[\"GS25 광안리점\"] (Door, Transom, DoorHandle, LobbyFloor, LobbyCeiling, LobbyLight, Partition x2, Step x8)",
   "bounds": "building min(-388.87,6.5,260.51) max(-306.74,46.2,365.99); lobby min(-331.18,6.8,307.56) max(-309.4,19.9,317.97); upper-floor Core min(-388.25,20.5,261.42) max(-308.26,42.5,365.06)",
   "enterable": false,
   "rooms": [
    {
     "name": "1F lobby + stair (공용 현관·계단실, sealed)",
     "center": [
      -320.29,
      13.35,
      312.77
     ],
     "size": [
      21.78,
      13.1,
      10.41
     ],
     "floorY": 6.8,
     "ceilingY": 18
    },
    {
     "name": "2F 수영 365 내과의원 (solid Core block, no interior)",
     "center": [
      -348.26,
      26.2,
      313.24
     ],
     "size": [
      80,
      10.6,
      103.6
     ],
     "floorY": 20.9,
     "ceilingY": 31.5
    },
    {
     "name": "3F 광안 공인중개사 · 원룸 투룸 상가 (solid Core block, no interior)",
     "center": [
      -348.26,
      37.2,
      313.24
     ],
     "size": [
      80,
      10.5,
      103.6
     ],
     "floorY": 32,
     "ceilingY": 42.5
    },
    {
     "name": "Roof (parapet, penthouse 11.5x9x10 with RoofDoor, water tank, 3 AC condensers)",
     "center": [
      -347.91,
      43.1,
      313.25
     ],
     "size": [
      103.9,
      0.6,
      79.9
     ],
     "floorY": 43.1
    }
   ],
   "props": [
    "Lobby: Door 7x8.3 Glass t0.3 (solid, CanCollide default true, no prompt) + Transom + DoorHandle 3-stud bar at x-309.3 z309.5..316.5; Sign_광안로 상가 '2F 내과 · 3F 부동산' above",
    "LobbyFloor 10x0.3x21.6 Granite (x-331.2..-309.4), LobbyCeiling only over the front 9 studs (x-318.4..-309.4), LobbyLight Neon 8x2",
    "Step x8 Granite 9 wide, run 1.56, rise 0.98 each, solid to the floor, x-330.9..-318.2 rising to y14.6 then a blank Partition at x-331.5 (stair to nowhere)",
    "Partition (GS25 model) x3: lobby north wall z317.6..318.8 (shared with delivery), lobby west wall x-331.5, GS25 north wall z305.7..308.0",
    "Upper floors: Core 102.2x22x78.1 solid Concrete #2e2e32 filling 2F+3F; Slab 104x1x80 CeramicTiles at y20.4",
    "Facade: Window x30 Glass t0.2 (tag NightWindow, LitChance/LitColor/Zone office|corridor), Blinds one 103x2.5 strip, Pier x28, Spandrel x4, Lintel x4, Sash x4, FloorBand x2, WinFrame/WinJamb/WinStile (FacadeDetail), PartyWall x2",
    "Signs: Sign_수영 365 내과의원 · 건강검진 62x3.4 band (2F), Sign_광안 공인중개사 · 원룸 투룸 상가 62x3.4 band (3F), vertical blade signs Sign_딜리버리 and Sign_내과 0.9x14x3.2 on Brackets",
    "WallServices: ACUnit, DrainHose, DownPipe, GasPipe, CableBundle; Roof: Roof, Parapet x4, Coping x4, RoofPatch, Penthouse, RoofDoor, TankStand x2, WaterTank 6x5x6, ACSkid + ACCondenser x3 (+ ACFan), VentStack x2"
   ],
   "gameplay": [
    "No gameplay inside. Annex skips it (ancestor 'convenience' is a HOST_VENUE) so no generated 'go upstairs' interior; StreetSigns/SignStyles treat 'convenience' as HOST_ANCESTORS (sign styling only)",
    "NightWindow tagged windows are lit at night by the environment system (attrs LitChance/LitColor/LitSeed/Zone) - lit glass shows the black Core behind",
    "The lobby north Partition is the wall behind the delivery office's fake restroom door (Door_restroom at x-331.6 z318.6); an enclosed unused void exists at x-388..-332 z308..316.5 (no floor, only PlotPaving)"
   ],
   "emptyOrCrude": [
    "Lobby is sealed: the glass Door is a static collidable part with no ProximityPrompt; the lobby cannot be reached from street, GS25 or delivery",
    "Stair to nowhere: 8 solid granite blocks rise 7.8 studs and end against a wall; to reach the 2F slab (top 20.9) needs a landing at ~y13.9 and a return flight (total rise 14.1 studs); no handrail, nosing, wall light, 층별 안내판, 우편함, 소화기, 계량기함",
    "2F clinic and 3F realtor named on huge signs are one solid dark concrete block behind 20 % transparent glass; Blinds are one continuous strip; nothing to see or enter"
   ],
   "realWorld": [
    "1F 공용 현관: 유리 여닫이문 (당기세요/미세요), 층별 안내판 (2F 수영 365 내과 · 3F 광안 공인중개사), 우편함, 센서등, 계단 핸드레일·논슬립, 소화기, 계량기/분전함, CCTV, 전단지 붙은 게시판",
    "2F 내과의원: 접수·수납 데스크 (PC, 카드단말기, 번호표/대기 모니터), 대기 의자 열 + TV + 정수기 + 잡지, 진료실 2 (책상·PC·진료 침대·혈압계·청진기), 주사실/수액실 (침대 + 커튼), 건강검진 구역 (채혈실·X-ray·초음파·내시경실·탈의실), 처방전 프린터, 화장실, 손소독제",
    "3F 공인중개사: 창문/유리 매물 포스터 (원룸·투룸 보증금/월세), 중개사 책상 2~3 + PC, 상담 테이블 + 소파, 매물 지도·단지 배치도, 중개사 자격증·사업자등록증 액자, 서류 캐비닛, 정수기, 화분",
    "Roof: 옥탑 계단실, 물탱크, 실외기, 안테나, 빨래줄/평상 (부산 상가 옥상 흔함)"
   ],
   "interactionIdeas": [
    "Lobby door: E = 문 열기 (hinged) and a floor directory prompt that teleports/walks to 2F/3F",
    "Mailboxes (우편함): E = check mail (ties to phone/home systems)",
    "2F clinic: 접수 kiosk/desk -> wait number on monitor -> 진료 (ties to Health system), 수액 bed rest",
    "3F realtor: browse listing posters/PC (ties to GwangalliHomesShared housing), 상담 seat with an NPC agent",
    "Stair landing light sensor (센서등) that turns on when a player approaches"
   ]
  },
  {
   "name": "광안 딜리버리 사무실 (배차실 · 라이더 대기 · 퀵 출발대)",
   "path": "Workspace.Gwangalli.delivery[\"광안 딜리버리\"] (office half, x > -341.9)",
   "bounds": "min(-341.86,6.8,318.18) max(-309.5,18.0,365.16)",
   "enterable": true,
   "rooms": [
    {
     "name": "Office / dispatch floor (T-bar ceiling)",
     "center": [
      -325.68,
      12.4,
      341.67
     ],
     "size": [
      32.36,
      11.2,
      46.98
     ],
     "floorY": 6.8,
     "ceilingY": 18
    },
    {
     "name": "Dispatch table island (table x-325..-320.8 z333.7..346.8, NPC 배차 실장 behind at x-327.5)",
     "center": [
      -323,
      8.3,
      340.25
     ],
     "size": [
      5,
      3.1,
      13.1
     ],
     "floorY": 6.8,
     "ceilingY": 18
    },
    {
     "name": "Rider gear corner (5 lockers + 4 helmet hooks + 4 delivery boxes, SE)",
     "center": [
      -319.7,
      10.3,
      322.4
     ],
     "size": [
      17.4,
      7,
      7.4
     ],
     "floorY": 6.8,
     "ceilingY": 18
    },
    {
     "name": "Quick shelf (퀵 물건 · 출발 대기, north wall)",
     "center": [
      -326.84,
      10.6,
      363.3
     ],
     "size": [
      18.1,
      7.6,
      3.2
     ],
     "floorY": 6.8,
     "ceilingY": 18
    },
    {
     "name": "Waiting benches + water purifier + plant (west side by low wall)",
     "center": [
      -337.8,
      9,
      340
     ],
     "size": [
      4,
      4.6,
      44
     ],
     "floorY": 6.8,
     "ceilingY": 18
    },
    {
     "name": "Fake restroom door (no room behind)",
     "center": [
      -331.6,
      10.55,
      318.55
     ],
     "size": [
      3.4,
      7.5,
      0.3
     ],
     "floorY": 6.8,
     "ceilingY": 14.3
    },
    {
     "name": "Entrance (AutoDoor_Delivery 6 wide, x-309.8 z339..345)",
     "center": [
      -309.83,
      11.25,
      341.97
     ],
     "size": [
      1,
      8.9,
      6.6
     ],
     "floorY": 6.8,
     "ceilingY": 16.9
    }
   ],
   "props": [
    "Floor x1 46.4x0.3x77.7 SmoothPlastic #b0b6ba shared with the warehouse (no tile/epoxy split)",
    "Ceiling/CeilingBoard 46.4x0.3x31.5 + TBar x16; LightPanel x5 here (two 4x18 with SurfaceLight Range28 AlwaysOn, three 0.9x26 strips); CassetteAC x3 + ACVanes/ACGrille; SmokeDetector x3; CCTV x1 + mount; ExitSign over door; Baseboard x2",
    "WallLining Plaster (north 77.7 long, south 22.5) + BrandBand yellow 31.5 on north wall; LowWall x2 15-17 long x4.2 tall + black LowWallCap (half partition to warehouse with 14-stud opening z333.4..347.4) + SortSign '분류장 · 상차장 →'",
    "DispatchTableTop 13x0.3x4 WoodPlanks + DispatchModesty 12.4x2.8 + DispatchLeg x2 (slabs) + DispatchMonitor x3 3.2x2 static SurfaceGui ('퀵 배차 현황 대기 4 · 진행 7 · 평균 18분', '택배 상차 현황 오늘 128건 …', '광안리 배송 구역 …') + MonitorStand x3 + Keyboard x1 + LabelPrinter + Radio + TablePlate '배차 테이블 · 퀵 / 택배 선택'",
    "Chair x1: ChairSeat 1.5x0.2x1.5 Wood + ChairBack + 4 ChairLeg",
    "배차 실장 NPC (anchored R15 rig, tag GwJobStaff, attrs Job=delivery NpcName=배차 실장) at (-327.5,9.89,340.14) with Phone (hidden) + Camera parts",
    "QuickShelf: ShelfBack 18x7.6x2.8 solid metal box + ShelfDeck x4 + Parcel x40 blank Cardboard bricks (0.7-2 x0.64-1.5 x2) + Sign_퀵 물건 · 출발 대기",
    "Locker x5 1.65x7x2 solid Metal blocks (x-328.4..-318 z318.6..320.4)",
    "HelmetHook x4 + Helmet x4 (1.3 Ball parts: white/red/black/yellow) + DeliveryBox x4 1.6 cyan cubes on the floor (x-312.9 z319.9..325.3)",
    "Bench x2 (Seat, Disabled) 3.4x0.4x1.6 + BenchBase x2; WaterPurifier 1.4x4.6x1.4 box + PurifierLamp neon",
    "Plant: Pot 4.4 cylinder + Soil + 2 Leaves sphere-mesh LeafyGrass up to y21.98 at (-337.5,*,320.3)",
    "RouteMap 8x4.8 text panel '광안 배송 구역도 ①…⑤' + MapPin x4; NoticeBoard 5x4 '오늘의 공지 · 헬멧 필수 …'",
    "FitOut/Door_restroom: DoorCasing 3.4x7.5 + DoorLeaf 2.8x7.2 Wood + DoorHandle + Sign_화장실 남·여",
    "FireExtinguisher x1 + Sign_소화기 (x-338.8 z363.9)",
    "Storefront: ShopWindow x6 6.6x9.4 Glass t0.55, Mullion x8, Sign_광안 딜리버리 22x3.2 yellow, Sign_24시 퀵 · 당일 택배, window decals 라이더 · 택배기사 모집 / 퀵 30분 · 광안리 전 지역, Car_Scooter (yellow 125cc with red DeliveryBox) parked outside at x-302.3 z330.5..335.3, Destination"
   ],
   "gameplay": [
    "JobDelivery (server): Station_dispatch (-319.30,7.30,340.29) gets ProximityPrompt 'GwangalliDispatchPrompt' (E, hold 0.3, 10 studs, '퀵 / 택배 고르기' · '🛵 배차 테이블') -> openDispatch -> delivery_quick / delivery_parcel shift start",
    "Station_shelf (-326.78,7.30,360.25): 퀵 'pickup' task prompt in front of QuickShelf (ParcelBox to the hands); Station_dock / Station_pad / Station_exit in warehouse/yard; GwJobSpawn (-316.21,7.3,329.84) 4x1x4",
    "배차 실장 model = JS.BOSS delivery staff (tag GwJobStaff); GwangalliWorkSpots delivery_quick/delivery_parcel: sources station 'dispatch' or point 'delivery_quick_dispatch', uniforms '광안 딜리버리'; WorkConfig ranks 신입 라이더..전설의 라이더",
    "Destination (DisplayName '광안 딜리버리') at (-305.44,7.06,342.05) = ctx.dest(OFFICE) used by JobDelivery.officePos (returns, distance pay)",
    "AutoDoor_Delivery (tag AutoDoor) opened for NPCs by StreetInteract/Places; Annex skips 'delivery' ancestor; not a ShopLife candidate (no Gondola_1/OpenChiller/Interior) -> WaterPurifier/Bench/Door_restroom have no prompts today",
    "DetailLOD NearLOD on FitOut/Detail and NearDetail groups; InteriorLight SurfaceLights on 3 panels",
    "Keep clear: door (x-309.8 z342) -> Station_dispatch walk line; table/NPC island; QuickShelf front (Station_shelf); LowWall opening z333.4..347.4 to the warehouse"
   ],
   "emptyOrCrude": [
    "Floor is one plain SmoothPlastic slab for office + warehouse; no vinyl tile, no entrance mat, no floor markings",
    "Dispatch desk is a slab table on slab legs with 3 static text monitors, one keyboard, no PCs/mice/headsets/phones/chargers; only one cheap chair for a 13-stud table",
    "QuickShelf is a solid 18x7.6x2.8 metal block with parcels embedded in its faces, not open shelving; 40 parcels have no tape, waybill labels or size variety",
    "Lockers are solid blocks (no doors/vents/name tags); helmets are plain spheres on hooks; delivery boxes are bare cyan cubes",
    "No rider lounge: 2 disabled benches only - no sofa, TV, vending/coffee-mix table, microwave, fridge, phone charging station, rain-gear rack, insulated bag shelf",
    "Plant clips through geometry: leaves reach y21.98 (ceiling 18.0, slab 19.9-20.9) and z316.7 (south wall at 318.4); pot is a 4.4-stud cylinder",
    "Restroom door is a facade - no restroom room behind it (the area behind is the sealed lobby/void)",
    "No customer drop-off counter (scale, label printer, waybills, boxes/tape) despite '24시 퀵 · 당일 택배' and '배달 문의' signs",
    "Walls: two flat text panels (RouteMap, NoticeBoard) on otherwise bare plaster; no clock, whiteboard of today's rankings, safety posters, rider recruitment poster inside"
   ],
   "realWorld": [
    "접수 카운터: 퀵/택배 접수 PC, 저울, 운송장 프린터, 포장재 (박스·테이프·에어캡), 요금표, 카드단말기, 대기 의자",
    "배차실: 배차 PC 2~3대 × 듀얼 모니터 (배차 프로그램 지도·콜 리스트), 헤드셋/유선전화, 무전기 충전 거치대, 벽걸이 TV (실시간 콜 현황), 화이트보드 (오늘 건수·라이더 순위), 프린터, 서류함, 사무용 의자 여러 개",
    "라이더 대기실: 소파·접이식 의자, TV, 정수기, 믹스커피·컵라면·간식 선반, 소형 냉장고, 전자레인지, 휴대폰 멀티 충전 스테이션·거치대, 사물함 (이름표), 헬멧 거치대 다수, 우비·방한복·토시·장갑 걸이, 보온/보냉 배달가방·배달통 선반",
    "벽: 안전 포스터 (헬멧·신호 준수·보험), 라이더 모집 포스터, 배송 구역 지도 + 핀, 벽시계, 공지 게시판",
    "정비 코너: 타이어 공기주입기, 공구함, 엔진오일·체인 루브, 전기 오토바이 배터리 충전/교환",
    "실제 화장실 (세면대·거울·핸드드라이어), 소화기, CCTV, 비상구 유도등"
   ],
   "interactionIdeas": [
    "Dispatch monitors: live SurfaceGui list driven by JobDelivery (waiting / in progress / avg time) - E on a monitor = preview today's calls before choosing",
    "Helmet rack: E = take/return helmet (wear accessory; NoticeBoard '헬멧 필수' check before quick shift)",
    "Insulated bag/box shelf: E = take 보온가방 (back accessory) for 퀵",
    "Locker: E open personal locker (door swings), store/change into the 광안 딜리버리 uniform",
    "Phone charging station: E = charge phone (phone battery stat), rider lounge sofa sit + TV on/off (channel cycles), coffee mix + water purifier cup",
    "Reception scale + label printer: E weigh customer parcel -> print waybill (new mini task for delivery_parcel)",
    "Quick shelf: highlight the specific parcel for the current order (label shows 건물/호수 from JobDelivery)",
    "Restroom: real small restroom built into the void behind the door (x-388..-332 z308..316.5) with sink/hand-dryer prompts"
   ]
  },
  {
   "name": "광안 딜리버리 분류장 · 상차장 (sorting warehouse + loading dock)",
   "path": "Workspace.Gwangalli.delivery[\"광안 딜리버리\"].SortingArea (+ DeckCeiling, LightPanels, FitOut #2, GS25-model GroundBack/DockHeader walls)",
   "bounds": "min(-388.05,6.8,317.32) max(-341.0,18.0,364.57)",
   "enterable": true,
   "rooms": [
    {
     "name": "Sort floor (metal deck ceiling #787c80)",
     "center": [
      -364.52,
      12.4,
      340.95
     ],
     "size": [
      47.05,
      11.2,
      47.25
     ],
     "floorY": 6.8,
     "ceilingY": 18
    },
    {
     "name": "Conveyor line (x-361.1..-358.2 z327..355.1, belt top y9.6)",
     "center": [
      -359.63,
      8.2,
      341.04
     ],
     "size": [
      2.9,
      2.8,
      28.1
     ],
     "floorY": 6.8,
     "ceilingY": 18
    },
    {
     "name": "Pallet zone (4 pallets x 6 cartons, x-381..-370.3 z327.2..358.8)",
     "center": [
      -375.65,
      9.3,
      343
     ],
     "size": [
      10.7,
      5,
      31.6
     ],
     "floorY": 6.8,
     "ceilingY": 18
    },
    {
     "name": "Loading dock opening (shutter rolled up, to yard/pad)",
     "center": [
      -387.96,
      11.75,
      342.51
     ],
     "size": [
      1.1,
      9.9,
      12
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    }
   ],
   "props": [
    "SortingArea/ConveyorFrame 28x2.6x2.4 solid Metal box + ConveyorBelt 28x0.15x2 Rubber + ConveyorCarton x6 (1.8x1.15x1.3) static on the belt",
    "Pallet x4 4.4x0.5x4.4 WoodPlanks slabs + PalletCarton x24 2x1.45x3.8 blank Cardboard (3 high x 2)",
    "RollCage x2 3.2x5.6x2.6 DiamondPlate t0.5 translucent boxes + CageBoxes x2 (x-370 z321..328.5)",
    "DockStripe 12.8x0.2x7.2 yellow, DockBumper x2 Rubber 0.6x2.2, ShutterRoll 12x0.8x0.6 at y17.1, DockSign '상차장 · 택배 탑차'",
    "DeckCeiling 46.4x0.3x46.2 Metal; LightPanel 16x4 (SurfaceLight Range30 AlwaysOn) + two 40x0.8 strips; SmokeDetector x3; CCTV + mount (x-343.1 z319.7); ExitSign (x-365 z363.8); FireExtinguisher + Sign_소화기 (x-386 z363)",
    "Walls: Partition 55.2 long (south, z317.4), WallLining north, GroundBack walls (GS25 model) x-388.3 with DockHeader over the 12-stud opening"
   ],
   "gameplay": [
    "Station_dock (-383.96,7.30,342.58): delivery_parcel task 'load' prompt -> SpawnJobVehicle(player,'parcel_truck', pad CFrame) via ServerStorage.GwangalliEvents; 4 drops planned",
    "Walk route office -> LowWall opening (x-341, z333.4..347.4) -> dock station -> dock opening (z336.5..348.5) -> Station_pad (-404.46,7.1,342.2) must stay free of collidable props",
    "DetailLOD NearLOD (SortingArea/NearDetail extra ConveyorCarton x5); InteriorLight 16x4 panel"
   ],
   "emptyOrCrude": [
    "Conveyor is a static solid box: no rollers, side guides, legs, motor, scan arch or E-stop; cartons don't move",
    "Pallets are flat slabs (no deck boards/blocks); cartons and cage boxes are blank brown bricks; roll cages are 50 % transparent solid boxes instead of wire mesh cages",
    "47x47-stud hall is ~35 % used: empty floor x-358..-341 (between conveyor and low wall) and the north/south strips z318..327 / z355..364",
    "No racking, no region sort bays/cages numbered like the RouteMap (① 번화가 ② 민락 ③ 남천 ④ 광남로 ⑤ 해변로), no hand trucks/pallet jack, no PDA chargers, no wrap/tape station",
    "Dock opening is a plain hole: no shutter rails/curtain, dock leveler, seal or traffic light; floor has no pedestrian/forklift safety lines beyond the dock stripe",
    "Ceiling is a flat grey metal plate with three lights - no joists, ducts, high-bay fixtures or industrial fans"
   ],
   "realWorld": [
    "하차·분류 컨베이어 (롤러/벨트, 측면 가이드, 다리, 바코드 스캔 터널 또는 핸드 PDA, 비상정지 버튼, 분류 슈트)",
    "구역별 분류 칸 + 대형 롤테이너 다수 (구역 번호 행잉 사인), 팔레트 + 수동 파렛트 트럭 (핸드자키), 핸드카트 (대차)",
    "스트레치 필름·테이프건·송장 프린터·저울 작업대, PDA 충전 랙, 파손/반품/보관 구역 (반품 카트), 철제 랙",
    "상차 도크: 셔터 (레일·커튼·조작 스위치), 도크 레벨러, 도크 실/쉘터, 고무 범퍼, 도크 신호등, 휠 초크, 1톤 탑차 후진 가이드",
    "바닥 안전선 (노랑 보행 통로·적재 구역), LED 하이베이, 산업용 대형 선풍기/온풍기, 노출 덕트·트러스, 소화기·소화전, CCTV, 출퇴근기"
   ],
   "interactionIdeas": [
    "Conveyor switch: E = start/stop (belt texture scrolls, cartons slide to the end), E-stop button",
    "PDA scan: E on a carton = beep + show its 구역 number; then E on the matching region cage to sort (a delivery_parcel prep task before 'load')",
    "Pallet jack: E grab -> move a pallet to the dock; stretch-wrap a pallet (hold E, film spins)",
    "Shutter switch at the dock: E = roll the shutter curtain up/down (animate ShutterRoll); dock light turns green when the Porter is docked",
    "Weigh oversize parcel at the scale table and print a label"
   ]
  },
  {
   "name": "광안 딜리버리 차고 (outdoor parcel-truck pad)",
   "path": "Workspace.Gwangalli.delivery[\"광안 딜리버리 차고\"]",
   "bounds": "pad min(-411.62,6.59,333.07) max(-397.29,6.64,351.33) on YardAsphalt min(-426.41,6.56,257.31) max(-387.38,6.61,366.99)",
   "enterable": false,
   "rooms": [
    {
     "name": "Truck pad (yellow outline 14x18)",
     "center": [
      -404.46,
      6.62,
      342.2
     ],
     "size": [
      14.3,
      0.05,
      18.3
     ],
     "floorY": 6.6
    },
    {
     "name": "Rear yard (shared with GS25 back: parking lines x4, Kia Ray, Porter)",
     "center": [
      -406.9,
      6.6,
      312.15
     ],
     "size": [
      39,
      0.05,
      109.7
     ],
     "floorY": 6.6
    }
   ],
   "props": [
    "PadLine x4 yellow 0.4-wide lines, PadText 12x2 '택배 차량 전용' painted on the ground",
    "GarageSign 8x3x0.2 yellow '광안 딜리버리 차고 · 출구 →' floating at y9.5..12.5 (x-404.8 z362.7) with no post",
    "Car_Porter II (Hyundai Porter II truck model, VehicleKind truck) parked at x-418.5..-415 z349.4..365.2, outside the pad",
    "Neighbouring GS25 yard items: ParkingLine x4 (x-424..-408), Car_Kia Ray, Car_Porter II (GS25), RollCage x2 + Boxes x2 at GS25 back door, OutdoorAC x3"
   ],
   "gameplay": [
    "Station_pad (-404.46,7.10,342.20) tags GwJobStation + GwVehiclePad, Kind=parcel_truck: JobDelivery spawns/despawns the 탑차 here (SpawnJobVehicle / DespawnJobVehicle), final 'goto pad' return",
    "Station_exit (-403.00,7.10,264.21) at the south yard exit",
    "Pad must stay free of collidable props (vehicle spawn), and the lane dock(x-388)->pad->exit(z264) must stay drivable"
   ],
   "emptyOrCrude": [
    "Called 차고 but there is no garage/canopy: just painted lines on asphalt",
    "Sign floats in the air without a post or wall",
    "No wheel stops, cones, lighting pole, CCTV, gate/barrier at the exit, wash area, air pump or EV/battery charging"
   ],
   "realWorld": [
    "택배 차량 주차장: 철골 캐노피 지붕, 차량 번호별 주차칸, 카 스토퍼, 라바콘, 조명 기둥, CCTV, 출입 차단기",
    "세차 호스·수전, 타이어 공기주입기, 1톤 전기 포터 충전기, 오토바이 주차 라인 + 배터리 교환 스테이션"
   ],
   "interactionIdeas": [
    "Air pump / wash hose: E = 세차 (truck shine) or tyre check mini-task before a parcel route",
    "EV charger for an electric Porter / battery swap cabinet for e-scooters (E = swap, battery % in HUD)",
    "Place cones (E) around the truck while loading"
   ]
  }
 ],
 "notes": "Full JSON written to /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/cvs_delivery.json (generator script /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/cvsdl/write_json.py). Scale: the anchored 배차 실장 rig is ~5.3 studs tall (feet 6.8, head top ~12.2), so about 0.32 m/stud. GS25 ceiling is 11 studs (~3.5 m), counter top 3.6 studs, gondola 6.6 studs, fridge door 6.2 studs. Layout: one 3-storey shell '광안로 상가 (GS25)' (x -388.9..-306.7, z 260.5..366.0) holds GS25 (south, z 261.8..307.2), a sealed lobby+stair (x -331.2..-309.4, z 307.6..318.0) and 광안 딜리버리 (north, z 317.3..365.2). Facades face +X (street at x≈-300). An enclosed, unused void with no floor sits at x -388..-332, z 308..316.5, between the GS25 north Partition (z305.7..308) and the delivery Partition (z316.5..318.4). It is a natural place for the delivery restroom (its door already sits at x-331.6 z318.6) and for the lobby stair's return flight. The exterior walls GroundSide/GroundBack/DockHeader belong to the GS25 model even where they enclose the delivery warehouse. 2F/3F are one solid Core block. Annex skips everything under 'convenience' and 'delivery' (HOST_VENUES). ShopLife picks up GS25 as a 'venue' candidate but not the delivery office. So any interior on the upper floors or in the delivery office has to come from the new interior system. Implementation constraints found: (1) JobWorld snaps its runtime anchors to DIRECT children of the GS25 model named StaffMicrowave, HotWaterMachine, CashDrawer and CardTerminalScreen. (2) GwangalliStaff builds its NPC walk graph once, from server raycasts against CanCollide parts, so new collidable geometry should stay client-side or out of the aisles. (3) JobCvsPlus places server-side product displays (workspace.GwCvsPlus) at the 4 slot anchors, so the SlotBack/SlotBoard volumes must stay free. (4) DetailLOD hides NearLOD/ZoneLOD models with LocalTransparencyModifier. Hiding the crude originals therefore needs another channel (local Transparency/CanQuery writes, restored on exit) or must be re-applied after DetailLOD runs. (5) ShopLife's name lookups miss 'HotWater' (the part is HotWaterMachine) and 'IceCreamChest' (the part is IceCreamFreezer) in this store; alias parts or attributes would light up those prompts. (6) All Station_* anchors, Destination, the AutoDoor_* models, the POS tags (GwPosScreen/Customer/Scanner/Printer) and the ATM part must keep their names and positions. Dumps for follow-up are in /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/cvsdl/: conv.txt, deliv.txt, conv_c.txt, deliv_c.txt, propsumm.json and allaabb.json (world AABBs of all 256,801 parts). Scripts read: JobWorld, JobCvs, JobCvsPlus, JobDelivery, JobShop, GwangalliStaff, ShopLife/Scan, ShopFlows, Bank, Law/Crimes, StreetInteract/Places, Annex, DetailLOD, GwangalliJobs/World, CvsWorld, GwangalliWorkSpots and GwangalliCustomerShared. Because addons has no ShopLife/Scan, it was read from bld/eff."
}
```

## survey:pcbang_karaoke

```json
{
 "venues": [
  {
   "name": "광안 PC방 (광안타워 1F, 48석 + 흡연실)",
   "path": "Workspace.Gwangalli.pcbang['광안 PC방']",
   "bounds": "(89.1,6.85,268.1)..(148.1,17.95,365.6)",
   "enterable": true,
   "rooms": [
    {
     "name": "Front zone: entrance + counter + kiosk + self bar (open to hall)",
     "center": [
      118.6,
      12.4,
      279.3
     ],
     "size": [
      59,
      11.1,
      22.4
     ],
     "floorY": 6.85,
     "ceilingY": 17.95
    },
    {
     "name": "Counter staff aisle (behind CounterBody; fridge/snack shelf/ramen cooker)",
     "center": [
      92.7,
      12.4,
      278.9
     ],
     "size": [
      7.2,
      11.1,
      18.1
     ],
     "floorY": 6.85,
     "ceilingY": 17.95
    },
    {
     "name": "흡연실 glass room (front-right corner)",
     "center": [
      138.4,
      11.6,
      282.4
     ],
     "size": [
      19.2,
      9.6,
      12
     ],
     "floorY": 6.83,
     "ceilingY": 16.4
    },
    {
     "name": "PC hall (6 back-to-back desk rows A-F, 48 PCStation)",
     "center": [
      118.6,
      12.4,
      318
     ],
     "size": [
      59,
      11.1,
      55
     ],
     "floorY": 6.85,
     "ceilingY": 17.95
    },
    {
     "name": "Hall back strip (fake restroom doors, exit, printer) - mostly empty",
     "center": [
      118.6,
      12.4,
      355.3
     ],
     "size": [
      59,
      11.1,
      20.6
     ],
     "floorY": 6.85,
     "ceilingY": 17.95
    }
   ],
   "props": [
    "PC_01..PC_48 Models (tag PCStation) x48, 23 parts each (1104 parts): MonitorBezel 2.9x1.7x0.15 box + MonitorScreen 2.7x1.5 Neon (SurfaceGui '광안 PC방 / 좌석 NN · 로그인 해주세요'), MonitorNeck 0.36x0.7 box, MonitorFoot 1.6x0.08x0.75, DeskMat 3.4x1.3, Keyboard 1.5x0.12x0.5 box + KeyboardRGB neon slab, Mouse 0.25x0.12x0.4 box, Headset (HeadsetBand + 2 cylinder HeadsetCup) floating 1.3 studs above the desk and clipping the monitor's left edge (no hook), Webcam box, SeatTag, CupHolder 0.45 box, PCTower 0.8x1.9x1.6 box + TowerRGB strip, Seat (Seat 2x0.4x2, top y 8.75), ChairBack 2x3.6x0.4 box, ChairAccent strip, 2 Armrest bars, GasLift cylinder, ChairBase flat 2.1 disc. Quality: readable but all-box; identical seats; seat pitch 4.8 studs",
    "Desk furniture (PCHall root): DeskTop 19.2x0.2x2.6 x12 (top y 9.7, 6 back-to-back pairs at z~300/303, 319/322, 337/340 in two blocks x 97.6..116.8 and 124.8..144.0), DeskEdgeLED x12, DeskSide x24, Divider 19.2x5.5x0.3 x6 + DividerRGB x6, RowTag x6 (A열..F열)",
    "Hall ceiling/services: HallCeilingExposed 59.2x75.2 black slab, CeilingLED neon lines x6 (3 across, 3 along), SpiralDuct cylinder 62 long only along x=94, Diffuser x3, LightHolder x4 (PointLight r24, InteriorLight), CCTV ball x3 + mounts, CassetteAC + ACGrille",
    "Hall walls: WallPanel east (0.15x11.2x97.6) + back (59.2 wide) flat dark (36,38,44), WallAccentLED vertical neon x5, BaseLED floor strips x2, Partition west flat dark; signs: Sign_좌석에서 주문, Sign_금연, Sign_청소년 출입 안내, Sign_신규회원 1시간 무료 (4x5.4 boards); LEDScreen 9x4.2 '광안리 PC방 리그' (tag LEDScreen); Board_pc (BoardFrame + BoardFace VenueBoard 'pc', 5 rows)",
    "Back strip: RestroomDoor x2 (4x8, on the building's rear wall - no restroom behind), Sign_남 MEN / 여 WOMEN / 화장실, ExitDoor + ExitSign + PanicBar + FireExtinguisher, PrinterTable 4x3.2x2.85 + Printer box + Sign_프린트 1장 100원; HallCarpetTiles 59.2x75.2 single slab",
    "Front: AutoDoor_PC방 (2 sliding glass leaves, tag AutoDoor), EntranceMat, Threshold; CounterBody 3.5x3.5x13 box + CounterTop 4x0.3x13.4 + CounterLED + CounterFrontSign 'COUNTER · 충전 · 음식 주문'; POSMonitor (static '좌석 현황 32/48'), POSStand, CardTerminal, ReceiptPrinter, CallBell (all small boxes); StaffSeat stool; LEDScreen 11x2.6 price ticker over counter; menu strip sign '컵라면 3,500 · 짜파게티 4,000 · 핫도그 2,500 · 탄산음료 1,500'",
    "Behind counter: Fridge (3-door reach-in 7x8x3.6, FridgeDoor glass slab, 4 WireShelf, 40 Bottle cylinders 0.27 dia x 0.8 tall in flat colours, FridgeGlow/FridgeLamp), SnackShelf (BackPanel 7x7, 4 Board, 4 PriceRail, 38 Product flat-colour boxes, no labels), Sign_음료 1,500원~ / Sign_과자 · 컵라면, BackCabinet 7.3x3.4x1.2, RamenCooker 2.4x2x1 box + red CookerDisplay, HotWater 1.8x2.8 box + tap, RamenStock x3 boxes + RamenPot cylinder",
    "Kiosk (KioskBase + KioskPedestal + KioskHead 2.6x3.4x0.7 with '무인 요금 충전' text + KioskCardSlot) at (104.3,·,275.6)",
    "Self bar at east front corner: SelfBarCabinet 2.85x3.4x4.5 + WaterPurifier 2x3x1.6 box + IceDispenser 1.7x2.2 box + Sign_셀프바 · 물 · 얼음; RecycleCabinet green box '분리수거 · 컵라면 국물'",
    "흡연실 model (45 parts): SmokingRoomGlass x10 + Mullion/HeadRail/SillRail frame, SmokingRoomDoor glass 3.6 wide (CanCollide false, static), SmokingRoomBulkhead 19.25x1.6x12.4, SmokingRoomFloor, AshtrayStand cylinder x2 + AshtrayTop, ExhaustFan + grille, AirPurifier 1.25x3x3 box, Sign_흡연실 SMOKING ROOM, Sign_전자담배도 흡연실에서, LightPanel + PointLight",
    "Front ceiling: FrontCeiling model (CeilingBoard 59.2x22.5 dark + 17 TBar), LightPanel x4 (SurfaceLight, InteriorLight)",
    "Staff: 알바생 지훈 (VenueStaff rig, 21 parts, Act typing, apron) at HomeCF (94.4,9.8,278.9); Spot_pc_counter invisible 2.3x5.5x10 VenueSpot at (101.1,9.6,280.2)",
    "Outside (not interior): Destination part (108.7,7.1,264.1), StandingSign, Car_Sonata (127.6,·,390.5) and Car_Tucson (103.6,·,390.7) parked in the rear yard"
   ],
   "gameplay": [
    "VenuePC (ServerScriptService.GwangalliGameplay.VenuePC): watches tag PCStation; needs attr PCNo + child Seat (class Seat) + Keyboard (or MonitorScreen); sets Keyboard.CanQuery=true and adds ProximityPrompt 'GwangalliPCPrompt' 'PC 켜기' (ObjectText 'PC NN · 1시간 1,000원', MaxDistance 7, key E); charges V.PC.feePerHour=1000 per in-game hour and auto-extends, Seat:Sit (seat Disabled while free), writes model attr PCUser (UserId/0), fires VenueEvent pcStart/pcEnd/pcRank, racer leaderboard on VenueBoard 'pc' (Board_pc/BoardFace Row1..5 '광안대교 나이트 레이서 랭킹')",
    "CLIENT GAP: StarterPlayerScripts.GwangalliVenues/PC is an 18-line placeholder addon (its comment wrongly says the PCStations are not built in this place). pcStart has no client handler: no camera on the monitor, no racer game, the screen keeps '로그인 해주세요' after paying. A real PC client (desktop UI, game, in-seat order) is the biggest interaction hole",
    "VenueLife: VenueSpot Spot_pc_counter (Spot='pc_counter', Label, PickupCF (99.2,10.6,286.1) on the counter top) -> prompt '음식 주문' -> 'menu' event handled by client GwangalliVenues/Spots (menu pcbang: ramen 3500, jjapa 4000, hotdog 2500, pc_soda 1500, prep 6-20 s). Seated players get the food at RamenCF on their desk (≈1.4 studs right of the monitor, desk front edge) carried by the clerk; others at PickupCF; food prop prompt '먹기'/'마시기'",
    "Clerk delivery (VenueLife.clerkDeliver): VenueStaff 'pc_clerk' 알바생 지훈 walks HomeCF -> Way1 (94.2,6.8,271.1) -> Way2 (108.8,6.8,271.2) -> Way3 (120.7,6.8,292.0) -> PC AislePos -> PC ServePos and back (TweenService on HumanoidRootPart, no pathfinding). BUG: every AislePos is mirrored about z≈266.5 (PC_01 AislePos (120.4,6.8,237.7) vs ServePos z 295.2; rows use z 237.7/224.8/219.2/206.3/200.7/187.8) so the clerk tweens out through the front glass 30-80 studs into the street and back. The correct value is ≈(120.8, 6.8, ServePos.Z)",
    "ShopStaff (GwangalliGameplay.ShopStaff): the venue Model '광안 PC방' has a ShopFloor child (that is the side shop 광안 분식) so its anchor is the 분식 'Counter' part (63.5,8.4,276.4); kindOf('광안 PC방') = 'game' -> a hoodie 알바생 (typing/phone) stands in the 분식 instead of a 분식 cook. Nothing staffs the PC counter except the VenueStaff rig (skips within 9 studs)",
    "GwangalliWorld/Screens: LEDScreen tag x2 (counter price ticker, hall league screen) cycle attr Messages; GwangalliWorld/Lights: 8 InteriorLight (LightPanel SurfaceLights, LightHolder PointLights, 흡연실 PointLight) under the global interior budget (nearest 24/16/6 by tier); GwangalliIndoorLight dims lights under a roof x0.55",
    "DetailLOD: ZoneLOD models PCHall (LODCenter (118.7,12.4,314), radius 110), Fridge and SnackShelf (radius 66), 흡연실 (radius 74); 20 NearLOD models (NearDetail/Detail/ShopDetail) hidden until near (GwArrive pass)",
    "GwangalliDoors + client: AutoDoor_PC방 leaves with OpenOffset; StreetInteract/Places opens it for NPCs with AutoDoorOpener proxies",
    "NPC/world references: GwangalliCitizens place 'pcbang' (dest '광안 PC방', r 70, indoor, lane backlane; thugs 13 h, students 20-22 h, errand 'PC방 충전 카드'), GwangalliNav node 3095 (108.7,6.6,264.1), Taxi landmark, ProgressShared FUN_WORDS",
    "Separate system NOT wired here: GwangalliBuildings ShopFlows 'pcbang' (이용권 + GameViews 30 s reaction game) runs only in the procedural 광안 프라자 2F at the demo district (≈4283,·,-200); can be reused as the monitor game",
    "Must not block/rename/move: PC_NN models and attrs PCNo/AislePos/ServePos/RamenCF, Seat, Keyboard, MonitorScreen (SurfaceGui face), the RamenCF desk spot and the ServePos aisle behind each chair (z 295.2/308.2/313.7/326.7/332.2/345.2), central aisle x 116.9..124.8, Way1..3 path, Spot_pc_counter + PickupCF, Board_pc BoardFace, both LEDScreens, VenueStaff rig + HomeCF, counter staff aisle x 92.6..96.3, AutoDoor leaves + slide pocket (leaves 4 wide slide ±3.75 -> keep x ≈99..118.6 within 0.6 of z 268 clear), Destination"
   ],
   "emptyOrCrude": [
    "Back third of the hall (z 345..365.6, 59x20 studs) is bare carpet: only a printer table at x 95; the two restroom doors are fake (the back wall z 365.7 is the building's rear), no lounge, lockers, charging or vending",
    "All 48 seats identical, while the facade promises '커플석' and '240Hz 게이밍 모니터': no couple seats, no premium/FPS zone, no team room, no zone signage",
    "PC station is boxes: flat box monitor (no curve, thin bezel or VESA stand), slab keyboard with a neon top, box mouse, box tower with one RGB strip, headset floats 1.3 studs over the desk and clips the monitor's left edge, no cables, sockets, USB hub or call button",
    "Gaming chair: box seat + box back + flat disc base; no 5-star wheelbase, headrest or lumbar pillow, wings or stitching",
    "Walls are flat dark slabs with 5 vertical LED bars; no esports posters, game key art, branded wall graphics, mirror or clock; a single spiral duct along the west wall only",
    "Counter is a 3.5x3.5x13 box; there is no real kitchen (no fryer, microwave, induction, sink, order-ready screen, menu photos, tray rack or serving robot); food is a box RamenCooker and box HotWater",
    "Fridge bottles are 40 uniform single-colour cylinders without caps or labels; the snack shelf is 38 flat-colour boxes; both sit behind the counter so customers cannot browse them",
    "The kiosk is a box head with text; the self bar is three boxes (no cups, straws, napkins, wet tissue or sauces); the smoking room has only 2 cylinder ashtrays",
    "POSMonitor text is static ('좌석 현황 32/48') and monitors stay on '로그인 해주세요' even for paying players (no client)",
    "Lighting relies on 4 hall PointLights + neon; no per-seat desk glow, no screen light spill on faces"
   ],
   "realWorld": [
    "Entrance: auto door, 24시/연중무휴 decal, age notice (청소년 22시 이후 출입 제한), price board, membership/ID check notice, umbrella stand, floor mat",
    "Self-service kiosk(s) (회원가입/로그인/충전, card + cash + QR), counter with POS, card terminal, receipt printer, call bell, seat-map monitor showing used/free seats",
    "Open kitchen behind the counter: ramen cooker (자동 라면 조리기), hot water dispenser, fryer, microwave, induction, rice cooker, sink, order screen, photo menu board (라면, 짜파게티, 볶음밥, 떡볶이, 핫도그, 감자튀김, 치즈스틱, 에이드)",
    "Beverage fridges and a snack/cup-noodle wall, often customer-accessible next to the counter, with price tags",
    "Self bar: water purifier, ice maker, paper cups, straws, napkins, wet tissue, chopsticks, sauces, trash and liquid-waste sink (국물 버리는 곳)",
    "Seat zones: 일반석, 커플석 (wide 2-seat desk/sofa), 프리미엄/FPS석 (high-Hz monitors, brand gear), 팀룸 (3-5 seats), sometimes 흡연석 booths",
    "Station: 24-27\" 165-360 Hz monitor (often curved), mechanical RGB keyboard, gaming mouse on a large desk mat, headset on a hook, webcam, cup holder, power + USB charging, seat number tag, call button, side dividers, ergonomic gaming chair with headrest/lumbar pillows",
    "Exposed black ceiling with ducts, cable trays, track/line LED, RGB accents; carpet tiles; acoustic treatment; CCTV; cassette AC; air purifiers",
    "Wall TV/LED showing esports (LCK) or tournament promos, game posters, ranking board",
    "Glass smoking room with ventilation fan, ashtray tables/standing ledges, air purifier, door closer; vape notice",
    "Restrooms, printer/scanner corner, fire extinguisher and exit, lost-and-found and phone chargers at the counter; serving robot or staff delivering food to seats"
   ],
   "interactionIdeas": [
    "PC 켜기 (exists, server) -> client: camera to monitor, login screen with seat no. and time left, launcher (광안대교 나이트 레이서 / GameViews reaction game), '음식 주문' button on the monitor (sign promises 모니터 하단 메뉴 → 음식 주문), '자리 비움', '종료'",
    "Kiosk '요금 충전' (1h/3h/10h/야간 정액) and '회원가입 (1시간 무료)'; counter '충전 카드 구매' for the Citizens errand",
    "Desk '직원 호출' bell -> clerk walks to ServePos; '헤드셋 쓰기' while seated (weld headset to head); '의자 높이 조절'",
    "Fridge '음료 꺼내기' and snack shelf '과자 고르기' (move both to a customer-accessible spot or let the clerk hand them over)",
    "Self bar '물 받기', '얼음 담기' (cup prop -> drink act); recycle cabinet '컵라면 국물 버리기' after eating",
    "Printer '인쇄하기 (100원)' -> printed sheet prop",
    "Smoking room glass door '문 열기' (slide), air purifier '공기청정기 켜기'",
    "League LED / counter '리그 참가 신청' -> joins the racer ranking event",
    "Restroom door '화장실' fade, as ShopLife does",
    "Live seat-map monitor fed by PCUser attributes; monitor screens switch to the game when PCUser ~= 0"
   ]
  },
  {
   "name": "광안타워 1F 엘리베이터 로비 + 2F-5F (스터디카페 · 연합의원 · 태권도 · 수학학원)",
   "path": "Workspace.Gwangalli.pcbang['광안 PC방'] (Lobby* parts) + Workspace.Gwangalli.pcbang['광안타워 (PC방)']",
   "bounds": "lobby (78.8,6.85,268.2)..(88.3,17.95,290.0); upper floors solid Core (58.0,20.5,268.0)..(148.2,64.5,366.0)",
   "enterable": false,
   "rooms": [
    {
     "name": "1F lobby (glass Door CanCollide default true; no AutoDoor tag; Annex skips host venue 'pcbang')",
     "center": [
      83.55,
      12.4,
      279.1
     ],
     "size": [
      9.5,
      11.1,
      21.8
     ],
     "floorY": 6.85,
     "ceilingY": 17.95
    },
    {
     "name": "2F-5F floors (Core block 90.2x44x98.1, no interior)",
     "center": [
      103.1,
      42.5,
      317
     ],
     "size": [
      90.2,
      44,
      98.1
     ],
     "floorY": 20.9,
     "ceilingY": 64.5
    }
   ],
   "props": [
    "Door 6x8.3 glass slab + Transom + DoorHandle; ShopWindow 1.6 wide x2 + mullions",
    "LobbyFloor 9.2x21.6, LobbyCeiling 9.2x21.6, LobbyLight neon panel 7.2x2, Partition walls x2 (plaster)",
    "ElevatorDoor 4.8x8.5 metal slab + ElevatorSeam + Sign_▲ 1F ▼ (fake; no call button, car or indicator)",
    "Directory sign on facade 'Sign_5F 수학학원 4F 태권도 3F 연합의원 2F 스터디카페 1F PC방'; Fascia + Sign_광안타워 '2F-5F · 엘리베이터'",
    "Upper floors: 48 Window parts (tag NightWindow, Zone office, LitChance 0.42), Spandrel/SillFlash x4, floor signs Sign_스터디카페 온 / 광안 연합의원 / 해오름 태권도 / 수학의 정석 전문학원, vertical Sign_PC방 and Sign_태권도, roof Penthouse/WaterTank/AC/SolarPanel"
   ],
   "gameplay": [
    "None: no prompts, no tags inside the lobby; Annex HOST_VENUES skips anything under 'pcbang', so no '들어가기' annex door either",
    "ShopStaff/ShopLife ignore it (no ShopFloor/Interior in the lobby)",
    "NightWindow lighting (GwangalliWorld) on the 48 upper windows"
   ],
   "emptyOrCrude": [
    "Lobby is a sealed 9.5x21.8 box behind a solid glass door: fake elevator, no mailboxes, call button, floor indicator, directory board, CCTV or fire box",
    "Upper floors are one solid dark Core block behind lit windows; the 4 tenants exist only as signs"
   ],
   "realWorld": [
    "Korean 근린생활시설 lobby: glass door with door closer/keypad, wall directory (층별 안내), mailboxes, elevator with call button + floor display + inspection certificate, fire hydrant box, CCTV, stair door (비상계단), notice board",
    "2F 스터디카페 (kiosk, lockers, single desks with lamps), 3F 의원 (reception, waiting chairs, exam room), 4F 태권도장 (mats, mirrors, belt rack), 5F 학원 (classrooms, whiteboards)"
   ],
   "interactionIdeas": [
    "Make the door an AutoDoor/swing door and add '엘리베이터 호출' -> ride with a fade to an annex floor (Annex already supports building archetypes)",
    "'층별 안내' directory prompt listing tenants; '우편함 확인'"
   ]
  },
  {
   "name": "광안 분식 (광안타워 1F 옆 가게)",
   "path": "Workspace.Gwangalli.pcbang['광안 PC방'] (ShopFloor/ShopBackWall/ShopLight/Counter/Sign_광안 분식 at x 57.8..76.8)",
   "bounds": "(57.8,6.85,268.5)..(76.8,16.0,278.4)",
   "enterable": false,
   "rooms": [
    {
     "name": "Shop room 19x9.9 (glass Door collides; not ShopLife: model has ShopFloor but no Interior child)",
     "center": [
      67.3,
      11.4,
      273.45
     ],
     "size": [
      19,
      9.15,
      9.9
     ],
     "floorY": 6.85,
     "ceilingY": 16
    }
   ],
   "props": [
    "ShopFloor 19.08x0.3x10.2, ShopBackWall 19.08x9.7 cream slab, ShopLight 17x8.5 slab as ceiling (tag NightNeon), Counter 5.72x3.3x2 orange box",
    "Door 4.8x7 glass + Handle + ShopDetail/DoorFrame, ShopWindow x3, ShutterBox, Fascia + Sign_광안 분식 '떡볶이 · 김밥 · 순대 · 튀김'"
   ],
   "gameplay": [
    "ShopStaff spawns an 알바생 (kind 'game' from the parent model name '광안 PC방') behind this Counter - wrong persona for a 분식집",
    "Not a ShopLife walk-in shop (needs a child 'Interior'); Annex skips it (host venue); no ordering"
   ],
   "emptyOrCrude": [
    "Only a box counter in an empty room: no 떡볶이 pan, 어묵 steamer, fryer, 김밥 station, menu board, tables or stools",
    "Space behind the back wall (x 57.8..78.4, z 278.9..366) is an unreachable void"
   ],
   "realWorld": [
    "즉석 떡볶이 철판 + 어묵 국물통, 튀김기 + 튀김 진열대, 김밥 말이대, 순대 찜기, 메뉴판 with prices, 2-4 small tables with stools, water purifier, 포장 용기, 카드 단말기"
   ],
   "interactionIdeas": [
    "Make it a ShopLife 'snack' counter shop (StreetShops type snack, flow counter) by adding an Interior child or ShopLifeType attr on a wrapper; '떡볶이 주문', '어묵 국물 떠먹기'"
   ]
  },
  {
   "name": "광안 코인노래연습장 (광안빌딩 1F, 8 rooms)",
   "path": "Workspace.Gwangalli.karaoke['광안 코인노래연습장']",
   "bounds": "(-6.6,6.85,268.5)..(41.0,17.95,358.0)",
   "enterable": true,
   "rooms": [
    {
     "name": "Lobby (coin changer, vending, counter, waiting sofa, TOP100 LED)",
     "center": [
      17.2,
      12.4,
      280.65
     ],
     "size": [
      47.6,
      11.1,
      24.3
     ],
     "floorY": 6.85,
     "ceilingY": 17.95
    },
    {
     "name": "Counter staff zone (behind Counter, StaffCabinet, mic sterilizer)",
     "center": [
      33.2,
      12.4,
      289.15
     ],
     "size": [
      15.6,
      11.1,
      7.3
     ],
     "floorY": 6.85,
     "ceilingY": 17.95
    },
    {
     "name": "Corridor 'ROOM 01 ~ 08' (12 wide, neon)",
     "center": [
      17.3,
      12.4,
      317
     ],
     "size": [
      12,
      11.1,
      48
     ],
     "floorY": 6.85,
     "ceilingY": 17.95
    },
    {
     "name": "Booth_01 (east)",
     "center": [
      32.35,
      12.4,
      299
     ],
     "size": [
      17.3,
      11.1,
      11.6
     ],
     "floorY": 6.83,
     "ceilingY": 17.95
    },
    {
     "name": "Booth_02 (east)",
     "center": [
      32.35,
      12.4,
      311
     ],
     "size": [
      17.3,
      11.1,
      11.6
     ],
     "floorY": 6.83,
     "ceilingY": 17.95
    },
    {
     "name": "Booth_03 (east)",
     "center": [
      32.35,
      12.4,
      323
     ],
     "size": [
      17.3,
      11.1,
      11.6
     ],
     "floorY": 6.83,
     "ceilingY": 17.95
    },
    {
     "name": "Booth_04 (east)",
     "center": [
      32.35,
      12.4,
      335
     ],
     "size": [
      17.3,
      11.1,
      11.6
     ],
     "floorY": 6.83,
     "ceilingY": 17.95
    },
    {
     "name": "Booth_05 (west, mirrored)",
     "center": [
      2.17,
      12.4,
      299
     ],
     "size": [
      17.45,
      11.1,
      11.6
     ],
     "floorY": 6.83,
     "ceilingY": 17.95
    },
    {
     "name": "Booth_06 (west)",
     "center": [
      2.17,
      12.4,
      311
     ],
     "size": [
      17.45,
      11.1,
      11.6
     ],
     "floorY": 6.83,
     "ceilingY": 17.95
    },
    {
     "name": "Booth_07 (west)",
     "center": [
      2.17,
      12.4,
      323
     ],
     "size": [
      17.45,
      11.1,
      11.6
     ],
     "floorY": 6.83,
     "ceilingY": 17.95
    },
    {
     "name": "Booth_08 (west)",
     "center": [
      2.17,
      12.4,
      335
     ],
     "size": [
      17.45,
      11.1,
      11.6
     ],
     "floorY": 6.83,
     "ceilingY": 17.95
    },
    {
     "name": "Back zone (fake restroom doors, exit, water purifier) - mostly empty",
     "center": [
      17.2,
      12.4,
      349.6
     ],
     "size": [
      47.6,
      11.1,
      16.8
     ],
     "floorY": 6.85,
     "ceilingY": 17.95
    }
   ],
   "props": [
    "Booth_01..08 Models (tags KaraokeRoom + ZoneLOD, attrs RoomNo/RoomName, LODCenter, LODRadius 73), 83 parts each (664). TV wall (far end): TVBezel 9.2x5.4 box + KaraokeScreen 8.84x5.04 (SurfaceGui 'ROOM NN / 문 옆 패널에서 방을 잡고 노래를 골라요', GuiFace Back) + TVUnderglow neon; MachineCabinet 6x2.5x2.16 + CabinetTop + seam; KaraokeMachine 3.4x0.8x1.6 box + MachineDisplay '38131' + 4 MachineLED; MicDock; 2 FloorSpeaker 0.9x5.6x1.4 boxes (2 Woofer + 1 Tweeter discs each), Subwoofer box + cone, 2 ceiling Speaker boxes + cone; MicStand (MicBase disc, MicPole, Mic cylinder, MicHead ball)",
    "Booth seating: SofaBack (1 Seat, against the corridor wall), SofaLeft (3 Seats), SofaRight (2 Seats) = 6 Sittable Seats per booth, burgundy (130,26,30) box Base/Backrest/Arm/BackCushion + Plinth; table: TableBase + TableGlow neon + glass TableTop 3.2x6 (top y 8.51); on the table: 2 WirelessMic (cylinder + ball head), Tambourine (attr GwKaraoke 'tambourine') + 4 Jingle discs, SongBook + label, Remote + neon keys, MenuStand wedge, 2 Cup cylinders, TissueBox",
    "Booth shell: Carpet 11.6x17.3 navy, AccentWall (fabric) behind the TV, 2 AcousticPanel 9x15.3 flat fabric on the side walls, 6 AcousticTile 1.1 squares, KaraokeZone invisible 17.3x11.2x11.6 box, MirrorBall 1.5 ball (attr GwKaraoke 'ball') + rod, LaserProjector box + neon lens, 3 LedStrip neon at the ceiling edge, Sign_이달의 신곡 poster; BoothDoor glass 4.7 wide modelled permanently open (swung flat against the partition) + DoorEdge + DoorHandle",
    "Corridor face of each booth: Sign_NN, 3 DoorNeon frame, StatusLight (green/red), KaraokePanel 1.1x2 (SurfaceGui 'NN / 빈 방 · 터치') + PanelGlow",
    "Corridor: CorridorWall x10 + CorridorWallLintel x8, BoothPartition x10 (17.3x11.2x0.4 plaster), CorridorRunner carpet 9x47.8, CorridorNeon x5 (PointLights), FloorNeon x2, BoothLightHolder x4 (PointLight r16), ArchLintel + Sign_ROOM 01 ~ 08 + ArchNeon x2",
    "Lobby west: CoinChanger 3x6.6x2.6 blue box + ChangerDisplay '500원 교환' + BillSlot + CoinTray + signs; VendingMachine 3.4x6.2x2.6 red box + Display + 15 Can slabs 0.4x0.8x0.2; Sign_1곡 500원 · 4곡 1,000원 price board 8x4.2 ('무인 운영 · 24시간 · CCTV 녹화중'); FireExtinguisher",
    "Lobby east: Counter model (ToeKick/Body 10x3.15x2.1/Top/LedStrip) + CardReader + Sign_카운터 · 마이크 커버 무료 + CCTVMonitor 'CH1 복도 · CH2 로비', StaffCabinet 2x6.5x6.2, MicCoverBox slab, Booth_Lobby MicSterilizer 1.1x2.2x2.2 + UV neon, CatalogPost + CatalogBook (노래 책), Board_karaoke (VenueBoard 'karaoke' '👑 오늘의 노래왕'), LEDScreen 6.4x3.6 'TOP 100 인기차트'",
    "Lobby front: WaitingSofa (4 Seats, black boxes) against the glass, EntranceMat, AutoDoor_노래연습장 (2 leaves), lobby MirrorBall 2.2, CassetteAC + grille, LightPanel x2 pink (PointLight), LobbyCeiling model (CeilingBoard 47.7x24.5 + 15 TBar), Sign_SING SING neon, Sign_이용 안내, Sign_신곡 입고, CCTV",
    "Back zone: BackFloorTiles 47.55x17.05, RestroomDoor x2 + DoorKnob (on the rear wall, nothing behind), Sign_남/여/화장실 · TOILET (PointLight), ExitDoor + PanicBar + ExitSign, WaterPurifier 2.4x4.6x2.45 + CupDispenser + WaterTap + Sign_정수기, FireExtinguisher, CCTV",
    "Shell: Floor 47.7x89.7 single dark purple slab, Ceiling 47.7x65.2 dark, WallLining slabs (the east lobby wall is fabric), Partition west (x=-7.0)",
    "Outside (not interior): Destination (5.5,7.1,264.5), StandingSign, neon 노래연습장/24H signs, RecycleBins model behind the building, Car_Kia Ray (9.9,·,389.0), Car_Scooter"
   ],
   "gameplay": [
    "VenueKaraoke (ServerScriptService.GwangalliGameplay.VenueKaraoke): tag KaraokeRoom; finds KaraokeZone and KaraokePanel by name (FindFirstChild recursive); KaraokePanel gets ProximityPrompt '방 잡기' (dist 8, E); rent V.KARAOKE.fee=500 per 30 in-game minutes, auto-extended while anyone is inside, released after 20 s empty; room attributes KRenter/KRenterName/KPaidUntil/KSong/KStart/KSerial/KResultName/KResultScore/KResultSerial; ops kSong/kStop/kScore/kLeave; daily 행복 rewards, 90+ 인기도; lobby board '오늘의 노래왕' (VenueBoard 'karaoke')",
    "Client GwangalliVenues/Karaoke: paints StatusLight (green 60,255,120 / red 255,60,60) and the KaraokePanel SignGui 'Sub' label ('빈 방 · 터치' / '이용 중 · name'); inside test = KaraokeZone local box +0.5 (X/Z) and +3 (Y); builds SurfaceGui 'KaraokeTV' on KaraokeScreen (disables its SignGui): countdown, lyrics wipe, pitch lane, score fanfare, confetti; action bar 노래 선택/탬버린/나가기; rhythm taps (Space/F); chiptune; spins MirrorBall + one local PointLight while singing",
    "VenueLife emote 'tambourine' welds a NEW tambourine prop to the hands (the table Tambourine stays put); GwKaraoke attributes on Tambourine/MirrorBall are read by no script",
    "Other systems: Arcade board 'karaoke' (source karaoke, 노래방 최고 점수), Progress quest 'karaoke_song' (1-3 songs), Journey 'karaoke' (find radius 30), Social invite '코노 가자' dest, Citizens place 'karaoke' (r 70, indoor, students/DJ fans), GwangalliNav node 3094 (5.5,6.6,264.5), Taxi landmark '코인노래방이요, PC방 옆'",
    "ShopStaff: the venue Model has a ShopFloor child (the side shop 광안 마라탕) so its only anchor is the 마라탕 'Counter' part (-37.8,8.4,276.5) -> an 알바생 (kind 'game' from '코인/노래') stands in the 마라탕; the karaoke Counter (a Model, not a BasePart) gets nobody. The sign says 무인 운영 so an empty counter is plausible, but the 마라탕 persona is wrong",
    "Lights/LOD: 8 InteriorLight PointLights (LightPanel x2, CorridorNeon, BoothLightHolder x4, toilet sign) under the interior budget; DetailLOD hides each Booth_NN beyond 73 studs of its LODCenter and Booth_Lobby (center (30.6,11.2,285.2), r 73); 20 NearLOD models; LEDScreen cycling via GwangalliWorld/Screens",
    "SIGN/GAMEPLAY MISMATCH: every price sign (facade, lobby board, standing sign) says '1곡 500원 · 4곡 1,000원' but the game rents by time (500원 per 30 in-game min); the 동전교환기 and coin culture have no gameplay",
    "Separate richer flow NOT wired here: GwangalliBuildings ShopFlows 'karaoke' + GwangalliBuildingsClient KaraokeView/KaraokeRoom/KaraokeMic/KaraokeBand/KaraokeLyrics (리모컨 예약 목록, 에코/키/싱크, voice mode, mic pass, cheers) serve only the procedural 광안 프라자 (GwB_Shop with ShopId attrs) in the demo district",
    "Must not block/rename/move: Booth_NN names + RoomNo/RoomName, KaraokeZone (keep the room's footprint inside it), KaraokePanel (corridor face, prompt dist 8), KaraokeScreen (TV face is GuiFace Back, the TV gui is client-built on it), StatusLight, MirrorBall, all 6 Seats per booth and the 4 WaitingSofa Seats, TableTop, Board_karaoke BoardFace, CardReader, WaterPurifier, Counter, AutoDoor leaves + pocket (leaves 4.5 wide slide ±4.25 -> keep x ≈-5.3..16.2 within 0.6 of z 268.4 clear), the corridor and door openings (z 299.5..304.5 etc.), Destination"
   ],
   "emptyOrCrude": [
    "Booths are 17.3x11.6 studs (≈5x3.5 m) with a 6-seat U sofa, a normal-노래방 size. A real 코인노래방 booth is ≈1.5-2.5 m² for 1-3 people (bench, small shelf). Missing inside: the coin/bill acceptor and touch song panel that every coin room has, a mic charging cradle, a bag hook, an AC/vent grille, a light/echo control panel and an intercom/call button",
    "Everything in the booth is boxes: sofas without rounded edges or tufting, box TV bezel, box karaoke machine with a 5-digit display, box speakers with disc cones",
    "Booth walls are flat: one fabric AccentWall, two flat AcousticPanels and six 1.1-stud tiles; no diffusers, patterned wallpaper, mirror wall or LED wall-wash; plain dark ceiling with 3 LED strips",
    "The booth door is a static glass slab that stays swung open against the partition: it never closes, has no frame, closer or window strip, so the rooms do not read as soundproof",
    "Lobby fixtures are flat-colour boxes (blue coin changer, red vending machine with 15 flat can slabs); the counter top is bare (no POS, mic-cover dispenser display or candy bowl); the waiting sofa is boxy; the lobby centre (x 0..20, z 273..290) is empty floor",
    "Back zone (47.6x16.8 studs) holds only a water purifier and two fake restroom doors on the rear wall",
    "Price signage contradicts gameplay (per-song signs vs time rental); the GwKaraoke attrs are dead"
   ],
   "realWorld": [
    "Entrance: 24H neon, coin-karaoke price board (1곡 500원 / 4곡 1,000원, or time packs), 무인 운영 + CCTV notice, 동전교환기 (bill -> 500원 coins), drink vending machine, mic-cover dispenser, mic UV sterilizer, hand sanitizer, sometimes a small counter with snacks",
    "Corridor: narrow (≈1.2-1.5 m), each booth with a room number LED, 사용중/빈방 light, glass door with frosted band and door closer, neon/LED strips",
    "Booth (coin type): 1-3 person bench, TV 32-50\" on the wall, TJ미디어/금영 machine with per-room coin payment module (coin + bill slot, remaining-song display), touch song-search panel or remote, 2 wireless mics on a charging cradle, speakers + amp, small shelf/cup holder, hooks, ventilation/AC, mirror ball or LED lighting with light modes, acoustic foam/diffuser walls",
    "General 노래방 room (larger): U sofa, glass table, tambourines, song books, remote, disco lighting, scoring screen with 점수 and 서비스 시간",
    "Back: restrooms, water purifier with paper cups, fire exit and extinguisher, trash/recycle bins"
   ],
   "interactionIdeas": [
    "Coin changer '지폐 교환' (1,000원 -> 2 x 500원 coin items) and a per-booth coin slot '500원 넣기' that buys songs, matching the signs (or change the signs to time pricing)",
    "Vending machine '음료 뽑기' (can drops into the tray -> drink act); water purifier '물 마시기'",
    "Booth 'Remote' / touch panel '곡 검색 · 예약' anchored on the prop (opens the existing picker); song book '노래책 보기'",
    "Table mic '마이크 들기' (weld mic, show the singer), '마이크 커버 씌우기' at MicCoverBox, '마이크 살균' at MicSterilizer (UV glow 10 s)",
    "Table tambourine '탬버린 흔들기': hide the table prop while the emote prop is in hand",
    "Booth door '문 닫기 / 열기' (swing with closer; StatusLight stays the source of truth)",
    "Light panel '조명 모드' (disco / mood / bright) driving LedStrip, MirrorBall spin and the laser",
    "Machine '에코 · 키' knobs (reuse KaraokeRoom.roomOp ideas), '점수 보기', 95+ '서비스 1곡'",
    "Lobby LED '인기차트 보기', board '오늘의 노래왕', waiting sofa '앉아서 기다리기'"
   ]
  },
  {
   "name": "광안빌딩 1F 계단 로비 + 2F-4F (스크린골프 · 당구클럽 · 필라테스)",
   "path": "Workspace.Gwangalli.karaoke['광안 코인노래연습장'] (Lobby*/Step/Mailboxes parts) + Workspace.Gwangalli.karaoke['광안빌딩 (코인노래연습장)']",
   "bounds": "lobby (-16.5,6.85,268.6)..(-7.4,17.95,290.2); upper floors solid Core (-46.1,20.5,268.4)..(41.1,53.5,358.5)",
   "enterable": false,
   "rooms": [
    {
     "name": "1F stair lobby (glass Door collides; Annex skips host venue 'karaoke')",
     "center": [
      -11.95,
      12.4,
      279.4
     ],
     "size": [
      9.1,
      11.1,
      21.6
     ],
     "floorY": 6.85,
     "ceilingY": 17.95
    },
    {
     "name": "2F-4F floors (Core 87.2x33x90.1, no interior)",
     "center": [
      -2.5,
      37,
      313.4
     ],
     "size": [
      87.2,
      33,
      90.1
     ],
     "floorY": 20.9,
     "ceilingY": 53.5
    }
   ],
   "props": [
    "Door 5.6x8.3 glass + Transom + DoorHandle, ShopWindow x2, Sign_광안빌딩 '2F-4F · 엘리베이터 없음', directory 'Sign_4F 필라테스 3F 당구클럽 2F 스크린골프 1F 코인노래'",
    "Step x8 (8.2 wide, 1.56 deep, rising to y 14.6 at z 289.9) that run into the Partition at z 290.6 (dead end, no landing or 2F door)",
    "Mailboxes 0.7x4x5 metal slab (CanCollide false), LobbyFloor, LobbyCeiling (only over z 268.6..277.4), LobbyLight",
    "Upper: 33 NightWindow windows, Pier/Spandrel/Blinds facade, floor signs Sign_광안 스크린골프 / 큐 당구클럽 / 광안 필라테스 & PT, vertical Sign_코인노래 and Sign_당구장, roof penthouse/tank/AC/antenna"
   ],
   "gameplay": [
    "None inside. Mailboxes is on the R4 protected list (ShopLife '우편함' name) but this lobby is not scanned (no ShopFloor/Interior)",
    "Annex HOST_VENUES skips everything under 'karaoke', so no annex entrance for 2F-4F"
   ],
   "emptyOrCrude": [
    "Stairs climb into a wall; the 2F-4F tenants are only signs on a solid core",
    "Bare lobby: no stair rail, handrail, landing light, wall directory, fire box or notice board"
   ],
   "realWorld": [
    "Narrow 계단식 상가 lobby: steel handrail, anti-slip stair nosing, landing with floor sign (2F 스크린골프), wall directory, mailboxes, motion-sensor lights, 소화전, posters for the tenants; 2F screen golf bays, 3F 4-ball billiard tables with 점수판, 4F pilates reformers"
   ],
   "interactionIdeas": [
    "Stair landing '2F 올라가기' -> annex floor (Annex building archetypes / existing 당구 physics ShopFlow), '층별 안내' directory, '우편함 확인'"
   ]
  },
  {
   "name": "광안 마라탕 (광안빌딩 1F 옆 가게)",
   "path": "Workspace.Gwangalli.karaoke['광안 코인노래연습장'] (ShopFloor/ShopBackWall/ShopLight/Counter/Sign_광안 마라탕 at x -46.2..-18.4)",
   "bounds": "(-46.2,6.85,268.6)..(-18.4,16.0,278.5)",
   "enterable": false,
   "rooms": [
    {
     "name": "Shop room 27.6x9.9 (glass Door collides; not ShopLife)",
     "center": [
      -32.3,
      11.4,
      273.55
     ],
     "size": [
      27.6,
      9.15,
      9.9
     ],
     "floorY": 6.85,
     "ceilingY": 16
    }
   ],
   "props": [
    "ShopFloor 27.58x0.3x10.2, ShopBackWall 27.58x9.7 tan slab, ShopLight 25.6x8.5 slab (NightNeon), Counter 8.27x3.3x2 red box (4 kids)",
    "Door 4.8x7 glass + Handle + DoorFrame, ShopWindow x4, ShutterBox, Sign_광안 마라탕 '마라샹궈 · 꿔바로우 · 포장 가능'"
   ],
   "gameplay": [
    "ShopStaff spawns an 알바생 (kind 'game' from the parent name '광안 코인노래연습장') behind this Counter - wrong persona for a 마라탕 shop",
    "MafiaService places its recruiter between 마라탕 and CLUB OCEAN outside (exterior only); StreetShops already has a 'mara' menu (마라탕 1인 12,000원) that could serve it"
   ],
   "emptyOrCrude": [
    "A box counter in an empty room: no self-serve ingredient fridge/bar (마라탕 재료 냉장 쇼케이스), bowls and tongs, scale, wok/soup station, tables or menu board"
   ],
   "realWorld": [
    "마라탕 shop: open ingredient fridge (vegetables, tofu, noodles, meat) with steel bowls + tongs, weigh-and-pay scale at the counter, spice-level chart (0-3단계), kitchen pass with soup pots, 4-8 tables, chopstick/spoon caddies, water purifier, takeout containers"
   ],
   "interactionIdeas": [
    "'재료 담기' at the ingredient fridge -> '무게 재기 · 계산' at the counter (weight-based price) -> '맵기 선택' -> seated eat (ShopLife counter flow with the existing 'mara' dish)"
   ]
  }
 ],
 "notes": "Full JSON is at /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/pcbang_karaoke.json (key pcbang_karaoke). Scope: Workspace.Gwangalli.pcbang (광안 PC방 + 광안타워) and Workspace.Gwangalli.karaoke (광안 코인노래연습장 + 광안빌딩). Both buildings face -Z (street side z<267); PC방 yaw ≈180.4°, karaoke exactly 180°. Interior floor top y 6.85 and ceiling underside y 17.95 (11.1 studs ≈ 3.3 m) in both; only the ground-floor venues can be entered. Upper floors (광안타워 2F-5F, 광안빌딩 2F-4F), both building lobbies and both side shops (광안 분식, 광안 마라탕) cannot be entered: their glass Door parts keep the default CanCollide=true, they have no AutoDoor tag, and Annex skips host venues 'pcbang'/'karaoke'.\n\nBiggest gameplay holes: (1) the PC client is a placeholder (GwangalliVenues/PC.luau, 18 lines), so 'PC 켜기' takes 1,000원, seats you and then shows nothing. (2) Every PCStation AislePos is mirrored about z≈266.5, so the food clerk tweens out through the front glass into the street and back; the correct value is ≈(120.8, 6.8, ServePos.Z). (3) ShopStaff treats each venue model's side shop (분식/마라탕) as the storefront and puts a PC방/노래방-style 알바생 there. (4) Karaoke signs say 1곡 500원 / 4곡 1,000원, but rental is 500원 per 30 in-game minutes.\n\nPart budget today: PC방 ≈1,577 interior parts (PCHall 1,218, of which 48 PCs x 23 = 1,104). Karaoke ≈1,149 (8 booths x 83 direct parts = 664, or 856 counting the sofa sub-models).\n\nUpgrades should be client-local, near-only overlays (Workspace.GwInteriorDetailLocal, NearLOD/ZoneLOD radii 66-110) that hide crude originals per rules R1-R7 in bld/systems.json. Inside ZoneLOD/NearLOD roots that are not arrive-hidden, set a local Transparency=1 and disable the SurfaceGuis yourself. Never hide PCStation Seat/Keyboard/MonitorScreen, KaraokePanel/KaraokeZone/KaraokeScreen/StatusLight/MirrorBall, Seats, TableTops or VenueSpot/VenueBoard/VenueStaff; overlay nicer non-colliding copies at the same pose instead. KaraokeScreen and MonitorScreen carry client-built SurfaceGuis (KaraokeTV, future PC desktop): keep the face (Back) and size, or move the gui with the overlay. New lights should be few, tagged InteriorLight (global budget: nearest 24/16/6) and backed by Neon emissive surfaces.\n\nScale: 1 stud ≈ 0.3 m. The PC seat pitch of 4.8 studs ≈ 1.45 m is wide (real ≈ 0.9-1.1 m), and the karaoke booths (≈5.2x3.5 m) are normal-노래방 size, not coin-booth size. Keep the existing footprints, because gameplay zones depend on them, and fill them with detail. Couple/premium seating can only be decoration unless the seat graph is rebuilt server-side.\n\nResearch sources: https://stay.enko.kr/blog/how-to-use-karaoke-in-korea ; https://glasswallet.com/blog/coin-karaoke-startup-cost-guide (each room has 반주기, amp, speakers, wireless mics, monitor and a coin payment module) ; https://www.geconomy.co.kr/mobile/article.html?no=321840 (2026 PC방 with 커플룸/커플석/3인석/5인 팀룸 and per-seat monitor tiers) ; https://www.gamemeca.com/view.php?gid=499245 (brand premium-gear zones in PC방).\n\nWorking files (read-only dumps): /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/pk/dump.json (every instance in both districts, with world pose/size/colour/attrs/tags), plus the helper scripts pk/ls.py, pk/aabb.py and pk/nd.py in the same folder."
}
```

## survey:arcade_club

```json
{
 "venues": [
  {
   "name": "광안 게임랜드 1F 오락실 (main hall + 계단 로비)",
   "path": "Workspace.Gwangalli.arcade.광안 게임랜드",
   "bounds": "hall (-377.6,6.8,405.1)..(-303.0,18.0,483.7); lobby (-323.8,6.8,394.7)..(-302.0,18.0,404.3); whole model (-428,6.5,379)..(-297,20.5,487) incl. 3 parked cars outside the back wall",
   "enterable": true,
   "rooms": [
    {
     "name": "오락실 hall (SpaceCarpet 80.2x75.7 floor, Ceiling at 18.15; model is rotated ~-89 deg about Y, facade/entrance faces +X onto 광안로)",
     "center": [
      -340.3,
      12.4,
      444.4
     ],
     "size": [
      74.6,
      11.2,
      78.6
     ],
     "floorY": 6.8,
     "ceilingY": 18
    },
    {
     "name": "entrance: 6 glass FoldedDoorLeaf (open storefront) + granite Threshold, x -305..-300, z 427.3..439.8; Destination '광안 게임랜드' at (-298.6,7.1,433.2)",
     "center": [
      -302.6,
      11.4,
      433.1
     ],
     "size": [
      3,
      9,
      12.5
     ],
     "floorY": 6.8,
     "ceilingY": 16.2
    },
    {
     "name": "계단 로비 (granite LobbyFloor, glass Door at z 396.7..402.7, 8 granite Step rising west from y 7.8 to 14.6 and ending at the end Partition x -324; LobbyCeiling only x -311..-302)",
     "center": [
      -312.9,
      12.4,
      399.5
     ],
     "size": [
      21.8,
      11.2,
      9.6
     ],
     "floorY": 6.8,
     "ceilingY": 18
    }
   ],
   "props": [
    "ClawMachine_01..12 x12 (36 parts each): Cabinet 4x2.8x4 SmoothPlastic box (6 colours), TopBox 4.2x1.3x4.1, Neon Marquee 3.8x1 with SurfaceGui text (인형뽑기/LUCKY/피규어/대형인형/과자뽑기/GOLD), GlassBox 3.9x3.8x3.9 T=.78, 4 corner Posts, PrizeBed 3.8x0.5x3.8 Fabric, 8 Plush (SpecialMesh) + 3 PlushHead balls, gantry rail + carriage + cable + hub + 3 thin box ClawProngs, ControlPanel slab + GrabButton + Joystick/Knob, CoinPlate '1,000원', PrizeDoor 1.3x1.3 flat black, DropGuard glass box, 2 EdgeNeon. Row of 6 along the side wall x -333..-307 z 480.5..485, island of 6 (2x3, back-to-back) x -321.6..-308.6 z 458.8..467. Decent silhouette, but all flat boxes, no side art/bevel/LED chase, no prize chute, no coin-op slot detail",
    "펀치기계 (10 parts): PunchBase 5.2x3.2x3.2 red box, PunchTower 4.4x6.4x1.6, Neon ScoreDisplay 'SCORE 987/오늘의 최고기록', PunchTopBox + PUNCH KING marquee, PadArm + Leather PunchPad 2.2x2.6x1.3, BoxingGlove box, CoinSlotPlate, Sign_도전! '900점 이상 경품 증정'. At x -320.8..-315.5 z 404.8..408.1 (against the south partition)",
    "BasketballMachine_1/2 (26 parts each): FrontCabinet 6x3x3 orange, Ramp 5.6x2.2x13 + RampBase, BackPanel 5.8x9.6, Backboard, 8 Neon Rim segments, cylinder Net T=.5, 2 Fabric SideNet 8.5x13 T=.55 + NetFrames, Neon Marquee BASKET KING, ScoreLED 'SCORE 36', FrontScore 'BASKET 00:45', 5 Rubber Basketball balls. x -379..-363 z 469..482.5 against the back wall",
    "RacingCabinet_1..3 (14 parts each): ScreenCabinet 6x9x4 single box, Neon RaceScreen 5.2x3.6 ('BUSAN RACER', 광안대교 코스 LAP 2/3...), DashBase box, SeatBase 4.8x0.3x5.5, Leather SeatBack slab + RacingSeat 2.2x0.5x2 box (no bucket shape), 2 SidePanels, cylinder SteeringWheel 1.9, WheelColumn, 2 box Pedals. x -379..-367 z 444.7..464.8",
    "리듬게임_DanceBeat (24 parts): DanceCabinet 9.2x8.4x3.4 box, Neon DanceScreen ('♪ 광안리 연가 PERFECT x128'), 2 Speaker boxes + 4 cones, Neon marquee, DiamondPlate DancePlatform 9.2x0.6x6.6 with 8 Neon ArrowPanels 1.2x1.2 (flat squares, not arrows), 2 SafetyBars + 4 SafetyPosts. x -378.2..-367.8 z 422.1..431.5",
    "RetroCabinet_1..4 (11 parts each): CabinetBody 3.6x7.2x3.4 single black box, flat Neon RetroScreen 3x2.2 (INSERT COIN / STAGE 3 / BUBBLE POP / GAME OVER), Neon Marquee (STREET FIGHT / SPACE WAR / BUBBLE POP / TANK 1990), ControlDeck slab, 2 joysticks + 2 knobs, round Leather StoolSeat on post. x -358.5..-342.8 z 404..411 (row on the south partition, all facing north)",
    "AirHockey (13 parts): TableBody 5.6x2.6x10 blue box, white PlayField, 2 Neon EndRails, 2 SideRails, 2 cylinder Mallets, Puck, 2 Goals, CenterLine, ScoreBoard '3 : 5'. Alone in the hall centre at x -346.3..-336.2 z 437.5..443.3",
    "CoinExchanger x2 (3x6.6x2.6 blue/red boxes) + Sign_동전교환기 + Neon ExchangerDisplay ('1,000원 → 500원 ×2', '5,000원 권 사용 가능') + BillSlot + CoinTray, x -312.4..-305.6 z 405..407.7 just inside the entrance",
    "Prize corner: PrizeCounterBase 13x2.6x3.5 + Glass PrizeShowcase + Marble PrizeCounterTop + Neon CounterLED (x -339.8..-326.7 z 410.4..414.2), 3 PrizeShelf 13x1.8 on the partition (z 404.4..406.5) holding 23 PrizePlush (SpecialMesh) at y 10.5/13/15.5, 8 SmallPrize boxes on the counter, Sign_경품 교환 · PRIZE, Sign_교환 안내 '티켓 100장 = 중형 인형'. No staff / ticket counter / POS",
    "VendingMachine (17 parts): Body 3.4x6.2x2.6 blue box, white Display panel, 15 Cans as 0.4x0.8x0.2 flat boxes (x -377.8..-375.2 z 418..421.5)",
    "Walls/ceiling: dark-purple Plaster WallLining x2 + Partition (no posters except 2 info panels), 11 CeilingNeon tubes (grid 5 pink x 6 cyan, 72-76 long), 4 WallNeon strips, 4 LightPanel (Neon + SurfaceLight, InteriorLight tag), 5 LightHolder PointLights, 2 CassetteAC (+ grille/vanes), 2 CCTV balls, black SmoothPlastic Ceiling slab, 18 CarpetConfetti 0.7 squares on a flat navy Carpet",
    "Wall info: Sign_이용 안내 (CCTV 녹화중 · 22시 이후 청소년 출입금지), Sign_인형뽑기 요금 (1회 1,000원 · 5,000원 6회), ScreenHousing + LEDScreen 6.4x3.6 (attr Messages '오늘의 펀치왕 987점|농구 최고 기록 64점|레이싱 베스트 랩 00:58.1|신규 인형 입고!', tag LEDScreen) on the side wall z 483.3",
    "Back wall x -377.7: RestroomDoor 4x8 flat Metal slab + Sign_화장실, ExitDoor 4x8 + PanicBar + green ExitSign (both doors lead nowhere: outer wall GroundBack is behind them), FireExtinguisher on the south partition; outside the back wall: 4 OutdoorAC + fans, 2 GasMeter, RecycleBins (4 bins)",
    "Facade (outside): Sign_광안 게임랜드 x2 + 34 MarqueeBulb (Neon balls), 12 NeonTube sign frames, 14 ShopWindow glass panes T=.5 + mullions, Sign_GAME/Sign_인형뽑기/price strips (transparent parts with SurfaceGui), StandingSign A-board, Sign_경품 대방출 on the side, Sign_3F 방탈출 2F 보드게임 1F 오락실 directory"
   ],
   "gameplay": [
    "Play/Arcade World (ServerScriptService.GwangalliGameplay.Play.Arcade.World, config GwangalliPlayShared.Arcade.MACHINES): finds Models by NAME under Workspace.Gwangalli.arcade.광안 게임랜드: '펀치기계' (needs PunchBase, PunchTower, PunchPad, ScoreDisplay with SurfaceGui Face/Text + Face/Sub), 'BasketballMachine_1'/'_2' (needs 8 child parts named 'Rim', FrontCabinet, ScoreLED Face/Text, FrontScore Face/Text). Builds workspace.GwangalliPlay.Arcade: Anchor_gl_punch / Anchor_gl_basket1/2 with ProximityPrompt 'ArcadePrompt' (G key, MaxActivationDistance 9, '한 판 하기', 펀치 500원 / 농구 1,000원) at stand = PunchBase floor +4.6 studs out of the pad, basket FrontCabinet +3.4 studs; ballFrom/hoop from Rim average. Games: punch (tap charge + needle), basketball (40 s power/aim), 1:1 팔씨름 (free). Scores/leaderboards/rewards in Hub; NPC regulars 민수/유나/지훈/박 사장/덕배 할배 for challenges",
    "Play/Arcade World ArmTable: builds its own 팔씨름 table (Top 3.2x0.3x2.4 + Leg + Pad + 2 Grips + Sign) at the FIRST spot whose 6x4x7 box (centre y+2.8) is empty server-side: (-327,6.75,428), (-330,6.75,425), (-332,6.75,440), (-345,6.75,425). Keep these 4 boxes clear of any new visible geometry (client builds do not block the server check but would visually intersect the table)",
    "Play/Arcade World boards: wallBoard raycasts 14 studs from the punch stand (+6.2 y, +side*6.5) and basket stand (+6.4 y) to the nearest map wall and paints P.Boards (Board_punch 4.6x3.2, Board_basketball), Board_armwrestle 3.4x2.6 hovers 8.6 above the arm table. LEDScreen (direct child, attr Messages) is rewritten live ('오늘의 펀치왕 %d점|농구 최고 기록 %d점|...'): do not rename/move LEDScreen or ScoreDisplay/ScoreLED/FrontScore labels",
    "GwangalliGameplay/Interact: tagExisting() tags each Model matching ^ClawMachine_%d+$ -> its PrizeDoor part gets tag GwInteract (GwKind 'claw', GwId = model name, label 인형뽑기). Server ops over ReplicatedStorage.GwangalliRemotes.InteractRequest: 'clawStart' {part=PrizeDoor} (within 9 studs, spends 1,000원 '광안 게임랜드 인형뽑기', pose claw_play, 12 s aim), 'clawDrop' {u,w in -1..1 over PrizeBed} (nearest Plush to the target, chance 0.12..0.55, prize 곰돌이/토끼/광안리 갈매기/고양이/펭귄/오리 인형, held plush 90 s, happiness +2), 'clawCancel'. Uses PrizeBed CFrame/Size and Plush positions. NO CLIENT in v7 (no GwangalliInteract hub module 'Claw'), so the 12 claw machines are currently NOT playable — the single biggest missing interaction",
    "Interact sittables (IS.classify by name): StoolSeat x4 (retro stools) -> chair, RacingSeat x3, SeatBase x3 ('seat' wins over 'base' -> bench), the 8 lobby 'Step' parts -> edge sit. Do not hide/move them",
    "GwangalliGameplay/ShopStaff: the arcade root Model has a direct child 'ShopFloor' (the photo shop floor) so the whole '광안 게임랜드' model is a storefront; its anchor is the only ANCHORS match 'Counter' (photo-shop counter at (-309.7,8.4,384.6)) -> one '알바생' NPC (kind game: hoodie/casual, typing/phone/teller, '말 걸기') stands behind the PHOTO counter, not at the prize counter. Keep ShopFloor/Counter/ShopBackWall and the 2x3-stud staff zone behind the counter",
    "DetailLOD: 24 machine Models are ZoneLOD (LOD='zone', LODRadius 86-91, LODCenter at the machine) and 7 NearDetail + ShopDetail + RecycleBins are NearLOD (LOD='near'); hide crude parts per R3 (Transparency vs LocalTransparencyModifier depending on GwArrive) and re-apply on stream-in",
    "Navigation / meta: Destination part DisplayName '광안 게임랜드' (tag Destination) = GwangalliNav node 3024 (-298.6,6.6,433.2), phone MapData, taxi names; Journey step 'arcade' (find radius 40, visit event arcade.play source arcade, hint from 준호 '펀치머신 한 판'); GwangalliCitizens area 'arcade' indoor r=70; IS.PHOTO_SPOTS 'arcade' (-330,7,433) r=45 (photo mode popularity); Pocha/Mind lines mention it",
    "GwangalliDetails 네컷사진관 '네컷사진관 게임랜드점' is a separate runtime booth auto-placed on the 광안로 sidewalk near (-301,6.5,452) yaw 270 (auto search r=70 around the Destination) in workspace.GwangalliDetailsWorld — keep the sidewalk in front of the facade clear",
    "Lights: 5 PointLight + 3 SurfaceLight tagged InteriorLight (GwangalliIndoorLight dims x0.55, Range cap 18); 136 parts tagged NeonTube (night neon), GwSurfaceGui on all signs; no ambient sound: GwangalliAmbience Soundscape has no arcade bed (silent arcade)",
    "Annex: arcade is in Annex HOST_VENUES, so GwangalliBuildings never gives the 2F/3F an annex interior; StreetSigns treats 'arcade' as a host ancestor"
   ],
   "emptyOrCrude": [
    "Hall is 28% occupied: largest empty floor square 34x34 studs centred (-345.3, 461.1) — between the claw island (x>-322), the basketball/racing wall (x<-367) and the air hockey (z<443.3). The whole north-centre (x -365..-322, z 445..479) is bare navy carpet; the south-centre around the air hockey (x -365..-322, z 415..437) also only has confetti squares. A real 오락실 of this size (~22x24 m) is packed wall-to-wall with ~40-60 machines in rows",
    "Only 25 machines total and 5 kinds of video games; no 대전 격투 (철권-style candy cabinets back-to-back), no 펌프잇업-style dance machine (DanceBeat is a DDR-like generic), no 총게임, no 리듬 (drum/유비트), no 두더지 잡기, no 망치/킥 machine, no 경품 뽑기 (key-master/ 가위 자르기 / 브릿지), no 가챠 capsule wall, no 코인노래방 booths",
    "Every cabinet is 1-3 axis-aligned SmoothPlastic boxes: RetroCabinet = one 3.6x7.2x3.4 black brick with a flat Neon rectangle as screen (no bezel, no angled CRT, no marquee overhang, no coin door/2 coin slots, no side art/T-molding, no 1P/2P button rows); RacingCabinet seat is a flat box on a slab (no bucket seat, no seat-belt/headrest, no shifter); DanceBeat arrows are flat squares; vending cans are flat 0.4x0.8x0.2 boxes; CoinExchanger is a coloured box with a strip display",
    "Floor = single flat navy Carpet with 18 loose 0.7-stud coloured squares as 'space pattern'; walls = flat dark plaster with a few neon strips — no game posters, no 등급분류 stickers, no mirror/LED wall art, no zone floor graphics. Ceiling is a black slab + tube grid, no speakers/sprinklers/hanging zone signs (only 인형뽑기 존 sign)",
    "Fake doors: RestroomDoor (화장실) and ExitDoor are flat slabs on the back wall with the outside wall right behind (no restroom behind); lobby stair (8 Steps up to y 14.6) ends against a wall — stair to nowhere although signs advertise 2F 보드게임 · 3F 방탈출",
    "Prize corner has no 직원/계산대 (the ShopStaff 알바생 is placed in the photo shop instead), no ticket dispenser/ticket counter, prize shelves are 3 flat slabs; no seating/bench, no trash bin, no water purifier inside (recycle bins are outside behind the back wall)",
    "Lighting is thin for 6,000 sq studs: 5 PointLights + 4 panels; machines have no own light (only Neon parts), no screen glow SurfaceLights",
    "Silent: no BGM/jingles/coin sounds anywhere in the arcade",
    "Retro/racing/dance/air hockey/vending/coin exchanger have no interaction at all; claws are server-ready but client-less"
   ],
   "realWorld": [
    "Storefront: 인형뽑기 기계 wall visible through glass, LED 전광판/채널 간판 '인형뽑기 · 오락실 · 코인노래방', 24시 무인 운영 sign, 지폐교환기 (1만/5천/1천원 -> 500원/1000원 coin) at the door, CCTV 녹화중 sticker, 청소년 출입시간 안내 (게임산업법: 22시 이후 청소년 출입 제한)",
    "Crane zone (인형뽑기방 style): 10-30 crane machines in rows/back-to-back islands, each ~0.9x0.9x2 m with LED-framed glass, top marquee lightbox, side plastic art panels, prize chute (상품 출구) with flap, coin/bill acceptor + card reader (카드 결제 단말기), 1회 1,000원 / 5,000원 6회 stickers, '집게 힘 조절 공지' sticker; variants: 대형 크레인(giant plush), 투클로, 과자뽑기, 피규어 브릿지(다리) 게임, 가위 자르기 (string-cut prizes), 키마스터/선물뽑기 behind acrylic (에어팟·닌텐도 스위치·향수), 랜덤박스 자판기",
    "Capsule-toy (가챠) wall: 20-60 stacked capsule machines (2-3 high), 500-3,000원, capsule recycle bin",
    "Video cabinets: 철권/KOF 대전 candy cabinets placed back-to-back in pairs (1P/2P sides, 32'' LCD, 8-button control panel, round stools), retro multi-game (50-in-1) cabinets, 슈팅/총게임 (light-gun cabinet with gun holsters, pedal), 레이싱 (마리오카트/이니셜D style: bucket seat, wheel, gear, pedals, 2-4 linked), 펌프잇업 (Andamiro, Korean) with 5-panel diagonal pad + safety bar, 유비트/사운드볼텍스/태고의 달인 drum, DJMAX",
    "Physical/sports: 펀치기 (boxing bag that drops), 킥 머신, 망치(해머) strength tester, 농구 (2-4 linked hoops, ball return ramp), 에어하키 (2P, LED rim), 두더지 잡기 (hammers on chains), 야구/축구 슈팅",
    "코인노래방 booths inside the arcade: 2-6 glass-door booths (2x1.5 m), sofa bench, monitor, 2 mics, 500원/1곡 · 1,000원/3곡 coin box, LED ceiling",
    "Prize exchange: glass prize showcase + wall of plush/figures with ticket prices, ticket counter machine, staff POS, plush bags",
    "Amenities: 음료 자판기 (cans/bottles with lit buttons, coin + card), 정수기 with paper cups, 쓰레기통/분리수거, 의자/둥근 스툴 at cabinets, 소화기 + 비상구 유도등, CCTV domes, 사업자등록증·게임제공업 등록증 frame, 화장실 열쇠 at counter (often in the building corridor)",
    "Finish/lighting: black-light 우주 패턴 carpet or checker tiles, black ceiling with RGB LED tubes, machines are the main light (screens + marquees), loud BGM + machine attract sounds, ceiling speakers"
   ],
   "interactionIdeas": [
    "인형뽑기 x12 (biggest win, server already exists): client-local prompt on PrizeDoor '인형뽑기 1,000원' -> InteractRequest:InvokeServer('clawStart', {part = PrizeDoor}); 12 s aim with WASD/stick moving a local copy of ClawCarriage over PrizeBed (u,w = -1..1), button/E to drop -> 'clawDrop' {u,w}; animate cable lowering, prongs closing, lift; on win drop the plush down the chute to PrizeDoor (server then sets GwHeld plush). 'clawCancel' on leave. Joystick/GrabButton animate with input",
    "RetroCabinet x4: sit on StoolSeat -> '한 판 하기 (무료 체험)' opens a SurfaceGui mini game on RetroScreen (SPACE WAR shooter / BUBBLE POP / TANK 1990 / STREET FIGHT 1-button), local hi-score shown on the screen and marquee flash",
    "RacingCabinet x3: sit in RacingSeat -> camera to RaceScreen, A/D turns SteeringWheel, W/S pedals; lane-dodge 광안대교 course on the screen, lap time vs the LED best lap",
    "DanceBeat: step onto DancePlatform -> arrow panels light on the beat, arrow keys / 4 on-screen pads, PERFECT/GREAT combo on DanceScreen; spectators see the panels flash",
    "AirHockey: 1P vs AI or 2 players on opposite ends; mallet follows mouse, local puck physics, ScoreBoard updates, goal horn",
    "CoinExchanger: '지폐 교환' -> bill slot animation + coin clink into CoinTray + display '500원 ×2' (cosmetic, no money)",
    "VendingMachine: '음료 고르기' -> lit product buttons, can drops into the bottom bin with sound (cosmetic; real purchase would need a server spend like GwangalliBuildings ACTIONS.vending)",
    "Prize counter: '경품 구경' UI listing the shelf prizes with ticket prices; move/duplicate the 알바생 look-alike there (client-only figure) or add a counter bell",
    "Punch/Basket/Arm wrestle already have server 'ArcadePrompt' — only add cosmetic attract-mode lights/sounds and keep ≥6.5 studs away from their anchors with any new prompt",
    "New machines for the empty 34x34 zone (non-colliding visual + local mini-games): 철권-style 대전 pair (2P local fight), 두더지 잡기 (hit moles 30 s), 가챠 wall ('가챠 돌리기' capsule pops out), 2 코인노래방 booths (door slides, '노래 고르기' list, link to the karaoke venue), 총게임 cabinet",
    "Restroom/exit doors: '화장실 (건물 복도)' / '비상구' prompt that shows a toast or locks with a rattle sound instead of a dead slab; lobby stair top: closed door '2F 보드게임카페 주사위 · 준비중' with knock prompt"
   ]
  },
  {
   "name": "셀프사진관 찰칵 (4컷 사진 · 24시간 무인) inside 게임랜드 빌딩",
   "path": "Workspace.Gwangalli.arcade.광안 게임랜드 (ShopFloor / ShopBackWall / ShopLight / Counter / Sign_셀프사진관 찰칵 / Door at z 390.2 / ShopDetail)",
   "bounds": "(-312.4,6.8,380.9)..(-302.0,16.5,393.2)",
   "enterable": true,
   "rooms": [
    {
     "name": "photo shop room (CeramicTiles ShopFloor 12.08x10.2, ShopBackWall at x -312, glass Door 4.8x7 on the facade at z 387.8..392.6, ShopLight panel at y 16.1 is the only 'ceiling'; partition to the stair lobby at z 393.9..395.1)",
     "center": [
      -307.2,
      11.6,
      387
     ],
     "size": [
      10.4,
      9.7,
      12.3
     ],
     "floorY": 6.8,
     "ceilingY": 16.1
    }
   ],
   "props": [
    "ShopFloor x1 CeramicTiles (214,212,204)",
    "ShopBackWall x1 12.08x9.7x0.5 white SmoothPlastic",
    "Counter x1 3.62x3.3x2 pink WoodPlanks box at x -310.8..-308.7 z 382.8..386.4 (ShopStaff anchor)",
    "ShopLight x1 10.08x0.2x8.5 (tag NightNeon)",
    "ShopDetail/DoorFrame x1 (5.1x0.28x0.21 metal), Handle x1 on the door",
    "Sign_셀프사진관 찰칵 on the fascia ('4컷 사진 · 24시간 무인')"
   ],
   "gameplay": [
    "ShopStaff: this ShopFloor makes the parent '광안 게임랜드' a storefront and 'Counter' is the anchor -> an 알바생 NPC (kind 'game') stands behind the counter facing the door and offers '말 걸기'. Never hide/move ShopFloor, Counter, ShopBackWall (R4); keep 2x3 staff zone behind Counter",
    "GwangalliDetails 네컷사진관 is NOT here: the Details photo-booth session (frame colour, props, 3-2-1, 4 poses -> polaroid strip, album, 같이 찍기) runs only at its own booths (spots prom / arcade sidewalk (-301,452) / market). An indoor booth could reuse the same client UI pattern but cannot start a Details session without a server spot",
    "IS.PHOTO_SPOTS 'arcade' (-330,7,433) r=45 covers this shop: first photo-mode picture here gives popularity +1"
   ],
   "emptyOrCrude": [
    "Room is a 10x12 empty tiled box with a single pink box 'Counter' — there are NO photo booths, no curtains, no kiosk, no props, no mirror; 40% of the floor is the counter + walls only, largest empty square 6x6 at (-308.4,388.9)",
    "No real ceiling (light panel floating at 16.1 under the building core at 20.5), bare white back wall, no sample-photo wall, no lighting other than the panel",
    "A '24시간 무인' shop with a staffed counter NPC is contradictory; real 무인 사진관 have a payment kiosk instead of a clerk"
   ],
   "realWorld": [
    "2-4 photo booths (인생네컷/포토이즘/하루필름 style) ~1.5 W x 2 D x 2.2 H m each: black/white/pink box, fabric curtain on a rail, inside: monitor + camera with ring/soft box, shutter remote, bench/stool, backdrop colour (white/pink/blue), floor mark",
    "Payment kiosk per booth (touchscreen, card reader, 4,000-5,000원, frame/선택 메뉴), QR download sign",
    "Prop wall / 소품 rack: 머리띠 (bunny ears), 모자, 선글라스/하트 안경, 왕관, 가발, 인형, 말풍선 피켓 on hooks and baskets",
    "Vanity: large mirror with bulb frame, 고데기/드라이기/빗/헤어롤, 거울 앞 선반, 화장대 의자",
    "Printer output slot + 사진 정리 테이블 with 가위·투명 포토 케이스, trash bin",
    "Sample photo wall (액자 collage), brand neon logo, bright white LED ceiling, tiled or epoxy floor, 'CCTV 촬영중' and 이용 방법 1-2-3 signs"
   ],
   "interactionIdeas": [
    "Booth curtain: '커튼 열기/닫기' (local tween), inside '촬영하기' -> client photo mode 3-2-1 with flash + 4-cut strip from ViewportFrames (copy the Details look; cosmetic, no server spend)",
    "Prop rack: '소품 고르기' -> pick 머리띠/안경/모자, attach a local accessory for the session",
    "Vanity mirror: '머리 만지기' -> camera close-up + hair-fix emote, 고데기 steam particle",
    "Kiosk: '프레임 선택' UI (colour frames, 2컷/4컷) feeding the booth session",
    "Printer slot: strip slides out at the end with sound"
   ]
  },
  {
   "name": "게임랜드 빌딩 2F 보드게임카페 주사위 / 3F 방탈출 카페 미스터리룸 (upper floors)",
   "path": "Workspace.Gwangalli.arcade.게임랜드 빌딩 (오락실)",
   "bounds": "(-381,20.5,378)..(-297,56.3,487); floors 2F y 20.5..31.7, 3F y 31.7..42.5 (FloorBand at 31.7)",
   "enterable": false,
   "rooms": [
    {
     "name": "solid Core 104.2x22x76.1 Concrete (no interior) behind facade glass",
     "center": [
      -340.5,
      31.5,
      432.4
     ],
     "size": [
      76.1,
      22,
      104.2
     ],
     "floorY": 20.5,
     "ceilingY": 42.5
    }
   ],
   "props": [
    "Core x1 solid concrete block (no rooms)",
    "Facade: Blinds x3 (Fabric strips 105.2x3.94 / 77.2x2.68 / 77.2x3.29 pressed on the glass), FacadeDetail WinFrame x8, WinStile x29, SillStain x4, Pier, FloorBand x2, 30 'Window' parts tagged NightWindow (LitChance/LitColor/LitSeed attrs)",
    "Signs: Sign_보드게임카페 주사위, Sign_방탈출 카페 미스터리룸, vertical Sign_인형뽑기 x2, Sign_방탈출 x2",
    "Roof: Parapet, Coping, Crown (pink plaster), Penthouse 12x9x10, 3 ACCondenser + skid + fans, Antenna"
   ],
   "gameplay": [
    "Model attr Floors=3; NightWindow windows lit at night by the environment system",
    "Excluded from Annex (arcade is a HOST_VENUE) so no system builds these floors; the 1F lobby stair and directory sign point to them"
   ],
   "emptyOrCrude": [
    "The 2F/3F businesses advertised on 3 signs do not exist: solid concrete core, blinds glued to the glass; the 1F stair dead-ends at y 14.6"
   ],
   "realWorld": [
    "2F 보드게임카페: tables for 2-6 with chairs, wall shelves of 300+ board games (부루마블, 할리갈리, 루미큐브, 젠가), counter with drinks/snacks (음료 1잔 필수), 시간제 요금표 (1시간 3,000원), staff explaining rules, bell",
    "3F 방탈출: reception/waiting lounge with theme posters (공포/추리/감성), lockers for phones, 3-5 theme rooms with locked doors, hint tablet/walkie-talkie, CCTV control desk, photo zone with result boards ('탈출 성공 00:42')"
   ],
   "interactionIdeas": [
    "Keep non-enterable but finish the stair: landing + closed door '2F 보드게임카페 주사위 · OPEN 13:00' with '문 두드리기' / '예약 안내' toast",
    "Optional later: a client-only 2F board-game room (tables + shelves) reached through a door at the stair top; 3F escape-room lobby with a '테마 고르기' poster wall (cosmetic)"
   ]
  },
  {
   "name": "CLUB OCEAN 광안 — entrance sequence (Forecourt, Vestibule, EntranceTunnel, Lobby: 입장료 cashier, lockers, photo wall)",
   "path": "Workspace.Gwangalli.club.CLUB OCEAN 광안.{Forecourt, ClubDoor, Vestibule, EntranceTunnel, Lobby}",
   "bounds": "forecourt (-237,6.5,264)..(-217,31.4,487); vestibule (-219.8,7,368.5)..(-211.6,16.5,382.6); tunnel (-211.8,7,369.6)..(-192.1,16.5,381.9); lobby (-192.6,7,344.9)..(-177.2,17.5,407.1)",
   "enterable": true,
   "rooms": [
    {
     "name": "Forecourt (granite EntrancePlatform, RedCarpet, valet bay, queue, ID podium)",
     "center": [
      -227,
      7,
      375
     ],
     "size": [
      20,
      10,
      140
     ],
     "floorY": 6.8,
     "ceilingY": 19.3
    },
    {
     "name": "Vestibule (metal detector frame, open door leaves)",
     "center": [
      -215.7,
      11.8,
      375.6
     ],
     "size": [
      8.2,
      9.5,
      14.1
     ],
     "floorY": 7,
     "ceilingY": 16.5
    },
    {
     "name": "EntranceTunnel (30 vertical LED bars, 2 floor lines)",
     "center": [
      -202,
      11.8,
      375.8
     ],
     "size": [
      19.7,
      9.5,
      12.3
     ],
     "floorY": 7,
     "ceilingY": 16.5
    },
    {
     "name": "Lobby (marble floor + brass inlay, velvet walls, ceiling neon ring)",
     "center": [
      -184.9,
      12.3,
      376
     ],
     "size": [
      15.4,
      10.5,
      62.2
     ],
     "floorY": 7,
     "ceilingY": 17.5
    }
   ],
   "props": [
    "Forecourt: IDPodium + wedge PodiumTop + Tablet_IDCheck + ScannerLED + Sign_신분증 필수 + ProximityPrompt IDCheckPrompt ('신분증 보여주기', tag ClubIDCheck); ValetStand + Sign_VALET + AFrame x2 발렛파킹; Planter x2 with palms; Bollard x2 LED; GuestListSign A-frame; TaxiDropOff staged open taxi door; 3 parked cars (Genesis G80, 2 taxis) with full interiors; queue NPCs (People Zone 'Near' x10)",
    "ClubDoor (28 parts, tag ClubDoor, attrs Inward/SlideTime 0.75): 2 sliding leaves with glass/LED/pulls, ClubDoorBarrier (14.1x10.1 invisible-ish blocker) + _VIP/_Exit/_SideExit barriers, ClubDoorOutside (eject point), ClubBouncerPost with ClubEntryPrompt ('입장하기', tag ClubIDCheck), 2 rope posts + velvet ropes (closed/open), Sign_ENTRY ₩30,000 (FRI·SAT ₩50,000 · 팔찌 재입장 무료)",
    "Vestibule: VestibuleWall x2, DoorLeaf_Open x2 + DoorPull x2, DetectorPanel x2 + DetectorHead + DetectorLED (walk-through metal detector)",
    "EntranceTunnel: TunnelLED x30 (ClubLight Kind Tunnel), FloorLine x2, TunnelLightHost PointLight",
    "Lobby/Cashier_입장료: CashierCounter 10 long + metal CounterTop + UnderGlow + 3 Onyx panels, 3 GlassPartitions, BackDesk, POSMonitor, TerminalScreen, CardTerminal, CashTray, WristbandBoard with 30 Wristbands, Sign_ENTRANCE · 입장료 '₩30,000 (1 DRINK) · FRI/SAT ₩50,000'; Staff_001 + Guest NPCs",
    "Lobby/Lockers_락커: LockerCarcass 18.8x9.1 with 32 LockerDoor + 32 KeypadLED + numbers 101-132, Sign_LOCKER · 물품보관함 ₩2,000 (x -192.1..-190.2, z 384.5..403.3)",
    "Lobby photo wall: StepAndRepeat 13.2x9.9 fabric (CLUB OCEAN / 광안 · GWANGALLI logo grid), Sign_오늘 밤, 광안리에서 + neon, Sign_#CLUBOCEAN #광안리, RingLight + core + PhoneHolder + tripod (3 legs), PhotoMark floor sticker",
    "Lobby misc: LobbyRight bench (base/cushion/back) + Sign_TONIGHT · 오늘 밤 + plant; Sign_HOUSE RULES (약물 반입 금지 · 음주운전 금지 · 분실물 책임지지 않음), Sign_CLUB OCEAN 16x5, Sign_MAIN HALL ▲, Sign_TABLE · BAR · DJ ▶, curtain (8 folds + valance), ExitSign"
   ],
   "gameplay": [
    "Club.server PAID DOOR: ProximityPrompts tagged ClubIDCheck (IDCheckPrompt at the podium, ClubEntryPrompt at ClubBouncerPost) -> ClubRemote 'door' sheet (walk-in fee weekday 30,000 / Fri-Sat 50,000, or table booking), spend via GwangalliGameplayAPI, wristband attrs ClubOceanWristband/ClubOceanWristbandUntil; door is client-side (GwangalliClubShow Door: local slide + barrier); every EjectEvery s the server teleports players without wristband from any non-Near ClubZone to ClubDoorOutside",
    "Life.luau club hooks: cover / VIP table spend, waypoint 'CLUB OCEAN 광안', entry stats; Journey/Club gate (found within 60 studs of the Destination or in the Near zone)",
    "ClubRuntime zone boxes (tag ClubZone, attr Zone): Zone_Lobby (-219.1,6.5,344.5)..(-177.2,18.5,407.1), Zone_Near (-285,-1.5,219.6)..(-43.4,76.5,533.1). GwangalliPlayShared.Zones and ClubRanking Zones read them",
    "ClubLights drives every ClubLight-tagged part (777 total; Tunnel x30, Portal, FacadeLine...) — don't hide/recolour them; ClubCrowd (StreetLife) animates the People rigs (130 ClubNPC, AnimationController)",
    "ShowAnchors Show_Lobby / Show_HallTurn / Show_HallDoor used by GwangalliClub Booking (합석 event walk)",
    "Interact excludes everything under 'CLUB OCEAN' from sittable tagging; systems.json rule: only wall-mounted, non-colliding decor in the club; DetailLOD: Lobby/EntranceTunnel are ZoneLOD (LODRadius 73/53)"
   ],
   "emptyOrCrude": [
    "Lobby is 47% occupied and well dressed; small gaps only (12-stud empty square at (-185.6,369.9) = the walking lane, which must stay clear)",
    "Lockers, wristband board, coat/ID desk and photo wall are pure decoration: no locker opens, the ring-light photo wall has no photo action",
    "Tunnel is 33% occupied: bare walls between the LED bars (fine for a light tunnel); vestibule has no ID scanner screen or bag-check table"
   ],
   "realWorld": [
    "Door: 신분증 검사 with ID scanner/flashlight, 19세 미만 출입금지 sign, bouncers in black, velvet ropes + VIP lane, guest list MD with tablet, 손목밴드/도장, metal detector wand & 소지품 검사 table, smoking area outside",
    "Cashier: 입장료 board (요일별, 1 drink 포함), card terminal, wristband colours by night, coat check/물품보관 (₩2,000-3,000), lockers with keypad or key wristband",
    "Lobby: step-and-repeat photo wall with ring light, event posters (DJ lineup), 하우스 룰, 분실물/휴대폰 충전 대여 (보조배터리), water, CCTV"
   ],
   "interactionIdeas": [
    "Locker: '보관함 열기' on a LockerDoor -> door swings (local), keypad beep, 'No.1xx 사용 중' toast; second press closes",
    "Photo wall: stand on PhotoMark -> '포토월 촬영' ring-light flash + camera snap (client photo mode with flash), no server cost",
    "Wristband board: '팔찌 확인' shows the player's own ClubOceanWristbandUntil time (read-only attr)",
    "Metal detector: walking through DetectorPanel beeps/flashes DetectorLED (client sound)",
    "Do NOT add prompts near IDCheckPrompt/ClubEntryPrompt (6.5-stud rule) and never duplicate pay/entry"
   ]
  },
  {
   "name": "CLUB OCEAN 광안 — Main Room (dance floor, DJ booth, LED wall, MainBar, TableFloor 31 tables, Mezzanine, HallRooms)",
   "path": "Workspace.Gwangalli.club.CLUB OCEAN 광안.{MainRoom, MainBar, TableFloor, HallRooms, ClubShowAnchors}",
   "bounds": "(-177.2,7.0,341.1)..(-71.2,32.5,412.7); HallRooms extend to z 425",
   "enterable": true,
   "rooms": [
    {
     "name": "Main hall (BlackGlossFloor 70x105, black ceiling install 22.2..32.5, Zone_Main)",
     "center": [
      -124.2,
      19.8,
      376.9
     ],
     "size": [
      106,
      25.5,
      71.6
     ],
     "floorY": 7,
     "ceilingY": 32.5
    },
    {
     "name": "LEDDanceFloor (48 Neon tiles, ClubFloorTile) in front of the DJ booth",
     "center": [
      -107,
      7.1,
      373.5
     ],
     "size": [
      9.2,
      0.2,
      22.2
     ],
     "floorY": 7,
     "ceilingY": 32.5
    },
    {
     "name": "DJ booth platform (BoothDeck)",
     "center": [
      -98.7,
      10.2,
      373.7
     ],
     "size": [
      6.4,
      16,
      23.8
     ],
     "floorY": 10.3,
     "ceilingY": 26.3
    },
    {
     "name": "VIP platform G1-G4 (x -88..-71)",
     "center": [
      -79.5,
      8,
      373
     ],
     "size": [
      17,
      10,
      58
     ],
     "floorY": 8,
     "ceilingY": 32.5
    },
    {
     "name": "Mezzanine (3 booths M1-M3, champagne bar, 흡연실) along the west wall",
     "center": [
      -167,
      19.5,
      376
     ],
     "size": [
      20.5,
      13,
      70
     ],
     "floorY": 19.5,
     "ceilingY": 32.5
    },
    {
     "name": "SmokingRoom_흡연실 (glass box on the mezzanine)",
     "center": [
      -171.4,
      23.6,
      347.2
     ],
     "size": [
      9.7,
      8.2,
      11.4
     ],
     "floorY": 19.5,
     "ceilingY": 27.7
    },
    {
     "name": "HallRooms: CoatCheck_물품보관 (-176.7..-164.5, z 364.6..381), InfoDesk, CornerLounge_A/B, 남자화장실 (-177.4..-167.5, z 395.4..424.3), 여자화장실 (-81.2..-72, z 401.6..424.1)",
     "center": [
      -124,
      12.7,
      383
     ],
     "size": [
      106,
      11.5,
      84
     ],
     "floorY": 7,
     "ceilingY": 18
    }
   ],
   "props": [
    "Finishes: BlackGlossFloor, BackWallLining, 22 LacquerPanel, 13 WallLEDLine + 3 CoveLED + 3 FloorLEDLine (ClubLight AccentLine), BrassLine",
    "LEDWall: 352 Neon LEDPanel (1.67x1.47) in LEDWallFrame 56.8x17.8 on the back wall x -73..-71 (ClubLight Kind Wall, Col/Row attrs)",
    "DJBooth (96): BoothPlatform 23.8 long + DiamondPlate deck, 38 BoothLED, glass rails, 4 steps, DJDesk + 4 CDJ3000 + DJM_Mixer + jog wheels/displays, laptop on stand, 2 BoothMonitor on stands, gooseneck WorkLamp, DeskLogo; DJ_009 + MC_010 NPCs",
    "Show rig: TrussRig (6 TrussParts + 8 chain hoists), Fixtures 12 MovingHead + 8 BeamFixture + 6 strobes + 2 blinders (20 Beams, 12 SpotLights), Lasers x4 (32 Beams), Effects CO2 x4 / Confetti x2 / Hazer x2 (10 ParticleEmitters), ShowInstallation: MirrorBall 6 dia + 34 glints + pin spots, 20 KineticTube winches, StageFX cold spark x4 / flame x2 / low fog x2, spiral ducts, cable trays, sprinklers, delay speakers, Wayfinding hanging signs; SoundSystem 16 line-array cabinets + 6 flown subs + 4 wall fills",
    "MainBar (340): 4 BarCounter sides around an island (x -148..-124.7, z 363.9..382) with Marble BarTop + brass + 16 OnyxFront, FootRail, UnderBarStation, 4 IceWell, 2 TapTower, DripTray, POSScreen, Gantry back bar with 6 FridgeGlow + backlight + 2 glass shelves, 11 stools (6 Seat + 5 non-seat StoolCushion), BarDetail 75 bottles + 24 speed-rail bottles + 8 tap handles + garnish trays/shakers/highballs/rocks/12 shot glasses/2 소주 bottles, BarCanopy 24 hanging glasses + 2 MenuBoards (칵테일 12,000-15,000 / 모엣 390,000 / 돔 페리뇽 890,000 / 소맥 SET 25,000 / 생맥주 9,000); Bartender_019/020/021",
    "ServiceStation (232) along z 407-412: 96-panel side LED frame, 5 pilasters, BackBarCounter 53.8 + Marble top, 63 bottles on 2 glass shelves, 16 glasses, 4 LED ice buckets + champagne, LEDSignBoards (HAPPY BIRTHDAY ♥ / VIP ♛ OCEAN), SparklerBox, IceMachine, Sign_VIP BOTTLE SERVICE",
    "TableFloor: 31 ClubTable models — Standing T1-T10 (podium + marble top + ring LED + bottle set), Bar S1-S6, DJ D1-D3, Booth B1-B8 (tufted velvet sofas, partitions, marble tables, pillows), VIPPlatform G1-G4 (raised marble platform, velvet ropes, 80 tufted channels, 18 champagne, fruit platters, birthday cake, foil balloons, MOËT TOWER ChampagneTower, ChampagneCabinet); every table has ServePoint",
    "Mezzanine: 3 MezzSlab + carpet, fascia LED x7, glass balustrades, 22-step marble stair with StepLED, 3 MezzBooth (velvet back, sofa, marble table, ice bucket, flutes, M1-M3), MezzChampagneBar (17 bottles), SmokingRoom (glass walls, extractor hood, leather bench, 2 ashtray pedestals, haze emitter)",
    "HallRooms: CoatCheck (27 Coats on 2 rails, ticket board 01-12, ₩3,000), InfoDesk (reservation book, tablet, HOUSE RULES '19세 이상 · 신분증 · 테이블 예약제'), CornerLounge_A/B (carpet platforms, tufted sofas, marble tables with bottle sets), StaffDoor_관계자외출입금지 (dark doorway), 2 restrooms (3+2 stalls, urinals, marble vanity, halo mirrors, powder bench), CCTV domes x4"
   ],
   "gameplay": [
    "Club.server tables: Models tagged ClubTable (31; attrs TableId/TableType Standing|Bar|DJ|Booth|VIP/Capacity/Reserved) -> '보틀 서비스' ProximityPrompt on every ServePoint (ClubShared.Menu champagne / VIP parade / birthday parade via ClubRemote 'order', spend through GwangalliGameplayAPI) and '테이블 앉기' when the table has Seats (124 Seat parts in the club). ParadeAt/ParadeTable/ParadePath on ClubRuntime: staff walk ParadeRoute WP1-WP8 to the table; WallMsg* attrs put names on the LED wall",
    "GwangalliClub (Show/Booking/BottleService) + client GwangalliClubShow (Show/Booking/Ui): bottle shows use ServePoint, BucketRim, ShowBottle/ShowFoil/SetSparkler names, Show_LEDWall/Show_DJ/Show_SpotRig/Show_Floor/Show_StaffDoor anchors; 합석 booking uses Seat attr ClubGuestSeat",
    "ClubLights (client, 4,560 lines): all ClubLight parts by Kind (Wall 448, Booth 39, TableRing 38, IceBucket 54, AccentLine 22, MovingHead 16, Kinetic 20, Strobe, Blinder, Beam, LaserEmitter, BarFront/BarBack, Fascia, VIPEdge, MirrorBall/Glint, ColdSpark/Flame/LowFog...), ClubFloorTile x48, ClubLaser, ClubCO2, ClubConfetti, ClubHaze, ClubFX, ClubMirrorRay, ClubShowBeam; 64-bar show synced on ShowEpoch; ClubDance client = dance ring game (+3 happiness / 10 min through Club.server); ClubMusic (BPM 126)",
    "ClubRanking (GwangalliBuildings): builds ClubRankingBoard on the main room's south wall (raycast from the MainRoom bounding-box centre along -RightVector, BOARD_Y) — keep that wall face free; Zones attr lists ZONE_MODELS {MainRoom, TableFloor, HallRooms, MainBar, OceanSkyLounge_2F, Room2_HipHop, RooftopTerrace, Corridor, Lobby, VIPStair}",
    "People: 106 ClubNPC rigs in Zone 'Main' (attrs Anim/Pose/Role/Zone/Bounce) animated locally; DetailLOD ZoneLOD for MainRoom (r 106), MainBar (63), TableFloor (94), HallRooms (108)",
    "Hard rule (systems.json): nothing on the LED dance floor, no colliding props in the club, only wall-mounted non-colliding decor; never move seats/ServePoints/table tops"
   ],
   "emptyOrCrude": [
    "Main hall is 75% occupied and is the most detailed interior in the map (largest empty square only 10 studs at (-167.2,387.1), the mezzanine stair foot). Not crude",
    "Minor: 5 of the 11 MainBar stools are non-sittable StoolCushion parts; bottles are plain Glass cylinders without labels/caps; menu boards are SurfaceGui text only",
    "StaffDoor_관계자외출입금지 is a DarkDoorway decal-like slab; back of house (BackOfHouse/StaffRooms_*/plenums) are solid concrete blocks — fine as non-enterable",
    "Hall restrooms (HallRooms) are compact and complete but have no paper towel/trash/tissue dispensers"
   ],
   "realWorld": [
    "Korean EDM club main hall (서면/강남/해운대 style): raised DJ booth with 4x CDJ-3000 + DJM-V10/A9, booth monitors, LED wall/mapping behind the DJ, moving heads/lasers/CO2 jets/cold sparks, mirror ball, line arrays + subs, black ceiling with trusses",
    "Tables: 스탠딩 테이블, 부스 (소파 6인), VIP 단상 with velvet rope, 테이블 번호, LED 얼음 바스켓, 양주/샴페인 세트, 과일 안주, 스파클러 bottle parade, 생일 이벤트 (cake, balloon, LED board)",
    "Bar: island or wall bar, back bar with 양주 (조니워커/잭다니엘/예거), 샴페인, 하이볼, 소맥, 생맥주 taps, POS, ice wells, glass racks, menu lightbox",
    "Mezzanine/VIP booths, 흡연실 (legally separate glass room with extractor), restrooms with 파우더룸, coat check, staff in black with earpieces/light sticks, security posts, CCTV, exit signs, 생수 무료 station"
   ],
   "interactionIdeas": [
    "Bars: '메뉴 보기' on BarCanopy MenuBoards (local UI of the drink list; no order — bottle service is server-owned at tables)",
    "DJ booth (from the floor in front of BoothGlassRail, not on the LED floor): '신청곡 쪽지 전달' -> toast 'DJ에게 쪽지 전달!' + DJ NPC nod emote (cosmetic)",
    "Champagne tower (VIPPlatform/ChampagneTower) and cake: '구경하기' camera framing + sparkle particles",
    "Smoking room: SmokeDoor slides open on approach (local), extractor fan hum, haze thicker while inside",
    "Coat check: '옷 맡기기' -> a coat appears on the rail with a ticket number toast; InfoDesk tablet: '예약 확인' showing the player's table (read GwangalliClubShow Tables attr)",
    "Restroom sinks/hand dryers/mirrors: '손 씻기' water particle + sound, '핸드 드라이어' sound, '거울 보기' camera close-up; stall doors swing + OccupancyLED red/green"
   ]
  },
  {
   "name": "CLUB OCEAN 광안 — Restrooms_화장실 (front block) + Corridor",
   "path": "Workspace.Gwangalli.club.CLUB OCEAN 광안.{Restrooms_화장실, Corridor}",
   "bounds": "restrooms (-217.7,6.8,263.5)..(-176.0,18.0,312.1); corridor (-176.1,6.8,264.1)..(-158.0,17.5,340.4)",
   "enterable": true,
   "rooms": [
    {
     "name": "여자화장실 (tiled floor/ceiling, 41 deep)",
     "center": [
      -196.8,
      12.3,
      280.3
     ],
     "size": [
      41.3,
      10.5,
      19.6
     ],
     "floorY": 7,
     "ceilingY": 17.5
    },
    {
     "name": "남자화장실",
     "center": [
      -197,
      12.3,
      301.8
     ],
     "size": [
      41.3,
      10.5,
      20.6
     ],
     "floorY": 7,
     "ceilingY": 17.5
    },
    {
     "name": "ExitPassage (emergency passage along the street wall)",
     "center": [
      -196.6,
      11.4,
      266.8
     ],
     "size": [
      41.1,
      8.5,
      6.6
     ],
     "floorY": 7,
     "ceilingY": 15.5
    },
    {
     "name": "Corridor (Zone_Corridor, links lobby side, restrooms and ROOM 2)",
     "center": [
      -167,
      12.3,
      302.2
     ],
     "size": [
      18.1,
      10.5,
      76.3
     ],
     "floorY": 7,
     "ceilingY": 17.5
    }
   ],
   "props": [
    "Restrooms (101 parts): 5 StallPartition + 5 StallDoor + 5 OccupancyLED + 5 ToiletBowl + 5 Cistern + 5 ToiletSeat, 2 StallHeader, 2 Marble VanityCounter 18 long + under-glow, 6 VesselSink + 6 WallTap + 6 SoapDispenser + 6 BasinWater, 6 RoundMirror + 6 MirrorHalo (Neon), 4 Urinal + 4 UrinalDivider, 2 HandDryer, 6 WallTile panels, WCDivider, Sign_오늘도 예뻐 ♡ / Sign_LOOKING GOOD, 2 PointLights",
    "Corridor (27 parts): floor/ceiling, 3 CorridorNorthWall concrete, CeilingLED + 2 SkirtLED, signs 여자 WOMEN / 남자 MEN / 화장실 RESTROOM / ROOM 2 · HIP-HOP (+ neon) / LOVE · MUSIC · OCEAN / ◀ ROOM 2 · 화장실 / MAIN HALL ▶ / TONIGHT WE DANCE, 3 event posters (FRI · DJ HAEWON TECH HOUSE 23:00, SAT · SEAN WAVE K-EDM 23:30, LADIES NIGHT THU FREE ENTRY 22-24), FireExtinguisher + Sign_소화기, ExitSign, 1 PointLight"
   ],
   "gameplay": [
    "ClubZone boxes Zone_Restroom (-217.7,6.5,263.5)..(-176,18.5,312.1) and Zone_Corridor; wristband eject applies inside; ClubLights treats 'Corridor' as a lighting zone",
    "DetailLOD ZoneLOD: Restrooms_화장실 (r 73), Corridor (r 82)",
    "Club rule: no colliding new props in the club; stalls/sinks are not sittable (Interact excludes CLUB OCEAN)"
   ],
   "emptyOrCrude": [
    "Restrooms are oversized (each ~41x20 studs = 12x6 m) for 5 stalls: 39-42% occupied, an empty 12-14-stud tiled square in the middle of each (women (-201.4,280.5), men (-202.7,300.5)); missing paper-towel dispensers, trash bins, tissue holders, hooks, floor drains, 흡연 금지 / 휴지는 휴지통에 signs, ceiling vents/downlights",
    "Corridor 76x18 studs is 23% occupied: long bare concrete walls with only signs and one extinguisher; largest empty square 14 studs at (-168.1,272.1); no bench, no water station, no phone-charging kiosk, no CCTV, no trash, no wall art lighting"
   ],
   "realWorld": [
    "Club restroom: queue line outside, dark tiles + mood lighting, mirrors with LED halo, 파우더룸 bench (women), paper towels + hand dryer, sanitary bin in stalls, 휴지 dispenser, 'CCTV 없음' privacy note, cleaning staff cart, mouthwash/hair products tray in upscale clubs",
    "Club corridor: dark walls with lightbox posters of resident DJs and events, neon slogans, 휴대폰 충전 대여 kiosk, water dispenser (생수), cigarette disposal near smoking room, CCTV, security staff, 비상구 유도등 + 소화기 every 20 m"
   ],
   "interactionIdeas": [
    "Sink: '손 씻기' (water particle in VesselSink + tap sound, hands animation); HandDryer: '건조하기' roar sound + air particle; RoundMirror: '거울 보기' close camera + hair-fix emote ('오늘도 예뻐 ♡' text pop)",
    "StallDoor: '들어가기/나가기' local swing + OccupancyLED red/green",
    "Corridor posters: '라인업 보기' card with tonight's DJ schedule; new wall-mounted phone-charging kiosk 'Charge' prompt -> toast (cosmetic); wall water dispenser '물 마시기' drink emote"
   ]
  },
  {
   "name": "CLUB OCEAN 광안 — Room2_HipHop (ROOM 2 · HIP-HOP)",
   "path": "Workspace.Gwangalli.club.CLUB OCEAN 광안.Room2_HipHop",
   "bounds": "(-156.7,6.8,264.4)..(-86.0,22.5,314.5)",
   "enterable": true,
   "rooms": [
    {
     "name": "Room 2 (PolishedConcrete 49x70 floor, concrete ceiling at 22.5, BrickWall on the z 264-266 side, stage + LED screen at the x -86 end)",
     "center": [
      -121.4,
      14.8,
      289.5
     ],
     "size": [
      70.7,
      15.5,
      50.1
     ],
     "floorY": 7,
     "ceilingY": 22.5
    }
   ],
   "props": [
    "PolishedConcrete floor, Ceiling, BackWall, StorageBehind (solid), BrickWall 70 long, 2 Ducts 69 long",
    "3 graffiti signs Sign_OCEAN CREW / Sign_BUSAN 051 / Sign_HIPHOP 4 LIFE = flat 14x5.5x0.1 SmoothPlastic panels with SurfaceGui text on the z 313.5 wall; Sign_HIP-HOP + 4 neon, Sign_♛ OCEAN, 12 HipHopStrip neon",
    "Room2Stage 18x2.5x12 Metal block + StageLED; Room2Desk + DeskTop + DeskPanel, 2 TurntableBase + platters/labels/tonearms, BattleMixer + Crossfader; ScreenHousing 22.6x9.1 + LEDScreen 22x8.5; 2 Room2Sub + cones, 2 Room2Top + woofers/horns; Room2Truss 40 + 4 drops; 4 MovingHead (Beam + SpotLight each)",
    "Room2Bar (69): bar counter 24 + top + back bar + shelf glow, 2 glass shelves, 52 bottles, 5 StoolPost + 5 Stool (Seat)",
    "Room2Sofa x3 (13 parts each, 4 Seats each) along z 310-313; 3 Wood LowTable 3.5x1.6x7; CypherRing Neon 11 dia + CypherFloor at (-122.3,7,289)"
   ],
   "gameplay": [
    "Zone_HipHop ClubZone (-156.7,6.5,264.4)..(-86,22.5,314.5); ClubLights Kind HipHopStrip x13 + MovingHead x4 (Room 'HipHop' show beams); 7 ClubNPC in Zone HipHop; DetailLOD ZoneLOD r 93",
    "21 Seats (5 bar stools + 12 sofa + ...) used for sitting; no prompts"
   ],
   "emptyOrCrude": [
    "40% occupied: the west half between the bar (z 265..277) and the sofas (z 310..313) is bare polished concrete — empty 24x24-stud square centred (-143.7,289.4); the cypher ring sits alone in the middle with nothing around it",
    "Graffiti is three flat plastic boards with typed text (no spray-paint texture/tags/drips, no stickers/posters wall); only one brick wall, other walls bare concrete; stage is a plain metal block without a front truss, barrier or monitors",
    "No standing tables / drink rails, no crowd barrier, no sneaker/merch wall, no corner speakers, no neon art, very low NPC count (7) for a 49x70 room"
   ],
   "realWorld": [
    "Korean hip-hop room / 힙합클럽 (홍대/서면): low ceiling with exposed ducts, graffiti murals and sticker-bombed walls, neon slogans, DJ booth with 2 turntables + battle mixer + laptop, MC mic stand, bass-heavy subs in corners, standing tables with drink rails along the walls, bar with soju/beer/highball, LED screen with visuals, cypher circle for freestyle/dance battles, chain-link or crate decor, sneakers/street-wear display in some venues"
   ],
   "interactionIdeas": [
    "CypherRing: '프리스타일 배틀' -> stand in the ring, beat-synced dance/rap emote rhythm prompt (client; like ClubDance), nearby NPCs cheer",
    "Turntables: '스크래치' -> scratch sound + platter spin (local), crossfader slide",
    "Stage mic: '마이크 잡기' hold-mic pose + echo voice line toast",
    "Graffiti wall: '태그 남기기' -> local spray decal of the player's name on the wall (client only)",
    "Bar: '메뉴 보기' local drink list (no server order)"
   ]
  },
  {
   "name": "CLUB OCEAN 광안 — VIPStair + OceanSkyLounge_2F (2F VIP lounge)",
   "path": "Workspace.Gwangalli.club.CLUB OCEAN 광안.{VIPStair, OceanSkyLounge_2F, Facade_Level2}",
   "bounds": "stair hall (-220.4,7.0,469.5)..(-179.1,33.9,488.1); lounge (-220.4,33.9,315.5)..(-177.8,46.9,488.1)",
   "enterable": true,
   "rooms": [
    {
     "name": "VIP stair hall (marble HallFloor, 44 Steps with StepLED, landing at 19.4-20.4, Zone_VIPStair)",
     "center": [
      -199.7,
      20.2,
      478.8
     ],
     "size": [
      41.3,
      26.5,
      18.6
     ],
     "floorY": 7,
     "ceilingY": 32.5
    },
    {
     "name": "Ocean Sky Lounge 2F (WoodPlanks floor 154x40, dark glass facade 29 panes on the 광안로 side x -219, L2Roof at 46.9, Zone_Lounge)",
     "center": [
      -199.1,
      40.4,
      401.8
     ],
     "size": [
      42.6,
      13,
      172.6
     ],
     "floorY": 33.9,
     "ceilingY": 46.9
    }
   ],
   "props": [
    "VIPStair (106): HallWall, HallBackWall, 44 marble Step + 44 StepLED, 2 StairSoffit, Landing 17.8x7, StairDivider, 4 RailPost + BrassRail, 2 WallHandrail, WallLED 40 long, Sign_OCEAN SKY LOUNGE ('2F · VIP ONLY · ROOFTOP ↑'), VIPHostPodium + PodiumLED at (-216.4,8.8,473.6)",
    "Lounge shell: 3 LoungeFloor, 3 TerraceGlass + 6 Mullion + DoorHead to the terrace, 2 CoveLED 154 long, 3 GlassBalustrade + HandRail + RailShoe (stair void), Sign_OCEAN SKY LOUNGE + 4 neon, 2 LoungeLightHost PointLights at y 46.3",
    "LoungeBar (171): BarCounter 42x3.9 Wood + Marble BarTop + UnderGlow (x -187.5..-184.3, z 386..428), BackCounter 46 + 8.7-high ShelfBacklight + 3 glass shelves with 149 Bottles, 7 BarStool Seats on posts; Bartender_005",
    "5 LoungeSofa along the windows (x -209..-204, z 325..451; 14 long, 4 Seats + 4 back cushions + 2 arms each = 20 Seats), 5 Marble LowTable 8x1.6x3 with Neon Candle + WineBottle, 2 Plants (pot/soil/leaves) at the ends"
   ],
   "gameplay": [
    "Zone_Lounge (-220.4,33.2,315.5)..(-176.8,46.9,488.1), Zone_VIPStair; wristband eject; the VIP stair hall's own street opening (x -221, z 471.4..479.6) is closed by ClubDoorBarrier_VIP, an invisible collider the client GwangalliClubShow Door module toggles; inside the club 'VIP ONLY' is only a sign (no extra server gate beyond the wristband); 2 ClubNPC Lounge rigs (Bartender_005, Guest_006); DetailLOD ZoneLOD OceanSkyLounge_2F r 150, VIPStair r 68",
    "ClubRanking ZONE_MODELS include OceanSkyLounge_2F/VIPStair (player 'in the club' check)"
   ],
   "emptyOrCrude": [
    "Lounge is huge (42x173 studs) and only 32% occupied: a ~12-stud-wide bare wooden aisle runs the full length between the sofas (x ≤ -204) and the bar (x ≥ -190); largest empty square 22 studs at (-194.1,439.5); the north part z 430..488 (beyond the bar) and z 315..384 (before the bar) hold only one sofa/table pair each",
    "Lighting is 2 PointLights + 2 cove strips for 7,300 sq studs: no pendants, no table lamps, no floor lights; ceiling is the bare L2Roof underside",
    "No rugs, armchairs, side tables, high tables, DJ corner/speakers, artwork, curtains, menu stands; only 2 NPCs -> feels deserted",
    "VIPHostPodium has no host NPC/tablet"
   ],
   "realWorld": [
    "Korean rooftop/sky lounge bar (광안대교 view): floor-to-ceiling glass with window-facing sofas and 2-person tables, low lounge chairs and ottomans, rugs, pendant/globe lights and candle lamps, long back-lit bar with bottle wall and 8-12 stools, a small DJ console with speakers, plants and partitions, menu stands with cocktail/wine/whisky lists, staff station, VIP host desk at the stair top with reservation tablet"
   ],
   "interactionIdeas": [
    "Window: '광안대교 야경 보기' -> camera pans to the bridge/sea view for a few seconds (local)",
    "Candle on LowTable: '촛불 켜기/끄기' toggle Neon + tiny PointLight (GwIndoorDim set)",
    "LoungeBar: '메뉴 보기' wine/cocktail list; bartender NPC '말 걸기' line (cosmetic toast)",
    "VIP host podium: '예약 확인' reading the player's booking; add a small DJ corner with '음악 볼륨' local mute/boost of ClubMusic"
   ]
  },
  {
   "name": "CLUB OCEAN 광안 — RooftopTerrace (OCEAN ROOFTOP)",
   "path": "Workspace.Gwangalli.club.CLUB OCEAN 광안.RooftopTerrace",
   "bounds": "(-217.8,34.1,263.5)..(-70.0,46.1,317.7)",
   "enterable": true,
   "rooms": [
    {
     "name": "Rooftop deck (2 WoodPlanks TerraceDeck 52x73, open sky, glass balustrade, Zone_Terrace)",
     "center": [
      -143.9,
      40,
      290.6
     ],
     "size": [
      147.8,
      12,
      54.2
     ],
     "floorY": 34.1,
     "ceilingY": 47.7
    }
   ],
   "props": [
    "2 TerraceDeck, 5 GlassBalustrade + HandRail + RailShoe (73 long each)",
    "5 Daybed (8x8 WoodPlanks base, Fabric mattress Seat, back cushion, 2 pillows) along z 265-274 at x -204, -182, -160, -138, -116",
    "2 TerraceSofa (14 long, 4 Seats) + 2 WoodPlanks CoffeeTable at x -193 and -129, z 292..307",
    "RooftopBar: only RooftopBarCounter 6x3.9x20 Wood + Marble BarTop + UnderGlow + Sign_ROOFTOP BAR (x -96.7..-76.6, z 307.3..313.6); Bartender_007 NPC stands behind it",
    "4 patio heaters (pole/base/reflector/Neon glow), 12 FestoonPole + 12 wires + 54 FestoonBulb, 4 metal Planters with palms (28 leaves), Sign_OCEAN ROOFTOP + 4 neon, 2 TerraceLightHost PointLights"
   ],
   "gameplay": [
    "Zone_Terrace ClubZone (-217.8,33.2,263.5)..(-70,47.7,317.7); 1 ClubNPC (Bartender_007); 13 Seats (5 daybed mattresses, 8 sofa seats); not in DetailLOD ZoneLOD list (RooftopTerrace has no LOD attr) so it is always loaded"
   ],
   "emptyOrCrude": [
    "25% occupied on 8,000 sq studs: largest empty square 24 studs at (-172.8,300.5); the whole centre strip z 280..305 between daybeds and the rail is bare decking; east half (x -110..-70) has only the bar",
    "RooftopBar is just a counter + top + glow strip (4 parts): no back bar/bottles, no stools, no ice well/taps/POS/glass rack, no menu",
    "No umbrellas/parasols/shade sails, no cocktail high tables, no lounge chairs, no floor uplights/lanterns, no speakers/DJ, no sea-view binoculars; 1 NPC only"
   ],
   "realWorld": [
    "Korean rooftop bar (광안리 루프탑): daybeds/cabanas with curtains, outdoor sofas with cushions, high tables with stools along the glass rail facing the bridge, parasols, festoon lights, heaters, an outdoor bar with back shelf, beer taps, ice wells, stools, menu board (하이볼/맥주/칵테일), speakers + small DJ booth, planters, 금연/흡연구역 signs, staff with trays"
   ],
   "interactionIdeas": [
    "Heater: '히터 켜기/끄기' toggles HeaterGlow + a warm PointLight (local)",
    "Rail binoculars (new, wall-mounted on the rail): '광안대교 망원경' zoomed camera",
    "Daybed: already a Seat — add '눕기' via the existing sit system is not available in the club (Interact excludes CLUB OCEAN), so a client 'lie down' pose on the daybed Seat is cosmetic",
    "RooftopBar: '메뉴 보기' local list; festoon string '조명 모드' cycles bulb colours (local)"
   ]
  }
 ],
 "notes": "I surveyed Workspace.Gwangalli.arcade (광안 게임랜드: 2,217 instances, 1,597 parts) and Workspace.Gwangalli.club (CLUB OCEAN 광안: 12,307 instances, 7,906 parts, 130 NPC rigs).\n\nORIENTATION: Both buildings are rotated about -89 degrees around Y (local X maps to world -Z). Every bound above is a world AABB computed from CFrame and Size. The arcade facade and entrance face +X onto 광안로; the Destination part is at (-298.6,7.1,433.2). The club facade faces -X (x about -219), with the door at z about 375.\n\nVERDICT: The arcade is the crude venue.\n- Its 75x79-stud hall is only 28% occupied, with a 34x34-stud empty square at (-345,461).\n- It has 25 boxy machines, no sound at all, fake restroom and exit doors, and a stair that ends against a wall.\n- The 셀프사진관 is empty apart from one pink box.\n- The 2F and 3F behind the three signs are a solid concrete block.\n\nThe club main room is already dense to AAA level: 75% occupied, 1,422 + 1,310 + 340 parts and a full show rig. Its weak spots are:\n- 2F Ocean Sky Lounge: 32% occupied, a 12-stud bare aisle for 170 studs, only 2 lights.\n- RooftopTerrace: 25% occupied; the rooftop bar is 4 parts.\n- Room 2 Hip-Hop: 40% occupied, a 24x24 bare concrete area, flat 'graffiti' boards.\n- The long Corridor (23%) and the oversized front restrooms.\n\nPLAYABLE TODAY:\n- Arcade: 펀치 (500원), 농구 x2 (1,000원), and the 팔씨름 table (the server builds it at the first free of 4 spots), all through 'ArcadePrompt' anchors in workspace.GwangalliPlay.Arcade.\n- The 12 claw machines are server-ready but unplayable. GwangalliGameplay/Interact implements clawStart, clawDrop and clawCancel over GwangalliRemotes.InteractRequest and tags PrizeDoor with GwInteract, but v7 has no client for them. Building that client is the highest-value arcade interaction.\n- Club: the paid door (ClubIDCheck prompts), '보틀 서비스' and '테이블 앉기' prompts on all 31 ClubTables, the ClubDance ring game, 124 Seats, shows and parades, and the ranking board.\n\nDO NOT TOUCH (names that must stay):\n- Arcade:\n  - 펀치기계 {PunchBase, PunchTower, PunchPad, ScoreDisplay Face/Text and Sub}\n  - BasketballMachine_1/2 {Rim x8, FrontCabinet, ScoreLED, FrontScore}\n  - LEDScreen (attr Messages, direct child)\n  - ClawMachine_NN {PrizeDoor, PrizeBed, Plush}\n  - ShopFloor and Counter (the ShopStaff 알바생 anchor in the photo shop)\n  - Destination\n  - StoolSeat, RacingSeat, SeatBase and Step (sittables)\n  - the 4 arm-table spots (-327,428), (-330,425), (-332,440), (-345,425), each kept as a clear 6x7 box\n  - 14 studs of wall-raycast space beside punch and basket for the wall boards\n- Club:\n  - everything tagged ClubLight, ClubFloorTile, ClubTable, ClubZone, ClubDoor, ClubIDCheck, ClubShowAnchor, ClubNPC or ClubRuntime\n  - ServePoint parts and Seats (ClubGuestSeat)\n  - ParadeRoute WP1-8\n  - the LED dance floor (nothing on it)\n  - the main room's south wall (ClubRankingBoard raycast)\n- The systems.json rule for the club allows only wall-mounted, non-colliding decor, and Interact excludes CLUB OCEAN from sittables.\n\nLOD:\n- Arcade machines are ZoneLOD (LODRadius 86-91); arcade NearDetail and ShopDetail are NearLOD.\n- Club rooms are ZoneLOD with these radii: Lobby 73, Tunnel 53, Restrooms 73, Corridor 82, VIPStair 68, Lounge 150, MainRoom 106, MainBar 63, TableFloor 94, HallRooms 108, Room2 93. RooftopTerrace has no LOD attr.\n- Hide crude parts per bld rule R3: LocalTransparencyModifier inside GwArrive roots, local Transparency otherwise. Never reparent or rename.\n\nPRIORITY BUILD LIST, ARCADE:\n1. Claw client plus a per-machine detail skin: LED-framed glass, side art, chute flap, bill acceptor, card reader, rating sticker.\n2. Fill the 34x34 hole with a row of 철권-style back-to-back 대전 pairs, a 펌프-style dance machine, a gun cabinet, 두더지/망치, a gacha wall, 2 코인노래방 booths and a key-master 경품 machine. Keep the 4 arm spots and 2.5-stud aisles clear.\n3. Re-skin the RetroCabinet, Racing, DanceBeat, Vending and CoinExchanger silhouettes: angled CRT bezel, coin door, bucket seat, arrow-shaped pads, bottle and can rows with lit buttons.\n4. Wall posters, 등급 stickers, blacklight carpet texture, ceiling speakers and sprinklers, hanging zone signs, SurfaceLights for machine screens, arcade BGM and attract sounds.\n5. Photo shop: 2-3 booths with curtains, kiosk, prop wall, vanity, sample-photo wall, ceiling.\n6. A stair-top landing with a closed 2F door and an 'OPEN 13:00' sign; prompts on the restroom and exit doors.\n\nPRIORITY BUILD LIST, CLUB (all non-colliding):\n- Lounge: pendants, rugs, armchairs, high tables.\n- Rooftop: back bar, stools, parasols, high tables.\n- Room 2: graffiti decals, standing rails, stage barrier.\n- Corridor: posters, charging kiosk, water station.\n- Restrooms: dispensers and bins.\n\nFiles:\n- Findings: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/arcade_club.json (this summary plus per-room occupancy).\n- Raw dumps, every instance with world pos, size, colour, material, attrs and tags: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/ac/arcade.txt and /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/ac/club.txt\n- Per-model compact summary: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/ac/club_c2.txt\n- Occupancy per room: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/ac/occ.json\n\nSources: one web search (gamemeca.com, e.g. https://www.gamemeca.com/view.php?gid=566126) confirmed that crane games sit at the entrance of Korean game centers and that Pump It Up and DDR are the staple dance games. The rest of the real-world checklists come from general knowledge."
}
```

## survey:bowling

```json
{
 "venues": [
  {
   "name": "1F 로비 · 리셉션 카운터 · 볼링화 대여 · 프로샵 · 포토존",
   "path": "Workspace.Gwangalli.bowling.실내.로비_카운터 (+ 1층_외벽 Floor_Lobby/AutoDoor_정문/ShopWindow, 실내.FitOut)",
   "bounds": "(253.6,6.75,442.7)-(341.6,28.68,469.2)",
   "enterable": true,
   "rooms": [
    {
     "name": "로비 전체 (Floor_Lobby Marble 40,40,46; 88x26)",
     "center": [
      297.6,
      17.7,
      456.2
     ],
     "size": [
      88,
      21.9,
      26
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    },
    {
     "name": "리셉션 카운터 + 직원 통로 + 신발장 벽 (직원은 z451~454, 손님은 z457~)",
     "center": [
      315.6,
      17.7,
      450
     ],
     "size": [
      28.5,
      21.9,
      14.5
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    },
    {
     "name": "정문 웰컴 / 대기 소파 존 (자동문 x258.8~270.8, z469.6)",
     "center": [
      270,
      17.7,
      460
     ],
     "size": [
      32,
      21.9,
      18
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    },
    {
     "name": "포토존 + 프로샵 (동쪽 끝, WallLiner x341.1)",
     "center": [
      336,
      17.7,
      456
     ],
     "size": [
      11,
      21.9,
      22
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    }
   ],
   "props": [
    "Reception x1 model: Body 28x3.15x2.7 WoodPlanks (28,22,44) + Marble Top 28.4x0.3x3.2 (y10.55 = ~1.15 m) + ToeKick + purple LedStrip — one box counter, nothing on the staff side",
    "POSScreen x2 2.2x1.5x0.12 slabs + POSStand x2 + Keyboard x2 + CustomerDisplay x2 ('결제 금액 4,500원') + CardTerminal x2 0.6x0.35x0.8 + ReceiptPrinter x1 + CounterBell x1 cylinder — flat slabs, readable but primitive",
    "Seat x2 staff stools (leather discs on StoolPost/StoolFoot)",
    "신발장 x1: CubbyBack 26.8x9.6x0.5 + Shelf x7 + Divider x9 + 6 size-label strips (220~285) + Shoe x88 (green Leather 0.4x0.42x0.95 boxes) + SoleHeel x44 — reads as a grid of identical green blocks",
    "Shoe x2 (red boxes on counter) + SockBasket x1 (fabric box) — no sock vending",
    "Sign_요금 안내 PRICE 26x6.6 board (일반 4,500 / 학생 4,000 / 경로 3,500 / 락볼링 5,500 / 볼링화 1,500 / 대관 45,000) + Sign_SHOES / Sign_볼링화 대여 neon outlines (NeonTube x12)",
    "Kiosk x1: KioskBody 1.1x4.2x0.5 + KioskBase + KioskScreen ('무인 접수 / 게임 선택 / ▶ 터치') — decorative, no script",
    "ShoeSterilizer x1 3.6x6.4x2.9 white box + SterilizerUV neon panel + sign — no doors/shelves",
    "ProShop x1: glass case 8.3x(2.6+3.8)x3.5 + glass shelf + ProBall x10 spheres + sign 'PRO SHOP · 볼링공 · 볼링화'",
    "WaitingSofa x1 (11 wide, 3 Seats, purple leather) + Plant x2 (pot + 2 leaf blobs)",
    "LEDHalo x3 ring lights 6 dia (SurfaceLight) hung on wires + Sign_WELCOME TO ROCK BOWL banner 12x3.2 on 2 wires",
    "Photo zone: Sign_광안리의 밤은 STRIKE! neon (NeonTube x4) + PhotoWing x8 neon bars + Sign_PHOTO ZONE; Sign_이달의 하이스코어 10x6.4 static text (1. 김*준 279 …)",
    "WallLiner x2 dark plaster (24,18,38) around the elevator hall corner; FitOut: SmokeDetector x3, CCTV x1, ExitSign x1",
    "직원 (볼링화 대여) NPC rig (block R15, skinned at runtime) at (316.7,9.9,452.5)",
    "Spot_bowl_shoes invisible 7x5.5x2.5 prompt host at (316.6,9.5,458.3)"
   ],
   "gameplay": [
    "VenueSpot Spot_bowl_shoes (attrs Spot=bowl_shoes, Label '볼링화 대여 · 1,500원'): VenueLife.setupSpot creates ProximityPrompt '볼링화 대여' (E, MaxDist 9) + 'GwangalliShoeColor' '색상 바꾸기 ▶' (R); pays V.SHOES.price, welds model 'GwangalliBowlingShoes' to the feet; re-trigger returns them. Keep name, tag VenueSpot, attrs, position; no collidable geometry between the customer side (z>457) and the spot.",
    "VenueStaff '직원 (볼링화 대여)' (Staff=shoe_clerk, Act=teller, HomeCF (316.72,9.88,452.54)) — VenueLife staff[], GwangalliStaticNpcSkins hides its body parts and stands an avatar clone in place; keep the aisle behind the counter (x302~329, z451~454) free.",
    "AutoDoor_정문 (tag AutoDoor, OpenRadius 14, leaves OpenOffset) — GwangalliDoors opens it; keep doorway + 14-stud radius path clear.",
    "Destination_락볼링클럽 (부지_주차장, (265.0,7.06,481.3), DisplayName '광안 락볼링클럽 (볼링장)') — taxi/nav/Journey (find radius 40) / Social invite target in front of the door.",
    "Interact sittable scan: WaitingSofa Seats and counter stool Seats get GwSittable.",
    "실내 is a ZoneLOD model (LODCenter 293.6,17.8,398.1, LODRadius 136) and the small props are NearLOD 'NearDetail' models (shown within ~100-120 studs, arrive hidden via GwArrive).",
    "GwangalliIndoorLight dims LEDHalo SurfaceLights (x0.55, Range<=18).",
    "KioskScreen, Sign_이달의 하이스코어, ProShop, ShoeSterilizer: no script references (safe to replace)."
   ],
   "emptyOrCrude": [
    "West half of the lobby x253.6~300, z446~462 (~46x16 studs) is bare dark marble: only a ceiling banner, 3 halo rings, one kiosk and 2 plants — no lane-status board, queue/ticket machine, trophy case, party zone, umbrella stand.",
    "Lobby is a 22-stud (~6.6 m) void under a flat dark ceiling slab (16,14,22) with no ceiling features (no grid, speakers, downlight array) above x253~300.",
    "Reception counter is one box: no cash drawer, phone, shoe-return bins, label printer, staff-side shelving; no lane-status monitors on the wall behind.",
    "Shoe wall: 88 identical green boxes; real rental shoes are two-tone with size numbers on the heel; no return basket / disinfectant spray.",
    "Shoe sterilizer is a closed box with a purple neon panel (no glass doors, racks, shoes inside).",
    "No 양말 자판기 (Korean alleys require socks) and no 손님 신발장 (key shoe lockers).",
    "Pro shop is one glass case with 10 spheres; no ball wall, bags, wrist supports, tapes, drill press, ball spinner, no clerk.",
    "Photo zone: neon bars on a dark wall; no printed backdrop, pin/ball props, ring light, floor sticker.",
    "Front shop windows (13.5 tall) show nothing behind them; no window vinyl / promo posters / event POP."
   ],
   "realWorld": [
    "프런트 카운터: POS 2~3대, 레인 배정 관리 PC, 카드단말기, 영수증 프린터, 진동벨/대기번호 호출기, 전화기, 현금함",
    "카운터 뒤 레인 현황 모니터 (레인별 사용중/대기/남은 게임) + 라이트박스 요금표 (일반·학생·경로·락볼링 심야·볼링화 대여·대관)",
    "볼링화 선반 (220~300mm 사이즈별 칸, 투톤 렌탈화, 뒤꿈치 사이즈 숫자) + 반납 바구니 + 소독 스프레이",
    "신발 살균건조기 (UV, 유리문, 칸별 선반)",
    "양말 자판기 / 양말 판매대 (1,000~2,000원)",
    "손님 신발 보관 열쇠 신발장",
    "무인 키오스크 (게임 수 선택·결제), 대기 소파 + 낮은 테이블, 정수기 + 종이컵, 휴대폰 충전기",
    "프로샵: 볼 진열 벽 (리액티브/우레탄 볼), 볼 백, 장갑·아대, 테이프, 로진백, 지공기(드릴 프레스), 볼 표면 재생기/스피너, 볼 클리너",
    "트로피 진열장, 퍼펙트(300) 명예의 전당 사진, 이달의 하이스코어, 동호회·리그 일정, 생일파티/단체 POP",
    "포토존: 네온 사인 + 대형 볼링핀 오브제 + 바닥 스티커 + 링라이트",
    "출입구: 자동문, 우산꽂이/우산 비닐, 손소독제, 바닥 매트, 영업시간·청소년 이용시간 안내, CCTV 안내",
    "조명: 로비는 밝은 다운라이트/간접조명, 레인 쪽은 어둡게 (락볼링 시간 블랙라이트)"
   ],
   "interactionIdeas": [
    "무인 접수 키오스크: '게임 접수' → lane picker UI (free lanes = BowlingLane models with Players==0) + waypoint arrow to the chosen lane",
    "레인 현황 보드 (new, behind counter): live 12-lane status (사용중/대기/게임 수) from Lane model attributes",
    "양말 자판기: '양말 사기 (1,000원)' → socks accessory; hint before renting shoes",
    "신발 살균기: '볼링화 살균' → glass doors open, UV glow 10 s, shoes swap",
    "손님 신발장: '신발 맡기기' → locker door swings, key number toast",
    "프로샵: '볼 구경하기' → colour/weight preview; '지공 맡기기' (drill animation) unlocks a personal ball colour for the Bowling picker",
    "카운터 벨: '벨 누르기' → ding + clerk turns to face the player",
    "포토존: '사진 찍기' → pose + flash (first visit popularity +1 like IS.PHOTO_SPOTS)",
    "이달의 하이스코어: render live rows from the Bowling server leaderboard instead of static text"
   ]
  },
  {
   "name": "1F 오락코너 (GAME ZONE)",
   "path": "Workspace.Gwangalli.bowling.실내.오락코너 (+ 1층_외벽 Floor_Arcade)",
   "bounds": "(231.6,6.75,444.0)-(253.6,28.68,470.2)",
   "enterable": true,
   "rooms": [
    {
     "name": "오락코너 (Floor_Arcade Carpet 38,26,62; 22x26)",
     "center": [
      242.6,
      17.7,
      457.2
     ],
     "size": [
      22,
      21.9,
      26
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    }
   ],
   "props": [
    "인형뽑기_1..3 x3 (each 24 parts): Cabinet 3.8x2.8x3.8 box, Glass 3.6x3.8 (t0.75), BackPanel, TopBox 3.8x1.4x3.9, Post x4, Gantry, Claw 0.8x0.4x0.6 box + ClawCable, Joystick + ball knob, CoinSlot neon, PrizeDoor, ChuteGlass, Plush x6 identical 0.9x0.8x0.9 cubes, TrimNeon, sign — boxy, 6 cube prizes, no claw prongs, no interior lights/mirrors",
    "펀치기계 x1: Cabinet 2.8x7.4x3 box, PunchPad 1.5x1.9x1.2 leather box (fixed; real pad swings down), ScreenHousing + LEDScreen (Messages 'PUNCH 872|HIGH 999|INSERT COIN'), ScoreDisplay, Sign_펀치왕",
    "농구게임 x1 (22 parts): FrontCabinet 6x2.8x2.2, Ramp wedge 5.6x1.6x6.2 + RampBase, SideNet x2 glass slabs, BackTower 6x11x0.6, Backboard 3.6x2.4 + BoardSquare, Hoop x6 bar segments, Basketball x5 spheres, LEDScreen ('BASKET 00|TIME 40|HI-SCORE 312'), TrimNeon",
    "에어하키 x1: HockeyBody 5.2x2.4x6.6 box, HockeyTop, HockeyRail x2 neon, Mallet x2 cylinders, Puck, CenterLine — no goals/score/legs",
    "인생사진 x1: BoothBody 6x8x4.4 white box + Curtain slab + sign 'PHOTO · 4컷' — not enterable, no camera/screen",
    "CoinChanger x1 1.4x5.6x2 metal box + Sign_동전교환",
    "Board_punch (BoardFrame 3.7x2.9 + BoardFace) '🥊 오늘의 펀치왕' rows on the west wall",
    "Sign_GAME ZONE + NeonTube x4; ArcadeLight x1 (PointLight); FireExtinguisher + sign (FitOut NearDetail)",
    "Walls: SideWall/WallPanel purple plaster (38,26,62) with side windows on x232"
   ],
   "gameplay": [
    "Spot_bowl_punch (VenueSpot, Spot=bowl_punch, Label '펀치왕 · 1회 500원', invisible 2.8x6x2.4 at (237.0,9.8,450.4)): VenueLife prompt '펀치! (500원)' → punch(): score, GwVenueAct 'punch', updates the machine's LEDScreen/ScoreDisplay and VenueBoard 'punch'.",
    "Board_punch/BoardFace (tag VenueBoard, Board=punch, SurfaceGui 'BoardGui' TextLabels Row1..Row5) — server writes rows; keep names.",
    "농구게임: Play.Arcade.World finds model '농구게임' under bowling/실내/오락코너 (Arcade.MACHINES id bw_basket, led=true), reads FrontCabinet / Hoop / LEDScreen (writes Messages 'BASKET nn|TIME nn|HI-SCORE nnn') and builds its own invisible prompt anchor in workspace.GwangalliPlay.Arcade — do not rename/move these parts.",
    "인형뽑기_1..3 are NOT playable: Interact.tagExisting only tags models matching ^ClawMachine_%d+$ (with a PrizeDoor child) as kind 'claw' (IS.CLAW price, claw_play pose).",
    "에어하키 / 인생사진 / CoinChanger: no script references.",
    "Pocha NPC line mentions the 오락코너 basketball high score 300; Journey 'arcade.play' is shared by bowling/billiards/minigames."
   ],
   "emptyOrCrude": [
    "Only 7 machines in 22x26 studs; the window side x237~248, z465~469 and the centre aisle are empty carpet.",
    "Claw machines: identical cube plush, box claw, no LED marquee, no prize pile.",
    "Punch pad is a fixed box (real boxing machines have a fold-down padded target).",
    "Air hockey has no goal slots, score LEDs, legs; photo booth is a closed box.",
    "No rhythm/dance (펌프), racing, gun or fighting cabinets; no prize/redemption counter; no token cups.",
    "Ceiling dark and flat with a single PointLight; carpet single colour (no UV-reactive pattern)."
   ],
   "realWorld": [
    "인형뽑기 크레인 3~6대 (LED 마키, 거울 내벽, 인형 30~50개, 경품 출구, 집게 3발)",
    "펀치기 (접히는 샌드백 패드 + 점수 LED + 랭킹), 농구 게임 2연대 (망, 카운트다운 LED), 에어하키 (양쪽 골 + 점수판)",
    "리듬게임: 펌프 잇 업 / 댄스러시, 유비트, 태고의 달인; 레이싱 시트형, 건슈팅, 철권 대전 기체",
    "인생네컷/스티커 사진 부스 (내부 카메라 + 터치스크린 + 배경 + 소품 바구니 + 프린터 출구)",
    "동전교환기 (지폐→500원), 경품 교환 카운터",
    "형광 카펫, 천장 LED 바/네온, 청소년 이용시간 안내, CCTV"
   ],
   "interactionIdeas": [
    "인형뽑기: '인형뽑기 (500원)' → joystick/drop claw mini game → plush held prop (alias these to Interact's claw flow or a client copy)",
    "에어하키: '에어하키 (1,000원)' 1v1 client-physics puck, goal LEDs",
    "인생사진: '사진 찍기' → step into the booth, 4-shot countdown flashes, printed 4컷 photo held prop + popularity",
    "동전교환기: '동전 교환' → cash to token counter UI with coin clink",
    "리듬게임 (new cabinet): '펌프 하기' → arrow tap mini game with score board",
    "펀치기계: animate the pad folding down when the prompt fires"
   ]
  },
  {
   "name": "1F 라운지 · DJ 부스",
   "path": "Workspace.Gwangalli.bowling.실내.라운지 (+ 1층_외벽 Floor_Lounge, 실내.Partition RailGlass)",
   "bounds": "(244.0,6.75,395.4)-(284.4,28.68,443.9)",
   "enterable": true,
   "rooms": [
    {
     "name": "라운지 (Floor_Lounge WoodPlanks 70,46,34; open to bar x231~244 and lobby z>443)",
     "center": [
      264.2,
      17.7,
      419.6
     ],
     "size": [
      40.4,
      21.9,
      48.5
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    },
    {
     "name": "DJ 부스 (DJPlatform y7.2~7.6)",
     "center": [
      265.7,
      17.7,
      400.7
     ],
     "size": [
      20.6,
      21.9,
      10.6
     ],
     "floorY": 7.6,
     "ceilingY": 28.68
    },
    {
     "name": "CloudCeiling 하부 소파 존 (lowered cloud y21.6)",
     "center": [
      252.1,
      14.2,
      426
     ],
     "size": [
      12,
      14.9,
      30
     ],
     "floorY": 6.75,
     "ceilingY": 21.6
    }
   ],
   "props": [
    "LoungeSofa x3 (8 wide; Plinth, Base, Backrest 8x3.9x0.8, Seat x2, Arm x2, BackCushion x2; purple leather) at x247~251, z412~440 facing +x",
    "LowTable x3 (WoodPlanks 3.4x0.25x4.4 on a 0.6 post) with BeerGlass x3, Cocktail x3, FriesBasket x3",
    "Pouf x6 teal fabric cylinders 1.4x1.8x1.8 (+ invisible Seat on each)",
    "HighLedge 2.55x0.25x30 along the lane rail x282.4 + LedgeBracket x3 + 7 bar stools (StoolPost/StoolFoot + invisible Seat)",
    "CloudCeiling 12x0.4x30 WoodPlanks at y21.8 + CloudLED x4 + CloudDownlight (SurfaceLight) + CloudHanger x4",
    "MirrorBall 2.4 Foil sphere + rod; PinSpot x2",
    "DJ부스: DJPlatform 16x0.8x9.4 DiamondPlate + PlatformNeon, DJDesk 10.2x3.6x2, DeckBody x2 + Platter x2 + PlatterLabel x2, Mixer + MixerLEDs, Laptop, PASpeaker x2 2.2x6x2.2 + Woofer x4, ScreenHousing/LEDScreen x2 (9.4x3.2 desk front, 15x8 wall; Messages 'DJ|COSMIC|ROCK BOWL|PARTY'), DJLight (PointLight)",
    "Board_bowling (BoardFrame 7.3x4.9 + BoardFace '🎳 오늘의 볼링 TOP 5') on the partition at (283.2,16.8,400.5)",
    "Partition: RailBase/RailGlass/RailCap/RailNeon 32 long between lounge and lanes; PartitionWall 0.8x21.9x74 dark purple + WallNeon (BowlingCosmic)"
   ],
   "gameplay": [
    "Board_bowling/BoardFace (tag VenueBoard, Board=bowling): VenueLife.setBoard('bowling') writes Row1..Row5 of SurfaceGui 'BoardGui' from LastBowlingScore submissions — keep name/tag/attr.",
    "Pouf/stool invisible Seats and sofa Seats → Interact GwSittable (sit/lean).",
    "WallNeon tagged BowlingCosmic → BowlingClient hue-cycles it while the camera is in the lane hall.",
    "DJ booth, mirror ball, LEDScreen: no script interaction (LEDScreen Messages are cycled by the generic LEDScreen tag)."
   ],
   "emptyOrCrude": [
    "The centre x255~280, z408~440 (~25x32 studs) is empty wood floor under a static mirror ball — no rugs, standing tables, floor lighting.",
    "Sofas/tables are boxes; drinks are cylinders; no cushions variety, lamps, wall art or TV on the west wall (WallPanel planks only).",
    "DJ decks are flat boxes; no headphones, cables, monitor speakers, truss/moving heads/laser/fog over the booth; PA speakers are plain boxes.",
    "Mirror ball does not spin or cast light spots; PinSpots emit nothing."
   ],
   "realWorld": [
    "라운지 소파 + 낮은 테이블 + 바 높이 스탠딩 테이블, 쿠션, 러그, 사이드 램프",
    "대형 LED 스크린/프로젝터 (뮤비·스포츠 중계), 네온 아트, 볼링 테마 그래픽 월",
    "DJ 부스: CDJ 2대 + 믹서, 헤드폰, 노트북 스탠드, 모니터 스피커, 전면 LED 패널, 상부 트러스 + 무빙라이트·레이저·포그머신",
    "미러볼 + 핀스폿 (반사 점 회전), 클럽 음향 (서브우퍼)",
    "QR 주문 메뉴판, 테이블 번호, 충전 스테이션, 코트 후크"
   ],
   "interactionIdeas": [
    "DJ 부스: 'DJ 하기' → genre/song select for the hall BGM, platter scratch animation, cosmic light tempo change (BowlingCosmic speed)",
    "미러볼: '조명 켜기' → spin + moving light dots (client)",
    "라운지 테이블: '메뉴 보기' → order bar/snack items delivered to the table (VenueLife order with a lounge spot)",
    "하이레저 스툴: sit with a camera framing toward the lanes (spectate)",
    "대형 스크린: '채널 바꾸기' (뮤비 / 야구 중계 / 볼링 하이라이트)"
   ]
  },
  {
   "name": "1F ROCK & BOWL BAR",
   "path": "Workspace.Gwangalli.bowling.실내.ROCK_BOWL_BAR",
   "bounds": "(231.4,6.75,403.9)-(243.5,28.68,440.3)",
   "enterable": true,
   "rooms": [
    {
     "name": "바 (백바 x231.4~234 | 바텐더 통로 x234~237 | 카운터 x237~240.8 | 스툴 x241~243.5)",
     "center": [
      237.4,
      17.7,
      422.1
     ],
     "size": [
      12.1,
      21.9,
      36.4
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    }
   ],
   "props": [
    "BarCounter model: Body 32x3.15x2.7 dark WoodPlanks + Marble Top 32.4x0.3x3.2 + ToeKick + pink LedStrip — single box, no foot rail",
    "BackBarCabinet 1.9x3.4x30 + BackBarTop + BarMirror 0.15x7.6x29 + GlassShelf x3 (29 long) + ShelfGlow x3 purple neon + Bottle x36 glass cylinders (3 sizes, same shape)",
    "TapColumn x2 + TapBar x2 + Faucet x8 + TapHandle x8 (yellow) + DripTray x2",
    "SojuBottle x3, BeerGlass x2 + Foam x2, Cocktail x3 + Stem x3, Shaker x1 on the counter",
    "Seat x9 bar stools (leather 1.3 disc + StoolPost/StoolFoot)",
    "PendantShade x5 (neon cylinders 1x0.9) on 9.9-long cords (2 PointLights)",
    "Fridge (2-door glass cooler at x231.6~235.5, z404.4~409.7): Body x2, Kick x2, SidePanel x4, WireShelf x6, FridgeDoor x2 glass, FridgeGlow x2, FridgeLamp x2, Bottle x24 identical brown cylinders",
    "Signs: Sign_ROCK & BOWL BAR (neon outline), Sign_DRINK menu 6.2x3.2 (생맥주 500cc 5,000 / 하이볼 8,000 / 칵테일 9,000 / 소주·맥주 5,000), Sign_BAR · 생맥주 · 칵테일 · 하이볼 on the counter front"
   ],
   "gameplay": [
    "No staff: ShopStaff only uses a BasePart named BarCounter/BackBar/POS... as a loose anchor; here BarCounter is a Model (parts Body/Top/...) and there is no ShopFloor → no bartender spawns.",
    "No purchase spot: the VenueLife 'bowling' menu (tteokbokki, eomuk, fries, bowl_cola) exists only at Spot_bowl_snack in 분식코너; drinks on Sign_DRINK cannot be bought.",
    "Seat x9 → Interact GwSittable.",
    "If a builder adds a BasePart named 'BarCounter' or a ShopCounter tag, ShopStaff would start spawning a 바텐더 there (kind pub) — use that deliberately or avoid the names."
   ],
   "emptyOrCrude": [
    "Unattended bar with nothing to buy.",
    "Back bar: flat mirror + 36 identical cylinders; no label/shape variety, glass racks, ice well, sink, speed rail, POS, kegs/CO2, branded draft tower, coasters, napkins.",
    "Fridge holds 24 identical brown cylinders (no soju/beer brands).",
    "Pendants hang 10 studs below a flat 28.7 ceiling with no bar canopy/soffit."
   ],
   "realWorld": [
    "생맥주 디스펜서 (카스/테라/켈리 탭 핸들 + 브랜드 타워), 맥주잔 냉동고",
    "하이볼 타워, 칵테일 툴 (셰이커·지거·스트레이너·바스푼), 제빙기, 싱크, 글라스 렉, 컵 워셔",
    "백바: 위스키·보드카·진·리큐르 병 (다양한 형태/라벨) + LED 선반 조명; 소주/맥주 냉장 쇼케이스 (참이슬·처음처럼·카스)",
    "바 POS + 카드단말기, 진동벨, 안주 메뉴판 (치킨, 감자튀김, 나쵸, 소떡소떡, 마른안주)",
    "바 체어 + 발판 레일, 코스터, 냅킨·빨대 통, 안주 접시",
    "바텐더 (블랙 유니폼), 청소년 주류 판매 금지 안내"
   ],
   "interactionIdeas": [
    "바텐더 NPC + '주문하기' → drinks menu (생맥주/하이볼/칵테일/콜라, non-alcoholic variants) → held cup + drink pose",
    "생맥주 탭: '맥주 따르기' (알바 mode) → pour animation with foam fill",
    "냉장고: '냉장고 열기' → glass door swings, pick a bottle held prop",
    "셰이커: '칵테일 만들기' shake-rhythm mini game",
    "바 스툴: sit facing the bar, '건배' emote with neighbours"
   ]
  },
  {
   "name": "1F 분식코너 (ROCK & BOWL 분식)",
   "path": "Workspace.Gwangalli.bowling.실내.분식코너",
   "bounds": "(231.0,6.75,369.0)-(283.0,28.68,396.0)",
   "enterable": true,
   "rooms": [
    {
     "name": "주방 (카운터 뒤, KitchenCounter x231.3~233.5)",
     "center": [
      233.6,
      17.7,
      384.8
     ],
     "size": [
      5.3,
      21.9,
      19
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    },
    {
     "name": "주문 카운터 + 픽업대 (SnackCounter x235.5~238.6, PickupShelf x239.5~242.1)",
     "center": [
      238.8,
      17.7,
      385.2
     ],
     "size": [
      6.6,
      21.9,
      19
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    },
    {
     "name": "식사 홀 (SnackTable 3세트)",
     "center": [
      260,
      17.7,
      382.8
     ],
     "size": [
      32,
      21.9,
      10
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    },
    {
     "name": "분식코너 전체 (Floor_Back CeramicTiles 150,146,140)",
     "center": [
      257,
      17.7,
      382.5
     ],
     "size": [
      52,
      21.9,
      27
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    }
   ],
   "props": [
    "KitchenCounter 2.3x3.4x19 steel + Backsplash ceramic 0.15x5.2x19 + WallShelf 18 + Container x8 (red cylinders)",
    "Fryer + FryerOil slab, Microwave box, RiceCooker cylinder",
    "SnackCounter: Body 18x2.95x2.2 red WoodPlanks + steel Top + LedStrip",
    "TteokbokkiPan 1.9x0.4x4.5 + Tteokbokki red slab 1.5x0.16x4.1 + RiceCake x6; EomukPot + Broth + Skewer x5; WarmerGlass + Twigim x6",
    "PickupShelf 2.4x3.3x4 + Marble PickupTop + Sign_픽업 PICK-UP",
    "Sign_분식 SNACK 17x5 menu board on 2 wires (떡볶이 4,000 · 순대 4,000 · 튀김 3,500 / 어묵 2,000 · 김밥 3,000 · 라면 4,500 / 치킨 18,000 · 감자튀김 4,000 · 생맥주 5,000) + Sign_떡볶이 neon",
    "SnackTable x3 (TableTop 4x0.2x4 + pedestal) with 12 chairs (Seat 1.7 + ChairBack + 4 legs, red fabric)",
    "SnackLight 4x4 (SurfaceLight), FireExtinguisher, Sign_비상구 (exit at x230.2 z371.9)",
    "분식 이모 NPC rig (apron, bandana) at (234.8,9.5,390.7)"
   ],
   "gameplay": [
    "Spot_bowl_snack (VenueSpot, Spot=bowl_snack, Label 'ROCK & BOWL 분식 · 떡볶이 · 어묵 · 감자튀김', invisible 2.7x5.5x14 at (239.9,9.5,386.2), PickupCF (240.77,10.16,377.48)): prompt '분식 주문' → VenueEvent 'menu' (items tteokbokki, eomuk, fries, bowl_cola); VenueLife.order requires the player within 22 studs; after def.prep the food prop is placed at PickupCF and further orders stack +1.3 studs along its X axis (= +z) → keep PickupTop (x239.5~242.1, z374.3~378.5, top y10.15) clear; the 3rd order lands at z~380, past the shelf.",
    "VenueStaff '분식 이모' (Staff=bowl_cook, Act=cook, HomeCF (234.79,9.52,390.68)) — skinned by GwangalliStaticNpcSkins ('분식'/'이모' → apron, f); keep x233.5~236 behind the counter free.",
    "Chair Seats x12 → Interact sittables; eating plays GwPose eat after pickup.",
    "GwangalliVenues/Spots client: bowling menu title '🌶️ ROCK & BOWL 분식' / '주문 후 픽업대에서 받아 가세요'."
   ],
   "emptyOrCrude": [
    "No exhaust hood over the fryer/pans, no sink, fridge, prep table, gas burners, gimbap station, ramen cooker; food is flat coloured slabs.",
    "No POS/kiosk/pager at the counter; menu is one 17x5 panel without photos.",
    "Only 3 tables x 4 chairs in a 52x27 zone; x246~283 at z387~396 and z369~378 are empty tile; no self-bar (단무지·물·수저), napkins, condiments, trash/recycling, tray return.",
    "Snack bar sits under the 28.7 dark ceiling with one light; no lightbox soffit."
   ],
   "realWorld": [
    "메뉴 라이트박스 (사진 + 가격), 키오스크 주문 + 진동벨, 픽업대 + 식기 반납대",
    "국물 떡볶이 대형 철판, 어묵 사각 통 (꼬치 + 국자 + 종이컵), 튀김 진열대 + 튀김기, 순대 찜기, 김밥 말이대, 즉석라면 조리기",
    "후드 + 덕트, 2조 싱크, 업소용 4도어 냉장고, 음료 쇼케이스",
    "셀프바: 단무지, 물, 종이컵, 수저통, 냅킨, 이쑤시개",
    "스테인리스/원목 테이블 + 의자, 분리수거함"
   ],
   "interactionIdeas": [
    "키오스크 (new): '주문하기' → same VenueLife menu + 진동벨 held prop that buzzes when the food lands at PickupCF",
    "어묵 통: '어묵 꼬치 집기 (1,000원)' self-serve skewer + eat pose; '국물 뜨기' paper cup",
    "셀프바: '단무지/물 가져오기' small held props",
    "반납대: '식기 반납' after eating → tidy table + small happiness",
    "떡볶이 철판 (알바 mode): '휘젓기' cook animation"
   ]
  },
  {
   "name": "1F 화장실 (남/여) + 사무실 · 창고",
   "path": "Workspace.Gwangalli.bowling.실내.화장실 (+ 1층_외벽 RollerShutter/BackWall, Floor_Back)",
   "bounds": "(230.4,6.75,328.9)-(254.6,18.0,368.7)",
   "enterable": true,
   "rooms": [
    {
     "name": "남자 화장실 (entrance gap x253.7, z362~365.5)",
     "center": [
      242.3,
      12.2,
      362.2
     ],
     "size": [
      22.5,
      10.85,
      10.9
     ],
     "floorY": 6.75,
     "ceilingY": 17.6
    },
    {
     "name": "여자 화장실 (entrance gap z346.5~350)",
     "center": [
      242.2,
      12.2,
      350.2
     ],
     "size": [
      22.4,
      10.85,
      10.9
     ],
     "floorY": 6.75,
     "ceilingY": 17.6
    },
    {
     "name": "사무실 · 창고 STAFF ONLY (StaffDoor x253.6 z338; rear RollerShutter x235.5~249.5 to the loading dock)",
     "center": [
      241.8,
      12.2,
      336.3
     ],
     "size": [
      22.8,
      10.85,
      14.7
     ],
     "floorY": 6.75,
     "ceilingY": 17.6
    }
   ],
   "props": [
    "Wall x10 + Divider (plaster 226,222,214), Ceiling x2 at y17.6~18.0",
    "PrivacyScreen x2 (maze entrance walls 0.6x7.4x6.5)",
    "Wainscot x2 ceramic 4.5 high on the x231 wall",
    "SinkCounter x4 marble 2.8x0.5x1.8 + Basin x4 metal discs (no taps) + Mirror x2 8x4",
    "StallPanel x6 + StallDoor x4 (purple plastic slabs) → 2 stalls per room",
    "Toilet x4 marble boxes 1.3x1.5x1.2",
    "Signs: 남자 화장실 MEN, 여자 화장실 WOMEN, 사무실 · STAFF ONLY, 화장실 RESTROOM → (hung on 10.7 wires at z368.9)",
    "StaffDoor WoodPlanks slab 0.6x7.8x3.7 (not a door model)"
   ],
   "gameplay": [
    "No scripts, tags or prompts reference these rooms; StaffDoor is a static part (no GwangalliDoors tag).",
    "Exit door ExitDoor_비상구 at (230.2,10.6,371.9) and RollerShutter/'물품 반입구 · 하역장' sign outside are exterior decor."
   ],
   "emptyOrCrude": [
    "No faucets, soap, paper towels/hand dryer, trash bins; basins are flat discs on boxes.",
    "No urinals in the men's room.",
    "Toilets are marble boxes (no bowl/seat/tank), no paper holders, bidet, hooks; stall doors flat slabs with no lock indicator.",
    "No ceiling light inside either room (ceiling drops to y17.6; nearest light is CorridorLight at y28.5 outside) → dark; no exhaust fan.",
    "Uses the corridor's big tile floor slab; no wet-area tile/drain.",
    "Office/창고 22.8x14.7 is completely empty (no desk, PC, CCTV monitors, safe, shelving, stock boxes); the loading-dock shutter opens into nothing."
   ],
   "realWorld": [
    "남자: 소변기 3~4 + 칸막이, 양변기 칸 2~3 (휴지걸이, 사용중 표시 잠금, 옷걸이), 세면대 (센서 수전 + 거울 + 핸드솝), 핸드드라이어/페이퍼타올, 휴지통",
    "여자: 양변기 칸 3~4 + 위생용품 수거함, 파우더 존 (거울 + 선반), 기저귀 교환대",
    "공통: 타일 바닥 + 배수구, 벽 타일, 매입 천장등 + 환풍기, 여성 안심 비상벨, 미로형 입구, 청소 점검표",
    "사무실: 책상 + PC, CCTV 분할 모니터, 금고, 레인 관리 서버/스코어 시스템 랙, 서류장, 볼링화·핀 재고 박스, 직원 사물함, 하역 카트"
   ],
   "interactionIdeas": [
    "세면대: '손 씻기' → water particle + sound",
    "핸드드라이어: '손 말리기' blow sound",
    "칸 문: '들어가기/잠그기' → door swings, red 사용중 indicator; '물 내리기' flush sound",
    "거울: '옷매무새 확인' → mirror camera showing the outfit",
    "사무실 (알바/staff): 'CCTV 보기' lane-hall camera view; '정산하기' mini task"
   ]
  },
  {
   "name": "1F 복도 (사물함 · 자판기 · 정수기) + 기계실 통로",
   "path": "Workspace.Gwangalli.bowling.실내.복도, 실내.기계실_통로, 실내.Partition",
   "bounds": "(253.9,6.75,327.6)-(353.7,28.68,369.0)",
   "enterable": true,
   "rooms": [
    {
     "name": "복도 (restroom/office side x254.5, partition x283)",
     "center": [
      268.7,
      17.7,
      348.9
     ],
     "size": [
      28.5,
      21.9,
      40.2
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    },
    {
     "name": "기계실 통로 (behind pinsetters; StaffDoor (280.3,10.6,329.8), ServiceDoor (333.4,10.6,326.6))",
     "center": [
      318.6,
      17.7,
      333.5
     ],
     "size": [
      69,
      21.9,
      11.6
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    }
   ],
   "props": [
    "Lockers x1 1.5x7.2x20 single metal box (60,90,150) + LockerSeam x12 strips (fake 10x2 doors) + Sign_사물함 LOCKER",
    "VendingMachine x2 (Body 3.4x6.2x2.6 red + Display neon (NightNeon) + Can x15 flat 0.4x0.8x0.2 slabs each)",
    "WaterPurifier 1.8x4.6x1.6 + CupDispenser glass",
    "FireExtinguisher, Sign_비상구, CorridorLight 4x4 (SurfaceLight)",
    "기계실: Workbench 10x3.2x2.2 metal box, PinCart 4x2.8x3, SparePin x6 cylinders, ServiceLight (SurfaceLight), Sign_비상구",
    "Partition: PartitionWall 0.8x21.9x74 (34,26,56) + 2 short pieces, WallNeon 58 long (BowlingCosmic), StaffDoor metal slab + Sign_STAFF ONLY"
   ],
   "gameplay": [
    "None interactive: Interact builds its own vending props (workspace.GwangalliInteract) and does not tag these VendingMachine models; lockers are not VenueSpots.",
    "WallNeon tag BowlingCosmic (BowlingClient hue cycle)."
   ],
   "emptyOrCrude": [
    "Corridor 28x40 is mostly bare tile; one wall has vending + purifier, the other a single locker slab.",
    "Lockers have no doors/numbers/keys/handles; vending cans are flat slabs, no buttons/coin slot/pickup bin.",
    "Machine passage: workbench box + cart; no pinsetter backs (pinsetters are single boxes), tool board, lane-conditioning machine, ball-return track, parts shelving."
   ],
   "realWorld": [
    "유료 보관함 (열쇠/번호키 100~500원), 음료 자판기 (캔/페트 + 커피), 정수기 + 종이컵, 소화기, 비상구 유도등, 청소도구함",
    "기계실: 핀세터 뒷면 (벨트·엘리베이터·핀 디스트리뷰터), 레인 정비기 (Kegel 오일 머신), 공구 보드, 부품 선반, 핀 카트, 작업등, '작업 중 출입금지' 표지"
   ],
   "interactionIdeas": [
    "사물함: '사물함 사용 (500원)' → door opens with number; store/retrieve",
    "자판기: '음료 뽑기' → drink picker, can drops (reuse Interact vending purchase)",
    "정수기: '물 마시기' (like gym_water)",
    "기계실 (알바/점검): '핀세터 점검' fix-jam mini task when a lane stalls"
   ]
  },
  {
   "name": "1F 레인홀 (12 레인 · 컨코스 · 핀세터)",
   "path": "Workspace.Gwangalli.bowling.볼링레인 (Lane_01..12, Pair_01_02..11_12, Cappings, MaskingWall, Pit) + 실내.레인홀_조명 + 1층_외벽 Floor_LaneHall/Floor_Concourse/HallLiner",
   "bounds": "(283.2,6.5,335.4)-(355.1,28.68,443.0)",
   "enterable": true,
   "rooms": [
    {
     "name": "레인 (approach z407~423 → pin deck z343~347; lanes x284~354)",
     "center": [
      319,
      17.7,
      379.2
     ],
     "size": [
      70.4,
      21.9,
      88
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    },
    {
     "name": "컨코스 · 세티 (ball returns z420~425, settees z428~434, ball racks z434~442; Floor_Concourse Carpet 30,22,52)",
     "center": [
      319.9,
      17.7,
      432.9
     ],
     "size": [
      70.4,
      21.9,
      20
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    },
    {
     "name": "핀세터 · 피트 (behind MaskingWall z347.3, masking y16.5~28.7)",
     "center": [
      318,
      17.7,
      341
     ],
     "size": [
      70,
      21.9,
      13
     ],
     "floorY": 6.75,
     "ceilingY": 28.68
    }
   ],
   "props": [
    "Lane_01..12 (BowlingLane, ~170 inst each): Approach 6.3/5.7x0.75x16 + LaneBed 3.5x0.75x60.41 + PinDeck 3.5x3.65 WoodPlanks (214,172,118), Gutter x2 + GutterLip x2, BumperL/R (yellow, retracted), FoulLine, ApproachDot x12, LaneDot x8, Arrow x14 tiny slabs, invisible FoulBarrier/LaneFrame/PromptAnchor/BallRest, Sweep bar, PitCurtain, Pinsetter (one 4.8x5.7x11.44 metal box) + PinsetterDeck + PinsetterTurret (red box), Sign_N lane number, MonitorScreen_NN 5.1x2.95 slab (SurfaceGui LaneMonitor_NN), Pins Pin_1..10 (Collider + box Belly + Foot/Neck cylinders + box Head + 2 Stripes), Ball (BallCore sphere + 3 finger-hole discs)",
    "Pair x6: Sign_ROCK BOWL / GWANGALLI masking panel 11.4x4.3, PinLight (SurfaceLight), BallReturnStand/Base/Hood (cylinder)/Mouth/BallRail x2/DryerGrille/ReturnNeon, MonitorPole 9.8 + MonitorBar + 2 mounts, 6 settee seats (SetteeBase/Seat/Back/Cap/Neon, purple leather) in a line, round TableTop + leg + foot + Beer/Cocktail/SnackBasket, ConsolePost + ScoreConsole 1.5x0.12x1 (ConsoleGui 'LANE 1 · 2'), BallRack (RackFoot, 2 ends, 2 trays, HouseBall x12 with Lb attr, BallRackPrompt, sign 'HOUSE BALL 8–16 LB')",
    "Cappings: Capping x13, Kickback x13, CosmicStrip x13, KickbackNeon x13, FoulSensor x13, StepNeon 69.6",
    "MaskingWall 69.6x12.15x0.6 + MaskingEnd x2 + CosmicPlanet x6 + CosmicStar x10 + CosmicRing + Sign_STRIKE ZONE + HallLeaderboard 15x4.8 (LeaderboardGui) + LeaderboardEdge",
    "Pit: PitFloor rubber 69.6x3.4 + PitBack fabric",
    "레인홀_조명: LEDStrip x8 (69.6 long, BowlingCosmic), BlackLight x3, SetteeLight x3 (SurfaceLight), Duct x3 96 long, Speaker x3 + cones, MuralPlanet x4, MuralZigzag x12, Sign_Rock & Bowl neon; Truss: TrussChord x2, TrussLace x10, TrussHanger x2, MovingHead x7 + lens + yoke",
    "HallLiner (east wall 22,18,34) + MuralNeon x2 (65 long); BackLiner x3 (z328)"
   ],
   "gameplay": [
    "ServerScriptService.Bowling: CollectionService 'BowlingLane' models; uses LaneFrame (attrs LaneLength 60.96, LaneWidth 3.5, ApproachLength 16, BallDiameter 0.72, DeckEnd 64.06, GutterDepth/Width, PinHeight 1.27, PinRow, PinSpacing, PitDepth, PitEnd), PromptAnchor (ProximityPrompt '볼링 치기' / '합류하기'), FoulBarrier (CanCollide on, group BowlingBarrier), BallRest, Sweep (DropHeight/Travel), BumperL/R (UpOffset), Pins/Pin_1..10 (PinNumber, PrimaryPart Collider), Ball (BallCore), LaneBed/PinDeck (custom friction), Approach, Pit; renders SurfaceGui LaneMonitor_NN; model attribute Players.",
    "Bowling.prepareLane/prepareHallParts: EVERY CanCollide BasePart inside a Lane_XX model (except pins/ball) and inside 'Pit' and 'Cappings' is put in collision group BowlingLane (collides with the server-physics ball and pins) → never add server-side collidable parts under these models; client-only decor outside them.",
    "BallRackPrompt x6 → server adds ProximityPrompt '공 고르기' (F, ObjectText '하우스볼 8~16 lb', MaxDist 8) → Picker UI; HouseBall Lb attrs are decor.",
    "HallLeaderboard (MaskingWall) SurfaceGui 'LeaderboardGui' Row1..5 written by Bowling server.",
    "BowlingClient: parts tagged BowlingCosmic (LEDStrip, CosmicStrip, SetteeNeon, MovingHeadLens, CosmicPlanet, MuralPlanet, StepNeon, WallNeon) hue-cycle at 3 Hz while the camera is inside their bbox (+16 margin, r90); lane prompts hidden locally while playing; BowlingFX Cam/Rig/Guide drive the approach camera → keep each lane volume (x lane±3, z335~423, y6.75~19) free of new opaque client parts.",
    "Play.Street.onBowlingLane (busy check), Life/Progress via player attr LastBowlingScore, VenueLife bowling board, Arcade Adapters hookBowling, ServerStorage.GwangalliBowlingEvent.",
    "Interact skips model '볼링레인' for sittables (settee Seats are not GwSittable).",
    "Not referenced by any script (safe to hide/replace client-side): ScoreConsole/ConsoleGui, Settee*, BallReturn*, DryerGrille, MonitorPole/Bar/Mount, masking Sign_* panels, PinLight, Pinsetter/PinsetterDeck/PinsetterTurret, PitCurtain, Kickback*, MaskingWall art, Truss/MovingHead, Speaker, Duct (Capping/Kickback are collidable in group BowlingLane — hide visually, don't delete).",
    "볼링레인 is a ZoneLOD model (LODCenter 318.6,17.6,388.1, LODRadius 106)."
   ],
   "emptyOrCrude": [
    "Pinsetters are single boxes with a red box turret; masking is a flat panel with neon dots; pit curtain a slab.",
    "Ball return: box base + cylinder hood; no hand-blower vent detail, ball ring/track.",
    "Score console is a 1.5x0.12x1 slab on a post; overhead monitors flat slabs on a pole; no big projection screens above the masking.",
    "Settees: 6 identical boxes in a straight line per pair (no U/ㄷ team seating, cup holders, shoe-change bench, belongings baskets).",
    "Pins have box bellies/heads (not lathe profiles); balls plain spheres with 3 flat dots.",
    "Lane surface: no board lines/oil sheen; arrows/dots are tiny slabs; gutters flat channels.",
    "No ball cleaner/polisher, towel, rosin at the approach; ceiling over lanes is a flat dark slab with 3 ducts (no acoustic panels, projector rig, lane canopy)."
   ],
   "realWorld": [
    "합성 레인 (39보드 결), 어프로치 도트, 가이드 애로우 7개, 파울라인 + 파울 센서, 거터, 어린이용 자동 범퍼",
    "페어마다: 볼 리턴기 (후드 + 핸드 블로어 + 볼 받침 링), 터치 스코어 콘솔 (이름·범퍼·게임 추가·직원 호출), 오버헤드 모니터 2대 (점수/리플레이), U자/ㄷ자 팀 소파 + 테이블 + 컵홀더, 볼링화 갈아신는 벤치",
    "마스킹 유닛 (라이트박스 그래픽/LED 영상) + 핀라이트 + 레인 번호",
    "핀세터 (Brunswick GS-X / AMF 82-90XL): 데크, 스위퍼, 핀 디스트리뷰터, 커튼 뒤로 일부 보임",
    "락볼링: 블랙라이트, 형광 캡핑, 무빙헤드/레이저, 대형 프로젝션 스크린 (뮤비), 클럽 음향",
    "하우스볼 랙 (6~16lb 색깔별), 볼 클리너 머신, 타월, 로진백, 볼 폴리셔",
    "컨코스: 관람석, 음료 테이블, 직원 호출벨, 음료 주문 태블릿"
   ],
   "interactionIdeas": [
    "스코어 콘솔: '콘솔 사용' → name entry, bumper toggle (server already supports per-player bumpers), add game, call staff",
    "볼 리턴 송풍구: '손 말리기' → air sound + particle",
    "볼 클리너 (new, concourse): '공 닦기' → ball spins in the machine",
    "로진백/타월: '로진 묻히기' quick emote before throwing",
    "팀 소파 테이블: order drinks to the lane (bar staff NPC delivers)",
    "오버헤드 모니터: replay of the last strike from BowlingFX camera",
    "코스믹 모드 (staff button): toggle black-light / disco mode via the BowlingCosmic parts"
   ]
  },
  {
   "name": "1F 엘리베이터 홀 (2~4층 전용) + 엘리베이터 (광안빌딩)",
   "path": "Workspace.Gwangalli.bowling.실내.2~4층_엘리베이터홀 + 상층_2F-4F.엘리베이터_광안빌딩",
   "bounds": "(341.1,6.75,446.0)-(354.8,19.0,467.9)",
   "enterable": true,
   "rooms": [
    {
     "name": "1F 엘리베이터 홀 (Floor_UpperLobby Granite 196,178,150; street door x346~349 z467.9)",
     "center": [
      348.2,
      12.7,
      457
     ],
     "size": [
      13.2,
      11.9,
      21.2
     ],
     "floorY": 6.75,
     "ceilingY": 18.6
    }
   ],
   "props": [
    "Wall x2 plaster (196,188,174) + Ceiling 12.7x0.4x20.4 at y18.8",
    "ElevatorDoor x2 4.4x8.2x0.15 metal slabs + DoorSeam + ElevatorHead (never open)",
    "ElevatorButton_2F/3F/4F metal tiles (0.6~1.3 wide) on the z447 wall at x342.3/347.9/353.8 + ButtonPlate x12 (all floors)",
    "Sign_층별 안내 7x5.4 (4F 휘트니스 / 3F 헤어·편집숍 / 2F 당구 / 1F 락볼링)",
    "Mailbox x4 stacked 1x0.9x6 boxes; LobbyLight (SurfaceLight)",
    "ElevatorStop_1..4 invisible 4x1x4 pads at (348.0,7.3,451.9) / (347.9,30.6/41.5/52.5,451.9)"
   ],
   "gameplay": [
    "ElevatorButton (tag; Floor, FromFloor, Target 'ElevatorStop_<n>', Label): Venues.setupButton → prompt → fade + safe teleport onto the ElevatorStop pad; StreetInteract NPC routine 'lift' rides via the same buttons (Places.luau). Keep names/attrs/tags and the pads unobstructed.",
    "Model attrs ElevatorGroup '광안 락볼링빌딩', Floors '1,2,3,4'."
   ],
   "emptyOrCrude": [
    "No floor indicator or ▲▼ call buttons; destination buttons are bare text tiles; doors never open and there is no cab (ride = fade teleport).",
    "Mailboxes are 4 boxes; no CCTV, notice board, 소화전, plant, trash."
   ],
   "realWorld": [
    "LED 층 표시기 + 방향 화살표, ▲▼ 호출 버튼, 헤어라인 스테인리스 문, 승강기 점검 필증",
    "층별 안내 (테넌트 로고), 호실별 우편함, 게시판, 소화전함, CCTV, 비상구 유도등, 금연 표지",
    "엘리베이터 카: 조작반 (1~4, 열림/닫힘, 비상통화), 거울, 핸드레일, 정원 표시, 천장 조명, 층 표시"
   ],
   "interactionIdeas": [
    "호출 버튼: '엘리베이터 부르기' → arrow lights, indicator counts, door leaves slide open (client tween) and the existing ElevatorButton teleport fires from inside a client-built cab",
    "카 조작반: floor buttons mapped 1:1 to ElevatorButton_nF",
    "우편함/층별 안내: tap for venue hours and floor info"
   ]
  },
  {
   "name": "2F 광안 당구클럽",
   "path": "Workspace.Gwangalli.bowling.상층_2F-4F.2F_광안당구클럽 (+ 2F_입구, 구조_계단_엘리베이터.2F_바닥천장, FitOut)",
   "bounds": "(232.2,30.08,415.2)-(354.2,39.56,468.7)",
   "enterable": true,
   "rooms": [
    {
     "name": "당구 홀 (Floor_2F WoodPlanks 46,40,38 + 2 Carpet strips 58,30,34; ceiling 30,28,34)",
     "center": [
      282.8,
      34.8,
      442.45
     ],
     "size": [
      101.2,
      9.5,
      52.5
     ],
     "floorY": 30.08,
     "ceilingY": 39.56
    },
    {
     "name": "큐 보관함 · 화장실 코너 (extension floor)",
     "center": [
      343.6,
      34.8,
      421.4
     ],
     "size": [
      21.2,
      9.5,
      12.5
     ],
     "floorY": 30.08,
     "ceilingY": 39.56
    },
    {
     "name": "입구 (glass partition x333.9, door gap z~458~461)",
     "center": [
      333.9,
      34.8,
      457.5
     ],
     "size": [
      1,
      9.5,
      20.8
     ],
     "floorY": 30.08,
     "ceilingY": 39.56
    }
   ],
   "props": [
    "당구대 x8: 대대(3쿠션) 당구대_1,2,5,6,7,8 — TableBody 9.6x1.12x5 Wood, Cloth 9.06x0.25x4.46 blue, Cushion x4, Rail x4 square 0.62 bars, TableLeg x2 blocks 1.5x1.25x3.9, LampShade 6.6x0.5x1.6 + LampDiffuser neon + 2 hangers, 3~4 balls (0.21), Sign_3쿠션 'NN : NN'; 포켓볼대_3,4 — 8.1x1.12x4.2, green cloth, Pocket x6 cylinders, 16/7 balls",
    "Carpet x2 77x15.8 under the table rows (z448~464, z421~437)",
    "대기석 (z416~425): 4 sofas 10 wide (3 seats each, black leather), SideTable x4 with Bottle x4 + Cup x4, 짜장면 Bowl + Jjajang + Danmuji + DeliveryBox (철가방) — nice touch; CueRack x3 3.2x6 + Cue x15",
    "카운터 (x320~332, z444~451): CounterBody 10x3.1x2.4 + Granite top + glow + POSMonitor/POSScreen, Chalk x4, Cue x8 + CueRackBase/Top, LogoWall 12x8.4 + Sign_BILLIARDS CLUB neon, Sign_당구 요금 (대대 10분 2,500 · 중대 2,000 · 포켓 2,500 · 1시간 13,000 · 개인 큐 보관 월 10,000 · 짜장면 배달 OK)",
    "큐보관함: CueLockers 18.6x7.2x1.6 single wood box + LockerSeam x12, red sofa, plant, RestroomDoor + Sign_화장실 WC (door on the back wall)",
    "VendingMachine 3.2x6.2x3 + VendingWindow neon + slot; WaterDispenser + LED; LEDScreen x2 in housings (PBA 3쿠션 생중계 / 하이런 이벤트); Sign 매너 큐 · 금연 · 큐 보관함; Sign_오늘도 하이런!",
    "WindowLedge 76x0.2x1.8 + 8 stools (StoolBase/StoolPost/StoolSeat)",
    "Downlight x17 neon discs (only 당구대_2 and _8 carry a SurfaceLight)",
    "People x4 static block mannequins (Thigh/Shin/Torso/Arm boxes, ball head, box hair) + 2 cues",
    "FitOut: Baseboard, CassetteAC x3 (+vanes/grilles), CCTV, ExitSign, extinguisher, Door_restroom (back wall), SmokeDetector, SwitchPlate"
   ],
   "gameplay": [
    "No scripted gameplay: ShopFlows billiards drives only models named 'BilliardTable_<n>' (children TableCenter, Ball1..4, Scoreboard) inside a ShopFloor shop; Shared.Billiards sim play area is W=12 x H=6 studs (R 0.26) vs this cloth 9.06x4.46 → these tables can't be played.",
    "Players are sent here anyway: Destination_당구클럽 (338.2,30.58,457.18) 'DisplayName 광안 당구클럽 (2F)', Social invite 'billiards' (dest '광안 당구클럽 (2F)'), GwangalliNav node 3010, Taxi confuse list.",
    "No clerk: ShopStaff needs a ShopFloor storefront or a loose BasePart named POS/PosBase/BarCounter/FrontDesk… or a ShopCounter tag; 'POSMonitor' doesn't match → empty counter.",
    "Model attrs TableType '대대 (3쿠션)' / '포켓볼' are informational only.",
    "Interact sittables: sofa Seats x14, StoolSeat x8 (name contains seat/stool → chair).",
    "상층_2F-4F is a ZoneLOD (LODCenter 293.3,53.5,442.2, LODRadius 143); per-table 'Detail'/'NearDetail' are NearLOD."
   ],
   "emptyOrCrude": [
    "Tables: square bar rails, two block legs, no diamond sights, corner castings or apron; '3쿠션' tables 1,2,5,7 carry 4 balls (4구 set).",
    "No per-table scoreboard (전자 점수판/주판) or wall cue rack per table; no chalk on rails, no bridge/rest.",
    "17 'downlights' are emissive discs that light nothing; ceiling is a flat dark slab.",
    "Central aisle z437~448 between the two table rows is 11 studs of bare floor x232~320 with nothing (no score towers, side tables, ash-free stands).",
    "Static block mannequins look primitive next to the skinned NPCs.",
    "Restroom door (348.2,33.8,415.4) and FitOut Door_restroom lead into the back wall z416.1 — there is no restroom (behind is the solid Core block)."
   ],
   "realWorld": [
    "대대 국제식 3쿠션 테이블 (열선 슬레이트, 다이아몬드 포인트, 고무 쿠션, 6족 원목 다리), 중대, 9ft 포켓볼대 (포켓 + 볼 리턴)",
    "테이블마다: 사각 LED 조명, 전자 점수판 (태블릿/큐스코어: 이닝·하이런·애버리지), 큐 스탠드, 초크 + 파우더, 레스트, 브러시",
    "카운터: 시간제 요금 POS (테이블별 타이머), 공 세트 보관, 큐 팁 교체 공구, 음료 냉장고, 커피 머신",
    "개인 큐 보관함 (번호), 관전 소파 + 사이드 테이블, 짜장면·탕수육 배달 메뉴판",
    "TV PBA/LPBA 중계, 대회 포스터, 금연/매너 안내, 공기청정기, 에어컨",
    "포켓볼: 삼각 랙/9볼 랙, 1~15번 볼 세트"
   ],
   "interactionIdeas": [
    "당구대: '당구 치기 (10분 2,500원)' → reuse GameViews/ShopFlows billiards (aim + Shared.Billiards.shoot) by building TableCenter/Ball1..4 aliases client/server-side and scaling the sim to the 9.06x4.46 cloth",
    "큐 걸이: '큐 고르기' → cue held prop; 초크: '초크 칠하기' emote",
    "점수판: '점수 올리기' manual counter for social play",
    "카운터: '테이블 배정' timer + clerk NPC; '짜장면 시키기' → delivery NPC with 철가방 after N s, eat at the side table",
    "자판기 / 정수기: buy coffee, drink water",
    "TV: 'PBA ↔ 야구' channel"
   ]
  },
  {
   "name": "3F 헤어살롱",
   "path": "Workspace.Gwangalli.bowling.상층_2F-4F.3F_헤어살롱_편집숍.헤어살롱 (+ 3F_입구, 3F_바닥천장)",
   "bounds": "(294.7,41.0,415.0)-(354.3,50.55,468.7)",
   "enterable": true,
   "rooms": [
    {
     "name": "살롱 홀 (Floor_Salon WoodPlanks 150,112,78; reception + styling island)",
     "center": [
      314.2,
      45.8,
      442.45
     ],
     "size": [
      38.4,
      9.55,
      52.5
     ],
     "floorY": 41,
     "ceilingY": 50.55
    },
    {
     "name": "샴푸실 · SPA (extension corner)",
     "center": [
      345.4,
      45.8,
      420.8
     ],
     "size": [
      17.6,
      9.55,
      11
     ],
     "floorY": 41,
     "ceilingY": 50.55
    },
    {
     "name": "컬러바 (along back wall z415.6~423.5)",
     "center": [
      313.7,
      45.8,
      419.5
     ],
     "size": [
      30.7,
      9.55,
      8
     ],
     "floorY": 41,
     "ceilingY": 50.55
    }
   ],
   "props": [
    "살롱_리셉션: DeskBody 8x3.1x2.2 white + wood top (ShopCounter_salon) + DeskGlow + Sign_HAIR SALON; Detail: Tablet + screen, plant, Magazine x3",
    "대기소파 x1 (10 wide, 3 seats, beige fabric) + CoffeeTable 6x1.5x2.4",
    "스타일링_아일랜드: IslandCounter 22x2.8x2.2 + IslandTop + IslandMirrorWall 22x5.8x1.1 (double-sided), Mirror x6 3.4x4.8 + MirrorLight x6, 스타일링체어_1..6 (3 per side; ChairBase disc, ChairPost, seat 2x0.55x1.9, ChairBack, Armrest x2, Footrest), Trolley x6 + TrolleyTop, Product x12 cylinders, PendantCord/Shade/Bulb x6 (2 PointLights AlwaysOn)",
    "컬러바: ColorCounter 18x3.1x2.2 + ColorTop + ColorShelf + ColorBox x12 identical, Steamer x2 (base + pole + ring), Sign COLOR · PERM · CLINIC",
    "샴푸실: BasinCabinet x3 + Basin x3 black marble + Faucet/FaucetSpout x3, WashChairBase/WashChair/WashBack/LegRest x3, TowelCabinet + Towel x4 cylinders, PendantGlobe x3, Sign SHAMPOO · SPA",
    "Sign_HAIR PRICE 7.5x4.6 (커트 15,000 · 다운펌 25,000 · 펌 60,000~ · 염색 50,000~ · 클리닉 30,000 · 드라이 12,000), Sign_hair & style neon, PartitionWall 0.6x9.6x31.1 at x294.7, Downlight x8 neon discs",
    "People: 3 static block figures (one with Cape) + Ponytail"
   ],
   "gameplay": [
    "SalonChair (tag; Label '헤어 스타일링 의자', Pose sit) on 스타일링체어_2..6 → Venues.setupShop(inst, true): kiosk prompts ('<style> 구매' + '다음 상품 ▶'), each chair starts on a different style; 스타일링체어_1 has an untagged 'ChairSeat' → only 5 of 6 chairs work.",
    "ShopCounter_salon (tag; ShopId salon, Label '헤어살롱 예약 · 스타일 선택') → Venues kiosk + menu board above counter, phone PhoneAction 'buy' within reach; ShopStaff spawns a clerk behind this ShopCounter-tagged part (no other staff within 9 studs) → keep z465~468 behind the desk clear.",
    "Interact excludes SalonChair/ShopCounter-tagged parts; 대기소파 Seats sittable.",
    "Destination_헤어·편집숍 (338.2,41.46,457.18)."
   ],
   "emptyOrCrude": [
    "Window side x297~322, z449~462 (~25x13) between island and reception is empty wood floor; no product retail shelf or coffee bar.",
    "Styling chairs are box seats on discs (no hydraulic base, headrest); trolleys hold only cylinders (no scissors, combs, dryers, irons).",
    "Color bar: 12 identical boxes; no dye tubes, bowls, brushes, scale, gloves; steamers are a ring on a pole.",
    "Shampoo basins are black boxes, no hose sprayers; towels are cylinders; no towel warmer.",
    "No washer/dryer, broom/hair on floor, designer profile frames.",
    "Static block people."
   ],
   "realWorld": [
    "리셉션: 예약 태블릿/POS, 카드단말기, 홈케어 제품 진열장 (샴푸·트리트먼트·왁스), 쇼핑백",
    "대기: 소파 + 패션 잡지·스타일북 + 커피 머신/티 셀프바 + 정수기",
    "스타일링: 대형 거울 + LED, 유압 미용의자 (페달·헤드레스트), 워킹 트롤리 (가위·빗·클립·스프레이), 드라이어 홀더, 고데기/매직기, 손님 가운 걸이",
    "샴푸실: 백워시 샴푸대 (도기 볼 + 샤워헤드 호스), 리클라이너, 수건 온장고, 수건장, 은은한 조명",
    "펌/염색: 디지털펌 기계, 롤러볼/클라이맥존 가열기, 호수별 염색약 진열, 염모 볼·브러시, 저울, 비닐장갑, 캡",
    "기타: 세탁기·건조기, 빗자루/머리카락 청소기, 디자이너 소개 액자, 가격표, 네온 사인"
   ],
   "interactionIdeas": [
    "미용의자: keep the kiosk, add a stylist NPC haircut animation (scissors, hair-clipping particles) and a mirror camera reveal",
    "샴푸대: '샴푸 받기' → lie-back pose, water sound, towel wrap",
    "펌 가열기: '펌 기계' timer with a spinning heater ring",
    "컬러바: '염색 컬러 고르기' → hair colour picker feeding the salon purchase",
    "잡지: sit + read pose; 커피 셀프바: '커피 받기' held cup",
    "제품 진열장: buy hair wax (appearance buff)"
   ]
  },
  {
   "name": "3F 편집숍 (GWANGAN SELECT SHOP)",
   "path": "Workspace.Gwangalli.bowling.상층_2F-4F.3F_헤어살롱_편집숍.편집숍",
   "bounds": "(232.2,41.0,416.2)-(294.4,50.55,468.7)",
   "enterable": true,
   "rooms": [
    {
     "name": "매장 (Floor_3F Concrete 206,202,194)",
     "center": [
      263.3,
      45.8,
      442.45
     ],
     "size": [
      62.2,
      9.55,
      52.5
     ],
     "floorY": 41,
     "ceilingY": 50.55
    },
    {
     "name": "피팅룸 (3 booths, curtains z424.7)",
     "center": [
      262,
      45.6,
      422
     ],
     "size": [
      28.8,
      9.5,
      11.2
     ],
     "floorY": 41,
     "ceilingY": 50.4
    },
    {
     "name": "쇼윈도 (WindowPlatform y41.6)",
     "center": [
      245.7,
      45.8,
      466
     ],
     "size": [
      20,
      9.2,
      4.6
     ],
     "floorY": 41.6,
     "ceilingY": 50.55
    }
   ],
   "props": [
    "행거_1..4 x4: RackPost x2 + RackFoot x2 + RackRail 6.6 cylinder, Garment x10 each (0.28x3~4x2.1 fabric slabs, one colour per rack)",
    "진열테이블_1..2 x2: TableTop 6.8x0.3x3.6 wood + white base + FoldedStack x6 boxes",
    "벽면행거 (x292~294.6, z419~445): WallRail 26 + WallShelf 26 + Garment x18 + FoldedStack x8",
    "피팅룸: FittingWall x4, FittingHeader 18.4x0.4x8.5, FittingCurtain x3 slabs, FittingMirror x3, FittingStool x3, MirrorFrame x2 + FloorMirror x2, Sign FITTING ROOM",
    "슈즈선반: ShoeShelf 15.4x7.2x1.6 + ShelfEdge x3 + Shoes x10 and Bag x5 (identical 1.8x0.65x1.2 boxes)",
    "편집숍_계산대: CounterBody 10x3.1x2.4 + ShopCounter_clothing wood top + POSMonitor/POSScreen + ShoppingBag x3 cardboard + Sign GWANGAN SELECT",
    "WindowPlatform 20x0.6x4.6 + 3 mannequins (Stand, StandPole, Pants, Top, 2 Sleeves, Neck, box Head)",
    "천장조명: LinearBody x6 + LinearDiffuser x6 + Hanger x12; TrackRail 20 + TrackHead x4 + lenses (2 SurfaceLights)",
    "Plants x2; Sign_SELECT SHOP · NEW ARRIVALS (window), Sign_GWANGAN SELECT SHOP (back wall); People: 2 static block figures at the counter"
   ],
   "gameplay": [
    "ShopCounter_clothing (tag; ShopId clothing, Label '편집숍 계산대 · 옷 구매') → Venues kiosk prompts + menu board above, PhoneAction 'buy'; ShopStaff clerk behind the counter (z428~431) → keep clear.",
    "Fitting room, racks, mirrors: no script references."
   ],
   "emptyOrCrude": [
    "Centre x262~292, z430~465 (~30x35) is nearly empty concrete; 4 racks + 2 tables for a 62x52 store.",
    "Garments are flat slabs (no hangers, sleeves, collars); folded stacks are boxes; shoes/bags identical boxes.",
    "Mannequins: box heads on poles, no arms/hands.",
    "Fitting curtains are slabs; no hooks, mats, booth numbers, mirror lighting.",
    "No accessories (caps, sunglasses, jewellery case, socks), brand wall graphics, price tags, sale POP, EAS gate, speaker, rug, companion seating."
   ],
   "realWorld": [
    "행거 (원목/블랙 파이프) + 옷걸이 + 사이즈 링, 벽면 선반 (폴딩 니트·티), 중앙 테이블 진열, 조명 슈즈 월, 가방·모자·주얼리 유리 진열장",
    "전신 마네킹 (팔·손 포즈), 시즌 VMD 쇼윈도, 브랜드 레터링/네온",
    "피팅룸: 커튼 + 전신거울 + 후크 + 스툴 + 신발 벗는 매트 + 번호표",
    "계산대: POS, 카드단말기, 택건/가격표, 쇼핑백·포장지, 영수증 프린터, 도난방지 태그 리무버",
    "입구 도난방지 게이트, 디퓨저, 스피커, 식물, 트랙 조명"
   ],
   "interactionIdeas": [
    "행거/벽면: '옷 구경하기' → item card from the clothing stock, '입어보기' → fitting room",
    "피팅룸: '커튼 닫기 / 입어보기' → curtain tween + outfit preview camera, '구매하기' at the counter",
    "전신거울: pose/photo",
    "슈즈 월: '신어보기' preview; 액세서리 진열장: caps/sunglasses accessory purchase",
    "쇼윈도 마네킹: rotate the daily VMD set"
   ]
  },
  {
   "name": "4F 광안 휘트니스 24",
   "path": "Workspace.Gwangalli.bowling.상층_2F-4F.4F_광안휘트니스24 (+ 4F_입구, 4F_바닥천장)",
   "bounds": "(232.2,52.0,414.9)-(354.2,61.95,468.7)",
   "enterable": true,
   "rooms": [
    {
     "name": "운동 홀 (Floor_4F Rubber 44,45,48; ceiling 26,26,30)",
     "center": [
      282.8,
      57,
      442.45
     ],
     "size": [
      101.2,
      9.95,
      52.5
     ],
     "floorY": 52,
     "ceilingY": 61.95
    },
    {
     "name": "유산소 존 (window side: treadmills, bikes, rowers)",
     "center": [
      266,
      57,
      462.5
     ],
     "size": [
      63,
      9.95,
      9
     ],
     "floorY": 52,
     "ceilingY": 61.95
    },
    {
     "name": "프리웨이트 존 (squat racks, benches)",
     "center": [
      245,
      57,
      440
     ],
     "size": [
      26,
      9.95,
      24
     ],
     "floorY": 52,
     "ceilingY": 61.95
    },
    {
     "name": "머신 · 기능성 존 (mirror wall z416, cable, pull-up, leg press, lat, turf)",
     "center": [
      300,
      57,
      425
     ],
     "size": [
      45,
      9.95,
      18
     ],
     "floorY": 52,
     "ceilingY": 61.95
    },
    {
     "name": "리셉션 · 인바디 · PT",
     "center": [
      325.5,
      57,
      455
     ],
     "size": [
      17,
      9.95,
      24
     ],
     "floorY": 52,
     "ceilingY": 61.95
    },
    {
     "name": "락커 코너 (extension; shower doors are fake)",
     "center": [
      344.6,
      57,
      421.4
     ],
     "size": [
      19,
      9.95,
      12.8
     ],
     "floorY": 52,
     "ceilingY": 61.95
    }
   ],
   "props": [
    "러닝머신_1..8 (deck, belt, motor hood, 2 uprights, 2 handrails, console screen)",
    "실내사이클_1..4 (feet, flywheel, crank, frame, seat post, saddle, bar post, handlebar, console)",
    "로잉머신_1..2 (rail, seat, flywheel housing, footrests, screen + arm, feet)",
    "스쿼트랙_1..2 (LiftingPlatform 7.2x5.8, 4 uprights, top beam, pull-up bar, 2 safety bars, Barbell 7.3, Plate x4)",
    "벤치프레스_1..2 (frame, foot, uprights + J-hooks, Barbell, Plate x4)",
    "덤벨랙 (base, 2 shelves, 4 legs, 16 dumbbells = DumbbellHead x32 + DumbbellHandle x16); 덤벨벤치_1..2",
    "케이블크로스오버 (12 parts), 턱걸이_딥스 (11), 레그프레스 (base, back, sled, footplate, 2 plates), 랫풀다운 (tower, WeightStack, boom, cable, bar, seat post, knee pad)",
    "기능성존: TurfLane + TurfLine x2 + TurfMark x4, PlyoBox x3, Sled + handle; 스트레칭존: YogaMat x4; Detail: Kettlebell x6, GymBall x3, FoamRoller x5",
    "거울벽: Mirror x6 + MirrorFrame x9 (z416~417); 3 TVs (ScreenHousing + LEDScreen messages + TVMount)",
    "리셉션: CounterBody + ShopCounter_gym_store marble + CounterLED + POS, LogoWall 12x8.6 + neon, Sign_회원권 안내 (1개월 49,000 …), Fridge glass + Drink x12, SupplementShelf + ProteinTub x5 + Shaker x3, plants x2",
    "인바디: platform, column, foot/hand electrodes, Sign_InBody",
    "락커_샤워실: LockerBank 18.6x7.2x1.8 + LockerDoor x6 (102~107) + seams, LockerBench, TowelShelf + Towel x3, LockerRoomDoor x2 + signs (남자/여자 탈의실 · 샤워실)",
    "천장: LinearBody/Diffuser x18 (4 SurfaceLights AlwaysOn) + Hanger x36 + Duct x2 (98 long)",
    "WaterDispenser + LED; Signs 운동은 배신하지 않는다 / 오늘도 득근! / FREE WEIGHT / PT ZONE",
    "NPCs: 트레이너 김코치, 회원 (스트레칭), 회원 (덤벨 컬); People model: Sign_PT · 오늘의 루틴 · 김코치 floating at (327.0,100.0,451.2) + loose dumbbell"
   ],
   "gameplay": [
    "GymStation x25 (tag; attrs StationType treadmill/bike/squat/bench/dumbbell/pullup/inbody, Pose, RepStyle, Machine, Label; runtime InUse) → Venues.setupStation hold-1s prompt → gym session (sets, form taps, gains); Play/Gym routines; GwangalliVenues/Gym client rep animation. Parts named Bar/Barbell/Weight/Weights/WeightStack/Plate/Plates/Handle/Dumbbell (G.GYM_MOVING_PARTS) or attr GymMoving bob during sets (<=12 anchored parts per station model) → don't rename, keep anchored, don't weld new parts to them.",
    "VenueSpot gym_locker x6 (LockerDoor, LockerNo 102~107): server ProximityPrompt '락커 열기' tweens door.CFrame 105° about its left hinge → keep the swing space (z424~426) free.",
    "VenueSpot gym_water (Spot_gym_water at (331.2,54.5,437.0), '물 마시기' hold 0.3) and gym_trainer (Spot_gym_trainer + VenueStaff Staff=gym_trainer, routine quest).",
    "VenueStaff gym_regular x2 (Act stretch / gym:curl) animated members; GwangalliStaticNpcSkins skins 트레이너 ('uniform').",
    "ShopCounter_gym_store (ShopId gym_store) kiosk (drinks/protein); trainer within 9 studs so ShopStaff adds no clerk.",
    "Destination_헬스장 (338.2,52.46,457.18); Journey quest find radius 35, dy 6.",
    "Interact excludes GymStation-tagged parts from sittables."
   ],
   "emptyOrCrude": [
    "Equipment is box-built: treadmill decks/hoods boxes, consoles flat neon slabs, bikes are stick figures; plates/dumbbells plain cylinders.",
    "Missing the typical Korean gym machine line: smith machine, chest/shoulder press, pec deck, leg extension/curl, hack squat, seated row, hip ab/adductor; no plate trees, barbell storage, incline/decline benches, stepmill, elliptical.",
    "Locker room/shower doors (z415.6) open into the back wall — no changing room, showers, powder area.",
    "No entry gate, towel return, sanitizer stations, scale, speakers, GX/PT room.",
    "Floor is uniform dark rubber; walls plain plaster (40,40,44) except the mirror wall.",
    "Floating sign 'Sign_PT · 오늘의 루틴 · 김코치' at y100 (38 studs above the roof y62.9) — misplaced."
   ],
   "realWorld": [
    "출입: 지문/안면/QR 출입 게이트, 회원 키오스크, 인포 데스크 (운동복·수건 대여, 보충제·음료·쉐이크)",
    "유산소: 개별 TV 러닝머신, 업라이트/리컴번트 사이클, 천국의 계단, 일립티컬, 로잉",
    "프리웨이트: 파워랙, 플랫/인클라인/디클라인 벤치, 1~40kg 덤벨 랙, 원판 거치대, 바벨 거치대, 데드리프트 플랫폼, 초크볼",
    "머신: 스미스, 레그프레스, 핵스쿼트, 레그 익스텐션/컬, 체스트·숄더프레스, 펙덱, 랫풀다운, 시티드 로우, 케이블 크로스오버, 어시스트 풀업, 힙 어브/어덕션",
    "스트레칭/기능성: 매트, 폼롤러, 밴드, 짐볼, 케틀벨, 플라이오 박스, 슬레드 + 인조잔디",
    "위생: 기구 소독 스프레이 + 페이퍼타올, 정수기 + 종이컵, 수건 반납함, 쓰레기통",
    "탈의실/샤워: 번호 락커, 벤치, 파우더존 (드라이기·스킨/로션·면봉), 체중계, 샤워 부스 + 디스펜서, 탈수기",
    "기타: 동기부여 문구, 음악 스피커, TV 뉴스, PT룸, GX룸, 인바디"
   ],
   "interactionIdeas": [
    "출입 게이트 (new): '지문 찍기' → beep + gate arm opens",
    "수건: '수건 받기' held towel / '수건 반납'",
    "덤벨랙: '덤벨 들기 (5~20kg)' → held dumbbell + free curl emote",
    "원판: choose plate weight at squat/bench before a session (display only)",
    "소독 스테이션: '기구 닦기' after a set (+manner/popularity)",
    "샤워실 (client-built rooms inside the hall, since behind the doors is solid core): '샤워하기' → steam + water, fatigue down",
    "체중계: '체중 재기' from stats; 프로틴 쉐이크: order at the counter; TV channel / playlist select"
   ]
  },
  {
   "name": "2F–4F 엘리베이터 홀 · 입구 · 비상계단",
   "path": "Workspace.Gwangalli.bowling.상층_2F-4F.{2F,3F,4F}_엘리베이터홀, {2F,3F,4F}_입구, 구조_계단_엘리베이터 (계단, 바닥천장)",
   "bounds": "(333.1,29.5,427.5)-(354.8,62.6,467.9)",
   "enterable": true,
   "rooms": [
    {
     "name": "2F 엘리베이터 홀 (Floor_Lobby Granite)",
     "center": [
      344.2,
      34.8,
      457.3
     ],
     "size": [
      21.2,
      9.5,
      20.8
     ],
     "floorY": 30.08,
     "ceilingY": 39.56
    },
    {
     "name": "3F 엘리베이터 홀",
     "center": [
      344.2,
      45.8,
      457.3
     ],
     "size": [
      21.2,
      9.55,
      20.8
     ],
     "floorY": 41,
     "ceilingY": 50.55
    },
    {
     "name": "4F 엘리베이터 홀",
     "center": [
      344.2,
      57,
      457.3
     ],
     "size": [
      21.2,
      9.95,
      20.8
     ],
     "floorY": 52,
     "ceilingY": 61.95
    },
    {
     "name": "비상계단 (2 flights per floor, landings z431.8)",
     "center": [
      337.6,
      46,
      437
     ],
     "size": [
      7.4,
      32.6,
      17.6
     ],
     "floorY": 30.08,
     "ceilingY": 62
    }
   ],
   "props": [
    "Per floor: ElevatorJamb x4, ElevatorHead x2, ElevatorDoor x4 (2 cars x 2 leaves), DoorSeam x2, Sill x2, Sign 'n ▲' / 'n ▼' text tiles, Sign_층별 안내 3.2x2.6, Sign_nF 4.4x4.4, Bench 8x1.3x1.6 + BenchBase, FireExtinguisher + sign, LobbyLight x2; 2F plant",
    "ElevatorButton_1F/2F/3F/4F plates + ButtonPlate per floor (x339.8~353.8, z447)",
    "입구: PartitionGlass x2 (7.6/7.2 wide, t0.62) + base rails + header, DoorPost x2, venue sign 16 wide + OPEN hours (12:00-02:00 / 10:00-21:00 / 24H)",
    "계단: Step x32 + StepNosing x32 (yellow), StairLanding x2, StairWall, Handrail x4, StairLight x5, StairGuardGlass + rail, FireDoorLeaf x3 + DoorFrames, Sign nF 비상계단",
    "ElevatorCoreWall 13.2x32.6x19.2 solid block (no shaft)"
   ],
   "gameplay": [
    "ElevatorButton (Floor/FromFloor/Target 'ElevatorStop_<n>'/Label) per floor → Venues teleport onto ElevatorStop pads (347.9, 30.6/41.5/52.5, 451.9); NPC routines ride via the same buttons.",
    "Destination_당구클럽/헤어·편집숍/헬스장 at (338.2, 30.58/41.46/52.46, 457.18) — Journey Signals use a tight y band to tell stacked venues apart.",
    "FireDoorLeaf / 입구 glass have no door scripts; keep the 입구 door gap and stair runs walkable."
   ],
   "emptyOrCrude": [
    "Doors never open; no cab, no lit floor indicator or ▲▼ call buttons (text tiles only).",
    "Halls 21x21 with one bench: no notice board, CCTV, 소화전함, trash, tenant directory graphics.",
    "Stair: concrete boxes; fire doors static slabs."
   ],
   "realWorld": [
    "LED 층 표시기, ▲▼ 호출 버튼, 스테인리스 문, 테넌트 로고 층별 안내, 소화전함, 소화기, 비상구 유도등, CCTV, 게시판, 휴지통, 화분, 금연 표지",
    "비상계단: 방화문 (도어클로저, 피난 안내도), 층 표시, 핸드레일, 비상등, 논슬립"
   ],
   "interactionIdeas": [
    "호출 버튼 → indicator + door open animation + cab interior with a floor panel bound to the existing ElevatorButton_nF",
    "방화문: '문 열기' push-bar sound, auto close",
    "층별 안내: tap shows venue info/hours"
   ]
  }
 ],
 "notes": "Full JSON written to /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/bowling.json (14 venues). 광안 락볼링클럽 빌딩 (Workspace.Gwangalli.bowling, 10,996 instances). Building AABB x230.4~355.6, z326.6~470.4, rotated ~0.95 deg about Y (rotation entries ±0.0165: walls drift ~+0.0165 x per stud of z). Front facade faces +z (z~469), main AutoDoor at x264.8.\nSCALE: lanes are built 1 stud = 1 ft (LaneLength 60.96, LaneWidth 3.5, ball 0.72, pin 1.27); characters ~5.2 studs. 1F clear height 21.9 (floor top y6.75, ceiling y28.68, dark 16,14,22). Upper floors: 2F floor 30.08 / ceil 39.56, 3F 41.0 / 50.55, 4F 52.0 / 61.95; roof y62.86.\nUPPER FLOORS cover only the front 52.5 studs (z416.2~468.7, plus a 21x12.5 corner x333~354 z415~428 and the lobby/stair/elevator core x333~355 z427~468); behind the back wall z416.1 is a solid 'Core' block 122x33x88. Every restroom/shower/staff door on 2F~4F (Door_restroom, RestroomDoor, LockerRoomDoor, Door_staff) opens into it, so new rooms have to be carved inside the front zone.\nLOD: three ZoneLOD models hide whole interiors beyond radius: 볼링레인 (318.6,17.6,388.1 r106), 실내 (293.6,17.8,398.1 r136), 상층_2F-4F (293.3,53.5,442.2 r143). 247 NearLOD 'NearDetail'/'Detail' models arrive hidden (GwArrive) and show within ~100~120 studs (DetailLOD writes LocalTransparencyModifier). A client builder that hides crude parts must not fight those LTM writes: use its own Transparency on its clones, or register its models with LOD='near' + NearLOD tag.\nDO NOT rename / move / block (runtime contracts):\n- Bowling lanes: BowlingLane models and their LaneFrame, PromptAnchor, FoulBarrier, BallRest, Sweep, BumperL/R, Pins/Pin_n/Collider, Ball/BallCore, LaneBed, PinDeck, Approach, MonitorScreen_NN/LaneMonitor_NN, BallRackPrompt, HallLeaderboard/LeaderboardGui, Pit, Cappings.\n- The collision-group rule: any CanCollide part under Lane_XX/Pit/Cappings joins group BowlingLane on first claim.\n- BowlingCosmic-tagged parts.\n- VenueSpot parts: Spot_bowl_shoes, Spot_bowl_snack + PickupCF, Spot_bowl_punch, LockerDoor x6, Spot_gym_water, Spot_gym_trainer.\n- VenueBoard BoardFace (Board_bowling, Board_punch, SurfaceGui BoardGui Row1..5).\n- VenueStaff rigs: shoe_clerk, bowl_cook, gym_trainer, gym_regular x2. GwangalliStaticNpcSkins hides their bodies and clones an avatar.\n- '농구게임' model + FrontCabinet/Hoop/LEDScreen (Play.Arcade.World); LEDScreen Messages.\n- GymStation x25 + moving part names (Bar/Barbell/Weight(s)/WeightStack/Plate(s)/Handle/Dumbbell).\n- SalonChair x5; ShopCounter_salon/_clothing/_gym_store.\n- ElevatorButton x12 + ElevatorStop_1..4; Destination x4; AutoDoor_정문.\nEXISTING PROMPTS (created at runtime): lane '볼링 치기'/'합류하기', '공 고르기', '볼링화 대여' + '색상 바꾸기 ▶', '분식 주문', '펀치! (500원)', 농구게임 (Arcade), gym stations (hold 1 s), '락커 열기', '물 마시기', trainer routine, salon/clothing/gym_store kiosks ('<item> 구매' + '다음 상품 ▶'), elevator buttons, and Interact sit on Seat/sofa/stool names (볼링레인 settees excluded).\nBIGGEST GAPS:\n(1) 2F 당구클럽 has zero gameplay and no clerk, although Social/Nav/Taxi send players there. The tables aren't named 'BilliardTable_n', and the sim area is 12x6 vs the 9.06x4.46 cloth.\n(2) ROCK & BOWL BAR has no bartender (BarCounter is a Model; ShopStaff needs a BasePart anchor) and nothing to buy.\n(3) 1F restrooms have no fixtures, urinals or lights, and the office/창고 is empty.\n(4) 인형뽑기_1..3 are not playable (Interact claw needs the name ^ClawMachine_%d+$).\n(5) Large empty floors: lobby west x253~300 z446~462, lounge centre x255~280 z408~440, select-shop centre x262~292 z430~465, salon window side x297~322 z449~462, billiards aisle z437~448, corridor x254~281 z343~369.\n(6) Static block 'People' mannequins on 2F (4) and 3F (5) look primitive next to the skinned NPCs.\n(7) 3F 스타일링체어_1 lacks the SalonChair tag.\n(8) The gym sign 'Sign_PT · 오늘의 루틴 · 김코치' floats at (327,100,451).\n(9) Elevators are fade-teleports with doors that never open.\n(10) The 3rd 분식 order is placed at z~380, off the PickupTop shelf.\nSurvey helpers: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/bw/dump.json (every bowling instance with pos/rot/size/material/colour/attrs/tags), /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/bw/summ.py (grouped part summary per subtree), /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/bw/models.py (per-model AABB + tags), /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/bw/write.py (generator for bowling.json)."
}
```

## survey:hospital_garage

```json
{
 "venues": [
  {
   "name": "광안 메디컬 의원 1F (접수·대기실 · 진료실 1 내과 · 주사실/처치실 · 약국 코너 · 후면 계단/엘리베이터 홀)",
   "path": "Workspace.Gwangalli.hospital['광안 메디컬 의원'].1F (+ Staff, AutoDoor_Hospital, Destination at the venue root)",
   "bounds": "(-575.5,6.9,263.3)..(-454.8,17.95,340.7)  [floor top 6.9 (Floor 118.4x0.3x73.6 at y 6.75), CeilingBoard bottom 17.95; model rotated ~178.1 deg about Y (local axes ~1.9 deg off world), street facade + AutoDoor face -Z at z~264-267]",
   "enterable": true,
   "rooms": [
    {
     "name": "로비 + 접수·수납 (ReceptionDesk 20 wide, open to the waiting room; entrance AutoDoor at x -495.9)",
     "center": [
      -504.5,
      12.4,
      278.3
     ],
     "size": [
      47,
      11.05,
      25.5
     ],
     "floorY": 6.9,
     "ceilingY": 17.95
    },
    {
     "name": "대기실 (3 WaitingBench x4 seats on WaitingRug 25x22, TV, kids corner, water purifier)",
     "center": [
      -468.5,
      12.4,
      279.6
     ],
     "size": [
      25,
      11.05,
      26.1
     ],
     "floorY": 6.9,
     "ceilingY": 17.95
    },
    {
     "name": "진료실 1 · 내과 (DoctorDesk, ExamBed, BP trolley, sink; FrostedFilm on the street glass; door at x -535 z 293)",
     "center": [
      -551.3,
      12.4,
      278.1
     ],
     "size": [
      43.4,
      11.05,
      26.9
     ],
     "floorY": 6.9,
     "ceilingY": 17.95
    },
    {
     "name": "1F 복도 (ConsultWall/ReceptionWall/TVWall z~292-294 to PharmHeader/TreatWall z~296.7-298.5; mint WayBand)",
     "center": [
      -515,
      12.4,
      295.6
     ],
     "size": [
      118,
      11.05,
      3.6
     ],
     "floorY": 6.9,
     "ceilingY": 17.95
    },
    {
     "name": "약국 코너 staff side (PharmacyCounter 28 wide under PharmHeader opening x -559..-531, MedShelf, DispensingMachine, VaccineFridge)",
     "center": [
      -545.3,
      12.4,
      308.7
     ],
     "size": [
      57.5,
      11.05,
      21.7
     ],
     "floorY": 6.9,
     "ceilingY": 17.95
    },
    {
     "name": "중앙 통로 (between PharmWall x -515 and TreatWall x -503.8; links corridor to back hall) - completely empty",
     "center": [
      -509.5,
      12.4,
      310.1
     ],
     "size": [
      11.1,
      11.05,
      23.7
     ],
     "floorY": 6.9,
     "ceilingY": 17.95
    },
    {
     "name": "주사실 · 처치실 (TreatBed1/2, MedicineCabinet, TreatmentCart, sink, sharps; door at x -487 z 298.8)",
     "center": [
      -479.5,
      12.4,
      311.1
     ],
     "size": [
      45.7,
      11.05,
      21.7
     ],
     "floorY": 6.9,
     "ceilingY": 17.95
    },
    {
     "name": "후면 홀 (stair up to 2F x -497..-519 z 325-336, elevator x -548 z 337.6 (fake), fake doors 남/여 화장실 x -564/-570, STAFF ONLY x -528, 창고 x -538 on the back wall, fire exit x -456.8 z 331.5, bench)",
     "center": [
      -515.7,
      12.4,
      330.5
     ],
     "size": [
      116.7,
      11.05,
      12.5
     ],
     "floorY": 6.9,
     "ceilingY": 17.95
    }
   ],
   "props": [
    "Shell: Floor = one 118.4x73.6 SmoothPlastic slab (222,224,222) for every room; 13 interior walls 11 tall Plaster (222,218,208) 0.6 thick (ReceptionWall 30, TVWall 25.2, ConsultWall x3, TreatWall x3, PharmWall x3, PharmHeader 28x3, BackWall x2); WayBand mint 0.5 strips x3; Ceiling1F = CeilingBoard 118.4x73.6 + 45 TBar (correct 600-grid look)",
    "Lighting: LightPanel neon slabs 24x8 x2 (lobby), 18x8 x2 (waiting), 36x8 + 36x10 (consult), 40x8 x2 (treatment), 36x8 x2 (pharmacy), 32x4 / 64x4 / 112x4 / 112x3 (corridors) - each one huge glowing slab lying over the T-bar grid; only 6 SurfaceLights (Range 20, InteriorLight AlwaysOn) on 1F, none in BackZone / mid hall / corridor ends; CassetteAC x5 (3.8 box + grille + 4 vanes), CCTV ball x3",
    "Lobby: ReceptionDesk Model (ToeKick, FrontPanel 20x3.3 mint, Ledge 20.4, WorkDesk 20x2.2x4.1, WorkTop, DeskGlow neon) + Detail(NearLOD): 2 Monitor 1.8x1.1 slabs + stands, DeskBell ball; DeskSign '접수 · 수납'; 2 staff chairs (1.6 slab seat + slab back + 1 cylinder leg + disc foot); Printer 3x1.2x2.4 box; FileTray box; TicketKiosk 1.6x4.6x1.2 white box + KioskScreen '번호표 / 터치하세요' + TicketSlot; Sanitizer pole+box; ScreenHousing+LEDScreen 13x3 static '대기 3명 · 진료중 7번 / 다음 8번'; wall Sign_광안 메디컬 의원 22x2.2, Sign_09:00 22:00, Sign_층별 안내 7.6x5.2; StandPoster '독감 예방접종'; Plant x2 (cylinder pot + 2 SpecialMesh leaf blobs); FireExtinguisher cylinder; EntranceMat 8x4.2",
    "Waiting room: WaitingBench x3 (BenchBar 8.4 + 3 legs + 4 BenchSeat Seats 1.8x0.3x1.8 Sittable + 4 flat BenchBack 1.8x1.8x0.15 teal fabric) = 12 seats in 3 rows facing the TV wall; ScreenHousing+LEDScreen 10x5.6 '건강 정보'; Sign_손 씻기, Sign_금연 4.6x3.6 posters; WaterPurifier 1.6x4.6 box + panel + tap + CupHolder slab; MagazineRack box + 4 Magazine slabs; KidsCorner (PlayMat 8x2.6, round TableTop, 2 cylinder Stools, 3 Block cubes, KidsDivider, KidsSign '어린이 놀이방'); AirPurifier box + LED strip; Plant",
    "진료실 1: DoctorDesk Model (DeskTop 12x3.6 wood, DeskBody, Kick, Monitor 4x2.3 '진료 차트 · 혈압 118/76', MonitorFoot, Keyboard slab, ChartFiles box, Mug cylinder); doctor chair + patient Seat (both 1.6 slab stools); ExamBed Model (home-style bed: BedFrame, 4 legs, Mattress 3.4x0.6x7, BedSeat Seat 'exam', Blanket, Pillow, WOOD Headboard 3.4x2.7 + Footboard, one SideRail, L CurtainRail + ONE Curtain panel 4.1 wide); BPMonitor trolley (pole, top, BPUnit '120 / 80', cuff slab); OtoscopeUnit wall box + 3 otoscope cylinders; SinkCabinet 5.8x3x4.6 + top + steel Sink box + Tap + Mirror + PaperTowel; MedWasteBin yellow box '의료폐기물' + Bin cylinder; wall frames Sign_인체 해부도, Sign_의사 면허증, Sign_전문의 자격, Sign_손 씻기 6단계; Scale floor slab + ScaleColumn + ScaleDisplay '0.0 kg · 신장'; Plant",
    "주사실: TreatBed1/2 (same home-style bed + IVPole cylinder 6.2, IVBase, IVBag glass box, IVLine, BedsideCabinet box + wood top + WaterCup; one curtain panel each); MedicineCabinet (base 16x3.4x2.9, top, UpperCabinet 16x5.2x1.7, 39 MedBox ~1.1 cubes in 6 colours behind CabinetGlass t0.55, label '주사제 · 수액 · 소모품'); TreatmentCart (box body, top, 4 wheel cylinders, tray, bottle, gauze); SharpsBin yellow cube on SharpsStand box; SinkCabinet + Sink + Tap; signs '주사 후 5분간 눌러 주세요', '처치실 · TREATMENT', frozen clock 'Sign_10:24'; Plant",
    "약국 코너: PharmacyCounter (toe kick, Body 28x2.95x2.7, Top 28.4 slab, LedStrip); PharmSign 28x2.4 '약국 코너 · 처방약 수령'; ShutterBox bar; DeskBell; PrescriptionScreen 4.4x2.3 '처방 접수 / 조제 대기 2건'; 4 SupplementBox cubes; CounterNote '약사 조제 중 · 벨을 눌러 주세요'; MedShelf (BackPanel 24x7.5, 2 Uprights, 5 Boards 23.6) + Detail(NearLOD) 148 Product boxes (only white/orange/cream/blue, no labels) + 5 PriceRails; DispensingMachine 6x7.4x5.3 box + screen '자동조제기 · 조제 중' + outlet slab; VaccineFridge 4.4x5.6x4.5 box + glass + label '백신 보관 2~8°C'; 1 chair",
    "후면 홀: 20 Step boxes 10x(0.83..15.0)x1.33 (solid stacked, rising -x from x -497 to -519 at z ~330) + 12 RailPost + 2 Rail + 2 MidRail; Door_남자 화장실 / Door_여자 화장실 / Door_STAFF ONLY / Door_창고 (flat 4x8 leaf + jambs + head + handle + sign on the exterior back wall z~337-338, nothing behind); ElevatorJamb x2, ElevatorHead, 2 ElevatorDoor slabs 2.16x8.6 (collidable), FloorIndicator neon, CallButton slab, Sign_엘리베이터; FireExitDoor slab + PushBar + ExitSign x2; Sign_2F ↑; WaitingBench (4 seats); FireExtinguisher; Plant x2",
    "Staff (venue root): 의사 김선생 R15 rig (HospitalStaff, Role doctor) seated at the DoctorDesk (HRP -554.2,8.9,272.5) with apron, glasses, stethoscope parts, badge; 간호사 박선생 (Role nurse) standing beside ExamBed (HRP -565.8,9.8,283.9) with hidden Syringe/SyringeNeedle/SyringePlunger (GwProp syringe); VialTray + TrayStand + 3 Vial at (-565.6,9.9,279.4); HospitalPrompt_doctor (-554.4,9.4,278.9) '진료 받기'; HospitalPrompt_desk (-514.5,9.4,281.2) '접수하기'"
   ],
   "gameplay": [
    "GwangalliGameplay/Health (server): binds every part tagged HospitalPrompt (Kind doctor|desk) -> opens the hospital UI (HealthEvent 'clinic'); reach G.HEALTH.reach 14 (+6) from the anchor; HealthRequest treat/vitamin/checkup charges the fee then runs the choreography: Health.findBed('exam') = ExamBed.BedSeat (Seat, tag HospitalBed, BedKind 'exam') -> player placed 2.6 above the seat and Seat:Sit; nurse 박선생 RightShoulder/RightElbow Motor6D C0 tween + parts with attribute GwProp='syringe' made visible 2.5 s; doctor posed seated by Motor6D C0 writes; rigs found by tag HospitalStaff + attribute Role. DO NOT move/rename/hide: ExamBed BedSeat, both HospitalPrompt_* anchors (invisible 2x4x2) and their ProximityPrompts, the two rigs and their Motor6Ds, the syringe parts",
    "HospitalBed Seats (8): ExamBed 'exam'; TreatBed1, TreatBed2, 2F CheckupBed 'treat'; 2F WardBed_A/B of Ward_201 and Ward_202 'ward'. Health collapse and Arms/KOSystem.wardTarget() -> Health.findBed('ward') wake the player on a ward bed ('광안메디컬 입원실에서 눈을 떴어요'); Play/Ems/Patients.TRANSIT = (-465.3,9.6,304.5) = TreatBed1 (EMS handover). Interact's sittable scan EXCLUDES HospitalBed-tagged parts",
    "Law/Hospital (server NPC life): spawns 접수1 / 의사2 / 간호사3 / 외래 환자3 / 입원 환자1 / 보호자2 when a player is within 170 of CENTER (-515,7,300); walks a named SPOTS graph (1F y 7.2: fore -496,252 · door -496,270 · lobby -505,276 · desk_front -515,281 · desk -503,284 · wait1..3 -466,275/281/287 · hall -505,300 · hall2 -525,294 · bench -520,328 · pharm -540,294 · cons_door -537,297 · cons -545,285 · treat_door -485,296 · treat -478,308 · treat_bed -468,309 · lift1 -548,332; 2F spots in the 2F venue). At start it builds a 2-stud WALK GRID (x0 -582, z0 250, 70x48 cells) from SERVER parts (names with Leaf/Threshold/Track/Prompt/Floor/Rug/Mat and CanCollide=false are passable; every Model named Door_* / AutoDoor* is carved open). Client-only props are invisible to that grid -> NPCs will walk through client furniture unless it stays off the spot-to-spot corridors; server-side props would re-route/block them. Path Workspace.Gwangalli.hospital['광안 메디컬 의원'] is hard-coded",
    "EMS / 119 + Law: Ems.HOSPITAL = Destination '광안메디컬' (-495.8,7.1,261.2, tag Destination); Ems.BASE_POS (-450,7,262), DUTY_POS (-456,7,256), Ambulance PAD (-446,7,254), Law/Rescue BAY (-442,7.2,290) + ENTRANCE (-496,7.2,262); Law/Police.tplData clones AmbulanceBay/Car_Ambulance as the ambulance template",
    "AutoDoor_Hospital (tag AutoDoor, DoorLeaf/LeafStile/Sign parts carry OpenOffset ±3.75): slid by the generic auto-door system - keep the doorway x -500..-491.9 z 264.5..268 clear",
    "Generic tags: NearLOD 'Detail' models (GwangalliWorld/DetailLOD), InteriorLight, LEDScreen x5 (GwangalliWorld/Screens cycles attribute Messages 'a|b|c' - none set, so static), GwSurfaceGui x96, NeonTube, NightGlow/NightNeon. StreetSigns: 'hospital' is a HOST_ANCESTOR; Annex HOST_VENUES.hospital = true; ShopStaff spawns nobody here (no ShopFloor/PosBase anchors) and skips counters within 9 of HospitalStaff",
    "Interact (server): BenchSeat Seats carry Sittable=true; the start scan tags chairs/benches/sofas GwSittable -> keep those parts (or keep them as invisible seat proxies) when replacing visuals"
   ],
   "emptyOrCrude": [
    "Occupancy (furniture band floor+0.3..+7, 2-stud grid): lobby 25% (largest empty square 18x18 at -490,275.5); waiting 28% (14x14 at -475,276.5); 진료실 26% (16x16 at -540,277.6); 약국 21% (16x16 at -537,308.8); 주사실 28% (14x14 at -496.3,306.2); 중앙 통로 0% (12x12 at -510,303.2); 후면 홀 22% (12x12 at -569,329.2); corridor 19%",
    "진료실 1 is a 43x27-stud (~15x9 m) room for ONE desk + one exam bed (real 의원 진료실 ~3x4 m); the west half x -548..-529 is bare floor; reads as an empty hall",
    "Ceiling light = giant neon slabs (24x8 to 112x4) lying on the T-bar grid instead of 2x2-stud LED panels in the grid; only 6 real lights on 1F -> flat glare + dark corners",
    "Floor: one uniform 118x73 SmoothPlastic slab through every room; no 데코타일/장판 seams, no 걸레받이, no corridor/room colour coding, no thresholds",
    "Walls: bare 11-tall plaster with a 0.5 WayBand; no 안전손잡이 handrails, corner guards, outlets/switches, 소화전 cabinet, AED box, bulletin boards (비급여 가격표, 의료진 소개), 진료실 앞 대기 환자 모니터",
    "Beds (ExamBed, TreatBed1/2) are home beds with wooden headboard/footboard, one side rail, one curtain panel; real clinic uses a padded 진찰대 with paper roll + step and 수액 recliners / stretcher beds with full ceiling-track curtains",
    "Every chair = 1.6 slab seat + slab back on one cylinder + disc (doctor, staff, patient, pharmacy identical)",
    "Reception: no acrylic partition, card terminal, signature pad, receipt/처방전 printer detail (Printer is a box), phone, 접수 순서 screen; no receptionist rig (only Law/Hospital's roaming actor)",
    "TicketKiosk is a white box with a flat label; LEDScreens frozen ('대기 3명 · 진료중 7번'); Sign_10:24 frozen clock",
    "약국: 148 identical unlabeled Product boxes in 4 colours; DispensingMachine/VaccineFridge plain boxes; no pharmacist, 조제대, 약포지 포장기, 약품 서랍장, OTC shelf facing customers, 드링크 냉장고, 결제 단말기, 약봉투",
    "주사실 46x22 with only 2 beds (real 4-6 recliners/beds with curtains, O2/suction outlets, 주사 준비대)",
    "중앙 통로 0% furnished; 후면 홀 has a solid stepped block stair (no nosing/landing), a fake elevator and four fake doors painted on the outside wall (no restroom/staff/storage)",
    "No X-ray/검사실/채혈실, real 화장실, 탈의실, wheelchair, umbrella stand, 열화상 체온계, 무인수납기"
   ],
   "realWorld": [
    "Entrance: 자동문 + 진료시간 시트지, 우산 비닐 포장기, 휠체어 보관, 손소독제 스탠드, 열화상 체온 카메라, 마스크 안내",
    "접수·수납: 하이/로우 카운터, 아크릴 가림막, 모니터 2-3, 카드 단말기 + 서명패드, 영수증/처방전 프린터, 신분증 확인 안내 (2024.5~ 본인확인 의무화), 비급여 진료비 안내판, 볼펜 꽂이, 전화기, 번호 표시기",
    "무인 접수·수납 키오스크 + 번호표 발권기 (딩동 '00번'), 진료실별 대기 순서 TV (이름 마스킹 '김*수'), 건강 정보 TV",
    "대기실: 팔걸이 있는 빔 체어, 정수기 + 종이컵 + 컵 수거통, 잡지 거치대, 어린이 놀이 코너, 공기청정기, 화분, 벽시계, 의료진 소개 액자, 예방접종/검진 포스터",
    "진료실: L자 책상 + EMR/PACS 모니터 2대, 하이백 의자, 환자 회전 스툴, 보호자 의자, 진찰대 (롤 시트) + 발판, 천장 레일 커튼, 청진기, 벽걸이 이경/검안경 세트, 혈압계, 체온계, 설압자/알콜솜 통, 세면대 + 페이퍼타올 + 손소독제, 노란 의료폐기물 박스, 손상성 폐기물 통, 면허증 액자, 문 앞 '진료 중' 표시등",
    "주사실·수액실: 리클라이너/침대 3-6, U자 커튼 레일, 수액 거치대, 주사 준비대, 약품 냉장고, 처치 카트, 손상성 폐기물 통, 세면대, 산소/석션 아울렛",
    "약국: 조제실 (약품 서랍장, ATC 분포기, 조제대, 냉장고), 투약구 + 상담 창, OTC 진열 (박카스, 판피린, 타이레놀, 까스활명수, 파스, 밴드), 드링크 쇼케이스, 계산대 + 카드단말기, 약봉투, 처방전 수거함",
    "검사: 채혈 의자, 심전도실, 초음파실, X-ray실 (납문, '촬영중' 경고등), 탈의실 + 검사복 + 사물함",
    "공용: 남/여 화장실, 침대용 엘리베이터 (호출 버튼, 층 표시), 논슬립 계단 + 층 표시, 소화기 + 옥내소화전, AED, 유도등, CCTV 스티커, 안전 손잡이; 마감: 600x600 매입 LED, 데코타일/장판, 걸레받이, 실명판 + 점자"
   ],
   "interactionIdeas": [
    "번호표 발권기: '번호표 뽑기' -> ticket pops from TicketSlot, LEDScreen counts down + 딩동 '0NN번 환자분 접수창구로' (reuse the GwangalliFeatures/ATM 번호표 pattern), then points to HospitalPrompt_desk",
    "자동 혈압계 (1F BPMonitor / 2F BPMachine): '혈압 재기' -> cuff inflate, display counts up to a value from the client-readable Player.Fatigue attribute ('병원 진료를 권해요' when high)",
    "체중계 (1F Scale, 2F Scale + HeightRod): '키·몸무게 재기' -> rod slides to head, cm/kg/BMI readout",
    "정수기 x2: '물 마시기' paper-cup prop + drink pose",
    "MagazineRack '잡지 보기' (local SurfaceGui pages); Sanitizer '손 소독' (pump + sparkle + sound); KidsCorner '블록 쌓기'",
    "TV / LEDScreen: set the Messages attribute so Screens cycles 건강 정보 / 대기 번호; '채널 바꾸기'",
    "Curtains: '커튼 치기/걷기' (client tween along the rail)",
    "Glass doors Door_진료실 1 / 주사실: swing open on approach (leaves already CanCollide=false) + '진료 중' lamp while GwTreating is set",
    "Elevator: '엘리베이터 타기' doors slide, indicator 1->2, fade to 2F (NPC spots lift1/lift2 at -548,332; needs a 2F door)",
    "DeskBell '벨 누르기'; after a Health 'cured' event '처방약 수령' at the pharmacy counter (약봉투 prop)",
    "MedicineCabinet / VaccineFridge / DispensingMachine: glass door opens, fridge light + hum, 약포지 printing animation",
    "Wheelchair (new): '휠체어 타기'; fire exit PushBar / new AED box cosmetic open"
   ]
  },
  {
   "name": "광안 메디컬 의원 2F (입원실 201 · 202 · 간호사실 · 복도 · 휴게실 LOUNGE · 계단홀 · 건강검진센터)",
   "path": "Workspace.Gwangalli.hospital['광안 메디컬 의원'].2F (shell: ['광안 메디컬 의원 (건물)'] Window x14, PartyWall x3, SlabCut, Roof)",
   "bounds": "(-575.5,21.08,263.0)..(-454.8,29.45,340.7)  [Floor2 top 21.08 (4 slabs leaving the stair void x -519..-497 z 324..336), CeilingBoard bottom 29.45 -> 8.4-stud rooms; street side = Window glazing 14.9x8 x8 + SpandrelGlass]",
   "enterable": true,
   "rooms": [
    {
     "name": "입원실 201 (WardBed_A/B, TV, wardrobe, 2 chairs, blind; door x -494.8 z 290.5)",
     "center": [
      -477.5,
      25.3,
      278
     ],
     "size": [
      43.5,
      8.4,
      24.5
     ],
     "floorY": 21.08,
     "ceilingY": 29.45
    },
    {
     "name": "간호사실 (NurseDesk facing the corridor, med fridge, chart rack, side desk)",
     "center": [
      -514.4,
      25.3,
      277.3
     ],
     "size": [
      26.9,
      8.4,
      25.2
     ],
     "floorY": 21.08,
     "ceilingY": 29.45
    },
    {
     "name": "입원실 202 (WardBed_A/B; door x -534.8 z 289.2)",
     "center": [
      -551.3,
      25.3,
      275.9
     ],
     "size": [
      43.5,
      8.4,
      23.2
     ],
     "floorY": 21.08,
     "ceilingY": 29.45
    },
    {
     "name": "2F 병동 복도",
     "center": [
      -514.5,
      25.3,
      292.6
     ],
     "size": [
      117,
      8.4,
      4.4
     ],
     "floorY": 21.08,
     "ceilingY": 29.45
    },
    {
     "name": "휴게실 · LOUNGE (2 sofas, low table, TV, 2 vending, purifier, 2 table sets)",
     "center": [
      -475.2,
      25.3,
      317.4
     ],
     "size": [
      38.3,
      8.4,
      38.3
     ],
     "floorY": 21.08,
     "ceilingY": 29.45
    },
    {
     "name": "계단 · 엘리베이터 홀 (stair arrives at x -519 z~330; glass rail around the void; bench)",
     "center": [
      -509.7,
      25.3,
      317.8
     ],
     "size": [
      26.4,
      8.4,
      40.5
     ],
     "floorY": 21.08,
     "ceilingY": 29.45
    },
    {
     "name": "건강검진센터 (desk, scale, BP station, eye chart, hearing booth, ECG cart, 1 bed; 8-wide glass door x -543..-535 z 295)",
     "center": [
      -549,
      25.3,
      316.1
     ],
     "size": [
      47.8,
      8.4,
      40.4
     ],
     "floorY": 21.08,
     "ceilingY": 29.45
    }
   ],
   "props": [
    "Shell: Floor2 x4 SmoothPlastic (214,226,222); WardWall x6, BackWall2 x4, LoungeWall 42.6, CheckupWall 42.6 (plaster, 8.45 tall); WayBand mint 118.4; SoffitLining; Ceiling2F = CeilingBoard + 45 TBar; glass stair balustrade (2 RailGlass 23x2.7 + 2 Rail + 10 RailPost)",
    "Ward_201 / Ward_202 (69 parts each): 2 WardBed each (home-style bed: wooden Headboard/Footboard, Mattress, BedSeat Seat 'ward' tag HospitalBed, Blanket, Pillow, one SideRail, L CurtainRail + one Curtain 4.1x7.35, IVPole + IVBag + IVLine, BedsideCabinet + wood top + WaterCup); 2 visitor slab stools; ScreenHousing + LEDScreen 6.4x3.6 'TV 201/202'; 2 CallPanel 0.8x1 slabs '호출'; Blind 43.4x2.85 flat fabric slab + BlindBox over the street windows; Wardrobe 2.4x7.8x5 box + one seam strip; Bin cylinder; LightPanel 36.6x6 x2 + CassetteAC",
    "NurseStation (40 parts): NurseDesk (ToeKick, FrontPanel 16x3.3 mint, Ledge, WorkDesk, WorkTop, DeskGlow) + Detail 2 Monitors + DeskBell; NurseSign '간호사실'; 2 slab chairs; MedFridge 4x5.6x4 box + glass; ChartRack 6x6x2.2 box + 6 Chart slabs; SideDesk 8x3x3 + Monitor '병동 현황 · 201 2명 · 202 1명'; Plant; 2 LightPanels (no SurfaceLight)",
    "Lounge (129 parts): Sofa x2 (plinth, base, backrest, arms, 3/2 Seat, back cushions - decent); LowTableTop + leg block; 4 floor Cushions; ScreenHousing + LEDScreen 9x5 '광안리 뉴스'; VendingMachine x2 (Body 3.4x6.2x2.6 blue/red box, Display slab NightNeon, 15 Can slabs 0.4x0.8x0.2, no buttons/coin slot/out tray); WaterPurifier + panel; TableSet x2 (round top, cylinder leg + disc, 4 Seat + 4 ChairBack + 16 ChairLeg); Plant x2; Sign_조용히 쉬어 가세요; 2 LightPanels 32x8 (no SurfaceLight)",
    "CheckupCenter (70 parts): DeskTop 12x3.4 + DeskBody + Monitor '검진 결과 · 정상'; 4 slab chairs; Scale 3x0.3x3 + HeightRod 7.4 + ScaleDisplay '체중 · 신장 · BMI'; BPStation 6x2.8x4 box + BPMachine '자동 혈압계 / 팔을 넣어 주세요' + BPCuffRing; Sign_시 력 표 4.2x6.8 ('C O ㄷ E / ㅁ O C ㄷ / E ㄷ O ㅁ') + EyeLine floor strip; CheckupBed (same bed, 'treat'); HearingBooth SOLID 8x8.6x8 metal cube + BoothWindow + '청력 검사실'; ECGCart (top, body, ECGUnit '심전도'); Sign_건강검진 안내 '접수 → 신체계측 → 혈압 → 시력 → 상담'; Plant x2; 3 LightPanels 44x8 (no SurfaceLight); CassetteAC",
    "LandingHall (22 parts): WaitingBench (4 seats), sign '← 휴게실 · 입원실 ↓ · 검진센터 →', ExitSign, FireExtinguisher, Plant, 2 LightPanels",
    "Corridor: LightPanel 36x4 (only SurfaceLight on 2F besides the two wards) + 72x4; Door_입원실 201 / 202 / 건강검진센터 (aluminium jambs, translucent leaf t0.35 CanCollide=false, rails, handle, mint sign)"
   ],
   "gameplay": [
    "Ward beds (4 BedSeat, tag HospitalBed, BedKind 'ward'): Health collapse/ambulance and Arms/KOSystem hospital transport seat the player here via Health.findBed('ward'); keep Seats, CFrames and tags",
    "CheckupBed BedSeat 'treat'. Law/Hospital 2F spots (y 21.2): lift2 (-548,332) [NO elevator door on 2F; NPCs appear by the checkup-centre back wall], landing (-540,294), corr2 (-520,290), station (-515,284), w201_door (-497,293), w201 (-480,283), w201_bed (-466,282), w202_door (-537,292), w202 (-550,281), w202_bed (-540,281), check_door (-543,298), check (-552,312), lounge (-478,311); nurses 'typing' at the station and 'clipboard' at beds, inpatient + guardian at w201_bed; walk grid built from server parts at start",
    "Sofa/TableSet Seats + chairs: Interact sittable scan (GwSittable); LEDScreen tag on 2 ward TVs + lounge TV (static)",
    "2F windows (Window x8, tag NightWindow, Zone office, LitChance 0.7): lit at night from outside - an interior that adds real lights should keep/replace this",
    "Not used by any system: vending machines, water purifier, eye chart, scale, BP machine, hearing booth, ECG cart (decoration only)"
   ],
   "emptyOrCrude": [
    "Occupancy: ward 201 27% (12x12 empty at -480.2,272.7); ward 202 28% (12x12 at -552,271.3); nurse station 51%; lounge 24% (14x14 at -488.3,328.2); stair hall 11% (18x18 at -512.9,311.5); checkup centre 19% (24x24 at -561.9,312.9); corridor 16%",
    "건강검진센터 is the emptiest room: 48x40 with a 24x24 bare centre and no light source (3 neon slabs only); hearing booth is a solid grey cube; eye chart is not a real 한천석/란돌트 chart; no 탈의실, 채혈실, X-ray, 초음파, 내시경, 인바디, 대기 소파",
    "입원실 201/202 are 43x24 (~15x8 m) holding 2 beds (real 2인실 ~4x5 m, 다인실 4-6 beds); wooden home beds with one rail + one curtain panel; no 전동침대, overbed table, headwall (산소/석션/조명/호출), 보호자 침대, in-room 화장실, 냉장고, 사물함, door name plate",
    "No real lights in nurse station, lounge, stair hall, checkup centre (3 SurfaceLights on all of 2F)",
    "Vending = coloured box + flat display + 15 slab cans; lounge table a block; no microwave, 커피 자판기, cups, 충전 스테이션",
    "No 2F elevator door (Law/Hospital NPCs teleport to lift2 -548,332)",
    "Corridor: bare walls, no handrails, no 손소독제 at ward doors, no name plates, no linen/투약 cart, no wheelchair"
   ],
   "realWorld": [
    "입원실: 전동 병원침대 (리모컨, 양측 사이드레일, 바퀴 브레이크, 회색 플라스틱 head/foot panels), 헤드월 유닛 (산소·석션, 콘센트, 개별 조명, 호출 버튼), 천장 U자 커튼 레일 + 병상별 커튼, 오버베드 테이블 (식판), 보호자 간이침대/접이식 소파, 사물함·옷장, 소형 냉장고, 벽걸이 TV, 병실 화장실 + 샤워, 손소독제, 수액 거치대, 휠체어, 환자 명패 (이름 마스킹), 블라인드",
    "간호사 스테이션: 오픈 카운터 + EMR 모니터 여러 대, 환자 현황판, 투약 카트, 차트 카트, 약품 냉장고, 전화기, 프린터, 호출벨 수신 패널, 손소독제",
    "휴게실: 소파, 테이블, TV, 음료 + 커피 자판기, 정수기, 전자레인지, 신문, 충전기, 창가 의자 (광안대교 뷰)",
    "건강검진센터: 접수 + 순서 안내 모니터, 탈의실 + 사물함 + 검진복, 자동 신장 체중계, 인바디, 자동 혈압계 부스, 한천석 시력표/자동 시력계, 방음 청력 부스 (헤드폰 + 응답 버튼), 채혈실 (채혈 의자, 채혈관 랙, 원심분리기), 소변 검사 창구, 흉부 X-ray실 (납문 + '촬영중' 등), 심전도 침대, 초음파실 (어두운 방), 내시경실 + 회복실, 구강 검진 체어, 상담실",
    "계단·엘리베이터 홀: 침대용 엘리베이터 문 + 층 표시 + 호출 버튼, 층 안내도, 유도등, 소화전, 의자"
   ],
   "interactionIdeas": [
    "Ward bed '병실 휴식': lie on a free ward bed (BedSeat is a Seat; HospitalBed is excluded from Interact sittables -> small server op or GwPose 'lie') with TV on and curtain closing",
    "CallPanel '간호사 호출' -> chime + lamp on a nurse-station board; optional server hook sending a Law/Hospital nurse to w201_bed / w202_bed",
    "오버베드 테이블 '환자식 먹기' (죽 tray prop)",
    "Ward/lounge TV '채널 변경'; blind '블라인드 올리기/내리기'",
    "Vending x2: tag server-side as Interact kind 'vending' (GwInteract + GwInteractKind/Id/Label + GwItems 'water,ion,coffee,sikhye') so the existing '음료 뽑기' purchase works; can drops into the tray",
    "'건강검진 코스' mini quest: desk -> 체중계 -> 혈압계 -> 시력표 (Landolt C mini game) -> 청력 부스 (beeps) -> 심전도 bed (ECG line) -> result sheet; final step calls the existing HealthRequest 'checkup' op",
    "Nurse station '차트 보기' panel (201/202 patients), 투약 카트 drawers",
    "New 2F elevator door at the checkup back wall (x~-548): '1층으로' fade ride",
    "Lounge: 정수기 '물 마시기', 전자레인지 '데우기', '폰 충전', 창가 '광안대교 보기'"
   ]
  },
  {
   "name": "광안 메디컬 의원 building shell, roof and exterior service areas (구급차 베이 · 후면 마당 · 옥상)",
   "path": "Workspace.Gwangalli.hospital['광안 메디컬 의원 (건물)'] (Floors=2) + ['광안 메디컬 의원'].AmbulanceBay / BackYard / Forecourt / Planter / Bench / StandingSign + PlotPaving",
   "bounds": "building (-576.5,6.5,261.4)..(-453.8,35.3,341.7); PlotPaving 168.6x138 at (-515.8,6.3,322.6); AmbulanceBay (-453.6,6.6,267.9)..(-430.7,15.7,305.9); BackYard (-576.7,6.6,340)..(-457.7,12,391)",
   "enterable": false,
   "rooms": [
    {
     "name": "구급차 베이 (BayLine 22x38, BayFill, 6 hatch stripes, Car_Ambulance 'Hyundai Solati 119', 2 bollards, BaySign '구급차 전용')",
     "center": [
      -442.6,
      9,
      286.9
     ],
     "size": [
      22,
      6,
      38
     ],
     "floorY": 6.6
    },
    {
     "name": "후면 마당 (YardAsphalt 119x51, 4 parking lines, Car_Sonata + Car_Kia Ray, 4 OutdoorAC, WasteStore 의료폐기물 보관소)",
     "center": [
      -517.2,
      8,
      365.5
     ],
     "size": [
      119,
      5,
      51
     ],
     "floorY": 6.6
    },
    {
     "name": "옥상 (Roof 119.9x75.9, parapet 3.5, Penthouse with RoofDoor, WaterTank, 3 ACCondenser, VentStack) - no stair reaches it",
     "center": [
      -515.1,
      33.6,
      301.6
     ],
     "size": [
      119.9,
      3.5,
      75.9
     ],
     "floorY": 32.1
    }
   ],
   "props": [
    "Facade 1F: 17 ShopWindow panes 6.1-6.6 wide t0.5 + 21 Mullions + rails, Fascia 117.8x3.4 + neon stripe + mint stripe, Sign_광안 메디컬 의원 44x3.2, Sign_365일 진료, CrossBox + 2 green CrossNeon, glass lettering (건강검진 · 영양주사 / 독감 예방접종 / 진료 접수 · 번호표 / 응급 진료), Canopy 16x4.6 + 2 CanopyLight + SurfaceLight, Threshold, AutoDoor_Hospital",
    "Facade 2F: 8 Window 14.9x8 (NightWindow) + 6 small windows, SpandrelGlass, Transom, 21 Mullions, lettering band '입원실 · 건강검진센터 · 영양주사', vertical blade sign '광안메디컬의원'",
    "Forecourt 120x9, 6 Planter, 2 Bench, StandingSign; WallServices (AC unit + cage, DownPipe, yellow GasPipe)"
   ],
   "gameplay": [
    "AmbulanceBay/Car_Ambulance = ambulance TEMPLATE for Law/Police.tplData('ambulance') - do not rename/move/strip; Law/Rescue drives to BAY (-442,7.2,290) then walks to ENTRANCE (-496,7.2,262); EMS base (-450,7,262) radius 40/30",
    "Destination '광안메디컬' (-495.8,7.1,261.2): quick travel, Health nearClinic (+20), Patients release point",
    "BackYard cars are map parked cars (car-interior system handles 'Car_' models)"
   ],
   "emptyOrCrude": [
    "Roof unreachable (Penthouse/RoofDoor solid, no stair above 2F)",
    "No 응급실 side door from the ambulance bay (bay ends at the east wall x -455.6); paramedics walk round to the front AutoDoor",
    "Street glass shows the lobby, waiting room and consult room (behind FrostedFilm 44.6x6.6) - interior must read well from outside"
   ],
   "realWorld": [
    "의원 building: 1층 약국 (녹색 십자는 약국용) + 의원 간판, 측면 층별 안내 간판, 진료시간 시트지, 주차 안내, 구급차 전용 노면 표시, 잠금식 의료폐기물 보관 창고, 실외기 거치대, 옥상 물탱크/실외기"
   ],
   "interactionIdeas": [
    "Side 응급 출입문 on the east wall facing the bay (x -455.6, z~285) with '응급실' light box, opening into the 주사실 near TreatBed1 (Patients.TRANSIT)",
    "Optional roof access via a new flight from the 2F stair hall (rooftop garden with 광안대교 view)"
   ]
  },
  {
   "name": "광안 오토 쇼룸 (신차 · 중고차 전시장 + 상담 데스크 + 고객 라운지)",
   "path": "Workspace.Gwangalli.garage['광안 오토 정비소 & 중고차'].쇼룸 (+ venue-root GroundSide/GroundBack/Fascia/ShopWindow/AutoDoor_Garage/Staff; 2F = ['광안 오토 (쇼룸 건물)'].Core solid block)",
   "bounds": "(-601.0,6.67,419.7)..(-528.9,21.45,473.8)  [ShowroomFloor 70.4x51.8 top 6.67 (light marble-like); CeilingBoard bottom 21.45 -> 14.8-stud hall; glass storefront faces +Z at z~472-474, AutoDoor at x -565.8; inner walls = GroundSide x -599.2 / -530.6 and GroundBack z 422.0 (brick-type exterior material 196,188,174); rotated ~-1.9 deg]",
   "enterable": true,
   "rooms": [
    {
     "name": "전시 홀 (6 turntables 17-stud dia in 2 rows of 3: z~438-440 and ~459-461, x -589/-565/-541)",
     "center": [
      -564.9,
      14.1,
      450.3
     ],
     "size": [
      68.4,
      14.8,
      42.4
     ],
     "floorY": 6.67,
     "ceilingY": 21.45
    },
    {
     "name": "후면 띠: 상담 데스크 (x -593..-579) + 고객 라운지 (x -552..-533) along the back wall z 422-429; Sign_광안 오토 at x -570",
     "center": [
      -564.9,
      14.1,
      425.5
     ],
     "size": [
      68.4,
      14.8,
      6.9
     ],
     "floorY": 6.67,
     "ceilingY": 21.45
    },
    {
     "name": "상담실 · 계약 (Door_office on the west wall x -599.6 z 429.8) - FAKE, no room",
     "center": [
      -600,
      10.4,
      429.8
     ],
     "size": [
      0.2,
      7.5,
      3.4
     ],
     "floorY": 6.67,
     "ceilingY": 14.2
    },
    {
     "name": "화장실 남/여 (Door_restroom on the back wall x -531.5 z 421.9) - FAKE",
     "center": [
      -531.5,
      10.4,
      421.9
     ],
     "size": [
      3.4,
      7.5,
      0.2
     ],
     "floorY": 6.67,
     "ceilingY": 14.2
    },
    {
     "name": "2F (Core 70.2x11x52.1 dark solid block behind 2F windows) - not enterable",
     "center": [
      -564.9,
      28,
      446.7
     ],
     "size": [
      70.2,
      11,
      52.1
     ],
     "floorY": 22.9,
     "ceilingY": 33.5
    }
   ],
   "props": [
    "6 Display cars (큐비 mint, 플래그십 black, 미드 세단 white, 트레일 SUV red, 패밀리 9인승 silver, 1톤 트럭 navy; 60-85 parts each with NearLOD Detail + Interior; tag GarageDisplayCar, NoDrive) on 6 Turntable discs (0.34x17x17, tag GarageTurntable, attribute Centre, GarageKind) + 6 neon TurntableRim 17.5",
    "6 PriceCard 3.6x2.2 on StandPost 3.2 + StandFoot (tag GaragePrompt; prompt '구매 / 시승' moved by the server to Attachment GaragePromptAnchor 1.6 below); 2 DiscTag floor stickers '첫 차 추천' / '드림카'; Runway 5x22.9 dark carpet from the door",
    "SalesDesk (14 parts): DeskBody 14x3.6x3 navy box, DeskTop slab, DeskLED neon, DeskSign '구매 상담 · 렌트 · 내 차 관리', Monitor 2.6x1.85 slab + stand, Keyboard slab, Brochures box, 2 customer chairs (1.8 slab seat + back + post) at the WEST end (x -595.8), not facing the desk",
    "Lounge (10 parts): Sofa = one 14x1.8x3 box + SofaBack 14x2x1 box, CoffeeTable 6x1.4x2.2 wood block, one Magazine slab, LoungeTV 10x5.2 '광안 오토 · 이달의 특가', WaterPurifier box, 2 PlantPot + 2 Plant mesh",
    "FitOut: 3 CassetteAC, 3 SmokeDetector, 2 SwitchPlate, 3 Baseboard strips, ExitSign, Door_office + Door_restroom (flat leaf on the wall), Sign_광안 오토 16x4.2 '믿을 수 있는 중고차 · 정직한 정비'; CCTV; FireExtinguisher",
    "Lighting: 4 LightPanel neon strips (3 x 0.8x42 with SurfaceLight Range 26 + 1 x 66x0.8) on a plain CeilingBoard; no spotlights on cars",
    "Storefront: 8 ShopWindow 7.6x11.6 + 10 Mullions, Fascia 69.8x3.4 + orange neon stripe, Sign_광안 오토 정비소 & 중고차 46x3.3, Sign_중고차 할부 OK, glass lettering '오늘의 특가 · 중고 큐비 15만원' / '시승 무료 · 60초' / 'OPEN 09:00-22:00'",
    "Staff: 박사장 (사장님) rig (tag GarageStaff, Role owner) behind the desk at HRP (-586.2,9.7,422.4); GarageDesk_office anchor (-586.4,9.2,428.7) '상담 · 렌트 · 내 차'"
   ],
   "gameplay": [
    "GwangalliGameplay/Garage (server): venue root by tag GarageShop / name under Workspace.Gwangalli.garage (attributes Place '광안정비소', Route = 11 test-drive points); fixMapBoards at start: moves GaragePrompt prompts to Attachment 'GaragePromptAnchor', slims PricePylon PylonPost, trims Mullion/Jamb in front of glass lettering, nudges LIVE_BOARDS (LoungeTV, PylonHead, PriceBoard, LEDSign, DeskSign, PriceCard) 0.003 and sets GwLiveBoard - keep those names",
    "GwangalliGarage client: GaragePrompt -> Sheet '구매'; GarageDesk office -> Sheet '내 차'; Sheet.startShow(kind) SPINS the GarageTurntable disc + GarageDisplayCar around the disc's Centre (BulkMoveTo every frame) and frames the camera -> keep an ~8.75-stud radius clear around each Centre, never weld props to the disc",
    "ServerScriptService.GwangalliShowroom (after 6 s): clones one static car per GS.MODELS entry (13 real models: K5, 쏘렌토, G90, GV80, 싼타페, 쏘나타 16/06, 아이오닉 5 N, 아반떼 N, 카니발, K7, EV6, 투스카니, 옵티마) into Workspace.GwangalliShowroom (tag GarageShowroomCar, prompt '신차 보기') on the first FREE 2-stud spots of ShowroomFloor, then apron, then lot within 95, box-testing SERVER parts. Client-only furniture is invisible to that test -> read Workspace.GwangalliShowroom at runtime and avoid those boxes (server-side props would push those cars to the lot)",
    "Destination '광안정비소' (-566,7.1,479), GarageReturn (-560,7.1,478.6) (test drivers put back here), GarageSpawn (-500,7,480.4) 6.6x1x17; AutoDoor_Garage (tag AutoDoor, OpenOffset ±3.75)",
    "Interact sittable scan may tag ChairSeat / Sofa (GwSittable); Journey 'first_car' (place 광안정비소 radius 40); StreetSigns HOST_ANCESTOR 'garage'; Annex HOST_VENUES.garage"
   ],
   "emptyOrCrude": [
    "Occupancy (turntables excluded, cars counted): 50%, largest empty square 12x12 at (-578.1,447.1) - the hall is mostly cars; the crude part is everything that is NOT a car",
    "Inner walls are the building's exterior brick-type shell on all three sides, 14.8 tall and bare except one sign, a TV and two fake doors (real: white/brand feature walls, LED media wall, glass offices)",
    "Customer lounge = a 14-stud box sofa + box back + block table: crudest furniture in the venue; no coffee machine, drink fridge, cups, magazine rack, 상담 테이블",
    "Sales area: one box desk, customer chairs at its side; no 상담 테이블 sets, no 계약실 (Door_office painted on the wall), no tablet/kiosk, paperwork, card terminal, key box",
    "Ceiling: flat board + 4 neon strips; no track spotlights on cars, no baffles/banners",
    "Restroom fake; no 출고 존 / ceremony area, no wheel/tyre or accessory display, no paint sample board, no 성능·상태 점검기록부 board",
    "2F is a solid dark block behind black glass"
   ],
   "realWorld": [
    "Korean new-car showroom (현대/기아/제네시스 지점): glass facade + brand pylon, 4-8 display cars (some on turntables) each with 사양 스탠드/태블릿, ceiling track spotlights per car, brand wall + LED media wall, 상담 테이블 4-8 sets (2-4 chairs, brochure holder, tablet), entrance 리셉션, 계약실 (glass partition, table, 계약서, 카드단말기), 출고 존 (curtain/screen, 꽃다발, 포토월), 컬러·내장재 샘플 보드, 휠/타이어 전시, 액세서리 진열 (블랙박스, 틴팅, 매트, 방향제), 고객 라운지 (캡슐 커피머신, 음료 냉장고, 정수기, 소파, 잡지, TV, 키즈 공간), 카탈로그 랙, 시승 예약 안내, 화장실",
    "중고차 매매상사: windscreen price cards (연식·주행거리·가격·사고 유무), 성능·상태 점검기록부 게시, 할부·리스 안내, 차량 키 보관함, 사무 책상 여러 개"
   ],
   "interactionIdeas": [
    "Lounge 캡슐 커피머신 '커피 내리기' (cup prop, steam, drink pose), drink fridge '음료 꺼내기', 정수기 '물 마시기', catalogue rack '카탈로그 보기' (GS.MODELS specs)",
    "상담 테이블 tablet/kiosk '차량 비교' -> opens the existing Sheet 쇼룸 tab",
    "Paint sample board: tap a chip -> local recolour preview of the nearest display car (GS.paintParts)",
    "Brand media wall / LoungeTV slideshow of GS.MODELS names + prices",
    "출고 존: on a 'buy' GarageEvent ('cars' changed) play a local delivery ceremony (curtain, confetti, 사장님 hands a key prop, photo pose)",
    "Key cabinet: '시승 키 받기' -> key prop then the existing testdrive op",
    "Wheel/accessory displays with price tags; display-car '운전석 앉아 보기' (NoDrive) via the car-interior module"
   ]
  },
  {
   "name": "광안 오토 정비 베이 (2-post lift x2 · 공구벽 · 오일 선반) + 타이어 코너",
   "path": "Workspace.Gwangalli.garage['광안 오토 정비소 & 중고차']['정비 베이'] + .TireCorner + Staff/김기사 (정비사), GarageDesk_service",
   "bounds": "bay (-524.7,6.66,421.4)..(-473.3,22.5,477.0) [BayFloor 48x54 top 6.66 grey; BayWall x3 16 tall (206,210,214); open front at z~476 with two rolled-up RollUpDrum between 3 BayColumns; BayRoof bottom 22.5, 3 Truss at y 21.6]; tire corner (-474.0,6.6,439.0)..(-469.8,16.3,475.0)",
   "enterable": true,
   "rooms": [
    {
     "name": "정비 베이 (리프트 1 x -518..-506 raised with 미드 세단 at 5.2; 리프트 2 x -494..-481 lowered = drive-in; ToolWall along the back wall z 423-426; OilShelf on the east wall)",
     "center": [
      -499,
      14,
      450
     ],
     "size": [
      46,
      14.6,
      52.1
     ],
     "floorY": 6.66,
     "ceilingY": 21.3
    },
    {
     "name": "정비 대기 구역 (GarageZone_service 14x8x30 over lift 2 + ZoneMark at z 469.8)",
     "center": [
      -488.1,
      11,
      453.5
     ],
     "size": [
      14,
      8,
      30
     ],
     "floorY": 6.66,
     "ceilingY": 15
    },
    {
     "name": "타이어 코너 (CornerCanopy 4.8x28 at y 16.1 between bay and wash)",
     "center": [
      -471.9,
      11.3,
      457
     ],
     "size": [
      4.2,
      9.4,
      36
     ],
     "floorY": 6.6,
     "ceilingY": 15.9
    }
   ],
   "props": [
    "리프트 1 (정비 중) (tag GarageLift, Raised true, LiftHeight 5.2, Role display): 2 red LiftPost 1.3x13.2x1.7, 2 LiftFoot, 2 LiftCarriage (LiftMoves), 4 LiftArm 0.6x0.3x7.2 + 4 LiftArmPad (LiftMoves), LiftTopBar 12.6, LiftMotor blue box, 2 SafetyLine; LiftCar 미드 세단 (tag GarageLiftCar, 75 parts) raised; LooseTyre",
    "리프트 2 (정비 대기) (Raised false, Role drivein): same 18 parts, arms on the floor",
    "ToolWall (66 parts): Pegboard 28x7.2 + header; 10 Wrench, 6 Screwdriver + tips, Hammer, 4 SocketSet, TapeMeasure, 7 Plier (all 0.1-thick slabs); Workbench 16x0.3x2.3 + 2 leg slabs, Vise box, PartsTray; ToolChest 4.8x5.64x2 red box + 6 painted DrawerLine strips + handle; CompressorTank cylinder + motor box; HoseReel; OilShelf 1.2x7x12 + 8 OilCan boxes; FireExtinguisher; Sign_안전제일 · 리프트 하부 출입 금지",
    "Front: BayFascia 50.4x3.2, Sign_정비 · 수리 · 타이어 · 엔진오일 26x2.4, LEDSign 10x2.5 '● 정비 중 · 친절 정비' (tag GarageLED), ZoneMark '정비 대기 구역 · 여기에 세우세요'",
    "Lighting: 4 LightPanel 8x0.14x1 under the trusses (2 with SurfaceLight Range 22) for a 46x52 bay",
    "TireCorner (34 parts): CornerCanopy + 2 posts, 16 TireStack plain cylinders 0.9x2.5, TireRackShelf + 4 legs + 4 RackTire, 3 OilDrum cylinders + lids",
    "Staff: 김기사 (정비사) rig (tag GarageStaff, Role mechanic) at HRP (-504.1,9.7,459.5) with cap, rag, wrench; GarageDesk_service anchor (-482.1,9.2,470.2) '정비 받기'"
   ],
   "gameplay": [
    "Garage server 'repair' needs the player's car inside GarageZone_service (tag GarageZone, Zone 'service', 14x8x30 at -488.1,11,453.5) or remotely on the lift car; zone enter/leave events - the drive-in path from the bay mouth (z 476) to lift 2 and the zone box must stay free of collidable props",
    "GwangalliGarage/Fx (client) repair: raises every part with attribute LiftMoves (+ the car via DriveBase), sparks + clanks at the wheels, GarageLED blinks; staff idle anim on GarageStaff rigs - never rename/re-parent LiftArm*/LiftCarriage/LiftArmPad or the LED part",
    "GarageSpawn (-500,7,480.4) 6.6x1x17 at the bay mouth: test-drive / towed cars appear here - keep the lane clear",
    "ShopStaff skips (GarageStaff within 9 studs)"
   ],
   "emptyOrCrude": [
    "Occupancy: 21%, largest empty square 22x22 at (-498,435.9) (between the lifts and the tool wall); both 54-long side walls bare 16-tall panels (only oil shelf + one extinguisher)",
    "Missing standard 카센터 equipment: 타이어 탈착기, 휠 밸런서, 얼라인먼트 리프트, 폐유 수거기, OBD 진단기 cart, 배터리 충전기, 플로어 잭 + 잭스탠드, 크리퍼, ceiling air/oil hose reels, 임팩트 렌치, 부품 선반, 폐타이어/폐유 드럼 area, 정비 요금표, 안전 포스터, 고객 대기 창",
    "Floor: one flat grey slab; no epoxy zones, drain channel, oil stains (only 2 SafetyLines per lift)",
    "Lighting dim: 4 small 8x1 panels for ~2,400 sq studs, no high-bay lamps or work lights",
    "Tools are 0.1-thick slabs on a flat pegboard; tool chest a red box with painted drawers; tyres plain cylinders"
   ],
   "realWorld": [
    "카센터 / 1급 정비공장: 2주식 리프트 per bay (control box, safety locks), 4주식 얼라인먼트 리프트 + 센서, 타이어 탈착기 + 휠 밸런서, 질소 충전기, 폐유 수거기, 천장 오일 디스펜서 릴 (엔진오일/ATF/에어), 에어 컴프레서 + 에어 라인, 임팩트·토크 렌치, 빨간 공구 카트, 스캐너 노트북 cart, 배터리 테스터, 브레이크 정비기, 에어컨 냉매 충전기, 잭 & 스탠드, 크리퍼, 부품 선반 (필터, 와이퍼, 패드 박스), 엔진오일 4L 진열, 폐타이어 적치, 폐유 드럼 + 흡착포, 작업등, 세면대, 소화기, 안전 수칙, 정비 요금표 (엔진오일 교환 4만원~), 정비 현황 화이트보드 (차량번호·작업·상태), 유리창 고객 대기실 (TV, 커피) - 블루핸즈/오토큐/스피드메이트 style"
   ],
   "interactionIdeas": [
    "Lift control box on each post: '리프트 올리기/내리기' plays the Fx lift motion locally only when no repair runs",
    "Tool wall '공구 집기' -> held wrench / impact-gun prop + sound; tool cart drawers slide",
    "Tyre changer / balancer '타이어 교체 구경' (wheel spins with readout)",
    "OBD 진단기 '차량 진단' -> fault-code style report from the player's car DriveCondition/DriveDirt, then a button calling the existing 'repair' op",
    "정비 현황 board by GarageDesk_service listing cars with GarageRepairing + progress",
    "Compressor '에어 넣기' (cosmetic tyre pressure); waste-oil caddy rolls under lift 1 with drip particles"
   ]
  },
  {
   "name": "광안 오토 자동세차장 (문형 자동세차 1 bay · 진공 청소기)",
   "path": "Workspace.Gwangalli.garage['광안 오토 정비소 & 중고차'].자동세차장 + Staff/GarageDesk_wash",
   "bounds": "(-470.3,6.66,427.2)..(-439.9,20.7,478.7)  [WashFloor 28x50 top 6.66; WashWall x2 4 tall + WashGlass 8.6 above; WashRoof bottom 20.1; open both ends]",
   "enterable": true,
   "rooms": [
    {
     "name": "세차 레인 (WashGuideLines x -461.2 / -449.2, WashStopLine z 441.9, gantry travel z 433.6 -> 468.6)",
     "center": [
      -455.1,
      13.4,
      452.6
     ],
     "size": [
      25.3,
      13.4,
      50
     ],
     "floorY": 6.66,
     "ceilingY": 20.1
    },
    {
     "name": "side strips beside the lane (x -467.8..-461.6 and -448.8..-442.3) - bare",
     "center": [
      -455.1,
      9,
      452.6
     ],
     "size": [
      25.3,
      4,
      48
     ],
     "floorY": 6.66,
     "ceilingY": 10.5
    }
   ],
   "props": [
    "WashGantry (tag GarageWashGantry, TravelOffset (-1.15,0,34.98)): 2 GantryLeg boxes 1.6x10.6x2.4, GantryBeam 22x1.4x2.8, SprayBar 18.4x0.4x0.4 metal bar (no nozzles), BrushL / BrushR vertical cylinders 3x9.2 (blue/red, tag GarageWashBrush, Axis y), BrushTop horizontal 2.6x7.6 (Axis x) + 3 cores",
    "2 GantryRail 47, DrainGrate 4x24, WashStopLine '정지선 STOP', 2 WashGuideLine 30, 4 WashPost, WashFascia + Sign '🫧 자동세차 · 5,000원', WashGuide board (3 steps), 1 LightPanel 12x1 + SurfaceLight",
    "VacuumStation 2.5x4.54x2 yellow box + one hose cylinder (z 425.5, outside the floor); GarageDesk_wash anchor (-467.2,9.2,473.6) '세차하기'"
   ],
   "gameplay": [
    "Garage 'wash' needs the car inside GarageZone_wash (tag GarageZone, Zone 'wash', 13x8x31 at -455.2,11,456.1); GwangalliGarage/Fx slides the gantry by TravelOffset over the car and back spinning the 3 GarageWashBrush parts about their Axis, then the server sets DriveDirt 0 / DriveShineUntil - lane, zone box and the gantry's 35-stud travel envelope (z 432..471, y up to ~19.8) must stay clear; never re-parent the brushes",
    "GarageDesk_wash prompt is the payment point (5,000원)"
   ],
   "emptyOrCrude": [
    "Occupancy: 7%, largest empty square 26x26 at (-455.7,448.2) (lane must stay open, but both 6-stud side strips are bare)",
    "No entry signal (전진/정지/후진), no payment kiosk (prompt is an invisible box), no dryer arch, no pre-wash gun / foam lance, no tyre rails, no drying zone, no water/foam particles, no mat washer; vacuum station is a box + one cylinder",
    "Brushes are smooth coloured cylinders; gantry legs plain boxes"
   ],
   "realWorld": [
    "문형/터널식 자동세차기: 입구 결제 키오스크 (카드, 현금, 세차권), 코스 선택 (일반/폼/왁스/하부), LED 진입 유도판 + 신호등, 미러 접기 안내, 바퀴 가이드 레일, 고압 프리워시, 폼 분사, 천/스펀지 스트립 회전 브러시, 드라이어 블로워 아치, '세차 완료' 표시, 드라잉존 (타월), 오버헤드 스윙 붐 진공청소기 여러 대 (동전/카드), 매트 세척기, 타이어 광택제, 배수 그레이팅 + 물기"
   ],
   "interactionIdeas": [
    "결제 키오스크 at GarageDesk_wash: '코스 선택' UI (기본 5,000원 -> existing 'wash' op) + receipt",
    "Signal board '전진' until the car crosses WashStopLine, then '정지', '세차 완료 · 출차하세요' after Fx",
    "Dryer arch + water/foam ParticleEmitters on the SprayBar during the wash (client, keyed on GarageWashing)",
    "Vacuum station '실내 청소' (hose prop + sound; optional DriveDirt reduction via a new server op)",
    "Towel rack '타월로 닦기' wipe emote"
   ]
  }
 ],
 "notes": "Full JSON (identical content + occupancy table): /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/hospital_garage.json. Raw dump of every instance (pos/rot/size/material/colour/attrs/tags/parent id): /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/hg/dump.json; trees: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/hg/hosp_tree.txt, /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/hg/gar_tree.txt, /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/hg/h2f.txt; occupancy /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/hg/occ.json.\n\nSCOPE: Workspace.Gwangalli.hospital = 2,465 instances / 1,901 parts / 49 Seats / 10 lights / 2 prompts; Workspace.Gwangalli.garage = 2,495 instances / 1,855 parts (~1,300 are car models) / 6 lights / 9 prompts. Both models are rotated ~1.9 deg about Y (hospital facade faces -Z at z~264, garage facade faces +Z at z~473); bounds are world AABBs. Material ids in the dump are the place codec's own codes (inferred: m13 Glass, m67 Neon, m10 Metal, m11 SmoothPlastic, m45 Fabric, m77 Wood, m37 Plaster, m28 brick/concrete shell).\n\nHOSPITAL VERDICT: there are plenty of props, and every room has the right object names. The problem is scale and form, not emptiness. Rooms are 2-4x real size (진료실 43x27 for one desk; wards 43x24 for 2 beds; checkup centre 48x40 with a 24x24 bare centre). Occupancy is 11-28% everywhere except the nurse station (51%). Every bed is a wooden home bed with one curtain panel. Every chair is a slab stool on a pole. Ceiling 'lights' are huge neon slabs lying over the T-bar grid, and the whole building has only 9 interior SurfaceLights (none in the checkup centre, lounge, nurse station, stair hall or back hall). There is one uniform floor slab, and the walls are bare (no handrails or baseboards). LED screens and the clock show frozen text. The restroom, staff room and storage doors are fake, the elevator is fake (with no 2F door), the stair is a solid block and the hearing booth is a solid cube. Best plan: keep all gameplay parts and rebuild furniture and fixtures on the client at real scale. Split oversized rooms visually: 진료실 into 진료실 + 검사실/채혈실, wards into 4-bed 다인실 with U-shaped curtains and a headwall, checkup into 탈의실/채혈/X-ray/초음파 cubicles. Add 2x2 LED panels with real SurfaceLights.\n\nGARAGE VERDICT: the showroom floor is about 50% cars (6 detailed display cars on turntables), so it reads busy. Everything around the cars is crude: exterior-brick inner walls, a box sofa and box table for the lounge, one box sales desk with chairs at its side, fake 상담실/화장실 doors, a flat ceiling with 4 neon strips, no spotlights and a solid 2F. The service bay has two good lifts and a decent tool wall, but it is 21% occupied, the 54-stud side walls are bare, it has 4 small light panels, and there is no tyre, alignment or diagnosis equipment. The car wash is a gantry with 3 cylinder brushes and nothing else: no kiosk, signal lights, dryer or water.\n\nMUST-NOT-BREAK CONTRACT (never destroy, rename, re-parent or move these. Hiding them only through client LocalTransparencyModifier/Transparency is OK if collision and attributes stay):\nHospital:\n- Tag HospitalStaff: 2 rigs plus their Motor6Ds; the server poses them.\n- Tag HospitalPrompt: HospitalPrompt_desk at (-514.5,9.4,281.2) and HospitalPrompt_doctor at (-554.4,9.4,278.9), each with its ProximityPrompt.\n- Tag HospitalBed: 8 BedSeat Seats.\n  - exam (-569.6,8.8,283.2)\n  - TreatBed1 (-465.3,8.8,308.6); this is also EMS Patients.TRANSIT\n  - TreatBed2 (-479.3,8.8,308.1)\n  - CheckupBed (-566.1,22.9,329.3)\n  - ward 201 A/B (-466.5,22.9,279.1) and (-488.5,22.9,278.3)\n  - ward 202 A/B (-540.2,22.9,276.6) and (-562.2,22.9,275.9)\n- GwProp=syringe parts on the nurse rig.\n- Destination '광안메디컬'.\n- AutoDoor_Hospital and its OpenOffset attributes.\n- AmbulanceBay/Car_Ambulance (the ambulance template).\n- Door_* model names.\n- The hard-coded path Workspace.Gwangalli.hospital['광안 메디컬 의원'].\n- Law/Hospital NPCs walk a fixed spots graph on a grid built once from SERVER parts. Client furniture is invisible to that grid, so it must stay off the spot-to-spot corridors (exact spots are in the 1F/2F gameplay entries).\nGarage:\n- Tag GarageShop on the root, with attributes Place and Route.\n- GarageDisplayCar x6.\n- GarageTurntable x6 with the Centre attribute. The client spins disc + car, so keep an 8.75-stud radius clear around each Centre.\n- GaragePrompt PriceCards x6 and their GaragePromptAnchor attachments.\n- GarageDesk x3 (office, service, wash).\n- GarageStaff x2.\n- GarageLift x2 (LiftMoves parts) and GarageLiftCar.\n- GarageZone service and wash.\n- GarageWashGantry (TravelOffset) and GarageWashBrush x3 (Axis attribute).\n- GarageLED.\n- GarageSpawn (-500,7,480.4) and GarageReturn (-560,7.1,478.6).\n- Destination '광안정비소'.\n- The LIVE_BOARDS part names.\n- GwangalliShowroom adds 13 more cars on free floor, found from SERVER parts after 6 s. Read Workspace.GwangalliShowroom (tag GarageShowroomCar) and keep client props out of those cars' boxes.\nBoth:\n- Interact GwSittable seats (BenchSeat Seats also carry Sittable=true).\n- NearLOD Detail models, InteriorLight, NightWindow (2F glass lit at night), LEDScreen (attribute Messages) and GwSurfaceGui.\n- StreetSigns HOST_ANCESTORS include 'hospital' and 'garage'.\n\nRUNTIME: no runtime script builds furniture inside either venue. Garage.fixMapBoards only trims boards and bars and moves the PriceCard prompts; Health poses the rigs; GwangalliShowroom adds cars.\n\nSEPARATE HOSPITAL: a second hospital, 광안 종합병원, is built at runtime by GwangalliBuildings/Hospital + Builder/Hospital at site x -704, z 1236 (4F + RF heliport, ShopLife desks, Workspace.GwangalliHospital points, workspace attribute GwB_HOSPITAL). It is not under Workspace.Gwangalli.hospital and was not surveyed here. The Health, EMS and KO systems all target the static 광안 메디컬 의원.\n\nREUSABLE SERVER HOOKS:\n- Interact 'vending' purchase (tag GwInteract + GwInteractKind/Id/Label + GwItems) for the 2F vending machines.\n- HealthRequest checkup/vitamin/treat, plus the client-readable Player.Fatigue attribute.\n- GarageRequest repair/wash/testdrive and GarageEvent.\n- The ATM client's 번호표 pattern, for the hospital ticket kiosk."
}
```

## survey:shops

```json
{
 "venues": [
  {
   "name": "바다옷장 (clothing, ShopId clothing)",
   "path": "Workspace.Gwangalli.shops.바다옷장",
   "bounds": "ShopBounds world AABB (-428.0,6.8,98.7)..(-398.5,16.7,141.4); CFrame centre (-413.25,11.75,120.04), size 28.39 x 9.9 x 41.88, yaw ~181.5 deg (entrance faces world -z). Interior AABB (-428.1,6.8,99.0)..(-398.5,16.9,141.3). Floor top Y 6.8 (Shell/ShopFloor WoodPlanks #d6c2a2), ceiling underside Y 16.7. Entrance = host facade beachfront/구간08 광안로 (만남의 광장) ~ 광안로61번길/테마타워/광안 기념품샵 PORT: 4 ShopWindow T=0.55 + AutoDoor centre (-412.7,10.6,98.7).",
   "rooms": [
    {
     "name": "sales floor (매장)",
     "center": [
      -413.2,
      11.8,
      116.4
     ],
     "size": [
      28.4,
      9.9,
      34.5
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    },
    {
     "name": "fitting booth 1 (피팅룸 1)",
     "center": [
      -403.2,
      10.8,
      137.6
     ],
     "size": [
      7.4,
      8.1,
      7.4
     ],
     "floorY": 6.8,
     "ceilingY": 14.9
    },
    {
     "name": "fitting booth 2 (피팅룸 2)",
     "center": [
      -411.9,
      10.8,
      137.4
     ],
     "size": [
      10,
      8.1,
      7.4
     ],
     "floorY": 6.8,
     "ceilingY": 14.9
    },
    {
     "name": "mirror lounge / staff door nook",
     "center": [
      -422.4,
      11.8,
      137.1
     ],
     "size": [
      11,
      9.9,
      7.4
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    },
    {
     "name": "show window zone (쇼윈도)",
     "center": [
      -412.7,
      11.8,
      101.1
     ],
     "size": [
      28.4,
      9.9,
      3.9
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    }
   ],
   "props": [
    "Show window: WindowPlinth x2 (7.4x0.8x3.3 white, collidable) at (-403.8,7.2,101.5)/(-421.6,7.2,101.0) + 3 mannequins + Sign_NEW ARRIVAL 2.6x0.7 — mannequins are 7 stacked primitives (cylinder base/pole, box legs/torso/shoulders, sphere-mesh head), no arms/hands: crude",
    "Mannequins total x5 (3 window + 2 on MannequinPlinth 4x0.6x3.2 at (-413.4,7.1,126.4) with 2 MannequinJacket boxes) — torso colour = outfit, no layering: crude",
    "Left-wall (world +x side) hanging Rail 23 studs + 2 RailBracket at y13.0 centre (-400.1,13.0,116.3); TopShelf 23x0.15x1.6 WoodPlanks above with 10 FoldedStack boxes",
    "Garment x53: flat Fabric slabs 0.22x2.55x2.1 (some 0.2x2.7x2.0 / 3.45 tall), 17 colours, on the wall rail and the free-standing rack — no hangers, hooks, sleeves or tags: very crude (reads as coloured cards)",
    "Free-standing rack: RackPost x2 + RackBar 7.6 + RackFoot 8.4x1.6 (Metal) at (-420.4,12.7,116.2) with garments",
    "Nesting tables: DisplayTable x2 (4.8x0.25x3.2 WoodPlanks on DisplayBase 4.2x2.7x2.6 white, collidable) at (-413.0,9.6,109.4)/(-413.2,9.6,119.4) with 6 FoldedStack boxes each + Sign_SALE 30% — boxes only, no fold lines/prints: crude",
    "Right-wall cubby unit: CubbyBack 12x7.2 + 7 CubbySide + 5 CubbyShelf (WoodPlanks #c9a57a) centre (-425.4,10.8,110.1) with FoldedTees x24 (1.5x0.5x1.1 boxes, 17 colours)",
    "Shoe wall: ShoeShelf x4 (6.8x0.12x1.3) at (-426.8,9.6,120.7) with Shoes x12 (1.3x0.44x0.9 Leather bricks, 3 colours, not paired, no sole/toe): crude",
    "Accessory Pegboard 3.8x4.4 (Wood) at (-399.4,12.0,130.9) with Cap x6 (box + SpecialMesh) and Sunglasses x3 (0.8x0.2x0.28 glass bricks); HatStandBase + HatStandPole 5.6 + 3 Caps; SaleBin 3x2.2x2 (WoodPlanks) at (-410.2,7.9,105.1) with SockPack x6 + Sign_3켤레 10,000원",
    "Cash desk: CashCounter 1.8x3.3x6.2 white + CashTop WoodPlanks + CounterLogoBand (navy) at (-424.0,10.2,128.7); PosBase/PosStand/PosScreen/PosGlow(neon)/CardReader; ShopBag x3 flat Cardboard sheets; Vase + Flowers; PosterFrame + Sign_바다옷장 behind; staff 점원 rig",
    "Fitting area (Shell): FittingWall x3 + FittingHeader 17.5 + BoothDivider x2 form 2 booths; Interior: Curtain x2 (4.5x6.6x0.12 Fabric, collidable, tag GwShopCurtain, attrs Index, OpenOffset (1.89,0,0.05), OpenWidth 0.72), CurtainRod x2, MirrorFrame+Mirror x2 (2.5x6.1 Glass), Hook x2 (1 per booth), BoothStool x2 (leather cylinders), BoothRug x2, BoothTrim lid at y14.9, Sign_FITTING ROOM",
    "Mirror lounge: BigMirrorFrame + BigMirror 3.6x6.9 at (-422.4,10.8,140.6), Pouf (Seat, fabric cylinder), Door_staff 'STAFF ONLY · 창고' (DoorCasing/DoorLeaf/handle/kickplate) at (-417.9,10.4,140.7) — painted door on the back wall, nothing behind",
    "Lighting: TrackRail x2 (28 long, black) + TrackHead x10 + TrackLamp x10 (neon), LightFrame/LightPanel 14.1x2 neon over the fitting area, 3 invisible Shell/LightHost SurfaceLights (InteriorLight, AlwaysOn); Plant x2 (pot + soil + 2 LeafyGrass sphere-mesh clumps)",
    "Signs/Detail: Sign_교환 · 환불 안내, Sign_카드 결제 OK, Sign_사업자등록증 in CertFrame, Sign_CCTV 녹화중, PosterFrame",
    "standard FitOut kit (near-identical in all 7 shops; snack + pharmacy lack the extinguisher, salon + pharmacy lack the door mat): CassetteAC 3.8x0.34x3.8 + vanes/grille, CCTV glass ball + mount, ExitSign 2.6x1.0, FireExtinguisher cylinder + valve + Sign_소화기, SmokeDetector discs, WallSpeaker box, CCTV MonitorScreen (SurfaceGui 4 cams + ● REC), CertFrame x1-2, Sign_Wi-Fi (PW 12345678), Sign_10월 calendar, UmbrellaStand + 2 Umbrella sticks, DoorMat + stripe, Baseboard x3 (hidden inside Shell/Skirting, redundant) — functional-looking but generic, flat boxes, no textures"
   ],
   "gameplay": [
    "ShopLife (addon ServerScriptService.GwangalliBuildings.ShopLife + place ShopLife/Scan): found via tag GwShop; SS.GWSHOP.clothing = {'retail','gw_clothing'} -> pick flow (shelves -> basket -> 계산하기 -> bag), menu SS.MENUS.clothing (린넨 셔츠, 썸머 원피스, 보드 숏츠, 버킷햇, fitting=true). Stations spawn within 75 studs of a player, prompts 6.5 studs.",
    "계산하기 at Point_counter_1 (-421.9,10.1,128.6) (GwShopPoint, PointKind counter, Label '옷 고르기') = shop.gwOrder; PosBase/PosScreen/CardReader also read (rec.pos/display).",
    "고르기 shelves: Scan only accepts parts named WallRack/DisplayTable/Rack/WallBay/Hanger/Gondola/WallShelf/Shelf/Product -> only the 2 DisplayTable parts become shelves; Rail, RackBar, Cubby*, ShoeShelf, Pegboard, SaleBin are invisible to gameplay.",
    "입어 보기 👗 피팅룸 at Point_fitting_1 (-403.2,10.1,132.1) and Point_fitting_2 (-410.4,10.1,132.0) (PointKind fitting) -> life.open view 'fitting'. FitStand_1 (-403.4,9.8,138.0)/FitStand_2 (-410.6,9.8,137.8) (inside booth) and FitOut_1/2 (-403.2,9.8,130.5)/(-410.4,9.8,130.4) are for the map's own Shops server, absent in v7.",
    "GwShopCurtain parts (Curtain Index 1/2, OpenOffset) were meant to slide open via the map's Shops client (GwangalliShops.client, absent) -> in v7 curtains are collidable and never move: booths cannot be entered.",
    "No Bin in the shop -> ShopLife spawns a FoodKit 'bin' via Scan.freeSpot along the hframe +Z edge (for GwShop ShopBounds that is the storefront/entrance side) with prompt 버리기.",
    "GwShopSpot Spot_1 (-401.6,9.8,111.8) Act shop, Spot_2 (-423.4,9.8,109.2) shop, Spot_3 (-422.3,9.8,137.6) look, Spot_4 (-410.2,9.8,116.6) phone: ambient-customer anchors from GwangalliShopsShared contract; no v7 script reads them.",
    "ShopStaff (addon GwangalliGameplay/ShopStaff adoptClerks): 점원 (tag GwShopClerk, Role clerk, Act teller, NpcName 점원) HRP at (-426.4,9.8,128.5) facing the counter -> NpcId/NpcKind attrs, tag GwShopStaff, ProximityPrompt 'StaffTalk' 말 걸기 (9 studs) on HumanoidRootPart; KIND_BY.fashion lines. GwangalliShopService greets via ShopLife bus 'enter' (counter rig within 32 studs of the order point).",
    "DetailLOD (place StarterPlayerScripts/GwangalliWorld/DetailLOD): Interior is a ZoneLOD model (LOD='zone', LODCenter (-413.3,8.4,126.2), LODRadius 121) hidden by LocalTransparencyModifier when the camera is farther; FitOut/Detail sub-models are NearLOD (LOD='near').",
    "GwangalliWorld/Lights handles the 3 SurfaceLights tagged InteriorLight (AlwaysOn).",
    "MUST KEEP (names/positions/collision): ShopBounds, Shell/ShopFloor, Points/* (Point_counter_1, Point_fitting_n, FitStand_n, FitOut_n, Spot_n), Curtain (name+tag+attrs), DisplayTable, PosBase/PosScreen/CardReader, the 점원 rig. Keep the door->counter->booth path and the AutoDoor swing zone (DoorMat (-413.2,6.8,101.0)) clear."
   ],
   "emptyOrCrude": [
    "Garments are 53 flat slabs pressed onto a 0.12 rail: no hangers/hooks, no shoulder shape, sleeves, size rings or price tags.",
    "Folded goods are plain boxes (FoldedStack 1.5x0.65x1.2, FoldedTees 1.5x0.5x1.1) with no fold lines, prints or uneven stacking; display tables hold only 6 boxes each.",
    "Shoes = bricks (not pairs, no soles), caps = box+sphere mesh, sunglasses = glass bricks; no accessory glass case, no jewellery, no bags/beachwear (래시가드, 비치백, 슬리퍼) for a 광안리 shop.",
    "Mannequins are 7-block figures without arms/hands; window has no seasonal vinyl lettering, no spotlights aimed at it (track lamps are ceiling-centre only).",
    "Fitting rooms sealed by collidable curtains that never open in v7; each booth has 1 hook, stool, rug and mirror only — no number plate, '최대 3벌' notice, face covers, slippers or bench for companions.",
    "Cash desk: no barcode scanner, receipt printer, shopping-bag stand, tissue/wrapping, tag remover, impulse items; counter is a white box with a navy band.",
    "Walls are bare plaster except 1 poster; no slat wall, lookbook graphics or full-length mirrors on the sales floor; floor one WoodPlanks slab; ceiling one flat slab.",
    "No EAS anti-theft gate at the door, no stockroom (Door_staff is a painted panel), no steamer, no music: 0 Sound instances.",
    "Storefront glass (host facade) is uniform T=0.55 with nothing applied inside (영업시간 / NEW SEASON vinyl lives only on an exterior Sign_ part)."
   ],
   "realWorld": [
    "쇼윈도: 2-3 full-body mannequins (arms, hands, styled outfit + accessories) on plinths, seasonal vinyl on glass (NEW ARRIVAL / SUMMER SALE), dedicated window spotlights, small props (beach bag, straw hat, surfboard decal for 광안리 vibe)",
    "Entrance: 도난방지 EAS gate pair, door chime, entrance mat, 영업시간 시트지, '카드 OK' sticker",
    "Wall 행거: double-hung chrome/black bars at ~1.2 m and ~1.8 m, uniform wooden or velvet hangers, size rings S/M/L/XL, face-out waterfall arms showing a front-facing garment, hanging price/brand tags",
    "Upper wall: shelf with folded stacks + mini torso forms / hat stands; slat wall or pegboard with accessories (caps, bucket hats, sunglasses, scrunchies, socks)",
    "Cubbies: folded knits/tees in colour gradient, small acrylic price holders",
    "Floor fixtures: nesting tables with folded stacks + sign holders, 4-way / T-stand rolling racks, 균일가 sale wagon (9,900원), sunglasses spinner tower with mini mirror, hat tower, shoe display (one shoe per pair + boxes below), beachwear rack (래시가드, 보드숏, 원피스 수영복, 비치타월)",
    "Accessory glass showcase at the counter (귀걸이, 목걸이, 머리끈) + impulse socks/양말 bin",
    "Fitting rooms: 2-3 booths with curtain or louvred doors, full-length mirror, 3 hooks, stool, slippers + mat, booth number plate, '피팅룸 이용 안내 · 최대 3벌' sign, face-cover (메이크업 방지) basket, 대기 의자 outside",
    "Cash counter: POS + barcode scanner + card terminal + receipt printer, 쇼핑백 stand (S/M/L) under counter, tissue paper, tag remover (택 제거기), gift ribbon, 포인트 적립 tablet, 교환·환불 안내, business cards",
    "Back of house: stockroom with boxes, garment steamer, staff locker",
    "Lighting 3000-3500K track spots on walls and window + linear pendants over counter; full-length column mirrors; BGM speaker; diffuser; plants"
   ],
   "interactionIdeas": [
    "행거 옷 고르기: hanger slides along the rail (TweenService) and the garment pulls toward the player; size picker (S/M/L) on the basket UI",
    "Fitting curtain prompt 커튼 열기/닫기: slide by Curtain.OpenOffset (client tween, server CanCollide toggled); inside at FitStand_n the avatar previews the outfit; mirror pose / selfie camera",
    "Big mirror 거울 보기: camera flips to a mirror view, rotate avatar",
    "Sunglasses spinner: rotate the tower, '써 보기' attaches the item to the head for 30 s",
    "Hat stand / pegboard: try on a cap",
    "Sale bin 뒤적이기: random discounted item card",
    "Shoe wall: sit on the pouf and '신어 보기'",
    "Cash desk: POS beep + receipt print + 택 제거 animation, ShopBag carried in hand after paying (SH.BAG_SECONDS)",
    "EAS gate beeps if you walk out holding an unpaid basket (ties to ShopLife's unpaid-bill dash warning)"
   ],
   "enterable": true
  },
  {
   "name": "광안 서프 & SUP (surf shop + rental, ShopId surf)",
   "path": "Workspace.Gwangalli.shops.광안 서프 & SUP",
   "bounds": "ShopBounds world AABB (-513.2,6.8,96.2)..(-481.4,16.7,135.0); centre (-497.27,11.75,115.59), size 30.61 x 9.9 x 37.88, yaw ~181.8 deg. Interior AABB (-513.2,6.8,96.4)..(-481.4,16.9,135.0). Floor top 6.8 (WoodPlanks #9c8a74), ceiling underside 16.7 (WoodPlanks + 5 exposed Wood beams 30.6x0.7x0.7 at y16.4). Host facade beachfront/구간08 .../광안샤인빌딩/비치용품 · 튜브대여 (ShopWindow x4 T=0.55, AutoDoor centre (-496.7,10.6,96.3)).",
   "rooms": [
    {
     "name": "shop + rental floor",
     "center": [
      -497.1,
      11.8,
      110
     ],
     "size": [
      30.6,
      9.9,
      26.6
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    },
    {
     "name": "behind rental counter (staff side, lockers/shower door on back wall)",
     "center": [
      -497.7,
      11.8,
      130.1
     ],
     "size": [
      30.6,
      9.9,
      8.7
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    }
   ],
   "props": [
    "Surfboard rack on the world +x wall: RackBase 21.5x0.6x2.4 + RackRail 21.5 (Wood) centre (-483.0,7.1,111.7); Surfboard x9 standing flat slabs 1.75x6.6x0.2 (9 colours) + Stringer x9 (0.22x5.8x0.22 box standing proud of the deck) + 1 HangingBoard 2x0.22x8.4 on 2 wires over the centre — square-ended rectangles, no rocker/nose/fins/leash plug/deck pad: crude",
    "Wetsuit wall (world -x side): SuitRail 13 + Wetsuit x10 (0.2x4.9x1.5 Fabric slabs black/navy/teal) + SuitTrim x10 (0.24x0.8x1.7 'shoulder' boxes) centre (-511.0,13.9,106.6) — no hangers, no limb silhouette, no size tags: crude",
    "GearShelf x3 (7x0.14x1.4 Wood) at (-512.0,10.6,118.0) with Fin x4 (boxes), LeashCoil x4 (cylinder discs), SurfWax x4 (bricks)",
    "SUP island: SupRack 6.4x1.4x8 wood block with SupBoard x3 (2.9x0.3x10.5 orange slabs) at (-497.1,7.5,110.0); PaddleShaft x3 + PaddleBlade x3 leaning",
    "VestStand 3.6x5.6x0.6 wood panel with LifeVest x4 (1.5x1.6x0.3 orange boxes) at (-505.3,9.6,116.4)",
    "Bench (Seat, SeatIndex 1) 5x0.3x1.6 + 2 BenchLeg at (-490.4,8.2,118.7); CoolerBox + CoolerLid at (-494.4,7.5,120.7); TowelBasket + RolledTowel x4; FloatRing (two cylinders, 'hole' is an opaque light disc), BeachBall sphere; FlipFlopBoard 3x3.2 with FlipFlops x6 (rubber slabs)",
    "RentalCounter 15x3.3x2.4 (teal WoodPlanks) + CounterTop 15.4x2.75 + CounterBoard/stripe at (-497.5,8.4,124.6); POS kit (PosBase/PosStand/PosScreen/PosGlow/CardReader); SunscreenDisplay 2.2x1.05x1 + Sunscreen x4 cylinders",
    "Back wall (teal plaster): Sign_SURF neon frame (4 NeonTube 5.14) at (-497.8,14.9,134.3), MenuFrame + Sign_RENTAL price board at (-488.9,13.5,134.8) (서프보드 15,000 / 선크림 6,000 / 비치타월 9,000)",
    "Locker x8 (1.8x3.3x1.55 solid grey Metal boxes, 2 rows) + LockerTag x8 (orange squares) at (-508.0,10.5,133.4) — no doors, vents, numbers or keys: crude",
    "ShowerDoor 3.6x7.4 plank panel + Sign_SHOWER · 샤워실 at (-484.7,10.5,134.9) — a door painted on the back wall; there is no shower or changing room",
    "Posters/Detail: Sign_SURF LESSON (초보 환영 · 1:1 강습 문의), Sign_광안리 파도 예보 (static '오늘 0.6 m · 남동풍 · SUP 좋음'), lesson cards 새벽 파도/키즈 클래스/선셋 세션/SUP 투어, 2025 광안리 서핑 대회, Sign_SUP 안전 수칙, CertFrame x2 (사업자등록증, 수상레저 사업 등록증), Sign_렌탈 · 강습 예약",
    "Lighting: LightFrame/LightPanel 12x1.2 neon over the counter + 3 Shell LightHost SurfaceLights; SwitchPlate x2; Plant x1",
    "standard FitOut kit (near-identical in all 7 shops; snack + pharmacy lack the extinguisher, salon + pharmacy lack the door mat): CassetteAC 3.8x0.34x3.8 + vanes/grille, CCTV glass ball + mount, ExitSign 2.6x1.0, FireExtinguisher cylinder + valve + Sign_소화기, SmokeDetector discs, WallSpeaker box, CCTV MonitorScreen (SurfaceGui 4 cams + ● REC), CertFrame x1-2, Sign_Wi-Fi (PW 12345678), Sign_10월 calendar, UmbrellaStand + 2 Umbrella sticks, DoorMat + stripe, Baseboard x3 (hidden inside Shell/Skirting, redundant) — functional-looking but generic, flat boxes, no textures"
   ],
   "gameplay": [
    "ShopLife: SS.GWSHOP.surf = {'retail','gw_surf'} (menu SS.MENUS.beach) -> pick flow. NO part matches the retail shelf names (WallRack/DisplayTable/Rack/WallBay/Hanger/Gondola/WallShelf/Shelf/Product): GearShelf, SupRack, RackBase, RackRail, SuitRail, SunscreenDisplay are ignored -> zero '고르기' prompts, so '계산하기' at Point_counter_1 only toasts '진열대에서 먼저 골라요 🧺' — the surf shop cannot sell or rent anything in v7.",
    "Point_counter_1 (-497.5,10.1,122.4) (PointKind counter, Label '렌탈 · 구매') = gwOrder; CounterTop = rec.counter; PosScreen = display.",
    "No Bin -> FoodKit bin spawned via Scan.freeSpot on the storefront side (버리기).",
    "GwangalliShopsShared SH.MENU (surf_sup -> Venues sup_rental, surf_board rental prop 'board_surf' carried 600 s, surf_sunscreen, surf_towel) is for the absent map Shops server.",
    "GwShopSpot: Spot_1 (-486.1,9.8,110.4) shop, Spot_2 (-490.4,9.8,118.7) sit_phone (Lift 0, at the Bench), Spot_3 (-508.2,9.8,106.2) shop, Spot_4 (-502.1,9.8,121.5) phone — unused by v7 scripts.",
    "ShopStaff adopts 서프 강사 (GwShopClerk, Role clerk -> KIND_BY.rental, Act teller) HRP (-497.6,9.9,127.4) behind the counter facing the entrance; 말 걸기 prompt.",
    "ZoneLOD LODCenter (-497.3,9.9,117.7) LODRadius 122; NearLOD Detail x2; 3 InteriorLight SurfaceLights; 4 NeonTube parts tagged NeonTube; 3 SignGuis tagged NightGlow.",
    "MUST KEEP: ShopBounds, Points/*, Bench (Seat), CounterTop + POS kit names, 서프 강사 rig; walkway door -> counter and both counter ends (u ±7.5..15.3) to the staff side."
   ],
   "emptyOrCrude": [
    "Boards (surf + SUP) are flat rectangles with box stringers; no fins, leash, traction pad, board bags, soft-top beginner boards or brand graphics.",
    "Wetsuits are flat black slabs with a teal 'shoulder' box; no hangers, rash guards, boardshorts or booties.",
    "Lockers are 8 solid boxes (no doors/keys); the shower is a painted door — no changing room, shower stalls, foot wash or hose, though signage advertises 샤워실.",
    "No wet-area treatment: no rubber/deck tiles, sand, drying rack, puddles; floor is clean planks.",
    "Rental counter is a plain teal block: no waiver tablet/clipboard, wristband keys, rental log board, inflator pump, VHF/safety gear.",
    "Wave forecast is a static poster; no TV/whiteboard with 파고·풍속·수온·물때.",
    "Gear shelf items are generic blocks; float ring hole is opaque; beach ball plain sphere.",
    "Functionally empty: ShopLife finds no shelves so nothing can be bought; 0 Sound instances."
   ],
   "realWorld": [
    "Board racks: vertical wall rack + horizontal rental rack, soft-top 초보 boards (foam, 8-9 ft), longboards, shortboards, fins in, leashes coiled on the tail, board bags",
    "SUP: inflatable SUP boards rolled/inflated, 3-piece paddles in a bin, hand/electric pump, ankle leashes",
    "Wetsuit rail by size (S/M/L/XL tags), rash guards, boardshorts, surf booties, gloves; drying rack + rinse bucket for returned suits",
    "Safety: 구명조끼 (life vests) on hooks by size, helmets, whistle, first-aid kit, 수상레저 사업 등록증 and 강사 자격증 framed, safety rules board",
    "Rental counter: POS + card terminal, waiver/이용 서약서 tablet or clipboard, rental log, wristband locker keys on a pegboard, price board (렌탈 2시간 / 강습 1회 / SUP 투어)",
    "Changing rooms (탈의실) with curtains, shower room (샤워실) with hot water, foot-wash tap at the entrance, towel rental",
    "Lockers with numbered doors and band keys; benches; hooks for bags",
    "Conditions board/TV: 파고, 풍향·풍속, 수온, 물때, 오늘의 강습 시간표; instructor photos; surf competition posters",
    "Retail: wax, sunscreen, 방수팩 (phone pouches), sunglasses, 비치타월, 슬리퍼, cold drinks cooler/fridge",
    "Finishes: rubber deck tiles or concrete with sand, wood slats, surf stickers, palm plants, hammock"
   ],
   "interactionIdeas": [
    "Board rack: 보드 고르기 -> pick a board (carry board_surf prop on the shoulder for the rental time)",
    "Wetsuit rail: 웻슈트 빌리기 -> walk to a changing curtain -> avatar outfit swap",
    "Lockers: 사물함 열기 (door swings, wristband key on wrist, store/retrieve a bag icon)",
    "Counter: 이용 서약서 서명 tablet mini-UI, then pay rental; instructor lines",
    "Conditions TV: 파도 예보 shows live game weather/wind/time",
    "SUP: 펌프질 hold-prompt inflates the board; take a paddle + life vest (required before SUP)",
    "Wax: 왁스 칠하기 mini-game on a board on the counter",
    "Shower / foot wash: rinse sand off (water particles, sound)",
    "Cooler: 음료 꺼내기 (lid opens, cold can in hand); bench: sit / check phone"
   ],
   "enterable": true
  },
  {
   "name": "광안 떡볶이 (분식집, ShopId snack)",
   "path": "Workspace.Gwangalli.shops.광안 떡볶이",
   "bounds": "ShopBounds world AABB (-637.9,6.8,91.6)..(-597.2,16.7,125.0); centre (-617.58,11.75,108.28), size 39.46 x 9.9 x 31.88, yaw ~182.3 deg. Interior AABB (-637.9,6.8,91.7)..(-597.2,16.9,125.0). Floor top 6.8 (CeramicTiles #d7d0c2), ceiling underside 16.7 (flat slab + 34 TBar strips). Host facade beachfront/구간08 .../광안해변 243빌딩/부산어묵 광안점 (name mismatch; ShopWindow x6 T=0.55, AutoDoor centre (-616.9,10.6,92.0)).",
   "rooms": [
    {
     "name": "hall (홀) with 4 tables + wall bar",
     "center": [
      -620.8,
      11.8,
      108.2
     ],
     "size": [
      32.9,
      9.9,
      31.8
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    },
    {
     "name": "open cooking line (조리대, staff aisle)",
     "center": [
      -601,
      11.8,
      104.1
     ],
     "size": [
      6.5,
      9.9,
      19.2
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    }
   ],
   "props": [
    "Open cooking line along the world +x wall: StationBody 3.2x3.1x19.2 (red CeramicTiles) + StationTop 3.5x0.25x19.4 Metal + yellow stripe, centre (-602.6,8.3,104.1); BackCounter 1.5x3.2x19.2 Metal + WallShelf with SupplyTub x8 behind (staff aisle ~2.5 studs)",
    "떡볶이 Pan 3x0.45x5.2 + Sauce slab + Tteok x10 (0.9x0.3 cylinders) + 1 FishCake plate at (-602.5,10.4,102.5) — 10 rice cakes in a pan that should hold hundreds; no 어묵 sheets, 대파, 삶은 계란: crude",
    "EomukTank 3x1x3.4 + EomukBroth (glass) + Skewer x8 + Eomuk x8 (0.2x0.65x0.5 flat boxes) at (-602.7,10.6,107.4): crude",
    "TwigimCase glass box 3x1.7x4.4 (T0.55) + CasePaper + Twigim x6 (bricks) at (-602.4,11.0,97.1); SundaeSteamer + SteamerLid cylinders at (-602.9,10.9,110.9); GimbapBoard + GimbapRoll x3 (black cylinders, no cut slices) at (-603.0,10.2,112.9)",
    "SteamVent x3 with Steam ParticleEmitter (attr ShopSteam) on pan/tank and self urn; price strip Sign_떡볶이 4,500 · 김밥 3,500 · 어묵 2,000 18.2 wide on StripWire; LightFrame/LightPanel 3.2x15.2 neon over the line",
    "Hall: 4 GwShopTable models Table_1..4 (TableTop 3.2x0.15x2.2 white + red TableEdge, 4 TableLeg, 4 Seat cylinders + StoolBody, TrayPoint) at (-610.6,9.2,100.0) (-610.9,9.2,107.3) (-622.8,9.2,99.5) (-623.1,9.2,106.9); each with NapkinBox+Napkins, CupStack, ForkBox",
    "Wall bar on the world -x wall: WallBar 1.9x0.25x18.4 plank + 4 BarBracket at (-636.2,10.2,102.7) + 6 bar stools (StoolPost/FootRing/StoolFoot + red Seat cylinder)",
    "Back wall: MenuFrame + Sign_광안 떡볶이 MENU 11x3.6 (yellow, 5 items) at (-616.7,14.1,124.2); SelfCounter 5.6x3.1x2.2 Metal + BrothUrn + UrnTap + PaperCups + Sign_어묵 국물 · 물 셀프 at (-607.0,8.3,123.5); Fridge model (Body/Kick/SidePanel x2/FridgeGlow neon/FridgeDoor glass T0.55/DoorMullion/DoorHandle x2, 3 WireShelf, Bottle x20 cylinders) at (-625.1,10.7,122.1); RamenShelf + RamenPack x4 at (-631.1,11.3,122.9); StaffDoor metal panel (nocol) + Sign_STAFF ONLY at (-635.4,10.5,123.5); Bin x2 + BinLid (blue cylinders) at (-619.9,7.9,122.9); OriginFrame + Sign_원산지 표시",
    "Door_restroom (DoorCasing/DoorLeaf wood/DoorHandle/Sign_화장실 남 ♂ · 여 ♀) on the world +x wall at (-598.5,10.4,122.4) — leaf on a solid wall, no restroom behind",
    "Walls: Shell WallTiles (white, 3.45 tall) + red TileStripe on side + back walls; PosterFrame x3 (매운맛 도전!, 떡튀순 세트), clock; TubeBody/TubeLamp x2 over tables; Plant",
    "standard FitOut kit (near-identical in all 7 shops; snack + pharmacy lack the extinguisher, salon + pharmacy lack the door mat): CassetteAC 3.8x0.34x3.8 + vanes/grille, CCTV glass ball + mount, ExitSign 2.6x1.0, FireExtinguisher cylinder + valve + Sign_소화기, SmokeDetector discs, WallSpeaker box, CCTV MonitorScreen (SurfaceGui 4 cams + ● REC), CertFrame x1-2, Sign_Wi-Fi (PW 12345678), Sign_10월 calendar, UmbrellaStand + 2 Umbrella sticks, DoorMat + stripe, Baseboard x3 (hidden inside Shell/Skirting, redundant) — functional-looking but generic, flat boxes, no textures"
   ],
   "gameplay": [
    "ShopLife: SS.GWSHOP.snack = {'snack','gw_snack'} -> TYPES.snack flow 'counter', pay pre, water=true; menu SS.MENUS.snack. 주문하기 at Point_order_1 (-605.1,10.1,102.4) (GwShopPoint PointKind order, Label 주문하기); 픽업하기 anchor = Scan.front(Point_order_1)+1.4 studs (no PassLedge/PassTop/Counter* part exists).",
    "Cook station: none of COOK_PRIORITY names (EspressoBody..Fryer, StockPot, Broth, Burner, KitchenPass, PassLedge, Hood ...) exist (Pan, EomukTank, SundaeSteamer, TwigimCase are not listed) and there is no pass/counter part -> no 'Cook' anchor, ShopLife's cooking fx/steam beat has nowhere to play.",
    "Tables: the 4 GwShopTable models give 4 '앉기' prompts (테이블 n · 4석); the 6 wall-bar Seats have no table (WallBar is not in TABLE_NAMES) so they get no prompt; menu board = first PosterFrame (Sign_광안 떡볶이 MENU is not an exact MENU_NAMES key); 화장실 이용 from Door_restroom/DoorLeaf; 버리기 at the first Bin.",
    "Water: no WaterPurifier/WaterBottle/WaterDispenser -> ShopLife spawns a FoodKit 'water' purifier through Scan.freeSpot along the storefront edge (hframe +Z = entrance side for GwShop) with prompt 물 따르기.",
    "GwangalliShopService: counter flow -> pickup call 'N번 손님~ ○○ 나왔습니다!' by the counter rig; ShopStaff adopts 분식 이모 (GwShopClerk Role clerk, Act cook) HRP (-600.0,9.8,102.6) in the staff aisle facing the hall; 말 걸기.",
    "GwShopSpot: Spot_1 (-634.1,9.8,98.3) eat_sit (Prop plate_snack, PropTint tteok, PropPos (-635.9,10.35,98.2) on the wall bar), Spot_2 (-610.3,9.8,109.2) eat_sit Table 2 (PropTint set), Spot_3 (-623.5,9.8,97.7) sit_phone Table 3, Spot_4 (-605.9,9.8,96.6) phone — unused in v7.",
    "ZoneLOD LODCenter (-617.6,11.9,109.3) LODRadius 126; NearLOD Detail x3 (fridge bottles etc.).",
    "MUST KEEP: Table_1..4 models (TableTop, Seat, TrayPoint names), Point_order_1, Door_restroom/DoorLeaf, Bin, Fridge/FridgeDoor, 분식 이모 rig; clear aisle from door to Point_order_1 and to each table."
   ],
   "emptyOrCrude": [
    "Food on the line is token geometry: 10 rice-cake cylinders on a flat red slab, 8 flat eomuk boxes, 6 twigim bricks, 3 uncut gimbap cylinders, closed sundae steamer.",
    "Missing the defining 분식 equipment: 튀김기 (fryer) for 튀김, gas range + 라면 냄비, 김밥 재료통 (단무지/햄/계란/시금치), 떡볶이 가위, ladles/spatulas, sneeze guard, 포장 용기/비닐봉투/은박지, 배달앱 태블릿 + 주문 프린터.",
    "Station is a solid 19.2-long tiled block; sauce has no gloss/bubbles; no heat glow.",
    "Tables bare apart from napkin/cup/fork boxes: no 메뉴판 card, 단무지, 물병, 수저통, 호출벨; stools have no seat cushion detail.",
    "Wall bar is a plank on brackets with nothing on it.",
    "Self corner: urn + paper cups only; no water purifier (a FoodKit one gets dropped near the window at runtime), no 단무지 셀프 통/tongs.",
    "Drink fridge: 20 cylinders in 5 colours, no labels/brand header.",
    "Restroom and staff doors are painted panels; no TV, no photo menu wall; flat ceiling with strip grid; 0 Sound instances (no bubbling/frying/BGM)."
   ],
   "realWorld": [
    "Street-facing open cooking line (often right behind the window): wide shallow 떡볶이 철판 full of 밀떡/쌀떡 + 어묵 sheets + 대파 + 삶은 계란 in glossy red sauce, 이모 stirring with a big spatula",
    "부산 어묵 꼬치 tank: stainless rectangular broth tank with dozens of skewered 꼬치어묵 standing in rows, ladle, paper cups; customers eat standing and count sticks",
    "튀김 corner: fryer + glass-front display rack of 오징어/김말이/고구마/야채/만두 튀김 on paper, tongs, tray",
    "순대 steamer (round 찜기 with steam), cutting board + knife for 순대/간/허파",
    "김밥 station: bamboo mat, 김 stack, 재료통 (단무지, 햄, 맛살, 계란, 시금치, 우엉), 참기름 bottle, sliced rolls on a plate",
    "라면/쫄면 gas range with 양은 냄비",
    "Big backlit menu board with photos + prices, 맵기 단계 sign, 포장/배달 안내, 원산지 표시판, 영업신고증",
    "Seating: small 4-person tables (stainless or melamine), round stools, wall counter for solo eaters",
    "Tabletop: 냅킨통, 수저통 (숟가락·젓가락·포크·이쑤시개), stainless water cups + 물병, 단무지 dish",
    "Self corner: 정수기, cup dispenser, 어묵 국물 셀프, 단무지 반찬 냉장고",
    "Drink fridge (glass door, branded header: 콜라/사이다/쿨피스/식혜), 포장 용기 shelf, 배달앱 태블릿 x2-3 + receipt printer",
    "Wall/floor tiles, TV, clock, 학생 posters, 음식물 쓰레기통; restroom usually in the building corridor"
   ],
   "interactionIdeas": [
    "어묵 꼬치 셀프: pick a skewer from the tank (hand prop), eat standing, pay by counting sticks at the counter (부산식)",
    "BrothUrn: 국물 따르기 into a paper cup (steam puff, hot drink in hand)",
    "튀김 case: 집게로 고르기 — choose pieces with tongs into a tray",
    "이모 stirs the 떡볶이 pan (spatula anim + steam) when an order is placed; 맵기 1-3 choice",
    "Sundae steamer: lid lifts with a steam burst, chopping sound",
    "Drink fridge: 문 열기 (door swings on its hinge, take a bottle)",
    "Self corner: 단무지 담기, 물 따르기, 휴지 뽑기",
    "김밥 말기 mini-game (career/job)",
    "포장: bag carried in hand; 매운맛 도전 photo-wall pose spot"
   ],
   "enterable": true
  },
  {
   "name": "행복 돼지국밥 (돼지국밥집, ShopId gukbap)",
   "path": "Workspace.Gwangalli.shops.행복 돼지국밥",
   "bounds": "ShopBounds world AABB (-914.9,6.8,77.8)..(-873.5,16.7,119.9); centre (-894.2,11.75,98.85), size 39.13 x 9.9 x 39.88, yaw ~183.3 deg. Interior AABB (-914.9,6.8,78.1)..(-873.5,16.9,119.9). Floor top 6.8 (CeramicTiles #c4bdb0), ceiling underside 16.7. Hall z ~78..107, kitchen behind the pass z ~109..119. Host facade beachfront/구간09 광안로61번길 ~ 광안해변로241번길/행복빌딩/행복 돼지국밥 (ShopWindow x6 T=0.55, AutoDoor centre (-893.0,10.6,78.6)).",
   "rooms": [
    {
     "name": "hall (홀) 8 tables + 평상",
     "center": [
      -893.9,
      11.8,
      93.1
     ],
     "size": [
      39,
      9.9,
      28.3
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    },
    {
     "name": "kitchen behind pass (주방, sealed by PassCounter)",
     "center": [
      -898.9,
      11.8,
      113.9
     ],
     "size": [
      31.6,
      9.9,
      9.3
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    },
    {
     "name": "store room behind StoreWall (fake SwingDoor)",
     "center": [
      -879.2,
      11.8,
      114.1
     ],
     "size": [
      7.6,
      9.9,
      11.1
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    }
   ],
   "props": [
    "Hall tables: 8 GwShopTable models Table_1..8 (TableTop 3.6x0.15x2.3 stainless Metal + TableEdge, 4 TableLeg 2.35, 4 round stools each = 32 Seat cylinders 1.2 dia + 128 StoolLeg + 32 StoolRing, TrayPoint) e.g. Table_1 at (-887.0,9.2,87.2) — 32 identical backless metal stools",
    "Per-table condiments (x8 each): NapkinBox+Napkins, Dadegi (red cylinder), SaeujeotJar (glass cylinder), BuchuBowl (Grass cylinder), WaterBottle (glass cylinder), SujeoTong with Spoons + Chopsticks as solid boxes 0.22x0.4x0.36 — complete set but each item is a single primitive: crude",
    "평상 (raised floor seating) on the world +x wall: Pyeongsang 7.17x1.3x18 WoodPlanks + PyeongsangEdge + StepBoard 1.2x0.55x14 at (-878.0,7.4,96.2); LowTable x2 (3.2x0.15x2.6) + 8 LowTableLeg; Cushion x8 (1.3x0.25x1.3 red/green Fabric squares); SujeoTong x2",
    "Kitchen pass: PassCounter 31.57x3.3x2.2 (tiled, collidable) + PassTop Metal at (-898.5,8.4,108.1) spanning from StoreWall to the far wall; PassSoffit 31.6x2.8 wood header with 4 menu plaques (Sign_돼지국밥 9,500 / 순대국밥 10,000 / 섞어국밥 10,500 / 수육백반 14,000) + PosterFrame Sign_원산지 표시 + Sign_24시 영업; on the pass: TtukStack x4 (뚝배기 cylinders), KkakdugiJar + Kkakdugi, RiceBowl x3, PassTray (WoodPlanks 3x0.1x1.8) at (-897.2,10.4,108.2)",
    "Kitchen: Burner x3 (3.8x1.4x3.8) + StockPot x3 (3.4 cylinders) + Broth discs + PotHandle x6 + Ladle x2 + SteamVent x3 (Steam particles) at (-892.7,9.9,116.4); Hood 15x1.4x4.8 + HoodDuct + DiamondPlate HoodFilter; BowlShelf x3 with Bowl x15 (뚝배기/stainless) at (-905.3,12.8,117.3); RiceCooker; BackCounter 5x3.3x2.3; KimchiFridge 2.27x4.4x3.2 white box + seam at (-913.2,9.0,111.0); LightFrame/LightPanel 18x1.2",
    "StoreWall 7.6x10.1x0.4 (Shell) at (-878.9,11.9,108.3) with SwingDoor (2.9x7.2 plank, nocol) + DoorPorthole pasted on its hall face at (-879.7,10.4,108.1) — fake door, solid wall behind",
    "Cash desk by the entrance: CashDesk 2.2x3.2x5.2 wood + Marble CashDeskTop at (-909.0,10.1,82.2); POS kit; CandyBowl + Candy x5 + Toothpicks; Sign_카드 · 현금 · 간편결제 OK; 사장님 rig",
    "Self bar on the world -x wall: SelfBar 6.5x3.1x2 Metal + SelfTray x3 + SelfBanchan x3 (flat red slabs) + Sign_반찬 · 물 셀프입니다 at (-912.8,8.3,98.0); WaterStand + Purifier 1.4x2.8x1.4 + PurifierPanel + Tap + DripTray + CupStack at (-912.2,10.8,87.6)",
    "Walls: Shell Wainscot (WoodPlanks 3.05 tall) + WainscotRail on both side walls; TVMount + TVBezel + static Sign_광안리 날씨 · 맑음 23°C (오후 6시 드론쇼 예정) at (-874.1,13.9,83.9); Sign_행 복 (福 / 한 그릇에 담은 정) calligraphy; HookRail + 4 Hook; FanMount + WallFan; clock; TubeBody/TubeLamp x3 over the hall",
    "Door_restroom (wood DoorLeaf, Sign_화장실) on the back wall at (-883.9,10.4,119.3) — inside the kitchen strip behind the PassCounter",
    "Bin + BinLid at (-904.0,7.9,104.7); Plant; FitOut: 3 cassette ACs, extinguisher, CCTV, exit sign, OriginFrame, CertFrame x2 (영업신고증, 위생교육 수료증)",
    "standard FitOut kit (near-identical in all 7 shops; snack + pharmacy lack the extinguisher, salon + pharmacy lack the door mat): CassetteAC 3.8x0.34x3.8 + vanes/grille, CCTV glass ball + mount, ExitSign 2.6x1.0, FireExtinguisher cylinder + valve + Sign_소화기, SmokeDetector discs, WallSpeaker box, CCTV MonitorScreen (SurfaceGui 4 cams + ● REC), CertFrame x1-2, Sign_Wi-Fi (PW 12345678), Sign_10월 calendar, UmbrellaStand + 2 Umbrella sticks, DoorMat + stripe, Baseboard x3 (hidden inside Shell/Skirting, redundant) — functional-looking but generic, flat boxes, no textures"
   ],
   "gameplay": [
    "ShopLife: SS.GWSHOP.gukbap = {'soup','gw_gukbap'} -> TYPES.soup flow 'table', pay post (계산 on the way out), water=true, banchan korean; menu SS.MENUS.gukbap (돼지/순대/섞어국밥, 수육, 공기밥, 청포도 소다, 사이다).",
    "Stations: 앉기 on all 8 GwShopTable + the 2 LowTable (kind 'low', Cushion seats -> '좌식 테이블'); 계산하기 at Point_order_1 (-906.6,10.1,82.3) (PointKind order); cook = StockPot (first COOK_PRIORITY hit); pass = PassTop; counter = CashDeskTop; menu board = first PosterFrame; bin = Bin.",
    "Water: WATER_NAMES = WaterBottle/WaterPurifier/WaterDispenser, so a table WaterBottle (the first one in descendant order) becomes the '물 따르기 · 정수기 (셀프)' station while the real Purifier at the self bar is ignored.",
    "Restroom: Door_restroom/DoorLeaf found, but its prompt anchor (Scan.front: ~2.7 studs toward the door, ~w -17 local) lies in the kitchen strip ~9 studs behind the collidable PassCounter -> unreachable with PROMPT_DIST 6.5.",
    "GwangalliShopService (addon): while the shop is open a 서빙 알바 waiter rig is spawned in workspace.GwangalliShopStaff and walks with PathfindingService from the pass to the ordering table (TrayPoint) and back; staffMode {serve=true}; needs walkable aisles between PassTop and every table.",
    "Play.Career.Gukbap (addon, 국밥집 알바): uses ShopBounds (inside test), DoorMat (customer entry), all 8 GwShopTable (Seat children + TrayPoint), PassTray + PassCounter (국밥 말기 cook panel, 쟁반 들기), Point_order_1 (계산하기 change panel) and the GwShopClerk rigs; its own prompts/props live under workspace.GwangalliPlay.Career.Gukbap; HUD finds Destination 'DisplayName 행복 돼지국밥'.",
    "GwangalliWorkSpots.gukbap (+ WorkPlacement): work spot fixed at world (-897.5,8,104) facing (-897.5,8,92) = hall side of the pass; sources {clerk='gukbap'} and {shopPoint='gukbap'}; uniform text 행복 돼지국밥.",
    "ShopStaff adopts 사장님 (Role clerk, Act teller) HRP (-911.6,9.7,82.1) at the cash desk and 주방 이모 (Role cook, Act cook) HRP (-892.4,9.6,111.4) in the kitchen; 말 걸기 prompts.",
    "GwShopSpot: Spot_1 (-886.7,9.8,96.2) eat_sit Table 2 (set_gukbap pork), Spot_2 (-897.9,9.8,98.6) eat_sit Table 6 (sundae), Spot_3 (-907.3,9.8,92.4) sit_phone Table 7, Spot_4 (-905.1,9.8,80.0) phone — unused by v7.",
    "ZoneLOD LODCenter (-894.2,7.0,107.9) LODRadius 124.",
    "MUST KEEP: Table_1..8 (child names TableTop/Seat/TrayPoint), LowTable/Cushion names, PassTray, PassCounter, PassTop, DoorMat, Point_order_1, CashDeskTop + POS kit, StockPot, Bin, both rigs; never place collidable props at (-897.5,8,104), on the pass, or in pass<->table paths."
   ],
   "emptyOrCrude": [
    "Kitchen is sealed: PassCounter (3.3 tall) spans wall to StoreWall and the SwingDoor is a non-collidable panel glued to a solid wall; the restroom door sits in that sealed strip (prompt unreachable).",
    "Kitchen equipment is primitive: stock pots = cylinders with a flat broth disc, burners = black boxes; no 가마솥/육수 솥 with 토렴 strainer, no 수육 steamer + cutting board + knife, no 업소용 4-door fridge (KimchiFridge is a white box), no sink/dish rack/식기세척기, no gas hoses/valves.",
    "Tables: every condiment is one primitive; spoons/chopsticks are solid boxes; no 앞접시, water cups, 김치/깍두기 통 with tongs, 소금/후추, 호출벨, 계산서 꽂이.",
    "Seating: 32 identical backless stools and 8 identical tables; 평상 cushions are thin squares, no 신발 벗는 곳/신발장, no 방석 stack or 칸막이.",
    "Walls: wainscot + calligraphy + static TV slab; no 방송 출연 / 맛집 액자, 유명인 사인, food photos, 메뉴 pictures.",
    "Self bar holds 3 flat red slabs ('banchan'); no glass 반찬 냉장고, tongs, 앞접시 stack, 컵 소독기 (UV cup sterilizer), apron hooks.",
    "Ceiling is a flat slab with 3 bare tube lamps; 0 Sound instances (no bubbling broth, kitchen clatter, TV)."
   ],
   "realWorld": [
    "Front: 계산대 by the door with POS, card terminal, 박하사탕 bowl, 이쑤시개, 명함, 24시 sign; menu board with photos above the pass",
    "Open kitchen / pass: huge 육수 솥 (가마솥) boiling with steam, 토렴 station (strainer basket + ladle pouring broth over rice in 뚝배기 3-4 times), 뚝배기 stacks, 공깃밥 온장고 (rice warmer cabinet), 수육 steamer + 도마 + 칼, 순대/내장 bins, 깍두기 대형 통",
    "Back kitchen: 업소용 냉장고 45박스 (4-door stainless), 김치냉장고, 3-구 가스 화구, 싱크대 + 식기세척기 + 건조대, 국자/집게 rail",
    "Tables: stainless or wood 4-person tables, 수저통 (or drawer under the table), 냅킨, 다대기 (양념장), 새우젓 단지 with tiny spoon, 부추무침(정구지) bowl, 소금·후추, 물병 + stainless cups, 김치/깍두기 통 + 가위/집게, 앞접시, 호출벨",
    "Side dishes per set: 김치, 깍두기, 부추, 양파 + 고추 + 쌈장 (수육), 새우젓, 소면",
    "좌식 방/평상 with 방석 stack, 신발 벗는 곳 + 신발장, low tables, sometimes 미닫이문 room for 단체석",
    "Walls: 메뉴판 plaques, 원산지 표시판, 맛집 방송 출연 액자, 유명인 사인, TV (야구/뉴스), wall fan, clock, local-business calendar, '부추는 정구지' Busan-dialect notes",
    "Self bar: glass 반찬 냉장고, 정수기, UV 컵 소독기, 앞치마 hooks, 물티슈",
    "Floor anti-slip tiles; restroom off the hall or in the building corridor"
   ],
   "interactionIdeas": [
    "Sit -> 수저 꺼내기 from SujeoTong (spoon+chopsticks props placed at your seat spot)",
    "Water bottle 물 따르기 into a stainless cup (pour anim, cup prop)",
    "Customize your bowl: 다대기 / 새우젓 / 부추 넣기 (Food part colour + bite stat), 공깃밥 말기",
    "깍두기/김치 통: 집게로 덜기 onto an 앞접시",
    "평상: 신발 벗기 then 좌식 sit on a cushion",
    "Career (Gukbap.luau): 토렴 3x ladle mini-game at the pot, 수육 썰기 slicing timing, 쟁반 들기 carry",
    "TV remote: change channel (야구 / 뉴스 / 광안리 드론쇼 live) ; wall fan on/off",
    "Cash desk: 박하사탕 하나, 이쑤시개, change counting UI",
    "Self bar: open the 반찬 냉장고, take refills"
   ],
   "enterable": true
  },
  {
   "name": "광안 치킨 (치킨호프, ShopId chicken)",
   "path": "Workspace.Gwangalli.shops.광안 치킨",
   "bounds": "ShopBounds world AABB (-1121.5,6.8,64.2)..(-1092.2,16.7,84.0) (hall only); centre (-1106.81,11.75,74.13), size 28.15 x 9.9 x 17.88, yaw ~184 deg. Interior AABB (-1121.5,6.8,64.6)..(-1092.2,16.9,98.0) (includes the kitchen room outside ShopBounds). Floor top 6.8 (hall CeramicTiles #d9c3a0; Shell/KitchenFloor Concrete (-1111.4,6.5,83.3)..(-1093.1,6.8,98.5)), ceilings underside 16.7. Host facade beachfront/구간09 .../광안 오션 레지던스/광안 치킨 & 맥주 (ShopWindow x4 T=0.55, AutoDoor centre (-1106.2,10.6,64.9)).",
   "rooms": [
    {
     "name": "hall (홀) 4 tables + counter",
     "center": [
      -1106.8,
      11.8,
      74.3
     ],
     "size": [
      28,
      9.9,
      18.1
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    },
    {
     "name": "kitchen room (주방, pass window only, no door)",
     "center": [
      -1102.2,
      11.8,
      90.7
     ],
     "size": [
      17,
      9.9,
      14
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    }
   ],
   "props": [
    "Order counter: CounterBody 16.17x2.75x1.9 (yellow) + CounterStripe (red) + ToeKick + Marble CounterTop 16.32x0.3x2.3 at (-1113.0,10.0,79.7); POS kit + ReceiptPrinter + ServiceBell/knob; BoxStack x3 on counter (1.7x0.53x1.7 red Cardboard cubes) + CupHolder; hanging Sign_주문 · 포장 하는 곳 on SignWire",
    "MenuFrame 8.7x3.9 + Sign_MENU · 광안 치킨 (후라이드 20,000 / 양념 21,000 / 반반 21,000 / 1인 순살 12,000) at (-1115.7,13.9,82.4); PosterFrame Sign_바삭 (매일 새 기름); clock",
    "Pass window: gap in ShopBackWall (5 pieces) 11.55 wide, y 10.8..14.25; PassLedge 11.55x0.12x1.6 Metal + red PassTrim at (-1101.5,10.7,83.7)",
    "Kitchen room (KitchenWall x3 CeramicTiles, Concrete floor): Fryer x2 (3.2x3.3x3 Metal) + FryerOil glass slab + FryBasket x4 (DiamondPlate boxes) + BasketHandle x4 + FryerDial neon + SteamVent x2 at (-1098.9,8.4,96.0); Hood 8.57x1.4x3.7 + duct + filter; PrepTable 12.95x3.2x2.2 with FlourTray (Sand), MarinadeBin + RawChicken slab, SauceBucket x2, Tongs at (-1100.3,8.4,86.1); KitchenFridge 3.2x7.6x3.4 box at (-1108.9,10.6,89.6); Sink + SinkBowl at (-1095.0,8.4,91.2); WallShelf + SauceTub x5; BoxStack x10 floor stacks",
    "Hall: 4 GwShopTable models (TableTop 3.8x0.15x2.6 WoodPlanks, 4 TableLeg, 4 chairs each = 16 Seat 1.5x0.2x1.5 + ChairBack + 64 ChairLeg, TrayPoint), e.g. Table_1 at (-1097.9,9.2,69.8); per table NapkinBox+Napkins, CallBell + neon CallBellButton, WetWipe; 4 pendants (PendantCord + yellow PendantShade cylinder + neon PendantBulb ball)",
    "Walls: Shell Wainscot yellow CeramicTiles 2.85 tall + red WainscotCap both sides; BrickWall 17.75x6.6 (Brick material sheet) at (-1092.8,13.4,75.2); TV (TVBezel 4.9x2.89, static '야구 중계 LIVE · 부산 4 : 3 서울 · 8회말 2사 만루') at (-1093.0,13.6,73.1); PosterFrame x4 (치킨은/사랑입니다, 반반, 오늘의 추천); HookRail + 5 Hook",
    "Self corner (world -x front corner): WaterStand + Purifier + PurifierPanel + Tap + DripTray + CupStack at (-1119.4,10.8,65.8); SelfCabinet 3.6x3x1.5 + Marble SelfTop + RadishTub + WetWipeBox + Sign_셀프 코너 · 치킨무 · 물티슈 at (-1119.8,8.3,69.4)",
    "Drink Fridge model (red Body header, glass door T0.55, 3 WireShelf, Bottle x20 red/brown cylinders, 2 handles) at (-1119.1,10.7,75.3)",
    "Bin + BinLid at (-1105.5,7.9,78.0); Plant; LightFrame/LightPanel x2 (10x1 neon: over counter and in kitchen); FitOut: only 1 CassetteAC, 1 SmokeDetector, extinguisher, CCTV, exit sign, CertFrame x2",
    "standard FitOut kit (near-identical in all 7 shops; snack + pharmacy lack the extinguisher, salon + pharmacy lack the door mat): CassetteAC 3.8x0.34x3.8 + vanes/grille, CCTV glass ball + mount, ExitSign 2.6x1.0, FireExtinguisher cylinder + valve + Sign_소화기, SmokeDetector discs, WallSpeaker box, CCTV MonitorScreen (SurfaceGui 4 cams + ● REC), CertFrame x1-2, Sign_Wi-Fi (PW 12345678), Sign_10월 calendar, UmbrellaStand + 2 Umbrella sticks, DoorMat + stripe, Baseboard x3 (hidden inside Shell/Skirting, redundant) — functional-looking but generic, flat boxes, no textures"
   ],
   "gameplay": [
    "ShopLife: SS.GWSHOP.chicken = {'chicken','gw_chicken'} -> TYPES.chicken flow 'table', pay post, water=true, banchan chicken; menu SS.MENUS.chicken.",
    "Stations: 앉기 on the 4 GwShopTable; 계산하기 + 바에서 주문 at Point_order_1 (-1114.7,10.1,77.7) (PointKind order); cook = FryBasket (first COOK_PRIORITY hit, inside the doorless kitchen); pass = PassLedge; counter = CounterTop; display = PosScreen; menu board = first PosterFrame (Sign_MENU · 광안 치킨 is not an exact MENU_NAMES key); bin = Bin.",
    "Water: 'Purifier' is not in WATER_NAMES -> ShopLife spawns a SECOND FoodKit purifier via Scan.freeSpot (storefront edge) next to the existing one.",
    "Tap mini-game ('직접 따라보기 · 무알콜 생맥 탭 (퍼펙트 푸어 도전)') is coded for t == 'chicken' but needs a part named TapHandle/TapPost/TapBar — none exists, so it never appears.",
    "No Door_restroom -> no 화장실 prompt.",
    "GwangalliShopService: waiter rig walks (PathfindingService) from the pass (PassLedge) to tables, serves on TrayPoint; 호출벨 'call' events bring the waiter ('네~ 부르셨어요?'). The existing CallBell parts are decorative.",
    "ShopStaff adopts 사장님 (Role clerk) HRP (-1115.0,9.7,81.6) behind the counter and 주방 (Role cook) HRP (-1099.8,9.7,88.5) in the kitchen; 말 걸기.",
    "GwShopSpot: Spot_1 (-1097.5,9.8,77.7) eat_sit Table 2 (tray_chicken fried, PropPos (-1098.3,9.3,75.7)), Spot_2 (-1112.0,9.8,66.9) eat_sit Table 3 (yangnyeom), Spot_3 (-1114.5,9.8,76.5) sit_phone Table 4, Spot_4 (-1109.7,9.8,77.8) phone — unused by v7.",
    "ZoneLOD LODCenter (-1106.8,7.7,81.9) LODRadius 103.",
    "MUST KEEP: Table_1..4 (TableTop/Seat/TrayPoint), PassLedge + the ShopBackWall pass opening, FryBasket/Fryer names, CounterTop + POS kit, Point_order_1, Bin, Fridge/FridgeDoor, both rigs; aisles pass<->tables for the pathfinding waiter."
   ],
   "emptyOrCrude": [
    "Kitchen room has no door at all (KitchenWall/ShopBackWall closed except the pass window at 4 studs height); cook rig is boxed in and the kitchen lies outside ShopBounds.",
    "Fryers are steel boxes with a glass 'oil' sheet and grid boxes as baskets; no oil filter, 폐유통, 튀김옷 반죽기, 염지통, 양념 버무림 볼, 포장대.",
    "Counter lacks 배달앱 태블릿 (배민/쿠팡이츠/요기요), phone, 치킨무+콜라 포장 sets, 비닐봉투; box stacks are unprinted red cubes.",
    "'치킨 & 맥주' with no beer: no 생맥주 tap, beer fridge, 500cc mugs/pitcher; no 뼈통, 비닐장갑, 앞접시, 소금/소스 dishes on tables.",
    "16 identical chairs (flat seat + flat back + 4 sticks) and plank tables; brick wall is a single Brick sheet; TV is a static slab; no 롯데 자이언츠 pennants or neon sign.",
    "Only 1 cassette AC and 1 smoke detector for a 28x18 hall; ceiling flat; 0 Sound instances (no sizzle, TV crowd, BGM).",
    "Runtime will add a duplicate water purifier near the window (Scan name mismatch)."
   ],
   "realWorld": [
    "Order/pickup counter: POS, card terminal, receipt printer, 배달앱 태블릿 x2-3 + 주문 알림 프린터, landline phone, 영수증 꽂이, pre-folded printed 치킨 박스 stacks, 치킨무 + 콜라 + 소스 포장 set, 비닐봉투 roll",
    "Kitchen: 2-3 업소용 전기/가스 튀김기 with baskets on hooks, 염지 통, 반죽기, 파우더(튀김옷) bins, 양념/간장/마늘 소스 통 + 버무림 스텐볼 (wok), 기름 거름 필터 + 폐유통, 업소용 냉장고/냉동고, 싱크대, hood with grease drip, 포장대",
    "Hall (치킨호프): wooden tables + chairs, 생맥주 탭 (Cass/Terra/Kelly), 맥주 냉장고 + frozen 500cc mugs, 3000cc pitchers, 소주/음료 fridge",
    "Tabletop: 호출벨, 냅킨, 물티슈, 비닐장갑 box, 뼈통, 앞접시, 치킨무 리필 dish, 소금 + 양념 소스 dish",
    "Walls: TV showing 야구 (Busan = 롯데 자이언츠), team pennants/uniform, beer brand posters and neon, menu photo board, 오늘의 추천, 원산지·영업신고증",
    "Self corner: 정수기, 치킨무 셀프 냉장고, 물티슈",
    "Lighting: warm pendants over tables, bright kitchen panels"
   ],
   "interactionIdeas": [
    "Order at the counter or 키오스크; 배달 tablet 'ding' + printer chatter when NPC orders arrive",
    "Watch the cook: basket lowers into oil (bubble particles + sizzle), shakes, hangs to drain; 양념 버무리기 toss in the wok (career)",
    "Table 호출벨: press -> ShopService waiter comes ('call' bus op); bell button lights",
    "Add a TapPost so ShopLife's 무알콜 생맥 탭 'perfect pour' mini-game appears; frozen mug from the beer fridge",
    "Self corner: 치킨무 리필, 물티슈 뜯기, 물 따르기 (fix name to WaterPurifier to avoid the duplicate)",
    "비닐장갑 끼기 -> eat with hands anim; bones into 뼈통",
    "TV: 야구 score ticks with game time, crowd cheer on home runs; channel change",
    "포장: carry the printed box + bag; fridge 음료 꺼내기"
   ],
   "enterable": true
  },
  {
   "name": "헤어살롱 물결 (미용실, ShopId salon)",
   "path": "Workspace.Gwangalli.shops.헤어살롱 물결",
   "bounds": "ShopBounds world AABB (-1221.3,6.8,56.8)..(-1200.6,16.7,96.0); centre (-1210.94,11.75,76.42), size 17.72 x 9.9 x 37.88, yaw ~184.5 deg. Interior AABB (-1221.3,6.8,57.1)..(-1200.6,16.9,96.0). Floor top 6.8 (dark Marble #55555a), ceiling underside 16.7. Host facade beachfront/구간10 광안해변로241번길 ~ 광안해변로255번길/민락해변 257빌딩/해변 호프 (name mismatch; ShopWindow x2 T=0.55, AutoDoor centre (-1209.4,10.6,57.2)).",
   "rooms": [
    {
     "name": "reception + waiting (w 9..19)",
     "center": [
      -1209.9,
      11.8,
      62.5
     ],
     "size": [
      17.6,
      9.9,
      9.9
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    },
    {
     "name": "styling stations x2 (w -4..8)",
     "center": [
      -1210.8,
      11.8,
      74.2
     ],
     "size": [
      17.6,
      9.9,
      13.5
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    },
    {
     "name": "dryer / towel warmer + shampoo zone (w -19..-4.5)",
     "center": [
      -1211.9,
      11.8,
      88.1
     ],
     "size": [
      17.6,
      9.9,
      14.4
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    }
   ],
   "props": [
    "Reception: Reception 1.6x3.4x4.8 white + gold Metal ReceptionTop + pink ReceptionBand at (-1204.2,8.5,64.3); POS kit; Vase + Flowers; ProductShelf x3 (gold, 5.2x1) with HairProduct x18 (0.7x0.4 cylinders, 3 colours) on the wall behind at (-1201.6,12.5,64.5); 원장님 rig behind the desk",
    "Waiting: SofaBase + SofaBack 6.26 wide pink Fabric + SofaSeat x2 (Seat) at (-1215.1,7.4,58.9); SideTable gold + Magazine x3 (flat 1.2x0.1x1.2 squares)",
    "Styling stations x2 on the world +x wall: MirrorFrame 3.8x5 gold + Mirror 3.4x4.6 + MirrorLED x2 strips each at (-1201.8,12.7,71.5)/(-1202.4,12.7,79.1); ToolCabinet 3.6x2.9x1.1 black + Marble ToolShelf with HairDryer (0.4x0.8x0.4 box), Spray x2 cylinders, Comb slab per station",
    "Styling chairs x2: ChairBase disc, ChairPost, ChairBody 2x0.5x2 Leather, SalonChair_1/2 (Seat 1.9x0.4x1.9, attrs ShopId/Index) at (-1205.5,8.8,71.2)/(-1206.1,8.8,78.8), ChairBack 2x3.15x0.3, Headrest, Armrest x2 + ArmPost x2, FootRest — BUILT BACKWARDS: the Seat faces the mirror (-u) but ChairBack/Headrest sit between seat and mirror and the FootRest is behind; seated avatars face into the backrest",
    "TrolleyTray x3 + TrolleyPost x2 (tool trolley) at (-1203.8,8.5,75.2); PendantCord + PendantGlobe (neon ball) over each chair; LightFrame/LightPanel 10x1.3 over the shampoo zone; TubeLamp 11.8 along the centre",
    "Opposite wall: PriceFrame 6.9x4.4 gold + SalonPriceBoard (댄디컷 15,000 ... 핑크 탈색 60,000) at (-1219.3,13.6,72.1); DisplayShelf x4 white with ShampooBottle x20 (gold/pink cylinders) at (-1218.3,9.0,64.7); ColorChart 3x2.2 + HairSwatch x12 (12 colours) + label at (-1218.6,12.0,61.2); PosterFrame + Sign_물결 (자연스럽게, 나답게)",
    "Shampoo zone (back): BasinCabinet x2 3.2x2.8x1.8 black + Basin (vertical cylinder disc 0.6x1.8) + BasinTap + WashSeat (Seat, faces the entrance, back to basin) + WashBase + WashBack at (-1207.8,8.2,94.7)/(-1213.7,8.2,94.3); TowelShelf + Towels x4 slabs",
    "Hood dryer stand: DryerBase disc + DryerPole + DryerArm + DryerHood 2x1.6x2.2 pink + DryerInner at (-1214.6,11.5,84.2); TowelWarmer 1.7x4.2x1.5 + glass WarmerDoor + LED at (-1219.4,8.9,85.2)",
    "Door_staff 'STAFF · 직원 휴게실' painted door at (-1217.2,10.4,94.8); Shell Wainscot pink Plaster 3.25 + GoldRail on both walls; Plant; Sign_미용사 면허증 / 미용업 신고증 CertFrames",
    "standard FitOut kit (near-identical in all 7 shops; snack + pharmacy lack the extinguisher, salon + pharmacy lack the door mat): CassetteAC 3.8x0.34x3.8 + vanes/grille, CCTV glass ball + mount, ExitSign 2.6x1.0, FireExtinguisher cylinder + valve + Sign_소화기, SmokeDetector discs, WallSpeaker box, CCTV MonitorScreen (SurfaceGui 4 cams + ● REC), CertFrame x1-2, Sign_Wi-Fi (PW 12345678), Sign_10월 calendar, UmbrellaStand + 2 Umbrella sticks, DoorMat + stripe, Baseboard x3 (hidden inside Shell/Skirting, redundant) — functional-looking but generic, flat boxes, no textures"
   ],
   "gameplay": [
    "ShopLife: SS.GWSHOP.salon = {'salon','salon'} -> TYPES.salon flow 'service', ui 'desk', pay pre; menu SS.MENUS.salon. No PointKind order/counter -> orderPart = PosBase at the reception -> prompt '스타일 상담'.",
    "Point_chair_1 (-1207.1,10.1,71.1) Label '헤어 시술 1' and Point_chair_2 (-1207.7,10.1,78.7) '헤어 시술 2' (PointKind chair) -> prompts '앉아서 스타일 고르기 💇 헤어 시술 n' (life.open menuPayload desk, salon=true, chair index). Service flow -> no bin is added; no Door_restroom.",
    "GwangalliShopsShared contract: SalonChair_n Seat (ShopId, Index) = the styling chair; StylistSpot_1 (-1207.9,9.8,71.1) / StylistSpot_2 (-1208.5,9.8,78.7) = where the stylist stands for the 8 s cut (SH.CUT_SECONDS, events cut/cutDone) — for the absent map server; hair purchases go through Venues.buy 'hair_<id>' (G.SALON).",
    "Play.Together.Table: a 'salon' service shows '같이 받는 중' for companions.",
    "ShopStaff adopts 원장님 (GwShopClerk Role stylist -> KIND_BY.salon, Act teller) HRP (-1202.2,9.6,64.5) behind the reception facing the room; 말 걸기.",
    "GwShopSpot: Spot_1 (-1213.9,9.8,59.2) sit_phone, Spot_2 (-1217.0,9.8,58.9) sit_phone (sofa), Spot_3 (-1215.7,9.8,65.0) shop — unused by v7.",
    "ZoneLOD LODCenter (-1211.0,7.0,79.3) LODRadius 112.",
    "MUST KEEP: SalonChair_1/2 (Seat class, names, attrs, CFrame facing the mirror), Point_chair_n, StylistSpot_n, SofaSeat/WashSeat seats, PosBase, 원장님 rig; the floor in front of each chair (StylistSpot) must stay walkable."
   ],
   "emptyOrCrude": [
    "Styling chairs are assembled backwards relative to their Seat (backrest + headrest on the mirror side, footrest behind) — the key fixture of the shop looks broken when used.",
    "Only 2 stations in a 17.7 x 37.9 room; the middle (between the reception and the shampoo zone) is mostly empty floor with a price board on the wall.",
    "Tools are tokens: dryer = small box, comb = slab, sprays = cylinders; no scissors, clippers, irons (고데기/아이롱), round brushes, clips, cape (커트보), neck strip, hand mirror.",
    "Shampoo units: basin is an upright disc, no neck rest cut-out, no hand-shower hose; wash chair = 3 black boxes.",
    "No perm machine (디지털 펌/롤러볼), no colour mixing cart (bowls, brushes, foil, dye tubes) though a ColorChart is shown; hood dryer is boxy.",
    "Waiting area: magazines are flat squares; no water/coffee machine, reservation tablet, coat hooks or bag lockers.",
    "38 product bottles are identical cylinders without pumps or labels.",
    "No hair clippings, broom, towel sterilizer, washing machine; 0 Sound instances (no dryer hum, scissors snips, BGM)."
   ],
   "realWorld": [
    "Reception: desk with POS + card terminal, 네이버 예약 tablet/appointment book, business cards, product display (클리닉 샴푸, 에센스, 왁스) on lit shelves",
    "Waiting: sofa, magazines + style books (헤어 카탈로그), water dispenser / capsule coffee machine with paper cups, coat hooks, small lockers or bag baskets",
    "Styling stations (4-6 typical): large mirror with LED, counter shelf with spray bottle, combs, round brushes, clips, scissors pouch/holster, clippers on a hook, 고데기/아이롱 hanging, hair dryer in a holster, UV sterilizer box",
    "Hydraulic styling chair (black leather, chrome base, footrest in front) facing the mirror; cape (커트보) on a hook; 목 수건",
    "Rolling trolley (왜건) with clips, perm rods (로트), foil, gloves",
    "Shampoo area: reclining shampoo chairs + ceramic basins with neck rest and hand shower, pump bottles of 샴푸/린스/트리트먼트, towel stacks, towel cabinet",
    "Chemical services: digital perm machine with cables/rods, 열처리기 (롤러볼 heater), colour bar with dye tubes, mixing bowls + brushes, scale, colour swatch chart",
    "Back: washing machine + towel dryer rack, staff room",
    "Floor: hair clippings around chairs, broom + dustpan; price board, 미용사 면허증 + 미용업 신고증 framed; bright 5000K lighting + pendant accents"
   ],
   "interactionIdeas": [
    "Reception: 예약 확인 on the tablet -> wait on the sofa (magazine UI / style catalogue) until called",
    "Styling chair (fix orientation): cape goes on, stylist walks to StylistSpot_n, scissors/clipper anim with snip SFX, hair particles falling and clippings decals accumulating on the floor; mirror shows the result",
    "Shampoo chair: recline (camera tilt), hand-shower water particles + sound, towel wrap afterwards",
    "Hood dryer: sit under it with a timer bar",
    "Colour chart: pick a swatch -> preview hair colour before buying 염색",
    "Product shelf: 제품 사기 at the reception",
    "Career/odd job: sweep the hair with a broom, fold warm towels from the TowelWarmer (door opens, steam)"
   ],
   "enterable": true
  },
  {
   "name": "바다약국 (약국, ShopId pharmacy)",
   "path": "Workspace.Gwangalli.shops.바다약국",
   "bounds": "ShopBounds world AABB (-1241.2,6.8,55.3)..(-1220.9,16.7,90.4); centre (-1231.04,11.75,72.83), size 17.72 x 9.9 x 33.88, yaw ~184.5 deg. Interior AABB (-1241.2,6.8,55.5)..(-1220.9,16.9,90.4). Floor top 6.8 (CeramicTiles #eeeeea), ceiling underside 16.7 (flat slab + 24 TBar strips). Host facade beachfront/구간10 .../민락해변 257빌딩/바삭치킨 (name mismatch; ShopWindow x2 T=0.55, AutoDoor centre (-1229.7,10.6,55.6)).",
   "rooms": [
    {
     "name": "retail floor (OTC shelves, gondola, BP corner)",
     "center": [
      -1230.6,
      11.8,
      66.9
     ],
     "size": [
      17.6,
      9.9,
      21.9
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    },
    {
     "name": "counter + dispensary (조제실, behind counter)",
     "center": [
      -1231.9,
      11.8,
      83.7
     ],
     "size": [
      17.6,
      9.9,
      11.9
     ],
     "floorY": 6.8,
     "ceilingY": 16.7
    }
   ],
   "props": [
    "Wall shelf units: 5 Shelf models (BackPanel 5.2x7 white + 2 Upright + 3 Board 4.8x1.3 + green Header 5.2x0.7) at (-1222.3,10.3,72.1) (-1221.8,10.3,66.7) (-1221.4,10.3,61.3) on the world +x wall and (-1239.2,10.3,65.4) (-1238.8,10.3,60.0) on the -x wall; category boards Sign_감기 · 해열 · 진통 / 소화 · 위장 · 변비 / 파스 · 밴드 · 소독 in PosterFrames at y15.6",
    "Centre Gondola (SideA/SideB: BackPanel 7x4.6, Upright x2, Board x2 each; EndPanel x2 + green EndHeader x2) at (-1230.6,9.1,66.7)",
    "Product x115 (0.68x1.58x0.75 typical, 62 sizes, 10 colours, 36 plain white) + PriceRail x19 (SurfaceGui price lists e.g. '종합감기약 4,500 · 해열진통제 3,000 · 코감기 시럽 5,500') — unlabelled boxes: crude",
    "Drink Fridge model (green Body header, glass FridgeDoor T0.55, 4 WireShelf, Bottle x30 brown/cream cylinders, 2 handles) at (-1238.1,10.7,73.3) + Sign_피로회복제 · 1,000원",
    "BP corner: BPSeat (Seat) + BPSeatBase, BPMachine 1.4x4x1.6 box + BPCuff cylinder + neon BPScreen at (-1225.0,8.8,58.9); Scale 1.4x0.25x1.4 slab; Sign_자동 혈압계",
    "Counter 14.06x3.3x2.4 white + Marble CounterTop + green CounterStripe at (-1231.7,10.2,79.0); POS kit; BottleTray + DrinkBottle x6; LeafletStand; 약사님 rig behind",
    "Dispensary: DispensaryHeader 17.72x2.5x0.2 spanning the room at y15.4; DispensaryGlass 5.86x7.4 (T0.6) only over one third at (-1237.7,10.5,82.8) + Sign_조제실; DrawerCabinet 10.6x7.6x1.6 + Drawer x30 faces at (-1229.0,10.6,89.1); PrepCounter 5x3.2x2 + PillTray at (-1238.2,8.4,88.2); GreenCross x2 neon bars + Sign_약사와 상담하세요 at (-1229.0,15.4,89.6)",
    "QueueDisplay 2.4x1x0.35 + Sign_0 2 7 ('번 고객님 · 처방 조제 완료', static) at (-1240.1,15.1,76.6); Door_staff 'Sign_조제실 · 관계자 외 출입금지' at (-1223.4,10.4,86.3)",
    "Shell: GreenBand stripes, green Skirting; LightFrame/LightPanel x3 (10x2 neon); Sign_휴일지킴이약국 (일요일 · 공휴일 10:00 - 18:00); CertFrames 약사 면허증 / 약국 개설 등록증; FitOut: 1 cassette AC, 1 smoke detector",
    "standard FitOut kit (near-identical in all 7 shops; snack + pharmacy lack the extinguisher, salon + pharmacy lack the door mat): CassetteAC 3.8x0.34x3.8 + vanes/grille, CCTV glass ball + mount, ExitSign 2.6x1.0, FireExtinguisher cylinder + valve + Sign_소화기, SmokeDetector discs, WallSpeaker box, CCTV MonitorScreen (SurfaceGui 4 cams + ● REC), CertFrame x1-2, Sign_Wi-Fi (PW 12345678), Sign_10월 calendar, UmbrellaStand + 2 Umbrella sticks, DoorMat + stripe, Baseboard x3 (hidden inside Shell/Skirting, redundant) — functional-looking but generic, flat boxes, no textures"
   ],
   "gameplay": [
    "ShopLife: SS.GWSHOP.pharmacy = {'pharmacy','gw_pharmacy'} -> TYPES.pharmacy flow 'service', ui 'consult', pay pre; menu SS.MENUS.pharmacy. '상담하기' at Point_counter_1 (-1232.0,10.1,76.8) (PointKind counter, Label '약 사기') = gwOrder.",
    "Shelf/fridge discovery only runs for cvs/bakery/retail types, so the 5 shelves, gondola, 115 products and the drink fridge are pure decor; service flow -> no bin added; no Door_restroom.",
    "BPSeat is a real Seat (players can sit) but no script drives the BP machine or the scale.",
    "GwangalliShopsShared SH.MENU pharm_drink (rest 10) / pharm_vitamin / pharm_patch / pharm_digest with 'rest' effects — only for the absent map Shops server.",
    "ShopStaff adopts 약사님 (GwShopClerk Role pharmacist -> KIND_BY.pharmacy, Act teller) HRP (-1232.3,9.7,81.6) behind the counter facing the entrance; 말 걸기.",
    "GwShopSpot: Spot_1 (-1224.9,9.8,65.7) shop, Spot_2 (-1233.0,9.8,67.1) shop, Spot_3 (-1227.9,9.8,76.5) phone — unused by v7.",
    "ZoneLOD LODCenter (-1231.1,11.9,73.8) LODRadius 112; 10 NearLOD Detail models (shelf fills, fridge bottles, price rails).",
    "MUST KEEP: Point_counter_1, Counter/CounterTop, POS kit, BPSeat, Fridge/FridgeDoor, 약사님 rig; keep the counter front (prompt within 6.5 studs) and aisles clear."
   ],
   "emptyOrCrude": [
    "Products are 115 unlabelled boxes (a third pure white): no medicine box art, blister packs, bottles, tubes, 박카스 cartons; price rails carry text but items don't.",
    "Behind-counter OTC wall is missing: real 약국 keep 일반의약품 on shelves right behind the pharmacist; here there is empty floor between the counter and the drawer cabinet.",
    "Dispensary is thin: one drawer cabinet + small prep counter; no ATC 자동조제기, 약포지 printer, PC monitors, 약 봉투, medicine fridge, prescription intake tray, 번호표 발권기 (queue display is a static '027').",
    "Glass partition covers only 5.9 of 17.7 studs; the header spans the rest, so the 조제실 reads as an open half-room.",
    "No waiting chairs for prescription pick-up (only the BP stool); no shopping baskets; no counter-front impulse display (박카스 pyramid, 핫팩, 껌, 마스크, 손소독제).",
    "BP machine = box + cylinder cuff; scale = flat slab with no display.",
    "All-white flat surfaces, flat ceiling with strip grid; 0 Sound instances."
   ],
   "realWorld": [
    "Front: 휴일지킴이 / 영업시간 sign on the door, green cross, 처방전 접수 sign",
    "Counter: long white counter with POS + card terminal, 처방전 접수함 (tray), 번호표 발권기 + LED queue display with chime, 약 봉투 stacks, receipt printer, impulse display of 박카스/비타500/까스활명수 boxes, 핫팩, 껌, 마스크, 손소독제",
    "Behind the counter (pharmacist reach): 일반의약품 boxes on shelves sorted by category (감기약, 해열진통제, 소화제, 파스, 연고), cough syrups, 안약",
    "Open self-select shelves: 건강기능식품 (비타민, 유산균, 오메가3), 더마 화장품, 밴드/소독약, 마스크, 생리대, 칫솔/치약, 아기용품",
    "Drink fridge (피로회복제, 비타음료, 쌍화탕) at the counter",
    "조제실 behind glass: ATC 자동 정제분포기, 약포지 포장기, 조제대 with pill trays + spatulas, 약장 (drawers), PTP 박스 shelves, 의약품 냉장고, PCs with 팜IT3000-style screens, 시럽 bottles",
    "Waiting: bench/chairs, 자동 혈압계 + 체중계 (BMI printout), health posters (금연 상담, 의약품 부작용 피해구제)",
    "Framed 약사 면허증 + 약국 개설 등록증, 휴일지킴이약국 notice; bright white 5000-6500K panel lighting"
   ],
   "interactionIdeas": [
    "번호표 뽑기 at a ticket dispenser -> queue display counts up to your number with a 딩동 chime, then '상담하기'",
    "Consult: symptom picker (감기/소화/근육통/피로) -> pharmacist reaches to the OTC wall behind the counter and puts the box on the counter",
    "Shelves: pick supplements into a basket (needs shelf names ShopLife understands or a custom pick flow)",
    "Drink fridge: door opens, take 피로회복제, twist cap + gulp anim (rest effect)",
    "BP machine: sit on BPSeat, cuff inflates (tween), screen shows SYS/DIA/pulse; scale: step on -> weight/BMI slip",
    "Prescription pick-up: 약 봉투 handed over at the counter (prop in hand)"
   ],
   "enterable": true
  }
 ],
 "notes": "Workspace.Gwangalli.shops holds 7 walk-in ground-floor GwShop shops on 광안해변로 (Models tagged GwShop, attrs ShopId + DisplayName): each = Shell (ShopFloor, 2 ShopWall, ShopBackWall, ShopCeiling, Skirting, extra wall finishes, 3 invisible LightHost with SurfaceLight tagged InteriorLight AlwaysOn), Interior (ZoneLOD model: furniture, props, Life/FitOut/Detail sub-models, NPC rigs, Table_n), Points (GwShopPoint Point_<kind>_<n> + GwShopSpot Spot_n), ShopBounds (invisible box of the walk-in room) and exterior Sign_ boards. All share floor top Y 6.8 and ceiling underside Y 16.7 (9.9 studs clear), yaw ~180 deg (+1.5..+4.5 deg following the beach road), entrance on the world -z side. The shop front (glass T=0.55, AutoDoor, fascia, awning) belongs to separate host facade models under Workspace.Gwangalli.beachfront whose names do not match the shop (광안 기념품샵 PORT, 비치용품 · 튜브대여, 부산어묵 광안점, 행복 돼지국밥, 광안 치킨 & 맥주, 해변 호프, 바삭치킨) and contain no interior. Local frame used in this survey: u = ShopBounds RightVector (~world -x), w = ShopBounds back axis with +w toward the entrance (~world -z); rooms[].center/size are world (size = across x height x depth). Build quality overall: 234-593 primitive Parts per shop, 0 MeshParts/Unions, no textures (1-2 Decals are NPC faces), SurfaceGuis only on signs, 0 Sound instances, lighting = 3 SurfaceLights + neon slabs. A copy-pasted FitOut kit (cassette ACs, CCTV + CCTV monitor GUI, exit sign, extinguisher, smoke detectors, wall speaker, cert frames, Wi-Fi 'PW 12345678', umbrella stand, door mat) appears near-identically in all 7; the 'Sign_10월' calendar puts Oct 1 on a Wednesday (2025 layout; Oct 2026 starts on Thursday). Back-of-house doors (Door_staff, Door_restroom, StaffDoor, ShowerDoor, SwingDoor) are panels on solid walls: no restroom, stockroom, shower or staff room exists anywhere; chicken and gukbap kitchens are sealed. Runtime: GwangalliShopsShared (place) documents a dedicated map Shops server/client (GwangalliGameplay/Shops.luau, StarterPlayerScripts/GwangalliShops, remote ShopRequest) that is NOT present in v7, so the ShopLife add-on (hostShops=false) runs all 7 shops through the place's ShopLife/Scan name matching; GwShopSpot ambient spots, curtain opening (OpenOffset), FitStand/StylistSpot choreography and SH.MENU prices are unused. Other consumers: ShopStaff (adopts every GwShopClerk rig: NPC attrs + 말 걸기 prompt), GwangalliShopService (greetings, pickup calls, PathfindingService waiter for table shops chicken/gukbap), Play.Career.Gukbap + GwangalliWorkSpots/WorkPlacement (gukbap job), DetailLOD (ZoneLOD Interior radius 103-126, NearLOD Detail models), GwangalliWorld/Lights (InteriorLight). Scan quirks the new interiors should account for (names, not code): chicken 'Purifier' and snack's missing purifier make ShopLife spawn a FoodKit purifier through Scan.freeSpot on the storefront edge (hframe +Z = entrance side for GwShop ShopBounds); surf has no retail shelf names so nothing can be bought; clothing exposes only its 2 DisplayTables as shelves; chicken lacks a TapPost/TapHandle for the coded 생맥 tap mini-game; snack has no cook/pass/counter part; gukbap's restroom prompt is unreachable behind the PassCounter; gukbap water station lands on a table WaterBottle; the salon's styling chairs are assembled backwards around their Seats; the fitting-room curtains are collidable and never open. Safe upgrade path (as done for car interiors): a client LocalScript that hides crude parts with LocalTransparencyModifier (same mechanism DetailLOD uses, so it must re-apply after DetailLOD shows the zone) and builds detailed replacements near the player keeps every server system working, provided the server parts stay (names, positions, Seat CFrames, tags, attrs), replacement geometry is CanCollide/CanQuery false or matches the collision footprint of hidden collidable parts (counters, PassCounter, StationBody, partitions, curtains, plinths), aisles stay open for the PathfindingService waiter and the gukbap work spot (-897.5,8,104), and nothing is placed in the AutoDoor swing zone. Fixes that need server-visible parts (WaterPurifier/TapPost/WallRack names, an opening curtain, a reachable restroom door, reoriented salon chairs) must be done server-side. Full findings JSON (adds per-venue localFrame, npcs, doors, all sign texts, repeat-variety stats and a complete grouped part inventory): /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/shops.json. Working files: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/shp/ (dumps <ShopId>.txt, local layouts L_<ShopId>.txt, raw.json, props.json, rooms.json, psrc/ extracted place scripts)."
}
```

## survey:hotels_homes

```json
{
 "venues": [
  {
   "name": "호메르스호텔 HOMERS HOTEL (광안해변로 217, 20F, 152 rooms attr) - lobby, wedding lobby, 2F-4F banquet strip, 6F front lounge, 6 ON ROOF TOP",
   "path": "Workspace.Gwangalli.landmarks['호메르스호텔 HOMERS HOTEL'] (+ sibling Workspace.Gwangalli.landmarks['현관 디테일 · 호메르스호텔'])",
   "bounds": "(152.5,6.0,100.7)..(293.6,255.9,231.4); lobby (256.7,6.5,114.5)..(279.9,21.4,151.7)",
   "enterable": true,
   "rooms": [
    {
     "name": "1F 호텔 로비 Lobby (walk-in via AutoDoor LobbyDoor at x266-271 z114.8; elevators on back wall z150.5)",
     "center": [
      268.65,
      13.68,
      132.85
     ],
     "size": [
      21.9,
      13.85,
      35.7
     ],
     "floorY": 6.75,
     "ceilingY": 20.6
    },
    {
     "name": "1F 호메르스 웨딩 · 컨벤션 로비 (walk-in via WeddingDoor AutoDoor x166-170 z116.3)",
     "center": [
      169,
      13.4,
      126.3
     ],
     "size": [
      27.4,
      13.25,
      19.8
     ],
     "floorY": 6.75,
     "ceilingY": 20
    },
    {
     "name": "2F 다이닝홀 strip behind facade glass (UNREACHABLE, Core solid behind z>131.4)",
     "center": [
      222.8,
      29,
      122.55
     ],
     "size": [
      104.2,
      10.6,
      16.5
     ],
     "floorY": 23.7,
     "ceilingY": 34.3
    },
    {
     "name": "3F 웨딩홀 strip (UNREACHABLE)",
     "center": [
      222.8,
      41.5,
      122.55
     ],
     "size": [
      104.2,
      10.6,
      16.5
     ],
     "floorY": 36.2,
     "ceilingY": 46.8
    },
    {
     "name": "4F 크리에이티브홀 / 연회장 strip (UNREACHABLE; 5F band is a solid Core 104x11.7x15 at y60.5-72.3)",
     "center": [
      222.8,
      54,
      122.55
     ],
     "size": [
      104.2,
      10.6,
      16.5
     ],
     "floorY": 48.7,
     "ceilingY": 59.3
    },
    {
     "name": "6F 프론트 · 라운지 (UNREACHABLE; real Homers front desk is on 6F)",
     "center": [
      223.45,
      79.35,
      168.1
     ],
     "size": [
      94.7,
      12.1,
      25
     ],
     "floorY": 73.3,
     "ceilingY": 85.4
    },
    {
     "name": "6 ON ROOF TOP 루프탑 라운지 terrace on podium roof (UNREACHABLE; open sky, string-light canopy y~83-86)",
     "center": [
      222.95,
      79,
      134.5
     ],
     "size": [
      136.5,
      11.3,
      41.8
     ],
     "floorY": 73.35
    },
    {
     "name": "주차장 램프 B1-B4 portal (fake: RampVoid black 9.9x7.9 panel at z178, no garage)",
     "center": [
      286.7,
      10.5,
      167.8
     ],
     "size": [
      11.7,
      8,
      21.9
     ],
     "floorY": 6.6,
     "ceilingY": 13.9
    }
   ],
   "props": [
    "1F lobby (63 visible non-shell parts in 782 sq studs = 8.1/100sq): LobbySofa x1 (2-seat, navy 58,68,96 leather: Plinth 6.6x0.3x2.8, Base 7x0.85x2.6, Backrest 7x3.9x0.8, 2 Seat, 2 Arm, 2 BackCushion - all boxes), armchair x2 (Plinth+Seat 1.8x1.15x2.3+Back 2.8x2.6x0.6+2 Arms, tan leather), round side table (TableLeg cylinder + TableTop) with glass Vase 1.2 + 4 Bloom balls + Greenery, potted Plant x1 (2.2 ball pot + 2 ball-mesh leaves), Rug 12x11.5 burgundy carpet, ChandelierCore neon ball 1.56 (PointLight AlwaysOn, tag InteriorLight) + ChandelierRod + 6 Crystal glass bars + 2 ChandelierRing, Downlight x4 (only near the entrance z~116.6), CoveSoffit x4 + CoveLED x4 (perimeter cove), elevators x3 (6 ElevatorDoor leaves 2.16x8.6 brushed metal, 6 jambs, 3 heads, 3 FloorIndicator neon 1.2x0.34, 3 CallButton plates), Sign_HOMERS HOTEL 17x2.4 on back wall reading 'HOMERS HOTEL / 6F FRONT DESK · 6 ON ROOF TOP'",
    "1F lobby shell: Floor 22.7x0.25x36.6 single marble slab (228,224,216), Ceiling 22.7x0.8x36.4 plain, west SideWall + BackWall marble 200,188,168, east wall = exterior LaneWall (concrete facade material 214,208,198 visible inside), front = 3 LobbyGlass 5.65x13.45 T0.45 + LobbyDoor AutoDoor (2 DoorLeaf 4.5x9.75 + 2 DoorStile, OpenOffset ±4.1) + DoorHeader",
    "1F wedding lobby (9 parts in 543 sq studs = 1.7/100sq): Plant x2, Sign_Wedding 12x4 ('3F 웨딩홀 · 4F 크리에이티브홀 · 5F 오딧세이홀'), Floor 28.2x20.6 marble, Ceiling, BackWall 188,172,144; outside GlassCanopy 16x6.6 + 2 TieRods, Sign_호메르스 웨딩 & 컨벤션 24x2.6",
    "2F dining strip: TableTop x8 (3.6x0.3x3.6 boxes) + TableLeg x8, Chair x16 (each ONE box 1.6x3.4x0.8 wood), CeilingLight x4 strips; 3F: VirginRoad 6x0.06x15.8, FlowerStand x8 + Flowers x8, Chandelier x3 (4.6x2.6x4.6 Neon boxes); 4F: BanquetTable x6 (cylinder 5.4 dia, no chairs), Centerpiece x6 (1.4 boxes); Floor_2F wood 170,130,90, Floor_3F carpet white, Floor_4F carpet 120,40,50; BackWall x3 236,226,206",
    "6F front lounge (41 parts in 2368 sq studs = 1.7/100sq): FrontDesk Model (ToeKick 25.9 + Body 26x3.15x2.2 wood + marble Top 26.4x0.3x2.7 + LedStrip) - no monitors, bell, key encoder, logo wall; Sign_HOMERS HOTEL  FRONT DESK 20x2.6; LoungeSofa x2 (4-seat, navy), LowTable x2 6x1.5x2.5, PendantBulb x3 + PendantShade/Cord; Floor 94.4x25.8 wood, LoungeGlass 94.8x12.1 single pane, BackWall wood 92,62,42",
    "6 ON ROOF TOP (261 parts in 5706 sq studs = 4.6/100sq): TerraceDeck 136x0.35x40.8 wood, Balustrade x3 glass + Handrail x3, sofa sets x4 (SofaBase 11x1.3x3 + SofaBack + 2 SofaArm, 25 Seat), CoffeeTable x4 + TableCandle x4 (neon), lounge chairs x8 (ChairBase 3x1x2.8 + ChairBack), parasols x4 (pole + 12-dia disc canopy + top), TerraceBar 22x3.6x3 + wood top + BarLed + BarShelf (43 Product bottles, 2 PriceRail) + 5 stools, Planter x3 + Shrub x9, Sign_6 ON ROOF TOP, LightPost x5 + Wire x28 + Bulb x63 (NightNeon festoon)",
    "현관 디테일 · 호메르스호텔 (outside porte-cochere): Sign_★★★★ (4성), 벨카트 Luggage Cart (deck + brass uprights + 2 suitcases), 우산 비닐 포장기 (WrapperBody 1.4x3.4x1), 발렛파킹 podium + Sign_VALET, FlagPole x3 + Sign_HOMERS flags, Bollard x7; Canopy 30.5x1.2x12 + CanopyLight, Destination '호메르스호텔' at (268.3,7,107.8)",
    "Upper floors 7F-20F: Core 93.8x147x61.5 solid block (y87-234) behind 312 NightWindow glass panes + 79 Curtain parts; no rooms exist; roof: helipad, ElevatorMachineRoom, cooling towers, water tank, AC units",
    "Lighting: whole model has 5 PointLights (InteriorLight) total; most 'lights' are Neon/NightNeon slabs"
   ],
   "gameplay": [
    "AutoDoor (GwangalliDoors server + GwangalliDoorsClient): models LobbyDoor, WeddingDoor tagged AutoDoor; leaves carry OpenOffset (world V3) / ClosedCFrame / Collides attrs - keep names, tags, attributes and leaf CFrames",
    "Annex (GwangalliBuildings/Annex via MapIndex): the hotel Model (Core/Pier/Spandrel children, name contains 호텔/HOTEL) is an Annex entry of arch 'hotel'; DoorLeaf parts (DOOR_KIND main), ServiceDoor (back) and Sign_* parts are read to place '들어가기' prompts and a 층별 안내 directory -> teleports to a procedural A.hotel instance at the y=3000 band. Do not rename DoorLeaf/ServiceDoor/BackDoor/Sign_* or add parts named Door/DoorLeaf/LobbyDoor/GlassDoor (they would become new Annex doors); model attribute Annex=false removes the Annex inside",
    "MapIndex: indexed as building cat 'hotel' (minimap / full map); '현관 디테일' prefix is skipped",
    "Destination tag parts (taxi Career/Taxi, JobDelivery, Journey, Citizens, Mind, HUD waypoints, GwangalliNav): '호메르스호텔' (268.3,7,107.8) and the Bronx one - keep",
    "NightWindows client: 294 NightWindow-tagged panes (Zone hotel, LitChance/LitColor/LitSeed) light at night; StreetSigns: NightGlow/NightNeon/NeonTube/LEDScreen/NearLOD tags; GwangalliIndoorLight dims PointLights under a roof (x0.55, range<=18)",
    "ShopStaff: anchors must be BaseParts named PosBase/POS/BarCounter/FrontDesk... outside storefronts; FrontDesk here is a Model, so NO hotel staff NPC is spawned in the lobby or on 6F",
    "GwangalliInteractShared.PHOTO_SPOTS 'rooftop' = 호텔 루프탑 라운지 at (209,75,135) r45 yMin60 - currently cannot be reached on foot (no stair/elevator/ElevatorButton to 6F)",
    "MiniGamesShared 'memory_east' street mini-game labelled '호메르스호텔 앞' (outdoor)",
    "Lobby elevators are decoration: no ElevatorButton/ElevatorStop parts (the Venues.luau ElevatorButton contract Floor/Target='ElevatorStop_<n>' is only used in the bowling building)"
   ],
   "emptyOrCrude": [
    "Everything above 1F is unreachable: 2F-4F, 6F front lounge and 6 ON ROOF TOP have no stair, escalator or working elevator, so the real 6F check-in floor and the rooftop photo spot are display-only; the lobby sign advertises '6F FRONT DESK'",
    "1F lobby has no reception/bell desk, no 층별 안내 directory, no luggage storage, only 1 sofa + 2 armchairs (4 seats in 782 sq studs); elevator hall z136-151 is bare floor",
    "Lobby floor is one 22.7x36.6 marble slab (no inlay, joints, entrance mat or windbreak vestibule), ceiling one flat slab (perimeter cove + 4 downlights at the door), east wall raw exterior concrete",
    "All furniture is boxes (sofa = 6-8 boxes, 2F chairs single 1.6x3.4x0.8 boxes, 3F chandeliers neon boxes); no MeshParts/Textures/Decals; only 5 real lights for the whole hotel",
    "Wedding lobby almost empty (2 plants + 1 sign in 543 sq studs): no 축의금 접수대, 방명록, 웰컴보드 이젤, 화환, 하객 소파, no elevator/escalator to the halls",
    "3F wedding hall has no stage/backdrop or guest chairs; 4F banquet round tables without chairs; 2F dining has no buffet line (real 2F = 조식당)",
    "6F front desk is a bare box counter (no monitors, card terminal, key-card encoder, world clocks, logo wall); 25.8-deep lounge with 2 sofas only",
    "Rooms 7F-20F do not exist (solid Core); parking ramp is a black panel",
    "No staff NPC anywhere (ShopStaff ignores Model FrontDesk)"
   ],
   "realWorld": [
    "Real Homers (호텔 호메르스 광안리, 광안해변로 217): 1F 수제맥주 펍 (Bronx), 2F 조식당 + 소규모 세미나실, 3F 웨딩홀, 4-5F 연회장, 6F 프런트 + '6 ON ROOF TOP' 라운지, 7F+ 오션뷰 객실 (mom-mom.net, trip.com listings)",
    "1F elevator lobby of an upper-floor-front hotel: 자동문 + 바람막이 전실, 우산 비닐 포장기 inside the vestibule, 대형 '6F FRONT' 방향 사인 + 층별 안내판 (B1-B4 주차, 1F 펍, 2F 레스토랑, 3F 웨딩, 6F 프런트/루프탑, 7-20F 객실), 벨데스크 or 무인 안내 키오스크, 짐 카트, 엘리베이터 홀 (상/하 호출버튼 panels, 홀랜턴 화살표, 층 표시 LED, 정원/중량 표지), 대리석 바닥 패턴 + 현관 매트, 간접조명 천장 + 펜던트, 아트월, 꽃 센터피스, 대기 소파 그룹, 비상구 녹색 유도등, 소화기함, CCTV 돔, 금연 표지",
    "6F front desk: 2-3 체크인 스테이션 (모니터, 키카드 인코더, 카드 단말기, 데스크 벨, 브로셔 스탠드), 로고 월 + 세계 시계 4개 (SEOUL/NEW YORK/LONDON/TOKYO), 대기 라인 스탠션, 컨시어지, 웰컴 드링크 바, 라운지 좌석 + 통창 오션뷰, 짐 보관실 문, 화장실 표지",
    "Wedding/convention lobby: 안내 데스크, 축의금 접수대 x2 (신랑측/신부측), 방명록, 웰컴보드 이젤 + 포토테이블, 축하 화환 줄, 하객 대기 소파, 연회장 일정 LED, 에스컬레이터/엘리베이터",
    "Rooftop lounge: 바 카운터 + 백바 조명, 칵테일/맥주 메뉴 보드, 하이테이블 + 바스툴, 소파 부스, 야외 가스 히터, 파라솔, 전구 줄조명, 유리 난간, DJ 부스/스피커, 광안대교 포토 프레임"
   ],
   "interactionIdeas": [
    "Lobby elevator call panel ProximityPrompt '6F 프런트 · 루프탑' -> door open -> fade ride using the existing ElevatorButton/ElevatorStop contract (ElevatorStop parts on the 6F floor y73.3 and in the lobby) so 6F lounge, 6 ON ROOF TOP and photo spot 'rooftop' become reachable",
    "6F front desk '체크인' handing off to the Annex hotel check-in (ShopFlows hotel_lobby frontdesk -> GwB_HotelRoom key card); '짐 맡기기', '와이파이 비밀번호 보기'",
    "Bell cart push (carry luggage), umbrella wrapper 'wrap umbrella', valet podium '발렛 맡기기' (calls the player's car)",
    "Rooftop bar: '칵테일 주문' (bartender shake), sit at sofa/parasol tables, framed 광안대교 photo spot, string lights by DayNight",
    "Wedding lobby: '축의금 내기' (envelope + 방명록 서명), '포토테이블 사진'",
    "Lobby coffee/water station, brochure rack 'take map', luggage locker"
   ]
  },
  {
   "name": "브롱스브루잉 광안리BP점 BRONX BREWING (Homers 1F craft beer pub)",
   "path": "Workspace.Gwangalli.landmarks['호메르스호텔 HOMERS HOTEL']['브롱스브루잉 광안리BP점 BRONX BREWING']",
   "bounds": "(182.7,6.5,103.1)..(257.4,21.8,164.8)",
   "enterable": true,
   "rooms": [
    {
     "name": "Pub hall (walk-in via 2 PubDoor AutoDoors at x~203.7 and x~239.7, z115.3)",
     "center": [
      219.85,
      13.9,
      139.5
     ],
     "size": [
      72.7,
      14.25,
      47.8
     ],
     "floorY": 6.75,
     "ceilingY": 21
    },
    {
     "name": "Brewery tank room behind BreweryGlass (x184-205, z146.7-163)",
     "center": [
      194.5,
      13.9,
      155
     ],
     "size": [
      21,
      14.25,
      16.6
     ],
     "floorY": 6.75,
     "ceilingY": 21
    },
    {
     "name": "Street terrace under PubCanopy (barrel tables)",
     "center": [
      219.6,
      12,
      109
     ],
     "size": [
      70,
      11,
      7
     ],
     "floorY": 6.6,
     "ceilingY": 17.7
    }
   ],
   "props": [
    "339 visible parts in 3475 sq studs (9.8/100sq): BarCounter Model (Body 41x3.25x2.7 metal + wood Top 41.4x0.3x3.2 + LedStrip + ToeKick) + FootRail 41, BackBarCabinet 41x3.6x3.2 + BackBarTop, BottleShelf (MirrorBack 19.7x7.3 + 3 glass BarShelf + 3 ShelfGlow + 97 Bottle cylinders 0.9x0.31), TapWall 18.5x7.2 + TapManifold + Tap x12 + TapTower x6 + TapHandle x18, Sign_BRONX ON TAP 12 (IPA · PALE ALE · 광안 LAGER · STOUT · WEIZEN), Sign_TODAY'S BEER board 6x5, Sign_BRONX neon",
    "Seating: Seat x41 (1.6x0.3x1.6 square pads on single StoolLeg cylinders, no backrests), CommunalTable 12x0.3x2.4 + 2 legs, ~8 round TableTop cylinders 3.4 dia with BeerGlass + BeerFoam x18, BarrelTable x4 + BarrelHoop x4 outside",
    "Brewery: BreweryGlass 21.2x14 T0.6 + frame, BrewTank x3 (cylinder 8.2x4.8) + BrewTankDome x3 + Manifold x2 + TankPipe x3, Keg x3",
    "Ceiling/walls: Duct x2 (72-long cylinders) + CableTray, PendantBulb x11 + shades/cords, ScreenHousing x3 + LEDScreen x3 (Messages 'LIVE 롯데 자이언츠 vs 두산|BRONX IPA · 광안 LAGER|HAPPY HOUR 17:00-19:00'), BrickWall 72.4x14.25, dark SideWalls, Floor 72.4x47.85 single concrete slab",
    "Storefront: PubGlass x5 12.4x10.8, Muntin x12, KickPlate x3, SteelPier x2, Fascia 74x3.3, Sign_BRONX BREWING 34x3.4, Sign_브롱스 광안리BP점 ('CRAFT BEER PUB · 12:00 - 02:00'), Sign_CRAFT BEER + 4 NeonTube, Sign_ON TAP, PubCanopy 70x7 + 3 CanopyRod; Destination '브롱스 광안리 (호메르스호텔 1F)' (239.5,7,105.2)"
   ],
   "gameplay": [
    "AutoDoor PubDoor x2 (OpenOffset ±2.8)",
    "No ordering/eating: ShopLife only scans street shops (Interior + ShopFloor), GwShop-tagged shops and the GS25 venue; this pub has neither",
    "ShopStaff: BarCounter is a Model (LOOSE anchors must be BaseParts) -> no bartender NPC although KINDS lists '브롱스' under pub",
    "LEDScreen messages cycled by StreetSigns; Destination used by taxi/delivery/HUD/Street Events/Mind Talk lines that mention 브롱스",
    "Annex reads the PubDoor DoorLeaf parts as 'main' doors of the Homers building and the Sign_BRONX* texts as shop destinations"
   ],
   "emptyOrCrude": [
    "Stools are flat square pads on a pole (41 identical); round tables are bare discs",
    "No restroom, no kitchen pass, no POS or table-order tablets, no glass rack, no beer fridge, no table menus, no darts",
    "Single-slab floor, plain dark side walls; tap handles plain bars without beer names; bottles uniform cylinders",
    "Back half (z147-163) only has the tank glass; no tasting bar facing the tanks"
   ],
   "realWorld": [
    "Korean craft beer pub: 15-20 탭 with branded handles + 맥주 이름/ABV 칠판, 맥주잔 냉각 렉 + 잔 세척기, 병맥주 쇼케이스, 등받이 바 스툴, 하이테이블, 테이블 QR 오더/호출벨, 스포츠 중계 TV (롯데 자이언츠), 피자/감자튀김 주방 패스 + 픽업 벨, 다트 기계, 굿즈 진열, 양조 탱크 투어 창, 화장실 표지, POS + 카드 단말기, 야외 바렐 테이블"
   ],
   "interactionIdeas": [
    "Pull a tap (IPA / PALE ALE / 광안 LAGER / STOUT / WEIZEN -> glass fills, foam)",
    "Sit at bar/table -> table-order tablet UI; call bell",
    "Darts minigame; '경기 보기' on the LED screens",
    "Brewery window tour camera; buy merch glass"
   ]
  },
  {
   "name": "수영구 생활문화센터 · 광안리 관광안내소 (광안해변로 219, 5F) - tourist info, 여름경찰서, 바다갤러리",
   "path": "Workspace.Gwangalli.landmarks['수영구 생활문화센터 · 광안리 관광안내소']",
   "bounds": "(43.6,6.0,102.7)..(145.7,94.2,233.0)",
   "enterable": true,
   "rooms": [
    {
     "name": "광안리 관광안내소 Tourist Information Center (walk-in via InfoDoor AutoDoor x102-107 z120.8)",
     "center": [
      110.9,
      13.6,
      142.3
     ],
     "size": [
      60,
      13.65,
      43
     ],
     "floorY": 6.75,
     "ceilingY": 20.4
    },
    {
     "name": "광안리 여름경찰서 - visible through glass only: Door parts are static collidable glass; BackWall at z143.3 leaves a hidden void z143.7-165",
     "center": [
      63.8,
      13.3,
      132
     ],
     "size": [
      30.2,
      13.05,
      21.8
     ],
     "floorY": 6.75,
     "ceilingY": 19.8
    },
    {
     "name": "바다갤러리 SEA GALLERY 2F-3F double-height strip (UNREACHABLE)",
     "center": [
      92.75,
      36.45,
      126.75
     ],
     "size": [
      64.1,
      25.5,
      22.3
     ],
     "floorY": 23.7,
     "ceilingY": 49.2
    }
   ],
   "props": [
    "Tourist info (220 parts in 2580 sq studs = 8.5/100sq): InfoCounter Model 20 wide (white wood Body + marble Top + blue LedStrip) + CounterWave stripe, Monitor x2 (2.4x1.6 boxes, no screens), staff Seat x2, Sign_TOURIST INFORMATION 26x3.2 ('관광안내 · 旅游咨询 · 観光案内'), LEDScreen 12x6.2 (Messages '광안리 M 드론라이트쇼 SAT 20:00|WELCOME TO GWANGALLI|부산불꽃축제 11.7 SAT|광안리어방축제 JUNE'), BrochureRack x3 (36 Product brochure slabs each = 103), Locker x4 (2.8x8x2.6 plain blue boxes, 1 LockerHandle) + Sign_짐보관함 LUGGAGE STORAGE, ChargingStation box + ChargingLed + Sign_휴대폰 충전 · FREE Wi-Fi, WaitingSofa (3-seat), 유모차 · 휠체어 대여 (2 wheelchairs of discs + seat + back, 2 strollers of boxes), PhotoPrintKiosk 3x5.4x3 + KioskScreen, 트릭아트 포토존 (22x12.6 wall sign + GildedFrame x4 + bridge drawing of parts + 2 FootMarks), CeilingLight 8x2 (SurfaceLight) + CeilingLine x2",
    "Police box (13 parts in 658 sq studs = 2.0/100sq): PoliceDesk 22 wide (navy body, white top), Monitor x2 boxes, Seat x2, Sign_POLICE 광안리 여름경찰서, CeilingLight 26x2 NightNeon slab; outside Car_Police (Sonata 순찰차, full interior) at (62.7,7.3,111.4), Sign_광안리 여름경찰서 ('POLICE · 부산수영경찰서 112')",
    "Sea gallery (11 parts in 1429 sq studs = 0.8/100sq): 5 poster panels 8x6 (광안리의 새벽 / 노을과 광안대교 / 드론라이트쇼 / 민락의 바다 / 불꽃축제, SurfaceGui text), SpotLight x5 (flat NightNeon bars), GalleryBench x2, GalleryGlass x16",
    "Outdoor: SUP보드 안내판 (4 boards), 건물명 표지석 + benches + InfoPylon 'i', 세족장 Foot Wash (trough + 4 taps + 2 shower posts), 3 flags",
    "Upper floors 4F-5F: Core solid; StairPenthouse box + RoofDoor; 12 SolarPanels"
   ],
   "gameplay": [
    "Details.luau lost-wallet quest builds '분실물 센터 (관광안내소)' counter at runtime OUTSIDE the door at (96,6.5,101) tagged GwLostFound; returnWallet requires the player within 16 studs - keep clear",
    "Destination '광안리 관광안내소' (104.7,7,111.7): ctx.setWaypoint in Details/Play.Street, taxi/nav/MapData, Street Events, Pocha/Mind lines",
    "PHOTO_SPOTS 'info' (105,7,112) r45; MiniGamesShared 'wordchain_center' '관광안내소 앞'",
    "AutoDoor InfoDoor; LEDScreen messages; InteriorLight SurfaceLight",
    "Annex: 문화센터/관광안내 -> PUBLIC building (one room); InfoDoor DoorLeaf = main, BackDoor = back, police 'Door' parts = 'shop' doors -> '들어가기' prompts",
    "ShopStaff: InfoCounter/PoliceDesk are Models -> no staff NPC",
    "StreetInteract/Cast has a 여름경찰서 police NPC bio (street cast)"
   ],
   "emptyOrCrude": [
    "Tourist info: no staff, no wall map / touch kiosk, monitors are black boxes, lockers are plain boxes without doors/keypads, wheelchairs/strollers are disc-and-box sketches, no souvenir shelf, no water purifier, no restroom signage",
    "Police box nearly empty (desk + 2 chairs + sign) and not walk-in; 21-stud hidden void behind its back wall",
    "Sea gallery: 5 flat posters and 2 benches in a 64x23x25.5 hall; no partitions, plinths, captions, docent desk; unreachable"
   ],
   "realWorld": [
    "광안리 관광안내소: 다국어 상담 카운터 (한/영/중/일), 광안리·부산 관광지도 월 + 터치스크린 키오스크, 언어별 브로슈어 랙, 무료 짐보관함 (번호식/QR, 칸마다 문), 휴대폰 충전 스테이션, 휠체어·유모차 대여, 부산 굿즈/기념품, 트릭아트 포토존, 대기 의자, 정수기, 와이파이 안내, 행사 LED, 분실물 센터, 수유실/화장실 안내, 스탬프 투어 도장대",
    "여름경찰서: 민원 접수 카운터 + 아크릴 칸막이, 분실물 선반 + 습득물 대장, 미아 보호 매트, 구급함 + AED, 구명튜브/구명조끼, 안전 포스터 (몰카·성범죄 예방, 음주 수영 금지), 무전기 충전대, CCTV 모니터, 근무 화이트보드, 태극기, 포돌이 스탠디, 대기 벤치, 112 표지",
    "Community gallery: 가벽 + 캡션, 트랙 조명, 좌대 오브제, 영상 스크린, 안내 데스크 + 방명록, 전시 포스터, 계단/엘리베이터"
   ],
   "interactionIdeas": [
    "Info counter '관광 안내 받기' -> waypoint menu (Destinations), '스탬프 찍기' collection",
    "Brochure 'take map', locker 'store item' (code keypad UI), phone charging, wheelchair/stroller rental",
    "Photo print kiosk after a trick-art photo (spot 'info')",
    "Police box: '분실물 신고/습득물 맡기기' (lost-wallet tie-in), '미아 찾기' quest, '길 묻기'",
    "Gallery artwork caption prompts, guestbook"
   ]
  },
  {
   "name": "호텔 아쿠아펠리스 HOTEL AQUA PALACE (광안해변로 225, 21F) - lobby, leisure front, 2F 광안차이나, 6F waterpark, 8F-9F 찜질방, 21F observatory, rooftop infinity pool",
   "path": "Workspace.Gwangalli.landmarks['호텔 아쿠아펠리스 HOTEL AQUA PALACE'] (+ Workspace.Gwangalli.landmarks['현관 디테일 · 호텔 아쿠아펠리스'])",
   "bounds": "(-120.8,6.0,103.0)..(36.7,276.5,231.2); lobby (-63.4,6.5,116.5)..(-21.1,21.3,163.0)",
   "enterable": true,
   "rooms": [
    {
     "name": "1F 호텔 로비 Lobby (walk-in via LobbyDoor AutoDoor x-44..-38 z117; penthouse HomeEntrance portal right in front at (-41.3,10.05,114.7))",
     "center": [
      -42.25,
      13.3,
      139.7
     ],
     "size": [
      41.5,
      13.15,
      44.8
     ],
     "floorY": 6.75,
     "ceilingY": 19.9
    },
    {
     "name": "1F 워터파크 · 스파 입구 / LEISURE FRONT (walk-in via WaterparkDoor AutoDoor x-4..2 z117.2)",
     "center": [
      -0.6,
      13.3,
      139.8
     ],
     "size": [
      36.8,
      13.15,
      45
     ],
     "floorY": 6.75,
     "ceilingY": 19.9
    },
    {
     "name": "2F 광안차이나 restaurant strip (UNREACHABLE)",
     "center": [
      -41.3,
      28.2,
      123.05
     ],
     "size": [
      152,
      10.2,
      14.1
     ],
     "floorY": 23.1,
     "ceilingY": 33.3
    },
    {
     "name": "6F 아쿠아펠리스 워터파크 hall (UNREACHABLE; pools sunk to y65-66.5)",
     "center": [
      -41.45,
      80.8,
      172.85
     ],
     "size": [
      152.7,
      20.6,
      112.9
     ],
     "floorY": 70.5,
     "ceilingY": 91.1
    },
    {
     "name": "8F 찜질방 strip (UNREACHABLE, 10.2 deep)",
     "center": [
      -41.4,
      108.6,
      139.2
     ],
     "size": [
      113.6,
      10.2,
      10.2
     ],
     "floorY": 103.5,
     "ceilingY": 113.7
    },
    {
     "name": "9F 찜질방 strip (UNREACHABLE)",
     "center": [
      -41.4,
      119,
      139.2
     ],
     "size": [
      113.6,
      10,
      10.2
     ],
     "floorY": 114,
     "ceilingY": 124
    },
    {
     "name": "21F 스카이전망대 SKY OBSERVATORY (UNREACHABLE)",
     "center": [
      -41.45,
      247.25,
      160.3
     ],
     "size": [
      115.1,
      14.9,
      54.6
     ],
     "floorY": 239.8,
     "ceilingY": 254.7
    },
    {
     "name": "21F 스카이워크 glass-floor cantilever",
     "center": [
      -41.35,
      241.6,
      120.95
     ],
     "size": [
      18.1,
      4,
      24.1
     ],
     "floorY": 239.8
    },
    {
     "name": "루프탑 인피니티풀 deck (UNREACHABLE, open sky)",
     "center": [
      -41.4,
      258,
      160.2
     ],
     "size": [
      116.2,
      3,
      57.8
     ],
     "floorY": 256.8
    }
   ],
   "props": [
    "1F lobby (80 parts in 1859 sq studs = 4.3/100sq): FrontDesk Model 18 wide (ToeKick, marble FrontPanel 18x3.3x0.8, Ledge, slate WorkDesk + WorkTop, DeskGlow neon) + 2 Monitors with neon screens + DeskBell, armchair x2 (teal), LobbySofa x1 (2-seat ivory), round TableTop 3 dia + TableFoot, Plant x2, Rug 12x13.2, ChandelierCore 1.87 neon ball (PointLight) + 2 rings + rod + 8 Crystal, Downlight x16, CoveSoffit/CoveLED x4, ONE elevator (2 leaves 1.96x8.6) at x-61..-57, WaterWall 26x4x0.1 glass, Sign_HOTEL AQUA PALACE",
    "Leisure front (20 parts in 1656 sq studs = 1.2/100sq): LeisureFront counter 16 wide, Sign_LEISURE FRONT ('워터파크 · 찜질방 · 인피니티풀 발권'), 2 elevators (4 leaves) at x-18..-8, ONE CeilingLight 34x0.15x36 NightNeon slab as the whole ceiling; Destination '아쿠아펠리스 워터파크 · 찜질방' (-1.3,7,107.1); Sign_6F 워터파크 · 8F-9F 찜질방 · 21F 스카이전망대",
    "2F 광안차이나 (28 parts in 2143 sq studs): Lantern x12 (red neon boxes) + LanternCord x12, RoundTable x4 (cylinders, NO chairs), red carpet, 14 facade glass panes, Sign_광안차이나 ('짬뽕 · 딤섬 · WINE BAR')",
    "6F waterpark (217 parts in 17240 sq studs = 1.3/100sq): WavePool 62x36 (floor, 4 walls, water T0.3, 2 WaveFoam, WaveMachine 54x5.6, Sign '최대 파고 1.5m'), BeachEntry sand 62x12.8, LazyRiver (2 segments + 7 walls), SplashPool 22x14, 2 round SpaPools + Bubbles, BODY SLIDE 90m (24 cylinder segments + 23 ball joints + 6 supports), slide tower (4 legs, 12x12 platform, 8 steps), 7 palms (42 fronds), 12 loungers, 3 parasols, 1 lifeguard seat, CeilingLight x12 (SurfaceLight), Truss x7, 40 glass panes",
    "8F-9F 찜질방 (15 parts): HeatedFloor x2 113.6x10.8, CedarWall x2, Mat x12, CoveLight x2, Sign_황토 불가마 · 편백 찜질방",
    "21F observatory (12 parts in 9058 sq studs = 0.13/100sq): floor 115x56, 20 glass panes, Bench x3, Binocular x4 on posts, Sign_SKY OBSERVATORY 21F ('광안대교 · 해운대 · 마린시티'), 1 CeilingLight 40x4; SkywalkGlassFloor 18x24 T0.55 + beams + balustrades + struts + under-light",
    "Rooftop: InfinityPool 92x17 (floor, 3 walls, InfinityEdgeGlass, CatchChannel, water, PoolLed), RoofDeck 114x36 wood, Lounger x8, Sign_INFINITY POOL ('해수 온천 09:00-21:00'), Sign_HOTEL AQUA PALACE 88x10 on 6 frames, MEP on the deck (cooling tower, AC units, vents, lightning rod, aviation light)",
    "현관 디테일: 벨카트, 우산 비닐 포장기, 발렛 podium, 3 flags, Bollard x9; 주차장 입구 (Driveway, Header, black Void panel - fake garage)",
    "Solid Cores fill 3F-5F and 10F-20F; 235 NightWindow panes"
   ],
   "gameplay": [
    "Life-game 펜트하우스: listing aqua_ph (tier 5, buy) place = Destination '호텔 아쿠아펠리스' (-42.3,7,109.9); HomeEntrance_penthouse portal (Tier penthouse) at (-41.3,10.05,114.7) 2.4 studs in front of the AutoDoor - GwangalliHome creates '집으로 들어가기 / 초인종 / 입주 문의' prompts (reach 18); the unit itself is a ServerStorage template clone far above the map",
    "Annex: hotel entry (DoorLeaf of LobbyDoor/WaterparkDoor/CafeDoor = main doors) -> '들어가기' to the generic A.hotel instance; 3 overlapping systems at one door (AutoDoor walk-in, Annex prompt, HomeEntrance prompt)",
    "Destinations '호텔 아쿠아펠리스', '아쿠아펠리스 워터파크 · 찜질방', 'fondx 홍미당 (아쿠아펠리스 1F)' (taxi, HUD categories, Street Events, Journey buyable-home text)",
    "PHOTO_SPOTS 'infinity' (-60,258,155) r70 yMin220 (unreachable) and 'hotelrow' (-42,7,110)",
    "Grades.HOST_LISTINGS / ProgressShared 'penthouse' reference 아쿠아펠리스",
    "No ShopLife flow and no staff in lobby/leisure front (FrontDesk & LeisureFront are Models); InteriorLight: 3 SurfaceLight + 3 PointLight for the whole model"
   ],
   "emptyOrCrude": [
    "All signature leisure venues (waterpark, 찜질방, observatory, infinity pool, 2F restaurant) are unreachable showpieces: leisure-front elevators are decoration",
    "Lobby 42x46 with one 2-seat sofa, 2 armchairs, a desk (4.3/100sq) and a single elevator for a 21-floor hotel",
    "Leisure front nearly empty: one counter and a whole-ceiling neon slab; no ticket kiosks, price board, gates, shoe lockers, wristband dispenser, swimwear shop",
    "2F restaurant tables without chairs; 찜질방 a 10-stud strip with mats only (no 불가마, rooms, snack bar, TV); observatory 12 props in 9000 sq studs",
    "Waterpark lacks changing rooms/showers/lockers, kids' area, tube racks, snack bar, depth markers, safety signage; slide is ball-and-cylinder segments",
    "Box geometry throughout, no textures; rooms 10F-20F are solid Core"
   ],
   "realWorld": [
    "Real Hotel Aqua Palace: 실내 비치 워터파크 (파도풀, 대형 바디슬라이드), 지하 816 m 온천수 24시간 오션뷰 사우나 + 찜질방, 2F 조식 뷔페, 21F 스카이 전망대 (주말 무료) (ktriptips, mom-mom, trvlogue)",
    "Beach-hotel lobby: 프런트 3-4 스테이션 (모니터, 키카드 인코더, 카드 단말기), 로고 월 + 세계 시계, 벨데스크 + 짐 보관, 컨시어지, 라운지 좌석 그룹, 생화 센터피스, 대리석 패턴 바닥, 엘리베이터 2-4대 + 카드키 리더, 층별 안내, 비상구 유도등, 소화기, ATM",
    "워터파크/스파 매표소: 요금표 (대인/소인/투숙객), 발권 카운터 + 키오스크, 신발장 (번호 열쇠), 팔찌형 RFID 락커키, 입장 게이트, 수영복·튜브 판매, 남/여 탈의실 입구, 대기 벤치, 안전 수칙 판",
    "Indoor waterpark: 파도풀 + 유수풀 + 키즈풀 (tipping bucket 놀이시설), 바디/튜브 슬라이드 + 계단 타워, 구명조끼 대여대, 튜브 보관대, 안전요원 망루 여러 개, 수심 표시, 스낵바 (치킨·라면·맥주), 선베드 + 파라솔, 탈의실 + 샤워실 + 파우더룸, 시계, 스피커",
    "찜질방: 황토 불가마 (돔 + 나무문), 소금방, 얼음방, 편백방, 휴게 홀 (매트, 목침/베개), 대형 TV, 매점 (식혜, 맥반석 계란, 컵라면), 안마의자, 수면실, 찜질복 대여, 락커, PC/만화 코너",
    "Sky observatory: 창마다 파노라마 안내 그래픽 (광안대교, 해운대, 마린시티, 이기대), 동전식 망원경, 포토존 프레임, 카페 키오스크, 기념품, 유리바닥 주의 표지",
    "Rooftop infinity pool: 카바나, 타월 스테이션, 샤워 기둥, 풀바, 파라솔, 수심 표시, 안전요원 의자, 야간 수중 조명"
   ],
   "interactionIdeas": [
    "Leisure front '발권' kiosk (워터파크 / 찜질방 / 인피니티풀 tickets) -> wristband item -> working elevator to 6F/8F/21F/roof via ElevatorButton + ElevatorStop",
    "Waterpark: '튜브 빌리기', '바디슬라이드 타기' (scripted ride camera), periodic wave-pool waves, '구명조끼 착용', snack bar order, lifeguard whistle event",
    "찜질방: '찜질복 갈아입기', '불가마 들어가기' (heat meter), '식혜 · 맥반석 계란 사먹기', '양머리 수건' emote, lie on mats",
    "Observatory: coin binocular zoom camera, landmark name panels, photo frame, glass skywalk step-out",
    "Infinity pool lounger, towel pickup, sunset photo; lobby '체크인' handing off to the Annex key-card flow"
   ]
  },
  {
   "name": "fondx 홍미당 부산광안리점 (Aqua Palace 1F bakery cafe)",
   "path": "Workspace.Gwangalli.landmarks['호텔 아쿠아펠리스 HOTEL AQUA PALACE']['fondx 홍미당 부산광안리점']",
   "bounds": "(-117.6,6.5,107.8)..(-63.3,21.3,162.9)",
   "enterable": true,
   "rooms": [
    {
     "name": "Bakery hall (walk-in via CafeDoor AutoDoor x-93..-89 z116.9)",
     "center": [
      -90.85,
      13.3,
      139.5
     ],
     "size": [
      51.3,
      13.15,
      45
     ],
     "floorY": 6.75,
     "ceilingY": 19.9
    }
   ],
   "props": [
    "152 parts in 2308 sq studs (6.6/100sq): BreadShelf x3 (38.4x0.25x2.6 boards on back wall), DisplayTable x4 (10x2.8x5) + DisplayTop x4 + Bread x45 (1.2x0.8x1.1 boxes) + Tray x12 + Cake x5, labels 홍미당 식빵 / 명란바게트 / 앙버터 x2, Showcase 5x3x16 glass on base + light, Checkout 5x2.95x11.7 + POS box 2x1.4x1.4 + CoffeeMachine box 3.2x2.6x3, LEDScreen 14x3.2 (menu '아메리카노 4,500 · 라떼 5,000|소금빵 3,200 · 앙버터 4,300|OCEAN VIEW SEATS · 2F 광안차이나'), Seat x16 (window bar + 3 tables), PendantBulb x5 (PointLight), Awning wedge 50.4 red, ABoard 'NEW 소금빵', Destination 'fondx 홍미당 (아쿠아펠리스 1F)'"
   ],
   "gameplay": [
    "ShopStaff: POS BasePart outside a storefront -> LOOSE counter site, kind 'bakery' (keys 홍미당/fondx) -> 빵집 직원 NPC with '말 걸기' (only while a player is within 150 studs)",
    "No ShopLife ordering/eating flow",
    "AutoDoor CafeDoor; LEDScreen messages; Destination used by taxi/HUD/Street Events/Mind lines; Annex reads CafeDoor DoorLeaf as an Aqua main door"
   ],
   "emptyOrCrude": [
    "Bread are identical brown boxes; no tray-and-tongs station, per-item price tags, packing counter, pickup counter, self bar; coffee machine a single box",
    "Plain plaster walls, no menu board above the counter except the LED strip, no open bakery kitchen window"
   ],
   "realWorld": [
    "Korean bakery cafe: 입구 트레이 + 집게 스테이션, 아일랜드 진열대 (빵마다 이름·가격 POP), 냉장 케이크 쇼케이스, 계산대 (POS, 카드 단말기, 포장 봉투/박스), 음료 카운터 + 에스프레소 머신 + 그라인더 + 메뉴 보드, 픽업대 + 진동벨, 셀프바 (물, 냅킨, 빨대), 오픈 베이킹 키친 + 오븐, 창가 오션뷰 바 좌석, 시식 코너"
   ],
   "interactionIdeas": [
    "Take tray + tongs, pick bread (소금빵, 앙버터, 명란바게트, 식빵) -> pay at POS -> eat at a seat",
    "Order coffee -> vibrating pager -> pickup",
    "Timed 'fresh bread' event at the oven window"
   ]
  },
  {
   "name": "켄트호텔 광안리 by 켄싱턴 KENT HOTEL (광안해변로 229, 15F, 85 rooms attr) - lobby, 2F cafe, 15F sky lounge, rooftop bar",
   "path": "Workspace.Gwangalli.landmarks['켄트호텔 광안리 by 켄싱턴 KENT HOTEL'] (+ Workspace.Gwangalli.landmarks['현관 디테일 · 켄트호텔 광안리'])",
   "bounds": "(-207.2,6.0,102.0)..(-126.1,206.2,230.8); lobby (-168.7,6.5,115.7)..(-128.1,21.3,158.5)",
   "enterable": true,
   "rooms": [
    {
     "name": "1F 켄트호텔 로비 (walk-in via LobbyDoor AutoDoor x-150..-145 z116.4)",
     "center": [
      -147.75,
      13.3,
      137.05
     ],
     "size": [
      38.5,
      13.15,
      40.9
     ],
     "floorY": 6.75,
     "ceilingY": 19.9
    },
    {
     "name": "2F 카페 & 베이커리 strip (UNREACHABLE)",
     "center": [
      -166.3,
      27.65,
      122.1
     ],
     "size": [
      74.2,
      8.9,
      14.4
     ],
     "floorY": 23.2,
     "ceilingY": 32.1
    },
    {
     "name": "15F 스카이라운지 SKY LOUNGE / reception (UNREACHABLE)",
     "center": [
      -166.65,
      167.5,
      154.1
     ],
     "size": [
      77.9,
      13,
      79.8
     ],
     "floorY": 161,
     "ceilingY": 174
    },
    {
     "name": "루프탑 바 ROOFTOP BAR deck (UNREACHABLE, open sky)",
     "center": [
      -166.5,
      180,
      139.3
     ],
     "size": [
      77.4,
      9,
      50.4
     ],
     "floorY": 175.6
    }
   ],
   "props": [
    "1F lobby (70 parts in 1575 sq studs = 4.5/100sq): ConciergeDesk Model 7 wide (walnut FrontPanel, slate Ledge, WorkDesk, DeskGlow) + 2 Monitors + DeskBell, armchair x2, LobbySofa 3-seat, round TableTop 2.8 + TableFoot, Rug 14x14.5, Plant x1, PendantBulb x2 (PointLight), Downlight x7 (front only), CoveSoffit/CoveLED x4, elevators x2 (4 dark leaves, brass jambs), Sign_KENT HOTEL ('15F RECEPTION · SKY LOUNGE'); dark shell (floor 70,70,72 marble, ceiling 50,50,54)",
    "2F cafe (44 parts): Chair x12 (single boxes 1.6x2.9x0.8), CafeTable x6, PastryCounter 11x3.5x2.5 + Showcase glass, PendantBulb x6",
    "15F sky lounge (197 parts in 6216 sq studs = 3.2/100sq): SkyBar 28 wide + BackBar (BackPanel 26x7, 3 boards, 87 Product bottles), Sign_KENT SKY LOUNGE, LoungeSofa 7-seat 20 wide, Seat x26 incl stools, 7 tables, 14 chair backs/legs, 4 pendants on 5.2 cords, 22 LoungeGlass panes all round, wood LoungeFloor 76x46.8",
    "Rooftop bar (75 parts): Deck 76.8x49.6, RooftopBar 24x3.6x3 + BarLed, Seat x17 + StoolLeg x17, 3 tables, Parasol x3, LightPost x2 + Wire x4 + Bulb x10, CrownBand x3, Sign_KENT HOTEL 38x7 + by KENSINGTON, CrownCore machine box, RoofDoor (fake)",
    "현관 디테일: Sign_★★★ (3성), 벨카트, 우산 비닐 포장기, 발렛 podium, Bollard x7; Canopy 41.5x1x11.4; back: ParkingShutter + Sign_P 켄트호텔 주차장 (fake)",
    "Cores fill 3F-14F; 201 NightWindow panes"
   ],
   "gameplay": [
    "AutoDoor LobbyDoor; Destination '켄트호텔 광안리' (-147.7,7,109.3) used by Career/Taxi, HUD, Nav, Citizens, destination lists",
    "Annex: hotel entry (LobbyDoor + GS25Door DoorLeaf parts) -> generic A.hotel interior",
    "ShopStaff: ConciergeDesk is a Model -> no front staff; the GS25 next door gets one",
    "Elevators decorative; NightWindow tags; InteriorLight: 2 PointLight + 1 SurfaceLight"
   ],
   "emptyOrCrude": [
    "Reception is advertised on 15F but 15F and the rooftop bar are unreachable; 1F only has a 7-wide concierge desk (no check-in), 5 seats, 1 plant",
    "Lighting: 7 downlights at the door + 2 pendants in a dark 38x41 room; back half near elevators empty",
    "2F cafe chairs single boxes; no espresso machine, POS, menu",
    "Sky lounge one bar + one sofa in 6200 sq studs; no booths, DJ, menu; rooftop bar 3 tables"
   ],
   "realWorld": [
    "Kent Hotel 광안리 by Kensington: 24시간 데스크, 뷔페 조식, 커피숍, 레스토랑, 수하물 보관, 바다 전망, 광안대교 루프탑 (mom-mom.net; 15F reception not confirmed)",
    "3-star hotel 1F: 소형 프런트 or 무인 체크인 키오스크, 짐 보관함, 엘리베이터 홀 + 카드키 리더, 층별 안내, 웰컴티/커피 코너, 소파 + 잡지랙, 브로슈어, 비상구 유도등, CCTV, 우산꽂이",
    "Sky lounge: 리셉션 데스크, 조식 뷔페 라인, 바 + 백바 조명, 칵테일·와인 메뉴, 창가 소파석 + 하이테이블, 피아노/DJ, 통창 야경",
    "Rooftop bar: 바 + 냉장고, 스툴, 소파 존, 야외 히터, 줄조명, 파라솔, 광안대교 포토 프레임"
   ],
   "interactionIdeas": [
    "1F '15F 리셉션' elevator button (ElevatorButton/ElevatorStop) -> 15F check-in prompt -> Annex hotel room key card",
    "Sky lounge: breakfast buffet time window (plate minigame), cocktail order, piano/DJ toggle, window seat night view",
    "Rooftop bar '건배' social emote, sunset photo"
   ]
  },
  {
   "name": "GS25 광안해변점 (Kent Hotel 1F convenience store)",
   "path": "Workspace.Gwangalli.landmarks['켄트호텔 광안리 by 켄싱턴 KENT HOTEL']['GS25 광안해변점']",
   "bounds": "(-204.3,6.5,103.9)..(-168.2,21.3,158.1)",
   "enterable": true,
   "rooms": [
    {
     "name": "Store floor (walk-in via GS25Door AutoDoor x-188..-184 z116)",
     "center": [
      -186.25,
      12.7,
      136.65
     ],
     "size": [
      35.7,
      11.95,
      40.9
     ],
     "floorY": 6.75,
     "ceilingY": 18.7
    },
    {
     "name": "Outdoor terrace (2 plastic tables)",
     "center": [
      -176,
      8.5,
      108.5
     ],
     "size": [
      12,
      4,
      8
     ],
     "floorY": 6.6
    }
   ],
   "props": [
    "395 parts in 1460 sq studs (27/100sq, densest landmark room): Fridge x4 (6.6 wide: Body, Kick, 2 SidePanels, FridgeGlow, glass door, 2 mullions, 3 WireShelves, 3 handles, FridgeLamp, 40 Bottles each), Shelf x3 gondolas (18x5.4, 2 boards, 2 PriceRails, 40 Product boxes each), Counter 11 wide + 담배진열장 (CigCabinet 10x5.8 + neon header + SurfaceGui pack grid 5x15), POS x2 (PosBase, PosScreenBack, CustomerDisplay), SteamerCase, Microwave, HotWater, RamenCounter 4x3x3, IceCreamChest + glass, ATM (2.6x6.2 + header + screen + keypad), CeilingLight x9 (SurfaceLight), Sign_24시간 · ATM, PlasticTable x2 outside (4 blue box chairs each)"
   ],
   "gameplay": [
    "ShopStaff: PosBase BaseParts -> LOOSE counter -> cvs '편의점 점원' NPC",
    "Not the 알바 store (JobWorld/JobCvs/Places use GS25 광안리점 in Workspace.Gwangalli.convenience); no ShopLife purchase flow here",
    "Destination 'GS25 광안해변점 (켄트호텔 1F)' (-185.8,7,105.9) used by HUD, Nav, Citizens",
    "AutoDoor GS25Door; Annex reads its DoorLeaf as a Kent main door"
   ],
   "emptyOrCrude": [
    "Products uniform boxes/cylinders without labels; only 3 gondolas; no endcaps, no 카페25 coffee machine, no 도시락 chiller, no 택배 kiosk, no recycling station, no eat-in counter",
    "Cannot buy anything although it looks like a working store"
   ],
   "realWorld": [
    "GS25 beach branch: 워크인 냉장고, 도시락/김밥 오픈 쇼케이스, 과자·라면 곤돌라 + 엔드캡 행사 POP (1+1, 2+1), 계산대 (POS 2, 카드 단말기, 담배장, 복권), 카페25 원두커피 머신, 핫바/찐빵 스티머, 전자레인지 + 온수기, 아이스크림 냉동고, ATM, 반값택배 키오스크, 분리수거함, 창가 취식 바, 파라솔 테라스 + 해변용품 (튜브, 돗자리, 불꽃) 진열"
   ],
   "interactionIdeas": [
    "Open fridge door and pick a drink; pick snack -> pay at POS (shared with the main GS25 flow)",
    "Cup ramen -> hot water -> wait -> eat at terrace",
    "Microwave lunchbox, ATM withdraw, 택배 kiosk, buy 해변용품 for beach activities"
   ]
  },
  {
   "name": "Annex hotel interior (runtime '들어가기' inside of Homers / Aqua Palace / Kent)",
   "path": "built at runtime by ServerScriptService.GwangalliBuildings.Annex -> Builder.plan('hotel') = Builder/Archetypes A.hotel; instances under the GwangalliBuildings root in the y=3000 band",
   "bounds": "slot grid ORIGIN (-9600,3000,-9600), SLOT 560, 16 columns; plan W 50 x D 48 (room centers below are plan-local), floors B1 h12, 1F h13 lobby, 2F-9F, roof",
   "enterable": true,
   "rooms": [
    {
     "name": "1F hotel_lobby (Builder/Shops T.hotel_lobby): frontdesk point, LogoWall, chandelier, sofa3, armchair, coffee table, 2 monstera, aquarium, 2 staff (프런트, 컨시어지) - plan-local coords",
     "center": [
      0,
      6.5,
      10.5
     ],
     "size": [
      50,
      13,
      21
     ],
     "floorY": 0
    },
    {
     "name": "2F 아케이드 홀 / 3F 카지노 라운지 / 8F VIP / 9F 프리미엄 (Royal casino floors) - plan-local",
     "center": [
      0,
      0,
      24
     ],
     "size": [
      50,
      13,
      48
     ]
    },
    {
     "name": "4F-7F guest rooms: hotel_standard 12.5x21 (bed_queen, desk, tv_small, armchair, minibar, toilet, washbasin, shower, wallpad), hotel_deluxe 14.4x21 (bed_king, tv55, 2 armchairs, minibar, floor lamp, bathtub), hotel_suite 25x21 (entry, powder, living, bath, bedroom; sofa3, tv55, coffee table, bathtub + shower) - plan-local",
     "center": [
      0,
      0,
      24
     ],
     "size": [
      50,
      10.5,
      48
     ]
    }
   ],
   "props": [
    "Procedural Kit boxes + GwangalliBuildingsShared/Furniture builders; the lobby LogoWall text is hard-coded 'HOTEL SEASIDE GWANGAN / 호텔 씨사이드 광안' whichever real hotel was entered"
   ],
   "gameplay": [
    "Annex prompts appear within NEAR=70 studs of the building footprint; KEEP 150 s; MAX_LIVE 6; leave via '나가기' at the door used",
    "ShopFlows hotel_lobby frontdesk '체크인 / 체크아웃' -> Menus.HOTEL_ROOMS (standard/deluxe/suite) -> key card (GwB_HotelRoom, GwB_HotelLabel, GwB_Hold 'keycard'); Doors handle hotel card doors; Elevators module runs real elevators; Royal tiers gate 8F/9F",
    "ShopLife.annexLink offers '🛏️ 객실 층으로 (체크인 · 객실)' from map lobbies of type lobby/residence"
   ],
   "emptyOrCrude": [
    "Branding mismatch: Homers, Aqua Palace and Kent all lead to the same 'HOTEL SEASIDE GWANGAN' casino hotel (B1 parking, 2F arcade, 3F casino) instead of each real program (Homers 2F 조식당/3F 웨딩/4-5F 연회장/6F 프런트·루프탑; Aqua 6F 워터파크/8-9F 찜질방/21F 전망대/루프탑 풀; Kent 15F 라운지/루프탑)",
    "Two lobbies per hotel: the static walk-in map lobby (no check-in) and the Annex lobby (check-in)"
   ],
   "realWorld": [
    "Korean hotel room: 카드키 전원 슬롯, 현관 슬리퍼, 옷장 (가운, 다리미, 금고), 미니바 냉장고 + 커피포트 + 캡슐커피 + 생수 2병, 책상 + 스탠드 + USB 콘센트, 벽걸이 TV, 화이트 린넨 침대 + 러너, 협탁 조명 스위치 패널, 암막 + 쉬어 커튼, 오션뷰 창가 소파, 욕실 (레인샤워, 비데, 어메니티, 수건 3종, 드라이어), 객실 번호판 + DND 램프, 문 뒤 화재 대피도"
   ],
   "interactionIdeas": [
    "Per-hotel identity: pass the real name/nameEn/floor program into A.hotel (or AnnexKind/AnnexFloors attrs on the landmark) so logo wall and floors match",
    "In-room: key-card slot lights, curtains, minibar item, kettle + capsule coffee, safe code, DND lamp, rain shower"
   ]
  },
  {
   "name": "Workspace.Gwangalli.homes.Entrances (5 HomeEntrance portals) + the street lobbies they sit at",
   "path": "Workspace.Gwangalli.homes.Entrances.HomeEntrance_{goshiwon,oneroom,officetel,apartment,penthouse}",
   "bounds": "(-1501.2,6.5,33.1)..(416.6,16.1,903.1)",
   "enterable": false,
   "rooms": [
    {
     "name": "HomeEntrance_goshiwon portal '황령하우스 · 광안 고시텔 3F' beside 광안 메디컬 의원 (no 고시원 building; trash bags + scooter next to it)",
     "center": [
      -489.1,
      10.1,
      255.4
     ],
     "size": [
      4,
      7,
      1.4
     ],
     "floorY": 6.6
    },
    {
     "name": "HomeEntrance_oneroom at 미성맨션 공동현관 (uptown RowC Block_C6 villa) - lobby is a SOLID brick block 'Lobby' 10.96x10.5x11.36 at (209.2,11.8,608.5) with a dark-glass LobbyDoor panel, under pilotis parking",
     "center": [
      209.6,
      10.1,
      601.5
     ],
     "size": [
      4,
      7,
      1.4
     ],
     "floorY": 6.6
    },
    {
     "name": "HomeEntrance_officetel at 테라스타오션 TERRASTAR OCEAN lobby Model: ShopFloor 12.2x14.4 at (-1496,6.6,43.8), ShopBackWall, 2 partitions, 2 elevators, 4 downlights, EMPTY 'Interior' model",
     "center": [
      -1495.2,
      10.1,
      34.8
     ],
     "size": [
      4.8,
      7,
      1.4
     ],
     "floorY": 6.6
    },
    {
     "name": "HomeEntrance_apartment at 광안자이 정문 (GatePylon 4.4x22x4.4, BarrierPost, NameStone, intercom pillar); towers ~96 studs away",
     "center": [
      413.6,
      10.1,
      902.3
     ],
     "size": [
      5,
      7,
      1.4
     ],
     "floorY": 6.6
    },
    {
     "name": "HomeEntrance_penthouse in front of the Aqua Palace LobbyDoor",
     "center": [
      -41.3,
      10.05,
      114.7
     ],
     "size": [
      6,
      7,
      1.4
     ],
     "floorY": 6.6
    }
   ],
   "props": [
    "Each portal: HomeEntrance part (invisible, CanCollide/CanQuery/CanTouch false, attrs Destination, DisplayName, KoreanName, ListingId goshiwon|oneroom|officetel|xi_apt|aqua_ph, Tier, TierIndex 1-5, tag HomeEntrance), EntranceCue (3 PortalNeon + ThresholdNeon in tier colour 150,150,160 / 90,170,230 / 40,196,210 / 255,196,64 / 176,110,255, tag HomeEntranceCue), Kiosk (goshiwon A-frame '1인실 · 보증금 0원 월 18만원부터 ↑ 3층 계단'; oneroom KeypadPillar + LED + '미성맨션 공동현관 원룸 · 투룸 · 풀옵션'; officetel stand 'TERRASTAR OCEAN 오피스텔 입주민 출입구'; apartment IntercomPillar + screen + keypad '광안자이 입주민 출입 세대 호출 · 방문 차량 등록'; penthouse brass stand 'PENTHOUSE RESIDENCE 입주민 전용 엘리베이터 · 컨시어지')",
    "Destination parts (Category 'home') for goshiwon (-489,7.2,253.1) and oneroom (209.6,7.1,599.2)"
   ],
   "gameplay": [
    "GwangalliHome LocalScript builds local ProximityPrompts on HomeEntrance parts: 집으로 들어가기 (owner), 초인종 (owner online), 입주 문의 (월세/매매/대출) within G.HOME_ENTRANCE_REACH 18",
    "Housing.luau: missing tiers get a fallback entrance at the listing Destination (folder GwangalliHomeEntrances); leaving a home returns to the HomeEntrance; Details.luau lists HomeEntrance among door/destination tags",
    "Nothing here is an interior: entering teleports to the per-player unit",
    "TERRASTAR OCEAN lobby is a street-shop style Model (Interior + ShopFloor) -> ShopLife residence lobby -> Annex lobbyLink '🛗 엘리베이터 · 위층 세대 둘러보기'; the officetel portal sits 1.5 studs outside its AutoDoor"
   ],
   "emptyOrCrude": [
    "고시원 has no building: a free-standing neon door frame next to a clinic and trash bags; sign promises '3층 계단' with no stair",
    "미성맨션 lobby is a solid brick cube; no mailboxes, no 공동현관 door that opens",
    "TERRASTAR OCEAN lobby Interior is empty: no 무인택배함, 우편함, 보안 데스크, seating, directory; elevators decorative",
    "광안자이 only a gate: no 동 출입구 / 로비 / 경비실 at the portal"
   ],
   "realWorld": [
    "고시원 entrance: 상가 옆 좁은 계단 입구, '○○고시텔' 세로 간판, 층별 안내, 형광등 계단 + 전단지, 3층 철문 + 번호키, 신발장, 총무실 창구, 공용주방·세탁실 안내",
    "빌라/원룸 공동현관: 필로티 주차장, 유리문 + 번호키 도어폰, 호수별 우편함, 바닥 택배, 계단실, 분리수거장, CCTV 안내",
    "오피스텔 1F 로비: 자동문 + 카드키 리더, 보안 데스크, 무인 택배함, 우편함, 소파, 엘리베이터 2-3대, 입주민 공지 게시판, 관리사무소",
    "아파트 단지: 정문 차단기 + 경비실, 동 표지, 동 출입구 캐노피, 공동현관 월패드 호출, 우편함, 엘리베이터 홀, 커뮤니티 안내판"
   ],
   "interactionIdeas": [
    "Keypad/intercom: enter door code or call a unit; open the 공동현관 door visually before the teleport",
    "Building mailbox wall, parcel locker '택배 찾기' (delivery job tie-in)",
    "Officetel security desk greeting, elevator ride effect (HomesFloors.rideEffect) before entering the unit"
   ]
  },
  {
   "name": "HomeUnit_goshiwon - 광안 고시원 1인실 (tier 1, 창문형 + 개인 샤워실, plan 7.8 m2)",
   "path": "ServerStorage.GwangalliHomes.HomeUnit_goshiwon (template; cloned per owner into Workspace.GwangalliHomeInstances.Home_<UserId> / Tour_<UserId>)",
   "bounds": "template interior (-4004.1,999.0,9993.2)..(-3995.9,1008.3,10006.5), UnitRoot (-4000,1000,10000); runtime clone pivoted to (0, 4000+row*1400, (col-3.5)*3200), 8 columns",
   "enterable": true,
   "rooms": [
    {
     "name": "main 방 (bed + built-in desk wall)",
     "center": [
      -4000,
      1003.9,
      9998.25
     ],
     "size": [
      7.25,
      7.7,
      9.3
     ],
     "floorY": 1000.05,
     "ceilingY": 1007.75
    },
    {
     "name": "현관 (shoe cabinet, mirror door, mail pocket)",
     "center": [
      -4001.6,
      1003.9,
      10004.45
     ],
     "size": [
      4,
      7.7,
      3.1
     ],
     "floorY": 1000.05,
     "ceilingY": 1007.75
    },
    {
     "name": "bath 샤워실 wet cell",
     "center": [
      -3997.9,
      1003.9,
      10004.45
     ],
     "size": [
      3,
      7.6,
      3.1
     ],
     "floorY": 1000.13,
     "ceilingY": 1007.75
    }
   ],
   "props": [
    "228 parts excluding backdrop (Plastic 115, Metal 35, Fabric 22, Plaster 14, Glass 9); lights: desk LampHead PointLight, BathLight PointLight, LEDPanel SurfaceLight",
    "Shell: Floor 7.2x12 wood (Room main, Surface floor), Ceiling, Wall x9 + Partition x4 (Room/Surface), FloorBath tile, TileWall x6; Fixtures: door mirror, DoorLock, notice '외출 시 전등·전열기 OFF / 공용주방 07:00~23:00 · 총무실 101호', MailPocket + Letter, SmokeDetector, Sprinkler, Switch, 2 Outlets, PowerStrip, VentFan, ceiling texture lines x6, Baseboard/Crown x3, Window 2.3 wide (8 sash, 2 glass, sill) + roll Blind, Door with levers, LEDPanel 2.2, WetCellDoor (2 frosted leaves + track)",
    "Slots: bed_goshiwon_single 3x6.4 (plinth, frame, mattress, duvet, fold, pillow mesh, throw, headboard), desk_goshiwon_builtin 7.2 wide (drawer unit, monitor arm/screen, keyboard, mouse, arm lamp), chair_study, shelf_wall (books, 3 cup noodles, cactus; MountY 5.34), corkboard_memos, desk_fan",
    "Props: ShoeCabinet, slippers + 4 shoes, MiniFridge 1.6x1.7x1.4, Kitchenette (microwave, kettle, cup), HangerRail + 4 clothes, PlasticDrawers, DryingRack + 4 laundry, Ramen boxes x2 + 3 cup noodles, WallAC, WetCell (toilet with mesh bowl, basin 0.54x0.3x0.8, shower riser/head, mixer, drain, towel, mirror), InteriorPanel tablet '🛠 인테리어'",
    "Interact: interior, bed (lie), desk (sit), fridge (crouch), wardrobe, window '창밖 보기', mailbox, shower; ExitDoor; Spawn",
    "Backdrop AlleyView: alley wall 26x40, barred neighbour window (NightNeon), outdoor AC, gas/drain pipes, wires"
   ],
   "gameplay": [
    "Housing.luau (server): clones template, PivotTo grid slot, anchors, enables Seats, proxifies HomeInteract parts inside default furniture, ProximityPrompts on HomeInteract parts with Kind in G.HOME_KINDS (bed sofa tv fridge table shower wardrobe desk window mailbox door) + 'interior'; UseAt Attachment Pose; HomeSeat; sleep via Life.sleep; fridge/desk/mailbox/wardrobe panels via HomeState",
    "Furniture: FurnitureSlot Models (SlotId, Category, DefaultItem, Footprint, Rotate, MountY, SlotBase, child 'Furniture' Default=true + ItemId) - server destroys/rebuilds bought variants (G.furnitureSpec, 40+ HS variants), quarter turns saved per listing",
    "Themes: Shell parts with Room + Surface ('wall'|'floor'|'light') and Lights with Room are recoloured (Color + Material, OrigColor/OrigMaterial attrs); HomeState 'themes'",
    "Model attrs HomeOwnerId, HomeTier, HomeListing, TvOn, Staged; ModelStreamingMode PersistentPerPlayer; HS.FURNITURE_LIGHTS 3; GwangalliHome client: HUD, 꾸미기, Interior decor/tour mode, window photo camera, TV SurfaceGui on Screen/TVScreen parts",
    "Must keep: UnitRoot (PrimaryPart), Spawn, ExitDoor, HomeInteract + Kind/Label/SlotId/UseAt, FurnitureSlot contract, Room/Surface attrs, Backdrop/WindowView; GwangalliIndoorLight dims PointLights under the ceiling"
   ],
   "emptyOrCrude": [
    "Reasonably furnished but all boxes/cylinders (bed = 8 boxes, chair base = 5 bars), flat plaster walls without wallpaper pattern, single wood floor slab",
    "Missing goshiwon signatures: room number plate, TV/monitor content, power-strip clutter, 공용주방/세탁실 (the notice mentions them), fire extinguisher, 소음 주의 notice",
    "Window has only a roll blind; no clutter (bag, laptop, toiletries, snacks)"
   ],
   "realWorld": [
    "고시원 1인실 (창문형, 욕실형): 싱글 침대 ~90cm + 하부 수납, 붙박이 책상 + 책장 + 의자, 미니 냉장고, 개별 벽걸이 에어컨, 소형 TV/모니터, 행거/슬림 옷장, 샤워부스 + 변기 + 미니 세면대, 환풍기, 스프링클러 + 화재감지기 + 소화기, 방 번호 + 번호키, 방범/블라인드 창, 멀티탭, 와이파이 안내, 입실 규칙",
    "Shared: 공용주방 (밥·김치·라면 무료, 밥솥, 인덕션, 전자레인지, 정수기, 이름표 냉장고), 세탁실, 총무실 창구, 좁은 복도 + 방 번호판, 신발장"
   ],
   "interactionIdeas": [
    "Desk monitor 'turn on' (공부/게임/유튜브 screen), desk lamp, desk fan toggle",
    "Ramen -> kettle boil -> eat at desk; mini-fridge door opens with drinks",
    "Wall AC remote, blind up/down, light switch (Room main), drying rack laundry, mirror outfit check",
    "Shared kitchen / laundry corridor scene (공용주방 무료 밥·김치)"
   ]
  },
  {
   "name": "HomeUnit_oneroom - 광안동 풀옵션 원룸 (tier 2, 미성맨션)",
   "path": "ServerStorage.GwangalliHomes.HomeUnit_oneroom (runtime clone Workspace.GwangalliHomeInstances.Home_<UserId>)",
   "bounds": "template interior (-2010.8,999.0,9990.8)..(-1989.2,1008.4,10008.8), UnitRoot (-2000,1000,10000); backdrop alley (-2026,983.5,9982.2)..(-1974,1018,9991.2)",
   "enterable": true,
   "rooms": [
    {
     "name": "main 방 (bed, sofa, table, barred window + curtain)",
     "center": [
      -2002.5,
      1004,
      9998.75
     ],
     "size": [
      15,
      7.9,
      13.5
     ],
     "floorY": 1000.05,
     "ceilingY": 1007.95
    },
    {
     "name": "TV / wardrobe nook (east)",
     "center": [
      -1992.5,
      1004,
      9996.6
     ],
     "size": [
      5,
      7.9,
      9.2
     ],
     "floorY": 1000.05,
     "ceilingY": 1007.95
    },
    {
     "name": "kitchen strip (Room kitchen)",
     "center": [
      -2004.6,
      1004,
      10006.8
     ],
     "size": [
      10.8,
      7.9,
      2.4
     ],
     "floorY": 1000.05,
     "ceilingY": 1007.95
    },
    {
     "name": "현관 (step-down tile)",
     "center": [
      -1997.1,
      1003.8,
      10006.8
     ],
     "size": [
      4.2,
      8.4,
      2.4
     ],
     "floorY": 999.55,
     "ceilingY": 1007.95
    },
    {
     "name": "bath",
     "center": [
      -1992.5,
      1004,
      10004.6
     ],
     "size": [
      5,
      7.9,
      6.8
     ],
     "floorY": 1000.13,
     "ceilingY": 1007.95
    }
   ],
   "props": [
    "312 parts excluding backdrop; lights: LampShade, BathLight, SensorLight PointLights + LEDPanel SurfaceLight",
    "Fixtures: DoorLock + LED + handle, Peephole, DoorCloser, Wallpad + screen, Thermostat + LCD, Switch, 2 Outlets, SmokeDetector, VentFan, EntryMirror, SensorLight, Window 9.8 wide (8 sash, 4 glass, 9 security Bars + 3 rails), entrance + bath doors, 2 LED panels",
    "Slots: curtain_linen_sheer, bed_supersingle 3.6x6.6, table_cafe2 (2 chairs), tv_43_cabinet (TV, screen, cabinet, soundbar), rug_round_beige, plant_monstera, lamp_floor_brass, sofa_loveseat_beige, purifier_white, deco_vase_stand, art_abstract_warm, shelf_open_white",
    "Props: ShoeCabinet + 4 shoes, Kitchen (base cabinet, countertop, sink, 2-ring induction, hood, 2 uppers + LEDs, rice cooker, kettle, front-load Washer under counter), Fridge + microwave on top, Nightstand + lamp, Wardrobe 4.6x7.9x2, WallAC, Bathroom (toilet, vanity + LED mirror, 3 shower glass panels, rain head, mat, towel), InteriorPanel",
    "Interact: interior, bed, wardrobe, fridge, table '식사하기', tv, sofa, shower, window, mailbox '택배·우편 확인 (인터폰)'; ExitDoor; Spawn; backdrop alley + utility pole"
   ],
   "gameplay": [
    "Same Housing/HS/GwangalliHome contract as the goshiwon (HomeInteract prompts, FurnitureSlot swaps, Room/Surface themes, TVScreen gui, UseAt poses)",
    "Listing oneroom -> HomeEntrance_oneroom at 미성맨션 (209.6,10.1,601.5)"
   ],
   "emptyOrCrude": [
    "Sterile: no clutter (dishes, food, laundry, bag, laptop), no wallpaper texture, single-slab floors, box beds/sofas",
    "Kitchen without utensils, dish rack, cutting board; no 분리수거 bins, no 빨래건조대, no bathroom toiletries or toilet-paper holder"
   ],
   "realWorld": [
    "풀옵션 원룸: 싱크대 하부 드럼세탁기, 소형 2도어 냉장고, 2구 인덕션 + 후드, 전자레인지, 벽걸이 에어컨, 붙박이장, 신발장 + 전신거울, 비디오폰, 디지털 도어락, 보일러 온도조절기, 방범창, 블라인드/커튼, LED 방등 + 현관 센서등, 욕실 (샤워부스/커튼, 수건장, 환풍기, 휴지걸이), 슈퍼싱글 침대, 행거, 접이식 테이블, 빨래건조대, 분리수거 봉투, 택배 박스"
   ],
   "interactionIdeas": [
    "Washer 'start laundry' (drum spin) -> drying rack",
    "Induction cook 라면/계란 (pot, steam), sink wash dishes, rice cooker steam",
    "Intercom answer door / 배달음식 받기, light switches per Room, curtain open/close, AC remote, purifier mode LED"
   ]
  },
  {
   "name": "HomeUnit_officetel - 테라스타오션 오피스텔 (tier 3, 복층 loft, sea view)",
   "path": "ServerStorage.GwangalliHomes.HomeUnit_officetel (runtime clone Workspace.GwangalliHomeInstances.Home_<UserId>)",
   "bounds": "template interior (-15.8,999.0,9990.7)..(15.8,1016.5,10009.3), UnitRoot (0,1000,10000); backdrop sea/광안대교/skyline (-588,910,9816)..(798,1141,10020)",
   "enterable": true,
   "rooms": [
    {
     "name": "living (double height, 30-wide full-height glazing to the sea)",
     "center": [
      0,
      1008,
      9996.5
     ],
     "size": [
      30,
      15.9,
      10
     ],
     "floorY": 1000.05,
     "ceilingY": 1015.95
    },
    {
     "name": "kitchen under the loft (bar table)",
     "center": [
      -5.9,
      1004.15,
      10005
     ],
     "size": [
      18.2,
      8.2,
      7
     ],
     "floorY": 1000.05,
     "ceilingY": 1008.25
    },
    {
     "name": "bath",
     "center": [
      6.2,
      1004.1,
      10005
     ],
     "size": [
      5.6,
      8.1,
      7
     ],
     "floorY": 1000.13,
     "ceilingY": 1008.25
    },
    {
     "name": "현관 + hall",
     "center": [
      12,
      1003.9,
      10005
     ],
     "size": [
      6,
      8.4,
      7
     ],
     "floorY": 999.55,
     "ceilingY": 1008.25
    },
    {
     "name": "loft 복층 침실 (stair x-15..-12.3, glass railing)",
     "center": [
      0,
      1012.15,
      10005
     ],
     "size": [
      30,
      7.6,
      7
     ],
     "floorY": 1008.35,
     "ceilingY": 1015.95
    }
   ],
   "props": [
    "383 parts excluding backdrop; lights: LampShade + BathLight PointLights, PendantLED + KitchenLinear SurfaceLights",
    "Fixtures: Glazing (4 glass, 4 frames, 3 mullions, transom, sill), Stair (9 steps + 9 treads + stringer), GlassRailing + StairRailing, 3 kitchen downlights + KitchenLinear, LinearPendants, ArtWall + LED, Wallpad, Thermostat, DoorLock, Peephole, SensorLight",
    "Slots: curtain_double_height 30x15.6, sofa_fabric3_grey, coffee_oak, rug_grey_wool, tv_55_wall, desk_oak_window (monitor + laptop), chair_office_mesh, lamp_floor_brass, plant_olive_tree, plant_sansevieria, art_canvas_sea, bartable_oak2 (2 stools), bed_queen_platform (loft), standac_white, purifier_white, deco_vase_stand",
    "Props: ShoeCabinet with niche LED + mirror + diffuser, Kitchen (2 base cabinets, 3-ring induction, hood, sink, rice cooker, kettle, washer), Fridge, Nightstand, LoftWardrobe 6 wide, LoftDetail (rug + plant), Bathroom (26 parts), InteriorPanel",
    "Interact: interior, sofa, tv, desk, table (bartable), fridge, bed (loft), wardrobe (loft), shower, window '바다 보기', mailbox"
   ],
   "gameplay": [
    "Same Housing/HS contract; window kind = photo moment (cooldown 90 s) toward the sea backdrop (Coast, 광안대교 49 parts, Skyline 38, Neighbours)",
    "Listing officetel -> HomeEntrance_officetel at TERRASTAR OCEAN (-1495.2,10.1,34.8)"
   ],
   "emptyOrCrude": [
    "Big 30x10x16 living volume with sofa, TV, desk; bare walls except the art wall; no clutter; stand AC only (no ceiling cassette)",
    "Loft stair plain stacked boxes (no 수납계단 drawers); kitchen lacks utensils, dish rack, microwave; no indoor drying rack"
   ],
   "realWorld": [
    "복층 오피스텔: 천장형 시스템에어컨, 빌트인 냉장고 + 드럼세탁기 + 인덕션 + 후드 + 전자레인지, 수납 계단, 유리난간, 낮은 복층 침대, 통창 + 전동 블라인드/암막, 월패드 (방문자, 관리비, 택배 알림, 엘리베이터 호출), 붙박이 신발장 + 전신거울, 실내 빨래건조대, 욕실 (샤워부스, 비데, 수건장), 공기청정기, 로봇청소기, 홈카페 머신"
   ],
   "interactionIdeas": [
    "Wallpad: 엘리베이터 호출, 택배 확인, 관리비 (bills tie-in), visitor camera",
    "Motorized blinds/curtains for the sea view; ceiling AC on/off with vanes",
    "Robot vacuum loop, capsule coffee machine, loft stair drawers"
   ]
  },
  {
   "name": "HomeUnit_apartment - 광안자이 아파트 84㎡ (tier 4, 3 rooms 2 baths, listing xi_apt)",
   "path": "ServerStorage.GwangalliHomes.HomeUnit_apartment (runtime clone Workspace.GwangalliHomeInstances.Home_<UserId>)",
   "bounds": "template interior (1979.2,998.6,9980.2)..(2020.8,1008.7,10015.8), UnitRoot (2000,1000,10000); backdrop city + 광안대교 (1440,775,9812)..(2560,1097,10003)",
   "enterable": true,
   "rooms": [
    {
     "name": "living 거실 (tray ceiling + cove, chaise sofa, 65-inch TV, art wall)",
     "center": [
      2001,
      1004.2,
      9992
     ],
     "size": [
      16,
      8.25,
      14
     ],
     "floorY": 1000.05,
     "ceilingY": 1008.3
    },
    {
     "name": "kitchen + dining (island + 3 stools, fridge column, 4-seat dining)",
     "center": [
      2003,
      1003.9,
      10007
     ],
     "size": [
      20,
      7.7,
      16
     ],
     "floorY": 1000.05,
     "ceilingY": 1007.75
    },
    {
     "name": "master bedroom 안방",
     "center": [
      1986.5,
      1003.9,
      9994
     ],
     "size": [
      13,
      7.7,
      18
     ],
     "floorY": 1000.05,
     "ceilingY": 1007.75
    },
    {
     "name": "dress room 드레스룸",
     "center": [
      1990,
      1003.9,
      10009
     ],
     "size": [
      6,
      7.7,
      12
     ],
     "floorY": 1000.05,
     "ceilingY": 1007.75
    },
    {
     "name": "master bath 안방 욕실",
     "center": [
      1983.5,
      1003.9,
      10009
     ],
     "size": [
      7,
      7.7,
      12
     ],
     "floorY": 1000.13,
     "ceilingY": 1007.75
    },
    {
     "name": "study 서재 · 작은방 (desk, daybed, tall bookshelf)",
     "center": [
      2014.5,
      1003.9,
      9991
     ],
     "size": [
      11,
      7.7,
      12
     ],
     "floorY": 1000.05,
     "ceilingY": 1007.75
    },
    {
     "name": "common bath 공용 욕실 (bathtub)",
     "center": [
      2016.5,
      1003.9,
      10001
     ],
     "size": [
      7,
      7.7,
      8
     ],
     "floorY": 1000.13,
     "ceilingY": 1007.75
    },
    {
     "name": "현관 + 중문 (sliding glass Jungmun)",
     "center": [
      2016.5,
      1003.7,
      10010
     ],
     "size": [
      7,
      8.2,
      10
     ],
     "floorY": 999.55,
     "ceilingY": 1007.75
    },
    {
     "name": "veranda 베란다 (washer + dryer, drying rack)",
     "center": [
      1986.5,
      1003.6,
      9983
     ],
     "size": [
      13,
      7.85,
      4
     ],
     "floorY": 999.7,
     "ceilingY": 1007.55
    }
   ],
   "props": [
    "759 parts excluding backdrop; lights: 2 LEDPanel SurfaceLights, PendantBulb PointLight, TrayLight SurfaceLight (4 real lights for 9 rooms)",
    "Fixtures: 5 smoke detectors, 4 outlets, 4 switches, wallpad, thermostat, doorlock, peephole, door closer, entry mirror, Cove (4 CoveLED + TrayLight), living window (16 sash, 8 glass), study window, VerandaDoor, VerandaWindow, StudyBlind, 6 doors, Jungmun (4 stiles, 4 bars, 2 glass, track), 3 kitchen pendants, 8 kitchen + 4 living downlights, ArtWall + trims",
    "Slots (18): curtain_linen_sheer, curtain_blackout_grey, sofa_fabric_chaise, coffee_marble_round, rug_wool_beige, tv_65_wall, lamp_floor_arc, plant_ficus_tree, plant_monstera, art_pair_warm, standac_white, purifier_beige, deco_vase_stand, dining_oak4, bed_queen_upholstered, desk_study_oak, chair_office_mesh, bookshelf_tall_white",
    "Props: ShoeCabinetWall (niche LED, mirror, diffuser), shoes + slippers, Kitchen (36: cabinets, 3-ring induction, hood, sink, microwave, rice cooker, kettle), FridgeColumn (양문형 2 bodies + 2 doors + display), Island (3 stools), MasterBedside (2 nightstands + lamps), Dresser + mirror + stool + perfume, MasterTV, MasterAC wall unit, Veranda (washer + dryer, basket, rack + 6 laundry, 2 plants), DressRoom (2 rails, 17 clothes, 2 shelves, mirror), MasterBath (29), CommonBath (tub + water + glass, vanity, toilet), Daybed, StudyAC",
    "Interact (13): interior, sofa, tv, window '광안대교 보기', window '베란다 창밖 보기', fridge, table (dining), bed, wardrobe (드레스룸), shower (master), shower '반신욕 하기', desk, mailbox '월패드 (택배·관리비·방문자)'"
   ],
   "gameplay": [
    "Same Housing/HS contract; HS.ROOM_FACTOR scales theme prices (bath/dress/veranda 0.6, study 0.8); TIER_MULT 2.8; listing xi_apt (buy 1,200만, Journey) -> HomeEntrance_apartment at 광안자이 정문",
    "Max guests 6 (집들이, doorbell, invite, kick/ban)"
   ],
   "emptyOrCrude": [
    "Good room set but only 4 real lights for 9 rooms; box furniture; plain walls; single-slab floors",
    "Missing Korean apartment staples: 김치냉장고, 식기세척기, 정수기, 에어프라이어, 팬트리, 다용도실/보일러, 분리수거함, 로봇청소기, 거실 시스템에어컨, 가족사진/달력/시계, 아이방",
    "No small items in kitchen/baths (dishes, cups, towel sets, toiletries, bidet seat)"
   ],
   "realWorld": [
    "84㎡ 3룸 2욕실: 현관 (중문, 신발장 + 벤치, 센서등, 도어락, 전신거울), 거실 (아트월, 소파, 거실장 + 65형 TV, 스탠드 + 시스템 에어컨, 공기청정기, 러그, 이중 커튼, 확장 거실 창 광안대교 뷰), 주방 (ㄷ자 싱크대 + 아일랜드, 양문형 냉장고 + 김치냉장고, 3구 인덕션, 후드, 식기세척기, 밥솥, 정수기, 전자레인지, 에어프라이어, 팬트리, 4인 식탁), 다용도실 (세탁기 + 건조기 직렬, 보일러, 건조대, 분리수거함), 안방 (침대, 협탁, 화장대, 드레스룸, 욕실: 샤워부스, 이중 세면대, 비데), 작은방 2 (서재, 아이방), 공용 욕실 (욕조, 비데, 수납장), 월패드, 각방 온도조절기, 로봇청소기, 화분, 가족사진, 벽시계, 달력"
   ],
   "interactionIdeas": [
    "Kimchi fridge 'take 김치', dishwasher load/start, water purifier pour, air fryer cook",
    "Veranda washer -> dryer -> fold laundry in the dress room; thermostat 온도 setting",
    "Wallpad call elevator / visitor / 관리비, robot vacuum, bidet seat, bathtub fill (water rises) for 반신욕, kids' room toy box"
   ]
  },
  {
   "name": "HomeUnit_penthouse - 아쿠아펠리스 오션뷰 펜트하우스 (tier 5, duplex, listing aqua_ph)",
   "path": "ServerStorage.GwangalliHomes.HomeUnit_penthouse (runtime clone Workspace.GwangalliHomeInstances.Home_<UserId>)",
   "bounds": "template interior (3969.2,999.0,9974.0)..(4030.8,1018.9,10014.8), UnitRoot (4000,1000,10000); backdrop coast/광안대교/skyline/neighbours incl. 호메르스호텔 + 켄트호텔 blocks (3380,810,9817)..(4620,1062,10013)",
   "enterable": true,
   "rooms": [
    {
     "name": "living (double height ~18, chandelier, fireplace feature wall, 85-inch frame TV, grand piano)",
     "center": [
      4000,
      1009,
      9998.95
     ],
     "size": [
      24,
      17.9,
      21.1
     ],
     "floorY": 1000.05,
     "ceilingY": 1017.95
    },
    {
     "name": "dining + home bar (6-seat marble table, 70-bottle bar)",
     "center": [
      3979,
      1004.5,
      9995
     ],
     "size": [
      18,
      8.9,
      14
     ],
     "floorY": 1000.05,
     "ceilingY": 1008.95
    },
    {
     "name": "kitchen (island, tall fridge column)",
     "center": [
      3979,
      1004.5,
      10008
     ],
     "size": [
      18,
      8.9,
      12
     ],
     "floorY": 1000.05,
     "ceilingY": 1008.95
    },
    {
     "name": "foyer / entry (console, sculpture, mirror, coat wardrobe)",
     "center": [
      4000,
      1004.5,
      10011.8
     ],
     "size": [
      24,
      8.9,
      4.5
     ],
     "floorY": 1000.05,
     "ceilingY": 1008.95
    },
    {
     "name": "study 서재 (executive desk, walnut wall bookshelf, lounge chair)",
     "center": [
      4021,
      1004.4,
      9997
     ],
     "size": [
      18,
      8.7,
      18
     ],
     "floorY": 1000.05,
     "ceilingY": 1008.75
    },
    {
     "name": "wine room (glass wall, 62 bottles) + powder room",
     "center": [
      4021,
      1004.4,
      10010
     ],
     "size": [
      18,
      8.7,
      8
     ],
     "floorY": 1000.05,
     "ceilingY": 1008.75
    },
    {
     "name": "mezzanine master bedroom (king bed, ocean-view tub, dress area)",
     "center": [
      4021,
      1013.65,
      9996.5
     ],
     "size": [
      18,
      8.6,
      17
     ],
     "floorY": 1009.35,
     "ceilingY": 1017.95
    },
    {
     "name": "master bath (upper level)",
     "center": [
      4025.6,
      1013.8,
      10009.6
     ],
     "size": [
      8.7,
      8.4,
      8.8
     ],
     "floorY": 1009.6,
     "ceilingY": 1017.95
    },
    {
     "name": "terrace (jacuzzi, fire table, loungers, canopy)",
     "center": [
      4000,
      1009,
      9981.1
     ],
     "size": [
      60,
      18.3,
      13.8
     ],
     "floorY": 999.8
    }
   ],
   "props": [
    "889 parts excluding backdrop (Plastic 209, Glass 171, Metal 152, Fabric 82, Wood 72, Neon 65); lights: LampShade PointLight, terrace CanopyLight SpotLight, LinearPendantLED SurfaceLight, ChandelierCore PointLight",
    "Fixtures: ceiling-cassette AC + grille, wallpad, thermostat, doorlock + pull handle, 5 smoke detectors; glazing (dining, living L/R, study, 17-part upper) + sliding glass leaves to the terrace; TerraceRailing + barrier; 4 doors; Fireplace (glass, neon flame, hearth 11.2), Chandelier (8 rings + 8 RingLEDs + cables + core), Stair (10 treads) + StairRailing + MezzRailing, ~20 downlights, linear DiningPendant",
    "Slots (21): tv_85_frame, sofa_boucle_modular 11 wide, coffee_travertine_pair, rug_silk_grey 14x11, chair_lounge_walnut x2, art_large_abstract 9x6, art_bridge_photo, plant_olive_large, plant_ficus, lamp_floor_arc_brass, dining_marble6, desk_walnut_executive, chair_office_leather, bookshelf_walnut_wall 9x8, bed_king_upholstered, purifier_beige, curtains x3, deco_vase_stand x2",
    "Props: Terrace (63: hot tub body/water/glow/step, fire table + flame, outdoor sofa, 3 loungers + rolled towels, 4 planters with trees, parasol, 4 wall washers), Foyer (console, sculpture, vase, mirror, wardrobe), GrandPiano (case, mesh tail, lid, key bed, keys, 3 legs, bench), Bar (body/top, back bar, 5 shelves + 70 bottles + 7 flutes, 3 stools, LEDs), Kitchen (42), Study (lounge chair, rug), WineRoom (62 bottles, 6 shelves), Powder (toilet, vanity, LED mirror), MasterSuite (nightstands, bed bench, lounge chair, closet drawers, rail + 6 clothes, ocean-view tub), MasterBath (29)",
    "Interact (15): sofa, tv, window '광안대교 야경 보기', window '침실 창밖 보기', table, fridge, desk, bed, wardrobe, shower '레인 샤워', shower '오션뷰 욕조 반신욕', sofa '선베드에 눕기' (terrace), shower '자쿠지' (terrace), mailbox '월패드 (컨시어지·택배)', interior"
   ],
   "gameplay": [
    "Same Housing/HS contract; max guests 10; TIER_MULT 4; Grades.HOST_LISTINGS + ProgressShared level-15 'penthouse'; Journey buyable home (4,800만); HomeEntrance_penthouse at the Aqua Palace lobby",
    "Backdrop Neighbours includes '호메르스호텔' and '켄트호텔' blocks (painted set, not the map)"
   ],
   "emptyOrCrude": [
    "Grand piano, home bar, wine room and fireplace are props with no interaction",
    "Only 4 real lights for a double-height duplex at night; box geometry; no art lighting; no private elevator hall although the listing sign promises '입주민 전용 엘리베이터 · 컨시어지'",
    "No guest bedroom, no laundry, no smart-home panel content; terrace without BBQ grill"
   ],
   "realWorld": [
    "Busan beachfront penthouse: 전용 엘리베이터 홀 + 대리석 현관 + 콘솔/거울, 복층 거실 (층고 5-6 m, 통창, 샹들리에, 벽난로), 모듈 소파, 그랜드 피아노, 와인셀러 (온도 디스플레이), 홈바 + 아이스메이커, 아일랜드 키친 + 빌트인 가전 (오븐, 식기세척기, 와인냉장고), 6-8인 대리석 식탁, 서재, 마스터 스위트 (킹 침대, 워크인 드레스룸, 오션뷰 욕조, 이중 세면대), 게스트 룸 + 파우더룸, 테라스 (자쿠지, 선베드, 파이어 테이블, 바비큐 그릴, 아웃도어 다이닝), 스마트홈 터치패널, 시스템 에어컨, 전동 커튼, 컨시어지 월패드, 미술품 + 픽처 조명"
   ],
   "interactionIdeas": [
    "Grand piano 'play' (melody, bench sit pose), home bar 'mix cocktail', wine room 'pick a bottle', fireplace on/off (flame neon + light)",
    "Smart-home scenes (영화 모드: curtains close + lights dim + TV on; 파티 모드: bar LEDs + music), motorized curtains",
    "Terrace: jacuzzi bubbles, BBQ grill cook, fire table, sunset/drone-show photo; concierge wallpad 'room service / call valet'"
   ]
  }
 ],
 "notes": "Full JSON (same content) written to /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/hotels_homes.json. Working files: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/hh/ (all.pkl decoded place, t0-t7.txt landmark/home trees, h_HomeUnit_*.txt templates, dens.json per-room density, c.py/hsum.py/dens.py helpers). Script evidence from bld/src/** (full v7 script dump) and v7all/gen/addons/zip/**.\n\nKEY FINDINGS\n1) Only ground floors of the landmarks are walk-in (AutoDoor). All upper venues (Homers 2F-4F, 6F front lounge, 6 ON ROOF TOP; Aqua 2F 광안차이나, 6F waterpark, 8F-9F 찜질방, 21F observatory, rooftop pool; Kent 2F cafe, 15F sky lounge, rooftop bar; culture-center 2F-3F gallery) have no stair/escalator/working elevator; lobby elevators are decoration. Photo spots 'rooftop' (209,75,135) and 'infinity' (-60,258,155) in GwangalliInteractShared are unreachable. The existing ElevatorButton (Floor, Target='ElevatorStop_<n>', Label) + ElevatorStop contract in ServerScriptService.GwangalliGameplay.Venues (fade + safe teleport; also used by StreetInteract/Places for NPCs) is the zero-code way to connect them, but needs server-side tagged parts (only used today in Workspace.Gwangalli.bowling.상층_2F-4F.엘리베이터_광안빌딩).\n2) Floors above the amenity levels are solid Core blocks behind NightWindow glass; hotel rooms exist only in the Annex instance, which for all three hotels is the same generic A.hotel casino hotel with a hard-coded 'HOTEL SEASIDE GWANGAN' logo wall (branding/program mismatch).\n3) Real programs (web): Homers 1F 수제맥주, 2F 조식당/세미나, 3F 웨딩홀, 4-5F 연회장, 6F 프런트 + 6 ON ROOF TOP; Aqua Palace 실내 비치 워터파크 (파도풀, 바디슬라이드), 816 m 온천수 24h 오션뷰 사우나·찜질방, 2F 조식, 21F 스카이전망대; Kent 24h desk, 뷔페, 커피숍, 루프탑 (15F reception unconfirmed). The static map layout matches these.\n4) Density (visible non-shell parts per 100 sq studs): Homers lobby 8.1, wedding lobby 1.7, 2F/3F/4F 2.1/1.4/1.1, 6F front 1.7, roof 4.6, Bronx 9.8; tourist info 8.5, police 2.0, gallery 0.8; Aqua lobby 4.3, leisure front 1.2, 홍미당 6.6, 2F China 1.3, waterpark 1.3, 찜질방 1.3, observatory 0.13, roof pool 0.9; Kent lobby 4.5, GS25 27, 2F cafe 4.1, sky lounge 3.2, roof bar 1.9. Real lights: Homers 5, Aqua 6, Kent 3; the rest are Neon slabs. All geometry is boxes/cylinders/balls (SpecialMesh only on foliage/pillows), no textures.\n5) Staff/flows: ShopStaff only treats BaseParts named PosBase/POS/BarCounter/FrontDesk/CashierPanel outside storefronts as counters, so hotel FrontDesk/ConciergeDesk/LeisureFront/InfoCounter/PoliceDesk/BarCounter (all Models) get no NPC; 홍미당 (POS) and GS25 광안해변점 (PosBase) do. ShopLife ordering covers none of the landmark shops.\n6) Do not break: GwangalliDoors AutoDoor models + leaf attrs (OpenOffset/ClosedCFrame/Collides); Annex door/sign reading (part names DoorLeaf/LobbyDoor/EntranceDoor/FrontDoor/Door/GlassDoor/ShopDoor/BackDoor/ServiceDoor, Sign_*, ShopGlass/ShopWindow; model attrs Annex/AnnexKind/AnnexFloors); MapIndex building detection (Core/Pier/Spandrel/Roof children); Destination tag + DisplayName (taxi, delivery, nav, HUD, quests); NightWindow/NightGlow/NightNeon/NeonTube/LEDScreen(Messages)/NearLOD/InteriorLight/GwSurfaceGui tags; GwangalliTextures skips LOD='near' ancestors; Details lost-wallet counter at (96,6.5,101) outside the tourist center. New client parts should be CanQuery=false and not use Annex door names.\n7) Homes: Workspace.Gwangalli.homes only holds 5 HomeEntrance portals (non-colliding prompt part + neon cue + kiosk). Real interiors are ServerStorage.GwangalliHomes.HomeUnit_<tier> templates (goshiwon 228, oneroom 312, officetel 383, apartment 759, penthouse 889 parts excluding backdrops) staged at x=-4000/-2000/0/2000/4000, y=1000, z=10000, cloned per owner by ServerScriptService.GwangalliGameplay.Housing into Workspace.GwangalliHomeInstances (Home_<UserId> / Tour_<UserId>) at x=0, y=4000+row*1400, z=(col-3.5)*3200 (8 columns), PrimaryPart UnitRoot, PersistentPerPlayer streaming. Preserve UnitRoot, Spawn, ExitDoor, HomeInteract (Kind/Label/SlotId/UseAt Pose), FurnitureSlot Models (server swaps furniture), Room+Surface attrs (theme recolour), Lights with Room, Backdrop, TVScreen/Screen parts, model attrs HomeOwnerId/HomeTier/HomeListing/TvOn/Staged. A client AAA overlay should key off those attrs, re-run when slots change, add detail around the shell and mirror theme colours rather than hide Room/Surface parts. GwangalliHomesFloors v2 defines 14 layouts but only the 5 tier templates exist in v7, Housing.templateFor only looks up HomeUnit_<tierKey>, and homes.Buildings (lobbies/halls) does not exist.\n8) Entrance surroundings are crude: the goshiwon portal stands beside 광안 메디컬 의원 with no 고시원 building; the 미성맨션 'Lobby' is a solid brick cube; the TERRASTAR OCEAN lobby Interior model is empty; 광안자이 has only a gate; the penthouse portal overlaps the Aqua Palace AutoDoor and its Annex prompt (three prompts at one door).\nWeb sources: https://mom-mom.net/travel/properties/64f0b3b4acda0efda76e4f04 , https://kr.trip.com/hotels/busan-hotel-detail-1171946/homers-hotel-busan/ , https://mom-mom.net/travel/properties/64f80bafacd3f742aa51a681 , https://www.ktriptips.com/kor/stay/397655 , https://mom-mom.net/travel/properties/64f0b9f64115596698521126 , https://www.trvlogue.com/ko/busan-aquapalace-review"
}
```
