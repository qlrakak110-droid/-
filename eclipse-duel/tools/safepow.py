# One-off: make every GLSL pow() in src/ safe on mobile GPUs, where pow(x, y) with x < 0 (even -1e-9 from an
# interpolated varying) is NaN and one NaN pixel in the HDR buffer blooms into a white blob.
#   pow(X, 2.0)  ->  ((X) * (X))          pow(X, Y)  ->  pow(max(X, 0.0), Y)   (unless X is visibly >= 0 already)
import re, sys, pathlib
SAFE = re.compile(r'^\s*(abs|max|sat|saturate|clamp|exp|exp2|smoothstep|length|h11|h12|n01|fbm|step|fract|sqrt|dot2)\s*\(')
NUM = re.compile(r'^\s*[0-9.]+\s*$')
def args(s, i):
    # s[i] is the char after 'pow('; returns (list of top-level args, index after the closing paren)
    depth, start, out = 0, i, []
    while i < len(s):
        c = s[i]
        if c in '([': depth += 1
        elif c in ')]':
            if depth == 0: out.append(s[start:i]); return out, i + 1
            depth -= 1
        elif c == ',' and depth == 0: out.append(s[start:i]); start = i + 1
        i += 1
    return None, i
def whole(x):
    # is the SAFE call the whole expression (its closing paren is the last char)?
    m = SAFE.match(x)
    if not m: return False
    a, end = args(x, m.end())
    return a is not None and x[end:].strip() == ''
n = 0
for p in pathlib.Path('src').rglob('*.js'):
    s = p.read_text(); out = []; i = 0; changed = False
    for m in re.finditer(r'(?<![\w.])pow\(', s):
        if m.start() < i: continue
        a, end = args(s, m.end())
        if not a or len(a) != 2: continue
        x, y = a[0].strip(), a[1].strip()
        if '\n' in x or NUM.match(x): continue
        if y == '2.0': rep = f'(({x}) * ({x}))' if not re.match(r'^[\w.]+$', x) else f'({x} * {x})'
        elif whole(x): continue
        else: rep = f'pow(max({x}, 0.0), {y})'
        out.append(s[i:m.start()]); out.append(rep); i = end; changed = True; n += 1
    if changed:
        out.append(s[i:]); p.write_text(''.join(out)); print(p)
print(n, 'pow() calls rewritten')
