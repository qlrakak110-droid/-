# compare.py <beforeDir> <afterDir> <out.png> <name...>: rows of before | after (half size), labelled
import sys
from PIL import Image, ImageDraw, ImageFont
bd, ad, out, names = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
W, H = 640, 360
try: font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 22)
except Exception:
    try: font = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 22)
    except Exception: font = ImageFont.load_default()
img = Image.new('RGB', (W * 2 + 12, (H + 6) * len(names) + 40), (18, 20, 26))
d = ImageDraw.Draw(img)
d.text((10, 8), 'BEFORE (original)', fill=(220, 220, 220), font=font); d.text((W + 22, 8), 'AFTER (tinted glass)', fill=(255, 210, 120), font=font)
for i, n in enumerate(names):
    y = 40 + i * (H + 6)
    for j, dd in enumerate((bd, ad)):
        im = Image.open(f'{dd}/{n}.png').convert('RGB').resize((W, H), Image.LANCZOS)
        img.paste(im, (j * (W + 12), y))
    d.text((8, y + 6), n, fill=(255, 255, 255), font=font)
img.save(out, optimize=True)
print(out, img.size)
