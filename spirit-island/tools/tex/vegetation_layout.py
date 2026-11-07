"""vegetation_layout — atlas regions shared by the texture painters (tools/tex/vegetation_*.py) and the Blender
model scripts (tools/blender/vegetation_*.py). Pure python (no numpy / PIL) so Blender can import it.

Regions are (x0, y0, x1, y1) in IMAGE pixels of a 1024 x 1024 atlas, y measured from the TOP of the image.
For leaf / plant cards the attachment point (twig base, stem base) is at the bottom-centre of the region.
"""
N = 1024

# foliage atlas: assets/tex/vegetation/foliage_{albedo,alpha,normal}.jpg
FOLIAGE = {
    'broad':   (0, 0, 512, 512),       # deciduous twig cluster (beech / linden-like ovate serrated leaves)
    'birch':   (512, 0, 1024, 512),    # small birch leaves on drooping twigs
    'needle':  (0, 512, 512, 1024),    # fir / spruce needle spray
    'blossom': (512, 512, 1024, 1024), # cherry blossom twig with young leaves
}

# ground cover atlas: assets/tex/vegetation/cover_{albedo,alpha,normal}.jpg
COVER = {
    'lawn':    (0, 0, 512, 256),       # short dense meadow blades (card strip)
    'wild':    (512, 0, 1024, 256),    # tall wild grass with seed heads
    'fern_a':  (0, 256, 256, 768),     # fern frond (base at bottom)
    'fern_b':  (256, 256, 512, 768),
    'clover':  (512, 256, 768, 512),   # top-down clover patch
    'rosette': (768, 256, 1024, 512),  # top-down plantain / moss rosette
    'daisy':   (512, 512, 640, 768),   # flowering plant side cards (base at bottom)
    'butter':  (640, 512, 768, 768),
    'bell':    (768, 512, 896, 768),
    'pink':    (896, 512, 1024, 768),
    'reed':    (0, 768, 256, 1024),    # reeds / sedge for water edges
    'sedge':   (256, 768, 512, 1024),
    'leafbed': (512, 768, 768, 1024),  # fallen leaves / litter decal (top-down)
    'moss':    (768, 768, 1024, 1024), # moss cushion (top-down)
}


def uv_rect(region, inset=1.0):
    """region -> (u0, v0, u1, v1) in Blender UV space (origin bottom-left), inset by a pixel to avoid bleeding"""
    x0, y0, x1, y1 = region
    return ((x0 + inset) / N, 1 - (y1 - inset) / N, (x1 - inset) / N, 1 - (y0 + inset) / N)
