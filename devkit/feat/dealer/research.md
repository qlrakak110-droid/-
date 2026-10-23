# GwangalliCarDealer — research + design (광안 오토 영업 컨설턴트 · 차량 카탈로그 · 시승 · 계약)

Scratch: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/dealer/`
(`$D` below). `$Z` = `$D/pack/core/gen/addons/zip` = the add-on sources unpacked from the studio HTML
(`python3 -I scratchpad/tools/unpack.py <html> $D/pack`). `$B` = `scratchpad/bld/src` (523 scripts
dumped from v7 place.bin).

**Version note (important).** The studio upserts ~385 add-on scripts (`gen/addons.json`, field `upsert`)
on top of place.bin. The add-on versions (`$Z`) are NEWER than the place.bin dumps (`$B`): Garage 1690 vs
1418 lines, GarageShared 639 vs 503 (place.bin GS has **no GS.MODELS**, luxury new 3,200,000 vs 6,500,000).
Code against `$Z`, but tolerate the older API: `GS.MODELS == nil`, prices read at runtime only, never
hard-coded. Both versions expose `GwangalliGarageAPI:Invoke("request", player, op, payload)`
(`$Z/.../Garage.luau:1313`, `$B/.../Garage.ModuleScript.luau:1263`).

---------------------------------------------------------------------------------------------------
## 1. Existing integration points (exact)

### 1.1 Venue instances (Workspace.Gwangalli.garage['광안 오토 정비소 & 중고차'], read-only)
Dump: `scratchpad/bld/hg/dump.json` (key `garage`); survey `scratchpad/bld/hospital_garage.json`.
Model is rotated ~-1.9° about Y; storefront faces +Z at z≈472-474; ShowroomFloor top y = 6.67.

| what | instance / tag | attrs / world pos |
|---|---|---|
| venue root | Model tag `GarageShop` | `Place='광안정비소'`, `Route='-578.9,6.5,511.5|-713.5,6.5,510.0|…|-517.0,6.5,515.6'` (11 test-drive points, packed) |
| 6 kit display cars | Model `Display_<kind>` tag `GarageDisplayCar` | `GarageKind`, `VehicleKind`, `NoDrive=true`, `PaintId`, `CarModel` (generic: '큐비 박스카', '미드 세단', '플래그십 세단', '트레일 SUV', '패밀리 9인승 밴', '든든 1톤 트럭'); 113-174 parts |
| 6 turntables | Part `Turntable` tag `GarageTurntable` 0.34x17x17 | `Centre` (V3), `GarageKind`; centres compact (-589.37,459.22) luxury (-565.38,460.01) sedan (-541.39,460.80) suv (-588.68,438.23) van (-564.69,439.02) truck (-540.70,439.81); client spins disc+car → keep r 8.75 clear |
| 6 price cards | Part `PriceCard` tag `GaragePrompt` 3.6x2.2 at y 10.8 | `GarageKind`; prompt '구매 / 시승' (MaxActivationDistance 12) moved by Garage to Attachment `GaragePromptAnchor`; cards at z≈448-449 (back row) and z≈469-471 (front row) |
| owner desk | Part `GarageDesk_office` tag `GarageDesk` (-586.36,9.2,428.71) | `Kind='office'`; prompt `GarageDeskPrompt` ActionText '상담 · 렌트 · 내 차', ObjectText '박사장 (사장님)', range 12 |
| service / wash desks | `GarageDesk_service` (-482.07,9.2,470.25) / `GarageDesk_wash` (-467.17,9.2,473.64) | '정비 받기' / '세차하기 · 자동세차 5,000원' |
| staff rigs | Model tag `GarageStaff` | 박사장 (사장님) `Role=owner` HRP (-586.2,9.7,422.4) look +Z; 김기사 (정비사) `Role=mechanic` (-504.1,9.7,459.5). **AnimationController rigs, no Humanoid** (probe_out.txt) |
| spawn lane | Part tag `GarageSpawn` (-500.01,7.0,480.36) 6.6x1x17 | LookVector = heading; test/rent cars appear here |
| return point | Part tag `GarageReturn` (-559.98,7.06,478.6) | finished test drivers are put here |
| destination | `Destination` '광안정비소' (-566,7.1,479) | quick travel / waypoint |
| lift car | Model tag `GarageLiftCar` | `CarModel='미드 세단'`, NoDrive |
| signs | `Sign_시승 무료 · 60초`, `Sign_오늘의 특가 · 중고 큐비 15만원`, `Sign_중고차 매매 상담 · 할부 · 렌트`, DeskSign '구매 상담 · 렌트 · 내 차 관리' | LIVE_BOARDS names must keep their names |

Occupancy ASCII map of the showroom (x -602..-527, z 418..486): `python3 $D/g2.py`. Free floor bands:
back band between owner desk (x -598..-580) and lounge (x -557..-537) at z 422-429; aisle crossing z 448-451.

### 1.2 Server garage module — ServerScriptService.GwangalliGameplay.Garage (`$Z/ServerScriptService/GwangalliGameplay/Garage.luau`)
Feature module (init/onLoaded/onCharacter/onLeave) of the GwangalliGameplay Script; owns d.cars.
- Remotes (created in `GwangalliRemotes`): `GarageRequest` RemoteFunction, `GarageEvent` RemoteEvent (`:1563-1567`).
  GarageEvent payload `{kind = "open"|"zone"|"repair"|"wash"|"cars"|"testdrive"|"toast", …}` (GS header `:30-37`).
- **Server API we call**: `ServerStorage.GwangalliGarageAPI` BindableFunction (`bindApi` `:1266`):
  ```lua
  -- Garage.luau:1281-1315
  if op == "cars" then return views(player)              -- list of GS.carView
  elseif op == "status" then return opStatus(player)      -- {cars,max,owned,bank,cash,atGarage,zone,outId,testCooldown,testing,loaded,free}
  elseif op == "give" then ... (player, kind|modelId, grade?, colorId?) -> view   -- no payment (tests / rewards)
  elseif op == "setCondition" then ... (player, id, cond) -> bool
  elseif op == "request" then return handle(player, a, b) -- = the GarageRequest remote, same validation
  ```
- `handle` (`:1148-1183`): op whitelist `OPS` (`:1104`: status, list, quote, buy, sell, rent, testdrive, call,
  dismiss, tow, repair, wash, waypoint, endtest); `Util.bucket(player, 6, 12)` (`:1155`, shared global
  per-player bucket: 6 tokens/s, burst 12); per-op cooldown `COOLDOWN` (`:1146`: buy 1 s, testdrive 1.5 s,
  quote 0.15 s…); `"loading"` until `s.loaded`; MUTATING ops take `s.busy`.
- `opBuy` (`:610-672`): payload `{kind, grade='new'|'used', color, loan}` or `{model=id, color?, loan}`;
  price ALWAYS from GS (`wanted` `:588-604`); checks `atGarage(player,160)` (`:258`, flat distance to the
  GarageShop pivot), `GS.owned(cars) >= GS.MAX_CARS` (3), one per model, missed-loan block; pays via
  `ctx.spend(player, amount, label, true, "bank")` (`pay` `:483`: bank first, cash fallback); 할부: pays
  `q.down`, `car.loan={remaining,daily,lastDay=d.lifeDay,missed=0,total}`, addBill; `markDirty(player,true)`
  (own DataStore `GwangalliGarage_v1`, key `u_<UserId>`); `ctx.notify(…"🚗 구매 완료 · "…)`;
  `pushCars` → GarageEvent `{kind="cars"}`; returns
  `{ok=true, code="ok", car=GS.carView(car), receipt={label, plate, paid, account, loan?, price, grade, kind, model, color}}`.
  Errors: `loading`, `bad`, `far`, `max`, `owned`, `loanMissed`, `insufficient` (Korean `message`).
- `opQuote` (`:1059`): `{kind, grade, model, owned, price, loan=GS.loanQuote|nil, canLoan, afford, affordDown, bank, cash}`.
- `opRent` (`:748`): 큐비 one in-game day (`GS.RENTAL` fee 20,000, 2400 s), auto-calls the car near GarageSpawn.
- `opCall` (`:709`): `{id}` → `vapi("spawnOwned", …)`, returns `{label, meters, car=Model, plate, id}`.
- `opTestDrive` (`:849-899`): **kind only** (`p.kind`, `p.color`) — a showroom model cannot be test-driven
  as itself; 60 s (`GS.TEST_DRIVE.seconds`), cooldown 45 s, `atGarage 160`; dismisses the called car;
  spawns at GarageSpawn seated; `ctx.allowTeleport(player,6)`; fires GarageEvent
  `{kind="testdrive", stage="start", carKind, seconds, route, car}`. End (`endTest` `:822`): eject,
  despawn, `ctx.allowTeleport(player,8)` + `Util.teleportTo(GarageReturn)`, fires `stage="end", why`.
  Daily loop (`:1244-1258`) ends it on time, car gone, or driver (`model:GetAttribute("DriveDriver") ~= UserId`) away 5 s.
- `dismiss` op: despawns the called car + untracks (`:1121-1128`).
- Garage does **not** apply the level perks `used_car_discount`, `car_loan`, `luxury_new` (grep: only
  Progress/Taxi/Relationships call `perk`).

### 1.3 Shared data — ReplicatedStorage.GwangalliGarageShared (GS) (`$Z/ReplicatedStorage/GwangalliGarageShared.luau`)
Pure module, safe on the client. Functions we call (line):
`GS.price(kind, grade)` 234 · `GS.modelInfo(id)` 243 · `GS.modelName(id|entry)` 251 (generic label unless
`GS.SHOW_REAL_NAMES` 139 = false) · `GS.modelPrice(id)` 260 · `GS.carName(car)` 266 · `GS.loanQuote(price)`
281 → `{price, down, principal, total, daily, days}` · `GS.canLoan(price)` 290 (≥ `GS.LOAN.minPrice` 300,000)
· `GS.sellValue` 337 · `GS.colorEntry/colorRGB/color3` 344-358 · `GS.ownsModel(cars,id)` 473 ·
`GS.modelViews(cars)` 486 · `GS.carView` 508 · `GS.callable` 543 · `GS.paintParts(model)` 579 (ref part
BodySide / CabSide / Hood, same-colour parts outside "Interior") · `GS.applyColor(model, color3, id)` 595 ·
`GS.formatWon(n)` 628.
Data: `GS.KIND_ORDER` 118; `GS.CATALOG` 121-128 (6 kinds: label/full/glyph/blurb/new/used/seats/tag —
compact 큐비 390,000/150,000 · sedan 미드 세단 780,000/320,000 · suv 트레일 SUV 980,000/420,000 · truck 1톤 트럭
640,000/280,000 · van 패밀리 밴 1,250,000/520,000 · luxury 플래그십 6,500,000/2,900,000); `GS.USED_COND {55,80}`;
`GS.MODELS` 142-160 (13: k5 1,150,000 · sorento 1,450,000 · g90 9,800,000 · gv80 7,900,000 · santafe 1,300,000 ·
sonata16 650,000 · ioniq5n 5,900,000 · avanten 1,600,000 · carnival 1,700,000 · k7 1,400,000 · ev6 1,500,000 ·
sonata06 380,000 · tuscani 520,000 · optima 340,000; fields id/real/kind/label/glyph/body/seats/price/blurb/tag);
`GS.RENTAL` 168; `GS.LOAN {down=0.3, rate=0.05, days=10, missLimit=3, minPrice=300000}` 173; `GS.COLORS` 176
(8: white 화이트, black 블랙, silver 실버, grey 그레이, navy 네이비, red 레드, beige 베이지, mint 민트);
`GS.MAX_CARS=3` 110, `GS.SELL_RATE=0.6`; `GS.TEST_DRIVE {seconds=60, cooldown=45}` 215;
`GS.Tags` 54-72, `GS.Attr` 74-95 (`DriveCarId`, `DriveTestDrive`, `DriveOwnedCar`, `DriveModel`, `GwShowroomModel`, `GwCarModel`…).
Profile record (GS header 25-30): `{id, kind, color, plate, cond, dirt, bought, grade, t, studs, loan?, rental?, towed?, model?}`.

### 1.4 Vehicles — ServerScriptService.GwangalliVehicles/{Spawn,Cars,Rig,Analyze,Parked} + ReplicatedStorage.GwangalliVehiclesShared (VS)
- `ServerStorage.GwangalliVehiclesAPI` BindableFunction (Spawn header `$Z/…/Spawn.luau:28-37`):
  `"spawnOwned"(player, spec, opts) -> ok, msg ("label|meters"), model` with
  `spec={id, kind, model?, color(Color3), colorId, plate, cond, dirt, label, rental, testDrive(unix end)}`,
  `opts={near, cframe(ground), radius, force(skip cooldown), seat(put player in driver seat)}`;
  `"despawn"(player, reason?)`, `"current"(player)`, `"eject"(model)`, `"park"(model)`,
  `"seat"(player, model) -> ok,msg`, `"occupants"(model)`.
- One called car per player: `callOwned` despawns the previous one (`Spawn.luau:704-707`); sets
  `DriveTestDrive` attr when `spec.testDrive` (`:717`); owner-only driver seat.
- Kit templates (`Spawn.template` `:183`): first non-traffic, non-NoDrive map Model with `VehicleKind==kind`
  under Workspace.Gwangalli, else a GarageDisplayCar, cached in `ServerStorage.GwangalliDriveTemplates`.
  In v7 that resolves to the real-looking parked cars (verified, `$D/q4.py`): compact = Car_Kia Ray (151 parts),
  sedan = Car_Sonata (DN8, 159), luxury = Car_Genesis G80 (172), suv = Car_Tucson (164), van = Car_Carnival (171),
  truck = Car_Porter II (109, inside the coast food-truck model).
- Model templates (`Spawn.modelTemplate` `:231`): `ServerStorage.GwangalliCarModels[GS.MODELS[i].real]` or a
  child with `GwCarModel == real`; **missing → kit car of the same kind**.
- `VS.Specs` (`$Z/…/GwangalliVehiclesShared.luau:111-153`): per kind `mass, topKmh, reverseKmh, accel, brake, drive`
  (compact 100 km/h FWD … luxury 165 RWD, suv AWD, truck 102 RWD); `VS.spec(kind)` 176; `VS.Drivable` 158.
- Map car census (`$D/q2.py`): Car_Kia Ray ×~30, Car_Sonata ×~37, Car_Tucson ×~28, Car_Porter II ×~22,
  Car_Carnival ×~17, Car_Genesis G80 ×~7, taxi/police/ambulance, Car_Scooter ×~120, LotCar_* (15-16 part boxes).

### 1.5 Showroom — ServerScriptService.GwangalliShowroom (`$Z/ServerScriptService/GwangalliShowroom.luau`)
After `SETTLE=6` s (`:40`) it needs `ServerStorage.GwangalliCarModels` (`WaitForChild 30`, `:376`); then clones each
GS.MODELS entry into `Workspace.GwangalliShowroom` (tag `GarageShowroomCar`, attrs `NoDrive`, `VehicleKind`,
`GwShowroomModel`, `GwCarModel`, `:267-272`) on free 2-stud grid spots tested against SERVER parts, adds a
'신차 보기' prompt on `ShowroomAnchor` (`:293-322`), sets `folder:SetAttribute("Placed", done)` (`:778`).
**v7 place.bin has no `ServerStorage.GwangalliCarModels` (GWPB search: 0 instances with GwCarModel /
GwShowroomModel; ServerStorage = GwangalliHomes, GwangalliTextures, 3 modules) → the Showroom places 0 cars and
the folder is never created (probe in studio: "NO GwangalliShowroom", "NO GwangalliCarModels").** The 13 models
are still sellable through the Sheet 쇼룸 tab but are delivered as the kit car of their kind.

### 1.6 Client garage UI — StarterPlayerScripts.GwangalliGarage (+ folder Net/Sheet/Fx/Hud)
`$Z/StarterPlayer/StarterPlayerScripts/GwangalliGarage.luau` (+ Sheet.luau there; Net/Fx/Hud from `$B`).
- Prompt routing (`:135-165`): GaragePrompt → `Sheet.open{tab="buy", kind}`; GarageDesk office → `{tab="mine"}`;
  service/wash → zone actions; ShowroomPrompt (`GwShowroomModel`) → `{tab="showroom", model}`. Identifies
  prompts by tag on `prompt.Parent` → **our own prompts are ignored by it**.
- Public opener: `LocalPlayer.GwangalliGarageOpen` BindableEvent `:Fire({tab, kind, model})` (`:167-176`).
- After a Garage test drive ends with `why=="time"` it reopens the Sheet on that kind after 1.2 s (`:82-88`).
- Sheet (`Sheet.luau:1-17`): ScreenGui `GwangalliGarageUI` DisplayOrder 32 (`:367-378`), sets
  `HideGwangalliHUD` while open; 4 tabs 구매 (kit kinds, 신차/중고, 8 colours previewed on the turntable car,
  할부 toggle, "시승 60초", 구매하기), 쇼룸 (13 model cards, buy / loan double-tap, **no test drive**), 내 차
  (call/repair/sell/tow), 렌트. Side panel only; no categories, no 3D preview of the 13 models, no NPC talk.
- Hud (`$B/…/GwangalliGarage/Hud.ModuleScript.luau:5-6, 190-250`): test-drive chip + route beacons, driven by GarageEvent only.

### 1.7 Money / profile / progress
- `ServerStorage.GwangalliGameplayAPI` (`$Z/ServerScriptService/GwangalliGameplay.luau:478-495`):
  ```lua
  if op == "balance" then return d and d.cash or 0, d and d.bank or 0 end
  if op == "spend" then ... return ctx.spend(player, math.floor(amount), label or "건물 · 생활")
  elseif op == "earn" then ... return ctx.ledger(player, "bank", math.floor(amount), label or "생활 수익")
  elseif op == "addStats" then return ctx.addStats(player, amount, label or "생활") end
  ```
  (`ctx.spend` `:358`: G.spend bank/cash, sets player attrs `Money`/`Bank`, notifies.) Used the same way by GwangalliBikes.
- Client-readable player attributes: `Money`, `Bank`, `LifeLevel`, `LifeTitle`, `OnShift`, `GwJob`, `InTaxi`,
  `LawCuffed`, `GwangalliProfileReady` (G.Attr, `$Z/ReplicatedStorage/GwangalliGameplayShared.luau:123-145`).
- Profiles (`…/Profiles.luau:467 get, 560 save`): sanitize drops unknown keys — d.cars lives in Garage's own store.
- Level perks (`$Z/ReplicatedStorage/GwangalliProgressShared.luau:424-439`): L3 `used_car_discount` 0.05,
  L8 `car_loan`, L18 `luxury_new` (owner="garage", advertised in the level UI, **not enforced anywhere**).
  Ledger classification: labels containing 환불/반환/취소/정산금 are refunds and never count as earnings (`:163, 182-196`).
  Achievements `first_car`, `car_3`; milestone `first_car` (celebration with camera) fire from d.cars automatically.
- Anti-teleport: `ctx.teleportAllowed` only consulted by Jobs during a shift (`Jobs.luau:2045`) → block our test
  drive while `OnShift` so our end-of-test teleport can never void a shift.

### 1.8 NPC / UI toolkits we reuse (all ReplicatedStorage, client+server safe)
- `GwangalliUI` (K, `$B/ReplicatedStorage/GwangalliUI.ModuleScript.luau:1-30`): tokens, K.Panel/Card/Button/
  Segmented/Tabs/Chip/Pill/Toggle/Modal/confirm/BottomSheet/Ring/MoneyLabel/EmptyState/Skeleton, `K.DialogBox(gui)`
  (`:2983`; `api.show{name, role, portrait|icon, portraitColor, text, choices={{id,label,style}}, timer}`,
  `api.onChoice`, `api.layout(mode,W,H)`, `api.hide()`), `K.toast`, `K.feedback`, `K.blur`, `K.won`, `K.Layout`.
- `GwangalliLayout`: `Layout.metrics()` (`class` e.g. "phoneP", `touch`), `Layout.onChanged`, `Layout.rect/slot`.
- `GwangalliNPCLooks` (`$Z/ReplicatedStorage/GwangalliNPCLooks.luau:1-36`): `Looks.resolve(look, seed)`,
  `Looks.build(spec, {name, humanoid=false, anchored=true, cframe})` → block R15 rig (AnimationController +
  Animator, R15 Motor6D names, parts non-colliding/massless); styles `suit`, `reception`, `office` (`:124-164`).
- `GwangalliAnim` (`$Z/ReplicatedStorage/GwangalliAnim.luau:1-60`): `Anim.play(model,"idle")`,
  `Anim.rig(model)` → `ctl:look(pos)`, `ctl:gesture("talk"|"listen"|"nod")`, `ctl:emote("bow"|"wave_small"|"give"|"thumbs"|"clap")`,
  `ctl:setDetail`, `ctl:step()` (client per frame). Default Roblox animations only.
- `GwangalliAvatarPool` (ServerScriptService add-on) fills `ReplicatedStorage.GwangalliAvatarPool` with real
  avatars (`Ready`, `Avatar_NN` with `Style="formal"`, `Gender`, `Ground`) — optional nicer look; falls back to Looks.
- HUD hide contract: any enabled ScreenGui with attribute `HideGwangalliHUD=true` (`GwangalliHUD.luau:22`).
- `CarClient` integrated shortcut: button "🚗 내 차" at top-right (AnchorPoint (1,0), y=104, 92x44) — keep clear.

### 1.9 Other dealers on the map / at runtime
- **오토바이**: GwangalliBikes add-on (`$Z/ServerScriptService/GwangalliBikes.luau`, BikeShared 3 bikes
  690k-1.89M) needs `ServerStorage.GwangalliBikes` + `Workspace.GwangalliBikeShop` (광안 모터스) — **neither is in
  v7** (probe: false; GWPB: none). Buying is prompt-only (`prompt:GetAttribute("BikeBuyId")`, `:520`); remote
  `GwangalliBikeRemotes.Request` ops are only list/spawn/store (`:557`). → at most an info tab + waypoint when present.
- **렌터카**: only Garage `rent` (큐비 하루). **중고차**: only Garage kit `grade="used"` (random cond 55-80).
- Legacy `CarServer`/`CarConfig` shop (Hatch/Sedan/SUV/Sports, "🚗 자동차 매장") is disabled in Gwangalli mode
  (`$B/ServerScriptService/CarServer.Script.luau:1-12` returns early; `CityBuilder.Build` returns `{integrated=true}`).
- No other car dealer, Dialog-driven sales NPC, catalog UI or 출고 ceremony exists. `Sign_임대 · 매매` parts are shop-rental signs.

### 1.10 Interior team (GwangalliBuildingInterior/T_garage.luau, read-only for us)
Client-side furniture under `Workspace.GwInteriorDetailLocal`. Keeps clear (`T_garage.luau:886-978`): turntable
cylinders r 8.75 to the ceiling, PriceCard fronts, GarageDesk prompt fronts, staff HRPs ±2.3, GarageReturn,
**aisles between turntable columns** (x≈-580.5..-574.2 and -556.5..-550.2, z≈430..469), **entrance** (x≈-571..-558,
z≈467..473). Builds 2 상담 테이블 sets at B(-10.4,-24.4) / (3.6,-24.4) ≈ world (-575,426) / (-561,426), 6.2x6 footprints,
with a decorative tablet '차량 비교'. It scans NPCs only inside the venue model (Scan.luau:326) → it cannot see our
NPC; it also avoids its own prompts within 6.5 studs of venue prompts only. Our NPC must therefore stand in a
spot it never furnishes (aisle/entrance keep or the gap between the two consult tables x -572..-564, z 423-429).

### 1.11 Engine / place facts
Workspace.StreamingEnabled = true (place.bin) → client may not have far models; ServerStorage invisible to
clients. Temp-studio engine lacks ViewportFrame/WorldModel (probe) → pcall + fallback; real Roblox has them.
`Players.CreateHumanoidModelFromDescription` exists in the engine.

---------------------------------------------------------------------------------------------------
## 2. What exists vs. the target

Target: walk into 광안 오토 → talk to a sales NPC → full-screen catalog of every car grouped by type →
detail (3D, colours, specs, price/할부) → 시승 or 계약 → 출고.

| capability | today | gap |
|---|---|---|
| sales NPC conversation | 박사장 is a static rig; desk prompt jumps straight to the '내 차' sheet | no talk, no lines, no personality, no greeting/look-at |
| buy kit car 신차/중고, colour, 할부 | Sheet 구매 tab (server-authoritative) | side panel only, kinds as chips |
| buy 13 models | Sheet 쇼룸 tab | no 3D preview (v7: no templates), no colours shown, no test drive |
| catalog by type | none | categories 경차/세단/SUV/밴·트럭/프리미엄/친환경/스포츠/중고차/렌트, sort/filter, compare |
| 3D preview | turntable spin of the 6 physical kit cars only | per-entry viewport, drag-rotate, recolour |
| test drive | kit kinds only, 60 s, Garage HUD; after end the Sheet pops up | models as themselves (when a template exists), result report, dealer follow-up |
| level perks | advertised (L3/L8/L18), not applied | honour L3 discount (cash-back), show L8/L18 badges; optional enforcement |
| delivery | receipt card in the Sheet | 출고 ceremony (key hand-over, plate reveal, confetti, 지금 타기) |
| dealer memory | none | visits, tested cars, wish list, returning-customer lines |
| bikes / used listings | absent in v7 | optional, behind feature detection |

---------------------------------------------------------------------------------------------------
## 3. Conflicts / risks and how we avoid them

1. **Money/ownership duplication** — never re-implement buying. All buy/rent/dismiss/call go through
   `GwangalliGarageAPI:Invoke("request", player, op, payload)` so prices, MAX_CARS, 할부, plates, saving,
   notifications, achievements stay Garage's. Our server adds only gates + cash-back.
2. **Shared rate bucket** (`Util.bucket 6/s burst 12`, Garage per-op cooldowns): compute quotes on the client with
   pure GS (`GS.loanQuote`) and call the server only for list-once/buy/test; our own bucket is stricter (see §4.3).
3. **Test-drive overlap with Garage** (one called car per player): before ours, `request "dismiss"`; refuse if
   `GarageAPI "status".testing`; while ours runs, if the car vanishes (Garage test, phone call) we end silently.
   Our test spawns through VehiclesAPI with `id="dealer_test"`, so Garage never tracks/damages it and its
   post-test Sheet never pops (that only follows Garage's own GarageEvent).
4. **Showroom placement** (server box test after 6 s): spawn our NPC only after `Workspace.GwangalliShowroom`
   has `Placed`, or immediately when `ServerStorage.GwangalliCarModels` is absent at t≥8 s (Showroom will bail).
   If templates appear later, Showroom simply treats our NPC parts as an obstacle (no overlap).
5. **Interior furniture** cannot see our NPC → NPC spots chosen in their keep zones / free gap (§4.5) and
   validated at runtime against server parts + GarageShowroomCar boxes + turntable sweeps; never inside the venue
   model; all our GUIs in PlayerGui with Adornee.
6. **Prompt clashes**: our prompt ≥ 8 studs from GaragePrompt/GarageDesk/ShowroomPrompt prompts, own
   `ObjectText`, E key, `RequiresLineOfSight=false`, range 10. GwangalliGarage ignores it (no Garage tags).
7. **Existing Sheet** stays fully usable; our dialog links to it (`GwangalliGarageOpen {tab="mine"|"rent"}`)
   and closes our UI first. Our catalog DisplayOrder 33 (above Sheet 32), dialog 36 (above GwangalliDialog 35),
   ceremony 40; set `HideGwangalliHUD` while open; avoid the top-right "🚗 내 차" button rect.
8. **Names/trademarks**: show `GS.modelName` (generic) unless `GS.SHOW_REAL_NAMES`; our spec flavour text never
   names brands.
9. **v7 has no model templates** → the 13 models would preview and deliver as the kit car of their kind.
   Server reports `available` per model (same lookup as `Spawn.modelTemplate`); `Config.SHOW_MODELS_WITHOUT_TEMPLATE`
   (default **false**: hide them from our catalog so "하이브리드 중형 세단" is not a second, pricier Sonata; when
   true they show with "출고 차량: 동급 미드 세단" fine print). Kit cars (6 × 신차/중고) + 렌트 are always listed.
10. **Old GS without MODELS / different prices**: everything derived at runtime; `GS.MODELS or {}`.
11. **Streaming**: previews come from server-made templates in ReplicatedStorage (always replicated), not from
    streamed map cars; NPC model `ModelStreamingMode=Atomic`; client tolerates a missing NPC.
12. **Teleport after test**: only when the player is > 40 studs from GarageReturn and not `OnShift`; uses
    `character:PivotTo`. Test refused while `OnShift`, `InTaxi`, `LawCuffed`, dead, or seated in a non-own seat.
13. **Level-gate inconsistency**: enforcing L8/L18 only on our path is bypassable via the Sheet →
    `Config.ENFORCE_LEVEL_GATES=false` (badges + advice only). L3 used discount honoured as a refund-labelled
    cash-back on our path (`Config.USED_DISCOUNT_CASHBACK=true`), label "광안 오토 레벨 혜택 · 중고차 5% 할인 환불"
    via GameplayAPI "earn" (refund class → no level farming; payout ≤ 5% of a purchase that already happened).
14. **DataStore**: our own small store, UpdateAsync, debounced ≥ 60 s, on leave + BindToClose, never written when the
    read failed.
15. **ViewportFrame cost on phones**: one live detail viewport; card thumbnails lazy (visible cards only, max 8 alive),
    stripped clones (no Interior, no parts < 0.15 studs); fallback to glyph tiles when ViewportFrame is missing.

---------------------------------------------------------------------------------------------------
## 4. Add-on design

### 4.1 Files (only under the allowed paths)
```
src/ReplicatedStorage/GwangalliCarDealerShared/
  init.luau        Shared: names (remotes folder, tags, attrs), VERSION, require of the children, GS/VS loaders (pcall, WaitForChild ≤ 20 s)
  Config.luau      every tunable: NPC list + spots, ranges, timings, flags, prompt texts, test-drive length, store name
  Catalog.luau     pure: builds entries from GS.CATALOG/GS.MODELS/VS.Specs (+ fallback copy of the 6 kinds),
                   categories, sort keys, spec flavour, perf bars, entry-id encode/parse/validate, price/loan maths
  Lines.luau       Korean dialogue lines (greeting variants, budget advice, after-test, owner, errors) + pick(seed)
  Util.luau        won formatting (GS.formatWon fallback), clamp/finite, rate bucket class, deep-sanitise helpers
src/ServerScriptService/GwangalliCarDealer/
  init.server.luau boot: remotes, bridges, Npc.start, Store hooks, Players events, BindToClose
  Bridge.luau      finds + wraps GwangalliGarageAPI / GwangalliVehiclesAPI / GwangalliGameplayAPI (pcall, cache, retry)
  Npc.luau         spot finding, rig build (AvatarPool formal → NPCLooks suit), prompt, attributes
  Previews.luau    ReplicatedStorage.GwangalliCarDealerPreviews: stripped preview template per entry
  Service.luau     Request handler: validation, rate limits, distance, gates, proxy to Garage, cash-back, events
  TestDrive.luau   dealer test drive (spawn, watch, report, end, return)
  Store.luau       DataStore "GwangalliCarDealer_v1" (visits, tested, wish, bests)
src/StarterPlayer/StarterPlayerScripts/GwangalliCarDealer/
  init.client.luau boot: K/GS/Layout, Net, NpcFx, Dialog, Catalog; prompt hook; public BindableEvent
  Net.luau         Request/Event wrappers, state cache (catalog snapshot, money attrs)
  NpcFx.luau       look-at, idle/talk/emotes (GwangalliAnim client-side), name tag Billboard (PlayerGui, Adornee)
  Dialog.luau      K.DialogBox in ScreenGui "GwangalliCarDealerDialog", conversation tree, optional 2-shot camera
  Catalog.luau     full-screen catalog: header, category chips, sort/filter, card grid (virtualised)
  Detail.luau      detail page/panel: viewport, colours, spec table, price/할부 box, actions, compare tray
  Viewport.luau    preview clone management, recolour (GS.applyColor), orbit/drag/zoom, thumbnails queue
  Contract.luau    견적서 + hold-to-sign modal, result handling, error copy
  Ceremony.luau    출고 overlay (blur, plate reveal, confetti, NPC give/bow, 지금 타기)
  TestHud.luau     dealer test-drive HUD (countdown chip, route beacons in Workspace.GwangalliCarDealerLocal, 시승 끝내기, report card)
```

### 4.2 Remotes (server creates `ReplicatedStorage.GwangalliCarDealerRemotes`, parented last)
- `Request` RemoteFunction `(op: string, payload: table?) -> {ok, code, message, ...}`
- `Event` RemoteEvent server→client `{k = ..., ...}`

| op | payload | server does | returns |
|---|---|---|---|
| `hello` | `{npc: string}` | visit++ (once per 5 min), picks greeting context | `{ok, npc={id,name,role}, ctx={visits, firstVisit, owned, max, testedLast?, level, lastTest?}}` |
| `catalog` | — | GS views + Garage `status` + `cars` + availability + store | `{ok, entries=[EntryView], owned=[carView], slots={owned,max}, money={bank,cash}, level, perks, loanBlocked, rentActive, testCooldown, garageReady}` |
| `buy` | `{entry, color, loan: bool}` | validate → gates → near NPC (≤ 30 studs) → Garage `request "buy"` → cash-back → Store → Event `delivered` | Garage result + `{cashback?}` |
| `deliver` | `{id}` | Garage `request "call" {id}` then VehiclesAPI `"seat"` | `{ok, meters}` |
| `testdrive` | `{entry, color}` | TestDrive.start | `{ok, seconds, route}` |
| `endtest` | — | TestDrive.stop(player,"player") | `{ok}` |
| `rent` | — | Garage `request "rent"` | Garage result |
| `wish` | `{entry, on: bool}` | Store (≤ 12) | `{ok, wish=[...]}` |
| `waypoint` | — | Garage `request "waypoint"` | `{ok}` |

Event `k`: `"test"` `{stage="start", entry, seconds, route=[Vector3], car=Model}` / `{stage="end", why="time"|"player"|"left"|"gone"|"respawn", report={topKmh, meters, seconds, entry}}`;
`"delivered"` `{entry, car=carView, receipt, cashback?}`; `"state"` (catalog refresh hint after Garage `cars` changes: client also listens to `GwangalliRemotes.GarageEvent` `kind=="cars"`); `"toast"` `{kind, icon, title, body}`.

Validation (Service): `type(op)=="string"`, `#op<=16`, op in whitelist; payload `nil|table`, ≤ 8 keys;
`entry` string ≤ 40 matching `^kit:(%l+):(%l+)$` (kind ∈ GS.CATALOG, grade ∈ {new, used}) or
`^model:([%w_]+)$` (∈ GS.MODEL_BY_ID and available); `color` ∈ GS.COLORS ids else default; `loan` boolean;
`id` string ≤ 16. Rate: own bucket 3/s burst 6 per player + per-op cooldown (buy 2, testdrive 3, deliver 2,
rent 2, catalog 1, hello 1, wish 0.5); one in-flight mutating op per player (busy lock, always released in pcall).
Distance: mutating ops need the player root ≤ `Config.CONTRACT_RANGE` (30) from any dealer NPC root
(Garage still applies its own 160-stud check). Catalog/wish/hello work anywhere (phone browsing).

### 4.3 Data schemas
EntryView (server → client; prices from GS on the server):
```lua
{ id = "kit:sedan:new" | "kit:sedan:used" | "model:k5", kind = "sedan", grade = "new"|"used",
  model = "k5"?, name = "미드 세단", full = "미드 세단", glyph = "🚗", body = "세단", seats = 5,
  price = 780000, loan = {down, daily, days, total}? , canLoan = true, tag = "첫 차 추천"?,
  cats = { "sedan", "used"? , "eco"?, "sport"?, "premium"? }, perf = { top = 135, accel = 21, brake = 46, mass = 150, drive = "FWD" },
  specText = "2.0 가솔린 · 전륜 · 복합연비 12.6km/L", blurb = "...", condRange = {55,80}?,
  available = true, preview = "kit_sedan" | "model_k5" (child name in GwangalliCarDealerPreviews) | nil,
  owned = false, tested = unix?, wished = false, lock = { level = 18, why = "레벨 18부터 출고" }? }
```
Store record (DataStore `GwangalliCarDealer_v1`, key `u_<UserId>`):
```lua
{ v = 1, visits = 0, last = 0, firstMet = false, tested = { [entryId] = unix } (≤ 30),
  best = { [entryId] = { kmh = 0, m = 0 } }, wish = { entryId, ... } (≤ 12), bought = 0, cashback = 0 }
```
Sanitised on load (types, sizes, known ids only); `canSave=false` when the read failed.

Catalog categories (Catalog.luau, multi-membership; new GS.MODELS entries auto-classified by kind/body/label/tag):
`all 전체 · compact 경차 · sedan 세단 · suv SUV · utility 밴·트럭 · premium 프리미엄 · eco 친환경 · sport 스포츠 · used 중고차 · rent 렌트`
(+ `bike 오토바이` only if `ReplicatedStorage.GwangalliBikeShared` and `Workspace.GwangalliBikeShop` exist: info + 길 안내).
Mapping: compact→경차; sedan→세단; suv→SUV; van/truck→밴·트럭; luxury kind or price ≥ 4,000,000→프리미엄;
label/blurb contains 하이브리드/전기 or glyph ⚡→친환경; tag 고성능 or body 쿠페→스포츠; grade used→중고차.
Sort: 추천순 (tag, affordability, price), 낮은 가격순, 높은 가격순, 빠른 순 (VS topKmh). Filters: 살 수 있는 차만
(bank+cash ≥ price, or ≥ 계약금 when 할부 가능), 할부 가능, 찜한 차.

### 4.4 Server modules
- **Bridge**: `garage(op, player, ...)` → `GwangalliGarageAPI:Invoke` in pcall (WaitForChild 30 s once, re-resolve if
  Parent nil); `request(player, op, payload)`; `vehicles(op, ...)`; `wallet(op, player, amount, label)`; `GS()`, `VS()`;
  `garageRoot()` (tag GarageShop), `marker(tag)`, `route()` (parse `Route` attr like Garage `routeInfo`),
  `modelTemplate(id)` (same lookup as Spawn), `kitSource(kind)` (ServerStorage.GwangalliDriveTemplates child with that
  VehicleKind → else Spawn-like map search → else GarageDisplayCar). Missing Garage → `garageReady=false`
  (catalog read-only, NPC says "전산 점검 중").
- **Npc**: waits for venue (tag GarageShop ≤ 90 s) and Showroom rule (§3.4); for each enabled Config NPC tries its
  ordered candidate spots: floor raycast (exclude our folder), footprint 2.6×6×2.6 free of server BaseParts except
  floor (`GetPartBoundsInBox`, ignore CanCollide=false decals ≤ 0.2 thick), ≥ 9.3 from turntable centres,
  ≥ 8 from every ProximityPrompt parent, outside GarageShowroomCar boxes (+1.5); builds rig (AvatarPool formal of the
  configured gender when `Ready`, else `Looks.build(Looks.resolve({style="suit", body=...}, seed), {humanoid=false})`),
  anchors root, `CanCollide/CanQuery/CanTouch=false`, Model `GwangalliCarDealer_NPC_<id>` in `Workspace.GwangalliCarDealer`,
  attrs `GwCarDealerNpc=id`, `NpcName`, `NpcRole`, `DefaultTab`; tag `GwCarDealerNpc`; Attachment "PromptAnchor" at chest
  with ProximityPrompt (ActionText "상담하기", ObjectText "한서윤 대리 · 영업 컨설턴트", E, Hold 0, range 10,
  attr `GwCarDealerNpc`). No server animation (clients animate). Logs the chosen spot.
- **Previews**: once at start (after Npc spot wait, `task.wait` every 2 models): for each kit kind and each available
  model clone the source, strip scripts/prompts/sounds/lights/particles/constraints/Seat welds, keep BaseParts +
  Decals/SurfaceAppearance/SpecialMesh, anchor, collisions/queries off, pivot at origin, attrs `Entry`, `PaintRef`;
  cap `Config.PREVIEW_MAX_PARTS` (400) by dropping smallest parts; `ReplicatedStorage.GwangalliCarDealerPreviews`
  `Ready=true` when done.
- **Service**: handlers above; `catalogFor(player)` merges Catalog entries + Garage `status`/`cars` + Store; gates:
  `level = player:GetAttribute("LifeLevel") or 1`; `lock` for loan < 8 / luxury-new < 18 only when
  `ENFORCE_LEVEL_GATES`; cash-back after a successful used purchase when level ≥ 3:
  `wallet("earn", player, round100(price*0.05), "광안 오토 레벨 혜택 · 중고차 5% 할인 환불")`.
  Optional pass hook: entries with `pass` key check `ServerStorage.GwangalliPassesAPI:Invoke("has", player, key)` if present.
- **TestDrive** (own flow, `Config.TEST_MODE="dealer"`; `"garage"` = proxy Garage `testdrive {kind,color}`):
  refuse when `OnShift`, `InTaxi`, `LawCuffed`, dead, active test (ours or Garage `status.testing`), cooldown
  (`Config.TEST_COOLDOWN` 45 s), far from NPC. `request "dismiss"`; `vehicles("spawnOwned", player, {id="dealer_test",
  kind, model = available and id or nil, color=GS.color3(c), colorId=c, plate="시승 "..4 digits, cond=100, dirt=0,
  label=name.." 시승차", testDrive=os.time()+secs}, {near=GarageSpawn.Position, cframe=groundFrame(GarageSpawn),
  radius=200, force=true, seat=true})`. 4 Hz watcher: top speed (root AssemblyLinearVelocity → VS.kmh), metres
  (×0.3), driver `DriveDriver==UserId` else leftAt; end on time (`Config.TEST_SECONDS` 75), left > 5 s (after 4 s
  grace), model gone, CharacterAdded/Humanoid.Died, PlayerRemoving. End: `vehicles("eject", model)`, wait 0.2,
  `vehicles("despawn", player)` only if `vehicles("current", player) == model`; return teleport (§3.12); Event
  `test end` with report; Store tested/best.
- **Store**: load on PlayerAdded (retry ×3), save debounced/leave/close.

### 4.5 NPCs (Config)
```lua
NPCS = {
  { id = "consult", enabled = true, name = "한서윤 대리", role = "영업 컨설턴트", body = "f", style = "suit",
    tab = "all", spots = {
      { pos = Vector3.new(-568.2, 0, 426.8), face = Vector3.zAxis },   -- 브랜드 월 앞, 상담 테이블 두 세트 사이 (y from floor ray)
      { pos = Vector3.new(-577.4, 0, 449.8), face = Vector3.zAxis },   -- 1번 통로 교차점 (interior aisle keep)
      { pos = Vector3.new(-570.8, 0, 468.6), face = Vector3.zAxis },   -- 입구 왼쪽 (entrance keep)
  } },
  { id = "used", enabled = false, name = "정우진 과장", role = "중고차 · 렌트 담당", body = "m", style = "suit", tab = "used", spots = {...} },
}
HOOK_OWNER_DESK = false  -- true: client locally disables 박사장 desk prompt and puts a local "상담하기" prompt on the same
                         -- anchor that opens our dialog (with "내 차 관리" → GwangalliGarageOpen{tab="mine"}); restored on error
```
Distances checked: spot 1 is 18 studs from the desk prompt and 22 from the nearest PriceCard; spot 2 is 8.7 from the
SUV card and ≥ 15 from all turntable centres. Final spot is logged and must be screenshot-verified in studio.

### 4.6 UI screens (K kit only, Korean, mobile/PC/gamepad)
1. **NPC name tag** (BillboardGui in PlayerGui, Adornee = NPC head, MaxDistance 30): "💬 한서윤 대리" / "영업 컨설턴트 · 차량 상담".
   Within 14 studs the NPC looks at the player; first approach per visit → `wave_small` + bubble "어서 오세요! 광안 오토입니다 😊".
2. **Dialog** (K.DialogBox, ScreenGui DisplayOrder 36, optional over-the-shoulder 2-shot camera, NPC gesture "talk"):
   first visit "안녕하세요, 광안 오토 영업 컨설턴트 한서윤입니다. 어떤 차 찾고 계세요?"; returning "또 오셨네요, {이름}님!
   지난번에 시승하신 {차} 아직 고민 중이세요?"; owner "{차} 잘 타고 계세요? 정비는 옆 정비 베이 김기사님께 맡기시면 돼요."
   Choices: [🚗 전체 차량 보기] [💰 예산에 맞는 차 추천] [🏁 시승하고 싶어요] [⏱ 하루 렌트] [🔑 내 차 관리] [닫기].
   Budget branch: "예산은 어느 정도 생각하세요?" [50만 원 이하] [150만 원 이하] [500만 원 이하] [상관없어요] → NPC line with her
   pick ("첫 차라면 큐비 중고가 제일 무난해요. 150,000원이면 바로 출고돼요!") → catalog filtered + pick highlighted "추천".
   Shortfall: "지금 잔액으로는 {부족}원이 모자라요. 할부로 하시면 계약금 {계약금}원이면 돼요." / "알바 몇 번 더 하시면 금방이에요!"
3. **Catalog** (ScreenGui "GwangalliCarDealerUI" DisplayOrder 33, HideGwangalliHUD, controls off on touch):
   header "광안 오토 · 차량 카탈로그", 통장/현금 chips (live from `Bank`/`Money` attrs), "내 차고 {n}/3" chip (→ Sheet mine), ✕;
   category chips (horizontal scroll); sort Segmented + toggles 살 수 있는 차만 / 할부 가능 / 찜; "오늘의 추천" banner (daily seed);
   card grid — phone portrait 1 column row cards (thumb 120 px left), phone landscape 2 columns, tablet/PC 3-4 columns
   with the detail panel docked right (38 %). Card: 3D thumb or glyph tile, name, body·인승, price (신차/중고), "할부 시 계약금
   {x}원 · 하루 {y}원 × 10일", tags (첫 차 추천 / 드림카 / 고성능 / 최저가 / 중고 상태 55~80%), badges 보유 중 / 시승 완료 / 찜 ❤ / Lv.18.
4. **Detail**: big viewport (auto-spin 18°/s, drag rotate, pinch/wheel zoom, double-tap reset), 8 colour swatches
   (recolour clone, name "레드"), spec table 최고속도 · 구동 · 승차 인원 · 연료/연비 text · 5-dot bars 가속/제동/승차감;
   신차/중고 segmented (kit only), 할부 toggle with quote lines 계약금 / 하루 납입 × 10일 / 총 납입 (이자 5%); disabled
   reasons; actions [🏁 시승하기 (75초)] [🛒 계약하기] [❤ 찜] [비교 담기]; compare tray (2 cars side by side).
5. **Contract** (K.Modal): 견적서 — 차량, 색상, 등급, 결제(일시불/할부), 금액, 결제 계좌 "통장 우선 · 부족하면 현금", 번호판
   "부산 번호판 자동 발급", 혜택 "레벨 3 혜택 5% 환불"; hold-to-sign button "길게 눌러 서명하기" (0.8 s ring) → buy; errors
   from Garage `message` shown verbatim (already Korean).
6. **출고 ceremony** (DisplayOrder 40, K.blur): "🎉 출고를 축하드려요!" car name, plate reveal (letters flip
   "부산12가 3456"), 계약 요약, confetti frames, NPC `give` → `bow` emotes, `K.feedback("money")`; [🚗 지금 타기] (deliver op)
   [나중에 탈게요] ("'내 차'에서 언제든 부를 수 있어요" toast).
7. **Test HUD**: top chip "🏁 시승 중 · 52초" + "다음 지점 230m ▶ (3/11)", glowing beacon at the next route point
   (client parts in `Workspace.GwangalliCarDealerLocal`), [시승 끝내기]; end card "시승 리포트 — 최고 132km/h · 1.4km · 75초"
   → [계약하기] (opens Detail on that entry near the NPC) [다른 차 보기] [닫기]; NPC line "시승 어떠셨어요? 승차감 괜찮죠? 😄".
Input: gamepad — catalog opens with SelectedObject = first chip/card, LB/RB switch categories, B closes/back,
X toggles 찜, Y opens detail actions; PC — Esc/Backspace back, wheel scroll, 1-9 category hotkeys; touch targets ≥ 56 px.
Reduced motion respected via `K.reduced()`.

### 4.7 Player flows
1. **Browse + buy (cash)**: enter showroom → name tag + wave → E "상담하기" → dialog → "전체 차량 보기" → catalog →
   SUV → 트레일 SUV 신차 → colour 레드 → 계약하기 → 견적서 → hold to sign → server: validate, near NPC, Garage buy
   (bank→cash) → Event delivered → ceremony → 지금 타기 → Garage call + seat → driving.
2. **할부**: same with 할부 toggle; card shows 계약금 = 30 %; Garage charges daily (existing). Missed-loan players see
   "밀린 할부가 있어서 새 할부를 할 수 없어요" (Garage message) and the toggle disabled from `loanBlocked`.
3. **Test drive**: detail → 시승하기 → server dismisses called car, spawns test car at GarageSpawn seated → HUD + route
   → time/end → eject, despawn, back at GarageReturn → report card → 계약하기 → contract.
4. **Budget advice**: dialog → budget → filtered catalog with pick.
5. **Rent**: dialog "하루 렌트" → Garage rent (car appears at the lane) → toast.
6. **내 차 관리 / 팔기 / 정비**: dialog → closes ours → `GwangalliGarageOpen:Fire({tab="mine"})`.
7. **Phone/remote**: `LocalPlayer.GwangalliCarDealerOpen` BindableEvent `:Fire({tab?, entry?})` opens the catalog
   anywhere (read-only; 계약/시승 buttons say "매장에서 상담원과 계약할 수 있어요" + 길 안내 = Garage `waypoint`).
8. **Errors**: loading ("차 정보를 불러오는 중이에요"), max cars ("차고가 가득 찼어요 (3/3) · 한 대를 팔면 살 수 있어요" + 내 차 버튼),
   owned model ("이미 가진 차예요"), insufficient, cooldown ("{n}초 뒤에 다시 시승할 수 있어요"), on shift ("근무 중에는 시승할 수 없어요").

### 4.8 Verification plan
Offline (mock runtime `scratchpad/bprev/lib/rbx.luau` copies in `$D`): Catalog build/categories/sort for old + new GS,
entry-id parsing/validation fuzz, Service validation table (bad types, NaN, long strings), bucket/cooldowns, Store
sanitise/merge. Studio (one run at a time, `flock …/.studio.lock timeout 1500`): NPC spot + screenshot from the door,
dialog/catalog screenshots at 390×844 and 1920×1080, buy via server (`GameplayAPI earn` money → `Service` buy) checks
d.cars/plate/cash, dealer test start/end with `Config.TEST_SECONDS` override attribute, ceremony screenshot.
