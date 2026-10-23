import struct, json, sys, os
class GWPB:
    FIX = {0:0,1:0,2:0,3:8,4:4,7:12,8:8,10:12,11:3,14:16,15:8,21:20,22:1,23:1,24:24,28:1}
    def __init__(self, path):
        self.u8 = u8 = open(path,'rb').read()
        assert u8[:4] == b'GWPB'
        self.p = 8
        n = self.vi(); self.STR = []
        for i in range(n):
            l = self.vi(); self.STR.append(u8[self.p:self.p+l]); self.p += l
        self.meta = self.vi()
        nrot = u8[self.p]; self.p += 1
        self.ROT = []
        for i in range(nrot):
            self.ROT.append([b-256 if b>127 else b for b in u8[self.p:self.p+9]]); self.p += 9
        npool = self.vi(); self.poolPos = []
        for i in range(npool): self.poolPos.append(self.p); self.skip()
        ns = self.vi(); self.SHAPES = [None]
        for i in range(ns):
            k = self.vi(); self.SHAPES.append([self.s(self.vi()) for _ in range(k)])
        ni = self.vi(); self.inst = [None]
        for iid in range(1, ni+1):
            cls = self.vi(); name = self.vi(); pd = self.vi(); shape = self.vi()
            parent = iid - pd if pd else 0
            props = {}
            if shape:
                names = self.SHAPES[shape]
                for k in range(len(names)):
                    r = self.vi()
                    if r == 0: props[names[k]] = ('at', self.p); self.skip()
                    else: props[names[k]] = ('at', self.poolPos[r-1])
            na = self.vi(); attrs = {}
            for k in range(na):
                an = self.s(self.vi()); attrs[an] = self.p; self.skip()
            nt = self.vi(); tags = [self.s(self.vi()) for _ in range(nt)]
            self.inst.append(dict(id=iid, cls=self.s(cls), name=self.s(name), parent=parent, props=props, attrs=attrs, tags=tags))
        assert u8[self.p:self.p+4] == b'END!', self.p
    def s(self, i): return self.STR[i].decode('utf-8', 'replace')
    def vi(self):
        u8 = self.u8; b = u8[self.p]; self.p += 1
        if b < 128: return b
        v = b & 127; mul = 128
        while True:
            b = u8[self.p]; self.p += 1
            if b < 128: return v + b*mul
            v += (b & 127)*mul; mul *= 128
    def skip(self):
        tag = self.u8[self.p]; self.p += 1
        if tag in self.FIX: self.p += self.FIX[tag]; return
        if tag in (5,6,18,25): self.vi()
        elif tag == 9: self.p += 49 if self.u8[self.p+12] == 0 else 13
        elif tag == 12: self.p += 4; self.vi()
        elif tag == 13: self.p += 4; self.vi(); self.p += 4; self.vi()
        elif tag == 16: k = self.vi(); self.p += k*12
        elif tag == 17: k = self.vi(); self.p += k*16
        elif tag in (19,27): self.vi(); self.vi()
        elif tag in (20,26): self.vi(); self.vi(); self.vi()
        else: raise Exception('bad tag %d at %d' % (tag, self.p-1))
    def val(self, at):
        save = self.p; self.p = at
        u8 = self.u8; tag = u8[self.p]; self.p += 1
        f = lambda o: struct.unpack_from('<f', u8, o)[0]
        try:
            if tag == 0: return None
            if tag == 1: return False
            if tag == 2: return True
            if tag == 3: return struct.unpack_from('<d', u8, self.p)[0]
            if tag == 4: return f(self.p)
            if tag == 5: v = self.vi(); return (v >> 1) ^ -(v & 1)
            if tag == 6: return self.s(self.vi())
            if tag == 7: return ('V3', f(self.p), f(self.p+4), f(self.p+8))
            if tag == 9:
                x,y,z = f(self.p), f(self.p+4), f(self.p+8); rc = u8[self.p+12]
                m = [f(self.p+13+4*k) for k in range(9)] if rc == 0 else self.ROT[rc-1]
                return ('CF', x,y,z, m)
            if tag == 10: return ('C3', f(self.p), f(self.p+4), f(self.p+8))
            if tag == 11: return ('C3', u8[self.p]/255, u8[self.p+1]/255, u8[self.p+2]/255)
            if tag == 18: return ('BC', self.vi())
            if tag == 19: a = self.vi(); b = self.vi(); return ('Enum', self.s(a), b)
            if tag == 25: return ('Ref', self.vi())
            return ('tag', tag)
        finally:
            self.p = save
    def prop(self, inst, name):
        v = inst['props'].get(name)
        return self.val(v[1]) if v else None
    def path(self, iid):
        parts = []
        while iid:
            i = self.inst[iid]; parts.append(i['name']); iid = i['parent']
        return '/'.join(reversed(parts))
