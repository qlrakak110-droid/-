// Small yaw / plane helpers of the RPG mode. Convention (README §2): yaw is a rotation about +Y, yaw 0 faces +X,
// forward F = (cos yaw, 0, -sin yaw), right R = (sin yaw, 0, cos yaw) — the same thing as `root.rotation.y = yaw` on a
// character whose model forward is +X.

export const TAU = Math.PI * 2;
export const DEG = Math.PI / 180;
/** Fixed simulation step (s). */
export const STEP = 1 / 60;

/** Yaw of the world direction (dx, dz). */
export const yawTo = (dx, dz) => Math.atan2(-dz, dx);
/** Forward x / z of a yaw. */
export const fwdX = (yaw) => Math.cos(yaw);
export const fwdZ = (yaw) => -Math.sin(yaw);
/** Right x / z of a yaw. */
export const rightX = (yaw) => Math.sin(yaw);
export const rightZ = (yaw) => Math.cos(yaw);

/** Wrap an angle to (-PI, PI]. */
export function wrapPi(a) {
  a = (a + Math.PI) % TAU;
  if (a < 0) a += TAU;
  return a - Math.PI;
}
/** Shortest signed difference b - a in (-PI, PI]. */
export const angDiff = (a, b) => wrapPi(b - a);
/** Move `yaw` toward `target` by at most `maxStep` radians. */
export function turnToward(yaw, target, maxStep) {
  const d = wrapPi(target - yaw);
  if (Math.abs(d) <= maxStep) return target;
  return wrapPi(yaw + Math.sign(d) * maxStep);
}
export const clamp = (x, a = 0, b = 1) => (x < a ? a : x > b ? b : x);
export const lerp = (a, b, t) => a + (b - a) * t;
/** Interpolate an angle along the shortest arc. */
export const lerpAngle = (a, b, t) => a + wrapPi(b - a) * t;
/** Frame-rate independent exponential approach factor. */
export const dampK = (lambda, dt) => 1 - Math.exp(-lambda * dt);
export const hypot2 = (x, z) => Math.sqrt(x * x + z * z);

/** Time tolerance of every timeline comparison (clocks accumulate 1/60 steps). */
export const EPS = 1e-6;
/** True when the interval (tPrev, tNow] touches the window [t0, t1]. */
export const crosses = (t0, t1, tPrev, tNow) => tNow >= t0 - EPS && tPrev < t1 - EPS;
/** True when the instant t lies in (tPrev, tNow]. */
export const passes = (t, tPrev, tNow) => t > tPrev + EPS && t <= tNow + EPS;
