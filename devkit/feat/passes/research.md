# GwangalliPasses: research and design

Three Robux game passes for 광안리 (v7), shipped as one add-on:
- **#1 프리미엄 차고** (PremiumGarage): pass-only premium vehicles + a remote garage on the phone.
- **#3 편의 패스** (Convenience): jail and KO / respawn waits cut by 50 %, plus a 블랙마켓 app on the phone.
- **#4 과시 패스** (Flex): KO finish effects, a custom plate, a neon nickname (over the head and in chat).

The user asked for passes 1, 3 and 4 only ("1번3번4번만 기능 구현해줘 대화 판단해서 알잘딱"). Pass #2 is not built.

Path prefixes:
- `EFF/` = `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/eff/`. This is the v7 place scripts with the v7 add-on zip (`v7all/gen/addons.json`) overlaid by `bld/eff.py`, so it is the code that actually runs in v7. `bld/src` alone is missing every add-on (Arms, KOSystem, PassPerks, GamePassConfig, Store, ...).
- `REPO/` = `/home/user/-/`
- `SCR/` = `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/`

Runtime facts marked **[probe]** come from the dealer agent's live temp-studio probe of v7 (`SCR/feat/dealer/probe_out.txt`).

---------------------------------------------------------------------------------------------------

## 0. Summary of decisions

1. **No existing place script is edited.** Every behaviour change is a runtime hook from our own Script / LocalScript. There are three kinds:
   - **Wrap a module-table function** that other code calls through the table (`Spawn.template`, `Jail.begin`, `KO.koHelp`, client `Api.status` / `Api.callCar`).
   - **Call public server APIs**: `GwangalliVehiclesAPI`, `GwangalliGarageAPI`, `GwangalliGameplayAPI`, `GwangalliArmsAPI`, `GwangalliCrimeBus`.
   - **Add entries to shared module tables at runtime**: `VS.Specs` / `VS.Drivable`, `GamePassConfig`, the client copy of `A.KO.SELF_HELP_AFTER`.

   One OPTIONAL patch, `patches/GwangalliPasses_Phone.patch`, turns our phone icon into a native dock app. Without it the icon is injected at runtime.
2. **Pass ownership follows the existing convention.** We set player attribute `GwPass_<key>` (`GwangalliPassPerks` / `GwangalliStore` read it). The pass Ids live in our config (0 = 판매 준비 중). When an Id is > 0, we also add the pass to `ReplicatedStorage.GamePassConfig` at runtime, on the server and the client, so the phone **R$ app** and the side **부스트 상점** list it for free.
3. **Premium vehicles are new VehicleKinds** (`gw_super`, `gw_hyper`, `gw_vip`, `gw_offroad`). Each has its own handling spec, is spawned through `GwangalliVehiclesAPI "spawnOwned"`, and uses a template we supply by wrapping `Spawn.template`. Ownership = owning the pass. They are never written into the Garage's `d.cars`, so the 3-car cap, Garage saving, sell / loan and the dealer stay untouched.
4. **Waits are halved per player.**
   - **Jail**: wrap `Jail.begin` and halve `episode.seconds`, with a minimum of 15 s.
   - **KO**: wrap `KO.koHelp` so a pass owner may ask for the hospital after half of `SELF_HELP_AFTER`. Our own loop sends the KO'd pass owner to the hospital at half of `EMS_WAIT` / `EMS_TOTAL` when no ambulance is on the way. The client copy of `A.KO.SELF_HELP_AFTER` is halved for the local owner so the button shows up on time.
   - **Roblox respawn**: a pass owner gets their character back at half of `Players.RespawnTime`.
5. **The 블랙마켓 app reuses the existing Arms weapon shop end to end.** That covers the stock, prices, money, nonces, inventory and the full-screen `WeaponShopUI`. We register a per-player phone shop `dealer:gwphone_<UserId>` anchored on the owner's HumanoidRootPart (`GwangalliArmsAPI "setShopState"`) and open it with `GwangalliArmsAPI "openShop"`. The `dealer:` prefix means no client can open someone else's phone shop. The shop still refuses on its own street checks (police near, SWAT, gunfire, chased, KO, cuffed, seated).
6. **Flex effects are server-decided and client-rendered.**
   - **KO**: KO events come off `ServerStorage.GwangalliCrimeBus` (`KnockedOut`, `NpcKnockedOut`, `OfficerDown`). The server picks the attacker's chosen effect and fires it to the clients near the victim.
   - **Plates**: the custom plate is filtered (TextService) and applied server-side with `GS.applyPlate` to every owned or premium car the owner calls.
   - **Neon nickname**: it is a player attribute. Every client draws its own BillboardGui in PlayerGui (Adornee = Head) with an animated UIGradient. Chat gets a gradient name prefix through `TextChatService.OnIncomingMessage`, which nobody in the place sets today.

---------------------------------------------------------------------------------------------------

## 1. Existing integration points (exact)

### 1.1 Game passes, store and money

**`ReplicatedStorage.GamePassConfig`** (`EFF/ReplicatedStorage/GamePassConfig.luau:1-12`) is a plain table keyed by pass key:
```lua
-- Store = true: 폰 "R$" 앱(로벅스 상점)에 진열 (Order 순). Perk = "income" | "speed": ServerScriptService.GwangalliPassPerks가 효과를 건다
	Mafia = { Id = 2027126370, Name = "마피아 패스", Job = "Mafia", Store = true, Order = 4, Title = "마피아", Desc = "..." },
	Income = { Id = 2025338384, Name = "수익 1.2배", Perk = "income", Store = true, Order = 1, ... },
	Speed = { Id = 2026040372, Name = "속도 1.2배", Perk = "speed", Store = true, Order = 2, ... },
```
(Police 2025752373, SWAT 2026604361, EMS 2027198352 also.)

**`ServerScriptService.GwangalliPassPerks`** (`EFF/ServerScriptService/GwangalliPassPerks.luau`):
- `storeKeys()` re-reads `Passes` on every call (`:18-26`).
- `grant()` sets `player:SetAttribute("GwPass_" .. key, true)` (`:38-50`) and does nothing else for an unknown Perk.
- `check()` uses `UserOwnsGamePassAsync` with 3 retries (`:52-67`).
- It has its own `PromptGamePassPurchaseFinished` handler that loops over `storeKeys()` (`:84-93`).

→ If we add our keys to the SERVER `GamePassConfig` table early, PassPerks also grants `GwPass_<ourKey>`. That is harmless and redundant, because we check ourselves.

**`ReplicatedStorage.GwangalliStore`** (client, `EFF/ReplicatedStorage/GwangalliStore.luau`):
- `Store.list(group)` keeps only entries with `def.Store and tonumber(def.Id)`. The group is `"boost"` when `def.Perk` is set, otherwise `"job"` (`:18-32`).
- `Store.owned(key)` = `LocalPlayer:GetAttribute("GwPass_"..key) == true` (`:66-68`).
- `Store.buy(key)` = `PromptGamePassPurchase` (`:70-77`).
- `Store.changed(fn)` listens to `GwPass_*` attributes (`:83-89`).

Consumers:
- **Phone R$ app** (`EFF/StarterPlayer/StarterPlayerScripts/GwangalliPhone/Apps/Robux.luau:83-102`) builds its rows lazily, the first time the app opens.
- **Side 부스트 상점 panel** (`EFF/StarterPlayer/StarterPlayerScripts/GwangalliPassShop.luau:77`) uses `Store.list("boost")` at top level and builds its rows when the script starts.

→ Our client injects its entries into the client `GamePassConfig` table as the first thing it does. The R$ app then always lists them. The side panel lists them only if our LocalScript ran first; it is an extra, not something we depend on.

**Other pass users** (do not conflict; each filters its own Id):
- `MafiaService.luau:482,544`
- `SwatService.luau:65,479`
- `Law/Cop.luau:99,1003`
- `Law/Crimes.luau:721`
- `Arms/WeaponPermissionSystem.luau:139,252`
- `Play/Ems/Pass.luau:64,112`

Several `PromptGamePassPurchaseFinished` connections already exist, and adding one more is fine. **`MarketplaceService.ProcessReceipt` is owned by `Arms/SpecialBox.luau`** (the header says only one per place). We only use game passes, so we never touch ProcessReceipt.

**Studio test convention** (`MafiaService.luau:486-488`):
```lua
local function studioFree(): boolean
	return RunService:IsStudio() and workspace:GetAttribute("GwMafiaStudioTest") == true
end
```
→ Ours: `RunService:IsStudio() and workspace:GetAttribute("GwPassesStudioTest") == true`. Admins get the passes free too, when `workspace.GwPassesAdminFree == true` and Player attribute `GwangalliAdmin == true`. That attribute is written by `GwangalliLiveOps.luau:345` from `GwangalliLiveConfig.ADMINS`, the game owner and group rank 254+ (`:19-20, :323`).

**Money: `ServerStorage.GwangalliGameplayAPI`** (BindableFunction, `EFF/ServerScriptService/GwangalliGameplay.luau:478-496`):
```lua
 api.OnInvoke = function(op, player, amount, label)
  if op == "balance" then return d and d.cash or 0, d and d.bank or 0 end
  if op == "spend" then ... return ctx.spend(player, math.floor(amount), label or "건물 · 생활")
  elseif op == "earn" then ... return ctx.ledger(player, "bank", math.floor(amount), label or "생활 수익")
```
- `ctx.spend` pays from ONE account only: cash first, then bank (see the dealer research §1.2).
- Labels containing 환불/반환/취소 are not counted as income.
- Player attributes `Money` (cash) and `Bank` mirror the balances live.

### 1.2 Vehicles

**Shared contract: `ReplicatedStorage.GwangalliVehiclesShared` (VS)** (`EFF/ReplicatedStorage/GwangalliVehiclesShared.luau`):
- Remotes folder `GwangalliVehiclesRemotes` holds `Drive` (RemoteEvent) and `CallCar` (RemoteFunction: "call" / "dismiss" / "status") (`:32-36`).
- Car-model attributes `VS.Attr` (`:42-61`): `VehicleKind`, `DriveRig` (JSON), `DriveOwner`, `DriveDriver`, `DriveLabel`, `DrivePlate`, `DriveCarId`, `DriveOwnedCar`, `DriveCondition`, `DriveTestDrive`, `NoDrive`.
- `VS.Limits` (`:87-100`): MaxPlayerCars 1, **CallCooldown 8**, GlobalCallGap 0.5, **CallRadius 260**, IdleDespawn 300, FarDespawn 700.
- `VS.Specs[kind]` (`:116-152`) holds the six kit kinds plus taxi / police / scooter. Top speeds: compact 100, sedan 135, **luxury 165**, suv 128, van 118, truck 102, scooter 88 km/h.
- `VS.Drivable = { sedan, luxury, compact, suv, van, truck }` (`:158`). `VS.ParkedDrivable` adds taxi / police / scooter (`:163`).
- `VS.spec(kind)` returns `Specs[kind] or Specs.sedan` (`:176-178`).
- `VS.freeSpawnAllowed` is true only with the dev switch, or for an admin while `GwAdminFree` is on (`:183-190`).

**The six kit kinds are clones of PARKED map cars** (place.bin counts): sedan = `Car_Sonata` (41), compact = `Car_Kia Ray` (32), suv = `Car_Tucson` (30), truck = `Car_Porter II` (26), van = `Car_Carnival` (19), **luxury = `Car_Genesis G80` (9)**, taxi = `Car_Taxi` (8), police = `Car_Police` / `PoliceCar_광안1..3`, ambulance = `Car_Ambulance` (2), scooter = `Car_Scooter` (116).

**There are no hypercars or supercars anywhere.** `ServerStorage.GwangalliCarModels` is missing in v7 **[probe]**, so the 14 `GS.MODELS` showroom cars spawn as kit cars of their kind. `ReplicatedStorage.CarBuilder` can build a procedural "sports" body (`EFF/ReplicatedStorage/CarBuilder.luau:13-50`, `CarConfig.Cars.Sports`: "스포츠카"). `ServerStorage.GwangalliCarAdapter` shows how to strip such a body to the drive contract (`EFF/ServerStorage/GwangalliCarAdapter.luau`), but nothing calls it.

**Server spawn: `ServerScriptService.GwangalliVehicles` (Folder) → `Spawn` (ModuleScript)** (`EFF/ServerScriptService/GwangalliVehicles/Spawn.luau`). The Folder sits next to a Script of the same name, so find it by class.
- API header `:28-37`; binding `:945-1003`:
  ```lua
  --   "spawnOwned" (player, spec, opts?) -> ok, msg, model     spec = { id, kind, model?, color (Color3), colorId, plate, cond, dirt, label, rental, testDrive }
  --        opts = { near: Vector3?, cframe: CFrame? (ground frame), radius?, force? (skip the cooldown), seat? }; msg = "label|meters"
  --   "despawn" (player, reason?) -> ok   "current" (player) -> Model?   "seat" (player, model)   "occupants" (model)   "status" (player)
  ```
- `Spawn.template(kind)` (`:183-228`) works in this order:
  1. the `templates[kind]` cache;
  2. the first PARKED map model under `workspace.Gwangalli` with `VehicleKind == kind` (not rigged / traffic / NoDrive);
  3. a model tagged `GarageDisplayCar` with `GarageKind == kind`;
  4. `fallbackCar(kind)`, a contract box car (`:120-166`).

  It is a **module-table function**, and `prepare()` calls it through the table: `local model = Spawn.template(o.kind):Clone()` (`:558`). **That makes it our hook point.**
- `prepare()` → `decorate()` → `Rig.rig()` (`:532-569`). `decorate` (`:397-409`) does `GS.applyColor(model, color, colorId)` (paint = every part matching the colour of `BodySide` / `CabSide` / `Hood`) and `GS.applyPlate(model, plate)`.
- `build()` (`:572-616`) uses `o.cframe` first if `clearAt` passes, then the road lanes within `o.radius or CallRadius`. It sets `DriveOwner`.
- `Spawn.callOwned(player, spec, opts)` (`:676-736`):
  - refuses unless `VS.Drivable[spec.kind]` (`:678`) → **we add our kinds to the SERVER `VS.Drivable`**;
  - `checkCallLimits(player, o.force == true)` (`:618-644`: refuses while driving, during the 8 s cooldown unless forced, or when someone else sits in the old car);
  - replaces the player's previous called car;
  - sets `DriveOwnedCar = true`, `DriveCarId = spec.id`, `DriveCondition`, `DriveDirt` and `DriveLabel`;
  - calls `Cars.register(rec, {owner, ownerOnly = true, carId, label})`. Only the owner may drive; passengers may ride.
- Spawned cars are parented to `workspace.GwangalliPlayerCars` (`:91-103`).

**Rig and physics come from `VehicleKind`.**
- `Rig.rig` reads `local kind = model:GetAttribute(VS.Attr.Kind); local spec = VS.spec(kind)` (`EFF/ServerScriptService/GwangalliVehicles/Rig.luau:136-139`) and stores `kind` in the `DriveRig` JSON (`:333-345`).
- The driver's client does `local spec = VS.spec(rig.kind)` (`EFF/StarterPlayer/StarterPlayerScripts/GwangalliDrive/Drive.luau:168`).
- The server's anti-speed check uses the rig record's spec: `limit = VS.studs(rec.spec.topKmh) * 1.6 + 25` (`EFF/ServerScriptService/GwangalliVehicles/Cars.luau:885`).

→ A new kind needs `VS.Specs[kind]` on **both** peers, and the template's `VehicleKind` must be that kind. Then rig, controller and speed limit are all consistent with no JSON rewriting.

**Garage: `ServerScriptService.GwangalliGameplay` (Folder) → `Garage`** (`EFF/ServerScriptService/GwangalliGameplay/Garage.luau`; full analysis in `SCR/feat/dealer/research.md` §1.2).
- `ServerStorage.GwangalliGarageAPI` (`:1266-1318`):
  - `"cars"(player)` returns views;
  - `"status"(player)`;
  - `"give"(player, kind|modelId, grade?, colorId?)`;
  - `"setCondition"(player, id, cond)` sets `car.cond` and the live model's condition, then pushes the list (no `markDirty`; it is saved on autosave / leave);
  - `"request"(player, op, payload)` runs the validated `handle()`.
- `OPS.call` drops `near` (`:1104-1146`), so Garage cars always spawn on the nearest lane.
- `opCall` (`:709-746`) calls `vapi("spawnOwned", player, {id, kind, model, color, colorId, plate, cond, dirt, label, rental})` and then `track()` (condition / wear).
- Plates come from `uniquePlate(cars)` (`:500-518`), format `GS.plate()` = `"부산%02d%s %04d"` (`EFF/ReplicatedStorage/GwangalliGarageShared.luau:365-371`). Rentals use a 허 plate (`Garage.luau:781-782`); test drives use "시승 1234" (`:881`). `GS.sanitizeCar` keeps a plate of at most 24 bytes (`GarageShared:405`).
- `GS.MAX_CARS = 3` (`GarageShared:110`) is a global constant, so per-player extra slots cannot be done cleanly. We don't need them: premium cars live outside `d.cars`.
- `GS.JOB_VEHICLES` (`GarageShared:102-108`) = parcel_truck, police, swat, **limo (luxury base, black)**, **armored (suv base)**. These are job vehicles spawned through `ServerStorage.GwangalliEvents.SpawnJobVehicle`. Police, ambulance and taxi belong to their jobs; **premium kinds must never be `police` / `ambulance` / `taxi`** (Jail's ride-car search, NPC police and Taxi read those kinds).
- `GS.applyPlate(model, text)` (`GarageShared:608-620`) writes every TextLabel under `PlateFront` / `PlateRear` and sets `DrivePlate`.
- Map plates are Part `PlateFront` / `PlateRear` 1.74 × 0.37 studs → SurfaceGui (PixelsPerStud 44) → TextLabel (text such as "27서 8478"), checked on `Car_Genesis G80`, `Car_Sonata` and `Car_Kia Ray` in place.bin.
- Who reads plates: `Law/Cop.luau:714` (player-cop plate lookup reads `DrivePlate`), `Taxi.luau:440-443`, the client `GwangalliWorld/TrafficModels` (traffic only).

**Fuel** (`EFF/ServerScriptService/GwangalliGameplay/Fuel.luau:82-131`) drains `d.fuel[DriveCarId]` for any called car with `DriveOwnedCar == true`, and the controller cuts the engine at `DriveFuel` 0. Our premium ids (`gwp_<key>`) therefore get a fuel gauge and need refuelling. That is the intended realism; no change.

**Client entry points for "my car"** (no phone app; the phone has no vehicle app):
- **HUD button "🚗 내 차"** (`EFF/StarterPlayer/StarterPlayerScripts/CarClient.luau:1-27`, ScreenGui `GWIntegratedCarShortcut`, top-right) calls `require(PlayerScripts.GwangalliDrive(Folder).Api).open("callcar")`.
- Chat `/차` and `/car` (`GwangalliDrive/Api.luau:250-261`, TextChatCommand).
- The Features flow `LocalPlayer.GwangalliFeaturesOpen:Fire("callcar", args)` (`GwangalliFeatures/CallCar.luau`).
- The garage desk prompt opens Sheet "mine". The Garage public opener is `LocalPlayer.GwangalliGarageOpen:Fire({tab = "buy"|"showroom"|"mine"|"rent"})`.

**The 차 부르기 sheet** (`GwangalliDrive/UI.luau:671-790`) renders `st.cars` views: `id, label, glyph, color (GS colour id), plate, cond, band, rental, loan, towed`.
- Its "부르기" button emits `"call"`, and the handler is `UI.on("call", function(kind) ctx.Api.callCar(kind) end)` (`Drive.luau:521-523`).
- The sheet data comes from `ctx.UI.setSheetStatus(Api.status())` (`Api.luau:204,215,235`).
- Both `Api.status` and `Api.callCar` are **module-table functions** of `GwangalliDrive/Api` (`Api.luau:109,134`), so they can be wrapped on the client.

**Car interiors** (our team, `REPO/src/StarterPlayer/StarterPlayerScripts/GwangalliCarInterior/Styles.luau:3`) pick a style by `InteriorStyle` attribute > `CarModel` / model name > `VehicleKind`. The keys are sonata, sonata_taxi, g80, tucson, ray, carnival, porter, solati. → Our templates set `InteriorStyle` ("g80" for the VIP and supercars, "tucson" for the offroader).

### 1.3 Jail

`ServerScriptService.GwangalliGameplay.Law` (ModuleScript) → `Jail` (child ModuleScript), `EFF/ServerScriptService/GwangalliGameplay/Law/Jail.luau`:
- The sentence is computed in `Law.arrest` and passed in `episode.seconds` (`EFF/ServerScriptService/GwangalliGameplay/Law.luau:704-718`):
  ```lua
	local episode = { sev = sev, fine = fine, paid = paid, owed = owed, seized = seized, crimes = crimesText, seconds = seconds, band = band.label, by = info.by, cop = info.cop, surrender = info.surrender == true }
	...
	if Law.children.Jail then
		Law.children.Jail.begin(player, s, episode, info)
	end
  ```
  → **`Jail.begin` is called through the module table** (`Law.children[name] = require(child)`, `Law.luau:1161`), so we can wrap it.
- `Jail.begin(player, s, episode, info)` (`Jail.luau:658-704`): `local seconds = episode.seconds; j = {total = seconds, pending = seconds, ...}`. The arrest push / notify shows `seconds`.
- `intoCell` (`:491-512`) starts the clock at the cell: `j.endsAt = serverNow() + j.pending` and `player:SetAttribute(LS.Attr.Jail, j.endsAt)`. The attribute is `LawJail`, in server time; the client shows 남은 시간 from it.
- Rejoin resumes from `d.law.jail.left` (`Jail.resume`, `:706`; saved at `:963-971`), which is already the halved remainder.
- Limits: `Law.JAIL_MIN = 30`, `Law.JAIL_MAX = 300` (`EFF/ReplicatedStorage/GwangalliLawShared.luau:287-288`). `sentenceFor` clamps to them (`:295-305`). `bailFor(sev, left, total)` scales with `left / total` (`:307-311`), so halving both keeps the bail ratio.
- Player cops also end in `Law.arrest` → `Jail.begin` (handover, `Law/Cop.luau:750-770`). Police shooting (`GwLethalDown`) means a KO in "arrest" mode, then `Law.arrest`.
- `GwangalliGameplay/Crime` (the old jail / police) is **not** in `FEATURE_MODULES` (`GwangalliGameplay.luau:498`) and is inactive.

### 1.4 KO / "respawn" waits

Nobody dies in this game: 0 HP = KO (`Arms/KOSystem.luau:1-25`). The wait is the KO screen until 119 / transport.
- `A.KO` lives in `ReplicatedStorage.GwangalliArmsShared` (`EFF/ReplicatedStorage/GwangalliArmsShared.luau:276-296`):
  ```lua
	SELF_HELP_AFTER = 20, -- s down before "병원으로 이송" can be pressed
	EMS_WAIT = 95, -- s without an ambulance at the scene -> fallback transport (fade)
	EMS_TOTAL = 150, -- hard cap
	FEE_FIRST_AID = 8000, FEE_HOSPITAL = 20000,
  ```
- `KO.down` (`KOSystem.luau:775-865`) creates `rec = { t0 = os.clock(), since = serverNow(), mode = "ems", ... }` in a module-private `records` table. It sets character attributes `GwKO = true`, `ArmsKO = state`, `ArmsKOUntil` (`push`, `:143-156`) and fires the bus event `KnockedOut` (`:843`).
- `tickEms` (`:592-640`): `if inc.closed or elapsed >= A.KO.EMS_TOTAL or (not atScene and elapsed >= A.KO.EMS_WAIT) then transport(rec, "fallback")`. It reads `A.KO` live, but the values are global, so they cannot be changed per player.
- `KO.koHelp(victim)` (`:1022-1029`):
  ```lua
	if not rec or rec.mode ~= "ems" or rec.busy or rec.aid or now() - rec.t0 < A.KO.SELF_HELP_AFTER then return false end
	transport(rec, "self")
  ```
  It is reached through the table: `m.on("koHelp", function(player) KO.koHelp(player) end)` (`:1227-1229`). `transport()` only spawns a thread after `setState` / `once`, so a temporary `A.KO.SELF_HELP_AFTER` override restored right after the call is safe.
- Client KO screen: `GwangalliArms/CombatUI.luau:1124` (`if ... os.clock() - ko.downAt < A.KO.SELF_HELP_AFTER then` = no button) and `:1558` (countdown). It reads the client's own `A` table, so we can halve it for the local owner only.
- Bus events for the ambulance phase: `EmsDispatched` (fired once when the incident leaves "call", `:632-634`), `FirstAidStarted`, `TransportStarted`, `Hospitalized`, `Revived` (`ArmsShared.luau:101-125`).
- Illness collapse (`GwangalliGameplay/Health.luau:304-397`) is only 3 s on the floor plus a fade: nothing to halve. Bump knockdowns are about 1-2 s (`GwangalliBumpShared` KNOCK_DUR / GETUP_DUR 0.7). A real Roblox death or reset uses `Players.RespawnTime`, which nothing in the place sets (default 5 s).

### 1.5 Black market (총기상 / Arms weapon shop)

- The dealer NPC `GwangalliGameplay/WeaponDealer` (`EFF/ServerScriptService/GwangalliGameplay/WeaponDealer.luau:1-30`) **never sells**. It hands requests to `Arms/WeaponShopSystem` (`EFF/ServerScriptService/GwangalliGameplay/Arms/WeaponShopSystem.luau`). The contract is `ReplicatedStorage.GwangalliWeaponDealerShared`.
- **Server API ops on `ServerStorage.GwangalliArmsAPI`** (`WeaponShopSystem.luau:1181-1189`; dispatcher `Arms.luau:204,306-317,434`):
  ```lua
	M.api("openShop", function(player, shopId, opts) return Shop.openShop(player, shopId, opts) end)   -- trusted request
	M.api("setShopState", function(shopId, st) Shop.setShopState(shopId, st) end)                     -- {open, reason, npcId, anchor, radius, name}
	M.api("shopState", function(shopId) return Shop.shopState(shopId) end)                             -- {open, reason}
  ```
- `request(player, shopId, opts, trusted)` (`:392-433`) checks, in order:
  - `playerReady` (`:344-362`, i.e. `Combat.canAct`: alive, not KO / cuffed / jailed / surrendering / stunned / **seated** / working);
  - `Shop.blocked` (`streetBlock`, `:295-320`: shop closed, attacked, `policeNear(anchor, 45)`, `swatNear(90)`, `gunfireNear(70 / 8 s)`, plus `playerBlock`: grudge, `PoliceChase`);
  - distance to `anchorPos(shop)` ≤ radius + 12 (trusted).

  It then opens a 180 s session (`A.SHOP.SESSION_S`) and sends Event `{kind = "shop", op = "open", shopId, name, tab}`.
- `anchorPos` (`:194-207`) uses `shop.anchor` (BasePart / Model / Vector3 in workspace), then the NPC model.
- **`fromClient` refuses every `dealer:`-prefixed id** (`:446-450`: "a dealer's shop opens only through his talk"). So a phone shop named `dealer:gwphone_<UserId>` can only be opened by the server.
- For `dealer:` ids, `request` stores `dealerId`, and `closeSession` / `buy` call `ctx.weaponDealer.closed(player)` / `.note(player, dealerId, "trade")`. Both are tolerant of unknown ids (`WeaponDealer.luau:2057-2083`: `byId[dealerId]` is nil, so they return false).
- `setShopState` calls `removeFallback()` (`:471-478`). That removes the studio-only trade point at `A.SHOP.FALLBACK_POS` once ANY shop registers, so we register lazily, on first use.
- Purchases are client Query `"catalog"` / `"buy"` / `"ammo"` (`:627-822`). Each re-runs `tradeCheck` (session, `Shop.blocked`, `playerReady`, distance ≤ radius + 12) and charges through `ctx.spend` BEFORE `Inv.give`, with a refund on failure, a nonce and a per-player lock.
- Client `GwangalliArms/WeaponShopUI` opens only on the server's "open" event (`:4-6`). It closes when the player walks `WALK_AWAY = 24` studs from where it opened (`:47`). Its ScreenGui `GwangalliArmsShop` carries `HideGwangalliHUD`, so **the phone closes itself** while it is open (`GwangalliPhone/Phone.luau:1737-1768`).
- Stock (`EFF/ReplicatedStorage/GwangalliArmsShared/WeaponData.luau:85-350`):

  | Tier | Guns (price 원) | Access |
  |---|---|---|
  | 1 | M1911 85,000 · M686 120,000 · MP5 165,000 · M870 190,000 | everyone |
  | 2 | Desert Eagle 260,000 · MAC-10 240,000 · M1014 380,000 · M14 450,000 | everyone |
  | 3 | UMP45 580,000 · M4A1 650,000 · AA-12 820,000 · SR-25 1,100,000 | mafia only |
  | 4 | PPSh-41 900,000 · M249 1,400,000 · M24 2,500,000 | mafia only |

  Ammo boxes cost 6,000-25,000. There is **no purchasable 방탄복** (body armour exists only as the SWAT cosmetic in `SwatService.luau:28,125`). We add none: it would change combat balance.
- Inventory: `d.inventory` hidden items `gw_gun_<id>` / `gw_ammo_<id>` (`ArmsShared.luau:373`).

### 1.6 KO / kill events (for finish effects)

`ServerStorage.GwangalliCrimeBus` (BindableEvent, `Arms.luau:176-190,433`): `Fire(name, payload)`, where `payload.userId` is filled in from `payload.player`.
- `KnockedOut` (`KOSystem.luau:843` via `once`) is a PLAYER victim: `{ player = victim, pos, mild, mode, kind = byKind ("player" | "npc" | "officer" | "env"...), by = attacker UserId (players) or NPC id, weapon, move }`.
- `NpcKnockedOut` (`MeleeCombatSystem.luau:258-260`, `GunCombatSystem.luau:896-897`) is an NPC / pedestrian victim: `{ player = ATTACKER, id, kind ("ped" | "npc" | ...), pos, by = "melee" | weapon = id }`.
- `OfficerDown` (`KOSystem.luau:1139`) is a police officer victim: `{ player = ATTACKER?, id, kind = o.unit or "police", pos }`.
- `Revived` / `Hospitalized` / `KOArrested` end the victim's KO.

### 1.7 Name tags and chat

- Player overhead names use **the default Humanoid display** (nothing sets `DisplayDistanceType` on player humanoids; only NPC rigs get None: `GwangalliNPCLooks.luau:1240`, `GwangalliAvatarPool.luau:518-520`, `Club.luau:592`).
- Extra tags on players:
  - **`GwB_TitleTag`** (server BillboardGui on Head, StudsOffset (0, 3.4, 0), MaxDistance 60: the Royal tier and title, `EFF/ServerScriptService/GwangalliBuildings/Royal.luau:79-115`);
  - **`GwFriendTag`** (client, on friend NPCs, `GwangalliStreetLife/Friends.luau:74`).
- Chat bubbles stand on top of tags named in `LIFT_TAGS = { "NameTag", "PlayTag", "MiniGameNameTag", "GwFriendTag", "GwB_TitleTag", "Tag", "StreetLifeChip" }` (`GwangalliBumpShared.luau:486`). That lookup searches the person's own model, so a tag of ours placed in PlayerGui is not found. We keep our tag low (StudsOffset ≈ 2.4), where the default name sits.
- **`GwangalliLabelDeclutter`** (`EFF/StarterPlayer/StarterPlayerScripts/GwangalliLabelDeclutter.luau:1-30`) parks overlapping BillboardGuis. Owner hooks are attributes on the BillboardGui: `GwLabelClass = "named"`, `GwNoDeclutter`, `GwLabelFocus`. Unknown guis without a class are never touched. → Our neon tag sets `GwLabelClass = "named"` and `GwLabelFocus = true`.
- **Chat = TextChatService.** `GunClient.luau:966-967` checks `TCS.ChatVersion == Enum.ChatVersion.TextChatService`; there are TextChatCommands (`Api.luau:252`) and `DisplayBubble` (`Coach.luau:1044`). **Nothing sets `TextChatService.OnIncomingMessage`** (grep over EFF and REPO/src). It is a single callback that cannot be read or chained, so we claim it once and mark `TextChatService:SetAttribute("GwIncomingOwner", "GwangalliPasses")`. If another add-on already set the marker, we skip chat neon (the tags still work). Legacy chat gets a degraded path (see 4.6).
- Text filtering pattern in use: `TextService:FilterStringAsync(raw, userId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()` (`GwangalliClub.luau:189-190`, `Bank.luau:1339-1345`).

### 1.8 Phone

`StarterPlayerScripts.GwangalliPhone` (LocalScript plus a sibling Folder of ModuleScripts, `EFF/StarterPlayer/StarterPlayerScripts/GwangalliPhone/Phone.luau`).
- The registry is **closed**: local `APP_META`, `GRID_APPS = { people, together, jobs, realty, taxi, shop, robux, profile, camera, settings }` and `DOCK_APPS = { call, messages, map, bank }` (`:63-86`). `Phone.launch` / `GwangalliPhoneOpen` only open ids in `APP_META` (`:2128-2141`).
- Hierarchy: `PlayerGui.GwangalliPhone` (ScreenGui, DisplayOrder 30, `Enabled` toggles with open / close, `:1592-1654`) → `Device` (`:707`) → `Screen` (`:718`, ClipsDescendants) → `Home` (`:724`) → `Grid` (UIGridLayout) / `Dock` (UIGridLayout, FillDirectionMaxCells 4). App roots live in `Screen.Apps` (`:784`).
- Layout (`applyHomeLayout`, `:957-1080`): 4 columns. On short (landscape-phone) screens with more than 2 rows it switches to 5 columns, so **the 10-app grid is completely full on landscape phones**. The dock cell width = `floor((innerW - 8) / 4)` (`:1048`). Re-run on resize.
- Icon cells (`appIcon`, `:469-509`): TextButton "App_<id>" → Icon (gradient tile + gloss + glyph) + Label; `K.pressable`.
- Any enabled ScreenGui with attribute `HideGwangalliHUD = true` closes the phone (`:1737-1768`). Opening the phone again: `LocalPlayer.GwangalliPhoneOpen:Fire(appId?)`.
- UI kit `ReplicatedStorage.GwangalliUI` (K, `EFF/ReplicatedStorage/GwangalliUI.luau:1-30`): tokens (`K.Color` cyan / magenta / gold on navy glass, `K.Grad.bridge`), `K.Card` / `K.Button` / `K.Segmented` / `K.Toggle` / `K.Modal` / `K.BottomSheet` / `K.toast`, `K.pressable`, `K.Glyph(id)` (built-in ids only; else emoji), `K.MIN_TAP`, `K.reduced()`, `K.tier()`.

### 1.9 Other context

- The dealer add-on (another agent, `src/*/GwangalliCarDealer*`, not in the repo yet) plans an optional hook: entries with a `pass` key call `ServerStorage.GwangalliPassesAPI:Invoke("has", player, key)` (`SCR/feat/dealer/research.md:377`). **We provide that BindableFunction.**
- Our team's GwangalliBuildingInterior hides some map furniture locally. That is irrelevant here: we never parent to map parts, and our world FX live in our own folders.

---------------------------------------------------------------------------------------------------

## 2. What exists vs what the target needs

| Target | Exists | Missing (we build) |
|---|---|---|
| Pass purchase / ownership | GamePassConfig + PassPerks + GwangalliStore + R$ app (attributes `GwPass_<key>`) | three new passes (keys, Ids, desc), our own ownership check / grant, Studio / admin test grant, listing in the R$ app (runtime injection) |
| Premium vehicles | 6 kit kinds (fastest: 플래그십 G80, 165 km/h), 14 showroom models that spawn as kit cars in v7, job limo / armored | 4 pass-only vehicles with their own looks and handling (super / hyper / VIP / offroad), paints, a premium plate frame, underglow |
| Remote garage | "차 부르기" calls OWNED cars to the nearest lane within 260 studs (8 s cooldown); remote 견인 | premium fleet callable anywhere, "바로 내 옆" delivery (ground frame next to the player, no 8 s cooldown), 출장 정비 (remote repair of owned Garage cars at the normal price), premium cars also listed in the existing 차 부르기 sheet |
| Shorter jail | 30-300 s sentence, workout / 공기놀이 cuts, 보석금 | ×0.5 for pass owners (min 15 s) + "편의 패스 적용" toast |
| Shorter KO wait | self help after 20 s, fallback transport after 95 s (cap 150 s) | self help after 10 s; transport at 47 s / 75 s when no ambulance is coming; KO-screen chip; Roblox respawn ×0.5 |
| Phone black market | dealer NPC → WeaponShopSystem → WeaponShopUI (must stand next to the dealer) | phone app "블랙마켓" that opens the same shop anywhere, still under the street checks |
| KO finish effects | hit FX / KO ticks for the attacker (GwangalliArms HitFx) | world FX visible to everyone nearby, 5-6 selectable styles, preview |
| Custom plate | random "부산12가 3456" per car record | per-player vanity plate (filtered, optional uniqueness) + plate styles, applied to every owned / premium car the owner calls |
| Neon nickname | default Humanoid name, Royal title tag | animated gradient nameplate (all clients) + gradient chat name |

---------------------------------------------------------------------------------------------------

## 3. Conflicts, risks, mitigations

1. **Requiring other systems' ModuleScripts.**
   - Risk: we require `GwangalliGameplay/Law/Jail`, `GwangalliGameplay/Arms/KOSystem` and `GwangalliVehicles/Spawn` to wrap their functions. Requiring a module that its owner has not initialized yet still returns the cached table, but `init` has not run.
   - Mitigation: wait first for the owner's public signal (`ServerStorage.GwangalliVehiclesAPI` for Spawn; `ServerStorage.GwangalliArmsAPI` for KOSystem; `ServerStorage.GwangalliWeaponShop` with attribute `ArmsReady == true` for the shop; `ServerStorage.GwangalliGameplayAPI` for Law). Use `WaitForChild` timeouts of 90 s and pcall every require and every wrap. Wraps are idempotent (a sentinel field `__gwPasses = true` on the wrapper; keep `orig`). A missing hook degrades with one `warn` and the feature UI shows "준비 중".
2. **Global constants overridden "for one call"** (`A.KO.SELF_HELP_AFTER` in the koHelp wrapper).
   - Risk: another player could read the overridden value.
   - Mitigation: `koHelp` checks synchronously before it yields; set, call, restore inside one pcall. Nothing else mutates `A.KO`, and bus handlers (BindableEvent) that run immediately do not read `SELF_HELP_AFTER`.
3. **Auto-transport stealing an EMS player's job.**
   - Risk: a forced transport while a 119 player is on the way would take their work.
   - Mitigation: force it only when the KO state is `waiting` (attribute `ArmsKO`) **and** no `EmsDispatched` was seen for that victim since `GwKO` turned on. The hard cap at `EMS_TOTAL × 0.5` applies only when the state is not `firstaid` / `transport`. Never force in `arrest` mode.
4. **Fees.** Forced transport = `transport(rec, "self")`, which costs `FEE_HOSPITAL` 20,000. Without the pass the same KO would also end in fallback hospital transport at 95 s (same fee), so the pass only saves time.
5. **Phone layout.** On landscape phones the 10-app grid is full (5 columns × 2 rows). Mitigation: our icon goes in the **dock** as a 5th cell:
   - after every phone layout pass, set `Dock.UIGridLayout.FillDirectionMaxCells = 5` and the cell width `floor((dockInnerW - 8) / 5)`, re-applied on `CellSize` change;
   - mirror the icon size from `App_bank.Icon.Size`.

   The optional patch makes it native (`DOCK_APPS` + `#DOCK_APPS` cells). If the dock cannot be found, fallbacks are a `/패스` chat command and a "내 패스" card injected into the R$ app.
6. **Our app over the phone.**
   - Risk: parenting into the phone's own frames fights its navigation.
   - Mitigation: our app is **our own ScreenGui** (DisplayOrder 31, IgnoreGuiInset like the phone). Its root follows `Device.Screen.AbsolutePosition` / `AbsoluteSize` and the phone's corner radius, so it looks inside the phone.
   - Close it when `GwangalliPhone.Enabled` goes false, when the phone's home pill or another app is used (watch `Screen.Apps` children `Visible`), on back, or when `WeaponShopUI` opens (the phone closes itself then).
7. **TextChatService.OnIncomingMessage is single-owner.** Claim it only if `TextChatService:GetAttribute("GwIncomingOwner")` is nil, then set the marker. Forward nothing (it cannot be chained). Rewrite only messages that have a `TextSource` whose player carries `GwNeonName`, and only when `message.PrefixText` contains that player's DisplayName (team / system prefixes untouched).
8. **Premium kinds in other systems.**
   - Server `VS.Drivable[gw_*] = true` also allows admin free spawns (`Spawn.call`, admins with `GwAdminFree` only). Acceptable.
   - Client `VS.Drivable` stays untouched, so the client `Api.callCar` treats `gwp_*` ids as garage ids; our wrapper routes them first.
   - The car interior gets `InteriorStyle`; Fuel works by `DriveCarId`; `GwangalliCarOccupants` / `Hazard` decode the rig normally.
   - Never use the kinds police / taxi / ambulance.
9. **High speed** (up to 220-230 km/h, about 210 studs/s).
   - The server kick-back limit is `topKmh × 1.6 + 25` = 366+ studs/s, which is OK.
   - Controller stability at phone frame rates is only tested to 165 km/h, so **test `gw_hyper` in the temp studio and cap it at 220 km/h if it hops**. Keep `mass` / `E` / `U` / `z` close to luxury, and raise only topKmh / accel / brake / grip / steerHigh.
10. **Plates.** `GS.sanitizeCar` caps 24 bytes, but we never write `d.cars`. The vanity plate is applied to the spawned model only. The Garage list and the 차 부르기 sheet show the record plate unless our client wrap swaps it (it does, for consistency). Player-cop lookup (`DrivePlate`) shows the vanity plate: intended.
11. **KO FX spam** (an SMG on a crowd). Mitigation:
    - server: one effect per attacker per 1.0 s and at most 12 per server per second; send only to players within 220 studs of `pos`;
    - client: at most 3 concurrent effects, particle counts scaled by `GwangalliQuality` tier and `K.reduced()`.
12. **Ownership races.** `UserOwnsGamePassAsync` can be stale right after buying, so trust `PromptGamePassPurchaseFinished(purchased = true)` and set the attribute immediately. Re-check on join with 3 retries. While unknown, treat the player as not owning.
13. **Exploits.**
    - The client never sends prices, ids of other players' cars, or positions that get trusted. The summon position is the server's own raycast next to the server-side HRP.
    - Plate text is length / charset checked, filtered, and the filtered result must equal the input.
    - The phone shop id is server-only (`dealer:` prefix).
    - Every remote is rate limited (token bucket 8 burst, 4/s) with per-op cooldowns, and every payload is type checked.
14. **Mid-sentence purchase.** `Jail` keeps `j.endsAt` private, so buying the pass in a cell applies from the next arrest. Tell the player: "다음 체포부터 적용돼요". A KO already in progress is covered at once, because our loop measures from `GwKO`.
15. **Studio fallback trade point.** Registering a shop removes it (`removeFallback`), so register the phone shop lazily, the first time a pass owner opens the 블랙마켓.

---------------------------------------------------------------------------------------------------

## 4. Add-on design

### 4.1 Files (only under the allowed paths)

```
src/ReplicatedStorage/GwangalliPassesShared/
  init.luau          names (remotes, attributes, folders), pass keys, small pure helpers (P.owned(player, key) reads GwPass_<key>)
  Config.luau        pass Ids (0 = 판매 준비 중), titles / descs, multipliers, cooldowns, feature switches
  Cars.luau          premium catalog + handling specs + paints (pure data)
  CarBodies.luau     pure part builders: the hypercar body (wedge + glass + lamps + tyres + interior seats),
                     body kits (spoiler, splitter, side skirts, underglow, roof light bar, bull bar, big tyres), plate frame styles
                     (used by the server for templates and by the client for ViewportFrame previews)
  Plates.luau        normalize / validate (charset, length), style table (colours, fonts, frame)
  Neon.luau          palettes (ColorSequence + stroke colour + speed), rich-text gradient for chat
  KoFx.luau          effect defs (ids, names, durations, colours, sounds with built-in fallbacks)
  Lines.luau         every Korean UI string (reason → text maps)

src/ServerScriptService/GwangalliPasses/
  init.server.luau   boot: wait for systems (timeouts), start modules in order, bind remotes / API, PlayerAdded / Removing / BindToClose
  Hooks.luau         finds and wraps other systems (Spawn.template, Jail.begin, KO.koHelp), API bindable lookups, all pcall-guarded
  Ownership.luau     pass checks, Studio / admin grant, PromptGamePassPurchaseFinished, GamePassConfig injection (server table), attributes
  Data.luau          our DataStore (load / debounce save / leave / BindToClose), plate-claim store
  Net.luau           RemoteFunction "Request" + RemoteEvent "Event", token buckets, payload validation, dispatch table
  Garage.luau        premium kinds (VS.Specs / VS.Drivable), templates (ServerStorage.GwangalliPassesTemplates), summon / dismiss, paint,
                     출장 정비 (Garage API setCondition + GameplayAPI spend), status for the UI
  Waits.luau         jail halving (Jail.begin wrap), KO halving (koHelp wrap + watcher loop + bus EmsDispatched), quick respawn
  Market.luau        phone black market: per-player shop registration, open, state → Korean reason
  Plates.luau        set / clear vanity plate (validate, filter, unique claim), apply to spawned cars (GwangalliPlayerCars.ChildAdded)
  Neon.luau          set palette → player attribute GwNeonName; Humanoid name hiding while on
  KoFx.luau          crime-bus listener → effect broadcast (rate limits, range), preview
  Api.luau           ServerStorage.GwangalliPassesAPI (BindableFunction) for other add-ons (dealer)

src/StarterPlayer/StarterPlayerScripts/GwangalliPasses/
  init.client.luau   boot: StoreHook FIRST (before any yield), then Net, Specs (VS.Specs copies), modules
  Net.luau           remotes, request wrapper, event fan-out
  StoreHook.luau     client GamePassConfig injection (Id > 0 only), purchase prompts, ownership change signal
  PhoneHook.luau     dock icon "VIP" (runtime injection or patch-native mode), follows the phone's Screen rect, open / close rules
  Hub.luau           the app shell (own ScreenGui GwangalliPassesApp): header, K.Segmented tabs 차고 · 블랙마켓 · 꾸미기, locked states,
                     gamepad selection, reduced motion
  GarageTab.luau     premium cards (ViewportFrame preview), paint chips, 바로 옆 / 도로 호출, 돌려보내기, my Garage cars + 출장 정비
  MarketTab.luau     dark-web screen: connection status, 기본 · 상위 · 탄약 entries → server opens WeaponShopUI
  FlexTab.luau       plate editor (live plate preview), neon nickname palettes (live preview), KO effect list + 미리보기
  Preview.luau       client-side preview models (CarBodies + map-car clones), ViewportFrame camera orbit
  NeonTags.luau      overhead neon nametags for every player with GwNeonName (BillboardGui in PlayerGui, Adornee = Head)
  ChatNeon.luau      TextChatService.OnIncomingMessage gradient name prefix (claims the marker)
  KoFxClient.luau    renders KO finish effects (Workspace.GwPassesFxLocal), attacker stamp + camera punch
  QoLClient.luau     client A.KO.SELF_HELP_AFTER halving, KO-screen chip countdown, jail toast
  DriveHook.luau     wraps GwangalliDrive Api.status / Api.callCar: premium cars in the 차 부르기 sheet, vanity plate in rows

patches/GwangalliPasses_Phone.patch   OPTIONAL: native dock app "vip" in GwangalliPhone/Phone.luau (Korean note inside)
```

### 4.2 Names (Shared init)

- `P.REMOTES_FOLDER = "GwangalliPassesRemotes"` (ReplicatedStorage). It contains `Request` (RemoteFunction) and `Event` (RemoteEvent) and is parented last.
- `P.API = "GwangalliPassesAPI"` (ServerStorage BindableFunction).
- Pass keys: `P.KEYS = { garage = "PremiumGarage", qol = "Convenience", flex = "Flex" }`. Ownership attribute `GwPass_<key>` (same as PassPerks).
- Player attributes (server writes):
  - `GwNeonName` (palette id, "" = off);
  - `GwKoFx` (fx id, "" = off);
  - `GwVanityPlate` (text or nil);
  - `GwPlateStyle` (style id);
  - `GwPassQoLKOEnd` (server time of our forced transport, for the client chip).
- Car-model attributes (server writes on premium cars): `GwPremiumCar = <car key>`, `InteriorStyle`, `GwPlateStyle`.
- Folders:
  - `ServerStorage.GwangalliPassesTemplates` (server-only templates);
  - `Workspace.GwPassesFxLocal` (client-only FX);
  - `PlayerGui.GwangalliPassesApp` / `GwangalliPassesTags` (ScreenGui holding the BillboardGuis) / `GwangalliPassesKO` (chip).

### 4.3 Config (defaults)

```lua
Config.PASSES = {
	PremiumGarage = { Id = 0, Order = 7, Title = "프리미엄 차고", Perk = "garage", Store = true, -- suggested 799 R$
		Desc = "하이퍼카 · 슈퍼카 · VIP · 오프로더 4대 + 어디서든 내 옆으로 배달 · 출장 정비" },
	Convenience = { Id = 0, Order = 8, Title = "편의 패스", Perk = "qol", Store = true, -- suggested 349 R$
		Desc = "유치장 · 기절 대기 시간 절반 + 폰 블랙마켓 앱 (어디서든 총기 · 탄약)" },
	Flex = { Id = 0, Order = 9, Title = "과시 패스", Perk = "flex", Store = true, -- suggested 299 R$
		Desc = "KO 피니시 이펙트 · 나만의 번호판 · 네온 닉네임 (머리 위 + 채팅)" },
}
Config.STUDIO_ATTR = "GwPassesStudioTest"; Config.ADMIN_ATTR = "GwPassesAdminFree"
Config.JAIL_MULT = 0.5; Config.JAIL_MIN = 15
Config.KO_MULT = 0.5           -- SELF_HELP_AFTER, EMS_WAIT, EMS_TOTAL
Config.RESPAWN_MULT = 0.5
Config.SUMMON_COOLDOWN = 4     -- our own (the 8 s VS cooldown is skipped with force = true)
Config.SUMMON_SIDE = 9         -- studs to the player's side for "바로 옆"
Config.SUMMON_RADIUS = 400     -- lane search radius when "바로 옆" is blocked
Config.REPAIR_FEE_MULT = 1.0   -- 출장 정비 = GS.repairCost (same as the 정비소)
Config.PLATE = { MIN = 2, MAX = 9, COOLDOWN = 30, UNIQUE = true }
Config.KOFX = { PER_ATTACKER_GAP = 1.0, SERVER_PER_SEC = 12, RANGE = 220 }
Config.SHOP_RADIUS = 8
```

### 4.4 Premium catalog (`Shared/Cars.luau`)

| key | label (UI) | VehicleKind | body / template | spec (km/h · accel · brake · drive · gripF/R) | look |
|---|---|---|---|---|---|
| `hyper` | 블랙 하이퍼카 "광안 GT-X" | `gw_hyper` | our procedural wedge body (CarBodies.hyper) | 220 · 36 · 58 · AWD · 0.37/0.38 | low wedge, glass canopy, neon light blades, rear wing, centre-lock rims, purple underglow |
| `super` | 레드 슈퍼카 "광안 GT" | `gw_super` | `CarBuilder.Build("Sports")` stripped like GwangalliCarAdapter | 205 · 32 · 54 · RWD · 0.35/0.36 | sports body + splitter / skirts / ducktail, candy red, gold rims |
| `vip` | VIP 블랙 에디션 | `gw_vip` | the luxury map template (`orig("luxury")`, G80) + kit | 185 · 29 · 52 · RWD · 0.32/0.33, z 0.7 | matte black, chrome window line, gold emblem plate frame, soft white underglow, InteriorStyle g80 |
| `offroad` | 몬스터 오프로더 | `gw_offroad` | the suv map template (Tucson) lifted +1.2 studs, tyres ×1.35 | 150 · 22 · 46 · AWD · 0.34/0.35, E 0.42, U 0.85 | bull bar, roof light bar, snorkel, mud flaps, sand camo or army green, InteriorStyle tucson |

- Specs start as `table.clone(VS.Specs.luxury)` (or `suv` for the offroader). We override only label / model / topKmh / accel / brake / drive / grip / steerHigh, and E / U / z for the offroader.
- `label` = Korean name (`DriveLabel`).
- Paints: the 8 GS colours (white 화이트 ... mint 민트) plus `matte_black 매트 블랙`, `pearl 펄 화이트`, `candy_red 캔디 레드`, `lime 네온 라임`, `purple 미드나잇 퍼플`, `gold 샴페인 골드`. Each paint is `{id, name, rgb, material?}`; `material` is a Material for the paint parts, e.g. SmoothPlastic for matte and Foil / Glass for pearl.
- Default plate: `광안 VIP` + 2 random digits for the VIP; the others get a normal `GS.plate()`. A Flex vanity plate overrides it.

### 4.5 Remotes and payloads

`ReplicatedStorage.GwangalliPassesRemotes.Request` (RemoteFunction) `InvokeServer(op, payload) -> { ok: boolean, code: string?, message: string?, ... }`. Every `payload` must be a table or nil and is type checked field by field.

| op | payload | result | checks |
|---|---|---|---|
| `state` | – | `{ ok, owned = {PremiumGarage, Convenience, Flex}, ids = {...}, garage = {cars = PremiumView[], out = key?, mine = GarageView[]}, settings = {plate, plateStyle, neon, koFx}, qol = {active}, market = {open, reason, text} }` | 0.25 s cooldown |
| `summon` | `{ car = key, mode = "here" \| "road" }` | `{ ok, message, meters }` | owns PremiumGarage, `car` in catalog, alive, not KO / cuffed / jailed / in another car, our 4 s cooldown |
| `dismiss` | – | `{ ok, message }` | the current called car must be premium (`GwPremiumCar`) |
| `paint` | `{ car = key, paint = id }` | `{ ok }` | owns; paint in list; repaints the live car too (`GS.applyColor` + material) |
| `repair` | `{ id = d.cars id }` | `{ ok, message, cost }` | owns PremiumGarage; the car is in `GarageAPI "cars"`; `cost = GS.repairCost(kind, cond, model) × mult` > 0; `GameplayAPI "spend"` with label "🔧 출장 정비 · <plate>"; then `GarageAPI "setCondition"(player, id, 100)` |
| `market` | `{ tab = "basic" \| "upper" \| "ammo" }` | `{ ok, reason, text }` | owns Convenience; registers / refreshes the phone shop; `GwangalliArmsAPI "openShop"` |
| `marketState` | – | `{ open, reason, text }` | owns; `GwangalliArmsAPI "shopState"` + `playerReady` mirror (seated → "차에서 내려야 해요") |
| `setPlate` | `{ text = string, style = id }` | `{ ok, code, message, plate }` | owns Flex; `Plates.validate`; TextService filter must equal the input; unique claim; 30 s cooldown |
| `clearPlate` | – | `{ ok }` | owns Flex |
| `setNeon` | `{ palette = id \| "" }` | `{ ok }` | owns Flex; palette in list |
| `setKoFx` | `{ fx = id \| "" }` | `{ ok }` | owns Flex; fx in list |
| `previewKo` | `{ fx = id }` | `{ ok }` | owns Flex; 3 s cooldown; fires Event `kofx` to the requester only, at their position |

`Event` (RemoteEvent, server → client) `FireClient(payload)`:
- `{ kind = "owned", owned = {...} }` after a grant;
- `{ kind = "kofx", fx, pos = Vector3, by = userId, victim = "player" | "npc" | "officer", self = bool }`;
- `{ kind = "toast", icon, title, body, tone }`;
- `{ kind = "garage", out = key? }` (called car changed);
- `{ kind = "qol", what = "jail", before, after }` / `{ kind = "qol", what = "ko", endsAt }`.

`ServerStorage.GwangalliPassesAPI` (BindableFunction):
- `"has"(player, key) -> bool`
- `"owned"(player) -> table`
- `"catalog"() -> premium list`
- `"summon"(player, carKey, mode?) -> ok, msg`
- `"plateOf"(player) -> text?`

### 4.6 Server modules, step by step

**init.server.luau**
1. Require Shared. Build the remotes folder, but parent it only after Net has bound its handlers.
2. `Ownership.start()`: inject our passes into the server `GamePassConfig` when Id > 0, and hook `PlayerAdded`.
3. `Data.start()` (DataStore `GwangalliPasses_v1`, key `u_<UserId>`).
4. In parallel (each in a pcall, each with its own wait):
   - `Hooks.vehicles()` (wait `ServerStorage.GwangalliVehiclesAPI`, then require `SSS.GwangalliVehicles(Folder).Spawn`);
   - `Hooks.law()` (wait `GwangalliGameplayAPI`, then require `SSS.GwangalliGameplay(Folder).Law.Jail`);
   - `Hooks.ko()` (wait `GwangalliArmsAPI`, then require `...Arms.KOSystem`);
   - `Hooks.bus()` (wait `GwangalliCrimeBus`).
5. Start `Garage`, `Waits`, `Market`, `Plates`, `Neon`, `KoFx`, `Api`. A missing dependency sets a feature flag `ready.<feature> = false`, which `state` reports so the UI shows "준비 중".

**Ownership**
- `owns(player, key)`: cached per player; Studio / admin grant; else `UserOwnsGamePassAsync` (3 tries, 5 s apart).
- `grant(player, key)` sets `GwPass_<key> = true`, fires Event "owned" and calls module `onGrant` hooks: Neon defaults to "bridge" and KO FX to "lightning" on first grant; the respawn hook is armed.
- `PromptGamePassPurchaseFinished(player, id, purchased)` → `grant`. Keys with Id 0 are never checked.

**Data**

Profile `{ v = 1, garage = { paint = { [carKey] = paintId }, last = carKey? }, plate = { text?, style }, neon = palette, ko = fxId, stats = { kofx = n } }`.
- Load with retries.
- Save is `UpdateAsync`, debounced 8 s and on leave. While loading, mutations queue; if the load failed, never save (same rule as Garage).
- BindToClose flushes.
- Plate claims: DataStore `GwangalliPlates_v1`, key = normalized text (uppercased, spaces collapsed), value `userId`. `UpdateAsync` claims only if empty or ours, and releases the old key on change.

**Garage**
1. `register()`:
   - on the server `VS` table: `VS.Specs[kind] = spec` and `VS.Drivable[kind] = true` for the 4 kinds;
   - build the templates into `ServerStorage.GwangalliPassesTemplates`. `hyper` = `CarBodies.hyper()`; `super` = `CarBuilder.Build("Sports")` cleaned (strip joints / constraints / seats; rename Chassis → Underbody, Cushion → SeatCushion; keep a `BodySide` paint reference); `vip` / `offroad` = `origTemplate("luxury" | "suv"):Clone()` plus kits. Each template gets attribute `VehicleKind = kind`, `InteriorStyle`, `GwPremiumCar = key`, and parts named per the contract: Tyre (Cylinder), Underbody, BodySide, Grille, HeadlampLens, TailLamp, PlateFront / PlateRear with SurfaceGui + TextLabel, Interior (Model, attribute LOD = "near") with SeatCushion.
2. Wrap: `Spawn.template = function(kind) if TEMPLATES[kind] then return TEMPLATES[kind] end return orig(kind) end`. Spawn clones the returned model and never mutates the template.
3. `summon(player, key, mode)`:
   - validate;
   - `here` → raycast from `HRP.Position + side × 9` down 40 studs (exclude characters and cars) for a ground point, then `cframe = CFrame.lookAt(ground, ground + flatLook)`;
   - `vapi("spawnOwned", player, { id = "gwp_" .. key, kind, color = paint.rgb, colorId = paint.id, plate, cond = 100, dirt = 0, label }, { near = hrp.Position, cframe = (here ? cframe : nil), radius = Config.SUMMON_RADIUS, force = true })`;
   - on success, apply the paint material, the underglow PointLight colour, the vanity plate / style (Plates.applyTo), `GwPremiumCar`, and an arrival FX request to nearby clients (a short light sweep);
   - `msg = "label|meters"` → toast "🏎️ 블랙 하이퍼카 도착! 9m 옆에 세워 뒀어요".
4. `dismiss` → `vapi("despawn", player, "보관")` when `current` has `GwPremiumCar`.
5. `status(player)` → premium views `{ key, label, glyph, kind, topKmh, accel, drive, paint, plate, out = (current car's GwPremiumCar == key) }` + `mine = GarageAPI "cars"` (for 출장 정비).

**Waits**
- **Jail**: `Jail.begin = function(player, s, episode, info)`. If the player owns Convenience, `local e = table.clone(episode); e.seconds = math.max(Config.JAIL_MIN, math.ceil(e.seconds * Config.JAIL_MULT))`, then fire Event `qol` (before, after) → toast "⚡ 편의 패스 · 유치장 2분 → 1분". Call `orig(player, s, e, info)`.
- **KO watcher**:
  - per character, on `GwKO` true: `koStart[player] = os.clock()`, `emsSeen[player] = false`. Bus `EmsDispatched` with `payload.player == p` sets `emsSeen = true`; `Revived` / `Hospitalized` / `KOArrested`, or `GwKO` nil, clears it.
  - A loop every 0.5 s, for owners with `ArmsKO == "waiting"`: when `elapsed ≥ EMS_WAIT × 0.5` and not `emsSeen`, or `elapsed ≥ EMS_TOTAL × 0.5` and the state is not `firstaid` / `transport`, run `forceHelp(player)` (calls the wrapped `koHelp` with the override = 0).
  - Set `GwPassQoLKOEnd = serverNow + remaining` for the client chip.
- **koHelp wrap**: `KO.koHelp = function(victim) if owns(victim) and koStart[victim] and os.clock() - koStart[victim] >= A.KO.SELF_HELP_AFTER * Config.KO_MULT then local old = A.KO.SELF_HELP_AFTER; A.KO.SELF_HELP_AFTER = 0; local ok, r = pcall(orig, victim); A.KO.SELF_HELP_AFTER = old; return ok and r end return orig(victim) end`.
- **Respawn**: `Humanoid.Died` (owners) → `task.delay(Players.RespawnTime * 0.5, function() if player.Character == dead then player:LoadCharacter() end end)`. Skip when `Players.CharacterAutoLoads == false`.

**Market**
- `ensureShop(player)`: `id = "dealer:gwphone_" .. UserId`; `ArmsAPI:Invoke("setShopState", id, { open = true, name = "블랙마켓 · 다크앱", anchor = hrp, radius = Config.SHOP_RADIUS })`. Refresh the anchor on CharacterAdded.
- `open(player, tab)`: `ensureShop`, then `ok, why = ArmsAPI:Invoke("openShop", player, id, { tab = tab })`; map `why` to Korean:
  - police → "🚓 근처에 경찰이 있어 접속이 차단됐어요";
  - swat → "🚨 특임대가 근처에 있어요";
  - gunfire → "🔫 총소리가 나서 거래가 잠시 멈췄어요";
  - chased → "🚔 경찰에 쫓기는 중엔 접속할 수 없어요";
  - busy → the seated / KO / working text;
  - attacked / grudge → generic.
- `state(player)` → `ArmsAPI "shopState"` + seated check.
- Leave the shop registered while the player is online; `PlayerRemoving` → `setShopState(id, { open = false })`.

**Plates**
- `Plates.validate(text)`:
  - trim and collapse spaces; uppercase ASCII;
  - `utf8.len` within 2..9 characters;
  - allowed codepoints: 0xAC00-0xD7A3 (Hangul syllables), 0-9, A-Z, space, `-`;
  - at least one non-space character;
  - not all digits longer than 8.
- Then filter; the filtered text must equal the input, else "사용할 수 없는 번호판이에요". Then the unique claim, else "이미 누가 쓰는 번호판이에요".
- Apply: `workspace.GwangalliPlayerCars.ChildAdded` and `GwPremiumCar` spawns. If the model has `DriveOwnedCar == true`, `DriveOwner == owner.UserId`, no `DriveRental` / `DriveTestDrive`, and the owner has Flex plus a plate, run `GS.applyPlate(model, text)` and the style: plate parts' Color / Material, TextLabel TextColor3 / FontFace / Stroke, an optional thin neon frame part (CanCollide / CanQuery / CanTouch false, Massless, welded to the plate) for gold / neon.
- Styles:
  - 기본 (white, black text);
  - 전기차 (blue-white gradient, black text; IRL Korean EV plates);
  - 옛날 녹색 (green, white text: pre-2006 plates);
  - 골드 VIP (black, gold text, gold frame);
  - 카본 (dark graphite, white);
  - 네온 (dark, cyan text with a glowing frame, Neon material).

**Neon**
- `setNeon` → `player:SetAttribute("GwNeonName", palette)`.
- On each character, for owners with neon on: `Humanoid.DisplayDistanceType = None` (restore `Viewer` when off or when the pass is lost). Re-apply on CharacterAdded.
- Legacy chat (`TextChatService.ChatVersion == LegacyChatService`): ChatService speaker `SetExtraData("NameColor", palette.c1)` + `Tags = {{TagText = "✦", TagColor = c2}}`, pcall'd.

**KoFx**
- Bus listener:
  - `KnockedOut`: attacker = `Players:GetPlayerByUserId(payload.by)` when `payload.kind == "player"` and `by` is a number; pos = `payload.pos` or the victim's HRP.
  - `NpcKnockedOut` / `OfficerDown`: attacker = `payload.player`.
- If the attacker owns Flex and `GwKoFx ~= ""`, apply the rate gates, then FireClient to every player within `RANGE` of pos: `{kind = "kofx", fx, pos, by, victim, self = (p == attacker)}`.

**Api**: `GwangalliPassesAPI.OnInvoke` dispatch (validate `player` instances).

### 4.7 Client modules and UI

**StoreHook** (runs first, before any yield): `local GPC = require(RS:WaitForChild("GamePassConfig"))`; for every pass in `Shared.Config.PASSES` with Id > 0 and missing in GPC, `GPC[key] = { Id, Name = Title, Title, Desc, Perk, Store = true, Order }`. Ownership signal = `LocalPlayer.AttributeChanged` on `GwPass_*`. `buy(key)` = `MarketplaceService:PromptGamePassPurchase`, pcall'd; with Id 0 it shows the toast "판매 준비 중이에요".

**PhoneHook**
- Wait for `PlayerGui.GwangalliPhone` → `Device.Screen.Home.Dock`, re-hooking whenever the phone gui is recreated.
- Add a cell `App_vip`: a TextButton with the same structure as the phone's dock icons. Its icon tile has a gradient from gold `(255, 194, 71)` to magenta `(255, 79, 163)`, glyph "👑" (TextLabel, since `K.Glyph` has no vip id), gloss frame, `K.pressable`.
- Mirror the size from `App_bank.Icon`; set the dock UIGridLayout to 5 columns (see risk 5).
- The badge dot shows on the first join after a grant, and while the 블랙마켓 is blocked it shows a red dot.
- Activated → `Hub.open()`.
- Patch-native mode: if `ReplicatedStorage.GwangalliPassesShared:GetAttribute("PhoneNative")` is set (the patch sets it) or `Dock:FindFirstChild("App_vip")` was made by the phone, skip the injection; the phone calls our app module itself.

**Hub** (own ScreenGui `GwangalliPassesApp`, DisplayOrder 31, ResetOnSpawn false, `ScreenInsets = CoreUISafeInsets`)
- The root frame tracks `Device.Screen` (AbsolutePosition / AbsoluteSize each RenderStepped while visible) with the phone's corner radius and `K.Color.bg`. Its open animation is the phone's style: zoom from the icon plus a cover fade.
- Header: back "‹" (44 px), title "VIP 패스", subtitle with owned chips "✦ 프리미엄 차고 · ✦ 편의 · ✦ 과시".
- `K.Segmented` tabs: 차고 · 블랙마켓 · 꾸미기.
- A locked tab shows a hero card (pitch + benefit bullets + "R$ 799로 열기" / "판매 준비 중") instead of content.
- Gamepad: `GuiService.SelectedObject` = the first button on open; ButtonB = back. PC: Esc = back.
- Closes when `GwangalliPhone.Enabled == false`, the phone goes home / another app opens, the weapon shop opens, or on back. Reopening the phone after back is not needed, since the phone stays open underneath.

**GarageTab**
- A ScrollingFrame of 4 big cards (`K.Card`, 168 px). Each card has:
  - a ViewportFrame preview (Preview: CarBodies hyper / super built locally; vip / offroad from a local clone of a streamed-in `Car_Genesis G80` / `Car_Tucson` / Display car with the kit applied; glyph tile fallback; slow orbit; `K.reduced()` = static);
  - the name and an "최고 220km/h · 사륜" chip;
  - the paint row (14 chips, 32 px, selected ring);
  - buttons [📍 바로 내 옆으로] (primary) and [🛣️ 도로로] (secondary); [↩️ 돌려보내기] when out.
- Section "내 차 출장 정비": the Garage cars (from `state.garage.mine`) with condition bar + [🔧 출장 정비 N원] (disabled when cond = 100) + confirm (`K.confirm`).
- Toasts through `K.toast`.

**MarketTab**
- Dark theme (near-black `(8, 10, 12)`, neon green `(57, 255, 136)`, mono font); a fake "보안 연결" handshake line animates on open (0.6 s).
- Status line from `marketState` (refreshed every 2 s while visible): "🟢 보안 연결됨 · 거래 가능", or a red reason.
- Three entries: [기본 총기] (basic), [조직 물건] (upper; shows "[마피아 전용]" when not mafia, the server decides), [탄약] (ammo). Tap → `Request "market"` → success: the existing WeaponShopUI opens and the phone and our hub close themselves; failure: shake + reason.
- Footer: "총기상 NPC와 같은 가격 · 경찰 · 특임대 근처에선 접속이 막혀요".

**FlexTab**
- Plate editor: a live 2D plate preview (a Frame with UICorner 4, aspect 1.74 : 0.37 = 4.7) in the chosen style, a TextBox (ClearTextOnFocus false; the client checks length / charset first), style chips, [저장]. Sample presets: "광안 1004", "부산 VIP", "GW 7777".
- Neon nickname: palette chips, each a live mini preview of the DisplayName with an animated UIGradient; [끄기] toggle.
- KO effects: a list (name, short description, [▶ 미리보기], selected check).

**NeonTags**
- For every player with `GwNeonName` set, create a BillboardGui in `PlayerGui.GwangalliPassesTags`: Adornee = Head, Size (200, 30), StudsOffset (0, 2.4, 0), MaxDistance 90, LightInfluence 0, AlwaysOnTop false, attributes `GwLabelClass = "named"`, `GwLabelFocus = true`.
- The TextLabel shows the DisplayName in FontFace GothamSSm Bold with a UIGradient (palette ColorSequence, Offset animated −1 → 1 at palette.speed, `Rotation` 15) and a UIStroke (palette.stroke, Thickness 1.6, Transparency 0.35) as the glow.
- The local player sees their own tag (flex).
- Rebind on CharacterAdded and attribute change. Hide while the target sits in a vehicle seat that hides heads? Not needed.
- Palettes (Shared/Neon):
  - `bridge` 광안대교 (cyan → magenta, `K.Grad.bridge`);
  - `sunset` 해운대 노을 (orange → pink);
  - `gold` 황금 (gold → amber);
  - `aurora` 오로라 (lime → cyan → violet);
  - `ice` 아이스 (white → sky);
  - `rainbow` 레인보우 (hue cycle).

**ChatNeon**: claim `OnIncomingMessage` (see risk 7). For a message from a player with `GwNeonName`, set `props.PrefixText = "<font color='#FFC247'>✦</font> " .. Neon.richGradient(DisplayName, palette) .. rest`. `rest` is whatever followed the name in the original PrefixText (usually ":"). `richGradient` emits one `<font color>` per UTF-8 character, sampling the ColorSequence, with `<b>`.

**KoFxClient** (Shared/KoFx defs; all FX in `Workspace.GwPassesFxLocal`, anchored, CanCollide / CanQuery / CanTouch false, CastShadow false, Debris 3 s). Built-in content only: particles `rbxasset://textures/particles/sparkles_main.dds`, `fire_main.dds`, `smoke_main.dds`; sounds from `A.SOUNDS` ids with their `rbxasset://sounds/...` fallbacks (`ArmsShared.luau:423-470`).
- `lightning` 번개 KO: 3-4 jagged Neon part bolts from the sky to pos, a white flash PointLight (Range 24, 0.15 s), an expanding cyan ring (Cylinder, Neon, Size tween), sparkles; sound `heavy` + `electronicpingshort` pitched low.
- `inferno` 화염 KO: a fire_main burst (Rate burst 40), ember sparkles, orange flash, a smoke ring.
- `neonring` 네온 충격파: three staggered rings in the attacker's neon palette colours plus a floor decal-like disc.
- `money` 돈다발: 16 thin green bill parts (0.05 × 0.6 × 1.2) burst out with random spin and fall, a gold coin sparkle; sound `coins`.
- `sakura` 벚꽃 (부산 봄): pink sparkles (Color pink, LightEmission 0.6), 20 petal parts swirling up; soft chime.
- `stamp` K.O. 스탬프: a big BillboardGui "K.O." (GothamBlack, gradient, pop scale 1.6 → 1) at pos + 3 studs, plus a dust ring.

The attacker (`self = true`) also gets a 0.12 s screen flash, `Camera.FieldOfView` +4 then back over 0.25 s (skipped when reduced motion), and a "K.O.!" banner with the effect name. Quality: `GwangalliQuality` tier low → no lights and half the particles; at most 3 concurrent.

**QoLClient**
- If the local player owns Convenience: `A.KO.SELF_HELP_AFTER = orig × 0.5` (restore when not owned).
- On `GwKO`: show the chip (ScreenGui `GwangalliPassesKO`, DisplayOrder above the KO screen) "⚡ 편의 패스 · N초 후 병원 이송", counting down to `GwPassQoLKOEnd`.
- Event `qol` jail → toast.

**DriveHook**
- Find `PlayerScripts.GwangalliDrive` (Folder) → `Api`, waiting up to 30 s.
- Wrap `Api.status`: `local st = orig()`; for owners, append the premium views shaped like `GS.carView`: `{ id = "gwp_"..key, label = "✦ " .. label, glyph, color = paint GS id or "black", plate, cond = 100, band = "good" }`, and set `st.max = (st.max or 3) + #premium`. Replace `plate` in every view with the vanity plate when set.
- Wrap `Api.callCar`: `if type(arg) == "string" and string.sub(arg, 1, 4) == "gwp_" then return ourSummon(key, "road") end return orig(arg)`.

### 4.8 Korean lines (Shared/Lines.luau, excerpt)

- Locked: "프리미엄 차고 패스가 있으면 이 차를 어디서든 부를 수 있어요", "편의 패스 전용 앱이에요", "과시 패스로 나만의 번호판과 네온 닉네임을 써 보세요".
- Summon: "{label} 도착! {m}m 옆에 세워 뒀어요", "여긴 차를 세울 자리가 없어서 가까운 도로에 세워 뒀어요 ({m}m)", "운전 중에는 차를 부를 수 없어요", "잠시 후 다시 불러 주세요 ({s}초)".
- Repair: "🔧 출장 정비 완료! {plate} 상태 100% · {cost}", "돈이 부족해요 ({cost} 필요)", "이미 상태가 좋아요".
- Market: "🟢 보안 연결됨 · 거래 가능", "🚓 근처에 경찰이 있어 접속이 차단됐어요", "🚗 차에서 내려야 거래할 수 있어요", "😵 지금은 앱을 쓸 수 없어요".
- Plate: "번호판은 2~9글자, 한글 · 숫자 · 영어만 쓸 수 있어요", "사용할 수 없는 번호판이에요", "이미 누가 쓰는 번호판이에요", "번호판을 바꿨어요! 다음에 부르는 차부터 달려요".
- QoL: "⚡ 편의 패스 · 유치장 {a} → {b}", "⚡ 편의 패스 · {s}초 후 병원으로 이송돼요", "편의 패스 혜택은 다음 체포부터 적용돼요".
- Pass: "판매 준비 중이에요", "패스 구매 완료! 바로 적용됐어요 ✦".

### 4.9 Player flows

1. **Buy.**
   1. 폰 → dock 👑 VIP → a locked tab → "R$ 799로 열기" → Roblox prompt.
   2. Server `PromptGamePassPurchaseFinished` → `grant`; the attribute flips; the hub re-renders to unlocked.
   3. Toast "패스 구매 완료! 바로 적용됐어요 ✦".
   4. (The R$ app lists the three passes too when their Ids are set.)
2. **Premium call.**
   1. VIP → 차고 → 블랙 하이퍼카 → paint 캔디 레드 → [📍 바로 내 옆으로].
   2. Server: validate → raycast side spot → `spawnOwned` (force) → paint / plate / underglow.
   3. Toast "블랙 하이퍼카 도착! 9m 옆…". The car appears with an arrival light sweep, and the player walks up and drives (ownerOnly).
   4. Friends may ride as passengers. Fuel drains as usual. [돌려보내기] or the 차 부르기 sheet's dismiss sends it back.
   5. The same premium cars also appear in "🚗 내 차" (차 부르기) as "✦ 블랙 하이퍼카"; [부르기] there = the road delivery.
3. **출장 정비.** VIP → 차고 → 내 차 → "미드 세단 42%" → [🔧 출장 정비 31,200원] → confirm → paid (GameplayAPI spend) → `setCondition 100` → the live car's smoke stops → toast.
4. **Jail.** Arrested with a 2:00 sentence → `Jail.begin` wrap → the arrest card says 유치장 1:00 → toast "⚡ 편의 패스 · 유치장 2분 → 1분" → the cell → released after 60 s.
5. **KO.**
   1. Knocked out by a gang member → the KO screen plus our chip "⚡ 편의 패스 · 47초 후 병원 이송".
   2. The "병원으로 이송" button shows after 10 s instead of 20 s.
   3. With no ambulance coming, the fade to the hospital ward happens at 47 s; with an ambulance (`EmsDispatched`), the normal 119 flow runs (cap 75 s).
6. **Black market.**
   1. VIP → 블랙마켓 → "🟢 보안 연결됨" → [기본 총기].
   2. The server registers the shop on the HRP and opens it → the WeaponShopUI opens (the phone closes) → buy M1911 85,000원 (cash first, then bank) → the gun goes into the inventory.
   3. If a police car is within 45 studs → "🚓 근처에 경찰이 있어 접속이 차단됐어요" and an open shop closes.
7. **Flex.**
   1. VIP → 꾸미기 → plate "광안 1004" + 골드 VIP → 저장 → filtered and claimed → the next car called (owned or premium) carries the gold plate (the cop lookup shows it too).
   2. Neon "광안대교" → everyone sees the animated gradient name over the head; chat shows "✦ N̲a̲m̲e̲:" in the gradient.
   3. KO effect "번개" → the player KOs an NPC in a street fight → everyone within 220 studs sees bolts plus a ring; the attacker sees the "K.O.!" banner.

### 4.10 Optional patch (`patches/GwangalliPasses_Phone.patch`)

Against `EFF/StarterPlayer/StarterPlayerScripts/GwangalliPhone/Phone.luau`. Korean note: "선택 사항: 폰 하단 독에 VIP 앱을 정식으로 넣습니다. 안 넣어도 애드온이 같은 자리에 아이콘을 붙입니다."
- Add `vip = { title = "VIP", glyph = "👑", c1 = gold, c2 = magenta, module = "Vip", external = "GwangalliPasses", server = false }` to `APP_META`, and `"vip"` to `DOCK_APPS`.
- In `ensureBuilt`, if `meta.external`, find `PlayerScripts[meta.external]` (LocalScript) → child ModuleScript `PhoneApp` (our Hub exposes the `(ctx) -> app` contract).
- Dock math: `/ 4` → `/ #DOCK_APPS`, `FillDirectionMaxCells = #DOCK_APPS`.
- Set the attribute `ReplicatedStorage.GwangalliPassesShared.PhoneNative = true` at start, so PhoneHook skips its injection.

### 4.11 Test plan

- **Offline mock** (`SCR/bprev/lib/rbx.luau` copy in `SCR/feat/passes/`):
  - `Plates.validate` table tests (Hangul / ASCII / emoji / length / spaces);
  - `Neon.richGradient`;
  - the Jail wrapper halving (min 15);
  - the koHelp wrapper restores `SELF_HELP_AFTER` even when orig errors;
  - the summon validation matrix;
  - the token bucket.
- **Temp studio** (one run, under flock, 1500 s timeout), with `workspace.GwPassesStudioTest = true`:
  1. Spawn each premium kind through our API; check it rigs (`DriveRigged`), that `VS.spec(rig.kind).topKmh` matches, and take a screenshot of each car.
  2. Arrest via `Law.arrest` → `LawJail - now ≈ half`.
  3. `GwangalliArmsAPI "knockOut"` the player → `ArmsKO` waiting → transport at ~47 s.
  4. Phone shop `openShop` ok; with a police officer spawned near → refused "police".
  5. `previewKo` FX screenshot; neon tag screenshot.
  6. The plate applies on spawn.

### 4.12 Open questions for the owner (defaults used)

- Pass Ids and prices: the config has Id 0 → "판매 준비 중" until the owner fills in the dashboard numbers. Suggested 799 / 349 / 299 R$.
- Should premium cars be sellable or appear in the dealer? Default: no, they are pass-only, and the dealer may show them as "패스 전용" via `GwangalliPassesAPI "catalog"` / `"has"`.
- Should premium cars wear down (condition)? Default: no wear (not tracked by Garage), but fuel is used.
- Should the black market add a fee for remote delivery? Default: none (same prices as the dealer).
