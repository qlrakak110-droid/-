// Side and rear view of a hero's run cycle (sandbox, free camera travelling with the hero).
//   HERO=vorn GAIT=run node tools/shot.mjs game --as boss --size 480x480 --scenario src/rpg/tests/runsheet.mjs --sheet 8 --sheet-only --out shots/rpg/run_vorn
export default async ({ evalJs, advance, shot, log }) => {
  const hero = process.env.HERO || 'vorn', sprint = process.env.GAIT === 'sprint', view = process.env.VIEW || 'side';
  await evalJs(`__ED.rpg.start('${hero}', { sandbox: true })`);
  await evalJs('__ED.rpg.god(true); __ED.rpg.clear(); __ED.rpg.lock(null); __ED.rpg.tp(-12, 0, 0); __ED.rpg.give({ stamina: true })');
  await evalJs(`(() => { const w = __ED.rpg.world(); w.camera.worldShot((t, out) => { const h = w.hero.view.pos; ${view === 'side' ? 'out.pos.set(h.x + 0.3, 1.15, h.z + 4.2); out.look.set(h.x + 0.3, 1.0, h.z);' : 'out.pos.set(h.x - 4.2, 1.6, h.z + 0.6); out.look.set(h.x, 1.05, h.z);'} out.fov = 36; }, { dur: 99 }); })()`);
  await evalJs(`__ED.rpg.move(0, 1, 9)${sprint ? "; __ED.rpg.press('dodge', 9)" : ''}`);
  await advance(1.2);
  for (let i = 0; i < 8; i++) { await shot('f' + i); await advance(process.env.STEP ? +process.env.STEP : 0.085); }
  log(JSON.stringify(await evalJs('(() => { const s = __ED.rpg.state(); return { x: s.hero.x, z: s.hero.z, st: s.hero.state, gait: s.hero.gait, speed: s.hero.speed }; })()')));
};
