# tools/blender — the Blender character pipeline of 흑일무림

Heroes are modelled in **headless Blender 5.3 driven by Python scripts** (no hand-made binary sources): every asset in
`assets/chars/<hero>/` is regenerated from `tools/blender/heroes/<hero>.py` + the library `edlib`. The game reads the
result through `src/char/assets.js` as ordinary kit pieces of the hero's rig, so cloth, springs, glow control, shadows,
afterimages and dispose work unchanged. **Proportions, bones, sockets, weapon lengths, grips and the main colliders are
the rig's and never change** (108 clips depend on them): the scripts model what the skeleton wears and holds.

```
tools/blender/
  export_rig.mjs        game rig -> rigs/<hero>.json (runs the real character runtime in Node)
  edlib.py              the library hero scripts import (one namespace over ed/*.py)
  ed/core.py            scene, axes, Rig (rig.json), build_armature, pose_armature, meshes, attributes, looks, part()
  ed/body.py            anatomical base body (SDF masses in bone frames) + hands with separated fingers, region culling
  ed/sdf.py             signed-distance sculpting (smooth unions, cuts) and its mesher
  ed/model.py           lofts / lathes / sweeps / ribbons, solidify / bevel / subdivide / displace / wrinkle / boolean /
                        engrave, pattern generators: weave, weave_relief, lamellar (+ lacing), braid, helix_wrap, knot,
                        tassel, lacing, grid_surface
  ed/cloth.py           body-fitted garment shells (wrap), push_out, Blender cloth draping (drape), pleats, hem, seam
  ed/skin.py            bone-heat weights on bone subsets, helper-bone stations, transfer_weights, spring chains,
                        runtime cloth panels (define_panel / bind_panel), rigid islands, smoothing, limits, mirror check
  ed/bake.py            vertex AO + curvature -> ed_cav, decimate_to, UVs, Cycles high -> low map bakes
  ed/render.py          Cycles preview sheets (studio / arena night / silhouette)
  ed/export.py          the EDM1 asset + manifest + generated JS module
  heroes/pilot.py       the pipeline pilot on VORN's rig (src/char/asset_pilot.js, lab src/labs/asset.js)
  build_assets.sh       <hero|all> [--preview]: rigs + hero scripts
  rigs/<hero>.json      generated rig exports (kael, iska, vorn, pilot)
```

## 1. Running

```sh
cd eclipse-duel
node tools/blender/export_rig.mjs                         # rigs/kael|iska|vorn|pilot.json (~7 s)
tools/blender/build_assets.sh pilot --preview             # rigs + heroes/pilot.py -> assets/chars/pilot + shots/blender/pilot
/opt/blender-env/venv/bin/python tools/blender/heroes/pilot.py --stage 3      # stop after a stage, preview sheet of it
/opt/blender-env/venv/bin/python tools/blender/heroes/pilot.py --no-preview   # asset only (~25 s)
node tools/shot.mjs asset --do "__ED.lab.play('pair')" --at 0.5 --out shots/blender/pilot/eng_pair     # in-engine check
```

`ED_THREADS` (default 2) caps Cycles threads; the machine is shared: keep previews at <= 960x540, 8-16 samples. There is
no GPU: never EEVEE. The fused SDF body takes ~1 min the first time and is cached in `build/blender-cache/` (keyed by
rig, build options and the source of body.py / sdf.py).

New hero: add it to `HEROES` in `export_rig.mjs` if its design module is new, copy the skeleton below to
`heroes/<hero>.py`, run it, then import `assets/chars/<hero>/index.js` from the design (section 6).

## 2. Conventions

* **Units / axes.** Metres. Game: `+X` forward, `+Y` up, `+Z` the fighter's right (camera side). Blender: the hero
  faces `-Y`, `Z` up, the right hand at `-X`. Converted once in `ed/core.py`: `blender = (-gz, -gx, gy)`,
  `game = (-by, bz, -bx)` (`ed.g2b`, `ed.b2g`). **Every world-space argument of edlib is Blender space**; offsets relative
  to a bone are in the bone's **game** frame, exactly as in the JS kit: `rig.pt('foreArmR', [0, -0.1, 0])` is 10 cm
  down the right forearm. Exported assets are in game bind space.
* **Bind pose.** Meshes are authored in the rig's bind pose (A-pose: arms ~28 deg abducted; see rig.json `axes.bind`).
  `pose_armature(arm, rig, 'walk')` puts the armature in a pose sampled from the game (idle, walk, guard, attack
  wind-up / impact are in rig.json) to check deformation in Blender.
* **Parts** (`ed.part(obj, name, slot, flags)`): the unit `assets.add(kit, hero, { parts })` selects. One object per
  part (join pieces first); parts sharing a name are concatenated. A cloth-bound part carries exactly one panel.
* **Slots** = draw calls (<= 6 per hero; the pilot uses 4): `cloth` (robes, skirts, sashes, wraps: solidified, single
  sided), `gear` (body, armour, hat, hair, boots), `hair` (alpha-cut strands: `cutout`), `blade` (weapon). The design's
  `materials` must have every slot the asset uses (or remap with `slotMap`).
* **Looks** (`ed.look(name, color, rough, metal, set, amt, wear, occ, glow, inlay=, vein=, eye=)`): one Blender material =
  one kit look; `set` is a texture set of `src/char/kit/textures.js`. Colours are **linear** and as dark as the game
  needs (black silk ~0.01, violet silk (0.05, 0.02, 0.09), bronze F0 (0.42, 0.27, 0.11)): Blender previews look darker
  than a lit studio; judge colour in the engine. UV sets (`brocade`, `lamellar`, `bamboo`, `gauze`, `hair`, `blade`, `fur`)
  need an `ed_uvw` attribute (u, v, code) on the object; tiling sets (`silk`, `hemp`, `leather`, `lacquer`, `bronze`, ...)
  need nothing.
* **Per-vertex surface data** (exported, read by the shared character shader): `ed_col` (albedo multiplier), `ed_cav`
  (< 1 occlusion / grime, 1..2 convex edge wear: `bake_cavity` writes AO + curvature into it), `ed_glow` (inlay, vein,
  eye masks; else the look's constants), `ed_uvw`, `ed_cloth` (panel u, v, share), `ed_bake` UV layer + `ed_bakew`
  (baked maps).
* **Skin weights** are vertex groups named after game bones, <= 4 influences, normalised (the exporter enforces both).
  Bones are stored by NAME and resolved at load.

### Binding to the rig

| what | how |
|---|---|
| body | `ed.body(rig, arm=arm)`: bone heat on the anatomical chain + the rig's helper bones from the station tables (deltoid, twist, half-joint, crease helpers) |
| garments over the body | `ed.transfer_weights(body, garment, arm, bones=[...])`: the garment bends exactly like the limb inside it |
| hard pieces | `ed.rigid(obj, 'head')` (hat, weapon on `weaponR`); many plates: `ed.rigid_islands(plates, body)` (each plate rides the body without bending) |
| spring chains (hair, sash ends, tassels) | the JS design declares the chain (`bones` + `springs`); `export_rig.mjs` puts it in rig.json; `ed.along_chain(obj, rig, 'queue', parent='head', root_blend=0.06)` |
| runtime cloth (skirts, coat tails) | drape in Blender, `pan = ed.define_panel(name, grid, anchor='hips', rig=rig, cols, rows, **cloth options)` (columns from the fighter's LEFT = Blender +x to his right), `ed.bind_panel(obj, pan, share=lambda u, v: ed.smoothstep(0.1, 0.42, v))`; the design's `cloth: assetCloth(asset)` makes the verlet panels from the asset (`mesh: false`). The game's cloth starts where Blender left it; vertices store (u, v, share), turned into bilinear weights on whatever particle grid the quality tier runs |

## 3. Library reference (`import edlib as ed`)

Scene / rig: `reset_scene(threads=None)`, `Rig(hero_or_path)` (`.pt(bone, off)`, `.pts`, `.vec`, `.local(bone, P)`,
`.head / .tail(bone)`, `.socket(name)`, `.capsules()`, `.weapon(k)` (base, tip, grips, extent), `.panel(name)`,
`.chain(prefix)`, `.chain_points(prefix)`, `.of_kind(*kinds)`, `.K` body scale, `.P` proportions, `.data`),
`build_armature(rig, name='rig', kinds=None)`, `pose_armature(arm, rig, pose=None)`, `collection`, `select`, `delete`,
`join(objs, name)`, `duplicate`, `log`.

Meshes / data: `new_mesh(name, verts, faces)`, `verts_of`, `set_verts`, `normals_of`, `tris_of`, `tri_count`, `add_mod(obj,
kind, **props)`, `apply_mods`, `shade(obj, angle)`, `recalc_normals(obj, inside=False)`, `weld`, `transform`, `mirror_x`,
`set_attr / get_attr`, `set_color`, `set_weights / get_weights`, `rigid(obj, bone)`, `look(...)`, `assign_look(obj, mat,
faces=None)`, `part(obj, name, slot, flags=(), order=0)`, `g2b / b2g`, `smoothstep`, `lerp`, `normalize`, `polyline(points,
n)`, `curve_fn`.

Body: `body(rig, name='body', build=None, voxel=0.0065, tris=9000, hands=True, feet=True, arm=None)` (`build`: mass,
chest, waist, hips, arms, legs, neck, muscle, bust, hands; `ed.body.last_sdf` = its SDF), `body_sdf(rig, build)`,
`hand(rig, side, girth)`, `keep_regions(body, [regions])` (0 torso, 1 head / neck, 2 arms, 3 hands, 4 legs, 5 feet),
`cull_hidden(body, covers, keep=mask)` (delete what garments hide), `SDF` (`group`, `ell`, `cone`, `chain`, `cut`,
`subset(groups, offset)`, `eval`, `grad`, `project`, `mesh`).

Modelling: `loft(name, rings, close, caps)`, `ellipse_ring`, `sweep(name, path, section, radius, scale_y, twist)`,
`tube`, `lathe(name, profile [[r, h]], segs, origin, axis, a0, a1, caps)`, `ribbon(name, path, width, normal, camber, nu,
thickness, code)`, `ellipsoid`, `capsule`, `box(bevel_w)`, `solidify(obj, thickness, offset)`, `bevel(obj, width,
segments, angle)`, `subdivide`, `smooth(obj, factor, iterations, mask)`, `displace(obj, fn(P, N), strength)`,
`wrinkle(obj, amount, scale, stretch, mask, along)`, `boolean(obj, cutter, op)`, `engrave(obj, paths, width, depth)`,
`surface_normal(S, u, v)`, `cone_surface(apex, axis, radius, height, bell)`, `grid_surface(loft_obj, offset)` (a
parametric surface over a draped garment: lay lamellar, weaves, belts on it).

Patterns: `weave(name, S, nu, nv, pattern=(2, 2), sub, across)` (real over / under strips: a bake source),
`weave_relief(obj, nu, nv)` (game-resolution displacement), `lamellar(name, S, rows, cols, ..., closed, lod)` ->
(plates, lacing), `braid(name, path, width, thickness, pitch, taper)`, `helix_wrap(name, a, b, radius, turns, width,
sides, ellipse, axes)`, `knot(name, center, size, facing, up)`, `tassel(name, top, direction, length, radius, strands)`,
`lacing(name, left, right)`.

Garments / cloth: `wrap(name, sdf, centers, n, offset, arc, ease, min_r, rmax)` (rings cast against the body SDF,
concavities spanned), `ring_axis(points, n)`, `push_out(obj, sdf, clearance)`, `drape(obj, colliders, pin, frames, mass,
tension, bending, thickness)` (Blender cloth stepped and frozen), `collider`, `remove_colliders`, `pleats(obj, count,
depth)`, `hem(obj, side, width, roll)`, `seam(obj, fn, depth, width)`, `body_radius`, `convexify`.

Skinning: `auto_skin(obj, arm, rig, bones=None, helpers=True)`, `heat_weights(obj, arm, bones)`, `transfer_weights(src,
dst, arm, smooth, bones, mask)`, `along_chain(obj, rig, prefix, param, parent, root_blend)`, `chain_weights`,
`by_rows(obj, rig, {row: bone})`, `rigid_islands(obj, src)`, `station_weights`, `smooth_weights`, `limit_normalize(W,
4)`, `define_panel(name, grid, anchor, rig, cols, rows, **opts)`, `bind_panel(obj, panel, share, uv)`,
`mirror_check(obj, rig)`, `weight_report(obj)`, `islands(obj)`, `skin.PANELS`.

Baking / budgets: `bake_cavity(objs, samples, distance)` (Cycles vertex AO with the whole hero occluding + curvature ->
`ed_cav`), `bake_vertex_ao`, `surface_cavity`, `curvature`, `decimate_to(obj, tris, protect_boundary=True)`,
`uv_unwrap(obj)`, `uv_from_grid(obj)`, `bake_object_maps(high, low, size, name)` (object-space normal in game axes +
mask R AO / G curvature / B albedo x 0.5 -> WEBP records for `export_asset(textures=)`), `bake_maps` (tangent / AO).

Preview / export: `preview_sheet(label, name, height, rig='studio')` (front, 3/4, side, back, bust, silhouette, the
other light rig -> `shots/blender/<label>/<name>.png`), `render_view(label, name, target, dist, yaw)`,
`light_rig('studio' | 'arena' | 'white')`, `camera`, `render_still`, `contact_sheet`;
`export_asset(hero, objs, textures=[], scripts=[__file__, ...])`.

## 4. Minimal hero script (start here)

```python
# tools/blender/heroes/<hero>.py
import os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import numpy as np
import edlib as ed

HERO = 'kael'                                   # rigs/<HERO>.json (node tools/blender/export_rig.mjs)
PREVIEW = '--no-preview' not in sys.argv
ed.reset_scene()
rig = ed.Rig(HERO); arm = ed.build_armature(rig); P = rig.pt; K = rig.K
LK = {
    'skin': ed.look('skin', color=(0.2, 0.12, 0.08), rough=0.6, set='leather', amt=0.15),
    'silk': ed.look('silk', color=(0.012, 0.01, 0.01), rough=0.55, set='silk', amt=0.9),
    'iron': ed.look('iron', color=(0.1, 0.1, 0.11), rough=0.4, metal=1.0, set='scorched', amt=0.8, vein=0.4),
}
# 1. body (skinned, helper bones included)
body = ed.body(rig, arm=arm, tris=12000, build={'mass': 1.1, 'chest': 1.1})
S = ed.body.last_sdf
ed.assign_look(body, LK['skin'])
# 2. a robe torso fitted to the body, folds, skinned like the body under it
ax = ed.ring_axis([P('chest', [0, 0.28, 0]), P('spine', [0, 0.05, 0]), P('hips', [0, -0.02, 0])], 24)
robe = ed.wrap('robe', S.subset(['torso', 'neck']), ax, n=48, offset=0.01)
ed.wrinkle(robe, amount=0.003, scale=22); ed.push_out(robe, S, 0.006)
ed.assign_look(robe, LK['silk'])
ed.transfer_weights(body, robe, arm)
ed.solidify(robe, 0.004)
# 3. a hard piece on one bone
mask = ed.ellipsoid('mask', P('head', [0.09, 0.09, 0]), [0.03, 0.06, 0.07]); ed.assign_look(mask, LK['iron']); ed.rigid(mask, 'head')
# 4. what shows, parts, budgets, baked surface data, export
ed.cull_hidden(body, [robe, mask], keep=np.isin(ed.get_attr(body, 'ed_region'), [3]))
parts = [(body, 'body', 'gear'), (robe, 'robe', 'cloth'), (mask, 'mask', 'gear')]
for i, (o, name, slot) in enumerate(parts):
    ed.part(o, name, slot, order=i)
objs = [p[0] for p in parts]
ed.decimate_to(robe, 9000)
ed.bake_cavity(objs, samples=24, distance=0.1)
ed.export_asset(HERO, objs, scripts=[os.path.abspath(__file__)])
if PREVIEW:
    ed.preview_sheet(HERO, 'final', height=2.0)
```

Then in the design (keep proportions, colliders, weapon, sockets):

```js
import kaelAsset from '../../../assets/chars/kael/index.js';
import { addAsset, assetCloth, attachAssetMaps } from '../../char/assets.js';
export const kael = { ...,
  materials: { cloth: {...}, gear: {...}, blade: {...} },          // every slot the asset uses
  cloth: assetCloth(kaelAsset),                                      // panels defined in Blender (if any)
  attach(char, quality) { attachAssetMaps(char, kaelAsset, quality); return attachGlow(char, GLOW); },
  build(kit) { addAsset(kit, kaelAsset, { design: this }); buildWeapon(kit, 'greatsword', {}); },
};
```

`addAsset(kit, ref, { parts, exclude, slotMap, looks, design })`: `parts` = names or fn, `looks` = per-look overrides
(retune colours in JS without re-running Blender), `design: this` lets `attachAssetMaps` find the baked-map vertices.

## 5. Asset format (EDM1)

`assets/chars/<hero>/<hero>.edm`: `'EDM1'` | u32 JSON length | JSON (padded to 4) | data block. JSON: `format, hero,
script (hash), triangles, vertices, looks[], panels[] (name, cols, rows, anchors, top (pinned edge in anchor-bone
frames), rest (f32 offset, game space), params), textures[] (name, kind, mime, width, height, off, length), parts[]`.
A part: `name, slot, flags, vertices, triangles, bmin, bmax, bones[] (names), runs[] (look, v0, vn, i0, in)` and
streams (offsets into the data block, 4-aligned): `pos` u16x4 (in bmin..bmax), `nrm` i8x3 + u8 cavity (x2/255), `col`
u8x3 (sqrt(linear / 2)) + u8 look, `skin` u8x4 palette indices + u8x4 weights (sum 255, or 255 x (1 - cloth share)),
optional `glow` u8x4, `uvw` {off, min, max} u16x4, `bake` {off, maps} u16x4 (u, v, weight), `cloth` {panel, off} u16x4
(u, v, share), `idx` {off, type 16 | 32}. Vertices are sorted by look (one kit piece per run). `<hero>.json` is the
manifest (triangles, bytes, parts, looks, bones used, build seconds, script hash, Blender version); `index.js` is
generated: it imports the binary (esbuild `binary` loader in `tools/build.mjs`) and registers it, so only targets that
import a hero embed its asset.

## 6. Budgets (per hero)

<= 60k triangles, <= 6 draw calls, embedded asset <= 2.2 MB (geometry + textures, before base64), decode + build at boot
<= 150 ms, the whole page <= 12 MB, `char.update` <= 1 ms on desktop (verlet cloth <= 3 panels). Low tier: the baked maps
are skipped (`attachAssetMaps(char, ref, { tier: 'low' })`), vertex data stay. Measure in the lab:
`node tools/shot.mjs asset --at 0 --eval "__ED.lab.play('stats')"`.

## 7. Previews and checks

* Blender: `ed.preview_sheet(label, name)` -> `shots/blender/<label>/<name>.png` (judge form, folds, silhouette).
* Engine: `src/labs/asset.js` (pair with the kit-built VORN, turntable, bust, waist, hands, sil, clip, stats, dispose);
  the art lab (`node tools/shot.mjs art --hash design=<hero> ...`) once the hero design imports its asset.
* Game: `node tools/shot.mjs game --as bl-<label> --hash "demo=vorn,kael,hard&seed=7" --at 6,12 --sheet 2 --sheet-only
  --out shots/blender/<label>/demo` (private build; never build dist/).

## 8. Troubleshooting (what bit us)

* **A joined object is gone.** `ed.join` merges into the first object and deletes the others: compute anything per
  piece (blade uvw, bake weights) before joining.
* **Garment lining shows outside.** Open sheets (lofted panels, wraps with an `arc`) have arbitrary winding: orient them
  away from their axis before `solidify` (heroes/pilot.py `orient_out`), else the inner look ends up on the outside.
* **Skirts collapse between the legs** when draped against the legs themselves: drape against the convex hull of hips +
  legs (`wrap(..., S.subset(['torso', 'legR', 'legL']))` as collider) and keep frames low (12-20) with bending 3-6.
* **`solidify(even=True)` throws spikes** out of the sharp folds of draped cloth: keep even thickness off for cloth.
* **Attributes on joined objects**: objects without an attribute get zeros on join; `ed_cloth` must live only on the
  cloth part (one panel per part), `ed_bakew` must be set (0) on the pieces without maps.
* **Lamellar budgets.** A full cuirass at lod 1 (rounded plates + raised stitches) is ~36k triangles: use `lod=0`
  (~15k with the shoulder piece) and bake the rest.
* **Decimating lamellar / weaves** breaks their islands: decimate garments only, lower the generator resolution for
  pattern pieces.
* **Image orientation.** Blender writes v = 0 at the bottom row: textures load with `flipY = true`.
* **Normal maps are object space in GAME axes** (`normal_r='NEG_Y', normal_g='POS_Z', normal_b='NEG_X'`): the shader
  uses them in bind space directly (no tangents); do not convert them to tangent space.
* **Cycles bake of vertex AO** needs every object's armature modifier hidden at render (bake_vertex_ao does it); an AO
  that comes out white means the bake failed (see the log line).
* **export_rig.mjs for a design that imports its own asset** works on a missing asset (the import is stubbed), so a new
  hero can bootstrap; re-export the rig after the asset changes its cloth panels (build_assets.sh does both).
