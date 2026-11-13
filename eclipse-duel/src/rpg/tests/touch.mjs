// Touch controls smoke test (run with --touch --size 844x390): the stick moves the hero, the seals act.
export default async ({ page, evalJs, advance, shot, log }) => {
  await evalJs(`__ED.rpg.start('kael', { sandbox: true })`);
  await advance(0.6);
  const cdp = await page.context().newCDPSession(page);
  const touch = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map(([x, y, id]) => ({ x, y, id })) });
  const st = () => evalJs('(() => { const s = __ED.rpg.state(); return { x: +s.hero.x.toFixed(2), z: +s.hero.z.toFixed(2), state: s.hero.state, attack: s.hero.attack, cam: s.camera && +s.camera.yaw.toFixed(2) }; })()');
  const a = await st();
  await touch('touchStart', [[150, 300, 1]]); await touch('touchMove', [[150, 230, 1]]);
  await advance(1.0);
  const b = await st();
  await shot('stick');
  await touch('touchEnd', []);
  await advance(0.3);
  await touch('touchStart', [[500, 150, 2]]); await touch('touchMove', [[600, 150, 2]]); await advance(0.2); await touch('touchEnd', []);
  await advance(0.2);
  const c = await st();
  await touch('touchStart', [[783, 314, 3]]); await advance(0.1); await touch('touchEnd', []);
  await advance(0.15);
  const d = await st();
  await shot('light');
  log(JSON.stringify({ a, b, c, d }));
  log((Math.hypot(b.x - a.x, b.z - a.z) > 1 ? 'PASS' : 'FAIL') + ' stick moves the hero');
  log((c.cam !== b.cam ? 'PASS' : 'FAIL') + ' drag turns the camera');
  log((d.state === 'attack' ? 'PASS' : 'FAIL') + ' the light seal attacks');
};
