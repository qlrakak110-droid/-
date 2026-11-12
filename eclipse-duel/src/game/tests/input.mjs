// Every human action through the input path (ctx.input.setVirtual, the keyboard, the touch pad), checked against the
// rules state and event stream; prints PASS / FAIL per check.
//   node tools/shot.mjs game --scenario src/game/tests/input.mjs --out shots/game/input
//   node tools/shot.mjs game --touch --size 844x390 --scenario src/game/tests/input.mjs --out shots/game/input_land   (TOUCH=1 checks)
// FIGHTER (default kael) is P1. Sections: actions (walk, dash, backstep, dodge, guard, the light chain, every heavy
// and skill, the ultimate), pause / resume, quit to title, title -> select -> versus -> KO -> result -> rematch,
// result -> select, touch pad (with --touch).
export default async ({ page, evalJs, advance, shot, log }) => {
  const A = (c) => evalJs(c);
  const id = process.env.FIGHTER || 'kael';
  let fails = 0;
  const check = (name, ok, info = '') => { if (!ok) fails++; log(`${ok ? 'PASS' : 'FAIL'} ${name}${info ? '  ' + info : ''}`); };
  const set = (actions, down) => A(`(() => { for (const a of ${JSON.stringify(actions)}) __ED.ctx.input.setVirtual(a, ${down}, 0); return 1; })()`);
  const tap = async (actions, holdSec = 1 / 30) => { await set(actions, true); await advance(holdSec); await set(actions, false); await advance(1 / 60); };
  const f0 = () => A('(() => { const f = __ED.game.match().fighters[0]; return { x: +f.x.toFixed(3), state: f.state, move: f.move, walkDir: f.walkDir, clip: __ED.game.session().actors[0].char.clip }; })()');
  const evs = () => A('window.__ev.splice(0)');
  const hook = () => A(`(() => { window.__ev = []; __ED.game.match().on('*', (n, e) => { if (/^(moveStart|dodge|superFreezeStart|cinematicStart|hit|state)$/.test(n)) window.__ev.push([n, e.fighter ?? e.attacker, e.move || e.kind || e.to || '']); }); return 1; })()`);
  const settle = async () => {
    for (let k = 0; k < 40; k++) { const s = (await f0()).state; if (s === 'idle') break; await advance(0.1); }
    await A("__ED.game.place(0, -1.2, 1); __ED.game.place(1, 1.2, -1); __ED.game.meters(1, { hp: 900, guard: 100 })");
    await advance(0.25); await evs();
  };
  const moveId = (slot) => A(`__ED.game.moveFor(0, '${slot}')`);

  if (process.env.TOUCH) {
    await A(`__ED.game.start('${id}', 'iska', { mode: 'training', seed: 5 })`);
    await A('__ED.game.skipIntro()'); await hook();
    await A("__ED.game.controller(0, 'human')");
    await advance(0.3);
    const pad = await A("(() => { const p = document.querySelector('.ed-pad'); const r = p && p.getBoundingClientRect(); return p ? { vis: getComputedStyle(p).display !== 'none' && getComputedStyle(p).visibility !== 'hidden', w: r.width, h: r.height } : null; })()");
    check('touch pad shown in the fight', !!pad && pad.vis, JSON.stringify(pad));
    await settle();
    const btn = async (a) => A(`(() => { const b = document.querySelector('.pad-btn.pb-${a}'); if (!b) return null; const r = b.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width }; })()`);
    for (const [a, slot] of [['light', 'light1'], ['heavy', 'heavy'], ['skill1', 'skill1']]) {
      await settle();
      const b = await btn(a);
      if (!b) { check(`touch ${a} button exists`, false); continue; }
      await page.touchscreen.tap(b.x, b.y);
      await advance(0.1);
      const e = await evs();
      const want = await moveId(slot);
      check(`touch ${a} -> ${want}`, e.some((x) => x[0] === 'moveStart' && x[1] === 0 && x[2] === want), `button ${Math.round(b.w)}px at ${Math.round(b.x)},${Math.round(b.y)}`);
    }
    // the stick: a finger lands on the left zone and drags right, held 0.5 s
    await settle();
    const zone = await A("(() => { const z = document.querySelector('.pad-zone'); const r = z.getBoundingClientRect(); return { x: r.x + r.width * 0.4, y: r.y + r.height * 0.6 }; })()");
    const cdp = await page.context().newCDPSession(page);
    const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y, id: 1 }] });
    const x0 = (await f0()).x;
    await touch('touchStart', zone.x, zone.y); await advance(1 / 60);
    await touch('touchMove', zone.x + 30, zone.y); await advance(1 / 60);
    await touch('touchMove', zone.x + 70, zone.y + 2); await advance(0.5);
    const mid = await f0();
    await shot('touch_walk');
    await touch('touchEnd', 0, 0); await advance(0.2);
    check('touch stick right -> walk forward', mid.state === 'walk' && mid.x > x0 + 0.4, JSON.stringify(mid) + ' from x ' + x0);
    await shot('touch_pad');
    log(fails ? `${fails} FAILED` : 'ALL PASS');
    return;
  }

  // ---- actions (training: P2 idle dummy, infinite FP / ULT) -------------------------------------------------------
  await A(`__ED.game.start('${id}', 'iska', { mode: 'training', seed: 5 })`);
  await A('__ED.game.skipIntro()'); await hook();
  await settle();
  let s = await f0();
  await set(['right'], true); await advance(0.5);
  const w = await f0(); await set(['right'], false); await advance(0.3);
  check('walk forward', w.state === 'walk' && w.walkDir === 1 && w.x > s.x + 0.5 && /walkF/.test(w.clip), JSON.stringify(w));
  s = await f0();
  await set(['left'], true); await advance(0.5);
  const wb = await f0(); await set(['left'], false); await advance(0.3);
  check('walk back', wb.state === 'walk' && wb.walkDir === -1 && wb.x < s.x - 0.4 && /walkB/.test(wb.clip), JSON.stringify(wb));
  for (const [name, acts, kind] of [['dash (dodge + forward)', ['dodge', 'right'], 'dash'], ['backstep (dodge + back)', ['dodge', 'left'], 'backstep'], ['dodge', ['dodge'], 'dodge']]) {
    await settle(); await advance(0.8);
    await tap(acts, 0.05); await advance(0.1);
    const e = await evs();
    check(name, e.some((x) => x[0] === 'dodge' && x[1] === 0 && x[2] === kind), JSON.stringify(e.filter((x) => x[1] === 0).slice(0, 4)));
  }
  await settle();
  await set(['guard'], true); await advance(0.4);
  const g = await f0(); await set(['guard'], false); await advance(0.2);
  check('guard (held)', g.state === 'guard' && /guard|block/i.test(g.clip), JSON.stringify(g));

  // the light chain: presses inside the cancel windows
  await settle();
  const chain = [await moveId('light1'), await moveId('light2'), await moveId('light3')];
  for (let k = 0; k < 3; k++) { await tap(['light']); await advance(0.16); }
  await advance(0.8);
  const ce = (await evs()).filter((x) => x[0] === 'moveStart' && x[1] === 0).map((x) => x[2]);
  check('light chain light1 > light2 > light3', chain.every((m, k) => ce[k] === m), JSON.stringify(ce) + ' want ' + JSON.stringify(chain));

  for (const [slot, acts] of [['heavy', ['heavy']], ['fheavy', ['right', 'heavy']], ['dheavy', ['down', 'heavy']], ['skill1', ['skill1']], ['skill2', ['skill2']], ['skill3', ['skill3']]]) {
    await settle();
    if (acts.length > 1) { await set([acts[0]], true); await advance(1 / 30); }
    await tap([acts[acts.length - 1]]);
    if (acts.length > 1) await set([acts[0]], false);
    await advance(0.1);
    const want = await moveId(slot);
    const e = await evs();
    check(`${slot} (${acts.join('+')}) -> ${want}`, e.some((x) => x[0] === 'moveStart' && x[1] === 0 && x[2] === want), JSON.stringify(e.filter((x) => x[0] === 'moveStart')));
    await advance(1.2);
  }
  await settle();
  await A("__ED.game.place(0, -1.0, 1); __ED.game.place(1, 1.0, -1)");
  await tap(['ult']); await advance(0.3);
  let e = await evs();
  check('ult -> super-freeze', e.some((x) => x[0] === 'superFreezeStart' && x[1] === 0), JSON.stringify(e.filter((x) => x[0] !== 'state').slice(0, 4)));
  await shot('ult_freeze');
  await advance(1.6);
  e = await evs();
  check('ult -> cinematic lock on the idle dummy', e.some((x) => x[0] === 'cinematicStart'), JSON.stringify(e.filter((x) => x[0] !== 'state').slice(0, 6)));
  await advance(6.5);
  const cam = await A('[__ED.ctx.cam.mode, +__ED.ctx.post.fx.letterbox.toFixed(2), __ED.ctx.env.mood ? +__ED.ctx.env.mood.darken.toFixed(2) : 0]');
  check('after the ultimate: fight camera, no letterbox, world mood restored', cam[0] === 'fight' && cam[1] < 0.02 && cam[2] < 0.02, JSON.stringify(cam));

  // ---- pause / resume with the keyboard ----------------------------------------------------------------------------
  const t0 = await A('__ED.game.match().time');
  await page.keyboard.press('Escape'); await advance(0.4);
  const ps = await A('[__ED.game.state, __ED.game.screen, __ED.ctx.time.baseScale, __ED.game.match().time]');
  await advance(1.0);
  const t1 = await A('__ED.game.match().time');
  check('Esc pauses (time frozen)', ps[0] === 'pause' && ps[1] === 'pause' && ps[2] === 0 && Math.abs(t1 - ps[3]) < 1e-6, JSON.stringify(ps) + ' t ' + t0 + ' -> ' + t1);
  await shot('pause');
  await page.keyboard.press('Escape'); await advance(0.4);
  const rs = await A('[__ED.game.state, __ED.game.screen, __ED.ctx.time.baseScale]');
  check('Esc resumes', rs[0] === 'match' && rs[1] === 'hud' && rs[2] === 1, JSON.stringify(rs));

  // ---- the tab is hidden mid-fight: the game pauses itself ----------------------------------------------------------
  await A("(() => { Object.defineProperty(document, 'hidden', { value: true, configurable: true }); document.dispatchEvent(new Event('visibilitychange')); return 1; })()");
  await advance(0.3);
  const hs = await A('[__ED.game.state, __ED.game.screen, __ED.ctx.time.baseScale]');
  await A("(() => { Object.defineProperty(document, 'hidden', { value: false, configurable: true }); document.dispatchEvent(new Event('visibilitychange')); return 1; })()");
  check('hidden tab pauses', hs[0] === 'pause' && hs[1] === 'pause' && hs[2] === 0, JSON.stringify(hs));
  await page.keyboard.press('Escape'); await advance(0.4);

  // ---- HUD shows live values (timer, HP after a hit) ----------------------------------------------------------------
  await settle();
  await A("__ED.game.place(0, -0.9, 1); __ED.game.place(1, 0.9, -1); __ED.game.meters(1, { hp: 700 })");
  await tap(['heavy']); await advance(1.2);
  const hud = await A(`(() => {
    const m = __ED.game.match(), f = m.fighters[1];
    const bars = [...document.querySelectorAll('#ui .hp-fill')].map((e) => e.style.transform);
    const timer = [...document.querySelectorAll('#ui .tm-num')].map((e) => e.textContent.trim());
    return { hp: Math.round(f.hp), hpMax: f.hpMax, ratio: +(f.hp / f.hpMax).toFixed(3), bars, timer, clock: m.clock };
  })()`);
  check('HUD HP bar follows the rules HP', hud.bars.some((t) => Math.abs(parseFloat(t.replace(/.*scaleX\(/, '')) - hud.ratio) < 0.02), JSON.stringify(hud));
  check('HUD timer is the round clock (training: infinite)', hud.timer.includes('∞'), JSON.stringify(hud.timer));

  // ---- quit to title from the pause menu (two-step confirm), by mouse ------------------------------------------------
  const clickText = async (re) => {
    const r = await A(`(() => { const b = [...document.querySelectorAll('#ui button')].find((x) => ${re}.test(x.textContent) && x.offsetParent); if (!b) return null; const q = b.getBoundingClientRect(); return { x: q.x + q.width / 2, y: q.y + q.height / 2, t: b.textContent.trim().slice(0, 40) }; })()`);
    if (r) { await page.mouse.click(r.x, r.y); await advance(0.25); }
    return r;
  };
  await page.keyboard.press('Escape'); await advance(0.4);
  const q1 = await clickText('/QUIT TO TITLE/');
  const q2 = await clickText('/PRESS AGAIN|QUIT/');
  await advance(0.5);
  const ts = await A('[__ED.game.state, __ED.game.screen, __ED.ctx.time.baseScale, __ED.game.session().mode]');
  check('pause > quit to title (confirm)', ts[0] === 'title' && ts[1] === 'title' && ts[2] === 1 && ts[3] === 'showcase', JSON.stringify(ts) + ' clicked ' + JSON.stringify([q1 && q1.t, q2 && q2.t]));

  // ---- title -> select -> vs -> match by keyboard, then KO -> result -> rematch ------------------------------------
  await page.keyboard.press('Enter'); await advance(0.4);
  for (let k = 0; k < 6 && (await A('__ED.game.state')) === 'select'; k++) { await page.keyboard.press('Enter'); await advance(0.35); }
  const vs = await A('[__ED.game.state, __ED.game.screen]');
  check('title > select > vs (Enter)', vs[0] === 'vs' && vs[1] === 'vs', JSON.stringify(vs));
  await advance(3.6);
  const ms = await A('[__ED.game.state, __ED.game.screen, __ED.game.match().phase, __ED.game.session().mode]');
  check('vs > match (HUD, round intro)', ms[0] === 'match' && ms[1] === 'hud' && ms[3] === 'versus', JSON.stringify(ms));
  await A('__ED.game.skipIntro()'); await hook();
  await A("__ED.game.controller(1, 'idle'); __ED.game.round(2, [1, 0])");
  await A('__ED.game.skipIntro()');
  await A("__ED.game.place(0, -0.9, 1); __ED.game.place(1, 0.9, -1); __ED.game.meters(1, { hp: 5 })");
  await advance(0.2);
  await tap(['heavy']);
  await advance(9);
  const rr = await A('[__ED.game.state, __ED.game.screen, __ED.game.match().phase, __ED.game.match().winner]');
  check('KO in the deciding round > result screen', rr[0] === 'result' && rr[1] === 'result' && rr[3] === 0, JSON.stringify(rr));
  await shot('result');
  const rm = await clickText('/REMATCH/');
  await advance(0.5);
  const after = await A('[__ED.game.state, __ED.game.screen, __ED.game.match().round, __ED.game.match().fighters.map((f) => f.rounds + ":" + f.hp), __ED.game.match().phase]');
  check('result > rematch (round 1, full HP)', after[0] === 'match' && after[1] === 'hud' && after[2] === 1 && after[3].every((x) => x.startsWith('0:')), JSON.stringify(after) + ' via ' + (rm && rm.t));
  // result > select
  await A("__ED.game.round(2, [1, 0])"); await A('__ED.game.skipIntro()');
  await A("__ED.game.controller(1, 'idle'); __ED.game.place(0, -0.9, 1); __ED.game.place(1, 0.9, -1); __ED.game.meters(1, { hp: 5 })");
  await tap(['heavy']); await advance(9);
  const sl = await clickText('/SELECT|선택/');
  await advance(0.6);
  const ss = await A('[__ED.game.state, __ED.game.screen, __ED.game.session().mode]');
  check('result > character select', ss[0] === 'select' && ss[1] === 'select' && ss[2] === 'showcase', JSON.stringify(ss) + ' via ' + (sl && sl.t));
  log(fails ? `${fails} FAILED` : 'ALL PASS');
};
