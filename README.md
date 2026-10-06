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
- 👊 주먹 (어깨빵 왼쪽 버튼 / F키) → 서버가 NPC HP·치명타·넘어짐·**기절(HP 0)** 판정, 머리 위 HP바 + 데미지 숫자
- 맞은 NPC 반응 (유형·성격): **반격**(실제로 여러 번 때리는 난투, 맞으면 플레이어 HP 감소 — 15 미만으로는 안 떨어짐) / **도망** / **신고**(전화 → 경찰이 바로 앎) / 경찰은 **체포**
- 기절: 그 자리에 누워 있고 주변 사람이 112 신고·도망, 26초 뒤 실려 감. 이름 있는 시민은 10분간 "입원"(거리에 안 나옴). 범죄 `폭행치사`
- 핵심 NPC(가게·퀘스트)는 기절하지 않음 (넘어지고 신고)
- 밤 취객 시비 (따라오며 시비 대사, 가까이 있으면 밀침, 멀어지면 포기) · 취객 싸움은 3~4번 주고받다 한 명이 넘어지고 구경꾼이 신고하면 경찰이 와서 말림

테스트 훅(디버그 모드 전용): Law `debug` — `carsOnly` / `noGrab` / `carDemo` / `fakeCar`, `GwangalliFightAPI` (goto / gopunch / tp), MindAPI `quarrel` / `fightscene`.

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

## 테스트 방법 (개발용)

`workspace:SetAttribute("GwangalliStreetLifeDebug", true)` 일 때만 열리는 테스트 훅:
`LocalPlayer.GwangalliMindAPI`, `GwangalliPeopleAPI`, `GwangalliLawAPI` (BindableFunction, 명령은 클라이언트 스레드에서 실행),
Law 서버의 `debug` op (수배 설정·체포·유닛 목록).
