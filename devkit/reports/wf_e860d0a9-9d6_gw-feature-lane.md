# gw-feature-lane (wf_e860d0a9-9d6)

- status: completed
- failed agents (never finished, usually the usage limit): build:clinic, fix:clinic, review:clinic:correctness, review:clinic:experience, test:clinic

## research:clinic

I wrote the design doc to /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/clinic/research.md (545 lines). Nothing was run in the temp studio; the doc's §4.10 has the test plan.

Summary (30 lines):
1. **Biggest finding: health state is lost on rejoin.** `Profiles.sanitize` (`PROF:149-337`) keeps only whitelisted keys and `health` is not one of them. So illness, 미납금 (debt), visits and risk reset every time a player rejoins; only fatigue survives (it is in `stats`). Today a rejoin is a free cure and wipes debt. Our add-on keeps its own `GwangalliClinic_v1` store, mirrors `{illness, risk, debt}` into it and restores it on join, then calls `Health.onLoaded`.
2. **Health module.** We require `ServerScriptService["GwangalliGameplay"]` (the Folder) `.Health` directly, the same way Jobs does. We use `Health.status`, `Health.rest(player, amount)`, `Health.findBed`, `Health.isIll` and `Health.fatigue`.
3. **Health API.** `ServerStorage.GwangalliHealthAPI` op `cure` is the plain cure (no fee, no choreography); `setFatigue` is the fallback. We must pass the Player instance, because an unknown id falls back to the first player in the server (`HEALTH:848`).
4. **Profiles direct writes.** `Profiles.get` is used only for `d.health` fields the API cannot reach: debt, risk, visits, lastVitamin/lastCheckup, and capping `illness.online`.
5. **Money.** `GwangalliGameplayAPI` `spend` pays cash first. For the card/cash choice I designed account-specific debits through `G.ledger`, then syncing the Money/Bank attributes, `ProfileChanged` and `Notify` the same way `ctx.ledger` does. The `spend` op is the fallback.
6. **Reusing existing effects.** We fire the existing `HealthEvent` with kind `cured` / `vitamin` / `checkup` so the current client sparkles ("완치! 🎉") play. We never fire `clinic`, which would open the old sheet.
7. **The illness kinds already define the treatment.** Each kind's `cure` text (e.g. 감기 "주사 한 방 + 감기약 3일분") becomes our recommended plan. The plan's total equals `HS.fee(kind)` (진찰료 + 처치료 + 약제비), so the owner's G.HEALTH prices still control the balance.
8. **Legacy prompts.** The two `HospitalPrompt` prompts get disabled at runtime (the KaraokePlus pattern), but only after our server has fully booted. If anything fails, the old clinic keeps working.
9. **Collapse risk.** A patient could hit the 600 s collapse timer mid-visit. While they are inside the clinic with a registered visit, we cap `illness.online` at 600 − 180 s.
10. **Interior team (client-only) overlaps.** T_clinic adds a fake kiosk "번호표 뽑기", a fake 호출 board, fake wait monitors and toy checkup prompts. We locally disable their duplicate prompts and cover their screens with our own SurfaceGuis in PlayerGui (their gui is named `"Gw"..partName`).
11. **Their "진료 중" lamp** reads the character's `GwTreating` attribute, so we set it during consult and treatment.
12. **Map parts mapped.** Kiosk, desk windows 1/2, lobby LED, waiting TV, consult seat, ExamBed, TreatBed1/2 (with IV bags), pharmacy counter and screen, and the 2F checkup stations (Scale, BP, EyeLine, HearingBooth, CheckupBed/ECG). Ward beds are never reserved. StreamingEnabled is on.
13. **Bed conflicts.** NPC spots and the EMS handover point (TRANSIT) sit next to TreatBed1/2. The bed allocator works around them, and all our parts are non-colliding so the NPC walk grid is unaffected.
14. **Files.** Shared: `init`, `Config`, `Medical`, `Billing`, `Sites`. Server: `init`, `Bridge`, `Store`, `Site`, `Net`, `Queue`, `Visit`, `Checkup`, `Ward`. Client: `init`, `Net`, `Prompts`, `Tracker`, `Desk`, `Consult`, `Treat`, `Pharmacy`, `Checkup`, `Screens`, `Staff`, `Chart`, `Ui`.
15. **Remotes.** `ClinicRequest` (RemoteFunction) with ops hello / ticket / register / enter / answer / exam / plan / treat / pay / pharmacy / dose / cancel / checkup / vitals / chart, plus `ClinicEvent` (RemoteEvent). A shared `State` Configuration replicates the call board, masked names (홍*동), staff actions and bed states.
16. **Visit steps.** 번호표 → 창구 호출 → 접수·문진 → 진료 대기 → 진료실 → 주사 or 수액 → 수납 → 약국 → done. Timers, distance and step checks are all on the server; minigames are flavour only.
17. **Real-world content.** KCD 상병 codes (J00, B34.9, K29.1, Z73.0, R53), vitals computed from real fatigue/illness, a diagnosis line that names the cause (job, fatigue level), an itemised receipt with 야간 가산 and 공단/본인 split, and a 처방전.
18. **After the visit.** A three-dose medication course with real effects (fatigue −6 and risk −10 per dose). Walking out unpaid turns the bill into `d.health.debt`, which our next 수납 or the ambulance fee collects.
19. **건강검진 코스 (2F).** Real measurements (height, BMI, blood pressure, Landolt C eye test, hearing test, ECG) and a graded result sheet (A–D). A "D" result links straight into a 진료 visit.
20. **Other flows.** 퇴원 수속 after a collapse or KO ward wake-up; 편의 패스 (`qol`) halves waits, which fits the owner's "패스없이" wording; a lite version for 광안 종합병원 using its `GwB_HospitalDept` desks, off until verified.
21. **New staff** built with `Anim.buildR15`: 원무과 ×2, 주사실 간호사, 약사, 검진센터 직원, and an optional second doctor (opens a 2F 진료실 2 when 3 or more are waiting for the doctor). They are animated client-side through `Anim.rig`.
