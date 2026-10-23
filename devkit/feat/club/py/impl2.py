exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/py/impl1.py').read().split("for c in kids[main]:")[0])
si=[c for c in kids[club] if G.inst[c]['name']=='MainRoom'][0]
inst=[c for c in kids[si] if G.inst[c]['name']=='ShowInstallation'][0]
for c in kids[inst]:
    i=G.inst[c]; print('SI', i['cls'], i['name'], bbox(c))
# parts near the LED wall plane (x > -82) outside the LED z range, inside main room
print('--- near LED wall flanks')
st=[club]
while st:
    x=st.pop()
    for c in kids.get(x,[]): st.append(c)
    i=G.inst[x]; p=pos(i); s=size(i)
    if p and s and i['cls'] in ('Part','MeshPart','WedgePart','UnionOperation') and p[0]>-82 and p[0]<-60 and (320<p[2]<346 or 402<p[2]<432) and 8<p[1]<34 and max(s)>2:
        print(' ', path(x)[-70:], p, s, pv(i,'Transparency'))
