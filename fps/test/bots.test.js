// Headless multiplayer test: two bots join, walk into position, one shoots the other until a kill.
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import { PLAYER, WEAPONS } from '../public/shared/map.js';

const AR = WEAPONS[0];

const PORT = 3900 + Math.floor(Math.random() * 90);
const server = spawn(process.execPath, ['server.js'], { env: { ...process.env, PORT: String(PORT), KILL_LIMIT: '2', BOTS: '0' }, stdio: 'pipe' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function bot(name) {
  const ws = new WebSocket(`ws://localhost:${PORT}`);
  const b = { ws, name, msgs: [], waiters: [], id: 0, life: 0, pos: null };
  ws.addEventListener('message', (e) => {
    const m = JSON.parse(e.data);
    if (m.t === 'welcome') b.id = m.id;
    if (m.t === 'spawn') { b.life = m.life; b.pos = m.p.slice(); }
    if (m.t === 'fix') b.pos = m.p.slice();
    b.msgs.push(m);
    b.waiters = b.waiters.filter((w) => !(w.pred(m) && (w.res(m), true)));
  });
  b.send = (m) => ws.send(JSON.stringify(m));
  b.wait = (pred, ms = 4000) => {
    const found = b.msgs.find(pred);
    if (found) return Promise.resolve(found);
    return new Promise((res, rej) => {
      b.waiters.push({ pred, res });
      setTimeout(() => rej(new Error(`${name}: timed out waiting`)), ms);
    });
  };
  b.open = new Promise((r) => ws.addEventListener('open', r));
  // Walk to (x, z) at sprint speed, sending states like the real client.
  b.walkTo = async (x, z) => {
    for (;;) {
      const dx = x - b.pos[0], dz = z - b.pos[2], d = Math.hypot(dx, dz);
      const step = Math.min(d, PLAYER.sprint * 0.05);
      b.pos = [b.pos[0] + (dx / (d || 1)) * step, 0, b.pos[2] + (dz / (d || 1)) * step];
      b.send({ t: 'state', p: b.pos, y: 0, x: 0, l: b.life });
      await sleep(50);
      if (d < 0.01) return;
    }
  };
  return b;
}

try {
  await sleep(400);
  const status = await (await fetch(`http://localhost:${PORT}/status`)).json();
  assert.equal(status.players, 0);
  const html = await (await fetch(`http://localhost:${PORT}/`)).text();
  assert.match(html, /STRIKE/);
  const three = await fetch(`http://localhost:${PORT}/vendor/three.module.js`);
  assert.equal(three.status, 200);
  assert.equal((await fetch(`http://localhost:${PORT}/../server.js`)).status, 404);

  const a = bot('Alice'), b = bot('Bob');
  await Promise.all([a.open, b.open]);
  a.send({ t: 'join', name: 'Alice<script>' });
  await a.wait((m) => m.t === 'spawn');
  b.send({ t: 'join', name: 'Bob' });
  await b.wait((m) => m.t === 'spawn');
  const board = await a.wait((m) => m.t === 'board' && m.p.length === 2);
  assert.ok(board.p.some((r) => r[1] === 'Alicescript'), 'name sanitized');
  await a.wait((m) => m.t === 'join' && m.name === 'Bob');

  // Teleport attempt is rejected.
  const before = a.pos.slice();
  a.send({ t: 'state', p: [before[0] + 30, 0, before[2]], y: 0, x: 0, l: a.life });
  const fix = await a.wait((m) => m.t === 'fix');
  assert.deepEqual(fix.p, before);

  await Promise.all([a.walkTo(0, -30), b.walkTo(0, -36)]);
  await sleep(1600); // spawn protection + let history settle

  // Alice aims at Bob's head (Bob is 6m further toward -z).
  const eye = [0, PLAYER.eye, -30];
  const target = [0, 1.68, -36];
  const d = target.map((v, i) => v - eye[i]);
  let shots = 0;
  const killP = a.wait((m) => m.t === 'kill' && m.v === b.id, 5000);
  for (; shots < 4; shots++) {
    a.send({ t: 'shoot', o: eye, d, l: a.life });
    await sleep(AR.fireMs + 10);
    if (a.msgs.some((m) => m.t === 'kill')) break;
  }
  const kill = await killP;
  assert.equal(kill.k, a.id);
  assert.equal(kill.h, 1, 'headshot');
  const hm = a.msgs.filter((m) => m.t === 'hm');
  assert.ok(hm.length >= 1 && hm.every((m) => m.h === 1));
  const dmg = b.msgs.filter((m) => m.t === 'dmg');
  assert.equal(dmg[0].hp, 100 - AR.head);
  const seen = b.msgs.filter((m) => m.t === 'shot' && m.id === a.id);
  assert.ok(seen.length >= 2, 'victim sees shots');
  console.log(`✓ headshot kill in ${shots + 1} shots`);

  const respawn = await b.wait((m) => m.t === 'spawn' && m.life === 2, 5000);
  console.log('✓ respawned at', respawn.p);

  // Loadout applies on next spawn; walls block bullets; sniper headshot one-shots.
  a.send({ t: 'loadout', w: 2 });
  b.msgs.length = 0;
  await b.walkTo(0, -38);
  await sleep(1600);
  // Through the tower: Alice at (0,-30) aiming at Bob placed at (0, 12) would hit concrete. Check via a wall shot first.
  const wallShot = b.wait((m) => m.t === 'shot' && m.id === a.id);
  a.send({ t: 'shoot', o: eye, d: [0, 0, 1], l: a.life });
  const ws = await wallShot;
  assert.equal(ws.v, 0, 'shot into tower must not hit anyone');
  assert.ok(Math.abs(ws.e[2] - -22.4) < 0.05, 'bullet stops at the mid cover wall');
  console.log('✓ wall blocks bullets');

  // Switch to pistol: the next shot within the switch time is ignored.
  a.send({ t: 'slot', s: 1 });
  a.send({ t: 'shoot', o: eye, d, l: a.life });
  await sleep(120);
  assert.ok(!b.msgs.some((m) => m.t === 'dmg'), 'no damage during weapon switch');
  await sleep(300);
  const hpBefore = 100;
  a.send({ t: 'shoot', o: eye, d: [0, 1.73 - PLAYER.eye, -8], l: a.life });
  const pd = await b.wait((m) => m.t === 'dmg');
  assert.equal(pd.hp, hpBefore - WEAPONS[3].head, 'pistol headshot damage');
  console.log('✓ weapon switch + pistol damage');

  // Board updated
  const b2 = await a.wait((m) => m.t === 'board' && m.p.find((r) => r[0] === a.id)?.[2] === 1);
  assert.ok(b2);

  // Private rooms: create → code → friend joins by code; bad codes are rejected; rooms are isolated.
  const host = bot('Host'), friend = bot('Friend'), lost = bot('Lost');
  await Promise.all([host.open, friend.open, lost.open]);
  host.send({ t: 'join', name: 'Host', mode: 'create', bots: false });
  const hw = await host.wait((m) => m.t === 'welcome');
  assert.match(hw.room, /^[A-Z2-9]{5}$/);
  assert.equal(hw.pub, 0);
  assert.equal(hw.players.length, 1, 'new private room starts empty');
  friend.send({ t: 'join', name: 'Friend', mode: 'code', code: hw.room.toLowerCase() });
  const fw = await friend.wait((m) => m.t === 'welcome');
  assert.equal(fw.room, hw.room);
  assert.deepEqual(fw.players.map((p) => p[1]).sort(), ['Friend', 'Host']);
  await host.wait((m) => m.t === 'join' && m.name === 'Friend');
  lost.send({ t: 'join', name: 'Lost', mode: 'code', code: 'ZZZZZ' });
  const err = await lost.wait((m) => m.t === 'error');
  assert.match(err.m, /찾을 수 없습니다/);
  await sleep(200);
  assert.ok(!a.msgs.some((m) => m.t === 'join' && (m.name === 'Host' || m.name === 'Friend')), 'public room never sees private players');
  const st = await (await fetch(`http://localhost:${PORT}/status`)).json();
  assert.equal(st.rooms, 2);
  host.ws.close(); friend.ws.close();
  await sleep(200);
  assert.equal((await (await fetch(`http://localhost:${PORT}/status`)).json()).rooms, 1, 'empty room is removed');
  console.log('✓ room codes');

  // Disconnect broadcasts leave
  b.ws.close();
  await a.wait((m) => m.t === 'leave' && m.id === b.id);
  console.log('✓ leave broadcast');
  a.ws.close();
  console.log('ALL TESTS PASSED');
} catch (e) {
  console.error('TEST FAILED:', e);
  process.exitCode = 1;
} finally {
  server.kill();
}
