// Per-frame render cost of an ultimate (gl.finish after every frame, so the time is the real GPU work under
// SwiftShader): prints the most expensive frames with the lock time, camera shot, live particles per layer, visible
// VFX meshes, draw calls and triangles.  ULT=kael node tools/shot.mjs game --size 320x180 --scenario src/game/tests/ultcost.mjs
export default async ({ evalJs, log }) => {
  const u = process.env.ULT || 'kael';
  const foe = u === 'kael' ? 'iska' : 'kael';
  const N = Number(process.env.FRAMES || 420);
  await evalJs(`__ED.game.start('${u}', '${foe}', { mode: 'demo', seed: 11 })`);
  await evalJs('__ED.game.skipIntro()');
  await evalJs("__ED.game.controller(0, 'idle'); __ED.game.controller(1, 'idle'); __ED.game.place(0, -1.4, 1); __ED.game.place(1, 0.6, -1); __ED.game.meters(0, { ult: 100 })");
  await evalJs('__ED.advance(1); __ED.render(); 1');
  await evalJs("__ED.game.forceMove(0, __ED.game.moveFor(0, 'ult'))");
  const rows = await evalJs(`(() => {
    const ctx = __ED.ctx, gl = ctx.renderer.getContext(), v = ctx.vfx, out = [];
    const live = () => {
      const o = {};
      for (const k in v.particles.layers) {
        const r = v.particles.layers[k].ring, f = r.f32; let n = 0;
        for (let i = 0; i < r.capacity; i++) { const b = i * r.stride, life = f[b + 7]; if (life === 0) continue; const now = life < 0 ? v.clock.real : v.clock.game; if (now >= f[b + 3] && now < f[b + 3] + Math.abs(life)) n++; }
        o[k] = n;
      }
      return o;
    };
    for (let i = 0; i < ${N}; i++) {
      ctx.frame(1 / 60, false);
      const t0 = performance.now();
      ctx.renderer.info.reset(); ctx.post.render(ctx.scene, ctx.camera); gl.finish();
      const ms = performance.now() - t0;
      const m = __ED.game.match();
      const meshes = v.root.children.filter((c) => c.visible).map((c) => c.name || c.type).join(',');
      const dist = ctx.post.distortionScene.children.filter((c) => c.visible).length;
      out.push({ i, ms: +ms.toFixed(0), lock: m.cinematic ? +m.cinematic.t.toFixed(2) : null, mt: +m.fighters[0].moveTime.toFixed(2), shot: ctx.cam.state.shot, cam: ctx.camera.position.toArray().map((x) => +x.toFixed(1)), fov: +ctx.camera.fov.toFixed(0),
        calls: ctx.renderer.info.render.calls, tris: ctx.renderer.info.render.triangles, p: live(), meshes, dist });
    }
    return out;
  })()`);
  const tot = rows.reduce((a, r) => a + r.ms, 0);
  log('frames', rows.length, 'total ms', tot, 'mean', (tot / rows.length).toFixed(1));
  const top = [...rows].sort((a, b) => b.ms - a.ms).slice(0, 14);
  for (const r of top) log(JSON.stringify(r));
  // timeline every 15 frames
  for (const r of rows.filter((x) => x.i % 15 === 0)) log('t', r.i, r.ms + 'ms', 'lock', r.lock, 'mt', r.mt, 'shot', r.shot, 'cam', JSON.stringify(r.cam), 'p', JSON.stringify(r.p), 'tris', r.tris);
};
