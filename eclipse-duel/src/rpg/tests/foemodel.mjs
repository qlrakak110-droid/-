// Model review of the cultists in the engine (sandbox, free camera): front / side / back of both kinds.
export default async ({ evalJs, advance, shot }) => {
  await evalJs(`__ED.rpg.start('kael', { sandbox: true })`);
  await evalJs(`(() => { const r = __ED.rpg, w = r.world(); r.god(true); r.clear(); r.lock(null); r.tp(-13, 3, 0); for (const [k, z] of [['cultist', -0.8], ['protector', 0.9]]) { const a = w.spawn(k, { x: 0, z, yaw: Math.PI, force: true }); a.controller = { think() {} }; } window.__view = (yaw, dist, h, look, fov) => w.camera.worldShot((t, out) => { out.pos.set(-Math.cos(yaw) * dist, h, Math.sin(yaw) * dist); out.look.set(0, look, 0); out.fov = fov; }, { dur: 99 }); })()`);
  await advance(1.2);
  for (const [k, v] of Object.entries({ front: [0.0, 4.6, 1.5, 1.15, 34], q: [0.75, 4.6, 1.6, 1.15, 34], back: [3.14, 4.6, 1.5, 1.15, 34], bust: [0.25, 2.4, 1.75, 1.6, 30] })) { await evalJs(`__view(${v.join(',')})`); await advance(1.2); await shot(k); }
};
