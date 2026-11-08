#!/usr/bin/env python3
"""Geometry audit for the Seoul skyline build (strict "no visible defects" pass).

    node seoul-skyline/tools/preview.js --dump dump.json [--dump-filter <lua pattern>] ...
    python3 seoul-skyline/tools/audit_geom.py dump.json [--filter Interior,ShowHome] [--limit 200] [--json out.json]

Checks (Block parts; cylinders' flat caps are treated as their bounding square):
  * ZFIGHT  : two visible faces that point the same way, lie in the same plane (|d| < 0.012 stud ≈ 3.6 mm) and overlap
              → flicker in Roblox. Severity HIGH when colour or material differ, LOW when identical.
  * NEARFIGHT: same, but 0.012 .. 0.04 stud apart — flickers at distance on mobile depth buffers (exterior rule ≥ 0.3,
              interior trim rule ≥ 0.05 in HANDOFF.md).
  * SLIVER  : visible part thinner than 0.05 stud in some axis but large in the others (Roblox clamps 0.05; a 0.05 plate
              that is not flush-mounted looks like paper).
Ignores fully transparent parts (≥ 0.95) and pairs that are both glass with transparency ≥ 0.5.
"""
import json, math, sys, collections, argparse

EPS_FIGHT = 0.012
EPS_NEAR = 0.04


def load(path):
    d = json.load(open(path))
    cols = d['cols']
    ix = {c: i for i, c in enumerate(cols)}
    parts = []
    for r in d['rows']:
        p = {c: r[i] for c, i in ix.items()}
        p['R'] = ((p['r00'], p['r01'], p['r02']), (p['r10'], p['r11'], p['r12']), (p['r20'], p['r21'], p['r22']))
        parts.append(p)
    return parts


def col(R, i):
    return (R[0][i], R[1][i], R[2][i])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def faces(p):
    """Yield (normal, planeD, centre, u, v, hu, hv) for the 6 faces of a block (cylinder: axis X caps + bounding sides skipped)."""
    s = (p['sx'], p['sy'], p['sz'])
    c = (p['x'], p['y'], p['z'])
    R = p['R']
    shape = p['shape']
    axes = [col(R, 0), col(R, 1), col(R, 2)]
    out = []
    for i in range(3):
        if shape == 'Cylinder' and i != 0:
            continue  # curved side: not planar
        if shape in ('Ball', 'Mesh', 'Wedge', 'Corner'):
            continue
        j, k = [a for a in range(3) if a != i]
        for sg in (1, -1):
            n = tuple(sg * a for a in axes[i])
            fc = tuple(c[t] + n[t] * s[i] / 2 for t in range(3))
            out.append((n, dot(n, fc), fc, axes[j], axes[k], s[j] / 2, s[k] / 2, shape == 'Cylinder'))
    return out


def rect_poly(fc, u, v, hu, hv, bu, bv):
    pts = []
    for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        p = tuple(fc[t] + u[t] * hu * a + v[t] * hv * b for t in range(3))
        pts.append((dot(p, bu), dot(p, bv)))
    return pts


def clip(subject, clipper):
    def inside(p, a, b):
        return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= -1e-9

    def inter(p1, p2, a, b):
        x1, y1 = p1; x2, y2 = p2; x3, y3 = a; x4, y4 = b
        den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if abs(den) < 1e-12:
            return p2
        t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
        return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))

    out = subject
    for i in range(len(clipper)):
        a, b = clipper[i], clipper[(i + 1) % len(clipper)]
        inp = out
        out = []
        if not inp:
            break
        s = inp[-1]
        for e in inp:
            if inside(e, a, b):
                if not inside(s, a, b):
                    out.append(inter(s, e, a, b))
                out.append(e)
            elif inside(s, a, b):
                out.append(inter(s, e, a, b))
            s = e
    return out


def area(poly):
    if len(poly) < 3:
        return 0.0
    a = 0.0
    for i in range(len(poly)):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % len(poly)]
        a += x1 * y2 - x2 * y1
    return abs(a) / 2


def ccw(poly):
    a = 0.0
    for i in range(len(poly)):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % len(poly)]
        a += x1 * y2 - x2 * y1
    return poly if a > 0 else poly[::-1]


LEVEL_CITY, LEVEL_PROM, LEVEL_WATER = 24.0, 5.0, 0.0
FAR = dict(edge=-700, parkTo=-867, slopeTo=-910)
NEAR = dict(edge=700, parkTo=1267, slopeTo=1317)


def ground_y(z):
    if FAR['edge'] < z < NEAR['edge']:
        return LEVEL_WATER
    if z <= FAR['edge']:
        if z > FAR['parkTo']:
            return LEVEL_PROM
        if z > FAR['slopeTo']:
            return LEVEL_PROM + (LEVEL_CITY - LEVEL_PROM) * (FAR['parkTo'] - z) / (FAR['parkTo'] - FAR['slopeTo'])
        return LEVEL_CITY
    if z < NEAR['parkTo']:
        return LEVEL_PROM
    if z < NEAR['slopeTo']:
        return LEVEL_PROM + (LEVEL_CITY - LEVEL_PROM) * (z - NEAR['parkTo']) / (NEAR['slopeTo'] - NEAR['parkTo'])
    return LEVEL_CITY


class Occluders:
    CELL = 16.0

    def __init__(self, parts):
        self.grid = collections.defaultdict(list)
        self.big = []
        for p in parts:
            if p['transparency'] > 0.3 or p['shape'] not in ('Block', 'Cylinder'):
                continue
            hx, hy, hz = self.half_extent(p)
            lo = (p['x'] - hx, p['y'] - hy, p['z'] - hz)
            hi = (p['x'] + hx, p['y'] + hy, p['z'] + hz)
            c0 = [math.floor(lo[i] / self.CELL) for i in range(3)]
            c1 = [math.floor(hi[i] / self.CELL) for i in range(3)]
            n = (c1[0] - c0[0] + 1) * (c1[1] - c0[1] + 1) * (c1[2] - c0[2] + 1)
            if n > 4000:
                self.big.append(p)
                continue
            for i in range(c0[0], c1[0] + 1):
                for j in range(c0[1], c1[1] + 1):
                    for k in range(c0[2], c1[2] + 1):
                        self.grid[(i, j, k)].append(p)

    @staticmethod
    def half_extent(p):
        R = p['R']
        s = (p['sx'] / 2, p['sy'] / 2, p['sz'] / 2)
        return tuple(sum(abs(R[i][j]) * s[j] for j in range(3)) for i in range(3))

    @staticmethod
    def inside(p, q):
        d = (q[0] - p['x'], q[1] - p['y'], q[2] - p['z'])
        R = p['R']
        if p['shape'] == 'Cylinder':
            lx = d[0] * R[0][0] + d[1] * R[1][0] + d[2] * R[2][0]
            ly = d[0] * R[0][1] + d[1] * R[1][1] + d[2] * R[2][1]
            lz = d[0] * R[0][2] + d[1] * R[1][2] + d[2] * R[2][2]
            r = min(p['sy'], p['sz']) / 2
            return abs(lx) <= p['sx'] / 2 + 1e-4 and ly * ly + lz * lz <= r * r
        for j, sj in enumerate((p['sx'], p['sy'], p['sz'])):
            l = d[0] * R[0][j] + d[1] * R[1][j] + d[2] * R[2][j]
            if abs(l) > sj / 2 + 1e-4:
                return False
        return True

    def covered(self, q, skip):
        key = tuple(math.floor(q[i] / self.CELL) for i in range(3))
        for p in self.grid.get(key, ()):
            if p['_id'] not in skip and self.inside(p, q):
                return True
        for p in self.big:
            if p['_id'] not in skip and self.inside(p, q):
                return True
        return False


def hidden(occ, n, poly, bu, bv, d, skip):
    # sample the overlap polygon (centroid + vertices pulled 15 % inward), 0.03 stud outside the face
    if not poly:
        return False
    cx = sum(x for x, _ in poly) / len(poly)
    cy = sum(y for _, y in poly) / len(poly)
    pts = [(cx, cy)] + [(cx + (x - cx) * 0.85, cy + (y - cy) * 0.85) for x, y in poly]
    for (a, b) in pts:
        q = tuple(bu[t] * a + bv[t] * b + n[t] * (d + 0.03) for t in range(3))
        if n[1] < -0.9 and q[1] <= ground_y(q[2]) + 0.06:
            continue  # downward face resting on the ground / terrain
        if n[1] > 0.9 and q[1] <= ground_y(q[2]) - 0.5:
            continue  # buried
        if not occ.covered(q, skip):
            return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dump')
    ap.add_argument('--filter', default='')
    ap.add_argument('--limit', type=int, default=150)
    ap.add_argument('--json')
    ap.add_argument('--min-area', type=float, default=0.02)
    a = ap.parse_args()
    parts = load(a.dump)
    filt = [f for f in a.filter.split(',') if f]
    # candidates: visible parts; at least one of each pair must match the filter
    vis = [p for p in parts if p['transparency'] < 0.95]
    for i, p in enumerate(vis):
        p['_id'] = i
        p['_in'] = (not filt) or any(f in p['path'] for f in filt)
    buckets = collections.defaultdict(list)
    for p in vis:
        for f in faces(p):
            n, d = f[0], f[1]
            key = (round(n[0], 2) + 0.0, round(n[1], 2) + 0.0, round(n[2], 2) + 0.0, math.floor(d / 0.1))
            buckets[key].append((p, f))
    occ = Occluders(vis)
    seen = set()
    issues = []
    nhidden = 0
    for key, lst in buckets.items():
        nk = key[:3]
        # also compare with neighbour d bucket
        cands = lst + buckets.get(nk + (key[3] + 1,), [])
        if len(cands) < 2:
            continue
        for i in range(len(lst)):
            p1, f1 = lst[i]
            for j in range(len(cands)):
                p2, f2 = cands[j]
                if p2['_id'] <= p1['_id'] and j < len(lst):
                    continue
                if p1['_id'] == p2['_id']:
                    continue
                if not (p1['_in'] or p2['_in']):
                    continue
                gap = abs(f1[1] - f2[1])
                if gap >= EPS_NEAR:
                    continue
                if p1['material'] == 'Glass' and p2['material'] == 'Glass' and p1['transparency'] >= 0.5 and p2['transparency'] >= 0.5:
                    continue
                pair = (min(p1['_id'], p2['_id']), max(p1['_id'], p2['_id']), nk)
                if pair in seen:
                    continue
                n = f1[0]
                bu = f1[3]
                bv = (n[1] * bu[2] - n[2] * bu[1], n[2] * bu[0] - n[0] * bu[2], n[0] * bu[1] - n[1] * bu[0])
                A = ccw(rect_poly(f1[2], f1[3], f1[4], f1[5], f1[6], bu, bv))
                B = ccw(rect_poly(f2[2], f2[3], f2[4], f2[5], f2[6], bu, bv))
                poly = clip(A, B)
                ov = area(poly)
                if ov < a.min_area:
                    continue
                seen.add(pair)
                if hidden(occ, n, poly, bu, bv, f1[1], {p1['_id'], p2['_id']}):
                    nhidden += 1
                    continue
                same = p1['material'] == p2['material'] and (p1['r'], p1['g'], p1['b']) == (p2['r'], p2['g'], p2['b'])
                kind = 'ZFIGHT' if gap < EPS_FIGHT else 'NEARFIGHT'
                sev = 'LOW' if same else ('HIGH' if kind == 'ZFIGHT' else 'MED')
                issues.append({'kind': kind, 'sev': sev, 'gap': round(gap, 4), 'overlap': round(ov, 3), 'normal': [round(x, 2) for x in n],
                               'a': p1['path'], 'b': p2['path'], 'at': [round(f1[2][t], 2) for t in range(3)],
                               'amat': f"{p1['material']} {p1['r']},{p1['g']},{p1['b']}", 'bmat': f"{p2['material']} {p2['r']},{p2['g']},{p2['b']}"})
    for p in vis:
        if not p['_in'] or p['shape'] not in ('Block',):
            continue
        s = sorted((p['sx'], p['sy'], p['sz']))
        if s[0] <= 0.051 and s[1] > 3 and p['material'] != 'Neon':
            issues.append({'kind': 'SLIVER', 'sev': 'LOW', 'a': p['path'], 'size': [p['sx'], p['sy'], p['sz']], 'at': [p['x'], p['y'], p['z']]})
    order = {'HIGH': 0, 'MED': 1, 'LOW': 2}
    issues.sort(key=lambda r: (order[r['sev']], r['kind'], -r.get('overlap', 0)))
    cnt = collections.Counter((r['kind'], r['sev']) for r in issues)
    print('parts', len(parts), 'visible', len(vis), 'issues', len(issues), 'hidden-skipped', nhidden, dict(cnt))
    groups = collections.Counter('.'.join(r['a'].split('.')[2:4]) for r in issues if r['sev'] != 'LOW')
    print('by group (HIGH/MED):', dict(groups.most_common(30)))
    for r in issues[: a.limit]:
        if r['kind'] == 'SLIVER':
            print(f"{r['sev']:4s} SLIVER  {r['a']}  size={r['size']} at={r['at']}")
        else:
            print(f"{r['sev']:4s} {r['kind']:9s} gap={r['gap']:<6} ov={r['overlap']:<7} n={r['normal']} at={r['at']}\n      A {r['a']} [{r['amat']}]\n      B {r['b']} [{r['bmat']}]")
    if a.json:
        json.dump(issues, open(a.json, 'w'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
