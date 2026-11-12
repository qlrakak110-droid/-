# ECLIPSE DUEL — fighter move design and skill storyboards

Binding creative brief for the fighter content (`src/fighters/<id>/`). Every name here is original.
Times are seconds from move start. `f/u/s` = fighter-local forward / up / side (toward camera).
"Beat" notation for each skill: **WIND-UP** (anticipation) → **RELEASE** (smear) → **IMPACT** (hit-stop, flash) →
**AFTERMATH** (lingering FX, follow-through) → **SETTLE** (recover pose).

Global feel targets
- Light hits: 0.05–0.07 s hit-stop, small spark burst, 0.15 trauma shake, chroma 0.2.
- Heavy hits: 0.10–0.13 s hit-stop, impact frame on counter hits only, 0.35 trauma, radial 0.25, ground ring.
- Skill finishers: 0.14–0.18 s hit-stop, impact frame (2–3 frames), 0.5 trauma, chroma 0.6, radial 0.5, light flash.
- Ultimates: super-freeze 0.6 s (world darkens via `env.setMood`, letterbox in, camera cut to the user), then a
  4–6 s cinematic lock if the opening hit connects; whiff/block = short recovery with a big but harmless VFX.
- Every cinematic shot list below is mirrored automatically for the left-facing fighter (anchor-local frame).

---

## KAEL 카엘 — 잿불의 집행자 · Cinder Warden
Greatsword, two-handed. Slow, enormous arcs, hyper-armour on heavies. Palette: magma core → ember orange → black smoke.
Idle: blade resting on the shoulder, embers dripping from the cracks in his armour, slow heavy breathing.

| slot | name | frame feel | notes |
|---|---|---|---|
| light1 | 재가르기 Ash Cleave | 0.14 startup | diagonal down-right cut, short ember trail |
| light2 | 역날베기 Back Edge | 0.13 | rising backhand, trail continues the arc |
| light3 | 잿불내려찍기 Cinder Drop | 0.24 | overhead into the floor, small floor crack + ember spray, knockdown |
| heavy | 용광로 휘두르기 Furnace Sweep | 0.32, armour 0.12–0.32 | full horizontal 300° spin swing, huge trail, wall of sparks |
| f+heavy | 돌진 찌르기 Molten Lunge | 0.26, moves 3.2 m | shoulder-first lunge into a thrust, magma streak behind, crumple |
| d+heavy | 분화 올려베기 Vent Launcher | 0.22 | upward cut that splits the floor, fire geyser, launch |

### skill1 — 잿불 초승달 Ember Crescent (FP 25, CD 4 s) — projectile
- WIND-UP 0–0.28: blade dragged behind along the floor, sparks and a molten groove trail; hips coil.
- RELEASE 0.28: rising diagonal swing; a burning crescent wave (2.2 m tall) detaches and travels forward 11 m/s,
  scorching a line on the floor, leaving falling cinders. `ember.wave`.
- IMPACT: wave bursts into a fire flower + slash decal on the victim; 0.12 hit-stop; heavy level.
- Camera: small push-in on release (kick fov -3), shake 0.3 on impact.

### skill2 — 균열 분출 Fault Eruption (FP 35, CD 7 s) — ground line
- WIND-UP 0–0.40: Kael raises the sword overhead with both hands, ember aura flares, rune circle under his feet.
- RELEASE 0.40: drives the blade into the floor. Cracks race forward 6 m (glowing magma inside the cracks);
  4 magma columns erupt along the line, 0.08 s apart, each with rock debris and a ring.
- IMPACT: launch on the first column, follow-up columns juggle. 0.15 hit-stop on the first, 0.06 on the rest.
- Camera: low ground skim toward the opponent following the crack (0.5 s, slowmo 0.6), then cut back.

### skill3 — 화염 갑주 Pyre Bulwark (FP 30, CD 9 s) — counter
- Stance 0–0.6: sword planted, armour cracks blaze; an ember shell forms.
  If struck during the stance: instant counter — Kael explodes outward (`ember.explosion`), 360° fire ring,
  0.18 hit-stop, impact frame, knockdown. Whiff: sheds the shell harmlessly.
- Camera on counter: crash-zoom to Kael (0.25 s), shake 0.5.

### ULT — 일식의 장작 Pyre of the Black Sun (ULT 100)
Opening: 0.6 s super-freeze. World darkens to deep red (`env.setMood({darken: 0.75, tint: 0xff5020})`), letterbox in.
Kael lifts the greatsword to the eclipse; the blade drinks the corona and ignites white-hot.
Opening hit: forward leap-slash covering 4 m (active 0.85–1.0). On hit → cinematic lock 5.2 s.

| t | shot (camera) | action | VFX / post / audio |
|---|---|---|---|
| 0.00 | low-angle hero push-in on Kael, dutch 6° | sword raised to the eclipse | corona flare on the blade, embers sucked upward (`charge.gather`), `ult_start` riser |
| 0.60 | cut: wide side, slight orbit | leap-slash forward | `ember.slash.heavy`, trail, speedlines, whoosh_huge |
| 1.00 | cut: impact punch-in on victim | blade connects | impact frame 3 frames, flash white, hit-stop 0.2, chroma 1, radial 0.8 |
| 1.25 | orbit sweep 70° around both | 3 rapid burning cuts (X pattern) | 3 × `ember.slash`, afterimages of Kael, 0.06 hit-stop each |
| 2.30 | top-down slam view | Kael hurls the victim into the air with an upward cut | fire geyser, debris, `hit.crit` |
| 2.80 | ground-level skim looking up, slowmo 0.3 | Kael leaps after, spins once, sword trailing a full ring of fire | `ember.inferno` begins, sky turns crimson, music swell |
| 3.90 | cut: crash zoom from far | downward meteor slam carrying the victim to the floor | `ember.meteor`, huge crater decal, magma columns ring, white flash |
| 4.30 | wide establishing, shake 1.0 | shockwave expands across the arena, pillars of fire | `ult_impact`, distortion shock, exposure pulse, letterbox out |
| 5.20 | blend back to fight cam | Kael rises from the crater, sword on shoulder | embers and smoke linger 3 s |
Damage: 80 + 3×40 + 60 + 260 = 520 (scaled by nothing; the lock is a single combo of its own).

---

## ISKA 이스카 — 서릿별 무녀 · Froststar Oracle
Twin crescent blades. Fast, precise, airy; mobility and zoning. Palette: starlight white core → cyan → white mist.
Idle: hovering slightly on her toes, blades crossed low, a slow snowfall of glittering motes around her.

| slot | name | frame feel | notes |
|---|---|---|---|
| light1 | 서리 긋기 Rime Flick | 0.09 | quick right-hand slash |
| light2 | 쌍월 Twin Moons | 0.10 | left then right, two thin trails |
| light3 | 별부채 Star Fan | 0.16 | spinning double slash, crystalline shards burst, knockback |
| heavy | 빙결 회전 Glacier Pirouette | 0.22 | full-body spin with both blades, frost ring, multi-hit ×3 |
| f+heavy | 얼음길 Frostline Step | 0.18, moves 3.5 m | slides forward on a line of ice, slashing through |
| d+heavy | 초승 올려치기 Rising Crescent | 0.16 | backflip slash that launches, crescent trail of starlight |

### skill1 — 서릿별 투창 Starshard Volley (FP 20, CD 3.5 s) — projectile
- WIND-UP 0–0.18: crosses blades, three ice shards crystallise in a fan around her.
- RELEASE 0.18 / 0.24 / 0.30: shards fire in sequence (14 m/s) with frost ribbons. `frost.shard`.
- IMPACT: each shard shatters into glitter + frost decal; third one freezes (crumple).

### skill2 — 빙정 행렬 Crystal Procession (FP 30, CD 6 s) — ground line
- WIND-UP 0–0.25: stabs both blades into the ground; frost spreads around her feet.
- RELEASE 0.25: a line of ice spikes races forward 7 m, each larger than the last (`frost.spikes`), the last one huge.
- IMPACT: launches; spikes hold for 0.6 s, then shatter (`frost.shatter`) with glittering debris.
- Camera: side tracking shot along the spikes, slowmo 0.7 on the last spike.

### skill3 — 월광 잔상 Moonlit Afterimage (FP 25, CD 7 s) — dodge-attack
- 0–0.12: Iska blinks backward leaving a frozen afterimage statue (intangible window 0–0.30).
- 0.30: she reappears behind the opponent and slashes; the ice statue shatters forward at the same time (2 hits).
- Camera: whip-pan following the blink (0.2 s), impact punch-in.

### ULT — 떨어지는 서릿별 Fall of the Frozen Star (ULT 100)
Super-freeze 0.6 s: world goes silver-blue (`setMood({darken: 0.8, tint: 0x8fc8ff})`), snowfall stops mid-air.
Iska spins both blades, draws a star-shaped rune circle under the opponent. Opening hit: the circle snaps shut
(active 0.75–0.95, unblockable ground rune, avoidable by dodge or by being airborne). On hit → lock 5.4 s.

| t | shot | action | VFX / post / audio |
|---|---|---|---|
| 0.00 | face close-up on Iska, slow push | eyes open, irises glowing | frost aura, snow motes swirl, `ult_start` |
| 0.60 | top-down view of the rune circle | circle snaps shut, victim frozen in a crystal | `frost.nova`, ice crystal encases victim, `ice_form` |
| 1.20 | ground skim around the crystal, orbit 90° | Iska dashes around the crystal slashing 6 times | 6 × `frost.slash`, glitter, afterimages, fast cuts |
| 2.40 | cut: wide low angle looking up at the eclipse, slowmo 0.4 | Iska leaps high, a constellation of light points appears in the sky | stars connect into lines (beam/ribbon), `frost.starfall` charging |
| 3.40 | over-the-shoulder from Iska in the air down to the crystal | star lances rain down (12) | `frost.starfall`, each impact a ring + shard burst, rapid flashes |
| 4.40 | cut: impact punch-in, slowmo 0.2 | Iska lands, crosses blades, crystal + victim shatter | `frost.shatter` huge, impact frame inverted, white flash, `ice_shatter` |
| 4.90 | wide establishing | frost wave rolls across the arena, everything rimed | `frost.blizzard` tail, letterbox out |
| 5.40 | blend back | Iska flicks the frost off her blades | snow glitter lingers |
Damage: 60 + 6×25 + 12×10 + 200 = 530.

---

## VORN 볼른 — 뇌명의 창기사 · Stormcaller Lancer
War spear. Mid speed, longest reach, explosive dashes and armour-piercing thrusts. Palette: violet-white arc core,
electric violet, gold sparks. Idle: spear held low behind, small arcs crawling along the spear head and the helm horns.

| slot | name | frame feel | notes |
|---|---|---|---|
| light1 | 섬광 찌르기 Flash Jab | 0.11 | quick thrust, long reach (2.4 m) |
| light2 | 회전 쳐올리기 Haft Spin | 0.12 | spins the spear, butt-end strike |
| light3 | 천둥 꿰기 Thunder Pierce | 0.20 | lunging thrust with a lightning spike out of the tip, knockback |
| heavy | 폭풍 휩쓸기 Gale Sweep | 0.28 | wide low sweep, trip (knockdown), sparks along the floor |
| f+heavy | 번개 돌격 Lightning Charge | 0.20, moves 4 m | dashes as a streak of lightning (afterimages), armour-piercing |
| d+heavy | 하늘 꿰뚫기 Skyward Lance | 0.18 | upward thrust that launches, bolt shoots to the sky |

### skill1 — 뇌창 투척 Thunder Javelin (FP 25, CD 4 s) — projectile
- WIND-UP 0–0.26: spear drawn back over the shoulder, a duplicate javelin of pure lightning forms on it.
- RELEASE 0.26: throws the lightning javelin (20 m/s) with a crackling ribbon. `volt.javelin`.
- IMPACT: bolt explosion, chain arcs to the floor, stun (crumple).

### skill2 — 낙뢰 Stormfall (FP 35, CD 7 s) — targeted strike
- WIND-UP 0–0.45: raises the spear to the sky; clouds above the arena flicker; a marker scorches under the opponent.
- RELEASE 0.45: a sky bolt strikes the marker (`volt.strike`), then two more 0.12 s apart, the last one huge.
- Camera: tilt up to the sky then crash down to the strike (cut), shake 0.6.

### skill3 — 섬전 보법 Arc Step (FP 20, CD 5 s) — teleport dash
- Vorn dissolves into a bolt and re-forms 4 m forward (passes through the opponent), leaving a lightning line that
  detonates 0.25 s later (`volt.dash` + `volt.chain`). Intangible during travel.

### ULT — 천벌의 뇌창 Lance of the Ninefold Storm (ULT 100)
Super-freeze 0.6 s: world turns violet-black, rain streaks appear frozen (`setMood({darken: 0.8, tint: 0xa080ff})`).
Opening hit: an armour-piercing lightning dash-thrust (active 0.7–0.9, travels 6 m). On hit → lock 5.0 s.

| t | shot | action | VFX / post / audio |
|---|---|---|---|
| 0.00 | low hero angle, rain, lightning silhouettes Vorn | spear raised, sky bolt hits the spear tip | `volt.strike` into the spear, `volt.charge`, `ult_start` |
| 0.60 | cut: weapon-follow along the spear | lightning dash-thrust | `volt.dash`, speedlines, afterimages |
| 0.90 | impact punch-in, impact frame | spear skewers, victim lifted on the spear | flash violet-white, hit-stop 0.2 |
| 1.20 | orbit sweep rising | Vorn hurls the victim upward and throws the spear after them | `volt.javelin` |
| 1.80 | over-the-shoulder looking up | Vorn leaps; nine bolts strike the floating victim in sequence | 9 × `volt.chain`/bolt, rapid flashes, stuttered hit-stops |
| 3.20 | wide low establishing, slowmo 0.35 | Vorn catches the spear mid-air, the storm gathers into it | `volt.storm`, the eclipse corona flickers violet |
| 4.10 | top-down slam view, crash zoom | Vorn drives the victim down with the spear: a colossal pillar of lightning | `volt.strike` huge + pillar, crater, `ult_impact`, white flash, shake 1 |
| 5.00 | blend back | Vorn lands, spear twirl, arcs fade | sparks + scorch linger |
Damage: 90 + 9×22 + 230 = 518.
