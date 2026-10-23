#!/bin/bash
# simall.sh [keys...]: run the sim (no render) for fixtures, print V/K summary lines and errors
S=/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev
SRC=${SRC:-/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior}
cd $S
TAG=${TAG:-${ONLY:-all}}
ONLY="$ONLY" python3 -I gen.py "$SRC" out/mods_$TAG.luau >/dev/null || exit 1
KEYS="$@"; [ -z "$KEYS" ] && KEYS=$(cut -f1 batch_all.txt)
for k in $KEYS; do
  sed "s#require(\"./out/mods\")#require(\"./mods_$TAG\")#; s#require(\"./lib/rbx\")#require(\"../lib/rbx\")#; s#require(\"./fx/\"#require(\"../fx/\"#" sim.luau > out/simq_$TAG.luau
  ../luau/luau out/simq_$TAG.luau -a $k > out/$k.simout 2>&1
  if grep -q "^JSON " out/$k.simout; then grep "^JSON " out/$k.simout | sed 's/^JSON //' > out/$k.gen.json; fi
  echo "== $k"; grep "^#V\|^#K\|ERROR\|error\|failed" out/$k.simout | cut -c1-260 | head -8
  grep -v "^#\|^JSON " out/$k.simout | head -5
done
