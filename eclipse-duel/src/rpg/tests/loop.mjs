// The whole expedition with the bot: altar -> gate -> cultists -> protector -> the idol -> victory. Logs the flow every
// 15 simulated seconds and the invariants at the end.
//   HERO=kael MAX=420 node tools/shot.mjs game --as boss --size 320x180 --scenario src/rpg/tests/loop.mjs
export default async ({ evalJs, advance, shot, log }) => {
  const hero = process.env.HERO || 'kael', max = +(process.env.MAX || 420);
  await evalJs(`__ED.rpg.start('${hero}', { bot: true })`);
  if (process.env.GOD) await evalJs('__ED.rpg.god(true)');
  let won = false;
  for (let t = 0; t < max && !won; t += 15) {
    await advance(15);
    const s = await evalJs('(() => { const s = __ED.rpg.state(), n = __ED.rpg.snapshot(); return { mode: s.mode, flow: s.flow, hp: Math.round(s.hero.hp), hs: s.hero.state, pills: n.hero.chalice, foes: s.foes.map((f) => f.kind + ":" + Math.round(f.hp) + ":" + f.state + (f.attack ? "/" + f.attack : "")), boss: n.boss && { hp: Math.round(n.boss.hp), phase: n.boss.phase } }; })()');
    log((t + 15) + 's ' + JSON.stringify(s));
    if (s.flow === 'victory') won = true;
    if (process.env.SHOTS && (t % 60 === 45)) await shot('t' + (t + 15));
  }
  log('checks ' + JSON.stringify(await evalJs('__ED.rpg.checks()')));
  log(won ? 'PASS victory' : 'no victory within ' + max + ' s');
};
