import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gwpb import GWPB
g = GWPB(sys.argv[1]); out = sys.argv[2]
n = 0; idx = []
for i in g.inst[1:]:
    if i['cls'] in ('Script','LocalScript','ModuleScript'):
        src = g.prop(i, 'Source')
        if not isinstance(src, str): continue
        p = g.path(i['id']).replace(':','_')
        fp = os.path.join(out, p + '.' + i['cls'] + '.luau')
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        if os.path.exists(fp): fp = fp[:-5] + '.%d.luau' % i['id']
        open(fp,'w',encoding='utf-8').write(src); n += 1
        idx.append((i['id'], i['cls'], p, len(src)))
json.dump(idx, open(os.path.join(out, '_index.json'),'w'), ensure_ascii=False, indent=0)
print('instances', len(g.inst)-1, 'scripts', n)
