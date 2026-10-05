#!/usr/bin/env python3
"""Rebuild a 광안리 임시 스튜디오 player HTML with changed / added scripts.

  python3 tools/repack.py BASE.html OUT.html [--scripts scripts] [--label "1.0 v2.1"]

Every file under scripts/ is one script, its path = the instance path under the DataModel:
  scripts/ReplicatedStorage/GwangalliMindShared.luau            -> ModuleScript
  scripts/ServerScriptService/GwangalliGameplay/Mind.luau       -> ModuleScript
  scripts/StarterPlayer/StarterPlayerScripts/Foo.client.luau    -> LocalScript
  scripts/ServerScriptService/Foo.server.luau                   -> Script
An existing script at that path gets the new Source; a missing one is appended as a new instance
(its parent must exist). Idempotent: running it on its own output gives the same place.
"""
import base64, gzip, json, os, re, sys, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gwpb import Place, enc_vi

SCRIPT_CLASSES = ('Script', 'LocalScript', 'ModuleScript')

def read_pack(html, name):
    m = re.search(r'(<script type="application/x-gw-pack" id="gw-pack-%s">)(.*?)(</script>)' % name, html, re.S)
    raw = gzip.decompress(base64.b64decode(m.group(2)))
    assert raw[:4] == b'GWPK'
    hl = int.from_bytes(raw[4:8], 'little'); hdr = json.loads(raw[8:8 + hl]); base = 8 + hl
    files = {f['n']: raw[base + f['o']: base + f['o'] + f['l']] for f in hdr}
    return m, files

def write_pack(files):
    hdr, body, o = [], bytearray(), 0
    for n, b in files.items():
        hdr.append({'n': n, 'o': o, 'l': len(b)}); body += b; o += len(b)
    hj = json.dumps(hdr, separators=(',', ':')).encode()
    raw = b'GWPK' + len(hj).to_bytes(4, 'little') + hj + bytes(body)
    gz = gzip.compress(raw, 9, mtime=0)
    return raw, gz, base64.b64encode(gz).decode()

def collect(scripts_dir):
    out = []
    for root, _, fs in os.walk(scripts_dir):
        for f in sorted(fs):
            if not f.endswith('.luau'):
                continue
            full = os.path.join(root, f)
            rel = os.path.relpath(full, scripts_dir).replace(os.sep, '/')[:-5]
            cls = 'ModuleScript'
            if rel.endswith('.client'):
                cls, rel = 'LocalScript', rel[:-7]
            elif rel.endswith('.server'):
                cls, rel = 'Script', rel[:-7]
            out.append(('DataModel/' + rel, cls, open(full, 'rb').read()))
    return out

def rebuild(data, changes):
    P = Place(data)
    S = list(P.S)
    sidx = {}
    for i, s in enumerate(S):
        sidx.setdefault(s, i)
    def sref(b):
        if b in sidx:
            return sidx[b]
        S.append(b); sidx[b] = len(S) - 1; return len(S) - 1
    # path -> id (script-bearing tree only: everything under the services)
    path_of = {}
    children = {}
    for i in range(1, len(P.inst)):
        it = P.inst[i]
        children.setdefault(it['parent'], []).append(i)
    def find(path):
        parts = path.split('/')
        cur = [i for i in children.get(0, []) if P.s(P.inst[i]['name']) == parts[0]]
        if not cur:
            return None
        node = cur[0]
        for name in parts[1:]:
            nxt = None
            for c in children.get(node, []):
                if P.s(P.inst[c]['name']) == name:
                    # prefer a script when a folder shares the name (LocalScript + Folder pattern)
                    if nxt is None:
                        nxt = c
            node = nxt
            if node is None:
                return None
        return node
    def find_script(path, cls):
        parts = path.split('/')
        parent = find('/'.join(parts[:-1]))
        if parent is None:
            return None, None
        for c in children.get(parent, []):
            it = P.inst[c]
            if P.s(it['name']) == parts[-1] and P.s(it['cls']) == cls:
                return parent, c
        return parent, None
    src_shape = None
    for k, names in enumerate(P.shapes):
        if names and [P.s(x) for x in names] == ['Source']:
            src_shape = k; break
    assert src_shape
    replaced, added = [], []
    new_records = []
    next_id = len(P.inst)
    edits = {}
    pending = {}  # path -> new instance id (scripts added in this run can parent later ones)
    for path, cls, src in changes:
        ppath = '/'.join(path.split('/')[:-1])
        if ppath in pending:
            parent, sid = pending[ppath], None
        else:
            parent, sid = find_script(path, cls)
        if parent is None:
            raise SystemExit('parent missing for ' + path)
        if sid is not None:
            it = P.inst[sid]
            assert it['shape'] and 'Source' in [P.s(x) for x in P.shapes[it['shape']]], path
            edits[sid] = sref(src)
            replaced.append(path)
        else:
            rec = enc_vi(sref(cls.encode())) + enc_vi(sref(path.split('/')[-1].encode())) + enc_vi(next_id - parent) + enc_vi(src_shape)
            rec += b'\x00\x06' + enc_vi(sref(src)) + b'\x00\x00'
            new_records.append(rec); added.append(path); pending[path] = next_id; next_id += 1
    # serialise: header (strings), then everything from meta up to the instance count verbatim,
    # instance records (edited ones re-encoded), appended records, the tail.
    out = bytearray(data[:8])
    out += enc_vi(len(S))
    for s in S:
        out += enc_vi(len(s)) + s
    out += data[P.after_strings:P.inst_start]
    out += enc_vi(len(P.inst) - 1 + len(new_records))
    for i in range(1, len(P.inst)):
        it = P.inst[i]
        if i in edits:
            body = enc_vi(it['cls']) + enc_vi(it['name']) + enc_vi(i - it['parent'] if it['parent'] else 0) + enc_vi(it['shape'])
            names = [P.s(x) for x in P.shapes[it['shape']]]
            for nm, (ref, vp, ve) in zip(names, it['props']):
                if nm == 'Source':
                    body += b'\x00\x06' + enc_vi(edits[i])
                elif ref:
                    body += enc_vi(ref)
                else:
                    body += b'\x00' + data[vp:ve]
            # attributes + tags follow the last property verbatim
            tail_start = it['props'][-1][2] if it['props'][-1][0] == 0 else None
            if tail_start is None:
                # last prop was a pool ref: the attrs start right after its varint; re-read the record
                r = __import__('gwpb').Reader(data); r.p = it['start']
                for _ in range(4): r.vi()
                for (ref2, vp2, ve2) in it['props']:
                    v = r.vi()
                    if v == 0: r.skip()
                tail_start = r.p
            out += body + data[tail_start:it['end']]
        else:
            out += data[it['start']:it['end']]
    for r in new_records:
        out += r
    out += data[P.inst_end:]
    return bytes(out), replaced, added

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('base'); ap.add_argument('out')
    ap.add_argument('--scripts', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts'))
    ap.add_argument('--label', default=None)
    ap.add_argument('--emulator', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'emulator'),
                    help='files that replace entries of the "core" pack (engine/*.luau, js/*.js): emulator fixes')
    a = ap.parse_args()
    html = open(a.base, encoding='utf-8').read()
    m, files = read_pack(html, 'place')
    changes = collect(a.scripts)
    # parents first (a new module folder script before its children)
    changes.sort(key=lambda c: c[0].count('/'))
    data, replaced, added = rebuild(files['place.bin'], changes)
    Place(data)  # re-parse: structure check
    files['place.bin'] = data
    raw, gz, b64 = write_pack(files)
    html = html[:m.start(2)] + b64 + html[m.end(2):]
    mm = re.search(r'<script id="gw-manifest" type="application/json">(.*?)</script>', html, re.S)
    man = json.loads(mm.group(1))
    man['packs']['place']['raw'] = len(raw); man['packs']['place']['gz'] = len(gz)
    man['place']['scripts'] = man['place'].get('scripts', 0) + len(added)
    man['place']['instances'] = man['place'].get('instances', 0) + len(added)
    if a.label:
        old = man.get('label')
        man['label'] = a.label
        if old:
            html = html.replace(old, a.label)
    js = json.dumps(man, ensure_ascii=False, separators=(',', ':'))
    mm = re.search(r'<script id="gw-manifest" type="application/json">(.*?)</script>', html, re.S)
    html = html[:mm.start(1)] + js + html[mm.end(1):]
    # emulator (player shell) fixes: same file names as in the core pack
    core_changed = []
    if a.emulator and os.path.isdir(a.emulator):
        mc, cfiles = read_pack(html, 'core')
        for root, _, fs in os.walk(a.emulator):
            for f in sorted(fs):
                full = os.path.join(root, f)
                rel = os.path.relpath(full, a.emulator).replace(os.sep, '/')
                if rel in cfiles:
                    new = open(full, 'rb').read()
                    if new != cfiles[rel]:
                        cfiles[rel] = new
                        core_changed.append(rel)
        if core_changed:
            craw, cgz, cb64 = write_pack(cfiles)
            html = html[:mc.start(2)] + cb64 + html[mc.end(2):]
            mm = re.search(r'<script id="gw-manifest" type="application/json">(.*?)</script>', html, re.S)
            man = json.loads(mm.group(1))
            man['packs']['core']['raw'] = len(craw); man['packs']['core']['gz'] = len(cgz)
            js = json.dumps(man, ensure_ascii=False, separators=(',', ':'))
            html = html[:mm.start(1)] + js + html[mm.end(1):]
    open(a.out, 'w', encoding='utf-8').write(html)
    for p in core_changed: print('  * core', p)
    print('replaced %d, added %d -> %s (%.1f MB)' % (len(replaced), len(added), a.out, len(html) / 1e6))
    for p in replaced: print('  ~', p)
    for p in added: print('  +', p)

if __name__ == '__main__':
    main()
