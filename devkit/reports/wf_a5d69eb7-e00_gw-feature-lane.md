# gw-feature-lane (wf_a5d69eb7-e00)

- status: completed
- failed agents (never finished, usually the usage limit): build:passes, fix:passes, review:passes:correctness, review:passes:experience, test:passes

## research:passes

The design doc is finished at /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/passes/research.md (725 lines). This was research only: no studio run, and no source files written.

1. **Which code to read.** The real v7 code is in `scratchpad/bld/eff/` (place scripts plus the v7 add-on zip). `bld/src` alone is missing Arms, KOSystem, GamePassConfig, GwangalliStore and GwangalliPassPerks.
2. **Pass system already exists.** `GamePassConfig`, `GwangalliPassPerks` (sets player attribute `GwPass_<key>`), `GwangalliStore` and the phone "R$" app all work this way. Our 3 passes copy that convention. When a pass Id is above 0, we add it to `GamePassConfig` at runtime on both server and client, and the R$ app lists it. `ProcessReceipt` belongs to `Arms/SpecialBox`; we only use game passes, so we never touch it. Other purchase-finished handlers filter their own Id, so there is no conflict.
3. **No place script edits.** Everything is a runtime hook:
   - wrapped functions: `Spawn.template`, `Jail.begin`, `KO.koHelp`, and on the client `Api.status` / `Api.callCar`;
   - existing server APIs: `GwangalliVehiclesAPI`, `GwangalliGarageAPI`, `GwangalliGameplayAPI`, `GwangalliArmsAPI`, `GwangalliCrimeBus`;
   - runtime additions to shared tables (vehicle specs, `GamePassConfig`, the client's KO help timer).

   There is one optional patch, `GwangalliPasses_Phone.patch`, for a native phone dock icon.
4. **Cars today.** You can already call your own cars anywhere with "차 부르기" (the "🚗 내 차" button, `/차`, or the call-car flow). They spawn on the nearest road within 260 studs, with an 8-second cooldown. The fastest car is the G80 "플래그십" at 165 km/h. There are no supercars: `GwangalliCarModels` is missing in v7, so the 14 showroom models spawn as basic kit cars.
5. **Pass #1 premium cars.** Four new car types: 하이퍼카 (our own part-built body), 슈퍼카 (CarBuilder "Sports" body), VIP (G80 base) and 오프로더 (Tucson base, lifted).
   - Each has its own handling spec, set on both server and client.
   - They spawn through the vehicles API with `force` and an exact spot next to the player ("바로 내 옆").
   - They are never added to the Garage's saved car list, so the 3-car cap and Garage saving are untouched.
   - "출장 정비" (remote repair) uses Garage `setCondition` plus a normal charge through the gameplay money API, at the 정비소 price.
   - They also appear in the existing 차 부르기 list.
6. **Pass #3 shorter jail.** Wrap `Jail.begin` and halve the sentence, minimum 15 s. Bail scales correctly.
7. **Pass #3 shorter KO wait.** Players never die; they get knocked out and wait for 119.
   - The "병원으로 이송" button appears at 10 s instead of 20 s (wrapper on the server, timer halved on the owner's client).
   - Our loop sends the owner to hospital at 47 s instead of 95 s (75 s hard cap instead of 150 s), but only when no ambulance has been dispatched, so 119 players don't lose their job.
   - Roblox respawn time is halved too.
8. **Pass #3 phone black market.** Each owner gets a server-only shop `dealer:gwphone_<UserId>` anchored on their own character, opened through the Arms API. Clients can't open `dealer:` shops, so nobody can use someone else's.
   - The existing weapon shop screen opens, and the phone closes itself.
   - Same prices and stock as the 총기상 (tier 1-2 for everyone, tier 3-4 mafia only). There is no 방탄복 item; we add none, to keep combat balance.
   - The shop's own checks still block trading: police within 45 studs, SWAT, gunfire, being chased, KO, or sitting in a car.
9. **Pass #4 KO effects.** KO events come from the crime bus (`KnockedOut`, `NpcKnockedOut`, `OfficerDown`). There are six effect styles, rate-limited and sent only to players within 220 studs. Built-in assets only.
10. **Pass #4 plates.** Plates are `PlateFront` / `PlateRear` with a SurfaceGui; `GS.applyPlate` writes them.
    - The custom plate is checked for length and characters, text-filtered, and optionally unique across players.
    - It is applied to every owned or premium car when it spawns, in 6 styles, including the old green Korean plate and an EV blue plate.
11. **Pass #4 neon nickname.** An animated gradient name tag in each viewer's own screen, with the default Humanoid name hidden while it's on, and works with `GwangalliLabelDeclutter`. Chat uses `TextChatService.OnIncomingMessage`, which nothing in the place sets today. It can't be shared, so we mark it as ours and back off if another add-on got there first.
12. **Phone app.** One "👑 VIP" icon with tabs 차고 · 블랙마켓 · 꾸미기. The grid is full on landscape phones (10 apps in 5 columns × 2 rows), so the icon goes in the dock as a 5th slot. The app is our own screen laid exactly over the phone's screen.
13. **Remotes:** one RemoteFunction (12 actions) and one RemoteEvent, with rate limits and per-action checks. A server API `GwangalliPassesAPI` (`has`, `owned`, `catalog`, `summon`, `plateOf`) is for the dealer agent, which already plans to call `"has"`.
14. **Saving:** DataStore `GwangalliPasses_v1` (key `u_<UserId>`) plus `GwangalliPlates_v1` for unique plates. Test switches: workspace attribute `GwPassesStudioTest` in Studio, and `GwPassesAdminFree` for admins.
15. **Risks that need a decision or a test:**
    - The hypercar is set to 220 km/h, but the driving code has only been tested up to 165 km/h. It needs a temp-studio test.
    - Buying 편의 패스 while already in jail only applies from the next arrest, because the remaining time isn't reachable from outside.
    - Pass Ids are 0 ("판매 준비 중") until the owner enters the real numbers. Suggested prices: 799 / 349 / 299 R$.

Files to create (all under the allowed paths): `src/ReplicatedStorage/GwangalliPassesShared/` (8 modules), `src/ServerScriptService/GwangalliPasses/` (13 files), `src/StarterPlayer/StarterPlayerScripts/GwangalliPasses/` (15 files), and the optional `patches/GwangalliPasses_Phone.patch`.
