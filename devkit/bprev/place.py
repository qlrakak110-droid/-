# Place access for the building preview: decoded props (UDim2, Vector2, FontFace), world AABB index (cached)
import sys, os, struct, pickle, math
SP = '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
sys.path.insert(0, SP + '/tools')
from gwpb import GWPB

BASE = ('Part', 'WedgePart', 'CornerWedgePart', 'Seat', 'VehicleSeat', 'MeshPart', 'TrussPart', 'SpawnLocation', 'UnionOperation')

class Place(GWPB):
    def val(self, at):
        save = self.p; self.p = at
        u8 = self.u8; tag = u8[self.p]; self.p += 1
        f = lambda o: struct.unpack_from('<f', u8, o)[0]
        try:
            if tag == 8: return ('V2', f(self.p), f(self.p + 4))
            if tag == 12:
                s = f(self.p); self.p += 4; o = self.vi(); return ('UD', s, (o >> 1) ^ -(o & 1))
            if tag == 13:
                sx = f(self.p); self.p += 4; ox = self.vi(); sy = f(self.p); self.p += 4; oy = self.vi()
                return ('UD2', sx, (ox >> 1) ^ -(ox & 1), sy, (oy >> 1) ^ -(oy & 1))
            if tag == 20:
                a = self.vi(); b = self.vi(); c = self.vi(); return ('Font', self.s(a), b, c)
            if tag == 19:
                a = self.vi(); b = self.vi(); return ('Enum', self.s(a), self.s(b))
            if tag == 15: return ('NR', f(self.p), f(self.p + 4))
            if tag == 17:
                k = self.vi(); out = []
                for i in range(k):
                    o = self.p + i * 16; out.append((f(o), f(o + 4), f(o + 8), f(o + 12)))
                return ('CS', out)
        finally:
            self.p = save
        return GWPB.val(self, at)

    def __init__(self, path=SP + '/v7place/place.bin'):
        GWPB.__init__(self, path)
        self.kids = {}
        for i in self.inst[1:]:
            self.kids.setdefault(i['parent'], []).append(i['id'])

    def P(self, iid, name, default=None):
        v = self.prop(self.inst[iid], name)
        return default if v is None else v

    def path(self, iid):
        out = []
        while iid:
            out.append(self.inst[iid]['name']); iid = self.inst[iid]['parent']
        return '/'.join(reversed(out))

    def desc(self, iid):
        out = []; st = [iid]
        while st:
            x = st.pop()
            for c in self.kids.get(x, []):
                out.append(c); st.append(c)
        return out

    def child(self, iid, name):
        for c in self.kids.get(iid, []):
            if self.inst[c]['name'] == name: return c

def aabb(cf, size):
    x, y, z, r = cf[1], cf[2], cf[3], cf[4]
    sx, sy, sz = size[1] / 2, size[2] / 2, size[3] / 2
    ex = abs(r[0]) * sx + abs(r[1]) * sy + abs(r[2]) * sz
    ey = abs(r[3]) * sx + abs(r[4]) * sy + abs(r[5]) * sz
    ez = abs(r[6]) * sx + abs(r[7]) * sy + abs(r[8]) * sz
    return (x - ex, y - ey, z - ez, x + ex, y + ey, z + ez)

_place = None
def load():
    global _place
    if _place is None:
        _place = Place()
    return _place

def index(G):
    cache = SP + '/bprev/aabb.pkl'
    if os.path.exists(cache):
        return pickle.load(open(cache, 'rb'))
    idx = []
    for i in G.inst[1:]:
        if i['cls'] in BASE:
            cf = G.prop(i, 'CFrame'); sz = G.prop(i, 'Size')
            if cf and sz and sz[0] == 'V3':
                idx.append((i['id'],) + aabb(cf, sz))
    pickle.dump(idx, open(cache, 'wb'))
    return idx
