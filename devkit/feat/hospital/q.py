import pickle, sys
exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
rows=pickle.load(open('aabbs.pkl','rb'))
t=G.inst[3]
print('terrain props', t.get('props').keys() if isinstance(t.get('props'),dict) else t.keys())
for k in ['SmoothGrid','MaterialColors','PhysicsGrid']:
    try:
        v=G.prop(t,k); print(k, type(v), (len(v) if hasattr(v,'__len__') else v))
    except Exception as e: print(k,'err',e)
def q(mn,mx,lim=40):
    out=[]
    for iid,a,b in rows:
        if a[0]<mx[0] and b[0]>mn[0] and a[1]<mx[1] and b[1]>mn[1] and a[2]<mx[2] and b[2]>mn[2]:
            out.append((iid,a,b))
    return out
import json
box=json.loads(sys.argv[1])
r=q(box[0],box[1])
print(len(r))
for iid,a,b in r[:int(sys.argv[2]) if len(sys.argv)>2 else 40]:
    print(path(iid)[-90:], [round(x,1) for x in a],[round(x,1) for x in b])
