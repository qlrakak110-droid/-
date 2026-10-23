# gw-feature (wf_34d7f991-e42)

- status: completed
- failed agents (never finished, usually the usage limit): build:crew, fix:crew, review:crew:correctness, review:crew:experience, test:crew

## research:crew

# GwangalliShopCrew: research and design (v1)

Feature: interactable shop staff ("크루") that greets, takes orders, relays them to a visible cook, carries the dish on a tray and serves the table, clears tables, answers questions and remembers regulars, with optional NPC diners and an optional "일손 돕기" mini shift.

Everything is an add-on. It finds the place's systems at runtime with pcall, timeouts and fallbacks. It edits no place script.

Allowed paths:
- `src/ServerScriptService/GwangalliShopCrew/`
- `src/StarterPlayer/StarterPlayerScripts/GwangalliShopCrew/`
- `src/ReplicatedStorage/GwangalliShopCrewShared/`
- the scratch dir `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/crew/`

---------------------------------------------------------------------------------------------------

## 0. TL;DR

1. **Use the ShopLife Bus.** `ServerStorage.GwangalliShopLife {Event, Request}` was built for this feature. ShopLife cooks and owns orders, bills, dishes and seats. Staff plug in through these ops:
   - `staffMode {serve=true}`
   - `queue`
   - `serve {orderId}`
   - `claimSeat`, `npcOrder`, `npcEat`, `npcLeave`

   In the place file no system uses these ops today.
2. **There are two "v7"s.**
   - `place.bin`: 523 scripts, dumped to `bld/src`.
   - The owner's studio HTML adds a pack of 385 add-on entries on top. The merged view is `bld/eff`.

   The add-on pack already contains a basic waiter, **`ServerScriptService.GwangalliShopService`**. It runs one waiter per open table shop, uses PathfindingService and `staffMode serve`, carries a tray, shows bubbles, and has no interaction.

   Our crew must either take it over (default) or coexist with it. It must never double-serve or fight over `staffMode`.
3. **Today's gaps:**
   - 50 table-service shops (211 tables, 793 seats). 23 of them have no cashier anchor, so `ShopStaff` puts nobody there. In `place.bin` they are completely unstaffed.
   - No visible cook.
   - No NPC diners.
   - Staff only say canned lines.
   - No regular-customer memory.
   - No table clearing.
   - Annex rooms have no staff at all.
4. **Design:**
   - A server brain per crewed shop with up to three roles (cook / waiter / cashier).
   - Rigs follow the existing NPC attribute contract. They are tagged `GwShopStaff` and live in `workspace.GwangalliShopStaff`, so GwangalliNPCClient animates them for free.
   - Paths come from our own deterministic grid planner, which follows the client interior's kept aisles (service point to each table).
   - Tray and dish visuals are built on the client from `FoodKit`.
   - Dialogs use `GwangalliUI.DialogBox`.
   - A 단골 (regular) system: visit days, 도장 쿠폰 stamps, 서비스. Saved in our own DataStore.
   - A hard serve guard, so no order can ever get stuck.

---------------------------------------------------------------------------------------------------

## 1. Sources and conventions

| Name | Path (scratchpad-relative) | Notes |
|---|---|---|
| place-only scripts | `bld/src/<Service>/<Path>.<Class>.luau` | 523 scripts, exactly what is in `v7place/place.bin` |
| **effective** scripts | `bld/eff/<Service>/<Path>.luau` | `bld/src` + `v7all/gen/addons.json` overlays (the studio HTML's add-on pack, 385 entries, many "upsert" replacements). This is what the owner's studio runs. Line numbers below are from `bld/eff` unless marked *(src)*. |
| map | `v7place/place.bin` (GWPB) | 141 ShopLife candidate shops: 134 street shops (`Model` with `Interior` + `ShopFloor`) + 7 GwShop. My census scripts: `feat/crew/py/shops_scan.py` → `shops_scan.json`, `layout.py`, `dest.py`, `feat/crew/lt/cls.luau` (Luau CLI + real `StreetShops` classifier) |

Add-on-only scripts that matter here (present in `bld/eff`, absent from `place.bin`):
- `GwangalliShopService` (waiter)
- `GwangalliStaticNpcSkins`
- `GwangalliAvatarPool`
- `GwangalliGameplay/WorkPlacement` (+`NpcPort`)
- `GwangalliPath`
- the alcohol-free `StreetShops` rename

Upserted versions also differ from the place file:
- `ShopLife` (+645 lines: 합석 / N빵 / 주문해 주기 through the Together bridge)
- `GwangalliNPCClient`, `GwangalliAnim`, `GwangalliNPCLooks` (real avatars), `ShopStaff`, `Jobs`

The design must work in both worlds, which is why every integration point has a fallback.

---------------------------------------------------------------------------------------------------

## 2. Existing systems and exact integration points

### 2.1 ShopLife core: `ServerScriptService.GwangalliBuildings.ShopLife`

ShopLife is a ModuleScript child of the `GwangalliBuildings` Script, started by it. When its services are up, the Script sets `workspace:SetAttribute("GwB_Ready", true)` (`GwangalliBuildings.luau:207`).

**Scope and lifecycle**
- It turns every map shop into a working one: prompts, orders, cooking timers, dishes, seats, bills.
- Its header says plainly: "NPCs: not created or moved here … NPC customers / staff can be plugged in through its Request ops (claimSeat, npcOrder, staffMode, markReady, serve ...)" (*src* `ShopLife.ModuleScript.luau:17-20`).
- `ACTIVATE = 75` / `DEACTIVATE = 120` studs (`ShopLife.luau:66-67`).
- `activate(shop)` (`:1576`) builds `Workspace.GwangalliBuildingsShopLife/<shopKey>/Anchors/*`. These are invisible 1×1×1 parts with ProximityPrompt `LifePrompt`, `MaxActivationDistance 6.5`, `AlwaysShow`, attribute `LifeKind`. Anchor names: `Cook`, `Order` (계산하기 / 주문하기 / 키오스크 주문), `Pickup`, `Table_<n>` (앉기), `MenuBoard`, `Restroom`, `Bin`, `Water`, …
- It emits Bus `open` at the end (`:1779`). `deactivate` (`:1806`) emits `close`. It does **not** reset `shop.staff`.

**Dishes**
- Dishes live in `<shop folder>/Dishes` (`dishFolder`, `:600`) as `Dish_<id>` / `Setting_<id>` models.
- The presence tick removes a done dish 25 s after its owner left (`:2990`, `if d.done and d.doneAt and t - d.doneAt > 25 and not present then removeDish(d)`).

**Kitchen: the serve gate** (`:1346-1388`)
```lua
elseif o.phase == "cooking" and o.readyAt and t >= o.readyAt and not staff.cook then
    o.phase = "ready"
    Bus.emit("ready", shop, { orderId = o.id, item = o.item.id, number = o.number, where = o.dest })
    if o.dest == "table" then
        if not staff.serve then
            task.delay(0.8, serveOrder, o)      -- (no staff: ShopLife puts it on the table itself)
        end
    else
        serveOrder(o)
    end
...
elseif o.phase == "ready" and t - (o.readyAt or t) > 240 then
    -- never picked up / the customer never sat down: the shop lets it go
    orders[o.id] = nil
```
**Risk:** with `staff.serve = true`, a table order nobody serves is silently deleted after 240 s. A 후불 bill was already added at order time, so the player pays for nothing. This is why the serve guard (§5.9) is mandatory.

**Serving**
- `serveOrder` (`:1286`) spawns the dish at `seat.spot`, emits `served`, sends the shop line and the `life.fx served` effect.
- If the owner is not seated, it sets `o.waitSeat = true` and re-serves when they sit (`sit()`, `:1197`).

**Player remotes**
- `ReplicatedStorage.GwangalliBuildingsRemotes.{Request (RemoteFunction), Event (RemoteEvent)}`, through `Registry.on`/`Registry.fire`.
- Ops (`:3578-3619`): `life.order`, `life.act` (`{action="order"|"eat"|"water"|"banchan"|"rice"|"season"|"cheers"|"pay"|"stand"|…}`), `life.payMode`, `life.pay {shop}`, `life.pick`, `life.checkout`, `life.service`, `life.pour`, `life.state`.
- `handleAct "order"` fires `life.fx bell`, emits Bus `call`, and opens the menu (`:2486-2510`). In other words, the seated 🔔 주문 button **is** the 호출벨.
- A full table gives the toast "빈 자리가 없어요" (`:2025`).

**Read-only module API** (tests/tools, `:3838-3877`):
```lua
function ShopLife.byKey(key)  -- full shop rec (see 2.4)
function ShopLife.session(p)  -- (creates one if missing)
function ShopLife.dishes()    function ShopLife.orders()
function ShopLife.prompt(p, key, kind, data)   function ShopLife.sitAt(p, key, tableId?)   function ShopLife.ready()
```

### 2.2 ShopLife Bus: `ServerStorage.GwangalliShopLife` (`ShopLife/Bus.luau`)

Contract rules (`Bus.luau:12-15`):
- kinds and ops are append-only
- a field keeps its meaning
- shop keys are stable (`"<model name>@<x>,<z>"` or attribute `ShopLifeKey`)
- an unknown op returns `{ok=false, code="unknown_op"}`
- `Request:Invoke` never errors: it is pcall'd and returns `{ok=false, code="error"}`

**Events** (`Bus.luau:22-47`). Every payload carries `v`, `shop`, `shopName`, `shopType`, `t`:
`enter {userId}`, `leave {userId, unpaid}`, `seat {userId|npc, table, seat, cf}`, `stand`, `order {orderId?, userId|npc, items={{id,name,qty,price}}, table?, seat?, prepaid, number?, forUserId?}`, `cooking {orderId, item, station, seconds}`, `ready {orderId, item, number?, where="table"|"pickup"}`, `served {orderId, item, table?, seat?, cf, userId|npc}`, `pickup`, `bite`, `finished`, `paid {userId, total, items, auto, mode?, covered?, group?}`, `dash`, `call {userId, table}`, `cheers`, `trash`, `restroom`, `pick`, `checkout`, `service`, `grill {action="put"|"flip"|"cut"|"burnt"|"take", dish?}`, `water`, `open`, `close`.

Note: **player** `order` events carry `orderId = nil` (`ShopLife.luau:2470`). Map them through the `queue` op, the way ShopService's "[검토 수정]" block does (`GwangalliShopService.luau:662-678`).

**Ops** (`Bus.luau:49-64`):
```lua
"shops", -- {} -> { shops = { { key, name, type, menu, center, door } } }
"shop", -- { shop } -> { shop = { key, name, type, menu, stations = {...}, tables = {...} } }
"menu", -- { shop } -> { items = { { id, name, price, cat } } }
"claimSeat", -- { shop, npc, table? } -> { seat, table, cf }      an NPC customer takes a free seat
"releaseSeat", -- { shop, npc }
"npcOrder", -- { shop, npc, items = { id | { id, qty } } } -> { orderId }  dishes go to the NPC's seat
"npcEat", -- { shop, npc, seconds? } -> {}  the NPC's dishes empty over `seconds`
"npcLeave", -- { shop, npc } -> {}  the NPC's dishes stay a while, then are cleared
"staffMode", -- { shop, on, roles? = { cook = true, serve = true } } -> {}  staff NPCs cook / serve
"queue", -- { shop } -> { orders = { { orderId, item, phase, table?, seat?, number? } } }
"markCooking", "markReady", "serve", -- { orderId } -> {}
"say", -- { shop, text, who? } -> {}  show a staff line to the players in the shop
```

Implementation notes:
- `shopInfo(shop, full)` (`ShopLife.luau:3039-3063`):
  - `tables[i] = {id, kind, center, seats = {{id, cf, taken}}}`
  - `stations = {order, pickup (Scan.front of pass|counter), cook (CFrame), restroom, door}`
- `staffMode` (`:3185-3196`): `shop.staff = { cook = roles.cook == true, serve = roles.serve == true }`, or `nil` when `on == false`.
- `serve` (`:3231-3237`) requires `phase == "ready"`.
- `claimSeat` (`:3089`) activates the shop and marks `seatsTaken[seat] = npc`.
- `npcOrder` (`:3121-3142`) places a prepaid table order (no money involved). It also places the 반찬 setting when the type has banchan.

### 2.3 Other GwangalliBuildings modules (same cached tables, required after `GwB_Ready`)

Precedent: `Play.Grill` does exactly this:
```lua
-- GwangalliGameplay/Play/Grill.luau:1683-1715
if workspace:GetAttribute("GwB_Ready") ~= true then return false end
local gb = ServerScriptService:FindFirstChild("GwangalliBuildings")
local function req(name) local m = gb:FindFirstChild(name) ... pcall(require, m) end
local Reg = req("Registry")
if not Reg or type(Reg.handlers) ~= "table" or type(Reg.fire) ~= "function" then return false end
B.Registry = Reg; B.ShopFlows = req("ShopFlows"); B.Needs = req("Needs"); B.Interact = req("Interact")
```

| Module | API we use | file:line |
|---|---|---|
| Registry | `Registry.handlers[op](player, payload)`: call ShopLife's own validated handlers server-side (`life.act`, `life.pay`). `Registry.fire(p, kind, data)`, `Registry.toast(p, text, kind)`, `Registry.now()`, `Registry.pos(p)`. Rate bucket `RATE, BURST = 12, 24` applies to client calls only. | `Registry.luau:26,37,170-188,203,245` |
| Economy | `Economy.balance(p)`, `Economy.spend(p, amt, label) -> ok,msg`, `Economy.earn(p, amt, label)` (bank through HostBridge, else 건물 크레딧) | `Economy.luau:52,66,101` |
| Needs | `Needs.apply(p, {Satiety=..,Energy=..,Fun=..,Hygiene=..}, stats?, label?)`: player attributes `GwB_<Need>`, toast `needs.delta` | `Needs.luau:30`; config `GwangalliBuildingsShared/Config.luau:142` |
| Interact (buildings) | `Interact.give(p, item)`, `Interact.held(p)`: the HOLD system. A carried food item has the same shape as ShopLife's `giveItem` (*src* `ShopLife.ModuleScript.luau:1248-1290`) | `Interact.luau:160,200` |

### 2.4 What a ShopLife shop record contains (`ShopLife/Scan.luau`)

`Scan.shop(model, kind, index)` (*src* `Scan.ModuleScript.luau:182-596`) returns `rec` with:
- identity: `key, name, type, menuKey, def (TYPES entry), model`
- footprint: `frame` (horizontal CFrame at floor level), `sx`, `sz`, `floorY`, `door` (Vector3 of the AutoDoor model, else front centre), `center`
- named parts: `kiosk, pos, counter, cook, cookName, pass, display, tap, tank, cutting, espresso, menuBoard, hotwater, microwave, atm, deskBell, mailbox, trayStation, tester, restroom, bins, water, points (GwShopPoint), shelves`
- `tables`: `{ id, part, top, center, min, max, kind ("table"|"low"|"bar"|"counter"|"grill"), seats, grill, tray, gw }`
- `seats`: `{ id, part, top, cf (lookAt the table), real, table, spot }`. `spot` is where the dish lands, at the table top, 0.7-0.75 studs in from the edge facing the seat.

Names read include ChairSeat/StoolSeat/Stool/Seat/Cushion…, TableTop/LowTableTop/BarTop/CounterTop/PassTop…, PosBase/OrderKiosk…, the COOK_PRIORITY list, PASS_NAMES (`PassLedge, PassTop, PassTray, KitchenPass, PassCounter, DripTray`), menus, bins, water (`Scan.ModuleScript.luau:27-58`).

`Scan.inside(rec, pos, pad)`, `Scan.front(rec, part, dist)` (customer side, toward the door) and `Scan.freeSpot(rec, size, ignore)` are exported (`:598-650`).

### 2.5 Shop types, flows, menus and lines: `ReplicatedStorage.GwangalliBuildingsShared.StreetShops` (pure data)

- `SS.TYPES[type] = {label, icon, flow = "table"|"kiosk"|"counter"|"pick"|"service", ui, pay = "post"|"pre", water, banchan, grill, accent, staff?}` (`StreetShops.luau:32-64`).
- `SS.classify({names})` / `SS.classifyContents(props)` / `SS.menu(key)` / `SS.item(menuKey, id)` / `SS.line(type, key, seed)` / `SS.won(n)` (`:1185-1290`).
- Menu items: `{id, name, price, desc, icon, dish, tint, cat ("main"|"side"|"drink"|"alcohol"|"dessert"|"goods"), eat, bites, cook (s), fx ("boil"|"fry"|"grill"|"espresso"|"pour"|"tap"|"chop"|"scoop"|"steam"|…), effect, stats, share, rice, scissors, grill, opts}`.
- `SS.LINES[type] = {greet, order, served, bye}`. ShopLife shows these as the shop's "voice" chip (`life.line` → "💬 사장님: …").
- **The effective build is alcohol-free**:
  - 소주 → "청포도 소다", 맥주 → "무알콜 맥주 (병)", 하이볼 → "제로 하이볼", 사케 → "유자차".
  - pub icon 🍹; ShopStaff pub lines "무알콜 생맥", "수제 에이드"; `cat` stays `"alcohol"`.
  - Diff: `bld/src/.../StreetShops.ModuleScript.luau` vs `bld/eff/.../StreetShops.luau`, e.g. eff `:273`.
  - **Our lines must never name alcohol.** Item names always come from `SS.item` at runtime.

Census of the 141 map shops, classified with the real classifier:

| flow | shops | notes |
|---|---|---|
| table | **50** | 211 tables, 793 seats. Types: soup 9, noodle 4, pocha 6, grill 4, rawfish 8, seafood 3, pub 12, chicken 2, … **23 of the 50 have no cashier anchor** (no PosBase/Counter/…) → ShopStaff gives them nobody. Examples: 광안 돼지국밥, 남천 해장국, 광안 밀면, 1984 이바구밀면, 새벽집, 해변포차, 광안 곱창, 민락 복국, 조개구이 shops |
| kiosk | 35 | cafes (PosBase + EspressoBody/GroupHead + DripTray), burger (OrderKiosk + KitchenPass/PassLedge) |
| counter | 8 | snack/dessert |
| pick | 16 | cvs/bakery/retail |
| service | 24 | pharmacy, lobby, residence, realty, laundry, salon |
| unclassified | 8 | |

### 2.6 NPCs that exist in or around shops today

| System | Where / what | Count | Interaction | file:line |
|---|---|---|---|---|
| **ShopStaff** (GwangalliGameplay feature module) | One counter rig per storefront with a cashier anchor (`ANCHORS = {"PosBase","CashierPanel","OrderKiosk","FrontDesk","BackBar","POS","BarCounter","바 카운터","안내 · 접수 카운터","Counter"}`). It stands behind the counter (free 1.6×2.6×1.6 box). Rigs live in `workspace.GwangalliShopStaff`, tag `GwShopStaff`, `NpcKind "shop"`, attribute `ShopStaff = <label>`. Streams `ON_R/OFF_R = 150/180`, `MAX_ACTIVE 36`. Acts change every 20-40 s. Says "어서 오세요" once a minute within 11 studs. It skips counters with clerks/venue staff within 9 studs, and anything within 45 studs of the `JOB_SITES` destinations "스타벅스 광안리점" and "GS25 광안리점". It also adopts the 9 static `GwShopClerk` rigs. Sites are scanned **once** at +6 s. | ~400 sites, ≤36 live | Prompt `StaffTalk` "말 걸기" (E, 9 studs): canned greet/talk lines. No orders, no pay. | `ShopStaff.luau:34-40, 327, 361-372, 642-689, 706-745, 832-886` |
| **GwShopClerk** static rigs | Inside `Workspace.Gwangalli.shops.<shop>.Interior`: 행복 돼지국밥 (주방 이모 = cook, 사장님), 광안 치킨 (사장님, 주방), 광안 떡볶이 (분식 이모), 바다약국 (약사님), 헤어살롱 물결 (원장님), 바다옷장, 광안 서프 | 9 | through ShopStaff adoption | `bld/shops.json` |
| **GwangalliShopService** *(add-on pack only)* | One "서빙 알바" per open **table-flow** shop. Spawned on Bus `open`, dropped on `close`. NpcId `waiter_<key>`, attribute `GwWaiter = key`, tag `GwShopStaff`, in `workspace.GwangalliShopStaff`. Calls `staffMode {cook=false, serve=true}`. Uses PathfindingService (`AgentRadius 1.3`), `WALK 8.5`, `SERVE_TIMEOUT 25`, server-side tray parts with `Prop="cup"`, a BillboardGui `StaffBubble` on the head. Its voice is the nearest non-waiter `GwShopStaff` rig within 32 studs of the pass. Lines: greet / seat / orderAck / serve / pickup number / call / paid / leave. | ≤1 per open table shop | **none** (no prompt) | `GwangalliShopService.luau:1-60, 26-27, 265-290, 305-345, 409-461, 463-475, 603-613, 662-678, 691-750, 754, 801-815` |
| GwangalliStaff (점장 모드) | NPC 알바 at 스타벅스 광안리점 / GS25 광안리점 only, while the store is opened in 점장 모드. Rigs `GwStaff_<id>`, `NpcKind "shop"`, attribute `GwStaff`. API `ServerStorage.GwangalliStaff.API`. | ≤3 per store | manager UI | `GwangalliStaff.luau:1-60, 1000-1025` |
| Customers / JobWorld / Play.Career.Cafe | Job customers at the cafe/GS25 counters (`workspace.GwangalliNPCs`) | — | job flows | `Customers.luau:1-40` |
| Play.Career.Gukbap | 국밥집 알바 shift at **행복 돼지국밥**: its own customer parties + the player serving. `OnShift = true`, `Job = "gukbap"`. | — | career UI | `Gukbap.luau:1-14, 2003, 2076, 2221` |
| Play.Pocha | Owner actor + seats + ordering at the 5 tent 포장마차 and the indoor **"민락 포장마차"** (also a ShopLife shop!) | — | pocha UI | `Play/Pocha.luau:1-20` |
| HoeHall (횟집 job) | 활어직판장 hall at about (-2640, -24), `GwHoeHallOpen`. Not one of the 141 ShopLife shops. | — | job | `NPC.luau:225-240`, `GwangalliWorkSpots.luau:124-135` |
| Builder/Shops static figures | District shops (ShopFlows), x≈4283: anchored figures, no Humanoid. Out of scope. | — | — | `Builder/Shops.luau:85-130` |

### 2.7 NPC rig / animation contract (reuse everything)

**NPC.luau contract** (header `GwangalliGameplay/NPC.luau:22-37`):
- rig anchored at `HumanoidRootPart`
- model attributes:
  - `NpcId` (string, required by the client), `NpcKind`
  - `NpcGround` (root height above the feet, usually 3)
  - `NpcAct` (an `GwangalliAnim.ACTS` key)
  - `NpcYaw` (degrees)
  - `NpcLeg`: either a straight leg `"x0,y0,z0,x1,y1,z1,t0,dur"` or a polyline `"P;t0;speed;x,y,z;…"` (server clock `workspace:GetServerTimeNow()`)
  - `NpcLook` / `NpcTalk` (UserId)
  - `NpcEmote` `"name#seq#serverTime"` (plays only if under 3 s old)
  - `NpcKnock`, `NpcSeat`
- prop parts carry `Prop = "phone"|"cup"|"rag"|"clipboard"` and are shown while the act's prop matches.

**GwangalliNPCClient** (LocalScript) animates every Model tagged `GwShopStaff`, wherever it is (`GwangalliNPCClient.luau:1610-1625`). It needs a string `NpcId` and a `HumanoidRootPart`/PrimaryPart (`addModel`, `:527-540`). It handles walk interpolation, smooth turning, acts, emotes, head look and LOD.

**GwangalliAnim** (`ReplicatedStorage`):
- `Anim.ACTS` (`:733`): idle, look, chat, talk, listen, phone, eat, cup (`walkPose="cup"`), sit (`pose sit_bench`), wipe (prop rag), cook, flip, chop, clipboard (`walkPose`), behind (hands_behind, `walkPose`), teller, typing, lean, arms_crossed, shop, walk, …
- `Anim.POSES` (`:410`) includes `tray = { LeftShoulder = {22,0,8}, LeftElbow = {88,0,0} }` (`:428`), but **no ACT uses it**.
- Emotes include bow, nod, wave, clap, thumbs, give, receive, beckon.
- `Ctl:_applyAct` falls back to `ACTS.idle` for unknown acts. The ACTS table is read at use time, so a client script can *add* keys (append-only) safely.

**GwangalliNPCLooks**:
- `Looks.random(seed, hint)`, `Looks.resolve(look, seed)`, `Looks.build(spec, {name, anchored=true, shadow=false})` → `rig {model, root, head, parts, motors, ground, …}` (`:326, 196, 1173`).
- Effective build only: on the server, `Looks.build` clones a **real Roblox avatar** from `ReplicatedStorage.GwangalliAvatarPool` (uniform looks `u_apron`, `u_chef`, … for role styles). Fallback: the block rig. `AVATAR_MAX = 90` live avatars for the whole server (`:1007-1030, 1015`).
- STYLES: `apron, chef, black, suit, casual, office, street, fisher, granny, grandpa, tourist, …` (`:123-161`).

### 2.8 Speech bubbles, dialog UI kit, screen slots

- **Bubble pool**: GwangalliBump (client) creates `LocalPlayer.GwangalliBubble` (BindableEvent) with `Fire(adornee, text, typeId, dur, offsetY)`. It holds ≤10 bubbles at 40 studs (`GwangalliBumpShared.luau:33, 312`; `GwangalliBump.luau:57-69`).
  - The server-side `BumpEvent {kind="say", id}` only finds rigs in `workspace.GwangalliNPCs` (`GwangalliBump.luau:131-145`). So **our** rigs need our own `say` event + the client BindableEvent. Fallback: our own BillboardGui in PlayerGui.
- **GwangalliUI** (`ReplicatedStorage.GwangalliUI`, the shared premium kit): `K.DialogBox(gui)` → `api {show(data), hide(), place(rect), layout(mode,W,H), onChoice(id, ch), onClose}`.
  - `data = {npcId, name, role, portraitColor, icon, text, choices = {{id,label,style}}, timer = {total,left}}` (`GwangalliUI.luau:2998, 3243-3245`).
  - Also `K.toast{…}`, `K.Card`, `K.Chip`, `K.Button`, `K.BottomSheet`, `K.Modal`, `K.feedback`, `K.won`.
  - Usage example: `StarterPlayerScripts/GwangalliCafeOnboard.luau:280-330`.
- **GwangalliLayout**: slot contract. Use slot `"dialog"` (`GwangalliLayout.luau:50`). The ScreenGui uses `IgnoreGuiInset=false` + `ScreenInsets CoreUISafeInsets`. While a dialog shows, set the ScreenGui attribute `HideGwangalliHUD = true`.
- **ShopLife's own UI** (`GwangalliBuildingsClient/ShopLifeClient`):
  - ScreenGui `GwangalliBuildingsUI` (DisplayOrder 30)
  - seated HUD `LifeHud`: bottom centre, `Position (0.5,0,1,-74)`, 118 px tall (*src* `ShopLifeClient.ModuleScript.luau:1040-1050`; eff `ShopLifeClient.luau:1332`)
  - voice chip at the top (`showLine`), pager banner (`pagerBuzz`)
  - **Our dialog must sit above `LifeHud` when it exists.**

### 2.9 Money and stats

- `ServerStorage.GwangalliGameplayAPI` (BindableFunction). The final `OnInvoke` is installed by `GwangalliGameplay.luau:481-495`, overriding Life's club API:
  ```lua
  if op == "balance" then return d and d.cash or 0, d and d.bank or 0 end
  if op == "spend" then ... return ctx.spend(player, math.floor(amount), label or "건물 · 생활")
  elseif op == "earn" then ... return ctx.ledger(player, "bank", math.floor(amount), label or "생활 수익")
  elseif op == "addStats" then return ctx.addStats(player, amount, label or "생활") end
  ```
- `ctx.spend` takes cash first, then the bank (체크카드) (*src* `GwangalliGameplay.Script.luau:337-353`). `ctx.ledger` is the single place cash/bank change (`:305-321`).
- Building `Economy` wraps this API and keeps 건물 크레딧 when the life game is absent.
- `ServerStorage.GwangalliProgressAPI` `"track"(player, key, n)`. Keys such as `eat` / `shop_buy` / `earn_tip` are classified automatically from ledger labels (`GwangalliGameplay/Progress.luau:1-30`, `GwangalliProgressShared.luau:306-336`).
- Needs: player attributes `GwB_Satiety / GwB_Energy / GwB_Hygiene / GwB_Fun` (0-100) are readable by the server. We use them for a "배고파 보이시네~" greet.

### 2.10 How players get behind counters (jobs and shifts): attributes to respect

| Attribute (Player) | Set by | Meaning | file:line |
|---|---|---|---|
| `GwJob` | Jobs | career id while employed | `Jobs.luau:1779-1782` |
| `OnShift` + `Job="gukbap"` | Play.Career.Gukbap (and Jobs shifts) | on a shift now | `Gukbap.luau:2003, 2076, 2221` |
| `GwWorkShift` | Work (cafe sim) | job id during a Work shift | `Work.luau:1128, 1179` |
| `GwWorkPlaced` / `GwWorkUniform` | WorkPlacement *(add-on)*: auto-places the worker at `GwWorkSpot` / `GwJobStation` / clerk spots, apron + badge | placed for this shift | `GwangalliWorkSpots.luau:1-50`, `WorkPlacement.luau:1-30` |
| `GwMgrDuty` | Play.Manager (점장) | store id while on duty | `GwangalliPlayShared/Manager.luau:43` |
| `GwPlayActivity` | Play | `"gukbap"`, `"pocha"`, `"grill"`, … | `GwangalliPlayShared.luau:58` |

Job station parts: 32 parts tagged `GwJobStation` (GS25 광안리점). Job Destinations: `스타벅스 광안리점` (-833.8, 10.9, 83.2) is 23 studs from the STARBUCKS street shop; `GS25 광안리점` is a venue (not a street shop); `민락회타운` (-2582, -117).

### 2.11 Doors, fight/bump, skins, raycast skip lists

- **Auto doors** (`ServerScriptService.GwangalliDoors`): 166 models tagged `AutoDoor`. Any Model/BasePart tagged **`AutoDoorOpener`** opens them; position = its HumanoidRootPart or the part itself (`GwangalliDoors.luau:1-6, 218-262`).
  - Our anchored rigs' server root only moves at placements, so a small **proxy part** tagged `AutoDoorOpener` must be moved to the door while a diner passes.
- **Fight**: `GwShopStaff` rigs are punchable (`Fight.luau:16, 186-190`) unless "foreign": `F.FOREIGN_PREFIX = {"shop_","recipient_","mg_"}`, `F.FOREIGN_ATTR = {"ShopCustomer","DeliveryFor","MiniGameHost","StationId"}` (`GwangalliFightShared.luau:126-128`).
  - → Crew NpcIds start with **`shop_crew_`** and diners with **`shop_diner_`** (+ `ShopCustomer=true`). Nobody can punch the waiter mid-serve.
- **GwangalliStaticNpcSkins** *(add-on)*: replaces "map figures" (any model with HumanoidRootPart + UpperTorso + Head and no `AvatarId`) with a static avatar clone, on DescendantAdded. It skips `SKIP = { GwangalliNPCs, GwangalliStreetLife, GwangalliShopStaff, Camera, Terrain }` (`GwangalliStaticNpcSkins.luau:196`).
  - → Our block rigs **must** live under `workspace.GwangalliShopStaff`, or they get frozen into statues.
- Raycast / wall skip lists that already contain `GwangalliShopStaff`:
  - `GwangalliStreetLife/Mind.luau:299` `WALL_SKIP`
  - `GwangalliStaff.luau:3292`
  - `WeaponDealer.luau:828`
  - (place) `ShopStaff.luau:834`

  This is another reason to share that folder.

### 2.12 Client interior (other team: `GwangalliBuildingInterior`, read-only for us)

- Builds local decor within 22 studs of a shop and locally hides parts it replaces.
- Keep zones (`src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/Scan.luau:739-860`):
  - doors
  - restroom
  - **staff**: 5×4 studs behind each cashier anchor (`:794-798`)
  - table tops + 3.4, seats + 4
  - **aisles**: 2.5-wide corridors from the first of `KitchenPass, PassLedge, PassTray, PosBase, OrderKiosk, CounterTop` to **every table centre** (`:812-830`)
  - window band, bin/water spots, `Point_*` ± 2.5
  - NPC models found **inside the shop model** (Humanoid / GwShopClerk / VenueStaff / Staff) ± 2
  - `Scan.addWorldKeep(min,max,kind)` for other systems (`:861-864`)
- → Waiters should walk those pass→table corridors.
- → Our standing spots (cook/approach) are not inside the shop model, so the interior cannot see them. See the integration request in §8.

### 2.13 Map facts: real layouts (place.bin, local frame: x = across, z = depth, +z = door)

All street shops share these: floor top Y 6.8; AutoDoor at z≈+9.5..+11.5 (front glass `ShopWindow`); `ShopBackWall` at z≈-8.9..-10.9; `ShopPartition` side walls; seating 18-22 studs deep.

| shop (world floor centre) | layout facts that drive spots |
|---|---|
| **광안 돼지국밥** (1851.5, 6.6, 3.5) 26×18 | No counter. `KitchenPass` 5×3 panel **on the back wall** (x 2.4, z -8.7) with `PassLedge` at z -8.2 → a wall pass; no walk-in kitchen. 2 tables (x -4, z -2 / 5.4) + 8 ChairSeats. A 좌식평상 platform (x 9.4, 7×14.7, 1.3 high, collidable) with LowTableTop + Cushions. Restroom door at x -3.2 on the back wall. Cook/waiter must stand **in front of** the pass (open-kitchen look). |
| **팔도통닭** (1297.0, 6.6, 59.7) 19×18 | OrderKiosk (x -4.2, z 6.5) near the door; KitchenPass/PassLedge on the back wall (x 2.9); 4 tables. |
| **MEGA COFFEE** (2208.7, 6.6, -42.6) 20×19 | Counter (z -5, 2.0 deep) + back counter (z -8.5); staff aisle z -6.0..-7.8 (≈1.8 wide, ShopStaff barista stands here); PosBase x -2.5; EspressoBody/DripTray x 3.9; 4 window StoolSeats at z 6.8. |
| **SUNSET PUB** (2137.8, 6.6, -32.7) 22×19 | Counter at z -3.8 with TapPost; 4.6 studs behind it to the back wall (bartender zone); bar stools at z -1.0; 1 table. |
| **해변포차** (2033.8, 6.6, -12.7) 37×19 | 5 GrillTables (TableTop 3.4², Coals, Hood above), 20 Stools; a Fridge (x 16.1, z -7.3); **no counter, no pass**. `rec.cook` = the first Hood (above a table) → the service point must fall back to the fridge / back-wall centre. |
| **파도횟집** (1886.8, 6.6, 5.3) 37×18 | Counter + CuttingBoard against the back wall (z -7.6, back edge ≈ the wall) → **no room behind the counter**: the 사장님 works in front of the counter facing it. TankWater 9×2.6×2.7 near the door (x 7.9, z 7.4). 4 tables. |
| **하카타 라멘 광안** (1213.8, 6.6, 66.4) 40×18 | Counter (z -5.2) with 10+ StoolSeats in front (bar) + a 14-wide KitchenPass on the back wall behind it → the cook stands **between counter and pass** (2.9 studs). 6 tables. |
| **바다슈퍼** (2331.2, 6.6, -43.1) 28×22 | 2 counters (POS at x 4.7, z 5.6 near the door); gondolas; 2 fridges on the back wall. |
| **행복 돼지국밥** (-894.2, 6.6, 99.1) GwShop 39×40 | 8 GwShopTable (TrayPoint) + 2 LowTable; walk-in kitchen behind PassCounter (sealed); clerks 주방 이모 (-892.4, 111.4), 사장님; Gukbap career + WorkSpot (-897.5, 8, 104). |

---------------------------------------------------------------------------------------------------

## 3. What exists vs what the target needs

| Target ("top Korean life-sim" restaurant) | Today (place.bin) | Today (effective studio) | GwangalliShopCrew |
|---|---|---|---|
| Someone works in every restaurant | 27/50 table shops have a ShopStaff counter rig; **23 have nobody** | + a ShopService waiter appears in every open table shop | a full crew (cook, waiter, cashier when missing) in every eligible shop near players, annex rooms included |
| Greeted on entry, 단골 recognised | ShopStaff "어서 오세요" + ShopLife chip | + ShopService greet | role-aware greeting (one greeter per shop), regulars by name, hunger-aware |
| A waiter brings water/menu, takes the order | none (HUD button opens a menu) | bubble "메뉴 보시고 주문하시면 돼요~" | waiter walks over, pushes a 주문하시겠어요? dialog that opens ShopLife's real menu, acks the order, relays it to the kitchen |
| A visible cook working the order | ShopFx steam at the `Cook` anchor only | same | cook rig at the pass/station, act synced to Bus `cooking` (fx → cook/chop/flip/cup), calls "나왔어요~" |
| Dish carried and served | ShopLife pops the dish on the table | waiter + generic bowl prop (`Prop=cup`) | real dish replica (FoodKit) on a tray, served the moment the waiter arrives (`serve`), batched per table |
| 호출벨 / call | Bus `call` only | waiter walks over, says one line | waiter comes, dialog with real actions (주문 / 물 / 반찬 / 계산 / 추천) |
| Table cleared after leaving | dishes vanish after 25 s | none | waiter busses the table synced to dish removal |
| Paying | 계산하기 prompt, auto-pay after 10 s | + thanks line | cashier walks to the counter for 후불 guests, bows, 도장 쿠폰 |
| Customers in the shop | **no NPC customers** (Bus `claimSeat/npcOrder` unused) | same | NPC diners with seat budgets that never block players (phase 2) |
| Talking to staff means something | canned lines | none | context dialogs, recommendations from the real menu, 맛보기, 단골 card |
| Loyalty | none (Together's 단골 is player-player) | none | per-shop 단골 levels, stamps, 서비스, saved |
| A player can help out | jobs only at fixed sites | same | optional 3-minute "일손 돕기" (phase 3) |

---------------------------------------------------------------------------------------------------

## 4. Conflicts, risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **GwangalliShopService** (effective build) spawns its own waiter and toggles `staffMode` on `open/close`, leading to two waiters, double `serve`, `staffMode` fights | Config `TAKE_OVER_SHOP_SERVICE = true` (Script attribute `TakeOverShopService`). At boot (before and again after the bus is up): `svc.Enabled = false` (pcall; fallback `svc.Disabled = true`). Then sweep `workspace.GwangalliShopStaff` for models with attribute `GwWaiter`: `staffMode {on=false}` for that key, serve its ready table orders via `queue`→`serve`, destroy the model. Log `[GwangalliShopCrew] took over GwangalliShopService`. With the attribute false (**coexist**): never spawn waiters or call `staffMode` in table shops; add cook/cashier/diners/dialogs only, and route waiter choices to `life.act order` (ShopService answers the `call`). Diners get `GwWaiter="diner"` so ShopService's `staffOf()` (`:276`) never picks them as its voice. |
| R2 | `staffMode serve` left on with nobody serving → orders purged after 240 s, bill charged | **Serve guard** (§5.9): independent pcall'd 1 Hz loop. Any tracked `ready` table order older than `SERVE_TIMEOUT` (18 s) → `serve` directly. `staffMode` is on only while that shop's waiter rig is alive. Any brain error → `staffMode off` + serve all ready. `game:BindToClose` + `script.Destroying` → all off. A `queue` poll (3 s) adopts ready orders we missed. |
| R3 | Duplicate counter staff (ShopStaff rig + our cashier) and double greetings | Cashier role only when no ShopStaff rig and no GwShopClerk "clerk" is inside the footprint. Check order: (a) a live `GwShopStaff` model without `CrewShop` inside `Scan.inside(rec, pos, 1)` (ShopStaff is live within 150 studs, so it already exists when we spawn at ≤45); (b) `require(GwangalliGameplay.ShopStaff).sites()` positions; (c) offline prediction by ANCHORS names. Our greeting fires only when there is no ShopStaff rig (it greets itself). |
| R4 | Job/career sites: player is the worker (Gukbap at 행복 돼지국밥, cafe/GS25 jobs, 점장 모드, Pocha venue) | Static skip: shops within 45 studs of Destinations `스타벅스 광안리점`, `GS25 광안리점`, `민락회타운`; shop names in `SKIP_SHOPS = {"민락 포장마차"}` (Play.Pocha indoor venue); `source == "venue"`; `hostShops` GwShop takeover (`ShopLife.luau:3012`). Live stand-down: any player inside the footprint (+6) with `OnShift == true`, `GwWorkShift ~= nil`, `GwWorkPlaced` non-empty, `GwMgrDuty` non-empty, or `GwPlayActivity` ∈ {gukbap, pocha} → crew goes on break (walks out / despawns), `staffMode off`. Owner override: shop model attribute `ShopCrew = false`; workspace attribute `GwShopCrew = false` disables everything. |
| R5 | Client interior decor intrudes on our standing/approach spots (server cannot see it) | Walk the interior's kept pass→table aisles (cost bias in NavGrid). Publish our spots as tagged parts (`GwCrewSpot`, §5.6) and ask the interior team to keep 1.2 studs around them (§8). Rigs are non-colliding, so the worst case is visual overlap. |
| R6 | GwangalliStaticNpcSkins freezes block rigs that are not in its SKIP list | Rigs live in `workspace.GwangalliShopStaff` (SKIP-listed). Never parent rigs elsewhere. |
| R7 | Diners take seats players want ("빈 자리가 없어요") | Diners claim whole empty tables only. Always leave `KEEP_FREE_TABLES = 2` (+1 per 2 players in the shop) free. On Bus `enter`, if free tables < needed, the most-finished party wraps up (`npcEat` short → leave). Max 40 % of tables. |
| R8 | Fight/bump hits the waiter mid-serve | NpcId prefix `shop_` → `FightShared.foreign`; diners also `ShopCustomer = true`. |
| R9 | Remote abuse (spam talk, choices not offered, far away) | Per-player token bucket (5/s, burst 10), per-op cooldowns, distance ≤ 10 studs to the crew root (server), dialog token + whitelist of offered choice ids (NPC.luau pattern), string length/charset checks, no client-supplied money/items/positions. All money moves only on server-observed Bus `paid`. |
| R10 | Money creation (cashback/refunds, help pay) | Coupon refunds only after a real `paid` event of the same shop/day. Per-shop/day and per-player/day caps (§5.12). Labels prefixed `단골`/`알바비`. Dedupe by (userId, shop, day, t). |
| R11 | Alcohol references (effective build is alcohol-free) | Line bank lint test: forbid 술, 소주, 맥주 (unless the item name says 무알콜), 취, 안주 (ok?), 한잔, 건배 → we say "짠". Item names always from SS. |
| R12 | Performance (server rigs, avatars) | ≤ 6 crewed shops, ≤ 18 crew + ≤ 14 diner rigs. `AVATAR_MAX 90` is shared server-wide: pass `opts.avatar=false` for diners when `liveAvatars` is high (not readable, so cap our own count). Brain tick 4 Hz, no per-frame server work, NpcLeg polylines only. Client LOD: props/tags only within 40 studs. |
| R13 | ShopLife voice chip + our bubbles say the same thing | Our bubble lines are written to complement (the waiter's own words) and are rate-limited per player. The chip stays ShopLife's. |
| R14 | Emulator lacks PathfindingService / spatial queries | Own pure `NavGrid` (rasterised from part AABBs); `GetPartBoundsInBox` used only as an optional extra check. |
| R15 | Engine API drift (`Script.Enabled`, `ModelStreamingMode`, `GuiService.SelectedObject`) | pcall each; no hard dependency. |
| R16 | DataStore unavailable (studio / limits) | pcall; memory-only profile; UpdateAsync merge; save on leave / 180 s dirty / BindToClose (the Interact and Relationships pattern). |
| R17 | ShopLife upserts differ (Together fields) | Only documented Bus fields are required; extra fields (`forUserId`, `mode`) are optional. |

---------------------------------------------------------------------------------------------------

## 5. Design

### 5.1 Goals, non-goals, phases

**Goals**
- The restaurant loop feels like a real Korean 식당: 어서 오세요 → 물/메뉴 → 주문 → 주방 → 서빙 → 식사 → 계산 → 정리.
- Staff can be talked to.
- Regulars are remembered.
- Mobile + PC + gamepad.
- Server-authoritative.
- Zero stuck orders.

**Non-goals**
- Re-implementing ordering, menus, prices or eating (ShopLife's).
- Changing map parts.
- Touching job sites.

**Phases**
- **P1 (ship first):** crew in table / counter / kiosk shops; serving; cook sync; pickup calls; table clearing; dialogs (주문 · 추천 · 물 · 반찬 · 계산 · 잘 먹었습니다); ShopService takeover; tags/bubbles; serve guard.
- **P2:** NPC diners; 단골 system + 도장 쿠폰 + 서비스; 단골 card UI; idle banter; pick/service flavour roles (stocker, stylist, baker).
- **P3 (config-off by default):** 일손 돕기 mini shift.

### 5.2 Architecture

```
ServerStorage.GwangalliShopLife (Bus)  ──events──▶  Director ──▶ Crew[shopKey] (brain, roles)
        ▲  Request ops (staffMode/queue/serve/claimSeat/npcOrder/...)        │   ├─ Rig (attrs, NpcLeg, say)
        └───────────────────────────────────── Bridge ◀──────────────────────┘   ├─ Sites (spots, NavGrid)
GwangalliBuildings.{ShopLife(read), Registry(handlers/fire), Needs, Interact, Economy}       ├─ Diners (P2)
GwangalliGameplayAPI (earn/balance), GwangalliProgressAPI, GwangalliGameplay.ShopStaff(sites)  └─ Talk / Regulars / Help
                    │
   ReplicatedStorage.GwangalliShopCrewNet {Request RF, Event RE}  ◀──▶  client GwangalliShopCrew
                                                                     (Visuals: tray/tags · Bubbles · Dialog · RegularCard · HelpHud)
workspace.GwangalliShopStaff/<crew + diner rigs>   (tag GwShopStaff → GwangalliNPCClient animates)
workspace.GwangalliShopCrew/<shopKey>/{Spots, Doors}   (our own invisible parts)
```

### 5.3 File list and responsibilities

**Server: `src/ServerScriptService/GwangalliShopCrew/`** (`init.server.luau` = Script, siblings = ModuleScripts)

| File | Responsibility |
|---|---|
| `init.server.luau` | Boot: kill switch (`workspace.GwShopCrew == false`). ShopService takeover pass #1. Create Net + ServerStorage API. Wait for `GwB_Ready` (≤120 s) + Bus (≤60 s; missing → log + stop). `Bridge.bind()`, takeover pass #2, `Regulars.init`, `Director.start`. Player hooks. `BindToClose` → `Director.shutdown()` (all staffMode off + serve ready). |
| `Bridge.luau` | **Only** this file touches foreign systems. All pcall'd, with nil-safe fallbacks. `Bridge.req(op, payload) -> table`, `Bridge.onEvent(fn)`, `Bridge.shopRec(key)` (ShopLife.byKey, else rebuilt from `shop` op), `Bridge.session(p)`, `Bridge.dishesOf(key)`, `Bridge.lifeAct(p, action, extra)` = `Registry.handlers["life.act"](p, {action=…})`, `Bridge.lifePay(p, key)`, `Bridge.fire(p, kind, data)`, `Bridge.needs(p, delta, label)`, `Bridge.give(p, item)` (Interact.give), `Bridge.earn(p, amt, label)` (GameplayAPI earn → Economy.earn fallback), `Bridge.track(p, key, n)` (ProgressAPI), `Bridge.shopStaffIn(rec)`, `Bridge.workingPlayerIn(rec)`, `Bridge.jobSite(rec)`, `Bridge.takeOverShopService()`. |
| `Sites.luau` | Per-shop analysis, cached by key, rebuilt if `rec.model` changes. Eligibility, role roster, persona seeds, spots (service S, waiter home H, cook C, cashier K, table approach A[t][seat], clear spot, door in/out), NavGrid build (time-sliced), publishes `GwCrewSpot` parts. |
| `Rig.luau` | Build crew/diner rigs (Looks), attribute contract writes, `walk(r, pts, act, speed) -> secs` with abort tokens, `place`, `face`, `act`, `emote`, `look(userId)`, `carry(str)`, `say(text, dur, tone)` (→ Net to players ≤45 studs), `sit(seatCf)`, door-opener proxy, the `CrewTalk` prompt. |
| `Crew.luau` | Per-shop brain: roles, job queue, event handlers (§5.8), idle life, `staffMode` ownership, table-clearing scheduler, stand-down. One coroutine per role with abort tokens. A 4 Hz shop tick. |
| `Serve.luau` | Order tracking (orderId ↔ table/seat/owner), batching, waiter assignment, **serve guard**, queue polling. |
| `Diners.luau` (P2) | Arrival policy, parties, claimSeat → walk → sit → order (waiter) → npcOrder → eat → npcLeave → pay walk → leave; seat budget; door proxy. |
| `Talk.luau` | Dialog trees per role and context, tokens, choice whitelists, action execution, cooldowns. |
| `Regulars.luau` (P2) | DataStore profile, visit/stamp/coupon/service bookkeeping from Bus events, level-ups, the card view. |
| `Help.luau` (P3) | 일손 돕기 sessions. |
| `Net.luau` | Creates `ReplicatedStorage.GwangalliShopCrewNet {Request, Event}`. Router, rate limits, validators, `Net.fire(p, kind, data)`, `Net.fireNear(pos, r, kind, data)`. |

**Client: `src/StarterPlayer/StarterPlayerScripts/GwangalliShopCrew/`**

| File | Responsibility |
|---|---|
| `init.client.luau` | Boot; inject custom ACTS/POSES into `GwangalliAnim` (append-only, pcall); start modules. |
| `Net.luau` | `Net.request(op, payload)`, `Net.on(kind, fn)` (WaitForChild 60 s; silent if missing). |
| `Visuals.luau` | Watch `CollectionService:GetTagged("GwShopCrew")` rigs. Name tags (BillboardGui in **PlayerGui**, Adornee = Head, MaxDistance 28). Tray/dish props from `CrewCarry` (FoodKit replicas welded to the hands, LOD 40 studs). Free-table pointer ring (BillboardGui adorned to ShopLife's `Anchors/Table_n`). |
| `Bubbles.luau` | `say` events → `LocalPlayer.GwangalliBubble:Fire(head, text, typeId, dur)`; fallback pooled BillboardGuis in PlayerGui. |
| `Dialog.luau` | Our ScreenGui `GwangalliShopCrewUI` (DisplayOrder 32, `IgnoreGuiInset=false`, CoreUISafeInsets) + `K.DialogBox`, placed by `GwangalliLayout.rect("dialog")` and lifted above ShopLife's `LifeHud`. Keyboard 1-6 / Esc, gamepad selection + ButtonB, touch. Lite fallback card if GwangalliUI is missing. |
| `RegularCard.luau` (P2) | 단골 card panel, level-up banner, stamp animation. |
| `HelpHud.luau` (P3) | Task chip, timer, earnings. |

**Shared: `src/ReplicatedStorage/GwangalliShopCrewShared/`** (`init.luau` = ModuleScript exporting the children; pure, no instances at require time)

| File | Contents |
|---|---|
| `init.luau` | `VERSION`, names (`NET`, `FOLDER`, `RIG_FOLDER`, tags, attribute names), `require` of the children |
| `Config.luau` | all tunables (§5.18) |
| `Lines.luau` | Korean line bank per role / shop type / event, Busan variants, `{item}` / `{n}` / `{name}` placeholders, `Lines.pick(key, ctx, seed)` |
| `Personas.luau` | deterministic crew names / titles / looks / dialect from `(shopKey, type, role)` |
| `NavGrid.luau` | pure grid planner (unit-tested with the Luau CLI) |
| `Util.luau` | hashing, KST day key, `won`, yaw helpers, CrewCarry encode/decode |

### 5.4 Boot sequence (server)

1. If `workspace:GetAttribute("GwShopCrew") == false`, return.
2. Takeover pass #1 (§R1).
3. `Net.create()`. Create `ServerStorage.GwangalliShopCrew` (Folder: `API` BindableFunction, `Event` BindableEvent, attribute `Ready=false`).
4. Wait for `workspace.GwB_Ready` (poll 1 s, ≤120 s), then `ServerStorage:WaitForChild("GwangalliShopLife", 60)` → `Event`, `Request`.
5. `Bridge.bind()`: require `GwangalliBuildings.{ShopLife, Registry, Needs, Interact, Economy}`, `GwangalliGameplay.ShopStaff`, `ReplicatedStorage.{GwangalliBuildingsShared, GwangalliNPCLooks, GwangalliShopCrewShared}`, `ServerStorage.{GwangalliGameplayAPI, GwangalliProgressAPI}`. Each one is optional except the Bus.
6. Takeover pass #2 (sweep `GwWaiter` rigs).
7. `Bridge.onEvent(Director.onBus)`. `Director.start()`: 1 Hz activation loop + 4 Hz brains + serve guard loop. Each loop has its own pcall and records `lastError`.
8. Set `ServerStorage.GwangalliShopCrew` `Ready = true`. Print `[GwangalliShopCrew] ready (n eligible shops)`.

### 5.5 Eligibility and crew composition

A shop is **eligible** if all of these hold:
- the rec exists
- `rec.model` has no `ShopCrew == false` attribute
- not a job site (§R4)
- not in `SKIP_SHOPS`
- not `source == "venue"`
- not `hostShops` GwShop
- the role table below gives ≥1 role
- Sites found the required spots

It is **crewed** when eligible and a player is within `SPAWN_R = 45` studs of `rec.center` (3D, so annex rooms at y≈3000 work). The nearest `MAX_SHOPS = 6` win, and the shop a player is inside always wins. It despawns when no player is within `DESPAWN_R = 90` for 20 s, on Bus `close`, or on stand-down.

| type (SS) | P1 roles | persona (title · style · dialect) | spot notes |
|---|---|---|---|
| soup (국밥·해장국·복국) | cook, waiter, cashier* | cook "사장님" (f, middle, `chef`, busan) · waiter "홀 이모" (f, middle, `apron`, busan) · cashier "카운터 알바" | wall pass → cook in front of the pass ledge |
| noodle / katsu / chinese | cook, waiter, cashier* | "주방장" (m, `chef`) · "알바" (young, `apron`) | |
| grill / pocha | cook, waiter | "이모" (f, senior/middle, `apron`, busan; at the fridge / back-wall station, also cashier) · "막내 알바" (young) | no pass → service point = fridge front / back-wall centre |
| rawfish / seafood | cook, waiter | "사장님" (m, middle, `fisher`, busan; cutting board + tank) · "이모" | counter against the wall → stand in front of the counter |
| chicken | cook, waiter, cashier* | "사장님" (m, `chef`) · "알바" | |
| pub | cook ("바 매니저", `black`), waiter ("서버", young) | | behind the bar (4.6 studs of room) |
| snack (분식) | cook ("분식 이모", f, busan); waiter only if the shop has tables | | counter flow serves `dest="table"` when seated & 매장 |
| cafe | barista (at espresso / DripTray, `apron`); `floor` (wipes tables) if ≥4 tables | | staff aisle 1.8 studs; not on the ShopStaff POS spot (≥2.2 apart) |
| burger | kitchen crew at the pass ("크루", `apron`) | | |
| dessert | cook at the station ("점원") | | |
| P2: bakery / cvs / retail | `stocker` (box prop, roams shelves), bakery `baker` (bread tray from the back) | | |
| P2: salon | `stylist` behind the chair during `service` salon events | | |
| others (lobby, residence, realty, pharmacy, laundry, bank, clinic, office, play) | none (ShopStaff/clerks cover them) | | |

`*` cashier only when no ShopStaff / GwShopClerk staff is present (§R3). In shops with ≤4 tables the cook doubles as cashier: they walk to K when a 후불 guest heads out.

GwShop shops use their static clerks as the cook/cashier, so the crew there is **waiter only** (예: 행복 돼지국밥, 광안 치킨, 광안 떡볶이), and only while nobody works there (§R4).

Personas (`Personas.luau`):
- `seed = Looks.hash(shopKey .. role)`
- `name` from a Korean given-name list (순자, 미숙, 영희, 정자, 지수, 민준, 서연, 하준, 도윤, 수빈 …)
- `label = title .. " · " .. name` (prompt ObjectText, name tag)
- `look = {body, age, style}` → `Looks.random(seed, look)`
- `icon` (👩‍🍳 🧑‍🍳 🙋 ☕ 🐟), `color` (shop accent)
- `dialect = "busan"|"std"`

The same shop always has the same people.

### 5.6 Site analysis: spots + NavGrid

Inputs come from `Bridge.shopRec(key)`: frame, sx, sz, floorY, door, tables (min/max/seats/spot), pass/cook/counter/pos/kiosk/menuBoard/tank/cutting/espresso parts, model. If the module table is missing, use Bus `shop` (centres + seat CFrames) and our own part scan.

**NavGrid (shared, pure)**
- Grid in the shop's local frame, 0.5-stud cells, footprint `sx × sz` (shrunk 0.4) + a 4-stud strip outside the door (diners).
- **Obstacles**: every BasePart descendant of `rec.model` whose world AABB overlaps the band `[floorY+0.35, floorY+5.5]`, with Transparency < 0.95, or CanCollide (both furniture and walls; many table legs / chair backs are CanCollide=false, so visibility counts). Excluded:
  - `ShopFloor, Sill, Baseboard, Skirting, Threshold, Wainscot`
  - `AutoDoor` descendants (door leaves), `ShopBounds, LightHost, ShopCeiling`
  - `Sign_*` and wall-hung items (bottom > floorY+4.5)
  - parts under 0.15 studs tall (rugs/mats)

  Plus ShopLife's FoodKit props in `Workspace.GwangalliBuildingsShopLife/<key>` (bin/purifier). AABBs are rasterised (rotated parts via the 8 corners → local AABB) and inflated by `AGENT_R = 0.7`.
- **Seat cells** (chair footprints + 0.3) are blocked for walking. The diner's own target seat is "end-only".
- **Cost**: 1.0 base; **0.7 inside the interior's aisle corridors** (segments from the service point to each table centre, 2.5 wide: the same rule as `GwangalliBuildingInterior/Scan.luau:812-830`); 1.3 within 0.6 of walls.
- A* (8-neighbour, octile heuristic, no corner cutting) + string-pulling (grid line of sight). Output: feet points at `floorY` (+0.02).
- Cache paths by `(fromSpot, toSpot)`. Rasterisation yields every 200 parts (time-sliced), so it runs in <10 ms per shop.

**Spots** (world feet + yaw)
- **S (service point):** a free cell 1.0-1.4 studs on the customer side of the first of `pass` (PassLedge/PassTop/PassTray/KitchenPass), the counter (staff side, if free), the cook station, `stations.pickup`, the fridge, or the back-wall centre (`Scan.freeSpot`-like). Faces the part.
- **C (cook):** "behind" the cook station / counter if a free 1.6×4.4×1.6 box exists there (ShopStaff's standSpot method: offsets 1.7/2.6/3.6 behind, sides 0, ±1.4, ±2.4). Otherwise S + lateral 2.2 toward the side with more room, facing the station.
- **H (waiter home):** S + lateral 2.4 (the other side from C), facing the room centre.
- **K (cashier):** behind the order point (counter/PosBase) if free, else beside `stations.order` facing the door. Skipped if not needed.
- **A[t][s] (approach):** candidate points on the table AABB expanded by 1.2, every 0.5 studs; free cells only; ≥1.0 from any seat top; score = |p − seat.top| (want 1.4-3.0) + 0.15 × path length from H. Face = `seat.spot`. Per table, the best "shared" A is also stored for clearing / taking orders.
- **D_in / D_out:** door ± inward × (2.0 / 3.5) (diners).
- If S or the minimum spot for a role is missing, that role is dropped. If no role is left, the shop is ineligible (logged in `status()`).
- **Publish:** `workspace.GwangalliShopCrew/<shopKey>/Spots/<Kind>_<n>`. Parts are Anchored, 1×1×1, Transparency 1, CanCollide/CanQuery/CanTouch false, tag **`GwCrewSpot`**, attributes `ShopKey`, `Kind` (`home`|`cook`|`cashier`|`service`|`approach`), `Radius` (1.2). Created on Bus `open` (75 studs, before the interior builds at 22) and destroyed on `close`.

### 5.7 Rigs and motion contract

**Build:**
```lua
Looks.build(Looks.random(seed, look), { name = "Crew_" .. role .. "_" .. shopName, anchored = true, shadow = false })
```
- then every BasePart: CanCollide/CanTouch/CanQuery false
- `ModelStreamingMode = Atomic` (pcall)

**Attributes** (set before parenting, tag last):
`NpcId = "shop_crew_" .. hash6(shopKey) .. "_" .. role`, `NpcKind = "shop"`, `NpcGround = rig.ground`, `NpcAct`, `NpcYaw`, `NpcLeg`, `NpcLook = 0`, `NpcTalk = 0`, `NpcEmote = ""`, **`ShopStaff = label`** (other systems read this as the staff label), `CrewShop = shopKey`, `CrewRole`, `CrewName`, `CrewTitle`, `CrewCarry = ""`.

Diners: `NpcId = "shop_diner_" .. serial`, `ShopCustomer = true`, `GwWaiter = "diner"` (coexist guard), `CrewShop`, `CrewRole = "diner"`.

**Tags:** `GwShopStaff` (NPCClient animation), `GwShopCrew` (ours). Parent `workspace.GwangalliShopStaff` (create if missing).

**Prompt** (crew only): `ProximityPrompt "CrewTalk"`
- `ActionText = "말 걸기"`, `ObjectText = label`
- `KeyboardKeyCode E`, `GamepadKeyCode ButtonX`, `HoldDuration 0`
- `MaxActivationDistance 7`, `RequiresLineOfSight false`, `Exclusivity OnePerButton`
- `UIOffset (0, 40)`, parented to the root
- disabled while the rig walks (server toggles `Enabled`)

**Motion:**
- `Rig.walk` writes one `"P;t0;speed;pts…"` leg (t0 = now + 0.15). It returns `len/speed`. It writes the final root CFrame + static leg on arrival (ShopService `setLeg`/`stand` pattern, `GwangalliShopService.luau:305-345`).
- Speeds: waiter 7.0 (5.8 with a tray), cook 5.5, diners 5.0.
- Abort: `walk` checks `r.token`; a new command increments it.

**Door opener:** one proxy Part per walking diner, tagged `AutoDoorOpener`, placed at the door 1.2 s before the leg reaches it and removed 1.5 s after (scheduled from the polyline arc length).

**Custom acts** (client injection, append-only; fallback names used by the server when the client lacks them):

| act | definition | fallback |
|---|---|---|
| `crew_tray` | `{ base="idle", pose="tray", gesture="breathe", walkPose="tray" }` | `cup` |
| `crew_tray2` | two-hand pose table `{LeftShoulder={34,0,10}, LeftElbow={80,0,0}, RightShoulder={34,0,-10}, RightElbow={80,0,0}}` (뚝배기 쟁반) | `cup` |
| `crew_note` | `{ base="idle", pose="clipboard", gesture="scroll", walkPose="clipboard" }` (order pad) | `clipboard` |
| `crew_sit_eat` | `sit_bench` legs + `cup` arm, `gesture="nod"` | `sit` |
| `crew_bow_idle` | `hands_front` + `gesture="breathe"` | `teller` |

The server always writes the custom name. The client injects before its first rig registers, so unknown names fall back to idle. Never rely on prop parts for these.

**Carry** (`CrewCarry`, client builds the visuals):
- `"dish|<menuKey>|<itemId>|<qty>"` → FoodKit.dish replica(s) on a round tray
- `"water"` → stainless pitcher + 2 cups
- `"menu"` → menu board
- `"empty"` → stacked emptied bowls (`FoodKit.eatPart(model, 0)`)
- `"box"` → stock box (P2)
- `""` → none

### 5.8 Crew brain: roles and event mapping

Each role runs a loop over a priority job queue: `serve > relay > takeOrder > answerCall > welcome > clear > checkOn > idle`. Each job is a coroutine with an abort token; arrival waits use `task.wait(secs)` + validity checks.

| Trigger | Role | Behaviour (lines from `Lines.luau`; examples) |
|---|---|---|
| Bus `open` | — | `Sites.get(key)` → publish spots; spawn if crewed |
| Bus `close` / stand-down / despawn | all | serve guard flush → `staffMode off` → walk to the back (if anyone watches) → destroy |
| Bus `enter {userId}` | greeter = cashier or cook (only if no ShopStaff rig) | face + wave: "어서 오이소~ 편한 데 앉으이소!" / regular: "{name}님 또 오셨네예!" / hungry (`GwB_Satiety < 25`): "배고파 보이시네~ 따끈한 거 한 그릇 하고 가요!" (≤1 per player per 60 s) |
| Bus `seat {userId}` (table flow) | waiter | `CrewCarry="water"`, walk to A, place (emote give), "물이랑 메뉴판 여기 있어요~" → push dialog "주문하시겠어요?" [주문할게요][추천해 주세요][조금 있다가요] (timer 10 s) |
| Bus `call {userId}` | waiter | if not already there: "네~ 잠시만요!" → walk to A → "네~ 부르셨어요?" + dialog |
| Bus `order` (player) | waiter (if within 6 studs of that table) / voice | nod: "네~ {item} 하나요!" → `relay` job: walk to S, "{item} 하나요~" → cook replies "예~ 하나!" |
| Bus `order` (npc) | waiter | same relay |
| Bus `cooking {orderId, seconds}` | cook | act by `item.fx`: boil/steam → `cook`, fry → `cook`, chop → `chop`, grill → `flip`, espresso/pour/tap/scoop/blend → `cup`, none → `teller`. Hold until `seconds`; ≤1 line per 20 s ("국물 팔팔 끓고 있습니더~") |
| Bus `ready where="table"` | waiter | **serve pipeline** (§5.9) |
| Bus `ready where="pickup"` | cook/barista | `CrewCarry` dish 1.5 s at the station → walk 1-2 steps to Pickup → "{n}번 손님~ {item} 나왔습니다!" (only if ShopService is not running) |
| Bus `pickup` | barista | "맛있게 드세요~" |
| Bus `finished` (all of a player's dishes done) | waiter | after 8 s, once per seating: walk by, "더 필요하신 거 없으세요?" |
| Bus `cheers` | waiter | emote clap / "짠~! 맛있게 드세요" |
| Bus `grill {action="burnt"}` | waiter | "어머 탔네~ 너무 오래 올려 두면 타요!" |
| Bus `stand` / `leave` / npcLeave | waiter | schedule **clear** of that table when its dishes are done: walk to A, `wipe` act, wait until the table's `Dish_*/Setting_*` models are removed (`Dishes.ChildRemoved`, ≤30 s), `CrewCarry="empty"`, back to S, clear carry |
| Bus `paid {userId}` | cashier (or cook) | bow: "감사합니다~ 또 오이소!"; `Regulars.onPaid` |
| Bus `dash` | cashier | "손님~ 계산은 하고 가셔야지예~" |
| idle (every 20-45 s) | waiter: wipe a free table / fold napkins (`work`) / look around; cook: prep (`chop`/`wipe`), `arms_crossed`; cashier: `teller`/`typing` | banter pairs between roles (≤1 per 90 s, only when a player is within 20 studs): "오늘 손님 많네예~" / "그러게요, 바쁘다 바빠!" |
| player within 3 studs of an idle crew | any | `NpcLook = userId` for 3 s |

**`staffMode` ownership** (per shop):
- `on {cook=false, serve=true}` only after the waiter rig is spawned **and** S/A spots exist
- `off` before the waiter is removed, and on any brain error

### 5.9 Serving pipeline and the serve guard

```
onReady(orderId, where="table"):
  o = Serve.track(orderId)               -- {shop, item, table, seat, owner|npc, readyAt}
      (table/seat from the `queue` op; seat cf from Bus `seat` cache or rec.tables)
  if not waiter alive or no approach spot for that seat: Bridge.req("serve",{orderId}); return
  enqueue serve job (batch: other ready orders of the same table within 3 s, <= 3 dishes)
serve job (waiter):
  walk H/where-ever -> S                       ("받아 갈게요~" to the cook, 0.6 s)
  CrewCarry = "dish|menu|item|qty", act crew_tray(2)
  pts = NavGrid.path(S, A[table][seat]); secs = Rig.walk(...)
  wait(secs); verify: order still tracked & not served & shop crewed
  face seat.spot; emote "give"; wait 0.35
  for each batched order: Bridge.req("serve", {orderId})   -- dish appears exactly now
  CrewCarry = ""; line: "주문하신 {item} 나왔습니다~ 맛있게 드세요!" (soup: "뚝배기 뜨거우니 조심하이소~")
  walk back to H (act behind)
guard (own pcall loop, 1 Hz, independent of the brains):
  for o in tracked: if not o.served and now - o.readyAt > SERVE_TIMEOUT (18 s): serve directly
  every 3 s per crewed shop: Bridge.req("queue") -> adopt untracked {phase="ready", dest="table"}
  if shop.staffModeOn and (no live waiter or brain dead > 5 s): staffMode off + serve all ready
  on Bus "served": mark done; on "close": flush
```

Owner not seated (stood up) → `serve` immediately: ShopLife does `waitSeat` and re-serves on sit.

Typical latency ready→on table: 3-7 s. Worst case 18 s.

### 5.10 NPC diners (P2)

**Policy** (per crewed table-flow shop):
- target tables = `floor(#tables × occ)`, where `occ` by `Lighting.ClockTime`:
  - 0.25 base
  - 0.5 at 11:30-13:30 and 18:00-20:30
  - pocha/grill/pub 0.6 at 19:00-02:00
  - 0.1 at 03:00-07:00
- capped by `#tables − KEEP_FREE(2) − ceil(playersInShop/2)`, `MAX_PER_SHOP 6` rigs, global `MAX_DINERS 14`
- arrivals every 15-40 s; party size 1-3 (≤ seats)

**Flow:**
1. spawn at D_out (only if no player sees the door within 18 studs, else 6 studs further down the sidewalk)
2. `claimSeat {shop, npc, table}` per member
3. walk (door proxy) to the seat's A
4. `Rig.sit(seat.cf)` (feet = seat top − 0.9, act `sit`; numbers from `Play/Actors.luau:385-404`, to be tuned in studio)
5. 2-5 s later the waiter takes the order (`crew_note` act at the table; diner bubble "이모~ 여기 {item} 하나 주세요!")
6. `npcOrder {items}`: 1 main + optional side/drink, never `cat == "alcohol"`
7. served by the waiter
8. eat: act `crew_sit_eat`, `npcEat {seconds = 25-50}`
9. `npcLeave` → stand (act idle)
10. walk to K/Order ("잘 먹었습니다~", cashier bow)
11. leave through the door → despawn

Wrap-up rule (§R7) on Bus `enter`.

Looks: `Looks.random(seed, {style ∈ casual/office/street/tourist/hoodie, night → club-free plain})`. Pass `opts.avatar=false` when our live diner count ≥ 10, to save avatar budget.

### 5.11 Talk / dialog system

**Server-authoritative trees** (`Talk.luau`). A node is `{text, choices = {{id, label, style?}}}`. The server keeps the last node per player `{token, crewId, ids = set, expires = now+60}`.

**Root by role and context** (≤ 6 choices incl. "괜찮아요"/close):

| Role / context | Choices → effect |
|---|---|
| waiter, player seated here (table flow) | **주문할게요** → `Bridge.lifeAct(p,"order")` (ShopLife opens its menu; our dialog closes) · **추천 메뉴 있어요?** → line from SS menu (the day's pick: hash(day, shop) over `cat=="main"`): "오늘은 {item} 강추예요! {desc} · {price}" · **물 좀 주세요** (cooldown 25 s) → waiter `CrewCarry="water"`, pours (act `cup`) + `Bridge.lifeAct(p,"water")` only when the player's cup is empty, else just the gesture · **반찬 더 주세요** (banchan types; when every banchan piece is eaten) → `Bridge.lifeAct(p,"banchan")` (ShopLife refills exactly then) · **여기서 계산할게요** (pocha/pub/grill/seafood) → `Bridge.lifePay(p, key)` / others: "계산은 나가실 때 카운터에서 해 주세요~" (cashier walks to K) |
| waiter, player standing | **자리 있어요?** → names a free table + `Event point {table}` (pulsing marker 5 s) · 추천 메뉴 · **내 단골 가게** (P2 card) |
| cook | **뭐 만드세요?** → current order ("지금 {item} 끓이는 중이에예~") · **맛있는 냄새 나요!** → once per day per shop: 맛보기 (`Bridge.needs(p,{Satiety=3, Fun=2},"맛보기")` + "한 입 드셔 보이소~") · 추천 메뉴 |
| cashier | **계산할게요** (bill > 0) → `Bridge.lifePay` · **영수증 보여 주세요** → text = bill lines from `Bridge.session(p).bills[key]` · **포장 돼요?** → line · **단골 카드** (P2) |
| any, after `paid` < 3 min | **잘 먹었습니다!** → `Regulars.compliment` (+1 point once per visit-day), line "아이고 고맙습니더~ 또 오이소!" |
| any (P3) | **일손 도와드릴까요?** → `Help.offer` |

Crew behaviour during a dialog:
- the rig sets `NpcTalk = userId` and faces the player; it stops walking unless serving
- the dialog closes on distance > 14 studs, timeout, or a serve job preempting (the waiter says "잠시만요~ 서빙 먼저 하고 올게요!")

**Pushed dialogs** (server → client `dialog`): waiter welcome at the table, call answers. ≤1 pushed dialog per player per 45 s. A choice id `later` closes politely.

### 5.12 단골 (regulars) system (P2)

**Visit day:** first Bus `paid` (total > 0, not `auto`) of a player in a shop per KST day (`os.date("!%Y%m%d", os.time()+9*3600)`).

**Levels** (per shop, by visit days):

| Level | Visit days | Title | Perks |
|---|---|---|---|
| 1 | 1 | 첫 방문 | — |
| 2 | 3 | 아는 얼굴 | greeted by name |
| 3 | 7 | 단골 | greeted by name; 서비스: once per visit-day, a free small item via `Bridge.give` (held food, e.g. 음료 / 계란찜 / 콘치즈 from a per-type table), fallback `Bridge.needs` |
| 4 | 15 | 찐단골 | greeted by name; 서비스 |
| 5 | 30 | 가족 같은 손님 | greeted by name; 서비스 |

The favourite dish is mentioned ("오늘도 {fav}?").

**도장 쿠폰:** +1 stamp per visit-day (10 → 1 coupon, ≤3 stored). On the next `paid` in that shop with a coupon: `Bridge.earn(p, min(total, COUPON_VALUE=10000), "단골 쿠폰 · " .. shopName)` (refund into the bank) + toast "🎟️ 쿠폰 사용! 한 그릇 값 돌려드렸어요". Caps: 1 coupon per shop per day, `DAILY_EARN_CAP 20000` per player.

**Level-up:** Event `regular.up` → banner "🏅 '{shop}' 단골 등극! 사장님이 얼굴을 기억해요" + `K.feedback("success")`.

**Card view** (`card` op):
`{shop, shopName, icon, level, title, visits, nextAt, stamps, coupons, fav = {name, count}, perks = {strings}, top = {{shopName, level, visits}} (my top 5)}`

### 5.13 일손 돕기 (P3, `Config.HELP.enabled = false` by default)

- **Offer:** cook/cashier dialog "오늘 일손이 모자라네… 좀 도와줄래요?" when ≥1 NPC diner order is pending.
- **Refused when:** `OnShift` / `GwWorkShift` / `GwMgrDuty` / `GwPlayActivity` non-empty, already 3 sessions today, or the shop has no live crew.
- **Session:** 3 minutes or 6 deliveries. Player attribute `GwCrewHelp = shopKey` (ours). A simple apron part welded to the UpperTorso (skipped when `GwWorkUniform`).
- **Tasks:** only NPC-diner orders (never another player's dish). HUD chip "🍲 3번 테이블 · 돼지국밥".
  1. Prompt "쟁반 받기" on our S anchor (client shows it to the helper only).
  2. Server checks distance ≤ 5 → `GwCrewTray` attribute + tray prop on the player.
  3. Prompt "서빙하기" at that table's A anchor → server checks distance ≤ 5, order still ready and assigned → `serve`.
- **Pay:** 1,200원 + speed bonus ≤ 600 per delivery. Paid once at the end via `Bridge.earn(p, total, "알바비 · {shop} 일손 돕기")`. Cap 15,000 per session.
- **Ends on:** quit, leaving > 25 studs, timeout, a job shift starting, death.
- While helping, the waiter leaves NPC orders to the helper (the serve guard still applies).

### 5.14 Networking

`ReplicatedStorage.GwangalliShopCrewNet` (Folder, created by the server): `Request` (RemoteFunction), `Event` (RemoteEvent, server → client only; client FireServer is ignored).

**Client → server** `Request:InvokeServer(op, payload)` → `{ok, code?, msg?, …}`:

| op | payload (validated) | result |
|---|---|---|
| `talk` | `{crew = string ≤48, ^shop_crew_}` | `{ok, dialog = {crewId, name, role, icon, color, text, choices, token, timer?}}` |
| `choose` | `{crew, token = integer, choice = string ≤24 [%w_]}` | `{ok, dialog?, close?, toast?}` (actions run server-side) |
| `card` | `{shop = string ≤120}?` | `{ok, card}` (P2) |
| `help.start` / `help.quit` | `{shop}` / `{}` | `{ok, state}` (P3) |

Rules:
- `typeof` checks on every field; unknown op → `{ok=false, code="op"}`.
- Token bucket 5/s burst 10 → `{ok=false, msg="잠시 후 다시 시도해 주세요"}`.
- `talk` needs the character alive and ≤ 10 studs from the crew root and |dy| < 6.
- `choose` needs a token match, a choice in the offered set, an unexpired node, and still ≤ 14 studs.
- Per-choice cooldowns (water 25 s, recommend 5 s, taste once/day).

**Server → client** `Event:FireClient(p, kind, data)`:

| kind | data | sent to |
|---|---|---|
| `say` | `{id = NpcId, text, dur, tone = "plain"|"happy"|"busy"}` | players within 45 studs of the speaker |
| `dialog` | dialog table (pushed) | the target player |
| `dialog.close` | `{token}` | the target |
| `toast` | `{text, kind}` | the target |
| `point` | `{shop, table, label}` | the target |
| `regular.up` | `{shop, shopName, level, title}` (P2) | the target |
| `help.state` | `{on, task?, left, earned}` (P3) | the target |

**ServerStorage API** for other systems: `ServerStorage.GwangalliShopCrew` (Folder, `Ready`):
- `API:Invoke(op, …)`: `"status"` → `{shops, crew, diners, errors}`, `"standDown"(shopKey, on)`, `"crew"(shopKey)` → views, `"regular"(userId, shopKey)` → card, `"serveNow"(shopKey)`
- `Event` (`"served"`, `"regular.up"`, `"help.done"`)

### 5.15 Client UX (mobile / PC / gamepad)

- **Name tag** (BillboardGui in PlayerGui, Adornee = Head, `StudsOffsetWorldSpace (0, 2.4, 0)`, MaxDistance 28, LightInfluence 0): title line "홀 이모" (bold, accent colour) + name "순자"; a ♥ chip "단골" when the player's level ≥ 2 in that shop (the card data is cached client-side from the last `talk`).
- **Bubbles:** GwangalliBubble pool (same style as every NPC); `tone` maps to `typeId` (`plain`).
- **Dialog:**
  - `K.DialogBox` (portrait glyph = persona icon, name = label, role = shop name) in the Layout `dialog` slot, raised above `LifeHud`
  - choices as big buttons (≥44 px); typewriter; timer ring for pushed dialogs
  - PC: number keys 1-6, Esc closes
  - gamepad: `GuiService.SelectedObject` = first choice, ButtonB closes
  - ScreenGui attribute `HideGwangalliHUD = true` while shown
  - an 8 s auto-close for pushed dialogs
- **Point marker:** a pulsing ring BillboardGui adorned to ShopLife's `Anchors/Table_<n>` + "빈 자리" label, 5 s.
- **단골 card (P2):** `K.Card` modal: shop icon + name, ★ level + title, "방문 7일째", 10 stamp circles (filled with a stamp animation when you earn one), 쿠폰 n장, 자주 먹는 메뉴, 다음 혜택, "내 단골 가게 TOP 5".
- **Help HUD (P3):** a top-right chip (Layout `topRight`) with task, timer and 💰.

### 5.16 Data schemas

**Server, in memory:**
```lua
Site = { key, name, type, flow, menuKey, rec, roles = {"cook","waiter","cashier"}, spots = { S, H, C, K, A = { [tableId] = { [seatId] = {pos, yaw} , shared = {pos,yaw} } }, Din, Dout },
         nav = NavGrid, persona = { [role] = Persona }, hasShopStaff = bool, gwClerks = {...}, eligible = bool, why = string? }
Crew = { site, rigs = { [role] = R }, jobs = { [role] = queue }, staffModeOn = bool, seatCf = { ["u"..uid | "n"..npc] = CFrame },
         lastGreet = { [uid] = t }, pushed = { [uid] = t }, clearQ = { tableId... }, error = string?, born = t }
R (rig) = { id, model, root, head, ground, role, label, pos (feet), yaw, token, busy = jobName?, act, carry }
Order = { id, shopKey, item, menuKey, qty, table, seat, owner = uid?, npc = id?, readyAt, served = bool, assigned = role? }
Diner = { id, rig = R, shopKey, party = id, seat, table, phase = "walkIn"|"seated"|"ordered"|"eating"|"paying"|"leaving", orderIds }
DialogNode = { token, crewId, ids = { [id] = true }, expires, ctx }
```

**DataStore `GwangalliShopCrew_v1`, key `u_<UserId>`:**
```lua
{ v = 1,
  shops = { [shopKey] = { n = visitDays, last = "20261016", st = stamps (0-9), cp = coupons (0-3), sp = spentWon (capped 1e9),
                          fav = { [itemId] = count } (<= 8), nm = shopName, cmp = lastComplimentDay } },   -- <= 120 shops (LRU by last)
  day = { d = "20261016", earned = won, taste = { [shopKey] = true }, svc = { [shopKey] = true }, help = n },
  tot = { visits = n } }
```
Merge rule: per shop take max `n`; `last` = later; stamps/coupons follow the record with the later `last`; day block from the later `d`.

### 5.17 Config (`GwangalliShopCrewShared/Config.luau`)

Server Script attributes override: `TakeOverShopService`, `Diners`, `MaxShops`, `Debug`. Workspace attributes: `GwShopCrew = false` (off), `GwShopCrewDebug` (logs + 🧪 status prompt).

```lua
ENABLED=true; TAKE_OVER_SHOP_SERVICE=true
MAX_SHOPS=6; MAX_CREW_RIGS=18; SPAWN_R=45; DESPAWN_R=90; DESPAWN_AFTER=20
WALK={waiter=7.0, tray=5.8, cook=5.5, diner=5.0}; AGENT_R=0.7; CELL=0.5
SERVE_TIMEOUT=18; QUEUE_POLL=3; BATCH_WINDOW=3; MAX_BATCH=3
TALK_R=10; TALK_CLOSE_R=14; DIALOG_TTL=60; PUSH_GAP=45; RATE=5; BURST=10
GREET_GAP=60; BANTER_GAP=90; LINE_GAP_PER_PLAYER=6
JOB_SITES={"스타벅스 광안리점","GS25 광안리점","민락회타운"}; JOB_SITE_R=45; SKIP_SHOPS={"민락 포장마차"}
DINERS={enabled=true, max=14, perShop=6, keepFree=2, occBase=0.25, occPeak=0.5, occNight=0.6, gap={15,40}, eat={25,50}}
REGULAR={levels={1,3,7,15,30}, titles={"첫 방문","아는 얼굴","단골","찐단골","가족 같은 손님"}, stampsPerCoupon=10, maxCoupons=3, couponValue=10000, dailyEarnCap=20000, serviceLevel=3}
HELP={enabled=false, perDay=3, seconds=180, maxDeliveries=6, pay=1200, bonus=600, cap=15000}
NPC_PREFIX="shop_crew_"; DINER_PREFIX="shop_diner_"; RIG_FOLDER="GwangalliShopStaff"; FOLDER="GwangalliShopCrew"
NET="GwangalliShopCrewNet"; API="GwangalliShopCrew"; DATASTORE="GwangalliShopCrew_v1"; TAG="GwShopCrew"; SPOT_TAG="GwCrewSpot"
```

### 5.18 Performance budget

| Side | Budget |
|---|---|
| Server | ≤ 6 shops × 4 Hz brain (table scans only); 1 Hz activation; 1 Hz guard; Bus ops are BindableFunction calls (cheap). One NpcLeg string per walk; root CFrame writes only on arrival. Spot / NavGrid build once per shop open, time-sliced (<10 ms). |
| Network | Attribute changes per walk/act (~0.3/s per rig); bubbles only to players ≤45 studs. |
| Client | Animation via NPCClient LOD (existing). Our client keeps ≤ 12 name tags, ≤ 6 tray props (≤40 studs) and one dialog. |

### 5.19 Korean line-bank guidelines (`Lines.luau`)

- Natural spoken Korean. Busan 사투리 for `dialect="busan"` owners (오이소, 하이소, 마이 무라, 예~, ~습니더); 표준어 for young 알바 / cafes.
- No alcohol words (§R11); no English except brand-y cafe lines ("Thank you~" allowed only in pub/cafe persona sets).
- Keys:
  - `greet`, `greetRegular`, `greetHungry`, `welcomeSeat`, `askOrder`, `orderAck`, `relay`, `cookAck`, `cooking`, `readyCall`
  - `serve`, `serveHot`, `pickupCall`, `pickupThanks`, `callAnswer`, `busyWait`, `water`, `banchan`, `checkOn`, `clear`
  - `paid`, `bye`, `dash`, `recommend`, `taste`, `receipt`, `takeout`, `banterA/B`, `cheers`, `burnt`
  - `regularUp`, `service`, `couponUse`
  - `helpOffer/helpThanks`
  - diner lines `dinerOrder`, `dinerServed`, `dinerBye`
- Samples:
  - "어서 오이소~ 편한 데 앉으이소!"
  - "물이랑 메뉴판 여기 있어예~ 천천히 보시고 불러 주이소"
  - "네~ {item} 하나요! 금방 나갑니더"
  - "{item} 하나요~!" / "예~ 하나!"
  - "주문하신 {item} 나왔습니다~ 맛있게 드세요!"
  - "뚝배기 뜨거우니까 조심하이소~"
  - "{n}번 손님~ {item} 나왔습니다!"
  - "네~ 부르셨어요?"
  - "잠시만요~ 서빙 먼저 하고 올게요!"
  - "치워 드릴게요~"
  - "감사합니다~ 또 오이소!"
  - "{name}님 또 오셨네예! 오늘도 {fav}?"
  - "오늘은 {item} 강추예요! {desc}"
  - "한 입 드셔 보이소~ 간 괜찮지예?"
  - "이모~ 여기 {item} 하나 주세요!"
  - "잘 먹었습니다~"

---------------------------------------------------------------------------------------------------

## 6. Player flows (step by step)

**F1: 국밥집 (광안 돼지국밥, a table shop with no counter)**
1. The player walks within 75 studs. Bus `open` → Sites builds spots (S in front of the wall pass, C left of it, H right, A for both tables and the 평상) and publishes `GwCrewSpot`. Within 45 studs the crew spawns: 사장님 (cook, `cook` act at C) and 홀 이모 (waiter at H, `behind`). `staffMode {serve=true}`.
2. The player enters. Bus `enter` → 사장님 turns and waves, bubble "어서 오이소~ 편한 데 앉으이소!" (ShopLife's chip also greets).
3. The player sits (`앉기`). Bus `seat` → 이모 walks with the water pitcher, gesture `give`, "물이랑 메뉴판 여기 있어예~" → pushed dialog "주문하시겠어요?" [주문할게요][추천해 주세요][조금 있다가요].
4. **주문할게요** → the server calls `life.act order` → ShopLife's 나무 메뉴판 opens. The player orders 돼지국밥. Bus `order` → 이모 nods "네~ 돼지국밥 하나요!" → walks to S: "돼지국밥 하나요~!" → 사장님 "예~ 하나!".
5. Bus `cooking (14 s)` → 사장님 `cook` (stir) at the pass; ShopFx steam at the Cook anchor.
6. Bus `ready (table)` → 이모 goes to S, a 뚝배기 tray appears (`crew_tray2`), walks the aisle, stops beside the seat, `give` → `serve` → the dish appears on the table → "뚝배기 뜨거우니까 조심하이소~".
7. The player eats with ShopLife's HUD (밥 말기, 부추·새우젓 …). They may talk to 이모: 물 / 반찬 더 (refill when empty) / 추천.
8. The player stands and goes to the order point. ShopLife's "계산하기" prompt → Bus `paid` → 사장님 (cashier duty) at K bows: "감사합니다~ 또 오이소!". 단골: visit day 1, stamp 1.
9. Bus `leave` → 이모 clears the table: `wipe` until the dishes vanish (ShopLife, about 25 s after done), carries the empty bowls back.

**F2: 카페 (MEGA COFFEE)**
1. ShopStaff's barista is at the POS (the ShopStaff rig). Our 바리스타 stands at the espresso machine (C).
2. Kiosk order → Bus `order` → our barista: "주문 확인했습니다~".
3. Bus `cooking (espresso)` → `cup` act. Bus `ready (pickup)` → cup carry 1.5 s → "023번 손님~ 아이스 아메리카노 나왔습니다!" (the pager banner fires too).
4. Bus `pickup` → "맛있게 드세요~".

**F3: 포차 at night (해변포차)**
1. 이모 at the fridge station, 막내 알바 waiting. NPC diners at 60 % of the tables (P2), with lively bubbles.
2. Grill order → 알바 serves the raw platter → "자주 뒤집어 주세요~". `grill burnt` → line.
3. **여기서 계산할게요** works at the table (`life.pay`).

**F4: 횟집 (파도횟집)**
1. The player uses "수조에서 고르기" (ShopLife tank UI). Bus `order` → 사장님 walks to the tank (`fish` act 3 s) → to the cutting board (`chop` for the cooking seconds).
2. 이모 serves the 회 platter.

**F5: talking to staff anywhere.** "말 걸기" → context dialog (§5.11). Distance/token checked; actions run through ShopLife's own handlers.

**F6: 단골 (P2).**
1. Third visit day → banner "🏅 '광안 돼지국밥' 아는 얼굴!". On the next entry: "○○님 또 오셨네예!".
2. Seventh day → 단골: once per visit-day, "서비스예요~" hands a free 음료 (held item).
3. Tenth stamp → a coupon. The next paid meal is refunded (≤10,000원) with the toast "🎟️ 쿠폰 사용!".

**F7: NPC diners (P2).** Parties walk in (the auto door opens), sit, the waiter takes their orders, the cook cooks, the waiter serves, they eat, pay with a bow at the counter and leave. When a player group arrives and free tables run low, the most-finished party leaves early.

**F8: 일손 돕기 (P3).** Accept → apron → task chip → pick up the tray at the pass → serve the diner's table → … → summary "알바비 7,800원 입금".

---------------------------------------------------------------------------------------------------

## 7. Test plan and acceptance criteria

**Offline (Luau CLI `scratchpad/luau/luau`, scripts in `feat/crew/`):**
1. `NavGrid` unit tests on fixtures exported from `place.bin` (python: part AABBs + table/seat/pass data for 광안 돼지국밥, 팔도통닭, MEGA COFFEE, 해변포차, 파도횟집, 하카타 라멘, 행복 돼지국밥). Assert: every table has ≥1 approach spot reachable from S and from D_in; paths never enter table/seat AABBs; ≥70 % of path length lies in aisle corridors; runtime < 5 ms per shop.
2. `Lines` lint: every value is a non-empty Korean string; no forbidden alcohol words; placeholders resolve; Busan keys exist for every busan persona type.
3. `Personas` determinism (the same key gives the same name/look) and the type → roles table covers every `SS.TYPES` key.
4. Crew/Serve state machine on the mock runtime (`bprev/lib/rbx.luau` copy + a fake Bus that emits seat → order → cooking → ready and records ops). Expect: `staffMode on` after spawn; `serve` within ≤ 8 s simulated after ready; guard serve at 18 s when the waiter is killed; `staffMode off` on close / error; no `serve` twice for one order; coexist mode never calls `staffMode`.
5. Remote validators (fuzz: wrong types, long strings, stale tokens, far player) never error and refuse.

**Studio (temp studio HTML via harness, `flock … timeout 1500`):**
1. Inject our three folders (the `tools/build_studio.py` pattern). Boot, then check the log for "[GwangalliShopCrew] took over GwangalliShopService" and that no `GwWaiter` model remains.
2. Teleport to 광안 돼지국밥 (1851.5, 9.8, 3.5). `ShopLife.sitAt(player, key, 1)`, then `Registry.handlers["life.order"](player, {shop=key, item="dwaeji"})` in the server ctx. Screenshots at t+2 s (waiter at the table with water), t+16 s (cook act), t+20 s (tray walking), t+24 s (dish on the table). Measure ready→served from Bus events (< 8 s).
3. Repeat for MEGA COFFEE (pickup call), 해변포차 (no pass: service point fallback), 파도횟집 (counter against the wall), 행복 돼지국밥 (waiter only; then set `OnShift=true` + `Job="gukbap"` on the player: the crew stands down and `staffMode` goes off).
4. Kill switch: `workspace.GwShopCrew=false` before boot → nothing spawns. Destroy our Script mid-serve → the guard/BindToClose path serves; no order older than 20 s left in `queue`.
5. Mobile layout check (viewport 844×390): dialog above `LifeHud`, buttons ≥44 px.

**Acceptance criteria:**
- 0 stuck orders over a 30-minute soak with 3 simulated players.
- No duplicate waiter in any shop.
- Rigs never inside tables/walls in screenshots of the 7 sample shops.
- All UI text Korean.
- Server script time < 1 ms average.
- No warnings spam (≤1 per minute).

---------------------------------------------------------------------------------------------------

## 8. Integration requests to other teams (through the orchestrator)

1. **Building interior (`GwangalliBuildingInterior`):** in `Scan.keepouts`, also keep clear `Radius` (1.2) around every Part tagged **`GwCrewSpot`** whose `ShopKey` matches the venue (or simply inside the venue footprint). Kinds: home/cook/cashier/service/approach. These parts exist from Bus `open` (75 studs) onward, before you build at 22 studs. Please also keep the pass/service point the same as your aisle origin (first of KitchenPass, PassLedge, PassTray, PosBase, OrderKiosk, CounterTop). We use the same rule for our aisle bias.
2. **Owner / pack maintainers:** `GwangalliShopService` is superseded by GwangalliShopCrew. We disable it at runtime by default (Script attribute `TakeOverShopService = false` keeps both, in coexist mode).
3. **Nobody else** should spawn staff in ShopLife shops without checking `ServerStorage.GwangalliShopCrew.API:Invoke("crew", shopKey)` (or the `CrewShop` attribute on rigs).

## 9. Open questions (decide during implementation; defaults in brackets)

- Busan dialect intensity for 알바 personas [표준어 for young staff, 사투리 for owners/이모].
- Should diners use the kiosk/pickup flow in cafes? [no in P2; table-flow shops only].
- 단골 coupon as a refund vs "free next dish" [refund via `earn`: it is the only server-safe way without changing ShopLife prices].
- Do crewed annex rooms need a cashier when ShopLife puts the order point by the door? [yes, if K is found].
- NPCClient injection timing: if a rig registers before our ACTS injection, the first act may show as idle until the next act change [acceptable; the server re-writes act at each job start].

Files:
- Design doc: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/crew/research.md`
- Census data and scripts: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/crew/py/shops_scan.json`, `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/crew/py/shops_scan.py`, `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/crew/py/layout.py`, `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/crew/py/dest.py`, `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/crew/lt/cls.luau`
