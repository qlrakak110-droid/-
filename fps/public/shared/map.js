// Shared between server (hit detection, spawns) and client (rendering, collision).

export const ARENA = 44; // half-size of the playable square

export const PLAYER = {
  radius: 0.38,
  height: 1.8,
  eye: 1.62,
  walk: 6.2,
  sprint: 9.2,
  ads: 3.6,
  jump: 7.6,
  gravity: 22,
  step: 0.55,
  maxHp: 100,
};

// Every player carries a primary (chosen in the menu) and the pistol.
// spread values are cone radii in radians; recoil is permanent pitch climb per shot.
export const WEAPONS = [
  {
    id: 'ar', name: 'AR-7 돌격소총', short: 'AR-7', auto: true, fireMs: 95, mag: 30, reloadMs: 2000,
    body: 26, head: 68, falloffDist: 35, falloff: 0.75,
    spread: 0.0025, bloom: 0.0045, maxBloom: 0.028, moveSpread: 0.024, adsMul: 0.35,
    recoil: 0.0065, punch: 0.018, adsFov: 56, speed: 1, loud: 1,
  },
  {
    id: 'smg', name: 'VX-9 기관단총', short: 'VX-9', auto: true, fireMs: 64, mag: 35, reloadMs: 1700,
    body: 18, head: 40, falloffDist: 20, falloff: 0.6,
    spread: 0.006, bloom: 0.004, maxBloom: 0.032, moveSpread: 0.01, adsMul: 0.5,
    recoil: 0.0042, punch: 0.012, adsFov: 62, speed: 1.08, loud: 0.8,
  },
  {
    id: 'sniper', name: 'K-14 저격소총', short: 'K-14', auto: false, fireMs: 1150, mag: 5, reloadMs: 2800,
    body: 90, head: 200, falloffDist: 999, falloff: 1,
    spread: 0.05, bloom: 0, maxBloom: 0, moveSpread: 0.06, adsMul: 0.02,
    recoil: 0.035, punch: 0.07, adsFov: 20, scope: true, speed: 0.9, loud: 1.4,
  },
  {
    id: 'pistol', name: 'P-22 권총', short: 'P-22', auto: false, fireMs: 165, mag: 12, reloadMs: 1400,
    body: 30, head: 75, falloffDist: 25, falloff: 0.7,
    spread: 0.004, bloom: 0.009, maxBloom: 0.03, moveSpread: 0.012, adsMul: 0.5,
    recoil: 0.012, punch: 0.026, adsFov: 66, speed: 1.1, loud: 0.7,
  },
];
export const PRIMARIES = [0, 1, 2];
export const PISTOL = 3;
export const RANGE = 250;

export const BOXES = [];

const add = (x0, y0, z0, x1, y1, z1, kind, tint) =>
  BOXES.push({
    min: [Math.min(x0, x1), y0, Math.min(z0, z1)],
    max: [Math.max(x0, x1), y1, Math.max(z0, z1)],
    kind,
    tint,
  });

const block = (cx, cz, w, d, h, kind, y = 0, tint) =>
  add(cx - w / 2, y, cz - d / 2, cx + w / 2, y + h, cz + d / 2, kind, tint);

// --- outer walls ---
{
  const T = 1, H = 7, A = ARENA;
  add(-A - T, 0, -A - T, A + T, H, -A, 'wall');
  add(-A - T, 0, A, A + T, H, A + T, 'wall');
  add(-A - T, 0, -A, -A, H, A, 'wall');
  add(A, 0, -A, A + T, H, A, 'wall');
}

// --- central tower with stairs north & south ---
block(0, 0, 10, 10, 3, 'concrete');
for (let i = 0; i < 5; i++) {
  const h = 0.5 * (i + 1);
  block(0, -9.5 + i, 3, 1, h, 'concrete');
  block(0, 9.5 - i, 3, 1, h, 'concrete');
}
block(-4.8, 0, 0.4, 10, 1, 'concrete', 3);
block(4.8, 0, 0.4, 10, 1, 'concrete', 3);
for (const z of [-4.8, 4.8]) {
  block(-3.25, z, 3.5, 0.4, 1, 'concrete', 3);
  block(3.25, z, 3.5, 0.4, 1, 'concrete', 3);
}

// --- corner rooms (open roof, doorways with lintels) ---
function room(cx, cz, s, h, doors) {
  const t = 0.5, hs = s / 2, g = 1.3, lintel = 2.7;
  const wallX = (z, door) => {
    if (!door) return add(cx - hs, 0, z - t / 2, cx + hs, h, z + t / 2, 'wall');
    add(cx - hs, 0, z - t / 2, cx - g, h, z + t / 2, 'wall');
    add(cx + g, 0, z - t / 2, cx + hs, h, z + t / 2, 'wall');
    add(cx - g, lintel, z - t / 2, cx + g, h, z + t / 2, 'wall');
  };
  const wallZ = (x, door) => {
    if (!door) return add(x - t / 2, 0, cz - hs + t / 2, x + t / 2, h, cz + hs - t / 2, 'wall');
    add(x - t / 2, 0, cz - hs + t / 2, x + t / 2, h, cz - g, 'wall');
    add(x - t / 2, 0, cz + g, x + t / 2, h, cz + hs - t / 2, 'wall');
    add(x - t / 2, lintel, cz - g, x + t / 2, h, cz + g, 'wall');
  };
  wallX(cz - hs, doors.includes('n'));
  wallX(cz + hs, doors.includes('s'));
  wallZ(cx - hs, doors.includes('w'));
  wallZ(cx + hs, doors.includes('e'));
}
room(30, 30, 12, 4.5, 'nw');
room(-30, -30, 12, 4.5, 'se');
room(30, -30, 12, 4.5, 'sw');
room(-30, 30, 12, 4.5, 'ne');

// --- mid cover walls & pillars ---
block(0, -22, 12, 0.8, 2.4, 'concrete');
block(0, 22, 12, 0.8, 2.4, 'concrete');
block(-22, 0, 0.8, 12, 2.4, 'concrete');
block(22, 0, 0.8, 12, 2.4, 'concrete');
for (const [x, z] of [[12, 12], [-12, 12], [12, -12], [-12, -12]]) block(x, z, 1.2, 1.2, 5, 'concrete');

// --- containers (climbable via the crate next to them) ---
const CONTAINERS = [
  [-14, -30, 6, 2.6, 0xb5442f], [14, 30, 6, 2.6, 0x2f6bb5],
  [-30, 12, 2.6, 6, 0x3f8a4a], [30, -12, 2.6, 6, 0xd08a2a],
];
for (const [x, z, w, d, tint] of CONTAINERS) block(x, z, w, d, 2.5, 'container', 0, tint);

// --- crates, placed point-symmetric so neither side is favoured ---
const CRATES = [
  [-10.4, -30, 1.25], [-31.2, 8, 1.25], // step-ups next to containers
  [8, -14, 1.6], [9.4, -14.2, 1.25], [-18, -8, 1.6], [-18, -6.4, 1.25],
  [26, -2, 1.6], [6, -34, 1.6], [7.6, -34.2, 1.25], [7, -34, 1.25, 1.6],
  [-38, -14, 1.6], [-36.5, -14, 1.25], [18, -40, 1.6], [-3, -30, 1.25],
  [30, -30, 1.6], // inside rooms
];
for (const [x, z, s, y = 0] of CRATES) {
  block(x, z, s, s, s, 'crate', y);
  block(-x, -z, s, s, s, 'crate', y);
}

// Barrels and sandbag walls (collidable props).
const PROPS = [
  ['barrel', -17.7, -27.6], ['barrel', -16.9, -27.3], ['barrel', 32.1, -9.2],
  ['barrel', -42.9, -20.5], ['barrel', -42.9, -19.6], ['barrel', 24.9, -24.9],
];
for (const [kind, x, z] of PROPS) {
  block(x, z, 0.62, 0.62, 0.92, kind);
  block(-x, -z, 0.62, 0.62, 0.92, kind);
}
for (const [x, z, w, d] of [[8, -26.5, 4, 1], [-26.5, 8, 1, 4], [-36, -4, 1, 3]]) {
  block(x, z, w, d, 0.9, 'sandbag');
  block(-x, -z, w, d, 0.9, 'sandbag');
}

export const SPAWNS = [
  [-40, -40], [40, 40], [-40, 40], [40, -40],
  [0, -40], [0, 40], [-40, 0], [40, 0],
  [-20, -38], [20, 38], [-38, 20], [38, -20],
  [27, 33], [-27, -33], [33, -27], [-33, 27],
].map(([x, z]) => ({ x, y: 0, z, yaw: Math.atan2(x, z) }));

// --- geometry helpers ---

/** Slab test. Returns {t, axis, sign} (sign is the hit face normal along axis) or null. */
export function rayAABB(o, d, min, max) {
  let tmin = 0, tmax = Infinity, axis = -1, sign = 0;
  for (let i = 0; i < 3; i++) {
    if (Math.abs(d[i]) < 1e-9) {
      if (o[i] < min[i] || o[i] > max[i]) return null;
      continue;
    }
    const inv = 1 / d[i];
    let t1 = (min[i] - o[i]) * inv, t2 = (max[i] - o[i]) * inv, s = -1;
    if (t1 > t2) { const tmp = t1; t1 = t2; t2 = tmp; s = 1; }
    if (t1 > tmin) { tmin = t1; axis = i; sign = s; }
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax) return null;
  }
  return { t: tmin, axis, sign };
}

/** Nearest hit against floor + map boxes within maxT. Returns {t, n} or null. */
export function raycastMap(o, d, maxT = RANGE) {
  let best = null;
  if (d[1] < 0) {
    const t = -o[1] / d[1];
    if (t < maxT) best = { t, n: [0, 1, 0] };
  }
  for (const b of BOXES) {
    const h = rayAABB(o, d, b.min, b.max);
    if (h && h.t < (best ? best.t : maxT)) {
      const n = [0, 0, 0];
      if (h.axis >= 0) n[h.axis] = h.sign;
      best = { t: h.t, n };
    }
  }
  return best;
}

/** Head and body hitboxes for a player standing with feet at (x, y, z). */
export function playerHitboxes(x, y, z) {
  return [
    { head: true, min: [x - 0.25, y + 1.48, z - 0.25], max: [x + 0.25, y + 1.88, z + 0.25] },
    { head: false, min: [x - 0.4, y, z - 0.4], max: [x + 0.4, y + 1.48, z + 0.4] },
  ];
}

/** First box overlapping a player standing at (x, y, z), or null. */
export function collideBox(x, y, z) {
  const r = PLAYER.radius, h = PLAYER.height;
  for (const b of BOXES) {
    if (x + r > b.min[0] && x - r < b.max[0] &&
        y + h > b.min[1] && y < b.max[1] &&
        z + r > b.min[2] && z - r < b.max[2]) return b;
  }
  return null;
}
