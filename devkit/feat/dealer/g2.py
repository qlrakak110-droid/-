import json,collections,math
S='/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
d=json.load(open(S+'/bld/hg/dump.json'))['garage']
byid={x['id']:x for x in d}
PART=('Part','MeshPart','WedgePart','UnionOperation','TrussPart','CornerWedgePart','Seat','VehicleSeat','SpawnLocation')
def corners(x):
    p=x['pos']; s=x['size']; r=x.get('rot') or [1,0,0,0,1,0,0,0,1]
    R=[[r[0],r[1],r[2]],[r[3],r[4],r[5]],[r[6],r[7],r[8]]]
    out=[]
    for sx in (-1,1):
      for sy in (-1,1):
        for sz in (-1,1):
            l=(sx*s[0]/2,sy*s[1]/2,sz*s[2]/2)
            w=[p[i]+R[i][0]*l[0]+R[i][1]*l[1]+R[i][2]*l[2] for i in range(3)]
            out.append(w)
    return out
X0,X1,Z0,Z1=-602,-527,418,486
grid=collections.defaultdict(set)
for x in d:
    if x['cls'] not in PART or 'pos' not in x: continue
    c=corners(x); ys=[q[1] for q in c]
    if max(ys)<=7.3 or min(ys)>15: continue  # floor-level or high
    tr = None
    # transparency unknown in dump? check
    xs=[q[0] for q in c]; zs=[q[2] for q in c]
    if max(xs)<X0 or min(xs)>X1 or max(zs)<Z0 or min(zs)>Z1: continue
    if (max(xs)-min(xs))>60 and (max(zs)-min(zs))>40: continue
    for gx in range(int(math.floor(min(xs))), int(math.ceil(max(xs)))):
        for gz in range(int(math.floor(min(zs))), int(math.ceil(max(zs)))):
            grid[(gx,gz)].add(x['name'])
# turntable sweeps
tts=[(-589.37,459.22),(-565.38,460.01),(-541.39,460.8),(-588.68,438.23),(-564.69,439.02),(-540.7,439.81)]
rows=[]
for gz in range(Z1,Z0-1,-1):
    line=''
    for gx in range(X0,X1+1):
        ch='.'
        if any(math.hypot(gx+0.5-a,gz+0.5-b)<8.75 for a,b in tts): ch='o'
        if (gx,gz) in grid: ch='#'
        line+=ch
    rows.append('%4d %s'%(gz,line))
print('     '+''.join(str(abs(x)%10) for x in range(X0,X1+1)))
print('\n'.join(rows))
print(sorted(set(n for v in grid.values() for n in v))[:200])
print(list(d[5].keys()))
