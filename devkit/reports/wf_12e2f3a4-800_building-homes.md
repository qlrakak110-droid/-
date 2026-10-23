# building-homes (wf_12e2f3a4-800)

- status: completed
- failed agents (never finished, usually the usage limit): none

## build:T_home

```json
{
 "summaryKo": "고시원 1인실은 붙박이 책상(공부 화면 모니터 · 선풍기 · 스탠드 · 컵라면 선반), 수납 침대, 행거 옷, 미니 냉장고 · 전자레인지, 건조대, 소화기에 더해 문 옆에 '입실 안내'(22시 이후 소음 주의 · 공용주방 · 와이파이 · 분리수거) A4 안내문을 테이프로 붙였습니다. 원룸은 창가가 가구로 꽉 차서 천장형 빨래 건조대(수건 · 티셔츠 · 양말걸이)를 창 앞에 달았고, 책장은 칸마다 책 · 액자 · 장식이 꽉 차게 바뀌었습니다. 오피스텔 복층 거실에는 바다 쪽 창가에 캣타워와 맨 위에서 자는 고양이, 밥그릇 · 물그릇을 놓았고, 높은 천장에는 원목 날개 실링팬(벽 스위치로 천천히 돌기 시작)을 달았습니다. 복층 침실에는 침대 머리맡 액자 선반과 독서등, 무드등이 있는 낮은 책장, 난간 쪽 빈백 + 사이드 테이블(머그 · 책), 요가 매트 · 덤벨 · 폼롤러, 끝 벽 빨래 건조대 · 3단 트롤리를 넣었습니다. 아파트 안방에는 침대 밑 러그, 광안대교 노을 캔버스 사진, TV 아래 6단 서랍장(액자 · 보석 트레이 · 디퓨저 · 화분)을 두었고, 드레스룸은 욕실 문 앞 옷봉 · 서랍을 비우고 서랍 앞판을 통로 쪽으로 바로잡았으며 서랍장 위에 시계 보관함 · 보석함 · 향수 · 스카프, 뒤에서 빛나는 전신 거울을 놓았습니다. 펜트하우스 거실 벽난로는 이어진 불빛 띠 위에 끝이 뾰족한 불꽃이 겹쳐 실제 리니어 벽난로처럼 보이고, 다이닝 홈바는 상자 70개를 와인 · 위스키 · 진 · 코냑 병으로 바꾸고 결이 있는 백라이트 오닉스 벽과 허리케인 캔들을 더했습니다. 펜트하우스 서재에는 문 사이 크레덴자(지구본 · 디캔터 · 시가 상자 · 상패)와 세계지도, 위스키 진열장(내부 LED), 슬레이트 피처월 대형 작품 + 황동 리빌, 라운지 체어 옆 대리석 사이드 테이블 + 독서 램프, 꽉 찬 서가를 두었고, 마스터 침실에는 침대 위 대형 추상화 + 픽처 라이트와 침대 밑 간접등을 넣었습니다. 소파 팔걸이에 지름 3 스터드짜리 원판이 붙어 나오던 버그(파이핑 인자가 뒤바뀜)를 고쳐서 모든 등급의 소파가 깔끔해졌습니다.",
 "interactions": [
  "goshiwon/main: 롤 블라인드 올리기·내리기, 책상 밑 멀티탭(모니터·선풍기 전원), 벽걸이 에어컨(날개 + LED)",
  "oneroom/main: 커튼 열기·닫기, 플로어 스탠드, 에어컨",
  "officetel/living: 전동 커튼, 로봇청소기 '청소 시작'(한 바퀴 돌고 도크로 돌아감), 실링팬 켜기·끄기(천천히 빨라지고 느려짐), 고양이 장난감 흔들기(꼬리 흔듦; 머리가 서버 창문 프롬프트와 가까우면 공으로 대신함)",
  "officetel/loft: 머리맡 독서등, 책장 위 무드등, 에어컨",
  "apartment/living: 전동 커튼, 아크 스탠드, 공기청정기 모드 바꾸기",
  "apartment/bedroom: 전동 커튼(암막), 에어컨, 화장대 거울 LED",
  "apartment/dress: 선반 LED 조명(문 옆 벽 스위치 + SurfaceLight 1개), 백라이트 전신 거울. 서랍 열기(서랍이 앞으로 미끄러져 나오며 개킨 티셔츠가 보임)도 있지만, 서버 옷장 프롬프트 박스(4x5x8)가 이 방을 다 덮어서 이 배치에서는 안 생김",
  "apartment/study: 독서 스탠드, 롤 블라인드, 에어컨",
  "penthouse/living: 전동 커튼, 아크 스탠드, 벽난로 불 켜기·끄기(불꽃 깜빡임 + 불빛)",
  "penthouse/dining: 전동 커튼, 백바 허리케인 촛불 켜기(깜빡이는 불꽃 + PointLight), 바 조명(오닉스 백라이트 + 선반 LED + SurfaceLight)",
  "penthouse/study: 지구본 돌리기, 위스키 진열장 조명, 라운지 독서 플로어 램프",
  "penthouse/bedroom: 전동 커튼, 공기청정기 모드, 침대 밑 간접등(벽 스위치)"
 ],
 "fixtures": [
  {
   "key": "home_goshiwon_main",
   "parts": 628,
   "ok": true,
   "hidden": 109,
   "lights": 0,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_goshiwon_bath",
   "parts": 206,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_goshiwon_entry",
   "parts": 170,
   "ok": true,
   "hidden": 11,
   "lights": 0,
   "prompts": 1,
   "blocked": 0
  },
  {
   "key": "home_oneroom_main",
   "parts": 769,
   "ok": true,
   "hidden": 112,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_oneroom_kitchen",
   "parts": 297,
   "ok": true,
   "hidden": 35,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_oneroom_bath",
   "parts": 384,
   "ok": true,
   "hidden": 19,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_oneroom_entry",
   "parts": 238,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 1,
   "blocked": 0
  },
  {
   "key": "home_officetel_living",
   "parts": 793,
   "ok": true,
   "hidden": 103,
   "lights": 1,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_officetel_kitchen",
   "parts": 438,
   "ok": true,
   "hidden": 55,
   "lights": 1,
   "prompts": 5,
   "blocked": 0
  },
  {
   "key": "home_officetel_bath",
   "parts": 364,
   "ok": true,
   "hidden": 19,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_officetel_entry",
   "parts": 244,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 1,
   "blocked": 0
  },
  {
   "key": "home_officetel_loft",
   "parts": 379,
   "ok": true,
   "hidden": 33,
   "lights": 2,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_apartment_living",
   "parts": 549,
   "ok": true,
   "hidden": 68,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_apartment_kitchen",
   "parts": 941,
   "ok": true,
   "hidden": 99,
   "lights": 1,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_apartment_bedroom",
   "parts": 566,
   "ok": true,
   "hidden": 47,
   "lights": 0,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_apartment_dress",
   "parts": 466,
   "ok": true,
   "hidden": 22,
   "lights": 1,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_apartment_study",
   "parts": 529,
   "ok": true,
   "hidden": 70,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_apartment_bath",
   "parts": 1029,
   "ok": true,
   "hidden": 43,
   "lights": 2,
   "prompts": 6,
   "blocked": 0
  },
  {
   "key": "home_apartment_entry",
   "parts": 412,
   "ok": true,
   "hidden": 20,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_penthouse_living",
   "parts": 651,
   "ok": true,
   "hidden": 77,
   "lights": 2,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_dining",
   "parts": 789,
   "ok": true,
   "hidden": 132,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_kitchen",
   "parts": 470,
   "ok": true,
   "hidden": 36,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_study",
   "parts": 731,
   "ok": true,
   "hidden": 54,
   "lights": 2,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_bedroom",
   "parts": 824,
   "ok": true,
   "hidden": 68,
   "lights": 0,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_bath",
   "parts": 387,
   "ok": true,
   "hidden": 21,
   "lights": 1,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_penthouse_entry",
   "parts": 602,
   "ok": true,
   "hidden": 31,
   "lights": 1,
   "prompts": 2,
   "blocked": 0
  }
 ],
 "sheets": [
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_goshiwon_main__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_oneroom_main__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_officetel_living__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_officetel_living__n2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_officetel_loft__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_living__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_living__n1.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_bedroom__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_bedroom__n1.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_dress__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_study__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_living__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_living__n5.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_dining__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_study__r3.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_bedroom__r3.jpg"
 ],
 "sharedRequests": [
  "Homes.luau Homes.post (around line 125): every FurnitureSlot keep is built from the current room's floor (y=0.05) up to the slot's top, whatever floor the slot is on. So a mezzanine bed (penthouse bedroom over the study, officetel loft over the kitchen) leaves a 0..12.8 column in the room below, and kitchen slots below the loft leave thin floor keeps in the loft. Patch: before V:addKeep, `local base = d:FindFirstChild('SlotBase') or d.PrimaryPart; local by = if base and base:IsA('BasePart') then V.cf:PointToObjectSpace(base.Position).Y else mn.Y; if by > V.H - 1 or by < -1 then continue end`. T_home currently works around this inside its own build with C:fixKeeps.",
  "Homes.post: a slot footprint (the Footprint attr is larger than the piece) can cross a wall into the next room, e.g. the hall art and kitchen slots poke 1-2.3 studs into the apartment bedroom, and the living TV slot pokes into the penthouse study. Suggested fix: clip each slot keep at the shell wall between the slot base and the room. T_home does this in C:fixKeeps.",
  "Scan.luau Scan.keepouts line 834: the shop 'window' band (y 3.4..H within 1.8 of V.z1) also goes into home rooms, where +Z is the room door, so wall art and tall cabinets near the door wall get blocked. Patch: `if V.kind ~= 'home' then V:addKeep(... 'window') end`. Its 'restroom' keeps (3.4-deep door clearances) also reach through walls into home bedrooms. For homes they are best clipped at walls or skipped (Scan.keepouts ~line 755).",
  "FYI for Housing / the HomeUnit_apartment template: Interact_wardrobe in the dress room is an invisible 4x5x8 box, so the 2.6-stud no-client-prompt zone covers the whole dress room except its two ends. A smaller part, or one placed at the closet face, would allow client interactions such as drawers in there."
 ],
 "notes": "I only edited /home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/T_home.luau. It still calls HomeWet.build(K, V, S) for kitchen, bath and entry, after its own shell trim, slot overlays and the new keep fix.\n\nChecks: all 26 home fixtures run with simall.sh with no errors and blocked=0. A harness I added fires every prompt twice, runs the animations over time and calls rebuildSlot on every slot; all 12 of my fixtures pass with errs=0. I did at least 3 render rounds on every assigned fixture with close-up cameras (most got 4-5), plus night renders for the apartment living and bedroom, the officetel living (cat, fan, sofa) and the penthouse fireplace.\n\nBugs fixed:\n- Sofa arm piping had its K:cyl length and diameter swapped. Every sofa arm grew a 3.1-stud disc; this was the large flat 'oval tray' visible beside sofas in every tier.\n- A kitchen slot under the officetel loft (the bar table) was claimed and built twice, once by the kitchen and once by the loft. The slot owner probe now uses the slot's real height.\n- tween was a local declared after its first use, so the dress-room drawer slide would have called nil.\n- Dress room: drawer fronts faced the wall, and the drawer unit and the rail with clothes ran across the master-bath doorway. Rails and drawers now split around wall openings, and fronts face the aisle.\n- Dress room: about 300 parts of 6-part shoes and sweaters were cut. Shoes are now sole plus upper; sweaters are a box plus a fold line.\n- The robot vacuum animation could index a negative path step.\n- The fireplace glass was dark Glass material, which hid the neon flames at night. It is now translucent SmoothPlastic, and the flames are layered and pointed over a glow band.\n- The duvet 'wrinkle' ellipses showed as lumps on beds and were removed.\n\nNew shared-safe helpers inside T_home:\n- C:fixKeeps runs per room build only. It drops slot keeps from other floors, clips slot keeps at shell walls, and removes the shop window band for non-wet rooms. Door, point and other-slot keeps are left alone.\n- C:wallSpotHigh is for wall decor at y >= 4; it ignores only door and restroom keeps.\n- Also: slotRecOf, slotAt, C:bedRug, C:lowShelf, C:ceilingRack, P.beanBag, P.rollingCart, P.pictureLedge, P.catTower and P.ceilingFan.\n- overlaySlot now stores its F frame. rebuildSlot also rebuilds the bed rug and the penthouse under-bed glow when the bed slot changes.\n- K.homeCx = Cx is set for offline testing.\n\nPlacement guards and limits:\n- The new loose floor props respect V.decorPlus.\n- My lights stay at 3 or fewer per room (C:light cap); glow otherwise uses Neon.\n- Client prompts stay at 4 or fewer per room. The officetel living drops its floor-lamp toggle (noLampToggle) so it keeps curtain, robot vacuum, fan and cat.\n\nTools:\n- Test harness: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/hometools/test.sh\n- Tagged renders: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/hometools/run2.sh\n- Part listers: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/hometools/dump.py and /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/hometools/gen.py\n- Cameras: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/cams/hm/*.json\n\nKnown limits:\n- The apartment living walls are fully taken by slots, so the robot vacuum, toy basket and photo cluster cannot be placed there.\n- Penthouse dining has no full-height free wall, so its sideboard code places nothing.\n- The tub-fill idea was skipped because it would duplicate the server's 반신욕/shower action.\n\nNothing was committed."
}
```

## build:HomeWet

```json
{
 "summaryKo": "현관: 다섯 등급 모두 현관 철문 안쪽 면을 새로 입혔습니다. 원룸은 웜그레이, 오피스텔은 차콜, 아파트는 화이트그레이지 도어 필름에 홈 몰딩을 두르고 방화문 스티커와 말굽 도어스토퍼를 달았습니다. 원룸·오피스텔 문에는 배달 자석 전단(광안 통닭, 황금 반점, 피자 한판)과 자석 클립에 끼운 관리비 고지서를 붙였습니다. 앞면이 엇나가 있던 신발장(원룸 1.1×2.3, 아파트 6.7 폭 붙박이장)은 바로 세웠습니다. 이제 문짝 여러 짝, 열리는 칸 안의 신발, 거울 문, 니치 쟁반과 디퓨저가 제자리에 있습니다. 옆으로 튀어나와 있던 월패드는 벽에 납작하게 붙였습니다. 우산꽂이와 택배 상자는 문 앞 통로를 피해 놓습니다. 벽 없는 허공에 떠 있던 구둣주걱 같은 벽 소품은 진짜 벽 앞, 실제 벽면 깊이에만 붙습니다. 원룸·오피스텔은 열고 닫는 분전반 문(안에 메인·분기 차단기)을 상호작용 프롬프트가 겹치지 않는 벽에만 답니다. 아파트에는 바다 풍경 그림, 펜트하우스에는 문 정면 파티션에 황동 액자 그림과 그림 조명 네온 띠, 신발 신는 벤치와 손님 슬리퍼를 더했습니다. 펜트하우스 호두나무 붙박이장도 한 톤 밝혔습니다. 욕실: 펜트하우스는 물탱크 없는 일체형 스마트 비데에 벽 리모컨과 무드 네온을 달았습니다. 탱크형 변기 위에는 여분 휴지와 방향제를 올렸고, 오피스텔 이상 샤워 칸에는 스퀴지를 걸었습니다. 아파트 욕조 테두리에는 엎어 둔 대야와 바가지를 놓았습니다. 휴지걸이는 이제 다섯 등급 모두에 있습니다. 변기솔은 오피스텔을 뺀 네 곳, 욕실화는 고시원을 뺀 네 곳에 놓였고, 원룸은 발매트를 새로 짓고 그 위에 욕실화를 올렸습니다. 주방: 펜트하우스는 상부장을 밝은 호두나무로 바꿔 하부장과 투톤을 만들었습니다. 새카맣게 보이던 냉장고는 호두나무 패널의 냉장·냉동 두 칼럼에 손잡이 한 쌍과 위쪽 환기 그릴을 단 모습으로 바꿨습니다. 나머지 주방(싱크대, 인덕션과 냄비, 후드, 식기건조대, 밥솥, 김치냉장고, 분리수거함 등)은 앞 작업분을 확인하고 그대로 두었습니다. 14개 픽스처가 모두 오류 없이 돌아가고, 낮·밤 렌더도 확인했습니다.",
 "interactions": [
  "현관 신발장 문 열기/닫기 (모든 등급, 열린 칸 안에 신발)",
  "분전반 문 열기/닫기 (원룸/오피스텔 현관, 프롬프트가 HomeInteract와 겹치지 않는 진짜 벽에만)",
  "도어 가드(걸쇠) 걸기/풀기 (ExitDoor 프롬프트와 겹치지 않을 때만 프롬프트)",
  "현관 센서등: 가까이 가면 자동으로 켜짐 (프롬프트 없음)",
  "월패드 화면 순환 (프롬프트 없음, 등급별 문구)",
  "욕실: 수전 물 틀기, 거울 수납장 열기, 환풍기 켜기, 변기 뚜껑 열기/닫기",
  "주방: 수전 물 틀기, 수납장 문, 후드 팬, 서랍, 드럼세탁기 세탁 시작, 밥솥 취사 시작 (앞 작업분, 회귀 확인)"
 ],
 "fixtures": [
  {
   "key": "home_goshiwon_bath",
   "parts": 209,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_goshiwon_entry",
   "parts": 170,
   "ok": true,
   "hidden": 11,
   "lights": 0,
   "prompts": 1,
   "blocked": 0
  },
  {
   "key": "home_oneroom_kitchen",
   "parts": 297,
   "ok": true,
   "hidden": 35,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_oneroom_bath",
   "parts": 427,
   "ok": true,
   "hidden": 20,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_oneroom_entry",
   "parts": 238,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 1,
   "blocked": 0
  },
  {
   "key": "home_officetel_kitchen",
   "parts": 438,
   "ok": true,
   "hidden": 55,
   "lights": 1,
   "prompts": 5,
   "blocked": 0
  },
  {
   "key": "home_officetel_bath",
   "parts": 392,
   "ok": true,
   "hidden": 19,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_officetel_entry",
   "parts": 244,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 1,
   "blocked": 0
  },
  {
   "key": "home_apartment_kitchen",
   "parts": 941,
   "ok": true,
   "hidden": 99,
   "lights": 1,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_apartment_bath",
   "parts": 1035,
   "ok": true,
   "hidden": 43,
   "lights": 2,
   "prompts": 6,
   "blocked": 0
  },
  {
   "key": "home_apartment_entry",
   "parts": 412,
   "ok": true,
   "hidden": 20,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_penthouse_kitchen",
   "parts": 470,
   "ok": true,
   "hidden": 36,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_bath",
   "parts": 422,
   "ok": true,
   "hidden": 21,
   "lights": 1,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_penthouse_entry",
   "parts": 602,
   "ok": true,
   "hidden": 31,
   "lights": 1,
   "prompts": 2,
   "blocked": 0
  }
 ],
 "sheets": [
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_goshiwon_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_goshiwon_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_oneroom_kitchen.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_oneroom_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_oneroom_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_officetel_kitchen.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_officetel_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_officetel_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_kitchen.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_kitchen.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/hwdbg/night.jpg"
 ],
 "sharedRequests": [
  "T_home (욕실 몰딩): T_home 이 욕실(V.room == 'bath')에도 나무색 HomeBaseboard / HomeBaseboardLine / HomeBaseboardBead 를 붙입니다(고시원 욕실에서 11개씩, 타일 벽 아래 갈색 띠로 보임). 욕실 칸에서는 걸레받이를 건너뛰거나(타일은 바닥까지 내려옴) 타일색 회색 PVC(약 196,194,188, SmoothPlastic)로 바꿔 주세요. 예: 걸레받이 루프 첫머리에 `if self.V.room == 'bath' then return end`.",
  "T_home 또는 서버 카탈로그 (펜트하우스 올리브 나무): 거실 FurnitureSlot plant_olive_large 의 Canopy 파트(로컬 x≈9.65, y≈7.7, 지름 1.98)가 x=9 주방 파티션을 뚫고 나와 주방 쪽 벽에 초록 덩어리로 보입니다. 슬롯 오버레이에서 수관을 벽 안쪽으로 줄이거나 옮기고, 뚫고 나온 Canopy 를 로컬로 숨겨 주세요(protected 라서 HomeWet 은 숨길 수 없음).",
  "Scan/Homes (참고, 막히지는 않음): Homes 가 fitRoom 에 margin 0.4 를 넘겨서, 중심이 방 상자 0.4 밖에 있는 벽 두께 안 파트(현관 DoorLeaf, 경계 벽)는 V.byName/V.parts 에 들어가지 않습니다. HomeWet 은 V.model 을 직접 읽어(읽기만) 우회했습니다. 다른 모듈도 문짝·벽 레코드가 필요하면 Homes 에서 margin 을 0.5 로 올리면 됩니다(공용 코드 변경 필수 아님)."
 ],
 "notes": "수정한 파일은 /home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/HomeWet.luau 하나뿐입니다(4633 → 5083줄). 앞 작업분은 그대로 두고 그 위에 쌓았습니다.\n\n고친 버그:\n(1) 월패드 slab 인자 순서가 틀려 몸체가 벽에서 0.7 튀어나와 있었습니다. 펜트하우스 현관에서 선반처럼 보이던 그 부분입니다.\n(2) nearestWall 이 거의 같은 거리일 때 짧은 끝면을 앞면으로 골라, 원룸·아파트 신발장이 옆으로 돌아가 있었습니다. 이제 길쭉한 물건은 얇은 축에 수직인 벽 둘 가운데 가까운 쪽을 고릅니다.\n(3) entryClutter 의 wallSlot 이 방 상자 테두리에 물건을 걸어, 원룸 현관 문 앞 허공에 구둣주걱이 떠 있었습니다(시트에서 '검은 기둥'으로 보이던 것). 이제 벽 파트가 실제로 뒤에 있어야 하고(solidBehind), 실제 벽면 깊이에 맞춰 붙이며(wallFaceOffset), 벽면이 고르지 않은 자리는 쓰지 않습니다.\n(4) 우산꽂이·택배 같은 현관 바닥 소품이 문 앞 통로에 놓였습니다. 이제 C.doorKeep 통로를 피합니다.\n(5) 현관 문짝(DoorLeaf)이 fitRoom margin 밖이라 V.byName 에 없었습니다. V.model 을 읽기만 해서 찾습니다.\n(6) 큰 샤워 HomeInteract 자리 안에서는 욕실화와 변기솔이 놓이지 못했습니다. 새 claim 모드 lowmat 은 큰 point 자리만 무시하고, 작은 point·slot·solid·예약 검사는 그대로 합니다.\n\n이번 세션 중에 생긴 회귀(펜트하우스 가운 걸이의 dx 미정의)는 찾아서 고쳤고, 마지막 sim 에서 14개 모두 단계 오류 0입니다. luau-compile 통과했습니다.\n\n새 불빛은 없습니다. 그림 조명과 스마트 비데 무드등은 Neon 이라 방마다 불빛 수가 그대로입니다(T_home 몫 포함 0~2). V.decorPlus 이면 벤치와 욕실화 같은 바닥 소품은 짓지 않고, 벽에 거는 물건과 붙박이만 짓습니다. 테마로 색이 바뀌는 Shell(Room/Surface) 파트 위에 새로 덮은 것은 없습니다. 문 필름은 테마가 없는 철문 DoorLeaf 에만 입혔고, TileWall·FloorBath 에도 Room/Surface 속성이 없습니다.\n\n알려진 남은 점:\n- 고시원 욕실(3×3 칸)에는 앞서 지은 물건의 예약 자리가 칸 전체를 덮어 욕실화를 둘 곳이 없습니다. 오피스텔 욕실은 변기솔 자리가 없습니다.\n- 고시원 세면대 수전, 그리고 원룸·오피스텔의 도어 가드 프롬프트는 서버 HomeInteract(샤워, ExitDoor)와 너무 가까워 일부러 막아 두었습니다. 물건 자체는 지어집니다.\n- 그 때문에 원룸·오피스텔·고시원 현관은 프롬프트가 1개뿐이고(목표는 2~4개), 상호작용은 나머지 자동 동작(센서등, 월패드 화면 순환)으로 채웁니다. 원룸·오피스텔은 분전반 프롬프트가 겹치지 않는 진짜 벽이 없어 분전반을 짓지 않습니다. 시뮬레이션 기준이며, 같은 픽스처라도 분전반 자리를 찾을 때는 프롬프트가 2개 나옵니다.\n- 아파트 욕실에서 보이는 짙은 세로 판은 서버 ShowerGlass 입니다. 오피스텔 샤워 칸 바닥의 검은 덩어리는 HomeWet 이 만든 파트에서는 찾지 못했고, 처음 렌더부터 있던 것입니다.\n\n미리보기 렌더러에서는 Glass+Reflectance 거울이 평평한 회색으로 나옵니다. Roblox 에서는 반사됩니다.\n\n이 결과를 내는 데 쓴 렌더 확인용 카메라 파일은 /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/cams/hw_*.json, 밤 렌더(n_* 뷰)는 hwn_*.json 입니다. 오늘 sim 로그는 out/hwr_*.log 와 out/hwrn_*.log 입니다.",
 "critique": [
  "현관이 가장 약했고 고쳤습니다: 철문 안쪽이 맨 검은 판이었고, 신발장 두 개(원룸·아파트)가 짧은 끝면을 앞으로 해 서 있었고, 허공에 뜬 구둣주걱이 문 앞에 검은 기둥처럼 보였습니다.",
  "벽에 거는 물건은 이제 진짜 벽 파트가 뒤에 있어야 하고 실제 벽면 깊이(파티션 두께)에 맞춰 붙습니다. 펜트하우스 그림은 처음에 0.2 만큼 파티션 안에 묻혀 있었습니다.",
  "펜트하우스 주방은 상부장·냉장고가 렌더러 조명에서 새카맣게 보였습니다. 패널형 호두나무 냉장고 칼럼과 투톤 상부장으로 읽히게 했습니다.",
  "펜트하우스 욕실 변기를 일체형 스마트 비데로 바꿨습니다. 뒤 몸체가 아직 낮은 물탱크처럼 보이니 더 납작하게 다듬을 여지가 있습니다.",
  "남은 아쉬움: 고시원 욕실에 욕실화가 없고 오피스텔 욕실에 변기솔이 없습니다. 아파트 현관 그림이 서버의 인테리어 태블릿 바로 옆이라 그 벽이 조금 붐빕니다.",
  "밤 렌더(원룸 주방, 아파트 주방, 오피스텔 욕실)는 따뜻하고 읽기 쉽습니다. 붙박이 가전 화면과 LED 띠가 빛 없이 Neon 만으로 빛납니다."
 ]
}
```

## review:T_home

```json
{
 "summaryKo": "이번 검수로 T_home.luau 하나만 고쳤고, 26개 집 방 모두 오류 없이 돕니다. 렌더는 낮 근접 2회, 밤 1회, 부분 확인 2회를 돌렸습니다. 고시원 1인실과 원룸은 구성을 그대로 두고, 같은 '아치+점' 그림이 여러 집에서 반복되던 것만 바꿨습니다. 이제 상품 · 등급 · 방에 따라 웜 아치 · 먹선 드로잉 · 색면 회화 중 하나가 걸리고, 원룸 거실 액자와 아파트 거실 2폭 그림도 서로 다릅니다. 오피스텔 복층 침실과 모든 등급 침대의 베개는 원반처럼 보이던 납작한 타원 대신, 모서리가 둥근 직사각 베개에 가운데가 볼록하고 앞쪽에 박음선이 있는 모양이 됐습니다. 아파트 안방 침대 위에는 바다 그림이 두 장 겹치지 않도록 '광안대교 노을' 사진을 새로 그렸습니다(보라 · 분홍 · 주황 하늘, 낮은 해, 물빛 반사, 다리 실루엣과 조명). 아파트 서재의 빈 벽에는 바닷가 가족사진 4장(옷 색이 다른 어른 · 아이)을 걸고, 책상 옆에는 동그라미 친 10월 달력을 달았습니다. 펜트하우스 서재의 세계지도는 노란 덩어리 세 개에서 경위선, 알아볼 수 있는 대륙 30여 조각(한반도 · 일본 포함), 나침반, 부산 핀이 있는 앤티크 지도로 바뀌었습니다. 펜트하우스 침실의 프리스탠딩 욕조는 뚜껑처럼 막혀 있던 판 대신 림 · 안쪽 띠 · 물이 보이고, 트레이 · 초 · 와인잔이 물 위에 놓입니다. 침대 가운데 검은 상자처럼 보이던 포인트 쿠션은 어두운 스로우 색일 때 카라멜 · 머스터드 톤으로 바뀝니다. 그 밖에 기본 가구를 돌릴 때와 아트월 색이 테마로 바뀔 때도 오버레이가 따라가게 했고, TV 화면 · 테마 쉘 면 · 창밖 풍경은 어떤 코드 경로로도 숨겨지지 않게 막았습니다.",
 "interactions": [
  "상호작용은 이번에 새로 추가하지 않았습니다. 이전 작업의 상호작용은 프롬프트를 두 번씩 누르고 슬롯을 다시 짓는 테스트에서 모두 통과했습니다(errs=0).",
  "goshiwon/main: 롤 블라인드, 책상 밑 멀티탭(모니터 · 선풍기), 벽걸이 에어컨",
  "oneroom/main: 커튼, 플로어 스탠드, 에어컨",
  "officetel/living: 전동 커튼, 로봇청소기 청소 시작, 실링팬, 고양이 장난감",
  "officetel/loft: 독서등, 무드등, 에어컨",
  "apartment/living: 전동 커튼, 아크 스탠드, 공기청정기 모드",
  "apartment/bedroom: 암막 전동 커튼, 에어컨, 화장대 거울 LED, 난방 조절기",
  "apartment/dress: 선반 LED 스위치, 백라이트 전신 거울",
  "apartment/study: 독서 스탠드, 롤 블라인드, 에어컨",
  "penthouse/living: 전동 커튼, 아크 스탠드, 벽난로 불(깜빡임 + 불빛)",
  "penthouse/dining: 전동 커튼, 허리케인 촛불, 바 조명",
  "penthouse/study: 지구본 돌리기, 위스키 진열장 조명, 라운지 독서 램프",
  "penthouse/bedroom: 전동 커튼, 공기청정기 모드, 침대 밑 간접등"
 ],
 "fixtures": [
  {
   "key": "home_goshiwon_main",
   "parts": 645,
   "ok": true,
   "hidden": 109,
   "lights": 0,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_oneroom_main",
   "parts": 791,
   "ok": true,
   "hidden": 112,
   "lights": 1,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_officetel_living",
   "parts": 851,
   "ok": true,
   "hidden": 103,
   "lights": 1,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_officetel_loft",
   "parts": 452,
   "ok": true,
   "hidden": 33,
   "lights": 2,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_apartment_living",
   "parts": 558,
   "ok": true,
   "hidden": 68,
   "lights": 1,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_apartment_bedroom",
   "parts": 630,
   "ok": true,
   "hidden": 47,
   "lights": 0,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_apartment_dress",
   "parts": 571,
   "ok": true,
   "hidden": 22,
   "lights": 1,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_apartment_study",
   "parts": 652,
   "ok": true,
   "hidden": 70,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_living",
   "parts": 648,
   "ok": true,
   "hidden": 77,
   "lights": 2,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_dining",
   "parts": 790,
   "ok": true,
   "hidden": 132,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_study",
   "parts": 888,
   "ok": true,
   "hidden": 54,
   "lights": 2,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_penthouse_bedroom",
   "parts": 533,
   "ok": true,
   "hidden": 49,
   "lights": 0,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_goshiwon_bath",
   "parts": 241,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_goshiwon_entry",
   "parts": 246,
   "ok": true,
   "hidden": 11,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_oneroom_kitchen",
   "parts": 301,
   "ok": true,
   "hidden": 35,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_oneroom_bath",
   "parts": 479,
   "ok": true,
   "hidden": 20,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_oneroom_entry",
   "parts": 353,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_officetel_kitchen",
   "parts": 449,
   "ok": true,
   "hidden": 55,
   "lights": 1,
   "prompts": 5,
   "blocked": 0
  },
  {
   "key": "home_officetel_bath",
   "parts": 422,
   "ok": true,
   "hidden": 19,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_officetel_entry",
   "parts": 317,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_apartment_kitchen",
   "parts": 942,
   "ok": true,
   "hidden": 99,
   "lights": 1,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_apartment_bath",
   "parts": 1075,
   "ok": true,
   "hidden": 43,
   "lights": 2,
   "prompts": 6,
   "blocked": 0
  },
  {
   "key": "home_apartment_entry",
   "parts": 575,
   "ok": true,
   "hidden": 20,
   "lights": 0,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_penthouse_kitchen",
   "parts": 479,
   "ok": true,
   "hidden": 36,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_bath",
   "parts": 460,
   "ok": true,
   "hidden": 21,
   "lights": 1,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_penthouse_entry",
   "parts": 855,
   "ok": true,
   "hidden": 31,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  }
 ],
 "sheets": [
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/rv/v2_combo.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/rv/n3a.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/rv/n3b.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/rv/q1.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/rv/q2a.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_goshiwon_main__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_oneroom_main__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_officetel_living__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_officetel_loft__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_living__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_bedroom__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_dress__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_apartment_study__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_living__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_dining__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_study__q2.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/home_penthouse_bedroom__q2.jpg"
 ],
 "sharedRequests": [
  "Optional, robustness: Scan.hide could itself refuse three kinds of part: those named Screen or TVScreen (or carrying a SurfaceGui), those with both Room and Surface attributes, and those under a Backdrop or WindowView ancestor. Patch at the top of Scan.hide: `if p.Name == 'Screen' or p.Name == 'TVScreen' or p:FindFirstChildOfClass('SurfaceGui') or (p:GetAttribute('Room') ~= nil and p:GetAttribute('Surface') ~= nil) or p:FindFirstAncestor('Backdrop') or p:FindFirstAncestor('WindowView') then return end`. T_home now does this in its own C:hide, so this would only protect the other T_ builders.",
  "Still open from the previous builder; T_home works around these in C:fixKeeps. (1) In Homes.post, slot keeps should start at the slot's own floor (SlotBase Y), not at the room floor; otherwise mezzanine beds leave a full-height column in the room below. (2) In Scan.keepouts, the shop 'window' band (about line 834) should be skipped for V.kind == 'home', because +Z in a home room is the door side, not a shop front.",
  "Harness only, not game code: bprev/sim.luau has no switch for V.decorPlus. I tested decorPlus by adding `V.decorPlus = true` after Homes.post in a copied sim (out/sim_rvdp.luau). A `--decor` flag would make this repeatable."
 ],
 "critique": [
  "Fixed: penthouse bedroom freestanding tub. A full rim slab covered the whole top, so the tub looked like it had a lid and the water was hidden. It is now an oval shell with a thin rim, an inner shading band and visible water. The tray, candle and wine glass were raised so they no longer cut into the water.",
  "Fixed: the same 'warm' arch-and-dot painting appeared in the oneroom, the apartment living room (diptych) and the apartment study. Slot art now picks warm, lines or colour-field from a hash of item, tier and room, and the diptych keeps one style for both panels.",
  "Fixed: the apartment bedroom showed two near-identical sea paintings side by side (the slot art plus our canvas). Our canvas is now a new 'sunset' kind: a Gwangan Bridge sunset photo with banded sky, low sun, sea reflections, and a bridge silhouette with deck lights.",
  "Fixed: every tier's bed pillows were single lens-shaped ellipsoids that read as flat discs. They are now a rounded-rectangle body with a centre puff and a front seam line in a slightly darker tone (an earlier tint went lighter by mistake; corrected).",
  "Fixed: when the throw was navy or black, the penthouse and apartment accent cushion took the same colour and read as a black box in the middle of the bed. Dark throws now switch it to caramel (lux 5) or mustard.",
  "Fixed: the penthouse study 'world map' was five yellow blobs. It is now an antique equirectangular map with a 30-degree graticule, about 35 continent and island ellipses (including Korea and Japan), a compass rose and a Busan pin with a needle.",
  "Fixed: the apartment study had two large blank walls. Added a beach family-photo cluster and a desk-side October calendar. Both are skipped when V.decorPlus is set.",
  "Fixed: photo-cluster pictures showed tall black alien-like silhouettes. They are now beach snapshots with sky, sea and sand bands and 2-3 people (one smaller child) in varied shirt colours, with flat disc heads and hair so nothing pokes out past the frame.",
  "Fixed (contract, rotation): when the server rotates a DEFAULT slot piece it calls PivotTo and fires no ChildAdded or ChildRemoved, so the overlay kept the old pose. slotOverlays now also listens to the default piece's base-part CFrame and rebuilds the slot.",
  "Fixed (contract, theme colour): art-wall grout colour was read only once at build time. The grout now listens to the ArtWall part's Color and recolours itself when a theme is bought (the connection is stored in K.conns so it is cleaned up on teardown).",
  "Fixed (contract guard): C:hide now refuses Screen and TVScreen parts, parts with a SurfaceGui, Room/Surface shell parts, and anything under Backdrop or WindowView. Hidden counts did not change in any fixture, so nothing was being violated before.",
  "Checked, not a bug: the large silver 'cone' in the dress-room default views is the end of the 0.1-stud rail seen from 0.4 studs away by a corner camera. The white bar on the officetel TV wall is a server linear pendant.",
  "Checked, not a bug: some default-sheet tiles (backL, backR, cornerR) were stale PNGs from 16 Oct, because the default rig now writes only some views. The penthouse bedroom art and the apartment bedroom dresser really are present. All judgements were made on fresh close-up runs instead.",
  "Checked: the night whisky-cabinet glass door in the penthouse study appears as a white panel. This is the preview's specular reflection of the ceiling panel on Glass at Transparency 0.7, so I left it.",
  "Not fixed (geometry): the blank wall left of the penthouse dining back-bar is only about 1.5 studs of dining wall. The rest belongs to the open-plan neighbouring room, which builds its own walls, so gallery art cannot fit there.",
  "Not fixed (geometry): the goshiwon storage-bed headboard cap sits flush with the desk front and about 0.15 studs above the desk top. This follows the server's bed slot geometry, inside the reserved footprint, and was left as is.",
  "Not fixed (renderer): the zig-zag shadow banding near ceilings and on wardrobe tops comes from the offline renderer's shadow map. No Kit part causes it.",
  "Verified: all 26 home fixtures ran in simall.sh with no errors and blocked=0. All 12 T_home fixtures pass the prompt, animation and slot-rebuild harness (errs=0). The decorPlus sim was also error-free; loose floor props drop out and slot overlays remain. Lights stay at 3 or fewer and client prompts at 4 or fewer per room."
 ],
 "notes": "I edited only /home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/T_home.luau. I made no commits. The parent workflow's own work-in-progress commit 8cce70e already picked up most of these edits; the only uncommitted change is the decorPlus guard in the apartment study.\n\nChanged areas:\n- C:hide: contract guard.\n- slotOverlays: listens to the default piece's CFrame so a rotation triggers a rebuild.\n- Art wall: grout follows theme colour changes.\n- artPaint: new 'sunset' kind.\n- SLOT.art: painting style varies per item, tier and room.\n- Bed pillows and accent cushion.\n- Penthouse bedroom tub.\n- Penthouse study world map.\n- Apartment study: photo cluster and calendar.\n- P.photoCluster: beach snapshots.\n\nHomeWet.build is still called for kitchen, bath and entry after the shell trim, as before.\n\nRender rounds:\n- Default rig: all 12 fixtures.\n- v1: close-ups of all 12.\n- v2: targeted fixes.\n- n3: night, all 12. One n3 sheet was briefly an older run's file, because that tag already existed in shots/; it was re-rendered.\n- q1: targeted close-ups.\n- q2: final close-ups of all 12.\n\nTools and cameras:\n- Generated-part lister: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/rvtools/gd.py\n- Batch render scripts: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/rv/go.sh and /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/rv/go2.sh\n- Close-up cameras: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/cams/rv/*.json\n\nCaveat for whoever renders next: tags such as v1 and n3 already existed in shots/ from earlier runs. Use fresh tags so stale sheets are not mistaken for current ones."
}
```

## review:HomeWet

```json
{
 "summaryKo": "현관: 다섯 등급 모두 신발을 새로 만들었습니다. 운동화는 겉창, 두툼한 흰 미드솔, 고무 앞코, 혀, 끈 세 줄, 뒤축 탭, 옆 로고로 짓고, 구두와 로퍼는 굽, 웰트, 페니 띠, 광택으로 지어서 더는 상자로 보이지 않습니다. 고시원 현관에는 법정 비치품인 3.3kg ABC 소화기(안전핀, 압력계, 호스, 노즐, 라벨)를 두었습니다. 오피스텔과 아파트의 우산꽂이, 택배, 소화기는 이제 벽 두께 안으로 파고들지 않고 방 안쪽에 놓입니다. 아파트 아이 킥보드는 바퀴가 바닥에 눕혀진 원판이었는데, 이제 바퀴가 세워져 있고 LED 허브, 포크, 브레이크, 그립테이프가 있습니다. 펜트하우스 현관 그림은 환기 그릴처럼 보이던 단색화를 달항아리 그림(바닥 띠, 그림자, 이음선, 입, 굽, 하이라이트, 붉은 낙관)으로 바꿨습니다. 욕실: 원룸·오피스텔·아파트 세면대 뒤 띠에 칫솔컵과 칫솔 둘, 치약, 핸드워시 펌프를 놓았습니다. 원룸 샤워 칸에는 없던 샤워 선반(샴푸, 린스, 바디워시, 비누, 이태리타올, 샤워볼)을 걸었습니다. 고시원 바 수전은 좁은 칸에 맞게 짧아져 벽을 뚫지 않습니다. 욕실 천장 테두리의 갈색 나무 몰딩은 흰 PVC로 바꾸고 나무 걸레받이는 감췄습니다. 펜트하우스는 일체형 스커트 몸통 스마트 변기로 바꾸고, 변기를 실제 타일 면까지 당겼으며, 세면대를 관통하던 유리판은 이 클라이언트에서만 숨겼습니다. 주방: 모든 등급에서 싱크볼 안을 하부장 몸통이 메워 납작한 판으로 보이던 것을 고쳐, 이제 깊은 개수대(담가 둔 그릇, 거름망, 고무장갑)가 보입니다. 아파트에는 언더싱크 직수 정수기 전용 수전을 달았습니다. 펜트하우스 상부장과 냉장고 패널은 밝은 호두나무로 밝혔고, 에스프레소 머신(그룹헤드, 포터필터, 스팀 완드, 압력계, 컵 워머)은 엉뚱한 곳에 떠 있던 포터필터를 제자리에 다시 지었습니다. 오피스텔 캡슐머신은 벽에 박히던 물통을 1.0 깊이 안으로 들였고, 얼굴처럼 보이던 버튼을 위로 옮겼습니다.",
 "interactions": [
  "현관: 신발장 문 열기/닫기 (모든 등급, 안에 신발), '신발 정리' (벗어 던진 운동화 바로 세우기), 분전반 문 (원룸/오피스텔, 프롬프트 겹치지 않는 벽이 있을 때), 도어 가드 걸쇠 (ExitDoor와 겹치지 않을 때), 택배 상자 뜯기, 센서등 자동 점등 · 월패드 화면 순환 (프롬프트 없음)",
  "욕실: 세면대 수전 물 틀기/잠그기, 거울 수납장 열기 (원룸~아파트), 환풍기 켜기, 변기 뚜껑 열기/닫기",
  "주방: 싱크대 수전 물, 그릇 수납장 문, 레인지 후드 팬, 수저 서랍, 드럼세탁기 세탁 시작, 밥솥 취사 시작",
  "이번 수정에서 새 프롬프트는 없습니다 (프롬프트 수 변화 없음, 서버 집 행동과 중복 없음)"
 ],
 "fixtures": [
  {
   "key": "home_goshiwon_bath",
   "parts": 241,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_goshiwon_entry",
   "parts": 246,
   "ok": true,
   "hidden": 11,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_oneroom_kitchen",
   "parts": 301,
   "ok": true,
   "hidden": 35,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_oneroom_bath",
   "parts": 479,
   "ok": true,
   "hidden": 20,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_oneroom_entry",
   "parts": 353,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_officetel_kitchen",
   "parts": 449,
   "ok": true,
   "hidden": 55,
   "lights": 1,
   "prompts": 5,
   "blocked": 0
  },
  {
   "key": "home_officetel_bath",
   "parts": 422,
   "ok": true,
   "hidden": 19,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_officetel_entry",
   "parts": 317,
   "ok": true,
   "hidden": 16,
   "lights": 0,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_apartment_kitchen",
   "parts": 942,
   "ok": true,
   "hidden": 99,
   "lights": 1,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_apartment_bath",
   "parts": 1075,
   "ok": true,
   "hidden": 43,
   "lights": 2,
   "prompts": 6,
   "blocked": 0
  },
  {
   "key": "home_apartment_entry",
   "parts": 575,
   "ok": true,
   "hidden": 20,
   "lights": 0,
   "prompts": 4,
   "blocked": 0
  },
  {
   "key": "home_penthouse_kitchen",
   "parts": 479,
   "ok": true,
   "hidden": 36,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  },
  {
   "key": "home_penthouse_bath",
   "parts": 460,
   "ok": true,
   "hidden": 22,
   "lights": 1,
   "prompts": 2,
   "blocked": 0
  },
  {
   "key": "home_penthouse_entry",
   "parts": 855,
   "ok": true,
   "hidden": 31,
   "lights": 1,
   "prompts": 3,
   "blocked": 0
  }
 ],
 "sheets": [
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_r1_home_oneroom_kitchen.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_r1_home_oneroom_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_r1_home_goshiwon_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_r1_home_oneroom_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_r1_home_apartment_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_r2_home_penthouse_kitchen.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_r2_home_penthouse_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_r2_home_goshiwon_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_f1_home_penthouse_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_f1_home_officetel_kitchen.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_f1_home_officetel_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_w1_home_oneroom_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_w1_home_penthouse_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_n3_home_oneroom_kitchen.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_n3_home_apartment_entry.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_n3_home_penthouse_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_b0_home_apartment_kitchen.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_b0_home_apartment_bath.jpg",
  "/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/shots/rv_b0_home_officetel_bath.jpg"
 ],
 "sharedRequests": [
  "T_home (욕실 몰딩, 근본 수정): 욕실(V.room == 'bath')에도 나무 HomeBaseboard*와 HomeCrown*가 붙습니다. 지금은 HomeWet.build가 bath 방에서 이번 방 빌드 중 T_home이 만든 파트(K.parts[1..K.hwStart])를 손봅니다: HomeBaseboard*는 Transparency = 1, HomeCrown*는 Color (234,234,230) + SmoothPlastic. T_home에서 직접 고쳐 주세요. baseboardRun(C_, s, u0, u1) 첫 줄에 `if C_.room == \"bath\" then return end`를 넣고, 욕실 크라운 look을 흰 PVC lk(234,234,230)로 바꾸면 됩니다. 그러면 HomeWet 쪽 패치는 할 일이 없어집니다.",
  "T_home 슬롯 오버레이 (펜트하우스 올리브 나무, 아직 그대로): 거실 FurnitureSlot plant_olive_large의 Canopy(서버, protected)가 x≈9 주방 파티션을 뚫고 나옵니다. 주방 쪽 벽에 초록 덩어리로 보입니다(home_penthouse_kitchen 'island' 뷰). 오버레이에서 Canopy를 숨기고 수관을 파티션 안쪽(슬롯 footprint 안)으로 다시 지어 주세요.",
  "T_home 슬롯 오버레이 (아파트 주방 몬스테라): MonsteraStem/MonsteraLeaf(주방 프레임 x≈0.8~2.1, z≈-9.7, y 1.6~2.1)가 Partition 안으로 0.4 들어갑니다. 잎 펼침을 벽 쪽 반대로 돌리거나 벽 앞 0.1까지로 줄여 주세요.",
  "서버 템플릿 HomeUnit_penthouse (욕실): 안쪽 ShowerGlass 판 하나(욕실 프레임 ≈(0.07,3.75,-3.38), 폭 1.55)가 VanityCabinet과 오른쪽 Basin을 관통합니다. HomeWet은 세면대 몸통과 0.15 넘게 겹치는 ShowerGlass/FrostBand만 로컬로 숨깁니다. 템플릿에서 그 판을 없애거나 x ≥ -0.76(샤워 칸 쪽)으로 옮겨 주세요. 같은 템플릿의 ToiletTank는 벽 속에 0.35 묻혀 있습니다(HomeWet이 변기 뒤를 타일 면까지 당겨 보정합니다).",
  "펜트하우스 안방 쪽 욕조(TubWall x4 · TubFloor · TubFaucet · TubSpout, 욕실 중심에서 x≈-18.8)는 욕실 방 상자 밖이라 HomeWet이 다루지 않습니다. 맨 상자 그대로입니다. 그 방을 맡은 T_home이 리스킨하거나, 원하면 HomeWet이 bathtub()를 HomeWet.reskinTub(K, V)로 내보내고 TubFaucet/TubSpout도 처리하도록 넓힐 수 있습니다(필요하면 요청 바랍니다)."
 ],
 "notes": "수정한 파일은 /home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior/HomeWet.luau 하나뿐입니다(지금 5615줄). luau-compile을 통과했습니다. luau-analyze에서 정의되지 않은 지역 변수는 없었고, 걸린 것은 Roblox 전역(game, Enum, CFrame 등)뿐입니다. 14개 픽스처 모두 단계 오류 없이 돕니다(위 fixtures는 마지막 sim 값). 새 불빛과 새 프롬프트는 없습니다. 테마로 색이 바뀌는 Shell 파트 위에 새 오버레이도 없습니다. V.decorPlus를 강제로 켠 디버그 sim에서 바닥 소품(택배, 소화기, 킥보드, 벤치, 욕실화, 분리수거함, 매트)이 지어지지 않는 것을 확인했습니다. 벽에 거는 우산과 리스킨한 신발은 그대로 남습니다.\n\n주요 코드 변경:\n(1) kitchenBase: CabCarcass를 싱크볼 자리에서 비웁니다(볼 바닥 아래, 앞뒤 띠, 좌우만 채움). 모든 주방에서 볼이 납작한 판으로 보이던 버그입니다.\n(2) espressoMachine: C:bar에 pcf 없이 방 좌표를 넘겨 포터필터가 엉뚱한 곳에 떠 있었습니다. 1.0 자리 안에 다시 지었습니다.\n(3) capsuleMachine: 물통이 벽에 0.2 박히던 것을 깊이 1.0 안으로 들였고, 버튼을 위로 옮겼습니다.\n(4) vanity: 볼 양옆에 자리가 없으면 볼 뒤 띠에 놓습니다(faucetXs). 원룸·오피스텔·아파트에 칫솔컵이 생겼습니다.\n(5) shower: 캐디 후보 자리를 여러 개 시도하고(원룸 캐디 생김), 중복이던 뒤 기둥을 양쪽 둘로 바꿨습니다. 바 수전 길이는 벽 폭에 맞춥니다(bh).\n(6) toilet: 펜트하우스는 스커트 몸통입니다. wallFaceOffset으로 묻힌 물탱크만큼 뒤를 당기고 tankD를 보정합니다.\n(7) entryClutter.floorSpot: wallParts와 겹치는지 검사하고, 여백 0.02~0.32로 방 안쪽으로 당깁니다.\n(8) sneaker/dressShoe 새로 짓기. extinguisher는 고시원 포함, 실제 크기로.\n(9) 킥보드 바퀴 방향 수정.\n(10) 펜트하우스 달항아리 그림, 상부장·냉장고 패널 호두나무를 C3(150,112,78) 쪽으로 85% lerp.\n(11) 아파트(ti≥4) 언더싱크 정수기 수전과 C:reserve.\n(12) 우산꽂이를 못 놓은 현관은 벽 고리에 장우산과 3단 우산을 겁니다. 원룸 현관에는 걸 수 있는 벽(뒤에 벽이 있는 빈 면)이 없어 여전히 없습니다.\n(13) towelBar를 벽 폭 안으로 자릅니다(자리가 0.8보다 좁으면 원래 크기).\n(14) 욕실에서 T_home의 걸레받이를 감추고 크라운을 흰색으로 바꿉니다(sharedRequests 1번).\n\n검사 도구(스크래치패드, 공유 코드 아님):\n- /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/hwrev/rv.sh: 새 폴더 shots/rv_<tag>_<key>/에 렌더하므로 이전 PNG가 섞이지 않습니다.\n- /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/hwrev/pen.py: 생성 파트가 서버 벽·유리·가구를 0.1 넘게 관통하는지 검사합니다.\n- /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/hwrev/q.py: 방 프레임 좌표로 근처 파트를 조회합니다.\n- 카메라 파일: /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev/cams/hwr1_*.json, hwr2_*.json, hwr3_*.json, hwn3_*.json, hwf_*.json.\n\n남은 관통은 보이지 않는 곳뿐입니다:\n- 아파트·펜트하우스 신발장/콘솔 몸통이 Partition에 0.13~0.2 들어갑니다. 서버 ShoeCabinet 자체가 벽에 묻혀 있고 벽이 두꺼워 보이지 않습니다.\n- 고시원 수건걸이 접힘이 0.12 겹칩니다. 칸이 좁아 막대를 옮기면 문 쪽을 막습니다.\n\n미리보기 렌더러 한계:\n- Glass+Reflectance 거울과 Metal은 짙은 회색·남색으로 보입니다.\n- 넓은 면에 지그재그 그림자 줄이 생깁니다.",
 "critique": [
  "[고침] 주방 싱크볼이 모든 등급에서 납작한 회색 판으로 보였습니다. 원인은 하부장 몸통 상자(CabCarcass)가 볼 안을 상판 바로 아래까지 채운 것이었습니다. 이제 몸통이 볼 자리를 비워 0.72 깊이 개수대와 그 안의 그릇, 거름망, 고무장갑이 보입니다.",
  "[고침] 펜트하우스 에스프레소 머신의 포터필터가 pcf 없이 방 좌표로 지어져 조리대 엉뚱한 곳에 떠 있었고, 몸통은 1.2×1.05로 자리(1.0×1.0)를 넘었습니다. 그룹헤드, 포터필터와 손잡이, 스팀 완드, 압력계, 컵 워머, 물받이 그릴을 갖춘 머신으로 다시 지었습니다.",
  "[고침] 오피스텔 캡슐머신은 물통이 타일 벽에 0.2 박혀 있었습니다. 앞면의 큰 흰 Neon 버튼 두 개는 로봇 얼굴처럼 보였습니다. 깊이를 맞추고 버튼은 위로 옮겼으며 투입구 선과 배지를 더했습니다.",
  "[고침] 원룸 욕실에 샴푸와 바디워시가 하나도 없었습니다(캐디 자리를 유리 칸막이가 막음). 원룸·오피스텔·아파트 세면대 위에도 칫솔컵이 없었습니다. 캐디 자리를 여러 후보로 찾고, 세면대 소품은 볼 뒤 띠에 놓아 지금은 모두 있습니다.",
  "[고침] 현관 신발이 검은 상자와 흰 상자로 읽혔습니다(시트에서 가장 '싸 보이는' 요소). 운동화와 구두·로퍼를 부위별로 다시 모델링했습니다.",
  "[고침] 고시원 현관에 소화기가 없었습니다(고시원은 법정 비치). 다른 등급 소화기도 실제(47cm)보다 작았습니다. 크기를 맞추고 고시원에도 둡니다.",
  "[고침] 아파트 킥보드 앞바퀴가 바닥에 눕힌 원판(vcyl)이었고 뒷바퀴는 굵은 드럼이었습니다. 세운 바퀴로 고쳤습니다.",
  "[고침] 오피스텔 현관 택배 상자가 파티션에 0.19 박혔습니다(방 상자 끝 = 벽 중심선). floorSpot이 이제 실제 벽 부피를 피합니다.",
  "[고침] 펜트하우스 현관의 '단색화'는 렌더에서 환기 그릴이나 라디에이터처럼 보였습니다. 바로 알아보는 달항아리 그림으로 바꿨습니다. 처음 두 사발형은 눈사람처럼 보여 어깨 넓은 한 몸통으로 다시 다듬었습니다.",
  "[고침] 펜트하우스 주방은 상부장과 냉장고 패널이 거의 검은 갈색이라 방 전체가 어두웠습니다. 밝은 호두나무로 바꾸었습니다.",
  "[고침] 펜트하우스 스마트 비데 변기가 울퉁불퉁한 덩어리였습니다. 일체형 스커트 몸통, 림, 바닥 그림자 띠로 다듬었습니다. 템플릿 물탱크가 벽 속에 0.35 묻혀 있어 변기와 그 위 수건 선반이 벽에 반쯤 들어가던 것도 실제 타일 면까지 당겼습니다.",
  "[고침, 로컬] 펜트하우스 욕실의 서버 ShowerGlass 판 하나가 세면대 몸통과 오른쪽 볼을 관통해, 열린 문짝처럼 서 있었습니다. 이 클라이언트에서만 숨기고 템플릿 수정은 sharedRequests로 넘겼습니다.",
  "[고침] 고시원 샤워 바 수전 손잡이가 좁은 칸의 파티션을 뚫었습니다. 막대 길이를 벽 폭에 맞춥니다.",
  "[고침, 로컬 우회] 욕실 천장 테두리에 갈색 나무 크라운, 타일 벽 아래에 나무 걸레받이가 보였습니다(T_home 몫). HomeWet이 욕실 방에서 감추고 흰 PVC로 바꿉니다. 근본 수정은 T_home에 요청했습니다.",
  "[추가] 아파트 84㎡ 주방에 한국 아파트 필수품인 정수기가 없었습니다. 조리대 자리가 가득해 언더싱크 직수 정수기 전용 수전(LED 링)으로 달았습니다.",
  "[남음] 아파트 주방은 조리대 끝 두 곳이 전자레인지와 식기건조대로 차 있어 에어프라이어와 커피머신이 놓이지 않습니다(오피스텔에는 있음). 오피스텔 주방에는 빌트인 전자레인지가 없습니다.",
  "[남음] 원룸 현관(4.2×2.4)에는 우산꽂이를 둘 바닥도, 벽 고리를 걸 빈 벽도 없어 우산이 없습니다. 벽 고리용 대체 코드는 넣었지만, 다른 현관은 우산꽂이가 놓여서 쓰이지 않았습니다.",
  "[남음, 타 모듈] 펜트하우스 올리브 나무 수관이 주방 파티션을 뚫습니다. 아파트 몬스테라 잎도 벽에 0.4 묻힙니다. 둘 다 T_home 슬롯 오버레이 몫입니다.",
  "[남음, 서버] 펜트하우스 욕실 템플릿에는 욕조가 없습니다(욕조는 안방 쪽 맨 상자). 고시원 수건걸이 접힘이 0.12 겹칩니다(눈에 거의 안 보임).",
  "[확인] 밤 렌더(원룸 주방, 아파트 현관, 펜트하우스 욕실·주방)는 하부장 LED, 거울 할로, 그림 조명 Neon만으로 읽힙니다. 이번 수정으로 불빛 수는 늘지 않았습니다(방마다 0~2개)."
 ]
}
```
