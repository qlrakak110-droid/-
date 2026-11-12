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
src/char/qa.js               motion-quality metrics (tip arcs, pops, ROM, balance, feet, floor, key continuity ...)
src/labs/char.js             lab page (node tools/build.mjs char)
src/labs/rigqa.js            rig regression suite (section 10)
```

Budgets of the demo knight (high tier): **3 draw calls** (slots `plate`, `suit`, `blade`; +3 in the shadow pass),
~57k triangles, 196 bones (57 animated incl. helpers / fingers / weapon / plume / tassets + 104 cape + 35 tabard cloth
particles), ~0.7 ms CPU per `update()` on desktop over a combat chain (two cloths included; ~0.1 ms without cloth). No per-frame
allocations in `update()`. Contract limits: <= 6 draw calls and <= 60k triangles per character.

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
| `root` | `THREE.Group` to place on the fight line. Model forward is **+X**; the sign of `root.scale.x` carries the facing (mirror), its magnitude the world scale. |
| `scale` | Uniform world scale (getter / setter; `design.scale` sets it at creation). `setFacing` keeps it. A colossus can be the default rig scaled here (cheap) or built from scaled proportions (every rig constant follows the proportions). |
| `bodyScale` | Hips pivot height / 1.04 m of the proportions: pass it as `play(name, { scale })` to retarget a clip authored for the 1.95 m knight (section 5). |
| `setFacing(f, { turn = 0 })` | `+1` face +X, `-1` face -X (instant mirror, the 2.5D-fighter convention: the same side always faces the camera). `turn` > 0 (seconds): the mirror happens at once and the mirrored model spins in through the front. Mirroring always moves a point at side offset `s` by `2s` (a law of the mirror, whatever the timing); doing it while the fighter is seen side-on (as here) puts that jump in depth, where it is least visible. Cloth / springs are unaffected. |
| `facing` | current facing (getter). |
| `bones` | `{ name: THREE.Bone }` — all bones (section 4). |
| `sockets` | `Object3D` markers, world matrices valid after `update()`: `weaponBase`, `weaponTip` (`weaponBase2`/`weaponTip2` ... for more weapons), `handR`, `handL` (centre of the fist), `chest`, `head`, `hips`, `footR`, `footL` (sole), `back`, plus `design.sockets`. |
| `play(name, { fade = 0.1, speed = 1, loop = clip.loop, startAt = 0, restart = false, scale = design.clipScale ?? 1 })` | Crossfade to a clip (or a registered pose: it is held). The fade weight is a smoothstep (no velocity step at either end). Re-playing the clip that is already looping keeps it running unless `restart`. Up to 4 clips blend at once; a 5th folds the two oldest into one frozen snapshot of their current blend (nothing that still carries weight is dropped). `scale` multiplies every positional channel of the clip (hips offset, root motion, IK positions and poles, look target): retargeting. Feet planted when a fade starts stay where they are in the world until the new clip lifts them (foot locks). |
| `clip`, `clipTime`, `clipDuration`, `finished` | state of the newest clip (`finished`: non-looping and at its end). |
| `setClipTime(t)` | External time: the newest clip stops self-advancing until the next `play()`. Events and root motion between the previous and the new time are still produced (forward only). |
| `update(dtGame, dtReal)` | Advance clips, IK, additive motion, springs, cloth; writes bones and socket matrices. Call once per frame. `dtGame = 0` (hit-stop) freezes animation and cloth; the flash still decays on `dtReal`. |
| `rootDelta` | `{ f, u }` root motion (fighter metres) produced by this `update()`: every playing clip contributes by its share of the blend (a walk fading out keeps carrying its planted feet). Not applied unless `applyRootMotion = true`. |
| `onEvent(fn(name, data, clipName))` | Clip markers crossed this update (newest clip only). Returns an unsubscribe function. |
| `flash(color, amount = 1, dur = 0.15)` | Emissive flash on every material (`color`: hex / `THREE.Color` / `[r,g,b]` HDR), fresnel-weighted, quadratic decay over `dur` real seconds. |
| `impulse({ bone = 'body', dir = [-1,0,0], amount = 1 })` | Additive physical flinch that springs back. `dir` is the push direction `[f,u,s]` (a hit from the front pushes `[-1,0,0]`). `'body'`: hips / spine / chest bend away with a lagging head whip and a hips shove; any bone name: that bone alone. `amount` 1 = heavy hit: ~8 deg torso bend + ~12 deg head whip, settles in ~0.4 s; `amount` is clamped to +-4 and stacked hits saturate (head whip <= ~50 deg). Frame-rate independent (sub-stepped). Non-finite input is ignored. |
| `lookAt(target, weight = 1)` | Head + neck track a world `Vector3` / `Object3D` (limited to 75 deg, blended in ~0.1 s); `null` releases. Clips with `look: false` disable it; a clip `look` channel overrides it. |
| `layer(name, clip, { weight = 1, mask = 'upper', additive = false, speed = 1, loop, fade = 0.15 })` | Masked override layer (attack while walking) or additive layer (motion relative to the clip's first frame). Masks: `'upper' 'lower' 'arms' 'head'` or an array of bone names. Override layers solve their own IK. |
| `stopLayer(name, fade = 0.15)` | Fade a layer out and remove it. |
| `breath` | `{ rate = 0.32 Hz, depth = 1 }` procedural breathing (chest, shoulders, head counter-motion), scaled per clip by `clip.breath`. |
| `wind` | `[x,y,z]` world-space wind acceleration for cloth (m/s^2; 2-6 is a stiff breeze). Gusts are added deterministically. |
| `teleport()` | Reset cloth, spring bones, flinch springs and IK memories after placing the character somewhere new. Root moves faster than 30 m/s x body scale x world scale and facing flips are detected automatically (a 20 m/s dash at dt 1/30 is not). |
| `diag` | Diagnostics of the last update: `{ drop, gripErr, footErr, reach: [handR, handL, footR, footL] }` (automatic pelvis drop m, residual two-handed grip error m, planted-foot error m, reach ratios). |
| `weapon` | `{ bone, mesh, material, grips, setVisible(b) }` of the first design weapon (`material` is the blade slot material: tint / glow it for skills). |
| `materials`, `meshes` | `{ slot: material }`, `{ slot: SkinnedMesh }`. |
| `stats` | `{ triangles, drawCalls, bones }`. |
| `prewarm()` | `renderer.compile(scene, camera)` now. |
| `setVisible(b)`, `dispose()` | Visibility; free geometries, materials, bone texture and detach. |

Order of operations inside `update()`: advance clips (events, root motion) -> sample + resolve every active clip
(breathing, FK, automatic pelvis drop, hand / foot IK, that clip's two-handed grip) -> crossfade -> layers -> foot
locks -> flinch springs -> re-plant feet where the blend put them + floor / toe contact -> two-handed grip IK on the
blended grip target -> look-at -> helper bones -> plate followers -> spring bones -> cloth -> bones + sockets.
Breathing is applied before IK, so IK hands and feet stay exactly on their targets; a flinch is a physical push and
moves hands and weapon with the body (feet are re-planted).

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
| `shoulderR/L` (clavicle, points outward) | **depress** (shoulder down); `-X` = shrug up | protract (shoulder forward); `-Y` = pull back | rolls the clavicle, which swings the whole hanging arm forward like a small flexion (+30: elbow moves ~15 cm forward); avoid, use the upper arm |
| `upperArmR/L` | adduct: arm swings across toward the midline; **`-X` = raise sideways (abduct)** | internal rotation (front of the arm turns toward the midline) | **raise forward (flex)**; `-Z` = swing back |
| `foreArmR/L` | (not anatomical — keep 0) | pronation; moved into the hand automatically (forearm stays a hinge; twist is spread by helpers) | **bend the elbow** (0..150) |
| `handR/L` | flex toward the palm (palm side = midline) | pronate (thumb turns toward the midline) | tilt toward the thumb (radial); `-Z` toward the little finger |
| `fingers*`, `fingerTips*`, `thumb*` | driven by the `curl` channel; keys on them are ignored (with a console warning) | | |
| `weaponR/L` (fist centre, grip axis) | roll the blade about its own axis | yaw the blade toward the midline | tip up. Keys are relative to the weapon's rest pose in the fist (the design's `gripAngle`). Aim weapons with hand IK instead |

### Legs (`thigh`, `shin`, `foot`, `toe`)

| bone | `+X` | `+Y` | `+Z` |
|---|---|---|---|
| `thighR/L` | adduct (leg across); **`-X` = abduct (leg out)** | internal rotation (knee turns toward the midline) | **hip flexion (leg forward / knee up)**; `-Z` = leg back |
| `shinR/L` | (keep 0) | (keep 0) | **`-Z` = bend the knee** (0..-150); `+Z` hyperextends |
| `footR/L` (ankle, points forward) | invert (sole turns toward the midline) | toe-in (toes turn toward the midline); `-Y` = toe-out | **toes up (dorsiflex)**; `-Z` = point the foot |
| `toeR/L` (ball of the foot) | — | — | toes up (bend at the ball) |

### Helper bones (driven every frame — never key them)

`deltoidR/L` (child of the clavicle at the shoulder joint, half of the arm swing: pauldrons), `upperArmTwistR/L`
(cancels half of the upper-arm twist near the shoulder), `elbowR/L` / `kneeR/L` (half of the joint angle: couters /
poleyns), `foreArmTwistR/L` (65% of the wrist twist: vambraces), `hipJointR/L` (child of the hips at the hip joint, half
of the thigh swing: groin), `thighTwistR/L` (cancels half of the thigh twist near the hip), `elbowVolR/L` /
`kneeVolR/L` (half-joint + a volume scale that grows with flexion: the under-suit's joint ring only, no plates).
Twist is measured relative to the hanging arm and faded out between 100 and 150 deg of elevation (where it is
ill-defined); twist helpers never jump across +-180 deg (they keep last frame's side). Helper bones take their driven
values in the bind pose, so the suit is undeformed in its bind pose.

**Plate followers** (`design.bones[i].follow = { bone, k }`): a design bone that shares its parent with `bone` takes
`k` x that bone's swing every frame (before spring bones, which then use it as their target). Articulates armour by
data: the knight's tassets follow 55% of the thigh.

### Worked pose examples

```js
// arms hanging relaxed
bones: { upperArmR: [-14, 6, 4], upperArmL: [-14, 6, 4], foreArmR: [0, 0, 16], foreArmL: [0, 0, 16] }
// right arm raised straight forward to shoulder height, elbow straight
bones: { upperArmR: [0, 0, 90] }
// both arms raised sideways to a T (abduction is -X on both sides because of the mirror convention)
bones: { upperArmR: [-90, 0, 0], upperArmL: [-90, 0, 0] }
// fist in front of the chin: upper arm forward 40 and across 25 (adduct), elbow 130
bones: { upperArmR: [25, 0, 40], foreArmR: [0, 0, 130] }
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
| `ease` | Ease name (`core/math.js`) or fn | shapes the segment **ending** at this key, for every channel of the key, as **tangents** (velocity stays continuous through every key): `'out*'` (outQuad / outCubic / outSine ...) = the motion decelerates into this key and stops there (zero velocity on both sides); `'inOut*'` = stops at both ends; `'in*'` = starts from rest at the previous key and **hits this key fast** (an impact: the next segment starts from rest, the one deliberate velocity step — blade into the floor, a foot landing); `'linear'` (default) = smooth spline through the keys. Other eases (`outBack`, `outElastic`, `outBounce`, `snap`, functions) remap time on the segment and break velocity continuity at its ends — use them only for deliberate snaps |
| `interp` | `'auto'` \| `'linear'` \| `'step'` | segment ending at this key. `auto`: clamped Catmull-Rom (passes through keys, never overshoots a keyed value, holds stop dead). `linear`: constant velocity; the keys around a linear run take its slope, so curves flow into and out of it (a planted foot sliding back at root speed lands and lifts without a step) |
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
ik: { handR: { pos, aim, up, rot, pole, w, soft, space, ease, interp } }
```

| field | meaning |
|---|---|
| `pos` | **hands**: centre of the fist (the grip axis). **feet**: the sole point straight under the ankle (`u = 0` = flat on the floor) |
| `aim`, `up` | orientation as vectors (preferred): for hands the **weapon frame**: `aim` = where the held blade points, `up` = the blade's back edge (opposite the true edge) — the hand takes whatever orientation holds the blade that way (the design's `gripAngle` included); for feet `aim` = toe direction, `up` = top of the foot. `up` is orthogonalised. A key with `aim` and no `up` keeps the roll of the neighbouring keys (the previous key's `up` is carried along the turn of the aim; the first such key borrows the next key's); only an effector that never keys `up` uses world +Y |
| `rot` | orientation as fighter-frame Euler `[x,y,z]` (ZXY) relative to the zero pose orientation (hand: blade forward, edge down; foot: toes forward). **Not mirrored**: the same numbers turn both feet toward the same world direction (`footL: { rot: [0, 14, 0] }` turns the left toes out, while FK `footL: [0, 14, 0]` turns them in). Prefer `aim` / `up`, which mean the same thing on both sides |
| `pole` | point `[f,u,s]` (fighter frame) the elbow / knee should point at. Default: elbows down-back-out in the chest frame (then swivelled for the wrist, see below); knees over the toes for a foot below the hip, turning with the reach in the leg's sagittal plane (foot forward at hip height: knee up; foot behind: knee down), continuous for every reach direction except beside the hip above and behind it |
| `w` | weight 0..1 (IK vs the FK pose of the same clip); `w: 0` or `null` turns the effector off |
| `soft` | soft reach: the last fraction of the limb's length over which it eases into full extension (default 0.006: an arm or leg at exactly full reach is ~7 deg bent and 1-2 mm short; `0` = may lock straight, for thrusts / a straight back leg). Per key, interpolated |
| `space` | `'root'` (default, moves with the root), `'origin'` (the root position at clip start: **planted feet during root motion**), `'hips'` / `'chest'` (bone frame: hands that ride a spinning torso). Spaces may change from key to key; the target blends between them |

Position-only or orientation-only keys are allowed (key `aim` a frame later than `pos` to make the blade lag).
Without any orientation key a foot keeps its FK orientation (as the leg puts it) and a hand keeps its FK wrist pose
(it rides the new forearm).

**Arms stay human.** Hand targets choose the elbow's swivel around the shoulder-wrist line (a smooth cost: pole,
wrist, humeral rotation, elbow out of the torso) so that the wrist stays within pronation / supination +-90 deg and
85 deg of bend, the humerus within its rotation range and the elbow out of the body (design collider `torso`). What
the swivel cannot absorb is clamped softly at the wrist (the blade then deviates from the key: the key asked for an
impossible wrist — `qa.jointLimits` lists such frames); a demand past ~140 deg of pronation eases back to neutral at
180 deg, so the hand never jumps between its two limits. Keys that ask for that much can still make the elbow switch
sides in one frame: fix the key (aim / up), it is not reachable by a human arm. Near or past full reach the clavicle rises / protracts toward the target (up to ~24 deg). In a
two-handed grip the off hand may roll around the handle; if the grip point is out of the off arm's reach, the main
hand is pulled toward the off shoulder just enough for both to hold it (`diag.gripErr`). When a crossfade changes the
grip point (pommel -> blade), the off hand lets go and moves with its arm over >= 0.35 s, then re-grips.

**Pelvis drop.** Feet targets on (or just above) the floor that are out of reach lower the hips: a smooth, bounded
drop (at most `design.maxPelvisDrop`, default 0.16 m x body scale), released smoothly (~80 ms) when the foot lifts.
Hips / chest-space feet and feet in the air do not drop the hips. `diag.drop` shows it: more than a few cm means the
clip's hips are too high for its stance — fix the data. Feet are re-planted after flinch / blending (with their
authored knee pole) and kept above the floor: heel, sole and ball pad on the sole plane; the toe bends about its joint
until the toe tip rests exactly on the floor.

### Weapons

The weapon bone sits at the centre of the fist. In the zero hand pose the grip axis is `+X` (blade forward), the edge
`-Y` (true edge down), the flats `+-Z`, tilted toward the little finger by the design's `gripAngle` (a handle crosses
the palm diagonally; the knight uses 40 deg, which keeps wrists in range when the blade continues the forearm line).
Design grip points are in the weapon bone frame (`grip: { pos: [-0.155,0,0] }` puts the off hand below the main hand on
a long grip). Aim weapons with hand IK `aim` / `up` (they describe the weapon frame, so `gripAngle` never changes
where a keyed blade points); the tip travels on an arc because the hand position and the orientation are interpolated
separately (position spline + quaternion spline).

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
  gripAngle: 40,                                            // weapon tilt in the fist (deg, toward the little finger)
  scale: 1, clipScale: 1, maxPelvisDrop: 0.16,              // world scale, default play() scale, drop limit (m x body)
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
| `proportions` | `hipHeight 0.98, pelvisDrop 0.06, hipWidth 0.10, thighRatio 0.52, ankleHeight 0.085, footLength 0.135, footDrop 0.055, toeLength 0.08, heelLength 0.065, spine 0.11, chest 0.17, neck 0.255, head 0.105, shoulderHeight 0.20, clavicleRoot 0.03, clavicle 0.19, shoulderBack 0.015, upperArm 0.30, foreArm 0.27, hand 0.085, palm 0.022`. Every other rig constant follows them: finger / thumb / twist-helper offsets scale with `hand` / `upperArm`; sockets, foot-contact ramps, eye height, breathing, flinch and the teleport threshold with the body scale (hips pivot / 1.04 m). A 4.2x colossus built from 4.2x proportions matches the knight scaled by 4.2 within ~1 mm (normalised) |
| `gripAngle` | default 0. Rest tilt (deg) of both weapon bones toward the little finger; 30-45 recommended for swords, spears, axes |
| `scale`, `clipScale`, `maxPelvisDrop` | world scale of `root` (default 1), default `play()` scale (use `char.bodyScale` for clips authored on the knight), automatic pelvis drop limit (m at body scale 1, default 0.16) |
| `materials` | one entry per slot = one draw call. `createKitMaterial` options: `color` (multiplies vertex colour), `roughness` / `metalness` (multiplied by per-vertex values), `envMapIntensity`, `detailScale` (detail tiles per metre), `bump` (detail normal strength), `side: 'double'`, `glowScale` |
| `bones` | extra bones (`at` in the parent's zero frame). Mirror pairs by `...R` / `...L` names. `follow: { bone, k }` drives the bone by `k` x the swing of a bone with the same parent (articulated plates, section 4); `at` then defaults to that bone's position |
| `springs` | spring chains: `stiffness` (1/s^2 toward the animated direction), `damping` (1/s), `gravity` (x g), `inertia` (0..1, how much root motion it feels), `limit` (deg cone around the rest direction), `radius` (collision), `tip` (end of the last bone in its frame) |
| `colliders` | capsules for cloth and springs: endpoints = bone + offset (zero frame), radius. A design with a cape needs `head` and `neck` capsules (a spin throws the cape up over the head). The capsule named `torso` also keeps the elbows out of the body |
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
| `shell(o)` | curved plate swept along Y: `y0, y1, rx, rz, ox, oz, n` (superellipse), `a0, a1` (coverage deg, 0 = +X, 90 = +Z), `thick`, `rim` (rolled bead radius), `rimEdges 'tbs'`, `rimTop`, `rimSegs`, `ridge {at, w, h}` / `ridges`, `bulge(u,v)`, `dy(u,v,deg)` (shaped edges), `inner` (default: open plates and closed tubes that flare open at an end, e.g. cuffs), `caps [top, bottom]` (closed tubes: end discs for finger / toe tips), `part 'plate' \| 'rim'` (split to colour rims as trim), `segs [radial, rings]` |
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
  with deterministic gusts. Root motion feeds back as inertia; teleports and facing flips do not.
  Hit-stop (`dtGame = 0`) freezes it. Reset hangs the cloth under gravity and pre-settles it (10 steps).
  Capsules move smoothly across the sub-steps, collision also runs inside the constraint iterations (the sheet wraps
  around a limb instead of being torn across it), damping is per 1/120 s and verlet velocities are rescaled when the
  step changes (slow motion and dropped frames behave like 60 fps). The edge rim is oriented per quad (no see-through
  slit along the edges). Detail scales with `ctx.quality.cloth` (grid size and iterations).
* **Spring bones** follow their bone's keyed rotation when a clip keys it (otherwise its rest), are sub-stepped at
  <= 1/120 s with rescaled verlet velocities (same response at 30 / 60 / 120 Hz and in slow motion).

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
   (tip below `u = 0` = through the floor; planted foot sockets should not move). `char.diag` gives the automatic
   pelvis drop (should stay under a few cm: lower the clip's hips instead), the two-handed grip error and the reach
   ratios. `src/char/qa.js` (`auditClip`) gives the rest: joint ranges (a hand listed there is a key asking for an
   impossible wrist), pops, planted-foot drift (< 1 cm: a planted foot keeps its exact key until it lifts), floor
   penetration, key continuity.
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
* Determinism: no randomness at runtime; cloth gusts are functions of game time. The arm IK is a pure function of the
  pose (identical at 30 / 60 / 120 Hz and when scrubbed). Two small memories only act at limits: twist helpers keep
  their side past +-180 deg, and the automatic pelvis drop is released over ~80 ms; `teleport()` clears them.
* Clips shared between body types: `play(name, { scale: char.bodyScale })` (or `design.clipScale`) scales hips offsets,
  root motion and IK targets / poles authored for the 1.95 m knight; hips / chest-space targets scale too.

---

## 10. Rig regression suite

`src/labs/rigqa.js` runs every measurement the rig audit used, on the shipped runtime, for the knight and for ISKA-like
(1.78 m), VORN-like (2.02 m) and 4.2x giant proportions (shared clips retargeted with `bodyScale`), and reduces them
to pass / fail checks:

```
node tools/shot.mjs rigqa --eval "__ED.lab.play('all')"                       # { checks: [{ name, value, limit, pass }], passed, failed }
node tools/shot.mjs rigqa --eval "__ED.lab.play('all', { failedOnly: true })"  # only the failures
node tools/shot.mjs rigqa --eval "__ED.lab.play('all', { only: 'clips', bodies: ['kael'] })"   # one group: clips | runtime | ik | xfade | cloth | cpu
node tools/shot.mjs rigqa --eval "__ED.qa.clip('demo.combo3', 'iska')"         # raw numbers of one clip on one body
```

| group | checks |
|---|---|
| clips (every demo clip x 4 bodies, 60 Hz) | no NaN; hand swing <= 87 deg and twist <= 92 deg (human wrist); twist / deltoid helpers never jump beyond their source bone's own step (> 10 deg); two-handed grip error <= 1 cm; automatic pelvis drop step <= 2.5 cm / frame and its 2nd difference <= 1.2 cm / frame^2; knight only: no velocity step at any key (C1), planted-foot drift <= 1 cm, feet floor penetration <= 5 mm |
| runtime | 5 plays inside one fade window (weapon tip step <= 10 cm); idle <-> guard / walk -> guard grip-point changes (off hand <= 10 cm / frame, back on the grip after the fade); guard blade roll drift; walk -> idle planted foot slide; setFacing on a scaled root; events of a huge dt; flinch 30 Hz vs 120 Hz and 30 stacked hits; 1500-frame API fuzz (NaN, bounded hips) |
| ik | random targets within 95% reach through the full pipeline with breathing on (<= 1 mm); neutral standing hips = 1.04 m; root / hips / chest-space hands with breathing; hips-space foot vs root-space hand; authored knee pole on a planted foot; pelvis-drop sweep continuity and bound; pitched foot targets (heel / ball / toe tip on the floor); default knee pole on 10 target rings around the hip (knee speed <= 7x the target's, knight and giant); upper-arm abduction sweep 0..185 deg (helper continuity); forearm twist 160..200 deg (helper continuity); mirrorClip keep; giant from proportions (sockets / fingers) |
| xfade | 90-pair crossfade matrix (qa.crossfade pops) |
| cloth | combo3 cape vs the head; NaN |
| cpu | ms per update of the knight with both cloths over a 300-frame combat chain (combo1, combo2, combo3, slam), replayed 8 times: the mean of each frame's fastest run (the uncontended cost on a shared machine) <= 1.0 ms |

Run it after any change to `src/char/` and before committing clips that change shared poses. It takes ~45 s on an idle machine (longer under load; the CPU check stays valid under load).
Checks marked `[known, round 1]` are residual single-frame arm switches in demo clips whose keys ask for more wrist and
shoulder rotation than a human has (combo3 at 0.233 s, the mirrored combo1M); they are held to their measured value so
any regression still fails.
