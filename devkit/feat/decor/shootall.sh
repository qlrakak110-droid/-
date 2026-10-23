#!/bin/bash
D=/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor
cd $D
for c in "$@"; do
  echo "== $c"; timeout 700 bash shoot.sh $c 4 14 2>&1 | tail -4
done
echo ALLDONE
