// Cinematic sequencer: plays a list of keyed shots authored in the anchor fighter's local frame.
//
// Each shot is normalised once at play() time (no per-frame allocation). Every frame the current shot is evaluated
// into a Pose; shot changes report a transition (hard cut or timed blend) that the director applies. Positions are
// mirrored by the anchor's facing, so one shot list serves both sides of the screen.

import * as THREE from 'three';
import { clamp, lerp, ease as resolveEase, DEG } from '../core/math.js';
import { Pose, Damp3, readPoint } from './pose.js';

/** A coordinate frame a shot can be authored in. */
class SpaceRef {
  constructor(kind, src = null) {
    this.kind = kind;        // 'anchor' | 'target' | 'mid' | 'world' | 'arena' | 'custom'
    this.src = src;
    this.snap = new THREE.Vector3();
    this.live = new Damp3();
    this.raw = new THREE.Vector3();
  }
}

const toV3 = (a) => (a == null ? null : a.isVector3 ? a.clone() : new THREE.Vector3(a[0], a[1], a[2]));
const pair = (v, d) => (v == null ? [d, d] : Array.isArray(v) ? [v[0], v[1] ?? v[0]] : [v, v]);
const asList = (v) => (v == null || v === false ? [] : Array.isArray(v) ? v : [v]);

/**
 * @param {object} ctx  app context
 * @param {object} dir  director services: { shaker, letterboxTo(v, dur), letterboxValue(), targets: [srcA, srcB], fight }
 */
export function createSequencer(ctx, dir) {
  const pose = new Pose();
  const refs = { anchor: new SpaceRef('anchor'), target: new SpaceRef('target'), mid: new SpaceRef('mid'), world: new SpaceRef('world'), arena: new SpaceRef('arena') };
  const _a = new THREE.Vector3(), _b = new THREE.Vector3(), _c = new THREE.Vector3(), _o = new THREE.Vector3(), _o2 = new THREE.Vector3(), _w = new THREE.Vector3();

  const S = {
    active: false, shots: null, i: 0, t: 0, fresh: false, facing: 1, opts: null, handle: null,
    transition: null, ended: false, slowH: null, lbTouched: false, lbBefore: 0, gen: 0,
  };

  // ---- spaces ---------------------------------------------------------------------------------------------------
  function spaceOf(v, custom) {
    if (v == null) return null;
    if (typeof v === 'string') {
      if (!refs[v]) throw new Error('cam: unknown shot space "' + v + '"');
      return refs[v];
    }
    let r = custom.get(v);
    if (!r) { r = new SpaceRef('custom', v); custom.set(v, r); }
    return r;
  }

  /** Frame origin of a fighter frame: under the fighter on the floor (or lifted with it when followY). */
  function fighterPoint(ref, followY, out) {
    if (!readPoint(ref.src, out)) { out.set(0, 0, 0); return out; }
    out.y = followY ? Math.max(0, out.y - dir.fight.chestHeight) : 0;
    return out;
  }

  function sample(ref, followY, out) {
    if (ref.kind === 'custom') { if (!readPoint(ref.src, out)) out.set(0, 0, 0); return out; }
    return fighterPoint(ref, followY, out);
  }

  /**
   * At shot entry: snapshot every frame the shot uses (fighter frames on the floor) and reset their live trackers
   * (lifted with the fighter when followY), so following starts without catch-up.
   */
  function prime(n) {
    for (const r of n.refs) {
      if (r.kind === 'world' || r.kind === 'arena' || r.kind === 'mid') continue;
      sample(r, false, r.snap);
      r.live.reset(sample(r, n.followY, r.raw));
    }
  }

  function track(n, dt) {
    if (n.follow === 'none') return;
    for (const r of n.refs) {
      if (r.kind === 'world' || r.kind === 'arena' || r.kind === 'mid') continue;
      r.live.step(sample(r, n.followY, r.raw), n.followLag, dt);
    }
  }

  function origin(ref, live, out) {
    switch (ref.kind) {
      case 'world': case 'arena': return out.set(0, 0, 0);
      case 'mid': {
        const a = live ? refs.anchor.live.value : refs.anchor.snap, b = live ? refs.target.live.value : refs.target.snap;
        return out.addVectors(a, b).multiplyScalar(0.5);
      }
      default: return out.copy(live ? ref.live.value : ref.snap);
    }
  }

  /** local [f, u, s] in `ref` -> world. */
  function toWorld(local, ref, live, out) {
    if (ref.kind === 'world') return out.copy(local);
    origin(ref, live, out);
    out.x += local.x * S.facing;
    out.y += local.y;
    out.z += local.z;
    return out;
  }

  // ---- normalisation -------------------------------------------------------------------------------------------
  /**
   * One key. `from` keys take their spaces from the key, then the shot (default 'anchor'); `to` keys inherit anything
   * they omit from `from` (including the space of an inherited position / look).
   */
  function normKey(k, from, shot, custom) {
    const sp = k.space || shot.space || 'anchor';
    const lsp = k.lookSpace || shot.lookSpace || sp;
    if (!from) {
      return {
        pos: toV3(k.pos), look: toV3(k.look) || new THREE.Vector3(0, 1.3, 0),
        fov: k.fov ?? shot.fov ?? 40, roll: k.roll ?? shot.roll ?? 0,
        space: spaceOf(sp, custom), lookSpace: spaceOf(lsp, custom),
      };
    }
    return {
      pos: toV3(k.pos) || from.pos,
      look: toV3(k.look) || from.look,
      fov: k.fov ?? from.fov,
      roll: k.roll ?? from.roll,
      space: k.pos || k.space ? spaceOf(sp, custom) : from.space,
      lookSpace: k.look || k.lookSpace ? spaceOf(lsp, custom) : from.lookSpace,
    };
  }

  function normalize(shot, clockDefault, custom) {
    const n = {
      src: shot,
      dur: Math.max(0, shot.dur ?? 1),
      clock: shot.clock || clockDefault,
      cut: shot.cut === undefined || shot.cut === true || shot.cut === 0,
      blend: typeof shot.cut === 'number' ? shot.cut : 0.35,
      ease: resolveEase(shot.ease || 'inOutSine'),
      follow: shot.follow === true || shot.follow === 'all' ? 'all' : shot.follow === 'look' ? 'look' : 'none',
      followY: !!shot.followY,
      followLag: shot.followLag ?? 0.12,
      handheld: shot.handheld ?? 0,
      mirrorRoll: shot.space !== 'world',
      orbit: null, via: null, viaSpace: null,
      cues: [],
      refs: [],
    };
    n.lookEase = shot.lookEase ? resolveEase(shot.lookEase) : n.ease;
    n.fovEase = shot.fovEase ? resolveEase(shot.fovEase) : n.ease;
    n.from = normKey(shot.from || {}, null, shot, custom);
    n.to = shot.to ? normKey(shot.to, n.from, shot, custom) : n.from;
    if (shot.via) { n.via = toV3(shot.via); n.viaSpace = spaceOf(shot.viaSpace || shot.space || 'anchor', custom); }
    if (shot.orbit) {
      const o = shot.orbit;
      const [a0, a1] = pair(o.from ?? o.angle, 0), [r0, r1] = pair(o.radius, 5), [h0, h1] = pair(o.height, 1.6);
      n.orbit = { pivot: toV3(o.pivot) || new THREE.Vector3(0, 1.2, 0), space: spaceOf(o.space || shot.space || 'anchor', custom), a0: a0 * DEG, a1: (o.to ?? a1) * DEG, r0, r1, h0, h1 };
      if (!shot.from || !shot.from.look) { n.from.look = n.orbit.pivot; n.from.lookSpace = n.orbit.space; }
      if (!shot.to || !shot.to.look) { if (n.to === n.from) n.to = { ...n.from }; n.to.look = n.from.look; n.to.lookSpace = n.from.lookSpace; }
    }
    if (!n.from.pos && !n.orbit) n.from.pos = new THREE.Vector3(0, 1.6, 6);
    if (!n.to.pos) n.to.pos = n.from.pos;
    // cues
    for (const s of asList(shot.shake)) n.cues.push({ at: (typeof s === 'object' && s.at) || 0, type: 'shake', data: typeof s === 'number' ? { amount: s } : s, done: false });
    for (const k of asList(shot.kick)) n.cues.push({ at: k.at || 0, type: 'kick', data: k, done: false });
    if (shot.slowmo != null && shot.slowmo !== false) {
      const sm = typeof shot.slowmo === 'number' ? { scale: shot.slowmo } : shot.slowmo;
      n.cues.push({ at: sm.at || 0, type: 'slowmo', data: sm, done: false });
    }
    n.cues.sort((a, b) => a.at - b.at);
    // frames this shot reads (snapshotted at entry, tracked when following)
    const used = new Set([n.from.space, n.from.lookSpace, n.to.space, n.to.lookSpace]);
    if (n.viaSpace) used.add(n.viaSpace);
    if (n.orbit) used.add(n.orbit.space);
    if ([...used].some((r) => r.kind === 'mid')) { used.add(refs.anchor); used.add(refs.target); }
    n.refs = [...used].filter(Boolean);
    return n;
  }

  // ---- cues ----------------------------------------------------------------------------------------------------
  function mirrorDir(d, n, out) {
    if (!d) return null;
    if (Array.isArray(d)) out.set(d[0], d[1], d[2]); else out.copy(d);
    if (n.mirrorRoll) out.x *= S.facing;
    return out;
  }

  function fireCue(c, n) {
    const d = c.data;
    if (c.type === 'shake') {
      dir.shaker.shake(d.amount ?? 0.4, { ...d, dir: mirrorDir(d.dir, n, _w) });
    } else if (c.type === 'kick') {
      dir.shaker.kick({ ...d, roll: (d.roll || 0) * (n.mirrorRoll ? S.facing : 1), offset: mirrorDir(d.offset, n, _w) });
    } else if (c.type === 'slowmo') {
      const scale = clamp(d.scale ?? 0.4, 0.02, 1);
      const ei = d.easeIn ?? 0.08, eo = d.easeOut ?? 0.18;
      const span = Math.max(0.01, d.dur ?? n.dur - c.at);
      let real = span;
      if (n.clock === 'game') real = (span - (ei + eo) * (1 + scale) * 0.5) / scale + ei + eo;
      if (S.slowH) S.slowH.cancel();
      S.slowH = ctx.time.slowmo(scale, Math.max(real, ei + eo + 0.01), { easeIn: ei, easeOut: eo });
    }
  }

  function runCues(n) {
    for (const c of n.cues) if (!c.done && S.t >= c.at - 1e-9) { c.done = true; fireCue(c, n); }
  }

  // ---- shot flow -----------------------------------------------------------------------------------------------
  function enter(i) {
    const prev = S.shots[S.i];
    if (prev && i !== S.i && S.slowH) { S.slowH.cancel(); S.slowH = null; }
    S.i = i;
    const n = S.shots[i];
    for (const c of n.cues) c.done = false;
    prime(n);
    const lb = n.src.letterbox;
    if (lb !== undefined && lb !== null) {
      const v = typeof lb === 'object' ? lb.amount ?? 1 : lb === true ? 1 : lb === false ? 0 : lb;
      dir.letterboxTo(v, typeof lb === 'object' && lb.dur != null ? lb.dur : 0.3);
      S.lbTouched = true;
    }
    S.transition = n.cut ? { cut: true } : { cut: false, blend: n.blend, clock: n.clock };
    if (S.opts.onShot) S.opts.onShot(i, n.src);
  }

  /**
   * Start a sequence. Returns a handle (see director.play). `opts` already carries resolved anchor / target sources.
   */
  function play(shots, opts) {
    if (S.active) finish(false);
    const custom = new Map();
    S.gen++;
    S.opts = opts;
    refs.anchor.src = opts.anchor;
    refs.target.src = opts.target;
    S.shots = (Array.isArray(shots) ? shots : [shots]).map((s) => normalize(s, opts.clock || 'game', custom));
    S.facing = opts.facing;
    S.active = true;
    S.ended = false;
    S.lbTouched = false;
    S.lbBefore = dir.letterboxValue();
    S.slowH = null;
    S.t = 0;
    S.i = -1;
    enter(0);
    S.fresh = true;
    const gen = S.gen;
    S.handle = {
      /** Stop now and blend back to fight framing over `blend` seconds (0 = cut). */
      stop: (blend) => { if (S.gen === gen && S.active) dir.stop(blend ?? opts.blendOut ?? 0.35); },
      get done() { return S.gen !== gen || !S.active; },
      get index() { return S.gen === gen ? S.i : -1; },
      get time() { return S.gen === gen ? S.t : 0; },
    };
    return S.handle;
  }

  /** Advance and evaluate. Returns the pose, or null when inactive. */
  function update(dtGame, dtReal) {
    if (!S.active) return null;
    let n = S.shots[S.i];
    const fresh = S.fresh;
    S.fresh = false;
    if (!fresh) S.transition = null;
    if (!fresh && !S.ended) {
      S.t += n.clock === 'real' ? dtReal : dtGame;
      while (S.t >= n.dur && S.i < S.shots.length - 1) {
        const carry = S.t - n.dur;
        enter(S.i + 1);
        n = S.shots[S.i];
        S.t = Math.min(carry, n.dur);
      }
      if (S.t >= n.dur && S.i === S.shots.length - 1) { S.t = n.dur; S.ended = true; }
    }
    runCues(n);
    track(n, dtReal);
    evaluate(n, S.t);
    return pose;
  }

  function evaluate(n, t) {
    const u = n.dur > 0 ? clamp(t / n.dur) : 1;
    const e = n.ease(u), el = n.lookEase(u), ef = n.fovEase(u);
    const livePos = n.follow === 'all', liveLook = n.follow !== 'none';
    if (n.orbit) {
      const o = n.orbit;
      toWorld(o.pivot, o.space, livePos, _c);
      const a = lerp(o.a0, o.a1, e), r = lerp(o.r0, o.r1, e);
      const fs = o.space.kind === 'world' ? 1 : S.facing;
      origin(o.space, livePos, _o2);
      pose.pos.set(_c.x + Math.sin(a) * r * fs, _o2.y + lerp(o.h0, o.h1, e), _c.z + Math.cos(a) * r);
    } else {
      toWorld(n.from.pos, n.from.space, livePos, _a);
      toWorld(n.to.pos, n.to.space, livePos, _b);
      if (n.via) {
        toWorld(n.via, n.viaSpace, livePos, _c);
        const k = 1 - e;
        pose.pos.copy(_a).multiplyScalar(k * k).addScaledVector(_c, 2 * k * e).addScaledVector(_b, e * e);
      } else pose.pos.lerpVectors(_a, _b, e);
    }
    toWorld(n.from.look, n.from.lookSpace, liveLook, _a);
    toWorld(n.to.look, n.to.lookSpace, liveLook, _b);
    pose.look.lerpVectors(_a, _b, el);
    pose.fov = lerp(n.from.fov, n.to.fov, ef);
    pose.roll = lerp(n.from.roll, n.to.roll, e) * DEG * (n.mirrorRoll ? S.facing : 1);
  }

  /** End the sequence: cancel its slow-motion, restore the letterbox, notify. */
  function finish(completed, blend = 0.35) {
    if (!S.active) return;
    S.active = false;
    S.gen++;
    if (S.slowH) { S.slowH.cancel(); S.slowH = null; }
    const o = S.opts;
    if (S.lbTouched && !o.keepLetterbox) dir.letterboxTo(S.lbBefore, Math.max(0.3, blend));
    if (o.onDone) o.onDone(completed);
  }

  return {
    pose, play, update, finish,
    get active() { return S.active; },
    get ended() { return S.active && S.ended; },
    get transition() { return S.transition; },
    get index() { return S.active ? S.i : -1; },
    get shotTime() { return S.t; },
    get handheld() { return S.active && S.shots[S.i] ? S.shots[S.i].handheld : 0; },
    get opts() { return S.opts; },
  };
}
