# src/char — character runtime

Procedural armoured fighters: one skeleton, one `SkinnedMesh` per material slot (rigid plates bound 100% to one
bone + a smooth-skinned under-suit), a data-driven clip mixer with IK, spring bones and verlet cloth.

```
src/char/index.js       createCharacter(ctx, design) -> Character; re-exports the clip API
src/char/anim.js        clip / pose registry, compiler, sampler, mirroring
src/char/skeleton.js    bone table, proportions, zero / bind pose, forward kinematics
src/char/ik.js          two-bone IK (pole + soft reach), floor / toe contact, look-at
src/char/build.js       design kit: pieces -> bind space -> merged SkinnedMeshes
src/char/shapes.js      modelling primitives (plates, lathes, tubes, blades ...)
src/char/materials.js   kit material (per-vertex PBR attributes, triplanar detail, hit flash)
src/char/spring.js      spring bones          src/char/cloth.js   verlet cloth          src/char/collide.js  capsules
src/char/rigmath.js     allocation-free quaternion / spline helpers
src/char/designs/knight.js   demo design (full plate knight, greatsword, cape + tabard cloth, plume, tassets)
src/char/clips/demo.js       demo clips (idle, guard, walks, 3-hit combo, slam, hit reaction, mirrored combo)
src/labs/char.js             lab page (node tools/build.mjs char)
```

Budgets of the demo knight (high tier): **3 draw calls** (slots `plate`, `suit`, `blade`; +3 in the shadow pass),
**56.9k triangles**, 188 bones (49 animated incl. helpers / fingers / weapon / plume / tassets + 104 cape + 35 tabard
cloth particles), ~0.5-0.6 ms CPU per `update()` on desktop (two cloths included). No per-frame allocations in
`update()`. Contract limits: <= 6 draw calls and <= 60k triangles per character.

---

## 1. Quick start

```js
import { createCharacter } from '../char/index.js';
import { knight } from '../char/designs/knight.js';
import '../char/clips/demo.js';                     // registers demo.* clips

const p1 = createCharacter(ctx, knight, { name: 'p1' });   // added to ctx.scene
p1.root.position.set(-2.5, 0, 0);
p1.setFacing(1);
p1.play('demo.idle');
const tip = new THREE.Vector3();
p1.onEvent((name, data, clip) => { if (name === 'hit') ctx.vfx?.burst(sparks, { pos: p1.sockets.weaponTip.getWorldPosition(tip) }); });
ctx.onUpdate((dg, dr) => p1.update(dg, dr), ctx.ORDER.CHAR);

// game logic owns move time:
p1.play('demo.combo1', { fade: 0.06 });
p1.setClipTime(fighter.moveTime);                    // every frame while the move runs
p1.root.position.x += p1.rootDelta.f * p1.facing;    // if the presentation applies root motion itself
```

```js
// reactions
p2.play('demo.hit', { fade: 0.04, restart: true });
p2.impulse({ dir: [-1, 0.1, 0.2], amount: 1.2 });    // physical flinch on top of the clip
p2.flash([4, 1.4, 0.4], 1, 0.18);                    // HDR emissive flash, real time
p2.lookAt(p1.sockets.head);                          // head tracks the opponent
```

---

## 2. Character API

`createCharacter(ctx, design, opts?)` — `opts`: `{ parent = ctx.scene (null = do not add), name }`.

| member | description |
|---|---|
| `root` | `THREE.Group` to place on the fight line. Model forward is **+X**; `root.scale.x` carries the facing (mirror). |
| `setFacing(f, { turn = 0 })` | `+1` face +X, `-1` face -X (instant mirror, the 2.5D-fighter convention: the same side always faces the camera). `turn` > 0 (seconds) spins through a quick turn instead. Cloth / springs are unaffected. |
| `facing` | current facing (getter). |
| `bones` | `{ name: THREE.Bone }` — all bones (section 4). |
| `sockets` | `Object3D` markers, world matrices valid after `update()`: `weaponBase`, `weaponTip` (`weaponBase2`/`weaponTip2` ... for more weapons), `handR`, `handL` (centre of the fist), `chest`, `head`, `hips`, `footR`, `footL` (sole), `back`, plus `design.sockets`. |
| `play(name, { fade = 0.1, speed = 1, loop = clip.loop, startAt = 0, restart = false })` | Crossfade to a clip (or a registered pose: it is held). Re-playing the clip that is already looping keeps it running unless `restart`. Up to 4 clips blend at once. |
| `clip`, `clipTime`, `clipDuration`, `finished` | state of the newest clip (`finished`: non-looping and at its end). |
| `setClipTime(t)` | External time: the newest clip stops self-advancing until the next `play()`. Events and root motion between the previous and the new time are still produced (forward only). |
| `update(dtGame, dtReal)` | Advance clips, IK, additive motion, springs, cloth; writes bones and socket matrices. Call once per frame. `dtGame = 0` (hit-stop) freezes animation and cloth; the flash still decays on `dtReal`. |
| `rootDelta` | `{ f, u }` root motion (fighter metres) produced by this `update()`. Not applied unless `applyRootMotion = true`. |
| `onEvent(fn(name, data, clipName))` | Clip markers crossed this update (newest clip only). Returns an unsubscribe function. |
| `flash(color, amount = 1, dur = 0.15)` | Emissive flash on every material (`color`: hex / `THREE.Color` / `[r,g,b]` HDR), fresnel-weighted, quadratic decay over `dur` real seconds. |
| `impulse({ bone = 'body', dir = [-1,0,0], amount = 1 })` | Additive physical flinch that springs back. `dir` is the push direction `[f,u,s]` (a hit from the front pushes `[-1,0,0]`). `'body'`: hips / spine / chest bend away with a lagging head whip and a hips shove; any bone name: that bone alone. `amount` 1 = heavy hit: ~8 deg torso bend + ~12 deg head whip, settles in ~0.4 s; scale freely (2-3 for launchers). |
| `lookAt(target, weight = 1)` | Head + neck track a world `Vector3` / `Object3D` (limited to 75 deg, blended in ~0.1 s); `null` releases. Clips with `look: false` disable it; a clip `look` channel overrides it. |
| `layer(name, clip, { weight = 1, mask = 'upper', additive = false, speed = 1, loop, fade = 0.15 })` | Masked override layer (attack while walking) or additive layer (motion relative to the clip's first frame). Masks: `'upper' 'lower' 'arms' 'head'` or an array of bone names. Override layers solve their own IK. |
| `stopLayer(name, fade = 0.15)` | Fade a layer out and remove it. |
| `breath` | `{ rate = 0.32 Hz, depth = 1 }` procedural breathing (chest, shoulders, head counter-motion), scaled per clip by `clip.breath`. |
| `wind` | `[x,y,z]` world-space wind acceleration for cloth (m/s^2; 2-6 is a stiff breeze). Gusts are added deterministically. |
| `teleport()` | Reset cloth / springs after placing the character somewhere new (jumps > 0.6 m per frame and facing flips are detected automatically). |
| `weapon` | `{ bone, mesh, material, grips, setVisible(b) }` of the first design weapon (`material` is the blade slot material: tint / glow it for skills). |
| `materials`, `meshes` | `{ slot: material }`, `{ slot: SkinnedMesh }`. |
| `stats` | `{ triangles, drawCalls, bones }`. |
| `prewarm()` | `renderer.compile(scene, camera)` now. |
| `setVisible(b)`, `dispose()` | Visibility; free geometries, materials, bone texture and detach. |

Order of operations inside `update()`: advance clips (events, root motion) -> sample + resolve every active clip
(FK, automatic pelvis drop, hand / foot IK) -> crossfade -> layers -> breathing + flinch springs -> re-plant feet where
the blend put them + floor / toe contact -> two-handed grip IK -> look-at -> helper bones -> spring bones -> cloth ->
bones + sockets.

---

## 3. Frames, units, conventions

* Metres, seconds, degrees in data. Y up.
* **Fighter frame `(f, u, s)` = the character's model space** (= `root` local space): `+X = f` forward (toward the
  opponent), `+Y = u` up, `+Z = s` side toward the camera, which is the **fighter's right side**. Facing `-1` mirrors
  `X`, so everything authored in this frame mirrors for P2 automatically.
* `root` sits on the floor (`u = 0` is the floor while the fighter is grounded).
* **Zero pose**: every bone rotation 0. All bone frames are parallel to the fighter frame; the body stands straight,
  arms and legs hang straight down (`-Y`), feet / toes / weapon point `+X`. Authored bone rotations are local
  rotations relative to this pose, so `[0,0,0]` always means "the zero pose for this bone".
* **Euler order ZXY** (`R = Rz * Rx * Ry`): the bone first pitches about Z, then rolls about its new X, then twists
  about its new Y (its own long axis for limbs). Use mostly one axis per bone; combine with care.
* **Left bones are mirrored**: on every `...L` bone the X and Y components are negated before use, so the same
  numbers on `upperArmR` and `upperArmL` give mirror-image poses. Centre bones are not mirrored.
* The **bind pose** (arms in an A-pose) is only used to build the smooth under-suit. Authors never see it.

Heights of the zero pose (default proportions): hips pivot 1.04, hip joints 0.98 (`s = +-0.10`), spine 1.15,
chest 1.32, neck base 1.575, head pivot (skull base) 1.68, head top ~1.90, shoulder joints 1.52 (`f = -0.015`,
`s = +-0.22`), elbows 1.22, wrists 0.95, fist centre (grip) 0.865, knees 0.515, ankles 0.085, ball of the foot
`f = +0.135`. Lengths: upper arm 0.30, forearm 0.27, thigh 0.465, shin 0.43, wrist -> fist 0.085.

---

## 4. Bones and axes

Measured from the rig (a +30 deg rotation on one axis, how the bone's tip moves). "Toward the midline" is `-s` for a
right bone and `+s` for a left bone (the mirror convention makes the meaning symmetric).

### Centre bones (`hips`, `spine`, `chest`, `neck`, `head`) — point up

| bone | `+X` | `+Y` | `+Z` |
|---|---|---|---|
| `hips` (pelvis; root of everything, use `hips.rot` / `hips.pos`) | side-bend: top tilts toward `+s` (camera / own right) | turn left: front turns toward `-s` (away from the camera) | tilt back (top toward `-f`); `-Z` bows forward |
| `spine` (lumbar) | same | same | lean back; `-Z` = bend forward |
| `chest` (thorax) | same | same | lean back / chest up; `-Z` = hunch forward |
| `neck` | same | same | head back; `-Z` = chin down |
| `head` | ear toward the right (`+s`) shoulder | look left (`-s`) | look up; `-Z` = look down |

### Arms (`shoulder`, `upperArm`, `foreArm`, `hand`, fingers) — hang down in the zero pose, palm toward the thigh, thumb forward

| bone | `+X` | `+Y` | `+Z` |
|---|---|---|---|
| `shoulderR/L` (clavicle, points outward) | **depress** (shoulder down); `-X` = shrug up | protract (shoulder forward); `-Y` = pull back | roll about the clavicle (avoid) |
| `upperArmR/L` | adduct: arm swings across toward the midline; **`-X` = raise sideways (abduct)** | internal rotation (front of the arm turns toward the midline) | **raise forward (flex)**; `-Z` = swing back |
| `foreArmR/L` | (not anatomical — keep 0) | pronation; moved into the hand automatically (forearm stays a hinge; twist is spread by helpers) | **bend the elbow** (0..150) |
| `handR/L` | flex toward the palm (palm side = midline) | pronate (thumb turns toward the midline) | tilt toward the thumb (radial); `-Z` toward the little finger |
| `fingers*`, `fingerTips*`, `thumb*` | driven by the `curl` channel — do not key | | |
| `weaponR/L` (fist centre, grip axis) | roll the blade about its own axis | yaw the blade toward the midline | tip up. Fixed in the hand; aim weapons with hand IK instead |

### Legs (`thigh`, `shin`, `foot`, `toe`)

| bone | `+X` | `+Y` | `+Z` |
|---|---|---|---|
| `thighR/L` | adduct (leg across); **`-X` = abduct (leg out)** | internal rotation (knee turns toward the midline) | **hip flexion (leg forward / knee up)**; `-Z` = leg back |
| `shinR/L` | (keep 0) | (keep 0) | **`-Z` = bend the knee** (0..-150); `+Z` hyperextends |
| `footR/L` (ankle, points forward) | invert (sole turns toward the midline) | toe-in (toes turn toward the midline); `-Y` = toe-out | **toes up (dorsiflex)**; `-Z` = point the foot |
| `toeR/L` (ball of the foot) | — | — | toes up (bend at the ball) |

### Helper bones (driven every frame — never key them)

`deltoidR/L` (child of the clavicle at the shoulder joint, half of the arm swing: pauldrons), `upperArmTwistR/L`
(cancels half of the upper-arm twist near the shoulder), `elbowR/L` / `kneeR/L` (half of the joint angle: volume-
preserving joint ring, couters / poleyns), `foreArmTwistR/L` (65% of the wrist twist: vambraces).

### Worked pose examples

```js
// arms hanging relaxed
bones: { upperArmR: [-14, 6, 4], upperArmL: [-14, 6, 4], foreArmR: [0, 0, 16], foreArmL: [0, 0, 16] }
// right arm raised straight forward to shoulder height, elbow straight
bones: { upperArmR: [0, 0, 90] }
// both arms raised sideways to a T (abduction is -X on both sides because of the mirror convention)
bones: { upperArmR: [-90, 0, 0], upperArmL: [-90, 0, 0] }
// fist at the chin: upper arm forward 40, elbow 130
bones: { upperArmR: [0, 0, 40], foreArmR: [0, 0, 130] }
// torso wound up to the right (front toward the camera) and leaning forward, head kept on the opponent
hips: { rot: [0, -30, 0] }, bones: { spine: [0, -10, -8], chest: [0, -10, -6], neck: [0, 18, 4], head: [0, 26, 0] }
// high knee (FK): thigh up 90, shin back 90, toes pointed
bones: { thighL: [0, 0, 90], shinL: [0, 0, -90], footL: [0, 0, -20] }
// hand targets (IK, preferred for weapons): blade pointing forward and up 40 deg from the right hip, true edge down
ik: { handR: { pos: [0.3, 1.0, 0.18], aim: [0.77, 0.64, 0], up: [-0.64, 0.77, 0] } }
```

---

## 5. Clips and poses

```js
import { defineClip, definePose, mirrorClip, mirrorPose } from '../char/index.js';
```

* `definePose(name, channels)` — a static key (no `t`). Keys can start from a pose with `pose: 'name'`.
* `defineClip(name, def)` — registers raw data; compiled lazily per rig. `play()` of a pose name holds that pose.
* `mirrorClip(src, dst, { events, hands = 'swap' })` / `mirrorPose(src, dst)` — left/right mirror: swap L/R bones
  and effectors, negate `s` of positions / aims / poles, negate X and Y of centre-bone and IK Euler rotations, swap
  `curl`, `mainHand`, `gripHand`. `hands: 'keep'` mirrors the body, legs and the hand / weapon paths but keeps each
  hand's job (a right-handed greatsword cuts the mirrored arc: `demo.combo1M`); `'swap'` suits twin blades and
  unarmed moves. `events` optionally renames markers. A hand never grips the weapon it holds itself.
* `listClips()`, `listPoses()`, `hasClip(name)`, `invalidateClips()` (after re-defining while authoring live).

### Clip definition

| field | default | meaning |
|---|---|---|
| `duration` | last key `t` | seconds |
| `loop` | `false` | looping clips get a closing key at `t = duration` copied from the first key (per channel) unless you key `t = duration` yourself (needed when the end differs from the start, e.g. origin-space feet) |
| `base` | `'neutral'` | pose / clip / inline channel object filling every channel the clip never keys |
| `keys` | — | array of keys (any order; sorted by `t`) |
| `events` | `[]` | `[{ t, name, data }]` markers (`onEvent`) |
| `mainHand` | `'R'` | hand holding the weapon |
| `gripHand` | `'L'` | hand that IKs to the weapon grip when `grip` > 0 |
| `gripAt` | `'grip'` | grip point name in `design.weapon.grips` (`'blade'` for half-swording ...) |
| `breath` | `1` | scale of procedural breathing during this clip |
| `look` | `true` | `false` ignores `char.lookAt` during this clip |

### Key channels

Every channel is optional on a key; each channel is interpolated only between the keys that define it.

| channel | format | notes |
|---|---|---|
| `t` | seconds | |
| `ease` | Ease name (`core/math.js`) or fn | remaps time on the segment **ending** at this key, for every channel of the key. Default `'linear'` (smooth spline through the keys) |
| `interp` | `'auto'` \| `'linear'` \| `'step'` | segment ending at this key. `auto`: clamped Catmull-Rom (passes through keys, never overshoots a keyed value, holds stop dead) |
| `pose` | pose name | start from that pose's channels; the key's own channels override |
| `bones` | `{ bone: [x,y,z] }` or `{ bone: { r: [x,y,z], ease, interp } }` | FK degrees (section 4). Quaternion splines (shortest path). Per-bone `ease` / `interp` override the key's |
| `hips` | `{ pos: [f,u,s], rot: [x,y,z], ease, interp }` | `pos` = offset of the pelvis from its rest position (m). `rot` = pelvis Euler, **interpolated per component** so multi-turn spins work (`[0, 300, 0]`) |
| `ik` | `{ handR \| handL \| footR \| footL: target }` | see below |
| `grip` | `0..1` or `{ v, ease }` | off hand (`gripHand`) holds the weapon grip point `gripAt` by IK |
| `curl` | `[left, right]` 0 open .. 1 fist | fingers; a gripping hand is forced to a fist |
| `look` | `{ at: [f,u,s], w }` or `null` | head look-at target in the fighter frame |
| `root` | `[f, u]` or `{ pos, ease, interp }` | **cumulative** root motion at this key (start at `[0,0]`). `rootDelta` reports its change per update |

### IK targets

```js
ik: { handR: { pos, aim, up, rot, pole, w, space, ease, interp } }
```

| field | meaning |
|---|---|
| `pos` | **hands**: centre of the fist (the grip axis). **feet**: the sole point straight under the ankle (`u = 0` = flat on the floor) |
| `aim`, `up` | orientation as vectors (preferred): for hands `aim` = where a held blade points (out of the thumb side of the fist), `up` = the blade's back edge (opposite the true edge); for feet `aim` = toe direction, `up` = top of the foot. `up` is orthogonalised |
| `rot` | orientation as fighter-frame Euler `[x,y,z]` (ZXY) relative to the zero pose orientation (hand: blade forward, edge down; foot: toes forward). Not mirrored. |
| `pole` | point `[f,u,s]` (fighter frame) the elbow / knee should point at. Default: elbows down-back-out in the chest frame, knees over the toes |
| `w` | weight 0..1 (IK vs the FK pose of the same clip); `w: 0` or `null` turns the effector off |
| `space` | `'root'` (default, moves with the root), `'origin'` (the root position at clip start: **planted feet during root motion**), `'hips'` / `'chest'` (bone frame: hands that ride a spinning torso). Spaces may change from key to key; the target blends between them |

Position-only or orientation-only keys are allowed (key `aim` a frame later than `pos` to make the blade lag).
Without any orientation key the end bone keeps its FK orientation (feet stay as the leg puts them).
Feet targets out of reach make the runtime drop the pelvis just enough (planted feet never slide). Feet are re-planted
after additive motion and kept above the floor (heel / sole / ball and toe tip).

### Weapons

The weapon bone sits at the centre of the fist. In the zero hand pose the grip axis is `+X` (blade forward), the edge
`-Y` (true edge down), the flats `+-Z`. Design grip points are in the weapon bone frame (`grip: { pos: [-0.155,0,0] }`
puts the off hand below the main hand on a long grip). Aim weapons with hand IK `aim` / `up`; the tip travels on an
arc because the hand position and the orientation are interpolated separately (position spline + quaternion spline).

### Example: an attack clip

```js
defineClip('kael.light1', {
  duration: 0.95, breath: 0.3,
  keys: [
    { t: 0, pose: 'kael.stance' },
    // anticipation: coil away, blade over the shoulder (ease out = fast start, soft arrival)
    { t: 0.15, ease: 'outCubic', hips: { pos: [-0.1, -0.07, 0.02], rot: [3, -50, 2] },
      bones: { spine: [2, -10, 6], chest: [3, -15, 6], head: [0, 26, -6] },
      ik: { handR: { pos: [-0.08, 1.6, 0.21], aim: [-0.85, 0.28, 0.44], up: [0.25, -0.9, 0.15] } } },
    // hang: hips start to unwind first, the blade still drifts back (lag)
    { t: 0.2, ease: 'inOutSine', hips: { rot: [2, -38, 1] }, ik: { handR: { pos: [-0.04, 1.63, 0.2], aim: [-0.92, 0.04, 0.4] } } },
    // smear: 2-3 frames, an extra key steers the arc over the top
    { t: 0.225, ik: { handR: { pos: [0.22, 1.55, 0.14], aim: [0.15, 0.96, 0.15], up: [-0.95, 0.1, 0.25] } } },
    { t: 0.25, hips: { pos: [0.06, -0.12, -0.01], rot: [-2, 12, -3] },
      ik: { handR: { pos: [0.56, 1.17, 0.03], aim: [0.82, -0.42, -0.38], up: [0.3, 0.8, -0.5] } } },
    // follow-through (ease out), settle, recover to the stance
    { t: 0.34, ease: 'outQuad', pose: 'kael.c1end' },
    { t: 0.95, ease: 'inOutSine', pose: 'kael.stance' },
  ],
  events: [{ t: 0.17, name: 'trailOn' }, { t: 0.245, name: 'hit' }, { t: 0.42, name: 'trailOff' }],
});
```

Chaining: end a hit on (or near) a named link pose and start the next hit from it (`demo.c1end` -> `demo.combo2`);
the game crossfades with `fade: 0.05-0.1` on cancel.

Walk cycles with root motion: key `root: [D, 0]` at `t = duration` with `interp: 'linear'` and move planted feet
linearly backwards in root space at the same speed (see `walk()` in `clips/demo.js`) — or key them in `'origin'`.

---

## 6. Design format

A design is data plus one `build(kit, shapes, rig)` function. It lives outside the runtime
(e.g. `src/fighters/<id>/design.js`).

```js
export const design = {
  id: 'kael', idle: 'kael.idle',
  proportions: { upperArm: 0.31, hipHeight: 1.0 },          // overrides of DEFAULT_PROPORTIONS (skeleton.js)
  materials: { plate: { envMapIntensity: 1.2, detailScale: 4.5, bump: 0.1 }, suit: {...}, blade: {...} },
  bones: [{ name: 'plume1', parent: 'head', at: [-0.03, 0.245, 0], rot?: [x,y,z] | quat?: [x,y,z,w] }, ...],
  springs: [{ bones: ['plume1', 'plume2'], stiffness: 50, damping: 3.5, gravity: 0.45, tip: [-0.07,-0.08,0], limit: 75, radius: 0.02, collide: true, inertia: 1 }],
  colliders: [{ name: 'torso', a: ['spine', [0,0,0]], b: ['chest', [0,0.15,0]], r: 0.17 }, ...],
  cloth: [{ name: 'cape', slot: 'suit', top: [[bone, [x,y,z]], ...], cols: 9, rows: 12, length: 1.1, ... }],
  weapon: { hand: 'R', slot: 'blade', base: [0.09,0,0], tip: [1.47,0,0], grips: { grip: { pos: [-0.155,0,0] }, blade: { pos: [0.56,0,0] } } },
  // or weapons: [{ hand: 'R', ... }, { hand: 'L', ... }]   -> weaponBase2 / weaponTip2 sockets
  sockets: { visor: ['head', [0.14, 0.06, 0]] },
  build(kit, S, rig) { ... },
};
```

| field | notes |
|---|---|
| `proportions` | `hipHeight 0.98, pelvisDrop 0.06, hipWidth 0.10, thighRatio 0.52, ankleHeight 0.085, footLength 0.135, footDrop 0.055, toeLength 0.08, heelLength 0.065, spine 0.11, chest 0.17, neck 0.255, head 0.105, shoulderHeight 0.20, clavicleRoot 0.03, clavicle 0.19, shoulderBack 0.015, upperArm 0.30, foreArm 0.27, hand 0.085, palm 0.022` |
| `materials` | one entry per slot = one draw call. `createKitMaterial` options: `color` (multiplies vertex colour), `roughness` / `metalness` (multiplied by per-vertex values), `envMapIntensity`, `detailScale` (detail tiles per metre), `bump` (detail normal strength), `side: 'double'`, `glowScale` |
| `bones` | extra bones (`at` in the parent's zero frame). Mirror pairs by `...R` / `...L` names |
| `springs` | spring chains: `stiffness` (1/s^2 toward the animated direction), `damping` (1/s), `gravity` (x g), `inertia` (0..1, how much root motion it feels), `limit` (deg cone around the rest direction), `radius` (collision), `tip` (end of the last bone in its frame) |
| `colliders` | capsules for cloth and springs: endpoints = bone + offset (zero frame), radius |
| `cloth` | `top` = pinned edge ordered from the fighter's left (`-s`) to right (`+s`); `cols, rows` (x `quality.cloth`), `length`, `drape [f,u,s]` hang direction, `flare` (relative widening at the bottom), `offset(u,v) -> [f,u,s]`, `pinRows 1`, `thickness 0.012`, `subdiv 2`, `damping 0.035`, `stretch 1 / shear 0.7 / bend 0.25`, `tether 1.04` (max stretch vs rest), `margin 0.025`, `maxSpeed 14`, `gravity 1`, `wind 1`, `inertia 1`, `surface: { outer: { color, rough, detail }, inner: { color, rough, cavity } }` |
| `weapon(s)` | `hand`, `slot` (material slot of its pieces), `base`, `tip` (sockets), `grips` (`{ name: { pos, rot } }` in the weapon bone frame; the off hand takes the weapon frame's orientation plus `rot`) |

### Kit (`build(kit, S, rig)`)

All pieces are authored in a bone's **zero-pose frame** (origin at the joint, +X forward, +Y up, +Z = the fighter's
right / camera side); the kit bakes them into bind space and merges per slot.

| call | meaning |
|---|---|
| `kit.add(slot, bone, geo, opts)` | rigid piece, 100% on `bone` |
| `kit.addPair(slot, base, geo, opts)` | `base+'R'` and its z-mirrored copy on `base+'L'` (`'elbow'` or `'elbowR'`) |
| `kit.addBlend(slot, frameBone, geo, [[bone, w], ...], opts)` | rigid shape split over several bones |
| `kit.addSkinned(slot, geo, (x,y,z,i) => [[bone, w], ...], opts)` | per-vertex weights (bind-space positions; `opts.frame` = author in that bone's frame) |
| `kit.loft(slot, spec, opts)` / `kit.loftPair` | smooth-skinned tube along a bone chain (under-suit, plumes) |
| `kit.bonePos(bone)` | bind-space position of a bone |

`opts` (surface + placement): `at`, `rot` (deg, ZXY), `scale` (placement in the bone frame), `color` (hex sRGB,
`[r,g,b]` linear, or `fn(p, n, i)`), `rough` (0.5), `metal` (0), `detail` (1 = full triplanar detail), `cavity`
(albedo multiplier / AO, number or fn), `glow` (`[r,g,b]` HDR emissive or fn). One slot can mix steel, brass,
leather and glowing slits: these are vertex attributes, not materials.

`loft` spec: `path: [[bone, [x,y,z]], ...]` (centreline control points), `weights: [[k, bone], ...]` (skin stations at
fractional path index k; influence blends smoothly between consecutive stations — put a half-joint helper at a joint
and the neighbouring bones a few cm either side), `rx`, `rz`, `ox`, `oz`, `n` (curves over the path index),
`segs: [radial, rings]`, `caps: [start, end]`.

### Shapes (`S`, `src/char/shapes.js`)

"curve" = number, `[[v, value], ...]` (Catmull-Rom) or `fn(v)`.

| function | notes |
|---|---|
| `shell(o)` | curved plate swept along Y: `y0, y1, rx, rz, ox, oz, n` (superellipse), `a0, a1` (coverage deg, 0 = +X, 90 = +Z), `thick`, `rim` (rolled bead radius), `rimEdges 'tbs'`, `rimTop`, `rimSegs`, `ridge {at, w, h}` / `ridges`, `bulge(u,v)`, `dy(u,v,deg)` (shaped edges), `inner` (default only for open plates), `part 'plate' \| 'rim'` (split to colour rims as trim), `segs [radial, rings]` |
| `lathe(points [[r,y]...], { segs, a0, a1 })` | surface of revolution around Y |
| `tube(points, radius, seg, { closed, caps, scaleZ })` | tube along a polyline (`Vector3`s or `[x,y,z]`) |
| `path(points, n)` | Catmull-Rom samples |
| `blade({ length, width, thick, edge, fuller: {from,to,w,depth}, sections, back })` | faceted blade along +X, edges +-Y |
| `box(w,h,d,radius)`, `sphere(r,ws,hs)`, `cylinder(rt,rb,h,seg)` | rounded primitives |
| `xf(geo, {at, rot, scale})`, `mirrorZ(geo)`, `merge(geos)`, `profile(points)`, `fnOf(x)` | utilities |

Rotations that orient sweeps: `rot: [0,0,90]` maps +Y to -X, `[0,0,-90]` maps +Y to +X, `[90,0,0]` maps +Y to +Z.

---

## 7. Secondary motion

* **Spring bones** (plumes, tassets, straps): verlet tip particles in the fighter frame, pulled to the animated
  direction, gravity, cone limit, capsule collision (tassets ride on the thighs).
* **Cloth**: verlet grid in the fighter frame; each particle drives a bone, the render mesh is part of a merged
  `SkinnedMesh` (outer + lining + rim, bilinear weights), so cloth adds no draw call. Sub-stepped Gauss-Seidel
  constraints, long-range tethers (no runaway stretch), velocity clamp, body capsules + floor with friction, wind
  with deterministic gusts. Root motion feeds back as inertia; jumps > 0.6 m and facing flips do not.
  Hit-stop (`dtGame = 0`) freezes it. Reset hangs the cloth under gravity and pre-settles it (24 steps).
  Detail scales with `ctx.quality.cloth` (grid size and iterations).

---

## 8. Authoring workflow (attack clip)

1. **Block the poses** as `definePose`s: stance, anticipation peak, impact, follow-through (link pose). Check each
   still: `node tools/shot.mjs char --do "__ED.lab.play('pose','kael.c1end')" --at 0.5 --view "0,1.0,0,3.5,0,4" --out shots/char/x`
   (and a 3/4 view, yaw 35). Hands by IK with `aim` / `up`; hips lead (`hips.rot`), chest counter-rotates.
2. **Time it**: anticipation 0.12-0.2 s with `ease: 'outCubic'` into a short hang, the strike in 2-4 frames with one
   intermediate key steering the arc, impact, follow-through with `'outQuad'`, a settle key, recovery.
   Hips start unwinding before the arms; key `aim` one frame later than `pos` for blade lag.
3. **Contact sheet at frame multiples** (the harness advances whole 1/60 s frames — use times that are multiples of
   1/60 or the labels lie):
   ```
   node tools/shot.mjs char --do "__ED.lab.play('clip','kael.light1')" \
     --at 0,0.1,0.15,0.2,0.2167,0.2333,0.25,0.2833,0.3333,0.5,0.75,0.95 --sheet-only \
     --view "0,1.0,0,4.0,0,4" --out shots/char/kael_light1
   ```
   Repeat from a 3/4 view (`yaw 35`). Read the sheet: arc of the tip, edge alignment, interpenetration (blade in the
   floor or the body), foot planting, cape behaviour.
4. **Measure** when in doubt: sample `char.sockets.weaponTip.getWorldPosition()` per frame through `--scenario`
   (tip below `u = 0` = through the floor; planted foot sockets should not move).
5. **Mirror / chain**: `mirrorClip` for the other hand; play the chain in the lab
   (`__ED.lab.play('chain', ['a','b','c'])`) and check the crossfades.
6. Live authoring: `__ED.anim.defineClip(...)`, then `__ED.anim.invalidateClips()` and play it again.

Lab scenarios (`src/labs/char.js`): `reset`, `clip(name, speed)`, `pose(name, t)`, `chain(names)`, `turn(deg, dist)`,
`flip(turn)`, `duel`, `cloth` (stress: whipping root, flips, teleports, attack chain), `joints` (extreme joint test
pose), `bones` (skeleton overlay). The lab applies root motion to `root.position`.

---

## 9. Integration notes

* The character does not register its own `onUpdate`: the game calls `update(dtGame, dtReal)` at `ORDER.CHAR`.
* `root.position.y` > 0 (jumps) is fine: the floor for foot contact and cloth is world `y = 0`.
* Rotating `root` (cinematics) is supported: cloth / springs receive the rotation as inertia, gravity stays world down.
* All character materials share one shader program (`customProgramCacheKey`), so a second fighter costs no compile.
* Determinism: no randomness at runtime; cloth gusts are functions of game time.
