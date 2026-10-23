#!/bin/bash
# ffrv.sh key... : render ffrv cams for each fixture, build sheet shots/ffrv_<key>.jpg
S=/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev
cd $S
for k in "$@"; do
  names=$(python3 -c "import json;print(','.join(c['name'] for c in json.load(open('cams/ffrv_$k.json'))))")
  ONLY=T_fastfood ./run.sh ff_$k --lcams cams/ffrv_$k.json --q ultra > out/ffrv_$k.log 2>&1
  python3 sheet.py $S/shots/ffrv_$k.jpg ffrv_$k $(for n in ${names//,/ }; do echo "$n|shots/ff_$k/$n.png"; done) >/dev/null
  echo "$k $(grep '^#K' out/ffrv_$k.log)"
done
