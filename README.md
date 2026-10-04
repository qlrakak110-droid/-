# 광안리 해변 미니게임 거리 (Gwangalli Beach MiniGames)

광안리 오픈월드 인생게임(`광안리 임시 스튜디오 1.0 v2.0` place)에 추가하는 **해변 미니게임 시스템**입니다.
메뉴에서 고르는 미니게임이 아니라, 광안리 산책로를 걷다가 테이블·오락기·NPC를 만나 **실제 맵 안에서**
다른 플레이어 또는 NPC와 게임머니를 걸고 노는 콘텐츠입니다.

> **게임 내부 가상 화폐(원)만 사용합니다.** Robux, 개발자 상품, 현금이나 실제 가치가 있는 재화와 연결되거나
> 환전되는 경로는 코드 어디에도 없습니다 (`MS.VIRTUAL_CURRENCY_ONLY`). 모든 돈 처리는 서버의 기존
> 인생게임 장부(`ctx.spend` / `ctx.ledger`)를 통해서만 일어납니다.

## 들어 있는 것

| 게임 | 위치(산책로) | NPC (난이도) | 방식 |
|---|---|---|---|
| ⚫ 오목 | 만남의 광장 앞 / 민락 쪽 / 해변 동쪽 | 박씨 아저씨(일반), 김 사범님(고수) | 실제 3D 오목판, 흑백 랜덤, 30초 제한, 한국룰(흑 쌍삼·4-4·장목 금지), 무승부 제안, 기권, 재대결 |
| 💬 끝말잇기 | 관광안내소 앞 / 민락 쪽 벤치 | 민준(고등학생, 일반), 하준이(초등학생, 초보) | 10초 제한, 두음법칙, 중복 금지, 사전(2,825단어) + Roblox 텍스트 필터, 말풍선 |
| ✌️ 가위바위보 | 광안리 중앙 / 남천 쪽 | 하은(관광객, 초보), 동수 과장(일반) | 3·2·1 카운트, 3판 2선승, 손 애니메이션 + 손 모양 표시 |
| ⚡ 순발력 대결 | 해변 중앙 데크 옆 (오락기) | 태호(알바생, 일반) | 준비…지금!, 부정 출발, 서버 시간 판정 + 핑 보정 |
| 🧠 기억력 대결 | 호메르스호텔 앞 | 순자 할머니(일반) | 숫자 2~3초 표시 → 동시 입력, 라운드마다 길어짐 |
| 🔢 숫자 맞히기 | 축제의 광장 서쪽 | 덕배 할아버지(일반) | 1~100 업다운, 번갈아 추측 |
| 🎯 타이밍 게임 | 만남의 광장 옆 (오락기) | 지호(꼬마, 초보) | 움직이는 막대를 가운데에 멈추기, 3라운드 합산 |
| ❓ 퀴즈 대결 | 해맞이광장 옆 | 서연(퀴즈 동아리, 고수) | 90문제 은행(부산·상식·한국어·수학…), 먼저 맞히면 1점 |

* 12개 스팟이 한곳에 몰리지 않고 **산책로 벤치 그룹 사이사이**에 배치됩니다(파라솔 테이블, 스툴, 표지판,
  밤에 켜지는 랜턴, 해변 오락기). 배치할 때 바닥과 주변을 검사해서 벤치·화단·가로등과 겹치지 않는 자리로
  자동으로 조금씩 옮깁니다.
* 게임이 시작돼도 순간이동하지 않습니다: 자리에 앉음 → 카메라가 테이블로 이동 → 3·2·1 → 게임 → 결과 →
  카메라 원상복귀. 주변 NPC·차량·광안대교·파도는 그대로 보입니다.
* 지나가는 사람도 오목판 위의 실제 돌, 손 동작, 말풍선을 볼 수 있고, **[관전]** 하면
  `OOO VS OOO · 상금 · 스코어` 화면이 뜹니다. 관전자 베팅은 없습니다(설계상 제외).

## 흐름

```
산책 중 테이블 근처(14 stud) → 카드: [게임 참가] [상대 찾기] [친구에게 신청] [NPC와 연습]
  · 게임 참가   : 참가비를 골라 앉아서 기다림 → 지나가던 사람이 [⚔️ 도전하기 ₩10,000]
  · 상대 찾기   : 앉아서 기다리며 서버 전체에 "OOO님이 오목 대결을 찾고 있어요!" 알림 (먼저 수락한 사람)
  · 친구에게 신청: 친구/근처 사람 선택 → 상대 화면에 "OOO님이 오목 대결을 신청했습니다. 참가비 ₩10,000 [수락][거절]"
                 멀리서 수락하면 테이블 위에 🎯 표시가 뜨고 90초 안에 걸어오면 시작 (순간이동 없음)
  · NPC와 연습  : 그 자리 NPC와 바로 시작 (NPC는 성격·대사·난이도가 다름)
결과 카드: "OOO 승리! +₩20,000", 전적·승률·랭크 변화 → [🔁 재대결] (둘 다 누르면 같은 자리·같은 참가비로 바로)
```

참가비: 친선전(₩0) / ₩1,000 / ₩5,000 / ₩10,000 / ₩50,000. 보유 금액(현금 또는 통장 한쪽)보다 큰 참가비는
UI에서 비활성화되고 **서버가 다시 검증**합니다.

## 게임머니 처리 (서버 전용, `BetService`)

1. 대결 생성 시 양쪽 잔액을 **먼저 모두 확인** → 한 명씩 참가비 차감(현금 우선, 부족하면 체크카드) →
   두 번째 차감이 실패하면 첫 번째를 즉시 환불. 이때 돈은 경기(escrow)에 보관됩니다.
2. 게임 진행 (클라이언트는 "여기에 두겠다" 같은 **의도만** 보냄. 돈/결과를 보내는 경로 없음)
3. 승자 결정 → `settle()` 이 **정확히 한 번**만 실행됨: `settled` 플래그를 장부 기록 *전에* 세우고, 확인과
   설정 사이에 yield가 없어서 기권·나가기·시간초과가 동시에 와도 이중 지급이 불가능합니다.
4. 승자에게 판돈 지급 (`ctx.ledger`, 거래내역에 "광안리 미니게임 · 오목 상금"으로 남음)

나가기 규칙(서버가 결정):

| 언제 | 처리 |
|---|---|
| 앉는 중 / 3·2·1 카운트다운 | 경기 취소, 양쪽 참가비 전액 환불 |
| 경기 중 기권 버튼·접속 종료·사망/리스폰·테이블에서 22 stud 이상 8초 이탈 | 기권패: 상대가 판돈 획득 |
| 결과 화면 | 이미 정산 완료, 변화 없음 |
| 서버 종료(`BindToClose`) | 진행 중인 모든 판돈 환불 |

NPC 상대: 하우스가 같은 금액을 걸고, 이기면 참가비 + 하우스 몫을 받지만 **하루(KST) 순수익 ₩30,000 한도**가
있어 NPC로 돈을 찍어낼 수 없습니다. 초보 NPC는 ₩1,000까지만 걸 수 있습니다.

## 등급 / 명성 (`RewardService`)

* 게임별 전적(승/패/무, 연승, 최고 연승), 전체 Elo 레이팅(시작 1000), 랭크:
  **브론즈 → 실버(1100) → 골드(1250) → 플래티넘(1400) → 다이아(1550)** (5판 이상부터 표시)
* 이기면 행복 +1 (PvP는 인기 +1도), 랭크 업 알림, 결과 카드에 "오목 33승 18패 · 승률 64% · 🥇 골드 (+12)"
* 📊 버튼: 내 전적 카드 + 이 서버 명예의 전당 TOP
* DataStore `GwangalliMiniGames_v1` (키 `u_<UserId>`), Studio·미게시 place에서는 메모리 저장
* 플레이어 속성 `MiniRank`, `MiniRankIcon`, `MiniRating`, `MiniWins` 로 다른 UI에서도 랭크 표시 가능

## 치팅 방지 (`AntiCheat` + 각 게임 서버)

* 모든 요청: 토큰 버킷 속도 제한, payload 형태 검사, 테이블 거리 검사, 경기 참가자 검사
* 오목: 차례/빈칸/금수 서버 판정. 가위바위보: 상대 선택은 공개 전 절대 전송 안 함
* 순발력: 서버가 "지금!" 순간을 미리 알려주지 않음. "지금!" 전에 도착했거나, 핑상 "지금!"을 받기 전에
  보낸 입력은 부정 출발. 반응속도 = 서버 측정값 − 그 플레이어의 왕복 지연(측정, 상한 있음). 클라이언트
  측정값은 서버값보다 **느릴 때만** 채택 → 핑을 속여 빨라질 수 없음
* 타이밍·퀴즈: 클라이언트 경과 시간은 서버 추정치와의 차이가 지연 허용 범위 안일 때만 채택
* 끝말잇기: 사전 + 금칙어 + Roblox `TextService` 필터 (라이브 서버는 필터 실패 시 거부)

## 설치

### 1) 파일 넣기
Rojo 사용 시 `default.project.json` (기존 place 위에 sync, `$ignoreUnknownInstances`).
Rojo 없이: `python3 tools/build_rbxmx.py` → `build/` 의 모델 3개를 Studio에 드래그:

| 파일 | 넣을 곳 |
|---|---|
| `MiniGames_ReplicatedStorage.rbxmx` | `ReplicatedStorage` |
| `MiniGames_Server.rbxmx` | `ServerScriptService.GwangalliGameplay` (모듈들이 든 **Folder**) |
| `MiniGames_StarterPlayerScripts.rbxmx` | `StarterPlayer.StarterPlayerScripts` |

### 2) 기능 모듈 한 줄 등록 (필수)
`ServerScriptService.GwangalliGameplay` (Script)의 `FEATURE_MODULES` 목록에 `"MiniGames"` 를 추가합니다
(`patches/GwangalliGameplay.FEATURE_MODULES.patch` 참고):

```lua
local FEATURE_MODULES = { "MiniGames", "Bank", "Relationships", ... }
```
MiniGames는 이 코어가 넘겨주는 `ctx`(돈 장부·알림·능력치)를 쓰기 때문에 별도 Script가 아니라 기존
기능 모듈 규약(`init / onLoaded / onCharacter / onLeave`)으로 붙습니다. `onLeave` 가 프로필 저장 *전에*
호출되므로, 나가는 순간 정산된 돈도 프로필과 함께 저장됩니다.

### 3) (선택) 단어 사전 확장
* `WordChain/WordList.luau` 에 단어 추가, 또는
* DataStore `GwangalliWordList_v1` 키 `words` 에 공백으로 구분한 단어 문자열 저장 (서버 시작 시 병합), 또는
* `WordDictionary.registerProvider({ name, has = function(word) ... end })` 로 외부 사전 연결.
  국립국어원 표준국어대사전 Open API 등은 API 키를 숨긴 프록시 서버를 두고 `WordDictionary.HTTP_URL`
  을 설정하면 `httpProvider` 가 붙습니다 (HttpService 활성화 필요).

## 코드 구조

```
src/ReplicatedStorage/GwangalliMiniGamesShared/      공용 (서버+클라)
  init.luau          설정: 참가비, 게임 목록, 랭크/Elo, NPC 성격·대사, 스팟 좌표, 원격 계약
  OmokConfig.luau    오목 규칙 + 승리/금수 판정 (순수 함수)
  WordRules.luau     끝말잇기 규칙: 한글 음절, 두음법칙, 이어지기 판정
src/ServerScriptService/GwangalliGameplay/MiniGames/  서버 (GwangalliGameplay 기능 모듈)
  init.luau            원격 생성, 요청 라우팅·검증, 루프, BindToClose 환불
  MiniGameManager      스팟·좌석·경기 생명주기·나가기 규칙·재대결·관전
  MatchmakingService   신청 / 상대 찾기 / 수락 후 걸어오기
  BetService           판돈 보관·정산·환불 (유일한 돈 경로)
  RewardService        전적·레이팅·랭크·DataStore
  AntiCheat            속도 제한·payload·거리·지연 측정
  StationBuilder       산책로에 테이블/오락기 생성
  NpcHosts             스팟 NPC (GwangalliNPCLooks 리그 + GwangalliNPCClient 애니메이션 계약)
  Omok/OmokServer      (+ AI 초보/일반/고수)
  WordChain/WordChainServer, WordDictionary, WordList
  RockPaperScissors/RpsServer · ReactionGame/ReactionServer · MemoryGame/MemoryServer
  NumberGuess/NumberGuessServer · TimingGame/TimingServer · Quiz/QuizServer, QuizBank
src/StarterPlayer/StarterPlayerScripts/GwangalliMiniGames/  클라이언트 (LocalScript)
  init.client.luau   부트스트랩·이벤트 라우팅
  Hud                스팟 카드, 참가비/친구 선택, 신청 팝업, 전적
  Stage              VS 바, 타이머, 카운트다운, 결과 카드
  CameraDirector     테이블 카메라·이동 잠금
  Fx                 소리, 손 동작(이모트), 말풍선, 손 모양
  Omok/OmokClient, OmokBoards (주변 모든 오목판의 돌을 그림) · <Game>/<Game>Client
```

### 새 미니게임 추가하기
1. `MS.GAMES` 에 항목 추가, `MS.STATIONS` 에 스팟 추가 (원하면 `MS.NPCS` 에 NPC)
2. 서버 `MiniGames/<Game>/<Game>Server.luau`: `init(M)`, `new(match, api)`, `begin(gs, api)`,
   `input(gs, side, payload, api)`, `tick(gs, now, api)`, `view(gs, side)`, (선택)`cleanup` 구현.
   `api.finish(winner, reason)` 만 부르면 돈·전적·결과 화면은 매니저가 처리합니다.
3. 클라 `GwangalliMiniGames/<Game>/<Game>Client.luau`: `mount(ctx)` → `{ game, event, update, destroy }`
4. 서버 `init.luau` 의 `M.GAME_MODULES`, 클라 `init.client.luau` 의 `CLIENTS` 에 한 줄씩 등록

## 모바일
오목은 판을 손가락으로 탭(고스트 돌 → 다시 탭 또는 [착수]), 끝말잇기는 모바일 키보드, 가위바위보는
104px 버튼 3개, 순발력은 화면 중앙 210px 버튼, 기억력·숫자는 엄지 키패드. 게임 패널은 화면 아래 40%
이내로 두고 경기 중에는 `HideGwangalliHUD` 로 걷기 HUD를 치워서 테이블과 바다가 보이게 했습니다.

## 테스트
`tools/harness.js` 는 업로드된 스튜디오 HTML(헤드리스 Chromium)에 이 `src/` 트리를 그대로 주입하고
코어 스크립트의 `FEATURE_MODULES` 를 패치한 뒤 테스트 스크립트를 실행합니다.
`tools/test_bot.luau` 는 8개 게임을 각 NPC와 실제 요청 경로(`MiniGames.handle`)로 끝까지 플레이하며
참가비 차감·정산·전적·자리 해제·escrow 잔여 0을 확인합니다.

```
node tools/harness.js <repo> <초> tools/test_bot.luau   # studio.html 이 tools/ 옆에 있어야 함
```

## 임시 스튜디오(HTML) 버전
`dist/Gwangalli_Studio_1.0_v2.0_MiniGames.html` 은 업로드한 `광안리 임시 스튜디오 1.0 v2.0` 에 미니게임을
넣은 버전입니다. 열면 엔진이 뜬 뒤 몇 초 안에 미니게임 스크립트가 자동으로 들어가고
(`[MiniGames] ready: 12 stations, 11 NPC hosts, 8 games`), 산책로 테이블 근처로 가면 버튼이 뜹니다.
다시 만들기: `python3 tools/build_studio.py <원본 스튜디오.html> dist/<출력>.html`
(스튜디오는 1인 시뮬레이션이라 PvP는 NPC 대결·관전 위주로 확인할 수 있습니다.)
