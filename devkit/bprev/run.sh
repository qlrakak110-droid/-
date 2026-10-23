#!/bin/bash
# run.sh <key> [--night] [--only a,b] : bundle modules, run the sim, render previews -> shots/<key>/*.png + shots/<key>.jpg sheet
S=/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev
SRC=${SRC:-/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior}
KEY=$1; shift
cd $S
ONLY="$ONLY" python3 -I gen.py "$SRC" out/mods_$KEY.luau >/dev/null || exit 1
sed "s#require(\"./out/mods\")#require(\"./out/mods_$KEY\")#" sim.luau > out/sim_$KEY.luau
sed -i 's#require("./lib/rbx")#require("../lib/rbx")#; s#require("./fx/"#require("../fx/"#; s#require("./out/mods_#require("./mods_#' out/sim_$KEY.luau
../luau/luau out/sim_$KEY.luau -a $KEY > out/$KEY.simout 2>&1
grep "^#" out/$KEY.simout | head -60
grep -v "^#\|^JSON " out/$KEY.simout | head -20
if ! grep -q "^JSON " out/$KEY.simout; then echo "NO JSON (sim failed)"; exit 1; fi
grep "^JSON " out/$KEY.simout | sed 's/^JSON //' > out/$KEY.gen.json
OUT=$S/shots/$KEY
node preview.js $KEY --gen out/$KEY.gen.json --out $OUT "$@" 2>&1 | grep -v "^shot\|^ms"
python3 sheet.py $S/shots/$KEY.jpg "$KEY" $(for f in $OUT/*.png; do n=$(basename $f .png); echo "$n|$f"; done) >/dev/null
echo "sheet: $S/shots/$KEY.jpg"
