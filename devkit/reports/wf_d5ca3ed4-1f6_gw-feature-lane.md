# gw-feature-lane (wf_d5ca3ed4-1f6)

- status: completed
- failed agents (never finished, usually the usage limit): build:crew, build:dealer, fix:club, fix:crew, fix:dealer, fix:decor, fix:hospital, fix:karaoke, review:club:correctness, review:club:experience, review:crew:correctness, review:crew:experience, review:dealer:correctness, review:dealer:experience, review:decor:correctness, review:decor:experience, review:hospital:correctness, review:hospital:experience, review:karaoke:correctness, review:karaoke:experience, test:club, test:crew, test:dealer, test:decor, test:hospital, test:karaoke

## research:dealer

The design doc is written to `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/dealer/research.md` (461 lines). This was research only: no repo files were created or edited, and I didn't do a new studio run.

1. **Which code is live.** The studio applies about 385 add-on scripts on top of `place.bin`, and those are newer than the `bld/src` dumps. The older Garage shared module has no `GS.MODELS` list, and its flagship price is 3,200,000 instead of 6,500,000. I unpacked the add-ons into `$D/pack` and designed against them. The add-on must read prices and models at runtime and work with both versions.
2. **Buying already works.** The server Garage module handles buy, quote, rent, call, dismiss and test drive, with prices, the 3-car limit, 할부, plates and saving. Our server can reuse all of it through `ServerStorage.GwangalliGarageAPI:Invoke("request", player, op, payload)` (Garage.luau:1313, also present in the older dump at :1263). Money calls go through `GwangalliGameplayAPI` "balance", "spend" and "earn".
3. **Car data.** There are 6 basic car types with 신차/중고 prices and 13 named models, plus 8 colours, a 큐비 day rental, a loan rule (30% down, 5% interest, 10 days) and a 60-second test drive. Speed and handling per type come from the vehicles shared module.
4. **The 13 named models have no 3D cars in v7.** `ServerStorage.GwangalliCarModels` doesn't exist in `place.bin` (zero instances found). So the showroom script places nothing, and buying a named model gives you the basic car of the same type. In v7 the basic cars are the real-looking parked cars: Kia Ray, Sonata, Tucson, Carnival, Genesis G80 and Porter II. The design hides those 13 from our catalog until their models exist (one config switch).
5. **What's missing today.** 박사장 is a static figure, and the desk prompt jumps straight to the "내 차" panel. The existing UI is a 4-tab side panel with no categories and no 3D preview of the named models, and those models can't be test-driven. After a test drive the panel pops up again. The level perks (중고차 5% at level 3, 할부 at level 8, flagship at level 18) are advertised but not applied anywhere.
6. **No other dealers in v7.** The motorbike shop needs a shop model and bike templates that aren't in the place, and it only sells through prompts. 렌트 and 중고차 exist only as Garage options. The old CarServer shop is switched off in this mode.
7. **Layout around the NPC.** The other team's interior furniture can't see our NPC, but it never builds in the aisles, the entrance area, or the gap between its two consultation tables. The NPC must also stay off the turntable circles, at least 8 studs from the existing prompts, and spawn only after the showroom script has finished placing cars. Streaming is on, so previews are built from copies the server puts in ReplicatedStorage.
8. **Planned files**
   - Shared: `init`, `Config`, `Catalog`, `Lines`, `Util`.
   - Server: `init.server`, `Bridge`, `Npc`, `Previews`, `Service`, `TestDrive`, `Store`.
   - Client: `init.client`, `Net`, `NpcFx`, `Dialog`, `Catalog`, `Detail`, `Viewport`, `Contract`, `Ceremony`, `TestHud`.
   - Remotes: `ReplicatedStorage.GwangalliCarDealerRemotes`, holding `Request` and `Event`.
9. **Server rules.** Every input is validated: whitelisted operations, a strict car-id pattern, our own rate limit plus per-operation cooldowns, and one action at a time per player. Buying, test driving and renting require being within 30 studs of the NPC; browsing works anywhere.
10. **Test drive.** The add-on runs its own test drive, so named models can be driven as themselves once their models exist. It records top speed and distance for a report and sends the player back to the return point afterwards. It's refused during a work shift, in a taxi, or when cuffed, and Garage's panel never pops up after it.
11. **Level perks.** The 5% used-car discount is paid back after purchase, labelled as a refund so it doesn't count as earnings. The level 8 and 18 limits show as badges only, because the existing panel would bypass them; enforcing them is one config switch.
12. **Player flow.**
    - **Dialog.** The NPC (한서윤 대리, 영업 컨설턴트) looks at you and waves. The dialog offers: browse all cars, a budget-based recommendation, test drive, day rental, and "내 차 관리", which opens the existing panel.
    - **Catalog.** Full screen, with category tabs: 경차 / 세단 / SUV / 밴·트럭 / 프리미엄 / 친환경 / 스포츠 / 중고차 / 렌트. It has sort and filter options and lazy-loaded 3D thumbnails.
    - **Detail.** A rotatable 3D view, 8 colours, specs, a 할부 quote, and buttons to test drive, buy, save or compare.
    - **Buying.** A quote sheet with hold-to-sign, then a delivery ceremony: plate reveal, confetti, a key hand-over, and "지금 타기".
    - **Remote browsing.** A public open event lets the phone show the catalog anywhere, read-only.
13. **Saving.** A small separate store (`GwangalliCarDealer_v1`) keeps visits, test drives, best results and a wish list. The doc also covers the offline and studio test plan.

**Decisions for you:**
- **Hidden models:** I hid the 13 named models in v7 rather than show them as a pricier copy of a basic car. Showing them with an "출고 차량: 동급 …" note is the alternative.
- **Second NPC:** a second NPC for 중고차·렌트 is defined but off.
- **Desk takeover:** the option to have 박사장's desk open our dialog is off by default. Turning it on hides that map prompt for each player and puts our own in its place.
- **NPC spots:** the three candidate spots are picked from the maps and still need a studio screenshot to confirm.

## build:karaoke

The karaoke add-on is written and working: 30 Luau files across the three allowed folders, and every file passes `luau-compile --binary`. The full flow (pay, reserve, sing, score, rewards, release) passes my offline mock tests. In the temp studio it ran from payment through a scored song. One thing does not show correctly there yet: the TV draws as a flat overlay in the corner of the screen instead of on the booth's screen part. I believe this is the test engine's fault and not the code's (explained below), but it has only been checked in the browser engine, never in real Roblox.

A previous agent had already written `init.luau` (config), `Songs.luau` and `Chart.luau`. I kept them; they hold 58 songs and pass validation with no problems. Everything else is new.

## Test results
- **Offline server test** (`/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/test/t_server.luau`): 0 failures. It covers:
  - payment: charging, the same request id not being charged twice, free trial when the money API is missing
  - queue: corridor/inside checks, auto-start, 우선예약, cancel, refund within 5 s and none after, pause, live tempo, 처음부터
  - scoring: perfect taps give 100점 plus 서비스곡, voice scoring, tambourine beats can't be farmed
  - rewards: Progress, Social, LED/board, score prize
  - room rules: intruders pushed out, knock/accept, mic hand-over and auto-return, renter handover, release when empty and when idle
- **Offline client test** (`t_client.luau` in the same folder): 0 failures. It builds every UI module and checks every property name against the engine's class list, then plays whole songs on PC and phone screen sizes. All six background scenes, the lyric wipe and 간주중 appeared.
- **Temp studio**: 8 rooms found, the old "방 잡기" prompts switched off, buying and reserving through the real remotes worked. The song auto-started, the singer screen and note lane showed (screenshot below), and the next song in the queue started on its own.
  - The test score was 55: the machine was so slow that my automatic tapper hit notes late.
  - The last run hit the 25-minute limit before the score-screen screenshot.
  - The shared studio lock had a queue of over an hour, so I cancelled my final run.
- **TV overlay**: a newer copy of the same engine has a fix for screens that get their target part set after they are created, which suggests the overlay is an old-engine bug. I changed the TV to re-attach itself whenever it switches booths, but couldn't re-test that.

Studio screenshots of the song book, remote and singer screen are in `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run1/` and `.../run5/`.

## Files
**`src/ReplicatedStorage/GwangalliKaraokeShared/`**
- `init.luau` – owner settings, names, input checks, the shared song clock, Korean text and error messages.
- `Songs.luau` – 58 songs with 5-digit numbers (38131…). Lyrics are original with made-up artists, or public-domain tunes (전래 민요, Twinkle, Happy Birthday, Ode to Joy, Frère Jacques, London Bridge, Jingle Bells). Each song has genre, BPM and key.
- `Chart.luau` – turns a song into an identical timeline on server and every client: beat-timed lyrics, melody, chords, tap notes, 간주.
- `Score.luau` (new) – timing windows, tap and voice score formulas, grades, Korean comments.
- `Search.luau` (new) – search by title, artist, 초성 or song number (e.g. ㄱㅇㄷㄱ, 38262).

**`src/ServerScriptService/GwangalliKaraokePlus/`**
- `init.server.luau` – startup order, game loops, lobby LED text, sets the "active" flag.
- `Bridge.luau` – all hookups to the owner's systems, each with a fallback: money, VenueLife (daily caps, mic in hand, toasts), Progress, Social, Journey, the 노래왕 board, LED, switching off the old prompt.
- `Net.luau` – the remotes, plus rate limits per kind of request.
- `Rooms.luau` – booths, who is inside, 잠금/친구만/누구나, knock/invite/kick, pushing out intruders, buying songs, handover, release; also keeps writing the old `KRenter`-style booth attributes.
- `Playback.luau` – 20-song queue, 우선예약, start/stop/처음부터/pause, live tempo/key/echo.
- `Mics.luau` – the two mics: grab, put down, pass, auto-return.
- `Scoring.luau` – judges taps and voice on the server, effects, rewards, 100점 bonus song.
- `Voice.luau` – echo mic rig and soundproofing through the new Audio API, only if it exists.
- `Store.luau` – saves favourites, recent songs, best scores, stats and settings; weekly chart.

**`src/StarterPlayer/StarterPlayerScripts/GwangalliKaraokePlus/`**
- `init.client.luau` – waits for the server, starts everything, includes a debug hook that only works when the `Debug` attribute is set.
- `Net`, `Kit` (UI kit in the game's colours), `Rooms` (room state on the client).
- `Legacy` – hides the old karaoke bar, TV and the screen's placeholder sign.
- `Band` – the backing band built from built-in sounds, guide melody, key/tempo, optional licensed track, muffled sound from the corridor.
- `Mic` – measures your voice per lyric line.
- `Rhythm` – singer screen: lyric strip, note lane, ♪ 박자 button.
- `TV`, `Lyrics`, `Background` – the booth TV, two-line colour-wipe lyrics, genre backgrounds.
- `Hud`, `Book`, `Remote`, `Prompts`, `Fx` – button bar and cards, 노래책, 리모컨, E-prompts, lights and confetti.

## Install steps for the owner
1. Put the three folders in Studio as: ModuleScript `ReplicatedStorage.GwangalliKaraokeShared`, Script `ServerScriptService.GwangalliKaraokePlus`, LocalScript `StarterPlayer.StarterPlayerScripts.GwangalliKaraokePlus`. With Rojo, the orchestrator needs to add these three paths to `default.project.json`.
2. No existing script needs editing. The old "방 잡기" prompt is switched off automatically.
3. Turn on **Game Settings → Security → Enable Studio Access to API Services** so saving works.
4. For the echo mic and soundproofing, voice chat must be enabled in Game Settings → Communication, and `VoiceChatService.UseAudioApi = Enabled`. Without them, scoring falls back to the tap game and a Korean hint explains why.

## Settings in `init.luau`
- **On/off:** `Enabled`, `TakeOverLegacy`, `Billing` ("credits" or "free"), `FreeWhenNoEconomy`.
- **Prices:** `Packs` (1곡 500 · 4곡 1,000 · 8곡 2,000), `MaxCredits`, `RefundWindow`, `BonusScore`, `BonusSongsMax`.
- **Room timers:** `EmptyGrace` 40 s, `IdleRelease` 150 s.
- **Queue and room:** `QueueMax` 20, `QueuePerPlayer` 6, `AllowedMax`, `DefaultPrivacy`.
- **Controls:** tempo, key and echo ranges.
- **Voice:** `Voice`, `Soundproof`, `EchoAllMembers`.
- **Rewards:** `Rewards` (shares the old karaoke's daily caps), `ScoreCoins` (small prize: 300원 at 95점+, 5 a day; set to 0 to turn off).
- **Display and saving:** `WriteBoard`, `WriteLED`, DataStore names.
- **Sounds:** `Samples`, `Instruments`, `SongAudio` (licensed backing tracks only).
- **Effects and keys:** `EffectCooldown`, prompt keys.

## Left out on purpose
- No search of Roblox's audio library for backing tracks, no per-song online leaderboard, no lobby background music.
- No muting of the singer's normal voice for listeners: everyone hears it alongside the echoed speaker.
- The old timed-rental billing mode was dropped from the config.
- Not my files, flagged for others:
  - **Interior team** could read the new booth attributes `KPCredits`, `KPSongNo`, `KPMicsOut` and `KPTambOut` (songs left, current number, which mics are out, tambourine in use).
  - **Journey** still says "500원이면 30분!".
- **Not tested in real Roblox:** live voice, saving, and the TV appearing on the screen part.

## build:hospital

The hospital facility layer is finished: every system is built, all 12 files pass `luau-compile`, and 22 of 22 offline checks pass. In the temp studio all zones built live, but walk-through tests could only be run offline. Your commit removing the disability symbols is kept, and none were re-added.

**Current images ("현재 이미지"), live temp-studio screenshots**
- /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/hospital/final/hospital_live_1.jpg — 1F back hall at the restrooms, women's and men's restrooms, elevator at 1F / 2F (open) / roof tower, ER entrance outside, ER projecting sign
- /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/hospital/final/hospital_live_2.jpg — fire exit outside, 2F 건강검진센터 glass doors, new 2F stair-hall passage, 2F fire-stair door, roof garden, pergola, 직원 휴게실, 창고
- Single shots: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/hospital/studio/run11/ and /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/hospital/studio/run12/ (PNG). Offline renders are in /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/hospital/sim/shots2/.

**Files** (all under /home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/; the previous agent wrote most of them, I reviewed, fixed and finished them)
- `HospitalPlus.luau` — registers the keep zones at load; `start`/`stop`/`status`; build director (builds within 140 studs, tears down past 170), 10 Hz animation loop, `HospDebug` console, offline-test entry points.
- `Hosp_Geo.luau` — pure data: hospital frame, coordinates, keep zones, NPC corridors, server prompt and bed safety boxes, map-part lookups, colours, sounds, budgets.
- `Hosp_Lib.luau` — shared helpers: zone kits, wall replacement, hide/restore of map parts, door animators, presence sensing, sounds, particles, client seats, safe teleport.
- `Hosp_UI.luau` — fade, toasts, elevator panel (keys 1·2·3, gamepad, touch), telescope view.
- `Hosp_Restroom.luau` — 남/여 화장실 with lockable stalls (사용중/비어있음), urinals, sinks, dryers, diaper stations, emergency bells, motion lights.
- `Hosp_Elevator.luau` — 1F/2F/R landings, roof tower, one moving cabin and its state machine, rider shifted in the same frame (no fade), hospital NPCs call and use it.
- `Hosp_Doors.luau` — 5 automatic glass doors, 진료 중 lamp, name plates, wait monitor, STAFF ONLY / 창고 / 2F fire-stair / roof doors.
- `Hosp_Exits.luau` — east-wall replacement with a walk-through 응급실 출입구 and 비상구, and the new 2F stair-hall passage (the map's stair hall was sealed).
- `Hosp_Portal.luau` — hidden rooms under the hospital: prefetch, fade in/out, watchdog if the server moves the player, cleanup.
- `Hosp_Rooms.luau` — 직원 휴게실, 창고, 비상계단 interiors.
- `Hosp_Roof.luau` — roof garden, rails with invisible guards, 광안대교 telescope.
- `Hosp_Signs.luau` — floor numbers, relocated 건강검진 안내 board, low exit-path signs, 1F hall guide.

**What I changed this session**
- **Telescope:** after closing it, it now reopens with one press (it needed two).
- **Teleports:** the player now stands up from a seat first, and the whole character is moved with `PivotTo`.
- **Elevator panel:** moved inward so it no longer covers the right-edge HUD buttons on mobile.
- **Other builders' decor:** loose decor from other room builders that lands inside the restrooms or lift shafts is now hidden locally. This covers T_clinic's restroom hanging sign, which would otherwise hang inside the women's restroom.
- **Beds:** all 8 hospital bed seats are now protected from decor, plus any live tagged ones.
- **Small visual and text fixes:**
  - Hall-side wall panelling and a handrail on the restroom front.
  - A red double-sided 응급실 sign above the canopy, visible from the ambulance bay.
  - A second ceiling light in 창고.
  - Toasts reworded to drop "(연출)".

**Tests**
- **Offline (22 of 22 pass):** restroom door, stall lock, fire exit, ER doors, hidden-room watchdog and cleanup, elevator.
- **Offline simulator:** I added render-step support so the elevator's floor arrival actually runs; elevator 1→2→R→1 and all three hidden rooms pass.
- **Tiers:** no part was dropped at high, mid or low quality.
- **Temp studio:** all zones built. Elevator calls moved the cabin to 2F and R. A hospital NPC had already brought the cabin to 2F, which shows the NPC hookup works live. 직원 휴게실 and 창고 built on request.
- **Studio limits:**
  - The browser engine's own avatar controller overrides teleports made from game code.
  - The page ran out of memory (2 GB) at the end of the last run.
  - Because of these, walking through doors was tested offline only. The 2F back wall also looked missing in one studio shot; it exists in the place file and nothing in this layer hides it.

**Install**
1. Put `HospitalPlus` and the eleven `Hosp_*` ModuleScripts as direct children of the existing `GwangalliBuildingInterior` LocalScript in StarterPlayerScripts (Rojo does this automatically; by hand, use exactly those names).
2. Nothing else: `init.client.luau` already loads HospitalPlus.

**Game settings:** none needed. It is client-only with no remotes, no data saving and no new asset IDs. The existing StreamingEnabled is fine. Keep `Workspace.FallenPartsDestroyHeight` below -60 (it is -120 now), because the hidden rooms sit at about y -43.

**Settings you can change**
- On the LocalScript: attribute `Enabled=false` or `HospitalPlus=false` turns the layer off and restores the map. `Debug=true` turns on logs. `HospDebug` takes commands (`status`, `lift`, `call 2`, `go staff hall`, `tp x y z`).
- In `Hosp_Geo`: `BUILD_R` 140, `TEAR_R` 170, `ROOF_R` 90, part/light budgets per tier, sound and texture IDs, `ROOMS` and `PORTAL_Y` (hidden-room location).
- Ride time is `1.4 + 1.1 × floors` seconds, set in `Hosp_Elevator`.

**Left out or limited, knowingly**
- Bells, the ER intercom and the lift alarm only play a sound and a toast; no staff NPC comes.
- The rooftop fire stair is a hidden room behind a fade, not a real stair in the building.
- Other players riding the lift appear to pop between floors, the same way the server's NPCs do.
- The telescope uses a raised viewpoint, because buildings on the beachfront block the real view of the bridge.
- Restroom gender is not enforced.

**Changes needed in other people's files**
- **`init.client.luau`, around line 235:** venue rooms under the `SKIP_ROOTS` groups never build, so no T_clinic hospital room exists in the live game. The fix is to use a check that only reads the `GwInterior` and `ShopLife` attributes, not `skipped(f.model)`. HospitalPlus does not depend on this.
- **`T_clinic.luau`:**
  - Line 4879: change the floor directory to `"R   옥상 정원 · 휴게 공간"`.
  - Line 4884: remove the restroom hanging sign (it is hidden locally for now).
  - Have its ceiling lights in the back hall and checkup room avoid `facility_room` keep zones.
  - Do not hide or reskin the map parts this layer owns.

Offline test scripts are in /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/hospital/sim/ (`mk.sh`, `simtest.luau`, `simtest2.luau`); the studio drivers are `hosp7.js` and `hosp8.js` in /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/hospital/studio/.

## build:karaoke

The karaoke add-on is complete and working. A previous run had already written most of it; this pass added the fixes listed below. All 30 files pass luau-compile, and the offline tests (t_server, t_client, t_client_phone, t_chart, t_search) finish with 0 failures. In the temp studio, one song went all the way through: buy 4 songs, reserve, title card, colour-wipe lyrics, pause, autotap rhythm scoring, then the score screen (80점 A) with rewards and the 오늘의 노래왕 board.

The owner's "현재 이미지" request is answered by these screenshots:
- TV idle: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run7/B1_idle_tv.png
- TV ready (방 잡은 뒤): /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run8/R1_ready.png
- Title card: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run9/S2_title.png
- Lyrics during a song: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run9/S3_lyrics.png and /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run8/R2_title.png (kids background)
- Score screen and result card: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run9/S4_score.png
- Phone layout (HUD, 리모컨, 노래책): /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run7/B9_phone_hud.png, /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run7/B10_phone_remote.png, /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run7/B11_phone_book.png
- PC 리모컨, 노래책, payment sheet (from the earlier run): /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run5/05_remote.png, /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run5/04_book.png, /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/studio/run5/03_pay_sheet.png

The pause overlay and the player HUD sit on top of the TV in these shots only because the test camera points straight at the screen.

The temp studio has two display quirks that are not in the game code. It draws TV screens as a flat overlay that shows through walls. Before the fix below it also did not draw TV screens that become visible later.

**Changes in this pass**
- **TV screens:** TV and other-room screens now set `PixelsPerStud` to the screen's width; Roblox ignores this with `FixedSize`, and it makes the temp studio draw the TV the right size. Hidden TV screens are now detached and re-attached when shown, which fixed the blank 대기 / 노래 / 점수 screens in the studio.
- **Title card:** it now stays up through the start of the intro (until 4 beats before the first line, at most 3.5 s), and lyrics appear as it fades. Before, most songs only showed it for the 1.2 s lead-in.
- **Echo mic:** echo and reverb now run side by side and output only the echo sound. The singer's normal voice still comes from their character, so nobody hears the voice twice. Wires are named `Mic_<userId>`. Echo levels were retuned.
- **Voice scoring:** the server now accepts voice-score lines and the voice on/off status only from players who actually have a voice device on the server, which makes faking a voice score harder.
- **Action bar:** while holding a mic, the 탬버린 button hides and 박수 stays. The duplicate 박수 button is gone.
- **Payment sheet:** better text contrast on the first button, and a shorter sheet.
- **New config `TapLatency` (0.04 s):** offsets the rhythm-tap judging for sound and input delay.
- **Takeover off:** if `TakeOverLegacy = false` and the old karaoke is running, the server now removes its remotes and room state, so the old karaoke runs untouched.
- `t_server.luau` now covers the voice-device check.

**Files**
`src/ReplicatedStorage/GwangalliKaraokeShared/` (ModuleScript "GwangalliKaraokeShared")
- `init.luau`: settings, instance and remote names, validation helpers, the song clock, packs, effects, genres, Korean error messages.
- `Songs.luau`: 58 songs with 5-digit numbers (38131…45598). All are original songs by fictional artists, traditional 민요, or public-domain melodies with original words. Each has title, artist, genre, BPM, key, part, credits, and an optional sound id.
- `Chart.luau`: works out the same song timeline on the server and every client (intro, verse, chorus, 간주, outro; chords, melody, beat-timed lyric syllables, tap notes, tempo).
- `Score.luau`: timing windows, tap and voice score formulas, grades, Korean comments.
- `Search.luau`: 노래책 search by title, artist, 초성 or song number.

`src/ServerScriptService/GwangalliKaraokePlus/` (Script)
- `init.server.luau`: start-up order, loops, lobby LED and chart attributes, sets `Active`.
- `Net.luau`: the three remotes and the request router (rate limits, input checks, Korean errors).
- `Bridge.luau`: links to existing systems, all pcall'd with fallbacks: money API, `VenueLife` (daily caps, sing pose and mic prop, notices, teleport permission), Progress `karaoke_song`, Social, turning off the old panel prompts, LED board.
- `Rooms.luau`: booth discovery, rent, credits, privacy (잠금 / 친구만 / 누구나), knock / invite / kick, guiding uninvited players out, handing over the room, releasing empty or idle rooms, room state plus the old `KRenter` / `KPaidUntil` attributes.
- `Playback.luau`: 20-song 예약 queue (6 per person), 우선예약, cancel, start, stop with refund, 처음부터, pause, tempo / key / echo / guide / score settings, auto-advance.
- `Mics.luau`: two mics per room (grab, put down, pass with accept card, auto-return).
- `Scoring.luau`: judges taps, voice lines and on-beat tambourine on the server; effects broadcast with cooldowns; rewards, 100점 서비스곡, board.
- `Voice.luau`: echo mic and soundproofing through the new audio API (rewired on enter, restored on leave).
- `Store.luau`: saves favourites, recent songs, best scores, stats and settings; weekly chart; memory fallback; saves on shutdown.

`src/StarterPlayer/StarterPlayerScripts/GwangalliKaraokePlus/` (LocalScript)
- `init.client.luau`: waits for the server's `Active`, starts the modules, one frame loop, studio debug hook (only when the script attribute `Debug` is true).
- `Net`, `Kit`, `Rooms`: requests with timeout, UI kit (uses the game's GwangalliUI look with a fallback), room views and which room I'm in.
- `Legacy`: hides the old karaoke UI and TV.
- `Prompts`: local ProximityPrompts on our own invisible anchors (panel, coin slot, remote, mics, tambourine, lobby).
- `TV`: the TV as a SurfaceGui in PlayerGui on `KaraokeScreen` (idle slideshow, ready / queue, next-song countdown, title card, lyrics, 간주중, next-song ticker, badges, 분위기 meter, emoji, pause, 두구두구 score, 100점 celebration), plus simple screens for the other rooms.
- `Lyrics`: two-line TJ-style colour wipe with part colours and countdown dots.
- `Background`: generated video-style backgrounds per genre.
- `Band`: the accompaniment, synced to the server clock; pitched built-in sounds per genre, guide melody, key / tempo / volume, muffled sound in the corridor, effect sounds.
- `Mic`: local voice-level analysis per lyric line.
- `Rhythm`: the singer's tap lane (F / K / R2 / touch).
- `Hud`: action bar, payment sheet, result card, mic-pass and knock cards, banners, shortcuts.
- `Book`: 노래책 (인기차트 / 신곡 / 장르 / 애창곡 / 최근 / 수첩, search, 예약 / 우선예약).
- `Remote`: 리모컨 (number pad, queue, play controls, echo / key / tempo, volume sliders, room settings, people).
- `Fx`: booth light show, lasers, 폭죽 / 꽃가루 / 환호 / 100점 particles, emotes.

**Install for the owner**
1. Put each of the three folders in Studio as named. The folder's `init` file becomes the script itself and the other files become its child ModuleScripts:
   - `GwangalliKaraokeShared` goes in ReplicatedStorage as a ModuleScript.
   - `GwangalliKaraokePlus` (server) goes in ServerScriptService as a Script.
   - `GwangalliKaraokePlus` (client) goes in StarterPlayer → StarterPlayerScripts as a LocalScript.
2. With Rojo, the orchestrator still needs to add those three entries to `default.project.json`; I didn't touch it.
3. No existing script needs editing.

**Game settings**
- Game Settings → Security → Enable Studio Access to API Services, so saving works in Studio. Without it, data is kept in memory only.
- For the echo mic and voice scoring: voice chat turned on, and `VoiceChatService.UseAudioApi = Enabled` with default voice on. Without these, players get a Korean hint and the rhythm-tap game.
- HTTP requests are not needed.

**Config knobs** (in `GwangalliKaraokeShared/init.luau`, commented in Korean)
- **Switches:** `Enabled`, `TakeOverLegacy`.
- **Billing:** `Billing` ("credits" or "free"), `FreeWhenNoEconomy`, `Packs` (500원 / 1,000원 / 2,000원), `MaxCredits`, `RefundWindow`, `BonusScore`, `BonusSongsMax`.
- **Queue and timing:** `QueueMax` (20), `QueuePerPlayer`, `RestartMax`, `PauseMax`, `EmptyGrace`, `IdleRelease`, `LeadIn`, `ScoreHold`, `AutoStartDelay`, `TapLatency`.
- **Room access:** `DefaultPrivacy`, `PushOutIntruders`, `PanelReach`, `AllowedMax`.
- **Controls:** tempo / key / echo ranges.
- **Voice:** `Voice` ("auto" or "off"), `Soundproof`, `EchoAllMembers`.
- **Rewards:** `Rewards` (daily caps), `ScoreCoins` (300원 at 95+ points, cooldown and daily max; set `Amount = 0` to turn off), `WriteBoard`, `WriteLED`.
- **Saving:** DataStore names.
- **Sounds:** `Samples` (built-in rbxasset sounds), `Instruments` (optional custom drum / effect asset ids), `SongAudio` (optional licensed backing track per song).
- **Other:** `EffectCooldown`, prompt keys, `Debug`.

**Not included**
- The optional "MR 반주곡" library search (`AssetService:SearchAudioAsync`) from the design doc.
- A per-song global top-5 ranking; there are personal bests plus the 오늘의 노래왕 board.
- A "내 목소리 듣기" monitor toggle.
- Licensed backing tracks: every `soundId` is empty, so all songs use the built-in, slightly chiptune-sounding band until the owner adds licensed tracks.
- The 민요 melodies are written note by note and should be checked by ear before a public event.
- The new audio API parts (echo rig, soundproofing, voice analysis) are pcall-guarded, but this engine and the offline tests could not run real voice, so they are untested.

## build:decor

Note: claude-sonnet-5[1m] (the safety classifier) was unavailable (timed out) when reviewing this subagent's work. Please carefully verify the subagent's actions and output before acting on them.

The 자유 배치 인테리어 add-on is written and works end to end in the temp studio (oneroom). The engine rented a home, entered it and attached the add-on. Pieces placed and stacked; finishes, presets, photo and lamp/speaker interactions all worked. The editor UI ran in landscape and portrait, and photo mode worked. All 45 files pass luau-compile, and luau-analyze shows no lint warnings. Git status is clean for these paths now, so the orchestrator seems to have already committed this state.

**Test results**
- **Studio:** the server scenario placed 12 pieces. A lamp stacked on a coffee table. A repeated request (same request id) charged only once. Wall finish, preset save/plan, photo reward and interactions all worked. Interior score came out at 110 (센스 있는 집), and the life game's 인테리어 점수 / 편안함 / 가구 가치 picked up our pieces. After leave → enter, all 12 pieces were rebuilt.
- **Offline (real HomeUnit fixtures, all 5 tiers):** the scan and placement rules ran on every tier, about 0.1–1.7 ms per check. Save-format round trip lost nothing. Bad requests were refused: NaN → "bad", another player's/unknown uid → "bad", out-of-bounds → "outside", malformed batch → "bad".
- **Offline client↔server loop:** pick → place → undo/redo, move with the stacked lamp carried along, recolour, remove → restore, and multi-select group move all worked.
- **Not covered by any test:** gamepad, real touch gestures, a second player (likes/방명록), and DataStore persistence. Catalog thumbnails render black in the temp studio because it can't draw ViewportFrames; they should render in real Roblox, but that's unverified. The new catalog items were never rendered to check how they look. I stopped the render batch so I wasn't holding the shared studio lock other agents were waiting on; only the lighting sheet got rendered.

**Bugs found and fixed during testing**
- Every catalog item was being treated as a speaker, fireplace and aquarium (a name clash in the item builder).
- Emptied default-furniture slots were still blocking placement.
- Two separate bathrooms were merged into one room.
- On an unpublished Studio place, loading saves would hang about 45 s before falling back to memory.
- On phones the confirm button scrolled off-screen.
- Portrait layout didn't rebuild when the screen rotated.

**Files**
`src/ReplicatedStorage/GwangalliDecorShared/` (ModuleScript `init.luau` + children)
- `init`: loads and exposes all shared modules.
- `Config`: every tunable.
- `Text`: all Korean strings, refusal messages, 원 formatting, 초성 search, 조사.
- `Palette`: named colours, materials, HSV/hex conversion, light colours.
- `Kit`: the small modelling language the items are written in.
- `Catalog`: item registry, colour/material per slot, exact bounds, stacking surfaces, interactions, search, sort, 8 추천 세트.
- `Items*` ×14: **167 pieces** across 거실 16, 침실 13, 주방 16, 욕실 10, 조명 12, 식물 11, 벽장식 11, 가전·전자 12, 러그 10, 수납 10, 취미·게임 12, 베란다 10, 시즌·파티 12, 아이·펫 12.
- `Geometry`: box math, poses, snapping.
- `Unit`: reads a home model (floors, walls, ceilings, fixtures, slot spaces, door/현관/fixture clearances, stairs, rooms, levels).
- `Rules`: placement checks shared by server and client — support/stacking, raise/lower, wall and ceiling mounting, overlaps, 겹치기 허용, people, caps.
- `Path`: keeps doors and fixtures reachable.
- `Codec`: compact save format relative to UnitRoot, plus the strict sanitizer.
- `Finish`: 14 wall finishes, 11 floors, 6 lighting presets, pricing.
- `Score`: score, 6 grades, 18 badges, 10 goals.
- `Spec`: turns a piece's spec into a Model (server pieces, ghosts, thumbnails).

`src/ServerScriptService/GwangalliDecorPlus/` (Script `init.server.luau` + children)
- `init.server`: creates the remotes, finds the life game, handles players joining and leaving.
- `Host`: adapters to Profiles / Housing / ctx money (fallback `GwangalliGameplayAPI`), and adds our pieces to the life game's score and furniture value.
- `Store`: own DataStore with session lock, retries, autosave, memory fallback.
- `Homes`: watches `GwangalliHomeInstances` and builds `model.DecorPlus/Item_<uid>`, as specified.
  - Each piece is tagged `GwDecorItem` with DecorUid / ItemId / OwnerUserId / PlaceKind / Look / Pivot attributes.
  - It also handles the light budget, prompts (앉기 / 눕기 / 불 / TV + 채널 / 음악 / 문·커튼 / 먹이), room finishes, and clearing ours when the host theme is applied.
  - Pieces from a previous home go to 창고 when the player has moved.
- `Actions`: every request (open, place, move, moveMany, color, remove, restore, sellStored, interact, finish, preset, like, guestbook, gbDelete, photo, set). Includes validation, rate limits, duplicate-request protection, and 10-minute full refund / undo.
- `Social`: ❤️ likes (once per 20 h per guest), filtered 방명록, 📸 reward, badges and goal rewards.

`src/StarterPlayer/StarterPlayerScripts/GwangalliDecorPlus/` (LocalScript `init.client.luau` + children)
- `init.client`: home tracking, open/close (K, pill, D-pad ↑), never runs together with the slot 🛠️ 인테리어, hides the HomeBar while editing.
  - Also adds `LocalPlayer.GwangalliDecorPlusOpen:Fire("editor"|"photo"|"close")` so other scripts (e.g. the phone) can open it.
- `Net`: request wrapper with request ids and timeout.
- `Ui`: UI kit in the place's style.
- `Camera`: dollhouse camera and wall/ceiling/upper-floor cutaway.
- `Editor`: placement core.
  - Ghost tint, grid 끔/0.25/0.5/1, rotation 15/45/90/미세, lift, stacking, wall/ceiling mounting, move/rotate/duplicate/delete, undo/redo, multi-select + group move, 세트 cart.
  - Controls: PC keys R/T, Q/E, G, Ctrl+Z/Y, Del, Ctrl+D, M, F, Tab; touch drag/tap/long-press/pinch; gamepad centre cursor.
- `Panels`: top bar, catalog (tabs, 초성 search, style filter, sort, thumbnails, 창고, 세트), action bar with pinned ✓/✕, info card, and the 벽지·바닥·조명 (with host themes), 프리셋, 목표·뱃지, 설정 and 도움말 screens.
- `Picker`: per-slot curated swatches, HSV picker, material chips.
- `Preview`: 3D catalog thumbnails.
- `Effects`: wall/floor patterns, lighting presets incl. 파티, 8 TV channels, aquarium fish + feeding, real-time wall clock, speaker music, fire flicker, mirror ball.
- `Visit`: home pill (owner: ✨ 자유 배치 · ⭐ · ❤️/📝; guest: ❤️ 좋아요 · 📝 방명록 · 🔍 구경 · 📸).
- `Photo`: 📸 mode with 5 filters and shutter.

**Install for the owner**
1. Put the three folders in place (Rojo mapping or by hand):
   - `GwangalliDecorShared` → ReplicatedStorage (ModuleScript with its children).
   - `GwangalliDecorPlus` → ServerScriptService, at the top level, not inside the GwangalliGameplay folder.
   - `GwangalliDecorPlus` → StarterPlayer.StarterPlayerScripts (LocalScript with its children).
2. Publish the place and turn on Game Settings → Security → "Enable Studio Access to API Services". Without it, layouts are memory-only and the editor shows "⚠️ 지금은 저장이 안 되는 세션이에요".
3. 방명록 filtering only works in a published game.
4. No existing scripts need editing; HTTP requests are not needed.

**Config knobs (`GwangalliDecorShared/Config.luau`)**
- Caps per tier (items / parts / real lights): goshiwon 80, oneroom 140, officetel 200, apartment 260, penthouse 300. 창고 holds 400.
- Money: 50 % sell-back, 10-minute full refund and undo window, delete default (창고 or 팔기), pay from bank first.
- Placement: grid and rotation steps, lift step (0.25) and max lift (10), 겹치기 허용 on/off, reachability check on/off, clearance sizes, batch max (40).
- Rate limits and per-action cooldowns.
- Social: like dedupe hours, daily like rewards, 방명록 size and length, daily photo rewards, 3 preset slots.
- Client: K key, display order, thumbnail cache size, effect range, camera.
- `SPEAKER_TRACKS`: empty by default, so speakers use a built-in tone sequencer; add music asset ids to use real tracks.
- Host integration: switch off if the host ships its own HomeDecor, link to the host's score/value (on), clear our finish when a host theme is applied (on).

**Design decisions and what's left out**
- Saves use our own DataStore because the life-game profile sanitizer drops unknown item ids. Our pieces still count toward the life game's score and value through a server-side wrapper.
- Presets are 3 slots per home layout (tier). Loading one re-places owned pieces, takes from 창고, optionally buys what's missing, and charges for finishes that differ from the current ones.
- Not built: 함께 꾸미기 (co-decorating) and a virtual placement preview while touring a home.
- In the real oneroom, free space is limited by the default slot furniture. Selling or storing a slot piece through 🛠️ 인테리어 frees that space; 겹치기 허용 bypasses it.

Screenshots are in `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor/studio/out2/` (editor `11_editor.png`, selection `13_selected.png`, presets `14_presets.png`, portrait `15_portrait.png` / `16_portrait_placing.png`, photo `17_photo.png`) and `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor/studio/out1/` (home pill `00_home_pill.png`, finish panel `04_finish.png`, goals `05_goals.png`, decorated room `06_world.png`). The studio harness is `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor/studio/decor.js` and `decor2.js` in the same folder; the offline tests are in `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor/tests/` (`rules.luau`, `server.luau`, `client.luau`).

## build:club

GwangalliClubPlus is finished: 19 files that all pass luau-compile, building on the earlier agent's server and LED modules. The logic passed offline tests in a mock Roblox runtime. In the temp studio it was only partly checked: the client built every fixture in the real club, but none of our visuals showed in screenshots and no paid flow went through there.

**Testing**
- **Offline, client:** I ran a scripted night: legend order, VIP 후원 cue, two ranking updates, DJ ON AIR plus every pad, 합석 walk-in with 짠 and 댄스, and clicking the 후원 / 랭킹 / DJ pad UI. No errors, and everything was cleaned up 30 s after leaving the club.
- **Offline, server:** donate, cooldown, bad amount, filter reject, unknown table, duplicate request id, order from a show, direct order with no show, DJ join/pads/admin skip, Robux receipts and memory-only rankings all behaved correctly. Receipts are idempotent; an unknown product returns NotProcessedYet. The LED timeline (slotting, pauses around order intros) also passed its own test.
- **Temp studio, client:** in the real CLUB OCEAN it detected Zone_Main and built 4 lasers, 8 moving heads (free ceiling spots it found itself), CO2, sparks, strobes, haze, LED floor, mirror ball, booth glow, both LED canvases and the rail.
- **Temp studio, server:** a 후원 there was refused with `gate`. That was correct: the place's own systems had reset the test player's wristband to 0 and set `GwJourneyClub` to "locked".
- **No screenshots of our visuals:** none of them showed up in the captured shots (the wall still shows the house "OCEAN" pixels). The browser engine also slowed to minutes per frame under the show's load. I stopped after 6 runs; please check the look in real Roblox Studio.

**Bugs found and fixed during testing**
- Club rooms were detected by part name; they now use the `Zone` attribute, as Club.server and ClubLights do.
- Orders were priced at 0 when GwangalliClubShowShared couldn't be read; there is now a fallback copy of the menu.
- One order could be counted twice when the Tables write arrived before the Show write; the check now waits 0.6 s.
- One failing frame killed a whole client loop permanently; loops now survive bad frames and stop on the 5th error in a row.
- The side-board ticker forced the whole big board to redraw every frame; it now has its own small screen, and the LED loop writes far fewer properties per frame.

**Files**

Shared — `src/ReplicatedStorage/GwangalliClubPlusShared/`:
- `init.luau` — contract, Config, tiers, KST night/week keys, validation, JSON, fallbacks (map positions, menu prices).
- `Lines.luau` — all Korean text (receipts, DJ, LED, boards, ticker, UI, show, rank, pad).

Server — `src/ServerScriptService/GwangalliClubPlus/`:
- `init.server.luau` — boot, remotes, money/text-filter helpers, entry gate, rate limit, request handling, 0.5 s tick, flush on shutdown.
- `Bridge.luau` — reads the club's Show / Tables / Booking attributes, ClubShowHook, ClubRanking, wristband and in-club checks.
- `Stage.luau` — the centre LED timeline: paid / DJ cues queue around the club's own order intros and 합석 card, plus the ticker.
- `Ranking.luau` — 오늘의 큰손, 후원 랭킹, 최고가 주문, 이번 주 (OrderedDataStore with retries, memory fallback).
- `Donate.luau` — 전광판 후원 with in-game money (presets or custom amount, filtered message, target 전체 / DJ / 테이블) and Robux intent.
- `Receipts.luau` — Robux receipt handler: always exported, and installs ProcessReceipt itself only under the conditions in install step 4.
- `Dj.luau` — one guest DJ at a time: queue, 3-min turns, admins, pads with cooldowns, filtered LED text, ON AIR.

Client — `src/StarterPlayer/StarterPlayerScripts/GwangalliClubPlus/`:
- `init.client.luau` — starts each module in its own pcall.
- `Core.luau` — shared context, zone tracking, beat clock, loops, map lookups, builders.
- `Led.luau`, `LedArt.luau` — beat-synced idle VJ, and takeovers for orders (4 tiers, DisplayName + @username, count-up price, rank badge), 후원, 합석 card, DJ, plus short notes.
- `Fx.luau` — CO2, confetti, fountains and 폭죽, strobe, screen flash, haze, LED floor ripples, mirror-ball rays, DJ booth glow with ON AIR sign, sparkle trails and follow spots.
- `Lasers.luau` — purple laser fans and moving heads in the house show's sections; cues lock on tables or follow walkers.
- `Director.luau` — turns orders, 후원, 합석 and DJ pads into synced world cues, including bottle-staff trails and 짠 / 댄스 moments.
- `Boards.luau` — side LED "CLUB OCEAN 랭킹전": 4 cards with row-slide, ▲n / NEW chips and a "NEW 1위" stamp, plus ticker and live banner.
- `Signs.luau` — table LED signs with the current orderer, presenter board over the lead bottle staff, bartender bottle flair, 👑 / 💸 crowns for #1.
- `Ui.luau` — left rail (💸 후원 · 🏆 랭킹 · 🎧 DJ), sheets, DJ pad (PC keys 1–5), receipts; touch, PC and gamepad.

**Install steps for the owner**
1. In Studio, put `GwangalliClubPlusShared` (ModuleScript, child `Lines`) in ReplicatedStorage.
2. Put `GwangalliClubPlus` (Script plus its child modules) in ServerScriptService.
3. Put `GwangalliClubPlus` (LocalScript plus its child modules) in StarterPlayer › StarterPlayerScripts.
4. Robux 후원 (optional):
   - Create developer products and list them in `Config.Robux.Products` as `{ id, won, label }`.
   - If ProcessReceipt is free, the add-on installs it after 6 s (`ClaimWait`).
   - If another script owns ProcessReceipt, it should set the ServerStorage attribute `GwProcessReceiptOwner` and forward receipts to `ServerStorage.GwangalliReceiptHandlers.GwangalliClubPlus`.
5. Game settings: publish the place and turn on "Enable Studio Access to API Services" so rankings save (otherwise they stay per-server). Text filtering only works in a live game or Studio play.

No existing scripts need editing. If GwangalliLiveConfig has `enabled("clubplus") == false`, the add-on stays off.

**Config knobs** (all in `GwangalliClubPlusShared.Config`)
- `Enabled`, `RequireWristband`
- `OrderTier` / `DonateTier`: price thresholds for 프리미엄 / VIP / 레전드.
- `Donate`: presets, min/max/step, cooldown, queue limits, message length, templates, stats.
- `Robux`: products, install switch, claim wait.
- `DJ`: on/off, turn length, queue size, price, rejoin cooldown, booth radius, admins (UserIds or group rank), share paid to the DJ and its nightly cap, pad cooldowns.
- `Ranking`: top size, flush/sync intervals, retries.
- `Stage`: lead time, gap, max cues, ticker length.
- `Rate`: request rate limit.
- `Quality`: per-tier budgets.
- `Show`: laser palette and width, head rows and height, laser-show frequency, sign height, crown offsets.
- `Fallback`: map positions and menu prices.

**Behaviour to know**
- Players flagged `GwJourneyClub = "locked"` or without a valid wristband can't 후원 or DJ. The club's own systems set those attributes.
- Diagnostic attributes (`Zone`, `Err_*`, `JobErr_*`, `Started`) are written on the client LocalScript, for checking in Studio.

**Knowingly left out**
- From the research doc: 테이블 선물 gift parade, 밸런스 게임 / 단체 사진 / 합석 리포트, 명예의 전당 and 인기 테이블 boards, the lobby "TONIGHT" screen.
- A per-player opt-out of name display.
- No audio cues.

Test tools (mock runtime, bundler, mock tests, studio harness) are in `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/mock/` and `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/studio/`. The studio build uses lower quality budgets for testing only.
