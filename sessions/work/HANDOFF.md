# 알바 세션 인계 메모 (NPC 세션 → 알바/콘텐츠 세션)

이 폴더(`sessions/work/scripts/`)는 **빌드에 들어가지 않아요** (`tools/repack.py`는 `scripts/`만 묶음).
NPC 세션에서 만들다 멈춘 알바 시스템 초안을 지우지 않고 여기 보관했어요. 알바 세션에서 필요한 것만
`scripts/`로 옮겨 쓰면 돼요.

## 역할 분담

| NPC 세션 (빌드에 포함) | 알바 세션 (이 폴더 / 나중) |
|---|---|
| 손님 NPC의 **행동**: 입장, 줄 서기, 말풍선 주문, 인내심 막대, 재촉, 칭찬·불만·화내고 나가기, 단골(동네 주민) 호감도 | 출근·퇴근, 급여, 알바 레벨·숙련도, 미션, 보상, 메뉴, 음료/계산 채점, 랜덤 업무 이벤트, 알바 UI |
| `ReplicatedStorage/GwangalliCustomerShared.luau` (성격·대사·가게 위치) | `GwangalliWorkConfig` / `GwangalliWorkShared` / `Work*.luau` / `GwangalliUnifiedWork*` |
| `ServerScriptService/GwangalliGameplay/Customers.luau` | |

빌드에는 v0.3 원본 `Work.luau` / `WorkCafe.luau` / `WorkOrders.luau`가 그대로 들어가요 (수정 없음).

## 연결 지점 (이것만 지키면 양쪽을 따로 고칠 수 있어요)

손님 모듈은 **`WorkOrders`의 공개 함수만** 써요:

```lua
WorkOrders.registerProvider(storeId, { name = "npc-session", onCall(order), onResult(result), onCancelled(order, reason) })
WorkOrders.placeOrder(storeId, customerId, nil, { name, patience?, group?, meta = { persona, strict, citizenId, npc = "npc-session" } })
WorkOrders.receive(orderId)          -- 손님이 픽업대에 도착했을 때
WorkOrders.cancel(orderId, "left")   -- 손님이 그냥 나갈 때
WorkOrders.view(order, now)          -- 말풍선에 띄울 주문 내용 (items[i].text)
```

- 가게 열림 조건: 그 가게 직업으로 근무 중인 플레이어가 있음 (`player:GetAttribute("GwWorkShift") == job`)
  **그리고** `ctx.work.handles(job)` 이 true.
- `result.reaction` = `thanks | ok | complain | angry | left`, `result.remake = true`면 손님이 불평하고 다시 기다려요.
- 진상(`meta.strict`)·단골(`meta.persona == "regular"`)을 채점/팁에 반영할지는 알바 세션 결정이에요.
  손님 모듈은 진상의 `complain`을 `angry`로, 단골의 `ok`를 `thanks`로 **보여 주기만** 해요.
- 이벤트: `ServerStorage.GwangalliCustomerEvents` (`arrive` / `order` / `react` / `tip` / `leave`). 단골 팁 지급은 알바 세션 몫이에요.
- 새 가게 추가: `ServerStorage.GwangalliCustomersAPI:Invoke("registerSite", "gs25", spec)` 또는
  `GwangalliCustomerShared.SITES`에 항목 추가. GS25는 건물의 `GwJobStation` 표식(door_out / door_in /
  queue1..3 / browse1..4)을 그대로 써요. 강제 열기/닫기: `("setOpen", siteId, true|false|nil)`.

## 이 폴더 파일 상태 (만든 에이전트 보고 기준)

| 파일 | 상태 |
|---|---|
| `WorkCustomers.luau`, `GwangalliWorkLines.luau` | 손님 NPC 첫 버전 (Work.luau 내부에 붙는 방식). NPC 세션은 대신 `Customers.luau`를 씀 — 대사는 `GwangalliCustomerShared`로 옮김 |
| `WorkStore.luau` | 편의점 시뮬 (카드 계산·택배·환불 테스트됨, 현금/신분증/이벤트/진열/마감은 미검증) |
| `WorkDelivery.luau` | 배달 시뮬 (한 번 접수→포장→전달 확인, 나머지 미검증) |
| `Work.luau`, `WorkCafe.luau`, `WorkOrders.luau`, `GwangalliWorkConfig.luau`, `GwangalliWorkShared.luau` | v0.3 원본 + 수정본 (레벨 등급, 정산 추가 항목, 버그 수정: shot 힌트 machine1, claimFor 사이즈, 카운터 닦기 힌트) |
| `GwangalliUnifiedWork.client.luau` + `GwangalliUnifiedWork/` | 알바 HUD (렌더 확인, 마지막 레이아웃 수정 미검증) |

참고: `ctx.onShift`(GwangalliGameplay.server.luau)는 옛 Jobs만 봐요. 새 Work 근무도 "근무 중"으로
치려면 `return Jobs.onShift(player) or (ctx.work ~= nil and ctx.work.onShift(player))`.
