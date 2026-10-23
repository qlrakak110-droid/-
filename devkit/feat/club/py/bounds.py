exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/py/south.py').read().split("rows=[]")[0])
import sys
for name in sys.argv[1:]:
    roots=[c for c in walk(club) if G.inst[c]['name']==name]
    for root in roots[:3]:
        lo=[1e9]*3; hi=[-1e9]*3; n=0
        names={}
        for x in walk(root):
            i=G.inst[x]
            if i['cls'] in ('Part','MeshPart','WedgePart','UnionOperation','TrussPart','CornerWedgePart'):
                bb=aabb(i)
                if not bb: continue
                n+=1; names[i['name']]=names.get(i['name'],0)+1
                for k in range(3): lo[k]=min(lo[k],bb[0][k]); hi[k]=max(hi[k],bb[1][k])
        print(name, path(root)[len(path(club)):], n, [round(v,1) for v in lo], [round(v,1) for v in hi], dict(list(names.items())[:12]))
