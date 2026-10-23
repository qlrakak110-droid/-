exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/py/survey.py').read().split("big=[]")[0])
import math
def aabb(i):
    c=cf(i); s=size(i)
    if not c or not s: return None
    p=c[1:4]; R=c[4]
    h=[s[0]/2,s[1]/2,s[2]/2]
    ext=[abs(R[0])*h[0]+abs(R[1])*h[1]+abs(R[2])*h[2], abs(R[3])*h[0]+abs(R[4])*h[1]+abs(R[5])*h[2], abs(R[6])*h[0]+abs(R[7])*h[1]+abs(R[8])*h[2]]
    return [p[k]-ext[k] for k in range(3)],[p[k]+ext[k] for k in range(3)]
rows=[]
for x in walk(club):
    i=G.inst[x]
    if i['cls'] in ('Part','MeshPart','WedgePart','UnionOperation','TrussPart','CornerWedgePart'):
        bb=aabb(i)
        if not bb: continue
        lo,hi=bb
        # south wall band z 340..347, height 13..31, x -160..-75
        if hi[2]>339 and lo[2]<347 and hi[1]>13 and lo[1]<31 and hi[0]>-160 and lo[0]<-75:
            rows.append((round(lo[0],1),round(hi[0],1),round(lo[1],1),round(hi[1],1),round(lo[2],1),round(hi[2],1),path(x)[len(path(club)):][-60:]))
for r in sorted(rows): print(r)
