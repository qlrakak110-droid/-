import sys, pickle, time
sys.path.insert(0,'/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/tools')
from gwpb import GWPB
t=time.time()
G=GWPB('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7place/place.bin')
print('load',time.time()-t, len(G.inst))
seen={}
for i in G.inst[1:]:
    c=i['cls']
    if c not in seen: seen[c]={}
    for k,v in i['props'].items():
        if k not in seen[c]:
            seen[c][k]=G.val(v[1])
from collections import Counter
cc=Counter(i['cls'] for i in G.inst[1:])
for c,n in cc.most_common(60):
    print(c,n, {k:(str(v)[:40]) for k,v in seen[c].items()})
