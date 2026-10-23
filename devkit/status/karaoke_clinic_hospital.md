## Karaoke · Clinic · Hospital: handoff

> 범례 / legend: **[V]** I checked this myself on 2026-10-23 (read the code or re-ran it on the current `src`). **[L]** I read it in an agent's studio log or screenshot, but did not re-run it. **[C]** An agent report says so and nobody has verified it.
> Repo `/home/user/-`, branch `claude/car-interior-window-rendering-6i5i62`, working tree clean. **[V]** All 71 Luau files in these three areas pass `luau-compile --binary`.
> **[V]** `python3 tools/bundle_plus.py <out>` builds both files and they compile:
> - server: 123 modules
> - client: 191 modules
> - Clinic, KaraokePlus and HospitalPlus are inside the bundle.
>
> **[V]** `default.project.json` only maps MiniGames and CarInterior. None of these three add-ons are in Rojo, so the bundle is the delivery path.

### 0. Journals and agents

| Workflow | Label → agentId | Outcome |
|---|---|---|
| `wf_d5ca3ed4-1f6` | build:karaoke `ab19b65931c0d896b` (1st), `ab9a8413fd28d31fa` (2nd) | both returned a result |
| | build:hospital `af24aa0cdfc645760` | failed (session limit) |
| | build:hospital `ac1c42003c9ee4217` | result |
| | test, review:{correctness,experience} and fix, for both karaoke and hospital | **all failed, twice**: 10-16 17:14 session limit, 10-17 07:43 weekly limit **[V]** (I read the transcripts) |
| `wf_e860d0a9-9d6` | research:clinic `ac534313fa6ee3ad5` | result: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/clinic/research.md` (545 lines) |
| | build:clinic `ad9badbdffedb0a01` | died 10-16 17:20 (session limit) after writing most files |
| | build:clinic `ae3c61fa87507d4bf` | died 10-17 07:44 (weekly limit) during studio run14. **No build result was ever returned.** test/review/fix never ran (both rounds). |
| `wf_6914fa1a-18a` | first research:clinic | no result |
| `wf_acf868d2-2e2` | first hospital lane | every stage failed (`feat/hospital/design.md` exists anyway) |
| `wf_e8381be9-1c3` | build/review:T_clinic | interior team; relevant only for overlaps |

- Transcripts: `/root/.claude/projects/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/subagents/workflows/<wf>/agent-<id>.jsonl`.
- Repo copies of the scratch folders: `/home/user/-/devkit/feat/{karaoke,clinic,hospital}`. **The hospital offline sim (`feat/hospital/sim/`) is NOT in devkit.** Copy it before `/tmp` goes away.
- My re-run copies: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/handoff/karaoke_clinic_hospital/` (`kp/`, `sim/`, `clinic/`, `bundle/`, `*.out`).

---

### 1. GwangalliKaraokePlus (코인노래방, 팡팡노래방 style)

**Files (30)**
- `src/ReplicatedStorage/GwangalliKaraokeShared/`
  - `init` (config, names, clock, err)
  - `Songs` (58 songs **[V]**, 484 lines)
  - `Chart` (904 lines; one timeline shared by server and clients)
  - `Score`, `Search` (초성 / 곡번호)
- `src/ServerScriptService/GwangalliKaraokePlus/`
  - `init.server`, `Bridge`, `Net`, `Rooms` (1003 lines), `Playback`, `Mics`, `Scoring`, `Voice` (new Audio API), `Store`
- `src/StarterPlayer/StarterPlayerScripts/GwangalliKaraokePlus/`
  - `init.client`, `Net`, `Kit`, `Rooms`, `Legacy`, `Band`, `Mic`, `Rhythm`, `TV` (995 lines), `Lyrics`, `Background`, `Hud`, `Book`, `Remote`, `Prompts`, `Fx`

**What works**

| Flow | Status |
|---|---|
| Offline server: pay / 중복 결제 방지 / 무료 체험, queue / 우선예약 / cancel / refund within 5 s, pause / tempo / 처음부터, tap + voice scoring, 100점 서비스곡, rewards, privacy / knock / kick / intruder push-out, mic pass, idle/empty release, voice-device check | **[V]** `t_server.luau`: 76 ok, 0 failures |
| Offline client: every UI module checked against the class/property list, PC + phone | **[V]** `t_client` 21 ok, `t_client_phone` 21 ok |
| Charts, search, intro | **[V]** `t_chart` builds all 58 charts; `t_search` and `t_intro` run clean |
| Temp studio: buy 4 songs, reserve, title card, colour-wipe lyrics, pause, autotap, score screen | **[L]** `feat/karaoke/studio/run9.log` reaches state play → settle → score, exit 0 |
| Temp studio score of 80점 A, rewards, 노래왕 board | **[C]** screenshots in `studio/run9/S4_score.png` |
| Real Roblox: Audio API echo mic, soundproofing, voice scoring, DataStore saving, TV SurfaceGui on the screen part | **never tested** |

- The temp studio draws the TV as a flat overlay. The agent believes this is the browser engine's fault, not the code's **[C]**.
- The source has not changed since the agent's last test run. My regenerated `srcs.luau` has exactly the same byte size (425,461) **[V]**.

**Re-run the tests**
1. Copy the three `src` folders into `kp/{sh,srv,cli}`.
2. Run `python3 -I handoff/karaoke_clinic_hospital/gensrc_kp.py`.
3. Run `luau t_*.luau` inside `kp/`. The original harness is in `feat/karaoke/test/` (`mock.luau`, `classprops.luau`, `sync.sh`, `gensrc.py`).

Studio:
- Build with `feat/karaoke/studio/build9.py`, which uses `shpatch/` with longer timers: LeadIn 5, ScoreHold 120, PauseMax 900.
- Drive with `kp*.js`.
- Always run under `flock …/.studio.lock timeout 1500`.

**Config knobs** (`GwangalliKaraokeShared/init.luau:34-108`) **[V]**
- Switches: `Enabled`, `TakeOverLegacy`
- Billing: `Billing` ("credits" or "free"), `FreeWhenNoEconomy`, `Packs` (500 / 1,000 / 2,000원), `MaxCredits` 30, `RefundWindow` 5, `BonusScore` 100, `BonusSongsMax`
- Queue and timing: `QueueMax` 20, `QueuePerPlayer` 6, `EmptyGrace` 40, `IdleRelease` 150, `TapLatency` 0.04
- Room access: `DefaultPrivacy` "friends", `AllowedMax` 12
- Voice: `Voice` "auto", `Soundproof`, `EchoAllMembers`
- Rewards: `ScoreCoins` (300원 at 95점+, 5 a day), `WriteBoard`, `WriteLED`
- Saving: `DataStoreName` `GwangalliKaraokePlus_v1`, `ChartStoreName` `GwangalliKaraokePlus_Chart_v1`
- Sounds: `Samples`, `Instruments` (all ""), `SongAudio = {}`
- Remotes, under the shared module's `Remotes` folder: `KPRequest` (RemoteFunction), `KPEvent`, `KPLive` (Unreliable)

**Integration with the owner's place** **[V]** (from `Bridge.luau`)
- Money: `ServerStorage.GwangalliGameplayAPI` ops `balance`, `spend`, `earn`, `addStats`
- `ServerScriptService.GwangalliGameplay` (Folder) → `VenueLife` (caps, sing pose, mic prop, teleport permission)
- `GwangalliProgressAPI` `track karaoke_song`, `GwangalliSocialAPI` `joint`
- Lobby LED: `CollectionService` tag `LEDScreen`
- Legacy takeover: `Bridge.takeOver` keeps every ProximityPrompt under `KaraokePanel` disabled after `GwangalliKaraokePrompt` appears
- Booths: tag `KaraokeRoom` inside venue `광안 코인노래연습장`, parts `KaraokeZone`, `KaraokePanel`, `KaraokeScreen`, `WirelessMic`
- It keeps writing the old `KRenter` / `KRenterName` / `KPaidUntil` attributes and adds `KPState`, `KPCredits`, `KPSongNo`, `KPMicsOut`, `KPTambOut`. **[V]** The interior code does not read the new KP* attributes yet; `T_karaoke` keeps `KaraokeScreen`.

**Known gaps (agent-listed [C])**
- Every `soundId` is "", so all songs use the built-in, chiptune-like band.
- The 민요 melodies need checking by ear.
- Left out on purpose: `SearchAudioAsync` MR library, per-song global top 5, "내 목소리 듣기".
- Listeners hear the singer's normal voice alongside the echo.
- The owner's `GwangalliPlayShared/Journey` still says "500원이면 30분!" **[V]** (found in the place dump).

**Fragile code fact [V]:** song numbers are `38000 + 131*index` (`Songs.luau:428-458`). Inserting a song into `LIST` renumbers every song after it.

### 1b. Pending: real-song support (`feat/lane_args_round2.json` → `features[1]` key `karaokesongs`, **not started [V]**)
No file mentions `CustomSongs`, `addCustom` or `lrc`, and no workflow ran this lane. The same file's `features[0]` is `clubfun` (another area).

**Spec summary**
1. A song may carry `soundId` (audio the owner uploaded and has rights to), `soundOffset`, and `lrc = {{t=sec, text="..."}, ...}` (optional end time and `{M}/{F}/{A}` part prefix). For lrc songs:
   - the TV wipe follows `Sound.TimePosition`, interpolated per character up to the next line;
   - long gaps show 간주;
   - the band/melody synth is OFF;
   - tempo and key are hidden, or show the hint "원곡 반주는 템포/키 고정";
   - scoring falls back to voice-activity or rhythm-tap;
   - song number, search and charts list them like built-in songs (genre, 'new' tag).
2. New `GwangalliKaraokeShared/CustomSongs.luau`:
   - returns `{}` by default, with a commented Korean example (rights-only, upload in Creator Hub, use the timing tool);
   - `Songs.addCustom(list)` validates types, lengths, ≤300 lines and sorted times, and numbers songs 90001+ unless a number is given;
   - call it with `require(CustomSongs)`. The bundle will also feed the list from the server config.
3. 가사 싱크 도구 (client-only, never saves on the server):
   - who: Studio play mode, or players with the place's admin attribute;
   - opened from a hidden 리모컨 button or `/가사싱크`;
   - inputs: soundId + lyric text;
   - controls: 재생, then SPACE or the big 탭 button at each line start; undo, ±0.1 s, replay from line N, preview with the real wipe;
   - 내보내기 shows a selectable Lua table and prints it to Output.
4. Booth sync for everyone, late joiners seek the Sound, and a Sound load failure shows a Korean message and skips.
5. Tests: offline (lrc maths, merge/validation); temp studio with a fake soundId and a simulated clock; screenshots of the tool and of the TV with a custom song.

**Where to plug in [V]**
- `Songs.luau:428-460`: move the normalisation loop into `normalize(s)` and reuse it in `addCustom`. Update `LIST`, `byId`, `byNo`, `COUNT`. `Search.find` and `Book` iterate `Songs.LIST`, so they pick custom songs up automatically.
- `Chart.get` (`Chart.luau:816`): needs an lrc branch with absolute line times, duration and 간주 gaps, no melody, and taps derived from the lines. The server's `Playback.luau:74` uses the chart's duration, so the server needs lrc length or a `length` field; it has no Sound.
- `Band.luau:308-357` (`trackOf`/`syncTrack`) already:
  - takes `soundId` / `Config.SongAudio`;
  - seeks on start (handles late joiners);
  - corrects drift over 0.12 s;
  - applies tempo through `PlaybackSpeed` and key through PitchShift.

  For lrc songs: force rate 1 and key 0, mute synth and guide, and detect `IsLoaded` timeout to show a toast and skip. The skip needs a server op so the whole room skips.
- `Lyrics.luau` and `TV.luau`: wipe from `TimePosition`. `Remote.luau`: tempo/key hint and the hidden tool button.
- Admin attribute: Player attribute **`GwangalliAdmin`** (`GwangalliLiveConfig.ADMIN_ATTR`, a UI hint only; the server re-checks), or `RunService:IsStudio()`.
- Bundle: `GW_CONFIG` (`tools/bundle_plus.py` ~105-126) has no songs slot. Clients only get `ReplicatedStorage.GwangalliPlus` attributes (`PassId_*`, `Off_*`), so server-config songs must be replicated, e.g. as a JSON StringValue under the shared module, before the client calls `addCustom`.

---

### 2. GwangalliClinic (광안 메디컬 의원 진료 보기)

**Files**
- Shared: `init`, `Config` (184 lines), `Medical` (496), `Billing` (272), `Sites`
- Server: `init.server`, `Bridge` (665), `Store`, `Site`, `Net`, `Patient`, `Queue`, `Visit` (1405), `Checkup`, `Ward`
- Client: `init.client`, `Ui` (1238), `Net`, `Prompts`, `Tracker`, `Desk`, `Consult`, `Treat`, `Pharmacy`, `Checkup`, `Screens`, `Staff`, `Chart`, **`Lounge`** (waiting-room magazine; added by the second agent, not in the design)

**Server flow** (`Visit.luau`; ops registered at :1329-1341, plus `checkup` at `Checkup.luau:473` and `ward` at `Ward.luau:258`) **[V]**
`desk_wait → desk_called → desk → consult_wait → consult_called → consult → (treat_go → treat | iv_go → iv) → pay_go → pharm_go → pharm_wait → pharm_ready → done`, plus `need_money`, `chk_course → chk_result`, and Ward `퇴원 수속`.
- Remotes: `GwangalliClinicShared.Remotes.ClinicRequest` (RemoteFunction, token-bucket rate limits) and `ClinicEvent`.
- `State` Configuration (`Active`, `Legacy`, `Act_<staff>`).
- Owner/test hook: `ServerStorage.GwangalliClinicAPI` with ops `invoke`, `visit`, `health`, `cancel`.

**Verification status**

| Step | Status |
|---|---|
| Billing / Medical maths (4 kinds × day/night × 초진/재진 × debt; vitals; cause text; grade) | **[V]** `t_billing`: fails 0. The test needs a `local Vector3` shim on a copy of `Config.luau`; my copy is `handoff/.../clinic/`. |
| 번호표 → 창구 call → 접수/문진 → consult call → enter → 4 exams → 진단 J00 → 3 plans (A 15,000 / B 27,000 / C 5,500) → plan A → treat (illness cleared, fatigue 91→40) | **[L]** `feat/clinic/studio/run12.log` (driver clinic6.js), screenshots `out12/C1_consult.png`, `T1_inject.png` |
| 수납 (pay), 처방전 → 약국 → 3-dose course | **Unverified.** `out12/R1_receipt.png` and the out11 05–07 shots are **OOM crash screens [V]**; run7/run8 pay calls failed with `far`/`noVisit` because the avatar position was NaN |
| IV (수액) path (plan B, 위염/번아웃), Ward/퇴원 수속, debt on walk-out, persistence (`GwangalliClinic_v1`), legacy prompt takeover live, virtual patients, Staff NPCs | **Never tested.** The studio drivers set `Config.Staff.Enabled=false`. |
| 건강검진: eye, ear and ECG stations ok; height and bp returned `tooSoon`; report "남은 검사 2개" | **[L]** run13. Not complete end to end. |
| Offline state-machine test with a mocked Bridge (design §4.10) | **Never written** |

**Suspected bugs, for the next reviewer** (found by reading code; not reproduced)
1. **NaN character position after the treat step** in the temp studio (runs 7, 8, 12, 13). `Site.lie` and `unlie` guard zero vectors (`Site.luau:425-485`), so the cause is unknown: Health's nurse choreography, the engine, or our anchoring (`root.Anchored=true` at `Site.luau:443`). Check in real Studio.
2. **`tooSoon` at height/bp** 7–22 s after `begin`, while `MinStation` is 3.5. Likely cause: a second `begin`, possibly from the client UI, rebuilds `chk.cur` with a new `t0` (`Checkup.luau:296-338`). The same path lets a client re-roll its measurements.
3. **Debt can come back after it was paid.** Sequence: `defer` → `Store.addMirrorDebt` sets `mirrorPinned`; the player pays within 30 s of the last mirror tick and leaves; `save()` keeps `max(current, pinned)` (`Store.luau:218-228`).
4. `Bridge.canAfford` checks `cash>=amt or bank>=amt` (single account). It is consistent with `charge`, but a split balance is reported as 잔액 부족.

**Config knobs** (`Config.luau`) **[V]**
- Switches: `Enabled`, `Debug`, `TakeOverLegacy`, `PersistHealth`, `StudioMemoryOnly`
- `Venue` (path `Gwangalli/hospital/광안 메디컬 의원`, zone box)
- `Wait`: desk/consult timings, `CallTimeout` 60, `RegisterTimeout` 240, `ConsultTimeout` 300, `GoTimeout` 180
- `Virtual` patients
- `Fees`: 진찰료 5,500/4,000, `NightAddRate` 0.3, `IVExtra` 12,000, `Vaccine` 35,000, `DefaultMethod` "card"
- `Treat`, `Meds` (3 doses / 150 s), `Checkup`, `Ward`
- `Pass` (`qol`, waits ×0.5)
- `Staff`
- `Interior`: `SuppressAlways` "번호표 뽑기"; `SuppressDuringCheckup` now also includes "혈압 재기" (last edit, commit fbd78e5, 10-17 07:41)
- `Reach`, `Rate`
- Test-only stretched timers live in `studio/clinic*.js`, not in the repo.

**Integration with the owner's place** **[V]**
- Requires `ServerScriptService.GwangalliGameplay` (Folder) → `Health` (`status`, `fatigue`, `rest`, `findBed`, `onLoaded`) and `Profiles` (`get`, `markDirty`, `persistent`).
- `ServerStorage.GwangalliHealthAPI` ops `treat`, `vitamin`, `checkup`, `setFatigue`, `setRisk` (all present in the place dump `Health.ModuleScript.luau:703-887`).
- `GwangalliGameplayAPI` `balance`, `spend`, `addStats`; the optional ctx from VenueLife / Play / MiniGames enables the `ctx.ledger` card/cash debit.
- `GwangalliPassesAPI has qol`; `GwangalliRemotes.Notify`; `ReplicatedStorage.GwangalliAnim` (Staff rigs), `GwangalliUI`, `GwangalliLayout`.
- Legacy takeover: tags `HospitalPrompt` / `HospitalStaff` are kept disabled, and only after boot.
- If the Health system is missing, `waitReady(90)` fails and the old hospital keeps working.
- With the interior (client): the character attribute `GwTreating` drives the 진료 중 lamp (`Hosp_Doors.luau:150`). Screens are overlaid by part name `CallBoardNo`, `WaitScreen`, `KioskScreen` (T_clinic) and `WaitMonitorText` (Hosp_Doors). No interior code sets `GwClinicScreen`.

**Not implemented (design options) [V]:** 광안 종합병원 lite (`GwB_HospitalDept`) and the second doctor / 진료실 2. The vaccine department and Ward 퇴원 수속 do exist.

**Studio drivers**
- `feat/clinic/studio/gen.py` → `inject.json`
- `clinic2…8.js`; run12 used clinic6, run13 clinic7; clinic8 / run14 died at boot
- helpers `helper/ClinicTest.server.luau` and `ClinicClientTest.client.luau`
- The temp studio hits OOM at about 2 GB after 10–20 minutes, so keep runs short and split the flow.

---

### 3. HospitalPlus and Hosp_* (client-only facility layer inside GwangalliBuildingInterior)

**Files (12):**
- `HospitalPlus` (director: build at 140 studs, tear down at 170; 10 Hz animation; `HospDebug`)
- `Hosp_Geo` (data, keeps, `BUILD_R` / `TEAR_R` / `ROOF_R` / `PORTAL_Y=-50`, `BUDGET`)
- `Hosp_Lib`, `Hosp_UI`, `Hosp_Restroom`, `Hosp_Elevator`, `Hosp_Doors`, `Hosp_Exits`, `Hosp_Portal`, `Hosp_Rooms`, `Hosp_Roof`, `Hosp_Signs`

Loaded by `GwangalliBuildingInterior/init.client.luau:510` (`ADDONS = {"HospitalPlus","Reskin"}`, `A.start(ctx)`) **[V]**. No remotes and no saving.

| Item | Status |
|---|---|
| Offline sim: restroom doors / stall lock, fire exit, ER doors, portal in / watchdog / cleanup, lift hall call and doorway hold, foreign decor hidden | **[V]** `simtest2`: 22/22 PASS on the current `src` |
| Elevator 1→2→R→1, staff / store / stair hidden rooms, glass doors | **[V]** `simtest` sequence runs cleanly |
| Temp studio: all zones built, lift moved to 2F/R, an NPC brought the cabin to 2F | **[C]**. In `studio/run12.out` **[V]**: `portal_store_built` PASS, then `portal_stair` TIMEOUT (engine OOM / slowness) |
| Walking through doors in studio | offline only (the engine's avatar controller overrides teleports) **[C]** |

- Re-run the sim: `handoff/.../sim/mk.sh` (bundles via `bprev/gen.py`), then `luau simtest.luau` and `simtest2.luau`. They need `../../../bprev/fx/hospital_backhall` and `fx_bld.luau`.
- Live screenshots: `feat/hospital/final/hospital_live_{1,2}.jpg`.

**Knobs [V]**
- LocalScript attributes: `Enabled=false` or `HospitalPlus=false` turn the layer off (`HospitalPlus.luau:178`); `Debug`; `HospDebug` commands (`status`, `lift`, `call 2`, `go staff hall`, `tp x y z`), output in `HospDebugOut`.
- Keep `Workspace.FallenPartsDestroyHeight` below -60, because the hidden rooms sit at about y -47 **[C]**.

**Requests to other files**
- `init.client.luau`: venue rooms under `SKIP_ROOTS` now build (`skipped(f.model, true)` at :236, commit 6aacf68) → **done [V]**.
- `T_clinic.luau:4879`: floor directory should read "R 옥상 정원 · 휴게 공간" → **not done [V]** (still "R 옥상 (관계자 외 출입금지)").
- `T_clinic.luau:4884`: restroom hang sign → **still present [V]**. HospitalPlus hides it locally (sim `foreign_hidden` PASS).
- T_clinic ceiling lights should avoid `facility_room` keeps → not checked.

**Known limits [C]**
- Bells, the ER intercom and the lift alarm only play a sound and a toast.
- The roof fire stair is a hidden room behind a fade.
- Other riders pop between floors.
- The telescope uses a raised viewpoint.
- One studio shot was missing the 2F back wall; this layer does not hide it.
- Commit ce4a495 removed the disability symbols; keep it that way.

---

### 4. Next steps, in priority order
1. **Clinic**:
   - Write an offline state-machine test (mock Bridge / Health / Profiles) covering `pay`, `pharmacy`, `dose`, IV, `defer`/debt, ward, and the checkup `begin`/`station` path.
   - Fix suspected bugs 2 and 3 above.
   - Run short, split studio runs for 수납 → 약국 and 건강검진.
   - Investigate the NaN position.
   - Then do the missing correctness and experience review.
2. **Karaoke**: the review (correctness and experience) and fix stages never ran. After that, build `karaokesongs` (§1b).
3. **Hospital**:
   - Run review and fix.
   - Apply the two T_clinic text and sign edits.
   - Copy `feat/hospital/sim` into `devkit`.
4. All three: test in real Roblox Studio. The voice / Audio API, DataStores, SurfaceGui on the screen part, the place's Health choreography and the legacy takeover have never run in the real engine.