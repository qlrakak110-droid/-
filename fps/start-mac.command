#!/bin/sh
# STRIKE ZONE server launcher (macOS / Linux)
cd "$(dirname "$0")"
if ! command -v node >/dev/null 2>&1; then
  echo ""
  echo "  Node.js가 설치되어 있지 않습니다. https://nodejs.org 에서 LTS 버전을 설치하세요."
  echo ""
  exit 1
fi
PORT="${PORT:-3000}"
( sleep 1; (open "http://localhost:$PORT" || xdg-open "http://localhost:$PORT") >/dev/null 2>&1 ) &
PORT="$PORT" node server.js
