import sys
sys.path.insert(0, '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/tools')
from gwpb import GWPB
G = GWPB('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7place/place.bin')
byid={i['id']:i for i in G.inst[1:]}
def anc(i):
    out=[]
    p=i['parent']
    while p in byid:
        out.append(byid[p]['name']); p=byid[p]['parent']
    return out
for i in G.inst[1:]:
    if i['cls']=='ProximityPrompt':
        a=anc(i)
        if '광안 오토 정비소 & 중고차' in a:
            props={}
            for k in i['props']:
                try: props[k]=G.prop(i,k)
                except Exception as e: props[k]='ERR'
            print(a[0], {k:v for k,v in props.items() if k in ('ActionText','ObjectText','MaxActivationDistance','KeyboardKeyCode','HoldDuration','RequiresLineOfSight','Exclusivity','GamepadKeyCode','UIOffset')})
