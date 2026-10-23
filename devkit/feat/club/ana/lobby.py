exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import math
def pv(i,k):
    v=i['props'].get(k)
    return G.val(v[1]) if v else None
def pos(i):
    cf=pv(i,'CFrame')
    if cf and cf[0]=='CF': return tuple(round(x,1) for x in cf[1:4])
    return None
def size(i):
    s=pv(i,'size') or pv(i,'Size')
    if s and s[0]=='V3': return tuple(round(x,2) for x in s[1:4])
    return None
import sys
target=sys.argv[1]
for i in G.inst[1:]:
    p=path(i['id'])
    if target in p and i['cls'] in ('Part','MeshPart','WedgePart','UnionOperation'):
        s=size(i); q=pos(i)
        if s and max(s)>=4:
            print(p.split('CLUB OCEAN 광안/')[-1][:70], q, s)
