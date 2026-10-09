# 광안리 인생게임 — 추가 시스템 (임시 스튜디오 빌드)

이 저장소는 **광안리 임시 스튜디오 플레이어 HTML**(Roblox 플레이스를 브라우저에서 돌리는 에뮬레이터)에
스크립트를 덧붙여 다시 묶는 작업 공간이에요. 기존 맵·차량·건물·상점·NPC 대화·호감도·전투 코드는
**지우거나 되돌리지 않고** 그 위에 추가했어요.

## 폴더

| 경로 | 내용 |
|---|---|
| `base/src/` | 기준 빌드(Vehicle v0.3 Integrated)에서 꺼낸 원본 스크립트 전체 (참고용, 직접 수정하지 않음) |
| `scripts/` | 새로 추가하거나 바꾼 스크립트만. 경로 = Roblox 인스턴스 경로 (`Name.luau` ModuleScript, `.client.luau` LocalScript, `.server.luau` Script) |
| `tools/extract.py` | 플레이어 HTML → 스크립트 폴더 |
| `tools/repack.py` | 기준 HTML + `scripts/` → 새 플레이어 HTML (같은 경로는 교체, 없는 경로는 추가) |
| `dist/` | 완성된 플레이어 HTML (브라우저로 열면 바로 실행) |

```bash
python3 tools/extract.py 기준.html base/src            # 원본 꺼내기
python3 tools/repack.py 기준.html dist/새버전.html --label "버전 이름"
```

## 1. NPC 생활 · 마음 (Mind)

- 102명 명단(`GwangalliCitizens`) — 시민·학생·직장인·취객·노숙자·걸렁뱅이·불량배·동네바보·경찰·점원/알바·부자·관광객, 시간대별 일과표.
- 머리 위 말풍선 대화(플레이어 대사 포함), 자유 입력 + 칩, 같은 말 반복 금지, 장소·시간·날씨·관계·지난 대화 기억.
- 호감도·신뢰도·분노도·공포도·친밀도, 취향 알아내기, 번호 교환, 휴대폰 **인맥** 앱(전화·문자·약속).
- NPC끼리 대화·싸움, 동네바보 장난(어깨빵·길막·따라오기), 걸렁뱅이 시비.
- 이름 없는 행인도 시간대에 따라 출근·카페·편의점(아침) / 식사(점심) / 식당·술집(저녁) / 술자리(심야), 심야엔 일부가 취객.

## 2. 치안 (Law) — `ServerScriptService/GwangalliGameplay/Law*`

서버가 모든 것을 결정해요. 계약(숫자·속성·대사)은 `ReplicatedStorage/GwangalliLawShared.luau`.

| 모듈 | 하는 일 |
|---|---|
| `Law.luau` | 수배 단계(0~5★) 단일 관리, 범죄 → **신고 대기** → 신고 접수 시에만 수배 + 출동, 경찰이 못 보는 동안만 수배 감소, 벌금(현금 → 통장 → 미납 자동 징수), 압수, 전과, 저장 |
| `Law/Police.luau` | NPC 경찰: 도보 경찰·순찰차·도로 차단·검문·증원·평시 순찰. 일부러 허술함(시야 밖이면 마지막 목격 위치로, 갈림길 실수, 계단·골목에서 멈칫, 제압 실패) — 수배가 오를수록 강해짐 |
| `Law/Jail.luau` | 체포 → 수갑 → 경찰차 탑승 이송 → 광안지구대 유치장. 남은 시간 UI, 앉기·수감자 대화·인사·팔굽혀펴기·공기놀이(시간 단축)·보석금 |
| `Law/Cop.luau` | 플레이어 경찰 직업(패스 ID `LS.POLICE_PASS_ID`, 0 = 테스트용 무료). 근무·신고 목록·수배자·순찰·순찰차·차량 조회·수갑·호송·인계·범칙금. **수배/신고된 범죄가 있는 사람만 체포 가능**, 부당 체포 → 평판 하락 + 체포 기능 제한 |
| `Law/Crimes.luau` | 소범죄(편의점 절도·소매치기·자전거 절도·차량 절도·폐차장·작은 상점 털기·불법 배달)와 조직 범죄(금고 털이·고급 차량·밀수·구역 다툼: 긴 준비 + 큰 위험 + 큰 보상, 패스는 문만 열어 줌) |
| `Law/City.luau` | 도시의 NPC 사건(밤에 더 많음) → 신고 목록 + NPC 경찰 출동, 플레이어 경찰도 검거 가능 |

수배 단계: 1★ 근처 경찰 1~2명(경범죄는 검문 후 범칙금) · 2★ 순찰차 · 3★ 순찰차 여러 대 + 도로 추격 · 4★ 증원 + 검문 + 도로 차단 · 5★ 특별 수사대.

클라이언트: `StarterPlayerScripts/GwangalliLaw.client.luau` (수배 카드·무전·검문 대화·체포 요약·유치장·👮 경찰 패널·🕶️ 뒷골목 패널·👛 소매치기 버튼·목표 지점 표시).

### NPC 가시성 버그 (원인과 수정)

- **원인**: 임시 스튜디오 엔진은 NPC 리그가 Workspace에 들어오는 순간 루트 기준 각 파트의 위치를 기록하고,
  **루트에서 40 스터드 넘게 떨어진 파트는 루트를 따라가지 않게** 해요. 행인 풀(`GwangalliStreetLife/Pool`)·경찰·사건 NPC·
  유치장·손님은 리그를 원점에서 만든 뒤 **루트만** 옮기고 붙여서, 몸 파트가 맵 원점에 남아 이름표·얼굴만 보였어요
  (측정: 수정 전 행인 15/15·경찰 전원 머리가 (0,0) → 수정 후 0/15, 0/33).
- **수정**: 모든 생성 지점에서 `model:PivotTo()`로 리그 전체를 옮긴 뒤 붙여요. Law 리그·손님은 `ModelStreamingMode = Atomic`
  (실제 Roblox StreamingEnabled 대비), 경찰차는 `Persistent`. NPC 클라이언트는 루트가 늦게 스트리밍돼도 다시 등록해요.
- 이 엔진은 NPC 자세를 **애니메이션 트랙**으로만 그려요 (관절 직접 변형은 안 그림) → 차 안 경찰은 R15 앉기 트랙을 재생해요.

### 경찰 출동 (GTA 스타일)

| 단계 | 동작 |
|---|---|
| 스폰 | 신고 지점에서 도로를 거슬러 260~600 스터드, 모든 플레이어에게서 220 이상 + 시야 밖 |
| 탑승 | 운전석·조수석에 경찰관이 처음부터 앉아 있음 (`NpcSeat` → 클라이언트가 매 프레임 좌석에 고정) |
| 주행 | 경로(`LawPath`/`LawT0`)를 서버는 Heartbeat마다, 클라이언트(`GwangalliLawCars`)는 렌더 프레임마다 샘플링 — 순간이동 없음. 코너는 경로 속도 프로필로 감속(예: 직선 60 → 급코너 11 스터드/초) → 재가속 |
| 추적 | 최신 위치가 35 스터드 이상 바뀌면 재계획: 현재 위치·방향·속도에서 이어서 앞쪽 차선으로 합류 (방향 튐 없음) |
| 정차 | 용의자 9 스터드 앞 보도 쪽, 여러 대면 19 스터드 간격으로 줄지어 정차 |
| 하차 | 운전자 → 0.6초 뒤 조수석: 좌석 → 문 → 도로 옆으로 걸어 나와 잠깐 선 뒤 달림 |
| 도보 추격 | 플레이어가 걸어서 도망 / 골목·해변처럼 차선이 28 스터드 안에 없으면 근처에 세우고 도보로 |
| 차량 추격 | 용의자가 차를 타면(2★+) 내린 경찰이 차로 돌아와 타고 도로 추격, 1.2~2초마다 매끄럽게 재계획 |
| 종료 | 밖에 있는 경찰이 걸어 돌아와 탄 뒤 출발 (못 오면 남아서 걸어감) |

### 길거리 싸움 (Fight)

- `ReplicatedStorage/GwangalliFightShared.luau` (계약), `ServerScriptService/GwangalliGameplay/Fight.luau`, `StarterPlayerScripts/GwangalliFight.client.luau`
- **자체 공격 버튼·HP바 없음 — 기존 공격이 들어오는 수신기.** 전투 시스템은 *실제로 맞은* 공격만 넘겨요:
  - 클라이언트: `LocalPlayer.GwangalliNPCHitAPI:Invoke("hit", { model = <히트박스에 닿은 NPC 모델/파트>, attack = "punch"|"kick"|"shove"|"strong", power = 0..2 })` (`Invoke("resolve", model)` → `{ kind, id }`)
  - 서버: `ServerStorage.GwangalliNPCHitAPI:Invoke("hit", player, { model | kind, id, attack, power })`
  - 어깨빵·대화 카드 "때리기"·차량 충돌도 같은 서버 코드로 들어감. 서버가 거리(사거리)·높이를 다시 확인하고 빗나간 건 무시
  - **NPC HP는 Fight가 가짐** (전투 시스템은 이 대상들의 HP를 따로 두지 말 것): 데미지·치명타·넘어짐/날아감·**기절(HP 0)**·반응·범죄(Law) 전부 서버 판정
  - 대상: 거리 보행자(클라이언트 리그, `StreetId`)와 `NpcId`가 있는 서버 NPC 리그 (핵심 NPC·경찰·특임대·119·손님·가게 직원). 교도소 수감자, 알바·미니게임 리그는 제외 (`GwangalliFightShared.foreign`)
- 맞은 NPC 반응 (유형·성격·HP): **반격**(실제로 여러 번 때리는 난투, 사거리 안·마주 볼 때만 맞음, 맞으면 플레이어 HP 감소 — 15 미만으로는 안 떨어짐) / **경고** / **도망** / **신고**(전화 → 경찰이 바로 앎) / 경찰은 **체포**. 핵심 NPC는 일어난 뒤에야 반격
- 기절: 그 자리에 누워 있고 주변 사람이 112 신고·도망, 26초 뒤 실려 감 (119가 오면 실어 갈 때까지). 이름 있는 시민은 10분간 "입원"(거리에 안 나옴). 범죄 `폭행치사`
- 핵심 NPC(가게·퀘스트)는 기절하지 않음 (넘어지고 신고). **걸어 다니는 경찰·특임대·119 대원은 HP 0이면 쓰러져** 모든 AI에서 빠지고, 119가 실어 가거나 시간이 다 될 때까지 누워 있음 (차 안에 앉은 대원은 쓰러지지 않음)
- 밤 취객 시비 (따라오며 시비 대사, 가까이 있으면 밀침, 멀어지면 포기) · 취객 싸움은 3~4번 주고받다 한 명이 넘어지고 구경꾼이 신고하면 경찰이 와서 말림
- 차량과 보행자: 플레이어 차가 스치거나(피함) 치면 그 보행자가 성격대로 반응 (노려보기·손가락질·기억, 겁먹기). **NPC끼리의 차량 접촉은 범위 밖** (NPC 차량 교통이 필요한데, 기본 차량 시스템은 건드리지 않음)

#### 생활콘텐츠 → NPC 사건 트리거

생활콘텐츠(또는 다른 서버 시스템)는 "사건이 났다"는 신호만 보내고, 배역·연출은 NPC 시스템이 해요.
코드 주석: `ServerScriptService/GwangalliGameplay/Fight.luau` 끝부분 `GwangalliNPCEvents` (이 내용과 맞춰 둘 것).

- 호출 (서버 전용): `ServerStorage.GwangalliNPCEvents:Invoke("incident", player, kind, { pos = Vector3?, id = string? })` → `true`면 보냄
  - `player = nil` + `pos` 필수: 장소 사건(포장마차·클럽 입구 등) → `pos` 120 스터드 안의 모든 플레이어에게 보냄, 한 명이라도 받으면 `true`
  - `pos`: 생략하면 플레이어 주변. `id`: 특정 시민/행인 id (없으면 근처에서 고름)
- `kind` 7가지
  | kind | 동작 |
  |---|---|
  | `drunk_quarrel` | 취객 시비: 취객이 플레이어를 따라오며 시비 대사, 가까우면 밀침 (근처에 없으면 이름 있는 취객·행인이 걸어 들어옴) |
  | `stall_fight` | 포장마차 싸움: 근처 술꾼 두 명이 말다툼 → 사과 / 말림 / 자리 뜨기 / 몸싸움 |
  | `street_fight` | 길거리 싸움: 근처 행인 두 명, 같은 결말들 |
  | `lost` | 길 잃은 사람이 다가와 길을 물음 (말 걸면 대답·감사) |
  | `help` | 도움 요청 (말 걸면 감사, 이름 있는 시민은 기억) |
  | `suspicious` | 수상한 사람이 따라옴 (말 걸면 들켜서 자리 뜸) |
  | `police_chase` | 서버(Law/City)가 `pos`(없으면 플레이어 주변 시야 밖)에 소매치기를 세우고 경찰이 바로 쫓음 — 서버 리그라 주변 모두가 봄 |
  - 싸움 배역: 경찰·동네바보·노숙자·배달 라이더는 안 뽑힘. `lost`/`help`/`suspicious`: 경찰·동네바보·불량배·취객은 안 뽑힘 (걸렁뱅이는 `suspicious`만)
- 결과 확인: 플레이어 속성 `GwangalliIncidentLast` = `"kind:true"`(누군가 배역을 맡음) / `"kind:false"`(아무도 없음)
- 주의: 거리 행인은 **클라이언트마다 따로** 시뮬레이션돼요 → `police_chase` 말고는 받은 플레이어 화면에서만 보임. 모두가 봐야 하면 `player = nil` + `pos`로 부르거나 플레이어마다 한 번씩 부를 것
- 테스트: Law `debug` act `incident` (`kind=...`), 디버그 모드에선 `workspace.GwangalliIncidentResult` = `"kind:ok:agentId"`

테스트 훅(디버그 모드 전용): Law `debug` — `carsOnly` / `noGrab` / `carDemo` / `fakeCar`, `GwangalliFightAPI` (goto / gopunch / gopunchModel / tp), MindAPI `quarrel` / `fightscene`.

## 3. 가게 손님 NPC (Customers) — 알바 시스템과 분리

이 세션은 **손님의 행동만** 맡아요: 입장 → 줄 서기 → 말풍선 주문 → 인내심 막대 + 재촉 → 픽업 →
칭찬 / 보통 / 불만 / 화내고 나가기. 성격: 평범·급한·취객·진상·학생(무리)·단골(동네 주민 → 호감도 반영).

- `ReplicatedStorage/GwangalliCustomerShared.luau` — 성격·대사(같은 말 연속 금지)·가게 위치
- `ServerScriptService/GwangalliGameplay/Customers.luau` — 손님 NPC (v0.3 `WorkOrders` 공개 함수만 사용)
- 출근·급여·레벨·숙련도·미션·보상 = **알바 세션**. 빌드에는 v0.3 원본 알바 코드가 그대로 들어가요.
  만들다 멈춘 알바 초안(편의점·배달·알바 HUD 등)은 `sessions/work/`에 보관 (빌드 제외) →
  연결 방법은 `sessions/work/HANDOFF.md`.

## 4. 경제 · 목표

- `Goals.luau` + `GwangalliGoals.client.luau`: 항상 보이는 **다음 목표** 카드 (차량 구매까지 남은 돈, 다음 집, 알바 숙련도, NPC 호감도, 수배, 범죄 해금, 경찰 진급, 연료, 미납 벌금).
- `Fuel.luau`: 내 차 연료(운전 거리만큼 감소, 0%면 시동 꺼짐) + SK 광안셀프주유소 주유.
- 돈 쓰는 곳: 음식·옷·휴대폰 상점·집·차량·정비·세차·견인·연료·선물·벌금·보석금·범죄 장비·미니게임 등.

## 5. NPC 자유 대화 — `GwangalliGameplay/Mind/Talk.luau` (+ 선택: `Mind/Brain.luau`)
- 직접 입력한 문장을 절(문장 단위)로 나눠 읽음: 인사 + 내 얘기 + 질문을 한 번에 말해도 각각 대답.
- 대화 맥락: NPC가 방금 한 질문의 대답("이름이 뭐예요?" → "민수야"), "너는?", "왜?", "진짜?", "뭐?", "ㅋㅋ", "나도!".
- 플레이어 정보 기억(`rec.pf`, 저장됨): 이름·직업·나이·고향·좋아하는 것·기분·한 일 → 다음에 만나면 먼저 꺼냄.
- 성격: NPC가 좋아하는 화제엔 신나고, 싫어하는 화제는 싫은 티 → 계속하면 거절·자리 뜸. 욕·같은 말 반복도 싫어함.
- 존댓말 → 반말: 친해지면 "말 놓을까?" (NPC가 먼저 제안하기도 함). 점원은 근무 중이면 주문·계산·봉투·메뉴 얘기.
- "노래방 갈래?"처럼 장소를 말하면 기존 약속 시스템(Relationships)으로 바로 약속. 번호·문자·호감도는 기존 그대로.
- Claude 연결(선택, 실제 로블록스만): HTTP 허용 + Secrets `ANTHROPIC_API_KEY` → 일상 대화를 Claude가 캐릭터로 답함. 욕·협박·고백·번호는 항상 규칙 엔진.

## 6. 배달 라이더 NPC — `GwangalliStreetLife/Delivery.luau`, `ReplicatedStorage/GwangalliRobShared.luau`
- 라이더 8명(오토바이 6 · 도보 2): 배달 박스/가방, 오토바이 위에 앉아 빠르게 이동, 가게 앞에 잠깐(3.5~8초) 섰다가 다음 가게로.
- 자유 대화 가능(배달 얘기, 긴 대화는 "콜 들어왔다!" 하고 떠남). 맞으면 놀라서 도망 / 신고 시도.
- 총 위협(총 Tool 들고 바라보면, 또는 무기 시스템이 API "threat" 호출): 성격(nerve)에 따라 항복(손 듦) / 얼어붙음 / 도망 / 112 신고 시도.
- 강탈 규칙(읽기 전용 데이터): 라이더 4.5~9만 원(항복하면 1.15배), 일반 행인 0.8~2.2만 원, 쓰러진(KO) NPC = 0원.
  - 클라: 모델 속성 `GwRobbable / GwRobReward / GwRobState / GwRobDead`, `LocalPlayer.GwangalliNPCRobAPI` ("info" / "list" / "threat" / "robbed"), 이벤트 `GwangalliNPCRobEvents`.
  - 서버: `ServerStorage.GwangalliNPCRobAPI` ("info", player, id) — HP/KO는 Fight 기준.
  - 돈 지급·수배·경찰·성공 판정은 범죄 시스템 담당(여기서 안 만듦).

## 7. 친구 퍼레이드 (Friend Avatar NPC) — `GwangalliFriendAvatars.server.luau`, `GwangalliStreetLife/Friends.luau`
- 로블록스 친구 중 최대 8명의 실제 아바타를 서버가 불러와(캐시) 그 플레이어에게만 보이게 함(최대 6명 동시).
- 저녁 만남의 광장(17~23.5시), 밤 클럽 앞(19~3시) 근처에 가면 행진 → 춤 → 다가가면 손 흔듦, 이름표 표시.
- 친구 아바타는 그대로 사용, 나쁜 역할 금지(강탈·싸움·경찰·신고 대상 아님), 멀어지면 제거.
- 에뮬레이터 테스트: `workspace:SetAttribute("GwangalliFriendAvatarTest", true)` (임시 이름 + 로스터 외형).

## 8. 특임대 (SWAT) — `Law/Swat.luau`
- 출동 조건: 수배 ★4 이상, 또는 대형 사건(은행 털이 `bank_raid` · 카지노 털이 `casino_raid` · 총격전 `gunfight`). 일반 경찰은 그대로.
- 플레이어 1명당 밴 1대(대원 4명), 최대 2팀. 경찰보다 HP 높고(320) 명중·엄폐·팀 이동(여러 방향 접근, 돌입 최대 2명)이 좋음.
- 차로 도주하면 밴에 타서 추격, 놓치면 마지막 목격 위치 수색(45초) 후 철수.
- 치트 금지: 벽 너머 추적 없음(시야 레이), 순간이동 없음, 명중 확률 상한 70%, 속도 제한. 시야를 끊거나 차를 바꾸거나 멀리 가면 도망칠 수 있음.
- 체력 25 이하면 잠깐 기절(이동 느려짐) → 체포 확률 상승. 총소리는 주변 시민이 듣고 도망.

## 9. 119 구급대 — `Law/Rescue.luau`
- 쓰러진 사람(KO) 발생 → 구급차 출동 → 운전 → 도착 → 하차 → 접근 → 응급처치 → 이송 → 병원 도착.
- 현장이 위험하면(싸움 · 총격 · 특임대 작전 · 수배자 근처) 조금 떨어진 곳에서 대기, 안전해지면 진입. 전투하지 않음.
- 서버 API: `ServerStorage.GwangalliRescueAPI`, `ctx.rescue.casualty({pos, id, kind, player})`.

## 10. 병원 NPC — `Law/Hospital.luau`
- 접수 1 · 의사 2 · 간호사 3 · 환자 3(교체) · 입원 환자 · 보호자: 복도 이동, 진료, 접수, 병실 이동, 짧은 대화, 응급실.
- 벽 검사한 격자 + A* 경로(1층/2층, 엘리베이터 이동). 병원 170스터드 안에 있을 때만 동작.
- 구급차가 도착하면 간호사·의사가 입구로 나와 환자를 응급 침대로.

## 11. NPC 성향 · 호감도 · 감정 — `ReplicatedStorage/GwangalliMindShared.luau`, `GwangalliGameplay/Mind.luau`
- NPC마다 성향 10가지(친절 · 소심 · 공격성 · 경계심 · 욕심 · 사교성 · 인내심 · 겁 · 호기심 · 정의감). 직업/타입 기본값 + 개별 성격.
- 플레이어별 호감도 -100~100 (적대 -100 · 증오 -70 · 싫어함 -40 · 불편 -10 · 보통 0 · 호감 20 · 친한 사이 50 · 절친 80 · 최고 100). 저장됨.
  - 오름: 인사·대화·선물·음식·도움·구조. 내림: 때림·어깨빵·도둑질·배신(선물 후 폭행)·총 위협·범죄 목격·쫓아다님.
- 감정: NORMAL HAPPY ANGRY SCARED SAD ANNOYED NERVOUS DRUNK.
- 관계가 나쁠 때 성격별 반응: 폭력적 → 째려봄/시비/공격, 소심 → 짧게 대답/피함/대화 차단/도망, 무관심 → 무시·폰 보며 대답·"시간 없어요", 겁 많음 → 도망, 정의감 → 경고·신고·피해자 도움.
- 같은 NPC에게 계속 말 걸면 "그만 좀 하세요." 후 일정 시간 대화 차단(성격마다 시간 다름).
- 위험하면 도망: 총 들고 있음, 총소리, 맞음, 폭력적인 플레이어 접근, 사이 나쁜 플레이어가 쫓아옴.
- 공격 결정: 공격성 · 관계 · 누가 먼저 쳤나 · 근처 경찰 · 무기 · NPC 체력 · 같이 있는 친구(크루).
- 밤(저녁 이후)에는 직장인 · 대학생 · 관광객 등이 술집거리(광안 먹자골목 · 민락 회타운)나 클럽으로 이동.
- 성능: 플레이어와 가까운 NPC만 자주 갱신, 멀면 느리게.

## 12. 가게 점원 NPC — `GwangalliGameplay/ShopStaff.luau`
- 맵의 가게(편의점 · 카페 · 빵집 · 식당 · 술집 · 약국 · 화장품 · 옷가게 · 미용실 · 호텔 프런트 · 마트 · PC방 · 부동산 · 은행 · 대여소 …)를 자동으로 찾아 카운터 뒤에 점원 1명.
  - 카운터 찾기: PosBase / POS / OrderKiosk / FrontDesk / BackBar / BarCounter / Counter (가게 모델의 ShopFloor 기준). 카운터 없는 사무실·집은 제외.
  - 이미 직원이 있는 곳(거리 가게 7곳 점원, PC방·볼링장·병원·정비소 직원, 키 NPC)과 알바 매장(스타벅스 광안리점 · GS25 광안리점)은 건너뜀.
  - 거리 가게 7곳의 기존 점원(움직이지 않던 것)은 애니메이션 + 말 걸기 추가.
- 가게 종류별 옷차림·동작(계산 · 닦기 · 컵 · 요리 · 타자 …), 가까이 가면 "어서 오세요~", "말 걸기"로 가게별 대사.
- 성능: 플레이어 150스터드 안의 가게만 점원 생성(최대 36명), 멀어지면 제거.
- 돈·주문·알바 로직은 없음(알바 세션 담당). 점원은 `workspace.GwangalliShopStaff`, 태그 `GwShopStaff`.

## 13. 길거리 인원
- 길거리 NPC 최대 50명(모든 품질 단계, 절전 모드 32명) — `GwangalliStreetLife/Config.luau` `Cap`.

## 14. 총기상 NPC — `GwangalliGameplay/WeaponDealer.luau`, 계약: `ReplicatedStorage/GwangalliWeaponDealerShared.luau`
- 뒷골목 3곳(먹자골목 켄트호텔 뒤 · 스타벅스 뒤 · 호메르스 뒤)에 총기상(칼자국 · 박씨 · 까마귀). 검은 옷 · 선글라스 · 모자, 팔짱 · 망보기 · 폰.
- **역할: 연결만.** 플레이어 감지 → 대화 → 거래 가능 여부 확인 요청 → 범죄 세션 WeaponShopSystem 호출 → (범죄 세션이) OpenWeaponShopUI.
  가격 · 성능 · 구매 · 돈 차감 · 총기 지급은 **없음**(범죄 세션 담당).
- 대화: [말 걸기] → "뭘 찾는데?" → 물건 좀 보여줘. / 그냥 지나가던 길이야. / 특별한 물건 있어? (기존 폰 대화창에 데이터만 보냄, UI 수정 없음)
  - 일반 플레이어: 기본 물건만 연결("기본적인 것들은 있다." "돈은 있지?" "괜히 문제 만들지 마."). 특별한 물건을 물으면 기본 물건만 권함.
  - 마피아: "너라면 위에 물건도 보여줄 수 있지." "새 물건 들어왔다." "일반 손님한테는 안 보여주는 거다." → special 요청.
    마피아 여부는 범죄/직업 쪽에서 읽기만 함(WeaponShopSystem access → 직업 속성 → 범죄 레벨 조직 수습). 실제 물건은 WeaponShopSystem이 결정.
- 성향: 경계심 높음 · 사교성 낮음 · 공격성 중간 · 겁 중간 · 낯선 사람에게 불친절. 호감도(총기상별, 저장됨):
  높음 → 부드러운 말투 · 적극적 / 낮음 → 퉁명 · 특별 물건 거부 · 가끔 거래 거부 / 매우 낮음 → 대화 차단(시간이 지나면 조금씩 회복).
- 위험: 경찰 · 특임대 · 경찰차 · 근무 중 경찰 플레이어가 가까우면 "오늘은 장사 안 한다." / 총격전 · 총소리 → 거래 중단, 숨었다가 조용해지면 복귀 /
  싸움판 → 대화 중단 / 총 든 손님 → 거래 안 함. 열린 상점은 WeaponShopCancel로 취소 신호.
- 공격당하면: 대화 · 거래 종료, 그 플레이어 5분 거래 차단(다른 총기상도 소문 듣고 2분 거부), 성격에 따라 반격(직접 주먹) 또는 도망. 어깨빵도 인식.
- 같은 대사 반복 방지(상황 · 호감도 · 직업별 대사 풀, 15분 안에 같은 말 안 함).
- 범죄 세션 연결 방법(둘 중 하나): `ctx.weaponShop = { request, access?, cancel? }` 또는 `ServerStorage.GwangalliWeaponShop`의
  RequestWeaponShop / WeaponShopResult / WeaponShopCancel / WeaponShopClosed 이벤트 + 폴더 속성 Ready=true. 자세한 건 계약 파일 주석.
- 총 시스템은 `ServerStorage.GwangalliGunfire`(BindableEvent: 위치)를 쏘면 총기상이 총소리에 반응.

## 테스트 방법 (개발용)

`workspace:SetAttribute("GwangalliStreetLifeDebug", true)` 일 때만 열리는 테스트 훅:
`LocalPlayer.GwangalliMindAPI`, `GwangalliPeopleAPI`, `GwangalliLawAPI` (BindableFunction, 명령은 클라이언트 스레드에서 실행),
Law 서버의 `debug` op (수배 설정·체포·유닛 목록).
