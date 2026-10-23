# gw-feature (wf_e0983fd1-86f)

- status: completed
- failed agents (never finished, usually the usage limit): build:karaoke, fix:karaoke, review:karaoke:correctness, review:karaoke:experience, test:karaoke

## research:karaoke

# GwangalliKaraokePlus: research and design (팡팡노래방-style karaoke for 광안 코인노래연습장)

Scope: an add-on dropped into the owner's v7 place. It upgrades the 8 existing booths of
`Workspace.Gwangalli.karaoke["광안 코인노래연습장"]` into a 팡팡노래방 / TJ-machine style coin karaoke:
coin credits (1곡 500원 · 4곡 1,000원, matching the signs), a numbered song book, reservations
(예약 / 우선예약), a two-line colour-wipe lyric TV, a score screen with a drumroll, tambourine,
clap and cheer effects, mics you can hold and pass, echo / key / tempo, voice singing with soundproofing
when the place uses the Audio API, and a rhythm-tap fallback for players without voice.
Every in-game string is Korean.

Paths used below:
- `BLD` = `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/src` (dump of the v7 place scripts; file = `<Service>/<Path>.<Class>.luau`)
- `REPO` = `/home/user/-`
- `ZIP` = `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7pack/core/gen/addons/zip` (an older, richer karaoke written for the GwangalliBuildings plaza. It is in the studio bundle, NOT in v7. It is useful to port from. Details in section 1.10)

Line numbers are as read on 2026-10-16. `T_karaoke.luau` is being edited right now by the interior team, so its numbers may drift by ±15 lines.

---------------------------------------------------------------------------------------------------

## 0. Decisions (TL;DR)

1. **Take over the booths and keep the world contract.** The add-on owns the rental, the songs and
   the TV of the 8 `KaraokeRoom` booths. The legacy server module `VenueKaraoke` becomes inert:
   we disable its `GwangalliKaraokePrompt`, and without a renter nothing in it runs. The add-on keeps
   writing the legacy attributes that other systems read (`KRenter`, `KRenterName`, `KPaidUntil`).
   It never writes `KSong`, so the legacy client never starts its chiptune.
2. **Billing = coin credits** (`1곡 500원 · 4곡 1,000원 · 8곡 2,000원`). This matches every sign in the
   building. Today the game charges 500원 per 30 in-game minutes, which is 30 real seconds. A song uses
   one credit when it starts. A song cancelled within 5 s gives the credit back. Money goes only
   through `ServerStorage.GwangalliGameplayAPI` ("spend", cash first, then the check card).
   `Config.Billing = "legacy"` is an optional fallback that keeps the old time rental (Phase 2).
3. **Reuse the live game modules on the server.** `require(<ServerScriptService.GwangalliGameplay Folder>.VenueLife)`
   returns the same table the game uses, because ModuleScripts are cached per VM. From it we call
   `VenueLife.capped / setAct / clearAct / fire / setBoard / ctx.notify / ctx.allowTeleport`, so
   happiness and popularity caps, the sing + mic hand-prop act, toasts, the "오늘의 노래왕" board and the
   Journey hooks behave exactly like the rest of the game. Every call is pcall'd, and BindableFunction
   APIs are the fallback.
4. **Fix the dead daily goal.** `GwangalliProgressShared` has the goal "노래방에서 %d곡 부르기"
   (key `karaoke_song`, owner "interiors"), but nothing in v7 ever tracks it. We call
   `GwangalliProgressAPI:Invoke("track", player, "karaoke_song", 1)` once per completed song.
5. **The client builds every UI from the place's own kit**: `ReplicatedStorage.GwangalliUI` (K) and
   `GwangalliLayout`, with a minimal built-in fallback. The TV is a SurfaceGui in PlayerGui with
   `Adornee = KaraokeScreen`, `Face = Back` and a high `ZOffset`, so it covers the legacy TV. The legacy
   `KaraokeTV` is also disabled. Prompts are created on the client, on our own invisible anchors in
   `Workspace.GwKaraokePlusLocal`. Every request they send is validated by the server.
6. **Audio: three tiers.** (a) A generated band (kick / snare / hats / bass / pad / arpeggio + guide
   melody from the built-in sounds already used in the place), always in sync. (b) An optional
   owner-supplied instrumental per song (`Config.SongAudio`). (c) Optional "MR 반주곡" found through
   `AssetService:SearchAudioAsync` on published places, the same way ClubMusic and GwangalliBuildings
   Sounds already do. **Voice** uses the engine voice input (`AudioDeviceInput`) when the place has
   `VoiceChatService.UseAudioApi = Enabled`. With it we get an echo/reverb mic rig, room soundproofing
   and voice-loudness scoring. Without it, scoring falls back to rhythm taps.
7. **Scoring is server-authoritative.** Clients send note indices plus timing offsets (tap mode) or
   per-line loudness triples (voice mode). They never send a score. The server judges, scores, rewards
   and writes the board.

---------------------------------------------------------------------------------------------------

## 1. Existing integration points

### 1.1 World: the venue model (place.bin)

`DataModel/Workspace/Gwangalli/karaoke/광안 코인노래연습장` (Model, no tags). Floor top y = 6.85,
ceiling underside y = 17.95. `StreamingEnabled = true` on Workspace, so client code must handle
booths streaming in and out. The server sees every booth. Static ProximityPrompts in the venue: none
(all are created at runtime).

**Booths**: `Booth_01` … `Booth_08`. Each is a Model with tags `KaraokeRoom` and `ZoneLOD` and attributes
`RoomNo` (1..8), `RoomName` ("01".."08"), `LOD="zone"`, `LODCenter`, `LODRadius=73`. 83 parts each.
East booths 01-04 have their TV at +X. West booths 05-08 are mirrored, with the TV at -X.

| part (FindFirstChild recursive) | Booth_01 world pose / size | notes |
|---|---|---|
| `KaraokeZone` | (32.35,12.40,299.01) size (11.60,11.20,17.30) Transparency 1, CanCollide false, rotated (local Z = world X) | membership box (server + client) |
| `KaraokeScreen` | (40.52,13.10,299.01) size (8.84,5.04,0.05), attr `GuiFace="Back"`, child `SignGui` (SurfaceGui "ROOM 01 / 문 옆 패널에서 방을 잡고 노래를 골라요") | TV face; Back face points into the room (-X for east booths, +X for west) |
| `TVBezel` / `TVUnderglow` | (40.70,13.10,299.01) 9.2×5.4×0.32 / neon strip y 10.34 | |
| `KaraokePanel` | (23.18,12.10,298.15) 1.1×2×0.2, attr `RoomNo`, `SignGui.Face.Sub` = "빈 방 · 터치", `.Text` = "01" | corridor face. The legacy prompt host |
| `StatusLight` | (23.20,16.45,303.90) neon 0.4 | the legacy client paints it green (60,255,120) or red (255,60,60) |
| `MirrorBall` | (31.35,16.10,299.01) ball 1.5, attr `GwKaraoke="ball"`; `LaserProjector`/`LaserLens` (36.0,17.43,299.0) | |
| `TableTop` | (31.80,8.38,299.01) 3.2×0.25×6, top y 8.505 | gameplay table (never hidden) |
| `Remote` + `RemoteKeys` | (32.00,8.57,299.58) | 리모컨 prop |
| `SongBook` + `SongBookLabel` | (31.95,8.70,298.33) | 노래책 prop |
| `WirelessMic` ×2 + `WirelessMicHead` ×2 | (32.80,8.67,299.51) and (33.20,8.67,298.21) | the two room mics |
| `Tambourine` (attr `GwKaraoke="tambourine"`) + 4 `Jingle` | (30.10,8.61,299.61) | |
| `MicBase/MicPole/Mic/MicHead` | stand at (37.20,6.88,301.61), mic (36.75,12.12,301.26) | stand mic |
| `KaraokeMachine` / `MachineDisplay` ("38131") / `MicDock` / `MachineCabinet` | (39.80,9.85,299.01) / (38.98,9.88,298.61) / (39.90,9.55,301.36) | 반주기. We put the coin slot here |
| Seats | SofaBack 1 (25.80,8.13,296.28), SofaLeft 3 (z 295.3), SofaRight 2 (z 302.71), all `Seat` with attr `Sittable` | 6 seats per booth |
| `BoothDoor` (glass, Transparency 0.45) | (26.25,11.05,304.48) 0.15×8.3×4.7, swung flat against the partition | door opening z 299.5..304.5 at x≈23.2 |

Other booths: the same layout at z = 299 / 311 / 323 / 335. East booths: panel x = 23.18, screen x = 40.52.
West booths: panel x = 11.42, screen x = -6.07, screen faces +X.
Full dump: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/py/booths.txt` and `.../py/booth01.txt`.

**Lobby and other areas** (same venue model):
- `Booth_Lobby` (ZoneLOD, LODCenter (30.6,11.2,285.2)). `Board_karaoke/BoardFace/BoardGui` with labels
  `Title` ("👑 오늘의 노래왕") and `Row1..Row5`. VenueBoard `Board = "karaoke"` is written by VenueLife.setBoard.
  `CatalogPost` (21.45,8.60,289.50) with `NearDetail/CatalogBook` (21.45,10.35,289.50) and the
  sign "노래 책 · 신곡 목록". `MicSterilizer` (38.30,10.90,288.31) + `SterilizerUV`.
- `LEDScreen` (40.11,13.70,276.51), tag `LEDScreen`, attr `Messages = "TOP 100 인기차트|1위 ♪ 광안대교 불빛 아래|2위 ♪ 민락동 치킨송|3위 ♪ 갈매기 트로트|이달의 신곡 업데이트"`.
  It is cycled by the client `GwangalliWorld/Screens`, which re-reads `Messages` every ~5 s
  (`BLD/StarterPlayer/StarterPlayerScripts/GwangalliWorld/Screens.ModuleScript.luau:1,43,77`). There is precedent
  for a server writing it: Arcade `World.ModuleScript.luau:484-485` `pcall(part.SetAttribute, part, "Messages", msg)`.
- `CoinChanger` (-5.24,10.10,272.60) + `ChangerDisplay` + signs "동전교환기" / "지폐 → 500원 동전".
  `VendingMachine` (Model). `WaitingSofa` (4 Seats at z 271.4). `Counter` (Model) + `NearDetail/CardReader`
  (27.25,11.00,283.70). `MicCoverBox` (38.90,11.60,289.01). `StaffCabinet`. `CCTVMonitor`.
  `WaterPurifier` (0.24,9.10,356.83).
- Price signs: `Sign_1곡 500원 · 4곡 1,000원` (lobby, "요금 안내 · 무인 운영 · 24시간 · CCTV 녹화중"),
  `Sign_1곡 500원 4곡 1,000원` (facade), `Sign_이용 안내`, `Sign_신곡 입고`, `Sign_SING SING`, and per booth
  `Sign_이달의 신곡` ("♪ 민락동 치킨송").
- `Destination` (5.46,7.06,264.50), attr `DisplayName="광안 코인노래연습장"`, tag `Destination`.
  `AutoDoor_노래연습장` (tag AutoDoor).
- Rooms frames for the interior generator: `REPO/tools/venues/rooms.json` ("광안 코인노래연습장": lobby
  center (17.2,6.85,280.65) size (47.6,11.1,24.3); corridor (17.3,6.85,317.0) 12×48; booth01..08 17.3×11.6).

**Tags and attributes on this venue that we depend on**: `KaraokeRoom` and `RoomNo` (discovery),
`KaraokeZone`, `KaraokePanel`, `KaraokeScreen` (+`GuiFace`), `MirrorBall`, `StatusLight`, `LEDScreen` + `Messages`,
and the VenueBoard "karaoke". The interior's coin LCD treats `KPaidUntil - now` seconds as in-game minutes (1 real s = 1 game min),
so `KPaidUntil = now + 60*credits` reads "남은 시간 240분" for 4 songs, which is about right in game time. The `GwKaraoke` attributes on the tambourine and ball are read by no script today.

### 1.2 Server: the legacy `VenueKaraoke` (`BLD/ServerScriptService/GwangalliGameplay/VenueKaraoke.ModuleScript.luau`)

Started by `Venues.init` → `VenueLife.init` → `VenueKaraoke.init(life)`
(`Venues.ModuleScript.luau:1407-1421`). How it works today:

- Prompt creation (`:202-214`):
  ```lua
  local pr = L.prompt(panel, "방 잡기", "", 0.3, 8, Enum.KeyCode.E)
  pr.Name = "GwangalliKaraokePrompt"
  ```
  This is a **server** ProximityPrompt parented to the map part `KaraokePanel`.
- Rent (`:138-157`): `L.pay(player, V.KARAOKE.fee, string.format("코인노래방 ROOM %s (30분)", r.name))`,
  then attrs `KRenter` (UserId), `KRenterName`, `KPaidUntil`, then `L.fire(player, { kind = "kOpen", room = r.no })`,
  which opens the legacy picker on the client.
- Auto extension (`:384-396`): every tick, while anyone is inside and `t >= r.paidUntil`, it charges again
  ("코인노래방 ROOM %s 연장 (30분)"). Release after `V.KARAOKE.emptyGrace` (20 s) empty (`:374-383`).
  Renter-left handover (`:362-372`).
- Song state is written to booth attributes (`writeSong :87-92`): `KSong`, `KStart`, `KSerial`. Release clears
  `KRenter=0`, `KRenterName=""`, `KPaidUntil=0`, `KResultName=""`, `KResultScore=0` (`:110-127`).
- Ops through `VenueLife.handle`: `kSong` (`:256-289`, ids validated by `Util.str(p.song, 8)` + `V.SONG_BY_ID`; it
  also calls `L.setAct(player, "sing", dur + countdown, "mic")`), `kStop`, `kLeave`, `kScore` (`:307-353`: it
  **trusts client counts** `perfect` / `good` clamped to the note total; `V.karaokeScore`; rewards
  `L.capped(player, "venue_karaoke", V.KARAOKE.dailyRewards, V.KARAOKE.reward)` and, for 90+,
  `L.capped(player, "venue_karaoke90", V.KARAOKE.daily90, V.KARAOKE.reward90)`; board `L.submit(kingTop, …, 5)` +
  `kingRows()` → `L.setBoard("karaoke", …)`; `L.fire(mem, { kind = "kResult", room, serial, name, score, mine })`).
- Exports only `Karaoke.init` and `Karaoke.members`. The `rooms` table is local, so it cannot be driven from outside.

Pricing data (`BLD/ReplicatedStorage/GwangalliVenuesShared.ModuleScript.luau:82-92`):
```lua
V.KARAOKE = { fee = 500, periodMinutes = 30, emptyGrace = 20, countdown = 3,
  scoreWindow = { perfect = 0.12, good = 0.24 }, dailyRewards = 12, reward = { happiness = 3 },
  reward90 = { popularity = 1 }, daily90 = 3 }
```
`period = math.max(10, V.gameMinutes(30, 24))` = **30 real seconds per 500원**, since
`GwangalliConfig.DayLengthMinutes = 24` (`GwangalliConfig.ModuleScript.luau:18`). Songs: 10 ORIGINAL songs
`s01..s10` (`:95-136`) numbered `s.number = 38000 + i * 131` (`:139`), so 38131 … 39310. Chart `V.chart(song)`
(`:180-204`): each line spans 2 bars, with 3-5 tap notes per line. Score `V.karaokeScore` = `40 + raw*60`
(`:208-214`). Comments `V.scoreComment` (`:216-227`). The remote/world contract is documented at `:7-48`.

### 1.3 Server: `VenueLife` API that we call (`BLD/ServerScriptService/GwangalliGameplay/VenueLife.ModuleScript.luau`)

How we get it: `ServerScriptService` holds both a **Script** and a **Folder** named `GwangalliGameplay`.
Iterate the children and pick `IsA("Folder")`, the same way the game itself does
(`GwangalliGameplay.Script.luau:41-48`). Then `require(folder.VenueLife)`. It is ready when
`VenueLife.V ~= nil and VenueLife.ctx ~= nil` (set at `:965-966`). Poll every 0.5 s for up to 40 s.

| function (line) | signature | our use |
|---|---|---|
| `VenueLife.capped` (:85-104) | `(player, key, limit, delta) -> (applied?, ok)` uses Profiles `d.daily.counts[key]` (real-day reset via `G.dayKey`) and `ctx.addStats(…, silent=true)` | song rewards, shared keys `venue_karaoke` / `venue_karaoke90` (same daily totals as legacy, no double dipping) + our own `kp_cheer` |
| `VenueLife.setAct` (:267-289) | `(player, act, seconds?, prop?) -> token`, sets player attrs `GwVenueAct` / `GwVenueActT` and welds the hand prop (`mic`, `tambourine`, …) | `setAct(p, "sing", nil, "mic")` while holding a mic; `setAct(p, "tambourine", 2.6, "tambourine")` |
| `VenueLife.clearAct` (:252-265) | `(player)` | putting a mic down |
| `VenueLife.fire` (:62-66) | `(player, payload)` → VenueEvent | Journey hooks: `{kind="kOpen", room=0}` and `{kind="kResult", room=0, mine=true, …}` (see 3.4) |
| `VenueLife.setBoard` / `rowsOf` / `submit` (:314-361) | `setBoard(board, rows)`; `submit(list, {name, score, userId, …}, size) -> rank` | "👑 오늘의 노래왕" |
| `VenueLife.inside` (:118-123) | `(part, pos, pad?)` box test with +3 Y | membership |
| `VenueLife.ctx.notify` | `(player, kind, title, body?, extra?)` → Notify remote (`GwangalliGameplay.Script.luau:237-247`) | all Korean toasts |
| `VenueLife.ctx.allowTeleport` | `(player, seconds)` (`GwangalliGameplay.Script.luau:149-152`) | before pushing an intruder out of a locked room |

Hand props (`:181-249`): `"mic"` = a dark cylinder plus a ball welded to the right hand. `"tambourine"`.
Note that `setAct` always calls `clearAct` first, so a mic holder cannot also play the tambourine prop (handled in the design).
Router: `reqRemote.OnServerInvoke` with `Util.bucket(player, 6, 12)` (`:1008-1025`). The add-on uses its **own**
remotes and does not share this bucket.

### 1.4 Money: `ServerStorage.GwangalliGameplayAPI` (`BLD/ServerScriptService/GwangalliGameplay.Script.luau:457-475`)

```lua
api.OnInvoke = function(op, player, amount, label)
  if op == "balance" then return d and d.cash or 0, d and d.bank or 0 end
  if op == "spend" then ... return ctx.spend(player, math.floor(amount), label or "건물 · 생활")
  elseif op == "earn" then ... return ctx.ledger(player, "bank", math.floor(amount), label or "생활 수익")
  elseif op == "addStats" then return ctx.addStats(player, amount, label or "생활") end
```
`ctx.spend` (`:337-353`) takes cash first, then the bank ("체크카드"), and shows the toast `-1,000원 <label>`.
`ctx.canAfford` (`:331-335`). Precedent for an outside Script using this API plus a timed Invoke:
`BLD/ServerScriptService/Bowling.Script.luau:354-394` (`bindable`, `invokeTimed`) and `:396-397` (API names). We
copy that pattern, with one difference: a **money op is never abandoned on timeout**. The room stays
"결제 중…" until the Invoke returns, and there is one money op in flight per player.

Profiles (`Profiles.ModuleScript.luau:1-10`): DataStore "GwangalliProfile_v1" with a session lock.
`Profiles.sanitize` drops unknown keys, so **add-on data needs its own DataStore**. Progress does the same
(`Progress.ModuleScript.luau:28-31`).

### 1.5 Progress, Journey, Social, boards

- **Progress** (`BLD/ServerScriptService/GwangalliGameplay/Progress.ModuleScript.luau:24-26, 439-470, 1328-1349`):
  `ServerStorage.GwangalliProgressAPI:Invoke("track", player, key, n)`. The key `karaoke_song`
  (`GwangalliProgressShared.ModuleScript.luau:347` `karaoke_song = { name = "노래방", owner = "interiors" }`) feeds
  the daily goal `:492` "노래방에서 %d곡 부르기" (n 1/2/3, 6,000원 + 인기 1) and the achievement `:674`
  "노래방 가수". **No v7 script tracks it today.**
- **Journey** (`BLD/ServerScriptService/GwangalliGameplay/Play/Journey/Signals.ModuleScript.luau:19, 487-503, 605`) wraps
  `VenueLife.fire`: `kResult` with `mine == true` → `played(player, "karaoke")`; `kOpen` → `J.kind(player, "karaoke")`
  + `emit(player, "karaoke.open", { room = payload.room })`. The Journey place "karaoke" unlocks on the event
  "karaoke.open" (`GwangalliPlayShared/Journey.ModuleScript.luau:189-198`). Its hint text says
  "500원이면 30분!" (`:196`). That text is out of date once credits ship, and it is not our file.
- **Social** (`Relationships.ModuleScript.luau:31-36, 2655-2665`): `ServerStorage.GwangalliSocialAPI:Invoke("joint", player, "karaoke")`
  awards the companion NPC affinity for a karaoke outing. The source is `karaoke = { base = 3, max = 1, label = "코노" }`
  (`GwangalliSocialShared.ModuleScript.luau:193`). Club.Script uses this API the same way (`Club.Script.luau:767-772`).
- **Board**: VenueBoard "karaoke" → `Board_karaoke` rows (VenueLife.setBoard). The legacy board writes only at init
  and after a legacy kScore, so after the takeover we are its only writer.

### 1.6 Client: legacy `GwangalliVenues` (what we must coexist with)

- LocalScript `StarterPlayerScripts/GwangalliVenues` + Folder `GwangalliVenues/{Common,Spots,Gym,Karaoke,PC}`.
  `Common.init` creates `PlayerGui.GwangalliVenues` (ScreenGui, DisplayOrder 43) (`Common.ModuleScript.luau:149-162`).
  It sets the HUD-hide contract `gui:SetAttribute("HideGwangalliHUD", …)` (`:279-283`) and the built-in sounds pool
  (`:231-258`): `tap = clickfast.wav`, `ping = electronicpingshort.wav`, `swoosh = swoosh.wav`. Its act
  driver animates `GwVenueAct` for every player (`POSES.sing` / `tambourine` `:40-50`).
- `GwangalliVenues/Karaoke.ModuleScript.luau`:
  - the TV: `sg.Name = "KaraokeTV"`, Face Back, `CanvasSize 1024×580`, `MaxDistance 80`, **`sg.Parent = scr`** (map part,
    `:145-206`). It disables the screen's `SignGui` while built (`:202-205`).
  - the action bar `Frame "KaraokeBar"` (`:380`), `Frame "KaraokeStrip"` (`:412`), `TextButton "KaraokeTap"` (`:417`) in
    `PlayerGui.GwangalliVenues`. `step()` rewrites their `Visible` 30× a second (`:538-545`).
  - picker sheet `"KaraokePicker"` opened on VenueEvent `kOpen` when `p.room` matches a room (`:739-746`).
  - keys `Space` / `F` → `Karaoke.tap()` while a legacy song runs (`:752-759`). The chiptune `C.note(n.p, 0.2)` (`:664`)
    and the metronome only run while `KSong` is a valid `V.SONG_BY_ID` id.
  - room paint: StatusLight colour plus `KaraokePanel.SignGui…Sub` text from `KRenter` (`:82-94`). **We keep this behaviour**,
    because we keep writing `KRenter`.
  - it spins `MirrorBall.CFrame` locally plus one PointLight while a legacy song plays (`:500-525`, `:684-689`).

### 1.7 Client UI kit and layout

- `ReplicatedStorage.GwangalliUI` (K, 3,375 lines, header `:1-35`): tokens `K.Color` (glass, cyan #3DD6F5, magenta
  #FF4FA3, gold #FFC247), `K.Font`, `K.Type`, `K.Radius`, and the components `K.Button` (sets `Name = opts.name`),
  `K.ListRow`, `K.BottomSheet` (`:2614`), `K.Tabs`, `K.Segmented`, `K.SearchBar` (`:1998`), `K.Slider`, `K.Toggle`, `K.Chip`, `K.Modal`,
  `K.toast`, `K.countUp`, `K.won`. It uses no image asset ids.
- `ReplicatedStorage.GwangalliLayout` (`:1-60`): slots `bottomCenter` (context banners), `rightColumn.sprint`,
  `sheetRight`, `Layout.onChanged`. The legacy karaoke bar uses `bottomCenter` and puts its tap button at `rightColumn.sprint`.
- HUD hide: any enabled ScreenGui with attribute `HideGwangalliHUD = true` hides the HUD
  (`GwangalliInteractClient/Hud.ModuleScript.luau:527`, `ClubMusic.LocalScript.luau:819`).

### 1.8 Audio, music, voice in the place

- **Sound instances in place.bin: 0.** The GWPB dump contains no Sound, SoundGroup, SoundService or VoiceChatService
  instances, because the format keeps only Workspace / Lighting / StarterPlayer / RS / SS / SSS. So the
  `VoiceChatService.UseAudioApi` / `EnableDefaultVoice` values **are unknown**. No v7 script references
  VoiceChatService or AudioDeviceInput.
  TextChatService is in use (`GwangalliDrive/Api.ModuleScript.luau:26,259` adds TextChatCommands).
- Built-in sounds used by owner scripts (count of uses): `rbxasset://sounds/electronicpingshort.wav` (35),
  `clickfast.wav` (29), `swoosh.wav` (21), `action_falling.mp3` (7), `action_jump_land.mp3` (6), `action_swim.mp3` (5),
  `action_footsteps_plastic.mp3` (4), `impact_water.mp3` (2), `uuhhh.mp3` (1). **These are the only sounds we use by default.**
- Marketplace audio ids in scripts: only `rbxassetid://5736468541` (police siren, `Law/Police.ModuleScript.luau:1286`).
  The other `rbxassetid://` values are default avatar **animations** (GwangalliAnim / ClubShared):
  cheer R15 `507770677` / R6 `129423030`, dance1-3 R15 `507771019` / `507776043` / `507777268`, wave `507770239`.
  They can be played through `GwangalliAnim.play(target, "cheer" | "dance1")` (`GwangalliAnim.ModuleScript.luau:1-40`).
- **ClubMusic** (`ClubMusic.Script.luau:1-20, 431-458`): it finds music at runtime with
  `AssetService:SearchAudioAsync(AudioSearchParams{ Artist="Monstercat" | keyword "EDM" …, AudioSubType Music })`,
  verifies each track by loading it on the server, caches the playlist in a DataStore and syncs playback with
  `TrackStart` (server time) / `TrackId` attributes. The client resyncs on drift (`ClubMusic.LocalScript.luau:294-357`).
  The club model attribute `MusicAssetId = ''` (empty in v7).
- **GwangalliBuildings Sounds** (`ServerScriptService/GwangalliBuildings/Sounds.ModuleScript.luau:20-51`) publishes found ids as
  attributes of `ReplicatedStorage.GwangalliBuildingsSounds`, including `karaoke_music = { "kpop instrumental", "music", 60, 400 }`
  and `karaoke_muffled = { "muffled music", "sfx", 10, 300 }`. `Config.SOUND_SEARCH = true`
  (`GwangalliBuildingsShared/Config.ModuleScript.luau:136`). We read these two attributes at runtime as optional
  corridor and lobby ambience.

### 1.9 The building-interior team (client decor), DetailLOD, streaming

- `REPO/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/T_karaoke.luau` (1,546 lines, being edited) builds local
  decor under `Workspace.GwInteriorDetailLocal`. It **locally hides** and rebuilds at the same pose: WirelessMic/Head,
  Tambourine + Jingles, SongBook/Label, Remote/RemoteKeys, KaraokeMachine, MachineDisplay, MicDock, the stand-mic parts
  and the speakers (`hideRec` calls around `:523-958`). It never hides KaraokePanel, KaraokeZone, KaraokeScreen
  (TV face), StatusLight, MirrorBall, Seats or TableTop (header `:6-9`).
- Its own **local** prompts use `KeyboardKeyCode = R` (`Interact.luau:106`): 조명 모드 on its `LightPanel` (`T_karaoke ~:1227`),
  에어컨 (`~:1239`), 문 닫기/열기 swing (`~:1310`).
- Its live displays read **our** booth attributes (`~:1416-1460`):
  - the coin LCD reads `KPaidUntil` and shows "남은 시간\n%d분", otherwise "500원 · 30분\n동전 · 지폐".
  - the VFD reads `KSong` and shows `songNo(tonumber(match(id,"%d+")))` with `songNo(i) = 38000 + i*131` (`:125-127`).
  - `rented()` = `KRenter ~= 0` (`:385-388`).
  - its tablet shows fake "곡 검색 · 예약" rows, and its notice says "30분 500원 · 사용 중 자동 연장" (`~:1183-1198`).
- DetailLOD (`GwangalliWorld/DetailLOD.ModuleScript.luau:1-33`) hides a whole `ZoneLOD` booth beyond 73 studs with
  LocalTransparencyModifier **and disables the guis inside it**, then restores them. A gui parented to the screen part
  (the legacy KaraokeTV) can therefore be re-enabled by DetailLOD. A PlayerGui gui with an Adornee is unaffected.
- Map rules (`bld/systems.json` "rules" R1-R4): never destroy, rename, reparent, resize or re-CFrame map instances; keep
  everything in our own root folder; never hide gameplay parts (KaraokePanel / KaraokeZone, seats, table tops, VenueBoard …).
  For us this means no MirrorBall CFrame spinning (the legacy client does it; we will not), and all props and lights in
  our own folders.

### 1.10 Reference implementation (not in v7, portable)

`ZIP/ReplicatedStorage/GwangalliBuildingsShared/Karaoke.luau` (530 lines), `ZIP/ServerScriptService/GwangalliBuildings/ShopFlows/KaraokeVoice.luau`
(625), `ZIP/StarterPlayer/StarterPlayerScripts/GwangalliBuildingsClient/{KaraokeView 2179, KaraokeRoom 1182, KaraokeBand 557,
KaraokeMic 499, KaraokeLyrics 365, KaraokeKit 351}.luau`. They were written for the procedural 광안 프라자 karaoke and
follow the same conventions. What we port, with renames (`GwK_*` → `GwKP_*`) and the new data source:
- `Karaoke.chart` with per-syllable times `sylT` and 3-lane notes; `judge` windows `perfect 0.09 / good 0.18 / early 0.32`;
  `LIVE_SLACK 0.5`, `STALE 6`, `SETTLE 1.5`; `voiceLine` / `voiceScore` (per-line v / r / o loudness numbers);
  `beatOffset` / `vibeBonus` (tambourine on the beat); `GRADES` S/A/B/C; `ECHO_PRESETS` (5 levels with DelayTime /
  Feedback / Wet / Decay); `MIC_CHAIN`; `KEY_MIN/MAX ±5`; `SYNC` listener delay (`Karaoke.luau:44-130`).
- KaraokeVoice: a room speaker rig `AudioFader → AudioCompressor → AudioEqualizer → AudioEcho → AudioReverb → AudioFader → AudioEmitter`,
  one Wire per mic holder from the **engine-created** `AudioDeviceInput`. Soundproofing sets `AccessType = Allow` +
  `SetUserIdAccessList(room members)` and restores the old lists afterwards. It never creates a device and never reads
  PluginSecurity props (`KaraokeVoice.luau:1-20`).
- KaraokeMic: a client AudioAnalyzer on its own device (RmsLevel only; GetSpectrum is empty for device inputs). KaraokeLyrics:
  a two-line wipe with TextService prefix widths, 4 countdown dots and "간주중". KaraokeBand: a 16th-grid generated band from
  clickfast / electronicpingshort, optional AudioPlayer track → AudioPitchShifter (key) → fader.
  KaraokeRoom: cheer bar, mic hand-over card, local dry-voice mute (`AudioInteractionGroup`), self-monitor toggle.

---------------------------------------------------------------------------------------------------

## 2. What exists vs the target

### 2.1 How players sing today (v7)

1. They walk to a booth's corridor panel, where the E prompt says "방 잡기" (ROOM NN · 30분 500원). Paying 500원 rents the
   room. The fee repeats every 30 **real seconds** while anyone stays inside, which costs about 1,000원 a minute.
2. The legacy picker sheet lists the 10 original songs (number, title, artist, genre, BPM, length). Picking a song
   starts it 3 s later for everyone in the room. The picker holds the "mic", meaning the sing pose and a hand prop for the song.
3. The TV (a SurfaceGui on the screen part) shows a countdown, a title, one lyric line with a per-line wipe plus the next
   line, and a pitch lane of tap notes. Players press "♪ 박자" (Space / F / touch) on the notes. A chiptune melody plus a
   metronome comes from pitched `electronicpingshort.wav`.
4. At the end each client sends its own perfect / good counts. The server scores 40-100 and gives 행복 +3 (12 a day) and
   인기도 +1 for 90+ (3 a day). The TV shows the room's best score with a count-up, a comment and confetti for 90+. The lobby
   board "👑 오늘의 노래왕" updates.
5. Voice: whatever Roblox default voice chat the place has, which is spatial. There is no echo and no soundproofing,
   and voice does not affect the score.

### 2.2 팡팡노래방 (Roblox) — what we could learn

Public info is thin. The detail pages (op.gg, namu.wiki, roblox.com) could not be fetched from this sandbox (DNS).
Search snippets give: "팡팡 노래방" by **팡팡스튜디오**, genre Entertainment / Music & Audio, created 2026-03-07,
about 590K visits, about 4.1K favourites, 91.6% rating, max 60 players per server, a recent "[🔥추석 이벤트]" title,
tags 노래방 / 노래부르기 / 보컬 / K-POP. The description says audio copyrights belong to their holders, which
suggests it plays Roblox-library audio as backing tracks. A separate game, Stingray "Ro-Karaoke" (2024), supports up to
30 people with voice or text chat. The feature set the owner asked for is our target: rooms, a numbered song book,
reservations, a colour-wipe lyric display, a score screen, tambourine and effects, and an echo mic. It matches
real TJ / 금영 coin-karaoke UX.

### 2.3 Gap table

| target feature | exists in v7 | missing / wrong |
|---|---|---|
| rooms (8 booths, status light, panel) | ✅ booths, StatusLight, panel paint | privacy (anyone can walk in and sing), knock / invite, idle release with credits |
| pricing that matches the signs | ❌ time rental 500원/30 s | 1곡 500원 · 4곡 1,000원 coin credits, 서비스곡, cancel refund window |
| 노래책 with numbers | ⚠️ 10 songs in a flat list with numbers 38131… | 40+ songs, tabs (인기차트 / 신곡 / 장르 / 애창곡 / 최근 / MR), search by 제목 / 가수 / **초성** / 번호, song detail, lobby read-only book |
| 리모컨 / 예약 | ❌ picking replaces the current song | queue of 10 (3 per player), 우선예약, 취소, number pad, 지금 부르기, auto-advance |
| lyrics with colour wipe | ⚠️ one line, line-level wipe | TJ two-line alternate layout, per-syllable wipe, 4-dot count-in, 간주중, part colours (남 / 여 / 같이) |
| score screen | ⚠️ count-up + comment | 두구두구 drumroll, grade, 100점 fanfare + 서비스 1곡, per-singer (듀엣) scores, records (내 최고 / 방 최고 / 순위) |
| tambourine / effects | ⚠️ tambourine button (act + prop) | 박수 · 환호 · 폭죽 buttons (TJ remote style), on-beat tambourine judging → 분위기 meter + bonus, TV emoji, light fx |
| echo mic | ❌ | 에코 0-5 (Audio API rig), 키 ±5, 템포 ±2, 멜로디 가이드, 반주 볼륨, 싱크 |
| singing with voice | ⚠️ default spatial voice | room speaker with echo, soundproofing, voice-loudness score, mic hold / pass (2 mics) |
| backing music | ⚠️ single-voice chiptune | generated full band, owner instrumentals, library MR |
| server-authoritative score | ❌ trusts client counts | hit offsets / voice lines judged on the server |
| daily goal `karaoke_song` | ❌ never tracked | track per completed song |
| companion affinity "코노" | ❌ | SocialAPI joint("karaoke") |
| persistence | ❌ | 애창곡, 최근 부른 곡, per-song best, settings, 노래방 수첩 stats, weekly chart |
| lobby LED chart | static text | live "TOP 인기차트" + 오늘의 노래왕 |

---------------------------------------------------------------------------------------------------

## 3. Conflicts and risks, with mitigations

1. **Legacy server rental and prompt.** If both systems ran, players would see two "방 잡기" prompts and pay twice.
   → After our boot, set `Enabled = false` on every **server** ProximityPrompt under each `KaraokePanel`. Our own
   prompts are client-local, so no server prompt there is ours. Watch `DescendantAdded` and
   `GetPropertyChangedSignal("Enabled")` to keep them off. VenueKaraoke then never gets a renter, and its tick and ops do
   nothing (`getRoom` answers "먼저 방을 잡아 주세요"). Start order: VenueLife sets `.V` before `VenueKaraoke.init` runs
   `release()` on every booth (`Venues.ModuleScript.luau:1407-1421`). So we wait for VenueLife.V, then up to 10 s for the legacy
   prompts to appear, then take over. No players exist that early, so the overlapping writes are harmless.
   Kill switch: `Config.TakeOverLegacy = false` leaves the legacy system untouched and runs Plus only on booths whose
   panel has no legacy prompt.
2. **Legacy client UI duplication.** `KaraokeBar`, `KaraokeStrip`, `KaraokeTap` and `KaraokeTV` would show next to ours.
   → Our client neutralises them **only after** the server publishes `GwangalliKaraokeShared:GetAttribute("Active") == true`:
   - `PlayerGui.GwangalliVenues.KaraokeBar / KaraokeStrip / KaraokeTap`: `Destroy()` once, and again if they reappear.
     The legacy code keeps setting properties on the destroyed objects, which does not error.
     Their only parenting path (`C.pop` into the strip) runs only inside `Karaoke.tap()`, which needs a legacy song, which we never start.
   - every `KaraokeScreen.KaraokeTV` (ChildAdded watch): `Enabled = false`, re-asserted on `Enabled` changes (DetailLOD restores guis).
   - our TV uses `ZOffset = 5`, so it covers the legacy TV even if a frame slips.
   - no legacy song ever starts, because **we never write `KSong`** (it stays ""). So there is no chiptune, metronome or Space/F
     handler, no `C.hideHud("karaoke")` and no MirrorBall CFrame spin.
3. **Legacy picker via `kOpen`.** Firing `kOpen` with a real room number would open the old picker.
   → We fire Journey's events with **`room = 0`**: `VenueLife.fire(player, {kind="kOpen", room=0})` when a player rents or joins,
   and `{kind="kResult", room=0, serial, name, score, mine=true}` per singer. The legacy client finds no room 0, so it opens nothing.
   For `kResult mine` it plays one "ping", which is fine. Journey only needs `kind` / `mine`.
4. **Interior team attributes.** Their coin LCD reads `KPaidUntil` as minutes, and their VFD derives numbers from `KSong`.
   → We write `KRenter`, `KRenterName` (StatusLight, panel text, `rented()` keep working) and `KPaidUntil = now + 60*credits`,
   which is a harmless approximation shown as "남은 시간 N분". We also add booth attributes **`KPCredits`, `KPSongNo`,
   `KPMicsOut`, `KPTambOut`, `KPState`** and ask the interior team (section 4.17) to prefer them: "남은 곡 N곡", the real
   number on the VFD, and hiding their local table-mic / tambourine copies while a player holds them. Until they do,
   the worst case is cosmetic: a "남은 시간" label and a mic visible on the table and in the hand at the same time.
5. **Prompt key collisions.** Legacy uses E (now disabled) and the interior uses R. → We use E with
   `Exclusivity = OnePerButton`, so only the nearest of our close table prompts shows. `MaxActivationDistance` is 6 at the
   table and 8 at the panel. No prompt is placed within 1.5 studs of their light panel or AC prompts.
6. **Never touching map parts.** All our parts go in `Workspace.GwangalliKaraokePlus` (server: speaker anchors) or
   `Workspace.GwKaraokePlusLocal` (client: prompt anchors, fx). No CFrame or visibility edits on map parts.
   The only map writes are server **attributes** on booth Models (legacy precedent), on `LEDScreen.Messages`
   (Arcade precedent) and on the VenueBoard rows through VenueLife.
7. **Streaming.** Booths can be streamed out on clients. → The full room state lives in
   `ReplicatedStorage.GwangalliKaraokeShared.State.Room_NN` (Configuration attributes), which is always replicated. The
   client binds visuals with `CollectionService:GetInstanceAddedSignal("KaraokeRoom")` and rebinds on stream-in.
8. **Money safety.** → Money moves only through `GwangalliGameplayAPI` "spend". There is one money op in flight per player and
   a request id (`rid`) cache of 120 s, so a double tap returns the first result. Credits are capped at 30. Nothing money-like
   persists across servers, because credits live only in the room session. This is the real-world rule ("남은 곡은 퇴실하면 사라져요")
   and it removes any duplication by server hopping. If the API is missing: `Config.FreeWhenNoEconomy` (default true, so
   studio tests without the core work) makes packs cost 0, and the payment sheet says "무료 체험".
9. **Remote abuse.** → Our own remotes, a per-player token bucket per op class, type, range and length checks,
   membership and distance checks, role checks (renter-only ops), hit and voice timing windows, and caps on queue, cheer and favourites.
10. **Voice API availability.** The `UseAudioApi` / `EnableDefaultVoice` values in v7 are unknown and are PluginSecurity
    (scripts cannot read them). → Detect `Player:FindFirstChildOfClass("AudioDeviceInput")` (engine-created) at runtime.
    The rig is built only when at least one mic holder has a device. Every Audio API call is pcall'd. With no device,
    singing uses tap scoring and the echo control affects only the guide melody (local EchoSoundEffect / ReverbSoundEffect).
    Owner action (section 4.14): enable the Audio API voice in Studio for the full experience.
11. **Rewards farming.** Songs cost money, and stat rewards use the shared daily caps (`venue_karaoke` 12 a day, `venue_karaoke90`
    3 a day). Cheer rewards have their own small cap. The Progress goal counts only songs that are at least 60% complete,
    with at least 30% of notes or lines engaged.
12. **Engine quirks in the temp studio.** The browser engine may lack the Audio API, UnreliableRemoteEvent or SearchAudioAsync,
    so all of them are pcall'd with fallbacks (RemoteEvent instead of UnreliableRemoteEvent). DataStore runs memory-only when
    `game.PlaceId == 0` or on access errors.
13. **Other karaoke code in the studio bundle (ZIP plaza).** It uses `GwK_*` names and plaza KaraokeScreens with `ScreenKind`.
    We discover rooms only by tag `KaraokeRoom` + `RoomNo` + `KaraokeZone`, inside `Config.VenueModelNames`, and use the
    `GwKP_` prefix everywhere.
14. **Light budget.** We add at most 2 local Light instances (current room only, `Shadows=false`, only while a song plays)
    and do not tag them `InteriorLight`. Neon parts and particles do the rest.

---------------------------------------------------------------------------------------------------

## 4. Add-on design

### 4.1 Principles

- Drop-in: 3 folders, no edits to existing scripts. If anything we integrate with is missing, that feature degrades
  and nothing errors.
- Server-authoritative for money, rental, queue, mics, privacy, scoring, rewards and persistence. Clients render and
  propose actions.
- Deterministic shared data: the catalog plus `chart(song, tempo)` compute the same timeline on the server and every client.
  Only song ids, timing offsets and small numbers cross the network.
- Mobile + PC + gamepad: kit components, layout slots, ProximityPrompts (tap / E / ButtonX), big touch targets (≥ 44 px),
  ContextActionService bindings only while inside a rented room.

### 4.2 Files (only under the allowed paths)

```
src/ReplicatedStorage/GwangalliKaraokeShared/            (ModuleScript "GwangalliKaraokeShared")
  init.luau        contract: VERSION, remote / attr names, Config (owner-tunable, see 4.14), formatting (won, mmss,
                   number pad), validation helpers (isNum, int, str), room-state JSON codecs
  Songs.luau       the catalog (section 4.18): legacy s01..s10 (same titles / lyrics / numbers) + new s11..s41;
                   genres, tags, parts; Songs.byId / byNo; 초성 index (Hangul choseong per title / artist)
  Chart.luau       chart(song, tempoStep) -> {bpm, beat, bar, intro, duration, lines{text, t0, t1, chars, sylT, part},
                   notes{t, lane, p, line, ch}, beatsN}; cached; port of ZIP Karaoke.chart (+ tempo factor
                   1 + 0.05*step); lineAt(chart, t); syllable progress helper for the wipe
  Score.luau       judge(dt), tapScore(perfect, good, total, maxCombo), voiceLine(v, r, o), voiceScore(lines, n),
                   beatOffset(chart, t), vibeBonus(onBeat), grade(score) -> {id, color, head, sub}, comments (Korean),
                   participation(...)
  Search.luau      choseong(str), normalize, match(song, query) (title / artist / number / 초성), ranking
src/ServerScriptService/GwangalliKaraokePlus/            (Script "GwangalliKaraokePlus")
  init.server.luau boot order (4.13), wiring, Active flag, BindToClose
  Bridge.luau      every integration: GameplayAPI (balance / spend / earn / addStats, timed + inflight guard),
                   VenueLife live table (capped / setAct / clearAct / fire / setBoard / notify / allowTeleport),
                   ProgressAPI track, SocialAPI joint, legacy takeover (disable panel prompts), GwangalliBuildingsSounds
                   ids, LEDScreen Messages; all pcall + fallbacks
  Net.luau         creates Remotes (KPRequest RemoteFunction, KPEvent RemoteEvent, KPLive UnreliableRemoteEvent with
                   RemoteEvent fallback); router with per-op validators, token buckets, rid cache, error codes
  Rooms.luau       discovery, room records, membership (KaraokeZone box), privacy / allowed list / knock / invite / kick,
                   intruder push-out, credits & purchases, renter handover, idle / empty release, state attributes +
                   legacy compat attributes
  Queue.luau       reservation queue (10, 3 per player), 우선예약, cancel, number reservation, start / stop / skip,
                   auto-advance timer, serial, tempo / key snapshot per song
  Mics.luau        2 mic slots per room: grab / put / pass offer (10 s TTL) / auto-return (leave 3 s, respawn, leave game);
                   sing act + mic prop via Bridge; singers list for the current song
  Scoring.luau     per-song session: tap hit intake (validate + judge), voice line intake, cheer / vibe meter,
                   settle -> results; rewards (capped stats, 서비스곡, Progress, Journey, Social), board + LED, records
  Voice.luau       Audio API rig per room (speaker anchor part in Workspace.GwangalliKaraokePlus.Room_NN): chain,
                   holder wires, echo presets, soundproofing access lists (narrow-only, restored); off when no device
  Library.luau     optional MR discovery (SearchAudioAsync -> verify load -> DataStore cache) -> State.Library attr
  Store.luau       player DataStore "GwangalliKaraokePlus_v1" (load / merge / autosave / leave / BindToClose, memory
                   fallback), weekly chart counts "GwangalliKaraokePlus_Chart_v1", optional per-song bests
src/StarterPlayer/StarterPlayerScripts/GwangalliKaraokePlus/   (LocalScript "GwangalliKaraokePlus")
  init.client.luau boot: wait Shared + Remotes + Active, Legacy.neutralize, build modules, Heartbeat / RenderStepped
  Net.luau         request(op, payload) with timeout -> {ok, code, message, ...}; on(kind, fn); live channel
  Kit.luau         thin adapter over GwangalliUI (K) + GwangalliLayout with a minimal fallback kit; Korean text helpers
  RoomWatch.luau   booth discovery (tag), state objects (State.Room_NN attributes -> typed room view), current room
                   (zone test 4 Hz), corridor-nearest room, stream in / out rebinding
  Legacy.luau      neutralises the GwangalliVenues karaoke UI / TV (3.2), re-asserting watchers
  Prompts.luau     local anchors + ProximityPrompts (4.11), texts per state (빈 방 / 이용 중 / 노크)
  TV.luau          SurfaceGui (PlayerGui, Adornee KaraokeScreen, Face Back, CanvasSize 1280x730, ZOffset 5,
                   LightInfluence 0, Brightness 1.6, MaxDistance 60): idle / ready / title / singing / score / next screens,
                   queue strip, effect emoji, confetti; light "attract" view for the corridor-facing room
  Lyrics.luau      two-line TJ wipe (port of ZIP KaraokeLyrics) with part colours
  Background.luau  generative 뮤직비디오 scenes made of Frames + UIGradients (광안대교 야경, 밤바다, 불꽃, 도시 네온,
                   벚꽃, 트로트 무대) chosen by genre; no image assets
  Band.luau        generated band + guide melody + optional asset track (Sound / AudioPlayer synced to KPT0), key / tempo,
                   local echo fallback (SoundGroup + Echo / Reverb / PitchShift effects), corridor muffled playback (EQ)
  Mic.luau         voice probe + AudioAnalyzer session (port of ZIP KaraokeMic), level meter feed
  Rhythm.luau      tap mode: note lane on the singer HUD, F / K / ButtonR2 / touch, batched hits to the server
  Book.luau        노래책 UI (tabs, search, rows, detail, favourites, 노래방 수첩 stats); read-only lobby mode
  Remote.luau      리모컨 UI (number pad, queue, 에코 / 키 / 템포 / 멜로디 / 점수, room settings, 퇴실)
  Hud.luau         action bar, payment sheet, singer strip, result card, mic offer card, knock / invite cards,
                   room-entry banner, HideGwangalliHUD attr
  Fx.luau          effects in Workspace.GwKaraokePlusLocal: disco SpotLights on an invisible anchor at the MirrorBall
                   position, laser Beams, sparkle / confetti ParticleEmitters (default texture), cheer sounds,
                   emotes (GwangalliAnim cheer / dance / clap)
```
The orchestrator must add 3 entries to `REPO/default.project.json` (not ours to edit):
`ReplicatedStorage.GwangalliKaraokeShared` → `src/ReplicatedStorage/GwangalliKaraokeShared`,
`ServerScriptService.GwangalliKaraokePlus` → `src/ServerScriptService/GwangalliKaraokePlus`,
`StarterPlayer.StarterPlayerScripts.GwangalliKaraokePlus` → `src/StarterPlayer/StarterPlayerScripts/GwangalliKaraokePlus`.

### 4.3 Runtime instances we create

| instance | by | content |
|---|---|---|
| `ReplicatedStorage.GwangalliKaraokeShared.Remotes` (Folder) | server | `KPRequest` (RemoteFunction), `KPEvent` (RemoteEvent), `KPLive` (UnreliableRemoteEvent, else RemoteEvent) |
| `ReplicatedStorage.GwangalliKaraokeShared.State` (Folder) | server | `Room_01..08` (Configuration: room attrs, 4.5), attr `Library` (MR JSON), `Chart` (TOP list JSON), `King` (today's top JSON) |
| attr `GwangalliKaraokeShared.Active` / `Version` | server | true once booted; clients neutralise legacy only then |
| attr `Workspace.GwKaraokePlus = true` | server | for other teams (interior notice text) |
| `Workspace.GwangalliKaraokePlus.Room_NN.Speaker` | server | Anchored, invisible, non-colliding, CanQuery / CanTouch false; 0.6 studs in front of the screen; holds `AudioEmitter` + rig (Voice) |
| `Workspace.GwKaraokePlusLocal` | client | prompt anchors, fx anchors, lights, particles (attr `LOD="near"` so GwangalliTextures skips it) |
| `PlayerGui.GwangalliKaraokePlus` (ScreenGui, DisplayOrder 44, ScreenInsets CoreUISafeInsets) | client | HUD / sheets |
| `PlayerGui.GwKP_TV` (SurfaceGui) | client | TV of the current room |
| `SoundService.GwKP_Band` (Folder + SoundGroup) | client | band pool, effects, analyzer (`GwKP_Mic`) |
| booth Model attrs `KRenter`, `KRenterName`, `KPaidUntil` (compat) + `KPState`, `KPCredits`, `KPSongNo`, `KPMicsOut`, `KPTambOut` | server | mirrors for legacy and interior readers |
| player attr `GwKPRoom` (room no or 0), `GwKPAct` ("clap" + serial) | server | other clients play the clap emote; quick lookups |

### 4.4 Remotes and payloads

`KPRequest:InvokeServer(op: string, payload: table?) -> { ok: boolean, code: string?, message: string? (Korean), ... }`

| op | payload | rules | returns |
|---|---|---|---|
| `hello` | `{}` | once per join | `{ ok, me = {fav, recent, best, stats, settings}, voice = Config.Voice }` |
| `buy` | `{ room: int, pack: "p1"\|"p4"\|"p8", rid: string≤24 }` | within 9 studs of the panel or inside; room free (this rents it) or player allowed; one in flight; credits after ≤ 30 | `{ ok, credits, renter }`; codes `busy`, `money`, `full`, `locked` |
| `reserve` | `{ room, song: str≤8, first: bool?, duet: bool? }` | inside + allowed; queue < 10, mine < 3 | `{ ok, qid }` |
| `reserveNo` | `{ room, no: int 10000..99999, first? }` | same, resolves Songs.byNo | `{ ok, qid, song }`; code `nosong` "없는 곡 번호예요" |
| `cancel` | `{ room, qid: int }` | own entry, or renter | `{ ok }` |
| `first` | `{ room, qid }` | own entry, or renter → move to top (우선예약) | `{ ok }` |
| `start` | `{ room }` | allowed; queue non-empty; not playing; credits > 0 | `{ ok, serial }` |
| `stop` | `{ room }` | current singer or renter; refund if `now - t0 < Config.RefundWindow` | `{ ok, refunded }` |
| `set` | `{ room, echo: 0..5?, key: -5..5?, tempo: -2..2?, guide: bool?, score: bool? }` | allowed member; tempo only when not playing (applies to the next song) | `{ ok }` |
| `privacy` | `{ room, mode: "lock"\|"friends"\|"open" }` | renter | `{ ok }` |
| `invite` / `kick` | `{ room, userId: int }` | renter; target in server / within 40 studs | `{ ok }` |
| `knock` | `{ room }` | outside, near the panel, cooldown 8 s | `{ ok }` (renter gets `knock` event) |
| `leave` | `{ room }` | renter → release (warns about credits on the client first); guest → just leaves | `{ ok }` |
| `mic` | `{ room, action: "grab"\|"put"\|"pass", slot: 1\|2?, to: userId? }` | inside + allowed; pass target inside | `{ ok, slot }` |
| `micAnswer` | `{ room, offer: int, accept: bool }` | the offered player | `{ ok }` |
| `hits` | `{ room, serial: int, hits: { {i: int, dt: number} } ≤ 24 }` | current singer; ≥ 0.2 s between batches | `{ ok, judged = {perfect, good, combo} }` (live, for the HUD) |
| `voice` | `{ room, serial, lines: { {li, v, r, o} } ≤ 3 }` | current singer in voice mode; ≥ 0.25 s apart | `{ ok, live }` |
| `voiceStatus` | `{ live: bool, why: str≤12? }` | client probe result, ≤ 1 per 5 s | `{ ok }` |
| `cheer` | `{ room, kind: "tamb"\|"clap"\|"cheer"\|"fire"\|"dance", beats: {number}≤8? }` | inside + allowed; 3/s; tamb beats = client song times of on-beat shakes | `{ ok, vibe }` |
| `fav` | `{ song, on: bool }` | ≤ 30 favourites | `{ ok }` |
| `settings` | `{ lyricSize: "S"\|"M"\|"L"?, guideVol: 0..1?, bandVol: 0..1?, sync: 0..0.8?, monitor: bool?, mode: "auto"\|"tap"? }` | | `{ ok }` |
| `rank` | `{ song }` | 1/s | `{ ok, top = {{name, score}} ≤ 5, mine }` (optional OrderedDataStore, cached 60 s) |

`KPEvent` (server → one client): `{kind="toast", title, body}` (only when VenueLife.ctx.notify is missing),
`{kind="knock", room, from, name}`, `{kind="micOffer", room, offer, from, name, slot}`, `{kind="result", room, serial,
scores = {{uid, name, score, grade, mode, perfect, good, miss, combo, vibe}}, mine = {score, best, isBest, rank,
rewards = "행복 +3 · 인기도 +1", bonusSong = bool}}`, `{kind="kicked", room, reason}`, `{kind="enterDenied", room}`.

`KPLive` (server → room members, unreliable): `{kind="fx", room, fx = "tamb"|"clap"|"cheer"|"fire"|"dance", from = uid}`,
`{kind="judge", room, uid, j = "P"|"G"|"M", combo}` (so listeners' TVs show the singer's judgements), `{kind="vibe", room, v}`.

Error codes → Korean messages (examples): `room` "방을 찾을 수 없어요", `notInside` "방 안에서만 할 수 있어요",
`locked` "다른 손님이 이용 중인 방이에요 🔒", `money` "잔액이 부족해요", `credits` "남은 곡이 없어요 · 동전을 넣어 주세요",
`queueFull` "예약은 10곡까지예요", `mine` "한 사람당 3곡까지 예약할 수 있어요", `rate` "잠시 후에 다시 시도해 주세요",
`renter` "방 주인만 할 수 있어요".

### 4.5 Room state (ReplicatedStorage `State.Room_NN` Configuration attributes)

| attr | type | meaning |
|---|---|---|
| `No`, `Name` | int, str | 1..8, "01".. |
| `State` | str | `free` / `open` / `intro` / `sing` / `settle` / `score` |
| `Renter`, `RenterName` | int, str | 0 = free |
| `Credits` | int | remaining songs (0..30) |
| `Privacy` | str | `lock` (default) / `friends` / `open` |
| `Allowed` | str JSON | `[uid, ...]` ≤ 12 (renter included) |
| `Members` | str JSON | `[uid, ...]` currently inside (server zone test, 1 Hz) |
| `Queue` | str JSON | `[{q=qid, s="s12", by=uid, n="name", d=duet}]` ≤ 10 |
| `Serial` | int | increments per started song |
| `Song`, `SongNo` | str, int | current song ("" if none) |
| `T0`, `Dur` | number | server time of beat 0 (title card + count-in before it), chart duration (s) |
| `Tempo`, `Key`, `Echo` | int | −2..2, −5..5, 0..5 (Echo default 3) |
| `Guide`, `ScoreOn` | bool | 멜로디 가이드, 점수 표시 |
| `Singers` | str JSON | `[{u=uid, n="name", m="voice"\|"tap", s=1\|2}]` |
| `Mics` | str JSON | `[uid or 0, uid or 0]` |
| `Vibe` | int 0..100 | 분위기 meter |
| `Result` | str JSON | last result `{serial, scores=[{u,n,s,g}], bonus}` |
| `NextT` | number | server time the next queued song auto-starts (0 = none) |
| `IdleT` | number | server time of auto-release if nothing happens (shown as a warning) |
| `VoiceRig` | bool | the Audio API speaker rig is live |

Booth Model mirrors: `KRenter`, `KRenterName`, `KPaidUntil` (= now + 60·Credits), `KPState`, `KPCredits`, `KPSongNo`,
`KPMicsOut` ("1,2" slots out, "" none), `KPTambOut` (bool). `KSong` stays "".

### 4.6 Data schemas

**Song** (Songs.luau):
```lua
{ id = "s12", no = 39572, title = "드론쇼 하늘 위에", artist = "네온캣", genre = "댄스", bpm = 124,
  part = "F",            -- "M" 남 / "F" 여 / "MF" 혼성 / "D" 듀엣 (line parts below)
  stars = 2, tags = { "new" }, year = 2026, credit = "작사·작곡 광안 노래방 오리지널",
  lines = { "…", "…" },  -- 8-12 ORIGINAL lines; a duet line may be { text = "…", part = "M" }
  form = nil,            -- optional order of line indices (1절-후렴-2절), nil = as written
  seed = 12 }
```
The number is `38000 + i*131` for every catalog index i. This keeps the legacy numbers and the interior's `songNo(i)`
formula identical. Legacy ids s01..s10 keep their exact titles, artists and lyrics, so the LED "TOP 100" text and the
"이달의 신곡" sign stay true.

**Chart**: see Chart.luau above. The intro is 1 bar of title card + count-in. Each lyric line spans 2 bars (8 beats):
syllables on the half-beat grid over 6 beats, then 2 beats of rest. Optional `form` repeats lines.
Duration target is 45-100 s (`Score.validate()` checks 20..140).

**Player record** (DataStore `GwangalliKaraokePlus_v1`, key `u_<UserId>`, UpdateAsync merge, autosave every 180 s when dirty,
save on leave and in BindToClose, memory-only fallback):
```lua
{ v = 1,
  fav = { "s03", ... },                    -- ≤ 30 (애창곡)
  recent = { { s = "s05", t = os.time(), sc = 92 }, ... },   -- ≤ 20
  best = { s05 = 97, s12 = 88 },           -- per-song personal best
  stats = { songs = 0, hundred = 0, duets = 0, tamb = 0, firstT = 0 },
  settings = { lyricSize = "M", guideVol = 0.6, bandVol = 0.8, sync = 0.25, monitor = false, mode = "auto" } }
```
Merge rule: `fav` and `settings` take the newest. `best` takes the max per song. `stats` take the max per field
(monotonic). `recent` is the union, newest 20.

**Chart counts** (`GwangalliKaraokePlus_Chart_v1`, key `w_<ISO week>`): `{ [songId] = plays }`. Each server keeps
increments in memory and flushes them every 5 min with UpdateAsync (add). It reads back the top 20 on boot and after
each flush → `State.Chart` attr + LED.

**Today's king** (per server, like legacy): `{ {name, userId, score, title} }` top 5 → board + `State.King`.

### 4.7 Economy and rewards (Config defaults)

- Packs: `p1` 1곡 500원 · `p4` 4곡 1,000원 (지폐) · `p8` 8곡 2,000원 (지폐 2장). Ledger labels:
  "코인노래방 ROOM 03 · 4곡". Whoever pays the first pack becomes the renter. Allowed guests can add packs too ("같이 내기").
- A credit is used at song start (intro). `stop` within 5 s of T0 refunds it ("곡 취소 · 1곡 돌려받았어요").
- 서비스곡: a score of 100 (Config.BonusScore = 100) gives +1 credit ("🎉 100점! 서비스 1곡"). At most 2 per room session.
- Room release: empty for 20 s; or `open` with 0 credits and no activity for 150 s (warning banner at 120 s "곡을 추가하지
  않으면 30초 뒤 방이 비워져요"); or the renter leaves the game → the earliest allowed member still inside becomes renter
  (toast "방장이 바뀌었어요"), else release. Unused credits are lost on release, and the client warns before 퇴실.
- Rewards per singer per finished song (participation ≥ Config.MinParticipation):
  `VenueLife.capped(p, "venue_karaoke", 12, {happiness = 3})`; score ≥ 90 → `capped(p, "venue_karaoke90", 3, {popularity = 1})`;
  `ProgressAPI track karaoke_song 1`; `VenueLife.fire(p, {kind="kResult", room=0, serial, name, score, mine=true})`;
  `SocialAPI joint(p, "karaoke")` (the companion; Relationships applies its own daily max).
  Fallbacks without VenueLife: `GameplayAPI addStats` with an in-memory per-day cap.
- Cheer: an on-beat tambourine shake (|offset| ≤ 0.08 s of a half beat) adds to `Vibe`. When the song ends, the singer gets
  `vibeBonus` up to +3 (score capped at 100). A listener with ≥ 8 on-beat shakes gets `capped(p, "kp_cheer", 5, {happiness = 1})`.
- No cash payouts, so karaoke stays a money sink plus happiness, popularity and social.

### 4.8 Scoring

- **Tap mode** (no voice device, or setting "박자 모드"): notes come from the chart (3 lanes). The singer HUD shows the lane,
  and presses go to the server in batches as `{i, dt}`. Per hit the server checks: `i` in range and not already judged;
  arrival song time `st = (now - T0)` with `note.t - LIVE_SLACK ≤ st ≤ note.t + STALE`; `|dt| ≤ early`; then judges with
  `Score.judge(dt)`. It tracks combo and max combo. Final: `Score.tapScore(perfect, good, total, maxCombo)`, the legacy curve
  (40 + 60·raw) plus a small combo term.
- **Voice mode** (the singer's client reports `voiceStatus live`, and the singer holds a mic during ≥ `MIC_SEEN` lines):
  the client analyzer produces per line `v` (syllables voiced), `r` (rests kept quiet) and `o` (onsets). The server accepts
  each line once, inside `[lineEnd - SEND_SLACK, lineEnd + STALE]`, clamps the values to 0..1 and computes `Score.voiceScore`.
  A mean `v` below 15 counts as not sung, so there is no reward. TV badge "🎤 LIVE VOICE".
- **Participation**: the share of notes judged (any) or lines with `v ≥ 0.15`, at least 30% and song ≥ 60% elapsed while inside.
  Stopping early gives no score.
- **Duet**: up to 2 singers (mic slots 1 and 2), each scored separately, shown as 1P / 2P on the TV. The board takes each
  singer's score.
- **Result presentation**: settle 1.5 s → drumroll 1.6 s ("두구두구…") → count-up → grade and comment, held for 6 s.
  100점 gives a fanfare, confetti, the room lights in gold and "서비스 1곡". Comments extend `V.scoreComment`:
  100 "축하합니다! 100점! 🎉 전국 노래자랑 나가도 되겠어요", 95+ "와우! 가수 데뷔각?", 90+ "노래 실력이 프로급이에요",
  80+ "노래 실력 수준급! 👏", 70+ "흥이 넘쳐요!", <70 "다음엔 더 잘할 수 있어요 · 탬버린이라도 열심히 🪇".

### 4.9 Audio

- **Generated band** (client `Band.luau`, port of ZIP KaraokeBand): a 16th grid with a lookahead scheduler (0.1 s).
  Kick (`action_jump_land.mp3` pitched 0.6), snare (`clickfast.wav` 0.8 + `swoosh.wav` short), hats (`clickfast.wav` 1.8,
  quiet), bass (`electronicpingshort.wav` at 0.31-0.5 speed following I-vi-IV-V roots per genre), arpeggio, pad (soft pings),
  fills plus a crash at section changes, and the **guide melody** (the chart's note pitches; toggle "멜로디").
  Key shifts every pitched tone by `2^(key/12)`. Genre presets: 발라드 (half-time, pad), 댄스 / EDM (four-on-the-floor),
  트로트 (뽕짝 2-beat, bass on 1 and 3), 록 (8th hats, backbeat), 힙합 (boom-bap swing).
  Pools: 16 ping + 12 click Sounds in `SoundService.GwKP_Band`. Volumes follow `bandVol` and `guideVol`, and stay under
  K.settings.sound = false (mute).
- **Owner instrumentals** (`Config.SongAudio[id] = { id = "rbxassetid://…", bpm, offset, gain }`, empty by default):
  `Sound` (or `AudioPlayer`) with `TimePosition = now - T0 + offset`, resynced when drift > 0.08 s. Key comes from
  `PitchShiftSoundEffect` (Octave = 2^(key/12)) or `AudioPitchShifter`. The generated band then plays only the guide melody.
- **Library MR** (`Config.LibraryMR = true`, published place only): server `Library.luau` sends ≤ 6 SearchAudioAsync
  queries ("karaoke instrumental", "kpop instrumental", "piano ballad", "acoustic guitar", "city pop", "lofi"), with
  AudioSubType Music and 60-240 s. It verifies by loading (`IsLoaded`, 8 s), caches in DataStore `GwangalliKaraokePlus_MR_v1`
  for 24 h and publishes `State.Library` = `[{id="m01", no=90001, title, artist, len, asset}]` ≤ 20. These show in the
  노래책 tab "MR 반주곡": no lyrics, TV visualizer (PlaybackLoudness bars), voice score only (tap mode shows "점수 없음 · 자유곡").
  Failure or empty result means the tab is hidden.
- **Echo** without the Audio API: a local `EchoSoundEffect` + `ReverbSoundEffect` on the band SoundGroup's guide channel, set
  from `Echo` (presets from ZIP `ECHO_PRESETS`; level 0 bypasses). The remote label reads "에코 (멜로디)".
- **Voice rig** (server `Voice.luau`, port of ZIP KaraokeVoice, `Config.Voice = "auto"`):
  - a room speaker anchor + `AudioEmitter` with the chain In(AudioFader 1.4) → AudioCompressor (−20 dB, 4:1, 6 dB makeup) →
    AudioEqualizer (−3 / 0 / +2) → AudioEcho → AudioReverb → Out(AudioFader). One `Wire` per mic holder that has an
    engine `AudioDeviceInput`. `Echo` level → echo / reverb presets. State attr `VoiceRig = true`.
  - soundproofing: for every member inside, set the device's `AccessType = Allow` and the access list to the members, so
    people outside cannot hear the room. Lists only ever narrow: existing Allow / Deny lists are intersected and restored
    on leave or release.
  - client (`Mic.luau` / `Band.luau`): when `VoiceRig` is true, mute the dry character voice of mic holders locally
    (`AudioInteractionGroup = "GwKP_DryOff"` on their character emitter for this listener only) so only the echoed room
    speaker carries their voice. The singer's own wire is cut locally unless "내 목소리 듣기 (이어폰)" is on.
    Listener sync delay `sync` (default 0.25 s) delays the band for listeners to match voice latency (the singer uses 0).
  - Never creates an `AudioDeviceInput`. Never reads PluginSecurity properties. Everything is pcall'd.
- **Corridor / lobby**: when the player is outside any room but within 14 studs of a playing room's door, the client plays that
  room's band at 25% through an `EqualizerSoundEffect` (HighGain −40, MidGain −12), so the song is heard muffled. One room at a time.
  The lobby BGM is optional: `GwangalliBuildingsSounds.karaoke_music` at 0.15, only when no room is audible.

### 4.10 UI screens (all Korean; GwangalliUI look: dark glass, cyan / magenta / gold, radii 12-24)

1. **Room-entry banner** (bottomCenter, 3 s): "🎤 ROOM 03 · 남은 곡 4곡 · 예약 2곡", plus for a guest "○○님의 방".
2. **Action bar** (bottomCenter, inside an allowed room): `[🎵 노래책] [📟 리모컨] [🎤 마이크] [🪇 탬버린 | 👏 박수] [🎉]`.
   🎉 opens a mini tray (환호 / 폭죽 / 춤). With the mic held, the 🎤 button reads "마이크 내려놓기" and the tambourine
   button becomes 👏 (no prop clash). During the singer's own song the bar shrinks to `[📟] [■ 취소]`.
3. **Payment sheet** (동전 넣기): title "🪙 ROOM 03 · 동전 · 지폐 넣기", balance row "현금 12,300원 · 통장 45,000원",
   pack rows `1곡 500원` / `4곡 1,000원 · 지폐` (badge "이득") / `8곡 2,000원`, footnote "남은 곡은 퇴실하면 사라져요 (환불 불가)".
   On success: coin sound, the TV shows "남은 곡 4" and the panel turns red.
4. **노래책 (Book)**: header "📖 노래책 · 총 41곡". Tabs `인기차트 | 신곡 | 장르 | 애창곡 | 최근 부른 곡 | MR`. Search bar
   "제목 · 가수 · 초성 · 번호 검색" (예: ㄱㅇㄷㄱ → 광안대교 불빛 아래). Genre chips (발라드 / 댄스 / 트로트 / 힙합 / 록 /
   인디 / 시티팝 / EDM / 축하곡 / 듀엣). Row: `39572 | 드론쇼 하늘 위에 / 네온캣 · 댄스 · 1:12 · ★★☆ · 여 | [예약] [♥]`.
   Row detail on tap: 2 lyric preview lines, BPM, "내 최고 92점", "이 서버 최고 ○○ 98점", [예약] [우선예약] [듀엣 예약].
   Footer: "남은 곡 3 · 예약 2/10 · [동전 넣기]". Lobby mode (CatalogBook): the same book without reserve buttons, plus
   "방을 잡으면 바로 예약할 수 있어요". Includes the **노래방 수첩** page: 총 부른 곡, 100점 횟수, 최고 점수 곡,
   애창곡 TOP 3, 듀엣 횟수.
5. **리모컨 (Remote)**: a 5-digit LED display, keypad 1-9 / 0 / ⌫, `[예약] [우선예약] [시작] [취소]`. Rows: 에코 `− ■■■□□ +`
   (labels 끄기 / 약하게 / 조금 / 기본 / 많이 / 동굴), 키 `♭ 0 ♯`, 템포 `− 0 +` ("다음 곡부터"), 멜로디 on/off, 점수 on/off,
   반주 볼륨 slider, 싱크 slider (voice listeners). 예약 목록 rows `1. 39441 수변공원 노을 · 민수 [▲] [✕]`.
   Room settings (renter): 방 공개 `🔒 잠금 | 👥 친구만 | 🌐 누구나`, `초대하기` (nearby players list), `내보내기`,
   `퇴실하기` (confirm "남은 2곡은 사라져요. 나갈까요?").
6. **TV (SurfaceGui, 1280×730)**:
   - idle (free): "동전을 넣어 주세요 🪙" big, "1곡 500원 · 4곡 1,000원", room number, slideshow (TOP 5, 신곡 3, 오늘의 노래왕), clock.
   - ready (credits, nothing queued): "곡을 선택해 주세요 🎤", "남은 곡 N", recommended songs, "리모컨 · 노래책으로 예약".
   - title card (intro): number, title, artist, 작사·작곡 credit, genre, KEY / TEMPO badges, ★, singer names (1P / 2P),
     4 count-in dots ●●●●.
   - singing: background scene; top bar `♪ 39572 드론쇼 하늘 위에 · 네온캣 | 다음 ▶ 38262 민락동 치킨송 | 남은 곡 3`;
     ECHO / KEY indicators; two-line lyrics with a syllable wipe (upper line left-aligned, lower right-aligned; base white with
     a dark stroke; fill cyan for 남 / pink for 여 / green for 같이); 4-dot countdown before lines after a gap; "♬ 간주중 ♬" with
     a progress bar; lower-left live judgements (PERFECT / GOOD / MISS + COMBO) or a voice meter; bottom progress bar;
     분위기 meter; emoji rain for cheers (👏 🪇 🎉 🔥).
   - score: dark overlay, "두구두구…" drum, big number count-up (gold), grade chip, comment, per-singer cards for a duet,
     "내 최고 기록 갱신!" / "오늘의 노래왕 2위", "서비스 1곡!" banner, confetti frames.
   - next: "다음 곡 3…" + title.
   - corridor attract view (an adjacent room seen from outside): "ROOM 03 · 이용 중 · ♪ 제목" only, low update rate.
7. **Singer HUD** (when you sing): a lyric strip (current + next line, wipe) above bottomCenter, for readability on phones.
   Tap mode: a compact 3-lane note strip + a big "♪ 박자" button at `rightColumn.sprint` (touch), F / K / ButtonR2.
   Voice mode: mic level meter + "마이크를 가까이 · 가사 색을 따라 불러요". `HideGwangalliHUD = true` while singing.
8. **Result card** (singer): score, grade, rewards line ("행복 +3 · 인기도 +1"), "애창곡에 추가 ♥", `[한 곡 더]` (opens the book).
9. **Cards**: mic offer "○○님이 마이크를 건넸어요 🎤 [받기] [괜찮아요]" (10 s); knock "똑똑! ○○님이 들어오고 싶어해요
   [들어오세요] [거절]"; denied "🔒 이 방은 잠겨 있어요 · 노크해 보세요".

### 4.11 Prompts (client-local, on our own anchors in `Workspace.GwKaraokePlusLocal`) and input

| anchor at | prompt (ActionText / ObjectText) | condition | action |
|---|---|---|---|
| KaraokePanel + 0.3 toward the corridor | "방 잡기" / "ROOM 03 · 1곡 500원" | free | payment sheet |
| same | "노크하기" / "ROOM 03 · ○○님 이용 중" | busy, not allowed | `knock` |
| same | (none, a banner instead) | allowed | — |
| KaraokeMachine top (coin slot) | "동전 넣기" / "남은 곡 N곡" | inside, allowed (or free → rent) | payment sheet |
| Remote | "리모컨" / "예약 · 에코 · 키" | inside, allowed | remote |
| SongBook | "노래책 보기" / "총 41곡" | inside | book |
| WirelessMic 1 / 2 | "마이크 잡기" / "무선 마이크 1" | slot free, allowed | `mic grab` |
| Tambourine | "탬버린 흔들기" | allowed, not holding a mic | `cheer tamb` + act |
| lobby CatalogBook | "노래책 보기" / "노래 책 · 신곡 목록" | always | book (read-only) |
| lobby Board_karaoke face | "랭킹 보기" / "오늘의 노래왕" | always | ranking sheet |
| lobby CoinChanger | "지폐 교환" / "1,000원 → 500원 동전 2개" | always | flavour toast + coin sound, no money change ("방 안 코인기에 바로 결제돼요") |

All prompts: KeyboardKeyCode E, GamepadKeyCode ButtonX, HoldDuration 0, RequiresLineOfSight false, Exclusivity
OnePerButton, MaxActivationDistance 6 (table) / 8 (panel, lobby). Anchors are recomputed when a booth streams in.
They use the map props' CFrames read once, and stay valid while the interior team hides the props.

Bindings (ContextActionService at normal priority, only inside an allowed room, released on leave). Chosen after
grepping the place's key usage: M = global TravelKey (`GwangalliConfig.ModuleScript.luau:290`), J = GwangalliInteractClient
/ EMS, P + DPadUp = phone, ButtonX = prompts. The bindings: `B` / ButtonY = 노래책, `N` / ButtonL1 = 리모컨, `T` / ButtonR1 = 탬버린
(T is only the car radio while driving), `F` `K` / ButtonR2 = 박자 (tap mode only; F matches the legacy key), `Esc` / ButtonB =
close sheet. The mic has no hotkey (prompt or action-bar button). Space is never bound, because jump stays jump. Sheets
support gamepad selection (`GuiService.SelectedObject` on the first row).

### 4.12 Player flows

**A. Rent and sing alone**
1. Walk into the corridor. The panel shows "빈 방 · 터치" (green). The prompt reads "방 잡기 · 1곡 500원".
2. Open the payment sheet → choose "4곡 1,000원" → `buy{room, pack="p4", rid}`. The server checks distance, room free and
   money, then calls `GameplayAPI spend(1000, "코인노래방 ROOM 03 · 4곡")`. On success: Renter = you, Credits = 4,
   State `open`, compat attrs (StatusLight red), `VenueLife.fire(p, {kind="kOpen", room=0})` for Journey. Toast "🎤 ROOM 03을
   잡았어요 · 남은 곡 4곡".
3. Enter. The banner appears and the action bar shows. Open 노래책 → search "치킨" → [예약] → `reserve`. Queue = 1. If nothing
   is playing, the server auto-starts after 1.5 s: a credit is used (3 left), Serial+1, Song, `T0 = now + 3 + intro`; the
   reservation owner auto-grabs a free mic (`setAct sing + mic` prop, visible to all).
4. Title card + count-in. The song plays. Voice device live → voice mode: you sing into the mic, the room speaker echoes,
   and the meter moves. Otherwise tap mode: press 박자 on notes.
5. End → settle → drumroll → score 87 "노래 실력 수준급! 👏". Result card: "행복 +3". Board updated if in today's top 5.
   Progress goal +1. Record saved.
6. Queue empty → State `open`, "곡을 선택해 주세요". Leave the room: the empty-grace timer runs. After 20 s the room is released
   (remaining credits lost; the warning was shown when leaving via 퇴실 or the door).

**B. Friends, duet, cheering**
1. The renter's room is 🔒 잠금 by default. A friend at the panel sees "노크하기". Knock → the renter's card [들어오세요] →
   `invite` → the friend is allowed. (With "친구만", Roblox friends of the renter are allowed automatically.)
2. The friend reserves "너의 이름 광안리 (듀엣)" with [듀엣 예약]. At start the two mic holders become 1P and 2P. Lyric
   lines are coloured by part.
3. The others press 🪇 탬버린: the VenueLife act + prop shows, a jingle sound plays, on-beat shakes fill 분위기, the TV shows
   🪇. 👏 / 🎉 / 🔥 make sounds, emoji and emotes (cheer animation, clap emote via `GwKPAct`).
4. Result: two score cards. 분위기 보너스 +2 each. 100점 → "서비스 1곡!" (+1 credit).

**C. Remote controls**: 에코 ▲ → `set{echo=4}` → Voice rig presets, or the local fallback; TV indicator. 키 ♯2 → band
   pitch +2 semitones for everyone in the room. 템포 + → next song chart at 1.05×. Number pad "38262" + 우선예약 → that song
   goes to the top of the queue. 취소 within 5 s → refund.

**D. Mic passing**: holder → 리모컨 or the mic button → "마이크 넘기기" → pick a member → their offer card → [받기] → server moves the
   slot (clearAct on the giver, setAct on the receiver). Walking out with a mic for > 3 s or respawning puts it back
   ("마이크를 제자리에 뒀어요").

**E. Intruder / locked room**: a non-allowed player walks in → after 1.5 s inside: `allowTeleport(p, 3)` → moved to 3.5 studs
   outside the panel (corridor side), facing the corridor → toast "🔒 ROOM 03은 다른 손님이 이용 중이에요 · 노크해 보세요".
   In "누구나" mode anyone may enter. People inside when the mode switches to locked stay allowed.

   Implementation details: if the intruder is seated (`Humanoid.SeatPart`), set `Humanoid.Sit = false` and wait one Heartbeat first.
   Target = `panel.Position + d * 3.5` with `d` = the horizontal unit vector from the KaraokeZone centre to the panel, and
   y = 6.85 + 3 (root height). Apply it with `PivotTo` on the character. Allow-listed: anyone in `Allowed`, the renter's Roblox
   friends in "친구만" mode (cached `Player:IsFriendsWith`, run in a task), and everyone in "누구나".

**F. Lobby**: 노래책 at the catalog stand (read-only), "랭킹 보기" on the board, the LED cycles "TOP 인기차트|1위 ♪ …|오늘의
   노래왕 ○○ 98점", and the coin changer flavour. Journey "karaoke.open" fires when a player first rents or joins a room.

**G. Edge cases**: the renter leaves the game → handover or release. Server shutdown → BindToClose saves records.
   No GameplayAPI → "무료 체험" packs. Plus server not active → the client does nothing and the legacy karaoke remains
   (no neutralisation).

### 4.13 Server boot and loops

Boot (`init.server.luau`):
1. `require(ReplicatedStorage:WaitForChild("GwangalliKaraokeShared", 30))`. If missing: warn and exit.
2. `Net.create()` (Remotes, `Active = false`). `Store.init()`.
3. `Bridge.init()`: GameplayAPI (wait ≤ 30 s, lazy re-lookup later), VenueLife (find the Folder, require, wait for `.V` ≤ 40 s),
   ProgressAPI / SocialAPI (lazy per call), GwangalliBuildingsSounds (optional).
4. `Rooms.discover()`: CollectionService "KaraokeRoom" Models with numeric `RoomNo`, a BasePart `KaraokeZone`, `KaraokePanel`
   and `KaraokeScreen`, under a venue named in `Config.VenueModelNames` (default `{"광안 코인노래연습장"}`). Also listen for
   tag added (late builds). Create State `Room_NN` + the speaker anchor.
5. Legacy takeover (if `Config.TakeOverLegacy`): wait ≤ 10 s for `GwangalliKaraokePrompt`, then disable all server prompts
   under each panel (+ watchers). Write compat attrs = free.
6. Start loops. `Active = true`. `Workspace.GwKaraokePlus = true`.
7. Players: PlayerAdded → `Store.load`. PlayerRemoving → mics back, membership / renter handover, `Store.save`.

Loops: **0.25 s room step** (state machine: `open` + queue + credits → `intro` (T0 = now + Config.Countdown 3 + intro) → `sing`
(now ≥ T0) → `settle` (now ≥ T0 + Dur) → +1.5 s compute → `score` (`Result`, events, rewards) → +7.6 s (`NextT`) → next
`intro` or `open`). **1 s membership step** (zone test → `Members`, intruders, mic leave grace, empty / idle release, voice
access lists sync, compat attrs). **5 min** chart flush. **60 s** LED + board refresh (only when changed).

### 4.14 Config (owner-facing, `GwangalliKaraokeShared/init.luau`)

```lua
Config = {
  Enabled = true, TakeOverLegacy = true, Billing = "credits",      -- "legacy" = keep VenueKaraoke time rental (Phase 2)
  VenueModelNames = { "광안 코인노래연습장" },
  Packs = { { id = "p1", songs = 1, price = 500 }, { id = "p4", songs = 4, price = 1000, badge = "이득" },
            { id = "p8", songs = 8, price = 2000 } },
  MaxCredits = 30, RefundWindow = 5, BonusScore = 100, BonusSongsMax = 2, FreeWhenNoEconomy = true,
  EmptyGrace = 20, IdleRelease = 150, IdleWarn = 120, Countdown = 3, NextGap = 7.6,
  QueueMax = 10, QueuePerPlayer = 3, AllowedMax = 12, DefaultPrivacy = "lock",
  Voice = "auto",                -- "auto" | "off"
  LibraryMR = true,              -- SearchAudioAsync MR tab (published places only)
  SongAudio = {},                -- [songId] = { id = "rbxassetid://…", bpm = , offset = , gain = 0.5 } (licensed only)
  Rewards = { song = { happiness = 3 }, daily = 12, high = { popularity = 1 }, highMin = 90, highDaily = 3,
              cheer = { happiness = 1 }, cheerDaily = 5, minParticipation = 0.3 },
  WriteLED = true, WriteBoard = true,
}
```
Owner recommendations: (1) For the voice echo and soundproofing, in Studio select `VoiceChatService` and set
`UseAudioApi = Enabled`, `EnableDefaultVoice = true`. Voice must also be enabled in Game Settings → Communication.
(2) Optional real backing tracks: fill `SongAudio` with licensed instrumentals only, never covers of real songs.

### 4.15 Performance budget

TV and lyrics update at 30 Hz only for the current room, with no per-frame instance or string allocation (the reference
discipline). The corridor attract view updates at 2 Hz. The band scheduler runs on Heartbeat with a 0.1 s lookahead and
≤ 28 pooled Sounds. Fx: ≤ 2 lights, ≤ 3 particle emitters, only during songs. Server: the 0.25 s step over 8 rooms, no
allocations in the steady state. JSON attrs are rewritten only on change. DataStore traffic: about 2 writes per player
per session plus 1 per 5 min per server.

### 4.16 Test plan

1. Offline (luau CLI + mock runtime copied from `bprev/lib/rbx.luau` into `feat/karaoke/`): Chart determinism across tempos,
   catalog validation (numbers unique, 20 ≤ duration ≤ 140, ≥ 3 notes per line), `Search.choseong` / match cases
   ("ㄱㅇㄷㄱ", "38262", "치킨"), Score curves (0 / 50 / 100 points), judge windows, the queue state machine with fake players
   and fake clocks (cancel refund, 우선예약, per-player cap, auto-advance), mic offers, membership, intruders, and Store merge rules.
2. `luau-compile --binary` every file. `luau-analyze` (ignore Roblox-global noise).
3. Temp studio (flock + timeout 1500, one run): inject the three trees with the `build_studio.py` pattern. In the server ctx,
   teleport the player into Booth_01 → `buy p4` (free mode if no API) → `reserve s02` → wait → screenshot the TV
   (title / lyrics / score) → check `KRenter`, State attrs, that the legacy prompt is disabled, that the legacy bar is gone,
   and that `Board_karaoke` Row1 updated → leave → release after 20 s.
4. Live (owner, Roblox): voice rig with two voice accounts (echo audible, soundproofing from the corridor), SearchAudio MR tab, DataStore persistence.

### 4.17 Cross-team / orchestrator notes

- **Interior team (`GwangalliBuildingInterior/T_karaoke.luau`)**: please (a) show "남은 곡 N곡" on the coin LCD when booth attr
  `KPCredits` exists (else keep the KPaidUntil text); (b) on the VFD prefer `KPSongNo` (number) over `KSong`; (c) hide your
  local table-mic copies for the slots listed in `KPMicsOut` ("1", "2", "1,2") and your tambourine copy while `KPTambOut == true`;
  (d) when `Workspace:GetAttribute("GwKaraokePlus") == true`, change the notice text to "1곡 500원 · 4곡 1,000원 · 100점이면 서비스 1곡"
  and the tablet header to "리모컨 · 노래책으로 예약". Our prompts live in `Workspace.GwKaraokePlusLocal`, so keep them clear like other prompts.
- **Orchestrator**: add the 3 Rojo entries (4.2). Bundle and build scripts are not ours.
- Not ours, flag to the owner: the Journey hint "500원이면 30분!" (`GwangalliPlayShared/Journey.ModuleScript.luau:196`) and the
  legacy `GwangalliVenuesShared` contract comments describe the old rental.

### 4.18 Song catalog plan (all ORIGINAL; fictional artists; no real lyrics)

Legacy (kept verbatim, numbers 38131 … 39310): s01 광안대교 불빛 아래 (파도청년단, 발라드 84), s02 민락동 치킨송 (바삭즈, 댄스 120),
s03 2호선 막차 (금련산 밴드, 록 132), s04 갈매기 트로트 (김부산, 트로트 104), s05 썸머 모래성 (오션걸즈, 팝 112), s06 PC방 영웅 (레벨업,
힙합 96), s07 새벽 편의점 (도시소년, 인디 88), s08 득근득근 (헬스보이즈, EDM 128), s09 해운대 말고 광안리 (수영구 청년회, 시티팝 100),
s10 생일 축하해 친구야 (노래방 오리지널, 축하곡 108).

New (s11-s41, numbers 39441 … 43371; 8-12 lines each, written in implementation):
s11 수변공원 노을 (바닷마을 밴드, 발라드 76, 여) · s12 드론쇼 하늘 위에 (네온캣, 댄스 124, 여) · s13 국밥 한 그릇의 위로 (서면 블루스,
블루스 82, 남) · s14 남천동 벚꽃길 (봄날소녀, 팝 108, 여) · s15 해운대에서 광안리까지 (파도청년단, 록 140, 남) · s16 밤바다 버스킹 (기타소년,
어쿠스틱 92, 남) · s17 퇴근길 막차 버스 (도시소년, 인디 96, 남) · s18 첫 월급 (레벨업, 힙합 94, 남) · s19 광안대교 드라이브 (시티라이트,
시티팝 112, 혼성) · s20 엄마의 된장찌개 (김부산, 트로트 100, 남) · s21 오늘도 출근 (직장인 밴드, 록 128, 남) · s22 썸 타는 중 (오션걸즈,
팝 116, 여) · s23 파도 위의 고백 (윤바다, 발라드 72, 남) · s24 깡통시장 야시장 (부산 트로트, 트로트 118, 여) · s25 불꽃축제 (네온캣, EDM 128,
여) · s26 편의점 알바 (레벨업, 힙합 90, 남) · s27 새벽 세 시 택시 (금련산 밴드, 록 136, 남) · s28 바다가 보이는 원룸 (김바다, 발라드 80, 남) ·
s29 우리 동네 PC방 (레벨업, 댄스 126, 남) · s30 별 보러 가자 황령산 (기타소년, 어쿠스틱 88, 혼성) · s31 민락 회센터 (김부산, 트로트 112, 남) ·
s32 시험 끝! (학교종, 팝 132, 혼성) · s33 너의 이름 광안리 (윤바다 & 오션걸즈, 듀엣 발라드 84, D) · s34 짝사랑 일기 (봄날소녀, 발라드 78, 여) ·
s35 여름 끝 바다 (파도청년단, 록 발라드 90, 남) · s36 한 번만 더 (시티라이트, R&B 86, 여) · s37 광안리 댄스파티 (민락 크루, 댄스 128, 혼성) ·
s38 가자 부산 (사직 응원단, 응원가 120, 혼성) · s39 할매 손칼국수 (김부산, 트로트 96, 남) · s40 졸업식 (학교종, 발라드 74, 혼성) ·
s41 보름달 소원 (김부산, 트로트 102, 혼성; 추석 신곡 tag "event").
Tags: "new" for s11-s20 (신곡 tab), and the seeded 인기차트 order s01, s02, s04, s09, s05 … until real play counts exist.

### 4.19 Build order (MVP first)

1. **MVP**: Shared (Config, Songs with all 41 songs, Chart, Score, Search); server Bridge + Net + Rooms (credits, privacy,
   intruders, release, compat attrs, legacy takeover) + Queue + Mics + Scoring (tap mode) + Store (fav / recent / best / stats);
   client Legacy + RoomWatch + Prompts + Hud (bar, payment, result, cards) + Book + Remote + TV + Lyrics + Background +
   Band (generated) + Rhythm + Fx. All rewards and integrations (capped stats, Progress, Journey, Social, board, LED).
2. **Phase 2**: Voice (rig, soundproofing, voice scoring, Mic.luau, dry mute, sync), Library MR, owner `SongAudio`, per-song
   OrderedDataStore ranking, `Billing = "legacy"`, corridor muffled playback and lobby BGM.

`Billing = "legacy"` (Phase 2): leave VenueKaraoke's prompt enabled. Treat `KRenter ~= 0` (legacy-written) as the rental and
make songs free while it holds (Credits shown as "∞"). Wrap `VenueLife.fire` once, observe-style: call the original first,
except that a `kOpen` payload is rewritten to `room = 0` before the original runs, so the legacy picker never opens.
After that, open our book on that client. Never write `KRenter` in this mode.

---------------------------------------------------------------------------------------------------

Sources for 2.2: [Bloxodes stats "korean karaoke"](https://bloxodes.com/stats/games/korean-karaoke-9845995128),
[Roblox: 팡팡 노래방](https://www.roblox.com/ko/games/92758696354559/unnamed), [OP.GG Roblox: [🔥추석 이벤트] 팡팡 노래방](https://op.gg/ko/roblox/games/9845995128),
[Medal clips: 팡팡 노래방](https://medal.tv/games/roblox/experiences/1b2QgNxrlaj-y8), [나무위키 노래방(Roblox)](https://namu.wiki/w/%EB%85%B8%EB%9E%98%EB%B0%A9(Roblox)),
[Stingray Ro-Karaoke launch](https://www.nasdaq.com/articles/stingray-group-launches-ro-karaoke-roblox),
[Roblox voice chat docs (ko)](https://create.roblox.com/docs/ko-kr/chat/voice-chat).
Real-world coin-karaoke references are already summarised in `bld/pcbang_karaoke.json` ("realWorld", "interactionIdeas").
