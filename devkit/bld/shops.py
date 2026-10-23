exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import sys; sys.setrecursionlimit(100000)
from collections import Counter
def child(iid, nm):
    for c in kids.get(iid,[]):
        if G.inst[c]['name']==nm: return c
def desc(iid):
    out=[]
    st=[iid]
    while st:
        x=st.pop()
        for c in kids.get(x,[]):
            out.append(c); st.append(c)
    return out
street=[];venue=[];gw=[]
for i in G.inst[1:]:
    if i['cls']=='Model':
        if child(i['id'],'Interior') and child(i['id'],'ShopFloor'):
            (gw if 'GwShop' in i['tags'] else street).append(i['id'])
        elif child(i['id'],'Gondola_1') or child(i['id'],'OpenChiller'):
            venue.append(i['id'])
print('street', len(street), 'gwshop', len(gw), 'venue', len(venue))
pc=Counter()
for s in street+gw+venue:
    i=G.inst[s]
    sf=child(s,'ShopFloor')
    pos=None
    if sf:
        cf=G.prop(G.inst[sf],'CFrame'); sz=G.prop(G.inst[sf],'Size')
        pos='(%.0f,%.1f,%.0f) sz(%.0f,%.1f,%.0f)'%(cf[1],cf[2],cf[3],sz[1],sz[2],sz[3]) if cf and sz else None
    d=desc(s)
    nparts=sum(1 for x in d if G.inst[x]['cls'] in ('Part','WedgePart','Seat','CornerWedgePart','TrussPart','MeshPart'))
    signs=[G.inst[x]['name'][5:] for x in d if G.inst[x]['name'].startswith('Sign_')][:3]
    attrs={k:G.val(v) for k,v in i['attrs'].items()}
    intr=child(s,'Interior')
    ni=len(desc(intr)) if intr else 0
    print(path(s).replace('DataModel/Workspace/',''), pos, 'parts',nparts,'interiorDesc',ni, signs, attrs if attrs else '', i['tags'])
