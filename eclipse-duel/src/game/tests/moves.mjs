// Move-by-move review: fighter P1 performs every MOVES.md slot against an idle P2, captured at the wind-up, the first
// active frame and the follow-through (labels: <fighter>_<slot>_<phase>).
//   FIGHTERS=kael,iska,vorn SLOTS=light1,light2,... node tools/shot.mjs game --size 960x540 --scenario src/game/tests/moves.mjs --sheet --sheet-only --out shots/game/moves
// Also: GUARD=1 (P2 blocks a string, then its guard breaks), DOWN=1 (knockdown, lying, get-up).
export default async ({ evalJs, advance, shot, log }) => {
  const A = (c) => evalJs(c);
  const fighters = String(process.env.FIGHTERS || 'kael,iska,vorn').split(',');
  const slots = String(process.env.SLOTS || 'light1,light2,light3,heavy,fheavy,dheavy,skill1,skill2,skill3').split(',');
  for (const id of fighters) {
    const foe = id === 'iska' ? 'kael' : 'iska';
    await A(`__ED.game.start('${id}', '${foe}', { mode: 'demo', seed: 21 })`);
    await A('__ED.game.skipIntro()');
    await A("__ED.game.controller(0, 'idle'); __ED.game.controller(1, 'idle')");
    for (const slot of slots) {
      const mv = await A(`__ED.game.moveFor(0, '${slot}')`);
      if (!mv) { log(id, slot, 'no move'); continue; }
      const far = /skill1|skill2/.test(slot) ? 4.2 : /fheavy/.test(slot) ? 3.4 : 2.0;
      await A(`__ED.game.place(0, ${(-far / 2).toFixed(2)}, 1); __ED.game.place(1, ${(far / 2).toFixed(2)}, -1); __ED.game.meters(0, { fp: 100 }); __ED.game.meters(1, { hp: 900 })`);
      await advance(0.6);
      const fd = await A(`(() => { const s = __ED.game.session(); const mc = s.actors[0].clips.move('${mv}'); return { startup: mc.startup, end: mc.frame.activeEnd ?? mc.startup + 0.1, dur: s.match.defs[0].moves['${mv}'].duration, clip: mc.name }; })()`);
      log(id, slot, mv, JSON.stringify(fd));
      await A(`__ED.game.forceMove(0, '${mv}')`);
      const t1 = Math.max(0.05, fd.startup - 0.07), t2 = fd.startup + 0.017, t3 = Math.min(fd.dur - 0.05, Math.max(fd.end + 0.1, fd.startup + 0.2));
      await advance(t1); await shot(`${id}_${slot}_a`);
      await advance(t2 - t1); await shot(`${id}_${slot}_b`);
      await advance(t3 - t2); await shot(`${id}_${slot}_c`);
      await advance(Math.max(0.3, fd.dur - t3 + 0.5));
    }
  }
  if (process.env.GUARD) {
    const id = fighters[0];
    await A(`__ED.game.start('${id}', 'vorn', { mode: 'demo', seed: 22 })`);
    await A('__ED.game.skipIntro()');
    await A("__ED.game.controller(0, 'idle'); __ED.game.controller(1, 'human'); __ED.ctx.input.setVirtual('guard', true, 1); __ED.game.place(0, -0.9, 1); __ED.game.place(1, 0.9, -1)");
    await advance(0.5);
    await A(`__ED.game.forceMove(0, __ED.game.moveFor(0, 'heavy'))`);
    const st = await A(`__ED.game.session().actors[0].clips.move(__ED.game.moveFor(0, 'heavy')).startup`);
    await advance(st + 0.02); await shot('guard_block');
    await advance(0.2); await shot('guard_after');
    await advance(1.0);
    await A("__ED.game.meters(1, { guard: 3 })");
    await A(`__ED.game.forceMove(0, __ED.game.moveFor(0, 'heavy'))`);
    await advance(st + 0.02); await shot('guardbreak_0');
    await advance(0.15); await shot('guardbreak_1');
    await advance(0.5); await shot('guardbreak_2');
    await A("__ED.ctx.input.setVirtual('guard', false, 1)");
  }
  if (process.env.DOWN) {
    const id = fighters[0];
    await A(`__ED.game.start('${id}', 'kael', { mode: 'demo', seed: 23 })`);
    await A('__ED.game.skipIntro()');
    await A("__ED.game.controller(0, 'idle'); __ED.game.controller(1, 'idle'); __ED.game.place(0, -0.9, 1); __ED.game.place(1, 0.9, -1)");
    await advance(0.5);
    const times = [0.3, 0.55, 0.85, 1.15, 1.5, 1.85, 2.2];
    let last = 0;
    await A(`__ED.game.forceMove(0, __ED.game.moveFor(0, '${process.env.DOWN_SLOT || 'dheavy'}'))`);
    for (const t of times) {
      await advance(t - last); last = t;
      const s = await A('(() => { const f = __ED.game.match().fighters[1]; return f.state + " y=" + f.y.toFixed(2) + " " + __ED.game.session().actors[1].char.clip; })()');
      log('down', t, s);
      await shot(`down_${t.toFixed(2)}`);
    }
  }
};
