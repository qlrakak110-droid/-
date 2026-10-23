import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gwpb import GWPB
g = GWPB(sys.argv[1]); cid = int(sys.argv[2])
kids = {}
for i in g.inst[1:]:
    kids.setdefault(i['parent'], []).append(i['id'])
root = g.inst[cid]
print('MODEL', g.path(cid), 'attrs', {k: g.val(v) for k, v in root['attrs'].items()})
ref = None
def walk(iid, d):
    global ref
    for c in kids.get(iid, []):
        i = g.inst[c]
        cf = g.prop(i, 'CFrame'); sz = g.prop(i, 'Size'); tr = g.prop(i, 'Transparency'); mat = g.prop(i, 'Material'); col = g.prop(i, 'Color')
        if i['name'] == 'Underbody' and cf: ref = cf
        pos = ''
        if cf and ref:
            dx, dy, dz = cf[1]-ref[1], cf[2]-ref[2], cf[3]-ref[3]
            m = ref[4]
            # local = R^T * d  (R columns = right, up, back)
            lx = m[0]*dx + m[3]*dy + m[6]*dz; ly = m[1]*dx + m[4]*dy + m[7]*dz; lz = m[2]*dx + m[5]*dy + m[8]*dz
            pos = 'local(%.2f,%.2f,%.2f)' % (lx, ly, lz)
        s = ('size(%.2f,%.2f,%.2f)' % sz[1:]) if sz and sz[0] == 'V3' else ''
        extra = []
        if tr: extra.append('T=%.2f' % tr)
        if mat: extra.append(str(mat[1:]) if isinstance(mat, tuple) else str(mat))
        if col and col[0] == 'C3': extra.append('rgb(%d,%d,%d)' % tuple(int(x*255) for x in col[1:]))
        at = {k: g.val(v) for k, v in i['attrs'].items()}
        print('  '*d + '%s [%s] %s %s %s %s' % (i['name'], i['cls'], s, pos, ' '.join(extra), at if at else ''))
        walk(c, d+1)
# find underbody first
for c in kids.get(cid, []):
    pass
def findref(iid):
    global ref
    for c in kids.get(iid, []):
        i = g.inst[c]
        if i['name'] == 'Underbody': ref = g.prop(i, 'CFrame'); return True
        if findref(c): return True
findref(cid)
walk(cid, 1)
