#!/bin/bash
# shoot.sh <cat|ids> [cols] [clock]: export + render a showroom -> shots/<sel>/
D=/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor
cd $D && python3 bundle.py out/bundle.luau S=/home/user/-/src/ReplicatedStorage/GwangalliDecorShared >/dev/null || exit 1
cd tests && ../../../luau/luau export.luau -a "$1" ${2:-4} ${3:-14} > ../out/export.txt 2>&1
grep -v "^JSON " ../out/export.txt | head -20
grep "^JSON " ../out/export.txt | sed 's/^JSON //' > ../out/scene_$$.json
cd $D && flock /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/.studio.lock timeout 600 node render.js out/scene_$$.json shots/$(echo "$1" | cut -c1-30 | tr ',' '_') 2>&1 | tail -5
rm -f out/scene_$$.json
