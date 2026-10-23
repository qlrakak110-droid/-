# export.py <key> (--path SUFFIX | --id IID) [--margin M]
#   fx/<key>.luau        venue subtree (sim fixture, with instance ids)
#   fx/<key>.scene.json  every part near the venue (render context) + SurfaceGuis + lights
import sys, json, re, os, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from place import load, index, aabb, BASE, SP

GUI = ('SurfaceGui', 'Frame', 'TextLabel', 'TextButton', 'UIStroke', 'UICorner', 'UIGradient', 'ImageLabel')
LIGHT = ('PointLight', 'SpotLight', 'SurfaceLight')

def enum(v):
    return v[2] if v and v[0] == 'Enum' else None

def col(v):
    return [round(v[1], 4), round(v[2], 4), round(v[3], 4)] if v and v[0] == 'C3' else None

def cf12(v):
    if not v: return [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]
    return [round(x, 5) for x in [v[1], v[2], v[3]] + list(v[4])]

def partrec(G, iid):
    i = G.inst[iid]
    cf = G.prop(i, 'CFrame'); sz = G.prop(i, 'Size')
    r = dict(id=iid, cls=i['cls'], name=i['name'], cf=cf12(cf), size=[round(sz[1], 4), round(sz[2], 4), round(sz[3], 4)] if sz else [4, 1, 2])
    c = col(G.prop(i, 'Color')); r['col'] = c or [0.64, 0.64, 0.65]
    r['mat'] = enum(G.prop(i, 'Material')) or 'Plastic'
    t = G.prop(i, 'Transparency'); r['t'] = round(t, 3) if t else 0
    rf = G.prop(i, 'Reflectance'); r['rf'] = round(rf, 3) if rf else 0
    sh = enum(G.prop(i, 'Shape'))
    if sh and sh != 'Block': r['shape'] = sh
    for k in G.kids.get(iid, []):
        ki = G.inst[k]
        if ki['cls'] == 'SpecialMesh':
            mt = enum(G.prop(ki, 'MeshType')) or 'Head'
            sc = G.prop(ki, 'Scale')
            r['mesh'] = dict(type=mt, scale=[sc[1], sc[2], sc[3]] if sc else [1, 1, 1])
    return r

def ud2(v, d):
    return [v[1], v[2], v[3], v[4]] if v and v[0] == 'UD2' else d

def guirec(G, iid):
    i = G.inst[iid]; cls = i['cls']; P = lambda n, d=None: (G.prop(i, n) if G.prop(i, n) is not None else d)
    r = dict(cls=cls, name=i['name'])
    if cls == 'SurfaceGui':
        r['face'] = enum(P('Face')) or 'Front'
        r['ppx'] = P('PixelsPerStud', 50)
        r['mode'] = enum(P('SizingMode')) or 'FixedSize'
        cs = P('CanvasSize'); r['canvas'] = [cs[1], cs[2]] if cs and cs[0] == 'V2' else [800, 600]
        r['bright'] = P('Brightness', 1); r['lightInf'] = P('LightInfluence', 1)
        ad = P('Adornee'); r['adornee'] = ad[1] if ad and ad[0] == 'Ref' else None
    elif cls in ('Frame', 'TextLabel', 'TextButton', 'ImageLabel'):
        dsz = [0, 100, 0, 100] if cls == 'Frame' else [0, 200, 0, 50]
        r['size'] = ud2(P('Size'), dsz); r['pos'] = ud2(P('Position'), [0, 0, 0, 0])
        ap = P('AnchorPoint'); r['anchor'] = [ap[1], ap[2]] if ap and ap[0] == 'V2' else [0, 0]
        r['bg'] = col(P('BackgroundColor3')) or [0.64, 0.64, 0.65]; r['bgT'] = P('BackgroundTransparency', 0)
        r['rot'] = P('Rotation', 0); r['vis'] = P('Visible', True); r['z'] = P('ZIndex', 1)
        if cls != 'Frame' and cls != 'ImageLabel':
            r['text'] = P('Text', 'Label'); r['tc'] = col(P('TextColor3')) or [0.106, 0.165, 0.208]
            r['scaled'] = P('TextScaled', False); r['ts'] = P('TextSize', 14)
            r['xa'] = enum(P('TextXAlignment')) or 'Center'; r['ya'] = enum(P('TextYAlignment')) or 'Center'
            r['tt'] = P('TextTransparency', 0); r['st'] = P('TextStrokeTransparency', 1); r['sc'] = col(P('TextStrokeColor3')) or [0, 0, 0]
            ff = P('FontFace'); r['bold'] = bool(ff and ff[0] == 'Font' and ff[2] >= 600)
            r['wrap'] = P('TextWrapped', False)
    elif cls == 'UIStroke':
        r['c'] = col(P('Color')) or [0, 0, 0]; r['th'] = P('Thickness', 1); r['tr'] = P('Transparency', 0)
        r['mode'] = enum(P('ApplyStrokeMode')) or 'Contextual'
    elif cls == 'UICorner':
        cr = P('CornerRadius'); r['r'] = [cr[1], cr[2]] if cr and cr[0] == 'UD' else [0, 8]
    elif cls == 'UIGradient':
        cs = P('Color'); r['cs'] = cs[1] if cs and cs[0] == 'CS' else None; r['rot'] = P('Rotation', 0)
    kids = [guirec(G, k) for k in G.kids.get(iid, []) if G.inst[k]['cls'] in GUI]
    if kids: r['kids'] = kids
    return r

def lightrec(G, iid):
    i = G.inst[iid]; P = lambda n, d=None: (G.prop(i, n) if G.prop(i, n) is not None else d)
    return dict(cls=i['cls'], part=i['parent'], c=col(P('Color')) or [1, 1, 1], b=P('Brightness', 1), range=P('Range', 8),
                angle=P('Angle', 90), face=enum(P('Face')) or 'Front', on=P('Enabled', True), shadows=P('Shadows', False))

def lua(v, ind=''):
    if v is None: return 'nil'
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, (int, float)): return repr(round(v, 5)) if isinstance(v, float) else str(v)
    if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
    if isinstance(v, tuple):
        if v[0] == 'V3': return 'Vector3.new(%r,%r,%r)' % (v[1], v[2], v[3])
        if v[0] == 'C3': return 'Color3.new(%r,%r,%r)' % (v[1], v[2], v[3])
        if v[0] == 'CF': return 'CFrame.new(%s)' % ','.join(repr(x) for x in [v[1], v[2], v[3]] + list(v[4]))
        if v[0] == 'Enum': return json.dumps('%s.%s' % (v[1], v[2]))
        return 'nil'
    if isinstance(v, list): return '{' + ','.join(lua(x) for x in v) + '}'
    if isinstance(v, dict): return '{' + ','.join('[%s]=%s' % (json.dumps(k, ensure_ascii=False), lua(x)) for k, x in v.items()) + '}'
    return 'nil'

def fixture(G, iid):
    i = G.inst[iid]
    n = dict(id=iid, cls=i['cls'], name=i['name'])
    if i['cls'] in BASE:
        r = partrec(G, iid)
        for k in ('cf', 'size', 'col', 'mat', 't', 'rf', 'shape'):
            if k in r: n[k] = r[k]
        cc = G.prop(i, 'CanCollide'); n['cc'] = bool(cc) if cc is not None else True
    elif i['cls'] == 'SpecialMesh':
        mt = enum(G.prop(i, 'MeshType')); sc = G.prop(i, 'Scale')
        n['meshType'] = mt or 'Head'; n['scale'] = [sc[1], sc[2], sc[3]] if sc else [1, 1, 1]
    elif i['cls'] in ('TextLabel',):
        n['text'] = G.prop(i, 'Text') or ''
    elif i['cls'] in LIGHT:
        n['on'] = G.prop(i, 'Enabled') if G.prop(i, 'Enabled') is not None else True
    elif i['cls'] in ('Attachment',):
        n['cf'] = cf12(G.prop(i, 'CFrame'))
    a = {k: G.val(v) for k, v in i['attrs'].items()}
    if a: n['attrs'] = a
    if i['tags']: n['tags'] = i['tags']
    ks = [fixture(G, k) for k in G.kids.get(iid, [])]
    if ks: n['kids'] = ks
    return n

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('key'); ap.add_argument('--path'); ap.add_argument('--id', type=int); ap.add_argument('--margin', type=float, default=14)
    ap.add_argument('--batch', help='file with lines: key<TAB>path-suffix')
    a = ap.parse_args()
    G = load()
    if a.batch:
        for line in open(a.batch, encoding='utf-8'):
            line = line.rstrip('\n')
            if not line.strip(): continue
            k, pth = line.split('\t')
            a.key, a.path, a.id = k, pth, None
            try: one(G, a)
            except SystemExit as e: print(k, e)
        return
    one(G, a)

def one(G, a):
    if a.id: vid = a.id
    else:
        c = [i['id'] for i in G.inst[1:] if i['cls'] in ('Model', 'Folder') and G.path(i['id']).endswith(a.path)]
        if not c: raise SystemExit('no venue ' + a.path)
        def shopish(x):
            if G.child(x, 'ShopFloor') and G.child(x, 'Interior'): return 0
            if any(G.inst[d]['name'] == 'ShopBounds' for d in G.desc(x)): return 1
            return 2
        c.sort(key=shopish)
        vid = c[0]
    ids = [vid] + G.desc(vid)
    box = None
    for x in ids:
        i = G.inst[x]
        if i['cls'] in BASE:
            cf = G.prop(i, 'CFrame'); sz = G.prop(i, 'Size')
            if cf and sz:
                b = aabb(cf, sz)
                if max(b[3] - b[0], b[5] - b[2]) > 400: continue  # ground slabs etc.
                box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), min(box[2], b[2]), max(box[3], b[3]), max(box[4], b[4]), max(box[5], b[5]))
    m = a.margin
    q = (box[0] - m, box[1] - 4, box[2] - m, box[3] + m, box[4] + 6, box[5] + m)
    near = [r[0] for r in index(G) if r[1] <= q[3] and r[4] >= q[0] and r[2] <= q[4] and r[5] >= q[1] and r[3] <= q[5] and r[6] >= q[2]]
    nearset = set(near)
    parts = [partrec(G, x) for x in near]
    guis, lights = [], []
    for x in near:
        for k in G.kids.get(x, []):
            ki = G.inst[k]
            if ki['cls'] == 'SurfaceGui':
                g = guirec(G, k); g['part'] = x; guis.append(g)
            elif ki['cls'] in LIGHT:
                lights.append(lightrec(G, k))
    # adorned guis living elsewhere
    for i in G.inst[1:]:
        if i['cls'] == 'SurfaceGui' and i['parent'] not in nearset:
            ad = G.prop(i, 'Adornee')
            if ad and ad[0] == 'Ref' and ad[1] in nearset:
                g = guirec(G, i['id']); g['part'] = ad[1]; guis.append(g)
    venue = dict(id=vid, path=G.path(vid), name=G.inst[vid]['name'], box=box)
    sf = G.child(vid, 'ShopFloor')
    if sf:
        venue['floor'] = partrec(G, sf)
    sb = [x for x in G.desc(vid) if G.inst[x]['name'] == 'ShopBounds']
    if sb:
        venue['bounds'] = partrec(G, sb[0])
    os.makedirs(SP + '/bprev/fx', exist_ok=True)
    json.dump(dict(venue=venue, parts=parts, guis=guis, lights=lights), open(SP + '/bprev/fx/%s.scene.json' % a.key, 'w'), ensure_ascii=False)
    # fixture: venue subtree + ancestor chain names (so scripts see Workspace.Gwangalli.<...>)
    chain = []
    p = G.inst[vid]['parent']
    while p:
        chain.append(dict(cls=G.inst[p]['cls'], name=G.inst[p]['name'], id=p)); p = G.inst[p]['parent']
    fx = dict(chain=list(reversed(chain)), tree=fixture(G, vid))
    open(SP + '/bprev/fx/%s.luau' % a.key, 'w').write('return function(Vector3, Color3, CFrame)\nreturn ' + lua(fx) + '\nend\n')
    print(a.key, venue['path'], 'parts in scene', len(parts), 'guis', len(guis), 'lights', len(lights), 'venue nodes', len(ids), 'box', [round(v, 1) for v in box])

if __name__ == '__main__':
    main()
