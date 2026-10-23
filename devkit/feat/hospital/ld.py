import json, math
S='/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
D=json.load(open(S+'/bld/hg/dump.json'))['hospital']
byid={r['id']:r for r in D}
def wAABB(r):
    p=r['pos']; R=r['rot']; s=r['size']
    h=[s[0]/2,s[1]/2,s[2]/2]
    ex=[abs(R[0])*h[0]+abs(R[1])*h[1]+abs(R[2])*h[2], abs(R[3])*h[0]+abs(R[4])*h[1]+abs(R[5])*h[2], abs(R[6])*h[0]+abs(R[7])*h[1]+abs(R[8])*h[2]]
    return [p[i]-ex[i] for i in range(3)],[p[i]+ex[i] for i in range(3)]
def parts():
    return [r for r in D if 'size' in r and 'pos' in r and r['cls'] in ('Part','WedgePart','MeshPart','Seat','UnionOperation','TrussPart','CornerWedgePart','VehicleSeat','SpawnLocation')]
