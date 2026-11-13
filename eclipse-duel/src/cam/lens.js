// Cinematic lens: what a focus puller, an operator and a colourist add on top of a shot. The director calls
// lens.update() once per frame with the pre-shake pose; everything here runs on real time.
//
//   * depth of field   auto-focus on the shot's subject (the aim point, a fighter, both fighters, any point source or a
//                      fixed distance), aperture per shot type or from the framing tightness; focus distance, aperture
//                      and the sharp range are critically damped (a focus pull) and snap on hard cuts. Fighters near
//                      the focal plane widen the sharp range, so a two-shot never loses a fighter to the blur.
//   * focus breathing  the fov narrows / widens by up to 1.5 % while the focus racks, like a real lens
//   * tone hints       small additive exposure / vignette offsets per shot, plus an automatic lift at steep angles
//                      (low angles against the night sky, top-down views of the dark floor)
//   * motion blur      whip pans and crash zooms smear through the post radial blur (a far-away centre turns it into a
//                      directional blur); orbits and slow moves stay sharp (the blur follows the aim point's screen
//                      motion, not the background's)
//
// It owns nothing in the post pipeline: fx values are offset additively (someone else's tween / reset simply wins and
// the offset eases back in afterwards), post.dof is driven only while a cinematic shot asks for it and released after.
// No per-frame allocations, no draw calls of its own; the post passes it switches on are listed in README.md.

import * as THREE from 'three';
import { clamp, smoothstep, DEG } from '../core/math.js';
import { damp1, readPoint } from './pose.js';

/** Lens settings (`cam.lens.settings`, live). */
export const LENS_DEFAULTS = {
  enabled: true,      // master switch for everything below (#camfx=0)
  dof: 1,             // aperture scale 0..1.5 (0 = never touch post.dof)
  dofMin: 0.12,       // apertures below this are not worth the two half-res passes: DOF stays off
  dofMinMid: 0.45,    // on the mid tier only portrait-class shots (aperture >= this) pay for DOF
  autoGain: 0.5,      // aperture gain of shots without a `dof` field (hand-keyed shots)
  pull: 0.14,         // s: focus pull smooth time
  breathe: 1,         // focus breathing scale (1 = 3.5 % fov per e-fold of focus distance, capped at 1.5 %)
  tone: 1,            // exposure / vignette hint scale
  lift: 0.11,         // exposure added when the view looks up >= 28 deg (subject against the night sky)
  liftDown: 0.07,     // exposure added on near-vertical top-down views (dark floor)
  blur: 1,            // whip-pan / crash-zoom blur scale (0 = off)
  shutter: 0.9,       // blur length: screen motion during this many 1/60 s frames
  blurLen: 0.03,      // longest pan streak (fraction of the screen; zoom blur: about the same at the frame edge). The
                      // post radial blur has 10 jittered taps: longer streaks break HDR highlights into dots and bands
};

const TAN20 = Math.tan(20 * DEG);
const BLUR_REACH = 3;   // uv: how far off-screen the blur centre may go (directional blur)

/** An additive offset on one numeric post.fx key. */
class Layer {
  constructor(key) { this.key = key; this.on = false; this.base = 0; this.last = 0; this.s = { v: 0, vel: 0 }; }
}

/**
 * Put `L.s.v` on top of fx[key]. A value we did not write (someone's tween, post.reset, setBaseline) becomes the new
 * base and our offset restarts from zero, so it eases back in after their change instead of fighting or popping.
 */
function applyLayer(L, fx, target) {
  if (!L.on) {
    if (Math.abs(L.s.v) < 1e-4) return;
    L.on = true;
    L.base = fx[L.key];
  } else if (fx[L.key] !== L.last) {
    L.on = false; L.s.v = 0; L.s.vel = 0;
    return;
  }
  if (target === 0 && Math.abs(L.s.v) < 1e-4) { fx[L.key] = L.base; L.on = false; L.s.v = 0; L.s.vel = 0; return; }
  fx[L.key] = L.last = L.base + L.s.v;
}

/**
 * @param {object} ctx app context (ctx.post is read every frame, so the lens works without one)
 * @param {object} [settings] overrides of LENS_DEFAULTS
 */
export function createLens(ctx, settings = {}) {
  const S = { ...LENS_DEFAULTS, ...settings };
  const fwd = new THREE.Vector3(), right = new THREE.Vector3(), up = new THREE.Vector3(), v = new THREE.Vector3(), P = new THREE.Vector3();
  const prevPos = new THREE.Vector3(), prevLook = new THREE.Vector3();
  let prevDist = 6, prevTan = TAN20, prevValid = false;
  const lnF = { v: Math.log(6), vel: 0 }, lnSlow = { v: Math.log(6), vel: 0 };
  const ap = { v: 0, vel: 0 }, rg = { v: 0.9, vel: 0 }, cineW = { v: 0, vel: 0 };
  let near = 1, breatheK = 1, dofOwned = false, focusNow = 6, blurS = 0;
  const dofOpts = { focus: () => focusNow, aperture: 0, range: 0.6, near: 1 };
  const Lexp = new Layer('exposure'), Lvig = new Layer('vignette'), Lrad = new Layer('radial');
  const flow = { x: 0, y: 0, s: 0 };
  const centre = { on: false, x: 0.5, y: 0.5, lx: 0.5, ly: 0.5 };
  // per-frame scratch of the focus solve
  let pos0 = null, tanV = TAN20, tanH = TAN20 * 16 / 9;

  /** Live readout: what the lens is doing this frame. */
  const info = { focus: 6, aperture: 0, range: 0.9, near: 1, exposure: 0, vignette: 0, blur: 0, breathe: 0, dof: false };
  const out = { fovAdd: 0 };

  /** View depth (m along the view axis) of a point source; NaN when it is empty. */
  function depthOf(src) {
    if (!readPoint(src, P)) return NaN;
    return v.subVectors(P, pos0).dot(fwd);
  }
  /** Is the point last read by depthOf() inside the frame (generous: bodies are bigger than their chest point)? */
  function inFrame(d) {
    return d > 0.25 && Math.abs(v.dot(right)) < d * tanH * 1.15 && Math.abs(v.dot(up)) < d * tanV * 1.4;
  }

  /**
   * Advance the lens.
   * @param {number} dt real seconds
   * @param {boolean} cine a cinematic shot is on screen
   * @param {boolean} cut this frame is a hard cut
   * @param {object|null} sh the normalised shot (sequencer): reads sh.dof, sh.tone, sh.blur, sh.breathe
   * @param {{pos: THREE.Vector3, look: THREE.Vector3, fov: number}} pose pre-shake camera pose
   * @param {number} aspect viewport aspect
   * @param {*} anchorSrc point source of the sequence's anchor fighter (chest)
   * @param {*} targetSrc point source of the sequence's target fighter
   * @returns {{fovAdd: number}} degrees to add to the fov (focus breathing)
   */
  function update(dt, cine, cut, sh, pose, aspect, anchorSrc, targetSrc) {
    const post = ctx.post;
    const fx = post ? post.fx : null;
    const on = S.enabled && cine && !!sh;
    pos0 = pose.pos;
    fwd.subVectors(pose.look, pose.pos);
    const dLook = Math.max(1e-3, fwd.length());
    fwd.multiplyScalar(1 / dLook);
    if (Math.abs(fwd.y) > 0.985) right.set(1, 0, 0); else right.set(-fwd.z, 0, fwd.x).normalize();
    up.crossVectors(right, fwd);
    tanV = Math.tan(pose.fov * DEG * 0.5);
    tanH = tanV * Math.max(0.3, aspect);
    if (cut) { cineW.v = on ? 1 : 0; cineW.vel = 0; } else damp1(cineW, on ? 1 : 0, 0.25, dt);

    // ---- focus: distance, sharp range, aperture ----------------------------------------------------------------
    const spec = on ? sh.dof : null;
    let F = dLook, tAp = 0, tRg = 0.35 + 0.1 * dLook, pull = S.pull;
    if (spec) {
      let half = 0;
      if (spec.mode === 'dist') F = spec.dist;
      else if (spec.mode === 'point') { const d = depthOf(spec.ref ? spec.ref.src : spec.src); if (d === d) F = d; }
      else if (spec.mode === 'both') {
        const dA = depthOf(anchorSrc), dB = depthOf(targetSrc);
        if (dA === dA && dB === dB) { F = 0.5 * (dA + dB); half = 0.5 * Math.abs(dA - dB) + 0.45; }
      }
      F = clamp(F, 0.25, 300);
      tRg = Math.max(spec.range >= 0 ? spec.range : 0.35 + 0.1 * F, half);
      if (spec.protect) {
        // a fighter in frame and near the focal plane is part of the subject: keep it sharp
        const win = 0.3 * F + 0.5;
        let d = depthOf(anchorSrc);
        if (d === d && inFrame(d) && Math.abs(d - F) < win) tRg = Math.max(tRg, Math.abs(d - F) + 0.35);
        d = depthOf(targetSrc);
        if (d === d && inFrame(d) && Math.abs(d - F) < win) tRg = Math.max(tRg, Math.abs(d - F) + 0.35);
      }
      tAp = spec.aperture >= 0 ? spec.aperture : clamp((1.1 * (TAN20 / tanV) * 2.6) / F, 0, 1) * (spec.gain >= 0 ? spec.gain : S.autoGain);
      near = spec.near;
      if (spec.pull >= 0) pull = spec.pull;
      const tier = post && post.features ? post.features.dof | 0 : 0;
      tAp *= S.dof;
      if (tier === 0 || tAp < S.dofMin || (tier === 1 && tAp < S.dofMinMid)) tAp = 0;
    }
    const lf = Math.log(F);
    if (cut || !prevValid) {
      lnF.v = lnSlow.v = lf; lnF.vel = lnSlow.vel = 0;
      ap.v = tAp; ap.vel = 0;
      rg.v = tRg; rg.vel = 0;
    } else {
      damp1(lnF, lf, pull, dt);
      damp1(lnSlow, lnF.v, 0.9, dt);
      damp1(ap, tAp, tAp > ap.v ? 0.18 : on ? 0.25 : 0.14, dt);
      damp1(rg, tRg, 0.2, dt);
      if (tAp === 0 && ap.v < 0.02) { ap.v = 0; ap.vel = 0; }     // an invisible tail must not keep the DOF passes alive
    }
    focusNow = Math.exp(lnF.v);
    if (post && post.dof) {
      if (ap.v > 0.004 || tAp > 0) {
        dofOpts.aperture = ap.v; dofOpts.range = rg.v; dofOpts.near = near;
        post.dof(dofOpts, 0);
        dofOwned = true;
      } else if (dofOwned) {
        post.dof(null, 0);
        dofOwned = false; ap.v = 0; ap.vel = 0;
      }
    }

    // ---- focus breathing ---------------------------------------------------------------------------------------
    if (on) breatheK = sh.breathe;
    out.fovAdd = clamp(0.035 * (lnF.v - lnSlow.v), -0.015, 0.015) * pose.fov * S.breathe * breatheK * cineW.v;

    // ---- tone hints --------------------------------------------------------------------------------------------
    let tExp = 0, tVig = 0;
    const tone = on ? sh.tone : null;
    if (tone) {
      const pitch = Math.asin(clamp(fwd.y, -1, 1)) / DEG;
      const auto = tone.auto ? S.lift * smoothstep(4, 28, pitch) + S.liftDown * smoothstep(40, 80, -pitch) : 0;
      tExp = (auto + tone.exposure) * S.tone;
      tVig = tone.vignette * S.tone;
    }
    if (cut) { Lexp.s.v = tExp; Lexp.s.vel = 0; Lvig.s.v = tVig; Lvig.s.vel = 0; }
    else { damp1(Lexp.s, tExp, 0.3, dt); damp1(Lvig.s, tVig, 0.3, dt); }
    if (fx) { applyLayer(Lexp, fx, tExp); applyLayer(Lvig, fx, tVig); }

    // ---- whip-pan / crash-zoom blur ----------------------------------------------------------------------------
    let amt = 0, cx = 0.5, cy = 0.5;
    const blurK = on && fx && post.hdr !== false && ctx.quality && ctx.quality.tier !== 'low' ? S.blur * sh.blur : 0;
    if (blurK > 0 && !cut && prevValid && dt > 0) {
      // screen motion of the point the camera aimed at a frame ago, and the change of the subject's scale
      const d = v.subVectors(prevLook, pose.pos).dot(fwd);
      if (d > 0.2) {
        const inv = 1 / dt, k = 1 - Math.exp(-dt / 0.03);
        flow.x += ((v.dot(right) / (d * tanH)) * 0.5 * inv - flow.x) * k;
        flow.y += ((v.dot(up) / (d * tanV)) * 0.5 * inv - flow.y) * k;
        flow.s += (Math.log((prevDist * prevTan) / (dLook * tanV)) * inv - flow.s) * k;
      }
      const T = (S.shutter / 60) * blurK;
      const bl = Math.hypot(flow.x, flow.y) * T, sg = flow.s * T;
      const bl2 = Math.min(S.blurLen, Math.max(0, bl - 0.006)), sg2 = Math.min(1.6 * S.blurLen, Math.max(0, Math.abs(sg) - 0.02));
      const mag = Math.max(sg2, bl2 / BLUR_REACH);
      if (mag > 1e-5) {
        // flow field sigma * (p - p*): zoom about the screen centre plus a pan; the pan alone = a far-away centre
        const sgn = sg2 >= bl2 / BLUR_REACH && sg > 0 ? 1 : -1;
        const q = bl > 1e-6 ? (T * bl2) / (bl * sgn * mag) : 0;
        cx = 0.5 - flow.x * q; cy = 0.5 - flow.y * q;
        amt = mag / 0.35;
      }
    } else { flow.x = flow.y = flow.s = 0; }
    blurS = cut ? 0 : Math.max(amt, blurS * Math.exp(-dt / 0.04));
    if (blurS < 0.002) blurS = 0;
    if (fx) {
      if (blurS > 0 && amt > 0) {
        if (!centre.on) { centre.on = true; centre.x = fx.radialCenter.x; centre.y = fx.radialCenter.y; }
        fx.radialCenter.set(cx, cy);
        centre.lx = cx; centre.ly = cy;
      } else if (centre.on && blurS === 0) {
        centre.on = false;
        if (fx.radialCenter.x === centre.lx && fx.radialCenter.y === centre.ly) fx.radialCenter.set(centre.x, centre.y);
      }
      Lrad.s.v = blurS;
      applyLayer(Lrad, fx, blurS);
    }

    prevPos.copy(pose.pos); prevLook.copy(pose.look);
    prevDist = dLook; prevTan = tanV; prevValid = true;

    info.focus = focusNow; info.aperture = ap.v; info.range = rg.v; info.near = near;
    info.exposure = Lexp.on ? Lexp.s.v : 0; info.vignette = Lvig.on ? Lvig.s.v : 0;
    info.blur = Lrad.on ? blurS : 0; info.breathe = out.fovAdd;
    info.dof = dofOwned && ap.v > 0.005;
    return out;
  }

  /** Give everything back to the post pipeline now (dispose, mode switches). */
  function release() {
    const post = ctx.post;
    if (!post) return;
    const fx = post.fx;
    for (const L of [Lexp, Lvig, Lrad]) {
      if (L.on && fx[L.key] === L.last) fx[L.key] = L.base;
      L.on = false; L.s.v = 0; L.s.vel = 0;
    }
    if (centre.on) { centre.on = false; if (fx.radialCenter.x === centre.lx && fx.radialCenter.y === centre.ly) fx.radialCenter.set(centre.x, centre.y); }
    if (dofOwned && post.dof) { post.dof(null, 0); dofOwned = false; }
    ap.v = 0; ap.vel = 0; blurS = 0; prevValid = false;
  }

  return { settings: S, info, update, release };
}

/**
 * Normalise a shot's `dof` field (sequencer, once per shot).
 *   false / 0                 no depth of field on this shot
 *   undefined / true          auto: focus on the aim point, aperture from the framing tightness
 *   number                    aperture, auto focus
 *   { focus, aperture, gain, range, near, pull, protect }
 * focus: 'auto' | 'look' (the aim point) | 'anchor' | 'target' (that fighter's chest) | 'both' / 'mid' (both fighters
 * sharp) | metres | point source. `refOf(name)` maps 'anchor' / 'target' to the sequencer's frame (its live source).
 */
export function normDof(d, refOf) {
  if (d === false || d === 0 || d === null) return null;
  const o = typeof d === 'number' ? { aperture: d } : d && typeof d === 'object' ? d : {};
  const f = o.focus ?? 'auto';
  const spec = {
    mode: 'look', ref: null, src: null, dist: 0,
    aperture: typeof o.aperture === 'number' ? Math.max(0, o.aperture) : -1,
    gain: typeof o.gain === 'number' ? o.gain : -1,
    range: typeof o.range === 'number' ? o.range : -1,
    near: o.near ?? 1,
    pull: typeof o.pull === 'number' ? o.pull : -1,
    protect: o.protect !== false,
  };
  if (typeof f === 'number') { spec.mode = 'dist'; spec.dist = f; }
  else if (f === 'both' || f === 'mid') spec.mode = 'both';
  else if (f === 'anchor' || f === 'target') { spec.mode = 'point'; spec.ref = refOf(f); }
  else if (f !== 'auto' && f !== 'look' && f != null) { spec.mode = 'point'; spec.src = f; }
  return spec;
}

/**
 * Normalise a shot's `tone` field: false = none; number = exposure offset; { exposure, vignette, auto }.
 * Default: the automatic steep-angle lift only.
 */
export function normTone(t) {
  if (t === false || t === null) return null;
  const o = typeof t === 'number' ? { exposure: t } : t && typeof t === 'object' ? t : {};
  return { exposure: o.exposure ?? 0, vignette: o.vignette ?? 0, auto: o.auto !== false };
}
