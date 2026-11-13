# Extract one averaged run cycle from a CMU mocap BVH (cgspeed conversion: Y up, the T-pose faces +Z, left = +X) and
# write it as phase curves for the heroes' run / sprint clips (src/rpg/core/clips/mocap_run.js).
#
#   python3 tools/mocap/extract_run.py tools/mocap/09_01.bvh
#
# Phase 0 = the right foot strikes (the same convention as locomotion.js). Curves are measured geometrically from joint
# positions and joint axes in a heading-aligned frame (x forward, y up, z right: the game's axes), so no rotation-order
# convention of the source survives into the game:
#   dy / sway / surge   pelvis height, lateral and fore-aft deviation from uniform travel (fractions of leg length)
#   pYaw pRoll pPitch   pelvis orientation (deg; yaw + = turned left, roll + = leaning right, pitch + = leaning forward)
#   tYaw tRoll tPitch   thorax orientation, hYaw hPitch = head
#   swingL abdL elbowL  left arm: shoulder swing (+ forward), abduction (+ away from the body), elbow flexion; R likewise
# Data: CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), subject 9 "run"; free for any use.
import sys, json, math, os
import numpy as np

src = sys.argv[1]
N = 16
L = open(src).read().split('\n')
joints, stack, i = [], [], 0
while not L[i].startswith('MOTION'):
    t = L[i].split()
    if t and t[0] in ('ROOT', 'JOINT'):
        joints.append(dict(name=t[1], parent=stack[-1] if stack else -1, ch=[])); cur = len(joints) - 1
    elif t and t[0] == 'End':
        joints.append(dict(name=joints[stack[-1]]['name'] + '_end', parent=stack[-1], ch=[], end=True)); cur = len(joints) - 1
    elif t and t[0] == '{': stack.append(cur)
    elif t and t[0] == '}': stack.pop()
    elif t and t[0] == 'OFFSET': joints[cur]['off'] = np.array(list(map(float, t[1:4])))
    elif t and t[0] == 'CHANNELS': joints[cur]['ch'] = t[2:]
    i += 1
nf = int(L[i + 1].split()[1]); dt = float(L[i + 2].split()[2])
D = np.array([list(map(float, l.split())) for l in L[i + 3:i + 3 + nf] if l.strip()])
idx = {j['name']: k for k, j in enumerate(joints)}


def rot(axis, deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return {'X': np.array([[1, 0, 0], [0, c, -s], [0, s, c]]), 'Y': np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]), 'Z': np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])}[axis]


P = np.zeros((nf, len(joints), 3)); R = np.zeros((nf, len(joints), 3, 3))
for f in range(nf):
    c = 0
    for k, j in enumerate(joints):
        Rl = np.eye(3); pos = j['off'].copy()
        for ch in j['ch']:
            v = D[f, c]; c += 1
            if ch.endswith('position'): pos['XYZ'.index(ch[0])] = v
            else: Rl = Rl @ rot(ch[0], v)
        if j['parent'] < 0: P[f, k], R[f, k] = pos, Rl
        else:
            p = j['parent']; P[f, k] = P[f, p] + R[f, p] @ pos; R[f, k] = R[f, p] @ Rl

hips = P[:, idx['Hips']]
h = hips[-1] - hips[0]; h[1] = 0; h /= np.linalg.norm(h)
right = np.array([-h[2], 0, h[0]])
G = np.stack([h, [0, 1, 0], right])            # bvh vector -> game axes
g = lambda v: v @ G.T
leg = np.linalg.norm(joints[idx['LeftLeg']]['off']) + np.linalg.norm(joints[idx['LeftFoot']]['off'])
speed = float(np.dot(hips[-1] - hips[0], h) / ((nf - 1) * dt))

# right foot strikes: the ankle is farthest ahead of the hips
ahead = (P[:, idx['RightFoot']] - hips) @ h
strikes = [f for f in range(2, nf - 2) if ahead[f] >= ahead[f - 1] and ahead[f] > ahead[f + 1] and ahead[f] > 0.6 * ahead.max()]
strikes = [s for k, s in enumerate(strikes) if k == 0 or s - strikes[k - 1] > 20]
assert len(strikes) >= 2, strikes


def axes(name, f):
    M = G @ R[f, idx[name]]                     # columns: joint x (left), y (up), z (forward) in game axes
    return M[:, 2], M[:, 1]                    # forward, up


def ypr(name, f):
    fw, up = axes(name, f)
    return np.array([math.degrees(math.atan2(-fw[2], fw[0])), math.degrees(math.atan2(up[2], up[1])), math.degrees(math.atan2(up[0], up[1]))])


def arm(side, f):
    sh, el, wr = (g(P[f, idx[side + n]]) for n in ('Arm', 'ForeArm', 'Hand'))
    fw, up = axes('Spine1', f)
    rt = np.cross(fw, up)
    u = (el - sh) / np.linalg.norm(el - sh); w = (wr - el) / np.linalg.norm(wr - el)
    swing = math.degrees(math.atan2(u @ fw, -(u @ up)))
    out = (u @ rt) * (1 if side == 'Right' else -1)
    return np.array([swing, math.degrees(math.asin(max(-1, min(1, out)))), math.degrees(math.acos(max(-1, min(1, u @ w))))])


def curves(a, b):
    """One cycle (frames a..b) resampled to N phases."""
    out = {}
    fr = np.arange(a, b + 1); ph = (fr - a) / (b - a)
    travel = (hips[fr] - hips[a]) @ h
    lin = travel[-1] * ph
    raw = dict(dy=(hips[fr, 1]) / leg, sway=(hips[fr] @ right) / leg, surge=(travel - lin) / leg)
    for nm, j in (('p', 'Hips'), ('t', 'Spine1'), ('h', 'Head')):
        A = np.array([ypr(j, f) for f in fr])
        raw[nm + 'Yaw'], raw[nm + 'Roll'], raw[nm + 'Pitch'] = A[:, 0], A[:, 1], A[:, 2]
    for s, side in (('L', 'Left'), ('R', 'Right')):
        A = np.array([arm(side, f) for f in fr])
        raw['swing' + s], raw['abd' + s], raw['elbow' + s] = A[:, 0], A[:, 1], A[:, 2]
    q = np.arange(N) / N
    for k, v in raw.items():
        v = v - (v[-1] - v[0]) * ph             # close the loop (drift over one cycle spread linearly)
        out[k] = np.interp(q, ph, v)
    return out, (b - a) * dt


cyc = [curves(strikes[k], strikes[k + 1]) for k in range(len(strikes) - 1)]
C = {k: np.mean([c[0][k] for c in cyc], axis=0) for k in cyc[0][0]}
T = float(np.mean([c[1] for c in cyc]))
# deviations for the translation / yaw channels (their means belong to the hero's own pose), smooth lightly (periodic)
for k in ('dy', 'sway', 'surge', 'pYaw', 'tYaw', 'hYaw', 'pRoll', 'tRoll'):
    C[k] = C[k] - C[k].mean()
for k in C:
    v = C[k]; C[k] = 0.25 * np.roll(v, 1) + 0.5 * v + 0.25 * np.roll(v, -1)
out = dict(source=os.path.basename(src), fps=round(1 / dt), cycles=len(cyc), period=round(T, 4), speed=round(speed * 0.0254 * 2.2, 3) if speed > 20 else round(speed, 3), n=N,
           **{k: [round(float(x), 4 if k in ('dy', 'sway', 'surge') else 2) for x in v] for k, v in C.items()})
js = ('// GENERATED by tools/mocap/extract_run.py from ' + out['source'] + ' (CMU Graphics Lab Motion Capture Database, subject 9 "run";\n'
      '// free for any use). One averaged run cycle as phase curves: phase 0 = the right foot strikes, n samples per cycle.\n'
      '// dy / sway / surge: pelvis deviation in leg lengths; angles in degrees (yaw + = left, roll + = right, pitch + = forward).\n'
      'export const MOCAP_RUN = ' + json.dumps(out, indent=1).replace('\n  ', ' ').replace('[ ', '[').replace('\n ]', ']') + ';\n')
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../src/rpg/core/clips/mocap_run.js')
open(dst, 'w').write(js)
print('strikes', strikes, 'cycles', len(cyc), 'period', round(T, 3), 'leg', round(leg, 2))
for k, v in C.items():
    print(f'{k:7s} min {v.min():8.3f} max {v.max():8.3f} mean {v.mean():8.3f}  argmax {int(v.argmax())} argmin {int(v.argmin())}')
