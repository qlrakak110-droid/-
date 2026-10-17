# TREND FISHING — Roblox Studio Starter

이 패키지는 Roblox Studio용 Lua 소스 프로젝트입니다. Blender가 필요 없습니다.

## 설치 방법
1. Roblox Studio에서 Baseplate 프로젝트를 엽니다.
2. Explorer에서 `ServerScriptService`에 `Script`를 추가하고 이름을 `TrendFishingServer`로 지정합니다.
3. `src/server/TrendFishingServer.server.lua` 전체 내용을 붙여 넣습니다.
4. `StarterPlayer > StarterPlayerScripts`에 `LocalScript`를 추가하고 이름을 `TrendFishingClient`로 지정합니다.
5. `src/client/TrendFishingClient.client.lua` 전체 내용을 붙여 넣습니다.
6. `View > Output`을 켠 뒤 `Play`를 눌러 테스트합니다.

## 포함 기능
- 서버에서 생성하는 저폴리 스타일 섬, 연못, 부두, 상점, 기지
- 서버 판정 낚시 보상 및 희귀도
- 코인, 낚싯대 강화, 물고기 판매, 기지 전시, 초당 수익
- DataStore 저장 코드

## DataStore 참고
저장은 게임을 Publish한 뒤 `Game Settings > Security > Enable Studio Access to API Services`를 켜야 Studio 테스트에서 동작합니다. 처음 테스트할 때는 이 설정을 켜지 않아도 플레이 기능을 확인할 수 있습니다.

## 현재 프로토타입 한계
- 낚시 입력은 버튼을 누른 뒤 일정 시간 후 자동으로 보상을 지급하는 기본 버전입니다.
- 기지 소유권/배치 위치는 간단한 프로토타입 규칙을 사용합니다.
- 모바일·PC UI는 기본 버튼형입니다. 애니메이션, 사운드, 상점 NPC, 게임패스, 정교한 낚시 미니게임은 다음 단계에서 추가할 수 있습니다.
- Roblox Studio에서 직접 실행·검증한 파일은 아니므로 Output 창에서 오류를 확인하며 테스트해야 합니다.


## 모바일 지원
- 터치 입력으로 UI 버튼을 누를 수 있습니다.
- 휴대폰 화면에서는 UI가 화면 왼쪽 위에 배치됩니다.
- `—` 버튼으로 패널을 접고 `+` 버튼으로 다시 펼칠 수 있어 Roblox 이동/점프 조작 공간을 확보할 수 있습니다.
- 모바일 실제 테스트는 Roblox 앱에서 게시된 경험을 실행해 확인해야 합니다.
