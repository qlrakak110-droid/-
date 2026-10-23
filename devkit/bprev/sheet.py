# sheet.py out.jpg title "label|path" ...   (2 columns, 640x360 tiles with labels)
import sys
from PIL import Image, ImageDraw, ImageFont
out, title, items = sys.argv[1], sys.argv[2], sys.argv[3:]
F = ImageFont.truetype('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc', 24)
FT = ImageFont.truetype('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc', 30)
W, H, top = 640, 360, 50 if title else 0
rows = (len(items) + 1) // 2
im = Image.new('RGB', (W * 2, top + H * rows), (12, 12, 14)); d = ImageDraw.Draw(im)
if title: d.text((14, 8), title, font=FT, fill=(255, 255, 255))
for i, it in enumerate(items):
    lab, p = it.split('|', 1)
    try: t = Image.open(p).convert('RGB').resize((W, H))
    except Exception: continue
    x, y = (i % 2) * W, top + (i // 2) * H
    im.paste(t, (x, y))
    tw = d.textlength(lab, font=F); d.rectangle([x, y, x + tw + 16, y + 34], fill=(0, 0, 0)); d.text((x + 8, y + 3), lab, font=F, fill=(255, 255, 255))
im.save(out, quality=86); print(out)
