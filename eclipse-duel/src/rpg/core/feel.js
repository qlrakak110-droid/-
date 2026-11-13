// Generic feel of the RPG mode: the default presentation of every world event (hits, guards, rolls, steps, deaths,
// skill casts, marker hints, projectile bodies), the 3D counterpart of src/game/feel.js. It runs for everything the
// actor's choreography does not replace (a handler returning false). Oriented effects are spawned in a stage frame
// (core/stage.js), so the VFX library's fight-line presets point the right way at any yaw.

import * as THREE from 'three';
import { paletteOf, defsOf } from '../../game/fx.js';
import { actorFrame, makeFrame, stageToWorld, withFrame, worldToStage } from './stage.js';
import { hypot2, yawTo } from './math3.js';

const LEVEL_K = { light: 0.55, heavy: 0.9, launch: 1.0, crumple: 1.0, knockdown: 1.1 };
const FLINCH = { light: 0.55, heavy: 1.0, launch: 1.6, crumple: 1.25, knockdown: 1.8 };
const ELEMENT_SFX = {
  ember: { cast: 'fire_ignite', burst: 'fire_burst' }, frost: { cast: 'ice_form', burst: 'ice_shatter' },
  volt: { cast: 'volt_zap', burst: 'volt_strike' }, steel: { cast: 'magic_cast', burst: 'shockwave' },
};
const FINISH = { ember: { name: 'ember.eruption' }, frost: { name: 'frost.shatter', chest: true }, volt: { name: 'volt.strike' } };
const WARN_PRESETS = new Set(['volt.strike']);
const GROUND = { ember: 'ember.eruption', volt: 'volt.strike' };
const LEAD = { 'ember.eruption': 0.14, '': 0.05 };
const TELEGRAPH = { ember: { kind: 'crack', magma: 1, radius: 1.1, reveal: 0.2 }, frost: { kind: 'frost', radius: 1.0, reveal: 0.25 }, volt: { kind: 'rune', palette: 'volt', radius: 1.1, reveal: 0.25 } };
const SLASH_LOOK = { ember: 'flame', frost: 'ice', volt: 'electric' };

/**
 * @param {object} ctx
 * @param {object} world
 * @param {object} P the presenter (core/present.js): { fx, sound, playedRecently, call, helperOf, indexOf }
 */
export function createFeel(ctx, world, P) {
  const fx = P.fx;
  const cam = ctx.cam, post = ctx.post;
  const V = new THREE.Vector3();
  const elOf = (a) => (a && a.view ? a.view.element : 'steel');
  const sfxOf = (a) => ELEMENT_SFX[elOf(a)] || ELEMENT_SFX.steel;
  const palOf = (a) => (a && a.view ? a.view.palette : paletteOf('ember'));
  const isHero = (a) => a && a === world.hero;
  const ghostAt = new Map();
  function ghost(a, life, intensity = 0.7, force = false) {
    if (!a.char || !a.char.root) return;
    const t = ctx.time.game;
    if (!force && t - (ghostAt.get(a.id) ?? -1) < 0.25) return;
    ghostAt.set(a.id, t);
    fx.call('afterimage', a.char.root, { palette: elOf(a) === 'steel' ? 'frost' : elOf(a), life, intensity });
  }

  /** Stage frame of a blow: origin at the attacker (or the contact), +X along the blow. */
  function blowFrame(e) {
    const a = e.attacker;
    if (a) return actorFrame(a, e.pos);
    return makeFrame(e.pos.x - e.dirX, e.pos.z - e.dirZ, yawTo(e.dirX, e.dirZ));
  }
  /** Contact point in the stage frame f (slightly toward the old camera side so sparks are not buried). */
  function contactStage(e, f) { V.set(e.pos.x, e.pos.y, e.pos.z); worldToStage(V, f, V); return [V.x, V.y, 0.14]; }

  // ---- hits -----------------------------------------------------------------------------------------------------
  function hit(e) {
    const A = e.attacker, Vc = e.victim;
    const f = blowFrame(e);
    const pos = contactStage(e, f);
    const lvl = e.level || 'light';
    const group = e.attack ? e.attack.group : 'normal';
    let k = LEVEL_K[lvl] ?? 0.7;
    if (group === 'skill') k += 0.25;
    if (group === 'ult') k += 0.35;
    if (e.armoured) k = 0.5;
    if (e.crit) k += 0.25;
    if (e.killed) k = Math.max(k, 1.3);
    const el = elOf(A);
    const heroHit = isHero(Vc);
    const names = e.crit || group === 'ult' ? ['combat.hit.crit', `combat.hit.${lvl}`] : group === 'skill' && el !== 'steel' ? [`${el}.hit`, `combat.hit.${lvl}`] : [`combat.hit.${lvl}`];
    withFrame(f, () => fx.play(names, { pos, dir: [1, 0.18, 0.32], facing: 1, scale: Math.min(2.2, 0.6 + 0.4 * (A ? A.scale : 1)) }, { element: el === 'steel' ? undefined : el, k, level: lvl, intensity: e.armoured ? 0.6 : 0.8 + 0.15 * Math.min(1, k) }, 'game.hit'));
    if (Vc.view) {
      if (!e.armoured) {
        Vc.view.impulse([e.front === false ? 1 : -1, lvl === 'launch' ? 0.5 : 0.1, 0.12], FLINCH[lvl] ?? 1);
        Vc.view.flash([0.8, 0.66, 0.56], Math.min(0.6, 0.22 + 0.22 * k), 0.12);
      } else Vc.view.flash([2, 1.2, 0.6], 0.5, 0.15);
      if (e.hitstop > 0) Vc.view.shake = 1;
    }
    const finisher = group !== 'normal' && (lvl === 'launch' || lvl === 'knockdown' || lvl === 'crumple');
    const big = A && A.scale > 1.6;
    if (heroHit) {
      // the hero is struck: a heavier, lower rumble and a red-edged pulse
      cam.shake((lvl === 'light' ? 0.26 : 0.48) * (big ? 1.5 : 1), { freq: big ? 9 : 13 });
      post.pulse('chroma', lvl === 'light' ? 0.3 : 0.55, { release: 0.3 });
      post.pulse('vignette', 0.12, { release: 0.5 });
      if (lvl !== 'light') cam.kick({ fov: 1.6, duration: 0.3 });
    } else {
      cam.shake(lvl === 'light' ? 0.13 : finisher ? 0.42 : 0.3, { freq: lvl === 'light' ? 20 : 15 });
      if (k >= 0.9) cam.kick({ fov: -1.0 - 1.4 * Math.min(1, k - 0.9), duration: 0.28 });
      post.pulse('chroma', 0.12 + 0.3 * Math.max(0, k - 0.55), { release: 0.22 });
      if (k >= 0.9) { post.radialAt(V.set(e.pos.x, e.pos.y, e.pos.z)); post.pulse('radial', 0.16 + 0.28 * Math.min(1, k - 0.9), { attack: 0.01, release: 0.22 }); }
      if (finisher || group === 'ult') post.impactFrame({ duration: 0.05, invert: 0, mono: 0.7 });
    }
    const wpos = V.set(e.pos.x, e.pos.y, e.pos.z);
    P.sound(lvl === 'light' ? 'hit_slash_light' : 'hit_slash_heavy', { pos: wpos });
    if (lvl === 'launch' || lvl === 'knockdown' || lvl === 'crumple' || big) P.sound('hit_blunt', { pos: wpos, volume: 0.65 });
    if (e.crit) P.sound('hit_crit', { pos: wpos, volume: 0.8 });
    if (group === 'skill' && finisher) P.sound(sfxOf(A).burst, { pos: wpos, volume: 0.6 });
    if (k >= 1.1 && ctx.env) ctx.env.pulse([e.pos.x, 0, e.pos.z], palOf(A).core, Math.min(1.5, 0.45 * k));
    if (e.killed) death(e.victim, A);
  }

  function guard(e) {
    const Vc = e.victim;
    const f = blowFrame(e);
    const pos = contactStage(e, f);
    const wpos = new THREE.Vector3(e.pos.x, e.pos.y, e.pos.z);
    if (e.guardBreak) {
      withFrame(f, () => fx.play('combat.guard.break', { pos, dir: [1, 0.3, 0.3], facing: 1 }, {}, 'game.guardBreak'));
      P.sound('guard_break', { pos: wpos });
      cam.shake(0.5, { freq: 14 });
      cam.kick({ fov: -3, duration: 0.35 });
      post.pulse('chroma', 0.7, { release: 0.35 });
      post.flash(0xdde8ff, 0.12, { release: 0.2 });
      if (Vc.view) { Vc.view.flash([1, 1.5, 2.5], 0.35, 0.3); Vc.view.impulse([-1, 0.3, 0.1], 1.6); }
      return;
    }
    withFrame(f, () => fx.play('combat.guard.block', { pos, dir: [1, 0.18, 0.32], facing: 1 }, { perfect: e.perfect }, 'game.guard'));
    P.sound('guard', { pos: wpos, pitch: e.perfect ? 1.25 : 1, volume: e.perfect ? 1 : 0.85 });
    if (Vc.view) Vc.view.impulse([-1, 0.05, 0.05], e.perfect ? 0.22 : 0.4);
    cam.shake(e.perfect ? 0.16 : 0.1, { freq: 20 });
    if (e.perfect) {
      post.pulse('chroma', 0.4, { release: 0.3 });
      if (Vc.view) Vc.view.flash([1.2, 2.2, 4], 0.7, 0.25);
      if (isHero(Vc)) { ctx.time.slowmo(0.4, 0.32, { easeIn: 0.02, easeOut: 0.18 }); P.sound('slowmo_in', { volume: 0.4 }); cam.kick({ fov: -2, duration: 0.3 }); }
    }
  }

  function counter(e) {
    const A = e.actor;
    if (!A.view) return;
    const el = elOf(A);
    withFrame(actorFrame(A), () => fx.play([`${el}.explosion`, 'combat.charge.release'], { pos: [0, 1.3, 0], dir: [1, 0.2, 0.3], facing: 1 }, { element: el }, 'game.finisher'));
    A.view.flash(palOf(A).mid, 0.2, 0.35);
    post.impactFrame({ duration: 0.05, invert: 0, mono: 0.7 });
    post.pulse('chroma', 0.6, { release: 0.3 });
    cam.shake(0.5, { freq: 14 });
    if (world.camera) world.camera.zoom(0.85, 0.45);
    P.sound('release', { pos: A.view.pos });
    P.sound(sfxOf(A).burst, { pos: A.view.pos, volume: 0.7 });
  }

  // ---- moves ----------------------------------------------------------------------------------------------------
  function moveStart(e) {
    const A = e.actor;
    if (!A.view || !A.char || !A.char.sockets) return;
    if (e.attack.group === 'skill' && !e.inst.forced && elOf(A) !== 'steel') {
      const tip = A.char.sockets.weaponTip;
      fx.play('combat.charge.gather', { pos: A.socket('weaponTip', new THREE.Vector3()), facing: 1 }, { element: elOf(A), duration: 0.22, follow: tip }, 'game.cast');
      A.view.glow(palOf(A).mid, 0.035, 0.45, 0.06);
      P.sound(sfxOf(A).cast, { pos: A.view.pos, volume: 0.6 });
    }
  }

  const DECAL_WORD = { crack: 'crack', scorch: 'scorch', frost: 'frost', rune: 'rune', glow: 'glow' };
  /** Marker data hints (moves.js): shake, kickFov, afterimage, impactFrame, audio, flash, decal, slowmo. */
  function marker(e, own = false) {
    const d = e.data, A = e.actor;
    if (!d || typeof d !== 'object' || !A || !A.view) return;
    if (typeof d.shake === 'number') cam.shake(d.shake * (isHero(A) ? 1 : 0.8) * Math.min(2, A.scale), { freq: A.scale > 1.6 ? 9 : 15 });
    if (typeof d.kickFov === 'number') cam.kick({ fov: d.kickFov, duration: 0.3 });
    if (d.afterimage) ghost(A, 0.35);
    if (d.impactFrame === true) post.impactFrame({ duration: 0.05, invert: 0, mono: 0.7 });
    const snd = typeof d.audio === 'string' ? d.audio : typeof d.sound === 'string' ? d.sound : null;
    if (snd && !P.playedRecently(snd, 1)) P.sound(snd, { pos: A.view.pos });
    if (typeof d.flash === 'number') A.view.flash(palOf(A).core, d.flash, 0.2);
    if (own || e.cinematic || world.lock) return;
    const kind = typeof d.decal === 'string' ? DECAL_WORD[d.decal.split(/\s+/)[0]] : null;
    if (kind && ctx.vfx && ctx.vfx.decalKinds && ctx.vfx.decalKinds[kind]) {
      const p = kind === 'rune' ? V.set(A.pos.x, 0, A.pos.z) : A.socket('weaponTip', V);
      const el = elOf(A);
      fx.call('decal', { kind, pos: [p.x, 0, p.z], radius: (kind === 'rune' ? 1.4 : 1.1) * A.scale, palette: el === 'steel' ? undefined : el, magma: el === 'ember' ? 0.8 : 0, life: kind === 'rune' ? 1.2 : 2.5 });
    }
    if (typeof d.slowmo === 'number' && d.slowmo > 0 && d.slowmo < 1 && isHero(A)) ctx.time.slowmo(Math.max(d.slowmo, 0.6), 0.3, { easeIn: 0.03, easeOut: 0.2 });
  }

  // ---- movement -------------------------------------------------------------------------------------------------
  function roll(e) {
    const A = e.actor;
    withFrame(makeFrame(A.pos.x, A.pos.z, yawTo(e.dirX, e.dirZ)), () => fx.play('combat.dust.dash', { pos: [0, 0, 0], facing: 1 }, { k: 0.55 }, 'game.dust'));
    P.sound('dodge', { pos: A.view ? A.view.pos : null, volume: 0.75 });
  }
  function dodge(e) {
    const A = e.actor;
    if (!e.perfect || !isHero(A) || !A.view) return;
    if (ctx.time.real - (dodge.at || -9) < 0.6) return;
    dodge.at = ctx.time.real;
    ctx.time.slowmo(0.45, 0.3, { easeIn: 0.02, easeOut: 0.18 });
    post.pulse('chroma', 0.4, { release: 0.3 });
    A.view.flash([1.5, 3, 5], 0.2, 0.25);
    ghost(A, 0.35, 0.55, true);
    P.sound('slowmo_in', { volume: 0.4 });
  }
  function step(e) {
    const A = e.actor;
    if (!A.view || (A.state !== 'move' && A.state !== 'guard' && A.state !== 'roll' && A.state !== 'attack')) return;
    const sprint = A.gait === 'sprint';
    P.sound('step', { pos: A.view.pos, volume: (sprint ? 0.6 : 0.42) * Math.min(1.8, A.scale), pitch: 1 / Math.sqrt(Math.max(0.6, A.scale)) });
    if (A.speed > 3 || A.scale > 1.5) withFrame(actorFrame(A), () => fx.play('combat.dust.step', { pos: [0, 0, 0], facing: 1, scale: A.scale }, { intensity: 0.6 }, null));
  }
  function land(e) {
    const A = e.actor;
    if (!A.view) return;
    fx.play('combat.dust.land', { pos: [A.pos.x, 0, A.pos.z] }, { k: e.hard ? 1.4 : 0.9, heavy: !!e.hard }, 'game.dust');
    P.sound(e.hard ? 'body_fall' : 'land', { pos: A.view.pos });
    cam.shake(e.hard ? 0.2 : 0.1, { freq: 12, dir: [0, 1, 0] });
    A.view.impulse([0, -1, 0], e.hard ? 0.9 : 0.4);
  }
  function teleport(e) {
    const A = e.actor;
    fx.play('game.burst', { pos: [e.fromX, 1.1, e.fromZ] }, { element: elOf(A) === 'steel' ? undefined : elOf(A), k: 0.6 });
    ghost(A, 0.35);
  }
  /** A foe goes down (the hero's death is the flow's / HUD's moment). */
  function death(victim, by) {
    if (!victim.view || victim.spec.boss) return;
    const p = victim.socket('chest', new THREE.Vector3());
    if (!isHero(victim)) {
      const el = elOf(by);
      fx.play('game.burst', { pos: p }, { element: el === 'steel' ? undefined : el, k: 0.8 * Math.min(1.6, victim.scale) });
      P.sound('hit_blunt', { pos: p, volume: 0.5 });
    } else {
      post.pulse('chroma', 0.8, { release: 1.0 });
      ctx.time.slowmo(0.3, 1.1, { easeIn: 0.05, easeOut: 0.5 });
      P.sound('body_fall', { pos: p });
      if (ctx.audio) ctx.audio.duck(0.6, 2.5);
    }
  }

  // ---- ultimate lock defaults (the duel's cineStart / cineTick feel) -------------------------------------------------
  function cineStart(A, Vc) {
    const f = actorFrame(A, Vc.pos);
    const p = Vc.socket('chest', new THREE.Vector3());
    const ps = worldToStage(p.clone(), f);
    withFrame(f, () => fx.play('combat.hit.crit', { pos: [ps.x, ps.y, 0.15], dir: [1, 0.1, 0.3], facing: 1 }, { element: elOf(A) }, 'game.finisher'));
    post.impactFrame({ duration: 0.06, invert: 0, mono: 0.7 });
    post.flash(0xffffff, 0.3, { release: 0.2 });
    post.pulse('chroma', 0.7, { release: 0.45 });
    cam.shake(0.6, { freq: 13 });
    P.sound('hit_crit', { pos: p });
    ctx.time.hitstop(0.18);
    if (Vc.view) Vc.view.flash([1.4, 1.2, 1], 0.5, 0.2);
  }
  function cineTick(A, Vc, e) {
    const f = actorFrame(A, Vc.pos);
    const p = Vc.socket('chest', new THREE.Vector3());
    const ps = worldToStage(p.clone(), f);
    const el = elOf(A);
    withFrame(f, () => {
      if (e.final) {
        fx.play(['combat.hit.crit'], { pos: [ps.x, ps.y, 0.15], dir: [1, 0.25, 0.3], facing: 1, scale: 1.2 * Math.min(2.5, Vc.scale) }, { element: el, intensity: 0.7 }, 'game.finisher');
        const fin = FINISH[el] || FINISH.ember;
        const at = fin.chest ? { pos: [ps.x, ps.y, 0.15], dir: [0, 1, 0], facing: 1 } : { pos: [ps.x, 0.02, 0], dir: [0, 1, 0], facing: 1 };
        fx.play([fin.name, `${el}.eruption`], at, { element: el, k: 1.1, huge: true }, 'game.erupt');
      } else fx.play(['combat.hit.heavy'], { pos: [ps.x, ps.y, 0.15], dir: [1, 0.25, 0.3], facing: 1 }, { element: el, k: 1.05 }, 'game.hit');
    });
    if (e.final) {
      post.flash(0xffffff, 0.3, { release: 0.3 });
      post.impactFrame({ duration: 0.07, invert: 0, mono: 0.8 });
      post.pulse('exposure', 0.15, { release: 0.5 });
      cam.shake(1, { freq: 10, duration: 1.2 });
      P.sound('ult_impact', { pos: p });
      P.sound(sfxOf(A).burst, { pos: p, volume: 0.8 });
    } else {
      post.pulse('chroma', 0.45, { release: 0.2 });
      cam.shake(0.35, { freq: 16 });
      P.sound('hit_slash_heavy', { pos: p });
    }
    if (Vc.view) Vc.view.flash([0.8, 0.66, 0.56], 0.3, 0.12);
    if (e.hitstop) ctx.time.hitstop(e.hitstop);
  }

  // ---- projectiles ----------------------------------------------------------------------------------------------
  // A projectile whose kind names a VFX preset plays it in its stage frame: travelling presets (ember.wave,
  // frost.shard, volt.javelin) follow a stage-space marker and impact() / fizzle with the projectile; strike presets
  // (volt.strike) telegraph for the delay. Other kinds: travelling -> a generic element body; on the floor -> an
  // element telegraph while it arms, then the element eruption.
  const shots = new Map();
  const ramps = {};
  function ribbonRamp(el) {
    if (ramps[el]) return ramps[el];
    const p = paletteOf(el);
    return (ramps[el] = [[0, p.core[0] * 0.5, p.core[1] * 0.5, p.core[2] * 0.5, 0.9], [0.2, p.mid[0], p.mid[1], p.mid[2], 0.6], [1, p.tail[0], p.tail[1], p.tail[2], 0]]);
  }
  /** Stage frame of a projectile: origin where its owner cast it, +X toward the projectile (its travel line). */
  function projFrame(p) {
    const dx = p.x0 - p.ownerX, dz = p.z0 - p.ownerZ;
    const yaw = p.speed > 0.6 ? p.yaw : dx * dx + dz * dz > 0.09 ? yawTo(dx, dz) : p.ownerYaw;
    return makeFrame(p.ownerX, p.ownerZ, yaw);
  }
  function stagePos(p, f, out) { return worldToStage(out.set(p.x, p.y, p.z), f, out); }

  function body(v, p) {
    const el = v.el, P2 = paletteOf(el);
    const m = v.markerW;
    v.handles.push(fx.call('flare', { kind: 'glow', pos: m.position, follow: m, color: P2.core, intensity: 0.8, size: 0.7, life: 30 }));
    v.handles.push(fx.call('ribbon', { follow: m, life: 0.32, width: 0.45, color: ribbonRamp(el) }));
    const em = fx.call('emitter', defsOf(el).trailMotes, { pos: m.position });
    if (em.follow) em.follow(m);
    v.handles.push(em);
    v.handles.push(fx.call('light', { pos: m.position, follow: m, color: P2.core, intensity: 60, range: 5, duration: Infinity }));
    void p;
  }
  function erupt(v, p) {
    if (v.erupted) return;
    v.erupted = true;
    for (const h of v.handles) if (h.stop) h.stop();
    v.handles.length = 0;
    const d = v.data, size = typeof d.size === 'number' ? d.size : 1;
    const huge = !!(d.huge || d.last);
    const f = v.frame;
    const sp = stagePos(p, f, new THREE.Vector3());
    const name = fx.has(v.kind) ? v.kind : GROUND[v.el];
    withFrame(f, () => {
      const at = { pos: [sp.x, 0.02, sp.z], dir: [0, 1, 0], facing: 1, scale: huge ? 1.15 : 1 };
      if (typeof d.length === 'number') { at.pos = [sp.x - d.length * 0.5, 1.0, sp.z + 0.1]; at.target = new THREE.Vector3(sp.x + d.length * 0.5, 1.0, sp.z + 0.1); at.dir = [1, 0, 0]; }
      if (name) fx.play(name, at, { element: v.el, huge, intensity: huge ? 1 : 0.85, k: 1 }, 'game.erupt');
      else {
        const H = Math.max(0.6, 1.6 * size);
        fx.call('spikes', { kind: 'ice', pattern: 'cluster', pos: [sp.x, 0, sp.z], radius: 0.2 + 0.25 * size, count: huge ? 6 : 3 + Math.round(size * 2), height: [H * 0.5, H], width: 0.22, stagger: 0.02, hold: d.hold ?? 0.6, facing: 1 });
        fx.call('decal', { kind: 'frost', pos: [sp.x, 0, sp.z], radius: 0.7 + 0.6 * size, life: 2.5 });
        fx.call('light', { pos: [sp.x, 0.8, sp.z + 0.9], color: paletteOf(v.el).core, intensity: 50 + 40 * size, range: 5, duration: 0.4 });
      }
    });
    const snd = sfxOf(v.owner).burst;
    if (huge || !P.playedRecently(snd, 0.1)) P.sound(snd, { pos: new THREE.Vector3(p.x, 0.5, p.z), volume: huge ? 0.85 : 0.55 });
    cam.shake(huge ? 0.35 : 0.2, { freq: 14 });
  }

  /** projectileSpawn: `suppressed` = the choreography's spawn handler returned false (it draws the projectile). */
  function projectileSpawn(p, suppressed) {
    if (suppressed) return;
    const A = p.owner;
    const el = elOf(A) === 'steel' ? 'ember' : elOf(A);
    const f = projFrame(p);
    const v = { id: p.id, owner: A, kind: p.kind, data: p.data || {}, frame: f, el, handles: [], ground: p.ground, preset: null, erupted: false, impacted: false,
      bodyPending: false, marker: null, markerW: null };
    shots.set(p.id, v);
    const sp = stagePos(p, f, new THREE.Vector3());
    if (v.ground) {
      if (WARN_PRESETS.has(v.kind) && fx.has(v.kind)) {
        v.erupted = true;
        withFrame(f, () => fx.play(v.kind, { pos: [sp.x, 0.02, sp.z], dir: [0, 1, 0], facing: 1 }, { element: el, warn: p.delay, huge: !!v.data.huge }, null));
      } else {
        const wait = p.delay - (LEAD[fx.has(v.kind) ? v.kind : GROUND[el] || ''] ?? 0.05);
        if (wait > 0.008 && ctx.vfx) {
          if (wait > 0.08) {
            const T = TELEGRAPH[el] || TELEGRAPH.volt;
            v.handles.push(fx.call('decal', { ...T, pos: [p.x, 0, p.z], life: p.delay + 0.6, reveal: Math.min(T.reveal, wait), fadeOut: 0.3 }));
            v.handles.push(fx.call('light', { pos: [p.x, 0.5, p.z], color: palOf(A).core, intensity: 35, range: 4, duration: p.delay + 0.1, attack: p.delay }));
          }
          ctx.vfx.schedule(wait, () => erupt(v, p));
        } else erupt(v, p);
      }
      return;
    }
    if (fx.has(v.kind)) {
      // a stage-space marker (unparented: its world matrix carries stage coordinates; stage.js hangs the preset's
      // anchor under the frame node)
      v.marker = new THREE.Object3D();
      v.marker.position.copy(sp);
      v.marker.updateMatrixWorld(true);
      const g = withFrame(f, () => fx.play(v.kind, { pos: sp.clone(), dir: [1, p.speed > 0 ? p.vy / p.speed : 0, 0], facing: 1 }, { element: el, follow: v.marker }, null));
      if (g !== fx.NULL) { v.preset = g; v.handles.push(g); }
    }
    if (!v.preset) {
      v.markerW = new THREE.Object3D();
      v.markerW.position.set(p.x, p.y, p.z);
      v.markerW.updateMatrixWorld(true);
      if (v.data.statue && A.char) fx.call('afterimage', A.char.root, { palette: el, life: p.delay + 0.3, intensity: 0.6, fill: 0.12 });
      if (p.delay > 0.05) v.bodyPending = true; else body(v, p);
    }
    P.sound(sfxOf(A).cast, { pos: new THREE.Vector3(p.x, p.y, p.z), volume: 0.7 });
  }
  function projectileActive(p) {
    const v = shots.get(p.id);
    if (!v) return;
    if (v.ground) erupt(v, p);
    else if (v.bodyPending) { v.bodyPending = false; v.markerW.position.set(p.x, p.y, p.z); v.markerW.updateMatrixWorld(true); body(v, p); }
  }
  function projectileHit(p, e) {
    const v = shots.get(p.id);
    if (v && v.preset && typeof v.preset.impact === 'function' && !v.impacted) {
      v.impacted = true;
      const sp = worldToStage(new THREE.Vector3(e.pos.x, e.pos.y, e.pos.z), v.frame);
      withFrame(v.frame, () => v.preset.impact(sp));
    }
  }
  function projectileExpire(p, reason) {
    const v = shots.get(p.id);
    if (!v) return;
    shots.delete(p.id);
    if (v.preset && !v.impacted) {
      if (typeof v.preset.impact === 'function' && reason === 'wall') { const sp = stagePos(p, v.frame, new THREE.Vector3()); withFrame(v.frame, () => v.preset.impact(sp)); }
      else v.preset.stop();
    }
    for (const h of v.handles) if (h !== v.preset) { if (h.stop) h.stop(); else if (h.kill) h.kill(); }
    if (!v.preset && !v.ground && !v.bodyPending && (reason === 'lifetime' || reason === 'wall')) fx.play('game.burst', { pos: [p.x, p.y, p.z] }, { element: v.el, k: 0.5 });
  }
  /** Per frame: move the projectile markers with the projectiles. */
  function updateProjectiles() {
    if (!shots.size) return;
    const list = world.projectiles.list;
    for (let k = 0; k < list.length; k++) {
      const p = list[k];
      const v = shots.get(p.id);
      if (!v || v.ground) continue;
      if (v.marker) { stagePos(p, v.frame, v.marker.position); v.marker.updateMatrixWorld(true); }
      if (v.markerW) { v.markerW.position.set(p.x, p.y, p.z); v.markerW.updateMatrixWorld(true); }
    }
  }
  function clearProjectiles() {
    for (const v of shots.values()) for (const h of v.handles) if (h.kill) h.kill();
    shots.clear();
  }

  void hypot2; void stageToWorld;
  return { hit, guard, counter, moveStart, marker, roll, dodge, step, land, teleport, death, cineStart, cineTick, ghost,
    projectileSpawn, projectileActive, projectileHit, projectileExpire, updateProjectiles, clearProjectiles, projFrame };
}
