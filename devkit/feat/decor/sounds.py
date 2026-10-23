exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
n=0
from collections import Counter
c=Counter()
for i in G.inst[1:]:
    if i['cls']=='Sound':
        sid=G.prop(i,'SoundId')
        c[str(sid)]+=1
        n+=1
        if n<30: print(path(i['id']), sid, G.prop(i,'Looped'))
print(n)
for k,v in c.most_common(30): print(v,k)
