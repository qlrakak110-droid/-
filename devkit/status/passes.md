# GwangalliPasses (게임패스 #1 프리미엄 차고 · #3 편의 패스 · #4 과시 패스): 인수인계

> 범례: **[V]** = 이번 세션에서 코드를 읽거나 직접 실행해서 확인함. **[A]** = 에이전트 보고서나 로그의 주장이고 다시 확인하지 않음.
> Repo root `/home/user/-`, branch `claude/car-interior-window-rendering-6i5i62`. 모든 경로는 repo 기준.

## 0. 현재 상태 한눈에

| 항목 | 상태 |
|---|---|
| 코드 | 37개 파일 완성. Server `src/ServerScriptService/GwangalliPasses/` 12개 (init.server + 11 modules), Client `src/StarterPlayer/StarterPlayerScripts/GwangalliPasses/` 17개, Shared `src/ReplicatedStorage/GwangalliPassesShared/` 8개. 선택 패치 `patches/GwangalliPasses_Phone.patch` 1개 |
| 문법 | **[V]** 37개 모두 `luau-compile` 통과 |
| 오프라인 로직 테스트 | **[V]** `devkit/feat/passes/tests` 사본을 scratch에서 다시 실행: **156 passed, 0 failed**. 범위는 key alias, plate 검증과 claim key, neon, cars, Util.wrap/bucket, jail/koHelp wrapper, Net payload copy와 rate limit, Plate.set/clear |
| 번들 | **[V]** `python3 tools/bundle_plus.py <out>` 정상 동작. server 123 modules, client 191 modules. GwangalliPasses가 양쪽에 들어감 |
| 폰 패치 | **[V]** v7 `GwangalliPhone/Phone.luau`에 `patch -p1 --dry-run` 깨끗하게 적용됨 |
| 실제 Studio 테스트 | **없음.** 웹 스튜디오 에뮬레이터(run1/run2.log)는 부팅, ready map(8개 전부 true), 프리미엄 템플릿 4개, 프리뷰 4개, 키오스크 배치까지만 성공 **[A, 로그는 직접 읽음]**. 차 스폰 이후 모든 단계가 에뮬레이터 OOM으로 실패(일반 차 스폰도 OOM)해서 summon, market, plate, neon, KO, hub UI는 **런타임 미검증** |
| 워크플로 | `wf_a5d69eb7-e00`: research 완료. build 2회 모두 사용 한도로 중단(10/16 17:24 session limit, 10/17 07:50 weekly limit). **test, review(correctness/experience), fix는 한 번도 실행되지 않음** |
| 마지막 자동 커밋(중단 직전) | `b230bbf` Data pending-replay와 DriveHook K.Modal. `fe7ab8c` Waits.jailWrapper 분리. `fbd78e5` Hub scrim(패널 모드 배경, 바깥 탭하면 닫힘). 세 개 모두 끝까지 쓰인 편집이고 컴파일 OK **[V]** |

## 1. Pass ID 설정 (정확한 위치)

**Rojo/소스 모드** (`src`를 그대로 쓸 때): `src/ReplicatedStorage/GwangalliPassesShared/Config.luau`
- `Config.PASSES.PremiumGarage.Id`: line 14
- `Config.PASSES.Convenience.Id`: line 34
- `Config.PASSES.Flex.Id`: line 53
- `Price` 799/349/299는 안내용 fallback입니다. 실제 가격은 `StoreHook.price`가 `GetProductInfo(...GamePass).PriceInRobux`로 가져옴 **[V]**

**번들 모드** (최종 전달물 2개 파일): 서버 파일 맨 위 `GW_CONFIG.PassIds`
- 생성된 `GwangalliPlus.server.luau`의 9~13행, 템플릿은 `tools/bundle_plus.py:115-119`
- 동작 **[V]** (`tools/bundle_plus.py:224-246, 294-305`):
  1. 서버가 `ReplicatedStorage.GwangalliPlus` Folder를 만들고 속성 `PassId_<Key> = tonumber(id) or 0`을 넣음
  2. `__post["GwangalliPassesShared/Config"]`가 Config 모듈이 로드되는 순간 `C.PASSES[key].Id`를 그 속성값으로 덮어씀. 서버와 클라이언트가 같은 값을 씀(클라이언트는 marker를 최대 45초 기다림)
- ⚠️ **번들 모드에서는 `Config.luau`의 Id가 항상 무시됩니다.** GW_CONFIG 값이 0이어도 number라서 0으로 덮어씀.
- ⚠️ `bundle_plus.py` 템플릿이 0으로 하드코딩되어 있어서 **다시 번들할 때마다 PassIds가 0으로 돌아갑니다.** ID가 정해지면 `tools/bundle_plus.py:116-118` 템플릿에도 넣으세요.

**Id = 0의 의미** **[V]** (`GwangalliPassesShared/init.luau` `P.available`, `Ownership.owns:54`):

| | Live 서버 | Studio |
|---|---|---|
| 상점, HUD 버튼, 폰 아이콘 | 숨김 (`P.anyAvailable`) | 보임 (`STUDIO_SHOW_UNCONFIGURED = true`) |
| 소유 판정 | 누구도 소유 안 함 (**admin free도 안 됨**) | 테스트 스위치나 admin으로만 소유 |
| 원격 차고 잠금 | **꺼짐** (`Garage.gateActive`가 `P.available("PremiumGarage")` 필요) → 누구나 어디서든 내 차 호출 | **켜짐** → 패스 없으면 정비소에서만 호출 |
| 구매 버튼 | (숨김) | 토스트 "판매 준비 중이에요 · Studio에서는 workspace 속성 GwPassesStudioTest 로 시험해 보세요" |

⚠️ **게임 영향**: PremiumGarage Id를 넣는 순간 **패스가 없는 모든 플레이어**가 정비소에서만 자기 차를 부를 수 있게 됩니다(지금 place는 어디서든 호출 가능). 원하지 않으면 `Config.GARAGE.REMOTE_LOCK = false`(Config.luau:88). GW_CONFIG에는 이 스위치가 없어서 소스 수정과 재번들이 필요합니다.

**테스트 스위치** **[V]** (`Ownership.luau` `studioSet` / `adminFree`). workspace 속성이고 실행 중에 바꿔도 반영됨(`GetAttributeChangedSignal`):
- `GwPassesStudioTest = true` (Bool): Studio 전용. 모든 패스 소유
- `GwPassesStudioTest = "garage,flex"` (String): Studio 전용. 나열한 것만 소유. alias는 `garage|qol|flex` 또는 key 이름, 대소문자 무시
- `GwPassesAdminFree = true`: **live에서도 동작.** Player 속성 `GwangalliAdmin == true`인 사람(GwangalliLiveOps가 넣음: owner, group rank ≥254, `GwangalliLiveConfig.ADMINS`, unpublished place면 전원)에게 전부 지급. 단 live에서는 Id > 0일 때만

## 2. 서버 집행 (perk별, 모두 [V] 코드 확인)

ownership 판단은 전부 `Ownership.owns(player,key)`(서버 테이블)이고, 클라이언트 속성을 믿지 않음. 패스가 없을 때 응답은 `{ok=false, code="locked"}`.

| Perk | 집행 지점 | 패스 없을 때 |
|---|---|---|
| #1 원격 차고 잠금 | `Garage.luau:712` `Util.wrap(Spawn,"callOwned")`. place `GwangalliVehicles/Spawn.bindApi`의 `spawnOwned`가 `Spawn.callOwned`를 모듈 테이블로 부르므로 wrap이 적용됨. place Garage `opCall`이 이 경로를 씀 | `gateActive and not owns and not inZone`이면 `false, gate_refuse` 반환하고 Event `{kind="gate"}`. **예외**: `spec.testDrive`(시승, 딜러 시승 포함), `spec.id=="test"`(Law 테스트 차), 프리미엄 id(`gwp_*`), `opts.gwAnywhere==true` |
| 정비소 구역 | `Garage.inZone:94`. tag `GarageShop` pivot에서 수평 130 studs(fallback `(-528,7,452)`), 또는 키오스크 40 studs 안. 0.5초마다 Player 속성 `GwPassAtGarage` 갱신 | — |
| 키오스크 | `buildStation`. `Workspace.GwangalliPassesWorld/VehicleCallStation`, tag `GarageReturn` + `(18,0,-1.4)`(fallback `(-542,6.7,477.2)`). Prompt를 쓰면 Event `station`이 가고 차 부르기 시트가 열림 | 누구나 사용 가능 |
| #1 프리미엄 차 4대 | `Garage.summon:327` (owns 확인, 4초 쿨다운, `spawnOwned force=true`). 템플릿은 `Spawn.template` wrap(`:702`). `Cars.install(VS,true)`가 서버 `VS.Specs`와 `Drivable`에 추가 | `locked` |
| 도색 / 출장 정비 | `Garage.setPaint:389`, `Garage.repair:429` (GarageAPI `cars` → `GS.repairCost × REPAIR_FEE_MULT` → GameplayAPI `spend` → GarageAPI `setCondition 100`, 실패하면 `earn`으로 환불) | `locked` |
| 패스를 잃을 때 | `Garage.start`의 onChanged에서 프리미엄 차가 나와 있으면 despawn | — |
| #3 유치장 ×0.5 | `Waits.jailWrapper:39`를 `Law/Jail.begin`에 wrap(`:65`). `episode.seconds × 0.5`(최소 15초, 올림), episode 복사본 사용. 보석금은 place 공식(left/total)을 그대로 따름 | 원래 시간. **이미 수감 중에 사면 다음 체포부터 적용** |
| #3 기절 | `Waits.koHelpWrapper:160`를 `Arms/KOSystem.koHelp`에 wrap(`:189`): 10초(20×0.5) 뒤 이송 버튼 허용. 0.5초 tick: 119 미출동이면 47.5초(95×0.5), 119 출동 후 "waiting"이면 75초(150×0.5)에 강제 이송. "arrest" 모드, firstaid, transport 중에는 안 함 | 원래 시간 |
| #3 실제 사망/리셋 | `Waits.luau:239` `hum.Died`에서 `RespawnTime×0.5`(최소 0.5초) 뒤 `LoadCharacter`. `CharacterAutoLoads`가 true일 때만 | Roblox 기본 |
| #3 폰 블랙마켓 | `Market.open:96` / `Market.state:74`. 플레이어마다 서버 전용 shop `dealer:gwphone_<UserId>`를 HRP에 anchor(radius 8)하고 ArmsAPI `openShop`으로 엶(place `WeaponShopSystem.luau:1181-1187`에 op가 있음). place의 street check(경찰, SWAT, 총성, 추격, KO, 수갑, 탑승)는 그대로 적용 | `locked`. 탭이 흐리게 보이고 문을 누르면 구매 프롬프트 |
| #4 번호판 | `Plate.set:201`: `Plates.validate`(2~8자, 공백 포함 10자 이하) → 20초 쿨다운 → `TextService` filter(결과가 원문과 달라지면 거절) → `Data.claimPlate`(서버 간 유일) → 저장, `GwVanityPlate`/`GwPlateStyle`. 차에 적용: `GwangalliPlayerCars.ChildAdded`에서 `DriveOwnedCar`이고 렌트·시승이 아니고 비프리미엄이면 적용, 프리미엄은 summon 안에서 적용(VIP는 기본 gold) | `locked` |
| #4 네온 닉네임 | `NeonName.set:87` / `push`: `GwNeonName` 속성. 켜져 있으면 Humanoid `DisplayDistanceType=None`. 처음 지급 시 기본 "bridge". 끄면 `"off"`로 저장 | `locked` |
| #4 KO 피니시 | `Finish.luau`: `GwangalliCrimeBus`의 `KnockedOut`(kind=="player", by=UserId), `NpcKnockedOut`, `OfficerDown`(payload 필드는 place `KOSystem.once:165` 등과 일치 **[V]**). 공격자당 1초, 서버 전체 12/s, 반경 220 studs. 미리보기 3초 간격 | 이펙트 없음, `locked` |

## 3. 공개 API와 사용처

- **서버 권위 API** (`Api.luau`): `ServerStorage.GwangalliPassesAPI` BindableFunction
  - `Invoke("has", player, "garage"|"qol"|"flex"|key)`, `"owned"`, `"available"`, `"catalog"`, `"summon"`, `"plateOf"`, `"canCallAnywhere"`, `"atGarage"`
  - `ServerStorage.GwangalliPassesChanged` BindableEvent `(player, key, owned)`
- **Shared** (`GwangalliPassesShared/init.luau`), 양쪽에서 사용 가능:
  - `P.has(player,k)`: Player 속성 `GwPass_<Key>`를 읽음
  - `P.changed(player, fn(key, owned))`: `AttributeChanged` 기반
  - `P.available(k)`, `P.idOf`, `P.key`
- **사용처** **[V]** grep 결과:
  - `GwangalliClinic/Bridge.luau:517-526` `hasPass`가 `has(player,"qol")`를 30초 캐시로 호출. Clinic 대기 ×0.5(`GwangalliClinicShared/Config.luau:135`, Queue/Visit). 이 perk는 Config의 `Convenience.Perks` 설명에 **빠져 있음**
  - **CarDealer는 Passes API를 전혀 쓰지 않음.** Dealer의 "프리미엄"은 가격 카테고리(`GwangalliCarDealerShared/Catalog.luau:34,56,136`: luxury이거나 신차 400만 이상)이고 패스와 관계없음
  - Dealer `OPS.deliver`(`Service.luau:503`)는 Garage `request "call"`을 거치므로 **잠금 대상**입니다. 정비소 구역(130) 밖이면 패스 없는 구매자는 거절됨. 시승은 `testDrive`라서 예외
- **기존 place 시스템 연동**: Id > 0이면 `ReplicatedStorage.GamePassConfig`에 3개 패스를 런타임 주입(서버 `Ownership.injectStore:145`, 클라이언트 `StoreHook.inject`). Perk 필드가 있어서 R$ 앱의 "boost" 그룹에 나옴(`GwangalliStore.list`).

## 4. 저장 (DataStore) [V] `Data.luau`

| Store | Key | 값 |
|---|---|---|
| `GwangalliPasses_v1` | `u_<UserId>` | `{v=1, garage={paint={[carKey]=paintId}}, plate={text?, style}, neon=id/"off"?, ko=id/"off"?, t}` (sanitize 거침) |
| `GwangalliPlates_v1` | `Plates.claimKey(text)` = `"p_"` + 공백 제거한 각 codepoint의 base36(4) | 소유자 UserId (0 = 해제) |

- 로드는 3회 재시도. 실패하면 이번 세션은 기본값만 쓰고 **저장하지 않음**(덮어쓰기 방지).
- Studio에서 API 접근이 꺼져 있으면 재시도 없이 메모리만 씀.
- 저장: 8초 debounce, 퇴장 시, BindToClose(최대 20초).
- 로드 전에 바뀐 설정은 pending으로 쌓였다가 로드 후 다시 적용됨.
- 입장 시 저장된 번호판을 다시 claim함.
- 패스 소유 자체는 저장하지 않음(매번 `UserOwnsGamePassAsync`). 프리미엄 차는 Garage `d.cars`에 들어가지 않음(3대 제한, 판매, 할부와 무관).

## 5. Studio에서 perk별 검증 절차 (테스터용)

**준비**
1. v7 place에 파일 2개를 넣음(또는 Rojo). Game Settings > Security > *Enable Studio Access to API Services* 켜기(저장 테스트용. 끄면 메모리만 씀).
2. Play 전에 Workspace 속성 `GwPassesStudioTest`를 추가. 실행 중에 바꿀 때는 **Server view**에서 바꿔야 함(Client view에서 바꾸면 반영 안 됨).
3. Output에 `[GwangalliPasses] ready · VIP 패스`가 떠야 함. `ReplicatedStorage.GwangalliPassesRemotes`의 속성 `GwPassesReady`(JSON)에서 garage, gate, jail, ko, market, kofx, plate, neon이 모두 true인지 확인(일부는 최대 150초 뒤 늦게 켜짐). Player 속성 `GwPass_PremiumGarage/Convenience/Flex`도 확인.

**#1 프리미엄 차고**
1. 스위치 `"qol,flex"`(차고 없음): 정비소에서 멀리 간 뒤 🚗 내 차 → 부르기 → "🔒 원격 차고 잠김" 다이얼로그(길찾기 / 패스 구매).
2. 광안 오토 정비소로 감: `GwPassAtGarage = true`가 되고 호출됨. 키오스크 Prompt "차량 호출"로 시트가 열림.
3. 스위치 `true`: 어디서든 호출됨. 👑 VIP(HUD "🚗 내 차" 아래 버튼, `/패스`, `/vip`, 폰 독 5번째 칸) → 차고 탭 → 4대(광안 GT-X 210km/h, 광안 GT 195, VIP 블랙 에디션 178, 몬스터 오프로더 145) "바로 내 옆" 호출, 도색 14종 저장, 출장 정비(손상된 내 차, 정비소 가격).
4. 프리미엄 차가 나와 있을 때 스위치를 끔: 차가 사라져야 함.
5. 210km/h 주행 안정성은 **반드시** 직접 몰아 볼 것(place 주행 코드는 165km/h까지만 확인됨 **[A]**).

**#3 편의 패스**
1. 체포(수배 → 경찰 NPC): 토스트 "⚡ 편의 패스 · 유치장 X → Y"가 뜨고 `LawJail` 남은 시간이 절반(최소 15초)인지 확인. 비소유자와 비교.
2. 기절(NPC와 싸움, 또는 Test > Clients and Servers 2인): 10초에 "병원으로 이송" 버튼이 나오는지, 상단 칩 "⚡ 편의 패스 · N초 후 병원으로 이송돼요"가 약 47초부터 세는지, 시간이 되면 자동 이송되는지 확인.
3. Esc > Reset(KO 중이 아닐 때): `RespawnTime×0.5`(기본 2.5초) 뒤 리스폰.
4. VIP → 블랙마켓 탭 "🟢 보안 연결됨" → 기본 총기 / 조직 물건 / 탄약 → 기존 WeaponShopUI가 열리고 폰이 닫힘. 경찰 근처, 차 안, 추격 중에는 거절 문구.
5. Clinic 진료 대기가 절반인지 확인.

**#4 과시 패스**
1. 꾸미기 → 번호판 `12가 3456` + 스타일(classic, ev, retro, gold, carbon, neon) 저장 → 내 차를 부르면 앞뒤 번호판에 반영. 거절 케이스: 이모지, 자모(ㅋㅋ), 숫자만, 1자, 9자 이상, 20초 쿨다운, 같은 번호판(2인 테스트로 "이미 누가 쓰는 번호판이에요").
2. 네온 6종(bridge 기본, sunset, gold, aurora, ice, rainbow): 머리 위 그라데이션 태그가 뜨고 기본 이름은 숨겨짐. 채팅 이름 그라데이션. 2인 테스트로 다른 사람 화면에서도 확인.
3. KO 이펙트 6종(lightning 기본, fireworks, skull, stars, money, stamp): 미리보기 → NPC를 주먹으로 KO → 반경 220 안 모든 사람에게 이펙트가 보이고 공격자는 승리 포즈.

## 6. 트러블슈팅

| 증상 | 원인 / 확인 |
|---|---|
| live에서 VIP 버튼, 폰 아이콘이 안 보임 | Id = 0, 또는 번들 GW_CONFIG에 안 넣고 Config.luau에만 넣음, 또는 재번들로 0으로 돌아감. Studio에서 `ReplicatedStorage.GwangalliPlus` 속성 `PassId_*` 확인 |
| 산 패스가 적용 안 됨 | `UserOwnsGamePassAsync` 실패(3회 × 4초). 300초마다 다시 확인. 구매 직후는 `PromptGamePassPurchaseFinished`로 바로 지급되고 8초 뒤 재확인(취소하지 않음) |
| 탭에 "이 기능은 지금 준비 중이에요" | `GwPassesReady`에서 해당 키가 false. Output의 `[GwangalliPasses] garage/jail/ko/market/kofx: ...` 경고 확인. 원인: `GwangalliVehiclesAPI`, `GwangalliGameplay/Law/Jail`, `Arms/KOSystem`, `GwangalliArmsAPI`, `GwangalliCrimeBus`가 없거나 늦게 생김(150초 대기) |
| Studio에서 갑자기 내 차가 정비소에서만 불림 | Studio에서 Id = 0이면 잠금이 켜짐(정상). `GwPassesStudioTest="garage"`로 해제 |
| 130~160 studs에서 "정비소인데 거절" | 우리 구역은 130, place Garage의 자체 "정비소" 판정은 150~170(`Config.luau:89`). `ZONE_RADIUS` 조정 |
| 폰 VIP 아이콘이 2개 | 패치를 적용했는데 `PhoneNative` 속성이 늦게 붙음(번들 모드에서 Shared placeholder가 아직 복제 안 된 경우). 패치를 빼거나 확인 |
| 채팅 네온 안 됨 | `TextChatService.OnIncomingMessage`는 콜백이 하나뿐이라 다른 스크립트가 덮어씀(`ChatNeon.luau:32`) |
| 번호판 저장이 항상 거절 | Studio TextService filter 실패도 거절됨(`plate_filter`). 게시된 place와 API 접근 확인 |
| 블랙마켓 "연결 안 됨" 고정 | ArmsAPI `shopState` probe가 60초 안에 응답 안 해도 `Market.ready = true`가 됨. 실제 원인은 Arms 쪽에 있음 |

## 7. 리뷰·테스트 안 된 것과 알려진 위험

**코드를 읽어서 찾은 버그 후보 (런타임 미재현)**
1. **[V-read] Ownership과 place `GwangalliPassPerks` 경합.**
   - 서버 `injectStore`로 우리 패스가 `GamePassConfig`에 들어가면, PassPerks(`storeKeys()`가 매번 동적으로 계산)도 우리 키를 `UserOwnsGamePassAsync`로 확인하고 `GwPass_<Key>=true`를 직접 넣습니다. PromptGamePassPurchaseFinished도 마찬가지.
   - 우리 `publish`(`Ownership.luau:77-96`)는 "속성의 이전 값"과 비교하므로, PassPerks가 먼저 true를 넣으면 **onChanged 리스너와 `GwangalliPassesChanged`가 한 번도 실행되지 않습니다.**
   - 결과: live(Id > 0)에서 네온 닉네임이 자동으로 켜지지 않거나 재입장 후 꺼짐(`NeonName` push/ensureDefault), `GwKoFx`·`GwVanityPlate` 속성이 비어 UI 상태가 틀림. 이펙트 발사와 차 번호판 적용은 live 판정이라 동작함.
   - 수정안: `publish`에서 속성 대신 내부 테이블 `published[player][key]`와 비교. 또는 서버 측 주입 끄기(클라이언트 주입만으로 R$ 앱 목록에는 충분).
2. **[V-read] 출장 정비 저장 누락 가능.** place GarageAPI `setCondition`(place `Garage.luau:1301-1311`)은 `s.dirty`를 켜지 않습니다. 수리 후 운전하지 않고 나가면 cond 100이 저장되지 않을 수 있음(돈은 이미 차감됨).
3. **[V-read] Plate.start가 동기 실행에서 `GwangalliGarageShared`를 최대 90초 기다림.** 없으면 init 전체(NeonName, Waits, Api, `Net.publish`)가 지연됨. v7에는 있으므로 위험 낮음.
4. **[V-read] Data.save 중복 방지.** debounce 저장 중에 퇴장하면 final save가 건너뜀(`if st.saving then return`). 그 사이 변경분이 유실될 수 있음(작음).
5. Dealer 배송은 잠금 대상(3절 참고). Api 주석은 "gwAnywhere를 넘겨라"라고 하지만 place `opCall`이 opts를 넘기지 않아서 불가능.

**검증 안 된 영역**
- 프리미엄 차 실제 스폰, 리깅, 주행: 하이퍼 210km/h, CarBodies의 부품 차체, VIP와 오프로더 키트.
- 폰 독 주입 레이아웃, Hub(phone/panel), 게임패드.
- KO 이펙트 시각과 성능(MAX_LIVE 3). 사운드 asset `rbxassetid://82235785832022`, `132504023010884`가 존재하는지 미확인(fb fallback 있음).
- 네온 태그와 GwangalliLabelDeclutter 충돌 여부.
- 실제 구매, 결제 흐름. DataStore 서버 간 유일 번호판.
- 콘텐츠 규칙 점검: '해골 마크'는 만화풍이고 '처형'·'피' 단어 없음(테스트로 확인).

**참고 자료**
- `devkit/feat/passes/research.md`: 설계와 place 연동 조사 **[A]**. "PassPerks 중복은 무해"라는 결론은 위 1번 때문에 **틀림**.
- 오프라인 테스트: `devkit/feat/passes/tests/{gen.py,body.luau}` + `t/lib/rbx.luau`. `gen.py`의 SRC가 `/home/user/-/src`로 하드코딩되어 있고 luau 바이너리가 필요함.
- 에뮬레이터 하니스: `devkit/feat/passes/studio/{build.py,gp*.js}`. 메모리 한계로 차 스폰 단계에서 OOM.

## 8. 체크리스트: Creator Dashboard에서 패스 3개 만들고 ID 넣는 작업자용

- [ ] Creator Dashboard > 해당 experience(광안리) > Monetization > Passes > **Create a Pass** × 3. 다른 기존 패스들과 같은 experience에서 만듦.

| Key | 이름(제안) | 추천가 | 설명 |
|---|---|---|---|
| `PremiumGarage` | 프리미엄 차고 | 799 R$ | 하이퍼카 · 슈퍼카 · VIP · 오프로더 + 어디서든 내 차 호출(원격 차고) · 출장 정비 |
| `Convenience` | 편의 패스 | 349 R$ | 유치장 · 기절 대기 시간 절반 + 폰 블랙마켓 앱 (+ 병원 진료 대기 50%) |
| `Flex` | 과시 패스 | 299 R$ | KO 피니시 이펙트 6종 · 나만의 번호판 · 네온 닉네임 |

- [ ] 아이콘(정사각 512×512) 업로드. *Item for Sale* 켜기. 가격 설정. 게임 안 표시 이름과 설명은 Config의 Title/Desc가 쓰이고 가격만 Roblox에서 가져옴.
- [ ] 각 패스의 **Pass ID**(숫자) 복사(Copy Asset ID 또는 URL).
- [ ] **번들 사용 시**: `GwangalliPlus.server.luau` 맨 위 `GW_CONFIG.PassIds`에 PremiumGarage, Convenience, Flex 입력. 그리고 **`tools/bundle_plus.py:116-118`에도 입력**(재번들 시 0으로 초기화 방지). `Config.luau`만 고치면 번들에서는 효과 없음.
- [ ] **Rojo 사용 시**: `Config.luau:14 / :34 / :53`.
- [ ] 결정 확인: PremiumGarage Id를 넣으면 비소유자의 원격 호출이 막힘. 원치 않으면 `REMOTE_LOCK = false`(Config.luau:88) 후 재번들.
- [ ] Publish하고 기존 서버 종료(Shut Down All Servers / Migrate). 새 서버부터 적용됨.
- [ ] Live 확인:
  - HUD 👑 VIP 버튼과 폰 독 아이콘이 보이는지
  - R$ 앱 부스트 목록에 3개가 실제 가격으로 나오는지
  - 부계정으로 구매하거나 Workspace `GwPassesAdminFree=true`(관리자 계정)로 perk가 켜지는지
  - 서버 Output에 `[GwangalliPasses]` 경고가 없는지
- [ ] 시작 전에 7절의 1번(Ownership 경합)을 고치는 것을 권장. 그렇지 않으면 live 소유자의 네온 닉네임이 들쭉날쭉할 수 있음.

---
Scratch(이번 세션, 읽기 전용 검증용):
- 테스트 재실행 사본: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/handoff/passes/tests/logic_test.luau`
- 번들 출력: `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/handoff/passes/bundle/GwangalliPlus.server.luau`, `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/handoff/passes/bundle/GwangalliPlus.client.luau`
- 에뮬레이터 로그(이전 에이전트): `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/passes/studio/run1.log`
- place 원본 덤프(연동 확인용): `/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/eff/`