exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import collections
def desc(iid):
    for c in kids.get(iid,[]):
        yield c
        yield from desc(c)
PARTS=('Part','MeshPart','WedgePart','UnionOperation','Seat','TrussPart','CornerWedgePart')
tpl=[i for i in G.inst[1:] if path(i['id']).startswith('DataModel/ServerStorage/GwangalliHomes/HomeUnit_') and path(i['id']).count('/')==3]
for t in tpl:
    if t['name'] not in ('HomeUnit_oneroom','HomeUnit_officetel','HomeUnit_penthouse'): continue
    print('==',t['name'])
    for top in kids[t['id']]:
        ti=G.inst[top]
        if ti['name'] not in ('Shell','Fixtures'): continue
        names=collections.Counter(); surf=collections.Counter()
        for d in desc(top):
            i=G.inst[d]
            if i['cls'] in PARTS:
                cc=G.prop(i,'CanCollide'); 
                a={k:G.val(v) for k,v in i['attrs'].items()}
                names[i['name']+('' if cc in (None,True) else '-')]+=1
                if a.get('Surface'): surf[(i['name'],a.get('Surface'))]+=1
            elif i['cls']=='Model': names['M:'+i['name']]+=1
        print(' ',ti['name'],dict(names.most_common(60)))
        print('  surf',dict(surf))
