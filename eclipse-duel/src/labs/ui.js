// UI lab: every screen with realistic data over the neutral stage, an animated HUD (damage, meters, combo,
// announcements, cinematic mode) and the touch pad. Scenarios run on real time through ctx.onUpdate, so captures at
// fixed simulation times are deterministic.
//
//   node tools/shot.mjs ui --do "__ED.lab.play('hudFight')" --at 0.2,0.8,1.6 --sheet-only --out shots/ui/fight
//   node tools/shot.mjs ui --do "__ED.lab.play('touch')" --size 844x390 --touch --at 0.5 --out shots/ui/touch

import * as THREE from 'three';
import { createLab } from '../core/lab.js';
import { createInput } from '../input/index.js';
import { createUI } from '../ui/index.js';
import { DEFAULT_ROSTER } from '../ui/roster.js';

const R = Object.fromEntries(DEFAULT_ROSTER.map((f) => [f.id, f]));

/** Two stand-in duelists on the fight line: dark armour capsules with HDR weapon emissives. */
function standIns(ctx) {
  const { scene } = ctx;
  const make = (x, facing, col, len) => {
    const g = new THREE.Group();
    const armour = new THREE.MeshStandardMaterial({ color: 0x3a3d46, metalness: 0.85, roughness: 0.38 });
    const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.3, 0.95, 6, 14), armour);
    body.position.y = 1.0;
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.17, 16, 12), armour);
    head.position.y = 1.78;
    const blade = new THREE.Mesh(new THREE.BoxGeometry(0.07, len, 0.02), new THREE.MeshBasicMaterial({ color: new THREE.Color(...col) }));
    blade.position.set(0.45 * facing, 1.25, 0.25);
    blade.rotation.z = -0.75 * facing;
    for (const m of [body, head]) { m.castShadow = true; }
    g.add(body, head, blade);
    g.position.x = x;
    scene.add(g);
    return g;
  };
  make(-1.9, 1, [8, 3, 0.6], 1.7);
  make(1.9, -1, [1.5, 4, 8], 1.1);
}

const skillState = (f, cds, fp) => [1, 2, 3].map((n, i) => {
  const m = f.moves.find((x) => x.slot === 'skill' + n);
  return { id: m.icon, name: m.name, icon: m.icon, cost: m.cost, cd: cds[i], ready: cds[i] <= 0 && fp >= m.cost };
});

createLab({
  view: { target: [0, 1.15, 0], dist: 8.2, yaw: 0, pitch: 5, fov: 40 },
  setup(ctx, lab) {
    standIns(ctx);
    createInput(ctx);
    const ui = createUI(ctx);
    lab.ui = ui;
    const touchDefault = ui.touch.visible;

    // scenario driver: one function of (t, dt) at a time, on real time
    let drive = null, t = 0;
    lab.drive = (fn) => { drive = fn; t = 0; if (fn) fn(0, 0); };
    ctx.onUpdate((dg, dr) => { if (drive) { t += dr; drive(t, dr); } }, ctx.ORDER.GAME);

    // a match state the HUD scenarios mutate
    lab.match = (o = {}) => {
      const m = {
        time: 87,
        roundsToWin: 2,
        p1: { name: 'KAEL', hp: 1000, hpMax: 1000, fp: 70, fpMax: 100, ult: 45, rounds: 1, element: 'ember' },
        p2: { name: 'ISKA', hp: 1000, hpMax: 1000, fp: 55, fpMax: 100, ult: 20, rounds: 0, element: 'frost' },
        cd1: [0, 0.45, 0], cd2: [0.7, 0, 0],
      };
      Object.assign(m.p1, o.p1); Object.assign(m.p2, o.p2);
      if (o.time !== undefined) m.time = o.time;
      if (o.cd1) m.cd1 = o.cd1;
      if (o.cd2) m.cd2 = o.cd2;
      return m;
    };
    lab.push = (m) => {
      ui.hud.set(m);
      ui.hud.skills(0, skillState(R.kael, m.cd1, m.p1.fp));
      ui.hud.skills(1, skillState(R.iska, m.cd2, m.p2.fp));
    };
    lab.startHud = (m, touch = touchDefault) => {
      ui.touch.setVisible(touch);
      ui.show('hud', { p1: R.kael, p2: R.iska, roundsToWin: 2 });
      lab.push(m);
    };

    // menu flow wiring so the lab is navigable by hand (keyboard / pad / touch)
    ui.on('start', () => ui.show('select', { roster: DEFAULT_ROSTER }));
    ui.on('back', (from) => { if (from === 'select') ui.show('title'); });
    ui.on('pick', (p) => ui.show('vs', { p1: p.p1, p2: p.cpu, difficulty: p.difficulty }));
    ui.on('vsDone', () => lab.play('hudFight'));
    ui.on('pause', () => ui.show('pause', { p1: R.kael, p2: R.iska }));
    ui.on('resume', () => ui.show('hud'));
    ui.on('toTitle', () => ui.show('title'));
    ui.on('rematch', () => lab.play('hudFight'));
    ui.on('select', () => ui.show('select', { roster: DEFAULT_ROSTER }));
    ui.on('quality', (q) => console.log('[ed] quality ->', q));
  },
  scenarios: {
    title(ctx, lab) { lab.drive(null); lab.ui.show('title'); },
    select(ctx, lab) { lab.drive(null); lab.ui.show('select', { roster: DEFAULT_ROSTER }); },
    /** P1 has picked KAEL, the cursor is choosing the CPU. */
    selectCpu(ctx, lab) { lab.drive(null); lab.ui.show('select', { roster: DEFAULT_ROSTER, p1: 'kael' }); },
    /** Both picked, difficulty step. */
    selectDiff(ctx, lab) { lab.drive(null); lab.ui.show('select', { roster: DEFAULT_ROSTER, p1: 'kael', cpu: 'vorn', difficulty: 'hard' }); },
    vs(ctx, lab) { lab.drive(null); lab.ui.show('vs', { p1: 'kael', p2: 'iska', difficulty: 'hard', duration: 99 }); },
    pause(ctx, lab) { lab.play('hud'); lab.ui.show('pause', { p1: R.kael, p2: R.iska }); },
    movelist(ctx, lab) { lab.play('hud'); lab.ui.show('movelist', { fighters: [R.kael, R.iska], index: 0, fromPause: true }); },
    movelistVorn(ctx, lab) { lab.drive(null); lab.ui.show('movelist', { fighters: DEFAULT_ROSTER, index: 2 }); },
    result(ctx, lab) {
      lab.drive(null);
      lab.ui.show('result', {
        winner: 0, p1: 'kael', p2: 'iska', score: [2, 1],
        rounds: [{ winner: 0, how: 'ko' }, { winner: 1, how: 'time' }, { winner: 0, how: 'perfect' }],
        stats: { p1: { maxCombo: 14, damage: 2140, ults: 2, hpLeft: 100 } },
      });
    },
    resultLose(ctx, lab) {
      lab.drive(null);
      lab.ui.show('result', { winner: 1, p1: 'iska', p2: 'vorn', score: [0, 2], rounds: [{ winner: 1, how: 'ko' }, { winner: 1, how: 'ko' }], stats: { p1: { maxCombo: 6, damage: 880, ults: 0 } } });
    },
    none(ctx, lab) { lab.drive(null); lab.ui.show('none'); },

    /** Static mid-fight HUD. */
    hud(ctx, lab, touch) {
      const m = lab.match({ p1: { hp: 640, ult: 72 }, p2: { hp: 410, fp: 30, ult: 100 } });
      lab.startHud(m, touch);
      lab.ui.hud.combo(0, 7, 186);
      lab.drive(null);
    },
    /** Low health, ULT ignited, low timer, cooldowns mid-sweep. */
    hudLow(ctx, lab) {
      const m = lab.match({ time: 8, p1: { hp: 180, fp: 15, ult: 100, rounds: 1 }, p2: { hp: 520, fp: 90, ult: 62, rounds: 1 }, cd1: [0.25, 0.8, 0.55], cd2: [0, 0, 0.3] });
      lab.startHud(m);
      lab.drive(null);
    },
    /** A short exchange: hits with ghost drain, combo punches, meters filling, a skill on cooldown, ULT igniting. */
    hudFight(ctx, lab) {
      const m = lab.match({ time: 99, p1: { rounds: 0, ult: 78, fp: 40 }, p2: { rounds: 0, ult: 10 } });
      lab.startHud(m);
      lab.ui.hud.announce('round', { round: 1 });
      const hits = [0.9, 1.05, 1.2, 1.38, 1.6, 1.85, 2.15];
      let next = 0, combo = 0, dmg = 0;
      lab.drive((t, dt) => {
        if (t > 1.5 && !m._fight) { m._fight = true; lab.ui.hud.announce('fight'); }
        m.time = Math.max(0, 99 - t);
        while (next < hits.length && t >= hits[next] + 1.0) {
          const d = next === hits.length - 1 ? 120 : 45 + next * 6;
          m.p2.hp = Math.max(0, m.p2.hp - d);
          combo++; dmg += d;
          m.p1.ult = Math.min(100, m.p1.ult + 4);
          m.p1.fp = Math.min(100, m.p1.fp + 4);
          lab.ui.hud.combo(0, combo, dmg);
          next++;
        }
        m.cd1 = [Math.max(0, 0.6 - t * 0.2), Math.max(0, 1 - t * 0.35), 0];
        lab.push(m);
      });
    },
    /** Damage on P1 only: hit flash, jolt, ghost hold then drain. */
    hudDamage(ctx, lab) {
      const m = lab.match({ p1: { hp: 820 } });
      lab.startHud(m);
      lab.drive((t) => {
        if (t >= 0.1 && !m._a) { m._a = 1; m.p1.hp = 560; }
        if (t >= 0.25 && !m._b) { m._b = 1; m.p1.hp = 470; }
        lab.push(m);
      });
    },
    /** Combo counter punching on every hit. */
    hudCombo(ctx, lab) {
      const m = lab.match({ p2: { hp: 900 } });
      lab.startHud(m);
      let n = 0, dmg = 0, acc = 0;
      lab.drive((t, dt) => {
        acc += dt;
        if (acc > 0.16 && n < 18) { acc = 0; n++; dmg += 38 + n * 3; m.p2.hp = Math.max(0, 900 - dmg); lab.ui.hud.combo(0, n, dmg); }
        lab.push(m);
      });
    },
    /** ULT gauge filling and igniting, skill coming off cooldown with a ready pulse. */
    hudUlt(ctx, lab) {
      const m = lab.match({ p1: { ult: 80, fp: 60 } });
      lab.startHud(m);
      lab.drive((t) => {
        m.p1.ult = Math.min(100, 80 + t * 40);
        m.cd1 = [Math.max(0, 0.3 - t * 0.5), 0.5, 0];
        lab.push(m);
      });
    },
    /** Announcer styles in sequence: round, fight, ko, perfect, timeup, draw, ult callout. */
    announce(ctx, lab, kind = 'round') {
      const m = lab.match({ p2: { hp: kind === 'ko' || kind === 'perfect' ? 0 : 600 } });
      lab.startHud(m);
      lab.drive(null);
      if (kind === 'ult') lab.ui.hud.announce('일식의 장작', { sub: 'PYRE OF THE BLACK SUN', style: 'ult', side: 0 });
      else if (kind === 'ultP2') lab.ui.hud.announce('떨어지는 서릿별', { sub: 'FALL OF THE FROZEN STAR', style: 'ult', side: 1 });
      else if (kind === 'final') lab.ui.hud.announce('final');
      else lab.ui.hud.announce(kind, { round: 2 });
    },
    /** Cinematic mode: HUD slides away, ULT name callout, then returns. */
    cine(ctx, lab) {
      const m = lab.match({ p1: { ult: 100 } });
      lab.startHud(m);
      lab.drive((t) => {
        if (t >= 0.1 && !m._c) { m._c = 1; lab.ui.hud.cinematic(true); lab.ui.hud.announce('일식의 장작', { sub: 'PYRE OF THE BLACK SUN', style: 'ult', side: 0 }); m.p1.ult = 0; }
        if (t >= 2.2 && !m._d) { m._d = 1; lab.ui.hud.cinematic(false); }
        lab.push(m);
      });
    },
    /** Control hints strip (keyboard labels). */
    hints(ctx, lab) { lab.play('hud'); lab.ui.hud.hints(true); },
    /** Touch pad over the HUD; a few buttons held so pressed states show. */
    touch(ctx, lab) {
      lab.play('hud', true);
      ctx.input.noteDevice('touch');
    },
    touchPressed(ctx, lab) {
      lab.play('touch');
      const q = (s) => lab.ui.root.querySelector(s);
      q('.pb-light').classList.add('is-down');
      q('.pb-skill2').classList.add('is-down');
      lab.ui.root.querySelector('.ed-pad').classList.add('stick-on');
    },
  },
});
