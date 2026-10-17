"""Read / write the studio's GWPB place bundle (format: engine/loader.luau, slow path).

Values are kept as (tag, payload) where payload is raw bytes, except for the tags that embed
string-table indices (6 string, 19 enum, 20 font) or instance ids (25 ref); those are decoded so a
bundle can be re-encoded with a new string table / instance numbering.
"""
import struct

FIX = {0: 0, 1: 0, 2: 0, 3: 8, 4: 4, 7: 12, 8: 8, 10: 12, 11: 3, 14: 16, 15: 8, 21: 20, 22: 1, 23: 1, 24: 24, 28: 1}


class Reader:
    def __init__(self, buf):
        self.b = buf
        self.p = 0

    def vi(self):
        b = self.b[self.p]; self.p += 1
        if b < 128:
            return b
        v = b - 128; mul = 128
        while True:
            b = self.b[self.p]; self.p += 1
            if b < 128:
                return v + b * mul
            v += (b - 128) * mul; mul *= 128

    def raw_vi(self):
        s = self.p; self.vi(); return self.b[s:self.p]

    def value(self, strs):
        tag = self.b[self.p]; self.p += 1
        if tag in FIX:
            n = FIX[tag]; v = (tag, self.b[self.p:self.p + n]); self.p += n; return v
        if tag == 6:
            return (6, strs[self.vi()])
        if tag == 19:
            return (19, strs[self.vi()], strs[self.vi()])
        if tag == 20:
            return (20, strs[self.vi()], strs[self.vi()], strs[self.vi()])
        if tag == 25:
            return (25, self.vi())
        s = self.p
        if tag in (5, 18):
            self.vi()
        elif tag == 9:
            self.p += 49 if self.b[self.p + 12] == 0 else 13
        elif tag == 12:
            self.p += 4; self.vi()
        elif tag == 13:
            self.p += 4; self.vi(); self.p += 4; self.vi()
        elif tag == 16:
            n = self.vi(); self.p += n * 12
        elif tag == 17:
            n = self.vi(); self.p += n * 16
        elif tag == 26:
            self.vi(); self.vi(); self.vi()
        elif tag == 27:
            self.vi(); self.vi()
        else:
            raise ValueError("bad tag %d at %d" % (tag, self.p - 1))
        return (tag, self.b[s:self.p])


def read(buf):
    assert buf[:4] == b"GWPB" and buf[4] == 1
    r = Reader(buf); r.p = 8
    strs = []
    for _ in range(r.vi()):
        n = r.vi(); strs.append(buf[r.p:r.p + n].decode("utf-8", "surrogateescape")); r.p += n
    meta = strs[r.vi()]
    nrot = buf[r.p]; r.p += 1
    rot = buf[r.p:r.p + nrot * 9]; r.p += nrot * 9
    pool = [r.value(strs) for _ in range(r.vi())]
    shapes = []
    for _ in range(r.vi()):
        shapes.append([strs[r.vi()] for _ in range(r.vi())])
    insts = []
    for i in range(r.vi()):
        cls = strs[r.vi()]; name = strs[r.vi()]; pd = r.vi(); shape = r.vi()
        props = {}
        if shape:
            for pn in shapes[shape - 1]:
                ref = r.vi()
                props[pn] = r.value(strs) if ref == 0 else pool[ref - 1]
        attrs = {}
        for _ in range(r.vi()):
            an = strs[r.vi()]; attrs[an] = r.value(strs)
        tags = [strs[r.vi()] for _ in range(r.vi())]
        insts.append({"id": i + 1, "cls": cls, "name": name, "parent": (i + 1 - pd) if pd else 0,
                      "props": props, "attrs": attrs, "tags": tags})
    assert buf[r.p:r.p + 4] == b"END!", r.p
    return {"meta": meta, "rot": rot, "insts": insts}


def _vi(n):
    out = bytearray()
    while n >= 128:
        out.append(128 + (n % 128)); n //= 128
    out.append(n)
    return bytes(out)


def write(place):
    """place: {meta, rot, insts}; insts in tree order (parents first), ids 1..n, parent = id or 0."""
    strs, sidx = [], {}

    def s(x):
        if x not in sidx:
            sidx[x] = len(strs); strs.append(x)
        return sidx[x]

    shapes, shidx = [], {}
    body = bytearray()

    def val(v):
        tag = v[0]
        if tag == 6:
            return bytes([6]) + _vi(s(v[1]))
        if tag == 19:
            return bytes([19]) + _vi(s(v[1])) + _vi(s(v[2]))
        if tag == 20:
            return bytes([20]) + _vi(s(v[1])) + _vi(s(v[2])) + _vi(s(v[3]))
        if tag == 25:
            return bytes([25]) + _vi(v[1])
        return bytes([tag]) + bytes(v[1])

    meta_i = s(place["meta"])
    for inst in place["insts"]:
        body += _vi(s(inst["cls"])) + _vi(s(inst["name"]))
        body += _vi(inst["id"] - inst["parent"] if inst["parent"] else 0)
        names = tuple(inst["props"].keys())
        if names:
            if names not in shidx:
                shapes.append(names); shidx[names] = len(shapes)
            body += _vi(shidx[names])
            for pn in names:
                body += b"\x00" + val(inst["props"][pn])
        else:
            body += _vi(0)
        body += _vi(len(inst["attrs"]))
        for an, av in inst["attrs"].items():
            body += _vi(s(an)) + val(av)
        body += _vi(len(inst["tags"]))
        for tg in inst["tags"]:
            body += _vi(s(tg))
    shape_bytes = bytearray(_vi(len(shapes)))
    for names in shapes:
        shape_bytes += _vi(len(names))
        for pn in names:
            shape_bytes += _vi(s(pn))
    out = bytearray(b"GWPB" + bytes([1, 0, 0, 0]))
    out += _vi(len(strs))
    for x in strs:
        e = x.encode("utf-8", "surrogateescape"); out += _vi(len(e)) + e
    out += _vi(meta_i)
    out += bytes([len(place["rot"]) // 9]) + bytes(place["rot"])
    out += _vi(0)  # pool (all values inline)
    out += shape_bytes
    out += _vi(len(place["insts"])) + body + b"END!"
    return bytes(out)


# helpers to build values
def f32s(*xs):
    return struct.pack("<%df" % len(xs), *xs)


def V3(x, y, z):
    return (7, f32s(x, y, z))


def CF(x, y, z):
    return (9, f32s(x, y, z) + b"\x00" + f32s(1, 0, 0, 0, 1, 0, 0, 0, 1))


def RGB(r, g, b):
    return (11, bytes([r, g, b]))


def BOOL(v):
    return (2 if v else 1, b"")


def STR(x):
    return (6, x)


def ENUM(e, item):
    return (19, e, item)


def NUM(x):
    return (4, f32s(x))
