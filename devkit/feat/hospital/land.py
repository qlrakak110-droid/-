exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
X=(0.999465,0,0.032713); Z=(-0.032713,0,0.999465)
def L(p):
    d=(p[0]+515,p[1]-6.9,p[2]-300)
    return (d[0]*X[0]+d[2]*X[2], d[1], d[0]*Z[0]+d[2]*Z[2])
def lbox(i):
    cf=G.prop(i,'CFrame'); sz=G.prop(i,'Size')
    if not cf or not sz: return None
    R=cf[4]; s=(sz[1],sz[2],sz[3])
    hx=abs(R[0])*s[0]/2+abs(R[1])*s[1]/2+abs(R[2])*s[2]/2
    hy=abs(R[3])*s[0]/2+abs(R[4])*s[1]/2+abs(R[5])*s[2]/2
    hz=abs(R[6])*s[0]/2+abs(R[7])*s[1]/2+abs(R[8])*s[2]/2
    c=L((cf[1],cf[2],cf[3]))
    return (c[0]-hx,c[1]-hy,c[2]-hz,c[0]+hx,c[1]+hy,c[2]+hz)
def walk(iid, pre=''):
    for c in kids.get(iid,[]):
        ci=G.inst[c]
        b=lbox(ci)
        if b: print(pre+'%-28s (%.2f,%.2f,%.2f)..(%.2f,%.2f,%.2f) cc=%s'%(ci['name'],*b,G.prop(ci,'CanCollide')))
        walk(c, pre+'  ')
for i in G.inst[1:]:
    if i['name']=='LandingHall': walk(i['id'])
# floor2 pieces
for i in G.inst[1:]:
    if i['name'] in ('Floor2','Floor') and G.inst[i['parent']]['name'] in ('2F','1F'):
        print(G.inst[i['parent']]['name'], i['name'], ['%.2f'%v for v in lbox(i)])
