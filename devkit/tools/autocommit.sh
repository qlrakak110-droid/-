#!/bin/bash
# 2분마다: 바뀐 .luau 가 전부 컴파일되면 WIP 커밋 + 푸시 (에이전트들이 계속 파일을 쓰는 동안)
cd /home/user/- || exit 1
L=/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/luau/luau-compile
end=$(( $(date +%s) + ${1:-7000} ))
while [ $(date +%s) -lt $end ]; do
  if [ -n "$(git status --short)" ]; then
    ok=1
    for f in $(git status --short | awk '{print $2}'); do
      case "$f" in *.luau) [ -f "$f" ] && { $L --binary "$f" >/dev/null 2>&1 || { ok=0; echo "$(date -u +%H:%M) compile fail $f"; }; };; esac
    done
    if [ $ok = 1 ]; then
      git add -A src >/dev/null 2>&1
      if ! git diff --cached --quiet; then
        n=$(git diff --cached --name-only | sed 's#.*/##; s#\.luau##' | tr '\n' ' ' | cut -c1-120)
        git commit -q -m "Building interiors: work in progress ($n)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SXNKocePqvuAzvQ1zFMUX8" && \
        for i in 1 2 3 4; do git push -q -u origin claude/car-interior-window-rendering-6i5i62 && break; sleep $((2**i)); done
        echo "$(date -u +%H:%M) committed $(git log --oneline | head -1)"
      fi
    fi
  fi
  sleep 120
done
