// Heroes of the RPG mode: one actor kind per fighter (`hero.kael`, `hero.iska`, `hero.vorn`), built from the fighter's
// own content — design, clips, rules definition (every move with its frame data, markers, projectiles, costs) and
// choreography — plus the rpg.<hero>.* locomotion clips. Also the human controller (ctx.input + camera -> intents).
//
// Move mapping (README §11 "Hero controls"):
//   light            light1 -> light2 -> light3 (the fighter's own cancel routes, also on whiff)
//   heavy            the heavy move; while sprinting: the f+heavy move; right after a roll: the d+heavy move
//   skill1..3, ult   the fighter's skills (FP, cooldown) and ultimate (full gauge)
// Hit volumes: every 2D hit box { f, u } of moves.js becomes an arc / box / circle around the hero (attacks.js
// shapeFromBox, by the move's swing style); SHAPES below overrides the few that need their own.

import { compileFighterDef } from '../../game/logic/index.js';
import { slotMoves } from '../../game/clips.js';
import { fromFighterMove } from './attacks.js';
import { angDiff, hypot2, yawTo, fwdX, fwdZ, rightX, rightZ } from './math3.js';
import './clips/index.js';

/** Per-hero tuning: body, speeds (m/s), stamina, roll. */
export const HEROES = {
  kael: {
    stats: { stamina: 112, walk: 1.9, run: 4.3, sprint: 6.3, turn: 620, accel: 22, decel: 30 },
    roll: { cost: 27, distance: 3.5, duration: 0.7, travel: 0.52, invuln: [0.04, 0.37], actFrom: 0.56 },
    staminaScale: 1.15, ultGain: 0.028,
  },
  iska: {
    stats: { stamina: 96, walk: 2.3, run: 5.3, sprint: 7.6, turn: 840, accel: 34, decel: 40 },
    roll: { cost: 20, distance: 3.9, duration: 0.56, travel: 0.42, invuln: [0.03, 0.33], actFrom: 0.44 },
    staminaScale: 0.8, ultGain: 0.036,
  },
  vorn: {
    stats: { stamina: 104, walk: 2.1, run: 4.8, sprint: 7.0, turn: 720, accel: 28, decel: 36 },
    roll: { cost: 23, distance: 3.7, duration: 0.62, travel: 0.46, invuln: [0.035, 0.35], actFrom: 0.5 },
    staminaScale: 1.0, ultGain: 0.032,
  },
};

/** Stamina a move costs, by its slot (x the hero's staminaScale). */
const STAMINA = { light1: 13, light2: 13, light3: 16, heavy: 28, fheavy: 26, dheavy: 22, skill1: 8, skill2: 10, skill3: 8, ult: 0 };

/** Hit volumes that are not derived from the 2D box: { [hero]: { [moveId]: { [hit label | index]: shape } } }. */
const SHAPES = {
  kael: {
    // Furnace Sweep: 300 degrees starting behind his right shoulder, ending in front
    sweep: { 0: { type: 'arc', r: [0, 2.3], angle: [-110, 190], u: [0.3, 1.8] } },
    // the leap-slash of the ultimate comes down on a lane in front
    pyre: { leapSlash: { type: 'box', f: [-0.2, 2.3], s: [-0.9, 0.9], u: [0, 2.6] } },
  },
  iska: {
    // the rune of the ultimate: a wide lane on the floor in front (snaps shut under whatever stands in it)
    frozen_star: { rune: { type: 'arc', r: [0, 6.2], angle: [-40, 40], u: [0, 1.4] } },
  },
  vorn: {},
};

const SLOT_BUTTON = { light: 'light', heavy: 'heavy', skill1: 'skill1', skill2: 'skill2', skill3: 'skill3', ult: 'ult' };

/**
 * Build the actor kind of a hero.
 * @param {object} fighter registry fighter { id, roster, element, design, def, clips, present, fallbackDesign }
 * @returns {object} kind spec
 */
export function heroKind(fighter) {
  const id = fighter.id;
  const tune = HEROES[id] || HEROES.kael;
  const cdef = compileFighterDef(fighter.def);
  const slots = slotMoves(cdef);
  const slotOf = {};
  for (const s in slots) slotOf[slots[s]] = s;
  const attacks = {};
  for (const mid in cdef.moves) {
    const mv = cdef.moves[mid];
    const slot = (mv.meta && mv.meta.slot) || slotOf[mid] || mid;
    const atk = fromFighterMove(mv, {
      slot,
      stamina: Math.round((STAMINA[slot] ?? 10) * tune.staminaScale),
      shapes: (SHAPES[id] || {})[mid],
      track: { until: Math.max(0.05, Math.min(mv.firstActive === Infinity ? 0.2 : mv.firstActive, 0.4) - 0.04), rate: 540 },
    });
    // act again a little before the clip has fully settled; counters / forced follow-ups cost nothing
    atk.cancelFrom = mv.superFreeze ? mv.duration : mv.duration - Math.min(0.14, mv.duration * 0.16);
    if (mv.group !== 'normal' && !mv.fpCost && !mv.ultCost) atk.stamina = 0;
    attacks[mid] = atk;
  }
  const st = cdef.stats;
  const base = { hp: st.hp, fp: st.fpMax, stamina: tune.stats.stamina };
  const r = fighter.roster || {};
  const rpgClip = (n) => `rpg.${id}.${n}`;

  /** Slot press -> attack id, by context. */
  function pick(world, a, slot) {
    switch (slot) {
      case 'light': return slots.light1 || null;
      case 'heavy':
        if (slots.fheavy && a.sprintRecent > 0 && a.speed > tune.stats.run * 0.9) return slots.fheavy;
        if (slots.dheavy && a.postRoll > 0) return slots.dheavy;
        return slots.heavy || null;
      case 'ult': return a.ult + 1e-6 >= a.ultMax ? slots.ult || null : null;
      default: return slots[slot] || (attacks[slot] ? slot : null);
    }
  }
  const groupOf = (mid) => (attacks[mid] ? attacks[mid].group : 'normal');

  /** May the running attack be left for `slot` now? The fighter's own cancel routes, else free once it has recovered. */
  function cancelInto(world, a, inst, slot, free) {
    const mv = inst.def.move;
    const t = inst.t;
    let want = pick(world, a, slot);
    if (mv) {
      const button = SLOT_BUTTON[slot];
      for (let i = 0; i < mv.cancels.length; i++) {
        const c = mv.cancels[i];
        if (t < c.t0 - 1e-6 || t > c.t1 + 1e-6) continue;
        if (c.onHit && !inst.connected) continue;
        if (c.onContact && !inst.contact) continue;
        if (c.on) { if (c.on === button && attacks[c.route]) return c.route; continue; }
        if (!want) continue;
        if (c.ids.has(want) || c.groups.has('any') || c.groups.has(groupOf(want))) return want;
      }
      // a light press during a light that has a route but is early: keep it buffered (do not restart light1)
      if (slot === 'light' && mv.cancels.some((c) => c.on === 'light') && !free) return null;
      if (slot === 'light' && free && mv.cancels.some((c) => c.on === 'light')) want = mv.cancels.find((c) => c.on === 'light').route;
    }
    return free ? want : null;
  }

  /** Facing an attack starts with: lock target, else the stick, else a soft target in front, else as it stands. */
  function aim(world, a) {
    const cam = world.camera;
    const locked = cam && cam.target && cam.target.alive ? cam.target : null;
    if (locked) return yawTo(locked.pos.x - a.pos.x, locked.pos.z - a.pos.z);
    const it = a.intent;
    if (it.moveX * it.moveX + it.moveZ * it.moveZ > 0.04) {
      // the stick aims; a soft target close to that direction bends it (aim assist)
      const y = yawTo(it.moveX, it.moveZ);
      const t = a.target && a.target.alive ? a.target : null;
      if (t) { const ty = yawTo(t.pos.x - a.pos.x, t.pos.z - a.pos.z); if (Math.abs(angDiff(y, ty)) < 0.6) return ty; }
      return y;
    }
    const t = a.target && a.target.alive ? a.target : null;
    if (t && a.distTo(t) < 9) return yawTo(t.pos.x - a.pos.x, t.pos.z - a.pos.z);
    return NaN;
  }

  return {
    team: 'hero', hero: id, fighter, cdef, slots, attacks, base,
    name: { ko: r.name || id, en: r.nameEn || id.toUpperCase() },
    element: fighter.element,
    design: fighter.design, fallbackDesign: fighter.fallbackDesign,
    present: fighter.present || {},
    stats: {
      hp: st.hp, fp: st.fpMax, ult: st.ultMax, stamina: tune.stats.stamina, poise: 0,
      radius: Math.max(0.36, st.pushWidth), height: st.height, scale: 1, mass: st.weight,
      walk: tune.stats.walk, run: tune.stats.run, sprint: tune.stats.sprint, turn: tune.stats.turn, accel: tune.stats.accel, decel: tune.stats.decel,
    },
    roll: tune.roll,
    guard: {},
    ultGain: tune.ultGain,
    clips: { run: rpgClip('run'), sprint: rpgClip('sprint'), roll: rpgClip('roll'), drink: rpgClip('drink'), dead: rpgClip('death'), rest: rpgClip('rest') },
    warmClips: [rpgClip('run'), rpgClip('sprint'), rpgClip('roll'), rpgClip('drink'), rpgClip('death'), rpgClip('rest')],
    budget: 'hero', spawnTime: 0, downTime: 0.75, getupTime: 0.65,
    pick, cancelInto, aim,
  };
}

/**
 * The best soft target of the hero: a hostile actor in front (of the stick, else of the facing), near first.
 * @returns {object|null}
 */
export function softTarget(world, a, dirYaw, range = 11) {
  let best = null, score = 1e9;
  for (let i = 0; i < world.actors.length; i++) {
    const b = world.actors[i];
    if (b === a || !b.alive || b.leaving > 0 || !world.hostile(a, b)) continue;
    const dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z;
    const d = hypot2(dx, dz) - b.radius;
    if (d > range) continue;
    const ang = Math.abs(angDiff(dirYaw, yawTo(dx, dz)));
    if (ang > 1.25 && d > 1.6) continue;
    const s = d + ang * 3.2;
    if (s < score) { score = s; best = b; }
  }
  return best;
}

/**
 * Human controller: ctx.input (player 0) + the third-person camera -> intents. Tap `dodge` = roll, hold = sprint.
 * Presses are latched per rendered frame (`frame(dtReal)`, real time) and consumed by the next fixed step, so nothing
 * is lost while the world is frozen by a hit-stop or stretched by slow motion.
 * @param {object} ctx
 */
export function humanController(ctx) {
  const mv = { x: 0, y: 0 };
  const latch = { attack: '', roll: false, drink: false, interact: false, lock: false, lockL: false, lockR: false };
  let dodgeHeld = 0, sprinting = false, guard = false, moving = false;
  const TAP = 0.24;
  const PRIORITY = ['ult', 'skill1', 'skill2', 'skill3', 'heavy', 'light'];
  return {
    kind: 'human',
    /** Sample the input once per rendered frame. */
    frame(dtReal) {
      const inp = ctx.input;
      if (!inp) return;
      if (inp.moveVec) inp.moveVec(0, mv); else { mv.x = inp.axis(0); mv.y = (inp.held('up') ? 1 : 0) - (inp.held('down') ? 1 : 0); }
      moving = mv.x * mv.x + mv.y * mv.y > 0.04;
      if (inp.held('dodge')) {
        dodgeHeld += dtReal;
        if (dodgeHeld > TAP && moving) sprinting = true;
      } else {
        if (dodgeHeld > 0 && !sprinting) latch.roll = true;       // released: a tap (or a hold while standing) rolls
        dodgeHeld = 0; sprinting = false;
      }
      guard = inp.held('guard');
      for (let i = 0; i < PRIORITY.length; i++) if (inp.pressed(PRIORITY[i])) { latch.attack = PRIORITY[i]; break; }
      if (inp.pressed('chalice')) latch.drink = true;
      if (inp.pressed('interact')) latch.interact = true;
      if (inp.pressed('lock')) latch.lock = true;
      if (inp.pressed('lockL') || inp.pressed('lookL')) latch.lockL = true;
      if (inp.pressed('lockR') || inp.pressed('lookR')) latch.lockR = true;
    },
    think(world, a, dt, it) {
      const cam = world.camera;
      const cy = cam ? cam.yaw : 0;
      // camera-relative: stick up = away from the camera
      it.moveX = fwdX(cy) * mv.y + rightX(cy) * mv.x;
      it.moveZ = fwdZ(cy) * mv.y + rightZ(cy) * mv.x;
      it.sprint = sprinting && moving;
      it.guard = guard;
      it.roll = latch.roll; latch.roll = false;
      it.attack = latch.attack; latch.attack = '';
      it.drink = latch.drink; latch.drink = false;
      it.interact = latch.interact; latch.interact = false;
      if (cam) {
        if (latch.lock) cam.toggleLock();
        if (cam.target) { if (latch.lockL) cam.switch(-1); if (latch.lockR) cam.switch(1); }
      }
      latch.lock = latch.lockL = latch.lockR = false;
      const locked = cam && cam.target && cam.target.alive ? cam.target : null;
      a.target = locked || softTarget(world, a, moving ? yawTo(it.moveX, it.moveZ) : a.yaw);
      void dt;
    },
    /** Drop every latched press (pause, cinematics). */
    clear() { latch.attack = ''; latch.roll = latch.drink = latch.interact = latch.lock = latch.lockL = latch.lockR = false; dodgeHeld = 0; sprinting = false; },
  };
}
