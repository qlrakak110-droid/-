exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
from collections import Counter
c=Counter(); ex={}
for i in G.inst[1:]:
    if i['cls']=='Model' and 'ModelStreamingMode' in i['props']:
        v=G.val(i['props']['ModelStreamingMode'][1])
        c[str(v)]+=1
        ex.setdefault(str(v),[]).append(path(i['id']).replace('DataModel/Workspace/Gwangalli/','')[:90])
print(c)
for k,v in ex.items():
    print(k, len(v), v[:12])
# sample a shop model's props
for i in G.inst[1:]:
    if i['name']=='남천 해장국' and i['cls']=='Model':
        print({k:G.val(v[1]) for k,v in i['props'].items()})
        break
