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

## 3. 알바 시뮬레이션 (Work)

카페(기존) + 편의점·배달·퀵 + 손님 NPC + 숙련도 + 랜덤 상황 — `GwangalliGameplay/Work*.luau`, `GwangalliUnifiedWork*`.

## 4. 경제 · 목표

- `Goals.luau` + `GwangalliGoals.client.luau`: 항상 보이는 **다음 목표** 카드 (차량 구매까지 남은 돈, 다음 집, 알바 숙련도, NPC 호감도, 수배, 범죄 해금, 경찰 진급, 연료, 미납 벌금).
- `Fuel.luau`: 내 차 연료(운전 거리만큼 감소, 0%면 시동 꺼짐) + SK 광안셀프주유소 주유.
- 돈 쓰는 곳: 음식·옷·휴대폰 상점·집·차량·정비·세차·견인·연료·선물·벌금·보석금·범죄 장비·미니게임 등.

## 테스트 방법 (개발용)

`workspace:SetAttribute("GwangalliStreetLifeDebug", true)` 일 때만 열리는 테스트 훅:
`LocalPlayer.GwangalliMindAPI`, `GwangalliPeopleAPI`, `GwangalliLawAPI` (BindableFunction, 명령은 클라이언트 스레드에서 실행),
Law 서버의 `debug` op (수배 설정·체포·유닛 목록).
