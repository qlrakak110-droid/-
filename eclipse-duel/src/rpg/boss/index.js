// 「흑일마신상 黑日魔神像」 IDOL OF THE BLACK SUN — the boss of 강호행 (README of src/rpg, §5 / §9).
// One of the arena's guardian statues, woken by the eclipse: a 5.7 m stone-and-bronze colossus with a great saber.
//
//   phase 1   흑일횡참 (sweep)  낙일참 (cleave)  관일자 (thrust)  진악각 (stomp)
//   phase 2   at 55 % HP it opens its second eye (개안: a roar that throws the hero back), burns with eclipse fire,
//             rests less between attacks and adds 일식연환 (cut, back cut, cleave) and 흑일강림 (the black sun's fire
//             erupts under the hero four times)
//   opening   breaking its poise drives it to one knee for 3.4 s
//
// Everything a hit needs is frame data (attacks below) next to the clip keys (clips.js, same clock); the VFX hang on
// attack markers in the idol's stage frame.

import * as THREE from 'three';
import { idolDesign } from './design.js';
import { defineIdolClips, T } from './clips.js';
import { withStage } from '../core/stage.js';
import { angDiff, yawTo, hypot2 } from '../core/math3.js';
import { sequence, around } from '../cine.js';

const SCALE = 3;
const NAME = { ko: '흑일마신상 黑日魔神像', en: 'Idol of the Black Sun' };
/** a horizontal cut as three travelling sectors (the blade is where the hit is): dir +1 = right to left */
function cutHits(t0, t1, dir, damage) {
  const seg = (t1 - t0) / 3, sect = dir > 0 ? [[28, 104], [-40, 44], [-106, -26]] : [[-106, -26], [-40, 44], [28, 104]];
  return sect.map((angle, i) => ({ t: [t0 + seg * i - 0.01, t0 + seg * (i + 1) + 0.02], shape: { type: 'arc', r: [1.7, 7.1], angle, u: [0, 2.3] }, damage, level: 'knockdown', poise: 60, hitstop: 0.13, guard: 48, knock: { f: 6.5, u: 3 } }));
}
const cleaveHits = (t) => [
  { t: [t - 0.06, t + 0.03], shape: { type: 'box', f: [1.3, 7.3], s: [-1.0, 1.0], u: [0, 7] }, damage: 150, level: 'knockdown', poise: 80, hitstop: 0.16, guard: 70 },
  { t: [t, t + 0.12], shape: { type: 'sphere', at: [6.2, 0.4, 0], r: 2.7 }, damage: 70, level: 'heavy', poise: 40, hitstop: 0.08, radial: true },
];

const ATTACKS = {
  sweep: {
    name: '흑일횡참', duration: T.sweep.dur, clip: 'rpg.idol.sweep',
    hits: cutHits(T.sweep.a, T.sweep.b, 1, 118),
    track: { until: 0.95, rate: 105 }, armour: [[0, T.sweep.dur]],
    markers: [{ t: 0.62, name: 'glint' }, { t: 1.1, name: 'cut', data: { dir: 1, audio: 'swing_heavy' } }, { t: 1.24, name: 'quake', data: { shake: 0.35 } }],
  },
  cleave: {
    name: '낙일참', duration: T.cleave.dur, clip: 'rpg.idol.cleave',
    hits: cleaveHits(T.cleave.hit),
    track: { until: 1.22, rate: 80 }, armour: [[0, T.cleave.dur]],
    markers: [{ t: 1.1, name: 'glint' }, { t: 1.33, name: 'fall', data: { audio: 'swing_heavy' } }, { t: T.cleave.hit, name: 'crash', data: { shake: 0.9 } }],
    cancel: { from: 2.9 },
  },
  thrust: {
    name: '관일자', duration: T.thrust.dur, clip: 'rpg.idol.thrust',
    hits: [{ t: [T.thrust.a, T.thrust.b], shape: { type: 'box', f: [1.4, 8.4], s: [-0.8, 0.8], u: [0.2, 3.2] }, damage: 126, level: 'knockdown', poise: 70, hitstop: 0.15, guard: 60, knock: { f: 9, u: 2.4 } }],
    track: { until: 0.9, rate: 120 }, armour: [[0, T.thrust.dur]],
    motion: [[0, 0], [0.95, 0], [1.08, 1.3], [T.thrust.dur, 1.3]],
    markers: [{ t: 0.55, name: 'glint' }, { t: 1.0, name: 'lunge', data: { audio: 'swing_heavy', shake: 0.3 } }],
  },
  stomp: {
    name: '진악각', duration: T.stomp.dur, clip: 'rpg.idol.stomp',
    hits: [
      { t: [T.stomp.hit - 0.03, T.stomp.hit + 0.05], shape: { type: 'sphere', at: [1.4, 0.5, -0.6], r: 1.7 }, damage: 120, level: 'knockdown', poise: 70, hitstop: 0.14 },
      { t: [T.stomp.hit, T.stomp.hit + 0.5], shape: { type: 'ring', at: [1.4, 0, -0.6], r: [0.4, 1.7], grow: [11, 11], u: [0, 0.9] }, damage: 62, level: 'knockdown', poise: 40, hitstop: 0.07, radial: true, guard: 30 },
    ],
    track: { until: 0.6, rate: 60 }, armour: [[0, T.stomp.dur]],
    markers: [{ t: T.stomp.hit, name: 'stomp', data: { shake: 0.8 } }],
  },
  eclipse: {
    name: '흑일강림', duration: T.eclipse.dur, clip: 'rpg.idol.eclipse',
    hits: [], track: { until: 1.2, rate: 60 }, armour: [[0, T.eclipse.dur]],
    markers: [{ t: T.eclipse.gather, name: 'gather' }, ...T.eclipse.casts.map((t, i) => ({ t, name: 'cast', data: { i, shake: i ? 0.2 : 0.5 } }))],
  },
  combo: {
    name: '일식연환', duration: T.combo.dur, clip: 'rpg.idol.combo',
    hits: [...cutHits(T.combo.s1[0], T.combo.s1[1], 1, 104), ...cutHits(T.combo.s2[0], T.combo.s2[1], -1, 104), ...cleaveHits(T.combo.hit)],
    track: { until: 2.7, rate: 70 }, armour: [[0, T.combo.dur]],
    markers: [{ t: 0.52, name: 'glint' }, { t: 0.88, name: 'cut', data: { dir: 1, audio: 'swing_heavy' } }, { t: 1.74, name: 'cut', data: { dir: -1, audio: 'swing_heavy' } },
      { t: 2.55, name: 'glint' }, { t: 2.8, name: 'fall', data: { audio: 'swing_heavy' } }, { t: T.combo.hit, name: 'crash', data: { shake: 0.9 } }],
    cancel: { from: 4.2 },
  },
  enrage: {
    name: '개안', duration: T.enrage.dur, clip: 'rpg.idol.enrage',
    hits: [{ t: [T.enrage.roar, T.enrage.roar + 0.4], shape: { type: 'ring', at: [0, 0, 0], r: [0.5, 2.6], grow: [16, 16], u: [0, 4] }, damage: 36, level: 'knockdown', poise: 30, hitstop: 0.05, radial: true, unblockable: true, knock: { f: 8, u: 3.4 } }],
    track: false, invuln: [[0, T.enrage.dur]], armour: [[0, T.enrage.dur]],
    markers: [{ t: 0.3, name: 'crackle' }, { t: T.enrage.roar, name: 'roar', data: { shake: 1.2 } }],
  },
};

// tuning: an autoplaying hero (no real dodging) reaches phase 2 and dies there; a little off the damage keeps the fight
// hard but lets three pills carry a careful player through
for (const atk of Object.values(ATTACKS)) for (const h of atk.hits) h.damage = Math.round(h.damage * 0.85);

/** The idol's mind: close in with a slow march, pick by distance and bearing, rest between attacks (less in phase 2). */
function brain() {
  const OPTIONS = [
    { id: 'stomp', phase: 1, w: 3, ok: (d, ang) => d < 2.4 },
    { id: 'sweep', phase: 1, w: 3, ok: (d, ang) => d < 5.6 && ang < 1.25 },
    { id: 'cleave', phase: 1, w: 2.2, ok: (d, ang) => d > 2.2 && d < 6.4 && ang < 0.6 },
    { id: 'thrust', phase: 1, w: 2.6, ok: (d, ang) => d > 4.4 && d < 9.2 && ang < 0.5 },
    { id: 'combo', phase: 2, w: 3.4, ok: (d, ang) => d < 5.8 && ang < 1.3 },
    { id: 'eclipse', phase: 2, w: 2.2, cd: 11, ok: () => true },
  ];
  return {
    kind: 'idol',
    think(world, a, dt, it) {
      const m = a.data, hero = world.hero;
      if (!hero || !hero.alive) { a.target = null; return; }
      a.target = hero;
      const dx = hero.pos.x - a.pos.x, dz = hero.pos.z - a.pos.z, c = hypot2(dx, dz) || 1;
      const d = c - hero.radius - a.radius;
      const face = yawTo(dx, dz);
      it.face = face;
      m.cool -= dt; m.castCool -= dt;
      if (a.state !== 'idle' && a.state !== 'move') return;
      if (m.phase === 1 && a.hp <= a.hpMax * 0.55) {
        m.phase = 2; m.cool = 0.5;
        world.startAttack(a, 'enrage', { force: true });
        world.emit('bossPhase', { boss: a, phase: 2 });
        return;
      }
      const ang = Math.abs(angDiff(a.yaw, face));
      if (m.cool <= 0 && hero.state !== 'down' && hero.state !== 'getup') {
        let total = 0;
        for (const o of OPTIONS) { o.on = o.phase <= m.phase && o.ok(d, ang) && !(o.cd && m.castCool > 0) && !(o.id === m.last && o.id === m.last2); if (o.on) total += o.w; }
        if (total > 0) {
          let r = world.rng() * total;
          for (const o of OPTIONS) {
            if (!o.on) continue;
            r -= o.w;
            if (r > 0) continue;
            it.attack = o.id;
            m.last2 = m.last; m.last = o.id;
            if (o.cd) m.castCool = o.cd;
            m.cool = ATTACKS[o.id].duration + (m.phase === 2 ? world.rng.range(0.5, 1.1) : world.rng.range(0.8, 1.6));
            return;
          }
        }
      }
      if (d > 4.0) { it.moveX = dx / c; it.moveZ = dz / c; }
    },
  };
}

export default function install(rpg) {
  defineIdolClips();
  let ctx = null;
  rpg.setup((s) => { ctx = s.ctx; });
  const fxOf = () => ctx && ctx.vfx;
  const V = new THREE.Vector3();

  rpg.actor('idol', {
    team: 'foe', name: NAME, boss: true, budget: 'boss', lockable: false, element: 'ember',
    stats: { hp: 3800, poise: 360, radius: 1.25, height: 5.6, scale: SCALE, mass: 60, walk: 1.2, run: 1.2, accel: 5, decel: 8, turn: 85, shards: 1200 },
    design: idolDesign(),
    clips: { idle: 'rpg.idol.idle', walk: 'rpg.idol.walk', run: 'rpg.idol.walk', stagger: 'rpg.idol.kneel', flinch: 'rpg.idol.idle', dead: 'rpg.idol.death', spawn: 'rpg.idol.wake' },
    attacks: ATTACKS,
    roll: null, guard: null,
    spawnTime: T.wake, corpseTime: 6.5,
    controller: () => brain(),
    onSpawn(world, a) {
      // a 5.7 m body flashing white on every hit floods the frame: keep the hit flash a glint
      if (a.view && a.view.flash) { const f = a.view.flash; a.view.flash = (c, k, d) => f(c, (k ?? 1) * 0.2, d); }
      a.data.phase = 1; a.data.cool = 1.2; a.data.castCool = 4; a.data.last = a.data.last2 = '';
      intro(world, a);
    },
    onPoiseBreak(world, a) {
      a.stun('stagger', T.kneel);
      world.fxAt(a, 'combat.guard.break', [1.2, 3.2, 0], { scale: 2.6 });
      world.fxAt(a, 'combat.dust.land', [0, 0, 0], { scale: 3, heavy: true });
      if (ctx) ctx.cam.shake(0.7, { freq: 8 });
    },
    onDeath(world, a) { death(world, a); },
  });

  rpg.encounter({
    id: 'idol', order: 100, boss: true, title: { ko: NAME.ko, en: 'IDOL OF THE BLACK SUN' },
    spawns: [{ kind: 'idol', x: 8.5, z: 0 }],
    heroAt: { x: -4, z: 0, yaw: 0 },
  });

  // ---- staging ------------------------------------------------------------------------------------------------------
  /** The statue wakes: the camera climbs from the saber's tip to the mask while the eyes kindle, then falls back behind the hero. */
  function intro(world, a) {
    const hero = world.hero, cam = world.camera;
    world.emit('bossIntro', { boss: a, phase: 1 });
    const fx = fxOf();
    if (fx) {
      world.fxAt(a, 'combat.dust.land', [0, 0, 0], { scale: 3.2, heavy: true });
      fx.schedule(1.7, () => { if (a.alive) { world.fxAt(a, 'combat.charge.release', [0.6, 4.3, 0], { element: 'eclipse', scale: 2.2 }); world.present.sound('ult_charge', { pos: a.view.pos, volume: 0.8 }); } });
      fx.schedule(3.3, () => { if (a.alive) { world.fxAt(a, 'combat.dust.stomp', [-1, 0, 0.7], { scale: 3, heavy: true }); ctx.cam.shake(0.6, { freq: 8 }); world.present.sound('land', { pos: a.view.pos, volume: 1 }); } });
    }
    if (!cam || !cam.worldShot || !hero) return;
    // three shots: the blade's tip on the stone with the statue beyond it, the mask as the eyes kindle, then low from
    // behind the hero as the idol rises to its full height
    const P = around(a), chest = new THREE.Vector3();
    const hx = hero.pos.x, hz = hero.pos.z, dl = Math.hypot(a.pos.x - hx, a.pos.z - hz) || 1, dx = (a.pos.x - hx) / dl, dz = (a.pos.z - hz) / dl;
    sequence(ctx, world, [
      { dur: 1.4, frame: (e, out) => { P(7.6 - 0.5 * e, 0.32 + 0.1 * e, 2.9 - 0.3 * e, out.pos); P(0.6, 2.3 + 0.4 * e, 0.2, out.look); out.fov = 31; } },
      { dur: 1.3, frame: (e, out) => { P(4.5 - 0.4 * e, 3.0 + 0.2 * e, -1.2 + 0.2 * e, out.pos); P(0.45, 3.45 + 0.25 * e, 0, out.look); out.fov = 27 - 2 * e; } },
      { dur: T.wake - 2.9, frame: (e, out) => { out.pos.set(hx - dx * 3.3 + dz * 1.2, 0.85 + 0.25 * e, hz - dz * 3.3 - dx * 1.2); P(0, 2.6 + 1.0 * e, 0, out.look); out.fov = 41 - 4 * e; } },
    ], { blendOut: 0.9, dof: { focus: () => a.socket('chest', chest), aperture: 0.9, range: 2.6 } });
  }

  /** 개안: the camera closes in on the hunched idol, then cuts under its face for the roar. */
  function enrageCam(world, a) {
    const P = around(a);
    sequence(ctx, world, [
      { dur: T.enrage.roar - 0.36, frame: (e, out) => { P(8.6 - 1.6 * e, 1.1, -2.9, out.pos); P(0.3, 2.9, 0, out.look); out.fov = 38 - 4 * e; } },
      { dur: 1.25, frame: (e, out) => { P(6.8, 0.9 + 0.3 * e, 2.4, out.pos); P(0.3, 4.2 + 0.2 * e, 0, out.look); out.fov = 37 + 7 * e; } },
    ], { blendOut: 0.7 });
  }

  function death(world, a) {
    const fx = fxOf();
    if (a.data.aura) { a.data.aura.stop(); a.data.aura = null; }
    if (!fx) return;
    world.slowmo(0.3, 1.4);
    if (ctx.rpg && ctx.rpg.world === world) {
      // the fall in a slow arc around the idol, then a low wide shot as it becomes a statue again
      const P = around(a), chest = new THREE.Vector3();
      sequence(ctx, world, [
        { dur: 2.4, frame: (e, out) => { const g = 0.45 + 0.85 * e; P(Math.cos(g) * 9.2, 2.7 + 0.5 * e, Math.sin(g) * 9.2, out.pos); P(0.2, 3.3 - 0.9 * e, 0, out.look); out.fov = 36; } },
        { dur: 2.8, frame: (e, out) => { P(12.5 - 1.6 * e, 0.8, -3.2, out.pos); P(0, 2.2, 0, out.look); out.fov = 34; } },
      ], { clock: 'real', blendOut: 1.2, dof: { focus: () => a.socket('chest', chest), aperture: 0.8, range: 3 } });
    }
    world.fxAt(a, 'combat.ko.burst', [0.4, 3.6, 0], { scale: 2.6 });
    fx.schedule(1.9, () => { world.fxAt(a, 'combat.dust.land', [0, 0, 0], { scale: 3.4, heavy: true }); ctx.cam.shake(0.8, { freq: 7 }); world.present.sound('body_fall', { pos: a.view.pos, volume: 1 }); });
    fx.schedule(3.0, () => world.fxAt(a, 'combat.charge.release', [0.5, 2.6, 0], { element: 'eclipse', scale: 2.4 }));
    if (ctx.post && ctx.post.grade) { ctx.post.grade('victory', 2.5); }
  }

  // ---- marker VFX (stage frame = the idol's frame: +X forward, +Z right, metres) -------------------------------------
  const tip = (a) => a.socket('weaponTip', V);
  const MARK = {
    glint(world, a) {
      const p = tip(a);
      const fx = fxOf();
      fx.flare({ kind: 'star', pos: [p.x, p.y, p.z], color: [3.4, 1.9, 0.6], size: 2.6, life: 0.34, intensity: 2.2 });
      world.present.sound('ult_charge', { pos: a.view.pos, volume: 0.35, pitch: 0.7 });
    },
    cut(world, a, e) {
      const dir = (e.data && e.data.dir) || 1;
      withStage(a, () => {
        const fx = fxOf();
        // the blade's path: a flat crescent a hand above the stone, black body under a gold corona, then fire
        fx.slash({ pos: [0.2, 1.25, 0], normal: [0, 1, 0], forward: [1, 0, 0], arc: dir > 0 ? [-108, 108] : [108, -108], radius: 6.9, width: 2.6, look: 'eclipse', sweep: 0.2, life: 0.75, distort: 0.03 });
        fx.slash({ pos: [0.2, 1.1, 0], normal: [0, 1, 0], forward: [1, 0, 0], arc: dir > 0 ? [-104, 104] : [104, -104], radius: 7.0, width: 1.5, look: 'flame', palette: 'ember', sweep: 0.2, life: 0.9, intensity: 0.8 });
        fx.ring({ pos: [0, 0, 0], look: 'dust', radius: [2, 8.5], life: 1.2, alpha: 0.6 });
      });
    },
    fall(world, a) {
      withStage(a, () => fxOf().slash({ pos: [0.6, 3.4, 0], arc: [118, -24], radius: 6.2, width: 2.0, look: 'flame', palette: 'ember', sweep: 0.11, life: 0.8 }));
    },
    crash(world, a) {
      world.fxAt(a, 'ember.eruption', [6.3, 0, 0], { scale: 1.9, k: 1.4 });
      world.fxAt(a, 'combat.dust.land', [6.3, 0, 0], { scale: 2.8, heavy: true });
      withStage(a, () => {
        const fx = fxOf();
        fx.decal({ kind: 'crack', pos: [6.2, 0, 0], radius: 4.2, palette: 'ember', magma: 1, life: 5 });
        fx.ring({ pos: [6.2, 0, 0], look: 'fire', palette: 'ember', radius: [0.6, 5.2], life: 0.8 });
      });
      world.present.sound('ground_slam', { pos: a.view.pos, volume: 1 });
      if (ctx.post && ctx.post.impactFrame) ctx.post.impactFrame({ duration: 0.06, invert: 0, mono: 0.7 });
    },
    lunge(world, a) {
      world.fxAt(a, 'combat.dust.dash', [0, 0, 0], { scale: 3, k: 1.4 });
      withStage(a, () => {
        const fx = fxOf();
        fx.ring({ pos: [3.4, 1.9, 0], normal: [1, 0, 0], look: 'shock', radius: [0.3, 1.5], life: 0.32, palette: 'ember', intensity: 0.5, alpha: 0.5 });
      });
    },
    stomp(world, a) {
      world.fxAt(a, 'combat.dust.stomp', [1.4, 0, -0.6], { scale: 3.4, heavy: true });
      withStage(a, () => {
        const fx = fxOf();
        fx.ring({ pos: [1.4, 0, -0.6], look: 'fire', palette: 'ember', radius: [0.6, 7.5], width: [0.5, 1.4], life: 0.62, ease: 1.4, height: 0.9 });
        fx.ring({ pos: [1.4, 0, -0.6], look: 'dust', radius: [0.8, 8.5], life: 1.3 });
        fx.decal({ kind: 'crack', pos: [1.4, 0, -0.6], radius: 3.4, palette: 'ember', magma: 0.9, life: 4 });
      });
      world.present.sound('ground_slam', { pos: a.view.pos, volume: 1 });
    },
    gather(world, a) {
      const h = world.fxAt(a, 'combat.charge.gather', [0.5, 6.1, -0.9], { element: 'eclipse', scale: 2.4, duration: T.eclipse.casts[0] - T.eclipse.gather });
      a.data.gatherFx = h;
      world.present.sound('ult_charge', { pos: a.view.pos, volume: 0.9 });
    },
    cast(world, a, e) {
      const hero = world.hero;
      if (!hero) return;
      const i = (e.data && e.data.i) || 0;
      if (i === 0) { world.fxAt(a, 'combat.charge.release', [1.3, 3.1, -0.9], { element: 'eclipse', scale: 2 }); if (ctx.post && ctx.post.pulse) ctx.post.pulse('chroma', 0.25, { release: 0.3 }); }
      // where the hero is going, not where it stands
      const lead = 0.35 + 0.1 * i;
      const x = hero.pos.x + hero.vel.x * lead + (hero.moveX || 0) * (hero.speed || 0) * lead, z = hero.pos.z + hero.vel.z * lead + (hero.moveZ || 0) * (hero.speed || 0) * lead;
      world.shoot(a, { kind: 'idol.sunfire', pos: { x, y: 0, z }, speed: 0, ground: true, delay: 0.85, lifetime: 0.5, radius: 1.5, height: [0, 4.5],
        hit: { damage: 70, level: 'launch', poise: 40, hitstop: 0.1, guard: 40 }, data: { huge: i === 3 } });
    },
    crackle(world, a) {
      world.fxAt(a, 'combat.charge.gather', [0.5, 3.0, 0], { element: 'eclipse', scale: 3, duration: T.enrage.roar - 0.3 });
      enrageCam(world, a);
      world.present.sound('ult_charge', { pos: a.view.pos, volume: 1, pitch: 0.6 });
      world.slowmo(0.5, 0.8);
    },
    roar(world, a) {
      world.fxAt(a, 'combat.ult.flash', [0.3, 3.6, 0], { scale: 1.5 });
      world.fxAt(a, 'ember.explosion', [0, 2.4, 0], { scale: 2.4 });
      withStage(a, () => {
        const fx = fxOf();
        fx.ring({ pos: [0, 0, 0], look: 'fire', palette: 'ember', radius: [1, 12], width: [0.8, 2.4], life: 0.9, ease: 1.6, height: 1.6 });
        fx.ring({ pos: [0, 0, 0], look: 'shock', palette: 'eclipse', radius: [1, 14], life: 0.7, distort: 0.04 });
        fx.decal({ kind: 'crack', pos: [0, 0, 0], radius: 6, palette: 'ember', magma: 1, life: 8 });
      });
      const fx = fxOf();
      if (!a.data.aura) {
        try { a.data.aura = fx.play('ember.aura', { pos: [a.pos.x, 0, a.pos.z], target: a.char.root, scale: 2.7 }, { follow: a.char.root }); } catch (err) { a.data.aura = null; }
      }
      world.present.sound('explosion', { pos: a.view.pos, volume: 1 });
      if (ctx.post && ctx.post.grade) ctx.post.grade('ember', 1.6);
      if (ctx.post && ctx.post.impactFrame) ctx.post.impactFrame({ duration: 0.08, invert: 0, mono: 0.8 });
    },
  };

  rpg.on('marker', (e) => {
    const a = e.actor;
    if (!a || a.kind !== 'idol' || !ctx || !ctx.vfx) return;
    const fn = MARK[e.name], world = ctx.rpg && ctx.rpg.world;
    if (!fn || !world) return;
    try { fn(world, a, e); } catch (err) { world.warnOnce && world.warnOnce('idol:' + e.name, 'idol marker ' + e.name + ' threw: ' + (err && err.message)); }
  });
  // the saber's tip drags on the stone while the idol marches
  rpg.on('step', (e) => {
    const a = e.actor;
    if (!a || a.kind !== 'idol' || !ctx || !ctx.vfx || a.state !== 'move') return;
    const world = ctx.rpg.world, p = a.socket('weaponTip', V);
    ctx.vfx.play('combat.hit.light', { pos: [p.x, 0.08, p.z], dir: [-Math.cos(a.yaw), 0.3, Math.sin(a.yaw)], scale: 1.4 }, { element: 'ember', intensity: 0.7 });
    ctx.cam.shake(0.16, { freq: 8, dir: [0, 1, 0] });
    void world;
  });
  rpg.on('mode', (e) => { if (e.mode === 'off' && ctx && ctx.post && ctx.post.grade) ctx.post.grade('night', 0.5); });
}
