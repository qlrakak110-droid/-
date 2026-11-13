// Interaction test for src/input + src/ui through the capture harness (real Playwright keyboard / CDP touch input).
//
//   node tools/shot.mjs ui --scenario src/ui/tests/interaction.mjs --out shots/ui/test_desk              (keyboard)
//   node tools/shot.mjs ui --scenario src/ui/tests/interaction.mjs --touch --size 844x390 --out shots/ui/test_touch
//
// Checks: keyboard navigation title -> select -> vs -> hud -> pause -> resume and the emitted UI events; held /
// pressed / released edges; blur releasing keys; multi-touch on the pad (stick + two buttons, released one by one)
// feeding input.held / pressed; that nothing covers the pad's controls (hit tests, also while a screen fades out);
// and that 600 hud.set / skills / combo calls with changing values add no DOM nodes. Prints PASS / FAIL per check.

export default async ({ page, evalJs, advance, shot, log }) => {
  const results = [];
  const check = (name, ok, detail = '') => { results.push({ name, ok: !!ok }); log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  ' + detail : ''}`); };
  const frame = () => advance(1 / 60);
  const raf2 = () => page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  const key = async (code) => { await page.keyboard.press(code); await frame(); };
  const touch = await evalJs('__ED.lab.ui.touch.visible');

  // event recorder
  await evalJs(`(() => { window.__T = []; const ui = __ED.lab.ui;
    for (const n of ['start', 'pick', 'vsDone', 'pause', 'resume', 'back', 'screen', 'toTitle']) ui.on(n, (...a) => __T.push([n, ...a]));
    return true; })()`);
  const events = (name) => evalJs(`__T.filter((e) => e[0] === '${name}')`);
  const screen = () => evalJs('__ED.lab.ui.screen');

  // ---------------------------------------------------------------------------------------------------------------
  // keyboard: title -> select -> vs -> hud -> pause -> resume
  await evalJs("__ED.lab.play('title')");
  await advance(0.3);
  await key('Enter');
  check('title: Enter emits start once and opens select', (await events('start')).length === 1 && (await screen()) === 'select');
  await key('KeyD');                                   // focus 염무강 -> 설리화
  check('select: D moves focus to the next card', await evalJs("__ED.lab.ui.focused().querySelector('.card-name').dataset.name === '설리화'"));
  await key('KeyJ');                                   // J = light + confirm: pick 설리화 (iska) as P1
  await key('Enter');                                  // focus moved to VORN for the CPU pick
  await key('ArrowRight');                             // difficulty normal -> hard (arrows move P1 in solo mode)
  await key('Enter');                                  // begin
  const pick = (await events('pick'))[0];
  check('select: pick event carries the keyboard choices', pick && pick[1].p1 === 'iska' && pick[1].cpu === 'vorn' && pick[1].difficulty === 'hard' && pick[1].random === false, JSON.stringify(pick && pick[1]));
  check('select -> vs', (await screen()) === 'vs');
  await key('Enter');
  check('vs: confirm before 0.8 s is ignored', (await events('vsDone')).length === 0);
  await advance(0.9);
  await key('Enter');
  await advance(3.5);
  check('vs: confirm skips, vsDone fires exactly once', (await events('vsDone')).length === 1 && (await screen()) === 'hud');
  await key('Escape');
  check('hud: Esc emits pause once (no same-frame resume)', (await events('pause')).length === 1 && (await events('resume')).length === 0 && (await screen()) === 'pause');
  await key('Escape');
  check('pause: Esc resumes', (await events('resume')).length === 1 && (await screen()) === 'hud');
  // coming back to a screen visited before shows exactly one focused item (the difficulty control was focused last time)
  await evalJs("__ED.lab.play('result'); __ED.lab.ui.show('select', { roster: __ED.lab.ui.roster })");
  await frame();
  check('return to select: exactly one focused item', (await evalJs("__ED.lab.ui.root.querySelectorAll('.is-focus').length")) === 1);

  // ---------------------------------------------------------------------------------------------------------------
  // held / pressed / released edges and blur
  await page.keyboard.down('KeyJ');
  await frame();
  const e1 = await evalJs("[__ED.ctx.input.held('light'), __ED.ctx.input.pressed('light'), __ED.ctx.input.frame(0).light]");
  await frame();
  const e2 = await evalJs("[__ED.ctx.input.held('light'), __ED.ctx.input.pressed('light')]");
  check('key down: held + pressed on the first frame, held only on the next', e1.join() === 'true,true,true' && e2.join() === 'true,false', JSON.stringify([e1, e2]));
  await page.keyboard.down('KeyA');
  await page.keyboard.down('KeyD');
  await frame();
  check('left + right cancel on the axis', (await evalJs('__ED.ctx.input.axis(0)')) === 0);
  await evalJs("window.dispatchEvent(new Event('blur'))");
  await frame();
  const b = await evalJs("[__ED.ctx.input.held('light'), __ED.ctx.input.released('light'), __ED.ctx.input.held('left'), __ED.ctx.input.held('right')]");
  check('window blur releases every held key (released edge fires)', b.join() === 'false,true,false,false', JSON.stringify(b));
  await page.keyboard.up('KeyJ'); await page.keyboard.up('KeyA'); await page.keyboard.up('KeyD');
  await frame();
  await evalJs("__ED.ctx.input.setVirtual('heavy', true, 0); __ED.ctx.input.setVirtual('heavy', false, 0)");
  await frame();
  check('a tap inside one frame still reads as pressed once', (await evalJs("__ED.ctx.input.pressed('heavy')")) === true);
  await frame();
  check('... and not on the following frame', (await evalJs("__ED.ctx.input.pressed('heavy')")) === false);

  // ---------------------------------------------------------------------------------------------------------------
  // DOM growth: 600 per-frame HUD updates with changing values (plus combo hits) add no nodes
  await evalJs("__ED.lab.play('hud')");
  await advance(0.5);
  const before = await evalJs('__ED.lab.ui.root.getElementsByTagName("*").length');
  const ms = await evalJs(`(() => { const ui = __ED.lab.ui; const t0 = performance.now(); let w = 0;
    for (let i = 0; i < 600; i++) {
      ui.hud.set({ time: 99 - i * 0.1, p1: { hp: 1000 - i * 1.3, hpMax: 1000, fp: i % 100, fpMax: 100, ult: i % 101, rounds: (i / 200) | 0 },
        p2: { hp: 1000 - i, hpMax: 1000, fp: (i * 3) % 100, fpMax: 100, ult: (i * 2) % 101, rounds: (i / 300) | 0 } });
      ui.hud.skills(0, ['kael-crescent', 'kael-eruption', 'kael-bulwark'].map((ic, j) => ({ id: ic, icon: ic, cost: 25 + j * 5, cd: ((i + j * 40) % 120) / 120 })));
      if (i % 9 === 0) ui.hud.combo(0, 2 + (i % 30), i * 7);
      if (i % 4 === 0) __ED.advance(1 / 60);
    }
    return performance.now() - t0; })()`);
  await advance(4);
  const after = await evalJs('__ED.lab.ui.root.getElementsByTagName("*").length');
  check('600 hud.set / skills / combo updates add no DOM nodes', after === before, `${before} -> ${after} nodes, ${(ms / 600).toFixed(3)} ms per update (incl. 150 sim frames)`);
  await evalJs("__ED.lab.ui.hud.announce('ko'); __ED.lab.ui.hud.announce('round', { round: 2 }); __ED.lab.ui.hud.announce('일식의 장작', { style: 'ult', side: 0 })");
  await advance(3);
  check('announcements remove their nodes when done', (await evalJs('__ED.lab.ui.root.getElementsByTagName("*").length')) === before);

  if (!touch) { summary(); return; }

  // ---------------------------------------------------------------------------------------------------------------
  // touch pad: nothing covers the controls, multi-touch (stick + two buttons) feeds input, release one by one
  await evalJs("__ED.lab.play('touch')");
  await advance(0.4);
  // a screen that is fading out must not take taps meant for the pad
  await evalJs("__ED.lab.ui.show('vs', { p1: 'kael', p2: 'iska', duration: 99 }); __ED.ctx.frame(1 / 60, false); __ED.lab.ui.show('hud')");
  const hits = await evalJs(`(() => { const out = []; const root = __ED.lab.ui.root;
    for (const el of root.querySelectorAll('.pad-btn')) {
      const r = el.getBoundingClientRect(); if (!r.width) continue;
      const x = r.left + r.width / 2, y = r.top + r.height / 2;
      const hit = document.elementFromPoint(x, y);
      out.push([el.className.split(' ')[1], !!(hit && hit.closest('.pad-btn') === el)]);
    }
    const z = root.querySelector('.pad-zone').getBoundingClientRect();
    const hz = document.elementFromPoint(z.left + z.width * 0.35, z.top + z.height * 0.6);
    out.push(['stick zone', !!(hz && hz.closest('.pad-zone'))]);
    return out; })()`);
  const blocked = hits.filter((x) => !x[1]).map((x) => x[0]);
  check('every pad control receives its own hit (also during a screen fade)', hits.length >= 9 && blocked.length === 0, blocked.length ? 'blocked: ' + blocked.join(', ') : `${hits.length} targets`);
  await advance(0.3);

  const cdp = await page.context().newCDPSession(page);
  const P = await evalJs(`(() => { const q = (s) => { const r = __ED.lab.ui.root.querySelector(s).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; };
    const z = __ED.lab.ui.root.querySelector('.pad-zone').getBoundingClientRect();
    return { stick: [z.left + z.width * 0.45, z.top + z.height * 0.55], light: q('.pb-light'), skill1: q('.pb-skill1') }; })()`);
  const pt = (id, [x, y]) => ({ x: Math.round(x), y: Math.round(y), id, radiusX: 4, radiusY: 4, force: 1 });
  const touchEv = async (type, points) => { await cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points }); await raf2(); };
  const held = () => evalJs("['right', 'left', 'light', 'skill1', 'up', 'down'].filter((a) => __ED.ctx.input.held(a))");
  const sRight = [P.stick[0] + 60, P.stick[1]];
  await touchEv('touchStart', [pt(1, P.stick)]);
  await touchEv('touchMove', [pt(1, sRight)]);
  await touchEv('touchStart', [pt(1, sRight), pt(2, P.light)]);
  await touchEv('touchStart', [pt(1, sRight), pt(2, P.light), pt(3, P.skill1)]);
  await frame();
  const h1 = await held();
  const p1 = await evalJs("[__ED.ctx.input.pressed('light'), __ED.ctx.input.pressed('skill1'), __ED.ctx.input.axis(0), __ED.ctx.input.device]");
  check('multi-touch: stick right + light + skill1 held together', h1.join() === 'right,light,skill1', JSON.stringify(h1));
  check('multi-touch: buttons read as pressed, axis +1, device touch', p1.join() === 'true,true,1,touch', JSON.stringify(p1));
  await shot('multitouch_down');
  await frame();
  check('pressed clears on the next frame while still held', (await evalJs("__ED.ctx.input.pressed('light') || __ED.ctx.input.pressed('skill1')")) === false && (await held()).join() === 'right,light,skill1');
  await touchEv('touchEnd', [pt(2, P.light)]);
  await frame();
  const h2 = await held();
  check('lifting one finger releases only its button', h2.join() === 'right,skill1' && (await evalJs("__ED.ctx.input.released('light')")) === true, JSON.stringify(h2));
  await touchEv('touchEnd', [pt(1, sRight)]);
  await frame();
  check('lifting the stick finger releases the direction', (await held()).join() === 'skill1');
  await touchEv('touchEnd', [pt(3, P.skill1)]);
  await frame();
  check('all fingers up: nothing held', (await held()).length === 0);
  await shot('multitouch_up');
  // the stick's vertical sector is strict: a mostly-horizontal drag does not press up / down
  await touchEv('touchStart', [pt(4, P.stick)]);
  await touchEv('touchMove', [pt(4, [P.stick[0] + 50, P.stick[1] - 22])]);
  await frame();
  const diag = await held();
  await touchEv('touchMove', [pt(4, [P.stick[0] + 30, P.stick[1] - 52])]);
  await frame();
  const diag2 = await held();
  await touchEv('touchEnd', [pt(4, [P.stick[0] + 30, P.stick[1] - 52])]);
  await frame();
  check('stick: shallow up-right = right only; steep up-right = right + up', diag.join() === 'right' && diag2.join() === 'right,up', JSON.stringify([diag, diag2]));
  // a held button is released when the pad hides (screen change) and on window blur
  await touchEv('touchStart', [pt(5, P.light)]);
  await frame();
  await evalJs("window.dispatchEvent(new Event('blur'))");
  await frame();
  check('window blur releases a held pad button', (await held()).length === 0);
  await touchEv('touchEnd', [pt(5, P.light)]);
  await frame();

  summary();

  function summary() {
    const bad = results.filter((r) => !r.ok);
    log(`${results.length - bad.length}/${results.length} checks passed`);
    if (bad.length) throw new Error('interaction test failed: ' + bad.map((r) => r.name).join('; '));
  }
};
