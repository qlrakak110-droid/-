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
/** Climax preset of the default ultimate finish per element (chest: played at the victim's chest, else its floor). */
const FINISH = { ember: { name: 'ember.eruption' }, frost: { name: 'frost.shatter', chest: true }, volt: { name: 'volt.strike' } };
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
  /** Screen-flash tint of a fighter: its element hue lifted toward paper white (a pure white flash reads as a white-out). */
  const tintOf = (A) => { const c = A.palette.core, m = Math.max(c[0], c[1], c[2], 1e-3); return [0.55 + 0.45 * c[0] / m, 0.55 + 0.45 * c[1] / m, 0.55 + 0.45 * c[2] / m]; };
  // light-foot afterimages draw a decimated silhouette of the character: build it now (behind the VS splash), not on
  // the first dodge
  if (ctx.vfx && ctx.vfx.afterimageProxy) for (const a of session.actors) { try { ctx.vfx.afterimageProxy(a.char.root); } catch (err) { /* ghosts fall back to the full meshes */ } }

  /**
   * Light-foot afterimages of a fighter in its element palette: a short trail of ghosts (each one draw of the
   * character's decimated silhouette proxy; the VFX pool caps the ghosts alive per fighter). The generic ones are
   * rate-limited to one trail per fighter per 0.25 s of game time (`force` for the perfect dodge).
   */
  const ghostAt = [-1, -1];
  function ghost(A, life, intensity = 0.7, force = false, count = 2) {
    const t = ctx.time.game;
    if (!force && t - ghostAt[A.index] < 0.25) return;
    ghostAt[A.index] = t;
    fx.call('afterimage', A.char.root, { palette: A.element, life, intensity, count, interval: 0.045 });
  }

  /** Contact point slightly in front of the bodies (toward the camera) so sparks are never buried. */
  function contact(e, out = P) { return out.set(e.x, e.y ?? 1.2, 0.18); }

  function hit(e) {
    const A = session.actors[e.attacker], V = session.actors[e.defender];
    const pos = contact(e).clone();
    const dir = D.set(e.facing, 0.18, 0.32).normalize().clone();
    if (e.blocked) {
      if (e.guardBreak) return;
      fx.play('combat.guard.block', { pos, dir, facing: e.facing }, { perfect: e.perfect }, 'game.guard');
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
    // the VFX library's tuned presets first (combat.hit.<level>, crit for counters / ultimates, the element hit for
    // skills), the generic game.hit while they do not exist
    const names = e.counter || group === 'ult' ? ['combat.hit.crit', `combat.hit.${lvl}`] : group === 'skill' ? [`${el}.hit`, `combat.hit.${lvl}`] : [`combat.hit.${lvl}`];
    fx.play(names, { pos, dir, facing: e.facing }, { element: el, k, level: lvl, intensity: e.armoured ? 0.6 : 0.85 + 0.15 * Math.min(1, k) }, 'game.hit');
    if (!e.armoured) {
      V.impulse([e.front === false ? 1 : -1, lvl === 'launch' ? 0.5 : 0.1, 0.12], FLINCH[lvl] ?? 1);
      V.char.flash([0.8, 0.66, 0.56], Math.min(0.6, 0.22 + 0.22 * k), 0.12);
    } else V.char.flash([2, 1.2, 0.6], 0.6, 0.15);
    const finisher = group !== 'normal' && (lvl === 'launch' || lvl === 'knockdown' || lvl === 'crumple');
    cam.shake(lvl === 'light' ? 0.15 + (e.counter ? 0.12 : 0) : finisher ? 0.5 : 0.35 + (e.counter ? 0.15 : 0), { freq: lvl === 'light' ? 20 : 15 });
    if (k >= 0.9) cam.kick({ fov: -1.2 - 1.8 * Math.min(1, k - 0.9), duration: 0.28 });
    post.pulse('chroma', 0.15 + 0.35 * Math.max(0, k - 0.55), { release: 0.22 });
    // (radial blur smears a bright core into a ball over the struck fighter: kept short and modest)
    if (k >= 0.9) { post.radialAt(pos); post.pulse('radial', 0.16 + 0.24 * Math.min(1, k - 0.9), { attack: 0.01, release: 0.18 }); }
    if (e.counter || finisher || group === 'ult') {
      // the ink frame: two-tone ink on paper for 2-3 frames, with brushed radial lines converging on the contact
      const dur = e.counter && !finisher ? 0.034 : 0.05;
      post.impactFrame({ duration: dur, invert: 0, mono: 0.75 });
      fx.call('speedlines', { pos, life: dur + 0.05, intensity: 0.55, density: 64, inner: 0.32, thickness: 1.7, boil: 30, attack: 0.01, release: 0.05, realtime: true });
    }
    if (finisher) post.flash(tintOf(A), 0.1, { release: 0.15 });
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
    fx.play('combat.guard.break', { pos, dir: [session.match.fighters[e.attacker].facing, 0.3, 0.3] }, {}, 'game.guardBreak');
    session.sound('guard_break', { pos });
    cam.shake(0.5, { freq: 14 });
    cam.kick({ fov: -3, duration: 0.35 });
    post.pulse('chroma', 0.7, { release: 0.35 });
    post.flash(0xdde8ff, 0.15, { release: 0.2 });
    V.char.flash([1, 1.5, 2.5], 0.35, 0.3);
    V.impulse([-1, 0.3, 0.1], 1.6);
    ctx.time.hitstop(0.12);
  }

  function counter(e) {
    const A = session.actors[e.fighter];
    const pos = A.socket('chest', new THREE.Vector3());
    fx.play([`${A.element}.explosion`, 'combat.charge.release'], { pos, dir: [A.facing, 0.2, 0.3], facing: A.facing }, { element: A.element }, 'game.finisher');
    A.char.flash(A.palette.mid, 0.2, 0.35);
    post.impactFrame({ duration: 0.05, invert: 0, mono: 0.7 });
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
      fx.play('combat.charge.gather', { pos, facing: A.facing }, { element: A.element, duration: 0.22, follow: A.char.sockets.weaponTip }, 'game.cast');
      // inner energy flares up the body as the technique starts
      fx.play('combat.aura.flare', { pos: A.at(0, 0, 0, new THREE.Vector3()), facing: A.facing }, { element: A.element, k: 0.8 }, null);
      A.glow(A.palette.mid, 0.035, 0.45, 0.06);
      session.sound(sfxOf(e.fighter).cast, { pos, volume: 0.6 });
    }
  }
  function moveEnd() {}

  /**
   * Marker data hints (moves.js authors can drive generic feel with data alone):
   *   { shake: trauma, kickFov: deg, afterimage: true, impactFrame: true, audio | sound: 'name', flash: amount,
   *     decal: 'crack' | 'scorch …' | 'frost' | 'rune …' | 'glow', slowmo: scale, cam: { shot, dur, slowmo, subject } }
   * (`vfx` / `fx` strings in marker data are storyboard notes: presets are placed by the choreography, never
   * automatically.) Decals, slow motion and camera cues are skipped during a cinematic lock.
   */
  const DECAL_WORD = { crack: 'crack', scorch: 'scorch', frost: 'frost', rune: 'rune', glow: 'glow' };
  /** Camera-cue framing kept clear of the effects on the fight line (the default ground skim runs 1.2 m from it,
   *  inside eruption columns and spike lines). */
  const CUE = { groundSkim: { from: [-1.4, 0.32, 3.6], to: [-1.8, 0.38, 3.1], fov: [46, 40] } };
  /** @param {boolean} [own] the fighter's choreography handles this marker: it owns the set piece (decal, slow
   *  motion and camera hints are skipped; the light hints still layer under it) */
  function marker(e, own = false) {
    const d = e.data;
    if (!d || typeof d !== 'object' || e.fighter === undefined) return;
    const A = session.actors[e.fighter];
    if (typeof d.shake === 'number') cam.shake(d.shake, { freq: 15 });
    if (typeof d.kickFov === 'number') cam.kick({ fov: d.kickFov, duration: 0.3 });
    if (d.afterimage) ghost(A, 0.35);
    if (d.impactFrame === true) post.impactFrame({ duration: 0.05, invert: 0, mono: 0.7 });
    const snd = typeof d.audio === 'string' ? d.audio : typeof d.sound === 'string' ? d.sound : null;
    // a marker sound the generic layer played within the last second (ult_start of the super-freeze, ult_impact of the
    // lock finish) is not doubled
    if (snd && !session.playedRecently(snd, 1)) session.sound(snd, { pos: A.pos });
    if (typeof d.flash === 'number') A.char.flash(A.palette.core, d.flash, 0.2);
    if (own || e.cinematic || match.cinematic) return;
    // floor decal: 'crack' / 'scorch arc' at the weapon tip, 'rune circle' under the fighter
    const kind = typeof d.decal === 'string' ? DECAL_WORD[d.decal.split(/\s+/)[0]] : null;
    if (kind && ctx.vfx && ctx.vfx.decalKinds && ctx.vfx.decalKinds[kind]) {
      const x = kind === 'rune' ? A.pos.x : A.socket('weaponTip', P).x;
      fx.call('decal', { kind, pos: [x, 0, 0.05], radius: kind === 'rune' ? 1.4 : 1.1, palette: A.element, magma: A.element === 'ember' ? 0.8 : 0, life: kind === 'rune' ? 1.2 : 2.5 });
    }
    if (typeof d.slowmo === 'number' && d.slowmo > 0 && d.slowmo < 1) ctx.time.slowmo(d.slowmo, 0.4, { easeIn: 0.03, easeOut: 0.2 });
    // camera cue { shot: vocabulary name, dur, slowmo, subject }: a short shot anchored on the fighter, then back
    const c = d.cam;
    if (c && typeof c === 'object' && typeof SHOTS[c.shot] === 'function' && cam.mode === 'fight') {
      const o = { ...CUE[c.shot], dur: c.dur || 0.5 };
      if (c.slowmo) o.slowmo = c.slowmo;
      if (c.subject) o.subject = c.subject;
      cam.play([SHOTS[c.shot](o)], { anchor: e.fighter, blendOut: 0.3, hud: false });
    }
  }

  // ---- ultimate lock ---------------------------------------------------------------------------------------------
  function cineStart(e) {
    const V = session.actors[e.defender], A = session.actors[e.attacker];
    const pos = V.socket('chest', new THREE.Vector3());
    fx.play('combat.hit.crit', { pos, dir: [A.facing, 0.1, 0.3], facing: A.facing }, { element: A.element }, 'game.finisher');
    post.impactFrame({ duration: 0.06, invert: 0, mono: 0.8 });
    post.flash(tintOf(A), 0.14, { release: 0.2 });
    post.pulse('chroma', 0.7, { release: 0.45 });
    cam.shake(0.6, { freq: 13 });
    session.sound('hit_crit', { pos });
    ctx.time.hitstop(0.18);
    V.char.flash([1.4, 1.2, 1], 0.5, 0.2);
  }

  function cineTick(e) {
    const A = session.actors[e.attacker], V = session.actors[e.defender];
    const pos = V.socket('chest', new THREE.Vector3());
    pos.z += 0.15;
    const dir = new THREE.Vector3(A.facing, 0.25, 0.3).normalize();
    if (e.final) {
      fx.play(['combat.hit.crit'], { pos, dir, facing: A.facing, scale: 1.2 }, { element: A.element, intensity: 0.7 }, 'game.finisher');
      // element climax of the default finish: magma column, crystal shatter, sky strike
      const fin = FINISH[A.element] || FINISH.ember;
      const at = fin.chest ? { pos: pos.clone(), dir: [0, 1, 0], facing: A.facing } : { pos: V.at(0, 0, 0, new THREE.Vector3()), dir: [0, 1, 0], facing: A.facing };
      fx.play([fin.name, `${A.element}.eruption`], at, { element: A.element, k: 1.1, huge: true }, 'game.erupt');
      // the finish is an ink frame (black ground, the blast as paper light), never an inverted white frame
      post.flash(tintOf(A), 0.16, { release: 0.3 });
      post.impactFrame({ duration: 0.07, invert: 0, mono: 0.85 });
      post.pulse('exposure', 0.08, { release: 0.5 });
      cam.shake(1, { freq: 10, duration: 1.2 });
      session.sound('ult_impact', { pos });
      session.sound(sfxOf(e.attacker).burst, { pos, volume: 0.8 });
    } else {
      fx.play(['combat.hit.heavy'], { pos, dir, facing: A.facing }, { element: A.element, k: 1.05 }, 'game.hit');
      post.pulse('chroma', 0.45, { release: 0.2 });
      cam.shake(0.35, { freq: 16 });
      session.sound('hit_slash_heavy', { pos });
    }
    V.char.flash([0.8, 0.66, 0.56], 0.3, 0.12);
    if (e.hitstop) ctx.time.hitstop(e.hitstop);
    const f = match.fighters[e.attacker];
    if (hud() && f.combo.hits >= 2) hud().combo(e.attacker, f.combo.hits, f.combo.damage);
    session.stats.tick(e);
  }

  // ---- projectiles -----------------------------------------------------------------------------------------------
  // A projectile whose `kind` names a VFX preset plays it (the move files' convention): travelling presets
  // ('ember.wave', 'frost.shard', 'volt.javelin') follow the rules projectile and impact() / fizzle with it; strike
  // presets ('volt.strike': armed with `warn` = the rules delay, 'volt.chain': along data.length) play on the floor.
  // Other kinds get an element body: travelling (>= 2 m/s) -> glow, ribbon, motes, light, slash arc from the moment it
  // is armed; on the floor (opponent-anchored, or creeping < 2 m/s: spike lines, columns) -> a rune telegraph while it
  // is armed, then the element eruption (ember.eruption, an ice-spike cluster sized by data.size, volt.strike).
  const shots = new Map();
  const tmpRamp = {};
  const WARN_PRESETS = new Set(['volt.strike']);
  const GROUND = { ember: 'ember.eruption', volt: 'volt.strike' };
  /** Lead time of a ground preset (crack before the column ...): it starts that much before the rules arm the hit. */
  const LEAD = { 'ember.eruption': 0.14, '': 0.05 };
  /** Floor telegraph per element while a ground projectile is armed. */
  const TELEGRAPH = { ember: { kind: 'crack', magma: 1, radius: 1.1, reveal: 0.2 }, frost: { kind: 'frost', radius: 1.0, reveal: 0.25 }, volt: { kind: 'rune', palette: 'volt', radius: 1.1, reveal: 0.25, intensity: 0.8 } };
  function ribbonRamp(el) {
    if (tmpRamp[el]) return tmpRamp[el];
    const p = fx.paletteOf(el);
    return (tmpRamp[el] = [[0, p.core[0] * 0.5, p.core[1] * 0.5, p.core[2] * 0.5, 0.9], [0.2, p.mid[0], p.mid[1], p.mid[2], 0.6], [1, p.tail[0], p.tail[1], p.tail[2], 0]]);
  }
  /** Generic travelling body (glow, ribbon, motes, light, element slash arc) following the proxy. */
  function body(v) {
    const P2 = fx.paletteOf(v.el);
    v.handles.push(fx.call('flare', { kind: 'glow', pos: v.proxy.position, follow: v.proxy, color: P2.core, intensity: 0.8, size: 0.7, life: 30 }));
    v.handles.push(fx.call('ribbon', { follow: v.proxy, life: 0.32, width: 0.45, color: ribbonRamp(v.el) }));
    const em = fx.call('emitter', fx.defsOf(v.el).trailMotes, { pos: v.proxy.position });
    if (em.follow) em.follow(v.proxy);
    v.handles.push(em);
    v.handles.push(fx.call('light', { pos: v.proxy.position, follow: v.proxy, color: P2.core, intensity: 60, range: 5, duration: Infinity }));
    v.handles.push(fx.call('slash', { pos: v.proxy.position, follow: v.proxy, look: { ember: 'flame', frost: 'ice', volt: 'electric' }[v.el] || 'razor', palette: v.el,
      facing: v.facing, normal: [0, 0, 1], forward: [1, 0, 0], arc: [-70, 70], radius: 0.8, width: 0.4, intensity: 0.8, life: v.life + 0.2, sweep: 0.05 }));
  }
  /** Floor eruption of a ground projectile at x (preset named by its kind, else the element's). */
  function erupt(v, x) {
    if (v.erupted) return;
    v.erupted = true;
    for (const h of v.handles) { if (h.stop) h.stop(); }
    v.handles.length = 0;
    const d = v.data, f = v.facing, size = typeof d.size === 'number' ? d.size : 1;
    const huge = !!(d.huge || d.last);
    const at = { pos: new THREE.Vector3(x, 0.02, 0), dir: [0, 1, 0], facing: f, scale: huge ? 1.15 : 1 };
    if (typeof d.length === 'number') {
      // a line (chain lightning laid over the projectile's length)
      at.pos.set(x - f * d.length * 0.5, 1.0, 0.1);
      at.target = new THREE.Vector3(x + f * d.length * 0.5, 1.0, 0.1);
      at.dir = [f, 0, 0];
    }
    const name = fx.has(v.kind) ? v.kind : GROUND[v.el];
    if (name) fx.play(name, at, { element: v.el, huge, intensity: huge ? 1 : 0.85, k: 1 }, 'game.erupt');
    else {
      // ice: a spike cluster sized by data.size, frost on the floor, a cold light
      const H = Math.max(0.6, 1.6 * size);
      fx.call('spikes', { kind: 'ice', pattern: 'cluster', pos: [x, 0, 0], radius: 0.2 + 0.25 * size, count: huge ? 6 : 3 + Math.round(size * 2), height: [H * 0.5, H], width: 0.22, stagger: 0.02, hold: d.hold ?? 0.6, facing: f });
      fx.call('decal', { kind: 'frost', pos: [x, 0, 0], radius: 0.7 + 0.6 * size, life: 2.5 });
      fx.call('light', { pos: [x, 0.8, 0.9], color: fx.paletteOf(v.el).core, intensity: 50 + 40 * size, range: 5, duration: 0.4 });
    }
    // a line of eruptions is one sound per 0.1 s, not one per column / spike
    const snd = sfxOf(v.owner).burst;
    if (huge || !session.playedRecently(snd, 0.1)) session.sound(snd, { pos: at.pos, volume: huge ? 0.85 : 0.55 });
    cam.shake(huge ? 0.35 : 0.2, { freq: 14 });
  }
  function projectile(name, e, suppressed) {
    if (name === 'projectileSpawn') {
      if (suppressed) return;
      const A = session.actors[e.owner];
      const proxy = new THREE.Object3D();
      proxy.position.set(e.x, e.y, 0.05);
      proxy.updateMatrixWorld();
      const speed = Math.hypot(e.vx || 0, e.vy || 0);
      const delay = e.delay || 0;
      const v = { id: e.id, owner: e.owner, kind: e.kind || '', data: e.data || {}, facing: e.facing || A.facing, proxy, handles: [], el: A.element,
        ground: speed < 2, preset: null, erupted: false, impacted: false, bodyPending: false, life: (e.lifetime || 1) + delay };
      shots.set(e.id, v);
      if (v.ground) {
        if (WARN_PRESETS.has(v.kind) && fx.has(v.kind)) {
          // the strike preset telegraphs itself and lands when the rules arm the projectile
          v.erupted = true;
          fx.play(v.kind, { pos: [e.x, 0.02, 0], dir: [0, 1, 0], facing: v.facing }, { element: v.el, warn: delay, huge: !!v.data.huge }, null);
        } else {
          const wait = delay - (LEAD[fx.has(v.kind) ? v.kind : GROUND[v.el] || ''] ?? 0.05);
          if (wait > 0.008 && ctx.vfx) {
            // a telegraph only when there is time to read it; a staggered line keeps its stagger either way
            if (wait > 0.08) {
              const T = TELEGRAPH[v.el] || TELEGRAPH.volt;
              v.handles.push(fx.call('decal', { ...T, pos: [e.x, 0, 0], life: delay + 0.6, reveal: Math.min(T.reveal, wait), fadeOut: 0.3 }));
              v.handles.push(fx.call('light', { pos: [e.x, 0.4, 0.6], color: A.palette.core, intensity: 35, range: 4, duration: delay + 0.1, attack: delay }));
            }
            ctx.vfx.schedule(wait, () => erupt(v, e.x));
          } else erupt(v, e.x);
        }
        return;
      }
      if (fx.has(v.kind)) {
        const g = fx.play(v.kind, { pos: proxy.position.clone(), dir: [Math.sign(e.vx) || v.facing, e.vy / speed, 0], facing: v.facing }, { element: v.el, follow: proxy }, null);
        if (g !== fx.NULL) { v.preset = g; v.handles.push(g); }
      }
      if (!v.preset) {
        // statue-like shots wait where they were left (an afterimage of the owner); the body appears when armed
        if (v.data.statue) fx.call('afterimage', A.char.root, { palette: v.el, life: delay + 0.3, intensity: 0.6, fill: 0.12 });
        if (delay > 0.05) v.bodyPending = true; else body(v);
      }
      session.sound(sfxOf(e.owner).cast, { pos: proxy.position, volume: 0.7 });
    } else if (name === 'projectileActive') {
      const v = shots.get(e.id);
      if (!v) return;
      if (v.ground) erupt(v, e.x);
      else if (v.bodyPending) { v.bodyPending = false; v.proxy.position.set(e.x, e.y, 0.05); v.proxy.updateMatrixWorld(); body(v); }
    } else if (name === 'projectileHit') {
      const v = shots.get(e.id);
      if (v && v.preset && typeof v.preset.impact === 'function' && !v.impacted) { v.impacted = true; v.preset.impact(new THREE.Vector3(e.x, e.y, 0.1)); }
    } else if (name === 'projectileExpire') {
      const v = shots.get(e.id);
      if (!v) return;
      shots.delete(e.id);
      const p = v.proxy.position.clone();
      if (v.preset && !v.impacted) {
        if (typeof v.preset.impact === 'function' && e.reason !== 'lifetime' && e.reason !== 'bounds' && e.reason !== 'round') v.preset.impact(p);
        else v.preset.stop();
      }
      for (const h of v.handles) if (h !== v.preset) { if (h.stop) h.stop(); else if (h.kill) h.kill(); }
      if (!v.preset && !v.ground && !v.bodyPending && (e.reason === 'clash' || e.reason === 'lifetime' || e.reason === 'bounds')) {
        fx.play('game.burst', { pos: p }, { element: v.el, k: e.reason === 'clash' ? 1.2 : 0.5 });
      }
    } else if (name === 'projectileClash') {
      cam.shake(0.25);
      session.sound('shockwave', { pos: [e.x, e.y, 0], volume: 0.6 });
    }
  }
  const projectileHit = (e) => projectile('projectileHit', e, false);
  /** Per frame: move the generic projectile bodies with the rules projectiles. */
  function updateProjectiles() {
    if (!shots.size) return;
    const list = match.projectiles;
    for (const v of shots.values()) {
      if (v.ground) continue;
      for (let k = 0; k < list.length; k++) {
        const p = list[k];
        if (p.id !== v.id) continue;
        v.proxy.position.set(p.x, p.y, 0.05);
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
    if (e.kind === 'dash' || e.kind === 'roll') fx.play('combat.dust.dash', { pos, facing: A.facing }, { k: 0.55 }, 'game.dust');
    if (e.kind === 'backstep') fx.play('combat.dust.dash', { pos, facing: -A.facing }, { k: 0.45, intensity: 0.7 }, 'game.dust');
    if (e.kind === 'dodge') ghost(A, 0.3);
    session.sound('dodge', { pos, volume: e.kind === 'dash' ? 0.7 : 0.85 });
  }
  function perfectDodge(e) {
    const A = session.actors[e.fighter];
    ctx.time.slowmo(0.35, 0.4, { easeIn: 0.02, easeOut: 0.2 });
    post.pulse('chroma', 0.45, { release: 0.35 });
    A.char.flash([1.5, 3, 5], 0.6, 0.3);
    ghost(A, 0.45, 0.8, true, 3);
    session.sound('slowmo_in', { volume: 0.45 });
  }
  function land(e) {
    const A = session.actors[e.fighter];
    const pos = A.at(0, 0, 0, new THREE.Vector3());
    const heavy = e.hard || e.ko;
    fx.play('combat.dust.land', { pos }, { k: heavy ? 1.4 : 0.9, heavy }, 'game.dust');
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
    ghost(A, 0.35);
  }

  function ko(e) {
    const V = session.actors[e.fighter], A = session.actors[e.by];
    const pos = V.socket('chest', new THREE.Vector3());
    session.stats.ko(e);
    if (!e.cinematic) {
      // the impact reads first (flash, impact frame), then time sinks into slow motion
      if (ctx.vfx) ctx.vfx.schedule(0.09, () => ctx.time.slowmo(0.22, 1.7, { easeIn: 0.06, easeOut: 0.7 }), { realtime: true });
      fx.play('combat.ko.burst', { pos, dir: [A.facing, 0.2, 0.3], facing: A.facing, scale: 0.7 }, { element: A.element, intensity: 0.5, realtime: true, k: 0.5 }, 'game.finisher');
      post.impactFrame({ duration: 0.06, invert: 0, mono: 0.7 });
      if (cam.mode !== 'cine') {
        cam.play([
          // framed wide enough that the falling victim reads (2.4 m filled the frame with its own weapon and the burst)
          SHOTS.impactPunchIn({ dur: 0.75, clock: 'real', shake: 0.8, dist: [5.2, 3.8], height: [1.5, 1.35], look: 1.1, fov: [40, 34] }),
          SHOTS.orbitSweep({ dur: 1.8, clock: 'real', cut: 0.3, subject: 'target', from: -30, to: 10, radius: [4.6, 4.0], height: [1.0, 1.6], look: 0.9 }),
        ], { anchor: e.by, blendOut: 0.9 });
      }
    }
    post.pulse('chroma', 0.6, { release: 0.8 });
    post.radialAt(pos);
    post.pulse('radial', 0.45, { attack: 0.01, release: 0.6 });
    session.sound('announce_ko');
    session.sound('slowmo_in', { delay: 0.05, volume: 0.6 });
    if (ctx.audio) ctx.audio.duck(0.6, 2.5);
    if (hud()) hud().announce('ko');
  }

  /**
   * Footstep dust (clip step events). The planted foot of an attack is a stomp (진각): a low dust ring, ink strokes
   * along the stone, leaves and pebbles; heavies, skills and ultimates crack the floor.
   */
  function step(actor) {
    const pos = actor.at(0, 0, 0, new THREE.Vector3());
    const f = match.fighters[actor.index];
    const mv = f && f.state === 'attack' && f.move ? match.defs[actor.index].moves[f.move] : null;
    if (mv) {
      const heavy = mv.group !== 'normal' || /heavy/.test((mv.meta && mv.meta.slot) || '');
      // the lead foot lands ahead of the root
      pos.x += actor.facing * 0.35;
      fx.play(['combat.dust.stomp', 'combat.dust.step'], { pos, facing: actor.facing }, { intensity: heavy ? 1 : 0.7, heavy }, null);
      if (heavy) cam.shake(0.08, { freq: 14, dir: [0, 1, 0] });
      return;
    }
    fx.play('combat.dust.step', { pos, facing: actor.facing }, { intensity: 0.7 }, null);
  }

  function state(e) {
    if (e.to === 'victory') session.onVictory(e.fighter);
  }

  return {
    hit, guardBreak, counter, moveStart, moveEnd, marker, cineStart, cineTick, projectile, projectileHit, updateProjectiles, clearProjectiles,
    dodge, perfectDodge, land, tech, wallBounce, teleport, ko, state, step,
  };
}
