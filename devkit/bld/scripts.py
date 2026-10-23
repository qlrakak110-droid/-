exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
from collections import Counter
c=Counter(i['cls'] for i in G.inst[1:])
print(len(G.inst), c.most_common(40))
n=0
for i in G.inst[1:]:
    if i['cls'] in ('Script','LocalScript','ModuleScript'):
        n+=1
        if n<80: print(i['cls'], path(i['id']), list(i['props'].keys())[:10])
print('scripts', n)
roots=[(G.inst[c]['cls'],G.inst[c]['name']) for c in kids.get(0,[])]
print(roots)
