# MURIM.md — binding art direction: 「흑일무림 黑日武林」

**This document supersedes every earlier description of the game's look, names and wording** (CONTRACT.md, MOVES.md,
module READMEs and any task brief written before it). Where a brief says "dark-fantasy knights", "Eclipse Ruins",
"plate armour", "runes", "Starlit Altar", "Ruin Sentinel", "Eclipse Colossus" and so on, translate it with the tables
below. Code identifiers do not change (`kael`, `iska`, `vorn`, clip names, preset names, file names): only what the
player sees and hears.

The owner's direction: a flagship, AAA-grade action game "in murim form" (무림: the Korean martial-arts-fantasy
tradition of wandering masters, sects, inner energy and named sword forms), with a third-person action-RPG mode, at
the level of ambition of the best dark action RPGs. **Everything stays original**: murim is a genre, so its common
vocabulary is free to use (강호, 문파, 내공, 검기, 경공, 초식, 별호, 운기조식, 경지 ...), but never take names,
characters, sects, techniques, stories, UI or designs from a specific existing novel, comic, film or game, and do not
use the famous real-world-derived sects of the genre (no 화산·무당·소림·마교·당가 etc.): our sects are invented.

## 1. World and tone

* **Title:** 「흑일무림 黑日武林」 (subtitle: ECLIPSE DUEL). Once in a hundred years a black sun (흑일, a total eclipse)
  rises over the martial world; that night the masters of the 강호 climb to the ruined summit terrace of the fallen
  Heaven-Martial Sect (천무문 天武門) and settle everything by 비무 (duel) under the eclipse.
* **Look:** ink-wash (수묵) dark fantasy. Ink-black night, the pale corona of the eclipse, warm pools from stone
  lanterns and incense braziers, a sea of clouds below jagged peaks, pines and bamboo as brush silhouettes, faded
  단청 reds and jade greens on ruined timber halls with curved tile roofs. Restraint: three or four hues per frame,
  deep blacks, bright accents only where the eye should go. It must read as East Asian martial fantasy at a glance and
  still be as grim and weighty as a dark action RPG — never cute, never neon, never generic "oriental" kitsch.
* **Energy (기 氣):** power is inner energy made visible: flowing wisps, ink-like trails, heat shimmer, frost breath,
  crawling lightning. Weapons leave 검기/도기 (blade energy) arcs with a brushed, dry-ink edge. Big moments use
  formation diagrams (진법 陣法: concentric rings of trigram-like bars, star charts, seal script — our own patterns)
  instead of western magic circles, and paper talismans, falling leaves, petals, snow and embers as particles.

## 2. Heroes (ids unchanged)

| id | name (display) | title 별호 | sect | weapon | inner art | palette |
|---|---|---|---|---|---|---|
| `kael` | **염무강 炎武剛** (Yeom Mu-gang) | 적염패도 赤焰覇刀 — the Crimson Flame Tyrant Saber | 적양문 赤陽門 (Red Sun Gate) | 참마대도 斬馬大刀: a colossal single-edged great saber (same length, grips and sockets as the greatsword it replaces) | 열양진기 烈陽眞氣 — fire | charred black, ember red-orange, dark bronze |
| `iska` | **설리화 雪梨花** (Seol Ri-hwa) | 빙월쌍도 氷月雙刀 — the Frost-Moon Twin Blades | 한월궁 寒月宮 (Cold Moon Palace) | 월아쌍도 月牙雙刀: twin crescent blades (unchanged shapes, refined) | 한빙진기 寒氷眞氣 — frost | moon white, deep indigo, pearl silver |
| `vorn` | **뇌진천 雷震天** (Noe Jin-cheon) | 천뢰신창 天雷神槍 — the Heaven-Thunder Spear | 뇌운보 雷雲堡 (Thundercloud Keep) | 뇌룡창 雷龍槍: a long war spear with a horsehair tassel (창영) below the head | 뇌정신공 雷霆神功 — lightning | storm violet, old gold, ink black |

Character design language (replaces the plate-armoured knights; **body proportions, skeleton, sockets, weapon lengths,
grip points and colliders stay exactly as they are — 108 clips depend on them**):

* Layered martial robes (무복, 장포) with real cloth weight: crossed collars, wide sashes with hanging ends, split
  skirts / coat tails that follow the legs, wrapped forearms and shins, cloth boots. Armour only as accents: a single
  beast-face pauldron, lamellar (찰갑) chest or shoulder pieces, leather bracers, a waist guard.
* Heads without modelling a realistic face: **염무강** wears a snarling iron demon half-mask (귀면) under a topknot with
  a loose mane and a short cloth headband; **설리화** a veiled wide bamboo hat (죽립 + 면사) or a silver half-mask with
  a long bound tail of hair and a hairpin (비녀); **뇌진천** a deep conical bamboo hat with a cloth face wrap and a
  queue. Eyes glow faintly in the element colour under the hat / mask.
* Silhouettes must stay instantly distinct in pure black: broad and heavy with the huge saber resting on the shoulder;
  slender with twin crescents and floating sleeves / hair; tall under the cone hat with the long tasselled spear.
* Materials: matte silk and hemp with visible weave only up close, worn leather, dark lacquer, forged steel with a
  bright edge, jade / bronze fittings; the element shows as energy seeping through seams, embroidery and the weapon.

## 3. Names and wording

* Techniques are 초식 with a Korean reading and Hanja, usually four characters (e.g. 화룡출해 火龍出海 is the pattern,
  not a name to reuse blindly — invent ours). Normals are plain forms, skills are 절기 絶技, ultimates are 오의 奧義:
  `kael` ult 「흑일분천 黑日焚天」, `iska` ult 「빙성낙월 氷星落月」, `vorn` ult 「구천뇌벌 九天雷罰」.
* UI vocabulary: 비무 (duel), 제 n 합 第n合 (round n), 「겨뤄라!」 (fight), 「결 決」 (K.O.), 「무결 無缺」 (perfect),
  「향이 다 탔다」 (time up: the round timer is an incense stick), 「승 勝」 / 「패 敗」, 생명 → 기혈 氣血 (HP),
  FP → 내공 內功, ultimate gauge → 오의 奧義, guard meter → 호신강기 護身罡氣, difficulty → 삼류 / 이류 / 일류 / 절정.
* Typography: system fonts only (no downloads): a serif / myeongjo stack for Korean and Hanja with brush feeling
  created by procedural ink-stroke frames, seals (낙관) and dry-brush dividers drawn in SVG / canvas, not by a font.
* Bilingual rule: Korean first, Hanja as accent, small English secondary where the current UI has English.

## 4. Arena: 「천무대 天武臺」 (replaces "Eclipse Ruins")

The ruined summit duelling terrace of the fallen sect, same footprint, budgets and API as the current arena:

* A great round stone terrace with a carved formation diagram (eclipse disc at the centre, rings of trigram-like bars
  and star points), cracked and puddled; an older duel's scars; a broken edge open to the cloud sea and the eclipse.
* Around it: toppled and standing stone lanterns (석등) with warm light, bronze incense braziers, broken red timber
  columns and a collapsed hall with curved tile roofs (기와) and faded 단청, a ruined gate (산문) with a hanging name
  board, stone stairs, tattered sect banners with brush calligraphy (our own text, e.g. 天武), paper talismans, twisted
  pines and bamboo, fallen roof tiles and weapon racks. Two colossal guardian statues of armoured martial deities
  (수호무신상) stand in the haze on either side of the vista (they replace the hooded colossi; one of them is the boss
  of the RPG mode). Far peaks rise from the cloud sea like an ink painting.
* Fight view stays calm and readable behind the fighters; detail lives in the cinematic angles.

## 5. Effects, camera, sound

* **VFX:** blade-energy crescents with dry-brush edges; inner-energy auras as flowing wisps; formation diagrams for
  wind-ups; ink-splash impact frames (the existing monochrome impact frame is an ink frame now); falling leaves,
  petals, snow, sparks and embers; dust rings from stomps (진각); afterimages as light-foot (경공) trails. Fire =
  red-gold 열양, frost = moon-white 한빙 with snow crystal bursts, lightning = violet-white 뇌기 with thunder rings.
  The rule stays: bright cores for 1-2 frames, never a white frame, the fighters always readable.
* **Camera:** as before, plus wuxia flourishes on cinematic shots (low sweeping orbits, a held wide "duel" frame with
  the eclipse between the two masters, fast push-ins on a drawn blade).
* **Audio (all synthesised):** pentatonic modes; breathy bamboo flute (대금) leads, plucked zither (가야금 / 거문고)
  figures, deep drums (북, 장구 patterns), gong and small gong accents for round calls and finishers, wind and pine
  ambience, steel rings, energy whooshes and thunder. No voices.

## 6. The action-RPG mode: 「강호행 江湖行」 (was "Eclipse Expedition")

| earlier brief | murim form |
|---|---|
| Eclipse Expedition | 「강호행 江湖行」 — a lone master's road through the black-sun night |
| Starlit Altar (rest point) | 「정심석 靜心石」: a meditation stone under a pine; resting is 운기조식 運氣調息 |
| Dawn Chalice (3 heals) | 「회천단 回天丹」: three restorative pills in a gourd |
| Eclipse Shards (currency) | 「공력 功力」 gathered from fallen foes; lost where you fall, reclaimable once |
| Vigor / Endurance / Might / Arcana | 근골 筋骨 / 기식 氣息 / 외공 外功 / 내공 內功 |
| level | 경지 境地 titles as the level rises: 삼류 → 이류 → 일류 → 절정 → 초절정 → 화경 → 현경 |
| Ruin Sentinel / elite | 흑일교 黑日敎 (our invented Black Sun Cult): 흑일교 무사 (cult swordsman) / 흑일교 호법 護法 (cult protector) |
| The Eclipse Colossus (boss) | 「흑일마신상 黑日魔神像」: one of the two guardian statues, woken and possessed by the black sun |
| mist gate | a curtain of mist between two leaning gate pillars hung with talisman ropes |
| death / victory banners | original brush-calligraphy banners, e.g. 「강호의 이슬이 되다」 / 「마신상 붕괴 · 흑일이 걷힌다」 |

Mechanics, budgets, module layout and ownership of the RPG mode are unchanged (CONTRACT.md).

## 7. What does not change

Engine, budgets, the 60 fps rule, quality tiers, module APIs, ownership, identifiers, the three move sets and their
frame data, the eclipse as the central motif, and the originality rule.
