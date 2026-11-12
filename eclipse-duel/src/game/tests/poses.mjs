// Contact sheet of the generic fallback clips on fighter 0: node tools/shot.mjs game --scenario src/game/tests/poses.mjs --sheet --sheet-only --out shots/game/poses
// CLIPS env var: comma list of clip:time (default: every game.* clip at a telling time).
export default async ({ evalJs, advance, shot }) => {
  const list = String(process.env.CLIPS || 'game.intro:0,game.intro:1.35,game.walkF:0.1,game.dash:0.12,game.backstep:0.1,game.dodge:0.2,game.hitLight:0.06,demo.hit:0.08,game.crumple:0.9,game.guardbreak:0.12,game.airRise:0.2,game.airFall:0.2,game.down:0.5,game.getup:0.2,game.koDown:0.5,game.victory:1.2,game.defeat:1.3,game.locked:0.2').split(',');
  await evalJs("__ED.game.start('kael', 'iska', { mode: 'demo', seed: 1 })");
  await evalJs("__ED.game.skipIntro()");
  await evalJs("__ED.game.controller(0, 'idle'); __ED.game.controller(1, 'idle'); __ED.game.place(0, -1.5, 1); __ED.game.place(1, 3.5, -1)");
  await advance(1.2);
  await evalJs("__ED.ctx.cam.setMode('free', 0)");
  for (const item of list) {
    const [clip, t] = item.split(':');
    await evalJs(`__ED.game.pose(0, '${clip}', ${Number(t) || 0})`);
    await advance(0.1);
    await evalJs(`(() => { const c = __ED.ctx.camera; c.position.set(-0.6, 1.25, 4.6); c.fov = 34; c.updateProjectionMatrix(); c.lookAt(-1.4, 0.85, 0); c.updateMatrixWorld(); })()`);
    await shot(clip.replace(/\./g, '_') + '_' + (Number(t) || 0).toFixed(2));
  }
};
