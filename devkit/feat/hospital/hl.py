import json, math, sys, re
S='/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
D=json.load(open(S+'/bld/hg/dump.json'))['hospital']
EX={int(k):v for k,v in json.load(open(S+'/feat/hospital/exact.json')).items()}
byid={r['id']:r for r in D}
A=math.radians(-1.8747)
# HF axes in world: X=(cos A,0,-sin A) , Z=(sin A,0,cos A)
cx,cy,cz=math.cos(A),0,-math.sin(A)
zx,zz=math.sin(A),math.cos(A)
O=(-515.0,6.9,300.0)
def toL(p):
    d=(p[0]-O[0],p[1]-O[1],p[2]-O[2])
    return (d[0]*cx+d[2]*cz, d[1], d[0]*zx+d[2]*zz)
def toW(l):
    return (O[0]+l[0]*cx+l[2]*zx, O[1]+l[1], O[2]+l[0]*cz+l[2]*zz)
def lbox(iid):
    e=EX[iid]; p=e['cf'][:3]; R=e['cf'][3:]; s=e['size']
    # local axes of part in HF: transform part axes
    axes=[(R[0],R[3],R[6]),(R[1],R[4],R[7]),(R[2],R[5],R[8])]
    def vl(v): return (v[0]*cx+v[2]*cz, v[1], v[0]*zx+v[2]*zz)
    la=[vl(a) for a in axes]
    h=[s[0]/2,s[1]/2,s[2]/2]
    ex=[sum(abs(la[k][j])*h[k] for k in range(3)) for j in range(3)]
    c=toL(p)
    return [c[j]-ex[j] for j in range(3)],[c[j]+ex[j] for j in range(3)],c
def fmt(v): return '(%s)'%','.join('%.2f'%x for x in v)
def show(filt=None, region=None, name=None, lim=400):
    n=0
    for r in D:
        if r['id'] not in EX: continue
        full=r['path']+'/'+r['name']
        if filt and not re.search(filt, full): continue
        if name and not re.search(name, r['name']): continue
        mn,mx,c=lbox(r['id'])
        if region:
            a,b=region
            if not (mn[0]<b[0] and mx[0]>a[0] and mn[1]<b[1] and mx[1]>a[1] and mn[2]<b[2] and mx[2]>a[2]): continue
        e=EX[r['id']]
        wmn=[0,0,0];
        print('%-48s L%s..%s W@%s sz%s cc=%s t=%s m=%s' % (full.replace('hospital/광안 메디컬 의원','H')[-48:], fmt(mn), fmt(mx), fmt(e['cf'][:3]), fmt(e['size']), e['cc'], e['t'], r.get('Material',[0,0,''])[2] if isinstance(r.get('Material'),list) else ''))
        n+=1
        if n>=lim: break
if __name__=="__main__" and len(sys.argv)>1:
    args=json.loads(sys.argv[1])
    show(**args)
