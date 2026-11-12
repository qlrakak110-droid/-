// Fight framing: side-on two-shot that keeps both fighters in frame.
//
// Ideal framing is solved analytically from the two chest points each frame:
//   * vertical: the lowest feet sit on a "feet line" and the highest head on a "fill" line (fractions of the frame
//     height, letterbox-aware), with a separation-dependent down-tilt -> distance Dv and camera height;
//   * horizontal: both fighters plus a side margin fit the frame width at the current aspect -> distance Dh;
//   * distance = max(Dv, Dh); fov / fill / feet line / tilt are interpolated near -> mid -> far by separation, so the
//     camera pushes in on a clinch and pulls back as the fighters part.
// The ideal is then smoothed with critically damped springs (fast pull-out, slower push-in, the look leads the dolly
// for an operated feel) and finally a hard pass guarantees both bodies stay inside the frame whatever the lag.

import { clamp, lerp, smoothstep, DEG } from '../core/math.js';
import { Pose, damp1, softFloor } from './pose.js';

const softCeil = (v, max, knee) => -softFloor(-v, -max, knee);

/** Default fight framing parameters (`cam.fight`). Distances in metres, angles in degrees, lags in seconds. */
export function defaultFight() {
  return {
    near: { sep: 1.0, fov: 34, fill: 0.6, feet: 0.13, pitch: 4.5 },
    mid: { sep: 4.5, fov: 37, fill: 0.46, feet: 0.17, pitch: 6.5 },
    far: { sep: 10, fov: 40, fill: 0.36, feet: 0.2, pitch: 8.5 },
    chestHeight: 1.35,
    headTop: 0.62,
    sideMargin: 1.15,
    edgePad: 0.04,
    bodyMargin: 0.55,
    hardTop: 0.5,
    air: { top: 0.8, feet: 0.08, pan: 2.0 },
    hardPad: 0.03,
    hardPadTop: 0.1,
    hardKnee: 0.12,
    pushSpeed: 8,
    minDist: 3.2,
    maxDist: 24,
    parallax: 0.16,
    overscan: 1.6,
    camInset: 1.2,
    bounds: { minX: -9, maxX: 9 },
    aspectRef: 1.5,
    aspectFov: 16,
    breathe: 0.12,
    lag: { focus: 0.2, cam: 0.42, out: 0.16, in: 0.55, sep: 0.3, rise: 0.08, fall: 0.45, land: 0.08, lift: 0.25, pan: 0.35, fov: 0.6 },
  };
}

/** Separation-dependent look: blends near -> mid -> far. */
function sepParam(P, key, d) {
  const k1 = smoothstep(P.near.sep, P.mid.sep, d), k2 = smoothstep(P.mid.sep, P.far.sep, d);
  return lerp(lerp(P.near[key], P.mid[key], k1), P.far[key], k2);
}

/** Angular span (rad) of the segment [xl, xr] on the fight plane seen from camera x `cx` at distance D. */
const span = (xl, xr, cx, D) => Math.atan((xr - cx) / D) - Math.atan((xl - cx) / D);

export function createFightRig(P) {
  const S = {
    sep: { v: 5, vel: 0 }, top: { v: 1.97, vel: 0 }, low: { v: 0, vel: 0 }, fov: { v: 37, vel: 0 },
    dist: { v: 7, vel: 0 }, focus: { v: 0, vel: 0 }, camX: { v: 0, vel: 0 }, pan: { v: 0, vel: 0 },
  };
  const prev = { D: 7, focus: 0, pan: 0 };
  const pose = new Pose();
  /** Live readout for debugging / labs. */
  const info = { dist: 0, focus: 0, camX: 0, height: 0, sep: 0, fov: 0, hardD: false, hardH: false, hardV: false };
  let primed = false;

  /**
   * Advance the rig. A, B: chest points (Vector3). view: { aspect, letterbox (0..1), zoom (distance factor),
   * focusX, focusW (zoom focus point / weight), snap (jump straight to the ideal) }.
   */
  function update(dt, A, B, view) {
    const snap = view.snap || !primed;
    primed = true;
    const step = (s, target, lag) => (snap ? ((s.v = target), (s.vel = 0), target) : damp1(s, target, lag, dt));
    const L = P.lag;
    const xL = Math.min(A.x, B.x), xR = Math.max(A.x, B.x);
    const sep = xR - xL, mid = 0.5 * (xL + xR);
    const zPlane = 0.5 * (A.z + B.z);
    const hiChest = Math.max(A.y, B.y), loChest = Math.min(A.y, B.y);
    const lowFeet = Math.max(0, loChest - P.chestHeight);
    const top = hiChest + P.headTop;
    const aspect = Math.max(0.3, view.aspect);
    const band = 1 - 2 * 0.115 * clamp(view.letterbox || 0);

    const dS = step(S.sep, sep, L.sep);
    const topS = step(S.top, top, top > S.top.v ? L.rise : L.fall);
    const lowS = step(S.low, lowFeet, lowFeet > S.low.v ? L.lift : L.land);

    const fovIdeal = clamp(sepParam(P, 'fov', dS) + Math.max(0, P.aspectRef - aspect) * P.aspectFov, 10, 75);
    const fov = step(S.fov, fovIdeal, L.fov);
    const fill = sepParam(P, 'fill', dS), pitch = sepParam(P, 'pitch', dS) * DEG;
    const tanV = Math.tan(fov * DEG * 0.5), tanH = tanV * aspect;
    // a jump first spends the headroom (and pans up a little by lowering the feet line), only then pulls back
    const standTop = P.chestHeight + P.headTop;
    const lift = Math.max(0, topS - lowS - standTop);
    const feet0 = sepParam(P, 'feet', dS);
    const feet = lerp(feet0, Math.min(feet0, P.air.feet), smoothstep(0, P.air.pan, lift));

    // ideal distance: vertical (standing size, airborne span under the air line) vs horizontal (side margins)
    const ndc = (frac) => (2 * frac - 1) * band;
    const tAt = (frac) => Math.tan(pitch + Math.atan(-ndc(frac) * tanV));
    const tF = tAt(feet);
    const Dv = Math.max(standTop / Math.max(1e-3, tF - tAt(feet + fill)), (topS - lowS) / Math.max(1e-3, tF - tAt(Math.max(feet + fill, P.air.top))));
    const Dh = (sep * 0.5 + P.sideMargin) / ((1 - P.edgePad) * tanH * Math.cos(pitch));
    const Dideal = clamp(Math.max(Dv, Dh), P.minDist, P.maxDist);
    const Dsoft = step(S.dist, Dideal, Dideal > S.dist.v ? L.out : L.in);
    const zoom = view.zoom || 1;
    let D = Dsoft * zoom;

    // ideal focus: the midpoint, held back so the frame does not run far past the arena walls, pulled by zoom focus
    const Wv = D * tanH;
    const lo = P.bounds.minX - P.overscan + Wv, hi = P.bounds.maxX + P.overscan - Wv;
    let fx = lo <= hi ? clamp(mid, lo, hi) : 0.5 * (lo + hi);
    if (view.focusW > 0) fx = lerp(fx, view.focusX, view.focusW);
    const focusSoft = step(S.focus, fx, L.focus);
    const camXIdeal = clamp(focusSoft * (1 - P.parallax), P.bounds.minX + P.camInset, P.bounds.maxX - P.camInset);
    const camX = step(S.camX, camXIdeal, L.cam);

    // ---- hard pass: both bodies always inside the frame ----
    // Walls (minimum distance, aim range, height range) come from the bodies with a small pad. Output values ease onto
    // a wall through a soft knee (C1, never past it). When a spring itself ends up past a wall it is moved onto the
    // wall with the velocity it just had (speed-limited), so releasing a wall decelerates smoothly instead of snapping.
    const aV = Math.atan(band * (1 - P.hardPad) * tanV), aT = Math.atan(band * (1 - P.hardPadTop) * tanV);
    const aH = Math.atan((1 - P.hardPad) * tanH * Math.cos(pitch));
    const lowY = lowFeet - 0.04, highY = hiChest + P.hardTop;
    const kn = P.hardKnee, vmax = P.pushSpeed;
    const pushTo = (s, wall, prevValue) => { s.vel = snap ? 0 : clamp((wall - prevValue) / dt, -vmax, vmax); s.v = wall; };
    const bl = xL - P.bodyMargin, br = xR + P.bodyMargin;
    let wallD = (highY - lowY) / (Math.tan(aT - pitch) + Math.tan(aV + pitch));
    if (span(bl, br, camX, wallD) > 2 * aH) {
      let a = wallD, b = wallD * 2;
      while (span(bl, br, camX, b) > 2 * aH && b < 1e3) b *= 2;
      for (let i = 0; i < 22; i++) { const m = 0.5 * (a + b); if (span(bl, br, camX, m) > 2 * aH) a = m; else b = m; }
      wallD = b;
    }
    info.hardD = S.dist.v * zoom < wallD;
    if (info.hardD) pushTo(S.dist, wallD / zoom, prev.D);
    D = softFloor(S.dist.v * zoom, wallD, kn * wallD);

    const thLo = Math.atan((br - camX) / D) - aH, thHi = Math.atan((bl - camX) / D) + aH;
    const fLo = camX + D * Math.tan(thLo), fHi = camX + D * Math.tan(thHi);
    info.hardH = S.focus.v < fLo || S.focus.v > fHi;
    if (fLo <= fHi && info.hardH) pushTo(S.focus, S.focus.v < fLo ? fLo : fHi, prev.focus);
    const thSoft = Math.atan((S.focus.v - camX) / D);
    const kth = Math.min(kn * aH, 0.5 * Math.max(0, thHi - thLo));
    const th = thLo <= thHi ? softCeil(softFloor(thSoft, thLo, kth), thHi, kth) : 0.5 * (thLo + thHi);
    const focus = camX + D * Math.tan(th);

    // camera height: floor (lowest feet) on the feet line plus a pan offset (pushed by the walls, relaxing to zero)
    step(S.pan, 0, L.pan);
    const hBase = lowS + D * tF;
    const hcMin = highY - D * Math.tan(aT - pitch), hcMax = lowY + D * Math.tan(aV + pitch);
    info.hardV = hBase + S.pan.v < hcMin || hBase + S.pan.v > hcMax;
    if (hcMin <= hcMax && info.hardV) pushTo(S.pan, (hBase + S.pan.v < hcMin ? hcMin : hcMax) - hBase, prev.pan);
    const kh = Math.min(kn * D * tanV, 0.5 * Math.max(0, hcMax - hcMin));
    const hc = softCeil(softFloor(hBase + S.pan.v, hcMin, kh), hcMax, kh);
    prev.D = S.dist.v; prev.focus = S.focus.v; prev.pan = S.pan.v;

    pose.pos.set(camX, hc, zPlane + D);
    pose.look.set(focus, hc - D * Math.tan(pitch), zPlane);
    pose.fov = fov;
    pose.roll = 0;
    info.dist = D; info.focus = focus; info.camX = camX; info.height = hc; info.sep = sep; info.fov = fov;
    return pose;
  }

  return { pose, info, update };
}
