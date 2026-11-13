// Contact sheets of one hero from the third-person camera (sandbox, locked training husk):
//   circle   running in a circle around the locked dummy (feet planted, camera stable)
//   roll     rolling through an attack (a husk swings, the hero rolls through it)
//   chain    the light chain
//   heavy, skill1, skill2, skill3, ult
//   rest / drink / death
//
//   HERO=kael SECTIONS=circle,chain node tools/shot.mjs game --as rpg-core --size 960x540 --scenario src/rpg/tests/sheets.mjs --sheet 4 --sheet-only --out shots/rpg/core/kael
// One sheet per run: pick SECTIONS (default: circle).

export default async ({ evalJs, advance, shot, log }) => {
  const hero = process.env.HERO || 'kael';
  const sections = (process.env.SECTIONS || 'circle').split(',');
  const R = (code) => evalJs(code);
  const frames = async (label, times) => {
    let t = 0;
    for (const x of times) { if (x > t) { await advance(x - t); t = x; } await shot(`${label}_${x.toFixed(2)}`); }
  };
  await R(`__ED.rpg.start('${hero}', { sandbox: true })`);
  await R('__ED.rpg.god(true)');
  await advance(0.5);
  const reset = async (dist = 2.3) => {
    await R(`(() => { const r = __ED.rpg; r.move(0, 0); r.tp(0, 0, 0); r.give({ hp: true, fp: true, stamina: true, cooldowns: true, ult: 0 }); const w = r.world(); for (const a of w.actors) if (a.kind === "dummy") { a.teleport(${dist}, 0, Math.PI); a.hp = a.hpMax; a.setState("idle"); } r.lock(true); })()`);
    await advance(0.6);
  };
  for (const sec of sections) {
    log('section ' + sec);
    if (sec === 'circle') {
      await reset(4);
      // strafe input while locked = a circle around the target (turn-to-move: the hero runs along the tangent)
      await R('__ED.rpg.move(1, 0.12)');
      await frames('circle', [0.5, 0.7, 0.9, 1.1, 1.3, 1.5, 1.7, 1.9, 2.4, 2.9, 3.4, 3.9]);
      const s = await R('__ED.rpg.state()');
      log('circle: hero ' + JSON.stringify({ x: s.hero.x, z: s.hero.z, speed: s.hero.speed, gait: s.hero.gait }) + ' cam ' + JSON.stringify(s.camera));
      await R('__ED.rpg.move(0, 0)');
    } else if (sec === 'sprint') {
      await R('__ED.rpg.lock(null); __ED.rpg.tp(-9, 0, 0); __ED.rpg.move(0, 1); __ED.rpg.press("dodge", 3)');
      await frames('sprint', [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2]);
      await R('__ED.rpg.move(0, 0)');
    } else if (sec === 'roll') {
      // a husk swings at the hero; the hero rolls through the blow
      await R('(() => { const r = __ED.rpg; r.clear(); r.tp(0, 0, 0); const id = r.spawn("husk", 2.1, 0, { spawnTime: 0 }); r.lock(id); const a = r.world().byId(id); a.controller = null; a.yaw = Math.PI; a.startAttack("slash", { force: true, target: r.world().hero }); })()');
      await advance(0.44);
      await R('__ED.rpg.move(0.25, 1); __ED.rpg.press("dodge", 0.05)');
      await frames('roll', [0.1, 0.16, 0.22, 0.28, 0.34, 0.4, 0.46, 0.52, 0.6, 0.7, 0.8, 0.95]);
      const s = await R('__ED.rpg.state()');
      log('roll: hero hp ' + s.hero.hp + '/' + s.hero.hpMax + ' state ' + s.hero.state);
      await R('__ED.rpg.move(0, 0); __ED.rpg.clear(); __ED.rpg.spawn("dummy", 4, 0)');
    } else if (sec === 'chain') {
      await reset();
      const T = [];
      for (let i = 0; i < 3; i++) {
        await R('__ED.rpg.press("light", 0.05)');
        for (const x of [0.1, 0.17, 0.24, 0.31]) { await advance(x - (T.length % 4 === 0 ? 0 : [0.1, 0.17, 0.24, 0.31][(T.length % 4) - 1])); T.push(x); await shot(`chain${i + 1}_${x.toFixed(2)}`); }
      }
    } else if (sec === 'heavy' || sec === 'skill1' || sec === 'skill2' || sec === 'skill3') {
      await reset(sec === 'skill1' ? 4.5 : sec === 'skill2' ? 3.5 : 2.3);
      await R(`__ED.rpg.press("${sec}", 0.05)`);
      await frames(sec, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.75, 0.9, 1.05, 1.2, 1.4, 1.7]);
    } else if (sec === 'ult') {
      await reset();
      await R('__ED.rpg.give({ ult: true }); __ED.rpg.press("ult", 0.05)');
      await frames('ult', [0.3, 0.7, 1.0, 1.3, 1.7, 2.2, 2.8, 3.4, 4.0, 4.6, 5.4, 6.4, 7.2, 8.0, 8.8, 9.6]);
      const s = await R('__ED.rpg.state()');
      log('ult: ' + JSON.stringify({ mode: s.mode, hero: s.hero.state, lock: s.lock, foe: s.foes[0] }));
    } else if (sec === 'misc') {
      await R('__ED.rpg.lock(null); __ED.rpg.tp(-6, 0, 0.6); __ED.rpg.hurt(300)');
      await advance(1.2);
      await R('__ED.rpg.give({ chalice: 3 }); __ED.rpg.press("chalice", 0.05)');
      await frames('drink', [0.25, 0.6, 0.95, 1.3]);
      await advance(0.6);
      await R('__ED.rpg.world().flow.resting = true; __ED.rpg.world().hero.setState("rest")');
      await frames('rest', [0.6, 2.2]);
      await R('__ED.rpg.world().flow.resting = false; __ED.rpg.world().hero.setState("idle"); __ED.rpg.god(false)');
      await advance(0.5);
      await R('__ED.rpg.hurt(99999, "heavy")');
      await frames('death', [0.15, 0.45, 0.8, 1.3, 1.9, 2.6]);
    }
  }
};
