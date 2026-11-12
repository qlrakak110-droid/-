// End-to-end keyboard flow: title -> select -> vs -> match (P1 human walks and attacks) -> pause -> resume.
// node tools/shot.mjs game --scenario src/game/tests/flow.mjs --out shots/game/flow
export default async ({ page, evalJs, advance, shot, log }) => {
  const key = async (code, hold = 0.05) => { await page.keyboard.down(code); await advance(hold); await page.keyboard.up(code); await advance(0.12); };
  const st = () => evalJs('[__ED.game.state, __ED.game.screen]');
  log('boot', JSON.stringify(await st()));
  await key('Enter'); await advance(0.4);
  log('after start', JSON.stringify(await st()));
  for (let i = 0; i < 6 && (await evalJs('__ED.game.state')) === 'select'; i++) { await key('Enter'); await advance(0.3); }
  log('after picks', JSON.stringify(await st()));
  await advance(1.0); await shot('vs');
  await advance(3.5);
  log('match', JSON.stringify(await st()), JSON.stringify(await evalJs('__ED.game.snapshot() && __ED.game.snapshot().phase')));
  await advance(2.5);
  await page.keyboard.down('KeyD'); await advance(0.6); await page.keyboard.up('KeyD');
  await key('KeyJ'); await advance(0.2); await key('KeyJ'); await advance(0.3);
  await shot('fight');
  const ev = await evalJs("__ED.game.events().filter((n) => n === 'moveStart' || n === 'hit').length");
  log('p1 x / moves+hits', JSON.stringify(await evalJs('__ED.game.snapshot().fighters[0].x')), ev);
  await key('Escape'); await advance(0.4);
  log('paused', JSON.stringify(await st()), 'baseScale', await evalJs('__ED.ctx.time.baseScale'));
  await shot('pause');
  await key('Escape'); await advance(0.3);
  log('resumed', JSON.stringify(await st()), 'baseScale', await evalJs('__ED.ctx.time.baseScale'));
};
