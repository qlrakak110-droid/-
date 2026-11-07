#!/usr/bin/env python3
"""Makes an *empty-place* copy of the 광안리 임시 스튜디오 player (engine + renderer only) used to preview
the Seoul skyline map headless (tools/preview.js) and to build the playable HTML (tools/make_studio.py).

    python3 seoul-skyline/tools/make_preview_studio.py [source studio.html] [out.html]

default source: dist/Gwangalli_Studio_1.0_v2.0_MiniGames.html, default out: seoul-skyline/tools/studio_empty.html
The Gwangalli place/static packs and the MiniGames injector are removed; the engine boots an empty DataModel.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, 'dist', 'Gwangalli_Studio_1.0_v2.0_MiniGames.html')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'studio_empty.html')
    html = open(src, encoding='utf-8').read()
    html = re.sub(r'<script type="application/x-gw-pack" id="gw-pack-place">.*?</script>\n?', '', html, flags=re.S)
    html = re.sub(r'<script type="application/x-gw-pack" id="gw-pack-static">.*?</script>\n?', '', html, flags=re.S)
    html = re.sub(r'<script>\n/\* 광안리 해변 미니게임 거리: injects.*?</script>\n', '', html, flags=re.S)
    m = re.search(r'(<script id="gw-manifest" type="application/json">)(.*?)(</script>)', html, re.S)
    man = json.loads(m.group(2))
    man['packs'].pop('place', None)
    man['packs'].pop('static', None)
    man['place'] = {'instances': 0, 'parts': 0, 'scripts': 0}
    man['label'] = 'Seoul Skyline'
    html = html[:m.start(2)] + json.dumps(man, ensure_ascii=False) + html[m.end(2):]
    open(out, 'w', encoding='utf-8').write(html)
    print(out, len(html))


if __name__ == '__main__':
    main()
