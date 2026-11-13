# 흑일무림 黑日武林 (ECLIPSE DUEL) — 초식 names, move design and skill storyboards

Binding creative brief for the fighter content (`src/fighters/<id>/`), in the murim form of `MURIM.md`. Every name here
is original. Code ids (`kael`, `iska`, `vorn`, move ids, markers, clip and preset names) are unchanged; mechanics,
times and numbers are exactly those of the previous brief. Times are seconds from move start. `f/u/s` = fighter-local
forward / up / side (toward camera). "Beat" notation for each skill: **WIND-UP** (anticipation) → **RELEASE** (smear) →
**IMPACT** (hit-stop, flash) → **AFTERMATH** (lingering FX, follow-through) → **SETTLE** (recover pose).

## Naming rule

Korean reading first, Hanja as the accent, a short English gloss third (the data lives in `src/ui/roster.js`, which
`registry.js` re-exports as `ROSTER`; `moves.js` carries the same names in its `name` fields).

| kind | Korean | form | examples |
|---|---|---|---|
| normals | 기본 초식 | three characters: an image + the technique (斬 cut, 擊 strike, 劈 cleave, 掃 sweep, 突 charge, 刺 thrust, 昇 rise ...) | 사양참 斜陽斬, 빙륜선 氷輪旋, 용미격 龍尾擊 |
| skills | 절기 絶技 | four characters | 잔양비참 殘陽飛斬, 빙순파지 氷筍破地, 낙뢰삼격 落雷三擊 |
| ultimates | 오의 奧義 | four characters, fixed by MURIM.md | 흑일분천 黑日焚天, 빙성낙월 氷星落月, 구천뇌벌 九天雷罰 |

UI vocabulary: 기혈 氣血 (HP) · 내공 內功 (FP) · 오의 奧義 (ultimate gauge) · 호신강기 護身罡氣 (guard; hyper-armour reads
as the same guarding aura) · 경공 輕功 (dodge) · 경초 / 중초 (light / heavy) · 제 n 합 (round n) · 「겨뤄라!」 (fight) ·
「결 決」 (K.O.) · 「무결 無缺」 (perfect) · 「향이 다 탔다」 (time up) · 「승 勝」 / 「패 敗」 · CPU ranks 삼류 / 이류 / 일류 / 절정.

### The full 초식 table

| hero | slot | move id | 초식 | Hanja | English gloss |
|---|---|---|---|---|---|
| 염무강 `kael` | light1 | `light1` | 사양참 | 斜陽斬 | Slanting-Sun Cut |
| | light2 | `light2` | 반조격 | 返照擊 | Afterglow Strike |
| | light3 | `light3` | 낙일벽 | 落日劈 | Setting-Sun Cleave |
| | heavy | `sweep` | 염륜소 | 炎輪掃 | Flame-Wheel Sweep |
| | f+heavy | `lunge` | 염마돌 | 炎馬突 | Flame-Steed Charge |
| | d+heavy | `vent` | 승염참 | 昇炎斬 | Rising-Flame Cut |
| | skill1 · 절기 | `crescent` | 잔양비참 | 殘陽飛斬 | Waning-Sun Flying Slash |
| | skill2 · 절기 | `eruption` | 열지분염 | 裂地噴炎 | Earth-Rending Eruption |
| | skill3 · 절기 | `bulwark` (+ `bulwark_burst`) | 열양호신 (· 반진) | 烈陽護身 (· 反震) | Blazing-Sun Ward (— Recoil) |
| | ult · 오의 | `pyre` | 흑일분천 | 黑日焚天 | Black Sun Burns the Heavens |
| 설리화 `iska` | light1 | `rime_flick` | 한광섬 | 寒光閃 | Cold-Gleam Flash |
| | light2 | `twin_moons` | 쌍월전 | 雙月剪 | Twin-Moon Shears |
| | light3 | `star_fan` | 성선무 | 星扇舞 | Star-Fan Dance |
| | heavy | `glacier_pirouette` | 빙륜선 | 氷輪旋 | Ice-Wheel Whirl |
| | f+heavy | `frostline_step` | 은하도 | 銀河渡 | Silver-River Crossing |
| | d+heavy | `rising_crescent` | 신월승 | 新月昇 | New-Moon Rising |
| | skill1 · 절기 | `starshard_volley` | 한성삼사 | 寒星三射 | Three Cold-Star Shots |
| | skill2 · 절기 | `crystal_procession` | 빙순파지 | 氷筍破地 | Ice Shoots Break the Earth |
| | skill3 · 절기 | `moonlit_afterimage` | 월영환신 | 月影幻身 | Moon-Shadow Phantom |
| | ult · 오의 | `frozen_star` | 빙성낙월 | 氷星落月 | Frost Star, Falling Moon |
| 뇌진천 `vorn` | light1 | `flash_jab` | 전광자 | 電光刺 | Lightning-Flash Thrust |
| | light2 | `haft_spin` | 용미격 | 龍尾擊 | Dragon-Tail Strike |
| | light3 | `thunder_pierce` | 뇌침관 | 雷針貫 | Thunder-Needle Pierce |
| | heavy | `gale_sweep` | 풍뢰소 | 風雷掃 | Wind-and-Thunder Sweep |
| | f+heavy | `lightning_charge` | 분뢰돌 | 奔雷突 | Racing-Thunder Charge |
| | d+heavy | `skyward_lance` | 충천창 | 衝天槍 | Sky-Piercing Spear |
| | skill1 · 절기 | `thunder_javelin` | 천뢰일척 | 天雷一擲 | Heaven-Thunder, One Throw |
| | skill2 · 절기 | `stormfall` | 낙뢰삼격 | 落雷三擊 | Three Falling Thunderbolts |
| | skill3 · 절기 | `arc_step` | 화뢰섬보 | 化雷閃步 | Thunder-Form Flash Step |
| | ult · 오의 | `ninefold_storm` | 구천뇌벌 | 九天雷罰 | Ninefold Heaven Thunder Judgment |

## Global feel targets

- Light hits: 0.05–0.07 s hit-stop, small spark burst, 0.15 trauma shake, chroma 0.2.
- Heavy hits: 0.10–0.13 s hit-stop, ink impact frame on counter hits only, 0.35 trauma, radial 0.25, dust ring (진각).
- Skill finishers: 0.14–0.18 s hit-stop, ink impact frame (2–3 frames), 0.5 trauma, chroma 0.6, radial 0.5, light flash.
- Ultimates (오의): super-freeze 0.6 s (world darkens via `env.setMood`, letterbox in, camera cut to the user, the 오의
  banner hangs at the user's side of the screen), then a 4–6 s cinematic lock if the opening hit connects; whiff / block
  = short recovery with a big but harmless VFX.
- Every cinematic shot list below is mirrored automatically for the left-facing fighter (anchor-local frame).
- Wind-ups that used a rune circle now use a formation diagram (진법 陣法: rings of trigram-like bars, star points, seal
  script — the `rune` marker and decal kind keep their names); plate armour is layered martial robes with a few
  lamellar accents, so glowing "armour cracks" are inner energy seeping through seams and embroidery.

---

## 염무강 炎武剛 (`kael`) — 적염패도 赤焰覇刀 · the Crimson Flame Tyrant Saber

적양문 赤陽門 (Red Sun Gate) · 참마대도 斬馬大刀, a colossal single-edged great saber held in two hands · 열양진기 烈陽眞氣.
Slow, enormous arcs, guard aura (hyper-armour) on heavies. Palette: red-gold 열양 core → ember orange → black smoke.
Idle: saber resting on the shoulder, embers dripping from the seams of his robes and the demon half-mask, slow heavy
breathing.

| slot | 초식 | frame feel | notes |
|---|---|---|---|
| light1 | 사양참 斜陽斬 Slanting-Sun Cut | 0.14 startup | diagonal down-right cut, short ember trail of 도기 |
| light2 | 반조격 返照擊 Afterglow Strike | 0.13 | rising backhand, trail continues the arc |
| light3 | 낙일벽 落日劈 Setting-Sun Cleave | 0.24 | overhead into the floor, small floor crack + ember spray, knockdown |
| heavy | 염륜소 炎輪掃 Flame-Wheel Sweep | 0.32, armour 0.12–0.32 | full horizontal 300° spin swing, huge trail, wall of sparks |
| f+heavy | 염마돌 炎馬突 Flame-Steed Charge | 0.26, moves 3.2 m | shoulder-first lunge into a thrust, molten streak behind, crumple |
| d+heavy | 승염참 昇炎斬 Rising-Flame Cut | 0.22 | upward cut that splits the floor, fire geyser, launch |

### skill1 — 잔양비참 殘陽飛斬 Waning-Sun Flying Slash (내공 25, CD 4 s) — projectile
- WIND-UP 0–0.28: blade dragged behind along the floor, sparks and a molten groove trail; hips coil.
- RELEASE 0.28: rising diagonal swing; a burning crescent of blade energy (2.2 m tall, the last sliver of a setting
  sun) detaches and travels forward 11 m/s, scorching a line on the floor, leaving falling cinders. `ember.wave`.
- IMPACT: the crescent bursts into a fire flower + slash decal on the victim; 0.12 hit-stop; heavy level.
- Camera: small push-in on release (kick fov -3), shake 0.3 on impact.

### skill2 — 열지분염 裂地噴炎 Earth-Rending Eruption (내공 35, CD 7 s) — ground line
- WIND-UP 0–0.40: he raises the saber overhead with both hands, the 열양 aura flares, a formation diagram lights
  under his feet.
- RELEASE 0.40: drives the blade into the floor. Cracks race forward 6 m (glowing magma inside the cracks);
  4 pillars of flame erupt along the line, 0.08 s apart, each with rock debris and a ring.
- IMPACT: launch on the first pillar, follow-up pillars juggle. 0.15 hit-stop on the first, 0.06 on the rest.
- Camera: low ground skim toward the opponent following the crack (0.5 s, slowmo 0.6), then cut back.

### skill3 — 열양호신 烈陽護身 Blazing-Sun Ward (내공 30, CD 9 s) — counter
- Stance 0–0.6: saber planted, the seams of his robes blaze; a shell of guarding fire (호신강기) forms.
  If struck during the stance: instant counter, 반진 反震 — the ward bursts outward (`ember.explosion`), 360° fire
  ring, 0.18 hit-stop, ink impact frame, knockdown. Whiff: sheds the shell harmlessly.
- Camera on counter: crash-zoom to him (0.25 s), shake 0.5.

### 오의 — 흑일분천 黑日焚天 Black Sun Burns the Heavens (오의 100)
Opening: 0.6 s super-freeze. World darkens to deep red (`env.setMood({darken: 0.75, tint: 0xff5020})`), letterbox in.
He lifts the great saber to the eclipse; the blade drinks the corona and ignites white-hot.
Opening hit: forward leap-slash covering 4 m (active 0.85–1.0). On hit → cinematic lock 5.2 s.

| t | shot (camera) | action | VFX / post / audio |
|---|---|---|---|
| 0.00 | low-angle hero push-in, dutch 6° | saber raised to the black sun | corona flare on the blade, embers sucked upward (`charge.gather`), `ult_start` riser |
| 0.60 | cut: wide side, slight orbit | leap-slash forward | `ember.slash.heavy`, trail, speedlines, whoosh_huge |
| 1.00 | cut: impact punch-in on victim | blade connects | ink impact frame 3 frames, flash, hit-stop 0.2, chroma 1, radial 0.8 |
| 1.25 | orbit sweep 70° around both | 3 rapid burning cuts (X pattern) | 3 × `ember.slash`, afterimages (경공 trails), 0.06 hit-stop each |
| 2.30 | top-down slam view | he hurls the victim into the air with an upward cut | fire geyser, debris, `hit.crit` |
| 2.80 | ground-level skim looking up, slowmo 0.3 | he leaps after, spins once, saber trailing a full wheel of fire | `ember.inferno` begins, sky turns crimson, music swell |
| 3.90 | cut: crash zoom from far | downward meteor slam carrying the victim to the floor | `ember.meteor`, huge crater decal, ring of flame pillars, flash |
| 4.30 | wide establishing, shake 1.0 | shockwave expands across the terrace, pillars of fire | `ult_impact`, distortion shock, exposure pulse, letterbox out |
| 5.20 | blend back to fight cam | he rises from the crater, saber on the shoulder | embers and smoke linger 3 s |

Damage: 80 + 3×40 + 60 + 260 = 520 (scaled by nothing; the lock is a single combo of its own).

---

## 설리화 雪梨花 (`iska`) — 빙월쌍도 氷月雙刀 · the Frost-Moon Twin Blades

한월궁 寒月宮 (Cold Moon Palace) · 월아쌍도 月牙雙刀, twin crescent blades · 한빙진기 寒氷眞氣.
Fast, precise, airy; mobility and zoning. Palette: moon-white core → pale indigo → white mist.
Idle: hovering slightly on her toes, blades crossed low, sleeves and veil drifting, a slow snowfall of glittering motes.

| slot | 초식 | frame feel | notes |
|---|---|---|---|
| light1 | 한광섬 寒光閃 Cold-Gleam Flash | 0.09 | quick right-hand slash |
| light2 | 쌍월전 雙月剪 Twin-Moon Shears | 0.10 | left then right, two thin trails |
| light3 | 성선무 星扇舞 Star-Fan Dance | 0.16 | spinning double slash, crystalline shards burst, knockback |
| heavy | 빙륜선 氷輪旋 Ice-Wheel Whirl | 0.22 | full-body spin with both blades, frost ring, multi-hit ×3 |
| f+heavy | 은하도 銀河渡 Silver-River Crossing | 0.18, moves 3.5 m | slides forward on a line of ice, slashing through |
| d+heavy | 신월승 新月昇 New-Moon Rising | 0.16 | backflip slash that launches, crescent trail of moonlight |

### skill1 — 한성삼사 寒星三射 Three Cold-Star Shots (내공 20, CD 3.5 s) — projectile
- WIND-UP 0–0.18: crosses blades, three ice shards (빙정) crystallise in a fan around her.
- RELEASE 0.18 / 0.24 / 0.30: shards fire in sequence (14 m/s) with frost ribbons. `frost.shard`.
- IMPACT: each shard shatters into glitter + frost decal; the third one freezes (crumple).

### skill2 — 빙순파지 氷筍破地 Ice Shoots Break the Earth (내공 30, CD 6 s) — ground line
- WIND-UP 0–0.25: stabs both blades into the ground; frost spreads around her feet.
- RELEASE 0.25: a line of ice shoots races forward 7 m, each larger than the last (`frost.spikes`), the last one huge.
- IMPACT: launches; the shoots hold for 0.6 s, then shatter (`frost.shatter`) with glittering debris.
- Camera: side tracking shot along the shoots, slowmo 0.7 on the last one.

### skill3 — 월영환신 月影幻身 Moon-Shadow Phantom (내공 25, CD 7 s) — dodge-attack
- 0–0.12: she blinks backward leaving a frozen afterimage statue (intangible window 0–0.30).
- 0.30: she reappears behind the opponent and slashes; the ice statue shatters forward at the same time (2 hits).
- Camera: whip-pan following the blink (0.2 s), impact punch-in.

### 오의 — 빙성낙월 氷星落月 Frost Star, Falling Moon (오의 100)
Super-freeze 0.6 s: world goes moon-white (`setMood({darken: 0.8, tint: 0x8fc8ff})`), snowfall stops mid-air.
She spins both blades and draws a star formation (성진 星陣) under the opponent. Opening hit: the formation snaps shut
(active 0.75–0.95, unblockable ground formation, avoidable by dodge or by being airborne). On hit → lock 5.4 s.

| t | shot | action | VFX / post / audio |
|---|---|---|---|
| 0.00 | close-up under the veiled hat, slow push | her eyes open, glowing moon-white | frost aura, snow motes swirl, `ult_start` |
| 0.60 | top-down view of the star formation | formation snaps shut, victim frozen in a crystal | `frost.nova`, ice crystal encases victim, `ice_form` |
| 1.20 | ground skim around the crystal, orbit 90° | she dashes around the crystal slashing 6 times | 6 × `frost.slash`, glitter, afterimages, fast cuts |
| 2.40 | cut: wide low angle looking up at the eclipse, slowmo 0.4 | she leaps high, a star chart of light points appears in the sky | stars connect into lines (beam/ribbon), `frost.starfall` charging |
| 3.40 | over-the-shoulder from the air down to the crystal | star lances rain down (12) | `frost.starfall`, each impact a ring + shard burst, rapid flashes |
| 4.40 | cut: impact punch-in, slowmo 0.2 | she lands, crosses blades, crystal + victim shatter | `frost.shatter` huge, inverted ink impact frame, flash, `ice_shatter` |
| 4.90 | wide establishing | frost wave rolls across the terrace, everything rimed | `frost.blizzard` tail, letterbox out |
| 5.40 | blend back | she flicks the frost off her blades | snow glitter lingers |

Damage: 60 + 6×25 + 12×10 + 200 = 530.

---

## 뇌진천 雷震天 (`vorn`) — 천뢰신창 天雷神槍 · the Heaven-Thunder Spear

뇌운보 雷雲堡 (Thundercloud Keep) · 뇌룡창 雷龍槍, a long war spear with a horsehair tassel · 뇌정신공 雷霆神功.
Mid speed, longest reach, explosive dashes and guard-piercing thrusts. Palette: violet-white 뇌기 core, storm violet,
old-gold sparks. Idle: spear held low behind, small arcs crawling along the spear head, the tassel and the rim of his
bamboo hat.

| slot | 초식 | frame feel | notes |
|---|---|---|---|
| light1 | 전광자 電光刺 Lightning-Flash Thrust | 0.11 | quick thrust, long reach (2.4 m) |
| light2 | 용미격 龍尾擊 Dragon-Tail Strike | 0.12 | spins the spear, butt-end strike |
| light3 | 뇌침관 雷針貫 Thunder-Needle Pierce | 0.20 | lunging thrust with a needle of lightning out of the tip, knockback |
| heavy | 풍뢰소 風雷掃 Wind-and-Thunder Sweep | 0.28 | wide low sweep, trip (knockdown), sparks along the floor |
| f+heavy | 분뢰돌 奔雷突 Racing-Thunder Charge | 0.20, moves 4 m | dashes as a streak of lightning (afterimages), guard-piercing |
| d+heavy | 충천창 衝天槍 Sky-Piercing Spear | 0.18 | upward thrust that launches, bolt shoots to the sky |

### skill1 — 천뢰일척 天雷一擲 Heaven-Thunder, One Throw (내공 25, CD 4 s) — projectile
- WIND-UP 0–0.26: spear drawn back over the shoulder, a second spear of pure lightning forms on it.
- RELEASE 0.26: throws the lightning spear (20 m/s) with a crackling ribbon. `volt.javelin`.
- IMPACT: bolt explosion, chain arcs to the floor, stun (crumple).

### skill2 — 낙뢰삼격 落雷三擊 Three Falling Thunderbolts (내공 35, CD 7 s) — targeted strike
- WIND-UP 0–0.45: raises the spear to the sky; clouds above the terrace flicker; a mark scorches under the opponent.
- RELEASE 0.45: a sky bolt strikes the mark (`volt.strike`), then two more 0.12 s apart, the last one huge.
- Camera: tilt up to the sky then crash down to the strike (cut), shake 0.6.

### skill3 — 화뢰섬보 化雷閃步 Thunder-Form Flash Step (내공 20, CD 5 s) — teleport dash
- He dissolves into a bolt and re-forms 4 m forward (passes through the opponent), leaving a lightning line that
  detonates 0.25 s later (`volt.dash` + `volt.chain`). Intangible during travel.

### 오의 — 구천뇌벌 九天雷罰 Ninefold Heaven Thunder Judgment (오의 100)
Super-freeze 0.6 s: world turns violet-black, rain streaks appear frozen (`setMood({darken: 0.8, tint: 0xa080ff})`).
Opening hit: a guard-piercing lightning dash-thrust (active 0.7–0.9, travels 6 m). On hit → lock 5.0 s.

| t | shot | action | VFX / post / audio |
|---|---|---|---|
| 0.00 | low hero angle, rain, lightning silhouettes him under the hat | spear raised, sky bolt hits the spear tip | `volt.strike` into the spear, `volt.charge`, `ult_start` |
| 0.60 | cut: weapon-follow along the spear | lightning dash-thrust | `volt.dash`, speedlines, afterimages |
| 0.90 | impact punch-in, ink impact frame | spear skewers, victim lifted on the spear | flash violet-white, hit-stop 0.2 |
| 1.20 | orbit sweep rising | he hurls the victim upward and throws the spear after them | `volt.javelin` |
| 1.80 | over-the-shoulder looking up | he leaps; nine bolts strike the floating victim in sequence | 9 × `volt.chain`/bolt, rapid flashes, stuttered hit-stops |
| 3.20 | wide low establishing, slowmo 0.35 | he catches the spear mid-air, the storm gathers into it | `volt.storm`, the eclipse corona flickers violet |
| 4.10 | top-down slam view, crash zoom | he drives the victim down with the spear: a colossal pillar of lightning | `volt.strike` huge + pillar, crater, `ult_impact`, flash, shake 1 |
| 5.00 | blend back | he lands, spear twirl, arcs fade | sparks + scorch linger |

Damage: 90 + 9×22 + 230 = 518.
