import sys
sys.path.insert(0, '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/tools')
from gwpb import GWPB
G = GWPB('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7place/place.bin')
kids = {}
for i in G.inst[1:]:
    kids.setdefault(i['parent'], []).append(i['id'])
def path(iid):
    out=[]
    while iid:
        out.append(G.inst[iid]['name']); iid=G.inst[iid]['parent']
    return '/'.join(reversed(out))
# find hospital roots
for i in G.inst[1:]:
    if i['name'] in ('광안 메디컬 의원','광안 메디컬 의원 (건물)'):
        print('ROOT', i['id'], i['cls'], path(i['id']))
        # print model-level children (non-part) and selected parts
        def walk(iid, depth):
            for c in kids.get(iid, []):
                ci = G.inst[c]
                n = ci['name']
                if ci['cls'] in ('Model','Folder') :
                    print('  '*depth + f"[{ci['cls']}] {n} ({len(kids.get(c,[]))})")
                    if depth < 3: walk(c, depth+1)
                elif any(k in n for k in ('Ground','BackWall','FireExit','PushBar','Elevator','FloorIndicator','CallButton','Sign_','RoofDoor','Penthouse','Roof','Door','Jamb','Head','Leaf','Handle','Rail','Parapet','Coping')):
                    print('  '*depth + f"{ci['cls']} {n}")
        walk(i['id'], 1)
