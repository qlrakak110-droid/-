exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import math
a=math.radians(-1.8747); ca,sa=math.cos(a),math.sin(a)
# HF: origin (-515,6.9,300), X=(ca,0,-sa)?? use XVector=(0.999465,0,0.032713), Z=(-0.032713,0,0.999465)
X=(0.999465,0,0.032713); Z=(-0.032713,0,0.999465)
def L(p):
    d=(p[0]+515,p[1]-6.9,p[2]-300)
    return (d[0]*X[0]+d[2]*X[2], d[1], d[0]*Z[0]+d[2]*Z[2])
def box(i):
    cf=G.prop(i,'CFrame'); sz=G.prop(i,'Size')
    R=cf[4]; c=(cf[1],cf[2],cf[3]); s=(sz[1],sz[2],sz[3])
    # world half extents
    hx=abs(R[0])*s[0]/2+abs(R[1])*s[1]/2+abs(R[2])*s[2]/2
    hy=abs(R[3])*s[0]/2+abs(R[4])*s[1]/2+abs(R[5])*s[2]/2
    hz=abs(R[6])*s[0]/2+abs(R[7])*s[1]/2+abs(R[8])*s[2]/2
    lc=L(c)
    # local extents approx (rotation small): swap
    return lc, s
names=['Door_진료실 1 · 내과','Door_주사실 · 처치실','Door_입원실 201','Door_입원실 202','Door_건강검진센터','Door_STAFF ONLY','Door_창고','Door_남자 화장실','Door_여자 화장실']
for i in G.inst[1:]:
    if i['name'] in names and i['cls']=='Model':
        print(i['name'])
        for c in kids.get(i['id'],[]):
            ci=G.inst[c]
            lc,s=box(ci)
            print('   %-22s c=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f) cc=%s t=%s'%(ci['name'],lc[0],lc[1],lc[2],s[0],s[1],s[2],G.prop(ci,'CanCollide'),G.prop(ci,'Transparency')))
