import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';
import {
  ARENA, PLAYER, WEAPONS, PRIMARIES, PISTOL, RANGE, SPAWNS,
  raycastMap, rayAABB, playerHitboxes,
} from './public/shared/map.js';
import { createBots } from './bots.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT) || 3000;
const KILL_LIMIT = Number(process.env.KILL_LIMIT) || 30;
const BOT_FILL = Number(process.env.BOTS ?? 6); // keep at least this many combatants while humans are online
const TICK_MS = 50;
const RESPAWN_MS = 3000;
const SPAWN_PROTECT_MS = 1500;
const ROUND_BREAK_MS = 10000;
const REGEN_DELAY_MS = 5000;
const REGEN_PER_SEC = 20;
const SWITCH_MS = 350;
const MAX_PLAYERS = 16;
const CLIENT_INTERP_MS = 100; // must match INTERP_MS in game.js
const MAX_REWIND_MS = 350;
const STREAKS = { 3: '3연속 처치', 5: '5연속 처치 — 폭주 중!', 8: '8연속 처치 — 막을 수 없다!', 12: '12연속 처치 — 전설!' };

// ---------- static files ----------
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};
const ROOTS = [
  ['/vendor/addons/', path.join(__dirname, 'node_modules/three/examples/jsm')],
  ['/vendor/', path.join(__dirname, 'node_modules/three/build')],
  ['/', path.join(__dirname, 'public')],
];

const server = http.createServer((req, res) => {
  let url;
  try { url = decodeURIComponent(req.url.split('?')[0]); } catch { url = ''; }
  if (url === '/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ players: humanCount(), bots: botCount(), max: MAX_PLAYERS }));
    return;
  }
  if (url === '/') url = '/index.html';
  for (const [prefix, dir] of ROOTS) {
    if (!url.startsWith(prefix)) continue;
    const file = path.normalize(path.join(dir, url.slice(prefix.length)));
    if (!file.startsWith(dir + path.sep)) break;
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); res.end('Not found'); return; }
      res.writeHead(200, {
        'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
        'Cache-Control': 'no-cache',
      });
      res.end(data);
    });
    return;
  }
  res.writeHead(404);
  res.end('Not found');
});

// ---------- game state ----------
const players = new Map();
let nextId = 1;
let roundOverUntil = 0;

const now = () => Date.now();
const r2 = (v) => Math.round(v * 100) / 100;
const joined = () => [...players.values()].filter((p) => p.joined);
const humanCount = () => joined().filter((p) => !p.bot).length;
const botCount = () => joined().filter((p) => p.bot).length;

function send(p, msg) {
  if (p.ws && p.ws.readyState === 1) p.ws.send(JSON.stringify(msg));
}
function broadcast(msg, except) {
  const s = JSON.stringify(msg);
  for (const p of players.values()) {
    if (p !== except && p.joined && p.ws && p.ws.readyState === 1) p.ws.send(s);
  }
}

function newPlayer(ws, bot = false) {
  const p = {
    id: nextId++, ws, bot, joined: false, name: '', hue: 0,
    pos: { x: 0, y: 0, z: 0 }, yaw: 0, pitch: 0,
    hp: PLAYER.maxHp, alive: false, life: 0, kills: 0, deaths: 0, streak: 0,
    primary: 0, nextPrimary: 0, slot: 0, ammo: [0, 0],
    reloadUntil: 0, reloadSlot: 0, switchUntil: 0, lastShot: 0, lastHurt: 0, lastAttacker: 0,
    protectUntil: 0, respawnAt: 0, lastState: now(), ping: 0, isAlive: true, history: [],
  };
  players.set(p.id, p);
  return p;
}

const weaponOf = (p) => (p.slot === 0 ? p.primary : PISTOL);

function join(p, name, primary) {
  p.joined = true;
  p.name = name;
  p.hue = Math.round((p.id * 137.508) % 360);
  p.nextPrimary = PRIMARIES.includes(primary) ? primary : 0;
  send(p, {
    t: 'welcome', id: p.id, killLimit: KILL_LIMIT,
    players: joined().map((o) => [o.id, o.name, o.hue, o.bot ? 1 : 0]),
  });
  broadcast({ t: 'join', id: p.id, name: p.name, hue: p.hue, bot: p.bot ? 1 : 0 }, p);
  if (!p.bot) broadcast({ t: 'chat', sys: 1, m: `${p.name} 님이 입장했습니다` });
  spawn(p);
  broadcast(boardMsg());
}

function leave(p) {
  players.delete(p.id);
  if (!p.joined) return;
  broadcast({ t: 'leave', id: p.id });
  if (!p.bot) broadcast({ t: 'chat', sys: 1, m: `${p.name} 님이 나갔습니다` });
  broadcast(boardMsg());
}

function pickSpawn(p) {
  const others = joined().filter((o) => o !== p && o.alive);
  const scored = SPAWNS.map((s) => {
    let d = Infinity;
    for (const o of others) d = Math.min(d, Math.hypot(o.pos.x - s.x, o.pos.z - s.z));
    return { s, d };
  }).sort((a, b) => b.d - a.d);
  return scored[Math.floor(Math.random() * Math.min(3, scored.length))].s;
}

function spawn(p) {
  const s = pickSpawn(p);
  p.pos = { x: s.x, y: s.y, z: s.z };
  p.yaw = s.yaw;
  p.pitch = 0;
  p.hp = PLAYER.maxHp;
  p.alive = true;
  p.life++;
  p.primary = p.nextPrimary;
  p.slot = 0;
  p.ammo = [WEAPONS[p.primary].mag, WEAPONS[PISTOL].mag];
  p.reloadUntil = 0;
  p.switchUntil = 0;
  p.protectUntil = now() + SPAWN_PROTECT_MS;
  p.lastState = now();
  p.respawnAt = 0;
  p.history = [{ t: now(), ...p.pos }];
  send(p, { t: 'spawn', p: [s.x, s.y, s.z], yaw: s.yaw, life: p.life, w: p.primary });
}

function boardMsg() {
  return {
    t: 'board',
    p: joined().map((p) => [p.id, p.name, p.kills, p.deaths, p.bot ? -1 : p.ping, p.hue]),
  };
}

const eyeOf = (p) => [p.pos.x, p.pos.y + PLAYER.eye, p.pos.z];

// Where was player v when the shooter saw them? (lag compensation)
function rewoundPos(v, t) {
  const h = v.history;
  if (!h.length || t >= h[h.length - 1].t) return v.pos;
  for (let i = h.length - 1; i > 0; i--) {
    const a = h[i - 1], b = h[i];
    if (a.t <= t) {
      const k = b.t === a.t ? 1 : (t - a.t) / (b.t - a.t);
      return { x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k, z: a.z + (b.z - a.z) * k };
    }
  }
  return h[0];
}

function finishReload(p, t) {
  if (p.reloadUntil && t >= p.reloadUntil) {
    p.ammo[p.reloadSlot] = WEAPONS[p.reloadSlot === 0 ? p.primary : PISTOL].mag;
    p.reloadUntil = 0;
  }
}

const isVec3 = (v) => Array.isArray(v) && v.length === 3 && v.every(Number.isFinite);

function handleShoot(p, msg) {
  const t = now();
  if (!p.alive || t < roundOverUntil || msg.l !== p.life) return;
  finishReload(p, t);
  const w = WEAPONS[weaponOf(p)];
  if (t - p.lastShot < w.fireMs * 0.7 || t < p.switchUntil) return;
  if (p.reloadUntil || p.ammo[p.slot] <= 0) return;
  p.lastShot = t;
  p.ammo[p.slot]--;

  // Trust the client's aim direction but not its origin beyond a small tolerance.
  const e = eyeOf(p);
  let o = isVec3(msg.o) ? msg.o : e;
  if (Math.hypot(o[0] - e[0], o[1] - e[1], o[2] - e[2]) > 1.5) o = e;
  if (!isVec3(msg.d)) return;
  const len = Math.hypot(...msg.d);
  if (len < 1e-6) return;
  const d = msg.d.map((v) => v / len);

  const wall = raycastMap(o, d, RANGE);
  let bestT = wall ? wall.t : RANGE;
  let victim = null, head = false;
  const seenAt = t - (p.bot ? 0 : Math.min(MAX_REWIND_MS, p.ping / 2 + CLIENT_INTERP_MS));
  for (const v of players.values()) {
    if (v === p || !v.joined || !v.alive) continue;
    const vp = rewoundPos(v, seenAt);
    for (const hb of playerHitboxes(vp.x, vp.y, vp.z)) {
      const h = rayAABB(o, d, hb.min, hb.max);
      if (h && h.t < bestT) { bestT = h.t; victim = v; head = hb.head; }
    }
  }
  const end = [o[0] + d[0] * bestT, o[1] + d[1] * bestT, o[2] + d[2] * bestT].map(r2);
  broadcast({ t: 'shot', id: p.id, w: weaponOf(p), o: o.map(r2), e: end, n: victim ? null : wall?.n ?? null, v: victim?.id ?? 0 }, p);

  if (!victim || t < victim.protectUntil) return;
  let dmg = head ? w.head : w.body;
  if (bestT > w.falloffDist) dmg = Math.round(dmg * w.falloff);
  victim.hp -= dmg;
  victim.lastHurt = t;
  victim.lastAttacker = p.id;
  const killed = victim.hp <= 0;
  send(victim, { t: 'dmg', hp: Math.max(0, Math.ceil(victim.hp)), from: [r2(p.pos.x), r2(p.pos.z)] });
  send(p, { t: 'hm', h: head ? 1 : 0, k: killed ? 1 : 0, v: victim.id, d: dmg });
  if (killed) kill(victim, p, head, weaponOf(p));
}

function kill(victim, killer, head, weapon) {
  victim.alive = false;
  victim.hp = 0;
  victim.deaths++;
  victim.respawnAt = now() + RESPAWN_MS;
  const ended = victim.streak >= 3 ? victim.streak : 0;
  victim.streak = 0;
  if (killer && killer !== victim) { killer.kills++; killer.streak++; }
  broadcast({ t: 'kill', k: killer ? killer.id : 0, v: victim.id, h: head ? 1 : 0, w: weapon, s: killer?.streak ?? 0, kh: killer ? Math.ceil(killer.hp) : 0 });
  if (killer && STREAKS[killer.streak]) broadcast({ t: 'chat', sys: 1, m: `🔥 ${killer.name} — ${STREAKS[killer.streak]}` });
  if (ended && killer) broadcast({ t: 'chat', sys: 1, m: `${killer.name} 님이 ${victim.name} 님의 ${ended}연속 처치를 끊었습니다` });
  broadcast(boardMsg());
  if (killer && killer.kills >= KILL_LIMIT && now() >= roundOverUntil) endRound(killer);
}

function endRound(winner) {
  roundOverUntil = now() + ROUND_BREAK_MS;
  broadcast({ t: 'round', w: winner.id, name: winner.name, ms: ROUND_BREAK_MS });
  setTimeout(() => {
    for (const p of joined()) {
      p.kills = 0;
      p.deaths = 0;
      p.streak = 0;
      spawn(p);
    }
    broadcast({ t: 'roundstart' });
    broadcast(boardMsg());
  }, ROUND_BREAK_MS);
}

function setPos(p, x, y, z, t) {
  p.pos = { x, y, z };
  p.history.push({ t, x, y, z });
  while (p.history.length && p.history[0].t < t - 1000) p.history.shift();
}

function handleState(p, msg) {
  if (!p.alive || msg.l !== p.life || !isVec3(msg.p)) return;
  const pos = msg.p;
  const t = now();
  const dt = Math.min(1, (t - p.lastState) / 1000);
  p.lastState = t;
  const moved = Math.hypot(pos[0] - p.pos.x, pos[2] - p.pos.z);
  const limit = PLAYER.sprint * 1.25 * dt + 1.2;
  if (moved > limit || Math.abs(pos[0]) > ARENA || Math.abs(pos[2]) > ARENA || pos[1] < -1 || pos[1] > 12) {
    // Reject impossible moves and pull the client back.
    send(p, { t: 'fix', p: [p.pos.x, p.pos.y, p.pos.z] });
    return;
  }
  setPos(p, pos[0], pos[1], pos[2], t);
  if (Number.isFinite(msg.y)) p.yaw = msg.y;
  if (Number.isFinite(msg.x)) p.pitch = Math.max(-1.6, Math.min(1.6, msg.x));
}

function handleSlot(p, slot) {
  if (!p.alive || (slot !== 0 && slot !== 1) || slot === p.slot) return;
  p.slot = slot;
  p.reloadUntil = 0; // switching cancels a reload
  p.switchUntil = now() + SWITCH_MS - 100;
}

function handleReload(p) {
  const t = now();
  finishReload(p, t);
  if (!p.alive || p.reloadUntil || t < p.switchUntil) return;
  if (p.ammo[p.slot] >= WEAPONS[weaponOf(p)].mag) return;
  p.reloadSlot = p.slot;
  p.reloadUntil = t + WEAPONS[weaponOf(p)].reloadMs - 150;
}

function cleanName(name, id) {
  const n = String(name ?? '').replace(/[^\p{L}\p{N} _\-.]/gu, '').trim().slice(0, 16);
  return n || `Player${id}`;
}

// ---------- bots ----------
const bots = createBots({
  players, newPlayer, join, leave, setPos, handleShoot, handleReload, weaponOf, now,
  isRoundOver: () => now() < roundOverUntil,
});

function balanceBots() {
  const humans = humanCount();
  const want = humans === 0 ? 0 : Math.max(0, Math.min(BOT_FILL - humans, MAX_PLAYERS - humans));
  const have = botCount();
  if (have < want) bots.add();
  else if (have > want) bots.removeOne();
}

// ---------- networking ----------
const wss = new WebSocketServer({ server, maxPayload: 4096 });

wss.on('connection', (ws) => {
  const p = newPlayer(ws);

  ws.on('pong', () => { p.isAlive = true; });
  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }
    if (!msg || typeof msg !== 'object') return;
    if (!p.joined) {
      if (msg.t !== 'join') return;
      if (humanCount() >= MAX_PLAYERS) { send(p, { t: 'full' }); ws.close(); return; }
      // Make room by removing a bot first if the server is full of them.
      if (joined().length >= MAX_PLAYERS) bots.removeOne();
      join(p, cleanName(msg.name, p.id), msg.w);
      return;
    }
    switch (msg.t) {
      case 'state': handleState(p, msg); break;
      case 'shoot': handleShoot(p, msg); break;
      case 'reload': handleReload(p); break;
      case 'slot': handleSlot(p, msg.s); break;
      case 'loadout':
        if (PRIMARIES.includes(msg.w)) p.nextPrimary = msg.w;
        break;
      case 'ping':
        if (Number.isFinite(msg.c)) send(p, { t: 'pong', c: msg.c });
        if (Number.isFinite(msg.rtt)) p.ping = Math.max(0, Math.min(999, Math.round(msg.rtt)));
        break;
      case 'chat': {
        const m = String(msg.m ?? '').replace(/\s+/g, ' ').trim().slice(0, 120);
        if (m) broadcast({ t: 'chat', id: p.id, m });
        break;
      }
    }
  });
  ws.on('close', () => leave(p));
});

// Drop dead connections.
setInterval(() => {
  for (const p of players.values()) {
    if (p.bot) continue;
    if (!p.isAlive) { p.ws.terminate(); continue; }
    p.isAlive = false;
    p.ws.ping();
  }
}, 10000);

// Simulation tick: bots, respawns, regen, snapshots.
let tickCount = 0;
setInterval(() => {
  const t = now();
  tickCount++;
  if (tickCount % 10 === 0) balanceBots();
  bots.tick(TICK_MS / 1000);
  for (const p of joined()) {
    finishReload(p, t);
    if (!p.alive && p.respawnAt && t >= p.respawnAt && t >= roundOverUntil) spawn(p);
    if (p.alive && p.hp < PLAYER.maxHp && t - p.lastHurt > REGEN_DELAY_MS) {
      p.hp = Math.min(PLAYER.maxHp, p.hp + REGEN_PER_SEC * TICK_MS / 1000);
    }
  }
  broadcast({
    t: 's',
    p: joined().map((p) => [
      p.id, r2(p.pos.x), r2(p.pos.y), r2(p.pos.z), r2(p.yaw), r2(p.pitch),
      p.alive ? 1 : 0, Math.ceil(p.hp), t < p.protectUntil ? 1 : 0, weaponOf(p),
    ]),
  });
  if (tickCount % 40 === 0) broadcast(boardMsg());
}, TICK_MS);

server.listen(PORT, () => {
  console.log(`STRIKE ZONE server running → http://localhost:${PORT}`);
});
