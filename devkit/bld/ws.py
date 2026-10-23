exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
dm = kids[0][0]
for c in kids[dm]:
    i=G.inst[c]; print('SVC', i['cls'], i['name'], len(kids.get(c,[])))
ws=[c for c in kids[dm] if G.inst[c]['cls']=='Workspace'][0]
def cnt(iid):
    n=1
    for c in kids.get(iid,[]): n+=cnt(c)
    return n
import sys
sys.setrecursionlimit(100000)
for c in kids[ws]:
    i=G.inst[c]; print(' WS', i['cls'], i['name'], len(kids.get(c,[])), cnt(c), {k:G.val(v) for k,v in i['attrs'].items()} if i['attrs'] else '', i['tags'])
gw=[c for c in kids[ws] if G.inst[c]['name']=='Gwangalli'][0]
for c in kids[gw]:
    i=G.inst[c]; print('  GW', i['cls'], i['name'], len(kids.get(c,[])), cnt(c), {k:G.val(v) for k,v in i['attrs'].items()} if i['attrs'] else '')
    for cc in kids.get(c,[])[:0]:
        pass
# tags
from collections import Counter
tc=Counter(t for i in G.inst[1:] for t in i['tags'])
print(tc.most_common(60))
ac=Counter(a for i in G.inst[1:] for a in i['attrs'])
print(ac.most_common(150))
