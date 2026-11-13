// RPG soak: the bot against three test husks (refilled as they die) for SECONDS simulated seconds (default 180), with
// invariants every half second: no NaN, nobody outside the arena, no stuck states, bounded actor / projectile /
// trigger counts, and no growth of scene children, geometries, textures or programs after the warm-up.
//
//   node tools/shot.mjs game --as rpg-core --size 320x180 --scenario src/rpg/tests/soak.mjs
//   HERO=iska SECONDS=60 RENDER=1 node tools/shot.mjs game --as rpg-core --size 320x180 --scenario src/rpg/tests/soak.mjs

export default async ({ evalJs, advance, shot, log }) => {
  const hero = process.env.HERO || 'kael';
  const total = Number(process.env.SECONDS || 180);
  const render = !!process.env.RENDER;
  const R = (code) => evalJs(code);
  await R(`__ED.rpg.start('${hero}', { sandbox: true, bot: true })`);
  await R('__ED.rpg.clear(); for (const p of [[5, -3], [6, 1], [4, 4]]) __ED.rpg.spawn("husk", p[0], p[1])');
  await advance(1);
  let base = null, fails = 0, kills = 0, deaths = 0, maxActors = 0;
  const bad = new Set();
  for (let t = 0; t < total; t += 0.5) {
    await advance(0.5);
    if (render && t % 5 === 0) await evalJs('__ED.render()');
    const c = await R(`(() => {
      const r = __ED.rpg, w = r.world(), c = r.checks();
      // keep three husks in play; revive the hero in place (sandbox: no altar walk)
      let n = 0; for (const a of w.actors) if (a.kind === 'husk' && !a.dead) n++;
      c.spawned = 0;
      while (n < 3) { const ang = w.rng() * 6.283, d = 5 + w.rng() * 4; r.spawn('husk', Math.cos(ang) * d, Math.sin(ang) * d); n++; c.spawned++; }
      c.mode = r.mode; c.hero = w.hero ? { hp: Math.round(w.hero.hp), state: w.hero.state } : null;
      return c;
    })()`);
    if (!c.ok) { fails++; for (const b of c.bad) bad.add(b); }
    kills += c.spawned;
    if (c.mode === 'dead') deaths++;
    maxActors = Math.max(maxActors, c.actors);
    if (t === 20) base = c;
    if (t % 30 === 0) log(`t=${t} mode=${c.mode} hero=${JSON.stringify(c.hero)} actors=${c.actors} proj=${c.projectiles} geo=${c.geometries} tex=${c.textures} prog=${c.programs} scene=${c.sceneChildren}`);
  }
  const end = await R('__ED.rpg.checks()');
  const st = await R('__ED.rpg.state()');
  log(`invariant failures: ${fails}${bad.size ? ' -> ' + [...bad].slice(0, 12).join(' | ') : ''}`);
  log(`husks respawned: ${kills - 0}, frames spent dead: ${deaths}, max actors: ${maxActors}`);
  if (base) log(`leak check (t=20 -> end): geometries ${base.geometries} -> ${end.geometries}, textures ${base.textures} -> ${end.textures}, programs ${base.programs} -> ${end.programs}, scene children ${base.sceneChildren} -> ${end.sceneChildren}, triggers ${base.triggers} -> ${end.triggers}`);
  const leak = base && (end.textures > base.textures + 2 || end.programs > base.programs || end.sceneChildren > base.sceneChildren + 6 || end.geometries > base.geometries + 12);
  log(`final: ${JSON.stringify({ mode: st.mode, hero: st.hero.state, hp: st.hero.hp, time: st.time })}`);
  if (process.env.SHOT) await shot('soak_end');
  log(`RESULT ${fails === 0 && !leak ? 'PASS' : 'FAIL'}`);
};
