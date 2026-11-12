// Frame-time profile: node tools/shot.mjs game --hash "prof&q=high" --size 640x360 --scenario src/game/tests/profile.mjs
// Two phases, each rendered frame by frame (1/60 s) with __ED.game.prof() (JS ms per update group, render submit ms,
// draw calls, triangles incl. the shadow pass) and per-frame peaks:
//   fight  FRAMES (default 240) frames of a hard-AI match (P1 / P2 from PAIR, default kael:iska), after the intro
//   ult    the whole ultimate of P1 (super-freeze, lock, finish, aftermath: ULT_FRAMES, default 420) on an idle P2
// CPU numbers are real JS cost; GPU time is not meaningful under SwiftShader. Resolution does not change them.
export default async ({ evalJs, advance, log }) => {
  const [p1, p2] = String(process.env.PAIR || 'kael:iska').split(':');
  const n = Number(process.env.FRAMES || 240), nu = Number(process.env.ULT_FRAMES || 420);
  const measure = (frames) => evalJs(`(() => {
    __ED.game.profReset();
    const t0 = performance.now(); let peakCalls = 0, peakTris = 0, peakJs = 0;
    for (let i = 0; i < ${frames}; i++) {
      const a = performance.now();
      __ED.ctx.frame(1 / 60, true);
      const r = __ED.ctx.renderer.info.render;
      peakCalls = Math.max(peakCalls, r.calls); peakTris = Math.max(peakTris, r.triangles);
      peakJs = Math.max(peakJs, performance.now() - a);
    }
    const p = __ED.game.prof();
    return { ...p, wallMsPerFrame: +((performance.now() - t0) / ${frames}).toFixed(2), peakFrameMs: +peakJs.toFixed(1), peakCalls, peakTris };
  })()`);
  await evalJs(`__ED.game.start('${p1}', '${p2}', { mode: 'demo', difficulty: 'hard', seed: 4 })`);
  await advance(3);
  const fight = await measure(n);
  log('fight', JSON.stringify(fight));
  await evalJs("__ED.game.controller(0, 'idle'); __ED.game.controller(1, 'idle')");
  await advance(1.2);
  const prog0 = await evalJs('__ED.info().programs');
  await evalJs("__ED.game.place(0, -1.4, 1); __ED.game.place(1, 0.6, -1); __ED.game.meters(0, { ult: 100 }); __ED.game.forceMove(0, __ED.game.moveFor(0, 'ult'))");
  const ult = await measure(nu);
  log('ult', JSON.stringify(ult));
  const chars = await evalJs('__ED.game.session().actors.map((a) => ({ id: a.fighter.id, design: a.fighter.sources.design, ...a.char.stats }))');
  const info = await evalJs('__ED.info()');
  log('chars', JSON.stringify(chars), 'programs before / after the ultimate', prog0, info.programs, JSON.stringify(info));
};
