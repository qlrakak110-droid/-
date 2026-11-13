// RPG profile (#prof): the bot hero against three test husks, FRAMES rendered frames (default 240). Prints JS ms per
// update group (ctx.ORDER), render submit ms, draw calls and triangles (average / peak), and the program count before
// and after (nothing may compile mid-fight).
//
//   node tools/shot.mjs game --as rpg-core --hash "prof&q=high" --size 960x540 --scenario src/rpg/tests/profile.mjs
//   HERO=vorn ULT=1 ...   also fires the ultimate on a husk half way through

export default async ({ page, evalJs, advance, log }) => {
  const hero = process.env.HERO || 'kael';
  const frames = Number(process.env.FRAMES || 240);
  const R = (code) => evalJs(code);
  await R(`__ED.rpg.start('${hero}', { sandbox: true, bot: true })`);
  await R('__ED.rpg.clear(); __ED.rpg.god(true); for (const p of [[4, -2.5], [5, 0.5], [3.5, 3]]) __ED.rpg.spawn("husk", p[0], p[1])');
  await advance(2.5);
  await evalJs('__ED.render()');
  const before = await R('__ED.info()');
  await R('__ED.rpg.profReset && __ED.rpg.profReset()');
  const res = await page.evaluate(async ({ frames, ult }) => {
    const ED = window.__ED, ctx = ED.ctx;
    let calls = 0, tris = 0, pc = 0, pt = 0, js = 0, jsPeak = 0;
    for (let i = 0; i < frames; i++) {
      if (ult && i === Math.floor(frames / 3)) { ED.rpg.give({ ult: true }); ED.rpg.press('ult', 0.05); }
      // refill the pack
      if (i % 30 === 0) { const w = ED.rpg.world(); let n = 0; for (const a of w.actors) if (a.kind === 'husk' && !a.dead) n++; while (n++ < 3) ED.rpg.spawn('husk', 4 + (i % 3), (i % 5) - 2); }
      const t0 = performance.now();
      ctx.frame(1 / 60, false);
      const d = performance.now() - t0;
      js += d; if (d > jsPeak) jsPeak = d;
      const r = ED.render();
      calls += r.calls; tris += r.tris; pc = Math.max(pc, r.calls); pt = Math.max(pt, r.tris);
    }
    return { jsAvg: js / frames, jsPeak, calls: calls / frames, callsPeak: pc, tris: tris / frames, trisPeak: pt, prof: ED.rpg.prof ? ED.rpg.prof() : null, state: ED.rpg.state() };
  }, { frames, ult: !!process.env.ULT });
  const after = await R('__ED.info()');
  log(`tier ${before.tier}  frames ${frames}  JS per frame avg ${res.jsAvg.toFixed(2)} ms  peak ${res.jsPeak.toFixed(2)} ms (wall clock on a shared machine)`);
  log(`draw calls avg ${res.calls.toFixed(0)} peak ${res.callsPeak}   triangles avg ${(res.tris / 1000).toFixed(0)}k peak ${(res.trisPeak / 1000).toFixed(0)}k`);
  log(`programs ${before.programs} -> ${after.programs}   geometries ${before.geometries} -> ${after.geometries}   textures ${before.textures} -> ${after.textures}`);
  if (res.prof) log('prof ' + JSON.stringify(res.prof));
  log('state ' + JSON.stringify({ mode: res.state.mode, hero: res.state.hero.state, foes: res.state.foes.length }));
};
