#!/bin/bash
# mk.sh: bundle the interior folder for the offline sim, with os.clock() mapped to the fake clock
cd /tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/hospital/sim
python3 -I ../../../bprev/gen.py /home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliBuildingInterior out/mods_t.luau >/dev/null || exit 1
python3 - <<'PY'
p='out/mods_t.luau'
s=open(p).read()
s=s.replace('os.clock()','__osclock()')
i=s.index('\n', s.index('local E = R.env'))
s=s[:i+1]+'local __osclock = function() return R.clock end\n'+s[i+1:]
open(p,'w').write(s)
PY
cp out/mods_t.luau out/mods_hosp.luau
