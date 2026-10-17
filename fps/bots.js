// Server-side AI players. They use the exact same shoot/reload paths as humans,
// so they obey fire rates, ammo, walls and spawn protection.
import { ARENA, BOXES, PLAYER, WEAPONS, raycastMap } from './public/shared/map.js';

const NAMES = ['민수', '지훈', '서준', '도윤', '하린', '지우', '유나', '태민', '현우', '수아', '예준', '시우', '다은', '건우'];
const BOT_PRIMARIES = [0, 0, 0, 1, 1, 2];

// ---------- navigation grid (1m cells on the ground plane) ----------
const N = ARENA * 2;
const blocked = new Uint8Array(N * N);
{
  const inflate = PLAYER.radius + 0.12;
  for (let i = 0; i < N; i++) {
    for (let j = 0; j < N; j++) {
      const x = -ARENA + i + 0.5, z = -ARENA + j + 0.5;
      if (Math.abs(x) > ARENA - 1 || Math.abs(z) > ARENA - 1) { blocked[i * N + j] = 1; continue; }
      for (const b of BOXES) {
        if (b.min[1] > PLAYER.height - 0.1) continue; // lintels, parapets: walk under/around
        if (x > b.min[0] - inflate && x < b.max[0] + inflate && z > b.min[2] - inflate && z < b.max[2] + inflate) {
          blocked[i * N + j] = 1;
          break;
        }
      }
    }
  }
}
const cellOf = (x, z) => [Math.floor(x + ARENA), Math.floor(z + ARENA)];
const free = (i, j) => i >= 0 && j >= 0 && i < N && j < N && !blocked[i * N + j];
const freeAt = (x, z) => { const [i, j] = cellOf(x, z); return free(i, j); };
const center = (i, j) => ({ x: -ARENA + i + 0.5, z: -ARENA + j + 0.5 });

function randomFreeCell() {
  for (;;) {
    const i = Math.floor(Math.random() * N), j = Math.floor(Math.random() * N);
    if (free(i, j)) return [i, j];
  }
}

/** A* over the grid with 8-way moves (no corner cutting). Returns world waypoints. */
function findPath(sx, sz, gi, gj) {
  let [si, sj] = cellOf(sx, sz);
  if (!free(si, sj)) {
    // Standing on an inflated edge: start from the nearest free neighbour.
    let found = false;
    for (let r = 1; r <= 2 && !found; r++) {
      for (let di = -r; di <= r && !found; di++) {
        for (let dj = -r; dj <= r && !found; dj++) {
          if (free(si + di, sj + dj)) { si += di; sj += dj; found = true; }
        }
      }
    }
    if (!found) return [];
  }
  const start = si * N + sj, goal = gi * N + gj;
  const g = new Float32Array(N * N).fill(Infinity);
  const came = new Int32Array(N * N).fill(-1);
  const closed = new Uint8Array(N * N);
  const heap = [];
  const push = (k, f) => {
    heap.push([f, k]);
    let c = heap.length - 1;
    while (c > 0) {
      const p = (c - 1) >> 1;
      if (heap[p][0] <= heap[c][0]) break;
      [heap[p], heap[c]] = [heap[c], heap[p]];
      c = p;
    }
  };
  const pop = () => {
    const top = heap[0], last = heap.pop();
    if (heap.length) {
      heap[0] = last;
      let c = 0;
      for (;;) {
        const l = c * 2 + 1, r = l + 1;
        let m = c;
        if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
        if (r < heap.length && heap[r][0] < heap[m][0]) m = r;
        if (m === c) break;
        [heap[m], heap[c]] = [heap[c], heap[m]];
        c = m;
      }
    }
    return top[1];
  };
  const h = (i, j) => { const dx = Math.abs(i - gi), dz = Math.abs(j - gj); return dx + dz - 0.586 * Math.min(dx, dz); };
  g[start] = 0;
  push(start, h(si, sj));
  let expanded = 0;
  while (heap.length && expanded < 6000) {
    const k = pop();
    if (closed[k]) continue;
    closed[k] = 1;
    expanded++;
    if (k === goal) break;
    const i = Math.floor(k / N), j = k % N;
    for (let di = -1; di <= 1; di++) {
      for (let dj = -1; dj <= 1; dj++) {
        if (!di && !dj) continue;
        const ni = i + di, nj = j + dj;
        if (!free(ni, nj)) continue;
        if (di && dj && (!free(i + di, j) || !free(i, j + dj))) continue;
        const nk = ni * N + nj, ng = g[k] + (di && dj ? 1.414 : 1);
        if (ng < g[nk]) { g[nk] = ng; came[nk] = k; push(nk, ng + h(ni, nj)); }
      }
    }
  }
  if (came[goal] === -1 && goal !== start) return [];
  const out = [];
  for (let k = goal; k !== start && k !== -1; k = came[k]) out.push(center(Math.floor(k / N), k % N));
  return out.reverse();
}

const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const rand = (a, b) => a + Math.random() * (b - a);

export function createBots(ctx) {
  const { players, newPlayer, join, leave, setPos, handleShoot, handleReload, weaponOf, now, isRoundOver } = ctx;
  const bots = () => [...players.values()].filter((p) => p.bot && p.joined);

  function add() {
    const used = new Set(bots().map((b) => b.name));
    const free = NAMES.filter((n) => !used.has('BOT ' + n));
    const name = 'BOT ' + (free.length ? free[Math.floor(Math.random() * free.length)] : NAMES[0]);
    const p = newPlayer(null, true);
    p.ai = {
      path: [], target: 0, reactAt: 0, errYaw: 0, errPitch: 0, nextShot: 0, burst: 0,
      strafe: 1, strafeUntil: 0, repathAt: 0, headAim: false, life: -1,
      skill: { react: rand(380, 720), err: rand(0.08, 0.16), spread: rand(0.012, 0.026), turn: rand(4.5, 7) },
    };
    join(p, name, BOT_PRIMARIES[Math.floor(Math.random() * BOT_PRIMARIES.length)]);
  }

  function removeOne() {
    const list = bots().sort((a, b) => Number(a.alive) - Number(b.alive));
    if (list.length) leave(list[0]);
  }

  function visible(p, o) {
    const eye = [p.pos.x, p.pos.y + PLAYER.eye, p.pos.z];
    const tgt = [o.pos.x, o.pos.y + 1.3, o.pos.z];
    const d = [tgt[0] - eye[0], tgt[1] - eye[1], tgt[2] - eye[2]];
    const dist = Math.hypot(...d);
    const hit = raycastMap(eye, d.map((v) => v / dist), dist);
    return !hit || hit.t > dist - 0.4;
  }

  function moveToward(p, tx, tz, speed, dt, t) {
    const dx = tx - p.pos.x, dz = tz - p.pos.z, d = Math.hypot(dx, dz);
    if (d < 1e-3) return true;
    const step = Math.min(d, speed * dt);
    const nx = p.pos.x + (dx / d) * step, nz = p.pos.z + (dz / d) * step;
    if (!freeAt(nx, nz) && freeAt(p.pos.x, p.pos.z)) return false;
    setPos(p, nx, 0, nz, t);
    return step >= d - 1e-3;
  }

  function think(p, dt) {
    const ai = p.ai, t = now();
    if (ai.life !== p.life) { // fresh spawn
      ai.life = p.life; ai.path = []; ai.target = 0;
    }
    if (isRoundOver()) return;

    // --- perception ---
    const fx = -Math.sin(p.yaw), fz = -Math.cos(p.yaw);
    let target = null, bestD = Infinity;
    for (const o of players.values()) {
      if (o === p || !o.joined || !o.alive) continue;
      const dx = o.pos.x - p.pos.x, dz = o.pos.z - p.pos.z, dist = Math.hypot(dx, dz);
      if (dist > 80 || dist >= bestD) continue;
      const facing = (dx * fx + dz * fz) / (dist || 1);
      const alerted = o.id === p.lastAttacker && t - p.lastHurt < 2500;
      if (facing < 0.45 && dist > 9 && !alerted && o.id !== ai.target) continue;
      if (!visible(p, o)) continue;
      target = o; bestD = dist;
    }

    if (target) {
      if (ai.target !== target.id) {
        ai.target = target.id;
        ai.reactAt = t + ai.skill.react * (bestD > 40 ? 1.3 : 1);
        ai.errYaw = rand(-1, 1) * ai.skill.err * 2;
        ai.errPitch = rand(-1, 1) * ai.skill.err;
        ai.headAim = Math.random() < 0.25;
      }
      ai.path = [];
      const dx = target.pos.x - p.pos.x, dz = target.pos.z - p.pos.z;
      const horiz = Math.hypot(dx, dz);
      const aimY = target.pos.y + (ai.headAim ? 1.68 : 1.15) - (p.pos.y + PLAYER.eye);
      const wantYaw = Math.atan2(-dx, -dz) + ai.errYaw;
      const wantPitch = Math.atan2(aimY, horiz) + ai.errPitch;
      ai.errYaw *= Math.exp(-2.8 * dt);
      ai.errPitch *= Math.exp(-2.8 * dt);
      const turn = ai.skill.turn * dt;
      const dy = wrap(wantYaw - p.yaw);
      p.yaw = wrap(p.yaw + Math.max(-turn, Math.min(turn, dy)));
      p.pitch += Math.max(-turn, Math.min(turn, wantPitch - p.pitch));

      // Strafe while fighting.
      if (t > ai.strafeUntil) { ai.strafe = Math.random() < 0.5 ? -1 : 1; ai.strafeUntil = t + rand(450, 1400); }
      const sx = Math.cos(p.yaw) * ai.strafe, sz = -Math.sin(p.yaw) * ai.strafe;
      const close = horiz < 7 ? -0.6 : horiz > 30 ? 0.5 : 0; // back off when too close, push in when far
      const mx = sx + (dx / horiz) * close, mz = sz + (dz / horiz) * close;
      if (!moveToward(p, p.pos.x + mx * 2, p.pos.z + mz * 2, PLAYER.walk * 0.7, dt, t)) ai.strafe *= -1;

      // Fire in bursts once on target.
      const w = WEAPONS[weaponOf(p)];
      if (p.ammo[p.slot] <= 0) { handleReload(p); return; }
      const aimOff = Math.abs(wrap(Math.atan2(-dx, -dz) - p.yaw));
      if (t >= ai.reactAt && t >= ai.nextShot && aimOff < 0.12 + 1.2 / Math.max(horiz, 1)) {
        const s = ai.skill.spread * (w.scope ? 0.15 : 1);
        const yaw = p.yaw + rand(-s, s), pitch = p.pitch + rand(-s, s);
        const d = [-Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch)];
        handleShoot(p, { o: [p.pos.x, p.pos.y + PLAYER.eye, p.pos.z], d, l: p.life });
        ai.burst++;
        const burstLen = w.auto ? 4 + Math.floor(Math.random() * 4) : 1;
        if (ai.burst >= burstLen) { ai.burst = 0; ai.nextShot = t + (w.auto ? rand(220, 480) : w.fireMs + rand(150, 600)); }
        else ai.nextShot = t + w.fireMs;
      }
      return;
    }

    // --- no target: roam / hunt ---
    ai.target = 0;
    if (t - p.lastHurt < 1500 && p.lastAttacker) {
      const a = players.get(p.lastAttacker);
      if (a) p.yaw = wrap(p.yaw + Math.max(-0.3, Math.min(0.3, wrap(Math.atan2(-(a.pos.x - p.pos.x), -(a.pos.z - p.pos.z)) - p.yaw))));
    }
    if (p.ammo[p.slot] < WEAPONS[weaponOf(p)].mag * 0.5) handleReload(p);
    if (!ai.path.length || t > ai.repathAt) {
      let goal = randomFreeCell();
      const others = [...players.values()].filter((o) => o !== p && o.joined && o.alive);
      if (others.length && Math.random() < 0.6) {
        const o = others[Math.floor(Math.random() * others.length)];
        const [gi, gj] = cellOf(o.pos.x + rand(-6, 6), o.pos.z + rand(-6, 6));
        if (free(gi, gj)) goal = [gi, gj];
      }
      ai.path = findPath(p.pos.x, p.pos.z, goal[0], goal[1]);
      ai.repathAt = t + rand(6000, 12000);
    }
    const wp = ai.path[0];
    if (!wp) return;
    const speed = ai.path.length > 6 ? PLAYER.sprint * 0.85 : PLAYER.walk;
    const reached = moveToward(p, wp.x, wp.z, speed, dt, t);
    if (reached) ai.path.shift();
    const dx = wp.x - p.pos.x, dz = wp.z - p.pos.z;
    if (Math.hypot(dx, dz) > 0.05) {
      const want = Math.atan2(-dx, -dz);
      p.yaw = wrap(p.yaw + Math.max(-6 * dt, Math.min(6 * dt, wrap(want - p.yaw))));
    }
    p.pitch *= 0.85;
  }

  return {
    add,
    removeOne,
    tick(dt) {
      for (const p of bots()) if (p.alive) think(p, dt);
    },
  };
}

export const _test = { findPath, freeAt, cellOf, N };
