// Smoke test of the fighter content API: injects a `present` table at runtime, forces moves and checks that every
// handler ran with a working helper. node tools/shot.mjs game --scenario src/game/tests/api.mjs --out shots/game/api
export default async ({ evalJs, advance, shot, log }) => {
  const A = (c) => evalJs(c);
  await A("__ED.game.start('kael', 'iska', { mode: 'demo', seed: 2 })");
  await A("__ED.game.skipIntro()");
  await A(`(() => {
    const calls = window.__apiCalls = [];
    const s = __ED.game.session();
    const heavy = __ED.game.moveFor(0, 'heavy'), ult = __ED.game.moveFor(0, 'ult');
    s.fighters[0].present = {
      moves: {
        heavy: {   // keyed by slot: resolves to the heavy move whatever its id
          start(h) { calls.push('start:' + h.move); h.glow(h.color('mid', 0.3), 1, 0.4); },
          swing(h) { calls.push('swing'); h.fx('game.cast', 'weaponTip'); h.cam.kick({ fov: -2 }); h.trail.start({ life: 0.2 }); h.after(0.2, (h2) => { calls.push('after'); h2.trail.stop(); }); },
          hit(h, e) { calls.push('hit:' + e.level); h.fx('game.finisher', { pos: 'contact', dir: [1, 0.2, 0.3] }); h.post.radial('contact', 0.5); h.audio('hit_crit'); return false; },
          end(h, e) { calls.push('end:' + e.reason); },
          options: { whoosh: 'swing_huge' },
        },
      },
      ult: {
        mood: { darken: 0.8, tint: 0xff4010 },
        freeze(h) { calls.push('freeze'); },
        shots: (h) => [h.shots.impactPunchIn({ dur: 0.6 }), h.shots.orbitSweep({ dur: 2.2, cut: 0.2 }), h.shots.wideEstablishing({ dur: 3 })],
        at: [{ t: 0.3, do(h) { calls.push('at0.3'); h.play(h.self.actor.clips.move(h.move || '${'${ult}'}').name); h.foeOffset([-0.3, 0.6], 0.3); } }, { t: 1.5, do(h) { calls.push('at1.5'); h.foeOffset([0, 0], 0.3); } }],
        tick(h, e) { calls.push('tick' + (e.final ? ':final' : '')); },
        end(h) { calls.push('ultEnd'); },
      },
      on: { ko(h) { calls.push('ko'); } },
    };
    __ED.game.controller(0, 'idle'); __ED.game.controller(1, 'idle');
    __ED.game.place(0, -1.0, 1); __ED.game.place(1, 0.9, -1);
    return heavy + ' / ' + ult;
  })()`).then((r) => log('moves', r));
  await advance(1.1);
  await A("__ED.game.forceMove(0, __ED.game.moveFor(0, 'heavy'))");
  await advance(0.36); await shot('heavy_hit');
  await advance(1.2);
  await A("__ED.game.place(0, -1.6, 1); __ED.game.place(1, 0.6, -1); __ED.game.meters(0, { ult: 100 }); __ED.game.forceMove(0, __ED.game.moveFor(0, 'ult'))");
  await advance(2.0); await shot('ult_lock');
  await advance(5.5);
  log('calls', JSON.stringify(await A('window.__apiCalls')));
  log('cam', await A('__ED.ctx.cam.mode'), 'mood', JSON.stringify(await A('__ED.ctx.env.mood && { darken: __ED.ctx.env.mood.darken }')));
};
