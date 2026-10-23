# GwangalliClubPlus — research + design (CLUB OCEAN 광안 AAA show add-on)

Scope: a drop-in add-on that makes CLUB OCEAN 광안 feel like a real top-tier Korean club night:
전광판 (LED wall) order / 후원 animations with nicknames, ranking boards, an own laser show layered in sync
with the house show, a richer bottle parade (+ 테이블 선물 parade), and a 합석 production on top of the
existing 합석 이벤트. Everything listens to the existing club contract; nothing in the place is edited.

Paths used below:
`P` = place dump `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/src/<Service>/<Path>.<Class>.luau`
`Z` = v7 studio add-on zip (UPSERTED over the place by the v7 studio) `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7all/gen/addons/zip/<Service>/<Path>.luau`
(Line numbers of `Z` files include the 1-line `-- Script @ ...` header the dump added.)

---------------------------------------------------------------------------------------------------

## 0. TL;DR

* Order events: listen to `ReplicatedStorage.GwangalliClubShow` folder attributes (JSON, server-written):
  `Show` (one write per bottle show: exact item, owner UserId, filtered name, table, `at`/`arriveAt`/`endAt`,
  staff path), `Tables` (table life; an `at` change without a matching `Show` = an order served without a
  show) and `Booking` (the 합석 event). Price = `GwangalliClubShowShared.item(itemId).price`.
* Ranking: a "오늘 밤 큰손 랭킹" board ALREADY exists (GwangalliBuildings/ClubRanking in the v7 zip:
  ODS `GwB_ClubSpend_<night>`, folder `ReplicatedStorage.GwangalliClubRanking` with `Top`/`Zones` attrs and
  `Fx` RemoteEvent, board on the main-room south wall, crown over #1, top-of-screen cards). Do NOT rebuild it;
  add the missing boards (후원왕, 이번 주, 명예의 전당, 인기 테이블) elsewhere and reuse its `Top`/`Fx` data.
* LED wall: physical 32x11 pixel grid (ClubLights, ASCII 5x7 font only) + a Korean SurfaceGui overlay from
  GwangalliClubShow (`ClubShowLED` part at the `Show_LEDWall` anchor, ZOffset 1) during shows / 합석. Our
  canvas = local transparent part 0.2 stud IN FRONT of `Show_LEDWall`, SurfaceGui in PlayerGui with Adornee.
  We own the first ~5 s of every show (nickname intro), then shrink to a lower-third band so their title stays
  readable; our own paid cues use free windows; we never cover ClubLights' countdown / DROP.
* Lasers: ClubLights re-aims all 32 `ClubLaser` beams at 30 Hz; never touch them. Our laser rig = our own
  Beams in our local folder, driven by `ClubShared.Bus` (beat / section / drop) + `ClubShared.clock`.
* Money: `ServerStorage.GwangalliGameplayAPI` — the EFFECTIVE handler at runtime is the unified wallet
  (GwangalliGameplay.Script overrides Life's club API): `balance`, `spend(amount,label)`, `earn(amount,label)`,
  `addStats(delta,label)`. No `ProcessReceipt` / developer products anywhere (a future central handler owns
  ProcessReceipt) → in-game won only.
* No player DJ role exists (NPC `DJ_009` + `MC_010`, "Resident DJ" catalogue music). DJ mode = optional phase 2.
* All-ages: the v7 zip's menu labels are already non-alcoholic in every build (스파클링 주스 / 프리미엄 음료) and
  the 합석 is friends-only framing. Our text: no alcohol words, no romance (no 고백 / 썸 / 커플).

---------------------------------------------------------------------------------------------------

## 1. Existing integration points (exact)

### 1.1 Which version is live
The v7 studio applies `gen/addons.json` entries with `upsert: true` over the place. Club-related upserts:
`ReplicatedStorage.GwangalliClubShowShared`, `ServerScriptService.Club`, `ServerScriptService.GwangalliClub.Show`,
`StarterPlayerScripts.GwangalliClubShow.{Show,Ui}`, `GwangalliGameplay/Play/Journey/Club`, `GwangalliGameplay/Bank`,
`GwangalliPhone/Apps/Bank`, AND new modules `ServerScriptService.GwangalliBuildings.ClubRanking` +
`StarterPlayerScripts.GwangalliBuildingsClient.ClubRanking` (wired in `Z/ServerScriptService/GwangalliBuildings.luau:150,154,196`
and `Z/StarterPlayer/StarterPlayerScripts/GwangalliBuildingsClient.luau:32,64`).
Differences vs the place dump are small (diffed): wristband 1440 → 2400 s; menu labels/icons non-alcoholic in
every build (`Z/ReplicatedStorage/GwangalliClubShowShared.luau:144-146`, icon fallback ✨ at :167); toast icons ✨.
Design for the zip version, but code every lookup defensively (ClubRanking may be missing in some live copies).

### 1.2 GwangalliClubShowShared (ReplicatedStorage, pure data)
`P/ReplicatedStorage/GwangalliClubShowShared.ModuleScript.luau`
* Contract header :6-31:
  ```
  ReplicatedStorage.GwangalliClubShow (Folder, GwangalliClub.server)
    RemoteEvent ShowEvent    server -> client: (kind, payload)  kinds: "menu", "order", "booking", "toast"
    RemoteEvent ShowRequest  client -> server: (op, a, b)  ops: "order" (tableId, itemId), "booking" (tableId), "act" (action), "menu" (tableId)
    attributes (JSON strings, written by the server only): Show / Tables / Booking
  ServerStorage.GwangalliClubAPI (BindableFunction): openMenu / reserve / hasTable / ownsTable
  ServerStorage.ClubShowHook (BindableFunction, Club.server): hold / tableInfo / tables / reach / stamp / route
  Player attributes: ClubOceanWristband, ClubOceanWristbandUntil
  ```
* Names :36-49: `Folder = "GwangalliClubShow"`, `Remote = {Event="ShowEvent", Request="ShowRequest"}`,
  `API_NAME = "GwangalliClubAPI"`, `HOOK_NAME = "ClubShowHook"`, `Tags = {Door="ClubDoor", Anchor="ClubShowAnchor"}`,
  `Attr = {Show, Tables, Booking, Wristband="ClubOceanWristband", WristbandUntil="ClubOceanWristbandUntil",
  GuestSeat="ClubGuestSeat", DoorFee="ClubDoorFee"}`.
* `ShowShared.allAges()` :62-88 (workspace attr `GwangalliClubAllAges`, `GwangalliConfig.ClubShow.AllAges`).
* Door :95-108 (Weekday 30,000 / Weekend 50,000; zip WristbandSeconds 2400); `kst`, `isWeekendNight` (06:00 cut) :111-128.
* Menu :141-147 (zip :143-147) — tiers / prices / staff:
  `basic` T1 90,000 (staff 1) · `champagne` T2 200,000 (2, parade) · `vodka` T3 350,000 (3, parade, dj) ·
  `gold` T4 600,000 (4, parade, dj, booking) · `royal` T5 1,200,000 (5, parade, dj, booking, confetti).
  Helpers `item(id)`, `label(item, aa)`, `icon(item, aa)` :153-167.
* Lines :170-181 `thanksTitle(tableId, aa)` → "G2 테이블 감사합니다 ✨", `djLine(tableId, name)`, `bookingTitle(tableId)`, `cheersWord(aa)`.
* Show timing :186-200 (`LeadIn 2.2, Speed 4.6, BasicSpeed 6.2, Gap 3.0, Hold 11, Spread 2.5, Stand 3.1, Outro 2.5,
  PropSeconds 480, OrderCooldownPlayer 20, OrderCooldownTable 25, MaxDistance 18, MaxQueue 3`).
* Booking :202-215 (`MinTier 3, AutoTier 4, Min 2, Max 4, Speed 5.4, Gap 2.6, Intro 2.4, Present 4.5, Duration 150,
  Cooldown 240, DanceSeconds 45, MD "MD 태양"`). Quality caps `Q.{high,mid,low,saver}` :218-223
  (`spark 36/24/12/6, confetti 140/90/45/20, spotLight`).
* Pure path helpers we reuse: `polyline(pts)` :229, `sample(pts, cum, d)` :241, `lineup(front, dir, n, spread)` :266,
  `travel`, `showLength(total, staff, tier)` :285-291. `pickGuests(...)` :300, `Lines` / `line(kind, tier, rnd, name)` :341-369.

### 1.3 GwangalliClub server (Script + context `C`)
`P/ServerScriptService/GwangalliClub.Script.luau`
* Creates folder + remotes :64-92 (folder parented last). Context `C` :97-103.
* `C.publish(attr, value)` :165-172 → `rfolder:SetAttribute(attr, HttpService:JSONEncode(value))` — JSON folder attributes.
* `C.filteredName(plr)` :176-197 — DisplayName (≤20 chars) through `TextService:FilterStringAsync(raw, plr.UserId,
  Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()`; "손님" on failure. **Every `name` in
  Show / Tables / Booking is already broadcast-filtered** → safe for our LED.
* `C.charge` :279-306 — the money pattern to copy: `gameplay("spend", plr, amount, label, "bank")`, 8 s timeout,
  statuses `paid | paid-late | noapi | free | declined | error | timeout`.
* `ServerStorage.GwangalliClubAPI` :350-376 (`openMenu`, `reserve`, `hasTable`, `ownsTable` only — NO way to start
  a show for someone else's table).
* Request bucket 6 tokens @ 1.5/s :381-396; dispatch :398-416; 0.5 s housekeeping :429-441.
* The modules (`Show`, `BottleService`, `Booking`) are internal (only reachable through `C`); an add-on cannot call
  them → listen to the attributes.

### 1.4 What BottleService / Show / Booking publish (the listening contract)
**Tables** — `P/ServerScriptService/GwangalliClub/BottleService.ModuleScript.luau:24-31`
```
C.publish("Tables", { [tableId] = { owner = UserId, name = filteredName, tier, set, at, untilT } })
```
`claim()` :57-71 (paid → owner; `at = 0` while the show waits; holds 900 s); `setTable(plr, id, item, at)` :74-80
(`at` = staff arrival). Order flow `order()` :163-268: label `"CLUB OCEAN <label> (<tableId>)"` :211, charge :212,
`Show.start({player, item, tableId, onArrive})` :233-246, no slot → `setTable(now+2)` + hook `stamp` :248-252 (served
without a show), `addStats` :154-157. Door booking `reserve()` :272-306 (basic set, shows through `Show.start`).
Note `publish()` drops the exact `item` (only `set`, which equals the item id) and keeps the table's BEST tier.

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
Order of writes inside `begin`: `Show` first, then `Tables`. `id` restarts at 1 per server.

**Booking** — `P/ServerScriptService/GwangalliClub/Booking.ModuleScript.luau:190-211`
```
{ id, table, owner, name, md, at, path, y, total, serve, centre, arriveAt, seatedAt, endAt,
  guests = { { id, name, g, tier (1..5 affinity tier), seat = "x,y,z,yaw"?, lines = { arrive, talk = {..}, laugh, dance, bye } } },
  act = { kind = ""|"cheers"|"dance"|"number"|"bye", at, n, untilT?, results?, lines? }, rev, aa, flags? }
```
`{id = 0}` when none (:26-32). `start()` :87-222 (hold :212, social `joint` table/club at arrival :215-220);
`act()` :249-317 (cheers/dance/number/bye; owner only; ≥ seatedAt-1; 2.5 s cooldown).

### 1.5 Club.server (ServerScriptService.Club) — hook + legacy
`P/ServerScriptService/Club.Script.luau`
* Header :1-46 (ShowEpoch, paid door, ClubShowHook, legacy tables/parades, life-game hooks).
* `ShowEpoch` = `math.floor(serverNow())` at start, written on every `ClubRuntime` model :295, :314.
* LED banner attrs on ClubRuntime :302-310 (`WallMsg`, `WallMsgKind`, `WallMsgAt`, `WallMsgFor`, `WallMsgSerial`);
  `setWall` :351-362, `queueWall` :366-376 (ASCII only via `ledName` :168-179).
* House parade `startParade` :518-535 (`ParadePath`, `ParadeTable`, `ParadeAt` on ClubRuntime), schedule loop :541-567.
* `stampBottles(rec, at, by)` :1049-1053 → table Model attrs `BottleAt`, `BottleBy` (ClubLights builds sparkler bottles).
* **ServerStorage.ClubShowHook** :1452-1539 — methods we will call (server only):
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
* `ClubRemote` (ReplicatedStorage RemoteEvent) :184-195; actions `order`, `doorPay`, `doorAsk`, `dance` :1541-1559.
* `ServerStorage.ClubGameplayEvent` (BindableEvent) :197-208: `:Fire("vipTable"|"birthday"|"entry", player)`.
* Player attr reply `ClubOrder = "<status>|<TableId>|<serverTime*10>"` :627-632.

### 1.6 ClubShared (ReplicatedStorage) — show clock, Bus, paths
`P/ReplicatedStorage/ClubShared.ModuleScript.luau`
* `BPM = 126`, `BEATS_PER_BAR = 4`, `SHOW_BARS = 64` (~122 s cycle) :12-14. Tags :17-34 (ClubVenue, ClubRuntime,
  ClubZone, ClubLight, ClubFloorTile, ClubLaser, ClubCO2, ClubConfetti, ClubSparkler, ClubHaze, ClubNPC, ClubFX,
  ClubMirrorRay, ClubShowBeam, ClubTable, ClubIDCheck). Attr names :35-70. Names :71-81.
* **Client Bus** :112-128 (ModuleScript cached per peer, so every LocalScript sees the same table):
  `state ("Idle"|"Near"|"Inside"), zone, showRoom, section (intro|build|drop|breakdown|groove), live, bpm, energy,
  beatAt, beatSerial, dropAt, dropSerial, countdown, photoAt, playerDanceAt, night`. ClubLights WRITES
  state/zone/showRoom/night (zone tick) and section/live/bpm/energy/countdown/beatAt/beatSerial/dropAt/dropSerial
  (`P/StarterPlayer/StarterPlayerScripts/ClubLights.LocalScript.luau:2595-2605, 2709-2711, 4501`).
  **Inputs** ClubLights READS: `photoAt` (LED photo moment), `playerDanceAt` (guests near the local player cheer).
* Parade timing :202-211; `paradeAt` :215; **`paradePath(route, dest, maxLeg, ext, clear?)`** :238-308;
  `pathLength` :310; `encodePath` / `decodePath(s, y)` :319-342 ("x,z;x,z" ≤ 64 points); `PARADE_MAX_LEG 60`, `PARADE_EXTEND 48`.
* Show script: `Sections` :372-379 (intro 0-16, build 16-24, drop 24-40, breakdown 40-48, build 48-56, drop 56-64),
  `Cues` :382-395 (CO2 bars 24/32/56/60, Confetti 24/56, Sparkler 40-48, ColdSpark, Flame, LowFog, MirrorBall),
  `Palettes` :406-413, **`clock(serverTime, epoch, bpm?, out?)`** :422-446.
* `ledText` / `textColumns` :513-559 (the pixel wall can only show A-Z 0-9 and some punctuation).

### 1.7 ClubLights (client, 4560 lines) — what it drives
`P/StarterPlayer/StarterPlayerScripts/ClubLights.LocalScript.luau`
* Header :1-56. Two modes: LIVE (ClubMusicShared onsets / bpm / level, sections from loudness, DROP from the
  detector) and CLOCK (126 BPM 64-bar clock from `ShowEpoch`; `currentEpoch()` :3951-3959).
* Quality tiers :114-220 (+ touch derive, saver :300-336). Show writes budgeted (low 20 Hz × 48 writes).
* Registries by tag :556-919: ClubLight `Kind` → colour items / fixtures (MovingHead, Beam) / Kinetic / MirrorBall /
  Strobe / Blinder; ClubFloorTile (48); ClubLaser beams :790-807; CO2 / Confetti / Sparkler / Haze / FX / rays / pins.
* LED wall = 352 pixel parts (main, Kind Wall, Row 0..10 × Col 0..31) + 96 side pixels (`Screen = "Side"`).
  Overlays :2611-2706: priority photo → flash → DROP → countdown (8..1 over the last 2 bars of a build,
  :2547-2551) → `WallMsg` banner (vip/birthday/welcome) → NOW PLAYING. Idle patterns: "CLUB OCEAN" scroll in
  intro/breakdown, EQ / rings / logo flash in build/drop (`wallColour` :2808-2840).
* Lasers :3308-3428: active only in visible rooms (Main/Lobby/Corridor) and `fanK | drop | breakdown | build
  (bar≥2) | intro (bar≥12)` (:3356-3358); patterns fan (after drop) / tunnel (intro, breakdown) / sweep (build) /
  three drop variants; re-aimed at 30 Hz, `a1.Position` + `beam.Enabled` + `beam.Color` written every update.
  → **Never write to ClubLaser beams; they would be overwritten within 33 ms.**
* `dropMoment` :2708-2717 (CO2 + confetti + crowd jump), `computeFrame` → Bus :2583-2607.

### 1.8 ClubMusic (server + client + shared) — tracks / BPM / DJ
`P/ServerScriptService/ClubMusic.Script.luau:1-20` — playlist from `MusicAssetId` override → DataStore cache
`ClubOceanMusic_v1` → `AssetService:SearchAudio(Async)` (Monstercat / APM / EDM...). Publishes `TrackId, TrackTitle,
TrackArtist, TrackStart, TrackLength, TrackBpm, TrackSerial, NextTrackId, MusicState, MusicOwner` on ClubRuntime and
`ReplicatedStorage.ClubMusicState`. No skip / request API; override tracks are titled "CLUB OCEAN 광안" by
"Resident DJ" (:493).
`P/ReplicatedStorage/ClubMusicShared.ModuleScript.luau:1-24,406-431` — client signal `Beat:Connect(fn(intensity,
isDrop))`, `Drop:Connect`, `level()`, `bpm()` (126 fallback), `isLive()`, `nowPlaying()`.
**DJ role: none for players** (grep: only NPC `People/DJ_009`, `People/MC_010`, anchor `Show_DJ`, the show's
`djLine` bubble). ClubDance is a dance button bar, not a DJ.

### 1.9 GwangalliClubShow client (the existing show layer)
`P/StarterPlayer/StarterPlayerScripts/GwangalliClubShow.LocalScript.luau:100-144` reads ShowEvent + the three JSON attrs.
* Core `P/.../GwangalliClubShow/Core.ModuleScript.luau`: optional modules :38-55 (GwangalliUI as `K`, GwangalliLayout,
  GwangalliQuality, ClubMusicShared, GwangalliNight), `Core.anchor(name)` via tag ClubShowAnchor :113-125, local folder
  `Workspace.GwangalliClubShowLocal` :207-218, single PreRender job driver :130-202, rig pool via GwangalliNPCLooks +
  GwangalliAnim :400-460.
* LED overlay `Z/StarterPlayer/StarterPlayerScripts/GwangalliClubShow/Show.luau:55-129`: Part `ClubShowLED` = anchor
  size at `Show_LEDWall` CFrame (:64), SurfaceGui Front, PPS 9, LightInfluence 0, Brightness 2.6, MaxDistance 230,
  **ZOffset 1** (:74); purple→navy→teal gradient; GothamBlack white title w/ magenta stroke + gold/white/cyan shimmer;
  cyan sub. `Show.led(title, sub, seconds)` :131-153.
* Show choreography `play(rec)` :473+: at `rec.at` (tier≥2) dim + `Show.led(thanksTitle, "<name>님 · <label>",
  holdEnd-now+2)` (:537); DJ bubble at `rec.at+1.5` on `Show_DJ` + `Bus.playerDanceAt` (:544-546); at arrival
  cheer + royal confetti/CO2 on the next beat (:551-555); staff rigs `ClubShowStaff<i>`, middle one holds a lit
  name board "<name>님 감사합니다".
* Booking client `P/.../GwangalliClubShow/Booking.ModuleScript.luau:296-336`: at `rec.at` `Show.led(bookingTitle,
  "<md> · 새 친구 n명이 <name>님 테이블로!", until presentEnd)`, dim, spot to `Show_HallDoor`; rigs named
  `ClubShowMD` / `ClubShowGuest<k>` (:430) under `Workspace.GwangalliClubShowLocal`.
* 합석 action card `Z/.../GwangalliClubShow/Ui.luau:570-651`: Panel "HapseokCard" 240×132 in the GwangalliLayout
  `topRight` slot (짠 / 같이 춤 / 번호 교환 / 잘 가요 → `ShowRequest("act", kind)`).

### 1.10 ClubRanking (GwangalliBuildings, v7 zip) — already shipped ranking
Server `Z/ServerScriptService/GwangalliBuildings/ClubRanking.luau`
* Contract :2-25: folder `ReplicatedStorage.GwangalliClubRanking`, attrs `Top` = `{ night, list = { {u, n, t} } (top 5), king }`,
  `Zones` = `{ {x,y,z,sx,sy,sz} }`; RemoteEvent `Fx` FireAllClients `{kind = "order"|"king"|"booking", table, name, u,
  item, tier, price, total, rank, prev, gap?, chase?, centre?, dethroned?, guests?, untilT?}`.
* Night `nightOf(unix) = floor((unix + 9h - 6h) / 86400)` :62-64. ODS `"GwB_ClubSpend_" .. night` :136-144; flush 20 s,
  sync 60 s, Studio → memory only :146-153.
* Board `Workspace.GwangalliBuildings.ClubRankingBoard` on the main room's SOUTH wall (raycast from MainRoom bbox
  centre along `-club:GetPivot().RightVector`, y 20.5, fit between wall things, 16..28 × 12.5) :290-405.
* Order detection = `Tables[id].at` changes (primed after first read) :528-550, exact item from `Show` when
  `|Show.arriveAt - at| < 0.05` :519-525; booking from `Booking.id` change :553-573.
Client `Z/StarterPlayer/StarterPlayerScripts/GwangalliBuildingsClient/ClubRanking.luau`: ScreenGui
`GwangalliClubRankingFx` DisplayOrder 40, top-centre cards at y 118 px (:101-194); board banner/frame flash + table
sparks (:256-297); 합석 party beams (:300-359); crown BillboardGui "👑 오늘 밤 큰손" over #1 (offset 3.2) (:364-403).

### 1.11 Money
* `ServerStorage.GwangalliGameplayAPI` is defined TWICE and the second wins:
  `Z/ServerScriptService/GwangalliGameplay/Life.luau:677-745` (setupClubApi: spend(amount,label,prefer) / addStats
  (clamped ±20) / balance / clubState / clubGrant / allowTeleport) is called from `Life.init` (`Z/.../GwangalliGameplay.luau:471`),
  then `Z/ServerScriptService/GwangalliGameplay.luau:481-496` replaces `OnInvoke` with the unified wallet:
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
  → effective ops: `balance` (0,0 when no profile), `spend` (no bank preference; cash first then 체크카드),
  `earn` (bank credit), `addStats` (NOT clamped — clamp ourselves to ±20). `clubState`/`clubGrant`/`allowTeleport`
  return `false` today. Code must work with both handlers.
* Income boost: `Z/ServerScriptService/GwangalliGameplay.luau:304-320` — `ctx.ledger` multiplies positive income by
  1.2 for `GwPassIncome` holders unless the label contains one of `INCOME_SKIP` (:309: 환불, 반환, 취소, 송금, 입금,
  출금, 받음, 빌려, 지원금, 매각, 매도, 정산, 상금, ...). Any `earn` we do (refund / DJ share) MUST carry "환불" or
  "정산" in its label.
* Bank (`Z/ServerScriptService/GwangalliGameplay/Bank.luau:1-36`): player↔player 송금 / 현금 주기 live inside the
  gameplay ctx — no server API for add-ons. We do not move money between players (except the optional DJ share).
* Reference prices: CVS shift ~28-33k원 (ShowShared :93-94), door 30k/50k, bottles 90k-1.2M, legacy
  `ClubShared.Menu` 150k/300k/250k (LiveConfig-bound, happy-hour multiplier) `P/ReplicatedStorage/ClubShared.ModuleScript.luau:85-89`.

### 1.12 Social / roster
* `ServerStorage.GwangalliSocialAPI` (`Z/ServerScriptService/GwangalliGameplay/Relationships.luau:32-49`):
  `affinity(id) -> a, tier`, `tier(id) -> tier, name`, `award(id, source, amount?)`, `joint(activity, ids?)`,
  `perk(kind, arg?)` (clubEntry, vipDiscount...). Sources (`Z/ReplicatedStorage/GwangalliSocialShared.luau:170-210`):
  `play` (같이 놂, base 3, max 2), `hangout`, `club`, `dance`, `drink` (음료 삼), `table`, `number`... (capped by the
  social system). Tiers :90-97: 모르는 사이 🤍 / 아는 사이 💛 / 친한 사이 🧡 / 친구 💖 / 절친 💞 (with colours).
* `ReplicatedStorage.GwangalliCitizens` (`Z/ReplicatedStorage/GwangalliCitizens.luau:8-30`): `byId[id] = {name, age, g,
  job, topics, accent = {r,g,b}, club, look, ...}`, `TOPICS[t].label` (:1075+, e.g. "맛집"), `smallTalk`, `greeting`,
  `numberLine`. Example guest: 이서연 · 22 · 대학생 (광고홍보학과) · topics photo/fashion/club.

### 1.13 Gates / player attributes
* Wristband: `ClubOceanWristbandUntil > workspace:GetServerTimeNow()` (Club.Script :692-699). Players without one
  are walked out of non-Near zones every 2 s.
* Journey: `GwJourneyClub` = "locked" | "hinted" | "open" (absent = open) (`Z/.../Play/Journey/Club.luau:5-12`).
* `ClubVIP`, `ClubVIPTable`, `ClubGuestList`, `ClubOrder` (ClubShared.Attr :65-69).

### 1.14 UI style + layout + quality + live config
* GwangalliUI kit `P/ReplicatedStorage/GwangalliUI.ModuleScript.luau:1-36` (API list), tokens :41-107: dark glass navy
  (glass 15,18,31 @ 0.14), cyan #3DD6F5, magenta #FF4FA3, gold #FFC247, violet #8B6CFF, green #3DDC84; fonts Gotham /
  GothamMedium / GothamBold / GothamBlack; type 28/22/18/15/14/12/11; radius 12/16/20/24; `K.Kinds.club` violet 🎶.
  Components: `K.BottomSheet(host, {title, subtitle, side = "bottom"|"right", width, onClose})` :2610-2614,
  `K.Button(parent, {text, style = primary|secondary|tonal|ghost|gold|bridge|..., onClick})` :1536-1538, `K.Tabs`,
  `K.Chip`, `K.ListRow`, `K.MoneyLabel`, `K.confirm`, `K.toast({kind, title, body, icon})` :2959, `K.won`, `K.countUp`,
  `K.shimmer`, `K.pop`, `K.pulse`.
* GwangalliLayout slot contract `P/ReplicatedStorage/GwangalliLayout.ModuleScript.luau:24-60`: topLeftChips, topCenter,
  topRight (합석 card lives here), rightColumn(.phone/.travel/.sprint), bottomCenter (Now Playing; ClubDance bar sits
  right above it), sheetRight (modal side sheet: disable controls), toasts, dialog. `Layout.rect(slot)`,
  `Layout.zones()` (thumb / jump), `Layout.onChanged(fn)`. Convention: a ScreenGui with `HideGwangalliHUD = true`
  asks HUD layers to step aside.
* Existing on-screen club UI: ClubDance bar (bottomCenter+), GwangalliClubShowUI sheets (DisplayOrder 46,
  sheetRight/bottom), 합석 card (topRight), ClubRanking cards (top centre, DisplayOrder 40), Now Playing (bottomCenter).
* GwangalliQuality `get()` → low|mid|high, `isSaver()`. GwangalliNight `hype()`.
* GwangalliLiveConfig (`Z/ReplicatedStorage/GwangalliLiveConfig.luau:12-22,123-136`): `Live.get(key)`, `Live.enabled(id)`
  (true when unknown), `Live.happyHour()`, `events.club.themeNight` ∈ none|hiphop|edm|kpop|retro|white|neon
  (labels "EDM 나이트" ...), `events.happyHour.multiplier` (club prices).

### 1.15 Marketplace / receipts / OrderedDataStore (confirmed)
* `ProcessReceipt`: assigned NOWHERE (place dump + all 381 zip/add-on files). The only mention,
  `Z/ServerScriptService/GwangalliGameplay/Arms/SpecialBox.luau:4-5,27`, says explicitly it never assigns it ("a place has
  exactly one; the future central receipt handler owns it"). No `PromptProductPurchase` / developer products.
* Game passes only: `ReplicatedStorage.GamePassConfig` + `GwangalliStore` (PromptGamePassPurchase) +
  `ServerScriptService.GwangalliPassPerks` (`GwPass_<key>`, `GwPassIncome`, `GwPassSpeed`).
* `GetOrderedDataStore`: `GwangalliBuildings/Royal` (`"GwB_Arcade_" .. game .. "_" .. day`) and ClubRanking
  (`"GwB_ClubSpend_" .. night`). Other club DataStore: `ClubOceanMusic_v1` (playlist cache).
* → GwangalliClubPlus sells nothing for Robux and never touches `MarketplaceService.ProcessReceipt`.

### 1.16 Geometry (from place.bin; world space; the club model is rotated ≈ -89° about Y)
* Anchors (tag ClubShowAnchor, under `CLUB OCEAN 광안/ClubShowAnchors`):
  `Show_LEDWall` CF pos (-72.88, 23.82, 373.99), size 56 × 17.05 × 0.1, LookVector ≈ (-1, 0, -0.015) (front face into the
  room); `Show_DJ` (-98.78, 17.5, 373.70); `Show_Floor` (-106.83, 10, 373.48); `Show_SpotRig` (-119.62, 27, 373.29);
  `Show_StaffDoor` (-153.39, 10, 410.69); `Show_Lobby` (-186.33, 10, 386.59); `Show_HallDoor` (-174.23, 10, 386.77);
  `Show_HallTurn` (-157.27, 10, 389.02).
* Main LED: `MainRoom/LEDWall/LEDWallFrame` (-71.8, 23.6, 374.0) 56.8 × 17.8. Side LED: `MainRoom/ServiceStation/
  SideLEDFrame` (-118.8, 23.3, 411.8) 58.4 long × 15.6 tall (x -148..-89.6), 96 pixels facing -Z into the room.
* Lasers: `MainRoom/Lasers/LaserEmitter` ×4 at (-98.0, 26.9, 361.6), (-98.4, 26.9, 385.6), (-73.3, 31.8, 347.4),
  (-74.1, 31.8, 400.6) (+ LaserAperture), 8 ClubLaser beams each.
* DJ booth: BoothPlatform (-98.7, 8.6, 373.7) spans x -101.7..-95.7, z 361.8..385.6, top y≈10.15; DJDesk (-99.4, 11.9,
  373.7); MirrorBall (-111.1, 23.9, 373.4); Kinetic tubes y 27.9 x -126.9..-103.3; LED dance floor (48 tiles) around
  `Show_Floor` — nothing may be placed on it.
* ParadeRoute (ClubRuntime/ParadeRoute, TargetTable G2) WP1..8: (-143.1,10,404.2) (-152.5,10,404.1) (-152.3,10,392.1)
  (-91.4,10,393.0) (-91.3,10,383.6) (-82.6,10,383.7) (-82.5,10,376.0) (-81.6,10,373.0).
* 31 tables: T1-T10 Standing (4), S1-S6 Bar (4), D1-D3 DJ (4), B1-B8 Booth (6), G1-G4 VIP platform (8/8/8/6).
* Zones (ClubRuntime): Main (-124.2, 19.5, 376.9) 70×26×105, HipHop, Lobby (-198.2, 12.5, 375.8) 62×12×41, Corridor,
  Restroom ×3, VIPStair, Lounge, Terrace, Near (310×78×237, Priority 1).
* Free mount candidates (non-colliding, wall/ceiling hung): under the MainBar canopy long beams
  (`MainBar/BarCanopy/CanopyBeam` at y 20.2, z 364.4 and 381.4, outer CanopyLED at z 363.4 / 382.5) → "bar TV" boards
  y 16.9-19.7 facing ±Z; lobby ceiling (`Lobby/LobbyCeiling` underside y 17.55) → hanging double-sided screen around
  (-184.5, 15.7, 380) facing ±X (lane tunnel → hall door). Mezzanine fascia (x -156.9, y 17.75-19.85, z 341-394) is
  occupied by FasciaLED + "CLUB OCEAN · 광안" sign and the wayfinding HangingSigns hang behind it (x -159/-160, z 356 / 387)
  → not used.

---------------------------------------------------------------------------------------------------

## 2. What exists vs. what is missing

| Target | Exists today | Missing (GwangalliClubPlus adds) |
|---|---|---|
| 전광판 order animation with nickname | Korean overlay "G2 테이블 감사합니다 ✨" + "<name>님 · <label>" fades in for the whole show (tier ≥2); staff name board; DJ bubble; ClubRanking banner on its board; pixel wall only ASCII "VIP NAME" (legacy) | Tier-scaled cinematic intro (stinger, big nickname reveal on the beat, item icon, price count-up, rank badge "오늘 밤 2위 · 1위까지 ₩…", 👑 1위 탈환 stamp), side-LED mirror, lower-third name strip while their title shows, a ticker of the night's events |
| 후원 (paid shout-outs) | nothing (no paid LED messages, no tips) | 전광판 후원: 기본 / 스페셜 / 레전드 grades, templates (생일, 환영, 감사, 응원, 크루, DJ 리스펙, 직접 쓰기 filtered), target (나 / 클럽 안 플레이어 / 테이블), queue + receipts |
| Ranking boards | 오늘 밤 큰손 TOP 5 (cross-server ODS) + crown + cards (ClubRanking) | 오늘 밤 후원왕, 이번 주 큰손 TOP 10, 명예의 전당 (역대 최고 단일 주문 / 하룻밤 최고 / 최다 후원), 오늘의 인기 테이블; "bar TV" boards + lobby TONIGHT screen + 랭킹 sheet with 내 순위 |
| Laser show | ClubLights house lasers (fan / tunnel / sweep, 30 Hz) | Own rig: TableLock (beams converge on the ordering / gifted table), Parade Follow, Crown, scheduled 8-bar "OCEAN LASER SHOW" in the house show's quiet intro bars, DJ-triggered cues (P2) |
| Bottle parade | Staff line with sparklers, name board, spotlight, dim, confetti (royal); house parade every 150 s | Light carpet unrolling under the staff, laser follow, crowd cheer pulses, gift parades to OTHER tables (테이블 선물) with recipient thanks |
| 합석 production | MD + 2-4 roster guests walk in, sit, bubbles, 짠/춤/번호/잘 가요, ClubRanking party beams | "MD 매칭" LED profile cards, guest name tags with affinity tier, walk-in light carpet + laser follow, ⚖️ 밸런스 게임 at the table (affinity via `play`), 📸 단체 사진 (LED countdown + polaroid), 📝 합석 리포트 |
| DJ | none for players | (P2) 게스트 DJ 타임: booking, DJ pad cues, ON AIR lower-third, crowd reaction |
| Robux | game passes only; no ProcessReceipt | none (by design) |

---------------------------------------------------------------------------------------------------

## 3. Conflicts / risks and how we avoid them

1. **LED overlay overlap.** Their `ClubShowLED` SurfaceGui sits AT the anchor CFrame with ZOffset 1 and stays up for the
   whole show (`Show.led(..., holdEnd - now + 2)`) and the 합석 intro. ClubLights' pixels show countdown / DROP / photo.
   → Our canvas part is 0.2 stud in front (always draws over theirs). Client LED scheduler rules:
   (a) order intro (ours) plays only in [Show.at, Show.at + intro] (2.2-8 s by tier) — exactly while the room dims and the
   first staff steps out — then we collapse to a 16 % lower band (their title/sub stay visible);
   (b) our paid cues get full-screen only in free windows (no official show / 합석 intro overlay, no countdown);
   otherwise they run on the side LED (no official overlay there) + the main lower band;
   (c) whenever `Bus.countdown > 0` or `os.clock() - Bus.dropAt < 2.2` our main full layer fades to 0 in 0.15 s
   (the drop belongs to the house show); the lower band may stay.
   The server scheduler also avoids the clock-mode countdown windows (bars 22-24.9 and 54-56.9 from ShowEpoch).
2. **Lasers.** ClubLights writes ClubLaser beams every 33 ms → we create our own Beams/Attachments in
   `Workspace.GwangalliClubPlusLocal`; distinct palette (ocean green 30,255,140 / gold 255,196,60); never run our big
   patterns during `F.fanK` (first 4 beats after a drop).
3. **Bus.** Write only the documented inputs (`playerDanceAt` for a local crowd cheer). Never write section / beat /
   drop / countdown / photoAt (photoAt would trigger ClubLights' own LED photo + nothing else; our photo is our canvas).
4. **ColorCorrection / Lighting.** The show adds `Lighting.ClubShowDim`; ClubLights grades the room. We add no
   Lighting effects.
5. **NPC rigs.** ClubLights / ClubCrowd own `ClubNPC` rigs (tags + LocalTransparencyModifier). GwangalliClubShow owns its
   staff / MD / guest rigs. We only ADORN their guest heads with BillboardGuis (in PlayerGui) and build our own gift
   staff rigs from GwangalliNPCLooks/GwangalliAnim in our own folder.
6. **Parades.** Our gift parade holds the house parade (`ClubShowHook hold`) and starts only when no official show is
   walking (`Show.endAt` passed, Booking walk-in done); an official show that starts mid-gift simply overlaps (local rigs,
   no collisions). Max 3 gifts queued.
7. **Ranking duplication.** If `ReplicatedStorage.GwangalliClubRanking` exists (wait ≤ 60 s) we reuse its `Top` and do not
   build any "오늘 밤 큰손" board; our boards show other categories. If it is missing we add a 큰손 page computed by us
   (separate ODS name `GwClubPlus_Spend_<night>`). Our order cards never duplicate ClubRanking's screen cards
   (we show world FX only; the buyer gets one K.toast only when ClubRanking is absent).
8. **Order event semantics.** One `Show` write per show; queued shows publish when they begin; `id` restarts per server
   → dedupe key = `id .. "@" .. at`. Orders served without a show → `Tables.at` change with no matching `Show`.
   `Tables.set` keeps the best tier (a lower order on a higher table is priced as the better set — same as ClubRanking;
   acceptable edge case).
9. **Money.** Unified wallet: `spend` ignores the bank preference, `balance` returns 0,0 without a profile, `addStats` is
   not clamped, Life-only ops return false. → Check `balance` first; reserve the queue slot BEFORE charging; charge with
   8 s timeout (+ paid-late honour); clamp stats ±20; refunds only via `earn` with "환불" in the label (no 1.2× boost).
   No API → features are free (like the club) with stricter cooldowns, and the sheet says "이벤트 무료".
10. **Remote abuse.** Token bucket (6 @ 1.5/s), per-op cooldowns, one paid op in flight per player, request ids (`rid`)
    dedupe double taps (same as Bank), strict payload types/lengths, enum ids only (server prices), target must be a
    current player inside the club, table ids must come from `ClubShowHook tables`, sender must be `inClub` + wristband
    + Journey not "locked".
11. **Text safety.** Free text ≤ 20 chars → `TextService:FilterStringAsync(text, sender.UserId, PublicChat)
    :GetNonChatStringForBroadcastAsync()`; reject (no charge) if it fails or comes back mostly '#'. Names only from
    the existing filtered names or our `filteredName` (same method as GwangalliClub). Targets can opt out
    (player attr `GwClubPlusNoTag`, toggle in the 랭킹 sheet ⚙️) — then "그 손님은 전광판 이름 표시를 꺼 두었어요".
    Sender → same target cooldown 5 min. No romance / alcohol templates.
12. **Performance (phones).** LED = UI tweens (TweenService, no per-frame Lua except count-ups ≤ 1.2 s); lasers 30 Hz with
    tier caps (high 24 beams / mid 12 / low 4 / saver 0); light carpet ≤ 40 segments (low 16); our parade rigs ≤ 3 (low 2,
    saver 1, pooled). Everything idles unless `Bus.state == "Inside"` (or Near for the lobby screen). Server: no per-frame
    work, 0.5 s tick.
13. **Streaming.** Anchors / tables may stream out: client looks them up by tag each time it needs them; all our world
    visuals are client-local; boards are client-built from replicated attributes (no server parts).
14. **Interior team.** GwangalliBuildingInterior may locally hide map parts and add `Workspace.GwInteriorDetailLocal`.
    Our wall/ceiling raycasts exclude that folder and ours; we never parent GUIs under map parts (all SurfaceGuis /
    BillboardGuis live in PlayerGui with `Adornee`); our props on table tops use the table top height (unchanged by them).
15. **UI overlap.** Rail of 3 buttons on the LEFT edge between `topLeftChips` bottom and the thumbstick zone top
    (`Layout.rect`, `Layout.zones`), so it never touches ClubDance (bottom), Now Playing (bottomCenter), 합석 card
    (topRight), toasts (top). Sheets use `sheetRight` (landscape) / bottom (portrait), set `HideGwangalliHUD` and pause
    controls like GwangalliClubShow Ui. Our 합석 extra buttons sit directly under their 132 px card in the topRight rect.
16. **Studio/engine quirks.** Spherecast / newer APIs pcall'd (same fallbacks as Club.server legClear).

---------------------------------------------------------------------------------------------------

## 4. Add-on design

### 4.1 Player-facing features (Korean names)
* **📺 전광판 연출** — every bottle order gets a tier-scaled LED intro with the buyer's nickname (automatic).
* **🎤 전광판 후원** — pay to put a nickname + message on the LED wall (기본 / 스페셜 / 레전드).
* **🎁 테이블 선물** — send a set to another occupied table; staff parade it over; the recipient can send 💙 고마워요.
* **🏆 랭킹** — bar TV boards + lobby TONIGHT screen + 랭킹 sheet (오늘 밤 큰손 · 후원왕 · 이번 주 · 명예의 전당 · 인기 테이블).
* **🟢 OCEAN LASER SHOW** — our laser rig: table lock-ons, parade follow, scheduled 8-bar shows.
* **✨ 합석 프로덕션** — MD 매칭 cards, name tags, 밸런스 게임, 단체 사진, 합석 리포트.
* **🎧 게스트 DJ 타임** (phase 2, `Config.DJ.Enabled = false` by default).

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
`ReplicatedStorage.GwangalliClubPlus` (Folder, created by the server, parented last) with RemoteEvent **`Request`**
(client → server: `(op: string, payload: table)`) and RemoteEvent **`Event`** (server → client: `(kind: string, payload: table)`).
No RemoteFunctions.

Client → server ops (all payload fields validated; unknown fields ignored):
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
Player attributes: `GwClubPlusTonight` (원 tonight: orders + shouts + gifts), `GwClubPlusWeek` (원 this week),
`GwClubPlusNoTag` (bool).

### 4.6 Data saving
* Keys: `night = floor((unix + 9h - 6h) / 86400)` (same as ClubRanking / the door), `week = floor((night + 3) / 7)`
  (Monday 06:00 KST; night 0 = Thu 1970-01-01).
* ODS `GwClubPlus_Shout_<night>` (uid → 원: shouts + gifts), ODS `GwClubPlus_Week_<week>` (uid → 원: orders + shouts + gifts),
  ODS `GwClubPlus_Spend_<night>` ONLY when ClubRanking is absent. DS `GwClubPlus_Records_v1` key `records`
  (UpdateAsync only when a record breaks). Optional DS `GwClubPlus_Player_v1` key `<uid>` `{v=1, life, shouts, gifts,
  bestRank, titles}` (P2).
* Write path: pending deltas per uid, flush every 30 s with `UpdateAsync(old + delta)` (failed deltas re-queued),
  `GetSortedAsync(false, 10)` every 60 s per board, `BindToClose` flush, Studio / 403 → memory only (ClubRanking pattern).
* Night rollover: switch keys before yielding, flush old pending into the old night (ClubRanking :456-469 pattern).
* Table popularity tonight: server memory only (table ids are per night, no need to persist).

### 4.7 Prices / limits (server-authoritative, `GwangalliClubPlusShared.Config`)
| Item | Price | What it does | Limits |
|---|---|---|---|
| 전광판 기본 | 30,000원 | lower band 10 s + ticker + side LED 6 s | player 45 s cooldown |
| 전광판 스페셜 | 80,000원 | main full 8 s (free window, else side full + lower) + sparkles + crowd cheer | queue ≤ 6 |
| 전광판 레전드 | 200,000원 | main full 14 s + laser Crown/TableLock + UI confetti + CO2 puffs on the beat + MC bubble at Show_DJ | 1 legend in queue at a time |
| 🍓 과일 플래터 선물 | 50,000원 | 1 staff, tray, lower band "🎁 B3 → G2" | player 60 s, gift queue ≤ 3 |
| 🧃 스파클링 주스 타워 | 150,000원 | 2 staff + sparklers, LED full 6 s, ClubLights bottles at arrival | same |
| 🎁 오션 기프트 박스 | 400,000원 | 3-staff parade + name sign + laser follow + confetti | same |
| 💙 고마워요 (thanks) | free | lower band one-liner from the recipient | once per gift |
| 🎧 게스트 DJ (P2) | 100,000원 / 4분 | ON AIR + 6 pads | 1 at a time, 10 min per player |
Happy hour (`Live.happyHour()`) multiplies these like club prices; `Live.enabled("clubplus") == false` turns the add-on off.
Stats: shout `{happiness = 2 + grade, popularity = grade}`, gift `{happiness = 3 + tier, popularity = tier}`.
No API → free, 2× cooldowns, menu shows "이벤트 무료".

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
Server subscribes to `GetAttributeChangedSignal("Show"|"Tables"|"Booking")` on `ReplicatedStorage.GwangalliClubShow`
(`WaitForChild` 120 s). Priming like ClubRanking (no events for the state found at start).

**Stage.luau** — one timeline for every LED / laser / parade moment.
```
Stage.push(cue) -> status, at        -- finds the earliest at >= now+0.6 where all lanes are free and (mode "full")
                                     -- no official window / countdown overlaps; downgrades full -> side+lower after 90 s
Stage.reserve(cue) -> token ; Stage.confirm(token) ; Stage.cancel(token)   -- reserve before charging
Stage.tick()                         -- publishes Stage attr when now/next change; schedules the laser show
```
Order events become cues `{kind = "order", at = rec.at, lanes = main(intro by tier) + lower(until endAt) + laser
(tier ≥ 3: arriveAt .. +4 beats)}` — they are never delayed (they follow the official show). Laser show: every 3rd
show cycle at clock bar 4 (`epoch + (k*64 + 4) * 60*4/126`), 8 bars, lanes laser + lower.

**Shout.luau** — `Shout.menu(p)`, `Shout.request(p, payload)`: gate → rid dedupe → cooldowns → template/grade/target
validation (target player in club + not `GwClubPlusNoTag`; table owned in `Tables`) → text filter (yields; re-check
gate after) → `Stage.reserve` → balance check → `C.charge(p, price, "CLUB OCEAN 전광판 후원 (스페셜)")` → confirm or cancel →
`Ranking.add(uid, name, price, "shout")` → receipt with position and ETA.

**Gift.luau** — validation (target table has a valid `Tables` owner who is in the server and not the sender; reach not
required, gate required) → reserve → charge `"CLUB OCEAN 테이블 선물 (G2)"` → path: lead `Show_StaffDoor` + `ClubShowHook
route` WP2..n + `ClubShared.paradePath(..., legClear)` to `tableInfo.serve` (copy of GwangalliClub `C.pathTo` :211-265) →
timing from `ShowShared.Show` (`showLength`, arrival like Show.arrival :79-84) → publish `Parade` when it starts (after
any official show / 합석 walk-in), `hook("hold", endAt - now + 4)`, `hook("stamp", table, arriveAt, senderUid)` for tier ≥ 2,
`Stage.push` LED cue at arrival, `Event "gifted"` to the recipient, `Ranking.add(..., "gift")`, `Ranking.tableHit`.

**Ranking.luau** — `Ranking.add(uid, name, amount, cat)` (cat = order/shout/gift), `Ranking.tableHit(table, kind, n)`,
`Ranking.rankOf(uid) -> rank, total` (ClubRanking `Top` when present for orders), pages + records → `Boards` attr every
change (debounced 2 s), player attrs, persistence (§4.6). On every order evt: enrich with rank (`order` Event broadcast
0.4 s after the Show write so ClubRanking has published).

**Hapseok.luau** — on a new `Booking.id`: profiles from `GwangalliCitizens.byId[id]` (name, age, job, 2 topic labels,
accent) + tier from the record; snapshot `social("affinity", owner, id)`; publish `Hapseok`. Game: `hgame start`
(owner, after `seatedAt`, once per booking, not during their dance act) → 5 rounds × 12 s from `Balance.pick(seed)`;
guest picks = `Balance.answer(guestId, qId, seed)`; owner `pick` per round; reveal → chemistry; end: for each guest with
≥ 3 matches `social("award", owner, id, "play")`, `addStats {happiness = 2}`; LED lower band updates. Photo: owner,
seated phase, ≤ 2 per booking, 30 s apart → `Stage.push {kind = "photo", lanes main full 6 s, data = {table, names}}`.
Report: when the booking ends (id → 0 or endAt), affinity after → `Event "report"` to the owner.

**Dj.luau (P2)** — book at the booth (root within the BoothPlatform box + 3 studs, gate, fee); cues rate-limited per pad
(laser 8 s, co2 12 s, confetti 15 s, hands 10 s, shout 20 s, count 30 s); broadcast as Stage cues; ON AIR lower band;
optional 30 % of DJ-template shout income to the DJ via `earn` with label "CLUB OCEAN DJ 후원 정산" (no boost; cap 300,000원
per night).

### 4.9 Client modules — rendering
**Led.luau**
* Canvas: local Part `PlusLED_Main` (Transparency 1, Anchored, CanCollide/CanQuery/CanTouch false) at
  `Show_LEDWall.CFrame * CFrame.new(0, 0, -0.2)`, size = anchor size; SurfaceGui in PlayerGui (`ResetOnSpawn = false`,
  Adornee = part, Face Front, PixelsPerStud 12 → 672×205, LightInfluence 0, Brightness 2.4, MaxDistance 230).
  Side canvas `PlusLED_Side` from `SideLEDFrame` (face toward the Main zone centre), PPS 10.
* Layers: `Full` (root frame, transparent when idle), `Lower` (bottom 16 % band: name strip / ticker), `FX` (UI
  particles: small Frames tweened; count capped by `ShowShared.Q[tier].confetti / 4`).
* Templates (Cues.luau timelines, beat-quantised with `Core.onBeat`):
  - order T1 (lower only 6 s): "🧊 T3 테이블 · {name}님 · 기본 세트 감사합니다".
  - order T2 (full 4.5 s): "THANK YOU" stinger → "{name}님" big (GothamBlack, gold→white shimmer) → "{icon} {label}" →
    "₩200,000" count-up → rank badge ("오늘 밤 3위 ▲2" / "1위까지 ₩150,000").
  - T3 (+ side LED mirror, laser TableLock at arrival), T4 (rotating ray background, letter-by-letter on beats,
    gold UI confetti), T5 (8 s "OCEAN ROYAL" crown drop → huge nickname → 3-2-1 on beats → "짠~! ✨" in sync with
    their confetti/CO2).
  - king: "👑 1위 탈환!" stamp (+ "{dethroned}님을 제쳤어요").
  - shout: per template palette (🎂 pink/gold "HAPPY BIRTHDAY" + "{target}님" + "from {sender}", 🎉 "WELCOME TO OCEAN",
    💙 "고마워요", 📣 "오늘 밤 주인공은 너야!", 🔥 "{크루명} 크루 출격!", 🎧 "DJ 선곡 최고!", ✍️ filtered text).
  - gift: "🎁 테이블 선물 도착!" + "{fromTable} {from}님 → {toTable} {to}님".
  - booking (MD 매칭): "MD 태양의 오늘의 합석 ✨" + 2-4 profile cards flipping in on beats → lower "✨ 합석 · G2 · 서연 · 민혁".
  - photo: "📸 G2 테이블 단체 사진" 3-2-1 → white flash → polaroid (names, "2026.10.16 · 23:41 · CLUB OCEAN 광안").
  - laser: lower "🟢 OCEAN LASER SHOW · 손 머리 위로! 🙌".
* Local priority: drop/countdown guard (§3.1c) > order intro > official overlay (we go lower) > our full cues >
  ticker. Late join: play if `now < at + dur`, skipping elapsed steps.
* Order intros are triggered from the official `Show` attribute directly (perfect sync with `rec.at`, works even if our
  Event is late); the rank badge waits for our `order` enrichment (shown at +2.5 s, skipped if it never comes).

**Lasers.luau**
* Mounts (read-only positions): M1/M2 = DJ-booth LaserEmitters (-98.0, 26.3, 361.6) / (-98.4, 26.3, 385.6),
  M3/M4 = LED-wall top emitters (-73.3, 31.2, 347.4) / (-74.1, 31.2, 400.6) (looked up by name under MainRoom/Lasers,
  offset 0.6 down), optional M5/M6 local "floor lasers" (0.8×0.5×1 non-colliding boxes) on the booth front edge
  x ≈ -101.9, z 366 / 381, y 10.4.
* Beam pool: high 4 per mount (24), mid 2 (12), low 1 on M1-M4 (4), saver off. Beam Width 0.08→0.22, LightEmission 1,
  LightInfluence 0, FaceCamera, Segments 1; Attachment1 moved with `WorldPosition` at 30 Hz (low 15 Hz).
* Patterns (Cues.luau): `lock(P)` converge + breathing radius; `crown(P)` alternating high/low points on a ring over a
  table; `follow(fn t -> pos)`; `fan(y)` sheet over heads; `tunnel(axis)`; `scan` floor sweep. Beat from
  `Bus.beatAt/beatSerial/bpm`, section from `Bus.section`; never during `os.clock() - Bus.dropAt < 4 beats`.
* Visible only in Main/Lobby/Corridor zones and within 150 studs (ClubLights' own rule).

**Parade.luau**
* Official shows (`Show` attr) and 합석 walk-ins (`Booking` attr): light carpet of thin Neon segments (2.2 wide, 0.04 tall,
  floor y = `rec.y - 3 + 0.04`) unrolling with the leader `d(t) = (t - (at + LeadIn)) * speed`, colour by tier,
  fade 3 s after the line passes, gone by `holdEnd`; segments inside the LED-floor AABB (ClubFloorTile bounds + 1)
  are skipped. Tier ≥ 3: laser `follow` on the leader; when the leader passes within 25 studs of the local player:
  `Bus.playerDanceAt = os.clock()` (local guests cheer).
* Gift parade (`Parade` attr): our pooled rigs (GwangalliNPCLooks staff spec: black outfit + earpiece, same as their
  `staffSpec`), props: tray + fruit (fruit), juice tower bottle with sparkler (tower), gift box with ribbon + sign
  "{from}님의 선물 🎁" (box); same phases as theirs (out / hold / present / bow / back) using ShowShared helpers; local gift
  props on the target table top (side edge, 5 min) + BillboardGui "🎁 from {fromTable} {from}님" 60 s.

**Boards.luau**
* "OCEAN 랭킹 TV" ×2: local parts under the MainBar canopy long beams (positions derived at runtime from
  `MainBar/BarCanopy/CanopyBeam` parts; fallback config CFrames), 14 × 2.8, facing out (±Z); SurfaceGui in PlayerGui.
  Pages rotate every 8 s: 🎤 오늘 밤 후원왕 TOP 5 · 🏆 이번 주 큰손 TOP 10 · ⭐ 명예의 전당 · 🔥 오늘의 인기 테이블
  (+ 👑 오늘 밤 큰손 page only when ClubRanking is absent). Footer per viewer: "내 순위 7위 · ₩350,000" / "TOP 10 밖".
* Lobby "TONIGHT @ CLUB OCEAN" hanging double-sided screen (6 × 3, y 14.2-17.2 under LobbyCeiling, near (-184.5, 380)):
  지금 1위, 후원왕, 다음 레이저 쇼 시각 (K.korClock), 합석 진행 중 테이블, 테마 나이트 (LiveConfig label).
* Placement check at build time: raycast/OverlapParams against map parts (excluding our folders and
  GwInteriorDetailLocal); skip a board whose box intersects anything.

**Hapseok.luau (client)**
* Name tags: BillboardGui (PlayerGui, Adornee = Head of `Workspace.GwangalliClubShowLocal.ClubShowGuest<k>`), "서연 · 22" +
  tier chip "💛 아는 사이" (GwangalliSocialShared.TIERS colours), MaxDistance 60, only after `seatedAt`.
* Owner buttons "⚖️ 밸런스 게임" / "📸 단체 사진" (K.Button, 2 × 44 px) placed at the topRight rect, y + 132 + 8.
* Game card (topRight below, or bottom sheet in portrait): "⚖️ 밸런스 게임 3/5", two big choices, 12 s ring;
  reveal: guest bubbles over heads ("저는 바다! 🌊" + reaction "오 저도요! 🙌" / "에이~ 그건 아니죠 ㅋㅋ"), score
  chips; result "케미 지수 80%! 🔥 완전 잘 맞네요".
* Before the photo flash the client fires the EXISTING `ShowRequest("act", "cheers")` 1.2 s early (public contract,
  owner only) so the guests raise glasses; the owner's screen flashes + shows a polaroid card (HUD hidden 3 s).
* Report card on `Event "report"`: "📝 오늘의 합석 리포트" · "서연 호감도 +9 · 아는 사이 → 친한 사이!" · "번호 교환 2명 ·
  케미 지수 80%".

**Ui.luau**
* HUD rail (left edge): 📺 전광판 · 🎁 선물 · 🏆 랭킹 (+ 🎧 DJ in P2), 48 px glass circles with labels on PC; visible only while
  `Bus.state == "Inside"`, wristband valid, Journey open, no other `HideGwangalliHUD` GUI; gamepad DPadLeft focuses the
  rail (ContextActionService, only while visible); PC hotkey N opens 전광판.
* 전광판 sheet: grade chips with price + mini live preview (the same template rendered in a small frame) → template grid
  → target (나 / 클럽 안 손님 목록 / 테이블) → optional text (TextBox, 20자 counter) → confirm bar
  "₩80,000 결제하고 송출하기 · 잔액 ₩1,234,000 → ₩1,154,000".
* 선물 sheet: occupied tables (id, owner, tier icon) → set cards → note chips → confirm.
* 랭킹 sheet: K.Tabs (오늘 밤 큰손 / 후원왕 / 이번 주 / 명예의 전당 / 인기 테이블), rows with rbxthumb headshots,
  내 순위, ⚙️ "전광판에 내 이름 표시" toggle.
* Receipts / errors via K.toast (kind "club"/"money"/"warn"): "📺 전광판 예약 완료 · 2번째 · 약 25초 뒤 송출돼요",
  "잔액이 부족해요", "잠시 후 다시 신청해 주세요 (12초)", "전광판 대기열이 꽉 찼어요", "메시지에 쓸 수 없는 표현이 있어요",
  "그 손님은 전광판 이름 표시를 꺼 두었어요", "클럽 안에서만 신청할 수 있어요".

### 4.10 Player flows
1. **Bottle order (existing) + 전광판 연출.** Player orders 골드 at G2 (their menu) → server `Show` write (at = now+0.4) →
   every client: their dim + our LED intro (T4 template, nickname "하늘님", "✨ 골드 스파클링 주스 · 레전드", ₩600,000 count-up)
   → +2.5 s rank badge from our `order` event ("오늘 밤 1위!" or "1위까지 ₩…") → our band collapses, their title shows →
   light carpet unrolls under the staff, lasers follow (tier ≥ 3) → at arrival laser TableLock 4 beats + their confetti →
   ticker gets "✨ G2 하늘님 · 골드 스파클링 주스". ClubRanking board/card/crown unchanged.
2. **전광판 후원.** 📺 → sheet (server `menu`) → 스페셜 · 🎂 생일 축하 · target 민지(player) · "생일 축하해!" → confirm → server:
   gate, filter, reserve slot (ETA 25 s), charge 80,000원 → receipt toast → at slot: main LED full 8 s (or side + lower if an
   official show is running), crowd cheer near the target, ticker line; target gets "🎂 하늘님이 전광판에 축하 메시지를
   띄웠어요!" toast.
3. **테이블 선물.** 🎁 → pick G3 (owner 준) → 🧃 스파클링 주스 타워 + "환영해요" → charge 150,000원 → queued behind any show →
   `Parade` publish: 2 staff with sparklers walk to G3, LED "🎁 테이블 선물 도착! B3 하늘님 → G3 준님", ClubLights sparkler bottles
   land at arrival, our props sit on the table edge 5 min → G3 owner gets "🎁 B3 하늘님이 선물을 보냈어요!" with
   "고마워요 보내기 💙" → free lower-band thanks.
4. **랭킹.** Walk past the bar → 랭킹 TV pages rotate; 🏆 → sheet with tabs + 내 순위; lobby screen on the way in/out.
5. **합석 production.** Tier ≥ 4 order (auto) or 신청 → their Booking start → our MD 매칭 LED cards on the beat → light carpet
   + laser follow on the MD walk → guests sit → name tags appear → owner taps ⚖️ → 5 rounds → chemistry + `play` affinity
   → 📸 photo (guests 짠 via their act, LED 3-2-1, polaroid) → booking ends → 📝 report card.
6. **OCEAN LASER SHOW.** Every ~6 min at clock bar 4 (intro), 8 bars: lower band "🟢 OCEAN LASER SHOW", tunnel → fan → crown
   over the current #1's table (if any) → fades before ClubLights' intro lasers at bar 12.
7. **Late joiner.** Reads `Stage`, `Parade`, `Hapseok`, `Boards`, official attrs; plays the remaining parts only.
8. **Failure paths.** No money → "잔액이 부족해요" (slot released); filter reject → no charge; target left → cue still plays
   with the stored name; sender left → cue plays; payment timeout → "결제가 지연되고 있어요" then paid-late honoured;
   no GameplayAPI → free with 2× cooldowns.
9. **(P2) 게스트 DJ.** Walk onto the booth → 🎧 → book 4 min → ON AIR band "🎧 GUEST DJ 하늘" → pads trigger our lasers / CO2 /
   confetti / LED count / 샤라웃 (table) → crowd cheer → session ends "오늘 밤 디제잉 수고했어요! 인기 +3".

### 4.11 Budgets / quality
| | high | mid | low | saver |
|---|---|---|---|---|
| Our laser beams | 24 @ 30 Hz | 12 @ 30 Hz | 4 @ 15 Hz | 0 |
| Light carpet segments | 40 | 30 | 16 | 0 (LED only) |
| Gift staff rigs | 3 | 3 | 2 | 1 |
| LED UI particles | 36 | 24 | 12 | 0 |
| Side LED canvas | yes | yes | yes | no |
| Boards refresh | 8 s page | 8 s | 12 s | 20 s |
Idle cost outside the club: one 0.5 s state check; nothing built until the first `Inside`.

### 4.12 Test plan
* Offline (Luau CLI + copy of `bprev/lib/rbx.luau` mock in `feat/club/`): Shared pure functions (keys, slotting vs
  official/countdown windows, prices, validation, Balance answers determinism, Rank merge, Cues pattern outputs), server
  modules with mocked `ClubShowHook` / `GwangalliGameplayAPI` / `GwangalliSocialAPI` / folder attrs (order dedupe, direct
  orders, booking lifecycle, money statuses incl. timeout + paid-late, rid dedupe, rate limits, night rollover).
* Studio (one run under flock, timeout 1500): inject modules, fake an order (`Show` attr write through the real GwangalliClub
  `BottleService.order` with money), a shout, a gift, a booking; screenshots of LED intro, lower band over their title,
  side LED, lasers lock, light carpet, bar TV boards, lobby screen, 합석 name tags + game card; check no errors and that
  ClubLights / GwangalliClubShow keep working.

### 4.13 Phasing
* P0: Shared, Bridge, Stage, Led (order intros + lower band + ticker), Lasers (lock/follow/show), Parade (light carpet),
  Shout, Ranking + Boards, Ui rail + sheets.
* P1: Gift parade + thanks, Hapseok (cards, tags, game, photo, report).
* P2: DJ mode, per-player titles (후원왕 tag), LiveConfig theme palettes.
