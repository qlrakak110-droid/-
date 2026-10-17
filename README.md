# TREND FISHING — Roblox Mobile Starter + 임시 스튜디오 (빈 버전)

| 경로 | 내용 |
|---|---|
| `dist/TempStudio_TrendFishing.html` | **빈 임시 스튜디오 + TREND FISHING** — 브라우저(폰 포함)에서 바로 열어서 플레이 |
| `dist/TempStudio_Empty.html` | 빈 임시 스튜디오 템플릿 (엔진만, 바닥판 + 스폰, 스크립트 없음) |
| `src/server/TrendFishingServer.server.lua` | 서버 스크립트 (ServerScriptService) |
| `src/client/TrendFishingClient.client.lua` | 클라이언트 UI (StarterPlayerScripts) |
| `default.project.json` | Rojo 프로젝트 파일 |
| `tools/build_studio.py` | `src/`를 빈 스튜디오에 넣어 `TempStudio_TrendFishing.html`을 다시 만듦 |
| `tools/make_empty_studio.py` | 광안리 스튜디오 HTML에서 맵·스크립트를 빼고 빈 템플릿을 만듦 |

`src/`의 Lua를 고친 뒤에는 `python3 tools/build_studio.py`만 실행하면 스튜디오 HTML에 반영됩니다.
Roblox Studio 설치 방법과 기능 설명은 [README_KO.md](README_KO.md)를 참고하세요.
