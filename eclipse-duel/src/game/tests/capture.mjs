// Deterministic game captures: node tools/shot.mjs game --scenario src/game/tests/capture.mjs [--touch --size WxH] --out shots/game/x
// SECTIONS env var (comma list) picks sections: flow, demo, heavy, ko, ult, result (default: all).
// Every section starts from a fresh state through the test API (window.__ED.game), so frames are reproducible.

export default async ({ evalJs, advance, shot, log }) => {
  const want = new Set(String(process.env.SECTIONS || 'flow,demo,heavy,ko,ult,result').split(','));
  const A = (code) => evalJs(code);
  const frames = async (label, times) => { let t = 0; for (const x of times) { await advance(x - t); t = x; await shot(`${label}_${x.toFixed(2)}`); } };

  if (want.has('flow')) {
    await A("__ED.game.title()"); await advance(1.2); await shot('title');
    await A("__ED.game.select()"); await advance(0.8); await shot('select');
    await A("__ED.game.versus('kael', 'iska', 'hard')"); await advance(0.9); await shot('vs');
  }
  if (want.has('demo')) {
    await A("__ED.game.start('kael', 'iska', { mode: 'demo', difficulty: 'hard', seed: 7 })");
    await frames('intro', [0.25, 1.0, 1.8, 2.4]);
    await frames('mid', [5, 9, 14, 20, 27]);
  }
  if (want.has('heavy')) {
    await A("__ED.game.start('kael', 'iska', { mode: 'demo', seed: 3 })");
    await A("__ED.game.skipIntro()");
    await A("__ED.game.controller(0, 'idle'); __ED.game.controller(1, 'idle'); __ED.game.place(0, -1.0, 1); __ED.game.place(1, 0.9, -1)");
    await advance(1.1);
    const id = await A("__ED.game.moveFor(0, 'heavy')");
    log('heavy move', id);
    await A(`__ED.game.forceMove(0, '${id}')`);
    await frames('heavy', [0.1, 0.25, 0.33, 0.36, 0.42, 0.55, 0.8]);
  }
  if (want.has('ko')) {
    await A("__ED.game.start('iska', 'kael', { mode: 'demo', seed: 5 })");
    await A("__ED.game.skipIntro()");
    await A("__ED.game.controller(0, 'idle'); __ED.game.controller(1, 'idle'); __ED.game.place(0, -0.9, 1); __ED.game.place(1, 0.9, -1); __ED.game.meters(1, { hp: 40 })");
    await advance(1.1);
    const id = await A("__ED.game.moveFor(0, 'heavy')");
    await A(`__ED.game.forceMove(0, '${id}')`);
    await frames('ko', [0.2, 0.3, 0.45, 0.8, 1.4, 2.2, 3.2, 4.5]);
  }
  if (want.has('ult')) {
    // ULT=kael,iska,vorn picks the users (default kael); each against the next roster fighter
    const users = String(process.env.ULT || 'kael').split(',');
    for (const u of users) {
      const foe = u === 'kael' ? 'iska' : u === 'iska' ? 'vorn' : 'kael';
      await A(`__ED.game.start('${u}', '${foe}', { mode: 'demo', seed: 11 })`);
      await A("__ED.game.skipIntro()");
      await A("__ED.game.controller(0, 'idle'); __ED.game.controller(1, 'idle'); __ED.game.place(0, -1.6, 1); __ED.game.place(1, 0.6, -1); __ED.game.meters(0, { ult: 100 })");
      await advance(1.1);
      const id = await A("__ED.game.moveFor(0, 'ult')");
      await A(`__ED.game.forceMove(0, '${id}')`);
      await frames(`ult_${u}`, [0.1, 0.4, 0.75, 0.95, 1.3, 1.9, 2.6, 3.4, 4.2, 5.0, 5.8, 6.6, 7.4]);
    }
  }
  if (want.has('result')) {
    await A("__ED.game.start('vorn', 'kael', { mode: 'demo', seed: 9 })");
    await A("__ED.game.skipIntro()");
    await A("__ED.game.round(3, [1, 1])");
    await A("__ED.game.skipIntro()");
    await A("__ED.game.controller(0, 'idle'); __ED.game.controller(1, 'idle'); __ED.game.place(0, -0.9, 1); __ED.game.place(1, 0.9, -1); __ED.game.meters(1, { hp: 30 })");
    const id = await A("__ED.game.moveFor(0, 'heavy')");
    await A(`__ED.game.forceMove(0, '${id}')`);
    await frames('final', [1.5, 4.5, 6.5, 9.5]);
    log('state', await A('__ED.game.state'));
  }
};
