# 광안리 애드온 인계 문서 (2026-10-23 기준)

다음 Claude는 먼저 `CLAUDE.md`(규칙)를 보고 이 문서를 끝까지 읽으세요.
자세한 근거 자료는 `devkit/` 아래에 있습니다.
- `devkit/status/`: 기능별 상태를 코드로 직접 확인한 보고서
- `devkit/reports/`: 지금까지 작업한 에이전트들의 최종 보고 원문
- `devkit/feat/<기능>/research.md`: 기능별 설계 문서

---

## 1. 이게 뭔가

- 사장님의 Roblox 오픈월드 인생게임 **"광안리"**(부산 광안리, place 이름 v7)에 넣는 추가 기능 묶음입니다.
- 사장님 기존 스크립트는 고치지 않습니다. 실행 중에 기존 시스템을 찾아 연결하는 **애드온** 방식입니다.
- 소스는 Rojo 구조로 `src/` 아래 기능별 폴더에 있습니다.
- 최종 전달은 `tools/bundle_plus.py`로 만든 **파일 2개**입니다.
  - `GwangalliPlus.server.luau`: ServerScriptService에 Script 1개로 넣음
  - `GwangalliPlus.client.luau`: StarterPlayerScripts에 LocalScript 1개로 넣음
- 사장님은 파일을 붙여넣기만 합니다.

| 폴더 (src/ 아래) | 기능 | 사장님 요청 |
|---|---|---|
| `StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior` | 모든 가게, 건물, 집 실내를 AAA급으로 꾸밈. 클라이언트 전용으로 플레이어 주변에만 파트를 만듦 | "모든 건물 집 등 aaa급 내부로, 물건 하나하나" |
| └ `HospitalPlus.luau`, `Hosp_*.luau` | 광안 메디컬 의원 시설: 자동문, 화장실, 엘리베이터 1F/2F/R, 비상구, 응급실 출입구, 옥상 | "병원 나갈 수 있는 문 등 다 구현" |
| `GwangalliClinic` (+Shared) | 진료 보기: 번호표, 접수, 호출 화면, 진찰, 처치, 수납, 약국, 건강검진. 게임의 기존 피로도→질병 시스템으로 움직임 | "진료도 볼 수 있어야" |
| `GwangalliKaraokePlus` (+Shared) | 팡팡노래방식 코인노래방: 리모컨, 예약, TV 가사, 점수. 오리지널·퍼블릭도메인 58곡 | "팡팡노래방처럼" |
| `GwangalliClubPlus` (+Shared) | CLUB OCEAN 쇼: 음료 주문이나 후원 시 가운데 전광판에 닉네임 애니메이션, 옆 전광판 랭킹, 레이저, DJ 모드, 합석 연출 | "실제 클럽처럼 화려하고 재밌게" |
| `GwangalliShopCrew` (+Shared) | 가게 NPC 직원 상호작용, 테이블 서빙 | "NPC 상호작용, 서빙" |
| `GwangalliDecorPlus` (+DecorShared) | 내 집 마련 자유 배치 인테리어 | "창의적으로 꾸미게" |
| `GwangalliCarDealer` (+Shared) | 차량 매장: NPC 대화 → 차종별 카탈로그 UI → 시승·구매 | "NPC한테 얘기하면 전체 차 종류별 UI" |
| `GwangalliPasses` (+Shared) | 게임패스 1·3·4번 (아래 6절) | "1번 3번 4번만 기능 구현" |

번들에 넣지 않는 것:
- `GwangalliCarInterior`: 차량 실내. 사장님이 직접 관리합니다.
- `GwangalliMiniGames`, `ServerScriptService/GwangalliGameplay/MiniGames`: 예전에 따로 전달한 해변 미니게임입니다.

## 2. 지금 상태 (정직하게)

**10/17에 주간 사용량 한도에 걸려서 진행 중이던 에이전트 작업이 한꺼번에 멈췄습니다.**
- 대부분 기능이 "만들기(build)"까지만 됐고, 테스트·리뷰·수정 단계는 한 번도 돌지 않았습니다.
- 만들다 끊긴 파일의 중간 편집은 자동 커밋으로 레포에 들어가 있습니다.
- 그 상태에서 중간판 2파일을 사장님께 이미 드렸습니다.

### 2-1. 건물 실내 (GwangalliBuildingInterior)
| 상태 | 파일 |
|---|---|
| 완성 + 리뷰 끝 | `T_cafe`, `T_pub`, `T_korean`, `T_grill`(고깃집·포차), `T_seafood`(횟집), `T_fastfood`, `T_store`, `T_service`, `T_style`(미용 등), `T_home` + `HomeWet`(집 5등급), `T_clinic`(병원 방), `T_garage`(정비소), `T_club` + `T_clubmain`(클럽 전 구역) |
| 완성, 리뷰 안 됨 | `T_pc`(PC방), `T_gs25`(GS25), `HospitalPlus`/`Hosp_*`(오프라인 22/22 통과, 리뷰 단계 미실행) |
| **만들다 끊김 (중간 상태)** | `T_bowling`(볼링장), `T_facility`(화장실·복도·홀) |
| 1차 버전만 있음 (업그레이드 작업 못 함) | `T_karaoke`, `T_arcade`(게임랜드), `T_delivery`, `T_billiards`, `T_gym` |
| 시작 못 함 | 런타임 건물 가구 리스킨(종합병원·디스트릭트·Annex). `Reskin` 모듈 없음. 훅만 `init.client.luau`에 있음 |

- **공용 모듈 수정 2차**(리뷰어 요청 15건)가 반쯤 적용된 채 끊겼습니다.
  - 관련 커밋: `fbd78e5`, `7916cfd`, `dc1f288`. Props, Scan, Common, T_pub, T_cafe를 고쳤습니다.
  - 검증과 회귀 시뮬은 안 했습니다. 요청 15건 목록은 `devkit/workflows/scripts/bi-shared-fixes-r2-*.js`에 있습니다.
- **클럽 실내 문구가 정책 위반 상태입니다.** 지금 반드시 고쳐야 합니다.
  - `T_club.luau`와 `T_clubmain.luau`에 실제 술 메뉴(소주, 카스·테라, 잭콕, 예거밤, 데킬라, 생맥주 등), "19+ · 2007년생부터 입장", "영업신고증 유흥주점영업"이 들어 있습니다.
  - 확인 방법: `grep -n '소주\|맥주\|카스\|테라\|잭콕\|예거\|데킬라\|위스키\|보드카\|칵테일\|하이볼\|19+\|년생\|유흥' src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/T_club*.luau`
  - 전부 무알콜 음료(에이드, 목테일, 무알콜 스파클링)로 바꿉니다. 이름과 가격은 실제 주문 메뉴(ClubPlus, place의 BottleService)와 맞춥니다.

### 2-2. 기능 애드온
| 기능 | 코드 | 확인된 것 | 안 된 것 |
|---|---|---|---|
| Passes | 37파일 완성 | 오프라인 테스트 156개 통과, 번들 포함 확인 | 리뷰·실게임 테스트 없음 (자세한 내용은 `devkit/status/passes.md`) |
| Karaoke | 30파일 완성 | 오프라인 테스트 통과, 임시 스튜디오에서 1곡 완주와 점수 화면 확인 | 리뷰, 실게임 음성·에코 테스트 없음. 실제 곡 지원 미착수 |
| Clinic | 대부분 완성 | 임시 스튜디오에서 번호표→문진표→진찰·혈압→진료 중→검진 결과→수납 화면 확인 | 마지막 build가 스튜디오 테스트 중 끊김. 리뷰 없음 |
| Hospital 시설 | 완성 | 오프라인 22/22 | 스튜디오 걷기 테스트 불가(엔진 한계), 리뷰 없음 |
| ClubPlus | 완성 | 번들 시동 OK | 테스트·리뷰 없음. 재미 업데이트 미착수 |
| ShopCrew | 대부분 | 시동 시 "took over GwangalliShopService", 141개 가게 연결 로그 | 마지막 build 끊김, 테스트·리뷰 없음 |
| DecorPlus | 완성 | 임시 스튜디오 편집기 화면 | 테스트·리뷰 없음. 카탈로그 썸네일이 검게 나오는 문제 |
| CarDealer | 대부분 | 시동 시 "hooked 박사장 as a dealer", "6 car previews ready" | 마지막 build 끊김(클라 UI 쪽), 테스트·리뷰 없음 |

`devkit/status/karaoke_clinic_hospital.md`에 노래방, 진료, 병원의 파일 구성, 설정값, 테스트 재실행 방법이 정리돼 있습니다.

### 2-3. 번들 (최종 2파일)
- `tools/bundle_plus.py`: Rojo 트리를 실행 중에 "자리표시 인스턴스"로 다시 세웁니다. 꺼 둔 Script/LocalScript와 빈 ModuleScript를 만들고 속성 `GwVMod`를 붙입니다.
  - 각 모듈의 `require`가 자리표시를 받으면 파일 안 함수를 부르므로, 원래 Rojo 구조와 똑같이 동작합니다.
  - 공용 모듈 자리표시는 서버가 ReplicatedStorage에 만들고, 클라이언트는 `ReplicatedStorage.GwangalliPlus` 표시 폴더를 기다렸다가 씁니다.
- 서버 파일 맨 위 `GW_CONFIG`:
  - `PassIds`: 패스 번호
  - `Features`: 기능 끄기. 클라이언트에도 적용
  - `ScriptAttributes`
- `tools/luau_strip.py`는 주석과 들여쓰기를 걷어 냅니다. `--verify`로 luau-ast 결과가 같은지 확인할 수 있습니다(254개 파일 0 불일치).
- 검증 이력:
  - 가짜 Roblox 환경 테스트: `devkit/bundle_test/mock.luau`
  - 임시 스튜디오 시동 테스트(`devkit/bundle_test/smoke*.js`): 서버 7개, 클라 8개 기능이 오류 없이 시작했습니다. 클라 실내 파트도 실제로 생성됐습니다(병원 로비 2732개, PC방 홀 894개).
- 크기: 서버 약 1.2MB, 클라 약 5.2MB. Studio에 붙여넣을 때 몇 초 멈출 수 있습니다. 실제 Studio에서 붙여넣기는 아직 확인하지 못했습니다.

## 3. 남은 일 (이 순서 권장)

1. **공용 수정 2차 마무리와 검증.**
   - 15건 중 무엇이 적용됐는지 `git show fbd78e5 7916cfd dc1f288`로 확인합니다.
   - 나머지를 마저 하고 전 매장 회귀 시뮬을 돌립니다(`simall.sh`, blocked=0 유지, 파트·프롬프트 수 비교).
2. **클럽 문구 전 연령화**(2-1 참고).
3. **볼링장·시설 실내 마무리**(`T_bowling`, `T_facility`), PC방·GS25 리뷰.
4. **기능별 테스트 → 리뷰(정확성·경험 2관점) → 수정**: Passes, Karaoke, Clinic, Hospital, ClubPlus, ShopCrew, DecorPlus, CarDealer. 스펙은 `devkit/workflows/args/lane_args_*.json`에 있습니다.
5. 노래방·게임랜드·딜리버리·당구·헬스 실내 업그레이드(스펙: `devkit/workflows/scripts/building-venues-b-*.js`).
6. **클럽 재미 업데이트**: HYPE→DROP, 댄스 배틀, 오늘의 미션, 인생네컷 포토부스, 리액션 휠, 단골·VIP 레벨, 신청곡.
7. **노래방 실제 곡 지원**: 운영자가 권리를 가진 SoundId와 타이밍 가사(lrc)를 넣는 CustomSongs, 가사 싱크 도구(/가사싱크).
   - 6과 7의 완성 스펙: `devkit/workflows/args/lane_args_round2.json`
   - 번들 쪽에서는 `GW_CONFIG.CustomSongs`를 서버에서 클라이언트로 전달하는 통로를 추가해야 합니다.
8. 브랜드명 정리: 우리가 만든 글자의 실제 상품·주류 브랜드를 가상 이름으로 바꿉니다. 예: `T_gs25` 창고 박스(참이슬·카스·신라면 등), `T_pub` 예거밤, `T_clinic` 비타500.
9. 통합 TODO:
   - CarDealer 프리미엄 등급을 `Passes.has(player,'garage')`로 잠그기
   - DecorPlus 침대를 기존 수면(Life.sleep)에 연결하거나 장식으로 두기
   - 진료 조언 "집에 가서 침대에서 푹 주무세요"
   - 데코 카탈로그 검은 썸네일
   - 테스트 하네스에서 출석체크 팝업 닫기
   - (선택) 리스킨
10. **최종**: 번들을 만들어 임시 스튜디오에서 확인합니다. 사장님께 2파일, 게임패스 인수인계 글(6절), 결과 이미지를 채팅으로 보냅니다.

## 4. 개발 환경 복원 (새 세션)

스크래치 경로가 도구 안에 하드코딩돼 있습니다. **같은 절대경로를 다시 만드는 게 가장 쉽습니다.**

```bash
S=/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad
mkdir -p $S && cp -r devkit/* $S/
# Luau CLI (luau, luau-compile, luau-analyze, luau-ast)
mkdir -p $S/luau && unzip -o devkit/bin/luau-linux.zip -d $S/luau && chmod +x $S/luau/*
# 임시 스튜디오(브라우저 Roblox 엔진) 풀기: 렌더러 js, place.bin, luau.wasm
python3 $S/tools/unpack.py dist/Gwangalli_Studio_v7_CarInterior.html $S/v7pack
mkdir -p $S/v7place && cp $S/v7pack/place/place.bin $S/v7place/place.bin
mkdir -p $S/v7zip/x && cp dist/Gwangalli_Studio_v7_CarInterior.html $S/v7zip/x/Gwangalli_Studio_v7-1.html
# 사장님 place 스크립트 덤프 (연동 조사용, 레포에는 커밋하지 말 것)
python3 $S/tools/dump_scripts.py $S/v7place/place.bin $S/bld/src
# playwright (Chromium은 /opt/pw-browsers 에 있음)
cd $S/harness && npm i playwright --no-save
```

- 위 절차는 이 세션의 구조를 그대로 옮긴 것입니다. **새 세션에서 처음부터 돌려 본 적은 없습니다.** 막히면 경로부터 확인하세요.
- 미리보기 픽스처(`bprev/fx/`, 135MB)는 레포에 없습니다. `bprev/export_rooms.py`(방 목록: `tools/venues/rooms.json`)와 `bprev/export.py`로 place.bin에서 다시 뽑습니다.
- 임시 스튜디오 HTML: `dist/Gwangalli_Studio_v7_CarInterior.html`은 v7 place에 차량 실내가 들어간 판입니다. 건물·기능 테스트에 그대로 써도 됩니다. 사장님 place가 v7 이후로 바뀌었으면 최신 HTML이나 place를 받아 오세요.

**자주 쓰는 명령**
- 문법 검사: `$S/luau/luau-compile --binary file.luau >/dev/null`
- 실내 시뮬
  - 전체: `cd $S/bprev && ./simall.sh`
  - 특정 매장: `./simall.sh cafe_mega pub_sunset`
  - 결과 줄 `#V`/`#K`의 parts, blocked, prompts를 봅니다. **blocked는 0이어야 합니다.**
- 실내 미리보기 이미지: `cd $S/bprev && ./run.sh <fixture키> [--night] [--q ultra] [--lcams cams/x.json]` → `bprev/shots/<키>.jpg`. 클럽은 `--q ultra`를 씁니다.
- 임시 스튜디오 테스트
  - 기능별 드라이버: `devkit/feat/<기능>/studio/*.js`
  - 번들 시동 테스트: `devkit/bundle_test/smoke2.js`
  - **항상** `flock $S/.studio.lock timeout 1500 node ...`로, 한 번에 하나씩 돌립니다. 부팅 2분, 메모리 2GB 한계가 있어 OOM이 나면 다시 돌립니다.
- 번들
  - 만들기: `python3 tools/bundle_plus.py <출력폴더>`
  - 구조 검증: `python3 tools/luau_strip.py --verify $S/luau/luau-ast $(find src -name '*.luau')`
  - 금지어 검사: `grep -rn '장애인\|♿' src`

## 5. 일하는 방식 팁

- 큰 작업은 Workflow로 나눠 돌렸습니다. 대표적인 흐름은 `gw-feature-lane.js`(만들기 → 테스트 → 리뷰 2관점 → 수정)입니다. 스크립트는 `devkit/workflows/scripts/`, 인자는 `devkit/workflows/args/`에 있습니다.
  - 이전 세션의 `resumeFromRunId`는 새 세션에서는 쓸 수 없습니다. 새로 실행하세요.
  - 프롬프트 안의 경로(`S=...`)는 4절 경로를 그대로 쓰면 맞습니다.
- **동시 에이전트는 8개 이하로 유지하세요.** 세션·주간 사용량 한도에 세 번 걸렸습니다.
- 실내 타입 모듈(T_*)은 공용 모듈(Kit/Scan/Props/Common)을 고치지 않습니다. 필요하면 "sharedRequests"로 보고받아 한 번에 반영합니다.
- 맵은 읽기 전용입니다. 맵 파트는 로컬로 숨기고(`Scan.hide`) 우리 파트로 다시 만듭니다. 문, 통로, 좌석, 테이블 윗면, 직원 자리, 프롬프트는 비워 둡니다(keep zone).
- 사장님은 진행 이미지를 자주 원합니다. `bprev/shots/*.jpg` 시트나 스튜디오 스크린샷을 보내되, 오류 화면이나 빈 화면은 빼세요.

## 6. 게임패스 인수인계 (패스 ID 넣는 작업자용)

전체 근거는 `devkit/status/passes.md`에 있습니다(파일과 줄 번호 포함). 요약:

- **어떤 패스인가**
  - 1번 **프리미엄 차고**(`PremiumGarage`)
    - 패스 전용 프리미엄 차 4대
    - 어디서든 내 차 호출(원격 차고)
    - 출장 정비
    - **패스가 없으면 차 호출은 정비소에서만** 됩니다. 정비소 키오스크 "차량 호출"이 있고, 폰의 차량 기능은 🔒로 보입니다.
  - 3번 **편의 패스**(`Convenience`): 유치장과 기절(병원 이송) 대기 50% 단축, 폰 블랙마켓 앱(총기상 물건을 원격 주문, 같은 가격)
  - 4번 **과시 패스**(`Flex`): KO 피니시 이펙트 6종과 승리 포즈, 나만의 번호판(텍스트 필터 적용), 네온 닉네임(머리 위와 채팅)
- **ID 넣는 곳**
  - 최종 2파일: 서버 파일 맨 위 `GW_CONFIG.PassIds`
  - 소스: `src/ReplicatedStorage/GwangalliPassesShared/Config.luau`의 `Config.PASSES.*.Id`
  - 번들 모드에서는 Config.luau의 Id가 무시되고 GW_CONFIG 값이 쓰입니다. 번들을 다시 만들면 0으로 돌아가므로, ID가 정해지면 `tools/bundle_plus.py`의 GW_CONFIG 템플릿에도 넣으세요.
- **ID = 0의 뜻**: 판매 준비 중입니다.
  - 라이브: 상점, 버튼, 폰 아이콘이 숨겨지고 잠금도 걸리지 않습니다.
  - Studio: 테스트용으로 보입니다.
- ⚠️ **PremiumGarage ID를 넣는 순간 모든 비구매자가 정비소에서만 차를 부를 수 있게 됩니다.**
  - 지금 place는 어디서든 호출이 가능합니다.
  - 이걸 원하지 않으면 `Config.GARAGE.REMOTE_LOCK = false`로 바꾸고 다시 번들합니다.
- **서버 판정**
  - 소유 여부는 `Ownership.owns`(서버)로만 판단합니다.
  - 차 호출 제한은 place의 `Spawn.callOwned`를 감싸서 겁니다. 시승과 프리미엄 차는 예외입니다.
  - 구매 직후 `PromptGamePassPurchaseFinished`로 바로 열리고, 서버가 다시 확인합니다.
- **Studio 테스트** (workspace 속성, 실행 중 변경 가능)
  - `GwPassesStudioTest = true`: 전부 소유
  - `GwPassesStudioTest = "garage,flex"`: 일부만 소유
  - `GwPassesAdminFree = true`: 관리자 무료. 라이브에서도 되지만 ID가 0보다 클 때만
- **확인 순서**
  1. Studio에서 속성 없이 실행해 잠금(🔒)을 확인합니다.
  2. `GwPassesStudioTest = true`로 바꿔 각 기능이 열리는지 봅니다.
  3. 라이브 비공개 서버에서 실제 구매 흐름을 확인합니다.
- **문제 해결**
  - 상점이 안 보임: ID가 0인지 확인합니다.
  - 구매 후에도 잠김: 출력창 `[GwangalliPasses]` 로그를 보고, 패스가 같은 게임(universe) 것인지 확인합니다.
  - 폰 VIP 아이콘 위치: `patches/GwangalliPasses_Phone.patch`는 선택입니다. 없으면 애드온이 실행 중에 붙입니다.

## 7. 맵(원본 place) 쪽 발견 사항
`devkit/notes/map_issues.md` 참고:
- GS25 냉장고 앞 Neon 판 때문에 음료가 하얗게 보임
- GS25 창고 뒷문이 랙에 막힘
- PC방 배달 동선 AislePos가 뒤집혀 있음
- 클럽 여자화장실 간판이 공중에 떠 있음

실내 스크립트가 로컬로 가려 둔 것도 있지만, 맵에서 고치면 깔끔합니다.

## 8. 주의
- **레포가 공개(public)입니다.** `dist/`의 스튜디오 HTML에 사장님 place 전체가 들어 있습니다. 사장님께 비공개 전환을 권했습니다. place 덤프와 place 파일은 새로 커밋하지 않습니다.
- 클라이언트 실내는 로컬 파트만 만들고 맵은 로컬로만 숨깁니다. 서버 게임플레이 파트(프롬프트, 좌석, NPC 동선)는 건드리지 않습니다.
