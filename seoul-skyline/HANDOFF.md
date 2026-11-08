# 인계 문서 — 서울 한강 야경 · 잠실 (Seoul Skyline) Roblox 맵

작성 시점: 2026-11-08 · 브랜치 `ccr-3a6246e5-93vjxm` · 상태: **중간본(실내 작업 진행 중)**

## 1. 한 줄 요약
해 질 녘 한강 너머 잠실 스카이라인(롯데월드타워 모티브 555 m)을 **실제 스케일(1 stud = 0.3 m)** 로 재현한 Roblox 맵.
모든 지오메트리는 Luau 빌더(`ServerStorage.SeoulSkyline`)가 결정적으로 생성. 외관 완성, 실내(로비·전망대·몰·편의점·
화장실·자전거 대여소·한강뷰 아파트 세대) 추가 중. 마지막 전체 빌드: **파트 33,528 · 광원 162 · 항공등 246 · Luau 오류 0**.

## 2. 산출물
| 파일 | 용도 |
|---|---|
| `build/SeoulSkyline.rbxlx` | 완성 place: Studio 로 열고 Play → 맵 자동 생성. 또는 커맨드 바 `require(game.ServerStorage.SeoulSkyline).Build()` 후 저장(굽기) |
| `build/SeoulSkyline_*.rbxmx` | 기존 place 에 드래그(ServerStorage / ServerScriptService / StarterPlayerScripts). Lighting.Technology = Future 수동 설정 |
| `dist/SeoulSkyline_Studio.html` | 브라우저 플레이(광안리 임시 스튜디오 엔진, 빈 place + 맵 주입) |
| `preview_hero.png`, `preview_deck.png` | 대표 구도 / 전망대 시점 렌더 |
| `default.project.json` | Rojo |

## 3. 구조 (`src/`)
```
ServerStorage/SeoulSkyline/        빌더 (ModuleScript 트리)
  init.luau        Build()/Clear()/SetNight()/ApplyLighting(), 모듈 순서(MODULES)
  Config.luau      좌표계·레벨·구역·팔레트·실측(Config.m, Config.Real)·품질·조명·클라이언트 옵션  ← 레이아웃의 단일 진실
  Kit.luau         파트 팩토리, 발자국 예약(reserve/isFree), 광원 예산, 야간 발광 태그, 항공등, 라벨, 수면 반사, 지형/차선 기록
  Facade.luau      건물 파사드 생성기(curtain/round/apartment/mid/far) — Neon 코어+층 슬래브+관통 멀리언+꺼진 창 패치
  Atmosphere       노을 조명/대기/하늘/구름/후처리/수면 색
  TerrainPlan      한강 수면·강바닥·호안·둔치·제방(지형)
  Landmark         롯데월드타워 모티브(555 m, 105층, 크라운, 첨탑, 서울스카이 유리 띠) + 몰 + 광장
  LandmarkInterior 타워 1층 로비 + 서울스카이 전망대 실내 + 몰 아트리움           (진행 중)
  Skyline          좌/중/우 고층 클러스터 60동 (40~64층)
  Bridge           잠실대교 모티브: 17 m 상판, 8차로, 조명 교각, 가로등, 차선
  Riverside        도시 지면, 올림픽대로/강변북로(8차로), 계단 호안, 산책로·자전거길, 가로수, 대로 3개
  Park             한강공원(나무 666), 60 m 전망대(스폰·포토 스팟·나선 계단·엘리베이터), 편의점·화장실·자전거 대여소 실내
  ShowHome         한강뷰 아파트 1동: 1층 로비 + 20층 84 m² 세대(거실·주방·안방·욕실·발코니)      (진행 중)
  Apartments       아파트 단지 369동(15~35층, 신축 49층)
  CityCarpet       지평선 LOD 도시 + 원경 산 능선
  WaterFx          유람선 3척 + 수면 반짝임
ServerScriptService/SeoulSkylineBoot.server.luau   맵 없으면 생성/있으면 조명 적용, 엘리베이터(태그 SeoulElevator), 낮밤 주기
StarterPlayer/StarterPlayerScripts/SeoulSkylineClient/
  init.client      맵 루트 감시·재시작        Traffic   차량 불빛 흐름(≤400 파트)
  Beacons          항공등 깜빡임              Boats     유람선 운항
  CameraFx         접속 시네마틱 + 포토 스팟   ElevatorFx 엘리베이터 페이드
  Util             공용 상수
```
빌드 순서 = 발자국 예약 우선순위: Atmosphere → TerrainPlan → Landmark → LandmarkInterior → Skyline → Bridge → Riverside →
Park → ShowHome → Apartments → CityCarpet → WaterFx.

## 4. 규약 (새 작업 시 반드시)
- **스케일**: 1 stud = 0.3 m. 크기는 `Config.m(미터)` / `Config.Real`. 레벨: 수면 0, 둔치 5, 도시/제방 24.
- **좌표**: 강은 X 축, 수면 Z −700~700. 먼 쪽(타워) −Z, 가까운 쪽(공원·스폰) +Z. 대표 구도 카메라 (240,342,1433)→−Z.
- **파트**: 항상 `Kit.*` 사용(Anchored·CastShadow·CanTouch·카운트·주기적 yield 처리). 장식은 collide=false, query=false.
- **z-fighting 금지**: 보이는 면끼리 외부 ≥0.3 stud, 실내 트림 ≥0.05 stud 띄움.
- **야간 발광**: Neon + `glow=true`(SetNight 낮/밤 전환). 광원은 `Kit.light`(전역 상한 240).
- **발자국**: 도시 위 배치는 `Kit.isFreeRect` 확인 후 `Kit.reserveRect`.
- **실내**: `Kit.group(parent, name, Config.InteriorStreaming)`(Atomic 스트리밍). 엘리베이터 = 태그 `SeoulElevator` +
  ProximityPrompt + Vector3 `ElevatorTarget` (서버가 이동, 클라이언트 ElevatorFx 가 페이드).
- **결정적**: 난수는 ctx.rng 만. 수면 반사는 `Config.Viewpoint.ReflectionEye` 쪽으로 정렬(`Kit.reflection`).

## 5. 도구
```
python3 seoul-skyline/tools/make_preview_studio.py     # tools/studio_empty.html (빈 place 엔진; gitignore)
node seoul-skyline/tools/preview.js --shots hero,deck [--only A,B] [--cam n=x,y,z:lx,ly,lz:fov] [--client] \
     [--pick "x,y"] [--eval '<luau>'] [--w 960 --h 540] [--out dir] [--prefix p_]
python3 seoul-skyline/tools/build.py                   # build/*.rbxlx, *.rbxmx
python3 seoul-skyline/tools/make_studio.py             # dist/SeoulSkyline_Studio.html
node seoul-skyline/tools/test_studio.js <html> <png>   # HTML 스모크 테스트 (SEOUL_READY 대기)
```
미리보기는 WebGL Roblox 에뮬레이터(근사). preview.js 는 Roblox 처럼 원거리까지 그리도록 도달거리를 넓히고
라이트 헤일로 스프라이트를 끔. 지형은 기록된 ops 로 그림(에뮬레이터 한계).

## 6. 진행 상황
완료: 핵심 프레임워크, 실측 스케일 전환, 외관 전 모듈, 클라이언트 효과, 엘리베이터(작동), 코드 검수(크래시 0, 기능 버그 2건 수정),
공원 실내(편의점·한강라면 코너·음료 냉장고·계산대·테라스, 공중화장실, 공공자전거 대여소, 전망대 안내판).
진행 중:
- `LandmarkInterior` + `Landmark`: 1층 로비(유리문·대리석·안내데스크·게이트·미디어월·엘리베이터), 서울스카이 전망대 실내
  (통유리·스카이데크 유리바닥·카페·기념품점·망원경), 몰 아트리움(매장·에스컬레이터·중층 발코니). 현재 1,803 파트 빌드됨.
- `ShowHome`: 로비·엘리베이터·20층 세대 완성 단계(1,359 파트), 마감 다듬기.

## 7. 남은 할 일 (우선순위)
1. 위 두 실내 마무리 → 전체 빌드 → 실내 눈높이 렌더 검수 → `build.py`/`make_studio.py` 재생성.
2. 편의점 자동문 실제 슬라이드(태그 `SeoulAutoDoor`, `ClosedOffset` 속성 이미 있음) — Boot 에 근접 감지 트윈 추가.
3. 미리보기에서 SurfaceGui 라벨이 비어 보이는 문제(에뮬레이터 한정): preview.js 에서 빌드 후 SurfaceGui.Enabled 토글.
4. 다리 끝 스텁을 8차로 실폭(RoadFrom±109.3)에 맞추기(Riverside 요청).
5. Roblox Studio 실기 확인: Future 조명 색감, Atmosphere 밀도, 원거리 LOD, StreamingEnabled 동작, 성능(모바일은
   `Config.Quality.Density = 0.7` 권장).

## 8. 알려진 한계
- 해가 화면 왼쪽으로 지도록 GeographicLatitude 8(실제 37.5). 강폭은 420 m 로 압축(실제 ≈1 km).
- `Terrain.Decoration`, `Lighting.Technology` 는 스크립트 설정 불가 → pcall, Studio 에서 수동 설정 권장.
- 수면 반사는 대표 구도/전망대 사이 한 점을 향해 정렬 → 측면 시점에선 납작한 띠로 보임.
- 실내 상품은 단색 박스/원기둥(인쇄 그래픽 없음).
