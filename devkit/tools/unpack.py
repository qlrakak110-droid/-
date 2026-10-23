import sys, re, base64, gzip, json, struct, os
src, out = sys.argv[1], sys.argv[2]
html = open(src, encoding='utf-8').read()
for m in re.finditer(r'<script type="application/x-gw-pack" id="gw-pack-(\w+)">([^<]*)</script>', html):
    name, text = m.group(1), m.group(2)
    raw = gzip.decompress(base64.b64decode(text))
    assert raw[:4] == b'GWPK'
    hl = struct.unpack('<I', raw[4:8])[0]
    header = json.loads(raw[8:8+hl].decode())
    base = 8 + hl
    for f in header:
        p = os.path.join(out, name, f['n'])
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'wb').write(raw[base+f['o']:base+f['o']+f['l']])
    print(name, len(header), 'files', len(raw), 'bytes', 'header keys', list(header[0].keys()))
