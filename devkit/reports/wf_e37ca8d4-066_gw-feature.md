# gw-feature (wf_e37ca8d4-066)

- status: completed
- failed agents (never finished, usually the usage limit): build:club, fix:club, review:club:correctness, review:club:experience, test:club

## research:club

# GwangalliClubPlus — research + design (CLUB OCEAN 광안 AAA show add-on)

Scope: an add-on the owner drops into the place, which makes CLUB OCEAN 광안 feel like a real top-tier Korean club night. It adds:
- 전광판 (LED wall) animations with nicknames, for bottle orders and paid 후원.
- Ranking boards.
- Its own laser show, running in sync with the house show.
- A richer bottle parade, plus a 테이블 선물 parade.
- A 합석 production on top of the existing 합석 이벤트.

Everything listens to the existing club contract. Nothing in the place is edited.

Paths used below:
- `P` = place dump: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/src/<Service>/<Path>.<Class>.luau`
- `Z` = v7 studio add-on zip, which the v7 studio applies on top of the place: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7all/gen/addons/zip/<Service>/<Path>.luau`
- Line numbers in `Z` files count the 1-line `-- Script @ ...` header that the dump added.

---------------------------------------------------------------------------------------------------

## 0. TL;DR

* **Order events.** Listen to the JSON folder attributes on `ReplicatedStorage.GwangalliClubShow`. Only the server writes them.
  * `Show`: one write per bottle show. It carries the exact item, the owner's UserId, the filtered name, the table, `at` / `arriveAt` / `endAt` and the staff path.
  * `Tables`: table life. An `at` change with no matching `Show` means an order was served without a show.
  * `Booking`: the 합석 event.
  * Price = `GwangalliClubShowShared.item(itemId).price`.
* **Ranking.** A "오늘 밤 큰손 랭킹" board already ships in the v7 zip as GwangalliBuildings/ClubRanking. It has:
  * ODS `GwB_ClubSpend_<night>`.
  * Folder `ReplicatedStorage.GwangalliClubRanking` with `Top` / `Zones` attributes and an `Fx` RemoteEvent.
  * A board on the main room's south wall, a crown over #1, and top-of-screen cards.
  * Do NOT rebuild it. Add the missing boards (후원왕, 이번 주, 명예의 전당, 인기 테이블) elsewhere, and reuse its `Top` / `Fx` data.
* **LED wall.**
  * Today it is a physical 32x11 pixel grid driven by ClubLights, which can only draw an ASCII 5x7 font.
  * During shows and 합석, GwangalliClubShow adds a Korean SurfaceGui overlay on its own `ClubShowLED` part at the `Show_LEDWall` anchor (ZOffset 1).
  * Our canvas is a local transparent part placed 0.2 stud in front of `Show_LEDWall`, with its SurfaceGui in PlayerGui and `Adornee` set.
  * We own the first ~5 s of every show (the nickname intro), then shrink to a lower-third band so their title stays readable.
  * Our own paid cues use free windows. We never cover ClubLights' countdown / DROP.
* **Lasers.** ClubLights re-aims all 32 `ClubLaser` beams at 30 Hz, so we never touch them. Our laser rig is our own Beams in our local folder, driven by `ClubShared.Bus` (beat / section / drop) and `ClubShared.clock`.
* **Money.** Through `ServerStorage.GwangalliGameplayAPI`.
  * The handler that actually runs is the unified wallet, because GwangalliGameplay.Script overrides Life's club API. Its ops are `balance`, `spend(amount,label)`, `earn(amount,label)`, `addStats(delta,label)`.
  * Nothing assigns `ProcessReceipt` and there are no developer products; a future central handler owns ProcessReceipt. So we use in-game won only.
* **DJ.** No player DJ role exists: only the NPCs `DJ_009` and `MC_010`, and "Resident DJ" catalogue music. DJ mode is an optional phase 2.
* **All-ages.** The v7 zip's menu labels are already non-alcoholic in every build (스파클링 주스 / 프리미엄 음료), and the 합석 is framed as friends only. Our text has no alcohol words and no romance (no 고백 / 썸 / 커플).

---------------------------------------------------------------------------------------------------

## 1. Existing integration points (exact)

### 1.1 Which version is live

The v7 studio applies the `gen/addons.json` entries marked `upsert: true` over the place.

Club-related upserts:
- `ReplicatedStorage.GwangalliClubShowShared`
- `ServerScriptService.Club`
- `ServerScriptService.GwangalliClub.Show`
- `StarterPlayerScripts.GwangalliClubShow.{Show,Ui}`
- `GwangalliGameplay/Play/Journey/Club`
- `GwangalliGameplay/Bank`
- `GwangalliPhone/Apps/Bank`
- New modules `ServerScriptService.GwangalliBuildings.ClubRanking` and `StarterPlayerScripts.GwangalliBuildingsClient.ClubRanking`. They are wired in at `Z/ServerScriptService/GwangalliBuildings.luau:150,154,196` and `Z/StarterPlayer/StarterPlayerScripts/GwangalliBuildingsClient.luau:32,64`.

Differences from the place dump are small (diffed):
- Wristband time goes from 1440 to 2400 s.
- Menu labels and icons are non-alcoholic in every build (`Z/ReplicatedStorage/GwangalliClubShowShared.luau:144-146`, icon fallback ✨ at :167).
- Toast icons use ✨.

Design for the zip version, but code every lookup defensively: some live copies may not have ClubRanking.

### 1.2 GwangalliClubShowShared (ReplicatedStorage, pure data)

`P/ReplicatedStorage/GwangalliClubShowShared.ModuleScript.luau`

* **Contract header** :6-31:
  ```
  ReplicatedStorage.GwangalliClubShow (Folder, GwangalliClub.server)
    RemoteEvent ShowEvent    server -> client: (kind, payload)  kinds: "menu", "order", "booking", "toast"
    RemoteEvent ShowRequest  client -> server: (op, a, b)  ops: "order" (tableId, itemId), "booking" (tableId), "act" (action), "menu" (tableId)
    attributes (JSON strings, written by the server only): Show / Tables / Booking
  ServerStorage.GwangalliClubAPI (BindableFunction): openMenu / reserve / hasTable / ownsTable
  ServerStorage.ClubShowHook (BindableFunction, Club.server): hold / tableInfo / tables / reach / stamp / route
  Player attributes: ClubOceanWristband, ClubOceanWristbandUntil
  ```
* **Names** :36-49:
  * `Folder = "GwangalliClubShow"`, `Remote = {Event="ShowEvent", Request="ShowRequest"}`
  * `API_NAME = "GwangalliClubAPI"`, `HOOK_NAME = "ClubShowHook"`
  * `Tags = {Door="ClubDoor", Anchor="ClubShowAnchor"}`
  * `Attr = {Show, Tables, Booking, Wristband="ClubOceanWristband", WristbandUntil="ClubOceanWristbandUntil", GuestSeat="ClubGuestSeat", DoorFee="ClubDoorFee"}`
* **All-ages switch.** `ShowShared.allAges()` :62-88 reads the workspace attribute `GwangalliClubAllAges` and `GwangalliConfig.ClubShow.AllAges`.
* **Door** :95-108: weekday 30,000, weekend 50,000; WristbandSeconds 2400 in the zip. `kst` and `isWeekendNight` (06:00 cut) at :111-128.
* **Menu** :141-147 (zip :143-147). Tiers, prices and staff:

  | id | tier | price | staff | flags |
  |---|---|---|---|---|
  | `basic` | T1 | 90,000 | 1 | — |
  | `champagne` | T2 | 200,000 | 2 | parade |
  | `vodka` | T3 | 350,000 | 3 | parade, dj |
  | `gold` | T4 | 600,000 | 4 | parade, dj, booking |
  | `royal` | T5 | 1,200,000 | 5 | parade, dj, booking, confetti |

  Helpers `item(id)`, `label(item, aa)`, `icon(item, aa)` at :153-167.
* **Lines** :170-181: `thanksTitle(tableId, aa)` → "G2 테이블 감사합니다 ✨", plus `djLine(tableId, name)`, `bookingTitle(tableId)`, `cheersWord(aa)`.
* **Show timing** :186-200: `LeadIn 2.2, Speed 4.6, BasicSpeed 6.2, Gap 3.0, Hold 11, Spread 2.5, Stand 3.1, Outro 2.5, PropSeconds 480, OrderCooldownPlayer 20, OrderCooldownTable 25, MaxDistance 18, MaxQueue 3`.
* **Booking** :202-215: `MinTier 3, AutoTier 4, Min 2, Max 4, Speed 5.4, Gap 2.6, Intro 2.4, Present 4.5, Duration 150, Cooldown 240, DanceSeconds 45, MD "MD 태양"`.
* **Quality caps** `Q.{high,mid,low,saver}` :218-223: spark 36/24/12/6, confetti 140/90/45/20, spotLight.
* **Pure path helpers we reuse:** `polyline(pts)` :229, `sample(pts, cum, d)` :241, `lineup(front, dir, n, spread)` :266, `travel`, `showLength(total, staff, tier)` :285-291. Also `pickGuests(...)` :300 and `Lines` / `line(kind, tier, rnd, name)` :341-369.

### 1.3 GwangalliClub server (Script + context `C`)

`P/ServerScriptService/GwangalliClub.Script.luau`

* Creates the folder and remotes at :64-92 (folder parented last). Context `C` at :97-103.
* `C.publish(attr, value)` :165-172 calls `rfolder:SetAttribute(attr, HttpService:JSONEncode(value))`, so these are JSON folder attributes.
* `C.filteredName(plr)` :176-197 takes the DisplayName (≤20 chars) through `TextService:FilterStringAsync(raw, plr.UserId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()`, with "손님" on failure. **Every `name` in Show / Tables / Booking is already broadcast-filtered**, so it is safe for our LED.
* `C.charge` :279-306 is the money pattern to copy:
  * `gameplay("spend", plr, amount, label, "bank")` with an 8 s timeout.
  * Statuses: `paid | paid-late | noapi | free | declined | error | timeout`.
* `ServerStorage.GwangalliClubAPI` :350-376 offers only `openMenu`, `reserve`, `hasTable`, `ownsTable`. There is NO way to start a show for someone else's table.
* Request bucket of 6 tokens @ 1.5/s at :381-396; dispatch at :398-416; 0.5 s housekeeping loop at :429-441.
* The modules (`Show`, `BottleService`, `Booking`) are internal and only reachable through `C`. An add-on cannot call them, so it has to listen to the attributes.

### 1.4 What BottleService / Show / Booking publish (the listening contract)

**Tables** — `P/ServerScriptService/GwangalliClub/BottleService.ModuleScript.luau:24-31`
```
C.publish("Tables", { [tableId] = { owner = UserId, name = filteredName, tier, set, at, untilT } })
```
* `claim()` :57-71: once paid, the player owns the table; `at = 0` while the show waits; the claim holds 900 s.
* `setTable(plr, id, item, at)` :74-80: `at` = staff arrival time.
* Order flow `order()` :163-268:
  * Label `"CLUB OCEAN <label> (<tableId>)"` at :211; charge at :212.
  * `Show.start({player, item, tableId, onArrive})` at :233-246.
  * No show slot → `setTable(now+2)` plus the hook `stamp` at :248-252 (served without a show).
  * `addStats` at :154-157.
* Door booking `reserve()` :272-306 uses the basic set and goes through `Show.start`.
* Note: `publish()` drops the exact `item` (it only keeps `set`, which equals the item id) and keeps the table's BEST tier.

**Show** — `P/ServerScriptService/GwangalliClub/Show.ModuleScript.luau:54-75,86-113`
```
rec = { id = serial, tier, item, label, table, owner, name, staff, path = ClubShared.encodePath(pts), y, total,
        dj, confetti, booking, aa, at, arriveAt, endAt, serve = {x,y,z} }
begin(): rec.at = now + 0.4; endAt = at + showLength; arriveAt = arrival(rec)
         C.publish("Show", rec)        -- :95  ONE write per show (queued shows publish when they begin)
         hook("hold", endAt-now+4)     -- :96  house parade waits
         hook("markBusy", table, endAt)-- :98
         hook("stamp", table, arriveAt, owner) -- :100 (tier>=2) ClubLights sparkler bottles
         BottleService.setTable(...)   -- :103 Tables.at = arriveAt
Show.init: publish("Show", {id = 0})   -- :175
```
Inside `begin`, `Show` is written first, then `Tables`. `id` restarts at 1 on each server.

**Booking** — `P/ServerScriptService/GwangalliClub/Booking.ModuleScript.luau:190-211`
```
{ id, table, owner, name, md, at, path, y, total, serve, centre, arriveAt, seatedAt, endAt,
  guests = { { id, name, g, tier (1..5 affinity tier), seat = "x,y,z,yaw"?, lines = { arrive, talk = {..}, laugh, dance, bye } } },
  act = { kind = ""|"cheers"|"dance"|"number"|"bye", at, n, untilT?, results?, lines? }, rev, aa, flags? }
```
* `{id = 0}` when there is no event (:26-32).
* `start()` :87-222: hold at :212; social `joint` table/club at arrival, :215-220.
* `act()` :249-317: cheers / dance / number / bye; owner only; only from seatedAt - 1; 2.5 s cooldown.

### 1.5 Club.server (ServerScriptService.Club) — hook + legacy

`P/ServerScriptService/Club.Script.luau`

* Header :1-46 covers ShowEpoch, the paid door, ClubShowHook, legacy tables/parades and the life-game hooks.
* `ShowEpoch` = `math.floor(serverNow())` at server start, written on every `ClubRuntime` model (:295, :314).
* LED banner attributes on ClubRuntime :302-310: `WallMsg`, `WallMsgKind`, `WallMsgAt`, `WallMsgFor`, `WallMsgSerial`. `setWall` :351-362 and `queueWall` :366-376 are ASCII only (via `ledName` :168-179).
* House parade `startParade` :518-535 writes `ParadePath`, `ParadeTable`, `ParadeAt` on ClubRuntime; schedule loop at :541-567.
* `stampBottles(rec, at, by)` :1049-1053 writes the table Model attributes `BottleAt` and `BottleBy`; ClubLights then builds sparkler bottles.
* **ServerStorage.ClubShowHook** :1452-1539. Methods we will call (server only):
  ```
  Invoke("hold", seconds)                       -> true   (house parade stays busy `seconds` more; clamp 0..600)
  Invoke("tableInfo", tableId)                  -> { id, kind, label, serve: Vector3, centre: Vector3, size: Vector3,
                                                     seats = { {cf, size, free, seat: Seat} }, busy }?
  Invoke("tables")                              -> { tableId... } (sorted)
  Invoke("reach", player, tableId, radius?)     -> bool  (living character within radius of ServePoint)
  Invoke("stamp", tableId, at, userId)          -> bool  (sparkler bottles land at server time `at`)
  Invoke("markBusy", tableId, untilServerTime)  -> bool
  Invoke("route")                               -> { Vector3 } ParadeRoute WP1..n
  Invoke("inClub", player)                      -> bool  (inside a non-"Near" ClubZone box)
  ```
* `ClubRemote` (ReplicatedStorage RemoteEvent) at :184-195; actions `order`, `doorPay`, `doorAsk`, `dance` at :1541-1559.
* `ServerStorage.ClubGameplayEvent` (BindableEvent) :197-208: `:Fire("vipTable"|"birthday"|"entry", player)`.
* Player attribute reply `ClubOrder = "<status>|<TableId>|<serverTime*10>"` at :627-632.

### 1.6 ClubShared (ReplicatedStorage) — show clock, Bus, paths

`P/ReplicatedStorage/ClubShared.ModuleScript.luau`

* `BPM = 126`, `BEATS_PER_BAR = 4`, `SHOW_BARS = 64` (~122 s per cycle) at :12-14.
* Tags :17-34: ClubVenue, ClubRuntime, ClubZone, ClubLight, ClubFloorTile, ClubLaser, ClubCO2, ClubConfetti, ClubSparkler, ClubHaze, ClubNPC, ClubFX, ClubMirrorRay, ClubShowBeam, ClubTable, ClubIDCheck. Attribute names :35-70; Names :71-81.
* **Client Bus** :112-128. The ModuleScript is cached per peer, so every LocalScript sees the same table.
  * Fields: `state ("Idle"|"Near"|"Inside"), zone, showRoom, section (intro|build|drop|breakdown|groove), live, bpm, energy, beatAt, beatSerial, dropAt, dropSerial, countdown, photoAt, playerDanceAt, night`.
  * ClubLights WRITES state / zone / showRoom / night on its zone tick, and section / live / bpm / energy / countdown / beatAt / beatSerial / dropAt / dropSerial every frame (`P/StarterPlayer/StarterPlayerScripts/ClubLights.LocalScript.luau:2595-2605, 2709-2711, 4501`).
  * **Inputs** ClubLights READS: `photoAt` (LED photo moment) and `playerDanceAt` (guests near the local player cheer).
* **Parades:** timing :202-211; `paradeAt` :215; **`paradePath(route, dest, maxLeg, ext, clear?)`** :238-308; `pathLength` :310; `encodePath` / `decodePath(s, y)` :319-342 ("x,z;x,z", ≤ 64 points); `PARADE_MAX_LEG 60`, `PARADE_EXTEND 48`.
* **Show script:**
  * `Sections` :372-379: intro 0-16, build 16-24, drop 24-40, breakdown 40-48, build 48-56, drop 56-64.
  * `Cues` :382-395: CO2 at bars 24/32/56/60, Confetti 24/56, Sparkler 40-48, ColdSpark, Flame, LowFog, MirrorBall.
  * `Palettes` :406-413; **`clock(serverTime, epoch, bpm?, out?)`** :422-446.
* `ledText` / `textColumns` :513-559: the pixel wall can only show A-Z, 0-9 and some punctuation.

### 1.7 ClubLights (client, 4560 lines) — what it drives

`P/StarterPlayer/StarterPlayerScripts/ClubLights.LocalScript.luau`

* Header :1-56. Two modes:
  * **LIVE:** follows ClubMusicShared (onsets, bpm, level); sections come from loudness; DROP comes from the detector.
  * **CLOCK:** the 126 BPM 64-bar clock from `ShowEpoch` (`currentEpoch()` :3951-3959).
* Quality tiers :114-220, with a touch variant and a saver mode at :300-336. Show writes are budgeted (low = 20 Hz × 48 writes).
* Registries by tag :556-919:
  * ClubLight `Kind` → colour items, fixtures (MovingHead, Beam), Kinetic, MirrorBall, Strobe, Blinder.
  * ClubFloorTile (48); ClubLaser beams :790-807.
  * CO2 / Confetti / Sparkler / Haze / FX / mirror-ball rays / pin spots.
* **LED wall** = 352 pixel parts on the main wall (Kind Wall, Row 0..10 × Col 0..31) plus 96 side pixels (`Screen = "Side"`).
  * Overlays :2611-2706, in priority order: photo → flash → DROP → countdown (8..1 over the last 2 bars of a build, :2547-2551) → `WallMsg` banner (vip/birthday/welcome) → NOW PLAYING.
  * Idle patterns: a "CLUB OCEAN" scroll in intro/breakdown; EQ / rings / logo flash in build/drop (`wallColour` :2808-2840).
* **Lasers** :3308-3428:
  * Active only in visible rooms (Main/Lobby/Corridor), and only when `fanK | drop | breakdown | build (bar≥2) | intro (bar≥12)` (:3356-3358).
  * Patterns: fan (after a drop), tunnel (intro, breakdown), sweep (build), and three drop variants.
  * Re-aimed at 30 Hz: `a1.Position`, `beam.Enabled` and `beam.Color` are written on every update.
  * → **Never write to ClubLaser beams; they would be overwritten within 33 ms.**
* `dropMoment` :2708-2717 fires CO2, confetti and a crowd jump. `computeFrame` writes the Bus at :2583-2607.

### 1.8 ClubMusic (server + client + shared) — tracks / BPM / DJ

* **Server** `P/ServerScriptService/ClubMusic.Script.luau:1-20`.
  * Playlist order: `MusicAssetId` override → DataStore cache `ClubOceanMusic_v1` → `AssetService:SearchAudio(Async)` (Monstercat / APM / EDM...).
  * Publishes `TrackId, TrackTitle, TrackArtist, TrackStart, TrackLength, TrackBpm, TrackSerial, NextTrackId, MusicState, MusicOwner` on ClubRuntime and on `ReplicatedStorage.ClubMusicState`.
  * There is no skip or request API. Override tracks are titled "CLUB OCEAN 광안" by "Resident DJ" (:493).
* **Shared** `P/ReplicatedStorage/ClubMusicShared.ModuleScript.luau:1-24,406-431`: client signal `Beat:Connect(fn(intensity, isDrop))`, plus `Drop:Connect`, `level()`, `bpm()` (126 fallback), `isLive()`, `nowPlaying()`.
* **DJ role: none for players.** A grep finds only the NPCs `People/DJ_009` and `People/MC_010`, the anchor `Show_DJ`, and the show's `djLine` bubble. ClubDance is a dance button bar, not a DJ.

### 1.9 GwangalliClubShow client (the existing show layer)

`P/StarterPlayer/StarterPlayerScripts/GwangalliClubShow.LocalScript.luau:100-144` reads ShowEvent and the three JSON attributes.

* **Core** `P/.../GwangalliClubShow/Core.ModuleScript.luau`:
  * Optional modules at :38-55: GwangalliUI (as `K`), GwangalliLayout, GwangalliQuality, ClubMusicShared, GwangalliNight.
  * `Core.anchor(name)` via the ClubShowAnchor tag :113-125; local folder `Workspace.GwangalliClubShowLocal` :207-218.
  * A single PreRender job driver :130-202; a rig pool via GwangalliNPCLooks + GwangalliAnim :400-460.
* **LED overlay** `Z/StarterPlayer/StarterPlayerScripts/GwangalliClubShow/Show.luau:55-129`:
  * Part `ClubShowLED`, same size as the anchor, at the `Show_LEDWall` CFrame (:64).
  * SurfaceGui on Front, PPS 9, LightInfluence 0, Brightness 2.6, MaxDistance 230, **ZOffset 1** (:74).
  * Look: purple→navy→teal gradient; GothamBlack white title with a magenta stroke and a gold/white/cyan shimmer; cyan sub-line.
  * `Show.led(title, sub, seconds)` :131-153.
* **Show choreography** `play(rec)` :473+:
  * At `rec.at` (tier ≥2): dim, and `Show.led(thanksTitle, "<name>님 · <label>", holdEnd-now+2)` (:537).
  * At `rec.at+1.5`: DJ bubble on `Show_DJ` and `Bus.playerDanceAt` (:544-546).
  * At arrival: cheer, and for royal, confetti/CO2 on the next beat (:551-555).
  * Staff rigs are named `ClubShowStaff<i>`; the middle one holds a lit name board "<name>님 감사합니다".
* **Booking client** `P/.../GwangalliClubShow/Booking.ModuleScript.luau:296-336`:
  * At `rec.at`: `Show.led(bookingTitle, "<md> · 새 친구 n명이 <name>님 테이블로!", until presentEnd)`, dim, spotlight to `Show_HallDoor`.
  * Rigs are named `ClubShowMD` / `ClubShowGuest<k>` (:430), under `Workspace.GwangalliClubShowLocal`.
* **합석 action card** `Z/.../GwangalliClubShow/Ui.luau:570-651`: Panel "HapseokCard", 240×132, in the GwangalliLayout `topRight` slot. Buttons 짠 / 같이 춤 / 번호 교환 / 잘 가요 send `ShowRequest("act", kind)`.

### 1.10 ClubRanking (GwangalliBuildings, v7 zip) — the ranking that already ships

**Server** `Z/ServerScriptService/GwangalliBuildings/ClubRanking.luau`
* Contract :2-25:
  * Folder `ReplicatedStorage.GwangalliClubRanking`.
  * Attribute `Top` = `{ night, list = { {u, n, t} } (top 5), king }`; attribute `Zones` = `{ {x,y,z,sx,sy,sz} }`.
  * RemoteEvent `Fx`, FireAllClients with `{kind = "order"|"king"|"booking", table, name, u, item, tier, price, total, rank, prev, gap?, chase?, centre?, dethroned?, guests?, untilT?}`.
* Night key `nightOf(unix) = floor((unix + 9h - 6h) / 86400)` :62-64.
* ODS `"GwB_ClubSpend_" .. night` :136-144; flushes every 20 s, syncs every 60 s; in Studio it keeps memory only :146-153.
* Board `Workspace.GwangalliBuildings.ClubRankingBoard` on the main room's SOUTH wall :290-405. It is placed by a raycast from the MainRoom bounding-box centre along `-club:GetPivot().RightVector`, at y 20.5, fitted between wall items, 16..28 × 12.5.
* Order detection: a `Tables[id].at` change (primed after the first read) :528-550; the exact item comes from `Show` when `|Show.arriveAt - at| < 0.05` :519-525; bookings come from a `Booking.id` change :553-573.

**Client** `Z/StarterPlayer/StarterPlayerScripts/GwangalliBuildingsClient/ClubRanking.luau`
* ScreenGui `GwangalliClubRankingFx`, DisplayOrder 40, top-centre cards at y 118 px (:101-194).
* Board banner / frame flash and table sparks (:256-297); 합석 party beams (:300-359).
* Crown BillboardGui "👑 오늘 밤 큰손" over #1, offset 3.2 (:364-403).

### 1.11 Money

* **`ServerStorage.GwangalliGameplayAPI` is defined twice, and the second definition wins.**
  * First, `Z/ServerScriptService/GwangalliGameplay/Life.luau:677-745` (setupClubApi) is called from `Life.init` (`Z/.../GwangalliGameplay.luau:471`). Its ops: spend(amount,label,prefer) / addStats (clamped ±20) / balance / clubState / clubGrant / allowTeleport.
  * Then `Z/ServerScriptService/GwangalliGameplay.luau:481-496` replaces `OnInvoke` with the unified wallet:
  ```lua
  api.OnInvoke = function(op, player, amount, label)
    local d = Profiles.get(player)
    if op == "balance" then return d and d.cash or 0, d and d.bank or 0 end
    if not d then return false end
    if op == "spend" then ... return ctx.spend(player, math.floor(amount), label or "건물 · 생활")
    elseif op == "earn" then ... return ctx.ledger(player, "bank", math.floor(amount), label or "생활 수익")
    elseif op == "addStats" then return ctx.addStats(player, amount, label or "생활") end
    return false
  end
  ```
  * The ops that work are:
    * `balance` — returns 0,0 when the player has no profile.
    * `spend` — no bank preference; pays cash first, then 체크카드.
    * `earn` — bank credit.
    * `addStats` — NOT clamped, so we clamp to ±20 ourselves.
  * `clubState` / `clubGrant` / `allowTeleport` return `false` today. Our code must work with either handler.
* **Income boost.** `Z/ServerScriptService/GwangalliGameplay.luau:304-320`: `ctx.ledger` multiplies positive income by 1.2 for `GwPassIncome` holders, unless the label contains one of `INCOME_SKIP` (:309: 환불, 반환, 취소, 송금, 입금, 출금, 받음, 빌려, 지원금, 매각, 매도, 정산, 상금, ...). Any `earn` we do (a refund or the DJ share) MUST put "환불" or "정산" in its label.
* **Bank** (`Z/ServerScriptService/GwangalliGameplay/Bank.luau:1-36`): player↔player 송금 and 현금 주기 live inside the gameplay ctx, with no server API for add-ons. We do not move money between players, except the optional DJ share.
* **Reference prices:**
  * One CVS shift pays ~28-33k원 (ShowShared :93-94).
  * Door 30k/50k; bottles 90k-1.2M.
  * Legacy `ClubShared.Menu` is 150k/300k/250k, bound to LiveConfig with the happy-hour multiplier (`P/ReplicatedStorage/ClubShared.ModuleScript.luau:85-89`).

### 1.12 Social / roster

* **`ServerStorage.GwangalliSocialAPI`** (`Z/ServerScriptService/GwangalliGameplay/Relationships.luau:32-49`): `affinity(id) -> a, tier`, `tier(id) -> tier, name`, `award(id, source, amount?)`, `joint(activity, ids?)`, `perk(kind, arg?)` (clubEntry, vipDiscount...).
* **Award sources** (`Z/ReplicatedStorage/GwangalliSocialShared.luau:170-210`): `play` (같이 놂, base 3, max 2), `hangout`, `club`, `dance`, `drink` (음료 삼), `table`, `number`... The social system caps them.
* **Tiers** :90-97: 모르는 사이 🤍 / 아는 사이 💛 / 친한 사이 🧡 / 친구 💖 / 절친 💞, each with a colour.
* **`ReplicatedStorage.GwangalliCitizens`** (`Z/ReplicatedStorage/GwangalliCitizens.luau:8-30`):
  * `byId[id] = {name, age, g, job, topics, accent = {r,g,b}, club, look, ...}`.
  * `TOPICS[t].label` (:1075+, e.g. "맛집"); also `smallTalk`, `greeting`, `numberLine`.
  * Example guest: 이서연 · 22 · 대학생 (광고홍보학과) · topics photo/fashion/club.

### 1.13 Gates / player attributes

* **Wristband:** valid while `ClubOceanWristbandUntil > workspace:GetServerTimeNow()` (Club.Script :692-699). Players without one are walked out of non-Near zones every 2 s.
* **Journey:** `GwJourneyClub` = "locked" | "hinted" | "open"; absent means open (`Z/.../Play/Journey/Club.luau:5-12`).
* Others: `ClubVIP`, `ClubVIPTable`, `ClubGuestList`, `ClubOrder` (ClubShared.Attr :65-69).

### 1.14 UI style, layout, quality, live config

* **GwangalliUI kit** `P/ReplicatedStorage/GwangalliUI.ModuleScript.luau:1-36` (API list) and tokens :41-107.
  * Colours: dark glass navy (glass 15,18,31 @ 0.14), cyan #3DD6F5, magenta #FF4FA3, gold #FFC247, violet #8B6CFF, green #3DDC84.
  * Fonts: Gotham / GothamMedium / GothamBold / GothamBlack. Type sizes 28/22/18/15/14/12/11. Radius 12/16/20/24.
  * `K.Kinds.club` = violet 🎶.
  * Components:
    * `K.BottomSheet(host, {title, subtitle, side = "bottom"|"right", width, onClose})` :2610-2614.
    * `K.Button(parent, {text, style = primary|secondary|tonal|ghost|gold|bridge|..., onClick})` :1536-1538.
    * `K.Tabs`, `K.Chip`, `K.ListRow`, `K.MoneyLabel`, `K.confirm`, `K.toast({kind, title, body, icon})` :2959.
    * `K.won`, `K.countUp`, `K.shimmer`, `K.pop`, `K.pulse`.
* **GwangalliLayout slot contract** `P/ReplicatedStorage/GwangalliLayout.ModuleScript.luau:24-60`.
  * Slots: topLeftChips, topCenter, topRight (the 합석 card lives here), rightColumn(.phone/.travel/.sprint), bottomCenter (Now Playing; the ClubDance bar sits right above it), sheetRight (modal side sheet; disable controls while open), toasts, dialog.
  * API: `Layout.rect(slot)`, `Layout.zones()` (thumbstick / jump), `Layout.onChanged(fn)`.
  * Convention: a ScreenGui with `HideGwangalliHUD = true` asks HUD layers to step aside.
* **Club UI already on screen:**
  * ClubDance bar (bottomCenter and above).
  * GwangalliClubShowUI sheets (DisplayOrder 46, sheetRight/bottom).
  * 합석 card (topRight).
  * ClubRanking cards (top centre, DisplayOrder 40).
  * Now Playing (bottomCenter).
* **GwangalliQuality:** `get()` → low|mid|high, plus `isSaver()`. **GwangalliNight:** `hype()`.
* **GwangalliLiveConfig** (`Z/ReplicatedStorage/GwangalliLiveConfig.luau:12-22,123-136`):
  * `Live.get(key)`, `Live.enabled(id)` (true when unknown), `Live.happyHour()`.
  * `events.club.themeNight` ∈ none|hiphop|edm|kpop|retro|white|neon (labels such as "EDM 나이트").
  * `events.happyHour.multiplier` (club prices).

### 1.15 Marketplace / receipts / OrderedDataStore (confirmed)

* **`ProcessReceipt`** is assigned NOWHERE, in the place dump or in any of the 381 zip / add-on files. The only mention, `Z/ServerScriptService/GwangalliGameplay/Arms/SpecialBox.luau:4-5,27`, says it never assigns it ("a place has exactly one; the future central receipt handler owns it"). There is no `PromptProductPurchase` and no developer product.
* **Game passes only:** `ReplicatedStorage.GamePassConfig` + `GwangalliStore` (PromptGamePassPurchase) + `ServerScriptService.GwangalliPassPerks` (`GwPass_<key>`, `GwPassIncome`, `GwPassSpeed`).
* **`GetOrderedDataStore`** is used by `GwangalliBuildings/Royal` (`"GwB_Arcade_" .. game .. "_" .. day`) and ClubRanking (`"GwB_ClubSpend_" .. night`). The other club DataStore is `ClubOceanMusic_v1` (playlist cache).
* → GwangalliClubPlus sells nothing for Robux and never touches `MarketplaceService.ProcessReceipt`.

### 1.16 Geometry (from place.bin; world space; the club model is rotated ≈ -89° about Y)

* **Anchors** (tag ClubShowAnchor, under `CLUB OCEAN 광안/ClubShowAnchors`):

  | Anchor | Position | Notes |
  |---|---|---|
  | `Show_LEDWall` | (-72.88, 23.82, 373.99) | size 56 × 17.05 × 0.1; LookVector ≈ (-1, 0, -0.015), front face into the room |
  | `Show_DJ` | (-98.78, 17.5, 373.70) | |
  | `Show_Floor` | (-106.83, 10, 373.48) | |
  | `Show_SpotRig` | (-119.62, 27, 373.29) | |
  | `Show_StaffDoor` | (-153.39, 10, 410.69) | |
  | `Show_Lobby` | (-186.33, 10, 386.59) | |
  | `Show_HallDoor` | (-174.23, 10, 386.77) | |
  | `Show_HallTurn` | (-157.27, 10, 389.02) | |

* **Main LED:** `MainRoom/LEDWall/LEDWallFrame` at (-71.8, 23.6, 374.0), 56.8 × 17.8.
* **Side LED:** `MainRoom/ServiceStation/SideLEDFrame` at (-118.8, 23.3, 411.8), 58.4 long × 15.6 tall (x -148..-89.6), 96 pixels facing -Z into the room.
* **Lasers:** 4 × `MainRoom/Lasers/LaserEmitter` (each with a LaserAperture) at (-98.0, 26.9, 361.6), (-98.4, 26.9, 385.6), (-73.3, 31.8, 347.4), (-74.1, 31.8, 400.6), with 8 ClubLaser beams each.
* **DJ booth and dance floor:**
  * BoothPlatform at (-98.7, 8.6, 373.7), spanning x -101.7..-95.7 and z 361.8..385.6, top y≈10.15.
  * DJDesk at (-99.4, 11.9, 373.7); MirrorBall at (-111.1, 23.9, 373.4); kinetic tubes at y 27.9, x -126.9..-103.3.
  * LED dance floor (48 tiles) around `Show_Floor` — nothing may be placed on it.
* **ParadeRoute** (ClubRuntime/ParadeRoute, TargetTable G2), WP1..8: (-143.1,10,404.2) (-152.5,10,404.1) (-152.3,10,392.1) (-91.4,10,393.0) (-91.3,10,383.6) (-82.6,10,383.7) (-82.5,10,376.0) (-81.6,10,373.0).
* **31 tables:** T1-T10 Standing (4 seats), S1-S6 Bar (4), D1-D3 DJ (4), B1-B8 Booth (6), G1-G4 VIP platform (8/8/8/6).
* **Zones** (under ClubRuntime): Main at (-124.2, 19.5, 376.9), 70×26×105; HipHop; Lobby at (-198.2, 12.5, 375.8), 62×12×41; Corridor; Restroom ×3; VIPStair; Lounge; Terrace; Near (310×78×237, Priority 1).
* **Free mount spots** (non-colliding, wall- or ceiling-hung):
  * Under the MainBar canopy's long beams (`MainBar/BarCanopy/CanopyBeam` at y 20.2, z 364.4 and 381.4; outer CanopyLED at z 363.4 / 382.5) → "bar TV" boards at y 16.9-19.7, facing ±Z.
  * Under the lobby ceiling (`Lobby/LobbyCeiling` underside at y 17.55) → a hanging double-sided screen around (-184.5, 15.7, 380), facing ±X (the lane from the tunnel to the hall door).
  * Not used: the mezzanine fascia (x -156.9, y 17.75-19.85, z 341-394). It already carries FasciaLED and the "CLUB OCEAN · 광안" sign, and the wayfinding HangingSigns hang behind it (x -159/-160, z 356 / 387).

---------------------------------------------------------------------------------------------------

## 2. What exists vs. what is missing

| Target | Exists today | Missing (GwangalliClubPlus adds) |
|---|---|---|
| 전광판 order animation with nickname | Korean overlay "G2 테이블 감사합니다 ✨" + "<name>님 · <label>" fades in for the whole show (tier ≥2); staff name board; DJ bubble; ClubRanking banner on its board; the pixel wall only shows ASCII "VIP NAME" (legacy) | A tier-scaled cinematic intro (stinger, big nickname reveal on the beat, item icon, price count-up, rank badge "오늘 밤 2위 · 1위까지 ₩…", 👑 1위 탈환 stamp); a side-LED mirror; a lower-third name strip while their title shows; a ticker of the night's events |
| 후원 (paid shout-outs) | Nothing: no paid LED messages, no tips | 전광판 후원 in 기본 / 스페셜 / 레전드 grades; templates (생일, 환영, 감사, 응원, 크루, DJ 리스펙, 직접 쓰기 filtered); target (나 / a player in the club / a table); queue + receipts |
| Ranking boards | 오늘 밤 큰손 TOP 5 (cross-server ODS) + crown + cards (ClubRanking) | 오늘 밤 후원왕, 이번 주 큰손 TOP 10, 명예의 전당 (역대 최고 단일 주문 / 하룻밤 최고 / 최다 후원), 오늘의 인기 테이블; "bar TV" boards, a lobby TONIGHT screen, and a 랭킹 sheet with 내 순위 |
| Laser show | ClubLights house lasers (fan / tunnel / sweep, 30 Hz) | Own rig: TableLock (beams converge on the ordering or gifted table), Parade Follow, Crown, a scheduled 8-bar "OCEAN LASER SHOW" in the house show's quiet intro bars, DJ-triggered cues (P2) |
| Bottle parade | Staff line with sparklers, name board, spotlight, dim, confetti (royal); house parade every 150 s | A light carpet that unrolls under the staff, laser follow, crowd cheer pulses, gift parades to OTHER tables (테이블 선물) with recipient thanks |
| 합석 production | MD + 2-4 roster guests walk in, sit, speech bubbles, 짠/춤/번호/잘 가요, ClubRanking party beams | "MD 매칭" LED profile cards; guest name tags with affinity tier; walk-in light carpet + laser follow; ⚖️ 밸런스 게임 at the table (affinity via `play`); 📸 단체 사진 (LED countdown + polaroid); 📝 합석 리포트 |
| DJ | None for players | (P2) 게스트 DJ 타임: booking, DJ pad cues, ON AIR lower-third, crowd reaction |
| Robux | Game passes only; no ProcessReceipt | None (by design) |

---------------------------------------------------------------------------------------------------

## 3. Conflicts / risks and how we avoid them

1. **LED overlay overlap.** Their `ClubShowLED` SurfaceGui sits AT the anchor CFrame with ZOffset 1. It stays up for the whole show (`Show.led(..., holdEnd - now + 2)`) and for the 합석 intro. ClubLights' pixels show the countdown, DROP and photo. Our canvas part sits 0.2 stud in front, so it always draws over theirs. The client LED scheduler follows these rules:
   * (a) Our order intro plays only in [Show.at, Show.at + intro] (2.2-8 s by tier), exactly while the room dims and the first staff member steps out. Then we collapse to a 16 % lower band, so their title and sub-line stay visible.
   * (b) Our paid cues go full-screen only in free windows: no official show or 합석 intro overlay, and no countdown. Otherwise they run on the side LED (which has no official overlay) plus the main lower band.
   * (c) Whenever `Bus.countdown > 0` or `os.clock() - Bus.dropAt < 2.2`, our main full layer fades out in 0.15 s, because the drop belongs to the house show. The lower band may stay.
   * The server scheduler also avoids the clock-mode countdown windows (bars 22-24.9 and 54-56.9 counted from ShowEpoch).
2. **Lasers.** ClubLights writes the ClubLaser beams every 33 ms. We create our own Beams and Attachments in `Workspace.GwangalliClubPlusLocal`, use a distinct palette (ocean green 30,255,140 / gold 255,196,60), and never run our big patterns during `F.fanK` (the first 4 beats after a drop).
3. **Bus.** We write only the documented input `playerDanceAt` (for a local crowd cheer). We never write section / beat / drop / countdown / photoAt. Writing photoAt would trigger ClubLights' own LED photo moment; our photo uses our canvas instead.
4. **ColorCorrection / Lighting.** The show adds `Lighting.ClubShowDim` and ClubLights grades the room. We add no Lighting effects.
5. **NPC rigs.** ClubLights and ClubCrowd own the `ClubNPC` rigs (tags + LocalTransparencyModifier). GwangalliClubShow owns its staff / MD / guest rigs. We only ADORN their guest heads with BillboardGuis (in PlayerGui), and we build our own gift staff rigs from GwangalliNPCLooks / GwangalliAnim in our own folder.
6. **Parades.** Our gift parade holds the house parade (`ClubShowHook hold`). It starts only when no official show is walking (`Show.endAt` has passed and any Booking walk-in is done). If an official show starts mid-gift, the two simply overlap (local rigs, no collisions). At most 3 gifts are queued.
7. **Ranking duplication.**
   * If `ReplicatedStorage.GwangalliClubRanking` exists (we wait up to 60 s), we reuse its `Top`, build no "오늘 밤 큰손" board, and our boards show other categories.
   * If it is missing, we add a 큰손 page computed by us, under a separate ODS name `GwClubPlus_Spend_<night>`.
   * Our order effects never duplicate ClubRanking's screen cards: we show world FX only, and the buyer gets one K.toast only when ClubRanking is absent.
8. **Order event semantics.**
   * One `Show` write per show; queued shows publish when they begin; `id` restarts per server. So the dedupe key is `id .. "@" .. at`.
   * Orders served without a show appear as a `Tables.at` change with no matching `Show`.
   * `Tables.set` keeps the best tier, so a lower order on a higher-tier table is priced as the better set. ClubRanking has the same edge case; it is acceptable.
9. **Money.**
   * The unified wallet's `spend` ignores the bank preference, `balance` returns 0,0 without a profile, `addStats` is not clamped, and the Life-only ops return false.
   * So: check `balance` first; reserve the queue slot BEFORE charging; charge with an 8 s timeout and honour paid-late; clamp stats to ±20.
   * Refunds go only through `earn`, with "환불" in the label (so no 1.2× boost).
   * No API → the features are free (as the club already does), with stricter cooldowns, and the sheet says "이벤트 무료".
10. **Remote abuse.**
    * Token bucket (6 @ 1.5/s), per-op cooldowns, and one paid op in flight per player.
    * Request ids (`rid`) dedupe double taps, as in Bank.
    * Strict payload types and lengths; enum ids only, with server-side prices.
    * The target must be a current player inside the club, and table ids must come from `ClubShowHook tables`.
    * The sender must be `inClub`, have a valid wristband, and not be Journey "locked".
11. **Text safety.**
    * Free text is ≤ 20 chars and goes through `TextService:FilterStringAsync(text, sender.UserId, PublicChat):GetNonChatStringForBroadcastAsync()`. If filtering fails or the result comes back mostly '#', we reject it with no charge.
    * Names come only from the existing filtered names, or from our `filteredName` (same method as GwangalliClub).
    * Targets can opt out with the player attribute `GwClubPlusNoTag` (a toggle under ⚙️ in the 랭킹 sheet); the sender then sees "그 손님은 전광판 이름 표시를 꺼 두었어요".
    * Same-sender-to-same-target cooldown of 5 min. No romance or alcohol templates.
12. **Performance (phones).**
    * The LED is UI tweens (TweenService); the only per-frame Lua is count-ups of ≤ 1.2 s.
    * Lasers run at 30 Hz with tier caps (high 24 beams / mid 12 / low 4 / saver 0).
    * Light carpet ≤ 40 segments (low 16); our parade rigs ≤ 3 (low 2, saver 1, pooled).
    * Everything idles unless `Bus.state == "Inside"` (or Near, for the lobby screen).
    * Server: no per-frame work; one 0.5 s tick.
13. **Streaming.** Anchors and tables may stream out, so the client looks them up by tag every time it needs them. All our world visuals are client-local, and the boards are client-built from replicated attributes (no server parts).
14. **Interior team.** GwangalliBuildingInterior may hide map parts locally and adds `Workspace.GwInteriorDetailLocal`.
    * Our wall and ceiling raycasts exclude that folder and ours.
    * We never parent GUIs under map parts: all SurfaceGuis and BillboardGuis live in PlayerGui with `Adornee`.
    * Our props on table tops use the table-top height, which they do not change.
15. **UI overlap.**
    * The HUD rail is 3 buttons on the LEFT edge, between the bottom of `topLeftChips` and the top of the thumbstick zone (`Layout.rect`, `Layout.zones`). It never touches ClubDance (bottom), Now Playing (bottomCenter), the 합석 card (topRight) or toasts (top).
    * Sheets use `sheetRight` in landscape and the bottom in portrait. While open they set `HideGwangalliHUD` and pause controls, like GwangalliClubShow's Ui.
    * Our extra 합석 buttons sit directly under their 132 px card in the topRight rect.
16. **Studio/engine quirks.** Spherecast and newer APIs are pcall'd, with the same fallbacks as Club.server's legClear.

---------------------------------------------------------------------------------------------------

## 4. Add-on design

### 4.1 Player-facing features (Korean names)
* **📺 전광판 연출** — every bottle order gets a tier-scaled LED intro with the buyer's nickname (automatic).
* **🎤 전광판 후원** — pay to put a nickname and a message on the LED wall (기본 / 스페셜 / 레전드).
* **🎁 테이블 선물** — send a set to another occupied table; staff parade it over; the recipient can reply 💙 고마워요.
* **🏆 랭킹** — bar TV boards, a lobby TONIGHT screen, and a 랭킹 sheet (오늘 밤 큰손 · 후원왕 · 이번 주 · 명예의 전당 · 인기 테이블).
* **🟢 OCEAN LASER SHOW** — our laser rig: table lock-ons, parade follow, scheduled 8-bar shows.
* **✨ 합석 프로덕션** — MD 매칭 cards, name tags, 밸런스 게임, 단체 사진, 합석 리포트.
* **🎧 게스트 DJ 타임** (phase 2; `Config.DJ.Enabled = false` by default).

### 4.2 Files (only under the allowed paths)
```
src/ReplicatedStorage/GwangalliClubPlusShared/          (ModuleScript "GwangalliClubPlusShared")
  init.luau     Config + names + prices + timing + keys + validation helpers (pure, no yields at require)
  Lines.luau    Korean text banks (LED headlines, templates, MC lines, reactions, receipts, errors)
  Cues.luau     LED template timelines per kind/tier + laser pattern functions (pure: t, beat -> targets)
  Rank.luau     night/week keys (KST 06:00), merge/top-N, record rules (pure)
  Balance.luau  밸런스 게임 question bank + deterministic guest answers + chemistry score (pure)

src/ServerScriptService/GwangalliClubPlus/              (Script "GwangalliClubPlus")
  init.server.luau  bootstrap, remotes, context C, rate limit, dispatch, PlayerRemoving, 0.5 s tick, BindToClose
  Bridge.luau       existing-system adapter: GwangalliClubShow attrs, ClubShowHook, GwangalliClubAPI,
                    GwangalliGameplayAPI, GwangalliSocialAPI, GwangalliCitizens, ClubRanking, LiveConfig, gates
  Stage.luau        server cue sheet: lanes (main / side / lower / laser / parade), slotting, Stage attr + "cue" events
  Shout.luau        전광판 후원 menu / validation / filter / charge / enqueue
  Gift.luau         테이블 선물: validation, charge, gift parade record (path), hold + stamp, thanks
  Ranking.luau      tonight / week / records aggregation, ODS + DS persistence, Boards attr, per-player attrs
  Hapseok.luau      합석 production: profiles, balance game state, photo cue, affinity report
  Dj.luau           (P2) guest DJ booking + cues

src/StarterPlayer/StarterPlayerScripts/GwangalliClubPlus/  (LocalScript "GwangalliClubPlus")
  init.client.luau  bootstrap; waits for shared modules; wires attrs/events; idle gating by Bus.state
  Core.luau         context: modules (ClubShared, ShowShared, PlusShared, K, Layout, Quality, ClubMusicShared,
                    Night, Citizens, SocialShared, NPCLooks, Anim), local folder, ScreenGui, tween/beat helpers, caps
  Led.luau          LED canvas (main + side), template renderer, lower band, ticker, local priority scheduler
  Lasers.luau       laser rig (mounts, Beam pool, 30 Hz aim job, patterns from Cues)
  Parade.luau       light carpet + laser follow for official shows / 합석 walk-ins; our gift parade rigs; gift props
  Boards.luau       bar TV boards + lobby TONIGHT screen (local parts + SurfaceGuis in PlayerGui)
  Hapseok.luau      MD 매칭 cards, guest name tags, 밸런스 게임 UI, photo, report card
  Ui.luau           HUD rail, 전광판 / 선물 / 랭킹 sheets, receipts, toasts (GwangalliUI kit only)
  Dj.luau           (P2) DJ pad
```

### 4.3 Server context `C` (init.server.luau) — functions every module uses
```
C.now() -> number                                    -- workspace:GetServerTimeNow()
C.isPlayer(p) -> bool
C.send(p, kind, payload) ; C.broadcast(kind, payload) -- Event:FireClient / FireAllClients
C.publish(attr, value)                               -- JSON on ReplicatedStorage.GwangalliClubPlus
C.filteredName(p) -> string                          -- same as GwangalliClub (cached; "손님" on failure)
C.filterText(p, text) -> string?                     -- broadcast filter, nil = rejected
C.balance(p) -> cash?, bank?                         -- GameplayAPI "balance"
C.charge(p, amount, label, onDone(status))          -- copy of GwangalliClub C.charge (8 s timeout, paid-late)
C.refund(p, amount, label)                           -- GameplayAPI "earn", label must contain "환불"
C.addStats(p, delta, label)                          -- clamped ±20
C.hook(method, ...) ; C.social(method, p, ...) ; C.clubApi(op, p, a)
C.gate(p) -> ok, reason                              -- player, wristband valid, Journey not locked, hook inClub
C.tableInfo(id) ; C.tables() ; C.reach(p, id, r)
C.won(n) -> "1,200,000원"
```

### 4.4 Remotes and payloads

`ReplicatedStorage.GwangalliClubPlus` is a Folder created by the server and parented last. It holds:
- RemoteEvent **`Request`** (client → server: `(op: string, payload: table)`)
- RemoteEvent **`Event`** (server → client: `(kind: string, payload: table)`)

No RemoteFunctions.

Client → server ops (every payload field is validated; unknown fields are ignored):
```
"menu"   { kind = "shout" | "gift" | "rank" }                         -> Event "menu"
"shout"  { rid: str<=16, grade = "basic"|"special"|"legend", tpl = "bday"|"welcome"|"thanks"|"cheer"|"crew"|"dj"|"free",
           target = { kind = "self"|"player"|"table", userId?: int, table?: str<=4 }, text?: str (utf8 <= 20) }
"gift"   { rid, table: str<=4, set = "fruit"|"tower"|"box", note = "hi"|"bday"|"thanks"|"cheer" }
"thanks" { giftId: int }                                             -- recipient, once per gift, free
"notag"  { on: bool }                                                -- opt out of being targeted
"hgame"  { op = "start"|"pick"|"stop", round?: int, pick?: 1|2 }     -- 합석 owner only
"hphoto" {}                                                          -- 합석 owner only
"dj"     { op = "book"|"cue"|"leave", cue? = "laser"|"co2"|"confetti"|"hands"|"shout"|"count", table? }  -- P2
```
Server → client kinds:
```
"menu"    { kind, priced: bool, free: bool, wallet = {cash, bank}, grades/sets = { {id, price, label, desc, icon} },
            templates = {...}, targets = { players = { {u, n} }, tables = { {id, owner, n, tier} } }, cooldown, queue }
"receipt" { op, status = "ok"|"queued"|"nofunds"|"wait"|"full"|"filter"|"notag"|"gate"|"error"|"free",
            price?, wait?, pos?, at?, rid }
"cue"     { id, kind, at, dur, lanes = {..}, mode = "full"|"lower", tier, data }    -- also mirrored in Stage attr
"order"   { key, table, u, n, item, tier, price, total?, rank?, prev?, gap?, king?, dethroned? }  -- enrichment
"gifted"  { giftId, from = {u, n, table}, to = {u, n, table}, set }                  -- to the recipient
"hgame"   { state = "round"|"reveal"|"done", round, q = {a, b}, picks?, score?, chem? }
"report"  { table, guests = { {n, before, after, tierFrom, tierTo} }, numbers, chem }
"toast"   { title, body, icon, kind }
```

### 4.5 Folder attributes (JSON, server-written) on ReplicatedStorage.GwangalliClubPlus
```
Stage   { v = 1, serial, now = cue?, next = { cue, cue, cue }, ticker = { {n, text, won?, at} } (<= 8) }
        cue = { id, kind = "order"|"shout"|"gift"|"king"|"booking"|"photo"|"laser"|"thanks"|"dj",
                at, dur, lanes, mode, tier, data = { ... } }
Boards  { v = 1, night, week, at, hasRanking = bool,
          pages = { { key = "spend"|"shout"|"week"|"tables", title, sub, rows = { {u, n, v, x?} } } },
          records = { bestOrder = {u, n, v, at}, bestNight = {u, n, v, night}, bestShout = {u, n, v, at} },
          nextLaser = serverTime }
Parade  { id, kind = "gift", set, tier, staff, table, from = {u, n, table?}, to = {u, n}, path, y, total,
          at, arriveAt, endAt, serve = {x, y, z} }   -- {id = 0} when none
Hapseok { booking = BookingId, table, owner, guests = { {id, name, age, job, tags = {"맛집","EDM"}, accent = {r,g,b}, tier} },
          game = { round, q = {a, b}, endsAt, state, score }?, photoAt? }        -- {booking = 0} when none
DJ      (P2) { u, n, untilT, cues = { {kind, at} } }
```
Player attributes:
- `GwClubPlusTonight` — won spent tonight (orders + shouts + gifts).
- `GwClubPlusWeek` — won spent this week.
- `GwClubPlusNoTag` — bool.

### 4.6 Data saving

* **Keys.**
  * `night = floor((unix + 9h - 6h) / 86400)`, the same cut as ClubRanking and the door.
  * `week = floor((night + 3) / 7)`, so a week starts Monday 06:00 KST (night 0 = Thu 1970-01-01).
* **Stores.**

  | Store | Kind | Contents |
  |---|---|---|
  | `GwClubPlus_Shout_<night>` | ODS | uid → won (shouts + gifts) |
  | `GwClubPlus_Week_<week>` | ODS | uid → won (orders + shouts + gifts) |
  | `GwClubPlus_Spend_<night>` | ODS | ONLY when ClubRanking is absent |
  | `GwClubPlus_Records_v1`, key `records` | DS | UpdateAsync only when a record breaks |
  | `GwClubPlus_Player_v1`, key `<uid>` | DS (optional, P2) | `{v=1, life, shouts, gifts, bestRank, titles}` |

* **Write path.**
  * Keep pending deltas per uid and flush every 30 s with `UpdateAsync(old + delta)`; failed deltas are re-queued.
  * `GetSortedAsync(false, 10)` every 60 s per board.
  * Flush on `BindToClose`. In Studio or on a 403, keep memory only (the ClubRanking pattern).
* **Night rollover.** Switch keys before yielding, then flush the old pending deltas into the old night (ClubRanking :456-469 pattern).
* **Table popularity tonight.** Server memory only; table ids are per night, so there is nothing to persist.

### 4.7 Prices / limits (server-authoritative, in `GwangalliClubPlusShared.Config`)

| Item | Price | What it does | Limits |
|---|---|---|---|
| 전광판 기본 | 30,000원 | lower band 10 s + ticker + side LED 6 s | 45 s cooldown per player |
| 전광판 스페셜 | 80,000원 | main full 8 s (in a free window; otherwise side full + lower) + sparkles + crowd cheer | queue ≤ 6 |
| 전광판 레전드 | 200,000원 | main full 14 s + laser Crown/TableLock + UI confetti + CO2 puffs on the beat + MC bubble at Show_DJ | 1 legend in the queue at a time |
| 🍓 과일 플래터 선물 | 50,000원 | 1 staff, tray, lower band "🎁 B3 → G2" | 60 s per player, gift queue ≤ 3 |
| 🧃 스파클링 주스 타워 | 150,000원 | 2 staff + sparklers, LED full 6 s, ClubLights bottles at arrival | same |
| 🎁 오션 기프트 박스 | 400,000원 | 3-staff parade + name sign + laser follow + confetti | same |
| 💙 고마워요 (thanks) | free | lower-band one-liner from the recipient | once per gift |
| 🎧 게스트 DJ (P2) | 100,000원 / 4분 | ON AIR + 6 pads | 1 at a time, 10 min cooldown per player |

* Happy hour (`Live.happyHour()`) multiplies these prices the same way it does club prices.
* `Live.enabled("clubplus") == false` turns the whole add-on off.
* Stats: shout gives `{happiness = 2 + grade, popularity = grade}`; gift gives `{happiness = 3 + tier, popularity = tier}`.
* No money API → everything is free, cooldowns are doubled, and the menu shows "이벤트 무료".

### 4.8 Server modules — responsibilities and key functions

**Bridge.luau**
```
Bridge.init(C)
Bridge.onOrder(fn(evt))     -- evt = { key = id.."@"..at, source = "show"|"direct", table, u, n, item, tier, price,
                            --         label, icon, at, arriveAt, endAt, path?, y? }
Bridge.onBooking(fn(rec, prevId))   Bridge.show() -> rec?   Bridge.booking() -> rec?   Bridge.tables() -> map
Bridge.officialWindows(t0, t1) -> { {from, to, kind = "show"|"booking"} }   -- LED overlay windows from Show/Booking
Bridge.countdownWindows(t0, t1) -> { {from, to} }  -- clock-mode, from ShowEpoch (ClubRuntime attr) + ClubShared.Sections
Bridge.rankingTop() -> decoded GwangalliClubRanking.Top?   Bridge.hasRanking() -> bool
```
The server subscribes to `GetAttributeChangedSignal("Show"|"Tables"|"Booking")` on `ReplicatedStorage.GwangalliClubShow` (`WaitForChild` 120 s). Priming works like ClubRanking: no events fire for the state found at start.

**Stage.luau** — one timeline for every LED / laser / parade moment.
```
Stage.push(cue) -> status, at        -- finds the earliest at >= now+0.6 where all lanes are free and (mode "full")
                                     -- no official window / countdown overlaps; downgrades full -> side+lower after 90 s
Stage.reserve(cue) -> token ; Stage.confirm(token) ; Stage.cancel(token)   -- reserve before charging
Stage.tick()                         -- publishes Stage attr when now/next change; schedules the laser show
```
* Order events become cues `{kind = "order", at = rec.at, lanes = main(intro by tier) + lower(until endAt) + laser (tier ≥ 3: arriveAt .. +4 beats)}`. They are never delayed, because they follow the official show.
* Laser show: every 3rd show cycle at clock bar 4 (`epoch + (k*64 + 4) * 60*4/126`), lasting 8 bars, on the laser and lower lanes.

**Shout.luau** — `Shout.menu(p)` and `Shout.request(p, payload)`. A request goes through these steps in order:
1. Gate check, then `rid` dedupe, then cooldowns.
2. Validate template, grade and target. A target player must be in the club and not have `GwClubPlusNoTag`; a target table must be owned in `Tables`.
3. Filter the text. This yields, so re-check the gate afterwards.
4. `Stage.reserve`, then a balance check.
5. `C.charge(p, price, "CLUB OCEAN 전광판 후원 (스페셜)")`, then confirm or cancel the reservation.
6. `Ranking.add(uid, name, price, "shout")`, then send a receipt with queue position and ETA.

**Gift.luau**
1. Validate: the target table has a valid `Tables` owner who is on the server and is not the sender. Reach is not required; the gate is.
2. Reserve, then charge `"CLUB OCEAN 테이블 선물 (G2)"`.
3. Build the path: lead from `Show_StaffDoor`, then `ClubShowHook route` WP2..n, then `ClubShared.paradePath(..., legClear)` to `tableInfo.serve`. This is a copy of GwangalliClub's `C.pathTo` (:211-265).
4. Timing comes from `ShowShared.Show` (`showLength`, plus an arrival calculation like Show.arrival :79-84).
5. Publish `Parade` when it starts (after any official show or 합석 walk-in). Call `hook("hold", endAt - now + 4)`, and `hook("stamp", table, arriveAt, senderUid)` for tier ≥ 2.
6. `Stage.push` an LED cue at arrival; send `Event "gifted"` to the recipient; call `Ranking.add(..., "gift")` and `Ranking.tableHit`.

**Ranking.luau**
* `Ranking.add(uid, name, amount, cat)` (cat = order/shout/gift), `Ranking.tableHit(table, kind, n)`, `Ranking.rankOf(uid) -> rank, total` (uses ClubRanking's `Top` for orders when present).
* Publishes pages and records to the `Boards` attribute on every change (debounced 2 s), sets the player attributes, and handles persistence (§4.6).
* On every order event, broadcasts the `order` enrichment with the rank, 0.4 s after the Show write, so that ClubRanking has published first.

**Hapseok.luau**
* **On a new `Booking.id`:** build profiles from `GwangalliCitizens.byId[id]` (name, age, job, 2 topic labels, accent) plus the tier from the record; snapshot `social("affinity", owner, id)`; publish `Hapseok`.
* **Game:**
  * `hgame start` is owner only, after `seatedAt`, once per booking, and not during their dance act.
  * 5 rounds × 12 s, questions from `Balance.pick(seed)`. Guest picks are `Balance.answer(guestId, qId, seed)`; the owner sends a `pick` per round.
  * Reveal → chemistry score.
  * At the end, for each guest with ≥ 3 matches: `social("award", owner, id, "play")`, and `addStats {happiness = 2}` for the owner. The LED lower band updates as it goes.
* **Photo:** owner only, during the seated phase, ≤ 2 per booking, at least 30 s apart → `Stage.push {kind = "photo", lanes main full 6 s, data = {table, names}}`.
* **Report:** when the booking ends (id → 0, or endAt passes), read affinity again and send `Event "report"` to the owner.

**Dj.luau (P2)**
* Booking happens at the booth: the root must be within the BoothPlatform box + 3 studs, the gate must pass, and the fee is charged.
* Cues are rate-limited per pad: laser 8 s, co2 12 s, confetti 15 s, hands 10 s, shout 20 s, count 30 s. They are broadcast as Stage cues, with an ON AIR lower band.
* Optional: 30 % of DJ-template shout income goes to the DJ via `earn`, labelled "CLUB OCEAN DJ 후원 정산" (no boost), capped at 300,000원 per night.

### 4.9 Client modules — rendering

**Led.luau**
* **Canvas.**
  * Main: a local Part `PlusLED_Main` (Transparency 1, Anchored, CanCollide/CanQuery/CanTouch false) at `Show_LEDWall.CFrame * CFrame.new(0, 0, -0.2)`, the same size as the anchor.
  * Its SurfaceGui lives in PlayerGui: `ResetOnSpawn = false`, Adornee = the part, Face Front, PixelsPerStud 12 (→ 672×205), LightInfluence 0, Brightness 2.4, MaxDistance 230.
  * Side: canvas `PlusLED_Side` built from `SideLEDFrame`, facing the Main zone centre, PPS 10.
* **Layers.**
  * `Full`: the root frame, transparent when idle.
  * `Lower`: the bottom 16 % band (name strip / ticker).
  * `FX`: UI particles (small Frames tweened), capped at `ShowShared.Q[tier].confetti / 4`.
* **Templates** (timelines in Cues.luau, beat-quantised with `Core.onBeat`):
  * Order T1 (lower band only, 6 s): "🧊 T3 테이블 · {name}님 · 기본 세트 감사합니다".
  * Order T2 (full, 4.5 s): "THANK YOU" stinger → "{name}님" big (GothamBlack, gold→white shimmer) → "{icon} {label}" → "₩200,000" count-up → rank badge ("오늘 밤 3위 ▲2" / "1위까지 ₩150,000").
  * Order T3: T2 plus the side LED mirror and a laser TableLock at arrival.
  * Order T4: adds a rotating-ray background, letter-by-letter reveal on beats, and gold UI confetti.
  * Order T5 (8 s): "OCEAN ROYAL" crown drop → huge nickname → 3-2-1 on beats → "짠~! ✨", in sync with their confetti/CO2.
  * King: a "👑 1위 탈환!" stamp, plus "{dethroned}님을 제쳤어요".
  * Shout, one palette per template:
    * 🎂 pink/gold "HAPPY BIRTHDAY" + "{target}님" + "from {sender}"
    * 🎉 "WELCOME TO OCEAN"
    * 💙 "고마워요"
    * 📣 "오늘 밤 주인공은 너야!"
    * 🔥 "{크루명} 크루 출격!"
    * 🎧 "DJ 선곡 최고!"
    * ✍️ the filtered free text
  * Gift: "🎁 테이블 선물 도착!" + "{fromTable} {from}님 → {toTable} {to}님".
  * Booking (MD 매칭): "MD 태양의 오늘의 합석 ✨" with 2-4 profile cards flipping in on beats → lower band "✨ 합석 · G2 · 서연 · 민혁".
  * Photo: "📸 G2 테이블 단체 사진" 3-2-1 → white flash → polaroid (names, "2026.10.16 · 23:41 · CLUB OCEAN 광안").
  * Laser: lower band "🟢 OCEAN LASER SHOW · 손 머리 위로! 🙌".
* **Local priority:** drop/countdown guard (§3.1c) > order intro > official overlay (we go to the lower band) > our full cues > ticker.
* **Late join:** play a cue if `now < at + dur`, skipping the steps that have already elapsed.
* **Order intros** are triggered directly from the official `Show` attribute, so they sync exactly with `rec.at` and still work if our Event arrives late. The rank badge waits for our `order` enrichment: it appears at +2.5 s, and is skipped if the enrichment never comes.

**Lasers.luau**
* **Mounts** (positions read only):
  * M1/M2: the DJ-booth LaserEmitters at (-98.0, 26.3, 361.6) / (-98.4, 26.3, 385.6).
  * M3/M4: the LED-wall top emitters at (-73.3, 31.2, 347.4) / (-74.1, 31.2, 400.6).
  * All four are looked up by name under MainRoom/Lasers and offset 0.6 down.
  * Optional M5/M6: local "floor lasers" (0.8×0.5×1 non-colliding boxes) on the booth's front edge at x ≈ -101.9, z 366 / 381, y 10.4.
* **Beam pool:**
  * Size per tier: high 4 per mount (24), mid 2 (12), low 1 on M1-M4 (4), saver off.
  * Beam settings: width 0.08→0.22, LightEmission 1, LightInfluence 0, FaceCamera, Segments 1.
  * Attachment1 is moved with `WorldPosition` at 30 Hz (15 Hz on low).
* **Patterns** (in Cues.luau):
  * `lock(P)`: converge on a point, with a breathing radius.
  * `crown(P)`: alternating high/low points on a ring over a table.
  * `follow(fn t -> pos)`: track a moving point.
  * `fan(y)`: a sheet over heads.
  * `tunnel(axis)`, and `scan` (a floor sweep).
* **Timing:** beat from `Bus.beatAt` / `beatSerial` / `bpm`, section from `Bus.section`. Never during the first 4 beats after a drop (`os.clock() - Bus.dropAt`).
* **Visibility:** only in the Main / Lobby / Corridor zones and within 150 studs (ClubLights' own rule).

**Parade.luau**
* **Official shows (`Show` attribute) and 합석 walk-ins (`Booking` attribute):**
  * A light carpet of thin Neon segments (2.2 wide, 0.04 tall) at floor y = `rec.y - 3 + 0.04`.
  * It unrolls with the leader at `d(t) = (t - (at + LeadIn)) * speed`, coloured by tier.
  * Segments fade 3 s after the line passes and are gone by `holdEnd`. Segments inside the LED-floor bounding box (ClubFloorTile bounds + 1) are skipped.
  * Tier ≥ 3: laser `follow` on the leader.
  * When the leader passes within 25 studs of the local player: `Bus.playerDanceAt = os.clock()` (local guests cheer).
* **Gift parade (`Parade` attribute):**
  * Our pooled rigs use the GwangalliNPCLooks staff spec (black outfit + earpiece), the same as their `staffSpec`.
  * Props by set: tray + fruit (fruit); juice tower bottle with a sparkler (tower); gift box with a ribbon and a sign "{from}님의 선물 🎁" (box).
  * Same phases as theirs (out / hold / present / bow / back), using the ShowShared helpers.
  * Local gift props sit on the target table top (side edge) for 5 min, plus a BillboardGui "🎁 from {fromTable} {from}님" for 60 s.

**Boards.luau**
* **"OCEAN 랭킹 TV" ×2:**
  * Local parts under the MainBar canopy's long beams (positions derived at runtime from the `MainBar/BarCanopy/CanopyBeam` parts; fallback config CFrames), 14 × 2.8, facing out (±Z), SurfaceGui in PlayerGui.
  * Pages rotate every 8 s: 🎤 오늘 밤 후원왕 TOP 5 · 🏆 이번 주 큰손 TOP 10 · ⭐ 명예의 전당 · 🔥 오늘의 인기 테이블. A 👑 오늘 밤 큰손 page is added only when ClubRanking is absent.
  * Per-viewer footer: "내 순위 7위 · ₩350,000" or "TOP 10 밖".
* **Lobby "TONIGHT @ CLUB OCEAN" screen:** hanging, double-sided, 6 × 3, at y 14.2-17.2 under LobbyCeiling near (-184.5, 380). It shows: 지금 1위, 후원왕, the next laser show time (K.korClock), the table where a 합석 is running, and the theme night (LiveConfig label).
* **Placement check at build time:** raycast / OverlapParams against map parts (excluding our folders and GwInteriorDetailLocal); skip any board whose box intersects something.

**Hapseok.luau (client)**
* **Name tags:** a BillboardGui in PlayerGui, Adornee = the Head of `Workspace.GwangalliClubShowLocal.ClubShowGuest<k>`. It shows "서연 · 22" plus a tier chip such as "💛 아는 사이" (GwangalliSocialShared.TIERS colours); MaxDistance 60; only after `seatedAt`.
* **Owner buttons:** "⚖️ 밸런스 게임" and "📸 단체 사진" (K.Button, 2 × 44 px), placed in the topRight rect at y + 132 + 8.
* **Game card** (below the buttons in topRight, or a bottom sheet in portrait):
  * Shows "⚖️ 밸런스 게임 3/5", two big choices and a 12 s ring.
  * Reveal: guest bubbles over their heads ("저는 바다! 🌊" plus a reaction such as "오 저도요! 🙌" or "에이~ 그건 아니죠 ㅋㅋ") and score chips.
  * Result: "케미 지수 80%! 🔥 완전 잘 맞네요".
* **Photo:** 1.2 s before the flash, the client fires the EXISTING `ShowRequest("act", "cheers")` (part of their public contract, owner only) so the guests raise their glasses. The owner's screen flashes and shows a polaroid card, with the HUD hidden for 3 s.
* **Report card** on `Event "report"`: "📝 오늘의 합석 리포트" · "서연 호감도 +9 · 아는 사이 → 친한 사이!" · "번호 교환 2명 · 케미 지수 80%".

**Ui.luau**
* **HUD rail (left edge):** 📺 전광판 · 🎁 선물 · 🏆 랭킹 (+ 🎧 DJ in P2), as 48 px glass circles, with labels on PC.
  * Visible only while `Bus.state == "Inside"`, the wristband is valid, Journey is open, and no other `HideGwangalliHUD` GUI is up.
  * Gamepad: DPadLeft focuses the rail (ContextActionService, only while visible). PC hotkey N opens 전광판.
* **전광판 sheet**, step by step:
  1. Grade chips with price and a mini live preview (the same template rendered in a small frame).
  2. Template grid.
  3. Target: 나 / 클럽 안 손님 목록 / 테이블.
  4. Optional text (TextBox with a 20자 counter).
  5. Confirm bar: "₩80,000 결제하고 송출하기 · 잔액 ₩1,234,000 → ₩1,154,000".
* **선물 sheet:** occupied tables (id, owner, tier icon) → set cards → note chips → confirm.
* **랭킹 sheet:** K.Tabs (오늘 밤 큰손 / 후원왕 / 이번 주 / 명예의 전당 / 인기 테이블), rows with rbxthumb headshots, 내 순위, and a ⚙️ "전광판에 내 이름 표시" toggle.
* **Receipts and errors** via K.toast (kind "club" / "money" / "warn"):
  * "📺 전광판 예약 완료 · 2번째 · 약 25초 뒤 송출돼요"
  * "잔액이 부족해요"
  * "잠시 후 다시 신청해 주세요 (12초)"
  * "전광판 대기열이 꽉 찼어요"
  * "메시지에 쓸 수 없는 표현이 있어요"
  * "그 손님은 전광판 이름 표시를 꺼 두었어요"
  * "클럽 안에서만 신청할 수 있어요"

### 4.10 Player flows

1. **Bottle order (existing) + 전광판 연출.**
   1. The player orders 골드 at G2 from their existing menu.
   2. The server writes `Show` (at = now+0.4).
   3. Every client: their dim, plus our LED intro (T4 template: nickname "하늘님", "✨ 골드 스파클링 주스 · 레전드", ₩600,000 count-up).
   4. At +2.5 s the rank badge appears from our `order` event ("오늘 밤 1위!" or "1위까지 ₩…").
   5. Our band collapses and their title shows.
   6. The light carpet unrolls under the staff; lasers follow (tier ≥ 3).
   7. At arrival: laser TableLock for 4 beats, plus their confetti.
   8. The ticker gets "✨ G2 하늘님 · 골드 스파클링 주스". ClubRanking's board, card and crown are unchanged.
2. **전광판 후원.**
   1. The player taps 📺 and the sheet opens (server `menu`).
   2. They choose 스페셜 · 🎂 생일 축하 · target 민지 (a player) · "생일 축하해!" and confirm.
   3. The server checks the gate, filters the text, reserves a slot (ETA 25 s) and charges 80,000원.
   4. The player gets a receipt toast.
   5. At the slot: the main LED goes full for 8 s (or side + lower band if an official show is running), guests near the target cheer, and a ticker line is added.
   6. The target gets the toast "🎂 하늘님이 전광판에 축하 메시지를 띄웠어요!".
3. **테이블 선물.**
   1. The player taps 🎁 and picks G3 (owner 준), then 🧃 스파클링 주스 타워 + "환영해요".
   2. 150,000원 is charged, and the gift queues behind any running show.
   3. `Parade` is published: 2 staff with sparklers walk to G3, and the LED shows "🎁 테이블 선물 도착! B3 하늘님 → G3 준님".
   4. ClubLights sparkler bottles land at arrival, and our props sit on the table edge for 5 min.
   5. G3's owner gets "🎁 B3 하늘님이 선물을 보냈어요!" with a "고마워요 보내기 💙" button, which sends a free lower-band thanks.
4. **랭킹.** Walking past the bar, the 랭킹 TV pages rotate. Tapping 🏆 opens the sheet with tabs and 내 순위. The lobby screen shows on the way in and out.
5. **합석 production.**
   1. A tier ≥ 4 order (automatic) or a request starts their Booking.
   2. Our MD 매칭 LED cards play on the beat.
   3. Light carpet and laser follow during the MD walk-in.
   4. Guests sit and the name tags appear.
   5. The owner taps ⚖️ and plays 5 rounds → chemistry score + `play` affinity.
   6. 📸 photo: guests 짠 via their act, LED 3-2-1, polaroid.
   7. The booking ends → 📝 report card.
6. **OCEAN LASER SHOW.** Every ~6 min, at clock bar 4 (intro), for 8 bars. The lower band shows "🟢 OCEAN LASER SHOW"; the rig goes tunnel → fan → a crown over the current #1's table (if any), and fades before ClubLights' intro lasers start at bar 12.
7. **Late joiner.** Reads `Stage`, `Parade`, `Hapseok`, `Boards` and the official attributes, and plays only the remaining parts.
8. **Failure paths.**
   * No money → "잔액이 부족해요", and the slot is released.
   * Filter reject → no charge.
   * Target left → the cue still plays with the stored name.
   * Sender left → the cue still plays.
   * Payment timeout → "결제가 지연되고 있어요", then a late payment is honoured.
   * No GameplayAPI → free, with doubled cooldowns.
9. **(P2) 게스트 DJ.**
   1. The player walks onto the booth, taps 🎧 and books 4 min.
   2. The ON AIR band shows "🎧 GUEST DJ 하늘".
   3. Pads trigger our lasers / CO2 / confetti / LED count / 샤라웃 (to a table), and the crowd cheers.
   4. When the session ends: "오늘 밤 디제잉 수고했어요! 인기 +3".

### 4.11 Budgets / quality

| | high | mid | low | saver |
|---|---|---|---|---|
| Our laser beams | 24 @ 30 Hz | 12 @ 30 Hz | 4 @ 15 Hz | 0 |
| Light carpet segments | 40 | 30 | 16 | 0 (LED only) |
| Gift staff rigs | 3 | 3 | 2 | 1 |
| LED UI particles | 36 | 24 | 12 | 0 |
| Side LED canvas | yes | yes | yes | no |
| Boards page interval | 8 s | 8 s | 12 s | 20 s |

Idle cost outside the club is one 0.5 s state check; nothing is built until the player is first `Inside`.

### 4.12 Test plan

* **Offline** (Luau CLI + a copy of the `bprev/lib/rbx.luau` mock in `feat/club/`):
  * Shared pure functions: keys, slotting against official / countdown windows, prices, validation, determinism of Balance answers, Rank merge, Cues pattern outputs.
  * Server modules with mocked `ClubShowHook` / `GwangalliGameplayAPI` / `GwangalliSocialAPI` / folder attributes: order dedupe, direct orders, the booking lifecycle, money statuses (including timeout and paid-late), rid dedupe, rate limits, night rollover.
* **Studio** (one run under flock, timeout 1500):
  * Inject the modules.
  * Trigger: an order (a real `Show` write through the real GwangalliClub `BottleService.order`, with money), a shout, a gift, and a booking.
  * Screenshot: the LED intro, the lower band over their title, the side LED, the laser lock, the light carpet, the bar TV boards, the lobby screen, and the 합석 name tags + game card.
  * Check there are no errors and that ClubLights and GwangalliClubShow keep working.

### 4.13 Phasing

* **P0:** Shared, Bridge, Stage, Led (order intros + lower band + ticker), Lasers (lock / follow / show), Parade (light carpet), Shout, Ranking + Boards, Ui rail + sheets.
* **P1:** Gift parade + thanks; Hapseok (cards, tags, game, photo, report).
* **P2:** DJ mode, per-player titles (후원왕 tag), LiveConfig theme palettes.

---------------------------------------------------------------------------------------------------

File: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/research.md`

This was a research-and-design step only. No code under the allowed `src/` paths was written yet, no studio run was done, and no progress image was produced.
