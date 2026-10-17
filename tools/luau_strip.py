#!/usr/bin/env python3
"""Luau 소스에서 주석 · 빈 줄 · 줄 앞 들여쓰기를 걷어 냅니다 (문자열 · 긴 문자열 · `보간 문자열` 은 그대로).

    strip(text) -> text       줄 수와 문장 경계는 바뀌지 않음 (줄을 합치지 않음: "ambiguous syntax" 걱정 없음)

tools/bundle_plus.py 가 씁니다. --verify 로 luau-ast 결과(위치 정보 제외)가 같은지 확인할 수 있습니다:
    python3 tools/luau_strip.py --verify path/to/luau-ast file.luau ...
"""
import json
import re
import subprocess
import sys

LONG_OPEN = re.compile(r"\[(=*)\[")


def _long_end(text, i, eq):
    close = "]" + eq + "]"
    j = text.find(close, i)
    if j < 0:
        raise ValueError("unterminated long bracket")
    return j + len(close)


def _short_string_end(text, i, q):
    # text[i] == q ; returns index after the closing quote
    n = len(text)
    j = i + 1
    while j < n:
        c = text[j]
        if c == "\\":
            if text.startswith("\\z", j):
                j += 2
                continue
            j += 2
            continue
        if c == q:
            return j + 1
        if c == "\n" and q != "`":
            raise ValueError("newline in string at %d" % j)
        if q == "`" and c == "{":
            j = _code_until_brace(text, j + 1)
            continue
        j += 1
    raise ValueError("unterminated string")


def _code_until_brace(text, i):
    # inside `...{ expr }...` : skip a balanced expression, return index after the matching }
    depth = 0
    n = len(text)
    j = i
    while j < n:
        c = text[j]
        if c in "\"'`":
            j = _short_string_end(text, j, c)
            continue
        if c == "[":
            m = LONG_OPEN.match(text, j)
            if m:
                j = _long_end(text, m.end(), m.group(1))
                continue
        if c == "{":
            depth += 1
        elif c == "}":
            if depth == 0:
                return j + 1
            depth -= 1
        j += 1
    raise ValueError("unterminated interpolation")


def strip(text):
    # 문자열 · 긴 문자열은 자리표시(\x00N\x00)로 빼 두고 주석을 지운 다음, 코드 줄만 다듬고 되돌림
    keep = []
    out = []
    n = len(text)
    i = 0
    seg = 0

    def lit(a, b):
        out.append(text[seg:a])
        keep.append(text[a:b])
        out.append("\x00%d\x00" % (len(keep) - 1))

    while i < n:
        c = text[i]
        if c in "\"'`":
            e = _short_string_end(text, i, c)
            lit(i, e)
            i = seg = e
            continue
        if c == "[":
            m = LONG_OPEN.match(text, i)
            if m:
                e = _long_end(text, m.end(), m.group(1))
                lit(i, e)
                i = seg = e
                continue
            i += 1
            continue
        if c == "-" and text.startswith("--", i):
            out.append(text[seg:i])
            m = LONG_OPEN.match(text, i + 2)
            if m:
                e = _long_end(text, m.end(), m.group(1))
                body = text[i:e]
                out.append("\n" * body.count("\n") if "\n" in body else " ")
                i = e
            else:
                e = text.find("\n", i)
                i = n if e < 0 else e
            seg = i
            continue
        i += 1
    out.append(text[seg:])
    s = "".join(out)
    lines = []
    for ln in s.split("\n"):
        t = ln.strip()
        if t:
            lines.append(t)
    s = _export_type("\n".join(lines))
    return PH.sub(lambda m: keep[int(m.group(1))], s)


PH = re.compile("\x00([0-9]+)\x00")


EXPORT = re.compile(r"^export(\s+type\b)", re.M)


def _export_type(s):
    # export type 는 모듈 맨 위에서만 쓸 수 있어 함수로 감쌀 때 걸리지 않게 'type' 으로
    return EXPORT.sub(lambda m: m.group(1).lstrip(), s)


def _norm(node):
    if isinstance(node, dict):
        return {k: _norm(v) for k, v in node.items() if k not in ("exported", "hasEnd") and not k.endswith("Location") and k != "location"}
    if isinstance(node, list):
        return [_norm(v) for v in node]
    return node


def _ast(tool, path):
    r = subprocess.run([tool, path], capture_output=True)
    if r.returncode != 0:
        raise SystemExit("luau-ast failed on %s: %s" % (path, r.stderr[:400]))
    return _norm(json.loads(r.stdout.decode("utf-8", "replace"))["root"])


def main():
    if len(sys.argv) > 3 and sys.argv[1] == "--verify":
        import os
        import tempfile

        tool = sys.argv[2]
        bad = 0
        for p in sys.argv[3:]:
            src = open(p, encoding="utf-8").read()
            with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
                f.write(strip(src))
                tmp = f.name
            try:
                if _ast(tool, p) != _ast(tool, tmp):
                    bad += 1
                    print("AST MISMATCH", p)
            finally:
                os.unlink(tmp)
        print("verified", len(sys.argv) - 3, "files,", bad, "mismatches")
        sys.exit(1 if bad else 0)
    sys.stdout.write(strip(open(sys.argv[1], encoding="utf-8").read()))


if __name__ == "__main__":
    main()
