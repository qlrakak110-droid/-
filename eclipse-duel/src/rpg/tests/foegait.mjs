// Side view of an enemy walking / running across the arena (sandbox): KIND=cultist|protector GAIT=walk|run
export default async ({ evalJs, advance, shot, log }) => {
  const kind = process.env.KIND || 'cultist', runG = process.env.GAIT === 'run';
  await evalJs(`__ED.rpg.start('kael', { sandbox: true })`);
  await evalJs(`(() => { const r = __ED.rpg, w = r.world(); r.god(true); r.clear(); r.lock(null); r.tp(-13, 6, 0); const a = w.spawn('${kind}', { x: -9, z: 0, yaw: 0, force: true }); a.controller = { think(w2, b, dt, it) { it.moveX = 1; it.moveZ = 0; it.run = ${runG}; } }; window.__foe = a; w.camera.worldShot((t, out) => { const h = a.view.pos; out.pos.set(h.x + 0.2, 1.2, h.z + 4.6); out.look.set(h.x + 0.2, 1.0 * a.scale, h.z); out.fov = 36; }, { dur: 99 }); })()`);
  await advance(1.6);
  for (let i = 0; i < 8; i++) { await shot('f' + i); await advance(runG ? 0.083 : 0.135); }
};
