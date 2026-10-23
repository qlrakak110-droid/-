#!/bin/bash
S=/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev
cd $S
KEY=$1
ONLY=T_bowling python3 -I gen.py /home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior out/mods_dumpbw.luau >/dev/null || exit 1
sed 's#require("./out/mods")#require("./mods_dumpbw")#; s#require("./lib/rbx")#require("../lib/rbx")#; s#require("./fx/"#require("../fx/"#' out/dump.luau > out/dumpbw_run.luau
../luau/luau out/dumpbw_run.luau -a $KEY
