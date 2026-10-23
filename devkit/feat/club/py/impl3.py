exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/py/impl1.py').read().split("for c in kids[main]:")[0])
def find(root,name):
    st=[root]
    while st:
        x=st.pop()
        for c in kids.get(x,[]): st.append(c)
        if G.inst[x]['name']==name: return x
for nm in ['DJBooth','TrussRig','Effects','Lasers','LEDDanceFloor','StageFX']:
    r=find(main,nm)
    seen={}
    st=[r]
    while st:
        x=st.pop()
        for c in kids.get(x,[]): st.append(c)
        i=G.inst[x]
        if i['cls'] in ('Part','MeshPart','WedgePart'):
            seen.setdefault(i['name'],[]).append((pos(i),size(i)))
    print('==',nm)
    for k,v in seen.items():
        print('  ',k,len(v),v[0], v[-1] if len(v)>1 else '')
r=find(main,'ServiceStation')
for nm in ['SideLEDFrame']:
    x=find(r,nm); i=G.inst[x]; print(nm, pv(i,'CFrame'), size(i))
x=find(club,'Show_LEDWall'); i=G.inst[x]; print('anchor', pv(i,'CFrame'), size(i))
