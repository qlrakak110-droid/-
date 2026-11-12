# ECLIPSE DUEL — roster balance sheet (KAEL · ISKA · VORN)

Owner: balance design (this file and `src/fighters/{kael,iska,vorn}/moves.js`). Creative brief: `MOVES.md`. Rules:
`src/game/logic/README.md`. This is also the **presentation team's reference**: frame data, the marker list of every
move and the three ultimate lock clocks are at the end (generated from the definitions, so they match the files).

## 1. Verdict

**Hard vs hard (the tuning target, 40–60 %): every pairing is inside the band.** 400 games per cross matchup, 200
per mirror, both sides merged:

| hard vs hard | vs KAEL | vs ISKA | vs VORN |
|---|--:|--:|--:|
| **KAEL** | 56 % (P1 side, mirror) | **54 %** | **48 %** |
| **ISKA** | 46 % | 51 % (mirror) | **50 %** |
| **VORN** | 52 % | 50 % | 48 % (mirror) |

- Rounds: average **36.6 s** (median 36.0, p10–p90 20.9–53.2 s), all KOs, **0 time-ups** at every level.
- Ultimates: each fighter fires about one every two rounds (0.45–0.50 per round) and lands **87 % (Kael), 76 % (Iska),
  89 % (Vorn)**. A combo-confirmed ultimate always lands (true combos by design); one thrown raw or as a punish lands
  about half the time for Kael and Vorn (blocked, or avoided by a dodge, the rest). Iska's rune is unblockable but
  ground-only: her misses are dodges and juggled (airborne) victims.
- No degenerate pattern: no move above 35 % of a fighter's use (top: Vorn's Flash Jab 27 %), every move used, no
  infinite (0 hits against the 40-hit / 8 s combo cap; longest combo 31 hits / 3 s, Iska's multi-hits), no long safe
  poke, nobody stuck at range (far-zone time 5–7 %), guard breaks rare (0.02–0.07 per round).
- Identity (MOVES.md) holds and is checked mechanically (§ 6); the three ultimate tick schedules match the storyboards
  exactly (§ 7).
- 2 970 verification matches (2 880 at 1/60 s, 90 at 1/30 s) ran with invariant checks (finite numbers, arena, floor,
  meters, juggle cap, push-boxes, every match ends): no failures. One 8 s "stuck" flag was traced to a legitimate
  combo plus the 0.6 s super-freeze and the 5.4 s lock (§ 10).
- Other levels (reported, not tuned): **normal** favours Kael (big hits against sloppy defence: 72 % vs Iska, 65 % vs
  Vorn); **nightmare** favours Vorn (safe spacing and long combos: 77 % vs Iska, 64 % vs Kael). See § 10.

## 2. Method

- AI vs AI (`createAIController`), the **same level on both sides**, every ordered pairing of the roster (9, mirrors
  included), normal / hard / nightmare, default rules, 1/60 s steps. Final numbers: 200 games per ordered pairing at
  hard (seed 31000), 60 at normal and nightmare (seed 32000), 10 at hard with 1/30 s steps (seed 33000).
- Noise: the standard error of a win rate is about 50 % / √n, so 2.5 points at 400 games. Two runs of the same files
  on different seeds differed by up to 6 points at 400 games, and 11 points at 160. Every decision below was taken at
  400–500 games per matchup on a fixed seed. Runs are deterministic: the same files and seed give the same result,
  bit for bit.
- Besides wins: damage per round (and per second of fighting), clean-hit rate, combos (count, length, damage, cap
  hits), ultimate starts by source (combo cancel or raw) and outcome (lock, blocked, whiffed), guard breaks, perfect
  guards, time-ups, distance zones, and per move: uses, hits, blocks, whiffs, punishes, the opponent's state when a
  whiffed move started, and the move it was cancelled from (this is how the dead routes in § 5 were found).
- A rough model used while tuning: a matchup's win rate follows the time-to-kill ratio
  `(HP_opp / damage-per-round_self) / (HP_self / damage-per-round_opp)`. About 1 point of win rate per 1 % of that
  ratio, centred on 50 % at ratio 1.

## 3. Win-rate matrices (final soak, generated)

**hard** (row beats column; cross matchups merged over both sides; mirrors = P1-side win rate)

| | kael | iska | vorn | overall |
|---|--:|--:|--:|--:|
| kael | 56% (200) | 54% (400) | 48% (400) | 51% |
| iska | 46% (400) | 51% (200) | 50% (400) | 49% |
| vorn | 52% (400) | 50% (400) | 48% (200) | 51% |

**normal** (row beats column; cross matchups merged over both sides; mirrors = P1-side win rate)

| | kael | iska | vorn | overall |
|---|--:|--:|--:|--:|
| kael | 57% (60) | 72% (120) | 65% (120) | 62% |
| iska | 28% (120) | 57% (60) | 52% (120) | 43% |
| vorn | 35% (120) | 48% (120) | 52% (60) | 44% |

**nightmare** (row beats column; cross matchups merged over both sides; mirrors = P1-side win rate)

| | kael | iska | vorn | overall |
|---|--:|--:|--:|--:|
| kael | 53% (60) | 58% (120) | 36% (120) | 48% |
| iska | 42% (120) | 55% (60) | 23% (120) | 38% |
| vorn | 64% (120) | 77% (120) | 47% (60) | 64% |

## 4. Behaviour (final soak, generated)

| level | rounds | avg round | median | p10–p90 | KO | time-ups | combo-cap hits | unfinished | invariant failures |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| normal | 1361 | 38.0 s | 37.3 s | 21.0–55.9 s | 1361 | 0 | 0 | 0 | 1 |
| hard | 4526 | 36.6 s | 36.0 s | 20.9–53.2 s | 4526 | 0 | 0 | 0 | 0 |
| nightmare | 1349 | 34.9 s | 34.5 s | 20.8–49.8 s | 1349 | 0 | 0 | 0 | 0 |

The one normal-level flag is the 8 s "stuck" heuristic catching a legitimate jab string, ultimate and 5.4 s lock in
an Iska mirror (traced, § 10); there are no real invariant failures.

Per fighter (all opponents merged; per round = per round that fighter played):

| level | fighter | win | dmg / round | clean-hit rate | combos / round | avg combo | longest combo | ult / round | ult lands | ult blocked | ult whiffs | guard breaks / round | perfect guards / round | top move | far-zone time |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|---|--:|
| normal | kael | 62% | 859 | 65% | 5.5 | 2.1 hits / 158 | 11 hits / 662 dmg / 1.95 s | 0.47 | 82% | 16% | 1% | 0.03 | 1.86 | light1 25% | 6% |
| normal | iska | 43% | 798 | 65% | 7.6 | 4.7 hits / 105 | 31 hits / 471 dmg / 2.77 s | 0.48 | 86% | 0% | 14% | 0.06 | 1.73 | rime_flick 24% | 4% |
| normal | vorn | 44% | 794 | 70% | 6.7 | 2.8 hits / 119 | 16 hits / 530 dmg / 1.78 s | 0.38 | 82% | 14% | 3% | 0.03 | 1.99 | flash_jab 31% | 5% |
| hard | kael | 51% | 814 | 65% | 4.1 | 2.8 hits / 200 | 13 hits / 560 dmg / 2.58 s | 0.46 | 87% | 11% | 1% | 0.02 | 1.38 | light1 23% | 7% |
| hard | iska | 49% | 821 | 68% | 6.5 | 6.2 hits / 127 | 31 hits / 521 dmg / 3 s | 0.50 | 76% | 0% | 24% | 0.07 | 1.40 | rime_flick 20% | 5% |
| hard | vorn | 51% | 825 | 75% | 4.8 | 4.6 hits / 172 | 21 hits / 446 dmg / 3.35 s | 0.45 | 89% | 7% | 3% | 0.02 | 1.36 | flash_jab 27% | 6% |
| nightmare | kael | 48% | 802 | 63% | 3.9 | 2.8 hits / 204 | 13 hits / 788 dmg / 2.48 s | 0.47 | 86% | 10% | 1% | 0.01 | 1.65 | light1 23% | 7% |
| nightmare | iska | 38% | 798 | 69% | 5.8 | 6.8 hits / 137 | 33 hits / 557 dmg / 3.42 s | 0.52 | 63% | 0% | 37% | 0.02 | 1.96 | rime_flick 17% | 6% |
| nightmare | vorn | 64% | 863 | 78% | 4.5 | 5.4 hits / 190 | 17 hits / 538 dmg / 1.93 s | 0.46 | 93% | 4% | 2% | 0.00 | 1.76 | flash_jab 27% | 7% |

Ultimate starts by source at hard (starts / landed / blocked; `raw` = thrown from neutral or as a punish, `c:<move>` = combo cancel):

- **kael**: c:lunge 436/429/0, raw 369/194/152, c:vent 282/282/0, c:sweep 265/265/0, c:crescent 47/45/0
- **iska**: c:glacier_pirouette 453/212/0, c:rime_flick 402/373/0, raw 169/165/0, c:starshard_volley 163/105/0, c:moonlit_afterimage 158/143/0, c:twin_moons 103/96/0, c:star_fan 40/38/0
- **vorn**: c:skyward_lance 389/388/0, c:arc_step 387/387/0, raw 283/143/99, c:lightning_charge 241/229/0, c:thunder_javelin 59/56/0

Move usage at hard (share of that fighter's move starts; uses / clean hits / blocked / whiffed / punished):

- **kael**: light1 23% (12032/4266/5697/1908/365), light2 13% (6627/3565/2851/204/111), sweep 12% (6252/1431/2641/2117/2346), bulwark 10% (5184/0/0/0/1728), light3 9% (4391/3290/1017/84/240), lunge 8% (4056/2716/858/432/851), eruption 8% (3900/6220/852/491/295), vent 7% (3559/2587/574/385/541), crescent 5% (2502/1558/521/439/151), pyre 3% (1399/1215/152/32/122), bulwark_burst 3% (1325/1246/0/79/37)
- **iska**: rime_flick 20% (16875/6485/8367/1884/305), glacier_pirouette 18% (15492/22535/14318/2551/1561), twin_moons 11% (9450/10495/8120/101/19), frostline_step 11% (9098/12691/2066/819/463), starshard_volley 9% (7495/14211/4562/844/41), rising_crescent 8% (7024/4839/1099/1069/1340), moonlit_afterimage 8% (6632/7987/2109/1346/94), star_fan 8% (6560/8201/4124/222/0), crystal_procession 7% (6182/9062/660/707/146), frozen_star 2% (1488/1132/0/356/2)
- **vorn**: flash_jab 27% (18430/7730/7091/3317/317), haft_spin 15% (10253/6392/3467/363/798), gale_sweep 11% (7780/1764/3130/2785/1914), thunder_pierce 11% (7213/12153/1638/191/19), skyward_lance 10% (6713/5506/532/665/605), arc_step 7% (4936/2980/716/1169/102), stormfall 7% (4547/12323/384/276/169), thunder_javelin 6% (4339/2941/787/605/189), lightning_charge 4% (2674/2072/359/252/319), ninefold_storm 2% (1359/1203/99/57/72)

Degenerate-pattern checks:

- normal: none (no move above 35 %, every move used, nobody stuck at range, no safe long pokes)
- hard: none (no move above 35 %, every move used, nobody stuck at range, no safe long pokes)
- nightmare: none (no move above 35 %, every move used, nobody stuck at range, no safe long pokes)

## 5. Balance log (what changed, why, measured effect)

Effects are hard vs hard, 500 games per cross matchup on a fixed seed, against the same seed without the change. "Kael
vs Iska +7" = Kael's win rate against Iska moved 7 points.

Starting point (the files as authored, 400–500 games per matchup, two seeds): Kael vs Iska 45–48 %, **Kael vs Vorn
34–38 %**, **Iska vs Vorn 59–61 %**. That is a rock-paper-scissors loop (Vorn > Kael, Iska > Vorn, Kael ≈ Iska) of about
16 points, which no overall buff or nerf of one fighter can remove (each of those moves two matchups the same way). So
the pass has two kinds of changes: ones that hit one matchup harder than the other (they shrink the loop), and
roster-wide strength changes that centre what is left. Ultimate routes were also cleaned up so the AI (and a player)
is never offered a cancel that mostly whiffs.

| # | fighter | change | why | measured effect |
|---|---|---|---|---|
| 1 | Iska | Glacier Pirouette duration 0.74 → 0.78 s (on block −7 → −10 f) | three hits, hits behind, the most-used and most-damaging Iska move, blocked ~7 000 times per soak and almost never punished: −7 f is just above the −0.12 s the AI (and Kael's 0.14 s jab) can punish | Iska vs Vorn −8, Kael vs Iska +7 |
| 2 | Kael | hurt half-width 0.47 → 0.52 m | the wide armoured body is his stated weakness to fast pressure; against Iska's short-reach strings a bigger target matters far more than against Vorn's tip-range spear | Kael vs Iska −6, Kael vs Vorn −2 (cycle −4) |
| 3 | Kael | Furnace Sweep armour 2 hits → 1 hit (window unchanged, 0.12–0.32) | the second absorbed hit only ever mattered against Iska's multi-hit spins; one hit still eats a single poke (Vorn's jab, haft, sky bolt) | Kael vs Iska −7, Kael vs Vorn −1 (cycle −6) |
| 4 | Kael | HP 1100 → 1230; +6 % damage on every normal and skill (light 48/52/84 → 51/55/89, sweep 118 → 125, lunge 96 → 102, vent 80 → 85, crescent 76 → 81, eruption columns 52/46 → 55/49; bulwark burst and the ultimate unchanged) | brings him back up after 2–3 and the loop changes, through his identity (most HP, biggest hits) rather than speed or safety (making the sweep safer or the stance shorter put Kael vs Iska at 67 %) | chosen between two measured sets on one seed — 1250 HP, 2 armour hits, no damage change: 51 / 44 / 54; 1280 HP, 1 armour hit, +6 %: 57 / 51 / 54 (Kael–Iska / Kael–Vorn / Iska–Vorn). 1230 HP + 1 hit + 6 % splits them: **54 / 48 / 50** (final) |
| 5 | Vorn | Gale Sweep and Lightning Charge are ground-only (`air: false`) | the AI threw both at juggled opponents they cannot reach (~120 and ~210 whiffs per 80 matches) and cancelled the charge into the sweep in the air (0 % connect): a trip and a ground charge should not chase an airborne target | Vorn vs Iska +2–3 (fewer wasted turns), Kael vs Vorn +1 |
| 6 | all | cancel routes that mostly whiff were removed: Iska Glacier Pirouette → Rising Crescent (25 % connect, it is her juggle extender), Iska Frostline Step → ultimate (0 %: the slide juggles, the rune is ground-only), Vorn Thunder Pierce → Stormfall (36 %: the blasted victim recovers before the bolts), Kael Molten Lunge → Furnace Sweep (32 %: the lunge also juggles) | "nothing useless is offered": the AI does not check whether a follow-up can reach an airborne victim, and a player should not be offered a trap | removes the AI's most common wasted turn (the pirouette → Rising Crescent route alone whiffed ~1 300 times in one nightmare soak, then got punished); win rates at hard within noise |
| 7 | Kael, Vorn | the ultimate is no longer offered after the light chain (Kael light1 / light2; Vorn Flash Jab / Haft Spin / Thunder Pierce). Kael: after heavy, f+heavy, d+heavy, both projectiles; Vorn: after f+heavy, d+heavy, javelin, Stormfall, Arc Step | a 0.14 s jab confirming into a 520-damage lock made the ultimate land 93 % of the time: it becomes the payoff of a big hit, and is thrown raw (blockable) more often | ultimate land rate at hard: Kael 93 → 87 %, Vorn 93 → 89 % (raw ultimates ~50 %); Kael −3 / −4 (paid back by 4) |
| 8 | Iska | ultimate lock retimed to the roster storyboard convention (§ 7); added `settle` at cinematicEnd, `data.storyboard` on every lock item, `meta.storyboardAtTrigger` 0.75 and `meta.impact` | Kael and Vorn already used it; MOVES.md times are from move start | none (the lock clock pauses the round; damage unchanged) |

Tried and rejected (same method):

| experiment | result | why rejected |
|---|---|---|
| Kael light1 reach 1.95 → 2.1 m (AI range 2.4) | Kael vs Vorn ±0, Kael vs Iska +3 | no effect where it was needed |
| Molten Lunge armour 1 → 2 hits | ±1 | noise |
| Kael weight 1.15 → 1.0 / 1.05 | ±2 | noise; keeps him the heaviest |
| Kael hurt width 0.47 → 0.42 | Kael vs Iska +9, vs Vorn −2 | grows the loop |
| Furnace Sweep −14 → −12 f + 0.8 s Pyre Bulwark | Kael vs Iska **67 %** | his unsafe tools are the counterplay to Iska |
| Stormfall bolts ground-only (no juggling) | Iska vs Vorn **72 %** | the sky-bolt juggle is Vorn's main damage against Iska |
| ultimate only after big hits for Kael and Vorn (also Kael's vent / crescent, Vorn's Skyward / Arc Step / Pierce) | Iska vs Vorn 74 % | too blunt: the lock is ~20 % of every fighter's damage |
| Stormfall damage −11 % | Kael vs Vorn +3, Iska vs Vorn +2 | not needed after 2–4 |
| Iska Glacier Pirouette → ultimate removed (it whiffs when the spin juggled) | hard: Iska vs Vorn +4, nightmare +2 | noise-level, and Iska's land rate would rise to ~90 % |
| `preferredRange` Kael 1.7 / 2.6, Vorn 1.7 / 2.6 | ±3 except Vorn 1.7 (Vorn +8 vs Kael) | the AI footsies distance barely matters |

## 6. Identity (MOVES.md), checked on the final files

| trait | KAEL slow · heavy · armoured | ISKA fast · mobile · zoning | VORN reach · dash · piercing |
|---|---|---|---|
| light startup (first active frame) | 8 f | **5 f** | 7 f |
| average startup of the six normals | **13.1 f** (slowest) | 9.1 f | 10.9 f |
| average damage per normal hit | **85** | 26 | 52 |
| biggest normal hit | **125** (Furnace Sweep) | 40 | 105 |
| HP | **1230** | 950 | 960 |
| walk / dash speed | 2.1 m/s / 5.6 m/s | **3.1 / 12.1** | 2.6 / 11.2 |
| hyper-armour | **Furnace Sweep (1 hit), Molten Lunge (1 hit), Pyre leap** | – | – |
| armour-piercing | – | – | **Thunder Pierce spike, Lightning Charge, ultimate** |
| light / heavy / longest strike reach | 1.95 / 2.25 / 5.05 m | 1.60 / 2.64 / 4.50 m | **2.42 / 2.65 / 6.10 m** |
| dashes ≥ 3.5 m | ultimate leap | Frostline Step (slide-through) | **Lightning Charge 4 m, Arc Step 4 m, ultimate 6 m** |
| mobility | – | **Frostline Step (pass-through), Moonlit Afterimage (intangible blink behind)** | Arc Step |
| zoning skills | Ember Crescent, Fault Eruption | **Starshard Volley (3 shards, 14 m/s), Crystal Procession (5 spikes, 7 m)** | Thunder Javelin, Stormfall |
| in play (hard) | fewest hits, biggest combos (2.8 hits / 200 damage), 4.1 combos per round | most combos (6.5 per round) and longest strings (6.2 hits / 127) | best clean-hit rate (75 %), most spacing (jab 27 %) |

The orderings above are asserted by the balance check script: startups, damage per hit, HP, feet, armour, piercing,
reach, dashes and Iska's mobility and zoning.

## 7. Ultimate storyboards — the roster convention

MOVES.md times are seconds from **move start**, and the cinematic lock continues that clock from the trigger. So for
all three fighters **storyboard t = trigger move time + lock t**: the anchor is `meta.storyboardAtTrigger`, and every lock
marker, tick and finish carries its storyboard time in `data.storyboard`.

| | anchor (trigger row) | lock | storyboard ticks (checked) | finish | last row (blend back) | cinematicEnd | damage |
|---|--:|--:|---|---|---|---|--:|
| KAEL Pyre of the Black Sun | 1.00 "blade connects" | 5.2 s | 3 × 40 at 1.25 / 1.40 / 1.55, hurl 60 at 2.30 | 260 at 3.90 (meteor) | 5.20 = lock 4.20 (`rise`) | storyboard 6.20 (`settle`) | 80 + 3×40 + 60 + 260 = **520** |
| ISKA Fall of the Frozen Star | 0.75 (the rune's first active frame; "circle snaps shut" in the 0.60 shot) | 5.4 s | 6 × 25 at 1.20 … 2.20, 12 × 10 at 3.40 … 4.28 | 200 at 4.40 (shatter) | 5.40 = lock 4.65 (`blendBack`) | storyboard 6.15 (`settle`) | 60 + 6×25 + 12×10 + 200 = **530** |
| VORN Lance of the Ninefold Storm | 0.90 "spear skewers" | 5.0 s | 9 × 22 at 1.90 … 2.91 (accelerating, inside the 1.80 row) | 230 at 4.10 (slam) | 5.00 = lock 4.10 (`blendBack`) | storyboard 5.90 (`settle`) | 90 + 9×22 + 230 = **518** |

- The rows before the trigger (0.00, 0.60) are on the move clock: the 0.6 s super-freeze, then the opener.
- The engine never emits a lock marker or tick at lock t = 0, so nothing is authored there. The trigger row's
  impact (punch-in, impact frame, flash, 0.2 s hit-stop) rides on `cinematicStart` and the trigger's `hit` event, and
  its parameters are in `meta.impact`. Iska's `crystal` beat sits at lock 0.01.
- The trigger can land anywhere in the active window: Kael 0.85–1.0 (0.85 from the 5 m start distance), Vorn 0.7–0.9
  (0.73 from 5 m). Iska's is always 0.75. The shot list stays anchored on the lock clock; only the hold before
  `cinematicStart` varies.
- The schedules were verified by simulation: each ultimate lands on an idle opponent, every tick fires on its lock
  time (within one step), the lock lasts exactly 5.2 / 5.4 / 5.0 s, and the unscaled damage totals 520 / 530 / 518.

## 8. Frame data

Generated from the definitions (`deriveFrameData`). Times in frames at 60 fps; startup = first active frame; reach = m
from the start position (strikes: box tip incl. motion; projectiles: travel); advantage after the **last** hit
(projectiles at point blank). KD = knockdown / launch (no advantage). `node src/game/logic/test/framedata.mjs <file>` prints
the same table.

### KAEL 카엘 (`kael`)

HP 1230 · walk 2.1 / back 1.55 m/s · weight 1.15 · hurt half-width 0.52 m · height 1.95 m · dash 1.9 m / 0.34 s · backstep 1.45 m · dodge 0.46 s (invuln 0.03–0.3) · AI aggression 0.42 zoning 0.4 preferred range 2.2 m

| move | slot | startup | active | recov | total | dmg | hits | reach | on hit | on block | level | cost | cd | notes |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|---|---|--:|---|
| `light1` | light | 8 | 3 | 14 | 25 | 51 | 1 | 1.95 | +4 | -5 | light | – | – | cancel |
| `light2` | light (chain) | 8 | 3 | 17 | 28 | 55 | 1 | 2.15 | +2 | -7 | light | – | – | cancel, moves 0.3 m |
| `light3` | light (chain) | 14 | 3 | 25 | 42 | 89 | 1 | 2.35 | KD | -12 | knockdown | – | – | cancel, moves 0.4 m |
| `sweep` | heavy | 19 | 5 | 28 | 52 | 125 | 1 | 2.25 | +4 | -14 | heavy | – | – | armour, cancel |
| `lunge` | f+heavy | 16 | 5 | 26 | 47 | 102 | 1 | 5.05 | +26 | -17 | crumple | – | – | armour, cancel, moves 3.2 m |
| `vent` | d+heavy | 13 | 5 | 25 | 43 | 85 | 1 | 1.85 | KD | -16 | launch | – | – | cancel |
| `crescent` | skill1 | 17 | 0 | 28 | 44 | 81 | 1 | 10.80 | +2 | -12 | heavy | FP 25 | 4 s | projectile, cancel |
| `eruption` | skill2 | 26 | 0 | 19 | 60 | 202 | 4 | 6.98 | KD | -8 | launch | FP 35 | 7 s | projectile, cancel |
| `bulwark` | skill3 | – | 0 | – | 55 | 0 | 0 | 0.00 | – | – | – | FP 30 | 9 s | counter stance |
| `bulwark_burst` | counter follow-up | 3 | 4 | 35 | 42 | 125 | 1 | 2.30 | KD | – | knockdown | – | – | invuln, unblockable |
| `pyre` | ult | 51 | 9 | 39 | 99 | 80 | 1 | 6.10 | -21 | -28 | heavy | ULT 100 | – | armour, cinematic, moves 4.0 m |

Eruption's 202 is all four columns (55 + 3 × 49); a real hit takes one to three (about 100–150). Ember Crescent's −12 on
block is at point blank; from its usual 3 m+ it is safe. Pyre's 80 is the opener only: the lock adds 440 (520 in all).
Pyre Bulwark's counter window is 0.04–0.6 s (strikes and projectiles); the burst is 125, unblockable, knockdown.

### ISKA 이스카 (`iska`)

HP 950 · walk 3.1 / back 2.4 m/s · weight 0.9 · hurt half-width 0.38 m · height 1.8 m · dash 2.9 m / 0.24 s · backstep 2 m · dodge 0.38 s (invuln 0.02–0.28) · AI aggression 0.55 zoning 0.65 preferred range 2.2 m

| move | slot | startup | active | recov | total | dmg | hits | reach | on hit | on block | level | cost | cd | notes |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|---|---|--:|---|
| `rime_flick` | light | 5 | 2 | 11 | 18 | 24 | 1 | 1.60 | +5 | -2 | light | – | – | cancel |
| `twin_moons` | light (chain) | 6 | 2 | 10 | 22 | 36 | 2 | 1.84 | +8 | -1 | light | – | – | cancel, moves 0.2 m |
| `star_fan` | light (chain) | 10 | 4 | 16 | 34 | 50 | 2 | 2.20 | +11 | -5 | heavy | – | – | cancel, moves 0.3 m |
| `glacier_pirouette` | heavy | 13 | 8 | 22 | 47 | 82 | 3 | 2.64 | +6 | -10 | heavy | – | – | cancel, moves 0.5 m |
| `frostline_step` | f+heavy | 11 | 10 | 18 | 38 | 44 | 2 | 4.50 | +8 | -13 | heavy | – | – | cancel, moves 3.5 m |
| `rising_crescent` | d+heavy | 10 | 4 | 24 | 37 | 40 | 1 | 1.74 | KD | -16 | launch | – | – | cancel, moves -0.2 m |
| `starshard_volley` | skill1 | 11 | 0 | 19 | 37 | 74 | 3 | 11.42 | +35 | -5 | crumple | FP 20 | 3.5 s | projectile, cancel |
| `crystal_procession` | skill2 | 15 | 0 | 17 | 47 | 124 | 5 | 7.71 | KD | -2 | launch | FP 30 | 6 s | projectile, cancel |
| `moonlit_afterimage` | skill3 | 18 | 3 | 21 | 42 | 66 | 2 | 4.29 | +7 | -11 | heavy | FP 25 | 7 s | projectile, invuln, teleport, cancel, moves -0.8 m |
| `frozen_star` | ult | 45 | 12 | 30 | 87 | 60 | 1 | 6.00 | -15 | – | heavy | ULT 100 | – | invuln, cinematic, unblockable, ground only |

Crystal Procession's 124 is all five spikes (a victim normally takes one or two). Starshard Volley's advantage is at
point blank (more plus at range). Moonlit Afterimage: intangible 0–0.3 s, reappears behind at 0.24, cut at 0.30 and the
statue from the original side; a guard-holder takes exactly one of the two. Frozen Star's −15 is the whiff figure.

### VORN 볼른 (`vorn`)

HP 960 · walk 2.6 / back 2 m/s · weight 1 · hurt half-width 0.41 m · height 1.9 m · dash 2.9 m / 0.26 s · backstep 1.85 m · dodge 0.42 s (invuln 0.02–0.29) · AI aggression 0.52 zoning 0.55 preferred range 2.1 m

| move | slot | startup | active | recov | total | dmg | hits | reach | on hit | on block | level | cost | cd | notes |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|---|---|--:|---|
| `flash_jab` | light | 7 | 2 | 14 | 23 | 36 | 1 | 2.42 | +3 | -5 | light | – | – | cancel, moves 0.1 m |
| `haft_spin` | light (chain) | 7 | 2 | 17 | 26 | 32 | 1 | 2.52 | +2 | -10 | light | – | – | cancel, moves 0.7 m |
| `thunder_pierce` | light (chain) | 12 | 5 | 20 | 38 | 66 | 2 | 3.71 | +10 | -8 | heavy | – | – | armour-pierce, cancel, moves 0.5 m |
| `gale_sweep` | heavy | 17 | 5 | 24 | 46 | 105 | 1 | 2.65 | KD | -12 | knockdown | – | – | ground only, cancel, moves 0.2 m |
| `lightning_charge` | f+heavy | 12 | 7 | 25 | 44 | 68 | 1 | 6.10 | +25 | -18 | crumple | – | – | armour-pierce, ground only, cancel, moves 4.0 m |
| `skyward_lance` | d+heavy | 11 | 4 | 23 | 38 | 58 | 1 | 2.07 | KD | -13 | launch | – | – | cancel, moves 0.1 m |
| `thunder_javelin` | skill1 | 16 | 0 | 25 | 41 | 72 | 1 | 10.25 | +29 | -12 | crumple | FP 25 | 4 s | projectile, cancel |
| `stormfall` | skill2 | 27 | 0 | 10 | 52 | 112 | 3 | target | KD | +5 | launch | FP 35 | 7 s | projectile, cancel |
| `arc_step` | skill3 | 26 | 0 | 11 | 37 | 55 | 1 | 4.02 | +19 | +2 | heavy | FP 20 | 5 s | projectile, invuln, cancel, moves 4.0 m |
| `ninefold_storm` | ult | 42 | 12 | 27 | 81 | 90 | 1 | 8.70 | -12 | -19 | heavy | ULT 100 | – | invuln, cinematic, armour-pierce, moves 6.0 m |

Stormfall's +5 and Arc Step's +2 on block are point-blank figures for targeted / trailing projectiles: the sky bolts
land on the marker wherever Vorn stands (usually 3 m+ away), and Arc Step's detonation trails a Vorn who is already
past the opponent. Thunder Pierce is −8 but blasts the guard back about 1.2 m, out of every fast punish. Gale Sweep and
Lightning Charge are ground-only (they pass under an airborne opponent).

## 9. Timeline markers per move (presentation reference)

Every move emits `marker` events on its own clock (`t` = s from move start). Ultimate lock markers carry
`cinematic: true` and run on the lock clock (t = 0 at the trigger); ticks and the finish emit their own `marker`.
Impact is never a marker: hang it on the engine `hit` event (contact point, level, hit-stop, label). `data` keys
listed are the ones the definitions set (style = trail style; vfx / fx = effect; cam = shot cue; storyboard = MOVES.md
time). The super-freeze `superFreeze` marker (t = 0) is emitted by the engine for every ultimate.

### KAEL 카엘

| move | markers (t s: name [data]) | hit labels | projectile kinds (spawn t) |
|---|---|---|---|
| `light1` | 0: **windup** · 0.08: **trailOn** [style=light] · 0.11: **swing** · 0.23: **trailOff** · 0.27: **recover** | – | – |
| `light2` | 0: **windup** [continues=light1] · 0.07: **trailOn** [style=rising] · 0.1: **swing** · 0.22: **trailOff** · 0.28: **recover** | – | – |
| `light3` | 0: **windup** · 0.13: **trailOn** [style=overhead] · 0.17: **swing** · 0.24: **crack** [decal=crack embers=true shake=0.35] · 0.33: **trailOff** · 0.44: **recover** | – | – |
| `sweep` | 0: **windup** [armour=true] · 0.12: **armour** · 0.23: **trailOn** [style=huge] · 0.27: **swing** · 0.32: **sparks** [vfx=wall of sparks shake=0.35] · 0.47: **trailOff** · 0.58: **recover** | – | – |
| `lunge` | 0: **windup** · 0.06: **charge** [vfx=magma streak afterimage=true] · 0.18: **trailOn** [style=thrust] · 0.22: **swing** · 0.4: **trailOff** · 0.5: **recover** | – | – |
| `vent` | 0: **windup** · 0.15: **trailOn** [style=rising] · 0.18: **split** [decal=crack] · 0.19: **swing** · 0.22: **geyser** [vfx=fire geyser] · 0.34: **trailOff** · 0.46: **recover** | – | – |
| `crescent` | 0: **windup** [coil=true] · 0.04: **drag** [vfx=sparks + molten groove] · 0.04: **trailOn** [style=drag] · 0.28: **release** [kickFov=-3] · 0.28: **detach** [vfx=ember.wave] · 0.4: **trailOff** · 0.5: **recover** | – | ember.wave (0.28) |
| `eruption` | 0: **windup** · 0.08: **rune** [decal=rune circle] · 0.2: **aura** [vfx=ember aura] · 0.32: **trailOn** [style=overhead] · 0.4: **release** [shake=0.4] · 0.4: **crack** [length=6 speed=18.75 cam] · 0.44: **column1** [f=1.5] · 0.46: **trailOff** · 0.52: **column2** [f=3] · 0.6: **column3** [f=4.5] · 0.68: **column4** [f=6] · 0.74: **recover** [wrench=true] | – | ember.column (0.4+0.04), ember.column (0.4+0.12), ember.column (0.4+0.2), ember.column (0.4+0.28) |
| `bulwark` | 0: **windup** [plant=true] · 0.02: **trailOn** [style=glow] · 0.04: **release** · 0.04: **shell** [vfx=ember shell] · 0.6: **shed** · 0.62: **trailOff** · 0.66: **recover** | – | – |
| `bulwark_burst` | 0: **windup** · 0: **counter** [cam] · 0.02: **trailOn** [style=glow] · 0.04: **release** · 0.05: **explode** [vfx=ember.explosion ring=360 impactFrame=true shake=0.5] · 0.22: **trailOff** · 0.38: **recover** | – | – |
| `pyre` | 0: **windup** [mood letterbox=true] · 0.05: **gather** [vfx=charge.gather audio=ult_start] · 0.35: **ignite** [vfx=corona flare blade=white-hot] · 0.56: **trailOn** [style=huge] · 0.6: **leap** [vfx=ember.slash.heavy speedlines=true audio=swing_huge] · 0.8: **release** · 1: **slam** [whiffVfx=ember.slash.heavy shake=0.5] · 1.06: **trailOff** · 1.12: **recover** | leapSlash | – |

**Ultimate lock clock** (5.2 s; storyboard t = 1.00 + lock t):

| lock t | storyboard t | event | name | damage | data |
|--:|--:|---|---|--:|---|
| 0.25 | 1.25 | marker | orbit |  | cam |
| 0.25 | 1.25 | tick | cut1 | 40 | vfx=ember.slash afterimage=true |
| 0.40 | 1.40 | tick | cut2 | 40 | vfx=ember.slash afterimage=true |
| 0.55 | 1.55 | tick | cut3 | 40 | vfx=ember.slash afterimage=true |
| 1.30 | 2.30 | tick | hurl | 60 | vfx=fire geyser audio=hit_crit |
| 1.80 | 2.80 | marker | leapAfter |  | slowmo=0.3 vfx=ember.inferno sky=crimson music=swell |
| 2.40 | 3.40 | marker | spin |  | vfx=ring of fire |
| 2.90 | 3.90 | finish | meteor | 260 | vfx=ember.meteor decal=crater flash=white |
| 3.30 | 4.30 | marker | shockwave |  | shake=1 audio=ult_impact distort=shock letterbox=false |
| 4.20 | 5.20 | marker | rise |  | cam lingerEmbers=3 |
| 5.20 | 6.20 | marker | settle |  |  |

### ISKA 이스카

| move | markers (t s: name [data]) | hit labels | projectile kinds (spawn t) |
|---|---|---|---|
| `rime_flick` | 0: **windup** · 0.05: **trailOn** [blades=R style=light] · 0.07: **swing** · 0.14: **trailOff** · 0.18: **recover** | flick | – |
| `twin_moons` | 0: **windup** · 0.05: **trailOn** [blades=both style=light] · 0.07: **swing** · 0.1: **slashL** · 0.17: **slashR** · 0.22: **trailOff** · 0.26: **recover** | left, right | – |
| `star_fan` | 0: **windup** · 0.08: **trailOn** [blades=both style=spin] · 0.12: **swing** · 0.16: **spin** · 0.25: **shards** · 0.32: **trailOff** · 0.38: **recover** | spin, shards | – |
| `glacier_pirouette` | 0: **windup** · 0.14: **trailOn** [blades=both style=spin] · 0.18: **swing** · 0.22: **spin1** · 0.3: **spin2** · 0.38: **spin3** · 0.38: **frostRing** · 0.46: **trailOff** · 0.52: **recover** | spin, frostRing | – |
| `frostline_step` | 0: **windup** · 0.06: **iceLine** · 0.1: **trailOn** [blades=both style=light] · 0.1: **slide** · 0.16: **swing** · 0.36: **trailOff** · 0.4: **stop** · 0.44: **recover** | slash | – |
| `rising_crescent` | 0: **windup** · 0.1: **flip** · 0.12: **trailOn** [blades=both style=rising] · 0.14: **swing** · 0.3: **trailOff** · 0.5: **land** · 0.52: **recover** | crescent | – |
| `starshard_volley` | 0: **windup** · 0.04: **crystallise** · 0.1: **trailOn** [blades=both style=light] · 0.18: **release** · 0.18: **shard1** · 0.24: **shard2** · 0.3: **shard3** · 0.36: **trailOff** · 0.42: **recover** | – | frost.shard (0.18), frost.shard (0.24), frost.shard (0.3) |
| `crystal_procession` | 0: **windup** · 0.05: **trailOn** [blades=both style=heavy] · 0.12: **stab** · 0.15: **trailOff** · 0.16: **frost** · 0.25: **release** · 0.25: **crack** · 0.25: **spike1** · 0.31: **spike2** · 0.37: **spike3** · 0.43: **spike4** · 0.49: **spike5** [slowmo=0.7] · 0.56: **recover** | – | frost.spike (0.25), frost.spike (0.25+0.06), frost.spike (0.25+0.12), frost.spike (0.25+0.18), frost.spike (0.25+0.24) |
| `moonlit_afterimage` | 0: **windup** · 0.02: **blink** · 0.02: **statue** · 0.12: **vanish** · 0.24: **reappear** · 0.25: **trailOn** [blades=both style=heavy] · 0.27: **swing** · 0.3: **strike** · 0.3: **shatter** · 0.4: **trailOff** · 0.46: **recover** | strike | frost.statue (0+0.32) |
| `frozen_star` | 0: **windup** [mood] · 0.05: **aura** · 0.15: **trailOn** [blades=both style=spin] · 0.35: **rune** [maxRange=6] · 0.6: **release** · 0.75: **snap** · 0.95: **trailOff** · 1.05: **recover** | rune | – |

**Ultimate lock clock** (5.4 s; storyboard t = 0.75 + lock t):

| lock t | storyboard t | event | name | damage | data |
|--:|--:|---|---|--:|---|
| 0.01 | 0.76 | marker | crystal |  | vfx=frost.nova audio=ice_form |
| 0.45 | 1.20 | marker | orbit |  | cam |
| 0.45 | 1.20 | tick | slash1 | 25 | vfx=frost.slash |
| 0.65 | 1.40 | tick | slash2 | 25 | vfx=frost.slash |
| 0.85 | 1.60 | tick | slash3 | 25 | vfx=frost.slash |
| 1.05 | 1.80 | tick | slash4 | 25 | vfx=frost.slash |
| 1.25 | 2.00 | tick | slash5 | 25 | vfx=frost.slash |
| 1.45 | 2.20 | tick | slash6 | 25 | vfx=frost.slash |
| 1.65 | 2.40 | marker | leap |  | slowmo=0.4 cam |
| 1.95 | 2.70 | marker | constellation |  |  |
| 2.65 | 3.40 | marker | starfall |  | cam |
| 2.65 | 3.40 | tick | lance1 | 10 | vfx=frost.starfall |
| 2.73 | 3.48 | tick | lance2 | 10 | vfx=frost.starfall |
| 2.81 | 3.56 | tick | lance3 | 10 | vfx=frost.starfall |
| 2.89 | 3.64 | tick | lance4 | 10 | vfx=frost.starfall |
| 2.97 | 3.72 | tick | lance5 | 10 | vfx=frost.starfall |
| 3.05 | 3.80 | tick | lance6 | 10 | vfx=frost.starfall |
| 3.13 | 3.88 | tick | lance7 | 10 | vfx=frost.starfall |
| 3.21 | 3.96 | tick | lance8 | 10 | vfx=frost.starfall |
| 3.29 | 4.04 | tick | lance9 | 10 | vfx=frost.starfall |
| 3.37 | 4.12 | tick | lance10 | 10 | vfx=frost.starfall |
| 3.45 | 4.20 | tick | lance11 | 10 | vfx=frost.starfall |
| 3.53 | 4.28 | tick | lance12 | 10 | vfx=frost.starfall |
| 3.65 | 4.40 | marker | land |  | slowmo=0.2 |
| 3.65 | 4.40 | finish | shatter | 200 | vfx=frost.shatter impactFrame=invert audio=ice_shatter |
| 4.15 | 4.90 | marker | frostWave |  | vfx=frost.blizzard letterbox=false |
| 4.65 | 5.40 | marker | blendBack |  | cam linger |
| 5.40 | 6.15 | marker | settle |  |  |

### VORN 볼른

| move | markers (t s: name [data]) | hit labels | projectile kinds (spawn t) |
|---|---|---|---|
| `flash_jab` | 0: **windup** · 0.07: **trailOn** [style=thrust] · 0.08: **swing** · 0.19: **trailOff** · 0.24: **recover** | jab | – |
| `haft_spin` | 0: **windup** [continues=flash_jab] · 0.02: **spin** · 0.05: **trailOn** [style=rising] · 0.09: **swing** · 0.21: **trailOff** · 0.27: **recover** | butt | – |
| `thunder_pierce` | 0: **windup** · 0.04: **lunge** · 0.14: **trailOn** [style=thrust] · 0.17: **swing** · 0.25: **spike** [fx=volt.spike length=0.7] · 0.33: **trailOff** · 0.42: **recover** | thrust, spike | – |
| `gale_sweep` | 0: **windup** · 0.2: **trailOn** [style=huge] · 0.24: **swing** · 0.28: **sparks** [fx=floor sparks decal=scorch arc] · 0.42: **trailOff** · 0.5: **recover** | sweep | – |
| `lightning_charge` | 0: **windup** · 0.06: **dash** [afterimage=true fx=volt.dash] · 0.12: **trailOn** [style=thrust] · 0.17: **swing** · 0.38: **stop** · 0.4: **trailOff** · 0.52: **recover** | charge | – |
| `skyward_lance` | 0: **windup** · 0.12: **trailOn** [style=rising] · 0.15: **swing** · 0.18: **bolt** [fx=volt.skybolt from=tip to=sky] · 0.3: **trailOff** · 0.42: **recover** | lance | – |
| `thunder_javelin` | 0: **windup** · 0.04: **form** [fx=volt.charge audio=volt_charge] · 0.18: **trailOn** [style=thrust] · 0.26: **release** [kickFov=-2] · 0.26: **detach** [fx=volt.javelin audio=volt_zap] · 0.36: **trailOff** · 0.44: **recover** | javelin | volt.javelin (0.26) |
| `stormfall` | 0: **windup** · 0.04: **raise** [cam] · 0.08: **mark** [fx=scorch marker at=target] · 0.1: **clouds** [fx=cloud flicker at=sky] · 0.36: **trailOn** [style=overhead] · 0.45: **release** [cam] · 0.45: **strike1** [fx=volt.strike at=target shake=0.35 audio=volt_strike] · 0.55: **trailOff** · 0.57: **strike2** [fx=volt.strike at=target shake=0.4 audio=volt_strike] · 0.69: **strike3** [fx=volt.strike at=target huge=true shake=0.6 audio=volt_strike] · 0.7: **recover** | bolt1, bolt2, bolt3 | volt.strike (0.08+0.37), volt.strike (0.08+0.49), volt.strike (0.08+0.61) |
| `arc_step` | 0: **windup** · 0.06: **trailOn** [style=glow] · 0.08: **release** · 0.08: **blink** [fx=volt.dash afterimage=true] · 0.18: **reappear** [fx=volt.reform line=4] · 0.2: **trailOff** · 0.43: **detonate** [fx=volt.chain at=line shake=0.3] · 0.45: **recover** | detonation | volt.chain (0.43) |
| `ninefold_storm` | 0: **windup** [mood letterbox=true cam] · 0: **freeze** [rain=frozen] · 0.1: **skyBolt** [fx=volt.strike into=spear tip audio=ult_start] · 0.2: **charge** [fx=volt.charge audio=volt_charge] · 0.56: **trailOn** [style=huge] · 0.6: **release** · 0.6: **dash** [fx=volt.dash afterimage=true speedlines=true cam] · 0.66: **swing** · 0.92: **overrun** [fx=volt.strike harmless=true shake=0.4] · 0.98: **trailOff** · 1.05: **recover** | lance | – |

**Ultimate lock clock** (5.0 s; storyboard t = 0.90 + lock t):

| lock t | storyboard t | event | name | damage | data |
|--:|--:|---|---|--:|---|
| 0.05 | 0.95 | marker | lift |  |  |
| 0.30 | 1.20 | marker | hurl |  | cam |
| 0.45 | 1.35 | marker | throw |  | fx=volt.javelin audio=volt_zap |
| 0.90 | 1.80 | marker | leap |  | cam |
| 1.00 | 1.90 | tick | bolt1 | 22 | fx=volt.chain flash=violet |
| 1.16 | 2.06 | tick | bolt2 | 22 | fx=volt.chain flash=violet |
| 1.31 | 2.21 | tick | bolt3 | 22 | fx=volt.chain flash=violet |
| 1.45 | 2.35 | tick | bolt4 | 22 | fx=volt.chain flash=violet |
| 1.58 | 2.48 | tick | bolt5 | 22 | fx=volt.chain flash=violet |
| 1.70 | 2.60 | tick | bolt6 | 22 | fx=volt.chain flash=violet |
| 1.81 | 2.71 | tick | bolt7 | 22 | fx=volt.chain flash=violet |
| 1.91 | 2.81 | tick | bolt8 | 22 | fx=volt.chain flash=violet |
| 2.01 | 2.91 | tick | bolt9 | 22 | fx=volt.strike flash=white last=true |
| 2.30 | 3.20 | marker | catch |  | cam |
| 2.40 | 3.30 | marker | storm |  | fx=volt.storm corona=violet flicker audio=volt_loop |
| 3.20 | 4.10 | finish | slam | 230 | fx=volt.strike huge=true pillar=true decal=crater audio=ult_impact post cam |
| 4.10 | 5.00 | marker | blendBack |  | cam letterbox=false mood=null |
| 4.10 | 5.00 | marker | land |  |  |
| 4.40 | 5.30 | marker | twirl |  | linger |
| 5.00 | 5.90 | marker | settle |  |  |

## 10. Open issues (owners other than balance) and notes

- **Engine, `cinematic.js` (logic):** a lock marker or tick at exactly t = 0 never fires (`passes(0, 0, h)` is
  false), so the sample fighter's `lock_impact` is silently lost. The roster authors nothing at lock 0 (the trigger
  beat rides on `cinematicStart` / the trigger `hit` + `meta.impact`); Iska's `crystal` sits at 0.01. Fix: emit t = 0
  items in `startCinematic`, or have the validator warn.
- **Engine, `defs.js` / `ai.js` (logic):** the validator accepts `ai.role: 'counter'` on a move without a `counter`
  block, and `defend()` then reads `x.mv.counter.t0` and throws (reported by the Iska author). Iska's blink therefore
  uses role `reversal`.
- **Engine, `combat.js` (logic):** a projectile with velocity 0 is judged "in front" by its position, so a ground
  column erupting just behind a guarding victim goes through guard. Kael's columns and Iska's spikes creep forward
  0.5 m/s as a workaround (5–8 cm over their life; presentation can ignore it).
- **AI (logic), affects every balance number here:**
  - block punishes are only attempted below −0.12 s on block, so a −7 f move is never punished from blockstun
    (this was why Glacier Pirouette dominated at −7);
  - combo cancels never check whether the follow-up can reach an airborne victim. The data no longer offers routes that
    mostly whiff, but one useful one remains: Iska's Glacier Pirouette → ultimate lands on a grounded victim and whiffs
    when the spin was a juggle (Iska's ultimate "whiffs" in the tables are mostly this);
  - the AI often answers a targeted column (Stormfall, 0.37 s telegraph) by walking back, which after a 0.22 s
    reaction rarely clears the bolt (from reading `ai.js`), so slow fighters eat more sky bolts in AI play than a
    human would;
  - below nightmare the AI rarely reacts to a ~0.2 s dash attack, so every f+heavy lands often in AI play (reported by
    the Vorn author).
- **Test tools (logic):** `test/soak.mjs` checks "every move of the sample fighter is used", so `runSoak({ def })`
  always fails for any other fighter (it should read `def.moves`). Its 8 s "stuck" heuristic also flags legitimate
  play with the real ultimates: a jab, a four-cancel string, the 0.6 s super-freeze and Iska's 5.4 s lock kept one
  fighter in `attack` for 8.04 s (traced; the only flag in 2 970 checked matches). It should not count lock /
  freeze time. There is no cross-fighter soak in the repo: the
  one used for this sheet (every ordered pairing × level, worker threads, invariant checks, per-move / per-context
  statistics) lives in the balance scratchpad and could move to `src/game/logic/test/` if the logic owner wants it.
- **Skill scaling (design note, not a bug):** at nightmare Vorn wins most matchups (long safe spacing, perfect
  guards, punishes on Kael's slow tools and Iska's whiffed juggles), at normal Kael beats Iska (big damage against
  sloppy defence). The target was hard vs hard; if nightmare is meant to be balanced too, the next levers are Vorn's
  block safety at range (Thunder Pierce's 7 m/s pushback, the chain's cancels on block) and Kael's recovery on his
  slowest tools — both move hard as well, so they need their own pass.
