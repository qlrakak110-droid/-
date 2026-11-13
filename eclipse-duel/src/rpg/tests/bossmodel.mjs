// Model review of the boss in the engine: full body from four sides and a bust, standing idle (free camera).
//   node tools/shot.mjs game --as boss --size 800x900 --scenario src/rpg/tests/bossmodel.mjs --sheet 5 --sheet-only --out shots/rpg/boss/model
import { T } from '../boss/clips.js';
export default async ({ evalJs, advance, shot }) => {
  await evalJs(`__ED.rpg.start('kael', { encounter: 'idol' })`);
  await evalJs('__ED.rpg.god(true)');
  await advance(T.wake + 1.2);
  await evalJs(`(() => { const r = __ED.rpg, w = r.world(); const b = w.actors.find((a) => a.kind === 'idol'); b.controller = { think() {} }; b.teleport(0, 0, Math.PI); r.tp(-13, 3, 0); r.lock(null); window.__view = (yaw, dist, h, look, fov) => w.camera.worldShot((t, out) => { out.pos.set(-Math.cos(yaw) * dist, h, Math.sin(yaw) * dist); out.look.set(0, look, 0); out.fov = fov; }, { dur: 99 }); })()`);
  await advance(0.5);
  const views = { front: [0.25, 11, 3.2, 3.0, 34], side: [1.57, 11, 3.2, 3.0, 34], back: [3.4, 11, 3.2, 3.0, 34], bust: [0.3, 5.2, 5.0, 4.9, 30], legs: [0.5, 5.5, 1.6, 1.7, 32] };
  for (const k of (process.env.VIEWS || 'front,side,back,bust,legs').split(',')) { await evalJs(`__view(${views[k].join(',')})`); await advance(1.2); await shot(k); }
};
