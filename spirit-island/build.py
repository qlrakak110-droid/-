#!/usr/bin/env python3
"""Bundles spirit-island/src/*.js into one self-contained HTML page.

    python3 spirit-island/build.py            -> spirit-island/index.html (open directly in a browser)
    python3 spirit-island/build.py --fragment <out.html>   -> page body without the <html>/<head> wrapper
"""
import os, sys, glob

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'src')


def bundle():
    parts = []
    for p in sorted(glob.glob(os.path.join(SRC, '*.js'))):
        with open(p, encoding='utf-8') as f:
            parts.append('// ---- %s ----\n%s' % (os.path.basename(p), f.read()))
    js = '\n'.join(parts)
    with open(os.path.join(SRC, 'template.html'), encoding='utf-8') as f:
        tpl = f.read()
    if '</script' in js:
        raise SystemExit('bundle must not contain </script')
    return tpl.replace('/*__BUNDLE__*/', js)


def main():
    body = bundle()
    if len(sys.argv) > 2 and sys.argv[1] == '--fragment':
        with open(sys.argv[2], 'w', encoding='utf-8') as f:
            f.write(body)
        print('wrote', sys.argv[2], len(body), 'bytes')
        return
    page = ('<!doctype html>\n<html lang="ko">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">\n'
            + body + '\n</html>\n')
    out = os.path.join(HERE, 'index.html')
    with open(out, 'w', encoding='utf-8') as f:
        f.write(page)
    print('wrote', out, len(page), 'bytes')


if __name__ == '__main__':
    main()
