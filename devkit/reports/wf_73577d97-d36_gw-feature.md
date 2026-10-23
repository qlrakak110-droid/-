# gw-feature (wf_73577d97-d36)

- status: completed
- failed agents (never finished, usually the usage limit): build:decor, fix:decor, review:decor:correctness, review:decor:experience, test:decor

## research:decor

# GwangalliDecorPlus — 내 집 마련 "자유 배치" 인테리어 add-on: research + design

Paths: `bld/src/...` = the dumped v7 scripts under
`/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/src/<Service>/<Path>.<Class>.luau`.
Line numbers are from that dump. Template geometry comes from `place.bin` (survey script and output:
`/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor/survey.py`, `templates.json`).
Catalog numbers come from a Luau CLI run over the real shared modules (`feat/decor/cat/stat.luau`).

---------------------------------------------------------------------------------------------------

## 0. Summary

1. **The place has two separate home systems.**
   - **A. Life-game homes** (`ServerScriptService.GwangalliGameplay.Housing`). These are the 내 집 마련 of the phone
     부동산 app, the realtor 정실장, the HomeEntrance prompts, rent/buy/loans and visits. Each owner gets a
     clone of `ServerStorage.GwangalliHomes.HomeUnit_<tier>` in `Workspace.GwangalliHomeInstances`, high above the
     map (y ≥ 4000). Decorating today is **slot-based only**: each slot swaps between catalog variants, can take a
     quarter turn, and each room has 벽지·바닥·조명 themes.
   - **B. District units** (`ServerScriptService.GwangalliBuildings`: Housing/Decor/HostBridge). These are physical
     units in the procedural demo district at (4283,19,-200). They already have free placement, but with their own
     catalog (`GwangalliBuildingsShared.Furniture`, 67 items), their own DataStore and their own client
     (`GwangalliBuildingsClient/DecorMode`). Through HostBridge they appear in the phone as `gwb_*` listings.
   - **Target: system A.** It is the main 내 집 마련 loop, and its creative decoration is missing.
2. **System A's free placement is half-built.** `ReplicatedStorage.GwangalliHomesShared` (HS) v2 already defines:
   - the free-placement catalog: 104 items in 20 categories with colourways and placement kinds
     floor/wall/small/rug, plus pure spec builders;
   - footprint/overlap math and record helpers;
   - an action list (`decorPlace/decorMove/decorRemove/decorRestore/decorColor/decorOpen/likeHome`);
   - **a persisted schema** `d.housing.units[listingId].items` + `nextUid` + `likes`. The profile sanitizer keeps it,
     move-out sends the items to 창고, and it counts toward 인테리어 점수, 편안함 and 순자산.

   What is missing: **no server handler and no client UI exist.** `Housing.onAction` drops unknown actions, and the
   `HomeDecor` feature module that `GwangalliGameplay.Script` lists in `FEATURE_MODULES` does not exist in v7.
   GwangalliDecorPlus fills exactly this gap, as an add-on.
3. **Integration strategy.** Use our own remotes and our own Script/LocalScript.
   - Read and write the life-game profile through the already-initialised modules: `Profiles`, `Housing`, and `ctx`
     from `VenueLife.ctx`.
   - Charge through `ctx.spend` (fallback: the `ServerStorage.GwangalliGameplayAPI` BindableFunction).
   - Build the item models inside the owner's home instance at `inst.model.DecorPlus` with the tag `GwDecorItem`.
     GwangalliBuildingInterior's `Homes.luau` already keeps that folder and tag clear.
   - Persist only G.FURNITURE ids, so the profile sanitizer can never drop a purchase.

---------------------------------------------------------------------------------------------------

## 1. Existing integration points (exact)

### 1.1 Boot order, folders, name collision

- `ServerScriptService` contains **both** a `Folder GwangalliGameplay` (modules) **and** a `Script GwangalliGameplay`
  with the same name. In v7 the Folder comes first, but the bootstrap finds it by class:
  `bld/src/ServerScriptService/GwangalliGameplay.Script.luau:41-48`
  ```lua
  -- The modules folder shares this script's name, so find it by class.
  for _, c in script.Parent:GetChildren() do
      if c:IsA("Folder") and c.Name == "GwangalliGameplay" then folder = c ...
  ```
  → **Our Host must do the same.** Do not use `ServerScriptService:FindFirstChild("GwangalliGameplay")`; HostBridge does
  (`GwangalliBuildings/HostBridge.ModuleScript.luau:68`), and it works only because of the current child order.
- Init order (`GwangalliGameplay.Script.luau:446-451`): `Profiles.init → Venues.init (→ VenueLife.init) → Taxi → Jobs →
  Life.init (→ Housing.init) → NPC`, then the optional `FEATURE_MODULES` (line 477, includes the missing `"HomeDecor"`),
  then `Profiles.startAutosave()` (511). ModuleScripts are cached per VM, so `require(folder.Housing)` from our Script
  returns **the same initialised table**.

### 1.2 How a player gets a home (system A)

- Listings: `bld/src/ReplicatedStorage/GwangalliGameplayShared.ModuleScript.luau:1160-1167`

  | listingId | name | kind | price | tierKey |
  |---|---|---|---|---|
  | `goshiwon` | 광안 고시원 1인실 | rent | 0원 보증금 + 6,000/일 | goshiwon |
  | `oneroom` | 광안동 풀옵션 원룸 | rent | 300,000원 보증금 + 14,000/일 | oneroom |
  | `officetel` | 테라스타오션 오피스텔 | rent | 1,000,000원 보증금 + 30,000/일 | officetel |
  | `xi_apt` | 광안자이 아파트 84㎡ | buy | 12,000,000원 (관리비 15,000/일) | apartment |
  | `aqua_ph` | 아쿠아펠리스 오션뷰 펜트하우스 | buy | 48,000,000원 (관리비 40,000/일) | penthouse |

  HostBridge appends `gwb_<building>_<template>[_ocean]` listings at runtime. These are system B, and entering one
  goes to the district unit (`HostBridge.ModuleScript.luau:7-16, 365-370`).
- Contract paths:
  - phone 부동산 app → `PhoneAction "rentHome"/"buyHome" {listingId}` (`GwangalliGameplay.Script.luau:595-600`);
  - `HomeAction "buyWithLoan"`;
  - the 입주 문의 prompt at HomeEntrance parts (client `GwangalliHome.LocalScript`, header lines 2-4).

  These call `Life.rentHome / Life.buyHome / Life.buyHomeLoan` (`GwangalliGameplay/Life.ModuleScript.luau:325, 348, 374`),
  which call `G.rentHome / G.buyHome` (Shared:1291, 1354). Moving out calls `leaveListing → G.moveOutFurniture`
  (Shared:1271-1277). The HS wrapper (HS:2251-2278) **moves the free items (`u.items`) to 창고 too**, selling any over
  the cap at 50 %.
- Profile home record: `d.home = { listingId, tier, owned, dueIn, missed, arrears, deposit }` + address
  (floor / unit / layoutId / priceMult / view), re-attached by the HS `G.reconcileHousing` wrapper (HS:2223-2249).
- Entering: `Housing.enter(player, via, quiet)` (`GwangalliGameplay/Housing.ModuleScript.luau:1799`). The callers are
  `HomeAction "enter"`, `PhoneAction "enterHome"`, and `Life.enterHome` (Life:466).

### 1.3 Home instances (server, system A)

- Templates: `ServerStorage.GwangalliHomes` (Folder attrs `SlotSpacing=3200, StackAxis="Y", Tiers=...`) holds
  `HomeUnit_goshiwon|oneroom|officetel|apartment|penthouse`.
  - Each template's children: `UnitRoot` (PrimaryPart), `Shell`, `Fixtures`, `Furniture` (slots), `Props`,
    `Interact`, `Backdrop`, `ExitDoor` (tag HomeInteract, Kind door), `Spawn`.
  - Model attrs: `DisplayName, KoreanName, Tier, TierIndex, ListingId, Rooms, PartCount, LightCount, GeomExtent, ViewExtent`.
- Cloning: `buildInstance` (Housing:1370-1570).
  - Clone the template, pivot UnitRoot to `G.homeSlotPosition(index, spacing)` (Housing:1405-1408, Shared:1643-1651:
    origin (0,4000,0), rows stack in Y), and anchor every part.
  - `Core.proxifyInteracts` (Housing:242-273).
  - `ModelStreamingMode = PersistentPerPlayer` + `AddPersistentPlayer(owner)`; guests are added in `attach()`
    (Housing:1456-1461, 1613-1617).
  - Model attributes (Housing:1462-1468): `HomeOwnerId=<userId>`, `HomeTier=<tierKey>`, `HomeListing=<listingId>`,
    `TvOn`, `Staged=true` (tours only).
  - Name: `"Home_<userId>"` or `"Tour_<userId>"` (Housing:1382). Parent `Workspace.GwangalliHomeInstances` (Housing:1469).
  - **The parenting happens before themes, slots and prompts are built.** All of that is synchronous with no yields up
    to `return inst` (Housing:1475-1569), so a `ChildAdded` handler with `task.defer` runs after the build has finished.
- Lifecycle:
  - destroyed by `destroyInstance` (Housing:1298-1320) on leave (`Housing.onLeave` 3447), on move/eviction
    (`Housing.onHomeChanged` 3362-3396), and after `G.HOME_IDLE_DESTROY = 900` s empty (tick, Housing:3523-3529);
  - tour units are destroyed 5 s after the viewer leaves (3531-3535);
  - our item models live inside the instance and die with it, so they must be rebuilt every time a new instance appears.
- Player attributes (Housing:970-975): `InHome = <owner userId>` (0 outside), `HomeRole = "owner"|"guest"|"viewer"|""`.
- Public server API we will call (Housing module table):
  - `Housing.available(): boolean` (1771), true once `remotes.HomeState` exists.
  - `Housing.instanceOf(player): Inst?` (1775), the owner's live instance (even when they are outside).
  - `Housing.where(player): (Inst?, role?)` (1779), the instance the player is in plus their role.
  - `Housing.isAtHome(player)` (1785), `Housing.enter(...)` (1799), `Housing.leave(...)` (1868),
    `Housing.openInterior(player)` (2944), `Housing.summary(player)` (3354).
  - `Housing.Core` (33): `Core.buildSpec(spec, frame, parent, name, maxLights) -> (Model, extra)` (282),
    `Core.collectThemes(model, view)` (361), `Core.roomBox(th, room, frame) -> (centre, size)` (504),
    `Core.roomAt(th, pos) -> room?` (541), `Core.scanUnit(model)` (191).
  - `Inst` fields we read: `owner, ownerId, listingId, tierKey, model, root, spawn, exit, slots[id] = {category, geo
    (container, base, frame, w, h, d), canRotate, current, rot}, interacts = {{part, kind, prompt, useCF}},
    themes (rooms/order), occupants[player] = role, staged, bboxCF/bboxSize`.
- Side effects inside the model that affect us:
  - `applyTv` / `rescanScreens` (Housing:1123-1157) turn **every** part named `Screen` or `TVScreen` in the whole model to
    Neon when the TV is toggled. HS `cu_roller` names a fabric blind part `Screen` (HS:602), which is an existing bug.
    In our builds, `Screen` names are kept only for TV items.
  - `sit()` (Housing:2145-2207) uses the nearest free `Seat` among **all** model descendants, so our placed sofas and
    chairs can be used by the 소파/식탁/책상 prompts. That is acceptable and even desirable.
- Test hook `ServerStorage.GwangalliHomesAPI` (BindableFunction, Housing:3550-3632 / 3705-3717):
  `Invoke("status"|"open"|"grant", userId?, amount?)`; grant works only in Studio or with
  `ServerStorage:GetAttribute("GwangalliTestMode")`.

### 1.4 Template geometry (UnitRoot-local; rotation is identity in all five)

| tier | rooms (Shell floor parts) | extent (x × z studs) | ceiling | levels | slots | parts / lights |
|---|---|---|---|---|---|---|
| goshiwon | main, FloorEntry, FloorBath | 7.2 × 12 | 7.8 | 1 | 6 (bed, desk, chair, shelf, art, appliance on desk y=2.55) | 246 / 3 |
| oneroom | main, kitchen, FloorEntry(y -0.4), FloorBath(0.2) | 20 × 16 | 7.9 | 1 | 12 | 332 / 4 |
| officetel | living, kitchen, FloorEntry, FloorBath, Floor; **loft y=8.4** (LoftFloor) | 30 × 17 | 16 (double height) | 2 (Fixtures/Stair 9 steps) | 16 (bed on the loft) | 489 / 4 |
| apartment | living, kitchen, bedroom, study, dress, 2×FloorBath, FloorEntry, FloorVeranda(-0.3) | 40 × 34 | 7.8 | 1 | 18 | 974 / 4 |
| penthouse | living, dining, kitchen, study, entry, FloorWine, FloorPowder, FloorEntry, **bedroom mezzanine y=9.4** (MezzFloor), FloorBath(9.5), **TerraceDeck** | 60 × 26 + terrace | 9.0 | 2 (Stair 10 treads) | 22 | 992 / 4 |

- Floor-type parts: `Shell` descendants with `Surface="floor"` or names `Floor*`, `LoftFloor`, `MezzFloor`, `TerraceDeck`.
  `Backdrop/광안대교/Deck` must be excluded. Shell parts keep default CanCollide/CanQuery = true.
- Wall-type parts: Shell `Surface="wall"`, `Wall`, `Partition`, `TileWall`, `TerraceWall`.
- Most Fixtures/Props/Furniture detail parts have CanCollide=false and CanQuery=false. The bodies (cabinets, fridge,
  wardrobe, bed body, sofa, ...) collide and are queryable (oneroom: Shell 28, Furniture 25, Props 26, Fixtures 14
  colliding parts).
- Slots: Models tagged `FurnitureSlot` with attrs `SlotId, Category, DefaultItem, Footprint (V3), Rotate?, Room?`,
  `SlotBase` part + child Model `Furniture` (`Default=true, ItemId=<kit id>`). Geometry via
  `G.slotGeometry(container)` (Shared:1664-1717).
- Interact parts (`Interact/Interact_<kind>`, tag `HomeInteract`, attrs `Kind, Label`, CanCollide=false and
  CanQuery=true). For example, oneroom has bed, wardrobe, fridge, table, tv, sofa, shower, window, mailbox, interior
  (the 현관 wall panel "🛠 인테리어") and ExitDoor.
- Doors: Models named `Door` (oneroom 2 … apartment 6), plus `WetCellDoor`, `VerandaDoor`, `Jungmun` (중문);
  `ExitDoor` part; `Spawn` part just inside the door.

### 1.5 Current decoration in system A (slot-based) — remotes and payloads

Remotes are in `ReplicatedStorage.GwangalliRemotes` (`G.RemotesFolder`, Shared:79). Housing creates them
(Housing:3695-3697):

- `HomeAction` (RemoteEvent, client→server, `(action, payload)`).
  - Dispatch: Housing:3302-3323.
  - **Drop rule:** `if type(action) ~= "string" or not handlers[action] or not G.HOME_ACTIONS[action] then return end`.
  - Then a bucket of 6/12 and per-action cooldowns `G.HOME_ACTIONS` (Shared:1577-1581 + HS:2177-2193).
  - Decor-related handlers:
    - `placeFurniture {slotId, variantId, rot?, sellOld?}` (Housing:2683-2740) → `HS.buyFurniture` (HS:354-396) →
      `G.placeFurniture` (Shared:2523-2564, bank first, the replaced piece goes to 창고);
    - `resetSlot {slotId}` (2742), `sellSlot {slotId}` (2762, 50 %), `sellStored {variantId}` (2783),
      `rotateSlot {slotId, rot 0..3}` (3022);
    - `setTheme {room, kind="wall"|"floor"|"light", id|"default"}` (2959-3019): price
      `HS.themePrice(kind,id,tierKey,room)`, paid with `G.spend(d, price, label, os.time(), "bank")`;
    - `openInterior` (2924), `tour {listingId}` (3052), `compliment` (3094), `upgrade {upgradeId}` (2807).
- `HomeState` (RemoteEvent, server→client `{kind=...}`): `enter` (payload Housing:1711-1746: role, ownerId, listingId,
  tierKey, homeName, slots, modelName, staged, housing), `exit`, `guests`, `furniture`, `interior` (2889-2920),
  `themes`, `interiorResult`, `doorbell`, `invite`, `tv`, `panel`, `pose`, `openApp`.
- `HomeQuery` (RemoteFunction, `"summary"`).
- Theme catalog (HS:79-139):
  - 벽지 6: silk_ivory, warm_beige, sage_green, dusty_blue, concrete, wood_panel;
  - 바닥 4: oak, walnut, porcelain, grey_tile;
  - 조명 5: warm, neutral, cool, amber, violet;
  - priced × `HS.TIER_MULT` (1/1.4/2/2.8/4) × `HS.ROOM_FACTOR`;
  - applied by `Core.applyRoomTheme` (Color + Material only) on parts with the `Room` + `Surface` attributes.
- Client:
  - `GwangalliHome/Interior` opens `ScreenGui "GwangalliInterior"` (DisplayOrder 16, `HideGwangalliHUD=true`,
    Interior:1375-1390). It has a scripted orbit camera, slot highlights and ghosts, tabs 🛋️ 가구 / 🎨 벽지·바닥·조명,
    and a 📦 tab that opens the legacy storage sheet.
  - `GwangalliHome.LocalScript`:
    - `HomeBar` sits in `ScreenGui "GwangalliHome"` (DisplayOrder 12) with the buttons 🛠️ 인테리어 / 💌 초대 / 🚪 나가기
      (lines 501-532);
    - the sheets live in `GwangalliHomeSheet` (15); the doorbell and invite popups in `GwangalliHomePopup` (**31**);
    - **PC key `B` = 인테리어, `I` = 초대** (2190-2200).

### 1.6 Free-placement groundwork that already exists (HS v2) — what we reuse

`bld/src/ReplicatedStorage/GwangalliHomesShared.ModuleScript.luau`. G and HS are pure modules, identical on server and
client, and `HS.extend(G)` runs at the end of the `GwangalliGameplayShared` require (Shared:3591-3605).

- Schema and limits:
  - schema comment, HS:1339-1351: `items = { { u = uid, i = itemId, v = colourway, x, y, z (UnitRoot frame), r = yaw°,
    m = room id, s = stacked } }`;
  - `HS.DECOR` (HS:1355-1368): `CAP=200, PART_CAP=2600, LIGHTS=3, ROOM_LIGHTS=4, REFUND=0.5, FRESH_SECONDS=600,
    TRASH_SECONDS=600, OVERLAP_MAX=0.35, MAX_HEIGHT=14, BATCH_MAX=40, GRID={0.5,1,0}, ROT_STEP=15`.
- Catalog and specs:
  - `HS.placeKind(itemId) -> "floor"|"wall"|"small"|"rug"` (1393);
  - `HS.CATALOG_TABS` (1403, 12 tabs: 소파·의자, 침대, 테이블·책상, 수납, 조명, 러그, 식물, 소품·벽장식, TV·가전, 주방,
    욕실, 커튼) and `HS.catalogTab(tabId) -> {itemId}` sorted by price (1419);
  - colourways: `HS.colorwayCount / colorway(id,cw) -> {name,color} / clampColorway / itemDef(id,cw)` (1487-1525,
    palettes PAL 1460-1471, e.g. fabric 그레이/네이비/카멜/올리브/크림);
  - `HS.itemSize(id)` (1527), **`HS.itemSpec(itemId, cw, stacked) -> spec`** (1575, drops the "Stand" pedestal when
    stacked), `HS.specBounds(spec)` (1612, **conservative cube for arbitrarily rotated parts**), `HS.itemBounds(id,
    stacked)` (1638, cached), `HS.itemPartCount` (1649).
- Collision helpers: `HS.decorBox(id, s, x, y, z, rDeg)` (1658), `HS.boxCorners` (1676), `HS.overlapFrac(a,b)` (1695,
  5×5 sampling; **rugs never overlap**), `HS.checkOverlap(items, cand, ignoreUid)` (1722).
- Records:
  - `HS.decorItems(unit)` (1736), `HS.findItem(unit, uid)` (1746);
  - **`HS.addItem(unit, rec) -> stored rec (new integer uid, rounds to 0.01)`** (1760), `HS.removeItem(unit, uid)`
    (1784), `HS.itemsDecor(unit)` (1793), `HS.itemsValue(unit)` (1804);
  - `HS.sanitizeItems(raw, unit)` (1816-1861): ≤200 items, `G.FURNITURE[i]` required, x/z clamp ±400, y -60..120,
    integer uid ≥1, `nextUid`, `likes`;
  - `HS.unitOf(d, listingId)` (150), which creates `{slots, rot, walls, floors, lights}`.
- Wrappers into G (HS:2119-2333):
  - `G.HOME_STORAGE_MAX = max(60, 200)` (2160);
  - action names with cooldowns, `decorPlace 0.12, decorMove 0.08, decorRemove 0.12, decorRestore 0.12,
    decorColor 0.1, decorOpen 0.5, likeHome 1` (2185-2192). These are registered, but **Housing has no handlers**, so
    the events are dropped;
  - `G.sanitizeHousing` keeps `items` (2209-2221) and `G.moveOutFurniture` moves them to 창고 (2251);
  - `G.furnitureValue` (2280) and `G.homeDecor` include items (2288);
  - `G.housingView` adds `itemCount, itemCap, likes, address` (2295-2332).
- Catalog (Luau CLI run): **104 items**, average **8.5 parts**, 1-6 colourways each.
  - Placement kinds: floor 65, wall 18 (art, curtains, tv_wall, bath cabinet/towel, wall clock/shelf/mirror),
    small 15 (candles, vase, books, diffuser, figures, cactus, eucalyptus, moon lamp, microwave, dish rack,
    toiletries, console, cushions, photo frames, aquarium), rug 6.
  - Categories: sofa 7, bed 6, tv 5, table 6, desk 4, chair 7, shelf 5, lamp 6, plant 7, rug 5, art 6,
    appliance 9, curtain 6, deco 15, kitchen 5, bath 5.
  - Prices range 20,000원 (art_ikea) to 6,500,000원 (tv_luxury), with decor 1-12.
  - 24 items carry 1 light; seats on sofas, chairs and table_glass; screens on 5 TVs.
- **The conservative bounds are a real problem.** `cu_wood_blind` measures 8.0×10.9×**7.8**, `dc_mirror` 3×3×3 and
  `lamp_tripod` 5×5.4×5, because of rotated parts. Our Geometry module must compute exact rotated extents.

Also present but unused in v7: `ReplicatedStorage.GwangalliLivingConfig` `LC.DECOR` (grid steps {0.5,1,2},
rotSteps {15,45,90}, placedCap 120, partCap 1500, pathWidth 3.6, previewValid/Invalid colours) and
`GwangalliLivingPlan/Shared`. These are data for a never-shipped "living tower"; we only borrow the tuning ideas.

### 1.7 Saving

- DataStore `GwangalliProfile_v1`, key `u_<UserId>` (Shared:76-77). Implemented in
  `GwangalliGameplay/Profiles.ModuleScript.luau`: UpdateAsync with a session lock (363-433), autosave every 120 s
  when dirty, save+release on leave.
- `sanitize` (149-337) **drops every unknown top-level key**. The exceptions are pass-throughs `work, law, fuel, dealer`
  (304-310), the open flag set `d.milestones[k]=true` for any string key (297-303; precedent:
  `d.milestones.jr_club_open` in Play/Journey/Club:341), and `d.housing` via `G.sanitizeHousing`, which HS wraps to
  keep `items`.
- **Consequence:** a free-placed item persists with the profile only if `G.FURNITURE[i]` exists **at profile-load time**.
  Never invent new item ids at runtime, because a profile loaded before the registration would lose those pieces.
- API:
  - `Profiles.get(player) -> d?` (460), `Profiles.isLoaded` (468), `Profiles.wait(player, timeout)` (474);
  - `Profiles.markDirty(player)` (486);
  - `Profiles.saveSoon(player, delay)` (601-621, coalesced, ≥7 s apart);
  - `Profiles.persistent(player)` (587): false for memory-only profiles (unpublished Studio, outage).

### 1.8 Money and stats

- Pure (Shared):
  - `G.ledger(d, account "cash"|"bank", delta, label, now, meta?) -> (ok, reason)` (710-747);
  - `G.spend(d, amount, label, now, prefer "bank"?) -> (ok, account)` (754-773; prefer bank, then the other account,
    labelled "(체크카드)");
  - `G.canAfford` (749), `G.sellStored(d, variantId, now)` (2601), `G.furnitureResale(id)` (= price × 0.5).
- Context (`GwangalliGameplay.Script.luau`):
  - `ctx.changed(player, ...keys)` (262-276: marks dirty + coalesced `ProfileChanged` push);
  - `ctx.ledger(player, account, delta, label, silent)` (305-321: sets the `Money`/`Bank` attrs + a toast);
  - **`ctx.spend(player, amount, label, silent, prefer)`** (337-353);
  - `ctx.addStats(player, delta, reason, silent)` (355-371);
  - `ctx.notify(player, kind, title, body, extra)` (237-248, `Notify` remote → GwangalliUI toast);
  - `ctx.refreshAttributes(player)` (278).
- **Getting ctx from outside:** `GwangalliGameplay/VenueLife.ModuleScript.luau:966` sets `VenueLife.ctx = ctx`, and
  Venues.init always loads it (`Venues.ModuleScript.luau:1407`). Fallback: `GwangalliGameplay/StreetInteract`
  (`Interact.ctx = ctx`, line 1267).
- No-ctx fallback: `ServerStorage.GwangalliGameplayAPI` (BindableFunction, Script:458-475):
  `Invoke("balance", player) -> cash, bank`; `Invoke("spend", player, amount, label) -> bool` (ctx.spend, cash first,
  with a toast); `Invoke("earn", player, amount, label)` (bank); `Invoke("addStats", player, delta, label)`.
- Gameplay value of decorating:
  - `G.homeComfort(d) = listing.comfort + upgrades + min(10, floor(G.homeDecor(d)/6))` (Shared:2715), which adds
    happiness when sleeping (`Life.sleep`, Life:520);
  - `G.homeDecor` includes items via the HS wrapper.

### 1.9 Other remotes and bindables in play

- `GwangalliRemotes`: `GetProfile` (RF), `ProfileChanged`, `PhoneAction`, `Notify`, `TaxiState`, `Dialog`, `WorkState`
  (RE; Script:120-128) + `HomeAction`, `HomeState`, `HomeQuery`.
- System B: `ReplicatedStorage.GwangalliBuildingsRemotes` (RemoteFunction + RemoteEvent, Registry:43-57, ops
  `decor.begin/place/move/remove/theme/room`, Decor.ModuleScript:347-608). **Not ours.**
- Client bindables made by GwangalliHome (1960-2003):
  - `LocalPlayer.GwangalliHomeOpen` (BindableEvent `:Fire("interior"|"tour", id|"close")`);
  - `LocalPlayer.GwangalliHomeQuery` (BindableFunction `:Invoke("state") -> {inside, role, homeName, listingId,
    tierKey, interior}`).
  - Wrapper module: `StarterPlayerScripts.GwangalliHome.Api`.

### 1.10 Client UI kit and layout contract

- `ReplicatedStorage.GwangalliUI` (K, 3375 lines). It is the house style for every screen:
  - tokens `K.Color` (glass navy + cyan/magenta/gold), `K.Font`, `K.Type`;
  - components `K.Button, K.Tabs, K.Segmented, K.Chip, K.SearchBar, K.BottomSheet, K.Modal, K.confirm, K.Toaster/K.toast,
    K.MoneyLabel, K.EmptyState, K.Slider, K.Toggle`;
  - helpers `K.won/wonShort/commas, K.pressable, K.feedback, K.countUp, K.reduced()`;
  - no image asset ids; emoji glyph tiles. Header lines 1-35.
- `ReplicatedStorage.GwangalliLayout` provides `Layout.rect(slot)` / `Layout.onChanged(fn)` for the slots `topCenter`,
  `bottomCenter`, `sheetRight`, `toasts`, `dialog`, ... (Layout:1-56).
  - Convention: an Enabled ScreenGui with `HideGwangalliHUD=true` makes the always-on HUD step aside (Layout:55-57;
    consumers: GwangalliInteractClient/Hud:527, ClubMusic, Journey, ...).
  - Use `IgnoreGuiInset=false` + `ScreenInsets=CoreUISafeInsets`.
- `ReplicatedStorage.GwangalliQuality` (`isLow()`, `reason()`) and `GwangalliAnim` are optional.

### 1.11 Other systems that touch homes

- **GwangalliBuildingInterior** (our other team, `src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior`).
  `Homes.luau:121-146` already reserves keep-zones for `FurnitureSlot` models, `HomeInteract` parts, **models tagged
  `GwDecorItem` or children of a `DecorPlus` folder**, and sets `V.decorPlus=true` when `model.DecorPlus` has children.
  T_home builds nothing (T_home.luau: empty build). `init.client.luau:122-127` skips GwangalliHomeInstances for shop
  dressing.
  → **Our naming contract:** the folder is `inst.model.DecorPlus` and every item model is tagged `GwDecorItem`.
- System B (`GwangalliBuildings` Decor/Housing/DecorMode): its own units (tag `GwB_Unit`, attr `OwnerUserId`, tag
  `GwB_Placed`). Do not touch it. Survey rule: "Player-owned homes (GwB_Unit ...) must not get extra props".
- Earlier map-survey rule (systems.json): "do NOT add detail inside GwangalliHomeInstances or HomeUnit_*". That rule
  targets decorative overlays; **player-placed furniture is exactly what those homes are for**, so we add only what the
  owner bought.

---------------------------------------------------------------------------------------------------

## 2. What exists vs what is missing

| Area | Exists in v7 | Missing (DecorPlus delivers) |
|---|---|---|
| Ownership / rent / buy / loans / bills | ✅ Life + Housing + phone 부동산 | — |
| Home instance per owner, visits, doorbell, 집들이 | ✅ | — |
| Slot furniture swap (catalog variants in fixed envelopes), quarter turns | ✅ | — (we link to it) |
| Room themes 벽지 6 / 바닥 4 / 조명 5 | ✅ setTheme + Interior UI | a quick-access tab in our editor that sends the same `HomeAction setTheme` (optional) |
| Free placement catalog (104 items, colourways, kinds, specs) | ✅ HS data only | server builders, validation, UI |
| Persisted free-item records, 창고 on move-out, decor/comfort/value | ✅ HS schema + wrappers | writers (no code ever adds items) |
| `decorPlace/Move/Remove/Restore/Color/Open/likeHome` actions | names + cooldowns only | **handlers (our own remotes)** |
| Wall-mount, surface stacking, rug layering rules | described in HS comments | implementation (server + client preview) |
| Exact bounds for rotated parts | ❌ (conservative cube) | Geometry.exactBounds |
| Placement editor (camera, ghost, grid/rotate snap, undo, 창고) | ❌ for system A | full editor (PC / mobile / gamepad) |
| Item interactions (sit on placed sofa, toggle lamp, TV glow) | partly (Housing sit/applyTv scan the model) | prompts on placed items, light budget |
| Likes (`unit.likes`) | field persisted, never written | ❤️ 좋아요 for guests + counter |
| Milestones / rewards for decorating | ❌ | `d.milestones.dp_*` + small stat rewards |
| Photo / showcase mode | window photo only (Housing) | 📸 집 사진 mode (cosmetic) |
| Layout presets, extra catalog, co-decorating | ❌ | P2 (own DataStore), see §4.15 |

---------------------------------------------------------------------------------------------------

## 3. Conflicts, risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | Two editors (Interior slot mode and ours) fight over the camera, controls and HUD | Mutual exclusion. Opening ours fires `LocalPlayer.GwangalliHomeOpen:Fire("close")` first. While `PlayerGui.GwangalliInterior.Enabled` is true, our entry button hides; if it turns true while ours is open, ours closes. Our ScreenGui uses DisplayOrder 16 (above HomeBar 12 and sheet 15, below popups 31, so the doorbell stays visible). |
| R2 | A free item collides with a slot piece later swapped to a bigger variant | Validate against **slot envelopes**: Footprint at the SlotBase frame (`G.slotGeometry`), and for `Rotate=true` slots the square of max(w, d), so it covers both turns. This applies to all kinds except rugs; rugs are tested only against the `rug` slot. |
| R3 | `applyTv` turns any part named `Screen` to Neon | In `Spec.build`, rename non-TV `Screen`/`TVScreen` parts to `ScreenPanel`. A TV item keeps its `spec.screen` part named `Screen`, so the room's TV prompt lights placed TVs too, which reads as a feature. |
| R4 | Housing `sit()` picks our seats | Allowed. Our seats: `Seat`, Transparency 1, CanCollide false, CanTouch false, CanQuery false, Disabled false (same as `Core.buildSpec`). |
| R5 | Profile sanitizer drops unknown ids, losing paid items | Only `G.FURNITURE` ids are ever stored. No runtime catalog additions to G/HS. An extra catalog (P2) would use its own record in its own store. |
| R6 | Money and item get out of sync | Both live in the same profile document. All checks happen first, then `spend` and the record mutation with **no yield in between**, then build. After purchases, `ctx.changed(player,"housing")` + `Profiles.saveSoon(player, 15)`. |
| R7 | Double charge (double tap, lag retry) | Every mutating request carries `rid` (≤24 chars). The server caches the last 32 results per player and returns the cached result on a repeat. |
| R8 | Exploits (fake coordinates, ids or prices; huge batches; spam) | Server-authoritative. Price comes from `G.FURNITURE`. Every number is type- and range-checked (finite, clamped). uids are checked against the player's own record. Batch limit `HS.DECOR.BATCH_MAX=40`. Token bucket 10/s burst 20 plus per-action cooldowns. Owner-inside-own-instance check every call. `GetPartBoundsInBox`/raycast validation. |
| R9 | Mobile budget (part count, lights) | Per-tier item and part caps (§4.13), `HS.DECOR.PART_CAP`, `Config.LIGHTS` real lights per home (the rest stay Neon), `CastShadow` only on collidable bodies, and no lights in ghosts or previews. |
| R10 | Host discovery race (our Script may start first) | `Host.discover()` retries every 1 s for 120 s until `Housing.available()` and `Profiles` respond. Until then remotes answer `{ok=false, code="booting"}` and the client button stays hidden. Instances that appeared earlier are scanned once discovery succeeds. |
| R11 | A future host version ships its own free placement (HS planned `HomeDecor`) | Dormant switch: if `folder:FindFirstChild("HomeDecor")` exists or `workspace:GetAttribute("GwHostDecor")==true`, we do not build. Our folder name `DecorPlus` never collides with host names. |
| R12 | System B units / `gwb_*` listings | `Housing.where` returns nil there, so our button never shows. We never touch `GwB_*` instances. |
| R13 | Instance destroyed mid-edit (idle, move, eviction, owner leaves) | The client watches `HomeState "exit"`, the `InHome` attribute and `model.AncestryChanged`, then closes the editor and shows "집 밖으로 나와서 꾸미기를 마쳤어요". The server drops sessions on model removal. Records stay in the profile. |
| R14 | An occupant gets trapped inside a new item | Reject when any occupant HumanoidRootPart lies inside the candidate box (inflated 0.5): `person` "사람이 서 있는 자리예요". Path check (P1) keeps doors and fixtures reachable. |
| R15 | Rugs z-fighting with rugs | Rug vs rug overlap > 10 % is rejected, including the rug slot envelope. Rugs get `y = floorTop + 0.02` and are drawn above the floor. |
| R16 | Staged 둘러보기 units | Never built. Optional client-only "가상 배치 미리보기" (P2) sends nothing to the server. |
| R17 | Keybind clashes | Entry `K` (unused in v7). In-editor keys are bound with `ContextActionService:BindActionAtPriority(..., Enum.ContextActionPriority.High.Value+50)` and return `Sink`; they are unbound on close. `B` stays with the slot mode. |
| R18 | Engine gaps in the browser studio (new APIs) | pcall every optional API: Highlight, TouchRotate, ViewportFrame camera, `AddPersistentPlayer`, `ModelStreamingMode`, `CoreUISafeInsets`. Fall back to SelectionBox and simple frames. |
| R19 | Map read-only rule / GUI rule | We never touch map parts. All our world models go under the home instance (server-owned, created at runtime) and `Workspace.GwDecorPlusLocal` (client ghosts). All GUIs live in PlayerGui; BillboardGuis are adorned, never parented under parts. |
| R20 | Exact-bounds drift between client preview and server | One shared `Geometry` + `Rules` module. The client uses the same rules with a local "world" adapter over the same replicated parts. The server stays final, and the UI shows the server's reason on a mismatch. |

---------------------------------------------------------------------------------------------------

## 4. Add-on design

### 4.1 Scope

- **P0 (ship).** Everything happens inside the owner's home:
  - free placement of any of the 104 HS items, with colourways, on floor / wall / surface / rug;
  - move, rotate (snap 15/45/90 or free), recolour, duplicate;
  - 창고로 / 팔기 (50 %) / 구매 취소 within 10 min (100 %);
  - place from 창고 (free);
  - undo/redo (20 steps);
  - budgets (count, parts, lights);
  - exact validation with Korean reasons;
  - a dollhouse camera with wall cutaway;
  - PC, mobile and gamepad controls;
  - guests see everything live;
  - placed sofas, chairs and beds get "앉기", lamps get "불 켜기/끄기", and TVs glow with the room TV.
- **P1.** Path check (doors and fixtures stay reachable), 스타일 세트 shopping lists (cart flow), ❤️ 좋아요 + counter,
  milestones with small rewards, a 📸 집 사진 mode, and a quick 벽지·바닥·조명 tab through the existing `setTheme`.
- **P2.** Layout presets (own DataStore), client-only virtual placement in 둘러보기, multi-select group move, sticker
  guestbook, extra catalog with its own store, owner-granted 함께 꾸미기.

### 4.2 Files (only the allowed paths)

```
src/ReplicatedStorage/GwangalliDecorShared/          (ModuleScript: init.luau + children)
  init.luau        entry: lazily requires G (GwangalliGameplayShared) and HS (GwangalliHomesShared) with
                   WaitForChild timeouts + pcall; exposes .Config .Text .Catalog .Geometry .Spec .Rules .G() .HS();
                   REMOTES_NAME = "GwangalliDecorPlusRemotes"
  Config.luau      every tunable (§4.13)
  Text.luau        every Korean string: reason codes -> messages, button labels, toasts, help
  Catalog.luau     catalog views over G.FURNITURE + HS: tabs, card info, search (Korean names + 초성 matching), style
                   filters, sorting, 스타일 세트 definitions (lists of {i, v}), price/decor helpers
  Geometry.luau    pure math: exact spec bounds (rotation matrices, not cubes), item OBB in the unit frame,
                   footprint corners, SAT OBB-OBB overlap + overlap fraction, snapping (grid / yaw / wall-align),
                   unit frame <-> world, wall-mount offset, box helpers, occupancy raster for the path check
  Spec.luau        spec -> Model builder used by server items, client ghosts and ViewportFrame previews (same geometry):
                   build(spec, frame, parent, name, opts{ghost, maxLights, seat, rename}) -> (Model, extra)
  Rules.luau       placement rules over an abstract `world` interface (server = real queries, client = local preview):
                   check(world, unit, cand, ignoreUid) -> (ok, code, detail, fixed = {x, y, z, r, s, m})

src/ServerScriptService/GwangalliDecorPlus/            (Script: init.server.luau + child ModuleScripts)
  init.server.luau boot: dormant check, Host.discover loop, remotes, instance watcher, PlayerRemoving cleanup
  Host.luau        discovery + adapters over the life game (Profiles, Housing, ctx / API fallback), §4.3
  Records.luau     profile-backed records: unit(d), items, storage, counts, fresh / trash session tables, milestones
  World.luau       per-instance server world: indexes (floors, walls, solids, slot envelopes, keep zones, levels),
                   raycasts / GetPartBoundsInBox with include lists, occupant positions; implements Rules' world API
  Builder.luau     builds / rebuilds / removes item models in inst.model.DecorPlus, light budget, prompts (앉기 / 불 켜기 /
                   TV), watches Workspace.GwangalliHomeInstances
  Actions.luau     Request handlers (open / place / move / color / remove / restore / sellStored / like / photo), payload
                   validation, bucket + cooldown + rid cache, Event pushes
  Social.luau      likes (dedupe), owner toasts, milestones + rewards (ctx.addStats), housewarming hooks

src/StarterPlayer/StarterPlayerScripts/GwangalliDecorPlus/   (LocalScript: init.client.luau + child ModuleScripts)
  init.client.luau boot: wait for shared + remotes, home state tracking, entry pill, K key, mutual exclusion
  Net.luau         Request wrapper (rid, timeout, busy flag), Event listener fan-out
  HomeCtx.luau     current home: model, unit frame, rooms, levels, client world adapter for Rules (local raycasts)
  Camera.luau      dollhouse orbit camera (room focus, orbit / zoom / pan, level switch) + cutaway (LocalTransparencyModifier
                   on Ceiling, camera-side walls, upper level) + restore
  Ghost.luau       ghost model (Spec ghost mode), validity tint, footprint plate, snap indicators
  Input.luau       pointer abstraction (mouse / touch / gamepad virtual cursor), gestures, CAS bindings (High+50, Sink)
  Editor.luau      state machine (browse / place / select / move), undo / redo, cart, calls Net, drives Ui
  Ui.luau          all screens (GwangalliUI K + GwangalliLayout; minimal fallback without K)
  Preview.luau     ViewportFrame thumbnails (lazy, cached ≤ 32, low tier = icon tiles)
  Visit.luau       guest overlay: ❤️ 좋아요, 🔍 구경 (tap to inspect), owner like counter
  Photo.luau       📸 집 사진 mode (UI off, free orbit, local ColorCorrection filters, restore)
```

Rojo note for the orchestrator: add mappings for `GwangalliDecorShared` (ReplicatedStorage), `GwangalliDecorPlus`
(ServerScriptService, **top level, not inside the GwangalliGameplay folder**) and `GwangalliDecorPlus`
(StarterPlayerScripts).

### 4.3 Boot and discovery (server)

1. `init.server.luau`: `Shared = require(ReplicatedStorage:WaitForChild("GwangalliDecorShared", 30))`. G and HS come
   from ReplicatedStorage (`WaitForChild` 60 s). If HS lacks `HS.DECOR`/`HS.itemSpec`/`HS.addItem`, warn once and stay
   dormant.
2. Dormant check (R11).
3. `Host.discover()`, repeated every 1 s for up to 120 s:
   - `folder` = the `ServerScriptService` child with `IsA("Folder") and Name=="GwangalliGameplay"`;
   - `Profiles = require(folder.Profiles)`, `Housing = require(folder.Housing)`;
   - ready when `Housing.available() == true` and `type(Profiles.get)=="function"`;
   - `ctx` = `require(folder.VenueLife).ctx`, else `require(folder.StreetInteract).ctx`; accept it only if it has
     `spend`, `ledger`, `changed`, `notify`, `addStats`;
   - else `api = ServerStorage:FindFirstChild("GwangalliGameplayAPI")` (BindableFunction).
4. Create `ReplicatedStorage.GwangalliDecorPlusRemotes` (Folder; children `Request` RemoteFunction and `Event`
   RemoteEvent; parent the folder last).
5. Instance watcher: for every child of `Workspace.GwangalliHomeInstances` (create a wait task if the folder is
   missing), plus `ChildAdded` → `task.defer` → if `model:GetAttribute("Staged")` is not true and
   `HomeOwnerId` > 0, call `Builder.buildAll(model)`. `ChildRemoved` / `AncestryChanged` → drop caches and sessions.
6. `Players.PlayerRemoving` → drop the session, rid cache and like cache (records are saved by Profiles).

Host adapter API (signatures):

```lua
Host.ready(): boolean
Host.profile(p): any?                          -- Profiles.get
Host.ownInside(p): (Inst?, code?)              -- Housing.where(p) == inst, inst.owner == p, not inst.staged,
                                               -- d.home and d.home.listingId == inst.listingId; codes notHome/staged/noProfile
Host.instOfModel(model): Inst?                 -- owner = Players:GetPlayerByUserId(model.HomeOwnerId); Housing.instanceOf(owner) with .model == model
Host.spend(p, amount, label): (boolean, string?) -- ctx.spend(p, amount, label, true, "bank") | api:Invoke("spend", ...)
Host.refund(p, amount, label)                  -- ctx.ledger(p, "bank", amount, label, true) | api:Invoke("earn", ...)
Host.changed(p, ...)                           -- ctx.changed(p, "housing", "cash", "bank") | Profiles.markDirty(p)
Host.saveSoon(p)                               -- Profiles.saveSoon(p, Config.SAVE_SOON)
Host.notify(p, title, body, extra?)            -- ctx.notify(p, "home", ...) | Event {kind="toast"}
Host.addStats(p, delta, reason?)               -- ctx.addStats | api:Invoke("addStats")
Host.roomAt(inst, worldPos): string?           -- Housing.Core.roomAt(inst.themes, pos) | name rules
```

### 4.4 Data schemas

**Persisted** (life-game profile, `d.housing.units[d.home.listingId]`). We create it with `HS.unitOf(d, listingId)` and
use only these fields:

```lua
items   = { { u = 7, i = "sofa_modern", v = 3, x = 2.5, y = 0, z = -4.75, r = 90, m = "living", s = nil } , ... }
nextUid = 8          -- HS.addItem maintains it
likes   = 12         -- total ❤️ from guests
```
- Coordinates are in the **UnitRoot frame** `F = CFrame.new(root.Position) * root.CFrame.Rotation`; y is the item's
  bottom.
- The world pivot is `F * CFrame.new(x, y, z) * CFrame.Angles(0, rad(r), 0)` (front = −Z).
- `s=true` means stacked on a surface (pedestal dropped).
- `m` is the room id: HS room ids, or `entry`/`bath`/`veranda`/`terrace`/`wine`/`powder` from floor names.
- Values are rounded by `HS.addItem` (0.01). The caps from `HS.sanitizeItems` apply.
- 창고: the shared `d.housing.storage[itemId] = n` (cap `G.HOME_STORAGE_MAX` = 200), the same pool the slot system uses.
- Milestones: `d.milestones["dp_first"]`, `dp_items10`, `dp_items30`, `dp_decor50`, `dp_decor100`, `dp_decor200`,
  `dp_like1`, `dp_like10`, `dp_like50`, `dp_set1`, `dp_photo1`.

**Server session memory** (not persisted):

```lua
sessions[player] = { inst = Inst, openedAt, rid = { order = {}, res = {} } (32), bucket = { t, tokens },
                     cool = { [action] = t },
                     fresh = { [uid] = { t = os.clock(), price = n } },        -- bought this visit -> 100 % refund
                     trash = { [uid] = { rec = {...}, how = "store"|"sell"|"refund", amount = n, t } } } -- undo of remove
likeSeen[ownerUserId][guestUserId] = os.time()   -- 20 h dedupe (lost on server restart = acceptable)
world[inst.model] = { floors, walls, solids, slotBoxes, keep, levels, baseParts = {}, version }
```

**Item model** (server-built, replicated through the persistent home model):

```
inst.model.DecorPlus                         Folder
  Item_<uid>      Model  tag GwDecorItem; attrs DecorUid=<uid>, ItemId, Colorway, Stacked, Room, OwnerUserId, PlaceKind
    DPHit         Part   PrimaryPart: exact-bounds box, Transparency 1, CanCollide false, CanTouch false, CanQuery true
                         (selection only; server queries always exclude DPHit parts)
    <spec parts>  Anchored; CanCollide = spec.collide; CanQuery = spec.collide (rug parts CanQuery false);
                  CastShadow = collide; Screen renamed for non-TV
    DPSeat        Seat (when spec.seat) + ProximityPrompt "앉기" on DPHit (kinds sofa / chair / bed / table_glass)
    PointLight    only inside the light budget; lamp items get prompt "불 켜기/끄기" (attr On)
```

**Client state** (Editor): `mode`, `pick = {i, v, s?}`, `ghostCF`, `sel = {uid}`, `undo = {...}`, `redo = {...}`,
`cart = {{i, v}}`, `settings = {grid=0.5, rot=45, cut=true}` (persisted per viewer in an attribute only, not
DataStore), `snapshot` (from open).

### 4.5 Remotes and payloads

`ReplicatedStorage.GwangalliDecorPlusRemotes`:

- `Request` (RemoteFunction) `Request:InvokeServer(action, payload) -> result`. Every result is
  `{ ok = bool, code = string?, msg = string? (Korean), ... }`. The server never yields on DataStore inside a handler.
- `Event` (RemoteEvent, server→client) `{ kind = ..., ... }`.

| action | payload (client → server) | checks | result (ok) |
|---|---|---|---|
| `open` | `{}` | own inside, profile | `snapshot` (below) |
| `place` | `{rid, i, v, x, y, z, r, s, src = "buy" \| "storage"}` | item id in G.FURNITURE; v integer clamp; finite numbers; caps; Rules.check; storage count / money | `{uid, rec, price, refund=0, src, balance={cash, bank}, counts, decor}` |
| `move` | `{rid, u, x, y, z, r, s}` | uid in record; Rules.check(ignore=u) | `{rec, counts}` |
| `color` | `{rid, u, v}` | uid; v ≠ current | `{rec}` (free) |
| `remove` | `{rid, uids = {...≤40}, how = "store" \| "sell"}` | uids in record; storage cap (store) | `{removed = {{u, how, amount}}, balance, counts, storage}` (fresh uids are always refunded 100 %, `how="refund"`) |
| `restore` | `{rid, uids = {...}}` | trash entry < TRASH_SECONDS; re-validate; money for sell / refund | `{map = {[oldUid] = newUid}, recs, balance}` |
| `sellStored` | `{rid, i, n = 1..10}` | storage count | `{amount, storage, balance}` (= G.sellStored ×n) |
| `like` | `{ownerId}` | caller is a guest in that owner's instance; 20 h dedupe | `{likes}` |
| `photo` | `{}` | own or guest inside; 90 s cooldown, max 3 a day (`d.housing.daily` untouched; own counter in milestones day key not needed: in-memory) | `{gain}` (small happiness) |

`snapshot`:

```lua
{ ok = true, ownerId, listingId, tierKey, homeName, address = "광안자이 101동 1203호" | false, owned = bool,
  caps = { items = n, parts = n, lights = n }, counts = { items, parts, lights },
  items = { recs... }, storage = { [itemId] = n }, storageCap = 200,
  rooms = { { id, name, icon, center = Vector3 (unit frame), size = Vector3, level = 1 | 2 } },
  levels = { { y = 0, name = "1층" }, { y = 8.4, name = "복층" } },
  keep = { { cf = CFrame (unit frame), size = Vector3, code = "door" | "entry" | "interact" | "stair", label = "침대" } },
  slots = { { id, category, cf = CFrame (unit frame), size = Vector3 } },     -- envelopes (rotation union applied)
  balance = { cash, bank }, decor = G.homeDecor(d), comfort = G.homeComfort(d), likes,
  config = { grid = {0.5, 1, 0}, rot = {15, 45, 90, 0}, freshSeconds = 600, trashSeconds = 600 },
  persistent = Profiles.persistent(p) }
```

`Event` kinds:

- `{kind="items", ownerId, add = {recs}, upd = {recs}, del = {uids}}`. Sent to every occupant, so guests' inspect lists
  and the owner's other open views stay current.
- `{kind="liked", by = displayName, likes}`, sent to the owner.
- `{kind="milestone", id, title, body}`.
- `{kind="close", code}`, sent when the instance is gone or the editor was opened elsewhere.
- `{kind="toast", title, body}`, used only when no ctx.notify is available.

Rate limits:
- token bucket 10/s burst 20 (move counts 0.5 token);
- cooldowns `open 1, place 0.12, move 0.08, color 0.1, remove 0.12, restore 0.12, sellStored 0.3, like 1, photo 2`
  (mirroring the `G.HOME_ACTIONS` decor values);
- the rid cache short-circuits repeats.

### 4.6 Placement rules (Rules.check, server-final)

Input: `cand = {i, v, x, y, z, r, s}` in the unit frame. Geometry derives the **exact item OBB** from
`HS.itemSpec(i, v, s)`: every part's rotated half-extents through the rotation matrix, then the min/max over all parts.
Order of checks (first failure wins; `code` → Text):

1. **Common.**
   - Finite numbers; `|x|, |z| ≤ 200`; `r` normalised to [0, 360).
   - Snap: when `r` is within 0.5° of a 15° step, snap it.
   - `kind = HS.placeKind(i)`.
   - Budgets: count < `caps.items` (`cap`); parts + `HS.itemPartCount` ≤ `caps.parts` (`parts`).
2. **Support / height by kind.**
   - `floor` / `rug`:
     - down-ray from `(x, y+3, z)` hits a floor-type part (§1.4) within `|hitY − y| ≤ 0.15`, otherwise `floating`;
     - the server **sets `y = hitY`** (and rugs get +0.02);
     - all 4 footprint corners, inset 0.15, must also hit floor-type parts at the same level (±0.3), otherwise
       `outside` ("집 밖으로 나가요"); this also catches holes and stairs;
     - a hit on `Stair*`/`StepNosing` gives `stair` ("계단에는 놓을 수 없어요").
   - `small`:
     - the down-ray hits a horizontal part (normal.Y > 0.95) that is not a floor, with its top 0.4 ≤ above floor ≤ 7;
       it can be a template counter, desk, island or nightstand, or a placed item part;
     - then `s=true` and `y = top`, and the 4 inset corners must be supported within 0.1;
     - with no surface, it may still stand on the floor if the item has a Stand (`s=false`); otherwise `noSurface`
       ("테이블·선반 위에 올려요").
   - `wall`:
     - the back face (+Z local) must touch a wall-type part: a ray from the item centre toward the back, length
       `d/2 + 0.6`, hits a wall part whose normal is anti-parallel to the item's back axis (dot < −0.95);
     - the server snaps the item flush (`gap 0.05`);
     - 3 extra rays at the back corners (inset 0.2) must hit the same plane ±0.1; otherwise `noWall` ("벽에 붙여서 걸어요");
     - curtains (`cu_*`) may also back onto `WindowGlass`/`WindowFrame`/`Glazing*`/`Sash` parts;
     - `y` is free, but `y ≥ floor + 0.3` and `y1 ≤ ceiling`.
3. **Height.** `y1 ≤ ceilingBottom − 0.05` at that level (`ceiling` "천장에 닿아요") and
   `y1 − floorY ≤ HS.DECOR.MAX_HEIGHT`.
4. **Shell walls.** `GetPartBoundsInBox(itemOBB shrunk 0.12 and raised 0.08)` with Include `{Shell}` returns no
   wall-type part; for wall kinds the box is shrunk an extra 0.15 on the back face. Failure: `wall` ("벽을 뚫을 수 없어요").
5. **Fixed solids.** The same box, Include `{Fixtures, Props, Interact?(no), ExitDoor}`. Any part with `CanCollide`
   or a name in the solid list (cabinet, counter, fridge, wardrobe, tub, toilet, vanity, island, piano, ...) fails with
   `fixture` ("붙박이 가구·설비와 겹쳐요"). A `small` item is exempt for the part it stands on.
6. **Slot envelopes** (R2): the OBB overlaps any slot envelope by more than 2 % of the smaller footprint, with heights
   intersecting. Rugs are tested only against `rug` slots. Failure: `slot` ("기본 가구 자리예요 · 🛠️ 인테리어에서 바꿀
   수 있어요").
7. **Other placed items.** Exact OBB SAT overlap fraction > `HS.DECOR.OVERLAP_MAX` (0.35), with heights intersecting
   by more than 0.15, fails with `overlap` ("다른 가구와 겹쳐요").
   - Rug vs rug > 0.10 fails (`rug`, "러그끼리 겹쳐요").
   - Wall vs wall items use the wall plane (2D overlap > 0).
   - A stacked item sitting on item U is allowed over U.
8. **Keep zones** (precomputed per instance, unit frame):
   - door swing and doorway: for every `Door*` model / `ExitDoor`, box = leaf width + 0.4 × 7 × 3.0 on both sides
     (`door`, "문이 열리는 자리예요");
   - entry path: Spawn box 3 × 7 × 3 (`entry`, "현관 통로는 비워 둬야 해요");
   - fixture fronts: for each HomeInteract part except window and mailbox, a 1.6-deep box in front of the part's
     outward face, or around it when the face is ambiguous (`interact`, "%s 앞은 비워 둬야 써요" with the interact
     label, e.g. "냉장고");
   - stairs and rails (`stair`).
   - Rugs ignore door and entry zones except the door swing (rug height is 0.1, so doors still clear) and ignore
     interact zones.
9. **People.** No occupant HRP inside the OBB inflated 0.5 (`person`).
10. **Path check (P1, `Config.PATH_CHECK`).**
    - Raster the level at 0.5 studs: blocked = fixed solids + slot envelopes + placed non-rug items with
      `y0 < floor+3` + the candidate.
    - Erode by the character half-width (1.0 stud).
    - BFS from the Spawn cell on level 1. For the upper level, start from the top-stair cell.
    - Every door cell and every interact "front" cell on that level must stay reachable; otherwise `path`
      ("이렇게 두면 %s(으)로 가는 길이 막혀요").
    - Cost: under 7k cells, well under 1 ms. Cache the static raster per instance.
11. **Lights** (info only, never a failure): if the item has `spec.lights` and the home's placed real lights ≥
    `caps.lights`, the result carries `warn="lightCap"` ("조명이 많아서 빛은 %d개까지만 켜져요"). The piece still glows
    Neon without a light.

The server returns `fixed = {x, y, z, r, s, m}` (snapped values) and stores those.

### 4.7 Money rules

- **Buy** (`src="buy"` or no storage stock): `price = G.FURNITURE[i].price`.
  `Host.spend(p, price, "가구 구매 · " .. name)` (bank first). On failure: `insufficient`, "통장 잔액이 부족해요 (필요
  190,000원 · 통장 120,000원 · 현금 30,000원)".
- **From 창고**: `storage[i] -= 1`, free.
- **Fresh undo.** A uid bought this visit less than `FRESH_SECONDS` (600) ago and removed (any `how`) gets a 100 %
  refund to the bank ("구매 취소 · 전액 환불") and does not go to 창고.
- **Store** (`how="store"`): `storage[i] += 1` if the total is under 200; otherwise `storageFull` ("창고가 꽉 찼어요
  (최대 200개). 안 쓰는 가구를 팔아 주세요").
- **Sell** (`how="sell"`): `Host.refund(p, floor(price × 0.5), "가구 판매 · " .. name)`.
- **Restore** within `TRASH_SECONDS`:
  - store → take it back from 창고 if still there, else buy;
  - sell → pay back the amount received;
  - refund → pay the full price again;
  - then re-validate placement.
- **Colour change and move** are free.
- Every money change: `Host.changed(p)` (pushes `cash`/`bank`/`housing` to the phone and HUD) + `Host.saveSoon(p)`.

### 4.8 Builder (server)

- `Builder.buildAll(model)`:
  - waits for `Host.instOfModel(model)` and the owner's profile;
  - creates or clears `DecorPlus`;
  - for each record, `Builder.build(inst, rec)`;
  - assigns lights in uid order up to `caps.lights` (attr `LightOn=true`);
  - spreads the work over frames at 40 items per frame.
- `Builder.build(inst, rec)`:
  - `spec = HS.itemSpec(rec.i, rec.v, rec.s)`, then `Spec.build(spec, F * CFrame.new(x,y,z) * Angles(0, r, 0),
    DecorPlus, "Item_"..u, { maxLights = budgetLeft, seat = true, rename = true })`;
  - adds the `DPHit` box, the attributes and the tag;
  - prompts:
    - seating gets `앉기`: the server checks `Housing.where(p) == inst`, then `seat:Sit(hum)`;
    - lamps get `불 켜기/끄기`, which toggles `On`, the light and the Neon colour;
    - prompts use `MaxActivationDistance 7`, `RequiresLineOfSight false`, `Exclusivity OnePerButton`, and the
      `HoldDuration` of the 0 kind.
- Move uses `PivotTo` when `s` and `v` are unchanged; colour or stacking changes rebuild.
- Removal destroys the model, then reassigns any freed light.
- World index invalidation: the item list changes `version`, so the path raster is recomputed lazily.

### 4.9 Client editor

- **Entry.**
  - Shown when `InHome == UserId`, `HomeRole == "owner"`, the home model has been found, `Interior` is closed and the
    server snapshot reports ok.
  - A pill `✨ 자유 배치` (`K.Button`, tonal, 56 px tall) sits just above the HomeBar: it reads
    `PlayerGui.GwangalliHome.HomeBar.AbsolutePosition` each `Layout.changed`, else uses `Layout.rect("bottomCenter")`
    minus 64.
  - Key `K`; gamepad `DPadUp` while at home.
  - A first-time coachmark: "가구를 원하는 곳에 직접 놓아 보세요! (K)".
- **Open.**
  - `Net.request("open")`; close the slot Interior first.
  - `setControls(false)` via `PlayerModule:GetControls():Disable()`, plus our gui `HideGwangalliHUD=true`.
  - Camera: Scriptable dollhouse orbit around the current room: 55° pitch, distance fitted to the room, FOV 50.
- **Cutaway** (option "벽 가리기", default on):
  - per frame (throttled to 10 Hz), set `LocalTransparencyModifier = 1` on the `Shell` Ceiling, on Shell wall parts
    whose outward normal points at the camera and lie between the camera and the room centre, and on everything above
    the selected level's ceiling;
  - always restore on close.
  - These are runtime-created home parts, not map parts.
- **Ghost.**
  - `Spec.build(..., {ghost=true})` gives Transparency 0.45, CanCollide/Query/Touch false and no lights, in
    `Workspace.GwDecorPlusLocal`.
  - Tint: green `rgb(90,220,140)` or red `rgb(235,80,80)` through a Highlight, falling back to a SelectionBox.
  - A flat footprint plate (Neon, 0.04 thick) shows the exact OBB, with grid lines when snap is on.
  - The status line shows the Rules reason.
  - Client raycast: Include = home model minus `DecorPlus` DPHit parts (selection uses DPHit only).
  - By kind: floor/rug snap to the hit floor; small to the hit surface top; wall to the hit wall plane with the item's
    yaw set to the wall normal.
  - Grid snap applies in the unit frame (0.5/1/off); yaw snaps by step (15/45/90/free).
  - The client recomputes `Rules.check` with the client world adapter at most every 50 ms.
- **Input map.**

  | action | PC | mobile | gamepad |
  |---|---|---|---|
  | aim ghost / pick | mouse move / click | drag one finger on the world | left stick moves a centre cursor |
  | place | LMB / Enter | ✓ 놓기 button (bottom bar) | A |
  | rotate | R / wheel+Shift (step), Q/E ±step | ⟲ ⟳ buttons, two-finger twist (TouchRotate) | LB / RB |
  | cancel / back | Esc / RMB | ✕ | B |
  | orbit camera | RMB drag / ← → | two-finger drag | right stick |
  | zoom | wheel | pinch | LT / RT |
  | pan | WASD / MMB drag | — (room chips) | D-pad |
  | select placed item | click it | tap it | A on the cursor |
  | move selected | drag it / M | long-press + drag | X |
  | delete (창고로) | Del | 📦 button | Y |
  | duplicate | Ctrl+D | ⧉ button | — |
  | undo / redo | Ctrl+Z / Ctrl+Y | ↶ ↷ in the top bar | View / Menu combos off (top-bar buttons) |
  | catalog toggle | Tab | sheet handle | Y (when nothing is selected) |

- **Undo/redo.** Entries `{op="place", uid}`, `{op="move", uid, from, to}`, `{op="color", uid, from, to}`,
  `{op="remove", uids, how}`. Inverse ops:
  - place → `remove{how="sell"}`, which is fresh, so 100 %;
  - move → move back;
  - colour → old colour;
  - remove → `restore`, then remap uids from `map`.
- **Cart** (스타일 세트, P1): choosing a set fills `cart`. After each successful place, the ghost auto-loads the next
  cart item and the sheet shows "세트 3/6 · 남은 금액 1,240,000원". Each piece is still paid on placement.

### 4.10 UI screens (Korean copy; all via GwangalliUI, touch targets ≥ 56 px)

1. **Entry pill:** `✨ 자유 배치` · tooltip `가구를 원하는 곳에 놓아요 (K)`.
2. **Top bar** (Layout top area):
   - `✕` (닫기) · title `자유 배치 · 광안동 풀옵션 원룸`;
   - room chips `전체 · 방 · 주방 · 거실 · 침실 · 서재 · 복층 · 테라스` + level toggle `1층 / 복층`;
   - stat chips `⭐ 인테리어 128` · `💳 1,250,000원` · `🛋️ 23/50` · `💡 2/3`;
   - `↶ ↷` · `📸` · `⚙️`.
3. **Catalog sheet** (`sheetRight`: portrait = bottom sheet, landscape = right panel):
   - tabs from `HS.CATALOG_TABS` + `📦 창고` + `🛍️ 추천 세트`;
   - `SearchBar` "가구 이름으로 찾기 (예: 소파, ㅅㅍ)";
   - filter chips `전체 · 이케아풍 · 모던 · 럭셔리 · 코지 · 트렌디` and a sort `가격 낮은 순 / 높은 순 / 인테리어 점수 순`;
   - card: 3D thumbnail, `벨벳 체스터필드 소파`, `3,800,000원` or `창고 2개 · 무료`, `⭐+12`, style pill, colour dots;
     tap → pick + ghost.
4. **Placement bar** (bottom, over the ghost):
   - `⟲` `⟳` `🎨 색상` `✓ 놓기 · 190,000원` (or `✓ 창고에서 꺼내기`) `✕`;
   - status line `✅ 여기에 놓을 수 있어요` / `❌ 다른 가구와 겹쳐요`;
   - `🔁 연속 배치` toggle.
5. **Colour popover:** swatches from `HS.colorway(id, cw)` with names (`그레이 · 네이비 · 카멜 · 올리브 · 크림`).
6. **Selection bar** (tap a placed item):
   - header `모던 카우치 (카멜 가죽) · 모던 · ⭐+6`;
   - buttons `✥ 옮기기` `⟲ 돌리기` `🎨 색 바꾸기` `⧉ 하나 더` `📦 창고에 넣기` `💰 팔기 +445,000원`
     (or `↩ 구매 취소 +890,000원` while fresh).
   - Sell asks `K.confirm`: "정말 팔까요? 산 값의 50%를 돌려받아요".
7. **창고 tab:** a grid of stored pieces `×n`, `꺼내 놓기` (picks a ghost), `팔기 (50%)`.
8. **추천 세트 tab** (P1). Cards with items count + total:
   - `🌊 광안리 오션 미니멀`
   - `🪵 따뜻한 우드 원룸`
   - `🎮 트렌디 게이밍 룸`
   - `🏨 호텔 스위트 럭셔리`
   - `🌿 플랜테리어 정글`
   - `☕ 홈카페 키친`

   Button `세트 담고 하나씩 놓기`.
9. **Settings (⚙️):** `격자 0.5 / 1 / 끔`, `회전 15° / 45° / 90° / 자유`, `벽 가리기 켜기/끄기`, `도움말`.
10. **Help coachmarks** (first open): "① 카탈로그에서 가구를 골라요 → ② 놓을 곳을 눌러요 → ③ ✓ 놓기! 놓은 가구를
    누르면 옮기거나 색을 바꿀 수 있어요".
11. **Guest overlay** (Visit): pill `❤️ 좋아요 12` (tap → like, once a day) and `🔍 구경` (tap items: name · style ·
    `이 가구는 TV·가전 탭에 있어요`). After liking: `❤️ 좋아요를 보냈어요!`.
12. **Owner toasts:**
    - `❤️ 민지님이 우리 집에 좋아요를 눌렀어요 (총 13개)`
    - `🛋️ 소파를 놓았어요 · -190,000원`
    - `📦 창고에 넣었어요`
    - `↩ 구매를 취소했어요 · +190,000원`
    - `🎉 첫 가구 배치! 행복 +3`
13. **Photo mode** (P1): `📸 집 사진` (UI hidden, orbit, filters `기본 · 따뜻하게 · 필름 · 야경`, `찰칵`) → toast
    `📸 집 사진을 저장했어요 · SNS 업로드!`.
14. **Not-saved warning** when `persistent=false`: banner `⚠️ 지금은 저장이 안 되는 세션이에요 (테스트 서버)`.

### 4.11 Player flows

1. **First home.**
   - The player rents a goshiwon (phone 부동산 → 계약) and gets 🏠 집으로 가기.
   - HomeState `enter` arrives; our client sees `InHome == me` and `role == owner`.
   - The `✨ 자유 배치` pill fades in with a one-time coachmark.
2. **Buy and place.**
   - `K` or the pill opens the editor (Interior closed, controls off, dollhouse camera on the current room).
   - Catalog tab `식물` → `몬스테라 화분 30,000원` gives a ghost.
   - The player drags it to a corner, it snaps to 0.5 and turns green. ✓ 놓기 sends
     `place {rid, i="plant_ikea", v=1, x, y, z, r, s=false, src="buy"}`.
   - The server validates, `ctx.spend` takes 30,000원 from the bank, `HS.addItem` stores the record, the model is built
     in DecorPlus, and `Event items` reaches the occupants.
   - The reply carries uid and balance. The client shows a toast, pushes undo, and with 연속 배치 on keeps the ghost.
   - Milestone `dp_first`: 행복 +3.
3. **Place from 창고.**
   - The 창고 tab lists `원목 의자 ×1` → 꺼내 놓기 → `place {src="storage"}`.
   - The server takes it from storage; the price is 0.
4. **Move / rotate / recolour.**
   - Tap the sofa to open the selection bar.
   - `✥ 옮기기` re-ghosts at the current pose; drag; ✓ → `move`. The server re-validates with ignore=uid and pivots
     the model.
   - `🎨` → swatch → `color` (free, rebuild).
5. **Remove.**
   - `📦 창고에 넣기` → `remove {how="store"}` → 창고 +1.
   - `💰 팔기` → confirm → `remove {how="sell"}` → +50 % to the bank.
   - A piece bought less than 10 min ago always refunds 100 %.
   - `↶` within 10 min → `restore`.
6. **Theme quick tab** (P1): `🎨 벽지·바닥·조명` lists the rooms and the HS options. A tap sends the existing
   `HomeAction "setTheme" {room, kind, id}`. We listen to `HomeState "interiorResult"`/`"themes"` for the result toast.
   The slot UI is not opened.
7. **Style set** (P1): `🏨 호텔 스위트 럭셔리` → `세트 담기` → cart 6 → place each one (each paid, each validated);
   finishing the cart grants milestone `dp_set1`.
8. **Insufficient money:** the server returns `insufficient`. The ghost turns red and shakes, a toast shows the exact
   amounts, and `💳 통장` opens the phone bank app (`LocalPlayer.GwangalliPhoneOpen:Fire("bank")` when present).
9. **Caps:**
   - `cap`: "원룸에는 가구를 최대 50개까지 놓을 수 있어요 · 더 넓은 집으로 이사하면 늘어요";
   - `parts`: "집이 너무 복잡해졌어요 (모바일 최적화) · 작은 소품을 조금 정리해 주세요".
10. **Guest visit.**
    - A friend rings and is admitted (Housing). The items are already replicated through the persistent model.
    - The friend's Visit overlay shows `❤️ 좋아요` and `🔍 구경`. Like → `like {ownerId}` → owner `u.likes += 1`, the
      owner gets the toast and 인기도 +0.5 (once per guest per 20 h). Milestones `dp_like1/10/50`.
11. **Owner leaves or the instance is destroyed:** the editor closes with "집 밖으로 나와서 꾸미기를 마쳤어요". On the
    next enter, Housing builds a new instance and our watcher rebuilds every item from the profile.
12. **Moving house:** Life calls `G.moveOutFurniture`. The HS wrapper moves every item to 창고 (selling the overflow
    over 200 at 50 %). Housing's `onHomeChanged` destroys the instance. In the new home the player places pieces from 창고.
13. **Respawn / KO / arrest:** `CharacterAdded` closes the editor and restores camera, controls and cutaway.
14. **Slot mode switch:** the 🛠️ 인테리어 button or `B` opens the slot Interior. We detect `GwangalliInterior.Enabled`
    and close ours. In our selection bar, an info row for slot pieces reads "기본 옵션 가구는 🛠️ 인테리어에서 바꿔요";
    tapping it opens their Interior via the bindable.

### 4.12 Social and rewards (P1)

- Likes: `u.likes` (persisted, visible in `G.housingView().likes` for the phone).
- Per-guest dedupe: 20 h, in server memory.
- Owner reward per like: `{happiness=1, popularity=0.5}`, capped at 10 a day per owner (in memory).
- Milestones (`d.milestones["dp_*"]`, once each, `ctx.addStats` + toast):

  | id | condition | reward |
  |---|---|---|
  | dp_first | first free-placed piece | 행복 +3 |
  | dp_items10 / 30 | 10 / 30 pieces | 행복 +3 / +5 |
  | dp_decor50 / 100 / 200 | `G.homeDecor` reaches the value | 인기도 +1 / +2 / +3 |
  | dp_like1 / 10 / 50 | likes | 인기도 +1 / +2 / +4 |
  | dp_set1 | finished a 스타일 세트 | 행복 +5 |
  | dp_photo1 | first 집 사진 | 인기도 +0.5 |

- Comfort: decor automatically raises sleep happiness through `G.homeComfort` (+1 per 6 decor, max +10). The editor
  shows `편안함 +n` next to ⭐.

### 4.13 Config (Config.luau)

```lua
CAPS = { goshiwon = { items = 25, parts = 300, lights = 2 }, oneroom = { items = 50, parts = 600, lights = 3 },
         officetel = { items = 80, parts = 1000, lights = 3 }, apartment = { items = 130, parts = 1600, lights = 4 },
         penthouse = { items = 200, parts = 2400, lights = 4 }, default = { items = 50, parts = 600, lights = 3 } }
GRID_STEPS = { 0.5, 1, 0 }   ROT_STEPS = { 15, 45, 90, 0 }   GRID_DEFAULT = 0.5   ROT_DEFAULT = 45
OVERLAP_MAX = 0.35   RUG_OVERLAP_MAX = 0.10   SLOT_OVERLAP_MAX = 0.02   WALL_GAP = 0.05
KEEP = { doorDepth = 3.0, entry = 3.0, interactDepth = 1.6 }   PATH_CHECK = true   PATH_CELL = 0.5   PATH_RADIUS = 1.0
FRESH_SECONDS = 600   TRASH_SECONDS = 600   SELL_RATE = 0.5   SAVE_SOON = 15
RATE = { tokens = 10, burst = 20 }   COOLDOWN = { open = 1, place = 0.12, move = 0.08, color = 0.1, remove = 0.12,
           restore = 0.12, sellStored = 0.3, like = 1, photo = 2 }   BATCH_MAX = 40   RID_CACHE = 32
LIKE_DEDUPE_HOURS = 20   LIKE_OWNER_DAILY = 10
KEY_OPEN = Enum.KeyCode.K   DISPLAY_ORDER = 16   PREVIEW_CACHE = 32
DORMANT_IF_HOST_DECOR = true
SETS = { ... }   -- 스타일 세트: { id, name, icon, desc, items = { {i, v} } } (ids validated against G.FURNITURE at boot)
```

### 4.14 Test plan

- **Offline Luau** (mock runtime copy in `feat/decor/`):
  - Geometry: exact bounds versus HS for rotated parts, SAT overlap, snapping.
  - Rules with a fake world built from `templates.json`: oneroom corners, walls, slots, doors, the loft level.
  - Records with a fake profile: add, remove, fresh refund, store cap, restore remap.
  - Sanitizer round trip: build items → `G.sanitizeHousing` → same items.
  - Money via a fake ctx: no spend on an invalid placement, a single spend on a rid replay.
- **Temp studio** (one run at a time under `flock`, `timeout 1500`):
  1. Boot.
  2. In the server context, give a home: `G.rentHome(Profiles.get(p), "oneroom", os.time())` + `Housing.enter(p, "phone")`,
     plus `GwangalliHomesAPI:Invoke("grant", p.UserId, 5e6)` in test mode.
  3. Call our Actions directly: open, place 10 items of each kind, move, colour, remove, restore.
  4. Check the `DecorPlus` children, `Housing.instanceOf(p)`, `HS.decorItems`, `G.homeDecor`, and `GwangalliHomesAPI
     status`.
  5. Screenshots of the editor UI (portrait and landscape viewports) and of the dollhouse cutaway.
  6. `Housing.leave` → instance destroyed → `enter` → items rebuilt.
- **Exploit tests:** NaN / inf / huge numbers, foreign uid, a guest calling place, 100 requests/s, an id not in
  G.FURNITURE, `src="storage"` without stock.

### 4.15 Open questions and future (P2)

- **Presets** (배치 저장 3칸/집): an own DataStore `GwangalliDecorPlus_v1` key `u_<id>`
  `{v=1, presets={[listingId]={{name, t, items={{i,v,x,y,z,r,s}}}}}}`. Loading a preset rearranges owned pieces and
  offers to buy the missing ones (price summary).
- **Extra catalog:** for example, wrapping system B's 67 `Furniture.build` models with their GwB tags stripped. It
  needs its own item list in that store, because the profile sanitizer would drop unknown ids.
- **함께 꾸미기:** the owner grants an online guest edit rights; the owner pays, or the guest pays as a gift.
- **Server 랭킹 "이번 주 인테리어 왕"** with an NPC 집 꾸미기 contest (in-memory per server).
- **Tenant restriction** (`LC.DECOR.finishTenantAllowed=false`, 원상복구) for themes: today the host allows it; keep
  host behaviour.

---------------------------------------------------------------------------------------------------

## Appendix A — reason codes → Korean (Text.luau)

| code | 메시지 |
|---|---|
| booting | 인테리어 기능을 준비하고 있어요. 잠시 후 다시 시도해 주세요 |
| notHome | 내 집 안에서만 꾸밀 수 있어요 |
| staged | 둘러보기 중에는 꾸밀 수 없어요 |
| noProfile | 프로필을 불러오는 중이에요 |
| unknown | 없는 가구예요 |
| cap | %s에는 가구를 최대 %d개까지 놓을 수 있어요 · 더 넓은 집으로 이사하면 늘어요 |
| parts | 집이 너무 복잡해졌어요 (모바일 최적화) · 작은 소품을 조금 정리해 주세요 |
| outside | 집 밖으로 나가요 |
| floating | 바닥이나 받침 위에 놓아 주세요 |
| stair | 계단에는 놓을 수 없어요 |
| noSurface | 테이블·선반 위에 올려요 |
| noWall | 벽에 붙여서 걸어요 |
| ceiling | 천장에 닿아요 |
| wall | 벽을 뚫을 수 없어요 |
| fixture | 붙박이 가구·설비와 겹쳐요 |
| slot | 기본 가구 자리예요 · 🛠️ 인테리어에서 바꿀 수 있어요 |
| overlap | 다른 가구와 겹쳐요 |
| rug | 러그끼리 겹쳐요 |
| door | 문이 열리는 자리예요 |
| entry | 현관 통로는 비워 둬야 해요 |
| interact | %s 앞은 비워 둬야 써요 |
| path | 이렇게 두면 %s(으)로 가는 길이 막혀요 |
| person | 사람이 서 있는 자리예요 |
| insufficient | 통장 잔액이 부족해요 (필요 %s · 통장 %s · 현금 %s) |
| noStock | 창고에 없는 가구예요 |
| storageFull | 창고가 꽉 찼어요 (최대 %d개) · 안 쓰는 가구를 팔아 주세요 |
| expired | 되돌릴 수 있는 시간이 지났어요 |
| same | 이미 그 색이에요 |
| rate | 잠시 후 다시 해 주세요 |
| liked | 오늘은 이미 좋아요를 눌렀어요 |
| lightCap (warn) | 조명이 많아서 빛은 %d개까지만 켜져요 |

## Appendix B — key code references (quick index)

- Housing (life game):
  - `bld/src/ServerScriptService/GwangalliGameplay/Housing.ModuleScript.luau`: header 1-29, Core.scanUnit 191,
    buildSpec 282, collectThemes 361, roomBox 504, roomAt 541, buildInstance 1370 (attrs 1462, parent 1469),
    destroyInstance 1298, where 1779, enter 1799, leave 1868, sit 2145, applyTv 1133, placeFurniture 2683,
    setTheme 2959, onAction drop rule 3303, remotes 3695, GwangalliHomesAPI 3705.
- HomesShared:
  - `bld/src/ReplicatedStorage/GwangalliHomesShared.ModuleScript.luau`: header 1-24, unitOf 150, DECOR 1355,
    placeKind 1393, CATALOG_TABS 1403, colourways 1460-1525, itemSpec 1575, specBounds 1612, decorBox 1658,
    checkOverlap 1722, addItem 1760, removeItem 1784, sanitizeItems 1816, extend 2119 (actions 2185, sanitize 2210,
    moveOut 2251, homeDecor 2288, housingView 2295).
- GameplayShared:
  - `bld/src/ReplicatedStorage/GwangalliGameplayShared.ModuleScript.luau`: LISTINGS 1160, HOME contract 1507-1546,
    HOME_TIERS 1549, homeSlotPosition 1643, slotGeometry 1664, FURNITURE 1742-1787, ledger 710, spend 754,
    sanitizeHousing 2395, placeFurniture 2523, sellStored 2601, moveOutFurniture 2617, homeDecor 2666,
    homeComfort 2715, HS hook 3591.
- Bootstrap:
  - `bld/src/ServerScriptService/GwangalliGameplay.Script.luau`: folder-by-class 41-48, ctx.changed 262, ledger 305,
    spend 337, addStats 355, GwangalliGameplayAPI 457-475, FEATURE_MODULES 477.
- Profiles:
  - `bld/src/ServerScriptService/GwangalliGameplay/Profiles.ModuleScript.luau`: sanitize 149 (milestones 297,
    passthrough 304-310), get 460, markDirty 486, persistent 587, saveSoon 601.
- ctx holder:
  - `bld/src/ServerScriptService/GwangalliGameplay/VenueLife.ModuleScript.luau:966` (`VenueLife.ctx = ctx`).
- Client:
  - `bld/src/StarterPlayer/StarterPlayerScripts/GwangalliHome.LocalScript.luau`: guis 215-219 (12/15/31),
    HomeBar 501-532, bindables 1960-2003, HomeState handler 2073, keys 2190-2200.
  - `.../GwangalliHome/Interior.ModuleScript.luau`: ScreenGui 1375-1390, close 1731.
- Neighbour client:
  - `src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/Homes.luau:121-146` (DecorPlus / GwDecorItem
    keep zones).

---------------------------------------------------------------------------------------------------

Files:
- /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor/research.md (this doc)
- /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor/templates.json (per-tier template survey: rooms, slots, interacts, doors, props)
- /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor/survey.py (place.bin template survey script)
- /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor/cat/stat.luau (Luau CLI catalog stats over copies of G/HS in the same folder)
