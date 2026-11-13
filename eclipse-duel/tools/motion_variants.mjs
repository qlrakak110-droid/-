// Variant-system check in the real game (src/fighters/MOTION.md section 4): which clip every slot resolves to for both
// fighters of a training match, and the clip / state sequence that really plays for light, heavy, launch, crumple and
// knockdown hits from the front and from behind, blocked hits, 14 s of idling and a KO.
//   (ONLY=back: just the blows from behind; TESTCLIPS=1: stand-in variant clips for P2, to exercise the selection)
//   P1=kael P2=iska node tools/shot.mjs game --as mm-<label> --size 640x360 --hash q=low --scenario tools/motion_variants.mjs --out shots/murim/motion/<label>/variants
export default async ({ page, evalJs, advance, shot, log }) => {
  const P1 = process.env.P1 || 'kael', P2 = process.env.P2 || 'iska';
  await evalJs(`__ED.game.start('${P1}', '${P2}', { mode: 'training', seed: 7 })`);
  await evalJs(`__ED.game.skipIntro()`);
  await advance(0.3);
  if (process.env.TESTCLIPS) {
    // stand-in variant clips for P2 under the naming convention (copies of its own clips): exercises the selection code
    await evalJs(`(() => { const C = __ED.clips, id = '${P2}', copy = (dst, src, dur) => { const d = C.getClipDef(id + '.' + src); C.defineClip(id + '.' + dst, { ...d, loop: false, duration: dur ?? d.duration }); };
      for (const v of ['hitLightHigh', 'hitLightMid', 'hitLightLow', 'hitLightBack']) copy(v, 'hitLight');
      copy('hitHeavyBack', 'hitHeavy'); copy('guardHit', 'guard', 0.24); copy('guardHitHeavy', 'guard', 0.36);
      copy('idleFidget', 'idle', 1.2); copy('idleFidget2', 'idle', 1.0); copy('turn', 'idle', 0.36); copy('walkStopF', 'idle', 0.3); copy('victory2', 'victory'); })()`);
    await evalJs(`__ED.game.start('${P1}', '${P2}', { mode: 'training', seed: 7 })`);
    await evalJs(`__ED.game.skipIntro()`);
    await advance(0.3);
  }
  const res = await evalJs(`(() => {
    const s = __ED.game.session(); const out = {};
    s.actors.forEach((a, i) => {
      const c = a.clips, slots = ['idle','guard','hitLight','hitLightHigh','hitLightMid','hitLightLow','hitLightBack','hitHeavy','hitHeavyBack','guardHit','guardHitHeavy','crumple','launched','launchedProne','fall','fallProne','down','downProne','getup','getupProne','tech','techProne','ko','koProne','turn','idleFidget','walkStopF','victory','locked','guardBreak'];
      out[a.fighter.id] = { names: c.names().length, slots: Object.fromEntries(slots.map((k) => [k, c.state(k).name + (c.has(k) ? '' : ' (-)')])), victory: c.variants('victory').map((v) => v.name), fidgets: c.variants('idleFidget').map((v) => v.name) };
    });
    return out; })()`);
  log(JSON.stringify(res, null, 1));
  const G = '__ED.game', clipOf = (i) => `${G}.session().actors[${i}].char.clip`;
  const seq = async (label, setup, frames = 40, who = 1) => {
    await evalJs(setup);
    const seen = [];
    for (let k = 0; k < frames; k++) { await advance(1 / 60); const c = await evalJs(`[${clipOf(who)}, ${G}.match().fighters[${who}].state]`); const tag = c.join('|'); if (seen[seen.length - 1] !== tag) seen.push(tag); }
    log(label + ': ' + seen.join(' > '));
  };
  const reset = `${G}.place(0, -1.0, 1); ${G}.place(1, 0.9, -1); ${G}.meters(1, { hp: 900 });`;
  const mv = async (slot) => evalJs(`${G}.moveFor(0, '${slot}')`);
  const only = process.env.ONLY || '';
  for (const slot of only ? [] : ['light1', 'heavy', 'dheavy', 'fheavy', 'light3']) {
    await evalJs(reset); await advance(1.2);
    const id = await mv(slot);
    await seq(`P1 ${slot} (${id}) -> P2`, `${G}.forceMove(0, '${id}')`, slot === 'light1' ? 50 : 200);
  }
  // from behind: P2 is busy in a long move of its own (an idle fighter turns round before the blow lands)
  const busy = await evalJs(`${G}.moveFor(1, 'skill2')`);
  for (const slot of ['light1', 'heavy', 'dheavy']) {
    await evalJs(reset); await advance(1.0);
    // P2 commits to its move facing P1, then P1 is put on its far side (a cross-up) and strikes
    await evalJs(`${G}.forceMove(1, '${busy}')`); await advance(0.1);
    await evalJs(`${G}.place(0, 2.7, -1)`);
    await seq(`P1 ${slot} from behind -> P2 (in ${busy})`, `${G}.forceMove(0, '${await mv(slot)}')`, slot === 'dheavy' ? 240 : 80);
  }
  if (only === 'back') return;
  // guard
  await evalJs(reset + `${G}.controller(1, 'human'); __ED.ctx.input.setVirtual('guard', true, 1);`); await advance(0.5);
  await seq('P1 light1 -> P2 guarding', `${G}.forceMove(0, '${await mv('light1')}')`, 60);
  await seq('P1 heavy -> P2 guarding', `${G}.forceMove(0, '${await mv('heavy')}')`, 90);
  await evalJs(`__ED.ctx.input.setVirtual('guard', false, 1); ${G}.controller(1, 'idle');`);
  // idle life
  await evalJs(reset); await advance(0.5);
  await seq('P2 idle for 14 s', `0`, 840);
  // the opponent crosses over: P2 turns round
  await seq('P1 placed behind P2 (turn)', `${G}.place(0, 2.4, -1)`, 60);
  // victory
  await seq('KO -> P1 victory', `${G}.meters(1, { hp: 1 }); ${G}.forceMove(0, '${await mv('light1')}')`, 420, 0);
  await shot('end');
};
