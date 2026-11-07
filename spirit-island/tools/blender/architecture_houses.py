"""Village cottages (architecture workstream): three half-timbered variants on the same footprint as the old procedural
cottage (walls 5.0 x 4.2 m, eaves 3.7 m), so positions, colliders, smoke and the healer crystal keep working.

  A  classic: 45-ish degree gable, X-braced panels, gabled door canopy, chimney through the left slope
  B  tall: steep 49 degree roof, K-braced corners, off-centre door with pent canopy, external stone stack on the back gable
  C  long: low 39 degree roof, single diagonal braces, open lean-to woodshed on the left, chimney through the right slope

Real geometry: rubble plinth with quoins and half-buried footing stones, plaster walls with recessed openings (reveals),
proud chamfered oak frame, recessed casement windows (frame, mullion/transom, glass, stone or oak sill), plank shutters
with battens and strap hinges, flower boxes with plants, plank doors with hinges / ring pull / stone steps, boarded roof
deck with exposed rafter tails, barge boards, ridge bedding, half-round gutters on brackets with swan-neck downpipes,
stone chimneys with corbelled caps, clay pots and lead flashing, wall lanterns. Roof tiles are instanced at runtime on the
roof planes listed in each variant's meta (extras). COLOR_0 = (AO, per-piece variation, grime mask).

blender -b -P tools/blender/architecture_houses.py  ->  assets/models/architecture/houses.glb
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Euler
import architecture_kit as K

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'models', 'architecture'))
HW, HD, Y0, YT = 2.5, 2.1, 0.56, 3.7          # half width / depth of the walls, top of plinth, top of walls
UP = Vector((0, 1, 0))
FACES = {
    'front': (Vector((0, 0, HD)), Vector((1, 0, 0)), Vector((0, 0, 1)), HW),
    'back': (Vector((0, 0, -HD)), Vector((-1, 0, 0)), Vector((0, 0, -1)), HW),
    'right': (Vector((HW, 0, 0)), Vector((0, 0, -1)), Vector((1, 0, 0)), HD),
    'left': (Vector((-HW, 0, 0)), Vector((0, 0, 1)), Vector((-1, 0, 0)), HD),
}

VARIANTS = {
    'A': dict(rise=2.25, ov=0.45, gov=0.5, brace='x', chimney=('slope', -1.25, -0.9), porch='gable', attic='single',
              door=0.0, windows=[('front', -1.71), ('front', 1.71), ('back', -1.71), ('back', 1.71), ('right', 0.0), ('left', 0.0)],
              boxes={('front', -1.71), ('front', 1.71), ('right', 0.0)}, lean=False, lantern=0.95, seed=11),
    'B': dict(rise=2.9, ov=0.5, gov=0.55, brace='k', chimney=('gable', 0.95), porch='pent', attic='pair',
              door=-1.0, windows=[('front', 1.25, 1.3), ('back', -1.5), ('back', 1.5), ('right', -1.0), ('right', 1.0), ('left', -1.0), ('left', 1.0)],
              boxes={('front', 1.25), ('right', -1.0), ('left', 1.0)}, lean=False, lantern=-0.15, seed=12),
    'C': dict(rise=2.0, ov=0.4, gov=0.45, brace='d', chimney=('slope', 1.2, 0.55), porch='none', attic='vent',
              door=0.0, windows=[('front', -1.71), ('front', 1.71), ('back', -1.71), ('back', 1.71), ('right', 0.0)],
              boxes={('front', -1.71), ('front', 1.71)}, lean=True, lantern=0.95, seed=13),
}
WIN_Y0, WIN_H, WIN_W = 1.97, 0.95, 0.86
DOOR_W, DOOR_H = 1.12, 2.08


def sstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a))); return t * t * (3 - 2 * t)


def P(face, u, y, n=0.0):
    o, U, N, _ = FACES[face]
    return o + U * u + UP * y + N * n


class House:
    def __init__(self, key):
        self.key = key; self.v = VARIANTS[key]; self.k = K.Kit(self.v['seed']); self.r = random.Random(self.v['seed'] * 7)
        v = self.v
        self.rise = v['rise']; self.ov = v['ov']; self.gov = v['gov']; self.RD = HD + v['gov']
        self.YR = YT + 0.25 + self.rise                 # deck top at the ridge
        self.slope = self.rise / HW
        self.th = math.atan(self.slope)
        self.meta = {'roof': [], 'ridge': [], 'smoke': [], 'top': self.YR + 0.3}
        self.openings = {f: [] for f in FACES}          # (u0, u1, y0, y1, kind)
        self.win_list = []

    # deck top height at horizontal distance |x| from the ridge
    def deck(self, ax):
        return self.YR - self.slope * ax

    def gable_top(self, u):
        return self.deck(abs(u)) - 0.13 / math.cos(self.th)

    # ------------------------------------------------------------------ openings
    def plan_openings(self):
        v = self.v
        self.openings['front'].append((v['door'] - DOOR_W / 2, v['door'] + DOOR_W / 2, Y0, Y0 + DOOR_H, 'door'))
        for w in v['windows']:
            face, uc = w[0], w[1]; ww = w[2] if len(w) > 2 else WIN_W
            self.openings[face].append((uc - ww / 2, uc + ww / 2, WIN_Y0, WIN_Y0 + WIN_H, 'win'))
            self.win_list.append((face, uc, ww))
        # gable (attic) openings
        a = v['attic']; yc = YT + 0.82
        for face in ('front', 'back'):
            if a == 'single': self.openings[face].append((-0.28, 0.28, yc + 0.18, yc + 0.78, 'attic'))
            elif a == 'pair':
                for uc in (-0.62, 0.62): self.openings[face].append((uc - 0.22, uc + 0.22, yc + 0.2, yc + 0.85, 'attic'))
            elif a == 'vent': self.openings[face].append((-0.26, 0.26, yc + 0.16, yc + 0.62, 'vent'))

    # ------------------------------------------------------------------ plaster walls (grid with holes + reveals)
    def walls(self):
        k = self.k
        for face, (o, U, N, half) in FACES.items():
            ops = self.openings[face]
            gable = face in ('front', 'back')
            ytop_rect = YT if gable else YT + 0.16
            ymax = self.YR if gable else ytop_rect
            us = set([-half, half, 0.0]); ys = set([Y0, ytop_rect])
            n = int(2 * half / 0.32)
            for i in range(n + 1): us.add(round(-half + 2 * half * i / n, 4))
            m = int((ymax - Y0) / 0.32)
            for i in range(m + 1): ys.add(round(Y0 + (ymax - Y0) * i / m, 4))
            for (u0, u1, y0, y1, kind) in ops: us.update([u0, u1]); ys.update([y0, y1])
            us = sorted(us); ys = sorted(ys)
            for i in range(len(us) - 1):
                for j in range(len(ys) - 1):
                    u0, u1, y0, y1 = us[i], us[i + 1], ys[j], ys[j + 1]
                    if u1 - u0 < 1e-4 or y1 - y0 < 1e-4: continue
                    cu, cy = (u0 + u1) / 2, (y0 + y1) / 2
                    if any(a < cu < b and c < cy < d for (a, b, c, d, _) in ops): continue
                    poly = [(u0, y0), (u1, y0), (u1, y1), (u0, y1)]
                    if cy > ytop_rect:
                        if not gable: continue
                        poly = clip_below(poly, lambda u: self.gable_top(u))
                        if len(poly) < 3: continue
                    elif y1 > ytop_rect + 1e-6: continue
                    pts = [P(face, u, y) for u, y in poly]
                    uo = {'front': 0.0, 'back': 0.37, 'right': 0.71, 'left': 0.13}[face]
                    uvs = [(u / 2.5 + uo, y / 2.5) for u, y in poly]
                    k.poly('plaster', pts, uvs, N, var=0.5, keyed=True)
            # reveals
            for (u0, u1, y0, y1, kind) in ops:
                dpt = 0.24
                for (a, b, nrm) in (((u0, y0), (u1, y0), UP), ((u1, y1), (u0, y1), -UP), ((u0, y1), (u0, y0), U), ((u1, y0), (u1, y1), -U)):
                    pts = [P(face, a[0], a[1], 0), P(face, b[0], b[1], 0), P(face, b[0], b[1], -dpt), P(face, a[0], a[1], -dpt)]
                    L = (Vector(a) - Vector(b)).length
                    k.poly('plaster', pts, [(0, 0), (L / 2.5, 0), (L / 2.5, dpt / 2.5), (0, dpt / 2.5)], nrm, var=0.5, keyed=True)

    # ------------------------------------------------------------------ plinth, quoins, footing stones
    def plinth(self):
        k, r = self.k, self.r
        e = 0.13
        k.box('stone', (0, (Y0 - 0.75) / 2, 0), (2 * HW + 2 * e, Y0 + 0.75, 2 * HD + 2 * e), ch=0.03, wuv=2.0)
        # chamfered weathering course on top of the plinth
        for face, (o, U, N, half) in FACES.items():
            a = P(face, -half - e, Y0 - 0.02, e - 0.02); b = P(face, half + e, Y0 - 0.02, e - 0.02)
            k.prism('stone', a, b, 0.07, 0.07, N + UP, ch=0.0, wuv=2.0)
        # quoins: big dressed corner stones, alternating long/short
        for sx in (-1, 1):
            for sz in (-1, 1):
                for i, (yy, h) in enumerate(((-0.1, 0.3), (0.24, 0.32))):
                    lx = 0.62 if i % 2 == 0 else 0.4; lz = 0.4 if i % 2 == 0 else 0.62
                    c = (sx * (HW + e + 0.015 - lx / 2), yy + h / 2, sz * (HD + e + 0.015 - lz / 2))
                    k.box('stone', c, (lx, h, lz), rot=(0, r.uniform(-0.02, 0.02), 0), ch=0.035, wuv=2.0)
        # footing stones half-sunk along the base (break the straight contact line)
        n = 0
        for face, (o, U, N, half) in FACES.items():
            u = -half - 0.1 + r.uniform(0, 0.4)
            while u < half + 0.1:
                if face == 'front' and abs(u - self.v['door']) < 1.0: u += 0.5; continue
                if self.v['lean'] and face == 'left': break
                if r.random() < 0.55:
                    sz = (r.uniform(0.28, 0.5), r.uniform(0.18, 0.3), r.uniform(0.22, 0.4))
                    c = P(face, u, -0.04, e + r.uniform(0.02, 0.16))
                    k.stone('stone', c, sz, rot_y=r.uniform(0, 3.14), seed=1000 + n + self.v['seed'] * 100, sub=1, rough=0.25, flat_bottom=0.4)
                    n += 1
                u += r.uniform(0.35, 0.8)

    # ------------------------------------------------------------------ timber frame
    def frame(self):
        k, r, v = self.k, self.r, self.v
        D, PR = 0.15, 0.045                   # timber depth, how far it stands proud of the plaster
        nc = PR - D / 2
        def beam(face, u0, y0, u1, y1, w=0.2, ch=0.02, mat='timber'):
            jit = r.uniform(-0.008, 0.008)
            k.prism(mat, P(face, u0, y0 + jit, nc), P(face, u1, y1 - jit, nc), w, D, FACES[face][2], ch=ch, uv=(0.5, 2.0))
        # corner posts (square, proud on both faces)
        for sx in (-1, 1):
            for sz in (-1, 1):
                c0 = Vector((sx * (HW - 0.075), Y0, sz * (HD - 0.075))); c1 = c0 + Vector((0, YT + 0.02 - Y0, 0))
                k.prism('timber', c0, c1, 0.24, 0.24, Vector((sx, 0, sz)), ch=0.025, uv=(0.5, 2.0))
        for face, (o, U, N, half) in FACES.items():
            ops = [op for op in self.openings[face] if op[4] in ('win', 'door')]
            beam(face, -half, Y0 + 0.11, half, Y0 + 0.11, w=0.22)                   # sill beam
            beam(face, -half, YT - 0.11, half, YT - 0.11, w=0.22)                   # top plate / tie beam
            posts = [-half + 0.12, half - 0.12]
            for (u0, u1, y0, y1, kind) in ops: posts += [u0 - 0.1, u1 + 0.1]
            posts = sorted(posts)
            merged = []
            for p in posts:
                if merged and p - merged[-1] < 0.3: merged[-1] = (merged[-1] + p) / 2
                else: merged.append(p)
            filled = [merged[0]]
            for p in merged[1:]:
                gap = p - filled[-1]
                if gap > 1.35:
                    m = int(gap / 1.1)
                    for i in range(1, m + 1): filled.append(filled[-1] + gap / (m + 1) if i == 1 else filled[-1] + gap / (m + 1))
                filled.append(p)
            for p in filled[1:-1]:
                beam(face, p, Y0 + 0.2, p, YT - 0.2, w=0.19)
            # panels between posts
            for i in range(len(filled) - 1):
                a, b = filled[i] + 0.095, filled[i + 1] - 0.095
                if b - a < 0.15: continue
                inside = [op for op in ops if op[0] > a - 0.05 and op[1] < b + 0.05]
                yl = Y0 + 0.22; yh = YT - 0.22
                if inside:
                    u0, u1, y0, y1, kind = inside[0]
                    if kind == 'win':
                        beam(face, a, y0 - 0.09, b, y0 - 0.09, w=0.18)
                        beam(face, a, y1 + 0.09, b, y1 + 0.09, w=0.18)
                        self.braces(face, beam, a, yl, b, y0 - 0.18, under=True, corner=(i == 0, i == len(filled) - 2))
                    else:
                        beam(face, a, y1 + 0.1, b, y1 + 0.1, w=0.2)
                else:
                    ym = 1.95
                    beam(face, a, ym, b, ym, w=0.17)
                    self.braces(face, beam, a, yl, b, ym - 0.085, under=False, corner=(i == 0, i == len(filled) - 2))
                    if v['brace'] in ('k', 'd') and (i == 0 or i == len(filled) - 2):
                        left = i == 0
                        beam(face, a if left else b, ym + 0.085, b if left else a, yh, w=0.15)
            if face in ('front', 'back'): self.gable_frame(face, beam)

    def braces(self, face, beam, a, y0, b, y1, under, corner):
        st = self.v['brace']
        if b - a < 0.3 or y1 - y0 < 0.25: return
        if st == 'x':
            beam(face, a, y0, b, y1, w=0.14); beam(face, a, y1, b, y0, w=0.14)
        elif st == 'k':
            if corner[0]: beam(face, a, y0, b, y1, w=0.15)
            elif corner[1]: beam(face, a, y1, b, y0, w=0.15)
            elif under:
                m = (a + b) / 2; beam(face, a, y0, m, y1, w=0.13); beam(face, b, y0, m, y1, w=0.13)
        else:
            if corner[0]: beam(face, a, y1, b, y0, w=0.15)
            elif corner[1]: beam(face, a, y0, b, y1, w=0.15)
            elif not under: beam(face, a, y0, b, y1, w=0.15)

    def gable_frame(self, face, beam):
        v = self.v; yc = YT + 0.82
        top = self.gable_top
        # collar beam across the gable
        uc = HW - (yc + 0.09 - YT - 0.12) / self.slope
        beam(face, -uc + 0.05, yc, uc - 0.05, yc, w=0.18)
        # lower band studs + braces
        for s in (-1, 1):
            beam(face, s * 0.95, YT + 0.1, s * 0.95, yc - 0.09, w=0.17)
            beam(face, s * 0.95, YT + 0.1, s * 1.75, yc - 0.09, w=0.13)
        if v['attic'] == 'pair':
            beam(face, 0, YT + 0.1, 0, top(0) - 0.05, w=0.18)
            for uc2 in (-0.62, 0.62):
                for s in (-1, 1):
                    u = uc2 + s * 0.32
                    if abs(u) > 0.2: beam(face, u, yc + 0.09, u, top(u) - 0.05, w=0.15)
        else:
            beam(face, 0, YT + 0.1, 0, yc - 0.09, w=0.17)
            for s in (-1, 1): beam(face, s * 0.38, yc + 0.09, s * 0.38, top(0.38) - 0.04, w=0.15)
            y1 = yc + (0.78 if v['attic'] == 'single' else 0.62)
            beam(face, -0.38, y1 + 0.08, 0.38, y1 + 0.08, w=0.14)
            beam(face, 0, y1 + 0.16, 0, top(0) - 0.05, w=0.15)
            for s in (-1, 1):
                u0 = s * 0.47; u1 = s * (0.47 + 0.9)
                if top(u1) - 0.1 > yc + 0.3: beam(face, u0, yc + 0.1, u1, top(u1) - 0.06, w=0.13)

    # ------------------------------------------------------------------ windows
    def windows(self):
        for (face, uc, ww) in self.win_list:
            self.window(face, uc, WIN_Y0, ww, WIN_H, shutters=True, box=(face, uc) in self.v['boxes'])
        for face in ('front', 'back'):
            for (u0, u1, y0, y1, kind) in self.openings[face]:
                if kind == 'attic': self.window(face, (u0 + u1) / 2, y0, u1 - u0, y1 - y0, shutters=False, box=False, small=True)
                if kind == 'vent': self.vent(face, u0, u1, y0, y1)

    def window(self, face, uc, y0, w, h, shutters, box, small=False):
        k, r = self.k, self.r
        o, U, N, half = FACES[face]
        y1 = y0 + h; fw = 0.07 if not small else 0.06; nz = -0.1
        def piece(u0, yy0, u1, yy1, ww, dd, n=nz, mat='wood'):
            k.prism(mat, P(face, u0, yy0, n), P(face, u1, yy1, n), ww, dd, N, ch=0.008, uv=(0.5, 2.0))
        l, rr = uc - w / 2, uc + w / 2
        piece(l + fw / 2, y0, l + fw / 2, y1, fw, 0.1); piece(rr - fw / 2, y0, rr - fw / 2, y1, fw, 0.1)
        piece(l + fw, y1 - fw / 2, rr - fw, y1 - fw / 2, fw, 0.1); piece(l + fw, y0 + fw / 2, rr - fw, y0 + fw / 2, fw, 0.1)
        ty = y0 + h * 0.64
        lights = 2 if w < 1.0 else 3
        for i in range(1, lights):
            u = l + (w) * i / lights
            piece(u, y0 + fw, u, y1 - fw, 0.045, 0.07, n=nz - 0.01)
        if not small: piece(l + fw, ty, rr - fw, ty, 0.045, 0.07, n=nz - 0.01)
        # glass (slightly bowed panes would be overkill; set back behind the glazing bars)
        g = [P(face, l + fw * 0.5, y0 + fw * 0.5, -0.125), P(face, rr - fw * 0.5, y0 + fw * 0.5, -0.125), P(face, rr - fw * 0.5, y1 - fw * 0.5, -0.125), P(face, l + fw * 0.5, y1 - fw * 0.5, -0.125)]
        k.poly('glass', g, [(0, 0), (1, 0), (1, 1), (0, 1)], N, var=r.random())
        # curtains: a soft fabric drape behind the glass catches the light and gives the window depth
        if not small:
            for s in (-1, 1):
                cu0 = uc + s * (w / 2 - 0.08); cu1 = uc + s * (w / 2 - 0.08 - w * 0.22)
                cp = [P(face, cu0, y0 + 0.08, -0.2), P(face, cu1, y0 + 0.2, -0.2), P(face, cu1, y1 - 0.06, -0.2), P(face, cu0, y1 - 0.06, -0.2)]
                k.poly('cloth', cp, [(0, 0), (1, 0), (1, 1), (0, 1)], N, var=r.random())
        # sill: projecting oak (or stone on the B variant) with a drip edge
        sm = 'stone' if self.key == 'B' and not small else 'wood'
        k.prism(sm, P(face, l - 0.1, y0 - 0.03, 0.02), P(face, rr + 0.1, y0 - 0.03, 0.02), 0.26, 0.06, UP, ch=0.012, uv=(0.5, 2.0) if sm == 'wood' else (2.0, 2.0))
        if shutters: self.shutters(face, l, rr, y0, y1)
        if box: self.flowerbox(face, uc, w, y0)

    def shutters(self, face, l, rr, y0, y1):
        k, r = self.k, self.r
        o, U, N, half = FACES[face]
        wl = (rr - l) / 2 + 0.03; hh = y1 - y0 + 0.06
        for s, hinge_u in ((-1, l - 0.02), (1, rr + 0.02)):
            phi = math.radians(r.uniform(18, 34))
            d = U * (s * math.cos(phi)) + N * math.sin(phi)           # leaf direction from the hinge, swung open
            m = (N - d * N.dot(d)).normalized()                        # leaf face pointing out of the wall
            base = P(face, hinge_u, y0 - 0.03, 0.06)
            planks = 3
            for i in range(planks):
                a = (i + 0.04) / planks * wl; b = (i + 0.96) / planks * wl
                c = base + d * ((a + b) / 2)
                k.prism('paint', c, c + UP * hh, b - a, 0.035, m, ch=0.006, uv=(0.5, 2.0), var=0.3 + 0.4 * r.random())
            for yy in (0.18, hh - 0.18):
                c = base + UP * yy
                k.prism('paint', c + d * 0.04 + m * 0.03, c + d * (wl - 0.04) + m * 0.03, 0.09, 0.025, m, ch=0.004, uv=(0.5, 2.0))
                k.prism('iron', c + d * (-0.02) + m * 0.047, c + d * (wl * 0.55) + m * 0.047, 0.035, 0.008, m, uv=(0.5, 0.5))
            k.prism('paint', base + UP * 0.18 + d * 0.06 + m * 0.03, base + UP * (hh - 0.18) + d * (wl - 0.06) + m * 0.03, 0.08, 0.022, m, ch=0.004, uv=(0.5, 2.0))

    def flowerbox(self, face, uc, w, y0):
        k, r = self.k, self.r
        o, U, N, half = FACES[face]
        L = w + 0.08; yb = y0 - 0.26
        c = P(face, uc, yb, 0.2)
        k.box('wood', c, (L, 0.2, 0.2), rot=rot_for(face), ch=0.01, uv=(0.5, 2.0))
        for s in (-1, 1):
            k.prism('iron', P(face, uc + s * L * 0.33, yb - 0.1, 0.05), P(face, uc + s * L * 0.33, yb - 0.1, 0.3), 0.03, 0.03, UP)
            k.prism('iron', P(face, uc + s * L * 0.33, yb - 0.32, 0.03), P(face, uc + s * L * 0.33, yb - 0.1, 0.28), 0.025, 0.025, U)
        self.plants(lambda t, q: P(face, uc + (t - 0.5) * (L - 0.12), yb + 0.1, 0.2 + q * 0.07), n=int(L / 0.09))

    def plants(self, at, n, top=0.0):
        plant_bed(self.k, self.r, at, n)

    def vent(self, face, u0, u1, y0, y1):
        k = self.k; o, U, N, half = FACES[face]
        k.poly('glass', [P(face, u0, y0, -0.2), P(face, u1, y0, -0.2), P(face, u1, y1, -0.2), P(face, u0, y1, -0.2)], [(0, 0), (1, 0), (1, 1), (0, 1)], N)
        n = 5
        for i in range(n):
            y = y0 + (i + 0.5) / n * (y1 - y0)
            k.prism('wood', P(face, u0, y, -0.08), P(face, u1, y, -0.08), 0.1, 0.018, N * 0.6 + UP * 0.8, ch=0.0)
        for s, u in ((1, u0 + 0.03), (-1, u1 - 0.03)): k.prism('wood', P(face, u, y0, -0.06), P(face, u, y1, -0.06), 0.06, 0.08, N, ch=0.008)

    # ------------------------------------------------------------------ door, steps, canopy, lantern
    def door(self):
        k, r, v = self.k, self.r, self.v
        face = 'front'; o, U, N, half = FACES[face]
        uc = v['door']; l, rr = uc - DOOR_W / 2, uc + DOOR_W / 2; y0, y1 = Y0, Y0 + DOOR_H
        def piece(u0, yy0, u1, yy1, ww, dd, n, mat='wood', ch=0.01):
            k.prism(mat, P(face, u0, yy0, n), P(face, u1, yy1, n), ww, dd, N, ch=ch, uv=(0.5, 2.0))
        piece(l + 0.05, y0, l + 0.05, y1, 0.1, 0.14, -0.07); piece(rr - 0.05, y0, rr - 0.05, y1, 0.1, 0.14, -0.07)
        piece(l, y1 - 0.05, rr, y1 - 0.05, 0.1, 0.14, -0.07)
        nb = 5; inner = DOOR_W - 0.2
        for i in range(nb):
            a = l + 0.1 + inner * i / nb + 0.006; b = l + 0.1 + inner * (i + 1) / nb - 0.006
            piece((a + b) / 2, y0 + 0.02, (a + b) / 2, y1 - 0.1, b - a, 0.05, -0.15, mat='door', ch=0.012)
        for yy in (y0 + 0.32, y1 - 0.42):
            piece(l + 0.14, yy, rr - 0.1, yy, 0.12, 0.03, -0.115, mat='door', ch=0.006)
            k.prism('iron', P(face, l + 0.06, yy, -0.096), P(face, l + 0.06 + inner * 0.62, yy, -0.096), 0.05, 0.01, N)
            k.box('iron', P(face, l + 0.06 + inner * 0.62, yy, -0.09), (0.06, 0.06, 0.02), rot=rot_for(face))
        # ring pull and escutcheon
        hp = P(face, rr - 0.24, Y0 + 1.0, -0.09)
        k.box('iron', hp, (0.08, 0.16, 0.012), rot=rot_for(face))
        ring = [hp + N * 0.03 + (UP * math.cos(t) * 0.06 + U * math.sin(t) * 0.06) - UP * 0.06 for t in [i / 10 * 2 * math.pi for i in range(10)]]
        k.tube('iron', ring, 0.009, seg=5, closed=True)
        # threshold + stone steps (sunk below the ground)
        k.box('stone', P(face, uc, Y0 - 0.03, -0.02), (DOOR_W + 0.1, 0.06, 0.3), rot=rot_for(face), ch=0.01, wuv=2.0)
        k.box('stone', P(face, uc, (Y0 - 0.02 - 0.5) / 2 + 0.0, 0.33), (DOOR_W + 0.4, Y0 - 0.02 + 0.5, 0.42), rot=rot_for(face), ch=0.03, wuv=2.0)
        k.box('stone', P(face, uc, (Y0 * 0.5 - 0.5) / 2, 0.78), (DOOR_W + 0.8, Y0 * 0.5 + 0.5, 0.5), rot=rot_for(face, r.uniform(-0.03, 0.03)), ch=0.035, wuv=2.0)
        # canopy
        if v['porch'] == 'gable': self.canopy_gable(uc)
        elif v['porch'] == 'pent': self.canopy_pent(uc)
        else:
            piece(l - 0.12, y1 + 0.16, rr + 0.12, y1 + 0.16, 0.2, 0.12, 0.02, mat='timber', ch=0.02)
        # wall lantern
        if v.get('lantern') is not None: self.lantern(face, v['lantern'] + (0.0 if uc == 0 else 0.0), 2.62)

    def canopy_gable(self, uc):
        k = self.k; face = 'front'; o, U, N, half = FACES[face]
        y_eave = Y0 + DOOR_H + 0.38; rise = 0.5; hwc = 0.78; depth = 1.05
        for s in (-1, 1):
            # bracket: wall post + curved-ish brace
            k.prism('timber', P(face, uc + s * 0.66, y_eave - 0.08, 0.06), P(face, uc + s * 0.66, y_eave - 0.08, depth - 0.06), 0.12, 0.1, UP, ch=0.012)
            k.prism('timber', P(face, uc + s * 0.66, y_eave - 0.62, 0.05), P(face, uc + s * 0.66, y_eave - 0.12, depth * 0.55), 0.09, 0.09, U, ch=0.01)
            # deck plane for this half
            a = P(face, uc, y_eave + rise, 0.0); b = P(face, uc + s * (hwc + 0.08), y_eave - 0.04, 0.0)
            th = math.atan2(rise + 0.04, hwc + 0.08)
            mid = (a + b) / 2 + N * (depth / 2)
            nrm = U * (s * math.sin(th)) + UP * math.cos(th)
            k.prism('wood', a + N * depth - nrm * 0.03, b + N * depth - nrm * 0.03, 0.16, 0.04, N, ch=0.004)  # front barge
            k.prism('wood', mid - nrm * 0.035 - N * (depth / 2) + N * 0.0, mid - nrm * 0.035 + N * (depth / 2) - N * 0.0, (b - a).length, 0.05, nrm, ch=0.0)
            v_dir = (a - b).normalized()
            self.meta['roof'] += [list(b + N * (depth + 0.02)) + list(-N) + list(v_dir) + [depth + 0.02, (a - b).length - 0.02]]
        self.meta['ridge'] += [list(P(face, uc, y_eave + rise + 0.0, depth + 0.02)) + list(-N) + [depth + 0.02]]

    def canopy_pent(self, uc):
        k = self.k; face = 'front'; o, U, N, half = FACES[face]
        yw = Y0 + DOOR_H + 0.55; depth = 0.95; drop = 0.36; hwc = 0.82
        th = math.atan2(drop, depth)
        nrm = (UP * math.cos(th) + N * math.sin(th)).normalized()
        for s in (-1, 1):
            k.prism('timber', P(face, uc + s * (hwc - 0.12), yw - 0.08, 0.06), P(face, uc + s * (hwc - 0.12), yw - drop - 0.06, depth - 0.05), 0.1, 0.12, U, ch=0.012)
            k.prism('timber', P(face, uc + s * (hwc - 0.12), yw - 0.85, 0.04), P(face, uc + s * (hwc - 0.12), yw - drop * 0.75 - 0.08, depth * 0.62), 0.09, 0.09, U, ch=0.01)
        a = P(face, uc, yw, 0.0); b = P(face, uc, yw - drop, depth)
        k.prism('wood', (a + b) / 2 - U * hwc - nrm * 0.03, (a + b) / 2 + U * hwc - nrm * 0.03, (b - a).length, 0.05, nrm, ch=0.0)
        k.prism('wood', b - U * hwc - nrm * 0.05, b + U * hwc - nrm * 0.05, 0.16, 0.04, (b - a).normalized(), ch=0.004)
        self.meta['roof'] += [list(b - U * hwc) + list(U) + list((a - b).normalized()) + [2 * hwc, (a - b).length]]

    def lantern(self, face, u, y):
        k = self.k; o, U, N, half = FACES[face]
        base = P(face, u, y, 0.05)
        k.box('iron', P(face, u, y - 0.05, 0.03), (0.12, 0.26, 0.03), rot=rot_for(face))
        arm = [base, base + N * 0.18 + UP * 0.05, base + N * 0.36 + UP * 0.02]
        k.tube('iron', arm, 0.016, seg=6)
        k.tube('iron', [base - UP * 0.2, base + N * 0.2 - UP * 0.02], 0.012, seg=5)
        c = base + N * 0.36 - UP * 0.2
        k.prism('glow', c - UP * 0.13, c + UP * 0.13, 0.15, 0.15, N, ch=0.0)
        for a in (-1, 1):
            for b in (-1, 1):
                q = c + U * (a * 0.085) + N * (b * 0.085)
                k.prism('iron', q - UP * 0.15, q + UP * 0.15, 0.022, 0.022, N)
        k.box('iron', c - UP * 0.16, (0.21, 0.025, 0.21), rot=rot_for(face))
        k.lathe('iron', c + UP * 0.14, [(0.15, 0.0), (0.14, 0.02), (0.02, 0.15), (0.0, 0.17)], seg=4, phase=math.pi / 4)
        k.lathe('iron', c + UP * 0.3, [(0.0, 0.0), (0.03, 0.0), (0.03, 0.03), (0.0, 0.05)], seg=6)

    # ------------------------------------------------------------------ roof structure
    def roof(self):
        k, r, v = self.k, self.r, self.v
        RD = self.RD; ov = self.ov; th = self.th; YR = self.YR
        ex = HW + ov
        for s in (-1, 1):
            n = Vector((s * math.sin(th), math.cos(th), 0))                       # outward roof normal
            down = Vector((s * math.cos(th), -math.sin(th), 0))                    # down-slope direction
            top = Vector((0, YR, 0)); eave = Vector((s * ex, self.deck(ex), 0))
            L = (eave - top).length
            # boarded deck (seen as the soffit under the eaves)
            mid = (top + eave) / 2 - n * 0.045
            k.prism('wood', mid + Vector((0, 0, -RD)), mid + Vector((0, 0, RD)), L, 0.09, n, ch=0.0, uv=(0.5, 2.0))
            # rafters (exposed tails under the eaves), spaced ~0.55 m
            m = int(2 * RD / 0.56)
            for i in range(m + 1):
                z = -RD + 0.08 + (2 * RD - 0.16) * i / m
                a = top + down * 0.12 - n * 0.17 + Vector((0, 0, z)); b = eave - down * 0.02 - n * 0.17 + Vector((0, 0, z))
                k.prism('timber', a, b, 0.09, 0.15, n, ch=0.012, uv=(0.5, 2.0))
            # wall plate along the eave wall (rafters sit on it)
            k.prism('timber', Vector((s * (HW - 0.02), YT + 0.08, -HD - 0.1)), Vector((s * (HW - 0.02), YT + 0.08, HD + 0.1)), 0.22, 0.2, Vector((s, 0, 0)), ch=0.02)
            # barge boards on both gables + verge rafters
            for sz in (-1, 1):
                z = sz * (RD - 0.025)
                k.prism('wood', top + Vector((0, 0.05, z)) - n * 0.07, eave + Vector((0, 0.05, z)) - n * 0.07 + down * 0.03, 0.3, 0.05, Vector((0, 0, sz)), ch=0.006, uv=(0.5, 2.0))
                k.prism('timber', top + Vector((0, 0, z - sz * 0.1)) - n * 0.17, eave + Vector((0, 0, z - sz * 0.1)) - n * 0.17, 0.12, 0.15, n, ch=0.012)
            # gutter on brackets + swan-neck downpipe (not on the lean-to side)
            if not (v['lean'] and s < 0):
                gy = self.deck(ex) - 0.12; gx = s * (ex + 0.07)
                k.tube('iron', [Vector((gx, gy + 0.012, -RD + 0.05)), Vector((gx, gy - 0.012, RD - 0.05))], 0.062, seg=8, uv=(0.3, 1.0))
                for i in range(int(2 * RD / 0.9) + 1):
                    z = -RD + 0.2 + (2 * RD - 0.4) * i / int(2 * RD / 0.9)
                    k.tube('iron', [Vector((s * (ex - 0.06), gy + 0.07, z)), Vector((gx + s * 0.075, gy + 0.03, z)), Vector((gx + s * 0.07, gy - 0.07, z))], 0.008, seg=4)
                zo = HD - 0.35
                pts = [Vector((gx, gy - 0.04, zo)), Vector((gx, gy - 0.22, zo)), Vector((s * (HW + 0.12), gy - 0.62, zo)), Vector((s * (HW + 0.12), 0.3, zo)), Vector((s * (HW + 0.28), 0.14, zo))]
                k.tube('iron', pts, 0.045, seg=8, uv=(0.3, 1.0))
                for yy in (1.2, 2.5):
                    k.prism('iron', Vector((s * (HW + 0.03), yy, zo)), Vector((s * (HW + 0.12), yy, zo)), 0.11, 0.02, UP)
            # tile plane for the runtime instancer: eave corner, along-eave dir, up-slope dir, lengths
            o = eave + Vector((0, 0, -RD))
            self.meta['roof'] += [list(o) + [0, 0, 1] + list(-down) + [2 * RD, L]]
        # ridge bedding (mortar) + ridge line for the cap tiles
        k.prism('stone', Vector((0, YR + 0.015, -RD - 0.02)), Vector((0, YR + 0.015, RD + 0.02)), 0.3, 0.07, UP, ch=0.02, wuv=2.0)
        self.meta['ridge'] += [[0, YR + 0.03, -RD - 0.03, 0, 0, 1, 2 * RD + 0.06]]

    # ------------------------------------------------------------------ chimney
    def chimney(self):
        k, r, v = self.k, self.r, self.v
        c = v['chimney']
        if c[0] == 'slope':
            cx, cz = c[1], c[2]
            yb = self.deck(abs(cx) + 0.36) - 0.25; ytop = self.YR + 0.95
            body = Vector((cx, (yb + ytop) / 2, cz))
            k.box('stone', body, (0.74, ytop - yb, 0.74), ch=0.02, wuv=2.0)
            # lead flashing skirt following the slope
            s = 1 if cx > 0 else -1
            yf = self.deck(abs(cx)) + 0.03
            k.box('iron', Vector((cx, yf, cz)), (0.86, 0.06, 0.86), rot=(0, 0, -s * self.th), ch=0.0)
        else:
            cx = c[1]; cz = -HD - 0.34
            ytop = self.YR + 0.7
            k.box('stone', Vector((cx, (YT + 0.3 - 0.5) / 2, cz)), (1.06, YT + 0.3 + 0.5, 0.66), ch=0.025, wuv=2.0)
            # weathered shoulders stepping in to the stack
            k.box('stone', Vector((cx, YT + 0.42, cz)), (0.96, 0.24, 0.6), rot=(0.0, 0, 0), ch=0.06, wuv=2.0)
            k.box('stone', Vector((cx, (YT + 0.5 + ytop) / 2, cz - 0.02)), (0.74, ytop - YT - 0.5, 0.56), ch=0.02, wuv=2.0)
            # footing stones
            for i in range(4):
                k.stone('stone', Vector((cx + r.uniform(-0.6, 0.6), -0.03, cz - 0.3 - r.uniform(0, 0.15))), (r.uniform(0.25, 0.4), 0.22, r.uniform(0.2, 0.35)), rot_y=r.uniform(0, 3), seed=3000 + i, flat_bottom=0.4)
        top = ytop
        k.box('stone', Vector((cx, top - 0.24, cz)), (0.9, 0.09, 0.9) if c[0] == 'slope' else (0.9, 0.09, 0.72), ch=0.015, wuv=2.0)
        k.box('stone', Vector((cx, top + 0.04, cz)), (0.86, 0.08, 0.86) if c[0] == 'slope' else (0.86, 0.08, 0.68), ch=0.015, wuv=2.0)
        pots = [(-0.17, 0), (0.17, 0)] if c[0] == 'slope' else [(0.0, 0)]
        for (dx, dz) in pots:
            pc = Vector((cx + dx, top + 0.08, cz + dz))
            hh = r.uniform(0.3, 0.42)
            k.lathe('clay', pc, [(0.115, 0.0), (0.1, hh * 0.85), (0.125, hh * 0.9), (0.125, hh), (0.085, hh), (0.085, hh - 0.08)], seg=12, uv=(0.5, 0.5))
            self.meta['smoke'].append(list(pc + Vector((0, hh + 0.1, 0))))

    # ------------------------------------------------------------------ lean-to woodshed (variant C)
    def leanto(self):
        k, r = self.k, self.r
        x0 = -HW - 0.02; x1 = -HW - 1.35; z0, z1 = -1.7, 1.15; yh = YT - 0.35; yl = 2.35
        for z in (z0, (z0 + z1) / 2, z1):
            k.prism('timber', Vector((x1 + 0.08, -0.15, z)), Vector((x1 + 0.08, yl - 0.08, z)), 0.16, 0.16, Vector((1, 0, 0)), ch=0.02)
            k.stone('stone', Vector((x1 + 0.08, 0.0, z)), (0.34, 0.2, 0.34), seed=4000 + int(z * 10), flat_bottom=0.5)
            k.prism('timber', Vector((x0, yh - 0.2, z)), Vector((x1 + 0.08, yl - 0.12, z)), 0.12, 0.15, Vector((0, 1, 0)), ch=0.015)
        k.prism('timber', Vector((x1 + 0.08, yl - 0.08, z0 - 0.2)), Vector((x1 + 0.08, yl - 0.08, z1 + 0.2)), 0.18, 0.16, Vector((1, 0, 0)), ch=0.02)
        k.prism('timber', Vector((x0 - 0.05, yh - 0.12, z0 - 0.2)), Vector((x0 - 0.05, yh - 0.12, z1 + 0.2)), 0.16, 0.12, Vector((-1, 0, 0)), ch=0.015)
        th = math.atan2(yh - yl, abs(x1 - x0) + 0.3)
        n = Vector((-math.sin(th), math.cos(th), 0)); down = Vector((-math.cos(th), -math.sin(th), 0))
        top = Vector((x0, yh + 0.02, 0)); eave = top + down * ((abs(x1 - x0) + 0.35) / math.cos(th))
        L = (eave - top).length
        mid = (top + eave) / 2 - n * 0.04
        k.prism('wood', mid + Vector((0, 0, z0 - 0.3)), mid + Vector((0, 0, z1 + 0.3)), L, 0.07, n, ch=0.0)
        for zz in (z0 - 0.28, z1 + 0.28):
            k.prism('wood', top + Vector((0, 0.03, zz)), eave + Vector((0, 0.03, zz)), 0.22, 0.04, Vector((0, 0, 1)), ch=0.005)
        self.meta['roof'] += [list(eave + Vector((0, 0, z0 - 0.3))) + [0, 0, 1] + list(-down) + [z1 - z0 + 0.6, L]]
        # stacked firewood: split logs, ends facing out
        for row in range(6):
            for i in range(int((z1 - z0 - 0.2) / 0.19)):
                z = z0 + 0.15 + i * 0.19 + (row % 2) * 0.09; y = 0.12 + row * 0.17
                if z > z1 - 0.05: continue
                rad = r.uniform(0.07, 0.095)
                c = Vector((x1 + 0.62 + r.uniform(-0.03, 0.03), y, z))
                self.log(c, rad, 0.95)
        # chopping block + axe-less stump
        self.log(Vector((x1 + 0.2, 0.2, z1 + 0.55)), 0.24, 0.42, vertical=True)

    def log(self, c, rad, length, vertical=False):
        k = self.k; r = self.r
        if vertical:
            k.lathe('timber', c - UP * length / 2, [(rad, 0), (rad * 1.02, length * 0.5), (rad, length), (0, length + 0.005)], seg=9, uv=(0.5, 1.0))
            return
        ax = Vector((1, 0, 0)); a = c - ax * length / 2; b = c + ax * length / 2
        k.prism('timber', a, b, rad * 1.8, rad * 1.8, Vector((0, 1, 0)).lerp(Vector((0, 0, 1)), r.random()), ch=rad * 0.55, uv=(0.5, 2.0))

    # ------------------------------------------------------------------ grime mask
    def grime(self, p, name):
        y = p.y
        if name == 'plaster':
            g = 0.85 * sstep(1.55, Y0 + 0.02, y)
            if abs(abs(p.x) - HW) < 0.05 and y > YT - 1.2: g = max(g, 0.55 * sstep(YT - 1.1, YT + 0.1, y))
            if abs(abs(p.z) - HD) < 0.05 and y > YT: g = max(g, 0.35 * sstep(YT + 0.4, self.gable_top(p.x), y))
            for (face, uc, ww) in self.win_list:
                o, U, N, half = FACES[face]
                q = p - o; u = q.dot(U); n = q.dot(N)
                if abs(n) < 0.05 and abs(u - uc) < ww / 2 + 0.05 and WIN_Y0 - 1.0 < y < WIN_Y0:
                    g = max(g, 0.4 * (1 - (WIN_Y0 - y) / 1.0))
            return g
        if name == 'stone':
            g = 0.7 * sstep(0.45, -0.25, y)
            if y > self.YR: g = max(g, 0.9 * sstep(self.YR + 0.5, self.YR + 1.1, y))
            return g
        if name in ('timber', 'wood', 'door', 'paint'): return 0.6 * sstep(1.3, Y0, y)
        if name == 'iron': return 0.3
        return 0.0

    def build(self):
        self.plan_openings(); self.walls(); self.plinth(); self.frame(); self.windows(); self.door(); self.roof(); self.chimney()
        if self.v['lean']: self.leanto()
        objs = self.k.build(self.key)
        return objs


def plant_bed(k, r, at, n, leaves=(6, 9), scale=1.0):
    """a planting of leafy rosettes (double-sided leaf blades) with clustered flower heads; at(t, q) -> soil point"""
    B = k.bin('flora')
    palettes = [(0.93, 0.36, 0.5), (0.98, 0.8, 0.32), (0.96, 0.95, 0.9), (0.97, 0.5, 0.26), (0.7, 0.5, 0.96), (0.52, 0.72, 0.98), (0.88, 0.2, 0.22)]
    pal = r.sample(palettes, 2)
    for i in range(n):
        t = (i + r.uniform(0.2, 0.8)) / n; q = r.uniform(-1, 1)
        p = at(t, q)
        g0 = (0.16 + r.uniform(-0.03, 0.04), 0.33 + r.uniform(-0.06, 0.06), 0.11 + r.uniform(-0.03, 0.03))
        for j in range(r.randint(*leaves)):
            ang = r.uniform(0, 2 * math.pi); tilt = r.uniform(0.3, 1.25)
            Ll = r.uniform(0.08, 0.14) * scale; wl = Ll * r.uniform(0.4, 0.6)
            d = Vector((math.sin(tilt) * math.cos(ang), math.cos(tilt), math.sin(tilt) * math.sin(ang)))
            side = d.cross(UP); side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
            base = p + Vector((r.uniform(-0.02, 0.02), 0.0, r.uniform(-0.02, 0.02)))
            mid = base + d * Ll * 0.5 + UP * Ll * 0.08
            tip = base + d * Ll - UP * Ll * 0.3 * math.sin(tilt)
            sh = r.uniform(0.85, 1.15)
            cb = tuple(c * 0.55 for c in g0); cm = tuple(min(1, c * sh) for c in g0); ct = tuple(min(1, c * sh * 1.2) for c in g0)
            ids = [B.vert(base, 0.5, col=cb), B.vert(mid + side * wl / 2, 0.5, col=cm), B.vert(tip, 0.5, col=ct), B.vert(mid - side * wl / 2, 0.5, col=cm)]
            B.face(ids, [(0, 0), (1, 0.5), (0.5, 1), (0, 0.5)], outward=side.cross(d) if side.cross(d).y > 0 else d.cross(side))
        for j in range(r.randint(1, 2)):
            fc = pal[r.randrange(2)]; fc = tuple(min(1, c * r.uniform(0.85, 1.05)) for c in fc)
            c = p + Vector((r.uniform(-0.05, 0.05), r.uniform(0.09, 0.15) * scale, r.uniform(-0.05, 0.05)))
            fn = (UP * 1.0 + Vector((r.uniform(-0.5, 0.5), 0, r.uniform(-0.5, 0.5)))).normalized()
            a1 = fn.orthogonal().normalized(); a2 = fn.cross(a1)
            for kk in range(2):                                # a pair of small 4-petal florets
                cc = c + a1 * r.uniform(-0.025, 0.025) + a2 * r.uniform(-0.025, 0.025) + fn * r.uniform(0, 0.012)
                ctr = B.vert(cc + fn * 0.004, 0.5, col=tuple(x * 0.8 for x in fc))
                ring = []
                for m_ in range(8):
                    ang = m_ / 8 * 2 * math.pi + kk; rad = (0.03 if m_ % 2 == 0 else 0.012) * r.uniform(0.85, 1.15) * (1 + (scale - 1) * 0.5)
                    ring.append(B.vert(cc + (a1 * math.cos(ang) + a2 * math.sin(ang)) * rad, 0.5, col=fc))
                for m_ in range(8):
                    B.face([ctr, ring[m_], ring[(m_ + 1) % 8]], [(0.5, 0.5), (0, 0), (1, 0)], outward=fn)


def clip_below(poly, f):
    """clip polygon [(u, y)] to y <= f(u) (f linear on the polygon's u-range)"""
    out = []
    n = len(poly)
    for i in range(n):
        a = poly[i]; b = poly[(i + 1) % n]
        ia = a[1] <= f(a[0]) + 1e-6; ib = b[1] <= f(b[0]) + 1e-6
        if ia: out.append(a)
        if ia != ib:
            # solve for t where y(t) = f(u(t))
            lo, hi = 0.0, 1.0
            for _ in range(40):
                t = (lo + hi) / 2; u = a[0] + (b[0] - a[0]) * t; y = a[1] + (b[1] - a[1]) * t
                if (y <= f(u)) == ia: lo = t
                else: hi = t
            t = (lo + hi) / 2
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def rot_for(face, extra=0.0):
    return (0, {'front': 0.0, 'back': math.pi, 'right': math.pi / 2, 'left': -math.pi / 2}[face] + extra, 0)


# ------------------------------------------------------------------ kit extension: leafy blobs with painted colour
def _blob(self, mat, c, size, col, seed=0, sub=1, rough=0.3):
    B = self.bin(mat); r = random.Random(seed)
    import bmesh
    from mathutils import noise
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    off = Vector((r.random() * 40, r.random() * 40, r.random() * 40))
    ids = {}
    for v in bm.verts:
        p = v.co.copy(); d = 1 + rough * noise.noise(p * 2.2 + off)
        p = Vector((p.x * size[0], max(p.y, -0.3) * size[1], p.z * size[2])) * d
        shade = 0.75 + 0.25 * max(0.0, v.co.y)
        ids[v.index] = B.vert(Vector(c) + p, 0.5, col=(col[0] * shade, col[1] * shade, col[2] * shade))
    for f in bm.faces:
        idx = [ids[v.index] for v in f.verts]
        fc = sum((B.V[i] for i in idx), Vector()) / len(idx)
        B.face(idx, [(0, 0)] * len(idx), outward=fc - Vector(c))
    bm.free()


K.Kit.blob = _blob


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    allobjs = []
    for key in ('A', 'B', 'C'):
        h = House(key)
        objs = h.build()
        g = K.ground_plane(60, 0.0)
        K.bake_colors(objs, occluders=[g], rays=20, dist=1.3, grime_fn=h.grime, skip_ao=('glass', 'glow'))
        bpy.data.objects.remove(g)
        for o in objs: K.material(o, 'arch_' + o['bin'])
        meta = bpy.data.objects.new(f'{key}_meta', None); bpy.context.scene.collection.objects.link(meta)
        meta['roof'] = [x for pl in h.meta['roof'] for x in pl]
        meta['ridge'] = [x for pl in h.meta['ridge'] for x in pl]
        meta['smoke'] = [x for pl in h.meta['smoke'] for x in pl]
        meta['top'] = h.meta['top']
        print(key, 'tris', K.tris(objs), {o['bin']: K.tris([o]) for o in objs})
        # glTF is +Y up from Blender's Z; meta was written in game coordinates directly
        for o in objs: o.location.x += 0
        allobjs += objs + [meta]
    path = K.export(os.path.join(OUT, 'houses.glb'), allobjs)
    print('wrote', path, os.path.getsize(path))


if __name__ == '__main__':
    main()
