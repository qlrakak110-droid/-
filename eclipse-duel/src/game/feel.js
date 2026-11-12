// Generic feel layer: the default presentation of every rules event, data-driven by hit level, move group and flags.
// Runs for everything a fighter's choreography does not override (see present.js). Numbers follow the global feel
// targets of src/fighters/MOVES.md: light 0.15 trauma / chroma 0.2, heavy 0.35 / radial 0.25, skill finishers 0.5 /
// impact frame, KO slow motion. Projectiles without their own visuals get a generic element body here too.

import * as THREE from 'three';
import * as SHOTS from '../cam/shots.js';

/** Strength per hit level (scales sparks, light, shake, post). */
const LEVEL_K = { light: 0.55, heavy: 0.9, launch: 1.0, crumple: 1.0, knockdown: 1.1 };
/** Victim flinch per level (char.impulse amount). */
const FLINCH = { light: 0.55, heavy: 1.0, launch: 1.6, crumple: 1.25, knockdown: 1.8 };
/** Element sounds: cast, burst. */
const ELEMENT_SFX = {
  ember: { cast: 'fire_ignite', burst: 'fire_burst' },
  frost: { cast: 'ice_form', burst: 'ice_shatter' },
  volt: { cast: 'volt_zap', burst: 'volt_strike' },
};

/**
 * @param {object} ctx
 * @param {object} session
 */
export function createFeel(ctx, session) {
  const match = session.match;
  const fx = session.fx;
  const P = new THREE.Vector3(), D = new THREE.Vector3();
  const hud = () => (ctx.ui && ctx.ui.hud) || null;
  const cam = ctx.cam, post = ctx.post;
  const sfxOf = (i) => ELEMENT_SFX[session.actors[i].element] || ELEMENT_SFX.ember;

  /** Contact point slightly in front of the bodies (toward the camera) so sparks are never buried. */
  function contact(e, out = P) { return out.set(e.x, e.y ?? 1.2, 0.18); }

  function hit(e) {
    const A = session.actors[e.attacker], V = session.actors[e.defender];
    const pos = contact(e).clone();
    const dir = D.set(e.facing, 0.18, 0.32).normalize().clone();
    if (e.blocked) {
      if (e.guardBreak) return;
      fx.play('game.guard', { pos, dir, facing: e.facing }, { perfect: e.perfect });
      session.sound('guard', { pos, pitch: e.perfect ? 1.25 : 1, volume: e.perfect ? 1 : 0.85 });
      V.impulse([-1, 0.05, 0.05], e.perfect ? 0.22 : 0.4);
      cam.shake(e.perfect ? 0.13 : 0.09, { freq: 20 });
      if (e.perfect) { post.pulse('chroma', 0.3, { release: 0.25 }); V.char.flash([1.2, 2.2, 4], 0.7, 0.2); }
      if (e.kind === 'strike') ctx.time.hitstop(Math.min(0.1, e.hitstop * 0.8));
      return;
    }
    const lvl = e.level || 'light';
    const mv = e.move && match.defs[e.attacker].moves[e.move];
    const group = mv ? mv.group : 'normal';
    let k = LEVEL_K[lvl] ?? 0.7;
    if (group === 'skill') k += 0.25;
    if (group === 'ult') k += 0.35;
    if (e.counter) k += 0.25;
    if (e.armoured) k = 0.5;
    if (e.ko) k = Math.max(k, 1.5);
    const el = A.element;
    fx.play([`${el}.hit.${lvl}`, `combat.hit.${lvl}`, `${el}.hit`], { pos, dir, facing: e.facing, scale: 0.8 + 0.3 * k }, { element: el, k, level: lvl, counter: e.counter }, 'game.hit');
    if (!e.armoured) {
      V.impulse([e.front === false ? 1 : -1, lvl === 'launch' ? 0.5 : 0.1, 0.12], FLINCH[lvl] ?? 1);
      V.char.flash([2.2, 1.8, 1.5], Math.min(0.9, 0.35 + 0.3 * k), 0.12);
    } else V.char.flash([2, 1.2, 0.6], 0.6, 0.15);
    const finisher = group !== 'normal' && (lvl === 'launch' || lvl === 'knockdown' || lvl === 'crumple');
    cam.shake(lvl === 'light' ? 0.15 + (e.counter ? 0.12 : 0) : finisher ? 0.5 : 0.35 + (e.counter ? 0.15 : 0), { freq: lvl === 'light' ? 20 : 15 });
    if (k >= 0.9) cam.kick({ fov: -1.2 - 1.8 * Math.min(1, k - 0.9), duration: 0.28 });
    post.pulse('chroma', 0.2 + 0.45 * Math.max(0, k - 0.55), { release: 0.25 });
    if (k >= 0.9) { post.radialAt(pos); post.pulse('radial', 0.22 + 0.35 * Math.min(1, k - 0.9), { attack: 0.01, release: 0.22 }); }
    if (e.counter || finisher || group === 'ult') post.impactFrame({ duration: e.counter && !finisher ? 0.034 : 0.05 });
    if (finisher) post.flash(0xffffff, 0.18, { release: 0.15 });
    session.sound(lvl === 'light' ? 'hit_slash_light' : 'hit_slash_heavy', { pos });
    if (lvl === 'launch' || lvl === 'knockdown' || lvl === 'crumple') session.sound('hit_blunt', { pos, volume: 0.65 });
    if (e.counter) session.sound('hit_crit', { pos, volume: 0.8 });
    if (group === 'skill' && finisher) session.sound(sfxOf(e.attacker).burst, { pos, volume: 0.6 });
    if (e.kind === 'strike') ctx.time.hitstop(e.hitstop);
    if (k >= 1.1 && ctx.env) ctx.env.pulse([e.x, 0, 0], A.palette.core, Math.min(1.5, 0.45 * k));
    if (e.combo >= 2 && hud()) hud().combo(e.attacker, e.combo, e.comboDamage);
    session.stats.hit(e);
  }

  function guardBreak(e) {
    const V = session.actors[e.fighter];
    const pos = new THREE.Vector3(e.x, e.y ?? 1.2, 0.18);
    fx.play('game.guardBreak', { pos, dir: [session.match.fighters[e.attacker].facing, 0.3, 0.3] }, {});
    session.sound('guard_break', { pos });
    cam.shake(0.5, { freq: 14 });
    cam.kick({ fov: -3, duration: 0.35 });
    post.pulse('chroma', 0.7, { release: 0.35 });
    post.flash(0xdde8ff, 0.25, { release: 0.2 });
    V.char.flash([2, 3, 5], 1.1, 0.3);
    V.impulse([-1, 0.3, 0.1], 1.6);
    ctx.time.hitstop(0.12);
  }

  function counter(e) {
    const A = session.actors[e.fighter];
    const pos = A.socket('chest', new THREE.Vector3());
    fx.play('game.finisher', { pos, dir: [A.facing, 0.2, 0.3], facing: A.facing }, { element: A.element });
    A.char.flash(A.palette.core, 0.9, 0.35);
    post.impactFrame({ duration: 0.05 });
    post.pulse('chroma', 0.6, { release: 0.3 });
    cam.shake(0.5, { freq: 14 });
    cam.zoom(0.82, 0.45, { focus: e.fighter });
    session.sound('release', { pos });
    session.sound(sfxOf(e.fighter).burst, { pos, volume: 0.7 });
  }

  function moveStart(e) {
    const A = session.actors[e.fighter];
    if (e.group === 'skill' && !e.forced) {
      const pos = A.socket('weaponTip', new THREE.Vector3());
      fx.play('game.cast', { pos, facing: A.facing }, { element: A.element });
      A.glow(A.palette.core, 0.18, 0.45, 0.06);
      session.sound(sfxOf(e.fighter).cast, { pos, volume: 0.6 });
    }
  }
  function moveEnd() {}

  /**
   * Marker data hints (moves.js authors can drive generic feel with data alone):
   *   { shake: trauma, kickFov: deg, afterimage: true, vfx: 'preset.name' (at the weapon tip), sound: 'name', flash: amount }
   */
  function marker(e) {
    const d = e.data;
    if (!d || typeof d !== 'object' || e.fighter === undefined) return;
    const A = session.actors[e.fighter];
    if (typeof d.shake === 'number') cam.shake(d.shake, { freq: 15 });
    if (typeof d.kickFov === 'number') cam.kick({ fov: d.kickFov, duration: 0.3 });
    if (d.afterimage) fx.call('afterimage', A.char.root, { color: A.palette.mid, life: 0.35 });
    if (typeof d.vfx === 'string' && fx.has(d.vfx)) fx.play(d.vfx, { pos: A.socket('weaponTip', new THREE.Vector3()), facing: A.facing }, { element: A.element });
    if (typeof d.sound === 'string') session.sound(d.sound, { pos: A.pos });
    if (typeof d.flash === 'number') A.char.flash(A.palette.core, d.flash, 0.2);
  }

  // ---- ultimate lock ---------------------------------------------------------------------------------------------
  function cineStart(e) {
    const V = session.actors[e.defender], A = session.actors[e.attacker];
    const pos = V.socket('chest', new THREE.Vector3());
    fx.play('game.finisher', { pos, dir: [A.facing, 0.1, 0.3], facing: A.facing }, { element: A.element });
    post.impactFrame({ duration: 0.06 });
    post.flash(0xffffff, 0.5, { release: 0.25 });
    post.pulse('chroma', 1, { release: 0.5 });
    cam.shake(0.6, { freq: 13 });
    session.sound('hit_crit', { pos });
    ctx.time.hitstop(0.18);
    V.char.flash([4, 3, 2.4], 1.2, 0.2);
  }

  function cineTick(e) {
    const A = session.actors[e.attacker], V = session.actors[e.defender];
    const pos = V.socket('chest', new THREE.Vector3());
    pos.z += 0.15;
    const dir = new THREE.Vector3(A.facing, 0.25, 0.3).normalize();
    if (e.final) {
      fx.play('game.finisher', { pos, dir, facing: A.facing }, { element: A.element });
      fx.play('game.erupt', { pos: V.at(0, 0, 0, new THREE.Vector3()) }, { element: A.element, k: 1.4 });
      post.flash(0xffffff, 0.7, { release: 0.35 });
      post.impactFrame({ duration: 0.07, invert: 1 });
      post.pulse('exposure', 0.4, { release: 0.6 });
      cam.shake(1, { freq: 10, duration: 1.2 });
      session.sound('ult_impact', { pos });
      session.sound(sfxOf(e.attacker).burst, { pos, volume: 0.8 });
    } else {
      fx.play('game.hit', { pos, dir, facing: A.facing }, { element: A.element, k: 1.05 });
      post.pulse('chroma', 0.45, { release: 0.2 });
      cam.shake(0.35, { freq: 16 });
      session.sound('hit_slash_heavy', { pos });
    }
    V.char.flash([2.2, 1.8, 1.5], 0.7, 0.12);
    if (e.hitstop) ctx.time.hitstop(e.hitstop);
    const f = match.fighters[e.attacker];
    if (hud() && f.combo.hits >= 2) hud().combo(e.attacker, f.combo.hits, f.combo.damage);
    session.stats.tick(e);
  }

  // ---- projectiles: generic element body following the rules projectile ------------------------------------------
  const shots = new Map();
  const tmpRamp = {};
  function ribbonRamp(el) {
    if (tmpRamp[el]) return tmpRamp[el];
    const p = fx.paletteOf(el);
    return (tmpRamp[el] = [[0, p.core[0] * 0.5, p.core[1] * 0.5, p.core[2] * 0.5, 0.9], [0.2, p.mid[0], p.mid[1], p.mid[2], 0.6], [1, p.tail[0], p.tail[1], p.tail[2], 0]]);
  }
  function projectile(name, e, suppressed) {
    if (name === 'projectileSpawn') {
      if (suppressed) return;
      const A = session.actors[e.owner];
      const proxy = new THREE.Object3D();
      proxy.position.set(e.x, e.y, 0.05);
      const targeted = Math.abs(e.vx) < 1e-3 && Math.abs(e.vy) < 1e-3;
      const v = { id: e.id, owner: e.owner, proxy, targeted, handles: [], el: A.element };
      const P2 = A.palette;
      if (targeted) {
        // telegraph on the floor until it arms
        proxy.position.y = 0.03;
        v.handles.push(fx.call('flare', { kind: 'ring', pos: proxy.position, follow: proxy, color: P2.mid, intensity: 0.9, size: [0.4, 1.5], life: Math.max(0.2, e.delay || 0.3), attack: 0.1 }));
        v.handles.push(fx.call('light', { pos: [e.x, 0.4, 0.3], color: P2.core, intensity: 40, range: 4, duration: Math.max(0.2, e.delay || 0.3) + 0.1, attack: Math.max(0.1, e.delay || 0.3) }));
      } else {
        v.handles.push(fx.call('flare', { kind: 'glow', pos: proxy.position, follow: proxy, color: P2.core, intensity: 1.1, size: 0.9, life: 30 }));
        v.handles.push(fx.call('ribbon', { follow: proxy, life: 0.32, width: 0.5, color: ribbonRamp(A.element) }));
        const em = fx.call('emitter', fx.defsOf(A.element).trailMotes, { pos: proxy.position });
        if (em.follow) em.follow(proxy);
        v.handles.push(em);
        v.handles.push(fx.call('light', { pos: proxy.position, follow: proxy, color: P2.core, intensity: 70, range: 5, duration: Infinity }));
        if (typeof (ctx.vfx && ctx.vfx.slash) === 'function') {
          v.handles.push(fx.call('slash', { pos: proxy.position, follow: proxy, look: { ember: 'flame', frost: 'ice', volt: 'electric' }[A.element] || 'razor', palette: A.element,
            facing: e.facing, normal: [0, 0, 1], forward: [1, 0, 0], arc: [-70, 70], radius: 0.95, width: 0.5, life: (e.lifetime || 1) + (e.delay || 0) + 0.2, sweep: 0.05 }));
        }
      }
      session.sound(sfxOf(e.owner).cast, { pos: proxy.position, volume: 0.7 });
      shots.set(e.id, v);
    } else if (name === 'projectileActive') {
      const v = shots.get(e.id);
      if (v && v.targeted) {
        fx.play('game.erupt', { pos: [e.x, 0, 0] }, { element: v.el, k: 1 });
        session.sound(sfxOf(v.owner).burst, { pos: v.proxy.position, volume: 0.8 });
        cam.shake(0.3, { freq: 14 });
      }
    } else if (name === 'projectileExpire') {
      const v = shots.get(e.id);
      if (!v) return;
      shots.delete(e.id);
      for (const h of v.handles) { if (h.stop) h.stop(); else if (h.kill) h.kill(); }
      if (e.reason === 'clash' || e.reason === 'lifetime' || e.reason === 'bounds') {
        fx.play('game.burst', { pos: v.proxy.position.clone() }, { element: v.el, k: e.reason === 'clash' ? 1.2 : 0.5 });
      }
    } else if (name === 'projectileClash') {
      cam.shake(0.25);
      session.sound('shockwave', { pos: [e.x, e.y, 0], volume: 0.6 });
    }
  }
  /** Per frame: move the generic projectile bodies with the rules projectiles. */
  function updateProjectiles() {
    if (!shots.size) return;
    const list = match.projectiles;
    for (const v of shots.values()) {
      for (let k = 0; k < list.length; k++) {
        const p = list[k];
        if (p.id !== v.id) continue;
        if (!v.targeted) v.proxy.position.set(p.x, p.y, 0.05);
        break;
      }
      v.proxy.updateMatrixWorld();
    }
  }
  function clearProjectiles() {
    for (const v of shots.values()) for (const h of v.handles) if (h.kill) h.kill();
    shots.clear();
  }

  // ---- movement, landings, KO ----------------------------------------------------------------------------------------
  function dodge(e) {
    const A = session.actors[e.fighter];
    const pos = A.at(0, 0, 0, new THREE.Vector3());
    if (e.kind === 'dash' || e.kind === 'roll') fx.play('game.dust', { pos }, { k: 0.55 });
    if (e.kind === 'backstep') fx.play('game.dust', { pos }, { k: 0.45 });
    if (e.kind === 'dodge') fx.call('afterimage', A.char.root, { color: A.palette.mid, life: 0.3 });
    session.sound('dodge', { pos, volume: e.kind === 'dash' ? 0.7 : 0.85 });
  }
  function perfectDodge(e) {
    const A = session.actors[e.fighter];
    ctx.time.slowmo(0.35, 0.4, { easeIn: 0.02, easeOut: 0.2 });
    post.pulse('chroma', 0.45, { release: 0.35 });
    A.char.flash([1.5, 3, 5], 0.6, 0.3);
    fx.call('afterimage', A.char.root, { color: [1, 2, 4], life: 0.45 });
    session.sound('slowmo_in', { volume: 0.45 });
  }
  function land(e) {
    const A = session.actors[e.fighter];
    const pos = A.at(0, 0, 0, new THREE.Vector3());
    const heavy = e.hard || e.ko;
    fx.play('game.dust', { pos }, { k: heavy ? 1.4 : 0.9 });
    session.sound(heavy ? 'body_fall' : 'land', { pos });
    cam.shake(heavy ? 0.22 : 0.1, { freq: 12, dir: [0, 1, 0] });
    A.impulse([0, -1, 0], heavy ? 0.9 : 0.4);
  }
  function tech(e) {
    const A = session.actors[e.fighter];
    fx.play('game.dust', { pos: A.at(0, 0, 0, new THREE.Vector3()) }, { k: 0.8 });
    session.sound('dodge', { volume: 0.7 });
  }
  function wallBounce(e) {
    cam.shake(0.45, { freq: 13 });
    fx.play('game.dust', { pos: [e.x, 0, 0] }, { k: 1.2 });
    session.sound('hit_blunt', { pos: [e.x, e.y, 0] });
    if (ctx.env) ctx.env.pulse([e.x, 0, 0], [2, 1.6, 1.3], 0.7);
  }
  function teleport(e) {
    const A = session.actors[e.fighter];
    fx.play('game.burst', { pos: new THREE.Vector3(e.from, 1.1, 0.1) }, { element: A.element, k: 0.6 });
    fx.call('afterimage', A.char.root, { color: A.palette.mid, life: 0.35 });
  }

  function ko(e) {
    const V = session.actors[e.fighter], A = session.actors[e.by];
    const pos = V.socket('chest', new THREE.Vector3());
    session.stats.ko(e);
    if (!e.cinematic) {
      // the impact reads first (flash, impact frame), then time sinks into slow motion
      if (ctx.vfx) ctx.vfx.schedule(0.09, () => ctx.time.slowmo(0.22, 1.7, { easeIn: 0.06, easeOut: 0.7 }), { realtime: true });
      fx.play('game.finisher', { pos, dir: [A.facing, 0.2, 0.3], facing: A.facing }, { element: A.element, realtime: true });
      post.impactFrame({ duration: 0.06 });
      post.flash(0xffffff, 0.35, { release: 0.18 });
      if (cam.mode !== 'cine') {
        cam.play([
          SHOTS.impactPunchIn({ dur: 0.75, clock: 'real', shake: 0.8 }),
          SHOTS.orbitSweep({ dur: 1.8, clock: 'real', cut: 0.3, subject: 'target', from: -30, to: 10, radius: [4.6, 4.0], height: [1.0, 1.6], look: 0.9 }),
        ], { anchor: e.by, blendOut: 0.9 });
      }
    }
    post.pulse('chroma', 1, { release: 0.9 });
    post.radialAt(pos);
    post.pulse('radial', 0.6, { attack: 0.01, release: 0.6 });
    session.sound('announce_ko');
    session.sound('slowmo_in', { delay: 0.05, volume: 0.6 });
    if (ctx.audio) ctx.audio.duck(0.6, 2.5);
    if (hud()) hud().announce('ko');
  }

  function state(e) {
    if (e.to === 'victory') session.onVictory(e.fighter);
  }

  return {
    hit, guardBreak, counter, moveStart, moveEnd, marker, cineStart, cineTick, projectile, updateProjectiles, clearProjectiles,
    dodge, perfectDodge, land, tech, wallBounce, teleport, ko, state,
  };
}
