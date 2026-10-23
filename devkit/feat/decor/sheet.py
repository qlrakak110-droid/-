import sys, glob
from PIL import Image
d, out, pat = sys.argv[1], sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else '*.png')
fs = sorted(f for f in glob.glob(d + '/' + pat))
ims = [Image.open(f).crop((140, 120, 1140, 620)).resize((640, 320)) for f in fs]
W = Image.new('RGB', (1280, 320 * ((len(ims) + 1) // 2)))
for i, im in enumerate(ims):
    W.paste(im, ((i % 2) * 640, (i // 2) * 320))
W.save(out)
print(out, len(ims))
