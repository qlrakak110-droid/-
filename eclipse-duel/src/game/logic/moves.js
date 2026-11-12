// Pure helpers over compiled moves (see defs.js compileMove): motion sampling, timeline windows, boxes.

/**
 * Forward displacement (metres, fighter-local +f) accumulated from move start to move time `t`.
 * @param {object} mv compiled move
 * @param {number} t  move time (s)
 */
export function forwardAt(mv, t) {
  const m = mv.motion;
  if (!m) return 0;
  if (m.segs) {
    let d = 0;
    for (const s of m.segs) {
      if (t <= s.t0) continue;
      d += s.v * (Math.min(t, s.t1) - s.t0);
    }
    return d;
  }
  return sampleKeys(m.keys, t, 1);
}

/** Height (metres above the floor) the move puts the fighter at, or null when the motion has no height track. */
export function heightAt(mv, t) {
  const m = mv.motion;
  if (!m || !m.hasU) return null;
  return Math.max(0, sampleKeys(m.keys, t, 2));
}

function sampleKeys(keys, t, k) {
  const n = keys.length;
  if (t <= keys[0][0]) return keys[0][k] || 0;
  if (t >= keys[n - 1][0]) return keys[n - 1][k] || 0;
  let i = 1;
  while (i < n && keys[i][0] < t) i++;
  const a = keys[i - 1], b = keys[i];
  const span = b[0] - a[0];
  const u = span > 0 ? (t - a[0]) / span : 1;
  const va = a[k] || 0, vb = b[k] || 0;
  return va + (vb - va) * u;
}

/** First window {t0, t1, ...} of `list` containing time t (inclusive), or null. */
export function windowAt(list, t) {
  if (!list) return null;
  for (const w of list) if (t >= w.t0 && t <= w.t1) return w;
  return null;
}

/** True when the move-time interval (tPrev, tNow] touches the closed window [t0, t1]. */
export function crosses(t0, t1, tPrev, tNow) {
  return tNow >= t0 && tPrev < t1;
}

/**
 * Convert a fighter-local box to a world AABB.
 * @param {number} x origin x  @param {number} y origin y  @param {number} facing +1|-1
 * @param {number} f0 @param {number} f1 forward range  @param {number} u0 @param {number} u1 up range
 * @param {number[]} out [x0, x1, y0, y1]
 */
export function worldBox(x, y, facing, f0, f1, u0, u1, out) {
  if (facing >= 0) { out[0] = x + f0; out[1] = x + f1; } else { out[0] = x - f1; out[1] = x - f0; }
  out[2] = y + u0;
  out[3] = y + u1;
  return out;
}

/** AABB overlap test of two [x0, x1, y0, y1] boxes. */
export function overlaps(a, b) {
  return a[0] < b[1] && b[0] < a[1] && a[2] < b[3] && b[2] < a[3];
}

/** Centre of the overlap of two boxes (contact point). Writes into out = {x, y}. */
export function contactPoint(a, b, out) {
  out.x = (Math.max(a[0], b[0]) + Math.min(a[1], b[1])) * 0.5;
  out.y = (Math.max(a[2], b[2]) + Math.min(a[3], b[3])) * 0.5;
  return out;
}
