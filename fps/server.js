import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import { WebSocketServer } from './ws-lite.js';
import {
  ARENA, PLAYER, WEAPONS, PRIMARIES, PISTOL, RANGE, SPAWNS,
  raycastMap, rayAABB, playerHitboxes,
} from './public/shared/map.js';
import { createBots } from './bots.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT) || 3000;
const KILL_LIMIT = Number(process.env.KILL_LIMIT) || 30;
const BOT_FILL = Number(process.env.BOTS ?? 6); // keep at least this many combatants while humans are in a room
const TICK_MS = 50;
const RESPAWN_MS = 3000;
const SPAWN_PROTECT_MS = 1500;
const ROUND_BREAK_MS = 10000;
const REGEN_DELAY_MS = 5000;
const REGEN_PER_SEC = 20;
const SWITCH_MS = 350;
const MAX_PLAYERS = 16;
const MAX_ROOMS = 200;
const CLIENT_INTERP_MS = 100; // must match INTERP_MS in game.js
const MAX_REWIND_MS = 350;
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I
const STREAKS = { 3: '3연속 처치', 5: '5연속 처치 — 폭주 중!', 8: '8연속 처치 — 막을 수 없다!', 12: '12연속 처치 — 전설!' };

// ---------- static files ----------
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};
const ROOTS = [['/', path.join(__dirname, 'public')]];

const server = http.createServer((req, res) => {
  let url;
  try { url = decodeURIComponent(req.url.split('?')[0]); } catch { url = ''; }
  if (url === '/status') {
    let humans = 0;
    for (const r of rooms.values()) humans += r.humanCount();
    const pub = [...rooms.values()].filter((r) => r.isPublic).reduce((n, r) => n + r.humanCount(), 0);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ players: humans, public: pub, rooms: rooms.size, max: MAX_PLAYERS }));
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

// ---------- helpers ----------
let nextId = 1;
const now = () => Date.now();
const r2 = (v) => Math.round(v * 100) / 100;
const isVec3 = (v) => Array.isArray(v) && v.length === 3 && v.every(Number.isFinite);

function send(p, msg) {
  if (p.ws && p.ws.readyState === 1) p.ws.send(JSON.stringify(msg));
}

function cleanName(name, id) {
  const n = String(name ?? '').replace(/[^\p{L}\p{N} _\-.]/gu, '').trim().slice(0, 16);
  return n || `Player${id}`;
}

const normCode = (c) => String(c ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8);

// =====================================================================
// A room is one independent match: its own players, bots, score and round.
// =====================================================================
const rooms = new Map();

function newCode() {
  for (;;) {
    let c = '';
    for (let i = 0; i < 5; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    if (!rooms.has(c)) return c;
  }
}

function createRoom({ isPublic, botFill }) {
  const code = newCode();
  const players = new Map();
  let roundOverUntil = 0;
  let tickCount = 0;

  const joined = () => [...players.values()].filter((p) => p.joined);
  const humanCount = () => joined().filter((p) => !p.bot).length;
  const botCount = () => joined().filter((p) => p.bot).length;

  function broadcast(msg, except, droppable = false) {
    const s = JSON.stringify(msg);
    for (const p of players.values()) {
      if (p === except || !p.joined || !p.ws || p.ws.readyState !== 1) continue;
      // A client that can't keep up skips snapshots instead of building an unbounded backlog.
      if (droppable && p.ws.bufferedAmount > 256 * 1024) continue;
      p.ws.send(s);
    }
  }

  function newPlayer(ws, bot = false) {
    const p = {
      id: nextId++, ws, bot, joined: false, name: '', hue: 0,
      pos: { x: 0, y: 0, z: 0 }, yaw: 0, pitch: 0,
      hp: PLAYER.maxHp, alive: false, life: 0, kills: 0, deaths: 0, streak: 0,
      primary: 0, nextPrimary: 0, slot: 0, ammo: [0, 0],
      reloadUntil: 0, reloadSlot: 0, switchUntil: 0, lastShot: 0, lastHurt: 0, lastAttacker: 0,
      protectUntil: 0, respawnAt: 0, lastState: now(), ping: 0, history: [],
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
      t: 'welcome', id: p.id, killLimit: KILL_LIMIT, room: code, pub: isPublic ? 1 : 0,
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
      if (!rooms.has(code)) return;
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

  const bots = createBots({
    players, newPlayer, join, leave, setPos, handleShoot, handleReload, weaponOf, now,
    isRoundOver: () => now() < roundOverUntil,
  });

  function balanceBots() {
    const humans = humanCount();
    const want = humans === 0 ? 0 : Math.max(0, Math.min(botFill - humans, MAX_PLAYERS - humans));
    const have = botCount();
    if (have < want) bots.add();
    else if (have > want) bots.removeOne();
  }

  const room = {
    code, isPublic, botFill,
    humanCount,
    addHuman(ws, name, primary) {
      if (joined().length >= MAX_PLAYERS) bots.removeOne(); // make room by dropping a bot
      const p = newPlayer(ws);
      join(p, cleanName(name, p.id), primary);
      return p;
    },
    leave,
    handle(p, msg) {
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
    },
    // Simulation tick: bots, respawns, regen, snapshots.
    tick() {
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
      }, null, true);
      if (tickCount % 40 === 0) broadcast(boardMsg());
    },
  };
  rooms.set(code, room);
  return room;
}

/** Public quick-match: the fullest public room that still has space, else a new one. */
function findPublicRoom() {
  let best = null;
  for (const r of rooms.values()) {
    if (!r.isPublic || r.humanCount() >= MAX_PLAYERS) continue;
    if (!best || r.humanCount() > best.humanCount()) best = r;
  }
  return best;
}

// ---------- networking ----------
const wss = new WebSocketServer({ server, maxPayload: 4096 });

wss.on('connection', (ws) => {
  let room = null, p = null;
  ws.missed = 0;
  const fail = (m) => { ws.send(JSON.stringify({ t: 'error', m })); ws.close(); };

  ws.on('pong', () => { ws.missed = 0; });
  ws.on('message', (raw) => {
    ws.missed = 0;
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }
    if (!msg || typeof msg !== 'object') return;
    if (p) { room.handle(p, msg); return; }
    if (msg.t !== 'join') return;

    if (msg.mode === 'code') {
      room = rooms.get(normCode(msg.code));
      if (!room) return fail('해당 코드의 방을 찾을 수 없습니다. 코드를 다시 확인해 주세요.');
      if (room.humanCount() >= MAX_PLAYERS) return fail('방이 가득 찼습니다 (최대 16명).');
    } else {
      if (msg.mode !== 'create') room = findPublicRoom();
      if (!room) {
        if (rooms.size >= MAX_ROOMS) return fail('서버에 방이 너무 많습니다. 잠시 후 다시 시도해 주세요.');
        room = createRoom({ isPublic: msg.mode !== 'create', botFill: msg.mode === 'create' && msg.bots === false ? 0 : BOT_FILL });
      }
    }
    p = room.addHuman(ws, msg.name, msg.w);
  });
  ws.on('close', () => {
    if (!p) return;
    room.leave(p);
    if (room.humanCount() === 0) rooms.delete(room.code);
  });
});

// Drop connections that have been silent for ~30s.
setInterval(() => {
  for (const ws of wss.clients) {
    if (++ws.missed > 3) { ws.terminate(); continue; }
    ws.ping();
  }
}, 10000);

setInterval(() => {
  for (const r of rooms.values()) r.tick();
}, TICK_MS);

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') console.error(`\n포트 ${PORT}이(가) 이미 사용 중입니다. 다른 포트로 실행하세요: PORT=3001 node server.js\n`);
  else console.error(e);
  process.exit(1);
});

server.listen(PORT, () => {
  const lan = Object.values(os.networkInterfaces()).flat()
    .filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => `http://${i.address}:${PORT}`);
  console.log('');
  console.log('  ███ STRIKE ZONE 서버 실행 중 ███');
  console.log('');
  console.log(`  내 컴퓨터에서 접속:      http://localhost:${PORT}`);
  for (const u of lan) console.log(`  같은 와이파이 친구 접속: ${u}`);
  console.log('');
  console.log('  게임에서 [방 만들기] → 방 코드/초대 링크를 친구에게 보내세요.');
  console.log('  종료: Ctrl + C');
  console.log('');
});
