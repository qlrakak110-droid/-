// Fight framing: side-on two-shot that keeps both fighters in frame.
//
// Ideal framing is solved analytically from the two chest points each frame:
//   * vertical: the lowest feet sit on a "feet line" and a standing fighter's head on a "fill" line (fractions of the
//     frame height, letterbox-aware) under a separation-dependent down-tilt; a jump first spends the headroom up to
//     an "air line" (panning up a little), only then pulls back;
//   * horizontal: both fighters plus a side margin fit the frame width at the current aspect;
//   * distance = max(vertical, horizontal); fov / fill / feet line / tilt blend near -> mid -> far by separation, so
//     the camera pushes in on a clinch and pulls back as the fighters part.
// The ideal is smoothed with critically damped springs (fast pull-out, slow push-in, the aim leads the dolly for an
// operated feel). Walls computed from the two bodies (minimum distance, aim range, height range) keep both fully in
// frame: they shape the spring targets with a margin, so the springs steer clear of them smoothly; only motion faster
// than the lag (launches, teleports) reaches a wall, where the spring is clamped and keeps the wall's velocity
// (speed-limited) so it decelerates smoothly when the wall releases.

import { clamp, lerp, smoothstep, DEG } from '../core/math.js';
import { Pose, damp1 } from './pose.js';

/** Default fight framing parameters (`cam.fight`). Distances in metres, angles in degrees, lags in seconds. */
export function defaultFight() {
  return {
    near: { sep: 1.0, fov: 34, fill: 0.6, feet: 0.13, pitch: 4.5 },
    mid: { sep: 4.5, fov: 37, fill: 0.46, feet: 0.17, pitch: 6.5 },
    far: { sep: 10, fov: 40, fill: 0.36, feet: 0.2, pitch: 8.5 },
    air: { top: 0.8, feet: 0.08, pan: 2.0 },
    chestHeight: 1.35,
    headTop: 0.62,
    sideMargin: 1.15,
    edgePad: 0.04,
    bodyMargin: 0.55,
    hardTop: 0.5,
    hardPad: 0.03,
    hardPadTop: 0.1,
    wallMargin: 0.1,
    pushSpeed: 8,
    lead: 0.14,
    minDist: 3.2,
    maxDist: 24,
    parallax: 0.16,
    overscan: 1.6,
    camInset: 1.2,
    bounds: { minX: -9, maxX: 9 },
    aspectRef: 1.5,
    aspectFov: 16,
    breathe: 0.12,
    lag: { focus: 0.2, cam: 0.42, out: 0.16, in: 0.55, sep: 0.3, rise: 0.08, fall: 0.45, land: 0.08, lift: 0.25, pan: 0.35, panPush: 0.1, fov: 0.6 },
  };
}

/** Separation-dependent look: blends near -> mid -> far. */
function sepParam(P, key, d) {
  const k1 = smoothstep(P.near.sep, P.mid.sep, d), k2 = smoothstep(P.mid.sep, P.far.sep, d);
  return lerp(lerp(P.near[key], P.mid[key], k1), P.far[key], k2);
}

/** Angular span (rad) of the segment [xl, xr] on the fight plane seen from camera x `cx` at distance D. */
const span = (xl, xr, cx, D) => Math.atan((xr - cx) / D) - Math.atan((xl - cx) / D);

/** Smallest distance at which [xl, xr] seen from `cx` spans at most 2 * aH (bisection; span shrinks with distance). */
function fitDistance(xl, xr, cx, aH, D0) {
  if (span(xl, xr, cx, D0) <= 2 * aH) return D0;
  let a = D0, b = D0 * 2;
  while (span(xl, xr, cx, b) > 2 * aH && b < 1e3) b *= 2;
  for (let i = 0; i < 22; i++) { const m = 0.5 * (a + b); if (span(xl, xr, cx, m) > 2 * aH) a = m; else b = m; }
  return b;
}

export function createFightRig(P) {
  const S = {
    sep: { v: 5, vel: 0 }, top: { v: 1.97, vel: 0 }, low: { v: 0, vel: 0 }, fov: { v: 37, vel: 0 },
    dist: { v: 7, vel: 0 }, focus: { v: 0, vel: 0 }, camX: { v: 0, vel: 0 }, pan: { v: 0, vel: 0 },
  };
  const SPRINGS = Object.values(S);
  S.climb = { v: 0, vel: 0, last: 0 };
  const pose = new Pose();
  /** Live readout for debugging / labs (hardD / hardH / hardV: a wall clamped this frame). */
  const info = { dist: 0, focus: 0, camX: 0, height: 0, sep: 0, fov: 0, hardD: false, hardH: false, hardV: false };
  let primed = false;
  // per-frame context shared by the helpers below (no closures allocated per frame)
  let snap = false, dt = 0, tanV0 = 0, band0 = 1, pitch0 = 0, camX0 = 0, D0 = 1;

  /** Spring toward target (or jump to it on a snap). */
  function step(s, target, lag) {
    if (snap) { s.v = target; s.vel = 0; return target; }
    return damp1(s, target, lag, dt);
  }
  /** Clamp a spring onto a wall, keeping the velocity it just had (speed-limited). */
  function wall(s, value) {
    s.vel = snap ? 0 : clamp((value - s.prev) / Math.max(dt, 1e-4), -P.pushSpeed, P.pushSpeed);
    s.v = value;
  }
  /** tan of the angle below the horizon of the ray through frame-height fraction `frac` (0 bottom .. 1 top). */
  const tAt = (frac) => Math.tan(pitch0 + Math.atan(-(2 * frac - 1) * band0 * tanV0));
  /** Aim x on the fight plane for an aim angle `th` (rad) from the dolly. */
  const fAt = (th) => camX0 + D0 * Math.tan(clamp(th, -1.2, 1.2));

  /**
   * Advance the rig. A, B: chest points (Vector3). view: { aspect, letterbox (0..1), zoom (distance factor),
   * focusX, focusW (zoom focus point / weight), snap (jump straight to the ideal), scaleA, scaleB (body size of each
   * target relative to the 1.9 m reference: chest / head / width margins scale with it, e.g. 4.5 for a giant) }.
   */
  function update(dtReal, A, B, view) {
    snap = view.snap || !primed;
    primed = true;
    dt = dtReal;
    for (let i = 0; i < SPRINGS.length; i++) SPRINGS[i].prev = SPRINGS[i].v;
    const L = P.lag;
    const sA = view.scaleA || 1, sB = view.scaleB || 1, sMax = Math.max(sA, sB);
    // soft extent (side margins) and body extent (walls) along the fight line, per target size
    const softL = Math.min(A.x - P.sideMargin * sA, B.x - P.sideMargin * sB), softR = Math.max(A.x + P.sideMargin * sA, B.x + P.sideMargin * sB);
    const bl = Math.min(A.x - P.bodyMargin * sA, B.x - P.bodyMargin * sB), br = Math.max(A.x + P.bodyMargin * sA, B.x + P.bodyMargin * sB);
    const sep = Math.abs(A.x - B.x) / sMax, mid = 0.5 * (softL + softR);
    const zPlane = 0.5 * (A.z + B.z);
    const lowFeet = Math.max(0, Math.min(A.y - P.chestHeight * sA, B.y - P.chestHeight * sB));
    const top = Math.max(A.y + P.headTop * sA, B.y + P.headTop * sB);
    const aspect = Math.max(0.3, view.aspect);
    const band = 1 - 2 * 0.115 * clamp(view.letterbox || 0);
    const zoom = view.zoom || 1;
    const m = P.wallMargin;

    // ---- smoothed inputs and separation-dependent look ----
    const dS = step(S.sep, sep, L.sep);
    // rising fighters are led by their (smoothed) climb rate so a launch is anticipated rather than chased
    if (!snap && dt > 0) damp1(S.climb, (top - S.climb.last) / dt, 0.09, dt); else S.climb.v = 0;
    S.climb.last = top;
    const lead = Math.max(0, S.climb.v) * P.lead;
    const topS = step(S.top, top + lead, top + lead > S.top.v ? L.rise : L.fall);
    const lowS = step(S.low, lowFeet, lowFeet > S.low.v ? L.lift : L.land);
    const fov = step(S.fov, clamp(sepParam(P, 'fov', dS) + Math.max(0, P.aspectRef - aspect) * P.aspectFov, 10, 75), L.fov);
    const fill = sepParam(P, 'fill', dS), pitch = sepParam(P, 'pitch', dS) * DEG;
    const tanV = Math.tan(fov * DEG * 0.5), tanH = tanV * aspect;
    const standTop = (P.chestHeight + P.headTop) * sMax;
    const feet0 = sepParam(P, 'feet', dS);
    const feet = lerp(feet0, Math.min(feet0, P.air.feet), smoothstep(0, P.air.pan, Math.max(0, topS - lowS - standTop)));
    tanV0 = tanV; band0 = band; pitch0 = pitch;
    const tF = tAt(feet);

    // ---- walls from the two bodies ----
    const aV = Math.atan(band * (1 - P.hardPad) * tanV), aT = Math.atan(band * (1 - P.hardPadTop) * tanV);
    const aH = Math.atan((1 - P.hardPad) * tanH * Math.cos(pitch));
    const lowY = lowFeet - 0.04, highY = Math.max(A.y + P.hardTop * sA, B.y + P.hardTop * sB);
    const Dv = Math.max(standTop / Math.max(1e-3, tF - tAt(feet + fill)), (topS - lowS) / Math.max(1e-3, tF - tAt(Math.max(feet + fill, P.air.top))));
    const Dh = (0.5 * (softR - softL)) / ((1 - P.edgePad) * tanH * Math.cos(pitch));
    const Dideal = clamp(Math.max(Dv, Dh), P.minDist, P.maxDist);
    // ideal aim: the midpoint, held back so the frame does not run far past the arena walls, pulled by zoom focus
    const Wv = Dideal * zoom * tanH;
    const lo = P.bounds.minX - P.overscan + Wv, hi = P.bounds.maxX + P.overscan - Wv;
    let fx = lo <= hi ? clamp(mid, lo, hi) : 0.5 * (lo + hi);
    if (view.focusW > 0) fx = lerp(fx, view.focusX, view.focusW);
    // the dolly trails the aim toward the arena centre (parallax yaw toward the fighters)
    const camX = step(S.camX, clamp((snap ? fx : S.focus.v) * (1 - P.parallax), P.bounds.minX + P.camInset, P.bounds.maxX - P.camInset), L.cam);
    const wallD = fitDistance(bl, br, camX, aH, (highY - lowY) / (Math.tan(aT - pitch) + Math.tan(aV + pitch)));

    // ---- distance ----
    const Dtarget = Math.max(Dideal, (wallD * (1 + m)) / zoom);
    step(S.dist, Dtarget, Dtarget > S.dist.v ? L.out : L.in);
    info.hardD = S.dist.v * zoom < wallD;
    if (info.hardD) wall(S.dist, wallD / zoom);
    const D = S.dist.v * zoom;

    // ---- aim (focus) ----
    const thLo = Math.atan((br - camX) / D) - aH, thHi = Math.atan((bl - camX) / D) + aH;
    camX0 = camX; D0 = D;
    const mth = Math.min(m * aH, 0.5 * Math.max(0, thHi - thLo));
    step(S.focus, thLo <= thHi ? clamp(fx, fAt(thLo + mth), fAt(thHi - mth)) : fAt(0.5 * (thLo + thHi)), L.focus);
    const fLo = fAt(thLo), fHi = fAt(thHi);
    info.hardH = fLo <= fHi && (S.focus.v < fLo || S.focus.v > fHi);
    if (info.hardH) wall(S.focus, S.focus.v < fLo ? fLo : fHi);
    const focus = S.focus.v;

    // ---- height: floor on the feet line, plus a pan the walls push (relaxing back to zero) ----
    const hBase = lowS + D * tF;
    const hcMin = highY - D * Math.tan(aT - pitch), hcMax = lowY + D * Math.tan(aV + pitch);
    const mh = Math.min(m * D * tanV, 0.5 * Math.max(0, hcMax - hcMin));
    const panTarget = hcMin <= hcMax ? clamp(0, hcMin + mh - hBase, hcMax - mh - hBase) : 0.5 * (hcMin + hcMax) - hBase;
    step(S.pan, panTarget, Math.abs(panTarget) > Math.abs(S.pan.v) ? L.panPush : L.pan);
    info.hardV = hcMin <= hcMax && (hBase + S.pan.v < hcMin || hBase + S.pan.v > hcMax);
    if (info.hardV) wall(S.pan, (hBase + S.pan.v < hcMin ? hcMin : hcMax) - hBase);
    const hc = hBase + S.pan.v;

    pose.pos.set(camX, hc, zPlane + D);
    pose.look.set(focus, hc - D * Math.tan(pitch), zPlane);
    pose.fov = fov;
    pose.roll = 0;
    info.dist = D; info.focus = focus; info.camX = camX; info.height = hc; info.sep = sep * sMax; info.fov = fov;
    return pose;
  }

  return { pose, info, update };
}
