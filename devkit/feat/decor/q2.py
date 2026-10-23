exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
from collections import Counter
c=Counter()
pre='DataModel/ServerStorage/GwangalliHomes/HomeUnit_oneroom/'
for i in G.inst[1:]:
    p=path(i['id'])
    if p.startswith(pre) and i['cls'] in ('Part','MeshPart','WedgePart','UnionOperation','Seat','CornerWedgePart','TrussPart'):
        top=p[len(pre):].split('/')[0]
        cc=G.prop(i,'CanCollide'); cq=G.prop(i,'CanQuery'); ct=G.prop(i,'CanTouch')
        c[(top, G.val(cc[1]) if isinstance(cc,tuple) else cc, G.val(cq[1]) if isinstance(cq,tuple) else cq)]+=1
for k,v in sorted(c.items(), key=lambda x:str(x)): print(k,v)
i=[x for x in G.inst[1:] if path(x['id'])==pre+'Shell'][0]
f=[x for x in kids[i['id']]][0]
print(G.inst[f]['name'], {k:v for k,v in G.inst[f]['props'].items() if k in ('CanCollide','CanQuery','CanTouch','Anchored','Material','Transparency')})
