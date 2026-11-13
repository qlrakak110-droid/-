// Regression: the duel still boots and plays with the RPG mode installed, and the hand-over is clean both ways.
//   title (capture: the 강호행 entry) -> keyboard: select -> vs -> match, P1 walks and attacks, pause / resume
//   -> title -> the expedition entry (ui event) -> RPG runs -> back to the title -> a duel match again (fight framing,
//      VFX wrappers gone, input mode 'solo').
//
//   node tools/shot.mjs game --as rpg-core --size 960x540 --scenario src/rpg/tests/duel.mjs --out shots/rpg/core/duel

export default async ({ page, evalJs, advance, shot, log }) => {
  let pass = 0, fail = 0;
  const check = (name, ok, info = '') => { if (ok) pass++; else fail++; log(`${ok ? 'PASS' : 'FAIL'} ${name}${info ? '  ' + info : ''}`); };
  const key = async (code, hold = 0.05) => { await page.keyboard.down(code); await advance(hold); await page.keyboard.up(code); await advance(0.12); };
  const st = () => evalJs('[__ED.game.state, __ED.game.screen]');
  await advance(2.0);
  let s = await st();
  check('boots to the title', s[0] === 'title' && s[1] === 'title', JSON.stringify(s));
  const entry = await evalJs('(() => { const b = document.querySelectorAll(".tt-exp-btn"); return { n: b.length, labels: [...b].map((x) => x.textContent) }; })()');
  check('title has the expedition entry', entry.n === 3, JSON.stringify(entry));
  if (!process.env.NOSHOT) await shot('title');
  // the duel by keyboard
  await key('Enter'); await advance(0.4);
  s = await st();
  check('start -> select', s[0] === 'select', JSON.stringify(s));
  for (let i = 0; i < 6 && (await evalJs('__ED.game.state')) === 'select'; i++) { await key('Enter'); await advance(0.3); }
  await advance(4.5);
  s = await st();
  check('select -> match', s[0] === 'match' && s[1] === 'hud', JSON.stringify(s));
  await advance(2.5);
  const x0 = await evalJs('__ED.game.snapshot().fighters[0].x');
  await page.keyboard.down('KeyD'); await advance(0.6); await page.keyboard.up('KeyD');
  await key('KeyJ'); await advance(0.2); await key('KeyJ'); await advance(0.3);
  const x1 = await evalJs('__ED.game.snapshot().fighters[0].x');
  const ev = await evalJs("__ED.game.events().filter((n) => n === 'moveStart').length");
  check('P1 walks and attacks', x1 > x0 + 0.5 && ev >= 1, `x ${x0} -> ${x1}, moveStart ${ev}`);
  // the arrow keys still move P1 in the duel (mode 'solo'), Q / R / E do nothing
  await page.keyboard.down('ArrowLeft'); await advance(0.4); await page.keyboard.up('ArrowLeft');
  const x2 = await evalJs('__ED.game.snapshot().fighters[0].x');
  check('arrows move in the duel', x2 < x1 - 0.2, `x ${x1} -> ${x2}`);
  await key('Escape'); await advance(0.4);
  s = await st();
  check('pause', s[0] === 'pause' && (await evalJs('__ED.ctx.time.baseScale')) === 0, JSON.stringify(s));
  await key('Escape'); await advance(0.3);
  s = await st();
  check('resume', s[0] === 'match' && (await evalJs('__ED.ctx.time.baseScale')) === 1, JSON.stringify(s));
  // to the title, into the RPG through the title entry, and back
  await evalJs('__ED.game.title()');
  await advance(1.5);
  await evalJs('__ED.ctx.ui.emit("expedition", "iska")');
  await advance(1.0);
  let r = await evalJs('__ED.rpg.state()');
  check('expedition entry starts the RPG', r.mode === 'play' && r.hero && r.hero.id === 'iska' && (await evalJs('__ED.game.state')) === 'rpg' && (await evalJs('__ED.ctx.cam.mode')) === 'free' && (await evalJs('__ED.ctx.input.mode')) === 'rpg',
    JSON.stringify({ mode: r.mode, hero: r.hero && r.hero.id, game: await evalJs('__ED.game.state'), cam: await evalJs('__ED.ctx.cam.mode'), input: await evalJs('__ED.ctx.input.mode') }));
  await evalJs('__ED.rpg.move(0, 1)'); await advance(1.0); await evalJs('__ED.rpg.move(0, 0)');
  // Esc pauses the RPG, the pause panel returns to the title
  await key('Escape'); await advance(0.2);
  r = await evalJs('__ED.rpg.state()');
  check('Esc pauses the RPG', r.mode === 'pause', r.mode);
  await evalJs('__ED.rpg.stop()');
  await advance(1.5);
  s = await st();
  const after = { game: s, cam: await evalJs('__ED.ctx.cam.mode'), input: await evalJs('__ED.ctx.input.mode'), stage: await evalJs('!!__ED.ctx.vfx.__stageInstalled'), scale: await evalJs('__ED.ctx.time.baseScale'), fov: await evalJs('__ED.ctx.camera.fov'), rpg: await evalJs('__ED.rpg.mode') };
  check('back at the title, everything restored', s[0] === 'title' && after.cam !== 'free' && after.input === 'solo' && !after.stage && after.scale === 1 && after.rpg === 'off', JSON.stringify(after));
  // a duel again
  await evalJs('__ED.game.start("kael", "vorn", { mode: "demo" })');
  await evalJs('__ED.game.skipIntro()');
  await advance(4);
  const snap = await evalJs('(() => { const m = __ED.game.snapshot(); return { phase: m.phase, hp: m.fighters.map((f) => f.hp), ev: __ED.game.events().length }; })()');
  check('a duel plays after the RPG', snap.ev > 5 && (await evalJs('__ED.ctx.cam.mode')) !== 'free', JSON.stringify(snap));
  if (!process.env.NOSHOT) await shot('duel_after');
  log(`RESULT ${pass} passed, ${fail} failed`);
};
