# 서울 한강 야경 · 잠실 (Seoul Skyline) — Roblox 맵

해 질 녘 한강 너머로 보이는 잠실 스카이라인(롯데월드타워 모티브 초고층, 긴 조명 다리, 양쪽 고층 클러스터,
아파트 단지, 안개 낀 산 능선, 나무가 빽빽한 강변공원)을 **Roblox 맵으로 재현**한 프로젝트입니다.
모든 지오메트리는 Luau 빌더가 결정적으로(같은 시드 → 같은 맵) 생성하므로 숫자 몇 개로 레이아웃·밀도·색감을
바꿀 수 있습니다.

> 미리보기 이미지: `shots/` (헤드리스 렌더러로 찍은 스크린샷 — 실제 Roblox Future 조명과 색감은 조금 다를 수 있음)

## 바로 쓰기

### A. 완성 place 파일 (가장 쉬움)
1. `build/SeoulSkyline.rbxlx` 를 Roblox Studio 로 엽니다 (Lighting.Technology = Future 가 미리 설정됨).
2. **Play** → `SeoulSkylineBoot` 가 맵을 생성합니다(수 초). 전망대에서 스폰.
3. (권장) 편집 모드에 맵을 **구워서 저장**: 보기 → 명령 모음(Command Bar)에서
   ```lua
   require(game.ServerStorage.SeoulSkyline).Build()
   ```
   실행 후 `Ctrl+S`. 이후 실행 때는 맵이 이미 있으므로 조명만 다시 적용됩니다(로딩 0초).

### B. 기존 place 에 넣기 (.rbxmx 드래그)
| 파일 | 넣을 곳 |
|---|---|
| `build/SeoulSkyline_ServerStorage.rbxmx` | `ServerStorage` (빌더 모듈) |
| `build/SeoulSkyline_ServerScriptService.rbxmx` | `ServerScriptService` (부트 스크립트) |
| `build/SeoulSkyline_StarterPlayerScripts.rbxmx` | `StarterPlayer.StarterPlayerScripts` (차량 불빛·항공등·유람선·카메라) |

그리고 **Lighting.Technology 를 Future** 로 바꿔 주세요(스크립트로는 바꿀 수 없는 속성).
Terrain 의 `Decoration`(잔디 블레이드)도 켜 두면 좋습니다.

### C. Rojo
`seoul-skyline/default.project.json` (`rojo serve seoul-skyline/default.project.json`).

### D. 브라우저에서 바로 보기
`dist/SeoulSkyline_Studio.html` — 광안리 임시 스튜디오 엔진(빈 place)에 이 맵을 넣은 버전. 열면 엔진이 뜬 뒤
맵이 생성되고 전망대에서 시작합니다. (Roblox 시뮬레이션이라 실제와 다를 수 있음)

## 맵 구성

| 모듈 | 내용 |
|---|---|
| `Atmosphere` | 해질녘 조명: Future, Atmosphere(노을 글레어·헤이즈), Sky, Clouds, Bloom, 색보정, SunRays, 수면 색 |
| `TerrainPlan` | 한강 수면(지형 Water) + 강바닥 + 돌 호안 + 양쪽 잔디 둔치 + 제방 사면 |
| `Landmark` | 롯데월드타워 모티브 초고층(곡선 테이퍼, 세로 이음선, 랜턴 크라운, 첨탑) + 저층 몰(파란 곡면 지붕) + 광장 |
| `Skyline` | 좌/중/우 고층 클러스터 (커튼월·원형·셋백, LED/첨탑/헬기장 크라운) |
| `Bridge` | 잠실대교 모티브 다경간 교량, 조명 교각, 가로등, 차선(차량 불빛 흐름) |
| `Riverside` | 양쪽 강변: 도시 지면, 올림픽대로/강변북로, 계단식 호안, 산책로·자전거길, 가로등, 대로 |
| `Park` | 플레이어 쪽 한강공원: 숲, 산책로, 편의점, 주차장, **전망대(스폰) + 📷 포토 스팟** |
| `Apartments` | 아파트 단지(판상형 + 동 번호 + 슈퍼그래픽, 고층 단지) |
| `CityCarpet` | 지평선까지 이어지는 LOD 도시 + 원경 산 능선 |
| `WaterFx` | 유람선, 수면 빛 반사 |
| `Facade` (공용) | 건물 파사드 생성기: Neon 조명 코어 + 층 슬래브 + 관통 멀리언 + 꺼진 창 패치 (z-fighting 없는 창 격자) |
| `Kit` (공용) | 파트 팩토리, 발자국 예약, 광원 예산, 야간 발광 태그, 지형/차선 기록 |

클라이언트(`SeoulSkylineClient`): 다리·강변도로 차량 불빛 흐름, 항공장애등 깜빡임, 유람선 운항,
접속 시네마틱(아무 키나 누르면 스킵), 전망대 **포토 스팟**(ProximityPrompt → 사진과 같은 구도 + 피사계 심도).

## 설정 (`ServerStorage.SeoulSkyline.Config`)

* `Quality.Density` — 아파트·도시 밀도(모바일 0.7 권장), `Quality.MaxLights` — 실제 광원 상한
* `Lighting.ClockTime` / `DayNightCycle` — 시간 고정(기본 17.95, 노을) 또는 하루 흐름(창문·가로등 자동 점등/소등)
* `Client.IntroCinematic / Traffic / TrafficDensity / Beacons / Boats`
* `Landmark`, `Bridge`, `Viewpoint`, `Zones` — 레이아웃. `SEED` 를 바꾸면 도시 배치가 달라집니다.

## 성능 메모
* 모든 장식 파트: Anchored, CanTouch 끔, 작은 파트/네온은 그림자 끔, 장식은 충돌·쿼리 끔.
* 건물 모델은 `ModelStreamingMode = Persistent` → StreamingEnabled 여도 원경 스카이라인이 사라지지 않습니다.
* 창문 불빛은 전부 Neon 발광(광원 아님). 실제 광원은 전망대·다리·광장 근처에만 예산 내 배치.
* 빌드 중 주기적으로 `task.wait()` 하므로 서버/커맨드 바가 멈추지 않습니다.

## 개발 도구
```
python3 seoul-skyline/tools/make_preview_studio.py   # 빈 place 스튜디오 엔진(tools/studio_empty.html) 생성
node seoul-skyline/tools/preview.js --shots hero,wide,landmark,bridge,park   # 헤드리스 렌더 → seoul-skyline/shots/
python3 seoul-skyline/tools/build.py                  # build/*.rbxlx, *.rbxmx
python3 seoul-skyline/tools/make_studio.py            # dist/SeoulSkyline_Studio.html
```
`preview.js` 옵션: `--only Atmosphere,TerrainPlan,Landmark` (일부 모듈만), `--cam 이름=x,y,z:lx,ly,lz:fov`,
`--client` (클라이언트 효과 포함), `--w/--h`, `--out`, `--prefix`.

## 스케일 / 좌표계
**실제 스케일: 1 stud = 0.3 m** (Roblox 아바타 키 ≈ 5.5 stud ≈ 1.7 m 기준). 건물 높이·층고·차로·가로등·난간은 실측값:
롯데월드타워 모티브 555 m = 1,850 stud, 오피스 층고 4.0 m, 아파트 층고 2.9 m(15~35층, 신축 49층),
차로 3.5 m, 도로 가로등 10 m, 난간 1.1 m, 나무 8~15 m. (`Config.m(미터)`, `Config.Real`)
강폭만 실제(≈1 km)보다 좁은 420 m(1,400 stud)로 압축 — 사진의 망원 구도와 걸어서 건너는 플레이를 위해.

수면 Y=0, 강은 X 축 방향(Z −700 ~ 700). 먼 쪽(잠실·타워) = −Z, 가까운 쪽(공원·전망대) = +Z.
대표 구도 카메라 (240, 342, 1433) → −Z 방향: 화면 오른쪽 = +X, 해는 화면 왼쪽(−X)으로 집니다.
