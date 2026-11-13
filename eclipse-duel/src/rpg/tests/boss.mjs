// Contact sheets of the boss 「흑일마신상」 from the third-person camera.
//   SECTION=intro | sweep | cleave | thrust | stomp | eclipse | combo | enrage | kneel | death | fight
//   HERO=kael DIST=5 SIDE=0 node tools/shot.mjs game --as boss --size 960x540 --scenario src/rpg/tests/boss.mjs --sheet 4 --sheet-only --out shots/rpg/boss/sweep
// SIDE=1 looks from the side (free camera) instead of from behind the hero.
import { T } from '../boss/clips.js';

export default async ({ evalJs, advance, shot, log }) => {
  const hero = process.env.HERO || 'kael', sec = process.env.SECTION || 'sweep', dist = +(process.env.DIST || 5), side = +(process.env.SIDE || 0);
  const R = (code) => evalJs(code);
  const frames = async (label, times) => { let t = 0; for (const x of times) { if (x > t) { await advance(x - t); t = x; } await shot(`${label}_${x.toFixed(2)}`); } };
  await R(`__ED.rpg.start('${hero}', { encounter: 'idol'${sec === 'fight' ? ', bot: true' : ''} })`);
  if (sec === 'intro') { await frames('intro', [0.1, 0.8, 1.6, 2.2, 2.8, 3.4, 4.0, 5.2]); return; }
  if (sec === 'fight') { await frames('fight', (process.env.TIMES || '6,10,14,18,22,26,30,34,38,42,46,50').split(',').map(Number)); log(JSON.stringify(await R('(() => { const s = __ED.rpg.state(); return { hero: s.hero.hp, foes: s.foes, flow: s.flow }; })()'))); return; }
  await R('__ED.rpg.god(true)');
  await advance(T.wake + 1.4);
  // freeze the idol's own mind, stand the hero `dist` m in front of it
  await R(`(() => { const r = __ED.rpg, w = r.world(); const b = w.actors.find((a) => a.kind === 'idol'); b.controller = { think() {} }; b.teleport(4, 0, Math.PI); r.tp(4 - 1.25 - 0.45 - ${dist}, ${side ? 0.01 : 0}, 0); r.lock(true); })()`);
  await advance(0.8);
  if (process.env.CAM) { const c = process.env.CAM.split(',').map(Number); await R(`(() => { const w = __ED.rpg.world(); w.camera.worldShot((t, out) => { out.pos.set(4 - ${c[0]}, ${c[1]}, ${c[2]}); out.look.set(4, ${c[3]}, 0); out.fov = ${c[4] || 40}; }, { dur: 99 }); })()`); }
  if (side) await R(`(() => { const w = __ED.rpg.world(); w.camera.worldShot((t, out) => { out.pos.set(0.5, 3.2, 15); out.look.set(0.5, 2.6, 0); out.fov = 46; }, { dur: 99 }); })()`);
  const B = `__ED.rpg.world().actors.find((a) => a.kind === 'idol')`;
  const times = {
    sweep: [0.3, 0.62, 1.04, 1.14, 1.19, 1.24, 1.29, 1.34, 1.5, 1.8, 2.2, 2.7],
    cleave: [0.3, 0.6, 1.08, 1.3, 1.37, 1.41, 1.45, 1.5, 1.6, 2.0, 2.6, 3.2],
    thrust: [0.3, 0.5, 0.95, 1.02, 1.05, 1.08, 1.12, 1.2, 1.4, 1.8, 2.2, 2.5],
    stomp: [0.3, 0.7, 0.95, 1.0, 1.04, 1.07, 1.12, 1.2, 1.35, 1.6, 2.0, 2.3],
    eclipse: [0.4, 0.8, 1.3, 1.9, 2.06, 2.2, 2.5, 2.9, 3.1, 3.3, 3.6, 4.0],
    combo: [0.5, 0.84, 0.95, 1.03, 1.22, 1.66, 1.8, 1.9, 2.14, 2.76, 2.86, 2.92, 3.0, 3.4, 4.0, 4.5],
    enrage: [0.3, 0.6, 1.3, 1.68, 1.74, 1.8, 1.9, 2.1, 2.4, 2.8, 3.2, 3.6],
    kneel: [0.1, 0.3, 0.75, 0.9, 1.6, 2.4, 2.9, 3.4],
    death: [0.1, 0.4, 1.1, 1.9, 2.1, 3.0, 4.0, 5.0],
    walk: [0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.4, 2.8],
    idle: [0.1, 1.4, 2.6, 3.9],
  }[sec];
  if (sec === 'kneel') await R(`(() => { const w = __ED.rpg.world(), b = ${B}; b.spec.onPoiseBreak(w, b); })()`);
  else if (sec === 'death') await R(`(() => { const b = ${B}; b.hp = 0; b.die(__ED.rpg.world().hero); })()`);
  else if (sec === 'walk') await R(`(() => { const w = __ED.rpg.world(), b = ${B}; b.teleport(10, 0, Math.PI); b.controller = { think(w2, a, dt, it) { it.moveX = -1; it.moveZ = 0; } }; })()`);
  else if (sec !== 'idle') log('started: ' + await R(`(() => { const w = __ED.rpg.world(), b = ${B}; return w.startAttack(b, '${sec}', { target: w.hero, force: true }); })()`));
  await frames(sec, times);
  log(JSON.stringify(await R('(() => { const s = __ED.rpg.state(); return { hero: [s.hero.x, s.hero.z, s.hero.hp, s.hero.state], foes: s.foes }; })()')));
};
