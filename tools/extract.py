#!/usr/bin/env python3
"""Dump every script of a 광안리 임시 스튜디오 player HTML into a folder tree (repack.py's layout).

  python3 tools/extract.py BASE.html OUT_DIR [--emulator EMU_DIR]

ModuleScript -> Name.luau, LocalScript -> Name.client.luau, Script -> Name.server.luau, under the
instance path (DataModel/ dropped). --emulator also dumps the core pack (engine luau / js modules).
"""
import os, sys, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gwpb import Place
from repack import read_pack

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('base'); ap.add_argument('out'); ap.add_argument('--emulator')
    a = ap.parse_args()
    html = open(a.base, encoding='utf-8').read()
    _, files = read_pack(html, 'place')
    P = Place(files['place.bin'])
    n = 0
    for i in range(1, len(P.inst)):
        it = P.inst[i]
        cls = P.s(it['cls'])
        if cls not in ('Script', 'LocalScript', 'ModuleScript'):
            continue
        si = P.strval(P.prop(i, 'Source'))
        src = P.S[si] if si is not None else b''
        parts = P.path(i).split('/')
        if parts and parts[0] == 'DataModel':
            parts = parts[1:]
        ext = {'Script': '.server.luau', 'LocalScript': '.client.luau', 'ModuleScript': '.luau'}[cls]
        p = os.path.join(a.out, *parts[:-1], parts[-1].replace('/', '_') + ext)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'wb') as f:
            f.write(src)
        n += 1
    if a.emulator:
        _, core = read_pack(html, 'core')
        for name, b in core.items():
            p = os.path.join(a.emulator, name)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, 'wb').write(b)
    print(n, 'scripts ->', a.out)

if __name__ == '__main__':
    main()
