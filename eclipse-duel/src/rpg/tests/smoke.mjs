// RPG smoke test: every hero boots in the sandbox (one training husk), walks, sprints, rolls, guards, does the full
// light chain, the heavy, the sprint attack, the post-roll attack, each skill, the ultimate (full lock on the dummy),
// drinks, dies and respawns; then the expedition flow is walked once with the bot. Prints PASS / FAIL per check.
//
//   node tools/shot.mjs game --as rpg-core --size 640x360 --scenario src/rpg/tests/smoke.mjs
//   HEROES=kael SHOTS=1 node tools/shot.mjs game --as rpg-core --size 960x540 --scenario src/rpg/tests/smoke.mjs --out shots/rpg/core/smoke

export default async ({ evalJs, advance, shot, log }) => {
  const heroes = (process.env.HEROES || 'kael,iska,vorn').split(',');
  const shots = !!process.env.SHOTS;
  let pass = 0, fail = 0;
  const check = (name, ok, info = '') => { if (ok) pass++; else fail++; log(`${ok ? 'PASS' : 'FAIL'} ${name}${info ? '  ' + info : ''}`); };
  const st = () => evalJs('__ED.rpg.state()');
  const R = (code) => evalJs(code);
  /** advance until pred(state) or timeout; returns the last state and whether it matched */
  const until = async (pred, max = 3, step = 1 / 30) => {
    let s = await st();
    for (let t = 0; t < max && !pred(s); t += step) { await advance(step); s = await st(); }
    return s;
  };
  /** states / attack ids seen while advancing `sec` */
  const watch = async (sec, step = 1 / 30) => {
    const seen = { states: new Set(), attacks: [], gaits: new Set(), last: null, minFoeHp: 1e9, lock: false, cine: false };
    for (let t = 0; t < sec; t += step) {
      await advance(step);
      const s = await st();
      seen.states.add(s.hero.state); seen.gaits.add(s.hero.gait);
      if (s.hero.attack && seen.attacks[seen.attacks.length - 1] !== s.hero.attack) seen.attacks.push(s.hero.attack);
      if (s.lock !== null) seen.lock = true;
      if (s.camera.cine) seen.cine = true;
      for (const f of s.foes) seen.minFoeHp = Math.min(seen.minFoeHp, f.hp);
      seen.last = s;
    }
    return seen;
  };
  const reset = async () => {
    // the dummy stands at the edge of the hero's first light (its reach differs per weapon)
    await R('(() => { const r = __ED.rpg; r.move(0, 0); r.tp(0, 0, 0); r.give({ hp: true, fp: true, stamina: true, cooldowns: true, ult: 0 }); const w = r.world(); const d = w.hero.spec.reach + 0.5; for (const a of w.actors) if (a.kind === "dummy") { a.teleport(d, 0, Math.PI); a.hp = a.hpMax; a.setState("idle"); } r.lock(true); })()');
    await advance(0.2);
  };
  const foeHp = async () => (await st()).foes.reduce((m, f) => Math.min(m, f.hp), 1e9);

  for (const hero of heroes) {
    log(`---- ${hero} ----`);
    let s = await R(`__ED.rpg.start('${hero}', { sandbox: true })`);
    await advance(0.4);
    s = await st();
    check(`${hero} boots`, s.mode === 'play' && s.hero && s.hero.id === hero && s.foes.length === 1, JSON.stringify({ mode: s.mode, state: s.hero && s.hero.state, foes: s.foes.length }));
    const info0 = await R('__ED.rpg.checks()');
    check(`${hero} invariants at start`, info0.ok, info0.bad.join('; '));

    // walk / run (camera-relative forward = +X at start)
    await R('__ED.rpg.lock(null); __ED.rpg.tp(-6, 0, 0); __ED.rpg.move(0, 1)');
    let w = await watch(1.0);
    check(`${hero} runs`, w.states.has('move') && w.last.hero.x > -6 + 2.5 && w.gaits.has('run'), `x ${w.last.hero.x} speed ${w.last.hero.speed}`);
    if (shots) await shot(`${hero}_run`);
    // sprint (hold dodge)
    await R('__ED.rpg.press("dodge", 1.2)');
    w = await watch(1.0);
    check(`${hero} sprints`, w.gaits.has('sprint'), `speed ${w.last.hero.speed} stamina ${w.last.hero.stamina}`);
    // sprint attack: heavy while sprinting -> the f+heavy move
    await R('__ED.rpg.press("heavy", 0.05)');
    w = await watch(1.2);
    const slots = await R('__ED.rpg.world().hero.spec.slots');
    check(`${hero} sprint attack`, w.attacks.includes(slots.fheavy), `attacks ${w.attacks.join(',')} want ${slots.fheavy}`);
    await R('__ED.rpg.move(0, 0)');
    s = await until((x) => x.hero.state === 'idle', 2.5);
    check(`${hero} stops`, s.hero.state === 'idle', s.hero.state);

    // roll (tap dodge while moving), then the post-roll attack (heavy right after)
    await R('__ED.rpg.give({ stamina: true }); __ED.rpg.tp(-6, 0, 0); __ED.rpg.move(0, 1); __ED.rpg.press("dodge", 0.05)');
    w = await watch(0.5);
    check(`${hero} rolls`, w.states.has('roll'), [...w.states].join(','));
    if (shots) await shot(`${hero}_roll`);
    await R('__ED.rpg.move(0, 0)');
    s = await until((x) => x.hero.state !== 'roll', 1.5);
    await R('__ED.rpg.press("heavy", 0.05)');
    w = await watch(1.0);
    check(`${hero} post-roll attack`, w.attacks.includes(slots.dheavy), `attacks ${w.attacks.join(',')} want ${slots.dheavy}`);
    await until((x) => x.hero.state === 'idle', 2.5);
    // backstep (dodge with no direction)
    await R('__ED.rpg.give({ stamina: true }); __ED.rpg.press("dodge", 0.05)');
    w = await watch(0.4);
    check(`${hero} backsteps`, w.states.has('roll'), [...w.states].join(','));
    await until((x) => x.hero.state === 'idle', 2);

    // guard
    await R('__ED.rpg.press("guard", 0.5)');
    w = await watch(0.4);
    check(`${hero} guards`, w.states.has('guard'), [...w.states].join(','));
    await until((x) => x.hero.state === 'idle', 1.5);

    // light chain on the dummy
    await reset();
    let hp0 = await foeHp();
    const seen = [];
    // mash light: the presses are buffered and chained through the fighter's own cancel windows
    for (let i = 0; i < 7; i++) {
      await R('__ED.rpg.press("light", 0.05)');
      const ww = await watch(0.17);
      for (const a of ww.attacks) if (!seen.includes(a)) seen.push(a);
      if (seen.length >= 3) break;
    }
    w = await watch(1.2);
    for (const a of w.attacks) if (!seen.includes(a)) seen.push(a);
    let hp1 = await foeHp();
    check(`${hero} light chain`, seen.includes(slots.light1) && seen.includes(slots.light2) && seen.includes(slots.light3), `saw ${seen.join(',')}`);
    check(`${hero} light chain hits`, hp1 < hp0, `dummy ${hp0} -> ${hp1}`);
    if (shots) await shot(`${hero}_chain`);
    await until((x) => x.hero.state === 'idle', 2.5);

    // heavy
    await reset();
    hp0 = await foeHp();
    await R('__ED.rpg.press("heavy", 0.05)');
    w = await watch(1.4);
    check(`${hero} heavy`, w.attacks.includes(slots.heavy) && w.minFoeHp < hp0, `attacks ${w.attacks.join(',')} dummy ${hp0} -> ${w.minFoeHp}`);
    await until((x) => x.hero.state === 'idle', 2.5);

    // skills
    for (const slot of ['skill1', 'skill2', 'skill3']) {
      await reset();
      hp0 = await foeHp();
      const fp0 = (await st()).hero.fp;
      await R(`__ED.rpg.press("${slot}", 0.05)`);
      w = await watch(2.2);
      const fp1 = w.last.hero.fp;
      check(`${hero} ${slot} starts`, w.attacks.includes(slots[slot]), `attacks ${w.attacks.join(',')} want ${slots[slot]}`);
      check(`${hero} ${slot} costs FP`, fp1 < fp0, `${fp0} -> ${fp1}`);
      // counters / dodge-attacks do no damage on an idle dummy; everything else must
      const isCounter = await R(`!!__ED.rpg.world().hero.spec.attacks["${slots[slot]}"].counter`);
      if (!isCounter) check(`${hero} ${slot} hits`, w.minFoeHp < hp0, `dummy ${hp0} -> ${w.minFoeHp}`);
      if (shots) await shot(`${hero}_${slot}`);
      await until((x) => x.hero.state === 'idle', 3);
    }

    // ultimate: super-freeze, opener, the full lock on the dummy
    await reset();
    await R('__ED.rpg.give({ ult: true })');
    hp0 = await foeHp();
    await R('__ED.rpg.press("ult", 0.05)');
    w = await watch(9);
    check(`${hero} ult starts`, w.attacks.includes(slots.ult), `attacks ${w.attacks.join(',')}`);
    check(`${hero} ult locks`, w.lock && w.cine, `lock ${w.lock} cine ${w.cine}`);
    check(`${hero} ult damage`, w.minFoeHp < hp0 - 300, `dummy ${hp0} -> ${w.minFoeHp}`);
    s = await until((x) => x.hero.state === 'idle' && x.lock === null && !x.camera.cine, 4);
    check(`${hero} ult ends clean`, s.hero.state === 'idle' && s.lock === null && !s.camera.cine && s.mode === 'play', JSON.stringify({ st: s.hero.state, lock: s.lock, cine: s.camera.cine, mode: s.mode }));
    check(`${hero} ult spent`, s.hero.ult < 50, `ult ${s.hero.ult}`);

    // chalice
    await reset();
    await R('__ED.rpg.lock(null); __ED.rpg.tp(-8, 0, 0); __ED.rpg.hurt(400)');
    await until((x) => x.hero.state === 'idle', 3);
    const h0 = (await st()).hero.hp;
    await R('__ED.rpg.give({ chalice: 3 }); __ED.rpg.press("chalice", 0.05)');
    w = await watch(1.8);
    check(`${hero} drinks`, w.states.has('drink') && w.last.hero.hp > h0 && w.last.hero.chalice === 2, `hp ${h0} -> ${w.last.hero.hp} chalice ${w.last.hero.chalice}`);

    // death and respawn
    await R('__ED.rpg.hurt(99999, "heavy")');
    await advance(0.3);
    s = await st();
    check(`${hero} dies`, s.mode === 'dead' && s.hero.state === 'dead', `${s.mode} ${s.hero.state}`);
    if (shots) await shot(`${hero}_dead`);
    s = await until((x) => x.mode === 'play' && x.hero.state !== 'dead', 6, 0.1);
    check(`${hero} respawns`, s.mode === 'play' && s.hero.hp === s.hero.hpMax, `${s.mode} hp ${s.hero.hp}/${s.hero.hpMax}`);
    const info1 = await R('__ED.rpg.checks()');
    check(`${hero} invariants at end`, info1.ok, info1.bad.join('; '));
  }

  // systems (first hero): lock-on and switching, guard / perfect guard / roll through a blow, camera vs the wall,
  // pause, the ultimate strike on a boss
  if (!process.env.NOSYSTEMS) {
    const hero = heroes[0];
    log('---- systems ----');
    await R(`__ED.rpg.start('${hero}', { sandbox: true })`);
    await R('window.__ev = {}; __ED.rpg.world().on("*", (e, name) => { window.__ev[name] = (window.__ev[name] || 0) + 1; }); __ED.rpg.clear()');
    const ev = async (name) => (await R(`window.__ev["${name}"] || 0`));
    const still = 'const a = __ED.rpg.world().byId(id); a.controller = null;';
    const ids = await R(`(() => { const r = __ED.rpg; r.tp(0, 0, 0); const out = []; for (const z of [-2.2, 2.2]) { const id = r.spawn('husk', 5, z, { spawnTime: 0 }); ${still} out.push(id); } return out; })()`);
    await advance(0.3);
    const l1 = await R('__ED.rpg.lock(true)');
    check('lock-on picks a target', ids.includes(l1), `locked ${l1} of ${ids}`);
    await R('__ED.rpg.press("lockR", 0.05)');
    await advance(0.2);
    let s = await st();
    check('lock switches target', ids.includes(s.camera.lock) && s.camera.lock !== l1, `lock ${l1} -> ${s.camera.lock}`);
    await R(`__ED.rpg.kill(${s.camera.lock})`);
    await advance(0.5);
    s = await st();
    check('lock releases a dead target', s.camera.lock !== ids.find((x) => x !== l1) || s.camera.lock === 0 || s.camera.lock === l1, `lock ${s.camera.lock}`);

    // a husk swings at the hero three times: blocked, perfectly guarded, rolled through
    const swing = async () => {
      await R(`(() => { const r = __ED.rpg, w = r.world(); r.clear(); r.move(0, 0); r.tp(0, 0, 0); r.give({ hp: true, stamina: true }); const id = r.spawn('husk', 1.9, 0, { spawnTime: 0, yaw: Math.PI }); ${still} r.lock(id); a.startAttack('slash', { force: true, target: w.hero }); })()`);
    };
    await swing();
    await R('__ED.rpg.press("guard", 1.2)');
    let hp0 = (await st()).hero.hp;
    let g0 = await ev('guard');
    await advance(1.1);
    s = await st();
    check('guard blocks', (await ev('guard')) > g0 && s.hero.hp > hp0 - 20, `guard events ${await ev('guard')} hp ${hp0} -> ${s.hero.hp} stamina ${s.hero.stamina}`);
    await until((x) => x.hero.state === 'idle', 2);
    await swing();
    await advance(0.52);                      // the slash is active from 0.62 s: raise the guard just before it
    await R('__ED.rpg.press("guard", 0.5)');
    const p0 = await ev('perfectGuard');
    await advance(0.5);
    s = await st();
    check('perfect guard', (await ev('perfectGuard')) > p0 && s.foes[0] && s.foes[0].state === 'stagger', `events ${await ev('perfectGuard')} foe ${s.foes[0] && s.foes[0].state}`);
    await until((x) => x.hero.state === 'idle', 2);
    await swing();
    await advance(0.5);
    hp0 = (await st()).hero.hp;
    const d0 = await ev('dodge');
    await R('__ED.rpg.move(0.3, 1); __ED.rpg.press("dodge", 0.05)');
    await advance(0.6);
    await R('__ED.rpg.move(0, 0)');
    s = await st();
    check('roll passes through a blow', (await ev('dodge')) > d0 && s.hero.hp === hp0, `dodge events ${await ev('dodge')} hp ${hp0} -> ${s.hero.hp}`);
    await until((x) => x.hero.state === 'idle', 2);
    await swing();
    hp0 = (await st()).hero.hp;
    await advance(1.0);
    s = await st();
    check('an unguarded blow lands', s.hero.hp < hp0 && (await ev('hit')) > 0, `hp ${hp0} -> ${s.hero.hp} state ${s.hero.state}`);
    await until((x) => x.hero.state === 'idle', 3);

    // camera boom against the arena wall
    await R('__ED.rpg.clear(); __ED.rpg.lock(null); __ED.rpg.tp(-14.7, 0, 0)');
    await advance(0.6);
    s = await st();
    const camR = await R('Math.hypot(__ED.ctx.camera.position.x, __ED.ctx.camera.position.z)');
    check('camera stays inside the wall', s.camera.dist < 2.2 && camR < 15.6, `boom ${s.camera.dist} m, camera radius ${camR.toFixed(2)}`);

    // pause
    await R('__ED.rpg.pause()');
    const t0 = (await st()).time;
    await advance(0.5);
    s = await st();
    check('pause freezes the world', s.mode === 'pause' && s.time === t0, `${s.mode} time ${t0} -> ${s.time}`);
    await R('__ED.rpg.resume()');
    await advance(0.3);
    s = await st();
    check('resume', s.mode === 'play' && s.time > t0, `${s.mode} time ${s.time}`);

    // the ultimate on a boss: no lock, one burst with the lock's total damage
    const bid = await R(`(() => { const r = __ED.rpg; r.clear(); r.tp(0, 0, 0); const id = r.spawn('standin.boss', 4.6, 0, { spawnTime: 0, yaw: Math.PI }); ${still} r.lock(id); r.give({ ult: true, hp: true, stamina: true }); return id; })()`);
    await advance(0.4);
    const b0 = (await st()).foes.find((f) => f.id === bid).hp;
    await R('__ED.rpg.press("ult", 0.05)');
    const w = await watch(5);
    s = await until((x) => x.mode === 'play' && x.hero.state === 'idle' && !x.camera.cine, 5);
    const b1 = s.foes.find((f) => f.id === bid);
    check('ultimate strike on a boss: no lock', !w.lock, `lock ${w.lock}`);
    check('ultimate strike damage', b1 && b0 - b1.hp > 350, `boss ${b0} -> ${b1 && b1.hp}`);
    check('ultimate strike ends clean', s.mode === 'play' && !s.camera.cine && s.hero.state === 'idle', `${s.mode} ${s.hero.state} cine ${s.camera.cine}`);
    const info = await R('__ED.rpg.checks()');
    check('systems invariants', info.ok, info.bad.join('; '));
  }

  // the expedition once with the bot (first hero): altar -> gate -> first encounter starts
  if (!process.env.NOFLOW) {
    log('---- flow ----');
    await R(`__ED.rpg.start('${heroes[0]}', { bot: true })`);
    await R('__ED.rpg.god(true)');
    let s = await st();
    check('flow starts at the altar', s.flow === 'altar', s.flow);
    await evalJs('__ED.render()');
    const prog0 = (await R('__ED.info()')).programs;
    s = await until((x) => x.flow === 'encounter' && x.foes.length >= 3, 24, 0.25);
    check('flow reaches the first encounter', s.flow === 'encounter' && s.foes.length > 0, `${s.flow} foes ${s.foes.length}`);
    await advance(0.5);
    await evalJs('__ED.render()');
    const prog1 = (await R('__ED.info()')).programs;
    check('no program compiled when the encounter spawned', prog1 === prog0, `programs ${prog0} -> ${prog1}`);
    if (shots) await shot('flow_encounter');
    s = await until((x) => x.flow === 'explore' || x.flow === 'boss' || (x.encounter && x.encounter !== s.encounter), 120, 0.5);
    check('bot clears the first encounter', s.flow !== 'encounter' || s.encounter !== 'standin.husks', `${s.flow} ${s.encounter} t ${s.time}`);
    await R('__ED.rpg.stop()');
    await advance(0.5);
    const g = await evalJs('__ED.game.state');
    check('back at the title', g === 'title', g);
  }
  log(`RESULT ${pass} passed, ${fail} failed`);
};
