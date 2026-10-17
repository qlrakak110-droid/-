@echo off
chcp 65001 >nul
title STRIKE ZONE Server
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo  Node.js가 설치되어 있지 않습니다.
  echo  https://nodejs.org 에서 LTS 버전을 설치한 뒤 다시 실행하세요.
  echo.
  start https://nodejs.org
  pause
  exit /b 1
)
start "" http://localhost:3000
node server.js
pause
