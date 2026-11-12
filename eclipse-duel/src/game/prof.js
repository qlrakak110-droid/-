// #prof: per-update-group CPU timing (ctx.onUpdate callbacks grouped by ctx.ORDER), render submit time and
// renderer.info, logged every 2 s as `[ed] prof ...` and readable through __ED.game.prof().
// Installed right after createApp, before any module registers its update, by wrapping ctx.onUpdate.

const GROUPS = ['INPUT', 'GAME', 'CHAR', 'VFX', 'CAM', 'ENV', 'UI', 'POST'];

/**
 * @param {object} ctx
 * @param {{ log?: boolean, interval?: number }} [opts]
 * @returns {{ report(): object, reset(): void }}
 */
export function installProfiler(ctx, opts = {}) {
  const O = ctx.ORDER;
  const groupOf = (order) => {
    let best = 'INPUT';
    for (const g of GROUPS) if (order >= O[g]) best = g;
    return best;
  };
  const acc = {}, peak = {};
  for (const g of GROUPS) { acc[g] = 0; peak[g] = 0; }
  acc.RENDER = 0; peak.RENDER = 0;
  let frames = 0, frameJs = 0, framePeak = 0, cur = 0;
  let calls = 0, tris = 0, last = performance.now();
  const now = () => performance.now();

  const orig = ctx.onUpdate.bind(ctx);
  ctx.onUpdate = (fn, order = O.GAME) => {
    const g = groupOf(order);
    return orig((dg, dr) => {
      const t0 = now();
      fn(dg, dr);
      const d = now() - t0;
      acc[g] += d; cur += d;
      if (d > peak[g]) peak[g] = d;
    }, order);
  };
  const post = ctx.post;
  const render = post.render.bind(post);
  post.render = (scene, camera) => {
    const t0 = now();
    render(scene, camera);
    const d = now() - t0;
    acc.RENDER += d;
    if (d > peak.RENDER) peak.RENDER = d;
    const i = ctx.renderer.info.render;
    calls += i.calls; tris += i.triangles;
    frames++;
    frameJs += cur;
    if (cur > framePeak) framePeak = cur;
    cur = 0;
    if (opts.log !== false && !ctx.test && now() - last > (opts.interval || 2000)) { console.log('[ed] prof ' + JSON.stringify(report())); reset(); }
  };

  function report() {
    const n = Math.max(1, frames);
    const out = { tier: ctx.quality.tier, frames, fps: Math.round(ctx.stats.fps), jsMs: +(frameJs / n).toFixed(3), jsPeakMs: +framePeak.toFixed(2), renderMs: +(acc.RENDER / n).toFixed(3), calls: Math.round(calls / n), tris: Math.round(tris / n), groups: {} };
    for (const g of GROUPS) out.groups[g] = { ms: +(acc[g] / n).toFixed(3), peak: +peak[g].toFixed(2) };
    return out;
  }
  function reset() {
    for (const g of GROUPS) { acc[g] = 0; peak[g] = 0; }
    acc.RENDER = 0; peak.RENDER = 0;
    frames = 0; frameJs = 0; framePeak = 0; cur = 0; calls = 0; tris = 0; last = now();
  }
  return { report, reset };
}
