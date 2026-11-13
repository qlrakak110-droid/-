// Model review of a hero in the engine (sandbox, free camera): front three-quarter, back (the gameplay view) and bust.
export default async ({ evalJs, advance, shot }) => {
  const hero = process.env.HERO || 'kael';
  await evalJs(`__ED.rpg.start('${hero}', { sandbox: true })`);
  await evalJs(`(() => { const r = __ED.rpg, w = r.world(); r.god(true); r.clear(); r.lock(null); r.tp(0, 0, Math.PI); window.__view = (yaw, dist, h, look, fov) => w.camera.worldShot((t, out) => { out.pos.set(-Math.cos(yaw) * dist, h, Math.sin(yaw) * dist); out.look.set(0, look, 0); out.fov = fov; }, { dur: 99 }); })()`);
  await advance(1.0);
  for (const [k, v] of Object.entries({ front: [0.5, 3.6, 1.35, 1.0, 34], back: [3.5, 3.6, 1.5, 1.0, 34], bust: [0.35, 1.5, 1.6, 1.5, 32] })) { await evalJs(`__view(${v.join(',')})`); await advance(1.2); await shot(k); }
};
