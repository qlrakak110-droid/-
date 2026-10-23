import json, base64, struct, sys, math
src = open('unpack/core/js/taxi_model.js', encoding='utf-8').read().split('\n')
MODELS = json.loads(src[1][len('const MODELS='):].rstrip(';'))
def piece(buf, pc):
    nv, nt, sz, o = pc['v'], pc['t'], pc['z'], pc['o']; K = 1/65535
    pos = []
    for i in range(nv):
        p = o + i*6
        pos.append(tuple((struct.unpack_from('<H', buf, p+k*2)[0]*K-0.5)*sz[k] + pc['c'][k] for k in range(3)))
    q = o + nv*6; nrm = []
    for i in range(nv):
        ox = buf[q+i*2]/255*2-1; oy = buf[q+i*2+1]/255*2-1; oz = 1-abs(ox)-abs(oy)
        if oz < 0:
            tx = (1-abs(oy))*(1 if ox>=0 else -1); ty = (1-abs(ox))*(1 if oy>=0 else -1); ox, oy = tx, ty
        l = math.sqrt(ox*ox+oy*oy+oz*oz); nrm.append((ox/l, oy/l, oz/l))
    q += nv*2
    if pc.get('u'): q += 16 + nv*4
    idx = []; hi = -1
    for k in range(nt*3):
        code = 0; shift = 1
        while True:
            b = buf[q]; q += 1
            if b < 128: code += b*shift; break
            code += (b-128)*shift; shift *= 128
        i = hi+1-code
        if i > hi: hi = i
        idx.append(i)
    return pos, nrm, idx
for M in MODELS:
    if 'data' not in M: continue
    buf = base64.b64decode(M['data'])
    for pc in M['pieces']:
        if pc['r'] not in ('glass', 'glass_dark'): continue
        pos, nrm, idx = piece(buf, pc)
        # car centre from glass bbox
        cx = sum(p[0] for p in pos)/len(pos); cy = sum(p[1] for p in pos)/len(pos); cz = sum(p[2] for p in pos)/len(pos)
        out = inn = 0; outA = inA = 0; agree = 0; area_tot = 0
        cats = {}
        for t in range(0, len(idx), 3):
            a, b, c = pos[idx[t]], pos[idx[t+1]], pos[idx[t+2]]
            u = [b[k]-a[k] for k in range(3)]; v = [c[k]-a[k] for k in range(3)]
            n = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
            ar = math.sqrt(sum(x*x for x in n))/2
            if ar < 1e-9: continue
            g = [(a[k]+b[k]+c[k])/3 for k in range(3)]
            d = (g[0]-cx, (g[1]-cy)*2, g[2]-cz)
            s = sum(n[k]*d[k] for k in range(3))
            vn = [(nrm[idx[t]][k]+nrm[idx[t+1]][k]+nrm[idx[t+2]][k]) for k in range(3)]
            if sum(vn[k]*n[k] for k in range(3)) > 0: agree += ar
            area_tot += ar
            if s > 0: out += 1; outA += ar
            else: inn += 1; inA += ar
            nn = [x/(2*ar) for x in n]
            cat = 'side' if abs(nn[0]) > 0.6 else ('front' if nn[2] < -0.3 else ('rear' if nn[2] > 0.3 else 'top'))
            cats[cat] = cats.get(cat, 0) + ar
        ys = [p[1] for p in pos]
        print(M['model'], pc['n'], 'tris', len(idx)//3, 'outward', out, round(outA,2), 'inward', inn, round(inA,2), 'vn-agree', round(agree/area_tot,3), 'y', round(min(ys),2), round(max(ys),2), {k: round(v,1) for k,v in cats.items()})
