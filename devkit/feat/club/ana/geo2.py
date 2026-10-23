exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
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
side=[i for i in G.inst[1:] if 'ClubLight' in i['tags'] and i['attrs'].get('Screen') and G.val(i['attrs']['Screen'])=='Side']
ps=[pos(x) for x in side]
print('side panels',len(side), 'x',min(p[0] for p in ps),max(p[0] for p in ps),'y',min(p[1] for p in ps),max(p[1] for p in ps),'z',min(p[2] for p in ps),max(p[2] for p in ps), size(side[0]), path(side[0]['id'])[-70:], {a:G.val(b) for a,b in side[0]['attrs'].items()})
rows=set(G.val(x['attrs']['Row']) for x in side); cols=set(G.val(x['attrs']['Col']) for x in side)
print(' rows',sorted(rows),' cols',sorted(cols))
names=['LEDWallFrame','DJDesk','BoothPlatform','DJ_009','MC_010','BoothMonitor','TrussPart','MirrorBall','LEDScreen','ScreenHousing','SideLEDFrame','StepAndRepeat','BackWallLining','MezzSlab','BoothGlassRail','CypherRing','Room2Stage','DeskLogo']
for i in G.inst[1:]:
    if i['name'] in names and 'CLUB OCEAN' in path(i['id']):
        print(i['cls'], path(i['id'])[-75:], pos(i), size(i))
