# GwangalliClinic — 병원 진료 보기 (research + design)

Feature: a full, real Korean 의원 visit at **광안 메디컬 의원** (map clinic) driven by the game's real
피로도 → 질병 → 병원 loop: 번호표 → 접수(문진) → 대기·호출 → 진료실(의사 상담·진찰·진단·치료계획) →
처치(주사 / 수액) → 수납(진료비 영수증) → 약국(처방전·조제·복약지도·약제비) → 복약, plus a 2F
**건강검진 코스** and a 입원실 **퇴원 수속**. Add-on only (no existing script edited).

Abbreviations used for source paths (owner's v7 dump, read-only):
- `SRC` = `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/src`
- `HEALTH` = `SRC/ServerScriptService/GwangalliGameplay/Health.ModuleScript.luau`
- `HSH` = `SRC/ReplicatedStorage/GwangalliHealthShared.ModuleScript.luau`
- `GSH` = `SRC/ReplicatedStorage/GwangalliGameplayShared.ModuleScript.luau`
- `GPS` = `SRC/ServerScriptService/GwangalliGameplay.Script.luau` (the gameplay core Script)
- `PROF` = `SRC/ServerScriptService/GwangalliGameplay/Profiles.ModuleScript.luau`
- `INT` = `/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior` (other team, read-only)
- Map dump: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/hg/dump.json` (+ `hosp_tree.txt`);
  extracted key parts list: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/clinic/hosp_parts.txt`

---------------------------------------------------------------------------------------------------

## 1. Existing integration points (exact)

### 1.1 The fatigue → illness → hospital loop (who does what)

| Piece | Where | Facts |
|---|---|---|
| Fatigue stat | `GSH:157` `G.STATS.fatigue` (`inverted = true`, 0..100, lower is better) | persisted in `d.stats` (PROF sanitize keeps `G.STAT_ORDER`, `PROF:189-191`) |
| Fatigue gain on shift | `HEALTH:772-791` tick: `if onShift ... addFatigue(player, HS.workGain(1, night))` | +1 / 32 s day, +1 / 22 s night (`G.HEALTH.fatigue`, `GSH:3532-3543`) |
| Fatigue per finished task | `HEALTH:235` `Health.onWork(player, seconds, jobId)`; called by Jobs `SRC/.../Jobs.ModuleScript.luau:189-197` (`pcall(H.onWork, player, math.max(0, seconds), jobId)`), `:795`; Gukbap career `.../Play/Career/Gukbap.ModuleScript.luau:1330-1331` | taskBonus 1.5 (+0.5 night) |
| Fatigue relief | `HEALTH:214` `function Health.rest(player, amount?, reason?) -> fatigueAfter`; callers: Life.sleep `.../Life.ModuleScript.luau:542-544` (`ctx.health.rest(player, G.HEALTH.fatigue.sleep or 70, "sleep")`), meals `Life:801-802`, `Details.ModuleScript.luau:1561-1562` | off shift -1 / 90 s automatically |
| Pay debuff | `HEALTH:203` `Health.payMultiplier(player) -> (mult, reason)`; Jobs reads it via `script.Parent:FindFirstChild("Health")` (`Jobs:125-155`) | 1.0 / 0.7 (≥50) / 0.4 (≥75) / 0.2 (≥90 or ill) |
| Risk → illness | `HEALTH:783-788` risk accrues only while working at fatigue ≥ 80; `fallIll` `HEALTH:265` | `h.illness = { kind, since, online }`; notify `"%s %s에 걸렸어요"`; `ctx.setWaypoint(player, "광안메디컬")`; HealthEvent `"ill"` |
| Illness kinds | `GSH` `G.HEALTH.KINDS` (cold 감기 15,000 / ache 몸살 25,000 / gastritis 위염 35,000 / burnout 번아웃 45,000), each `{name, icon, fee, desc, cure, emote}`; `HS.pickKind` `HSH` (night → cold, rider/taxi/lifeguard → ache, hoe/gs25/convenience/starbucks → gastritis, fatigue ≥ 97 → burnout) | `cure` strings already describe the real treatment: 감기 "주사 한 방 + 감기약 3일분", 몸살 "해열 주사 + 근육이완제", 위염 "위장약 처방 + 수액", 번아웃 "영양 수액 + 휴식 처방" — **our treatment plans implement exactly these** |
| Ill effects | `HEALTH:111-130` `applyCharacter`: WalkSpeed × 0.7, character attr `GwIll`; `HEALTH:803-812` 행복 -1/min, friend text after 45 s | client `GwangalliHealth/Effects` grade + cough emotes |
| Collapse | `HEALTH:813` `if h.illness.online >= Hh.collapseAfter (600 s) and not s.collapsing and not s.treating then collapse(player)`; `collapse` `HEALTH:306-381`: PlatformStand, `ctx.endShift`, fade "🚑 구급차 이동 중…", fee `HS.ambulanceFee(kind) + debt` (`:340`), bank → cash → **debt** (`h2.debt = math.max(0, fee - paid)` `:357`), cure, fatigue -50, 행복 -8, wake on `Health.findBed("ward")`, notify "광안메디컬 입원실에서 눈을 떴어요 🏥", HealthEvent `"woke"` | Player attr `GwCollapse` true during it |
| KO → hospital | `.../StreetInteract.ModuleScript.luau:488-505`: after KO `bed = ctx.health.findBed("ward", nil)` → placed on a ward bed | also EMS player job: `.../Play/Ems/Patients.ModuleScript.luau:36` `Patients.TRANSIT = Vector3.new(-465.3, 9.6, 304.5) -- 1F TreatmentRoom (TreatBed1 is unused by Health)`, `:277`, `:299` teleport held patients there; char attr `GwEmsPatient` |

### 1.2 Server APIs we will call (signatures)

**A. Health module (direct require, same Lua VM; precedent = Jobs `:134` requires it the same way).**
Instance path: `ServerScriptService["GwangalliGameplay"]` **Folder** (the Script of the same name is its
sibling; `GPS:41-47` finds the folder "by class") → `ModuleScript "Health"`.
```
Health.status(player) -> statusView?        HEALTH:138  (HS.statusView: fatigue, tierLabel, mult, risk, riskThreshold,
                                                          debt, visits, cured, collapses, fees, stats, illness{kind,name,icon,desc,cure,fee,since,minutes})
Health.fatigue(player) -> number            HEALTH:181
Health.isIll(player) -> kindId?             HEALTH:186
Health.payMultiplier(player) -> (n, why?)   HEALTH:203
Health.rest(player, amount, reason) -> f    HEALTH:214   (whole points through ctx.addStats + pushes Player.Fatigue)
Health.findBed(kind, near?) -> BasePart?    HEALTH:404   ("exam" | "treat" | "ward" | "any"; occupied seats +1000 penalty)
Health.onLoaded(player)                     HEALTH:896   (pushAttributes + applyCharacter + status push) — used after we restore a persisted illness
```
Ready check: `ServerStorage.GwangalliHealthAPI` exists (created at the end of `Health.init`, `HEALTH:1005`) and
`ctx.health = Health` already ran (`HEALTH:952`).

**B. `ServerStorage.GwangalliHealthAPI` (BindableFunction, `HEALTH:851-889`, `:1005`)**:
`Invoke(op, player, a, b)` with ops `status | setFatigue | setRisk | makeIll | cure | collapse | treat | vitamin | checkup | onWork`.
- `cure` (`:875`) → private `cure()` (`HEALTH:290-304`: illness=nil, risk=0, cured+1, attributes, walk speed, `ctx.changed`) + `pushStatus`. **No fee, no fatigue change, no happiness, no HealthEvent "cured"** — exactly the primitive we want.
- `setFatigue` (`:862`) absolute value (fallback when the module table is unreachable).
- **Always pass the Player instance**: `playerById` (`HEALTH:839-848`) falls back to `Players:GetPlayers()[1]` when an id is not found.
- Do NOT use API `treat/vitamin/checkup`: they go through `handle()` (`HEALTH:691`) = legacy fee (`kind.fee + debt`, `:724`) + legacy choreography.

**C. Profiles module (direct require, same folder) — only for fields the Health API cannot reach.**
```
Profiles.get(player) -> d?        PROF:460      live table: d.cash, d.bank, d.stats, d.health (Health owns it), d.lifeDay, d.job
Profiles.markDirty(player)        PROF:486
Profiles.view(player, keys)       PROF:902      EXPAND (PROF:889-899): cash -> cash, money, netWorth, transactions ; bank -> bank, netWorth, transactions
Profiles.persistent(player)       PROF:587      false = memory-only profile (never save our store then either)
```
`d.health` schema = `HS.defaultHealth()` (`HSH`): `{ illness = {kind, since, online}?, risk, debt, visits, cured, collapses, lastVitamin, lastCheckup }`.
We write only: `debt` (clear after our 수납 / add when the patient walks out unpaid), `risk` (lower after 진료 / 복약),
`visits`, `lastVitamin`, `lastCheckup`, `illness.online` (clamp, see §3.3) and restore `illness` (see §1.4).

**D. Money — `ServerStorage.GwangalliGameplayAPI` (BindableFunction, `GPS:458-474`)**:
```
Invoke("balance", player) -> cash, bank
Invoke("spend", player, amount, label) -> bool     ctx.spend: CASH first, then bank "(체크카드)" (G.spend GSH:754-772), toast "-15,000원 label"
Invoke("earn", player, amount, label) -> bool      bank credit
Invoke("addStats", player, {happiness = 5}, label) -> applied   (non-silent: one "능력치 변화" toast)
```
Used by KaraokePlus (`/home/user/-/src/ServerScriptService/GwangalliKaraokePlus/Bridge.luau:129-200`) and Passes.
For the 결제수단 choice (💳 카드 = 통장 / 💵 현금) we need an account-specific debit; there is no public op for it, so
`Bridge.charge` uses, in order:
1. `G.ledger(d, "bank"|"cash", -amount, label, os.time())` (`GSH:710-752`, returns `ok, "insufficient"`) on `Profiles.get(player)`,
   then sync exactly like `ctx.ledger` (`GPS:305-321`): `player:SetAttribute("Money", d.cash)`, `player:SetAttribute("Bank", d.bank)`,
   `GwangalliRemotes.ProfileChanged:FireClient(player, Profiles.view(player, {cash = true, bank = true}))`, `Profiles.markDirty`, and a
   `GwangalliRemotes.Notify` toast `{kind="money", title="-15,000원", body="광안 메디컬 의원 진료비 (체크카드)"}`.
2. fallback (module missing / Config.Payment.Mode = "api"): `GwangalliGameplayAPI:Invoke("spend", ...)` (no method choice; we
   compare `balance` before/after to print which account paid).
The Health module charges bank-first (`HEALTH:680-689`); our default method = 카드 (bank) to keep that behaviour.

**E. Remotes in `ReplicatedStorage.GwangalliRemotes` we fire (server → client only)**
- `HealthEvent` (`G.Remote.HealthEvent`, created `HEALTH:970-971`): fire `{kind="cured", illness=name, fee, status}` /
  `{kind="vitamin", fee, status}` / `{kind="checkup", status, advice, fee}` so the existing client
  (`SRC/StarterPlayer/StarterPlayerScripts/GwangalliHealth/Effects.ModuleScript.luau:318-336`: sparkle + "완치! 🎉" / "개운하다 💉";
  `Clinic.ModuleScript.luau:374-399` refreshes its status) plays its effects. Never fire `"clinic"` (opens the legacy sheet).
- `Notify` (`GPS:237-247`): `{kind = "success"|"warn"|"info"|"money"|"stat"|"home", title, body, sound = "notify"|"complete"}`.
- `ProfileChanged` (see D).

**F. Attributes / tags we read**
- Player: `Fatigue` (0..100), `Illness` ("" | kind) (`GSH:3518-3519`, pushed `HEALTH:102-110`), `GwCollapse`, `OnShift`
  (`Jobs:668`), `InTaxi` (`Taxi:2035`), `GwangalliProfileReady` (`PROF:549`), `Money`, `Bank`.
- Character: `GwIll`, `GwTreating` (Health sets it during its choreography; the interior's "진료 중" lamp reads it,
  `INT/Hosp_Doors.luau:138-170`), `GwKO`, `GwEmsPatient`.
- Tags: `HospitalPrompt` (anchor parts `Kind = "doctor" | "desk"`), `HospitalStaff` (rigs `Role = "doctor" | "nurse"`),
  `HospitalBed` (Seats `BedKind = "exam" | "treat" | "ward"`) (`GSH:3511-3525`), `LEDScreen` (GwangalliWorld/Screens cycles
  attribute `Messages`, `SRC/StarterPlayer/StarterPlayerScripts/GwangalliWorld/Screens.ModuleScript.luau`), `GwB_HospitalDept`
  (종합병원 desks, attr `ShopLifeKey`, `SRC/ServerScriptService/GwangalliBuildings/Builder/Hospital.ModuleScript.luau:246-255`).
- Clock: `ReplicatedStorage.GwangalliShared.clockNow()` (`SRC/ReplicatedStorage/GwangalliShared.ModuleScript.luau:52`; what `GPS:162-183` uses), fallback `Lighting.ClockTime`.
- Passes (optional): `ServerStorage.GwangalliPassesAPI:Invoke("has", player, "qol")` (`/home/user/-/src/ServerScriptService/GwangalliPasses/Api.luau:1-12`).
  The 편의 패스 already sells "대기 시간 50% 단축" (jail / KO); the clinic honours it for 진료 대기 (owner's "패스없이 … 계속 일하면" wording).

### 1.3 The map clinic (instances; `Workspace.Gwangalli.hospital["광안 메디컬 의원"]`, model rotated ~178.1° about Y; StreamingEnabled = true)

Root children: `1F`, `2F`, `Staff`, `AutoDoor_Hospital` (tag AutoDoor), `AmbulanceBay` (Law clones `Car_Ambulance` — never touch),
`BackYard`, `Destination` (DisplayName "광안메디컬", -495.8, 7.1, 261.2). Positions are world (x, y, z) from `dump.json`.

| Use | Path (under the venue) | Part / pos | Notes |
|---|---|---|---|
| 번호표 kiosk | `1F.Lobby.TicketKiosk` / `KioskScreen` / `TicketSlot` | (-500.49, 9.2, 282.04) / screen (-500.47, 10.6, 281.39) | interior hides these and builds its own kiosk (see §3.4) |
| 접수·수납 desk | `1F.Lobby.ReceptionDesk` (FrontPanel 20 wide, DeskSign (-514.55, 9.7, 283.49) "접수 · 수납") | legacy prompt anchor `Staff.HospitalPrompt_desk` (-514.47, 9.4, 281.18) | staff chairs (-509.77, 8.4, 290.24) and (-519.76, 8.4, 289.91) → 창구 1 / 창구 2 |
| Lobby LED (call board) | `1F.Lobby.LEDScreen` (tag LEDScreen) 13 × 3 at (-510.81, 15.3, 291.71); `SignGui` SurfaceGui (Brightness 2.5, tag GwSurfaceGui) → `Face` Frame → 2 × `Text` labels: "대기 3명 · 진료중 7번" / "다음 8번 · 접수 후 잠시만 기다려 주세요" | static today (no Messages attr) |
| Waiting room TV | `1F.WaitingRoom.LEDScreen` 10 × 5.6 at (-468.84, 14.5, 293.08) | 3 × `WaitingBench` (12 BenchSeat Seats) facing it |
| 진료실 1 · 내과 | `1F.ConsultRoom`: `DoctorDesk.Monitor` 4 × 2.3 (-557.93, 11.15, 276.11) ("진료 차트 · 혈압 118/76"), patient **Seat** `ConsultRoom.Seat` (-554.48, 8.4, 280.87), `ExamBed.BedSeat` (Seat, `BedKind="exam"`, -569.57, 8.8, 283.18), `BPMonitor.BPUnit` (-563.84, 10.7, 273.16), `Scale`/`ScaleDisplay` (-571.5, 13.0, 267.1) | door `1F["Door_진료실 1 · 내과"]` (x -535 z 293) |
| Static staff | `Staff["의사 김선생"]` (HRP -554.2, 8.9, 272.5; seated by Health `HEALTH:524-548`), `Staff["간호사 박선생"]` (HRP -565.8, 9.8, 283.9, beside ExamBed; hidden `GwProp="syringe"` parts), `Staff.VialTray` (-565.64, 9.9, 279.41) | block R15 rigs with AnimationController (GwangalliAnim-compatible) |
| 주사실 · 처치실 | `1F.TreatmentRoom.TreatBed1.BedSeat` (`treat`, -465.34, 8.8, 308.6) + `IVPole`/`IVBag` (-467.76, 12.4, 312.13); `TreatBed2.BedSeat` (`treat`, -479.34, 8.8, 308.15) + `IVBag` (-481.75, 12.4, 311.67); `MedicineCabinet`, `TreatmentCart` | door `1F["Door_주사실 · 처치실"]` (x -487 z 298.8) |
| 약국 코너 | `1F.PharmacyCorner.PharmacyCounter` (28 wide), `DeskBell` (-555.02, 10.75, 297.26), `PrescriptionScreen` (-535.48, 11.75, 299.35; SignGui → Face → `Text` "처방 접수", `Sub` "조제 대기 2건"), `DispensingMachine` (-564.68, 10.6, 317.21), chair (-545.19, 8.4, 302.59) | patient side = the corridor (Law spot `pharm` -540, 294) |
| 2F 건강검진센터 | `2F.CheckupCenter`: desk `Monitor` (-537.12, 25.3, 300.5) + staff chair (-535.23, 22.55, 303.92) + patient Seats (-531.99, 22.55, 296.62), (-536.98, 22.55, 296.45); `Scale` (-548.61, 21.2, 299.98) + `HeightRod` (-548.65, 25.05, 301.37) + `ScaleDisplay` (-548.65, 27.3, 301.35); `BPStation`/`BPMachine` (-556.09, 24.75, 299.43) + `BPCuffRing` + Seat (-555.91, 22.55, 293.83); `EyeLine` (-564.57, 21.07, 307.96) + `Sign_시 력 표` (-574.58, 27.45, 307.63); `HearingBooth` 8 × 8.6 × 8 (-532.05, 25.35, 329.03); `CheckupBed.BedSeat` (`treat`, -566.07, 22.95, 329.32) + `ECGCart.ECGUnit` (-555.51, 24.75, 327.46) | glass door `2F["Door_건강검진센터"]` x -543..-535 z 295; stair from 1F back hall |
| 입원실 | `2F.Ward_201/202` `WardBed_A/B.BedSeat` (`ward`) ×4, `CallPanel` ×4, LEDScreen ×2 | **never reserve ward beds** (collapse / KO use them) |

### 1.4 Data saving facts

- Profiles: DataStore `GwangalliProfile_v1`, key `u_<UserId>` (`PROF:1-10`). **`d.health` is NOT persisted**: the loader keeps only
  whitelisted keys (`PROF:149-337` — `stats, job, ... work, law, fuel, dealer, crime`; no `health`) while saving writes it
  (`PROF:400` `Util.deepCopy(d)`). So illness, 미납금 (debt), visits, risk reset on every rejoin today (fatigue survives in stats).
  A rejoin is currently a free cure and a free debt wipe.
- Our add-on gets its own store `GwangalliClinic_v1` (key `u_<UserId>`): chart, history, medication course, last checkup report and an
  optional **health mirror** `{illness, risk, debt}` restored into `d.health` on join (Config.PersistHealth, default on) — see §4.4.

### 1.5 Client UI kit and helpers

- `ReplicatedStorage.GwangalliUI` (K) `SRC/ReplicatedStorage/GwangalliUI.ModuleScript.luau:1-30`: `K.BottomSheet`, `K.Modal`, `K.confirm`
  (`:2590`), `K.DialogBox` (`:2983`, portrait + typewriter + choices), `K.ListRow`, `K.Card`, `K.Pill`, `K.ProgressBar`, `K.Ring`,
  `K.Segmented`, `K.Chip`, `K.toast`, `K.feedback(kind)`, `K.blur`, `K.won`, `K.countUp`, `K.countdown`, colors `K.Color`, type scale `K.Type`.
- `ReplicatedStorage.GwangalliLayout` slots (`SRC/ReplicatedStorage/GwangalliLayout.ModuleScript.luau:25-45`): `topRight` (tracker card),
  `bottomCenter` (banners), `sheetRight` (side sheets; modal → disable touch controls), `dialog`.
- Modal etiquette used by GwangalliHealth (`SRC/StarterPlayer/StarterPlayerScripts/GwangalliHealth.LocalScript.luau` ctx.modal):
  ScreenGui attr `HideGwangalliHUD`, `K.blur(on, key)`, PlayerModule `GetControls():Disable()` on touch.
- `ReplicatedStorage.GwangalliAnim` (`SRC/ReplicatedStorage/GwangalliAnim.ModuleScript.luau:1-60`): `Anim.rig(model)` controller →
  `:pose(name)` (`clipboard`, `sit`, `sit_bench`, `sunbathe` = lying (Root -84°), `nap`, `hands_front` …), `:gesture` (`talk`, `listen`,
  `nod`, `scroll`), `:look(pos)`, `:emote` (`bow`, `nod`, `beckon`, `give`, `receive`, `think`, `thumbs`), `Anim.buildR15(opts)` (light
  block rig, anchored root, non-colliding, AnimationController) — used to build our extra staff and to animate all staff client-side.
- Built-in sounds already used in the place: `rbxasset://sounds/electronicpingshort.wav` (×35, the interior's kiosk "딩"),
  `clickfast.wav`, `swoosh.wav`. No marketplace ids needed.
- ATM 번호표 pattern (`SRC/StarterPlayer/StarterPlayerScripts/GwangalliFeatures/ATM.ModuleScript.luau:441-462`): ticket = random 12..48,
  "🔔 딩동! %03d번 고객님 / 2번 창구로 와 주세요", `K.feedback("notify")`, 1.1 s later the teller screen.

---------------------------------------------------------------------------------------------------

## 2. What exists vs what is missing

**Exists (keep, reuse):**
- Real state: fatigue (persisted), risk, 4 illness kinds with fee / desc / cure text, collapse + ambulance + debt, ward wake-up,
  pay debuff, ill walk speed, coughing, friend text.
- Legacy hospital UI (`GwangalliHealth/Clinic`): ONE bottom sheet opened by the 2 prompts ("진료 받기" on the doctor, "접수하기" at
  the desk, `HEALTH:464-492`) with 3 rows: 진료 받기 (fee `kind.fee + debt`) / 영양주사 30,000 (fatigue -40) / 건강검진 10,000 (one
  sentence of advice, `HS.adviceFor`). Treatment = 2.5 s on the exam bed with the nurse arm tween + syringe (`HEALTH:628-678`).
- Map rooms with the right furniture (kiosk, LED screens, benches, consult desk + patient seat, exam bed, 2 IV beds, pharmacy
  counter + dispensing machine, 2F checkup devices, wards). Static 김선생 / 박선생 rigs.
- Law/Hospital NPC life (`SRC/ServerScriptService/GwangalliGameplay/Law/Hospital.ModuleScript.luau:1-110`, `:732-757`): 접수 1, 의사 2,
  간호사 3, 외래 환자 3, 입원 환자 1, 보호자 2 walking a SPOTS graph (desk_front -515,281 · desk -503,284 · wait1..3 · cons -545,285 ·
  treat -478,308 · treat_bed -468,309 · pharm -540,294 · check -552,312 …), only while a player is within 170 studs of (-515, 7, 300).
- Interior team (client-only cosmetics): T_clinic dresses every room and adds toy interactions — a fake kiosk "번호표 뽑기"
  (`INT/T_clinic.luau:2287-2375`, fake numbers `ticketNo` `:2153-2157`), a fake "호출번호" board (`:2319-2346`, cycles every 14 s),
  a hanging waiting monitor with fake names (`:2588-2610`), toy BP / 체온 / 키·몸무게 / 시력 / 청력 / 체성분 / 조제 prompts
  (`:1833, 2426, 3641, 6086, 6181, 6279, 6492`); HospitalPlus doors / elevator / restrooms / roof, a "진료 중" lamp driven by
  character `GwTreating` (`INT/Hosp_Doors.luau:138-170`) and a fake "진료 대기" monitor by the consult door (`:180-200`).

**Missing (this feature):**
1. A real 번호표 + queue shared by all players (numbers, 창구, 대기 n명, ETA) with calls on the real screens (LED, TV, door monitor,
   kiosk, pharmacy screen) and a 딩동 chime.
2. 접수 at a 창구: 초진/재진 from a real chart, 방문 목적, 문진표 (symptoms), 미납금 notice.
3. 진료실 consult: seat, doctor dialogue, 진찰 (체온 / 청진 / 인후 / 혈압) with vitals derived from the real fatigue / illness,
   a diagnosis that explains WHY (the shifts / fatigue history), and treatment-plan choices with prices.
4. 처치: 주사 on the exam bed (nurse 박선생), 수액 on the 주사실 beds (our nurse), lying pose, IV drip, early leave.
5. 수납: itemised 진료비 계산서·영수증 (진찰료 / 주사료 / 처치료 / 검사료 / 미납금, 야간 가산, 공단·본인 부담), 카드 / 현금, 처방전.
6. 약국: 처방전 제출, 조제 대기 번호, 복약지도, 약제비, 약봉투, then a medication course (doses) with real effects.
7. 건강검진 코스 on 2F with real measurements and a 결과지 (grade A–D) that links back to the 진료 flow.
8. 퇴원 수속 after a collapse / KO ward wake-up (pay the 미납 응급 진료비 at 원무과).
9. Persistence: chart / history / meds / last report, and the illness / debt mirror (today lost on rejoin).
10. Staff for the new steps: 원무과 직원 ×2, 주사실 간호사, 약사, 검진센터 직원 (+ optional 대진 의사).

---------------------------------------------------------------------------------------------------

## 3. Conflicts / risks and how we avoid them

### 3.1 Legacy hospital prompts / sheet
Both legacy prompts would open the old sheet next to our flow and its "진료 받기" would charge the old fee.
→ **Takeover (KaraokePlus precedent, `/home/user/-/src/ServerScriptService/GwangalliKaraokePlus/Bridge.luau:405-440`)**: once our
server is fully booted, set every `ProximityPrompt` under `CollectionService:GetTagged("HospitalPrompt")` to `Enabled = false` and
keep it off (`GetPropertyChangedSignal("Enabled")`, `GetInstanceAddedSignal`). Config.TakeOverLegacy (default true). If our boot fails
anywhere, we never disable them (the clinic keeps working the old way). On `script.Destroying` / `game:BindToClose` nothing is needed.
The legacy `HealthRequest` RemoteFunction stays callable (same exploit surface as today; its own fees).

### 3.2 Health owns `d.health`
We never replace the table, only touch documented fields with type checks (`type(h) == "table"`, numbers finite). Cure via the
public API op `cure`, fatigue via `Health.rest` (fallback API `setFatigue`). If the Health module or API is missing → the add-on
does not start (logs a warning; legacy stays).

### 3.3 Collapse timer during a visit
`collapseAfter` = 600 s of illness online (`HEALTH:813`). A patient who reaches 접수 at 590 s would be hit by the ambulance flow
in the middle of our consult (fee + teleport to a ward). → From the moment a visit is registered and while the player stays inside
the clinic zone, Visit clamps `d.health.illness.online = math.min(online, collapseAfter - Config.CollapseGrace (180))` every 15 s
("병원 안에서는 의료진이 지켜봐요"). Leaving the zone stops the clamp (the timer resumes).

### 3.4 Interior team (client) duplicates
- Their kiosk prompt "번호표 뽑기" on part `KioskTicket` (prompt named `GwInteriorPrompt`, `INT/Interact.luau:98-109`) and their
  toy checkup prompts would double ours. → Client `Prompts` locally sets `Enabled = false` (and keeps it off) on `GwInteriorPrompt`
  prompts whose `ActionText` is in Config.Interior.SuppressPrompts {"번호표 뽑기"} always, and {"키 · 몸무게 재기", "시력 검사",
  "청력 검사", "혈압 재기"} only while the local player's 검진 course is at that station (restored after).
- Their fake screens keep rewriting their labels (Interact.screenLoop / anim). → Client `Screens` overlays: for parts named
  Config.Interior.Screens {`CallBoardNo`, `WaitScreen`, `WaitMonitorText`, `KioskScreen`} under `Workspace.GwInteriorDetailLocal`
  (their SurfaceGui is `"Gw" .. partName`, Face Front, label `Text`; `INT/Kit.luau:328-363`) we disable their SurfaceGui (kept off)
  and draw ours in PlayerGui with `Adornee = part`, same Face, `ZOffset` +1. Same for the map's `SignGui` on the LED screens and
  `PrescriptionScreen` / `DoctorDesk.Monitor` / `ScaleDisplay` / `BPUnit` / `ECGUnit` (Face copied from the existing gui at runtime —
  the dump encodes Face as a codec value). Watch `DescendantAdded` (their rooms rebuild on stream in/out). If none of their parts
  exist, the map screens alone carry the info.
- Their "진료 중" lamp reads character `GwTreating` → we set `GwTreating = true` on the patient during consult + treatment
  (same meaning as Health's; only the interior reads it) and clear it on every exit path / respawn.
- Never parent GUIs or parts under map parts; our world objects live in `Workspace.GwangalliClinic` (server) and
  `Workspace.GwClinicLocal` (client props: ticket paper, 처방전, 약봉투, thermometer, IV drip particles).

### 3.5 NPCs and beds
- Law/Hospital builds its walk grid from server parts (`Law/Hospital:144-232`; CanCollide=false parts are passable): all our server
  parts are CanCollide=false, CanTouch=false, CanQuery=false (anchors) → no rerouting. Our staff rigs stand behind counters /
  in corners away from SPOTS (pharmacist behind the counter at ~(-545, 8.9, 304); 주사실 nurse between the beds at ~(-472, 9.6, 312);
  창구 staff on the two desk chairs; 검진 staff on the checkup desk chair). systems.json rule: keep 2 studs clear around static staff.
- Their ER patient goes to spot `treat` (-478, 308) ≈ TreatBed2; nurses use `treat_bed` (-468, 309) ≈ TreatBed1 side; EMS teleports held
  patients to `TRANSIT` (-465.3, 9.6, 304.5) (TreatBed1 foot). → Bed allocator: prefer TreatBed1 for IV unless a character with
  `GwEmsPatient` is within 10 studs of TRANSIT, then TreatBed2; ExamBed for 주사; CheckupBed for ECG. Reservation table +
  `Seat.Occupant` check; ward beds are never reserved.
- Static rigs: we don't move or reparent them. Gestures are client-side C0 layers via `Anim.rig` (Health posed the doctor once,
  `HEALTH:524-548`; the nurse arm tween only runs in the legacy choreography, which our takeover makes unreachable). The syringe
  props (`GwProp="syringe"`) are toggled locally (LocalTransparencyModifier) for the injection shot.

### 3.6 Money / economy
- Single fee path: legacy prompts are off, so a visit is never charged twice. Totals for the recommended plan equal
  `HS.fee(kind)` (owner tuning stays in G.HEALTH); vitamin / checkup prices = `G.HEALTH.services.*.fee`.
- Treatment before payment (real 의원 order) → walking out unpaid: after `Config.UnpaidGrace` (60 s outside the clinic zone, or on
  leave) the bill becomes `d.health.debt` (+ our persisted mirror) and is billed by our next 수납 **and** by Health's ambulance fee
  (`HEALTH:340`) — one source of truth (d.health.debt), mirrored only for persistence.
- Payments are idempotent per bill id; amounts are server numbers; refusals are Korean messages.

### 3.7 Other
- Streaming: client code waits for map parts with timeouts and re-binds on stream-in; staff models use `ModelStreamingMode.Atomic`.
- The legacy client sheet still listens to HealthEvent; we only fire `cured / vitamin / checkup / status` (never `clinic`).
- GameplayAPI `addStats` shows its own toast; we fold the happiness change into it (label "광안 메디컬 의원") and don't repeat it.
- 광안 종합병원 ShopLife desks have their own 진료 / 계산 (Humanoid health only, no illness link). Our "lite" site adds a separate
  prompt at its 내과 desk (different anchor, `KeyboardKeyCode = F`) and never touches ShopLife.
- On-shift patients: fatigue keeps rising on shift (`HEALTH:782`). The 접수 screen warns "근무 중이에요 · 퇴근하고 진료받으면 피로가 안
  쌓여요" (no forced endShift; ctx.endShift is not public).
- Jobs teleport detector (`Jobs:1304-1318`, > 160 studs) is irrelevant (our moves are < 20 studs, Seat:Sit).

---------------------------------------------------------------------------------------------------

## 4. Add-on design

### 4.1 Files (only the allowed paths)

```
src/ReplicatedStorage/GwangalliClinicShared/
  init.luau        contract: NAMES (remotes / folders / attributes), S.now(), validation (S.int/S.str/S.oneOf), S.mask(name) "홍*동",
                   S.won, S.clock(), JSON encode/decode (pcall), step ids + Korean labels, Config/Medical/Billing/Sites re-export
  Config.luau      owner tunables (Korean comments): Enabled, TakeOverLegacy, PersistHealth, waits, fees/shares, 야간 가산, plans,
                   beds, stations, pass perks, staff looks, interior names, reach radii, rate limits
  Medical.luau     pure content per illness kind + healthy tiers: 상병명 / KCD 코드, symptom ids & Korean labels, doctor / nurse /
                   pharmacist lines, plan templates, medicines (generic names, 용법), vitals model, checkup grading, advice text
  Billing.luau     pure: bill items for a visit (진찰료 초진/재진, 야간 가산, 주사료, 처치료(수액), 검사료, 약제비, 미납금), 공단/본인 split
                   for display, receipt rows, rounding to 100원
  Sites.luau       site table: "gwangan" (map paths + fallback world positions from §1.3) and "general" (광안 종합병원 lite:
                   GwB_HospitalDept discovery by ShopLifeKey)
src/ServerScriptService/GwangalliClinic/
  init.server.luau boot order: shared → Bridge.wait (≤ 60 s) → Store → Site → Net → Queue → Visit → Checkup → Ward → Board →
                   Bridge.takeOverLegacy → State.Active = true; any failure before the takeover leaves the legacy clinic untouched
  Bridge.luau      every integration of §1.2 (Health module/API, Profiles, GameplayAPI, remotes, passes, clock), legacy takeover,
                   health mirror restore/save, charge(player, amount, label, method)
  Store.luau       DataStore GwangalliClinic_v1 (UpdateAsync, retries, memory fallback, autosave 90 s dirty-only, save on leave/close,
                   skip when Profiles.persistent(player) == false)
  Site.luau        resolve map parts → Workspace.GwangalliClinic { Anchors (invisible parts + attributes), Staff (Anim.buildR15
                   rigs) }, bed registry / reservation, zone test (inside the clinic box + floor), anchor distance checks
  Net.luau         ClinicRequest (RemoteFunction) / ClinicEvent (RemoteEvent) in GwangalliClinicShared.Remotes; token buckets per
                   class; payload validation; pcall'd handlers → {ok=false, code, message} in Korean
  Queue.luau       ticket numbers (per server, starting 20–40), virtual patients (busy feel), 창구 1/2, consult queue (진료실 1 +
                   optional 대진), pharmacy queue; call announcements; State attributes Board / Call / Rx
  Visit.luau       per-player state machine (§4.6), timers, consult script, plans, treatment choreography, billing, pharmacy,
                   medication course, exits (cancel / walk-out / leave / respawn / KO / collapse)
  Checkup.luau     2F 건강검진 코스: stations, locks, measurements (server numbers), grade, report, persistence
  Ward.luau        입원실 wake-up (GwCollapse true→false while on a ward BedSeat, or KO ward placement) → 퇴원 수속 offer + debt payment
src/StarterPlayer/StarterPlayerScripts/GwangalliClinic/
  init.client.luau boot: wait shared + State.Active (≤ 90 s), ctx {K, Layout, Anim, S, net, bus, modal()}, modules
  Net.luau         RF call with timeout (8 s), ClinicEvent bus, "hello" on start + after respawn
  Prompts.luau     LOCAL ProximityPrompts on server anchors, text per visit step (only the next action is shown), suppress the
                   interior's duplicate prompts (§3.4)
  Tracker.luau     visit tracker card (Layout topRight), call banner (bottomCenter) + chime, guidance Beam/arrow to the next anchor,
                   dose chip (next to the health chip row)
  Desk.luau        kiosk screen, ticket paper, 접수 문진표, 수납 영수증 + 결제수단, 처방전 paper, 퇴원 수속 card
  Consult.luau     doctor DialogBox, camera framing, vitals panel, minigames (청진 호흡 / 인후 "아~" / 체온), diagnosis card, plan picker
  Treat.luau       injection timing bar + press hold, IV progress ring + drip FX + "눈 붙이기", lying pose for any character with
                   attr GwClinicPose = "lie" (local Anim pose on others too)
  Pharmacy.luau    조제 대기, 복약지도 card, 약봉투 handover, first dose
  Checkup.luau     course checklist, station minigames (키·몸무게 / 혈압 / 시력 Landolt C / 청력 beep / 심전도), 결과지 modal
  Screens.luau     world displays (overlays §3.4) rendering State.Board / Call / Rx + per-patient monitors; 딩동 sound at the LED
  Staff.luau       client animation of staff rigs (ours + 김선생 / 박선생) from State acts: pose / gesture / look / emote, props
  Chart.luau       진료 기록 sheet (history, last 결과지, meds left) opened from the tracker
  Ui.luau          shared builders on the GwangalliUI kit (document paper, receipt table, step chips, vitals tiles)
```

### 4.2 Remotes and payloads

`ReplicatedStorage.GwangalliClinicShared.Remotes.ClinicRequest:InvokeServer(op, payload)` → `{ ok, code?, message?, ... }`
(payload must be a table; every id is checked against a whitelist; numbers clamped; distance and step checked server-side):

| op | payload | when (step) | reply |
|---|---|---|---|
| `hello` | `{}` | any | `{ok, visit=VisitView?, chart=ChartView, meds=MedsView?, open={night, pass}, debt}` |
| `ticket` | `{kind="clinic"|"checkup"}` | no visit; ≤ 9 studs from Kiosk anchor (or 2F desk for checkup) | `{ok, visit}` (ticket n, ahead, eta) |
| `register` | `{purpose="ill"|"tired"|"checkup"|"general", symptoms={ids ≤ 6}}` | `calledDesk`, ≤ 10 from the called 창구 | `{ok, visit}` |
| `enter` | `{}` | `calledConsult`, ≤ 14 from ConsultSeat anchor | `{ok}` (server Seat:Sit, GwTreating = true) |
| `answer` | `{q=id, a=id}` | `consult` | `{ok, line}` (flavour only) |
| `exam` | `{kind="temp"|"stetho"|"throat"|"bp", quality=0..1}` | `consult`, in order | `{ok, vitals}` |
| `plan` | `{id="A"|"B"|"C"}` | `consult` after diagnosis, ≥ Config.MinConsult s | `{ok, visit}` (next = treat / billing) |
| `treat` | `{action="start"|"press"|"nap"|"stop", quality=0..1?}` | `toTreat` (≤ 8 from the bed anchor) / `treating` | `{ok, progress?}` |
| `pay` | `{bill=billId, method="card"|"cash"}` | `billing` / `pharmPay` / ward bill, ≤ 10 from 창구 / pharmacy | `{ok, receipt}` or `insufficient` with balances |
| `pharmacy` | `{action="submit"|"collect"}` | `toPharmacy` / `ready` | `{ok, visit}` |
| `dose` | `{}` | meds course, dose due | `{ok, meds}` |
| `cancel` | `{}` | before treatment (free) / after (bill → debt) | `{ok}` |
| `checkup` | `{action="start"|"station"|"finish", station=id, result={...}}` | course | `{ok, measure?, report?}` |
| `vitals` | `{anchor="lobbyBP"|"checkBP"}` | walk-up 자동 혈압계 (no visit), 1 / 20 s | `{ok, sys, dia, pulse}` |
| `chart` | `{}` | any | `{ok, history, report, meds}` |

Rate classes: ui 5/s burst 12 (hello/answer/exam/chart), act 2/s burst 4 (ticket/register/enter/plan/treat/pharmacy/dose/cancel/checkup),
money 0.8/s burst 2 (pay; plus a per-bill idempotency key).

`ClinicEvent:FireClient(player, payload)`: `{kind="visit", visit}` · `{kind="call", to="desk"|"consult"|"treat"|"billing"|"pharmacy",
window?, number, text}` · `{kind="line", who="doctor"|"nurse"|"desk"|"pharm"|"check", name, text, choices?}` · `{kind="vitals", ...}` ·
`{kind="progress", what="iv"|"dispense", t0, seconds}` · `{kind="bill", bill}` · `{kind="rx", rx}` · `{kind="done", summary}` ·
`{kind="report", report}` · `{kind="meds", meds}`.

Shared state for every client: `ReplicatedStorage.GwangalliClinicShared.State` (Configuration created by the server), attributes:
`Active` (bool), `Call` (JSON `{seq, n, to, win, name, t}`), `Board` (JSON `{serving={w1,w2,consult,pharm}, waiting={{n, name, st}…≤8},
counts={desk, consult, treat, pharm}, doctor="김선생"}`), `Rx` (JSON `{cooking={n…}, ready={n…}}`), staff acts `Act_doctor`,
`Act_nurse`, `Act_nurse2`, `Act_desk1`, `Act_desk2`, `Act_pharm`, `Act_check` (`"listen|<userId>|<t>"`), bed states `Bed_<id>`
(`"<userId>|iv|<t0>|<seconds>"` or ""), monitor text `Mon_consult` (masked chart line for the doctor's monitor). Names are masked
(`홍*동`), never full names.

### 4.3 Data schema (server)

Per-player session (`Visit`): `{ id, ticket, step, purpose, kind?, symptoms, window?, room?, bed?, plan?, dx?, vitals?, bill?, rx?,
unpaid, startedAt, stepAt, lastInZone, flags = {night, pass, revisit} }`.

VisitView (client): `{ id, ticket, step, stepLabel, purpose, ahead, eta, window?, room?, bed?, dx? = {name, code, desc, cause},
plan? = {id, name, items}, bill? = BillView, rx? = RxView, night, pass }`.

BillView: `{ id, kind="desk"|"pharmacy"|"ward", rows = {{label, amount, note?}}, subtotal, insurer (공단부담, display), self
(본인부담), debt, total, night, methods = {card = bankBalance, cash = cashBalance} }`.

RxView (처방전): `{ no, issued, patient (masked), dxCode, doctor="김선생", items = {{name, dose, times, days}}, note }`.

Store `GwangalliClinic_v1` / `u_<UserId>` (≤ 4 KB):
```
{ v = 1,
  chart = { no = "GA-0012345", first = unix, visits = n, last = unix, lastDx = "cold" },
  history = { { t, kind, dx, plan, paid, where = "gwangan" } ... ≤ 12 },
  meds = { kind, name, total = 3, taken = 1, nextAt = unix, until = unix } | nil,
  report = { t, grade = "A".."D", height, weight, bmi, bp = {s, d, p}, vision = {l, r}, hearing = {l, r}, ecg = "정상 동리듬",
             fatigue, risk, ill = kind? } | nil,
  mirror = { illness = {kind, since, online}?, risk, debt, t } }
```
Restore on join: wait `GwangalliProfileReady`, then if `mirror.illness` and no current illness → write it into `d.health.illness`
(kind validated by `HS.kind`, `online` kept), `debt = max(debt, mirror.debt)`, `risk = mirror.risk`, then `Health.onLoaded(player)`
(attributes + walk speed) and a toast "아직 감기 기운이 남아 있어요 🤧" / "광안 메디컬 미납 진료비 n원이 있어요". Mirror is refreshed
every 30 s and on every clinic event (so a crash loses ≤ 30 s), saved with the store.

### 4.4 Medical content (Medical.luau) — real-world grounded

| kind | 진단 (상병) | KCD | 주증상 (preselected) | 권장 계획 (= G.HEALTH cure text) | 약 (3 doses) |
|---|---|---|---|---|---|
| cold 감기 | 급성 비인두염 (감기) | J00 | 콧물 · 기침 · 인후통 · 미열 | 해열 주사(근육주사) + 감기약 3일분 | 해열진통제, 항히스타민제, 진해거담제 · 하루 3번 식후 30분 |
| ache 몸살 | 상세불명의 바이러스 감염 (몸살) | B34.9 | 근육통 · 오한 · 고열 · 두통 | 해열 주사 + 근육이완제 | 소염진통제, 근육이완제 |
| gastritis 위염 | 급성 위염 | K29.1 | 속쓰림 · 구역감 · 복통 · 식욕부진 | 위장약 처방 + 수액(전해질) | 위산분비억제제, 위점막보호제 |
| burnout 번아웃 | 탈진 (번아웃) | Z73.0 | 무기력 · 불면 · 집중력 저하 · 두통 | 영양 수액 + 휴식 처방 | 비타민 B 복합제 · "오늘은 알바 쉬기" |
| healthy, fatigue ≥ 50 | 피로 누적 | R53 | 피곤함 · 어깨 결림 | 영양주사 / 고농도 영양수액 / 상담만 | — |
| healthy, fatigue < 50 | 이상 소견 없음 | — | — | 상담만 (진찰료) | — |

Vitals model (server, deterministic per visit + small noise): 체온 healthy 36.5 + f·0.004; cold 37.8, ache 38.6, gastritis 37.2,
burnout 36.8; 혈압 sys = 112 + f·0.28 (+8 ill), dia = 72 + f·0.16; 맥박 66 + f·0.24 (+12 ill); SpO₂ 98 (97 cold). Diagnosis "cause"
line uses the real state: `"최근 {jobName} 근무로 피로도가 {f}까지 쌓였어요. 면역력이 떨어진 상태예요."` (job from `d.job.id`,
night → "밤샘 근무"). Doctor lines: 김선생 ("어디가 불편해서 오셨어요?", "숨 크게 들이쉬고… 내쉬세요", "아~ 해 보세요", "주사 한 대 맞고
약 3일 드세요. 오늘은 푹 쉬시고요."), nurse ("엉덩이 주사예요. 힘 빼세요~ 따끔합니다", "5분 정도 꾹 눌러 주세요", "수액은 30분
정도 걸려요. 불편하면 벨 누르세요"), 원무과 ("신분증 확인할게요", "처음 오셨어요?", "진료비 n원입니다. 카드로 하시겠어요?"), 약사
("042번 환자분 약 나왔습니다", "하루 세 번, 식후 30분에 드세요. 졸릴 수 있으니 운전은 조심하세요").

### 4.5 Fees (Billing.luau, defaults; all in Config)

- 진찰료: 초진 5,500 / 재진 4,000 (visit within 30 days in our chart). 야간·공휴일 가산 30% on 진찰료 when clock ≥ 18 or < 9
  (sign says 09:00~22:00; after 22:00 the clinic stays open as "야간 당직 진료" so a night-shift patient is never stranded).
- Recommended plan total = `HS.fee(kind)` (초진, day): consult 5,500; 약제비 = round100(PharmShare[kind] × (fee − 5,500)) paid at
  the 약국; 처치료 = the rest paid at 수납. Shares: cold 0.6, ache 0.4, gastritis 0.35, burnout 0.15 →
  cold 5,500 + 주사 3,800 + 약 5,700 = 15,000; ache 5,500 + 11,700 + 7,800 = 25,000; gastritis 5,500 + 19,200 + 10,300 = 35,000;
  burnout 5,500 + 33,600 + 5,900 = 45,000.
- Plan B "약만 처방" = consult + 약제비 (cheaper; cure when the first dose is taken, fatigue relief × 0.5).
  Plan C "+ 영양수액 추가" = A + round100(0.8 × services.vitamin.fee) (extra fatigue −vitamin, 45 s IV).
- Healthy + tired: 영양주사 = services.vitamin.fee (30,000, 비급여, no 진찰료) fatigue −vitamin (40); 고농도 영양수액 =
  round100(1.6 × vitamin fee) = 48,000, fatigue −60, 체력 +20, 45 s lying; 상담만 = 진찰료, risk × 0.5, advice.
- 건강검진 코스 = services.checkup.fee (10,000).
- 미납금 = `d.health.debt` added as a row at the next 수납 (and still collected by Health's ambulance fee).
- Receipt display (realism): 급여 rows show 공단부담금 = self × 7/3, 본인부담금 = self; 비급여 rows (영양주사/수액) 100% 본인.
- 편의 패스 ("qol"): waits × 0.5 (Config.PassPerks), shown as a ⚡ badge; no price change.

### 4.6 Visit state machine (server-authoritative)

```
(none) ─ticket→ waitDesk ─(virtual ahead served)→ calledDesk ─register→ waitConsult ─(queue)→ calledConsult ─enter→ consult
consult ─plan A/C (inject)→ toTreat(exam) ─treat start→ treating ─done→ toBilling
consult ─plan C/IV or gastritis/burnout→ toTreat(treat1|2) ─start→ treating(iv) ─done|stop→ toBilling
consult ─plan B / 상담만→ toBilling
toBilling ─(call to 창구)→ billing ─pay→ toPharmacy (if rx) | done
toPharmacy ─submit→ dispensing (8 s) → ready ─collect + pay→ done (first dose offered)
any ─cancel / KO / collapse / respawn / leave / out of zone > UnpaidGrace→ cancelled (bill → debt if treatment happened)
```
Server timers: virtual desk 4 + 5·ahead s; consult wait 6 + 8·ahead s + real queue (× 0.5 with the pass); MinConsult 14 s;
injection 6 s; IV 30 s (plans with 수액) / 45 s (고농도), "눈 붙이기" ×3 speed (min 12 s, screen fades); dispensing 8 s.
Call re-announced every 20 s; a called patient who doesn't come in 60 s is "보류" (moved back one place, then cancelled after 2 holds).
One visit per player; one patient per consult room / bed; 창구 1 + 2 serve in parallel.

Effects applied (server):
- Cure (plans A/C at treatment end; plan B at first dose): `HealthAPI:Invoke("cure", player)` → `Health.rest(player,
  G.HEALTH.fatigue.cured × planFactor)` → `GameplayAPI addStats {happiness = +5}` → `d.health.visits += 1` → fire HealthEvent
  `{kind="cured", illness=name, fee=total, status}` (existing sparkles + "완치! 🎉").
- 영양주사 / 수액: `Health.rest(player, amount)` spread over the IV (every 5 s a slice, so leaving early gives the slice earned),
  `addStats {stamina=…, happiness=+2}`, `d.health.lastVitamin = os.time()`, HealthEvent `{kind="vitamin"}`.
- 진료 itself: `d.health.risk = floor(risk × 0.5)` (상담만 path), clamps illness.online while inside (§3.3).
- Doses (meds course, 3 doses, every Config.DoseEvery = 180 s real time, window 20 min): each → `Health.rest(6)`, `risk −10`;
  last dose → `addStats {happiness=+2}`; a cold relapse ("ill" event) with doses left is told "처방약을 꼭 챙겨 드세요".

### 4.7 Player flows (step by step)

**A. 아파서 간 날 (감기, 편의점 야간 알바 후)**
1. Health makes the player ill → their existing toast + waypoint to 광안메디컬; our tracker shows "🏥 광안 메디컬 의원에서 진료받아요"
   with the walking distance.
2. Inside the AutoDoor, the kiosk prompt "번호표 뽑기" (local prompt on the Kiosk anchor). Kiosk UI: [🩺 진료 접수] [💉 주사·수액]
   [📋 건강검진 (2층)] [🧾 수납·처방전]. Ticket paper slides out of the slot (client prop); card "번호표 042 · 대기 2명 · 약 1분".
   Lobby LED + waiting TV now list "042 홍*동 · 접수 대기".
3. Virtual patients 040, 041 are called (LED "🔔 041 → 2번 창구", chime). Player sits on a bench (optional).
4. "🔔 딩동 — 042번 홍*동님, 1번 창구로 와 주세요" (banner + LED + TV + beam to 창구 1). Prompt "접수하기" at 창구 1.
   원무과 직원 dialog: 신분증 확인 ✓ → 초진 (chart created "등록번호 GA-…") → 방문 목적 (아파요) → 문진표: chips preselected from the
   real kind (콧물 · 기침 · 인후통 · 미열), the player can toggle; if on shift, the warning line. "진료실 앞에서 잠시만 기다려 주세요."
5. Queue: TV "진료실 1 · 내과 김선생 — 진료 중 038 / 대기 042 홍*동". Called: "042번 홍*동님, 진료실 1번으로 들어오세요".
6. Prompt "진료실 들어가기" on the patient seat → seated, camera frames doctor + patient, GwTreating on (door lamp "진료 중").
   Doctor turns to the player (Act listen), monitor shows "홍*동 · 초진 · 콧물/기침 · BT —".
   Dialogue: "어디가 불편해서 오셨어요?" (choices from the symptoms) → "체온 잴게요" (thermometer prop, count-up to 37.8 ℃) →
   "숨 크게 들이쉬고… 내쉬세요" (hold-to-inhale ring × 3, stethoscope gesture) → "아~ 해 보세요" (tap) → diagnosis card:
   "급성 비인두염 (감기) · J00 / 최근 편의점 야간 근무로 피로도가 91까지 쌓였어요. 면역력이 떨어진 상태예요." →
   plan cards: A "주사 + 감기약 3일분 (권장) 15,000원 · 완치 · 피로 −50" / B "약만 처방 11,200원 · 약 먹으면 완치 · 피로 −25" /
   C "주사 + 영양수액 39,000원 · 완치 · 피로 −90 · 45초".
7. A → "옆 처치 침대로 가세요, 박선생님이 주사 놔 드릴 거예요." Prompt "주사 맞기" at the ExamBed → seated, nurse turns, syringe
   shows; timing bar "힘 빼세요~" (tap in the green zone), "따끔!" (tiny camera shake), "5초간 꾹 눌러 주세요" hold. Server: cure +
   fatigue −50 + 행복 +5 → existing "완치! 🎉" sparkles; walk speed back.
8. "수납 창구에서 계산하고 처방전 받아 가세요" → 창구 call → prompt "수납하기" → 진료비 계산서·영수증 (진찰료 5,500 · 야간가산
   1,650 · 주사료 3,800 · 합계 / 공단 · 본인) + [💳 체크카드 (통장 n원)] [💵 현금 (n원)] → paid → 처방전 paper (2부) animation.
9. Pharmacy prompt "처방전 내기" → PrescriptionScreen "조제 중 042" (DispensingMachine act) → 8 s → "042번 약 나왔습니다" → 복약지도
   card (약 3종, ☀️🌤️🌙 식후 30분, 3일분) → 약제비 5,700 → 약봉투 handover (give/receive emotes) → "지금 한 번 드실래요?" → dose 1.
10. Summary card: "감기 완치 · 피로도 91 → 41 · 총 17,150원 · 오늘은 무리하지 마세요"; dose chip "💊 2/3 · 3분 후".

**B. 피곤해서 (healthy, fatigue 78)**: kiosk [💉 주사·수액] → 창구 → shortened consult ("피로가 많이 쌓였네요" + BP reading) →
plan 고농도 영양수액 → 주사실 TreatBed (our nurse 최선생, IV drip, lying pose, "눈 붙이기") → fatigue drops in slices → 수납 (비급여
48,000) → done ("개운하다 💉").

**C. 건강검진 코스 (2F)**: kiosk [📋 건강검진] or 2F desk prompt "검진 접수" → fee 10,000 at the 2F desk → checklist:
① 신장·체중 (stand on Scale; height rod slides to the head; height from the avatar's head height, weight from height + 근력; BMI)
② 혈압 (sit, cuff inflates, gauge counts; numbers from fatigue/illness) ③ 시력 (stand on EyeLine; Landolt C: 4-direction buttons,
5 rows shrinking → 1.2/1.0/0.8…; real result = performance) ④ 청력 (enter the booth; beeps L/R at random gaps, press when heard;
reaction accuracy → 정상/경도 저하) ⑤ 심전도 (lie on CheckupBed, ECG waveform; illness → "동성빈맥") → back to the desk →
결과지 modal (A4 style, stamp "광안 메디컬 의원 건강검진센터"): grade A 정상 / B 정상(경계) / C 주의 (피로 누적, risk %) / D 질환 의심
(ill → "1층 내과 진료를 받으세요" + [바로 진료 접수] creates a 진료 visit skipping the kiosk). Server: `lastCheckup`, visits+1,
HealthEvent `checkup` (status + advice), happiness +3 once per 24 h; report saved and shown in the chart.

**D. 쓰러짐 → 입원실 → 퇴원 수속**: Health's collapse wakes the player on a ward bed with the 응급 진료비 charged or as debt. Ward
detects GwCollapse true→false while seated on a ward BedSeat (or KO ward placement) → nurse line "정신이 드세요? 응급실로
실려 오셨어요" + card: 응급 진료비 n원 (미납 n원) [1층 원무과에서 수납] → guidance to 창구 → 퇴원 수속 bill → pay → debt 0.

**E. 미납 / 이탈**: treatment done but the player leaves the zone → tracker "진료비를 내지 않았어요 · 60초 안에 돌아오세요" → after 60 s
(or on leave): bill → `d.health.debt` (+ mirror) + toast "미납 진료비 n원 · 다음 방문 때 청구돼요". Next 수납 (or the ambulance fee) collects it.

**F. 여러 명**: real tickets interleave with virtual ones; 창구 1/2 parallel; one consult at a time (others see "진료 중 042",
the TV lists masked names in order); if the consult queue ≥ Config.SecondDoctorAt (3) and the 2F desk is free, 대진 의사 이선생
(our rig) opens 진료실 2 (2F checkup desk + patient chair) for the next patient.

**G. 광안 종합병원 (lite)**: if `GwB_HospitalDept` desks exist (ShopLifeKey hospital_internal / hospital_reception / hospital_inject /
hospital_pharmacy), Site adds anchors there and the same Visit engine runs without kiosk/screens/virtual queue: prompt "내과 진료
(질병·피로)" at 내과 → dialog consult → 주사 at 주사실 desk (no bed) → 수납 at 원무과 → 약국. Off by Config.Sites.general.Enabled
until verified in studio (cheap: Visit/Billing/Medical are site-agnostic; only anchors differ).

### 4.8 UI screens (client, GwangalliUI kit, Korean, mobile/PC/gamepad)

1. Kiosk screen (K.Modal, 4 big buttons ≥ 56 px, gamepad-selectable), ticket card.
2. Visit tracker (topRight card): ticket no, current step chip, "다음: 1번 창구 · 12m", progress dots 접수 → 진료 → 처치 → 수납 → 약국,
   tap → Chart sheet; 취소 link.
3. Call banner (bottomCenter, 4 s, chime "딩-동" = electronicpingshort ×2 at speeds 1.0 / 0.8) + haptic.
4. 접수 window: K.DialogBox (원무과 직원) + 문진표 sheet (K.Chip multi-select, K.Segmented 방문 목적), 미납금 pill, 근무 중 warning.
5. Consult: DialogBox (김선생) + vitals tiles (체온 / 혈압 / 맥박 / SpO₂ with K.countUp) + minigames (hold ring, tap) + diagnosis card
   (상병명 · 코드 · cause line · fatigue/risk bars) + plan cards (price, effect pills, time).
6. Treatment: timing bar + hold button (shot); IV ring with drip count, "눈 붙이기" / "그만 맞기".
7. 진료비 계산서·영수증 modal (paper style, rows, 공단/본인, 합계), 결제수단 buttons with balances, insufficient → "통장 n원 · 현금 n원"
   and [ATM 위치 안내] (waypoint toast).
8. 처방전 paper (교부번호, 상병코드, 처방 의약품 table, 용법) and 약봉투 / 복약지도 card.
9. Dose chip + "💊 약 먹기" button (cup pose for 1.5 s).
10. Visit summary card (before → after: 질병, 피로도, 급여 배율 0.2 → 1.0).
11. 건강검진: checklist card, station panels, 결과지 modal.
12. Chart sheet (K.BottomSheet sheetRight): 등록번호, history rows, last 결과지, meds left.
13. 퇴원 수속 card.
Modal etiquette: HideGwangalliHUD on our ScreenGui, `K.blur`, touch controls disabled while a sheet is open; all buttons
`K.pressable`; gamepad: `GuiService.SelectedObject` set to the primary button on open; ESC/B closes non-critical sheets.

### 4.9 World / staff

Server `Workspace.GwangalliClinic` (Folder):
- `Anchors` (Parts, Transparency 1, CanCollide/CanTouch/CanQuery false, Anchored, Size 2×4×2, attrs `Kind`, `Site`, `Label`):
  `Kiosk`, `Win1`, `Win2`, `ConsultSeat`, `ExamBed`, `TreatBed1`, `TreatBed2`, `Pharmacy`, `CheckDesk`, `CheckScale`, `CheckBP`,
  `CheckEye`, `CheckEar`, `CheckECG`, `Consult2` (optional), `LobbyBP`; CFrames from the map parts at boot (fallback = §1.3 positions).
- `Staff` (Models from `Anim.buildR15`, ModelStreamingMode Atomic, names = display): 원무과 김주임 / 이주임 (seated on the desk chairs,
  navy vests + lanyard), 간호사 최선생 (주사실, scrubs + cap), 약사 정약사 (white gown + name badge behind the counter), 검진센터 한선생
  (2F desk), optional 대진의 이선생. Attributes `ClinicRole`. No CollectionService tags (never `HospitalStaff`).
Client: `Staff.luau` animates every staff rig from `State.Act_*` (pose sit/clipboard/hands_front, gesture talk/listen/typing, look at
the patient, emote give/receive/bow/beckon), including 김선생 / 박선생 (local C0 layers via Anim.rig; syringe props toggled locally).
`Workspace.GwClinicLocal` holds client props: ticket paper, 처방전, 약봉투, thermometer, cotton ball, IV drip ParticleEmitter
(attached to the map IVBag via Attachment in our own part welded nowhere — a part positioned at the bag), Beam guidance.

### 4.10 Testing plan (for the implementer)
- Offline: pure modules (Billing totals = HS.fee for each kind/day/night/revisit; Medical vitals ranges; state machine transitions
  with mocked Bridge) under `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/lib/rbx.luau` copies.
- Studio (one run): inject shared + server + client, use `ServerStorage.GwangalliHealthAPI:Invoke("makeIll", player, "cold")` and
  `setFatigue` to drive states; verify legacy prompts disabled, anchors placed on the right parts, LED overlay, consult seat, cure
  (Player.Illness "" and WalkSpeed), bill/ledger (Money/Bank attributes), debt on walk-out, checkup report; screenshot lobby LED,
  consult, IV bed, receipt.
